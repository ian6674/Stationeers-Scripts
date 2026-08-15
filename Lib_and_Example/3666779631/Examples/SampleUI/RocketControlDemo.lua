-- Rocket Control System Demo
-- Demonstrates all UI elements with view transitions
-- Including new controls: slider, toggle, select, textinput
-- print() output appears in the Lua Debugger Logs tab.
local surfaces = {
    main = ss.ui.surface("main"),
    engine = ss.ui.surface("engine"),
    navigation = ss.ui.surface("navigation"),
    settings = ss.ui.surface("settings"),
}

local s = surfaces.main
local view = "main"
-- Get actual screen size from the console
local screen = s:size()
local W = screen.w
local H = screen.h

-- State
local fuel_level = 75
local oxygen_level = 92
local engine_temp = 340
local throttle = 0
local autopilot = false
local launch_armed = false
local nav_mode = 1               -- 1=orbit, 2=dock, 3=land
local mission_name = ""
local comm_channel = 0           -- 0=Alpha, 1=Beta, 2=Gamma, 3=Delta

local function log_action(message)
    print("[RocketControl] " .. tostring(message))
end

local PERSIST_KEY = "rocket"

local function persist_save_state()
    local ok, json = pcall(util.json.encode, {
        view = view,
        fuel_level = fuel_level,
        oxygen_level = oxygen_level,
        engine_temp = engine_temp,
        throttle = throttle,
        autopilot = autopilot,
        launch_armed = launch_armed,
        nav_mode = nav_mode,
        mission_name = mission_name,
        comm_channel = comm_channel,
    })
    if ok and json then ic.persist.set(PERSIST_KEY, json) end
end

local function persist_restore_state()
    if not ic.persist.has(PERSIST_KEY) then return end
    local blob = ic.persist.get(PERSIST_KEY)
    if type(blob) ~= "string" or blob == "" then return end
    local ok, decoded = pcall(util.json.decode, blob)
    if not ok or type(decoded) ~= "table" then return end

    if type(decoded.view) == "string" then view = decoded.view end
    if type(decoded.fuel_level) == "number" then fuel_level = decoded.fuel_level end
    if type(decoded.oxygen_level) == "number" then oxygen_level = decoded.oxygen_level end
    if type(decoded.engine_temp) == "number" then engine_temp = decoded.engine_temp end
    if type(decoded.throttle) == "number" then throttle = decoded.throttle end
    if type(decoded.autopilot) == "boolean" then autopilot = decoded.autopilot end
    if type(decoded.launch_armed) == "boolean" then launch_armed = decoded.launch_armed end
    if type(decoded.nav_mode) == "number" then nav_mode = decoded.nav_mode end
    if type(decoded.mission_name) == "string" then mission_name = decoded.mission_name end
    if type(decoded.comm_channel) == "number" then comm_channel = decoded.comm_channel end
end

persist_restore_state()

local function render_header()
    local header = s:element({
        id = "header_bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = 60 },
        style = { bg = "#1A1A2E" }
    })

    header:element({
        id = "title",
        type = "label",
        rect = { unit = "px", x = 20, y = 10, w = 350, h = 40 },
        props = { text = "ARTEMIS-7 CONTROL" },
        style = { font_size = 28, color = "#00FFAA", align = "left" }
    })

    header:element({
        id = "status_light",
        type = "label",
        rect = { unit = "px", x = W - 120, y = 15, w = 100, h = 30 },
        props = { text = launch_armed and "ARMED" or "SAFE" },
        style = { font_size = 18, color = launch_armed and "#FF3333" or "#33FF33", align = "right" }
    })

    -- Interface Mode button - click to toggle direct UI interaction
    -- Press ALT to exit interface mode
    header:element({
        id = "interface_btn",
        type = "interface_button",
        rect = { unit = "px", x = W - 90, y = 2, w = 70, h = 18 },
        props = { text = "INTERFACE" },
        style = { bg = "#664400", text = "#FFCC00", font_size = 8 }
    })
end

local function render_nav_tabs()
    local tabs = { { id = "nav_main", text = "STATUS", view = "main" },
        { id = "nav_engine",   text = "ENGINE",   view = "engine" },
        { id = "nav_nav",      text = "NAV",      view = "navigation" },
        { id = "nav_settings", text = "SETTINGS", view = "settings" } }
    local tab_w = math.floor((W - 20) / 4)
    local tab_y = 60
    for i, tab in ipairs(tabs) do
        local is_active = (view == tab.view)
        s:element({
            id = tab.id,
            type = "button",
            rect = { unit = "px", x = (i - 1) * tab_w + 10, y = tab_y, w = tab_w - 5, h = 40 },
            props = { text = tab.text },
            style = { bg = is_active and "#0066AA" or "#333344", text = "#FFFFFF", font_size = 14 },
            on_click = function(playerName)
                set_view(tab.view)
            end
        })
    end
end

local function render_main_view()
    local content_y = 110 -- Below header + tabs
    -- Left column - Fuel & O2
    -- Using ss.ui.icons.gas convenience enum for icon names
    s:element({
        id = "fuel_icon",
        type = "icon",
        rect = { unit = "px", x = 20, y = content_y + 25, w = 20, h = 20 },
        props = { name = ss.ui.icons.gas.Methane, icon_type = "gas" },
        style = { tint = "#FF9900" }
    })
    s:element({
        id = "fuel_label",
        type = "label",
        rect = { unit = "px", x = 45, y = content_y, w = 100, h = 25 },
        props = { text = "FUEL" },
        style = { font_size = 14, color = "#888888", align = "left" }
    })
    s:element({
        id = "fuel_bar",
        type = "progress",
        rect = { unit = "px", x = 45, y = content_y + 35, w = 195, h = 25 },
        props = { value = tostring(fuel_level), max = "100" },
        style = { bg = "#222222", fill = fuel_level > 20 and "#00CC66" or "#FF3333" }
    })
    s:element({
        id = "fuel_pct",
        type = "label",
        rect = { unit = "px", x = 250, y = content_y + 35, w = 60, h = 25 },
        props = { text = string.format("%.1f%%", fuel_level) },
        style = { font_size = 14, color = "#FFFFFF", align = "left" }
    })
    s:element({
        id = "o2_icon",
        type = "icon",
        rect = { unit = "px", x = 20, y = content_y + 105, w = 20, h = 20 },
        props = { name = ss.ui.icons.gas.Oxygen, icon_type = "gas" },
        style = { tint = "#3399FF" }
    })
    s:element({
        id = "o2_label",
        type = "label",
        rect = { unit = "px", x = 45, y = content_y + 80, w = 100, h = 25 },
        props = { text = "O2 SUPPLY" },
        style = { font_size = 14, color = "#888888", align = "left" }
    })
    s:element({
        id = "o2_bar",
        type = "progress",
        rect = { unit = "px", x = 45, y = content_y + 115, w = 195, h = 25 },
        props = { value = tostring(oxygen_level), max = "100" },
        style = { bg = "#222222", fill = "#3399FF" }
    })
    s:element({
        id = "o2_pct",
        type = "label",
        rect = { unit = "px", x = 250, y = content_y + 115, w = 60, h = 25 },
        props = { text = oxygen_level .. "%" },
        style = { font_size = 14, color = "#FFFFFF", align = "left" }
    })
    -- Right column - Engine temp & Arm
    local right_x = W - 160
    s:element({
        id = "temp_panel",
        type = "panel",
        rect = { unit = "px", x = right_x, y = content_y + 20, w = 140, h = 110 },
        style = { bg = "#1A1A2E" }
    })
    -- Border around temp panel
    s:element({
        id = "temp_border",
        type = "border",
        rect = { unit = "px", x = right_x, y = content_y + 20, w = 140, h = 110 },
        style = { color = engine_temp > 500 and "#FF6633" or "#0066AA", thickness = 1 }
    })
    s:element({
        id = "temp_label",
        type = "label",
        rect = { unit = "px", x = right_x + 5, y = content_y + 25, w = 130, h = 20 },
        props = { text = "ENG TEMP" },
        style = { font_size = 11, color = "#666666", align = "center" }
    })
    s:element({
        id = "temp_value",
        type = "label",
        rect = { unit = "px", x = right_x + 5, y = content_y + 55, w = 130, h = 50 },
        props = { text = math.floor(engine_temp) .. " K" },
        style = { font_size = 28, color = engine_temp > 500 and "#FF6633" or "#33FFCC", align = "center" }
    })
    s:element({
        id = "arm_check",
        type = "checkbox",
        rect = { unit = "px", x = right_x, y = content_y + 150, w = 140, h = 35 },
        props = { text = "ARM", checked = launch_armed and "true" or "false" },
        style = { bg = "#2A2A3E", text = "#FFFFFF", check_color = "#FF3333", font_size = 14 },
        on_click = function(playerName)
            launch_armed = not launch_armed
            log_action("Launch armed: " .. (launch_armed and "ON" or "OFF"))
            render()
        end
    })
    -- Bottom buttons
    local bottom_y = H - 20 - 60
    s:element({
        id = "launch_btn",
        type = "button",
        rect = { unit = "px", x = 20, y = bottom_y, w = W / 2 - 30, h = 60 },
        props = { text = "LAUNCH" },
        style = { bg = launch_armed and "#CC0000" or "#444444", text = "#FFFFFF", font_size = 24 },
        on_click = function(playerName)
            if launch_armed then
                throttle = 100
                log_action("Launch initiated")
                set_view("engine")
            end
            render()
        end
    })
    s:element({
        id = "abort_btn",
        type = "button",
        rect = { unit = "px", x = W / 2 + 10, y = bottom_y, w = W / 2 - 30, h = 60 },
        props = { text = "ABORT" },
        style = { bg = "#663300", text = "#FFCC00", font_size = 18 },
        on_click = function(playerName)
            throttle = 0
            launch_armed = false
            log_action("Abort pressed")
            render()
        end
    })
end

local function render_engine_view()
    local content_y = 110
    -- Throttle display
    s:element({
        id = "throttle_label",
        type = "label",
        rect = { unit = "px", x = 20, y = content_y, w = 150, h = 25 },
        props = { text = "THROTTLE" },
        style = { font_size = 16, color = "#888888", align = "left" }
    })
    s:element({
        id = "throttle_bar",
        type = "progress",
        rect = { unit = "px", x = 20, y = content_y + 45, w = W - 100, h = 35 },
        props = { value = tostring(throttle), max = "100" },
        style = { bg = "#222222", fill = "#FF6600" }
    })
    s:element({
        id = "throttle_pct",
        type = "label",
        rect = { unit = "px", x = W - 70, y = content_y + 45, w = 60, h = 35 },
        props = { text = throttle .. "%" },
        style = { font_size = 24, color = "#FFFFFF", align = "left" }
    })
    -- Throttle controls
    local throttle_vals = { 0, 25, 50, 75, 100 }
    local btn_w = math.floor((W - 40) / 5)
    for i, val in ipairs(throttle_vals) do
        s:element({
            id = "thr_" .. val,
            type = "button",
            rect = { unit = "px", x = (i - 1) * btn_w + 20, y = content_y + 100, w = btn_w - 10, h = 40 },
            props = { text = val .. "%" },
            style = { bg = throttle == val and "#FF6600" or "#333344", text = "#FFFFFF", font_size = 16 },
            on_click = function(playerName)
                throttle = val
                log_action("Throttle: " .. tostring(val) .. "%")
                render()
            end
        })
    end
    -- Autopilot toggle
    s:element({
        id = "autopilot_chk",
        type = "checkbox",
        rect = { unit = "px", x = 20, y = content_y + 155, w = 200, h = 40 },
        props = { text = "AUTOPILOT", checked = autopilot and "true" or "false" },
        style = { bg = "#2A2A3E", text = "#FFFFFF", check_color = "#00FFAA", font_size = 16 },
        on_click = function(playerName)
            autopilot = not autopilot
            log_action("Autopilot: " .. (autopilot and "ON" or "OFF"))
            render()
        end
    })
    -- Status panel
    s:element({
        id = "ap_panel",
        type = "panel",
        rect = { unit = "px", x = 230, y = content_y + 150, w = W - 250, h = 60 },
        style = { bg = "#1A1A2E" }
    })
    s:element({
        id = "ap_status",
        type = "label",
        rect = { unit = "px", x = 235, y = content_y + 160, w = W - 260, h = 40 },
        props = { text = autopilot and "AP: ENGAGED" or "AP: MANUAL" },
        style = { font_size = 18, color = autopilot and "#00FFAA" or "#FFAA00", align = "center" }
    })
end

local function render_navigation_view()
    local content_y = 110
    s:element({
        id = "nav_title",
        type = "label",
        rect = { unit = "px", x = 20, y = content_y, w = 250, h = 30 },
        props = { text = "NAVIGATION MODE" },
        style = { font_size = 18, color = "#888888", align = "left" }
    })
    -- Radio options
    local modes = { { id = 1, text = "ORBITAL INSERTION" },
        { id = 2, text = "DOCKING APPROACH" },
        { id = 3, text = "LANDING SEQUENCE" } }
    for i, mode in ipairs(modes) do
        s:element({
            id = "nav_mode_" .. mode.id,
            type = "radio",
            rect = { unit = "px", x = 20, y = content_y + 40 + (i - 1) * 45, w = W - 40, h = 38 },
            props = { text = mode.text, selected = nav_mode == mode.id and "true" or "false" },
            style = { bg = "#2A2A3E", text = "#FFFFFF", radio_color = "#00AAFF", font_size = 16 },
            on_click = function(playerName)
                nav_mode = mode.id
                log_action("Nav mode: " .. mode.text)
                render()
            end
        })
    end
    -- Current target panel (bottom right)
    local target_panel_h = 70
    local nav_confirm_h = 50
    local bottom_margin = 20
    local target_panel_y = H - bottom_margin - target_panel_h
    local nav_confirm_y = H - bottom_margin - nav_confirm_h
    local targets = { "ORBIT: 250km", "STATION ALPHA", "LANDING PAD 3" }
    s:element({
        id = "target_info",
        type = "panel",
        rect = { unit = "px", x = 230, y = target_panel_y, w = W - 250, h = target_panel_h },
        style = { bg = "#1A1A2E" }
    })
    s:element({
        id = "target_label",
        type = "label",
        rect = { unit = "px", x = 235, y = target_panel_y + 5, w = W - 260, h = 20 },
        props = { text = "TARGET" },
        style = { font_size = 10, color = "#666666", align = "center" }
    })
    s:element({
        id = "target_value",
        type = "label",
        rect = { unit = "px", x = 235, y = target_panel_y + 30, w = W - 260, h = 35 },
        props = { text = targets[nav_mode] },
        style = { font_size = 14, color = "#00FFAA", align = "center" }
    })
    -- Confirm button at bottom
    s:element({
        id = "nav_confirm",
        type = "button",
        rect = { unit = "px", x = 20, y = nav_confirm_y, w = 200, h = nav_confirm_h },
        props = { text = "ENGAGE NAV" },
        style = { bg = "#0066AA", text = "#FFFFFF", font_size = 18 },
        on_click = function(playerName)
            autopilot = true
            log_action("Nav confirm: autopilot ON")
            set_view("engine")
            render()
        end
    })
end

-- NEW: Settings view demonstrating scrollview - entire content is scrollable
local function render_settings_view()
    local status_h = 20
    local scroll_h = H - 120 - status_h - 10 -- Height of scrollable area (below header/tabs)
    local content_h = 520                    -- Total content height (taller than view = scrollable)
    -- Scrollable settings container
    local scroll = s:element({
        id = "settings_scroll",
        type = "scrollview",
        rect = { unit = "px", x = 10, y = 110, w = W - 20, h = scroll_h },
        props = { content_height = tostring(content_h) },
        style = { bg = "#0A0A15", scrollbar_bg = "#1A1A2E", scrollbar_handle = "#4488AA" }
    })
    -- All settings inside scrollview using child elements (no parent_id)
    local y = 10
    -- Mission Name (textinput)
    scroll:element({
        id = "mission_label",
        type = "label",
        rect = { unit = "px", x = 10, y = y, w = 150, h = 25 },
        props = { text = "MISSION NAME" },
        style = { font_size = 12, color = "#888888", align = "left" }
    })
    y = y + 35
    scroll:element({
        id = "mission_input",
        type = "textinput",
        rect = { unit = "px", x = 10, y = y, w = W - 60, h = 30 },
        props = { value = mission_name, placeholder = "Enter mission name…", title = "Mission Name" },
        style = { bg = "#1A1A2E", text = "#FFFFFF", placeholder_color = "#555555", font_size = 14 },
        on_change = function(new_value, playerName)
            mission_name = new_value or ""
            render()
        end
    })
    -- Comm Channel (select/dropdown)
    y = y + 45
    scroll:element({
        id = "comm_label",
        type = "label",
        rect = { unit = "px", x = 10, y = y, w = 150, h = 25 },
        props = { text = "COMM CHANNEL" },
        style = { font_size = 12, color = "#888888", align = "left" }
    })
    y = y + 35
    scroll:element({
        id = "comm_select",
        type = "select",
        rect = { unit = "px", x = 10, y = y, w = 180, h = 30 },
        props = { options = {"Alpha", "Beta", "Gamma", "Delta"}, selected = tostring(comm_channel) },
        style = { bg = "#1A1A2E", text = "#FFFFFF", font_size = 14 },
        on_change = function(new_value, playerName)
            comm_channel = tonumber(new_value) or 0
            log_action("Comm channel: " .. tostring(comm_channel))
            render()
        end
    })
    -- Throttle Slider
    y = y + 45
    scroll:element({
        id = "throttle_slider_label",
        type = "label",
        rect = { unit = "px", x = 10, y = y, w = 200, h = 25 },
        props = { text = "THROTTLE: " .. math.floor(throttle) .. "%" },
        style = { font_size = 12, color = "#888888", align = "left" }
    })
    y = y + 30
    scroll:element({
        id = "throttle_slider",
        type = "slider",
        rect = { unit = "px", x = 10, y = y, w = W - 60, h = 25 },
        props = { value = tostring(throttle), min = "0", max = "100" },
        style = { bg = "#1A1A2E", fill = "#FF6600", handle = "#FFFFFF" },
        on_change = function(new_value, playerName)
            throttle = math.floor(tonumber(new_value) or 0)
            render()
        end
    })
    -- Autopilot Toggle
    y = y + 45
    scroll:element({
        id = "autopilot_label",
        type = "label",
        rect = { unit = "px", x = 10, y = y, w = 150, h = 25 },
        props = { text = "AUTOPILOT" },
        style = { font_size = 12, color = "#888888", align = "left" }
    })
    scroll:element({
        id = "autopilot_toggle",
        type = "toggle",
        rect = { unit = "px", x = 160, y = y, w = 60, h = 25 },
        props = { value = autopilot and "true" or "false" },
        style = { on_color = "#00AA66", off_color = "#333344", knob = "#FFFFFF" },
        on_click = function(playerName)
            autopilot = not autopilot
            log_action("Autopilot: " .. (autopilot and "ON" or "OFF"))
            render()
        end
    })
    -- Launch Armed Toggle
    y = y + 40
    scroll:element({
        id = "armed_label",
        type = "label",
        rect = { unit = "px", x = 10, y = y, w = 150, h = 25 },
        props = { text = "LAUNCH ARMED" },
        style = { font_size = 12, color = "#888888", align = "left" }
    })
    scroll:element({
        id = "armed_toggle",
        type = "toggle",
        rect = { unit = "px", x = 160, y = y, w = 60, h = 25 },
        props = { value = launch_armed and "true" or "false" },
        style = { on_color = "#CC3333", off_color = "#333344", knob = "#FFFFFF" },
        on_click = function(playerName)
            launch_armed = not launch_armed
            log_action("Launch armed: " .. (launch_armed and "ON" or "OFF"))
            render()
        end
    })
    -- Extra settings to make scrolling obvious
    y = y + 50
    scroll:element({
        id = "extra_divider",
        type = "label",
        rect = { unit = "px", x = 10, y = y, w = W - 60, h = 25 },
        props = { text = "--- ADVANCED ---" },
        style = { font_size = 10, color = "#555555", align = "center" }
    })
    y = y + 35
    scroll:element({
        id = "fuel_reserve_label",
        type = "label",
        rect = { unit = "px", x = 10, y = y, w = 200, h = 25 },
        props = { text = "FUEL RESERVE: 15%" },
        style = { font_size = 12, color = "#888888", align = "left" }
    })
    y = y + 35
    scroll:element({
        id = "beacon_label",
        type = "label",
        rect = { unit = "px", x = 10, y = y, w = 200, h = 25 },
        props = { text = "BEACON: ENABLED" },
        style = { font_size = 12, color = "#888888", align = "left" }
    })
    y = y + 35
    scroll:element({
        id = "telemetry_label",
        type = "label",
        rect = { unit = "px", x = 10, y = y, w = 200, h = 25 },
        props = { text = "TELEMETRY: ACTIVE" },
        style = { font_size = 12, color = "#888888", align = "left" }
    })
    -- Status summary at bottom (outside scroll)
    local status_text = string.format(
        "Mission: %s | Ch: %s | Thr: %d%% | AP: %s",
        mission_name ~= "" and mission_name or "N/A",
        ({ "A", "B", "G", "D" })[comm_channel + 1],
        throttle,
        autopilot and "ON" or "OFF"
    )
    s:element({
        id = "status_text",
        type = "label",
        rect = { unit = "px", x = 10, y = H - 10 - status_h, w = W - 20, h = status_h },
        props = { text = status_text },
        style = { font_size = 9, color = "#00FFAA", align = "center" }
    })
end

function render()
    local desired = view or "main"
    if surfaces[desired] == nil then
        desired = "main"
    end
    s = surfaces[desired]
    s:clear()
    -- Background (full screen)
    s:element({
        id = "bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = H },
        style = { bg = "#0D0D1A" }
    })
    render_header()
    render_nav_tabs()
    if view == "main" then
        render_main_view()
    elseif view == "engine" then
        render_engine_view()
    elseif view == "navigation" then
        render_navigation_view()
    elseif view == "settings" then
        render_settings_view()
    end
    s:commit()
end

function set_view(name)
    local desired = name or "main"
    if surfaces[desired] == nil then
        desired = "main"
    end
    local previous = view
    view = desired
    s = surfaces[desired]
    ss.ui.activate(desired)
    if previous ~= view then
        log_action("View: " .. view)
    end
    render()
end

-- Initial render
log_action("Demo loaded")
set_view(view)

-- Tick function for animations
function tick(dt)
    -- Simulate fuel consumption when throttle > 0
    if throttle > 0 then
        fuel_level = math.max(0, fuel_level - throttle * 0.001)
        engine_temp = math.min(800, engine_temp + throttle * 0.1)
        render()
    else
        engine_temp = math.max(280, engine_temp - 0.5)
    end
    persist_save_state()
end
