-- Solar Tracker Maxi MK2 By MADMAX

----------Config Below-------------------
local LowSunAngle = 75 -- low-sun threshold (deg); higher value = lower sun
local LowPower = 40    -- min efficiency (%) to keep tracking; 0 = always track
local DBWrite = 1      -- housing write mode: 0 = vertical angle, 1 = power

-- Note housing codes:
-- 1000 = no daylight sensor, 1001 = config mode,
-- 1002 = config parking, 1003 = switch active ParkMode.
local RestStacker = 0 -- 0 = normal, 1 = reset (clears memory and stops)

-- Aliases (device indices in the housing):
-- NOTE: StationeersLuaFinal does not currently expose IC10-style "find by prefab hash".
-- Set these indices to match your housing wiring.
local Switch = 1 -- d1
local Sensor = 0 -- d0

----------end of config, no edits below-------------------

local LT = ic.enums.LogicType
local LBM = ic.enums.LogicBatchMethod

local read = ic.read
local write = ic.write
local batch_read = ic.batch_read
local batch_write = ic.batch_write
-- mem_* flashes housing LED (Lua API). stack_poke = IC10 poke (no LED). stack_push/pop/peek = push/pop/peek.
local mem_read = ic.mem_read
local mem_write = ic.mem_write
local mem_clear = ic.mem_clear
local stack_set_sp = ic.stack_set_sp
local stack_pop = ic.stack_pop
local stack_poke = ic.stack_poke
local sleep = ic.sleep
local yield = ic.yield

-- Circuit housing itself (for Setting/Error writes)
local DB = ic.const.BASE_UNIT_INDEX

-- Solar panel prefab hashes (from original script)
local PANEL_HASHES = {
    -2045627372, -- SolarPanel
    -539224550,  -- SolarPanelDual
    -934345724,  -- SolarPanelReinforced
    -1545574413, -- SolarPanelDualReinforced
}

-- Switch/lever prefab hashes (from original script)
local SWITCH_HASH = 321604921
local LEVER_HASH = 1220484876

-- Chip memory layout (matches original poke/peek usage)
local ADDR_CORRECTION = 0
local ADDR_PARK_H = 1
local ADDR_PARK_V = 2

local function wrap360(x)
    return x % 360
end

local function wrap180(x)
    return ((x + 180) % 360) - 180
end

local function db_setting(v)
    write(DB, LT.Setting, v)
end

local function db_error(v)
    write(DB, LT.Error, v)
end

local function write_panels(sensorV, sensorH, correction)
    local h = wrap360(sensorH + correction)
    local v = sensorV + 90.2 -- Correction for vertical axis

    for _, panelHash in ipairs(PANEL_HASHES) do
        batch_write(panelHash, LT.Vertical, v)
        batch_write(panelHash, LT.Horizontal, h)
    end
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

-- IC10 ReadInput used move sp 7 + pop r9 in a loop (housing LED from pop). Lua uses batch_read over hashes instead;
-- same behavior, no extra stack pops (vanilla l/s and batch paths do not flash the housing memory LED).

-- state vars mirroring original registers (IC10: move sp 3 then pop r13, pop r12, pop r2)
local correction, parkH, parkV
if RestStacker ~= 0 then
    mem_clear()
    db_error(1)
    correction = 0
    parkH = 0
    parkV = 0
else
    stack_set_sp(3)
    parkV = stack_pop() or 0
    parkH = stack_pop() or 0
    correction = stack_pop() or 0
end

local r0 = 0
local r10 = parkH
local r11 = parkV
local r14 = 0
local r15 = 0

-- If correction is not set, enter config mode
if not (correction > 0) then
    r0 = 6
end

local function sunrise_azimuth(sensorV, sensorH)
    if r15 == 1 then
        return
    end

    local delta = wrap180(sensorH - r10)
    local newParkH = wrap360(r10 + (delta / 2))
    local newParkV = (r11 + sensorV) / 2

    stack_poke(ADDR_PARK_H, newParkH)
    stack_poke(ADDR_PARK_V, newParkV)

    r10 = sensorH
    r11 = sensorV
    r15 = 1

    -- Decrement config countdown (matches original SunRiseazimuth tail)
    if r0 > 1 then
        r0 = r0 - 1
        if r0 == 2 then
            r0 = 0
        end
    end
end

local function park(mode)
    parkH = mem_read(ADDR_PARK_H) or 0
    parkV = mem_read(ADDR_PARK_V) or 0

    local v = parkV
    local h = parkH

    -- override mid point parking after config
    if mode > 1 then
        v = 0
        db_setting(1002)
    end

    r15 = 0

    write_panels(v, h, correction)
end

while true do
    -- Validate Switch device type (SwitchT)
    local swPrefab = read(Switch, LT.PrefabHash)
    if swPrefab == nil or (swPrefab ~= SWITCH_HASH and swPrefab ~= LEVER_HASH) then
        db_error(1) -- wrong switch/lever type on d1
        yield()
        goto continue
    end

    -- If NOT in config mode, update r0 from Switch Open
    if r0 < 2 then
        r0 = read(Switch, LT.Open) or 0
        if r0 == 1 then
            db_setting(1003) -- signal switch active in pack db
            park(r0)
            yield()
            goto continue
        end
    end

    -- Read daylight sensor
    local sensorV = read(Sensor, LT.Vertical)
    local sensorH = read(Sensor, LT.Horizontal)
    if sensorV == nil or sensorH == nil then
        db_setting(1000)                -- signal no daylight sensor found
        write_panels(10, 0, correction) -- Face almost up
        yield()
        goto continue
    end

    -- SunRiseazimuth
    if sensorV < LowSunAngle then
        sunrise_azimuth(sensorV, sensorH)
    end

    -- WritePanel (track)
    write_panels(sensorV, sensorH, correction)

    -- ReadInput (max panel power)
    local powerPercent = read_power_percent()

    -- Re-read vertical (matches original)
    sensorV = read(Sensor, LT.Vertical) or sensorV

    -- Config mode
    if r0 >= 5 then
        db_setting(1001) -- signal config mode

        -- WaitConfig block
        if r0 < 7 or powerPercent > 97 then
            r14 = powerPercent
            sleep(4)
            r0 = r0 + 1

            if r0 <= 9 then
                goto continue
            end

            correction = wrap360(correction)
            correction = wrap360(correction + 0.6) -- leading correction for horizontal axis
            stack_poke(ADDR_CORRECTION, correction)

            r0 = 4 -- config park countdown
            goto continue
        end

        -- Adjustment block
        if powerPercent < 25 or powerPercent < r14 then
            correction = correction - 180
        else
            correction = correction + 90
        end

        r14 = powerPercent
        r0 = 5
        goto continue
    end

    -- If switch active (r0 == 1) we'd have parked already; otherwise write requested db mode
    if DBWrite == 0 then
        db_setting(sensorV)      -- write vertical angle to housing
    elseif DBWrite == 1 then
        db_setting(powerPercent) -- write power to housing
    end

    -- Tracking conditions
    if sensorV < LowSunAngle then
        yield()
        goto continue
    end

    if powerPercent > LowPower then
        yield()
        goto continue
    end

    -- Park
    park(r0)

    yield()
    ::continue::
end
