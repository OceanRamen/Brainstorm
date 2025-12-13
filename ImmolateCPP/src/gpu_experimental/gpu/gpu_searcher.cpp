// GPU Searcher implementation
// Manages CUDA resources and kernel launches

#include "gpu_searcher.hpp"
#include <chrono>
#include <cstring>
#include <iostream>

#ifdef GPU_ENABLED
    #include <cuda_runtime.h>

// External kernel launch function
extern "C" void launch_seed_search(
    uint64_t start_seed, uint32_t count, FilterParams* d_params, uint64_t* d_result, int* d_found);

GPUSearcher::GPUSearcher() : initialized(false), device_id(0) {
    // Initialize CUDA
    cudaError_t err = cudaSetDevice(device_id);
    if (err != cudaSuccess) {
        std::cerr << "[GPU] Failed to set device: " << cudaGetErrorString(err) << std::endl;
        return;
    }

    // Allocate device memory
    err = cudaMalloc(&d_params, sizeof(FilterParams));
    if (err != cudaSuccess) {
        std::cerr << "[GPU] Failed to allocate params: " << cudaGetErrorString(err) << std::endl;
        return;
    }

    err = cudaMalloc(&d_result, sizeof(uint64_t));
    if (err != cudaSuccess) {
        std::cerr << "[GPU] Failed to allocate result: " << cudaGetErrorString(err) << std::endl;
        cudaFree(d_params);
        return;
    }

    err = cudaMalloc(&d_found, sizeof(int));
    if (err != cudaSuccess) {
        std::cerr << "[GPU] Failed to allocate found flag: " << cudaGetErrorString(err)
                  << std::endl;
        cudaFree(d_params);
        cudaFree(d_result);
        return;
    }

    // TODO: Allocate and initialize RNG lookup tables
    d_rng_tables = nullptr;

    initialized = true;
    std::cout << "[GPU] Searcher initialized successfully" << std::endl;
}

GPUSearcher::~GPUSearcher() {
    if (initialized) {
        cudaFree(d_params);
        cudaFree(d_result);
        cudaFree(d_found);
        if (d_rng_tables) {
            cudaFree(d_rng_tables);
        }
    }
}

std::string GPUSearcher::search(const std::string& start_seed, const FilterParams& params) {
    if (!initialized) {
        std::cerr << "[GPU] Searcher not initialized" << std::endl;
        return "";
    }

    // Convert string seed to numeric
    uint64_t numeric_seed = 0;
    for (size_t i = 0; i < start_seed.length() && i < 8; i++) {
        numeric_seed = (numeric_seed << 8) | start_seed[i];
    }

    // Reset found flag
    int zero = 0;
    cudaMemcpy(d_found, &zero, sizeof(int), cudaMemcpyHostToDevice);

    // Copy parameters to device
    cudaMemcpy(d_params, &params, sizeof(FilterParams), cudaMemcpyHostToDevice);

    // Search configuration
    const uint32_t BATCH_SIZE = 1048576;   // 1M seeds per batch
    const uint64_t MAX_SEEDS = 100000000;  // 100M max

    auto start_time = std::chrono::high_resolution_clock::now();
    uint64_t seeds_tested = 0;

    for (uint64_t offset = 0; offset < MAX_SEEDS; offset += BATCH_SIZE) {
        // Launch kernel
        launch_seed_search(numeric_seed + offset,
                           BATCH_SIZE,
                           (FilterParams*)d_params,
                           (uint64_t*)d_result,
                           (int*)d_found);

        // Wait for kernel to complete
        cudaDeviceSynchronize();

        // Check if found
        int found_flag;
        cudaMemcpy(&found_flag, d_found, sizeof(int), cudaMemcpyDeviceToHost);

        seeds_tested += BATCH_SIZE;

        if (found_flag) {
            uint64_t result_seed;
            cudaMemcpy(&result_seed, d_result, sizeof(uint64_t), cudaMemcpyDeviceToHost);

            // Convert back to string
            std::string result;
            for (int i = 7; i >= 0; i--) {
                result += (char)((result_seed >> (i * 8)) & 0xFF);
            }

            auto end_time = std::chrono::high_resolution_clock::now();
            auto duration =
                std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time);

            std::cout << "[GPU] Found match: " << result << " (" << seeds_tested << " seeds in "
                      << duration.count() << "ms = " << (seeds_tested * 1000 / duration.count())
                      << " seeds/sec)" << std::endl;

            return result;
        }

        // Progress update every 10M seeds
        if (seeds_tested % 10000000 == 0) {
            auto current_time = std::chrono::high_resolution_clock::now();
            auto duration =
                std::chrono::duration_cast<std::chrono::seconds>(current_time - start_time);
            if (duration.count() > 0) {
                std::cout << "[GPU] Tested " << (seeds_tested / 1000000) << "M seeds ("
                          << (seeds_tested / duration.count()) << " seeds/sec)" << std::endl;
            }
        }
    }

    std::cout << "[GPU] No match found after " << seeds_tested << " seeds" << std::endl;
    return "";
}

int GPUSearcher::get_compute_capability() const {
    if (!initialized)
        return 0;

    cudaDeviceProp props;
    cudaGetDeviceProperties(&props, device_id);
    return props.major * 10 + props.minor;
}

size_t GPUSearcher::get_memory_size() const {
    if (!initialized)
        return 0;

    cudaDeviceProp props;
    cudaGetDeviceProperties(&props, device_id);
    return props.totalGlobalMem;
}

int GPUSearcher::get_sm_count() const {
    if (!initialized)
        return 0;

    cudaDeviceProp props;
    cudaGetDeviceProperties(&props, device_id);
    return props.multiProcessorCount;
}

#else  // !GPU_ENABLED

// Stub implementation when GPU support is not compiled in
GPUSearcher::GPUSearcher() : initialized(false), device_id(0) {
    std::cout << "[GPU] Compiled without GPU support" << std::endl;
}

GPUSearcher::~GPUSearcher() {}

std::string GPUSearcher::search(const std::string& start_seed, const FilterParams& params) {
    return "";  // Always fail, will fall back to CPU
}

int GPUSearcher::get_compute_capability() const {
    return 0;
}
size_t GPUSearcher::get_memory_size() const {
    return 0;
}
int GPUSearcher::get_sm_count() const {
    return 0;
}

#endif  // GPU_ENABLED