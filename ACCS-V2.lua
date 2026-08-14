--##### Часть № 1 #####
-- ======================================================================
-- ACCS - AIR COMPOSITION & CONTROL SYSTEM (INDUSTRIAL LOGIC V2)
-- ======================================================================

local surfaces = {
    overview = ss.ui.surface("overview"),
    settings = ss.ui.surface("settings"),
}
local s = surfaces.overview
local view = "overview"

local W, H = 480, 272
local size = ss.ui.surface("overview"):size()
if size then W = size.w or W H = size.h or H end

local elapsed = 0
local BOX_COUNT = 8
local LIVE_REFRESH_TICKS = 4

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

local C = {
    bg = "#080B14", panel = "#0D1222", panel_light = "#141B32", divider = "#1A234A",
    text = "#F1F5F9", text_dim = "#94A3B8", accent = "#38BDF8", green = "#10B981", yellow = "#F59E0B", red = "#EF4444"
}

-- Атмосферные и температурные профили комнат базы (с адресами памяти с 0)
local rooms_cfg = {
    { id = 1, name = "Зона 1", is_greenhouse = false, min_p = 100, max_p = 105, target_t = 293.15, mem_p = 0, mem_t = 1 },
    { id = 2, name = "Зона 2", is_greenhouse = false, min_p = 101, max_p = 106, target_t = 293.15, mem_p = 2, mem_t = 3 },
    { id = 3, name = "Зона 3", is_greenhouse = false, min_p = 95,  max_p = 100, target_t = 293.15, mem_p = 4, mem_t = 5 }, 
    { id = 4, name = "Зона 4", is_greenhouse = false, min_p = 101, max_p = 106, target_t = 293.15, mem_p = 6, mem_t = 7 }, 
    { id = 5, name = "Зона 5", is_greenhouse = false, min_p = 100, max_p = 105, target_t = 291.15, mem_p = 8, mem_t = 9 }, 
    { id = 6, name = "Зона 6", is_greenhouse = false, min_p = 100, max_p = 105, target_t = 291.15, mem_p = 10, mem_t = 11 }, 
    { id = 7, name = "Зона 7", is_greenhouse = true,  min_p = 80,  max_p = 85,  target_t = 298.15, mem_p = 12, mem_t = 13 }, 
    { id = 8, name = "Зона 8", is_greenhouse = false, min_p = 90,  max_p = 95,  target_t = 293.15, mem_p = 14, mem_t = 15 }
}

-- Динамические привязки устройств и оперативная память
local accs_devices = {}
local accs_data = {}
local dropdown_open = {}
local cached_dropdowns = nil
local active_display_room = 1
local settings_page = 1
local base_global_status = STATE_NOMINAL

local settings_room_open = "false"
local room_options_str = "Тамбур|Производственная|Плавки металлов|Жилая комната|Аппаратная связи|Комната ACCS|Теплица (CO2)|Фильтрация газов"

for i = 1, BOX_COUNT do
    accs_devices[i] = {
        sensor = { prefab = 0, namehash = 0, sel = 0 },
        vent_in = { prefab = 0, namehash = 0, sel = 0 },
        vent_out = { prefab = 0, namehash = 0, sel = 0 },
        valve = { prefab = 0, namehash = 0, sel = 0 }
    }
    dropdown_open[i] = { sensor = "false", vent_in = "false", vent_out = "false", valve = "false" }
    accs_data[i] = {
        pressure = 0, temperature = 293.15, ratio_o2 = 0, ratio_n2 = 0, ratio_co2 = 0,
        ratio_pol = 0, ratio_n2o = 0, ratio_h2o = 0, ratio_ch4 = 0, ratio_h2 = 0,
        room_status = STATE_OFFLINE, is_online = false
    }
end

-- ==================== БЕЗОПАСНЫЕ ФУНКЦИИ API И ПАМЯТИ ====================

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

local function save_settings_to_storage()
    -- Контур А: Аппаратный бэкап чисел (с 0 ячейки)
    for i = 1, BOX_COUNT do
        local cfg = rooms_cfg[i]
        if cfg then
            mem_write(cfg.mem_p, cfg.min_p)
            mem_write(cfg.mem_t, math.floor(cfg.target_t * 100))
        end
    end

    -- Контур Б: Нативное сохранение всей структуры через ic.persist
    if ic.persist then
        local state = { devices = accs_devices, rooms = {} }
        for i = 1, BOX_COUNT do
            state.rooms[i] = { name = rooms_cfg[i].name, min_p = rooms_cfg[i].min_p, max_p = rooms_cfg[i].max_p, target_t = rooms_cfg[i].target_t }
        end
        local ok, json_str = pcall(util.json.encode, state)
        if ok and json_str then ic.persist.set("accs_data_v2", json_str) end
    end
end

local function initialize_settings()
    -- Шаг 1: Проверяем современное хранилище ic.persist
    local persist_loaded = false
    if ic.persist and ic.persist.has("accs_data_v2") then
        local saved_str = ic.persist.get("accs_data_v2")
        if type(saved_str) == "string" and saved_str ~= "" then
            local ok, decoded = pcall(util.json.decode, saved_str)
            if ok and type(decoded) == "table" then
                if type(decoded.devices) == "table" then
                    for i = 1, BOX_COUNT do
                        if decoded.devices[i] then
                            if decoded.devices[i].sensor then accs_devices[i].sensor = decoded.devices[i].sensor end
                            if decoded.devices[i].vent_in then accs_devices[i].vent_in = decoded.devices[i].vent_in end
                            if decoded.devices[i].vent_out then accs_devices[i].vent_out = decoded.devices[i].vent_out end
                            if decoded.devices[i].valve then accs_devices[i].valve = decoded.devices[i].valve end
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
                persist_loaded = true
            end
        end
    end

    -- Шаг 2: Страховочный контур (считываем значения из физической памяти)
    for i = 1, BOX_COUNT do
        local cfg = rooms_cfg[i]
        local backup_p = mem_read(cfg.mem_p)
        local backup_t = mem_read(cfg.mem_t)
        
        if backup_p and backup_p > 0 then
            rooms_cfg[i].min_p = backup_p
            rooms_cfg[i].max_p = backup_p + 5
        end
        
        -- Контур аппаратной страховки от пустых ячеек памяти (Кельвины * 100)
        -- Порог 27315 соответствует ровно 0 °C. Если в памяти ноль или мусор:
        if backup_t and backup_t >= 27315 then
            rooms_cfg[i].target_t = backup_t / 100
        else
            -- Принудительно выставляем дефолтные комнатные 20 °C (293.15 K)
            rooms_cfg[i].target_t = 293.15
        end
    end
    return persist_loaded
end
--##### Часть № 2 #####
-- ======================================================================
-- ПОЛУЧЕНИЕ СПИСКА УСТРОЙСТВ И ЛОГИКА ЖИЗНЕОБЕСПЕЧЕНИЯ БАЗЫ
-- ======================================================================

local function populate_device_caches()
    local ok, devs = pcall(device_list)
    if not ok or devs == nil then devs = {} end
    cached_dropdowns = { sensor = { "Выбрать Датчик..." }, vent = { "Выбрать Вентилятор..." }, valve = { "Выбрать Клапан..." } }
    cached_dropdowns.sensor_devs = {} cached_dropdowns.vent_devs = {} cached_dropdowns.valve_devs = {}

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

local function refresh_accs_readings()
    base_global_status = STATE_NOMINAL
    for i = 1, BOX_COUNT do
        local dev = accs_devices[i].sensor
        if tonumber(dev.prefab) ~= 0 and tonumber(dev.namehash) ~= 0 then
            local status, err = pcall(function()
                local p = safe_batch_read_name(dev.prefab, dev.namehash, LT.Pressure, LBM.Average)
                if p and p > 0 then
                    accs_data[i].pressure    = p
                    accs_data[i].temperature = safe_batch_read_name(dev.prefab, dev.namehash, LT.Temperature, LBM.Average) or 293.15
                    accs_data[i].ratio_o2    = safe_batch_read_name(dev.prefab, dev.namehash, LT.RatioOxygen, LBM.Average) or 0
                    accs_data[i].ratio_n2    = safe_batch_read_name(dev.prefab, dev.namehash, LT.RatioNitrogen, LBM.Average) or 0
                    accs_data[i].ratio_co2   = safe_batch_read_name(dev.prefab, dev.namehash, LT.RatioCarbonDioxide, LBM.Average) or 0
                    accs_data[i].ratio_pol   = safe_batch_read_name(dev.prefab, dev.namehash, LT.RatioPollutant, LBM.Average) or 0
                    accs_data[i].ratio_n2o   = safe_batch_read_name(dev.prefab, dev.namehash, LT.RatioNitrousOxide, LBM.Average) or 0
                    accs_data[i].ratio_h2o   = safe_batch_read_name(dev.prefab, dev.namehash, LT.RatioWater, LBM.Average) or 0
                    accs_data[i].ratio_ch4   = safe_batch_read_name(dev.prefab, dev.namehash, LT.RatioMethane, LBM.Average) or 0
                    accs_data[i].ratio_h2    = safe_batch_read_name(dev.prefab, dev.namehash, LT.RatioHydrogen, LBM.Average) or 0
                    accs_data[i].is_online   = true
                    
                    local total_combustible = accs_data[i].ratio_ch4 + accs_data[i].ratio_h2
                    if accs_data[i].ratio_pol > 0.005 or total_combustible > 0.005 or p < 30 then
                        accs_data[i].room_status = STATE_CRITICAL
                    elseif accs_data[i].pressure < rooms_cfg[i].min_p or accs_data[i].pressure > rooms_cfg[i].max_p then
                        accs_data[i].room_status = STATE_WARNING
                    elseif not rooms_cfg[i].is_greenhouse and accs_data[i].ratio_o2 < 0.18 then
                        accs_data[i].room_status = STATE_WARNING
                    elseif rooms_cfg[i].is_greenhouse and accs_data[i].ratio_co2 < 0.05 then
                        accs_data[i].room_status = STATE_WARNING
                    else
                        accs_data[i].room_status = STATE_NOMINAL
                    end
                else
                    accs_data[i].is_online = false
                    accs_data[i].room_status = STATE_OFFLINE
                end
            end)
            if not status then accs_data[i].is_online = false accs_data[i].room_status = STATE_OFFLINE end
        else
            accs_data[i].is_online = false accs_data[i].room_status = STATE_OFFLINE
        end

        if accs_data[i].room_status == STATE_CRITICAL then base_global_status = STATE_CRITICAL
        elseif accs_data[i].room_status == STATE_WARNING and base_global_status ~= STATE_CRITICAL then base_global_status = STATE_WARNING end
    end
end

local function execute_accs_logic()
    for i = 1, BOX_COUNT do
        local cfg = rooms_cfg[i]
        local data = accs_data[i]
        local v_in = accs_devices[i].vent_in
        local v_out = accs_devices[i].vent_out
        local v_valve = accs_devices[i].valve

        if data.is_online then
            if data.room_status == STATE_CRITICAL then
                safe_batch_write_name(v_in.prefab, v_in.namehash, LT.On, 0)
                safe_batch_write_name(v_out.prefab, v_out.namehash, LT.On, 1)
                safe_batch_write_name(v_out.prefab, v_out.namehash, LT.Mode, 0)
                safe_batch_write_name(v_out.prefab, v_out.namehash, LT.Setting, 100)
            else
                if data.pressure < cfg.min_p then
                    safe_batch_write_name(v_in.prefab, v_in.namehash, LT.On, 1)
                    safe_batch_write_name(v_in.prefab, v_in.namehash, LT.Mode, 1)
                    safe_batch_write_name(v_in.prefab, v_in.namehash, LT.Setting, 50)
                    safe_batch_write_name(v_out.prefab, v_out.namehash, LT.On, 0)
                elseif data.pressure > cfg.max_p then
                    safe_batch_write_name(v_out.prefab, v_out.namehash, LT.On, 1)
                    safe_batch_write_name(v_out.prefab, v_out.namehash, LT.Mode, 0)
                    safe_batch_write_name(v_out.prefab, v_out.namehash, LT.Setting, 30)
                    safe_batch_write_name(v_in.prefab, v_in.namehash, LT.On, 0)
                else
                    safe_batch_write_name(v_in.prefab, v_in.namehash, LT.On, 0)
                    safe_batch_write_name(v_out.prefab, v_out.namehash, LT.On, 0)
                end
            end

            -- Управление климатическим клапаном с гистерезисом 0.5 °C
            if tonumber(v_valve.prefab) ~= 0 and tonumber(v_valve.namehash) ~= 0 then
                if data.temperature > (cfg.target_t + 0.5) then
                    safe_batch_write_name(v_valve.prefab, v_valve.namehash, LT.On, 1)
                elseif data.temperature < (cfg.target_t - 0.5) then
                    safe_batch_write_name(v_valve.prefab, v_valve.namehash, LT.On, 0)
                end
            end
        else
            safe_batch_write_name(v_in.prefab, v_in.namehash, LT.On, 0)
            safe_batch_write_name(v_out.prefab, v_out.namehash, LT.On, 0)
            safe_batch_write_name(v_valve.prefab, v_valve.namehash, LT.On, 0)
        end
    end
end
--##### Часть № 3 #####
-- ======================================================================
-- ПРОМЫШЛЕННЫЙ МАТРИЧНЫЙ ИНТЕРФЕЙС ВКЛАДКИ ОБЗОР (OVERVIEW)
-- ======================================================================

local function get_status_color(status)
    if status == STATE_NOMINAL then return C.green end
    if status == STATE_WARNING then return C.yellow end
    if status == STATE_CRITICAL then return C.red end
    return C.text_dim
end

local function render_overview()
    s:clear()
    
    -- Фоновая подложка главного экрана
    s:element({ id = "main_bg", type = "panel", rect = { unit = "px", x = 0, y = 0, w = W, h = H }, style = { bg = C.bg } })
    
    -- Главный заголовок ACCS
    s:element({ id = "header_title", type = "label", rect = { unit = "px", x = 12, y = 8, w = 300, h = 18 }, props = { text = "ACCS - Air Control & Composition System" }, style = { font_size = 12, color = C.accent, align = "left" } })

    -- Сетка построения монументальной таблицы (строки 44px на весь экран)
    local start_x = 10
    local start_y = 54   
    local row_h   = 44   
    local border_gap = 2

    -- Размеры колонок под крупные цифры с учётом переноса названий комнат
    local col_room_w = 70  -- Название помещения (по центру, с переносом)
    local col_p_w    = 62  -- Давление (кПа)
    local col_t_w    = 58  -- Температура (°C)
    local col_o2_w   = 62  -- Кислород (%)
    local col_n2_w   = 62  -- Азот (%)
    local col_co2_w  = 62  -- Углекислый газ (%)
    local col_dng_w  = 60  -- Зона аварийных боксов

    -- Расчёт точных координат по оси X
    local x_room = start_x
    local x_p    = x_room + col_room_w + border_gap
    local x_t    = x_p    + col_p_w    + border_gap
    local x_o2   = x_t    + col_t_w    + border_gap
    local x_n2   = x_o2   + col_o2_w   + border_gap
    local x_co2  = x_n2   + col_n2_w   + border_gap
    local x_dng  = x_co2  + col_co2_w  + border_gap

    -- Отрисовка промышленной "Шапки" таблицы с указанием физических единиц
    s:element({ id = "h_col_room", type = "label", rect = { unit = "px", x = x_room, y = start_y, w = col_room_w, h = 14 }, props = { text = "ЗОНА" }, style = { font_size = 11, color = C.accent, align = "center" } })
    s:element({ id = "h_col_p",    type = "label", rect = { unit = "px", x = x_p,    y = start_y, w = col_p_w,    h = 14 }, props = { text = "P (кПа)" }, style = { font_size = 11, color = C.accent, align = "center" } })
    s:element({ id = "h_col_t",    type = "label", rect = { unit = "px", x = x_t,    y = start_y, w = col_t_w,    h = 14 }, props = { text = "T (°C)" }, style = { font_size = 11, color = C.accent, align = "center" } })
    s:element({ id = "h_col_o2",   type = "label", rect = { unit = "px", x = x_o2,   y = start_y, w = col_o2_w,   h = 14 }, props = { text = "O2 (%)" }, style = { font_size = 11, color = C.accent, align = "center" } })
    s:element({ id = "h_col_n2",   type = "label", rect = { unit = "px", x = x_n2,   y = start_y, w = col_n2_w,   h = 14 }, props = { text = "N2 (%)" }, style = { font_size = 11, color = C.accent, align = "center" } })
    s:element({ id = "h_col_co2",  type = "label", rect = { unit = "px", x = x_co2,  y = start_y, w = col_co2_w,  h = 14 }, props = { text = "CO2 (%)" }, style = { font_size = 11, color = C.accent, align = "center" } })
    s:element({ id = "h_col_dng",  type = "label", rect = { unit = "px", x = x_dng,  y = start_y, w = col_dng_w,  h = 14 }, props = { text = "УГРОЗЫ" }, style = { font_size = 11, color = C.red,    align = "center" } })

    local data_start_y = start_y + 16

    -- Цикл генерации монументальной таблицы по всем 8 комнатам базы одновременно
    for i = 1, BOX_COUNT do
        local cfg = rooms_cfg[i]
        local data = accs_data[i]
        local cur_y = data_start_y + (i - 1) * row_h
        local text_color = get_status_color(data.room_status)

        -- Панель-подложка для каждой ячейки строки
        s:element({ id = "row_panel_" .. i, type = "panel", rect = { unit = "px", x = start_x, y = cur_y, w = W - 20, h = row_h - 2 }, style = { bg = C.panel, border_color = "#121A30", border_width = 1 } })

        -- Идеальное центрирование и перенос названий комнат на две строки по пробелам
        local first_word, second_word = string.match(cfg.name, "([^%s]+)%s+(.*)")
        if first_word and second_word then
            s:element({ id = "r_name_w1_" .. i, type = "label", rect = { unit = "px", x = x_room + 2, y = cur_y + 11, w = col_room_w - 2, h = 12 }, props = { text = first_word }, style = { font_size = 10, color = text_color, align = "center" } })
            s:element({ id = "r_name_w2_" .. i, type = "label", rect = { unit = "px", x = x_room + 2, y = cur_y + 23, w = col_room_w - 2, h = 12 }, props = { text = second_word }, style = { font_size = 10, color = text_color, align = "center" } })
        else
            s:element({ id = "r_name_" .. i, type = "label", rect = { unit = "px", x = x_room + 2, y = cur_y + 15, w = col_room_w - 2, h = 14 }, props = { text = cfg.name }, style = { font_size = 12, color = text_color, align = "center" } })
        end

        -- Форматирование числовых показателей атмосферы с точностью до десятых
        local p_txt = data.is_online and string.format("%.0f", data.pressure) or "--"
        local t_txt = data.is_online and string.format("%.1f", data.temperature - 273.15) or "--"
        local o2_txt = data.is_online and string.format("%.1f", data.ratio_o2 * 100) or "--"
        local n2_txt = data.is_online and string.format("%.1f", data.ratio_n2 * 100) or "--"
        local co2_txt = data.is_online and string.format("%.1f", data.ratio_co2 * 100) or "--"

        -- Отрисовка крупных числовых параметров по центру с высотой y + 14
        s:element({ id = "r_p_" .. i, type = "label", rect = { unit = "px", x = x_p, y = cur_y + 14, w = col_p_w, h = 16 }, props = { text = p_txt }, style = { font_size = 13, color = C.text, align = "center" } })
        s:element({ id = "r_t_" .. i, type = "label", rect = { unit = "px", x = x_t, y = cur_y + 14, w = col_t_w, h = 16 }, props = { text = t_txt }, style = { font_size = 13, color = C.yellow, align = "center" } })
        s:element({ id = "r_o2_" .. i, type = "label", rect = { unit = "px", x = x_o2, y = cur_y + 14, w = col_o2_w, h = 16 }, props = { text = o2_txt }, style = { font_size = 13, color = C.text, align = "center" } })
        s:element({ id = "r_n2_" .. i, type = "label", rect = { unit = "px", x = x_n2, y = cur_y + 14, w = col_n2_w, h = 16 }, props = { text = n2_txt }, style = { font_size = 13, color = C.text_dim, align = "center" } })
        s:element({ id = "r_co2_" .. i, type = "label", rect = { unit = "px", x = x_co2, y = cur_y + 14, w = col_co2_w, h = 16 }, props = { text = co2_txt }, style = { font_size = 13, color = C.accent, align = "center" } })

        -- Матрица химических угроз (Колонка Danger-боксов)
        if data.is_online then
            local alert_tag = ""
            if data.ratio_pol > 0.001 then alert_tag = "POL"
            elseif data.ratio_ch4 > 0.001 then alert_tag = "CH4"
            elseif data.ratio_h2 > 0.001 then alert_tag = "H2"
            elseif data.ratio_n2o > 0.001 then alert_tag = "N2O"
            elseif data.ratio_h2o > 0.001 then alert_tag = "H2O" end

            if alert_tag ~= "" then
                local b_w, b_h = 42, 16
                local b_x = x_dng + math.floor((col_dng_w - b_w) / 2)
                s:element({ id = "alert_box_" .. i, type = "panel", rect = { unit = "px", x = b_x, y = cur_y + 14, w = b_w, h = b_h }, style = { bg = (elapsed % 2 == 0) and C.red or "#40060B" } })
                s:element({ id = "alert_txt_" .. i, type = "label", rect = { unit = "px", x = b_x, y = cur_y + 16, w = b_w, h = b_h - 2 }, props = { text = alert_tag }, style = { font_size = 8, color = "#FFFFFF", align = "center" } })
            else
                s:element({ id = "alert_ok_" .. i, type = "label", rect = { unit = "px", x = x_dng, y = cur_y + 14, w = col_dng_w, h = 16 }, props = { text = "OK" }, style = { font_size = 11, color = C.green, align = "center" } })
            end
        else
            s:element({ id = "alert_off_" .. i, type = "label", rect = { unit = "px", x = x_dng, y = cur_y + 14, w = col_dng_w, h = 16 }, props = { text = "OFF" }, style = { font_size = 11, color = C.text_dim, align = "center" } })
        end
    end
    s:commit()
end
--##### Часть № 4 #####
-- ======================================================================
-- ПРОМЫШЛЕННЫЙ ИНТЕРФЕЙС НАСТРОЕК (SETTINGS) — ВЕРХНИЙ БЛОК И ТЕРМОСТАТЫ
-- ======================================================================

local function render_settings()
    s:clear()
    
    -- Фоновая подложка экрана настроек
    s:element({ id = "settings_bg", type = "panel", rect = { unit = "px", x = 0, y = 0, w = W, h = H }, style = { bg = C.bg } })
    s:element({ id = "settings_title", type = "label", rect = { unit = "px", x = 12, y = 8, w = 300, h = 18 }, props = { text = "ACCS - Конфигурация параметров комнат" }, style = { font_size = 14, color = C.accent, align = "left" } })

    if cached_dropdowns == nil then populate_device_caches() end
    local idx = settings_page
    local cfg = rooms_cfg[idx]

    -- ДИНАМИЧЕСКАЯ СБОРКА СПИСКА КОМНАТ: Берём актуальные имена прямо из памяти чипа
    local dynamic_options = {}
    for i = 1, BOX_COUNT do
        table.insert(dynamic_options, rooms_cfg[i].name)
    end
    local room_options_str = table.concat(dynamic_options, "|")

    local pane_x, pane_y, pane_w, pane_h = 12, 54, W - 24, H - 66
    s:element({ id = "room_pane_single", type = "panel", rect = { unit = "px", x = pane_x, y = pane_y, w = pane_w, h = pane_h }, style = { bg = C.panel, border_color = "#1E2538", border_width = 1 } })
    
    -- Выбор настраиваемого помещения (Широкий выпадающий список)
    s:element({ id = "sel_room_lbl", type = "label", rect = { unit = "px", x = pane_x + 14, y = pane_y + 12, w = 120, h = 16 }, props = { text = "Выбор помещения:" }, style = { font_size = 11, color = C.accent, align = "left" } })
    s:element({
        id = "sel_room_dropdown", type = "select", rect = { unit = "px", x = pane_x + 150, y = pane_y + 8, w = 270, h = 22 },
        props = { options = room_options_str, selected = idx - 1, open = settings_room_open },
        on_toggle = function() settings_room_open = settings_room_open == "true" and "false" or "true" render_settings() draw_navigation_tabs() end,
        on_change = function(opt) settings_page = (tonumber(opt) or 0) + 1 settings_room_open = "false" render_settings() draw_navigation_tabs() end
    })

    local item_start_y, step_y = pane_y + 36, 22
    local label_w, input_x, drop_w = 170, pane_x + 190, 240

    -- НАСТРОЙКА ИМЕНИ КОМНАТЫ: Нативный textinput до 20 символов
    s:element({ id = "lbl_room_name", type = "label", rect = { unit = "px", x = pane_x + 14, y = item_start_y + 2, w = label_w, h = 16 }, props = { text = "Изменить имя зоны:" }, style = { font_size = 11, color = C.text } })
    s:element({ 
        id = "inp_room_name", type = "textinput", 
        rect = { unit = "px", x = input_x, y = item_start_y, w = drop_w, h = 20 }, 
        props = { value = cfg.name, placeholder = "Имя зоны...", title = "Название комнаты (до 20 симв.)" }, 
        style = { bg = "#161B2C", text = C.accent, font_size = 10 }, 
        on_change = function(value, player)
            if value and value ~= "" then
                cfg.name = string.sub(value, 1, 20)
                save_settings_to_storage()
                render_settings() draw_navigation_tabs()
            end
        end 
    })

    -- Установка ТЕМПЕРАТУРЫ (Крупный жирный шрифт 14px, без мусорных префиксов)
    local y_t = item_start_y + step_y
    s:element({ id = "t_cfg_lbl", type = "label", rect = { unit = "px", x = pane_x + 14, y = y_t + 2, w = label_w, h = 16 }, props = { text = "Настройка температуры:" }, style = { font_size = 11, color = C.text, align = "left" } })
    s:element({ id = "t_minus_b", type = "button", rect = { unit = "px", x = input_x, y = y_t, w = 18, h = 18 }, props = { text = "-" }, style = { bg = "#1E2538", text = C.text, font_size = 11 }, on_click = function() cfg.target_t = math.max(273.15, cfg.target_t - 1.0) render_settings() draw_navigation_tabs() save_settings_to_storage() end })
    local current_t_c = math.floor(cfg.target_t - 273.15 + 0.5)
    s:element({ id = "t_val_lbl", type = "label", rect = { unit = "px", x = input_x + 22, y = y_t + 2, w = 55, h = 16 }, props = { text = string.format("%d °C", current_t_c) }, style = { font_size = 14, color = C.yellow, align = "center" } })
    s:element({ id = "t_plus_b", type = "button", rect = { unit = "px", x = input_x + 81, y = y_t, w = 18, h = 18 }, props = { text = "+" }, style = { bg = "#1E2538", text = C.text, font_size = 11 }, on_click = function() cfg.target_t = math.min(323.15, cfg.target_t + 1.0) render_settings() draw_navigation_tabs() save_settings_to_storage() end })

    -- Установка ДАВЛЕНИЯ (Крупный жирный шрифт 14px)
    local y_p = y_t + step_y
    s:element({ id = "p_cfg_lbl", type = "label", rect = { unit = "px", x = pane_x + 14, y = y_p + 2, w = label_w, h = 16 }, props = { text = "Настройка давления:" }, style = { font_size = 11, color = C.text, align = "left" } })
    s:element({ id = "p_minus_b", type = "button", rect = { unit = "px", x = input_x, y = y_p, w = 18, h = 18 }, props = { text = "-" }, style = { bg = "#1E2538", text = C.text, font_size = 11 }, on_click = function() cfg.min_p = math.max(0, cfg.min_p - 5) cfg.max_p = cfg.min_p + 5 render_settings() draw_navigation_tabs() save_settings_to_storage() end })
    s:element({ id = "p_val_lbl", type = "label", rect = { unit = "px", x = input_x + 22, y = y_p + 2, w = 55, h = 16 }, props = { text = string.format("%d кПа", cfg.min_p) }, style = { font_size = 14, color = C.accent, align = "center" } })
    s:element({ id = "p_plus_b", type = "button", rect = { unit = "px", x = input_x + 81, y = y_p, w = 18, h = 18 }, props = { text = "+" }, style = { bg = "#1E2538", text = C.text, font_size = 11 }, on_click = function() cfg.min_p = math.min(200, cfg.min_p + 5) cfg.max_p = cfg.min_p + 5 render_settings() draw_navigation_tabs() save_settings_to_storage() end })
--##### Часть № 5 #####
-- ======================================================================
-- ПРОМЫШЛЕННЫЙ ИНТЕРФЕЙС НАСТРОЕК (ПРИБОРЫ), НАВИГАЦИЯ И ГЛАВНЫЙ ЦИКЛ
-- ======================================================================

    local y_s = y_p + step_y
    s:element({ id = "sens_cfg_lbl", type = "label", rect = { unit = "px", x = pane_x + 14, y = y_s + 4, w = label_w, h = 16 }, props = { text = "Датчик газа комнаты:" }, style = { font_size = 10, color = C.text, align = "left" } })
    s:element({
        id = "sel_sens_single", type = "select", rect = { unit = "px", x = input_x, y = y_s, w = drop_w, h = 20 },
        props = { options = table.concat(cached_dropdowns.sensor, "|"), selected = accs_devices[idx].sensor.sel, open = dropdown_open[idx].sensor },
        on_toggle = function() dropdown_open[idx].sensor = dropdown_open[idx].sensor == "true" and "false" or "true" render_settings() draw_navigation_tabs() end,
        on_change = function(opt)
            local o = tonumber(opt) or 0 accs_devices[idx].sensor.sel = o dropdown_open[idx].sensor = "false"
            if o == 0 then accs_devices[idx].sensor.prefab = 0 accs_devices[idx].sensor.namehash = 0
            else local d = cached_dropdowns.sensor_devs[o] accs_devices[idx].sensor.prefab = d.prefab_hash accs_devices[idx].sensor.namehash = d.name_hash end
            render_settings() draw_navigation_tabs() save_settings_to_storage()
        end
    })

    local y_v1 = y_s + step_y
    s:element({ id = "vin_cfg_lbl", type = "label", rect = { unit = "px", x = pane_x + 14, y = y_v1 + 4, w = label_w, h = 16 }, props = { text = "Вентилятор ПОДАЧИ:" }, style = { font_size = 10, color = C.green, align = "left" } })
    s:element({
        id = "sel_vin_single", type = "select", rect = { unit = "px", x = input_x, y = y_v1, w = drop_w, h = 20 },
        props = { options = table.concat(cached_dropdowns.vent, "|"), selected = accs_devices[idx].vent_in.sel, open = dropdown_open[idx].vent_in },
        on_toggle = function() dropdown_open[idx].vent_in = dropdown_open[idx].vent_in == "true" and "false" or "true" render_settings() draw_navigation_tabs() end,
        on_change = function(opt)
            local o = tonumber(opt) or 0 accs_devices[idx].vent_in.sel = o dropdown_open[idx].vent_in = "false"
            if o == 0 then accs_devices[idx].vent_in.prefab = 0 accs_devices[idx].vent_in.namehash = 0
            else local d = cached_dropdowns.vent_devs[o] accs_devices[idx].vent_in.prefab = d.prefab_hash accs_devices[idx].vent_in.namehash = d.name_hash end
            render_settings() draw_navigation_tabs() save_settings_to_storage()
        end
    })

    local y_v2 = y_v1 + step_y
    s:element({ id = "vout_cfg_lbl", type = "label", rect = { unit = "px", x = pane_x + 14, y = y_v2 + 4, w = label_w, h = 16 }, props = { text = "Вентилятор ОТКАЧКИ:" }, style = { font_size = 10, color = C.red, align = "left" } })
    s:element({
        id = "sel_vout_single", type = "select", rect = { unit = "px", x = input_x, y = y_v2, w = drop_w, h = 20 },
        props = { options = table.concat(cached_dropdowns.vent, "|"), selected = accs_devices[idx].vent_out.sel, open = dropdown_open[idx].vent_out },
        on_toggle = function() dropdown_open[idx].vent_out = dropdown_open[idx].vent_out == "true" and "false" or "true" render_settings() draw_navigation_tabs() end,
        on_change = function(opt)
            local o = tonumber(opt) or 0 accs_devices[idx].vent_out.sel = o dropdown_open[idx].vent_out = "false"
            if o == 0 then accs_devices[idx].vent_out.prefab = 0 accs_devices[idx].vent_out.namehash = 0
            else local d = cached_dropdowns.vent_devs[o] accs_devices[idx].vent_out.prefab = d.prefab_hash accs_devices[idx].vent_out.namehash = d.name_hash end
            render_settings() draw_navigation_tabs() save_settings_to_storage()
        end
    })

    local y_vl = y_v2 + step_y
    s:element({ id = "vlv_cfg_lbl", type = "label", rect = { unit = "px", x = pane_x + 14, y = y_vl + 4, w = label_w, h = 16 }, props = { text = "Клапан радиатора:" }, style = { font_size = 10, color = C.yellow, align = "left" } })
    s:element({
        id = "sel_vlv_single", type = "select", rect = { unit = "px", x = input_x, y = y_vl, w = drop_w, h = 20 },
        props = { options = table.concat(cached_dropdowns.valve, "|"), selected = accs_devices[idx].valve.sel, open = dropdown_open[idx].valve },
        on_toggle = function() dropdown_open[idx].valve = dropdown_open[idx].valve == "true" and "false" or "true" render_settings() draw_navigation_tabs() end,
        on_change = function(opt)
            local o = tonumber(opt) or 0 accs_devices[idx].valve.sel = o dropdown_open[idx].valve = "false"
            if o == 0 then accs_devices[idx].valve.prefab = 0 accs_devices[idx].valve.namehash = 0
            else local d = cached_dropdowns.valve_devs[o] accs_devices[idx].valve.prefab = d.prefab_hash accs_devices[idx].valve.namehash = d.name_hash end
            render_settings() draw_navigation_tabs() save_settings_to_storage()
        end
    })
    s:commit()
end

draw_navigation_tabs = function()
    s:element({ id = "tab_overview", type = "button", rect = { unit = "px", x = 12, y = 28, w = 100, h = 20 }, props = { text = "ОБЗОР" }, style = { bg = view == "overview" and "#1E3A8A" or C.panel, text = "#FFFFFF", font_size = 10, border_color = view == "overview" and C.accent or "#1E2538", border_width = 1 }, on_click = function() view = "overview" s = surfaces.overview ss.ui.activate("overview") render_overview() draw_navigation_tabs() end })
    s:element({ id = "tab_settings", type = "button", rect = { unit = "px", x = 122, y = 28, w = 100, h = 20 }, props = { text = "НАСТРОЙКИ" }, style = { bg = view == "settings" and "#1E3A8A" or C.panel, text = "#FFFFFF", font_size = 10, border_color = view == "settings" and C.accent or "#1E2538", border_width = 1 }, on_click = function() view = "settings" s = surfaces.settings ss.ui.activate("settings") render_settings() draw_navigation_tabs() end })
end

local function update_hardware_console()
    local name_hash = ic.hash("Central_ACCS_Console")
    local room_idx = settings_page or 1
    local disp_data = accs_data[room_idx]
    
    if disp_data == nil then return end

    local room_status = base_global_status == STATE_NOMINAL and disp_data.room_status or base_global_status

    local hardware_color = 0
    if room_status == STATE_NOMINAL then hardware_color = 2
    elseif room_status == STATE_WARNING then hardware_color = 1
    elseif room_status == STATE_CRITICAL then hardware_color = 4 end

    safe_batch_write_name(CONSOLE_2X2_HASH, name_hash, LT.Color, hardware_color)
    safe_batch_write_name(CONSOLE_2X2_HASH, name_hash, LT.Mode, disp_data.is_online and math.floor(disp_data.pressure) or 0)
end

-- ==================== СИСТЕМНЫЙ ЗАПУСК И ИНИЦИАЛИЗАЦИЯ ====================
s = surfaces.overview 
ss.ui.activate("overview") 

populate_device_caches()   -- СНАЧАЛА строим структуру кэшей
initialize_settings()      -- ЗАТЕМ безопасно накатываем из памяти (mem + persist)
render_overview() 
draw_navigation_tabs()

while true do
    elapsed = elapsed + 1
    refresh_accs_readings() 
    execute_accs_logic() 
    update_hardware_console()
    
    if view == "overview" then 
        render_overview() 
        draw_navigation_tabs() 
    elseif view == "settings" then
        render_settings()
        draw_navigation_tabs()
    end
    ic.yield()
end
-- А и Б сидели на трубе
