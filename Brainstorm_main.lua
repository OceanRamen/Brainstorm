local lovely = require("lovely")
local nativefs = require("nativefs")
Brainstorm.INITIALIZED = true
Brainstorm.VER = "Brainstorm v1.1.0-alpha"

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

-- HELPER FUNCTIONS
Brainstorm.FUNCS = {}
function Brainstorm.FUNCS.inspectDepth(table, indent, depth)
	if depth and depth > 5 then -- Limit the depth to avoid deep nesting
		return "Depth limit reached"
	end

	if type(table) ~= "table" then -- Ensure the object is a table
		return "Not a table"
	end

	local str = ""
	if not indent then
		indent = 0
	end

	for k, v in pairs(table) do
		local formatting = string.rep("  ", indent) .. tostring(k) .. ": "
		if type(v) == "table" then
			str = str .. formatting .. "\n"
			str = str .. inspectDepth(v, indent + 1, (depth or 0) + 1)
		elseif type(v) == "function" then
			str = str .. formatting .. "function\n"
		elseif type(v) == "boolean" then
			str = str .. formatting .. tostring(v) .. "\n"
		else
			str = str .. formatting .. tostring(v) .. "\n"
		end
	end

	return str
end

function Brainstorm.FUNCS.inspect(table)
	if type(table) ~= "table" then
		return "Not a table"
	end

	local str = ""
	for k, v in pairs(table) do
		local valueStr = type(v) == "table" and "table" or tostring(v)
		str = str .. tostring(k) .. ": " .. valueStr .. "\n"
	end

	return str
end
