// CUDA kernel for GPU-accelerated seed filtering
// Pure device code - no host runtime dependencies

#include <stdint.h>

// GPU-compatible RNG implementation matching Balatro's algorithm
__device__ uint32_t pseudoseed_device(const char* key, int len) {
    uint32_t hash = 2166136261u;
    for (int i = 0; i < len; i++) {
        hash ^= (uint32_t)key[i];
        hash *= 16777619u;
    }
    return hash;
}

__device__ double pseudorandom_device(uint32_t seed, const char* context) {
    // Combine seed with context string
    int ctx_len = 0;
    while (context[ctx_len]) ctx_len++;
    
    uint32_t combined = seed;
    for (int i = 0; i < ctx_len; i++) {
        combined = combined * 31u + (uint32_t)context[i];
    }
    
    // PCG-like algorithm
    uint64_t state = combined;
    state = state * 6364136223846793005ULL + 1442695040888963407ULL;
    uint32_t xorshifted = ((state >> 18u) ^ state) >> 27u;
    uint32_t rot = state >> 59u;
    uint32_t result = (xorshifted >> rot) | (xorshifted << ((-rot) & 31));
    
    return (double)result / 4294967296.0;
}

// Filter parameters structure (must match host)
struct FilterParams {
    uint32_t tag1;
    uint32_t tag2;
    uint32_t voucher;
    uint32_t pack;
    float min_souls;
    uint32_t observatory;
    uint32_t perkeo;
};

// Debug statistics
struct DebugStats {
    uint64_t seeds_tested;
    uint64_t tag_matches;
    uint64_t voucher_matches;
    uint64_t pack_matches;
    uint64_t souls_matches;
    uint64_t total_matches;
    uint32_t thread_id;
    uint32_t block_id;
};

// Main kernel function - searches for matching seeds
extern "C" __global__ void find_seeds_kernel(
    uint64_t start_seed,
    uint32_t count,
    const FilterParams* params,
    uint64_t* result,
    volatile int* found,
    DebugStats* debug_stats
) {
    uint32_t tid = blockIdx.x * blockDim.x + threadIdx.x;
    uint32_t stride = blockDim.x * gridDim.x;
    
    // Early exit if another thread found a match
    if (*found) return;
    
    // Process seeds in strided pattern for coalesced memory access
    for (uint32_t i = tid; i < count && !(*found); i += stride) {
        uint64_t seed_num = start_seed + i;
        
        // Convert seed number to string (8 chars, A-Z)
        char seed_str[9];
        uint64_t temp = seed_num;
        for (int j = 7; j >= 0; j--) {
            seed_str[j] = 'A' + (temp % 26);
            temp /= 26;
        }
        seed_str[8] = '\0';
        
        // Check tags if specified
        if (params->tag1 != 0xFFFFFFFF) {
            // Generate ante 1 tags using RNG
            uint32_t seed_hash = pseudoseed_device(seed_str, 8);
            
            // Small blind tag
            double rng1 = pseudorandom_device(seed_hash, "Tag_Small_1");
            uint32_t small_tag = (uint32_t)(rng1 * 30);  // 30 possible tags
            
            // Big blind tag  
            double rng2 = pseudorandom_device(seed_hash, "Tag_Big_1");
            uint32_t big_tag = (uint32_t)(rng2 * 30);
            
            bool match = false;
            if (params->tag2 == 0xFFFFFFFF) {
                // Single tag - must appear on either blind
                match = (small_tag == params->tag1 || big_tag == params->tag1);
            } else if (params->tag1 == params->tag2) {
                // Same tag twice - must appear on both blinds
                match = (small_tag == params->tag1 && big_tag == params->tag1);
            } else {
                // Two different tags - both must appear (order-agnostic)
                bool has_tag1 = (small_tag == params->tag1 || big_tag == params->tag1);
                bool has_tag2 = (small_tag == params->tag2 || big_tag == params->tag2);
                match = has_tag1 && has_tag2;
            }
            
            if (!match) continue;
            
            // Track statistics
            if (debug_stats) {
                atomicAdd((unsigned long long*)&debug_stats->tag_matches, 1ULL);
            }
        }
        
        // Check voucher if specified
        if (params->voucher != 0xFFFFFFFF) {
            uint32_t seed_hash = pseudoseed_device(seed_str, 8);
            double rng = pseudorandom_device(seed_hash, "Voucher_1");
            uint32_t voucher = (uint32_t)(rng * 32);  // 32 possible vouchers
            
            if (voucher != params->voucher) continue;
            
            if (debug_stats) {
                atomicAdd((unsigned long long*)&debug_stats->voucher_matches, 1ULL);
            }
        }
        
        // Check pack if specified
        if (params->pack != 0xFFFFFFFF) {
            uint32_t seed_hash = pseudoseed_device(seed_str, 8);
            double rng = pseudorandom_device(seed_hash, "Pack_1");
            uint32_t pack = (uint32_t)(rng * 8);  // 8 possible packs
            
            if (pack != params->pack) continue;
            
            if (debug_stats) {
                atomicAdd((unsigned long long*)&debug_stats->pack_matches, 1ULL);
            }
        }
        
        // Found a match! Try to claim it atomically
        int old = atomicCAS((int*)found, 0, 1);
        if (old == 0) {
            // We won the race, store the result
            *result = start_seed + i;
            
            if (debug_stats) {
                atomicAdd((unsigned long long*)&debug_stats->total_matches, 1ULL);
                debug_stats->thread_id = tid;
                debug_stats->block_id = blockIdx.x;
            }
        }
    }
    
    // Update total seeds tested (only thread 0)
    if (debug_stats && tid == 0) {
        atomicAdd((unsigned long long*)&debug_stats->seeds_tested, (unsigned long long)count);
    }
}