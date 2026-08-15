-- NetworkAnalyser.lua
-- Uses ic.device.list() to enumerate all devices on the chip's data cable network
-- and prints a summary to the Lua Debugger Logs tab. Also demonstrates ic.net.network_id()
-- to read the 8 cable-network-scope Channel registers.
--
-- HOW TO USE:
--   Insert a Lua chip into any IC Housing connected to the data network you want to inspect.
--   The output appears in the Lua Debugger Motherboard or the in-game debug log.

local LT  = ic.enums.LogicType
local LBM = ic.enums.LogicBatchMethod

-- ── Helper: safe read that returns nil instead of throwing ───────────────────
local function safe_read_id(ref_id, logic_type)
    local ok, val = pcall(read_id, ref_id, logic_type)
    return ok and val or nil
end

-- ── Scan and print all data-network devices ──────────────────────────────────
local function scan_network()
    local devices = device_list()  -- returns array from ic.device.list()
    print("=== Network Analyser ===")
    print("  Devices on data network: " .. #devices)
    print("")

    for i, d in ipairs(devices) do
        -- Resolve a human-readable prefab name if the hash is registered
        local pname = prefab_name(d.prefab_hash) or ("hash:" .. d.prefab_hash)
        local name  = d.display_name ~= "" and d.display_name or "(unlabelled)"
        local ref   = tostring(d.ref_id)

        print(string.format("[%02d] %s", i, name))
        print(string.format("     Prefab  : %s", pname))
        print(string.format("     Ref ID  : %s", ref))

        -- Try to read a handful of common logic types
        local power    = safe_read_id(d.ref_id, LT.Power)
        local on_off   = safe_read_id(d.ref_id, LT.On)
        local temp     = safe_read_id(d.ref_id, LT.Temperature)
        local pressure = safe_read_id(d.ref_id, LT.Pressure)

        if power    ~= nil then print("     Power   : " .. tostring(power))    end
        if on_off   ~= nil then print("     On      : " .. tostring(on_off))   end
        if temp     ~= nil then
            print(string.format("     Temp    : %.1f K (%.1f C)", temp, temp - 273.15))
        end
        if pressure ~= nil then
            print(string.format("     Pressure: %.1f kPa", pressure / 1000))
        end
        print("")
    end
end

-- ── Read the 8 cable-network Channel registers ───────────────────────────────
local function scan_network_channels()
    local net_ref = ic.net.network_id()
    if net_ref == nil then
        print("No data cable network found.")
        return
    end

    print("=== Cable Network Channels (ref=" .. tostring(net_ref) .. ") ===")
    local channel_types = {
        LT.Channel0, LT.Channel1, LT.Channel2, LT.Channel3,
        LT.Channel4, LT.Channel5, LT.Channel6, LT.Channel7,
    }
    for i, ct in ipairs(channel_types) do
        local v = safe_read_id(net_ref, ct) or 0
        print(string.format("  Channel%d = %g", i - 1, v))
    end
    print("")
end

-- ── Main ─────────────────────────────────────────────────────────────────────
scan_network()
scan_network_channels()

print("Scan complete. Rescanning every 30 seconds...")

while true do
    sleep(30)
    scan_network()
    scan_network_channels()
end
