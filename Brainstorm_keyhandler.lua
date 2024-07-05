local lovely = require("lovely")
local nativefs = require("nativefs")

Brainstorm.AUTOREROLL = {}

local saveKeys = { "1", "2", "3", "4", "5" }

function Controller:key_press_update(key, dt)
	if self.locks.frame then
		return
	end
	if string.sub(key, 1, 2) == "kp" then
		key = string.sub(key, 3)
	end
	if key == "enter" then
		key = "return"
	end
	-- Brainstorm Key Handler
	for i, k in ipairs(saveKeys) do
		--  SaveState
		if key == k and love.keyboard.isDown(Brainstorm.SETTINGS.keybinds.saveState) then
			if G.STAGE == G.STAGES.RUN then
				compress_and_save(G.SETTINGS.profile .. "/" .. "saveState" .. k .. ".jkr", G.ARGS.save_run)
				saveManagerAlert("Saved state to slot [" .. k .. "]")
			end
		end
		--  LoadState
		if key == k and love.keyboard.isDown(Brainstorm.SETTINGS.keybinds.loadState) then
			G:delete_run()
			G.SAVED_GAME = get_compressed(G.SETTINGS.profile .. "/" .. "saveState" .. k .. ".jkr")
			if G.SAVED_GAME ~= nil then
				G.SAVED_GAME = STR_UNPACK(G.SAVED_GAME)
			end
			G:start_run({
				savetext = G.SAVED_GAME,
			})
			saveManagerAlert("Loaded save from slot [" .. k .. "]")
		end
  end
	--  FastReroll
	if key == Brainstorm.SETTINGS.keybinds.rerollSeed and love.keyboard.isDown("lctrl") then
		FastReroll()
	end
	if key == Brainstorm.SETTINGS.keybinds.autoReroll and love.keyboard.isDown("lctrl") then
		Brainstorm.AUTOREROLL.autoRerollActive = not Brainstorm.AUTOREROLL.autoRerollActive
	end

	if self.text_input_hook then
		if key == "escape" then
			self.text_input_hook = nil
		elseif key == "capslock" then
			self.capslock = not self.capslock
		else
			G.FUNCS.text_input_key({
				e = self.text_input_hook,
				key = key,
				caps = self.held_keys["lshift"] or self.held_keys["rshift"],
			})
		end
		return
	end

	if key == "escape" then
		if G.STATE == G.STATES.SPLASH then
			G:delete_run()
			G:main_menu()
		else
			if not G.OVERLAY_MENU then
				G.FUNCS:options()
			elseif not G.OVERLAY_MENU.config.no_esc then
				G.FUNCS:exit_overlay_menu()
			end
		end
	end

	if (self.locked and not G.SETTINGS.paused) or self.locks.frame or self.frame_buttonpress then
		return
	end
	self.frame_buttonpress = true
	self.held_key_times[key] = 0

	if not _RELEASE_MODE then
		if key == "tab" and not G.debug_tools then
			G.debug_tools = UIBox({
				definition = create_UIBox_debug_tools(),
				config = { align = "cr", offset = { x = G.ROOM.T.x + 11, y = 0 }, major = G.ROOM_ATTACH, bond = "Weak" },
			})
			G.E_MANAGER:add_event(Event({
				blockable = false,
				func = function()
					G.debug_tools.alignment.offset.x = -4
					return true
				end,
			}))
		end
		if self.hovering.target and self.hovering.target:is(Card) then
			local _card = self.hovering.target
			if G.OVERLAY_MENU then
				if key == "1" then
					unlock_card(_card.config.center)
					_card:set_sprites(_card.config.center)
				end
				if key == "2" then
					unlock_card(_card.config.center)
					discover_card(_card.config.center)
					_card:set_sprites(_card.config.center)
				end
				if key == "3" then
					if _card.ability.set == "Joker" and G.jokers and #G.jokers.cards < G.jokers.config.card_limit then
						add_joker(_card.config.center.key)
						_card:set_sprites(_card.config.center)
					end
					if
						_card.ability.consumeable
						and G.consumeables
						and #G.consumeables.cards < G.consumeables.config.card_limit
					then
						add_joker(_card.config.center.key)
						_card:set_sprites(_card.config.center)
					end
				end
			end
			if key == "q" then
				if _card.ability.set == "Joker" or _card.playing_card or _card.area then
					local _edition = {
						foil = not _card.edition,
						holo = _card.edition and _card.edition.foil,
						polychrome = _card.edition and _card.edition.holo,
						negative = _card.edition and _card.edition.polychrome,
					}
					_card:set_edition(_edition, true, true)
				end
			end
		end
		if key == "h" then
			G.debug_UI_toggle = not G.debug_UI_toggle
		end
		if key == "b" then
			G:delete_run()
			G:start_run({})
		end
		if key == "l" then
			G:delete_run()
			G.SAVED_GAME = get_compressed(G.SETTINGS.profile .. "/" .. "save.jkr")
			if G.SAVED_GAME ~= nil then
				G.SAVED_GAME = STR_UNPACK(G.SAVED_GAME)
			end
			G:start_run({ savetext = G.SAVED_GAME })
		end
		if key == "j" then
			G.debug_splash_size_toggle = not G.debug_splash_size_toggle
			G:delete_run()
			G:main_menu("splash")
		end
		if key == "8" then
			love.mouse.setVisible(not love.mouse.isVisible())
		end
		if key == "9" then
			G.debug_tooltip_toggle = not G.debug_tooltip_toggle
		end
		if key == "space" then
			live_test()
		end
		if key == "v" then
			if not G.prof then
				G.prof = require("engine/profile")
				G.prof.start()
			else
				G.prof:stop()
				print(G.prof.report())
				G.prof = nil
			end
		end
		if key == "p" then
			G.SETTINGS.perf_mode = not G.SETTINGS.perf_mode
		end
	end
end
