#!/usr/bin/env lua

-- CPU DLL smoke check: verifies presence and size thresholds.

local function ok(status, label, detail)
  if status then
    print("✓ " .. label)
  else
    print("✗ " .. label .. (detail and (": " .. detail) or ""))
  end
end

local dll_path = "Immolate.dll"
local f, err = io.open(dll_path, "rb")
if not f then
  ok(false, "CPU DLL present", err)
  os.exit(1)
end

local size = f:seek("end")
f:close()
ok(true, "CPU DLL present")
local size_mb = size / (1024 * 1024)
ok(size_mb > 1.5, "CPU DLL plausible size", string.format("%.2f MB", size_mb))
