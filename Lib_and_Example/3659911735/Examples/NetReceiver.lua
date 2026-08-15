-- NetReceiver.lua
-- Example: Listens for incoming network messages on a named channel.
-- Place this chip in a housing on a data network.
-- Use a labeller to name the housing (e.g., "Receiver") so senders can target it by name.
-- print() output appears in the Lua Debugger Logs tab.

local LT = ic.enums.LogicType
local CHANNEL = "control"

-- Handler function called when a message arrives on CHANNEL.
-- Parameters:
--   fromId   - ReferenceId of the sender's housing
--   fromName - DisplayName of the sender's housing (player-assigned via labeller)
--   payload  - The decoded message (can be nil, bool, number, string, or table)
function on_message(fromId, fromName, payload)
    print(string.format("[NetReceiver] Message from %s (id=%d)", fromName, fromId))

    -- Handle different payload types
    if type(payload) == "table" then
        -- If payload is a table, print its contents
        for k, v in pairs(payload) do
            print(string.format("  %s = %s", tostring(k), tostring(v)))
        end

        -- Example: If the message contains a "command" field, act on it
        if payload.command == "set_on" and payload.value ~= nil then
            ic.write(0, LT.On, payload.value)
            print("  -> Set device 0 On to " .. tostring(payload.value))
        end
    else
        print("  Payload: " .. tostring(payload))
    end
end

-- Register the handler by name (string) so it persists across save/load.
-- Using a string name instead of the function directly allows the handler
-- to survive world saves and reloads.
ic.net.listen(CHANNEL, "on_message")

-- Print our endpoint info so the user knows how to reach us
local myId = ic.net.id()
print(string.format("[NetReceiver] Listening on channel '%s' (my id=%s)", CHANNEL, tostring(myId)))
print("[NetReceiver] Tip: Use a labeller to name this housing for easier targeting!")

-- Main loop - just keep the chip running
while true do
    sleep(1)
end
