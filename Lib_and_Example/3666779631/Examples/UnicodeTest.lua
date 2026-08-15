-- UnicodeTest.lua
-- Tests Unicode rendering with the fallback font system.
-- Raw Unicode characters work directly thanks to AsciiString UTF-8 patches.

local ui = ss.ui.surface("main")
ss.ui.activate("main")

local size = ui:size()
local W, H = size.w, size.h

ui:element({
    id = "bg",
    type = "panel",
    rect = { unit = "%", x = 0, y = 0, w = 100, h = 100 },
    style = { bg = "#0F172A" },
})

ui:element({
    id = "title",
    type = "label",
    rect = { unit = "px", x = 0, y = 8, w = W, h = 24 },
    props = { text = "Unicode Rendering Test" },
    style = { color = "#38BDF8", font_size = 16, align = "center" },
})

-- Arrows
ui:element({
    id = "arrows",
    type = "label",
    rect = { unit = "px", x = 16, y = 40, w = W - 32, h = 20 },
    props = { text = "Arrows: ◀ ▶ ▲ ▼ ← → ↑ ↓" },
    style = { color = "#E2E8F0", font_size = 14, align = "left" },
})

-- Degree, micro, plus-minus
ui:element({
    id = "symbols",
    type = "label",
    rect = { unit = "px", x = 16, y = 65, w = W - 32, h = 20 },
    props = { text = "Units: 22.5°C  |  3.2µmol  |  ±0.5%" },
    style = { color = "#E2E8F0", font_size = 14, align = "left" },
})

-- Dashes and bullets
ui:element({
    id = "dashes",
    type = "label",
    rect = { unit = "px", x = 16, y = 90, w = W - 32, h = 20 },
    props = { text = "Dashes: – en — em  |  Bullets: • ● ○" },
    style = { color = "#E2E8F0", font_size = 14, align = "left" },
})

-- Math symbols
ui:element({
    id = "math",
    type = "label",
    rect = { unit = "px", x = 16, y = 115, w = W - 32, h = 20 },
    props = { text = "Math: ≤ ≥ ≠ × ÷ ∞ ≈ √" },
    style = { color = "#E2E8F0", font_size = 14, align = "left" },
})

-- Misc symbols
ui:element({
    id = "misc",
    type = "label",
    rect = { unit = "px", x = 16, y = 140, w = W - 32, h = 20 },
    props = { text = "Misc: ✓ ✗ ★ ☆ ♪ ⌂ © ®" },
    style = { color = "#E2E8F0", font_size = 14, align = "left" },
})

-- Greek letters
ui:element({
    id = "greek",
    type = "label",
    rect = { unit = "px", x = 16, y = 165, w = W - 32, h = 20 },
    props = { text = "Greek: α β γ δ ε θ λ π σ Ω" },
    style = { color = "#E2E8F0", font_size = 14, align = "left" },
})

-- Currency
ui:element({
    id = "currency",
    type = "label",
    rect = { unit = "px", x = 16, y = 190, w = W - 32, h = 20 },
    props = { text = "Currency: ¢ £ ¥ €" },
    style = { color = "#E2E8F0", font_size = 14, align = "left" },
})

-- Status line
ui:element({
    id = "status",
    type = "label",
    rect = { unit = "px", x = 0, y = H - 24, w = W, h = 20 },
    props = { text = "Raw Unicode in source. ? = font issue, boxes = encoding issue." },
    style = { color = "#475569", font_size = 9, align = "center" },
})

ui:commit()
