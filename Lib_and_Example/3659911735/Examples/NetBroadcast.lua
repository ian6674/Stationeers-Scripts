-- NetBroadcast.lua
-- Example: Broadcasts messages to ALL Lua chips on the same data network.
-- Useful for network-wide announcements, synchronization, or discovery.

local LT = ic.enums.LogicType
local CHANNEL = "broadcast"

-- Broadcast a heartbeat/status message to all peers
local function broadcast_status()
    local myId = ic.net.id()
    local status = {
        type = "status",
        id = myId,
        uptime = os.time(),
        pressure = ic.read(0, LT.Pressure) or 0,
        temperature = ic.read(0, LT.Temperature) or 0
    }

    -- broadcast returns the number of peers that received the message
    local delivered = ic.net.broadcast(CHANNEL, status)
    print(string.format("[Broadcast] Status sent to %d peers", delivered))
end

-- Broadcast an alert
local function broadcast_alert(message)
    local alert = {
        type = "alert",
        message = message,
        priority = "high"
    }

    local delivered = ic.net.broadcast(CHANNEL, alert)
    print(string.format("[Broadcast] Alert sent to %d peers: %s", delivered, message))
end

-- Handler for incoming broadcasts from other chips
function on_broadcast(fromId, fromName, payload)
    if type(payload) ~= "table" then
        return
    end

    if payload.type == "status" then
        print(string.format("[Broadcast] Status from %s: P=%.1f T=%.1f",
            fromName, payload.pressure or 0, payload.temperature or 0))
    elseif payload.type == "alert" then
        print(string.format("[Broadcast] ALERT from %s: %s", fromName, payload.message or ""))
    end
end

-- Listen for broadcasts on CHANNEL
ic.net.listen(CHANNEL, "on_broadcast")

print(string.format("[Broadcast] Listening on channel '%s' and broadcasting status every 10 seconds", CHANNEL))

-- Main loop
local counter = 0
while true do
    counter = counter + 1

    -- Broadcast status every 10 seconds
    broadcast_status()

    -- Occasionally send an alert (every minute)
    if counter % 6 == 0 then
        broadcast_alert("Periodic check-in from broadcaster")
    end

    sleep(10)
end
