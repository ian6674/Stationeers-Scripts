--[[
    WirelessTabletDemo.lua

    ScriptedScreens example: Friendly wireless tablet network manager.
    - Lists in-range omni power transmitters
    - Connects/disconnects to wireless data networks
    - Shows mesh handoff status
    - Pings the connected data network to show peer responses

    Usage:
    1. Insert a wireless ScriptedScreens Lua cartridge into a tablet.
    2. Power the tablet on and run this script.
    3. Tap a transmitter to connect; mesh can be toggled on/off.
]]

local ui = ss.ui.surface("main")
ss.ui.activate("main")

local size = ui:size()
local W, H = 480, 272
if size then W, H = size.w or W, size.h or H end

-- Visual theme
local COLORS = {
    bg = "#0B1120",
    panel = "#111827",
    panel_soft = "#0F172A",
    header = "#1F2937",
    text = "#E2E8F0",
    text_dim = "#94A3B8",
    accent = "#38BDF8",
    accent_dark = "#0EA5E9",
    success = "#22C55E",
    warning = "#F59E0B",
    danger = "#EF4444",
    button = "#1E293B",
}

local networks = {}
local status = {
    connected = false,
    in_range = false,
    mesh = true,
    network_id = 0,
    transmitter_id = 0,
    transmitter_name = "",
    distance = 0,
    max_distance = 0
}

-- Use NetChat ping channel so tablet pings show in NetChat.lua
local NET_CHANNEL = "monitor"
local net_state = {
    peer_count = 0,
    peers = {},
    last_ping_time = 0,
    last_ping_from = "",
    last_pong_time = 0,
    last_pong_from = "",
}

local my_id = 0
local my_name = "Tablet"

local mesh_enabled = true
local last_error = ""
local SCAN_INTERVAL = 10

-- Sanitize string to ASCII-only (replace non-printable/non-ASCII with ?)
local function ascii_safe(str)
    if not str or str == "" then return "" end
    local out = {}
    for i = 1, #str do
        local b = string.byte(str, i)
        if b >= 32 and b <= 126 then
            out[#out + 1] = string.char(b)
        else
            out[#out + 1] = "?"
        end
    end
    return table.concat(out)
end

local function format_distance(value)
    if value == nil then return "-- m" end
    return string.format("%.1f m", value)
end

local function format_age(timestamp)
    if not timestamp or timestamp <= 0 then
        return "--"
    end
    local age = os.clock() - timestamp
    if age < 0 then age = 0 end
    return string.format("%.1fs ago", age)
end

local function safe_call(fn, ...)
    local ok, a, b, c = pcall(fn, ...)
    if not ok then
        return false, tostring(a) or "unknown error"
    end
    return true, a, b, c
end

local function update_my_identity()
    local ok, id = safe_call(ic.net.id)
    if ok and id then
        my_id = id
    else
        my_id = 0
    end
end

local function refresh_network_info()
    if not status.connected or not status.in_range then
        net_state.peer_count = 0
        net_state.peers = {}
        return
    end

    local ok, peers = safe_call(ic.net.peers)
    if not ok or type(peers) ~= "table" then
        net_state.peer_count = 0
        net_state.peers = {}
        return
    end

    net_state.peer_count = #peers
    net_state.peers = peers

    -- Update my_name from peer list
    for _, peer in ipairs(peers) do
        if peer.id == my_id then
            local name = ascii_safe(peer.name or "")
            my_name = name ~= "" and name or ("Tablet-" .. tostring(my_id))
            break
        end
    end
end

local function update_status()
    local ok, result = safe_call(ss.tablet.wireless.status)
    if not ok then
        last_error = ascii_safe(tostring(result))
        return
    end

    if type(result) == "table" then
        status = result
    end

    update_my_identity()
    refresh_network_info()
end

local function scan_networks()
    local ok, result = safe_call(ss.tablet.wireless.list)
    if not ok then
        last_error = ascii_safe(tostring(result))
        networks = {}
        return
    end

    networks = result or {}
end

-- Forward declaration
local render

local function connect_to(target_id)
    local ok, result, err = safe_call(ss.tablet.wireless.connect, target_id, mesh_enabled)
    if not ok then
        last_error = ascii_safe(tostring(result))
        update_status()
        render()
        return
    end

    if not result then
        last_error = ascii_safe(tostring(err or "unable to connect"))
    else
        last_error = ""
    end

    update_status()
    render()
end

local function send_ping()
    if not status.connected or not status.in_range then
        last_error = "Not connected"
        render()
        return
    end

    local payload = {
        type = "ping",
        name = my_name,
        time = os.clock(),
    }

    local ok, result = safe_call(ic.net.broadcast, NET_CHANNEL, payload)
    if not ok then
        last_error = "Broadcast: " .. ascii_safe(tostring(result))
        render()
        return
    end

    net_state.last_ping_time = os.clock()
    net_state.last_ping_from = my_name
    last_error = ""
    render()
end

-- Message handler for network pings/pongs
function on_wireless_net(fromId, fromName, payload)
    if type(payload) ~= "table" then
        return
    end

    local sender = ascii_safe(fromName or "") ~= "" and ascii_safe(fromName) or ("ID " .. tostring(fromId))

    if payload.type == "ping" then
        net_state.last_ping_time = os.clock()
        net_state.last_ping_from = sender

        -- Send pong reply
        if status.connected and status.in_range then
            safe_call(ic.net.send, fromId, NET_CHANNEL, {
                type = "pong",
                name = my_name,
            })
        end
    elseif payload.type == "pong" then
        net_state.last_pong_time = os.clock()
        net_state.last_pong_from = sender
    end
end

ic.net.listen(NET_CHANNEL, "on_wireless_net")

local function disconnect()
    safe_call(ss.tablet.wireless.disconnect)
    update_status()
    render()
end

local function render_status_text()
    if not status.connected then
        return "DISCONNECTED"
    end
    if status.in_range then
        return "CONNECTED"
    end
    return "OUT OF RANGE"
end

render = function()
    ui:clear()

    -- Background
    ui:element({
        id = "bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = H },
        style = { bg = COLORS.bg }
    })

    -- Header
    ui:element({
        id = "header",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = 36 },
        style = { bg = COLORS.header }
    })

    ui:element({
        id = "title",
        type = "label",
        rect = { unit = "px", x = 14, y = 8, w = W - 28, h = 20 },
        props = { text = "WIRELESS NETWORKS" },
        style = { font_size = 14, color = COLORS.accent, align = "left" }
    })

    -- Status panel
    local status_y = 42
    local status_h = 140

    ui:element({
        id = "status_panel",
        type = "panel",
        rect = { unit = "px", x = 10, y = status_y, w = W - 20, h = status_h },
        style = { bg = COLORS.panel }
    })

    -- Status line 1: Connection status
    ui:element({
        id = "status_label",
        type = "label",
        rect = { unit = "px", x = 20, y = status_y + 10, w = 250, h = 18 },
        props = { text = "Status: " .. render_status_text() },
        style = { font_size = 12, color = status.in_range and COLORS.success or COLORS.warning, align = "left" }
    })

    -- Status line 2: Network/transmitter info
    local tx_name = ascii_safe(status.transmitter_name or "")
    if tx_name == "" and status.connected then
        tx_name = "Transmitter " .. tostring(status.transmitter_id)
    end
    local detail_text = status.connected and ("Net " .. tostring(status.network_id) .. " | " .. tx_name) or
        "No active connection"

    ui:element({
        id = "status_detail",
        type = "label",
        rect = { unit = "px", x = 20, y = status_y + 28, w = 250, h = 16 },
        props = { text = detail_text },
        style = { font_size = 10, color = COLORS.text_dim, align = "left" }
    })

    -- Status line 3: Range info
    ui:element({
        id = "status_range",
        type = "label",
        rect = { unit = "px", x = 20, y = status_y + 44, w = 250, h = 16 },
        props = { text = "Range: " .. format_distance(status.distance) .. " / " .. format_distance(status.max_distance) },
        style = { font_size = 10, color = COLORS.text_dim, align = "left" }
    })

    -- Status line 4: Local identity
    ui:element({
        id = "status_local",
        type = "label",
        rect = { unit = "px", x = 20, y = status_y + 60, w = 250, h = 16 },
        props = { text = "Local: " .. ascii_safe(my_name) .. " (" .. tostring(my_id) .. ")" },
        style = { font_size = 10, color = COLORS.text_dim, align = "left" }
    })

    -- Status line 5: Peer count and pong info
    local pong_text = net_state.last_pong_from ~= "" and
        (ascii_safe(net_state.last_pong_from) .. " " .. format_age(net_state.last_pong_time)) or "--"
    ui:element({
        id = "status_peers",
        type = "label",
        rect = { unit = "px", x = 20, y = status_y + 76, w = 250, h = 16 },
        props = { text = "Peers: " .. tostring(net_state.peer_count) .. " | Pong: " .. pong_text },
        style = { font_size = 10, color = COLORS.text_dim, align = "left" }
    })

    -- Status line 6: Error (if any) - BELOW the peer info
    if last_error ~= "" then
        ui:element({
            id = "status_error",
            type = "label",
            rect = { unit = "px", x = 20, y = status_y + 92, w = 250, h = 16 },
            props = { text = "Error: " .. ascii_safe(last_error) },
            style = { font_size = 10, color = COLORS.danger, align = "left" }
        })
    end

    -- Peer list (small, below error line)
    local peer_y = status_y + 110
    local max_peers_shown = 2
    for i = 1, math.min(#net_state.peers, max_peers_shown) do
        local peer = net_state.peers[i]
        local pname = ascii_safe(peer.name or "")
        if pname == "" then pname = "ID " .. tostring(peer.id) end
        if peer.id == my_id then pname = pname .. " (you)" end

        ui:element({
            id = "peer_" .. i,
            type = "label",
            rect = { unit = "px", x = 20, y = peer_y + (i - 1) * 12, w = 250, h = 12 },
            props = { text = "> " .. pname },
            style = { font_size = 9, color = COLORS.text_dim, align = "left" }
        })
    end

    -- Buttons (right side)
    local btn_w = 90
    local btn_h = 22
    local btn_x = W - btn_w - 22

    ui:element({
        id = "btn_refresh",
        type = "button",
        rect = { unit = "px", x = btn_x, y = status_y + 8, w = btn_w, h = btn_h },
        props = { text = "REFRESH" },
        style = { bg = COLORS.accent_dark, text = COLORS.text, font_size = 10 },
        on_click = function()
            last_error = ""
            scan_networks()
            update_status()
            render()
        end
    })

    ui:element({
        id = "btn_mesh",
        type = "button",
        rect = { unit = "px", x = btn_x, y = status_y + 34, w = btn_w, h = btn_h },
        props = { text = "MESH " .. (mesh_enabled and "ON" or "OFF") },
        style = { bg = mesh_enabled and COLORS.success or COLORS.button, text = COLORS.text, font_size = 10 },
        on_click = function()
            mesh_enabled = not mesh_enabled
            render()
        end
    })

    ui:element({
        id = "btn_disconnect",
        type = "button",
        rect = { unit = "px", x = btn_x, y = status_y + 60, w = btn_w, h = btn_h },
        props = { text = "DISCONNECT" },
        style = { bg = COLORS.button, text = COLORS.text, font_size = 10 },
        on_click = function()
            disconnect()
        end
    })

    ui:element({
        id = "btn_ping",
        type = "button",
        rect = { unit = "px", x = btn_x, y = status_y + 86, w = btn_w, h = btn_h },
        props = { text = "PING" },
        style = { bg = COLORS.accent_dark, text = COLORS.text, font_size = 10 },
        on_click = function()
            send_ping()
        end
    })

    -- Network list panel
    local list_y = status_y + status_h + 8
    local list_h = H - list_y - 10

    ui:element({
        id = "list_panel",
        type = "panel",
        rect = { unit = "px", x = 10, y = list_y, w = W - 20, h = list_h },
        style = { bg = COLORS.panel_soft }
    })

    ui:element({
        id = "list_title",
        type = "label",
        rect = { unit = "px", x = 18, y = list_y + 6, w = W - 36, h = 16 },
        props = { text = "In-range transmitters" },
        style = { font_size = 11, color = COLORS.text_dim, align = "left" }
    })

    local row_h = 34
    local max_rows = math.max(1, math.floor((list_h - 28) / row_h))

    if #networks == 0 then
        ui:element({
            id = "list_empty",
            type = "label",
            rect = { unit = "px", x = 18, y = list_y + 30, w = W - 36, h = 18 },
            props = { text = "No omni transmitters in range." },
            style = { font_size = 11, color = COLORS.text_dim, align = "left" }
        })
    else
        local row_y = list_y + 26
        for i = 1, math.min(#networks, max_rows) do
            local t = networks[i]
            local is_active = status.connected and status.transmitter_id == t.id
            local tname = ascii_safe(t.name or "")
            if tname == "" then tname = "Transmitter " .. tostring(t.id) end

            ui:element({
                id = "row_bg_" .. i,
                type = "panel",
                rect = { unit = "px", x = 14, y = row_y, w = W - 28, h = row_h - 4 },
                style = { bg = is_active and "#1E3A8A" or COLORS.panel }
            })

            ui:element({
                id = "row_name_" .. i,
                type = "label",
                rect = { unit = "px", x = 22, y = row_y + 6, w = W - 160, h = 16 },
                props = { text = tname },
                style = { font_size = 11, color = COLORS.text, align = "left" }
            })

            ui:element({
                id = "row_meta_" .. i,
                type = "label",
                rect = { unit = "px", x = 22, y = row_y + 20, w = W - 160, h = 14 },
                props = { text = "Net " .. tostring(t.network_id) .. " | " .. format_distance(t.distance) },
                style = { font_size = 9, color = COLORS.text_dim, align = "left" }
            })

            ui:element({
                id = "row_btn_" .. i,
                type = "button",
                rect = { unit = "px", x = W - 108, y = row_y + 7, w = 80, h = 20 },
                props = { text = is_active and "ACTIVE" or "CONNECT" },
                style = { bg = is_active and COLORS.success or COLORS.button, text = COLORS.text, font_size = 9 },
                on_click = function()
                    connect_to(t.id)
                end
            })

            row_y = row_y + row_h
        end

        if #networks > max_rows then
            ui:element({
                id = "list_more",
                type = "label",
                rect = { unit = "px", x = 18, y = list_y + list_h - 18, w = W - 36, h = 14 },
                props = { text = "+" .. tostring(#networks - max_rows) .. " more" },
                style = { font_size = 9, color = COLORS.text_dim, align = "left" }
            })
        end
    end

    ui:commit()
end

-- Initial data fetch and render
scan_networks()
update_status()
render()

-- Main loop
local tick = 0
while true do
    tick = tick + 1

    -- Update status every tick
    update_status()

    -- Scan for networks periodically
    if tick % (SCAN_INTERVAL * 2) == 0 then
        scan_networks()
    end

    -- Render every few ticks
    if tick % 3 == 0 then
        render()
    end

    ic.yield()
end
