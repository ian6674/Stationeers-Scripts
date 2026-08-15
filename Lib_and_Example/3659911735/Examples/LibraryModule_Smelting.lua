--@module smelting
-- LibraryModule_Smelting.lua
-- Complete smelting recipe database for Stationeers furnaces.
-- Other Lua chips on the same data network load this via: local smelting = require("smelting")
--
-- HOW TO USE:
--   1. Put this script on a Lua chip and insert it into an IC Housing.
--   2. The housing must be powered and on the same data cable network as consumer chips.
--   3. Any chip on the same network can call: local smelting = require("smelting")
--
-- FEATURES:
--   - Recipe database with input/output items, temperature ranges, pressure limits
--   - Lookup by output name, input ingredient, or furnace type
--   - Temperature/pressure range checking for active furnace monitoring
--
-- NOTE: Actual smelting recipes are defined in the game's XML data files, not
-- hardcoded in C#. The recipes below are based on well-known community data.
-- Temperature ranges and ratios may change with game updates; verify in-game
-- via Stationpedia if in doubt.

local smelting         = {}

-- ── Prefab Hashes ──────────────────────────────────────────────────────────────
-- Use ic.hash("ItemFurnace") etc. in-game to get exact prefab hashes.
-- Hashes are computed from prefab name strings and vary; look them up at runtime.
-- Example: local hash = ic.hash("ItemFurnace")
--          local temp  = ic.batch_read(hash, LT.Temperature, "Average")

-- ── Temperature Constants ──────────────────────────────────────────────────────
smelting.KELVIN_OFFSET = 273.15

--- Convert Kelvin to Celsius.
function smelting.k_to_c(k) return k - 273.15 end

--- Convert Celsius to Kelvin.
function smelting.c_to_k(c) return c + 273.15 end

-- ── Recipe Database ────────────────────────────────────────────────────────────
-- Each recipe contains:
--   name:          Output item name
--   inputs:        Table of {item=string, count=number}
--   output_count:  Number of output items produced (default 1)
--   temp_min:      Minimum temperature in Kelvin (nil = no minimum)
--   temp_max:      Maximum temperature in Kelvin (nil = no maximum)
--   pressure_min:  Minimum pressure in kPa (nil = no minimum)
--   pressure_max:  Maximum pressure in kPa (nil = no maximum)
--   furnace:       Required furnace type ("any", "arc", "advanced")
--   notes:         Human-readable tips

-- Temperature and pressure ranges sourced from stationeersfurnace.com
-- (scraped from game XML data). Inputs verified against Stationeers Wiki
-- Furnace and Advanced Furnace pages. Pressure is in kPa (1 MPa = 1000 kPa).
-- Basic ore flash points are ~327 K (ore melts into reagent above this).

smelting.recipes = {
    -- ── Basic Ingots (any furnace, single ore) ───────────────────────────────
    -- These just need the ore heated above its flash point (~327 K).
    -- No specific pressure requirement.
    {
        name     = "Iron Ingot",
        inputs   = { { item = "Iron Ore", count = 1 } },
        temp_min = 327,
        furnace  = "any",
        notes    = "Basic smelt. Heat ore above flash point.",
    },
    {
        name     = "Gold Ingot",
        inputs   = { { item = "Gold Ore", count = 1 } },
        temp_min = 327,
        furnace  = "any",
    },
    {
        name     = "Silver Ingot",
        inputs   = { { item = "Silver Ore", count = 1 } },
        temp_min = 327,
        furnace  = "any",
    },
    {
        name     = "Copper Ingot",
        inputs   = { { item = "Copper Ore", count = 1 } },
        temp_min = 327,
        furnace  = "any",
    },
    {
        name     = "Lead Ingot",
        inputs   = { { item = "Lead Ore", count = 1 } },
        temp_min = 327,
        furnace  = "any",
    },
    {
        name     = "Nickel Ingot",
        inputs   = { { item = "Nickel Ore", count = 1 } },
        temp_min = 327,
        furnace  = "any",
    },
    {
        name     = "Silicon Ingot",
        inputs   = { { item = "Silicon Ore", count = 1 } },
        temp_min = 327,
        furnace  = "any",
    },
    {
        name     = "Cobalt Ingot",
        inputs   = { { item = "Cobalt Ore", count = 1 } },
        temp_min = 327,
        furnace  = "any",
    },

    -- ── Simple Alloys (Furnace or Advanced Furnace) ──────────────────────────
    -- Temp/pressure from stationeersfurnace.com (scraped from game XML).
    -- Inputs from Stationeers Wiki Furnace page.
    {
        name         = "Steel Ingot",
        inputs       = {
            { item = "Iron Ore", count = 3 },
            { item = "Coal",     count = 1 },
        },
        temp_min     = 900,   -- 900 K
        temp_max     = 3000,  -- 3000 K
        pressure_min = 1000,  -- 1 MPa
        pressure_max = 60000, -- 60 MPa
        furnace      = "any",
        notes        = "3:1 Iron:Coal. Wide temp/pressure window.",
    },
    {
        name         = "Electrum Ingot",
        inputs       = {
            { item = "Gold Ore",   count = 1 },
            { item = "Silver Ore", count = 1 },
        },
        temp_min     = 600,  -- 600 K
        temp_max     = 3000, -- 3000 K
        pressure_min = 800,  -- 0.8 MPa
        pressure_max = 2400, -- 2.4 MPa
        furnace      = "any",
        notes        = "1:1 Gold:Silver. Narrow pressure window (800-2400 kPa).",
    },
    {
        name         = "Solder Ingot",
        inputs       = {
            { item = "Iron Ore", count = 1 },
            { item = "Lead Ore", count = 1 },
        },
        temp_min     = 350,    -- 350 K
        temp_max     = 550,    -- 550 K
        pressure_min = 1000,   -- 1 MPa
        pressure_max = 100000, -- 100 MPa
        furnace      = "any",
        notes        = "1:1 Iron:Lead. Low temp (350-550 K), wide pressure.",
    },
    {
        name         = "Invar Ingot",
        inputs       = {
            { item = "Iron Ore",   count = 3 },
            { item = "Nickel Ore", count = 1 },
        },
        temp_min     = 1200,  -- 1200 K
        temp_max     = 1500,  -- 1500 K
        pressure_min = 18000, -- 18 MPa
        pressure_max = 20000, -- 20 MPa
        furnace      = "any",
        notes        = "3:1 Iron:Nickel. Very tight window! 1200-1500 K, 18-20 MPa.",
    },
    {
        name         = "Constantan Ingot",
        inputs       = {
            { item = "Copper Ore", count = 1 },
            { item = "Nickel Ore", count = 1 },
        },
        temp_min     = 1000,  -- 1000 K
        temp_max     = 10000, -- 10000 K
        pressure_min = 20000, -- 20 MPa
        pressure_max = 60000, -- 60 MPa
        furnace      = "any",
        notes        = "1:1 Copper:Nickel. Needs 20+ MPa, wide temp window.",
    },

    -- ── Super Alloys (Advanced Furnace required) ─────────────────────────────
    -- Inputs verified from Advanced Furnace wiki page.
    -- These use RAW ORES (not ingots), except where noted.
    -- Do NOT degas the ores - N2O from silver/lead ore is needed.
    {
        name         = "Stellite Ingot",
        inputs       = {
            { item = "Silicon Ore", count = 2 },
            { item = "Silver Ore",  count = 1 },
            { item = "Cobalt Ore",  count = 1 },
        },
        temp_min     = 1800,   -- 1800 K (Stationpedia)
        temp_max     = 100000, -- 100000 K
        pressure_min = 10000,  -- 10 MPa (Stationpedia)
        pressure_max = 20000,  -- 20 MPa
        furnace      = "advanced",
        notes        = "2:1:1 Silicon:Silver:Cobalt. Do not degas - needs N2O from silver ore.",
    },
    {
        name         = "Inconel Ingot",
        inputs       = {
            { item = "Gold Ore",    count = 1 },
            { item = "Nickel Ore",  count = 1 },
            { item = "Steel Ingot", count = 1 },
        },
        temp_min     = 600,   -- 600 K
        temp_max     = 3000,  -- 3000 K
        pressure_min = 23500, -- 23.5 MPa
        pressure_max = 24000, -- 24 MPa
        furnace      = "advanced",
        notes        = "Very tight pressure! 23.5-24 MPa. Steel Ingot + raw ores.",
    },
    {
        name         = "Astroloy Ingot",
        inputs       = {
            { item = "Steel Ingot", count = 1 },
            { item = "Copper Ore",  count = 1 },
            { item = "Cobalt Ore",  count = 1 },
        },
        temp_min     = 1000,  -- 1000 K
        temp_max     = 3000,  -- 3000 K
        pressure_min = 30000, -- 30 MPa
        pressure_max = 40000, -- 40 MPa
        furnace      = "advanced",
        notes        = "Tight pressure window (30-40 MPa). Uses Steel Ingot + raw ores.",
    },
    {
        name         = "Hastelloy Ingot",
        inputs       = {
            { item = "Silver Ore", count = 1 },
            { item = "Nickel Ore", count = 1 },
            { item = "Cobalt Ore", count = 1 },
        },
        temp_min     = 950,   -- 950 K
        temp_max     = 1000,  -- 1000 K
        pressure_min = 25000, -- 25 MPa
        pressure_max = 30000, -- 30 MPa
        furnace      = "advanced",
        notes        = "Tight window! 950-1000 K, 25-30 MPa. Do not degas ores.",
    },
    {
        name         = "Waspaloy Ingot",
        inputs       = {
            { item = "Lead Ore",   count = 2 },
            { item = "Silver Ore", count = 1 },
            { item = "Nickel Ore", count = 1 },
        },
        temp_min     = 400,    -- 400 K (Stationpedia)
        temp_max     = 800,    -- 800 K
        pressure_min = 50000,  -- 50 MPa (Stationpedia)
        pressure_max = 100000, -- 100 MPa
        furnace      = "advanced",
        notes        = "2:1:1 Lead:Silver:Nickel. Low temp, very high pressure. Do not degas ores.",
    },
}

-- ── Lookup Functions ───────────────────────────────────────────────────────────

--- Find a recipe by exact output name (case-insensitive).
-- @param name  Output item name (e.g. "Steel Ingot")
-- @return recipe table or nil
function smelting.find(name)
    local lower = string.lower(name)
    for _, r in ipairs(smelting.recipes) do
        if string.lower(r.name) == lower then
            return r
        end
    end
    return nil
end

--- Find all recipes that use a given input ingredient.
-- @param ingredient  Input item name (e.g. "Iron Ore")
-- @return list of matching recipe tables
function smelting.find_by_input(ingredient)
    local lower = string.lower(ingredient)
    local results = {}
    for _, r in ipairs(smelting.recipes) do
        for _, inp in ipairs(r.inputs) do
            if string.lower(inp.item) == lower then
                results[#results + 1] = r
                break
            end
        end
    end
    return results
end

--- Get all recipe names as a simple list.
-- @return list of strings
function smelting.list()
    local names = {}
    for _, r in ipairs(smelting.recipes) do
        names[#names + 1] = r.name
    end
    return names
end

--- Check if the given temperature and pressure are within range for a recipe.
-- @param recipe       Recipe table from smelting.recipes
-- @param temp_k       Current furnace temperature in Kelvin
-- @param pressure_kpa Current furnace pressure in kPa (optional)
-- @return in_range (bool), status_string
function smelting.check_range(recipe, temp_k, pressure_kpa)
    if recipe.temp_min and temp_k < recipe.temp_min then
        return false, "TOO COLD"
    end
    if recipe.temp_max and temp_k > recipe.temp_max then
        return false, "TOO HOT"
    end
    if recipe.pressure_min and pressure_kpa and pressure_kpa < recipe.pressure_min then
        return false, "UNDER PRESSURE"
    end
    if recipe.pressure_max and pressure_kpa and pressure_kpa > recipe.pressure_max then
        return false, "OVER PRESSURE"
    end
    return true, "IN RANGE"
end

--- Format a recipe's input list as a human-readable string.
-- @param recipe  Recipe table
-- @return string like "3x Iron Ore + 1x Coal"
function smelting.format_inputs(recipe)
    local parts = {}
    for _, inp in ipairs(recipe.inputs) do
        parts[#parts + 1] = inp.count .. "x " .. inp.item
    end
    return table.concat(parts, " + ")
end

--- Format a recipe's temperature range as a string.
-- @param recipe  Recipe table
-- @param celsius If true, display in Celsius (default Kelvin)
-- @return string like "480 - 800 K" or "207 - 527 C"
function smelting.format_temp_range(recipe, celsius)
    local lo = recipe.temp_min
    local hi = recipe.temp_max
    local unit = " K"

    if celsius then
        lo = lo and smelting.k_to_c(lo)
        hi = hi and smelting.k_to_c(hi)
        unit = " C"
    end

    if lo and hi then
        return string.format("%.0f - %.0f%s", lo, hi, unit)
    elseif lo then
        return string.format("%.0f+%s", lo, unit)
    else
        return "any" .. unit
    end
end

return smelting
