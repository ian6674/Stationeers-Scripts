-- PIAC - Power Info and Control
-- Real-time power generation dashboard with wind, solar, and generator monitoring.
--
-- FEATURES:
--   - Wind turbine power generation monitoring
--   - Solar panel charge monitoring
--   - Solid fuel generator status with on/off toggle buttons
--   - Gas fuel generator power generation monitoring
--   - Linechart history visualization for all sources
--   - Settings tab with device dropdowns
--   - Auto ON/OFF generator control based on thresholds
--   - Energy usage chart by cable analyzer data
--   - Solar Tracker Maxi MK1 rebuilt into lua with configurable settings

-- ==================== SURFACES & VIEW ====================

local surfaces = {
    overview = ss.ui.surface("overview"),
    settings = ss.ui.surface("settings"),
}
local s    = surfaces.overview
local view = "overview"

local W, H = 480, 272
local size = ss.ui.surface("overview"):size()
if size then
    W = size.w or W
    H = size.h or H
end

local elapsed = 0
local currenttime = 0
local LIVE_REFRESH_TICKS = 6
local handles = {
    view = nil,
    header = {},
    nav = {},
    footer = {},
    overview = {},
}

-- ==================== CONSTANTS ====================

local LT              = ic.enums.LogicType
local LST             = ic.enums.LogicSlotType
local LBM             = ic.enums.LogicBatchMethod
local hash            = ic.hash
local batch_read      = ic.batch_read
local batch_write     = ic.batch_write
local batch_read_name = ic.batch_read_name
local batch_write_name = ic.batch_write_name
local batch_read_slot = ic.batch_read_slot

-- ==================== PERSISTENT MEMORY MAP ====================



local MEM_SOLID_FORCE   = 0
local MEM_GAS_FORCE     = 1
local MEM_SETTINGS_INIT = 2
local MEM_WIND_MAX_POWER = 3
local MEM_AUTO_ON_WIND   = 4
local MEM_AUTO_ON_SOLAR  = 5
local MEM_AUTO_ON_BAT    = 6
local MEM_AUTO_OFF_REN   = 7
local MEM_AUTO_OFF_BAT   = 8
local MEM_HISTORY_MAX    = 9

local MEM_PREFAB_WIND    = 10
local MEM_PREFAB_SOLAR   = 12
local MEM_PREFAB_SOLID   = 14
local MEM_PREFAB_GAS     = 16
local MEM_PREFAB_PRESREG = 18
local MEM_NAMEHASH_PRESREG = 19
local MEM_PREFAB_BAT     = 20
local MEM_PREFAB_CABLE   = 22
local MEM_NAMEHASH_CABLE = 23

local MEM_MK1_PANEL_PORT  = 32
local MEM_MK1_SENSOR_PORT = 33
local MEM_MK1_PMODE       = 34
local MEM_MK1_LOW_OUTPUT  = 35
local MEM_MK1_LOW_SUN     = 36
local MEM_PREFAB_DAYLIGHT    = 37
local MEM_NAMEHASH_DAYLIGHT  = 38
local MEM_MK1_ENABLED         = 39
local MEM_REFRESH_TICKS       = 40

-- ==================== DEVICE PREFAB FILTER LISTS ====================

local wind_prefabs = {
    [hash("StructureWindTurbine")] = true,
    [hash("StructureUprightWindTurbine")] = true,
}
local solar_prefabs = {
    [hash("StructureSolarPanelReinforced")] = true,
    [hash("StructureSolarPanelFlatReinforced")] = true,
    [hash("StructureSolarPanelDualReinforced")] = true,
    [hash("StructureSolarPanel1x5ReinforcedSingle")] = true,
    [hash("StructureSolarPanel")]           = true,
    [hash("StructureSolarPanelFlat")] = true,
    [hash("StructureSolarPanelDual")] = true,
    [hash("StructureSolarPanel1x5Reinforced")] = true,
}
local solid_prefabs = {
    [hash("StructureSolidFuelGenerator")] = true,
}
local gas_prefabs = {
    [hash("StructureGasGenerator")] = true,
}
local presreg_prefabs = {
    [hash("StructurePressureRegulator")] = true,
    [hash("StructurePressureRegulatorMirrored")] = true,
}
local battery_prefabs = {
    [hash("StationBatteryNuclear")] = true,
    [hash("StructureBattery")] = true,
    [hash("StructureBatteryLarge")] = true,
}
local cable_prefabs = {
    [hash("StructureCableAnalysizer")] = true,
}

local daylight_sensor_prefabs = {
    [hash("StructureDaylightSensor")] = true,
}

-- ==================== STATE ====================

local windPower    = 0
local windCount    = 0
local windMaxpower = 0
local windMaxPowerPerTurbine = 5000
local windHistory  = {}

local solarCharge    = 0
local solarMaxCharge = 0
local solarPct       = 0
local solarCount     = 0
local solarHistory   = {}

local solidCount      = 0
local solidOnCount    = 0
local solidPower      = 0
local solidForceState = nil
local solidHistory    = {}

local gasCount      = 0
local gasOnCount    = 0
local gasPower      = 0
local gasPct        = 0
local gasForceState = nil
local gasHistory    = {}

local presregCount  = 0
local presregSetting = 0
local presregHistory = {}

local batCharge  = 0
local batMax     = 0
local batPct     = 0
local batHistory = {}

local cablePower   = 0
local cableHistory = {}

local mk1_PanelPortPos  = 2
local mk1_SensorPortPos = 2
local mk1_pMode         = 0
local mk1_LowOutPut     = 40
local mk1_LowSunAngle   = 75
local mk1_Enabled       = true
local settings_mk1_panel_port_input  = "2"
local settings_mk1_sensor_port_input = "2"
local settings_mk1_pmode_input       = "0"
local settings_mk1_low_output_input  = "40"
local settings_mk1_low_sun_input     = "75"

local settings_dropdown_selected = {
    wind   = 0,
    solar  = 0,
    solid  = 0,
    gas    = 0,
    presreg = 0,
    bat    = 0,
    cable  = 0,
    daylight = 0,
}
local settings_dropdown_open = {
    wind   = "false",
    solar  = "false",
    solid  = "false",
    gas    = "false",
    presreg = "false",
    bat    = "false",
    cable  = "false",
    daylight = "false",
}
local settings_wind_max_power_input = "5000"
local historyChartMax = 100
local settings_history_max_input = "100"
local settings_subtab = "devices"

local auto_on_wind_pct   = 5
local auto_on_solar_pct  = 5
local auto_on_bat_pct    = 10
local auto_off_ren_pct   = 10
local auto_off_bat_pct   = 15

local settings_auto_on_wind_input   = "5"
local settings_auto_on_solar_input  = "5"
local settings_auto_on_bat_input    = "10"
local settings_auto_off_ren_input   = "10"
local settings_auto_off_bat_input   = "15"
local HISTORY_LEN = 50

for i = 1, HISTORY_LEN do
    windHistory[i]  = 0
    solarHistory[i] = 0
    solidHistory[i] = 0
    gasHistory[i]   = 0
    presregHistory[i] = 0
    batHistory[i]   = 0
    cableHistory[i] = 0
end

-- ==================== COLORS ====================
local C = {
    bg          = "#0A0E1A",
    header      = "#0C1220",
    panel       = "#0F1628",
    panel_light = "#151D30",
    divider     = "#1A2540",
    text        = "#E2E8F0",
    text_dim    = "#64748B",
    text_muted  = "#475569",
    accent      = "#38BDF8",
    green       = "#22C55E",
    yellow      = "#EAB308",
    orange      = "#F97316",
    red         = "#EF4444",
    blue        = "#3B82F6",
    gen_on      = "#22C55E",
    gen_off     = "#475569",
    btn_on      = "#166534",
    btn_off     = "#3F1515",
    btn_auto    = "#1E3A5F",
}

-- ==================== MEMORY HELPERS ====================

local function write(address, value)
    mem_write(address, value)
end

local function read(address)
    return mem_read(address) or 0
end

local function selected_prefab(mem_slot)
    local prefab = tonumber(read(mem_slot)) or 0
    if prefab == 0 then return nil end
    return prefab
end

local function selected_namehash(mem_slot)
    local namehash = tonumber(read(mem_slot)) or 0
    if namehash == 0 then return nil end
    return namehash
end

local function selected_hash_pair(prefab_mem_slot, namehash_mem_slot)
    local prefab = selected_prefab(prefab_mem_slot)
    local namehash = selected_namehash(namehash_mem_slot)
    if prefab == nil or namehash == nil then return nil, nil end
    return prefab, namehash
end

-- ==================== HELPERS ====================

local function pct_color(pct)
    if pct >= 70 then return C.green end
    if pct >= 40 then return C.yellow end
    if pct >= 15 then return C.orange end
    return C.red
end

local function status_text(pct)
    if pct >= 80 then return "OPTIMAL" end
    if pct >= 50 then return "NOMINAL" end
    if pct >= 20 then return "LOW" end
    return "CRITICAL"
end

local function status_color(pct)
    if pct >= 80 then return C.green end
    if pct >= 50 then return C.accent end
    if pct >= 20 then return C.orange end
    return C.red
end

local function fmt(v, d)
    if v == nil then return "--" end
    d = d or 1
    return string.format("%." .. d .. "f", v)
end

local function fmt_power(watts)
    if watts == nil then return "--" end
    if watts >= 1000 then return fmt(watts / 1000, 1) .. " kW" end
    return fmt(watts, 0) .. " W"
end

local function fmt_energy(joules)
    if joules == nil or joules ~= joules then return "--" end
    if joules >= 1000000 then return fmt(joules / 1000000, 1) .. " MJ" end
    if joules >= 1000 then return fmt(joules / 1000, 1) .. " kJ" end
    return fmt(joules, 0) .. " J"
end

local function push_history(buf, val)
    table.remove(buf, 1)
    buf[#buf + 1] = val
end

local function reset_handles()
    handles = {
        view = nil,
        header = {},
        nav = {},
        footer = {},
        overview = {},
    }
end

-- ==================== INITIALIZATION ====================

local function initialize_settings()
    if read(MEM_SETTINGS_INIT) == 1 then
        windMaxPowerPerTurbine = tonumber(read(MEM_WIND_MAX_POWER)) or 5000
        settings_wind_max_power_input = tostring(windMaxPowerPerTurbine)
        local savedHistoryMax = tonumber(read(MEM_HISTORY_MAX)) or 0
        if savedHistoryMax <= 0 then
            savedHistoryMax = 100
            write(MEM_HISTORY_MAX, savedHistoryMax)
        end
        historyChartMax = savedHistoryMax
        if historyChartMax < 10 then historyChartMax = 10 end
        settings_history_max_input = tostring(historyChartMax)
        auto_on_wind_pct  = tonumber(read(MEM_AUTO_ON_WIND))  or 5
        auto_on_solar_pct = tonumber(read(MEM_AUTO_ON_SOLAR)) or 5
        auto_on_bat_pct   = tonumber(read(MEM_AUTO_ON_BAT))   or 10
        auto_off_ren_pct  = tonumber(read(MEM_AUTO_OFF_REN))  or 10
        auto_off_bat_pct  = tonumber(read(MEM_AUTO_OFF_BAT))  or 15
        settings_auto_on_wind_input  = tostring(auto_on_wind_pct)
        settings_auto_on_solar_input = tostring(auto_on_solar_pct)
        settings_auto_on_bat_input   = tostring(auto_on_bat_pct)
        settings_auto_off_ren_input  = tostring(auto_off_ren_pct)
        settings_auto_off_bat_input  = tostring(auto_off_bat_pct)
        mk1_PanelPortPos  = tonumber(read(MEM_MK1_PANEL_PORT))  or 2
        mk1_SensorPortPos = tonumber(read(MEM_MK1_SENSOR_PORT)) or 2
        mk1_pMode         = tonumber(read(MEM_MK1_PMODE))        or 0
        mk1_LowOutPut     = tonumber(read(MEM_MK1_LOW_OUTPUT))   or 40
        mk1_LowSunAngle   = tonumber(read(MEM_MK1_LOW_SUN))      or 75
        mk1_Enabled       = (tonumber(read(MEM_MK1_ENABLED)) or 1) ~= 0
        settings_mk1_panel_port_input  = tostring(mk1_PanelPortPos)
        settings_mk1_sensor_port_input = tostring(mk1_SensorPortPos)
        settings_mk1_pmode_input       = tostring(mk1_pMode)
        settings_mk1_low_output_input  = tostring(mk1_LowOutPut)
        settings_mk1_low_sun_input     = tostring(mk1_LowSunAngle)
        local stored_ticks = tonumber(read(MEM_REFRESH_TICKS)) or 0
        if stored_ticks >= 1 then
            LIVE_REFRESH_TICKS = math.min(120, stored_ticks)
        end
        return
    end
    write(MEM_SOLID_FORCE, 0)
    write(MEM_GAS_FORCE, 0)
    write(MEM_WIND_MAX_POWER, 5000)
    write(MEM_AUTO_ON_WIND,  5)
    write(MEM_AUTO_ON_SOLAR, 5)
    write(MEM_AUTO_ON_BAT,   10)
    write(MEM_AUTO_OFF_REN,  10)
    write(MEM_AUTO_OFF_BAT,  15)
    write(MEM_HISTORY_MAX,   100)
    write(MEM_SETTINGS_INIT, 1)
    write(MEM_MK1_PANEL_PORT,  2)
    write(MEM_MK1_SENSOR_PORT, 2)
    write(MEM_MK1_PMODE,       0)
    write(MEM_MK1_LOW_OUTPUT,  40)
    write(MEM_MK1_LOW_SUN,     75)
    write(MEM_MK1_ENABLED,     1)
    write(MEM_REFRESH_TICKS, LIVE_REFRESH_TICKS)
    windMaxPowerPerTurbine = 5000
    settings_wind_max_power_input = "5000"
    historyChartMax = 100
    settings_history_max_input = "100"
end

local function load_force_states()
    local sv = read(MEM_SOLID_FORCE)
    if sv == 1 then solidForceState = true
    elseif sv == 2 then solidForceState = false
    else solidForceState = nil end

    local gv = read(MEM_GAS_FORCE)
    if gv == 1 then gasForceState = true
    elseif gv == 2 then gasForceState = false
    else gasForceState = nil end
end

local function save_force_states()
    if solidForceState == true then write(MEM_SOLID_FORCE, 1)
    elseif solidForceState == false then write(MEM_SOLID_FORCE, 2)
    else write(MEM_SOLID_FORCE, 0) end

    if gasForceState == true then write(MEM_GAS_FORCE, 1)
    elseif gasForceState == false then write(MEM_GAS_FORCE, 2)
    else write(MEM_GAS_FORCE, 0) end
end

-- ==================== DATA COLLECTION ====================

local function read_wind()
    local prefab = selected_prefab(MEM_PREFAB_WIND)
    if prefab == nil then
        windPower = 0
        windCount = 0
        windMaxpower = 0
        push_history(windHistory, 0)
        return
    end
    local sumPower, avgPower
    sumPower = batch_read(prefab, LT.PowerGeneration, LBM.Sum)
    avgPower = batch_read(prefab, LT.PowerGeneration, LBM.Average)

    if sumPower ~= nil and avgPower ~= nil and avgPower > 0 then
        windPower    = sumPower
        windCount    = math.floor((sumPower / avgPower) + 0.5)
        windMaxpower = windCount * windMaxPowerPerTurbine
        push_history(windHistory, math.min(100, (windPower / windMaxpower) * 100))
    else
        windPower    = 0
        windCount    = 0
        windMaxpower = 0
        push_history(windHistory, 0)
    end
end

local function read_solar()
    local prefab = selected_prefab(MEM_PREFAB_SOLAR)
    if prefab == nil then
        solarCount = 0
        solarCharge = 0
        solarMaxCharge = 0
        solarPct = 0
        push_history(solarHistory, 0)
        return
    end
    local avgRatio, sumC, sumM
    avgRatio = batch_read(prefab, LT.Ratio,   LBM.Average)
    sumC     = batch_read(prefab, LT.Charge,  LBM.Sum)
    sumM     = batch_read(prefab, LT.Maximum, LBM.Sum)

    local count   = 0
    local charge  = 0
    local maxChg  = 0

    if avgRatio ~= nil then
        charge = sumC or 0
        maxChg = sumM or 0

        if sumC ~= nil and sumC > 0 then
            local avgC = batch_read(prefab, LT.Charge, LBM.Average)
            if avgC ~= nil and avgC > 0 then
                count = math.floor((sumC / avgC) + 0.5)
            end
        elseif sumM ~= nil and sumM > 0 then
            local avgM = batch_read(prefab, LT.Maximum, LBM.Average)
            if avgM ~= nil and avgM > 0 then
                count = math.floor((sumM / avgM) + 0.5)
            end
        end
    end

    solarCount     = count
    solarCharge    = charge
    solarMaxCharge = maxChg
    solarPct       = maxChg > 0 and (charge / maxChg) * 100 or 0
    push_history(solarHistory, solarPct)
end

local function read_solid_generators()
    local prefab = selected_prefab(MEM_PREFAB_SOLID)
    if prefab == nil then
        solidCount = 0
        solidOnCount = 0
        solidPower = 0
        push_history(solidHistory, 0)
        return
    end
    local sumOn, sumHash, avgHash, power
    sumOn   = batch_read(prefab, LT.On,              LBM.Sum)
    sumHash = batch_read(prefab, LT.PrefabHash,      LBM.Sum)
    avgHash = batch_read(prefab, LT.PrefabHash,      LBM.Average)
    power   = batch_read(prefab, LT.PowerGeneration, LBM.Sum)

    local onCount = 0
    local total   = 0
    local pwr     = 0

    if sumOn ~= nil then
        onCount = math.floor(sumOn + 0.5)
        if sumHash ~= nil and avgHash ~= nil and avgHash ~= 0 then
            total = math.floor(math.abs(sumHash / avgHash) + 0.5)
        end
        if total < onCount then total = onCount end
        if total < 1 and onCount > 0 then total = 1 end
        pwr = power or 0
    end

    if total ~= total or total == nil then total = 0 end
    if onCount ~= onCount or onCount == nil then onCount = 0 end
    if pwr ~= pwr or pwr == nil then pwr = 0 end

    solidCount   = total
    solidOnCount = onCount
    solidPower   = pwr
    push_history(solidHistory, math.min(historyChartMax, solidPower / 1000))
end

local function read_gas_generators()
    local prefab = selected_prefab(MEM_PREFAB_GAS)
    if prefab == nil then
        gasCount = 0
        gasOnCount = 0
        gasPower = 0
        gasPct = 0
        push_history(gasHistory, 0)
        return
    end
    local sumOn, sumHash, avgHash, power, gaspress
    sumOn    = batch_read(prefab, LT.On,              LBM.Sum)
    sumHash  = batch_read(prefab, LT.PrefabHash,      LBM.Sum)
    avgHash  = batch_read(prefab, LT.PrefabHash,      LBM.Average)
    power    = batch_read(prefab, LT.PowerGeneration, LBM.Sum)
    gaspress = batch_read(prefab, LT.Pressure,        LBM.Sum)

    local onCount = 0
    local total   = 0
    local pwr     = 0

    if sumOn ~= nil then
        onCount = math.floor(sumOn + 0.5)
        if sumHash ~= nil and avgHash ~= nil and avgHash ~= 0 then
            total = math.floor(math.abs(sumHash / avgHash) + 0.5)
        end
        if total < onCount then total = onCount end
        if total < 1 and onCount > 0 then total = 1 end
        pwr = power or 0
    end

    gasCount   = total
    gasOnCount = onCount
    gasPower   = pwr
    gasPct     = gaspress or 0
    push_history(gasHistory, math.min(historyChartMax, gasPower / 1000))
end

local function read_presreg()
    local named_prefab, named_namehash = selected_hash_pair(MEM_PREFAB_PRESREG, MEM_NAMEHASH_PRESREG)
    if named_prefab == nil then
        presregCount = 0
        presregSetting = 0
        push_history(presregHistory, 0)
        return
    end

    local sumOn
    local setting
    local total = 0

    sumOn = batch_read_name(named_prefab, named_namehash, LT.On, LBM.Average)
    setting = batch_read_name(named_prefab, named_namehash, LT.Setting, LBM.Average)
    if sumOn ~= nil then
        total = 1
    end

    presregCount = total
    if setting ~= nil and setting == setting then
        presregSetting = setting
    else
        presregSetting = 0
    end
    push_history(presregHistory, math.min(100, presregCount))
end

local function read_battery()
    local prefab = selected_prefab(MEM_PREFAB_BAT)
    if prefab == nil then
        batCharge = 0
        batMax = 0
        batPct = 0
        push_history(batHistory, 0)
        return
    end
    local chargeAvg = batch_read(prefab, LT.Charge, LBM.Average)
    local maxcapAvg = batch_read(prefab, LT.Maximum, LBM.Average)
    local chargeSum = batch_read(prefab, LT.Charge, LBM.Sum)
    local maxcapSum = batch_read(prefab, LT.Maximum, LBM.Sum)

    if chargeAvg ~= nil and maxcapAvg ~= nil then
        batCharge = chargeSum or 0
        batMax = maxcapSum or 0
        batPct = maxcapAvg > 0 and (chargeAvg / maxcapAvg) * 100 or 0
    else
        batCharge = 0
        batMax = 0
        batPct = 0
    end

    push_history(batHistory, batPct)
end

local function read_cable_analyzer()
    local named_prefab, named_namehash = selected_hash_pair(MEM_PREFAB_CABLE, MEM_NAMEHASH_CABLE)
    if named_prefab == nil then
        cablePower = 0
        push_history(cableHistory, 0)
        return
    end

    local actual = batch_read_name(named_prefab, named_namehash, LT.PowerActual, LBM.Average)
    if actual ~= nil and actual == actual then
        cablePower = actual
    else
        cablePower = 0
    end

    push_history(cableHistory, math.min(historyChartMax, math.max(0, cablePower / 1000)))
end

local autoGenActive = false

--local function update_auto_gen_state()
--    local wPct = windCount > 0 and math.min(100, (windPower / windMaxpower) * 100) or 0
--    if not autoGenActive then
--        if (wPct < auto_on_wind_pct or solarPct < auto_on_solar_pct) and batPct < auto_on_bat_pct then
--            autoGenActive = true
--        end
--    else
--       if (wPct > auto_off_ren_pct or solarPct > auto_off_ren_pct) and batPct > auto_off_bat_pct then
--            autoGenActive = false
--        end
--    end
--end
local function update_auto_gen_state()
    local wPct = windCount > 0 and math.min(100, (windPower / windMaxpower) * 100) or 0
    if not autoGenActive then
        if (wPct + solarPct < auto_on_wind_pct + auto_on_solar_pct) and batPct < auto_on_bat_pct then
            autoGenActive = true
        end
    else
        if (wPct + solarPct > auto_off_ren_pct) or batPct > auto_off_bat_pct then
            autoGenActive = false
        end
    end
end

local function apply_solid_override()
    local prefab = selected_prefab(MEM_PREFAB_SOLID)
    if prefab == nil then return end
    local val
    if solidForceState == true then
        val = 1
    elseif solidForceState == false then
        val = 0
    else
        val = autoGenActive and 1 or 0
    end
    batch_write(prefab, LT.On, val)
end

local last_gas_on = nil
local function apply_gas_override()
    local prefab = selected_prefab(MEM_PREFAB_GAS)
    if prefab == nil then return end
    local val
    if gasForceState == true then
        val = 1
    elseif gasForceState == false then
        val = 0
    else
        val = autoGenActive and 1 or 0
    end
    if last_gas_on ~= val then
        batch_write(prefab, LT.On, val)
        last_gas_on = val
    end
end

local function adjust_presreg_setting(delta)
    local named_prefab, named_namehash = selected_hash_pair(MEM_PREFAB_PRESREG, MEM_NAMEHASH_PRESREG)
    if named_prefab == nil then return end

    local current = batch_read_name(named_prefab, named_namehash, LT.Setting, LBM.Average)
    if current == nil or current ~= current then
        current = 0
    end

    local next_setting = current + delta
    if next_setting < 0 then
        next_setting = 0
    end

    batch_write_name(named_prefab, named_namehash, LT.Setting, next_setting)
    presregSetting = next_setting
end

-- ==================== SOLAR TRACKER ====================

local DEBUG_LOG_ENABLED = false

local function log_action(message)
    if not DEBUG_LOG_ENABLED then return end
    local gt  = util.game_time()
    local gtH = math.floor(gt / 3600)
    local gtM = math.floor((gt % 3600) / 60)
    local gtS = math.floor((gt % 3600) % 60)
    print("[PIAC] H" .. gtH .. " : M" .. gtM .. " : S" .. gtS .. " | " .. tostring(message))
end

local function wrap_degrees(value)
    local v = (tonumber(value) or 0) % 360
    if v < 0 then v = v + 360 end
    return v
end

local function device_list_safe()
    local ok, devices = pcall(device_list)
    if not ok or type(devices) ~= "table" then return {} end
    return devices
end

local function mk1_find_daylight_sensor()
    local sel_ph, sel_nh = selected_hash_pair(MEM_PREFAB_DAYLIGHT, MEM_NAMEHASH_DAYLIGHT)
    if sel_ph == nil then return nil end
    return { prefab_hash = sel_ph, name_hash = sel_nh }
end

local function mk1_write_panels(horizontal, vertical)
    local h = wrap_degrees(horizontal)
    local v = math.max(0, math.min(180, tonumber(vertical) or 0))
    local sel = selected_prefab(MEM_PREFAB_SOLAR)
    if sel == nil then return false end
    batch_write(sel, LT.Horizontal, h)
    batch_write(sel, LT.Vertical,   v)
    return true
end

local function mk1_max_panel_output_pct()
    local max_ratio = 0
    local sel = selected_prefab(MEM_PREFAB_SOLAR)
    if sel == nil then return 0 end
    local ratio = batch_read(sel, LT.Ratio, LBM.Average)
    if ratio ~= nil and ratio == ratio then max_ratio = ratio end
    return math.floor(max_ratio * 100 + 0.5)
end

local function mk1_park_panels()
    mk1_write_panels(0 - (mk1_PanelPortPos * 90), 165)
end

local function mk1_face_sensor_port()
    local chSensorA = mk1_SensorPortPos * (-90)
    local cPanelA   = mk1_PanelPortPos  * 90
    mk1_write_panels(chSensorA - cPanelA, 165)
end

local function mk1_track_sun(sensor)
    local cPanelA   = mk1_PanelPortPos  * 90
    local chSensorA = mk1_SensorPortPos * (-90)
    local cvSensorA = 90
    local sensor_h  = batch_read_name(sensor.prefab_hash, sensor.name_hash, LT.Horizontal, LBM.Average) or 0
    local sensor_v  = batch_read_name(sensor.prefab_hash, sensor.name_hash, LT.Vertical,   LBM.Average) or 10

    local hSolarA = wrap_degrees(sensor_h + chSensorA + cPanelA)
    local vSolarA = sensor_v + cvSensorA

    -- North(0) or South(2) facing panel ports need +180° correction
    if mk1_PanelPortPos == 0 or mk1_PanelPortPos == 2 then
        hSolarA = wrap_degrees(hSolarA + 180)
    end

    if not mk1_write_panels(hSolarA, vSolarA) then return end

    if sensor_v <= mk1_LowSunAngle then return end

    local output_pct = mk1_max_panel_output_pct()
    if output_pct < mk1_LowOutPut then
        mk1_park_panels()
        log_action("ST-MK1 dusk - parking (" .. output_pct .. "% < " .. mk1_LowOutPut .. "%)")
    end
end

local function tick_solar_mk1()
    if not mk1_Enabled then return end
    if selected_prefab(MEM_PREFAB_SOLAR) == nil then return end

    local sensor = mk1_find_daylight_sensor()
    if sensor == nil then return end

    if mk1_pMode == 2 then
        mk1_face_sensor_port()
        return
    end

    if mk1_pMode == 1 then
        mk1_park_panels()
        return
    end

    mk1_track_sun(sensor)
end

-- ==================== SETTINGS DEVICE CACHE ====================

local piac_filter_wind     = function(d) return wind_prefabs[   tonumber(d and d.prefab_hash) or 0] == true end
local piac_filter_solar    = function(d) return solar_prefabs[  tonumber(d and d.prefab_hash) or 0] == true end
local piac_filter_solid    = function(d) return solid_prefabs[  tonumber(d and d.prefab_hash) or 0] == true end
local piac_filter_gas      = function(d) return gas_prefabs[    tonumber(d and d.prefab_hash) or 0] == true end
local piac_filter_presreg  = function(d) return presreg_prefabs[tonumber(d and d.prefab_hash) or 0] == true end
local piac_filter_bat      = function(d) return battery_prefabs[tonumber(d and d.prefab_hash) or 0] == true end
local piac_filter_cable    = function(d) return cable_prefabs[  tonumber(d and d.prefab_hash) or 0] == true end
local piac_filter_daylight = function(d) return daylight_sensor_prefabs[tonumber(d and d.prefab_hash) or 0] == true end

local function build_piac_device_options(devs, predicate)
    local options    = { "Select" }
    local candidates = {}
    for i, dev in ipairs(devs) do
        if predicate == nil or predicate(dev) then
            local label = tostring((dev and dev.display_name) or ("Device " .. tostring(i)))
            label = label:gsub("|", "/")
            table.insert(options, label)
            table.insert(candidates, dev)
        end
    end
    if #candidates == 0 then
        table.insert(options, "No devices found")
    end
    return options, candidates
end

local function piac_selected_index_from_saved(candidates, mem_prefab, mem_namehash)
    local saved_prefab = tonumber(read(mem_prefab)) or 0
    local saved_namehash = mem_namehash ~= nil and (tonumber(read(mem_namehash)) or 0) or 0
    if saved_prefab == 0 then return 0 end
    for i, dev in ipairs(candidates) do
        local ph = tonumber(dev and dev.prefab_hash) or 0
        local nh = tonumber(dev and dev.name_hash) or 0
        if ph == saved_prefab and (mem_namehash == nil or nh == saved_namehash) then
            return i
        end
    end
    return 0
end

local function piac_write_selected_device(index, candidates, mem_prefab, mem_namehash)
    if index == 0 then
        write(mem_prefab, 0)
        if mem_namehash ~= nil then write(mem_namehash, 0) end
        return
    end
    local picked = candidates[index]
    if picked ~= nil then
        write(mem_prefab, tonumber(picked.prefab_hash) or 0)
        if mem_namehash ~= nil then write(mem_namehash, tonumber(picked.name_hash) or 0) end
    end
end

local piac_dropdown_defs = {
    { id = "cfg_wind",    key = "wind",    label = "Wind Turbines",      mem_prefab = MEM_PREFAB_WIND,    filter = piac_filter_wind    },
    { id = "cfg_solar",   key = "solar",   label = "Solar Panels",       mem_prefab = MEM_PREFAB_SOLAR,   filter = piac_filter_solar   },
    { id = "cfg_solid",   key = "solid",   label = "Solid Generators",   mem_prefab = MEM_PREFAB_SOLID,   filter = piac_filter_solid   },
    { id = "cfg_gas",     key = "gas",     label = "Gas Generators",     mem_prefab = MEM_PREFAB_GAS,     filter = piac_filter_gas     },
    { id = "cfg_presreg", key = "presreg", label = "Pressure Regulators",mem_prefab = MEM_PREFAB_PRESREG, mem_namehash = MEM_NAMEHASH_PRESREG, filter = piac_filter_presreg },
    { id = "cfg_bat",     key = "bat",     label = "Batteries",          mem_prefab = MEM_PREFAB_BAT,     filter = piac_filter_bat     },
    { id = "cfg_cable",   key = "cable",   label = "Cable Analyzer",     mem_prefab = MEM_PREFAB_CABLE,   mem_namehash = MEM_NAMEHASH_CABLE,    filter = piac_filter_cable   },
    { id = "cfg_daylight",key = "daylight",label = "Daylight Sensor",    mem_prefab = MEM_PREFAB_DAYLIGHT, mem_namehash = MEM_NAMEHASH_DAYLIGHT, filter = piac_filter_daylight },
}

local function populate_piac_dropdown_cache()
    local devs = device_list_safe()
    cached_piac_dropdowns = {}
    for _, def in ipairs(piac_dropdown_defs) do
        local opts, cands = build_piac_device_options(devs, def.filter)
        local sel = piac_selected_index_from_saved(cands, def.mem_prefab, def.mem_namehash)
        cached_piac_dropdowns[def.key] = { opts = opts, candidates = cands, selected = sel }
        settings_dropdown_selected[def.key] = sel
    end
end

-- ==================== RENDER HELPERS ====================

local dashboard_render
local set_view

local function render_header()
    local header = s:element({
        id = "header_bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = 30 },
        style = { bg = C.header }
    })
    header:element({
        id = "title",
        type = "label",
        rect = { unit = "px", x = 14, y = 6, w = 300, h = 20 },
        props = { text = "PIAC - Power Info and Control" },
        style = { font_size = 14, color = C.text, align = "left" }
    })

    local statTxt = status_text(solarPct)
    local statCol = status_color(solarPct)
    handles.header.status_dot = header:element({
        id = "status_dot",
        type = "panel",
        rect = { unit = "px", x = W - 90, y = 12, w = 6, h = 6 },
        style = { bg = statCol }
    })
    handles.header.status_label = header:element({
        id = "status_label",
        type = "label",
        rect = { unit = "px", x = W - 82, y = 7, w = 76, h = 18 },
        props = { text = statTxt },
        style = { font_size = 11, color = statCol, align = "left" }
    })
end

local function render_nav_tabs()
    local tabs = {
        { id = "nav_overview", text = "OVERVIEW", view = "overview" },
        { id = "nav_settings", text = "SETTINGS", view = "settings" },
    }
    local tab_w = math.floor((W - 10) / #tabs)

    for i, tab in ipairs(tabs) do
        local is_active = (view == tab.view)
        handles.nav[tab.view] = s:element({
            id = tab.id,
            type = "button",
            rect = { unit = "px", x = (i - 1) * tab_w + 5, y = 34, w = tab_w - 4, h = 22 },
            props = { text = tab.text },
            style = {
                bg           = is_active and "#6844aa" or "#333344",
                text         = "#FFFFFF",
                font_size    = 11,
                gradient     = is_active and "#3b1f88" or "#1c1c2e",
                gradient_dir = "vertical"
            },
            on_click = function()
                set_view(tab.view)
            end
        })
    end
end

local function render_footer()
    local footer = s:element({
        id = "footer_bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = H - 18, w = W, h = 18 },
        style = { bg = C.header }
    })
    local gt  = util.game_time()
    local gtH = math.floor(gt / 3600)
    local gtM = math.floor((gt % 3600) / 60)
    handles.footer.left = footer:element({
        id = "footer_left",
        type = "label",
        rect = { unit = "px", x = 8, y = 3, w = 120, h = 14 },
        props = { text = "Time: " .. currenttime },
        style = { font_size = 8, color = C.text_muted, align = "left" }
    })
    handles.footer.right = footer:element({
        id = "footer_right",
        type = "label",
        rect = { unit = "px", x = W - 200, y = 3, w = 192, h = 14 },
        props = { text = string.format("Tick %.0f | ELAPSED %dh %02dm", math.floor(elapsed), gtH, gtM) },
        style = { font_size = 8, color = C.text_muted, align = "right" }
    })
end

local function update_header_dynamic()
    local statTxt = status_text(solarPct)
    local statCol = status_color(solarPct)
    if handles.header.status_dot ~= nil then
        handles.header.status_dot:set_style({ bg = statCol })
    end
    if handles.header.status_label ~= nil then
        handles.header.status_label:set_props({ text = statTxt })
        handles.header.status_label:set_style({ font_size = 11, color = statCol, align = "left" })
    end
end

local function update_nav_dynamic()
    if handles.nav.overview ~= nil then
        local active = view == "overview"
        handles.nav.overview:set_style({
            bg = active and "#6844aa" or "#333344",
            text = "#FFFFFF",
            font_size = 11,
            gradient = active and "#3b1f88" or "#1c1c2e",
            gradient_dir = "vertical"
        })
    end
    if handles.nav.settings ~= nil then
        local active = view == "settings"
        handles.nav.settings:set_style({
            bg = active and "#6844aa" or "#333344",
            text = "#FFFFFF",
            font_size = 11,
            gradient = active and "#3b1f88" or "#1c1c2e",
            gradient_dir = "vertical"
        })
    end
end

local function update_footer_dynamic()
    local gt  = util.game_time()
    local gtH = math.floor(gt / 3600)
    local gtM = math.floor((gt % 3600) / 60)
    if handles.footer.left ~= nil then
        handles.footer.left:set_props({ text = "Time: " .. currenttime })
    end
    if handles.footer.right ~= nil then
        handles.footer.right:set_props({ text = string.format("Tick %.0f | ELAPSED %dh %02dm", math.floor(elapsed), gtH, gtM) })
    end
end

-- ==================== OVERVIEW VIEW ====================

local function render_overview()
    local body_y = 60
    local col_w  = math.floor((W - 22) / 2)
    local left_x = 5
    local right_x = left_x + col_w + 6

    local section_title_h = 12
    local panel_gap = 4
    local content_bottom = H - 20
    local history_gap = 4
    local history_title_h = 12
    local content_h = content_bottom - body_y
    local history_h = math.max(64, math.floor(content_h * 0.34))
    local top_bottom = content_bottom - history_gap - history_title_h - history_h


    local wind_panel_h = 28
    s:element({
        id = "wind_section",
        type = "label",
        rect = { unit = "px", x = left_x, y = body_y, w = col_w, h = section_title_h },
        props = { text = "WIND TURBINES" },
        style = { font_size = 10, color = C.accent, align = "center" }
    })

    local wind_panel_y = body_y + section_title_h
    local wind_panel = s:element({
        id = "wind_info_bg",
        type = "panel",
        rect = { unit = "px", x = left_x, y = wind_panel_y, w = col_w + 2, h = wind_panel_h + 5 },
        style = { bg = C.panel }
    })
    local windPct = windCount > 0 and math.min(100, (windPower / windMaxpower) * 100) or 0
    handles.overview.wind_count = wind_panel:element({
        id = "wind_count",
        type = "label",
        rect = { unit = "px", x = 10, y = 2, w = col_w - 14, h = 10 },
        props = { text = "Turbines: " .. windCount },
        style = { font_size = 9, color = C.text, align = "left" }
    })
    handles.overview.wind_generation = wind_panel:element({
        id = "wind_generation",
        type = "label",
        rect = { unit = "px", x = 10, y = 12, w = col_w - 14, h = 10 },
        props = { text = "Generation: " .. fmt_power(windPower) .. " / " .. fmt_power(windMaxpower) },
        style = { font_size = 9, color = C.text, align = "left" }
    })
    handles.overview.wind_pct = wind_panel:element({
        id = "wind_pct",
        type = "label",
        rect = { unit = "px", x = 10, y = 22, w = col_w - 14, h = 10 },
        props = { text = "Utilization: " .. fmt(windPct, 1) .. "%" },
        style = { font_size = 9, color = pct_color(windPct), align = "left" }
    })

    local solar_panel_h = 28
    local solar_y = wind_panel_y + wind_panel_h + panel_gap
    s:element({
        id = "solar_section",
        type = "label",
        rect = { unit = "px", x = left_x, y = solar_y, w = col_w , h = section_title_h },
        props = { text = "SOLAR PANELS" },
        style = { font_size = 10, color = C.yellow, align = "center" }
    })

    local solar_panel_y = solar_y + section_title_h
    local solar_panel = s:element({
        id = "solar_info_bg",
        type = "panel",
        rect = { unit = "px", x = left_x, y = solar_panel_y, w = col_w + 2, h = solar_panel_h + 5 },
        style = { bg = C.panel }
    })
    handles.overview.solar_count = solar_panel:element({
        id = "solar_count",
        type = "label",
        rect = { unit = "px", x = 10, y = 2, w = col_w - 14, h = 10 },
        props = { text = "Panels: " .. solarCount },
        style = { font_size = 9, color = C.text, align = "left" }
    })
    handles.overview.solar_tracker_status = solar_panel:element({
        id = "solar_tracker_status",
        type = "label",
        rect = { unit = "px", x = 10, y = 2, w = col_w - 14, h = 10 },
        props = { text = mk1_Enabled and "TRACK ON" or "TRACK OFF" },
        style = { font_size = 7, color = mk1_Enabled and C.green or C.red, align = "right" }
    })
    handles.overview.solar_generation = solar_panel:element({
        id = "solar_generation",
        type = "label",
        rect = { unit = "px", x = 10, y = 12, w = col_w - 14, h = 10 },
        props = { text = "Generation: " .. fmt_power(solarCharge) .. " / " .. fmt_power(solarMaxCharge) },
        style = { font_size = 9, color = C.text, align = "left" }
    })
    handles.overview.solar_pct = solar_panel:element({
        id = "solar_pct",
        type = "label",
        rect = { unit = "px", x = 10, y = 22, w = col_w - 14, h = 10 },
        props = { text = "Utilization: " .. fmt(solarPct, 1) .. "%" },
        style = { font_size = 9, color = pct_color(solarPct), align = "left" }
    })

    local bat_section_y = solar_panel_y + solar_panel_h + panel_gap
    local bat_panel_y = bat_section_y + section_title_h
    local bat_panel_h = math.max(30, top_bottom - bat_panel_y)

    s:element({
        id = "bat_section_lbl",
        type = "label",
        rect = { unit = "px", x = left_x, y = bat_section_y, w = col_w, h = section_title_h },
        props = { text = "BATTERY" },
        style = { font_size = 10, color = C.accent, align = "center" }
    })
    s:element({
        id = "bat_panel_bg",
        type = "panel",
        rect = { unit = "px", x = left_x, y = bat_panel_y, w = col_w + 2, h = bat_panel_h },
        style = { bg = C.panel }
    })

    local bat_bar_w = col_w - 36
    local bat_bar_x = left_x + 18
    local spark_h = math.max(6, bat_panel_h - 32)
    handles.overview.bat_pct = s:element({
        id = "bat_pct",
        type = "label",
        rect = { unit = "px", x = left_x + 8, y = bat_panel_y + 7, w = col_w - 16, h = 14 },
        props = { text = fmt(batPct, 1) .. "%" },
        style = { font_size = 16, color = pct_color(batPct), align = "center" }
    })
    handles.overview.bat_energy = s:element({
        id = "bat_energy",
        type = "label",
        rect = { unit = "px", x = left_x + 8, y = bat_panel_y + 20, w = col_w - 16, h = 8 },
        props = { text = fmt_energy(batCharge) .. " / " .. fmt_energy(batMax) },
        style = { font_size = 7, color = C.text_dim, align = "center" }
    })
    handles.overview.bat_progress = s:element({
        id = "bat_progress",
        type = "progress",
        rect = { unit = "px", x = bat_bar_x, y = bat_panel_y + 28, w = bat_bar_w, h = 6 },
        props = { value = batPct, max = "100" },
        style = { bg = "#1A2540", fill = pct_color(batPct) }
    })
    handles.overview.bat_sparkline = s:element({
        id = "bat_sparkline",
        type = "linechart",
        rect = { unit = "px", x = bat_bar_x - 25, y = bat_panel_y + 35, w = bat_bar_w + 20, h = spark_h },
        props = {
            series = { batHistory },
            series_colors = { pct_color(batPct) },
            min = 0,
            max = 100,
        },
        style = {
            bg = "transparent",
            show_grid = "true",
            show_legend = "false",
            fill = "true",
            thickness = "1.0",
            font_size = "4"
        }
    })


    local right_panel_pad = 7
    local right_panel_x = right_x + right_panel_pad
    local right_panel_w = col_w - (right_panel_pad * 2)
    local title_h = section_title_h
    local section_gap = panel_gap
    local right_total_h = top_bottom - body_y
    local fixed_h = (title_h * 2) + section_gap
    local panel_h_base = math.floor((right_total_h - fixed_h) / 2)
    if panel_h_base < 52 then panel_h_base = 52 end
    local extra_h = right_total_h - fixed_h - (panel_h_base * 2)

    local solid_panel_h = panel_h_base + (extra_h > 0 and extra_h or 0)
    local gas_panel_h = panel_h_base

    local meter_w = math.min(62, math.max(48, right_panel_w - 122))
    local meter_x = right_panel_x + right_panel_w - meter_w - 8

    s:element({
        id = "solid_section",
        type = "label",
        rect = { unit = "px", x = right_panel_x, y = body_y, w = right_panel_w, h = title_h },
        props = { text = "SOLID FUEL GENERATORS" },
        style = { font_size = 10, color = C.orange, align = "center" }
    })

    local solid_panel_y = body_y + title_h
    s:element({
        id = "solid_panel_bg",
        type = "panel",
        rect = { unit = "px", x = right_panel_x - 7, y = solid_panel_y, w = right_panel_w + 16, h = solid_panel_h - 27 },
        style = { bg = C.panel }
    })

    local sDisplayActive = solidForceState ~= nil and solidForceState or (solidOnCount > 0)
    local solidTotal = (solidCount ~= nil and solidCount == solidCount) and solidCount or 0
    local solidRunning = (solidOnCount ~= nil and solidOnCount == solidOnCount) and solidOnCount or 0
    local sCountTxt = (solidTotal <= 0) and "No generators detected"
        or ("DETECTED: " .. solidTotal .. "  RUNNING: " .. solidRunning)
    handles.overview.solid_count_lbl = s:element({
        id = "solid_count_lbl",
        type = "label",
        rect = { unit = "px", x = right_panel_x + 8, y = solid_panel_y + 4, w = right_panel_w - 56, h = 10 },
        props = { text = sCountTxt },
        style = { font_size = 8, color = C.text, align = "left" }
    })
    handles.overview.solid_status_dot = s:element({
        id = "solid_status_dot",
        type = "panel",
        rect = { unit = "px", x = right_panel_x + right_panel_w - 45, y = solid_panel_y + 6, w = 5, h = 5 },
        style = { bg = sDisplayActive and C.gen_on or C.gen_off }
    })
    handles.overview.solid_status_txt = s:element({
        id = "solid_status_txt",
        type = "label",
        rect = { unit = "px", x = right_panel_x + right_panel_w - 37, y = solid_panel_y + 4, w = 30, h = 10 },
        props = { text = solidCount == 0 and "N/A" or (sDisplayActive and "ON" or "OFF") },
        style = { font_size = 8, color = sDisplayActive and C.gen_on or C.gen_off, align = "left" }
    })

    s:element({
        id = "solid_power_lbl",
        type = "label",
        rect = { unit = "px", x = right_panel_x + 8, y = solid_panel_y + 18, w = 46, h = 10 },
        props = { text = "Output:" },
        style = { font_size = 8, color = C.text_dim, align = "left" }
    })
    handles.overview.solid_power_val = s:element({
        id = "solid_power_val",
        type = "label",
        rect = { unit = "px", x = right_panel_x + 54, y = solid_panel_y + 18, w = right_panel_w - 62, h = 10 },
        props = { text = fmt_power(solidPower) },
        style = { font_size = 8, color = C.text_dim, align = "left" }
    })

    local solidSlot = 0
    local solidPrefab = selected_prefab(MEM_PREFAB_SOLID)
    if solidPrefab ~= nil then
        solidSlot = batch_read_slot(solidPrefab, 0, LST.Quantity, LBM.Sum) or 0
    end
    local solidgenPct = math.min(100, (solidSlot / 1000) * 100)
    handles.overview.solid_debug = s:element({
        id = "solid_debug",
        type = "label",
        rect = { unit = "px", x = right_panel_x + 8, y = solid_panel_y + 32, w = right_panel_w - meter_w - 20, h = 10 },
        props = { text = "Input Quantity: " .. fmt(solidSlot, 0) },
        style = { font_size = 8, color = C.text_dim, align = "left" }
    })
    handles.overview.solid_gas_bar = s:element({
        id = "solid_gas_bar",
        type = "progress",
        rect = { unit = "px", x = meter_x - 15, y = solid_panel_y + 33, w = meter_w + 20, h = 8 },
        props = { value = solidgenPct, max = "100" },
        style = { bg = "#a51919", fill = "#00E676" }
    })

    local btn_h = 14
    local btn_gap = 4
    local btn_pad = 14
    local btn_w = math.floor((right_panel_w - (btn_pad * 2) - (btn_gap * 2)) / 3)
    local btn_y = solid_panel_y + solid_panel_h - btn_h - 2
    handles.overview.solid_btn_on = s:element({
        id = "solid_btn_on",
        type = "button",
        rect = { unit = "px", x = right_panel_x + btn_pad, y = btn_y - 30, w = btn_w, h = btn_h },
        props = { text = "ON" },
        style = { bg = solidForceState == true and C.green or C.btn_on, text = "#FFFFFF", font_size = 9, gradient = "#0d0b1e", gradient_dir = "vertical" },
        on_click = function()
            solidForceState = true
            save_force_states()
            dashboard_render(false)
        end
    })
    handles.overview.solid_btn_off = s:element({
        id = "solid_btn_off",
        type = "button",
        rect = { unit = "px", x = right_panel_x + btn_pad + btn_w + btn_gap, y = btn_y - 30, w = btn_w, h = btn_h },
        props = { text = "OFF" },
        style = { bg = solidForceState == false and C.red or C.btn_off, text = "#FFFFFF", font_size = 9, gradient = "#0d0b1e", gradient_dir = "vertical" },
        on_click = function()
            solidForceState = false
            save_force_states()
            dashboard_render(false)
        end
    })
    handles.overview.solid_btn_auto = s:element({
        id = "solid_btn_auto",
        type = "button",
        rect = { unit = "px", x = right_panel_x + btn_pad + (btn_w + btn_gap) * 2, y = btn_y - 30, w = btn_w, h = btn_h },
        props = { text = "AUTO" },
        style = { bg = solidForceState == nil and C.accent or C.btn_auto, text = "#FFFFFF", font_size = 9, gradient = "#0d0b1e", gradient_dir = "vertical" },
        on_click = function()
            solidForceState = nil
            save_force_states()
            dashboard_render(false)
        end
    })

    local gas_section_y = solid_panel_y + solid_panel_h + section_gap - 32
    s:element({
        id = "gas_section",
        type = "label",
        rect = { unit = "px", x = right_panel_x, y = gas_section_y, w = right_panel_w, h = title_h },
        props = { text = "GAS FUEL GENERATORS" },
        style = { font_size = 10, color = C.green, align = "center" }
    })

    local gas_panel_y = gas_section_y + title_h
    s:element({
        id = "gas_panel_bg",
        type = "panel",
        rect = { unit = "px", x = right_panel_x - 7, y = gas_panel_y, w = right_panel_w + 16, h = gas_panel_h + 32 },
        style = { bg = C.panel }
    })

    local gDisplayActive = gasForceState ~= nil and gasForceState or (gasOnCount > 0)
    local gCountTxt = gasCount == 0 and "No generators detected"
        or ("DETECTED: " .. (gasCount or "none") .. "  RUNNING: " .. (gasOnCount or "none"))
    handles.overview.gas_count_lbl = s:element({
        id = "gas_count_lbl",
        type = "label",
        rect = { unit = "px", x = right_panel_x + 8, y = gas_panel_y + 4, w = right_panel_w - 56, h = 10 },
        props = { text = gCountTxt },
        style = { font_size = 8, color = C.text, align = "left" }
    })
    handles.overview.gas_status_dot = s:element({
        id = "gas_status_dot",
        type = "panel",
        rect = { unit = "px", x = right_panel_x + right_panel_w - 45, y = gas_panel_y + 6, w = 5, h = 5 },
        style = { bg = gDisplayActive and C.gen_on or C.gen_off }
    })
    handles.overview.gas_status_txt = s:element({
        id = "gas_status_txt",
        type = "label",
        rect = { unit = "px", x = right_panel_x + right_panel_w - 37, y = gas_panel_y + 4, w = 30, h = 10 },
        props = { text = gasCount == 0 and "N/A" or (gDisplayActive and "ON" or "OFF") },
        style = { font_size = 8, color = gDisplayActive and C.gen_on or C.gen_off, align = "left" }
    })

    s:element({
        id = "gas_power_lbl",
        type = "label",
        rect = { unit = "px", x = right_panel_x + 8, y = gas_panel_y + 18, w = 46, h = 10 },
        props = { text = "Output:" },
        style = { font_size = 8, color = C.text_dim, align = "left" }
    })
    handles.overview.gas_power_val = s:element({
        id = "gas_power_val",
        type = "label",
        rect = { unit = "px", x = right_panel_x + 54, y = gas_panel_y + 18, w = right_panel_w - 62, h = 10 },
        props = { text = fmt_power(gasPower) },
        style = { font_size = 8, color = C.text_dim, align = "left" }
    })

    local gbtn_y = gas_panel_y + 32
    handles.overview.gas_btn_on = s:element({
        id = "gas_btn_on",
        type = "button",
        rect = { unit = "px", x = right_panel_x + btn_pad, y = gbtn_y + 10, w = btn_w, h = btn_h },
        props = { text = "ON" },
        style = { bg = gasForceState == true and C.green or C.btn_on, text = "#FFFFFF", font_size = 9, gradient = "#0d0b1e", gradient_dir = "vertical" },
        on_click = function()
            gasForceState = true
            save_force_states()
            dashboard_render(false)
        end
    })

    local gas_pressure_y = gas_panel_y + gas_panel_h - btn_h - 2
    local gasCol = pct_color(gasPct)
    handles.overview.gas_debug = s:element({
        id = "gas_debug",
        type = "label",
        rect = { unit = "px", x = right_panel_x + 8, y = gas_pressure_y - 7, w = right_panel_w - meter_w - 20, h = 10 },
        props = { text = "Pressure: " .. fmt(gasPct, 0) .. " kPa" },
        style = { font_size = 8, color = gasCol, align = "left" }
    })
    handles.overview.gas_bar = s:element({
        id = "gas_bar",
        type = "progress",
        rect = { unit = "px", x = meter_x - 15, y = gas_pressure_y - 6, w = meter_w + 20, h = 8 },
        props = { value = gasPct, max = "100" },
        style = { bg = "#00E676", fill = "#a51919" }
    })

    local reg_label_y = gas_pressure_y + 12
    local reg_btn_h = 12
    local reg_btn_gap = 4
    local reg_btn_w = math.floor((right_panel_w - (btn_pad * 2) - (reg_btn_gap * 3)) / 4)
    local reg_btn_y = reg_label_y + 9
    local regText = presregCount == 0 and "Reg Set: N/A" or ("Reg Set: " .. fmt(presregSetting, 1) .. " kPa")
    handles.overview.presreg_setting_lbl = s:element({
        id = "presreg_setting_lbl",
        type = "label",
        rect = { unit = "px", x = right_panel_x + 8, y = reg_label_y - 3, w = right_panel_w - 16, h = 9 },
        props = { text = regText },
        style = { font_size = 7, color = C.text_dim, align = "center" }
    })

    s:element({
        id = "presreg_btn_p1",
        type = "button",
        rect = { unit = "px", x = right_panel_x + btn_pad, y = reg_btn_y, w = reg_btn_w, h = reg_btn_h },
        props = { text = "+1" },
        style = { bg = C.btn_auto, text = "#FFFFFF", font_size = 8, gradient = "#0d0b1e", gradient_dir = "vertical" },
        on_click = function()
            adjust_presreg_setting(1)
        end
    })
    s:element({
        id = "presreg_btn_m1",
        type = "button",
        rect = { unit = "px", x = right_panel_x + btn_pad + reg_btn_w + reg_btn_gap, y = reg_btn_y, w = reg_btn_w, h = reg_btn_h },
        props = { text = "-1" },
        style = { bg = C.btn_auto, text = "#FFFFFF", font_size = 8, gradient = "#0d0b1e", gradient_dir = "vertical" },
        on_click = function()
            adjust_presreg_setting(-1)
        end
    })
    s:element({
        id = "presreg_btn_p01",
        type = "button",
        rect = { unit = "px", x = right_panel_x + btn_pad + (reg_btn_w + reg_btn_gap) * 2, y = reg_btn_y, w = reg_btn_w, h = reg_btn_h },
        props = { text = "+0.1" },
        style = { bg = C.btn_auto, text = "#FFFFFF", font_size = 8, gradient = "#0d0b1e", gradient_dir = "vertical" },
        on_click = function()
            adjust_presreg_setting(0.1)
        end
    })
    s:element({
        id = "presreg_btn_m01",
        type = "button",
        rect = { unit = "px", x = right_panel_x + btn_pad + (reg_btn_w + reg_btn_gap) * 3, y = reg_btn_y, w = reg_btn_w, h = reg_btn_h },
        props = { text = "-0.1" },
        style = { bg = C.btn_auto, text = "#FFFFFF", font_size = 8, gradient = "#0d0b1e", gradient_dir = "vertical" },
        on_click = function()
            adjust_presreg_setting(-0.1)
        end
    })
    handles.overview.gas_btn_off = s:element({
        id = "gas_btn_off",
        type = "button",
        rect = { unit = "px", x = right_panel_x + btn_pad + btn_w + btn_gap, y = gbtn_y + 10, w = btn_w, h = btn_h },
        props = { text = "OFF" },
        style = { bg = gasForceState == false and C.red or C.btn_off, text = "#FFFFFF", font_size = 9, gradient = "#0d0b1e", gradient_dir = "vertical" },
        on_click = function()
            gasForceState = false
            save_force_states()
            dashboard_render(false)
        end
    })
    handles.overview.gas_btn_auto = s:element({
        id = "gas_btn_auto",
        type = "button",
        rect = { unit = "px", x = right_panel_x + btn_pad + (btn_w + btn_gap) * 2, y = gbtn_y + 10, w = btn_w, h = btn_h },
        props = { text = "AUTO" },
        style = { bg = gasForceState == nil and C.accent or C.btn_auto, text = "#FFFFFF", font_size = 9, gradient = "#0d0b1e", gradient_dir = "vertical" },
        on_click = function()
            gasForceState = nil
            save_force_states()
            dashboard_render(false)
        end
    })

    s:element({
        id = "chart_lbl",
        type = "label",
        rect = { unit = "px", x = 5, y = top_bottom + history_gap, w = W - 10, h = history_title_h },
        props = { text = "GENERATION HISTORY" },
        style = { font_size = 10, color = C.text, align = "center" }
    })
    handles.overview.power_chart = s:element({
        id = "power_chart",
        type = "linechart",
        rect = { unit = "px", x = 5, y = top_bottom + history_gap + history_title_h, w = W - 10, h = history_h },
        props = {
            series        = { windHistory, solarHistory, solidHistory, gasHistory, cableHistory },
            series_colors = { C.blue, C.yellow, C.orange, C.green, C.red },
            series_labels = { "Wind %", "Solar %", "Gen kW", "Gas kW", "Grid " .. fmt_power(cablePower) .. " usage" },
            min = 0,
            max = historyChartMax,
        },
        style = {
            bg          = C.panel,
            show_grid   = "true",
            show_legend = "true",
            fill        = "true",
            thickness   = "1.5",
            font_size   = "7"
        }
    })
end

local function update_overview_dynamic()
    if next(handles.overview) == nil then return end

    local windPct = windCount > 0 and math.min(100, (windPower / windMaxpower) * 100) or 0
    if handles.overview.wind_count ~= nil then
        handles.overview.wind_count:set_props({ text = "Turbines: " .. windCount })
    end
    if handles.overview.wind_generation ~= nil then
        handles.overview.wind_generation:set_props({ text = "Generation: " .. fmt_power(windPower) .. " / " .. fmt_power(windMaxpower) })
    end
    if handles.overview.wind_pct ~= nil then
        handles.overview.wind_pct:set_props({ text = "Utilization: " .. fmt(windPct, 1) .. "%" })
        handles.overview.wind_pct:set_style({ font_size = 9, color = pct_color(windPct), align = "left" })
    end

    if handles.overview.solar_count ~= nil then
        handles.overview.solar_count:set_props({ text = "Panels: " .. solarCount })
    end
    if handles.overview.solar_tracker_status ~= nil then
        handles.overview.solar_tracker_status:set_props({ text = mk1_Enabled and "TRACK ON" or "TRACK OFF" })
        handles.overview.solar_tracker_status:set_style({ font_size = 7, color = mk1_Enabled and C.green or C.red, align = "right" })
    end
    if handles.overview.solar_generation ~= nil then
        handles.overview.solar_generation:set_props({ text = "Generation: " .. fmt_power(solarCharge) .. " / " .. fmt_power(solarMaxCharge) })
    end
    if handles.overview.solar_pct ~= nil then
        handles.overview.solar_pct:set_props({ text = "Utilization: " .. fmt(solarPct, 1) .. "%" })
        handles.overview.solar_pct:set_style({ font_size = 9, color = pct_color(solarPct), align = "left" })
    end

    if handles.overview.bat_pct ~= nil then
        handles.overview.bat_pct:set_props({ text = fmt(batPct, 1) .. "%" })
        handles.overview.bat_pct:set_style({ font_size = 16, color = pct_color(batPct), align = "center" })
    end
    if handles.overview.bat_energy ~= nil then
        handles.overview.bat_energy:set_props({ text = fmt_energy(batCharge) .. " / " .. fmt_energy(batMax) })
    end
    if handles.overview.bat_progress ~= nil then
        handles.overview.bat_progress:set_props({ value = batPct, max = "100" })
        handles.overview.bat_progress:set_style({ bg = "#1A2540", fill = pct_color(batPct) })
    end
    if handles.overview.bat_sparkline ~= nil then
        handles.overview.bat_sparkline:set_props({ series = { batHistory }, series_colors = { pct_color(batPct) }, min = 0, max = 100 })
    end

    local sDisplayActive = solidForceState ~= nil and solidForceState or (solidOnCount > 0)
    local solidTotal = (solidCount ~= nil and solidCount == solidCount) and solidCount or 0
    local solidRunning = (solidOnCount ~= nil and solidOnCount == solidOnCount) and solidOnCount or 0
    local sCountTxt = (solidTotal <= 0) and "No generators detected" or ("DETECTED: " .. solidTotal .. "  RUNNING: " .. solidRunning)
    local solidPrefab = selected_prefab(MEM_PREFAB_SOLID)
    local solidSlot = 0
    if solidPrefab ~= nil then
        solidSlot = batch_read_slot(solidPrefab, 0, LST.Quantity, LBM.Sum) or 0
    end
    local solidgenPct = math.min(100, (solidSlot / 1000) * 100)

    if handles.overview.solid_count_lbl ~= nil then
        handles.overview.solid_count_lbl:set_props({ text = sCountTxt })
    end
    if handles.overview.solid_status_dot ~= nil then
        handles.overview.solid_status_dot:set_style({ bg = sDisplayActive and C.gen_on or C.gen_off })
    end
    if handles.overview.solid_status_txt ~= nil then
        handles.overview.solid_status_txt:set_props({ text = solidCount == 0 and "N/A" or (sDisplayActive and "ON" or "OFF") })
        handles.overview.solid_status_txt:set_style({ font_size = 8, color = sDisplayActive and C.gen_on or C.gen_off, align = "left" })
    end
    if handles.overview.solid_power_val ~= nil then
        handles.overview.solid_power_val:set_props({ text = fmt_power(solidPower) })
    end
    if handles.overview.solid_debug ~= nil then
        handles.overview.solid_debug:set_props({ text = "Input Quantity: " .. fmt(solidSlot, 0) })
    end
    if handles.overview.solid_gas_bar ~= nil then
        handles.overview.solid_gas_bar:set_props({ value = solidgenPct, max = "100" })
    end
    if handles.overview.solid_btn_on ~= nil then
        handles.overview.solid_btn_on:set_style({ bg = solidForceState == true and C.green or C.btn_on, text = "#FFFFFF", font_size = 9, gradient = "#0d0b1e", gradient_dir = "vertical" })
    end
    if handles.overview.solid_btn_off ~= nil then
        handles.overview.solid_btn_off:set_style({ bg = solidForceState == false and C.red or C.btn_off, text = "#FFFFFF", font_size = 9, gradient = "#0d0b1e", gradient_dir = "vertical" })
    end
    if handles.overview.solid_btn_auto ~= nil then
        handles.overview.solid_btn_auto:set_style({ bg = solidForceState == nil and C.accent or C.btn_auto, text = "#FFFFFF", font_size = 9, gradient = "#0d0b1e", gradient_dir = "vertical" })
    end

    local gDisplayActive = gasForceState ~= nil and gasForceState or (gasOnCount > 0)
    local gCountTxt = gasCount == 0 and "No generators detected" or ("DETECTED: " .. (gasCount or "none") .. "  RUNNING: " .. (gasOnCount or "none"))
    local gasCol = pct_color(gasPct)
    local regText = presregCount == 0 and "Reg Set: N/A" or ("Reg Set: " .. fmt(presregSetting, 1) .. " kPa")

    if handles.overview.gas_count_lbl ~= nil then
        handles.overview.gas_count_lbl:set_props({ text = gCountTxt })
    end
    if handles.overview.gas_status_dot ~= nil then
        handles.overview.gas_status_dot:set_style({ bg = gDisplayActive and C.gen_on or C.gen_off })
    end
    if handles.overview.gas_status_txt ~= nil then
        handles.overview.gas_status_txt:set_props({ text = gasCount == 0 and "N/A" or (gDisplayActive and "ON" or "OFF") })
        handles.overview.gas_status_txt:set_style({ font_size = 8, color = gDisplayActive and C.gen_on or C.gen_off, align = "left" })
    end
    if handles.overview.gas_power_val ~= nil then
        handles.overview.gas_power_val:set_props({ text = fmt_power(gasPower) })
    end
    if handles.overview.gas_debug ~= nil then
        handles.overview.gas_debug:set_props({ text = "Pressure: " .. fmt(gasPct, 0) .. " kPa" })
        handles.overview.gas_debug:set_style({ font_size = 8, color = gasCol, align = "left" })
    end
    if handles.overview.gas_bar ~= nil then
        handles.overview.gas_bar:set_props({ value = gasPct, max = "100" })
    end
    if handles.overview.presreg_setting_lbl ~= nil then
        handles.overview.presreg_setting_lbl:set_props({ text = regText })
    end
    if handles.overview.gas_btn_on ~= nil then
        handles.overview.gas_btn_on:set_style({ bg = gasForceState == true and C.green or C.btn_on, text = "#FFFFFF", font_size = 9, gradient = "#0d0b1e", gradient_dir = "vertical" })
    end
    if handles.overview.gas_btn_off ~= nil then
        handles.overview.gas_btn_off:set_style({ bg = gasForceState == false and C.red or C.btn_off, text = "#FFFFFF", font_size = 9, gradient = "#0d0b1e", gradient_dir = "vertical" })
    end
    if handles.overview.gas_btn_auto ~= nil then
        handles.overview.gas_btn_auto:set_style({ bg = gasForceState == nil and C.accent or C.btn_auto, text = "#FFFFFF", font_size = 9, gradient = "#0d0b1e", gradient_dir = "vertical" })
    end
    if handles.overview.power_chart ~= nil then
        handles.overview.power_chart:set_props({
            series = { windHistory, solarHistory, solidHistory, gasHistory, cableHistory },
            series_colors = { C.blue, C.yellow, C.orange, C.green, C.red },
            series_labels = { "Wind %", "Solar %", "Gen kW", "Gas kW", "Grid " .. fmt_power(cablePower) .. " usage" },
            min = 0,
            max = historyChartMax,
        })
    end
end

-- ==================== SETTINGS VIEW ====================

local function render_settings()
    local content_y = 60

    s:element({
        id = "settings_bg",
        type = "panel",
        rect = { unit = "px", x = 8, y = content_y, w = W - 16, h = H - content_y - 22 },
        style = { bg = "#0A0A15" }
    })

    local stab_w = math.floor((W - 16) / 3)
    local stab_h = 20
    local stab_y = content_y + 4
    s:element({
        id = "stab_devices",
        type = "button",
        rect = { unit = "px", x = 8, y = stab_y, w = stab_w - 2, h = stab_h },
        props = { text = "DEVICES" },
        style = {
            bg           = settings_subtab == "devices" and "#6844aa" or "#1c1c2e",
            text         = "#FFFFFF",
            font_size    = 10,
            gradient     = settings_subtab == "devices" and "#3b1f88" or "#111120",
            gradient_dir = "vertical"
        },
        on_click = function()
            settings_subtab = "devices"
            dashboard_render()
        end
    })
    s:element({
        id = "stab_power",
        type = "button",
        rect = { unit = "px", x = 8 + (stab_w + 2), y = stab_y, w = stab_w - 2, h = stab_h },
        props = { text = "POWER & AUTO" },
        style = {
            bg           = settings_subtab == "power" and "#6844aa" or "#1c1c2e",
            text         = "#FFFFFF",
            font_size    = 10,
            gradient     = settings_subtab == "power" and "#3b1f88" or "#111120",
            gradient_dir = "vertical"
        },
        on_click = function()
            settings_subtab = "power"
            dashboard_render()
        end
    })
    s:element({
        id = "stab_solar",
        type = "button",
        rect = { unit = "px", x = 8 + (stab_w + 2) * 2, y = stab_y, w = stab_w - 2, h = stab_h },
        props = { text = "SOLAR TRACKER" },
        style = {
            bg           = settings_subtab == "solar" and "#6844aa" or "#1c1c2e",
            text         = "#FFFFFF",
            font_size    = 10,
            gradient     = settings_subtab == "solar" and "#3b1f88" or "#111120",
            gradient_dir = "vertical"
        },
        on_click = function()
            settings_subtab = "solar"
            dashboard_render()
        end
    })

    local tab_content_y = stab_y + stab_h + 4

    local lbl_x   = 18
    local inp_x   = 190
    local inp_w   = W - inp_x - 20
    local row_h   = 26

    if settings_subtab == "devices" then
        s:element({
            id = "settings_hint",
            type = "label",
            rect = { unit = "px", x = lbl_x, y = tab_content_y + 2, w = W - 36, h = 12 },
            props = { text = "Select a device for each type. Leave on 'Select' to read all matching devices." },
            style = { font_size = 8, color = C.text_dim, align = "left" }
        })

        local base_y = tab_content_y + 16
        local dd_x   = 140
        local dd_w   = W - dd_x - 20

        for i, def in ipairs(piac_dropdown_defs) do
            local y = base_y + (i - 1) * row_h
            if cached_piac_dropdowns == nil then
                populate_piac_dropdown_cache()
            end
            local cache_entry = cached_piac_dropdowns[def.key] or { opts = { "Select" }, candidates = {}, selected = 0 }
            settings_dropdown_selected[def.key] = cache_entry.selected
            s:element({
                id = def.id .. "_label",
                type = "label",
                rect = { unit = "px", x = lbl_x, y = y + 3, w = 118, h = 20 },
                props = { text = def.label },
                style = { font_size = 9, color = "#94A3B8", align = "left" }
            })
            s:element({
                id = def.id .. "_dropdown",
                type = "select",
                rect = { unit = "px", x = dd_x, y = y, w = dd_w, h = 22 },
                props = {
                    options  = table.concat(cache_entry.opts, "|"),
                    selected = settings_dropdown_selected[def.key],
                    open     = settings_dropdown_open[def.key],
                },
                on_toggle = function()
                    if cached_piac_dropdowns == nil then
                        populate_piac_dropdown_cache()
                    end
                    settings_dropdown_open[def.key] = settings_dropdown_open[def.key] == "true" and "false" or "true"
                    dashboard_render()
                end,
                on_change = function(optionIndex)
                    local sel = tonumber(optionIndex) or 0
                    settings_dropdown_selected[def.key] = sel
                    if cached_piac_dropdowns and cached_piac_dropdowns[def.key] then
                        cached_piac_dropdowns[def.key].selected = sel
                    end
                    piac_write_selected_device(sel, cache_entry.candidates, def.mem_prefab, def.mem_namehash)
                    settings_dropdown_open[def.key] = "false"
                    dashboard_render()
                end
            })
        end

        s:element({
            id = "settings_note",
            type = "label",
            rect = { unit = "px", x = lbl_x, y = base_y + #piac_dropdown_defs * row_h + 6, w = W - 36, h = 20 },
            props = { text = "NOTE: No selection = no read/write for that system. Named devices require prefab + name." },
            style = { font_size = 7, color = C.text_muted, align = "left" }
        })

        s:element({
            id = "refresh_ticks_label",
            type = "label",
            rect = { unit = "px", x = lbl_x, y = base_y + #piac_dropdown_defs * row_h + 30, w = inp_x - lbl_x - 4, h = 20 },
            props = { text = "Refresh Ticks (1-120):" },
            style = { font_size = 9, color = "#94A3B8", align = "left" }
        })
        s:element({
            id = "refresh_ticks_input",
            type = "textinput",
            rect = { unit = "px", x = inp_x, y = base_y + #piac_dropdown_defs * row_h + 30, w = 60, h = 20 },
            props = { value = tostring(LIVE_REFRESH_TICKS), placeholder = "6" },
            on_change = function(new_value)
                local n = math.max(1, math.min(120, tonumber(new_value) or LIVE_REFRESH_TICKS))
                LIVE_REFRESH_TICKS = n
                write(MEM_REFRESH_TICKS, n)
            end
        })

    elseif settings_subtab == "power" then
        local cy = tab_content_y

        s:element({
            id = "pwr_title",
            type = "label",
            rect = { unit = "px", x = lbl_x, y = cy, w = W - 36, h = 14 },
            props = { text = "Power Settings" },
            style = { font_size = 10, color = C.accent, align = "left" }
        })
        s:element({
            id = "wind_max_power_label",
            type = "label",
            rect = { unit = "px", x = lbl_x, y = cy + 16, w = inp_x - lbl_x - 4, h = 20 },
            props = { text = "Max Watts per Turbine:" },
            style = { font_size = 9, color = "#94A3B8", align = "left" }
        })
        s:element({
            id = "wind_max_power_input",
            type = "textinput",
            rect = { unit = "px", x = inp_x, y = cy + 16, w = inp_w, h = 20 },
            props = { value = settings_wind_max_power_input, placeholder = "5000" },
            on_change = function(newVal)
                local numVal = tonumber(newVal) or 5000
                if numVal < 100 then numVal = 100 end
                if numVal > 100000 then numVal = 100000 end
                windMaxPowerPerTurbine = numVal
                settings_wind_max_power_input = tostring(numVal)
                write(MEM_WIND_MAX_POWER, numVal)
                dashboard_render()
            end
        })

        s:element({
            id = "history_max_label",
            type = "label",
            rect = { unit = "px", x = lbl_x, y = cy + 40, w = inp_x - lbl_x - 4, h = 20 },
            props = { text = "History Chart Max kW:" },
            style = { font_size = 9, color = "#94A3B8", align = "left" }
        })
        s:element({
            id = "history_max_input",
            type = "textinput",
            rect = { unit = "px", x = inp_x, y = cy + 40, w = inp_w, h = 20 },
            props = { value = settings_history_max_input, placeholder = "100" },
            on_change = function(newVal)
                local numVal = tonumber(newVal) or 100
                if numVal < 10 then numVal = 10 end
                if numVal > 1000 then numVal = 1000 end
                historyChartMax = numVal
                settings_history_max_input = tostring(numVal)
                write(MEM_HISTORY_MAX, numVal)
                dashboard_render()
            end
        })

        local auto_title_y = cy + 68
        s:element({
            id = "auto_title",
            type = "label",
            rect = { unit = "px", x = lbl_x, y = auto_title_y, w = W - 36, h = 14 },
            props = { text = "Auto Generator Thresholds" },
            style = { font_size = 10, color = C.accent, align = "left" }
        })
        s:element({
            id = "auto_hint",
            type = "label",
            rect = { unit = "px", x = lbl_x, y = auto_title_y + 16, w = W - 36, h = 10 },
 --           props = { text = "ON when (wind<A% OR solar<B%) AND battery<C%   |   OFF when (wind>D% OR solar>D%) AND battery>E%" },
            props = { text = "ON when (wind+solar<A%+B%) AND battery<C%   |   OFF when (wind+solar>D%) OR battery>E%" },
            style = { font_size = 7, color = C.text_muted, align = "left" }
        })

        local auto_rows = {
            { id = "auto_on_wind",  label = "A  –  Turn ON when wind < (%)",        mem = MEM_AUTO_ON_WIND,  get = function() return auto_on_wind_pct  end, inp = function() return settings_auto_on_wind_input  end, set = function(v) auto_on_wind_pct  = v; settings_auto_on_wind_input  = tostring(v) end },
            { id = "auto_on_solar", label = "B  –  Turn ON when solar < (%)",       mem = MEM_AUTO_ON_SOLAR, get = function() return auto_on_solar_pct end, inp = function() return settings_auto_on_solar_input end, set = function(v) auto_on_solar_pct = v; settings_auto_on_solar_input = tostring(v) end },
            { id = "auto_on_bat",   label = "C  –  Turn ON when battery < (%)",     mem = MEM_AUTO_ON_BAT,   get = function() return auto_on_bat_pct   end, inp = function() return settings_auto_on_bat_input   end, set = function(v) auto_on_bat_pct   = v; settings_auto_on_bat_input   = tostring(v) end },
            { id = "auto_off_ren",  label = "D  –  Turn OFF when renewables > (%)", mem = MEM_AUTO_OFF_REN,  get = function() return auto_off_ren_pct  end, inp = function() return settings_auto_off_ren_input  end, set = function(v) auto_off_ren_pct  = v; settings_auto_off_ren_input  = tostring(v) end },
            { id = "auto_off_bat",  label = "E  –  Turn OFF when battery > (%)",    mem = MEM_AUTO_OFF_BAT,  get = function() return auto_off_bat_pct  end, inp = function() return settings_auto_off_bat_input  end, set = function(v) auto_off_bat_pct  = v; settings_auto_off_bat_input  = tostring(v) end },
        }
        local ar_gap = 4
        local ar_h   = 20
        for i, row in ipairs(auto_rows) do
            local ry = auto_title_y + 28 + (i - 1) * (ar_h + ar_gap)
            s:element({
                id = row.id .. "_lbl",
                type = "label",
                rect = { unit = "px", x = lbl_x, y = ry + 2, w = inp_x - lbl_x - 4, h = 16 },
                props = { text = row.label },
                style = { font_size = 9, color = "#94A3B8", align = "left" }
            })
            s:element({
                id = row.id .. "_input",
                type = "textinput",
                rect = { unit = "px", x = inp_x, y = ry, w = inp_w, h = ar_h },
                props = { value = row.inp(), placeholder = tostring(row.get()) },
                on_change = function(newVal)
                    local numVal = tonumber(newVal)
                    if numVal == nil then return end
                    if numVal < 0 then numVal = 0 end
                    if numVal > 100 then numVal = 100 end
                    row.set(numVal)
                    write(row.mem, numVal)
                    dashboard_render()
                end
            })
        end

    else
        local cy = tab_content_y
        local mk1_btn_y = cy
        local mk1_status_col = mk1_Enabled and C.green or C.red

        s:element({
            id = "mk1_title",
            type = "label",
            rect = { unit = "px", x = lbl_x, y = cy + 18, w = W - 36, h = 14 },
            props = { text = "Solar Tracker MK1 Config" },
            style = { font_size = 10, color = C.yellow, align = "left" }
        })

        s:element({
            id = "mk1_state_dot",
            type = "panel",
            rect = { unit = "px", x = lbl_x + 102, y = mk1_btn_y + 4, w = 7, h = 7 },
            style = { bg = mk1_status_col }
        })
        s:element({
            id = "mk1_state_lbl",
            type = "label",
            rect = { unit = "px", x = lbl_x + 112, y = mk1_btn_y + 1, w = 70, h = 12 },
            props = { text = mk1_Enabled and "ACTIVE" or "OFF" },
            style = { font_size = 8, color = mk1_status_col, align = "left" }
        })
        s:element({
            id = "mk1_enable_on",
            type = "button",
            rect = { unit = "px", x = lbl_x, y = mk1_btn_y, w = 42, h = 14 },
            props = { text = "ON" },
            style = {
                bg = mk1_Enabled and C.green or C.btn_on,
                text = "#FFFFFF",
                font_size = 8,
                gradient = mk1_Enabled and "#0f4a26" or "#0d0b1e",
                gradient_dir = "vertical"
            },
            on_click = function()
                mk1_Enabled = true
                write(MEM_MK1_ENABLED, 1)
                dashboard_render()
            end
        })
        s:element({
            id = "mk1_enable_off",
            type = "button",
            rect = { unit = "px", x = lbl_x + 46, y = mk1_btn_y, w = 42, h = 14 },
            props = { text = "OFF" },
            style = {
                bg = (not mk1_Enabled) and C.red or C.btn_off,
                text = "#FFFFFF",
                font_size = 8,
                gradient = (not mk1_Enabled) and "#471313" or "#0d0b1e",
                gradient_dir = "vertical"
            },
            on_click = function()
                mk1_Enabled = false
                write(MEM_MK1_ENABLED, 0)
                dashboard_render()
            end
        })

        s:element({
            id = "mk1_hint",
            type = "label",
            rect = { unit = "px", x = lbl_x, y = cy + 30, w = W - 36, h = 10 },
            props = { text = "pMode: 0=Track  1=Park  2=Face port  |  Panel port: 0=N 1=E 2=S 3=W  |  Sensor port: 0=E 1=N 2=W 3=S" },
            style = { font_size = 7, color = C.text_muted, align = "left" }
        })
        s:element({
            id = "mk1_solar_note",
            type = "label",
            rect = { unit = "px", x = lbl_x, y = cy + 40, w = W - 36, h = 10 },
            props = { text = "Uses selected Solar Panels + Daylight Sensor from Devices tab. No selection = tracker does nothing." },
            style = { font_size = 7, color = C.text_muted, align = "left" }
        })
        s:element({
            id = "mk1_low_output_help",
            type = "label",
            rect = { unit = "px", x = lbl_x, y = cy + 50, w = W - 36, h = 10 },
            props = { text = "LowOutPut: 0-100, parks at dusk. Higher = park earlier, 0 = always track." },
            style = { font_size = 7, color = C.text_muted, align = "left" }
        })
        s:element({
            id = "mk1_low_sun_help",
            type = "label",
            rect = { unit = "px", x = lbl_x, y = cy + 60, w = W - 36, h = 10 },
            props = { text = "LowSunAngle: low-sun threshold (deg); higher = lower sun." },
            style = { font_size = 7, color = C.text_muted, align = "left" }
        })

        local mk1_rows = {
            { id = "mk1_panel_port",  label = "Panel Port Pos (0=N,1=E,2=S,3=W):",    mem = MEM_MK1_PANEL_PORT,  min_v = 0, max_v = 3,   get = function() return mk1_PanelPortPos  end, inp = function() return settings_mk1_panel_port_input  end, set = function(v) mk1_PanelPortPos  = v; settings_mk1_panel_port_input  = tostring(v) end },
            { id = "mk1_sensor_port", label = "Sensor Port Pos (0=E,1=N,2=W,3=S):",  mem = MEM_MK1_SENSOR_PORT, min_v = 0, max_v = 3,   get = function() return mk1_SensorPortPos end, inp = function() return settings_mk1_sensor_port_input end, set = function(v) mk1_SensorPortPos = v; settings_mk1_sensor_port_input = tostring(v) end },
            { id = "mk1_pmode",       label = "pMode (0=Track / 1=Park / 2=Port):",   mem = MEM_MK1_PMODE,       min_v = 0, max_v = 2,   get = function() return mk1_pMode         end, inp = function() return settings_mk1_pmode_input       end, set = function(v) mk1_pMode         = v; settings_mk1_pmode_input       = tostring(v) end },
            { id = "mk1_low_output",  label = "Low Output Threshold % (0-100):",      mem = MEM_MK1_LOW_OUTPUT,  min_v = 0, max_v = 100, get = function() return mk1_LowOutPut     end, inp = function() return settings_mk1_low_output_input  end, set = function(v) mk1_LowOutPut     = v; settings_mk1_low_output_input  = tostring(v) end },
            { id = "mk1_low_sun",     label = "Low Sun Angle threshold (0-90):",      mem = MEM_MK1_LOW_SUN,     min_v = 0, max_v = 90,  get = function() return mk1_LowSunAngle   end, inp = function() return settings_mk1_low_sun_input     end, set = function(v) mk1_LowSunAngle   = v; settings_mk1_low_sun_input     = tostring(v) end },
        }
        local mr_gap = 4
        local mr_h   = 20
        for i, row in ipairs(mk1_rows) do
            local ry = cy + 74 + (i - 1) * (mr_h + mr_gap)
            s:element({
                id = row.id .. "_lbl",
                type = "label",
                rect = { unit = "px", x = lbl_x, y = ry + 2, w = inp_x - lbl_x - 4, h = 16 },
                props = { text = row.label },
                style = { font_size = 9, color = "#94A3B8", align = "left" }
            })
            s:element({
                id = row.id .. "_input",
                type = "textinput",
                rect = { unit = "px", x = inp_x, y = ry, w = inp_w, h = mr_h },
                props = { value = row.inp(), placeholder = tostring(row.get()) },
                on_change = function(newVal)
                    local numVal = tonumber(newVal)
                    if numVal == nil then return end
                    if numVal < row.min_v then numVal = row.min_v end
                    if numVal > row.max_v then numVal = row.max_v end
                    row.set(numVal)
                    write(row.mem, numVal)
                    dashboard_render()
                end
            })
        end
    end
end

-- ==================== MAIN RENDER ====================

dashboard_render = function(force_rebuild)
    if force_rebuild == nil then
        force_rebuild = true
    end

    local desired = view or "overview"
    if surfaces[desired] == nil then desired = "overview" end
    s = surfaces[desired]

    if force_rebuild or handles.view ~= desired then
        s:clear()
        reset_handles()

        s:element({
            id = "bg",
            type = "panel",
            rect = { unit = "px", x = 0, y = 0, w = W, h = H },
            style = { bg = C.bg }
        })

        render_header()
        render_nav_tabs()

        if desired == "overview" then
            render_overview()
        elseif desired == "settings" then
            render_settings()
        end

        render_footer()
        handles.view = desired
        ss.ui.activate(desired)
        s:commit()
        return
    end

    update_header_dynamic()
    update_nav_dynamic()
    update_footer_dynamic()
    if desired == "overview" then
        update_overview_dynamic()
    end

    ss.ui.activate(desired)
    s:commit()
end

set_view = function(name)
    local desired = name or "overview"
    if surfaces[desired] == nil then desired = "overview" end
    view = desired
    s = surfaces[desired]
    ss.ui.activate(desired)
    dashboard_render(true)
end

-- ==================== SERIALIZATION ====================

function serialize()
    local solidStr = solidForceState == true and "on" or solidForceState == false and "off" or "auto"
    local gasStr   = gasForceState   == true and "on" or gasForceState   == false and "off" or "auto"
    local state    = { view = view, solid = solidStr, gas = gasStr }
    local ok, json = pcall(util.json.encode, state)
    if not ok then return nil end
    return json
end

function deserialize(blob)
    if type(blob) ~= "string" or blob == "" then return end
    local ok, decoded = pcall(util.json.decode, blob)
    if not ok or type(decoded) ~= "table" then return end
    if type(decoded.view) == "string" then view = decoded.view end
    if decoded.solid == "on"  then solidForceState = true
    elseif decoded.solid == "off" then solidForceState = false
    else solidForceState = nil end
    if decoded.gas == "on"  then gasForceState = true
    elseif decoded.gas == "off" then gasForceState = false
    else gasForceState = nil end
end

-- ==================== BOOT ====================

initialize_settings()
load_force_states()
populate_piac_dropdown_cache()
set_view(view)

-- ==================== MAIN LOOP ====================

local tick = 0
while true do
    tick    = tick + 1
    elapsed = elapsed + 1
    currenttime = util.clock_time()


    update_auto_gen_state()
    apply_solid_override()
    apply_gas_override()
    tick_solar_mk1()

    if tick % LIVE_REFRESH_TICKS == 0 then
        read_wind()
        read_solar()
        read_solid_generators()
        read_gas_generators()
        read_presreg()
        read_battery()
        read_cable_analyzer()
        dashboard_render(false)
    end

    ic.yield()
end
