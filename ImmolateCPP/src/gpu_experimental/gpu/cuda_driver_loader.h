#pragma once
#ifdef _WIN32
#include <windows.h>
#endif
#include <stdint.h>
#include <cstdio>
#include <type_traits>

// CUDA Driver API calling convention on Windows
#ifndef CUDAAPI
#if defined(_WIN64)
#define CUDAAPI  // __stdcall is ignored on Win64
#elif defined(_WIN32)
#define CUDAAPI __stdcall
#else
#define CUDAAPI
#endif
#endif

// Minimal CUDA Driver API types
typedef int CUdevice;
typedef struct CUctx_st* CUcontext;
typedef struct CUmod_st* CUmodule;
typedef struct CUfunc_st* CUfunction;
typedef struct CUstream_st* CUstream;
typedef unsigned long long CUdeviceptr;

typedef enum {
    CUDA_SUCCESS = 0,
    CUDA_ERROR_INVALID_VALUE = 1,
    CUDA_ERROR_OUT_OF_MEMORY = 2,
    CUDA_ERROR_NOT_INITIALIZED = 3,
    CUDA_ERROR_DEINITIALIZED = 4,
    CUDA_ERROR_NO_DEVICE = 100,
    CUDA_ERROR_INVALID_DEVICE = 101,
    CUDA_ERROR_INVALID_IMAGE = 200,
    CUDA_ERROR_INVALID_CONTEXT = 201,
    CUDA_ERROR_FILE_NOT_FOUND = 301,
    CUDA_ERROR_NOT_FOUND = 500,
    CUDA_ERROR_NOT_READY = 600,
    CUDA_ERROR_LAUNCH_FAILED = 719,
    CUDA_ERROR_LAUNCH_TIMEOUT = 702,
    CUDA_ERROR_LAUNCH_OUT_OF_RESOURCES = 701,
    CUDA_ERROR_UNKNOWN = 999
} CUresult;

// Function pointer types for CUDA Driver API
typedef CUresult (CUDAAPI *PFN_cuInit)(unsigned int);
typedef CUresult (CUDAAPI *PFN_cuDeviceGet)(CUdevice*, int);
typedef CUresult (CUDAAPI *PFN_cuDeviceGetCount)(int*);
typedef CUresult (CUDAAPI *PFN_cuDeviceGetName)(char*, int, CUdevice);
typedef CUresult (CUDAAPI *PFN_cuDevicePrimaryCtxRetain)(CUcontext*, CUdevice);
typedef CUresult (CUDAAPI *PFN_cuDevicePrimaryCtxRelease)(CUdevice);
typedef CUresult (CUDAAPI *PFN_cuCtxCreate)(CUcontext*, unsigned int, CUdevice);
typedef CUresult (CUDAAPI *PFN_cuCtxDestroy)(CUcontext);
typedef CUresult (CUDAAPI *PFN_cuCtxSetCurrent)(CUcontext);
typedef CUresult (CUDAAPI *PFN_cuCtxGetCurrent)(CUcontext*);
typedef CUresult (CUDAAPI *PFN_cuCtxPushCurrent)(CUcontext);
typedef CUresult (CUDAAPI *PFN_cuCtxPopCurrent)(CUcontext*);
typedef CUresult (CUDAAPI *PFN_cuModuleLoadDataEx)(CUmodule*, const void*, unsigned int, void*, void*);
typedef CUresult (CUDAAPI *PFN_cuModuleGetFunction)(CUfunction*, CUmodule, const char*);
typedef CUresult (CUDAAPI *PFN_cuMemAlloc)(CUdeviceptr*, size_t);
typedef CUresult (CUDAAPI *PFN_cuMemFree)(CUdeviceptr);
typedef CUresult (CUDAAPI *PFN_cuMemcpyHtoD)(CUdeviceptr, const void*, size_t);
typedef CUresult (CUDAAPI *PFN_cuMemcpyDtoH)(void*, CUdeviceptr, size_t);
typedef CUresult (CUDAAPI *PFN_cuMemsetD32)(CUdeviceptr, unsigned int, size_t);
typedef CUresult (CUDAAPI *PFN_cuLaunchKernel)(CUfunction, 
                                               unsigned, unsigned, unsigned,  // grid
                                               unsigned, unsigned, unsigned,  // block
                                               unsigned, CUstream,            // shared mem, stream
                                               void**, void**);               // kernel params, extra
typedef CUresult (CUDAAPI *PFN_cuCtxSynchronize)(void);
typedef CUresult (CUDAAPI *PFN_cuModuleUnload)(CUmodule);
typedef CUresult (CUDAAPI *PFN_cuGetErrorString)(CUresult, const char**);
typedef CUresult (CUDAAPI *PFN_cuGetErrorName)(CUresult, const char**);

// CUDA Driver API loader structure
struct CudaDrv {
#ifdef _WIN32
    HMODULE h = nullptr;
#else
    void* h = nullptr;
#endif
    
    // Function pointers
    PFN_cuInit cuInit = nullptr;
    PFN_cuDeviceGet cuDeviceGet = nullptr;
    PFN_cuDeviceGetCount cuDeviceGetCount = nullptr;
    PFN_cuDeviceGetName cuDeviceGetName = nullptr;
    PFN_cuDevicePrimaryCtxRetain cuDevicePrimaryCtxRetain = nullptr;
    PFN_cuDevicePrimaryCtxRelease cuDevicePrimaryCtxRelease = nullptr;
    PFN_cuCtxCreate cuCtxCreate = nullptr;
    PFN_cuCtxDestroy cuCtxDestroy = nullptr;
    PFN_cuCtxSetCurrent cuCtxSetCurrent = nullptr;
    PFN_cuCtxGetCurrent cuCtxGetCurrent = nullptr;
    PFN_cuCtxPushCurrent cuCtxPushCurrent = nullptr;
    PFN_cuCtxPopCurrent cuCtxPopCurrent = nullptr;
    PFN_cuModuleLoadDataEx cuModuleLoadDataEx = nullptr;
    PFN_cuModuleGetFunction cuModuleGetFunction = nullptr;
    PFN_cuMemAlloc cuMemAlloc = nullptr;
    PFN_cuMemFree cuMemFree = nullptr;
    PFN_cuMemcpyHtoD cuMemcpyHtoD = nullptr;
    PFN_cuMemcpyDtoH cuMemcpyDtoH = nullptr;
    PFN_cuMemsetD32 cuMemsetD32 = nullptr;
    PFN_cuLaunchKernel cuLaunchKernel = nullptr;
    PFN_cuCtxSynchronize cuCtxSynchronize = nullptr;
    PFN_cuModuleUnload cuModuleUnload = nullptr;
    PFN_cuGetErrorString cuGetErrorString = nullptr;
    PFN_cuGetErrorName cuGetErrorName = nullptr;
    
    // Debug logging file
    FILE* debug_file = nullptr;
    
    bool load() {
#ifdef _WIN32
        h = LoadLibraryA("nvcuda.dll");
        if (!h) {
            if (debug_file) fprintf(debug_file, "[CUDA Driver] Failed to load nvcuda.dll\n");
            return false;
        }
        
        auto Q = [&](auto& fp, const char* name) {
            fp = reinterpret_cast<std::remove_reference_t<decltype(fp)>>(GetProcAddress(h, name));
            if (!fp && debug_file) {
                fprintf(debug_file, "[CUDA Driver] Failed to get function: %s\n", name);
            }
            return fp != nullptr;
        };
        
        // For v2 functions: try v2 first, then fallback to legacy
        auto Qv2 = [&](auto& fp, const char* name_v2, const char* name_legacy) {
            fp = reinterpret_cast<std::remove_reference_t<decltype(fp)>>(GetProcAddress(h, name_v2));
            if (fp) {
                if (debug_file) fprintf(debug_file, "[CUDA Driver] Bound %s\n", name_v2);
                return true;
            }
            fp = reinterpret_cast<std::remove_reference_t<decltype(fp)>>(GetProcAddress(h, name_legacy));
            if (fp) {
                if (debug_file) fprintf(debug_file, "[CUDA Driver] Bound %s (legacy)\n", name_legacy);
                return true;
            }
            if (debug_file) {
                fprintf(debug_file, "[CUDA Driver] Failed to get function: %s or %s\n", name_v2, name_legacy);
            }
            return false;
        };
#else
        // Linux/WSL2 path (for testing)
        return false;
#endif
        
        // Load all required functions (use v2 where applicable)
        bool success = Q(cuInit, "cuInit") &&
                      Q(cuDeviceGet, "cuDeviceGet") &&
                      Q(cuDeviceGetCount, "cuDeviceGetCount") &&
                      Q(cuDeviceGetName, "cuDeviceGetName") &&
                      Q(cuDevicePrimaryCtxRetain, "cuDevicePrimaryCtxRetain") &&
                      Q(cuDevicePrimaryCtxRelease, "cuDevicePrimaryCtxRelease") &&
                      Qv2(cuCtxCreate, "cuCtxCreate_v2", "cuCtxCreate") &&
                      Qv2(cuCtxDestroy, "cuCtxDestroy_v2", "cuCtxDestroy") &&
                      Q(cuCtxSetCurrent, "cuCtxSetCurrent") &&
                      Q(cuModuleLoadDataEx, "cuModuleLoadDataEx") &&
                      Q(cuModuleGetFunction, "cuModuleGetFunction") &&
                      Qv2(cuMemAlloc, "cuMemAlloc_v2", "cuMemAlloc") &&
                      Qv2(cuMemFree, "cuMemFree_v2", "cuMemFree") &&
                      Qv2(cuMemcpyHtoD, "cuMemcpyHtoD_v2", "cuMemcpyHtoD") &&
                      Qv2(cuMemcpyDtoH, "cuMemcpyDtoH_v2", "cuMemcpyDtoH") &&
                      Qv2(cuMemsetD32, "cuMemsetD32_v2", "cuMemsetD32") &&
                      Q(cuLaunchKernel, "cuLaunchKernel") &&
                      Q(cuCtxSynchronize, "cuCtxSynchronize") &&
                      Q(cuModuleUnload, "cuModuleUnload");
        
        // Optional error functions
        Q(cuGetErrorString, "cuGetErrorString");
        Q(cuGetErrorName, "cuGetErrorName");
        
        // Optional context management functions
        Q(cuCtxGetCurrent, "cuCtxGetCurrent");
        Q(cuCtxPushCurrent, "cuCtxPushCurrent");
        Q(cuCtxPopCurrent, "cuCtxPopCurrent");
        
        if (debug_file && success) {
            fprintf(debug_file, "[CUDA Driver] Successfully loaded all required functions\n");
        }
        
        return success;
    }
    
    void unload() {
#ifdef _WIN32
        if (h) {
            FreeLibrary(h);
            h = nullptr;
        }
#endif
    }
    
    const char* getErrorString(CUresult err) {
        if (cuGetErrorString) {
            const char* str = nullptr;
            if (cuGetErrorString(err, &str) == CUDA_SUCCESS && str) {
                return str;
            }
        }
        
        // Fallback for common errors
        switch (err) {
            case CUDA_SUCCESS: return "CUDA_SUCCESS";
            case CUDA_ERROR_INVALID_VALUE: return "CUDA_ERROR_INVALID_VALUE";
            case CUDA_ERROR_OUT_OF_MEMORY: return "CUDA_ERROR_OUT_OF_MEMORY";
            case CUDA_ERROR_NOT_INITIALIZED: return "CUDA_ERROR_NOT_INITIALIZED";
            case CUDA_ERROR_NO_DEVICE: return "CUDA_ERROR_NO_DEVICE";
            case CUDA_ERROR_INVALID_DEVICE: return "CUDA_ERROR_INVALID_DEVICE";
            case CUDA_ERROR_INVALID_CONTEXT: return "CUDA_ERROR_INVALID_CONTEXT";
            case CUDA_ERROR_FILE_NOT_FOUND: return "CUDA_ERROR_FILE_NOT_FOUND";
            case CUDA_ERROR_NOT_FOUND: return "CUDA_ERROR_NOT_FOUND";
            case CUDA_ERROR_LAUNCH_FAILED: return "CUDA_ERROR_LAUNCH_FAILED";
            case CUDA_ERROR_LAUNCH_TIMEOUT: return "CUDA_ERROR_LAUNCH_TIMEOUT";
            case CUDA_ERROR_LAUNCH_OUT_OF_RESOURCES: return "CUDA_ERROR_LAUNCH_OUT_OF_RESOURCES";
            default: return "CUDA_ERROR_UNKNOWN";
        }
    }
};