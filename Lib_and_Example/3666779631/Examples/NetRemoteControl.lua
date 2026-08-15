-- NetRemoteControl.lua
-- ScriptedScreens example: Remote System Control Panel via RPC
--
-- A command-center console that discovers Lua chips on the network,
-- queries their status via RPC, and lets the operator issue remote
-- commands - all rendered on a slick control panel UI.
--
-- COMPANION CHIP SCRIPT (run on one or more remote Lua chips):
-- ─────────────────────────────────────────────────────────────────
--   local LT = ic.enums.LogicType
--   local active = true
--
--   ic.net.register("status", function(payload, fromId, fromName)
--       local temp = ic.read(0, LT.Temperature)
--       return {
--           active = active,
--           temp   = temp,
--           uptime = os.clock(),
--       }
--   end)
--
--   ic.net.register("toggle", function(payload, fromId, fromName)
--       active = not active
--       return { active = active }
--   end)
--
--   ic.net.register("set_mode", function(payload, fromId, fromName)
--       if type(payload) ~= "table" or payload.mode == nil then
--           error("expected payload.mode")
--       end
--       return { mode = payload.mode, applied = true }
--   end)
--
--   while true do ic.yield() end
-- ─────────────────────────────────────────────────────────────────
--
-- Without companion chips the console runs a built-in RPC simulation
-- so the UI is fully functional for demonstration purposes.

local ui = ss.ui.surface("main")
ss.ui.activate("main")

local size = ui:size()
local W, H = 480, 272
if size then W, H = size.w or W, size.h or H end

-- ── Theme ──────────────────────────────────────────────────────────────
local C = {
    bg     = "#080C18",
    panel  = "#111827",
    header = "#1E293B",
    card   = "#0F172A",
    dim    = "#475569",
    muted  = "#64748B",
    text   = "#E2E8F0",
    green  = "#22C55E",
    yellow = "#EAB308",
    orange = "#F97316",
    red    = "#EF4444",
    cyan   = "#06B6D4",
    blue   = "#3B82F6",
    purple = "#8B5CF6",
}

-- ── State ──────────────────────────────────────────────────────────────
local peers = {}         -- array of { id, name }
local peerStatus = {}    -- id -> { active, temp, uptime, lastPoll, error }
local selectedPeer = nil -- id of selected peer
local eventLog = {}      -- last N log lines
local MAX_LOG = 8
local myId = ic.net.id()
local tickCount = 0
local simMode = true -- simulation until real peers found

-- Simulated peers (used when no real network peers exist)
local simPeers = {
    { id = 90001, name = "Reactor-A" },
    { id = 90002, name = "Airlock-N1" },
    { id = 90003, name = "Greenhouse" },
    { id = 90004, name = "Solar-Ctrl" },
}
local simStatus = {}

local function init_sim()
    for _, p in ipairs(simPeers) do
        simStatus[p.id] = {
            active = true,
            temp   = 18 + math.random() * 10,
            uptime = math.random(100, 9000),
        }
    end
end
init_sim()

-- ── Helpers ────────────────────────────────────────────────────────────
local function log(msg)
    table.insert(eventLog, msg)
    while #eventLog > MAX_LOG do table.remove(eventLog, 1) end
    print("[RemoteCtrl] " .. msg)
end

local function fmt(v, d)
    if v == nil then return "--" end
    return string.format("%." .. (d or 1) .. "f", v)
end

local function fmt_uptime(s)
    if s == nil then return "--" end
    local m = math.floor(s / 60)
    local sec = math.floor(s % 60)
    if m > 60 then
        local h = math.floor(m / 60)
        m = m % 60
        return string.format("%dh%02dm", h, m)
    end
    return string.format("%dm%02ds", m, sec)
end

-- ── Peer discovery ─────────────────────────────────────────────────────
local function refresh_peers()
    local raw = ic.net.peers() or {}
    local realPeers = {}
    for _, p in ipairs(raw) do
        if p.id ~= myId then
            table.insert(realPeers, p)
        end
    end

    if #realPeers > 0 then
        if simMode then
            simMode = false
            log("LIVE: found " .. #realPeers .. " real peers")
        end
        peers = realPeers
    else
        if not simMode then
            -- Stay in live mode but show empty
            peers = realPeers
        else
            peers = simPeers
        end
    end
end

-- ── RPC callbacks ──────────────────────────────────────────────────────

-- Called when a status query returns
function on_status_response(ok, payload, err, fromId, fromName)
    if ok and type(payload) == "table" then
        -- Companion chips report raw sensor Kelvin; convert to Celsius
        local tempC = payload.temp and util.temp(payload.temp) or nil
        peerStatus[fromId] = {
            active   = payload.active,
            temp     = tempC,
            uptime   = payload.uptime,
            lastPoll = os.clock(),
            error    = nil,
        }
    else
        peerStatus[fromId] = peerStatus[fromId] or {}
        peerStatus[fromId].error = err or "unknown error"
        peerStatus[fromId].lastPoll = os.clock()
        log("ERR " .. tostring(fromName or fromId) .. ": " .. tostring(err))
    end
    render()
end

-- Called when a toggle command returns
function on_toggle_response(ok, payload, err, fromId, fromName)
    if ok and type(payload) == "table" then
        local st = peerStatus[fromId] or {}
        st.active = payload.active
        st.lastPoll = os.clock()
        st.error = nil
        peerStatus[fromId] = st
        local state = payload.active and "ACTIVE" or "STANDBY"
        log((fromName or tostring(fromId)) .. " → " .. state)
    else
        log("Toggle failed: " .. tostring(err))
    end
    render()
end

-- Called when a set_mode command returns
function on_mode_response(ok, payload, err, fromId, fromName)
    if ok and type(payload) == "table" then
        log((fromName or tostring(fromId)) .. " mode=" .. tostring(payload.mode))
    else
        log("set_mode failed: " .. tostring(err))
    end
    render()
end

-- ── Actions ────────────────────────────────────────────────────────────
local function poll_status(peerId)
    if simMode then
        -- Simulate RPC response
        local s = simStatus[peerId]
        if s then
            s.uptime = s.uptime + math.random(1, 5)
            s.temp = s.temp + (math.random() - 0.5) * 0.5
            peerStatus[peerId] = {
                active   = s.active,
                temp     = s.temp,
                uptime   = s.uptime,
                lastPoll = os.clock(),
                error    = nil,
            }
        end
        return
    end

    pcall(function()
        ic.net.request(peerId, "status", nil, "on_status_response", 5)
    end)
end

local function toggle_peer(peerId)
    if simMode then
        local s = simStatus[peerId]
        if s then
            s.active = not s.active
            peerStatus[peerId] = peerStatus[peerId] or {}
            peerStatus[peerId].active = s.active
            peerStatus[peerId].lastPoll = os.clock()
            local nm = "?"
            for _, p in ipairs(peers) do
                if p.id == peerId then
                    nm = p.name; break
                end
            end
            local state = s.active and "ACTIVE" or "STANDBY"
            log(nm .. " → " .. state)
        end
        render()
        return
    end

    pcall(function()
        ic.net.request(peerId, "toggle", nil, "on_toggle_response", 5)
    end)
    log("Toggle sent → " .. tostring(peerId))
end

local function send_mode(peerId, mode)
    if simMode then
        log("Mode " .. tostring(mode) .. " → simulated")
        render()
        return
    end

    pcall(function()
        ic.net.request(peerId, "set_mode", { mode = mode }, "on_mode_response", 5)
    end)
    log("set_mode(" .. tostring(mode) .. ") → " .. tostring(peerId))
end

-- ── Render ─────────────────────────────────────────────────────────────
function render()
    ui:clear()

    -- Background
    ui:element({
        id = "bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = H },
        style = { bg = C.bg }
    })

    -- Header
    local hdr = ui:element({
        id = "hdr",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = 36 },
        style = { bg = C.header }
    })
    hdr:element({
        id = "title",
        type = "label",
        rect = { unit = "px", x = 12, y = 7, w = 200, h = 22 },
        props = { text = "REMOTE CONTROL" },
        style = { font_size = 14, color = C.purple, align = "left" }
    })
    local modeText = simMode and "DEMO" or "LIVE"
    local modeColor = simMode and C.yellow or C.green
    hdr:element({
        id = "mode",
        type = "label",
        rect = { unit = "px", x = W - 80, y = 9, w = 70, h = 18 },
        props = { text = modeText },
        style = { font_size = 11, color = modeColor, align = "right" }
    })

    -- Toolbar
    local tb = ui:element({
        id = "tb",
        type = "panel",
        rect = { unit = "px", x = 0, y = 36, w = W, h = 28 },
        style = { bg = "#0D1117" }
    })
    tb:element({
        id = "refresh",
        type = "button",
        rect = { unit = "px", x = 8, y = 3, w = 80, h = 22 },
        props = { text = "REFRESH" },
        style = { bg = "#334155", text = C.text, font_size = 10 },
        on_click = function()
            refresh_peers()
            for _, p in ipairs(peers) do poll_status(p.id) end
            log("Refreshed " .. #peers .. " peers")
            render()
        end
    })
    tb:element({
        id = "poll_all",
        type = "button",
        rect = { unit = "px", x = 96, y = 3, w = 80, h = 22 },
        props = { text = "POLL ALL" },
        style = { bg = C.blue, text = "#FFFFFF", font_size = 10 },
        on_click = function()
            for _, p in ipairs(peers) do poll_status(p.id) end
            log("Polling all...")
            render()
        end
    })
    tb:element({
        id = "peer_cnt",
        type = "label",
        rect = { unit = "px", x = W - 100, y = 5, w = 90, h = 16 },
        props = { text = #peers .. " endpoints" },
        style = { font_size = 10, color = C.dim, align = "right" }
    })

    -- ── Peer list (left panel) ─────────────────────────────────────────
    local listX = 4
    local listY = 68
    local listW = 195
    local rowH = 34
    local maxRows = math.floor((H - listY - 24) / rowH)

    for i, peer in ipairs(peers) do
        if i > maxRows then break end
        local y = listY + ((i - 1) * rowH)
        local st = peerStatus[peer.id] or {}
        local isSelected = selectedPeer == peer.id
        local bgCol = isSelected and "#1E3A5F" or ((i % 2 == 0) and C.card or C.panel)

        -- Clickable row (entire row acts as select button)
        local pid = peer.id
        local row = ui:element({
            id = "pr_" .. i,
            type = "button",
            rect = { unit = "px", x = listX, y = y, w = listW, h = rowH - 2 },
            props = { text = "" },
            style = { bg = bgCol },
            on_click = function()
                selectedPeer = pid
                poll_status(pid)
                render()
            end
        })

        -- Status dot
        local dotColor = C.dim
        if st.active == true then
            dotColor = C.green
        elseif st.active == false then
            dotColor = C.orange
        end
        if st.error then dotColor = C.red end

        row:element({
            id = "pd_" .. i,
            type = "panel",
            rect = { unit = "px", x = 6, y = 8, w = 6, h = 6 },
            style = { bg = dotColor }
        })

        -- Name
        local displayName = (peer.name ~= "" and peer.name) or ("Chip-" .. peer.id)
        row:element({
            id = "pn_" .. i,
            type = "label",
            rect = { unit = "px", x = 16, y = 2, w = listW - 22, h = 16 },
            props = { text = displayName },
            style = { font_size = 11, color = isSelected and C.cyan or C.text, align = "left" }
        })

        -- ID + uptime
        local sub = "ID:" .. peer.id
        if st.uptime then sub = sub .. " | " .. fmt_uptime(st.uptime) end
        row:element({
            id = "ps_" .. i,
            type = "label",
            rect = { unit = "px", x = 16, y = 17, w = listW - 22, h = 12 },
            props = { text = sub },
            style = { font_size = 8, color = C.dim, align = "left" }
        })
    end

    -- ── Detail panel (right side) ──────────────────────────────────────
    local detX = 208
    local detY = 68
    local detW = W - detX - 4

    ui:element({
        id = "det_bg",
        type = "panel",
        rect = { unit = "px", x = detX, y = detY, w = detW, h = 108 },
        style = { bg = C.card }
    })

    if selectedPeer then
        local st = peerStatus[selectedPeer] or {}
        local peerName = "?"
        for _, p in ipairs(peers) do
            if p.id == selectedPeer then
                peerName = p.name ~= "" and p.name or ("Chip-" .. p.id); break
            end
        end

        -- Detail header
        ui:element({
            id = "d_name",
            type = "label",
            rect = { unit = "px", x = detX + 8, y = detY + 4, w = detW - 16, h = 18 },
            props = { text = peerName },
            style = { font_size = 13, color = C.cyan, align = "left" }
        })

        -- Status row
        local activeText = "UNKNOWN"
        local activeColor = C.dim
        if st.active == true then
            activeText = "ACTIVE"; activeColor = C.green
        elseif st.active == false then
            activeText = "STANDBY"; activeColor = C.orange
        end
        if st.error then
            activeText = "ERROR"; activeColor = C.red
        end

        ui:element({
            id = "d_stat",
            type = "label",
            rect = { unit = "px", x = detX + 8, y = detY + 24, w = 80, h = 16 },
            props = { text = activeText },
            style = { font_size = 12, color = activeColor, align = "left" }
        })

        -- Temperature
        if st.temp then
            ui:element({
                id = "d_tl",
                type = "label",
                rect = { unit = "px", x = detX + 8, y = detY + 44, w = 50, h = 14 },
                props = { text = "TEMP" },
                style = { font_size = 9, color = C.dim, align = "left" }
            })
            ui:element({
                id = "d_tv",
                type = "label",
                rect = { unit = "px", x = detX + 8, y = detY + 58, w = 80, h = 20 },
                props = { text = fmt(st.temp) .. " C" },
                style = { font_size = 16, color = C.text, align = "left" }
            })
        end

        -- Uptime
        if st.uptime then
            ui:element({
                id = "d_ul",
                type = "label",
                rect = { unit = "px", x = detX + 100, y = detY + 44, w = 60, h = 14 },
                props = { text = "UPTIME" },
                style = { font_size = 9, color = C.dim, align = "left" }
            })
            ui:element({
                id = "d_uv",
                type = "label",
                rect = { unit = "px", x = detX + 100, y = detY + 58, w = 80, h = 20 },
                props = { text = fmt_uptime(st.uptime) },
                style = { font_size = 16, color = C.text, align = "left" }
            })
        end

        -- Error display
        if st.error then
            ui:element({
                id = "d_err",
                type = "label",
                rect = { unit = "px", x = detX + 8, y = detY + 82, w = detW - 16, h = 14 },
                props = { text = "ERR: " .. tostring(st.error) },
                style = { font_size = 9, color = C.red, align = "left" }
            })
        end

        -- ── Command buttons ────────────────────────────────────────────
        local cmdY = detY + 114
        local btnGap = 4
        local btnH = 22
        local btnPad = 6 -- padding from detail panel edges
        local btnArea = detW - btnPad * 2
        local btnW = math.floor((btnArea - btnGap * 3) / 4)

        ui:element({
            id = "cmd_lbl",
            type = "label",
            rect = { unit = "px", x = detX + btnPad, y = cmdY, w = 80, h = 14 },
            props = { text = "COMMANDS" },
            style = { font_size = 9, color = C.dim, align = "left" }
        })

        cmdY = cmdY + 16
        local selId = selectedPeer

        ui:element({
            id = "cmd_poll",
            type = "button",
            rect = { unit = "px", x = detX + btnPad, y = cmdY, w = btnW, h = btnH },
            props = { text = "POLL" },
            style = { bg = C.blue, text = "#FFF", font_size = 10 },
            on_click = function()
                poll_status(selId)
                log("Poll → " .. tostring(selId))
                render()
            end
        })

        ui:element({
            id = "cmd_toggle",
            type = "button",
            rect = { unit = "px", x = detX + btnPad + (btnW + btnGap), y = cmdY, w = btnW, h = btnH },
            props = { text = "TOGGLE" },
            style = { bg = C.orange, text = "#000", font_size = 10 },
            on_click = function()
                toggle_peer(selId)
            end
        })

        ui:element({
            id = "cmd_eco",
            type = "button",
            rect = { unit = "px", x = detX + btnPad + (btnW + btnGap) * 2, y = cmdY, w = btnW, h = btnH },
            props = { text = "ECO" },
            style = { bg = C.green, text = "#000", font_size = 10 },
            on_click = function()
                send_mode(selId, "eco")
            end
        })

        ui:element({
            id = "cmd_perf",
            type = "button",
            rect = { unit = "px", x = detX + btnPad + (btnW + btnGap) * 3, y = cmdY, w = btnW, h = btnH },
            props = { text = "PERF" },
            style = { bg = C.purple, text = "#FFF", font_size = 10 },
            on_click = function()
                send_mode(selId, "performance")
            end
        })
    else
        -- No selection placeholder
        ui:element({
            id = "d_empty",
            type = "label",
            rect = { unit = "px", x = detX + 8, y = detY + 40, w = detW - 16, h = 20 },
            props = { text = "Select an endpoint" },
            style = { font_size = 12, color = C.dim, align = "center" }
        })
    end

    -- ── Event log (full-width, below both panels) ────────────────
    local logY = detY + 152
    local logH = H - logY - 20
    local logW = W - 8

    ui:element({
        id = "log_bg",
        type = "panel",
        rect = { unit = "px", x = 4, y = logY, w = logW, h = logH },
        style = { bg = "#0D1117" }
    })
    ui:element({
        id = "log_hdr",
        type = "label",
        rect = { unit = "px", x = 10, y = logY + 2, w = 70, h = 12 },
        props = { text = "EVENT LOG" },
        style = { font_size = 8, color = C.dim, align = "left" }
    })

    local logLineH = 11
    for li = 1, #eventLog do
        local ly = logY + 14 + ((li - 1) * logLineH)
        if ly + logLineH > logY + logH then break end
        ui:element({
            id = "log_" .. li,
            type = "label",
            rect = { unit = "px", x = 10, y = ly, w = logW - 16, h = logLineH },
            props = { text = eventLog[li] },
            style = { font_size = 7, color = C.muted, align = "left" }
        })
    end

    -- Footer
    ui:element({
        id = "ft",
        type = "label",
        rect = { unit = "px", x = 8, y = H - 16, w = 180, h = 12 },
        props = { text = "RPC Control | ID:" .. tostring(myId) },
        style = { font_size = 8, color = C.dim, align = "left" }
    })

    ui:commit()
end

-- ── Boot ───────────────────────────────────────────────────────────────
log("System online")
refresh_peers()
-- Initial poll
for _, p in ipairs(peers) do poll_status(p.id) end
if #peers > 0 then selectedPeer = peers[1].id end
render()

-- ── Main loop ──────────────────────────────────────────────────────────
while true do
    tickCount = tickCount + 1

    -- Auto-poll every ~8 seconds
    if tickCount % 80 == 0 then
        refresh_peers()
        for _, p in ipairs(peers) do poll_status(p.id) end
        render()
    end

    ic.yield()
end
