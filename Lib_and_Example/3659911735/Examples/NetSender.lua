-- NetSender.lua
-- Example: Sends network messages to a target on the same data network.
-- Place this chip in a housing on the same data network as NetReceiver.

local LT = ic.enums.LogicType

local CHANNEL = "control"

-- Configuration: Target by name (set via labeller) or by ReferenceId
-- Option 1: Target by name (easier, requires labelling the receiver housing)
local TARGET_NAME = "Receiver"

-- Option 2: Target by ReferenceId (uncomment and set the actual id)
-- local TARGET_ID = 123456789

-- Send a simple string message
local function send_string()
    local ok, err = pcall(function()
        ic.net.send(TARGET_NAME, CHANNEL, "Hello from sender!")
    end)
    if ok then
        print("[NetSender] Sent string message")
    else
        print("[NetSender] Failed to send: " .. tostring(err))
    end
end

-- Send a structured table message
local function send_table()
    local message = {
        command = "set_on",
        value = 1,
        timestamp = os.time(),
        sender = "NetSender"
    }

    local ok, err = pcall(function()
        ic.net.send(TARGET_NAME, CHANNEL, message)
    end)
    if ok then
        print("[NetSender] Sent table message")
    else
        print("[NetSender] Failed to send: " .. tostring(err))
    end
end

-- Send a number
local function send_number()
    local temperature = ic.read(0, LT.Temperature) or 0
    local ok, err = pcall(function()
        ic.net.send(TARGET_NAME, CHANNEL, temperature)
    end)
    if ok then
        print("[NetSender] Sent temperature: " .. tostring(temperature))
    else
        print("[NetSender] Failed to send: " .. tostring(err))
    end
end

print("[NetSender] Starting - will send messages every 5 seconds")
print("[NetSender] Target: " .. TARGET_NAME)

-- Main loop - send different message types
local counter = 0
while true do
    counter = counter + 1

    if counter % 3 == 1 then
        send_string()
    elseif counter % 3 == 2 then
        send_table()
    else
        send_number()
    end

    sleep(5)
end
