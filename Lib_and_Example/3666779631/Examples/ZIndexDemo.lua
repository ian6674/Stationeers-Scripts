-- ZIndexDemo.lua
-- Demonstrates per-parent draw order via props.z_index (or props.zIndex).
-- PASS: static area shows BLUE on top; animated area cycles which color wins every 2s;
-- scroll strip shows PURPLE over ORANGE in the overlap (hint text sits above panels).
--
-- SETUP: ScriptedScreens motherboard + Lua chip; paste script, run.

local ui = ss.ui.surface("main")
ss.ui.activate("main")

local size = ui:size()
local W, H = 480, 272
if size then W, H = size.w or W, size.h or H end

local MID = math.floor(W / 2)
local BOX_W = MID - 24
local BOX_H = 72
local LEFT_X = 12
local RIGHT_X = MID + 12
-- Vertical bands: title (4-22) → subtitle (22-36) → headers (38-49) → stacks → notes → scroll
local HDR_Y = 38
local BOX_Y = 50

ui:clear()

ui:element({
    id = "bg",
    type = "panel",
    rect = { unit = "px", x = 0, y = 0, w = W, h = H },
    style = { bg = "#0B1220" },
})

ui:element({
    id = "title",
    type = "label",
    rect = { unit = "px", x = 8, y = 4, w = W - 16, h = 18 },
    props = { text = "Z-INDEX DEMO  (higher z_index = in front)" },
    style = { font_size = 12, color = "#E2E8F0", align = "center" },
})

ui:element({
    id = "subtitle",
    type = "label",
    rect = { unit = "px", x = 12, y = 22, w = W - 24, h = 14 },
    props = { text = "Same rect per stack. Scroll area = nested parent." },
    style = { font_size = 8, color = "#64748B", align = "center" },
})

ui:element({
    id = "hdr_left",
    type = "label",
    rect = { unit = "px", x = LEFT_X, y = HDR_Y, w = BOX_W, h = 11 },
    props = { text = "STATIC (z = 1, 2, 5)", z_index = 2 },
    style = { font_size = 10, color = "#94A3B8" },
})

ui:element({
    id = "hdr_right",
    type = "label",
    rect = { unit = "px", x = RIGHT_X, y = HDR_Y, w = BOX_W, h = 11 },
    props = { text = "ANIMATED (2s / phase)", z_index = 2 },
    style = { font_size = 10, color = "#94A3B8" },
})

local function stack_panels(prefix, base_x, z1, z2, z3)
    ui:element({
        id = prefix .. "_red",
        type = "panel",
        rect = { unit = "px", x = base_x, y = BOX_Y, w = BOX_W, h = BOX_H },
        props = { z_index = z1 },
        style = { bg = "#DC2626" },
    })
    ui:element({
        id = prefix .. "_green",
        type = "panel",
        rect = { unit = "px", x = base_x, y = BOX_Y, w = BOX_W, h = BOX_H },
        props = { z_index = z2 },
        style = { bg = "#16A34A" },
    })
    ui:element({
        id = prefix .. "_blue",
        type = "panel",
        rect = { unit = "px", x = base_x, y = BOX_Y, w = BOX_W, h = BOX_H },
        props = { z_index = z3 },
        style = { bg = "#2563EB" },
    })
end

stack_panels("st", LEFT_X, 1, 2, 5)
stack_panels("anim", RIGHT_X, 10, 20, 30)

local NOTE_Y = BOX_Y + BOX_H + 5
local NOTE_H = 26

ui:element({
    id = "st_note",
    type = "label",
    rect = { unit = "px", x = LEFT_X, y = NOTE_Y, w = BOX_W, h = NOTE_H },
    props = { text = "Expect solid BLUE (not red/green)." },
    style = { font_size = 9, color = "#CBD5E1", align = "center" },
})

ui:element({
    id = "anim_status",
    type = "label",
    rect = { unit = "px", x = RIGHT_X, y = NOTE_Y, w = BOX_W, h = NOTE_H },
    props = { text = "Top: BLUE (initial)", z_index = 2 },
    style = { font_size = 10, color = "#FDE047", align = "center" },
})

local SCROLL_LABEL_Y = NOTE_Y + NOTE_H + 4
local SCROLL_Y = SCROLL_LABEL_Y + 12
local SCROLL_H = math.max(48, H - SCROLL_Y - 6)
local SW = math.min(300, W - 40)
local CONTENT_H = 138

ui:element({
    id = "sv_label",
    type = "label",
    rect = { unit = "px", x = LEFT_X, y = SCROLL_LABEL_Y, w = W - 24, h = 11 },
    props = { text = "Scrollview: purple z=5 over orange z=2", z_index = 2 },
    style = { font_size = 9, color = "#64748B" },
})

local scroll = ui:element({
    id = "z_scroll",
    type = "scrollview",
    rect = { unit = "px", x = LEFT_X, y = SCROLL_Y, w = W - 24, h = SCROLL_H },
    props = { content_height = tostring(CONTENT_H) },
    style = {
        bg = "#111827",
        scrollbar_bg = "#1E293B",
        scrollbar_handle = "#64748B",
    },
})

-- Text above the colored panels (never covered)
scroll:element({
    id = "z_scroll/hint",
    type = "label",
    rect = { unit = "px", x = 6, y = 4, w = SW + 20, h = 16 },
    props = { text = "Overlap below - mixed area should look PURPLE" },
    style = { font_size = 9, color = "#E2E8F0", align = "center" },
})

scroll:element({
    id = "z_scroll/orange",
    type = "panel",
    rect = { unit = "px", x = 6, y = 24, w = SW, h = 54 },
    props = { z_index = 2 },
    style = { bg = "#EA580C" },
})

scroll:element({
    id = "z_scroll/purple",
    type = "panel",
    rect = { unit = "px", x = 40, y = 36, w = SW, h = 54 },
    props = { z_index = 5 },
    style = { bg = "#9333EA" },
})

-- z on props only (visuals still in style): nested parent = scroll content
scroll:element({
    id = "z_scroll/zprops_lbl",
    type = "label",
    rect = { unit = "px", x = 6, y = 96, w = SW + 20, h = 12 },
    props = { text = "z on props (camelCase zIndex on front panel):" },
    style = { font_size = 8, color = "#94A3B8" },
})

scroll:element({
    id = "z_scroll/zprops_back",
    type = "panel",
    rect = { unit = "px", x = 20, y = 108, w = 120, h = 22 },
    props = { z_index = 1 },
    style = { bg = "#1E293B" },
})

scroll:element({
    id = "z_scroll/zprops_front",
    type = "panel",
    rect = { unit = "px", x = 36, y = 114, w = 120, h = 22 },
    props = { zIndex = 5 },
    style = { bg = "#7C3AED" },
})

ui:commit()

local t = 0
local top_names = { "RED", "GREEN", "BLUE" }

function tick(dt)
    t = t + dt
    local phase = math.floor(t / 2) % 3
    local zr, zg, zb = 10, 10, 10
    if phase == 0 then
        zr, zg, zb = 30, 20, 10
    elseif phase == 1 then
        zr, zg, zb = 10, 30, 20
    else
        zr, zg, zb = 20, 10, 30
    end

    ui:element({
        id = "anim_red",
        type = "panel",
        rect = { unit = "px", x = RIGHT_X, y = BOX_Y, w = BOX_W, h = BOX_H },
        props = { z_index = zr },
        style = { bg = "#DC2626" },
    })
    ui:element({
        id = "anim_green",
        type = "panel",
        rect = { unit = "px", x = RIGHT_X, y = BOX_Y, w = BOX_W, h = BOX_H },
        props = { z_index = zg },
        style = { bg = "#16A34A" },
    })
    ui:element({
        id = "anim_blue",
        type = "panel",
        rect = { unit = "px", x = RIGHT_X, y = BOX_Y, w = BOX_W, h = BOX_H },
        props = { z_index = zb },
        style = { bg = "#2563EB" },
    })

    ui:element({
        id = "anim_status",
        type = "label",
        rect = { unit = "px", x = RIGHT_X, y = NOTE_Y, w = BOX_W, h = NOTE_H },
        props = { text = "Top: " .. top_names[phase + 1] .. "  (phase " .. phase .. "/2)", z_index = 2 },
        style = { font_size = 10, color = "#FDE047", align = "center" },
    })

    ui:commit()
end
