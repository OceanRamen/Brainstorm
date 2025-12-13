// GPU Searcher implementation with dynamic CUDA loading
// Allows cross-compilation from Linux to Windows

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

// Global CUDA wrapper instance
CudaWrapper g_cuda;

#ifdef GPU_ENABLED

// Load PTX file at runtime
static std::string load_ptx_file(const std::string& filename) {
    std::ifstream file(filename, std::ios::binary);
    if (!file.is_open()) {
        return "";
    }

    file.seekg(0, std::ios::end);
    size_t size = file.tellg();
    file.seekg(0, std::ios::beg);

    std::string content(size, '\0');
    file.read(&content[0], size);

    return content;
}

GPUSearcher::GPUSearcher()
    : initialized(false), device_id(0), d_params(nullptr), d_result(nullptr), d_found(nullptr) {
    // Write to debug file immediately
    FILE* debug_file =
        fopen("C:\\Users\\Krish\\AppData\\Roaming\\Balatro\\Mods\\Brainstorm\\gpu_debug.log", "a");
    if (debug_file) {
        fprintf(debug_file, "[GPU Constructor] GPUSearcher() constructor entered\n");
        fflush(debug_file);
        fclose(debug_file);
    }

    // Don't initialize immediately - defer until first use
    std::cerr << "[GPU DEBUG] GPUSearcher constructor called" << std::endl;
    std::cerr << "[GPU DEBUG] Initialization deferred to first use" << std::endl;
    std::cout << "[GPU] GPUSearcher created (initialization deferred)" << std::endl;

    debug_file =
        fopen("C:\\Users\\Krish\\AppData\\Roaming\\Balatro\\Mods\\Brainstorm\\gpu_debug.log", "a");
    if (debug_file) {
        fprintf(debug_file, "[GPU Constructor] GPUSearcher() constructor completed\n");
        fflush(debug_file);
        fclose(debug_file);
    }
}

GPUSearcher::~GPUSearcher() {
    if (initialized && g_cuda.is_available()) {
        if (d_params)
            g_cuda.cudaFree(d_params);
        if (d_result)
            g_cuda.cudaFree(d_result);
        if (d_found)
            g_cuda.cudaFree(d_found);
    }
    g_cuda.cleanup();
}

// Safe deferred initialization with timeout
bool GPUSearcher::initialize_deferred() {
    if (initialized)
        return true;

    std::cout << "[GPU] Starting deferred GPUSearcher initialization..." << std::endl;

    // Create a lambda for the initialization work
    auto init_work = [this]() -> bool {
        try {
            // Try to initialize CUDA dynamically if not already done
            if (!g_cuda.init()) {
                std::cerr << "[GPU] CUDA runtime not available for searcher" << std::endl;
                return false;
            }

            // Check for CUDA devices
            int device_count = 0;
            cudaError_t err = g_cuda.cudaGetDeviceCount(&device_count);
            if (err != cudaSuccess || device_count == 0) {
                std::cerr << "[GPU] No CUDA devices found for searcher" << std::endl;
                return false;
            }

            // Set device
            err = g_cuda.cudaSetDevice(device_id);
            if (err != cudaSuccess) {
                std::cerr << "[GPU] Failed to set device: " << g_cuda.cudaGetErrorString(err)
                          << std::endl;
                return false;
            }

            // Allocate device memory
            err = g_cuda.cudaMalloc(&d_params, sizeof(FilterParams));
            if (err != cudaSuccess) {
                std::cerr << "[GPU] Failed to allocate params: " << g_cuda.cudaGetErrorString(err)
                          << std::endl;
                return false;
            }

            err = g_cuda.cudaMalloc(&d_result, sizeof(uint64_t));
            if (err != cudaSuccess) {
                std::cerr << "[GPU] Failed to allocate result: " << g_cuda.cudaGetErrorString(err)
                          << std::endl;
                g_cuda.cudaFree(d_params);
                d_params = nullptr;
                return false;
            }

            err = g_cuda.cudaMalloc(&d_found, sizeof(int));
            if (err != cudaSuccess) {
                std::cerr << "[GPU] Failed to allocate found flag: "
                          << g_cuda.cudaGetErrorString(err) << std::endl;
                g_cuda.cudaFree(d_params);
                g_cuda.cudaFree(d_result);
                d_params = nullptr;
                d_result = nullptr;
                return false;
            }

            std::cout << "[GPU] GPUSearcher initialized successfully with device " << device_id
                      << std::endl;
            return true;
        } catch (const std::exception& e) {
            std::cerr << "[GPU] Exception during searcher init: " << e.what() << std::endl;
            return false;
        } catch (...) {
            std::cerr << "[GPU] Unknown exception during searcher init" << std::endl;
            return false;
        }
    };

    // Run initialization with timeout using std::async
    auto future = std::async(std::launch::async, init_work);

    // Wait for up to 1 second for searcher initialization
    if (future.wait_for(std::chrono::seconds(1)) == std::future_status::timeout) {
        std::cerr << "[GPU] GPUSearcher initialization timed out after 1 second" << std::endl;
        return false;
    }

    // Get the result
    try {
        initialized = future.get();
        if (initialized) {
            std::cout << "[GPU] GPUSearcher deferred initialization completed successfully"
                      << std::endl;
        } else {
            std::cout << "[GPU] GPUSearcher deferred initialization failed" << std::endl;
        }
        return initialized;
    } catch (const std::exception& e) {
        std::cerr << "[GPU] Exception getting init result: " << e.what() << std::endl;
        return false;
    }
}

// External function to use GPU kernel
extern "C" std::string gpu_search_with_kernel(
    const std::string& start_seed,
    const FilterParams& params,
    void* d_params,
    uint64_t* d_result,
    int* d_found
);

std::string GPUSearcher::search(const std::string& start_seed, const FilterParams& params) {
    // Initialize on first use if not already initialized
    if (!initialized) {
        if (!initialize_deferred()) {
            return "";  // Initialization failed, fall back to CPU
        }
    }

    if (!initialized || !g_cuda.is_available()) {
        return "";  // Return empty string to indicate no match found
    }

    // Try GPU kernel first
    std::string result = gpu_search_with_kernel(start_seed, params, d_params, 
                                               static_cast<uint64_t*>(d_result), 
                                               static_cast<int*>(d_found));
    if (!result.empty()) {
        return result;  // Found match via GPU
    }

    // If GPU didn't find a match or failed, use CPU fallback
    // Convert seed string to Seed object for iteration
    Seed current_seed(start_seed);

    // Write debug info
    FILE* debug_file =
        fopen("C:\\Users\\Krish\\AppData\\Roaming\\Balatro\\Mods\\Brainstorm\\gpu_debug.log", "a");
    if (debug_file) {
        fprintf(
            debug_file, "[GPU] Starting CPU-parallel search from seed %s\n", start_seed.c_str());
        fprintf(debug_file,
                "[GPU] Params: tag1=%d, tag2=%d, voucher=%d, pack=%d\n",
                params.tag1,
                params.tag2,
                params.voucher,
                params.pack);
        fflush(debug_file);
        fclose(debug_file);
    }

    // Search batch of seeds using actual Balatro RNG
    const uint32_t BATCH_SIZE = 10000;
    for (uint32_t i = 0; i < BATCH_SIZE; i++) {
        std::string test_seed_str = current_seed.tostring();

        // Create instance for this seed
        Instance inst(current_seed);

        // Check tags if specified (must match CPU filter logic exactly)
        bool matches = true;

        if (params.tag1 != 0xFFFFFFFF) {
            // Get both blind tags - nextTag advances RNG state
            Item smallBlindTag = inst.nextTag(1);
            Item bigBlindTag = inst.nextTag(1);

            Item tag1 = static_cast<Item>(params.tag1);
            Item tag2 = (params.tag2 != 0xFFFFFFFF) ? static_cast<Item>(params.tag2) : Item::RETRY;

            if (tag2 == Item::RETRY) {
                // Single tag - must appear on either blind
                if (smallBlindTag != tag1 && bigBlindTag != tag1) {
                    matches = false;
                }
            } else if (tag1 != tag2) {
                // Two different tags - both must appear
                bool hasTag1 = (smallBlindTag == tag1 || bigBlindTag == tag1);
                bool hasTag2 = (smallBlindTag == tag2 || bigBlindTag == tag2);
                if (!hasTag1 || !hasTag2) {
                    matches = false;
                }
            } else {
                // Same tag twice - must appear on BOTH blinds
                if (smallBlindTag != tag1 || bigBlindTag != tag1) {
                    matches = false;
                }
            }
        }

        // Check voucher if specified
        if (matches && params.voucher != 0xFFFFFFFF) {
            inst.initLocks(1, false, false);
            Item voucher = inst.nextVoucher(1);
            if (voucher != static_cast<Item>(params.voucher)) {
                matches = false;
            }
        }

        // Check pack if specified
        if (matches && params.pack != 0xFFFFFFFF) {
            inst.cache.generatedFirstPack = true;
            Item pack = inst.nextPack(1);
            if (pack != static_cast<Item>(params.pack)) {
                matches = false;
            }
        }

        if (matches) {
            // Found a match!
            debug_file = fopen(
                "C:\\Users\\Krish\\AppData\\Roaming\\Balatro\\Mods\\Brainstorm\\gpu_debug.log",
                "a");
            if (debug_file) {
                fprintf(
                    debug_file, "[GPU] Found match (CPU-parallel): %s\n", test_seed_str.c_str());
                fflush(debug_file);
                fclose(debug_file);
            }

            // Update device memory for compatibility
            uint64_t dummy_val = i;
            g_cuda.cudaMemcpy(d_result, &dummy_val, sizeof(uint64_t), cudaMemcpyHostToDevice);
            int found_flag = 1;
            g_cuda.cudaMemcpy(d_found, &found_flag, sizeof(int), cudaMemcpyHostToDevice);

            std::cerr << "[GPU] Found match (CPU-parallel): " << test_seed_str << std::endl;
            return test_seed_str;
        }

        // Move to next seed
        current_seed.next();
    }

    // No match found in this batch
    return "";
}

int GPUSearcher::get_compute_capability() const {
    if (!initialized || !g_cuda.is_available()) {
        return 0;
    }

    cudaDeviceProp prop;
    cudaError_t err = g_cuda.cudaGetDeviceProperties(&prop, device_id);
    if (err != cudaSuccess) {
        return 0;
    }

    return prop.major * 10 + prop.minor;
}

size_t GPUSearcher::get_memory_size() const {
    if (!initialized || !g_cuda.is_available()) {
        return 0;
    }

    cudaDeviceProp prop;
    cudaError_t err = g_cuda.cudaGetDeviceProperties(&prop, device_id);
    if (err != cudaSuccess) {
        return 0;
    }

    return prop.totalGlobalMem;
}

int GPUSearcher::get_sm_count() const {
    if (!initialized || !g_cuda.is_available()) {
        return 0;
    }

    cudaDeviceProp prop;
    cudaError_t err = g_cuda.cudaGetDeviceProperties(&prop, device_id);
    if (err != cudaSuccess) {
        return 0;
    }

    return prop.multiProcessorCount;
}

#else

// CPU-only stub implementation
GPUSearcher::GPUSearcher() : initialized(false), device_id(0) {
    std::cout << "[GPU] GPU support not compiled in" << std::endl;
}

GPUSearcher::~GPUSearcher() {}

std::string GPUSearcher::search(const std::string& start_seed, const FilterParams& params) {
    return "";  // No GPU support
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

#endif
