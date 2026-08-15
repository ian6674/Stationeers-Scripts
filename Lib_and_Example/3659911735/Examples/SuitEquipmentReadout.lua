-- SuitEquipmentReadout.lua - read worn gear via suit device pins (same mapping as vanilla IC10)
--
-- Install: Lua chip in the suit's chip slot; wear the suit. Prints a summary every few seconds.
--
-- The suit is the circuit holder. Device indices resolve to the player's equipment as ILogicable:
--   0 = Helmet        3 = Glasses
--   1 = Backpack      4 = Left hand item
--   2 = Toolbelt      5 = Right hand item
--   ic.const.BASE_UNIT_INDEX = the suit itself (SELF)
--
-- ic.read(pin, LogicType)        - top-level logic on that worn item (when supported)
-- ic.read_slot(pin, slot, LogicSlotType) - per-slot reads on devices that expose them (tanks, racks, …)
--
-- Helmet prefabs (e.g. GasMask) are often NOT multi-slot Devices: Occupied@slot0 may be unreadable
-- even with a mask on - use ic.read(pin, LT.On) / LT.Volume in that case.
-- StationeersLua allows suit pins 3-5 on SuitBase (vanilla IsValidIndex only listed 0-2; IC mapping
-- still resolves glasses/hands via GetLogicableFromIndex).
--
-- If a hand (or other) slot holds a plain Item (not ILogicable), GetLogicableFromIndex returns null
-- for that pin - vanilla IC10 cannot see it either. Only Device / logic-capable occupants expose reads.

local LT  = ic.enums.LogicType
local LST = ic.enums.LogicSlotType

local SELF       = ic.const.BASE_UNIT_INDEX
local PIN_HELMET = 0
local PIN_HAND_L = 4
local PIN_HAND_R = 5

local PIN_LABELS = {
    [0] = "helmet",
    [1] = "backpack",
    [2] = "toolbelt",
    [3] = "glasses",
    [4] = "left_hand",
    [5] = "right_hand",
}

local LOG_INTERVAL = 8.0
local log_elapsed  = 0

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

--- First slot index where Occupied read succeeds; prefer a non-empty slot when scanning.
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

local function append_hash_line(line, pin, slotIdx)
    if slotIdx == nil then
        return line
    end
    local ph  = safe_read_slot(pin, slotIdx, LST.PrefabHash)
    local oh  = safe_read_slot(pin, slotIdx, LST.OccupantHash)
    local rid = safe_read_slot(pin, slotIdx, LST.ReferenceId)
    local h = ph or oh
    if h ~= nil or rid ~= nil then
        line = line .. string.format("  hash=%s  ref=%s", tostring(h), tostring(rid))
    end
    return line
end

local function describe_pin(pin)
    local label = PIN_LABELS[pin] or ("pin_" .. tostring(pin))
    local dname = safe_device_name(pin)

    local slotIdx, occ = scan_occupied_slots(pin, 7)
    if slotIdx == nil then
        if pin == PIN_HELMET then
            local on  = safe_read(pin, LT.On)
            local vol = safe_read(pin, LT.Volume)
            if on ~= nil or vol ~= nil then
                local bits = {}
                if dname then table.insert(bits, "item=" .. dname) end
                if on ~= nil then table.insert(bits, "On=" .. tostring(on)) end
                if vol ~= nil then table.insert(bits, "Volume=" .. tostring(vol)) end
                return string.format("  %-12s  helmet logic: %s", label, table.concat(bits, "  "))
            end
        end
        local hint = dname and ("  (ic sees item: " .. dname .. ")") or ""
        return string.format("  %-12s  no Occupied read on slots 0-7%s", label, hint)
    end

    local line = string.format("  %-12s  slot%d Occupied=%s", label, slotIdx, tostring(occ))
    if dname then
        line = line .. "  item=" .. dname
    end
    line = append_hash_line(line, pin, slotIdx)

    if pin == PIN_HELMET then
        local open = safe_read_slot(pin, slotIdx, LST.Open)
        if open == nil and slotIdx ~= 0 then
            open = safe_read_slot(pin, 0, LST.Open)
        end
        if open ~= nil then
            line = line .. string.format("  Open=%s", tostring(open))
        end
    end

    if pin == PIN_HAND_L or pin == PIN_HAND_R then
        local on = safe_read(pin, LT.On)
        if on ~= nil then
            line = line .. string.format("  device.On=%s", tostring(on))
        end
    end

    return line
end

print("[SuitEquipmentReadout] Logging suit pins every " .. tostring(LOG_INTERVAL) .. "s (see script header)")

function tick(dt)
    log_elapsed = log_elapsed + dt
    if log_elapsed < LOG_INTERVAL then
        return
    end
    log_elapsed = 0

    local intP = safe_read(SELF, LT.Pressure)
    local suitOn = safe_read(SELF, LT.On)
    print(string.format(
        "[SuitEquipmentReadout] SELF On=%s  internalPressure=%s kPa",
        tostring(suitOn),
        intP ~= nil and string.format("%.1f", intP) or "n/a"
    ))

    for pin = 0, 5 do
        print(describe_pin(pin))
    end
end
