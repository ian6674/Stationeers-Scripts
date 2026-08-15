-- NetSensorNetwork.lua
-- Example: A practical sensor network where multiple chips report to a central hub.
-- Deploy multiple copies of this script across your base, each monitoring local sensors.
-- Name one housing "Hub" to act as the central data collector.

local LT = ic.enums.LogicType

-- Configuration
local REPORT_CHANNEL = "sensor_report"
local COMMAND_CHANNEL = "sensor_command"
local REPORT_INTERVAL = 10 -- seconds

-- Determine our role
local myId = ic.net.id()
local peers = ic.net.peers()
local myName = ""
local isHub = false

for _, peer in ipairs(peers) do
    if peer.id == myId then
        myName = peer.name
        isHub = myName:lower():find("hub") ~= nil
    end
end

print(string.format("[SensorNet] Node '%s' (id=%d) - Role: %s",
    myName, myId, isHub and "HUB" or "SENSOR"))

--------------------------------------------------------------------------------
-- HUB MODE: Collect and display sensor data from all nodes
--------------------------------------------------------------------------------

if isHub then
    local sensorData = {} -- Table of node data keyed by id

    function on_sensor_report(fromId, fromName, payload)
        if type(payload) ~= "table" or payload.type ~= "sensor_report" then
            return
        end

        sensorData[fromId] = {
            name = fromName,
            temperature = payload.temperature,
            pressure = payload.pressure,
            timestamp = os.time()
        }

        print(string.format("[Hub] Report from '%s': T=%.1fK P=%.1fkPa",
            fromName, payload.temperature or 0, payload.pressure or 0))
    end

    ic.net.listen(REPORT_CHANNEL, "on_sensor_report")

    -- Hub can send commands to all sensors
    local function send_command(cmd)
        local delivered = ic.net.broadcast(COMMAND_CHANNEL, { type = "command", command = cmd })
        print(string.format("[Hub] Command '%s' sent to %d sensors", cmd, delivered))
    end

    -- Hub main loop
    print(string.format("[Hub] Collecting sensor reports on channel '%s'", REPORT_CHANNEL))

    while true do
        sleep(30)

        -- Print summary
        print("")
        print("=== Sensor Network Summary ===")
        local staleThreshold = os.time() - 60

        for id, data in pairs(sensorData) do
            local status = data.timestamp > staleThreshold and "OK" or "STALE"
            print(string.format("  %s: T=%.1fK P=%.1fkPa [%s]",
                data.name, data.temperature or 0, data.pressure or 0, status))
        end
        print("")
    end

    --------------------------------------------------------------------------------
    -- SENSOR MODE: Read local sensors and report to hub
    --------------------------------------------------------------------------------
else
    -- Handle commands from hub
    function on_command(fromId, fromName, payload)
        if type(payload) ~= "table" or payload.type ~= "command" then
            return
        end

        print(string.format("[Sensor] Command from hub: %s", payload.command or "unknown"))

        if payload.command == "identify" then
            -- Flash a light or something to identify this node
            ic.write(0, LT.On, 1)
            sleep(0.5)
            ic.write(0, LT.On, 0)
        end
    end

    ic.net.listen(COMMAND_CHANNEL, "on_command")

    -- Report sensor data to hub
    local function report_to_hub()
        local report = {
            type = "sensor_report",
            temperature = ic.read(0, LT.Temperature) or 0,
            pressure = ic.read(0, LT.Pressure) or 0,
            nodeId = myId,
            nodeName = myName
        }

        local ok, err = pcall(function()
            ic.net.send("Hub", REPORT_CHANNEL, report)
        end)
        if ok then
            print(string.format("[Sensor] Reported T=%.1fK P=%.1fkPa",
                report.temperature, report.pressure))
        else
            print("[Sensor] Failed to report: " .. tostring(err))
        end
    end

    -- Sensor main loop
    print(string.format("[Sensor] Reporting to Hub every %d seconds", REPORT_INTERVAL))

    while true do
        report_to_hub()
        sleep(REPORT_INTERVAL)
    end
end
