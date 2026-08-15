-- Atmosphere Monitor Display
-- ScriptedScreens command center display for gas mixture monitoring
-- Shows pressure, temperature, and gas composition

local ui = ss.ui.surface("main")
ss.ui.activate("main")

local W, H = 480, 272

local size = ui:size()
if size then
    W = size.w or W
    H = size.h or H
end

-- Simulated atmosphere data
local atmoData = {
    zone = "MAIN HAB",
    pressure = 101.3,
    temperature = 21.5,
    gases = {
        { name = "O2",  pct = 21.0, color = "#29B6F6" },
        { name = "N2",  pct = 78.0, color = "#8B5CF6" },
        { name = "CO2", pct = 0.04, color = "#F97316" },
        { name = "H2O", pct = 0.96, color = "#06B6D4" },
    },
    warnings = {},
}

local function get_pressure_color(p)
    if p >= 95 and p <= 105 then return "#00E676" end
    if p >= 80 and p <= 120 then return "#FFEB3B" end
    return "#FF5252"
end

local function get_temp_color(t)
    if t >= 18 and t <= 26 then return "#00E676" end
    if t >= 10 and t <= 35 then return "#FFEB3B" end
    return "#FF5252"
end

local function get_o2_color(pct)
    if pct >= 19 and pct <= 23 then return "#00E676" end
    if pct >= 16 and pct <= 25 then return "#FFEB3B" end
    return "#FF5252"
end

local function fmt(v, decimals)
    if v == nil then return "--" end
    decimals = decimals or 1
    return string.format("%." .. decimals .. "f", v)
end

local function check_warnings()
    atmoData.warnings = {}
    if atmoData.pressure < 90 then
        table.insert(atmoData.warnings, "LOW PRESSURE")
    elseif atmoData.pressure > 110 then
        table.insert(atmoData.warnings, "HIGH PRESSURE")
    end
    if atmoData.temperature < 15 then
        table.insert(atmoData.warnings, "LOW TEMP")
    elseif atmoData.temperature > 30 then
        table.insert(atmoData.warnings, "HIGH TEMP")
    end
    if atmoData.gases[1].pct < 18 then
        table.insert(atmoData.warnings, "LOW OXYGEN")
    end
    if atmoData.gases[3].pct > 1 then
        table.insert(atmoData.warnings, "HIGH CO2")
    end
end

local function render()
    check_warnings()
    ui:clear()

    -- Background
    ui:element({
        id = "bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = H },
        style = { bg = "#0A0E1A" }
    })

    -- Header
    local header = ui:element({
        id = "hdr",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = 44 },
        style = { bg = "#1E293B" }
    })

    header:element({
        id = "title",
        type = "label",
        rect = { unit = "px", x = 16, y = 10, w = 180, h = 22 },
        props = { text = "ATMOSPHERE" },
        style = { font_size = 16, color = "#E2E8F0", align = "left" }
    })

    header:element({
        id = "zone",
        type = "label",
        rect = { unit = "px", x = W - 140, y = 12, w = 124, h = 20 },
        props = { text = atmoData.zone },
        style = { font_size = 12, color = "#94A3B8", align = "right" }
    })

    -- Warning banner (if any)
    local warningY = 48
    if #atmoData.warnings > 0 then
        local warnText = table.concat(atmoData.warnings, " | ")
        ui:element({
            id = "warn_bg",
            type = "panel",
            rect = { unit = "px", x = 8, y = warningY, w = W - 16, h = 22 },
            style = { bg = "#7F1D1D" }
        })
        ui:element({
            id = "warn_txt",
            type = "label",
            rect = { unit = "px", x = 16, y = warningY + 2, w = W - 32, h = 18 },
            props = { text = "⚠ " .. warnText },
            style = { font_size = 12, color = "#FCA5A5", align = "center" }
        })
        warningY = warningY + 28
    end

    -- Main readings - pressure and temp
    local readingY = warningY + 10

    ui:element({
        id = "pres_lbl",
        type = "label",
        rect = { unit = "px", x = 16, y = readingY, w = 100, h = 16 },
        props = { text = "PRESSURE" },
        style = { font_size = 11, color = "#64748B", align = "left" }
    })

    ui:element({
        id = "pres_val",
        type = "label",
        rect = { unit = "px", x = 16, y = readingY + 16, w = 140, h = 28 },
        props = { text = fmt(atmoData.pressure) .. " kPa" },
        style = { font_size = 22, color = get_pressure_color(atmoData.pressure), align = "left" }
    })

    ui:element({
        id = "temp_lbl",
        type = "label",
        rect = { unit = "px", x = 180, y = readingY, w = 100, h = 16 },
        props = { text = "TEMPERATURE" },
        style = { font_size = 11, color = "#64748B", align = "left" }
    })

    ui:element({
        id = "temp_val",
        type = "label",
        rect = { unit = "px", x = 180, y = readingY + 16, w = 120, h = 28 },
        props = { text = fmt(atmoData.temperature) .. " °C" },
        style = { font_size = 22, color = get_temp_color(atmoData.temperature), align = "left" }
    })

    -- Gas composition section
    local gasY = readingY + 50

    ui:element({
        id = "gas_title",
        type = "label",
        rect = { unit = "px", x = 16, y = gasY, w = 150, h = 16 },
        props = { text = "GAS COMPOSITION" },
        style = { font_size = 11, color = "#64748B", align = "left" }
    })

    -- Gas bars
    local barW = 100
    local barH = 18
    local spacing = 24

    for i, gas in ipairs(atmoData.gases) do
        local y = gasY + (i * spacing)
        local barVal = math.min(gas.pct, 100)

        -- For low percentages, scale up for visibility
        local displayPct = barVal
        if gas.name == "CO2" or gas.name == "H2O" then
            displayPct = math.min(barVal * 50, 100)
        end

        ui:element({
            id = "gas_lbl_" .. i,
            type = "label",
            rect = { unit = "px", x = 16, y = y, w = 40, h = barH },
            props = { text = gas.name },
            style = { font_size = 12, color = "#94A3B8", align = "left" }
        })

        ui:element({
            id = "gas_bar_" .. i,
            type = "progress",
            rect = { unit = "px", x = 60, y = y + 2, w = barW, h = barH - 4 },
            props = { value = tostring(displayPct), max = "100" },
            style = { bg = "#1E293B", fill = gas.color }
        })

        local color = gas.color
        if gas.name == "O2" then
            color = get_o2_color(gas.pct)
        end

        ui:element({
            id = "gas_pct_" .. i,
            type = "label",
            rect = { unit = "px", x = 168, y = y, w = 60, h = barH },
            props = { text = fmt(gas.pct, 2) .. "%" },
            style = { font_size = 12, color = color, align = "left" }
        })
    end

    -- Right side - pie chart representation (simplified as stacked bar)
    local chartX = 260
    local chartY = gasY - 20
    local chartW = W - chartX - 20
    local chartH = 80

    ui:element({
        id = "chart_bg",
        type = "panel",
        rect = { unit = "px", x = chartX, y = chartY, w = chartW, h = chartH },
        style = { bg = "#111827" }
    })

    ui:element({
        id = "chart_title",
        type = "label",
        rect = { unit = "px", x = chartX, y = chartY + chartH + 4, w = chartW, h = 16 },
        props = { text = "COMPOSITION" },
        style = { font_size = 10, color = "#64748B", align = "center" }
    })

    -- Stacked horizontal bar
    local barX = chartX + 10
    local barY = chartY + 30
    local totalW = chartW - 20
    local stackH = 24

    local cumX = barX
    for i, gas in ipairs(atmoData.gases) do
        local w = math.max(2, (gas.pct / 100) * totalW)
        if gas.name == "CO2" or gas.name == "H2O" then
            w = math.max(4, w * 2) -- Make trace gases visible
        end
        ui:element({
            id = "stack_" .. i,
            type = "panel",
            rect = { unit = "px", x = cumX, y = barY, w = w, h = stackH },
            style = { bg = gas.color }
        })
        cumX = cumX + w
    end

    -- Status indicator
    local statusColor = "#00E676"
    local statusText = "NOMINAL"
    if #atmoData.warnings > 0 then
        statusColor = "#FF5252"
        statusText = "ALERT"
    end

    ui:element({
        id = "status_dot",
        type = "panel",
        rect = { unit = "px", x = W - 100, y = H - 28, w = 12, h = 12 },
        style = { bg = statusColor }
    })

    ui:element({
        id = "status_txt",
        type = "label",
        rect = { unit = "px", x = W - 84, y = H - 30, w = 70, h = 16 },
        props = { text = statusText },
        style = { font_size = 12, color = statusColor, align = "left" }
    })

    ui:commit()
end

render()

-- Main loop - simulate atmospheric fluctuations
local tick = 0
while true do
    tick = tick + 1

    -- Small random fluctuations
    atmoData.pressure = atmoData.pressure + (math.random() - 0.5) * 0.3
    atmoData.temperature = atmoData.temperature + (math.random() - 0.5) * 0.1
    atmoData.gases[1].pct = atmoData.gases[1].pct + (math.random() - 0.5) * 0.05
    atmoData.gases[3].pct = atmoData.gases[3].pct + (math.random() - 0.5) * 0.002

    -- Keep values in reasonable range
    atmoData.pressure = math.max(80, math.min(120, atmoData.pressure))
    atmoData.temperature = math.max(10, math.min(35, atmoData.temperature))
    atmoData.gases[1].pct = math.max(15, math.min(25, atmoData.gases[1].pct))
    atmoData.gases[3].pct = math.max(0.01, math.min(2, atmoData.gases[3].pct))

    if tick % 8 == 0 then
        render()
    end

    ic.yield()
end
