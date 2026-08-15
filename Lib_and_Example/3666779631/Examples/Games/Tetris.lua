local LT = ic.enums.LogicType
local read = ic.read
local write = ic.write
local yield = ic.yield
local DB = ic.const.BASE_UNIT_INDEX

-- Some cartridge chips don't expose LogicType.Setting; guard reads so on_frame doesn't abort.
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
-- Multiplayer: draw_board / draw_preview use canvas_begin_update + canvas_end_update per paint.

local screen = s:size()
local W = screen.w
local H = screen.h

local BOARD_W = 10
local BOARD_H = 20

-- Layout constants
local HUD_H = 28
local PAD = 4
local CTRL_W = 100 -- width reserved for controls on right

-- Board fills most of the screen height, controls on right
local availH = H - HUD_H - PAD * 2
local availW = W - CTRL_W - PAD * 3
local CELL = math.floor(math.min(availW / BOARD_W, availH / BOARD_H))
if CELL < 4 then CELL = 4 end

local boardDispW = CELL * BOARD_W
local boardDispH = CELL * BOARD_H

local boardX = PAD
local boardY = PAD

-- Right panel (controls + info) fills remaining space
local rightX = boardX + boardDispW + PAD
local rightW = W - rightX - PAD

-- Canvas resolution matches display for crisp pixels
local CANVAS_W = boardDispW
local CANVAS_H = boardDispH
local CANVAS_ID = "tetris_board"

-- Preview canvases (smaller)
local PREV_CELL = 6
local PREV_SIZE = 4 * PREV_CELL
local NEXT_ID = "tetris_next"
local HOLD_ID = "tetris_hold"

local COLORS = {
    I = { 0, 220, 220 },
    O = { 220, 220, 0 },
    T = { 160, 0, 220 },
    S = { 0, 220, 0 },
    Z = { 220, 0, 0 },
    J = { 0, 80, 220 },
    L = { 220, 140, 0 },
    G = { 90, 90, 90 },
    W = { 210, 210, 210 },
}

local PIECES = {
    I = {
        { { 0, 1 }, { 1, 1 }, { 2, 1 }, { 3, 1 } },
        { { 2, 0 }, { 2, 1 }, { 2, 2 }, { 2, 3 } },
        { { 0, 2 }, { 1, 2 }, { 2, 2 }, { 3, 2 } },
        { { 1, 0 }, { 1, 1 }, { 1, 2 }, { 1, 3 } },
    },
    O = {
        { { 1, 1 }, { 2, 1 }, { 1, 2 }, { 2, 2 } },
        { { 1, 1 }, { 2, 1 }, { 1, 2 }, { 2, 2 } },
        { { 1, 1 }, { 2, 1 }, { 1, 2 }, { 2, 2 } },
        { { 1, 1 }, { 2, 1 }, { 1, 2 }, { 2, 2 } },
    },
    T = {
        { { 1, 1 }, { 0, 2 }, { 1, 2 }, { 2, 2 } },
        { { 1, 1 }, { 1, 2 }, { 2, 2 }, { 1, 3 } },
        { { 0, 2 }, { 1, 2 }, { 2, 2 }, { 1, 3 } },
        { { 1, 1 }, { 0, 2 }, { 1, 2 }, { 1, 3 } },
    },
    S = {
        { { 1, 1 }, { 2, 1 }, { 0, 2 }, { 1, 2 } },
        { { 1, 1 }, { 1, 2 }, { 2, 2 }, { 2, 3 } },
        { { 1, 2 }, { 2, 2 }, { 0, 3 }, { 1, 3 } },
        { { 0, 1 }, { 0, 2 }, { 1, 2 }, { 1, 3 } },
    },
    Z = {
        { { 0, 1 }, { 1, 1 }, { 1, 2 }, { 2, 2 } },
        { { 2, 1 }, { 1, 2 }, { 2, 2 }, { 1, 3 } },
        { { 0, 2 }, { 1, 2 }, { 1, 3 }, { 2, 3 } },
        { { 1, 1 }, { 0, 2 }, { 1, 2 }, { 0, 3 } },
    },
    J = {
        { { 0, 1 }, { 0, 2 }, { 1, 2 }, { 2, 2 } },
        { { 1, 1 }, { 2, 1 }, { 1, 2 }, { 1, 3 } },
        { { 0, 2 }, { 1, 2 }, { 2, 2 }, { 2, 3 } },
        { { 1, 1 }, { 1, 2 }, { 0, 3 }, { 1, 3 } },
    },
    L = {
        { { 2, 1 }, { 0, 2 }, { 1, 2 }, { 2, 2 } },
        { { 1, 1 }, { 1, 2 }, { 1, 3 }, { 2, 3 } },
        { { 0, 2 }, { 1, 2 }, { 2, 2 }, { 0, 3 } },
        { { 0, 1 }, { 1, 1 }, { 1, 2 }, { 1, 3 } },
    },
}

local function new_grid()
    local g = {}
    for y = 1, BOARD_H do
        g[y] = {}
        for x = 1, BOARD_W do
            g[y][x] = nil
        end
    end
    return g
end

local grid = new_grid()

local bag = {}
local nextq = {}

local hold = nil
local hold_used = false

local piece = nil
local paused = false
local game_over = false

local score = 0
local lines = 0
local level = 0

local drop_accum = 0
local dirty_ui = true
local dirty_canvas = true

local inputq = {}
local enqueue

local held = {}
local function set_held(key, v)
    held[key] = v and true or false
end

local function normalize_key(key)
    if key == nil then
        return nil
    end
    if #key == 1 then
        return string.upper(key)
    end
    return key
end

local DAS = 0.15
local ARR = 0.045
local SD_ARR = 0.03

local dir = 0
local dir_hold = 0
local dir_rep = 0
local sd_hold = 0

local function is_left_held()
    return held["LeftArrow"] or held["A"]
end

local function is_right_held()
    return held["RightArrow"] or held["D"]
end

local function is_down_held()
    return held["DownArrow"] or held["S"]
end

local function set_dir(new_dir)
    if dir == new_dir then
        return
    end
    dir = new_dir
    dir_hold = 0
    dir_rep = 0
    if dir == -1 then
        enqueue("left")
    elseif dir == 1 then
        enqueue("right")
    end
end

local function enqueue_key_action(key)
    key = normalize_key(key)
    if key == nil then
        return
    end
    if key == "LeftArrow" or key == "A" then
        set_dir(-1)
        return
    end
    if key == "RightArrow" or key == "D" then
        set_dir(1)
        return
    end
    if key == "UpArrow" or key == "W" or key == "X" then
        enqueue("rot")
        return
    end
    if key == "Z" then
        enqueue("rot_ccw")
        return
    end
    if key == "DownArrow" or key == "S" then
        sd_hold = 0
        enqueue("down")
        return
    end

    if key == "Space" then
        enqueue("drop")
        return
    end
    if key == "C" then
        enqueue("hold")
        return
    end
    if key == "LeftShift" or key == "RightShift" then
        enqueue("hold")
        return
    end
    if key == "P" then
        enqueue("pause")
        return
    end
    if key == "R" then
        enqueue("reset")
        return
    end
end

local function handle_keydown(key)
    key = normalize_key(key)
    if key == nil then return end
    if held[key] then return end
    set_held(key, true)
    enqueue_key_action(key)
end

local function handle_keyup(key)
    key = normalize_key(key)
    if key == nil then return end
    set_held(key, false)

    if key == "LeftArrow" or key == "A" or key == "RightArrow" or key == "D" then
        if is_left_held() and not is_right_held() then
            set_dir(-1)
        elseif is_right_held() and not is_left_held() then
            set_dir(1)
        else
            set_dir(0)
        end
    end
end

local ALL_PIECES = { "I", "O", "T", "S", "Z", "J", "L" }

local function refill_bag()
    bag = {}
    for i = 1, #ALL_PIECES do
        bag[i] = ALL_PIECES[i]
    end
end

local function pop_bag()
    if #bag == 0 then
        refill_bag()
    end
    -- Pick a random piece from remaining bag
    -- Use math.random() * n + floor to get integer in [1, n]
    local idx = math.floor(math.random() * #bag) + 1
    local v = bag[idx]
    -- Remove it by swapping with last and popping
    bag[idx] = bag[#bag]
    bag[#bag] = nil
    return v
end

local function ensure_next(n)
    while #nextq < n do
        nextq[#nextq + 1] = pop_bag()
    end
end

local function dequeue_next()
    ensure_next(5)
    local t = nextq[1]
    table.remove(nextq, 1)
    ensure_next(5)
    return t
end

enqueue = function(action)
    inputq[#inputq + 1] = action
end

local function cell_filled(x, y)
    if x < 0 or x >= BOARD_W then
        return true
    end
    if y < 0 then
        return true
    end
    if y >= BOARD_H then
        return false
    end
    return grid[y + 1][x + 1] ~= nil
end

local function piece_cells(ptype, rot)
    local r = ((rot % 4) + 4) % 4 + 1
    return PIECES[ptype][r]
end

local function can_place(p)
    local cells = piece_cells(p.t, p.r)
    for i = 1, 4 do
        local cx = p.x + cells[i][1]
        local cy = p.y + cells[i][2]
        if cell_filled(cx, cy) then
            return false
        end
    end
    return true
end

local function spawn_piece(t)
    piece = { t = t, r = 0, x = 3, y = BOARD_H }
    hold_used = false
    if not can_place(piece) then
        game_over = true
    end
end

local function reset_game()
    grid = new_grid()
    bag = {}
    nextq = {}
    hold = nil
    hold_used = false
    score = 0
    lines = 0
    level = 0
    drop_accum = 0
    paused = false
    game_over = false
    refill_bag()
    ensure_next(5)
    spawn_piece(dequeue_next())
    dirty_ui = true
    dirty_canvas = true
end

local function lock_piece()
    local cells = piece_cells(piece.t, piece.r)
    for i = 1, 4 do
        local cx = piece.x + cells[i][1]
        local cy = piece.y + cells[i][2]
        if cy >= BOARD_H then
            game_over = true
            return
        end
        if cy >= 0 and cy < BOARD_H then
            grid[cy + 1][cx + 1] = piece.t
        end
    end

    local cleared = 0
    local y = 1
    while y <= BOARD_H do
        local full = true
        for x = 1, BOARD_W do
            if grid[y][x] == nil then
                full = false
                break
            end
        end
        if full then
            cleared = cleared + 1
            for yy = y, BOARD_H - 1 do
                grid[yy] = grid[yy + 1]
            end
            grid[BOARD_H] = {}
            for x = 1, BOARD_W do
                grid[BOARD_H][x] = nil
            end
        else
            y = y + 1
        end
    end

    if cleared > 0 then
        lines = lines + cleared
        local add
        if cleared == 1 then
            add = 100
        elseif cleared == 2 then
            add = 300
        elseif cleared == 3 then
            add = 500
        else
            add = 800
        end
        score = score + add * (level + 1)
        level = math.floor(lines / 10)
    end

    spawn_piece(dequeue_next())
end

local function try_move(dx, dy)
    local np = { t = piece.t, r = piece.r, x = piece.x + dx, y = piece.y + dy }
    if can_place(np) then
        piece.x = np.x
        piece.y = np.y
        return true
    end
    return false
end

local function try_rotate(dir)
    local nr = piece.r + dir
    local kicks
    if piece.t == "I" then
        kicks = { 0, 1, -1, 2, -2 }
    else
        kicks = { 0, 1, -1, 2, -2 }
    end
    for i = 1, #kicks do
        local dx = kicks[i]
        local np = { t = piece.t, r = nr, x = piece.x + dx, y = piece.y }
        if can_place(np) then
            piece.r = nr
            piece.x = np.x
            return true
        end
    end
    return false
end

local function hard_drop()
    local d = 0
    while try_move(0, -1) do
        d = d + 1
    end
    score = score + d * 2
    lock_piece()
end

local function hold_swap()
    if hold_used then return end
    hold_used = true
    if hold == nil then
        hold = piece.t
        spawn_piece(dequeue_next())
    else
        local tmp = hold
        hold = piece.t
        spawn_piece(tmp)
    end
end

local function drop_interval()
    local base = 0.8 - (level * 0.06)
    if base < 0.08 then base = 0.08 end
    return base
end

local function draw_block(canvasId, x, y, cell, r, g, b)
    local px = x * cell
    local py = y * cell
    local cw = cell
    local ch = cell
    s.canvas_rect(canvasId, px, py, cw, ch, r, g, b)
end

local function draw_board()
    s.canvas_begin_update(CANVAS_ID)
    s.canvas_clear(CANVAS_ID, 10, 10, 14)

    for y = 0, BOARD_H - 1 do
        for x = 0, BOARD_W - 1 do
            local t = grid[y + 1][x + 1]
            if t ~= nil then
                local c = COLORS[t]
                draw_block(CANVAS_ID, x, y, CELL, c[1], c[2], c[3])
            end
        end
    end

    if not game_over and piece ~= nil then
        local ghost = { t = piece.t, r = piece.r, x = piece.x, y = piece.y }
        while can_place({ t = ghost.t, r = ghost.r, x = ghost.x, y = ghost.y - 1 }) do
            ghost.y = ghost.y - 1
        end
        local cells = piece_cells(ghost.t, ghost.r)
        local gc = COLORS.G
        for i = 1, 4 do
            local cx = ghost.x + cells[i][1]
            local cy = ghost.y + cells[i][2]
            if cy >= 0 and cy < BOARD_H then
                draw_block(CANVAS_ID, cx, cy, CELL, gc[1], gc[2], gc[3])
            end
        end

        local cells2 = piece_cells(piece.t, piece.r)
        local c = COLORS[piece.t]
        for i = 1, 4 do
            local cx = piece.x + cells2[i][1]
            local cy = piece.y + cells2[i][2]
            if cy >= 0 and cy < BOARD_H then
                draw_block(CANVAS_ID, cx, cy, CELL, c[1], c[2], c[3])
            end
        end
    end

    s.canvas_end_update(CANVAS_ID)
    s.canvas_apply(CANVAS_ID)
end

local function draw_preview(canvasId, t)
    s.canvas_begin_update(canvasId)
    s.canvas_clear(canvasId, 10, 10, 14)
    if t == nil then
        s.canvas_end_update(canvasId)
        s.canvas_apply(canvasId)
        return
    end
    local c = COLORS[t]
    local cells = piece_cells(t, 0)
    for i = 1, 4 do
        local cx = cells[i][1]
        local cy = cells[i][2]
        draw_block(canvasId, cx, cy, PREV_CELL, c[1], c[2], c[3])
    end
    s.canvas_end_update(canvasId)
    s.canvas_apply(canvasId)
end

local function render_ui()
    s:clear()

    -- Background
    s:element({
        id = "bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = H },
        style = { bg = "#0A0A12" }
    })

    -- Board border
    s:element({
        id = "board_border",
        type = "panel",
        rect = { unit = "px", x = boardX - 2, y = boardY - 2, w = boardDispW + 4, h = boardDispH + 4 },
        style = { bg = "#2A2A3C" }
    })

    -- Board canvas
    s:element({
        id = CANVAS_ID,
        type = "canvas",
        rect = { unit = "px", x = boardX, y = boardY, w = boardDispW, h = boardDispH },
        props = { width = tostring(CANVAS_W), height = tostring(CANVAS_H) },
        style = { bg = "#000000" }
    })

    -- Right panel background
    s:element({
        id = "right_bg",
        type = "panel",
        rect = { unit = "px", x = rightX, y = boardY, w = rightW, h = boardDispH },
        style = { bg = "#12121C" }
    })

    -- Layout right panel from top to bottom
    local rpad = 4
    local curY = boardY + boardDispH - rpad -- start from top

    -- NEXT preview (at top)
    curY = curY - 14
    s:element({
        id = "next_lbl",
        type = "label",
        rect = { unit = "px", x = rightX, y = curY, w = rightW, h = 14 },
        props = { text = "NEXT" },
        style = { font_size = 10, color = "#888899", align = "center" }
    })
    curY = curY - PREV_SIZE - 2
    s:element({
        id = NEXT_ID,
        type = "canvas",
        rect = { unit = "px", x = rightX + math.floor((rightW - PREV_SIZE) / 2), y = curY, w = PREV_SIZE, h = PREV_SIZE },
        props = { width = tostring(PREV_SIZE), height = tostring(PREV_SIZE) },
        style = { bg = "#0A0A10" }
    })

    -- HOLD preview
    curY = curY - 16
    s:element({
        id = "hold_lbl",
        type = "label",
        rect = { unit = "px", x = rightX, y = curY, w = rightW, h = 14 },
        props = { text = "HOLD" },
        style = { font_size = 10, color = "#888899", align = "center" }
    })
    curY = curY - PREV_SIZE - 2
    s:element({
        id = HOLD_ID,
        type = "canvas",
        rect = { unit = "px", x = rightX + math.floor((rightW - PREV_SIZE) / 2), y = curY, w = PREV_SIZE, h = PREV_SIZE },
        props = { width = tostring(PREV_SIZE), height = tostring(PREV_SIZE) },
        style = { bg = "#0A0A10" }
    })

    -- Stats
    curY = curY - 20
    s:element({
        id = "score_lbl",
        type = "label",
        rect = { unit = "px", x = rightX, y = curY, w = rightW, h = 12 },
        props = { text = "SCORE" },
        style = { font_size = 9, color = "#666677", align = "center" }
    })
    curY = curY - 16
    s:element({
        id = "score_val",
        type = "label",
        rect = { unit = "px", x = rightX, y = curY, w = rightW, h = 16 },
        props = { text = tostring(score) },
        style = { font_size = 14, color = "#FFFFFF", align = "center" }
    })
    curY = curY - 14
    s:element({
        id = "level_lbl",
        type = "label",
        rect = { unit = "px", x = rightX, y = curY, w = rightW / 2, h = 12 },
        props = { text = "LVL" },
        style = { font_size = 9, color = "#666677", align = "center" }
    })
    s:element({
        id = "lines_lbl",
        type = "label",
        rect = { unit = "px", x = rightX + rightW / 2, y = curY, w = rightW / 2, h = 12 },
        props = { text = "LINES" },
        style = { font_size = 9, color = "#666677", align = "center" }
    })
    curY = curY - 14
    s:element({
        id = "level_val",
        type = "label",
        rect = { unit = "px", x = rightX, y = curY, w = rightW / 2, h = 14 },
        props = { text = tostring(level) },
        style = { font_size = 12, color = "#00CCFF", align = "center" }
    })
    s:element({
        id = "lines_val",
        type = "label",
        rect = { unit = "px", x = rightX + rightW / 2, y = curY, w = rightW / 2, h = 14 },
        props = { text = tostring(lines) },
        style = { font_size = 12, color = "#00FF88", align = "center" }
    })

    -- Controls at bottom of right panel
    local btnW = math.floor((rightW - rpad * 3) / 2)
    local btnH = 24
    local gap = 3

    local function btn(id, x, y, w, h, text, fn, color)
        s:element({
            id = id,
            type = "button",
            rect = { unit = "px", x = x, y = y, w = w, h = h },
            props = { text = text },
            style = { bg = color or "#2A2A3C", text = "#FFFFFF", font_size = 9 },
            on_click = fn
        })
    end

    local ctrlY = boardY + rpad

    -- Row 1: LEFT / RIGHT
    btn("b_left", rightX + rpad, ctrlY, btnW, btnH, "< LEFT", function() enqueue("left") end)
    btn("b_right", rightX + rpad + btnW + gap, ctrlY, btnW, btnH, "RIGHT >", function() enqueue("right") end)

    -- Row 2: ROT / DOWN
    ctrlY = ctrlY + btnH + gap
    btn("b_rot", rightX + rpad, ctrlY, btnW, btnH, "ROTATE", function() enqueue("rot") end, "#3C3A5C")
    btn("b_down", rightX + rpad + btnW + gap, ctrlY, btnW, btnH, "DOWN", function() enqueue("down") end)

    -- Row 3: DROP / HOLD
    ctrlY = ctrlY + btnH + gap
    btn("b_drop", rightX + rpad, ctrlY, btnW, btnH, "DROP", function() enqueue("drop") end, "#2A3A4C")
    btn("b_hold", rightX + rpad + btnW + gap, ctrlY, btnW, btnH, "HOLD", function() enqueue("hold") end, "#2A4C3A")

    -- Row 4: PAUSE / RESET
    ctrlY = ctrlY + btnH + gap
    btn("b_pause", rightX + rpad, ctrlY, btnW, btnH, "PAUSE", function() enqueue("pause") end, "#3A2A4C")
    btn("b_reset", rightX + rpad + btnW + gap, ctrlY, btnW, btnH, "RESET", function() enqueue("reset") end, "#4C2A2A")

    -- HUD bar at bottom
    s:element({
        id = "hud",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = HUD_H },
        style = { bg = "#151520" }
    })

    s:element({
        id = "interface_btn",
        type = "interface_button",
        rect = { unit = "px", x = W - 90, y = 6, w = 70, h = 16 },
        props = { text = "INTERFACE" },
        style = { bg = "#664400", text = "#FFCC00", font_size = 8 }
    })

    local status = game_over and "GAME OVER" or (paused and "PAUSED" or "TETRIS")
    local statusColor = game_over and "#FF4444" or (paused and "#FFCC00" or "#FFFFFF")
    s:element({
        id = "status",
        type = "label",
        rect = { unit = "px", x = PAD, y = 6, w = W - PAD * 2, h = 16 },
        props = { text = status },
        style = { font_size = 13, color = statusColor, align = "center" }
    })

    s:commit()

    ensure_next(1)
    draw_preview(HOLD_ID, hold)
    draw_preview(NEXT_ID, nextq[1])
end

local function process_action(a)
    if a == "reset" then
        reset_game()
        return
    end

    if game_over then
        return
    end

    if a == "pause" then
        paused = not paused
        dirty_ui = true
        return
    end

    if paused then
        return
    end

    if a == "left" then
        if try_move(-1, 0) then
            dirty_ui = true; dirty_canvas = true
        end
        return
    end

    if a == "right" then
        if try_move(1, 0) then
            dirty_ui = true; dirty_canvas = true
        end
        return
    end

    if a == "down" then
        if try_move(0, -1) then
            score = score + 1
            dirty_ui = true; dirty_canvas = true
        else
            lock_piece()
            dirty_ui = true; dirty_canvas = true
        end
        return
    end

    if a == "rot" then
        if try_rotate(1) then
            dirty_ui = true; dirty_canvas = true
        end
        return
    end

    if a == "rot_ccw" then
        if try_rotate(-1) then
            dirty_ui = true; dirty_canvas = true
        end
        return
    end

    if a == "drop" then
        hard_drop()
        dirty_ui = true; dirty_canvas = true
        return
    end

    if a == "hold" then
        hold_swap()
        dirty_ui = true; dirty_canvas = true
        return
    end
end

reset_game()
render_ui()

local warmup = 10
-- os.clock is CPU time and runs slower on multiplayer servers; use game time instead.
local last_clock = util.game_time()

-- on_frame runs every Unity frame (~60fps) for smooth rendering and input
local function game_frame()
    local now = util.game_time()
    local dt = now - last_clock
    last_clock = now

    -- Clamp dt to avoid huge jumps (e.g. after pause/load)
    if dt < 0 then dt = 0 end
    if dt > 0.1 then dt = 0.1 end

    -- Read Setting input from the game world (moved from tick to avoid concurrent state usage)
    local setting = safe_read_setting()
    if setting ~= 0 then
        if setting == 1 then
            enqueue("left")
        elseif setting == 2 then
            enqueue("right")
        elseif setting == 3 then
            enqueue("rot")
        elseif setting == 4 then
            enqueue("down")
        elseif setting == 5 then
            enqueue("drop")
        elseif setting == 6 then
            enqueue("hold")
        elseif setting == 7 then
            enqueue("pause")
        elseif setting == 8 then
            enqueue("reset")
        end
        safe_write_setting(0)
    end

    -- Frame-level input events (keydown/keyup) for smooth on_frame behavior
    local events = s:poll_input()
    for i = 1, #events do
        local ev = events[i]
        local name = string.lower(ev.event or "")
        if name == "keydown" then
            handle_keydown(ev.value)
        elseif name == "keyup" then
            handle_keyup(ev.value)
        end
    end

    -- Auto-repeat disabled: key events arrive on game tick and were causing jumpy bursts.
    -- Movement now happens only on discrete keydown events.

    -- Process input queue
    local n = #inputq
    if n > 0 then
        for i = 1, n do
            process_action(inputq[i])
        end
        inputq = {}
    end

    -- Gravity
    if not paused and not game_over then
        drop_accum = drop_accum + dt
        local interval = drop_interval()
        if drop_accum >= interval then
            drop_accum = drop_accum - interval
            if not try_move(0, -1) then
                lock_piece()
            end
            dirty_ui = true
            dirty_canvas = true
        end
    end

    -- Render UI when needed (labels, score, etc.)
    if dirty_ui then
        render_ui()
        dirty_ui = false
    end

    if warmup > 0 then
        dirty_canvas = true
        warmup = warmup - 1
    end

    -- Render canvas when needed (board, previews)
    if dirty_canvas then
        draw_board()
        ensure_next(1)
        draw_preview(HOLD_ID, hold)
        draw_preview(NEXT_ID, nextq[1])
        dirty_canvas = false
    end
end

-- Register on_frame for smooth ~60fps game loop
s:on_frame(game_frame)
