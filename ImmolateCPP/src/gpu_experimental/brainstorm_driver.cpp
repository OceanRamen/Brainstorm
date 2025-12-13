#include <windows.h>
#include <string>
#include <cstring>
#include <cstdint>
#include <cstdio>
#include <chrono>
#include "gpu/gpu_types.h"

// External functions from gpu_kernel_driver.cpp
extern "C" std::string gpu_search_with_driver(
    const std::string& start_seed_str,
    const FilterParams& params
);

extern "C" void cleanup_gpu_driver();

// External function from gpu_worker_client.cpp
extern "C" std::string gpu_search_with_worker(
    const std::string& start_seed,
    const FilterParams& params,
    uint32_t count
);

// Main DLL entry point - Note: souls is double, observatory and perkeo are bool
extern "C" __declspec(dllexport) 
const char* brainstorm(
    const char* seed,
    const char* voucher,
    const char* pack,
    const char* tag1,
    const char* tag2,
    double souls,        // Changed to double to match FFI definition
    bool observatory,    // Changed to bool to match FFI definition  
    bool perkeo         // Changed to bool to match FFI definition
) {
    // Log entry for debugging
    FILE* log = fopen("C:\\Users\\Krish\\AppData\\Roaming\\Balatro\\Mods\\Brainstorm\\gpu_driver.log", "a");
    if (log) {
        fprintf(log, "\n========================================\n");
        fprintf(log, "[DLL] brainstorm() ENTRY at %lld\n", 
                (long long)std::chrono::duration_cast<std::chrono::milliseconds>(
                    std::chrono::high_resolution_clock::now().time_since_epoch()).count());
        fprintf(log, "[DLL] Parameters:\n");
        fprintf(log, "  seed=%s\n", seed ? seed : "null");
        fprintf(log, "  tag1=%s\n", tag1 ? tag1 : "null");
        fprintf(log, "  tag2=%s\n", tag2 ? tag2 : "null");
        fprintf(log, "  souls=%f\n", souls);
        fprintf(log, "  observatory=%d\n", observatory ? 1 : 0);
        fprintf(log, "  perkeo=%d\n", perkeo ? 1 : 0);
        fprintf(log, "[DLL] Thread ID: %lu\n", GetCurrentThreadId());
        fprintf(log, "[DLL] Process ID: %lu\n", GetCurrentProcessId());
        fflush(log);
    }
    
    try {
        // Convert string parameters to FilterParams
        FilterParams params;
        // For now, just set everything to 0xFFFFFFFF (no filter) to test GPU initialization
        // TODO: Implement proper string to ID conversion for tags/vouchers/packs
        params.tag1 = 0xFFFFFFFF;  // Temporarily disable tag filtering
        params.tag2 = 0xFFFFFFFF;  // Temporarily disable tag filtering
        params.voucher = 0xFFFFFFFF;  // Temporarily disable voucher filtering
        params.pack = 0xFFFFFFFF;  // Temporarily disable pack filtering
        params.require_souls = (souls > 0) ? 1 : 0;  // Convert double to bool
        params.require_observatory = observatory ? 1 : 0;  // Convert bool to uint32_t
        params.require_perkeo = perkeo ? 1 : 0;  // Convert bool to uint32_t
        
        if (log) {
            fprintf(log, "[DLL] FilterParams prepared:\n");
            fprintf(log, "  tag1=%u (0x%X)\n", params.tag1, params.tag1);
            fprintf(log, "  tag2=%u (0x%X)\n", params.tag2, params.tag2);
            fprintf(log, "  voucher=%u\n", params.voucher);
            fprintf(log, "  pack=%u\n", params.pack);
            fprintf(log, "[DLL] Calling gpu_search_with_driver()...\n");
            fflush(log);
        }
        
        // First try in-process GPU driver
        std::string result = gpu_search_with_driver(seed, params);
        
        if (log) {
            fprintf(log, "[DLL] gpu_search_with_driver() returned\n");
            fprintf(log, "[DLL] Result: %s\n", result.empty() ? "EMPTY (no match or GPU failed)" : result.c_str());
            
            if (result.empty()) {
                fprintf(log, "[DLL] In-process GPU failed, trying worker process...\n");
                fflush(log);
            }
        }
        
        // If in-process failed, try worker process
        if (result.empty()) {
            result = gpu_search_with_worker(seed, params, 1000000);
            
            if (log) {
                fprintf(log, "[DLL] gpu_search_with_worker() returned\n");
                fprintf(log, "[DLL] Result: %s\n", result.empty() ? "EMPTY (worker also failed)" : result.c_str());
            }
        }
        
        if (log) {
            fprintf(log, "[DLL] Result length: %zu\n", result.length());
            if (!result.empty()) {
                fprintf(log, "[DLL] SUCCESS: Found matching seed: %s\n", result.c_str());
            }
            fprintf(log, "========================================\n");
            fclose(log);
        }
        
        if (!result.empty()) {
            // Return a copy that the caller can free
            char* result_copy = (char*)malloc(result.size() + 1);
            strcpy(result_copy, result.c_str());
            return result_copy;
        }
    } catch (...) {
        if (log) {
            fprintf(log, "  EXCEPTION in brainstorm()\n");
            fclose(log);
        }
    }
    
    return nullptr;
}

// Free result memory
extern "C" __declspec(dllexport)
void free_result(const char* result) {
    if (result) {
        free((void*)result);
    }
}

// Get hardware info
extern "C" __declspec(dllexport)
const char* get_hardware_info() {
    static char info[256];
    snprintf(info, sizeof(info), "CUDA Driver API (PTX JIT)");
    return info;
}

// Compatibility stub - Driver API always uses GPU with automatic fallback
extern "C" __declspec(dllexport)
void set_use_cuda(bool enable) {
    // No-op: Driver API handles GPU automatically
    // GPU is used if available, falls back to CPU if not
}

// Get acceleration type - 0=CPU, 1=GPU
extern "C" __declspec(dllexport)
int get_acceleration_type() {
    // TODO: Actually detect if GPU is available
    // For now, return 1 to indicate GPU mode (Driver API attempts GPU first)
    return 1;
}

// Get tags for a specific seed - stub for compatibility
extern "C" __declspec(dllexport)
const char* get_tags(const char* seed) {
    // Driver API doesn't implement this function
    // Return empty string for compatibility
    static const char* empty = "";
    return empty;
}

// DLL cleanup
BOOL WINAPI DllMain(HINSTANCE hinstDLL, DWORD fdwReason, LPVOID lpReserved) {
    if (fdwReason == DLL_PROCESS_DETACH) {
        cleanup_gpu_driver();
    }
    return TRUE;
}
