# StationeersLua — Beginner's Guide

A step-by-step walkthrough for writing Lua scripts on programmable chips in [Stationeers](https://store.steampowered.com/app/544550/Stationeers/). This guide assumes you have StationeersLua installed and working. For installation instructions and the full API reference, see [`README.md`](README.md). For a line-by-line IC10-to-Lua translation table, see [`MAPPING.MD`](MAPPING.MD).

---

## Table of Contents

1. [Quick Start](#1-quick-start)
2. [How Lua Chips Work](#2-how-lua-chips-work)
3. [Script Structure](#3-script-structure)
4. [Reading & Writing Devices](#4-reading--writing-devices)
5. [Enumerations & Constants](#5-enumerations--constants)
6. [Batch Operations](#6-batch-operations)
7. [Slots & Reagents](#7-slots--reagents)
8. [Memory & Stack](#8-memory--stack)
9. [Bitwise Operations](#9-bitwise-operations)
10. [String & Hash Utilities](#10-string--hash-utilities)
11. [Control Flow — sleep, yield, tick](#11-control-flow--sleep-yield-tick)
12. [Events](#12-events)
13. [Networking — Direct Messaging](#13-networking--direct-messaging)
14. [Networking — Pub/Sub](#14-networking--pubsub)
15. [Networking — RPC](#15-networking--rpc)
16. [Networking — Pack/Unpack](#16-networking--packunpack)
17. [Temperature Conversion](#17-temperature-conversion)
18. [JSON Utilities](#18-json-utilities)
19. [Save/Load Persistence](#19-saveload-persistence)
20. [Debugging](#20-debugging)
21. [Sandbox & Limits](#21-sandbox--limits)
22. [Error Handling Patterns](#22-error-handling-patterns)
23. [Common Patterns & Recipes](#23-common-patterns--recipes)
24. [Migrating from IC10](#24-migrating-from-ic10)
25. [Library Chips — require()](#25-library-chips--require)
26. [Companion Mods](#26-companion-mods)
27. [MCP Server & AI Editor Integration](#27-mcp-server--ai-editor-integration)
28. [VS Code Extension](#28-vs-code-extension)
29. [Wireless Development Board](#29-wireless-development-board)
30. [Editor Intelligence (LSP)](#30-editor-intelligence-lsp)

---

## 1. Quick Start

### What You Need

1. A Stationeers world with **BepInEx**, **StationeersLaunchPad**, and **IC10Editor** installed.
2. The **StationeersLua** mod in your `mods/` folder.
3. An **Integrated Circuit (Lua)** item (prefab: `ItemIntegratedCircuitLua`).

### Your First Script

1. Craft or spawn an **Integrated Circuit (Lua)**.
2. Insert it into any **IC Housing** (or Advanced IC Housing).
3. Open the housing's code editor.
4. If your script is getting too long for the editor, click the **`?`** button in **IC10Editor** to disable the editor's **script length** and **line length** limits.
5. Paste this:

```lua
-- Blink a light on d0 every second

local LT = ic.enums.LogicType
local on = false

while true do
    on = not on
    write(0, LT.On, on and 1 or 0)
    sleep(1)
end
```

6. Save. The light on device pin **d0** will blink on/off every second.

> **Tip:** For larger Lua programs, the **`?`** button in IC10Editor can disable both the script-length and line-length limits.

When the **Lua** formatter is active in IC10Editor, the editor also applies **Lua auto-indent/dedent** (block keywords, `end`/`until` alignment, 4-space Tab / Shift+Tab, and Vim `>>` / `<<`).

---

## 2. How Lua Chips Work

### Lifecycle

```
 ┌─────────────┐
 │  Code saved  │  Editor saves source to chip
 └──────┬───────┘
        ▼
 ┌─────────────┐
 │ Compile/Init │  Lua VM created, standard libs opened, ic table injected,
 │              │  module-level code runs (up to 500,000 instructions)
 └──────┬───────┘
        ▼
 ┌─────────────┐
 │  Tick loop   │  Every game tick (~0.5s):
 │              │   1. Network messages processed
 │              │   2. Events dispatched
 │              │   3. Sleeping user coroutines resumed (if timers expired)
 │              │   4. Main coroutine resumed (if sleeping/yielding)
 │              │   5. tick(dt) coroutine resumed (if defined; supports sleep/yield)
 │              │  Budget: 50,000 instructions per tick
 └──────┬───────┘
        ▼
 ┌─────────────┐
 │   Shutdown   │  Housing powered off, chip removed, or game exit
 └─────────────┘
```

### Key Rules

- **Server-authoritative**: All Lua execution happens on the server/host. Clients see results via game state sync.
- **Deterministic**: No filesystem I/O, no HTTP, no threads. Only `sleep`/`yield` for pausing.
- **Power-gated**: If the IC housing is off or unpowered, the script will not compile, initialize, or tick.

---

## 3. Script Structure

There are two main patterns for structuring a Lua chip script.

### Pattern A: `tick()` Function

Define a global `tick(dt)` function. It's called every game tick automatically.

```lua
local LT = ic.enums.LogicType

-- Module-level code runs once at init
local threshold = 25.0
print("Script initialized, threshold = " .. threshold)

-- Called every game tick
function tick(dt)
    local temp = read(0, LT.Temperature)
    if temp ~= nil and temp > threshold then
        write(1, LT.On, 1)  -- Turn on cooling
    else
        write(1, LT.On, 0)  -- Turn off cooling
    end
end
```

- `dt` is the delta time in seconds since the last tick.
- Module-level code above `tick()` runs once during initialization.
- `sleep()` and `yield()` work inside `tick()`. When `tick()` yields or sleeps, its coroutine is suspended and resumed on the next eligible tick. The main coroutine (if any) continues independently.

### Pattern B: Infinite Loop with `yield`/`sleep`

Don't define `tick()`. Instead, use a `while true` loop with `yield()` or `sleep()`.

```lua
local LT = ic.enums.LogicType

while true do
    local temp = read(0, LT.Temperature)
    if temp ~= nil and temp > 25 then
        write(1, LT.On, 1)
    else
        write(1, LT.On, 0)
    end
    yield()  -- Wait until next tick
end
```

- `yield()` pauses until the next game tick.
- `sleep(seconds)` pauses for a real-time duration.
- Both patterns are valid. Choose whichever feels more natural.

### Pattern C: Hybrid

You can combine both: module-level init code, a main coroutine that yields, *and* a `tick()` function. Both the resumed coroutine and `tick(dt)` can execute in the same tick.

---

## 4. Reading & Writing Devices

Devices are connected to the IC housing via **device pins** (`d0` through `d5`). The housing itself is accessible as `db` (device base), which in Lua is `ic.const.BASE_UNIT_INDEX` (typically index 6).

> **Advanced Computing compatibility:** If the [Advanced Computing](https://steamcommunity.com/sharedfiles/filedetails/?id=3465059322) mod is installed, chip stacks support extended device pins `d0`–`d11` and rack self-addressing at `d100`+. StationeersLua fully supports these extended indices — `read()`, `write()`, and all device functions work with any valid device index provided by the housing's `ICircuitHolder`.

### Read a Logic Value

```lua
local LT = ic.enums.LogicType

-- Read temperature from device on pin d0
local temp = read(0, LT.Temperature)

-- Returns nil if the device is missing or disconnected
if temp == nil then
    print("No device on d0!")
end
```

### Write a Logic Value

```lua
-- Turn on a device on pin d1
write(1, LT.On, 1)

-- Write may throw if the device is missing
local ok, err = pcall(function()
    write(1, LT.Setting, 42)
end)
if not ok then
    print("Write failed: " .. err)
end
```

### By Reference ID

For stable addressing that doesn't depend on pin wiring:

```lua
-- Get the ReferenceId of the device on d0
local id = device_id(0)
print("Device d0 id = " .. tostring(id))

-- Read/write using the ID directly
local temp = read_id(id, LT.Temperature)
write_id(id, LT.On, 1)
```

### Network Index

Most read/write functions accept an optional `networkIndex` parameter for multi-network setups:

```lua
-- Read from device on d0, network index 0
local value = read(0, LT.Temperature, 0)

-- Read channels from the housing itself
local ch0 = read(ic.const.BASE_UNIT_INDEX, LT.Channel0, 0)
```

### Device Labels

```lua
-- Set the display name of the device on d0
device_label(0, "Main Sensor")
-- Shorthand:
label(0, "Main Sensor")
```

### Device Name Lookup

```lua
-- Get the live display name of a device on pin d0
local name = device_name(0)
print("d0 display name: " .. tostring(name))

-- Get the prefab name from a hash
local prefab = prefab_name(-2045627372)
print("Prefab: " .. tostring(prefab))  -- "SolarPanel"

-- Resolve a nameHash by scanning visible devices
local resolved = namehash_name(deviceHash, nameHash)
```

### Device List

Enumerate all devices visible on the chip's data cable network (same scope as batch operations):

```lua
-- Returns a 1-indexed Lua array of device info tables
local devices = device_list()

for i, dev in ipairs(devices) do
    print(string.format("%d: %s (id=%d, prefab=%d)",
        i, dev.display_name, dev.ref_id, dev.prefab_hash))
end
```

Each entry contains:
- `ref_id` — the device's ReferenceId (for use with `read_id()` / `write_id()`)
- `prefab_hash` — the device's prefab hash (for use with `batch_read()` / `batch_write()`)
- `name_hash` — the device's name hash
- `display_name` — the device's current display name

Accepts an optional `networkIndex` parameter: `device_list(networkIndex)`.

### Host Info

`ic.host_info()` returns metadata about the chip's host device:

```lua
local info = ic.host_info()
print(info.name)         -- display name of the host (e.g. "Hardsuit")
print(info.ref_id)       -- host ReferenceId
print(info.prefab_hash)  -- host prefab hash
print(info.type)         -- "suit", "scripted_visor", "circuit_housing", "tablet", "motherboard", "device", or "unknown"

-- Wearables (suits and scripted visors) can report the wearer
if (info.type == "suit" or info.type == "scripted_visor") and info.wearer then
    print("Worn by: " .. info.wearer)
end
```

Wearable hosts can also include:

- `wearer` - display name of the current wearer
- `wearer_ref_id` - wearer ReferenceId
- `wearer_prefab_hash` - wearer prefab hash

These fields are present for suits and **Scripted Visor** hosts when someone is actually wearing them. In all other host types they are `nil`.

Chips installed in **pipe-style machine hosts** (for example filtration units, deep miners, dispersal towers — types that use `DeviceInputOutputCircuit`) report `type` `"device"` and use the same read/write APIs as other powered hosts on their data network.

---

## 5. Enumerations & Constants

Built-in names from vanilla Stationeers are available under `ic.enums`:

```lua
local LT  = ic.enums.LogicType         -- On, Off, Temperature, Pressure, ...
local LST = ic.enums.LogicSlotType      -- Occupied, Quantity, Charge, ...
local LBM = ic.enums.LogicBatchMethod   -- Average, Sum, Minimum, Maximum
local LRM = ic.enums.LogicReagentMode   -- TotalContents, ...
local SI  = ic.enums.SorterInstruction  -- Logic Sorter stack opcodes (device memory)
local CO  = ic.enums.ConditionOperation  -- Packed compare ops (Equals, Greater, ...)
```

Each enum table maps **name → integer**:

```lua
print(LT.Temperature)  -- prints the integer value
print(LT.On)           -- prints the integer value
```

**Many gas and liquid ratios** are available under `ic.enums.LogicType` (including hydrazine, helium, silanol, hydrochloric acid, ozone, liquid forms, and pipe `Input` / `Output` style names). The optional **`gas` library** in `Examples/LibraryModule_Gas.lua` maps `gas.TYPE` flags to the matching ratio name for use with `read()`.

**Logic Sorter:** `ic.enums.SorterInstruction` exposes the game's sorter opcode names (`None`, `FilterPrefabHashEquals`, `FilterPrefabHashNotEquals`, and so on). `ic.enums.ConditionOperation` exposes `Equals`, `Greater`, `Less`, and `NotEquals` for the compare mode embedded in packed stack words. Use them with `mem_put` / `mem_get` on the sorter's device index; you still pack each 64-bit program word yourself (same layout as IC10 `put` on the sorter pin). The community wiki "Logic Sorter" page documents the full row layout.

Speaker modes use **`ic.enums.SoundAlert`** (same pattern: name to integer for `write(..., LogicType.Mode, ...)`).

Constants are under `ic.const`:

```lua
local DB = ic.const.BASE_UNIT_INDEX      -- Housing device index (typically 6)
local BN = ic.const.BASE_NETWORK_INDEX   -- Base network index
```

All vanilla IC10 `define` constants are also available:

```lua
local pi = ic.const.pi    -- If defined by the game
```

---

## 6. Batch Operations

Batch operations read/write across **all devices of a given type** on the data network.

### Reading in Batch

```lua
local LT  = ic.enums.LogicType
local LBM = ic.enums.LogicBatchMethod

-- Get the average temperature of all gas sensors on the network
local sensorHash = hash("StructureGasSensor")
local avgTemp = batch_read(sensorHash, LT.Temperature, LBM.Average)

-- With a name filter (only sensors labelled "Zone A")
local nameHash = hash("Zone A")
local avgTemp = batch_read_name(sensorHash, nameHash, LT.Temperature, LBM.Average)

-- Batch slot read
local occupied = batch_read_slot(sensorHash, 0, ic.enums.LogicSlotType.Occupied, LBM.Sum)
```

### Writing in Batch

```lua
-- Turn on all lights of a certain type
local lightHash = hash("StructureWallLight")
batch_write(lightHash, LT.On, 1)

-- With name filter
batch_write_name(lightHash, hash("Hallway"), LT.On, 1)

-- Batch slot write
batch_write_slot(lightHash, 0, ic.enums.LogicSlotType.On, 1)
```

### Batch Methods

| Method | Description |
|--------|-------------|
| `LBM.Average` | Average of all matching values |
| `LBM.Sum` | Sum of all matching values |
| `LBM.Minimum` | Smallest value |
| `LBM.Maximum` | Largest value |

> **Note:** The optional `networkIndex` parameter on batch functions is a **StationeersLua extension**. Vanilla IC10 batch always uses the housing's device list.

---

## 7. Slots & Reagents

### Slot Operations

Devices have **slots** (e.g., inventory slots, gas canister ports). Read/write slot properties using `LogicSlotType`:

```lua
local LST = ic.enums.LogicSlotType

-- Check if slot 0 on device d0 is occupied
local occ = read_slot(0, 0, LST.Occupied)

-- Read the quantity in slot 1 of device d2
local qty = read_slot(2, 1, LST.Quantity)

-- Write to a slot
write_slot(0, 0, LST.On, 1)

-- By reference ID
local qty = read_slot_id(deviceId, 0, LST.Quantity)
write_slot_id(deviceId, 0, LST.On, 1)
```

### Reagent Operations

```lua
local LRM = ic.enums.LogicReagentMode

-- Read reagent contents from device on d0
local amount = read_reagent(0, LRM.TotalContents, reagentHash)

-- Get the reagent → prefab hash mapping table
local map = rmap(0)
for reagentHash, prefabHash in pairs(map) do
    print(reagentHash .. " -> " .. prefabHash)
end
```

---

## 8. Memory & Stack

### Chip Internal Memory

Each chip has 512 memory addresses (0–511) that persist across ticks (and across save/load via vanilla persistence):

```lua
-- Read from chip memory address 0
local value = mem_read(0)

-- Write to chip memory address 10
mem_write(10, 42.5)

-- Clear all chip memory
mem_clear()
```

> **Housing LED note:** `mem_read`, `mem_write`, and `mem_clear` flash the IC housing memory light, matching the memory-style operations in vanilla.

### External Device Memory

Read/write another device's memory:

```lua
-- Read address 5 from device on d0
local value = mem_get(0, 5)

-- Write value to address 5 on device d0
mem_put(0, 5, 100)

-- Clear all memory on device d0
mem_clear_device(0)

-- By reference ID
local value = mem_get_id(deviceId, 5)
mem_put_id(deviceId, 5, 100)
mem_clear_id(deviceId)
```

### Stack Operations

The chip has an internal stack (shared with memory). These map directly to IC10 `push`/`pop`/`peek`/`poke`:

```lua
stack_push(42)          -- Push value onto stack
local top = stack_peek() -- Read top without removing
local val = stack_pop()  -- Pop from top

stack_poke(5, 100)      -- Write directly to stack address 5

-- Stack/return address pointers
local sp = stack_get_sp()
stack_set_sp(0)

local ra = stack_get_ra()
stack_set_ra(0)
```

> **Note:** In Lua, you'll almost always use local variables and tables instead of the IC10 stack. These functions exist for IC10 compatibility and for communicating with vanilla IC10 chips via shared memory.

> **Housing LED note:** `stack_push`, `stack_pop`, and `stack_peek` flash the IC housing memory light like vanilla `push` / `pop` / `peek`. `stack_poke` does **not** flash, matching vanilla `poke`.

---

## 9. Bitwise Operations

StationeersLua provides 53-bit-safe bitwise operations (matching IC10's numeric precision):

```lua
local result = bit_and(a, b)    -- Bitwise AND
local result = bit_or(a, b)     -- Bitwise OR
local result = bit_xor(a, b)    -- Bitwise XOR
local result = bit_nor(a, b)    -- Bitwise NOR
local result = bit_not(a)       -- Bitwise NOT

local result = bit_sll(a, n)    -- Shift left logical
local result = bit_srl(a, n)    -- Shift right logical (unsigned)
local result = bit_sra(a, n)    -- Shift right arithmetic (signed)

-- Extract a bit field: n bits starting at position pos
local field = bit_ext(value, pos, len)

-- Insert src into dst at position pos, width len
local result = bit_ins(dst, src, pos, len)
```

**Example: Packing flags into a single number**

```lua
local flags = 0
flags = bit_or(flags, bit_sll(1, 0))  -- Set bit 0 (power on)
flags = bit_or(flags, bit_sll(1, 3))  -- Set bit 3 (alert active)

-- Check if bit 3 is set
if bit_and(flags, bit_sll(1, 3)) ~= 0 then
    print("Alert is active")
end
```

---

## 10. String & Hash Utilities

```lua
-- Hash a string (Animator.StringToHash — same as IC10 HASH())
local h = hash("StructureGasSensor")

-- Get the prefab name from a known hash (returns nil if unknown)
local name = prefab_name(h)

-- Pack a short string into a number (ASCII-6 encoding, up to ~10 chars)
local packed = pack_ascii6("HELLO")
local str = unpack_ascii6(packed)  -- "HELLO"

-- Strip Unity rich-text color tags from a string
local clean = strip_color_tags("<color=#FF0000>Error</color>")
-- clean == "Error"

-- Convert a float to a 53-bit integer (truncating fractional part)
local int = to_int53(42.7)  -- 42
```

---

## 11. Control Flow — sleep, yield, tick

### `yield()`

Pauses the current execution context until the next game tick. Works in the main coroutine, inside `tick()`, and inside user-created coroutines:

```lua
while true do
    -- This body runs once per tick
    local temp = read(0, ic.enums.LogicType.Temperature)
    print("Temp: " .. tostring(temp))
    yield()
end
```

### `sleep(seconds)`

Pauses the current execution context for a real-time duration. The runtime counts down across ticks. Works in the main coroutine, inside `tick()`, and inside user-created coroutines:

```lua
print("Starting...")
sleep(5)
print("5 seconds later!")
```

Each execution context sleeps independently — sleeping in `tick()` does not freeze the main coroutine, and sleeping in a user coroutine does not freeze either.

### `sleep()` and `yield()` in User Coroutines

When you call `sleep()` or `yield()` inside a coroutine you created with `coroutine.create()`, the runtime automatically tracks and resumes it:

```lua
local function worker(name, interval)
    while true do
        print(name .. " working")
        sleep(interval)
    end
end

local fast = coroutine.create(worker)
local slow = coroutine.create(worker)
coroutine.resume(fast, "fast", 1)   -- starts, runs until first sleep(1)
coroutine.resume(slow, "slow", 5)   -- starts, runs until first sleep(5)

-- Both coroutines are now managed by the runtime.
-- "fast" resumes every ~1s, "slow" every ~5s, independently.
-- The main chunk and tick() continue running normally.
```

Key points:
- The runtime auto-resumes sleeping user coroutines each tick. Do **not** manually `coroutine.resume()` a coroutine that is sleeping — the runtime handles it.
- Up to 32 user coroutines can be sleeping simultaneously (exceeding this throws an error).

### `tick(dt)`

If you define a global function named `tick`, it's called automatically every game tick. `sleep()` and `yield()` work inside it — when `tick()` yields, its coroutine is suspended and resumed on the next eligible tick:

```lua
function tick(dt)
    -- dt = seconds since last tick (~0.5s typically)
    print("Delta: " .. dt)
end
```

Example with sleep inside `tick()`:

```lua
function tick(dt)
    write(0, ic.enums.LogicType.On, 1)
    sleep(2)
    write(0, ic.enums.LogicType.On, 0)
    sleep(2)
end
```

### `throw(message)`

Immediately throws a Lua runtime error:

```lua
throw("something went terribly wrong")
```

### `hcf()`

**Halt and Catch Fire** — permanently destroys the chip:

```lua
hcf()  -- The chip is gone. No undo.
```

---

## 12. Events

Register handlers for custom events fired by other mods or the game:

```lua
-- Register by function reference
ic.events.on("myEvent", function(arg)
    print("Event received with arg: " .. tostring(arg))
end)

-- Register by function name (survives save/load better)
function handleMyEvent(arg)
    print("Got event: " .. tostring(arg))
end
ic.events.on("myEvent", "handleMyEvent")

-- Unregister
ic.events.off("myEvent")
```

Events are processed at the **start of each tick**, before the main coroutine resumes and before `tick(dt)` is called.

> Events are primarily used by companion mods (like ScriptedScreens) to deliver UI input events to scripts. The base game does not fire Lua events on its own.

---

## 13. Networking — Direct Messaging

Lua chips on the **same data network** can send messages to each other. All networking is server-authoritative and scoped to the physical data cable network (including bridged networks).

### Setup

```lua
-- Get your own endpoint ID (the housing's ReferenceId)
local myId = ic.net.id()
print("My endpoint: " .. tostring(myId))

-- List all Lua chip peers on the network
local peers = ic.net.peers()
for _, p in ipairs(peers) do
    print(string.format("  Peer: %s (id=%d)", p.name, p.id))
end
```

### Sending Messages

```lua
-- Send to a specific target by name (set via labeller on the housing)
ic.net.send("ReceiverChip", "alerts", { temp = 300, status = "critical" })

-- Send to a specific target by ReferenceId
ic.net.send(targetId, "alerts", "Hello!")

-- Broadcast to ALL Lua chips on the network
local delivered = ic.net.broadcast("status", { online = true })
print("Delivered to " .. delivered .. " peers")
```

### Receiving Messages

**Option A: Handler function** (recommended)

```lua
-- Register a listener for a channel
ic.net.listen("alerts", function(fromId, fromName, payload)
    print("Alert from " .. fromName .. ": " .. tostring(payload))
end)

-- Handler by name (persists better across save/load)
function onAlert(fromId, fromName, payload)
    print("Alert from " .. fromName)
end
ic.net.listen("alerts", "onAlert")

-- Unregister
ic.net.listen("alerts", nil)
```

**Option B: Poll-style** (for advanced use)

```lua
while true do
    local fromId, fromName, channel, payload = ic.net.recv()
    if fromId ~= nil then
        print("Message on " .. channel .. " from " .. fromName)
    end
    yield()
end
```

### Channel Notes

- Channels are **strings** (e.g. `"alerts"`, `"sensor_data"`).
- You can pass an **integer** channel (e.g. `1000`) — it's treated as `"1000"`.
- Max payload size: **128 KB** (MessagePack encoded).
- Supported payload types: `nil`, `boolean`, `number`, `string`, `table`.
- Functions, userdata, and cyclic tables are **not** supported.

---

## 14. Networking — Pub/Sub

Topic-based publish/subscribe on top of the data network. More flexible than direct messaging — publishers don't need to know subscribers, and subscribers use wildcard patterns.

### Publishing

```lua
-- Simple publish
ic.net.publish("sensors/temp", { temp = 300, zone = "HAB-1" })

-- Publish with options
ic.net.publish("sensors/temp", { temp = 300 }, {
    retain = true,        -- New subscribers get the last retained value immediately
    ttl = 60,             -- Retained message expires after 60 seconds
    include_self = false  -- Don't deliver to self (default)
})

-- Clear a retained message by publishing nil
ic.net.publish("sensors/temp", nil, { retain = true })
```

### Subscribing

```lua
-- Subscribe to an exact topic
ic.net.subscribe("sensors/temp", function(topic, payload, fromId, fromName, retained)
    local prefix = retained and "[RETAINED] " or ""
    print(prefix .. "Temp from " .. fromName .. ": " .. payload.temp)
end)

-- Subscribe with wildcards
-- * matches any sequence of characters
-- ? matches a single character
ic.net.subscribe("sensors/*", function(topic, payload, fromId, fromName, retained)
    print("Got " .. topic .. " from " .. fromName)
end)

-- Subscribe by handler name (better for save/load)
function onSensor(topic, payload, fromId, fromName, retained)
    print(topic .. ": " .. tostring(payload))
end
ic.net.subscribe("sensors/*", "onSensor")

-- Unsubscribe
ic.net.unsubscribe("sensors/*")
```

### Topic Rules

| Rule | Detail |
|------|--------|
| Max length | 128 characters |
| Wildcards | `*` (any sequence), `?` (single char) |
| Retained | New subscribers get the last retained value on subscription |
| TTL | Retained messages auto-expire after `ttl` seconds |
| Queue limit | 128 messages per subscriber queue (backpressure) |

---

## 15. Networking — RPC

Request/response pattern with correlation IDs and timeouts. Think of it as calling a function on another chip.

### Server Side (Register Methods)

```lua
-- Register an RPC method
ic.net.register("get_status", function(payload, fromId, fromName)
    print("get_status called by " .. fromName)

    local temp = read(0, ic.enums.LogicType.Temperature)
    local pressure = read(0, ic.enums.LogicType.Pressure)

    -- Return value becomes the response payload
    return {
        temp = temp,
        pressure = pressure,
        uptime = os.clock()
    }
end)

-- If the handler throws, the error is sent back to the caller
ic.net.register("set_mode", function(payload, fromId, fromName)
    if type(payload) ~= "table" or payload.mode == nil then
        error("expected payload with 'mode' field")
    end
    mem_write(0, payload.mode)
    return { ok = true }
end)

-- Unregister a method
ic.net.unregister("get_status")

-- Keep alive to process incoming requests
while true do
    yield()
end
```

Handlers may call `yield()` or `sleep()` before returning. The runtime resumes the handler through the RPC path only, honors the sleep duration, and delivers the return value or error to the caller when the handler finishes:

```lua
ic.net.register("slow_status", function(payload, fromId, fromName)
    sleep(2)
    return { ok = true, from = fromName }
end)
```

### Client Side (Call Methods)

```lua
-- Call by target name or ID
ic.net.request("ServerChip", "get_status", nil,
    function(ok, payload, err, fromId, fromName)
        if ok then
            print("Temp: " .. tostring(payload.temp))
            print("Pressure: " .. tostring(payload.pressure))
        else
            print("RPC failed: " .. tostring(err))
        end
    end,
    10  -- Timeout in seconds (default 10, max 120)
)

-- Call with parameters
ic.net.request("ServerChip", "set_mode", { mode = 3 },
    function(ok, payload, err)
        if ok then print("Mode set!") end
    end
)

-- Keep alive to receive callbacks
while true do
    yield()
end
```

### RPC Rules

| Rule | Detail |
|------|--------|
| Method name max | 64 characters |
| Timeout | Default 10s, max 120s |
| Handler pauses | `yield()` and `sleep()` are allowed; return value and errors reach the caller when the handler completes |
| Error handling | If handler throws, `ok = false` and `err` contains the message |
| Timed-out requests | Silently expired (no callback) |

---

## 16. Networking — Pack/Unpack

Serialize Lua values to/from base64-encoded MessagePack. Useful for storing structured data in chip memory or transferring via non-network channels.

```lua
-- Pack a Lua table to a base64 string
local packed = ic.net.pack({ x = 1, y = 2, items = {"a", "b"} })
print(type(packed))  -- "string"

-- Unpack back to a Lua value
local value = ic.net.unpack(packed)
print(value.x, value.y)  -- 1  2
print(value.items[1])     -- "a"
```

Supported types: `nil`, `boolean`, `number` (double), `string`, `table` (array or map).

---

## 17. Temperature Conversion

Universal temperature conversion via `util.temp(value, from, to)`.  
Units: `"K"` (Kelvin), `"C"` (Celsius), `"F"` (Fahrenheit). Case-insensitive.

```lua
-- Stationeers sensors report Kelvin — convert to Celsius
local tempK = ic.read(0, ic.enums.LogicType.Temperature)
local tempC = util.temp(tempK, "K", "C")
print(tempC)  -- e.g. 21.85

-- Celsius to Fahrenheit
local tempF = util.temp(tempC, "C", "F")
print(tempF)  -- e.g. 71.33

-- Fahrenheit back to Kelvin
local tempK2 = util.temp(tempF, "F", "K")
print(tempK2)  -- e.g. 295.0
```

> **Tip:** The `from` parameter defaults to `"K"` and `to` defaults to `"C"`, so
> `util.temp(295)` is a quick Kelvin→Celsius shorthand.

### Time Utilities

Server-authoritative game time helpers (world elapsed time + day count):

```lua
local t = util.game_time()  -- seconds since world start
local day = util.days_past() -- integer day count
print(t, day)
```

Orbital time-of-day clock helpers (normalized + formatted clock):

```lua
local tod = util.time_of_day()  -- 0..1 (fraction of day)
local clock24 = util.clock_time()            -- "HH:MM"
local clock12 = util.clock_time("hh:MM A")   -- "HH:MM AM/PM"
local clock24s = util.clock_time("HH:MM:ss") -- with seconds
print(tod, clock24, clock12, clock24s)
```

Clock pattern tokens:
- `HH` = 24h hour
- `hh` = 12h hour
- `MM` / `mm` = minutes
- `ss` = seconds
- `A` / `a` = AM/PM

---

## 18. JSON Utilities

General-purpose JSON encode/decode under the `util` namespace (not under `ic`):

```lua
-- Encode a Lua value to JSON
local json = util.json.encode({ name = "test", value = 42, tags = {1, 2, 3} })
print(json)  -- {"name":"test","value":42,"tags":[1,2,3]}

-- Decode JSON to a Lua value
local obj = util.json.decode('{"temp": 300, "status": "ok"}')
print(obj.temp)    -- 300
print(obj.status)  -- "ok"
```

---

## 19. Save/Load Persistence

### What's Automatic

The game automatically persists:
- The chip's **source code**
- IC10-style state: **registers, stack, memory** (the 512-address memory)

So `mem_read`/`mem_write` values survive save/load with no extra work.

### What's NOT Automatic

**Lua local/global variables are NOT persisted.** After a load, your script re-initializes from scratch (module-level code runs again).

### Load order

On load: **hydrate `ic.persist` → compile → init → optional legacy `deserialize(blob)` → tick loop**. Keys from `ic.persist` are available during module-level init. Legacy `deserialize` still runs after init only if you define it. Full guide: `StationeersLuaDocs/docs/guide/persistence.md`. Example: `Examples/PersistExample.lua`.

### Opt-In Persistence (`ic.persist`)

String key/value store; survives save/load, IC housing power off/on (chip stays in housing), and chip pull/reinsert when source is unchanged:

```lua
local KEY = "settings"

local function load_settings()
    if not ic.persist.has(KEY) then return nil end
    local raw = ic.persist.get(KEY)
    if type(raw) ~= "string" then return nil end
    local ok, t = pcall(util.json.decode, raw)
    return ok and t or nil
end

local mode = "auto"
local setpoint = 22.0
local saved = load_settings()
if saved then
    mode = saved.mode or mode
    setpoint = saved.setpoint or setpoint
end

function tick(dt)
    local ok, raw = pcall(util.json.encode, { mode = mode, setpoint = setpoint })
    if ok and raw then ic.persist.set(KEY, raw) end
end
```

| API | Description |
|------|-------------|
| `ic.persist.set(key, value)` | Store string; returns `true` on success |
| `ic.persist.get(key)` | Read string or `nil` |
| `ic.persist.has(key)` | Key exists |
| `ic.persist.delete(key)` | Remove one key |
| `ic.persist.clear()` | Remove all keys for this chip |

Keys starting with `__` are reserved. Limits: BepInEx section **Lua Persist** (`MaxKeyLength`, `MaxValueLength`, `MaxTotalBytes`; defaults 128 / 8192 / 32768). Server/host config applies in multiplayer.

### Legacy `serialize()` / `deserialize(blob)`

Still supported (stored in KV under the hood). Prefer `ic.persist` for new scripts. Legacy hooks run on save/power-off (`serialize`) and after init on load (`deserialize`); must be synchronous (no `yield`/`sleep`).

---

## 20. Debugging

### `print()`

Writes to the **Lua Debugger Logs** tab (per-chip, bounded, cleared on power cycle):

```lua
print("Temperature:", temp, "Pressure:", pressure)
-- Output: Temperature:	300	Pressure:	101.3
```

Multiple arguments are tab-separated.

### Lua Debugger Motherboard

If you have the **MotherboardLuaDebugger** installed in a computer on the same data network, it provides:
- Current compile/runtime error state
- Full Lua exception message and traceback
- Chip memory window (peek at mem addresses)
- Stack pointer (`sp`) and return address (`ra`)
- Event/net queue sizes and sleep state
- A "Copy" button to copy the snapshot to clipboard

### VS Code Debugger

The **VS Code extension** supports attaching a full debugger to running Lua chips — breakpoints, pause/step/continue, stack frames, scopes, and variable inspection. See [Section 28: VS Code Extension](#28-vs-code-extension) for details.

### Checking Device Connections

```lua
-- Print all device info for debugging
for i = 0, 5 do
    local id = device_id(i)
    local name = device_name(i)
    print(string.format("d%d: id=%s name=%s", i, tostring(id), tostring(name)))
end
```

### Checking Nil Returns

Many `read*` functions return `nil` when a device is missing:

```lua
local temp = read(0, LT.Temperature)
if temp == nil then
    print("Device on d0 is not connected or doesn't support Temperature")
else
    print("Temperature: " .. temp)
end
```

---

## 21. Sandbox & Limits

Lua chip scripts run in a **deterministic sandbox**:
- Background async work during a tick is not supported; use coroutine suspension via `sleep` / `yield` instead.
- `print(...)` writes to the **Lua Debugger Logs** tab (per-chip, bounded, cleared on power cycle/runtime reset).
- File I/O, module loading, and process-affecting operations are disabled.

### Instruction Limits

| Phase | Budget |
|-------|--------|
| Initialization (module-level code) | 500,000 instructions (default) |
| Per tick (coroutine + tick + events) | 50,000 instructions (default) |

In the in-game mod configuration (BepInEx), category **[Lua VM]**: `InitInstructionLimit` and `TickInstructionLimit` override these defaults. Only the simulation host runs chip Lua, so in multiplayer only the server or host settings apply.

Exceeding limits triggers a runtime error on the chip.

### Sandboxed Libraries

**Available:**

| Library | Notes |
|---------|-------|
| `math` | Full: `math.sin`, `math.floor`, `math.random`, etc. |
| `string` | Full: `string.format`, `string.sub`, `string.find`, etc. |
| `table` | Full: `table.insert`, `table.remove`, `table.sort`, etc. |
| `coroutine` | Full: `coroutine.create`, `coroutine.resume`, `coroutine.yield`, etc. `sleep`/`yield` work inside user coroutines. |
| `utf8` | UTF-8 string handling |
| `debug` | **Not available** (removed from the chip environment) |
| `os.clock` | High-resolution timer |
| `os.time` | Current Unix timestamp |
| `os.date` | Date/time formatting |
| `os.difftime` | Time difference |
| `pcall`, `xpcall` | Protected calls |
| `tonumber`, `tostring`, `type` | Standard conversions |
| `pairs`, `ipairs`, `next` | Table iteration |
| `select`, `unpack`, `rawget`, `rawset` | Table utilities |
| `load`, `pcall` | Dynamic code loading (from strings only) |
| `util.json` | JSON encode/decode |

**Blocked:**

| Blocked | Reason |
|---------|--------|
| `io` | Filesystem access |
| `debug` | Introspection / hooks not supported on chips |
| `package` | Filesystem module loading (replaced by data-network `require()`) |
| `dofile`, `loadfile` | Filesystem access |
| `os.execute`, `os.exit`, `os.remove`, `os.rename` | Process/filesystem mutation |
| `os.tmpname`, `os.setlocale`, `os.getenv` | System interaction |

---

## 22. Error Handling Patterns

### Nil-checking Reads

```lua
local temp = read(0, LT.Temperature)
if temp == nil then
    -- Device missing, disconnected, or doesn't support this logic type
    return
end
```

### Protected Calls for Writes

```lua
local ok, err = pcall(function()
    write(0, LT.On, 1)
end)
if not ok then
    print("Write failed: " .. tostring(err))
end
```

### Network Error Handling

```lua
local ok, err = pcall(function()
    ic.net.send("Target", "channel", { data = 123 })
end)
if not ok then
    print("Network send failed: " .. tostring(err))
end
```

### NaN Detection

```lua
local value = read(0, LT.Temperature)
if value ~= nil and value == value then  -- NaN check: NaN ~= NaN
    -- value is a valid number
end
```

---

## 23. Common Patterns & Recipes

### Thermostat

```lua
local LT = ic.enums.LogicType

local setpoint = 22.0  -- Target temperature in Celsius
local hysteresis = 1.0  -- Deadband to prevent rapid switching

function tick(dt)
    local temp = read(0, LT.Temperature)
    if temp == nil then return end

    -- Convert Kelvin to Celsius if needed
    -- temp = temp - 273.15

    local cooling = read(1, LT.On) or 0

    if temp > setpoint + hysteresis then
        write(1, LT.On, 1)  -- Turn on cooling
    elseif temp < setpoint - hysteresis then
        write(1, LT.On, 0)  -- Turn off cooling
    end
end
```

### Solar Tracker (Simple)

```lua
local LT  = ic.enums.LogicType
local LBM = ic.enums.LogicBatchMethod

local panelHash = hash("StructureSolarPanel")

function tick(dt)
    local sensorV = read(0, LT.Vertical)
    local sensorH = read(0, LT.Horizontal)
    if sensorV == nil or sensorH == nil then return end

    batch_write(panelHash, LT.Vertical, sensorV + 90)
    batch_write(panelHash, LT.Horizontal, sensorH)
end
```

### Airlock Controller

```lua
local LT = ic.enums.LogicType

local INNER_DOOR = 0   -- d0
local OUTER_DOOR = 1   -- d1
local VENT = 2          -- d2

local function close_all()
    write(INNER_DOOR, LT.Open, 0)
    write(OUTER_DOOR, LT.Open, 0)
end

local function depressurize()
    close_all()
    write(VENT, LT.On, 1)
    write(VENT, LT.Mode, 0)  -- Outward mode
    sleep(5)
    write(VENT, LT.On, 0)
end

local function pressurize()
    close_all()
    write(VENT, LT.On, 1)
    write(VENT, LT.Mode, 1)  -- Inward mode
    sleep(5)
    write(VENT, LT.On, 0)
end

-- Simple cycle: open inner, wait, cycle, open outer, wait, cycle back
while true do
    pressurize()
    write(INNER_DOOR, LT.Open, 1)
    sleep(5)
    close_all()
    depressurize()
    write(OUTER_DOOR, LT.Open, 1)
    sleep(5)
    close_all()
end
```

### Sensor Hub (Networking)

```lua
-- Publish local sensor data to the network every 5 seconds
local LT = ic.enums.LogicType

while true do
    local temp = read(0, LT.Temperature) or 0
    local pressure = read(0, LT.Pressure) or 0

    ic.net.publish("sensors/local", {
        temp = temp,
        pressure = pressure,
    }, { retain = true, ttl = 30 })

    sleep(5)
end
```

### Accumulating a Rolling Average

```lua
local LT = ic.enums.LogicType

local buffer = {}
local WINDOW = 20

function tick(dt)
    local temp = read(0, LT.Temperature)
    if temp == nil then return end

    table.insert(buffer, temp)
    if #buffer > WINDOW then
        table.remove(buffer, 1)
    end

    local sum = 0
    for _, v in ipairs(buffer) do sum = sum + v end
    local avg = sum / #buffer

    write(ic.const.BASE_UNIT_INDEX, LT.Setting, avg)
end
```

### Using Chip Memory to Persist a Counter

```lua
-- Counter that survives save/load via chip memory (no ic.persist needed)
local ADDR_COUNT = 0

local count = mem_read(ADDR_COUNT) or 0

function tick(dt)
    count = count + 1
    mem_write(ADDR_COUNT, count)
    write(ic.const.BASE_UNIT_INDEX, LT.Setting, count)
end
```

---

## 24. Migrating from IC10

If you're coming from IC10 assembly, here's a quick cheat sheet:

| IC10 | Lua |
|------|-----|
| `alias Temp r0` | `local temp` |
| `define PI 3.14` | `local PI = 3.14` |
| `l r0 d0 Temperature` | `local temp = read(0, LT.Temperature)` |
| `s d0 On 1` | `write(0, LT.On, 1)` |
| `ls r0 d0 0 Occupied` | `local occ = read_slot(0, 0, LST.Occupied)` |
| `lb r0 HASH("GasSensor") Temperature 2` | `local avg = batch_read(hash("GasSensor"), LT.Temperature, LBM.Average)` |
| `push 42` | `stack_push(42)` |
| `pop r0` | `local val = stack_pop()` |
| `move r0 r1` | `local a = b` |
| `add r0 r1 r2` | `local a = b + c` |
| `and r0 r1 r2` | `local a = bit_and(b, c)` |
| `j label` | `while true do ... end` or `goto label` |
| `beq r0 0 label` | `if r0 == 0 then ... end` |
| `sleep 5` | `sleep(5)` |
| `yield` | `yield()` |
| `hcf` | `hcf()` |

### Key Differences

1. **No registers** — Use Lua variables. Far more readable and no 16-register limit.
2. **No line numbers** — Use functions, loops, and `if/else`. No `j 5` or `beq r0 0 15`.
3. **Nil instead of errors** — `read()` returns `nil` for missing devices instead of crashing.
4. **Strings are native** — No ASCII-6 packing needed for most things (but available via `pack_ascii6` for IC10 interop).
5. **Tables** — Use Lua tables for data structures. IC10 has only 16 registers and a 512-value stack.
6. **Functions** — Define reusable functions instead of `jal`/`j ra` jump patterns.
7. **Error handling** — Use `pcall()` for protected calls instead of branching on error codes.

### Network / Channel Addressing

IC10 uses `d0:0` connection syntax and logic types like `Channel0..Channel7`.

In Lua, most `read`/`write` variants accept an optional `networkIndex` parameter:

```lua
local LT = ic.enums.LogicType

-- Read from device on d0, network index 0
local value = read(0, LT.Temperature, 0)

-- Read all channels 0..7 from db:0 into a table
local channels = {}
for i = 0, 7 do
    channels[i] = read(ic.const.BASE_UNIT_INDEX, LT.Channel0 + i, 0)
end
```

### Numeric Formats

IC10 supports `$` hex and `%` binary literals. Lua equivalents:

| IC10 | Lua |
|------|-----|
| `$FF` | `0xFF` |
| `$E1B2` | `0xE1B2` |
| `%101010` | No `0b` binary literals in Lua 5.2 — use `tonumber("101010", 2)` |

### CRC Hashes

IC10 docs describe hashes as CRC-32 checksums. StationeersLua provides `hash()` to generate the same values:

```lua
local sensorHash = hash("StructureGasSensor")
local nameHash = hash("Sensor 1")
```

For the full line-by-line mapping, see [`MAPPING.MD`](MAPPING.MD).

---

## 25. Library Chips — require()

Library chips let you write **reusable Lua modules** that other chips can load via `require()`. A library chip is a passive source code store — it has **no Lua VM of its own**. When another chip calls `require("modname")`, the library source is compiled and executed inside the *requesting* chip's VM.

### Creating a Library Chip

Add a `--@module <name>` annotation anywhere in the script:

```lua
--@module atmos
-- Atmosphere utilities for Stationeers

local atmos = {}

atmos.MIN_PRESSURE_KPA = 20
atmos.MAX_TEMP_K = 323.15

function atmos.is_breathable(pressure, temp, co2)
    if pressure < atmos.MIN_PRESSURE_KPA then return false, "low pressure" end
    if temp > atmos.MAX_TEMP_K then return false, "too hot" end
    if co2 > 2.0 then return false, "CO2 toxicity" end
    return true, "safe"
end

return atmos
```

Put this on a Lua chip in an IC Housing on the same data cable network as consumer chips.

### Using a Library

```lua
local atmos = require("atmos")

local safe, reason = atmos.is_breathable(101, 295, 0.5)
print(safe and "OK" or reason)
```

### How It Works

1. **Detection**: When a chip's source is saved, StationeersLua scans for `--@module` annotations. If found, the chip is registered as a library chip and **no VM is created**.
2. **Syntax check**: The library source is compiled in a temporary state to catch syntax errors early. Errors are flagged on the library chip's housing.
3. **Network search**: When `require("modname")` is called, the system searches the requesting chip's data cable network for a library chip exporting that module.
4. **Compilation**: The library source is compiled inside the requesting chip's VM using Lua's `load()`, with a chunk name like `@HousingName:modname` for clear error attribution.
5. **Caching**: The module return value is cached per-VM. Subsequent `require()` calls return the cached value instantly.

### Multi-Module Chips

A single chip can export multiple modules:

```lua
--@module pid
--@module utils

local M = {}

M.pid = { ... }   -- PID controller module
M.utils = { ... } -- Utility functions

return M  -- Must return a table with keys matching module names
```

When `require("pid")` is called, the source runs once and all declared modules are cached from the returned table.

### Hot Reload

Pass `true` as a second argument to force re-loading:

```lua
local atmos = require("atmos", true)  -- Clears cache, re-compiles from library source
```

Note that this will cause the requiring script to restart entirely when the code on the library chip is updated.

### Error Handling

| Scenario | Behavior |
|----------|----------|
| Module not found on network | `error("module 'x' not found on data network")` |
| Library chip has syntax errors | `error("module 'x' has syntax errors...")` |
| Library source fails to compile | `error("require 'x': compile error: ...")` |
| Runtime error in library init | Standard Lua error with traceback pointing to `@HousingName:modname` |

### Configuration

| Config Entry | Default | Description |
|--------------|---------|-------------|
| `AllowLibraryChips` | `true` | Enable/disable the library chip system |
| `AllowMultiModule` | `true` | Allow multiple `--@module` annotations per chip |
| `LibraryLoadInstructionBudget` | `200000` | Max instructions for loading a library module |

### Key Rules

- Library chips have **no VM** — they don't tick, can't read devices, and don't consume CPU.
- Scope is per **data cable network** — only chips on the same physical cable segment can see each other.
- The library source runs inside the **requesting chip's** VM, so `read()`, `write()`, `ic.*` all refer to the consumer's devices.
- Library chips persist via existing chip source save/load — no new save data needed.
- In multiplayer, the module index is rebuilt server-side on world load.

---

## 26. Companion Mods

### ScriptedScreens

For **custom touchscreen UIs** on computer consoles and tablets, install **ScriptedScreens**. It adds:
- Declarative UI elements (buttons, sliders, labels, progress bars, charts, tables, gauges)
- Touch and keyboard input
- Canvas drawing for custom graphics
- Grid and flex layout helpers
- 60fps frame callbacks for games and animations

The `ss` API is injected alongside `ic` when a Lua chip is hosted in a ScriptedScreens-compatible device:

```lua
local ui = ss.ui.surface("main")
ss.ui.activate("main")
ui:clear()

ui:element({
    id = "hello",
    type = "label",
    rect = { unit = "px", x = 10, y = 100, w = 200, h = 30 },
    props = { text = "Hello World!" },
    style = { font_size = 18, color = "#22C55E" }
})

ui:commit()
```

See the ScriptedScreens `GUIDE.MD` for full documentation.

---

## 27. MCP Server & AI Editor Integration

StationeersLua includes a built-in **Model Context Protocol (MCP)** server that exposes game state, chip discovery, code read/write, and debug surfaces to AI-aware editors such as Cursor, Windsurf, and other MCP clients.

### How It Works

The HTTP listener runs locally inside your game client (default port `3030`). It exposes two independent surfaces on the same port:

- **MCP JSON-RPC** — for AI editors (Cursor, Windsurf, Claude Code, etc.)
- **Extension REST** — for the VS Code extension (chip browsing, code sync, debugger attach)

Each surface is enabled independently via its own config toggle. Both share the same port.

### MCP Tools

| Tool | Description |
|------|-------------|
| `get_editor_state` | Query editor selection, network scope, chip list, and `wireless_remote_access_only` when only the suit wireless board supplies scope |
| `get_editor_code` | Read the live IC editor draft text (not the compiled chip source) |
| `set_editor_code` | Update the IC editor draft — does **not** compile or export to the chip |
| `list_chips` | Enumerate accessible Lua chips on the current data network(s) |
| `get_chip_code` | Read a chip's current source by ref ID |
| `set_chip_code` | Write source to a chip by ref ID — compiles and exports immediately |
| `patch_chip_code` | Apply exact substring replacements to a chip's source without rewriting the entire file |
| `get_chip_errors` | Retrieve error details for chips with debugger authority |
| `get_chip_logs` | Get buffered `print()` / script log output for a chip |
| `list_library_modules` | List library chip modules visible on the current network(s) |
| `get_network_devices` | Enumerate devices on the current data network |
| `get_all_network_devices` | List all data cable networks in the world and their connected devices |
| `read_device_value` | Read a logic value from a device by reference ID and LogicType name |
| `get_device_logic_types` | Get all readable and writable LogicType values for a device |
| `get_game_state` | Query world name, time, and other top-level game state |
| `search_docs` | Full-text search across all embedded documentation resources |
| `search_stationpedia` | Full-text search over the in-game Stationpedia encyclopedia |

`get_editor_state` (and REST `GET /api/editor`) include **`wireless_remote_access_only`**: `true` when MCP/REST scope comes from the **Wireless Development Board** alone — no IC motherboard editor open. In that mode `selected_chip_ref_id` and `selected_housing_*` are unset; the suit board is a network bridge, not a chip or housing. Use `network_id` / `network_names` for the connected data network.

When **both** `Enabled` and `EnableExtensionApi` are `true`, additional debugger tools are registered:

| Tool | Description |
|------|-------------|
| `get_debug_session_state` | Get the active VS Code debugger session state for an attached chip |
| `get_debug_stack_trace` | Get the stack trace for a paused chip in the active debugger session |
| `get_debug_scopes` | Get debugger scopes for a paused frame |
| `get_debug_variables` | Get debugger variables for a scope or variable reference |

### MCP Resources

| URI | Content |
|-----|---------|
| `stationeers://lua/readme` | MCP server README and recommended workflow |
| `stationeers://lua/guide` | Full StationeersLua scripting guide |
| `stationeers://lua/migration` | IC10 to Lua instruction-by-instruction guide |
| `stationeers://lua/api/logic` | Logic read/write and batch API reference |
| `stationeers://lua/api/device` | Device discovery and slot API reference |
| `stationeers://lua/api/memory` | Chip memory API reference |
| `stationeers://lua/api/network` | Inter-chip networking API reference |
| `stationeers://lua/api/http` | HTTP request API reference |
| `stationeers://lua/api/utility` | Utility functions reference |
| `stationeers://lua/api/events` | Event system reference |
| `stationeers://lua/api/library` | Library chip / `require()` reference |
| `stationeers://lua/enums/logic_type` | Complete `LogicType` enum values (`LT.*`) |
| `stationeers://lua/enums/logic_slot_type` | Complete `LogicSlotType` enum values (`LST.*`) |
| `stationeers://lua/enums/batch_method` | `LogicBatchMethod` enum values |
| `stationeers://lua/enums/sorter_instruction` | `SorterInstruction` enum (Logic Sorter stack opcodes) |
| `stationeers://lua/enums/condition_operation` | `ConditionOperation` enum (packed compare modes) |
| `stationeers://lua/examples/index` | Catalog of bundled example scripts |
| `stationeers://lua/examples/<path>` | Individual example files (`.lua`, `.ic10`, `.md`) |

### Configuration

All settings live in the StationeersLua config file under `[MCP Server]`:

| Setting | Default | Description |
|---------|---------|-------------|
| `Enabled` | `false` | Enable the MCP JSON-RPC surface for AI editors |
| `EnableExtensionApi` | `false` | Enable the REST surface for the VS Code extension |
| `Port` | `3030` | Shared HTTP listener port for both surfaces |
| `BindAddress` | `127.0.0.1` | Bind address for the HTTP listener |
| `AllowRemoteConnections` | `false` | Bind to all interfaces instead of localhost only |
| `AllowedBrowserOrigins` | `` (empty) | Comma-separated allowlist of browser `Origin` values permitted to call the listener. Empty blocks all browser origins (anti CSRF / DNS-rebinding). Native clients send no `Origin` and are unaffected. |
| `AllowNetworkChipAccess` | `false` | Master toggle for network-wide chip access |
| `AllowNetworkChipAccessOnlyForWirelessBoards` | `true` | When network access is enabled, restrict full network scope to the Wireless Development Board only |
| `AllowMultiplayerDebugProxy` | `false` | Allow multiplayer clients to proxy VS Code debugger traffic to the server |
| `EnableExperimentalDebugger` | `false` | **[Experimental]** Enable the VS Code DAP debugger. When disabled, debug endpoints and MCP debug tools are unavailable, and the Debug button is hidden in the Chip Explorer |
| `EnableLspServer` | `false` | Enable the LSP (Language Server Protocol) TCP server for VS Code. Provides Stationeers-specific completions, diagnostics, hover, and signature help |
| `LspPort` | `3031` | TCP port for the LSP server (must differ from the HTTP port) |
| `ExternalLuaLanguageServerPath` | *(empty)* | Optional full path to **lua-language-server** for the **in-game** IC10 Lua editor. When set, the mod registers `LuaFormatterExternalLsp` (vanilla `LSPFormatter` + stdio). When empty, the editor uses `LuaLanguageService` only. Does not change the VS Code TCP LSP |
| `ExternalLuaLanguageServerArguments` | *(empty)* | Optional arguments passed to `ExternalLuaLanguageServerPath` |
| `ExternalLuaLanguageServerWorkingDirectory` | *(empty)* | Optional working directory for that process (empty = directory of the executable) |

The HTTP listener only starts if at least one of `Enabled` or `EnableExtensionApi` is `true`. Dedicated servers **never** start the local HTTP listener.

The listener validates the HTTP `Host` header and rejects browser requests whose `Origin` is not listed in `AllowedBrowserOrigins`. CORS responses no longer use a wildcard.

---

## 28. VS Code Extension

The **StationeersLua VS Code extension** connects VS Code to the running game for external editing and debugging of Lua chips.

### Features

- **Chip Explorer** sidebar — browse accessible chips grouped by data cable network, with inline Pull/Export/Debug actions
- **Editor sync** — saving a file in VS Code updates the in-game editor draft (not a full export)
- **Explicit export** — compile code to the chip via command palette or sidebar action
- **Conflict detection** — tracks `source_version` to detect external changes from the in-game editor, AI editors, or other players
- **Debugger** — attach to running Lua chip runtimes with breakpoints, pause/step/continue, stack frames, scopes, and variable inspection
- **IntelliSense** — Lua type stubs for StationeersLua and ScriptedScreens APIs (via Sumneko Lua)
- **Stationeers LSP** — built-in language server providing Stationeers-specific completions, diagnostics, hover, and signature help (see [Section 30](#30-editor-intelligence-lsp))
- **Snippets** — 23 code snippets for common Stationeers Lua patterns
- **AI editor MCP config** — generates MCP config files for Cursor, Windsurf, Claude Code, and VS Code Copilot

### Setup

1. Install the extension in VS Code
2. Enable `EnableExtensionApi` in the StationeersLua mod config
3. Launch Stationeers and load a world
4. Run **StationeersLua: Connect to Game Server** from the command palette
5. Give the bridge a chip scope — either:
   - open the in-game **IC editor** on a computer and select a chip, hit edit to show editor UI in-game, **or**
   - wear a suit with the **Wireless Development Board** connected (with `AllowNetworkChipAccess` enabled — see [Section 29](#29-wireless-development-board))
6. Use the **Chips** sidebar to browse and open chips

You do not need the IC editor open when wireless remote access alone exposes the chips you care about.

### Status bar

When connected, the status bar summarizes context: **Wireless link** and the remote network name when only the suit board supplies scope; otherwise the in-game holder label when a chip is selected in the IC editor. The tooltip only shows a chip `(ref …)` when the game provides a real ref — no meaningless `ref null`.

### Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `stationeers-lua.gameServerUrl` | `http://127.0.0.1:3030` | Base URL for the in-game HTTP server |
| `stationeers-lua.syncOnSave` | `true` | Sync the in-game editor draft on file save |
| `stationeers-lua.autoRefreshChipExplorer` | `true` | Auto-poll chip explorer metadata |
| `stationeers-lua.chipExplorerRefreshIntervalMs` | `5000` | Poll interval in ms (1000–60000) |
| `stationeers-lua.lspPort` | `3031` | TCP port for the Stationeers LSP server (must match mod config `LspPort`) |

### Commands

| Command | Description |
|---------|-------------|
| Connect to Game Server | Establish connection to the StationeersLua HTTP server |
| Disconnect from Game Server | Drop the active connection |
| Refresh Chip Explorer | Force-refresh the chip tree |
| Open Chip | Pull a chip's source into a local temp file |
| Export Chip to Game | Compile and export local source to the chip |
| Pull Code from Chip | Refresh local file from the chip's compiled source |
| Debug Chip | Attach the VS Code debugger to a Lua chip |
| Configure AI Editor (MCP) | Generate MCP config for supported AI editors |

> **Note:** The VS Code debugger is an experimental feature — enable `EnableExperimentalDebugger` in the `[MCP Server]` config to use it. Debugging is Lua chips only — IC10 chips can be opened and exported but not debugged. In multiplayer, debug sessions are proxied through the mod's network layer when `AllowMultiplayerDebugProxy` is enabled on the server.

---

## 29. Wireless Development Board

The **Wireless Development Board** is a wearable EVA suit module that gives the MCP server and VS Code extension remote access to Lua chips on a powered omni transmitter's data network — without needing to stand at a computer with the IC editor open.

### Setup

1. Print the board at an **Electronics Printer**
2. Insert the board into the dedicated **Wireless Dev Board** slot on a supported EVA suit
3. Wear the suit
4. Open the wireless board slot in your suit inventory to access the board's controls

For full compile and runtime error diagnostics over wireless, install a **Lua Debugger Motherboard** into the board's internal debugger slot.

### Board Controls

| Control | Description |
|---------|-------------|
| **Wireless Network** | Cycle through powered omni transmitters in range (Alt to cycle backwards) |
| **Wireless Mesh** | Toggle mesh handoff — automatically switch to the best in-range transmitter on the same network |
| **Wireless Disconnect** | Clear the current wireless connection |

### Connection Behavior

- The board scans for **powered omni transmitters** within range
- The connection **persists across save/load** — on relog, the board reconnects automatically if the network is still in range
- Brief transmitter outages are tolerated with a short reconnect grace period
- Removing the suit or the board immediately drops the wireless connection
- When mesh is enabled and multiple transmitters share the same network, the board automatically switches to the closest one as you move

### Requirements

- The server config **`AllowNetworkChipAccess`** must be enabled
- You must be wearing the suit with the board installed
- At least one **powered** omni transmitter must be in range

### Combining with the IC Editor

If you have the in-game IC editor open on a wired computer **and** a wireless board connected to a different network, both networks are accessible at the same time. MCP and VS Code can operate across both the wired editor network and the wireless suit-board network simultaneously.

> **Dedicated Servers:** Dedicated servers do not expose the HTTP/MCP listener directly. In multiplayer, a client can use its own local StationeersLua bridge while the game routes debug traffic to the server over mod network messages.

### Scripting API (`ic.wireless`)

Lua chips inside a suit (with a wireless dev board) or inside a wireless tablet cartridge can programmatically control the wireless connection:

| Function | Description |
|----------|-------------|
| `ic.wireless.list()` | Returns a list of in-range powered omni transmitters. Each entry: `{ id, network_id, name, distance, max_distance }` |
| `ic.wireless.connect(id [, mesh])` | Connect to a transmitter or network by id. `mesh` defaults to `true`. Returns `true` on success, or `false, error` on failure |
| `ic.wireless.disconnect()` | Clear the current wireless connection |
| `ic.wireless.status()` | Returns `{ available, connected, in_range, mesh, network_id, transmitter_id, transmitter_name, distance, max_distance }` |
| `ic.wireless.set_mesh(enabled)` | Toggle mesh handoff mode without reconnecting |

> `ic.wireless.status()` never throws — if no wireless device is present it returns `{ available = false, connected = false }`. All other functions throw if no wireless device is available.

**Example — auto-connect to the closest transmitter:**

```lua
local nets = ic.wireless.list()
if #nets > 0 then
    local ok, err = ic.wireless.connect(nets[1].id)
    if ok then
        print("Connected to " .. nets[1].name)
    else
        print("Failed: " .. err)
    end
end
```

---

## 30. Editor Intelligence (LSP)

StationeersLua includes a built-in **Language Server Protocol (LSP)** server that provides Stationeers-specific code intelligence in both the in-game IC10Editor and VS Code.

### What It Provides

| Feature | Description |
|---------|-------------|
| **Diagnostics** | Real-time Lua parse and compile error highlighting |
| **Completions** | Lua keywords, standard library, and the full StationeersLua API |
| **Enum completions** | `ic.enums.LogicType.` (and other `ic.enums.*` tables, including `SorterInstruction` / `ConditionOperation`) triggers member completions with numeric values |
| **Constant completions** | `ic.const.` triggers completions for all game constants |
| **Parameter-aware completions** | Typing the second argument of `ic.read()` suggests `LogicType` members; the third argument of `ic.read_slot()` suggests `LogicSlotType` members |
| **`require()` completions** | Inside `require("...")`, module names from library chips on the active data network are suggested |
| **Hover** | Hover over any API function for its signature, description, and example; hover over enum members to see their numeric values |
| **Signature help** | Function call signatures with parameter highlighting |
| **Formatting** | Document formatting via the LSP |

### In-Game Editor

The in-game IC10Editor uses the language service directly (no TCP needed). Completions, hover tooltips, and diagnostics work automatically when the editor is open.

The in-game editor also provides **Lua auto-indent**: pressing Enter auto-indents to the correct level, and typing closing keywords (`end`, `until`, `else`, `elseif`) auto-dedents. Tab uses 4-space indentation. Shift+Tab dedents.

### VS Code (Dual LSP)

In VS Code, two language servers work together:

1. **Sumneko Lua** — general-purpose Lua intelligence (type checking, refactoring, go-to-definition)
2. **Stationeers LSP** — Stationeers-specific intelligence (game API completions, enum values, diagnostics, network-scoped `require()` suggestions)

The Stationeers LSP connects over TCP when `EnableLspServer` is enabled in the mod config.

### Network-Scoped Completions

Completions are scoped to the **data network** of the chip being edited:

- `require("...")` only suggests modules from library chips on that chip's network
- Enum and constant completions are global (same in every context)
- Parameter-position suggestions (LogicType, LogicSlotType) are global

This works correctly with all access modes: wired IC editor, wireless development board, and combined wired + wireless.

### Configuration

Mod config (`[MCP Server]` section):

| Setting | Default | Description |
|---------|---------|-------------|
| `EnableLspServer` | `false` | Enable the LSP TCP server for VS Code |
| `LspPort` | `3031` | TCP port for the LSP server (must differ from the HTTP port) |
| `ExternalLuaLanguageServerPath` | *(empty)* | Optional stdio **lua-language-server** for the in-game IC10 Lua editor (see main MCP table above) |
| `ExternalLuaLanguageServerArguments` | *(empty)* | Optional arguments for that executable |
| `ExternalLuaLanguageServerWorkingDirectory` | *(empty)* | Optional process working directory |

VS Code extension setting:

| Setting | Default | Description |
|---------|---------|-------------|
| `stationeers-lua.lspPort` | `3031` | TCP port to connect to (must match mod config) |

> **Note:** `EnableLspServer` only controls the **TCP** LSP for external editors (for example VS Code). The in-game IC10 Lua editor uses `LuaLanguageService` when `ExternalLuaLanguageServerPath` is empty; when that path is set, it uses stdio **lua-language-server** via IC10Editor's `LSPFormatter` integration instead.

> **Compatibility note:** Dedicated servers and installs without **IC10Editor** skip the optional in-game external language-server integration cleanly. That optional path is only used where the editor mod exists; the built-in runtime and TCP LSP support are unaffected.

---

## Quick Reference Card

### Global Functions

| Function | Description |
|----------|-------------|
| `read(dev, logicType [, net])` | Read logic value |
| `write(dev, logicType, value [, net])` | Write logic value |
| `read_id(id, logicType [, net])` | Read by ReferenceId |
| `write_id(id, logicType, value [, net])` | Write by ReferenceId |
| `read_slot(dev, slot, slotType [, net])` | Read slot value |
| `write_slot(dev, slot, slotType, value [, net])` | Write slot value |
| `read_slot_id(id, slot, slotType [, net])` | Read slot by ReferenceId |
| `write_slot_id(id, slot, slotType, value [, net])` | Write slot by ReferenceId |
| `read_reagent(dev, mode, hash [, net])` | Read reagent value |
| `rmap(dev [, net])` | Get reagent→prefab map |
| `batch_read(hash, logicType, method [, net])` | Batch read |
| `batch_read_name(hash, nameHash, logicType, method [, net])` | Batch read + name filter |
| `batch_read_slot(hash, slot, slotType, method [, net])` | Batch read slot |
| `batch_read_slot_name(hash, nameHash, slot, slotType, method [, net])` | Batch read slot + name |
| `batch_write(hash, logicType, value [, net])` | Batch write |
| `batch_write_name(hash, nameHash, logicType, value [, net])` | Batch write + name |
| `batch_write_slot(hash, slot, slotType, value [, net])` | Batch write slot |
| `batch_write_slot_name(hash, nameHash, slot, slotType, value [, net])` | Batch write slot + name |
| `mem_read(addr)` | Read chip memory |
| `mem_write(addr, value)` | Write chip memory |
| `mem_clear()` | Clear chip memory |
| `mem_get(dev, addr [, net])` | Read device memory |
| `mem_put(dev, addr, value [, net])` | Write device memory |
| `mem_clear_device(dev [, net])` | Clear device memory |
| `mem_get_id(id, addr [, net])` | Read device memory by id |
| `mem_put_id(id, addr, value [, net])` | Write device memory by id |
| `mem_clear_id(id [, net])` | Clear device memory by id |
| `stack_push(value)` | Push to stack |
| `stack_pop()` | Pop from stack |
| `stack_peek()` | Peek top of stack |
| `stack_poke(addr, value)` | Write to stack address |
| `stack_get_sp()` / `stack_set_sp(v)` | Get/set stack pointer |
| `stack_get_ra()` / `stack_set_ra(v)` | Get/set return address |
| `hash(str)` | String → hash |
| `prefab_name(hash)` | Hash → prefab name |
| `device_id(dev)` | Get device ReferenceId |
| `device_name(dev [, net])` | Get device display name |
| `device_label(dev, name)` / `label(dev, name)` | Set device label |
| `namehash_name(devHash, nameHash [, net])` | Resolve nameHash to display name |
| `device_list([net])` | List all devices on the data network |
| `host_info()` | Host metadata (name, type, wearer for wearable hosts) |
| `pack_ascii6(str)` | Pack string to number |
| `unpack_ascii6(num)` | Unpack number to string |
| `strip_color_tags(str)` | Remove Unity color tags |
| `to_int53(value)` | Convert to 53-bit int |
| `util.game_time()` | Seconds since world start (server time) |
| `util.days_past()` | Days passed in world (server time) |
| `util.time_of_day()` | Fraction of day (0..1) |
| `util.clock_time([pattern])` | Formatted clock time (pattern tokens `HH`, `hh`, `MM`, `ss`, `A`) |
| `bit_and/or/xor/nor/not(a [,b])` | Bitwise ops |
| `bit_sll/srl/sra(a, n)` | Bit shifts |
| `bit_ext(val, pos, len)` | Extract bit field |
| `bit_ins(dst, src, pos, len)` | Insert bit field |
| `require(modname [, reload])` | Load module from library chip on data network |
| `sleep(seconds)` | Pause current context (main, tick, or user coroutine) |
| `yield()` | Pause until next tick (main, tick, or user coroutine) |
| `throw(msg)` | Throw runtime error |
| `hcf()` | Halt and Catch Fire |
| `print(...)` | Print to debugger logs |

### Namespaces

| Namespace | Key Members |
|-----------|-------------|
| `ic.enums` | `LogicType`, `LogicSlotType`, `LogicBatchMethod`, `LogicReagentMode`, `SoundAlert`, `SorterInstruction`, `ConditionOperation` |
| `ic.const` | `BASE_UNIT_INDEX`, `BASE_NETWORK_INDEX`, game constants |
| `ic.events` | `.on(name, handler)`, `.off(name)` |
| `ic.net` | `.id()`, `.peers()`, `.send()`, `.broadcast()`, `.recv()`, `.listen()` |
| `ic.net` (pub/sub) | `.publish()`, `.subscribe()`, `.unsubscribe()` |
| `ic.net` (rpc) | `.request()`, `.register()`, `.unregister()` |
| `ic.net` (pack) | `.pack()`, `.unpack()` |
| `ic.wireless` | `.list()`, `.connect()`, `.disconnect()`, `.status()`, `.set_mesh()` |
| `util.json` | `.encode()`, `.decode()` |
