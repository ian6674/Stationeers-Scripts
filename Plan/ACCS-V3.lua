--##### ACCS V3 - РАСШИРЕННАЯ СИСТЕМА ЖИЗНЕОБЕСПЕЧЕНИЯ #####
-- ======================================================================
-- ACCS - AIR COMPOSITION & CONTROL SYSTEM (INDUSTRIAL LOGIC V3)
-- ======================================================================

local surfaces = {
    overview = ss.ui.surface("overview"),
    settings = ss.ui.surface("settings"),
    gases = ss.ui.surface("gases"),
    graphs = ss.ui.surface("graphs"),
    logs = ss.ui.surface("logs")
}
local s = surfaces.overview
local view = "overview"

local W, H = 480, 272
local size = ss.ui.surface("overview"):size()
if size then
    W = size.w or W
    H = size.h or H
end

local elapsed = 0
local BOX_COUNT = 8
local FAST_UPDATE_TICKS = 2
local SLOW_UPDATE_TICKS = 6
local HISTORY_SIZE = 60

-- Системные хеши префабов устройств
local SENSOR_HASH      = ic.hash("StructureGasSensor")
local ACTIVE_VENT_HASH = ic.hash("StructureActiveVent")
local CONSOLE_2X2_HASH = ic.hash("StructureConsole2x2")
local VALVE_HASH       = ic.hash("StructureDigitalValve")

local LT = ic.enums.LogicType
local LST = ic.enums.LogicSlotType
local LBM = ic.enums.LogicBatchMethod

-- Цветовые статусы комнат
local STATE_OFFLINE  = 0
local STATE_NOMINAL  = 1
local STATE_WARNING  = 2
local STATE_CRITICAL = 3
local STATE_EMERGENCY = 4

local C = {
    bg = "#080B14", panel = "#0D1222", panel_light = "#141B32", divider = "#1A234A",
    text = "#F1F5F9", text_dim = "#94A3B8", accent = "#38BDF8", green = "#10B981", 
    yellow = "#F59E0B", red = "#EF4444", orange = "#F97316", purple = "#8B5CF6"
}

-- Конфигурация комнат (все равнозначны, убрана логика теплицы)
local rooms_cfg = {
    { id = 1, name = "Зона 1", min_p = 100, max_p = 105, target_t = 293.15, mem_p = 0, mem_t = 1 },
    { id = 2, name = "Зона 2", min_p = 101, max_p = 106, target_t = 293.15, mem_p = 2, mem_t = 3 },
    { id = 3, name = "Зона 3", min_p = 95,  max_p = 100, target_t = 293.15, mem_p = 4, mem_t = 5 }, 
    { id = 4, name = "Зона 4", min_p = 101, max_p = 106, target_t = 293.15, mem_p = 6, mem_t = 7 }, 
    { id = 5, name = "Зона 5", min_p = 100, max_p = 105, target_t = 291.15, mem_p = 8, mem_t = 9 }, 
    { id = 6, name = "Зона 6", min_p = 100, max_p = 105, target_t = 291.15, mem_p = 10, mem_t = 11 }, 
    { id = 7, name = "Зона 7", min_p = 90,  max_p = 95,  target_t = 293.15, mem_p = 12, mem_t = 13 }, 
    { id = 8, name = "Зона 8", min_p = 90,  max_p = 95,  target_t = 293.15, mem_p = 14, mem_t = 15 }
}

-- ==================== ОПТИМИЗИРОВАННЫЕ СТРУКТУРЫ ДАННЫХ ====================

-- Единая структура данных для всех комнат
local room_state = {}
local history = {}
local formatted_cache = {}
local previous_display = {}
local log_entries = {}

for i = 1, BOX_COUNT do
    room_state[i] = {
        config = rooms_cfg[i],
        devices = {
            sensor = { prefab = 0, namehash = 0, sel = 0 },
            vent_in = { prefab = 0, namehash = 0, sel = 0 },
            vent_out = { prefab = 0, namehash = 0, sel = 0 },
            valve = { prefab = 0, namehash = 0, sel = 0 }
        },
        readings = {
            pressure = 0, temperature = 293.15,
            ratio_o2 = 0, ratio_n2 = 0, ratio_co2 = 0,
            ratio_pol = 0, ratio_n2o = 0, ratio_h2o = 0,
            ratio_ch4 = 0, ratio_h2 = 0,
            room_status = STATE_OFFLINE, is_online = false,
            emergency_type = nil
        },
        dropdown_open = { sensor = false, vent_in = false, vent_out = false, valve = false }
    }
    
    -- Инициализация истории для графиков
    history[i] = {
        pressure = {},
        temperature = {},
        o2 = {},
        n2 = {},
        co2 = {},
        pol = {},
        n2o = {},
        h2o = {},
        ch4 = {},
        h2 = {}
    }
    
    -- Инициализация предыдущего состояния для дельта-обновлений
    previous_display[i] = {
        pressure = 0, temperature = 0, o2 = 0, n2 = 0, co2 = 0,
        pol = 0, status = STATE_OFFLINE
    }
end

local cached_dropdowns = nil
local settings_page = 1
local settings_room_open = false
local base_global_status = STATE_NOMINAL
local log_counter = 0

-- Флаги для вкладки графиков
local graphs_initialized = false
local graph_chart_handle = nil

-- ==================== БЕЗОПАСНЫЕ ФУНКЦИИ API ====================

local function safe_batch_read_name(prefab, namehash, logic_type, method)
    if ic.batch_read_name == nil or prefab == nil or namehash == nil then return nil end
    local p, n = tonumber(prefab) or 0, tonumber(namehash) or 0
    if p == 0 or n == 0 then return nil end
    return ic.batch_read_name(p, n, logic_type, method)
end

local function safe_batch_write_name(prefab, namehash, logic_type, value)
    if ic.batch_write_name == nil or prefab == nil or namehash == nil or logic_type == nil or value == nil then return false end
    local p, n = tonumber(prefab) or 0, tonumber(namehash) or 0
    if p == 0 or n == 0 then return false end
    ic.batch_write_name(p, n, logic_type, value)
    return true
end

-- ==================== СИСТЕМА ЛОГИРОВАНИЯ ====================

local function add_log_entry(room_id, event_type, message, value)
    log_counter = log_counter + 1
    table.insert(log_entries, {
        id = log_counter,
        time = os.date("%H:%M:%S"),
        room = room_id,
        type = event_type,
        message = message,
        value = value
    })
    
    -- Ограничиваем размер лога
    if #log_entries > 200 then
        table.remove(log_entries, 1)
    end
    
    -- Сохраняем в persist
    if ic.persist then
        local log_data = { entries = log_entries, counter = log_counter }
        local ok, json_str = pcall(util.json.encode, log_data)
        if ok and json_str then
            ic.persist.set("accs_log_v3", json_str)
        end
    end
end

local function load_logs()
    if ic.persist and ic.persist.has("accs_log_v3") then
        local saved_str = ic.persist.get("accs_log_v3")
        if type(saved_str) == "string" and saved_str ~= "" then
            local ok, decoded = pcall(util.json.decode, saved_str)
            if ok and type(decoded) == "table" then
                if type(decoded.entries) == "table" then
                    log_entries = decoded.entries
                    log_counter = decoded.counter or #log_entries
                end
            end
        end
    end
end

-- ==================== ОПТИМИЗИРОВАННОЕ КЕШИРОВАНИЕ ====================

local function get_cached_string(format_str, value)
    local key = format_str .. tostring(value)
    if not formatted_cache[key] then
        formatted_cache[key] = string.format(format_str, value)
    end
    return formatted_cache[key]
end

local function clear_cache()
    formatted_cache = {}
end

-- ==================== СОХРАНЕНИЕ И ЗАГРУЗКА ====================

local function save_settings_to_storage()
    -- Сохраняем конфигурацию
    for i = 1, BOX_COUNT do
        local cfg = rooms_cfg[i]
        if cfg then
            mem_write(cfg.mem_p, cfg.min_p)
            mem_write(cfg.mem_t, math.floor(cfg.target_t * 100))
        end
    end

    -- Сохраняем устройства и конфиг
    if ic.persist then
        local state = { 
            devices = {}, 
            rooms = {},
            history = history 
        }
        for i = 1, BOX_COUNT do
            state.devices[i] = room_state[i].devices
            state.rooms[i] = { 
                name = rooms_cfg[i].name, 
                min_p = rooms_cfg[i].min_p, 
                max_p = rooms_cfg[i].max_p, 
                target_t = rooms_cfg[i].target_t 
            }
        end
        local ok, json_str = pcall(util.json.encode, state)
        if ok and json_str then 
            ic.persist.set("accs_data_v3", json_str) 
        end
    end
end

local function initialize_settings()
    -- Загружаем из persist
    local persist_loaded = false
    if ic.persist and ic.persist.has("accs_data_v3") then
        local saved_str = ic.persist.get("accs_data_v3")
        if type(saved_str) == "string" and saved_str ~= "" then
            local ok, decoded = pcall(util.json.decode, saved_str)
            if ok and type(decoded) == "table" then
                if type(decoded.devices) == "table" then
                    for i = 1, BOX_COUNT do
                        if decoded.devices[i] then
                            room_state[i].devices = decoded.devices[i]
                        end
                    end
                end
                if type(decoded.rooms) == "table" then
                    for i = 1, BOX_COUNT do
                        if decoded.rooms[i] then
                            rooms_cfg[i].name = decoded.rooms[i].name or rooms_cfg[i].name
                            rooms_cfg[i].min_p = tonumber(decoded.rooms[i].min_p) or rooms_cfg[i].min_p
                            rooms_cfg[i].max_p = tonumber(decoded.rooms[i].max_p) or rooms_cfg[i].max_p
                            rooms_cfg[i].target_t = tonumber(decoded.rooms[i].target_t) or rooms_cfg[i].target_t
                        end
                    end
                end
                if type(decoded.history) == "table" then
                    history = decoded.history
                end
                persist_loaded = true
            end
        end
    end

    -- Загружаем логи
    load_logs()

    -- Страховочный контур из памяти
    for i = 1, BOX_COUNT do
        local cfg = rooms_cfg[i]
        local backup_p = mem_read(cfg.mem_p)
        local backup_t = mem_read(cfg.mem_t)
        
        if backup_p and backup_p > 0 then
            rooms_cfg[i].min_p = backup_p
            rooms_cfg[i].max_p = backup_p + 5
        end
        
        if backup_t and backup_t >= 27315 then
            rooms_cfg[i].target_t = backup_t / 100
        else
            rooms_cfg[i].target_t = 293.15
        end
    end
    return persist_loaded
end

-- ==================== ПОЛУЧЕНИЕ СПИСКА УСТРОЙСТВ ====================

local function populate_device_caches()
    local ok, devs = pcall(device_list)
    if not ok or devs == nil then devs = {} end
    cached_dropdowns = { 
        sensor = { "Выбрать Датчик..." }, 
        vent = { "Выбрать Вентилятор..." }, 
        valve = { "Выбрать Клапан..." } 
    }
    cached_dropdowns.sensor_devs = {} 
    cached_dropdowns.vent_devs = {} 
    cached_dropdowns.valve_devs = {}

    for _, dev in ipairs(devs) do
        local label = tostring(dev.display_name or "Устройство"):gsub("|", "/")
        local ph = tonumber(dev.prefab_hash) or 0
        if ph == SENSOR_HASH then
            table.insert(cached_dropdowns.sensor, label)
            table.insert(cached_dropdowns.sensor_devs, dev)
        elseif ph == ACTIVE_VENT_HASH then
            table.insert(cached_dropdowns.vent, label)
            table.insert(cached_dropdowns.vent_devs, dev)
        elseif ph == VALVE_HASH then
            table.insert(cached_dropdowns.valve, label)
            table.insert(cached_dropdowns.valve_devs, dev)
        end
    end
end

-- ==================== ОПТИМИЗИРОВАННОЕ ОБНОВЛЕНИЕ ДАННЫХ ====================

local function calculate_room_status(i)
    local data = room_state[i].readings
    local cfg = room_state[i].config
    
    -- Проверяем критические условия
    if data.pressure < 30 then
        data.emergency_type = "DEPRESSURIZATION"
        return STATE_EMERGENCY
    end
    
    -- Проверяем токсичные газы (все кроме N2, O2, CO2)
    local toxic_total = data.ratio_pol + data.ratio_n2o + data.ratio_h2o + 
                        data.ratio_ch4 + data.ratio_h2
    if toxic_total > 0.005 then
        data.emergency_type = "TOXIC"
        return STATE_EMERGENCY
    end
    
    -- Проверяем предупреждения
    if data.pressure < cfg.min_p or data.pressure > cfg.max_p then
        data.emergency_type = nil
        return STATE_WARNING
    end
    
    if data.ratio_o2 < 0.18 then
        data.emergency_type = nil
        return STATE_WARNING
    end
    
    data.emergency_type = nil
    return STATE_NOMINAL
end

local function update_history(i)
    local data = room_state[i].readings
    local hist = history[i]
    
    table.insert(hist.pressure, data.pressure)
    table.insert(hist.temperature, data.temperature)
    table.insert(hist.o2, data.ratio_o2 * 100)
    table.insert(hist.n2, data.ratio_n2 * 100)
    table.insert(hist.co2, data.ratio_co2 * 100)
    table.insert(hist.pol, data.ratio_pol * 1000)
    table.insert(hist.n2o, data.ratio_n2o * 1000)
    table.insert(hist.h2o, data.ratio_h2o * 1000)
    table.insert(hist.ch4, data.ratio_ch4 * 1000)
    table.insert(hist.h2, data.ratio_h2 * 1000)
    
    -- Ограничиваем размер истории
    if #hist.pressure > HISTORY_SIZE then
        table.remove(hist.pressure, 1)
        table.remove(hist.temperature, 1)
        table.remove(hist.o2, 1)
        table.remove(hist.n2, 1)
        table.remove(hist.co2, 1)
        table.remove(hist.pol, 1)
        table.remove(hist.n2o, 1)
        table.remove(hist.h2o, 1)
        table.remove(hist.ch4, 1)
        table.remove(hist.h2, 1)
    end
end

local function refresh_accs_readings()
    base_global_status = STATE_NOMINAL
    
    for i = 1, BOX_COUNT do
        local dev = room_state[i].devices.sensor
        if tonumber(dev.prefab) ~= 0 and tonumber(dev.namehash) ~= 0 then
            local status, err = pcall(function()
                local p = safe_batch_read_name(dev.prefab, dev.namehash, LT.Pressure, LBM.Average)
                if p and p > 0 then
                    local data = room_state[i].readings
                    data.pressure = p
                    data.temperature = safe_batch_read_name(dev.prefab, dev.namehash, LT.Temperature, LBM.Average) or 293.15
                    data.ratio_o2 = safe_batch_read_name(dev.prefab, dev.namehash, LT.RatioOxygen, LBM.Average) or 0
                    data.ratio_n2 = safe_batch_read_name(dev.prefab, dev.namehash, LT.RatioNitrogen, LBM.Average) or 0
                    data.ratio_co2 = safe_batch_read_name(dev.prefab, dev.namehash, LT.RatioCarbonDioxide, LBM.Average) or 0
                    data.ratio_pol = safe_batch_read_name(dev.prefab, dev.namehash, LT.RatioPollutant, LBM.Average) or 0
                    data.ratio_n2o = safe_batch_read_name(dev.prefab, dev.namehash, LT.RatioNitrousOxide, LBM.Average) or 0
                    data.ratio_h2o = safe_batch_read_name(dev.prefab, dev.namehash, LT.RatioWater, LBM.Average) or 0
                    data.ratio_ch4 = safe_batch_read_name(dev.prefab, dev.namehash, LT.RatioMethane, LBM.Average) or 0
                    data.ratio_h2 = safe_batch_read_name(dev.prefab, dev.namehash, LT.RatioHydrogen, LBM.Average) or 0
                    data.is_online = true
                    
                    -- Логируем изменения статуса
                    local old_status = data.room_status
                    data.room_status = calculate_room_status(i)
                    
                    -- Логируем критические события
                    if data.room_status == STATE_EMERGENCY and old_status ~= STATE_EMERGENCY then
                        local msg = data.emergency_type == "DEPRESSURIZATION" and 
                            "Разгерметизация!" or "Токсичные газы!"
                        add_log_entry(i, "EMERGENCY", msg, string.format("P:%.0f кПа", data.pressure))
                    elseif data.room_status == STATE_WARNING and old_status ~= STATE_WARNING then
                        add_log_entry(i, "WARNING", "Отклонение параметров", 
                            string.format("P:%.0f кПа, O2:%.1f%%", data.pressure, data.ratio_o2 * 100))
                    elseif data.room_status == STATE_NOMINAL and old_status ~= STATE_NOMINAL then
                        add_log_entry(i, "INFO", "Параметры в норме", "")
                    end
                    
                    -- Обновляем историю для графиков
                    if elapsed % SLOW_UPDATE_TICKS == 0 then
                        update_history(i)
                    end
                else
                    local data = room_state[i].readings
                    data.is_online = false
                    if data.room_status ~= STATE_OFFLINE then
                        add_log_entry(i, "WARNING", "Датчик не отвечает", "")
                    end
                    data.room_status = STATE_OFFLINE
                    data.emergency_type = nil
                end
            end)
            if not status then 
                local data = room_state[i].readings
                data.is_online = false
                data.room_status = STATE_OFFLINE
                data.emergency_type = nil
            end
        else
            local data = room_state[i].readings
            data.is_online = false
            data.room_status = STATE_OFFLINE
            data.emergency_type = nil
        end

        -- Обновляем глобальный статус
        if room_state[i].readings.room_status == STATE_EMERGENCY then 
            base_global_status = STATE_EMERGENCY
        elseif room_state[i].readings.room_status == STATE_CRITICAL then 
            base_global_status = STATE_CRITICAL
        elseif room_state[i].readings.room_status == STATE_WARNING and 
               base_global_status ~= STATE_EMERGENCY and 
               base_global_status ~= STATE_CRITICAL then 
            base_global_status = STATE_WARNING 
        end
    end
end

-- ==================== РАСШИРЕННАЯ ЛОГИКА УПРАВЛЕНИЯ ====================

local function execute_accs_logic()
    for i = 1, BOX_COUNT do
        local cfg = room_state[i].config
        local data = room_state[i].readings
        local dev = room_state[i].devices
        local v_in = dev.vent_in
        local v_out = dev.vent_out
        local v_valve = dev.valve

        if data.is_online then
            -- Аварийные сценарии
            if data.room_status == STATE_EMERGENCY then
                if data.emergency_type == "DEPRESSURIZATION" then
                    -- При разгерметизации: отключаем всё, закрываем клапаны
                    safe_batch_write_name(v_in.prefab, v_in.namehash, LT.On, 0)
                    safe_batch_write_name(v_out.prefab, v_out.namehash, LT.On, 0)
                    safe_batch_write_name(v_valve.prefab, v_valve.namehash, LT.On, 0)
                    safe_batch_write_name(v_valve.prefab, v_valve.namehash, LT.Setting, 0)
                elseif data.emergency_type == "TOXIC" then
                    -- При токсичных газах: полная вентиляция
                    safe_batch_write_name(v_in.prefab, v_in.namehash, LT.On, 1)
                    safe_batch_write_name(v_in.prefab, v_in.namehash, LT.Mode, 1)
                    safe_batch_write_name(v_in.prefab, v_in.namehash, LT.Setting, 100)
                    safe_batch_write_name(v_out.prefab, v_out.namehash, LT.On, 1)
                    safe_batch_write_name(v_out.prefab, v_out.namehash, LT.Mode, 0)
                    safe_batch_write_name(v_out.prefab, v_out.namehash, LT.Setting, 100)
                end
            else
                -- Нормальное управление давлением
                if data.pressure < cfg.min_p then
                    safe_batch_write_name(v_in.prefab, v_in.namehash, LT.On, 1)
                    safe_batch_write_name(v_in.prefab, v_in.namehash, LT.Mode, 0)
                    safe_batch_write_name(v_in.prefab, v_in.namehash, LT.Setting, 30)
                    safe_batch_write_name(v_out.prefab, v_out.namehash, LT.On, 0)
                elseif data.pressure > cfg.max_p then
                    safe_batch_write_name(v_out.prefab, v_out.namehash, LT.On, 1)
                    safe_batch_write_name(v_out.prefab, v_out.namehash, LT.Mode, 1)
                    safe_batch_write_name(v_out.prefab, v_out.namehash, LT.Setting, 50)
                    safe_batch_write_name(v_in.prefab, v_in.namehash, LT.On, 0)
                else
                    safe_batch_write_name(v_in.prefab, v_in.namehash, LT.On, 0)
                    safe_batch_write_name(v_out.prefab, v_out.namehash, LT.On, 0)
                end

                -- Управление температурой с гистерезисом
                if tonumber(v_valve.prefab) ~= 0 and tonumber(v_valve.namehash) ~= 0 then
                    if data.temperature > (cfg.target_t + 0.5) then
                        safe_batch_write_name(v_valve.prefab, v_valve.namehash, LT.On, 1)
                        safe_batch_write_name(v_valve.prefab, v_valve.namehash, LT.Setting, 100)
                    elseif data.temperature < (cfg.target_t - 0.5) then
                        safe_batch_write_name(v_valve.prefab, v_valve.namehash, LT.On, 0)
                        safe_batch_write_name(v_valve.prefab, v_valve.namehash, LT.Setting, 0)
                    end
                end
            end
        else
            -- Если датчик офлайн - выключаем всё
            safe_batch_write_name(v_in.prefab, v_in.namehash, LT.On, 0)
            safe_batch_write_name(v_out.prefab, v_out.namehash, LT.On, 0)
            safe_batch_write_name(v_valve.prefab, v_valve.namehash, LT.On, 0)
        end
    end
end

-- ==================== UI: ОБНОВЛЕНИЕ КОНСОЛИ ====================

local function update_hardware_console()
    local name_hash = ic.hash("Central_ACCS_Console")
    local room_idx = settings_page or 1
    local data = room_state[room_idx] and room_state[room_idx].readings
    
    if data == nil then return end

    local room_status = base_global_status == STATE_NOMINAL and data.room_status or base_global_status

    local hardware_color = 0
    if room_status == STATE_NOMINAL then hardware_color = 2
    elseif room_status == STATE_WARNING then hardware_color = 1
    elseif room_status == STATE_EMERGENCY or room_status == STATE_CRITICAL then hardware_color = 4
    end

    safe_batch_write_name(CONSOLE_2X2_HASH, name_hash, LT.Color, hardware_color)
    safe_batch_write_name(CONSOLE_2X2_HASH, name_hash, LT.Mode, data.is_online and math.floor(data.pressure) or 0)
end

-- ==================== UI: СТАТУСЫ И ЦВЕТА ====================

local function get_status_color(status)
    if status == STATE_NOMINAL then return C.green end
    if status == STATE_WARNING then return C.yellow end
    if status == STATE_CRITICAL then return C.red end
    if status == STATE_EMERGENCY then return C.orange end
    return C.text_dim
end

local function get_status_text(status)
    if status == STATE_NOMINAL then return "НОРМА" end
    if status == STATE_WARNING then return "ПРЕДУПР." end
    if status == STATE_CRITICAL then return "КРИТИЧ." end
    if status == STATE_EMERGENCY then return "АВАРИЯ" end
    return "ОТКЛЮЧ."
end

-- ==================== UI: ВКЛАДКА ОБЗОР ====================

local function render_overview_delta()
    -- Очищаем только если нужно полное обновление
    if elapsed % (FAST_UPDATE_TICKS * 2) == 0 then
        s:clear()
        -- Фон
        s:element({ id = "main_bg", type = "panel", rect = { unit = "px", x = 0, y = 0, w = W, h = H }, style = { bg = C.bg } })
        s:element({ id = "header_title", type = "label", rect = { unit = "px", x = 12, y = 8, w = 300, h = 18 }, 
            props = { text = "ACCS V3 - Air Control & Composition System" }, 
            style = { font_size = 12, color = C.accent, align = "left" } })
    end

    local start_x = 10
    local start_y = 54   
    local row_h = 44   
    local border_gap = 2

    local col_room_w = 65
    local col_p_w = 50
    local col_t_w = 50
    local col_o2_w = 50
    local col_n2_w = 50
    local col_co2_w = 50
    local col_status_w = 65

    local x_room = start_x
    local x_p = x_room + col_room_w + border_gap
    local x_t = x_p + col_p_w + border_gap
    local x_o2 = x_t + col_t_w + border_gap
    local x_n2 = x_o2 + col_o2_w + border_gap
    local x_co2 = x_n2 + col_n2_w + border_gap
    local x_status = x_co2 + col_co2_w + border_gap

    -- Перерисовываем заголовки только при полном обновлении
    if elapsed % (FAST_UPDATE_TICKS * 2) == 0 then
        s:element({ id = "h_col_room", type = "label", rect = { unit = "px", x = x_room, y = start_y, w = col_room_w, h = 14 }, 
            props = { text = "ЗОНА" }, style = { font_size = 10, color = C.accent, align = "center" } })
        s:element({ id = "h_col_p", type = "label", rect = { unit = "px", x = x_p, y = start_y, w = col_p_w, h = 14 }, 
            props = { text = "P" }, style = { font_size = 10, color = C.accent, align = "center" } })
        s:element({ id = "h_col_t", type = "label", rect = { unit = "px", x = x_t, y = start_y, w = col_t_w, h = 14 }, 
            props = { text = "T" }, style = { font_size = 10, color = C.accent, align = "center" } })
        s:element({ id = "h_col_o2", type = "label", rect = { unit = "px", x = x_o2, y = start_y, w = col_o2_w, h = 14 }, 
            props = { text = "O₂" }, style = { font_size = 10, color = C.accent, align = "center" } })
        s:element({ id = "h_col_n2", type = "label", rect = { unit = "px", x = x_n2, y = start_y, w = col_n2_w, h = 14 }, 
            props = { text = "N₂" }, style = { font_size = 10, color = C.accent, align = "center" } })
        s:element({ id = "h_col_co2", type = "label", rect = { unit = "px", x = x_co2, y = start_y, w = col_co2_w, h = 14 }, 
            props = { text = "CO₂" }, style = { font_size = 10, color = C.accent, align = "center" } })
        s:element({ id = "h_col_status", type = "label", rect = { unit = "px", x = x_status, y = start_y, w = col_status_w, h = 14 }, 
            props = { text = "СТАТУС" }, style = { font_size = 10, color = C.accent, align = "center" } })
    end

    local data_start_y = start_y + 16

    for i = 1, BOX_COUNT do
        local data = room_state[i].readings
        local cur_y = data_start_y + (i - 1) * row_h
        local text_color = get_status_color(data.room_status)
        
        -- Проверяем, изменились ли данные
        local changed = false
        if previous_display[i].pressure ~= data.pressure or
           previous_display[i].temperature ~= data.temperature or
           previous_display[i].o2 ~= data.ratio_o2 or
           previous_display[i].status ~= data.room_status then
            changed = true
        end
        
        if changed or elapsed % (FAST_UPDATE_TICKS * 2) == 0 then
            -- Обновляем панель только если изменилась
            s:element({ id = "row_panel_" .. i, type = "panel", 
                rect = { unit = "px", x = start_x, y = cur_y, w = W - 20, h = row_h - 2 }, 
                style = { bg = C.panel, border_color = data.room_status == STATE_EMERGENCY and C.orange or "#121A30", border_width = data.room_status == STATE_EMERGENCY and 2 or 1 } })
            
            -- Имя комнаты
            s:element({ id = "r_name_" .. i, type = "label", 
                rect = { unit = "px", x = x_room + 2, y = cur_y + 15, w = col_room_w - 2, h = 14 }, 
                props = { text = rooms_cfg[i].name }, 
                style = { font_size = 11, color = text_color, align = "center" } })
            
            -- Данные
            local p_txt = data.is_online and string.format("%.0f", data.pressure) or "--"
            local t_txt = data.is_online and string.format("%.1f", data.temperature - 273.15) or "--"
            local o2_txt = data.is_online and string.format("%.1f", data.ratio_o2 * 100) or "--"
            local n2_txt = data.is_online and string.format("%.1f", data.ratio_n2 * 100) or "--"
            local co2_txt = data.is_online and string.format("%.1f", data.ratio_co2 * 100) or "--"
            
            s:element({ id = "r_p_" .. i, type = "label", 
                rect = { unit = "px", x = x_p, y = cur_y + 14, w = col_p_w, h = 16 }, 
                props = { text = p_txt }, 
                style = { font_size = 12, color = C.text, align = "center" } })
            s:element({ id = "r_t_" .. i, type = "label", 
                rect = { unit = "px", x = x_t, y = cur_y + 14, w = col_t_w, h = 16 }, 
                props = { text = t_txt }, 
                style = { font_size = 12, color = C.yellow, align = "center" } })
            s:element({ id = "r_o2_" .. i, type = "label", 
                rect = { unit = "px", x = x_o2, y = cur_y + 14, w = col_o2_w, h = 16 }, 
                props = { text = o2_txt }, 
                style = { font_size = 12, color = C.accent, align = "center" } })
            s:element({ id = "r_n2_" .. i, type = "label", 
                rect = { unit = "px", x = x_n2, y = cur_y + 14, w = col_n2_w, h = 16 }, 
                props = { text = n2_txt }, 
                style = { font_size = 12, color = C.text_dim, align = "center" } })
            s:element({ id = "r_co2_" .. i, type = "label", 
                rect = { unit = "px", x = x_co2, y = cur_y + 14, w = col_co2_w, h = 16 }, 
                props = { text = co2_txt }, 
                style = { font_size = 12, color = C.green, align = "center" } })
            
            -- Статус
            local status_text = data.is_online and get_status_text(data.room_status) or "OFF"
            local status_color = data.is_online and text_color or C.text_dim
            s:element({ id = "r_status_" .. i, type = "label", 
                rect = { unit = "px", x = x_status, y = cur_y + 14, w = col_status_w, h = 16 }, 
                props = { text = status_text }, 
                style = { font_size = 10, color = status_color, align = "center" } })
            
            -- Сохраняем предыдущее состояние
            previous_display[i].pressure = data.pressure
            previous_display[i].temperature = data.temperature
            previous_display[i].o2 = data.ratio_o2
            previous_display[i].n2 = data.ratio_n2
            previous_display[i].co2 = data.ratio_co2
            previous_display[i].status = data.room_status
        end
    end
    s:commit()
end

-- ==================== UI: ВКЛАДКА ГАЗЫ ====================

local gases_s = surfaces.gases

local function render_gases()
    gases_s:clear()
    gases_s:element({ id = "gases_bg", type = "panel", rect = { unit = "px", x = 0, y = 0, w = W, h = H }, style = { bg = C.bg } })
    gases_s:element({ id = "gases_title", type = "label", rect = { unit = "px", x = 12, y = 8, w = 300, h = 18 }, 
        props = { text = "ACCS V3 - Мониторинг газов" }, 
        style = { font_size = 12, color = C.accent, align = "left" } })
    
    -- Селектор комнаты для вкладки газы
    gases_s:element({ id = "gases_room_lbl", type = "label", 
        rect = { unit = "px", x = 12, y = 28, w = 80, h = 14 }, 
        props = { text = "Комната:" }, 
        style = { font_size = 10, color = C.text, align = "left" } })
    
    local room_names = {}
    for i = 1, BOX_COUNT do
        table.insert(room_names, rooms_cfg[i].name)
    end
    gases_s:element({
        id = "gases_room_select",
        type = "select",
        rect = { unit = "px", x = 90, y = 28, w = 120, h = 18 },
        props = { options = table.concat(room_names, "|"), selected = settings_page - 1 },
        on_change = function(opt)
            settings_page = (tonumber(opt) or 0) + 1
            render_gases()
            draw_navigation_tabs()
        end
    })
    
    local room_idx = settings_page
    local data = room_state[room_idx].readings
    
    local start_x = 10
    local start_y = 54
    local row_h = 26
    local col_w = 55
    
    -- Заголовки газов с единицами измерения
    local gas_headers = {
        { name = "O₂", unit = "%", color = C.accent },
        { name = "N₂", unit = "%", color = C.text_dim },
        { name = "CO₂", unit = "%", color = C.green },
        { name = "POL", unit = "‰", color = C.red },
        { name = "N₂O", unit = "‰", color = C.purple },
        { name = "H₂O", unit = "‰", color = C.accent },
        { name = "CH₄", unit = "‰", color = C.yellow },
        { name = "H₂", unit = "‰", color = C.orange }
    }
    
    -- Заголовки
    for g = 1, #gas_headers do
        local x = start_x + (g - 1) * col_w
        gases_s:element({ id = "g_header_" .. g, type = "label", 
            rect = { unit = "px", x = x, y = start_y, w = col_w, h = 14 }, 
            props = { text = gas_headers[g].name .. " (" .. gas_headers[g].unit .. ")" }, 
            style = { font_size = 9, color = gas_headers[g].color, align = "center" } })
    end
    
    -- Данные по комнатам
    for i = 1, BOX_COUNT do
        local room_data = room_state[i].readings
        local cur_y = start_y + 18 + (i - 1) * row_h
        
        -- Имя комнаты
        gases_s:element({ id = "g_room_" .. i, type = "label", 
            rect = { unit = "px", x = start_x - 55, y = cur_y + 3, w = 50, h = 16 }, 
            props = { text = rooms_cfg[i].name }, 
            style = { font_size = 9, color = C.text, align = "right" } })
        
        -- Панель статуса комнаты
        local status_color = get_status_color(room_data.room_status)
        gases_s:element({ id = "g_status_dot_" .. i, type = "panel", 
            rect = { unit = "px", x = start_x - 8, y = cur_y + 5, w = 6, h = 6 }, 
            style = { bg = room_data.is_online and status_color or C.text_dim } })
        
        -- Значения газов
        local gas_values = {
            room_data.ratio_o2 * 100,
            room_data.ratio_n2 * 100,
            room_data.ratio_co2 * 100,
            room_data.ratio_pol * 1000,
            room_data.ratio_n2o * 1000,
            room_data.ratio_h2o * 1000,
            room_data.ratio_ch4 * 1000,
            room_data.ratio_h2 * 1000
        }
        
        for g = 1, #gas_values do
            local x = start_x + (g - 1) * col_w
            local val = room_data.is_online and string.format("%.1f", gas_values[g]) or "--"
            local color = room_data.is_online and C.text or C.text_dim
            -- Подсветка для опасных значений
            if g == 1 and room_data.is_online and gas_values[g] < 18 then color = C.red end
            if g == 3 and room_data.is_online and gas_values[g] > 5 then color = C.yellow end
            if g >= 4 and room_data.is_online and gas_values[g] > 1 then color = C.orange end
            
            gases_s:element({ id = "g_val_" .. i .. "_" .. g, type = "label", 
                rect = { unit = "px", x = x, y = cur_y, w = col_w, h = 18 }, 
                props = { text = val }, 
                style = { font_size = 10, color = color, align = "center" } })
        end
    end
    
    gases_s:commit()
end

-- ==================== UI: ВКЛАДКА ГРАФИКИ (исправленная с linechart) ====================

local graphs_s = surfaces.graphs
local graphs_initialized = false
local graph_chart_handle = nil
local graph_select_handle = nil  -- Глобальный handle для селектора

-- Функция обновления данных графиков с использованием linechart
local function render_graphs_data()
    local room_idx = settings_page
    local hist = history[room_idx]
    local data = room_state[room_idx].readings
    
    -- Подготавливаем данные для linechart
    local series_data = {}
    local series_colors = {}
    local series_labels = {}
    
    -- Давление (синий) - #3B82F6
    table.insert(series_data, hist and hist.pressure or {})
    table.insert(series_colors, "#3B82F6")
    table.insert(series_labels, "P кПа")
    
    -- Температура (жёлтый) - переводим в °C, значения ниже 0 заменяем на 0 для графика
    local temp_series = {}
    if hist and hist.temperature then
        for _, v in ipairs(hist.temperature) do
            local temp_c = v - 273.15
            table.insert(temp_series, math.max(0, temp_c))  -- Зануляем отрицательные
        end
    end
    table.insert(series_data, temp_series)
    table.insert(series_colors, "#F59E0B")
    table.insert(series_labels, "T °C")
    
    -- O₂ (голубой) - #06B6D4
    table.insert(series_data, hist and hist.o2 or {})
    table.insert(series_colors, "#06B6D4")
    table.insert(series_labels, "O₂%")
    
    -- CO₂ (зелёный) - #22C55E
    table.insert(series_data, hist and hist.co2 or {})
    table.insert(series_colors, "#22C55E")
    table.insert(series_labels, "CO₂%")
    
    -- POL (красный) - #EF4444
    table.insert(series_data, hist and hist.pol or {})
    table.insert(series_colors, "#EF4444")
    table.insert(series_labels, "POL‰")
    
    -- N₂ (серый) - #94A3B8
    table.insert(series_data, hist and hist.n2 or {})
    table.insert(series_colors, "#94A3B8")
    table.insert(series_labels, "N₂%")
    
    -- N₂O (фиолетовый) - #8B5CF6
    table.insert(series_data, hist and hist.n2o or {})
    table.insert(series_colors, "#8B5CF6")
    table.insert(series_labels, "N₂O‰")
    
    -- H₂O (бирюзовый) - #14B8A6
    table.insert(series_data, hist and hist.h2o or {})
    table.insert(series_colors, "#14B8A6")
    table.insert(series_labels, "H₂O‰")
    
    -- CH₄ (жёлтый) - #EAB308
    table.insert(series_data, hist and hist.ch4 or {})
    table.insert(series_colors, "#EAB308")
    table.insert(series_labels, "CH₄‰")
    
    -- H₂ (оранжевый) - #F97316
    table.insert(series_data, hist and hist.h2 or {})
    table.insert(series_colors, "#F97316")
    table.insert(series_labels, "H₂‰")
    
    -- Обновляем график через set_props
    if graph_chart_handle then
        graph_chart_handle:set_props({
            series = series_data,
            series_colors = series_colors,
            series_labels = series_labels,
            min = nil,  -- авто-масштабирование
            max = nil,  -- авто-масштабирование
        })
    end
    
    -- Определяем цвет для температуры в информационной строке
    local temp_c = (data.temperature or 293.15) - 273.15
    local temp_color = C.text
    if temp_c < 0 then
        temp_color = "#38BDF8"  -- светло-синий
    elseif temp_c < 15 then
        temp_color = "#22D3EE"  -- голубой
    elseif temp_c < 25 then
        temp_color = "#22C55E"  -- зелёный
    elseif temp_c < 35 then
        temp_color = "#EAB308"  -- жёлтый
    elseif temp_c < 55 then
        temp_color = "#F97316"  -- оранжевый
    else
        temp_color = "#EF4444"  -- красный
    end
    
    -- Информационная строка с цветной температурой (используем два элемента)
    -- Базовая часть
    graphs_s:element({
        id = "graph_info_base",
        type = "label",
        rect = { unit = "px", x = 10, y = H - 24, w = W - 20, h = 14 },
        props = {
            text = string.format(
                "P=%.0f кПа | T=",
                data.pressure or 0
            )
        },
        style = { font_size = 8, color = C.text_dim, align = "left" }
    })
    
    -- Значение температуры с цветом (поверх базовой части)
    graphs_s:element({
        id = "graph_info_temp",
        type = "label",
        rect = { unit = "px", x = 10 + string.len(string.format("P=%.0f кПа | T=", data.pressure or 0)) * 5, y = H - 24, w = 80, h = 14 },
        props = {
            text = string.format("%.1f°C", temp_c)
        },
        style = { font_size = 8, color = temp_color, align = "left" }
    })
    
    -- Остальная часть
    graphs_s:element({
        id = "graph_info_rest",
        type = "label",
        rect = { unit = "px", x = 10 + string.len(string.format("P=%.0f кПа | T=%.1f°C", data.pressure or 0, temp_c)) * 5, y = H - 24, w = 300, h = 14 },
        props = {
            text = string.format(
                " | O₂=%.1f%% | CO₂=%.1f%% | POL=%.1f‰ | N₂=%.1f%%",
                (data.ratio_o2 or 0) * 100,
                (data.ratio_co2 or 0) * 100,
                (data.ratio_pol or 0) * 1000,
                (data.ratio_n2 or 0) * 100
            )
        },
        style = { font_size = 8, color = C.text_dim, align = "left" }
    })
    
    graphs_s:commit()
end

-- Функция отрисовки структуры (вызывается один раз)
local function render_graphs_structure()
    graphs_s:clear()
    
    -- Фон
    graphs_s:element({
        id = "graphs_bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = H },
        style = { bg = C.bg }
    })
    
    -- Заголовок
    graphs_s:element({
        id = "graphs_title",
        type = "label",
        rect = { unit = "px", x = 12, y = 8, w = 300, h = 18 },
        props = { text = "ACCS V3 - Графики трендов" },
        style = { font_size = 12, color = C.accent, align = "left" }
    })
    
    -- Селектор комнаты
    local selector_y = 54
    
    graphs_s:element({
        id = "graph_room_lbl",
        type = "label",
        rect = { unit = "px", x = 12, y = selector_y + 2, w = 60, h = 14 },
        props = { text = "Комната:" },
        style = { font_size = 10, color = C.text, align = "left" }
    })
    
    local room_names = {}
    for i = 1, BOX_COUNT do
        table.insert(room_names, rooms_cfg[i].name)
    end
    
    -- Создаём селектор и сохраняем handle в глобальную переменную
    graph_select_handle = graphs_s:element({
        id = "graph_room_select",
        type = "select",
        rect = { unit = "px", x = 75, y = selector_y, w = 130, h = 18 },
        props = {
            options = table.concat(room_names, "|"),
            selected = settings_page - 1,
            open = false
        },
        style = { z_index = 10 },
        on_change = function(opt)
            local new_room = (tonumber(opt) or 0) + 1
            if new_room ~= settings_page then
                settings_page = new_room
                -- Обновляем selected у селектора через глобальный handle
                if graph_select_handle then
                    graph_select_handle:set_props({ selected = settings_page - 1 })
                end
                -- Обновляем данные графика
                render_graphs_data()
            end
        end
    })
    
    -- Основной график (linechart) с fill = "false"
    graph_chart_handle = graphs_s:element({
        id = "graph_main_chart",
        type = "linechart",
        rect = { unit = "px", x = 10, y = 78, w = W - 20, h = H - 130 },
        props = {
            capacity = 60,
            series = {},
            series_colors = {},
            series_labels = {},
            min = nil,
            max = nil,
        },
        style = {
            bg = C.panel,
            show_grid = "true",
            show_legend = "true",
            fill = "false",
            thickness = 1.5,
            font_size = 7,
            grid_color = "#1A234A",
            axis_color = C.text_dim,
            label_color = C.text_dim,
        }
    })
    
    graphs_initialized = true
    graphs_s:commit()
end

-- Обёрточная функция для внешнего вызова
local function render_graphs()
    if not graphs_initialized then
        render_graphs_structure()
    end
    render_graphs_data()
end

-- Функция для полной перерисовки (при смене вкладки)
local function render_graphs_full()
    graphs_initialized = false
    graph_chart_handle = nil
    graph_select_handle = nil
    render_graphs_structure()
    render_graphs_data()
end

-- ==================== UI: ВКЛАДКА ЛОГИ ====================

local logs_s = surfaces.logs

local function render_logs()
    logs_s:clear()
    logs_s:element({ id = "logs_bg", type = "panel", rect = { unit = "px", x = 0, y = 0, w = W, h = H }, style = { bg = C.bg } })
    logs_s:element({ id = "logs_title", type = "label", rect = { unit = "px", x = 12, y = 8, w = 300, h = 18 }, 
        props = { text = "ACCS V3 - Системный журнал" }, 
        style = { font_size = 12, color = C.accent, align = "left" } })
    
    -- Кнопка очистки лога
    logs_s:element({ id = "logs_clear", type = "button", 
        rect = { unit = "px", x = W - 70, y = 6, w = 60, h = 20 }, 
        props = { text = "ОЧИСТИТЬ" }, 
        style = { bg = C.panel, text = C.red, font_size = 9, border_color = C.red, border_width = 1 }, 
        on_click = function()
            log_entries = {}
            if ic.persist then
                ic.persist.set("accs_log_v3", util.json.encode({ entries = {}, counter = 0 }))
            end
            render_logs()
            draw_navigation_tabs()
        end })
    
    local log_y = 34
    local line_h = 14
    local max_lines = math.floor((H - log_y - 10) / line_h)
    
    -- Показываем последние записи
    local start_idx = math.max(1, #log_entries - max_lines + 1)
    for idx = start_idx, #log_entries do
        local entry = log_entries[idx]
        if entry then
            local y = log_y + (idx - start_idx) * line_h
            local color = C.text
            if entry.type == "EMERGENCY" then color = C.orange
            elseif entry.type == "WARNING" then color = C.yellow
            elseif entry.type == "INFO" then color = C.green end
            
            local text = string.format("[%s] Зона%d: %s %s", 
                entry.time or "--:--:--", 
                entry.room or 0,
                entry.message or "", 
                entry.value or "")
            
            logs_s:element({ id = "log_" .. idx, type = "label", 
                rect = { unit = "px", x = 12, y = y, w = W - 24, h = line_h - 1 }, 
                props = { text = text }, 
                style = { font_size = 9, color = color, align = "left", font = "monospace" } })
        end
    end
    
    if #log_entries == 0 then
        logs_s:element({ id = "logs_empty", type = "label", 
            rect = { unit = "px", x = 50, y = 100, w = 380, h = 20 }, 
            props = { text = "Журнал событий пуст" }, 
            style = { font_size = 12, color = C.text_dim, align = "center" } })
    end
    
    logs_s:commit()
end

-- ==================== UI: НАСТРОЙКИ ====================

local function render_settings()
    s:clear()
    
    s:element({ id = "settings_bg", type = "panel", rect = { unit = "px", x = 0, y = 0, w = W, h = H }, style = { bg = C.bg } })
    s:element({ id = "settings_title", type = "label", rect = { unit = "px", x = 12, y = 8, w = 300, h = 18 }, 
        props = { text = "ACCS V3 - Конфигурация" }, 
        style = { font_size = 14, color = C.accent, align = "left" } })

    if cached_dropdowns == nil then populate_device_caches() end
    local idx = settings_page
    local cfg = rooms_cfg[idx]
    local dev = room_state[idx].devices

    local dynamic_options = {}
    for i = 1, BOX_COUNT do
        table.insert(dynamic_options, rooms_cfg[i].name)
    end
    local room_options_str = table.concat(dynamic_options, "|")

    local pane_x, pane_y, pane_w, pane_h = 12, 54, W - 24, H - 66
    s:element({ id = "room_pane_single", type = "panel", 
        rect = { unit = "px", x = pane_x, y = pane_y, w = pane_w, h = pane_h }, 
        style = { bg = C.panel, border_color = "#1E2538", border_width = 1 } })
    
    -- Выбор комнаты
    s:element({ id = "sel_room_lbl", type = "label", 
        rect = { unit = "px", x = pane_x + 14, y = pane_y + 12, w = 120, h = 16 }, 
        props = { text = "Выбор помещения:" }, 
        style = { font_size = 11, color = C.accent, align = "left" } })
    s:element({
        id = "sel_room_dropdown", type = "select", 
        rect = { unit = "px", x = pane_x + 150, y = pane_y + 8, w = 270, h = 22 },
        props = { options = room_options_str, selected = idx - 1, open = settings_room_open },
        on_toggle = function() settings_room_open = not settings_room_open render_settings() draw_navigation_tabs() end,
        on_change = function(opt) settings_page = (tonumber(opt) or 0) + 1 settings_room_open = false render_settings() draw_navigation_tabs() end
    })

    local item_start_y, step_y = pane_y + 36, 22
    local label_w, input_x, drop_w = 170, pane_x + 190, 240

    -- Имя комнаты
    s:element({ id = "lbl_room_name", type = "label", 
        rect = { unit = "px", x = pane_x + 14, y = item_start_y + 2, w = label_w, h = 16 }, 
        props = { text = "Изменить имя зоны:" }, 
        style = { font_size = 11, color = C.text } })
    s:element({ 
        id = "inp_room_name", type = "textinput", 
        rect = { unit = "px", x = input_x, y = item_start_y, w = drop_w, h = 20 }, 
        props = { value = cfg.name, placeholder = "Имя зоны...", title = "Название комнаты (до 20 симв.)" }, 
        style = { bg = "#161B2C", text = C.accent, font_size = 10 }, 
        on_change = function(value)
            if value and value ~= "" then
                cfg.name = string.sub(value, 1, 20)
                save_settings_to_storage()
                render_settings() 
                draw_navigation_tabs()
            end
        end 
    })

    -- Температура
    local y_t = item_start_y + step_y
    s:element({ id = "t_cfg_lbl", type = "label", 
        rect = { unit = "px", x = pane_x + 14, y = y_t + 2, w = label_w, h = 16 }, 
        props = { text = "Настройка температуры:" }, 
        style = { font_size = 11, color = C.text, align = "left" } })
    s:element({ id = "t_minus_b", type = "button", 
        rect = { unit = "px", x = input_x, y = y_t, w = 18, h = 18 }, 
        props = { text = "-" }, 
        style = { bg = "#1E2538", text = C.text, font_size = 11 }, 
        on_click = function() cfg.target_t = math.max(273.15, cfg.target_t - 1.0) render_settings() draw_navigation_tabs() save_settings_to_storage() end })
    local current_t_c = math.floor(cfg.target_t - 273.15 + 0.5)
    s:element({ id = "t_val_lbl", type = "label", 
        rect = { unit = "px", x = input_x + 22, y = y_t + 2, w = 55, h = 16 }, 
        props = { text = string.format("%d °C", current_t_c) }, 
        style = { font_size = 14, color = C.yellow, align = "center" } })
    s:element({ id = "t_plus_b", type = "button", 
        rect = { unit = "px", x = input_x + 81, y = y_t, w = 18, h = 18 }, 
        props = { text = "+" }, 
        style = { bg = "#1E2538", text = C.text, font_size = 11 }, 
        on_click = function() cfg.target_t = math.min(323.15, cfg.target_t + 1.0) render_settings() draw_navigation_tabs() save_settings_to_storage() end })

    -- Давление
    local y_p = y_t + step_y
    s:element({ id = "p_cfg_lbl", type = "label", 
        rect = { unit = "px", x = pane_x + 14, y = y_p + 2, w = label_w, h = 16 }, 
        props = { text = "Настройка давления:" }, 
        style = { font_size = 11, color = C.text, align = "left" } })
    s:element({ id = "p_minus_b", type = "button", 
        rect = { unit = "px", x = input_x, y = y_p, w = 18, h = 18 }, 
        props = { text = "-" }, 
        style = { bg = "#1E2538", text = C.text, font_size = 11 }, 
        on_click = function() cfg.min_p = math.max(0, cfg.min_p - 5) cfg.max_p = cfg.min_p + 5 render_settings() draw_navigation_tabs() save_settings_to_storage() end })
    s:element({ id = "p_val_lbl", type = "label", 
        rect = { unit = "px", x = input_x + 22, y = y_p + 2, w = 55, h = 16 }, 
        props = { text = string.format("%d кПа", cfg.min_p) }, 
        style = { font_size = 14, color = C.accent, align = "center" } })
    s:element({ id = "p_plus_b", type = "button", 
        rect = { unit = "px", x = input_x + 81, y = y_p, w = 18, h = 18 }, 
        props = { text = "+" }, 
        style = { bg = "#1E2538", text = C.text, font_size = 11 }, 
        on_click = function() cfg.min_p = math.min(200, cfg.min_p + 5) cfg.max_p = cfg.min_p + 5 render_settings() draw_navigation_tabs() save_settings_to_storage() end })

    -- Датчик
    local y_s = y_p + step_y
    s:element({ id = "sens_cfg_lbl", type = "label", 
        rect = { unit = "px", x = pane_x + 14, y = y_s + 4, w = label_w, h = 16 }, 
        props = { text = "Датчик газа:" }, 
        style = { font_size = 10, color = C.text, align = "left" } })
    s:element({
        id = "sel_sens_single", type = "select", 
        rect = { unit = "px", x = input_x, y = y_s, w = drop_w, h = 20 },
        props = { options = table.concat(cached_dropdowns.sensor, "|"), 
                  selected = dev.sensor.sel, open = room_state[idx].dropdown_open.sensor },
        on_toggle = function() room_state[idx].dropdown_open.sensor = not room_state[idx].dropdown_open.sensor render_settings() draw_navigation_tabs() end,
        on_change = function(opt)
            local o = tonumber(opt) or 0 
            dev.sensor.sel = o 
            room_state[idx].dropdown_open.sensor = false
            if o == 0 then dev.sensor.prefab = 0 dev.sensor.namehash = 0
            else local d = cached_dropdowns.sensor_devs[o] dev.sensor.prefab = d.prefab_hash dev.sensor.namehash = d.name_hash end
            render_settings() draw_navigation_tabs() save_settings_to_storage()
        end
    })

    -- Вентилятор подачи
    local y_v1 = y_s + step_y
    s:element({ id = "vin_cfg_lbl", type = "label", 
        rect = { unit = "px", x = pane_x + 14, y = y_v1 + 4, w = label_w, h = 16 }, 
        props = { text = "Вентилятор ПОДАЧИ:" }, 
        style = { font_size = 10, color = C.green, align = "left" } })
    s:element({
        id = "sel_vin_single", type = "select", 
        rect = { unit = "px", x = input_x, y = y_v1, w = drop_w, h = 20 },
        props = { options = table.concat(cached_dropdowns.vent, "|"), 
                  selected = dev.vent_in.sel, open = room_state[idx].dropdown_open.vent_in },
        on_toggle = function() room_state[idx].dropdown_open.vent_in = not room_state[idx].dropdown_open.vent_in render_settings() draw_navigation_tabs() end,
        on_change = function(opt)
            local o = tonumber(opt) or 0 
            dev.vent_in.sel = o 
            room_state[idx].dropdown_open.vent_in = false
            if o == 0 then dev.vent_in.prefab = 0 dev.vent_in.namehash = 0
            else local d = cached_dropdowns.vent_devs[o] dev.vent_in.prefab = d.prefab_hash dev.vent_in.namehash = d.name_hash end
            render_settings() draw_navigation_tabs() save_settings_to_storage()
        end
    })

    -- Вентилятор откачки
    local y_v2 = y_v1 + step_y
    s:element({ id = "vout_cfg_lbl", type = "label", 
        rect = { unit = "px", x = pane_x + 14, y = y_v2 + 4, w = label_w, h = 16 }, 
        props = { text = "Вентилятор ОТКАЧКИ:" }, 
        style = { font_size = 10, color = C.red, align = "left" } })
    s:element({
        id = "sel_vout_single", type = "select", 
        rect = { unit = "px", x = input_x, y = y_v2, w = drop_w, h = 20 },
        props = { options = table.concat(cached_dropdowns.vent, "|"), 
                  selected = dev.vent_out.sel, open = room_state[idx].dropdown_open.vent_out },
        on_toggle = function() room_state[idx].dropdown_open.vent_out = not room_state[idx].dropdown_open.vent_out render_settings() draw_navigation_tabs() end,
        on_change = function(opt)
            local o = tonumber(opt) or 0 
            dev.vent_out.sel = o 
            room_state[idx].dropdown_open.vent_out = false
            if o == 0 then dev.vent_out.prefab = 0 dev.vent_out.namehash = 0
            else local d = cached_dropdowns.vent_devs[o] dev.vent_out.prefab = d.prefab_hash dev.vent_out.namehash = d.name_hash end
            render_settings() draw_navigation_tabs() save_settings_to_storage()
        end
    })

    -- Клапан
    local y_vl = y_v2 + step_y
    s:element({ id = "vlv_cfg_lbl", type = "label", 
        rect = { unit = "px", x = pane_x + 14, y = y_vl + 4, w = label_w, h = 16 }, 
        props = { text = "Клапан радиатора:" }, 
        style = { font_size = 10, color = C.yellow, align = "left" } })
    s:element({
        id = "sel_vlv_single", type = "select", 
        rect = { unit = "px", x = input_x, y = y_vl, w = drop_w, h = 20 },
        props = { options = table.concat(cached_dropdowns.valve, "|"), 
                  selected = dev.valve.sel, open = room_state[idx].dropdown_open.valve },
        on_toggle = function() room_state[idx].dropdown_open.valve = not room_state[idx].dropdown_open.valve render_settings() draw_navigation_tabs() end,
        on_change = function(opt)
            local o = tonumber(opt) or 0 
            dev.valve.sel = o 
            room_state[idx].dropdown_open.valve = false
            if o == 0 then dev.valve.prefab = 0 dev.valve.namehash = 0
            else local d = cached_dropdowns.valve_devs[o] dev.valve.prefab = d.prefab_hash dev.valve.namehash = d.name_hash end
            render_settings() draw_navigation_tabs() save_settings_to_storage()
        end
    })
    s:commit()
end

-- ==================== НАВИГАЦИЯ ====================

draw_navigation_tabs = function()
    local tab_width = 75
    local tabs = {
        { id = "overview", text = "ОБЗОР", surface = surfaces.overview },
        { id = "gases", text = "ГАЗЫ", surface = surfaces.gases },
        { id = "graphs", text = "ГРАФИКИ", surface = surfaces.graphs },
        { id = "logs", text = "ЛОГИ", surface = surfaces.logs },
        { id = "settings", text = "НАСТР.", surface = surfaces.settings }
    }
    
    for idx, tab in ipairs(tabs) do
        local x = 12 + (idx - 1) * (tab_width + 4)
        s:element({ 
            id = "tab_" .. tab.id, 
            type = "button", 
            rect = { unit = "px", x = x, y = 28, w = tab_width, h = 20 }, 
            props = { text = tab.text }, 
            style = { 
                bg = view == tab.id and "#1E3A8A" or C.panel, 
                text = "#FFFFFF", 
                font_size = 9, 
                border_color = view == tab.id and C.accent or "#1E2538", 
                border_width = 1 
            }, 
            on_click = function()
                view = tab.id
                s = tab.surface
                ss.ui.activate(tab.id)
                if view == "overview" then 
                    render_overview_delta()
                elseif view == "gases" then 
                    render_gases()
                elseif view == "graphs" then 
                    render_graphs_full()
                elseif view == "logs" then 
                    render_logs()
                elseif view == "settings" then 
                    render_settings() 
                end
                draw_navigation_tabs()
            end 
        })
    end
end

-- ==================== ГЛАВНЫЙ ЦИКЛ ====================

s = surfaces.overview 
ss.ui.activate("overview") 

populate_device_caches()
initialize_settings()
render_overview_delta()
draw_navigation_tabs()

local fast_counter = 0

while true do
    elapsed = elapsed + 1
    fast_counter = fast_counter + 1
    
    -- Быстрое обновление (каждый тик)
    if fast_counter % FAST_UPDATE_TICKS == 0 then
        refresh_accs_readings()
        execute_accs_logic()
        update_hardware_console()
    end
    
    -- UI обновление
    if view == "overview" then 
        render_overview_delta()
        draw_navigation_tabs()
    elseif view == "gases" then
        render_gases()
        draw_navigation_tabs()
    elseif view == "graphs" then
        if fast_counter % (FAST_UPDATE_TICKS * 2) == 0 then
            render_graphs_data()
            draw_navigation_tabs()
        end
    elseif view == "logs" then
        render_logs()
        draw_navigation_tabs()
    elseif view == "settings" then
        render_settings()
        draw_navigation_tabs()
    end
    
    ic.yield()
end
-- ACCS V3 - Система жизнеобеспечения нового поколения