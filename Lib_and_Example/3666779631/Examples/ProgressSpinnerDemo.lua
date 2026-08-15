-- ProgressSpinnerDemo.lua
-- Demonstrates progress bar features (color_stops, indeterminate mode, gradient
-- fills) and the spinner element. Simulates loading states and live-updating
-- values to show all the new UI primitives in action.

local ui = ss.ui.surface("main")
ss.ui.activate("main")

local size = ui:size()
local W, H = 480, 272
if size then W, H = size.w, size.h end

ui:clear()

-- ── Background ──────────────────────────────────────────────────────
ui:element({
    id = "bg",
    type = "panel",
    rect = { unit = "px", x = 0, y = 0, w = W, h = H },
    style = {
        gradient = { "#0F172A", "#1E293B" },
        gradient_dir = "vertical",
    },
})

-- ── Title ───────────────────────────────────────────────────────────
ui:element({
    id = "title",
    type = "label",
    rect = { unit = "px", x = 10, y = 4, w = W - 20, h = 20 },
    props = { text = "PROGRESS & SPINNER DEMO" },
    style = { font_size = 14, color = "#94A3B8", align = "center" },
})

-- ═══════════════════════════════════════════════════════════════════
-- Section 1: Basic progress bar
-- ═══════════════════════════════════════════════════════════════════
local y = 30

ui:element({
    id = "lbl_basic",
    type = "label",
    rect = { unit = "px", x = 10, y = y, w = 200, h = 14 },
    props = { text = "Basic progress bar" },
    style = { font_size = 10, color = "#64748B" },
})

ui:element({
    id = "bar_basic",
    type = "progress",
    rect = { unit = "px", x = 10, y = y + 16, w = W - 20, h = 14 },
    props = { value = 0.65 },
    style = { bg = "#1E293B", fill = "#3B82F6" },
})

-- ═══════════════════════════════════════════════════════════════════
-- Section 2: Progress bar with color_stops
-- ═══════════════════════════════════════════════════════════════════
y = y + 40

ui:element({
    id = "lbl_stops",
    type = "label",
    rect = { unit = "px", x = 10, y = y, w = 300, h = 14 },
    props = { text = "Color stops (green → yellow → red)" },
    style = { font_size = 10, color = "#64748B" },
})

-- We'll animate this one in the tick loop
ui:element({
    id = "bar_stops",
    type = "progress",
    rect = { unit = "px", x = 10, y = y + 16, w = W - 80, h = 14 },
    props = { value = 0.3 },
    style = {
        bg = "#1E293B",
        fill = "#22C55E",
        color_stops = {
            { 0,   "#22C55E" }, -- green: 0-50%
            { 0.5, "#EAB308" }, -- yellow: 50-80%
            { 0.8, "#EF4444" }, -- red: 80-100%
        },
    },
})

ui:element({
    id = "bar_stops_val",
    type = "label",
    rect = { unit = "px", x = W - 65, y = y + 16, w = 55, h = 14 },
    props = { text = "30%" },
    style = { font_size = 11, color = "#E2E8F0", align = "right" },
})

-- ═══════════════════════════════════════════════════════════════════
-- Section 3: Progress bar with gradient fill
-- ═══════════════════════════════════════════════════════════════════
y = y + 40

ui:element({
    id = "lbl_grad",
    type = "label",
    rect = { unit = "px", x = 10, y = y, w = 300, h = 14 },
    props = { text = "Gradient fill (horizontal)" },
    style = { font_size = 10, color = "#64748B" },
})

ui:element({
    id = "bar_grad",
    type = "progress",
    rect = { unit = "px", x = 10, y = y + 16, w = W - 20, h = 14 },
    props = { value = 0.85 },
    style = {
        bg = "#1E293B",
        fill = "#3B82F6",
        gradient = "#8B5CF6",
        gradient_dir = "horizontal",
    },
})

-- ═══════════════════════════════════════════════════════════════════
-- Section 4: Indeterminate progress bars
-- ═══════════════════════════════════════════════════════════════════
y = y + 40

ui:element({
    id = "lbl_indet",
    type = "label",
    rect = { unit = "px", x = 10, y = y, w = 300, h = 14 },
    props = { text = "Indeterminate (loading animation)" },
    style = { font_size = 10, color = "#64748B" },
})

ui:element({
    id = "bar_indet1",
    type = "progress",
    rect = { unit = "px", x = 10, y = y + 16, w = (W - 30) / 2, h = 8 },
    props = { indeterminate = true },
    style = { bg = "#1E293B", fill = "#38BDF8" },
})

ui:element({
    id = "bar_indet2",
    type = "progress",
    rect = { unit = "px", x = 20 + (W - 30) / 2, y = y + 16, w = (W - 30) / 2, h = 8 },
    props = { indeterminate = true },
    style = { bg = "#1E293B", fill = "#A78BFA", speed = 0.8 },
})

-- ═══════════════════════════════════════════════════════════════════
-- Section 5: Spinners
-- ═══════════════════════════════════════════════════════════════════
y = y + 36

ui:element({
    id = "lbl_spin",
    type = "label",
    rect = { unit = "px", x = 10, y = y, w = 300, h = 14 },
    props = { text = "Spinner elements" },
    style = { font_size = 10, color = "#64748B" },
})

-- A row of spinners with different styles
local spinners = {
    { color = "#38BDF8", track = "#1E293B", thick = 3, arc = 0.25, speed = 2,   label = "Default" },
    { color = "#22C55E", track = "#1E293B", thick = 4, arc = 0.4,  speed = 1.5, label = "Wide arc" },
    { color = "#EAB308", track = "#1E293B", thick = 2, arc = 0.15, speed = 4,   label = "Fast thin" },
    { color = "#EF4444", track = "#1E293B", thick = 5, arc = 0.5,  speed = 1,   label = "Slow thick" },
    { color = "#A78BFA", track = "#0F172A", thick = 3, arc = 0.3,  speed = 3,   label = "Purple" },
}

local spin_size = 36
local spin_gap = (W - 20 - #spinners * spin_size) / (#spinners - 1)

for i, s in ipairs(spinners) do
    local sx = 10 + (i - 1) * (spin_size + spin_gap)
    ui:element({
        id = "spin_" .. i,
        type = "spinner",
        rect = { unit = "px", x = sx, y = y + 16, w = spin_size, h = spin_size },
        style = {
            color = s.color,
            track_color = s.track,
            thickness = s.thick,
            arc_length = s.arc,
            speed = s.speed,
        },
    })
    ui:element({
        id = "spin_lbl_" .. i,
        type = "label",
        rect = { unit = "px", x = sx - 10, y = y + 54, w = spin_size + 20, h = 12 },
        props = { text = s.label },
        style = { font_size = 8, color = "#475569", align = "center" },
    })
end

-- ═══════════════════════════════════════════════════════════════════
-- Section 6: Gauge with invert
-- ═══════════════════════════════════════════════════════════════════
y = y + 72

ui:element({
    id = "lbl_gauge",
    type = "label",
    rect = { unit = "px", x = 10, y = y, w = 200, h = 14 },
    props = { text = "Gauge: normal vs inverted" },
    style = { font_size = 10, color = "#64748B" },
})

-- Normal gauge (danger = high values, on the right)
ui:element({
    id = "gauge_normal",
    type = "gauge",
    rect = { unit = "px", x = 30, y = y + 18, w = 130, h = 56 },
    props = {
        value = 165,
        min = 0,
        max = 200,
        warn = 0.65,
        danger = 0.85,
        label = "PRESSURE",
        unit = " kPa",
    },
    style = {
        bg = "#111827",
        arc_thickness = 6,
        font_size = 10,
        value_color = "#E2E8F0",
        label_color = "#64748B",
    },
})

-- Inverted gauge (danger = low values, on the left - useful for battery/fuel)
ui:element({
    id = "gauge_invert",
    type = "gauge",
    rect = { unit = "px", x = W / 2 + 30, y = y + 18, w = 130, h = 56 },
    props = {
        value = 25,
        min = 0,
        max = 100,
        warn = 0.35,
        danger = 0.15,
        invert = true,
        label = "BATTERY",
        unit = "%",
    },
    style = {
        bg = "#111827",
        arc_thickness = 6,
        font_size = 10,
        value_color = "#E2E8F0",
        label_color = "#64748B",
    },
})

ui:element({
    id = "gauge_lbl_n",
    type = "label",
    rect = { unit = "px", x = 10, y = y + 76, w = W / 2 - 10, h = 12 },
    props = { text = "Normal (high = danger)" },
    style = { font_size = 8, color = "#475569", align = "center" },
})

ui:element({
    id = "gauge_lbl_i",
    type = "label",
    rect = { unit = "px", x = W / 2, y = y + 76, w = W / 2 - 10, h = 12 },
    props = { text = "Inverted (low = danger)" },
    style = { font_size = 8, color = "#475569", align = "center" },
})

ui:commit()

-- ═══════════════════════════════════════════════════════════════════
-- Tick loop: animate the color_stops bar
-- ═══════════════════════════════════════════════════════════════════
local t = 0

function tick(dt)
    t = t + dt * 0.3 -- slow cycle
    -- Oscillate value between 0 and 1 with a sine wave
    local val = (math.sin(t) + 1) / 2

    ui:element({
        id = "bar_stops",
        type = "progress",
        rect = { unit = "px", x = 10, y = 86, w = W - 80, h = 14 },
        props = { value = val },
        style = {
            bg = "#1E293B",
            fill = "#22C55E",
            color_stops = {
                { 0,   "#22C55E" },
                { 0.5, "#EAB308" },
                { 0.8, "#EF4444" },
            },
        },
    })

    ui:element({
        id = "bar_stops_val",
        type = "label",
        rect = { unit = "px", x = W - 65, y = 86, w = 55, h = 14 },
        props = { text = string.format("%.0f%%", val * 100) },
        style = { font_size = 11, color = "#E2E8F0", align = "right" },
    })

    ui:commit()
end
