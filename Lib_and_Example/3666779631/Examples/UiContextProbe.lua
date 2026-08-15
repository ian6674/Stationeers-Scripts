-- UiContextProbe.lua
-- Programmable Visor HUD: live diagnostic of `ss.client_overlay()` so you can SEE the
-- vanilla UI rects your scripts are positioning around, color-coded by `kind`, with the
-- `ss.hud.safe_area()` rectangle drawn on top.
--
-- Drop the chip in a programmable visor, then move around the world and open vanilla UI
-- (hit F on a backpack, open the Stationpedia, etc.) - every visible vanilla panel will
-- appear as a translucent labeled rectangle in the visor canvas, in the EXACT coordinate
-- system your own `hud:layout()` rects use. No screen-to-canvas math, no Y flip, no scale
-- factors. Whatever you see here is the same numbers your script reads from `panels[].x`
-- / `.y` / `.w` / `.h`.
--
-- Status line shows:
--   `v=<int>`   - `ss.client_overlay().version`. Bumps on every actual change.
--   `src=...`   - "local" (this process is the wearer) or "remote_client" (relayed from
--                 the wearer's game client in multiplayer / dedicated servers).
--   `age=...s`  - how stale the relayed snapshot is (0 for the local case).
--   `panels=N`  - number of visible vanilla rects we know about.
--
-- Toggle it on/off without removing the chip via the small button in the corner.

local hud = ss.hud.surface("main")
ss.hud.activate("main")

local enabled = true

-- One color per `kind` value the overlay snapshot can emit. Anything unknown falls
-- through to "panel" so a future kind stays visible without breaking the probe.
local KIND_STYLE = {
    hands             = { fill = "#0EA5E933", line = "#0EA5E9" },
    clothing          = { fill = "#A78BFA33", line = "#A78BFA" },
    vitals            = { fill = "#F4722833", line = "#F47228" },
    inventory_window  = { fill = "#FACC1533", line = "#FACC15" },
    chrome            = { fill = "#94A3B833", line = "#94A3B8" },
    system_modal      = { fill = "#F472B633", line = "#F472B6" },
    panel             = { fill = "#22C55E33", line = "#22C55E" },
}

local function style_for(kind)
    return KIND_STYLE[kind] or KIND_STYLE.panel
end

local function status_line(o)
    if not o or not o.ok then
        return string.format("UI CONTEXT PROBE  v=0  src=%s  no overlay yet", tostring(o and o.source or "n/a"))
    end
    local ver  = tonumber(o.version) or 0
    local src  = tostring(o.source or "?")
    local age  = tonumber(o.relay_age_s) or 0
    local n    = (type(o.panels) == "table") and #o.panels or 0
    local cw   = math.floor(tonumber(o.canvas_w) or 0)
    local ch   = math.floor(tonumber(o.canvas_h) or 0)
    local sw   = math.floor(tonumber(o.screen_w) or 0)
    local sh   = math.floor(tonumber(o.screen_h) or 0)
    return string.format(
        "UI CONTEXT PROBE  v=%d  src=%s  age=%.1fs  panels=%d  canvas=%dx%d  screen=%dx%d",
        ver, src, age, n, cw, ch, sw, sh)
end

-- Build one panel-rect overlay child per vanilla panel, plus a label inside it. The whole
-- thing is non-interactive (no `props.draggable`) so it never steals input.
local function panel_children(o)
    local kids = {}
    if not o or not o.ok or type(o.panels) ~= "table" then
        return kids
    end
    for i = 1, #o.panels do
        local p = o.panels[i]
        if type(p) == "table" then
            local px = math.floor(tonumber(p.x) or 0)
            local py = math.floor(tonumber(p.y) or 0)
            local pw = math.floor(tonumber(p.w) or 0)
            local ph = math.floor(tonumber(p.h) or 0)
            if pw >= 4 and ph >= 4 then
                local kind = tostring(p.kind or "panel")
                local id = tostring(p.id or ("panel_" .. i))
                local title = tostring(p.title or "")
                local st = style_for(kind)
                local label = string.format("%s [%s] %dx%d", id, kind, pw, ph)
                if title ~= "" then
                    label = label .. "  " .. title
                end
                kids[#kids + 1] = {
                    id = "probe_" .. id,
                    type = "panel",
                    rect = { unit = "px", x = px, y = py, w = pw, h = ph },
                    style = { bg = st.fill, border = st.line, border_width = 2 },
                    children = {
                        {
                            id = "probe_label_" .. id,
                            type = "label",
                            rect = { unit = "px", x = 4, y = 4, w = math.max(40, pw - 8), h = 16 },
                            props = { text = label },
                            style = { font_size = 11, color = st.line, align = "left" },
                        },
                    },
                }
            end
        end
    end
    return kids
end

-- Translucent fill of `ss.hud.safe_area()` so you can see exactly where your HUD WOULD
-- land if you anchored to it, with all vanilla rect avoidance applied.
local function safe_area_child()
    local r = ss.hud.safe_area()
    if not r then return nil end
    local x = math.floor(tonumber(r.x) or 0)
    local y = math.floor(tonumber(r.y) or 0)
    local w = math.floor(tonumber(r.w) or 0)
    local h = math.floor(tonumber(r.h) or 0)
    if w < 4 or h < 4 then return nil end
    return {
        id = "probe_safe_area",
        type = "panel",
        rect = { unit = "px", x = x, y = y, w = w, h = h },
        style = { bg = "#22C55E14", border = "#22C55E", border_width = 1 },
        children = {
            {
                id = "probe_safe_area_label",
                type = "label",
                rect = { unit = "px", x = 6, y = 6, w = math.max(80, w - 12), h = 16 },
                props = { text = string.format("ss.hud.safe_area()  %dx%d at %d,%d  pad=%d",
                    w, h, x, y, math.floor(tonumber(r.pad) or 0)) },
                style = { font_size = 11, color = "#22C55E", align = "left" },
            },
        },
    }
end

local function rebuild()
    local o = ss.client_overlay()
    local sz = hud:size()
    local W, H = tonumber(sz.w), tonumber(sz.h)

    hud:clear()
    if not enabled then
        hud:layout({
            layout = "flex",
            rect = { unit = "px", x = 0, y = 0, w = W, h = H },
            children = {
                {
                    id = "probe_toggle",
                    type = "button",
                    rect = { unit = "px", x = 12, y = 12, w = 88, h = 24 },
                    props = { text = "PROBE OFF" },
                    style = { bg = "#1F2937", text = "#FACC15", font_size = 11, border = "#FACC15", border_width = 1 },
                    on_click = function()
                        enabled = true
                        rebuild()
                    end,
                },
            },
        })
        hud:commit()
        return
    end

    local kids = panel_children(o)
    local sa = safe_area_child()
    if sa then
        kids[#kids + 1] = sa
    end

    kids[#kids + 1] = {
        id = "probe_status_bg",
        type = "panel",
        rect = { unit = "px", x = 12, y = 12, w = math.min(W - 24, 760), h = 26 },
        style = { bg = "#0F172AE0", border = "#38BDF8", border_width = 1 },
        children = {
            {
                id = "probe_status",
                type = "label",
                rect = { unit = "px", x = 8, y = 5, w = math.min(W - 40, 740), h = 16 },
                props = { text = status_line(o) },
                style = { font_size = 11, color = "#E2E8F0", align = "left" },
            },
        },
    }

    kids[#kids + 1] = {
        id = "probe_toggle",
        type = "button",
        rect = { unit = "px", x = 12, y = 44, w = 88, h = 24 },
        props = { text = "PROBE ON" },
        style = { bg = "#0F172A", text = "#22C55E", font_size = 11, border = "#22C55E", border_width = 1 },
        on_click = function()
            enabled = false
            rebuild()
        end,
    }

    hud:layout({
        layout = "flex",
        rect = { unit = "px", x = 0, y = 0, w = W, h = H },
        children = kids,
    })
    hud:commit()
end

do
    ss.hud.on_overlay_change(rebuild)
    rebuild()
end
