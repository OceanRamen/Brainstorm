#pragma once
#include <stdint.h>

#if defined(__CUDACC__)
#define GPU_HOST_DEVICE __host__ __device__
#else
#define GPU_HOST_DEVICE
#endif

// Force 4-byte fields to avoid ABI surprises between host and device
// All fields are uint32_t for consistent alignment and size
struct FilterParams {
    uint32_t tag1;           // Tag ID or 0xFFFFFFFF for none
    uint32_t tag2;           // Second tag ID or 0xFFFFFFFF for none  
    uint32_t voucher;        // Voucher ID or 0xFFFFFFFF for none
    uint32_t pack;           // Pack ID or 0xFFFFFFFF for none
    uint32_t require_souls;  // 1 if souls required, 0 otherwise
    uint32_t require_observatory;  // 1 if observatory required, 0 otherwise
    uint32_t require_perkeo; // 1 if perkeo required, 0 otherwise
};

// Ensure consistent size across compilers
static_assert(sizeof(FilterParams) == 28, "FilterParams size mismatch");

// Debug statistics structure (optional)
struct DebugStats {
    uint64_t seeds_tested;
    uint64_t tag_matches;
    uint64_t tag_rejections;
    uint64_t voucher_matches;
    uint64_t voucher_rejections;
    uint64_t pack_matches;
    uint64_t pack_rejections;
    uint64_t observatory_matches;
    uint64_t observatory_rejections;
    uint64_t total_matches;
};

static_assert(sizeof(DebugStats) == 80, "DebugStats size mismatch");