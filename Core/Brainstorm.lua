-- Brainstorm Mod for Balatro
-- High-performance seed filtering and save state management
-- Author: Community Edition v3.0
-- License: MIT

local lovely = require("lovely")
local nfs = require("nativefs")
local ffi = require("ffi")

-- Initialize logging system
local logger_ok, logger = pcall(require, "Core.logger")
local log
if logger_ok then
  log = logger.for_module("Brainstorm")
else
  -- Fallback if logger not available
  log = {
    trace = function(msg, data) end,
    debug = function(msg, data)
      if Brainstorm.debug and Brainstorm.debug.enabled then
        print("[DEBUG] " .. tostring(msg))
      end
    end,
    info = function(msg, data)
      print("[INFO] " .. tostring(msg))
    end,
    warn = function(msg, data)
      print("[WARN] " .. tostring(msg))
    end,
    error = function(msg, data)
      print("[ERROR] " .. tostring(msg))
    end,
    start_timer = function() end,
    end_timer = function() end,
    log_throttled = function() end,
  }
end

Brainstorm = {}

-- Mod version
Brainstorm.VERSION = "Brainstorm v3.0.0"

-- Reserved for Steammodded compatibility
Brainstorm.SMODS = nil

Brainstorm.config = {
  enable = true,
  use_gpu_experimental = false, -- default to CPU-only; GPU is opt-in
  keybind_autoreroll = "r",
  keybinds = {
    options = "t",
    modifier = "lctrl",
    f_reroll = "r",
    a_reroll = "a",
    save_state = "z",
    load_state = "x",
  },
  ar_filters = {
    pack = {},
    pack_id = 1,
    voucher_name = "",
    voucher_id = 1,
    tag_name = "tag_charm",
    tag_id = 2,
    tag2_name = "",
    tag2_id = 1,
    soul_skip = 1,
    inst_observatory = false,
    inst_perkeo = false,
  },
  ar_prefs = {
    spf_id = 3,
    spf_int = 1000,
    face_count = 0,
    suit_ratio_id = 1,
    suit_ratio_percent = "Disabled",
    suit_ratio_decimal = 0,
  },
  debug_enabled = true,
}

-- Auto-reroll state management
-- Tracks the state of automatic seed rerolling
Brainstorm.ar_timer = 0 -- Time accumulator for reroll intervals
Brainstorm.ar_frames = 0 -- Frame counter for UI display timing
Brainstorm.ar_text = nil -- UI text element for "Rerolling..." message
Brainstorm.ar_active = false -- Whether auto-reroll is currently active

-- Debug statistics for performance monitoring and analysis
-- Helps users understand search difficulty and optimize filters
Brainstorm.debug = {
  enabled = false, -- Will be set from config
  seeds_tested = 0, -- Total seeds evaluated
  seeds_found = 0, -- Seeds matching DLL filters
  start_time = 0, -- When search started (os.clock)
  rejection_reasons = { -- Why seeds were rejected
    face_cards = 0, -- Not enough face cards
    suit_ratio = 0, -- Suit distribution too even
    dll_filter = 0, -- Failed DLL criteria
  },
  distributions = { -- Statistical distributions found
    face_cards = {}, -- Histogram of face card counts
    suit_ratios = {}, -- Histogram of suit ratios
  },
  last_report_time = 0, -- Last time we printed progress
  highest_suit_ratio = 0, -- Best ratio seen so far
  highest_face_count = 0, -- Most face cards seen
}

-- Static lookup tables for better performance
-- Avoids repeated string comparisons in hot loops
Brainstorm.RATIO_MAP = {
  ["Disabled"] = 0,
  ["50%"] = 0.5,
  ["60%"] = 0.6,
  ["70%"] = 0.7,
  ["75%"] = 0.75,
  ["80%"] = 0.80, -- 80% is mathematically impossible but kept for compatibility
}

-- Face card lookup for O(1) checking instead of multiple string comparisons
Brainstorm.FACE_CARDS = {
  ["Jack"] = true,
  ["Queen"] = true,
  ["King"] = true,
}

-- Constants
Brainstorm.AR_INTERVAL = 0.01 -- Seconds between reroll attempts (100 Hz)

-- Performance optimization: Cache frequently used functions
-- This avoids table lookups in hot code paths
local string_format = string.format
local string_lower = string.lower
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local table_insert = table.insert
local table_sort = table.sort
local os_clock = os.clock
local pcall = pcall

-- Random seed generation constants
-- Seed generation factors using prime-based constants for good distribution
-- These values minimize correlation between cursor position and generated seeds:
--   X factor (~1/3): Spreads horizontal mouse movement across seed space
--   Y factor (~7/8): Ensures vertical movement contributes strongly
--   Time factor (~2/5): Incorporates temporal variation for entropy
local SEED_X_FACTOR = 0.33411983 -- Prime-derived for X axis distribution
local SEED_Y_FACTOR = 0.874146 -- Prime-derived for Y axis spread
local SEED_TIME_FACTOR = 0.412311010 -- Prime-derived for time entropy

-- Find the Brainstorm mod directory
-- Searches for a directory containing "brainstorm" (case-insensitive)
local function find_brainstorm_directory(directory)
  for _, item in ipairs(nfs.getDirectoryItems(directory)) do
    local itemPath = directory .. "/" .. item
    if
      nfs.getInfo(itemPath, "directory")
      and string_lower(item):find("brainstorm")
    then
      return itemPath
    end
  end
  return nil
end

local function file_exists(file_path)
  return nfs.getInfo(file_path) ~= nil
end

-- Load configuration from file with backward compatibility
-- Uses deep merge to preserve new fields when loading old configs
function Brainstorm.load_config()
  local config_path = Brainstorm.PATH .. "/config.lua"
  if not file_exists(config_path) then
    Brainstorm.write_config() -- Create default config
  else
    local config_file, err = nfs.read(config_path)
    if not config_file then
      log.error(
        "Failed to read config file",
        { error = err or "unknown error" }
      )
      return
    end
    -- STR_UNPACK is a Balatro function for deserializing Lua tables
    local success, loaded_config = pcall(STR_UNPACK, config_file)
    if success and loaded_config then
      -- Deep merge loaded config with defaults to handle new fields
      -- This ensures backward compatibility when new config options are added
      local function deep_merge(target, source)
        for key, value in pairs(source) do
          if type(value) == "table" and type(target[key]) == "table" then
            deep_merge(target[key], value) -- Recursively merge nested tables
          else
            target[key] = value -- Overwrite or add new value
          end
        end
      end

      deep_merge(Brainstorm.config, loaded_config)

      -- Ensure new fields have default values if missing
      Brainstorm.config.ar_prefs.face_count = Brainstorm.config.ar_prefs.face_count
        or 0
      Brainstorm.config.ar_prefs.suit_ratio_id = Brainstorm.config.ar_prefs.suit_ratio_id
        or 1
      Brainstorm.config.ar_prefs.suit_ratio_percent = Brainstorm.config.ar_prefs.suit_ratio_percent
        or "Disabled"

      -- Map suit ratio percentage to decimal value (use static table)
      Brainstorm.config.ar_prefs.suit_ratio_decimal = Brainstorm.RATIO_MAP[Brainstorm.config.ar_prefs.suit_ratio_percent]
        or 0
      Brainstorm.config.use_gpu_experimental = Brainstorm.config.use_gpu_experimental
        or false
    end
  end
end

function Brainstorm.write_config()
  local config_path = Brainstorm.PATH .. "/config.lua"
  -- STR_PACK is a Balatro function for serializing Lua tables
  local success, packed = pcall(STR_PACK, Brainstorm.config)
  if success and packed then
    local write_success, err = nfs.write(config_path, packed)
    if not write_success then
      log.error(
        "Failed to write config file",
        { error = err or "unknown error" }
      )
    end
  end
end

function Brainstorm.init()
  print("[Brainstorm] Initializing...")

  Brainstorm.PATH = find_brainstorm_directory(lovely.mod_dir)
  if not Brainstorm.PATH then
    print("[Brainstorm] ERROR: Could not find Brainstorm directory")
    return false
  end

  print("[Brainstorm] Found mod at: " .. Brainstorm.PATH)

  Brainstorm.load_config()
  Brainstorm.debug.enabled = Brainstorm.config.debug_enabled or false

  -- Initialize logger with file path only if debug is enabled
  if logger_ok and logger.global and Brainstorm.debug.enabled then
    logger.global.file_path = Brainstorm.PATH .. "/brainstorm.log"
    logger.global:rotate_log_if_needed()
    -- Recreate the module logger with file path configured
    log = logger.for_module("Brainstorm")
    log:info(
      "Brainstorm initialized",
      { version = Brainstorm.VERSION, path = Brainstorm.PATH }
    )
  end

  -- Load UI with error handling
  local ui_path = Brainstorm.PATH .. "/UI/ui.lua"
  local ui_content = nfs.read(ui_path)
  if not ui_content then
    print("[Brainstorm] ERROR: Could not read UI file")
    return false
  end

  local ui_func, err = load(ui_content)
  if not ui_func then
    print("[Brainstorm] ERROR: Failed to load UI: " .. tostring(err))
    return false
  end

  local success, ui_err = pcall(ui_func)
  if not success then
    print("[Brainstorm] ERROR: Failed to initialize UI: " .. tostring(ui_err))
    return false
  end

  return true
end

-- Save state functionality
local save_state_keys = { "1", "2", "3", "4", "5" }

function Brainstorm.save_state_alert(text)
  G.E_MANAGER:add_event(Event({
    trigger = "after",
    delay = 0.4,
    func = function()
      attention_text({
        text = text,
        scale = 0.7,
        hold = 3,
        major = G.STAGE == G.STAGES.RUN and G.play or G.title_top,
        backdrop_colour = G.C.SECONDARY_SET.Tarot,
        align = "cm",
        offset = { x = 0, y = -3.5 },
        silent = true,
      })
      G.E_MANAGER:add_event(Event({
        trigger = "after",
        delay = 0.06 * G.SETTINGS.GAMESPEED,
        blockable = false,
        blocking = false,
        func = function()
          play_sound("other1", 0.76, 0.4)
          return true
        end,
      }))
      return true
    end,
  }))
end

function Brainstorm.save_game_state(slot)
  if G.STAGE == G.STAGES.RUN then
    local save_path = G.SETTINGS.profile
      .. "/"
      .. "save_state_"
      .. slot
      .. ".jkr"
    local success, err = pcall(compress_and_save, save_path, G.ARGS.save_run)
    if success then
      Brainstorm.save_state_alert("Saved state to slot [" .. slot .. "]")
      return true
    else
      print("[Brainstorm] Failed to save state: " .. tostring(err))
      Brainstorm.save_state_alert("Failed to save state")
      return false
    end
  end
  return false
end

function Brainstorm.load_game_state(slot)
  local save_path = G.SETTINGS.profile .. "/" .. "save_state_" .. slot .. ".jkr"
  local success, saved_game = pcall(get_compressed, save_path)

  if success and saved_game then
    local unpack_success, saved_data = pcall(STR_UNPACK, saved_game)
    if unpack_success and saved_data then
      G:delete_run()
      G.SAVED_GAME = saved_data
      G:start_run({ savetext = G.SAVED_GAME })
      Brainstorm.save_state_alert("Loaded state from slot [" .. slot .. "]")
      return true
    else
      print("[Brainstorm] Failed to unpack save: " .. tostring(saved_data))
      Brainstorm.save_state_alert("Corrupted save in slot [" .. slot .. "]")
      return false
    end
  else
    Brainstorm.save_state_alert("No save in slot [" .. slot .. "]")
    return false
  end
end

local key_press_update_ref = Controller.key_press_update
function Controller:key_press_update(key, dt)
  key_press_update_ref(self, key, dt)

  -- Safety check: ensure Brainstorm is initialized
  if
    not Brainstorm
    or not Brainstorm.config
    or not Brainstorm.config.keybinds
  then
    return
  end

  local keybinds = Brainstorm.config.keybinds

  -- Save state functionality
  for _, slot in ipairs(save_state_keys) do
    if key == slot then
      -- Save state
      if love.keyboard.isDown(keybinds.save_state) then
        Brainstorm.save_game_state(slot)
      end
      -- Load state
      if love.keyboard.isDown(keybinds.load_state) then
        Brainstorm.load_game_state(slot)
      end
    end
  end

  -- Original reroll functionality
  if love.keyboard.isDown(keybinds.modifier) then
    if key == keybinds.f_reroll then
      Brainstorm.reroll()
    elseif key == keybinds.a_reroll then
      print("[Brainstorm] Ctrl+A pressed - toggling auto-reroll")
      -- Wrap in pcall to catch any errors
      local success, err = pcall(function()
        if Brainstorm.ar_active then
          Brainstorm.stop_auto_reroll(false)
        else
          Brainstorm.ar_active = true

          -- Print helpful message for dual tag searches
          if
            Brainstorm.config.ar_filters.tag2_name
            and Brainstorm.config.ar_filters.tag2_name ~= ""
          then
            -- Safely get tag display names
            local tag1_display = Brainstorm.config.ar_filters.tag_name
            local tag2_display = Brainstorm.config.ar_filters.tag2_name

            -- Try to localize if the function exists and is safe
            if localize and type(localize) == "function" then
              local ok1, localized1 = pcall(localize, {
                type = "name_text",
                set = "Tag",
                key = Brainstorm.config.ar_filters.tag_name,
              })
              if ok1 and localized1 then
                tag1_display = localized1
              end

              local ok2, localized2 = pcall(localize, {
                type = "name_text",
                set = "Tag",
                key = Brainstorm.config.ar_filters.tag2_name,
              })
              if ok2 and localized2 then
                tag2_display = localized2
              end
            end

            if
              Brainstorm.config.ar_filters.tag_name
              == Brainstorm.config.ar_filters.tag2_name
            then
              print(
                string.format(
                  "[Brainstorm] Searching for DOUBLE %s tags...",
                  tag1_display
                )
              )
              print(
                "[Brainstorm] This is extremely rare! May take 5-30 seconds depending on the tag."
              )
            else
              print(
                string.format(
                  "[Brainstorm] Searching for %s + %s tags...",
                  tag1_display,
                  tag2_display
                )
              )
              print(
                "[Brainstorm] Dual tag combinations can take 5-20 seconds to find."
              )
            end
            log.info(
              "Order doesn't matter - either tag can be in either blind position."
            )
          end
        end
      end) -- End of pcall

      if not success then
        log.error("ERROR in auto-reroll toggle", { error = err })
      end
    end
  end
end

-- Check if the current seed has both required tags in the first ante
-- Supports order-agnostic matching and same-tag-twice requirements
-- Returns: true if tags match requirements, false otherwise
function Brainstorm.check_dual_tags()
  local tag1 = Brainstorm.config.ar_filters.tag_name
  local tag2 = Brainstorm.config.ar_filters.tag2_name

  -- If no second tag specified, always pass
  if not tag2 or tag2 == "" then
    return true
  end

  -- Tags are stored in G.GAME.round_resets.blind_tags.Small and .Big
  if
    not G.GAME
    or not G.GAME.round_resets
    or not G.GAME.round_resets.blind_tags
  then
    return false
  end

  local small_blind_tag = G.GAME.round_resets.blind_tags.Small
  local big_blind_tag = G.GAME.round_resets.blind_tags.Big

  -- Track dual tag checks for performance metrics
  if Brainstorm.debug.enabled then
    Brainstorm.debug.dual_tag_checks = (Brainstorm.debug.dual_tag_checks or 0)
      + 1
  end

  -- Special case: Looking for the same tag in BOTH blind positions
  -- Example: Double Investment Tags (extremely rare ~0.1% chance)
  if tag1 == tag2 then
    local both_match = (small_blind_tag == tag1 and big_blind_tag == tag1)
    if both_match then
      if Brainstorm.debug.enabled then
        log:info("Dual tag success: Both blinds have " .. tag1)
        Brainstorm.debug.dual_tag_successes = (
          Brainstorm.debug.dual_tag_successes or 0
        ) + 1
      end
      return true
    end
    return false
  else
    -- Different tags: Check both are present in either order
    -- Example: Investment + Charm (order doesn't matter)
    local has_tag1 = (small_blind_tag == tag1 or big_blind_tag == tag1)
    local has_tag2 = (small_blind_tag == tag2 or big_blind_tag == tag2)

    if has_tag1 and has_tag2 then
      if Brainstorm.debug.enabled then
        log:info("Dual tag success: Both tags found (order-agnostic)")
        Brainstorm.debug.dual_tag_successes = (
          Brainstorm.debug.dual_tag_successes or 0
        ) + 1
      end
      return true
    end
    return false
  end
end

-- Analyze the current deck composition
-- Used for Erratic deck validation (face cards and suit ratios)
-- Returns: Table with deck statistics
function Brainstorm.analyze_deck()
  local deck_summary = {}
  local suit_count = { Hearts = 0, Diamonds = 0, Clubs = 0, Spades = 0 }
  local face_card_count = 0
  local numeric_card_count = 0
  local ace_count = 0
  local unique_card_count = 0
  local face_cards = Brainstorm.FACE_CARDS -- Cache lookup table

  -- Iterate through all cards in the deck
  for _, card in ipairs(G.playing_cards) do
    if card.base then
      local card_value = card.base.value
      local card_suit = card.base.suit
      local card_name = card_value .. " of " .. card_suit
      deck_summary[card_name] = (deck_summary[card_name] or 0) + 1
      suit_count[card_suit] = (suit_count[card_suit] or 0) + 1

      -- Categorizing cards (optimized with lookup table)
      if card_value == "Ace" then
        ace_count = ace_count + 1
      elseif face_cards[card_value] then
        face_card_count = face_card_count + 1
      else
        numeric_card_count = numeric_card_count + 1
      end
    end
  end

  -- Count unique cards
  for _ in pairs(deck_summary) do
    unique_card_count = unique_card_count + 1
  end

  -- Return the analysis result
  return {
    deck_summary = deck_summary,
    suit_count = suit_count,
    face_card_count = face_card_count,
    numeric_card_count = numeric_card_count,
    ace_count = ace_count,
    unique_card_count = unique_card_count,
  }
end

-- Validate if a deck meets the specified requirements
-- Used for Erratic deck filtering based on face cards and suit distribution
-- Parameters:
--   deck_data: Analysis from analyze_deck()
--   min_face_cards: Minimum number of face cards required (0-23)
--   min_aces: Minimum number of aces required (unused currently)
--   dominant_suit_ratio: Required ratio for top 2 suits (0.5 to 0.75)
-- Returns: true if deck is valid, false otherwise
function Brainstorm.is_valid_deck(
  deck_data,
  min_face_cards,
  min_aces,
  dominant_suit_ratio
)
  -- Ensure parameters are not nil by providing default values
  min_face_cards = min_face_cards or 0
  min_aces = min_aces or 0
  dominant_suit_ratio = dominant_suit_ratio or 0

  -- Extract counts from the deck analysis
  local total_cards = #G.playing_cards
  local face_card_count = deck_data.face_card_count or 0
  local ace_count = deck_data.ace_count or 0
  local suit_count = deck_data.suit_count or {}

  -- Track distribution for debugging
  if Brainstorm.debug.enabled then
    local fc_bucket = math_floor(face_card_count / 5) * 5
    Brainstorm.debug.distributions.face_cards[fc_bucket] = (
      Brainstorm.debug.distributions.face_cards[fc_bucket] or 0
    ) + 1

    -- Track highest face count
    if face_card_count > Brainstorm.debug.highest_face_count then
      Brainstorm.debug.highest_face_count = face_card_count
    end
  end

  -- Check Face Cards & Aces
  if face_card_count < min_face_cards then
    if Brainstorm.debug.enabled then
      Brainstorm.debug.rejection_reasons.face_cards = Brainstorm.debug.rejection_reasons.face_cards
        + 1
    end
    return false
  end
  if ace_count < min_aces then
    --print("Deck has", ace_count, "aces, need", min_aces)
    return false
  end

  -- Check suit distribution (only if enabled - 0 means disabled)
  if dominant_suit_ratio and dominant_suit_ratio > 0 then
    local sorted_suits = {}
    for suit, count in pairs(suit_count) do
      table_insert(sorted_suits, { suit = suit, count = count })
    end

    if #sorted_suits > 0 then
      table_sort(sorted_suits, function(a, b)
        return a.count > b.count
      end)

      -- Calculate the combined percentage of the top 2 suits
      -- This represents how "suited" the deck is
      -- Higher values mean more cards of the same suits
      local top_2_suit_count = sorted_suits[1].count
        + (sorted_suits[2] and sorted_suits[2].count or 0)
      local top_2_suit_percentage = top_2_suit_count / total_cards

      -- Track suit ratio distribution
      if Brainstorm.debug.enabled then
        local ratio_bucket = math_floor(top_2_suit_percentage * 10) * 10
        Brainstorm.debug.distributions.suit_ratios[ratio_bucket] = (
          Brainstorm.debug.distributions.suit_ratios[ratio_bucket] or 0
        ) + 1

        -- Track the highest ratio we've seen
        if
          not Brainstorm.debug.highest_suit_ratio
          or top_2_suit_percentage > Brainstorm.debug.highest_suit_ratio
        then
          Brainstorm.debug.highest_suit_ratio = top_2_suit_percentage
        end
      end

      if top_2_suit_percentage < dominant_suit_ratio then
        if Brainstorm.debug.enabled then
          Brainstorm.debug.rejection_reasons.suit_ratio = Brainstorm.debug.rejection_reasons.suit_ratio
            + 1
        end
        return false
      end
    end
  end

  return true
end

function Brainstorm.print_debug_report(success)
  local elapsed = os_clock() - Brainstorm.debug.start_time
  local seeds_per_sec = Brainstorm.debug.seeds_tested / elapsed

  print("========================================")
  print("[Brainstorm Debug Report]")
  print(
    string.format(
      "Result: %s",
      success and "SUCCESS - Seed Found!" or "STOPPED"
    )
  )
  print(string.format("Time elapsed: %.2f seconds", elapsed))
  print(string.format("Seeds tested: %d", Brainstorm.debug.seeds_tested))
  print(string.format("Seeds per second: %.1f", seeds_per_sec))
  print(
    string.format("Seeds found matching DLL: %d", Brainstorm.debug.seeds_found)
  )

  print("\nRejection Reasons:")
  local total_rejections = Brainstorm.debug.rejection_reasons.face_cards
    + Brainstorm.debug.rejection_reasons.suit_ratio
  if total_rejections > 0 then
    print(
      string.format(
        "  Face cards: %d (%.1f%%)",
        Brainstorm.debug.rejection_reasons.face_cards,
        Brainstorm.debug.rejection_reasons.face_cards / total_rejections * 100
      )
    )
    print(
      string.format(
        "  Suit ratio: %d (%.1f%%)",
        Brainstorm.debug.rejection_reasons.suit_ratio,
        Brainstorm.debug.rejection_reasons.suit_ratio / total_rejections * 100
      )
    )
  end

  print("\nFace Card Distribution:")
  for bucket = 0, 30, 5 do
    local count = Brainstorm.debug.distributions.face_cards[bucket] or 0
    if count > 0 then
      print(
        string.format(
          "  %d-%d: %d seeds (%.1f%%)",
          bucket,
          bucket + 4,
          count,
          count / Brainstorm.debug.seeds_tested * 100
        )
      )
    end
  end

  print("\nSuit Ratio Distribution:")
  local max_ratio = 0
  for bucket = 40, 90, 10 do
    local count = Brainstorm.debug.distributions.suit_ratios[bucket] or 0
    if count > 0 then
      print(
        string.format(
          "  %d%%-%d%%: %d seeds (%.1f%%)",
          bucket,
          bucket + 9,
          count,
          count / Brainstorm.debug.seeds_tested * 100
        )
      )
      if bucket > max_ratio then
        max_ratio = bucket
      end
    end
  end

  -- Show exact max values found
  print(
    string.format(
      "\nHighest suit ratio found: %.1f%% (in %d%%-%d%% bucket)",
      (Brainstorm.debug.highest_suit_ratio or 0) * 100,
      max_ratio,
      max_ratio + 9
    )
  )
  print(
    string.format(
      "Highest face count found: %d face cards",
      Brainstorm.debug.highest_face_count or 0
    )
  )
  print(
    string.format(
      "\nTarget suit ratio: %.0f%%",
      (Brainstorm.config.ar_prefs.suit_ratio_decimal or 0) * 100
    )
  )
  print(
    string.format(
      "Target face count: %d",
      Brainstorm.config.ar_prefs.face_count or 0
    )
  )

  -- Recommendation
  if Brainstorm.config.ar_prefs.suit_ratio_decimal >= 0.75 then
    print("\nWARNING: 75% suit ratio is the maximum achievable!")
    print("Consider using 70% or lower for faster results.")
  elseif Brainstorm.config.ar_prefs.suit_ratio_decimal > 0.7 then
    print("\nNOTE: Suit ratios above 70% are extremely rare.")
    print("Expect longer search times.")
  end

  print("========================================")
end

-- Performance metrics are now tracked internally and shown in debug report only

-- Perform a single manual reroll
-- Preserves stake and challenge settings
function Brainstorm.reroll()
  local G = G -- Cache global for slight performance gain

  -- Preserve game state for restart
  G.GAME.viewed_back = nil
  G.run_setup_seed = G.GAME.seeded
  G.challenge_tab = G.GAME and G.GAME.challenge and G.GAME.challenge_tab or nil
  G.forced_seed = G.GAME.seeded and G.GAME.pseudorandom.seed or nil

  local seed = G.run_setup_seed and G.setup_seed or G.forced_seed
  local stake = (
    G.GAME.stake
    or G.PROFILES[G.SETTINGS.profile].MEMORY.stake
    or 1
  ) or 1

  G:delete_run()
  G:start_run({ stake = stake, seed = seed, challenge = G.challenge_tab })
end

-- Hook into the game's update loop for auto-reroll functionality
-- This is called every frame when the game is running
local update_ref = Game.update
function Game:update(dt)
  -- Safely call original update
  if update_ref then
    update_ref(self, dt)
  end

  -- Safety check for Brainstorm
  if not Brainstorm then
    return
  end

  -- Handle auto-reroll if active
  if Brainstorm.ar_active then
    -- Wrap in pcall to catch errors
    local success, err = pcall(function()
      -- Initialize debug tracking on first frame
      if Brainstorm.debug.start_time == 0 then
        Brainstorm.debug.start_time = os_clock()
        Brainstorm.debug.last_report_time = os_clock()
      end

      -- Update performance metrics
      if Brainstorm.debug.enabled then
        Brainstorm.debug.last_report_time = os_clock()
      end

      Brainstorm.ar_frames = Brainstorm.ar_frames + 1
      Brainstorm.ar_timer = Brainstorm.ar_timer + dt

      if Brainstorm.ar_timer >= Brainstorm.AR_INTERVAL then
        Brainstorm.ar_timer = Brainstorm.ar_timer - Brainstorm.AR_INTERVAL

        -- Try multiple seeds based on spf_int setting (seeds per second)
        -- AR_INTERVAL is 0.01 seconds, so we run 100 times per second
        -- Divide spf_int by 100 to get seeds per interval
        local seeds_to_try =
          math_max(1, math_floor(Brainstorm.config.ar_prefs.spf_int / 100))
        local seed_found = nil

        -- Determine if we need to validate Erratic deck requirements
        -- Erratic decks have random card distributions that need checking
        local has_erratic_requirements = G.GAME.starting_params.erratic_suits_and_ranks
          and (
            Brainstorm.config.ar_prefs.face_count > 0
            or Brainstorm.config.ar_prefs.suit_ratio_decimal > 0
          )

        -- Check if we have other filters active (vouchers, tags, packs)
        local has_other_filters = (
          Brainstorm.config.ar_filters.voucher_name ~= ""
        )
          or (Brainstorm.config.ar_filters.tag_name ~= "")
          or (Brainstorm.config.ar_filters.tag2_name ~= "")
          or (#Brainstorm.config.ar_filters.pack > 0)

        if has_erratic_requirements then
          -- Performance optimization for Erratic deck searches
          -- Limit seeds per frame to prevent lag spikes
          local max_seeds = 5 -- Conservative default to maintain 60 FPS
          if Brainstorm.config.ar_prefs.spf_int <= 500 then
            max_seeds = seeds_to_try -- Use full speed for low settings
          elseif Brainstorm.config.ar_prefs.spf_int <= 1000 then
            max_seeds = math_min(seeds_to_try, 5) -- Cap at 5 for medium
          else
            max_seeds = math_min(seeds_to_try, 10) -- Cap at 10 for high
          end
          local erratic_seeds_to_try = max_seeds

          -- Track performance metrics
          if
            Brainstorm.debug.enabled and Brainstorm.debug.seeds_tested == 0
          then
            log:info("Starting Erratic deck search", {
              seeds_per_frame = erratic_seeds_to_try,
              target_speed = Brainstorm.config.ar_prefs.spf_int,
            })
          end

          for i = 1, erratic_seeds_to_try do
            local test_seed = nil

            if has_other_filters then
              -- Use DLL to find seeds with voucher/tag/pack requirements
              test_seed = Brainstorm.auto_reroll()
              if test_seed then
                Brainstorm.debug.seeds_found = Brainstorm.debug.seeds_found + 1
              end
            else
              -- No other filters, just generate random seeds
              test_seed = random_string(
                8,
                G.CONTROLLER.cursor_hover.T.x * SEED_X_FACTOR
                  + G.CONTROLLER.cursor_hover.T.y * SEED_Y_FACTOR
                  + SEED_TIME_FACTOR
                    * (G.CONTROLLER.cursor_hover.time + i * 0.001)
              )
            end

            if test_seed then
              local stake = G.GAME.stake
              local challenge = G.GAME
                and G.GAME.challenge
                and G.GAME.challenge_tab
              G:delete_run()
              G:start_run({
                stake = stake,
                seed = test_seed,
                challenge = challenge,
              })

              -- Check if this seed meets the Erratic deck requirements
              local deck_data = Brainstorm.analyze_deck()
              Brainstorm.debug.seeds_tested = Brainstorm.debug.seeds_tested + 1

              -- Also check dual tags if configured
              local tags_valid = Brainstorm.check_dual_tags()

              if
                tags_valid
                and Brainstorm.is_valid_deck(
                  deck_data,
                  Brainstorm.config.ar_prefs.face_count,
                  0,
                  Brainstorm.config.ar_prefs.suit_ratio_decimal
                )
              then
                -- Found a valid seed that meets all criteria
                if Brainstorm.debug.enabled then
                  log:info("Seed found!", {
                    seed = test_seed,
                    seeds_tested = Brainstorm.debug.seeds_tested,
                  })
                end
                Brainstorm.stop_auto_reroll(true)
                G.GAME.used_filter = true
                G.GAME.seeded = false
                break
              end
            end
          end
        else
          -- No Erratic requirements, use DLL normally
          -- DLL already searches many seeds internally (100K-1M), so only call once
          seed_found = Brainstorm.auto_reroll()
          if seed_found then
            -- Found a seed that matches DLL criteria
            local stake = G.GAME.stake
            local challenge = G.GAME
              and G.GAME.challenge
              and G.GAME.challenge_tab
            G:delete_run()
            G:start_run({
              stake = stake,
              seed = seed_found,
              challenge = challenge,
            })

            -- Check dual tags if configured
            local tags_valid = Brainstorm.check_dual_tags()

            if tags_valid then
              if Brainstorm.debug.enabled then
                log:info("Seed found!", {
                  seed = seed_found,
                  seeds_tested = Brainstorm.debug.seeds_tested + 1,
                })
              end
              G.GAME.used_filter = true
              G.GAME.seeded = false
              Brainstorm.debug.seeds_tested = Brainstorm.debug.seeds_tested + 1
              Brainstorm.debug.seeds_found = Brainstorm.debug.seeds_found + 1
              Brainstorm.stop_auto_reroll(true)
            else
              -- Tags don't match, continue searching
              Brainstorm.debug.seeds_tested = Brainstorm.debug.seeds_tested + 1
            end
          end
        end
      end
      if
        Brainstorm.ar_frames == 60
        and not Brainstorm.ar_text
        and Brainstorm.ar_active
      then
        Brainstorm.ar_text = Brainstorm.attention_text({
          scale = 1.4,
          text = "Rerolling...",
          align = "cm",
          offset = { x = 0, y = -3.5 },
          major = G.STAGE == G.STAGES.RUN and G.play or G.title_top,
        })
      end
    end) -- End of pcall

    if not success then
      print("[Brainstorm] ERROR in auto-reroll update: " .. tostring(err))
      Brainstorm.ar_active = false -- Disable auto-reroll on error
    end
  end
end

-- Foreign Function Interface (FFI) for native DLL integration
-- The DLL provides high-performance seed filtering without game restarts
local ffi_loaded = false
local native_handles = { cpu = nil, gpu = nil }

-- Initialize FFI definitions for DLL functions
local function init_ffi()
  if not ffi_loaded then
    local success, err = pcall(
      ffi.cdef,
      [[
      // Enhanced brainstorm function with dual tag support
      const char* brainstorm(const char* seed, const char* voucher, const char* pack, const char* tag1, const char* tag2, double souls, bool observatory, bool perkeo);
      // Get both tags for a specific seed
      const char* get_tags(const char* seed);
      // Free memory allocated by DLL (prevents memory leaks)
      void free_result(const char* result);
      // GPU/CUDA functions
      int get_acceleration_type();  // 0=CPU, 1=GPU
      const char* get_hardware_info();
      void set_use_cuda(bool enable);
    ]]
    )
    if not success then
      print("[Brainstorm] Failed to initialize FFI: " .. tostring(err))
      return false
    end
    ffi_loaded = true
  end
  return true
end

local function load_cpu_native()
  if native_handles.cpu then
    return native_handles.cpu
  end

  local dll_path = Brainstorm.PATH .. "/Immolate.dll"
  local dll_file = io.open(dll_path, "rb")
  if not dll_file then
    if Brainstorm.debug.enabled then
      log:error("CPU DLL not found", { path = dll_path })
    end
    return nil
  end
  dll_file:close()

  local success, handle = pcall(ffi.load, dll_path)
  if not success then
    if Brainstorm.debug.enabled then
      log:error("Failed to load CPU DLL", { error = tostring(handle) })
    end
    return nil
  end

  native_handles.cpu = handle
  if Brainstorm.debug.enabled then
    log:info("Loaded CPU DLL", { path = dll_path })
  end
  return handle
end

local function load_gpu_native()
  if not Brainstorm.config.use_gpu_experimental then
    return nil
  end

  if native_handles.gpu then
    return native_handles.gpu
  end

  local dll_path = Brainstorm.PATH .. "/ImmolateCUDA.dll"
  local dll_file = io.open(dll_path, "rb")
  if not dll_file then
    if Brainstorm.debug.enabled then
      log:warn("GPU DLL not found (skipping)", { path = dll_path })
    end
    return nil
  end
  dll_file:close()

  local success, handle = pcall(ffi.load, dll_path)
  if not success then
    if Brainstorm.debug.enabled then
      log:error("Failed to load GPU DLL", { error = tostring(handle) })
    end
    return nil
  end

  native_handles.gpu = handle
  if Brainstorm.debug.enabled then
    log:info("Loaded GPU DLL (experimental)", { path = dll_path })
  end

  -- Log hardware info when available
  if handle.get_hardware_info then
    local info_ptr = handle.get_hardware_info()
    if info_ptr then
      local hardware_info = ffi.string(info_ptr)
      if Brainstorm.debug.enabled then
        log:info("GPU hardware info", { info = hardware_info })
      end
    end
  end

  return handle
end

-- Stop auto-reroll and clean up resources
-- Parameters:
--   success: Whether a matching seed was found
function Brainstorm.stop_auto_reroll(success)
  Brainstorm.ar_active = false
  Brainstorm.ar_frames = 0

  -- Remove UI text if present
  if Brainstorm.ar_text then
    if Brainstorm.ar_text.AT then
      Brainstorm.remove_attention_text(Brainstorm.ar_text)
    end
    Brainstorm.ar_text = nil
  end

  -- Print final debug report
  if Brainstorm.debug.enabled and Brainstorm.debug.seeds_tested > 0 then
    Brainstorm.print_debug_report(success)
  end

  -- Reset debug stats
  Brainstorm.debug.seeds_tested = 0
  Brainstorm.debug.seeds_found = 0
  Brainstorm.debug.start_time = 0
  Brainstorm.debug.highest_suit_ratio = 0
  Brainstorm.debug.highest_face_count = 0
  Brainstorm.debug.rejection_reasons = {
    face_cards = 0,
    suit_ratio = 0,
    dll_filter = 0,
  }
  Brainstorm.debug.distributions = {
    face_cards = {},
    suit_ratios = {},
  }
end

-- Generate and test seeds using the native DLL
-- Returns a matching seed or nil if none found
function Brainstorm.auto_reroll()
  -- Generate a pseudo-random seed based on cursor position and time
  local seed_found = random_string(
    8,
    G.CONTROLLER.cursor_hover.T.x * SEED_X_FACTOR
      + G.CONTROLLER.cursor_hover.T.y * SEED_Y_FACTOR
      + SEED_TIME_FACTOR * G.CONTROLLER.cursor_hover.time
  )

  -- Load native DLL with error handling (cache DLL handle)
  if not init_ffi() then
    print("[Brainstorm] FFI initialization failed")
    return nil
  end

  local immolate = load_cpu_native()
  if not immolate then
    return nil
  end

  if Brainstorm.config.use_gpu_experimental then
    local gpu_handle = load_gpu_native()
    if gpu_handle then
      immolate = gpu_handle
      Brainstorm.debug.gpu_enabled = true
    else
      Brainstorm.debug.gpu_enabled = false
    end
  else
    Brainstorm.debug.gpu_enabled = false
  end
  -- Extract pack name from configuration
  local pack = ""
  if #Brainstorm.config.ar_filters.pack > 0 then
    pack = Brainstorm.config.ar_filters.pack[1]:match("^(.*)_") or ""
  end
  local pack_name = pack ~= ""
      and localize({ type = "name_text", set = "Other", key = pack })
    or ""
  local tag_name = ""
  if
    Brainstorm.config.ar_filters.tag_name
    and Brainstorm.config.ar_filters.tag_name ~= ""
  then
    tag_name = localize({
      type = "name_text",
      set = "Tag",
      key = Brainstorm.config.ar_filters.tag_name,
    }) or ""
  end
  local tag2_name = ""
  if
    Brainstorm.config.ar_filters.tag2_name
    and Brainstorm.config.ar_filters.tag2_name ~= ""
  then
    tag2_name = localize({
      type = "name_text",
      set = "Tag",
      key = Brainstorm.config.ar_filters.tag2_name,
    })
  end
  local voucher_name = ""
  if
    Brainstorm.config.ar_filters.voucher_name
    and Brainstorm.config.ar_filters.voucher_name ~= ""
  then
    voucher_name = localize({
      type = "name_text",
      set = "Voucher",
      key = Brainstorm.config.ar_filters.voucher_name,
    }) or ""
  end

  -- Smart compatibility layer: Detect DLL version and use appropriate call
  -- Enhanced DLL (8 params) supports dual tags internally for 10-100x speedup
  -- Original DLL (7 params) requires external validation (slower)
  local result = nil

  -- Track DLL usage for performance metrics
  if Brainstorm.debug.enabled then
    Brainstorm.debug.dll_calls = (Brainstorm.debug.dll_calls or 0) + 1
  end

  -- Try enhanced DLL first (8 parameters with dual tag support)
  local enhanced_success, enhanced_result = pcall(function()
    return immolate.brainstorm(
      seed_found,
      voucher_name,
      pack_name,
      tag_name,
      tag2_name, -- 8th parameter for enhanced DLL
      Brainstorm.config.ar_filters.soul_skip,
      Brainstorm.config.ar_filters.inst_observatory,
      Brainstorm.config.ar_filters.inst_perkeo
    )
  end)

  if enhanced_success then
    -- Enhanced DLL detected and working!
    result = enhanced_result
    if
      tag2_name ~= ""
      and Brainstorm.debug.enabled
      and not Brainstorm.debug.dll_mode_logged
    then
      if Brainstorm.debug.enabled then
        log:info("Using enhanced DLL for dual tag search")
      end
      Brainstorm.debug.dll_mode_logged = true
    end
  else
    -- Fall back to original DLL (7 parameters, no dual tag support)
    -- This path is slower for dual tags as it requires game restarts
    if Brainstorm.debug.enabled and not Brainstorm.debug.dll_mode_logged then
      log:warn("Using original DLL (compatibility mode)")
      if tag2_name ~= "" then
        log:warn("Dual tag search will be slower - consider upgrading DLL")
      end
      Brainstorm.debug.dll_mode_logged = true
    end

    -- Old DLL only checks for first tag
    local call_success, call_result = pcall(function()
      return immolate.brainstorm(
        seed_found,
        voucher_name,
        pack_name,
        tag_name, -- Only first tag for old DLL
        Brainstorm.config.ar_filters.soul_skip,
        Brainstorm.config.ar_filters.inst_observatory,
        Brainstorm.config.ar_filters.inst_perkeo
      )
    end)

    if call_success then
      result = call_result
    else
      if Brainstorm.debug.enabled then
        log:error("DLL call failed", { error = tostring(call_result) })
      end
      return nil
    end
  end

  seed_found = result and ffi.string(result) or nil

  -- Free memory if enhanced DLL (always try to free for both versions)
  if result then
    if immolate.free_result then
      local free_success = pcall(immolate.free_result, result)
      if not free_success and Brainstorm.debug.enabled then
        log:warn("Failed to free DLL result memory")
      end
    end
  end

  -- Return the seed without restarting the game
  -- The caller will decide whether to restart based on deck validation
  return seed_found
end

-- Hook to color-code filtered seeds in the UI
-- Filtered seeds appear in blue instead of red
local cursr = create_UIBox_round_scores_row
function create_UIBox_round_scores_row(score, text_colour)
  local ret = cursr(score, text_colour)
  -- Color logic: Red for manual seeds, Blue for filtered seeds, Black otherwise
  ret.nodes[2].nodes[1].config.colour = (score == "seed" and G.GAME.seeded)
      and G.C.RED
    or (score == "seed" and G.GAME.used_filter) and G.C.BLUE
    or G.C.BLACK
  return ret
end

-- TODO: Rework attention text.
function Brainstorm.attention_text(args)
  args = args or {}
  args.text = args.text or "test"
  args.scale = args.scale or 1
  args.colour = copy_table(args.colour or G.C.WHITE)
  args.hold = (args.hold or 0) + 0.1 * G.SPEEDFACTOR
  args.pos = args.pos or { x = 0, y = 0 }
  args.align = args.align or "cm"
  args.emboss = args.emboss or nil

  args.fade = 1

  if args.cover then
    args.cover_colour = copy_table(args.cover_colour or G.C.RED)
    args.cover_colour_l = copy_table(lighten(args.cover_colour, 0.2))
    args.cover_colour_d = copy_table(darken(args.cover_colour, 0.2))
  else
    args.cover_colour = copy_table(G.C.CLEAR)
  end

  args.uibox_config = {
    align = args.align or "cm",
    offset = args.offset or { x = 0, y = 0 },
    major = args.cover or args.major or nil,
  }

  G.E_MANAGER:add_event(Event({
    trigger = "after",
    delay = 0,
    blockable = false,
    blocking = false,
    func = function()
      args.AT = UIBox({
        T = { args.pos.x, args.pos.y, 0, 0 },
        definition = {
          n = G.UIT.ROOT,
          config = {
            align = args.cover_align or "cm",
            minw = (args.cover and args.cover.T.w or 0.001)
              + (args.cover_padding or 0),
            minh = (args.cover and args.cover.T.h or 0.001)
              + (args.cover_padding or 0),
            padding = 0.03,
            r = 0.1,
            emboss = args.emboss,
            colour = args.cover_colour,
          },
          nodes = {
            {
              n = G.UIT.O,
              config = {
                draw_layer = 1,
                object = DynaText({
                  scale = args.scale,
                  string = args.text,
                  maxw = args.maxw,
                  colours = { args.colour },
                  float = true,
                  shadow = true,
                  silent = not args.noisy,
                  pop_in = 0,
                  pop_in_rate = 6,
                  rotate = args.rotate or nil,
                }),
              },
            },
          },
        },
        config = args.uibox_config,
      })
      args.AT.attention_text = true

      args.text = args.AT.UIRoot.children[1].config.object
      args.text:pulse(0.5)

      if args.cover then
        Particles(args.pos.x, args.pos.y, 0, 0, {
          timer_type = "TOTAL",
          timer = 0.01,
          pulse_max = 15,
          max = 0,
          scale = 0.3,
          vel_variation = 0.2,
          padding = 0.1,
          fill = true,
          lifespan = 0.5,
          speed = 2.5,
          attach = args.AT.UIRoot,
          colours = {
            args.cover_colour,
            args.cover_colour_l,
            args.cover_colour_d,
          },
        })
      end
      if args.backdrop_colour then
        args.backdrop_colour = copy_table(args.backdrop_colour)
        Particles(args.pos.x, args.pos.y, 0, 0, {
          timer_type = "TOTAL",
          timer = 5,
          scale = 2.4 * (args.backdrop_scale or 1),
          lifespan = 5,
          speed = 0,
          attach = args.AT,
          colours = { args.backdrop_colour },
        })
      end
      return true
    end,
  }))
  return args
end

function Brainstorm.remove_attention_text(args)
  if not args or not args.AT then
    return -- Nothing to remove
  end

  G.E_MANAGER:add_event(Event({
    trigger = "after",
    delay = 0,
    blockable = false,
    blocking = false,
    func = function()
      if not args.start_time then
        args.start_time = G.TIMERS.TOTAL
        if args.text and args.text.pop_out then
          args.text:pop_out(2)
        end
      else
        args.fade = math.max(0, 1 - 3 * (G.TIMERS.TOTAL - args.start_time))
        if args.cover_colour then
          args.cover_colour[4] = math.min(args.cover_colour[4], 2 * args.fade)
        end
        if args.cover_colour_l then
          args.cover_colour_l[4] = math.min(args.cover_colour_l[4], args.fade)
        end
        if args.cover_colour_d then
          args.cover_colour_d[4] = math.min(args.cover_colour_d[4], args.fade)
        end
        if args.backdrop_colour then
          args.backdrop_colour[4] = math.min(args.backdrop_colour[4], args.fade)
        end
        if args.colour then
          args.colour[4] = math.min(args.colour[4], args.fade)
        end
        if args.fade <= 0 and args.AT then
          args.AT:remove()
          return true
        end
      end
    end,
  }))
end
