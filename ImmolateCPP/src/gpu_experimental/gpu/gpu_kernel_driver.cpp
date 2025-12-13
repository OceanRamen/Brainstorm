/*
 * GPU Kernel Driver Bridge
 * 
 * Provides CUDA Driver API integration for GPU-accelerated seed searching.
 * Uses runtime PTX compilation for maximum compatibility.
 * Features automatic context management and error recovery.
 */

#include "cuda_driver_loader.h"
#include "gpu_types.h"
#include "seed.hpp"
#include <chrono>
#include <cstdio>
#include <cstring>
#include <string>
#include <thread>
#include <sstream>

// Include the embedded PTX code
#include "seed_filter_ptx.h"

// Global driver API instance
static CudaDrv drv;
static CUmodule mod = nullptr;
static CUfunction fn = nullptr;
static CUcontext ctx = nullptr;
static bool ready = false;

/* 
 * ScopedCtx - RAII wrapper for CUDA context management
 * Ensures context is current for the lifetime of the object
 */
struct ScopedCtx {
    CudaDrv& drv;
    CUcontext ctx;
    bool pushed;
    
    ScopedCtx(CudaDrv& d, CUcontext c) : drv(d), ctx(c), pushed(false) {
        // First check if context is already current
        CUcontext current = nullptr;
        if (drv.cuCtxGetCurrent) {
            drv.cuCtxGetCurrent(&current);
        }
        
        if (current != ctx) {
            // Context is not current, need to set it
            if (drv.cuCtxPushCurrent) {
                CUresult res = drv.cuCtxPushCurrent(ctx);
                if (res == CUDA_SUCCESS) {
                    pushed = true;
                } else {
                    // Push failed, try SetCurrent instead
                    drv.cuCtxSetCurrent(ctx);
                }
            } else {
                drv.cuCtxSetCurrent(ctx);
            }
        }
        // If context is already current, nothing to do
    }
    
    ~ScopedCtx() {
        if (pushed && drv.cuCtxPopCurrent) {
            CUcontext prev = nullptr;
            drv.cuCtxPopCurrent(&prev);
        }
    }
};

// Device memory pointers
static CUdeviceptr d_params = 0;
static CUdeviceptr d_result = 0;
static CUdeviceptr d_found = 0;
static CUdeviceptr d_debug_stats = 0;

// Performance metrics
struct GPUMetrics {
    uint64_t kernel_launches = 0;
    uint64_t total_seeds_tested = 0;
    uint64_t gpu_time_ms = 0;
    uint64_t matches_found = 0;
    double last_throughput_mps = 0.0;  // Million seeds per second
};
static GPUMetrics metrics;

// Initialize CUDA Driver API and load kernel
static bool ensure_module_loaded() {
    if (ready) return true;
    
    // Reset pointers in case of re-initialization
    mod = nullptr;
    fn = nullptr;
    ctx = nullptr;
    d_params = 0;
    d_result = 0;
    d_found = 0;
    d_debug_stats = 0;
    
    // Debug logging disabled for production
    FILE* debug_file = nullptr;
    drv.debug_file = nullptr;
    
    if (debug_file) {
        auto now = std::chrono::high_resolution_clock::now();
        auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()).count();
        fprintf(debug_file, "\n[%lld] ===== CUDA Driver API Initialization =====\n", ms);
    }
    
    // Load nvcuda.dll
    if (!drv.load()) {
        if (debug_file) {
            fprintf(debug_file, "[CUDA Driver] Failed to load nvcuda.dll or get functions\n");
            fclose(debug_file);
        }
        return false;
    }
    
    // Initialize CUDA
    CUresult res = drv.cuInit(0);
    if (res != CUDA_SUCCESS) {
        if (debug_file) {
            fprintf(debug_file, "[CUDA Driver] cuInit failed: %s\n", drv.getErrorString(res));
            fclose(debug_file);
        }
        return false;
    }
    
    // Get device count
    int device_count = 0;
    res = drv.cuDeviceGetCount(&device_count);
    if (res != CUDA_SUCCESS || device_count == 0) {
        if (debug_file) {
            fprintf(debug_file, "[CUDA Driver] No CUDA devices found\n");
            fclose(debug_file);
        }
        return false;
    }
    
    // Get first device
    CUdevice dev = 0;
    res = drv.cuDeviceGet(&dev, 0);
    if (res != CUDA_SUCCESS) {
        if (debug_file) {
            fprintf(debug_file, "[CUDA Driver] cuDeviceGet failed: %s\n", drv.getErrorString(res));
            fclose(debug_file);
        }
        return false;
    }
    
    // Get device name
    char device_name[256] = {0};
    if (drv.cuDeviceGetName) {
        drv.cuDeviceGetName(device_name, sizeof(device_name), dev);
        if (debug_file) {
            fprintf(debug_file, "[CUDA Driver] Device 0: %s\n", device_name);
        }
    }
    
    // Prefer primary context (plays nicest with other components)
    if (debug_file) {
        fprintf(debug_file, "[CUDA Driver] Retaining primary context for device %d\n", dev);
    }
    
    res = drv.cuDevicePrimaryCtxRetain(&ctx, dev);
    if (res != CUDA_SUCCESS) {
        if (debug_file) {
            fprintf(debug_file,
                    "[CUDA Driver] cuDevicePrimaryCtxRetain failed: %s (code %d)\n",
                    drv.getErrorString(res), res);
            fprintf(debug_file, "[CUDA Driver] Falling back to cuCtxCreate_v2\n");
        }
        
        // Fallback: create new context
        res = drv.cuCtxCreate(&ctx, 0, dev);
        if (res != CUDA_SUCCESS) {
            if (debug_file) {
                fprintf(debug_file,
                        "[CUDA Driver] cuCtxCreate_v2 failed: %s (code %d)\n",
                        drv.getErrorString(res), res);
                fclose(debug_file);
            }
            return false;
        }
    }
    
    // Make it current
    res = drv.cuCtxSetCurrent(ctx);
    if (res != CUDA_SUCCESS) {
        if (debug_file) {
            fprintf(debug_file, "[CUDA Driver] cuCtxSetCurrent failed: %s (code %d)\n",
                    drv.getErrorString(res), res);
            fclose(debug_file);
        }
        return false;
    }
    
    if (debug_file) {
        fprintf(debug_file, "[CUDA Driver] Context retained/created: %p\n", ctx);
        fprintf(debug_file, "[CUDA Driver] Context is now current\n");
    }
    
    // Synchronize context to ensure it's fully initialized
    res = drv.cuCtxSynchronize();
    if (res != CUDA_SUCCESS) {
        if (debug_file) {
            fprintf(debug_file, "[CUDA Driver] WARNING: cuCtxSynchronize failed: %s (code %d)\n", drv.getErrorString(res), res);
        }
    }
    
    if (debug_file) {
        fprintf(debug_file, "[CUDA Driver] Context set as current successfully\n");
        
        // Verify context is current
        CUcontext current = nullptr;
        if (drv.cuCtxGetCurrent) {
            res = drv.cuCtxGetCurrent(&current);
            if (res == CUDA_SUCCESS) {
                fprintf(debug_file, "[CUDA Driver] Verified current context: %p (expected: %p)\n", current, ctx);
                if (current != ctx) {
                    fprintf(debug_file, "[CUDA Driver] WARNING: Context mismatch!\n");
                }
            }
        }
    }
    
    // Allocate device memory FIRST (isolate mem alloc from module/JIT effects)
    const size_t PARAMS_SIZE = sizeof(FilterParams);
    const size_t RESULT_SIZE = sizeof(uint64_t);
    const size_t FOUND_SIZE = sizeof(int);
    const size_t DEBUG_STATS_SIZE = sizeof(DebugStats);
    
    if (debug_file) {
        fprintf(debug_file, "[CUDA Driver] === Memory Allocation Phase (BEFORE module load) ===\n");
        std::ostringstream oss;
        oss << std::this_thread::get_id();
        fprintf(debug_file, "[CUDA Driver] Thread ID: %s\n", oss.str().c_str());
    }
    
    // Ensure context is current for allocation
    // Note: After cuDevicePrimaryCtxRetain, context is already current
    // So we just verify it's current, don't need to push again
    CUcontext current = nullptr;
    if (drv.cuCtxGetCurrent) {
        res = drv.cuCtxGetCurrent(&current);
        if (res == CUDA_SUCCESS && current != ctx) {
            // Context not current, set it
            res = drv.cuCtxSetCurrent(ctx);
            if (res != CUDA_SUCCESS) {
                if (debug_file) {
                    fprintf(debug_file, "[CUDA Driver] Failed to set context: %s (code %d)\n",
                            drv.getErrorString(res), res);
                    fclose(debug_file);
                }
                return false;
            }
        }
    }
    
    if (debug_file) {
        fprintf(debug_file, "[CUDA Driver] Context verified as current for allocation\n");
    }
    
    // Allocate parameters
    res = drv.cuMemAlloc(&d_params, PARAMS_SIZE);
    if (res != CUDA_SUCCESS) {
        if (debug_file) {
            fprintf(debug_file, "[CUDA Driver] Failed to allocate params: %s (code %d)\n",
                    drv.getErrorString(res), res);
            fprintf(debug_file, "[CUDA Driver] Current ctx ptr at failure: ");
            CUcontext cur = nullptr;
            if (drv.cuCtxGetCurrent) drv.cuCtxGetCurrent(&cur);
            fprintf(debug_file, "%p\n", cur);
            fclose(debug_file);
        }
        return false;
    }
    
    if (debug_file) {
        fprintf(debug_file, "[CUDA Driver] Successfully allocated params: %llu bytes at 0x%llx\n", 
                (unsigned long long)PARAMS_SIZE, (unsigned long long)d_params);
    }
    
    // Context remains current for subsequent operations
    
    // NOW load PTX module (if alloc worked, context is sane)
    if (debug_file) {
        fprintf(debug_file, "[CUDA Driver] Loading PTX module (%u bytes)\n", build_seed_filter_ptx_len);
        fprintf(debug_file, "[CUDA Driver] PTX data ptr: %p\n", build_seed_filter_ptx);
        fflush(debug_file);
    }
    
    res = drv.cuModuleLoadDataEx(&mod, (const void*)build_seed_filter_ptx, 0, nullptr, nullptr);
    if (res != CUDA_SUCCESS) {
        if (debug_file) {
            fprintf(debug_file, "[CUDA Driver] cuModuleLoadDataEx failed: %s (code %d)\n", drv.getErrorString(res), res);
            fclose(debug_file);
        }
        return false;
    }
    
    if (debug_file) {
        fprintf(debug_file, "[CUDA Driver] PTX module loaded successfully: %p\n", mod);
        fflush(debug_file);
    }
    
    // Get kernel function
    if (debug_file) {
        fprintf(debug_file, "[CUDA Driver] Getting kernel function 'find_seeds_kernel'\n");
        fflush(debug_file);
    }
    res = drv.cuModuleGetFunction(&fn, mod, "find_seeds_kernel");
    if (res != CUDA_SUCCESS) {
        if (debug_file) {
            fprintf(debug_file, "[CUDA Driver] cuModuleGetFunction failed: %s (code %d)\n", drv.getErrorString(res), res);
            fclose(debug_file);
        }
        return false;
    }
    if (debug_file) {
        fprintf(debug_file, "[CUDA Driver] Kernel function found: %p\n", fn);
        fflush(debug_file);
    }
    
    // Allocate remaining memory with push/pop
    if (drv.cuCtxPushCurrent) {
        drv.cuCtxPushCurrent(ctx);
    }
    
    res = drv.cuMemAlloc(&d_result, RESULT_SIZE);
    if (res != CUDA_SUCCESS) {
        drv.cuMemFree(d_params);
        if (debug_file) {
            fprintf(debug_file, "[CUDA Driver] Failed to allocate result: %s\n", drv.getErrorString(res));
            fclose(debug_file);
        }
        return false;
    }
    
    res = drv.cuMemAlloc(&d_found, FOUND_SIZE);
    if (res != CUDA_SUCCESS) {
        drv.cuMemFree(d_params);
        drv.cuMemFree(d_result);
        if (debug_file) {
            fprintf(debug_file, "[CUDA Driver] Failed to allocate found flag: %s\n", drv.getErrorString(res));
            fclose(debug_file);
        }
        return false;
    }
    
    // Optional: allocate debug stats
    res = drv.cuMemAlloc(&d_debug_stats, DEBUG_STATS_SIZE);
    if (res != CUDA_SUCCESS) {
        // Non-fatal, just won't have debug stats
        d_debug_stats = 0;
        if (debug_file) {
            fprintf(debug_file, "[CUDA Driver] Warning: Failed to allocate debug stats (non-fatal)\n");
        }
    }
    
    // Context remains current for kernel operations
    
    if (debug_file) {
        fprintf(debug_file, "[CUDA Driver] ✓ Successfully initialized\n");
        fprintf(debug_file, "[CUDA Driver] Device memory allocated:\n");
        fprintf(debug_file, "  - d_params: 0x%llX (%zu bytes)\n", (unsigned long long)d_params, PARAMS_SIZE);
        fprintf(debug_file, "  - d_result: 0x%llX (%zu bytes)\n", (unsigned long long)d_result, RESULT_SIZE);
        fprintf(debug_file, "  - d_found: 0x%llX (%zu bytes)\n", (unsigned long long)d_found, FOUND_SIZE);
        if (d_debug_stats) {
            fprintf(debug_file, "  - d_debug_stats: 0x%llX (%zu bytes)\n", (unsigned long long)d_debug_stats, DEBUG_STATS_SIZE);
        }
        fclose(debug_file);
    }
    
    ready = true;
    return true;
}

// Launch kernel using Driver API
extern "C" void launch_seed_search_driver(
    uint64_t start_seed,
    uint32_t count,
    const FilterParams* h_params,  // Host pointer to params
    uint64_t* h_result,            // Host pointer for result (output)
    int* h_found                   // Host pointer for found flag (output)
) {
    if (!ensure_module_loaded()) {
        // Fail silently or return error
        if (h_found) *h_found = 0;
        return;
    }
    
    FILE* debug_file = nullptr; // Debug logging disabled for production
    
    // Use ScopedCtx for automatic push/pop
    ScopedCtx scoped(drv, ctx);
    
    if (debug_file) {
        std::ostringstream oss;
        oss << std::this_thread::get_id();
        fprintf(debug_file, "[CUDA Driver] Launch with thread ID: %s\n", oss.str().c_str());
    }
    
    auto gpu_start = std::chrono::high_resolution_clock::now();
    
    // Clear found flag and result
    int zero_flag = 0;
    uint64_t zero_result = 0;
    
    CUresult res = drv.cuMemcpyHtoD(d_found, &zero_flag, sizeof(int));
    if (res != CUDA_SUCCESS) {
        if (debug_file) {
            fprintf(debug_file, "[CUDA Driver] Failed to clear found flag: %s\n", drv.getErrorString(res));
            fclose(debug_file);
        }
        return;
    }
    
    res = drv.cuMemcpyHtoD(d_result, &zero_result, sizeof(uint64_t));
    if (res != CUDA_SUCCESS) {
        if (debug_file) {
            fprintf(debug_file, "[CUDA Driver] Failed to clear result: %s\n", drv.getErrorString(res));
            fclose(debug_file);
        }
        return;
    }
    
    // Copy parameters to device
    res = drv.cuMemcpyHtoD(d_params, h_params, sizeof(FilterParams));
    if (res != CUDA_SUCCESS) {
        if (debug_file) {
            fprintf(debug_file, "[CUDA Driver] Failed to copy params: %s\n", drv.getErrorString(res));
            fclose(debug_file);
        }
        return;
    }
    
    // Clear debug stats if available
    if (d_debug_stats) {
        drv.cuMemsetD32(d_debug_stats, 0, sizeof(DebugStats) / 4);
    }
    
    // Prepare kernel arguments
    // The kernel expects: (uint64_t, uint32_t, FilterParams*, uint64_t*, int*, DebugStats*)
    void* args[] = {
        &start_seed,     // uint64_t start_seed
        &count,          // uint32_t count
        &d_params,       // FilterParams* (device pointer)
        &d_result,       // uint64_t* (device pointer)
        &d_found,        // int* (device pointer)
        &d_debug_stats   // DebugStats* (device pointer, can be null)
    };
    
    // Calculate launch configuration
    const unsigned threads_per_block = 256;
    unsigned blocks = (count + threads_per_block - 1) / threads_per_block;
    
    // Limit blocks to avoid TDR timeout (Windows Display Driver timeout ~2 seconds)
    const unsigned MAX_BLOCKS = 16384;  // Conservative limit
    if (blocks > MAX_BLOCKS) {
        blocks = MAX_BLOCKS;
        if (debug_file) {
            fprintf(debug_file, "[CUDA Driver] Warning: Limiting blocks from %u to %u to avoid TDR\n", 
                    (count + threads_per_block - 1) / threads_per_block, MAX_BLOCKS);
        }
    }
    
    if (debug_file) {
        fprintf(debug_file, "[CUDA Driver] Launching kernel:\n");
        fprintf(debug_file, "  - Start seed: 0x%016llX\n", start_seed);
        fprintf(debug_file, "  - Count: %u\n", count);
        fprintf(debug_file, "  - Grid: %u blocks\n", blocks);
        fprintf(debug_file, "  - Block: %u threads\n", threads_per_block);
        fprintf(debug_file, "  - Total threads: %u\n", blocks * threads_per_block);
        fprintf(debug_file, "  - Filter params:\n");
        fprintf(debug_file, "    - tag1: %u\n", h_params->tag1);
        fprintf(debug_file, "    - tag2: %u\n", h_params->tag2);
        fprintf(debug_file, "    - voucher: %u\n", h_params->voucher);
        fprintf(debug_file, "    - pack: %u\n", h_params->pack);
    }
    
    // Launch kernel
    res = drv.cuLaunchKernel(
        fn,                    // kernel function
        blocks, 1, 1,         // grid dimensions (x, y, z)
        threads_per_block, 1, 1,  // block dimensions (x, y, z)
        0,                    // shared memory size
        0,                    // stream (0 = default)
        args,                 // kernel arguments
        nullptr               // extra options
    );
    
    if (res != CUDA_SUCCESS) {
        if (debug_file) {
            fprintf(debug_file, "[CUDA Driver] cuLaunchKernel failed: %s\n", drv.getErrorString(res));
            fclose(debug_file);
        }
        return;
    }
    
    // Synchronize and wait for completion
    res = drv.cuCtxSynchronize();
    if (res != CUDA_SUCCESS) {
        if (debug_file) {
            fprintf(debug_file, "[CUDA Driver] cuCtxSynchronize failed: %s\n", drv.getErrorString(res));
            fclose(debug_file);
        }
        return;
    }
    
    auto gpu_end = std::chrono::high_resolution_clock::now();
    auto gpu_ms = std::chrono::duration_cast<std::chrono::milliseconds>(gpu_end - gpu_start).count();
    
    // Copy results back to host
    res = drv.cuMemcpyDtoH(h_found, d_found, sizeof(int));
    if (res != CUDA_SUCCESS) {
        if (debug_file) {
            fprintf(debug_file, "[CUDA Driver] Failed to copy found flag: %s\n", drv.getErrorString(res));
            fclose(debug_file);
        }
        return;
    }
    
    if (*h_found) {
        res = drv.cuMemcpyDtoH(h_result, d_result, sizeof(uint64_t));
        if (res != CUDA_SUCCESS) {
            if (debug_file) {
                fprintf(debug_file, "[CUDA Driver] Failed to copy result: %s\n", drv.getErrorString(res));
                fclose(debug_file);
            }
            return;
        }
        metrics.matches_found++;
    }
    
    // Update metrics
    metrics.kernel_launches++;
    metrics.total_seeds_tested += count;
    metrics.gpu_time_ms += gpu_ms;
    metrics.last_throughput_mps = (count / 1000000.0) / (gpu_ms / 1000.0);
    
    // Copy debug stats if available
    DebugStats stats = {0};
    if (d_debug_stats) {
        drv.cuMemcpyDtoH(&stats, d_debug_stats, sizeof(DebugStats));
    }
    
    if (debug_file) {
        fprintf(debug_file, "[CUDA Driver] Kernel execution complete:\n");
        fprintf(debug_file, "  - Execution time: %lld ms\n", gpu_ms);
        fprintf(debug_file, "  - Found match: %s\n", *h_found ? "YES" : "NO");
        if (*h_found) {
            fprintf(debug_file, "  - Result seed: 0x%016llX\n", *h_result);
        }
        fprintf(debug_file, "  - Throughput: %.2f M seeds/sec\n", metrics.last_throughput_mps);
        
        if (d_debug_stats && stats.seeds_tested > 0) {
            fprintf(debug_file, "  - Debug stats:\n");
            fprintf(debug_file, "    - Seeds tested: %llu\n", stats.seeds_tested);
            fprintf(debug_file, "    - Tag matches: %llu\n", stats.tag_matches);
            fprintf(debug_file, "    - Total matches: %llu\n", stats.total_matches);
        }
        
        fprintf(debug_file, "  - Cumulative metrics:\n");
        fprintf(debug_file, "    - Total launches: %llu\n", metrics.kernel_launches);
        fprintf(debug_file, "    - Total seeds: %llu\n", metrics.total_seeds_tested);
        fprintf(debug_file, "    - Total matches: %llu\n", metrics.matches_found);
        fprintf(debug_file, "    - Average throughput: %.2f M seeds/sec\n",
                (metrics.total_seeds_tested / 1000000.0) / (metrics.gpu_time_ms / 1000.0));
        
        fclose(debug_file);
    }
}

// Wrapper function to match existing interface
extern "C" std::string gpu_search_with_driver(
    const std::string& start_seed_str,
    const FilterParams& params
) {
    FILE* debug_file = nullptr; // Debug logging disabled for production
    if (debug_file) {
        fprintf(debug_file, "\n[gpu_search_with_driver] ENTRY\n");
        fprintf(debug_file, "[gpu_search_with_driver] Seed: %s\n", start_seed_str.c_str());
        fprintf(debug_file, "[gpu_search_with_driver] Ready flag: %s\n", ready ? "true" : "false");
        fprintf(debug_file, "[gpu_search_with_driver] Context: %p\n", ctx);
        fprintf(debug_file, "[gpu_search_with_driver] Module: %p\n", mod);
        fprintf(debug_file, "[gpu_search_with_driver] Function: %p\n", fn);
        fflush(debug_file);
    }
    
    // Try to initialize GPU if not ready
    if (!ensure_module_loaded()) {
        // GPU initialization failed - return empty string to indicate no GPU
        if (debug_file) {
            fprintf(debug_file, "[gpu_search_with_driver] ensure_module_loaded() returned false\n");
            fprintf(debug_file, "[gpu_search_with_driver] GPU initialization failed, cannot search\n");
            fclose(debug_file);
        }
        return "";  // Return empty to indicate failure
    }
    
    if (debug_file) {
        fprintf(debug_file, "[gpu_search_with_driver] GPU initialized successfully\n");
        fprintf(debug_file, "[gpu_search_with_driver] Ready: %s, Context: %p, Module: %p\n", 
                ready ? "true" : "false", ctx, mod);
        fclose(debug_file);
    }
    
    try {
        // Convert seed string to numeric
        Seed seed_obj(start_seed_str);
        uint64_t start_seed_num = static_cast<uint64_t>(seed_obj.getID());
        
        const uint32_t BATCH_SIZE = 1000000;  // 1M seeds per batch
        
        uint64_t result_num = 0;
        int found = 0;
        
        // Launch kernel
        launch_seed_search_driver(start_seed_num, BATCH_SIZE, &params, &result_num, &found);
        
        if (found) {
            // Convert result back to string
            Seed result_seed(static_cast<long long>(result_num));
            return result_seed.tostring();
        }
    } catch (...) {
        // Catch any exceptions and log them
        FILE* debug_file = nullptr; // Debug logging disabled for production
        if (debug_file) {
            fprintf(debug_file, "[CUDA Driver] Exception caught in gpu_search_with_driver\n");
            fclose(debug_file);
        }
    }
    
    return "";  // No match found or error
}

// Cleanup function
extern "C" void cleanup_gpu_driver() {
    if (ready) {
        // Use ScopedCtx to ensure context is current
        ScopedCtx scoped(drv, ctx);
        
        // Free device memory
        if (d_params) drv.cuMemFree(d_params);
        if (d_result) drv.cuMemFree(d_result);
        if (d_found) drv.cuMemFree(d_found);
        if (d_debug_stats) drv.cuMemFree(d_debug_stats);
        
        // Unload module
        if (mod) drv.cuModuleUnload(mod);
        
        // Destroy or release context based on how it was created
        if (ctx) {
            // Try to destroy context first (if it was created with cuCtxCreate)
            CUresult res = drv.cuCtxDestroy(ctx);
            if (res != CUDA_SUCCESS) {
                // If destroy failed, it might be a primary context, try releasing
                drv.cuDevicePrimaryCtxRelease(0);
            }
        }
        
        // Unload driver
        drv.unload();
        
        // Reset all pointers
        ctx = nullptr;
        mod = nullptr;
        fn = nullptr;
        d_params = 0;
        d_result = 0;
        d_found = 0;
        d_debug_stats = 0;
        ready = false;
    }
}
