-- NetPingPong.lua
-- Example: Bidirectional ping-pong communication between two chips.
-- Deploy this same script to two housings on the same data network.
-- Name one "PingA" and the other "PingB" using a labeller.

local CHANNEL = "pingpong"

-- Determine our role based on housing name
-- The chip named "PingA" initiates; "PingB" responds
local myId = ic.net.id()
local peers = ic.net.peers()
local myName = ""
local partnerName = ""
local isInitiator = false

-- Find our name and partner
for _, peer in ipairs(peers) do
    if peer.id == myId then
        myName = peer.name
    end
end

if myName:lower():find("pinga") then
    isInitiator = true
    partnerName = "PingB"
elseif myName:lower():find("pingb") then
    isInitiator = false
    partnerName = "PingA"
else
    print("[PingPong] Warning: Name this housing 'PingA' or 'PingB'!")
    print("[PingPong] Current name: " .. myName)
    partnerName = "" -- Will need to be set manually
end

print(string.format("[PingPong] I am '%s' (id=%d)", myName, myId))
print(string.format("[PingPong] Partner: '%s'", partnerName))
print(string.format("[PingPong] Role: %s", isInitiator and "INITIATOR" or "RESPONDER"))

-- Statistics
local pingsSent = 0
local pongsReceived = 0
local pingsReceived = 0
local pongsSent = 0

-- Message handler
function on_message(fromId, fromName, payload)
    if type(payload) ~= "table" then
        return
    end

    if payload.type == "ping" then
        pingsReceived = pingsReceived + 1
        print(string.format("[PingPong] PING #%d from %s (seq=%d, latency=%.0fms)",
            pingsReceived, fromName, payload.seq or 0,
            (os.time() - (payload.timestamp or os.time())) * 1000))

        -- Send pong back
        local pong = {
            type = "pong",
            seq = payload.seq,
            timestamp = os.time(),
            originalTimestamp = payload.timestamp
        }
        local ok = pcall(function()
            ic.net.send(fromId, CHANNEL, pong)
        end)
        if ok then
            pongsSent = pongsSent + 1
        end
    elseif payload.type == "pong" then
        pongsReceived = pongsReceived + 1
        local roundTrip = (os.time() - (payload.originalTimestamp or os.time())) * 1000
        print(string.format("[PingPong] PONG #%d from %s (seq=%d, RTT=%.0fms)",
            pongsReceived, fromName, payload.seq or 0, roundTrip))
    end
end

ic.net.listen(CHANNEL, "on_message")

-- Send a ping
local function send_ping()
    if partnerName == "" then
        return false
    end

    pingsSent = pingsSent + 1
    local ping = {
        type = "ping",
        seq = pingsSent,
        timestamp = os.time()
    }

    local ok, err = pcall(function()
        ic.net.send(partnerName, CHANNEL, ping)
    end)
    if ok then
        print(string.format("[PingPong] Sent PING #%d to %s", pingsSent, partnerName))
    else
        print(string.format("[PingPong] Failed to send ping: %s", tostring(err)))
        pingsSent = pingsSent - 1
    end
    return ok
end

-- Print stats
local function print_stats()
    print(string.format("[PingPong] Stats: sent=%d recv=%d pongs_recv=%d pongs_sent=%d",
        pingsSent, pingsReceived, pongsReceived, pongsSent))
end

-- Main loop
if isInitiator then
    print("[PingPong] Starting as initiator, sending pings every 5 seconds...")
    sleep(2) -- Give responder time to start
end

while true do
    if isInitiator then
        send_ping()
    end

    sleep(5)

    -- Print stats occasionally
    if (pingsSent + pingsReceived) % 5 == 0 then
        print_stats()
    end
end
