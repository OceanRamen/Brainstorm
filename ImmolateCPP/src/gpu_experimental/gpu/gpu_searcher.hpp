#ifndef GPU_SEARCHER_HPP
#define GPU_SEARCHER_HPP

#include <cstdint>
#include <string>

// Filter parameters for GPU kernel
struct FilterParams {
    uint32_t tag1;
    uint32_t tag2;
    uint32_t voucher;
    uint32_t pack;
    bool require_souls;
    bool require_observatory;
    bool require_perkeo;
};

class GPUSearcher {
   private:
    void* d_params;      // Device memory for parameters
    void* d_result;      // Device memory for result
    void* d_found;       // Device memory for found flag
    void* d_rng_tables;  // Device memory for RNG lookup tables

    bool initialized;
    int device_id;

    // Deferred initialization with timeout protection
    bool initialize_deferred();

   public:
    GPUSearcher();
    ~GPUSearcher();

    // Search for matching seed using GPU
    std::string search(const std::string& start_seed, const FilterParams& params);

    // Get GPU capabilities
    int get_compute_capability() const;
    size_t get_memory_size() const;
    int get_sm_count() const;
};

#endif  // GPU_SEARCHER_HPP