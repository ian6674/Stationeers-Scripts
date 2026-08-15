-- PrefabThumbnailColorDemo.lua
-- Showcases `type = "icon"` with `icon_type = "prefab"` for real game prefabs and
-- `color_index` for painted thumbnail variants (same path as `Thing.GetThumbnail(prefab, n)`).
--
-- Prefab name strings in `container_prefabs` are taken from
-- `StationeersSrc/Assembly-CSharp/Assets/Scripts/Objects/Container.cs`
-- (`Prefab.Find<Item>("…")` training-container lists). `ItemPortablesConnector` is omitted
-- here because its prefab often has no inventory thumbnail (blank / white square in UI).
--
-- Optional: wire a Dial to d0. Its Setting value cycles which stackable is used
-- for the bottom `color_index` row (iron frames, steel sheets, copper sheets, …).

local ui = ss.ui.surface("main")
ss.ui.activate("main")

local SETTING = ic.enums.LogicType.Setting

-- Short labels + prefab strings from Container.cs (Prefab.Find<Item>(...)).
-- `ItemCableCoil` is from the same file (replaces connector: connector prefab has no thumbnail).
local container_prefabs = {
    { "ItemKitArcFurnace",   "KitArcFurnace" },
    { "ItemKitAutolathe",    "KitAutolathe" },
    { "ItemIronFrames",      "IronFrames" },
    { "ItemIronSheets",      "IronSheets" },
    { "ItemGlassSheets",     "GlassSheets" },
    { "ItemKitWallIron",     "KitWallIron" },
    { "ItemKitSolarPanel",   "KitSolar" },
    { "ItemCableCoil",       "CableCoil" },
}

local paint_targets = {
    { "ItemIronFrames",    "Iron frames" },
    { "ItemSteelSheets",   "Steel sheets" },
    { "ItemIronSheets",    "Iron sheets" },
    { "ItemCopperSheets",   "Copper sheets" },
    { "ItemGoldSheets",    "Gold sheets" },
    { "ItemSteelFrames",   "Steel frames" },
}

local num_colors = 6
local last_dial = -1
local paint_idx = 1

local size = ui:size()
local W, H = size.w, size.h
local hint_h = 18
local pad_x = 8
local inner_w = W - 2 * pad_x

-- Running Y (px, top-left). No negative offsets: every section is placed below the previous one.
local y = 6

ui:element({
    id = "bg",
    type = "panel",
    rect = { unit = "%", x = 0, y = 0, w = 100, h = 100 },
    style = { bg = "#0B1120" },
})

local function place_label(id, text, h, font_size, color, align)
    align = align or "center"
    ui:element({
        id = id,
        type = "label",
        rect = { unit = "px", x = pad_x, y = y, w = inner_w, h = h },
        props = { text = text },
        style = { color = color or "#94A3B8", font_size = font_size or 10, align = align },
    })
    y = y + h
end

place_label("title", "Prefab thumbnails + color_index", 20, 14, "#E2E8F0", "center")
place_label(
    "src_note",
    "A) Container.cs Item prefabs   B) explicit prefab icons   C) color_index 0..5 (Dial d0)",
    22,
    8,
    "#64748B",
    "center"
)

local cols = 4
local n_container = #container_prefabs
local container_rows = math.ceil(n_container / cols)

-- Shrink grid cells until the full layout fits above the footer (typ. 480x272).
local cell, lbl_h, row_gap, ecell, paint_cw
for try = 1, 5 do
    cell = math.max(22, math.min(34, math.floor((inner_w - (cols - 1) * 4) / cols) - (try - 1) * 2))
    lbl_h = 11
    row_gap = 8
    local row_stride = cell + 4 + lbl_h + row_gap
    local grid_h = container_rows * row_stride

    ecell = math.max(22, math.min(32, cell))
    local enum_row_h = ecell + 4 + lbl_h

    paint_cw = math.floor((inner_w - (num_colors - 1) * 4) / num_colors)
    paint_cw = math.max(20, math.min(paint_cw, 36))

    local paint_block = 12 + 14 + 4 + paint_cw + 4 + lbl_h + 6
    local total = y + 12 + grid_h + 10 + 12 + enum_row_h + 10 + paint_block + hint_h + 6
    if total <= H then
        break
    end
end

place_label("hdr_container", "A) Raw prefab strings (icon_type = prefab)", 13, 9, "#64748B", "center")
y = y + 4

local gap = 4
local base_x = math.floor((W - (cols * cell + (cols - 1) * gap)) / 2)
local grid_top = y
local row_stride = cell + 4 + lbl_h + row_gap

for i, entry in ipairs(container_prefabs) do
    local prefab, short = entry[1], entry[2]
    local col = (i - 1) % cols
    local row = math.floor((i - 1) / cols)
    local x = base_x + col * (cell + gap)
    local iy = grid_top + row * row_stride
    local id = "cpre_" .. i
    ui:element({
        id = id,
        type = "icon",
        rect = { unit = "px", x = x, y = iy, w = cell, h = cell },
        props = { icon_type = "prefab", name = prefab },
        style = { tint = "#FFFFFF" },
    })
    ui:element({
        id = id .. "_lbl",
        type = "label",
        rect = { unit = "px", x = x, y = iy + cell + 3, w = cell, h = lbl_h },
        props = { text = short },
        style = { color = "#94A3B8", font_size = 8, align = "center" },
    })
end

y = grid_top + container_rows * row_stride + 10

place_label("hdr_enum", "B) Specific prefabs", 13, 9, "#64748B", "center")
y = y + 4

local enum_defs = {
    { lab = "Arc furnace", props = { icon_type = "prefab", name = "StructureArcFurnace" } },
    { lab = "Steel ingot", props = { icon_type = "prefab", name = "ItemSteelIngot" } },
    { lab = "Gas Canister", props = { icon_type = "prefab", name = "ItemGasCanisterEmpty" } },
}
local ec = #enum_defs
local egap = 8
local ebase = math.floor((W - (ec * ecell + (ec - 1) * egap)) / 2)
local enum_row_top = y

for i, def in ipairs(enum_defs) do
    local plab, props = def.lab, def.props
    local x = ebase + (i - 1) * (ecell + egap)
    ui:element({
        id = "enum_" .. i,
        type = "icon",
        rect = { unit = "px", x = x, y = enum_row_top, w = ecell, h = ecell },
        props = props,
        style = { tint = "#FFFFFF" },
    })
    ui:element({
        id = "enum_" .. i .. "_lbl",
        type = "label",
        rect = { unit = "px", x = x, y = enum_row_top + ecell + 3, w = ecell, h = lbl_h },
        props = { text = plab },
        style = { color = "#94A3B8", font_size = 8, align = "center" },
    })
end

y = enum_row_top + ecell + 4 + lbl_h + 10

place_label("hdr_paint", "C) color_index 0..5 (same prefab)", 12, 9, "#64748B", "center")
y = y + 2

ui:element({
    id = "paint_target_lbl",
    type = "label",
    rect = { unit = "px", x = pad_x, y = y, w = inner_w, h = 14 },
    props = { text = paint_targets[1][2] .. " (" .. paint_targets[1][1] .. ")" },
    style = { color = "#38BDF8", font_size = 9, align = "center" },
})
y = y + 16

local icy = y
local cx0 = math.floor((W - (num_colors * paint_cw + (num_colors - 1) * 4)) / 2)

for i = 0, num_colors - 1 do
    local x = cx0 + i * (paint_cw + 4)
    local pid = "paint_" .. i
    ui:element({
        id = pid,
        type = "icon",
        rect = { unit = "px", x = x, y = icy, w = paint_cw, h = paint_cw },
        props = {
            icon_type = "prefab",
            name = paint_targets[1][1],
            color_index = i,
        },
        style = { tint = "#FFFFFF" },
    })
    ui:element({
        id = pid .. "_ix",
        type = "label",
        rect = { unit = "px", x = x, y = icy + paint_cw + 3, w = paint_cw, h = lbl_h },
        props = { text = tostring(i) },
        style = { color = "#475569", font_size = 8, align = "center" },
    })
end

y = icy + paint_cw + 4 + lbl_h + 6

-- Footer: prefer bottom of surface; if that would sit on top of content, drop it below the paint row.
local hint_y = H - hint_h - 2
if hint_y < y then
    hint_y = y
end

ui:element({
    id = "hint",
    type = "label",
    rect = { unit = "px", x = pad_x, y = hint_y, w = inner_w, h = hint_h },
    props = { text = "Dial d0 Setting cycles paint row prefab (optional)" },
    style = { color = "#334155", font_size = 8, align = "center" },
})

ui:commit()

local function apply_paint_row(target_index)
    local t = paint_targets[target_index]
    if not t then
        return
    end
    local prefab = t[1]
    for i = 0, num_colors - 1 do
        local h = ui:get("paint_" .. i)
        h:set_props({
            icon_type = "prefab",
            name = prefab,
            color_index = i,
        })
    end
    local lbl = ui:get("paint_target_lbl")
    lbl:set_props({ text = t[2] .. " (" .. prefab .. ")" })
end

while true do
    local ok, raw = pcall(ic.logic.read, 0, SETTING)
    if ok and type(raw) == "number" then
        local v = math.floor(raw)
        if v ~= last_dial then
            last_dial = v
            paint_idx = (v % #paint_targets) + 1
            apply_paint_row(paint_idx)
        end
    end
    ui:commit()
    sleep(0.25)
end
