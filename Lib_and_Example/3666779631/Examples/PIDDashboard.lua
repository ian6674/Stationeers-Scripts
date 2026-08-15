--[[
    PIDDashboard.lua

    A ScriptedScreens display that uses the "pid" and "gas" library modules
    from library chips on the same data cable network.

    Demonstrates that ScriptedScreens scripts CAN require() library modules -
    they just can't HOST them (no --@module on boards/cartridges).

    SETUP:
      1. Place LibraryModule_PID.lua on a Lua chip in an IC Housing on the data network
      2. Place LibraryModule_Gas.lua on another Lua chip in an IC Housing on the data network
      3. Put this script on a ScriptedScreens motherboard on the SAME data network
      4. Wire d0 to a Gas Sensor (room atmosphere)
      5. Wire d1 to an Active Vent or Volume Pump (pressure control output)

    FEATURES:
      - Live PID controller visualization (setpoint, error, output)
      - Gas composition bar chart from sensor readings
      - Color-coded pressure/temperature status
      - PID tuning controls (buttons to adjust Kp/Ki/Kd)
]]

-- Load library modules from library chips on the data network
local pid = require("pid")
local gas = require("gas")

local ui = ss.ui.surface("main")
ss.ui.activate("main")

local size = ui:size()
local W, H = 480, 272
if size then W, H = size.w or W, size.h or H end

local LT          = ic.enums.LogicType

-- ── Theme ──────────────────────────────────────────────────────────────────────
local C           = {
    bg     = "#0A0E1A",
    panel  = "#111827",
    header = "#0F172A",
    card   = "#1E293B",
    text   = "#E2E8F0",
    dim    = "#94A3B8",
    muted  = "#475569",
    accent = "#38BDF8",
    green  = "#22C55E",
    yellow = "#EAB308",
    orange = "#F97316",
    red    = "#EF4444",
    blue   = "#3B82F6",
}

-- ── State ──────────────────────────────────────────────────────────────────────
local ctrl        = pid.pressure(101.325) -- PID controller targeting 1 atm
local history     = {}                    -- Pressure history for sparkline
local MAX_HISTORY = 40
local connected   = false

-- ── Helpers ────────────────────────────────────────────────────────────────────
local function fmt(v, d)
    if v == nil then return "--" end
    return string.format("%." .. (d or 1) .. "f", v)
end

local function pressure_color(kpa)
    if kpa == nil then return C.muted end
    -- Armstrong limit (6.3 kPa) = vacuum damage, 1 atm = ideal
    if kpa >= gas.SAFE.armstrong_limit and kpa <= gas.SAFE.pressure_1atm * 6 then
        return C.green
    elseif kpa < gas.SAFE.armstrong_limit then
        return C.blue
    else
        return C.red
    end
end

local function temp_color(k)
    if k == nil then return C.muted end
    if k >= gas.SAFE.temp_min and k <= gas.SAFE.temp_max then
        return C.green
    elseif k < gas.SAFE.temp_min then
        return C.blue
    else
        return C.red
    end
end

-- ── Gas bar data builder ───────────────────────────────────────────────────────
local function build_gas_bars(ratios)
    local bars = {}
    -- Colors keyed by GasType flag values (from Chemistry.GasType)
    local colors = {
        [1]     = "#3B82F6", -- O2 blue
        [2]     = "#A855F7", -- N2 purple
        [4]     = "#F97316", -- CO2 orange
        [8]     = "#EF4444", -- VOL red
        [16]    = "#84CC16", -- POL lime
        [32]    = "#06B6D4", -- H2O cyan
        [64]    = "#EC4899", -- N2O pink
        [1024]  = "#06B6D4", -- Steam cyan
        [16384] = "#38BDF8", -- H2 light blue
    }

    for gas_type, ratio in pairs(ratios) do
        if ratio > 0.001 then
            bars[#bars + 1] = {
                label = gas.LABELS[gas_type] or ("G" .. gas_type),
                ratio = ratio,
                pct   = ratio * 100,
                color = colors[gas_type] or C.text,
            }
        end
    end

    -- Sort by ratio descending
    table.sort(bars, function(a, b) return a.ratio > b.ratio end)
    return bars
end

-- ── Render ─────────────────────────────────────────────────────────────────────
local function render(pressure, temp_k, pid_output, gas_ratios)
    ui:clear()

    local err = ctrl.setpoint - (pressure or 0)
    local temp_c = temp_k and gas.k_to_c(temp_k)

    -- Build gas composition bars
    local bars = build_gas_bars(gas_ratios or {})

    -- Build sparkline data string
    local spark_data = {}
    for i, v in ipairs(history) do
        spark_data[i] = tostring(v)
    end
    local spark_str = table.concat(spark_data, ",")

    -- ── Layout ─────────────────────────────────────────────────────────────────
    -- Background
    ui:element({
        id = "bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = H },
        style = { bg = C.bg },
    })

    local h = ui:layout({
        layout = "flex",
        direction = "column",
        gap = 0,
        rect = { unit = "px", x = 0, y = 0, w = W, h = H },
        children = {
            -- ── Header ─────────────────────────────────────────────────────────
            {
                id = "hdr",
                type = "panel",
                rect = { h = 30 },
                style = { bg = C.header },
                layout = "flex",
                direction = "row",
                gap = 0,
                padding = { left = 10, right = 10, top = 5, bottom = 5 },
                children = {
                    {
                        id = "title",
                        type = "label",
                        flex = 1,
                        props = { text = "PID PRESSURE CONTROLLER" },
                        style = { font_size = 14, color = C.accent, align = "left" },
                    },
                    {
                        id = "status",
                        type = "label",
                        rect = { w = 100 },
                        props = { text = connected and "LINKED" or "NO SENSOR" },
                        style = { font_size = 10, color = connected and C.green or C.red, align = "right" },
                    },
                },
            },

            -- ── Body ───────────────────────────────────────────────────────────
            {
                layout = "flex",
                flex = 1,
                direction = "row",
                gap = 6,
                padding = 6,
                children = {
                    -- ── Left column: PID info + sparkline ──────────────────────
                    {
                        layout = "flex",
                        flex = 3,
                        direction = "column",
                        gap = 4,
                        children = {
                            -- Gauges row
                            {
                                layout = "flex",
                                rect = { h = 70 },
                                direction = "row",
                                gap = 4,
                                children = {
                                    {
                                        id = "g_press",
                                        type = "gauge",
                                        flex = 1,
                                        props = {
                                            value = fmt(pressure, 1),
                                            min = "0",
                                            max = "200",
                                            warn = "0.75",
                                            danger = "0.90",
                                            label = "PRESSURE",
                                            unit = " kPa",
                                        },
                                        style = {
                                            bg = C.panel,
                                            arc_thickness = "5",
                                            font_size = "9",
                                            value_color = pressure_color(pressure),
                                            label_color = C.dim,
                                        },
                                    },
                                    {
                                        id = "g_temp",
                                        type = "gauge",
                                        flex = 1,
                                        props = {
                                            value = fmt(temp_k, 0),
                                            min = "200",
                                            max = "400",
                                            warn = "0.70",
                                            danger = "0.85",
                                            label = "TEMP",
                                            unit = " K",
                                        },
                                        style = {
                                            bg = C.panel,
                                            arc_thickness = "5",
                                            font_size = "9",
                                            value_color = temp_color(temp_k),
                                            label_color = C.dim,
                                        },
                                    },
                                },
                            },

                            -- PID stats row
                            {
                                id = "pid_panel",
                                type = "panel",
                                rect = { h = 50 },
                                style = { bg = C.panel },
                                layout = "flex",
                                direction = "column",
                                gap = 2,
                                padding = { left = 8, right = 8, top = 4, bottom = 4 },
                                children = {
                                    {
                                        id = "pid_sp",
                                        type = "label",
                                        rect = { h = 13 },
                                        props = { text = "SETPOINT: " .. fmt(ctrl.setpoint, 1) .. " kPa" },
                                        style = { font_size = 10, color = C.accent, align = "left" },
                                    },
                                    {
                                        id = "pid_err",
                                        type = "label",
                                        rect = { h = 13 },
                                        props = { text = string.format("ERROR: %+.2f kPa", err) },
                                        style = { font_size = 10, color = math.abs(err) < 2 and C.green or C.yellow, align = "left" },
                                    },
                                    {
                                        id = "pid_out",
                                        type = "label",
                                        rect = { h = 13 },
                                        props = { text = string.format("OUTPUT: %.1f%%", pid_output or 0) },
                                        style = { font_size = 10, color = C.text, align = "left" },
                                    },
                                },
                            },

                            -- Pressure sparkline
                            {
                                id = "spark",
                                type = "sparkline",
                                flex = 1,
                                props = {
                                    data = spark_str,
                                    min = "0",
                                    max = "200",
                                    label = "PRESSURE HISTORY",
                                },
                                style = {
                                    bg = C.panel,
                                    line = C.accent,
                                    fill = C.accent .. "20",
                                    font_size = "8",
                                    label_color = C.dim,
                                },
                            },

                            -- Temp in Celsius
                            {
                                id = "temp_c",
                                type = "label",
                                rect = { h = 14 },
                                props = { text = temp_c and (fmt(temp_c, 1) .. " °C") or "--- °C" },
                                style = { font_size = 10, color = C.dim, align = "center" },
                            },
                        },
                    },

                    -- ── Right column: gas composition ──────────────────────────
                    {
                        id = "gas_panel",
                        type = "panel",
                        rect = { w = 140 },
                        style = { bg = C.panel },
                        layout = "flex",
                        direction = "column",
                        gap = 3,
                        padding = 6,
                        children = (function()
                            local children = {
                                {
                                    id = "gas_title",
                                    type = "label",
                                    rect = { h = 16 },
                                    props = { text = "GAS COMPOSITION" },
                                    style = { font_size = 10, color = C.dim, align = "center" },
                                },
                            }
                            -- Gas bar rows
                            for i, bar in ipairs(bars) do
                                if i <= 6 then
                                    children[#children + 1] = {
                                        layout = "flex",
                                        rect = { h = 22 },
                                        direction = "column",
                                        gap = 1,
                                        children = {
                                            {
                                                layout = "flex",
                                                rect = { h = 12 },
                                                direction = "row",
                                                gap = 4,
                                                children = {
                                                    {
                                                        id = "gl_" .. i,
                                                        type = "label",
                                                        flex = 1,
                                                        props = { text = bar.label },
                                                        style = { font_size = 9, color = bar.color, align = "left" },
                                                    },
                                                    {
                                                        id = "gp_" .. i,
                                                        type = "label",
                                                        rect = { w = 45 },
                                                        props = { text = fmt(bar.pct, 1) .. "%" },
                                                        style = { font_size = 9, color = C.text, align = "right" },
                                                    },
                                                },
                                            },
                                            {
                                                id = "gb_" .. i,
                                                type = "progress",
                                                rect = { h = 6 },
                                                props = { value = fmt(bar.pct, 1), min = "0", max = "100" },
                                                style = { bg = "#1A1A2E", fill = bar.color },
                                            },
                                        },
                                    }
                                end
                            end
                            -- Empty state
                            if #bars == 0 then
                                children[#children + 1] = {
                                    id = "no_gas",
                                    type = "label",
                                    flex = 1,
                                    props = { text = "NO GAS DATA" },
                                    style = { font_size = 10, color = C.muted, align = "center" },
                                }
                            end
                            return children
                        end)(),
                    },
                },
            },

            -- ── Footer ─────────────────────────────────────────────────────────
            {
                id = "footer",
                type = "panel",
                rect = { h = 18 },
                style = { bg = C.header },
                layout = "flex",
                direction = "row",
                gap = 0,
                padding = { left = 10, right = 10, top = 2, bottom = 2 },
                children = {
                    {
                        id = "f_gains",
                        type = "label",
                        flex = 1,
                        props = { text = string.format("Kp=%.1f  Ki=%.2f  Kd=%.1f", ctrl.kp, ctrl.ki, ctrl.kd) },
                        style = { font_size = 9, color = C.dim, align = "left" },
                    },
                    {
                        id = "f_lib",
                        type = "label",
                        rect = { w = 160 },
                        props = { text = "pid + gas libs via require()" },
                        style = { font_size = 8, color = C.muted, align = "right" },
                    },
                },
            },
        },
    })

    ui:commit()
end

-- ── Main loop ──────────────────────────────────────────────────────────────────
-- Initial render with no data
render(nil, nil, 0, {})

while true do
    -- Read sensor on d0
    local pressure = ic.read(0, LT.Pressure)
    local temp_k   = ic.read(0, LT.Temperature)

    connected      = (pressure ~= nil)

    -- Read gas ratios using the gas library's RATIO_FIELD table (keyed by GasType flags)
    local ratios   = {}
    for gas_type, field in pairs(gas.RATIO_FIELD) do
        if LT[field] then
            ratios[gas_type] = ic.read(0, LT[field]) or 0
        end
    end

    -- Run PID controller
    local output = 0
    if connected and pressure then
        output = ctrl:update(ctrl.setpoint, pressure, 0.5) -- ~0.5s per game tick
        ic.write(1, LT.Setting, output)

        -- Track pressure history for sparkline
        history[#history + 1] = pressure
        if #history > MAX_HISTORY then
            table.remove(history, 1)
        end
    end

    -- Render every tick (ScriptedScreens uses yield-based loop)
    render(pressure, temp_k, output, ratios)

    yield()
end
