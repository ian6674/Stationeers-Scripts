-- PersistExample.lua
-- Demonstrates ic.persist for custom state across save/load and housing power cycles.
-- Watch the Lua Debugger Logs tab. Power the housing off/on or save/reload the world to
-- verify mode and setpoint come back. Chip memory (mem_read/mem_write) is still best for
-- simple numeric counters only.

local KEY = "demo"
local LOG = "[PersistExample]"

local function load_state()
    if not ic.persist.has(KEY) then
        return nil
    end
    local raw = ic.persist.get(KEY)
    if type(raw) ~= "string" or raw == "" then
        return nil
    end
    local ok, t = pcall(util.json.decode, raw)
    return ok and t or nil
end

local function save_state(t)
    local ok, raw = pcall(util.json.encode, t)
    if ok and raw then
        if ic.persist.set(KEY, raw) then
            return true
        end
        print(LOG .. " ic.persist.set failed (size limits?)")
        return false
    end
    print(LOG .. " util.json.encode failed")
    return false
end

local mode = "auto"
local setpoint = 22.0
local tick_count = 0
local log_acc = 0

local saved = load_state()
if saved and type(saved) == "table" then
    mode = saved.mode or mode
    setpoint = saved.setpoint or setpoint
    tick_count = tonumber(saved.tick_count) or 0
    print(string.format(
        "%s Restored from ic.persist: mode=%s setpoint=%.1f tick_count=%d",
        LOG, mode, setpoint, tick_count
    ))
else
    print(string.format(
        "%s No saved state (defaults): mode=%s setpoint=%.1f",
        LOG, mode, setpoint
    ))
    print(LOG .. " Edit mode/setpoint below; save world or power-cycle housing to test restore.")
end

function tick(dt)
    tick_count = tick_count + 1
    log_acc = log_acc + (dt or 0)

    -- Slowly drift setpoint so you can see live values change, then restore after reload.
    if mode == "auto" then
        setpoint = setpoint + 0.05
        if setpoint > 26.0 then setpoint = 22.0 end
    end

    save_state({ mode = mode, setpoint = setpoint, tick_count = tick_count })
    ic.write(ic.const.BASE_UNIT_INDEX, ic.enums.LogicType.Setting, setpoint)

    if log_acc >= 10.0 then
        log_acc = 0
        print(string.format(
            "%s tick=%d mode=%s setpoint=%.1f (written to Setting, saved to ic.persist)",
            LOG, tick_count, mode, setpoint
        ))
    end
end
