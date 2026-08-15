-- HttpPostExample.lua
-- Demonstrates using ic.http.post() to send JSON data to an HTTP endpoint
-- and polling for the response.
--
-- Requirements:
--   Server must have AllowHttp = True in the StationeersLua config.
--
-- API:
--   ic.http.get(url [, headers] [, timeout])        -> requestId
--   ic.http.post(url, body [, contentType] [, headers] [, timeout]) -> requestId
--   ic.http.put(url, body [, contentType] [, headers] [, timeout])  -> requestId
--   ic.http.delete(url [, headers] [, timeout])     -> requestId
--   ic.http.patch(url, body [, contentType] [, headers] [, timeout]) -> requestId
--   ic.http.poll() -> id, success, statusCode, body, error  (or nil)
--
-- Notes:
--   - Requests are asynchronous. poll() returns nil until the response arrives.
--   - Max 8 concurrent requests, 64KB body, 256KB response, 30s max timeout.
--   - Only http:// and https:// URLs are allowed.

-- Build a JSON payload
local payload = util.json.encode({
    sensor = "atmosphere",
    pressure = 101.325,
    temperature = 293.15,
    timestamp = ic.game_time(),
})

-- Send a POST request with custom headers
local reqId = ic.http.post(
    "https://httpbin.org/post",
    payload,
    "application/json",
    { ["X-Station-Id"] = "base-alpha" }
)

print("Request sent: " .. reqId)

-- Poll loop: wait for the response
local maxWait = 15 -- seconds
local elapsed = 0

while elapsed < maxWait do
    local id, success, status, body, err = ic.http.poll()

    if id ~= nil then
        if success then
            print("POST " .. status .. " OK")
            -- httpbin.org echoes back the posted JSON in response.json
            local resp = util.json.decode(body)
            if resp and resp.json then
                print("Echoed pressure: " .. tostring(resp.json.pressure))
            end
        else
            print("POST failed: " .. tostring(status) .. " " .. tostring(err))
        end
        return
    end

    sleep(0.25)
    elapsed = elapsed + 0.25
end

print("Request timed out after " .. maxWait .. "s")
