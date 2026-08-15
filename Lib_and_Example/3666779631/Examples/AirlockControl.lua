-- Airlock Control System
-- Tick-driven state machine for single-vent and dual-vent airlock designs.
-- Auto-detects whether d4 has a device: if yes, dual-vent mode; if no, single-vent.
--
-- DEVICE SLOTS:
--   d0 = Inner door (hab / pressurized side)
--   d1 = Outer door (vacuum / external side)
--   d2 = Gas sensor (inside airlock chamber)
--   d3 = Vent A - pressurization (Active Vent, Inward mode)
--   d4 = Vent B - depressurization (Active Vent, Outward mode) [OPTIONAL]
--
-- SINGLE-VENT MODE (d4 empty):
--   d3 switches between Outward/Inward automatically, AND the ExternalPressure
--   target is written each time - required because changing Mode via IC does NOT
--   call the game's internal ResetVent(), so thresholds must be set explicitly.
--
-- DUAL-VENT MODE (d4 connected):
--   d3 always Outward (pressurize), d4 always Inward (depressurize).
--   Pressure thresholds are still written at each cycle start for safety.
--
-- CYCLE FLOW:
--   Button press → SEALING (close+lock both doors, wait for LT.Idle confirmation)
--               → DEPRESSURIZE or PRESSURIZE (vent running)
--               → IDLE (unlock + open target door)
--
-- SAFETY:
--   - Doors must confirm fully closed (LT.Idle = 1) before any vent activates
--   - If either door opens during an active cycle, vents stop immediately
--   - Both doors unlocked on any abort - never leave player locked out
--   - Timeout returns to IDLE with warning (not a sticky error state)

local LT              = ic.enums.LogicType
local read            = ic.read
local write           = ic.write
local yield           = ic.yield

-- ==================== CONFIGURATION ====================
-- Edit these constants to match your build.

local VACUUM_KPA      = 1  -- below this = safe to open outer door
local PRESSURED_KPA   = 90 -- above this = safe to open inner door
local TIMEOUT_SEC     = 60 -- max vent time before auto-abort
local SEAL_TIMEOUT    = 5  -- max seconds to wait for doors to confirm closed

local INNER_SLOT      = 0  -- d0: inner door
local OUTER_SLOT      = 1  -- d1: outer door
local SENSOR_SLOT     = 2  -- d2: gas sensor
local VENT_A_SLOT     = 3  -- d3: pressurize vent (or shared single-vent)
local VENT_B_SLOT     = 4  -- d4: depressurize vent (optional)

-- Active Vent pressure targets written to the vent at cycle start.
-- These mirror what ResetVent() would set internally but ResetVent() is only
-- called on wrench interaction, NOT on IC Mode writes - so we must set them.
local PRESS_EXT_KPA   = 101.325 -- Outward ExternalPressure: pump room UP to ~1 atm
local PRESS_INT_KPA   = 0       -- Outward InternalPressure: deplete pipe fully
local DEPRESS_EXT_KPA = 0       -- Inward ExternalPressure:  pump room DOWN to vacuum
local DEPRESS_INT_KPA = 50000   -- Inward InternalPressure:  allow very high pipe pressure

-- ==================== STATE ====================

-- Active Vent Mode values (VentDirection enum in game source):
--   0 = Outward - pushes gas FROM pipe network INTO the room (pressurize)
--   1 = Inward  - pulls gas FROM the room INTO the pipe network (depressurize)
local VENT_OUTWARD    = 0
local VENT_INWARD     = 1

local S_IDLE          = 0
local S_SEALING       = 1 -- both doors closing, waiting for LT.Idle confirmation
local S_DEPRESS       = 2 -- vent actively depressurizing airlock
local S_PRESS         = 3 -- vent actively pressurizing airlock

local state           = S_IDLE
local cycle_start     = 0     -- os.clock() timestamp when current phase began
local cycle_target    = nil   -- "inner" or "outer": which door to open at end
local cycle_pump      = false -- true = needs vent cycle; false = direct open after seal
local dual_vent       = false -- auto-detected each tick

-- Warning system: transient messages that auto-clear after WARN_DURATION seconds
local warn_text       = ""
local warn_time       = 0
local WARN_DURATION   = 6

local status_text     = "Ready"

-- ==================== COLORS ====================

local C               = {
    bg     = "#0D1117",
    header = "#161B22",
    panel  = "#21262D",
    accent = "#58A6FF",
    green  = "#3FB950",
    yellow = "#D29922",
    red    = "#F85149",
    purple = "#9B59B6",
    text   = "#E6EDF3",
    dim    = "#8B949E",
    muted  = "#484F58",
}

-- ==================== HELPERS ====================

local function now() return os.clock() end

local function fmt_kpa(v)
    if v == nil then return "-- kPa" end
    return string.format("%.1f kPa", v)
end

local function fmt_temp(v)
    if v == nil then return "" end
    return string.format("%.0f °C", v)
end

local function warn(msg)
    warn_text = msg
    warn_time = now()
end

-- ==================== DEVICE I/O ====================

local function read_pressure()
    return read(SENSOR_SLOT, LT.Pressure) -- already kPa
end

local function read_temp()
    local t = read(SENSOR_SLOT, LT.Temperature)
    if t == nil then return nil end
    return t - 273.15 -- K -> C
end

local function door_open(slot)
    local v = read(slot, LT.Open)
    return v ~= nil and v > 0
end

-- A door is "sealed" when it is closed (Open=0) AND finished animating (Idle=1).
-- LT.Idle on Door returns: 0 = door is actively animating, 1 = door is static.
-- We treat a nil Idle (e.g. door doesn't support it) as sealed to avoid deadlock.
local function door_sealed(slot)
    local open = read(slot, LT.Open)
    if open ~= nil and open > 0 then return false end  -- door is open
    local idle = read(slot, LT.Idle)
    if idle ~= nil and idle == 0 then return false end -- door is still moving
    return true
end

local function set_door(slot, open)
    write(slot, LT.Open, open and 1 or 0)
end

local function lock_door(slot, locked)
    write(slot, LT.Lock, locked and 1 or 0)
end

-- Auto-detect dual vent: d4 is present if any read from it returns a value
local function detect_dual_vent()
    return read(VENT_B_SLOT, LT.On) ~= nil
end

-- Activate/deactivate the pressurization vent.
-- Also writes ExternalPressure and InternalPressure targets - required because
-- switching Mode via IC does NOT call ResetVent() internally, leaving stale
-- thresholds that would cause the vent to do nothing or stop immediately.
local function vent_pressurize(active)
    if active then
        if dual_vent then
            -- Dedicated Outward vent on d3 - just set targets and enable
            write(VENT_A_SLOT, LT.PressureExternal, PRESS_EXT_KPA)
            write(VENT_A_SLOT, LT.PressureInternal, PRESS_INT_KPA)
        else
            -- Single vent: switch to Outward first, then set targets
            write(VENT_A_SLOT, LT.Mode, VENT_OUTWARD)
            write(VENT_A_SLOT, LT.PressureExternal, PRESS_EXT_KPA)
            write(VENT_A_SLOT, LT.PressureInternal, PRESS_INT_KPA)
        end
    end
    write(VENT_A_SLOT, LT.On, active and 1 or 0)
end

-- Activate/deactivate the depressurization vent.
local function vent_depressurize(active)
    local slot = dual_vent and VENT_B_SLOT or VENT_A_SLOT
    if active then
        if not dual_vent then
            -- Single vent: switch to Inward first
            write(VENT_A_SLOT, LT.Mode, VENT_INWARD)
        end
        write(slot, LT.PressureExternal, DEPRESS_EXT_KPA)
        write(slot, LT.PressureInternal, DEPRESS_INT_KPA)
    end
    write(slot, LT.On, active and 1 or 0)
end

local function stop_vents()
    write(VENT_A_SLOT, LT.On, 0)
    if dual_vent then write(VENT_B_SLOT, LT.On, 0) end
end

-- ==================== CYCLE LOGIC ====================

-- Begin a cycle: close+lock both doors and enter SEALING state.
-- target = "inner" or "outer" (which door to open at end)
-- pump   = true if a pressure cycle is needed; false for direct open
local function start_seal(target, pump)
    state        = S_SEALING
    cycle_target = target
    cycle_pump   = pump
    cycle_start  = now()
    status_text  = "Sealing…"
    set_door(INNER_SLOT, false)
    set_door(OUTER_SLOT, false)
    lock_door(INNER_SLOT, true)
    lock_door(OUTER_SLOT, true)
end

local function finish_cycle_open(slot, msg)
    stop_vents()
    lock_door(slot, false)
    set_door(slot, true)
    state        = S_IDLE
    cycle_target = nil
    status_text  = msg
end

local function abort_cycle(reason)
    stop_vents()
    -- Always unlock both doors on abort so nobody gets trapped
    lock_door(INNER_SLOT, false)
    lock_door(OUTER_SLOT, false)
    state        = S_IDLE
    cycle_target = nil
    status_text  = "Ready"
    warn(reason)
end

-- Called every tick while state ~= S_IDLE
local function update_cycle(pressure)
    -- ── SEALING phase: wait for both doors to confirm fully closed ──
    if state == S_SEALING then
        if door_sealed(INNER_SLOT) and door_sealed(OUTER_SLOT) then
            -- Doors confirmed closed - transition to next phase
            if not cycle_pump then
                -- No pressure cycle needed: just open the target door directly
                local slot = (cycle_target == "inner") and INNER_SLOT or OUTER_SLOT
                local msg  = (cycle_target == "inner") and "Inner door open" or "Outer door open"
                finish_cycle_open(slot, msg)
            elseif cycle_target == "outer" then
                state       = S_DEPRESS
                cycle_start = now()
                status_text = "Depressurizing…"
                vent_depressurize(true)
            else
                state       = S_PRESS
                cycle_start = now()
                status_text = "Pressurizing…"
                vent_pressurize(true)
            end
        elseif now() - cycle_start > SEAL_TIMEOUT then
            -- Door stuck or blocked (player in doorway, physics issue, etc.)
            abort_cycle("Doors failed to seal - path may be blocked")
        end
        return
    end

    -- ── Active vent phase ──

    -- Safety: abort immediately if a door opens during venting
    -- (e.g. another player manually opens a door while cycle is running)
    if door_open(INNER_SLOT) or door_open(OUTER_SLOT) then
        abort_cycle("Door opened during cycle!")
        return
    end

    -- Sensor failure: warn but keep trying - don't abort the whole cycle
    if pressure == nil then
        warn("Sensor not responding - retrying")
        return
    end

    -- Timeout: give up and return to IDLE, unlocking both doors
    if now() - cycle_start > TIMEOUT_SEC then
        abort_cycle("Timeout - check vent pipe network")
        return
    end

    -- Check if target pressure has been reached
    if state == S_DEPRESS and pressure < VACUUM_KPA then
        finish_cycle_open(OUTER_SLOT, "Outer door open")
    elseif state == S_PRESS and pressure >= PRESSURED_KPA then
        finish_cycle_open(INNER_SLOT, "Inner door open")
    end
end

-- ==================== BUTTON HANDLERS ====================

local function on_inner(player)
    if state ~= S_IDLE then return end
    local p = read_pressure()
    -- pump=false if already pressurized: seal first, then direct open
    -- pump=true if at partial/vacuum pressure: seal, then pressurize, then open
    start_seal("inner", p == nil or p < PRESSURED_KPA)
end

local function on_outer(player)
    if state ~= S_IDLE then return end
    local p = read_pressure()
    -- pump=false if already at vacuum: seal first, then direct open
    -- pump=true if still pressurized: seal, then depressurize, then open
    start_seal("outer", p == nil or p >= VACUUM_KPA)
end

local function on_seal(player)
    stop_vents()
    set_door(INNER_SLOT, false)
    set_door(OUTER_SLOT, false)
    lock_door(INNER_SLOT, true)
    lock_door(OUTER_SLOT, true)
    state        = S_IDLE
    cycle_target = nil
    status_text  = "Sealed"
end

local function on_cancel(player)
    abort_cycle("Cycle cancelled")
end

-- ==================== UI BUILD (one-time) ====================

local ui = ss.ui.surface("main")
ss.ui.activate("main")
local sz = ui:size()
local W, H = sz.w or 480, sz.h or 272

ui:clear()

-- Background
ui:element({
    id = "bg",
    type = "panel",
    rect = { unit = "px", x = 0, y = 0, w = W, h = H },
    style = { bg = C.bg }
})

-- Header bar
local hdr = ui:element({
    id = "hdr",
    type = "panel",
    rect = { unit = "px", x = 0, y = 0, w = W, h = 44 },
    style = { bg = C.header }
})
hdr:element({
    id = "title",
    type = "label",
    rect = { unit = "px", x = 14, y = 10, w = 160, h = 24 },
    props = { text = "AIRLOCK CONTROL" },
    style = { font_size = 16, color = C.text, align = "left" }
})
hdr:element({
    id = "state_dot",
    type = "panel",
    rect = { unit = "px", x = W - 24, y = 17, w = 10, h = 10 },
    style = { bg = C.green }
})
hdr:element({
    id = "state_lbl",
    type = "label",
    rect = { unit = "px", x = W - 130, y = 12, w = 100, h = 20 },
    props = { text = "IDLE" },
    style = { font_size = 11, color = C.green, align = "right" }
})
hdr:element({
    id = "vent_mode",
    type = "label",
    rect = { unit = "px", x = W - 130, y = 28, w = 110, h = 14 },
    props = { text = "DETECTING…" },
    style = { font_size = 8, color = C.dim, align = "right" }
})
hdr:element({
    id = "iface",
    type = "interface_button",
    rect = { unit = "px", x = 180, y = 14, w = 64, h = 16 },
    props = { text = "INTERFACE" },
    style = { bg = "#333333", text = "#888888", font_size = 7 }
})

-- Left column layout constants
local col_l = 14
local col_r = 210

-- Pressure panel
local pp = ui:element({
    id = "pp",
    type = "panel",
    rect = { unit = "px", x = col_l, y = 52, w = 186, h = 60 },
    style = { bg = C.panel }
})
pp:element({
    id = "p_title",
    type = "label",
    rect = { unit = "px", x = 8, y = 4, w = 80, h = 14 },
    props = { text = "PRESSURE" },
    style = { font_size = 9, color = C.dim, align = "left" }
})
pp:element({
    id = "p_temp",
    type = "label",
    rect = { unit = "px", x = 100, y = 4, w = 80, h = 14 },
    props = { text = "" },
    style = { font_size = 9, color = C.dim, align = "right" }
})
pp:element({
    id = "p_val",
    type = "label",
    rect = { unit = "px", x = 8, y = 20, w = 170, h = 24 },
    props = { text = "-- kPa" },
    style = { font_size = 20, color = C.text, align = "left" }
})
pp:element({
    id = "p_bar",
    type = "progress",
    rect = { unit = "px", x = 8, y = 48, w = 170, h = 6 },
    props = { value = 0, min = 0, max = 110 },
    style = {
        bg = C.muted,
        fill = C.green,
        color_stops = {
            { 0,    C.purple },
            { 0.01, C.purple },
            { 0.05, C.yellow },
            { 0.82, C.green },
        }
    }
})

-- Door indicators (side by side)
local dy = 120
local dw = 90

local dp_i = ui:element({
    id = "dp_i",
    type = "panel",
    rect = { unit = "px", x = col_l, y = dy, w = dw, h = 46 },
    style = { bg = C.panel }
})
dp_i:element({
    id = "lbl",
    type = "label",
    rect = { unit = "px", x = 0, y = 4, w = dw, h = 14 },
    props = { text = "INNER" },
    style = { font_size = 9, color = C.dim, align = "center" }
})
dp_i:element({
    id = "st",
    type = "label",
    rect = { unit = "px", x = 0, y = 20, w = dw, h = 18 },
    props = { text = "CLOSED" },
    style = { font_size = 13, color = C.text, align = "center" }
})

local dp_o = ui:element({
    id = "dp_o",
    type = "panel",
    rect = { unit = "px", x = col_l + dw + 6, y = dy, w = dw, h = 46 },
    style = { bg = C.panel }
})
dp_o:element({
    id = "lbl",
    type = "label",
    rect = { unit = "px", x = 0, y = 4, w = dw, h = 14 },
    props = { text = "OUTER" },
    style = { font_size = 9, color = C.dim, align = "center" }
})
dp_o:element({
    id = "st",
    type = "label",
    rect = { unit = "px", x = 0, y = 20, w = dw, h = 18 },
    props = { text = "CLOSED" },
    style = { font_size = 13, color = C.text, align = "center" }
})

-- Right column: action buttons
local btn_w = W - col_r - 14
local btn_h = 36
local btn_gap = 6

ui:element({
    id = "btn_i",
    type = "button",
    rect = { unit = "px", x = col_r, y = 52, w = btn_w, h = btn_h },
    props = { text = "PRESSURIZE & OPEN" },
    style = { bg = C.accent, text = "#FFFFFF", font_size = 11 },
    on_click = on_inner
})
ui:element({
    id = "btn_o",
    type = "button",
    rect = { unit = "px", x = col_r, y = 52 + btn_h + btn_gap, w = btn_w, h = btn_h },
    props = { text = "DEPRESSURIZE & OPEN" },
    style = { bg = C.accent, text = "#FFFFFF", font_size = 11 },
    on_click = on_outer
})
ui:element({
    id = "btn_s",
    type = "button",
    rect = { unit = "px", x = col_r, y = 52 + (btn_h + btn_gap) * 2, w = btn_w, h = btn_h },
    props = { text = "SEAL AIRLOCK" },
    style = { bg = C.yellow, text = "#000000", font_size = 11 },
    on_click = on_seal
})
ui:element({
    id = "btn_c",
    type = "button",
    rect = { unit = "px", x = col_r, y = 52 + (btn_h + btn_gap) * 3, w = btn_w, h = btn_h },
    props = { text = "CANCEL CYCLE", visible = "false" },
    style = { bg = C.red, text = "#FFFFFF", font_size = 11 },
    on_click = on_cancel
})

-- Cycle progress bar (hidden when idle)
ui:element({
    id = "cyc_bar",
    type = "progress",
    rect = { unit = "px", x = col_l, y = H - 44, w = W - col_l * 2, h = 6 },
    props = { value = 0, min = 0, max = TIMEOUT_SEC, visible = "false" },
    style = { bg = C.muted, fill = C.yellow }
})

-- Status line
ui:element({
    id = "status",
    type = "label",
    rect = { unit = "px", x = col_l, y = H - 34, w = W - col_l * 2, h = 16 },
    props = { text = "Ready" },
    style = { font_size = 10, color = C.dim, align = "left" }
})

-- Warning line (hidden when no warning)
ui:element({
    id = "warn",
    type = "label",
    rect = { unit = "px", x = col_l, y = H - 18, w = W - col_l * 2, h = 16 },
    props = { text = "", visible = "false" },
    style = { font_size = 10, color = C.red, align = "left" }
})

ui:commit()

-- ==================== ELEMENT HANDLES (for tick updates) ====================

local h = {
    state_dot = ui:get("hdr/state_dot"),
    state_lbl = ui:get("hdr/state_lbl"),
    vent_mode = ui:get("hdr/vent_mode"),
    p_val     = ui:get("pp/p_val"),
    p_temp    = ui:get("pp/p_temp"),
    p_bar     = ui:get("pp/p_bar"),
    dp_i      = ui:get("dp_i"),
    di_st     = ui:get("dp_i/st"),
    di_lbl    = ui:get("dp_i/lbl"),
    dp_o      = ui:get("dp_o"),
    do_st     = ui:get("dp_o/st"),
    do_lbl    = ui:get("dp_o/lbl"),
    btn_i     = ui:get("btn_i"),
    btn_o     = ui:get("btn_o"),
    btn_c     = ui:get("btn_c"),
    cyc_bar   = ui:get("cyc_bar"),
    status    = ui:get("status"),
    warn      = ui:get("warn"),
}

-- ==================== TICK UPDATE ====================

local function get_state_label()
    if state == S_SEALING then return "SEALING" end
    if state == S_DEPRESS then return "DEPRESSURIZING" end
    if state == S_PRESS then return "PRESSURIZING" end
    return "IDLE"
end

local function get_state_color()
    if state == S_SEALING then return C.accent end
    if state == S_DEPRESS or state == S_PRESS then return C.yellow end
    return C.green
end

local function get_pressure_color(p)
    if p == nil then return C.dim end
    if p < VACUUM_KPA then return C.purple end
    if p >= PRESSURED_KPA then return C.green end
    return C.yellow
end

local function update_ui(pressure, temperature)
    local cycling = state ~= S_IDLE
    local p_color = get_pressure_color(pressure)
    local s_color = get_state_color()
    local i_open  = door_open(INNER_SLOT)
    local o_open  = door_open(OUTER_SLOT)

    -- Header state indicator
    h.state_dot:set_style({ bg = s_color })
    h.state_lbl:set_props({ text = get_state_label() })
    h.state_lbl:set_style({ color = s_color })
    h.vent_mode:set_props({ text = dual_vent and "DUAL VENT" or "SINGLE VENT" })

    -- Pressure readout
    h.p_val:set_props({ text = fmt_kpa(pressure) })
    h.p_val:set_style({ color = p_color })
    h.p_temp:set_props({ text = fmt_temp(temperature) })
    h.p_bar:set_props({ value = pressure or 0 })

    -- Door indicators
    h.dp_i:set_style({ bg = i_open and C.green or C.panel })
    h.di_st:set_props({ text = i_open and "OPEN" or "CLOSED" })
    h.di_st:set_style({ color = i_open and "#000000" or C.text })
    h.di_lbl:set_style({ color = i_open and "#000000" or C.dim })

    h.dp_o:set_style({ bg = o_open and C.purple or C.panel })
    h.do_st:set_props({ text = o_open and "OPEN" or "CLOSED" })
    h.do_st:set_style({ color = o_open and "#FFFFFF" or C.text })
    h.do_lbl:set_style({ color = o_open and "#FFFFFF" or C.dim })

    -- Button labels: only update when idle (during a cycle the labels stay fixed)
    if not cycling then
        local at_pressure = pressure ~= nil and pressure >= PRESSURED_KPA
        local at_vacuum   = pressure ~= nil and pressure < VACUUM_KPA
        h.btn_i:set_props({ text = at_pressure and "OPEN INNER" or "PRESSURIZE & OPEN" })
        h.btn_i:set_style({ bg = at_pressure and C.green or C.accent })
        h.btn_o:set_props({ text = at_vacuum and "OPEN OUTER" or "DEPRESSURIZE & OPEN" })
        h.btn_o:set_style({ bg = at_vacuum and C.purple or C.accent })
    end

    -- Cancel button: visible whenever a cycle is active (including sealing)
    h.btn_c:set_props({ visible = cycling and "true" or "false" })

    -- Cycle progress bar: sealing phase uses SEAL_TIMEOUT, pump phases use TIMEOUT_SEC
    if state == S_SEALING then
        local elapsed = now() - cycle_start
        h.cyc_bar:set_props({
            value = math.min(elapsed, SEAL_TIMEOUT),
            min = 0,
            max = SEAL_TIMEOUT,
            visible = "true"
        })
        h.cyc_bar:set_style({ fill = C.accent })
    elseif cycling then
        local elapsed = now() - cycle_start
        h.cyc_bar:set_props({
            value = math.min(elapsed, TIMEOUT_SEC),
            min = 0,
            max = TIMEOUT_SEC,
            visible = "true"
        })
        h.cyc_bar:set_style({ fill = C.yellow })
    else
        h.cyc_bar:set_props({ visible = "false" })
    end

    -- Status text
    h.status:set_props({ text = status_text })

    -- Warning text (auto-clear after WARN_DURATION)
    if warn_text ~= "" then
        if now() - warn_time > WARN_DURATION then
            warn_text = ""
            h.warn:set_props({ text = "", visible = "false" })
        else
            h.warn:set_props({ text = warn_text, visible = "true" })
        end
    end

    ui:commit()
end

-- ==================== MAIN LOOP ====================

while true do
    -- Auto-detect vent configuration each tick (handles hot-plug)
    dual_vent         = detect_dual_vent()

    -- Read sensors
    local pressure    = read_pressure()
    local temperature = read_temp()

    -- Run cycle state machine
    if state ~= S_IDLE then
        update_cycle(pressure)
    end

    -- Safety interlock: never allow both doors open simultaneously
    if door_open(INNER_SLOT) and door_open(OUTER_SLOT) then
        set_door(OUTER_SLOT, false)
        warn("SAFETY: Both doors were open!")
    end

    -- Update display
    update_ui(pressure, temperature)

    yield()
end
