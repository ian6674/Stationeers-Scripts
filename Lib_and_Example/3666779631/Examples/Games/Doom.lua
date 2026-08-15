-- DOOM-like Game for ScriptedScreens (Canvas Version)
-- A raycasting pseudo-3D dungeon crawler using pixel canvas
-- Controls: Arrow buttons, keyboard (arrows/WASD), or Setting 1-4
-- Enter Interface Mode to use keyboard controls, press ALT to exit
-- Multiplayer: render_canvas uses canvas_begin_update/canvas_end_update (many vlines per frame).

local LT = ic.enums.LogicType
local read = ic.read
local write = ic.write
local yield = ic.yield
local DB = ic.const.BASE_UNIT_INDEX

local s = ss.ui.surface("main")
ss.ui.activate("main")

local screen = s:size()
local W = screen.w
local H = screen.h

-- Canvas for 3D view
local CANVAS_W = 160
local CANVAS_H = 100
local CANVAS_ID = "doom_view"
local VIEW_Y = 40

-- Game constants
local MAP_SIZE = 8

-- Player state
local player = {
    x = 2.5,
    y = 2.5,
    angle = 0,
    health = 100,
    ammo = 50,
    score = 0
}

-- Simple map (1 = wall, 0 = empty, 3 = exit)
local map = {
    { 1, 1, 1, 1, 1, 1, 1, 1 },
    { 1, 0, 0, 0, 0, 0, 0, 1 },
    { 1, 0, 1, 1, 0, 1, 0, 1 },
    { 1, 0, 1, 0, 0, 0, 0, 1 },
    { 1, 0, 0, 0, 1, 1, 0, 1 },
    { 1, 0, 1, 0, 0, 0, 0, 1 },
    { 1, 0, 0, 0, 0, 0, 3, 1 },
    { 1, 1, 1, 1, 1, 1, 1, 1 }
}

local game_over = false
local game_won = false
local canvas_ready = false
local dirty_canvas = true

-- Keyboard input state
local held = {}
local inputq = {}

local function init_game()
    player.x = 2.5
    player.y = 2.5
    player.angle = 0
    player.health = 100
    player.ammo = 50
    player.score = 0
    game_over = false
    game_won = false
end

local function get_map(x, y)
    local mx = math.floor(x)
    local my = math.floor(y)
    if mx < 1 or mx > MAP_SIZE or my < 1 or my > MAP_SIZE then
        return 1
    end
    return map[my][mx]
end

local function cast_ray(angle)
    -- Fast grid-based DDA raycast (much cheaper than step marching)
    local rayDirX = math.cos(angle)
    local rayDirY = math.sin(angle)

    local mapX = math.floor(player.x)
    local mapY = math.floor(player.y)

    local invX = (rayDirX == 0) and 1e30 or (1.0 / rayDirX)
    local invY = (rayDirY == 0) and 1e30 or (1.0 / rayDirY)
    local deltaDistX = math.abs(invX)
    local deltaDistY = math.abs(invY)

    local stepX
    local stepY
    local sideDistX
    local sideDistY

    if rayDirX < 0 then
        stepX = -1
        sideDistX = (player.x - mapX) * deltaDistX
    else
        stepX = 1
        sideDistX = (mapX + 1.0 - player.x) * deltaDistX
    end

    if rayDirY < 0 then
        stepY = -1
        sideDistY = (player.y - mapY) * deltaDistY
    else
        stepY = 1
        sideDistY = (mapY + 1.0 - player.y) * deltaDistY
    end

    local side = 0
    local tile_type = 0

    -- Hard cap steps to prevent runaway
    for _ = 1, 64 do
        if sideDistX < sideDistY then
            sideDistX = sideDistX + deltaDistX
            mapX = mapX + stepX
            side = 0
        else
            sideDistY = sideDistY + deltaDistY
            mapY = mapY + stepY
            side = 1
        end

        -- Out of bounds -> treat as wall
        if mapX < 1 or mapX > MAP_SIZE or mapY < 1 or mapY > MAP_SIZE then
            tile_type = 1
            break
        end

        tile_type = map[mapY][mapX]
        if tile_type == 1 or tile_type == 3 then
            break
        end
    end

    local dist
    if side == 0 then
        dist = (mapX - player.x + (1 - stepX) / 2) / (rayDirX == 0 and 1e-6 or rayDirX)
    else
        dist = (mapY - player.y + (1 - stepY) / 2) / (rayDirY == 0 and 1e-6 or rayDirY)
    end

    if dist < 0 then dist = -dist end
    if dist > 8 then dist = 8 end

    return dist, tile_type
end

local function move_player(forward)
    if game_over or game_won then return end
    local move_speed = 0.2
    local dx = math.cos(player.angle) * move_speed * forward
    local dy = math.sin(player.angle) * move_speed * forward

    local new_x = player.x + dx
    local new_y = player.y + dy

    if get_map(new_x, player.y) == 0 or get_map(new_x, player.y) == 3 then
        player.x = new_x
    end
    if get_map(player.x, new_y) == 0 or get_map(player.x, new_y) == 3 then
        player.y = new_y
    end

    if get_map(player.x, player.y) == 3 then
        game_won = true
    end
end

local function turn_player(dir)
    if game_over or game_won then return end
    player.angle = player.angle + dir * 0.2
end

local function enqueue(action)
    inputq[#inputq + 1] = action
end

local function enqueue_key_action(key)
    if key == "UpArrow" or key == "W" then
        enqueue("forward")
        return
    end
    if key == "DownArrow" or key == "S" then
        enqueue("back")
        return
    end
    if key == "LeftArrow" or key == "A" then
        enqueue("turn_left")
        return
    end
    if key == "RightArrow" or key == "D" then
        enqueue("turn_right")
        return
    end
    if key == "R" then
        enqueue("restart")
        return
    end
end

-- Register keyboard handlers
s:on_keydown(function(key, playerName)
    if key == nil then return end
    if held[key] then return end
    held[key] = true
    enqueue_key_action(key)
end)

s:on_keyup(function(key, playerName)
    if key == nil then return end
    held[key] = false
end)

local function render_canvas()
    if not canvas_ready then return end

    s.canvas_begin_update(CANVAS_ID)
    -- Clear canvas with ceiling/floor
    local half_h = math.floor(CANVAS_H / 2)
    s.canvas_rect(CANVAS_ID, 0, half_h, CANVAS_W, half_h, 80, 80, 80) -- ceiling (top in texture coords)
    s.canvas_rect(CANVAS_ID, 0, 0, CANVAS_W, half_h, 60, 60, 40)      -- floor (bottom in texture coords)

    -- Raycast each column
    local fov = 1.0
    for col = 0, CANVAS_W - 1 do
        local ray_angle = player.angle - fov / 2 + (col / CANVAS_W) * fov
        local dist, tile_type = cast_ray(ray_angle)

        -- Fix fisheye
        dist = dist * math.cos(ray_angle - player.angle)

        local wall_height = math.floor(math.min(CANVAS_H, CANVAS_H / (dist + 0.001)))
        local wall_top = math.floor((CANVAS_H - wall_height) / 2)
        local wall_bottom = wall_top + wall_height

        -- Color based on distance
        local shade = math.floor(math.max(30, math.min(255, 255 - dist * 30)))

        local r, g, b
        if tile_type == 3 then
            r, g, b = 0, shade, 0 -- green for exit
        else
            r, g, b = shade, 0, 0 -- red for walls
        end

        s.canvas_vline(CANVAS_ID, col, wall_top, wall_bottom, r, g, b)
    end

    s.canvas_end_update(CANVAS_ID)
    s.canvas_apply(CANVAS_ID)
end

local function render()
    s:clear()

    -- Background
    s:element({
        id = "bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = H },
        style = { bg = "#000000" }
    })

    -- Canvas element for 3D view
    s:element({
        id = CANVAS_ID,
        type = "canvas",
        rect = { unit = "px", x = 10, y = VIEW_Y, w = W - 120, h = H - VIEW_Y - 10 },
        props = { width = tostring(CANVAS_W), height = tostring(CANVAS_H) },
        style = { bg = "#000000" }
    })
    canvas_ready = true

    -- HUD bar
    s:element({
        id = "hud_bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = 38 },
        style = { bg = "#1A1A2E" }
    })

    s:element({
        id = "title",
        type = "label",
        rect = { unit = "px", x = 10, y = 8, w = 80, h = 24 },
        props = { text = "DOOM" },
        style = { font_size = 18, color = "#FF0000", align = "left" }
    })

    s:element({
        id = "health_lbl",
        type = "label",
        rect = { unit = "px", x = 90, y = 8, w = 100, h = 24 },
        props = { text = "HP:" .. player.health },
        style = { font_size = 14, color = player.health > 30 and "#00FF00" or "#FF0000", align = "left" }
    })

    s:element({
        id = "score_lbl",
        type = "label",
        rect = { unit = "px", x = 190, y = 8, w = 120, h = 24 },
        props = { text = "SCORE:" .. player.score },
        style = { font_size = 14, color = "#FFFFFF", align = "left" }
    })

    -- Interface Mode button
    s:element({
        id = "interface_btn",
        type = "interface_button",
        rect = { unit = "px", x = W - 185, y = 10, w = 70, h = 20 },
        props = { text = "INTERFACE" },
        style = { bg = "#664400", text = "#FFCC00", font_size = 8 }
    })

    -- Control panel (right side)
    local ctrl_x = W - 100
    local btn_size = 32

    s:element({
        id = "ctrl_bg",
        type = "panel",
        rect = { unit = "px", x = W - 105, y = VIEW_Y, w = 100, h = H - VIEW_Y - 45 },
        style = { bg = "#1A1A2E" }
    })

    -- Forward
    s:element({
        id = "btn_fwd",
        type = "button",
        rect = { unit = "px", x = ctrl_x + 18, y = VIEW_Y + 100, w = btn_size, h = btn_size },
        props = { text = "FWD" },
        style = { bg = "#333344", text = "#FFFFFF", font_size = 9 },
        on_click = function(playerName)
            move_player(1); render(); render_canvas()
        end
    })

    -- Back
    s:element({
        id = "btn_back",
        type = "button",
        rect = { unit = "px", x = ctrl_x + 18, y = VIEW_Y + 30, w = btn_size, h = btn_size },
        props = { text = "BAK" },
        style = { bg = "#333344", text = "#FFFFFF", font_size = 9 },
        on_click = function(playerName)
            move_player(-1); render(); render_canvas()
        end
    })

    -- Turn Left
    s:element({
        id = "btn_left",
        type = "button",
        rect = { unit = "px", x = ctrl_x - 16, y = VIEW_Y + 65, w = btn_size, h = btn_size },
        props = { text = "LT" },
        style = { bg = "#333344", text = "#FFFFFF", font_size = 10 },
        on_click = function(playerName)
            turn_player(-1); render(); render_canvas()
        end
    })

    -- Turn Right
    s:element({
        id = "btn_right",
        type = "button",
        rect = { unit = "px", x = ctrl_x + 52, y = VIEW_Y + 65, w = btn_size, h = btn_size },
        props = { text = "RT" },
        style = { bg = "#333344", text = "#FFFFFF", font_size = 10 },
        on_click = function(playerName)
            turn_player(1); render(); render_canvas()
        end
    })

    -- Mini-map
    local map_size = 56
    local map_x = ctrl_x - 8
    local map_y = VIEW_Y + 145
    local cell = map_size / MAP_SIZE

    s:element({
        id = "minimap_bg",
        type = "panel",
        rect = { unit = "px", x = map_x - 2, y = map_y - 2, w = map_size + 4, h = map_size + 4 },
        style = { bg = "#333333" }
    })

    for my = 1, MAP_SIZE do
        for mx = 1, MAP_SIZE do
            local tile = map[my][mx]
            local col = "#000000"
            if tile == 1 then
                col = "#666666"
            elseif tile == 3 then
                col = "#00FF00"
            end
            s:element({
                id = "map_" .. mx .. "_" .. my,
                type = "panel",
                rect = { unit = "px", x = map_x + (mx - 1) * cell, y = map_y + (MAP_SIZE - my) * cell, w = cell, h = cell },
                style = { bg = col }
            })
        end
    end

    -- Player on minimap
    local px = map_x + (player.x - 1) * cell
    local py = map_y + (MAP_SIZE - player.y) * cell
    s:element({
        id = "player_dot",
        type = "panel",
        rect = { unit = "px", x = px - 2, y = py - 2, w = 4, h = 4 },
        style = { bg = "#00FFFF" }
    })

    -- Game over / win overlay
    if game_over then
        s:element({
            id = "gameover_txt",
            type = "label",
            rect = { unit = "px", x = 20, y = H / 2, w = W - 140, h = 30 },
            props = { text = "GAME OVER" },
            style = { font_size = 24, color = "#FF0000", align = "center" }
        })
    elseif game_won then
        s:element({
            id = "win_txt",
            type = "label",
            rect = { unit = "px", x = 20, y = H / 2, w = W - 140, h = 30 },
            props = { text = "YOU WIN!" },
            style = { font_size = 24, color = "#00FF00", align = "center" }
        })
    end

    s:commit()
    -- Canvas drawing is handled by on_frame callback (canvas created async)
end

-- Initialize
init_game()
render()

-- Warmup frames for canvas to be ready
local warmup = 5

-- Process input queue
local function process_input()
    local n = #inputq
    if n == 0 then return false end

    local did_action = false
    for i = 1, n do
        local a = inputq[i]
        if a == "forward" then
            move_player(1)
            did_action = true
        elseif a == "back" then
            move_player(-1)
            did_action = true
        elseif a == "turn_left" then
            turn_player(-1)
            did_action = true
        elseif a == "turn_right" then
            turn_player(1)
            did_action = true
        elseif a == "restart" then
            if game_over or game_won then
                init_game()
                did_action = true
            end
        end
    end

    for i = 1, n do
        inputq[i] = nil
    end

    return did_action
end

-- Tick function called by StationeersLua runtime with delta time
function tick(dt)
    if dt == nil then dt = 0.016 end

    local setting = read(DB, LT.Setting) or 0
    local did_action = false
    if setting >= 1 and setting <= 4 then
        if setting == 1 then
            move_player(1)
        elseif setting == 2 then
            move_player(-1)
        elseif setting == 3 then
            turn_player(-1)
        elseif setting == 4 then
            turn_player(1)
        end
        write(DB, LT.Setting, 0)
        did_action = true
    end

    -- Process keyboard input
    if process_input() then
        did_action = true
    end

    if did_action then
        render()
        dirty_canvas = true
    end

    -- Warmup ensures canvas is ready
    if warmup > 0 then
        warmup = warmup - 1
        dirty_canvas = true
    end

    -- Render canvas directly (like Tetris)
    if dirty_canvas then
        render_canvas()
        dirty_canvas = false
    end
end
