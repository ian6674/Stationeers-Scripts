-- SurvivalBeltAutoInjector.lua - automated medical response via the Survival Belt (Sanitation update)
--
-- Insert a Lua chip and a battery into the belt's own IC/battery slots, then load one or more
-- Auto-Injectors (Stim / Stun / Health) into the belt's dedicated Auto-Injector slots. Wear the belt.
--
-- Like the Advanced Tablet, the belt can read and write its own internal slots - so a chip running
-- inside it can watch the wearer's condition and fire an injector automatically. This script does
-- not assume which physical slot holds which injector type (you may only load two of the three, in
-- either order): it scans the belt's own slots each cycle and identifies injectors BY NAME via
-- ic.device_name(), the same way ic.device_name() already identifies items in suit hand/helmet slots.
--
-- ic.host_info().type == "toolbelt" identifies this host (vs "suit" for suit-installed chips).
--
-- SELF (ic.const.BASE_UNIT_INDEX) LogicTypes - read the WEARER, resolved by the belt itself:
--   EntityState   - wearer's entity state
--   HealthDamage  - wearer's total damage (0 = healthy); only resolves while the belt is worn
--   StunDamage    - wearer's stun damage (rises while stunned/knocked down); only while worn
--
-- Sub-slot access (same mechanism as suit pins 0-5 in SuitEquipmentReadout.lua): each of the belt's
-- own slots is addressable as a device "pin" (0..7). ic.write(pin, LT.Activate, 1) fires whatever
-- Auto-Injector occupies that pin - vanilla only allows this while the belt sits in a worn Human's
-- toolbelt slot (see Injector.SetLogicValue in the game's source); writes while unworn/holstered are
-- silently ignored rather than erroring.
--
-- Tune the thresholds below to taste, and flip AUTO_HEALTH / AUTO_STUN / AUTO_STIM off if you'd
-- rather trigger a given injector type by hand instead.

local LT  = ic.enums.LogicType
local LST = ic.enums.LogicSlotType

local SELF = ic.const.BASE_UNIT_INDEX
local MAX_SLOT = 7          -- Survival Belt has the same slot count as the Mk2 Toolbelt (8 slots, 0-7).

local SCAN_INTERVAL = 5.0   -- Re-scan slot contents this often (injectors are consumed on use).
local TICK_INTERVAL = 1.0   -- How often to check wearer condition and possibly fire an injector.

-- Auto-fire thresholds - adjust to taste.
local HEALTH_DAMAGE_THRESHOLD = 30.0
local STUN_DAMAGE_THRESHOLD   = 50.0

local AUTO_HEALTH = true
local AUTO_STUN   = true
local AUTO_STIM   = false   -- Stim is a buff, not a rescue response - off by default.
                             -- Flip to true and add your own trigger condition below to use it.

local scan_elapsed = 0
local tick_elapsed  = 0
local injector_pin  = { health = nil, stun = nil, stim = nil }

local function safe_read(pin, logicType)
    local ok, v = pcall(ic.read, pin, logicType)
    if ok then return v end
    return nil
end

local function safe_read_slot(pin, slotLogic)
    local ok, v = pcall(ic.read_slot, SELF, pin, slotLogic)
    if ok then return v end
    return nil
end

local function safe_device_name(pin)
    local ok, name = pcall(ic.device_name, pin)
    if ok and type(name) == "string" and name ~= "" then
        return name
    end
    return nil
end

--- Re-scans the belt's own slots and records which pin currently holds which injector type,
--- matched by display name. Works regardless of physical slot order or which two injector
--- types you loaded, and re-detects a fresh injector after the old one is consumed.
local function scan_injectors()
    injector_pin.health = nil
    injector_pin.stun   = nil
    injector_pin.stim   = nil

    for pin = 0, MAX_SLOT do
        if safe_read_slot(pin, LST.Occupied) == 1 then
            local name = safe_device_name(pin)
            if name then
                local lower = string.lower(name)
                if string.find(lower, "health") then
                    injector_pin.health = pin
                elseif string.find(lower, "stun") then
                    injector_pin.stun = pin
                elseif string.find(lower, "stim") or string.find(lower, "epi") then
                    injector_pin.stim = pin
                end
            end
        end
    end
end

--- Fires the injector at `pin`. Vanilla only allows this while the belt is worn by a Human;
--- otherwise the write is silently ignored (not an error).
local function fire_injector(pin, label)
    if pin == nil then return end
    ic.write(pin, LT.Activate, 1)
    print(string.format("[SurvivalBelt] Fired %s injector (pin %d)", label, pin))
end

print("[SurvivalBelt] Auto-injector responder running - scanning belt slots...")
scan_injectors()

function tick(dt)
    scan_elapsed = scan_elapsed + dt
    if scan_elapsed >= SCAN_INTERVAL then
        scan_elapsed = 0
        scan_injectors()
    end

    tick_elapsed = tick_elapsed + dt
    if tick_elapsed < TICK_INTERVAL then return end
    tick_elapsed = 0

    -- These read -1 (not 0) when the belt is not currently worn - see SurvivalToolbelt.GetLogicValue.
    local healthDamage = safe_read(SELF, LT.HealthDamage) or -1
    local stunDamage    = safe_read(SELF, LT.StunDamage) or -1

    if AUTO_HEALTH and injector_pin.health and healthDamage >= HEALTH_DAMAGE_THRESHOLD then
        fire_injector(injector_pin.health, "Health")
        injector_pin.health = nil -- consumed; the next scan will notice a reload
    end

    if AUTO_STUN and injector_pin.stun and stunDamage >= STUN_DAMAGE_THRESHOLD then
        fire_injector(injector_pin.stun, "Stun")
        injector_pin.stun = nil
    end

    -- Stim (Epi-Injector) is off by default - wire up your own condition here if you want it,
    -- e.g. auto-fire before a long EVA or when carrying a heavy load.
    -- if AUTO_STIM and injector_pin.stim and <your condition> then
    --     fire_injector(injector_pin.stim, "Stim")
    --     injector_pin.stim = nil
    -- end
end
