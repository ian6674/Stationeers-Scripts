-- NetAnnouncements.lua
-- ScriptedScreens example: Network announcement board
-- One console can post announcements that appear on all other screens.
-- Name your console "Announcer" to get the posting controls.

local ui = ss.ui.surface("main")
ss.ui.activate("main")

local CHANNEL = "announcements"
local MAX_ANNOUNCEMENTS = 5

local size = ui:size()
local W, H = 480, 272
if size then W, H = size.w or W, size.h or H end

-- State
local announcements = {}
local isAnnouncer = false
local myId = ic.net.id()
local myName = "Display"
local inputText = ""
local selectedPriority = "normal"

-- Determine if we're the announcer
local function check_role()
    local peers = ic.net.peers()
    for _, peer in ipairs(peers) do
        if peer.id == myId then
            myName = peer.name ~= "" and peer.name or "Display"
            isAnnouncer = myName:lower():find("announcer") ~= nil
            break
        end
    end
end
check_role()

-- Add an announcement
local function add_announcement(from, text, priority, timestamp)
    table.insert(announcements, 1, {
        from = from,
        text = text,
        priority = priority or "normal",
        time = timestamp or os.time()
    })
    while #announcements > MAX_ANNOUNCEMENTS do
        table.remove(announcements)
    end
end

-- Handle incoming announcements
function on_announcement(fromId, fromName, payload)
    if type(payload) ~= "table" then return end
    if payload.type == "announcement" then
        add_announcement(payload.from or fromName, payload.text, payload.priority, payload.time)
        render()
    elseif payload.type == "clear" then
        announcements = {}
        render()
    end
end

ic.net.listen(CHANNEL, "on_announcement")

-- Send an announcement
local function send_announcement(text, priority)
    if text == "" then return end

    local msg = {
        type = "announcement",
        from = myName,
        text = text,
        priority = priority,
        time = os.time()
    }

    -- Add locally
    add_announcement(myName, text, priority, os.time())

    -- Broadcast
    ic.net.broadcast(CHANNEL, msg)
end

-- Clear all announcements
local function clear_all()
    announcements = {}
    ic.net.broadcast(CHANNEL, { type = "clear" })
end

-- Get priority color
local function get_priority_color(priority)
    if priority == "urgent" then
        return "#FF5252"
    elseif priority == "warning" then
        return "#FFEB3B"
    else
        return "#22C55E"
    end
end

-- Format time ago
local function time_ago(timestamp)
    local diff = os.time() - timestamp
    if diff < 60 then
        return diff .. "s ago"
    elseif diff < 3600 then
        return math.floor(diff / 60) .. "m ago"
    else
        return math.floor(diff / 3600) .. "h ago"
    end
end

-- Render the UI
function render()
    ui:clear()

    -- Background
    ui:element({
        id = "bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = H },
        style = { bg = "#0F172A" }
    })

    -- Header
    local header = ui:element({
        id = "header",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = 44 },
        style = { bg = "#1E293B" }
    })

    header:element({
        id = "title",
        type = "label",
        rect = { unit = "px", x = 16, y = 10, w = 250, h = 24 },
        props = { text = "STATION ANNOUNCEMENTS" },
        style = { font_size = 16, color = "#F59E0B", align = "left" }
    })

    local roleText = isAnnouncer and "[ANNOUNCER]" or "[DISPLAY]"
    local roleColor = isAnnouncer and "#22C55E" or "#64748B"
    header:element({
        id = "role",
        type = "label",
        rect = { unit = "px", x = W - 110, y = 12, w = 100, h = 20 },
        props = { text = roleText },
        style = { font_size = 10, color = roleColor, align = "right" }
    })

    -- Content area depends on role
    local contentY = isAnnouncer and (H - 84) or (H - 10)
    local contentH = contentY - 54

    -- Announcements list
    if #announcements == 0 then
        ui:element({
            id = "no_announcements",
            type = "label",
            rect = { unit = "px", x = 20, y = H / 2 - 20, w = W - 40, h = 40 },
            props = { text = "No announcements" },
            style = { font_size = 14, color = "#475569", align = "center" }
        })
    else
        local rowH = 44
        for i, ann in ipairs(announcements) do
            if i > MAX_ANNOUNCEMENTS then break end

            local y = 50 + ((i - 1) * rowH)
            if y + rowH > contentY then break end

            local priorityColor = get_priority_color(ann.priority)
            local bgColor = i == 1 and "#1E293B" or "#111827"

            -- Row background
            ui:element({
                id = "ann_row_" .. i,
                type = "panel",
                rect = { unit = "px", x = 8, y = y, w = W - 16, h = rowH - 4 },
                style = { bg = bgColor }
            })

            -- Priority indicator
            ui:element({
                id = "ann_pri_" .. i,
                type = "panel",
                rect = { unit = "px", x = 8, y = y, w = 4, h = rowH - 4 },
                style = { bg = priorityColor }
            })

            -- From / time
            ui:element({
                id = "ann_from_" .. i,
                type = "label",
                rect = { unit = "px", x = 18, y = y + 4, w = 150, h = 14 },
                props = { text = ann.from },
                style = { font_size = 10, color = "#64748B", align = "left" }
            })

            ui:element({
                id = "ann_time_" .. i,
                type = "label",
                rect = { unit = "px", x = W - 90, y = y + 4, w = 80, h = 14 },
                props = { text = time_ago(ann.time) },
                style = { font_size = 9, color = "#475569", align = "right" }
            })

            -- Message text
            ui:element({
                id = "ann_text_" .. i,
                type = "label",
                rect = { unit = "px", x = 18, y = y + 20, w = W - 44, h = 20 },
                props = { text = ann.text },
                style = { font_size = 12, color = "#E2E8F0", align = "left" }
            })
        end
    end

    -- Announcer controls
    if isAnnouncer then
        local input_bg = ui:element({
            id = "input_bg",
            type = "panel",
            rect = { unit = "px", x = 0, y = H - 84, w = W, h = 84 },
            style = { bg = "#1E293B" }
        })

        input_bg:element({
            id = "input_label",
            type = "label",
            rect = { unit = "px", x = 12, y = 2, w = 120, h = 16 },
            props = { text = "New Announcement:" },
            style = { font_size = 10, color = "#94A3B8", align = "left" }
        })

        input_bg:element({
            id = "input",
            type = "textinput",
            rect = { unit = "px", x = 12, y = 22, w = W - 100, h = 26 },
            props = { text = inputText, placeholder = "Enter announcement…" },
            style = { bg = "#0F172A", color = "#E2E8F0", font_size = 11 },
            on_change = function(value)
                inputText = value or ""
            end
        })

        -- Priority buttons
        local priorities = { "normal", "warning", "urgent" }
        local priColors = { normal = "#22C55E", warning = "#FFEB3B", urgent = "#FF5252" }

        for pi, pri in ipairs(priorities) do
            local isSelected = selectedPriority == pri
            local bgColor = isSelected and priColors[pri] or "#334155"
            local textColor = isSelected and "#0F172A" or priColors[pri]

            input_bg:element({
                id = "pri_" .. pri,
                type = "button",
                rect = { unit = "px", x = 12 + (pi - 1) * 70, y = 56, w = 65, h = 22 },
                props = { text = pri:upper() },
                style = { bg = bgColor, text = textColor },
                on_click = function()
                    selectedPriority = pri
                    render()
                end
            })
        end

        -- Send button
        input_bg:element({
            id = "send_btn",
            type = "button",
            rect = { unit = "px", x = W - 80, y = 22, w = 70, h = 26 },
            props = { text = "SEND" },
            style = { bg = "#F59E0B", text = "#0F172A" },
            on_click = function()
                if inputText ~= "" then
                    send_announcement(inputText, selectedPriority)
                    inputText = ""
                    render()
                end
            end
        })

        -- Clear button
        input_bg:element({
            id = "clear_btn",
            type = "button",
            rect = { unit = "px", x = W - 80, y = 56, w = 70, h = 22 },
            props = { text = "CLEAR" },
            style = { bg = "#475569", text = "#E2E8F0" },
            on_click = function()
                clear_all()
                render()
            end
        })
    end

    ui:commit()
end

-- Initial render
render()

-- Main loop
local tick = 0
while true do
    tick = tick + 1

    -- Re-check role periodically (in case labeller changed)
    if tick % 300 == 0 then
        local wasAnnouncer = isAnnouncer
        check_role()
        if wasAnnouncer ~= isAnnouncer then
            render()
        end
    end

    -- Re-render to update time-ago
    if tick % 60 == 0 then
        render()
    end

    ic.yield()
end
