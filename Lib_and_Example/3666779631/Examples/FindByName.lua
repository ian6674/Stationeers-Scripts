-- FindByName - Device Lookup by Display Name
--
-- Demonstrates ic.find() and ic.find_all() for locating devices on the data
-- network by their Labeler-assigned name, without needing physical pin
-- connections (d0-d5).
--
-- HOW IT WORKS:
--   ic.find(name)     → returns the ReferenceId of the first matching device,
--                        or nil if none found.
--   ic.find_all(name) → returns a 1-indexed table of ALL matching ReferenceIds,
--                        or an empty table if none found.
--
--   The returned IDs work with ic.read_id() / ic.write_id() - the same
--   ID-based read/write functions used elsewhere in the Lua API.
--
-- SETUP:
--   1. Place devices on the same data cable network as the IC Housing.
--   2. Use a Labeler tool to name them (e.g. "Main Pump", "Hab Light").
--   3. Edit the DEVICES table below to match the names you've assigned.
--   4. Run the script - it will find each device and display live telemetry.
--
-- NOTE: Name matching is case-sensitive and uses the exact DisplayName.
--       If no device matches, the dashboard shows "NOT FOUND" for that entry.

-- ── Configuration ────────────────────────────────────────────────────────────
-- Edit these to match the Labeler names on your actual devices.
local DEVICES = {
    { name = "Main Pump",    label = "PUMP",    logic = "Setting" },
    { name = "Hab Light",    label = "LIGHT",   logic = "On" },
    { name = "Gas Sensor",   label = "SENSOR",  logic = "Temperature" },
    { name = "Wall Heater",  label = "HEATER",  logic = "On" },
}

-- How many seconds between each scan refresh
local REFRESH_INTERVAL = 1.0

-- ── Enums ────────────────────────────────────────────────────────────────────
local LT = ic.enums.LogicType

-- ── UI Setup ─────────────────────────────────────────────────────────────────
local ui = ss.ui.surface("main")
ss.ui.activate("main")

local size = ui:size()
local W, H = 480, 272
if size then W, H = size.w, size.h end

-- ── Build the UI ─────────────────────────────────────────────────────────────
ui:clear()

-- Background
ui:element({
    id = "bg", type = "panel",
    rect = { unit = "px", x = 0, y = 0, w = W, h = H },
    style = { bg = "#0F172A" },
})

-- Title bar
ui:element({
    id = "header", type = "panel",
    rect = { unit = "px", x = 0, y = 0, w = W, h = 32 },
    style = { bg = "#1E293B", gradient = "#0F172A", gradient_dir = "vertical" },
})

ui:element({
    id = "title", type = "label",
    rect = { unit = "px", x = 10, y = 4, w = W - 20, h = 24 },
    props = { text = "FIND BY NAME - DEVICE DASHBOARD" },
    style = { font_size = 13, color = "#22C55E", align = "left" },
})

ui:element({
    id = "status", type = "label",
    rect = { unit = "px", x = W - 160, y = 4, w = 150, h = 24 },
    props = { text = "SCANNING…" },
    style = { font_size = 11, color = "#64748B", align = "right" },
})

-- Separator
ui:element({
    id = "sep", type = "line",
    rect = { unit = "px", x = 0, y = 0, w = 0, h = 0 },
    props = { x1 = "10", y1 = "33", x2 = tostring(W - 10), y2 = "33" },
    style = { color = "#334155", thickness = "1" },
})

-- ── Device rows ──────────────────────────────────────────────────────────────
-- Each row: [LABEL]  [NAME]  [VALUE]  [STATUS]
local ROW_Y_START = 42
local ROW_H = 28
local ROW_GAP = 4

-- Create element rows for each device
local rows = {}
for i, dev in ipairs(DEVICES) do
    local y = ROW_Y_START + (i - 1) * (ROW_H + ROW_GAP)
    local prefix = "row_" .. i

    -- Row background (alternating)
    ui:element({
        id = prefix .. "_bg", type = "panel",
        rect = { unit = "px", x = 6, y = y, w = W - 12, h = ROW_H },
        style = { bg = (i % 2 == 0) and "#111827" or "#0F172A" },
    })

    -- Short label (left column)
    ui:element({
        id = prefix .. "_label", type = "label",
        rect = { unit = "px", x = 14, y = y + 2, w = 70, h = ROW_H - 4 },
        props = { text = dev.label },
        style = { font_size = 11, color = "#94A3B8", align = "left" },
    })

    -- Device name
    ui:element({
        id = prefix .. "_name", type = "label",
        rect = { unit = "px", x = 90, y = y + 2, w = 150, h = ROW_H - 4 },
        props = { text = dev.name },
        style = { font_size = 11, color = "#64748B", align = "left" },
    })

    -- Value (updated live)
    ui:element({
        id = prefix .. "_value", type = "label",
        rect = { unit = "px", x = 250, y = y + 2, w = 100, h = ROW_H - 4 },
        props = { text = "---" },
        style = { font_size = 12, color = "#E2E8F0", align = "right" },
    })

    -- Status indicator
    ui:element({
        id = prefix .. "_status", type = "label",
        rect = { unit = "px", x = 360, y = y + 2, w = 100, h = ROW_H - 4 },
        props = { text = "SEARCHING" },
        style = { font_size = 10, color = "#EAB308", align = "right" },
    })

    rows[i] = {
        prefix = prefix,
        ref_id = nil,    -- will be filled by find()
        dev = dev,
    }
end

-- ── "find_all" demo section ──────────────────────────────────────────────────
-- Shows how find_all returns multiple devices with the same name
local ALL_Y = ROW_Y_START + #DEVICES * (ROW_H + ROW_GAP) + 12

ui:element({
    id = "all_sep", type = "line",
    rect = { unit = "px", x = 0, y = 0, w = 0, h = 0 },
    props = { x1 = "10", y1 = tostring(ALL_Y), x2 = tostring(W - 10), y2 = tostring(ALL_Y) },
    style = { color = "#334155", thickness = "1" },
})

ui:element({
    id = "all_title", type = "label",
    rect = { unit = "px", x = 10, y = ALL_Y + 4, w = W - 20, h = 20 },
    props = { text = "find_all() DEMO - devices sharing the same name" },
    style = { font_size = 11, color = "#38BDF8", align = "left" },
})

ui:element({
    id = "all_result", type = "label",
    rect = { unit = "px", x = 10, y = ALL_Y + 26, w = W - 20, h = 40 },
    props = { text = "Searching for all \"" .. DEVICES[1].name .. "\"…" },
    style = { font_size = 10, color = "#94A3B8", align = "left" },
})

-- ── Usage hint at bottom ─────────────────────────────────────────────────────
ui:element({
    id = "hint", type = "label",
    rect = { unit = "px", x = 10, y = H - 24, w = W - 20, h = 20 },
    props = { text = "Name your devices with a Labeler • Names are case-sensitive" },
    style = { font_size = 9, color = "#475569", align = "center" },
})

ui:commit()

-- ── Main loop ────────────────────────────────────────────────────────────────
-- Periodically scan for devices by name and update the dashboard.
local scan_count = 0

while true do
    scan_count = scan_count + 1

    -- ── find() demo: locate each device by name ──────────────────────────────
    local found_count = 0
    for i, row in ipairs(rows) do
        local ref = ic.find(row.dev.name)
        row.ref_id = ref

        local val_handle = ui:get(row.prefix .. "_value")
        local status_handle = ui:get(row.prefix .. "_status")

        if ref then
            found_count = found_count + 1

            -- Read the configured logic type from the device
            local lt = LT[row.dev.logic]
            local ok, value = pcall(ic.read_id, ref, lt)

            if ok and value ~= nil then
                -- Format the value nicely
                local display
                if row.dev.logic == "On" then
                    display = (value ~= 0) and "ON" or "OFF"
                elseif row.dev.logic == "Temperature" then
                    display = string.format("%.1f K", value)
                elseif row.dev.logic == "Setting" then
                    display = string.format("%.1f", value)
                else
                    display = tostring(value)
                end

                val_handle:set_props({ text = display })
                status_handle:set_props({ text = "ONLINE" })
                status_handle:set_style({ color = "#22C55E" })
            else
                val_handle:set_props({ text = "ERR" })
                status_handle:set_props({ text = "READ FAIL" })
                status_handle:set_style({ color = "#EF4444" })
            end
        else
            val_handle:set_props({ text = "---" })
            status_handle:set_props({ text = "NOT FOUND" })
            status_handle:set_style({ color = "#EF4444" })
        end
    end

    -- ── find_all() demo: show all devices matching the first name ────────────
    local all_ids = ic.find_all(DEVICES[1].name)
    local all_text
    if #all_ids == 0 then
        all_text = "No devices named \"" .. DEVICES[1].name .. "\" found on network."
    elseif #all_ids == 1 then
        all_text = "1 device found: ID " .. tostring(all_ids[1])
    else
        local id_strs = {}
        for _, id in ipairs(all_ids) do
            id_strs[#id_strs + 1] = tostring(id)
        end
        all_text = #all_ids .. " devices found: IDs " .. table.concat(id_strs, ", ")
    end
    ui:get("all_result"):set_props({ text = all_text })

    -- ── Write example: toggle a device ───────────────────────────────────────
    -- Uncomment the block below to toggle "Hab Light" on/off every scan cycle:
    --
    -- local light_id = ic.find("Hab Light")
    -- if light_id then
    --     local current = ic.read_id(light_id, LT.On)
    --     if current ~= nil then
    --         ic.write_id(light_id, LT.On, (current ~= 0) and 0 or 1)
    --     end
    -- end

    -- Update status bar
    local status_text = found_count .. "/" .. #DEVICES .. " found  •  scan #" .. scan_count
    ui:get("status"):set_props({ text = status_text })

    ui:commit()
    sleep(REFRESH_INTERVAL)
end
