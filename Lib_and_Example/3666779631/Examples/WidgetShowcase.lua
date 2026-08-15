-- WidgetShowcase.lua
-- Demonstrates every ScriptedScreens chart, table, and layout widget on a single screen.
-- Uses the nested ui:layout() system - no manual pixel positioning needed.

local ui = ss.ui.surface("main")
ss.ui.activate("main")

local size = ui:size()
local W, H = 480, 272
if size then W, H = size.w, size.h end

ui:clear()

-- ── State for interactive widgets ────────────────────────────────────
local time = 0
local updateAccumulator = 0
local selected_row = 1
local sort_column = 1
local sort_dir = "asc"

local status_order = {
    ONLINE = 1,
    STANDBY = 2,
    WARNING = 3,
    ALERT = 4,
}

local table_rows = {
    { system = "Life Support", status = "ONLINE",  load = 42, trend = { 28, 32, 36, 38, 40, 42 } },
    { system = "Power Grid",   status = "ONLINE",  load = 78, trend = { 60, 64, 70, 74, 77, 78 } },
    { system = "Comms Array",  status = "STANDBY", load = 12, trend = { 10, 12, 11, 13, 12, 12 } },
    { system = "Thermal Ctrl", status = "WARNING", load = 91, trend = { 80, 84, 88, 90, 92, 91 } },
}

local function build_rows()
    local rows = {}
    for i, row in ipairs(table_rows) do
        rows[i] = {
            row.system,
            row.status,
            string.format("%.0f%%", row.load),
            {
                type = "sparkline",
                props = {
                    data = row.trend,
                    min = 0,
                    max = 100,
                },
                style = {
                    bg = "#0F172A",
                    line_color = "#38BDF8",
                    fill_color = "#38BDF820",
                    thickness = 1,
                }
            }
        }
    end
    return rows
end

local function sort_rows()
    table.sort(table_rows, function(a, b)
        if sort_column == 1 then -- System
            if sort_dir == "asc" then return a.system < b.system else return a.system > b.system end
        end
        if sort_column == 2 then -- Status
            local a_val = status_order[a.status] or 99
            local b_val = status_order[b.status] or 99
            if sort_dir == "asc" then return a_val < b_val else return a_val > b_val end
        end
        -- Load (column 3) or fallback
        if sort_dir == "asc" then return a.load < b.load else return a.load > b.load end
    end)
end

-- ── Data for charts ──────────────────────────────────────────────────
local tempHistory = {}
for i = 1, 30 do
    tempHistory[i] = 20 + math.sin(i * 0.3) * 4 + math.cos(i * 0.17) * 2
end

local prodSeries = {}
local consSeries = {}
for i = 1, 12 do
    prodSeries[i] = 800 + math.sin(i * 0.5) * 300 + math.cos(i * 0.3) * 150
    consSeries[i] = 600 + math.cos(i * 0.4) * 200 + math.sin(i * 0.6) * 100
end

sort_rows()

-- ── Background ────────────────────────────────────────────────────────
ui:element({
    id = "bg",
    type = "panel",
    rect = { unit = "px", x = 0, y = 0, w = W, h = H },
    style = { bg = "#0B1120" }
})

-- ── Entire screen laid out with nested flex ──────────────────────────
-- The root is a vertical flex: title bar + content area.
-- The content area is a horizontal flex: left column + right column.
-- Each column is a vertical flex containing section labels and widgets.

local h = ui:layout({
    layout = "flex",
    rect = { unit = "px", x = 0, y = 0, w = W, h = H },
    direction = "column",
    gap = 0,
    children = {
        -- ── Title bar ────────────────────────────────────────────────
        {
            id = "title_bg",
            type = "panel",
            rect = { h = 24 },
            style = { bg = "#1E293B" },
            layout = "flex",
            direction = "row",
            gap = 0,
            padding = { left = 8, right = 8 },
            children = {
                {
                    id = "title",
                    type = "label",
                    flex = 1,
                    props = { text = "WIDGET SHOWCASE" },
                    style = { font_size = 13, color = "#22C55E", align = "left" }
                },
                {
                    id = "title_ver",
                    type = "label",
                    rect = { w = 92 },
                    props = { text = "ScriptedScreens" },
                    style = { font_size = 9, color = "#475569", align = "right" }
                },
            }
        },

        -- ── Content area: two columns ────────────────────────────────
        {
            layout = "flex",
            flex = 1,
            direction = "row",
            gap = 8,
            padding = 6,
            children = {
                -- ── Left column: sparkline, bar chart, gauges ────────────
                {
                    layout = "flex",
                    flex = 1,
                    direction = "column",
                    gap = 4,
                    children = {
                        {
                            id = "lbl_sparkline",
                            type = "label",
                            rect = { h = 14 },
                            props = { text = "SPARKLINE" },
                            style = { font_size = 9, color = "#64748B" }
                        },

                        {
                            id = "spark1",
                            type = "sparkline",
                            rect = { h = 56 },
                            props = {
                                data = tempHistory,
                                min = 14,
                                max = 28,
                            },
                            style = {
                                bg = "#111827",
                                line_color = "#22C55E",
                                fill_color = "#22C55E18",
                                thickness = "2"
                            }
                        },

                        {
                            id = "lbl_barchart",
                            type = "label",
                            rect = { h = 14 },
                            props = { text = "BAR CHART" },
                            style = { font_size = 9, color = "#64748B" }
                        },

                        {
                            id = "bars1",
                            type = "barchart",
                            rect = { h = 56 },
                            props = {
                                labels = { "O2", "N2", "CO2", "H2O", "VOL" },
                                values = { 21.1, 78.1, 0.04, 1.2, 0.3 },
                                colors = { "#3B82F6", "#6366F1", "#EF4444", "#06B6D4", "#F59E0B" },
                                max = 100,
                            },
                            style = {
                                bg = "#111827",
                                font_size = "8",
                                gap = "3",
                                show_values = "true",
                                value_color = "#94A3B8"
                            }
                        },

                        {
                            id = "lbl_gauge",
                            type = "label",
                            rect = { h = 14 },
                            props = { text = "GAUGE" },
                            style = { font_size = 9, color = "#64748B" }
                        },

                        -- Gauge pair in a horizontal flex row
                        {
                            layout = "flex",
                            rect = { h = 62 },
                            direction = "row",
                            gap = 8,
                            children = {
                                {
                                    id = "gauge1",
                                    type = "gauge",
                                    flex = 1,
                                    props = {
                                        value = "101.3",
                                        min = "0",
                                        max = "200",
                                        warn = "0.65",
                                        danger = "0.85",
                                        label = "PRESSURE",
                                        unit = " kPa"
                                    },
                                    style = {
                                        bg = "#111827",
                                        arc_thickness = "7",
                                        font_size = "10",
                                        value_color = "#E2E8F0",
                                        label_color = "#64748B"
                                    }
                                },

                                {
                                    id = "gauge2",
                                    type = "gauge",
                                    flex = 1,
                                    props = {
                                        value = "22.4",
                                        min = "-20",
                                        max = "60",
                                        warn = "0.7",
                                        danger = "0.9",
                                        label = "TEMP",
                                        unit = " C"
                                    },
                                    style = {
                                        bg = "#111827",
                                        arc_thickness = "7",
                                        font_size = "10",
                                        value_color = "#E2E8F0",
                                        label_color = "#64748B",
                                        normal_color = "#22C55E80",
                                        warn_color = "#EAB30880",
                                        danger_color = "#EF444480"
                                    }
                                },
                            }
                        },
                    }
                },

                -- ── Right column: line chart + table ─────────────────────
                {
                    layout = "flex",
                    flex = 1,
                    direction = "column",
                    gap = 4,
                    children = {
                        {
                            id = "lbl_linechart",
                            type = "label",
                            rect = { h = 14 },
                            props = { text = "LINE CHART (multi-series)" },
                            style = { font_size = 9, color = "#64748B" }
                        },

                        {
                            id = "line1",
                            type = "linechart",
                            flex = 2,
                            props = {
                                series = { prodSeries, consSeries },
                                series_colors = { "#3B82F6", "#EF4444" },
                                series_labels = { "Produced", "Consumed" },
                                x_labels = { "1h", "3h", "6h", "9h", "12h" },
                            },
                            style = {
                                bg = "#111827",
                                show_grid = "true",
                                show_legend = "true",
                                fill = "true",
                                thickness = "2",
                                font_size = "8"
                            }
                        },

                        {
                            id = "lbl_table",
                            type = "label",
                            rect = { h = 14 },
                            props = { text = "TABLE (sortable + selectable)" },
                            style = { font_size = 9, color = "#64748B" }
                        },

                        {
                            id = "tbl1",
                            type = "table",
                            flex = 1,
                            props = {
                                columns = { "System", "Status", "Load", "Trend" },
                                rows = build_rows(),
                                col_widths = { 2, 1, 1, 1 },
                                selected_row = 1,
                                sort_column = 1,
                                sort_dir = "asc",
                            },
                            style = {
                                header_bg = "#1E293B",
                                header_color = "#94A3B8",
                                row_bg = "#111827",
                                alt_row_bg = "#0F172A",
                                row_color = "#E2E8F0",
                                selected_bg = "#1E3A5F",
                                selected_color = "#67E8F9",
                                font_size = "9",
                                row_height = "17",
                            },
                            on_click = function(value, playerName)
                                local row = tonumber(value) or 0
                                if row >= 1 then
                                    selected_row = row
                                    if h and h.tbl1 then
                                        h.tbl1:set_props({ selected_row = selected_row })
                                    end
                                    ui:commit()
                                end
                            end,
                            on_change = function(value, playerName)
                                local col = tonumber(value) or 1
                                if col == sort_column then
                                    sort_dir = (sort_dir == "asc") and "desc" or "asc"
                                else
                                    sort_column = col
                                    sort_dir = "asc"
                                end
                                sort_rows()
                                if h and h.tbl1 then
                                    h.tbl1:set_props({
                                        rows = build_rows(),
                                        sort_column = sort_column,
                                        sort_dir = sort_dir,
                                    })
                                end
                                ui:commit()
                            end,
                        },
                    }
                },
            }
        },
    }
})

ui:commit()

-- ── Live updates for graphs ──────────────────────────────────────────
local bar_base = { 21.1, 78.1, 0.04, 1.2, 0.3 }

local function update_graphs(dt)
    time = time + dt
    updateAccumulator = updateAccumulator + dt
    if updateAccumulator < 0.5 then return end
    updateAccumulator = 0

    -- Sparkline: shift data window
    local temp_val = 20 + math.sin(time * 0.7) * 4 + math.cos(time * 0.4) * 2
    table.remove(tempHistory, 1)
    tempHistory[#tempHistory + 1] = temp_val
    if h and h.spark1 then
        h.spark1:set_props({ data = tempHistory })
    end

    -- Bar chart: oscillate values
    local bar_values = {}
    for i = 1, #bar_base do
        bar_values[i] = bar_base[i] + math.sin(time * 0.5 + i) * 0.6
    end
    if h and h.bars1 then
        h.bars1:set_props({ values = bar_values })
    end

    -- Gauges: animate needle
    if h and h.gauge1 then
        h.gauge1:set_props({ value = string.format("%.1f", 100 + math.sin(time * 0.6) * 30) })
    end
    if h and h.gauge2 then
        h.gauge2:set_props({ value = string.format("%.1f", 22 + math.cos(time * 0.4) * 6) })
    end

    -- Line chart: shift series window
    table.remove(prodSeries, 1)
    table.remove(consSeries, 1)
    prodSeries[#prodSeries + 1] = 800 + math.sin(time * 0.5) * 300 + math.cos(time * 0.3) * 150
    consSeries[#consSeries + 1] = 600 + math.cos(time * 0.4) * 200 + math.sin(time * 0.6) * 100
    if h and h.line1 then
        h.line1:set_props({
            series = { prodSeries, consSeries },
        })
    end

    -- Table trend sparklines: update per-row history
    for i, row in ipairs(table_rows) do
        row.base = row.base or row.load
        local target = row.base + math.sin(time * 0.6 + i) * 4 + math.cos(time * 0.3 + i) * 2
        local next_val = math.max(0, math.min(100, target))
        row.load = next_val
        if row.trend then
            table.remove(row.trend, 1)
            row.trend[#row.trend + 1] = next_val
        end
    end
    sort_rows()
    if h and h.tbl1 then
        h.tbl1:set_props({
            rows = build_rows(),
            selected_row = selected_row,
            sort_column = sort_column,
            sort_dir = sort_dir,
        })
    end

    ui:commit()
end

function tick(dt)
    update_graphs(dt)
end
