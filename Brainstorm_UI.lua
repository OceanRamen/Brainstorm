local lovely = require("lovely")
local nativefs = require("nativefs")



Brainstorm.SearchTagList = {
	["None"]="",
	["Uncommon Tag"]="tag_uncommon",
	["Rare Tag"]="tag_rare",
	["Holographic Tag"]="tag_holo",
  ["Foil Tag"]="tag_foil",
	["Polychrome Tag"]="tag_polychrome",
	["Investment Tag"]="tag_investment",
	["Voucher Tag"]="tag_voucher",
	["Boss Tag"]="tag_boss",
	["Charm Tag"]="tag_charm",
	["Juggle Tag"]="tag_juggle",
	["Double Tag"]="tag_double",
	["Coupon Tag"]="tag_coupon",
	["Economy Tag"]="tag_economy",
	["Skip Tag"]="tag_skip",
	["D6 Tag"]="tag_d_six",
}

Brainstorm.SearchPackList = {
	["None"] = {},
	["Arcana"] = {"p_arcana_normal_1","p_arcana_normal_2","p_arcana_normal_3","p_arcana_normal_4","p_arcana_jumbo_1","p_arcana_jumbo_2","p_arcana_mega_1", "p_arcana_mega_2"},
	["Celestial"] = {"p_celestial_normal_1","p_celestial_normal_2","p_celestial_normal_3","p_celestial_normal_4","p_celestial_jumbo_1","p_celestial_jumbo_2","p_celestial_mega_1", "p_celestial_mega_2"},
	["Standard"] = {"p_standard_normal_1","p_standard_normal_2","p_standard_normal_3","p_standard_normal_4","p_standard_jumbo_1","p_standard_jumbo_2","p_standard_mega_1", "p_standard_mega_2"},
	["Buffoon"] = {"p_buffoon_normal_1","p_buffoon_normal_2","p_buffoon_jumbo_1","p_buffoon_mega_1"},
	["Spectral"] = {"p_spectral_normal_1","p_spectral_normal_2","p_spectral_jumbo_1","p_spectral_mega_1"},
	["Normal Arcana"] = {"p_arcana_normal_1","p_arcana_normal_2","p_arcana_normal_3","p_arcana_normal_4"},
	["Jumbo Arcana"] = {"p_arcana_jumbo_1","p_arcana_jumbo_2"},
	["Mega Arcana"] = {"p_arcana_mega_1", "p_arcana_mega_2"},
	["Normal Celestial"] = {"p_celestial_normal_1","p_celestial_normal_2","p_celestial_normal_3","p_celestial_normal_4"},
	["Jumbo Celestial"] = {"p_celestial_jumbo_1","p_celestial_jumbo_2"},
	["Mega Celestial"] = {"p_celestial_mega_1", "p_celestial_mega_2"},
	["Normal Standard"] = {"p_standard_normal_1","p_standard_normal_2","p_standard_normal_3","p_standard_normal_4"},
	["Jumbo Standard"] = {"p_standard_jumbo_1","p_standard_jumbo_2"},
	["Mega Standard"] = {"p_standard_mega_1", "p_standard_mega_2"},
	["Normal Buffoon"] = {"p_buffoon_normal_1","p_buffoon_normal_2"},
	["Jumbo Buffoon"] = {"p_buffoon_jumbo_1"},
	["Mega Buffoon"] = {"p_buffoon_mega_1"},
	["Normal Spectral"] = {"p_spectral_normal_1","p_spectral_normal_2"},
	["Jumbo Spectral"] = {"p_spectral_jumbo_1"},
	["Mega Spectral"] = {"p_spectral_mega_1"},
}
Brainstorm.seedsPerFrame = {
    ["500"] = 500,
    ["750"] = 750,
    ["1000"] = 1000,
}

local searchTagKeys = {"None", "Charm Tag", "Double Tag", "Uncommon Tag", "Rare Tag", "Holographic Tag", "Foil Tag", "Polychrome Tag", "Investment Tag", "Voucher Tag", "Boss Tag", "Juggle Tag", "Coupon Tag", "Economy Tag", "Skip Tag", "D6 Tag"}
local searchPackKeys = {"None", "Arcana", "Celestial", "Standard", "Buffoon", "Spectral", "Normal Arcana", "Jumbo Arcana", "Mega Arcana", "Normal Celestial", "Jumbo Celestial", "Mega Celestial", "Normal Standard", "Jumbo Standard", "Mega Standard", "Normal Buffoon", "Jumbo Buffoon", "Mega Buffoon", "Normal Spectral", "Jumbo Spectral", "Mega Spectral"}
local seedsPerFrame = {"500", "750", "1000"}
-- print(Brainstorm.FUNCS.inspect(searchTagKeys))

Brainstorm.G_FUNCS_options_ref = G.FUNCS.options
G.FUNCS.options = function(e)
	Brainstorm.G_FUNCS_options_ref(e)
end
local ct = create_tabs
function create_tabs(args)
	if args and args.tab_h == 7.05 then
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
						create_toggle({
							label = "Debug Mode",
							ref_table = Brainstorm.SETTINGS,
							ref_value = "debug_mode",
							callback = function(_set_toggle)
								_RELEASE_MODE = not Brainstorm.SETTINGS.debug_mode
								G.F_NO_ACHIEVEMENTS = Brainstorm.SETTINGS.debug_mode
							end,
						}),
						create_option_cycle({
							label = "AutoReroll Search Tag",
							scale = 0.8,
							w = 4,
							options = searchTagKeys,
							opt_callback = "change_search_tag",
							current_option = Brainstorm.SETTINGS.autoreroll.searchTagID or 1,
						}),
						create_option_cycle({
							label = "AutoReroll Search Pack",
							scale = 0.8,
							w = 4,
							options = searchPackKeys,
							opt_callback = "change_search_pack",
							current_option = Brainstorm.SETTINGS.autoreroll.searchPackID or 1,
						}),
						create_option_cycle({
							label = "Charm Tag/Arcana Pack: Number of Souls",
							scale = 0.8,
							w = 4,
							options = {0,1,2},
							opt_callback = "change_search_soul_count",
							current_option = Brainstorm.SETTINGS.autoreroll.searchForSoul + 1 or 1,
						}),
                        create_option_cycle({
							label = "Rerolls per Frame",
							scale = 0.8,
							w = 4,
							options = seedsPerFrame,
							opt_callback = "change_seeds_per_frame",
							current_option = Brainstorm.SETTINGS.autoreroll.seedsPerFrameID or 1,
						}),
					},
				}
			end,
			tab_definition_function_args = "Brainstorm",
		}
	end
	return ct(args)
end
function saveManagerAlert(text)
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
				offset = {
					x = 0,
					y = -3.5,
				},
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
