--[[
    DeviceInspector.lua

    A tablet cartridge that displays detailed information about any device
    the player is looking at. Shows logic values, slot contents, power state,
    power-network load, data network, atmosphere data, and other device properties.

    Usage:
    1. Insert this cartridge into a tablet
    2. Hold the tablet and look at devices (machines, batteries, containers, etc.)
    3. The display shows all available information about the target

    API demonstrated:
    - ss.tablet.target(callback, interval, includeRoomAtmos) - subscribe to target updates
    - Target snapshot: logic values, slots, power, atmosphere, network, etc.
]]

-- Get UI surface and screen dimensions
local ui = ss.ui.surface("main")
ss.ui.activate("main")

local size = ui:size()
local W, H = 480, 272
if size then W, H = size.w or W, size.h or H end

-- Color palette
local COLORS = {
    bg = "#0A0E1A",
    header = "#1E293B",
    section_bg = "#111827",
    text = "#E2E8F0",
    text_dim = "#94A3B8",
    accent = "#3B82F6",
    success = "#22C55E",
    warning = "#FFEB3B",
    danger = "#EF4444",
    power_on = "#22C55E",
    power_off = "#64748B",
}

-- Current target data
local target = nil

-- Scroll position for content
local scrollY = 0
local contentHeight = 0

-- Formatting helpers
local function fmt(value, decimals)
    decimals = decimals or 1
    if value == nil then return "---" end
    if type(value) == "boolean" then
        return value and "Yes" or "No"
    end
    if type(value) == "number" then
        if value == math.floor(value) then
            return tostring(math.floor(value))
        end
        return string.format("%." .. decimals .. "f", value)
    end
    return tostring(value)
end

local function fmt_percent(value)
    if value == nil then return "---" end
    return fmt(value * 100, 1) .. "%"
end

local function fmt_pressure(pa)
    if pa == nil then return "---" end
    return fmt(pa / 1000, 2) .. " kPa"
end

local function fmt_temp(k)
    if k == nil then return "---" end
    local celsius = k - 273.15
    return fmt(k, 1) .. " K (" .. fmt(celsius, 1) .. " °C)"
end

local function fmt_energy(value)
    if value == nil then return "---" end
    return fmt(value, 0) .. " J"
end

local function fmt_watts(value)
    if value == nil then return "---" end
    return fmt(value, 1) .. " W"
end

-- Render a section header
local function render_section(ui, y, title)
    ui:element({
        id = "section_" .. title,
        type = "panel",
        rect = { unit = "px", x = 8, y = y, w = W - 16, h = 24 },
        style = { bg = COLORS.section_bg }
    })
    ui:element({
        id = "section_" .. title .. "_txt",
        type = "label",
        rect = { unit = "px", x = 16, y = y + 4, w = W - 32, h = 16 },
        props = { text = title },
        style = { font_size = 11, color = COLORS.accent, align = "left" }
    })
    return y + 28
end

-- Render a key-value row
local function render_row(ui, y, key, value, valueColor)
    valueColor = valueColor or COLORS.text
    local rowId = "row_" .. key:gsub("%s", "_"):gsub("[^%w_]", "")

    ui:element({
        id = rowId .. "_key",
        type = "label",
        rect = { unit = "px", x = 16, y = y, w = 140, h = 18 },
        props = { text = key },
        style = { font_size = 11, color = COLORS.text_dim, align = "left" }
    })
    ui:element({
        id = rowId .. "_val",
        type = "label",
        rect = { unit = "px", x = 160, y = y, w = W - 176, h = 18 },
        props = { text = tostring(value) },
        style = { font_size = 11, color = valueColor, align = "left" }
    })
    return y + 20
end

-- Render the UI
local function render()
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
        rect = { unit = "px", x = 16, y = 10, w = 200, h = 24 },
        props = { text = "DEVICE INSPECTOR" },
        style = { font_size = 18, color = COLORS.text, align = "left" }
    })

    -- Distance indicator
    if target and target.has_target then
        header:element({
            id = "distance",
            type = "label",
            rect = { unit = "px", x = W - 100, y = 14, w = 84, h = 16 },
            props = { text = fmt(target.distance, 1) .. " m" },
            style = { font_size = 12, color = COLORS.text_dim, align = "right" }
        })
    end

    -- No target state
    if not target or not target.has_target then
        ui:element({
            id = "no_target",
            type = "label",
            rect = { unit = "px", x = 0, y = H / 2 - 24, w = W, h = 40 },
            props = { text = "Point at a device to inspect" },
            style = { font_size = 16, color = COLORS.text_dim, align = "center" }
        })

        if target and target.atmosphere then
            local ambientMode = target.atmosphere_mode or "world"
            local ambientLabel = "AMBIENT ATMOSPHERE (" .. string.upper(ambientMode) .. ")"
            local y = H / 2 + 20
            y = render_section(ui, y, ambientLabel)
            y = render_row(ui, y, "Pressure", fmt_pressure(target.atmosphere.pressure))
            y = render_row(ui, y, "Temperature", fmt_temp(target.atmosphere.temperature))
            if target.room and target.room.name then
                y = render_row(ui, y, "Room", target.room.name)
            end
        end

        ui:commit()
        return
    end

    -- Content area with scrollview
    local contentY = 50
    local scroll = ui:element({
        id = "content_scroll",
        type = "scrollview",
        rect = { unit = "px", x = 0, y = contentY, w = W, h = H - contentY },
        style = { bg = "transparent" }
    })

    local y = 8

    -- === BASIC INFO ===
    y = render_section(scroll, y, "DEVICE INFO")

    -- Name
    local displayName = target.display_name or target.prefab_name or "Unknown"
    y = render_row(scroll, y, "Name", displayName, COLORS.text)

    -- Custom name if different
    if target.custom_name and target.custom_name ~= "" and target.custom_name ~= displayName then
        y = render_row(scroll, y, "Custom Name", target.custom_name, COLORS.accent)
    end

    -- Prefab
    y = render_row(scroll, y, "Prefab", target.prefab_name or "---", COLORS.text_dim)

    -- Target kind
    if target.target_kind then
        y = render_row(scroll, y, "Target Kind", target.target_kind, COLORS.text_dim)
    end

    -- Reference ID
    y = render_row(scroll, y, "Reference ID", target.reference_id or "---", COLORS.text_dim)

    -- Room info for structure targets
    if target.room and target.room.name then
        y = render_row(scroll, y, "Room", target.room.name, COLORS.text_dim)
    end

    -- Health (if available)
    if target.health and target.max_health then
        local healthRatio = target.health / target.max_health
        local healthColor = COLORS.success
        if healthRatio < 0.25 then
            healthColor = COLORS.danger
        elseif healthRatio < 0.5 then
            healthColor = COLORS.warning
        end
        y = render_row(scroll, y, "Health", fmt(target.health, 0) .. " / " .. fmt(target.max_health, 0), healthColor)
    end

    y = y + 8

    -- === POWER STATE ===
    if target.power then
        y = render_section(scroll, y, "POWER")

        local power = target.power
        local onColor = power.on and COLORS.power_on or COLORS.power_off
        y = render_row(scroll, y, "Power On", power.on and "ON" or "OFF", onColor)

        local poweredColor = power.powered and COLORS.success or COLORS.danger
        y = render_row(scroll, y, "Powered", power.powered and "Yes" or "No", poweredColor)

        if power.charge and power.max_charge then
            y = render_row(scroll, y, "Charge", fmt(power.charge, 0) .. " / " .. fmt(power.max_charge, 0) .. " J")

            -- Charge bar
            scroll:element({
                id = "charge_bar_bg",
                type = "panel",
                rect = { unit = "px", x = 160, y = y, w = W - 176, h = 12 },
                style = { bg = COLORS.section_bg }
            })
            local chargeRatio = power.charge_ratio or 0
            local chargeColor = COLORS.success
            if chargeRatio < 0.25 then
                chargeColor = COLORS.danger
            elseif chargeRatio < 0.5 then
                chargeColor = COLORS.warning
            end

            scroll:element({
                id = "charge_bar",
                type = "panel",
                rect = { unit = "px", x = 160, y = y, w = math.floor((W - 176) * chargeRatio), h = 12 },
                style = { bg = chargeColor }
            })
            scroll:element({
                id = "charge_pct",
                type = "label",
                rect = { unit = "px", x = 160, y = y - 1, w = W - 176, h = 14 },
                props = { text = fmt_percent(chargeRatio) },
                style = { font_size = 10, color = "#FFFFFF", align = "center" }
            })
            y = y + 18
        end

        y = y + 8
    end

    -- === POWER USAGE ===
    if target.power_usage then
        y = render_section(scroll, y, "POWER USAGE")

        local usage = target.power_usage
        if usage.used_power then
            y = render_row(scroll, y, "Used", fmt_watts(usage.used_power))
        end
        if usage.generated_power then
            y = render_row(scroll, y, "Generated", fmt_watts(usage.generated_power))
        end
        if usage.net_power then
            local netColor = COLORS.text
            if usage.net_power > 0 then
                netColor = COLORS.success
            elseif usage.net_power < 0 then
                netColor = COLORS.warning
            end
            y = render_row(scroll, y, "Net", fmt_watts(usage.net_power), netColor)
        end

        y = y + 8
    end

    -- === POWER NETWORK ===
    if target.power_network then
        y = render_section(scroll, y, "POWER NETWORK")

        local net = target.power_network
        y = render_row(scroll, y, "Network", tostring(net.id or "---") .. " (" .. tostring(net.type or "?") .. ")")
        y = render_row(scroll, y, "Required", fmt_watts(net.required_load))
        y = render_row(scroll, y, "Potential", fmt_watts(net.potential_load))
        y = render_row(scroll, y, "Current", fmt_watts(net.current_load))
        y = render_row(scroll, y, "Shortfall", fmt_watts(net.shortfall_load))

        local ratio = 0
        if net.potential_load and net.potential_load > 0 then
            ratio = (net.required_load or 0) / net.potential_load
        end
        local ratioColor = COLORS.success
        if ratio > 1 then
            ratioColor = COLORS.danger
        elseif ratio > 0.85 then
            ratioColor = COLORS.warning
        end

        scroll:element({
            id = "power_net_bar_bg",
            type = "panel",
            rect = { unit = "px", x = 160, y = y, w = W - 176, h = 12 },
            style = { bg = COLORS.section_bg }
        })
        scroll:element({
            id = "power_net_bar",
            type = "panel",
            rect = { unit = "px", x = 160, y = y, w = math.floor((W - 176) * math.min(ratio, 1)), h = 12 },
            style = { bg = ratioColor }
        })
        scroll:element({
            id = "power_net_ratio",
            type = "label",
            rect = { unit = "px", x = 160, y = y - 1, w = W - 176, h = 14 },
            props = { text = fmt_percent(ratio) },
            style = { font_size = 10, color = "#FFFFFF", align = "center" }
        })
        y = y + 18

        y = render_row(scroll, y, "Devices", tostring(net.device_count or 0))
        y = render_row(scroll, y, "Power Devices", tostring(net.power_device_count or 0))
        y = render_row(scroll, y, "Data Devices", tostring(net.data_device_count or 0))
        y = render_row(scroll, y, "Batteries", tostring(net.battery_count or 0))

        if net.total_charge and net.max_charge then
            y = render_row(scroll, y, "Network Charge",
                fmt(net.total_charge, 0) .. " / " .. fmt(net.max_charge, 0) .. " J")
            y = render_row(scroll, y, "Network Ratio", fmt_percent(net.charge_ratio))
        end

        y = y + 8
    end

    -- === DATA NETWORK ===
    if target.data_network then
        y = render_section(scroll, y, "DATA NETWORK")

        local dataNet = target.data_network
        y = render_row(scroll, y, "Network",
            tostring(dataNet.id or "---") .. " (" .. tostring(dataNet.type or "?") .. ")")
        y = render_row(scroll, y, "Devices", tostring(dataNet.device_count or 0))
        y = render_row(scroll, y, "Data Devices", tostring(dataNet.data_device_count or 0))
        y = render_row(scroll, y, "Power Devices", tostring(dataNet.power_device_count or 0))

        y = y + 8
    end

    -- === LOGIC VALUES ===
    if target.logic then
        y = render_section(scroll, y, "LOGIC VALUES")

        -- Sort logic keys for consistent display
        local logicKeys = {}
        for k, _ in pairs(target.logic) do
            table.insert(logicKeys, k)
        end
        table.sort(logicKeys)

        for _, key in ipairs(logicKeys) do
            local value = target.logic[key]
            local displayValue = fmt(value, 2)

            -- Special formatting for known logic types
            if key == "On" or key == "Open" or key == "Power" then
                if value == 1 then
                    displayValue = "ON"
                    y = render_row(scroll, y, key, displayValue, COLORS.success)
                else
                    displayValue = "OFF"
                    y = render_row(scroll, y, key, displayValue, COLORS.power_off)
                end
            elseif key == "Ratio" or key == "Charge" then
                y = render_row(scroll, y, key, fmt_percent(value))
            elseif key == "Pressure" then
                y = render_row(scroll, y, key, fmt(value / 1000, 2) .. " kPa")
            elseif key == "Temperature" then
                local celsius = value - 273.15
                y = render_row(scroll, y, key, fmt(value, 1) .. " K (" .. fmt(celsius, 1) .. " °C)")
            else
                y = render_row(scroll, y, key, displayValue)
            end
        end

        y = y + 8
    end

    -- === ATMOSPHERE ===
    if target.atmosphere then
        y = render_section(scroll, y, "INTERNAL ATMOSPHERE")

        local atmos = target.atmosphere
        y = render_row(scroll, y, "Pressure", fmt_pressure(atmos.pressure))
        y = render_row(scroll, y, "Temperature", fmt_temp(atmos.temperature))
        if atmos.pressure_delta and atmos.max_pressure then
            y = render_row(scroll, y, "Delta P", fmt_pressure(atmos.pressure_delta))
            y = render_row(scroll, y, "Delta P Ratio", fmt_percent(atmos.pressure_ratio))
        end

        y = render_row(scroll, y, "Total Moles", fmt(atmos.total_moles, 2) .. " mol")
        y = render_row(scroll, y, "Volume", fmt(atmos.volume, 1) .. " L")
        if atmos.total_volume_liquids then
            y = render_row(scroll, y, "Liquid Volume", fmt(atmos.total_volume_liquids, 2) .. " L")
        end
        if target.atmosphere_mode then
            y = render_row(scroll, y, "Mode", target.atmosphere_mode)
        end
        if atmos.allowed_matter_state then
            y = render_row(scroll, y, "Matter State", atmos.allowed_matter_state)
        end

        y = y + 8
    end

    -- === ATMOS NETWORK ===
    if target.network then
        y = render_section(scroll, y, "ATMOS NETWORK")
        y = render_row(scroll, y, "Network",
            tostring(target.network.id or "---") .. " (" .. tostring(target.network.type or "?") .. ")")
        if target.network.content_type then
            y = render_row(scroll, y, "Content", target.network.content_type)
        end
        if target.network.pressure then
            y = render_row(scroll, y, "Pressure", fmt_pressure(target.network.pressure))
        end
        if target.network.temperature then
            y = render_row(scroll, y, "Temperature", fmt_temp(target.network.temperature))
        end
        if target.network.total_moles then
            y = render_row(scroll, y, "Total Moles", fmt(target.network.total_moles, 2) .. " mol")
        end
        if target.network.volume then
            y = render_row(scroll, y, "Volume", fmt(target.network.volume, 1) .. " L")
        end
        if target.network.total_moles_gases then
            y = render_row(scroll, y, "Gas Moles", fmt(target.network.total_moles_gases, 2) .. " mol")
        end
        if target.network.total_moles_liquids then
            y = render_row(scroll, y, "Liquid Moles", fmt(target.network.total_moles_liquids, 2) .. " mol")
        end
        y = y + 8
    end

    -- === THERMAL ===
    if target.thermal then
        y = render_section(scroll, y, "THERMAL")
        y = render_row(scroll, y, "Convected", fmt_energy(target.thermal.energy_convected))
        y = render_row(scroll, y, "Radiated", fmt_energy(target.thermal.energy_radiated))
        y = y + 8
    end

    -- === POSITION ===
    if target.position then
        y = render_section(scroll, y, "POSITION")
        local pos = target.position
        y = render_row(scroll, y, "X", fmt(pos.x, 2))
        y = render_row(scroll, y, "Y", fmt(pos.y, 2))
        y = render_row(scroll, y, "Z", fmt(pos.z, 2))
        y = y + 8
    end

    -- Update content height for scrollview
    contentHeight = y + 16
    scroll:set_props({ content_height = tostring(contentHeight) })

    ui:commit()
end

-- Target callback - called when the player looks at something
local function on_target(data)
    target = data
    render()
end

-- Initialize
local function init()
    -- Subscribe to target updates (0.15s interval - slightly slower for detailed inspection)
    ss.tablet.target(on_target, 0.15, true)

    -- Initial render
    render()
end

init()
