-- Rocket Monitor Display
-- ScriptedScreens command center display for rocket/shuttle status
-- Shows fuel levels, trajectory info, and launch status

local ui = ss.ui.surface("main")
ss.ui.activate("main")

local W, H = 480, 272

local size = ui:size()
if size then
    W = size.w or W
    H = size.h or H
end

-- Simulated rocket data (in real use, read from devices)
local rocketData = {
    name = "ROCKET ALPHA-7",
    status = "STANDBY",
    fuelH2 = 87.3,
    fuelO2 = 92.1,
    fuelN2O = 45.6,
    trajectory = "ORBIT-LEO",
    altitude = 0,
    velocity = 0,
    countdown = -1,
}

local function get_status_color(status)
    if status == "LAUNCH" then return "#00E676" end
    if status == "COUNTDOWN" then return "#FFEB3B" end
    if status == "STANDBY" then return "#29B6F6" end
    if status == "ABORT" then return "#FF5252" end
    return "#B0BEC5"
end

local function get_fuel_color(pct)
    if pct >= 80 then return "#00E676" end
    if pct >= 50 then return "#FFEB3B" end
    if pct >= 25 then return "#FF9800" end
    return "#FF5252"
end

local function fmt(v)
    if v == nil then return "--" end
    return string.format("%.1f", v)
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
                rect = { h = 48 },
                style = { bg = "#1E293B" },
                layout = "flex",
                direction = "row",
                gap = 0,
                padding = { left = 16, right = 16, top = 12 },
                children = {
                    {
                        id = "title",
                        type = "label",
                        flex = 1,
                        props = { text = "ROCKET MONITOR" },
                        style = { font_size = 18, color = "#E2E8F0", align = "left" }
                    },
                    {
                        id = "rocket_name",
                        type = "label",
                        rect = { w = 180 },
                        props = { text = rocketData.name },
                        style = { font_size = 14, color = "#94A3B8", align = "right" }
                    },
                }
            },

            -- ── Content: left (status/fuel) + right (trajectory/buttons) ─
            {
                layout = "flex",
                flex = 1,
                direction = "row",
                gap = 16,
                padding = { left = 16, right = 16, top = 12 },
                children = {
                    -- Left column: status + fuel bars
                    {
                        layout = "flex",
                        rect = { w = 220 },
                        direction = "column",
                        gap = 4,
                        children = {
                            {
                                id = "status_lbl",
                                type = "label",
                                rect = { h = 20 },
                                props = { text = "STATUS" },
                                style = { font_size = 11, color = "#64748B", align = "left" }
                            },
                            {
                                id = "status_val",
                                type = "label",
                                rect = { h = 24 },
                                props = { text = rocketData.status },
                                style = { font_size = 16, color = get_status_color(rocketData.status), align = "left" }
                            },
                            {
                                id = "fuel_title",
                                type = "label",
                                rect = { h = 18 },
                                props = { text = "FUEL LEVELS" },
                                style = { font_size = 12, color = "#94A3B8", align = "left" }
                            },
                            -- H2 fuel row
                            {
                                layout = "flex",
                                rect = { h = 20 },
                                direction = "row",
                                gap = 4,
                                children = {
                                    {
                                        id = "h2_lbl",
                                        type = "label",
                                        rect = { w = 36 },
                                        props = { text = "H2" },
                                        style = { font_size = 11, color = "#94A3B8", align = "left" }
                                    },
                                    {
                                        id = "h2_bar",
                                        type = "progress",
                                        flex = 1,
                                        props = { value = tostring(rocketData.fuelH2), max = "100" },
                                        style = { bg = "#1E293B", fill = get_fuel_color(rocketData.fuelH2) }
                                    },
                                    {
                                        id = "h2_pct",
                                        type = "label",
                                        rect = { w = 50 },
                                        props = { text = fmt(rocketData.fuelH2) .. "%" },
                                        style = { font_size = 11, color = get_fuel_color(rocketData.fuelH2), align = "left" }
                                    },
                                }
                            },
                            -- O2 fuel row
                            {
                                layout = "flex",
                                rect = { h = 20 },
                                direction = "row",
                                gap = 4,
                                children = {
                                    {
                                        id = "o2_lbl",
                                        type = "label",
                                        rect = { w = 36 },
                                        props = { text = "O2" },
                                        style = { font_size = 11, color = "#94A3B8", align = "left" }
                                    },
                                    {
                                        id = "o2_bar",
                                        type = "progress",
                                        flex = 1,
                                        props = { value = tostring(rocketData.fuelO2), max = "100" },
                                        style = { bg = "#1E293B", fill = get_fuel_color(rocketData.fuelO2) }
                                    },
                                    {
                                        id = "o2_pct",
                                        type = "label",
                                        rect = { w = 50 },
                                        props = { text = fmt(rocketData.fuelO2) .. "%" },
                                        style = { font_size = 11, color = get_fuel_color(rocketData.fuelO2), align = "left" }
                                    },
                                }
                            },
                            -- N2O fuel row
                            {
                                layout = "flex",
                                rect = { h = 20 },
                                direction = "row",
                                gap = 4,
                                children = {
                                    {
                                        id = "n2o_lbl",
                                        type = "label",
                                        rect = { w = 36 },
                                        props = { text = "N2O" },
                                        style = { font_size = 11, color = "#94A3B8", align = "left" }
                                    },
                                    {
                                        id = "n2o_bar",
                                        type = "progress",
                                        flex = 1,
                                        props = { value = tostring(rocketData.fuelN2O), max = "100" },
                                        style = { bg = "#1E293B", fill = get_fuel_color(rocketData.fuelN2O) }
                                    },
                                    {
                                        id = "n2o_pct",
                                        type = "label",
                                        rect = { w = 50 },
                                        props = { text = fmt(rocketData.fuelN2O) .. "%" },
                                        style = { font_size = 11, color = get_fuel_color(rocketData.fuelN2O), align = "left" }
                                    },
                                }
                            },
                        }
                    },

                    -- Right column: trajectory + buttons
                    {
                        layout = "flex",
                        flex = 1,
                        direction = "column",
                        gap = 2,
                        children = {
                            {
                                id = "traj_title",
                                type = "label",
                                rect = { h = 18 },
                                props = { text = "TRAJECTORY" },
                                style = { font_size = 11, color = "#64748B", align = "left" }
                            },
                            {
                                id = "traj_val",
                                type = "label",
                                rect = { h = 20 },
                                props = { text = rocketData.trajectory },
                                style = { font_size = 14, color = "#E2E8F0", align = "left" }
                            },
                            {
                                id = "alt_lbl",
                                type = "label",
                                rect = { h = 16 },
                                props = { text = "ALTITUDE" },
                                style = { font_size = 11, color = "#64748B", align = "left" }
                            },
                            {
                                id = "alt_val",
                                type = "label",
                                rect = { h = 20 },
                                props = { text = fmt(rocketData.altitude) .. " km" },
                                style = { font_size = 14, color = "#E2E8F0", align = "left" }
                            },
                            {
                                id = "vel_lbl",
                                type = "label",
                                rect = { h = 16 },
                                props = { text = "VELOCITY" },
                                style = { font_size = 11, color = "#64748B", align = "left" }
                            },
                            {
                                id = "vel_val",
                                type = "label",
                                rect = { h = 20 },
                                props = { text = fmt(rocketData.velocity) .. " m/s" },
                                style = { font_size = 14, color = "#E2E8F0", align = "left" }
                            },
                            {
                                id = "btn_abort",
                                type = "button",
                                rect = { h = 32 },
                                props = { text = "ABORT" },
                                style = { bg = "#991B1B", text = "#FFFFFF", font_size = 12 },
                                on_click = function(player)
                                    rocketData.status = "ABORT"
                                    rocketData.countdown = -1
                                    render()
                                end
                            },
                            {
                                id = "btn_launch",
                                type = "button",
                                rect = { h = 36 },
                                props = { text = "LAUNCH" },
                                style = { bg = "#166534", text = "#FFFFFF", font_size = 14 },
                                on_click = function(player)
                                    rocketData.status = "COUNTDOWN"
                                    rocketData.countdown = 10
                                    render()
                                end
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
                        props = { text = "LIVE TELEMETRY FEED" },
                        style = { font_size = 10, color = "#475569", align = "left" }
                    },
                }
            },
        }
    })

    ui:commit()
end

render()

-- Main loop - simulate telemetry updates
local tick = 0
while true do
    tick = tick + 1

    -- Countdown simulation
    if rocketData.countdown > 0 then
        rocketData.countdown = rocketData.countdown - 1
        if rocketData.countdown == 0 then
            rocketData.status = "LAUNCH"
            rocketData.velocity = 150
            rocketData.altitude = 0.5
        end
    elseif rocketData.status == "LAUNCH" then
        rocketData.velocity = rocketData.velocity + math.random(50, 150)
        rocketData.altitude = rocketData.altitude + rocketData.velocity * 0.001
        if rocketData.altitude > 100 then
            rocketData.status = "ORBIT"
        end
    end

    -- Slow fuel drain during launch
    if rocketData.status == "LAUNCH" or rocketData.status == "COUNTDOWN" then
        rocketData.fuelH2 = math.max(0, rocketData.fuelH2 - 0.3)
        rocketData.fuelO2 = math.max(0, rocketData.fuelO2 - 0.2)
        rocketData.fuelN2O = math.max(0, rocketData.fuelN2O - 0.1)
    end

    if tick % 5 == 0 then
        render()
    end

    ic.yield()
end
