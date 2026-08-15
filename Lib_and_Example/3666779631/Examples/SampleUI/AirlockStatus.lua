-- Airlock Status Display
-- ScriptedScreens command center display for airlock monitoring
-- Shows status of multiple airlocks with pressure and cycle state

local ui = ss.ui.surface("main")
ss.ui.activate("main")

local W, H = 480, 272

local size = ui:size()
if size then
    W = size.w or W
    H = size.h or H
end

-- Airlock states
local STATE = {
    SEALED = 1,
    CYCLING = 2,
    OPEN_INT = 3,
    OPEN_EXT = 4,
    ERROR = 5,
}

local STATE_NAMES = {
    [STATE.SEALED] = "SEALED",
    [STATE.CYCLING] = "CYCLING",
    [STATE.OPEN_INT] = "OPEN INT",
    [STATE.OPEN_EXT] = "OPEN EXT",
    [STATE.ERROR] = "ERROR",
}

local STATE_COLORS = {
    [STATE.SEALED] = "#00E676",
    [STATE.CYCLING] = "#FFEB3B",
    [STATE.OPEN_INT] = "#29B6F6",
    [STATE.OPEN_EXT] = "#F97316",
    [STATE.ERROR] = "#FF5252",
}

-- Simulated airlock data
local airlocks = {
    { id = "AL-01", name = "MAIN",  state = STATE.SEALED,   pressure = 101.2, cycleProgress = 0 },
    { id = "AL-02", name = "CARGO", state = STATE.SEALED,   pressure = 100.8, cycleProgress = 0 },
    { id = "AL-03", name = "EVA-A", state = STATE.CYCLING,  pressure = 45.3,  cycleProgress = 65 },
    { id = "AL-04", name = "EVA-B", state = STATE.OPEN_EXT, pressure = 0.0,   cycleProgress = 100 },
    { id = "AL-05", name = "DOCK",  state = STATE.SEALED,   pressure = 101.0, cycleProgress = 0 },
}

local function fmt(v)
    if v == nil then return "--" end
    return string.format("%.1f", v)
end

local function render()
    ui:clear()

    -- Background
    ui:element({
        id = "bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = H },
        style = { bg = "#0A0E1A" }
    })

    -- Header
    local header = ui:element({
        id = "hdr",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = 40 },
        style = { bg = "#1E293B" }
    })

    header:element({
        id = "title",
        type = "label",
        rect = { unit = "px", x = 16, y = 10, w = 180, h = 20 },
        props = { text = "AIRLOCK STATUS" },
        style = { font_size = 16, color = "#E2E8F0", align = "left" }
    })

    -- Count summary
    local sealedCount = 0
    local activeCount = 0
    for _, al in ipairs(airlocks) do
        if al.state == STATE.SEALED then
            sealedCount = sealedCount + 1
        elseif al.state ~= STATE.ERROR then
            activeCount = activeCount + 1
        end
    end

    header:element({
        id = "summary",
        type = "label",
        rect = { unit = "px", x = W - 160, y = 10, w = 144, h = 20 },
        props = { text = sealedCount .. " SEALED | " .. activeCount .. " ACTIVE" },
        style = { font_size = 11, color = "#94A3B8", align = "right" }
    })

    -- Column headers
    local headerY = 48
    local colId = 16
    local colName = 70
    local colState = 140
    local colPres = 240
    local colCycle = 320

    ui:element({
        id = "col_id",
        type = "label",
        rect = { unit = "px", x = colId, y = headerY, w = 50, h = 16 },
        props = { text = "ID" },
        style = { font_size = 10, color = "#64748B", align = "left" }
    })

    ui:element({
        id = "col_name",
        type = "label",
        rect = { unit = "px", x = colName, y = headerY, w = 60, h = 16 },
        props = { text = "NAME" },
        style = { font_size = 10, color = "#64748B", align = "left" }
    })

    ui:element({
        id = "col_state",
        type = "label",
        rect = { unit = "px", x = colState, y = headerY, w = 80, h = 16 },
        props = { text = "STATUS" },
        style = { font_size = 10, color = "#64748B", align = "left" }
    })

    ui:element({
        id = "col_pres",
        type = "label",
        rect = { unit = "px", x = colPres, y = headerY, w = 70, h = 16 },
        props = { text = "PRESSURE" },
        style = { font_size = 10, color = "#64748B", align = "left" }
    })

    ui:element({
        id = "col_cycle",
        type = "label",
        rect = { unit = "px", x = colCycle, y = headerY, w = 80, h = 16 },
        props = { text = "CYCLE" },
        style = { font_size = 10, color = "#64748B", align = "left" }
    })

    -- Airlock rows
    local rowH = 36
    local startY = headerY + 20

    for i, al in ipairs(airlocks) do
        local y = startY + ((i - 1) * rowH)
        local stateColor = STATE_COLORS[al.state] or "#B0BEC5"

        -- Row background (alternating)
        local rowBg = (i % 2 == 0) and "#0F172A" or "#111827"
        ui:element({
            id = "row_bg_" .. i,
            type = "panel",
            rect = { unit = "px", x = 8, y = y, w = W - 16, h = rowH - 4 },
            style = { bg = rowBg }
        })

        -- Status indicator dot
        ui:element({
            id = "dot_" .. i,
            type = "panel",
            rect = { unit = "px", x = colId, y = y + 10, w = 10, h = 10 },
            style = { bg = stateColor }
        })

        -- ID
        ui:element({
            id = "id_" .. i,
            type = "label",
            rect = { unit = "px", x = colId + 16, y = y + 6, w = 50, h = 20 },
            props = { text = al.id },
            style = { font_size = 12, color = "#E2E8F0", align = "left" }
        })

        -- Name
        ui:element({
            id = "name_" .. i,
            type = "label",
            rect = { unit = "px", x = colName, y = y + 6, w = 60, h = 20 },
            props = { text = al.name },
            style = { font_size = 12, color = "#94A3B8", align = "left" }
        })

        -- State
        ui:element({
            id = "state_" .. i,
            type = "label",
            rect = { unit = "px", x = colState, y = y + 6, w = 80, h = 20 },
            props = { text = STATE_NAMES[al.state] },
            style = { font_size = 12, color = stateColor, align = "left" }
        })

        -- Pressure
        ui:element({
            id = "pres_" .. i,
            type = "label",
            rect = { unit = "px", x = colPres, y = y + 6, w = 70, h = 20 },
            props = { text = fmt(al.pressure) .. " kPa" },
            style = { font_size = 12, color = "#E2E8F0", align = "left" }
        })

        -- Cycle progress bar (only if cycling)
        if al.state == STATE.CYCLING then
            ui:element({
                id = "cycle_bar_" .. i,
                type = "progress",
                rect = { unit = "px", x = colCycle, y = y + 8, w = 80, h = 14 },
                props = { value = tostring(al.cycleProgress), max = "100" },
                style = { bg = "#1E293B", fill = "#FFEB3B" }
            })

            ui:element({
                id = "cycle_pct_" .. i,
                type = "label",
                rect = { unit = "px", x = colCycle + 84, y = y + 6, w = 40, h = 20 },
                props = { text = al.cycleProgress .. "%" },
                style = { font_size = 11, color = "#FFEB3B", align = "left" }
            })
        else
            ui:element({
                id = "cycle_dash_" .. i,
                type = "label",
                rect = { unit = "px", x = colCycle, y = y + 6, w = 80, h = 20 },
                props = { text = "-" },
                style = { font_size = 12, color = "#475569", align = "left" }
            })
        end
    end

    -- Footer
    ui:element({
        id = "footer",
        type = "label",
        rect = { unit = "px", x = 16, y = H - 22, w = 200, h = 14 },
        props = { text = "AUTO-REFRESH ENABLED" },
        style = { font_size = 10, color = "#475569", align = "left" }
    })

    ui:commit()
end

render()

-- Main loop - simulate airlock activity
local tick = 0
while true do
    tick = tick + 1

    for _, al in ipairs(airlocks) do
        if al.state == STATE.CYCLING then
            -- Progress the cycle
            al.cycleProgress = al.cycleProgress + math.random(2, 5)

            -- Update pressure based on direction
            if al.pressure > 50 then
                -- Depressurizing
                al.pressure = math.max(0, al.pressure - 3)
            else
                -- Pressurizing
                al.pressure = math.min(101.3, al.pressure + 3)
            end

            -- Complete cycle
            if al.cycleProgress >= 100 then
                al.cycleProgress = 100
                if al.pressure < 10 then
                    al.state = STATE.OPEN_EXT
                    al.pressure = 0
                else
                    al.state = STATE.OPEN_INT
                    al.pressure = 101.3
                end
            end
        end
    end

    -- Random state changes for demo
    if tick % 50 == 0 then
        local idx = math.random(1, #airlocks)
        local al = airlocks[idx]
        if al.state == STATE.SEALED then
            al.state = STATE.CYCLING
            al.cycleProgress = 0
        elseif al.state == STATE.OPEN_INT or al.state == STATE.OPEN_EXT then
            al.state = STATE.CYCLING
            al.cycleProgress = 0
        end
    end

    if tick % 5 == 0 then
        render()
    end

    ic.yield()
end
