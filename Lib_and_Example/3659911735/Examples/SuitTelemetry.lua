-- SuitTelemetry.lua - Suit chip that broadcasts vital stats over pub/sub
-- Pair with SuitDashboard.lua (ScriptedScreens) to display per-player
-- suit telemetry on a wall-mounted console or tablet.
--
-- Requirements:
--   - Lua chip installed in any suit (HardSuit, SpaceSuit, etc.)
--   - Wireless Development Board installed in the same suit, connected
--     to an omni transmitter network that the dashboard console shares.
--
-- Published topic: "suit/telemetry"
-- Payload: vitals plus loadout[] (pins 0-5: helmet…hands). Each entry:
--   label, item, detail, optional open (raw), open_str ("open"/"closed"/ajar…).
-- Helmet visor: LST.Open on any slot, else ic.read(pin, LT.Open). Other slots:
-- full slot scan + top-level logic (On, Lock, Vol, PrefabHash, …)
--
-- Engine limit (same for IC10 d0-d5 on a suit chip): only valid logic devices will show on the dashboard (electronic gear only mostly)
--
-- Also runs a coroutine that monitors the wireless connection status and
-- logs changes to the debugger (ic.wireless API demo).

local LT  = ic.enums.LogicType
local LST = ic.enums.LogicSlotType
local read = ic.read
local SELF = ic.const.BASE_UNIT_INDEX

local PIN_LABELS = {
    [0] = "helmet",
    [1] = "backpack",
    [2] = "toolbelt",
    [3] = "glasses",
    [4] = "left_hand",
    [5] = "right_hand",
}
local PIN_HELMET, PIN_HAND_L, PIN_HAND_R = 0, 4, 5

local PUBLISH_INTERVAL = 5
local elapsed = 0

local info = ic.host_info()
print("[SuitTelemetry] Started for " .. (info.wearer or "no wearer (suit not equipped)"))

local function safe_read(dev, logicType)
    local ok, v = pcall(ic.read, dev, logicType)
    if ok then return v end
    return nil
end

local function safe_read_slot(dev, slotIdx, slotLogic)
    local ok, v = pcall(ic.read_slot, dev, slotIdx, slotLogic)
    if ok then return v end
    return nil
end

local function safe_device_name(pin)
    local ok, n = pcall(ic.device_name, pin)
    if ok and n ~= nil and type(n) == "string" and n ~= "" then
        return n
    end
    return nil
end

local function scan_occupied_slots(pin, maxSlot)
    local firstIdx, firstOcc = nil, nil
    for s = 0, maxSlot do
        local occ = safe_read_slot(pin, s, LST.Occupied)
        if occ ~= nil then
            if firstIdx == nil then
                firstIdx, firstOcc = s, occ
            end
            if occ ~= 0 then
                return s, occ
            end
        end
    end
    if firstIdx ~= nil then
        return firstIdx, firstOcc
    end
    return nil, nil
end

--- Visor / hatch: slot Open first (any slot), then top-level Open on the worn item.
local function read_open_state(pin)
    for s = 0, 7 do
        local o = safe_read_slot(pin, s, LST.Open)
        if o ~= nil then
            return o, "slot" .. tostring(s)
        end
    end
    local top = safe_read(pin, LT.Open)
    if top ~= nil then
        return top, "device"
    end
    return nil, nil
end

local function fmt_open_phrase(v)
    if v == nil then
        return nil
    end
    if v == 0 then
        return "closed", v
    end
    if v == 1 then
        return "open", v
    end
    return string.format("ajar %.2f", v), v
end

--- Non-electronic gear often has no ic.device_name; still expose logic + slot hashes.
local function append_top_level_probe(pin, parts)
    -- Open is reported above via read_open_state (slot + device); skip duplicate here.
    local probes = {
        { "On",    LT.On },
        { "Lock",  LT.Lock },
        { "Set",   LT.Setting },
        { "Mode",  LT.Mode },
        { "Vol",   LT.Volume },
        { "Qty",   LT.Quantity },
        { "Chg",   LT.Charge },
        { "Pwr",   LT.Power },
        { "Temp",  LT.Temperature },
        { "PH",    LT.PrefabHash },
        { "Ref",   LT.ReferenceId },
    }
    for _, pr in ipairs(probes) do
        local v = safe_read(pin, pr[2])
        if v ~= nil then
            table.insert(parts, pr[1] .. "=" .. tostring(v))
        end
    end
end

--- Scan every slot for anything readable (backpack slots, toolbelt, etc.).
local function append_slot_scan(pin, parts, maxSlot)
    maxSlot = maxSlot or 7
    for s = 0, maxSlot do
        local occ = safe_read_slot(pin, s, LST.Occupied)
        local oh  = safe_read_slot(pin, s, LST.OccupantHash)
        local ph  = safe_read_slot(pin, s, LST.PrefabHash)
        local q   = safe_read_slot(pin, s, LST.Quantity)
        local o   = safe_read_slot(pin, s, LST.Open)
        if occ ~= nil or oh ~= nil or ph ~= nil or q ~= nil or o ~= nil then
            local bits = { "s" .. tostring(s) }
            if occ ~= nil then table.insert(bits, "occ=" .. tostring(occ)) end
            if oh  ~= nil then table.insert(bits, "oh=" .. tostring(oh)) end
            if ph  ~= nil and ph ~= oh then table.insert(bits, "ph=" .. tostring(ph)) end
            if q   ~= nil then table.insert(bits, "qty=" .. tostring(q)) end
            if o   ~= nil then table.insert(bits, "open=" .. tostring(o)) end
            table.insert(parts, table.concat(bits, ":"))
        end
    end
end

local function clip_detail(s, maxLen)
    if s == nil or s == "" then
        return ""
    end
    if #s <= maxLen then
        return s
    end
    return string.sub(s, 1, maxLen - 1) .. "…"
end

--- One equipment row for the dashboard (MessagePack-safe: numbers + strings only).
local function describe_pin(pin)
    local label = PIN_LABELS[pin] or ("pin_" .. tostring(pin))
    local dname = safe_device_name(pin)
    local slotIdx, occ = scan_occupied_slots(pin, 7)

    local open_raw, open_src = read_open_state(pin)
    local open_phrase, open_norm = fmt_open_phrase(open_raw)

    local function item_with_helmet_visor(base)
        if pin ~= PIN_HELMET or not open_phrase then
            return base or ""
        end
        local b = base or ""
        if b == "" then
            return "visor: " .. open_phrase
        end
        return b .. "  ·  " .. open_phrase
    end

    local function fallback_item_name()
        if dname and dname ~= "" then
            return dname
        end
        local ph = safe_read(pin, LT.PrefabHash)
        if ph ~= nil then
            return "prefab #" .. tostring(math.floor(ph))
        end
        if slotIdx ~= nil then
            local h = safe_read_slot(pin, slotIdx, LST.OccupantHash)
                or safe_read_slot(pin, slotIdx, LST.PrefabHash)
            if h ~= nil then
                return "slot hash " .. tostring(h)
            end
        end
        return ""
    end

    local parts = {}

    if slotIdx ~= nil then
        table.insert(parts, string.format("slot %d  occ=%s", slotIdx, tostring(occ)))
        local ph  = safe_read_slot(pin, slotIdx, LST.PrefabHash)
        local oh  = safe_read_slot(pin, slotIdx, LST.OccupantHash)
        local rid = safe_read_slot(pin, slotIdx, LST.ReferenceId)
        local h = ph or oh
        if h ~= nil then
            table.insert(parts, "hash=" .. tostring(h))
        end
        if rid ~= nil then
            table.insert(parts, "ref=" .. tostring(rid))
        end
    end

    if pin == PIN_HELMET and open_raw ~= nil then
        table.insert(parts, (open_src or "open") .. "=" .. tostring(open_raw))
    elseif pin ~= PIN_HELMET and open_raw ~= nil then
        table.insert(parts, "Open=" .. tostring(open_raw))
    end

    append_slot_scan(pin, parts, 7)
    append_top_level_probe(pin, parts)

    local detail = clip_detail(table.concat(parts, "  "), 200)

    local item = item_with_helmet_visor(fallback_item_name())

    if detail == "" then
        if dname then
            detail = "ic: " .. dname
        else
            detail = "no slot/logic reads"
        end
    end

    local row = {
        pin     = pin,
        label   = label,
        item    = item,
        detail  = detail,
        open    = open_norm,
        open_str = open_phrase,
    }
    return row
end

local function collect_loadout()
    local out = {}
    for pin = 0, 5 do
        table.insert(out, describe_pin(pin))
    end
    return out
end

-- Coroutine: watch wireless connection and log changes
local function wireless_monitor()
    local last_connected = nil
    local last_name = ""
    while true do
        local ws = ic.wireless.status()
        if not ws.available then
            if last_connected ~= nil then
                print("[Wireless] No wireless board detected")
                last_connected = nil
                last_name = ""
            end
        elseif ws.connected and ws.in_range then
            local name = ws.transmitter_name or ""
            if last_connected ~= true or name ~= last_name then
                print(string.format("[Wireless] Connected to %s (net %d, %.0fm / %.0fm)",
                    name ~= "" and name or "unnamed",
                    ws.network_id, ws.distance, ws.max_distance))
                last_connected = true
                last_name = name
            end
        elseif ws.connected and not ws.in_range then
            if last_connected ~= false then
                print("[Wireless] Out of range - reconnecting...")
                last_connected = false
                last_name = ""
            end
        else
            if last_connected ~= nil then
                print("[Wireless] Disconnected")
                last_connected = nil
                last_name = ""
            end
        end
        sleep(3)
    end
end

coroutine.resume(coroutine.create(wireless_monitor))

function tick(dt)
    elapsed = elapsed + dt
    if elapsed < PUBLISH_INTERVAL then return end
    elapsed = 0

    local h = ic.host_info()
    local player = h.wearer

    -- Don't publish when suit is not worn (in inventory, suit storage, etc.)
    if not player or player == "" then return end

    local stats = {
        player       = player,
        ext_pressure = read(SELF, LT.PressureExternal) or 0,
        ext_temp     = read(SELF, LT.TemperatureExternal) or 0,
        int_pressure = read(SELF, LT.Pressure) or 0,
        o2_ratio     = read(SELF, LT.RatioOxygen) or 0,
        pos_x        = read(SELF, LT.PositionX) or 0,
        pos_y        = read(SELF, LT.PositionY) or 0,
        pos_z        = read(SELF, LT.PositionZ) or 0,
        loadout      = collect_loadout(),
    }

    ic.net.publish("suit/telemetry", stats, { retain = true, ttl = 30 })
end
