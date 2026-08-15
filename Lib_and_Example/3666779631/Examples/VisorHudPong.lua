-- VisorHudPong.lua
-- Minimal Pong on the programmable visor: canvas playfield + chrome.
-- Same loop model as Games/Tetris.lua + Games/BlockBreaker.lua: **all sim + input + draw in on_frame**
-- (Unity ~60 Hz). Overlay / drag layout changes are callback-driven, so gameplay never shares
-- responsibility for repositioning the HUD.
-- **IMPORTANT (multiplayer):** `hud:commit()` MUST be called every on_frame to flush canvas ops to clients -
-- the same requirement as console canvas games (SpaceInvaders.lua, Tetris.lua, etc.). Without it, draw ops
-- queue on the server but are never sent, so clients see a static or empty canvas.
-- Multiplayer: server uses visor-specific canvas dense snapshots + sync floor (see ScriptedScreens.cfg);
-- this sample uses `canvas_with_update` and fewer center-line rects to keep op count low.
--
-- Input: **hud:poll_input()** each frame (keydown/keyup) → held left/right while keys down; ◀ / ▶ nudge.
-- Click **INTERFACE** for keyboard focus (Alt exits - vanilla). Space / P / Escape pause; R reset.
-- **Drag:** the **deck** panel is draggable and uses layout auto-drag-group generation so the whole
-- cluster moves; `hud:on_drag(rebuild_shell)` commits the new position automatically.
-- **Save:** `ic.persist` persists the drag offset across world save/load and housing power cycles.

local hud = ss.hud.surface("main")
ss.hud.activate("main")

local CANVAS_ID = "pong_cv"
local CANVAS_W, CANVAS_H = 200, 112
-- Header: separate rows so the score line is never vertically overlapped by the canvas (was clipping descenders).
local ROW_TITLE_H = 16
local ROW_SCORE_H = 22
local GAP_SCORE_TO_CANVAS = 8
local PANEL_TOP_PAD = 6
local BTN_ROW_H = 36
local PAD = 8
local IFACE_W, IFACE_H = 76, 18
local PANEL_W = CANVAS_W + PAD * 2
local PANEL_H = PANEL_TOP_PAD + ROW_TITLE_H + ROW_SCORE_H + GAP_SCORE_TO_CANVAS + CANVAS_H + PAD + BTN_ROW_H + PAD

local BALL = 5
local PADDLE_HW = 22
local PADDLE_H = 5
local TOP_Y = 12
local BOT_Y = CANVAS_H - 12

local min_x = PADDLE_HW + 2
local max_x = CANVAS_W - PADDLE_HW - 2

local score_p, score_ai = 0, 0
local paused = false

local ball = { x = CANVAS_W * 0.5, y = CANVAS_H * 0.5, vx = 78, vy = 62 }
local ai_x = CANVAS_W * 0.5
local ai_aim_x = CANVAS_W * 0.5 -- smoothed target; stops perfect frame-by-frame tracking
local player_x = CANVAS_W * 0.5

local canvas_ready = false
local last_score_txt = ""

local rebuild_shell

-- Held movement (updated from poll_input every on_frame - same pattern as BlockBreaker.lua)
local held_left = false
local held_right = false

local PADDLE_PX_PER_SEC = 300
local BTN_NUDGE = 34

local function sync_pause_button()
    local b = hud:get("btn_pause")
    if b then
        pcall(function()
            b:set_props({ text = paused and "RESUME" or "PAUSE" })
        end)
    end
end

local function surface_wh()
    -- hud:size() returns the wearer's actual visor canvas dims (real client RT on
    -- single-player / listen host; client-relayed RT on dedicated server). No fallback
    -- math needed; the runtime guarantees a sane non-zero size.
    local sz = hud:size()
    return tonumber(sz.w), tonumber(sz.h)
end

local function drag_panel_props(id)
    return {
        z_index = 0,
        draggable = "true",
        drag_group = "auto",
        drag_bounds = "screen",
    }
end

-- Pick a base position bottom-left that's already clear of vanilla UI. ss.hud.first_free_anchor
-- walks the safe area produced by ss.hud.safe_area() and returns the first anchor whose
-- placement doesn't intersect any panel from ss.client_overlay(). Falls back to the first
-- anchor in the list if every option conflicts (caller still gets a usable rect).
local function base_xy()
    local p = ss.hud.first_free_anchor(
        { "bottom_left", "bottom_right", "top_left", "top_right" },
        PANEL_W, PANEL_H)
    if not p then return 0, 0 end
    return tonumber(p.x) or 0, tonumber(p.y) or 0
end

-- Clamp a saved drag offset (dx, dy) so a panel of size (w, h) anchored at base
-- (bx, by) cannot leave the visible visor canvas (0..W, 0..H). Called from
-- rebuild_shell so a stale offset from a different screen aspect, an oversize
-- drag, or a corrupted save never strands the panel off-screen where the user
-- can't see it (and therefore can't drag it back). When the panel is bigger
-- than the canvas (degenerate aspect), pins the panel at the closest edge.
local function clamp_offset(bx, by, w, h, W, H, dx, dy)
    local lo_x, hi_x = -bx, W - w - bx
    local lo_y, hi_y = -by, H - h - by
    if hi_x < lo_x then hi_x = lo_x end
    if hi_y < lo_y then hi_y = lo_y end
    return math.max(lo_x, math.min(hi_x, dx)),
           math.max(lo_y, math.min(hi_y, dy))
end

local function serve_toward_player()
    ball.x = CANVAS_W * 0.5
    ball.y = CANVAS_H * 0.5
    local sc0 = (tonumber(score_p) or 0) + (tonumber(score_ai) or 0)
    local spd = 82 + sc0 * 2 -- gentler ramp so rallies stay readable
    local ang = (math.random() - 0.5) * 0.9
    ball.vx = tonumber(math.cos(ang) * spd * (math.random(1, 2) == 1 and 1 or -1)) or 78
    ball.vy = tonumber(math.abs(math.sin(ang)) * spd + 20) or 62
    if math.random(1, 2) == 1 then
        ball.vy = -ball.vy
    end
    ai_aim_x = ai_x
end

local function reset_match()
    score_p, score_ai = 0, 0
    player_x = CANVAS_W * 0.5
    ai_x = CANVAS_W * 0.5
    ai_aim_x = ai_x
    serve_toward_player()
end

local function draw_field()
    if not canvas_ready then
        return
    end
    -- Clamp for canvas ops (Lua-CSharp can throw on out-of-range if coords go bad).
    local bx = math.max(0, math.min(CANVAS_W, tonumber(ball.x) or 0))
    local by = math.max(0, math.min(CANVAS_H, tonumber(ball.y) or 0))
    -- One grouped paint per frame (same as console canvas_with_update in GUIDE.MD); coarser
    -- center dashes than step=6 cuts op count when dense-frame snapshot threshold is not used.
    hud:canvas_with_update(CANVAS_ID, function()
        hud:canvas_clear(CANVAS_ID, 8, 12, 22)
        for y = 0, CANVAS_H - 1, 10 do
            hud:canvas_rect(CANVAS_ID, CANVAS_W * 0.5 - 1, y, 2, 3, 40, 56, 72, 120)
        end
        hud:canvas_rect(CANVAS_ID, ai_x - PADDLE_HW, TOP_Y - PADDLE_H, PADDLE_HW * 2, PADDLE_H, 148, 196, 255, 255)
        hud:canvas_rect(CANVAS_ID, player_x - PADDLE_HW, BOT_Y, PADDLE_HW * 2, PADDLE_H, 56, 211, 138, 255)
        hud:canvas_rect(CANVAS_ID, bx - BALL * 0.5, by - BALL * 0.5, BALL, BALL, 255, 230, 120, 255)
    end)
    hud:canvas_apply(CANVAS_ID)
end

rebuild_shell = function()
    local W, H = surface_wh()
    local bx, by = base_xy()
    local off = hud:drag_offset("deck")
    local dx, dy = clamp_offset(bx, by, PANEL_W, PANEL_H, W, H, tonumber(off.dx) or 0, tonumber(off.dy) or 0)
    local px = bx + dx
    local py = by + dy
    canvas_ready = false
    last_score_txt = ""
    local bw = (PANEL_W - PAD * 2 - 12) / 4

    hud:clear()
    hud:layout({
        layout = "flex",
        rect = { unit = "px", x = px, y = py, w = PANEL_W, h = PANEL_H },
        children = {
            {
                id = "deck",
                type = "panel",
                layout = "column",
                gap = 0,
                rect = { w = PANEL_W, h = PANEL_H },
                padding = { left = PAD, right = PAD, top = PANEL_TOP_PAD, bottom = PAD },
                props = drag_panel_props("deck"),
                style = { bg = "#0A1020E6", border = "#38BDF8", border_width = 1 },
                children = {
                    {
                        layout = "row",
                        align = "center",
                        gap = 6,
                        rect = { h = ROW_TITLE_H },
                        children = {
                            {
                                id = "title",
                                type = "label",
                                flex = 1,
                                props = { text = "VISOR PONG" },
                                style = { font_size = 11, color = "#94A3B8", align = "left" },
                            },
                            {
                                id = "iface_btn",
                                type = "interface_button",
                                rect = { w = IFACE_W, h = IFACE_H },
                                props = { text = "INTERFACE" },
                                style = { bg = "#422006", text = "#FDE68A", font_size = 8 },
                            },
                        },
                    },
                    {
                        layout = "row",
                        rect = { h = ROW_SCORE_H },
                        children = {
                            {
                                id = "score_lbl",
                                type = "label",
                                flex = 1,
                                props = { text = string.format("AI %2d  ·  YOU %2d", score_ai, score_p) },
                                style = { font_size = 10, color = "#E2E8F0", align = "left" },
                            },
                        },
                    },
                    { layout = "row", rect = { h = GAP_SCORE_TO_CANVAS }, children = {} },
                    {
                        layout = "row",
                        rect = { h = CANVAS_H },
                        children = {
                            {
                                id = CANVAS_ID,
                                type = "canvas",
                                rect = { w = CANVAS_W, h = CANVAS_H },
                                props = { width = tostring(CANVAS_W), height = tostring(CANVAS_H), z_index = 0 },
                                style = { bg = "#050810" },
                            },
                        },
                    },
                    { layout = "row", rect = { h = PAD }, children = {} },
                    {
                        layout = "row",
                        gap = 4,
                        rect = { h = BTN_ROW_H - 4 },
                        children = {
                            {
                                id = "btn_l",
                                type = "button",
                                rect = { w = bw },
                                props = { text = "◀", z_index = 10 },
                                style = { bg = "#1E3A5F", text = "#E0F2FE", font_size = 16 },
                                on_click = function()
                                    player_x = math.max(min_x, (tonumber(player_x) or min_x) - BTN_NUDGE)
                                end,
                            },
                            {
                                id = "btn_r",
                                type = "button",
                                rect = { w = bw },
                                props = { text = "▶", z_index = 10 },
                                style = { bg = "#1E3A5F", text = "#E0F2FE", font_size = 16 },
                                on_click = function()
                                    player_x = math.min(max_x, (tonumber(player_x) or max_x) + BTN_NUDGE)
                                end,
                            },
                            {
                                id = "btn_pause",
                                type = "button",
                                rect = { w = bw },
                                props = { text = paused and "RESUME" or "PAUSE", z_index = 10 },
                                style = { bg = "#854D0E", text = "#FFFBEB", font_size = 11 },
                                on_click = function()
                                    paused = not paused
                                    sync_pause_button()
                                end,
                            },
                            {
                                id = "btn_reset",
                                type = "button",
                                rect = { w = bw },
                                props = { text = "RESET", z_index = 10 },
                                style = { bg = "#334155", text = "#F8FAFC", font_size = 11 },
                                on_click = function()
                                    paused = false
                                    reset_match()
                                    rebuild_shell()
                                end,
                            },
                        },
                    },
                },
            },
        },
    })
    canvas_ready = true
    hud:commit()
    draw_field()
end

local function refresh_score_label()
    local txt = string.format("AI %2d  ·  YOU %2d", score_ai, score_p)
    if txt == last_score_txt then
        return
    end
    last_score_txt = txt
    local ok, el = pcall(function()
        return hud:get("score_lbl")
    end)
    if ok and el then
        pcall(function()
            el:set_props({ text = txt })
        end)
    end
end

local last_clock = nil

local function step_sim(dt, now)
    -- Lua-CSharp: tonumber may fail or dt may be a non-number type; never pass nil into math.max.
    local d = tonumber(dt)
    if d == nil or d ~= d then
        d = 1 / 60
    elseif d <= 0 then
        d = 1 / 60
    elseif d > 0.1 then
        d = 0.1
    end
    dt = d
    now = tonumber(now) or 0

    if paused or not canvas_ready then
        return
    end

    player_x = tonumber(player_x) or (CANVAS_W * 0.5)
    ai_x = tonumber(ai_x) or (CANVAS_W * 0.5)
    ball.x = tonumber(ball.x) or (CANVAS_W * 0.5)
    ball.y = tonumber(ball.y) or (CANVAS_H * 0.5)
    ball.vx = tonumber(ball.vx) or 0
    ball.vy = tonumber(ball.vy) or 0

    -- Player: continuous motion while keys held (poll_input), same idea as BlockBreaker held_left/right.
    if held_left and not held_right then
        player_x = math.max(min_x, player_x - PADDLE_PX_PER_SEC * dt)
    elseif held_right and not held_left then
        player_x = math.min(max_x, player_x + PADDLE_PX_PER_SEC * dt)
    end

    -- AI: laggy aim + capped speed (old code used sign(dx)*full speed every frame = inhuman perfect wall).
    local sc = (tonumber(score_p) or 0) + (tonumber(score_ai) or 0)
    local desired
    if ball.vy < 0 then
        local noise = (math.sin(now * 3.1) + math.sin(now * 9.2)) * 6
        desired = ball.x + ball.vx * 0.07 + noise
    else
        desired = CANVAS_W * 0.5 + math.sin(now * 1.0) * 32
    end
    local aim_rate = ball.vy < 0 and 4.8 or 2.2
    ai_aim_x = ai_aim_x + (desired - ai_aim_x) * math.min(1, aim_rate * dt)

    local dx = ai_aim_x - ai_x
    local ai_px_per_sec = 44 + math.min(24, sc * 2)
    local max_step = ai_px_per_sec * dt
    if dx > max_step then
        dx = max_step
    elseif dx < -max_step then
        dx = -max_step
    end
    ai_x = math.max(min_x, math.min(max_x, ai_x + dx))

    ball.x = ball.x + ball.vx * dt
    ball.y = ball.y + ball.vy * dt

    if ball.x < BALL then
        ball.x = BALL
        ball.vx = math.abs(ball.vx)
    elseif ball.x > CANVAS_W - BALL then
        ball.x = CANVAS_W - BALL
        ball.vx = -math.abs(ball.vx)
    end

    local function paddle_hit(px, py, halfw)
        return math.abs(ball.x - px) <= halfw + BALL and ball.y >= py - PADDLE_H and ball.y <= py + PADDLE_H
    end

    if ball.vy < 0 and paddle_hit(ai_x, TOP_Y - PADDLE_H * 0.5, PADDLE_HW + 2) then
        ball.y = TOP_Y + PADDLE_H + BALL * 0.5
        ball.vy = math.abs(ball.vy)
        ball.vx = ball.vx + (ball.x - ai_x) * 2.8
    end
    if ball.vy > 0 and paddle_hit(player_x, BOT_Y + PADDLE_H * 0.5, PADDLE_HW + 2) then
        ball.y = BOT_Y - BALL * 0.5 - 0.5
        ball.vy = -math.abs(ball.vy)
        ball.vx = ball.vx + (ball.x - player_x) * 2.8
    end

    local cap = 200 + sc * 10
    local sp = math.sqrt(ball.vx * ball.vx + ball.vy * ball.vy)
    if sp > cap and sp > 0.001 then
        local s = cap / sp
        ball.vx, ball.vy = ball.vx * s, ball.vy * s
    end

    if ball.y < -12 then
        score_p = score_p + 1
        serve_toward_player()
        refresh_score_label()
    elseif ball.y > CANVAS_H + 12 then
        score_ai = score_ai + 1
        serve_toward_player()
        refresh_score_label()
    end

    draw_field()
end

local function drain_poll_input()
    local ok, events = pcall(function()
        return hud:poll_input()
    end)
    if not ok or type(events) ~= "table" then
        return
    end
    for i = 1, #events do
        local ev = events[i]
        if type(ev) == "table" then
            local evt = string.lower(tostring(ev.event or ""))
            local key = tostring(ev.value or "")
            if evt == "keydown" then
                if key == "LeftArrow" or key == "A" then
                    held_left = true
                elseif key == "RightArrow" or key == "D" then
                    held_right = true
                elseif key == "Space" or key == "P" or key == "Escape" then
                    paused = not paused
                    sync_pause_button()
                elseif key == "R" then
                    paused = false
                    reset_match()
                    rebuild_shell()
                end
            elseif evt == "keyup" then
                if key == "LeftArrow" or key == "A" then
                    held_left = false
                elseif key == "RightArrow" or key == "D" then
                    held_right = false
                end
            end
        end
    end
end

-- Tetris/BlockBreaker style: one frame function, no gameplay in tick().
local function game_frame()
    drain_poll_input()

    local ok, now = pcall(util.game_time)
    if not ok then
        return
    end
    local now_n = tonumber(now)
    if now_n == nil or now_n ~= now_n then
        return
    end
    now = now_n

    if last_clock == nil then
        last_clock = now
    end
    local dt = now - last_clock
    last_clock = now
    if dt < 0 then
        dt = 0
    end
    if dt > 0.1 then
        dt = 0.1
    end

    step_sim(dt, now)
    -- Must commit every on_frame to flush canvas ops to remote clients (same as SpaceInvaders.lua,
    -- Tetris.lua, etc.). Without this call, draw ops accumulate on the server but are never sent
    -- and clients see no animation in multiplayer.
    hud:commit()
end

hud:on_frame(game_frame)

local PERSIST_KEY = "layout"

local function persist_save_layout()
    local off = hud:drag_offset("deck")
    local ok, json = pcall(util.json.encode, { v = 1, lay_dx = off.dx, lay_dy = off.dy })
    if ok and json then ic.persist.set(PERSIST_KEY, json) end
end

local function persist_restore_layout()
    if not ic.persist.has(PERSIST_KEY) then return end
    local blob = ic.persist.get(PERSIST_KEY)
    if type(blob) ~= "string" or blob == "" then return end
    local ok, decoded = pcall(util.json.decode, blob)
    if not ok or type(decoded) ~= "table" then return end
    local dx = tonumber(decoded.lay_dx)
    local dy = tonumber(decoded.lay_dy)
    if dx and dy and dx == dx and dy == dy then
        hud:set_drag_offset("deck", dx, dy)
    end
end


do
    local ok, t0 = pcall(util.game_time)
    if ok and type(t0) == "number" and t0 == t0 then
        last_clock = t0
    end
    persist_restore_layout()
    local function on_layout_change()
        rebuild_shell()
        persist_save_layout()
    end
    hud:on_drag(on_layout_change)
    ss.hud.on_overlay_change(on_layout_change)
    rebuild_shell()
end
