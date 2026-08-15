-- ClockLogger.lua - Log the in-game clock every minute
-- Prints the current time to the Lua Debugger Logs tab once per minute.
-- Demonstrates util.clock_time(), util.game_time(), and util.days_past().

local acc = 0

print("[ClockLogger] Started - logging every 60s")
print("[ClockLogger] Day " .. util.days_past() .. " | " .. util.clock_time("hh:MM:ss A"))

function tick(dt)
    acc = acc + (dt or 0)
    if acc < 60.0 then return end
    acc = 0

    local clock = util.clock_time("hh:MM:ss A")
    local day   = util.days_past()
    local gt    = string.format("%.0f", util.game_time())

    print(string.format("[ClockLogger] Day %d | %s | elapsed %ss", day, clock, gt))
end
