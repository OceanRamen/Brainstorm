// GPU Worker Client
// Communicates with external gpu_worker.exe process

#include <windows.h>
#include <string>
#include <sstream>
#include <cstdio>
#include "seed.hpp"
#include "gpu_types.h"

static HANDLE g_worker_process = nullptr;
static HANDLE g_stdin_write = nullptr;
static HANDLE g_stdout_read = nullptr;

bool start_gpu_worker() {
    if (g_worker_process) return true; // Already running
    
    // Create pipes
    SECURITY_ATTRIBUTES sa = {sizeof(SECURITY_ATTRIBUTES), nullptr, TRUE};
    
    HANDLE stdin_read, stdout_write;
    if (!CreatePipe(&stdin_read, &g_stdin_write, &sa, 0) ||
        !CreatePipe(&g_stdout_read, &stdout_write, &sa, 0)) {
        return false;
    }
    
    // Don't inherit wrong ends
    SetHandleInformation(g_stdin_write, HANDLE_FLAG_INHERIT, 0);
    SetHandleInformation(g_stdout_read, HANDLE_FLAG_INHERIT, 0);
    
    // Start worker process
    STARTUPINFOA si = {};
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESTDHANDLES;
    si.hStdInput = stdin_read;
    si.hStdOutput = stdout_write;
    si.hStdError = GetStdHandle(STD_ERROR_HANDLE);
    
    PROCESS_INFORMATION pi = {};
    
    // Try to find gpu_worker.exe in same directory as DLL
    char exe_path[MAX_PATH];
    HMODULE hm = nullptr;
    GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | 
                       GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                       (LPCSTR)&start_gpu_worker, &hm);
    GetModuleFileNameA(hm, exe_path, sizeof(exe_path));
    
    // Replace DLL name with worker exe
    char* last_slash = strrchr(exe_path, '\\');
    if (last_slash) {
        strcpy(last_slash + 1, "gpu_worker.exe");
    }
    
    // Check if exe exists first
    FILE* test = fopen(exe_path, "rb");
    if (!test) {
        // Log error
        FILE* log = fopen("C:\\Users\\Krish\\AppData\\Roaming\\Balatro\\Mods\\Brainstorm\\gpu_worker.log", "a");
        if (log) {
            fprintf(log, "[Client] gpu_worker.exe not found at: %s\n", exe_path);
            fclose(log);
        }
        CloseHandle(stdin_read);
        CloseHandle(stdout_write);
        CloseHandle(g_stdin_write);
        CloseHandle(g_stdout_read);
        g_stdin_write = nullptr;
        g_stdout_read = nullptr;
        return false;
    }
    fclose(test);
    
    if (!CreateProcessA(exe_path, nullptr, nullptr, nullptr, TRUE,
                        0, nullptr, nullptr, &si, &pi)) {  // Removed CREATE_NO_WINDOW for now
        DWORD error = GetLastError();
        CloseHandle(stdin_read);
        CloseHandle(stdout_write);
        CloseHandle(g_stdin_write);
        CloseHandle(g_stdout_read);
        g_stdin_write = nullptr;
        g_stdout_read = nullptr;
        
        // Log error with more detail
        FILE* log = fopen("C:\\Users\\Krish\\AppData\\Roaming\\Balatro\\Mods\\Brainstorm\\gpu_worker.log", "a");
        if (log) {
            fprintf(log, "[Client] Failed to start gpu_worker.exe: %lu\n", error);
            fprintf(log, "[Client] Tried path: %s\n", exe_path);
            
            // Decode specific errors
            if (error == 2) fprintf(log, "[Client] Error: File not found\n");
            else if (error == 3) fprintf(log, "[Client] Error: Path not found\n");
            else if (error == 5) fprintf(log, "[Client] Error: Access denied\n");
            else if (error == 183) fprintf(log, "[Client] Error: File already exists (might be antivirus)\n");
            else if (error == 193) fprintf(log, "[Client] Error: Not a valid Win32 application\n");
            else if (error == 740) fprintf(log, "[Client] Error: Elevation required\n");
            
            fclose(log);
        }
        
        return false;
    }
    
    CloseHandle(stdin_read);
    CloseHandle(stdout_write);
    CloseHandle(pi.hThread);
    
    g_worker_process = pi.hProcess;
    
    // Log success
    FILE* log = fopen("C:\\Users\\Krish\\AppData\\Roaming\\Balatro\\Mods\\Brainstorm\\gpu_worker.log", "a");
    if (log) {
        fprintf(log, "[Client] Started gpu_worker.exe (PID %lu)\n", pi.dwProcessId);
        fclose(log);
    }
    
    return true;
}

void stop_gpu_worker() {
    if (g_worker_process) {
        // Send quit command
        if (g_stdin_write) {
            DWORD written;
            WriteFile(g_stdin_write, "QUIT\n", 5, &written, nullptr);
        }
        
        // Wait briefly then terminate if needed
        if (WaitForSingleObject(g_worker_process, 1000) != WAIT_OBJECT_0) {
            TerminateProcess(g_worker_process, 0);
        }
        
        CloseHandle(g_worker_process);
        g_worker_process = nullptr;
    }
    
    if (g_stdin_write) {
        CloseHandle(g_stdin_write);
        g_stdin_write = nullptr;
    }
    
    if (g_stdout_read) {
        CloseHandle(g_stdout_read);
        g_stdout_read = nullptr;
    }
}

extern "C" std::string gpu_search_with_worker(
    const std::string& start_seed,
    const FilterParams& params,
    uint32_t count = 1000000
) {
    FILE* log = fopen("C:\\Users\\Krish\\AppData\\Roaming\\Balatro\\Mods\\Brainstorm\\gpu_worker.log", "a");
    if (log) {
        fprintf(log, "[Client] gpu_search_with_worker called: %s\n", start_seed.c_str());
        fclose(log);
    }
    
    // Start worker if not running
    if (!start_gpu_worker()) {
        return ""; // Failed to start
    }
    
    // Format request
    char request[256];
    snprintf(request, sizeof(request), "%s %u %u %u %u %u\n",
             start_seed.c_str(),
             params.tag1,
             params.tag2,
             params.voucher,
             params.pack,
             count);
    
    // Send request
    DWORD written;
    if (!WriteFile(g_stdin_write, request, strlen(request), &written, nullptr)) {
        log = fopen("C:\\Users\\Krish\\AppData\\Roaming\\Balatro\\Mods\\Brainstorm\\gpu_worker.log", "a");
        if (log) {
            fprintf(log, "[Client] Failed to write to worker\n");
            fclose(log);
        }
        stop_gpu_worker(); // Restart on next call
        return "";
    }
    
    // Read response
    char response[256];
    DWORD read;
    std::string line;
    
    // Read until we get a line
    while (true) {
        if (!ReadFile(g_stdout_read, response, 1, &read, nullptr) || read == 0) {
            log = fopen("C:\\Users\\Krish\\AppData\\Roaming\\Balatro\\Mods\\Brainstorm\\gpu_worker.log", "a");
            if (log) {
                fprintf(log, "[Client] Failed to read from worker\n");
                fclose(log);
            }
            stop_gpu_worker();
            return "";
        }
        
        if (response[0] == '\n') break;
        line += response[0];
    }
    
    log = fopen("C:\\Users\\Krish\\AppData\\Roaming\\Balatro\\Mods\\Brainstorm\\gpu_worker.log", "a");
    if (log) {
        fprintf(log, "[Client] Worker response: %s\n", line.c_str());
        fclose(log);
    }
    
    // Parse response
    if (line.rfind("FOUND:", 0) == 0) {
        return line.substr(6); // Return seed after "FOUND:"
    }
    
    return ""; // No match or error
}

// Cleanup on DLL unload
struct WorkerCleanup {
    ~WorkerCleanup() {
        stop_gpu_worker();
    }
};
static WorkerCleanup g_cleanup;
