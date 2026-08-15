--[[
    AtmosAnalyzer.lua

    A tablet cartridge that displays atmospheric information for whatever
    the player is looking at. Replicates the base game's Atmos Analyzer
    cartridge fields and layout using ScriptedScreens tablet targeting.

    Usage:
    1. Insert this cartridge into a tablet
    2. Hold the tablet and look at objects with internal atmospheres
       (pipes, tanks, rooms via vents, etc.)
    3. The display shows pressure, temperature, and gas composition

    API demonstrated:
    - ss.tablet.target(callback, interval, includeRoomAtmos) - subscribe to target updates
    - Target snapshot: atmosphere.pressure, temperature, gases, etc.
    - Room/world snapshots: atmosphere_mode + room info when no target
]]

local ui = ss.ui.surface("main")
ss.ui.activate("main")

-- Screen dimensions
local size = ui:size()
local W, H = 480, 272
if size then W, H = size.w or W, size.h or H end

-- Color palette
local COLORS = {
    bg = "#0A0E1A",
    header = "#1E293B",
    text = "#E2E8F0",
    text_dim = "#94A3B8",
    accent = "#22C55E",
    warning = "#FFEB3B",
    danger = "#EF4444",

    -- Gas colors (matching game style)
    oxygen = "#3B82F6",    -- Blue
    nitrogen = "#A855F7",  -- Purple
    co2 = "#F97316",       -- Orange
    methane = "#EF4444",   -- Red (formerly Volatiles)
    pollutant = "#84CC16", -- Lime
    water = "#06B6D4",     -- Cyan
    n2o = "#EC4899",       -- Pink
    hydrogen = "#38BDF8",  -- Light blue
}

-- Current target data
local target = nil

-- Formatting helpers
local function fmt(value, decimals)
    decimals = decimals or 1
    if value == nil then return "N/A" end
    return string.format("%." .. decimals .. "f", value)
end

local function fmt_sig(value, sig)
    if value == nil then return "N/A" end
    if value == 0 then return "0" end
    local abs_value = math.abs(value)
    local digits = math.floor(math.log(abs_value, 10)) + 1
    local decimals = math.max(sig - digits, 0)
    return string.format("%." .. decimals .. "f", value)
end

local function fmt_prefix(value, unit, sig)
    if value == nil then return "N/A" end
    sig = sig or 3
    local abs_value = math.abs(value)
    local scaled = value
    local prefix = ""
    if abs_value >= 1e9 then
        scaled = value / 1e9
        prefix = "G"
    elseif abs_value >= 1e6 then
        scaled = value / 1e6
        prefix = "M"
    elseif abs_value >= 1e3 then
        scaled = value / 1e3
        prefix = "k"
    elseif abs_value >= 1 then
        scaled = value
        prefix = ""
    elseif abs_value >= 1e-3 then
        scaled = value * 1e3
        prefix = "m"
    elseif abs_value >= 1e-6 then
        scaled = value * 1e6
        prefix = "u"
    else
        scaled = value * 1e9
        prefix = "n"
    end
    return fmt_sig(scaled, sig) .. " " .. prefix .. unit
end

local function fmt_pressure(pa)
    if pa == nil or pa <= 0 then return "N/A" end
    return fmt_prefix(pa, "Pa", 3)
end

local function fmt_temp(kelvin)
    if kelvin == nil then return "N/A" end
    local celsius = kelvin - 273.15
    return fmt(celsius, 1) .. " °C"
end

local function fmt_liters(liters)
    if liters == nil or liters <= 0 then return "N/A" end
    return fmt_sig(liters, 3) .. " L"
end

local function fmt_energy(joules)
    if joules == nil or math.abs(joules) < 1e-6 then return "N/A" end
    local abs_value = math.abs(joules)
    if abs_value > 1e6 then
        return fmt_sig(joules / 1e6, 3) .. " MJ"
    end
    if abs_value > 1e3 then
        return fmt_sig(joules / 1e3, 3) .. " kJ"
    end
    if abs_value < 1 then
        return fmt_sig(joules * 1e3, 3) .. " mJ"
    end
    return fmt_sig(joules, 3) .. " J"
end

local function fmt_percent(value)
    if value == nil then return "N/A" end
    return fmt(value, 0) .. "%"
end

local function can_use_target(data)
    if not data or not data.has_target then
        return false
    end
    if not data.atmosphere then
        return false
    end
    return true
end

local function get_world_snapshot(data)
    if not data then
        return nil
    end
    if data.world then
        return data.world
    end
    if not data.has_target then
        return data
    end
    return nil
end

local function get_selected_title(data, world_data, use_target)
    if use_target and data then
        local name = data.display_name or data.custom_name or data.prefab_name or "UNKNOWN"
        return string.upper(name)
    end
    if world_data and world_data.room then
        local room_name = world_data.room.name
        if room_name and room_name ~= "" then
            return "ROOM " .. string.upper(room_name)
        end
        if world_data.room.id and world_data.room.id ~= 0 then
            return "ROOM " .. tostring(world_data.room.id)
        end
    end
    return "WORLD"
end

local function build_gas_rows(atmos)
    local rows = {}
    if not atmos or not atmos.gases then
        return rows
    end

    local gases = atmos.gases
    local total = atmos.total_moles or 0
    local gas_order = {
        { key = "Oxygen",              label = "O2",    color = COLORS.oxygen,    icon = "Oxygen" },
        { key = "Nitrogen",            label = "N2",    color = COLORS.nitrogen,  icon = "Nitrogen" },
        { key = "Methane",             label = "CH4",   color = COLORS.methane,   icon = "Methane" },
        { key = "Water",               label = "H2O",   color = COLORS.water,     icon = "Water" },
        { key = "Steam",               label = "STM",   color = COLORS.water,     icon = "Steam" },
        { key = "PollutedWater",       label = "P-H2O", color = COLORS.water,     icon = "PollutedWater" },
        { key = "Pollutant",           label = "POL",   color = COLORS.pollutant, icon = "Pollutant" },
        { key = "CarbonDioxide",       label = "CO2",   color = COLORS.co2,       icon = "CarbonDioxide" },
        { key = "NitrousOxide",        label = "N2O",   color = COLORS.n2o,       icon = "NitrousOxide" },
        { key = "Hydrogen",            label = "H2",    color = COLORS.hydrogen,  icon = "Hydrogen" },
        { key = "LiquidNitrogen",      label = "L-N2",  color = COLORS.nitrogen,  icon = "LiquidNitrogen" },
        { key = "LiquidOxygen",        label = "L-O2",  color = COLORS.oxygen,    icon = "LiquidOxygen" },
        { key = "LiquidMethane",       label = "LCH4",  color = COLORS.methane,   icon = "LiquidMethane" },
        { key = "LiquidCarbonDioxide", label = "L-CO2", color = COLORS.co2,       icon = "LiquidCarbonDioxide" },
        { key = "LiquidPollutant",     label = "L-POL", color = COLORS.pollutant, icon = "LiquidPollutant" },
        { key = "LiquidNitrousOxide",  label = "L-N2O", color = COLORS.n2o,       icon = "LiquidNitrousOxide" },
        { key = "LiquidHydrogen",      label = "L-H2",  color = COLORS.hydrogen,  icon = "LiquidHydrogen" },
    }

    for _, gas in ipairs(gas_order) do
        local moles = gases[gas.key]
        if moles and moles > 0 then
            local ratio = (total > 0) and (moles / total) or 0
            local volume = nil
            if atmos.volume and atmos.volume > 0 and total > 0 then
                -- Approximate volume based on total volume and mole ratio.
                volume = atmos.volume * ratio
            end
            table.insert(rows, {
                key = gas.key,
                label = gas.label,
                color = gas.color or COLORS.text,
                icon = gas.icon or gas.key,
                moles = moles,
                percent = ratio * 100,
                volume = volume,
            })
        end
    end

    table.sort(rows, function(a, b)
        return a.moles > b.moles
    end)

    return rows
end

-- Render the UI
local function render()
    ss.ui.activate("main")
    local updated_size = ui:size()
    if updated_size then W, H = updated_size.w or W, updated_size.h or H end
    ui:clear()

    -- Background
    ui:element({
        id = "bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = H },
        style = { bg = COLORS.bg }
    })

    -- Header
    local header = ui:element({
        id = "header",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = 44 },
        style = { bg = COLORS.header }
    })

    header:element({
        id = "title",
        type = "label",
        rect = { unit = "px", x = 16, y = 10, w = 220, h = 24 },
        props = { text = "ATMOS ANALYZER" },
        style = { font_size = 18, color = COLORS.text, align = "left" }
    })

    local world_snapshot = get_world_snapshot(target)
    local use_target = can_use_target(target)
    local active_snapshot = use_target and target or world_snapshot

    header:element({
        id = "selected_title",
        type = "label",
        rect = { unit = "px", x = W - 260, y = 12, w = 244, h = 20 },
        props = { text = get_selected_title(target, world_snapshot, use_target) },
        style = { font_size = 12, color = COLORS.text_dim, align = "right" }
    })

    local atmos = active_snapshot and active_snapshot.atmosphere or nil
    local has_atmos = atmos ~= nil
    local pressure = has_atmos and atmos.pressure or nil
    local total_moles = has_atmos and atmos.total_moles or nil
    local temperature = has_atmos and atmos.temperature or nil
    local volume = has_atmos and atmos.volume or nil
    local liquid_volume = has_atmos and atmos.total_volume_liquids or nil
    local liquid_ratio = has_atmos and atmos.liquid_volume_ratio or nil
    local latent_energy = has_atmos and atmos.last_tick_latent_energy or nil
    local pressure_delta = has_atmos and atmos.pressure_delta or nil
    local warning_pressure = has_atmos and atmos.warning_pressure or nil
    local danger_pressure = has_atmos and atmos.danger_pressure or nil

    local atmos_mode = active_snapshot and active_snapshot.atmosphere_mode or (has_atmos and atmos.mode or nil)
    local allowed_matter_state = has_atmos and atmos.allowed_matter_state or nil
    local thermal = use_target and target and target.thermal or nil
    local show_thermal = thermal ~= nil

    local pressure_text = (pressure and pressure > 0)
        and fmt_pressure(pressure)
        or "N/A"
    local temp_text = (total_moles and total_moles > 0)
        and fmt_temp(temperature)
        or "N/A"
    local capacity_text = fmt_liters(volume)
    local liquid_text = (liquid_volume and liquid_volume > 0) and fmt_liters(liquid_volume) or "N/A"
    local stress_text = "N/A"
    local convected_text = show_thermal and fmt_energy(thermal.energy_convected) or "N/A"
    local radiated_text = show_thermal and fmt_energy(thermal.energy_radiated) or "N/A"
    local latent_text = show_thermal and fmt_energy(latent_energy) or "N/A"

    local pressure_color = COLORS.accent
    if pressure_delta and warning_pressure and danger_pressure then
        if pressure_delta >= danger_pressure then
            pressure_color = COLORS.danger
        elseif pressure_delta >= warning_pressure then
            pressure_color = COLORS.warning
        end
    end

    -- Stress/overflow only applies to gas pipe networks.
    local is_gas_pipe = (atmos_mode and string.lower(atmos_mode) == "network")
        and (allowed_matter_state and string.lower(allowed_matter_state) == "gas")
    local stress_color = COLORS.text
    if is_gas_pipe then
        -- Vanilla thresholds: warn at 3/500 (0.006), danger at ~0.018.
        local warn_threshold = 3 / 500
        local danger_threshold = 0.018
        local ratio = liquid_ratio
        if ratio == nil and liquid_volume and volume and volume > 0 then
            ratio = liquid_volume / volume
        end
        if ratio then
            if ratio > danger_threshold then
                stress_color = COLORS.danger
            elseif ratio > warn_threshold then
                stress_color = COLORS.warning
            end
            stress_text = fmt_percent((ratio / 0.02) * 100)
        end
    end
    local liquid_color = is_gas_pipe and stress_color or COLORS.text
    local gas_volume_color = is_gas_pipe and stress_color or COLORS.text

    local info_y = 54
    local row_height = 18
    local row_gap = 6
    local row_step = row_height + row_gap

    local col1_x = 16
    local col1_label_w = 92
    local col1_value_x = col1_x + col1_label_w + 8
    local col1_value_w = 130

    local col2_x = 260
    local col2_label_w = 90
    local col2_value_x = col2_x + col2_label_w + 8
    local col2_value_w = 110

    local function render_row(id, label, value, x, y, label_w, value_x, value_w, value_color, value_size)
        local resolved_color = value_color or COLORS.text
        local resolved_size = value_size or 12
        ui:element({
            id = id .. "_label",
            type = "label",
            rect = { unit = "px", x = x, y = y, w = label_w, h = row_height },
            props = { text = label },
            style = { font_size = 11, color = COLORS.text_dim, align = "left" }
        })
        ui:element({
            id = id .. "_value",
            type = "label",
            rect = { unit = "px", x = value_x, y = y, w = value_w, h = row_height },
            props = { text = value },
            style = { font_size = resolved_size, color = resolved_color, align = "left" }
        })
    end

    render_row("pressure", "PRESSURE", pressure_text, col1_x, info_y, col1_label_w, col1_value_x, col1_value_w,
        pressure_color, 14)
    render_row("temperature", "TEMP", temp_text, col1_x, info_y + row_step, col1_label_w, col1_value_x, col1_value_w,
        COLORS.text, 14)
    render_row("capacity", "CAPACITY", capacity_text, col1_x, info_y + row_step * 2, col1_label_w, col1_value_x,
        col1_value_w)
    render_row("liquid", "LIQUID", liquid_text, col1_x, info_y + row_step * 3, col1_label_w, col1_value_x,
        col1_value_w, liquid_color)
    render_row("stress", "STRESS", stress_text, col1_x, info_y + row_step * 4, col1_label_w, col1_value_x,
        col1_value_w, stress_color)

    render_row("convected", "CONVECTED", convected_text, col2_x, info_y, col2_label_w, col2_value_x, col2_value_w)
    render_row("radiated", "RADIATED", radiated_text, col2_x, info_y + row_step, col2_label_w, col2_value_x, col2_value_w)
    render_row("latent", "LATENT", latent_text, col2_x, info_y + row_step * 2, col2_label_w, col2_value_x, col2_value_w)

    local gas_list_y = info_y + row_step * 5 + 10
    local gas_height = H - gas_list_y - 8
    if gas_height < 40 then
        gas_height = 40
    end

    local gas_scroll = ui:element({
        id = "gas_scroll",
        type = "scrollview",
        rect = { unit = "px", x = 0, y = gas_list_y, w = W, h = gas_height },
        style = { bg = "transparent" }
    })

    local col_icon = 16
    local col_name = 36
    local col_moles = 92
    local col_percent = 260
    local col_volume = 330

    gas_scroll:element({
        id = "gas_header_name",
        type = "label",
        rect = { unit = "px", x = col_name, y = 0, w = 50, h = 16 },
        props = { text = "GAS" },
        style = { font_size = 10, color = COLORS.text_dim, align = "left" }
    })
    gas_scroll:element({
        id = "gas_header_moles",
        type = "label",
        rect = { unit = "px", x = col_moles, y = 0, w = 70, h = 16 },
        props = { text = "MOLES" },
        style = { font_size = 10, color = COLORS.text_dim, align = "left" }
    })
    gas_scroll:element({
        id = "gas_header_percent",
        type = "label",
        rect = { unit = "px", x = col_percent, y = 0, w = 40, h = 16 },
        props = { text = "%" },
        style = { font_size = 10, color = COLORS.text_dim, align = "left" }
    })
    gas_scroll:element({
        id = "gas_header_volume",
        type = "label",
        rect = { unit = "px", x = col_volume, y = 0, w = 50, h = 16 },
        props = { text = "VOL" },
        style = { font_size = 10, color = COLORS.text_dim, align = "left" }
    })

    local gas_rows = build_gas_rows(atmos)
    if #gas_rows == 0 then
        gas_scroll:element({
            id = "gas_empty",
            type = "label",
            rect = { unit = "px", x = 16, y = 24, w = W - 32, h = 18 },
            props = { text = "NO GAS DATA" },
            style = { font_size = 11, color = COLORS.text_dim, align = "left" }
        })
        ui:commit()
        return
    end

    local gas_row_y = 20
    local gas_row_height = 18
    local gas_row_gap = 4

    for i, gas in ipairs(gas_rows) do
        local y = gas_row_y + (i - 1) * (gas_row_height + gas_row_gap)
        gas_scroll:element({
            id = "gas_" .. gas.key .. "_icon",
            type = "icon",
            rect = { unit = "px", x = col_icon, y = y + 2, w = 14, h = 14 },
            props = { name = ss.ui.icons.gas[gas.icon] or gas.icon, icon_type = "gas" },
            style = { tint = gas.color or COLORS.text }
        })
        gas_scroll:element({
            id = "gas_" .. gas.key .. "_name",
            type = "label",
            rect = { unit = "px", x = col_name, y = y, w = 60, h = gas_row_height },
            props = { text = gas.label },
            style = { font_size = 11, color = gas.color or COLORS.text, align = "left" }
        })

        gas_scroll:element({
            id = "gas_" .. gas.key .. "_moles",
            type = "label",
            rect = { unit = "px", x = col_moles, y = y, w = 150, h = gas_row_height },
            props = { text = fmt_prefix(gas.moles, "mol", 3) },
            style = { font_size = 11, color = COLORS.text, align = "left" }
        })

        gas_scroll:element({
            id = "gas_" .. gas.key .. "_pct",
            type = "label",
            rect = { unit = "px", x = col_percent, y = y, w = 50, h = gas_row_height },
            props = { text = fmt_percent(gas.percent) },
            style = { font_size = 11, color = COLORS.text, align = "left" }
        })

        gas_scroll:element({
            id = "gas_" .. gas.key .. "_vol",
            type = "label",
            rect = { unit = "px", x = col_volume, y = y, w = 120, h = gas_row_height },
            props = { text = gas.volume and fmt_sig(gas.volume, 3) .. " L" or "N/A" },
            style = { font_size = 11, color = gas_volume_color, align = "left" }
        })
    end

    ui:commit()
end

-- Target callback - called when the player looks at something
local function on_target(data)
    target = data
    render()
end

-- Initialize
local function init()
    -- Subscribe to target updates (0.1s interval) with room/world atmosphere fallback.
    ss.tablet.target(on_target, 0.1, true)

    -- Initial render
    render()
end

init()
