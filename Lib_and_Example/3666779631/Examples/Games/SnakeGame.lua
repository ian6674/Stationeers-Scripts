-- Snake Game for ScriptedScreens (Canvas Version)
-- Controls: Click arrow buttons, keyboard (arrows/WASD), or Setting 1-4
-- Enter Interface Mode to use keyboard controls, press ALT to exit
--
-- Uses canvas rendering with on_frame for smooth 60fps gameplay.
-- Multiplayer: render_canvas groups draws with canvas_begin_update/canvas_end_update.

local LT = ic.enums.LogicType
local read = ic.read
local write = ic.write
local yield = ic.yield
local DB = ic.const.BASE_UNIT_INDEX

-- Some cartridge chips don't expose LogicType.Setting; guard reads so tick doesn't abort.
local function safe_read_setting()
    local ok, value = pcall(read, DB, LT.Setting)
    if not ok or value == nil then
        return 0
    end
    return value
end

local function safe_write_setting(value)
    pcall(write, DB, LT.Setting, value)
end

local s = ss.ui.surface("main")
ss.ui.activate("main")

local screen = s:size()
local W = screen.w
local H = screen.h

-- Layout constants
local HUD_H = 40
local CTRL_W = 85
local PAD = 4

-- Canvas and game board sizing
local availH = H - HUD_H - PAD * 2
local availW = W - CTRL_W - PAD * 3
local CELL = 8
local COLS = math.floor(availW / CELL)
local ROWS = math.floor(availH / CELL)
local CANVAS_W = COLS * CELL
local CANVAS_H = ROWS * CELL
local CANVAS_ID = "snake_canvas"

-- Direction constants
local DIR = { UP = 1, RIGHT = 2, DOWN = 3, LEFT = 4 }

-- Game state
local snake = {}
local food = { x = 0, y = 0 }
local direction = DIR.RIGHT
local next_direction = DIR.RIGHT
local score = 0
local high_score = 0
local game_over = false
local paused = false

-- Canvas state
local canvas_ready = false
local dirty_ui = true
local dirty_canvas = true

-- Keyboard input state
local held = {}
local inputq = {}

-- Spawn food at random location not on snake
local function spawn_food()
    -- Use simple approach: pick random grid cell
    food.x = math.random(0, COLS - 1)
    food.y = math.random(0, ROWS - 1)
    -- Ensure it's not on snake (just try a few times)
    for _ = 1, 50 do
        local on_snake = false
        for _, seg in ipairs(snake) do
            if seg.x == food.x and seg.y == food.y then
                on_snake = true
                break
            end
        end
        if not on_snake then break end
        food.x = math.random(0, COLS - 1)
        food.y = math.random(0, ROWS - 1)
    end
end

-- Initialize/reset game
local function init_game()
    snake = {}
    direction = DIR.RIGHT
    next_direction = DIR.RIGHT
    score = 0
    game_over = false
    paused = false

    -- Start snake in middle of field
    local start_x = math.floor(COLS / 2)
    local start_y = math.floor(ROWS / 2)
    for i = 0, 3 do
        snake[#snake + 1] = { x = start_x - i, y = start_y }
    end

    spawn_food()
end

-- Set direction (prevents 180-degree turns)
local function set_direction(d)
    if d == DIR.UP and direction ~= DIR.DOWN then
        next_direction = DIR.UP
    elseif d == DIR.DOWN and direction ~= DIR.UP then
        next_direction = DIR.DOWN
    elseif d == DIR.LEFT and direction ~= DIR.RIGHT then
        next_direction = DIR.LEFT
    elseif d == DIR.RIGHT and direction ~= DIR.LEFT then
        next_direction = DIR.RIGHT
    end
end

local function enqueue(action)
    inputq[#inputq + 1] = action
end

local function enqueue_key_action(key)
    if key == "UpArrow" or key == "W" then
        enqueue("up")
        return
    end
    if key == "DownArrow" or key == "S" then
        enqueue("down")
        return
    end
    if key == "LeftArrow" or key == "A" then
        enqueue("left")
        return
    end
    if key == "RightArrow" or key == "D" then
        enqueue("right")
        return
    end
    if key == "Space" then
        enqueue("action")
        return
    end
    if key == "P" or key == "Escape" then
        enqueue("pause")
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

-- Move snake one step
local function move_snake()
    if game_over or paused then return false end

    direction = next_direction

    local head = snake[1]
    local new_head = { x = head.x, y = head.y }

    if direction == DIR.UP then
        new_head.y = new_head.y + 1
    elseif direction == DIR.DOWN then
        new_head.y = new_head.y - 1
    elseif direction == DIR.LEFT then
        new_head.x = new_head.x - 1
    elseif direction == DIR.RIGHT then
        new_head.x = new_head.x + 1
    end

    -- Wall collision
    if new_head.x < 0 or new_head.x >= COLS or new_head.y < 0 or new_head.y >= ROWS then
        game_over = true
        if score > high_score then high_score = score end
        return true
    end

    -- Self collision
    for i = 1, #snake do
        if snake[i].x == new_head.x and snake[i].y == new_head.y then
            game_over = true
            if score > high_score then high_score = score end
            return true
        end
    end

    -- Add new head
    table.insert(snake, 1, new_head)

    -- Check food collision
    if new_head.x == food.x and new_head.y == food.y then
        score = score + 10
        spawn_food()
    else
        -- Remove tail if no food eaten
        table.remove(snake)
    end

    return true
end

-- Process input queue
local function process_input()
    local n = #inputq
    if n == 0 then return end

    for i = 1, n do
        local a = inputq[i]
        if a == "up" then
            set_direction(DIR.UP)
        elseif a == "down" then
            set_direction(DIR.DOWN)
        elseif a == "left" then
            set_direction(DIR.LEFT)
        elseif a == "right" then
            set_direction(DIR.RIGHT)
        elseif a == "pause" then
            if not game_over then
                paused = not paused
            end
        elseif a == "action" then
            if game_over then
                init_game()
            else
                paused = not paused
            end
        end
    end

    for i = 1, n do
        inputq[i] = nil
    end
end

-- Canvas rendering (called every frame at 60fps)
local function render_canvas()
    if not canvas_ready then return end

    s.canvas_begin_update(CANVAS_ID)
    -- Clear canvas with background
    s.canvas_rect(CANVAS_ID, 0, 0, CANVAS_W, CANVAS_H, 17, 17, 34)

    -- Draw food (red)
    local fx = food.x * CELL
    local fy = food.y * CELL
    s.canvas_rect(CANVAS_ID, fx + 1, fy + 1, CELL - 2, CELL - 2, 255, 51, 51)

    -- Draw snake
    for i, seg in ipairs(snake) do
        local sx = seg.x * CELL
        local sy = seg.y * CELL
        if i == 1 then
            -- Head (bright green)
            s.canvas_rect(CANVAS_ID, sx + 1, sy + 1, CELL - 2, CELL - 2, 0, 255, 136)
        else
            -- Body (darker green)
            s.canvas_rect(CANVAS_ID, sx + 1, sy + 1, CELL - 2, CELL - 2, 0, 204, 102)
        end
    end

    -- Draw game over / paused text in center
    if game_over then
        local cx = math.floor(CANVAS_W / 2) - 30
        local cy = math.floor(CANVAS_H / 2) - 5
        s.canvas_rect(CANVAS_ID, cx - 5, cy - 5, 70, 15, 26, 26, 46)
    elseif paused then
        local cx = math.floor(CANVAS_W / 2) - 25
        local cy = math.floor(CANVAS_H / 2) - 5
        s.canvas_rect(CANVAS_ID, cx - 5, cy - 5, 60, 15, 26, 26, 46)
    end

    s.canvas_end_update(CANVAS_ID)
    s.canvas_apply(CANVAS_ID)
end

-- Render UI elements (static parts)
local function render_ui()
    s:clear()

    -- Background
    s:element({
        id = "bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = H },
        style = { bg = "#0D0D1A" }
    })

    -- Header bar
    s:element({
        id = "header",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = HUD_H },
        style = { bg = "#1A1A2E" }
    })

    s:element({
        id = "title",
        type = "label",
        rect = { unit = "px", x = 10, y = 8, w = 70, h = 24 },
        props = { text = "SNAKE" },
        style = { font_size = 18, color = "#00FFAA", align = "left" }
    })

    s:element({
        id = "score_label",
        type = "label",
        rect = { unit = "px", x = 85, y = 8, w = 100, h = 24 },
        props = { text = "SCORE: " .. score },
        style = { font_size = 14, color = "#FFFFFF", align = "left" }
    })

    s:element({
        id = "high_label",
        type = "label",
        rect = { unit = "px", x = 190, y = 8, w = 100, h = 24 },
        props = { text = "HIGH: " .. high_score },
        style = { font_size = 14, color = "#888888", align = "left" }
    })

    -- Interface Mode button
    s:element({
        id = "interface_btn",
        type = "interface_button",
        rect = { unit = "px", x = 295, y = 10, w = 70, h = 20 },
        props = { text = "INTERFACE" },
        style = { bg = "#664400", text = "#FFCC00", font_size = 8 }
    })

    -- Canvas for game field
    s:element({
        id = CANVAS_ID,
        type = "canvas",
        rect = { unit = "px", x = PAD, y = HUD_H + PAD, w = CANVAS_W, h = CANVAS_H },
        props = { width = tostring(CANVAS_W), height = tostring(CANVAS_H) },
        style = { bg = "#111122" }
    })
    canvas_ready = true

    -- Control panel (right side)
    local ctrl_x = W - CTRL_W + 5
    local ctrl_y = HUD_H + 10
    local btn_size = 28

    s:element({
        id = "ctrl_bg",
        type = "panel",
        rect = { unit = "px", x = W - CTRL_W, y = HUD_H + PAD, w = CTRL_W - PAD, h = H - HUD_H - PAD * 2 },
        style = { bg = "#1A1A2E" }
    })

    s:element({
        id = "ctrl_label",
        type = "label",
        rect = { unit = "px", x = ctrl_x, y = ctrl_y, w = 70, h = 16 },
        props = { text = "CONTROLS" },
        style = { font_size = 9, color = "#666666", align = "center" }
    })

    -- Up button
    s:element({
        id = "btn_up",
        type = "button",
        rect = { unit = "px", x = ctrl_x + 20, y = ctrl_y - 35, w = btn_size, h = btn_size },
        props = { text = "▲" },
        style = { bg = "#333344", text = "#FFFFFF", font_size = 16 },
        on_click = function(playerName) set_direction(DIR.UP) end
    })

    -- Down button
    s:element({
        id = "btn_down",
        type = "button",
        rect = { unit = "px", x = ctrl_x + 20, y = ctrl_y - 95, w = btn_size, h = btn_size },
        props = { text = "▼" },
        style = { bg = "#333344", text = "#FFFFFF", font_size = 16 },
        on_click = function(playerName) set_direction(DIR.DOWN) end
    })

    -- Left button
    s:element({
        id = "btn_left",
        type = "button",
        rect = { unit = "px", x = ctrl_x - 10, y = ctrl_y - 65, w = btn_size, h = btn_size },
        props = { text = "◀" },
        style = { bg = "#333344", text = "#FFFFFF", font_size = 16 },
        on_click = function(playerName) set_direction(DIR.LEFT) end
    })

    -- Right button
    s:element({
        id = "btn_right",
        type = "button",
        rect = { unit = "px", x = ctrl_x + 50, y = ctrl_y - 65, w = btn_size, h = btn_size },
        props = { text = "▶" },
        style = { bg = "#333344", text = "#FFFFFF", font_size = 16 },
        on_click = function(playerName) set_direction(DIR.RIGHT) end
    })

    -- Pause/Resume or Restart button
    local action_text = game_over and "RESTART" or (paused and "RESUME" or "PAUSE")
    local action_color = game_over and "#006633" or "#333344"
    s:element({
        id = "btn_action",
        type = "button",
        rect = { unit = "px", x = ctrl_x - 5, y = ctrl_y - 140, w = 78, h = 30 },
        props = { text = action_text },
        style = { bg = action_color, text = "#FFFFFF", font_size = 11 },
        on_click = function(playerName)
            if game_over then
                init_game()
                render_ui()
            else
                paused = not paused
                render_ui()
            end
        end
    })

    -- Status text
    local status_text = game_over and "GAME OVER" or (paused and "PAUSED" or "")
    local status_color = game_over and "#FF3333" or "#FFCC00"
    if status_text ~= "" then
        s:element({
            id = "status_text",
            type = "label",
            rect = { unit = "px", x = ctrl_x - 5, y = ctrl_y - 175, w = 78, h = 20 },
            props = { text = status_text },
            style = { font_size = 12, color = status_color, align = "center" }
        })
    end

    -- Hint text
    s:element({
        id = "hint",
        type = "label",
        rect = { unit = "px", x = ctrl_x - 5, y = PAD + 10, w = 78, h = 30 },
        props = { text = "WASD/Arrows\nto move" },
        style = { font_size = 8, color = "#444444", align = "center" }
    })

    s:commit()
end

-- Initialize game
init_game()
render_ui()

-- Warmup frames for canvas to be ready
local warmup = 5

-- Game speed timing
local move_interval = 0.12 -- seconds between moves
local move_accum = 0

-- Tick function called by StationeersLua runtime with delta time
function tick(dt)
    if dt == nil then dt = 0.016 end

    -- Check for logic Setting input (1=Up, 2=Right, 3=Down, 4=Left)
    local setting = safe_read_setting()
    if setting >= 1 and setting <= 4 then
        set_direction(math.floor(setting))
        safe_write_setting(0)
        dirty_ui = true
        dirty_canvas = true
    end

    -- Process keyboard input
    process_input()

    -- Move snake at game speed
    if not game_over and not paused then
        move_accum = move_accum + dt
        if move_accum >= move_interval then
            move_accum = move_accum - move_interval
            move_snake()
            dirty_ui = true
            dirty_canvas = true
        end
    end

    -- Render UI when needed
    if dirty_ui then
        render_ui()
        dirty_ui = false
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
