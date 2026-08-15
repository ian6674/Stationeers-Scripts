-- Life Support Systems Display
-- ScriptedScreens command center display for life support monitoring
-- Shows water, food, waste processing, and environmental systems

local ui = ss.ui.surface("main")
ss.ui.activate("main")

local W, H = 480, 272

local size = ui:size()
if size then
    W = size.w or W
    H = size.h or H
end

-- Simulated life support data
local lsData = {
    water = {
        clean = 85.2,
        dirty = 23.4,
        recycleRate = 94.5,
    },
    food = {
        stored = 42,
        maxStorage = 100,
        production = 2.5,
        consumption = 3.0,
    },
    waste = {
        level = 34.2,
        processRate = 78.0,
    },
    co2Scrubber = {
        efficiency = 97.8,
        status = "ACTIVE",
    },
    crewCount = 4,
    daysSupply = 14,
}

local function get_level_color(pct, inverse)
    if inverse then
        -- For waste: high = bad
        if pct <= 30 then return "#00E676" end
        if pct <= 60 then return "#FFEB3B" end
        if pct <= 80 then return "#FF9800" end
        return "#FF5252"
    else
        -- Normal: high = good
        if pct >= 60 then return "#00E676" end
        if pct >= 30 then return "#FFEB3B" end
        if pct >= 15 then return "#FF9800" end
        return "#FF5252"
    end
end

local function fmt(v, decimals)
    if v == nil then return "--" end
    decimals = decimals or 1
    return string.format("%." .. decimals .. "f", v)
end

local function get_overall_status()
    if lsData.water.clean < 20 or lsData.food.stored < 10 or lsData.waste.level > 90 then
        return "CRITICAL", "#FF5252"
    elseif lsData.water.clean < 40 or lsData.food.stored < 25 or lsData.waste.level > 70 then
        return "WARNING", "#FFEB3B"
    end
    return "NOMINAL", "#00E676"
end

local function render()
    ui:clear()

    -- Background
    ui:element({
        id = "bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = H },
        style = { bg = "#0A0E1A" }
    })

    -- Precompute dynamic values
    local statusText, statusColor = get_overall_status()
    local foodPct = (lsData.food.stored / lsData.food.maxStorage) * 100
    local foodNet = lsData.food.production - lsData.food.consumption
    local foodNetColor = foodNet >= 0 and "#00E676" or "#FF5252"
    local foodNetSign = foodNet >= 0 and "+" or ""
    local scrubColor = lsData.co2Scrubber.status == "ACTIVE" and "#00E676" or "#FF5252"

    -- Full-screen nested layout
    ui:layout({
        layout = "flex",
        rect = { unit = "px", x = 0, y = 0, w = W, h = H },
        direction = "column",
        gap = 0,
        children = {
            -- ── Header ───────────────────────────────────────────────
            {
                id = "hdr",
                type = "panel",
                rect = { h = 44 },
                style = { bg = "#1E293B" },
                layout = "flex",
                direction = "row",
                gap = 6,
                align = "center",
                padding = { left = 16, right = 16, top = 10 },
                children = {
                    {
                        id = "title",
                        type = "label",
                        flex = 1,
                        props = { text = "LIFE SUPPORT" },
                        style = { font_size = 16, color = "#E2E8F0", align = "left" }
                    },
                    {
                        id = "status_dot",
                        type = "panel",
                        rect = { w = 12 },
                        style = { bg = statusColor }
                    },
                    {
                        id = "status_txt",
                        type = "label",
                        rect = { w = 80 },
                        props = { text = statusText },
                        style = { font_size = 12, color = statusColor, align = "left" }
                    },
                }
            },

            -- ── Crew info bar ────────────────────────────────────────
            {
                layout = "flex",
                rect = { h = 20 },
                direction = "row",
                gap = 6,
                padding = { left = 16, top = 4 },
                children = {
                    {
                        id = "crew_lbl",
                        type = "label",
                        rect = { w = 50 },
                        props = { text = "CREW" },
                        style = { font_size = 10, color = "#64748B", align = "left" }
                    },
                    {
                        id = "crew_val",
                        type = "label",
                        rect = { w = 30 },
                        props = { text = tostring(lsData.crewCount) },
                        style = { font_size = 14, color = "#E2E8F0", align = "left" }
                    },
                    {
                        id = "days_lbl",
                        type = "label",
                        rect = { w = 140 },
                        props = { text = "SUPPLY: " .. lsData.daysSupply .. " DAYS" },
                        style = { font_size = 10, color = "#94A3B8", align = "left" }
                    },
                }
            },

            -- ── Top row: Water + Food panels ─────────────────────────
            {
                layout = "flex",
                flex = 1,
                direction = "row",
                gap = 8,
                padding = { left = 8, right = 8, top = 4 },
                children = {
                    -- Water systems panel
                    {
                        id = "water_bg",
                        type = "panel",
                        flex = 1,
                        style = { bg = "#111827" },
                        layout = "flex",
                        direction = "column",
                        gap = 2,
                        padding = 8,
                        children = {
                            {
                                id = "water_title",
                                type = "label",
                                rect = { h = 16 },
                                props = { text = "WATER SYSTEMS" },
                                style = { font_size = 11, color = "#06B6D4", align = "left" }
                            },
                            -- Clean water row
                            {
                                layout = "flex",
                                rect = { h = 16 },
                                direction = "row",
                                gap = 4,
                                children = {
                                    {
                                        id = "clean_lbl",
                                        type = "label",
                                        rect = { w = 50 },
                                        props = { text = "Clean" },
                                        style = { font_size = 10, color = "#94A3B8", align = "left" }
                                    },
                                    {
                                        id = "clean_bar",
                                        type = "progress",
                                        flex = 1,
                                        props = { value = tostring(lsData.water.clean), max = "100" },
                                        style = { bg = "#1E293B", fill = get_level_color(lsData.water.clean) }
                                    },
                                    {
                                        id = "clean_pct",
                                        type = "label",
                                        rect = { w = 42 },
                                        props = { text = fmt(lsData.water.clean) .. "%" },
                                        style = { font_size = 10, color = get_level_color(lsData.water.clean), align = "left" }
                                    },
                                }
                            },
                            -- Dirty water row
                            {
                                layout = "flex",
                                rect = { h = 16 },
                                direction = "row",
                                gap = 4,
                                children = {
                                    {
                                        id = "dirty_lbl",
                                        type = "label",
                                        rect = { w = 50 },
                                        props = { text = "Waste" },
                                        style = { font_size = 10, color = "#94A3B8", align = "left" }
                                    },
                                    {
                                        id = "dirty_bar",
                                        type = "progress",
                                        flex = 1,
                                        props = { value = tostring(lsData.water.dirty), max = "100" },
                                        style = { bg = "#1E293B", fill = get_level_color(lsData.water.dirty, true) }
                                    },
                                    {
                                        id = "dirty_pct",
                                        type = "label",
                                        rect = { w = 42 },
                                        props = { text = fmt(lsData.water.dirty) .. "%" },
                                        style = { font_size = 10, color = get_level_color(lsData.water.dirty, true), align = "left" }
                                    },
                                }
                            },
                            {
                                id = "recycle_lbl",
                                type = "label",
                                rect = { h = 14 },
                                props = { text = "Recycle: " .. fmt(lsData.water.recycleRate) .. "%" },
                                style = { font_size = 10, color = "#94A3B8", align = "left" }
                            },
                        }
                    },

                    -- Food supply panel
                    {
                        id = "food_bg",
                        type = "panel",
                        flex = 1,
                        style = { bg = "#111827" },
                        layout = "flex",
                        direction = "column",
                        gap = 2,
                        padding = 8,
                        children = {
                            {
                                id = "food_title",
                                type = "label",
                                rect = { h = 16 },
                                props = { text = "FOOD SUPPLY" },
                                style = { font_size = 11, color = "#22C55E", align = "left" }
                            },
                            {
                                id = "food_val",
                                type = "label",
                                rect = { h = 24 },
                                props = { text = tostring(lsData.food.stored) .. " units" },
                                style = { font_size = 16, color = get_level_color(foodPct), align = "left" }
                            },
                            {
                                id = "food_bar",
                                type = "progress",
                                rect = { h = 14 },
                                props = { value = tostring(foodPct), max = "100" },
                                style = { bg = "#1E293B", fill = get_level_color(foodPct) }
                            },
                            {
                                id = "food_rate",
                                type = "label",
                                rect = { h = 14 },
                                props = { text = "Rate: " .. foodNetSign .. fmt(foodNet) .. "/day" },
                                style = { font_size = 10, color = foodNetColor, align = "left" }
                            },
                        }
                    },
                }
            },

            -- ── Bottom row: Waste + CO2 panels ───────────────────────
            {
                layout = "flex",
                rect = { h = 66 },
                direction = "row",
                gap = 8,
                padding = { left = 8, right = 8, top = 4 },
                children = {
                    -- Waste processing panel
                    {
                        id = "waste_bg",
                        type = "panel",
                        flex = 1,
                        style = { bg = "#111827" },
                        layout = "flex",
                        direction = "column",
                        gap = 2,
                        padding = 8,
                        children = {
                            {
                                id = "waste_title",
                                type = "label",
                                rect = { h = 16 },
                                props = { text = "WASTE PROCESSING" },
                                style = { font_size = 11, color = "#F97316", align = "left" }
                            },
                            -- Waste level row
                            {
                                layout = "flex",
                                rect = { h = 16 },
                                direction = "row",
                                gap = 4,
                                children = {
                                    {
                                        id = "waste_lbl",
                                        type = "label",
                                        rect = { w = 42 },
                                        props = { text = "Level" },
                                        style = { font_size = 10, color = "#94A3B8", align = "left" }
                                    },
                                    {
                                        id = "waste_bar",
                                        type = "progress",
                                        flex = 1,
                                        props = { value = tostring(lsData.waste.level), max = "100" },
                                        style = { bg = "#1E293B", fill = get_level_color(lsData.waste.level, true) }
                                    },
                                    {
                                        id = "waste_pct",
                                        type = "label",
                                        rect = { w = 42 },
                                        props = { text = fmt(lsData.waste.level) .. "%" },
                                        style = { font_size = 10, color = get_level_color(lsData.waste.level, true), align = "left" }
                                    },
                                }
                            },
                            {
                                id = "process_lbl",
                                type = "label",
                                rect = { h = 14 },
                                props = { text = "Processing: " .. fmt(lsData.waste.processRate) .. "%" },
                                style = { font_size = 10, color = "#94A3B8", align = "left" }
                            },
                        }
                    },

                    -- CO2 Scrubber panel
                    {
                        id = "co2_bg",
                        type = "panel",
                        flex = 1,
                        style = { bg = "#111827" },
                        layout = "flex",
                        direction = "column",
                        gap = 2,
                        padding = 8,
                        children = {
                            {
                                id = "co2_title",
                                type = "label",
                                rect = { h = 16 },
                                props = { text = "CO2 SCRUBBER" },
                                style = { font_size = 11, color = "#8B5CF6", align = "left" }
                            },
                            {
                                layout = "flex",
                                rect = { h = 18 },
                                direction = "row",
                                gap = 8,
                                children = {
                                    {
                                        id = "co2_status",
                                        type = "label",
                                        rect = { w = 80 },
                                        props = { text = lsData.co2Scrubber.status },
                                        style = { font_size = 12, color = scrubColor, align = "left" }
                                    },
                                    {
                                        id = "co2_eff",
                                        type = "label",
                                        flex = 1,
                                        props = { text = fmt(lsData.co2Scrubber.efficiency) .. "% eff" },
                                        style = { font_size = 12, color = "#E2E8F0", align = "left" }
                                    },
                                }
                            },
                            {
                                id = "co2_bar",
                                type = "progress",
                                rect = { h = 12 },
                                props = { value = tostring(lsData.co2Scrubber.efficiency), max = "100" },
                                style = { bg = "#1E293B", fill = "#8B5CF6" }
                            },
                        }
                    },
                }
            },

            -- ── Footer ───────────────────────────────────────────────
            {
                layout = "flex",
                rect = { h = 22 },
                direction = "row",
                padding = { left = 16 },
                children = {
                    {
                        id = "footer",
                        type = "label",
                        flex = 1,
                        props = { text = "SYSTEMS MONITORED" },
                        style = { font_size = 10, color = "#475569", align = "left" }
                    },
                }
            },
        }
    })

    ui:commit()
end

render()

-- Main loop - simulate life support fluctuations
local tick = 0
while true do
    tick = tick + 1

    -- Water fluctuations
    lsData.water.clean = lsData.water.clean - 0.05 + (math.random() * 0.1)
    lsData.water.dirty = lsData.water.dirty + 0.03 - (math.random() * 0.06)

    -- Recycling adds to clean water
    if lsData.water.dirty > 10 then
        local recycled = lsData.water.dirty * (lsData.water.recycleRate / 100) * 0.01
        lsData.water.clean = lsData.water.clean + recycled
        lsData.water.dirty = lsData.water.dirty - recycled * 1.1
    end

    lsData.water.clean = math.max(0, math.min(100, lsData.water.clean))
    lsData.water.dirty = math.max(0, math.min(100, lsData.water.dirty))

    -- Food changes
    if tick % 20 == 0 then
        local netFood = lsData.food.production - lsData.food.consumption
        lsData.food.stored = math.max(0, math.min(lsData.food.maxStorage, lsData.food.stored + netFood * 0.1))
    end

    -- Waste processing
    lsData.waste.level = lsData.waste.level + 0.1 - (lsData.waste.processRate / 100) * 0.15
    lsData.waste.level = math.max(0, math.min(100, lsData.waste.level))

    -- CO2 scrubber efficiency fluctuates
    lsData.co2Scrubber.efficiency = lsData.co2Scrubber.efficiency + (math.random() - 0.5) * 0.2
    lsData.co2Scrubber.efficiency = math.max(90, math.min(100, lsData.co2Scrubber.efficiency))

    -- Update days supply estimate
    if lsData.food.consumption > 0 then
        lsData.daysSupply = math.floor(lsData.food.stored / lsData.food.consumption)
    end

    if tick % 8 == 0 then
        render()
    end

    ic.yield()
end
