local lovely = require("lovely")
local nativefs = require("nativefs")
Brainstorm.INITIALIZED = true
Brainstorm.VER = "Brainstorm v1.0.0-alpha"

function Brainstorm.update(dt)
	if Brainstorm.AUTOREROLL.autoRerollActive then
		Brainstorm.AUTOREROLL.rerollTimer = Brainstorm.AUTOREROLL.rerollTimer + dt
		if Brainstorm.AUTOREROLL.rerollTimer >= Brainstorm.AUTOREROLL.rerollInterval then
			Brainstorm.AUTOREROLL.rerollTimer = Brainstorm.AUTOREROLL.rerollTimer - Brainstorm.AUTOREROLL.rerollInterval
			seed_found = Brainstorm.auto_reroll()
			if seed_found then
				Brainstorm.AUTOREROLL.autoRerollActive = false
			end
		end
	end
end
