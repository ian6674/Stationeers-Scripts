-- SimpleTest.lua - Blink a light on d0
-- Connect a light (or any device with On/Off) to d0 on the housing
-- print() output appears in the Lua Debugger Logs tab.

local LT = ic.enums.LogicType
local state = 0
local acc = 0
local logTimer = 0

print("[SimpleTest] Logging to the Lua Debugger Logs tab")

function tick(dt)
    acc = acc + (dt or 0)
    logTimer = logTimer + (dt or 0)
    if logTimer >= 5.0 then
        logTimer = 0
        print(string.format("[SimpleTest] state=%d", state))
    end
    if acc < 1.0 then
        return
    end
    acc = 0

    state = 1 - state

    -- d0 = device index 0
    -- LogicType.On = 28 (use enum table to avoid hardcoding)
    ic.write(0, LT.On, state)
end
