-- FiltrationChip.lua - Lua chip running inside a filtration machine
-- Insert a Lua chip into the chip slot of a Filtration Machine or any
-- DeviceInputOutputCircuit (pipe devices with chip slots).
--
-- The chip runs while the machine is powered and switched on.
-- It has access to the same data cable network as the machine.
--
-- READABLE LogicTypes on the machine itself (SELF):
--   Setting, Maximum, Ratio
--   PressureInput, TemperatureInput, TotalMolesInput, CombustionInput
--   PressureOutput, TemperatureOutput, TotalMolesOutput, CombustionOutput
--   PressureInput2, TemperatureInput2, etc. (second pipe port if present)
--   PressureOutput2, TemperatureOutput2, etc.
--   RatioOxygenInput, RatioCarbonDioxideInput, RatioNitrogenInput, ...
--   RatioOxygenOutput, RatioCarbonDioxideOutput, ...
--   Power, On, Error, Activate, Lock, Color, PrefabHash, ReferenceId
--
-- WRITABLE LogicTypes:
--   Setting, On, Open, Mode, Activate, Lock, Color
--
-- NOTE: The gas filter type installed in the machine's filter slots is
-- accessed via SLOT logic (LogicSlotType.FilterType), not via ic.read().
-- Use ic.read_slot(SELF, slotIndex, ic.enums.LogicSlotType.FilterType)
-- to read which gas a given filter slot is filtering.

local LT   = ic.enums.LogicType
local read  = ic.read

local SELF = ic.const.BASE_UNIT_INDEX

local LOG_INTERVAL = 15
local log_elapsed  = 0

print("[Filtration] Chip active in filtration unit")

function tick(dt)
    log_elapsed = log_elapsed + dt
    if log_elapsed < LOG_INTERVAL then return end
    log_elapsed = 0

    local inputP  = read(SELF, LT.PressureInput) or 0
    local inputT  = read(SELF, LT.TemperatureInput) or 0
    local outputP = read(SELF, LT.PressureOutput) or 0
    local setting = read(SELF, LT.Setting) or 0
    local powered = read(SELF, LT.On) or 0

    print(string.format(
        "[Filtration] In=%.1f kPa / %.0f K  Out=%.1f kPa  Setting=%.0f  On=%d",
        inputP, inputT, outputP, setting, powered
    ))

    -- Example: read input gas ratios
    local o2in  = read(SELF, LT.RatioOxygenInput) or 0
    local co2in = read(SELF, LT.RatioCarbonDioxideInput) or 0
    print(string.format("[Filtration] Input O2=%.1f%%  CO2=%.1f%%", o2in * 100, co2in * 100))
end
