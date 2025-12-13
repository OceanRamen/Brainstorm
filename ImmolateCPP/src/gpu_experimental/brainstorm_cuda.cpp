/*
 * Brainstorm DLL - High-performance seed searching for Balatro
 * 
 * Features:
 *  - Transparent GPU acceleration via CUDA Driver API
 *  - Automatic CPU fallback when GPU unavailable
 *  - Dual tag support with order-agnostic matching
 *  - Zero-copy string interop with LuaJIT FFI
 */

#include "functions.hpp"
#include "search.hpp"
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <future>
#include <iostream>
#include <string>
#include <thread>

// Check for CUDA at compile time
#ifdef GPU_ENABLED
    #ifdef GPU_DYNAMIC_LOAD
        #include "gpu/cuda_wrapper.hpp"
    #else
        #include <cuda_runtime.h>
    #endif
    #include "gpu/gpu_searcher.hpp"
#endif

// Define IMMOLATE_API for DLL export
#ifndef IMMOLATE_API
    #ifdef _WIN32
        #ifdef BUILDING_DLL
            #define IMMOLATE_API __declspec(dllexport)
        #else
            #define IMMOLATE_API __declspec(dllimport)
        #endif
    #else
        #define IMMOLATE_API
    #endif
#endif

// Global filter settings (shared between CPU and GPU)
Item BRAINSTORM_VOUCHER = Item::RETRY;
Item BRAINSTORM_PACK = Item::RETRY;
Item BRAINSTORM_TAG1 = Item::RETRY;
Item BRAINSTORM_TAG2 = Item::RETRY;
long BRAINSTORM_SOULS = 0;
bool BRAINSTORM_OBSERVATORY = false;
bool BRAINSTORM_PERKEO = false;

// GPU state management
static bool g_cuda_available = false;
static bool g_use_cuda = false;                  // Default to false, enable after successful init
static bool g_initialization_attempted = false;  // Track if we've tried init
static int g_device_count = 0;
static std::string g_hardware_info = "CPU: GPU initialization not attempted";

#ifdef GPU_ENABLED
static GPUSearcher* g_gpu_searcher = nullptr;
#endif

// Safe GPU initialization with timeout
static void initialize_gpu_internal() {
#ifdef GPU_ENABLED

    try {
    #ifdef GPU_DYNAMIC_LOAD
        // Use dynamic CUDA loader
        extern CudaWrapper g_cuda;

        bool init_result = false;
        try {
            init_result = g_cuda.init();
        } catch (const std::exception& e) {
            // CUDA init failed - silent fallback to CPU
            init_result = false;
        } catch (...) {
            // CUDA init failed - silent fallback to CPU
            init_result = false;
        }

        if (!init_result) {
            g_cuda_available = false;
            g_hardware_info = "CPU: CUDA runtime not found";
            return;
        }

        cudaError_t err = cudaErrorUnknown;
        try {
            if (!g_cuda.cudaGetDeviceCount) {
                throw std::runtime_error("cudaGetDeviceCount function pointer is NULL");
            }
            err = g_cuda.cudaGetDeviceCount(&g_device_count);
        } catch (const std::exception& e) {
            // Device query failed - rethrow to be caught by outer handler
            throw;
        } catch (...) {
            // Device query failed - rethrow to be caught by outer handler
            throw;
        }

        if (err == cudaSuccess && g_device_count > 0) {
            // Prefer attribute/name path to avoid struct ABI mismatches
            int major = 0, minor = 0, mpc = 0;
            char name[256] = {0};
            size_t free_mem = 0, total_mem = 0;
            bool have_attrs = (g_cuda.cudaDeviceGetAttribute != nullptr);
            bool have_name = (g_cuda.cudaDeviceGetName != nullptr);

            // Set device 0 so cudaMemGetInfo works
            if (g_cuda.cudaSetDevice) {
                g_cuda.cudaSetDevice(0);
            }

            // Use safer attribute-based queries if available
            if (have_attrs) {
                g_cuda.cudaDeviceGetAttribute(&major, cudaDevAttrComputeCapabilityMajor, 0);
                g_cuda.cudaDeviceGetAttribute(&minor, cudaDevAttrComputeCapabilityMinor, 0);
                g_cuda.cudaDeviceGetAttribute(&mpc, cudaDevAttrMultiProcessorCount, 0);
            }

            if (have_name) {
                g_cuda.cudaDeviceGetName(name, (int)sizeof(name), 0);
            }

            if (g_cuda.cudaMemGetInfo) {
                g_cuda.cudaMemGetInfo(&free_mem, &total_mem);
            }

            // Fallback to properties only if necessary
            if ((!have_attrs || !have_name) && g_cuda.cudaGetDeviceProperties) {
                cudaDeviceProp props = {};
                err = g_cuda.cudaGetDeviceProperties(&props, 0);
                if (err == cudaSuccess) {
                    if (major == 0)
                        major = props.major;
                    if (minor == 0)
                        minor = props.minor;
                    if (mpc == 0)
                        mpc = props.multiProcessorCount;
                    if (name[0] == '\0') {
                        strncpy(name, props.name, sizeof(name) - 1);
                    }
                    if (total_mem == 0)
                        total_mem = props.totalGlobalMem;
                } else {
                    // Properties query failed - continue with partial info
                }
            }

            // Check if device meets minimum requirements
            if (major >= 6) {
                g_cuda_available = true;
                size_t total_mb = total_mem ? (total_mem / (1024 * 1024)) : 0;
                g_hardware_info = std::string("GPU: ") + (name[0] ? name : "(unknown)") +
                                  " (Compute " + std::to_string(major) + "." +
                                  std::to_string(minor) + ", " + std::to_string(mpc) + " SMs" +
                                  (total_mb ? (", " + std::to_string(total_mb) + " MB") : "") + ")";
            } else {
                g_hardware_info = std::string("CPU: GPU ") + (name[0] ? name : "(unknown)") +
                                  " too old (Compute " + std::to_string(major) + "." +
                                  std::to_string(minor) + " < 6.0)";
                // Log hardware info only in debug mode
            }
        } else {
            g_hardware_info = "CPU: No CUDA-capable GPU found";
            std::cout << "[Brainstorm] " << g_hardware_info << std::endl;
        }
    #endif  // GPU_DYNAMIC_LOAD

        // Create GPU searcher instance if CUDA is available (deferred initialization)
        if (g_cuda_available) {
            try {
                g_gpu_searcher = new GPUSearcher();
            } catch (const std::exception& e) {
                // GPUSearcher creation failed - fallback to CPU
                g_cuda_available = false;
                g_hardware_info = std::string("CPU: GPUSearcher creation failed - ") + e.what();
            } catch (...) {
                // GPUSearcher creation failed - fallback to CPU
                g_cuda_available = false;
                g_hardware_info = "CPU: GPUSearcher creation failed - unknown error";
            }

            // Only enable CUDA if everything succeeded
            g_use_cuda = g_cuda_available;
        }
    } catch (const std::exception& e) {
        g_cuda_available = false;
        g_use_cuda = false;
        g_hardware_info = std::string("CPU: GPU init failed - ") + e.what();
        // GPU init exception - fallback to CPU
    } catch (...) {
        g_cuda_available = false;
        g_use_cuda = false;
        g_hardware_info = "CPU: GPU init failed - unknown error";
        // Unknown GPU init exception - fallback to CPU
    }
#else
    g_hardware_info = "CPU: Compiled without GPU support";
#endif
}

// Initialize GPU support with timeout protection
static void initialize_gpu() {
    if (g_initialization_attempted)
        return;  // Only try once
    g_initialization_attempted = true;

    // Attempt GPU initialization with timeout protection

    // Use std::async to run initialization with timeout
    auto future = std::async(std::launch::async, initialize_gpu_internal);

    // Wait for up to 2 seconds for initialization to complete
    if (future.wait_for(std::chrono::seconds(2)) == std::future_status::timeout) {
        g_cuda_available = false;
        g_use_cuda = false;
        g_hardware_info = "CPU: GPU initialization timed out after 2 seconds";
        // Initialization timed out - fallback to CPU
    } else {
        // Get the result (this should be immediate since we already waited)
        try {
            future.get();
        } catch (const std::exception& e) {
            g_cuda_available = false;
            g_use_cuda = false;
            g_hardware_info = std::string("CPU: GPU init exception - ") + e.what();
            // Exception from async init - fallback to CPU
        }
    }

    // GPU initialization complete
}

// CPU implementation - existing filter logic
int filter_cpu(Instance& inst) {
    // Check tags first (cheapest operation)
    if (BRAINSTORM_TAG1 != Item::RETRY || BRAINSTORM_TAG2 != Item::RETRY) {
        Item smallBlindTag = inst.nextTag(1);
        Item bigBlindTag = inst.nextTag(1);

        if (BRAINSTORM_TAG2 == Item::RETRY) {
            if (smallBlindTag != BRAINSTORM_TAG1 && bigBlindTag != BRAINSTORM_TAG1) {
                return 0;
            }
        } else if (BRAINSTORM_TAG1 != BRAINSTORM_TAG2) {
            bool hasTag1 = (smallBlindTag == BRAINSTORM_TAG1 || bigBlindTag == BRAINSTORM_TAG1);
            bool hasTag2 = (smallBlindTag == BRAINSTORM_TAG2 || bigBlindTag == BRAINSTORM_TAG2);
            if (!hasTag1 || !hasTag2) {
                return 0;
            }
        } else {
            if (smallBlindTag != BRAINSTORM_TAG1 || bigBlindTag != BRAINSTORM_TAG1) {
                return 0;
            }
        }
    }

    // Check voucher if specified
    if (BRAINSTORM_VOUCHER != Item::RETRY) {
        inst.initLocks(1, false, false);
        Item firstVoucher = inst.nextVoucher(1);
        if (firstVoucher != BRAINSTORM_VOUCHER) {
            return 0;
        }
    }

    // Check pack if specified
    if (BRAINSTORM_PACK != Item::RETRY) {
        inst.cache.generatedFirstPack = true;
        if (inst.nextPack(1) != BRAINSTORM_PACK) {
            return 0;
        }
    }

    // Check special conditions
    if (BRAINSTORM_OBSERVATORY) {
        inst.initLocks(1, false, false);
        Item firstVoucher = inst.nextVoucher(1);
        if (firstVoucher != Item::Telescope) {
            return 0;
        }
        inst.cache.generatedFirstPack = true;
        Item pack = inst.nextPack(1);
        if (pack != Item::Mega_Celestial_Pack) {
            return 0;
        }
    }

    if (BRAINSTORM_PERKEO) {
        Item smallBlindTag = inst.nextTag(1);
        Item bigBlindTag = inst.nextTag(1);

        if (smallBlindTag != Item::Investment_Tag && bigBlindTag != Item::Investment_Tag) {
            return 0;
        }

        auto tarots = inst.nextArcanaPack(5, 1);
        bool found_soul = false;

        for (int t = 0; t < 5; t++) {
            if (tarots[t] == Item::The_Soul) {
                found_soul = true;
                break;
            }
        }

        if (!found_soul) {
            return 0;
        }
    }

    if (BRAINSTORM_SOULS > 0) {
        for (int i = 1; i <= BRAINSTORM_SOULS; i++) {
            auto tarots = inst.nextArcanaPack(5, 1);
            bool found_soul = false;
            for (int t = 0; t < 5; t++) {
                if (tarots[t] == Item::The_Soul) {
                    found_soul = true;
                    break;
                }
            }
            if (!found_soul) {
                return 0;
            }
        }
    }

    return 1;
}

// Main search function - dispatches to GPU or CPU
std::string brainstorm_internal(std::string seed,
                                std::string voucher,
                                std::string pack,
                                std::string tag1,
                                std::string tag2,
                                double souls,
                                bool observatory,
                                bool perkeo) {
    // Set global filters
    BRAINSTORM_VOUCHER = stringToItem(voucher);
    BRAINSTORM_PACK = stringToItem(pack);
    BRAINSTORM_TAG1 = stringToItem(tag1);
    BRAINSTORM_TAG2 = stringToItem(tag2);
    BRAINSTORM_SOULS = souls;
    BRAINSTORM_OBSERVATORY = observatory;
    BRAINSTORM_PERKEO = perkeo;

    // Decide whether to use GPU or CPU
    bool use_gpu = g_cuda_available && g_use_cuda;

#ifdef GPU_ENABLED
    if (use_gpu && g_gpu_searcher) {
        // Use GPU acceleration
        FilterParams params;
        params.tag1 =
            (BRAINSTORM_TAG1 != Item::RETRY) ? static_cast<uint32_t>(BRAINSTORM_TAG1) : 0xFFFFFFFF;
        params.tag2 =
            (BRAINSTORM_TAG2 != Item::RETRY) ? static_cast<uint32_t>(BRAINSTORM_TAG2) : 0xFFFFFFFF;
        params.voucher = (BRAINSTORM_VOUCHER != Item::RETRY)
                             ? static_cast<uint32_t>(BRAINSTORM_VOUCHER)
                             : 0xFFFFFFFF;
        params.pack =
            (BRAINSTORM_PACK != Item::RETRY) ? static_cast<uint32_t>(BRAINSTORM_PACK) : 0xFFFFFFFF;
        params.require_souls = (BRAINSTORM_SOULS > 0);
        params.require_observatory = BRAINSTORM_OBSERVATORY;
        params.require_perkeo = BRAINSTORM_PERKEO;

        std::string result = g_gpu_searcher->search(seed, params);
        if (!result.empty()) {
            return result;
        }
    }
#endif

    // Fall back to CPU implementation
    Search search(filter_cpu, seed, 1, 100000000);
    search.exitOnFind = true;
    return search.search();
}

// C interface for DLL export
extern "C" {
// Main search function with dual tag support
IMMOLATE_API const char* brainstorm(const char* seed,
                                    const char* voucher,
                                    const char* pack,
                                    const char* tag1,
                                    const char* tag2,
                                    double souls,
                                    bool observatory,
                                    bool perkeo) {
    // Initialize GPU on first call
    static bool initialized = false;
    if (!initialized) {
        initialize_gpu_internal();
        initialized = true;
    }

    std::string cpp_seed(seed ? seed : "");
    std::string cpp_voucher(voucher ? voucher : "");
    std::string cpp_pack(pack ? pack : "");
    std::string cpp_tag1(tag1 ? tag1 : "");
    std::string cpp_tag2(tag2 ? tag2 : "");

    std::string result = brainstorm_internal(
        cpp_seed, cpp_voucher, cpp_pack, cpp_tag1, cpp_tag2, souls, observatory, perkeo);

    return strdup(result.c_str());
}

// Get tags for a specific seed
IMMOLATE_API const char* get_tags(const char* seed) {
    std::string cpp_seed(seed);
    Seed s(cpp_seed);
    Instance inst(s);
    Item smallBlindTag = inst.nextTag(1);
    Item bigBlindTag = inst.nextTag(1);

    std::string formatted = itemToString(smallBlindTag) + "|" + itemToString(bigBlindTag);
    return strdup(formatted.c_str());
}

// Free memory allocated by DLL
IMMOLATE_API void free_result(const char* result) {
    free((void*)result);
}

// GPU/CUDA control functions
IMMOLATE_API int get_acceleration_type() {
    // 0 = CPU, 1 = GPU
    return (g_cuda_available && g_use_cuda) ? 1 : 0;
}

IMMOLATE_API const char* get_hardware_info() {
    return g_hardware_info.c_str();
}

IMMOLATE_API void set_use_cuda(bool enable) {
    // Only allow enabling if GPU is actually available
    if (enable && !g_cuda_available) {
        // Try to initialize if we haven't attempted yet
        if (!g_initialization_attempted) {
            initialize_gpu();
        }

        // If still not available after init attempt, reject enable request
        if (!g_cuda_available) {
            return; // Cannot enable CUDA - GPU not available
        }
    }

    g_use_cuda = enable && g_cuda_available;  // Only enable if GPU is actually available

    // CUDA preference updated
}
}
