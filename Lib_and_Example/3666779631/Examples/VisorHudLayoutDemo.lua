-- VisorHudLayoutDemo.lua
-- Programmable Visor HUD: compact upper-left overlay (not a full-screen center panel).
--
-- When the visor has an active wireless *data link* (`ic.wireless_status().connected`),
-- lists every device on that remote network that exposes LogicType.Charge (station batteries,
-- cells in chargers, etc.) with charge % and optional energy from Maximum.
--
-- When Wi-Fi / data link is down, nothing that requires the network is queried: no `device_list`,
-- no `read_id`. Only `ic.wireless_status()` (local RF state) drives a small "no link" strip.
--
-- Uses `ss.hud.safe_area()` to compute a top-left origin already clear of the hands strip,
-- suit status, open inventory windows, etc. - no manual screen-to-canvas inset math.
--
-- **Drag:** link-only modes drag **link_strip**; when a data link is up, a full-area
-- **deck** panel sits behind the power list and uses layout auto-drag-group generation.
-- `hud:on_drag(...)` keeps both ids' stored offsets in sync so the panel stays in the same
-- place when the HUD switches between strip mode and full deck mode.
-- **Save:** `serialize` / `deserialize` (VisorHudPong.lua pattern).
--
-- Note: Visor Lua runs on the server. `ss.client_overlay()` uses the local InventoryManager when
-- this process is the wearer (single-player / listen host). In **multiplayer**, the wearer's
-- game client pushes a HUD snapshot to the host; server Lua then sees `source = "remote_client"`
-- (and `relay_stale` if updates stopped). A **headless dedicated server** with no connected
-- wearer client still has no overlay until a client is wearing the visor.

local hud = ss.hud.surface("main")
ss.hud.activate("main")

local LT = ic.enums.LogicType

local PANEL_W = 340
local TITLE_H = 26
local ROW_H = 22
local BAR_H = 6
local LINK_STRIP_H = 22

local last_sig = nil

local function safe_wireless_status()
    local ok, w = pcall(function()
        return ic.wireless_status()
    end)
    if not ok or type(w) ~= "table" then
        return { available = false, connected = false, in_range = false, network_id = 0 }
    end
    return w
end

local function wireless_signature(w)
    local nid = tonumber(w.network_id) or 0
    local conn = w.connected and 1 or 0
    local av = w.available and 1 or 0
    local ir = w.in_range and 1 or 0
    return table.concat({ tostring(av), tostring(conn), tostring(ir), tostring(nid) }, ":")
end

local function collect_battery_rows()
    local ok_list, list = pcall(ic.device_list)
    if not ok_list or type(list) ~= "table" then
        return {}
    end

    local n = #list
    if n == 0 then
        return {}
    end

    local rows = {}
    for i = 1, n do
        local d = list[i]
        if type(d) == "table" then
            local ref = d.ref_id
            if ref ~= nil then
                local rid = math.floor(tonumber(ref) or 0)
                if rid ~= 0 then
                    local ok_ch, ch = pcall(ic.read_id, rid, LT.Charge)
                    if ok_ch and type(ch) == "number" and ch == ch then
                        local mx = nil
                        local ok_mx, mjv = pcall(ic.read_id, rid, LT.Maximum)
                        if ok_mx and type(mjv) == "number" and mjv == mjv and mjv > 0 then
                            mx = mjv
                        end
                        local ratio = ch
                        if ratio > 1.0001 then
                            ratio = (mx and mx > 0) and (ch / mx) or 1
                        end
                        ratio = math.max(0, math.min(1, ratio))
                        rows[#rows + 1] = {
                            ref = rid,
                            name = tostring(d.display_name ~= "" and d.display_name or ("#" .. tostring(rid))),
                            ratio = ratio,
                            max_j = mx,
                        }
                    end
                end
            end
        end
    end
    table.sort(rows, function(a, b)
        return a.name:lower() < b.name:lower()
    end)
    return rows
end

local function battery_snapshot_signature(rows)
    local parts = { tostring(#rows) }
    for i = 1, #rows do
        local r = rows[i]
        parts[#parts + 1] = tostring(r.ref) .. "=" .. tostring(math.floor(r.ratio * 10000 + 0.5))
    end
    return table.concat(parts, ",")
end

local function bar_color(ratio)
    local p = ratio * 100
    if p >= 80 then
        return "#22C55E"
    end
    if p >= 50 then
        return "#84CC16"
    end
    if p >= 25 then
        return "#EAB308"
    end
    if p >= 10 then
        return "#F97316"
    end
    return "#EF4444"
end

local function build_data_signature(w, rows, connected)
    return table.concat({
        wireless_signature(w),
        connected and battery_snapshot_signature(rows) or "x",
    }, "||")
end

-- Clamp a saved drag offset (dx, dy) so a panel of size (w, h) anchored at base
-- (bx, by) cannot leave the visible visor canvas (0..W, 0..H). Called from
-- rebuild so a stale offset from a different screen aspect, an oversize
-- drag, or a corrupted save never strands the deck / link strip off-screen
-- where the user can't see it (and therefore can't drag it back). When the
-- panel is bigger than the canvas (degenerate aspect), pins it at the closest edge.
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
        visible = true,
        draggable = "true",
        drag_group = "auto",
        drag_bounds = "screen",
    }
end

local function layout_label(id, text, font_size, color, align, rect, flex)
    local node = {
        id = id,
        type = "label",
        props = { text = text, visible = true },
        style = { font_size = font_size, color = color, align = align or "left" },
    }
    if rect ~= nil then
        node.rect = rect
    end
    if flex ~= nil then
        node.flex = flex
    end
    return node
end

local function inset_label_slot(id, text, h, pad_l, pad_r, font_size, color, align)
    return {
        layout = "column",
        rect = { h = h },
        padding = { left = pad_l, right = pad_r },
        children = {
            layout_label(id, text, font_size, color, align, nil, 1),
        },
    }
end

local function sync_drag_offsets(dx, dy)
    hud:set_drag_offset("deck", dx, dy)
    hud:set_drag_offset("link_strip", dx, dy)
end

local function rebuild(_o, w, rows)
    hud:clear()

    -- hud:size() reports the wearer's actual visor canvas dims (server-side Lua reads
    -- the wearer's client-relayed canvas size on dedicated hosts; no fallback math needed).
    local sz = hud:size()
    local W, H = tonumber(sz.w), tonumber(sz.h)

    -- ss.hud.safe_area() returns a canvas-space rect already clear of every vanilla panel
    -- from ss.client_overlay() (hands, suit status, open inventory windows, Stationpedia,
    -- etc.) plus a small pad. No screen-to-canvas inset math required.
    local safe = ss.hud.safe_area()
    local ml = tonumber(safe and safe.x) or 0
    local mt = tonumber(safe and safe.y) or 0
    local innerW = tonumber(safe and safe.w) or W

    local panel_w = math.min(PANEL_W, math.max(200, innerW * 0.45))

    local connected = w.available and w.connected

    if not w.available then
        local off = hud:drag_offset("link_strip")
        local dx, dy = clamp_offset(ml, mt, panel_w, LINK_STRIP_H, W, H, tonumber(off.dx) or 0, tonumber(off.dy) or 0)
        sync_drag_offsets(dx, dy)
        local panel_x = ml + dx
        local panel_y = mt + dy
        hud:layout({
            layout = "flex",
            rect = { unit = "px", x = panel_x, y = panel_y, w = panel_w, h = LINK_STRIP_H },
            children = {
                {
                    id = "link_strip",
                    type = "panel",
                    layout = "row",
                    rect = { w = panel_w, h = LINK_STRIP_H },
                    padding = { left = 8, right = 8, top = 3, bottom = 3 },
                    props = drag_panel_props("link_strip"),
                    style = { bg = "#1E1B4B", border = "#4338CA" },
                    children = {
                        layout_label("link_text", "VISOR \xC2\xB7 wireless status unavailable", 13, "#C7D2FE", "left", nil, 1),
                    },
                },
            },
        })
        hud:commit()
        return
    end

    if not connected then
        local hint = "VISOR \xC2\xB7 NO DATA LINK"
        if w.in_range == false and (tonumber(w.network_id) or 0) ~= 0 then
            hint = hint .. "  (out of range / reconnecting)"
        elseif (tonumber(w.network_id) or 0) == 0 then
            hint = hint .. "  (pick a network on the visor)"
        end
        local off = hud:drag_offset("link_strip")
        local dx, dy = clamp_offset(ml, mt, panel_w, LINK_STRIP_H, W, H, tonumber(off.dx) or 0, tonumber(off.dy) or 0)
        sync_drag_offsets(dx, dy)
        local panel_x = ml + dx
        local panel_y = mt + dy
        hud:layout({
            layout = "flex",
            rect = { unit = "px", x = panel_x, y = panel_y, w = panel_w, h = LINK_STRIP_H },
            children = {
                {
                    id = "link_strip",
                    type = "panel",
                    layout = "row",
                    rect = { w = panel_w, h = LINK_STRIP_H },
                    padding = { left = 8, right = 8, top = 3, bottom = 3 },
                    props = drag_panel_props("link_strip"),
                    style = { bg = "#1C1917", border = "#57534E" },
                    children = {
                        layout_label("link_text", hint, 13, "#D6D3D1", "left", nil, 1),
                    },
                },
            },
        })
        hud:commit()
        return
    end

    local max_rows = 18
    local shown = math.min(#rows, max_rows)
    local nid = tonumber(w.network_id) or 0
    local total_h = TITLE_H + 4 + ROW_H + 4
    local children = {
        {
            id = "frame",
            type = "panel",
            layout = "row",
            rect = { h = TITLE_H },
            padding = { left = 8, right = 8, top = 4, bottom = 4 },
            style = { bg = "#0C1220", border = "#38BDF8" },
            children = {
                layout_label("title", string.format("REMOTE POWER  \xC2\xB7  net %s", nid ~= 0 and tostring(nid) or "?"), 14, "#E0F2FE", "left", nil, 1),
            },
        },
    }

    if #rows == 0 then
        children[#children + 1] = inset_label_slot("empty", "No Charge-capable devices on this data network.", ROW_H + 4, 6, 6, 12, "#94A3B8", "left")
    else
        total_h = TITLE_H + shown * (ROW_H + BAR_H + 8)
        for i = 1, shown do
            local r = rows[i]
            local pct = r.ratio * 100
            local joules = (r.max_j and (r.ratio * r.max_j)) or nil
            local jstr = ""
            if joules and joules == joules then
                if joules >= 1e6 then
                    jstr = string.format("  %.2f MJ", joules / 1e6)
                elseif joules >= 1e3 then
                    jstr = string.format("  %.1f kJ", joules / 1e3)
                else
                    jstr = string.format("  %.0f J", joules)
                end
            end

            local line = string.format("%-18s  %5.1f%%%s", r.name:sub(1, 18), pct, jstr)
            local bw = panel_w - 16
            local fill = math.max(0, math.floor(bw * r.ratio + 0.5))
            local bar_children = {}
            if fill > 0 then
                bar_children[#bar_children + 1] = {
                    id = "bar_fill_" .. i,
                    type = "panel",
                    rect = { w = fill },
                    style = { bg = bar_color(r.ratio), border = "transparent" },
                }
            end

            children[#children + 1] = {
                id = "row_bg_" .. i,
                type = "panel",
                layout = "column",
                gap = 0,
                rect = { h = ROW_H + BAR_H + 4 },
                padding = { left = 8, right = 8, top = 1, bottom = 3 },
                children = {
                    layout_label("row_txt_" .. i, line, 12, "#CBD5E1", "left", { h = ROW_H }),
                    {
                        id = "bar_bg_" .. i,
                        type = "panel",
                        layout = "row",
                        rect = { h = BAR_H },
                        children = bar_children,
                        style = { bg = "#1E293B", border = "#334155" },
                    },
                },
                style = { bg = "#0F172A", border = "#1E293B" },
            }
        end

        if #rows > shown then
            total_h = total_h + ROW_H + 4
            children[#children + 1] = inset_label_slot("more", string.format("\xE2\x80\xA6 +%d more", #rows - shown), ROW_H, 6, 6, 11, "#64748B", "left")
        end
    end

    local off = hud:drag_offset("deck")
    local dx, dy = clamp_offset(ml, mt, panel_w, total_h, W, H, tonumber(off.dx) or 0, tonumber(off.dy) or 0)
    sync_drag_offsets(dx, dy)
    local panel_x = ml + dx
    local panel_y = mt + dy
    hud:layout({
        layout = "flex",
        rect = { unit = "px", x = panel_x, y = panel_y, w = panel_w, h = total_h },
        children = {
            {
                id = "deck",
                type = "panel",
                layout = "column",
                gap = 4,
                rect = { w = panel_w, h = total_h },
                props = drag_panel_props("deck"),
                style = { bg = "#0A10204D", border = "transparent" },
                children = children,
            },
        },
    })

    hud:commit()
end

hud:on_frame(function(_dt)
    local o = ss.client_overlay()
    local w = safe_wireless_status()
    local connected = w.available and w.connected
    local rows = connected and collect_battery_rows() or {}
    local sig = build_data_signature(w, rows, connected)
    if sig ~= last_sig then
        last_sig = sig
        rebuild(o, w, rows)
    end
end)

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
        sync_drag_offsets(dx, dy)
    end
end

local function persist_restore_layout_and_rebuild()
    persist_restore_layout()
    local o = ss.client_overlay()
    local w = safe_wireless_status()
    local rows = (w.available and w.connected) and collect_battery_rows() or {}
    last_sig = build_data_signature(w, rows, w.available and w.connected)
    rebuild(o, w, rows)
end


do
    local function on_layout_change()
        persist_save_layout()
        local o = ss.client_overlay()
        local w = safe_wireless_status()
        local rows = (w.available and w.connected) and collect_battery_rows() or {}
        last_sig = build_data_signature(w, rows, w.available and w.connected)
        rebuild(o, w, rows)
    end
    hud:on_drag(function(id)
        local off = hud:drag_offset(id)
        sync_drag_offsets(tonumber(off.dx) or 0, tonumber(off.dy) or 0)
        on_layout_change()
    end)
    ss.hud.on_overlay_change(on_layout_change)
    persist_restore_layout_and_rebuild()
end
