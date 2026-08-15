--[[
    SmeltingGuide.lua

    A practical furnace recipe guide with live monitoring.
    Displays recipe output images alongside real-time furnace readings
    so you can verify temperature and pressure targets while smelting.

    DEVICE WIRING:
      d0 = Furnace (Furnace, Arc Furnace, or Advanced Furnace)

    FEATURES:
      - Visual recipe cards with output item images (type="image")
      - Gauge widgets for live temperature and pressure readout
      - Progress bar showing target-temperature completion
      - Color-coded status: IN RANGE, TOO COLD, TOO HOT, OVERPRESSURE
      - Touch buttons to cycle through recipes
      - Persists selected recipe across world saves

    IMAGES:
      Recipe images are loaded from URLs in the recipe table below.
      Replace the example URLs with your own hosted images if desired.
      The server must have AllowRemoteImages = True in ScriptedScreens config.

    API / widgets demonstrated:
      - type="image" with dynamic URL swapping per recipe
      - type="gauge" with recipe-adaptive warn/danger thresholds
      - type="progress" for target-temperature completion bar
      - type="divider" for visual separators
      - ui:layout() nested flex system for responsive positioning
      - util.temp() for Kelvin → Celsius conversion
      - ic.read for live device data (Temperature, Pressure)
      - on_click callbacks for button navigation
      - serialize/deserialize for save persistence
]]

local ui = ss.ui.surface("main")
ss.ui.activate("main")

local size = ui:size()
local W, H = 480, 272
if size then W, H = size.w or W, size.h or H end

-- IC library shortcuts
local LT              = ic.enums.LogicType
local read            = ic.read
local yield           = ic.yield

-- ── Theme ────────────────────────────────────────────────────────────────────
local C               = {
    bg     = "#080C18",
    panel  = "#111827",
    header = "#0F172A",
    card   = "#1E293B",
    text   = "#E2E8F0",
    dim    = "#64748B",
    muted  = "#475569",
    accent = "#38BDF8",
    green  = "#22C55E",
    yellow = "#EAB308",
    orange = "#F97316",
    red    = "#EF4444",
    blue   = "#3B82F6",
}

-- ── Recipe Database ──────────────────────────────────────────────────────────
-- temp_min / temp_max are in Kelvin.  nil max = no upper limit.
-- pressure_max is in kPa; nil = no limit.
-- Image URLs point to Wikimedia Commons; swap for your own if preferred.
local recipes         = {
    {
        name         = "Iron Ingot",
        image        =
        "https://upload.wikimedia.org/wikipedia/commons/thumb/a/ad/Iron_electrolytic_and_1cm3_cube.jpg/250px-Iron_electrolytic_and_1cm3_cube.jpg",
        inputs       = { "1× Iron Ore" },
        output       = "1× Iron Ingot",
        temp_min     = 327,
        temp_max     = nil,
        pressure_max = nil,
        notes        = "Basic smelt. Melt above 327 K.",
    },
    {
        name         = "Steel Ingot",
        image        =
        "https://upload.wikimedia.org/wikipedia/commons/thumb/a/ad/Iron_electrolytic_and_1cm3_cube.jpg/250px-Iron_electrolytic_and_1cm3_cube.jpg",
        inputs       = { "3× Iron Ore", "1× Coal" },
        output       = "1× Steel Ingot",
        temp_min     = 900,   -- 900 K (stationeersfurnace.com)
        temp_max     = 3000,  -- 3000 K
        pressure_min = 1000,  -- 1 MPa
        pressure_max = 60000, -- 60 MPa
        notes        = "3:1 Iron:Coal. Wide temp/pressure window.",
    },
    {
        name         = "Electrum Ingot",
        image        = "https://upload.wikimedia.org/wikipedia/commons/thumb/5/5b/GoldNuggetUSGOV.jpg/250px-GoldNuggetUSGOV.jpg",
        inputs       = { "1× Gold Ore", "1× Silver Ore" },
        output       = "1× Electrum Ingot",
        temp_min     = 600,  -- 600 K
        temp_max     = 3000, -- 3000 K
        pressure_min = 800,  -- 0.8 MPa
        pressure_max = 2400, -- 2.4 MPa
        notes        = "1:1 Gold:Silver. Narrow pressure (800-2400 kPa).",
    },
    {
        name         = "Solder Ingot",
        image        = "https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Soudure2.jpg/250px-Soudure2.jpg",
        inputs       = { "1× Iron Ore", "1× Lead Ore" },
        output       = "1× Solder Ingot",
        temp_min     = 350,    -- 350 K
        temp_max     = 550,    -- 550 K
        pressure_min = 1000,   -- 1 MPa
        pressure_max = 100000, -- 100 MPa
        notes        = "1:1 Iron:Lead. Low temp (350-550 K).",
    },
    {
        name         = "Invar Ingot",
        image        = "https://upload.wikimedia.org/wikipedia/commons/thumb/5/57/Nickel_chunk.jpg/250px-Nickel_chunk.jpg",
        inputs       = { "3× Iron Ore", "1× Nickel Ore" },
        output       = "1× Invar Ingot",
        temp_min     = 1200,  -- 1200 K
        temp_max     = 1500,  -- 1500 K
        pressure_min = 18000, -- 18 MPa
        pressure_max = 20000, -- 20 MPa
        notes        = "3:1 Iron:Nickel. Tight! 1200-1500 K, 18-20 MPa.",
    },
    {
        name         = "Constantan Ingot",
        image        =
        "https://upload.wikimedia.org/wikipedia/commons/thumb/f/f0/NatCopper.jpg/250px-NatCopper.jpg",
        inputs       = { "1× Copper Ore", "1× Nickel Ore" },
        output       = "1× Constantan Ingot",
        temp_min     = 1000,  -- 1000 K
        temp_max     = 10000, -- 10000 K
        pressure_min = 20000, -- 20 MPa
        pressure_max = 60000, -- 60 MPa
        notes        = "1:1 Copper:Nickel. Needs 20+ MPa.",
    },
    {
        name         = "Silicon Ingot",
        image        = "https://upload.wikimedia.org/wikipedia/commons/thumb/e/e9/SiliconCroda.jpg/250px-SiliconCroda.jpg",
        inputs       = { "1× Silicon Ore" },
        output       = "1× Silicon Ingot",
        temp_min     = 327,
        temp_max     = nil,
        pressure_max = nil,
        notes        = "Solar panels & advanced electronics.",
    },
    {
        name         = "Inconel Ingot",
        image        =
        "https://upload.wikimedia.org/wikipedia/commons/thumb/5/57/Nickel_chunk.jpg/250px-Nickel_chunk.jpg",
        inputs       = { "1× Gold Ore", "1× Nickel Ore", "1× Steel Ingot" },
        output       = "1× Inconel Ingot",
        temp_min     = 600,   -- 600 K
        temp_max     = 3000,  -- 3000 K
        pressure_min = 23500, -- 23.5 MPa
        pressure_max = 24000, -- 24 MPa
        notes        = "Advanced Furnace. Very tight pressure (23.5-24 MPa).",
    },
}

-- ── State ────────────────────────────────────────────────────────────────────
local selectedRecipe  = 1
local furnaceTemp     = nil -- Kelvin, from d0
local furnacePressure = nil -- kPa, from d0
local connected       = false
local tickCount       = 0

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function fmt(v, d)
    if v == nil then return "--" end
    return string.format("%." .. (d or 1) .. "f", v)
end

-- Returns (status_label, color) for the current recipe vs furnace temp/press
local function eval_status(recipe, temp, press)
    if temp == nil then return "NO DATA", C.muted end
    if recipe.temp_min and temp < recipe.temp_min then
        return "TOO COLD", C.blue
    end
    if recipe.temp_max and temp > recipe.temp_max then
        return "TOO HOT", C.red
    end
    if recipe.pressure_min and press and press < recipe.pressure_min then
        return "LOW PRESSURE", C.blue
    end
    if recipe.pressure_max and press and press > recipe.pressure_max then
        return "OVER PRESSURE", C.orange
    end
    return "IN RANGE", C.green
end

-- Compute gauge warn/danger fractions from a recipe's temperature range.
-- The gauge arc goes 0→1 over [0, gaugeMax]; warn marks the start of the
-- caution zone and danger the start of the critical zone.
local function gauge_params(recipe)
    local gMax = 1600
    local warn = "0.75"
    local danger = "0.90"
    if recipe.temp_max then
        -- Scale gauge ceiling to ~1.5× the recipe max so the target zone
        -- sits comfortably inside the arc.
        gMax = math.max(math.ceil(recipe.temp_max * 1.5 / 100) * 100, 800)
        warn = string.format("%.2f", recipe.temp_max / gMax)
        danger = string.format("%.2f", math.min(0.95, recipe.temp_max * 1.25 / gMax))
    end
    return gMax, warn, danger
end

-- ── Render ───────────────────────────────────────────────────────────────────

local function render()
    ui:clear()

    local recipe               = recipes[selectedRecipe]

    -- ── Precompute live values ──
    local connText             = connected and "LINKED" or "NO FURNACE (d0)"
    local connColor            = connected and C.green or C.red

    -- Gauge thresholds adapted to the selected recipe
    local gMax, gWarn, gDanger = gauge_params(recipe)
    local tempStr              = connected and fmt(furnaceTemp, 0) or "0"
    local pressStr             = connected and fmt(furnacePressure, 1) or "0"
    local tempC                = furnaceTemp and util.temp(furnaceTemp) or nil
    local celsiusText          = tempC and (fmt(tempC, 1) .. " °C") or "--- °C"

    -- Target range label
    local rangeText            = "TARGET: " .. fmt(recipe.temp_min, 0) .. " K"
    if recipe.temp_max then
        rangeText = rangeText .. " - " .. fmt(recipe.temp_max, 0) .. " K"
    else
        rangeText = rangeText .. "+"
    end

    -- Target completion: how close furnace temp is to temp_min (0-100 %)
    local targetPct = 0
    if connected and furnaceTemp and recipe.temp_min and recipe.temp_min > 0 then
        targetPct = math.min(100, furnaceTemp / recipe.temp_min * 100)
    end

    -- Status evaluation
    local statusLabel, statusColor
    if not connected then
        statusLabel, statusColor = "OFFLINE", C.muted
    else
        statusLabel, statusColor = eval_status(recipe, furnaceTemp, furnacePressure)
    end

    -- ── Build right-column children dynamically (ingredient count varies) ──
    local rightChildren = {
        -- Gauge row: temperature + pressure
        {
            layout = "flex",
            rect = { h = 78 },
            direction = "row",
            gap = 6,
            children = {
                {
                    id = "g_temp",
                    type = "gauge",
                    flex = 1,
                    props = {
                        value = tempStr,
                        min = "0",
                        max = tostring(gMax),
                        warn = gWarn,
                        danger = gDanger,
                        label = "TEMP",
                        unit = " K",
                    },
                    style = {
                        bg = C.panel,
                        arc_thickness = "6",
                        font_size = "9",
                        value_color = C.text,
                        label_color = C.dim,
                        normal_color = "#22C55E80",
                        warn_color = "#EAB30880",
                        danger_color = "#EF444480",
                    },
                },
                {
                    id = "g_press",
                    type = "gauge",
                    flex = 1,
                    props = {
                        value = pressStr,
                        min = "0",
                        max = "200",
                        warn = "0.65",
                        danger = "0.85",
                        label = "PRESS",
                        unit = " kPa",
                    },
                    style = {
                        bg = C.panel,
                        arc_thickness = "6",
                        font_size = "9",
                        value_color = C.text,
                        label_color = C.dim,
                        normal_color = "#22C55E80",
                        warn_color = "#EAB30880",
                        danger_color = "#EF444480",
                    },
                },
            },
        },

        -- Celsius readout centered below gauges
        {
            id = "celsius",
            type = "label",
            rect = { h = 14 },
            props = { text = celsiusText },
            style = { font_size = 10, color = C.dim, align = "center" },
        },

        -- Target range label
        {
            id = "lbl_target",
            type = "label",
            rect = { h = 14 },
            props = { text = rangeText },
            style = { font_size = 9, color = C.dim, align = "left" },
        },

        -- Target completion progress bar
        {
            id = "target_bar",
            type = "progress",
            rect = { h = 8 },
            props = { value = tostring(targetPct), min = "0", max = "100" },
            style = { bg = "#1A1A2E", fill = statusColor },
        },

        -- Divider
        {
            id = "div1",
            type = "divider",
            rect = { h = 1 },
            style = { color = C.muted },
        },

        -- Ingredients header
        {
            id = "lbl_in",
            type = "label",
            rect = { h = 14 },
            props = { text = "INGREDIENTS" },
            style = { font_size = 9, color = C.dim, align = "left" },
        },
    }

    -- Ingredient rows (variable count per recipe)
    for i, input in ipairs(recipe.inputs) do
        rightChildren[#rightChildren + 1] = {
            id = "in_" .. i,
            type = "label",
            rect = { h = 15 },
            props = { text = "- " .. input },
            style = { font_size = 10, color = C.text, align = "left" },
        }
    end

    -- Status badge (panel with nested label)
    rightChildren[#rightChildren + 1] = {
        id = "status_bg",
        type = "panel",
        rect = { h = 22 },
        style = { bg = statusColor .. "20" },
        layout = "flex",
        direction = "row",
        gap = 6,
        padding = { left = 8 },
        children = {
            {
                id = "status_dot",
                type = "panel",
                rect = { w = 6, h = 6 },
                style = { bg = statusColor },
            },
            {
                id = "status_txt",
                type = "label",
                flex = 1,
                props = { text = statusLabel },
                style = { font_size = 11, color = statusColor, align = "left" },
            },
        },
    }

    -- Notes fill remaining space
    if recipe.notes then
        rightChildren[#rightChildren + 1] = {
            id = "notes",
            type = "label",
            flex = 1,
            props = { text = recipe.notes },
            style = { font_size = 9, color = C.dim, align = "left" },
        }
    end

    -- ── Background ──
    ui:element({
        id = "bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = H },
        style = { bg = C.bg },
    })

    -- ── Full-screen nested layout ──
    ui:layout({
        layout = "flex",
        rect = { unit = "px", x = 0, y = 0, w = W, h = H },
        direction = "column",
        gap = 0,
        children = {
            -- ── Header bar ──
            {
                id = "hdr",
                type = "panel",
                rect = { h = 34 },
                style = { bg = C.header },
                layout = "flex",
                direction = "row",
                gap = 0,
                padding = { left = 12, right = 12, top = 7, bottom = 7 },
                children = {
                    {
                        id = "title",
                        type = "label",
                        flex = 1,
                        props = { text = "SMELTING ASSISTANT" },
                        style = { font_size = 14, color = C.accent, align = "left" },
                    },
                    {
                        id = "conn",
                        type = "label",
                        rect = { w = 140 },
                        props = { text = connText },
                        style = { font_size = 10, color = connColor, align = "right" },
                    },
                },
            },

            -- ── Content: left card + right instruments ──
            {
                layout = "flex",
                flex = 1,
                direction = "row",
                gap = 6,
                padding = 4,
                children = {
                    -- ── Left column: recipe image card ──
                    {
                        layout = "flex",
                        rect = { w = 170 },
                        direction = "column",
                        gap = 3,
                        children = {
                            -- Recipe image (the star of the show)
                            {
                                id = "img",
                                type = "image",
                                flex = 3,
                                props = { url = recipe.image },
                            },
                            -- Recipe name
                            {
                                id = "rname",
                                type = "label",
                                rect = { h = 18 },
                                props = { text = recipe.name },
                                style = { font_size = 13, color = C.text, align = "center" },
                            },
                            -- Output
                            {
                                id = "rout",
                                type = "label",
                                rect = { h = 14 },
                                props = { text = recipe.output },
                                style = { font_size = 9, color = C.dim, align = "center" },
                            },
                            -- Page counter
                            {
                                id = "pg",
                                type = "label",
                                rect = { h = 12 },
                                props = { text = selectedRecipe .. " / " .. #recipes },
                                style = { font_size = 8, color = C.muted, align = "center" },
                            },
                            -- Navigation button row
                            {
                                layout = "flex",
                                rect = { h = 26 },
                                direction = "row",
                                gap = 4,
                                children = {
                                    {
                                        id = "bp",
                                        type = "button",
                                        flex = 1,
                                        props = { text = "< PREV" },
                                        style = { bg = C.card, text = C.text, font_size = 10 },
                                        on_click = function(playerName)
                                            selectedRecipe = selectedRecipe - 1
                                            if selectedRecipe < 1 then selectedRecipe = #recipes end
                                            persist_save_recipe()
                                            render()
                                        end,
                                    },
                                    {
                                        id = "bn",
                                        type = "button",
                                        flex = 1,
                                        props = { text = "NEXT >" },
                                        style = { bg = C.card, text = C.text, font_size = 10 },
                                        on_click = function(playerName)
                                            selectedRecipe = selectedRecipe + 1
                                            if selectedRecipe > #recipes then selectedRecipe = 1 end
                                            persist_save_recipe()
                                            render()
                                        end,
                                    },
                                },
                            },
                        },
                    },

                    -- ── Right column: gauges, progress, recipe details ──
                    {
                        id = "rpanel",
                        type = "panel",
                        flex = 1,
                        style = { bg = C.panel },
                        layout = "flex",
                        direction = "column",
                        gap = 4,
                        padding = 6,
                        children = rightChildren,
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
        selectedRecipe = math.max(1, math.min(#recipes, tonumber(val) or 1))
    end
end

local function persist_save_recipe()
    ic.persist.set(PERSIST_KEY, tostring(selectedRecipe))
end

persist_restore_recipe()

-- ── Main loop ────────────────────────────────────────────────────────────────

render()

while true do
    tickCount          = tickCount + 1

    -- Read furnace on d0 every tick
    local temp         = read(0, LT.Temperature)
    local press        = read(0, LT.Pressure)

    local wasConnected = connected
    connected          = (temp ~= nil)
    furnaceTemp        = temp
    furnacePressure    = press

    -- Re-render roughly once per second (~10 ticks) or on connection change
    if tickCount % 10 == 0 or (connected ~= wasConnected) then
        render()
    end

    yield()
end
