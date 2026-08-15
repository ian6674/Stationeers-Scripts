-- MediaPlayer.lua
-- Example: HTTP media streaming on a ScriptedScreens surface.
--
-- Usage:
--   Place this script in a ScriptedScreens Lua chip inside a console.
--   The server must have video enabled (EnableExperimentalVideo = True in the config).
--   Clients can opt out locally via EnableMediaLocally = False.
--
-- Controls:
--   - Enter a URL in the text box and press "Load" to start playback.
--   - Play/Pause, Stop, Rewind (-10s), Fast Forward (+10s).
--   - Fullscreen toggle (hides controls).
--   - Ctrl+Alt+MouseWheel: adjust per-screen volume (while looking at the console)
--   - Configurable mute key: toggle global media mute
--
-- Media props (Lua -> engine):
--   url       = HTTP/HTTPS URL to an .mp4 file
--   playing   = "true" or "false"
--   volume    = "0" to "1" (server-authoritative; client may override locally)
--   loop      = "true" or "false"
--   seek      = absolute seek time in seconds (one-shot, paired with seek_id)
--   seek_id   = integer nonce; every increment triggers a new seek

local ui                = ss.ui.surface("main")
ss.ui.activate("main")

-- Layout constants
local VIDEO_RECT_NORMAL = { x = 0.02, y = 0.16, w = 0.96, h = 0.64 }
local SEEK_STEP         = 10

-- Aspect ratios: adjust VIDEO_ASPECT to match your content (16/9, 4/3, 21/9, etc.)
-- SCREEN_ASPECT is 1 for the default square console screens; change if using set_resolution.
local VIDEO_ASPECT      = 16 / 9
local SCREEN_ASPECT     = 1

-- Compute a fullscreen rect that letterboxes (or pillarboxes) to preserve aspect ratio.
local function compute_fullscreen_rect()
    local videoRatio  = VIDEO_ASPECT
    local screenRatio = SCREEN_ASPECT

    if videoRatio > screenRatio then
        -- Video is wider than screen → letterbox (black bars top/bottom)
        local h = screenRatio / videoRatio
        return { x = 0, y = (1 - h) / 2, w = 1, h = h }
    else
        -- Video is taller than screen → pillarbox (black bars left/right)
        local w = videoRatio / screenRatio
        return { x = (1 - w) / 2, y = 0, w = w, h = 1 }
    end
end
local VIDEO_RECT_FULLSCREEN = compute_fullscreen_rect()

-- State
local videoUrl              = ""
local inputUrl              = ""
local isPlaying             = false
local isFullscreen          = false
local loopEnabled           = true
local volumeValue           = 0.5
local seekId                = 0
local baseTime              = 0
local playStartClock        = nil
local lastStatusClock       = 0
local soundTrigger          = 0 -- incremented each time a sound element play is triggered
local isAudioMode           = false

-- Visualizer state
local NUM_BARS              = 22
local VIZ_BG                = "#080814"
local _bPhase               = {}
local _bFreq                = {}
for i = 1, NUM_BARS do
    _bPhase[i] = (i - 1) / NUM_BARS * 6.2832
    _bFreq[i]  = 0.9 + math.abs(math.sin(i * 1.37)) * 1.4
end

-- Helpers
local function is_audio_url(url)
    local ext = string.lower(url:match("%.([^%.%?#]+)[%?#]?$") or "")
    return ext == "mp3" or ext == "ogg" or ext == "wav"
end

local function hsl_hex(h, s, l)
    h = h % 360
    local c = (1 - math.abs(2 * l - 1)) * s
    local x = c * (1 - math.abs((h / 60) % 2 - 1))
    local m = l - c / 2
    local r, g, b
    if h < 60 then
        r, g, b = c, x, 0
    elseif h < 120 then
        r, g, b = x, c, 0
    elseif h < 180 then
        r, g, b = 0, c, x
    elseif h < 240 then
        r, g, b = 0, x, c
    elseif h < 300 then
        r, g, b = x, 0, c
    else
        r, g, b = c, 0, x
    end
    return string.format("#%02x%02x%02x",
        math.floor((r + m) * 255 + .5),
        math.floor((g + m) * 255 + .5),
        math.floor((b + m) * 255 + .5))
end

-- Build a vertical gradient for one visualizer bar.
-- level 0..1 = normalised bar height from bottom.
-- Gradient position 0 = top of element, 1 = bottom.
local function bar_gradient(level, hue)
    if level < 0.01 then return { { 0, VIZ_BG }, { 1, VIZ_BG } } end
    local peak  = 1 - level
    local above = math.max(0, peak - 0.004)
    local mid   = math.min(1, peak + level * 0.45)
    return {
        { 0,     VIZ_BG },
        { above, VIZ_BG },
        { peak,  hsl_hex(hue, 1, 0.88) },
        { mid,   hsl_hex(hue, 1, 0.42) },
        { 1,     hsl_hex(hue, 1, 0.18) },
    }
end

local function clamp(v, minVal, maxVal)
    if v < minVal then return minVal end
    if v > maxVal then return maxVal end
    return v
end

local function current_playhead()
    if isPlaying and playStartClock then
        return baseTime + (os.clock() - playStartClock)
    end
    return baseTime
end

local function format_time(sec)
    sec = math.max(0, sec or 0)
    local m = math.floor(sec / 60)
    local s = math.floor(sec % 60)
    return string.format("%d:%02d", m, s)
end

local function update_status(prefix)
    if videoUrl == "" then
        ui:get("status"):set_props({ text = "No media loaded" })
        return
    end

    local playState = isPlaying and "Playing" or "Paused"
    local timeLabel = format_time(current_playhead())
    local status = prefix or (playState .. ": " .. videoUrl)
    ui:get("status"):set_props({ text = status .. " [" .. timeLabel .. "]" })
end

local function set_playing(nextPlaying)
    if nextPlaying == isPlaying then return end
    if nextPlaying then
        playStartClock = os.clock()
    else
        baseTime = current_playhead()
        playStartClock = nil
    end
    isPlaying = nextPlaying
end

local function issue_seek(newTime)
    seekId = seekId + 1
    ui:get("video"):set_props({ seek = newTime, seek_id = seekId })
end

local function seek_by(delta)
    if videoUrl == "" then return end
    baseTime = clamp(current_playhead() + delta, 0, 24 * 60 * 60)
    if isPlaying then
        playStartClock = os.clock()
    end
    issue_seek(baseTime)
    update_status()
end

local function stop_playback()
    if videoUrl == "" then return end
    set_playing(false)
    baseTime = 0
    if isAudioMode then
        ui:get("audio_player"):set_props({ playing = "false" })
    else
        issue_seek(0)
        ui:get("video"):set_props({ playing = "false" })
    end
    update_status("Stopped: " .. videoUrl)
end

local function upsert_video(rect)
    ui:element({
        id = "video",
        type = "media",
        rect = rect,
        props = {
            url     = videoUrl,
            playing = isPlaying and "true" or "false",
            volume  = tostring(volumeValue),
            loop    = loopEnabled and "true" or "false",
        },
    })
end

local function set_fullscreen(enable)
    if enable == isFullscreen then return end
    isFullscreen = enable

    upsert_video(enable and VIDEO_RECT_FULLSCREEN or VIDEO_RECT_NORMAL)

    local vis = enable and "false" or "true"
    local controls = {
        "title", "url_input", "load_btn", "status",
        "rew_btn", "toggle_btn", "stop_btn", "ff_btn",
        "vol_label", "vol_slider", "fs_btn"
    }

    for i = 1, #controls do
        local handle = ui:get(controls[i])
        if handle then handle:set_props({ visible = vis }) end
    end

    local exitBtn = ui:get("fs_exit")
    if exitBtn then exitBtn:set_props({ visible = enable and "true" or "false" }) end
end

-- Clear previous state
ui:clear()

-- Background panel
ui:element({
    id = "bg",
    type = "panel",
    rect = { x = 0, y = 0, w = 1, h = 1 },
    style = { bg = "#111111" },
})

-- Title label
ui:element({
    id = "title",
    type = "label",
    rect = { x = 0.02, y = 0.02, w = 0.96, h = 0.06 },
    props = { text = "Media Player", font_size = 18 },
    style = { color = "#FFFFFF" },
})

-- URL input row: text input + Load button
local urlInputHandle
urlInputHandle = ui:element({
    id = "url_input",
    type = "textinput",
    rect = { x = 0.02, y = 0.09, w = 0.78, h = 0.05 },
    props = { value = "", placeholder = "Enter .mp4 URL…" },
    style = { bg = "#1E293B", color = "#E2E8F0", font_size = 12 },
    on_change = function(value)
        inputUrl = value or ""
        -- Keep the UI text in sync with the authoritative props.
        if urlInputHandle then
            urlInputHandle:set_props({ value = inputUrl })
        end
    end,
})

ui:element({
    id = "load_btn",
    type = "button",
    rect = { x = 0.82, y = 0.09, w = 0.16, h = 0.05 },
    props = { text = "Load" },
    style = { bg = "#22C55E", text = "#0F172A" },
    on_click = function()
        if inputUrl ~= "" then
            local newAudioMode = is_audio_url(inputUrl)
            videoUrl = inputUrl
            set_playing(true)
            baseTime = 0
            playStartClock = os.clock()

            if newAudioMode then
                -- Stop any playing video; route audio through the sound element
                ui:get("video"):set_props({ playing = "false" })
                soundTrigger = soundTrigger + 1
                ui:get("audio_player"):set_props({
                    src     = videoUrl,
                    playing = "true",
                    trigger = tostring(soundTrigger),
                    loop    = loopEnabled and "true" or "false",
                    volume  = volumeValue,
                })
            else
                -- Stop any playing audio; route video through the media element
                ui:get("audio_player"):set_props({ playing = "false" })
                ui:get("video"):set_props({ url = videoUrl, playing = "true" })
            end

            -- Show/hide visualizer and hide stale bars on mode change
            if newAudioMode ~= isAudioMode then
                isAudioMode = newAudioMode
                ui:get("viz_bg"):set_props({ visible = isAudioMode and "true" or "false" })
                if not isAudioMode then
                    for i = 1, NUM_BARS do
                        local h = ui:get("viz_bar_" .. i)
                        if h then h:set_props({ visible = "false" }) end
                    end
                end
            else
                isAudioMode = newAudioMode
            end

            update_status("Playing: " .. videoUrl)
            ui:get("toggle_btn"):set_props({ text = "Pause" })
        end
    end,
})

-- Media element: created once with an empty URL; updated in-place when Load is clicked.
-- This avoids destroying/recreating the underlying VideoPlayer.
upsert_video(VIDEO_RECT_NORMAL)

-- Status label
ui:element({
    id = "status",
    type = "label",
    rect = { x = 0.02, y = 0.81, w = 0.96, h = 0.04 },
    props = { text = "No media loaded", font_size = 12 },
    style = { color = "#AAAAAA" },
})

-- Control row (rew, play/pause, stop, fwd, fullscreen)
ui:element({
    id = "rew_btn",
    type = "button",
    rect = { x = 0.02, y = 0.86, w = 0.12, h = 0.06 },
    props = { text = "-10s" },
}):on("click", function()
    seek_by(-SEEK_STEP)
end)

ui:element({
    id = "toggle_btn",
    type = "button",
    rect = { x = 0.16, y = 0.86, w = 0.18, h = 0.06 },
    props = { text = "Play" },
}):on("click", function()
    if videoUrl ~= "" then
        set_playing(not isPlaying)
        if isAudioMode then
            if isPlaying then
                -- Resume audio: re-trigger from the beginning (sound element has no seek)
                soundTrigger = soundTrigger + 1
                ui:get("audio_player"):set_props({ playing = "true", trigger = tostring(soundTrigger) })
            else
                ui:get("audio_player"):set_props({ playing = "false" })
            end
        else
            ui:get("video"):set_props({ playing = isPlaying and "true" or "false" })
        end
        ui:get("toggle_btn"):set_props({ text = isPlaying and "Pause" or "Play" })
        update_status()
    end
end)

ui:element({
    id = "stop_btn",
    type = "button",
    rect = { x = 0.36, y = 0.86, w = 0.12, h = 0.06 },
    props = { text = "Stop" },
}):on("click", function()
    stop_playback()
end)

ui:element({
    id = "ff_btn",
    type = "button",
    rect = { x = 0.50, y = 0.86, w = 0.12, h = 0.06 },
    props = { text = "+10s" },
}):on("click", function()
    seek_by(SEEK_STEP)
end)

ui:element({
    id = "fs_btn",
    type = "button",
    rect = { x = 0.64, y = 0.86, w = 0.18, h = 0.06 },
    props = { text = "Full" },
}):on("click", function()
    set_fullscreen(true)
end)

-- Fullscreen exit (only visible in fullscreen)
ui:element({
    id = "fs_exit",
    type = "button",
    rect = { x = 0.80, y = 0.02, w = 0.18, h = 0.06 },
    props = { text = "Exit", visible = "false" },
    style = { bg = "#DC2626", text = "#F8FAFC" },
}):on("click", function()
    set_fullscreen(false)
end)

-- Invisible sound element for audio-only playback (mp3/ogg/wav).
-- Uses UnityWebRequest which handles HTTP audio streams; VideoPlayer cannot.
ui:element({
    id    = "audio_player",
    type  = "sound",
    rect  = { x = 0, y = 0, w = 0, h = 0 },
    props = { src = "", volume = volumeValue, loop = "true", playing = "false", trigger = "0" },
})

-- Visualizer background panel (hidden until an audio URL is loaded)
ui:element({
    id    = "viz_bg",
    type  = "panel",
    rect  = VIDEO_RECT_NORMAL,
    props = { visible = "false" },
    style = { bg = VIZ_BG },
})

-- Visualizer bars (one per frequency band, hidden until audio mode active)
do
    local gap = 0.002
    local bw  = VIDEO_RECT_NORMAL.w / NUM_BARS - gap
    for i = 1, NUM_BARS do
        local bx = VIDEO_RECT_NORMAL.x + (i - 1) * (VIDEO_RECT_NORMAL.w / NUM_BARS)
        ui:element({
            id    = "viz_bar_" .. i,
            type  = "panel",
            rect  = { x = bx, y = VIDEO_RECT_NORMAL.y, w = bw, h = VIDEO_RECT_NORMAL.h },
            props = { visible = "false" },
            style = { bg = VIZ_BG, gradient_dir = "vertical" },
        })
    end
end

-- Volume slider (server-authoritative volume)
ui:element({
    id = "vol_label",
    type = "label",
    rect = { x = 0.02, y = 0.93, w = 0.18, h = 0.05 },
    props = { text = "Volume:", font_size = 12 },
    style = { color = "#CCCCCC" },
})

ui:element({
    id = "vol_slider",
    type = "slider",
    rect = { x = 0.22, y = 0.93, w = 0.55, h = 0.05 },
    props = { value = volumeValue, min = 0, max = 1 },
}):on("change", function(value)
    volumeValue = tonumber(value) or volumeValue
    ui:get("vol_slider"):set_props({ value = volumeValue })
    if isAudioMode then
        ui:get("audio_player"):set_props({ volume = volumeValue })
    else
        ui:get("video"):set_props({ volume = tostring(volumeValue) })
    end
end)

-- Register per-frame visualizer animation via the surface on_frame callback.
-- Runs in Unity Update (~60fps) for smooth gradient animation.
ui:on_frame(function()
    if not isAudioMode or not isPlaying then return end

    local t   = os.clock()
    local gap = 0.002
    local bw  = VIDEO_RECT_NORMAL.w / NUM_BARS - gap

    for i = 1, NUM_BARS do
        -- Layered sine waves with per-bar phase/frequency for organic movement
        local a1  = math.sin(t * _bFreq[i] + _bPhase[i])
        local a2  = math.sin(t * _bFreq[i] * 1.61803 + _bPhase[i] * 0.7) * 0.4
        local a3  = math.sin(t * 0.27 + _bPhase[i] * 0.3) * 0.25
        local lvl = math.min(1, math.max(0.02, math.abs(a1 + a2 + a3) / 1.65))

        -- Hue spans 0-300 across the bar array and slowly drifts with time
        local hue = ((i - 1) / (NUM_BARS - 1)) * 300 + t * 12
        local bx  = VIDEO_RECT_NORMAL.x + (i - 1) * (VIDEO_RECT_NORMAL.w / NUM_BARS)

        ui:element({
            id    = "viz_bar_" .. i,
            type  = "panel",
            rect  = { x = bx, y = VIDEO_RECT_NORMAL.y, w = bw, h = VIDEO_RECT_NORMAL.h },
            props = { visible = "true" },
            style = {
                bg           = VIZ_BG,
                gradient     = bar_gradient(lvl, hue),
                gradient_dir = "vertical",
            },
        })
    end
end)

ui:commit()

function tick(dt)
    -- Throttled status poll (~4Hz). Safe to coexist with on_frame above because
    -- tick() returns synchronously without yielding - the runtime's "on_frame
    -- skipped while tick yielded" guard would otherwise halt the chip with a
    -- clear runtime error.
    if videoUrl == "" then return end
    local now = os.clock()
    if now - lastStatusClock > 0.25 then
        lastStatusClock = now
        update_status()
    end
end
