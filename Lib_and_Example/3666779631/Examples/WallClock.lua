-- WallClock.lua
-- ScriptedScreens example: Beautiful 12-hour analog+digital wall clock
-- Displays a large digital clock with AM/PM, date line, and a pixel-drawn
-- analog clock face using canvas_line and canvas_circle.

local ui = ss.ui.surface("main")
ss.ui.activate("main")

local size = ui:size()
local W, H = 480, 272
if size then W, H = size.w or W, size.h or H end

-- ── Theme (hex for UI elements) ──────────────────────────────────────
local C            = {
    bg     = "#0B0E17",
    face   = "#0F172A",
    digit  = "#E2E8F0",
    ampm   = "#8B5CF6",
    date   = "#64748B",
    accent = "#3B82F6",
    dim    = "#475569",
    label  = "#94A3B8",
}

-- ── Canvas color palette (hex strings for drawing primitives) ────────
local CC           = {
    bg       = "#0F172A", -- dark face background
    ring     = "#1E293B", -- outer ring
    tick     = "#334155", -- minor tick marks
    tick_maj = "#94A3B8", -- major tick marks (12/3/6/9)
    hand_h   = "#E2E8F0", -- hour hand
    hand_m   = "#94A3B8", -- minute hand
    hand_s   = "#EF4444", -- second hand (red)
    center   = "#3B82F6", -- center dot (accent blue)
    num      = "#64748B", -- hour number dots
}

-- ── Canvas constants ─────────────────────────────────────────────────
local CLOCK_ID     = "clock_canvas"
local CLOCK_SIZE   = 180                  -- canvas pixel dimensions (square)
local CLOCK_CX     = CLOCK_SIZE / 2       -- center X in canvas coords
local CLOCK_CY     = CLOCK_SIZE / 2       -- center Y in canvas coords
local CLOCK_R      = (CLOCK_SIZE / 2) - 4 -- usable radius with margin

-- ── Shared time state (updated every frame, labels throttled) ────────
local lastLabelSec = -1 -- tracks last whole-second we updated labels

-- ── Draw the analog clock face onto the canvas ───────────────────────
-- Called every frame via on_frame for smooth sweeping second hand.
-- Also updates digital labels once per second.
-- Multiplayer: begin/end wraps ticks + hands into one op batch per frame.
local function draw_clock_face()
    -- Compute time with sub-second precision for smooth animation
    local tod = util.time_of_day()
    local frac = tod - math.floor(tod)
    local totalSecF = frac * 24 * 60 * 60 -- fractional total seconds
    local hour24 = math.floor(totalSecF / 3600) % 24
    local minute = math.floor(totalSecF / 60) % 60
    local secondF = totalSecF % 60 -- fractional seconds (smooth)
    local second = math.floor(secondF)

    ui:canvas_begin_update(CLOCK_ID)
    -- Clear the canvas to the face background color
    ui:canvas_clear(CLOCK_ID, CC.bg)

    -- Outer ring (two concentric circles for a subtle bezel)
    ui:canvas_circle(CLOCK_ID, CLOCK_CX, CLOCK_CY, CLOCK_R, CC.ring, 2)
    ui:canvas_circle(CLOCK_ID, CLOCK_CX, CLOCK_CY, CLOCK_R - 3, CC.tick, 1)

    -- Hour tick marks (12 positions)
    for h = 0, 11 do
        local angle = (h / 12) * 2 * math.pi - math.pi / 2
        local isMajor = (h % 3 == 0)
        local innerR = isMajor and (CLOCK_R - 16) or (CLOCK_R - 10)
        local outerR = CLOCK_R - 5
        local thickness = isMajor and 2 or 1
        local col = isMajor and CC.tick_maj or CC.tick

        local x0 = math.floor(CLOCK_CX + math.cos(angle) * innerR)
        local y0 = math.floor(CLOCK_CY - math.sin(angle) * innerR)
        local x1 = math.floor(CLOCK_CX + math.cos(angle) * outerR)
        local y1 = math.floor(CLOCK_CY - math.sin(angle) * outerR)
        ui:canvas_line(CLOCK_ID, x0, y0, x1, y1, col, thickness)
    end

    -- Small hour-number dots at 1-11 (skip 12/3/6/9 since ticks are bold)
    for h = 1, 11 do
        if h % 3 ~= 0 then
            local angle = (h / 12) * 2 * math.pi - math.pi / 2
            local dotR = CLOCK_R - 22
            local dx = math.floor(CLOCK_CX + math.cos(angle) * dotR)
            local dy = math.floor(CLOCK_CY - math.sin(angle) * dotR)
            ui:canvas_circle(CLOCK_ID, dx, dy, 1, CC.num, 1)
        end
    end

    -- ── Clock hands ──────────────────────────────────────────────────

    -- Hour hand: thick, short
    local hourAngle = ((hour24 % 12) + minute / 60) / 12 * 2 * math.pi - math.pi / 2
    local hhLen = CLOCK_R * 0.5
    local hx1 = math.floor(CLOCK_CX + math.cos(hourAngle) * hhLen)
    local hy1 = math.floor(CLOCK_CY - math.sin(hourAngle) * hhLen)
    ui:canvas_line(CLOCK_ID, CLOCK_CX, CLOCK_CY, hx1, hy1, CC.hand_h, 3)

    -- Minute hand: medium, longer (uses fractional seconds for smooth creep)
    local minAngle = (minute + secondF / 60) / 60 * 2 * math.pi - math.pi / 2
    local mhLen = CLOCK_R * 0.72
    local mx1 = math.floor(CLOCK_CX + math.cos(minAngle) * mhLen)
    local my1 = math.floor(CLOCK_CY - math.sin(minAngle) * mhLen)
    ui:canvas_line(CLOCK_ID, CLOCK_CX, CLOCK_CY, mx1, my1, CC.hand_m, 2)

    -- Second hand: thin, longest, sweeping (fractional seconds)
    local secAngle = secondF / 60 * 2 * math.pi - math.pi / 2
    local shLen = CLOCK_R * 0.82
    local sx1 = math.floor(CLOCK_CX + math.cos(secAngle) * shLen)
    local sy1 = math.floor(CLOCK_CY - math.sin(secAngle) * shLen)
    ui:canvas_line(CLOCK_ID, CLOCK_CX, CLOCK_CY, sx1, sy1, CC.hand_s, 1)
    -- Tail (opposite direction, short)
    local tailLen = CLOCK_R * 0.15
    local tx1 = math.floor(CLOCK_CX - math.cos(secAngle) * tailLen)
    local ty1 = math.floor(CLOCK_CY + math.sin(secAngle) * tailLen)
    ui:canvas_line(CLOCK_ID, CLOCK_CX, CLOCK_CY, tx1, ty1, CC.hand_s, 1)

    -- Center cap circle
    ui:canvas_circle(CLOCK_ID, CLOCK_CX, CLOCK_CY, 3, CC.center, 3)

    ui:canvas_end_update(CLOCK_ID)
    -- Flush the canvas to the texture
    ui:canvas_apply(CLOCK_ID)

    -- ── Throttled digital label updates (once per whole second) ──────
    local totalSecI = math.floor(totalSecF)
    if totalSecI ~= lastLabelSec then
        lastLabelSec = totalSecI

        local hour12 = hour24 % 12
        if hour12 == 0 then hour12 = 12 end
        local ampm = hour24 >= 12 and "PM" or "AM"

        local h_time = ui:get("digital_time")
        if h_time then h_time:set_props({ text = string.format("%02d:%02d", hour12, minute) }) end

        local h_sec = ui:get("digital_sec")
        if h_sec then h_sec:set_props({ text = string.format(":%02d", second) }) end

        local h_ampm = ui:get("digital_ampm")
        if h_ampm then h_ampm:set_props({ text = ampm }) end

        local h_day = ui:get("day_label")
        if h_day then h_day:set_props({ text = "DAY " .. tostring(util.days_past()) }) end

        local gt = util.game_time()
        local gtH = math.floor(gt / 3600)
        local gtM = math.floor((gt % 3600) / 60)
        local h_elapsed = ui:get("elapsed_label")
        if h_elapsed then h_elapsed:set_props({ text = string.format("ELAPSED %dh %02dm", gtH, gtM) }) end

        local h_v1 = ui:get("info_v_1")
        if h_v1 then h_v1:set_props({ text = util.clock_time("HH:MM:ss") }) end
        local h_v2 = ui:get("info_v_2")
        if h_v2 then h_v2:set_props({ text = util.clock_time("hh:MM:ss A") }) end
        local h_v3 = ui:get("info_v_3")
        if h_v3 then h_v3:set_props({ text = string.format("%.4f", frac) }) end
    end
end

-- ── Build UI layout (runs once at startup) ───────────────────────────
local function build_ui()
    ui:clear()

    -- Background
    ui:element({
        id = "bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = H },
        style = { bg = C.bg }
    })

    -- ── Left side: Digital clock ─────────────────────────────────
    local digX = 24
    local digY = 40

    -- "STATION TIME" label
    ui:element({
        id = "lbl_station",
        type = "label",
        rect = { unit = "px", x = digX, y = digY, w = 200, h = 16 },
        props = { text = "STATION TIME" },
        style = { font_size = 10, color = C.dim, align = "left" }
    })

    -- Large digital time
    ui:element({
        id = "digital_time",
        type = "label",
        rect = { unit = "px", x = digX, y = digY + 20, w = 220, h = 70 },
        props = { text = "--:--" },
        style = { font_size = 56, color = C.digit, align = "left" }
    })

    -- Seconds + AM/PM
    ui:element({
        id = "digital_sec",
        type = "label",
        rect = { unit = "px", x = digX + 190, y = digY + 28, w = 50, h = 30 },
        props = { text = ":--" },
        style = { font_size = 22, color = C.label, align = "left" }
    })
    ui:element({
        id = "digital_ampm",
        type = "label",
        rect = { unit = "px", x = digX + 190, y = digY + 56, w = 50, h = 24 },
        props = { text = "--" },
        style = { font_size = 18, color = C.ampm, align = "left" }
    })

    -- Accent bar
    ui:element({
        id = "accent_bar",
        type = "panel",
        rect = { unit = "px", x = digX, y = digY + 94, w = 220, h = 2 },
        style = { bg = C.accent }
    })

    -- Day counter
    ui:element({
        id = "day_label",
        type = "label",
        rect = { unit = "px", x = digX, y = digY + 102, w = 220, h = 16 },
        props = { text = "DAY --" },
        style = { font_size = 11, color = C.date, align = "left" }
    })

    -- Elapsed time
    ui:element({
        id = "elapsed_label",
        type = "label",
        rect = { unit = "px", x = digX, y = digY + 120, w = 220, h = 14 },
        props = { text = "ELAPSED --" },
        style = { font_size = 9, color = C.dim, align = "left" }
    })

    -- Info rows
    local infoY = digY + 150
    local infoLabels = { "24H", "12H", "FRAC" }
    for i, lbl in ipairs(infoLabels) do
        local iy = infoY + (i - 1) * 18
        ui:element({
            id = "info_l_" .. i,
            type = "label",
            rect = { unit = "px", x = digX, y = iy, w = 40, h = 14 },
            props = { text = lbl },
            style = { font_size = 8, color = C.dim, align = "left" }
        })
        ui:element({
            id = "info_v_" .. i,
            type = "label",
            rect = { unit = "px", x = digX + 44, y = iy, w = 140, h = 14 },
            props = { text = "--" },
            style = { font_size = 9, color = C.label, align = "left" }
        })
    end

    -- ── Right side: Canvas for analog clock ──────────────────────
    local clockX = W - CLOCK_SIZE - 20
    local clockY = math.floor((H - CLOCK_SIZE) / 2)
    ui:element({
        id = CLOCK_ID,
        type = "canvas",
        rect = { unit = "px", x = clockX, y = clockY, w = CLOCK_SIZE, h = CLOCK_SIZE },
        props = { width = tostring(CLOCK_SIZE), height = tostring(CLOCK_SIZE) },
        style = { bg = C.face }
    })

    -- Footer
    ui:element({
        id = "footer",
        type = "label",
        rect = { unit = "px", x = 8, y = H - 16, w = 200, h = 12 },
        props = { text = "Wall Clock | ScriptedScreens" },
        style = { font_size = 8, color = C.dim, align = "left" }
    })

    ui:commit()
end

-- ── Boot ─────────────────────────────────────────────────────────────
-- Build the UI layout once, then hand off to on_frame for all updates.
-- The script finishes execution so the LuaState is free for frame callbacks.
build_ui()
ui:on_frame(draw_clock_face)
