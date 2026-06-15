#include "functions.hpp"
#include "minijson.hpp"
#include "search.hpp"
#include <cstring>
#include <vector>

#ifdef _WIN32
  #ifdef BUILDING_DLL
    #define IMMOLATE_API __declspec(dllexport)
  #else
    #define IMMOLATE_API __declspec(dllimport)
  #endif
#else
  #define IMMOLATE_API
#endif

Item BRAINSTORM_PACK = Item::RETRY;
Item BRAINSTORM_TAG = Item::Charm_Tag;
long BRAINSTORM_SOULS = 1;

long filter(Instance inst) {
    if (BRAINSTORM_PACK != Item::RETRY) {
        inst.cache.generatedFirstPack = true; // we don't care about Pack 1
        if (inst.nextPack(1) != BRAINSTORM_PACK) {
            return 0;
        }
    }
    if (BRAINSTORM_TAG != Item::RETRY) {
        if (inst.nextTag(1) != BRAINSTORM_TAG) {
            return 0;
        }
    }
    if (BRAINSTORM_SOULS > 0) {
        for (int i = 1; i <= BRAINSTORM_SOULS; i++) {
            auto tarots = inst.nextArcanaPack(5, 1); // Mega Arcana Pack
            bool found_soul = false;
            for (int t = 0; t < 5; t++) {
                if (tarots[t] == Item::The_Soul) {
                    found_soul = true;
                    break;
                }
            }
            if (!found_soul) {
                return 0;
            }
        }
    }
    return 1;
};

IMMOLATE_API std::string brainstorm_cpp(std::string seed, std::string pack,
std::string tag, double souls) { BRAINSTORM_PACK = stringToItem(pack);
    BRAINSTORM_TAG = stringToItem(tag);
    BRAINSTORM_SOULS = souls;
    Search search(filter, seed, 1, 100000000);
    search.exitOnFind = true;
    return search.search();
}

// ---------------------------------------------------------------------------
// Step / filter tree
// ---------------------------------------------------------------------------

struct Step {
    std::string op;
    mini_json::Value args;
    std::vector<Step> subSteps; // used by "all" and "any" combinator ops
};

// ---------------------------------------------------------------------------
// Matching helpers
// ---------------------------------------------------------------------------

static Item parseItemSafe(const mini_json::Value &v) {
    if (!v.isString()) return Item::RETRY;
    return stringToItem(v.getString());
}

// Match a single Item against { "equals": "...", "in": [...] }
static bool matchesItem(Item actual, const mini_json::Value &cond) {
    const auto &eq = cond["equals"];
    if (eq.isString() && actual != parseItemSafe(eq)) return false;
    const auto &inArr = cond["in"];
    if (inArr.isArray()) {
        bool ok = false;
        for (const auto &el : inArr.array)
            if (el.isString() && actual == parseItemSafe(el)) { ok = true; break; }
        if (!ok) return false;
    }
    return true;
}

// Match a JokerData against { "joker": "...", "rarity": "...", "edition": "...", "stickers": {...} }
static bool matchesJoker(const JokerData &jd, const mini_json::Value &cond) {
    if (!cond.isObject()) return true;
    if (cond["joker"].isString()   && jd.joker   != parseItemSafe(cond["joker"]))   return false;
    if (cond["rarity"].isString()  && jd.rarity  != parseItemSafe(cond["rarity"]))  return false;
    if (cond["edition"].isString() && jd.edition != parseItemSafe(cond["edition"])) return false;
    const auto &stickers = cond["stickers"];
    if (stickers.isObject()) {
        if (stickers["eternal"].isBool()     && jd.stickers.eternal     != stickers["eternal"].getBool())     return false;
        if (stickers["perishable"].isBool()  && jd.stickers.perishable  != stickers["perishable"].getBool())  return false;
        if (stickers["rental"].isBool()      && jd.stickers.rental      != stickers["rental"].getBool())      return false;
    }
    return true;
}

// Match a Card against { "base": "...", "enhancement": "...", "edition": "...", "seal": "..." }
static bool matchesCard(const Card &card, const mini_json::Value &cond) {
    if (!cond.isObject()) return true;
    if (cond["base"].isString()        && card.base        != parseItemSafe(cond["base"]))        return false;
    if (cond["enhancement"].isString() && card.enhancement != parseItemSafe(cond["enhancement"])) return false;
    if (cond["edition"].isString()     && card.edition     != parseItemSafe(cond["edition"]))     return false;
    if (cond["seal"].isString()        && card.seal        != parseItemSafe(cond["seal"]))        return false;
    return true;
}

// Match a ShopItem against { "type": "...", "item": "...", "match": {joker cond} }
static bool matchesShopItem(const ShopItem &si, const mini_json::Value &cond) {
    if (!cond.isObject()) return true;
    if (cond["type"].isString() && si.type != parseItemSafe(cond["type"])) return false;
    if (cond["item"].isString() && si.item != parseItemSafe(cond["item"])) return false;
    if (cond["match"].isObject() && !matchesJoker(si.jokerData, cond["match"])) return false;
    return true;
}

static long long getNumber(const mini_json::Value &v, long long def) {
    return v.isNumber() ? static_cast<long long>(v.number) : def;
}

// Apply any/all/none/count sub-conditions over a vector<Item> pack.
// Sub-conditions use the same { "equals"/"in" } format as matchesItem.
static bool matchesItemPack(const std::vector<Item> &items, const mini_json::Value &args) {
    const auto &anyCond = args["any"];
    if (anyCond.isObject()) {
        bool found = false;
        for (const auto &item : items)
            if (matchesItem(item, anyCond)) { found = true; break; }
        if (!found) return false;
    }
    const auto &allCond = args["all"];
    if (allCond.isObject()) {
        for (const auto &item : items)
            if (!matchesItem(item, allCond)) return false;
    }
    const auto &noneCond = args["none"];
    if (noneCond.isObject()) {
        for (const auto &item : items)
            if (matchesItem(item, noneCond)) return false;
    }
    const auto &countCond = args["count"];
    if (countCond.isObject()) {
        const auto &matchCond = countCond["match"];
        int cnt = 0;
        for (const auto &item : items)
            if (!matchCond.isObject() || matchesItem(item, matchCond)) cnt++;
        long long minV = getNumber(countCond["min"], -1);
        long long maxV = getNumber(countCond["max"], -1);
        long long eqV  = getNumber(countCond["equals"], -1);
        if (minV >= 0 && cnt < (int)minV) return false;
        if (maxV >= 0 && cnt > (int)maxV) return false;
        if (eqV  >= 0 && cnt != (int)eqV)  return false;
    }
    return true;
}

// Apply any/all/none/count sub-conditions over a vector<JokerData> pack.
static bool matchesJokerPack(const std::vector<JokerData> &jokers, const mini_json::Value &args) {
    const auto &anyCond = args["any"];
    if (anyCond.isObject()) {
        bool found = false;
        for (const auto &jd : jokers)
            if (matchesJoker(jd, anyCond)) { found = true; break; }
        if (!found) return false;
    }
    const auto &allCond = args["all"];
    if (allCond.isObject()) {
        for (const auto &jd : jokers)
            if (!matchesJoker(jd, allCond)) return false;
    }
    const auto &noneCond = args["none"];
    if (noneCond.isObject()) {
        for (const auto &jd : jokers)
            if (matchesJoker(jd, noneCond)) return false;
    }
    const auto &countCond = args["count"];
    if (countCond.isObject()) {
        const auto &matchCond = countCond["match"];
        int cnt = 0;
        for (const auto &jd : jokers)
            if (!matchCond.isObject() || matchesJoker(jd, matchCond)) cnt++;
        long long minV = getNumber(countCond["min"], -1);
        long long maxV = getNumber(countCond["max"], -1);
        long long eqV  = getNumber(countCond["equals"], -1);
        if (minV >= 0 && cnt < (int)minV) return false;
        if (maxV >= 0 && cnt > (int)maxV) return false;
        if (eqV  >= 0 && cnt != (int)eqV)  return false;
    }
    return true;
}

// Apply any/all/none/count sub-conditions over a vector<Card> pack.
static bool matchesCardPack(const std::vector<Card> &cards, const mini_json::Value &args) {
    const auto &anyCond = args["any"];
    if (anyCond.isObject()) {
        bool found = false;
        for (const auto &card : cards)
            if (matchesCard(card, anyCond)) { found = true; break; }
        if (!found) return false;
    }
    const auto &allCond = args["all"];
    if (allCond.isObject()) {
        for (const auto &card : cards)
            if (!matchesCard(card, allCond)) return false;
    }
    const auto &noneCond = args["none"];
    if (noneCond.isObject()) {
        for (const auto &card : cards)
            if (matchesCard(card, noneCond)) return false;
    }
    const auto &countCond = args["count"];
    if (countCond.isObject()) {
        const auto &matchCond = countCond["match"];
        int cnt = 0;
        for (const auto &card : cards)
            if (!matchCond.isObject() || matchesCard(card, matchCond)) cnt++;
        long long minV = getNumber(countCond["min"], -1);
        long long maxV = getNumber(countCond["max"], -1);
        long long eqV  = getNumber(countCond["equals"], -1);
        if (minV >= 0 && cnt < (int)minV) return false;
        if (maxV >= 0 && cnt > (int)maxV) return false;
        if (eqV  >= 0 && cnt != (int)eqV)  return false;
    }
    return true;
}

// ---------------------------------------------------------------------------
// Step execution
// ---------------------------------------------------------------------------

static bool applyStep(const Step &step, Instance &inst) {
    const auto &args = step.args;

    // --- Combinators ---

    // "all": every sub-step must pass (AND)
    if (step.op == "all") {
        for (const auto &sub : step.subSteps)
            if (!applyStep(sub, inst)) return false;
        return true;
    }
    // "any": at least one sub-step must pass (OR)
    if (step.op == "any") {
        for (const auto &sub : step.subSteps)
            if (applyStep(sub, inst)) return true;
        return false;
    }

    // --- Simple game-state ops ---

    if (step.op == "tag") {
        int idx = static_cast<int>(getNumber(args["index"], 1));
        return matchesItem(inst.nextTag(idx), args);
    }
    if (step.op == "pack") {
        int idx = static_cast<int>(getNumber(args["index"], 1));
        return matchesItem(inst.nextPack(idx), args);
    }
    if (step.op == "voucher") {
        int idx = static_cast<int>(getNumber(args["index"], 1));
        Item val = inst.nextVoucher(idx);
        if (!matchesItem(val, args)) return false;
        if (args["activate"].getBool(false)) inst.activateVoucher(val);
        return true;
    }
    if (step.op == "boss") {
        int idx = static_cast<int>(getNumber(args["index"], 1));
        return matchesItem(inst.nextBoss(idx), args);
    }

    // --- Individual card draws ---

    // "joker": draw (and optionally advance) joker draws.
    // draw=N checks the 1st joker and advances through N draws total (original behaviour).
    if (step.op == "joker") {
        int draw = static_cast<int>(getNumber(args["draw"], 1));
        int ante = static_cast<int>(getNumber(args["ante"], 1));
        bool stickers = args["has_stickers"].getBool(true);
        std::string source = args["source"].getString("Brainstorm_Joker");
        JokerData jd = inst.nextJoker(source, ante, stickers);
        for (int i = 1; i < draw; i++) inst.nextJoker(source, ante, stickers);
        return matchesJoker(jd, args["match"]);
    }
    // "joker_window": search up to limit draws for any matching joker.
    if (step.op == "joker_window") {
        int limit = static_cast<int>(getNumber(args["limit"], 1));
        int ante = static_cast<int>(getNumber(args["ante"], 1));
        bool stickers = args["has_stickers"].getBool(true);
        std::string source = args["source"].getString("Brainstorm_Joker_Window");
        const auto &match = args["any"]["match"].isObject() ? args["any"]["match"] : args["match"];
        for (int i = 0; i < limit; i++) {
            JokerData jd = inst.nextJoker(source, ante, stickers);
            if (matchesJoker(jd, match)) return true;
        }
        return false;
    }
    // "tarot": draw the Nth tarot card (draw=N skips N-1 then checks the Nth).
    if (step.op == "tarot") {
        int draw = static_cast<int>(getNumber(args["draw"], 1));
        int ante = static_cast<int>(getNumber(args["ante"], 1));
        bool soulable = args["soulable"].getBool(true);
        std::string source = args["source"].getString("Brainstorm_Tarot");
        for (int i = 1; i < draw; i++) inst.nextTarot(source, ante, soulable);
        return matchesItem(inst.nextTarot(source, ante, soulable), args);
    }
    // "planet": draw the Nth planet card.
    if (step.op == "planet") {
        int draw = static_cast<int>(getNumber(args["draw"], 1));
        int ante = static_cast<int>(getNumber(args["ante"], 1));
        bool soulable = args["soulable"].getBool(true);
        std::string source = args["source"].getString("Brainstorm_Planet");
        for (int i = 1; i < draw; i++) inst.nextPlanet(source, ante, soulable);
        return matchesItem(inst.nextPlanet(source, ante, soulable), args);
    }
    // "spectral": draw the Nth spectral card.
    if (step.op == "spectral") {
        int draw = static_cast<int>(getNumber(args["draw"], 1));
        int ante = static_cast<int>(getNumber(args["ante"], 1));
        bool soulable = args["soulable"].getBool(true);
        std::string source = args["source"].getString("Brainstorm_Spectral");
        for (int i = 1; i < draw; i++) inst.nextSpectral(source, ante, soulable);
        return matchesItem(inst.nextSpectral(source, ante, soulable), args);
    }
    // "shop_item": draw the Nth shop item.
    if (step.op == "shop_item") {
        int draw = static_cast<int>(getNumber(args["draw"], 1));
        int ante = static_cast<int>(getNumber(args["ante"], 1));
        for (int i = 1; i < draw; i++) inst.nextShopItem(ante);
        return matchesShopItem(inst.nextShopItem(ante), args);
    }
    // "standard_card": draw the Nth standard playing card.
    if (step.op == "standard_card") {
        int draw = static_cast<int>(getNumber(args["draw"], 1));
        int ante = static_cast<int>(getNumber(args["ante"], 1));
        for (int i = 1; i < draw; i++) inst.nextStandardCard(ante);
        return matchesCard(inst.nextStandardCard(ante), args);
    }

    // --- Pack contents ops ---
    // Each uses any/all/none/count sub-conditions on the pack's items.

    // "arcana_pack": generate a tarot/soul pack and inspect its contents.
    if (step.op == "arcana_pack") {
        int size = static_cast<int>(getNumber(args["size"], 3));
        int ante = static_cast<int>(getNumber(args["ante"], 1));
        return matchesItemPack(inst.nextArcanaPack(size, ante), args);
    }
    // "celestial_pack": generate a planet pack and inspect its contents.
    if (step.op == "celestial_pack") {
        int size = static_cast<int>(getNumber(args["size"], 3));
        int ante = static_cast<int>(getNumber(args["ante"], 1));
        return matchesItemPack(inst.nextCelestialPack(size, ante), args);
    }
    // "spectral_pack": generate a spectral pack and inspect its contents.
    if (step.op == "spectral_pack") {
        int size = static_cast<int>(getNumber(args["size"], 2));
        int ante = static_cast<int>(getNumber(args["ante"], 1));
        return matchesItemPack(inst.nextSpectralPack(size, ante), args);
    }
    // "buffoon_pack": generate a joker pack and inspect its contents.
    if (step.op == "buffoon_pack") {
        int size = static_cast<int>(getNumber(args["size"], 2));
        int ante = static_cast<int>(getNumber(args["ante"], 1));
        return matchesJokerPack(inst.nextBuffoonPack(size, ante), args);
    }
    // "standard_pack": generate a playing-card pack and inspect its contents.
    if (step.op == "standard_pack") {
        int size = static_cast<int>(getNumber(args["size"], 3));
        int ante = static_cast<int>(getNumber(args["ante"], 1));
        return matchesCardPack(inst.nextStandardPack(size, ante), args);
    }

    // --- State mutation ops (always return true) ---

    // "init_locks": initialise lock/unlock state for a given ante/profile.
    if (step.op == "init_locks") {
        int ante = static_cast<int>(getNumber(args["ante"], 1));
        bool freshProfile = args["fresh_profile"].getBool(false);
        bool freshRun     = args["fresh_run"].getBool(false);
        inst.initLocks(ante, freshProfile, freshRun);
        if (args["unlock"].getBool(false)) inst.initUnlocks(ante, freshProfile);
        return true;
    }
    // "set": change deck or stake for subsequent draws.
    if (step.op == "set") {
        const auto &deck  = args["deck"];
        const auto &stake = args["stake"];
        if (deck.isString()) inst.setDeck(stringToItem(deck.getString()));
        if (stake.isString()) inst.setStake(stringToItem(stake.getString()));
        else if (stake.isNumber()) inst.setStake(static_cast<Item>(static_cast<int>(stake.number)));
        return true;
    }

    // --- Seed state inspection ---

    if (step.op == "state") {
        std::string field = args["field"].getString("");
        if (field == "id") {
            long long id = inst.seed.getID();
            const auto &eq = args["equals"];
            if (eq.isNumber() && id != static_cast<long long>(eq.number)) return false;
            const auto &range = args["range"];
            if (range.isArray() && range.array.size() >= 2) {
                long long lo = static_cast<long long>(range.array[0].number);
                long long hi = static_cast<long long>(range.array[1].number);
                if (id < lo || id > hi) return false;
            }
        }
        return true;
    }

    // Unknown op → fail safely so malformed queries don't silently pass.
    return false;
}

// ---------------------------------------------------------------------------
// Filter tree construction from JSON
// ---------------------------------------------------------------------------

static void collectSteps(const mini_json::Value &node, std::vector<Step> &out) {
    if (!node.isObject()) return;

    // { "all": [...] } → flatten children into sequential AND (same as before)
    if (node["all"].isArray()) {
        for (const auto &child : node["all"].array)
            collectSteps(child, out);
        return;
    }
    // { "any": [...] } → single OR combinator step with children
    if (node["any"].isArray()) {
        Step anyStep;
        anyStep.op = "any";
        for (const auto &child : node["any"].array)
            collectSteps(child, anyStep.subSteps);
        out.push_back(anyStep);
        return;
    }
    // { "op": "...", "args": {...} } → leaf step
    if (node["op"].isString()) {
        Step s;
        s.op   = node["op"].getString();
        s.args = node["args"];
        out.push_back(s);
    }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

static const char *dupCString(const std::string &str) {
    char *c_result = (char *)malloc(str.length() + 1);
    if (!c_result) return nullptr;
    std::strcpy(c_result, str.c_str());
    return c_result;
}

IMMOLATE_API const char *brainstorm_query(const char *seed,
                                          const char *query_json) {
    std::string seed_str  = seed      ? seed      : "";
    std::string query_str = query_json ? query_json : "";

    mini_json::Value root;
    if (!mini_json::parse(query_str, root) || !root.isObject()) {
        return dupCString("");
    }

    std::vector<Step> steps;
    collectSteps(root["filter"], steps);
    if (steps.empty()) {
        return dupCString("");
    }

    const auto &search = root["search"];
    int       threads    = static_cast<int>(getNumber(search["threads"],   1));
    long long max_seeds  = getNumber(search["max_seeds"], 100000000);
    bool      exit_on_find = search["exit_on_find"].getBool(true);

    Search s([steps](Instance inst) {
        for (const auto &step : steps)
            if (!applyStep(step, inst)) return 0;
        return 1;
    }, seed_str, threads, max_seeds > 0 ? max_seeds : 100000000);
    s.exitOnFind = exit_on_find;
    std::string result = s.search();
    return dupCString(result);
}

extern "C" {
    IMMOLATE_API const char* brainstorm(const char* seed, const char* pack,
const char* tag, double souls) { std::string cpp_seed(seed); std::string
cpp_pack(pack); std::string cpp_tag(tag); std::string result =
brainstorm_cpp(cpp_seed, cpp_pack, cpp_tag, souls);

        char* c_result = (char*)malloc(result.length() + 1);
        strcpy(c_result, result.c_str());

        return c_result;
    }

    IMMOLATE_API void free_result(const char* result) {
        free((void*)result);
    }
}
