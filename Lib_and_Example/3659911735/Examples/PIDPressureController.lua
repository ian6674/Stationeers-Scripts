-- PIDPressureController.lua
-- Demonstrates using the PID library module to regulate room pressure.
-- Requires the "pid" library chip on the same data cable network.
--
-- DEVICE WIRING:
--   d0 = Gas Sensor (reads room pressure)
--   d1 = Active Vent or Volume Pump (output: 0-100% setting)
--
-- The PID controller reads pressure from d0, compares it to the setpoint,
-- and writes a valve setting (0-100) to d1 to maintain target pressure.

local LT  = ic.enums.LogicType
local pid = require("pid")

-- Create a pressure-tuned PID controller targeting 101.325 kPa (1 atm)
local ctrl = pid.pressure(101.325)

-- Accumulator for throttled logging
local log_elapsed = 0
local LOG_INTERVAL = 5

print("PID Pressure Controller active")
print("  Target: " .. ctrl.setpoint .. " kPa")
print("  Gains:  Kp=" .. ctrl.kp .. " Ki=" .. ctrl.ki .. " Kd=" .. ctrl.kd)

function tick(dt)
    -- Read current pressure from gas sensor on d0
    local pressure = ic.read(0, LT.Pressure) or 0

    -- Update PID controller - returns valve setting 0..100
    local output = ctrl:update(ctrl.setpoint, pressure, dt)

    -- Write valve setting to active vent on d1
    ic.write(1, LT.Setting, output)

    -- Periodic status logging
    log_elapsed = log_elapsed + dt
    if log_elapsed >= LOG_INTERVAL then
        log_elapsed = 0
        local err = ctrl.setpoint - pressure
        print(string.format("P=%.1f kPa  Err=%.2f  Out=%.1f%%", pressure, err, output))
    end
end
