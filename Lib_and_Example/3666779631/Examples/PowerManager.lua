-- PowerManager.lua
-- Real-time power grid dashboard with battery monitoring and generator controls.
--
-- FEATURES:
--   - Battery charge percentage across all batteries on the network (average + total)
--   - Solid fuel generator status with on/off toggle buttons
--   - Animated battery gauge with color-coded thresholds
--   - Sparkline charge history
--

local ui = ss.ui.surface("main")
ss.ui.activate("main")

local W, H = 480, 272
local size = ui:size()
if size then W, H = size.w or W, size.h or H end

-- Top inset so headers/title bars stay inside visible glass on tight bezels (e.g. some modular screens).
local SAFE_TOP = 10

-- ==================== CONSTANTS ====================

local LT              = ic.enums.LogicType
local LBM             = ic.enums.LogicBatchMethod
local hash            = ic.hash
local batch_read      = ic.batch_read
local batch_write     = ic.batch_write

-- Prefab hashes for devices we care about
local BATTERY_LARGE   = hash("StructureBatteryLarge")
local BATTERY_SMALL   = hash("StructureBattery")
local BATTERY_NUCLEAR = hash("StationBatteryNuclear") -- Omni Transmitter Large mod
local GENERATOR_SOLID = hash("StructureSolidFuelGenerator")

local AUTO_GEN_ON_PCT  = 75
local AUTO_GEN_OFF_PCT = 99

-- History buffer length for sparkline
local HISTORY_LEN     = 50

-- ==================== STATE ====================

local batteryPct      = 0  -- Average charge ratio across all batteries (0-100)
local batteryCount    = 0  -- Number of batteries detected
local totalCharge     = 0  -- Sum of Charge across all batteries
local totalMaxCharge  = 0  -- Sum of Maximum across all batteries
local chargeHistory   = {} -- Rolling history for sparkline

local genCount        = 0
local genOnCount      = 0
local genPower        = 0   -- Total generator power output (W)
local genForceState   = nil -- nil = auto, true/false = forced
local autoGensDesired = false

local elapsed         = 0   -- Accumulated time from tick(dt)
local pulsePhase      = 0
local h               = nil -- Layout handles table (populated by build_ui)

-- Initialize history buffer
for i = 1, HISTORY_LEN do
    chargeHistory[i] = 0
end

-- ==================== COLORS ====================

local C = {
    bg          = "#06090F",
    header      = "#0C1220",
    panel       = "#0F1628",
    panel_light = "#151D30",
    divider     = "#1A2540",
    text        = "#E2E8F0",
    text_dim    = "#64748B",
    text_muted  = "#475569",
    accent      = "#38BDF8",
    green       = "#22C55E",
    yellow      = "#EAB308",
    orange      = "#F97316",
    red         = "#EF4444",
    gen_on      = "#22C55E",
    gen_off     = "#475569",
    btn_on      = "#166534",
    btn_off     = "#7F1D1D",
    btn_auto    = "#1E3A5F",
}

local BATTERY_COLOR_STOPS = {
    { 0.15, C.orange },
    { 0.40, C.yellow },
    { 0.70, C.green },
}

local BATTERY_SPARK_GRADIENT = {
    { 0.00, C.green },
    { 0.40, C.yellow },
    { 0.75, C.orange },
    { 1.00, C.red },
}

-- ==================== HELPERS ====================

local function battery_color(pct)
    if pct >= 70 then return C.green end
    if pct >= 40 then return C.yellow end
    if pct >= 15 then return C.orange end
    return C.red
end

local function status_text(pct)
    if pct >= 80 then return "OPTIMAL" end
    if pct >= 50 then return "NOMINAL" end
    if pct >= 20 then return "LOW" end
    if pct > 0 then return "CRITICAL" end
    return "DEPLETED"
end

local function status_color(pct)
    if pct >= 80 then return C.green end
    if pct >= 50 then return C.accent end
    if pct >= 20 then return C.orange end
    return C.red
end

local function fmt(v, d)
    if v == nil then return "--" end
    d = d or 1
    return string.format("%." .. d .. "f", v)
end

local function fmt_energy(joules)
    if joules == nil then return "--" end
    if joules >= 1000000 then return fmt(joules / 1000000, 1) .. " MJ" end
    if joules >= 1000 then return fmt(joules / 1000, 1) .. " kJ" end
    return fmt(joules, 0) .. " J"
end

local function push_history(buf, val)
    table.remove(buf, 1)
    buf[#buf + 1] = val
end

-- ==================== DATA COLLECTION ====================

local function read_batteries()
    local sources   = { BATTERY_LARGE, BATTERY_SMALL, BATTERY_NUCLEAR }
    local sumCharge = 0
    local sumMax    = 0
    local count     = 0

    for _, prefab in ipairs(sources) do
        local avgRatio = batch_read(prefab, LT.Ratio, LBM.Average)
        local sumC     = batch_read(prefab, LT.Charge, LBM.Sum)
        local sumM     = batch_read(prefab, LT.Maximum, LBM.Sum)

        if avgRatio ~= nil then
            sumCharge = sumCharge + (sumC or 0)
            sumMax    = sumMax + (sumM or 0)

            -- Estimate count via Sum / Average
            if sumC ~= nil and sumC > 0 then
                local avgC = batch_read(prefab, LT.Charge, LBM.Average)
                if avgC ~= nil and avgC > 0 then
                    count = count + math.floor((sumC / avgC) + 0.5)
                end
            elseif sumM ~= nil and sumM > 0 then
                local avgM = batch_read(prefab, LT.Maximum, LBM.Average)
                if avgM ~= nil and avgM > 0 then
                    count = count + math.floor((sumM / avgM) + 0.5)
                end
            end
        end
    end

    batteryCount   = count
    totalCharge    = sumCharge
    totalMaxCharge = sumMax
    batteryPct     = sumMax > 0 and (sumCharge / sumMax) * 100 or 0

    push_history(chargeHistory, batteryPct)
end

local function read_generators()
    local onCount = 0
    local total   = 0
    local power   = 0

    local sumOn   = batch_read(GENERATOR_SOLID, LT.On, LBM.Sum)
    if sumOn ~= nil then
        onCount = math.floor(sumOn + 0.5)

        -- Count via PrefabHash sum/average (every device of the same type has the same hash)
        local sumHash = batch_read(GENERATOR_SOLID, LT.PrefabHash, LBM.Sum)
        local avgHash = batch_read(GENERATOR_SOLID, LT.PrefabHash, LBM.Average)
        if sumHash ~= nil and avgHash ~= nil and avgHash ~= 0 then
            total = math.floor(math.abs(sumHash / avgHash) + 0.5)
        end
        if total < onCount then total = onCount end
        if total < 1 then total = 1 end

        local p = batch_read(GENERATOR_SOLID, LT.PowerGeneration, LBM.Sum)
        if p ~= nil then power = p end
    end

    genCount   = total
    genOnCount = onCount
    genPower   = power
end

local function apply_generator_override()
    if genForceState == true then
        batch_write(GENERATOR_SOLID, LT.On, 1)
    elseif genForceState == false then
        batch_write(GENERATOR_SOLID, LT.On, 0)
    else
        if batteryPct <= AUTO_GEN_ON_PCT then
            autoGensDesired = true
        elseif batteryPct >= AUTO_GEN_OFF_PCT then
            autoGensDesired = false
        end
        batch_write(GENERATOR_SOLID, LT.On, autoGensDesired and 1 or 0)
    end
end

-- ==================== BUILD UI (runs once) ====================
-- Returns handles table from ui:layout() so tick() can use h.id:set_props().

local function build_ui()
    ui:clear()

    local handles = ui:layout({
        layout = "flex",
        rect = { unit = "px", x = 0, y = SAFE_TOP, w = W, h = math.max(1, H - SAFE_TOP) },
        direction = "column",
        gap = 0,
        children = {
            -- ======== HEADER ========
            {
                id = "header",
                type = "panel",
                rect = { h = 36 },
                style = { bg = C.header },
                layout = "flex",
                direction = "row",
                gap = 6,
                align = "center",
                padding = { left = 14, right = 14, top = 6 },
                children = {
                    {
                        id = "title_icon",
                        type = "panel",
                        rect = { w = 4 },
                        style = { bg = C.accent }
                    },
                    {
                        id = "title",
                        type = "label",
                        flex = 1,
                        props = { text = "POWER MANAGER" },
                        style = { font_size = 14, color = C.text, align = "left" }
                    },
                    {
                        id = "status_dot",
                        type = "panel",
                        rect = { w = 10 },
                        style = { bg = C.text_dim }
                    },
                    {
                        id = "status_label",
                        type = "label",
                        rect = { w = 72 },
                        props = { text = "---" },
                        style = { font_size = 11, color = C.text_dim, align = "left" }
                    },
                }
            },

            -- ======== BODY: two columns ========
            {
                layout = "flex",
                flex = 1,
                direction = "row",
                gap = 6,
                padding = { left = 8, right = 8, top = 6, bottom = 6 },
                children = {
                    -- ──── LEFT COLUMN: Battery Info ────
                    {
                        layout = "flex",
                        flex = 3,
                        direction = "column",
                        gap = 4,
                        children = {
                            -- Battery section header
                            {
                                id = "bat_section",
                                type = "label",
                                rect = { h = 14 },
                                props = { text = "BATTERY NETWORK" },
                                style = { font_size = 9, color = C.accent, align = "left" }
                            },
                            -- Big percentage + gauge row
                            {
                                id = "bat_main_panel",
                                type = "panel",
                                rect = { h = 72 },
                                style = { bg = C.panel },
                                layout = "flex",
                                direction = "row",
                                gap = 12,
                                padding = { left = 12, right = 12, top = 8 },
                                children = {
                                    {
                                        layout = "flex",
                                        flex = 1,
                                        direction = "column",
                                        gap = 0,
                                        children = {
                                            {
                                                id = "bat_pct",
                                                type = "label",
                                                rect = { h = 36 },
                                                props = { text = "0.0%" },
                                                style = { font_size = 30, color = C.red, align = "left" }
                                            },
                                            {
                                                id = "bat_count",
                                                type = "label",
                                                rect = { h = 14 },
                                                props = { text = "0 batteries on network" },
                                                style = { font_size = 9, color = C.text_dim, align = "left" }
                                            },
                                            {
                                                id = "bat_energy",
                                                type = "label",
                                                rect = { h = 14 },
                                                props = { text = "-- / --" },
                                                style = { font_size = 9, color = C.text_muted, align = "left" }
                                            },
                                        }
                                    },
                                    -- Gauge
                                    {
                                        id = "bat_gauge",
                                        type = "gauge",
                                        rect = { w = 72 },
                                        props = {
                                            value = 0,
                                            min = 0,
                                            max = 100,
                                            warn = 0.4,
                                            danger = 0.8,
                                            invert = true,
                                            label = "",
                                            unit = "%",
                                        },
                                        style = {
                                            bg = C.panel,
                                            arc_thickness = 5,
                                            font_size = 0,
                                            value_color = C.red,
                                        }
                                    },
                                }
                            },
                            -- Charge bar
                            {
                                layout = "flex",
                                rect = { h = 16 },
                                direction = "row",
                                gap = 6,
                                children = {
                                    {
                                        id = "bat_bar",
                                        type = "progress",
                                        flex = 1,
                                        props = { value = 0, max = 100 },
                                        style = {
                                            bg = C.divider,
                                            fill = C.red,
                                            color_stops = BATTERY_COLOR_STOPS,
                                        }
                                    },
                                }
                            },
                            -- Sparkline
                            {
                                id = "bat_spark_lbl",
                                type = "label",
                                rect = { h = 12 },
                                props = { text = "CHARGE HISTORY" },
                                style = { font_size = 8, color = C.text_dim, align = "left" }
                            },
                            {
                                id = "bat_spark",
                                type = "sparkline",
                                flex = 1,
                                props = { data = chargeHistory, min = 0, max = 100 },
                                style = {
                                    bg = C.panel,
                                    line_color = "#FFFFFF",
                                    fill_color = "#FFFFFF28",
                                    gradient = BATTERY_SPARK_GRADIENT,
                                    gradient_dir = "vertical",
                                    thickness = "1.5"
                                }
                            },
                        }
                    },

                    -- ──── RIGHT COLUMN: Generators ────
                    {
                        layout = "flex",
                        flex = 2,
                        direction = "column",
                        gap = 4,
                        children = {
                            -- Section header
                            {
                                id = "gen_section",
                                type = "label",
                                rect = { h = 14 },
                                props = { text = "SOLID FUEL GENERATORS" },
                                style = { font_size = 9, color = C.orange, align = "left" }
                            },
                            -- Info panel (always present; text updates dynamically)
                            {
                                id = "gen_panel",
                                type = "panel",
                                flex = 1,
                                style = { bg = C.panel },
                                layout = "flex",
                                direction = "column",
                                gap = 4,
                                padding = { left = 10, right = 10, top = 8, bottom = 8 },
                                children = {
                                    -- Summary row
                                    {
                                        layout = "flex",
                                        rect = { h = 20 },
                                        direction = "row",
                                        gap = 8,
                                        children = {
                                            {
                                                id = "gen_count_lbl",
                                                type = "label",
                                                flex = 1,
                                                props = { text = "Scanning…" },
                                                style = { font_size = 11, color = C.text, align = "left" }
                                            },
                                            {
                                                id = "gen_status_dot",
                                                type = "panel",
                                                rect = { w = 10 },
                                                style = { bg = C.gen_off }
                                            },
                                            {
                                                id = "gen_status_txt",
                                                type = "label",
                                                rect = { w = 60 },
                                                props = { text = "IDLE" },
                                                style = { font_size = 11, color = C.gen_off, align = "left" }
                                            },
                                        }
                                    },
                                    -- Power output row
                                    {
                                        layout = "flex",
                                        rect = { h = 16 },
                                        direction = "row",
                                        gap = 8,
                                        children = {
                                            {
                                                id = "gen_power_lbl",
                                                type = "label",
                                                rect = { w = 100 },
                                                props = { text = "Total Output:" },
                                                style = { font_size = 10, color = C.text_dim, align = "left" }
                                            },
                                            {
                                                id = "gen_power_val",
                                                type = "label",
                                                flex = 1,
                                                props = { text = "0 W" },
                                                style = { font_size = 10, color = C.text_dim, align = "left" }
                                            },
                                        }
                                    },
                                }
                            },
                            -- Override label
                            {
                                id = "override_lbl",
                                type = "label",
                                rect = { h = 12 },
                                props = { text = "OVERRIDE: AUTO" },
                                style = { font_size = 9, color = C.text_dim, align = "center" }
                            },
                            -- Control buttons
                            {
                                layout = "flex",
                                rect = { h = 32 },
                                direction = "row",
                                gap = 4,
                                children = {
                                    {
                                        id = "btn_all_on",
                                        type = "button",
                                        flex = 1,
                                        props = { text = "ALL ON" },
                                        style = { bg = C.btn_on, text = "#FFFFFF", font_size = 11 },
                                        on_click = function()
                                            genForceState = true
                                            apply_generator_override()
                                            update_override_ui()
                                        end,
                                    },
                                    {
                                        id = "btn_all_off",
                                        type = "button",
                                        flex = 1,
                                        props = { text = "ALL OFF" },
                                        style = { bg = C.btn_off, text = "#FFFFFF", font_size = 11 },
                                        on_click = function()
                                            genForceState = false
                                            apply_generator_override()
                                            update_override_ui()
                                        end,
                                    },
                                    {
                                        id = "btn_auto",
                                        type = "button",
                                        flex = 1,
                                        props = { text = "AUTO" },
                                        style = { bg = C.accent, text = "#FFFFFF", font_size = 11 },
                                        on_click = function()
                                            genForceState = nil
                                            update_override_ui()
                                        end,
                                    },
                                }
                            },
                        }
                    },
                }
            },

            -- ======== FOOTER ========
            {
                id = "footer_bar",
                type = "panel",
                rect = { h = 18 },
                style = { bg = C.header },
                layout = "flex",
                direction = "row",
                gap = 0,
                padding = { left = 14, right = 14, top = 2 },
                children = {
                    {
                        id = "footer_left",
                        type = "label",
                        flex = 1,
                        props = { text = "T+0" },
                        style = { font_size = 8, color = C.text_muted, align = "left" }
                    },
                    {
                        id = "footer_right",
                        type = "label",
                        rect = { w = 140 },
                        props = { text = "REAL-TIME MONITORING" },
                        style = { font_size = 8, color = C.text_muted, align = "right" }
                    },
                }
            },
        }
    })

    ui:commit()
    return handles
end

-- ==================== LIVE UPDATE FUNCTIONS ====================
-- Called from tick(dt) - update elements via layout handles h.id:set_props/set_style.

-- Update override label and button highlight colors after a click
function update_override_ui()
    if not h then return end
    local lbl   = "AUTO"
    local color = C.text_dim
    if genForceState == true then
        lbl = "FORCED ON"; color = C.text
    elseif genForceState == false then
        lbl = "FORCED OFF"; color = C.text
    end
    if h.override_lbl then
        h.override_lbl:set_props({ text = "OVERRIDE: " .. lbl })
        h.override_lbl:set_style({ font_size = 9, color = color, align = "center" })
    end
    if h.btn_all_on then
        h.btn_all_on:set_style({ bg = genForceState == true and C.green or C.btn_on, text = "#FFFFFF", font_size = 11 })
    end
    if h.btn_all_off then
        h.btn_all_off:set_style({ bg = genForceState == false and C.red or C.btn_off, text = "#FFFFFF", font_size = 11 })
    end
    if h.btn_auto then
        h.btn_auto:set_style({ bg = genForceState == nil and C.accent or C.btn_auto, text = "#FFFFFF", font_size = 11 })
    end
    ui:commit()
end

-- Push latest battery data into the UI elements
local function update_battery_ui(dt)
    if not h then return end
    local batCol  = battery_color(batteryPct)
    local statTxt = status_text(batteryPct)
    local statCol = status_color(batteryPct)

    -- Header status
    if h.status_dot then h.status_dot:set_style({ bg = statCol }) end
    if h.status_label then
        h.status_label:set_props({ text = statTxt })
        h.status_label:set_style({ font_size = 11, color = statCol, align = "left" })
    end

    -- Big percentage
    if h.bat_pct then
        h.bat_pct:set_props({ text = fmt(batteryPct, 1) .. "%" })
        h.bat_pct:set_style({ font_size = 30, color = batCol, align = "left" })
    end

    -- Battery count & energy
    if h.bat_count then h.bat_count:set_props({ text = batteryCount .. " batteries on network" }) end
    if h.bat_energy then h.bat_energy:set_props({ text = fmt_energy(totalCharge) .. " / " .. fmt_energy(totalMaxCharge) }) end

    -- Gauge
    if h.bat_gauge then
        h.bat_gauge:set_props({
            value = batteryPct,
            min = 0,
            max = 100,
            warn = 0.4,
            danger = 0.8,
            invert = true,
            label = "",
            unit = "%"
        })
        h.bat_gauge:set_style({ bg = C.panel, arc_thickness = 5, font_size = 0, value_color = batCol })
    end

    -- Progress bar
    if h.bat_bar then
        h.bat_bar:set_props({ value = batteryPct, max = 100 })
        h.bat_bar:set_style({ bg = C.divider, fill = C.red, color_stops = BATTERY_COLOR_STOPS })
    end

    -- Sparkline (update data + gradient fill alpha with pulse animation)
    pulsePhase = pulsePhase + (dt or 0.1) * 2
    local pulse = 0.7 + 0.3 * math.sin(pulsePhase)
    local glowAlpha = string.format("%02X", math.floor(pulse * 40))
    if h.bat_spark then
        h.bat_spark:set_props({ data = chargeHistory, min = 0, max = 100 })
        h.bat_spark:set_style({
            bg = C.panel,
            line_color = "#FFFFFF",
            fill_color = "#FFFFFF" .. glowAlpha,
            gradient = BATTERY_SPARK_GRADIENT,
            gradient_dir = "vertical",
            thickness = "1.5"
        })
    end
end

-- Push latest generator data into the UI elements
local function update_generator_ui()
    if not h then return end
    if genCount == 0 then
        if h.gen_count_lbl then h.gen_count_lbl:set_props({ text = "No generators detected" }) end
        if h.gen_status_txt then h.gen_status_txt:set_props({ text = "N/A" }) end
        if h.gen_status_dot then h.gen_status_dot:set_style({ bg = C.gen_off }) end
        if h.gen_status_txt then h.gen_status_txt:set_style({ font_size = 11, color = C.gen_off, align = "left" }) end
        if h.gen_power_val then
            h.gen_power_val:set_props({ text = "0 W" })
            h.gen_power_val:set_style({ font_size = 10, color = C.text_dim, align = "left" })
        end
    else
        if h.gen_count_lbl then
            h.gen_count_lbl:set_props({
                text = "DETECTED: " ..
                    genCount .. "   RUNNING: " .. genOnCount
            })
        end

        local active = genOnCount > 0
        if h.gen_status_dot then h.gen_status_dot:set_style({ bg = active and C.gen_on or C.gen_off }) end
        if h.gen_status_txt then
            h.gen_status_txt:set_props({ text = active and "ACTIVE" or "IDLE" })
            h.gen_status_txt:set_style({ font_size = 11, color = active and C.gen_on or C.gen_off, align = "left" })
        end

        if h.gen_power_val then
            h.gen_power_val:set_props({ text = fmt(genPower, 0) .. " W" })
            h.gen_power_val:set_style({ font_size = 10, color = active and C.yellow or C.text_dim, align = "left" })
        end
    end
end

-- ==================== PERSISTENCE (ic.persist) ====================
local PERSIST_KEY = "gen_force"

local function persist_restore_gen_force()
    if not ic.persist.has(PERSIST_KEY) then return end
    local blob = ic.persist.get(PERSIST_KEY)
    if blob == "on" then
        genForceState = true
    elseif blob == "off" then
        genForceState = false
    else
        genForceState = nil
    end
end

local function persist_save_gen_force()
    if genForceState == nil then
        ic.persist.set(PERSIST_KEY, "auto")
    else
        ic.persist.set(PERSIST_KEY, genForceState and "on" or "off")
    end
end

persist_restore_gen_force()

-- ==================== BOOT ====================
-- Build UI layout once, capture handles, then tick(dt) handles live updates.

h = build_ui()

-- ==================== TICK CALLBACK ====================
-- Global tick(dt) called by ScriptedScreens runtime each game tick.
-- Reads network data, updates UI via layout handles, then commits.

function tick(dt)
    elapsed = elapsed + dt

    -- Collect data from the network
    read_batteries()
    read_generators()
    apply_generator_override()

    -- Update UI via layout handles
    update_battery_ui(dt)
    update_generator_ui()

    if h and h.footer_left then
        h.footer_left:set_props({ text = string.format("T+%.0f", elapsed) })
    end

    persist_save_gen_force()

    ui:commit()
end
