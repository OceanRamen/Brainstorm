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
local spf_list = {
	["500"] = 500,
	["750"] = 750,
	["1000"] = 1000,
}

local spf_keys = { "500", "750", "1000" }

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

local function filter_labels()
	local labels = { "Legacy (manual)" }
	for _, f in ipairs(Brainstorm.filters_list or {}) do
		labels[#labels + 1] = f.label
	end
	return labels
end

local function filter_current_option()
	if not Brainstorm.config.active_filter_id then
		return 1
	end
	for idx, f in ipairs(Brainstorm.filters_list or {}) do
		if f.id == Brainstorm.config.active_filter_id then
			return idx + 1
		end
	end
	return 1
end

G.FUNCS.change_active_filter = function(x)
	local key = x.to_key or 1
	if key == 1 then
		Brainstorm.config.active_filter_id = nil
	else
		local entry = Brainstorm.filters_list[key - 1]
		Brainstorm.config.active_filter_id = entry and entry.id or nil
	end
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

Brainstorm.opt_ref = G.FUNCS.options
G.FUNCS.options = function(e)
	Brainstorm.opt_ref(e)
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
									label = "FILTER SOURCE",
									scale = 0.8,
									w = 4,
									options = filter_labels(),
									opt_callback = "change_active_filter",
									current_option = filter_current_option(),
								}),
								create_option_cycle({
									label = "TAG SEARCH",
									scale = 0.8,
									w = 4,
									options = tag_keys,
									opt_callback = "change_target_tag",
									current_option = Brainstorm.config.ar_filters.tag_id or 1,
								}),
								create_option_cycle({
									label = "PACK SEARCH",
									scale = 0.8,
									w = 4,
									options = pack_keys,
									opt_callback = "change_target_pack",
									current_option = Brainstorm.config.ar_filters.pack_id or 1,
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
									label = "# of seeds to search per frame",
									scale = 0.8,
									w = 4,
									options = spf_keys,
									opt_callback = "change_spf",
									current_option = Brainstorm.config.ar_prefs.spf_id or 1,
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
