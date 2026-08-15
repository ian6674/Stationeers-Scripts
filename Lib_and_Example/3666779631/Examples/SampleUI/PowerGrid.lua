-- Power Grid Monitor
-- ScriptedScreens command center display for power generation and consumption
-- Shows solar output, battery status, and power draw

local ui = ss.ui.surface("main")
ss.ui.activate("main")

local W, H = 480, 272

local size = ui:size()
if size then
    W = size.w or W
    H = size.h or H
end

-- Simulated power data
local powerData = {
    solarOutput = 12500,
    solarMax = 18000,
    batteryCharge = 78.5,
    batteryCapacity = 500000,
    consumption = 8200,
    peakDraw = 15000,
    gridStatus = "STABLE",
    sources = {
        { name = "SOLAR ARRAY A", output = 6200, max = 9000, online = true },
        { name = "SOLAR ARRAY B", output = 6300, max = 9000, online = true },
        { name = "GENERATOR 1",   output = 0,    max = 5000, online = false },
    },
}

local function get_grid_color(status)
    if status == "STABLE" then return "#00E676" end
    if status == "WARNING" then return "#FFEB3B" end
    if status == "CRITICAL" then return "#FF5252" end
    return "#B0BEC5"
end

local function get_battery_color(pct)
    if pct >= 60 then return "#00E676" end
    if pct >= 30 then return "#FFEB3B" end
    if pct >= 10 then return "#FF9800" end
    return "#FF5252"
end

local function fmt_power(w)
    if w == nil then return "--" end
    if w >= 1000 then
        return string.format("%.1f kW", w / 1000)
    end
    return string.format("%.0f W", w)
end

local function fmt(v, decimals)
    if v == nil then return "--" end
    decimals = decimals or 1
    return string.format("%." .. decimals .. "f", v)
end

local function update_grid_status()
    local surplus = powerData.solarOutput - powerData.consumption
    if surplus < -1000 then
        powerData.gridStatus = "CRITICAL"
    elseif surplus < 0 or powerData.batteryCharge < 20 then
        powerData.gridStatus = "WARNING"
    else
        powerData.gridStatus = "STABLE"
    end
end

local function render()
    update_grid_status()
    ui:clear()

    -- Background
    ui:element({
        id = "bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = H },
        style = { bg = "#0A0E1A" }
    })

    -- Precompute dynamic values
    local statusColor = get_grid_color(powerData.gridStatus)
    local genPct = (powerData.solarOutput / powerData.solarMax) * 100
    local conPct = (powerData.consumption / powerData.peakDraw) * 100
    local batColor = get_battery_color(powerData.batteryCharge)
    local netPower = powerData.solarOutput - powerData.consumption
    local netColor = netPower >= 0 and "#00E676" or "#FF5252"
    local netSign = netPower >= 0 and "+" or ""

    -- Build dynamic source rows
    local sourceChildren = {}
    for i, src in ipairs(powerData.sources) do
        local srcColor = src.online and "#00E676" or "#475569"
        local outputColor = src.online and "#E2E8F0" or "#475569"
        local row = {
            layout = "flex",
            rect = { h = 22 },
            direction = "row",
            gap = 4,
            children = {
                {
                    id = "src_dot_" .. i,
                    type = "panel",
                    rect = { w = 8 },
                    style = { bg = srcColor }
                },
                {
                    id = "src_name_" .. i,
                    type = "label",
                    rect = { w = 140 },
                    props = { text = src.name },
                    style = { font_size = 11, color = outputColor, align = "left" }
                },
                {
                    id = "src_out_" .. i,
                    type = "label",
                    rect = { w = 80 },
                    props = { text = src.online and fmt_power(src.output) or "OFFLINE" },
                    style = { font_size = 11, color = outputColor, align = "left" }
                },
            }
        }
        -- Append progress bar if source is online
        if src.online then
            local srcPct = (src.output / src.max) * 100
            table.insert(row.children, {
                id = "src_bar_" .. i,
                type = "progress",
                flex = 1,
                props = { value = tostring(srcPct), max = "100" },
                style = { bg = "#1E293B", fill = "#22C55E" }
            })
        end
        sourceChildren[i] = row
    end

    -- Full-screen nested layout
    ui:layout({
        layout = "flex",
        rect = { unit = "px", x = 0, y = 0, w = W, h = H },
        direction = "column",
        gap = 0,
        children = {
            -- ── Header ───────────────────────────────────────────────
            {
                id = "header",
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
                        props = { text = "POWER GRID" },
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
                        props = { text = powerData.gridStatus },
                        style = { font_size = 12, color = statusColor, align = "left" }
                    },
                }
            },

            -- ── Main stats: three columns ────────────────────────────
            {
                layout = "flex",
                rect = { h = 78 },
                direction = "row",
                gap = 12,
                padding = { left = 16, right = 16, top = 10 },
                children = {
                    -- Generation
                    {
                        layout = "flex",
                        flex = 1,
                        direction = "column",
                        gap = 2,
                        children = {
                            {
                                id = "gen_lbl",
                                type = "label",
                                rect = { h = 16 },
                                props = { text = "GENERATION" },
                                style = { font_size = 11, color = "#64748B", align = "left" }
                            },
                            {
                                id = "gen_val",
                                type = "label",
                                rect = { h = 28 },
                                props = { text = fmt_power(powerData.solarOutput) },
                                style = { font_size = 22, color = "#00E676", align = "left" }
                            },
                            {
                                id = "gen_bar",
                                type = "progress",
                                rect = { h = 12 },
                                props = { value = tostring(genPct), max = "100" },
                                style = { bg = "#1E293B", fill = "#00E676" }
                            },
                            {
                                id = "gen_max",
                                type = "label",
                                rect = { h = 14 },
                                props = { text = "max " .. fmt_power(powerData.solarMax) },
                                style = { font_size = 10, color = "#475569", align = "left" }
                            },
                        }
                    },
                    -- Consumption
                    {
                        layout = "flex",
                        flex = 1,
                        direction = "column",
                        gap = 2,
                        children = {
                            {
                                id = "con_lbl",
                                type = "label",
                                rect = { h = 16 },
                                props = { text = "CONSUMPTION" },
                                style = { font_size = 11, color = "#64748B", align = "left" }
                            },
                            {
                                id = "con_val",
                                type = "label",
                                rect = { h = 28 },
                                props = { text = fmt_power(powerData.consumption) },
                                style = { font_size = 22, color = "#F97316", align = "left" }
                            },
                            {
                                id = "con_bar",
                                type = "progress",
                                rect = { h = 12 },
                                props = { value = tostring(conPct), max = "100" },
                                style = { bg = "#1E293B", fill = "#F97316" }
                            },
                            {
                                id = "con_peak",
                                type = "label",
                                rect = { h = 14 },
                                props = { text = "peak " .. fmt_power(powerData.peakDraw) },
                                style = { font_size = 10, color = "#475569", align = "left" }
                            },
                        }
                    },
                    -- Battery
                    {
                        layout = "flex",
                        flex = 1,
                        direction = "column",
                        gap = 2,
                        children = {
                            {
                                id = "bat_lbl",
                                type = "label",
                                rect = { h = 16 },
                                props = { text = "BATTERY" },
                                style = { font_size = 11, color = "#64748B", align = "left" }
                            },
                            {
                                id = "bat_val",
                                type = "label",
                                rect = { h = 28 },
                                props = { text = fmt(powerData.batteryCharge) .. "%" },
                                style = { font_size = 22, color = batColor, align = "left" }
                            },
                            {
                                id = "bat_bar",
                                type = "progress",
                                rect = { h = 12 },
                                props = { value = tostring(powerData.batteryCharge), max = "100" },
                                style = { bg = "#1E293B", fill = batColor }
                            },
                            {
                                id = "net_lbl",
                                type = "label",
                                rect = { h = 14 },
                                props = { text = "net " .. netSign .. fmt_power(netPower) },
                                style = { font_size = 10, color = netColor, align = "left" }
                            },
                        }
                    },
                }
            },

            -- ── Power sources ────────────────────────────────────────
            {
                layout = "flex",
                flex = 1,
                direction = "column",
                gap = 2,
                padding = { left = 16, right = 16, top = 4 },
                children = {
                    {
                        id = "src_title",
                        type = "label",
                        rect = { h = 18 },
                        props = { text = "POWER SOURCES" },
                        style = { font_size = 11, color = "#64748B", align = "left" }
                    },
                    -- Dynamic source rows inserted via table
                    table.unpack(sourceChildren),
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
                        props = { text = "REAL-TIME MONITORING" },
                        style = { font_size = 10, color = "#475569", align = "left" }
                    },
                }
            },
        }
    })

    ui:commit()
end

render()

-- Main loop - simulate power fluctuations
local tick = 0
local dayPhase = 0 -- 0-100 represents day cycle

while true do
    tick = tick + 1
    dayPhase = (dayPhase + 0.1) % 100

    -- Solar output varies with day cycle (peak at 50)
    local solarMultiplier = math.max(0, 1 - math.abs(dayPhase - 50) / 50)
    solarMultiplier = solarMultiplier * (0.9 + math.random() * 0.2)

    for _, src in ipairs(powerData.sources) do
        if src.name:find("SOLAR") then
            src.output = math.floor(src.max * solarMultiplier)
            src.online = src.output > 100
        end
    end

    -- Recalculate total solar
    powerData.solarOutput = 0
    for _, src in ipairs(powerData.sources) do
        if src.online then
            powerData.solarOutput = powerData.solarOutput + src.output
        end
    end

    -- Consumption fluctuates
    powerData.consumption = 7000 + math.random(0, 3000)

    -- Battery charge/discharge
    local netPower = powerData.solarOutput - powerData.consumption
    powerData.batteryCharge = powerData.batteryCharge + (netPower / powerData.batteryCapacity) * 100
    powerData.batteryCharge = math.max(0, math.min(100, powerData.batteryCharge))

    if tick % 8 == 0 then
        render()
    end

    ic.yield()
end
