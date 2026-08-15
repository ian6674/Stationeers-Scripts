-- NetSensorDashboard.lua
-- ScriptedScreens example: Station-Wide Sensor Dashboard via Pub/Sub
--
-- This console subscribes to sensor topics published by Lua chips across the
-- data network and renders a live multi-zone monitoring dashboard.
--
-- COMPANION CHIP SCRIPT (run on separate Lua chips, one per zone):
-- ─────────────────────────────────────────────────────────────────
--   local LT = ic.enums.LogicType
--   local ZONE = "HAB-1"            -- change per chip
--   while true do
--       local tempC = util.temp(ic.read(0, LT.Temperature), "K", "C")
--       local pres = ic.read(0, LT.Pressure)
--       ic.net.publish("sensor/" .. ZONE, {
--           zone = ZONE, temp = tempC, pres = pres, time = os.clock()
--       }, { retain = true, ttl = 30 })
--       ic.sleep(2)
--   end
-- ─────────────────────────────────────────────────────────────────
--
-- Without companion chips the dashboard runs a built-in simulation so the
-- UI is immediately visible when loaded on any console.

local ui = ss.ui.surface("main")
ss.ui.activate("main")

local size = ui:size()
local W, H = 480, 272
if size then W, H = size.w or W, size.h or H end

-- ── Theme ──────────────────────────────────────────────────────────────
local C = {
    bg     = "#080C18",
    panel  = "#111827",
    header = "#1E293B",
    dim    = "#475569",
    muted  = "#64748B",
    text   = "#E2E8F0",
    green  = "#22C55E",
    yellow = "#EAB308",
    orange = "#F97316",
    red    = "#EF4444",
    cyan   = "#06B6D4",
    blue   = "#3B82F6",
    purple = "#8B5CF6",
}

-- ── State ──────────────────────────────────────────────────────────────
local zones = {}     -- zone_name -> { temp, pres, time, stale }
local zoneOrder = {} -- ordered list of zone names for stable layout
local zoneSet = {}   -- quick lookup for dedup
local alertLog = {}  -- last 6 alert messages
local MAX_ALERTS = 6
local myId = ic.net.id()
local tickCount = 0
local simMode = true -- true until a real message arrives

-- ── Helpers ────────────────────────────────────────────────────────────
local function fmt(v, d)
    if v == nil then return "--" end
    return string.format("%." .. (d or 1) .. "f", v)
end

local function temp_color(t)
    if t == nil then return C.muted end
    if t >= 15 and t <= 30 then return C.green end
    if t >= 5 and t <= 40 then return C.yellow end
    return C.red
end

local function pres_color(p)
    if p == nil then return C.muted end
    if p >= 90 and p <= 110 then return C.green end
    if p >= 70 and p <= 130 then return C.yellow end
    return C.red
end

local function add_alert(msg)
    table.insert(alertLog, msg)
    while #alertLog > MAX_ALERTS do table.remove(alertLog, 1) end
end

local function register_zone(name)
    if not zoneSet[name] then
        zoneSet[name] = true
        table.insert(zoneOrder, name)
    end
end

-- ── Pub/Sub handler ────────────────────────────────────────────────────
function on_sensor(topic, payload, fromId, fromName, retained)
    if type(payload) ~= "table" then return end

    -- Real data arrived - disable simulation
    if simMode then
        simMode = false
        zones = {}
        zoneOrder = {}
        zoneSet = {}
        add_alert("LIVE: receiving real sensor data")
    end

    local zone = payload.zone or topic:match("sensor/(.+)") or "UNKNOWN"
    register_zone(zone)

    local prev = zones[zone]
    zones[zone] = {
        temp  = payload.temp,
        pres  = payload.pres,
        time  = os.clock(),
        stale = false,
    }

    -- Check for threshold crossings
    if payload.temp and payload.temp > 40 then
        add_alert(zone .. ": HIGH TEMP " .. fmt(payload.temp) .. " C")
    elseif payload.temp and payload.temp < 5 then
        add_alert(zone .. ": LOW TEMP " .. fmt(payload.temp) .. " C")
    end
    if payload.pres and payload.pres < 70 then
        add_alert(zone .. ": LOW PRESSURE " .. fmt(payload.pres) .. " kPa")
    elseif payload.pres and payload.pres > 130 then
        add_alert(zone .. ": HIGH PRESSURE " .. fmt(payload.pres) .. " kPa")
    end

    render()
end

ic.net.subscribe("sensor/*", "on_sensor")

-- ── Simulation ─────────────────────────────────────────────────────────
local simZones = { "HAB-1", "HAB-2", "AIRLOCK", "GREENHOUSE", "ENGINEERING" }
for _, z in ipairs(simZones) do register_zone(z) end

local function sim_tick()
    for _, z in ipairs(simZones) do
        local d = zones[z] or { temp = 21, pres = 101 }
        local t = (d.temp or 21) + (math.random() - 0.5) * 0.6
        local p = (d.pres or 101) + (math.random() - 0.5) * 0.4
        -- Airlock is more volatile
        if z == "AIRLOCK" then
            t = t + (math.random() - 0.5) * 2
            p = p + (math.random() - 0.5) * 3
        end
        zones[z] = {
            temp  = math.max(-10, math.min(60, t)),
            pres  = math.max(0, math.min(200, p)),
            time  = os.clock(),
            stale = false,
        }
    end
end

sim_tick() -- seed initial values

-- ── Render ─────────────────────────────────────────────────────────────
function render()
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
        rect = { unit = "px", x = 0, y = 0, w = W, h = 38 },
        style = { bg = C.header }
    })
    hdr:element({
        id = "title",
        type = "label",
        rect = { unit = "px", x = 12, y = 8, w = 200, h = 22 },
        props = { text = "SENSOR NETWORK" },
        style = { font_size = 15, color = C.cyan, align = "left" }
    })
    local modeText = simMode and "SIMULATED" or "LIVE"
    local modeColor = simMode and C.yellow or C.green
    hdr:element({
        id = "mode",
        type = "label",
        rect = { unit = "px", x = W - 120, y = 10, w = 110, h = 18 },
        props = { text = modeText },
        style = { font_size = 11, color = modeColor, align = "right" }
    })

    -- Column headers
    local colY = 42
    local cols = {
        { x = 12,  w = 100, text = "ZONE" },
        { x = 118, w = 70,  text = "TEMP" },
        { x = 194, w = 70,  text = "PRES" },
        { x = 270, w = 50,  text = "STATUS" },
    }
    for ci, col in ipairs(cols) do
        ui:element({
            id = "col_" .. ci,
            type = "label",
            rect = { unit = "px", x = col.x, y = colY, w = col.w, h = 14 },
            props = { text = col.text },
            style = { font_size = 9, color = C.dim, align = "left" }
        })
    end

    -- Zone rows
    local rowY = 58
    local rowH = 24
    local maxRows = math.floor((H - rowY - 72) / rowH)

    for i, zName in ipairs(zoneOrder) do
        if i > maxRows then break end
        local d = zones[zName]
        local y = rowY + ((i - 1) * rowH)
        local bgCol = (i % 2 == 0) and "#0F172A" or C.panel

        -- Mark stale (>15 seconds since last update)
        local age = d and (os.clock() - (d.time or 0)) or 999
        local stale = age > 15

        ui:element({
            id = "zr_" .. i,
            type = "panel",
            rect = { unit = "px", x = 4, y = y, w = W - 8, h = rowH - 2 },
            style = { bg = bgCol }
        })

        -- Zone name
        ui:element({
            id = "zn_" .. i,
            type = "label",
            rect = { unit = "px", x = 12, y = y + 3, w = 100, h = 18 },
            props = { text = zName },
            style = { font_size = 11, color = stale and C.dim or C.text, align = "left" }
        })

        if d then
            -- Temperature
            local tc = stale and C.dim or temp_color(d.temp)
            ui:element({
                id = "zt_" .. i,
                type = "label",
                rect = { unit = "px", x = 118, y = y + 3, w = 70, h = 18 },
                props = { text = fmt(d.temp) .. " C" },
                style = { font_size = 12, color = tc, align = "left" }
            })

            -- Temperature mini-bar (0-60 C range)
            local tPct = math.max(0, math.min(100, ((d.temp or 0) + 10) / 70 * 100))
            ui:element({
                id = "ztb_" .. i,
                type = "progress",
                rect = { unit = "px", x = 118, y = y + rowH - 5, w = 60, h = 3 },
                props = { value = tostring(tPct), max = "100" },
                style = { bg = "#1A1A2E", fill = tc }
            })

            -- Pressure
            local pc = stale and C.dim or pres_color(d.pres)
            ui:element({
                id = "zp_" .. i,
                type = "label",
                rect = { unit = "px", x = 194, y = y + 3, w = 70, h = 18 },
                props = { text = fmt(d.pres) .. " kPa" },
                style = { font_size = 12, color = pc, align = "left" }
            })

            -- Pressure mini-bar (0-200 kPa range)
            local pPct = math.max(0, math.min(100, (d.pres or 0) / 200 * 100))
            ui:element({
                id = "zpb_" .. i,
                type = "progress",
                rect = { unit = "px", x = 194, y = y + rowH - 5, w = 60, h = 3 },
                props = { value = tostring(pPct), max = "100" },
                style = { bg = "#1A1A2E", fill = pc }
            })

            -- Status badge
            local status, sc
            if stale then
                status, sc = "STALE", C.dim
            elseif temp_color(d.temp) == C.red or pres_color(d.pres) == C.red then
                status, sc = "ALERT", C.red
            elseif temp_color(d.temp) == C.yellow or pres_color(d.pres) == C.yellow then
                status, sc = "WARN", C.yellow
            else
                status, sc = "OK", C.green
            end

            -- Status dot
            ui:element({
                id = "zsd_" .. i,
                type = "panel",
                rect = { unit = "px", x = 270, y = y + 8, w = 6, h = 6 },
                style = { bg = sc }
            })
            ui:element({
                id = "zst_" .. i,
                type = "label",
                rect = { unit = "px", x = 280, y = y + 3, w = 46, h = 18 },
                props = { text = status },
                style = { font_size = 10, color = sc, align = "left" }
            })
        else
            ui:element({
                id = "zna_" .. i,
                type = "label",
                rect = { unit = "px", x = 118, y = y + 3, w = 120, h = 18 },
                props = { text = "awaiting data…" },
                style = { font_size = 10, color = C.dim, align = "left" }
            })
        end
    end

    -- ── Alert log (right side / bottom) ────────────────────────────────
    local alertX = 334
    local alertY = 42
    local alertW = W - alertX - 8

    ui:element({
        id = "al_bg",
        type = "panel",
        rect = { unit = "px", x = alertX, y = alertY, w = alertW, h = H - alertY - 28 },
        style = { bg = "#0D1117" }
    })
    ui:element({
        id = "al_hdr",
        type = "label",
        rect = { unit = "px", x = alertX + 6, y = alertY + 4, w = alertW - 12, h = 14 },
        props = { text = "ALERTS" },
        style = { font_size = 9, color = C.orange, align = "left" }
    })

    for ai = 1, #alertLog do
        local ay = alertY + 20 + ((ai - 1) * 14)
        ui:element({
            id = "al_" .. ai,
            type = "label",
            rect = { unit = "px", x = alertX + 6, y = ay, w = alertW - 12, h = 13 },
            props = { text = alertLog[ai] },
            style = { font_size = 8, color = C.orange, align = "left" }
        })
    end

    -- ── Footer ─────────────────────────────────────────────────────────
    local zoneCount = #zoneOrder
    local okCount = 0
    for _, zn in ipairs(zoneOrder) do
        local d = zones[zn]
        if d and not d.stale and temp_color(d.temp) == C.green and pres_color(d.pres) == C.green then
            okCount = okCount + 1
        end
    end

    ui:element({
        id = "ft_zones",
        type = "label",
        rect = { unit = "px", x = 12, y = H - 22, w = 160, h = 14 },
        props = { text = zoneCount .. " zones | " .. okCount .. " nominal" },
        style = { font_size = 10, color = C.dim, align = "left" }
    })
    ui:element({
        id = "ft_id",
        type = "label",
        rect = { unit = "px", x = W - 120, y = H - 22, w = 110, h = 14 },
        props = { text = "ID: " .. tostring(myId) },
        style = { font_size = 9, color = C.dim, align = "right" }
    })

    ui:commit()
end

-- ── Initial render ─────────────────────────────────────────────────────
print("[SensorDashboard] Started, subscribing to sensor/*")
render()

-- ── Main loop ──────────────────────────────────────────────────────────
while true do
    tickCount = tickCount + 1

    -- Run simulation if no real data
    if simMode and tickCount % 10 == 0 then
        sim_tick()
        render()
    end

    -- Periodic stale-check re-render (every ~5 seconds)
    if not simMode and tickCount % 50 == 0 then
        render()
    end

    ic.yield()
end
