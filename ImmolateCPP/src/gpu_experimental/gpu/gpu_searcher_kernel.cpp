// GPU Searcher implementation with actual CUDA kernel support
// This file provides the bridge between C++ and CUDA kernels

#include "functions.hpp"
#include "instance.hpp"
#include "rng.hpp"
#include "seed.hpp"
#include "util.hpp"
#include "cuda_wrapper.hpp"
#include "gpu_searcher.hpp"
#include <chrono>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <future>
#include <iostream>
#include <vector>
#include <atomic>

// External CUDA wrapper
extern CudaWrapper g_cuda;

// Debug mode flag
#define GPU_DEBUG 1  // Always enabled for now

// Performance metrics
struct GPUMetrics {
    std::atomic<uint64_t> kernel_launches{0};
    std::atomic<uint64_t> total_seeds_tested{0};
    std::atomic<uint64_t> gpu_time_ms{0};
    std::atomic<uint64_t> cpu_fallback_count{0};
    std::atomic<uint64_t> matches_found{0};
    double last_throughput_mps{0.0};  // Million seeds per second
};

static GPUMetrics g_metrics;

// External CUDA kernel function (linked from seed_filter.cu)
extern "C" void launch_seed_search(
    uint64_t start_seed,
    uint32_t count,
    void* d_params,
    uint64_t* d_result,
    int* d_found,
    void* d_debug_stats
);

// GPU kernel search implementation
std::string gpu_kernel_search(
    const std::string& start_seed_str,
    const FilterParams& params,
    void* d_params,
    uint64_t* d_result,
    int* d_found
) {
    // Convert seed string to numeric representation
    Seed seed_obj(start_seed_str);
    uint64_t start_seed_num = static_cast<uint64_t>(seed_obj.getID());
    
    const uint32_t BATCH_SIZE = 1000000;  // 1M seeds per kernel launch for GPU
    
    // Debug logging
    FILE* debug_file = nullptr;
    if (GPU_DEBUG) {
        debug_file = fopen("C:\\Users\\Krish\\AppData\\Roaming\\Balatro\\Mods\\Brainstorm\\gpu_debug.log", "a");
        if (debug_file) {
            auto now = std::chrono::high_resolution_clock::now();
            auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()).count();
            fprintf(debug_file, "\n[%lld] ===== GPU Kernel Search =====\n", ms);
            fprintf(debug_file, "[GPU] Starting search from seed: %s (0x%016llX)\n", 
                    start_seed_str.c_str(), start_seed_num);
            fprintf(debug_file, "[GPU] Filter params:\n");
            fprintf(debug_file, "  - Tag1: %d\n", params.tag1);
            fprintf(debug_file, "  - Tag2: %d\n", params.tag2);
            fprintf(debug_file, "  - Voucher: %d\n", params.voucher);
            fprintf(debug_file, "  - Pack: %d\n", params.pack);
            fprintf(debug_file, "  - Batch size: %u\n", BATCH_SIZE);
            fprintf(debug_file, "[GPU] Device memory pointers:\n");
            fprintf(debug_file, "  - d_params: %p\n", d_params);
            fprintf(debug_file, "  - d_result: %p\n", d_result);
            fprintf(debug_file, "  - d_found: %p\n", d_found);
            fflush(debug_file);
        }
    }
    
    auto gpu_start = std::chrono::high_resolution_clock::now();
    
    try {
        // Reset buffers
        int zero_flag = 0;
        uint64_t zero_result = 0;
        
        cudaError_t err = g_cuda.cudaMemcpy(d_found, &zero_flag, sizeof(int), cudaMemcpyHostToDevice);
        if (err != cudaSuccess) {
            throw std::runtime_error(std::string("Failed to reset found flag: ") + 
                                   g_cuda.cudaGetErrorString(err));
        }
        
        err = g_cuda.cudaMemcpy(d_result, &zero_result, sizeof(uint64_t), cudaMemcpyHostToDevice);
        if (err != cudaSuccess) {
            throw std::runtime_error(std::string("Failed to reset result: ") + 
                                   g_cuda.cudaGetErrorString(err));
        }
        
        // Copy parameters to device
        err = g_cuda.cudaMemcpy(d_params, &params, sizeof(FilterParams), cudaMemcpyHostToDevice);
        if (err != cudaSuccess) {
            throw std::runtime_error(std::string("Failed to copy params: ") + 
                                   g_cuda.cudaGetErrorString(err));
        }
        
        if (GPU_DEBUG && debug_file) {
            fprintf(debug_file, "[GPU] Launching CUDA kernel with %u threads...\n", BATCH_SIZE);
            fprintf(debug_file, "[GPU] Kernel function address: %p\n", (void*)&launch_seed_search);
            fflush(debug_file);
        }
        
        // Launch the kernel
        launch_seed_search(start_seed_num, BATCH_SIZE, d_params, d_result, d_found, nullptr);
        
        // Check for launch errors
        err = g_cuda.cudaGetLastError();
        if (err != cudaSuccess) {
            throw std::runtime_error(std::string("Kernel launch failed: ") + 
                                   g_cuda.cudaGetErrorString(err));
        }
        
        // Synchronize and wait for kernel completion
        err = g_cuda.cudaDeviceSynchronize();
        if (err != cudaSuccess) {
            throw std::runtime_error(std::string("Kernel execution failed: ") + 
                                   g_cuda.cudaGetErrorString(err));
        }
        
        // Check if match was found
        int found_flag = 0;
        err = g_cuda.cudaMemcpy(&found_flag, d_found, sizeof(int), cudaMemcpyDeviceToHost);
        if (err != cudaSuccess) {
            throw std::runtime_error(std::string("Failed to copy found flag: ") + 
                                   g_cuda.cudaGetErrorString(err));
        }
        
        auto gpu_end = std::chrono::high_resolution_clock::now();
        auto gpu_ms = std::chrono::duration_cast<std::chrono::milliseconds>(gpu_end - gpu_start).count();
        
        // Update metrics
        g_metrics.kernel_launches++;
        g_metrics.total_seeds_tested += BATCH_SIZE;
        g_metrics.gpu_time_ms += gpu_ms;
        g_metrics.last_throughput_mps = (BATCH_SIZE / 1000000.0) / (gpu_ms / 1000.0);
        
        if (found_flag) {
            // Get the result seed
            uint64_t result_num = 0;
            err = g_cuda.cudaMemcpy(&result_num, d_result, sizeof(uint64_t), cudaMemcpyDeviceToHost);
            if (err != cudaSuccess) {
                throw std::runtime_error(std::string("Failed to copy result: ") + 
                                       g_cuda.cudaGetErrorString(err));
            }
            
            // Convert back to string
            Seed result_seed(static_cast<long long>(result_num));
            std::string result_str = result_seed.tostring();
            
            g_metrics.matches_found++;
            
            if (GPU_DEBUG && debug_file) {
                fprintf(debug_file, "[GPU] ✓ Match found via GPU kernel: %s (0x%016llX)\n", 
                        result_str.c_str(), result_num);
                fprintf(debug_file, "[GPU] Execution time: %lld ms\n", gpu_ms);
                fprintf(debug_file, "[GPU] Throughput: %.2f M seeds/sec\n", 
                        g_metrics.last_throughput_mps);
                fprintf(debug_file, "[GPU] Total stats:\n");
                fprintf(debug_file, "  - Kernel launches: %llu\n", g_metrics.kernel_launches.load());
                fprintf(debug_file, "  - Total seeds tested: %llu\n", g_metrics.total_seeds_tested.load());
                fprintf(debug_file, "  - Matches found: %llu\n", g_metrics.matches_found.load());
                fprintf(debug_file, "  - Average throughput: %.2f M seeds/sec\n",
                        (g_metrics.total_seeds_tested.load() / 1000000.0) / 
                        (g_metrics.gpu_time_ms.load() / 1000.0));
                fclose(debug_file);
            }
            
            return result_str;
        } else {
            if (GPU_DEBUG && debug_file) {
                fprintf(debug_file, "[GPU] No match found in batch of %u seeds\n", BATCH_SIZE);
                fprintf(debug_file, "[GPU] Execution time: %lld ms\n", gpu_ms);
                fprintf(debug_file, "[GPU] Throughput: %.2f M seeds/sec\n",
                        g_metrics.last_throughput_mps);
                fclose(debug_file);
            }
        }
        
    } catch (const std::exception& e) {
        g_metrics.cpu_fallback_count++;
        
        if (GPU_DEBUG && debug_file) {
            fprintf(debug_file, "[GPU] ERROR: %s\n", e.what());
            fprintf(debug_file, "[GPU] GPU kernel execution failed\n");
            fprintf(debug_file, "[GPU] Fallback count: %llu\n", g_metrics.cpu_fallback_count.load());
            fclose(debug_file);
        }
        
        std::cerr << "[GPU] Kernel execution error: " << e.what() << std::endl;
    }
    
    return "";  // No match found
}

// Export the function for use in gpu_searcher_dynamic.cpp
extern "C" std::string gpu_search_with_kernel(
    const std::string& start_seed,
    const FilterParams& params,
    void* d_params,
    uint64_t* d_result,
    int* d_found
) {
    return gpu_kernel_search(start_seed, params, d_params, d_result, d_found);
}
