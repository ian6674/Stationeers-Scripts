--@module power
-- LibraryModule_Power.lua
-- Power grid monitoring and calculation helpers for Stationeers.
-- Other Lua chips on the same data network load this via: local power = require("power")
--
-- HOW TO USE:
--   1. Put this script on a Lua chip and insert it into an IC Housing.
--   2. The housing must be powered and on the same data cable network as consumer chips.
--   3. Any chip on the same network can call: local power = require("power")
--
-- FEATURES:
--   - Prefab hashes for common power devices (batteries, generators, solar panels)
--   - Battery state helpers (charge %, time remaining, health)
--   - Solar panel angle and efficiency calculations
--   - Power budget estimation (generation vs consumption)
--   - Formatting helpers for Watts and Joules

local power = {}

-- ── Prefab Hashes ──────────────────────────────────────────────────────────────
-- Prefab hashes are computed from prefab name strings at runtime.
-- Use ic.hash("prefabName") in-game to get exact values. Examples:
--   local bat_hash   = ic.hash("ItemBatteryCellLarge")
--   local solar_hash = ic.hash("ItemSolarPanel")
--   local charge     = ic.batch_read(bat_hash, LT.Charge, "Average")

-- ── LogicType Shortcuts ────────────────────────────────────────────────────────
-- Common LogicType fields for power devices. Use with ic.read() or ic.batch_read().
power.LT = {
    CHARGE     = "Charge",          -- Battery charge ratio (0..1)
    CHARGE_MAX = "Maximum",         -- Battery max capacity (J)
    POWER_GEN  = "PowerGeneration", -- Current generation (W)
    POWER_USE  = "PowerRequired",   -- Current consumption (W)
    RATIO      = "Ratio",           -- Solar output ratio (0..1)
    ON         = "On",              -- Device power state
    SETTING    = "Setting",         -- Device setting value
    HORIZONTAL = "Horizontal",      -- Solar horizontal angle
    VERTICAL   = "Vertical",        -- Solar vertical angle
}

-- ── Battery Helpers ────────────────────────────────────────────────────────────

--- Calculate battery charge percentage from charge ratio.
-- @param charge_ratio  Charge value from LogicType.Charge (0..1)
-- @return percentage 0..100
function power.charge_pct(charge_ratio)
    if charge_ratio == nil then return 0 end
    return math.min(100, math.max(0, charge_ratio * 100))
end

--- Estimate time remaining on battery at current drain rate.
-- @param charge_j       Current charge in Joules (Charge * Maximum)
-- @param drain_w        Current power drain in Watts
-- @return seconds remaining, or math.huge if drain is zero
function power.time_remaining(charge_j, drain_w)
    if drain_w == nil or drain_w <= 0 then return math.huge end
    if charge_j == nil or charge_j <= 0 then return 0 end
    return charge_j / drain_w
end

--- Estimate time to full charge at current charge rate.
-- @param charge_j       Current charge in Joules
-- @param max_j          Maximum capacity in Joules
-- @param charge_rate_w  Current charge rate in Watts
-- @return seconds to full, or math.huge if not charging
function power.time_to_full(charge_j, max_j, charge_rate_w)
    if charge_rate_w == nil or charge_rate_w <= 0 then return math.huge end
    local remaining = (max_j or 0) - (charge_j or 0)
    if remaining <= 0 then return 0 end
    return remaining / charge_rate_w
end

--- Get a color code for battery charge level.
-- @param pct  Charge percentage (0..100)
-- @return hex color string
function power.charge_color(pct)
    if pct >= 60 then return "#22C55E" end -- Green
    if pct >= 30 then return "#EAB308" end -- Yellow
    if pct >= 10 then return "#F97316" end -- Orange
    return "#EF4444"                       -- Red
end

--- Get a status label for battery charge level.
-- @param pct  Charge percentage (0..100)
-- @return status string
function power.charge_status(pct)
    if pct >= 95 then return "FULL" end
    if pct >= 60 then return "OK" end
    if pct >= 30 then return "LOW" end
    if pct >= 10 then return "CRITICAL" end
    return "EMPTY"
end

-- ── Formatting Helpers ─────────────────────────────────────────────────────────

--- Format watts with appropriate SI prefix.
-- @param watts  Power value in Watts
-- @return formatted string like "1.5 kW" or "320 W"
function power.fmt_watts(watts)
    if watts == nil then return "N/A" end
    local abs = math.abs(watts)
    if abs >= 1e6 then
        return string.format("%.1f MW", watts / 1e6)
    elseif abs >= 1e3 then
        return string.format("%.1f kW", watts / 1e3)
    else
        return string.format("%.0f W", watts)
    end
end

--- Format joules with appropriate SI prefix.
-- @param joules  Energy value in Joules
-- @return formatted string like "25.3 kJ" or "1.2 MJ"
function power.fmt_joules(joules)
    if joules == nil then return "N/A" end
    local abs = math.abs(joules)
    if abs >= 1e6 then
        return string.format("%.1f MJ", joules / 1e6)
    elseif abs >= 1e3 then
        return string.format("%.1f kJ", joules / 1e3)
    else
        return string.format("%.0f J", joules)
    end
end

--- Format seconds as human-readable time.
-- @param seconds  Duration in seconds
-- @return formatted string like "2h 15m" or "45m 30s"
function power.fmt_time(seconds)
    if seconds == nil or seconds == math.huge then return "--" end
    if seconds <= 0 then return "0s" end

    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)

    if h > 0 then
        return string.format("%dh %dm", h, m)
    elseif m > 0 then
        return string.format("%dm %ds", m, s)
    else
        return string.format("%ds", s)
    end
end

-- ── Power Budget ───────────────────────────────────────────────────────────────

--- Create a power budget tracker.
-- Add generation and consumption values, then query the balance.
-- @return budget table with :add_gen(), :add_load(), :balance(), :summary()
function power.budget()
    local b = {
        generation  = 0,
        consumption = 0,
        sources     = {},
        loads       = {},
    }

    --- Add a generation source.
    function b:add_gen(label, watts)
        self.generation = self.generation + (watts or 0)
        if label then
            self.sources[#self.sources + 1] = { label = label, watts = watts or 0 }
        end
    end

    --- Add a consumption load.
    function b:add_load(label, watts)
        self.consumption = self.consumption + (watts or 0)
        if label then
            self.loads[#self.loads + 1] = { label = label, watts = watts or 0 }
        end
    end

    --- Get net power balance (positive = surplus, negative = deficit).
    function b:balance()
        return self.generation - self.consumption
    end

    --- Get a summary string.
    function b:summary()
        local bal = self:balance()
        local sign = bal >= 0 and "+" or ""
        return string.format("Gen: %s | Load: %s | Net: %s%s",
            power.fmt_watts(self.generation),
            power.fmt_watts(self.consumption),
            sign, power.fmt_watts(bal))
    end

    --- Reset all tracked values.
    function b:reset()
        self.generation  = 0
        self.consumption = 0
        self.sources     = {}
        self.loads       = {}
    end

    return b
end

-- ── Utility ────────────────────────────────────────────────────────────────────

--- Clamp a value.
function power.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

--- Linear interpolation.
function power.lerp(a, b, t)
    return a + (b - a) * power.clamp(t, 0, 1)
end

return power
