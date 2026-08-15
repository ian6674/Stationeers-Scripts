-- StationOS - Fake Operating System UI
-- A retro-futuristic OS interface with utilities that leverage player identity
--
-- FEATURES:
--   - Login screen with player name detection
--   - File browser with user-specific "home" directory
--   - System monitor showing station stats
--   - Terminal emulator with basic commands
--   - Messaging system between users
--   - Customizable user themes

local LT = ic.enums.LogicType
local read = ic.read
local write = ic.write
local yield = ic.yield
local DB = ic.const.BASE_UNIT_INDEX

-- UI setup
local ui = ss.ui.surface("main")
ss.ui.activate("main")

local screen = ui:size()
local W = screen.w or 480
local H = screen.h or 272

-- ==================== COLORS & THEME ====================
local THEMES = {
    default = {
        bg = "#0C0C1E",
        desktop = "#1A1A2E",
        taskbar = "#16213E",
        window_bg = "#0F3460",
        window_title = "#1A1A40",
        accent = "#E94560",
        text = "#EAEAEA",
        text_dim = "#8892B0",
        button = "#1F4068",
        button_hover = "#2A5082",
        success = "#00D26A",
        warning = "#FFB800",
        error = "#FF4757",
    },
    matrix = {
        bg = "#000000",
        desktop = "#001100",
        taskbar = "#002200",
        window_bg = "#001800",
        window_title = "#003300",
        accent = "#00FF00",
        text = "#00FF00",
        text_dim = "#007700",
        button = "#003300",
        button_hover = "#004400",
        success = "#00FF00",
        warning = "#AAFF00",
        error = "#FF0000",
    },
    ocean = {
        bg = "#0A1929",
        desktop = "#0D2137",
        taskbar = "#132F4C",
        window_bg = "#173A5E",
        window_title = "#1E4976",
        accent = "#5090D3",
        text = "#B2BAC2",
        text_dim = "#5A6A7A",
        button = "#1E4976",
        button_hover = "#2A5A8A",
        success = "#4CAF50",
        warning = "#FFA726",
        error = "#F44336",
    },
}

local current_theme = "default"
local function C() return THEMES[current_theme] end

-- ==================== STATE ====================
local logged_in = false
local current_user = ""
local current_app = nil -- nil = desktop, or app name
local desktop_icons = {}
local messages = {}
local terminal_history = {}
local terminal_input = ""
local file_browser_path = "/"
local system_uptime = 0

-- User data storage (simulated file system)
local user_data = {}
local function get_user_data(user)
    if not user_data[user] then
        user_data[user] = {
            theme = "default",
            files = {
                ["readme.txt"] = "Welcome to StationOS!",
                ["notes.txt"] = "My personal notes...",
            },
            unread_messages = 0,
        }
    end
    return user_data[user]
end

-- Message storage
local function send_message(from, to, text)
    table.insert(messages, {
        from = from,
        to = to,
        text = text,
        time = os.date("%H:%M"),
        read = false,
    })
    local target_data = get_user_data(to)
    target_data.unread_messages = (target_data.unread_messages or 0) + 1
end

-- Pre-populate some messages
send_message("System", "Admin", "System initialized successfully.")
send_message("Commander", "Admin", "Status report needed ASAP.")

-- ==================== RENDER FUNCTIONS ====================

local function render_taskbar()
    local colors = C()

    -- Taskbar background
    ui:element({
        id = "taskbar",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = 32 },
        style = { bg = colors.taskbar }
    })

    -- OS logo/start button
    ui:element({
        id = "start_btn",
        type = "button",
        rect = { unit = "px", x = 4, y = 4, w = 60, h = 24 },
        props = { text = "STATION" },
        style = { bg = colors.accent, text = "#FFFFFF", font_size = 10 },
        on_click = function(playerName)
            if current_app then
                current_app = nil
            end
            render()
        end
    })

    -- Clock
    local time_str = os.date("%H:%M:%S")
    ui:element({
        id = "clock",
        type = "label",
        rect = { unit = "px", x = W - 70, y = 6, w = 65, h = 20 },
        props = { text = time_str },
        style = { font_size = 11, color = colors.text, align = "right" }
    })

    -- User name
    ui:element({
        id = "user_label",
        type = "label",
        rect = { unit = "px", x = W - 180, y = 6, w = 100, h = 20 },
        props = { text = current_user },
        style = { font_size = 10, color = colors.text_dim, align = "right" }
    })

    -- Interface mode button
    ui:element({
        id = "interface_btn",
        type = "interface_button",
        rect = { unit = "px", x = 70, y = 7, w = 55, h = 18 },
        props = { text = "INTERACT" },
        style = { bg = colors.button, text = colors.text_dim, font_size = 7 }
    })
end

local function render_desktop_icons()
    local colors = C()
    local icons = {
        { id = "app_files",    name = "Files",    app = "files",    x = 20,  y = 40 },
        { id = "app_terminal", name = "Terminal", app = "terminal", x = 20,  y = 100 },
        { id = "app_monitor",  name = "Monitor",  app = "monitor",  x = 20,  y = 160 },
        { id = "app_messages", name = "Messages", app = "messages", x = 100, y = 40 },
        { id = "app_settings", name = "Settings", app = "settings", x = 100, y = 100 },
        { id = "app_logout",   name = "Logout",   app = "logout",   x = 100, y = 160 },
    }

    for _, icon in ipairs(icons) do
        -- Icon button
        ui:element({
            id = icon.id,
            type = "button",
            rect = { unit = "px", x = icon.x, y = icon.y, w = 60, h = 40 },
            props = { text = icon.name },
            style = { bg = colors.button, text = colors.text, font_size = 10 },
            on_click = function(playerName)
                if icon.app == "logout" then
                    logged_in = false
                    current_user = ""
                    current_app = nil
                else
                    current_app = icon.app
                end
                render()
            end
        })
    end

    -- Show unread message count
    local udata = get_user_data(current_user)
    if udata.unread_messages and udata.unread_messages > 0 then
        ui:element({
            id = "msg_badge",
            type = "panel",
            rect = { unit = "px", x = 148, y = 59, w = 16, h = 16 },
            style = { bg = colors.error }
        })
        ui:element({
            id = "msg_badge_txt",
            type = "label",
            rect = { unit = "px", x = 148, y = 60, w = 16, h = 14 },
            props = { text = tostring(udata.unread_messages) },
            style = { font_size = 10, color = "#FFFFFF", align = "center" }
        })
    end
end

local function render_window(title, content_fn)
    local colors = C()
    local win_x = 180
    local win_y = 40
    local win_w = W - win_x - 10
    local win_h = H - 60

    -- Window background
    ui:element({
        id = "window_bg",
        type = "panel",
        rect = { unit = "px", x = win_x, y = win_y, w = win_w, h = win_h },
        style = { bg = colors.window_bg }
    })

    -- Title bar
    ui:element({
        id = "window_title_bg",
        type = "panel",
        rect = { unit = "px", x = win_x, y = win_y, w = win_w, h = 28 },
        style = { bg = colors.window_title }
    })

    ui:element({
        id = "window_title",
        type = "label",
        rect = { unit = "px", x = win_x + 10, y = win_y + 4, w = win_w - 60, h = 20 },
        props = { text = title },
        style = { font_size = 12, color = colors.text, align = "left" }
    })

    -- Close button
    ui:element({
        id = "window_close",
        type = "button",
        rect = { unit = "px", x = win_x + win_w - 28, y = win_y + 4, w = 20, h = 20 },
        props = { text = "X" },
        style = { bg = colors.error, text = "#FFFFFF", font_size = 10 },
        on_click = function(playerName)
            current_app = nil
            render()
        end
    })

    -- Content area
    content_fn(win_x + 8, win_y + 36, win_w - 16, win_h - 44)
end

local function render_files_app(x, y, w, h)
    local colors = C()
    local udata = get_user_data(current_user)

    -- Path bar
    ui:element({
        id = "files_path",
        type = "label",
        rect = { unit = "px", x = x, y = y, w = w, h = 18 },
        props = { text = "/home/" .. current_user },
        style = { font_size = 10, color = colors.text_dim, align = "left" }
    })

    -- File list
    local files = udata.files
    local i = 0
    for filename, content in pairs(files) do
        local fy = y + 24 + i * 24
        if fy + 22 > y + h then break end

        ui:element({
            id = "file_" .. i,
            type = "button",
            rect = { unit = "px", x = x, y = fy, w = w, h = 22 },
            props = { text = "  " .. filename },
            style = { bg = colors.button, text = colors.text, font_size = 11, align = "left" },
            on_click = function(playerName)
                -- Could open file viewer
                terminal_history[#terminal_history + 1] = "> Opening: " .. filename
                render()
            end
        })
        i = i + 1
    end

    -- New file button
    ui:element({
        id = "files_new",
        type = "button",
        rect = { unit = "px", x = x, y = y + h - 26, w = 80, h = 22 },
        props = { text = "+ New File" },
        style = { bg = colors.accent, text = "#FFFFFF", font_size = 10 },
        on_click = function(playerName)
            local fname = "file_" .. tostring(#udata.files + 1) .. ".txt"
            udata.files[fname] = "Created by " .. playerName
            render()
        end
    })
end

local function render_terminal_app(x, y, w, h)
    local colors = C()

    -- Terminal output
    local line_height = 14
    local max_lines = math.floor((h - 30) / line_height)

    for i = 1, math.min(#terminal_history, max_lines) do
        local idx = #terminal_history - max_lines + i
        if idx > 0 then
            ui:element({
                id = "term_line_" .. i,
                type = "label",
                rect = { unit = "px", x = x + 4, y = y + 50 + i * line_height, w = w - 8, h = line_height },
                props = { text = terminal_history[idx] },
                style = { font_size = 10, color = colors.text, align = "left" }
            })
        end
    end

    -- Input line
    ui:element({
        id = "term_prompt",
        type = "label",
        rect = { unit = "px", x = x + 4, y = y + h - 24, w = 60, h = 20 },
        props = { text = current_user .. "@station:~$" },
        style = { font_size = 10, color = colors.accent, align = "left" }
    })

    ui:element({
        id = "term_input",
        type = "textinput",
        rect = { unit = "px", x = x + 70, y = y + h - 26, w = w - 80, h = 22 },
        props = { value = terminal_input, placeholder = "Enter command…" },
        style = { bg = colors.desktop, text = colors.text, font_size = 10 },
        on_change = function(value, playerName)
            terminal_input = value or ""
        end
    })

    -- Quick command buttons
    local cmds = { "help", "whoami", "uptime", "clear" }
    for i, cmd in ipairs(cmds) do
        ui:element({
            id = "term_cmd_" .. i,
            type = "button",
            rect = { unit = "px", x = x + (i - 1) * 50, y = y + h - 48, w = 48, h = 18 },
            props = { text = cmd },
            style = { bg = colors.button, text = colors.text_dim, font_size = 8 },
            on_click = function(playerName)
                -- Execute command
                terminal_history[#terminal_history + 1] = "> " .. cmd
                if cmd == "help" then
                    terminal_history[#terminal_history + 1] = "Commands: help, whoami, uptime, clear, echo <msg>"
                elseif cmd == "whoami" then
                    terminal_history[#terminal_history + 1] = "User: " ..
                        playerName .. " (Session: " .. current_user .. ")"
                elseif cmd == "uptime" then
                    terminal_history[#terminal_history + 1] = "System uptime: " ..
                        math.floor(system_uptime) .. " seconds"
                elseif cmd == "clear" then
                    terminal_history = {}
                end
                render()
            end
        })
    end
end

local function render_monitor_app(x, y, w, h)
    local colors = C()

    -- System stats (simulated)
    local stats = {
        { label = "CPU Usage",  value = math.random(15, 85),  unit = "%" },
        { label = "Memory",     value = math.random(40, 70),  unit = "%" },
        { label = "Network",    value = math.random(0, 100),  unit = "kb/s" },
        { label = "Power Grid", value = math.random(80, 100), unit = "%" },
    }

    local bar_h = 20
    local gap = 8

    for i, stat in ipairs(stats) do
        local sy = y + 20 + i * (bar_h + gap + 16)

        ui:element({
            id = "stat_label_" .. i,
            type = "label",
            rect = { unit = "px", x = x, y = sy, w = w, h = 14 },
            props = { text = stat.label },
            style = { font_size = 10, color = colors.text_dim, align = "left" }
        })

        -- Progress bar
        local bar_color = colors.success
        if stat.value > 80 then
            bar_color = colors.error
        elseif stat.value > 60 then
            bar_color = colors.warning
        end

        ui:element({
            id = "stat_bar_" .. i,
            type = "progress",
            rect = { unit = "px", x = x, y = sy + 16, w = w - 60, h = bar_h },
            props = { value = tostring(stat.value), max = "100" },
            style = { bg = colors.desktop, fill = bar_color }
        })

        ui:element({
            id = "stat_value_" .. i,
            type = "label",
            rect = { unit = "px", x = x + w - 55, y = sy + 18, w = 55, h = bar_h },
            props = { text = stat.value .. stat.unit },
            style = { font_size = 12, color = colors.text, align = "right" }
        })
    end

    -- Active user
    ui:element({
        id = "mon_user",
        type = "label",
        rect = { unit = "px", x = x, y = y, w = w, h = 16 },
        props = { text = "Logged in as: " .. current_user },
        style = { font_size = 10, color = colors.accent, align = "left" }
    })
end

local function render_messages_app(x, y, w, h)
    local colors = C()
    local udata = get_user_data(current_user)

    -- Mark messages as read
    udata.unread_messages = 0

    -- Filter messages for current user
    local my_messages = {}
    for _, msg in ipairs(messages) do
        if msg.to == current_user or msg.from == current_user then
            table.insert(my_messages, msg)
        end
    end

    -- Message list
    local msg_h = 40
    for i = 1, math.min(#my_messages, 4) do
        local msg = my_messages[#my_messages - i + 1]
        local my = y + (i - 1) * (msg_h + 4)

        local is_sent = msg.from == current_user
        local header = is_sent and ("To: " .. msg.to) or ("From: " .. msg.from)
        local bg = is_sent and colors.button_hover or colors.button

        ui:element({
            id = "msg_bg_" .. i,
            type = "panel",
            rect = { unit = "px", x = x, y = my, w = w, h = msg_h },
            style = { bg = bg }
        })

        ui:element({
            id = "msg_header_" .. i,
            type = "label",
            rect = { unit = "px", x = x + 4, y = my + 4, w = w - 50, h = 14 },
            props = { text = header },
            style = { font_size = 9, color = colors.accent, align = "left" }
        })

        ui:element({
            id = "msg_time_" .. i,
            type = "label",
            rect = { unit = "px", x = x + w - 50, y = my + 4, w = 46, h = 14 },
            props = { text = msg.time },
            style = { font_size = 9, color = colors.text_dim, align = "right" }
        })

        ui:element({
            id = "msg_text_" .. i,
            type = "label",
            rect = { unit = "px", x = x + 4, y = my + 20, w = w - 8, h = 18 },
            props = { text = msg.text },
            style = { font_size = 10, color = colors.text, align = "left" }
        })
    end

    -- Compose section at bottom
    ui:element({
        id = "msg_compose_label",
        type = "label",
        rect = { unit = "px", x = x, y = y + h - 24, w = 50, h = 16 },
        props = { text = "Quick:" },
        style = { font_size = 9, color = colors.text_dim, align = "left" }
    })

    ui:element({
        id = "msg_send_admin",
        type = "button",
        rect = { unit = "px", x = x + 50, y = y + h - 26, w = 70, h = 20 },
        props = { text = "Ping Admin" },
        style = { bg = colors.accent, text = "#FFFFFF", font_size = 9 },
        on_click = function(playerName)
            send_message(playerName, "Admin", "Hello from " .. playerName)
            render()
        end
    })
end

local function render_settings_app(x, y, w, h)
    local colors = C()

    ui:element({
        id = "settings_title",
        type = "label",
        rect = { unit = "px", x = x, y = y, w = w, h = 18 },
        props = { text = "Theme Selection" },
        style = { font_size = 12, color = colors.text, align = "left" }
    })

    local themes = { "default", "matrix", "ocean" }
    for i, theme in ipairs(themes) do
        local is_active = current_theme == theme
        local btn_bg = is_active and colors.accent or colors.button

        ui:element({
            id = "theme_" .. theme,
            type = "button",
            rect = { unit = "px", x = x, y = y + 24 + (i - 1) * 35, w = w, h = 30 },
            props = { text = theme:upper() .. (is_active and " (active)" or "") },
            style = { bg = btn_bg, text = colors.text, font_size = 12 },
            on_click = function(playerName)
                current_theme = theme
                local udata = get_user_data(current_user)
                udata.theme = theme
                render()
            end
        })
    end

    ui:element({
        id = "settings_user",
        type = "label",
        rect = { unit = "px", x = x, y = y + h - 20, w = w, h = 16 },
        props = { text = "Logged in: " .. current_user },
        style = { font_size = 10, color = colors.text_dim, align = "left" }
    })
end

local function render_login_screen()
    local colors = C()
    ui:clear()

    -- Background
    ui:element({
        id = "login_bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = H },
        style = { bg = colors.bg }
    })

    -- Logo/title
    ui:element({
        id = "login_logo",
        type = "label",
        rect = { unit = "px", x = 0, y = 40, w = W, h = 40 },
        props = { text = "STATION OS" },
        style = { font_size = 32, color = colors.accent, align = "center" }
    })

    ui:element({
        id = "login_subtitle",
        type = "label",
        rect = { unit = "px", x = 0, y = 80, w = W, h = 20 },
        props = { text = "v2.4.1 - Secure Terminal Access" },
        style = { font_size = 11, color = colors.text_dim, align = "center" }
    })

    -- Login panel
    local panel_w = 200
    local panel_h = 100
    local panel_x = (W - panel_w) / 2
    local panel_y = (H - panel_h) / 2 + 10

    ui:element({
        id = "login_panel",
        type = "panel",
        rect = { unit = "px", x = panel_x, y = panel_y, w = panel_w, h = panel_h },
        style = { bg = colors.window_bg }
    })

    ui:element({
        id = "login_prompt",
        type = "label",
        rect = { unit = "px", x = panel_x, y = panel_y + 6, w = panel_w, h = 24 },
        props = { text = "Touch to authenticate" },
        style = { font_size = 12, color = colors.text, align = "center" }
    })

    -- Login button - captures player name
    ui:element({
        id = "login_btn",
        type = "button",
        rect = { unit = "px", x = panel_x + 20, y = panel_y + 35, w = panel_w - 40, h = 45 },
        props = { text = "LOGIN" },
        style = { bg = colors.accent, text = "#FFFFFF", font_size = 16 },
        on_click = function(playerName)
            current_user = playerName or "Guest"
            logged_in = true

            -- Load user theme
            local udata = get_user_data(current_user)
            current_theme = udata.theme or "default"

            terminal_history[#terminal_history + 1] = "Welcome, " .. current_user .. "!"
            terminal_history[#terminal_history + 1] = "Type 'help' for available commands."

            render()
        end
    })

    -- Interface mode button
    ui:element({
        id = "interface_btn",
        type = "interface_button",
        rect = { unit = "px", x = W / 2 - 35, y = H - 50, w = 70, h = 20 },
        props = { text = "INTERFACE" },
        style = { bg = colors.button, text = colors.text_dim, font_size = 9 }
    })

    ui:commit()
end

local function render_desktop()
    local colors = C()
    ui:clear()

    -- Desktop background
    ui:element({
        id = "desktop_bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = H },
        style = { bg = colors.desktop }
    })

    render_taskbar()
    render_desktop_icons()

    -- Render active app window
    if current_app == "files" then
        render_window("File Browser - /home/" .. current_user, render_files_app)
    elseif current_app == "terminal" then
        render_window("Terminal - " .. current_user .. "@station", render_terminal_app)
    elseif current_app == "monitor" then
        render_window("System Monitor", render_monitor_app)
    elseif current_app == "messages" then
        render_window("Messages", render_messages_app)
    elseif current_app == "settings" then
        render_window("Settings", render_settings_app)
    end

    ui:commit()
end

function render()
    if logged_in then
        render_desktop()
    else
        render_login_screen()
    end
end

-- Initial render
render()

-- Main loop
local tick = 0
while true do
    tick = tick + 1
    system_uptime = system_uptime + 0.1

    -- Periodic refresh (for clock, stats, etc.)
    if tick % 10 == 0 then
        render()
    end

    yield()
end
