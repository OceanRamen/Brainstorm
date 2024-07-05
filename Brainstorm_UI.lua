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
							label = "Deck View: Hide Played Cards",
							ref_table = Brainstorm.SETTINGS,
							ref_value = "hide_played",
							callback = function(_set_toggle)
                nativefs.write(lovely.mod_dir .. "/Brainstorm/settings.lua", STR_PACK(Brainstorm.SETTINGS))
							end,
						}),
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

function G.UIDEF.view_deck(unplayed_only)
	local deck_tables = {}
	remove_nils(G.playing_cards)
	G.VIEWING_DECK = true
	table.sort(G.playing_cards, function(a, b)
		return a:get_nominal("suit") > b:get_nominal("suit")
	end)
	local SUITS = {
		Spades = {},
		Hearts = {},
		Clubs = {},
		Diamonds = {},
	}
	local suit_map = { "Spades", "Hearts", "Clubs", "Diamonds" }
	for k, v in ipairs(G.playing_cards) do
		table.insert(SUITS[v.base.suit], v)
	end
	for j = 1, 4 do
		if SUITS[suit_map[j]][1] then
			local view_deck = CardArea(
				G.ROOM.T.x + 0.2 * G.ROOM.T.w / 2,
				G.ROOM.T.h,
				6.5 * G.CARD_W,
				0.6 * G.CARD_H,
				{
					card_limit = #SUITS[suit_map[j]],
					type = "title",
					view_deck = true,
					highlight_limit = 0,
					card_w = G.CARD_W * 0.7,
					draw_layers = { "card" },
				}
			)
			table.insert(
				deck_tables,
				{
					n = G.UIT.R,
					config = { align = "cm", padding = 0 },
					nodes = {
						{ n = G.UIT.O, config = { object = view_deck } },
					},
				}
			)
			local card_count = 0
			for i = 1, #SUITS[suit_map[j]] do
				if SUITS[suit_map[j]][i] then
					local greyed, _scale = nil, 0.7
					if
						unplayed_only
						and not (
							(SUITS[suit_map[j]][i].area and SUITS[suit_map[j]][i].area == G.deck)
							or SUITS[suit_map[j]][i].ability.wheel_flipped
						)
					then
						greyed = true
					end
            if not greyed and Brainstorm.SETTINGS.hide_played then
              card_count = card_count + 1
              local copy = copy_card(SUITS[suit_map[j]][i], nil, _scale)
              copy.greyed = greyed
              copy.T.x = view_deck.T.x + view_deck.T.w / 2
              copy.T.y = view_deck.T.y

              copy:hard_set_T()
              view_deck:emplace(copy)
            else if not Brainstorm.SETTINGS.hide_played then
              card_count = card_count + 1
              local copy = copy_card(SUITS[suit_map[j]][i], nil, _scale)
              copy.greyed = greyed
              copy.T.x = view_deck.T.x + view_deck.T.w / 2
              copy.T.y = view_deck.T.y

              copy:hard_set_T()
              view_deck:emplace(copy)
            end
          end
				end
			end
			view_deck.config.card_limit = card_count
		end
	end

	local flip_col = G.C.WHITE

	local suit_tallies = { ["Spades"] = 0, ["Hearts"] = 0, ["Clubs"] = 0, ["Diamonds"] = 0 }
	local mod_suit_tallies = { ["Spades"] = 0, ["Hearts"] = 0, ["Clubs"] = 0, ["Diamonds"] = 0 }
	local rank_tallies = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
	local mod_rank_tallies = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
	local rank_name_mapping = { 2, 3, 4, 5, 6, 7, 8, 9, 10, "J", "Q", "K", "A" }
	local face_tally = 0
	local mod_face_tally = 0
	local num_tally = 0
	local mod_num_tally = 0
	local ace_tally = 0
	local mod_ace_tally = 0
	local wheel_flipped = 0

	for k, v in ipairs(G.playing_cards) do
		if
			v.ability.name ~= "Stone Card"
			and (not unplayed_only or ((v.area and v.area == G.deck) or v.ability.wheel_flipped))
		then
			if v.ability.wheel_flipped and unplayed_only then
				wheel_flipped = wheel_flipped + 1
			end
			--For the suits
			suit_tallies[v.base.suit] = (suit_tallies[v.base.suit] or 0) + 1
			mod_suit_tallies["Spades"] = (mod_suit_tallies["Spades"] or 0) + (v:is_suit("Spades") and 1 or 0)
			mod_suit_tallies["Hearts"] = (mod_suit_tallies["Hearts"] or 0) + (v:is_suit("Hearts") and 1 or 0)
			mod_suit_tallies["Clubs"] = (mod_suit_tallies["Clubs"] or 0) + (v:is_suit("Clubs") and 1 or 0)
			mod_suit_tallies["Diamonds"] = (mod_suit_tallies["Diamonds"] or 0) + (v:is_suit("Diamonds") and 1 or 0)

			--for face cards/numbered cards/aces
			local card_id = v:get_id()
			face_tally = face_tally + ((card_id == 11 or card_id == 12 or card_id == 13) and 1 or 0)
			mod_face_tally = mod_face_tally + (v:is_face() and 1 or 0)
			if card_id > 1 and card_id < 11 then
				num_tally = num_tally + 1
				if not v.debuff then
					mod_num_tally = mod_num_tally + 1
				end
			end
			if card_id == 14 then
				ace_tally = ace_tally + 1
				if not v.debuff then
					mod_ace_tally = mod_ace_tally + 1
				end
			end

			--ranks
			rank_tallies[card_id - 1] = rank_tallies[card_id - 1] + 1
			if not v.debuff then
				mod_rank_tallies[card_id - 1] = mod_rank_tallies[card_id - 1] + 1
			end
		end
	end

	local modded = (face_tally ~= mod_face_tally)
		or (mod_suit_tallies["Spades"] ~= suit_tallies["Spades"])
		or (mod_suit_tallies["Hearts"] ~= suit_tallies["Hearts"])
		or (mod_suit_tallies["Clubs"] ~= suit_tallies["Clubs"])
		or (mod_suit_tallies["Diamonds"] ~= suit_tallies["Diamonds"])

	if wheel_flipped > 0 then
		flip_col = mix_colours(G.C.FILTER, G.C.WHITE, 0.7)
	end

	local rank_cols = {}
	for i = 13, 1, -1 do
		local mod_delta = mod_rank_tallies[i] ~= rank_tallies[i]
		rank_cols[#rank_cols + 1] = {
			n = G.UIT.R,
			config = { align = "cm", padding = 0.07 },
			nodes = {
				{
					n = G.UIT.C,
					config = { align = "cm", r = 0.1, padding = 0.04, emboss = 0.04, minw = 0.5, colour = G.C.L_BLACK },
					nodes = {
						{
							n = G.UIT.T,
							config = {
								text = rank_name_mapping[i],
								colour = G.C.JOKER_GREY,
								scale = 0.35,
								shadow = true,
							},
						},
					},
				},
				{
					n = G.UIT.C,
					config = { align = "cr", minw = 0.4 },
					nodes = {
						mod_delta
								and {
									n = G.UIT.O,
									config = {
										object = DynaText({
											string = {
												{ string = "" .. rank_tallies[i], colour = flip_col },
												{ string = "" .. mod_rank_tallies[i], colour = G.C.BLUE },
											},
											colours = { G.C.RED },
											scale = 0.4,
											y_offset = -2,
											silent = true,
											shadow = true,
											pop_in_rate = 10,
											pop_delay = 4,
										}),
									},
								}
							or {
								n = G.UIT.T,
								config = {
									text = rank_tallies[i] or "NIL",
									colour = flip_col,
									scale = 0.45,
									shadow = true,
								},
							},
					},
				},
			},
		}
	end

	local t = {
		n = G.UIT.ROOT,
		config = { align = "cm", colour = G.C.CLEAR },
		nodes = {
			{ n = G.UIT.R, config = { align = "cm", padding = 0.05 }, nodes = {} },
			{
				n = G.UIT.R,
				config = { align = "cm" },
				nodes = {
					{
						n = G.UIT.C,
						config = { align = "cm", minw = 1.5, minh = 2, r = 0.1, colour = G.C.BLACK, emboss = 0.05 },
						nodes = {
							{
								n = G.UIT.C,
								config = { align = "cm", padding = 0.1 },
								nodes = {
									{
										n = G.UIT.R,
										config = {
											align = "cm",
											r = 0.1,
											colour = G.C.L_BLACK,
											emboss = 0.05,
											padding = 0.15,
										},
										nodes = {
											{
												n = G.UIT.R,
												config = { align = "cm" },
												nodes = {
													{
														n = G.UIT.O,
														config = {
															object = DynaText({
																string = G.GAME.selected_back.loc_name,
																colours = { G.C.WHITE },
																bump = true,
																rotate = true,
																shadow = true,
																scale = 0.6
																	- string.len(G.GAME.selected_back.loc_name)
																		* 0.01,
															}),
														},
													},
												},
											},
											{
												n = G.UIT.R,
												config = {
													align = "cm",
													r = 0.1,
													padding = 0.1,
													minw = 2.5,
													minh = 1.3,
													colour = G.C.WHITE,
													emboss = 0.05,
												},
												nodes = {
													{
														n = G.UIT.O,
														config = {
															object = UIBox({
																definition = G.GAME.selected_back:generate_UI(
																	nil,
																	0.7,
																	0.5,
																	G.GAME.challenge
																),
																config = { offset = { x = 0, y = 0 } },
															}),
														},
													},
												},
											},
										},
									},
									{
										n = G.UIT.R,
										config = {
											align = "cm",
											r = 0.1,
											outline_colour = G.C.L_BLACK,
											line_emboss = 0.05,
											outline = 1.5,
										},
										nodes = {
											{
												n = G.UIT.R,
												config = { align = "cm", minh = 0.05, padding = 0.07 },
												nodes = {
													{
														n = G.UIT.O,
														config = {
															object = DynaText({
																string = {
																	{
																		string = localize("k_base_cards"),
																		colour = G.C.RED,
																	},
																	modded
																			and {
																				string = localize("k_effective"),
																				colour = G.C.BLUE,
																			}
																		or nil,
																},
																colours = { G.C.RED },
																silent = true,
																scale = 0.4,
																pop_in_rate = 10,
																pop_delay = 4,
															}),
														},
													},
												},
											},
											{
												n = G.UIT.R,
												config = { align = "cm", minh = 0.05, padding = 0.1 },
												nodes = {
													tally_sprite(
														{ x = 1, y = 0 },
														{
															{ string = "" .. ace_tally, colour = flip_col },
															{ string = "" .. mod_ace_tally, colour = G.C.BLUE },
														},
														{ localize("k_aces") }
													), --Aces
													tally_sprite(
														{ x = 2, y = 0 },
														{
															{ string = "" .. face_tally, colour = flip_col },
															{ string = "" .. mod_face_tally, colour = G.C.BLUE },
														},
														{ localize("k_face_cards") }
													), --Face
													tally_sprite(
														{ x = 3, y = 0 },
														{
															{ string = "" .. num_tally, colour = flip_col },
															{ string = "" .. mod_num_tally, colour = G.C.BLUE },
														},
														{ localize("k_numbered_cards") }
													), --Numbers
												},
											},
											{
												n = G.UIT.R,
												config = { align = "cm", minh = 0.05, padding = 0.1 },
												nodes = {
													tally_sprite(
														{ x = 3, y = 1 },
														{
															{ string = "" .. suit_tallies["Spades"], colour = flip_col },
															{
																string = "" .. mod_suit_tallies["Spades"],
																colour = G.C.BLUE,
															},
														},
														{ localize("Spades", "suits_plural") }
													),
													tally_sprite(
														{ x = 0, y = 1 },
														{
															{ string = "" .. suit_tallies["Hearts"], colour = flip_col },
															{
																string = "" .. mod_suit_tallies["Hearts"],
																colour = G.C.BLUE,
															},
														},
														{ localize("Hearts", "suits_plural") }
													),
												},
											},
											{
												n = G.UIT.R,
												config = { align = "cm", minh = 0.05, padding = 0.1 },
												nodes = {
													tally_sprite(
														{ x = 2, y = 1 },
														{
															{ string = "" .. suit_tallies["Clubs"], colour = flip_col },
															{ string = "" .. mod_suit_tallies["Clubs"], colour = G.C.BLUE },
														},
														{ localize("Clubs", "suits_plural") }
													),
													tally_sprite(
														{ x = 1, y = 1 },
														{
															{ string = "" .. suit_tallies["Diamonds"], colour = flip_col },
															{
																string = "" .. mod_suit_tallies["Diamonds"],
																colour = G.C.BLUE,
															},
														},
														{ localize("Diamonds", "suits_plural") }
													),
												},
											},
										},
									},
								},
							},
							{ n = G.UIT.C, config = { align = "cm" }, nodes = rank_cols },
							{ n = G.UIT.B, config = { w = 0.1, h = 0.1 } },
						},
					},
					{ n = G.UIT.B, config = { w = 0.2, h = 0.1 } },
					{
						n = G.UIT.C,
						config = { align = "cm", padding = 0.1, r = 0.1, colour = G.C.BLACK, emboss = 0.05 },
						nodes = deck_tables,
					},
				},
			},
			{
				n = G.UIT.R,
				config = { align = "cm", minh = 0.8, padding = 0.05 },
				nodes = {
					modded and {
						n = G.UIT.R,
						config = { align = "cm" },
						nodes = {
							{
								n = G.UIT.C,
								config = { padding = 0.3, r = 0.1, colour = mix_colours(G.C.BLUE, G.C.WHITE, 0.7) },
								nodes = {},
							},
							{
								n = G.UIT.T,
								config = {
									text = " " .. localize("ph_deck_preview_effective"),
									colour = G.C.WHITE,
									scale = 0.3,
								},
							},
						},
					} or nil,
					wheel_flipped > 0 and {
						n = G.UIT.R,
						config = { align = "cm" },
						nodes = {
							{ n = G.UIT.C, config = { padding = 0.3, r = 0.1, colour = flip_col }, nodes = {} },
							{
								n = G.UIT.T,
								config = {
									text = " " .. (wheel_flipped > 1 and localize({
										type = "variable",
										key = "deck_preview_wheel_plural",
										vars = { wheel_flipped },
									}) or localize({
										type = "variable",
										key = "deck_preview_wheel_singular",
										vars = { wheel_flipped },
									})),
									colour = G.C.WHITE,
									scale = 0.3,
								},
							},
						},
					} or nil,
				},
			},
		},
	}
	return t
end
