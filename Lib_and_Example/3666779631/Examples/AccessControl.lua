-- Access Control Panel
-- Security keypad with PIN code and biometric (player name) authentication
--
-- DEVICE WIRING:
--   d0 = Door or airlock to control
--
-- FEATURES:
--   - 4-digit PIN code entry via numeric keypad
--   - Biometric scan checks player name against authorized list
--   - Either valid PIN OR authorized biometric grants access
--   - Anyone can close the door (no auth required)
--   - Access log shows recent activity
--
-- DOOR BEHAVIOR:
--   - Door is set to Logic mode (Mode=1) and LOCKED on startup
--   - Manual interaction is disabled - only this script can control the door
--   - Open/close is controlled via Setting (0=closed, 1=open)
--   - Use CLOSE DOOR button or wait for timeout to close

local LT = ic.enums.LogicType
local read = ic.read
local write = ic.write
local yield = ic.yield

-- UI setup
local ui = ss.ui.surface("main")
ss.ui.activate("main")

local screen = ui:size()
local W = screen.w or 480
local H = screen.h or 272

-- ==================== CONFIGURATION ====================
-- Change these values to customize your security settings

-- The correct PIN code (4 digits)
local CORRECT_PIN = "1234"

-- Authorized player names for biometric access (case-insensitive)
local AUTHORIZED_PLAYERS = {
    "Zedle",
    -- Add more authorized players here
}

-- Door device slot
local DOOR_SLOT = 0

-- ==================== END CONFIGURATION ====================

-- State
local entered_pin = ""
local status_message = ""
local status_color = "#888888"
local status_timeout = 0
local access_log = {}
local MAX_LOG_ENTRIES = 5

-- Colors
local COLORS = {
    bg = "#0D1117",
    header = "#161B22",
    panel = "#21262D",
    accent = "#238636",
    danger = "#DA3633",
    warning = "#D29922",
    text = "#E6EDF3",
    text_dim = "#8B949E",
    button = "#30363D",
    button_hover = "#484F58",
    keypad = "#1F6FEB",
    biometric = "#8957E5",
}

-- Check if player is in authorized list (case-insensitive)
local function is_authorized(playerName)
    if not playerName or playerName == "" then
        return false
    end
    local playerLower = string.lower(playerName)
    for _, name in ipairs(AUTHORIZED_PLAYERS) do
        if string.lower(name) == playerLower then
            return true
        end
    end
    return false
end

-- Add entry to access log
local function log_access(playerName, method, granted)
    local entry = {
        player = playerName or "Unknown",
        method = method,
        granted = granted,
        time = os.date("%H:%M:%S"),
    }
    table.insert(access_log, 1, entry)
    while #access_log > MAX_LOG_ENTRIES do
        table.remove(access_log)
    end
end

-- Set status message with timeout
local function set_status(message, color, duration)
    status_message = message
    status_color = color
    status_timeout = duration or 3
end

-- Door control functions
-- Door is in Logic mode (Mode=1), script controls everything
-- We use Open to trigger the door, and lock/unlock as needed
local function open_door()
    write(DOOR_SLOT, LT.Lock, 0) -- Unlock to allow operation
    write(DOOR_SLOT, LT.Open, 1) -- Open
end

local function close_door()
    write(DOOR_SLOT, LT.Lock, 0) -- Unlock to allow operation
    write(DOOR_SLOT, LT.Open, 0) -- Close
end

-- Handle PIN digit entry
local function add_digit(digit)
    if #entered_pin < 4 then
        entered_pin = entered_pin .. digit
        set_status("", COLORS.text_dim, 0)
    end
end

-- Clear entered PIN
local function clear_pin()
    entered_pin = ""
    set_status("", COLORS.text_dim, 0)
end

-- Verify PIN and grant access
local function verify_pin(playerName)
    if entered_pin == CORRECT_PIN then
        set_status("ACCESS GRANTED", COLORS.accent, 3)
        log_access(playerName, "PIN", true)
        open_door()
    else
        set_status("ACCESS DENIED", COLORS.danger, 3)
        log_access(playerName, "PIN", false)
    end
    entered_pin = ""
end

-- Handle biometric scan
local function biometric_scan(playerName)
    if is_authorized(playerName) then
        set_status("BIOMETRIC VERIFIED: " .. playerName, COLORS.accent, 3)
        log_access(playerName, "BIO", true)
        open_door()
    else
        set_status("NOT AUTHORIZED: [" .. (playerName or "nil") .. "]", COLORS.danger, 5)
        log_access(playerName, "BIO", false)
    end
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

    -- Header bar
    local header = ui:element({
        id = "header",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = 50 },
        style = { bg = COLORS.header }
    })

    header:element({
        id = "title",
        type = "label",
        rect = { unit = "px", x = 16, y = 12, w = 200, h = 28 },
        props = { text = "ACCESS CONTROL" },
        style = { font_size = 20, color = COLORS.text, align = "left" }
    })

    -- Door status indicator
    local lock_state = read(DOOR_SLOT, LT.Lock)
    local is_locked = (lock_state or 0) > 0.5
    local door_color = is_locked and COLORS.danger or COLORS.accent
    local door_text = is_locked and "LOCKED" or "UNLOCKED"

    header:element({
        id = "door_status_dot",
        type = "panel",
        rect = { unit = "px", x = W - 120, y = 20, w = 12, h = 12 },
        style = { bg = door_color }
    })

    header:element({
        id = "door_status_txt",
        type = "label",
        rect = { unit = "px", x = W - 105, y = 16, w = 90, h = 20 },
        props = { text = door_text },
        style = { font_size = 14, color = door_color, align = "left" }
    })

    -- Interface mode button
    header:element({
        id = "interface_btn",
        type = "interface_button",
        rect = { unit = "px", x = W - 80, y = 32, w = 70, h = 16 },
        props = { text = "INTERFACE" },
        style = { bg = "#333333", text = "#AAAAAA", font_size = 8 }
    })

    -- Left panel: Keypad
    local keypad_x = 16
    local keypad_y = 60
    local btn_size = 50
    local btn_gap = 8

    -- PIN display
    local pin_panel = ui:element({
        id = "pin_panel",
        type = "panel",
        rect = { unit = "px", x = keypad_x, y = keypad_y, w = btn_size * 3 + btn_gap * 2, h = 40 },
        style = { bg = COLORS.panel }
    })

    local pin_display = string.rep("*", #entered_pin) .. string.rep("-", 4 - #entered_pin)
    pin_panel:element({
        id = "pin_display",
        type = "label",
        rect = { unit = "px", x = 10, y = 5, w = btn_size * 3 + btn_gap * 2 - 20, h = 30 },
        props = { text = pin_display },
        style = { font_size = 28, color = COLORS.text, align = "center" }
    })

    -- Numeric keypad (1-9, then C, 0, OK)
    local keys = {
        { "1", "2", "3" },
        { "4", "5", "6" },
        { "7", "8", "9" },
        { "C", "0", "OK" },
    }

    for row, row_keys in ipairs(keys) do
        for col, key in ipairs(row_keys) do
            local x = keypad_x + (col - 1) * (btn_size + btn_gap)
            local y = keypad_y + 50 + (row - 1) * (btn_size + btn_gap)

            local btn_color = COLORS.button
            local text_color = COLORS.text
            if key == "C" then
                btn_color = COLORS.warning
                text_color = "#000000"
            elseif key == "OK" then
                btn_color = COLORS.accent
                text_color = "#FFFFFF"
            end

            ui:element({
                id = "key_" .. key,
                type = "button",
                rect = { unit = "px", x = x, y = y, w = btn_size, h = btn_size },
                props = { text = key },
                style = { bg = btn_color, text = text_color, font_size = 20 },
                on_click = function(playerName)
                    if key == "C" then
                        clear_pin()
                    elseif key == "OK" then
                        verify_pin(playerName)
                    else
                        add_digit(key)
                    end
                    render()
                end
            })
        end
    end

    -- Right panel: Biometric + Close button
    local right_x = keypad_x + btn_size * 3 + btn_gap * 2 + 30
    local right_w = W - right_x - 16

    -- Biometric section
    local bio_panel = ui:element({
        id = "bio_panel",
        type = "panel",
        rect = { unit = "px", x = right_x, y = keypad_y, w = right_w, h = 115 },
        style = { bg = COLORS.panel }
    })

    bio_panel:element({
        id = "bio_title",
        type = "label",
        rect = { unit = "px", x = 10, y = 8, w = right_w - 20, h = 20 },
        props = { text = "BIOMETRIC SCAN" },
        style = { font_size = 12, color = COLORS.text_dim, align = "center" }
    })

    bio_panel:element({
        id = "bio_btn",
        type = "button",
        rect = { unit = "px", x = 20, y = 35, w = right_w - 40, h = 50 },
        props = { text = "SCAN" },
        style = { bg = COLORS.biometric, text = "#FFFFFF", font_size = 18 },
        on_click = function(playerName)
            biometric_scan(playerName)
            render()
        end
    })

    -- Close door button (no auth required)
    local close_panel = ui:element({
        id = "close_panel",
        type = "panel",
        rect = { unit = "px", x = right_x, y = keypad_y + 125, w = right_w, h = 60 },
        style = { bg = COLORS.panel }
    })

    close_panel:element({
        id = "close_btn",
        type = "button",
        rect = { unit = "px", x = 20, y = 10, w = right_w - 40, h = 40 },
        props = { text = "CLOSE DOOR" },
        style = { bg = COLORS.danger, text = "#FFFFFF", font_size = 14 },
        on_click = function(playerName)
            close_door()
            set_status("Door closed by " .. (playerName or "Unknown"), COLORS.text_dim, 2)
            render()
        end
    })

    -- Access log
    local log_top = keypad_y + 195
    local log_entry_h = 14
    local log_visible_entries = 3

    ui:element({
        id = "log_title",
        type = "label",
        rect = { unit = "px", x = right_x, y = log_top, w = right_w, h = 16 },
        props = { text = "RECENT ACCESS" },
        style = { font_size = 10, color = COLORS.text_dim, align = "left" }
    })

    for i, entry in ipairs(access_log) do
        if i > log_visible_entries then break end
        local y = log_top + i * log_entry_h
        local color = entry.granted and COLORS.accent or COLORS.danger
        local symbol = entry.granted and "+" or "x"
        local text = symbol .. " " .. entry.player .. " [" .. entry.method .. "]"
        ui:element({
            id = "log_" .. i,
            type = "label",
            rect = { unit = "px", x = right_x, y = y, w = right_w, h = 12 },
            props = { text = text },
            style = { font_size = 9, color = color, align = "left" }
        })
    end

    -- Status message area
    if status_message ~= "" then
        ui:element({
            id = "status_bg",
            type = "panel",
            rect = { unit = "px", x = 0, y = H - 28, w = W, h = 28 },
            style = { bg = COLORS.header }
        })
        ui:element({
            id = "status_txt",
            type = "label",
            rect = { unit = "px", x = 16, y = H - 24, w = W - 32, h = 22 },
            props = { text = status_message },
            style = { font_size = 14, color = status_color, align = "center" }
        })
    end

    ui:commit()
end

-- Initialize: set door to Logic mode and lock it
-- Logic mode (Mode=1) means manual interaction is disabled, script controls everything
write(DOOR_SLOT, LT.Mode, 1) -- Logic mode
write(DOOR_SLOT, LT.Lock, 1) -- Lock
write(DOOR_SLOT, LT.Open, 0) -- Ensure closed

-- Initial render
render()

-- Main loop
local tick = 0
while true do
    tick = tick + 1

    -- Update status timeout
    if status_timeout > 0 then
        status_timeout = status_timeout - 0.1
        if status_timeout <= 0 then
            status_message = ""
            render()
        end
    end

    -- Door is in Logic mode - script controls everything
    -- Keep it in Logic mode, and lock it when closed
    local mode_state = read(DOOR_SLOT, LT.Mode)
    local open_state = read(DOOR_SLOT, LT.Open)
    local idle_state = read(DOOR_SLOT, LT.Idle)
    local lock_state = read(DOOR_SLOT, LT.Lock)

    local is_open = (open_state or 0) > 0.5
    local is_idle = (idle_state or 1) > 0.5
    local is_locked = (lock_state or 0) > 0.5

    -- Ensure Logic mode
    if (mode_state or 0) < 0.5 then
        write(DOOR_SLOT, LT.Mode, 1)
    end

    -- Lock when closed and idle, unlock when open (so close operation works)
    if is_open then
        -- Keep unlocked while open so close button works
    elseif is_idle and not is_locked then
        -- Closed and idle: lock it
        write(DOOR_SLOT, LT.Lock, 1)
    end

    -- Periodic re-render
    if tick % 5 == 0 then
        render()
    end

    yield()
end
