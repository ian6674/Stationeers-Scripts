--@module pid
-- LibraryModule_PID.lua
-- A PID (Proportional-Integral-Derivative) controller library for feedback loops.
-- Other Lua chips on the same data network load this via: local pid = require("pid")
--
-- HOW TO USE:
--   1. Put this script on a Lua chip and insert it into an IC Housing.
--   2. The housing must be powered and on the same data cable network as consumer chips.
--   3. The chip has NO Lua VM of its own - it is a passive source code store.
--   4. Any chip on the same network can call: local pid = require("pid")
--
-- COMMON APPLICATIONS IN STATIONEERS:
--   - Room pressure regulation (wall cooler / heater valves)
--   - Temperature control (furnaces, greenhouses, habitats)
--   - Gas mixing (target ratio maintenance)
--   - Solar tracker fine-tuning
--   - Rocket thrust control

local pid = {}

--- Create a new PID controller instance.
-- @param kp  Proportional gain (how aggressively to correct current error)
-- @param ki  Integral gain (how aggressively to correct accumulated error)
-- @param kd  Derivative gain (how aggressively to dampen rate of change)
-- @param out_min  Minimum output value (default -100)
-- @param out_max  Maximum output value (default 100)
-- @return PID controller table with :update(setpoint, measured, dt) method
function pid.new(kp, ki, kd, out_min, out_max)
    local ctrl = {
        kp       = kp or 1.0,
        ki       = ki or 0.0,
        kd       = kd or 0.0,
        out_min  = out_min or -100,
        out_max  = out_max or 100,
        integral = 0,
        prev_err = 0,
        output   = 0,
        first    = true, -- skip derivative on first call (no prev_err yet)
    }

    --- Update the controller with a new measurement.
    -- Call this once per tick inside tick(dt).
    -- @param setpoint  Desired target value
    -- @param measured  Current measured value
    -- @param dt        Delta time in seconds (from tick(dt) argument)
    -- @return output   Control signal clamped to [out_min, out_max]
    function ctrl:update(setpoint, measured, dt)
        if dt <= 0 then return self.output end

        local err = setpoint - measured

        -- Proportional term
        local p = self.kp * err

        -- Integral term with anti-windup clamping
        self.integral = self.integral + err * dt
        local i = self.ki * self.integral

        -- Clamp integral to prevent windup
        local i_max = self.out_max * 0.8
        if i > i_max then
            self.integral = i_max / self.ki
            i = i_max
        elseif i < -i_max then
            self.integral = -i_max / self.ki
            i = -i_max
        end

        -- Derivative term (skip on first call to avoid spike)
        local d = 0
        if not self.first then
            d = self.kd * (err - self.prev_err) / dt
        end
        self.first = false
        self.prev_err = err

        -- Sum and clamp
        local raw = p + i + d
        if raw > self.out_max then raw = self.out_max end
        if raw < self.out_min then raw = self.out_min end

        self.output = raw
        return raw
    end

    --- Reset controller state (integral accumulator and derivative history).
    -- Useful when switching setpoints or modes.
    function ctrl:reset()
        self.integral = 0
        self.prev_err = 0
        self.output   = 0
        self.first    = true
    end

    --- Update gains without resetting state.
    function ctrl:tune(kp, ki, kd)
        self.kp = kp or self.kp
        self.ki = ki or self.ki
        self.kd = kd or self.kd
    end

    return ctrl
end

--- Convenience: create a controller pre-tuned for Stationeers pressure regulation.
-- Output range 0-100 (valve percentage). Tuned for ~101 kPa setpoint.
function pid.pressure(setpoint_kpa)
    local ctrl = pid.new(2.0, 0.3, 0.5, 0, 100)
    ctrl.setpoint = setpoint_kpa or 101.325
    return ctrl
end

--- Convenience: create a controller pre-tuned for Stationeers temperature regulation.
-- Output range -100 to 100 (negative = cooling, positive = heating).
function pid.temperature(setpoint_k)
    local ctrl = pid.new(1.5, 0.1, 1.0, -100, 100)
    ctrl.setpoint = setpoint_k or 293.15 -- 20 C
    return ctrl
end

--- Clamp a value to [lo, hi].
function pid.clamp(value, lo, hi)
    if value < lo then return lo end
    if value > hi then return hi end
    return value
end

--- Map a value from one range to another.
function pid.map(value, in_min, in_max, out_min, out_max)
    if in_max == in_min then return out_min end
    local t = (value - in_min) / (in_max - in_min)
    return out_min + t * (out_max - out_min)
end

return pid
