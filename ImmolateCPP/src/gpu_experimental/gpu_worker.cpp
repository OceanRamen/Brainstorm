// Standalone GPU Worker Process
// Receives filter parameters via stdin, returns results via stdout
// This completely isolates GPU operations from the game process

#include <iostream>
#include <string>
#include <cstring>
#include <chrono>
#include <thread>
#include "gpu/cuda_driver_loader.h"
#include "gpu/gpu_types.h"
#include "seed.hpp"

// Include embedded PTX
#include "gpu/seed_filter_ptx.h"

// Simple protocol:
// Input: <seed> <tag1> <tag2> <voucher> <pack> <count>
// Output: FOUND:<seed> or NONE

static bool run_gpu_search(
    const std::string& start_seed,
    const FilterParams& params,
    uint32_t count
) {
    CudaDrv drv;
    drv.debug_file = stderr; // Use stderr for debug output
    
    // Load driver
    if (!drv.load()) {
        std::cerr << "[Worker] Failed to load nvcuda.dll\n";
        return false;
    }
    
    // Initialize CUDA
    CUresult res = drv.cuInit(0);
    if (res != CUDA_SUCCESS) {
        std::cerr << "[Worker] cuInit failed: " << drv.getErrorString(res) << "\n";
        return false;
    }
    
    // Get device
    int device_count = 0;
    drv.cuDeviceGetCount(&device_count);
    if (device_count == 0) {
        std::cerr << "[Worker] No CUDA devices found\n";
        return false;
    }
    
    CUdevice dev = 0;
    drv.cuDeviceGet(&dev, 0);
    
    // Get device name
    char device_name[256] = {0};
    if (drv.cuDeviceGetName) {
        drv.cuDeviceGetName(device_name, sizeof(device_name), dev);
        std::cerr << "[Worker] Device: " << device_name << "\n";
    }
    
    // Create context (not primary - we own this process)
    CUcontext ctx = nullptr;
    res = drv.cuCtxCreate(&ctx, 0, dev);
    if (res != CUDA_SUCCESS) {
        std::cerr << "[Worker] cuCtxCreate failed: " << drv.getErrorString(res) << "\n";
        return false;
    }
    
    std::cerr << "[Worker] Context created: " << ctx << "\n";
    
    // Allocate device memory
    CUdeviceptr d_params = 0;
    CUdeviceptr d_result = 0;
    CUdeviceptr d_found = 0;
    
    res = drv.cuMemAlloc(&d_params, sizeof(FilterParams));
    if (res != CUDA_SUCCESS) {
        std::cerr << "[Worker] Failed to allocate params: " << drv.getErrorString(res) << "\n";
        drv.cuCtxDestroy(ctx);
        return false;
    }
    
    res = drv.cuMemAlloc(&d_result, sizeof(uint64_t));
    if (res != CUDA_SUCCESS) {
        std::cerr << "[Worker] Failed to allocate result: " << drv.getErrorString(res) << "\n";
        drv.cuMemFree(d_params);
        drv.cuCtxDestroy(ctx);
        return false;
    }
    
    res = drv.cuMemAlloc(&d_found, sizeof(int));
    if (res != CUDA_SUCCESS) {
        std::cerr << "[Worker] Failed to allocate found: " << drv.getErrorString(res) << "\n";
        drv.cuMemFree(d_params);
        drv.cuMemFree(d_result);
        drv.cuCtxDestroy(ctx);
        return false;
    }
    
    std::cerr << "[Worker] Memory allocated successfully\n";
    
    // Load PTX module
    CUmodule mod = nullptr;
    res = drv.cuModuleLoadDataEx(&mod, (const void*)build_seed_filter_ptx, 0, nullptr, nullptr);
    if (res != CUDA_SUCCESS) {
        std::cerr << "[Worker] Failed to load PTX: " << drv.getErrorString(res) << "\n";
        drv.cuMemFree(d_params);
        drv.cuMemFree(d_result);
        drv.cuMemFree(d_found);
        drv.cuCtxDestroy(ctx);
        return false;
    }
    
    std::cerr << "[Worker] PTX module loaded\n";
    
    // Get kernel function
    CUfunction fn = nullptr;
    res = drv.cuModuleGetFunction(&fn, mod, "find_seeds_kernel");
    if (res != CUDA_SUCCESS) {
        std::cerr << "[Worker] Failed to get kernel: " << drv.getErrorString(res) << "\n";
        drv.cuModuleUnload(mod);
        drv.cuMemFree(d_params);
        drv.cuMemFree(d_result);
        drv.cuMemFree(d_found);
        drv.cuCtxDestroy(ctx);
        return false;
    }
    
    std::cerr << "[Worker] Kernel function found\n";
    
    // Convert seed to numeric
    Seed seed_obj(start_seed);
    uint64_t start_seed_num = static_cast<uint64_t>(seed_obj.getID());
    
    // Clear found flag
    int zero = 0;
    drv.cuMemcpyHtoD(d_found, &zero, sizeof(int));
    
    // Copy parameters
    drv.cuMemcpyHtoD(d_params, &params, sizeof(FilterParams));
    
    // Launch kernel
    const int threads = 256;
    const int blocks = (count + threads - 1) / threads;
    
    void* args[] = {
        &start_seed_num,
        &count,
        &d_params,
        &d_result,
        &d_found,
        nullptr  // No debug stats
    };
    
    std::cerr << "[Worker] Launching kernel: " << blocks << " blocks, " << threads << " threads\n";
    
    res = drv.cuLaunchKernel(fn,
                             blocks, 1, 1,    // grid
                             threads, 1, 1,   // block
                             0, nullptr,      // shared mem, stream
                             args, nullptr);  // kernel args
    
    if (res != CUDA_SUCCESS) {
        std::cerr << "[Worker] Kernel launch failed: " << drv.getErrorString(res) << "\n";
        drv.cuModuleUnload(mod);
        drv.cuMemFree(d_params);
        drv.cuMemFree(d_result);
        drv.cuMemFree(d_found);
        drv.cuCtxDestroy(ctx);
        return false;
    }
    
    // Wait for completion
    res = drv.cuCtxSynchronize();
    if (res != CUDA_SUCCESS) {
        std::cerr << "[Worker] Sync failed: " << drv.getErrorString(res) << "\n";
    }
    
    // Check if found
    int found = 0;
    drv.cuMemcpyDtoH(&found, d_found, sizeof(int));
    
    if (found) {
        uint64_t result_num = 0;
        drv.cuMemcpyDtoH(&result_num, d_result, sizeof(uint64_t));
        
        // Convert back to string
        Seed result_seed(static_cast<long long>(result_num));
        std::cout << "FOUND:" << result_seed.tostring() << std::endl;
        
        std::cerr << "[Worker] Found match: " << result_seed.tostring() << "\n";
    } else {
        std::cout << "NONE" << std::endl;
        std::cerr << "[Worker] No match found in batch\n";
    }
    
    // Cleanup
    drv.cuModuleUnload(mod);
    drv.cuMemFree(d_params);
    drv.cuMemFree(d_result);
    drv.cuMemFree(d_found);
    drv.cuCtxDestroy(ctx);
    
    std::cerr << "[Worker] Cleanup complete\n";
    
    return found;
}

int main(int argc, char** argv) {
    if (argc > 1 && strcmp(argv[1], "--test") == 0) {
        // Test mode
        FilterParams params = {};
        params.tag1 = 0xFFFFFFFF;
        params.tag2 = 0xFFFFFFFF;
        params.voucher = 0xFFFFFFFF;
        params.pack = 0xFFFFFFFF;
        
        bool result = run_gpu_search("AAAAAAAA", params, 1000000);
        return result ? 0 : 1;
    }
    
    // Normal mode - read from stdin
    std::string line;
    while (std::getline(std::cin, line)) {
        if (line == "QUIT") break;
        
        // Parse input: seed tag1 tag2 voucher pack count
        std::string seed;
        uint32_t tag1, tag2, voucher, pack, count;
        
        if (sscanf(line.c_str(), "%8s %u %u %u %u %u",
                   seed.data(), &tag1, &tag2, &voucher, &pack, &count) != 6) {
            std::cout << "ERROR:Invalid input" << std::endl;
            continue;
        }
        
        FilterParams params = {};
        params.tag1 = tag1;
        params.tag2 = tag2;
        params.voucher = voucher;
        params.pack = pack;
        params.require_souls = 0;
        params.require_observatory = 0;
        params.require_perkeo = 0;
        
        run_gpu_search(seed, params, count);
    }
    
    return 0;
}