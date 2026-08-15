-- NetPollReceiver.lua
-- Example: Poll-style message receiving using ic.net.recv() instead of handlers.
-- Useful when you want to process messages at specific points in your main loop
-- rather than via callback handlers.

local LT = ic.enums.LogicType

local CHANNEL = "inbox"

-- Note: We do NOT call ic.net.listen() for CHANNEL.
-- Messages to CHANNEL will go to the inbox for polling.

print(string.format("[PollReceiver] Listening on channel '%s' via polling", CHANNEL))
print("[PollReceiver] Send messages to this chip to see them processed")

local messagesProcessed = 0

-- Process all pending messages in the inbox
local function process_inbox()
    local count = 0

    while true do
        -- recv() returns nil if inbox is empty
        -- otherwise returns: fromId, fromName, channel, payload
        local fromId, fromName, channel, payload = ic.net.recv()

        if fromId == nil then
            break -- No more messages
        end

        count = count + 1
        messagesProcessed = messagesProcessed + 1

        print(string.format("[PollReceiver] Message #%d from %s (id=%d) on channel %s:",
            messagesProcessed, fromName, fromId, tostring(channel)))

        if type(payload) == "table" then
            for k, v in pairs(payload) do
                print(string.format("    %s = %s", tostring(k), tostring(v)))
            end
        else
            print(string.format("    payload = %s", tostring(payload)))
        end
    end

    if count > 0 then
        print(string.format("[PollReceiver] Processed %d message(s) this cycle", count))
    end

    return count
end

-- Main loop - poll for messages at our own pace
while true do
    -- Do some other work first...
    local temp = ic.read(0, LT.Temperature) or 0
    local pressure = ic.read(0, LT.Pressure) or 0

    -- Now process any pending network messages
    local processed = process_inbox()

    -- More work...
    if messagesProcessed > 0 and messagesProcessed % 10 == 0 then
        print(string.format("[PollReceiver] Total messages processed: %d", messagesProcessed))
    end

    -- Sleep before next iteration
    sleep(1)
end
