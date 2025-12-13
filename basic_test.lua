#!/usr/bin/env lua

print("=== Brainstorm Basic Tests ===")

-- Test 1: Check files with io library
print("\n1. File checks:")
local files = {
  "Core/Brainstorm.lua",
  "Core/logger.lua",
  "UI/ui.lua",
  "config.lua",
  "Immolate.dll",
}

for _, file in ipairs(files) do
  local f = io.open(file, "r")
  if f then
    f:close()
    print("  ✓ " .. file)
  else
    print("  ✗ " .. file .. " not found")
  end
end

-- Test 2: Check DLL size
print("\n2. DLL check:")
local dll = io.open("Immolate.dll", "rb")
if dll then
  local size = dll:seek("end")
  dll:close()
  local size_mb = size / (1024 * 1024)
  print(string.format("  ✓ DLL size: %.2f MB", size_mb))
  if size_mb > 2.4 then
    print("  ✓ GPU-enabled DLL detected")
  else
    print("  ℹ CPU-only DLL detected")
  end
else
  print("  ✗ DLL not found")
end

-- Test 3: Check config syntax
print("\n3. Config syntax:")
local config_file = io.open("config.lua", "r")
if config_file then
  local content = config_file:read("*all")
  config_file:close()

  -- Try to load it
  local func, err = loadstring(content)
  if func then
    print("  ✓ Config syntax valid")
    -- Check for key settings
    if content:find("use_gpu_experimental") then
      print("  ✓ GPU settings present")
    end
    if content:find("debug_enabled") then
      print("  ✓ Debug settings present")
    end
  else
    print("  ✗ Config syntax error: " .. tostring(err))
  end
else
  print("  ✗ Config not found")
end

-- Test 4: Check logger module syntax
print("\n4. Logger module:")
local logger_file = io.open("Core/logger.lua", "r")
if logger_file then
  local content = logger_file:read("*all")
  logger_file:close()

  -- Remove ffi dependency for syntax check
  content = content:gsub("require%s*%(%s*[\"']ffi[\"']%s*%)", "nil")

  local func, err = loadstring(content)
  if func then
    print("  ✓ Logger syntax valid")
    if content:find("for_module") then
      print("  ✓ for_module function present")
    end
  else
    print("  ✗ Logger syntax error: " .. tostring(err))
  end
else
  print("  ✗ Logger not found")
end

print("\n=== Tests Complete ===")
print("\nNote: Full integration tests require LuaJIT (used by Balatro)")
print("These basic tests verify file integrity and syntax only.")
