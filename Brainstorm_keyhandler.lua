local lovely = require("lovely")
local nativefs = require("nativefs")

Brainstorm.AUTOREROLL = {}

local saveKeys = { "1", "2", "3", "4", "5" }

function Brainstorm.key_press_update(key)
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
end
