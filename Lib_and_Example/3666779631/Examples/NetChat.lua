-- NetChat.lua
-- ScriptedScreens example: A network chat UI
-- Deploy this to multiple consoles on the same data network.
-- Players can send text messages that appear on all connected screens.
-- print() output appears in the Lua Debugger Logs tab.

local ui = ss.ui.surface("main")
ss.ui.activate("main")

local CHANNEL = "chat"
local PING_CHANNEL = "monitor"
local MAX_MESSAGES = 12

local size = ui:size()
local W, H = 480, 272
if size then W, H = size.w or W, size.h or H end

-- State
local messages = {}
local inputText = ""
local myId = ic.net.id()
local myName = "Console"

local function update_my_name()
    local peers = ic.net.peers()
    for _, peer in ipairs(peers) do
        if peer.id == myId then
            myName = peer.name ~= "" and peer.name or ("Console-" .. myId)
            break
        end
    end
end
update_my_name()

-- Add a message to the chat log
local function add_message(sender, text, isSystem)
    table.insert(messages, {
        sender = sender,
        text = text,
        time = os.time(),
        isSystem = isSystem or false
    })
    if sender ~= "SYSTEM" then
        print(string.format("[NetChat] %s: %s", tostring(sender), tostring(text)))
    end
    -- Trim old messages
    while #messages > MAX_MESSAGES do
        table.remove(messages, 1)
    end
end

-- Handle incoming chat messages
function on_chat(fromId, fromName, payload)
    if type(payload) ~= "table" then return end
    if payload.type == "chat" and payload.text then
        local sender = payload.sender or fromName or ("ID:" .. fromId)
        add_message(sender, payload.text, false)
        render()
    elseif payload.type == "join" then
        local joinName = payload.name or fromName
        add_message("SYSTEM", joinName .. " joined the chat", true)
        print(string.format("[NetChat] %s joined", tostring(joinName)))
        render()
    end
end

ic.net.listen(CHANNEL, "on_chat")

-- Handle incoming pings from NetPeerMonitor and other pingers
function on_ping(fromId, fromName, payload)
    if type(payload) ~= "table" then return end

    if payload.type == "ping" then
        -- Reply with pong
        pcall(function()
            ic.net.send(fromId, PING_CHANNEL, { type = "pong" })
        end)

        -- Show ping in chat log
        local sender = fromName or ("ID:" .. fromId)
        add_message("PING", sender .. " pinged us", true)
        render()
    elseif payload.type == "pong" then
        -- We received a pong (if we ever send pings)
        local sender = fromName or ("ID:" .. fromId)
        add_message("PONG", sender .. " replied", true)
        render()
    end
end

ic.net.listen(PING_CHANNEL, "on_ping")

-- Send a chat message
local function send_message(text)
    if text == "" then return end

    print(string.format("[NetChat] Sending: %s", tostring(text)))

    local msg = {
        type = "chat",
        sender = myName,
        text = text
    }

    -- Add to our own log
    add_message(myName, text, false)

    -- Broadcast to others
    ic.net.broadcast(CHANNEL, msg)
end

-- Announce our presence
local function announce_join()
    print("[NetChat] Announcing join")
    ic.net.broadcast(CHANNEL, { type = "join", name = myName })
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
        rect = { unit = "px", x = 0, y = 0, w = W, h = 40 },
        style = { bg = "#1E293B" }
    })

    header:element({
        id = "title",
        type = "label",
        rect = { unit = "px", x = 12, y = 8, w = 200, h = 24 },
        props = { text = "NETWORK CHAT" },
        style = { font_size = 16, color = "#22C55E", align = "left" }
    })

    header:element({
        id = "interface",
        type = "interface_button",
        rect = { unit = "px", x = W - 240, y = 8, w = 72, h = 24 },
        props = { text = "TYPE" },
        style = { bg = "#2563EB", text = "#E2E8F0" }
    })

    header:element({
        id = "my_name",
        type = "label",
        rect = { unit = "px", x = W - 160, y = 12, w = 150, h = 18 },
        props = { text = myName },
        style = { font_size = 11, color = "#64748B", align = "right" }
    })

    -- Message area
    local msgAreaY = 44
    local msgAreaH = H - 94

    -- Render messages (bottom to top, newest at bottom)
    local lineH = 18
    local startY = 6
    local msgSpacing = 2
    local msgWidth = W - 140
    local sysWidth = W - 36

    -- Pre-measure message heights so we can size the scrollable content accurately.
    local layouts = {}
    local contentHeight = startY

    for i, msg in ipairs(messages) do
        local textColor = msg.isSystem and "#FFEB3B" or "#E2E8F0"
        local senderColor = msg.isSystem and "#FFEB3B" or "#22C55E"
        local fontSize = msg.isSystem and 10 or 11
        local messageText = msg.isSystem and ("[" .. msg.text .. "]") or msg.text
        local maxWidth = msg.isSystem and sysWidth or msgWidth
        local measured = ui:measure_text(messageText, maxWidth, fontSize, true)
        local measuredHeight = measured and measured.h or 0
        local messageHeight = math.max(lineH, math.ceil(measuredHeight))

        layouts[i] = {
            isSystem = msg.isSystem,
            textColor = textColor,
            senderColor = senderColor,
            fontSize = fontSize,
            messageText = messageText,
            messageHeight = messageHeight
        }

        contentHeight = contentHeight + messageHeight + msgSpacing
    end

    contentHeight = math.max(msgAreaH, contentHeight + 6)

    local scroll = ui:element({
        id = "msg_scroll",
        type = "scrollview",
        rect = { unit = "px", x = 8, y = msgAreaY, w = W - 16, h = msgAreaH },
        props = { content_height = tostring(contentHeight) },
        style = { bg = "#111827", scrollbar_bg = "#0B1220", scrollbar_handle = "#334155" }
    })

    local y = startY

    for i, layout in ipairs(layouts) do
        if not layout.isSystem then
            -- Sender name
            scroll:element({
                id = "msg_sender_" .. i,
                type = "label",
                rect = { unit = "px", x = 14, y = y, w = 100, h = lineH },
                props = { text = messages[i].sender .. ":" },
                style = { font_size = 11, color = layout.senderColor, align = "left" }
            })

            -- Message text
            scroll:element({
                id = "msg_text_" .. i,
                type = "label",
                rect = { unit = "px", x = 120, y = y, w = msgWidth, h = layout.messageHeight },
                props = { text = layout.messageText },
                style = { font_size = layout.fontSize, color = layout.textColor, align = "left" }
            })
        else
            -- System message (full width, centered)
            scroll:element({
                id = "msg_sys_" .. i,
                type = "label",
                rect = { unit = "px", x = 14, y = y, w = sysWidth, h = layout.messageHeight },
                props = { text = layout.messageText },
                style = { font_size = layout.fontSize, color = layout.textColor, align = "center" }
            })
        end

        y = y + layout.messageHeight + msgSpacing
    end

    -- Input area
    local input_area = ui:element({
        id = "input_bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = H - 44, w = W, h = 44 },
        style = { bg = "#1E293B" }
    })

    input_area:element({
        id = "input",
        type = "textinput",
        rect = { unit = "px", x = 12, y = 8, w = W - 100, h = 28 },
        props = { value = inputText, placeholder = "Type a message…" },
        style = { bg = "#0F172A", color = "#E2E8F0", font_size = 12 },
        on_change = function(value, playerName)
            inputText = value or ""
            render()
        end
    })

    input_area:element({
        id = "send_btn",
        type = "button",
        rect = { unit = "px", x = W - 80, y = 8, w = 70, h = 28 },
        props = { text = "SEND" },
        style = { bg = "#22C55E", text = "#0F172A" },
        on_click = function(playerName)
            if inputText ~= "" then
                send_message(inputText)
                inputText = ""
                render()
            end
        end
    })

    ui:commit()
end

-- Initial render
print(string.format("[NetChat] Connected as %s (id=%d)", myName, myId))
add_message("SYSTEM", "Connected as " .. myName, true)
render()

-- Announce join after a moment
sleep(1)
announce_join()

-- Main loop - just keep alive and periodically refresh name
local tick = 0
while true do
    tick = tick + 1

    -- Refresh our name occasionally (in case it was changed via labeller)
    if tick % 300 == 0 then
        update_my_name()
    end

    ic.yield()
end
