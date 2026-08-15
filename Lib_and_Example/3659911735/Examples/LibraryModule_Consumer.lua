-- LibraryChip_Consumer.lua
-- Demonstrates using require() to load the "atmos" library module from a library chip
-- on the same data cable network.
--
-- SETUP:
--   1. Put LibraryChip_Server.lua (the atmos module) on a Lua chip in an IC Housing.
--   2. Put this script on a DIFFERENT Lua chip, also on the same data cable network.
--   3. Both housings must be powered.
--
-- When this script calls require("atmos"), StationeersLua searches the data network
-- for a chip with --@module atmos, compiles its source inside THIS chip's VM, and
-- caches the result. Subsequent require("atmos") calls return the cached module.

local LT = ic.enums.LogicType

-- Load the atmos library from a library chip on the same data network.
-- This compiles and executes the library source inside this chip's VM.
local atmos = require("atmos")

print("Loaded atmos module!")
print("  Ideal pressure: " .. atmos.IDEAL_PRESSURE_KPA .. " kPa")
print("  Safe temp range: " .. atmos.k_to_c(atmos.MIN_TEMP_K) .. " to " ..
    atmos.k_to_c(atmos.MAX_TEMP_K) .. " C")

-- Example: Monitor atmosphere on a sensor wired to d0
-- Wire d0 to a Gas Sensor.
-- tick(dt) runs every game tick; use a time accumulator to throttle reads.

local INTERVAL = 5   -- seconds between sensor reads
local elapsed  = 999 -- start high so first tick reads immediately

function tick(dt)
    elapsed = elapsed + dt
    if elapsed < INTERVAL then return end
    elapsed            = 0
    -- Read sensor values from d0
    local pressure     = ic.read(0, LT.Pressure) or 0    -- kPa
    local temp_k       = ic.read(0, LT.Temperature) or 0 -- Kelvin
    local co2_pct      = ic.read(0, LT.RatioCarbonDioxide) or 0

    -- Use the atmos library to check breathability
    local safe, reason = atmos.is_breathable(pressure, temp_k, co2_pct * 100)

    -- Display results
    local temp_c       = atmos.k_to_c(temp_k)
    print(string.format("%.1f kPa  %.1f C  CO2=%.1f%%  %s",
        pressure, temp_c, co2_pct * 100, safe and "SAFE" or reason))
end
