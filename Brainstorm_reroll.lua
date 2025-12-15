local lovely = require("lovely")
local nativefs = require("nativefs")

Brainstorm.AUTOREROLL = {}

G.FUNCS.change_search_tag = function(x)
	Brainstorm.SETTINGS.autoreroll.searchTagID = x.to_key
	Brainstorm.SETTINGS.autoreroll.searchTag = Brainstorm.SearchTagList[x.to_val]
	nativefs.write(lovely.mod_dir .. "/Brainstorm/settings.lua", STR_PACK(Brainstorm.SETTINGS))
end

G.FUNCS.change_search_pack = function(x)
	Brainstorm.SETTINGS.autoreroll.searchPackID = x.to_key
	Brainstorm.SETTINGS.autoreroll.searchPack = Brainstorm.SearchPackList[x.to_val]
	-- Reset joker search when switching away from buffoon packs
	if not string.find(x.to_val, "Buffoon") then
		Brainstorm.SETTINGS.autoreroll.searchJokerID = 1
		Brainstorm.SETTINGS.autoreroll.searchJoker = ""
	end
	nativefs.write(lovely.mod_dir .. "/Brainstorm/settings.lua", STR_PACK(Brainstorm.SETTINGS))
end

G.FUNCS.change_search_joker = function(x)
	Brainstorm.SETTINGS.autoreroll.searchJokerID = x.to_key
	Brainstorm.SETTINGS.autoreroll.searchJoker = Brainstorm.SearchJokerList[x.to_val]
	nativefs.write(lovely.mod_dir .. "/Brainstorm/settings.lua", STR_PACK(Brainstorm.SETTINGS))
end

G.FUNCS.change_search_soul_count = function(x)
	Brainstorm.SETTINGS.autoreroll.searchForSoul = x.to_val
	nativefs.write(lovely.mod_dir .. "/Brainstorm/settings.lua", STR_PACK(Brainstorm.SETTINGS))
end

G.FUNCS.change_seeds_per_frame = function(x)
	Brainstorm.SETTINGS.autoreroll.seedsPerFrameID = x.to_key
	Brainstorm.SETTINGS.autoreroll.seedsPerFrame = Brainstorm.seedsPerFrame[x.to_val]
	nativefs.write(lovely.mod_dir .. "/Brainstorm/settings.lua", STR_PACK(Brainstorm.SETTINGS))
end

Brainstorm.AUTOREROLL.autoRerollActive = false
Brainstorm.AUTOREROLL.rerollInterval = 0.01 -- Time interval between rerolls (in seconds)
Brainstorm.AUTOREROLL.rerollTimer = 0

function FastReroll()
	G.GAME.viewed_back = nil
	G.run_setup_seed = G.GAME.seeded
	G.challenge_tab = G.GAME and G.GAME.challenge and G.GAME.challenge_tab or nil
	G.forced_seed, G.setup_seed = nil, nil
	if G.GAME.seeded then
		G.forced_seed = G.GAME.pseudorandom.seed
	end
	local current_stake = G.GAME.stake
	local _seed = G.run_setup_seed and G.setup_seed or G.forced_seed or nil
	local _challenge = G.challenge_tab
	if not G.challenge_tab then
		_stake = current_stake or G.PROFILES[G.SETTINGS.profile].MEMORY.stake or 1
	else
		_stake = 1
	end
	G:delete_run()
	G:start_run({ stake = _stake, seed = _seed, challenge = _challenge })
end

function Brainstorm.auto_reroll()
	local rerollsThisFrame = 0
	-- This part is meant to mimic how Balatro rerolls for Gold Stake
	local extra_num = -0.561892350821
	local seed_found = nil
	
	-- Debug: Show what we're searching for
	if Brainstorm.SETTINGS.debug_mode and Brainstorm.SETTINGS.autoreroll.searchJoker and Brainstorm.SETTINGS.autoreroll.searchJoker ~= "" then
		sendDebugMessage("[Brainstorm] AUTO-REROLL ACTIVE - Searching for joker: " .. Brainstorm.SETTINGS.autoreroll.searchJoker)
	end
	while not seed_found and rerollsThisFrame < Brainstorm.SETTINGS.autoreroll.seedsPerFrame do
		rerollsThisFrame = rerollsThisFrame + 1
		extra_num = extra_num + 0.561892350821
		seed_found = random_string(
			8,
			extra_num
				+ G.CONTROLLER.cursor_hover.T.x * 0.33411983
				+ G.CONTROLLER.cursor_hover.T.y * 0.874146
				+ 0.412311010 * G.CONTROLLER.cursor_hover.time
		)
		Brainstorm.random_state = {
			hashed_seed = pseudohash(seed_found),
		}
		if Brainstorm.SETTINGS.autoreroll.searchTag ~= "" then
			_tag = pseudorandom_element(G.P_CENTER_POOLS["Tag"], Brainstorm.pseudoseed("Tag1" .. seed_found)).key
			if _tag ~= Brainstorm.SETTINGS.autoreroll.searchTag then
				seed_found = nil
			end
		end
		if seed_found and Brainstorm.SETTINGS.autoreroll.searchForSoul then
			-- Check if arcana pack from skip has The Soul
			for i = 1, Brainstorm.SETTINGS.autoreroll.searchForSoul do
				local soul_found = false
				for i = 1, 5 do
					if pseudorandom(Brainstorm.pseudoseed("soul_Tarot1" .. seed_found)) > 0.997 then
						soul_found = true
					end
				end
				if not soul_found then
					seed_found = nil
					break
				end
			end
		end
		-- Check for joker search (works independently or with pack search)
		if seed_found and Brainstorm.SETTINGS.autoreroll.searchJoker and Brainstorm.SETTINGS.autoreroll.searchJoker ~= "" then
			if Brainstorm.SETTINGS.debug_mode then
				sendDebugMessage("[Brainstorm] Checking seed: " .. seed_found .. " for joker: " .. Brainstorm.SETTINGS.autoreroll.searchJoker)
			end
			local joker_found = false
			-- Check both shop pack slots for buffoon packs
			for slot = 1, 2 do
				local slot_cume, slot_it, slot_center = 0, 0, nil
				for k, v in ipairs(G.P_CENTER_POOLS['Booster']) do
					if (not _type or _type == v.kind) then slot_cume = slot_cume + (v.weight or 1) end
				end
				local slot_poll = pseudorandom(Brainstorm.pseudoseed("shop_pack"..slot..seed_found))*slot_cume
				for k, v in ipairs(G.P_CENTER_POOLS['Booster']) do
					if not _type or _type == v.kind then slot_it = slot_it + (v.weight or 1) end
					if slot_it >= slot_poll and slot_it - (v.weight or 1) <= slot_poll then
						slot_center = v
						break
					end
				end
				-- If this slot has a buffoon pack, check for the joker
				if slot_center then
					if Brainstorm.SETTINGS.debug_mode then
						sendDebugMessage("[Brainstorm] Slot " .. slot .. " pack: " .. slot_center.key)
					end
					if string.find(slot_center.key, "buffoon") then
						-- If pack search is active, verify this is the right pack type
						local pack_type_matches = true
						if Brainstorm.SETTINGS.autoreroll.searchPack and #Brainstorm.SETTINGS.autoreroll.searchPack > 0 then
							pack_type_matches = false
							for i = 1, #Brainstorm.SETTINGS.autoreroll.searchPack do
								if Brainstorm.SETTINGS.autoreroll.searchPack[i] == slot_center.key then
									pack_type_matches = true
									break
								end
							end
						end
						
						if pack_type_matches then
							if Brainstorm.SETTINGS.debug_mode then
								sendDebugMessage("[Brainstorm] Found buffoon pack, simulating...")
							end
							if simulate_buffoon_pack_jokers(slot_center.key, seed_found) then
								if Brainstorm.SETTINGS.debug_mode then
									sendDebugMessage("[Brainstorm] *** JOKER FOUND! ***")
								end
								joker_found = true
								break  -- Early exit once joker is found
							else
								if Brainstorm.SETTINGS.debug_mode then
									sendDebugMessage("[Brainstorm] Joker not in this pack")
								end
							end
						end
					end
				end
			end
			if not joker_found then
				seed_found = nil
			end
		elseif seed_found and Brainstorm.SETTINGS.autoreroll.searchPack and #Brainstorm.SETTINGS.autoreroll.searchPack > 0 then
			-- Pack-only search (no joker specified)
		    local cume, it, center = 0, 0, nil
			for k, v in ipairs(G.P_CENTER_POOLS['Booster']) do
				if (not _type or _type == v.kind) then cume = cume + (v.weight or 1 ) end
			end
			local poll = pseudorandom(Brainstorm.pseudoseed("shop_pack1"..seed_found))*cume
			for k, v in ipairs(G.P_CENTER_POOLS['Booster']) do
				if not _type or _type == v.kind then it = it + (v.weight or 1) end
				if it >= poll and it - (v.weight or 1) <= poll then center = v
break end
			end
			local pack_found = false
			for i = 1, #Brainstorm.SETTINGS.autoreroll.searchPack do
				if Brainstorm.SETTINGS.autoreroll.searchPack[i] == center.key then
					pack_found = true
					break
				end
			end
			if not pack_found then
				seed_found = nil
			end
		end
		--[[
		Relevant vanilla pack code
		    local cume, it, center = 0, 0, nil
			for k, v in ipairs(G.P_CENTER_POOLS['Booster']) do
				if (not _type or _type == v.kind) and not G.GAME.banned_keys[v.key] then cume = cume + (v.weight or 1 ) end
			end
			local poll = pseudorandom(pseudoseed((_key or 'pack_generic')..G.GAME.round_resets.ante))*cume
			for k, v in ipairs(G.P_CENTER_POOLS['Booster']) do
				if not G.GAME.banned_keys[v.key] then 
					if not _type or _type == v.kind then it = it + (v.weight or 1) end
					if it >= poll and it - (v.weight or 1) <= poll then center = v; break end
				end
			end
			return center
		]]
	end
	if seed_found then
		_stake = G.GAME.stake
		G:delete_run()
		G:start_run({
			stake = _stake,
			seed = seed_found,
			challenge = G.GAME and G.GAME.challenge and G.GAME.challenge_tab,
		})
		G.GAME.seeded = false
	end
	return seed_found
end

function Brainstorm.searchParametersMet()
	--note: this appears to be deprecated, so I didn't update it
	if not G or not G.GAME or not G.GAME.round_resets or not G.GAME.round_resets.blind_tags then
		print("One or more variables are nil or undefined")
		return false
	end

	local _tag = G.GAME.round_resets.blind_tags.Small
	if not _tag then
		print("Value of _tag is nil or undefined")
		return false
	end

	if _tag == Brainstorm.SETTINGS.autoreroll.searchTag then
		if Brainstorm.SETTINGS.autoreroll.searchForSoul then
			return true
		end
		-- Check if arcana pack from skip has The Soul
		Brainstorm.random_state = copy_table(G.GAME.pseudorandom)
		for i = 1, 5 do
			if pseudorandom(Brainstorm.pseudoseed("soul_Tarot1")) > 0.997 then
				return true
			end
		end
		return false
	else
		return false
	end
end

function wait(seconds)
	local start = os.clock()
	while os.clock() - start < seconds do
		-- Busy wait
	end
end

function simulate_buffoon_pack_jokers(pack_key, predict_seed)
	if Brainstorm.SETTINGS.debug_mode then
		sendDebugMessage("[Brainstorm] simulate_buffoon_pack_jokers called with pack: " .. pack_key .. ", seed: " .. (predict_seed or "nil"))
	end
	
	-- Determine joker count based on pack type
	local joker_count = 2  -- Default for Normal Buffoon
	if string.find(pack_key, "jumbo") then
		joker_count = 4  -- Jumbo Buffoon: 4 jokers, pick 1
	elseif string.find(pack_key, "mega") then
		joker_count = 4  -- Mega Buffoon: 4 jokers, pick 2
	end
	if Brainstorm.SETTINGS.debug_mode then
		sendDebugMessage("[Brainstorm] Simulating " .. joker_count .. " jokers")
	end

	-- Initialize a temporary RNG state for this simulation
	-- This mimics how Balatro's G.GAME.pseudorandom works but for prediction
	local temp_random_state = {}
	
	-- Simulate each joker slot in the pack
	-- Note: Jokers within packs use 'buf' as key_append, with ante 1 for first shop
	-- IMPORTANT: In Balatro, calling pseudoseed with the same key multiple times
	-- returns different values because it maintains and advances state for each key
	for i = 1, joker_count do
		-- Determine rarity using Balatro's algorithm
		-- Seed pattern: 'rarity' + ante + 'buf' (ante = 1 for first shop)
		-- We need to simulate state advancement, so we'll use a helper that tracks calls
		local rarity_key = "rarity1buf"
		if not temp_random_state[rarity_key] then
			temp_random_state[rarity_key] = pseudohash(rarity_key .. (predict_seed or ''))
		end
		temp_random_state[rarity_key] = math.abs(tonumber(string.format("%.13f", (2.134453429141 + temp_random_state[rarity_key] * 1.72431234) % 1)))
		local rarity_seed_value = (temp_random_state[rarity_key] + (pseudohash(predict_seed) or 0)) / 2
		local rarity_roll = pseudorandom(rarity_seed_value)
		
		local rarity = 1  -- Common
		local rarity_name = "Common"
		if rarity_roll > 0.95 then
			rarity = 3  -- Rare
			rarity_name = "Rare"
		elseif rarity_roll > 0.7 then
			rarity = 2  -- Uncommon
			rarity_name = "Uncommon"
		end
		if Brainstorm.SETTINGS.debug_mode then
			sendDebugMessage("[Brainstorm]   Joker #" .. i .. " rarity roll: " .. rarity_roll .. " -> " .. rarity_name)
		end

		-- Select joker from the rarity pool
		-- Seed pattern: 'Joker' + rarity + 'buf' + ante
		local joker_key = "Joker" .. rarity .. "buf1"
		if not temp_random_state[joker_key] then
			temp_random_state[joker_key] = pseudohash(joker_key .. (predict_seed or ''))
		end
		temp_random_state[joker_key] = math.abs(tonumber(string.format("%.13f", (2.134453429141 + temp_random_state[joker_key] * 1.72431234) % 1)))
		local joker_seed_value = (temp_random_state[joker_key] + (pseudohash(predict_seed) or 0)) / 2
		local joker_center = pseudorandom_element(G.P_JOKER_RARITY_POOLS[rarity], joker_seed_value)

		-- Check if this is the joker we're searching for
		if joker_center then
			if Brainstorm.SETTINGS.debug_mode then
				sendDebugMessage("[Brainstorm]   Generated: " .. joker_center.key .. " (" .. (joker_center.name or "unknown") .. ")")
			end
			if joker_center.key == Brainstorm.SETTINGS.autoreroll.searchJoker then
				if Brainstorm.SETTINGS.debug_mode then
					sendDebugMessage("[Brainstorm]   *** MATCH! ***")
				end
				return true
			end
		else
			if Brainstorm.SETTINGS.debug_mode then
				sendDebugMessage("[Brainstorm]   ERROR: Failed to generate joker")
			end
		end
	end

	return false
end

function Brainstorm.pseudoseed(key, predict_seed)
	if key == "seed" then
		return math.random()
	end

	if predict_seed then
		local _pseed = pseudohash(key .. (predict_seed or ""))
		_pseed = math.abs(tonumber(string.format("%.13f", (2.134453429141 + _pseed * 1.72431234) % 1)))
		return (_pseed + (pseudohash(predict_seed) or 0)) / 2
	end

	if not Brainstorm.random_state[key] then
		Brainstorm.random_state[key] = pseudohash(key .. (Brainstorm.random_state.seed or ""))
	end

	Brainstorm.random_state[key] =
		math.abs(tonumber(string.format("%.13f", (2.134453429141 + Brainstorm.random_state[key] * 1.72431234) % 1)))
	return (Brainstorm.random_state[key] + (Brainstorm.random_state.hashed_seed or 0)) / 2
end

--Used for reroll UI
--Based on Balatro's attention_text
function Brainstorm.attention_text(args)
    args = args or {}
    args.text = args.text or 'test'
    args.scale = args.scale or 1
    args.colour = copy_table(args.colour or G.C.WHITE)
    args.hold = (args.hold or 0) + 0.1*(G.SPEEDFACTOR)
    args.pos = args.pos or {x = 0, y = 0}
    args.align = args.align or 'cm'
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
      align = args.align or 'cm',
      offset = args.offset or {x=0,y=0}, 
      major = args.cover or args.major or nil,
    }

    G.E_MANAGER:add_event(Event({
      trigger = 'after',
      delay = 0,
      blockable = false,
      blocking = false,
      func = function()
          args.AT = UIBox{
            T = {args.pos.x,args.pos.y,0,0},
            definition = 
              {n=G.UIT.ROOT, config = {align = args.cover_align or 'cm', minw = (args.cover and args.cover.T.w or 0.001) + (args.cover_padding or 0), minh = (args.cover and args.cover.T.h or 0.001) + (args.cover_padding or 0), padding = 0.03, r = 0.1, emboss = args.emboss, colour = args.cover_colour}, nodes={
                {n=G.UIT.O, config={draw_layer = 1, object = DynaText({scale = args.scale, string = args.text, maxw = args.maxw, colours = {args.colour},float = true, shadow = true, silent = not args.noisy, args.scale, pop_in = 0, pop_in_rate = 6, rotate = args.rotate or nil})}},
              }}, 
            config = args.uibox_config
          }
          args.AT.attention_text = true

          args.text = args.AT.UIRoot.children[1].config.object
          args.text:pulse(0.5)

          if args.cover then
            Particles(args.pos.x,args.pos.y, 0,0, {
              timer_type = 'TOTAL',
              timer = 0.01,
              pulse_max = 15,
              max = 0,
              scale = 0.3,
              vel_variation = 0.2,
              padding = 0.1,
              fill=true,
              lifespan = 0.5,
              speed = 2.5,
              attach = args.AT.UIRoot,
              colours = {args.cover_colour, args.cover_colour_l, args.cover_colour_d},
          })
          end
          if args.backdrop_colour then
            args.backdrop_colour = copy_table(args.backdrop_colour)
            Particles(args.pos.x,args.pos.y,0,0,{
              timer_type = 'TOTAL',
              timer = 5,
              scale = 2.4*(args.backdrop_scale or 1), 
              lifespan = 5,
              speed = 0,
              attach = args.AT,
              colours = {args.backdrop_colour}
            })
          end
          return true
      end
      }))
      return args
end

function Brainstorm.remove_attention_text(args)
    G.E_MANAGER:add_event(Event({
        trigger = 'after',
        delay = 0,
        blockable = false,
        blocking = false,
        func = function()
          if not args.start_time then
            args.start_time = G.TIMERS.TOTAL
            args.text:pop_out(3)
          else
            --args.AT:align_to_attach()
            args.fade = math.max(0, 1 - 3*(G.TIMERS.TOTAL - args.start_time))
            if args.cover_colour then args.cover_colour[4] = math.min(args.cover_colour[4], 2*args.fade) end
            if args.cover_colour_l then args.cover_colour_l[4] = math.min(args.cover_colour_l[4], args.fade) end
            if args.cover_colour_d then args.cover_colour_d[4] = math.min(args.cover_colour_d[4], args.fade) end
            if args.backdrop_colour then args.backdrop_colour[4] = math.min(args.backdrop_colour[4], args.fade) end
            args.colour[4] = math.min(args.colour[4], args.fade)
            if args.fade <= 0 then
              args.AT:remove()
              return true
            end
          end
        end
      }))
end