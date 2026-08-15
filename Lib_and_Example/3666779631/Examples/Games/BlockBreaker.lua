-- ORBITAL BREAK - Breakout + power-ups on marked bricks
-- Same loop as SpaceInvaders.lua: on_frame + util.game_time() dt + poll_input + ui:commit().
-- Multiplayer: draw_frame uses canvas_begin_update/canvas_end_update so one paint = one op batch.
-- Bricks with a bright chip in the corner drop a typed pickup when destroyed.

local ui = ss.ui.surface("main")
ss.ui.activate("main")
ui:clear()

local W, H = ui:size().w, ui:size().h
local HUD_H = 50
local CTRL_H = 54
local MARGIN = 8
local CV = "brk_cv"
local CW = W - MARGIN * 2
local CH = H - HUD_H - CTRL_H - MARGIN * 2
local CX0 = MARGIN
local CY0 = HUD_H + MARGIN

local PU_WIDE, PU_SLOW, PU_LIFE, PU_SPLIT = 1, 2, 3, 4
local PU_DROP_SPEED = 98
local PU_SPAWN_CHANCE = 16
local MAX_BALLS = 4

local COL_ROW = {
    { 244, 114, 182 },
    { 251, 191, 36 },
    { 74, 222, 128 },
    { 56, 189, 248 },
    { 167, 139, 250 },
}

local brick_cols = 7
local brick_gap, brick_top = 4, 10
local brick_h = 14
local brick_rows = 5

local bricks = {}
local powerups = {}

local paddle_x = CW / 2
local paddle_w_base = 72
local paddle_w = paddle_w_base
local paddle_h = 10
local paddle_y = CH - 18
local paddle_spd = 260

local balls = {}
local base_spd = 240
local waiting = true
local score, lives, level = 0, 3, 1
local best = 0
local game_over = false

local wide_t, slow_t = 0, 0

local held_left, held_right, held_fire = false, false, false
local last_t = util.game_time()
local warmup = 8

local rng = (7919 + W + H) % 2147483646 + 1
local function rnd(n)
    if n <= 1 then
        return 1
    end
    rng = (rng * 48271) % 2147483647
    return (rng % n) + 1
end

local function px2(x, y, w, h)
    return { unit = "px", x = x, y = y, w = w, h = h }
end

local function brick_w()
    local g = brick_gap
    return math.floor((CW - g * (brick_cols + 1)) / brick_cols)
end

local function build_bricks()
    bricks = {}
    local bw = brick_w()
    local g = brick_gap
    brick_rows = math.min(4 + level, 5)
    for r = 1, brick_rows do
        for c = 1, brick_cols do
            local x = g + (c - 1) * (bw + g)
            local y = brick_top + (r - 1) * (brick_h + g)
            local pu = nil
            if rnd(100) <= PU_SPAWN_CHANCE then
                pu = rnd(4)
            end
            bricks[#bricks + 1] = { x = x, y = y, w = bw, h = brick_h, alive = true, row = r, pu_kind = pu }
        end
    end
end

local function alive_count()
    local n = 0
    for i = 1, #bricks do
        if bricks[i].alive then
            n = n + 1
        end
    end
    return n
end

local function speed_mul()
    return 1 + (level - 1) * 0.1
end

local function spd_scale()
    return (slow_t > 0) and 0.58 or 1
end

local function update_hud()
    local s = ui:get("score_lbl")
    if s then
        s:set_props({
            text = "<b>" .. tostring(score) .. "</b>"
                .. "  <color=#64748B>lvl " .. tostring(level)
                .. " · " .. tostring(lives) .. " lives"
                .. " · best " .. tostring(best) .. "</color>",
        })
    end
end

local function show_overlay(vis, txt)
    local g = ui:get("go_lbl")
    if g then
        g:set_props({
            visible = vis and "true" or "false",
            text = vis and (txt or "") or "",
        })
    end
end

local function reset_balls_wait()
    waiting = true
    balls = {
        { x = paddle_x, y = paddle_y - 7, r = 5, vx = 0, vy = 0 },
    }
end

local function try_serve()
    if game_over or not waiting then
        return
    end
    waiting = false
    local s = base_spd * speed_mul()
    local a = (rnd(70) / 100) * 0.7 + 0.15
    a = a * math.pi
    for i = 1, #balls do
        local b = balls[i]
        b.vx = math.cos(a) * s * (rnd(2) == 1 and -1 or 1)
        b.vy = -math.abs(math.sin(a) * s) - 40
    end
end

local function lose_life()
    lives = lives - 1
    powerups = {}
    if lives <= 0 then
        game_over = true
        if score > best then
            best = score
        end
        show_overlay(true, "<color=#F87171><b>HULL BREACH</b></color>\n<color=#94A3B8>RESTART or Space</color>")
    else
        show_overlay(true, "<color=#FBBF24><b>LOST ORB</b></color>\n<color=#94A3B8>" .. tostring(lives) .. " left · FIRE</color>")
        reset_balls_wait()
    end
    wide_t = 0
    slow_t = 0
    paddle_w = paddle_w_base
    update_hud()
end

local function init_game()
    score, level, lives = 0, 1, 3
    game_over = false
    paddle_x = CW / 2
    paddle_w = paddle_w_base
    wide_t = 0
    slow_t = 0
    powerups = {}
    build_bricks()
    reset_balls_wait()
    show_overlay(true, "<color=#94A3B8><b>FIRE</b> to launch</color>")
    update_hud()
end

local function next_level()
    level = level + 1
    score = score + 50 * level
    powerups = {}
    wide_t = 0
    slow_t = 0
    paddle_w = paddle_w_base
    build_bricks()
    reset_balls_wait()
    show_overlay(true, "<color=#4ADE80><b>SECTOR " .. tostring(level) .. "</b></color>\n<color=#94A3B8>FIRE</color>")
    update_hud()
end

local function spawn_powerup(cx, cy, kind)
    powerups[#powerups + 1] = {
        x = cx - 5,
        y = cy - 5,
        w = 10,
        h = 10,
        vy = PU_DROP_SPEED,
        kind = kind,
    }
end

local function apply_power(kind)
    if kind == PU_WIDE then
        paddle_w = math.min(118, paddle_w_base + 38)
        wide_t = 14
        score = score + 5
    elseif kind == PU_SLOW then
        slow_t = 11
        score = score + 5
    elseif kind == PU_LIFE then
        lives = math.min(9, lives + 1)
        score = score + 25
    elseif kind == PU_SPLIT then
        if not waiting and #balls < MAX_BALLS then
            local src = balls[rnd(#balls)]
            balls[#balls + 1] = {
                x = src.x,
                y = src.y - 2,
                r = 5,
                vx = src.vx + (rnd(28) - 14),
                vy = src.vy - math.abs(src.vy) * 0.35 - 30,
            }
            clamp_ball_speed(balls[#balls])
        else
            score = score + 40
        end
    end
    update_hud()
end

local function circle_rect(cx, cy, r, rx, ry, rw, rh)
    local qx = math.max(rx, math.min(cx, rx + rw))
    local qy = math.max(ry, math.min(cy, ry + rh))
    local dx, dy = cx - qx, cy - qy
    return dx * dx + dy * dy <= r * r
end

local function resolve_brick_ball(b, br)
    local cx, cy, r = b.x, b.y, b.r
    local rx, ry, rw, rh = br.x, br.y, br.w, br.h
    local penL = cx + r - rx
    local penR = rx + rw - (cx - r)
    local penT = cy + r - ry
    local penB = ry + rh - (cy - r)
    local mL, mR = math.abs(penL), math.abs(penR)
    local mT, mB = math.abs(penT), math.abs(penB)
    local minx = math.min(mL, mR)
    local miny = math.min(mT, mB)
    if minx < miny then
        b.vx = -b.vx
        if mL < mR then
            b.x = rx - r - 0.1
        else
            b.x = rx + rw + r + 0.1
        end
    else
        b.vy = -b.vy
        if mT < mB then
            b.y = ry - r - 0.1
        else
            b.y = ry + rh + r + 0.1
        end
    end
end

local function clamp_ball_speed(b)
    local sp = math.sqrt(b.vx * b.vx + b.vy * b.vy)
    local cap = 400 * speed_mul()
    if sp > cap then
        b.vx = b.vx * cap / sp
        b.vy = b.vy * cap / sp
    end
end

local function step(dt)
    if game_over then
        return
    end

    local sc = spd_scale()

    if wide_t > 0 then
        wide_t = wide_t - dt
        if wide_t <= 0 then
            paddle_w = paddle_w_base
        end
    end
    if slow_t > 0 then
        slow_t = slow_t - dt
    end

    if waiting then
        for i = 1, #balls do
            local b = balls[i]
            b.x = paddle_x
            b.y = paddle_y - b.r - 2
        end
    else
        for bi = #balls, 1, -1 do
            local b = balls[bi]
            b.x = b.x + b.vx * dt * sc
            b.y = b.y + b.vy * dt * sc

            if b.x - b.r < 0 then
                b.x = b.r
                b.vx = math.abs(b.vx)
            elseif b.x + b.r > CW then
                b.x = CW - b.r
                b.vx = -math.abs(b.vx)
            end
            if b.y - b.r < 0 then
                b.y = b.r
                b.vy = math.abs(b.vy)
            end

            if b.vy > 0 and b.y + b.r >= paddle_y and b.y + b.r <= paddle_y + paddle_h + b.r then
                if b.x >= paddle_x - paddle_w / 2 - b.r and b.x <= paddle_x + paddle_w / 2 + b.r then
                    b.y = paddle_y - b.r
                    b.vy = -math.abs(b.vy)
                    local e = (b.x - paddle_x) / (paddle_w / 2)
                    b.vx = b.vx + e * 95
                    clamp_ball_speed(b)
                end
            end

            if b.y - b.r > CH + 12 then
                table.remove(balls, bi)
                if #balls == 0 then
                    lose_life()
                    return
                end
            end
        end

        for bi = 1, #balls do
            local b = balls[bi]
            for i = 1, #bricks do
                local br = bricks[i]
                if br.alive and circle_rect(b.x, b.y, b.r, br.x, br.y, br.w, br.h) then
                    br.alive = false
                    score = score + 10 * br.row + level
                    if br.pu_kind ~= nil then
                        spawn_powerup(br.x + br.w / 2, br.y + br.h / 2, br.pu_kind)
                    end
                    resolve_brick_ball(b, br)
                    update_hud()
                    if alive_count() == 0 then
                        next_level()
                        return
                    end
                    break
                end
            end
        end
    end

    local pi = 1
    while pi <= #powerups do
        local p = powerups[pi]
        p.y = p.y + p.vy * dt * sc
        if p.y > CH + 16 then
            table.remove(powerups, pi)
        else
            local cx = p.x + p.w / 2
            local cy = p.y + p.h / 2
            if cy >= paddle_y - 2
                and cy <= paddle_y + paddle_h + 6
                and cx >= paddle_x - paddle_w / 2 - 4
                and cx <= paddle_x + paddle_w / 2 + 4
            then
                apply_power(p.kind)
                table.remove(powerups, pi)
            else
                pi = pi + 1
            end
        end
    end

    if held_left then
        paddle_x = math.max(paddle_w / 2 + 5, paddle_x - paddle_spd * dt * sc)
    end
    if held_right then
        paddle_x = math.min(CW - paddle_w / 2 - 5, paddle_x + paddle_spd * dt * sc)
    end

    if held_fire then
        try_serve()
        if not waiting then
            show_overlay(false, "")
        end
    end
end

local star_x = {}
local star_y = {}
for s = 1, 18 do
    star_x[s] = (s * 113 + 5) % (CW - 2) + 1
    star_y[s] = (s * 71 + 19) % (CH - 2) + 1
end

local function draw_powerup(p)
    local x, y = math.floor(p.x), math.floor(p.y)
    if p.kind == PU_WIDE then
        ui:canvas_rect(CV, x, y, p.w, p.h, 34, 197, 94, 255)
        ui:canvas_rect(CV, x + 1, y + 4, p.w - 2, 3, 20, 50, 30, 255)
    elseif p.kind == PU_SLOW then
        ui:canvas_rect(CV, x, y, p.w, p.h, 59, 130, 246, 255)
        ui:canvas_rect(CV, x + 3, y + 2, 2, 6, 255, 255, 255, 220)
    elseif p.kind == PU_LIFE then
        ui:canvas_rect(CV, x, y, p.w, p.h, 244, 63, 94, 255)
        ui:canvas_rect(CV, x + 4, y + 3, 2, 2, 255, 200, 210, 255)
    else
        ui:canvas_rect(CV, x, y, p.w, p.h, 250, 204, 21, 255)
        ui:canvas_rect(CV, x + 2, y + 2, 6, 6, 40, 30, 10, 255)
    end
    ui:canvas_rect_outline(CV, x, y, p.w, p.h, 255, 255, 255, 140, 1)
end

local function draw_frame()
    ui:canvas_begin_update(CV)
    ui:canvas_clear(CV, 5, 8, 18)

    for s = 1, 18 do
        ui:canvas_pixel(CV, star_x[s], star_y[s], 70, 90, 130, 110)
    end

    for i = 1, #bricks do
        local b = bricks[i]
        if b.alive then
            local c = COL_ROW[(b.row - 1) % #COL_ROW + 1]
            local x, y = math.floor(b.x), math.floor(b.y)
            ui:canvas_rect(CV, x, y, b.w, b.h, c[1], c[2], c[3], 255)
            if b.pu_kind ~= nil then
                local px = x + b.w - 5
                local py = y + 2
                if b.pu_kind == PU_WIDE then
                    ui:canvas_rect(CV, px, py, 3, 3, 74, 222, 128, 255)
                elseif b.pu_kind == PU_SLOW then
                    ui:canvas_rect(CV, px, py, 3, 3, 147, 197, 253, 255)
                elseif b.pu_kind == PU_LIFE then
                    ui:canvas_rect(CV, px, py, 3, 3, 251, 113, 133, 255)
                else
                    ui:canvas_rect(CV, px, py, 3, 3, 253, 224, 71, 255)
                end
            end
        end
    end

    for i = 1, #powerups do
        draw_powerup(powerups[i])
    end

    local px0 = math.floor(paddle_x - paddle_w / 2)
    ui:canvas_rect(CV, px0, paddle_y, paddle_w, paddle_h, 56, 189, 248, 255)
    ui:canvas_rect(CV, math.floor(paddle_x) - 3, paddle_y + paddle_h, 6, 6, 125, 211, 252, 255)
    ui:canvas_rect_outline(CV, px0, paddle_y, paddle_w, paddle_h, 255, 255, 255, 160, 1)

    for i = 1, #balls do
        local b = balls[i]
        local bx, by = math.floor(b.x), math.floor(b.y)
        ui:canvas_rect(CV, bx - 2, by - 2, 5, 5, 250, 250, 255, 255)
        ui:canvas_rect(CV, bx - 1, by - 1, 3, 3, 100, 255, 200, 240)
    end

    ui:canvas_end_update(CV)
    ui:canvas_apply(CV)
end

ui:on_frame(function()
    local now = util.game_time()
    local dt = now - last_t
    last_t = now
    if dt < 0 then
        dt = 0
    end
    if dt > 0.1 then
        dt = 0.1
    end

    local events = ui:poll_input()
    for i = 1, #events do
        local ev = events[i]
        local evt = string.lower(ev.event or "")
        local key = ev.value or ""
        if evt == "keydown" then
            if key == "LeftArrow" or key == "A" then
                held_left = true
            end
            if key == "RightArrow" or key == "D" then
                held_right = true
            end
            if key == "Space" or key == "UpArrow" or key == "W" then
                held_fire = true
            end
            if key == "R" then
                init_game()
            end
            if (key == "Space" or key == "Return") and game_over then
                init_game()
            end
        elseif evt == "keyup" then
            if key == "LeftArrow" or key == "A" then
                held_left = false
            end
            if key == "RightArrow" or key == "D" then
                held_right = false
            end
            if key == "Space" or key == "UpArrow" or key == "W" then
                held_fire = false
            end
        end
    end

    step(dt)
    draw_frame()
    ui:commit()
    warmup = math.max(0, warmup - 1)
end)

function on_btn_left(_v, _pid)
    if not game_over then
        paddle_x = math.max(paddle_w / 2 + 5, paddle_x - 28)
    end
end

function on_btn_right(_v, _pid)
    if not game_over then
        paddle_x = math.min(CW - paddle_w / 2 - 5, paddle_x + 28)
    end
end

function on_btn_fire(_v, _pid)
    if game_over then
        init_game()
        return
    end
    try_serve()
    if not waiting then
        show_overlay(false, "")
    end
end

function on_restart(_v, _pid)
    init_game()
end

ui:element({ id = "bg", type = "panel", rect = px2(0, 0, W, H), style = { bg = "#020617" } })
ui:element({ id = "header", type = "panel", rect = px2(10, 6, W - 20, HUD_H - 12), style = { bg = "#0F172A", border_radius = 10 } })

ui:element({
    id = "title_lbl",
    type = "label",
    rect = px2(14, 10, W - 130, 22),
    props = { text = "<b><color=#38BDF8>ORBITAL BREAK</color></b>" },
    style = { align = "left", font_size = 16, color = "#F8FAFC" },
})

ui:element({
    id = "score_lbl",
    type = "label",
    rect = px2(14, 28, W - 130, 20),
    props = { text = "<b>0</b>  <color=#64748B>lvl 1 · 3 lives · best 0</color>" },
    style = { align = "left", font_size = 11, color = "#E2E8F0" },
})

ui:element({
    id = "iface_btn",
    type = "interface_button",
    rect = px2(W - 108, 12, 98, 30),
    props = { text = "INTERFACE" },
    style = { bg = "#4C1D95", text = "#EDE9FE", font_size = 9 },
})

ui:element({
    id = "frame_cv",
    type = "panel",
    rect = px2(CX0 - 4, CY0 - 4, CW + 8, CH + 8),
    style = { bg = "#000000", border_radius = 12 },
})

ui:element({ id = CV, type = "canvas", rect = px2(CX0, CY0, CW, CH) })

ui:element({
    id = "go_lbl",
    type = "label",
    rect = px2(CX0 + 8, CY0 + 10, CW - 16, 52),
    props = { text = "", visible = "false" },
    style = { align = "center", font_size = 13, color = "#F87171" },
})

local BW = 54
local RW = 64
local GAP = 6
local fw = CW - BW * 2 - RW - GAP * 3
local xL = MARGIN
local xF = xL + BW + GAP
local xR_btn = xF + fw + GAP
local xR = xR_btn + RW + GAP

ui:element({
    id = "btn_left",
    type = "button",
    rect = px2(xL, H - CTRL_H, BW, 42),
    props = { text = "◀" },
    style = { bg = "#1E293B", text = "#F1F5F9", font_size = 18, border_radius = 8 },
    on_click = "on_btn_left",
})

ui:element({
    id = "btn_fire",
    type = "button",
    rect = px2(xF, H - CTRL_H, fw, 42),
    props = { text = "FIRE" },
    style = { bg = "#92400E", text = "#FEF3C7", font_size = 13, border_radius = 8 },
    on_click = "on_btn_fire",
})

ui:element({
    id = "btn_restart",
    type = "button",
    rect = px2(xR_btn, H - CTRL_H, RW, 42),
    props = { text = "RESTART" },
    style = { bg = "#0369A1", text = "#F0F9FF", font_size = 10, border_radius = 8 },
    on_click = "on_restart",
})

ui:element({
    id = "btn_right",
    type = "button",
    rect = px2(xR, H - CTRL_H, BW, 42),
    props = { text = "▶" },
    style = { bg = "#1E293B", text = "#F1F5F9", font_size = 18, border_radius = 8 },
    on_click = "on_btn_right",
})

ui:element({
    id = "hint_lbl",
    type = "label",
    rect = px2(12, H - CTRL_H - 18, W - 24, 14),
    props = {
        text = "<color=#64748B>Chip on brick = drop | green wide | blue slow | red extra life | yellow split</color>",
    },
    style = { align = "center", font_size = 8, color = "#64748B" },
})

init_game()
