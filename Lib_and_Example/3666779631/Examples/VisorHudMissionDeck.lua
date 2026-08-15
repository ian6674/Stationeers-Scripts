-- VisorHudMissionDeck.lua
-- Five "mission card" buttons + a status strip. Shows interactive on_click on a visor HUD
-- (same pattern as keypad examples: on_click receives optional playerName).
--
-- **Drag:** outer **deck** panel uses layout auto-drag-group generation so the whole stack moves.
-- `hud:on_drag(rebuild)` repositions it automatically after each drag.
-- **Save:** `serialize` / `deserialize` persist placement (VisorHudPong.lua pattern).
--
-- Anchored top-left via `ss.hud.first_free_anchor` so it stays clear of the hands strip,
-- open inventory windows, etc. - no manual screen-to-canvas inset math.

local hud = ss.hud.surface("main")
ss.hud.activate("main")

local CARD_W = 148
local CARD_H = 36
local GAP = 6

local missions = {
    { id = "m_scan", label = "SCAN", color = "#0EA5E9" },
    { id = "m_mine", label = "MINE", color = "#A855F7" },
    { id = "m_build", label = "BUILD", color = "#22C55E" },
    { id = "m_repair", label = "REPAIR", color = "#F97316" },
    { id = "m_idle", label = "STANDBY", color = "#64748B" },
}

local DECK_W = CARD_W + 16
local DECK_H = 72 + CARD_H * #missions + GAP * (#missions + 1)

local last_pick = "-"
local last_player = ""

local function base_xy()
    -- ss.hud.first_free_anchor walks the safe area produced by ss.hud.safe_area() and
    -- returns the first anchor whose placement doesn't intersect any panel from
    -- ss.client_overlay(). Falls back to the first anchor in the list if every option
    -- conflicts (caller still gets a usable rect).
    local p = ss.hud.first_free_anchor(
        { "top_left", "top_right", "bottom_left", "bottom_right" },
        DECK_W, DECK_H)
    if not p then return 0, 0 end
    return tonumber(p.x) or 0, tonumber(p.y) or 0
end

-- Clamp a saved drag offset (dx, dy) so a panel of size (w, h) anchored at base
-- (bx, by) cannot leave the visible visor canvas (0..W, 0..H). Called from
-- rebuild so a stale offset from a different screen aspect, an oversize
-- drag, or a corrupted save never strands the deck off-screen where the user
-- can't see it (and therefore can't drag it back). When the panel is bigger
-- than the canvas (degenerate aspect), pins the panel at the closest edge.
local function clamp_offset(bx, by, w, h, W, H, dx, dy)
    local lo_x, hi_x = -bx, W - w - bx
    local lo_y, hi_y = -by, H - h - by
    if hi_x < lo_x then hi_x = lo_x end
    if hi_y < lo_y then hi_y = lo_y end
    return math.max(lo_x, math.min(hi_x, dx)),
           math.max(lo_y, math.min(hi_y, dy))
end

local function drag_panel_props(id)
    return {
        z_index = 0,
        draggable = "true",
        drag_group = "auto",
        drag_bounds = "screen",
    }
end

local function rebuild()
    local sz = hud:size()
    local W, H = tonumber(sz.w), tonumber(sz.h)
    local bx, by = base_xy()
    local off = hud:drag_offset("deck")
    local dx, dy = clamp_offset(bx, by, DECK_W, DECK_H, W, H, tonumber(off.dx) or 0, tonumber(off.dy) or 0)
    local ox = bx + dx
    local oy = by + dy

    local status = "Last: " .. last_pick
    if last_player ~= "" then
        status = status .. "  (" .. last_player .. ")"
    end

    local children = {
        {
            layout = "row",
            rect = { h = 16 },
            children = {
                {
                    id = "hdr",
                    type = "label",
                    flex = 1,
                    props = { text = "QUICK ORDERS" },
                    style = { font_size = 10, color = "#94A3B8", align = "left" },
                },
            },
        },
    }

    for _, m in ipairs(missions) do
        children[#children + 1] = {
            id = m.id,
            type = "button",
            rect = { h = CARD_H },
            props = { text = m.label },
            style = { bg = m.color, text = "#FFFFFF", font_size = 14 },
            on_click = function(playerName)
                last_pick = m.label
                last_player = tostring(playerName or "")
                rebuild()
            end,
        }
    end

    children[#children + 1] = {
        layout = "row",
        rect = { h = 40 },
        padding = { top = 4 },
        children = {
            {
                id = "status",
                type = "label",
                flex = 1,
                props = { text = status },
                style = { font_size = 11, color = "#CBD5E1", align = "left" },
            },
        },
    }

    hud:clear()
    hud:layout({
        layout = "flex",
        rect = { unit = "px", x = ox, y = oy, w = DECK_W, h = DECK_H },
        children = {
            {
                id = "deck",
                type = "panel",
                layout = "column",
                gap = GAP,
                rect = { w = DECK_W, h = DECK_H },
                padding = { left = 8, right = 8, top = 8, bottom = 8 },
                props = drag_panel_props("deck"),
                style = { bg = "#0F172ACC", border = "#334155" },
                children = children,
            },
        },
    })
    hud:commit()
end

local PERSIST_KEY = "layout"

local function persist_save_layout()
    local off = hud:drag_offset("deck")
    local ok, json = pcall(util.json.encode, { v = 1, lay_dx = off.dx, lay_dy = off.dy })
    if ok and json then ic.persist.set(PERSIST_KEY, json) end
end

local function persist_restore_layout()
    if not ic.persist.has(PERSIST_KEY) then return end
    local blob = ic.persist.get(PERSIST_KEY)
    if type(blob) ~= "string" or blob == "" then return end
    local ok, decoded = pcall(util.json.decode, blob)
    if not ok or type(decoded) ~= "table" then return end
    local dx = tonumber(decoded.lay_dx)
    local dy = tonumber(decoded.lay_dy)
    if dx and dy and dx == dx and dy == dy then
        hud:set_drag_offset("deck", dx, dy)
    end
end

do
    persist_restore_layout()
    local function on_layout_change()
        rebuild()
        persist_save_layout()
    end
    hud:on_drag(on_layout_change)
    ss.hud.on_overlay_change(on_layout_change)
    rebuild()
end
