--[[
    EnergyNetworkTarget.lua

    Tablet cartridge example for inspecting cable power networks.
    Look at any device connected to power cables to see network load metrics.

    API demonstrated:
    - ss.tablet.target(callback, interval) - subscribe to target updates
    - Target snapshot: power_network fields
]]

local ui = ss.ui.surface("main")
ss.ui.activate("main")

local W, H = 480, 272
local size = ui:size()
if size then
    W, H = size.w, size.h
end

local COLORS = {
    bg = "#0B1220",
    header = "#0F172A",
    panel = "#111827",
    text = "#E2E8F0",
    text_dim = "#94A3B8",
    accent = "#38BDF8",
    warning = "#F59E0B",
    danger = "#EF4444",
    success = "#22C55E",
}

local target = nil

local function fmt(value, decimals)
    decimals = decimals or 1
    if value == nil then return "---" end
    if type(value) == "number" then
        if value == math.floor(value) then
            return tostring(math.floor(value))
        end
        return string.format("%." .. decimals .. "f", value)
    end
    return tostring(value)
end

local function fmt_watts(value)
    if value == nil then return "---" end
    return fmt(value, 1) .. " W"
end

local function fmt_percent(value)
    if value == nil then return "---" end
    return fmt(value * 100, 1) .. "%"
end

local function render_row(container, y, label, value, color)
    color = color or COLORS.text
    local id = "row_" .. label:gsub("%s", "_"):gsub("[^%w_]", "")

    container:element({
        id = id .. "_label",
        type = "label",
        rect = { unit = "px", x = 20, y = y, w = 160, h = 18 },
        props = { text = label },
        style = { font_size = 11, color = COLORS.text_dim, align = "left" }
    })

    container:element({
        id = id .. "_value",
        type = "label",
        rect = { unit = "px", x = 190, y = y, w = W - 210, h = 18 },
        props = { text = tostring(value) },
        style = { font_size = 11, color = color, align = "left" }
    })

    return y + 20
end

local function render()
    ui:clear()

    ui:element({
        id = "bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = H },
        style = { bg = COLORS.bg }
    })

    local header = ui:element({
        id = "header",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = 44 },
        style = { bg = COLORS.header }
    })

    header:element({
        id = "title",
        type = "label",
        rect = { unit = "px", x = 16, y = 10, w = W - 32, h = 24 },
        props = { text = "ENERGY NETWORK TARGET" },
        style = { font_size = 16, color = COLORS.text, align = "left" }
    })

    if not target or not target.has_target then
        ui:element({
            id = "no_target",
            type = "label",
            rect = { unit = "px", x = 0, y = H / 2 - 16, w = W, h = 32 },
            props = { text = "Look at a powered device" },
            style = { font_size = 16, color = COLORS.text_dim, align = "center" }
        })
        ui:commit()
        return
    end

    local content = ui:element({
        id = "content",
        type = "panel",
        rect = { unit = "px", x = 12, y = 54, w = W - 24, h = H - 66 },
        style = { bg = COLORS.panel }
    })

    local y = 10
    local name = target.display_name or target.prefab_name or "Unknown"
    y = render_row(content, y, "Target", name, COLORS.accent)
    y = render_row(content, y, "Distance", fmt(target.distance, 1) .. " m")

    local net = target.power_network
    if not net then
        y = render_row(content, y + 8, "Network", "No power network on target", COLORS.warning)
        ui:commit()
        return
    end

    y = render_row(content, y + 8, "Network", tostring(net.id or "---") .. " (" .. tostring(net.type or "?") .. ")")
    y = render_row(content, y, "Required", fmt_watts(net.required_load))
    y = render_row(content, y, "Potential", fmt_watts(net.potential_load))
    y = render_row(content, y, "Current", fmt_watts(net.current_load))
    y = render_row(content, y, "Shortfall", fmt_watts(net.shortfall_load))

    local ratio = 0
    if net.potential_load and net.potential_load > 0 then
        ratio = (net.required_load or 0) / net.potential_load
    end

    local ratio_color = COLORS.success
    if ratio > 1 then
        ratio_color = COLORS.danger
    elseif ratio > 0.85 then
        ratio_color = COLORS.warning
    end

    content:element({
        id = "load_ratio_bg",
        type = "panel",
        rect = { unit = "px", x = 20, y = y + 2, w = W - 64, h = 12 },
        style = { bg = COLORS.header }
    })
    content:element({
        id = "load_ratio_fill",
        type = "panel",
        rect = { unit = "px", x = 20, y = y + 2, w = math.floor((W - 64) * math.min(ratio, 1)), h = 12 },
        style = { bg = ratio_color }
    })
    content:element({
        id = "load_ratio_text",
        type = "label",
        rect = { unit = "px", x = 20, y = y, w = W - 64, h = 16 },
        props = { text = "Load: " .. fmt_percent(ratio) },
        style = { font_size = 10, color = COLORS.text, align = "center" }
    })
    y = y + 22

    y = render_row(content, y, "Devices", tostring(net.device_count or 0))
    y = render_row(content, y, "Power Devices", tostring(net.power_device_count or 0))
    y = render_row(content, y, "Data Devices", tostring(net.data_device_count or 0))
    y = render_row(content, y, "Batteries", tostring(net.battery_count or 0))

    if target.power then
        y = y + 8
        local charge = fmt(target.power.charge, 0) .. " / " .. fmt(target.power.max_charge, 0) .. " J"
        y = render_row(content, y, "Battery", charge)
        y = render_row(content, y, "Charge Ratio", fmt_percent(target.power.charge_ratio))
    end

    ui:commit()
end

local function on_target(data)
    target = data
    render()
end

ss.tablet.target(on_target, 0.1)
render()
