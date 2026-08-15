--@module atmos
-- LibraryModule_Atmos.lua
-- A library chip providing reusable atmosphere helper functions.
-- Other Lua chips on the same data network load this via: local atmos = require("atmos")
--
-- HOW TO USE:
--   1. Put this script on a Lua chip and insert it into an IC Housing.
--   2. The housing must be powered and on the same data cable network as consumer chips.
--   3. The chip has NO Lua VM of its own - it is a passive source code store.
--   4. Any chip on the same network can call: local atmos = require("atmos")
--
-- The --@module annotation above tells StationeersLua this is a library chip.
-- When require("atmos") is called, this source is compiled and executed inside the
-- requesting chip's VM. The return value becomes the module.

local atmos              = {}

-- Stationeers atmosphere constants (verified against game source)
atmos.IDEAL_PRESSURE_KPA = 101.325 -- Chemistry.ONE_ATMOSPHERE
atmos.MIN_PRESSURE_KPA   = 20      -- approximate safe total pressure
atmos.MAX_PRESSURE_KPA   = 607.95  -- 6 atm danger threshold
atmos.MIN_TEMP_K         = 263.15  -- Lungs.TemperatureMin: ZeroDegrees - 10 (-10 C)
atmos.MAX_TEMP_K         = 323.15  -- Lungs.TemperatureMax: ZeroDegrees + 50 (50 C)
atmos.MIN_O2_PARTIAL_KPA = 16.0    -- Chemistry.MinimumOxygenPartialPressure
atmos.MAX_CO2_PERCENT    = 2.0     -- CO2 toxicity threshold (%)
atmos.IDEAL_O2_PERCENT   = 21.0    -- Earth-normal O2

--- Clamp a value between min and max.
function atmos.clamp(value, lo, hi)
    if value < lo then return lo end
    if value > hi then return hi end
    return value
end

--- Linear interpolation between a and b by factor t (0..1).
function atmos.lerp(a, b, t)
    return a + (b - a) * atmos.clamp(t, 0, 1)
end

--- Check if atmosphere is breathable.
-- @param pressure_kpa  Total pressure in kPa
-- @param temp_k        Temperature in Kelvin
-- @param co2_percent   CO2 molar percentage
-- @param o2_percent    O2 molar percentage (optional, default 21)
-- @return is_safe, reason_string
function atmos.is_breathable(pressure_kpa, temp_k, co2_percent, o2_percent)
    o2_percent = o2_percent or atmos.IDEAL_O2_PERCENT

    if pressure_kpa < atmos.MIN_PRESSURE_KPA then
        return false, "pressure too low"
    end
    if pressure_kpa > atmos.MAX_PRESSURE_KPA then
        return false, "pressure too high"
    end
    if temp_k < atmos.MIN_TEMP_K then
        return false, "too cold"
    end
    if temp_k > atmos.MAX_TEMP_K then
        return false, "too hot"
    end
    if co2_percent > atmos.MAX_CO2_PERCENT then
        return false, "CO2 toxicity"
    end
    if o2_percent < 16 then
        return false, "O2 too low"
    end
    return true, "safe"
end

--- Compute molar fraction from partial pressure and total pressure.
function atmos.molar_fraction(partial_kpa, total_kpa)
    if total_kpa <= 0 then return 0 end
    return partial_kpa / total_kpa
end

--- Convert Kelvin to Celsius.
function atmos.k_to_c(kelvin)
    return kelvin - 273.15
end

--- Convert Celsius to Kelvin.
function atmos.c_to_k(celsius)
    return celsius + 273.15
end

return atmos
