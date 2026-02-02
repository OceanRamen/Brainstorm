local lovely = require("lovely")
local nfs = require("nativefs")

Brainstorm = {}

Brainstorm.VERSION = "Brainstorm v2.2.0-alpha"

Brainstorm.SMODS = nil

Brainstorm.config = {
  enable = true,
  keybind_autoreroll = "r",
  keybinds = {
    options = "t",
    modifier = "lctrl",
    f_reroll = "r",
    a_reroll = "a",
  },
  ar_filters = {
    pack = {},
    pack_id = 1,
    voucher_name = "",
    voucher_id = 1,
    tag_name = "tag_charm",
    tag_id = 2,
    soul_skip = 1,
    inst_observatory = false,
    inst_perkeo = false,
    joker_key = "",
    joker_id = 1,
    joker_location = "any",
    joker_location_id = 1,
  },
  ar_prefs = {
    spf_id = 3,
    spf_int = 1000,
    face_count = 0,
    suut_ratio_percent = "50%",
  },
}

Brainstorm.ar_timer = 0
Brainstorm.ar_frames = 0
Brainstorm.ar_text = nil
Brainstorm.ar_active = false
Brainstorm.AR_INTERVAL = 0.01

-- Cache frequently used functions
local math_abs = math.abs
local string_format = string.format
local string_lower = string.lower

local function findBrainstormDirectory(directory)
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

local function fileExists(filePath)
  return nfs.getInfo(filePath) ~= nil
end

function Brainstorm.loadConfig()
  local configPath = Brainstorm.PATH .. "/config.lua"
  if not fileExists(configPath) then
    Brainstorm.writeConfig()
  else
    local configFile, err = nfs.read(configPath)
    if not configFile then
      error("Failed to read config file: " .. (err or "unknown error"))
    end
    Brainstorm.config = STR_UNPACK(configFile) or Brainstorm.config
  end
end

function Brainstorm.writeConfig()
  local configPath = Brainstorm.PATH .. "/config.lua"
  local success, err = nfs.write(configPath, STR_PACK(Brainstorm.config))
  if not success then
    error("Failed to write config file: " .. (err or "unknown error"))
  end
end

function Brainstorm.init()
  Brainstorm.PATH = findBrainstormDirectory(lovely.mod_dir)
  Brainstorm.loadConfig()
  assert(load(nfs.read(Brainstorm.PATH .. "/UI/ui.lua")))()
end

local key_press_update_ref = Controller.key_press_update
function Controller:key_press_update(key, dt)
  key_press_update_ref(self, key, dt)
  local keybinds = Brainstorm.config.keybinds
  if love.keyboard.isDown(keybinds.modifier) then
    if key == keybinds.f_reroll then
      Brainstorm.reroll()
    elseif key == keybinds.a_reroll then
      Brainstorm.ar_active = not Brainstorm.ar_active
    end
  end
end

function analyze_deck()
  local deck_summary = {}
  local suit_count = {Hearts = 0, Diamonds = 0, Clubs = 0, Spades = 0}
  local face_card_count = 0
  local numeric_card_count = 0
  local ace_count = 0
  local unique_card_count = 0

  for _, card in ipairs(G.playing_cards) do
      if card.base then
          local card_name = card.base.value .. " of " .. card.base.suit
          deck_summary[card_name] = (deck_summary[card_name] or 0) + 1
          suit_count[card.base.suit] = (suit_count[card.base.suit] or 0) + 1

          -- Categorizing cards
          if card.base.value == "Ace" then
              ace_count = ace_count + 1
          elseif card.base.value == "Jack" or card.base.value == "Queen" or card.base.value == "King" then
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
      unique_card_count = unique_card_count
  }
end

function print_deck_summary(deck_data)
  print("----- Deck Breakdown -----")
  print(string.format("Total Unique Cards: %d", deck_data.unique_card_count))
  print(string.format("Face Cards (J, Q, K): %d", deck_data.face_card_count))
  print(string.format("Numeric Cards (2-10): %d", deck_data.numeric_card_count))
  print(string.format("Aces: %d", deck_data.ace_count))

  print("\nSuit Distribution:")
  for suit, count in pairs(deck_data.suit_count) do
      print(string.format("%s: %d", suit, count))
  end

  print("\nCard Breakdown:")
  for card_name, count in pairs(deck_data.deck_summary) do
      print(string.format("%s: %d", card_name, count))
  end
end

function is_valid_deck(deck_data, min_face_cards, min_aces, dominant_suit_ratio)
  -- Ensure parameters are not nil by providing default values
  min_face_cards = min_face_cards or 0
  min_aces = min_aces or 0
  dominant_suit_ratio = dominant_suit_ratio or 0

  -- Extract counts from the deck analysis
  local total_cards = #G.playing_cards
  local face_card_count = deck_data.face_card_count or 0
  local ace_count = deck_data.ace_count or 0
  local suit_count = deck_data.suit_count or 0

  -- Check Face Cards & Aces
  if face_card_count < min_face_cards then
      --print("Not enough face cards:", face_card_count, "Required:", min_face_cards)
      return false
  end
  if ace_count < min_aces then
      --print("Not enough aces:", ace_count, "Required:", min_aces)
      return false
  end

  -- Check suit distribution
  local sorted_suits = {}
  for suit, count in pairs(suit_count) do
      table.insert(sorted_suits, {suit = suit, count = count})
  end
  table.sort(sorted_suits, function(a, b) return a.count > b.count end)

  -- Sum the top 2 suit counts
  local top_2_suit_count = sorted_suits[1].count + (sorted_suits[2] and sorted_suits[2].count or 0)
  local top_2_suit_percentage = top_2_suit_count / total_cards

  if top_2_suit_percentage < dominant_suit_ratio then
      --print("Suit distribution is too spread out.")
      return false
  end

  return true
end

function Brainstorm.reroll()
  local G = G -- Cache global G for performance
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

local update_ref = Game.update
function Game:update(dt)
  update_ref(self, dt)

  if Brainstorm.ar_active then
    Brainstorm.ar_frames = Brainstorm.ar_frames + 1
    Brainstorm.ar_timer = Brainstorm.ar_timer + dt

    if Brainstorm.ar_timer >= Brainstorm.AR_INTERVAL then
      Brainstorm.ar_timer = Brainstorm.ar_timer - Brainstorm.AR_INTERVAL
      local seed_found = Brainstorm.autoReroll()
      if seed_found then
        if G.GAME.starting_params.erratic_suits_and_ranks then
          local deck_data = analyze_deck()        
          if is_valid_deck(deck_data, Brainstorm.config.ar_prefs.face_count, 0, Brainstorm.config.ar_prefs.suit_ratio_decimal) then
            Brainstorm.ar_active = false -- STOP REROLLING
            Brainstorm.ar_frames = 0
            if Brainstorm.ar_text then
              Brainstorm.removeAttentionText(Brainstorm.ar_text)
              Brainstorm.ar_text = nil
            end
          end
        else
          Brainstorm.ar_active = false -- STOP REROLLING
            Brainstorm.ar_frames = 0
            if Brainstorm.ar_text then
              Brainstorm.removeAttentionText(Brainstorm.ar_text)
              Brainstorm.ar_text = nil
            end
        end
      end
    end
    if Brainstorm.ar_frames == 60 and not Brainstorm.ar_text then
      Brainstorm.ar_text = Brainstorm.attentionText({
        scale = 1.4,
        text = "Rerolling...",
        align = "cm",
        offset = { x = 0, y = -3.5 },
        major = G.STAGE == G.STAGES.RUN and G.play or G.title_top,
      })
    end
  end
end

local ffi = require("ffi")
local lovely = require("lovely")
ffi.cdef([[
const char* brainstorm(const char* seed, const char* voucher, const char* pack, const char* tag, double souls, bool observatory, bool perkeo);
  ]])

-- Joker search helper: simulate RNG for prediction without modifying game state
local function predict_pseudoseed(key, predict_seed, temp_state)
  if not temp_state[key] then
    temp_state[key] = pseudohash(key .. (predict_seed or ""))
  end
  temp_state[key] = math.abs(tonumber(string.format("%.13f", (2.134453429141 + temp_state[key] * 1.72431234) % 1)))
  return (temp_state[key] + (pseudohash(predict_seed) or 0)) / 2
end

-- Simulate shop jokers for a given seed, returns true if target joker is found
local function simulate_shop_jokers(predict_seed, target_joker)
  local shop_slots = 2
  local temp_state = {}
  
  for i = 1, shop_slots do
    -- Determine card type for this slot
    local type_seed = predict_pseudoseed("cdt1", predict_seed, temp_state)
    local type_poll = pseudorandom(type_seed)
    
    -- Default rates from base game
    local joker_rate = 20
    local total_rate = 20 + 4 + 4 + 4 -- joker + tarot + planet + playing_card
    local polled_rate = type_poll * total_rate
    
    if polled_rate <= joker_rate then
      -- This slot generates a Joker
      local rarity_seed = predict_pseudoseed("rarity1sho", predict_seed, temp_state)
      local rarity_roll = pseudorandom(rarity_seed)
      
      local rarity = 1
      if rarity_roll > 0.95 then
        rarity = 3
      elseif rarity_roll > 0.7 then
        rarity = 2
      end
      
      local joker_seed = predict_pseudoseed("Joker" .. rarity .. "sho1", predict_seed, temp_state)
      local joker_center = pseudorandom_element(G.P_JOKER_RARITY_POOLS[rarity], joker_seed)
      
      if joker_center and joker_center.key == target_joker then
        return true
      end
    end
  end
  return false
end

-- Simulate buffoon pack jokers for a given seed, returns true if target joker is found
local function simulate_buffoon_pack_jokers(pack_key, predict_seed, target_joker)
  local joker_count = 2
  if string.find(pack_key, "jumbo") or string.find(pack_key, "mega") then
    joker_count = 4
  end
  
  local temp_state = {}
  
  for i = 1, joker_count do
    local rarity_seed = predict_pseudoseed("rarity1buf", predict_seed, temp_state)
    local rarity_roll = pseudorandom(rarity_seed)
    
    local rarity = 1
    if rarity_roll > 0.95 then
      rarity = 3
    elseif rarity_roll > 0.7 then
      rarity = 2
    end
    
    local joker_seed = predict_pseudoseed("Joker" .. rarity .. "buf1", predict_seed, temp_state)
    local joker_center = pseudorandom_element(G.P_JOKER_RARITY_POOLS[rarity], joker_seed)
    
    if joker_center and joker_center.key == target_joker then
      return true
    end
  end
  return false
end

-- Check if seed contains target joker in buffoon packs available in shop
local function check_buffoon_packs_for_joker(predict_seed, target_joker)
  local temp_state = {}
  
  -- Check both shop pack slots
  for slot = 1, 2 do
    local cume, it, center = 0, 0, nil
    for _, v in ipairs(G.P_CENTER_POOLS["Booster"]) do
      cume = cume + (v.weight or 1)
    end
    
    local poll_seed = predict_pseudoseed("shop_pack" .. slot, predict_seed, temp_state)
    local poll = pseudorandom(poll_seed) * cume
    
    for _, v in ipairs(G.P_CENTER_POOLS["Booster"]) do
      it = it + (v.weight or 1)
      if it >= poll and it - (v.weight or 1) <= poll then
        center = v
        break
      end
    end
    
    if center and string.find(center.key, "buffoon") then
      if simulate_buffoon_pack_jokers(center.key, predict_seed, target_joker) then
        return true
      end
    end
  end
  return false
end

-- Main joker search function, called after FFI returns a candidate seed
local function check_seed_for_joker(seed, target_joker, location)
  if not target_joker or target_joker == "" then
    return true -- No joker filter active
  end
  
  local found = false
  
  if location == "shop" or location == "any" then
    if simulate_shop_jokers(seed, target_joker) then
      found = true
    end
  end
  
  if not found and (location == "pack" or location == "any") then
    if check_buffoon_packs_for_joker(seed, target_joker) then
      found = true
    end
  end
  
  return found
end

function Brainstorm.autoReroll()
  local seed_found = random_string(
    8,
    G.CONTROLLER.cursor_hover.T.x * 0.33411983
      + G.CONTROLLER.cursor_hover.T.y * 0.874146
      + 0.412311010 * G.CONTROLLER.cursor_hover.time
  )

  local immolate = ffi.load(Brainstorm.PATH .. "/Immolate.dll")
  local pack
  if #Brainstorm.config.ar_filters.pack > 0 then
    pack = Brainstorm.config.ar_filters.pack[1]:match("^(.*)_")
  else
    pack = {}
  end
  local pack_name = localize({ type = "name_text", set = "Other", key = pack })
  local tag_name = localize({
    type = "name_text",
    set = "Tag",
    key = Brainstorm.config.ar_filters.tag_name,
  })
  local voucher_name = localize({
    type = "name_text",
    set = "Voucher",
    key = Brainstorm.config.ar_filters.voucher_name,
  })
  --print(pack_name, tag_name, voucher_name)
  seed_found = ffi.string(
    immolate.brainstorm(
      seed_found,
      voucher_name,
      pack_name,
      tag_name,
      Brainstorm.config.ar_filters.soul_skip,
      Brainstorm.config.ar_filters.inst_observatory,
      Brainstorm.config.ar_filters.inst_perkeo
    )
  )
  
  -- Post-filter: check for joker if joker search is active
  if seed_found and seed_found ~= "" then
    local target_joker = Brainstorm.config.ar_filters.joker_key
    local joker_location = Brainstorm.config.ar_filters.joker_location
    
    if not check_seed_for_joker(seed_found, target_joker, joker_location) then
      -- Seed doesn't have the target joker, reject it
      return nil
    end
  end
  
  if seed_found and seed_found ~= "" then
    _stake = G.GAME.stake
    G:delete_run()
    G:start_run({
      stake = _stake,
      seed = seed_found,
      challenge = G.GAME and G.GAME.challenge and G.GAME.challenge_tab,
    })
    G.GAME.used_filter = true
    G.GAME.filter_info = {
      filter_params = {
        seed_found,
        voucher_name,
        pack_name,
        tag_name,
        Brainstorm.config.ar_filters.soul_skip,
        Brainstorm.config.ar_filters.inst_observatory,
        Brainstorm.config.ar_filters.inst_perkeo,
      },
    }
    G.GAME.seeded = false
  end
  return seed_found
end

local cursr = create_UIBox_round_scores_row
function create_UIBox_round_scores_row(score, text_colour)
  local ret = cursr(score, text_colour)
  ret.nodes[2].nodes[1].config.colour = (score == "seed" and G.GAME.seeded)
      and G.C.RED
    or (score == "seed" and G.GAME.used_filter) and G.C.BLUE
    or G.C.BLACK
  return ret
end

-- TODO: Rework attention text.
function Brainstorm.attentionText(args)
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
                  args.scale,
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

function Brainstorm.removeAttentionText(args)
  G.E_MANAGER:add_event(Event({
    trigger = "after",
    delay = 0,
    blockable = false,
    blocking = false,
    func = function()
      if not args.start_time then
        args.start_time = G.TIMERS.TOTAL
        if args.text.pop_out then
          args.text:pop_out(2)
        end
      else
        --args.AT:align_to_attach()
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
        args.colour[4] = math.min(args.colour[4], args.fade)
        if args.fade <= 0 then
          args.AT:remove()
          return true
        end
      end
    end,
  }))
end
