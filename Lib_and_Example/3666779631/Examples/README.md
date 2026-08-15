Note that these lua scripts are ALL AI generated. They may have issues, but they are a good starting point and show off the capabilities of the Scriptable UI system.

## Examples

### Programmable Visor (HUD)

- **VisorHudLayoutDemo.lua** — Compact **upper-left** visor HUD (not a centered blocking panel). Uses `ss.client_overlay()` for vanilla-aware margins (local or `remote_client` relay in multiplayer). When `ic.wireless_status().connected`, scans `ic.device_list()` and reads `Charge` / `Maximum` per device (batteries on the remote data net) with small bar graphs. If the wireless data link is down, it does **not** query the network—only a thin “no data link” strip from `ic.wireless_status()`. Drag / overlay changes use callbacks (`hud:on_drag`, `ss.hud.on_overlay_change`) instead of polling.
- **VisorHudStopwatch.lua** — **Lower-right** mission timer: `RUN`/`PAUSE` and `RESET` with `on_click`, live readout updated in `on_frame` via `hud:get` + `set_props`, `util.game_time()` for elapsed. Rebuilds shell from callbacks: `hud:on_drag(rebuild_shell)` and `ss.hud.on_overlay_change(rebuild_shell)`.
- **VisorHudSciFiTicker.lua** — **Bottom ticker bar**: rotating in-character tips + `ic.wireless_status()` one-liner + `ic.host_info()` label. No `device_list` (safe when data link is off). Tips advance every few seconds using `util.game_time()`. Drag / overlay changes are callback-driven.
- **VisorHudMissionDeck.lua** — **Upper-left** “quick orders” strip of five `on_click` mission buttons + status line (shows last choice and optional `playerName`). Good minimal sample for **interactive** visor HUD + `ss.client_overlay()` margins. Drag / overlay changes are callback-driven.
- **VisorHudPong.lua** — **Lower-left** tiny **Pong** on **`ss.hud`** + **`canvas`**. Same loop style as **`Games/Tetris.lua`** / **`BlockBreaker.lua`**: sim + keyboard **`hud:poll_input()`** + draw run entirely in **`on_frame`**. Layout changes are callback-driven via `hud:on_drag(rebuild_shell)` and `ss.hud.on_overlay_change(rebuild_shell)`, so `poll_input()` is only for gameplay keys now. **`ic.persist`** (JSON via **`util.json`**) saves the drag offset across world saves and housing power cycles.

> **`tick()` and `on_frame` on the same chip - the actual rule.** A chip can define both. The runtime guarantees they never run concurrently when `tick()` is fully synchronous: the on_frame scheduler's `LuaState.IsRunning` check skips frames while `tick()` is mid-execution, and the next `on_frame` runs as soon as `tick()` returns. The pattern is **only unsafe when `tick()` yields** (`coroutine.yield()`, `ic.yield()`, runtime sleep). A yielded tick coroutine leaves shared globals and closure upvalues half-mutated; `on_frame` resuming on the same root `LuaState` would race them. **The runtime detects exactly this case** (`LuaChipRuntimeManager.IsChipTickYielded`) and halts the chip with a deterministic error message instead of letting the script cascade into "attempt to index a nil value" noise. So: write whichever shape suits the script, just don't `yield` from `tick()` while `on_frame` is registered. `VisorHudLayoutDemo`, `VisorHudSciFiTicker`, and `VisorHudPong` use `on_frame`; the first two are callback-driven for drag / overlay changes, while Pong still polls only for gameplay keys.

### Tablet Cartridges (Target Detection)

- **AtmosAnalyzer.lua** - Replicates the base game's atmos cartridge. Point at pipes, tanks, or vents to see pressure, temperature, and gas composition.
- **DeviceInspector.lua** - Detailed device inspector showing logic values, slot contents, power state, power/data networks, and health.
- **EnergyNetworkTarget.lua** - Focused view of power cable network loads and battery totals.

### Network Examples

- **NetChat.lua** - Peer-to-peer chat between Lua chips on the same data network.
- **NetPeerMonitor.lua** - Monitor all Lua chips on the network with ping/latency display.
- **NetAnnouncements.lua** - Broadcast announcements to all connected displays.
- **NetSensorDashboard.lua** - Station-wide sensor dashboard using **pub/sub**. Subscribes to `sensor/*` topics and renders a live multi-zone monitoring panel with temperature, pressure, status badges, and an alert log. Includes built-in simulation when no companion sensor chips are present.
- **NetRemoteControl.lua** - Remote system control panel using **RPC**. Discovers peers on the network, queries their status via `ic.net.request`, and lets the operator toggle systems and set modes. Detail panel shows live telemetry and command buttons. Runs a simulated demo when no real peers exist.

### Widget & Layout Demos

- **DragDropSilo.lua** — **Payload drag-and-drop** on **`ss.ui`** (motherboard or tablet): full-surface layout; top row of ingot **`icon`** sources; three tall silo **`panel`**s (**`drop_accepts`** modes: any / explicit list / partial). Engine **cursor-follow drag preview** (ghost clone tracks pointer) + dimmed source; each silo **accumulates** accepted drops (up to 12) and shows an icon grid. Uses element callbacks (`handle:on("drag_payload_begin")`, `handle:on("drop")`, `handle:on("drag_payload_cancel")`) instead of a `poll_input()` loop. **`interface_button`** (INTERFACE) for **Interface Mode** / keyboard. **`ic.persist`** stores silo contents (**`v = 3`** JSON).
- **WidgetShowcase.lua** - Static single-screen showcase of every chart, table, gauge, and layout widget. Demonstrates **sparkline**, **barchart**, **linechart** (multi-series with legend), **gauge** (with threshold zones), **table** (sortable + selectable), and **grid/flex** layout helpers — all on one screen with generated data.
- **LiveDashboard.lua** - Animated station monitoring dashboard that updates every tick with simulated sensor data. Features live-updating gauges (temperature, pressure), rolling sparkline histories, a multi-series power line chart, a sortable zone status table, and an atmospheric composition bar chart. Demonstrates real-time widget updates via `coroutine.yield()` loop.
- **GradientShowcase.lua** - Demonstrates all gradient features: 2-color, multi-stop (evenly-spaced), multi-stop (explicit positions), all four directions (horizontal, vertical, diagonal, radial), and the `ss.ui.gradient()` color interpolation helper.
- **ProgressSpinnerDemo.lua** - Showcases progress bar features (`color_stops` for value-dependent colors, `indeterminate` animated mode, gradient fills), spinner elements with varied configurations, and gauge invert mode. Includes animated tick loop.
- **ZIndexDemo.lua** - Overlapping panels with `props.z_index` / `props.zIndex`: static stack (expect blue on top), animated 2s phase cycle (red/green/blue take turns in front), scrollview nested overlap (hint text above panels; camelCase `zIndex` on props in scroll strip).

### Control Panels

- **AccessControl.lua** - Security keypad with PIN and biometric authentication.
- **AirlockControl.lua** - Tick-driven airlock controller with auto-detect single/dual vent, safety interlocks, and error-resilient cycling.
- **CCTVDashboard.lua** - Custom security camera dashboard using `type="camera"` elements with a primary large view and clickable thumbnails. **Requires the CCTV mod**. Each camera element independently specifies which device slot to display via `props.device`. Click thumbnails to swap the main view.
- **FindByName.lua** - Demonstrates `ic.find()` and `ic.find_all()` — finding devices on the data network by their Labeler-assigned name. Shows how to read/write devices without needing physical pin connections, and displays a live status dashboard of discovered devices.
- **SolarTrackerMaxiMK2-ScriptedScreens.lua** - Solar panel tracking system.

### SampleUI/

Dashboard-style monitoring displays (PowerGrid, LifeSupport, CommsStatus, etc.)

### Utility

- **WallClock.lua** - Beautiful 12-hour analog+digital wall clock. Shows large digital time with AM/PM, day counter, elapsed time, and a minimal analog clock face with hour/minute/second indicators. Updates every half-second.

### Games/

- **SnakeGame.lua** - Classic snake game
- **Tetris.lua** - Tetris clone
- **Doom.lua** - Doom-style raycaster demo
