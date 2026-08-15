-- LUNAR STRIKE - Space Invaders
-- Proper 60fps: on_frame + util.game_time() dt + poll_input() for keyboard
-- Based on the Tetris example pattern. No tick() needed.
-- Multiplayer: draw_frame uses canvas_begin_update/canvas_end_update (one paint = one op batch).
-- ◀ ▶ · FIRE · RESTART · INTERFACE then ←/→ A/D + Space/W/↑

local ui = ss.ui.surface("main")
ss.ui.activate("main")
ui:clear()

local W, H = ui:size().w, ui:size().h
local HUD_H  = 50
local CTRL_H = 54
local MARGIN = 8
local CV     = "inv_cv"
local CW     = W - MARGIN * 2
local CH     = H - HUD_H - CTRL_H - MARGIN * 2
local CX0    = MARGIN
local CY0    = HUD_H + MARGIN

-- Game constants (all in pixels/sec or seconds)
local COLS, ROWS   = 6, 4
local INV_W, INV_H = 32, 16
local GAP_X, GAP_Y = 10, 7
local FLEET_SPD    = 40    -- px/sec side movement
local FLEET_DROP   = 8     -- px drop on wall bounce
local FIRE_CD      = 0.28  -- seconds between player shots
local ALIEN_CD_MIN = 3.0   -- seconds min between alien shots
local ALIEN_CD_JIT = 4.0   -- extra random seconds
local PBULLET_SPD  = 260   -- px/sec upward
local ABLULET_SPD  = 90    -- px/sec downward (+ wave bonus)
local PLAYER_SPD   = 190   -- px/sec
local MOVE_HOLD_T  = 0.04  -- seconds per held-button nudge fire

-- Player
local player_x   = CW / 2
local player_y   = 30
local player_w   = 46
local player_h   = 12

local pbullet    = nil
local abullets   = {}
local fire_cd    = 0.0
local alien_cd   = ALIEN_CD_MIN + math.max(0, (ALIEN_CD_MIN * 0.5))

local score, lives, wave = 0, 3, 1
local best = 0
local game_over = false
local vp_timer   = 0.0   -- victory/hit pause countdown

local fleet_dir  = 1
local invaders   = {}

-- Input
local held_left  = false
local held_right = false
local held_fire  = false
local left_rep   = 0.0   -- auto-repeat timer for button hold
local right_rep  = 0.0

local warmup = 8
local last_t = util.game_time()

local rng = (9871 + W + H) % 2147483646 + 1
local function rnd(n)
    if n <= 1 then return 1 end
    rng = (rng * 48271) % 2147483647
    return (rng % n) + 1
end

local function px(x, y, w, h)
    return { unit = "px", x = x, y = y, w = w, h = h }
end

-- ── HUD / overlay helpers ─────────────────────────────────────────────────────
local function update_hud()
    local s = ui:get("score_lbl")
    if s then
        s:set_props({
            text = "<b>" .. tostring(score) .. "</b>"
                .. "  <color=#64748B>wave " .. tostring(wave)
                .. " · ♥" .. tostring(lives)
                .. " · best " .. tostring(best) .. "</color>",
        })
    end
end

local function show_overlay(vis, txt)
    local g = ui:get("go_lbl")
    if g then
        g:set_props({
            visible = vis and "true" or "false",
            text    = vis and (txt or "") or "",
        })
    end
end

-- ── Invader grid ──────────────────────────────────────────────────────────────
local function build_invaders()
    invaders = {}
    local total_w = COLS * INV_W + (COLS - 1) * GAP_X
    local start_x = (CW - total_w) / 2
    local row_step = INV_H + GAP_Y
    local base_y = CH - 28
    local idx = 0
    for r = 1, ROWS do
        for c = 1, COLS do
            idx = idx + 1
            invaders[idx] = {
                x   = start_x + (c - 1) * (INV_W + GAP_X),
                y   = base_y - (r - 1) * row_step,
                alive = true,
                row = r, col = c,
            }
        end
    end
    fleet_dir = 1
end

local function init_wave()
    pbullet  = nil
    abullets = {}
    fire_cd  = 0
    alien_cd = ALIEN_CD_MIN + rnd(math.floor(ALIEN_CD_JIT * 10)) / 10
    game_over = false
    vp_timer  = 0
    player_x  = CW / 2
    build_invaders()
    show_overlay(false, "")
    update_hud()
end

local function init_game()
    score = 0
    lives = 3
    wave  = 1
    init_wave()
end

-- ── Game logic ────────────────────────────────────────────────────────────────
local function alive_count()
    local n = 0
    for i = 1, #invaders do
        if invaders[i].alive then n = n + 1 end
    end
    return n
end

local function fleet_bounds()
    local minx, maxx, miny = CW, 0, CH
    for i = 1, #invaders do
        local v = invaders[i]
        if v.alive then
            if v.x < minx then minx = v.x end
            if v.x + INV_W > maxx then maxx = v.x + INV_W end
            if v.y < miny then miny = v.y end
        end
    end
    return minx, maxx, miny
end

local function try_player_shoot()
    if game_over or vp_timer > 0 then return end
    if pbullet == nil and fire_cd <= 0 then
        pbullet = { x = player_x, y = player_y + player_h + 2 }
        fire_cd = FIRE_CD
    end
end

local function try_alien_shoot()
    local bottom = {}
    for i = 1, #invaders do
        local v = invaders[i]
        if v.alive then
            if not bottom[v.col] or v.row > bottom[v.col].row then
                bottom[v.col] = v
            end
        end
    end
    local opts = {}
    for c = 1, COLS do
        if bottom[c] then opts[#opts + 1] = bottom[c] end
    end
    if #opts == 0 then return end
    local inv = opts[rnd(#opts)]
    local spd = ABLULET_SPD + wave * 8
    abullets[#abullets + 1] = { x = inv.x + INV_W / 2, y = inv.y - 2, vy = spd }
end

local function aabb(ax,ay,aw,ah, bx,by,bw,bh)
    return ax < bx+bw and ax+aw > bx and ay < by+bh and ay+ah > by
end

local function player_box()
    return player_x - player_w/2 + 4, player_y + 2, player_w - 8, player_h - 2
end

local function lose_life()
    lives = lives - 1
    abullets = {}
    pbullet  = nil
    if lives <= 0 then
        game_over = true
        if score > best then best = score end
        show_overlay(true, "<color=#F87171><b>MISSION FAILED</b></color>\n<color=#94A3B8>RESTART or Space</color>")
    else
        show_overlay(true, "<color=#FBBF24><b>SHIP HIT!</b></color>\n<color=#94A3B8>" .. tostring(lives) .. " ships left</color>")
        vp_timer = 1.4
    end
    update_hud()
end

local function step(dt)
    if game_over then return end

    -- Victory/hit pause countdown
    if vp_timer > 0 then
        vp_timer = vp_timer - dt
        if vp_timer <= 0 then
            vp_timer = 0
            show_overlay(false, "")
            if alive_count() == 0 then
                wave  = wave + 1
                score = score + 40 * wave
                build_invaders()
                alien_cd = ALIEN_CD_MIN + rnd(math.floor(ALIEN_CD_JIT * 10)) / 10
                update_hud()
            end
        end
        return
    end

    -- Player movement (smooth)
    if held_left then
        player_x = math.max(player_w/2 + 5, player_x - PLAYER_SPD * dt)
    end
    if held_right then
        player_x = math.min(CW - player_w/2 - 5, player_x + PLAYER_SPD * dt)
    end

    -- Auto-fire while held
    fire_cd = math.max(0, fire_cd - dt)
    if held_fire then
        try_player_shoot()
    end

    -- Fleet sideways movement
    local mn, mx = fleet_bounds()
    if mn < mx then
        local move = FLEET_SPD * fleet_dir * dt
        local new_mn = mn + move
        local new_mx = mx + move
        if new_mx > CW - 6 or new_mn < 6 then
            fleet_dir = -fleet_dir
            for i = 1, #invaders do
                if invaders[i].alive then
                    invaders[i].y = invaders[i].y - FLEET_DROP
                end
            end
        else
            for i = 1, #invaders do
                if invaders[i].alive then
                    invaders[i].x = invaders[i].x + move
                end
            end
        end
    end

    -- Player bullet
    if pbullet then
        pbullet.y = pbullet.y + PBULLET_SPD * dt
        if pbullet.y > CH + 10 then
            pbullet = nil
        else
            local bx, by = pbullet.x - 2, pbullet.y
            for i = 1, #invaders do
                local v = invaders[i]
                if v.alive and aabb(bx, by, 4, 10, v.x, v.y, INV_W, INV_H) then
                    v.alive = false
                    pbullet  = nil
                    score    = score + 10 * (ROWS - v.row + 1)
                    update_hud()
                    if alive_count() == 0 then
                        vp_timer = 1.2
                        show_overlay(true, "<color=#4ADE80><b>WAVE CLEAR!</b></color>")
                    end
                    break
                end
            end
        end
    end

    -- Alien shots
    alien_cd = alien_cd - dt
    if alien_cd <= 0 then
        try_alien_shoot()
        alien_cd = ALIEN_CD_MIN + rnd(math.floor(ALIEN_CD_JIT * 10)) / 10
    end

    -- Alien bullets
    local px1, py1, pw1, ph1 = player_box()
    local ai = 1
    while ai <= #abullets do
        local b = abullets[ai]
        b.y = b.y - b.vy * dt
        if b.y < -12 then
            table.remove(abullets, ai)
        elseif aabb(px1, py1, pw1, ph1, b.x-2, b.y-8, 4, 10) then
            table.remove(abullets, ai)
            lose_life()
            return
        else
            ai = ai + 1
        end
    end

    -- Invaders reach ship
    if alive_count() > 0 then
        local _, _, lowest = fleet_bounds()
        if lowest < player_y + player_h + 6 then
            lose_life()
            if not game_over then
                build_invaders()
                vp_timer = 1.2
            end
        end
    end
end

-- ── Canvas draw ───────────────────────────────────────────────────────────────
local star_x = {}
local star_y = {}
for s = 1, 18 do
    star_x[s] = (s * 113 + 5) % (CW - 2) + 1
    star_y[s] = (s * 71 + 19) % (CH - 2) + 1
end

local INV_COLORS = {
    { 140, 220, 150 },
    { 110, 200, 190 },
    { 130, 170, 240 },
    { 200, 160, 100 },
}

local function draw_frame()
    ui:canvas_begin_update(CV)
    ui:canvas_clear(CV, 5, 8, 18)

    -- stars
    for s = 1, 18 do
        ui:canvas_pixel(CV, star_x[s], star_y[s], 70, 90, 130, 110)
    end

    -- invaders
    for i = 1, #invaders do
        local v = invaders[i]
        if v.alive then
            local c = INV_COLORS[v.row] or INV_COLORS[1]
            local x, y = math.floor(v.x), math.floor(v.y)
            -- body
            ui:canvas_rect(CV, x+3, y+2, INV_W-6, INV_H-4, c[1], c[2], c[3], 255)
            -- outline
            ui:canvas_rect_outline(CV, x, y, INV_W, INV_H, 220, 220, 255, 180, 2)
            -- eye-slot cutouts
            ui:canvas_rect(CV, x+7,       y+INV_H-5, 5, 3, 20, 20, 30, 255)
            ui:canvas_rect(CV, x+INV_W-12, y+INV_H-5, 5, 3, 20, 20, 30, 255)
        end
    end

    -- alien bullets
    for i = 1, #abullets do
        local b = abullets[i]
        local by = math.floor(b.y)
        ui:canvas_rect(CV, math.floor(b.x)-1, by-7, 3, 9, 255, 80, 80, 255)
        -- glow
        ui:canvas_rect(CV, math.floor(b.x)-2, by-8, 5, 11, 255, 80, 80, 60)
    end

    -- player bullet
    if pbullet then
        local px2 = math.floor(pbullet.x)
        local py2 = math.floor(pbullet.y)
        ui:canvas_rect(CV, px2-1, py2, 3, 10, 100, 255, 180, 255)
        ui:canvas_rect(CV, px2-2, py2-1, 5, 12, 100, 255, 180, 60)
    end

    -- ship
    local px0 = math.floor(player_x - player_w/2)
    ui:canvas_rect(CV, px0, player_y, player_w, player_h, 56, 189, 248, 255)
    ui:canvas_rect(CV, math.floor(player_x)-3, player_y+player_h, 6, 6, 125, 211, 252, 255)
    ui:canvas_rect_outline(CV, px0, player_y, player_w, player_h, 255, 255, 255, 200, 2)
    -- engine glow
    ui:canvas_rect(CV, px0+4, player_y-3, player_w-8, 3, 255, 160, 50, 80)

    ui:canvas_end_update(CV)
    ui:canvas_apply(CV)
end

-- ── on_frame loop ─────────────────────────────────────────────────────────────
ui:on_frame(function()
    local now = util.game_time()
    local dt  = now - last_t
    last_t    = now
    if dt < 0 then dt = 0 end
    if dt > 0.1 then dt = 0.1 end

    -- Poll keyboard events (frame-aligned, not tick-rate)
    local events = ui:poll_input()
    for i = 1, #events do
        local ev  = events[i]
        local evt = string.lower(ev.event or "")
        local key = ev.value or ""
        if evt == "keydown" then
            if key == "LeftArrow"  or key == "A" then held_left  = true end
            if key == "RightArrow" or key == "D" then held_right = true end
            if key == "Space" or key == "UpArrow" or key == "W" then held_fire = true end
            if (key == "Space" or key == "Return") and game_over then
                init_game()
            end
        elseif evt == "keyup" then
            if key == "LeftArrow"  or key == "A" then held_left  = false end
            if key == "RightArrow" or key == "D" then held_right = false end
            if key == "Space" or key == "UpArrow" or key == "W" then held_fire = false end
        end
    end

    step(dt)
    draw_frame()
    ui:commit()
    warmup = math.max(0, warmup - 1)
end)

-- ── Button handlers ───────────────────────────────────────────────────────────
function on_btn_left(_v, _pid)
    if not game_over and vp_timer <= 0 then
        player_x = math.max(player_w/2 + 5, player_x - 28)
    end
end

function on_btn_right(_v, _pid)
    if not game_over and vp_timer <= 0 then
        player_x = math.min(CW - player_w/2 - 5, player_x + 28)
    end
end

function on_btn_fire(_v, _pid)
    try_player_shoot()
end

function on_restart(_v, _pid)
    init_game()
end

-- ── Layout ────────────────────────────────────────────────────────────────────
local function px2(x, y, w, h)
    return { unit = "px", x = x, y = y, w = w, h = h }
end

ui:element({ id = "bg", type = "panel", rect = px2(0, 0, W, H), style = { bg = "#020617" } })
ui:element({ id = "header", type = "panel", rect = px2(10, 6, W-20, HUD_H-12), style = { bg = "#0F172A", border_radius = 10 } })

ui:element({ id = "title_lbl", type = "label", rect = px2(14, 10, W-130, 22),
    props = { text = "<b><color=#A78BFA>LUNAR STRIKE</color></b>" },
    style = { align = "left", font_size = 16, color = "#F8FAFC" } })

ui:element({ id = "score_lbl", type = "label", rect = px2(14, 28, W-130, 20),
    props = { text = "<b>0</b>  <color=#64748B>wave 1 · ♥3 · best 0</color>" },
    style = { align = "left", font_size = 11, color = "#E2E8F0" } })

ui:element({ id = "iface_btn", type = "interface_button", rect = px2(W-108, 12, 98, 30),
    props = { text = "INTERFACE" },
    style = { bg = "#4C1D95", text = "#EDE9FE", font_size = 9 } })

ui:element({ id = "frame_cv", type = "panel",
    rect = px2(CX0-4, CY0-4, CW+8, CH+8),
    style = { bg = "#000000", border_radius = 12 } })

ui:element({ id = CV, type = "canvas", rect = px2(CX0, CY0, CW, CH) })

ui:element({ id = "go_lbl", type = "label",
    rect = px2(CX0+8, CY0+10, CW-16, 52),
    props = { text = "", visible = "false" },
    style = { align = "center", font_size = 13, color = "#F87171" } })

local BW = 54
local RW = 64
local GAP = 6
local fw = CW - BW*2 - RW - GAP*3
local xL = MARGIN
local xF = xL + BW + GAP
local xR_btn = xF + fw + GAP
local xR = xR_btn + RW + GAP

ui:element({ id = "btn_left", type = "button",
    rect = px2(xL, H-CTRL_H, BW, 42),
    props = { text = "◀" },
    style = { bg = "#1E293B", text = "#F1F5F9", font_size = 18, border_radius = 8 },
    on_click = "on_btn_left" })

ui:element({ id = "btn_fire", type = "button",
    rect = px2(xF, H-CTRL_H, fw, 42),
    props = { text = "FIRE" },
    style = { bg = "#92400E", text = "#FEF3C7", font_size = 13, border_radius = 8 },
    on_click = "on_btn_fire" })

ui:element({ id = "btn_restart", type = "button",
    rect = px2(xR_btn, H-CTRL_H, RW, 42),
    props = { text = "RESTART" },
    style = { bg = "#0369A1", text = "#F0F9FF", font_size = 10, border_radius = 8 },
    on_click = "on_restart" })

ui:element({ id = "btn_right", type = "button",
    rect = px2(xR, H-CTRL_H, BW, 42),
    props = { text = "▶" },
    style = { bg = "#1E293B", text = "#F1F5F9", font_size = 18, border_radius = 8 },
    on_click = "on_btn_right" })

ui:element({ id = "hint_lbl", type = "label",
    rect = px2(12, H-CTRL_H-18, W-24, 14),
    props = { text = "<color=#64748B>INTERFACE → keyboard · Alt exits · Space = shoot</color>" },
    style = { align = "center", font_size = 9, color = "#64748B" } })

init_game()