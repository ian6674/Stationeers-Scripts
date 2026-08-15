-- GradientShowcase.lua
-- Demonstrates all gradient features: 2-color, multi-stop (evenly-spaced),
-- multi-stop (explicit positions), and all four directions (horizontal,
-- vertical, diagonal, radial). Also shows the ss.ui.gradient() color
-- interpolation helper used to generate dynamic color ramps.

local ui = ss.ui.surface("main")
ss.ui.activate("main")

local size = ui:size()
local W, H = 480, 272
if size then W, H = size.w, size.h end

ui:clear()

-- ── Background ──────────────────────────────────────────────────────
ui:element({
    id = "bg", type = "panel",
    rect = { unit = "px", x = 0, y = 0, w = W, h = H },
    style = { bg = "#0F172A" },
})

-- ── Title ───────────────────────────────────────────────────────────
ui:element({
    id = "title", type = "label",
    rect = { unit = "px", x = 10, y = 4, w = W - 20, h = 20 },
    props = { text = "GRADIENT SHOWCASE" },
    style = { font_size = 14, color = "#94A3B8", align = "center" },
})

-- ── Row 1: Gradient directions (2-color) ────────────────────────────
local row1_y = 28
local col_w = (W - 50) / 4
local gap = 10

ui:element({
    id = "lbl_dirs", type = "label",
    rect = { unit = "px", x = 10, y = row1_y, w = W, h = 14 },
    props = { text = "Directions (2-color)" },
    style = { font_size = 10, color = "#64748B" },
})

local directions = { "horizontal", "vertical", "diagonal", "radial" }
for i, dir in ipairs(directions) do
    local x = 10 + (i - 1) * (col_w + gap)
    ui:element({
        id = "dir_" .. dir, type = "panel",
        rect = { unit = "px", x = x, y = row1_y + 16, w = col_w, h = 40 },
        style = {
            bg = "#3B82F6",
            gradient = "#8B5CF6",
            gradient_dir = dir,
        },
    })
    ui:element({
        id = "dir_lbl_" .. dir, type = "label",
        rect = { unit = "px", x = x, y = row1_y + 58, w = col_w, h = 12 },
        props = { text = dir },
        style = { font_size = 9, color = "#64748B", align = "center" },
    })
end

-- ── Row 2: Multi-stop evenly spaced ─────────────────────────────────
local row2_y = row1_y + 76

ui:element({
    id = "lbl_even", type = "label",
    rect = { unit = "px", x = 10, y = row2_y, w = W, h = 14 },
    props = { text = "Multi-stop (evenly spaced array of colors)" },
    style = { font_size = 10, color = "#64748B" },
})

-- Rainbow gradient
ui:element({
    id = "rainbow", type = "panel",
    rect = { unit = "px", x = 10, y = row2_y + 16, w = W - 20, h = 30 },
    style = {
        gradient = { "#EF4444", "#F97316", "#EAB308", "#22C55E", "#3B82F6", "#8B5CF6" },
        gradient_dir = "horizontal",
    },
})

ui:element({
    id = "rainbow_lbl", type = "label",
    rect = { unit = "px", x = 10, y = row2_y + 48, w = W - 20, h = 12 },
    props = { text = "{ \"#EF4444\", \"#F97316\", \"#EAB308\", \"#22C55E\", \"#3B82F6\", \"#8B5CF6\" }" },
    style = { font_size = 8, color = "#475569", align = "center" },
})

-- ── Row 3: Multi-stop explicit positions ─────────────────────────────
local row3_y = row2_y + 66

ui:element({
    id = "lbl_explicit", type = "label",
    rect = { unit = "px", x = 10, y = row3_y, w = W, h = 14 },
    props = { text = "Multi-stop (explicit positions)" },
    style = { font_size = 10, color = "#64748B" },
})

-- Heat map style: mostly cool, sharp transition to hot
ui:element({
    id = "heatmap", type = "panel",
    rect = { unit = "px", x = 10, y = row3_y + 16, w = (W - 30) / 2, h = 30 },
    style = {
        gradient = {
            { 0,    "#1E40AF" },  -- deep blue
            { 0.6,  "#22D3EE" },  -- cyan
            { 0.8,  "#EAB308" },  -- yellow
            { 1,    "#EF4444" },  -- red
        },
        gradient_dir = "horizontal",
    },
})

ui:element({
    id = "heatmap_lbl", type = "label",
    rect = { unit = "px", x = 10, y = row3_y + 48, w = (W - 30) / 2, h = 12 },
    props = { text = "Heat map (blue→cyan→yellow→red)" },
    style = { font_size = 8, color = "#475569", align = "center" },
})

-- Status bar: green→yellow→red with sharp cutoffs
local half_x = 10 + (W - 30) / 2 + 10
ui:element({
    id = "status_grad", type = "panel",
    rect = { unit = "px", x = half_x, y = row3_y + 16, w = (W - 30) / 2, h = 30 },
    style = {
        gradient = {
            { 0,    "#22C55E" },
            { 0.45, "#22C55E" },
            { 0.5,  "#EAB308" },
            { 0.75, "#EAB308" },
            { 0.8,  "#EF4444" },
            { 1,    "#EF4444" },
        },
        gradient_dir = "horizontal",
    },
})

ui:element({
    id = "status_lbl", type = "label",
    rect = { unit = "px", x = half_x, y = row3_y + 48, w = (W - 30) / 2, h = 12 },
    props = { text = "Status zones (sharp color bands)" },
    style = { font_size = 8, color = "#475569", align = "center" },
})

-- ── Row 4: ss.ui.gradient() helper + radial multi-stop ──────────────
local row4_y = row3_y + 66

ui:element({
    id = "lbl_helper", type = "label",
    rect = { unit = "px", x = 10, y = row4_y, w = W, h = 14 },
    props = { text = "ss.ui.gradient() helper + radial multi-stop" },
    style = { font_size = 10, color = "#64748B" },
})

-- Use the gradient helper to generate a color ramp and display as bar segments
local ramp = ss.ui.gradient("#3B82F6", "#EF4444", 12)
local bar_w = (W - 20 - 110) / #ramp  -- leave room for radial on the right

for i, hex in ipairs(ramp) do
    ui:element({
        id = "ramp_" .. i, type = "panel",
        rect = { unit = "px", x = 10 + (i - 1) * bar_w, y = row4_y + 16, w = bar_w + 1, h = 30 },
        style = { bg = hex },
    })
end

ui:element({
    id = "ramp_lbl", type = "label",
    rect = { unit = "px", x = 10, y = row4_y + 48, w = W - 130, h = 12 },
    props = { text = "ss.ui.gradient(\"#3B82F6\", \"#EF4444\", 12)" },
    style = { font_size = 8, color = "#475569", align = "center" },
})

-- Radial multi-stop
ui:element({
    id = "radial_multi", type = "panel",
    rect = { unit = "px", x = W - 100, y = row4_y + 6, w = 90, h = 56 },
    style = {
        gradient = {
            { 0,   "#FBBF24" },  -- gold center
            { 0.4, "#EF4444" },  -- red ring
            { 1,   "#1E1B4B" },  -- dark edge
        },
        gradient_dir = "radial",
    },
})

ui:commit()
