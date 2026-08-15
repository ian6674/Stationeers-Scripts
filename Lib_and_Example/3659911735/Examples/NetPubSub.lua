-- NetPubSub.lua
-- Demonstrates pub/sub messaging between Lua chips on the same data network.
--
-- CHIP A (Publisher): Reads a sensor and publishes temperature every 2 seconds.
-- CHIP B (Subscriber): Subscribes to temperature updates and prints them.
--
-- Both scripts can run on separate Lua chips connected to the same data network.

-- ============================================================================
-- CHIP A: Temperature Publisher
-- ============================================================================
-- Uncomment this block on the publishing chip and comment out CHIP B below.
--[[
local LT = ic.enums.LogicType

function tick(dt)
    -- Read temperature from device on d0
    local temp = read(0, LT.Temperature)

    -- Publish to all subscribers on "sensors/temp" topic
    local delivered = ic.net.publish("sensors/temp", {
        temp = temp,
        time = os.clock()
    }, {
        retain = true,   -- new subscribers get the last value immediately
        ttl = 30         -- retained value expires after 30 seconds
    })

    sleep(2)
end
--]]

-- ============================================================================
-- CHIP B: Temperature Subscriber
-- ============================================================================
-- This chip subscribes to temperature updates and logs them.

-- Subscribe using a wildcard to catch all sensor topics
ic.net.subscribe("sensors/*", function(topic, payload, fromId, fromName, retained)
    local prefix = retained and "[RETAINED] " or ""
    print(prefix .. "Topic: " .. topic)
    print("  From: " .. fromName .. " (" .. fromId .. ")")

    if type(payload) == "table" then
        if payload.temp then
            print("  Temp: " .. payload.temp)
        end
    else
        print("  Payload: " .. tostring(payload))
    end
end)

-- Keep the chip alive
while true do
    ic.yield()
end
