#pragma once

// Dynamic CUDA loader for Windows cross-compilation
// Build-time depends only on headers; all functions resolved at runtime.

#ifdef _WIN32
    #include <windows.h>
#else
    #include <dlfcn.h>
#endif

#include <cstdint>
#include <cstring>
#include <iostream>

// Use the REAL CUDA runtime types to avoid ABI/struct mismatches
// This header is platform-agnostic; we do not link against cudart at build time.
#ifdef __CUDACC__
    #include <cuda_runtime_api.h>
#else
    // When building with MinGW without CUDA headers, provide minimal definitions
    // These must match CUDA's exact layout - using official headers is strongly preferred
    #ifdef __has_include
        #if __has_include(<cuda_runtime_api.h>)
            #include <cuda_runtime_api.h>
            #define HAVE_CUDA_HEADERS 1
        #endif
    #endif

    #ifndef HAVE_CUDA_HEADERS
// Minimal CUDA type definitions when headers not available
// These MUST match the exact CUDA runtime definitions
typedef enum cudaError {
    cudaSuccess = 0,
    cudaErrorInvalidValue = 1,
    cudaErrorMemoryAllocation = 2,
    cudaErrorInitializationError = 3,
    cudaErrorInvalidDevice = 101,
    cudaErrorUnknown = 999
} cudaError_t;

typedef enum cudaMemcpyKind {
    cudaMemcpyHostToHost = 0,
    cudaMemcpyHostToDevice = 1,
    cudaMemcpyDeviceToHost = 2,
    cudaMemcpyDeviceToDevice = 3,
    cudaMemcpyDefault = 4
} cudaMemcpyKind;

// Device attributes for safer queries
typedef enum cudaDeviceAttr {
    cudaDevAttrComputeCapabilityMajor = 75,
    cudaDevAttrComputeCapabilityMinor = 76,
    cudaDevAttrMultiProcessorCount = 16,
    cudaDevAttrMaxThreadsPerBlock = 1,
    cudaDevAttrMaxBlockDimX = 2,
    cudaDevAttrMaxBlockDimY = 3,
    cudaDevAttrMaxBlockDimZ = 4,
    cudaDevAttrMaxGridDimX = 5,
    cudaDevAttrMaxGridDimY = 6,
    cudaDevAttrMaxGridDimZ = 7,
    cudaDevAttrTotalConstantMemory = 9,
    cudaDevAttrWarpSize = 10,
    cudaDevAttrMaxPitch = 11,
    cudaDevAttrMaxRegistersPerBlock = 12,
    cudaDevAttrClockRate = 13,
    cudaDevAttrTextureAlignment = 14,
    cudaDevAttrGpuOverlap = 15,
    cudaDevAttrKernelExecTimeout = 17,
    cudaDevAttrIntegrated = 18,
    cudaDevAttrCanMapHostMemory = 19,
    cudaDevAttrComputeMode = 20,
    cudaDevAttrConcurrentKernels = 31,
    cudaDevAttrEccEnabled = 32,
    cudaDevAttrPciBusId = 33,
    cudaDevAttrPciDeviceId = 34,
    cudaDevAttrMemoryClockRate = 36,
    cudaDevAttrGlobalMemoryBusWidth = 37,
    cudaDevAttrL2CacheSize = 38,
    cudaDevAttrMaxThreadsPerMultiProcessor = 39,
    cudaDevAttrUnifiedAddressing = 41,
    cudaDevAttrPciDomainId = 50
} cudaDeviceAttr;

// Minimal cudaDeviceProp struct - DO NOT USE unless absolutely necessary
// The actual struct layout varies between CUDA versions
struct cudaDeviceProp {
    char name[256];
    size_t totalGlobalMem;
    size_t sharedMemPerBlock;
    int regsPerBlock;
    int warpSize;
    size_t memPitch;
    int maxThreadsPerBlock;
    int maxThreadsDim[3];
    int maxGridSize[3];
    int clockRate;
    size_t totalConstMem;
    int major;
    int minor;
    // ... many more fields that vary by version
    // This is why we should avoid using the struct directly!
};
    #endif  // !HAVE_CUDA_HEADERS
#endif      // !__CUDACC__

// Undefine any macros that might conflict
#ifdef cudaGetDeviceProperties
    #undef cudaGetDeviceProperties
#endif

// Function pointers for CUDA runtime API
typedef cudaError_t (*cudaMalloc_t)(void**, size_t);
typedef cudaError_t (*cudaFree_t)(void*);
typedef cudaError_t (*cudaMemcpy_t)(void*, const void*, size_t, cudaMemcpyKind);
typedef cudaError_t (*cudaGetDeviceCount_t)(int*);
typedef cudaError_t (*cudaGetDeviceProperties_t)(cudaDeviceProp*, int);
typedef cudaError_t (*cudaSetDevice_t)(int);
typedef cudaError_t (*cudaDeviceSynchronize_t)(void);
typedef cudaError_t (*cudaGetLastError_t)(void);
typedef const char* (*cudaGetErrorString_t)(cudaError_t);
typedef cudaError_t (*cudaDeviceGetAttribute_t)(int*, cudaDeviceAttr, int);
typedef cudaError_t (*cudaGetDeviceProperties_v2_t)(cudaDeviceProp*, int);
typedef cudaError_t (*cudaRuntimeGetVersion_t)(int*);
typedef cudaError_t (*cudaDriverGetVersion_t)(int*);
typedef cudaError_t (*cudaMemGetInfo_t)(size_t*, size_t*);

// New safer function for getting device name
typedef cudaError_t (*cudaDeviceGetName_t)(char*, int, int);

// Dynamic CUDA loader class
class CudaWrapper {
   private:
    void* cuda_handle = nullptr;
    bool initialized = false;

   public:
    // Function pointers
    cudaMalloc_t cudaMalloc = nullptr;
    cudaFree_t cudaFree = nullptr;
    cudaMemcpy_t cudaMemcpy = nullptr;
    cudaGetDeviceCount_t cudaGetDeviceCount = nullptr;
    cudaGetDeviceProperties_t cudaGetDeviceProperties = nullptr;
    cudaGetDeviceProperties_v2_t cudaGetDeviceProperties_v2 = nullptr;
    cudaSetDevice_t cudaSetDevice = nullptr;
    cudaDeviceSynchronize_t cudaDeviceSynchronize = nullptr;
    cudaGetLastError_t cudaGetLastError = nullptr;
    cudaGetErrorString_t cudaGetErrorString = nullptr;
    cudaDeviceGetAttribute_t cudaDeviceGetAttribute = nullptr;
    cudaDeviceGetName_t cudaDeviceGetName = nullptr;
    cudaRuntimeGetVersion_t cudaRuntimeGetVersion = nullptr;
    cudaDriverGetVersion_t cudaDriverGetVersion = nullptr;
    cudaMemGetInfo_t cudaMemGetInfo = nullptr;

    bool init() {
        if (initialized)
            return true;

#ifdef _WIN32
        // Try different CUDA runtime versions
        const char* cuda_libs[] = {"cudart64_12.dll",
                                   "cudart64_11.dll",
                                   "cudart64_110.dll",
                                   "cudart64_10.dll",
                                   "cudart64_100.dll",
                                   "cudart64.dll",
                                   "cudart.dll",
                                   nullptr};

        for (int i = 0; cuda_libs[i] != nullptr; i++) {
            cuda_handle = LoadLibraryA(cuda_libs[i]);
            if (cuda_handle) {
                std::cout << "[GPU] Loaded CUDA runtime: " << cuda_libs[i] << std::endl;
                break;
            }
        }

        if (!cuda_handle) {
            std::cerr << "[GPU] Failed to load any CUDA runtime DLL" << std::endl;
            return false;
        }

        // Load function pointers
        cudaMalloc = (cudaMalloc_t)GetProcAddress((HMODULE)cuda_handle, "cudaMalloc");
        cudaFree = (cudaFree_t)GetProcAddress((HMODULE)cuda_handle, "cudaFree");
        cudaMemcpy = (cudaMemcpy_t)GetProcAddress((HMODULE)cuda_handle, "cudaMemcpy");
        cudaGetDeviceCount =
            (cudaGetDeviceCount_t)GetProcAddress((HMODULE)cuda_handle, "cudaGetDeviceCount");

        // Try v2 first, then fallback to v1
        cudaGetDeviceProperties_v2 = (cudaGetDeviceProperties_v2_t)GetProcAddress(
            (HMODULE)cuda_handle, "cudaGetDeviceProperties_v2");
        cudaGetDeviceProperties = (cudaGetDeviceProperties_t)GetProcAddress(
            (HMODULE)cuda_handle, "cudaGetDeviceProperties");
        if (!cudaGetDeviceProperties && cudaGetDeviceProperties_v2) {
            // Use v2 as v1 if v1 not found
            cudaGetDeviceProperties = (cudaGetDeviceProperties_t)cudaGetDeviceProperties_v2;
        }

        cudaSetDevice = (cudaSetDevice_t)GetProcAddress((HMODULE)cuda_handle, "cudaSetDevice");
        cudaDeviceSynchronize =
            (cudaDeviceSynchronize_t)GetProcAddress((HMODULE)cuda_handle, "cudaDeviceSynchronize");
        cudaGetLastError =
            (cudaGetLastError_t)GetProcAddress((HMODULE)cuda_handle, "cudaGetLastError");
        cudaGetErrorString =
            (cudaGetErrorString_t)GetProcAddress((HMODULE)cuda_handle, "cudaGetErrorString");

        // Safer attribute-based queries
        cudaDeviceGetAttribute = (cudaDeviceGetAttribute_t)GetProcAddress((HMODULE)cuda_handle,
                                                                          "cudaDeviceGetAttribute");
        cudaDeviceGetName =
            (cudaDeviceGetName_t)GetProcAddress((HMODULE)cuda_handle, "cudaDeviceGetName");

        // Version info
        cudaRuntimeGetVersion =
            (cudaRuntimeGetVersion_t)GetProcAddress((HMODULE)cuda_handle, "cudaRuntimeGetVersion");
        cudaDriverGetVersion =
            (cudaDriverGetVersion_t)GetProcAddress((HMODULE)cuda_handle, "cudaDriverGetVersion");
        cudaMemGetInfo = (cudaMemGetInfo_t)GetProcAddress((HMODULE)cuda_handle, "cudaMemGetInfo");

#else
        // For Linux testing
        cuda_handle = dlopen("libcudart.so", RTLD_LAZY);
        if (!cuda_handle) {
            return false;
        }

        cudaMalloc = (cudaMalloc_t)dlsym(cuda_handle, "cudaMalloc");
        cudaFree = (cudaFree_t)dlsym(cuda_handle, "cudaFree");
        cudaMemcpy = (cudaMemcpy_t)dlsym(cuda_handle, "cudaMemcpy");
        cudaGetDeviceCount = (cudaGetDeviceCount_t)dlsym(cuda_handle, "cudaGetDeviceCount");

        cudaGetDeviceProperties_v2 =
            (cudaGetDeviceProperties_v2_t)dlsym(cuda_handle, "cudaGetDeviceProperties_v2");
        cudaGetDeviceProperties =
            (cudaGetDeviceProperties_t)dlsym(cuda_handle, "cudaGetDeviceProperties");
        if (!cudaGetDeviceProperties && cudaGetDeviceProperties_v2) {
            cudaGetDeviceProperties = (cudaGetDeviceProperties_t)cudaGetDeviceProperties_v2;
        }

        cudaSetDevice = (cudaSetDevice_t)dlsym(cuda_handle, "cudaSetDevice");
        cudaDeviceSynchronize =
            (cudaDeviceSynchronize_t)dlsym(cuda_handle, "cudaDeviceSynchronize");
        cudaGetLastError = (cudaGetLastError_t)dlsym(cuda_handle, "cudaGetLastError");
        cudaGetErrorString = (cudaGetErrorString_t)dlsym(cuda_handle, "cudaGetErrorString");
        cudaDeviceGetAttribute =
            (cudaDeviceGetAttribute_t)dlsym(cuda_handle, "cudaDeviceGetAttribute");
        cudaDeviceGetName = (cudaDeviceGetName_t)dlsym(cuda_handle, "cudaDeviceGetName");
        cudaRuntimeGetVersion =
            (cudaRuntimeGetVersion_t)dlsym(cuda_handle, "cudaRuntimeGetVersion");
        cudaDriverGetVersion = (cudaDriverGetVersion_t)dlsym(cuda_handle, "cudaDriverGetVersion");
        cudaMemGetInfo = (cudaMemGetInfo_t)dlsym(cuda_handle, "cudaMemGetInfo");
#endif

        // Check minimum required functions
        if (!cudaMalloc || !cudaFree || !cudaMemcpy || !cudaGetDeviceCount || !cudaSetDevice ||
            !cudaDeviceSynchronize || !cudaGetLastError || !cudaGetErrorString) {
            std::cerr << "[GPU] Failed to load core CUDA functions" << std::endl;
            return false;
        }

        // At least one way to query device info must be present
        bool can_query_device = false;
        if (cudaDeviceGetAttribute && cudaDeviceGetName) {
            std::cout << "[GPU] Using safer attribute-based device queries" << std::endl;
            can_query_device = true;
        } else if (cudaGetDeviceProperties || cudaGetDeviceProperties_v2) {
            std::cout << "[GPU] WARNING: Using struct-based device queries (less safe)"
                      << std::endl;
            can_query_device = true;
        }

        if (!can_query_device) {
            std::cerr << "[GPU] No way to query device properties" << std::endl;
            return false;
        }

        // Log version info if available
        if (cudaRuntimeGetVersion) {
            int runtime_version = 0;
            cudaRuntimeGetVersion(&runtime_version);
            std::cout << "[GPU] CUDA Runtime version: " << runtime_version << std::endl;
        }

        if (cudaDriverGetVersion) {
            int driver_version = 0;
            cudaDriverGetVersion(&driver_version);
            std::cout << "[GPU] CUDA Driver version: " << driver_version << std::endl;
        }

        initialized = true;
        return true;
    }

    void cleanup() {
        if (cuda_handle) {
#ifdef _WIN32
            FreeLibrary((HMODULE)cuda_handle);
#else
            dlclose(cuda_handle);
#endif
            cuda_handle = nullptr;
        }
        initialized = false;
    }

    bool is_available() const { return initialized && cuda_handle != nullptr; }

    ~CudaWrapper() { cleanup(); }
};

// Global CUDA wrapper instance
extern CudaWrapper g_cuda;