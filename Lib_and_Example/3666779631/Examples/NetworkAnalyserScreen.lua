-- NetworkAnalyserScreen.lua
-- ScriptedScreens example: Visual data-network device browser using device_list()
--
-- Shows all devices on the chip's data cable network in a scrollable list.
-- Click a row to select a device and see its live logic values on a detail panel.
-- Uses ic.net.network_id() to display cable-network Channel registers.
--
-- SETUP:
--   Insert a Lua chip into a ScriptedScreens motherboard in a Console/Computer.
--   No device pins need to be wired - the chip reads from the data network directly.
--   The console must be connected to the data cable network you want to inspect.

local LT = ic.enums.LogicType

-- ── Screen layout constants ───────────────────────────────────────────────────
local W, H = 480, 272
local ui = ss.ui.surface("main")
do
    local sz = ui:size()
    if sz then W, H = sz.w or W, sz.h or H end
end
ss.ui.activate("main")

local COL_W        = math.floor(W * 0.42) -- left column (device list)
local DETAIL_W     = W - COL_W - 2    -- right column (detail panel)
local HEADER_H     = 28
local FOOTER_H     = 24
local LIST_H       = H - HEADER_H - FOOTER_H

-- ── State ─────────────────────────────────────────────────────────────────────
local devices      = {}  -- array from device_list()
local selected_idx = nil -- index into devices[]
local scan_age     = 0   -- seconds since last scan
local SCAN_PERIOD  = 5   -- re-scan every 5 s

-- Logic types to probe on selected device
local PROBE_TYPES  = {
    { name = "On",          lt = LT.On },
    { name = "Power",       lt = LT.Power },
    { name = "Open",        lt = LT.Open },
    { name = "Temperature", lt = LT.Temperature },
    { name = "Pressure",    lt = LT.Pressure },
    { name = "Setting",     lt = LT.Setting },
    { name = "Mode",        lt = LT.Mode },
    { name = "Error",       lt = LT.Error },
    { name = "LineNumber",  lt = LT.LineNumber },
    { name = "Channel0",    lt = LT.Channel0 },
    { name = "Channel1",    lt = LT.Channel1 },
}

-- ── Safe id-based reads ───────────────────────────────────────────────────────
local function safe_read_id(ref_id, lt)
    if ref_id == nil or ref_id == 0 then return nil end
    local ok, v = pcall(read_id, ref_id, lt)
    return ok and v or nil
end

-- ── Scan the data network ─────────────────────────────────────────────────────
local function do_scan()
    devices = device_list() or {}
    -- If selected device is now out of range, deselect
    if selected_idx and selected_idx > #devices then
        selected_idx = nil
    end
    scan_age = 0
end

-- ── Format a logic value for display ─────────────────────────────────────────
local function fmt_value(v)
    if v == nil then return "--" end
    if v ~= v then return "NaN" end
    if math.abs(v) >= 1e6 then
        return string.format("%.2e", v)
    elseif math.floor(v) == v then
        return tostring(math.floor(v))
    else
        return string.format("%.3f", v)
    end
end

-- ── Forward-declare render so click handlers can call it ──────────────────────
local render

-- ── Render ────────────────────────────────────────────────────────────────────
render = function()
    ui:clear()

    -- Header bar
    ui:element({
        id = "hdr",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = HEADER_H },
        style = { bg = "#1A2A3A" },
    })
    ui:element({
        id = "hdr_title",
        type = "label",
        rect = { unit = "px", x = 8, y = 4, w = W - 160, h = 20 },
        props = { text = "Network Analyser  |  " .. #devices .. " devices" },
        style = { font_size = 13, color = "#88CCFF" },
    })
    ui:element({
        id = "hdr_age",
        type = "label",
        rect = { unit = "px", x = W - 150, y = 4, w = 86, h = 20 },
        props = { text = string.format("scan +%.0fs", scan_age) },
        style = { font_size = 11, color = "#556677", align = "right" },
    })
    ui:element({
        id = "btn_scan",
        type = "button",
        rect = { unit = "px", x = W - 56, y = 3, w = 52, h = 22 },
        props = { text = "Rescan" },
        style = { bg = "#1A3A5A", text = "#CCDDEE", font_size = 11 },
        on_click = function()
            do_scan()
            render()
        end,
    })

    -- Left column: device list (scrollview)
    local list_sv = ui:element({
        id = "list_sv",
        type = "scrollview",
        rect = { unit = "px", x = 0, y = HEADER_H, w = COL_W, h = LIST_H },
        style = { bg = "#0D1A28" },
    })

    local row_h = 36
    for i, d in ipairs(devices) do
        local bg = (i == selected_idx) and "#1A4060" or (i % 2 == 0 and "#0D1820" or "#0F1E2C")
        local pname = prefab_name(d.prefab_hash) or "unknown"
        local label = d.display_name ~= "" and d.display_name or "(unlabelled)"

        -- Row button (captures i via closure for selection)
        local row = list_sv:element({
            id = "row_" .. i,
            type = "button",
            rect = { unit = "px", x = 0, y = (i - 1) * row_h, w = COL_W - 2, h = row_h - 1 },
            style = { bg = bg, text = "#CCDDEE", font_size = 11 },
            on_click = function()
                selected_idx = i
                render()
            end,
        })

        -- Device display name
        row:element({
            id = "lbl_name",
            type = "label",
            rect = { unit = "px", x = 6, y = 2, w = COL_W - 12, h = 14 },
            props = { text = label },
            style = { font_size = 11, color = "#CCDDEE" },
        })

        -- Prefab name
        row:element({
            id = "lbl_pname",
            type = "label",
            rect = { unit = "px", x = 6, y = 18, w = COL_W - 12, h = 12 },
            props = { text = pname },
            style = { font_size = 10, color = "#446688" },
        })
    end

    -- Right column: detail panel background
    local dx = COL_W + 2
    ui:element({
        id = "detail_bg",
        type = "panel",
        rect = { unit = "px", x = dx, y = HEADER_H, w = DETAIL_W, h = LIST_H },
        style = { bg = "#0A1520" },
    })

    if selected_idx and devices[selected_idx] then
        local d = devices[selected_idx]
        local pname = prefab_name(d.prefab_hash) or ("hash:" .. d.prefab_hash)
        local label = d.display_name ~= "" and d.display_name or "(unlabelled)"

        -- Detail rows
        local ty = 4
        local row_idx = 0
        local function detail_row(title, value, col)
            row_idx = row_idx + 1
            ui:element({
                id = "dr_" .. row_idx,
                type = "label",
                rect = { unit = "px", x = dx + 6, y = HEADER_H + ty, w = DETAIL_W - 8, h = 13 },
                props = { text = title .. ": " .. tostring(value) },
                style = { font_size = 11, color = col or "#AABBCC" },
            })
            ty = ty + 15
        end

        detail_row("Name", label, "#88CCFF")
        detail_row("Prefab", pname, "#6699BB")
        detail_row("Ref ID", d.ref_id, "#446688")

        -- Separator
        ty = ty + 4
        ui:element({
            id = "sep",
            type = "panel",
            rect = { unit = "px", x = dx + 4, y = HEADER_H + ty, w = DETAIL_W - 8, h = 1 },
            style = { bg = "#1A3A5A" },
        })
        ty = ty + 6

        -- Probe logic values
        for _, probe in ipairs(PROBE_TYPES) do
            local v = safe_read_id(d.ref_id, probe.lt)
            if v ~= nil then
                detail_row(probe.name, fmt_value(v), "#88BBAA")
            end
        end
    else
        ui:element({
            id = "no_sel",
            type = "label",
            rect = { unit = "px", x = dx + 8, y = HEADER_H + LIST_H / 2 - 8, w = DETAIL_W - 16, h = 20 },
            props = { text = "Select a device to inspect" },
            style = { font_size = 12, color = "#334455", align = "center" },
        })
    end

    -- Footer: network channel registers
    local net_ref = ic.net.network_id()
    local ch_text = "Net: " .. (net_ref and ("id=" .. math.floor(net_ref)) or "none") .. "  "
    if net_ref then
        local channel_lts = { LT.Channel0, LT.Channel1, LT.Channel2, LT.Channel3 }
        for ci, ct in ipairs(channel_lts) do
            local v = safe_read_id(net_ref, ct) or 0
            ch_text = ch_text .. "Ch" .. (ci - 1) .. "=" .. fmt_value(v) .. "  "
        end
    end
    ui:element({
        id = "footer",
        type = "panel",
        rect = { unit = "px", x = 0, y = H - FOOTER_H, w = W, h = FOOTER_H },
        style = { bg = "#0D1520" },
    })
    ui:element({
        id = "footer_lbl",
        type = "label",
        rect = { unit = "px", x = 6, y = H - FOOTER_H + 5, w = W - 12, h = 14 },
        props = { text = ch_text },
        style = { font_size = 10, color = "#334455" },
    })

    ui:commit()
end

-- ── Init & tick loop ──────────────────────────────────────────────────────────
do_scan()
render()

while true do
    scan_age = scan_age + 1
    if scan_age >= SCAN_PERIOD then
        do_scan()
    end
    -- Re-render every tick to keep detail panel values live
    render()
    yield()
end
