// Minimal CUDA Driver API test harness
// Tests the exact same loader and context management as the DLL
#include "../src/gpu_experimental/gpu/cuda_driver_loader.h"
#include <cstdio>
#include <thread>
#include <sstream>
#include <chrono>

int main() {
    printf("=== CUDA Driver API Probe ===\n");
    printf("Build info:\n");
    printf("  sizeof(void*): %zu\n", sizeof(void*));
    printf("  sizeof(CUdeviceptr): %zu\n", sizeof(CUdeviceptr));
    printf("  Thread ID: %s\n", []{
        std::ostringstream oss;
        oss << std::this_thread::get_id();
        return oss.str();
    }().c_str());
    printf("\n");
    
    CudaDrv drv;
    drv.debug_file = stdout;
    
    printf("[1] Loading nvcuda.dll...\n");
    if (!drv.load()) {
        printf("ERROR: Failed to load CUDA driver\n");
        return 1;
    }
    
    printf("[2] Initializing CUDA...\n");
    auto res = drv.cuInit(0);
    if (res != CUDA_SUCCESS) {
        printf("ERROR: cuInit failed: %s (code %d)\n", drv.getErrorString(res), res);
        return 2;
    }
    
    printf("[3] Getting device count...\n");
    int count = 0;
    res = drv.cuDeviceGetCount(&count);
    if (res != CUDA_SUCCESS) {
        printf("ERROR: cuDeviceGetCount failed: %s (code %d)\n", drv.getErrorString(res), res);
        return 3;
    }
    if (count <= 0) {
        printf("ERROR: No CUDA devices found\n");
        return 3;
    }
    printf("Found %d CUDA device(s)\n", count);
    
    printf("[4] Getting device 0...\n");
    CUdevice dev = 0;
    res = drv.cuDeviceGet(&dev, 0);
    if (res != CUDA_SUCCESS) {
        printf("ERROR: cuDeviceGet failed: %s (code %d)\n", drv.getErrorString(res), res);
        return 4;
    }
    
    char name[256] = {0};
    res = drv.cuDeviceGetName(name, sizeof(name), dev);
    if (res == CUDA_SUCCESS) {
        printf("Device 0: %s\n", name);
    }
    
    printf("[5] Retaining primary context...\n");
    CUcontext ctx = nullptr;
    res = drv.cuDevicePrimaryCtxRetain(&ctx, dev);
    if (res != CUDA_SUCCESS) {
        printf("ERROR: cuDevicePrimaryCtxRetain failed: %s (code %d)\n", drv.getErrorString(res), res);
        printf("Trying cuCtxCreate as fallback...\n");
        res = drv.cuCtxCreate(&ctx, 0, dev);
        if (res != CUDA_SUCCESS) {
            printf("ERROR: cuCtxCreate failed: %s (code %d)\n", drv.getErrorString(res), res);
            return 5;
        }
    }
    printf("Context: %p\n", ctx);
    
    printf("[6] Setting context as current...\n");
    res = drv.cuCtxSetCurrent(ctx);
    if (res != CUDA_SUCCESS) {
        printf("ERROR: cuCtxSetCurrent failed: %s (code %d)\n", drv.getErrorString(res), res);
        return 6;
    }
    
    printf("[7] Verifying current context...\n");
    if (drv.cuCtxGetCurrent) {
        CUcontext current = nullptr;
        res = drv.cuCtxGetCurrent(&current);
        if (res == CUDA_SUCCESS) {
            printf("Current context: %p (expected: %p)\n", current, ctx);
            if (current != ctx) {
                printf("WARNING: Context mismatch!\n");
            }
        } else {
            printf("WARNING: cuCtxGetCurrent failed: %s (code %d)\n", drv.getErrorString(res), res);
        }
    }
    
    printf("[8] Pushing context...\n");
    if (drv.cuCtxPushCurrent) {
        res = drv.cuCtxPushCurrent(ctx);
        if (res != CUDA_SUCCESS) {
            printf("WARNING: cuCtxPushCurrent failed: %s (code %d)\n", drv.getErrorString(res), res);
            printf("Continuing anyway...\n");
        } else {
            printf("Context pushed successfully\n");
        }
    }
    
    printf("[9] Allocating 4 bytes...\n");
    CUdeviceptr d = 0;
    res = drv.cuMemAlloc(&d, 4);
    if (res != CUDA_SUCCESS) {
        printf("ERROR: cuMemAlloc failed: %s (code %d)\n", drv.getErrorString(res), res);
        
        // Try to get more info
        if (drv.cuCtxGetCurrent) {
            CUcontext current = nullptr;
            drv.cuCtxGetCurrent(&current);
            printf("Current context at failure: %p\n", current);
        }
        return 7;
    }
    printf("Allocated at: 0x%llx\n", (unsigned long long)d);
    
    printf("[10] Writing data...\n");
    unsigned int value = 0x12345678;
    res = drv.cuMemcpyHtoD(d, &value, 4);
    if (res != CUDA_SUCCESS) {
        printf("ERROR: cuMemcpyHtoD failed: %s (code %d)\n", drv.getErrorString(res), res);
        drv.cuMemFree(d);
        return 8;
    }
    
    printf("[11] Reading data back...\n");
    unsigned int readback = 0;
    res = drv.cuMemcpyDtoH(&readback, d, 4);
    if (res != CUDA_SUCCESS) {
        printf("ERROR: cuMemcpyDtoH failed: %s (code %d)\n", drv.getErrorString(res), res);
        drv.cuMemFree(d);
        return 9;
    }
    
    if (readback != value) {
        printf("ERROR: Data mismatch! Written: 0x%08x, Read: 0x%08x\n", value, readback);
        drv.cuMemFree(d);
        return 10;
    }
    printf("Data verified: 0x%08x\n", readback);
    
    printf("[12] Freeing memory...\n");
    res = drv.cuMemFree(d);
    if (res != CUDA_SUCCESS) {
        printf("ERROR: cuMemFree failed: %s (code %d)\n", drv.getErrorString(res), res);
        return 11;
    }
    
    printf("[13] Popping context...\n");
    if (drv.cuCtxPopCurrent) {
        CUcontext popped = nullptr;
        res = drv.cuCtxPopCurrent(&popped);
        if (res != CUDA_SUCCESS) {
            printf("WARNING: cuCtxPopCurrent failed: %s (code %d)\n", drv.getErrorString(res), res);
        } else {
            printf("Popped context: %p\n", popped);
        }
    }
    
    printf("\n=== SUCCESS ===\n");
    printf("All CUDA Driver API operations completed successfully!\n");
    
    // Cleanup
    if (drv.cuDevicePrimaryCtxRelease) {
        drv.cuDevicePrimaryCtxRelease(dev);
    }
    drv.unload();
    
    return 0;
}
