#include "immolate.hpp"
#include "instance.hpp"
#include "items.hpp"
#include "search.hpp"
#include "functions.hpp"
#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <string>

namespace {

struct FilterConfig {
    Item voucher = Item::RETRY;
    Item pack = Item::RETRY;
    Item tag1 = Item::RETRY;
    Item tag2 = Item::RETRY;
    long souls = 0;
    bool observatory = false;
    bool perkeo = false;
};

Item parse_item_or_retry(const std::string& name) {
    if (name.empty()) {
        return Item::RETRY;
    }
    return stringToItem(name);
}

FilterConfig make_config(const std::string& voucher,
                         const std::string& pack,
                         const std::string& tag1,
                         const std::string& tag2,
                         double souls,
                         bool observatory,
                         bool perkeo) {
    FilterConfig cfg;
    cfg.voucher = parse_item_or_retry(voucher);
    cfg.pack = parse_item_or_retry(pack);
    cfg.tag1 = parse_item_or_retry(tag1);
    cfg.tag2 = parse_item_or_retry(tag2);
    cfg.souls = (souls > 0) ? static_cast<long>(souls) : 0;
    cfg.observatory = observatory;
    cfg.perkeo = perkeo;
    return cfg;
}

int apply_filters(Instance& inst, const FilterConfig& cfg) {
    // Tag checks (order agnostic, supports duplicate tag requirement)
    if (cfg.tag1 != Item::RETRY || cfg.tag2 != Item::RETRY) {
        const Item small_blind = inst.nextTag(1);
        const Item big_blind = inst.nextTag(1);

        if (cfg.tag2 == Item::RETRY) {
            if (small_blind != cfg.tag1 && big_blind != cfg.tag1) {
                return 0;
            }
        } else if (cfg.tag1 != cfg.tag2) {
            const bool has_tag1 = small_blind == cfg.tag1 || big_blind == cfg.tag1;
            const bool has_tag2 = small_blind == cfg.tag2 || big_blind == cfg.tag2;
            if (!has_tag1 || !has_tag2) {
                return 0;
            }
        } else {
            // same tag required twice
            if (small_blind != cfg.tag1 || big_blind != cfg.tag1) {
                return 0;
            }
        }
    }

    // Voucher check
    if (cfg.voucher != Item::RETRY) {
        inst.initLocks(1, false, false);
        const Item first_voucher = inst.nextVoucher(1);
        if (first_voucher != cfg.voucher) {
            return 0;
        }
    }

    // Pack check
    if (cfg.pack != Item::RETRY) {
        inst.cache.generatedFirstPack = true;
        if (inst.nextPack(1) != cfg.pack) {
            return 0;
        }
    }

    // Observatory setup (Telescope + Mega Celestial Pack)
    if (cfg.observatory) {
        inst.initLocks(1, false, false);
        if (inst.nextVoucher(1) != Item::Telescope) {
            return 0;
        }
        inst.cache.generatedFirstPack = true;
        if (inst.nextPack(1) != Item::Mega_Celestial_Pack) {
            return 0;
        }
    }

    // Perkeo setup (Investment tag + soul in Arcana)
    if (cfg.perkeo) {
        const Item small_blind = inst.nextTag(1);
        const Item big_blind = inst.nextTag(1);
        if (small_blind != Item::Investment_Tag && big_blind != Item::Investment_Tag) {
            return 0;
        }

        const auto tarots = inst.nextArcanaPack(5, 1);
        const bool found_soul =
            std::any_of(tarots.begin(), tarots.end(), [](Item item) { return item == Item::The_Soul; });
        if (!found_soul) {
            return 0;
        }
    }

    // Soul count requirements (Arcana packs)
    if (cfg.souls > 0) {
        for (long i = 0; i < cfg.souls; ++i) {
            const auto tarots = inst.nextArcanaPack(5, 1);
            const bool found_soul =
                std::any_of(tarots.begin(), tarots.end(), [](Item item) { return item == Item::The_Soul; });
            if (!found_soul) {
                return 0;
            }
        }
    }

    return 1;
}

std::string search_cpu(const std::string& seed, const FilterConfig& cfg) {
    auto filter_fn = [&cfg](Instance& inst) -> int { return apply_filters(inst, cfg); };
    Search search(filter_fn, seed, 1, 100000000);
    search.exitOnFind = true;
    return search.search();
}

}  // namespace

extern "C" {

IMMOLATE_API const char* brainstorm(const char* seed,
                                    const char* voucher,
                                    const char* pack,
                                    const char* tag1,
                                    const char* tag2,
                                    double souls,
                                    bool observatory,
                                    bool perkeo) {
    const std::string cpp_seed(seed ? seed : "");
    const std::string cpp_voucher(voucher ? voucher : "");
    const std::string cpp_pack(pack ? pack : "");
    const std::string cpp_tag1(tag1 ? tag1 : "");
    const std::string cpp_tag2(tag2 ? tag2 : "");

    const FilterConfig cfg =
        make_config(cpp_voucher, cpp_pack, cpp_tag1, cpp_tag2, souls, observatory, perkeo);
    const std::string result = search_cpu(cpp_seed, cfg);

    if (result.empty()) {
        return nullptr;
    }

    char* output = static_cast<char*>(std::malloc(result.size() + 1));
    if (!output) {
        return nullptr;
    }
    std::memcpy(output, result.c_str(), result.size() + 1);
    return output;
}

IMMOLATE_API const char* get_tags(const char* seed) {
    const std::string cpp_seed(seed ? seed : "");
    Seed s(cpp_seed);
    Instance inst(s);
    const Item small = inst.nextTag(1);
    const Item big = inst.nextTag(1);
    const std::string formatted = itemToString(small) + "|" + itemToString(big);
    char* output = static_cast<char*>(std::malloc(formatted.size() + 1));
    if (!output) {
        return nullptr;
    }
    std::memcpy(output, formatted.c_str(), formatted.size() + 1);
    return output;
}

IMMOLATE_API void free_result(const char* result) {
    if (result) {
        std::free(const_cast<char*>(result));
    }
}

IMMOLATE_API int get_acceleration_type() {
    return 0;  // CPU-only build
}

IMMOLATE_API const char* get_hardware_info() {
    static const char kInfo[] = "CPU-only build (CUDA disabled)";
    return kInfo;
}

IMMOLATE_API void set_use_cuda(bool /*enable*/) {
    // No-op for CPU-only build; exists for API compatibility.
}

}  // extern "C"
