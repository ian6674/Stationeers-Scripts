-- SuitChip.lua - Lua chip running inside an EVA suit
-- Insert a Lua chip into the chip slot of any suit (HardSuit, SpaceSuit, etc.).
-- The chip runs while the suit has battery power and the player is wearing it.
--
-- If a Wireless Development Board is installed in the suit and connected to
-- an omni transmitter network, the chip can also read/write network devices.
--
-- DEVICE SLOT INDICES (via ic.read / ic.write on SELF):
--   Slot 0 = Helmet        Slot 3 = Glasses
--   Slot 1 = Backpack      Slot 4 = Left hand item
--   Slot 2 = Toolbelt      Slot 5 = Right hand item
--   dSelf (ic.const.BASE_UNIT_INDEX) = The suit itself
--
-- READABLE LogicTypes on the suit itself (SELF):
--   PressureExternal, TemperatureExternal  - world atmosphere around the suit
--   Pressure, Temperature, TotalMoles      - internal suit atmosphere
--   RatioOxygen, RatioCarbonDioxide, etc.  - internal gas ratios
--   Setting, PressureSetting, TemperatureSetting
--   Filtration, AirRelease
--   PositionX/Y/Z, VelocityMagnitude, VelocityX/Y/Z
--   VelocityRelativeX/Y/Z, ForwardX/Y/Z, Orientation
--   EntityState, SoundAlert, On
--
-- WRITABLE LogicTypes:
--   Setting, PressureSetting, TemperatureSetting
--   Filtration, AirRelease, SoundAlert, On, Error

local LT   = ic.enums.LogicType
local read  = ic.read

local SELF = ic.const.BASE_UNIT_INDEX
local LOG_INTERVAL = 10
local log_elapsed  = 0

print("[SuitChip] Running inside EVA suit")

function tick(dt)
    log_elapsed = log_elapsed + dt
    if log_elapsed < LOG_INTERVAL then return end
    log_elapsed = 0

    local extPressure = read(SELF, LT.PressureExternal) or 0
    local extTemp     = read(SELF, LT.TemperatureExternal) or 0
    local intPressure = read(SELF, LT.Pressure) or 0
    local o2Ratio     = read(SELF, LT.RatioOxygen) or 0

    print(string.format(
        "[SuitChip] ExtP=%.1f kPa  ExtT=%.0f K  IntP=%.1f kPa  O2=%.0f%%",
        extPressure, extTemp, intPressure, o2Ratio * 100
    ))

    -- Example: read player position
    local px = read(SELF, LT.PositionX) or 0
    local py = read(SELF, LT.PositionY) or 0
    local pz = read(SELF, LT.PositionZ) or 0
    print(string.format("[SuitChip] Pos=(%.1f, %.1f, %.1f)", px, py, pz))
end
