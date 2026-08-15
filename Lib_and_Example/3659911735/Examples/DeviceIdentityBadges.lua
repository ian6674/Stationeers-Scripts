-- DeviceIdentityBadges.lua
--
-- Demonstrates:
-- - `prefab_name(prefabHash)` (prefab hash -> prefab name)
-- - `device_name(deviceIndex[, networkIndex])` (device slot -> live DisplayName)
-- - `namehash_name(deviceHash, nameHash[, networkIndex])` (deviceHash+nameHash -> live DisplayName)
--
-- The script writes a compact "badge" into each housing slot label.

local LT = ic.enums.LogicType

-- How many housing slots to scan (d0..dN-1)
local DEVICE_COUNT = 6

-- Seconds between relabel passes
local UPDATE_INTERVAL = 1.0

local acc = 0
local lastLabel = {}

local MAX_LABEL_LEN = 10

local function round_to_int(v)
    if type(math.tointeger) == "function" then
        local i = math.tointeger(v)
        if i ~= nil then
            return i
        end
    end

    if v >= 0 then
        return math.floor(v + 0.5)
    end

    return math.ceil(v - 0.5)
end

local function set_slot_label(slotIndex, text)
    device_label(slotIndex, text)
end

local function clamp_label(text)
    if text == nil then
        return ""
    end

    if #text > MAX_LABEL_LEN then
        return string.sub(text, 1, MAX_LABEL_LEN)
    end

    return text
end

local function strip_common_prefixes(text)
    if text == nil then
        return ""
    end

    local prefixes = {
        "Structure",
        "Item",
        "Device",
        "Logic",
    }

    for _, p in ipairs(prefixes) do
        if string.sub(text, 1, #p) == p then
            return string.sub(text, #p + 1)
        end
    end

    return text
end

local function compact_words(text)
    if text == nil then
        return ""
    end

    text = text:gsub("<.->", "")
    text = text:gsub("[^%w%s]", "")

    local words = {}
    for w in text:gmatch("%w+") do
        table.insert(words, w)
    end

    if #words <= 1 then
        return text:gsub("%s+", "")
    end

    local out = ""
    for _, w in ipairs(words) do
        out = out .. string.sub(w, 1, 4)
    end

    return out
end

local function make_short_label(slotIndex)
    local liveName = device_name(slotIndex)
    if liveName ~= nil and liveName ~= "" then
        return clamp_label(compact_words(liveName))
    end

    local prefabHashValue = ic.read(slotIndex, LT.PrefabHash)
    if prefabHashValue ~= nil then
        local prefabHash = round_to_int(prefabHashValue)
        local prefab = prefab_name(prefabHash)
        if prefab ~= nil and prefab ~= "" then
            prefab = strip_common_prefixes(prefab)
            return clamp_label(prefab)
        end
    end

    return ""
end

local function relabel_all()
    for i = 0, DEVICE_COUNT - 1 do
        local label = make_short_label(i)
        if label == "" then
            label = ""
        end

        if lastLabel[i] ~= label then
            lastLabel[i] = label
            set_slot_label(i, label)
        end
    end
end

function tick(dt)
    acc = acc + (dt or 0)
    if acc < UPDATE_INTERVAL then
        return
    end

    acc = 0
    relabel_all()
end
