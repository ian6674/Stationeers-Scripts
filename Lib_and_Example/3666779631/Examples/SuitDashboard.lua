-- SuitDashboard.lua
-- ScriptedScreens example: Per-Player EVA Suit Telemetry Dashboard
--
-- Subscribes to "suit/telemetry" from suit chips (SuitTelemetry.lua).
--
-- Scrollview rule (see DeviceInspector.lua): only **direct** `sv:element(...)` children
-- with explicit content Y. Nesting `row:element()` under a scrollview row runs
-- ComputeChildRect in C#, which treats the row's rect as surface space - first row y≈0
-- draws on top of the header. Transparent hit-button is added last per row for clicks.
--
-- Tap a crew row to open loadout; ← BACK returns to the list.

local ui = ss.ui.surface("main")
ss.ui.activate("main")

local W, H = 480, 272
do
    local sz = ui:size()
    if sz then W, H = sz.w or W, sz.h or H end
end

local HEADER_H = 32
local ROW_H    = 44
local LIST_H   = H - HEADER_H

local view = "main" -- "main" | "loadout"
local selected_player = nil

local CARD_H = 56
local PIN_ORDER = { "helmet", "backpack", "toolbelt", "glasses", "left_hand", "right_hand" }

local SLOT_ACCENTS = {
    helmet     = "#6366F1",
    backpack   = "#8B5CF6",
    toolbelt   = "#14B8A6",
    glasses    = "#38BDF8",
    left_hand  = "#F472B6",
    right_hand = "#FB7185",
}

local C = {
    bg       = "#070B14",
    panel    = "#0F172A",
    panel_hi = "#1E293B",
    header   = "#1E293B",
    dim      = "#64748B",
    muted    = "#475569",
    text     = "#F1F5F9",
    green    = "#22C55E",
    cyan     = "#22D3EE",
    accent   = "#38BDF8",
    btn      = "#2563EB",
    stripe   = "#334155",
}

local game_time = util.game_time
local STALE_SECONDS = 60
local players = {} -- name -> data (only source of truth for who appears)

local function player_names_sorted()
    local t = {}
    for name, d in pairs(players) do
        if d ~= nil then
            table.insert(t, name)
        end
    end
    table.sort(t)
    return t
end

local function prune_stale()
    local now = game_time()
    local kill = {}
    for name, d in pairs(players) do
        if (now - d.time) >= STALE_SECONDS then
            kill[#kill + 1] = name
        end
    end
    for i = 1, #kill do
        players[kill[i]] = nil
    end
end

local function o2_color(ratio)
    if ratio == nil then return C.dim end
    if ratio >= 0.19 then return C.green end
    if ratio >= 0.14 then return "#EAB308" end
    return "#EF4444"
end

local function pres_color(p)
    if p == nil then return C.dim end
    if p >= 80 and p <= 120 then return C.green end
    if p >= 50 and p <= 150 then return "#EAB308" end
    return "#EF4444"
end

local function fmt(v, d)
    if v == nil then return "--" end
    return string.format("%." .. (d or 1) .. "f", v)
end

local function pretty_slot_label(key)
    if not key or key == "" then
        return "SLOT"
    end
    return string.upper(string.gsub(tostring(key), "_", " "))
end

local function accent_for_label(label)
    return SLOT_ACCENTS[label] or C.accent
end

local function merge_loadout(name, payload)
    local prev = players[name]
    local oldLo = (prev and type(prev.loadout) == "table") and prev.loadout or nil
    if type(payload.loadout) == "table" then
        local n = 0
        for _ in pairs(payload.loadout) do
            n = n + 1
        end
        if n > 0 then
            return payload.loadout
        end
    end
    return oldLo
end

local function normalize_loadout_rows(raw)
    local byPin = {}
    if type(raw) == "table" then
        local nArray = #raw
        if nArray > 0 then
            for i = 1, nArray do
                local slot = raw[i]
                if type(slot) == "table" then
                    local p = tonumber(slot.pin)
                    if p ~= nil and p >= 0 and p <= 5 then
                        byPin[p] = slot
                    else
                        byPin[i - 1] = slot
                    end
                end
            end
        end
        if next(byPin) == nil then
            for k, slot in pairs(raw) do
                if type(slot) == "table" then
                    local p = tonumber(k)
                    if p ~= nil and p >= 0 and p <= 5 then
                        byPin[p] = slot
                    end
                end
            end
        end
    end

    local rows = {}
    for pin = 0, 5 do
        local slot = byPin[pin]
        if slot and type(slot) == "table" then
            if slot.label == nil and PIN_ORDER[pin + 1] then
                slot = {
                    pin      = pin,
                    label    = PIN_ORDER[pin + 1],
                    item     = slot.item or "",
                    detail   = slot.detail or "",
                    open     = slot.open,
                    open_str = slot.open_str,
                }
            end
            table.insert(rows, slot)
        else
            table.insert(rows, {
                pin    = pin,
                label  = PIN_ORDER[pin + 1],
                item   = "",
                detail = "No data (update SuitTelemetry.lua on suit).",
            })
        end
    end
    return rows
end

function on_telemetry(topic, payload, fromId, fromName, retained)
    if type(payload) ~= "table" or not payload.player then return end

    local name = payload.player
    if name == "" or name == "Unknown" then return end

    players[name] = {
        ext_pressure = payload.ext_pressure,
        ext_temp     = payload.ext_temp,
        int_pressure = payload.int_pressure,
        o2_ratio     = payload.o2_ratio,
        pos_x        = payload.pos_x,
        pos_y        = payload.pos_y,
        pos_z        = payload.pos_z,
        time         = game_time(),
        loadout      = merge_loadout(name, payload),
    }
end

ic.net.subscribe("suit/telemetry", "on_telemetry")

local render

local function go_main(_playerName)
    view = "main"
    selected_player = nil
    render()
end

local function go_loadout(player_name, _clicker)
    if not player_name or not players[player_name] then
        return
    end
    selected_player = player_name
    view = "loadout"
    render()
end

local function render_main()
    ui:clear()

    ui:element({
        id = "hdr",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = HEADER_H },
        style = { bg = C.header },
    })
    ui:element({
        id = "hdr_line",
        type = "panel",
        rect = { unit = "px", x = 0, y = HEADER_H - 2, w = W, h = 2 },
        style = { bg = C.cyan },
    })

    local plist = player_names_sorted()
    local nplay = #plist

    ui:element({
        id = "title",
        type = "label",
        rect = { unit = "px", x = 10, y = 6, w = W - 140, h = 18 },
        props = { text = "EVA SUIT TELEMETRY  ·  tap row → loadout" },
        style = { font_size = 12, color = C.cyan, align = "left" },
    })
    ui:element({
        id = "count",
        type = "label",
        rect = { unit = "px", x = W - 120, y = 8, w = 110, h = 14 },
        props = { text = tostring(nplay) .. " on net" },
        style = { font_size = 11, color = nplay > 0 and C.green or C.dim, align = "right" },
    })

    if nplay == 0 then
        ui:element({
            id = "empty",
            type = "label",
            rect = { unit = "px", x = 0, y = HEADER_H + LIST_H / 2 - 12, w = W, h = 24 },
            props = { text = "Waiting for suit telemetry…" },
            style = { font_size = 13, color = C.dim, align = "center" },
        })
        ui:commit()
        return
    end

    local rw = W - 4
    local sv = ui:element({
        id = "list_sv",
        type = "scrollview",
        rect = { unit = "px", x = 0, y = HEADER_H, w = W, h = LIST_H },
        style = { bg = C.bg },
    })

    for i, name in ipairs(plist) do
        local d = players[name]
        if d then
            local y0 = (i - 1) * ROW_H
            local rh = ROW_H - 2
            local stale = (game_time() - d.time) > 30
            local intCol = stale and C.stripe or pres_color(d.int_pressure)
            local subCol = stale and C.muted or C.dim
            local bg = stale and C.panel or (i % 2 == 0 and C.panel or C.panel_hi)

            local o2Val = d.o2_ratio and (d.o2_ratio * 100) or nil
            local line2 = string.format("INT %s kPa  ·  O2 %s%%  ·  EXT %s kPa @ %s K",
                fmt(d.int_pressure), fmt(o2Val, 0), fmt(d.ext_pressure), fmt(d.ext_temp, 0))
            local line3 = string.format("XYZ %.0f, %.0f, %.0f", d.pos_x or 0, d.pos_y or 0, d.pos_z or 0)

            local capture_name = name

            sv:element({
                id = "m_r" .. i .. "_bg",
                type = "panel",
                rect = { unit = "px", x = 0, y = y0, w = rw, h = rh },
                style = { bg = bg },
            })
            sv:element({
                id = "m_r" .. i .. "_st",
                type = "panel",
                rect = { unit = "px", x = 0, y = y0, w = 4, h = rh },
                style = { bg = intCol },
            })
            sv:element({
                id = "m_r" .. i .. "_nm",
                type = "label",
                rect = { unit = "px", x = 10, y = y0 + 4, w = rw - 96, h = 14 },
                props = { text = name },
                style = { font_size = 12, color = stale and C.dim or C.text, align = "left" },
            })
            sv:element({
                id = "m_r" .. i .. "_ln2",
                type = "label",
                rect = { unit = "px", x = 10, y = y0 + 19, w = rw - 16, h = 11 },
                props = { text = line2 },
                style = { font_size = 9, color = subCol, align = "left" },
            })
            sv:element({
                id = "m_r" .. i .. "_ln3",
                type = "label",
                rect = { unit = "px", x = 10, y = y0 + 30, w = rw - 16, h = 10 },
                props = { text = line3 },
                style = { font_size = 8, color = o2_color(d.o2_ratio), align = "left" },
            })
            sv:element({
                id = "m_r" .. i .. "_hint",
                type = "label",
                rect = { unit = "px", x = rw - 78, y = y0 + 12, w = 74, h = 14 },
                props = { text = "LOADOUT ›" },
                style = { font_size = 10, color = stale and C.muted or C.btn, align = "right" },
            })
            -- Clicks: last sibling on the row so raycast hits this first (MatchThree transparent style).
            sv:element({
                id = "m_r" .. i .. "_hit",
                type = "button",
                rect = { unit = "px", x = 0, y = y0, w = rw, h = rh },
                props = { text = " " },
                style = { bg = "#00000000", text = "#00000000", font_size = 8 },
                on_click = function(_pn)
                    go_loadout(capture_name)
                end,
            })
        end
    end

    local content_h = math.max(LIST_H, nplay * ROW_H + 8)
    sv:set_props({ content_height = tostring(content_h) })

    ui:commit()
end

local function render_loadout()
    ui:clear()

    local d = selected_player and players[selected_player] or nil

    ui:element({
        id = "hdr",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = HEADER_H },
        style = { bg = C.header },
    })
    ui:element({
        id = "hdr_line",
        type = "panel",
        rect = { unit = "px", x = 0, y = HEADER_H - 2, w = W, h = 2 },
        style = { bg = C.accent },
    })

    ui:element({
        id = "btn_back",
        type = "button",
        rect = { unit = "px", x = 6, y = 5, w = 58, h = 22 },
        props = { text = "← BACK" },
        style = { bg = C.panel_hi, text = C.text, font_size = 10 },
        on_click = go_main,
    })

    local title_text = "LOADOUT"
    local sub_text = ""
    if d and selected_player then
        title_text = selected_player
        local o2v = d.o2_ratio and (d.o2_ratio * 100) or nil
        sub_text = string.format("INT %s kPa  ·  O2 %s%%", fmt(d.int_pressure), fmt(o2v, 0))
    end

    ui:element({
        id = "lo_title",
        type = "label",
        rect = { unit = "px", x = 70, y = 5, w = W - 78, h = 14 },
        props = { text = title_text },
        style = { font_size = 13, color = C.text, align = "left" },
    })
    ui:element({
        id = "lo_sub",
        type = "label",
        rect = { unit = "px", x = 70, y = 19, w = W - 78, h = 12 },
        props = { text = sub_text },
        style = { font_size = 9, color = C.dim, align = "left" },
    })

    local body_top = HEADER_H
    local body_h = H - body_top
    local rows = normalize_loadout_rows(d and d.loadout or nil)

    local sv = ui:element({
        id = "lo_sv",
        type = "scrollview",
        rect = { unit = "px", x = 0, y = body_top, w = W, h = body_h },
        style = { bg = C.bg },
    })

    local cw = W - 12
    for j, slot in ipairs(rows) do
        local label = slot.label or ("pin_" .. tostring(slot.pin or j - 1))
        local accent = accent_for_label(label)
        local item_txt = (slot.item and slot.item ~= "") and slot.item or "- empty -"
        local det = slot.detail or ""

        local y0 = (j - 1) * CARD_H
        local ch = CARD_H - 4

        sv:element({
            id = "l_c" .. j .. "_bg",
            type = "panel",
            rect = { unit = "px", x = 4, y = y0, w = cw, h = ch },
            style = { bg = C.panel },
        })
        sv:element({
            id = "l_c" .. j .. "_ac",
            type = "panel",
            rect = { unit = "px", x = 4, y = y0, w = 5, h = ch },
            style = { bg = accent },
        })
        sv:element({
            id = "l_c" .. j .. "_sl",
            type = "label",
            rect = { unit = "px", x = 12, y = y0 + 4, w = cw - 10, h = 12 },
            props = { text = pretty_slot_label(label) },
            style = { font_size = 10, color = accent, align = "left" },
        })
        sv:element({
            id = "l_c" .. j .. "_it",
            type = "label",
            rect = { unit = "px", x = 12, y = y0 + 16, w = cw - 10, h = 14 },
            props = { text = item_txt },
            style = { font_size = 12, color = C.text, align = "left" },
        })
        sv:element({
            id = "l_c" .. j .. "_dt",
            type = "label",
            rect = { unit = "px", x = 12, y = y0 + 32, w = cw - 10, h = 18 },
            props = { text = det },
            style = { font_size = 9, color = C.dim, align = "left" },
        })
    end

    local lo_ch = math.max(body_h, #rows * CARD_H + 12)
    sv:set_props({ content_height = tostring(lo_ch) })

    ui:commit()
end

render = function()
    if view == "loadout" then
        render_loadout()
    else
        render_main()
    end
end

print("[SuitDashboard] suit/telemetry (flat scrollview rows, DeviceInspector-style)")
render()

function tick(dt)
    prune_stale()
    if view == "loadout" and selected_player and not players[selected_player] then
        go_main()
    end
    render()
    sleep(2)
end
