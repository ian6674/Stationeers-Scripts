-- VisorHudMultiPanel.lua (multi-panel diagnostics)
-- Programmable Visor HUD: several compact overlays, each draggable on its own.
--
-- When the visor has an active wireless data link, scans `ic.device_list()` once per frame
-- (when not mid-drag) and fills:
--   * Remote power (Charge-capable devices)
--   * Remote production (generators with PowerGeneration, solar-style Ratio)
--   * Remote atmo (PressureInput + TemperatureInput when readable)
--   * Remote net (device totals, Lua chip count, network id)
--
-- When Wi-Fi is down, only `ic.wireless_status()` is queried; a single draggable link strip appears.
--
-- Drag: each panel has its own `deck_*` + `drag_group` + saved offset in `serialize` / `deserialize`.
-- `hud:on_drag(...)` repositions panels automatically after each drag.

local hud = ss.hud.surface("main")
ss.hud.activate("main")

local LT = ic.enums.LogicType

local PAD = 6
local PANEL_W_POWER = 340
local PANEL_W_AUX = 300
-- Production names are long (e.g. "Generator (Solid Fuel)"); wider than other aux columns.
local PANEL_W_PROD = 420
local PROD_VAL_COL_W = 118
local COL_GAP = 10
local TITLE_H = 26
local ROW_H = 20
local BAR_H = 6
local LINK_STRIP_H = 22

local last_sig = nil

-- Per-panel pixel offsets (draggable independently).
local off = {
    link = { dx = 0, dy = 0 },
    power = { dx = 0, dy = 0 },
    prod = { dx = 0, dy = 0 },
    atmo = { dx = 0, dy = 0 },
    net = { dx = 0, dy = 0 },
}

-- ss.hud.safe_area() returns a canvas-space rect already clear of every vanilla panel from
-- ss.client_overlay() (hands, suit status, open inventory windows, Stationpedia, etc.) plus
-- a small pad. Convert to (ml, mt, mr, mb) the rest of this script expects.
local function scaled_margins(_o, W, H)
    local safe = ss.hud.safe_area()
    if not safe then
        return PAD, PAD, PAD, PAD
    end
    local x = tonumber(safe.x) or 0
    local y = tonumber(safe.y) or 0
    local w = tonumber(safe.w) or W
    local h = tonumber(safe.h) or H
    local ml = math.max(0, x)
    local mt = math.max(0, y)
    local mr = math.max(0, W - (x + w))
    local mb = math.max(0, H - (y + h))
    return ml, mr, mt, mb
end

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

local function collect_diagnostics()
    local ok_list, list = pcall(ic.device_list)
    if not ok_list or type(list) ~= "table" then
        return {
            batteries = {},
            production = {},
            atmo = {},
            device_count = 0,
            lua_chip_count = 0,
            charge_count = 0,
        }
    end

    local n = #list
    local batteries = {}
    local production = {}
    local atmo = {}
    local lua_chip_count = 0

    for i = 1, n do
        local d = list[i]
        if type(d) == "table" then
            local ref = d.ref_id
            if ref ~= nil then
                local rid = math.floor(tonumber(ref) or 0)
                if rid ~= 0 then
                    local nm_low = tostring(d.display_name or ""):lower()
                    local pref_low = tostring(d.prefab_name or ""):lower()
                    -- Solar panels (and similar) expose Charge like a battery; keep them out of REMOTE POWER
                    -- and show them under REMOTE PRODUCTION using Ratio instead.
                    local solar_like = nm_low:find("solar", 1, true) ~= nil
                        or pref_low:find("solar", 1, true) ~= nil
                        or pref_low:find("solarpanel", 1, true) ~= nil
                    if d.is_lua_chip or nm_low:find("lua chip", 1, true) or nm_low:find("(lua)", 1, true) then
                        lua_chip_count = lua_chip_count + 1
                    end

                    local ok_ch, ch = pcall(ic.read_id, rid, LT.Charge)
                    local has_charge = ok_ch and type(ch) == "number" and ch == ch
                    if has_charge and not solar_like then
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
                        batteries[#batteries + 1] = {
                            ref = rid,
                            name = tostring(d.display_name ~= "" and d.display_name or ("#" .. tostring(rid))),
                            ratio = ratio,
                            max_j = mx,
                        }
                    end

                    local ok_pg, pg = pcall(ic.read_id, rid, LT.PowerGeneration)
                    if ok_pg and type(pg) == "number" and pg == pg then
                        local on_v = nil
                        local ok_on, onn = pcall(ic.read_id, rid, LT.On)
                        if ok_on and type(onn) == "number" then
                            on_v = onn
                        end
                        production[#production + 1] = {
                            ref = rid,
                            name = tostring(d.display_name ~= "" and d.display_name or ("#" .. tostring(rid))),
                            kind = "gen",
                            value = pg,
                            on = on_v,
                        }
                    else
                        local ok_r, rv = pcall(ic.read_id, rid, LT.Ratio)
                        if ok_r and type(rv) == "number" and rv == rv then
                            local use_solar = false
                            if solar_like then
                                use_solar = true
                            elseif not has_charge then
                                local ok_mx2, cap = pcall(ic.read_id, rid, LT.Maximum)
                                local looks_solar = false
                                if ok_mx2 and type(cap) == "number" and cap == cap and cap > 1000 and cap < 5e6 then
                                    looks_solar = true
                                end
                                use_solar = looks_solar or nm_low:find("solar", 1, true) ~= nil
                            end
                            if use_solar then
                                production[#production + 1] = {
                                    ref = rid,
                                    name = tostring(d.display_name ~= "" and d.display_name or ("#" .. tostring(rid))),
                                    kind = "solar",
                                    value = math.max(0, math.min(1, rv)),
                                    on = nil,
                                }
                            end
                        end
                    end

                    local ok_pi, pi = pcall(ic.read_id, rid, LT.PressureInput)
                    if ok_pi and type(pi) == "number" and pi == pi then
                        local ti = nil
                        local ok_ti, tv = pcall(ic.read_id, rid, LT.TemperatureInput)
                        if ok_ti and type(tv) == "number" and tv == tv then
                            ti = tv
                        end
                        atmo[#atmo + 1] = {
                            ref = rid,
                            name = tostring(d.display_name ~= "" and d.display_name or ("#" .. tostring(rid))),
                            pressure = pi,
                            temp = ti,
                        }
                    end
                end
            end
        end
    end

    table.sort(batteries, function(a, b)
        return a.name:lower() < b.name:lower()
    end)
    table.sort(production, function(a, b)
        return a.name:lower() < b.name:lower()
    end)
    table.sort(atmo, function(a, b)
        return a.name:lower() < b.name:lower()
    end)

    return {
        batteries = batteries,
        production = production,
        atmo = atmo,
        device_count = n,
        lua_chip_count = lua_chip_count,
        charge_count = #batteries,
    }
end

local function diag_signature(d)
    local parts = {
        tostring(d.device_count),
        tostring(d.lua_chip_count),
        tostring(#d.batteries),
        tostring(#d.production),
        tostring(#d.atmo),
    }
    for i = 1, #d.batteries do
        local r = d.batteries[i]
        parts[#parts + 1] = "b" .. tostring(r.ref) .. "=" .. tostring(math.floor(r.ratio * 10000 + 0.5))
    end
    for i = 1, #d.production do
        local r = d.production[i]
        local v = r.kind == "solar" and math.floor(r.value * 10000 + 0.5) or math.floor(r.value + 0.5)
        parts[#parts + 1] = "p" .. tostring(r.ref) .. "=" .. tostring(v)
    end
    for i = 1, #d.atmo do
        local r = d.atmo[i]
        parts[#parts + 1] = "a" .. tostring(r.ref) .. "=" .. tostring(math.floor(r.pressure + 0.5))
            .. (r.temp and (":" .. tostring(math.floor(r.temp + 0.5))) or "")
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

local function build_data_signature(w, diag, connected)
    return table.concat({
        wireless_signature(w),
        connected and diag_signature(diag) or "x",
    }, "||")
end

local function drag_panel_props(id)
    return {
        visible = true,
        draggable = "true",
        drag_group = "auto",
        drag_bounds = "screen",
    }
end

local OFFSET_IDS = {
    link = "link_strip",
    power = "deck_power",
    prod = "deck_prod",
    atmo = "deck_atmo",
    net = "deck_net",
}

local function load_offset(key)
    local o = hud:drag_offset(OFFSET_IDS[key])
    off[key].dx = tonumber(o.dx) or 0
    off[key].dy = tonumber(o.dy) or 0
end

local function store_offset(key, dx, dy)
    off[key].dx = dx
    off[key].dy = dy
    hud:set_drag_offset(OFFSET_IDS[key], dx, dy)
end

-- Clamp a saved drag offset (dx, dy) so a panel of size (w, h) anchored at base
-- (bx, by) cannot leave the visible visor canvas (0..W, 0..H). Called from
-- rebuild for each draggable panel so a stale offset from a different screen
-- aspect, an oversize drag, or a corrupted save never strands a panel off-screen
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

-- Per-panel height calculations (must match build_*_panel_node body output below).
-- Pulled out so rebuild() can compute each panel's effective base rect before
-- clamping its offset; the clamp must run BEFORE the build call so the node's
-- `offset = { dx, dy }` field reads the clamped value.
local function compute_power_h(rows)
    local max_rows = 10
    if #rows == 0 then
        return TITLE_H + 4 + ROW_H + 4
    end
    local shown = math.min(#rows, max_rows)
    local h = TITLE_H + shown * (ROW_H + BAR_H + 8)
    if #rows > shown then
        h = h + ROW_H + 4
    end
    return h
end

local function compute_prod_h(prod)
    local max_p = 8
    if #prod == 0 then
        return TITLE_H + 4 + ROW_H + 4
    end
    local shown = math.min(#prod, max_p)
    local h = TITLE_H + shown * (ROW_H + 6)
    if #prod > shown then
        h = h + ROW_H + 4
    end
    return h
end

local function compute_atmo_h(atm)
    local max_a = 8
    if #atm == 0 then
        return TITLE_H + 4 + ROW_H + 4
    end
    local shown = math.min(#atm, max_a)
    local h = TITLE_H + shown * (ROW_H + 6)
    if #atm > shown then
        h = h + ROW_H + 4
    end
    return h
end

local function compute_net_h()
    local line_count = 7
    return TITLE_H + line_count * (ROW_H + 4)
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

local function titled_panel_node(id, key, w, h, frame_id, title_id, title_text, frame_bg, frame_border, title_color, body_children)
    local children = {
        {
            id = frame_id,
            type = "panel",
            layout = "row",
            rect = { h = TITLE_H },
            padding = { left = 8, right = 8, top = 4, bottom = 4 },
            children = {
                layout_label(title_id, title_text, 14, title_color, "left", nil, 1),
            },
            style = { bg = frame_bg, border = frame_border },
        },
    }
    for i = 1, #body_children do
        children[#children + 1] = body_children[i]
    end

    return {
        id = id,
        type = "panel",
        layout = "column",
        gap = 4,
        align = "start",
        rect = { w = w, h = h },
        offset = { dx = off[key].dx, dy = off[key].dy },
        props = drag_panel_props(id),
        style = { bg = "#0A10204D", border = "transparent" },
        children = children,
    }
end

local function build_link_strip_node(panel_w, text, bg, border, fg)
    return {
        id = "link_strip",
        type = "panel",
        layout = "row",
        rect = { w = panel_w, h = LINK_STRIP_H },
        offset = { dx = off.link.dx, dy = off.link.dy },
        padding = { left = 8, right = 8, top = 3, bottom = 3 },
        props = drag_panel_props("link_strip"),
        style = { bg = bg, border = border },
        children = {
            layout_label("link_text", text, 13, fg, "left", nil, 1),
        },
    }
end

local function build_power_panel_node(nid, rows)
    local max_rows = 10
    local shown_b = math.min(#rows, max_rows)
    local body = {}
    local h_power

    if #rows == 0 then
        h_power = TITLE_H + 4 + ROW_H + 4
        body[#body + 1] = inset_label_slot("empty_p", "No Charge-capable devices on this data network.", ROW_H + 4, 6, 6, 12, "#94A3B8", "left")
    else
        h_power = TITLE_H + shown_b * (ROW_H + BAR_H + 8)
        if #rows > shown_b then
            h_power = h_power + ROW_H + 4
        end

        for i = 1, shown_b do
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

            local line = string.format("%-16s  %5.1f%%%s", r.name:sub(1, 16), pct, jstr)
            local bw = PANEL_W_POWER - 16
            local fill = math.max(0, math.floor(bw * r.ratio + 0.5))
            local bar_children = {}
            if fill > 0 then
                bar_children[#bar_children + 1] = {
                    id = "bar_fill_p_" .. i,
                    type = "panel",
                    rect = { w = fill },
                    style = { bg = bar_color(r.ratio), border = "transparent" },
                }
            end

            body[#body + 1] = {
                id = "row_bg_p_" .. i,
                type = "panel",
                layout = "column",
                gap = 0,
                rect = { h = ROW_H + BAR_H + 4 },
                padding = { left = 8, right = 8, top = 1, bottom = 3 },
                children = {
                    layout_label("row_txt_p_" .. i, line, 12, "#CBD5E1", "left", { h = ROW_H }),
                    {
                        id = "bar_bg_p_" .. i,
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

        if #rows > shown_b then
            body[#body + 1] = inset_label_slot("more_p", string.format("… +%d more", #rows - shown_b), ROW_H, 6, 6, 11, "#64748B", "left")
        end
    end

    return titled_panel_node(
        "deck_power",
        "power",
        PANEL_W_POWER,
        h_power,
        "frame_p",
        "title_p",
        string.format("REMOTE POWER - net %s", nid ~= 0 and tostring(nid) or "?"),
        "#0C1220",
        "#38BDF8",
        "#E0F2FE",
        body
    )
end

local function build_prod_panel_node(prod)
    local max_p = 8
    local shown_p = math.min(#prod, max_p)
    local body = {}
    local h_prod
    if #prod == 0 then
        h_prod = TITLE_H + 4 + ROW_H + 4
        body[#body + 1] = inset_label_slot("empty_g", "No generators or solar-style Ratio devices found.", ROW_H + 4, 6, 6, 12, "#94A3B8", "left")
    else
        h_prod = TITLE_H + shown_p * (ROW_H + 6)
        if #prod > shown_p then
            h_prod = h_prod + ROW_H + 4
        end
        for i = 1, shown_p do
            local r = prod[i]
            local val_txt
            if r.kind == "gen" then
                local ons = ""
                if r.on ~= nil then
                    ons = r.on ~= 0 and " ON" or " off"
                end
                val_txt = string.format("%d W%s", math.floor(r.value + 0.5), ons)
            else
                val_txt = string.format("%.1f%% cap", r.value * 100)
            end

            body[#body + 1] = {
                layout = "row",
                align = "center",
                gap = 8,
                rect = { h = ROW_H + 2 },
                padding = { left = 6, right = 6 },
                children = {
                    layout_label("name_g_" .. i, r.name, 12, "#BBF7D0", "left", nil, 1),
                    layout_label("val_g_" .. i, val_txt, 12, "#86EFAC", "right", { w = PROD_VAL_COL_W }),
                },
            }
        end

        if #prod > shown_p then
            body[#body + 1] = inset_label_slot("more_g", string.format("… +%d more", #prod - shown_p), ROW_H, 6, 6, 11, "#64748B", "left")
        end
    end

    return titled_panel_node(
        "deck_prod",
        "prod",
        PANEL_W_PROD,
        h_prod,
        "frame_g",
        "title_g",
        "REMOTE PRODUCTION",
        "#0C1A14",
        "#4ADE80",
        "#DCFCE7",
        body
    )
end

local function build_atmo_panel_node(atm)
    local max_a = 8
    local shown_a = math.min(#atm, max_a)
    local body = {}
    local h_atm
    if #atm == 0 then
        h_atm = TITLE_H + 4 + ROW_H + 4
        body[#body + 1] = inset_label_slot("empty_a", "No PressureInput devices (filtration, etc.).", ROW_H + 4, 6, 6, 12, "#94A3B8", "left")
    else
        h_atm = TITLE_H + shown_a * (ROW_H + 6)
        if #atm > shown_a then
            h_atm = h_atm + ROW_H + 4
        end
        for i = 1, shown_a do
            local r = atm[i]
            local tpart = r.temp and string.format("  T %.0f K", r.temp) or ""
            local line = string.format("%-12s  P %.0f%s", r.name:sub(1, 12), r.pressure, tpart)
            body[#body + 1] = inset_label_slot("row_a_" .. i, line, ROW_H + 2, 6, 6, 12, "#E9D5FF", "left")
        end

        if #atm > shown_a then
            body[#body + 1] = inset_label_slot("more_a", string.format("… +%d more", #atm - shown_a), ROW_H, 6, 6, 11, "#64748B", "left")
        end
    end

    return titled_panel_node(
        "deck_atmo",
        "atmo",
        PANEL_W_AUX,
        h_atm,
        "frame_a",
        "title_a",
        "REMOTE ATMOS",
        "#1A1030",
        "#C084FC",
        "#F3E8FF",
        body
    )
end

local function build_net_panel_node(nid, diag)
    local lines = {
        string.format("Network id   %s", nid ~= 0 and tostring(nid) or "?"),
        string.format("Devices      %d", diag.device_count),
        string.format("Lua chips    %d", diag.lua_chip_count),
        string.format("Batteries    %d", #diag.batteries),
        string.format("Prod. rows   %d", #diag.production),
        string.format("Atmo probes  %d", #diag.atmo),
        string.format("Charge tags  %d", diag.charge_count),
    }
    local body = {}
    for li = 1, #lines do
        body[#body + 1] = inset_label_slot("n" .. li, lines[li], ROW_H, 8, 8, 12, "#FED7AA", "left")
    end

    return titled_panel_node(
        "deck_net",
        "net",
        PANEL_W_AUX,
        TITLE_H + #lines * (ROW_H + 4),
        "frame_n",
        "title_n",
        "REMOTE NET",
        "#18120E",
        "#FB923C",
        "#FFEDD5",
        body
    )
end

local function rebuild(o, w, diag)
    hud:clear()

    -- hud:size() returns the wearer's actual visor canvas dims in every environment
    -- (single-player, listen host, dedicated server). No fallback math required.
    local sz = hud:size()
    local W, H = tonumber(sz.w), tonumber(sz.h)

    local ml, mr, mt, mb = scaled_margins(o, W, H)
    local innerW = math.max(80, W - ml - mr)
    local innerH = math.max(LINK_STRIP_H, H - mt - mb)
    local connected = w.available and w.connected

    load_offset("link")
    load_offset("power")
    load_offset("prod")
    load_offset("atmo")
    load_offset("net")

    local function draw_link_strip(text, bg, border, fg)
        local panel_w = math.min(PANEL_W_POWER, math.max(200, innerW * 0.45))
        local dx, dy =
            clamp_offset(ml, mt, panel_w, LINK_STRIP_H, W, H, off.link.dx, off.link.dy)
        store_offset("link", dx, dy)
        hud:layout({
            layout = "flex",
            direction = "row",
            align = "start",
            rect = { unit = "px", x = ml, y = mt, w = innerW, h = LINK_STRIP_H },
            children = {
                build_link_strip_node(panel_w, text, bg, border, fg),
            },
        })
        hud:commit()
    end

    if not w.available then
        draw_link_strip("VISOR - wireless status unavailable", "#1E1B4B", "#4338CA", "#C7D2FE")
        return
    end

    if not connected then
        local hint = "VISOR - NO DATA LINK"
        if w.in_range == false and (tonumber(w.network_id) or 0) ~= 0 then
            hint = hint .. "  (out of range / reconnecting)"
        elseif (tonumber(w.network_id) or 0) == 0 then
            hint = hint .. "  (pick a network on the visor)"
        end
        draw_link_strip(hint, "#1C1917", "#57534E", "#D6D3D1")
        return
    end

    local nid = tonumber(w.network_id) or 0

    -- Per-panel base position in the flex row..
    -- We mirror that math here ONLY to clamp each panel's saved drag offset
    -- against its on-screen bounding rect; the actual rendering still goes
    -- through hud:layout below so the row math itself stays declarative.
    local h_power = compute_power_h(diag.batteries)
    local h_prod = compute_prod_h(diag.production)
    local h_atmo = compute_atmo_h(diag.atmo)
    local h_net = compute_net_h()
    local power_x = ml
    local prod_x = power_x + PANEL_W_POWER + COL_GAP
    local atmo_x = prod_x + PANEL_W_PROD + COL_GAP
    local net_x = atmo_x + PANEL_W_AUX + COL_GAP

    do
        local dx, dy =
            clamp_offset(power_x, mt, PANEL_W_POWER, h_power, W, H, off.power.dx, off.power.dy)
        store_offset("power", dx, dy)
    end
    do
        local dx, dy =
            clamp_offset(prod_x, mt, PANEL_W_PROD, h_prod, W, H, off.prod.dx, off.prod.dy)
        store_offset("prod", dx, dy)
    end
    do
        local dx, dy =
            clamp_offset(atmo_x, mt, PANEL_W_AUX, h_atmo, W, H, off.atmo.dx, off.atmo.dy)
        store_offset("atmo", dx, dy)
    end
    do
        local dx, dy =
            clamp_offset(net_x, mt, PANEL_W_AUX, h_net, W, H, off.net.dx, off.net.dy)
        store_offset("net", dx, dy)
    end

    hud:layout({
        layout = "flex",
        direction = "row",
        align = "start",
        gap = COL_GAP,
        rect = { unit = "px", x = ml, y = mt, w = innerW, h = innerH },
        children = {
            build_power_panel_node(nid, diag.batteries),
            build_prod_panel_node(diag.production),
            build_atmo_panel_node(diag.atmo),
            build_net_panel_node(nid, diag),
        },
    })

    hud:commit()
end

hud:on_frame(function(_dt)
    local o = ss.client_overlay()
    local w = safe_wireless_status()
    local connected = w.available and w.connected
    local diag = connected and collect_diagnostics()
        or { batteries = {}, production = {}, atmo = {}, device_count = 0, lua_chip_count = 0, charge_count = 0 }
    local sig = build_data_signature(w, diag, connected)
    if sig ~= last_sig then
        last_sig = sig
        rebuild(o, w, diag)
    end
end)

local PERSIST_KEY = "layout"

local function persist_save_layout()
    local saved = {}
    for _, k in ipairs({ "link", "power", "prod", "atmo", "net" }) do
        local o = hud:drag_offset(OFFSET_IDS[k])
        saved[k] = { dx = o.dx, dy = o.dy }
    end
    local ok, json = pcall(util.json.encode, { v = 2, off = saved })
    if ok and json then ic.persist.set(PERSIST_KEY, json) end
end

local function persist_restore_layout()
    if not ic.persist.has(PERSIST_KEY) then return end
    local blob = ic.persist.get(PERSIST_KEY)
    if type(blob) ~= "string" or blob == "" then return end
    local ok, decoded = pcall(util.json.decode, blob)
    if not ok or type(decoded) ~= "table" then return end
    if tonumber(decoded.v) == 2 and type(decoded.off) == "table" then
        for _, k in ipairs({ "link", "power", "prod", "atmo", "net" }) do
            local t = decoded.off[k]
            if type(t) == "table" then
                local dx = tonumber(t.dx)
                local dy = tonumber(t.dy)
                if dx and dy and dx == dx and dy == dy then
                    store_offset(k, dx, dy)
                end
            end
        end
    elseif tonumber(decoded.v) == 1 then
        local dx = tonumber(decoded.lay_dx)
        local dy = tonumber(decoded.lay_dy)
        if dx and dy and dx == dx and dy == dy then
            store_offset("power", dx, dy)
        end
    end
end

local function persist_restore_and_rebuild()
    persist_restore_layout()
    local o = ss.client_overlay()
    local w = safe_wireless_status()
    local connected = w.available and w.connected
    local diag = connected and collect_diagnostics()
        or { batteries = {}, production = {}, atmo = {}, device_count = 0, lua_chip_count = 0, charge_count = 0 }
    last_sig = build_data_signature(w, diag, connected)
    rebuild(o, w, diag)
end

do
    local function on_layout_change()
        persist_save_layout()
        local o = ss.client_overlay()
        local w = safe_wireless_status()
        local connected = w.available and w.connected
        local diag = connected and collect_diagnostics()
            or { batteries = {}, production = {}, atmo = {}, device_count = 0, lua_chip_count = 0, charge_count = 0 }
        last_sig = build_data_signature(w, diag, connected)
        rebuild(o, w, diag)
    end
    hud:on_drag(on_layout_change)
    ss.hud.on_overlay_change(on_layout_change)
    persist_restore_and_rebuild()
end
