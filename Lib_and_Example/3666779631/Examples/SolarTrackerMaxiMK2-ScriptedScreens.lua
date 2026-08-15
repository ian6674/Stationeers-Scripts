-- Solar Tracker Maxi MK2 with ScriptedScreens UI
-- Based on Solar Tracker Maxi MK2 by MADMAX
--
-- DEVICE WIRING (fixed):
--   d0 = Daylight sensor
--   d1 = Switch or lever for park mode (optional)
--
-- FEATURES:
--   - Automatic sun tracking with auto-calibration
--   - Park via UI button or physical switch on d1
--   - Live power and angle display on touchscreen
--
-- Housing codes: 1000 = no sensor, 1001 = config mode,
-- 1002 = config parking, 1003 = switch active ParkMode.

----------Config-------------------
local LowSunAngle = 75 -- Low-sun threshold (deg); higher = lower sun
local LowPower = 40    -- Min power % to keep tracking; 0 = always track
local DBWrite = 1      -- Housing write: 0 = vertical angle, 1 = power %
----------End of Config------------

-- IC library shortcuts
local LT = ic.enums.LogicType
local LBM = ic.enums.LogicBatchMethod

local read = ic.read
local write = ic.write
local batch_read = ic.batch_read
local batch_write = ic.batch_write
local mem_read = ic.mem_read
local mem_write = ic.mem_write
local sleep = ic.sleep
local yield = ic.yield

-- Circuit housing (db)
local DB = ic.const.BASE_UNIT_INDEX

-- Solar panel prefab hashes (matches IC10 poke 3-6)
local PANEL_HASHES = {
    -2045627372, -- SolarPanel
    -539224550,  -- SolarPanelDual
    -934345724,  -- SolarPanelReinforced
    -1545574413, -- SolarPanelDualReinforced
}

-- Device prefab hashes
local SWITCH_HASH = 321604921
local LEVER_HASH = 1220484876
local DAYLIGHT_SENSOR_HASH = 1076425094

-- Chip memory addresses (matches IC10 poke 0-2)
local ADDR_CORRECTION = 0
local ADDR_PARK_H = 1
local ADDR_PARK_V = 2

-- Fixed device indices (no UI configuration)
local Sensor = 0 -- d0: Daylight sensor
local Switch = 1 -- d1: Park switch/lever

----------Utility Functions---------

local function wrap360(x)
    return x % 360
end

local function wrap180(x)
    return ((x + 540) % 360) - 180 -- Matches IC10 wrap logic
end

local function db_setting(v)
    write(DB, LT.Setting, v)
end

local function db_error(v)
    write(DB, LT.Error, v)
end

local function fmt1(x)
    if x == nil then return "--" end
    return string.format("%.1f", x)
end

local function fmt0(x)
    if x == nil then return "--" end
    return string.format("%.0f", x)
end

----------Panel Functions-----------

local function write_panels(vAngle, hAngle, corr)
    local h = wrap360((hAngle or 0) + (corr or 0))
    local v = (vAngle or 0) + 90.2 -- IC10: add r7 r5 90.2
    for _, panelHash in ipairs(PANEL_HASHES) do
        batch_write(panelHash, LT.Vertical, v)
        batch_write(panelHash, LT.Horizontal, h)
    end
    return v, h
end

local function read_power_percent()
    local maxRatio = 0
    for _, panelHash in ipairs(PANEL_HASHES) do
        local r = batch_read(panelHash, LT.Ratio, LBM.Maximum)
        if r ~= nil and r > maxRatio then
            maxRatio = r
        end
    end
    return maxRatio * 100
end

----------State (matches IC10 registers)-----

-- Load stored values from memory (IC10: pop r13, pop r12, pop r2)
local r2 = mem_read(ADDR_CORRECTION) or 0 -- Horizontal r2
local r12 = mem_read(ADDR_PARK_H) or 0    -- Park horizontal
local r13 = mem_read(ADDR_PARK_V) or 0    -- Park vertical

local r0 = 0                              -- Mode: 0=track, 1=switch park, 4=park countdown, 5-9=calibrating
local r10 = r12                           -- Stored horizontal for sunrise calc
local r11 = r13                           -- Stored vertical for sunrise calc
local r14 = 0                             -- Previous power reading (for calibration)
local r15 = 0                             -- Sunrise azimuth done flag

local sensorV = nil
local sensorH = nil
local powerPercent = 0
local targetV = 0
local targetH = 0
local manualPark = false

-- Start calibration if no r2 set (IC10: bgt r2 0 Start)
if not (r2 > 0) then
    r0 = 6
end

----------Sunrise Azimuth-----------

local function sunrise_azimuth(vAngle, hAngle)
    if r15 == 1 then return end

    local delta = wrap180((hAngle or 0) - r10)
    local newParkH = wrap360(r10 + (delta / 2))
    local newParkV = (r11 + (vAngle or 0)) / 2

    mem_write(ADDR_PARK_H, newParkH)
    mem_write(ADDR_PARK_V, newParkV)

    r10 = hAngle or r10
    r11 = vAngle or r11
    r15 = 1

    if r0 > 1 then
        r0 = r0 - 1
        if r0 == 2 then r0 = 0 end
    end
end

----------Park Function-------------

local function park(modeVal)
    local pv = mem_read(ADDR_PARK_V) or 0
    local ph = mem_read(ADDR_PARK_H) or 0

    local v = pv
    local h = ph

    if modeVal ~= nil and modeVal > 1 then
        v = 0
        db_setting(1002)
    end

    r15 = 0
    targetV, targetH = write_panels(v, h, r2)
end

----------UI Setup------------------

local ui = nil
local W, H = 480, 272

local ok, surface = pcall(function() return ss.ui.surface("main") end)
if ok and surface then
    ui = surface
    ss.ui.activate("main")
    local size = ui:size()
    if size then
        W = size.w or W
        H = size.h or H
    end
end

----------UI Rendering--------------

local function get_mode_text()
    if r0 >= 5 then return "CALIBRATING" end
    if manualPark then return "PARKED (MANUAL)" end
    if r0 == 1 then return "PARKED (SWITCH)" end
    if sensorV == nil then return "NO SENSOR" end
    return "TRACKING"
end

local function get_mode_color()
    if r0 >= 5 then return "#29B6F6" end               -- Blue for calibrating
    if manualPark or r0 == 1 then return "#FFB300" end -- Amber for parked
    if sensorV == nil then return "#FF5252" end        -- Red for no sensor
    return "#00E676"                                   -- Green for tracking
end

local function get_power_color(p)
    if p == nil then return "#607D8B" end
    if p >= 80 then return "#00E676" end
    if p >= 50 then return "#FFEB3B" end
    if p >= 20 then return "#FF9800" end
    return "#FF5252"
end

local function render()
    if ui == nil then return end

    ui:clear()

    -- Header background
    local header = ui:element({
        id = "hdr_bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = 60 },
        style = { bg = "#0F172A" }
    })

    -- Title
    header:element({
        id = "title",
        type = "label",
        rect = { unit = "px", x = 16, y = 20, w = 200, h = 24 },
        props = { text = "SOLAR TRACKER" },
        style = { font_size = 18, color = "#E2E8F0", align = "left" }
    })

    -- Mode status
    header:element({
        id = "mode",
        type = "label",
        rect = { unit = "px", x = 16, y = 38, w = 200, h = 18 },
        props = { text = get_mode_text() },
        style = { font_size = 13, color = get_mode_color(), align = "left" }
    })

    -- Power display
    header:element({
        id = "power",
        type = "label",
        rect = { unit = "px", x = W - 120, y = 12, w = 104, h = 36 },
        props = { text = fmt0(powerPercent) .. "%" },
        style = { font_size = 28, color = get_power_color(powerPercent), align = "right" }
    })

    -- Main content background
    ui:element({
        id = "main_bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = 64, w = W, h = H - 64 },
        style = { bg = "#111827" }
    })

    -- Sensor readings
    ui:element({
        id = "lbl_sensor",
        type = "label",
        rect = { unit = "px", x = 16, y = 74, w = 150, h = 16 },
        props = { text = "SUN SENSOR" },
        style = { font_size = 11, color = "#94A3B8", align = "left" }
    })
    ui:element({
        id = "val_sensor",
        type = "label",
        rect = { unit = "px", x = 16, y = 92, w = 200, h = 20 },
        props = { text = "V: " .. fmt1(sensorV) .. "°   H: " .. fmt1(sensorH) .. "°" },
        style = { font_size = 14, color = "#E2E8F0", align = "left" }
    })

    -- Panel target
    ui:element({
        id = "lbl_target",
        type = "label",
        rect = { unit = "px", x = 16, y = 120, w = 150, h = 16 },
        props = { text = "PANEL TARGET" },
        style = { font_size = 11, color = "#94A3B8", align = "left" }
    })
    ui:element({
        id = "val_target",
        type = "label",
        rect = { unit = "px", x = 16, y = 138, w = 200, h = 20 },
        props = { text = "V: " .. fmt1(targetV) .. "°   H: " .. fmt1(targetH) .. "°" },
        style = { font_size = 14, color = "#E2E8F0", align = "left" }
    })

    -- Correction value
    ui:element({
        id = "lbl_corr",
        type = "label",
        rect = { unit = "px", x = 16, y = 166, w = 150, h = 16 },
        props = { text = "H CORRECTION" },
        style = { font_size = 11, color = "#94A3B8", align = "left" }
    })
    ui:element({
        id = "val_corr",
        type = "label",
        rect = { unit = "px", x = 16, y = 184, w = 200, h = 20 },
        props = { text = fmt1(r2) .. "°" },
        style = { font_size = 14, color = "#E2E8F0", align = "left" }
    })

    -- Buttons on right side
    local btnW = 130
    local btnX = W - btnW - 16

    -- Park/Resume button
    local parkText = manualPark and "RESUME" or "PARK"
    local parkColor = manualPark and "#2563EB" or "#B45309"
    ui:element({
        id = "btn_park",
        type = "button",
        rect = { unit = "px", x = btnX, y = 80, w = btnW, h = 40 },
        props = { text = parkText },
        style = { bg = parkColor, text = "#FFFFFF", font_size = 14 },
        on_click = function(playerName)
            manualPark = not manualPark
            if manualPark then
                park(1)
            end
            persist_save_tracker()
            render()
        end
    })

    -- Recalibrate button
    ui:element({
        id = "btn_cal",
        type = "button",
        rect = { unit = "px", x = btnX, y = 128, w = btnW, h = 40 },
        props = { text = "RECALIBRATE" },
        style = { bg = "#0EA5E9", text = "#FFFFFF", font_size = 14 },
        on_click = function(playerName)
            r2 = 0
            mem_write(ADDR_CORRECTION, 0)
            r0 = 6
            render()
        end
    })

    -- Status/hint text at bottom
    local hint = ""
    if r0 >= 5 then
        hint = "Calibrating… please wait"
    elseif sensorV == nil then
        hint = "Connect daylight sensor to d0"
    elseif manualPark then
        hint = "Manually parked. Tap RESUME to track."
    else
        hint = "Tracking sun. Tap PARK to stop."
    end

    ui:element({
        id = "hint",
        type = "label",
        rect = { unit = "px", x = 16, y = H - 28, w = W - 32, h = 20 },
        props = { text = hint },
        style = { font_size = 12, color = "#64748B", align = "left" }
    })

    ui:commit()
end

local PERSIST_KEY = "tracker"

local function persist_save_tracker()
    ic.persist.set(PERSIST_KEY, "manualPark=" .. tostring(manualPark))
end

local function persist_restore_tracker()
    if not ic.persist.has(PERSIST_KEY) then return end
    local blob = ic.persist.get(PERSIST_KEY)
    if type(blob) ~= "string" or blob == "" then return end
    persist_apply_tracker_blob(blob)
end

local function persist_apply_tracker_blob(blob)
    if type(blob) ~= "string" or blob == "" then
        return
    end

    local function unescape_value(value)
        value = tostring(value or "")
        local out = {}
        local i = 1
        local n = #value
        while i <= n do
            local c = string.sub(value, i, i)
            if c == "\\" then
                local nextc = string.sub(value, i + 1, i + 1)
                if nextc == "n" then
                    out[#out + 1] = "\n"
                elseif nextc == "r" then
                    out[#out + 1] = "\r"
                elseif nextc == "=" then
                    out[#out + 1] = "="
                elseif nextc == "\\" then
                    out[#out + 1] = "\\"
                elseif nextc == "" then
                    out[#out + 1] = "\\"
                else
                    out[#out + 1] = nextc
                end
                i = i + 2
            else
                out[#out + 1] = c
                i = i + 1
            end
        end
        return table.concat(out)
    end

    for line in string.gmatch(blob, "[^\n]+") do
        local k, v = string.match(line, "^(.-)=(.*)$")
        if k ~= nil and v ~= nil then
            if k == "manualPark" then
                manualPark = (unescape_value(v) == "true")
            end
        end
    end

    if manualPark then
        park(1)
    end

    if type(render) == "function" then
        pcall(render)
    end
end

persist_restore_tracker()

----------Main Loop-----------------

-- Initial render before loop starts
render()

local tickCount = 0

while true do
    tickCount = tickCount + 1

    -- Check physical switch (if present)
    local swPrefab = read(Switch, LT.PrefabHash)
    local hasSwitch = (swPrefab == SWITCH_HASH or swPrefab == LEVER_HASH)

    if hasSwitch and r0 < 2 and not manualPark then
        local swState = read(Switch, LT.Open) or 0
        if swState == 1 then
            db_setting(1003)
            park(1)
            if tickCount % 10 == 0 then render() end
            yield()
            goto continue
        end
    end

    -- Read daylight sensor
    sensorV = read(Sensor, LT.Vertical)
    sensorH = read(Sensor, LT.Horizontal)

    if sensorV == nil or sensorH == nil then
        db_setting(1000)
        targetV, targetH = write_panels(10, 0, r2)
        if tickCount % 10 == 0 then render() end
        yield()
        goto continue
    end

    -- Manual park mode
    if manualPark then
        if tickCount % 10 == 0 then render() end
        yield()
        goto continue
    end

    -- Sunrise azimuth detection
    if sensorV < LowSunAngle then
        sunrise_azimuth(sensorV, sensorH)
    end

    -- Track sun
    targetV, targetH = write_panels(sensorV, sensorH, r2)

    -- Read power
    powerPercent = read_power_percent()

    -- Calibration mode
    if r0 >= 5 then
        db_setting(1001)

        if r0 < 7 or powerPercent > 97 then
            r14 = powerPercent
            sleep(4)
            r0 = r0 + 1

            if r0 <= 9 then
                if tickCount % 5 == 0 then render() end
                goto continue
            end

            r2 = wrap360(r2 + 0.6)
            mem_write(ADDR_CORRECTION, r2)
            r0 = 4
            if tickCount % 5 == 0 then render() end
            goto continue
        end

        if powerPercent < 25 or powerPercent < r14 then
            r2 = r2 - 180
        else
            r2 = r2 + 90
        end

        r14 = powerPercent
        r0 = 5
        if tickCount % 5 == 0 then render() end
        goto continue
    end

    -- Write to housing
    if DBWrite == 0 then
        db_setting(sensorV)
    else
        db_setting(powerPercent)
    end

    -- Check if should park (low power/sun)
    if sensorV >= LowSunAngle and powerPercent <= LowPower then
        park(r0)
    end

    -- Update UI periodically
    if tickCount % 10 == 0 then
        render()
    end

    yield()
    ::continue::
end
