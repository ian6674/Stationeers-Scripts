-- LiveDashboard.lua
-- Animated station monitoring dashboard using charts, gauges, tables, and layouts.
-- Updates every tick with simulated sensor data to demonstrate live widget updates.
-- No external dependencies - runs entirely self-contained.

local ui = ss.ui.surface("main")
ss.ui.activate("main")

local size = ui:size()
local W, H = 480, 272
if size then W, H = size.w, size.h end

-- ── Simulation state ──────────────────────────────────────────────────
local tick = 0
local HISTORY_LEN = 40

-- Rolling history buffers
local tempHistory = {}
local pressHistory = {}
local powerHistory = {}
local loadHistory = {}

for i = 1, HISTORY_LEN do
    tempHistory[i] = 21.0
    pressHistory[i] = 101.3
    powerHistory[i] = 500
    loadHistory[i] = 400
end

-- Zone data for the table
local zones = {
    { name = "HAB-1",    temp = 21.0, press = 101.3, status = "OK" },
    { name = "HAB-2",    temp = 20.5, press = 100.8, status = "OK" },
    { name = "AIRLOCK",  temp = 15.2, press = 95.0,  status = "WARN" },
    { name = "WORKSHOP", temp = 23.1, press = 102.0, status = "OK" },
    { name = "MEDBAY",   temp = 22.0, press = 101.0, status = "OK" },
    { name = "STORAGE",  temp = 18.0, press = 99.5,  status = "OK" },
}

local selectedZone = 1
local sortCol = 1
local sortAsc = true

-- ── Helper: push value into rolling buffer ────────────────────────────
local function pushHistory(buf, val)
    table.remove(buf, 1)
    buf[#buf + 1] = val
end

-- ── Helper: sort zones ────────────────────────────────────────────────
local function sortZones()
    table.sort(zones, function(a, b)
        local va, vb
        if sortCol == 1 then
            va, vb = a.name, b.name
        elseif sortCol == 2 then
            va, vb = a.temp, b.temp
        elseif sortCol == 3 then
            va, vb = a.press, b.press
        else
            va, vb = a.status, b.status
        end
        if sortAsc then return va < vb else return va > vb end
    end)
end

-- ── Helper: build table rows array ────────────────────────────────────
local function buildRows()
    local rows = {}
    for i, z in ipairs(zones) do
        local statusColor = "#22C55E"
        if z.status == "WARN" then
            statusColor = "#F59E0B"
        elseif z.status == "ALERT" then
            statusColor = "#EF4444"
        end

        rows[i] = {
            z.name,
            string.format("%.1f", z.temp),
            string.format("%.1f", z.press),
            { text = z.status, style = { color = statusColor } }
        }
    end
    return rows
end

-- ══════════════════════════════════════════════════════════════════════
-- MAIN LOOP
-- ══════════════════════════════════════════════════════════════════════
while true do
    tick = tick + 1
    local t = tick * 0.05

    -- Simulate sensor drift
    local simTemp = 21.0 + math.sin(t) * 2.5 + math.cos(t * 1.7) * 1.0
    local simPress = 101.3 + math.sin(t * 0.6) * 3.0 + math.cos(t * 1.3) * 1.5
    local simPower = 800 + math.sin(t * 0.4) * 350
    local simLoad = 550 + math.cos(t * 0.55) * 200 + math.sin(t * 1.2) * 50

    pushHistory(tempHistory, simTemp)
    pushHistory(pressHistory, simPress)
    pushHistory(powerHistory, simPower)
    pushHistory(loadHistory, simLoad)

    -- Update zone data with small variations
    for i, z in ipairs(zones) do
        z.temp = z.temp + (math.random() - 0.5) * 0.4
        z.press = z.press + (math.random() - 0.5) * 0.2
        if z.temp > 28 or z.press < 90 then
            z.status = "ALERT"
        elseif z.temp > 25 or z.press < 95 then
            z.status = "WARN"
        else
            z.status = "OK"
        end
    end

    sortZones()

    -- ── Rebuild UI ────────────────────────────────────────────────────
    ui:clear()

    -- Slowly varying atmosphere
    local o2 = 20.9 + math.sin(t * 0.3) * 0.5
    local n2 = 78.1 + math.cos(t * 0.2) * 0.3
    local co2 = 0.04 + math.sin(t * 0.8) * 0.02
    local h2o = 0.9 + math.cos(t * 0.5) * 0.3

    -- Background
    ui:element({
        id = "bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = H },
        style = { bg = "#0B1120" }
    })

    -- ── Full-screen nested layout ────────────────────────────────────
    ui:layout({
        layout = "flex",
        rect = { unit = "px", x = 0, y = 0, w = W, h = H },
        direction = "column",
        gap = 0,
        children = {
            -- ── Header bar ───────────────────────────────────────────
            {
                id = "hdr_bg",
                type = "panel",
                rect = { h = 22 },
                style = { bg = "#1E293B" },
                layout = "flex",
                direction = "row",
                gap = 0,
                padding = { left = 8, right = 8 },
                children = {
                    {
                        id = "hdr_title",
                        type = "label",
                        flex = 1,
                        props = { text = "STATION MONITOR" },
                        style = { font_size = 12, color = "#22C55E" }
                    },
                    {
                        id = "hdr_tick",
                        type = "label",
                        rect = { w = 82 },
                        props = { text = "T+" .. tostring(tick) },
                        style = { font_size = 10, color = "#475569", align = "right" }
                    },
                }
            },

            -- ── Row 1: Gauges (left) + Sparklines (right) ───────────
            {
                layout = "flex",
                rect = { h = 66 },
                direction = "row",
                gap = 8,
                padding = { left = 6, right = 6, top = 4 },
                children = {
                    -- Two gauges side by side
                    {
                        layout = "flex",
                        rect = { w = 184 },
                        direction = "row",
                        gap = 4,
                        children = {
                            {
                                id = "g_temp",
                                type = "gauge",
                                flex = 1,
                                props = {
                                    value = string.format("%.1f", simTemp),
                                    min = "-10",
                                    max = "50",
                                    warn = "0.65",
                                    danger = "0.85",
                                    label = "TEMP",
                                    unit = " C"
                                },
                                style = {
                                    bg = "#111827",
                                    arc_thickness = "6",
                                    font_size = "9",
                                    value_color = "#E2E8F0",
                                    label_color = "#64748B"
                                }
                            },
                            {
                                id = "g_press",
                                type = "gauge",
                                flex = 1,
                                props = {
                                    value = string.format("%.1f", simPress),
                                    min = "0",
                                    max = "200",
                                    warn = "0.6",
                                    danger = "0.8",
                                    label = "PRESS",
                                    unit = " kPa"
                                },
                                style = {
                                    bg = "#111827",
                                    arc_thickness = "6",
                                    font_size = "9",
                                    value_color = "#E2E8F0",
                                    label_color = "#64748B"
                                }
                            },
                        }
                    },

                    -- Sparkline stack (temp + pressure history)
                    {
                        layout = "flex",
                        flex = 1,
                        direction = "column",
                        gap = 2,
                        children = {
                            {
                                id = "lbl_temp_hist",
                                type = "label",
                                rect = { h = 12 },
                                props = { text = "TEMPERATURE HISTORY" },
                                style = { font_size = 8, color = "#64748B" }
                            },
                            {
                                id = "spark_temp",
                                type = "sparkline",
                                flex = 1,
                                props = { data = tempHistory, min = 10, max = 35 },
                                style = {
                                    bg = "#111827",
                                    line_color = "#F59E0B",
                                    fill_color = "#F59E0B15",
                                    thickness = "1.5"
                                }
                            },
                            {
                                id = "lbl_press_hist",
                                type = "label",
                                rect = { h = 12 },
                                props = { text = "PRESSURE HISTORY" },
                                style = { font_size = 8, color = "#64748B" }
                            },
                            {
                                id = "spark_press",
                                type = "sparkline",
                                flex = 1,
                                props = { data = pressHistory, min = 85, max = 115 },
                                style = {
                                    bg = "#111827",
                                    line_color = "#3B82F6",
                                    fill_color = "#3B82F615",
                                    thickness = "1.5"
                                }
                            },
                        }
                    },
                }
            },

            -- ── Row 2: Power chart (left) + Zone table (right) ──────
            {
                layout = "flex",
                flex = 1,
                direction = "row",
                gap = 6,
                padding = { left = 6, right = 6, top = 4 },
                children = {
                    -- Power chart column
                    {
                        layout = "flex",
                        flex = 1,
                        direction = "column",
                        gap = 2,
                        children = {
                            {
                                id = "lbl_power",
                                type = "label",
                                rect = { h = 12 },
                                props = { text = "POWER (W)" },
                                style = { font_size = 8, color = "#64748B" }
                            },
                            {
                                id = "power_chart",
                                type = "linechart",
                                flex = 1,
                                props = {
                                    series = { powerHistory, loadHistory },
                                    series_colors = { "#22C55E", "#EF4444" },
                                    series_labels = { "Generated", "Load" },
                                },
                                style = {
                                    bg = "#111827",
                                    show_grid = "true",
                                    show_legend = "true",
                                    fill = "true",
                                    thickness = "1.5",
                                    font_size = "7"
                                }
                            },
                        }
                    },

                    -- Zone table column
                    {
                        layout = "flex",
                        flex = 1,
                        direction = "column",
                        gap = 2,
                        children = {
                            {
                                id = "lbl_zones",
                                type = "label",
                                rect = { h = 12 },
                                props = { text = "ZONE STATUS" },
                                style = { font_size = 8, color = "#64748B" }
                            },
                            {
                                id = "zone_tbl",
                                type = "table",
                                flex = 1,
                                props = {
                                    columns = { "Zone", "Temp", "Press", "Status" },
                                    rows = buildRows(),
                                    col_widths = { 2, 1, 1, 1 },
                                    selected_row = selectedZone,
                                    sort_column = sortCol,
                                    sort_dir = sortAsc and "asc" or "desc",
                                },
                                style = {
                                    header_bg = "#1E293B",
                                    header_color = "#94A3B8",
                                    row_bg = "#111827",
                                    alt_row_bg = "#0F172A",
                                    row_color = "#E2E8F0",
                                    selected_bg = "#1E3A5F",
                                    selected_color = "#67E8F9",
                                    font_size = "8",
                                    row_height = "14",
                                    header_font_size = "8",
                                },
                                on_click = function(value, playerName)
                                    selectedZone = tonumber(value) or 1
                                end,
                                on_change = function(value, playerName)
                                    local col = tonumber(value) or 1
                                    if col == sortCol then
                                        sortAsc = not sortAsc
                                    else
                                        sortCol = col
                                        sortAsc = true
                                    end
                                end,
                            },
                        }
                    },
                }
            },

            -- ── Bottom: atmospheric composition bar chart ────────────
            {
                layout = "flex",
                rect = { h = 56 },
                direction = "column",
                gap = 2,
                padding = { left = 6, right = 6, bottom = 2 },
                children = {
                    {
                        id = "lbl_atmos",
                        type = "label",
                        rect = { h = 12 },
                        props = { text = "ATMOSPHERIC COMPOSITION (%)" },
                        style = { font_size = 8, color = "#64748B" }
                    },
                    {
                        id = "atmos_bar",
                        type = "barchart",
                        flex = 1,
                        props = {
                            labels = { "Oxygen", "Nitrogen", "CO2", "Water" },
                            values = { o2, n2, co2, h2o },
                            colors = { "#3B82F6", "#6366F1", "#EF4444", "#06B6D4" },
                            max = 100,
                        },
                        style = {
                            bg = "#111827",
                            font_size = "7",
                            gap = "6",
                            show_values = "true",
                            value_color = "#94A3B8"
                        }
                    },
                }
            },
        }
    })

    ui:commit()
    coroutine.yield()
end
