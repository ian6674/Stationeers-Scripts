-- HttpGetExample.lua
-- Demonstrates using ic.http.get() to fetch data from an HTTP endpoint.
--
-- Requirements:
--   Server must have AllowHttp = True in the StationeersLua config.
--
-- How it works:
--   1. Send a GET request to a public JSON API.
--   2. Poll for the response each tick.
--   3. Log the result to the chip's display.

-- Send a GET request to a public test API
local requestId = ic.http.get("https://httpbin.org/get")

-- Poll until we get a response
while true do
    local id, success, statusCode, body, err = ic.http.poll()

    if id ~= nil then
        if success then
            -- Parse the JSON response
            local data = util.json.decode(body)
            print("HTTP " .. statusCode .. " OK")
            print("Origin: " .. (data and data.origin or "unknown"))
        else
            print("HTTP error: " .. (err or "unknown"))
        end
        break
    end

    -- No response yet - yield and try again next tick
    sleep(0.1)
end
