-- AirConditionerChip.lua - Lua chip in the wall Air Conditioner’s logic slot
--
-- Build: Air Conditioner (DeviceInputOutputCircuit). Power it, connect all three
-- pipe sides (input gas, conditioned output, waste/exchange), open the panel,
-- insert a StationeersLua chip with this script. The chip shares the unit’s
-- data network (use the front d0/d1 device buttons like other pipe machines).
--
-- Game source (Stationeers):
--   AirConditioner : DeviceInputOutputCircuit - heat pump; GoalTemperature is
--     OutputSetting in Kelvin (see OnRegistered default 293.15 K ≈ 20 °C).
--   Mode: 0 = Idle (stopped), 1 = Active (running) - same as the in-world
--     Start/Stop control (DeviceInputOutputCircuit mode strings Idle / Active).
--   OnAtmosphericTick only moves moles when Mode==1, powered, on, fully
--     connected, and |GoalTemperature − input gas temp| ≥ 1 K.
--   Extra logic reads on this prefab: OperationalTemperatureEfficiency,
--     TemperatureDifferentialEfficiency, PressureEfficiency (0..1 scalars).
--
-- SELF (ic.const.BASE_UNIT_INDEX) is the air conditioner. Same readable /
-- writable LogicTypes as other pipe circuit machines (see FiltrationChip.lua):
--   Read:  Setting (goal K), TemperatureInput / Output / Output2, pressures,
--          Power, On, Mode, Error, … plus the three *Efficiency types above.
--   Write: Setting (Kelvin), Mode, On, Open, Activate, Lock, Color
--
-- Celsius helpers (UI shows °C relative to absolute zero):
local function k_to_c(k)
    if not k then return nil end
    return k - 273.15
end

local function c_to_k(c)
    return c + 273.15
end

local LT   = ic.enums.LogicType
local read = ic.read
local write = ic.write
local SELF = ic.const.BASE_UNIT_INDEX

-- Periodic logging (seconds)
local LOG_INTERVAL = 12
local log_elapsed  = 0

--[[
  Optional auto cycle (off by default): sets a Kelvin setpoint and toggles
  Mode so the unit runs only when the inlet gas is more than 1 K away from
  the target (same threshold the game uses before processing moles).
  Set true to enable; adjust TARGET_C.
--]]
local AUTO_THERMOSTAT = false
local TARGET_C        = 21.0

print("[AirCon] Lua chip loaded - SELF = air conditioner")

function tick(dt)
    log_elapsed = log_elapsed + dt

    if AUTO_THERMOSTAT then
        local target_k = c_to_k(TARGET_C)
        local tin = read(SELF, LT.TemperatureInput)
        if tin and tin > 0 then
            write(SELF, LT.Setting, target_k)
            if math.abs(tin - target_k) >= 1.0 then
                write(SELF, LT.Mode, 1)
            else
                write(SELF, LT.Mode, 0)
            end
        end
    end

    if log_elapsed < LOG_INTERVAL then
        return
    end
    log_elapsed = 0

    local on   = read(SELF, LT.On)
    local mode = read(SELF, LT.Mode)
    local setk = read(SELF, LT.Setting)
    local tin  = read(SELF, LT.TemperatureInput)
    local tout = read(SELF, LT.TemperatureOutput)
    local tw   = read(SELF, LT.TemperatureOutput2)

    local opT = read(SELF, LT.OperationalTemperatureEfficiency)
    local dT  = read(SELF, LT.TemperatureDifferentialEfficiency)
    local pr  = read(SELF, LT.PressureEfficiency)

    print(string.format(
        "[AirCon] On=%s  Mode=%s (0=Idle 1=Active)  Goal=%.1f °C (%.1f K)",
        tostring(on), tostring(mode), k_to_c(setk) or 0, setk or 0
    ))
    print(string.format(
        "[AirCon] Tin=%.1f K  Tout=%.1f K  Twaste=%.1f K",
        tin or 0, tout or 0, tw or 0
    ))
    if opT or dT or pr then
        print(string.format(
            "[AirCon] Eff: opTemp=%.0f%%  deltaT=%.0f%%  pressure=%.0f%%",
            (opT or 0) * 100, (dT or 0) * 100, (pr or 0) * 100
        ))
    end
end
