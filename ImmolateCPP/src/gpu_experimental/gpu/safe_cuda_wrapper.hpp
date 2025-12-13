#pragma once

#include <iostream>
#include <memory>
#include <string>

#ifdef _WIN32
    #include <windows.h>
#endif

// Safe CUDA wrapper that gracefully handles initialization failures
class SafeCudaWrapper {
   private:
    bool cuda_available = false;
    bool init_attempted = false;
    std::string error_message;

#ifdef _WIN32
    HMODULE cuda_handle = nullptr;
    HMODULE cudart_handle = nullptr;
#endif

    // Function pointers for CUDA runtime
    void* (*cuda_malloc_ptr)(size_t) = nullptr;
    void (*cuda_free_ptr)(void*) = nullptr;
    void* (*cuda_memcpy_ptr)(void*, const void*, size_t, int) = nullptr;
    int (*cuda_get_device_count_ptr)(int*) = nullptr;
    int (*cuda_set_device_ptr)(int) = nullptr;
    const char* (*cuda_get_error_string_ptr)(int) = nullptr;

   public:
    SafeCudaWrapper() = default;

    ~SafeCudaWrapper() {
#ifdef _WIN32
        if (cuda_handle) {
            FreeLibrary(cuda_handle);
        }
        if (cudart_handle) {
            FreeLibrary(cudart_handle);
        }
#endif
    }

    bool initialize() {
        if (init_attempted) {
            return cuda_available;
        }
        init_attempted = true;

#ifdef _WIN32
        // Try to load CUDA runtime DLL
        // Try multiple possible paths
        const char* cuda_dlls[] = {
            "cudart64_12.dll",
            "cudart64_11.dll",
            "cudart64_10.dll",
            "C:\\Program Files\\NVIDIA GPU Computing Toolkit\\CUDA\\v12.6\\bin\\cudart64_12.dll",
            "C:\\Program Files\\NVIDIA GPU Computing Toolkit\\CUDA\\v11.8\\bin\\cudart64_11.dll"};

        for (const auto& dll_path : cuda_dlls) {
            cudart_handle = LoadLibraryA(dll_path);
            if (cudart_handle) {
                break;
            }
        }

        if (!cudart_handle) {
            error_message = "CUDA runtime DLL not found. GPU acceleration disabled.";
            return false;
        }

        // Load function pointers safely
        cuda_get_device_count_ptr =
            (int (*)(int*))GetProcAddress(cudart_handle, "cudaGetDeviceCount");
        if (!cuda_get_device_count_ptr) {
            error_message = "Failed to load CUDA functions. GPU acceleration disabled.";
            FreeLibrary(cudart_handle);
            cudart_handle = nullptr;
            return false;
        }

        // Test CUDA availability
        int device_count = 0;
        int result = cuda_get_device_count_ptr(&device_count);

        if (result != 0 || device_count == 0) {
            error_message = "No CUDA devices found. GPU acceleration disabled.";
            FreeLibrary(cudart_handle);
            cudart_handle = nullptr;
            return false;
        }

        cuda_available = true;
        return true;
#else
        error_message = "CUDA not supported on this platform";
        return false;
#endif
    }

    bool is_available() const { return cuda_available; }

    const std::string& get_error() const { return error_message; }

    // Safe wrapper for CUDA operations
    template <typename Func>
    bool safe_cuda_call(Func&& func, const std::string& operation) {
        if (!cuda_available) {
            return false;
        }

        try {
            func();
            return true;
        } catch (...) {
            error_message = "CUDA operation failed: " + operation;
            // Disable CUDA for future calls
            cuda_available = false;
            return false;
        }
    }
};

// Global instance
inline SafeCudaWrapper& get_cuda_wrapper() {
    static SafeCudaWrapper instance;
    return instance;
}