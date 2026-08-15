-- DragBoundsDemo.lua
-- Small `ss.ui` sample for live draggable bounds.
-- Shows both:
--   * `drag_bounds = "screen"` for a card that stops at the surface edge
--   * `drag_bounds = "element:bounds_box"` for a card that stays inside a panel
-- Rebuild-time clamp is kept too so stale saved offsets self-heal after resize / reload.

local ui = ss.ui.surface("main")
ss.ui.activate("main")

local CARD_W = 220
local CARD_H = 84
local IFACE_W = 108
local IFACE_H = 28

local status_txt = "Orange card is bounded to the whole screen. Blue card is bounded inside the blue box."
local last_sw, last_sh

local function surface_wh()
    local sz = ui:size()
    if type(sz) ~= "table" then
        return 960, 540
    end
    return math.max(320, tonumber(sz.w) or 960), math.max(240, tonumber(sz.h) or 540)
end

local function clamp_offset_to_rect(base_x, base_y, w, h, bounds_x, bounds_y, bounds_w, bounds_h, dx, dy)
    local lo_x = bounds_x - base_x
    local hi_x = bounds_x + bounds_w - w - base_x
    local lo_y = bounds_y - base_y
    local hi_y = bounds_y + bounds_h - h - base_y
    if hi_x < lo_x then hi_x = lo_x end
    if hi_y < lo_y then hi_y = lo_y end
    return math.max(lo_x, math.min(hi_x, dx)),
           math.max(lo_y, math.min(hi_y, dy))
end

local function drag_panel_props(id, bounds)
    return {
        draggable = "true",
        drag_group = "auto",
        drag_bounds = bounds,
    }
end

local function set_status(text)
    status_txt = text
    local status = ui:get("status")
    if status then
        pcall(function()
            status:set_props({ text = status_txt })
        end)
    end
end

local function wire_callbacks()
    local screen = ui:get("screen_card")
    if screen then
        screen:on("drag_begin", function()
            set_status("Dragging the orange card - live bounded to the screen.")
        end)
    end

    local box = ui:get("box_card")
    if box then
        box:on("drag_begin", function()
            set_status("Dragging the blue card - live bounded inside bounds_box.")
        end)
    end
end

local function build_card_node(id, w, h, bounds, title, body, bg, border)
    return {
        id = id,
        type = "panel",
        layout = "column",
        gap = 4,
        rect = { w = w, h = h },
        padding = { left = 10, right = 10, top = 8, bottom = 8 },
        props = drag_panel_props(id, bounds),
        style = { bg = bg, border = border, border_width = 2 },
        children = {
            {
                id = id .. "_title",
                type = "label",
                rect = { h = 20 },
                props = { text = title },
                style = { font_size = 14, color = "#F8FAFC", align = "left" },
            },
            {
                id = id .. "_body",
                type = "label",
                flex = 1,
                props = { text = body },
                style = { font_size = 12, color = "#CBD5E1", align = "left" },
            },
        },
    }
end

local function rebuild()
    local W, H = surface_wh()
    local pad = math.max(14, math.min(28, math.floor(W * 0.022)))
    local gap = math.max(10, math.min(18, math.floor(W * 0.016)))
    local header_h = 28
    local status_h = 42
    local box_x = pad
    local box_y = pad + header_h + status_h + gap
    local box_w = math.max(280, math.floor(W * 0.46))
    local box_h = math.max(160, H - box_y - pad)

    local box_base_x = box_x + 14
    local box_base_y = box_y + 14
    local box_off = ui:drag_offset("box_card")
    local box_dx, box_dy = clamp_offset_to_rect(
        box_base_x, box_base_y, CARD_W, CARD_H,
        box_x, box_y, box_w, box_h,
        tonumber(box_off.dx) or 0, tonumber(box_off.dy) or 0
    )
    ui:set_drag_offset("box_card", box_dx, box_dy)

    local screen_base_x = W - pad - CARD_W
    local screen_base_y = H - pad - CARD_H
    local screen_off = ui:drag_offset("screen_card")
    local screen_dx, screen_dy = clamp_offset_to_rect(
        screen_base_x, screen_base_y, CARD_W, CARD_H,
        0, 0, W, H,
        tonumber(screen_off.dx) or 0, tonumber(screen_off.dy) or 0
    )
    ui:set_drag_offset("screen_card", screen_dx, screen_dy)

    ui:clear()

    ui:element({
        id = "bg", type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = H },
        style = { bg = "#020617" },
    })

    ui:element({
        id = "title", type = "label",
        rect = { unit = "px", x = pad, y = pad, w = math.max(120, W - 2 * pad - IFACE_W - 8), h = header_h },
        props = { text = "DRAG BOUNDS DEMO" },
        style = { font_size = 18, color = "#E2E8F0", align = "left" },
    })

    ui:element({
        id = "iface_btn",
        type = "interface_button",
        rect = { unit = "px", x = W - pad - IFACE_W, y = pad, w = IFACE_W, h = IFACE_H },
        props = { text = "INTERFACE", z_index = 50 },
        style = { bg = "#422006", text = "#FDE68A", font_size = 9 },
    })

    ui:element({
        id = "status", type = "label",
        rect = { unit = "px", x = pad, y = pad + header_h, w = W - 2 * pad, h = status_h },
        props = { text = status_txt },
        style = { font_size = 12, color = "#94A3B8", align = "left" },
    })

    ui:element({
        id = "bounds_box", type = "panel",
        rect = { unit = "px", x = box_x, y = box_y, w = box_w, h = box_h },
        style = { bg = "#0F172ACC", border = "#38BDF8", border_width = 2 },
    })
    ui:element({
        id = "bounds_box_label", type = "label",
        rect = { unit = "px", x = box_x + 12, y = box_y + 10, w = box_w - 24, h = 24 },
        props = { text = "Bound box - this blue card cannot leave this panel" },
        style = { font_size = 13, color = "#BAE6FD", align = "left" },
    })

    ui:layout({
        layout = "flex",
        rect = { unit = "px", x = box_base_x + box_dx, y = box_base_y + box_dy, w = CARD_W, h = CARD_H },
        children = {
            build_card_node(
                "box_card",
                CARD_W,
                CARD_H,
                "element:bounds_box",
                "ELEMENT BOUNDS",
                "drag_bounds = \"element:bounds_box\"",
                "#082F49EE",
                "#38BDF8"
            ),
        },
    })

    ui:layout({
        layout = "flex",
        rect = { unit = "px", x = screen_base_x + screen_dx, y = screen_base_y + screen_dy, w = CARD_W, h = CARD_H },
        children = {
            build_card_node(
                "screen_card",
                CARD_W,
                CARD_H,
                "screen",
                "SCREEN BOUNDS",
                "drag_bounds = \"screen\"",
                "#431407EE",
                "#FB923C"
            ),
        },
    })

    ui:commit()
    wire_callbacks()
end

local PERSIST_KEY = "layout"

local function persist_save_layout()
    local screen = ui:drag_offset("screen_card")
    local box = ui:drag_offset("box_card")
    local ok, json = pcall(util.json.encode, {
        v = 1,
        screen_dx = screen.dx,
        screen_dy = screen.dy,
        box_dx = box.dx,
        box_dy = box.dy,
    })
    if ok and json then ic.persist.set(PERSIST_KEY, json) end
end

local function persist_restore_layout()
    if not ic.persist.has(PERSIST_KEY) then return end
    local blob = ic.persist.get(PERSIST_KEY)
    if type(blob) ~= "string" or blob == "" then return end
    local ok, d = pcall(util.json.decode, blob)
    if not ok or type(d) ~= "table" then return end
    local sdx = tonumber(d.screen_dx)
    local sdy = tonumber(d.screen_dy)
    local bdx = tonumber(d.box_dx)
    local bdy = tonumber(d.box_dy)
    if sdx and sdy and sdx == sdx and sdy == sdy then
        ui:set_drag_offset("screen_card", sdx, sdy)
    end
    if bdx and bdy and bdx == bdx and bdy == bdy then
        ui:set_drag_offset("box_card", bdx, bdy)
    end
end

function tick()
    local W, H = surface_wh()
    if W ~= last_sw or H ~= last_sh then
        last_sw, last_sh = W, H
        rebuild()
    end
end

do
    local W, H = surface_wh()
    last_sw, last_sh = W, H
    persist_restore_layout()
    ui:on_drag(function(id)
        local off = ui:drag_offset(id)
        set_status(string.format("%s placed at offset (%.0f, %.0f).", tostring(id), tonumber(off.dx) or 0, tonumber(off.dy) or 0))
        rebuild()
        persist_save_layout()
    end)
    rebuild()
end
