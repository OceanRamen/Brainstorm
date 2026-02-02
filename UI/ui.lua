local lovely = require("lovely")
local nativefs = require("nativefs")

local tag_list = {
  ["None"] = "",
  ["Uncommon Tag"] = "tag_uncommon",
  ["Rare Tag"] = "tag_rare",
  ["Holographic Tag"] = "tag_holo",
  ["Foil Tag"] = "tag_foil",
  ["Polychrome Tag"] = "tag_polychrome",
  ["Investment Tag"] = "tag_investment",
  ["Voucher Tag"] = "tag_voucher",
  ["Boss Tag"] = "tag_boss",
  ["Charm Tag"] = "tag_charm",
  ["Juggle Tag"] = "tag_juggle",
  ["Double Tag"] = "tag_double",
  ["Coupon Tag"] = "tag_coupon",
  ["Economy Tag"] = "tag_economy",
  ["Skip Tag"] = "tag_skip",
  ["D6 Tag"] = "tag_d_six",
}

local voucher_list = {
  ["None"] = "",
  ["Overstock"] = "v_overstock_norm",
  ["Clearance Sale"] = "v_clearance_sale",
  ["Hone"] = "v_hone",
  ["Reroll Surplus"] = "v_reroll_surplus",
  ["Crystal Ball"] = "v_crystal_ball",
  ["Telescope"] = "v_telescope",
  ["Grabber"] = "v_grabber",
  ["Wasteful"] = "v_wasteful",
  ["Tarot Merchant"] = "v_tarot_merchant",
  ["Planet Merchant"] = "v_planet_merchant",
  ["Seed Money"] = "v_seed_money",
  ["Blank"] = "v_blank",
  ["Magic Trick"] = "v_magic_trick",
  ["Hieroglyph"] = "v_hieroglyph",
  ["Director's Cut"] = "v_directors_cut",
  ["Paint Brush"] = "v_paint_brush",
}

local pack_list = {
  ["None"] = {},
  ["Normal Arcana"] = {
    "p_arcana_normal_1",
    "p_arcana_normal_2",
    "p_arcana_normal_3",
    "p_arcana_normal_4",
  },
  ["Jumbo Arcana"] = { "p_arcana_jumbo_1", "p_arcana_jumbo_2" },
  ["Mega Arcana"] = { "p_arcana_mega_1", "p_arcana_mega_2" },
  ["Normal Celestial"] = {
    "p_celestial_normal_1",
    "p_celestial_normal_2",
    "p_celestial_normal_3",
    "p_celestial_normal_4",
  },
  ["Jumbo Celestial"] = { "p_celestial_jumbo_1", "p_celestial_jumbo_2" },
  ["Mega Celestial"] = { "p_celestial_mega_1", "p_celestial_mega_2" },
  ["Normal Standard"] = {
    "p_standard_normal_1",
    "p_standard_normal_2",
    "p_standard_normal_3",
    "p_standard_normal_4",
  },
  ["Jumbo Standard"] = { "p_standard_jumbo_1", "p_standard_jumbo_2" },
  ["Mega Standard"] = { "p_standard_mega_1", "p_standard_mega_2" },
  ["Normal Buffoon"] = { "p_buffoon_normal_1", "p_buffoon_normal_2" },
  ["Jumbo Buffoon"] = { "p_buffoon_jumbo_1" },
  ["Mega Buffoon"] = { "p_buffoon_mega_1" },
  ["Normal Spectral"] = { "p_spectral_normal_1", "p_spectral_normal_2" },
  ["Jumbo Spectral"] = { "p_spectral_jumbo_1" },
  ["Mega Spectral"] = { "p_spectral_mega_1" },
}

-- Joker location options for search
local joker_location_list = {
  ["Any"] = "any",
  ["Shop"] = "shop",
  ["Buffoon Pack"] = "pack",
}

local joker_location_keys = { "Any", "Shop", "Buffoon Pack" }

-- Dynamic joker list (populated when game data is available)
local joker_list = { ["None"] = "" }
local joker_keys = { "None" }

-- Build joker list from game data
local function build_joker_list()
  if not G or not G.P_CENTER_POOLS or not G.P_CENTER_POOLS.Joker then
    return
  end
  
  joker_list = { ["None"] = "" }
  joker_keys = { "None" }
  
  local temp_jokers = {}
  for _, joker in ipairs(G.P_CENTER_POOLS.Joker) do
    if joker.key and joker.key ~= "" then
      local display_name = localize({ type = "name_text", set = "Joker", key = joker.key }) or joker.key
      table.insert(temp_jokers, { name = display_name, key = joker.key })
    end
  end
  
  -- Sort alphabetically by display name
  table.sort(temp_jokers, function(a, b) return a.name < b.name end)
  
  for _, joker in ipairs(temp_jokers) do
    joker_list[joker.name] = joker.key
    table.insert(joker_keys, joker.name)
  end
end

local spf_list = {
  ["500"] = 500,
  ["750"] = 750,
  ["1000"] = 1000,
}

local spf_keys = { "500", "750", "1000" }

local ratio_list = {
  ["50%"] = 0.5,
  ["60%"] = 0.6,
  ["70%"] = 0.7,
  ["75%"] = 0.75,
  ["80%"] = 0.80,
}

local ratio_keys = { "50%", "60%", "70%", "75%", "80%" }

local voucher_keys = {
  "None",
  "Overstock",
  "Clearance Sale",
  "Hone",
  "Reroll Surplus",
  "Crystal Ball",
  "Telescope",
  "Grabber",
  "Wasteful",
  "Tarot Merchant",
  "Planet Merchant",
  "Seed Money",
  "Blank",
  "Magic Trick",
  "Hieroglyph",
  "Director's Cut",
  "Paint Brush",
}

local tag_keys = {
  "None",
  "Charm Tag",
  "Double Tag",
  "Uncommon Tag",
  "Rare Tag",
  "Holographic Tag",
  "Foil Tag",
  "Polychrome Tag",
  "Investment Tag",
  "Voucher Tag",
  "Boss Tag",
  "Juggle Tag",
  "Coupon Tag",
  "Economy Tag",
  "Skip Tag",
  "D6 Tag",
}
local pack_keys = {
  "None",
  "Normal Arcana",
  "Jumbo Arcana",
  "Mega Arcana",
  "Normal Celestial",
  "Jumbo Celestial",
  "Mega Celestial",
  "Normal Standard",
  "Jumbo Standard",
  "Mega Standard",
  "Normal Buffoon",
  "Jumbo Buffoon",
  "Mega Buffoon",
  "Normal Spectral",
  "Jumbo Spectral",
  "Mega Spectral",
}

G.FUNCS.change_target_voucher = function(x)
  Brainstorm.config.ar_filters.voucher_id = x.to_key
  Brainstorm.config.ar_filters.voucher_name = voucher_list[x.to_val]
  Brainstorm.writeConfig()
end

G.FUNCS.change_target_pack = function(x)
  Brainstorm.config.ar_filters.pack_id = x.to_key
  Brainstorm.config.ar_filters.pack = pack_list[x.to_val]
  Brainstorm.writeConfig()
end

G.FUNCS.change_target_tag = function(x)
  Brainstorm.config.ar_filters.tag_id = x.to_key
  Brainstorm.config.ar_filters.tag_name = tag_list[x.to_val]
  Brainstorm.writeConfig()
end

G.FUNCS.change_soul_count = function(x)
  Brainstorm.config.ar_filters.soul_skip = x.to_val
  Brainstorm.writeConfig()
end

G.FUNCS.change_spf = function(x)
  Brainstorm.config.ar_prefs.spf_id = x.to_key
  Brainstorm.config.ar_prefs.spf_int = spf_list[x.to_val]
  Brainstorm.writeConfig()
end

G.FUNCS.change_face_count = function(x)
	Brainstorm.config.ar_prefs.face_count = x.to_val
	Brainstorm.writeConfig()
end

G.FUNCS.change_suit_ratio = function(x)
	Brainstorm.config.ar_prefs.suit_ratio_percent = x.to_key
  Brainstorm.config.ar_prefs.suit_ratio_decimal = ratio_list[x.to_val]
	Brainstorm.writeConfig()
end

G.FUNCS.change_target_joker = function(x)
  Brainstorm.config.ar_filters.joker_id = x.to_key
  Brainstorm.config.ar_filters.joker_key = joker_list[x.to_val]
  Brainstorm.writeConfig()
end

G.FUNCS.change_joker_location = function(x)
  Brainstorm.config.ar_filters.joker_location_id = x.to_key
  Brainstorm.config.ar_filters.joker_location = joker_location_list[x.to_val]
  Brainstorm.writeConfig()
end

Brainstorm.opt_ref = G.FUNCS.options
G.FUNCS.options = function(e)
  Brainstorm.opt_ref(e)
end

local ct = create_tabs
function create_tabs(args)
  if args and args.tab_h == 7.05 then
    -- Build joker list when opening settings (game data now available)
    build_joker_list()
    
    args.tabs[#args.tabs + 1] = {
      label = "Brainstorm",
      tab_definition_function = function()
        return {
          n = G.UIT.ROOT,
          config = {
            align = "cm",
            padding = 0.05,
            colour = G.C.CLEAR,
          },
          nodes = {
            {
              n = G.UIT.C,
              config = {
                align = "cm",
                padding = 0.05,
                r = 0.1,
                colour = darken(G.C.UI.TRANSPARENT_DARK, 0.25),
              },
              nodes = {
                create_option_cycle({
                  label = "AR: TAG SEARCH",
                  scale = 0.8,
                  w = 4,
                  options = tag_keys,
                  opt_callback = "change_target_tag",
                  current_option = Brainstorm.config.ar_filters.tag_id or 1,
                }),
                create_option_cycle({
                  label = "AR: VOUCHER SEARCH",
                  scale = 0.8,
                  w = 4,
                  options = voucher_keys,
                  opt_callback = "change_target_voucher",
                  current_option = Brainstorm.config.ar_filters.voucher_id or 1,
                }),
                create_option_cycle({
                  label = "AR: PACK SEARCH",
                  scale = 0.8,
                  w = 4,
                  options = pack_keys,
                  opt_callback = "change_target_pack",
                  current_option = Brainstorm.config.ar_filters.pack_id or 1,
                }),
                create_option_cycle({
                  label = "AR: N. SOULS",
                  scale = 0.8,
                  w = 4,
                  options = { 0, 1 },
                  opt_callback = "change_soul_count",
                  current_option = Brainstorm.config.ar_filters.soul_skip + 1
                    or 1,
                }),
                create_option_cycle({
                  label = "AR: JOKER SEARCH",
                  scale = 0.8,
                  w = 4,
                  options = joker_keys,
                  opt_callback = "change_target_joker",
                  current_option = Brainstorm.config.ar_filters.joker_id or 1,
                }),
                create_option_cycle({
                  label = "AR: JOKER LOCATION",
                  scale = 0.8,
                  w = 4,
                  options = joker_location_keys,
                  opt_callback = "change_joker_location",
                  current_option = Brainstorm.config.ar_filters.joker_location_id or 1,
                }),
              },
            },
            {
              n = G.UIT.C,
              config = {
                align = "cm",
                padding = 0.05,
                r = 0.1,
                colour = darken(G.C.UI.TRANSPARENT_DARK, 0.25),
              },
              nodes = {
                create_option_cycle({
                  label = "AP: Seeds per frame",
                  scale = 0.8,
                  w = 4,
                  options = spf_keys,
                  opt_callback = "change_spf",
                  current_option = Brainstorm.config.ar_prefs.spf_id or 1,
                }),
                create_toggle({
                  label = "AR: INST OBSERVATORY",
                  scale = 0.8,
                  ref_table = Brainstorm.config.ar_filters,
                  ref_value = "inst_observatory",
                  callback = function(_set_toggle) end,
                }),
                create_toggle({
                  label = "AR: INST PERKEO",
                  scale = 0.8,
                  ref_table = Brainstorm.config.ar_filters,
                  ref_value = "inst_perkeo",
                  callback = function(_set_toggle) end,
                }),
                create_option_cycle({
                  label = "ED: Min. # of Face Cards",
                  scale = 0.8,
                  w = 4,
                  options = {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25},
                  opt_callback = "change_face_count",
                  current_option = Brainstorm.config.ar_prefs.face_count + 1 or 1,
                }),
                create_option_cycle({
                  label = "ED: Suit Ratio ",
                  scale = 0.8,
                  w = 4,
                  options = ratio_keys,
                  opt_callback = "change_suit_ratio",
                  current_option = Brainstorm.config.ar_prefs.suit_ratio_percent,
                }),
              },
            },
          },
        }
      end,
      tab_definition_function_args = "Brainstorm",
    }
  end
  return ct(args)
end
