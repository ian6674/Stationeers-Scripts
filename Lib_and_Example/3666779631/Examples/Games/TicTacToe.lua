local LT = ic.enums.LogicType
local read = ic.read
local write = ic.write
local DB = ic.const.BASE_UNIT_INDEX

local s = ss.ui.surface("main")
ss.ui.activate("main")

local W, H = 1, 1
local minDim = 1
local HUD_H, PAD, GAP, CELL, BOARD_PX
local boardX, boardY, rightX, rightW
local font_cell, font_status, font_title, font_hud, font_help, btnH, ifaceW, ifaceH

local lastSurfW, lastSurfH

local COL = {
    bg = "#03010A",
    bg_lift = "#0B0620",
    vignette = "#010008",
    hud = "#08051A",
    hud_glow = "#12082E",
    hud_line_c = "#22D3EE",
    hud_line_m = "#E879F9",
    neon_cyan = "#22D3EE",
    neon_cyan_dim = "#0E7490",
    neon_magenta = "#F472B6",
    neon_magenta_dim = "#BE185D",
    violet = "#A78BFA",
    violet_dim = "#5B21B6",
    board_halo = "#134E4A",
    board_rim = "#164E63",
    board_well = "#040912",
    grid_mist = "#1E293B",
    cell = "#0C1220",
    cell_edge = "#1E293B",
    cell_fill_x = "#0F172A",
    cell_fill_o = "#1A0F1A",
    win = "#422006",
    win_glow = "#FBBF24",
    panel = "#0A0614",
    panel_shine = "#150B28",
    chip_line = "#F472B6",
    text = "#F8FAFC",
    muted = "#94A3B8",
    dim = "#64748B",
    x_hi = "#67E8F9",
    o_hi = "#FBCFE8",
    btn_top = "#7C3AED",
    btn_bot = "#4C1D95",
    btn_text = "#FAF5FF",
    iface_bg = "#1C1004",
    iface_text = "#FDE68A",
}

local function tmp_plain(s)
    if s == nil then
        return ""
    end
    s = tostring(s)
    s = string.gsub(s, "<", "")
    s = string.gsub(s, ">", "")
    return s
end

local function host_display_name()
    local ok, info = pcall(ic.host_info)
    if not ok or type(info) ~= "table" then
        return "Console"
    end
    local n = info.name
    if type(n) == "string" and n ~= "" then
        return tmp_plain(n)
    end
    return "Console"
end

local function compute_layout()
    local screen = s:size()
    W = math.max(1, math.floor(screen.w + 0.5))
    H = math.max(1, math.floor(screen.h + 0.5))
    minDim = math.min(W, H)

    HUD_H = math.max(26, math.min(44, math.floor(minDim * 0.076)))
    PAD = math.max(4, math.floor(minDim * 0.016))
    local contentTop = HUD_H + PAD
    local usableW = W - PAD * 2
    local usableH = H - contentTop - PAD
    if usableH < 48 then
        usableH = math.max(48, H - HUD_H - PAD)
        contentTop = math.max(HUD_H, H - usableH - PAD)
    end

    rightW = math.max(58, math.min(math.floor(W * 0.29), math.floor(minDim * 0.32)))
    local midGap = math.max(PAD, math.floor(minDim * 0.022))
    local maxBoardW = usableW - rightW - midGap
    local maxBoardH = usableH
    if maxBoardW < 78 then
        rightW = math.max(48, usableW - 78 - midGap)
        maxBoardW = usableW - rightW - midGap
    end

    BOARD_PX = math.floor(math.min(math.max(maxBoardW, 0), math.max(maxBoardH, 0)))
    GAP = math.max(3, math.floor(BOARD_PX * 0.02))
    CELL = math.max(10, math.floor((BOARD_PX - GAP * 2) / 3))
    BOARD_PX = CELL * 3 + GAP * 2

    local groupW = BOARD_PX + midGap + rightW
    local groupX = PAD + math.max(0, math.floor((usableW - groupW) / 2))
    boardX = groupX
    boardY = contentTop + math.max(0, math.floor((usableH - BOARD_PX) / 2))
    rightX = boardX + BOARD_PX + midGap

    font_cell = math.max(15, math.min(118, math.floor(CELL * 0.5)))
    font_status = math.max(10, math.min(24, math.floor(minDim * 0.034)))
    font_title = math.max(9, math.min(14, math.floor(minDim * 0.026)))
    font_hud = math.max(8, math.min(16, math.floor(minDim * 0.027)))
    font_help = math.max(6, math.min(10, math.floor(minDim * 0.017)))
    btnH = math.max(22, math.min(36, math.floor(minDim * 0.06)))
    ifaceW = math.max(54, math.min(82, math.floor(W * 0.175)))
    ifaceH = math.max(14, math.min(21, math.floor(HUD_H * 0.52)))
end

local board = { 0, 0, 0, 0, 0, 0, 0, 0, 0 }
local current = 1
local winner = 0
local win_line = nil

local dirty_ui = true

local LINES = {
    { 1, 2, 3 }, { 4, 5, 6 }, { 7, 8, 9 },
    { 1, 4, 7 }, { 2, 5, 8 }, { 3, 6, 9 },
    { 1, 5, 9 }, { 3, 5, 7 },
}

local function check_result()
    for i = 1, #LINES do
        local a, b, c = LINES[i][1], LINES[i][2], LINES[i][3]
        local v = board[a]
        if v ~= 0 and v == board[b] and v == board[c] then
            winner = v
            win_line = { a, b, c }
            return
        end
    end
    local full = true
    for i = 1, 9 do
        if board[i] == 0 then
            full = false
            break
        end
    end
    if full then
        winner = 3
    end
end

local function reset_game()
    for i = 1, 9 do
        board[i] = 0
    end
    current = 1
    winner = 0
    win_line = nil
    dirty_ui = true
end

local function place_at(idx)
    if winner ~= 0 or board[idx] ~= 0 then
        return
    end
    board[idx] = current
    check_result()
    if winner == 0 then
        current = (current == 1) and 2 or 1
    end
    dirty_ui = true
end

local function cell_bezel(idx)
    if win_line then
        for j = 1, 3 do
            if win_line[j] == idx then
                return COL.win_glow
            end
        end
    end
    return COL.cell_edge
end

local function cell_bg(idx)
    if win_line then
        for j = 1, 3 do
            if win_line[j] == idx then
                return COL.win
            end
        end
    end
    local v = board[idx]
    if v == 1 then
        return COL.cell_fill_x
    end
    if v == 2 then
        return COL.cell_fill_o
    end
    return COL.cell
end

local function cell_rich(idx)
    local v = board[idx]
    if v == 1 then
        return "<b><color=" .. COL.x_hi .. ">X</color></b>"
    end
    if v == 2 then
        return "<b><color=" .. COL.o_hi .. ">O</color></b>"
    end
    return ""
end

local function cell_muted(idx)
    if board[idx] == 0 then
        return COL.dim
    end
    return COL.text
end

local function status_rich()
    if winner == 1 then
        return "<size=115%><b><color=" .. COL.neon_cyan .. ">X</color></b></size>\n<color=#DDD6FE>seals it</color>"
    end
    if winner == 2 then
        return "<size=115%><b><color=" .. COL.neon_magenta .. ">O</color></b></size>\n<color=#DDD6FE>seals it</color>"
    end
    if winner == 3 then
        return "<color=" .. COL.win_glow .. "><b>Stalemate</b></color>\n<color=#A5B4FC>Perfectly balanced</color>"
    end
    if current == 1 then
        return "<color=#94A3B8>Your move</color>\n<b><color=" .. COL.neon_cyan .. ">PLAYER X</color></b>"
    end
    return "<color=#94A3B8>Your move</color>\n<b><color=" .. COL.neon_magenta .. ">PLAYER O</color></b>"
end

local function draw_bg_fx()
    s:element({
        id = "bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = H },
        style = { bg = COL.bg },
    })

    local glowH = math.max(40, math.floor(H * 0.42))
    s:element({
        id = "bg_bloom",
        type = "panel",
        rect = { unit = "px", x = 0, y = H - glowH, w = W, h = glowH },
        style = { bg = COL.bg_lift },
    })

    local vx = math.max(8, math.floor(minDim * 0.06))
    s:element({ id = "v_tl", type = "panel", rect = { unit = "px", x = 0, y = 0, w = vx, h = vx }, style = { bg = COL.vignette } })
    s:element({ id = "v_tr", type = "panel", rect = { unit = "px", x = W - vx, y = 0, w = vx, h = vx }, style = { bg = COL.vignette } })
    s:element({ id = "v_bl", type = "panel", rect = { unit = "px", x = 0, y = H - vx, w = vx, h = vx }, style = { bg = COL.vignette } })
    s:element({ id = "v_br", type = "panel", rect = { unit = "px", x = W - vx, y = H - vx, w = vx, h = vx }, style = { bg = COL.vignette } })
end

local function draw_board()
    local halo = 5
    s:element({
        id = "board_halo",
        type = "panel",
        rect = { unit = "px", x = boardX - halo, y = boardY - halo, w = BOARD_PX + halo * 2, h = BOARD_PX + halo * 2 },
        style = { bg = COL.board_halo },
    })

    s:element({
        id = "board_outer",
        type = "panel",
        rect = { unit = "px", x = boardX - 3, y = boardY - 3, w = BOARD_PX + 6, h = BOARD_PX + 6 },
        style = { bg = COL.board_rim },
    })

    s:element({
        id = "board_neon_t",
        type = "panel",
        rect = { unit = "px", x = boardX - 1, y = boardY - 2, w = BOARD_PX + 2, h = 2 },
        style = { bg = COL.neon_cyan },
    })
    s:element({
        id = "board_neon_l",
        type = "panel",
        rect = { unit = "px", x = boardX - 2, y = boardY - 1, w = 2, h = BOARD_PX + 2 },
        style = { bg = COL.neon_cyan_dim },
    })
    s:element({
        id = "board_neon_b",
        type = "panel",
        rect = { unit = "px", x = boardX - 1, y = boardY + BOARD_PX, w = BOARD_PX + 2, h = 2 },
        style = { bg = COL.neon_magenta },
    })
    s:element({
        id = "board_neon_r",
        type = "panel",
        rect = { unit = "px", x = boardX + BOARD_PX, y = boardY - 1, w = 2, h = BOARD_PX + 2 },
        style = { bg = COL.neon_magenta_dim },
    })

    s:element({
        id = "board_well",
        type = "panel",
        rect = { unit = "px", x = boardX, y = boardY, w = BOARD_PX, h = BOARD_PX },
        style = { bg = COL.board_well },
    })

    for row = 0, 2 do
        for col = 0, 2 do
            local idx = row * 3 + col + 1
            local x = boardX + col * (CELL + GAP)
            local y = boardY + row * (CELL + GAP)
            s:element({
                id = "bez_" .. idx,
                type = "panel",
                rect = { unit = "px", x = x - 1, y = y - 1, w = CELL + 2, h = CELL + 2 },
                style = { bg = cell_bezel(idx) },
            })
            s:element({
                id = "cell_" .. idx,
                type = "button",
                rect = { unit = "px", x = x, y = y, w = CELL, h = CELL },
                props = { text = cell_rich(idx) },
                style = {
                    bg = cell_bg(idx),
                    text = cell_muted(idx),
                    font_size = font_cell,
                },
                on_click = function()
                    place_at(idx)
                end,
            })
        end
    end
end

local function draw_sidebar(inner, rLeft, rW, pTop, pBot, g, titleH, titleY, statusY, statusH, statusBottom, btnY, helpY, helpH, helpText)
    s:element({
        id = "right_glow",
        type = "panel",
        rect = { unit = "px", x = rightX - 1, y = boardY - 2, w = rightW + 3, h = BOARD_PX + 4 },
        style = { bg = COL.panel_shine },
    })

    s:element({
        id = "right_border",
        type = "panel",
        rect = { unit = "px", x = rightX, y = boardY, w = 3, h = BOARD_PX },
        style = { bg = COL.chip_line },
    })

    s:element({
        id = "right_bg",
        type = "panel",
        rect = { unit = "px", x = rightX + 3, y = boardY, w = math.max(1, rightW - 3), h = BOARD_PX },
        style = { bg = COL.panel },
    })

    s:element({
        id = "right_inner_line",
        type = "panel",
        rect = { unit = "px", x = rightX + 3, y = boardY + 2, w = math.max(1, rightW - 5), h = 1 },
        style = { bg = COL.violet_dim },
    })

    local glam_title = "<size=95%><color=" .. COL.dim .. ">✦ ARCADE</color></size>\n<b><color=" .. COL.neon_cyan .. ">TIC</color> <color=#E0E7FF>TAC</color> <color=" .. COL.neon_magenta .. ">TOE</color></b>"

    s:element({
        id = "title_lbl",
        type = "label",
        rect = { unit = "px", x = rLeft, y = titleY, w = rW, h = titleH },
        props = { text = glam_title },
        style = { font_size = font_title, align = "center" },
    })

    s:element({
        id = "status_lbl",
        type = "label",
        rect = { unit = "px", x = rLeft, y = statusY, w = rW, h = statusH },
        props = { text = status_rich() },
        style = { font_size = font_status, align = "center" },
    })

    if helpH > 0 then
        s:element({
            id = "help_lbl",
            type = "label",
            rect = { unit = "px", x = rLeft, y = helpY, w = rW, h = helpH },
            props = { text = helpText },
            style = { font_size = font_help, align = "center" },
        })
    end

    s:element({
        id = "btn_reset",
        type = "button",
        rect = { unit = "px", x = rLeft, y = btnY, w = rW, h = btnH },
        props = { text = "✦ NEW RUN ✦" },
        style = { bg = COL.btn_top, text = COL.btn_text, font_size = math.max(8, math.floor(font_title * 1.08)) },
        on_click = function()
            reset_game()
        end,
    })
end

local function render_ui()
    compute_layout()

    s:clear()

    draw_bg_fx()
    draw_board()

    local inner = math.max(4, math.floor(PAD * 0.75))
    local rLeft = rightX + 3 + inner
    local rW = math.max(8, rightW - 3 - inner * 2)
    local pTop = boardY + inner
    local pBot = boardY + BOARD_PX - inner
    local g = math.max(3, math.floor(inner * 0.65))

    local titleH = math.max(30, math.floor(font_title * 2.85))
    local titleY = pTop
    local statusY = titleY + titleH + g
    local statusH = math.max(36, math.floor(font_status * 3.1))
    local statusBottom = statusY + statusH

    local btnY = pBot - btnH
    local helpGap = g
    local lineH = math.max(8, math.floor(font_help * 1.25))
    local helpMaxH = lineH * 3 + 8
    local helpY = statusBottom + g
    local helpH = btnY - helpGap - helpY

    if helpH < lineH + 2 then
        helpH = 0
        helpY = statusBottom
    elseif helpH > helpMaxH then
        helpY = btnY - helpGap - helpMaxH
        helpH = helpMaxH
        if helpY < statusBottom + g then
            helpY = statusBottom + g
            helpH = math.max(lineH + 2, btnY - helpGap - helpY)
        end
    end

    if helpY < statusBottom + g then
        helpY = statusBottom + g
        helpH = math.max(0, btnY - helpGap - helpY)
    end

    local helpText
    if helpH >= lineH * 2 + 2 then
        helpText = "<color=" .. COL.muted .. ">Touch the grid</color>\n<color=" .. COL.dim .. ">Keys <b>1-9</b> · <b>R</b> rematch</color>"
    else
        helpText = "<color=" .. COL.dim .. ">Tap · 1-9 · R</color>"
    end

    draw_sidebar(inner, rLeft, rW, pTop, pBot, g, titleH, titleY, statusY, statusH, statusBottom, btnY, helpY, helpH, helpText)

    s:element({
        id = "hud",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = HUD_H },
        style = { bg = COL.hud },
    })

    s:element({
        id = "hud_shine",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = math.max(1, math.floor(HUD_H * 0.35)) },
        style = { bg = COL.hud_glow },
    })

    local stripeY = HUD_H - 3
    s:element({ id = "hud_st_c", type = "panel", rect = { unit = "px", x = 0, y = stripeY, w = math.floor(W * 0.55), h = 2 }, style = { bg = COL.hud_line_c } })
    s:element({ id = "hud_st_m", type = "panel", rect = { unit = "px", x = math.floor(W * 0.45), y = stripeY, w = W - math.floor(W * 0.45), h = 2 }, style = { bg = COL.hud_line_m } })

    local ifaceY = math.max(3, math.floor((HUD_H - ifaceH) / 2))
    local ifaceX = W - ifaceW - PAD
    local hudGap = math.max(4, math.floor(PAD * 0.6))
    local titleBoxW = math.max(32, ifaceX - PAD - hudGap)

    local hostName = host_display_name()
    s:element({
        id = "hud_title",
        type = "label",
        rect = { unit = "px", x = PAD, y = ifaceY, w = titleBoxW, h = ifaceH },
        props = {
            text = "<color=" .. COL.violet .. ">" .. hostName .. "</color>  <b><color=#F1F5FF>Tic Tac Toe</color></b> <color=" .. COL.neon_cyan .. ">◆</color>",
        },
        style = { font_size = font_hud, align = "left" },
    })

    s:element({
        id = "interface_btn",
        type = "interface_button",
        rect = { unit = "px", x = W - ifaceW - PAD, y = ifaceY, w = ifaceW, h = ifaceH },
        props = { text = "INTERFACE" },
        style = { bg = COL.iface_bg, text = COL.iface_text, font_size = math.max(7, math.floor(ifaceH * 0.4)) },
    })

    s:commit()
end

reset_game()
render_ui()
dirty_ui = false

local last_clock = util.game_time()

local function normalize_key(key)
    if key == nil then
        return nil
    end
    if #key == 1 then
        return string.upper(key)
    end
    return key
end

local function game_frame()
    local now = util.game_time()
    local dt = now - last_clock
    last_clock = now
    if dt < 0 then
        dt = 0
    end
    if dt > 0.1 then
        dt = 0.1
    end
    _ = dt

    local sz = s:size()
    local sw = math.floor(sz.w + 0.5)
    local sh = math.floor(sz.h + 0.5)
    if lastSurfW == nil or sw ~= lastSurfW or sh ~= lastSurfH then
        lastSurfW, lastSurfH = sw, sh
        dirty_ui = true
    end

    local setting = read(DB, LT.Setting) or 0
    if setting ~= 0 then
        if setting == 8 then
            reset_game()
        end
        write(DB, LT.Setting, 0)
    end

    local events = s:poll_input()
    for i = 1, #events do
        local ev = events[i]
        local name = string.lower(ev.event or "")
        if name == "keydown" then
            local k = normalize_key(ev.value)
            if k == "R" then
                reset_game()
            elseif winner == 0 and k ~= nil and #k == 1 then
                local n = string.byte(k, 1) - string.byte("0", 1)
                if n >= 1 and n <= 9 then
                    place_at(n)
                end
            end
        end
    end

    if dirty_ui then
        render_ui()
        dirty_ui = false
    end
end

s:on_frame(game_frame)