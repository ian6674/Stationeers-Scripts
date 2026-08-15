-- CoroutineDemo.lua
-- Demonstrates user coroutines with independent sleep timers.
-- No devices needed - all output goes to the Lua Debugger log.

-- Three coroutines run concurrently inside a single chip, each
-- sleeping at its own rate. tick() also runs alongside them.

local function counter(name, interval)
    local i = 0
    while true do
        i = i + 1
        print(string.format("[%s] tick #%d (every %gs)", name, i, interval))
        sleep(interval)
    end
end

local function countdown(seconds)
    print("[Countdown] Starting from " .. seconds)
    for i = seconds, 1, -1 do
        print("[Countdown] " .. i .. "...")
        sleep(1)
    end
    print("[Countdown] Done! (coroutine finished naturally)")
end

-- Start three coroutines. Each runs to its first sleep(), then
-- the runtime auto-resumes them on schedule - no manual tracking.
coroutine.resume(coroutine.create(counter), "Fast", 2)
coroutine.resume(coroutine.create(counter), "Slow", 7)
coroutine.resume(coroutine.create(countdown), 10)

print("[Main] 3 coroutines launched")
print("[Main] Watch the debugger log - all three interleave freely")

-- tick() runs independently every game tick alongside the coroutines.
local elapsed = 0
function tick(dt)
    elapsed = elapsed + dt
    if elapsed >= 15 then
        elapsed = 0
        print("[tick] 15s summary - coroutines are still running above ^")
    end
end
