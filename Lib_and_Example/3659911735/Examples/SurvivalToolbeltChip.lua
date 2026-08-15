-- SurvivalToolbeltChip.lua - Lua chip running inside a Survival Toolbelt (Sanitation update)
-- Insert a Lua chip and a battery cell into the toolbelt's IC/battery slots.
-- The chip runs whenever the belt has a non-empty battery - it does not need to be
-- worn, and there is no on/off toggle (unlike suits and IC housings).
--
-- If the wearer's suit has a Wireless Development Board installed and connected to
-- an omni transmitter network, this chip shares that same wireless network - the
-- same behavior as Lua chips in suit IC slots.
--
-- READABLE/WRITABLE LogicTypes on the belt itself (SELF):
--   Volume, SoundAlert                      - the belt's own alert sound
--
-- READABLE-ONLY LogicTypes on the belt itself (SELF), resolved from the wearer:
--   EntityState                             - wearer's entity state
--   HealthDamage, StunDamage                - wearer's total / stun damage
--
-- ic.host_info().type is "toolbelt" for this host (vs "suit" for suit chips).

local LT   = ic.enums.LogicType
local read = ic.read

local SELF = ic.const.BASE_UNIT_INDEX
local LOG_INTERVAL = 10
local log_elapsed  = 0

local info = ic.host_info()
print(string.format("[ToolbeltChip] Running inside %s (type=%s, wearer=%s)",
    info.name or "toolbelt", info.type or "?", info.wearer or "nobody"))

function tick(dt)
    log_elapsed = log_elapsed + dt
    if log_elapsed < LOG_INTERVAL then return end
    log_elapsed = 0

    local health = read(SELF, LT.HealthDamage) or -1
    local stun   = read(SELF, LT.StunDamage) or -1
    local state  = read(SELF, LT.EntityState) or -1

    print(string.format(
        "[ToolbeltChip] Wearer health damage=%.1f stun damage=%.1f state=%d",
        health, stun, state
    ))
end
