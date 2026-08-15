-- NetRpc.lua
-- Demonstrates RPC (Remote Procedure Call) between Lua chips on the same data network.
--
-- CHIP A (Server): Registers RPC methods that other chips can call.
-- CHIP B (Client): Calls RPC methods on the server chip.
--
-- Both scripts can run on separate Lua chips connected to the same data network.

-- ============================================================================
-- CHIP A: RPC Server
-- ============================================================================
-- Uncomment this block on the server chip and comment out CHIP B below.
--[[
local LT = ic.enums.LogicType

-- Register an RPC method that returns sensor data
ic.net.register("get_status", function(payload, fromId, fromName)
    print("RPC get_status called by " .. fromName)

    local temp = read(0, LT.Temperature)
    local pressure = read(0, LT.Pressure)

    -- The return value is sent back as the response payload
    return {
        temp = temp,
        pressure = pressure,
        uptime = os.clock()
    }
end)

-- Register an RPC method that accepts parameters
ic.net.register("set_threshold", function(payload, fromId, fromName)
    if type(payload) ~= "table" or not payload.value then
        error("expected payload with 'value' field")
    end

    print("Threshold set to " .. payload.value .. " by " .. fromName)
    mem_write(0, payload.value)

    return { ok = true }
end)

print("RPC server ready. Methods: get_status, set_threshold")

-- Keep the chip alive to process incoming RPC requests
while true do
    ic.yield()
end
--]]

-- ============================================================================
-- CHIP B: RPC Client
-- ============================================================================
-- This chip calls RPC methods on a target chip (by name or ID).

local target = "Server" -- Change to your server chip's name or ID

-- Call the get_status RPC method
local reqId = ic.net.request(target, "get_status", nil,
    function(ok, payload, err, fromId, fromName)
        if ok then
            print("Status from " .. fromName .. ":")
            print("  Temp: " .. tostring(payload.temp))
            print("  Pressure: " .. tostring(payload.pressure))
            print("  Uptime: " .. tostring(payload.uptime))
        else
            print("RPC failed: " .. tostring(err))
        end
    end,
    5 -- 5 second timeout
)

print("Sent RPC request: " .. reqId)

-- Wait a bit, then call set_threshold
sleep(3)

ic.net.request(target, "set_threshold", { value = 42 },
    function(ok, payload, err)
        if ok then
            print("Threshold set successfully")
        else
            print("set_threshold failed: " .. tostring(err))
        end
    end
)

-- Keep alive to receive the callbacks
while true do
    ic.yield()
end
