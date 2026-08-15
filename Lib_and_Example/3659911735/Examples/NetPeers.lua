-- NetPeers.lua
-- Example: Discovers and lists all Lua chip peers on the same data network.
-- Useful for debugging, network topology discovery, or dynamic targeting.

local CHANNEL = "ping"

-- Discover and print all peers on the network
local function discover_peers()
    local peers = ic.net.peers()
    local myId = ic.net.id()

    print("=== Network Peer Discovery ===")
    print(string.format("My endpoint id: %s", tostring(myId)))
    print(string.format("Found %d peer(s) on data network:", #peers))
    print("")

    for i, peer in ipairs(peers) do
        local marker = ""
        if peer.id == myId then
            marker = " (self)"
        end
        print(string.format("  [%d] id=%d name='%s'%s", i, peer.id, peer.name, marker))
    end

    print("")
    return peers
end

-- Find a peer by name (partial match, case-insensitive)
local function find_peer_by_name(peers, searchName)
    searchName = string.lower(searchName)
    local matches = {}

    for _, peer in ipairs(peers) do
        if string.lower(peer.name):find(searchName) then
            table.insert(matches, peer)
        end
    end

    return matches
end

-- Example: Send a message to the first peer that isn't us
local function ping_first_peer()
    local peers = ic.net.peers()
    local myId = ic.net.id()

    for _, peer in ipairs(peers) do
        if peer.id ~= myId then
            print(string.format("Pinging peer: %s (id=%d)", peer.name, peer.id))
            local ok, err = pcall(function()
                ic.net.send(peer.id, CHANNEL, "ping")
            end)
            if ok then
                print("  Ping sent!")
            else
                print("  Failed: " .. tostring(err))
            end
            return
        end
    end

    print("No other peers found on network")
end

-- Handler for ping messages
function on_ping(fromId, fromName, payload)
    if payload == "ping" then
        print(string.format("Received ping from %s, sending pong...", fromName))
        pcall(function()
            ic.net.send(fromId, CHANNEL, "pong")
        end)
    elseif payload == "pong" then
        print(string.format("Received pong from %s!", fromName))
    end
end

ic.net.listen(CHANNEL, "on_ping")

print("[NetPeers] Network discovery example")
print("")

-- Initial discovery
discover_peers()

-- Main loop - rediscover periodically
while true do
    sleep(30)
    print("")
    print("[NetPeers] Refreshing peer list...")
    local peers = discover_peers()

    -- Try to ping someone
    ping_first_peer()
end
