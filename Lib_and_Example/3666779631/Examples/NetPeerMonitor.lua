-- NetPeerMonitor.lua
-- ScriptedScreens example: Network peer monitor with ping functionality
-- Shows all Lua chip peers on the data network and allows sending pings.
-- print() output appears in the Lua Debugger Logs tab.

local ui = ss.ui.surface("main")
ss.ui.activate("main")

local CHANNEL = "monitor"

local size = ui:size()
local W, H = 480, 272
if size then W, H = size.w or W, size.h or H end

-- State
local peers = {}
local myId = ic.net.id()
local peerResponded = {} -- Tracks which peers have responded to our pings

-- Refresh peer list
local function refresh_peers(reason)
    peers = ic.net.peers() or {}
    if reason then
        print(string.format("[NetPeerMonitor] Refreshed peers (%s): %d", reason, #peers))
    end
end

-- Handle incoming pings/pongs
function on_ping(fromId, fromName, payload)
    if type(payload) ~= "table" then return end

    if payload.type == "ping" then
        -- Reply with pong
        print(string.format("[NetPeerMonitor] Ping from %s (id=%d)", tostring(fromName), fromId))
        pcall(function()
            ic.net.send(fromId, CHANNEL, { type = "pong" })
        end)
    elseif payload.type == "pong" then
        -- Mark peer as responsive
        print(string.format("[NetPeerMonitor] Pong from %s (id=%d)", tostring(fromName), fromId))
        peerResponded[fromId] = true
        render()
    end
end

ic.net.listen(CHANNEL, "on_ping")

-- Send a ping to a peer
local function send_ping(peerId)
    peerResponded[peerId] = nil -- Clear previous response
    print(string.format("[NetPeerMonitor] Ping -> id=%d", peerId))
    pcall(function()
        ic.net.send(peerId, CHANNEL, { type = "ping" })
    end)
end

-- Ping all peers
local function ping_all()
    print("[NetPeerMonitor] Pinging all peers")
    for _, peer in ipairs(peers) do
        if peer.id ~= myId then
            send_ping(peer.id)
        end
    end
end

-- Render the UI
function render()
    ui:clear()

    -- Background
    ui:element({
        id = "bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = H },
        style = { bg = "#0A0E1A" }
    })

    -- Header
    local header = ui:element({
        id = "header",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = 44 },
        style = { bg = "#1E293B" }
    })

    header:element({
        id = "title",
        type = "label",
        rect = { unit = "px", x = 16, y = 10, w = 200, h = 24 },
        props = { text = "NETWORK PEERS" },
        style = { font_size = 16, color = "#3B82F6", align = "left" }
    })

    header:element({
        id = "peer_count",
        type = "label",
        rect = { unit = "px", x = W - 100, y = 12, w = 90, h = 20 },
        props = { text = #peers .. " peers" },
        style = { font_size = 12, color = "#64748B", align = "right" }
    })

    -- Toolbar
    local toolbar = ui:element({
        id = "toolbar",
        type = "panel",
        rect = { unit = "px", x = 0, y = 48, w = W, h = 32 },
        style = { bg = "#111827" }
    })

    toolbar:element({
        id = "refresh_btn",
        type = "button",
        rect = { unit = "px", x = 10, y = 4, w = 80, h = 24 },
        props = { text = "REFRESH" },
        style = { bg = "#334155", text = "#E2E8F0" },
        on_click = function()
            refresh_peers()
            render()
        end
    })

    toolbar:element({
        id = "ping_all_btn",
        type = "button",
        rect = { unit = "px", x = 100, y = 4, w = 80, h = 24 },
        props = { text = "PING ALL" },
        style = { bg = "#3B82F6", text = "#FFFFFF" },
        on_click = function()
            ping_all()
        end
    })

    -- Peer list
    local listY = 84
    local rowH = 28
    local visibleRows = math.floor((H - listY - 30) / rowH)

    for i, peer in ipairs(peers) do
        if i > visibleRows then break end

        local y = listY + ((i - 1) * rowH)
        local isSelf = peer.id == myId
        local bgColor = isSelf and "#1E3A5F" or "#111827"
        local nameColor = isSelf and "#22C55E" or "#E2E8F0"

        -- Row background
        ui:element({
            id = "peer_row_" .. i,
            type = "panel",
            rect = { unit = "px", x = 8, y = y, w = W - 16, h = rowH - 2 },
            style = { bg = bgColor }
        })

        -- Status indicator
        local statusColor = "#22C55E" -- Online
        ui:element({
            id = "peer_status_" .. i,
            type = "panel",
            rect = { unit = "px", x = 14, y = y + 9, w = 8, h = 8 },
            style = { bg = statusColor }
        })

        -- Name
        local displayName = peer.name ~= "" and peer.name or ("Unnamed-" .. peer.id)
        if isSelf then displayName = displayName .. " (self)" end

        ui:element({
            id = "peer_name_" .. i,
            type = "label",
            rect = { unit = "px", x = 28, y = y + 4, w = 180, h = 18 },
            props = { text = displayName },
            style = { font_size = 11, color = nameColor, align = "left" }
        })

        -- ID
        ui:element({
            id = "peer_id_" .. i,
            type = "label",
            rect = { unit = "px", x = 210, y = y + 4, w = 100, h = 18 },
            props = { text = "ID: " .. peer.id },
            style = { font_size = 9, color = "#64748B", align = "left" }
        })

        -- Response indicator (if pinged and responded)
        if peerResponded[peer.id] then
            ui:element({
                id = "peer_resp_" .. i,
                type = "label",
                rect = { unit = "px", x = 320, y = y + 4, w = 60, h = 18 },
                props = { text = "OK" },
                style = { font_size = 10, color = "#22C55E", align = "right" }
            })
        end

        -- Ping button (not for self)
        if not isSelf then
            local peerId = peer.id
            ui:element({
                id = "peer_ping_" .. i,
                type = "button",
                rect = { unit = "px", x = W - 70, y = y + 3, w = 50, h = 20 },
                props = { text = "PING" },
                style = { bg = "#475569", text = "#E2E8F0" },
                on_click = function()
                    send_ping(peerId)
                end
            })
        end
    end

    -- Footer
    ui:element({
        id = "footer",
        type = "label",
        rect = { unit = "px", x = 16, y = H - 22, w = 200, h = 14 },
        props = { text = "My ID: " .. tostring(myId) },
        style = { font_size = 10, color = "#475569", align = "left" }
    })

    ui:commit()
end

-- Initial setup
print(string.format("[NetPeerMonitor] Started (id=%d)", myId))
refresh_peers("startup")
render()

-- Main loop - auto-refresh periodically
local tick = 0
while true do
    tick = tick + 1

    if tick % 100 == 0 then
        refresh_peers("auto")
        render()
    end

    ic.yield()
end
