-- PrefabIconDemo.lua
-- Demonstrates prefab icon display on ScriptedScreens surfaces.
--
-- Wire a Dial (or any device with a Setting value) to d0 via the config screen.
-- The screen shows the corresponding ingot icon and name as you turn the dial.
-- The dial value (0..17) selects which ingot to display.

local ui = ss.ui.surface("main")
ss.ui.activate("main")

-- All ingot entries: { friendly name, enum value }
local ingots = {
    { "Iron Ingot",       ss.ui.icons.prefab.IronIngot },
    { "Steel Ingot",      ss.ui.icons.prefab.SteelIngot },
    { "Copper Ingot",     ss.ui.icons.prefab.CopperIngot },
    { "Gold Ingot",       ss.ui.icons.prefab.GoldIngot },
    { "Silver Ingot",     ss.ui.icons.prefab.SilverIngot },
    { "Nickel Ingot",     ss.ui.icons.prefab.NickelIngot },
    { "Lead Ingot",       ss.ui.icons.prefab.LeadIngot },
    { "Silicon Ingot",    ss.ui.icons.prefab.SiliconIngot },
    { "Electrum Ingot",   ss.ui.icons.prefab.ElectrumIngot },
    { "Solder Ingot",     ss.ui.icons.prefab.SolderIngot },
    { "Constantan Ingot", ss.ui.icons.prefab.ConstantanIngot },
    { "Invar Ingot",      ss.ui.icons.prefab.InvarIngot },
    { "Astroloy Ingot",   ss.ui.icons.prefab.AstroloyIngot },
    { "Hastelloy Ingot",  ss.ui.icons.prefab.HastelloyIngot },
    { "Waspaloy Ingot",   ss.ui.icons.prefab.WaspaloyIngot },
    { "Inconel Ingot",    ss.ui.icons.prefab.InconelIngot },
    { "Stellite Ingot",   ss.ui.icons.prefab.StelliteIngot },
}

local totalIngots = #ingots
local SETTING = ic.enums.LogicType.Setting
local lastIndex = -1

-- ── Build static UI ─────────────────────────────────────────────────────

local size = ui:size()
local W, H = size.w, size.h

ui:element({
    id = "bg",
    type = "panel",
    rect = { unit = "%", x = 0, y = 0, w = 100, h = 100 },
    style = { bg = "#0F172A" },
})

ui:element({
    id = "title",
    type = "label",
    rect = { unit = "px", x = 0, y = 10, w = W, h = 24 },
    props = { text = "Ingot Selector" },
    style = { color = "#94A3B8", font_size = 16, align = "center" },
})

ui:element({
    id = "icon",
    type = "icon",
    rect = { unit = "px", x = (W - 96) / 2, y = 50, w = 96, h = 96 },
    props = { name = ingots[1][2] },
    style = { tint = "#FFFFFF" },
})

ui:element({
    id = "name",
    type = "label",
    rect = { unit = "px", x = 0, y = 155, w = W, h = 24 },
    props = { text = ingots[1][1] },
    style = { color = "#E2E8F0", font_size = 18, align = "center" },
})

ui:element({
    id = "counter",
    type = "label",
    rect = { unit = "px", x = 0, y = 185, w = W, h = 20 },
    props = { text = "0 / " .. (totalIngots - 1) },
    style = { color = "#64748B", font_size = 12, align = "center" },
})

ui:element({
    id = "hint",
    type = "label",
    rect = { unit = "px", x = 0, y = H - 30, w = W, h = 20 },
    props = { text = "Turn the Dial on d0 to cycle ingots" },
    style = { color = "#475569", font_size = 10, align = "center" },
})

ui:commit()

-- ── Poll loop ───────────────────────────────────────────────────────────
-- Reads the Dial's Setting value each tick and updates the icon when it changes.

while true do
    local ok, raw = pcall(ic.logic.read, 0, SETTING)
    if ok and type(raw) == "number" then
        -- Wrap the dial value into our ingot range (1-indexed)
        local idx = (math.floor(raw) % totalIngots) + 1

        if idx ~= lastIndex then
            lastIndex = idx
            local entry = ingots[idx]

            -- Update icon and labels
            local icon = ui:get("icon")
            icon:set_props({ name = entry[2] })

            local name = ui:get("name")
            name:set_props({ text = entry[1] })

            local counter = ui:get("counter")
            counter:set_props({ text = math.floor(raw) .. " / " .. (totalIngots - 1) })
        end
    end

    ui:commit()
    sleep(0.25)
end
