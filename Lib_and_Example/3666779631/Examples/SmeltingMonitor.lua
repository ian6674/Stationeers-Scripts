--[[
    SmeltingMonitor.lua

    A ScriptedScreens display that uses the "smelting" library module
    from a library chip on the same data cable network.

    Shows live furnace temperature/pressure with recipe range checking,
    recipe lookup, and ingredient lists - all powered by the shared
    smelting library rather than hardcoded recipe data.

    SETUP:
      1. Place LibraryModule_Smelting.lua on a Lua chip in an IC Housing
      2. Put this script on a ScriptedScreens motherboard on the SAME data network
      3. Wire d0 to a Furnace (reads Temperature + Pressure)

    FEATURES:
      - Live furnace gauges (temperature + pressure)
      - Recipe selector with prev/next buttons
      - Color-coded range status from smelting.check_range()
      - Ingredient list and notes from recipe database
      - Celsius/Kelvin display
      - Persists selected recipe across saves
]]

-- Load the smelting library from a library chip on the data network
local smelt = require("smelting")

local ui = ss.ui.surface("main")
ss.ui.activate("main")

local size = ui:size()
local W, H = 480, 272
if size then W, H = size.w or W, size.h or H end

local LT = ic.enums.LogicType

-- ── Theme ──────────────────────────────────────────────────────────────────────
local C = {
    bg      = "#080C18",
    panel   = "#111827",
    header  = "#0F172A",
    card    = "#1E293B",
    text    = "#E2E8F0",
    dim     = "#94A3B8",
    muted   = "#475569",
    accent  = "#F59E0B",
    green   = "#22C55E",
    yellow  = "#EAB308",
    orange  = "#F97316",
    red     = "#EF4444",
    blue    = "#3B82F6",
}

-- ── State ──────────────────────────────────────────────────────────────────────
local selectedRecipe = 1
local recipeList     = smelt.list()
local connected      = false
local furnaceTemp    = nil
local furnacePressure = nil

-- ── Helpers ────────────────────────────────────────────────────────────────────
local function fmt(v, d)
    if v == nil then return "--" end
    return string.format("%." .. (d or 1) .. "f", v)
end

local function status_color(status)
    if status == "IN RANGE"       then return C.green end
    if status == "TOO COLD"       then return C.blue end
    if status == "TOO HOT"        then return C.red end
    if status == "OVER PRESSURE"  then return C.orange end
    if status == "UNDER PRESSURE" then return C.yellow end
    return C.muted
end

-- ── Render ─────────────────────────────────────────────────────────────────────
local function render()
    ui:clear()

    local recipe = smelt.recipes[selectedRecipe]
    if not recipe then return end

    -- Check range using the library
    local in_range, status = false, "OFFLINE"
    if connected and furnaceTemp then
        in_range, status = smelt.check_range(recipe, furnaceTemp, furnacePressure)
    end
    local sColor = status_color(status)

    -- Temperature in Celsius
    local temp_c = furnaceTemp and smelt.k_to_c(furnaceTemp) or nil

    -- Format inputs using the library helper
    local inputsStr = smelt.format_inputs(recipe)
    local rangeStr  = smelt.format_temp_range(recipe, false)

    -- Target completion percentage
    local targetPct = 0
    if connected and furnaceTemp and recipe.temp_min and recipe.temp_min > 0 then
        targetPct = math.min(100, furnaceTemp / recipe.temp_min * 100)
    end

    -- ── Background ─────────────────────────────────────────────────────────
    ui:element({
        id = "bg", type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = H },
        style = { bg = C.bg },
    })

    -- ── Build ingredient children dynamically ──────────────────────────────
    local ingredientChildren = {}
    for i, inp in ipairs(recipe.inputs) do
        ingredientChildren[#ingredientChildren + 1] = {
            id = "in_" .. i, type = "label", rect = { h = 15 },
            props = { text = "  " .. inp.count .. "x " .. inp.item },
            style = { font_size = 10, color = C.text, align = "left" },
        }
    end

    -- ── Layout ─────────────────────────────────────────────────────────────
    ui:layout({
        layout = "flex", direction = "column", gap = 0,
        rect = { unit = "px", x = 0, y = 0, w = W, h = H },
        children = {
            -- Header
            {
                id = "hdr", type = "panel", rect = { h = 30 },
                style = { bg = C.header },
                layout = "flex", direction = "row", gap = 0,
                padding = { left = 10, right = 10, top = 5, bottom = 5 },
                children = {
                    {
                        id = "title", type = "label", flex = 1,
                        props = { text = "SMELTING MONITOR" },
                        style = { font_size = 14, color = C.accent, align = "left" },
                    },
                    {
                        id = "conn", type = "label", rect = { w = 120 },
                        props = { text = connected and "FURNACE OK" or "NO FURNACE (d0)" },
                        style = { font_size = 10, color = connected and C.green or C.red, align = "right" },
                    },
                },
            },

            -- Body: left (gauges + status) + right (recipe details)
            {
                layout = "flex", flex = 1, direction = "row", gap = 6, padding = 6,
                children = {
                    -- Left column: gauges and PID
                    {
                        layout = "flex", flex = 1, direction = "column", gap = 4,
                        children = {
                            -- Gauge row
                            {
                                layout = "flex", rect = { h = 80 }, direction = "row", gap = 4,
                                children = {
                                    {
                                        id = "g_temp", type = "gauge", flex = 1,
                                        props = {
                                            value = fmt(furnaceTemp, 0),
                                            min = "0", max = "1600",
                                            warn = "0.50", danger = "0.85",
                                            label = "TEMP", unit = " K",
                                        },
                                        style = {
                                            bg = C.panel, arc_thickness = "6",
                                            font_size = "9",
                                            value_color = sColor,
                                            label_color = C.dim,
                                        },
                                    },
                                    {
                                        id = "g_press", type = "gauge", flex = 1,
                                        props = {
                                            value = fmt(furnacePressure, 1),
                                            min = "0", max = "200",
                                            warn = "0.65", danger = "0.85",
                                            label = "PRESS", unit = " kPa",
                                        },
                                        style = {
                                            bg = C.panel, arc_thickness = "6",
                                            font_size = "9",
                                            value_color = C.text,
                                            label_color = C.dim,
                                        },
                                    },
                                },
                            },

                            -- Celsius readout
                            {
                                id = "celsius", type = "label", rect = { h = 14 },
                                props = { text = temp_c and (fmt(temp_c, 1) .. " °C") or "--- °C" },
                                style = { font_size = 10, color = C.dim, align = "center" },
                            },

                            -- Target range
                            {
                                id = "range", type = "label", rect = { h = 14 },
                                props = { text = "TARGET: " .. rangeStr },
                                style = { font_size = 9, color = C.dim, align = "left" },
                            },

                            -- Progress bar
                            {
                                id = "prog", type = "progress", rect = { h = 8 },
                                props = { value = tostring(targetPct), min = "0", max = "100" },
                                style = { bg = "#1A1A2E", fill = sColor },
                            },

                            -- Status badge
                            {
                                id = "status_bg", type = "panel", rect = { h = 24 },
                                style = { bg = sColor .. "20" },
                                layout = "flex", direction = "row", gap = 6,
                                padding = { left = 8, top = 4, bottom = 4 },
                                children = {
                                    {
                                        id = "status_dot", type = "panel",
                                        rect = { w = 8, h = 8 },
                                        style = { bg = sColor },
                                    },
                                    {
                                        id = "status_txt", type = "label", flex = 1,
                                        props = { text = status },
                                        style = { font_size = 12, color = sColor, align = "left" },
                                    },
                                },
                            },
                        },
                    },

                    -- Right column: recipe details
                    {
                        id = "rpanel", type = "panel", rect = { w = 190 },
                        style = { bg = C.panel },
                        layout = "flex", direction = "column", gap = 3,
                        padding = 6,
                        children = (function()
                            local ch = {
                                -- Recipe name
                                {
                                    id = "rname", type = "label", rect = { h = 20 },
                                    props = { text = recipe.name },
                                    style = { font_size = 14, color = C.text, align = "center" },
                                },
                                -- Divider
                                {
                                    id = "div1", type = "divider", rect = { h = 1 },
                                    style = { color = C.muted },
                                },
                                -- Ingredients header
                                {
                                    id = "lbl_in", type = "label", rect = { h = 14 },
                                    props = { text = "INGREDIENTS" },
                                    style = { font_size = 9, color = C.dim, align = "left" },
                                },
                            }

                            -- Add ingredient rows
                            for i, c in ipairs(ingredientChildren) do
                                ch[#ch + 1] = c
                            end

                            -- Divider
                            ch[#ch + 1] = {
                                id = "div2", type = "divider", rect = { h = 1 },
                                style = { color = C.muted },
                            }

                            -- Notes
                            if recipe.notes then
                                ch[#ch + 1] = {
                                    id = "notes", type = "label", flex = 1,
                                    props = { text = recipe.notes },
                                    style = { font_size = 9, color = C.dim, align = "left" },
                                }
                            end

                            -- Page counter
                            ch[#ch + 1] = {
                                id = "pg", type = "label", rect = { h = 12 },
                                props = { text = selectedRecipe .. " / " .. #recipeList },
                                style = { font_size = 8, color = C.muted, align = "center" },
                            }

                            -- Nav buttons
                            ch[#ch + 1] = {
                                layout = "flex", rect = { h = 26 }, direction = "row", gap = 4,
                                children = {
                                    {
                                        id = "bp", type = "button", flex = 1,
                                        props = { text = "< PREV" },
                                        style = { bg = C.card, text = C.text, font_size = 10 },
                                        on_click = function()
                                            selectedRecipe = selectedRecipe - 1
                                            if selectedRecipe < 1 then selectedRecipe = #smelt.recipes end
                                            persist_save_recipe()
                                            render()
                                        end,
                                    },
                                    {
                                        id = "bn", type = "button", flex = 1,
                                        props = { text = "NEXT >" },
                                        style = { bg = C.card, text = C.text, font_size = 10 },
                                        on_click = function()
                                            selectedRecipe = selectedRecipe + 1
                                            if selectedRecipe > #smelt.recipes then selectedRecipe = 1 end
                                            persist_save_recipe()
                                            render()
                                        end,
                                    },
                                },
                            }

                            return ch
                        end)(),
                    },
                },
            },
        },
    })

    ui:commit()
end

-- ── Persistence (ic.persist) ───────────────────────────────────────────────────
local PERSIST_KEY = "recipe"

local function persist_restore_recipe()
    if not ic.persist.has(PERSIST_KEY) then return end
    local val = ic.persist.get(PERSIST_KEY)
    if type(val) == "string" and val ~= "" then
        selectedRecipe = math.max(1, math.min(#smelt.recipes, tonumber(val) or 1))
    end
end

local function persist_save_recipe()
    ic.persist.set(PERSIST_KEY, tostring(selectedRecipe))
end

persist_restore_recipe()

-- ── Main loop ──────────────────────────────────────────────────────────────────
render()

local tickCount = 0
while true do
    tickCount = tickCount + 1

    -- Read furnace on d0
    local temp  = ic.read(0, LT.Temperature)
    local press = ic.read(0, LT.Pressure)

    local wasConnected = connected
    connected       = (temp ~= nil)
    furnaceTemp     = temp
    furnacePressure = press

    -- Re-render ~once per second or on connection change
    if tickCount % 10 == 0 or (connected ~= wasConnected) then
        render()
    end

    yield()
end
