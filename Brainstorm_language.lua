local lovely = require("lovely")
local nativefs = require("nativefs")

function Brainstorm.BU()
    return nativefs.read(lovely.mod_dir .. "/Brainstorm/Language/BU.lua")
end

