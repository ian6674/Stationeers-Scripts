-- Communications Status Display
-- ScriptedScreens command center display for comms and network monitoring
-- Shows satellite links, data rates, and signal quality

local ui = ss.ui.surface("main")
ss.ui.activate("main")

local W, H = 480, 272

local size = ui:size()
if size then
    W = size.w or W
    H = size.h or H
end

-- Simulated comms data
local commsData = {
    mainLink = {
        name = "EARTH RELAY",
        status = "CONNECTED",
        signal = 87.5,
        latency = 342,
        dataRate = 2.4,
    },
    backupLink = {
        name = "SAT-BACKUP",
        status = "STANDBY",
        signal = 62.3,
        latency = 890,
        dataRate = 0.8,
    },
    localNet = {
        devices = 24,
        bandwidth = 94.2,
        errors = 0,
    },
    messages = {
        pending = 3,
        sent = 147,
        received = 203,
    },
    lastContact = 0, -- seconds ago
}

local function get_signal_color(pct)
    if pct >= 80 then return "#00E676" end
    if pct >= 60 then return "#FFEB3B" end
    if pct >= 40 then return "#FF9800" end
    return "#FF5252"
end

local function get_status_color(status)
    if status == "CONNECTED" then return "#00E676" end
    if status == "STANDBY" then return "#29B6F6" end
    if status == "CONNECTING" then return "#FFEB3B" end
    if status == "OFFLINE" then return "#FF5252" end
    return "#B0BEC5"
end

local function fmt(v, decimals)
    if v == nil then return "--" end
    decimals = decimals or 1
    return string.format("%." .. decimals .. "f", v)
end

local function fmt_time(seconds)
    if seconds < 60 then
        return seconds .. "s ago"
    elseif seconds < 3600 then
        return math.floor(seconds / 60) .. "m ago"
    else
        return math.floor(seconds / 3600) .. "h ago"
    end
end

local function render()
    ui:clear()

    -- Background
    ui:element({
        id = "bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = H },
        style = { bg = "#0A0E1A" }
    })

    -- Precompute dynamic values
    local overallStatus = commsData.mainLink.status == "CONNECTED" and "ONLINE" or "DEGRADED"
    local overallColor = overallStatus == "ONLINE" and "#00E676" or "#FFEB3B"
    local mainColor = get_status_color(commsData.mainLink.status)
    local backupColor = get_status_color(commsData.backupLink.status)
    local errColor = commsData.localNet.errors == 0 and "#00E676" or "#FF5252"
    local pendingColor = commsData.messages.pending > 0 and "#FFEB3B" or "#94A3B8"

    -- Full-screen nested layout
    ui:layout({
        layout = "flex",
        rect = { unit = "px", x = 0, y = 0, w = W, h = H },
        direction = "column",
        gap = 0,
        children = {
            -- ── Header ───────────────────────────────────────────────
            {
                id = "hdr",
                type = "panel",
                rect = { h = 44 },
                style = { bg = "#1E293B" },
                layout = "flex",
                direction = "row",
                gap = 6,
                align = "center",
                padding = { left = 16, right = 16, top = 10 },
                children = {
                    {
                        id = "title",
                        type = "label",
                        flex = 1,
                        props = { text = "COMMUNICATIONS" },
                        style = { font_size = 16, color = "#E2E8F0", align = "left" }
                    },
                    {
                        id = "status_dot",
                        type = "panel",
                        rect = { w = 12 },
                        style = { bg = overallColor }
                    },
                    {
                        id = "status_txt",
                        type = "label",
                        rect = { w = 70 },
                        props = { text = overallStatus },
                        style = { font_size = 12, color = overallColor, align = "left" }
                    },
                }
            },

            -- ── Link panels row: Primary + Backup ────────────────────
            {
                layout = "flex",
                flex = 1,
                direction = "row",
                gap = 8,
                padding = { left = 8, right = 8, top = 10 },
                children = {
                    -- Primary link panel
                    {
                        id = "main_bg",
                        type = "panel",
                        flex = 1,
                        style = { bg = "#111827" },
                        layout = "flex",
                        direction = "column",
                        gap = 2,
                        padding = 8,
                        children = {
                            {
                                id = "main_title",
                                type = "label",
                                rect = { h = 16 },
                                props = { text = "PRIMARY LINK" },
                                style = { font_size = 11, color = "#64748B", align = "left" }
                            },
                            {
                                layout = "flex",
                                rect = { h = 18 },
                                direction = "row",
                                gap = 4,
                                children = {
                                    {
                                        id = "main_name",
                                        type = "label",
                                        flex = 1,
                                        props = { text = commsData.mainLink.name },
                                        style = { font_size = 14, color = "#E2E8F0", align = "left" }
                                    },
                                    {
                                        id = "main_status",
                                        type = "label",
                                        rect = { w = 80 },
                                        props = { text = commsData.mainLink.status },
                                        style = { font_size = 10, color = mainColor, align = "right" }
                                    },
                                }
                            },
                            -- Signal row
                            {
                                layout = "flex",
                                rect = { h = 16 },
                                direction = "row",
                                gap = 4,
                                children = {
                                    {
                                        id = "main_sig_lbl",
                                        type = "label",
                                        rect = { w = 42 },
                                        props = { text = "Signal" },
                                        style = { font_size = 10, color = "#94A3B8", align = "left" }
                                    },
                                    {
                                        id = "main_sig_bar",
                                        type = "progress",
                                        flex = 1,
                                        props = { value = tostring(commsData.mainLink.signal), max = "100" },
                                        style = { bg = "#1E293B", fill = get_signal_color(commsData.mainLink.signal) }
                                    },
                                    {
                                        id = "main_sig_pct",
                                        type = "label",
                                        rect = { w = 42 },
                                        props = { text = fmt(commsData.mainLink.signal) .. "%" },
                                        style = { font_size = 10, color = get_signal_color(commsData.mainLink.signal), align = "left" }
                                    },
                                }
                            },
                            {
                                id = "main_lat",
                                type = "label",
                                rect = { h = 14 },
                                props = { text = "Latency: " .. commsData.mainLink.latency .. "ms" },
                                style = { font_size = 10, color = "#94A3B8", align = "left" }
                            },
                            {
                                id = "main_rate",
                                type = "label",
                                rect = { h = 14 },
                                props = { text = "Rate: " .. fmt(commsData.mainLink.dataRate) .. " Mbps" },
                                style = { font_size = 10, color = "#94A3B8", align = "left" }
                            },
                        }
                    },

                    -- Backup link panel
                    {
                        id = "backup_bg",
                        type = "panel",
                        flex = 1,
                        style = { bg = "#111827" },
                        layout = "flex",
                        direction = "column",
                        gap = 2,
                        padding = 8,
                        children = {
                            {
                                id = "backup_title",
                                type = "label",
                                rect = { h = 16 },
                                props = { text = "BACKUP LINK" },
                                style = { font_size = 11, color = "#64748B", align = "left" }
                            },
                            {
                                layout = "flex",
                                rect = { h = 18 },
                                direction = "row",
                                gap = 4,
                                children = {
                                    {
                                        id = "backup_name",
                                        type = "label",
                                        flex = 1,
                                        props = { text = commsData.backupLink.name },
                                        style = { font_size = 14, color = "#E2E8F0", align = "left" }
                                    },
                                    {
                                        id = "backup_status",
                                        type = "label",
                                        rect = { w = 80 },
                                        props = { text = commsData.backupLink.status },
                                        style = { font_size = 10, color = backupColor, align = "right" }
                                    },
                                }
                            },
                            -- Signal row
                            {
                                layout = "flex",
                                rect = { h = 16 },
                                direction = "row",
                                gap = 4,
                                children = {
                                    {
                                        id = "backup_sig_lbl",
                                        type = "label",
                                        rect = { w = 42 },
                                        props = { text = "Signal" },
                                        style = { font_size = 10, color = "#94A3B8", align = "left" }
                                    },
                                    {
                                        id = "backup_sig_bar",
                                        type = "progress",
                                        flex = 1,
                                        props = { value = tostring(commsData.backupLink.signal), max = "100" },
                                        style = { bg = "#1E293B", fill = get_signal_color(commsData.backupLink.signal) }
                                    },
                                    {
                                        id = "backup_sig_pct",
                                        type = "label",
                                        rect = { w = 42 },
                                        props = { text = fmt(commsData.backupLink.signal) .. "%" },
                                        style = { font_size = 10, color = get_signal_color(commsData.backupLink.signal), align = "left" }
                                    },
                                }
                            },
                            {
                                id = "backup_lat",
                                type = "label",
                                rect = { h = 14 },
                                props = { text = "Latency: " .. commsData.backupLink.latency .. "ms" },
                                style = { font_size = 10, color = "#94A3B8", align = "left" }
                            },
                            {
                                id = "backup_rate",
                                type = "label",
                                rect = { h = 14 },
                                props = { text = "Rate: " .. fmt(commsData.backupLink.dataRate) .. " Mbps" },
                                style = { font_size = 10, color = "#94A3B8", align = "left" }
                            },
                        }
                    },
                }
            },

            -- ── Bottom row: Local Network + Messages ─────────────────
            {
                layout = "flex",
                rect = { h = 66 },
                direction = "row",
                gap = 8,
                padding = { left = 8, right = 8, top = 6 },
                children = {
                    -- Local network panel
                    {
                        id = "net_bg",
                        type = "panel",
                        flex = 1,
                        style = { bg = "#111827" },
                        layout = "flex",
                        direction = "column",
                        gap = 2,
                        padding = 8,
                        children = {
                            {
                                id = "net_title",
                                type = "label",
                                rect = { h = 16 },
                                props = { text = "LOCAL NETWORK" },
                                style = { font_size = 11, color = "#64748B", align = "left" }
                            },
                            {
                                layout = "flex",
                                rect = { h = 18 },
                                direction = "row",
                                gap = 6,
                                children = {
                                    {
                                        id = "net_devices",
                                        type = "label",
                                        flex = 1,
                                        props = { text = commsData.localNet.devices .. " devices" },
                                        style = { font_size = 14, color = "#E2E8F0", align = "left" }
                                    },
                                    {
                                        id = "net_bw",
                                        type = "label",
                                        rect = { w = 80 },
                                        props = { text = fmt(commsData.localNet.bandwidth) .. "% BW" },
                                        style = { font_size = 12, color = "#94A3B8", align = "left" }
                                    },
                                }
                            },
                            {
                                id = "net_err",
                                type = "label",
                                rect = { h = 14 },
                                props = { text = "Errors: " .. commsData.localNet.errors },
                                style = { font_size = 10, color = errColor, align = "left" }
                            },
                        }
                    },

                    -- Messages panel
                    {
                        id = "msg_bg",
                        type = "panel",
                        flex = 1,
                        style = { bg = "#111827" },
                        layout = "flex",
                        direction = "column",
                        gap = 2,
                        padding = 8,
                        children = {
                            {
                                id = "msg_title",
                                type = "label",
                                rect = { h = 16 },
                                props = { text = "MESSAGES" },
                                style = { font_size = 11, color = "#64748B", align = "left" }
                            },
                            {
                                layout = "flex",
                                rect = { h = 18 },
                                direction = "row",
                                gap = 4,
                                children = {
                                    {
                                        id = "msg_pending",
                                        type = "label",
                                        flex = 1,
                                        props = { text = commsData.messages.pending .. " pending" },
                                        style = { font_size = 12, color = pendingColor, align = "left" }
                                    },
                                    {
                                        id = "msg_sent",
                                        type = "label",
                                        rect = { w = 60 },
                                        props = { text = "TX: " .. commsData.messages.sent },
                                        style = { font_size = 11, color = "#94A3B8", align = "left" }
                                    },
                                    {
                                        id = "msg_recv",
                                        type = "label",
                                        rect = { w = 60 },
                                        props = { text = "RX: " .. commsData.messages.received },
                                        style = { font_size = 11, color = "#94A3B8", align = "left" }
                                    },
                                }
                            },
                            {
                                id = "msg_last",
                                type = "label",
                                rect = { h = 14 },
                                props = { text = "Last contact: " .. fmt_time(commsData.lastContact) },
                                style = { font_size = 10, color = "#94A3B8", align = "left" }
                            },
                        }
                    },
                }
            },

            -- ── Footer ───────────────────────────────────────────────
            {
                layout = "flex",
                rect = { h = 22 },
                direction = "row",
                padding = { left = 16 },
                children = {
                    {
                        id = "footer",
                        type = "label",
                        flex = 1,
                        props = { text = "UPLINK ACTIVE" },
                        style = { font_size = 10, color = "#475569", align = "left" }
                    },
                }
            },
        }
    })

    ui:commit()
end

render()

-- Main loop - simulate comms activity
local tick = 0
while true do
    tick = tick + 1

    -- Signal fluctuations
    commsData.mainLink.signal = commsData.mainLink.signal + (math.random() - 0.5) * 2
    commsData.mainLink.signal = math.max(50, math.min(100, commsData.mainLink.signal))

    commsData.backupLink.signal = commsData.backupLink.signal + (math.random() - 0.5) * 3
    commsData.backupLink.signal = math.max(30, math.min(90, commsData.backupLink.signal))

    -- Latency fluctuations
    commsData.mainLink.latency = commsData.mainLink.latency + math.random(-20, 20)
    commsData.mainLink.latency = math.max(200, math.min(500, commsData.mainLink.latency))

    -- Bandwidth usage
    commsData.localNet.bandwidth = commsData.localNet.bandwidth + (math.random() - 0.5) * 5
    commsData.localNet.bandwidth = math.max(60, math.min(100, commsData.localNet.bandwidth))

    -- Message activity
    if tick % 15 == 0 then
        commsData.messages.received = commsData.messages.received + math.random(0, 2)
        commsData.lastContact = 0
    end

    if tick % 20 == 0 and commsData.messages.pending > 0 then
        commsData.messages.sent = commsData.messages.sent + 1
        commsData.messages.pending = commsData.messages.pending - 1
    end

    -- Increment last contact time
    commsData.lastContact = commsData.lastContact + 1

    -- Random new pending messages
    if tick % 50 == 0 then
        commsData.messages.pending = commsData.messages.pending + math.random(0, 2)
    end

    if tick % 8 == 0 then
        render()
    end

    ic.yield()
end
