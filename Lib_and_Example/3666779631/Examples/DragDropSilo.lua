-- DragDropSilo.lua
-- Full-surface payload drag/drop demo: drag ingot thumbnails onto silo drop zones.
-- Each silo accumulates every accepted drop (shown as a grid of icons inside).
-- **`ss.ui`** (motherboard or tablet). Engine: **`drag_source`** / **`drag_payload`**
-- on source icons and **`drop_target`** (+ **`drop_accepts`**, **`drop_dispatch_id`**)
-- on the destination silos.
-- While dragging, the engine clones the source icon under the cursor and dims the
-- source slot. This is payload DnD, not panel reposition drag, so it does NOT use
-- `draggable` / `drag_bounds`.
-- Uses element callbacks instead of a `poll_input()` drain:
-- **`handle:on("drag_payload_begin")`**, **`handle:on("drop")`**, and
-- **`handle:on("drag_payload_cancel")`**.
-- **`interface_button`** (INTERFACE): opens **Interface Mode** so keyboard events
-- reach the surface (see input-events guide).

local IFACE_W, IFACE_H = 108, 28

local ui = ss.ui.surface("main")
ss.ui.activate("main")

local last_sw, last_sh

local status_txt =
    "Drag an ingot from the top row onto a silo. LEFT accepts any ingot. MIDDLE whitelists all three. RIGHT rejects iron."

-- Accumulated drops per silo: dispatch_id → ordered list of payload tokens.
local silo_items = {
    silo_any     = {},
    silo_mixed   = {},
    silo_partial = {},
}

local MAX_SILO_ITEMS = 12

local PAYLOAD_LABELS = {
    ItemSteelIngot = "Steel",
    ItemIronIngot = "Iron",
    ItemGoldIngot = "Gold",
}

local INGOTS = {
    { id = "ingot_steel", payload = "ItemSteelIngot", label = "STEEL", tint = "#CBD5E1", slot_bg = "#1E293B", slot_border = "#64748B" },
    { id = "ingot_iron",  payload = "ItemIronIngot",  label = "IRON",  tint = "#CBD5E1", slot_bg = "#1E293B", slot_border = "#64748B" },
    { id = "ingot_gold",  payload = "ItemGoldIngot",  label = "GOLD",  tint = "#FDE047", slot_bg = "#3F2A05", slot_border = "#F59E0B" },
}

local SILOS = {
    {
        i = 0,
        pid = "silo_any",
        dispatch = "silo_any",
        label = "ANY INGOT",
        accepts_desc = "accepts any ingot",
        border = "#22C55E",
        bg = "#14532DCC",
        accepts = nil,
    },
    {
        i = 1,
        pid = "silo_mixed",
        dispatch = "silo_mixed",
        label = "ALL 3 (LIST)",
        accepts_desc = "accepts steel, iron, gold",
        border = "#38BDF8",
        bg = "#1E293BCC",
        accepts = { "ItemSteelIngot", "ItemIronIngot", "ItemGoldIngot" },
    },
    {
        i = 2,
        pid = "silo_partial",
        dispatch = "silo_partial",
        label = "STEEL + GOLD",
        accepts_desc = "rejects iron",
        border = "#F59E0B",
        bg = "#422006CC",
        accepts = { "ItemSteelIngot", "ItemGoldIngot" },
    },
}

local function payload_label(payload)
    return PAYLOAD_LABELS[payload] or payload or "?"
end

local function surface_wh()
    local sz = ui:size()
    if type(sz) ~= "table" then
        return 960, 540
    end
    return math.max(320, tonumber(sz.w) or 960), math.max(240, tonumber(sz.h) or 540)
end

local function fs_title(W) return math.max(13, math.min(22, math.floor(W / 52))) end
local function fs_body(W)  return math.max(9, math.min(14, math.floor(W / 72))) end

local PERSIST_KEY = "silo"

local function persist_save_silo()
    local state = {
        v = 3,
        silo_any = silo_items.silo_any,
        silo_mixed = silo_items.silo_mixed,
        silo_partial = silo_items.silo_partial,
    }
    local ok, json = pcall(util.json.encode, state)
    if ok and json then ic.persist.set(PERSIST_KEY, json) end
end

local function persist_restore_silo()
    if not ic.persist.has(PERSIST_KEY) then return end
    local blob = ic.persist.get(PERSIST_KEY)
    if type(blob) ~= "string" or blob == "" then return end
    local ok, d = pcall(util.json.decode, blob)
    if not ok or type(d) ~= "table" then return end

    for _, key in ipairs({ "silo_any", "silo_mixed", "silo_partial" }) do
        if type(d[key]) == "table" then
            local clean = {}
            for i = 1, math.min(#d[key], MAX_SILO_ITEMS) do
                if type(d[key][i]) == "string" and d[key][i] ~= "" then
                    clean[#clean + 1] = d[key][i]
                end
            end
            silo_items[key] = clean
        else
            silo_items[key] = {}
        end
    end
end

local function rebuild()
    local W, H = surface_wh()
    local pad   = math.max(12, math.min(28, math.floor(W * 0.025)))
    local gap   = math.max(8,  math.min(20, math.floor(W * 0.015)))
    local title_fs = fs_title(W)
    local body_fs  = fs_body(W)

    local header_h  = math.max(28, math.floor(title_fs * 1.6))
    local status_h  = math.max(32, math.floor(body_fs * 3.0))
    local ingot_row = math.max(86, math.floor(H * 0.18))
    local silo_top  = pad + header_h + status_h + gap + ingot_row + gap
    local silo_h    = math.max(100, H - silo_top - pad)
    local col_w     = math.floor((W - 2 * pad - 2 * gap) / 3)

    ui:clear()

    -- Full backdrop.
    ui:element({
        id = "bg", type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = H },
        style = { bg = "#020617" },
    })

    -- Title + Interface Mode (keyboard focus for this surface).
    local title_w = math.max(120, W - 2 * pad - IFACE_W - 8)
    ui:element({
        id = "title", type = "label",
        rect = { unit = "px", x = pad, y = pad, w = title_w, h = header_h },
        props = { text = "SILO ROUTER - drag & drop" },
        style = { font_size = title_fs, color = "#E2E8F0", align = "left" },
    })
    ui:element({
        id = "iface_btn",
        type = "interface_button",
        rect = { unit = "px", x = W - pad - IFACE_W, y = pad, w = IFACE_W, h = math.min(IFACE_H, header_h) },
        props = { text = "INTERFACE", z_index = 50 },
        style = { bg = "#422006", text = "#FDE68A", font_size = math.max(7, math.min(9, body_fs - 1)) },
    })

    -- Status line.
    ui:element({
        id = "status", type = "label",
        rect = { unit = "px", x = pad, y = pad + header_h, w = W - 2 * pad, h = status_h },
        props = { text = status_txt },
        style = { font_size = body_fs, color = "#94A3B8", align = "left" },
    })

    -- Ingot source row.
    local ingot_y = pad + header_h + status_h + gap
    local function col_x(i0) return pad + i0 * (col_w + gap) end

    local slot_pad = 6
    local slot_label_h = math.max(18, math.floor(body_fs * 1.6))
    local icon_h = math.max(40, ingot_row - slot_label_h - slot_pad * 2 - 2)
    -- Make the draggable icon RT square and centered inside its slot so the visible
    -- (preserveAspect) sprite tightly fills its RectTransform. Otherwise the engine
    -- clones the full rect for the drag ghost; preserving the grab offset across a
    -- wide-but-mostly-empty rect makes the cursor look far off-center from the visible
    -- ingot image during the drag.
    local icon_size = math.max(32, math.min(col_w - slot_pad * 2, icon_h))
    for i, def in ipairs(INGOTS) do
        local x = col_x(i - 1)
        ui:element({
            id = def.id .. "_slot", type = "panel",
            rect = { unit = "px", x = x, y = ingot_y, w = col_w, h = ingot_row },
            style = { bg = def.slot_bg, border = def.slot_border, border_width = 2 },
        })
        local icon_x = x + math.floor((col_w - icon_size) / 2)
        local icon_y = ingot_y + slot_pad + math.max(0, math.floor((icon_h - icon_size) / 2))
        ui:element({
            id = def.id, type = "icon",
            rect = { unit = "px", x = icon_x, y = icon_y, w = icon_size, h = icon_size },
            props = { name = "prefab:" .. def.payload, drag_source = "true", drag_payload = def.payload },
            style = { tint = def.tint },
        })
        ui:element({
            id = def.id .. "_lbl", type = "label",
            rect = { unit = "px", x = x + slot_pad, y = ingot_y + slot_pad + icon_h + 2, w = col_w - slot_pad * 2, h = slot_label_h },
            props = { text = def.label .. "  - drag source" },
            style = { font_size = body_fs, color = "#E2E8F0", align = "center" },
        })
    end

    -- Silo columns.
    for _, s in ipairs(SILOS) do
        local x = col_x(s.i)
        local lbl_h = math.max(22, math.floor(silo_h * 0.10))
        local sub_h = math.max(18, math.floor(body_fs * 1.5))
        local props = { drop_target = "true", drop_dispatch_id = s.dispatch }
        if s.accepts then props.drop_accepts = s.accepts end

        ui:element({
            id = s.pid, type = "panel",
            rect = { unit = "px", x = x, y = silo_top, w = col_w, h = silo_h },
            props = props,
            style = { bg = s.bg, border = s.border, border_width = 2 },
        })

        ui:element({
            id = s.pid .. "_hdr", type = "label",
            rect = { unit = "px", x = x + 4, y = silo_top + 4, w = col_w - 8, h = lbl_h },
            props = { text = s.label },
            style = { font_size = body_fs, color = "#F8FAFC", align = "center" },
        })
        ui:element({
            id = s.pid .. "_sub", type = "label",
            rect = { unit = "px", x = x + 6, y = silo_top + 6 + lbl_h, w = col_w - 12, h = sub_h },
            props = { text = s.accepts_desc },
            style = { font_size = math.max(9, body_fs - 1), color = "#CBD5E1", align = "center" },
        })

        -- Held items grid.
        local items = silo_items[s.dispatch] or {}
        local n = #items
        local content_y = silo_top + lbl_h + sub_h + 10
        local content_h = silo_h - lbl_h - sub_h - 16
        if n > 0 then
            local cols = math.max(1, math.min(4, math.ceil(math.sqrt(n))))
            local rows = math.ceil(n / cols)
            local cell_w = math.floor((col_w - 8) / cols)
            local cell_h = math.min(cell_w, math.floor(content_h / rows))
            for idx, payload in ipairs(items) do
                local r = math.floor((idx - 1) / cols)
                local c = (idx - 1) % cols
                local ix = x + 4 + c * cell_w
                local iy = content_y + r * cell_h
                local tint = (payload == "ItemGoldIngot") and "#FDE047" or "#CBD5E1"
                ui:element({
                    id = s.pid .. "_i" .. tostring(idx), type = "icon",
                    rect = { unit = "px", x = ix, y = iy, w = cell_w, h = cell_h },
                    props = { name = "prefab:" .. payload },
                    style = { tint = tint },
                })
            end
        else
            ui:element({
                id = s.pid .. "_empty", type = "label",
                rect = { unit = "px", x = x + 6, y = content_y + math.floor(content_h * 0.35), w = col_w - 12, h = 32 },
                props = { text = "Drop ingots here" },
                style = { font_size = body_fs - 1, color = "#64748B", align = "center" },
            })
        end

        -- Item count badge.
        if n > 0 then
            ui:element({
                id = s.pid .. "_cnt", type = "label",
                rect = { unit = "px", x = x + col_w - 48, y = silo_top + 4, w = 44, h = lbl_h },
                props = { text = tostring(n) .. "/" .. tostring(MAX_SILO_ITEMS) },
                style = { font_size = body_fs - 2, color = "#94A3B8", align = "right" },
            })
        end
    end

    persist_save_silo()
    ui:commit()
    wire_callbacks()
end

local function set_status(text)
    status_txt = text
    local lbl = ui:get("status")
    if lbl then
        pcall(function()
            lbl:set_props({ text = status_txt })
        end)
    end
end

function wire_callbacks()
    for _, def in ipairs(INGOTS) do
        local src = ui:get(def.id)
        if src then
            src:on("drag_payload_begin", function(payload)
                set_status(string.format(
                    "Dragging %s from %s. Drop it on a silo.",
                    payload_label(payload),
                    def.id
                ))
            end)
            src:on("drag_payload_cancel", function(payload)
                set_status(string.format(
                    "Cancelled / rejected: %s from %s.",
                    payload_label(payload),
                    def.id
                ))
            end)
        end
    end

    for _, s in ipairs(SILOS) do
        local silo = ui:get(s.pid)
        if silo then
            silo:on("drop", function(val)
                local payload, source_id, target_id = string.match(tostring(val or ""), "^([^&]+)&([^&]+)&([^&]+)$")
                local list = silo_items[s.dispatch]
                if not list or not payload then
                    return
                end

                if #list < MAX_SILO_ITEMS then
                    list[#list + 1] = payload
                    set_status(string.format(
                        "Accepted %s from %s → %s (%d/%d held).",
                        payload_label(payload),
                        source_id or "?",
                        target_id or s.dispatch,
                        #list,
                        MAX_SILO_ITEMS
                    ))
                    rebuild()
                else
                    set_status(string.format(
                        "Full: %s rejected by %s (%d/%d).",
                        payload_label(payload),
                        target_id or s.dispatch,
                        #list,
                        MAX_SILO_ITEMS
                    ))
                end
            end)
        end
    end
end

persist_restore_silo()

function tick()
    -- Watch for surface-size changes and rebuild when needed. Safe to coexist with
    -- on_frame because tick() returns synchronously without yielding (the runtime's
    -- "on_frame skipped while tick yielded" guard would otherwise halt the chip
    -- with a clear runtime error).
    local W, H = surface_wh()
    if W ~= last_sw or H ~= last_sh then
        last_sw, last_sh = W, H
        rebuild()
    end
end

do
    local W, H = surface_wh()
    last_sw, last_sh = W, H
    rebuild()
end
