-- VisorHudSciFiTicker.lua
-- Thin "ticker tape" along the bottom: rotating station tips + live wireless status
-- (no device_list - safe when data link is down). Anchored inside `ss.hud.safe_area()`
-- so it stays clear of vanilla hands / suit status / open inventory windows automatically.
--
-- **Drag:** the **bar** panel is draggable and uses layout auto-drag-group generation.
-- `hud:on_drag(rebuild)` repositions it automatically after each drag.
-- **Save:** `serialize` / `deserialize` persist placement (VisorHudPong.lua pattern).
--
-- Good demo for: small always-on readout, pcall(ic.wireless_status), automatic layout
-- around vanilla UI via the ss.hud.safe_area() callback flow.

local hud = ss.hud.surface("main")
ss.hud.activate("main")

local TIPS = {
    "Check suit O2 before leaving airlock.",
    "Label batteries after charging cycles.",
    "Close interior doors during decompression.",
    "Log canister swaps in the hab log.",
    "Pre-breathe mixed gas before long EVA.",
    "Verify waste tank levels on night cycle.",
    "Keep a spare battery in the suit locker.",
}

local BAR_H = 26

local tip_index = 1
local last_tip_rotate = 0.0
local ROTATE_SEC = 7.0

local last_content_sig = nil

local function safe_wireless()
    local ok, w = pcall(ic.wireless_status)
    if not ok or type(w) ~= "table" then
        return { available = false, connected = false, in_range = false, network_id = 0 }
    end
    return w
end

local function safe_host_line()
    local ok, h = pcall(ic.host_info)
    if not ok or type(h) ~= "table" then
        return "chip: (host_info n/a)"
    end
    local typ = tostring(h.type or "?")
    local nm = tostring(h.name or "")
    if nm ~= "" then
        return "host: " .. typ .. " - " .. nm
    end
    return "host: " .. typ
end

local function wireless_line(w)
    if not w.available then
        return "RF: unavailable"
    end
    if not w.in_range then
        return "RF: no omni in range"
    end
    if not w.connected then
        return "RF: in range - data link DOWN"
    end
    local nid = tonumber(w.network_id) or 0
    return string.format("RF: linked  net=%d", nid)
end

local function content_signature()
    local w = safe_wireless()
    return table.concat({
        tostring(tip_index),
        wireless_line(w),
        safe_host_line(),
    }, "||")
end

-- Clamp a saved drag offset (dx, dy) so a panel of size (w, h) anchored at base
-- (bx, by) cannot leave the visible visor canvas (0..W, 0..H). Called from
-- rebuild so a stale offset from a different screen aspect, an oversize
-- drag, or a corrupted save never strands the ticker off-screen where the user
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

    -- ss.hud.safe_area() returns a canvas-space rect already clear of every vanilla
    -- panel from ss.client_overlay() (hands, suit status, open inventory windows,
    -- Stationpedia, etc.) plus a small pad. No screen-to-canvas math needed.
    local safe = ss.hud.safe_area()
    local safe_x = tonumber(safe and safe.x) or 0
    local safe_y = tonumber(safe and safe.y) or 0
    local safe_w = tonumber(safe and safe.w) or W
    local safe_h = tonumber(safe and safe.h) or H

    local base_y = safe_y + safe_h - BAR_H
    local base_x = safe_x
    local bar_w = math.max(120, safe_w)
    local off = hud:drag_offset("bar")
    local dx, dy = clamp_offset(base_x, base_y, bar_w, BAR_H, W, H, tonumber(off.dx) or 0, tonumber(off.dy) or 0)
    local x = base_x + dx
    local y = base_y + dy

    local w = safe_wireless()
    local ticker = TIPS[tip_index] .. "   \226\128\162   " .. wireless_line(w) .. "   \226\128\162   " .. safe_host_line()

    hud:clear()
    hud:layout({
        layout = "flex",
        rect = { unit = "px", x = x, y = y, w = bar_w, h = BAR_H },
        children = {
            {
                id = "bar",
                type = "panel",
                layout = "row",
                rect = { w = bar_w, h = BAR_H },
                padding = { left = 10, right = 10, top = 4, bottom = 4 },
                props = drag_panel_props("bar"),
                style = { bg = "#020617EE", border = "#22D3EE", border_width = 1 },
                children = {
                    {
                        id = "ticker",
                        type = "label",
                        flex = 1,
                        props = { text = ticker },
                        style = { font_size = 11, color = "#E0F2FE", align = "left" },
                    },
                },
            },
        },
    })
    hud:commit()
end

local function maybe_advance_tip()
    local ok, t = pcall(util.game_time)
    if not ok or type(t) ~= "number" then
        return false
    end
    if t - last_tip_rotate < ROTATE_SEC then
        return false
    end
    last_tip_rotate = t
    tip_index = (tip_index % #TIPS) + 1
    return true
end

hud:on_frame(function(_dt)
    local advanced = maybe_advance_tip()
    local sig = content_signature()
    if advanced or sig ~= last_content_sig then
        last_content_sig = sig
        rebuild()
    end
end)

local PERSIST_KEY = "layout"

local function persist_save_layout()
    local off = hud:drag_offset("bar")
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
        hud:set_drag_offset("bar", dx, dy)
    end
    last_content_sig = content_signature()
end

do
    local ok, t = pcall(util.game_time)
    if ok and type(t) == "number" then
        last_tip_rotate = t
    end
    persist_restore_layout()
    local function on_layout_change()
        rebuild()
        persist_save_layout()
    end
    hud:on_drag(on_layout_change)
    ss.hud.on_overlay_change(on_layout_change)
    last_content_sig = content_signature()
    rebuild()
end
