#!/usr/bin/env lua

-- Minimal Lua smoke test: ensure configs parse and UI loads syntactically.

local function ok(status, label, detail)
  if status then
    print("✓ " .. label)
  else
    print("✗ " .. label .. (detail and (": " .. detail) or ""))
  end
end

-- Config parse
local config_status, cfg = pcall(dofile, "config.lua")
ok(config_status, "config.lua loads")
if config_status and type(cfg) ~= "table" then
  ok(false, "config.lua returns table", "got " .. type(cfg))
end

-- Brainstorm/UI syntax (no runtime side effects)
local function syntax_check(path)
  local fh, err = io.open(path, "r")
  if not fh then
    return false, "open failed: " .. tostring(err)
  end
  local content = fh:read("*all")
  fh:close()
  local fn, load_err = loadstring(content)
  if not fn then
    return false, "parse failed: " .. tostring(load_err)
  end
  return true
end

local lua_files = { "Core/Brainstorm.lua", "UI/ui.lua" }
for _, path in ipairs(lua_files) do
  local ok_syntax, err = syntax_check(path)
  ok(ok_syntax, path .. " syntax", err)
end
