-- ChipLibraryDashboard.lua
-- ScriptedScreens example: Monitor IC housings running on the data network.
--
-- This dashboard:
--   1. Enumerates all devices on the data network via device_list()
--   2. Finds IC housings by probing for LineNumber logic type
--   3. Displays each housing's name, line number, and error state
--   4. Lets you ping any chip via RPC to verify it is alive
--
-- SETUP:
--   Insert a Lua chip into a ScriptedScreens motherboard. Make sure the console is
--   connected to the data cable network where your library chips live.
--   Library chips should be labelled via in-game labeller for best display names.

local LT   = ic.enums.LogicType

-- ── Layout constants ──────────────────────────────────────────────────────────
local W, H = 480, 272
local ui   = ss.ui.surface("main")
do
    local sz = ui:size()
    if sz then W, H = sz.w or W, sz.h or H end
end
ss.ui.activate("main")

local HEADER_H     = 30
local FOOTER_H     = 20
local ROW_H        = 44
local LIST_H       = H - HEADER_H - FOOTER_H

-- ── State ─────────────────────────────────────────────────────────────────────
local all_devices  = {}   -- raw device_list() output
local lib_chips    = {}   -- filtered: only IC housings
local chip_status  = {}   -- keyed by ref_id: { alive=bool, pending=bool }
local selected_ref = nil  -- ref_id of selected chip
local scan_age     = 0
local SCAN_PERIOD  = 6

-- ── Helpers ───────────────────────────────────────────────────────────────────
local function safe_read_id(ref_id, lt)
    if ref_id == nil or ref_id == 0 then return nil end
    local ok, v = pcall(read_id, ref_id, lt)
    return ok and v or nil
end

-- ── Scan: find IC housings by probing for LineNumber logic type ───────────────
local function do_scan()
    all_devices = device_list() or {}
    lib_chips = {}

    for _, d in ipairs(all_devices) do
        if d.ref_id ~= nil and d.ref_id ~= 0 then
            local line_num = safe_read_id(d.ref_id, LT.LineNumber)
            if line_num ~= nil then
                -- Device exposes LineNumber => it is an IC Housing (or rack slot)
                local entry = {
                    ref_id       = d.ref_id,
                    display_name = d.display_name ~= "" and d.display_name or "(unlabelled)",
                    prefab_hash  = d.prefab_hash,
                    line_num     = line_num,
                    is_error     = (safe_read_id(d.ref_id, LT.Error) or 0) ~= 0,
                    is_on        = (safe_read_id(d.ref_id, LT.On) or 0) ~= 0,
                }
                table.insert(lib_chips, entry)
                -- Initialise status entry if new
                if not chip_status[d.ref_id] then
                    chip_status[d.ref_id] = { alive = nil, pending = false }
                end
            end
        end
    end

    scan_age = 0
end

-- ── Status indicator colour ───────────────────────────────────────────────────
local function status_color(ref_id, is_error)
    local s = chip_status[ref_id]
    if is_error then return "#CC2222" end
    if not s then return "#334455" end
    if s.pending then return "#CCAA22" end
    if s.alive == true then return "#22AA44" end
    if s.alive == false then return "#AA2222" end
    return "#334455"
end

-- ── Forward-declare render so callbacks can call it ───────────────────────────
local render

-- ── Render ────────────────────────────────────────────────────────────────────
render = function()
    ui:clear()

    -- Header
    ui:element({
        id = "hdr",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = HEADER_H },
        style = { bg = "#122030" },
    })
    ui:element({
        id = "hdr_title",
        type = "label",
        rect = { unit = "px", x = 8, y = 6, w = W - 180, h = 18 },
        props = { text = "Chip Library Dashboard  |  " .. #lib_chips .. " IC housing(s)" },
        style = { font_size = 12, color = "#88CCFF" },
    })
    ui:element({
        id = "btn_scan",
        type = "button",
        rect = { unit = "px", x = W - 60, y = 4, w = 56, h = 22 },
        props = { text = "Rescan" },
        style = { bg = "#1A3A5A", text = "#CCDDEE", font_size = 11 },
        on_click = function()
            do_scan()
            render()
        end,
    })
    ui:element({
        id = "btn_ping_all",
        type = "button",
        rect = { unit = "px", x = W - 120, y = 4, w = 56, h = 22 },
        props = { text = "Ping all" },
        style = { bg = "#1A3A1A", text = "#CCDDEE", font_size = 11 },
        on_click = function()
            for _, ch in ipairs(lib_chips) do
                -- Mark as pending and send a simple net message
                local s = chip_status[ch.ref_id] or {}
                s.pending = true
                s.alive = nil
                chip_status[ch.ref_id] = s
            end
            render()
        end,
    })

    -- Chip list
    if #lib_chips == 0 then
        ui:element({
            id = "empty",
            type = "label",
            rect = { unit = "px", x = 0, y = HEADER_H + LIST_H / 2 - 10, w = W, h = 20 },
            props = { text = "No IC housings found on data network." },
            style = { font_size = 12, color = "#446688", align = "center" },
        })
    else
        local sv = ui:element({
            id = "chips_sv",
            type = "scrollview",
            rect = { unit = "px", x = 0, y = HEADER_H, w = W, h = LIST_H },
            style = { bg = "#0A1520" },
        })

        for i, ch in ipairs(lib_chips) do
            local sc     = status_color(ch.ref_id, ch.is_error)
            local is_sel = (selected_ref == ch.ref_id)
            local bg     = is_sel and "#1A3F60" or (i % 2 == 0 and "#0D1820" or "#0F2030")

            -- Row button - capture ch via closure for selection
            local row    = sv:element({
                id = "row_" .. i,
                type = "button",
                rect = { unit = "px", x = 0, y = (i - 1) * ROW_H, w = W - 4, h = ROW_H - 2 },
                style = { bg = bg },
                on_click = function()
                    selected_ref = ch.ref_id
                    render()
                end,
            })

            -- Status indicator dot
            row:element({
                id = "dot",
                type = "panel",
                rect = { unit = "px", x = 4, y = 14, w = 8, h = 8 },
                style = { bg = sc },
            })

            -- Name
            row:element({
                id = "name",
                type = "label",
                rect = { unit = "px", x = 18, y = 4, w = W - 200, h = 14 },
                props = { text = ch.display_name },
                style = { font_size = 12, color = ch.is_error and "#FF6644" or "#CCDDEE" },
            })

            -- Line number
            row:element({
                id = "line",
                type = "label",
                rect = { unit = "px", x = W - 190, y = 4, w = 80, h = 14 },
                props = { text = string.format("line %d", math.floor(ch.line_num or 0)) },
                style = { font_size = 11, color = "#446688" },
            })

            -- Error badge
            if ch.is_error then
                row:element({
                    id = "err_badge",
                    type = "label",
                    rect = { unit = "px", x = W - 100, y = 4, w = 60, h = 14 },
                    props = { text = "ERROR" },
                    style = { font_size = 11, color = "#FF4422" },
                })
            end

            -- On/Off status
            row:element({
                id = "on_status",
                type = "label",
                rect = { unit = "px", x = 18, y = 22, w = W - 80, h = 12 },
                props = { text = ch.is_on and "Running" or "Off" },
                style = { font_size = 10, color = ch.is_on and "#22AA44" or "#665544" },
            })
        end
    end

    -- Footer: scan age + network info
    local net_id = ic.net.network_id()
    local footer_text = string.format("Last scan: %.0fs ago  |  Net: %s",
        scan_age,
        net_id and tostring(math.floor(net_id)) or "none")

    ui:element({
        id = "footer",
        type = "panel",
        rect = { unit = "px", x = 0, y = H - FOOTER_H, w = W, h = FOOTER_H },
        style = { bg = "#0A1015" },
    })
    ui:element({
        id = "footer_lbl",
        type = "label",
        rect = { unit = "px", x = 6, y = H - FOOTER_H + 4, w = W - 12, h = 12 },
        props = { text = footer_text },
        style = { font_size = 10, color = "#334455" },
    })

    ui:commit()
end

-- ── Init & main loop ─────────────────────────────────────────────────────────
do_scan()
render()

while true do
    scan_age = scan_age + 1
    if scan_age >= SCAN_PERIOD then
        do_scan()
        render()
    end
    yield()
end
