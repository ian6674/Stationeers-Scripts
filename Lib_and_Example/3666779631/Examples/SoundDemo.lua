-- SoundDemo.lua
-- Demonstrates the ScriptedScreens sound playback API.
--
-- Built-in game sounds play through the game's AudioManager with automatic
-- atmosphere-dependent volume (muffled in vacuum, normal in pressurized rooms).
-- Remote audio (wav/mp3/ogg) requires AllowMediaPlayback to be enabled.
--
-- API:
--   ss.play_sound(name_or_url, opts?)  -> id
--   ss.stop_sound(id)
--   ss.stop_all_sounds()
--
-- opts table (all optional):
--   volume = 0..1      (default 1)
--   loop   = true/false (default false)
--   id     = "string"   (explicit id for later stop; auto-generated if omitted)

local s = ss.ui.surface("main")
ss.ui.activate("main")

-- ── UI layout ────────────────────────────────────────────────────────────

s:clear()

local size = s:size()
local W, H = size.w, size.h
local halfW = (W - 30) / 2

-- Title
s:element({
    id = "title",
    type = "label",
    rect = { unit = "px", x = 0, y = 4, w = W, h = 24 },
    props = { text = "SOUND DEMO" },
    style = { font_size = 18, color = "#00ffcc", align = "center" },
})

-- Status text
s:element({
    id = "status",
    type = "label",
    rect = { unit = "px", x = 10, y = 30, w = W - 20, h = 16 },
    props = { text = "Press a button to play a sound." },
    style = { font_size = 11, color = "#888888" },
})

-- ── Built-in sound buttons (using ss.sounds enum) ───────────────────────
-- Each button plays a different built-in game sound via the ss.sounds table.

local builtInSounds = {
    { src = ss.sounds.LogicOnBeep,    label = "LogicOnBeep" },
    { src = ss.sounds.LogicOffBeep,   label = "LogicOffBeep" },
    { src = ss.sounds.CompletedChime, label = "CompletedChime" },
    { src = ss.sounds.Error,          label = "Error" },
    { src = ss.sounds.SwitchOn,       label = "SwitchOn" },
    { src = ss.sounds.SwitchOff,      label = "SwitchOff" },
    { src = ss.sounds.ActivateButton, label = "ActivateButton" },
    { src = ss.sounds.DialTurn,       label = "DialTurn" },
}

local btnY = 50
local col = 0
for i, snd in ipairs(builtInSounds) do
    local x = col == 0 and 10 or (halfW + 20)
    s:element({
        id = "btn_" .. snd.label,
        type = "button",
        rect = { unit = "px", x = x, y = btnY, w = halfW, h = 22 },
        props = { text = snd.label, value = snd.src },
        style = { bg = "#1E293B", color = "#E2E8F0", font_size = 10 },
        on_click = "on_sound_click",
    })
    col = col + 1
    if col >= 2 then
        col = 0
        btnY = btnY + 25
    end
end
if col ~= 0 then btnY = btnY + 25 end

-- ── Alert / announcement buttons ─────────────────────────────────────────

s:element({
    id = "alert_header",
    type = "label",
    rect = { unit = "px", x = 10, y = btnY, w = W - 20, h = 16 },
    props = { text = "ANNOUNCEMENTS (ss.sounds.alerts)" },
    style = { font_size = 10, color = "#F59E0B" },
})
btnY = btnY + 18

local alertSounds = {
    { src = ss.sounds.alerts.Warning,       label = "Warning" },
    { src = ss.sounds.alerts.Danger,        label = "Danger" },
    { src = ss.sounds.alerts.IntruderAlert, label = "IntruderAlert" },
    { src = ss.sounds.alerts.Welcome,       label = "Welcome" },
}

col = 0
for i, snd in ipairs(alertSounds) do
    local x = col == 0 and 10 or (halfW + 20)
    s:element({
        id = "btn_alert_" .. snd.label,
        type = "button",
        rect = { unit = "px", x = x, y = btnY, w = halfW, h = 22 },
        props = { text = snd.label, value = snd.src },
        style = { bg = "#422006", color = "#FDE68A", font_size = 10 },
        on_click = "on_sound_click",
    })
    col = col + 1
    if col >= 2 then
        col = 0
        btnY = btnY + 25
    end
end
if col ~= 0 then btnY = btnY + 25 end

-- ── Remote audio button (requires AllowMediaPlayback = true) ──────────────

s:element({
    id = "remote_header",
    type = "label",
    rect = { unit = "px", x = 10, y = btnY, w = W - 20, h = 16 },
    props = { text = "REMOTE AUDIO (requires media config)" },
    style = { font_size = 10, color = "#60A5FA" },
})
btnY = btnY + 18

s:element({
    id = "btn_remote",
    type = "button",
    rect = { unit = "px", x = 10, y = btnY, w = W - 20, h = 22 },
    props = { text = "Play Web Sound (mp3)", value = "https://www.soundjay.com/buttons_c2026/button-3.mp3" },
    style = { bg = "#1E3A5F", color = "#93C5FD", font_size = 10 },
    on_click = "on_sound_click",
})
btnY = btnY + 28

-- ── Volume slider ────────────────────────────────────────────────────────

s:element({
    id = "vol_label",
    type = "label",
    rect = { unit = "px", x = 10, y = btnY, w = 55, h = 18 },
    props = { text = "Volume:" },
    style = { font_size = 10, color = "#cccccc" },
})

s:element({
    id = "vol_slider",
    type = "slider",
    rect = { unit = "px", x = 65, y = btnY, w = W - 75, h = 18 },
    props = { value = "0.8", min = "0", max = "1" },
    on_change = "on_volume_change",
})
btnY = btnY + 24

-- ── Loop + Stop All ──────────────────────────────────────────────────────

s:element({
    id = "loop_btn",
    type = "button",
    rect = { unit = "px", x = 10, y = btnY, w = halfW, h = 22 },
    props = { text = "Loop: Warning" },
    style = { bg = "#224422", color = "#88ff88", font_size = 10 },
    on_click = "on_loop_toggle",
})

s:element({
    id = "stop_all_btn",
    type = "button",
    rect = { unit = "px", x = halfW + 20, y = btnY, w = halfW, h = 22 },
    props = { text = "Stop All" },
    style = { bg = "#442222", color = "#ff8888", font_size = 10 },
    on_click = "on_stop_all",
})

s:commit()

-- ── State ────────────────────────────────────────────────────────────────

local volume = 0.8
local looping = false

-- ── Event handlers ───────────────────────────────────────────────────────

function on_sound_click(value, player)
    -- value is the src string set on the button (e.g. "LogicOnBeep" or a URL)
    local id = ss.play_sound(value, { volume = volume })
    s:get("status"):set_props({ text = "Played: " .. value .. " → " .. tostring(id) })
    s:commit()
end

function on_volume_change(value, player)
    volume = tonumber(value) or 0.8
    s:get("vol_slider"):set_props({ value = tostring(volume) })
    s:get("status"):set_props({ text = "Volume: " .. string.format("%.0f%%", volume * 100) })
    s:commit()
end

function on_loop_toggle(value, player)
    if looping then
        ss.stop_sound("demo_loop")
        looping = false
        s:get("loop_btn"):set_props({ text = "Loop: Warning" })
        s:get("loop_btn"):set_style({ bg = "#224422" })
        s:get("status"):set_props({ text = "Stopped looping." })
    else
        -- Loop an announcement sound using ss.sounds.alerts
        ss.play_sound(ss.sounds.alerts.Warning, { volume = volume, loop = true, id = "demo_loop" })
        looping = true
        s:get("loop_btn"):set_props({ text = "Stop Loop" })
        s:get("loop_btn"):set_style({ bg = "#884400" })
        s:get("status"):set_props({ text = "Looping: Warning (id=demo_loop)" })
    end
    s:commit()
end

function on_stop_all(value, player)
    ss.stop_all_sounds()
    looping = false
    s:get("loop_btn"):set_props({ text = "Loop: Warning" })
    s:get("loop_btn"):set_style({ bg = "#224422" })
    s:get("status"):set_props({ text = "All sounds stopped." })
    s:commit()
end
