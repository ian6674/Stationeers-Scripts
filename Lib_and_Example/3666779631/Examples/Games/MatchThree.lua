-- Cosmic Match 3 - animated, on_frame state machine
--   IDLE → FLASH (matched gems shrink+whiten) → FALL (gems slide down, new fall from above) → CHECK → IDLE
--   Header includes interface_button → Interface Mode (keyboard); Alt exits.
--   Multiplayer: smoothest motion on the *client* - BepInEx ScriptedScreens `CanvasRemoteEveryBatchGpuUpload` = true (each network batch → GPU; default coalesces in-frame).

local ui = ss.ui.surface("main")
ss.ui.activate("main")
ui:clear()

-- ── Constants ──────────────────────────────────────────────────────────────────
local GRID       = 8
local NUM_TYPES  = 6
local FLASH_F    = 14   -- frames for pop-out effect  (~0.23 s @ 60 fps)
local FALL_F     = 22   -- frames for fall animation (~0.37 s)

local GEM_RGB = {
    { 225, 29,  72  }, -- red
    { 34,  197, 94  }, -- green
    { 59,  130, 246 }, -- blue
    { 234, 179, 8   }, -- yellow
    { 168, 85,  247 }, -- purple
    { 249, 115, 22  }, -- orange
}

local BG       = "#070B14"
local PANEL    = "#111827"
local ACCENT   = "#38BDF8"
local BOARD_BG = "#020617"
local BOTTOM_BAR = 76
local HEADER_IFACE_W = 102  -- room for interface_button on the right

-- Animation states
local IDLE  = "idle"
local FLASH = "flash"
local FALL  = "fall"
local CHECK = "check"

-- ── Layout vars (computed after ui:size()) ──────────────────────────────────
local size = ui:size()
local W, H = size.w, size.h

local board_cv  = "board_cv"
local x0, y0, board_px, cell, cell_font = 0, 0, 0, 0, 14

-- ── Game state ──────────────────────────────────────────────────────────────
local board       = {}
local score       = 0
local combo_chain = 0
local selected    = nil
local busy        = false

-- ── Animation state ─────────────────────────────────────────────────────────
local anim_state  = IDLE
local anim_frame  = 0
local flash_cells = {}   -- numeric keys: r*10+c → true
local fall_data   = {}   -- fall_data[c][i] = { t, from_r, to_r }

-- ── RNG (portable LCG) ──────────────────────────────────────────────────────
local rng = (W + H + 1337) % 2147483646 + 1
local function rnd(n)
    if n <= 1 then return 1 end
    rng = (rng * 48271) % 2147483647
    return (rng % n) + 1
end
local function random_type() return rnd(NUM_TYPES) end

-- ── Small helpers ────────────────────────────────────────────────────────────
local function px(x, y, w, h) return { unit = "px", x = x, y = y, w = w, h = h } end
local function cid(r, c) return "c_" .. r .. "_" .. c end

-- Canvas Y: 0 = canvas-bottom = screen-bottom; board_px = canvas-top = screen-top.
-- So higher cy → higher on screen; row 1 (top of grid) → cy near board_px.
local function cy_for(r) return board_px - (r - 1) * cell - cell / 2 end
local function rad() return math.max(5, math.floor(cell * 0.38)) end

-- ── Board helpers ────────────────────────────────────────────────────────────
local function safe_type_at(r, c)
    local bad = {}
    for g = 1, NUM_TYPES do bad[g] = false end
    local l1, l2 = board[r][c - 1], board[r][c - 2]
    if c >= 3 and l1 and l2 and l1 == l2 then bad[l1] = true end
    local u1 = board[r - 1] and board[r - 1][c]
    local u2 = board[r - 2] and board[r - 2][c]
    if r >= 3 and u1 and u2 and u1 == u2 then bad[u1] = true end
    local opts = {}
    for g = 1, NUM_TYPES do if not bad[g] then opts[#opts + 1] = g end end
    return #opts > 0 and opts[rnd(#opts)] or random_type()
end

local function collect_matches()
    local m = {}
    for r = 1, GRID do
        local c = 1
        while c <= GRID do
            local v = board[r][c]
            if not v or v == 0 then c = c + 1
            else
                local len = 1
                while c + len <= GRID and board[r][c + len] == v do len = len + 1 end
                if len >= 3 then for k = 0, len-1 do m[(r)*10+(c+k)] = true end end
                c = c + len
            end
        end
    end
    for c = 1, GRID do
        local r = 1
        while r <= GRID do
            local v = board[r][c]
            if not v or v == 0 then r = r + 1
            else
                local len = 1
                while r + len <= GRID and board[r + len][c] == v do len = len + 1 end
                if len >= 3 then for k = 0, len-1 do m[(r+k)*10+c] = true end end
                r = r + len
            end
        end
    end
    return m
end

local function mcount(mset) local n = 0; for _ in pairs(mset) do n = n+1 end; return n end

local function init_board()
    local tries = 0
    repeat
        tries = tries + 1
        for r = 1, GRID do
            board[r] = {}
            for c = 1, GRID do board[r][c] = safe_type_at(r, c) end
        end
    until mcount(collect_matches()) == 0 or tries > 30
    selected    = nil
    combo_chain = 0
end

-- ── Compute fall movement + update board ─────────────────────────────────────
-- After matched cells are zeroed, call this to build fall_data and update board
-- to its post-gravity state.  New gems start at from_r = 0 (just above row 1).
local function compute_fall()
    fall_data = {}
    for c = 1, GRID do
        fall_data[c] = {}
        local surviving = {}
        for r = 1, GRID do
            if board[r][c] ~= 0 then surviving[#surviving + 1] = { t = board[r][c], from_r = r } end
        end
        local new_count = GRID - #surviving
        for r = 1, GRID do board[r][c] = 0 end

        -- Surviving gems fall to the bottom (preserving order, top→bottom)
        for i = 1, #surviving do
            local to_r = new_count + i
            board[to_r][c] = surviving[i].t
            fall_data[c][#fall_data[c] + 1] = { t = surviving[i].t, from_r = surviving[i].from_r, to_r = to_r }
        end

        -- New gems: all start at from_r = 0 (one cell above the board top) and fall to rows 1..new_count
        for i = 1, new_count do
            local new_t = random_type()
            board[i][c]  = new_t
            fall_data[c][#fall_data[c] + 1] = { t = new_t, from_r = 0, to_r = i }
        end
    end
end

-- ── Canvas drawing ───────────────────────────────────────────────────────────
-- canvas_begin_update / canvas_end_update: one logical frame → one pending op group → one CanvasOpBatchV1
-- (when under max ops / size). Server skips min-sync throttle for a single multi-op group so MP animation
-- frames are not spaced by CanvasCommandMinSyncInterval. Requires matching ScriptedScreens on the server.

local function draw_gem(cx, cy, t, r)
    local rgb = GEM_RGB[t]
    if rgb then ui:canvas_fill_circle(board_cv, cx, cy, r, rgb[1], rgb[2], rgb[3], 255) end
end

-- Normal board state (idle / selection)
local function draw_idle()
    ui:canvas_begin_update(board_cv)
    ui:canvas_clear(board_cv, BOARD_BG)
    local r = rad()
    for row = 1, GRID do
        for col = 1, GRID do
            local t = board[row][col]
            if t and t ~= 0 then
                local cx = (col - 1) * cell + cell / 2
                local cy = cy_for(row)
                draw_gem(cx, cy, t, r)
                if selected and selected.r == row and selected.c == col then
                    ui:canvas_circle(board_cv, cx, cy, r + 3, 255, 255, 255, 255, 2)
                end
            end
        end
    end
    ui:canvas_end_update(board_cv)
    ui:canvas_apply(board_cv)
end

-- FLASH: matched gems shrink + whiten; others drawn normally
local function draw_flash()
    local t  = anim_frame / FLASH_F       -- 0→1
    local r0 = rad()
    ui:canvas_begin_update(board_cv)
    ui:canvas_clear(board_cv, BOARD_BG)
    for row = 1, GRID do
        for col = 1, GRID do
            local gt = board[row][col]
            if gt and gt ~= 0 then
                local cx = (col - 1) * cell + cell / 2
                local cy = cy_for(row)
                if flash_cells[row * 10 + col] then
                    -- Shrink and whiten toward white
                    local scale = math.max(0, 1 - t)
                    local fr = math.max(2, math.floor(r0 * scale))
                    local rgb = GEM_RGB[gt]
                    if rgb then
                        local wr = math.floor(rgb[1] + (255 - rgb[1]) * t)
                        local wg = math.floor(rgb[2] + (255 - rgb[2]) * t)
                        local wb = math.floor(rgb[3] + (255 - rgb[3]) * t)
                        ui:canvas_fill_circle(board_cv, cx, cy, fr, wr, wg, wb, 255)
                    end
                else
                    draw_gem(cx, cy, gt, r0)
                end
            end
        end
    end
    ui:canvas_end_update(board_cv)
    ui:canvas_apply(board_cv)
end

-- FALL: gems slide from from_r to to_r with ease-in (gravity feel)
local function draw_fall()
    local t  = anim_frame / FALL_F
    local et = t * t    -- ease-in: accelerates downward
    local r0 = rad()
    ui:canvas_begin_update(board_cv)
    ui:canvas_clear(board_cv, BOARD_BG)
    for col = 1, GRID do
        for _, gem in ipairs(fall_data[col]) do
            local from_cy = cy_for(gem.from_r)
            local to_cy   = cy_for(gem.to_r)
            local cy = from_cy + (to_cy - from_cy) * et
            -- Only draw if within canvas (new gems enter from above as they fall)
            if cy <= board_px + r0 then
                draw_gem((col - 1) * cell + cell / 2, cy, gem.t, r0)
            end
        end
    end
    ui:canvas_end_update(board_cv)
    ui:canvas_apply(board_cv)
end

-- ── Label / full redraw ──────────────────────────────────────────────────────
local function update_labels()
    local sc = ui:get("score_lbl")
    if sc then sc:set_props({ text = "<b>Score</b>  " .. tostring(score) }) end
    local hi = ui:get("hint_lbl")
    if hi then
        local txt
        if busy then
            if combo_chain > 1 then
                txt = "<color=#94A3B8>Cascade!  <color=#FDE047>x" ..
                      string.format("%.1f", 1 + (combo_chain - 1) * 0.5) .. " combo</color></color>"
            else
                txt = "<color=#94A3B8>Matching…</color>"
            end
        else
            txt = "<color=#64748B>INTERFACE = focus console · Alt exits · tap two adjacent gems to swap</color>"
        end
        hi:set_props({ text = txt })
    end
end

local function redraw_all()
    draw_idle()
    update_labels()
    ui:commit()
end

-- ── on_frame: full animation driver ─────────────────────────────────────────
ui:on_frame(function()
    if anim_state == IDLE then return end

    if anim_state == FLASH then
        draw_flash()
        ui:commit()
        anim_frame = anim_frame + 1
        if anim_frame >= FLASH_F then
            -- Zero out matched cells, then compute fall data + update board
            for key in pairs(flash_cells) do
                local r = math.floor(key / 10)
                local c = key - r * 10
                board[r][c] = 0
            end
            flash_cells = {}
            compute_fall()
            anim_state = FALL
            anim_frame = 0
        end

    elseif anim_state == FALL then
        draw_fall()
        ui:commit()
        anim_frame = anim_frame + 1
        if anim_frame >= FALL_F then
            anim_state = CHECK
            anim_frame = 0
        end

    elseif anim_state == CHECK then
        local mset = collect_matches()
        local n    = mcount(mset)
        if n > 0 then
            combo_chain = combo_chain + 1
            score       = score + math.floor(n * 12 * (1 + (combo_chain - 1) * 0.5))
            flash_cells = mset
            anim_state  = FLASH
            anim_frame  = 0
            update_labels()
            ui:commit()
        else
            anim_state  = IDLE
            busy        = false
            combo_chain = 0
            redraw_all()
        end
    end
end)

-- ── Input ────────────────────────────────────────────────────────────────────
local function swap_cells(r1, c1, r2, c2)
    board[r1][c1], board[r2][c2] = board[r2][c2], board[r1][c1]
end

local function try_swap(r1, c1, r2, c2)
    swap_cells(r1, c1, r2, c2)
    local mset = collect_matches()
    if mcount(mset) == 0 then
        swap_cells(r1, c1, r2, c2)
        selected = nil
        redraw_all()
        return
    end
    -- Valid match: score first wave, enter FLASH
    combo_chain = 1
    score       = score + math.floor(mcount(mset) * 12)
    selected    = nil
    busy        = true
    flash_cells = mset
    anim_state  = FLASH
    anim_frame  = 0
    update_labels()
    -- No canvas draw here; first on_frame will render the flash immediately.
    ui:commit()
end

local function handle_click(r, c)
    if busy then return end
    if not selected then
        selected = { r = r, c = c }
        redraw_all()
        return
    end
    local sr, sc = selected.r, selected.c
    if sr == r and sc == c then
        selected = nil
        redraw_all()
        return
    end
    if math.abs(sr - r) + math.abs(sc - c) ~= 1 then
        selected = { r = r, c = c }
        redraw_all()
        return
    end
    try_swap(sr, sc, r, c)
end

function on_new_game(_v, _pid)
    if busy then return end
    score      = 0
    anim_state = IDLE
    flash_cells = {}
    fall_data   = {}
    init_board()
    redraw_all()
end

-- ── Layout ───────────────────────────────────────────────────────────────────
ui:element({ id = "bg",     type = "panel", rect = px(0, 0, W, H),       style = { bg = BG } })
ui:element({ id = "header", type = "panel", rect = px(10, 6, W-20, 44),  style = { bg = PANEL, border_radius = 10 } })

local title_w = W - 20 - HEADER_IFACE_W
ui:element({ id = "title_lbl", type = "label", rect = px(10, 10, title_w, 22),
    props = { text = "<b><color=#E0F2FE>COSMIC MATCH</color></b>" },
    style = { align = "center", font_size = 18, color = "#F8FAFC" } })
ui:element({ id = "score_lbl", type = "label", rect = px(10, 30, title_w, 20),
    props = { text = "<b>Score</b>  0" },
    style = { align = "center", font_size = 14, color = ACCENT } })

ui:element({
    id = "iface_btn",
    type = "interface_button",
    rect = px(W - 10 - HEADER_IFACE_W, 9, HEADER_IFACE_W, 30),
    props = { text = "INTERFACE" },
    style = { bg = "#0F766E", text = "#CCFBF1", font_size = 10 },
})

local margin = 8
local top_y  = 56
local avail  = math.min(W - margin * 2, H - top_y - BOTTOM_BAR)
cell      = math.floor(avail / GRID)
board_px  = cell * GRID
x0        = math.floor((W - board_px) / 2)
y0        = top_y + math.floor((H - top_y - BOTTOM_BAR - board_px) / 2)
cell_font = math.max(8, math.floor(cell * 0.2))

ui:element({ id = "board_frame", type = "panel",
    rect  = px(x0 - 6, y0 - 6, board_px + 12, board_px + 12),
    style = { bg = "#000000", border_radius = 14 } })
ui:element({ id = board_cv, type = "canvas", rect = px(x0, y0, board_px, board_px) })

for r = 1, GRID do
    for c = 1, GRID do
        local rr, cc = r, c
        ui:element({
            id    = cid(r, c), type = "button",
            rect  = px(x0 + (c-1)*cell, y0 + (r-1)*cell, cell, cell),
            props = { text = " ", font_size = cell_font },
            style = { bg = "#00000000", text = "#00000000", border_radius = 8 },
            on_click = function(_v, _pid) handle_click(rr, cc) end,
        })
    end
end

ui:element({ id = "hint_lbl", type = "label", rect = px(12, H-66, W-24, 14),
    props = { text = "" }, style = { align = "center", font_size = 10, color = "#64748B" } })
ui:element({ id = "new_btn", type = "button", rect = px(28, H-48, W-56, 36),
    props = { text = "NEW GAME" },
    style = { bg = "#0284C7", text = "#F0F9FF", font_size = 14, border_radius = 10 },
    on_click = "on_new_game" })

init_board()
redraw_all()