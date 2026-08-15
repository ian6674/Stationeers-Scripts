-- VisorHudStopwatch.lua
-- Interactive mission timer: RUN/PAUSE toggle + RESET.
--
-- hud:on_drag(rebuild_shell)           -- repositions after every drag
-- ss.hud.on_overlay_change(rebuild_shell) -- repositions when vanilla UI changes
-- tick() only handles the running timer; all layout is callback-driven.

local hud = ss.hud.surface("main")
ss.hud.activate("main")

local PANEL_W = 200
local PANEL_H = 118

local running = false
local accumulated = 0.0
local segment_start = nil ---@type number|nil

local function fmt_elapsed(sec)
    if sec ~= sec or sec < 0 then
        return "00:00.00"
    end
    local m = math.floor(sec / 60)
    local s = sec - m * 60
    return string.format("%02d:%05.2f", m, s)
end

local function elapsed_now()
    if not running or segment_start == nil then
        return accumulated
    end
    local ok, t = pcall(util.game_time)
    if not ok or type(t) ~= "number" then
        return accumulated
    end
    return accumulated + (t - segment_start)
end

local function surface_wh()
    local sz = hud:size()
    return tonumber(sz.w), tonumber(sz.h)
end

-- Clamp the drag offset so the panel can't be placed completely off-screen.
local function clamp_offset(bx, by, w, h, W, H, dx, dy)
    local lo_x, hi_x = -bx, W - w - bx
    local lo_y, hi_y = -by, H - h - by
    if hi_x < lo_x then hi_x = lo_x end
    if hi_y < lo_y then hi_y = lo_y end
    return math.max(lo_x, math.min(hi_x, dx)),
           math.max(lo_y, math.min(hi_y, dy))
end

local function rebuild_shell()
    local W, H = surface_wh()
    local p = ss.hud.first_free_anchor(
        { "bottom_right", "top_right", "bottom_left", "top_left" },
        PANEL_W, PANEL_H)
    local bx = p and (tonumber(p.x) or 0) or 0
    local by = p and (tonumber(p.y) or 0) or 0

    -- Read cumulative drag displacement stored by the drag system.
    local off = hud:drag_offset("deck")
    local dx, dy = clamp_offset(bx, by, PANEL_W, PANEL_H, W, H,
                                 tonumber(off.dx) or 0,
                                 tonumber(off.dy) or 0)
    local px = bx + dx
    local py = by + dy

    local bw = (PANEL_W - 24 - 8) / 2

    hud:clear()
    hud:layout({
        layout = "flex",
        rect = { unit = "px", x = px, y = py, w = PANEL_W, h = PANEL_H },
        children = {
            {
                id = "deck",
                type = "panel",
                layout = "column",
                gap = 4,
                rect = { w = PANEL_W, h = PANEL_H },
                padding = { left = 8, right = 8, top = 6, bottom = 14 },
                props = {
                    z_index = 0,
                    draggable = "true",
                    drag_group = "auto",
                    drag_bounds = "screen",
                },
                style = { bg = "#0C1222CC", border = "#38BDF8", border_width = 1 },
                children = {
                    {
                        layout = "row",
                        rect = { h = 18 },
                        children = {
                            {
                                id = "title",
                                type = "label",
                                flex = 1,
                                props = { text = "MISSION TIMER" },
                                style = { font_size = 11, color = "#94A3B8", align = "center" },
                            },
                        },
                    },
                    {
                        layout = "row",
                        rect = { h = 36 },
                        children = {
                            {
                                id = "readout",
                                type = "label",
                                flex = 1,
                                props = { text = fmt_elapsed(elapsed_now()) },
                                style = { font_size = 22, color = "#E2E8F0", align = "center" },
                            },
                        },
                    },
                    {
                        layout = "row",
                        gap = 8,
                        rect = { h = 32 },
                        children = {
                            {
                                id = "btn_run",
                                type = "button",
                                rect = { w = bw },
                                props = { text = running and "PAUSE" or "RUN" },
                                style = { bg = running and "#EA580C" or "#16A34A", text = "#FFFFFF", font_size = 14 },
                                on_click = function()
                                    local ok, t = pcall(util.game_time)
                                    if not ok or type(t) ~= "number" then
                                        return
                                    end
                                    if running then
                                        accumulated = accumulated + (t - segment_start)
                                        running = false
                                        segment_start = nil
                                    else
                                        running = true
                                        segment_start = t
                                    end
                                    rebuild_shell()
                                end,
                            },
                            {
                                id = "btn_reset",
                                type = "button",
                                rect = { w = bw },
                                props = { text = "RESET" },
                                style = { bg = "#475569", text = "#F8FAFC", font_size = 14 },
                                on_click = function()
                                    running = false
                                    accumulated = 0.0
                                    segment_start = nil
                                    rebuild_shell()
                                end,
                            },
                        },
                    },
                },
            },
        },
    })
    hud:commit()
end

local function refresh_readout()
    local ok, h = pcall(function()
        return hud:get("readout")
    end)
    if ok and h then
        pcall(function()
            h:set_props({ text = fmt_elapsed(elapsed_now()) })
        end)
    end
end

local PERSIST_KEY = "layout"

local function persist_save_layout()
    local off = hud:drag_offset("deck")
    local ok, json = pcall(util.json.encode, { v = 1, dx = off.dx, dy = off.dy })
    if ok and json then ic.persist.set(PERSIST_KEY, json) end
end

local function persist_restore_layout()
    if not ic.persist.has(PERSIST_KEY) then return end
    local blob = ic.persist.get(PERSIST_KEY)
    if type(blob) ~= "string" or blob == "" then return end
    local ok, data = pcall(util.json.decode, blob)
    if not ok or type(data) ~= "table" then return end
    local dx = tonumber(data.dx)
    local dy = tonumber(data.dy)
    if dx and dy and dx == dx and dy == dy then
        hud:set_drag_offset("deck", dx, dy)
    end
end

function tick()
    if running then
        refresh_readout()
        hud:commit()
    end
end

do
    persist_restore_layout()
    local function on_layout_change()
        rebuild_shell()
        persist_save_layout()
    end
    hud:on_drag(on_layout_change)
    ss.hud.on_overlay_change(on_layout_change)
    rebuild_shell()
end
