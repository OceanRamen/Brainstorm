local lovely = require("lovely")
local nfs = require("nativefs")
local ffi = require("ffi")

Brainstorm = {}

Brainstorm.VERSION = "Brainstorm v2.2.0-alpha"

Brainstorm.SMODS = nil

Brainstorm.DEFAULT_CONFIG = {
	enable = true,
	keybinds = {
		options = "t",
		modifier = "lctrl",
		f_reroll = "r",
		a_reroll = "a",
	},
	ar_filters = {
		pack = {},
		pack_id = 1,
		tag_name = "tag_charm",
		tag_id = 2,
		soul_skip = 1,
	},
	ar_prefs = {
		spf_id = 3,
		spf_int = 1000,
	},
	active_filter_id = nil,
	debug = false,
}

Brainstorm.config = {}
Brainstorm.filters = {}
Brainstorm.filters_list = {}

Brainstorm.ar_timer = 0
Brainstorm.ar_frames = 0
Brainstorm.ar_text = nil
Brainstorm.ar_active = false
Brainstorm.AR_INTERVAL = 0.01
Brainstorm.immolate = nil
Brainstorm.immolate_cdef = false
Brainstorm.immolate_status = "unloaded"

-- Cache frequently used functions
local math_abs = math.abs
local string_format = string.format
local string_lower = string.lower

local function debugLog(...)
	if Brainstorm.config and Brainstorm.config.debug then
		print("Brainstorm:", ...)
	end
end

local function findBrainstormDirectory(directory)
	for _, item in ipairs(nfs.getDirectoryItems(directory)) do
		local itemPath = directory .. "/" .. item
		if nfs.getInfo(itemPath, "directory") and string_lower(item):find("brainstorm") then
			return itemPath
		end
	end
	return nil
end

local function ensureImmolateLoaded()
	if Brainstorm.immolate then
		Brainstorm.immolate_status = "loaded"
		return true
	end

	if not Brainstorm.immolate_cdef then
		ffi.cdef([[const char* brainstorm(const char* seed, const char* pack, const char* tag, double souls);]])
		ffi.cdef([[const char* brainstorm_query(const char* seed, const char* query_json);]])
		ffi.cdef([[void free_result(const char* result);]])
		Brainstorm.immolate_cdef = true
	end

	local ok, lib = pcall(ffi.load, Brainstorm.PATH .. "/Immolate.dll")
	if not ok then
		debugLog("Failed to load Immolate.dll:", tostring(lib))
		Brainstorm.immolate_status = "missing"
		return false
	end

	Brainstorm.immolate = lib
	Brainstorm.immolate_status = "loaded"
	return true
end

local function fileExists(filePath)
	return nfs.getInfo(filePath) ~= nil
end

local function mergeConfig(defaults, loaded)
	local merged = {}
	for key, value in pairs(defaults) do
		local incoming = loaded and loaded[key]
		if type(value) == "table" then
			merged[key] = mergeConfig(value, type(incoming) == "table" and incoming or {})
		elseif type(incoming) == type(value) then
			merged[key] = incoming
		else
			merged[key] = value
		end
	end
	return merged
end

function Brainstorm.loadConfig()
	local configPath = Brainstorm.PATH .. "/config.lua"
	if not fileExists(configPath) then
		Brainstorm.config = mergeConfig(Brainstorm.DEFAULT_CONFIG)
		Brainstorm.writeConfig()
		return
	end

	local configFile, err = nfs.read(configPath)
	if not configFile then
		error("Failed to read config file: " .. (err or "unknown error"))
	end
	local unpacked = STR_UNPACK(configFile) or {}
	Brainstorm.config = mergeConfig(Brainstorm.DEFAULT_CONFIG, unpacked)
	Brainstorm.writeConfig()
end

local function isArray(t)
	local count = 0
	for k in pairs(t) do
		if type(k) ~= "number" then
			return false
		end
		count = count + 1
	end
	return count == #t
end

local function escapeString(str)
	return str:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("%c", function(c)
		return string_format("\\u%04x", c:byte())
	end)
end

function Brainstorm.toJSON(val)
	local t = type(val)
	if t == "nil" then
		return "null"
	elseif t == "boolean" then
		return val and "true" or "false"
	elseif t == "number" then
		return tostring(val)
	elseif t == "string" then
		return '"' .. escapeString(val) .. '"'
	elseif t == "table" then
		if isArray(val) then
			local parts = {}
			for i = 1, #val do
				parts[#parts + 1] = Brainstorm.toJSON(val[i])
			end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local parts = {}
		for k, v in pairs(val) do
			if type(k) == "string" then
				parts[#parts + 1] = '"' .. escapeString(k) .. '":' .. Brainstorm.toJSON(v)
			end
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "null"
end

function Brainstorm.loadFilters()
	Brainstorm.filters = {}
	Brainstorm.filters_list = {}
	local filters_dir = Brainstorm.PATH .. "/filters"
	if not nfs.getInfo(filters_dir, "directory") then
		nfs.createDirectory(filters_dir)
		return
	end
	for _, item in ipairs(nfs.getDirectoryItems(filters_dir)) do
		if item:sub(-8) == ".bff.lua" then
			local filePath = filters_dir .. "/" .. item
			local chunk, err = load(nfs.read(filePath))
			if chunk then
				local ok, data = pcall(chunk)
				if ok and type(data) == "table" then
					if data.version == 1 and data.id and data.label then
						local entry = {
							id = data.id,
							label = data.label,
							description = data.description,
							query_json = data.query_json,
						}
						if not entry.query_json and data.query then
							entry.query_json = Brainstorm.toJSON(data.query)
						end
						if entry.query_json then
							Brainstorm.filters[entry.id] = entry
							Brainstorm.filters_list[#Brainstorm.filters_list + 1] = entry
						end
					else
						debugLog("Filter missing required fields in", item)
					end
				else
					debugLog("Failed to load filter", item, tostring(data))
				end
			else
				debugLog("Failed to compile filter", item, tostring(err))
			end
		end
	end
end

function Brainstorm.getActiveFilter()
	if not Brainstorm.config.active_filter_id then
		return nil
	end
	return Brainstorm.filters[Brainstorm.config.active_filter_id]
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
	if not Brainstorm.PATH then
		error("Brainstorm: could not locate mod directory")
	end

	Brainstorm.loadConfig()
	Brainstorm.loadFilters()
	Brainstorm.AR_INTERVAL = Brainstorm.getAutoInterval()
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

function Brainstorm.reroll()
	local G_ref = G
	G_ref.GAME.viewed_back = nil
	G_ref.run_setup_seed = G_ref.GAME.seeded
	G_ref.challenge_tab = G_ref.GAME and G_ref.GAME.challenge and G_ref.GAME.challenge_tab or nil
	G_ref.forced_seed = G_ref.GAME.seeded and G_ref.GAME.pseudorandom.seed or nil

	local seed = G_ref.run_setup_seed and G_ref.setup_seed or G_ref.forced_seed
	local stake = (G_ref.GAME.stake or G_ref.PROFILES[G_ref.SETTINGS.profile].MEMORY.stake or 1) or 1

	G_ref:delete_run()
	G_ref:start_run({ stake = stake, seed = seed, challenge = G_ref.challenge_tab })
end

local update_ref = Game.update
function Game:update(dt)
	update_ref(self, dt)

	if Brainstorm.ar_active then
		Brainstorm.ar_frames = Brainstorm.ar_frames + 1
		Brainstorm.ar_timer = Brainstorm.ar_timer + dt
		local interval = Brainstorm.getAutoInterval()

		if Brainstorm.ar_timer >= interval then
			Brainstorm.ar_timer = Brainstorm.ar_timer - interval
			if Brainstorm.autoReroll() then
				Brainstorm.ar_active = false
				Brainstorm.ar_frames = 0
				if Brainstorm.ar_text then
					Brainstorm.removeAttentionText(Brainstorm.ar_text)
					Brainstorm.ar_text = nil
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

function Brainstorm.getAutoInterval()
	local spf = Brainstorm.config.ar_prefs and Brainstorm.config.ar_prefs.spf_int or 1000
	local clamped = math.max(100, math.min(1000, spf))
	return 10 / clamped
end

function Brainstorm.getImmolateStatus()
	return Brainstorm.immolate_status or "unloaded"
end

function Brainstorm.autoReroll()
	local cursor = G.CONTROLLER and G.CONTROLLER.cursor_hover
	local entropy
	if cursor and cursor.T then
		entropy = cursor.T.x * 0.33411983 + cursor.T.y * 0.874146 + 0.412311010 * cursor.time
	else
		entropy = love.timer.getTime()
	end
	local seed_found = random_string(8, entropy)

	local filters = Brainstorm.config.ar_filters
	local pack_key = ""
	if #filters.pack > 0 then
		pack_key = filters.pack[1]:match("^(.*)_") or ""
	end
	local pack_name = localize({ type = "name_text", set = "Other", key = pack_key }) or ""
	local tag_name = localize({
		type = "name_text",
		set = "Tag",
		key = filters.tag_name,
	}) or ""

	if not ensureImmolateLoaded() or not Brainstorm.immolate.brainstorm then
		Brainstorm.ar_active = false
		debugLog("Immolate not available; disabling auto-reroll")
		return nil
	end

	local active_filter = Brainstorm.getActiveFilter()
	local seed_ptr
	if active_filter and Brainstorm.immolate.brainstorm_query then
		seed_ptr = Brainstorm.immolate.brainstorm_query(seed_found, active_filter.query_json)
	else
		seed_ptr = Brainstorm.immolate.brainstorm(
			seed_found,
			pack_name,
			tag_name,
			filters.soul_skip
		)
	end
	if not seed_ptr then
		return nil
	end
	seed_found = ffi.string(seed_ptr)
	if Brainstorm.immolate.free_result then
		Brainstorm.immolate.free_result(seed_ptr)
	end
	if not seed_found or seed_found == "" then
		return nil
	end

	local current_stake = G.GAME.stake
	G:delete_run()
	G:start_run({
		stake = current_stake,
		seed = seed_found,
		challenge = G.GAME and G.GAME.challenge and G.GAME.challenge_tab,
	})
	G.GAME.used_filter = true
	G.GAME.filter_info = {
		filter_params = {
			seed_found,
			pack_name,
			tag_name,
			filters.soul_skip,
		},
	}
	G.GAME.seeded = false
	return seed_found
end

local cursr = create_UIBox_round_scores_row
function create_UIBox_round_scores_row(score, text_colour)
	local ret = cursr(score, text_colour)
	ret.nodes[2].nodes[1].config.colour = (score == "seed" and G.GAME.seeded) and G.C.RED
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
						minw = (args.cover and args.cover.T.w or 0.001) + (args.cover_padding or 0),
						minh = (args.cover and args.cover.T.h or 0.001) + (args.cover_padding or 0),
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
