# ScriptedScreens Beginner Guide

This guide is for **brand new** ScriptedScreens users: how to install it, how to get a screen working in-game, and how to write your first scripted UI in Lua.

If you already know what you’re doing and just want the raw API, see `README.md`.

---

## What ScriptedScreens is

ScriptedScreens lets you draw and interact with **custom touchscreen UIs** on Stationeers consoles using **Lua**.

You write Lua scripts that:

- Create UI elements (panels, labels, buttons, sliders, etc.)
- Handle player input (click/change/toggle, keyboard input in interface mode)
- Optionally draw pixels (canvas) for games/graphs

---

## Requirements

You need:

- **BepInEx 5.x**
- **StationeersLaunchPad**
- **StationeersLua** (ScriptedScreens depends on it)
- **IC10Editor** (recommended for editing Lua chip scripts)

---

## In-game setup (first time)

1. Place a **Computer** or **Console**.
2. Craft/spawn a **ScriptedScreens Circuitboard (Lua Chip)** or **ScriptedScreens Motherboard (Lua Chip)**.
3. Insert an **Integrated Circuit (Lua)** (`ItemIntegratedCircuitLua`) into the board's built-in chip slot.
4. Insert the board into the computer.
5. Open the IC10Editor and paste a Lua script.

The ScriptedScreens boards do **not** run Lua by themselves. Each board has a slot, and you must insert a Lua chip before the UI or script will do anything.

Tablet variants work the same way:

- **Cartridge (Lua Chip)** and **Cartridge (Lua Chip, Wireless)** are tablet cartridges with a built-in slot for one **Integrated Circuit (Lua)**.
- Insert the Lua chip into the cartridge's slot, then insert the cartridge into a tablet.
- If there is no Lua chip inserted, there is no script running behind the UI.

### Wiring devices to pins (d0–d5)

If your script reads or writes external devices (dials, lights, sensors, etc.), you need to assign them to device pins:

1. Use a **screwdriver** on the **bolt on the side** of the console to open the **configuration screen**. This can be accessed on the computer by inserting a **data disk** into one of the disk slots.
2. In the config screen you will see slots for **d0** through **d5**. Select which device goes on which pin.
3. Close the config screen. Your script can now use `ic.logic.read(0, ...)` / `ic.logic.write(0, ...)` to talk to whatever device you assigned to d0, and so on.

**Optional pin hints in Lua:** You can record short labels for each pin (what *your* script uses that wire for). They appear on the config screen above the assigned device name and are saved with the board. This is separate from the Labeller tool and from `device_label`, which sets the device’s in-world display name.

```lua
ss.pin_label(0, "O2 sensor")
ss.pin_label(1, "Vent out")
```

Use `ss.pin_label(0)` with one argument to read the stored hint (`nil` if unset). **Tablet cartridges** do not use the pin config UI; `ss.pin_label` is only for motherboards/circuitboards.

> **Tip:** Insert a **Data Disk** into the computer if you need to import/export code.

---

## Core concepts

### Surface
A **surface** is a named UI “view” (like a page). You write to a surface using:

```lua
local ui = ss.ui.surface("main")
```

A physical screen index can be provided too:

```lua
local ui2 = ss.ui.surface("main", 1)
```

Only the **active** surface is rendered on a given physical screen. Switch it with:

```lua
ss.ui.activate("main")
```

### Visor HUD (`ProgrammableVisorGlasses`)

When the Lua chip sits in **Programmable Visor** glasses (glasses slot, powered), use **`ss.hud`** instead of `ss.ui` for the same surface API. **`tick()`**, **`ICircuitHolder` simulation**, and **`surface:on_frame`** only run while the visor is **equipped in the glasses slot** (on + battery); in your hand or elsewhere the chip does not execute, but you can still read/write source over the network / editor. `ss.hud.surface("main")`, `ss.hud.activate("main")`, then `surface:element`, `surface:commit`, canvas helpers, `surface:on_frame`, and interface mode. The HUD renders as a **screen-space overlay** tied to the wearer; its canvas **`sortingOrder` defaults to `InventoryManager.GameCanvas` + 1** (low fallback when `GameCanvas` is missing) and **each frame drops under any open `InventoryWindow`** (minimum `ZLayer - 1`) so equipment panels stay clickable; it still tends to sit **below** typical ImGui / debug overlays when no inventory is open. `ss.ui` remains for consoles and tablet cartridges; calling it on a visor-only chip shows the usual “wrong host” error—switch to `ss.hud`.

Other **visor-only** examples in `Examples/`: **`VisorHudStopwatch.lua`** (RUN/PAUSE/RESET timer), **`VisorHudSciFiTicker.lua`** (bottom ticker + wireless + host line), **`VisorHudMissionDeck.lua`** (five `on_click` mission buttons), **`VisorHudPong.lua`** (canvas Pong + `on_frame` + **`interface_button`** / keys), and **`VisorHudMultiPanel.lua`** (multi-column wireless diagnostics). All draggable visor samples now build their chrome with `hud:layout(...)`; `VisorHudMultiPanel.lua` is the bigger reference for per-panel `offset`, while the smaller examples show the same pattern for simple one-panel HUDs.

**Avoiding vanilla HUD:** `ss.client_overlay()` reports every visible vanilla rect worth avoiding - `InventoryManager` (hands, clothing, suit status, game info, pause / settings / incidents buttons, reading panel), `InventoryWindowManager` (every open inventory slot window with its parent slot title), and modals (Stationpedia rect; console / input / settings remain booleans because they are IMGUI). **Every rect is in visor canvas coordinates** (top-left origin, Y down) - the same space `hud:size()`, `hud:layout`, and `lay_dx` / `lay_dy` already use. No screen-to-canvas math, no Y flip, no scale factors.

The recommended path is the three helpers on `ss.hud`, not walking `panels[]` by hand:

- **`ss.hud.safe_area([pad])`** -> `{ x, y, w, h, pad, ok }` already minus every edge-touching vanilla panel + a pad (default 8 px, override via `ss.hud.set_safe_padding(n)`). Use the result directly as your panel rect.
- **`ss.hud.intersects_vanilla(x, y, w, h)`** -> bool. "Does this proposed placement collide with any vanilla rect right now?"
- **`ss.hud.first_free_anchor({"top_right", "top_left", "bottom_right", "bottom_left", "center", ...}, w, h)`** -> `{ x, y, w, h, anchor }`. Picks the first anchor whose placement doesn't collide; falls back to the first option if all conflict.

For change detection, **use `ss.hud.on_overlay_change(fn)`** instead of polling. Register a callback once and rebuild when the overlay actually changes, rather than comparing snapshot hashes or cached version ints every tick.

`ss.client_overlay()` also exposes `version`, `source` (`"local"` / `"remote_client"` / `"none"`), `canvas_w` / `canvas_h` (visor canvas pixels - same as `hud:size()`), `screen_w` / `screen_h` (raw client screen pixels, diagnostic), `relay_age_s` and `relay_stale = relay_age_s > 5`, all the modal booleans, and the full `panels[]` array (each entry has `id`, `kind` (`hands` / `clothing` / `vitals` / `inventory_window` / `chrome` / `system_modal`), optional `title`, `x`, `y`, `w`, `h`). On a **dedicated (batch) host** the wearer's client pushes the snapshot via the same MessagePack + LZ4 relay as `ss.ui` sync batches; until the first snapshot arrives the server returns `ok = false` with `reason = "no_remote_client_overlay"` plus a sane fallback `canvas_w` / `canvas_h` so layout never crashes. **`Examples/UiContextProbe.lua`** is the live diagnostic: drop it on a visor and every reported rect is drawn color-coded by `kind` with `id` / `title` labels and the `safe_area()` rect overlaid - that's the same coordinate space your scripts read.

**Visor `hud:size()` is always real.** The wearer's client pushes its actual `SSVisorHudRoot` `RectTransform` size (now exposed as `canvas_w` / `canvas_h`, MessagePack key 3 / 4 of the overlay snapshot) to the host with every overlay update, so server-side visor Lua's `hud:size()` returns the same coordinate space the client renders in (16:9, 16:10, 21:9 ultrawide, vertical, etc.) instead of the legacy hardcoded **1920x1080** server fallback. There is no need for `math.max(1920, sz.w)` workarounds in visor scripts; trust `hud:size()`. Until the first overlay snapshot arrives the server returns the canvas reference resolution (1920x1080) so the script never sees `(0,0)` / `(256,256)`.

**Off-screen / drag bounds are the script author's responsibility.** The mod no longer clamps drag deltas in `ScriptedScreensUiDragGroup.OnDrag` or `TryApplyDragGroupDeltaFromNetworkInput`; the raw `drag_end` delta reaches your `poll_input` handler verbatim and the authoritative model accepts whatever you write. If you want a panel to stay on-screen, accumulate `lay_dx` / `lay_dy` from `drag_end` (`dx&dy` value) and clamp them yourself either at accumulation time or inside your `rebuild` (e.g. `lay_dx = math.max(0, math.min(W - PANEL_W, lay_dx))`). This lets scripts intentionally peek off-edge, span multiple monitors via virtual coordinates, or do overscroll feedback without the mod reverting them.

### Elements
An **element** is a UI widget (label/button/panel/etc.) identified by a unique `id`.

```lua
ui:element({
    id = "title",
    type = "label",
    rect = { unit = "px", x = 20, y = 200, w = 200, h = 30 },
    props = { text = "Hello" },
    style = { font_size = 18, color = "#FFFFFF" }
})
```

### Draw order (`z_index`)
Overlapping elements that share the same **parent** in the UI tree (the surface root, a nested panel’s children, or a scroll view’s **content**) are sorted by **`z_index`** or **`zIndex`** on **`props` only** (not `style`, so stacking is not split across two tables). **Larger values draw in front**; when two elements tie, order is stable by element **`id`**. Stacking is recomputed when a UI batch is applied (for example after `ui:commit()` or updates from a `tick` loop).

Use this for modal panels over backgrounds, tooltips, or any time two widgets share the same rectangle. Bundled visual test: **`Examples/ZIndexDemo.lua`**.

### Rect / layout units
Element position/size comes from `rect`.

- `unit = "px"` uses pixels.
- `unit = "%"` / `"percent"` uses 0..100 percentages of the screen.

Coordinates use a **top-left origin** (Y increases downward).

### Commit
Changes are batched. After creating/updating elements, call:

```lua
ui:commit()
```

### Measuring text
If you need **accurate wrapped text heights**, use `ui:measure_text` to get the preferred size using the active TMP font:

```lua
local size = ui:measure_text("Hello world", 200, 14, true)
print("text size", size.w, size.h)
```

Arguments:

- `text` (string)
- `maxWidth` (optional) — wrap width in pixels (0 = no wrap)
- `fontSize` (optional) — size in pixels (defaults to 16)
- `wrap` (optional) — force wrap on/off (defaults to `maxWidth > 0`)

---

## Colors

All color values throughout the UI system accept three formats:

| Format | Example | Description |
|--------|---------|-------------|
| Hex | `"#FF0000"` | RGB hex color |
| Hex + alpha | `"#FF000080"` | RGBA hex color (50% opacity) |
| `rgb()` | `"rgb(255, 0, 0)"` | CSS-style RGB (values 0-255) |
| `rgba()` | `"rgba(255, 0, 0, 0.5)"` | CSS-style RGBA (RGB 0-255, alpha 0.0-1.0) |

These work everywhere a color is expected: `bg`, `fill`, `color`, `gradient`, `color_stops`, canvas functions, `ss.ui.gradient()`, etc.

---

## Element types reference

Every element has `id`, `type`, `rect`, and optional `props`, `style`, and event handlers. Optional **`z_index`** / **`zIndex`** on **`props`** control **draw order among siblings** (see **Draw order (`z_index`)** under Core concepts above).

### Display elements

#### `label`
Text display. Supports TMP rich text tags.

| Prop | Description |
|------|-------------|
| `text` | Text content (supports `<b>`, `<color>`, etc.) |

| Style | Description |
|-------|-------------|
| `font_size` | Font size (default 16) |
| `color` | Text color |
| `align` | `"left"`, `"center"`, `"right"` |

#### `panel`
Background rectangle. By default the panel image does **not** raycast (clicks pass through). Optional **draggable HUD** (visor, tablet, board surfaces):

| Prop | Description |
|------|-------------|
| `draggable` | `"true"` / `"1"` — panel participates in pointer drag; **raise `z_index` on buttons and other controls above this panel** so they stay clickable. |
| `drag_group` | Comma- or semicolon-separated **element ids** on the same surface that move together (default: this panel’s id only). All must use **`unit = "px"`** rects. For `surface:layout(...)` containers, you can also use `"auto"` or `drag_group_auto = true` to collect every descendant id automatically. |
| `drag_bounds` | Optional live clamp for the draggable **leader** during the gesture. `"screen"` / `"surface"` keeps the leader fully inside the surface root. `"element:<id>"` keeps the leader fully inside another same-surface element's rect. Followers in `drag_group` move with the leader. Omit the prop for raw unclamped drag. |

Panel reposition drags are exposed through callbacks only: **`surface:on_drag(fn)`** at the surface level, **`handle:on("drag_begin", fn)`** / **`handle:on("drag_end", fn)`** at the element level. The runtime stores the cumulative canvas-pixel offset for each draggable leader; read it with **`surface:drag_offset(id)`** during `rebuild()` and (optionally) restore a saved offset with **`surface:set_drag_offset(id, dx, dy)`**. There is no `poll_input` path for these events and no `drag_dispatch_id` alias - the element's own `id` is always what callbacks receive. While a `drag_group` pointer drag is active, **`ApplyRect`** is skipped on the group members so a concurrent flush cannot fight live **`anchoredPosition`** updates; **`element:set_props` / `set_style`** likewise refresh the snapshot rect from the live widget for **`unit = "px"`** elements so mid-drag text/style updates do not snap widgets back to stale coordinates. See **`Examples/VisorHudStopwatch.lua`** and **`Examples/DragBoundsDemo.lua`**.

**Drag bounds are still script-author owned:** the runtime does **not** clamp by default. Client `OnDrag` applies the raw pointer delta unless the draggable leader opts in with **`drag_bounds`**. Use **`drag_bounds = "screen"`** (or `"surface"`) when you want the panel to stop at the visible edge while dragging, or **`drag_bounds = "element:<id>"`** when you want it contained by another element. If you omit the prop, raw unclamped drag still works for off-edge peek, overscroll feedback, and multi-monitor coordinate spaces. Lua-side rebuild clamping is still useful as a persistence safety net for old saves / changed aspect ratios because it can repair stale saved offsets on the next rebuild even before the user drags again. This behavior applies to normal ScriptedScreens surfaces and visor HUDs alike. See **`Examples/DragBoundsDemo.lua`** for a minimal copyable sample that shows both modes side by side.

**Payload drag-and-drop (ingot → silo style):** on **`panel`**, **`button`**, or **`icon`**, set **`drag_source = "true"`** and **`drag_payload = "<token>"`** (no **`&`** in the token). Mark drop zones with **`drop_target = "true"`**; optional **`drop_accepts`** — prefer **`{ "A", "B" }`** (array of strings, case-insensitive); legacy comma/semicolon string still works — and **`drop_dispatch_id`** ( **`poll_input`** **`id`** for **`drop`**; default = drop zone **`id`**). **`poll_input`:** **`drop`** with **`value = "<payload>&<source_id>&<target_id>"`**; optional **`drag_payload_begin`** / **`drag_payload_cancel`** on the source element **`id`**. Events use the same networked UI-input path as clicks; the host re-validates **`drop`**. Mutually exclusive with **`draggable`** on the **same** **`panel`** (**`drag_source`** wins). While dragging, the mod spawns a **semi-opaque duplicate of the source `Image`/`RawImage`** on the same canvas that **follows the pointer** (destroyed on release). See **`Examples/DragDropSilo.lua`** for a full-surface reference that shows `drag_payload_begin`, `drop`, and `drag_payload_cancel` status handling plus `drop_accepts` whitelists on three silos.

| Style | Description |
|-------|-------------|
| `bg` | Background color (default dark) |
| `gradient` | End color for a linear gradient (start color is `bg`) |
| `gradient_dir` | Gradient direction: `"horizontal"`, `"vertical"` (default), `"diagonal"`, `"radial"` |

#### `progress`
Progress bar with a filled portion. Supports generic color stops, an indeterminate (animated) mode, and configurable fill direction (horizontal or vertical).

```lua
-- Basic progress bar
ui:element({
    id = "hp", type = "progress",
    rect = { unit = "px", x = 10, y = 10, w = 200, h = 20 },
    props = { value = 75, min = 0, max = 100 },
    style = { bg = "#1E293B", fill = "#22C55E" },
})

-- With color stops (fill changes color based on value)
ui:element({
    id = "temp", type = "progress",
    rect = { unit = "px", x = 10, y = 40, w = 200, h = 20 },
    props = { value = 0.7 },
    style = {
        bg = "#1E293B",
        fill = "#22C55E",          -- base color (0..0.5)
        color_stops = {
            { 0.5, "#EAB308" },    -- yellow from 50%
            { 0.8, "#EF4444" },    -- red from 80%
        },
    },
})

-- Indeterminate (animated sliding bar)
ui:element({
    id = "loading", type = "progress",
    rect = { unit = "px", x = 10, y = 70, w = 200, h = 8 },
    props = { indeterminate = true },
    style = { bg = "#1E293B", fill = "#38BDF8" },
})

-- Vertical progress bar (bottom to top)
ui:element({
    id = "fuel_level", type = "progress",
    rect = { unit = "px", x = 10, y = 100, w = 30, h = 120 },
    props = { value = 60, min = 0, max = 100, direction = ss.direction.BottomToTop },
    style = { bg = "#1E293B", fill = "#38BDF8" },
})

-- Right-to-left progress bar
ui:element({
    id = "rtl_bar", type = "progress",
    rect = { unit = "px", x = 50, y = 100, w = 200, h = 20 },
    props = { value = 0.4, direction = ss.direction.RightToLeft },
    style = { bg = "#1E293B", fill = "#EAB308" },
})
```

| Prop | Description |
|------|-------------|
| `value` | Current value (ignored in indeterminate mode) |
| `min` | Minimum value (default 0) |
| `max` | Maximum value (default 1) |
| `indeterminate` | If true, shows an animated sliding fill |
| `direction` | Fill direction: `ss.direction.LeftToRight` (default), `ss.direction.RightToLeft`, `ss.direction.TopToBottom`, `ss.direction.BottomToTop`. Raw strings `"ltr"`, `"rtl"`, `"ttb"`, `"btt"` also accepted. Works with both determinate and indeterminate modes. |

| Style | Description |
|-------|-------------|
| `bg` | Track background color |
| `fill` | Base fill color (default green) |
| `color_stops` | Array of `{ fraction, "#color" }` pairs — fill color changes when the value ratio meets or exceeds a stop |
| `speed` | Animation speed for indeterminate mode (default 1.2) |

#### `spinner`
A rotating arc loading indicator that animates continuously.

```lua
ui:element({
    id = "loading", type = "spinner",
    rect = { unit = "px", x = 10, y = 10, w = 40, h = 40 },
    style = { color = "#38BDF8", thickness = 4 },
})
```

| Style | Description |
|-------|-------------|
| `color` | Spinning arc color (default accent blue) |
| `track_color` | Background track color (default dim) |
| `thickness` | Arc thickness in pixels (default 4) |
| `arc_length` | Fraction of full circle for the arc (default 0.3) |
| `speed` | Rotations per second (default 2) |

#### Gradients

Gradients are supported as a style prop on `panel`, `button`, and `progress` elements. The `gradient` prop accepts three formats:

```lua
-- Format 1: String — 2-color gradient from bg to the given color
ui:element({
    id = "header", type = "panel",
    rect = { unit = "px", x = 0, y = 0, w = 480, h = 40 },
    style = { bg = "#1E3A5F", gradient = "#0F172A", gradient_dir = "horizontal" },
})

-- Format 2: Array of color strings — evenly-spaced multi-stop gradient
ui:element({
    id = "banner", type = "panel",
    rect = { unit = "px", x = 0, y = 0, w = 480, h = 40 },
    style = {
        gradient = { "#EF4444", "#EAB308", "#22C55E", "#3B82F6" },
        gradient_dir = "horizontal",
    },
})

-- Format 3: Array of {position, "#color"} pairs — explicit stop positions
ui:element({
    id = "status", type = "panel",
    rect = { unit = "px", x = 0, y = 0, w = 480, h = 40 },
    style = {
        gradient = {
            { 0,   "#22C55E" },   -- green at 0%
            { 0.7, "#EAB308" },   -- yellow at 70%
            { 1,   "#EF4444" },   -- red at 100%
        },
        gradient_dir = "horizontal",
    },
})
```

| Style | Description |
|-------|-------------|
| `gradient` | Gradient colors: a string (2-color from bg), array of hex strings (evenly-spaced), or array of `{position, "#color"}` pairs |
| `gradient_dir` | Direction: `"horizontal"`, `"vertical"` (default), `"diagonal"`, `"radial"` (center-outward) |

**Lua color interpolation helper:**

`ss.ui.gradient(from, to, steps)` returns a 1-indexed array of interpolated hex color strings. Useful for generating color ramps for bar charts, sparklines, or any multi-color use case.

```lua
local colors = ss.ui.gradient("#EF4444", "#22C55E", 5)
```

#### `line`
A line between two points. The element `rect` is ignored — positioning is done via props.

```lua
ui:element({
    id = "sep", type = "line",
    rect = { unit = "px", x = 0, y = 0, w = 0, h = 0 },
    props = { x1 = "10", y1 = "50", x2 = "200", y2 = "50" },
    style = { color = "#334155", thickness = "2" },
})
```

| Prop | Description |
|------|-------------|
| `x1`, `y1` | Start point (top-left origin) |
| `x2`, `y2` | End point |

| Style | Description |
|-------|-------------|
| `color` | Line color (default white) |
| `thickness` | Line thickness in pixels (default 2) |

#### `rect_outline` / `border`
Outline-only rectangle (no fill).

| Style | Description |
|-------|-------------|
| `color` | Outline color |
| `thickness` | Border thickness in pixels (default **2**) |

#### `circle`
Filled ellipse inscribed in `rect` (equal width/height → circle) or elliptical outline ring, via mesh rendering. Fill vs stroke is controlled by **`props.filled`**, not by `thickness`.

| Prop | Description |
|------|-------------|
| `filled` | Omit, empty, `true`, or `1` for **filled** (default). `false` or `0` for **outline** only. |

| Style | Mode | Description |
|-------|------|-------------|
| `bg` | Filled | Fill tint (default white). |
| `color` | Outline | Stroke color when `filled` is false. |
| `thickness` | Outline | Outline distance in pixels (default **2**). `0` produces **no visible** stroke. |

#### `divider`
Horizontal or vertical separator line.

| Style | Description |
|-------|-------------|
| `color` | Divider color (default gray) |

#### `icon`
Display a game icon (gas type, slot type, etc.) using the built-in icon atlas.

```lua
-- Using an enum value — icon_type is auto-detected, no need to specify it
ui:element({
    id = "o2_icon", type = "icon",
    rect = { unit = "px", x = 10, y = 10, w = 24, h = 24 },
    props = { name = ss.ui.icons.gas.Oxygen },
    style = { tint = "#3B82F6" },
})

-- Using a raw string — specify icon_type explicitly
ui:element({
    id = "steel", type = "icon",
    rect = { unit = "px", x = 40, y = 10, w = 32, h = 32 },
    props = { icon_type = "prefab", name = "ItemSteelIngot" },
})
```

| Prop | Description |
|------|-------------|
| `name` | Enum value (auto-detects type) or raw icon name |
| `icon_type` | Optional: `"gas"`, `"slot"`, `"prefab"`, or `"resource"`. Only needed for raw strings. |

| Style | Description |
|-------|-------------|
| `tint` | Icon tint color (default white) |

**How it works:** Enum values from `ss.ui.icons.*` embed a type prefix (e.g. `"gas:Oxygen"`, `"prefab:ItemSteelIngot"`) so the renderer auto-detects the icon type. When passing raw strings (not from the enum), set `icon_type` explicitly.

**Icon types:**
- **`gas`** — gas type icon. Use names from `ss.ui.icons.gas.*`.
- **`slot`** — slot type icon. Use names from `ss.ui.icons.slot.*`.
- **`prefab`** — any game item/object thumbnail. Pass a prefab name (e.g. `"ItemSteelIngot"`) or a numeric prefab hash. See [Prefab icons](#prefab-icons-icon_typeprefab) below.
- **`resource`** — raw Unity resource path (advanced).

Available icon names are exposed as `ss.ui.icons.gas.*`, `ss.ui.icons.slot.*`, and `ss.ui.icons.prefab.*` — see [Icon enum tables](#icon-enum-tables-ssuiicons) below.

### Interactive elements

#### `button`
Clickable button.

| Prop | Description |
|------|-------------|
| `text` | Button label |

| Style | Description |
|-------|-------------|
| `bg` | Background color |
| `text` | Text color |
| `font_size` | Font size |

| Event | Callback args |
|-------|---------------|
| `on_click` | `(playerName)` |

#### `interface_button`
Like `button`, but clicking it enters **Interface Mode** (keyboard capture). Useful for activating keyboard-driven UIs.

| Prop | Description |
|------|-------------|
| `text` | Button label (default "INTERFACE") |

| Style | Description |
|-------|-------------|
| `bg` | Background color |
| `text` | Text color |
| `font_size` | Font size |

#### `checkbox`
Checkbox with a label. Toggled via `on_click`.

```lua
ui:element({
    id = "opt1", type = "checkbox",
    rect = { unit = "px", x = 10, y = 40, w = 200, h = 24 },
    props = { text = "Enable logging", checked = "true" },
    style = { check_color = "#22C55E" },
    on_click = function(player)
        -- Toggle checked state in your script
    end,
})
```

| Prop | Description |
|------|-------------|
| `text` | Label text |
| `checked` | `"true"` / `"false"` |

| Style | Description |
|-------|-------------|
| `bg` | Background color |
| `check_color` | Checkmark / box outline color |
| `text` | Label text color |
| `font_size` | Label font size |

| Event | Callback args |
|-------|---------------|
| `on_click` | `(playerName)` |

#### `radio`
Radio button with a label. Use a group of radio elements with shared `on_click` logic.

| Prop | Description |
|------|-------------|
| `text` | Label text |
| `selected` | `"true"` / `"false"` |

| Style | Description |
|-------|-------------|
| `bg` | Background color |
| `radio_color` | Dot / circle outline color |
| `text` | Label text color |
| `font_size` | Label font size |

| Event | Callback args |
|-------|---------------|
| `on_click` | `(playerName)` |

#### `toggle`
On/off toggle switch with a sliding knob.

```lua
ui:element({
    id = "power", type = "toggle",
    rect = { unit = "px", x = 10, y = 40, w = 50, h = 24 },
    props = { value = "true" },
    style = { on_color = "#22C55E", off_color = "#334155", knob = "#FFFFFF" },
    on_click = function(player)
        -- Toggle value in your script
    end,
})
```

| Prop | Description |
|------|-------------|
| `value` | `"true"` / `"false"` |

| Style | Description |
|-------|-------------|
| `on_color` | Background when on (default green) |
| `off_color` | Background when off (default dark) |
| `knob` | Knob color (default white) |

| Event | Callback args |
|-------|---------------|
| `on_click` | `(playerName)` |

#### `slider`
Draggable slider with configurable direction. Fires `on_change` with the new value.

```lua
-- Horizontal slider (default)
ui:element({
    id = "vol", type = "slider",
    rect = { unit = "px", x = 10, y = 40, w = 200, h = 20 },
    props = { value = "0.5", min = "0", max = "1" },
    style = { bg = "#1E293B", fill = "#3B82F6", handle = "#FFFFFF" },
    on_change = function(value, player)
        print("New value:", value)
    end,
})

-- Vertical slider (bottom to top)
ui:element({
    id = "throttle", type = "slider",
    rect = { unit = "px", x = 10, y = 70, w = 24, h = 120 },
    props = { value = "75", min = "0", max = "100", direction = ss.direction.BottomToTop },
    style = { bg = "#1E293B", fill = "#22C55E", handle = "#FFFFFF" },
    on_change = function(value, player)
        print("Throttle:", value)
    end,
})
```

| Prop | Description |
|------|-------------|
| `value` | Current value |
| `min` | Minimum (default 0) |
| `max` | Maximum (default 100) |
| `direction` | Slide direction: `ss.direction.LeftToRight` (default), `ss.direction.RightToLeft`, `ss.direction.TopToBottom`, `ss.direction.BottomToTop`. Raw strings also accepted. |

| Style | Description |
|-------|-------------|
| `bg` | Track background |
| `fill` | Filled portion color |
| `handle` | Handle color |

| Event | Callback args |
|-------|---------------|
| `on_change` | `(value, playerName)` |

#### `select`
Dropdown select. By default the client opens and closes the list and closes it after a pick; scripts usually only implement `on_change`. Pass `options` as a **Lua array** of label strings, or as a **pipe-delimited string** for backward compatibility.

Supports **multi-select** mode where multiple options can be toggled on/off. In multi-select mode the dropdown stays open after each pick so users can select multiple items.

```lua
-- Single-select (default)
ui:element({
    id = "mode", type = "select",
    rect = { unit = "px", x = 10, y = 40, w = 200, h = 28 },
    props = { options = { "Auto", "Manual", "Off" }, selected = "0" },
    style = { bg = "#1E293B", text = "#E2E8F0", font_size = 12 },
    on_change = function(value, player)
        -- value is the 0-based index of the selected option (string)
        print("Selected index:", value)
    end,
})

-- Multi-select with highlight (selected rows are highlighted)
local selected_items = {}
ui:element({
    id = "tags", type = "select",
    rect = { unit = "px", x = 10, y = 80, w = 200, h = 28 },
    props = {
        options = { "Alpha", "Beta", "Gamma", "Delta" },
        multi = "highlight",
        selected = table.concat(selected_items, ","),
    },
    style = { bg = "#1E293B", text = "#E2E8F0", font_size = 12, selected_bg = "#2563EB" },
    on_change = function(value, player)
        -- value is the 0-based index of the toggled option
        local idx = tonumber(value)
        -- toggle in your selected_items table, then re-render
    end,
})

-- Multi-select with checkbox indicators
ui:element({
    id = "filters", type = "select",
    rect = { unit = "px", x = 10, y = 120, w = 200, h = 28 },
    props = {
        options = { "Errors", "Warnings", "Info" },
        multi = "checkbox",
        selected = "0,2",
    },
    style = { bg = "#1E293B", text = "#E2E8F0", font_size = 12 },
    on_change = function(value, player)
        -- value is the 0-based index of the toggled option
    end,
})
```

| Prop | Description |
|------|-------------|
| `options` | Array of strings, e.g. `{ "A", "B", "C" }`, **or** pipe-delimited string `"A\|B\|C"` |
| `selected` | 0-based selected index (single-select), **or** comma-separated indices `"0,2,3"` (multi-select) |
| `open` | *(Optional)* `"true"` / `"false"` — when set, forces visibility on each render; omit for automatic open/close |
| `multi` | `"none"` (default, single-select), `"highlight"` (multi-select with row highlighting), or `"checkbox"` (multi-select with ☐/☑ indicators). The dropdown stays open after each pick in multi-select modes. |

| Style | Description |
|-------|-------------|
| `bg` | Background color |
| `text` | Text color |
| `font_size` | Font size |
| `selected_bg` | Background color for selected items (default blue highlight) |

| Event | Callback args |
|-------|---------------|
| `on_change` | `(optionIndex, playerName)` — option selected (single) or toggled (multi). In both modes, `optionIndex` is the 0-based index of the affected option. |
| `on_toggle` | *(Optional)* `(playerName)` — header clicked (open/close); only needed for legacy/manual `open` state |

#### `textinput`
Single-line text input field. In interface mode, clicking focuses the field for direct keyboard input. Outside interface mode, clicking opens a modal text dialog.

```lua
ui:element({
    id = "name_input", type = "textinput",
    rect = { unit = "px", x = 10, y = 40, w = 200, h = 28 },
    props = { value = "", placeholder = "Enter name...", title = "Name" },
    style = { bg = "#0F172A", text = "#E2E8F0", placeholder_color = "#475569", font_size = 12 },
    on_change = function(value, player)
        print("Input:", value)
    end,
})
```

| Prop | Description |
|------|-------------|
| `value` | Current text value |
| `placeholder` | Placeholder text when empty |
| `title` | Dialog title (non-interface mode) |

| Style | Description |
|-------|-------------|
| `bg` | Background color |
| `text` | Text color |
| `placeholder_color` | Placeholder text color |
| `font_size` | Font size |

| Event | Callback args |
|-------|---------------|
| `on_change` | `(value, playerName)` — fired on end-edit |

### Container elements

#### `scrollview`
Scrollable container. Child elements are parented inside the scroll content area using the `parent:element()` handle pattern.

```lua
local scroll = ui:element({
    id = "log_scroll", type = "scrollview",
    rect = { unit = "px", x = 10, y = 50, w = 460, h = 200 },
    props = { content_height = "800" },
    style = {
        bg = "#0F172A",
        scrollbar_bg = "#1E293B",
        scrollbar_handle = "#475569",
        scroll_speed = "30",
    },
})

-- Add children inside the scroll content
for i = 1, 20 do
    scroll:element({
        id = "row_" .. i,
        type = "label",
        rect = { unit = "px", x = 5, y = (i - 1) * 30, w = 440, h = 28 },
        props = { text = "Log entry " .. i },
        style = { color = "#E2E8F0", font_size = 11 },
    })
end
```

| Prop | Description |
|------|-------------|
| `content_height` | Total scrollable content height in pixels (default 500) |

| Style | Description |
|-------|-------------|
| `bg` | Scroll area background |
| `scrollbar_bg` | Scrollbar track color |
| `scrollbar_handle` | Scrollbar handle color |
| `scroll_speed` | Scroll sensitivity (default 20) |
| `padding_bottom` | Extra padding at content bottom (default 20) |

---

## Your first UI (copy/paste)

This script draws a background panel, a title, and a clickable button.

```lua
local ui = ss.ui.surface("main")
ss.ui.activate("main")

local size = ui:size()
local W, H = 480, 272
if size then W, H = size.w, size.h end

ui:clear()

ui:element({
    id = "bg",
    type = "panel",
    rect = { unit = "px", x = 0, y = 0, w = W, h = H },
    style = { bg = "#0F172A" }
})

ui:element({
    id = "title",
    type = "label",
    rect = { unit = "px", x = 20, y = 10, w = W - 40, h = 40 },
    props = { text = "SCRIPTEDSCREENS" },
    style = { font_size = 24, color = "#22C55E", align = "left" }
})

ui:element({
    id = "btn",
    type = "button",
    rect = { unit = "px", x = 20, y = H - 60, w = 180, h = 40 },
    props = { text = "CLICK ME" },
    style = { bg = "#334155", text = "#FFFFFF" },
    on_click = function(playerName)
        print("Clicked by: " .. tostring(playerName))
    end
})

ui:commit()
```

---

## Updating UI without rewriting everything (element handles)

`ui:element(def)` returns an **element handle**. This is optional, but makes updates much easier.

```lua
local panel = ui:element({
    id = "panel",
    type = "panel",
    rect = { unit = "px", x = 10, y = 10, w = 200, h = 100 },
    style = { bg = "#1E293B" },
})

panel:set_style({ bg = "#334155" })
panel:set_props({ text = "Updated" })
```

You can also fetch an existing element later:

```lua
local panel = ui:get("panel")
panel:set_style({ bg = "#0EA5E9" })
```

### Removing elements

Remove a single element by id:

```lua
ui:remove("panel")
```

This also unregisters any event handlers attached to that element.

### Nested / relative layout
Handles can create nested children with **relative layout** and **id prefixing**:

```lua
local header = ui:element({
    id = "header",
    type = "panel",
    rect = { unit = "px", x = 0, y = 0, w = W, h = 60 },
    style = { bg = "#111827" }
})

header:element({
    id = "title",
    type = "label",
    rect = { unit = "px", x = 20, y = 10, w = 300, h = 40 },
    props = { text = "STATUS" },
    style = { color = "#FFFFFF", font_size = 20 }
})
```

This creates a child element with id `header/title`.

**Best practice:** Use `parent:element()` for any logical container with children (headers, panels, toolbars). This keeps related elements grouped and creates clean hierarchical IDs.

---

## Input & events

### Element events
These are set directly on the element definition:

- `on_click` (buttons, **checkbox**, **toggle**, `interface_button`; payload from `props.value` on buttons when set)
- `on_change` (sliders, **select** option picks, **textinput** after end-edit)
- `on_toggle` (**select** header only — opens/closes the dropdown; optional if you use legacy manual `props.open`; default dropdown UX is client-managed — see [#### `select`](#select) above)

Handlers receive a normalized set of arguments:

- For `click` with no `props.value`, and for `toggle`: `playerName`
- For `click` when `props.value` is set: `value`, `playerName`
- For `change`: `value`, `playerName`
- For **`interface_mode`** (from **`interface_button`**): `value` (`"1"` / `"0"` after client toggle), `playerName`

### Register/unregister handlers dynamically
If you have a handle, you can change handlers after creation:

```lua
local btn = ui:get("btn")

btn:on("click", function(playerName)
    print("clicked", playerName)
end)

btn:off("click")
```

You can also unregister by passing `nil`:

```lua
btn:on("click", nil)
```

### Keyboard input (interface mode)
Keyboard events are surface-level:

```lua
ui:on_keydown(function(key)
    if key == "Escape" or key == "LeftAlt" then
        ss.exit_interface_mode()
    end
end)

ui:on_keyup(function(key)
end)
```

To unregister:

```lua
ui:on_keydown(nil)
ui:on_keyup(nil)
```

Keyboard events only work reliably when you enter **Interface Mode** (click the screen or use an `interface_button`).

You can query and exit interface mode programmatically:

```lua
if ss.is_interface_mode() then
    -- Currently capturing keyboard input
end

ss.exit_interface_mode()  -- Return to normal game input
```

### Frame-aligned input (on_frame)
If your script uses `on_frame` for smooth rendering (e.g., games), poll input events directly each frame:

```lua
local ui = ss.ui.surface("main")

ui:on_frame(function()
    for _, ev in ipairs(ui:poll_input()) do
        if ev.event == "keydown" then
            print("down", ev.value)
        elseif ev.event == "keyup" then
            print("up", ev.value)
        elseif ev.event == "click" then
            print("click", ev.id, ev.value)
        end
    end
end)
```

`poll_input()` drains a per-frame input queue so `on_frame` scripts get smooth, frame-aligned events. Tick-based handlers (`on_keydown`, `on_keyup`, `on_click`, `on_change`, etc.) still work; events are delivered to both paths for compatibility.

---

## Multiple views (surfaces)

You can maintain several named views and switch between them:

```lua
local main = ss.ui.surface("main")
local settings = ss.ui.surface("settings")

ss.ui.activate("main")
-- later
ss.ui.activate("settings")
```

Tip: you can keep writing to inactive surfaces; they will display the latest state when activated.

---

## Virtual resolution

By default, surfaces use the physical screen resolution (typically 480×272 for consoles). You can override this with `surface:set_resolution(w, h)` to create higher-resolution displays or match a specific aspect ratio.

```lua
local ui = ss.ui.surface("main")
ss.ui.activate("main")

-- Set a custom virtual resolution (e.g. 960×544 for 2x detail)
ui:set_resolution(960, 544)

local size = ui:size()   -- returns { w = 960, h = 544 }
```

All element positioning and sizing then uses the virtual coordinate space. The UI is scaled to fit the physical screen automatically.

You can query the current effective resolution at any time:

```lua
local res = ui:get_resolution()   -- returns { w, h }
```

`get_resolution()` and `size()` both return the effective resolution (virtual if set, physical otherwise).

**Limits:** Max virtual width and height are configurable (default 4096px each). Setting resolution to `0, 0` resets to the physical screen size.

---

## Canvas drawing

A **canvas** element gives you a pixel buffer you can draw on directly — useful for graphs, games, or custom visualizations.

### Creating a canvas

```lua
local ui = ss.ui.surface("main")
ui:element({
    id = "my_canvas",
    type = "canvas",
    rect = { unit = "px", x = 10, y = 10, w = 160, h = 120 }
})
```

### Drawing on the canvas

After creating the element, use `canvas_*` functions to draw. Colors can be **numeric** (`r, g, b [, a]`), **hex strings** (`"#RRGGBB"` / `"#RRGGBBAA"`), or **CSS-style** (`"rgb(r, g, b)"` / `"rgba(r, g, b, a)"`). Always call `canvas_apply` when you're done drawing.

```lua
-- Basic drawing
ui:canvas_clear("my_canvas", "#000000")                     -- clear to black
ui:canvas_pixel("my_canvas", 10, 10, "#FF0000")             -- single red pixel
ui:canvas_hline("my_canvas", 50, 0, 159, "#333333")         -- horizontal line at y=50
ui:canvas_vline("my_canvas", 80, 0, 119, "#333333")         -- vertical line at x=80
ui:canvas_line("my_canvas", 0, 0, 159, 119, "#FFFFFF", 2)   -- diagonal, 2px thick

-- Shapes
ui:canvas_rect("my_canvas", 20, 20, 40, 30, "#00FF00")      -- filled rectangle
ui:canvas_rect_outline("my_canvas", 20, 20, 40, 30, "#FFFF00") -- rectangle outline
ui:canvas_circle("my_canvas", 80, 60, 30, "#00AAFF")        -- circle outline
ui:canvas_fill_circle("my_canvas", 80, 60, 15, "#0066CC")   -- filled circle
ui:canvas_fill_triangle("my_canvas", 80, 10, 60, 50, 100, 50, "#FF6600") -- filled triangle

-- Multi-point & arcs
ui:canvas_polyline("my_canvas", {10,10, 50,30, 90,10, 130,30}, "#FFFFFF") -- connected lines
ui:canvas_arc("my_canvas", 80, 60, 40, 0, 90, "#FF00FF")    -- 90° arc (0°=up, clockwise)

ui:canvas_apply("my_canvas")  -- commit to screen
```

### Quick reference

| Function | Arguments |
|---|---|
| `canvas_clear` | `(id, color)` |
| `canvas_pixel` | `(id, x, y, color)` |
| `canvas_hline` | `(id, y, x1, x2, color)` |
| `canvas_vline` | `(id, x, y1, y2, color)` |
| `canvas_line` | `(id, x0, y0, x1, y1, color [, thickness])` |
| `canvas_rect` | `(id, x, y, w, h, color)` |
| `canvas_rect_outline` | `(id, x, y, w, h, color [, thickness])` |
| `canvas_circle` | `(id, cx, cy, r, color [, thickness])` |
| `canvas_fill_circle` | `(id, cx, cy, r, color)` |
| `canvas_fill_triangle` | `(id, x0, y0, x1, y1, x2, y2, color)` |
| `canvas_polyline` | `(id, {x,y,...}, color [, thickness])` |
| `canvas_arc` | `(id, cx, cy, r, startDeg, endDeg, color [, thickness])` |
| `canvas_apply` | `(id)` |
| `canvas_begin_update` | `(id)` — start a **grouped** multiplayer paint pass |
| `canvas_end_update` | `(id)` — end grouped paint |
| `canvas_with_update` | `(id, function)` — run a **synchronous** function between begin/end (callback must not yield) |

### Multiplayer canvas batching

With **command replication** on (default, BepInEx **ScriptedScreens.cfg** → **Multiplayer** → `CanvasCommandReplication`), the server sends **draw commands** to clients, which replay them locally. To avoid one network batch per primitive (and torn frames), wrap a full animation step in **`canvas_begin_update` / `canvas_end_update`** (or **`canvas_with_update`**) so many primitives become **one** logical batch when op/byte limits allow. Still call **`canvas_apply`** after drawing.

> **`commit()` required every `on_frame` for canvas animation in multiplayer.** Canvas ops are buffered until `surface:commit()` flushes them to clients. If your `on_frame` draws to a canvas but never calls `commit()`, clients see an empty or static canvas. Call `commit()` at the end of every frame function, exactly like the console canvas games (`SpaceInvaders.lua`, `Tetris.lua`, `Doom.lua`, etc.) and `VisorHudPong.lua`. This applies to **both** `ss.ui` (consoles/tablets) and `ss.hud` (visor) surfaces.

When **several** groups are waiting, **`CanvasCommandMinSyncAutoTune`** / **`CanvasCommandMinSyncInterval`** throttle send rate. A **single** pending group with **more than one** op (typical grouped frame) **skips** that delay for that flush so batched animation is not held back as if it were a backlog — **except for programmable visor HUD** (`ss.hud` / `ProgrammableVisorGlasses`), where that shortcut flooded bandwidth at Unity frame rate; visor hosts always use the normal throttle plus optional **`VisorCanvasCommandMinSyncFloorSeconds`** and a lower **`VisorCanvasDenseFrameOpThreshold`** so small canvases prefer one RGBA snapshot per flush (see **ScriptedScreens.cfg** → **Multiplayer**).

On the **game client**, several received batches in one Unity frame are usually **merged** into **one** GPU upload by default; intermediate steps may not show. For the smoothest motion when the server sends many small batches, set **`CanvasRemoteEveryBatchGpuUpload = true`** on the **client** (same Multiplayer section; more GPU work).

**Dedicated servers:** Lua and `canvas_*` APIs run from the **server’s** mod install. If `canvas_begin_update` is missing, update **ScriptedScreens** on the server (not only on your client).

---

## Persistence (save/load)

On **console boards**, **circuit boards**, **tablet cartridges**, and the **programmable visor**, ScriptedScreens persists a **UI snapshot** (elements, canvases, scroll positions) with the world automatically. Vanilla IC circuit housings do not use ScriptedScreens UI.

For **script-owned state** (current tab, drag offsets, silo contents, etc.), use StationeersLua **`ic.persist`** (string KV; survives save/load, host power cycles, and chip pull/reinsert when source is unchanged):

**Editing chip source** in the IC editor clears the host UI before the new script compiles so stale elements from the old code do not remain on screen.

```lua
local KEY = "ui"

local function persist_save(tbl)
    local ok, raw = pcall(util.json.encode, tbl)
    if ok and raw then ic.persist.set(KEY, raw) end
end

local function persist_load()
    if not ic.persist.has(KEY) then return nil end
    local raw = ic.persist.get(KEY)
    if type(raw) ~= "string" then return nil end
    local ok, t = pcall(util.json.decode, raw)
    return ok and t or nil
end
```

Restore with `persist_load()` at module level (KV is hydrated before init). Save when state changes or each tick. `ic.persist.clear()` wipes all keys. See `StationeersLuaDocs/docs/guide/persistence.md` and `Examples/` (e.g. `DragDropSilo.lua`, `VisorHudPong.lua`).

Legacy global `serialize()` / `deserialize(blob)` still work but are deprecated.

---

## Network features

ScriptedScreens exposes the `ic.net` API for peer-to-peer communication between Lua chips on the same data network.

### Core network functions

```lua
-- Get this chip's network ID
local myId = ic.net.id()

-- Get list of other Lua chip IDs on network
local peers = ic.net.peers()  -- returns array of IDs

-- Send a message to another chip
ic.net.send(targetId, "channel", { data = "hello" })

-- Broadcast to all peers
ic.net.broadcast("channel", { data = "hello" })

-- Receive messages (call in your update loop)
local msg = ic.net.receive("channel")
if msg then
    print(msg.sender, msg.data)
end
```

### Ping/pong

```lua
ic.net.ping(targetId)  -- send ping

local pong = ic.net.pong()  -- check for pong responses
if pong then
    print("Pong from", pong.sender, "latency:", pong.latency)
end
```

See `Examples/NetChat.lua`, `Examples/NetPeerMonitor.lua`, and `Examples/NetAnnouncements.lua` for complete network UI examples.

---

## Tablet targeting (cartridges only)

When running on a **tablet cartridge**, you can detect what the player is looking at using the `ss.tablet.target` API.

```lua
-- Subscribe to target updates (callback fires when player looks at something)
-- Set includeRoomAtmos=true to receive room/world atmosphere data.
-- When a target exists, ambient data is nested under data.world.
ss.tablet.target(function(data)
    if data.has_target then
        print("Looking at:", data.display_name)
        print("Distance:", data.distance, "m")
        print("Type:", data.target_kind or "unknown")
        
        -- Atmosphere data (pipes, tanks, vents)
        if data.atmosphere then
            print("Pressure:", data.atmosphere.pressure / 1000, "kPa")
            print("Temperature:", data.atmosphere.temperature, "K")
        end
        
        -- Logic values (machines, devices)
        if data.logic then
            for key, value in pairs(data.logic) do
                print(key, "=", value)
            end
        end
        
        -- Power state (batteries)
        if data.power then
            print("Charge:", data.power.charge, "/", data.power.max_charge)
        end

        -- Power usage (devices)
        if data.power_usage then
            print("Used:", data.power_usage.used_power, "W")
            print("Generated:", data.power_usage.generated_power, "W")
        end

        -- Data network (devices)
        if data.data_network then
            print("Data network:", data.data_network.id, "devices:", data.data_network.device_count)
        end
        
        -- Slot contents
        if data.slots then
            for _, slot in ipairs(data.slots) do
                if slot.is_occupied then
                    print("Slot", slot.index, ":", slot.occupant_name)
                end
            end
        end
    else
        if data.atmosphere_mode == "room" and data.room then
            print("Room:", data.room.name)
        end
    end
    if data.world and data.world.atmosphere then
        print("Ambient pressure:", data.world.atmosphere.pressure / 1000, "kPa")
    end
end, 0.1, true)  -- Update interval in seconds (min 0.05)

-- Unsubscribe
ss.tablet.target(nil)
```

### Tablet wireless data networks (wireless cartridges only)

Wireless Lua cartridges can tether to omni power transmitters on the data network. The wireless API exposes
in-range transmitters and lets scripts connect to a network as if the tablet were wired in.

```lua
-- List available omni transmitters in range
local transmitters = ss.tablet.wireless.list()
for i, t in ipairs(transmitters) do
    print(i, t.name, t.id, t.network_id, t.distance .. "m")
end

-- Connect by transmitter id (or network_id), with mesh enabled
local ok, err = ss.tablet.wireless.connect(transmitters[1].id, true)
if not ok then
    print("connect failed:", err)
end

-- Query status
local status = ss.tablet.wireless.status()
print("connected:", status.connected, "in range:", status.in_range)

-- Disconnect
ss.tablet.wireless.disconnect()
```

`mesh = true` allows seamless handoff between multiple omni transmitters on the same data network while moving
through your base. The API throws if used on non-wireless cartridges or when the tablet is not powered on.

#### Wireless data parity

Once connected to a remote network, wireless cartridges have **full data parity** with wired boards. The following operations all work against the remote network:

- **Batch operations** — `batch_read()` / `batch_write()` across remote network devices
- **Device listing** — `device_list()` returns devices on the remote network
- **ID-based reads/writes** — `read_id()`, `write_id()`, `read_slot_id()`, `write_slot_id()`
- **Device memory by ID** — `mem_get_id()`, `mem_put_id()`, `mem_clear_id()`
- **Library chip require()** — `require("modname")` finds library chips on the remote network
- **Name-based lookup** — `find()`, `find_all()` search the remote network by device display name
- **Inter-chip networking** — `ic.net.send()`, `ic.net.publish()`, `ic.net.request()`, etc.

### Target snapshot fields

Top-level fields:

| Field | Description |
|-------|-------------|
| `has_target` | Boolean - whether something is targeted |
| `reference_id` | Target Thing's unique ID |
| `distance` | Distance to target in meters |
| `prefab_name` | Internal prefab name |
| `prefab_hash` | Prefab hash (Animator-style) |
| `display_name` | Localized display name |
| `custom_name` | Player-assigned custom name |
| `target_kind` | Target classification (`human`, `entity`, `device`, `item`, `structure`, `thing`) |
| `position` | `{x, y, z}` world coordinates |
| `health`, `max_health` | Damage state (DynamicThing) |
| `atmosphere` | Atmosphere snapshot table (see below) |
| `atmosphere_mode` | Target atmosphere mode (for targets) or `"room"`/`"world"` when no target and includeRoomAtmos is enabled |
| `network` | Atmosphere network info `{id, type}` (pipe/landing_pad/etc) |
| `thermal` | Thermal energy info `{energy_convected, energy_radiated}` (J) |
| `power` | Battery info `{powered, on, charge, max_charge, charge_ratio}` (J) |
| `power_usage` | Power usage info `{used_power, generated_power, net_power}` (W) |
| `power_network` | Power cable network info (see below) |
| `data_network` | Data cable network info (see below) |
| `slots` | Array of slot info with occupant details (see below) |
| `logic` | Table of logic values: IC-style names (`Setting`, `Power`, …), optional extras (`Error`, `Maximum`, `Volume`, `TotalMoles`, hashes), and gas/liquid ratios when the target exposes them |
| `room` | `{id, name}` room info for structure targets or ambient room when includeRoomAtmos is enabled |
| `world` | `{atmosphere_mode, room?, atmosphere}` ambient snapshot when includeRoomAtmos is enabled and there is a target |

#### Atmosphere fields (`data.atmosphere`)

| Field | Description |
|-------|-------------|
| `pressure` | Total pressure (Pa) |
| `pressure_gases` | Gas-only pressure (Pa) |
| `pressure_gases_and_liquids` | Gas + liquid pressure (Pa) |
| `temperature` | Temperature (K) |
| `total_moles` | Total moles (gas + liquid) |
| `total_moles_gases` | Total gas moles |
| `total_moles_liquids` | Total liquid moles |
| `volume` | Atmosphere volume (L) |
| `total_volume_liquids` | Liquid volume (L) |
| `liquid_volume_ratio` | Liquid volume / total volume (0-1) |
| `last_tick_latent_energy` | Latent energy from last tick (J) |
| `allowed_matter_state` | `Gas`, `Liquid`, or `All` |
| `mode` | Atmosphere mode (`World`, `Network`, `Thing`, etc.) |
| `pressure_delta` | Delta pressure between target and ambient (Pa, when available) |
| `max_pressure` | Target max safe delta pressure (Pa) |
| `warning_pressure` | Warning threshold delta pressure (Pa) |
| `danger_pressure` | Danger threshold delta pressure (Pa) |
| `pressure_ratio` | `pressure_delta / max_pressure` ratio |
| `gases` | Table of gas moles keyed by gas name |

#### Atmos network fields (`data.network`)

| Field | Description |
|-------|-------------|
| `id` | Atmos network reference id |
| `type` | Atmos network type (`pipe`, `landing_pad`, etc.) |
| `content_type` | Network content type (`gas`/`liquid`) |
| `pressure` | Network pressure (Pa) |
| `temperature` | Network temperature (K) |
| `total_moles` | Network total moles |
| `volume` | Network volume (L) |
| `total_moles_gases` | Network gas moles |
| `total_moles_liquids` | Network liquid moles |

#### Power usage fields (`data.power_usage`)

| Field | Description |
|-------|-------------|
| `used_power` | Power used by this device (W) |
| `generated_power` | Power generated by this device (W) |
| `net_power` | Net power (generated - used) (W) |

#### Power network fields (`data.power_network`)

| Field | Description |
|-------|-------------|
| `id` | Cable network reference id |
| `type` | Cable network type (`cablenetwork`/`wirelessnetwork`) |
| `required_load` | Required load (W) |
| `potential_load` | Potential load (W) |
| `current_load` | Current load (W) |
| `shortfall_load` | Shortfall load (W) |
| `during_tick_load` | During-tick load (W) |
| `battery_count` | Batteries on the network |
| `device_count` | Devices on the network |
| `data_device_count` | Data devices on the network |
| `power_device_count` | Power devices on the network |
| `total_charge` | Total battery charge on the network (J) |
| `max_charge` | Total battery capacity on the network (J) |
| `charge_ratio` | Total battery charge ratio (0-1) |

#### Data network fields (`data.data_network`)

| Field | Description |
|-------|-------------|
| `id` | Data network reference id |
| `type` | Data network type (`cablenetwork`/`wirelessnetwork`) |
| `device_count` | Devices on the network |
| `data_device_count` | Data devices on the network |
| `power_device_count` | Power devices on the network |

#### Slot fields (`data.slots[]`)

| Field | Description |
|-------|-------------|
| `index` | Slot index |
| `type` | Slot type string |
| `is_occupied` | Whether an occupant exists |
| `occupant_id` | Occupant reference id |
| `occupant_name` | Occupant display name |
| `occupant_prefab` | Occupant prefab name |
| `quantity` | Stack quantity (Stackable only) |
| `max_quantity` | Max stack quantity (Stackable only) |

See `Examples/AtmosAnalyzer.lua`, `Examples/DeviceInspector.lua`, and `Examples/EnergyNetworkTarget.lua` for complete tablet targeting examples.

---

## Icon enum tables (`ss.ui.icons`)

The `ss.ui.icons` table provides discoverable icon names for the `icon` element type.

### Gas icons (`ss.ui.icons.gas`)

`Oxygen`, `Nitrogen`, `CarbonDioxide` (alias `CO2`), `Methane` (alias `Volatiles`), `Pollutant`, `Water`, `NitrousOxide` (alias `N2O`), `LiquidNitrogen`, `LiquidOxygen`, `LiquidMethane` (alias `LiquidVolatiles`), `Steam`, `LiquidCarbonDioxide` (alias `LiquidCO2`), `LiquidPollutant`, `LiquidNitrousOxide`, `Hydrogen` (alias `H2`), `LiquidHydrogen`, `PollutedWater`, `Hydrazine`, `LiquidHydrazine`, `LiquidAlcohol` (alias `Ethanol`), `Helium` (alias `He`), `LiquidSodiumChloride` (alias `NaCl`), `Silanol`, `LiquidSilanol`, `HydrochloricAcid` (alias `HCl`), `LiquidHydrochloricAcid`, `Ozone` (alias `O3`), `LiquidOzone`

### Slot icons (`ss.ui.icons.slot`)

`None`, `Helmet`, `Suit`, `Back`, `GasFilter`, `GasCanister`, `Motherboard`, `Circuitboard`, `DataDisk`, `Organ`, `Ore`, `Plant`, `Uniform`, `Entity`, `Battery`, `Egg`, `Belt`, `Tool`, `Appliance`, `Ingot`, `Torpedo`, `Cartridge`, `AccessCard`, `Magazine`, `Circuit`, `Bottle`, `ProgrammableChip` (alias `Chip`), `Glasses`, `CreditCard`, `DirtCanister`, `SensorProcessingUnit` (alias `SPU`), `LiquidCanister`, `LiquidBottle`, `Wreckage`, `SoundCartridge`, `DrillHead`, `ScanningHead`, `Flare`, `SuitMod`, `Crate`, `Portables`, `RocketPayload`

### Prefab icons (`ss.ui.icons.prefab`)

A curated set of common item/structure prefab names. You can also pass **any** prefab name string or numeric prefab hash directly — the enum table is just for discoverability.

**Ingots:** `IronIngot`, `SteelIngot`, `CopperIngot`, `GoldIngot`, `SilverIngot`, `NickelIngot`, `LeadIngot`, `SiliconIngot`, `CoalIngot`, `ElectrumIngot`, `SolderIngot`, `ConstantanIngot`, `InvarIngot`, `AstroloyIngot`, `HastelloyIngot`, `WaspaloyIngot`, `InconelIngot`, `StelliteIngot` (`SteliteIngot` is a legacy alias for the same prefab)

**Ores:** `IronOre`, `CopperOre`, `GoldOre`, `SilverOre`, `NickelOre`, `LeadOre`, `SiliconOre`, `CoalOre`, `UraniumOre`, `CobaltOre`

**Ice:** `IceOxite`, `IceVolatiles`, `IceNitrice`

**Tools:** `Wrench`, `Screwdriver`, `Crowbar`, `Welder`, `AngleGrinder`, `Pickaxe`, `Drill`, `DuctTape`, `Multitool`, `Tablet`, `Labeller`

**Components:** `Cable`, `CableCoil`, `Pipe`, `SteelSheets`, `IronSheets`, `CopperSheets`, `GoldSheets`, `SteelFrames`, `IronFrames`, `CircuitBoard`, `IC`, `LuaChip`, `Battery`, `BatteryLarge`, `GasCanister`, `GasFilter`, `DataDisk`, `SensorLens`, `Motor`

**Gas canisters (Stationpedia gas thumbnails via `gas:` token):** `GasOxygen`, `GasNitrogen`, `GasCO2`, `GasVolatiles`, `GasWater`, `GasN2O` (these are not `prefab:ItemGasCanister*`; those prefab names are not valid for `Prefab.TryFind` thumbnails)

**Food:** `Potato`, `Tomato`, `Pumpkin`, `Corn`, `Wheat`, `Soybean`, `Rice`, `Mushroom`, `CannedFood`

**Equipment:** `Helmet`, `Suit`, `Jetpack`, `MiningBelt`, `ToolBelt`, `Uniform`

**Machines:** `ArcFurnace`, `Autolathe`, `ElectronicsPrinter`, `HydraulicPipeBender`, `Furnace`, `SolarPanel`, `BatterySmall`, `BatteryLargeStruct`, `AdvancedFurnace`, `Computer`, `Console`, `Light`, `Tank`, `GasMixer`, `PipeAnalyzer`, `ActiveVent`, `PassiveVent`, `Filtration`

### Prefab icons (`icon_type="prefab"`)

Display the in-game thumbnail for any item, structure, or object. Accepts a prefab name string or a numeric prefab hash.

```lua
-- Using the enum table (no icon_type needed)
ui:element({
    id = "steel", type = "icon",
    rect = { unit = "px", x = 10, y = 10, w = 32, h = 32 },
    props = { name = ss.ui.icons.prefab.SteelIngot },
})

-- Using a direct prefab name string (icon_type required for raw strings)
ui:element({
    id = "furnace", type = "icon",
    rect = { unit = "px", x = 50, y = 10, w = 32, h = 32 },
    props = { icon_type = "prefab", name = "StructureArcFurnace" },
})

-- Using a numeric prefab hash
ui:element({
    id = "item", type = "icon",
    rect = { unit = "px", x = 90, y = 10, w = 32, h = 32 },
    props = { icon_type = "prefab", name = tostring(prefabHash) },
})

-- With painted color variant (color_index prop)
ui:element({
    id = "painted", type = "icon",
    rect = { unit = "px", x = 130, y = 10, w = 32, h = 32 },
    props = { icon_type = "prefab", name = "ItemIronFrames", color_index = "2" },
})
```

| Prop | Description |
|------|-------------|
| `name` | Enum value (auto-detects) or raw prefab name/hash |
| `icon_type` | `"prefab"` — only needed for raw strings |
| `color_index` | Optional painted color variant index |

| Style | Description |
|-------|-------------|
| `tint` | Icon tint color (default white) |

### Usage examples

```lua
-- Gas icon via enum (auto-detected)
ui:element({
    id = "gas_icon", type = "icon",
    rect = { unit = "px", x = 10, y = 10, w = 24, h = 24 },
    props = { name = ss.ui.icons.gas.Oxygen },
    style = { tint = "#3B82F6" },
})

-- Slot icon via enum (auto-detected)
ui:element({
    id = "slot_icon", type = "icon",
    rect = { unit = "px", x = 40, y = 10, w = 24, h = 24 },
    props = { name = ss.ui.icons.slot.Battery },
})

-- Prefab icon via enum (auto-detected)
ui:element({
    id = "item_icon", type = "icon",
    rect = { unit = "px", x = 70, y = 10, w = 32, h = 32 },
    props = { name = ss.ui.icons.prefab.SteelIngot },
})
```

---

## Charts & Tables

### Sparkline

A lightweight chart that draws a polyline from data points. Useful for live sensor feeds, history graphs, or oscilloscope-style displays.

```lua
-- Data as a numeric array
local history = { 21.0, 21.3, 22.1, 21.8, 23.0, 22.5, 21.9 }

ui:element({
    id = "temp_chart",
    type = "sparkline",
    rect = { unit = "px", x = 10, y = 50, w = 200, h = 60 },
    props = {
        data = history,      -- array of floats
        min = 18,            -- optional: auto-detected if omitted
        max = 28,
    },
    style = {
        bg = "#111827",
        line_color = "#22C55E",
        fill_color = "#22C55E20",  -- semi-transparent fill under line
        thickness = 2,
    }
})
```

| Prop | Description |
|------|-------------|
| `data` | Array of float values |
| `min` | Minimum value for Y axis (auto-detected if omitted) |
| `max` | Maximum value for Y axis (auto-detected if omitted) |

| Style | Description |
|-------|-------------|
| `bg` | Background color |
| `line_color` | Polyline color (default green) |
| `fill_color` | Area fill under the line (default transparent) |
| `thickness` | Line thickness in pixels (default 2) |

### Bar Chart

A vertical bar chart with labeled bars, optional per-bar colors, and value labels.

```lua
ui:element({
    id = "atmos_bars",
    type = "barchart",
    rect = { unit = "px", x = 10, y = 50, w = 300, h = 100 },
    props = {
        labels = { "O2", "N2", "CO2", "H2O" },
        values = { 21.1, 78.1, 0.04, 1.2 },
        colors = { "#3B82F6", "#6366F1", "#EF4444", "#06B6D4" },  -- optional per-bar colors
        max = 100,
    },
    style = {
        bg = "#111827",
        font_size = 9,
        gap = 4,
        show_values = "true",
    }
})
```

| Prop | Description |
|------|-------------|
| `labels` | Array of bar labels |
| `values` | Array of float values |
| `colors` | Array of hex colors per bar (cycles if fewer than bars) |
| `min` | Minimum value (default 0) |
| `max` | Maximum value (auto-detected if omitted) |

| Style | Description |
|-------|-------------|
| `bg` | Background color |
| `bar_color` | Default bar color (when `colors` prop not set) |
| `label_color` | Label text color |
| `value_color` | Value text color above bars |
| `font_size` | Label/value font size |
| `gap` | Gap between bars in pixels (default 4) |
| `show_values` | `"true"` to show value labels above bars |

### Line Chart

A multi-series line chart with axes, grid lines, and an optional legend. Each series is rendered as a separate polyline using the sparkline engine internally.

```lua
ui:element({
    id = "power_chart",
    type = "linechart",
    rect = { unit = "px", x = 10, y = 50, w = 300, h = 120 },
    props = {
        series = {
            { 800, 750, 900, 850, 920 },
            { 600, 580, 640, 700, 650 },
        },
        series_colors = { "#22C55E", "#EF4444" },
        series_labels = { "Generated", "Load" },
        x_labels = { "1h", "3h", "6h", "9h", "12h" },
    },
    style = {
        bg = "#111827",
        show_grid = "true",
        show_legend = "true",
        fill = "true",
        thickness = 2,
        font_size = 9,
    }
})
```

| Prop | Description |
|------|-------------|
| `series` | Array of float arrays (each inner array is a series) |
| `series_colors` | Array of hex colors per series (defaults cycle through 6 built-in colors) |
| `series_labels` | Array of legend labels per series |
| `x_labels` | Array of X-axis labels |
| `min` | Y-axis minimum (auto-detected if omitted) |
| `max` | Y-axis maximum (auto-detected if omitted) |

| Style | Description |
|-------|-------------|
| `bg` | Background color |
| `grid_color` | Horizontal grid line color |
| `axis_color` | Axis line color |
| `label_color` | Axis/legend label color |
| `thickness` | Line thickness (default 2) |
| `font_size` | Label font size |
| `show_grid` | `"true"` to show horizontal grid lines with Y-axis labels |
| `show_legend` | `"true"` to show series legend at top |
| `fill` | `"true"` to fill area under each line |

### Gauge

A 180° arc gauge/meter with colored threshold zones and a needle. Useful for pressure, temperature, or any value with normal/warning/danger ranges.

```lua
ui:element({
    id = "pressure_gauge",
    type = "gauge",
    rect = { unit = "px", x = 10, y = 50, w = 120, h = 80 },
    props = {
        value = 101.3,
        min = 0,
        max = 200,
        warn = 0.65,       -- fraction where warn zone starts
        danger = 0.85,     -- fraction where danger zone starts
        label = "PRESSURE",
        unit = " kPa",
    },
    style = {
        bg = "#111827",
        arc_thickness = 8,
        font_size = 12,
        value_color = "#E2E8F0",
        label_color = "#64748B",
    }
})
```

| Prop | Description |
|------|-------------|
| `value` | Current value |
| `min` | Minimum value |
| `max` | Maximum value |
| `warn` | Fraction (0..1) where warning zone starts (default 0.6) |
| `danger` | Fraction (0..1) where danger zone starts (default 0.85) |
| `invert` | If true, color bands are reversed (danger on left, normal on right) |
| `label` | Optional label text below the value |
| `unit` | Optional unit suffix appended to the value display |

| Style | Description |
|-------|-------------|
| `bg` | Background color |
| `arc_color` | Arc border color |
| `needle_color` | Needle color |
| `normal_color` | Normal zone color |
| `warn_color` | Warning zone color |
| `danger_color` | Danger zone color |
| `value_color` | Value text color |
| `label_color` | Label text color |
| `arc_thickness` | Arc ring thickness in pixels (default 10) |
| `font_size` | Value/label font size |

### Table

A data table with column headers, alternating row colors, row selection, and sortable column headers.

```lua
ui:element({
    id = "sensor_table",
    type = "table",
    rect = { unit = "px", x = 10, y = 120, w = 300, h = 120 },
    props = {
        columns = { "Zone", "Temp", "Status" },
        rows = {
            { "HAB-1", 21.5, "OK" },
            { "HAB-2", 19.0, "WARN" },
            {
                "AIRLOCK",
                { text = "8.2", style = { color = "#F59E0B" } },
                { text = "ALERT", style = { color = "#EF4444" } },
            },
        },
        col_widths = { 2, 1, 1 },       -- relative column widths
        selected_row = 1,               -- 1-based index (0 for none)
        sort_column = 1,                -- 1-based column index (0 for none)
        sort_dir = "asc",               -- "asc" or "desc"
    },
    style = {
        header_bg = "#1E293B",
        header_color = "#94A3B8",
        row_bg = "#111827",
        alt_row_bg = "#0F172A",
        row_color = "#E2E8F0",
        selected_bg = "#1E3A5F",
        selected_color = "#67E8F9",
        font_size = 11,
        row_height = 22,
    },
    on_click = function(value, playerName)
        -- value is the 1-based row index that was clicked
        print("Row clicked: " .. tostring(value))
    end,
    on_change = function(value, playerName)
        -- value is the 1-based column index (header clicked for sorting)
        print("Sort by column: " .. tostring(value))
    end
})
```

| Prop | Description |
|------|-------------|
| `columns` | Array of column header strings or column maps (`{ title, width }`) |
| `rows` | Array of rows, each row is an array of cell values |
| `col_widths` | Array of relative column widths (default all equal) |
| `selected_row` | 1-based selected row index (0 for none) |
| `sort_column` | 1-based sorted column index (0 for none) |
| `sort_dir` | `"asc"` or `"desc"` |

| Event | Callback args |
|-------|---------------|
| `on_click` | `(rowIndex, playerName)` — data row clicked |
| `on_change` | `(columnIndex, playerName)` — header clicked (sort) |

---

## Layout Helpers

All layout helpers are available under **`ss.ui`** and also aliased under **`ss.hud`** for visor scripts: `ss.hud.grid(...)`, `ss.hud.flex(...)`, and `surface:layout(...)`.

### Grid

`ss.ui.grid(opts, children)` computes fixed-column grid cell rects for an array of child definitions. Each child gets its `rect` overwritten with the computed position and size. The function returns the children array so you can iterate and call `surface:element()`.

```lua
for _, def in ipairs(ss.ui.grid({
    rect = { unit = "px", x = 10, y = 50, w = 460, h = 200 },
    cols = 3,
    gap = 4,
    padding = 8,          -- optional; inset from container edges
    row_height = 60,      -- optional; defaults to square cells
}, {
    { id = "c1", type = "panel", style = { bg = "#1E293B" } },
    { id = "c2", type = "panel", style = { bg = "#334155" } },
    { id = "c3", type = "panel", style = { bg = "#1E293B" } },
    { id = "c4", type = "panel", style = { bg = "#334155" } },
    { id = "c5", type = "panel", style = { bg = "#1E293B" } },
    { id = "c6", type = "panel", style = { bg = "#334155" } },
})) do
    ui:element(def)
end
```

| Option | Description |
|--------|-------------|
| `rect` | Container rect (same format as element rects) |
| `cols` | Number of columns (default 2) |
| `gap` | Gap between cells in pixels (default 4) |
| `padding` | Inset from container edges (number or table, see [Padding](#padding)) |
| `row_height` | Fixed row height; if omitted, cells are square |

Returns the children array with computed rects applied.

### Flex

`ss.ui.flex(opts, children)` computes flexbox-style row/column rects for an array of child definitions. Children with a `flex` field grow proportionally; others use a fixed size from their `rect`. Returns the children array so you can iterate and call `surface:element()`.

```lua
for _, def in ipairs(ss.ui.flex({
    rect = { unit = "px", x = 10, y = 10, w = 460, h = 30 },
    direction = "row",
    gap = 6,
    padding = 4,          -- optional; inset from container edges
    align = "center",     -- cross-axis: start|center|end|stretch
    justify = "start",    -- main-axis: start|center|end|between|evenly
}, {
    { id = "name", type = "label", flex = 2,
      props = { text = "SENSOR NETWORK" },
      style = { font_size = 14, color = "#22C55E" } },
    { id = "spacer", type = "panel", flex = 1,
      style = { bg = "#00000000" } },
    { id = "status", type = "label",
      rect = { w = 60 },  -- fixed 60px width
      props = { text = "LIVE" },
      style = { font_size = 11, color = "#EAB308", align = "right" } },
})) do
    ui:element(def)
end
```

| Option | Description |
|--------|-------------|
| `rect` | Container rect |
| `direction` | `"row"` (default) or `"column"` |
| `gap` | Gap between items in pixels (default 4) |
| `padding` | Inset from container edges (number or table, see [Padding](#padding)) |
| `align` | Cross-axis alignment: `"stretch"` (default), `"start"`, `"center"`, `"end"` |
| `justify` | Main-axis distribution: `"start"` (default), `"center"`, `"end"`, `"between"`, `"evenly"` |

Children with `flex = N` share remaining space proportionally. Children without `flex` use their `rect.w` (row) or `rect.h` (column) as a fixed size.

Returns the children array with computed rects applied.

### Padding

All layout helpers (grid, flex, and nested layout) support a `padding` option that insets children from the container edges. Padding is applied *before* the layout algorithm runs.

```lua
-- Uniform padding on all sides
padding = 8

-- Per-side padding
padding = { top = 4, right = 8, bottom = 4, left = 8 }

-- Shorthand: vertical/horizontal
padding = { vertical = 6, horizontal = 10 }
```

### Nested Layout (`ui:layout`)

`surface:layout(def)` recursively processes a tree of nested layout containers and emits all leaf elements in a single call. This is the **recommended** way to build complex UIs - no manual pixel positioning needed.

Returns a **handles table** mapping each element `id` to its handle, so you can update elements later via `handles.my_id:set_props(...)`.

```lua
local h = ui:layout({
    layout = "flex",    -- "flex" (default) or "grid"
    rect = { unit = "px", x = 0, y = 0, w = 480, h = 272 },
    direction = "column", gap = 0,
    children = {
        -- Title bar (fixed 24px height)
        { layout = "flex", rect = { h = 24 }, direction = "row", gap = 0,
          children = {
            { id = "hdr", type = "panel", flex = 1, style = { bg = "#1E293B" } },
            { id = "title", type = "label", flex = 1,
              props = { text = "MY APP" },
              style = { font_size = 13, color = "#22C55E" } },
        }},

        -- Content area: two columns
        { layout = "flex", flex = 1, direction = "row", gap = 8, padding = 6,
          children = {
            -- Left column
            { layout = "flex", flex = 1, direction = "column", gap = 4,
              children = {
                { id = "chart", type = "sparkline", flex = 1,
                  props = { data = "1|2|3|4|5" },
                  style = { bg = "#111827" } },
            }},
            -- Right column
            { layout = "flex", flex = 1, direction = "column", gap = 4,
              children = {
                { id = "info", type = "label", flex = 1,
                  props = { text = "Details here" },
                  style = { color = "#E2E8F0" } },
            }},
        }},
    }
})

-- Update elements later using handles
h.title:set_props({ text = "UPDATED TITLE" })
h.chart:set_props({ data = "5|4|3|2|1" })
ui:commit()
```

**Node types in the tree:**

| Pattern | Behavior |
|---------|----------|
| Has `children` but no `id` | Pure layout container — computes child rects, not rendered |
| Has `id` but no `children` | Leaf element — emitted as a UI element |
| Has both `id` and `children` | Emitted as a UI element (defaults to `"panel"` if no `type`), then children are laid out inside it |

**Layout options on container nodes:**

| Field | Description |
|-------|-------------|
| `layout` | `"flex"` (default), `"grid"`, or shorthand `"row"` / `"column"` (equivalent to `layout = "flex"` + `direction = "row"` / `"column"`). Anything other than `"grid"` is treated as flex. |
| `direction` | `"row"` (default) or `"column"`. Ignored when `layout` is `"row"` / `"column"` (the shorthand wins). |
| `gap` | Spacing between children (default 4) |
| `padding` | Inset from container edges |
| `align` | Cross-axis alignment (flex only) |
| `justify` | Main-axis distribution (flex only) |
| `cols` | Number of columns (grid only, default 2) |
| `row_height` | Row height (grid only) |
| `offset` | Optional post-layout translation: `{ dx = N, dy = N }` (or `{ x = N, y = N }`) applied after flex/grid computes the child rect |

**Sizing children:**

| Field | Behavior |
|-------|----------|
| `flex = N` | Grows proportionally within available space |
| `rect = { w = N }` | Fixed width (in a row layout) |
| `rect = { h = N }` | Fixed height (in a column layout) |
| Neither | Defaults to 40px fixed |

**Auto drag groups for layout subtrees:**

When a layout-emitted container is draggable, you can ask the runtime to auto-build its `drag_group` from every descendant element id in the same subtree:

```lua
{
    id = "deck_power",
    type = "panel",
    layout = "column",
    rect = { w = 340, h = 220 },
    offset = { dx = off.power.dx, dy = off.power.dy },
    props = {
        draggable = "true",
        drag_group = "auto",        -- or drag_group_auto = true
    },
    children = {
        -- every descendant id is included automatically
    },
}
```

This removes the need to hand-maintain comma-separated lists like `"deck,title,row_1,row_2,bar_1,bar_2,..."` when using `surface:layout(...)`.

---

## Live updates (animating charts, gauges, tables)

Use element handles + `set_props` inside a `tick()` function to update widgets every frame (or at a throttled interval):

```lua
local ui = ss.ui.surface("main")
ss.ui.activate("main")

-- Create a sparkline and a gauge
local spark = ui:element({
    id = "temp_spark", type = "sparkline",
    rect = { unit = "px", x = 10, y = 10, w = 200, h = 60 },
    props = { data = { 20, 20, 20, 20, 20 } },
    style = { bg = "#111827", color = "#22C55E" }
})

local gauge = ui:element({
    id = "pressure", type = "gauge",
    rect = { unit = "px", x = 220, y = 10, w = 100, h = 60 },
    props = { value = "101.3", min = "80", max = "120", label = "kPa" },
})

ui:commit()

-- Rolling buffer for sparkline
local history = { 20, 20, 20, 20, 20 }
local accum = 0

function tick(dt)
    accum = accum + dt
    if accum < 0.5 then return end  -- throttle to 2 Hz
    accum = 0

    -- Push new value into history
    table.remove(history, 1)
    history[#history + 1] = 20 + math.sin(os.clock()) * 4

    -- Update sparkline data
    spark:set_props({ data = history })

    -- Update gauge value
    gauge:set_props({ value = string.format("%.1f", 101.3 + math.cos(os.clock()) * 5) })

    ui:commit()
end
```

The same pattern works for bar charts (`values`), line charts (`series`), and tables (`rows`, `selected_row`, `sort_column`).

---

## Image element

Display remote images (PNG, JPG, animated GIF) on your UI with `type = "image"`.

```lua
ui:element({
    id = "logo",
    type = "image",
    rect = { unit = "px", x = 10, y = 10, w = 200, h = 120 },
    props = { url = "https://example.com/image.png" },
})
```

- Each client downloads the image independently — the URL flows through the standard UI sync pipeline.
- Animated GIFs play back frame-by-frame with correct timing, transparency, and looping.
- Images are cached in a per-client LRU cache (default 64 entries) to avoid re-downloading.
- Transparency is fully supported (PNG alpha, GIF transparency).

**Server config:** `AllowRemoteImages` (default: `true`) gates whether image elements are processed. `MaxImageDimension` (default: 1024) limits max width/height. `ImageCacheSize` (default: 64) controls the LRU cache.

| Prop | Description |
|------|-------------|
| `url` | HTTP/HTTPS URL to a PNG, JPG, or GIF image |

See `Examples/ImageElement.lua` for a complete example.

---

## Media streaming (video)

Play HTTP video streams on your UI with `type = "media"`. Video is rendered to a texture and audio is spatialized from the screen position.

```lua
ui:element({
    id = "player",
    type = "media",
    rect = { unit = "px", x = 0, y = 0, w = 480, h = 272 },
    props = {
        url = "https://example.com/video.mp4",
        playing = "true",
        volume = "0.8",
        loop = "true",
        -- time = "30.0",  -- optional: seek to specific time
    },
})
```

- Video plays via Unity's VideoPlayer; audio is routed through a 3D AudioSource.
- Audio responds to atmosphere — muffled in vacuum, normal in pressurized rooms.
- Players can adjust per-screen volume with **Ctrl+Alt+MouseWheel** while looking at the screen.
- A global mute toggle is configurable in the client config.
- If a **mixer snapshot** interrupts playback (for example during an airlock pressurisation cycle), audio **restarts** when the server still expects the clip to be playing — it does not stay permanently silent.

**Server config:** `EnableExperimentalVideo` (default: `false`) must be enabled on the server. `AllowMediaPlayback` (default: `true`) is the master switch for all media. `AllowedMediaTypes` restricts file extensions. `MaxResolutionWidth/Height` and `MaxFPS` limit resource usage.

**Client config:** `EnableMediaLocally` (default: `true`) lets players opt out of all media locally. `ClientMasterVolume` (default: 0.5) scales all media audio.

| Prop | Description |
|------|-------------|
| `url` | HTTP/HTTPS URL to a video file (mp4, webm, etc.) |
| `playing` | `"true"` / `"false"` — playback state |
| `volume` | `"0"` to `"1"` — server-set volume (default 1) |
| `loop` | `"true"` / `"false"` — loop playback |
| `time` | Seek to a specific time in seconds (optional) |

See `Examples/MediaPlayer.lua` for a complete example.

---

## Sound playback

Play sounds from your scripts using `ss.play_sound()`. Sounds originate from the screen/tablet position and respond to atmosphere — muffled in vacuum, normal in pressurized rooms — matching the game's built-in audio behavior.

### Playing built-in game sounds

Use the `ss.sounds` enum table for discoverable sound names:

```lua
-- One-shot sound
ss.play_sound(ss.sounds.LogicOnBeep)

-- With options
ss.play_sound(ss.sounds.CompletedChime, { volume = 0.5 })

-- Looping sound with explicit id (for later stop)
ss.play_sound(ss.sounds.LogicOn, { loop = true, id = "alarm" })

-- Play an announcement / alert
ss.play_sound(ss.sounds.alerts.Warning)
ss.play_sound(ss.sounds.alerts.IntruderAlert, { loop = true, id = "intruder" })
```

### Stopping sounds

```lua
-- Stop a specific named sound
ss.stop_sound("alarm")

-- Stop all sounds on this device
ss.stop_all_sounds()
```

### Playing remote audio

If the server has media enabled (`AllowMediaPlayback = true`), you can also play wav/mp3/ogg files from URLs:

```lua
ss.play_sound("https://example.com/alert.wav", {
    volume = 0.7,
    loop = false,
    id = "web_sound",
})
```

Remote audio is downloaded per-client and played through a local AudioSource with 3D spatial audio and atmosphere-based volume attenuation.

### API reference

| Function | Description |
|----------|-------------|
| `ss.play_sound(src, opts?)` | Play a sound. Returns the sound id string. |
| `ss.stop_sound(id)` | Stop a specific sound by id. |
| `ss.stop_all_sounds()` | Stop all sounds on this device. |

**Options table (all optional):**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `volume` | number | 1.0 | Volume (0..1) |
| `loop` | boolean | false | Loop the sound |
| `id` | string | auto | Explicit id for later stop (auto-generated if omitted) |

### Built-in sound names (`ss.sounds`)

**UI feedback:** `ActivateButton`, `SwitchOn`, `SwitchOff`, `DialTurn`, `CompletedChime`, `DirectionNextButton`, `DirectionPreviousButton`, `Label`, `LabelConfirm`, `LabelCancel`

**Logic / IC:** `LogicOnBeep`, `LogicOffBeep`, `LogicError`, `LogicOn`, `LogicOff`, `LogicRead`, `LogicWrite`, `LogicMath`, `Error`

**Mechanical:** `LeverDown`, `LeverUp`, `PipeDeviceOn`, `PipeDeviceOff`, `PipeValveOn`, `PipeValveOff`, `ShutterOpen`, `ShutterClose`, `VentInwards`, `VentOutwards`, `WrenchOneShot`, `ScrewDriverOneShot`

**Power:** `ApcOpen`, `ApcClose`, `ApcOn`, `ApcOff`, `ApcCharged`, `ApcDischarged`, `ElectricalFailure`

**Storage:** `StorageLockerOpen`, `StorageLockerClose`, `ChuteBinOpen`, `ChuteBinClose`

### Announcements (`ss.sounds.alerts`)

`Danger`, `Warning`, `Alert`, `IntruderAlert`, `SystemFailure`, `Welcome`, `MalfunctionDetected`, `HaltWhoGoesThere`, `FireFireFire`, `StormIncoming`, `Depressurising`, `Pressurising`, `AirlockCycling`, `PowerLow`, `PressureHigh`, `PressureLow`, `TemperatureHigh`, `TemperatureLow`, `PollutantsDetected`, `HighCarbonDioxide`, `RocketLaunching`, `LiftOff`, `TraderIncoming`, `TraderLanded`, `Floor`, `One`, `Two`, `Three`, `Four`, `Five`, `Alarm1`–`Alarm12`, `Music1`, `Music2`, `Music3`

See `Examples/SoundDemo.lua` for a complete example.

---

## Tips & best practices

- Make element ids stable and unique.
- Batch changes and call `ui:commit()` once.
- Prefer `ui:get(id)` + `handle:set_props/set_style` for small updates.
- Avoid `ui:clear()` every frame unless you're intentionally rebuilding everything.
- Use multiple surfaces for multi-page UIs.
- Use `parent:element()` for containers with children (headers, panels, toolbars).
- Throttle live updates (e.g. 2–4 Hz) to avoid excessive UI rebuilds.

---

## Debugging output

`print(...)` writes to the **Lua Debugger motherboard** Logs tab. Insert the debugger board into a computer,
select your endpoint in the dropdown, and you can view the captured log output in-game.

---

## Troubleshooting

- UI not showing:
  - Ensure you called `ss.ui.activate("main")` (or your surface name).
  - Ensure you’re writing to the correct screen index.
  - Call `ui:size()` and verify you’re using sane coordinates.
- **Multiplayer — UI doesn’t render when you join a server** (host may still see it):
  - You most likely forgot **`ss.ui.activate(...)`** for the surface your script uses. Late-join replication can restore element data in the **model**, but **which surface is visible is chosen via `ss.ui.activate` and sent to clients**; without that call, joining players may never get a live Unity build of your UI.
- Button clicks not firing:
  - Make sure the element is on the active surface.
  - Ensure the element is visible and not covered.
- Keyboard doesn’t work:
  - Click the screen to enter **Interface Mode**.
  - Use `ss.exit_interface_mode()` (or press ALT) to exit.

---

## Next steps

- Browse `Examples/` for complete UIs and games:
  - `WidgetShowcase.lua` - Static + interactive demo of all chart/table/gauge widgets
  - `LiveDashboard.lua` - Animated live-updating station monitoring dashboard
  - `CCTVDashboard.lua` - CCTV camera dashboard with primary view + clickable thumbnails (requires CCTV mod)
  - `FindByName.lua` - Device lookup by Labeler name using `ic.find()` / `ic.find_all()`
  - `SampleUI/` - Dashboard monitors (PowerGrid, LifeSupport, etc.)
  - `Games/` - Snake, Tetris, Doom
  - `NetChat.lua`, `NetPeerMonitor.lua`, `NetAnnouncements.lua` - Network examples
  - `AccessControl.lua`, `AirlockControl.lua` - Interactive control panels
  - `ImageElement.lua` - Remote image display (PNG, JPG, animated GIF)
  - `MediaPlayer.lua` - HTTP video streaming with spatial audio
  - `SoundDemo.lua` - Built-in game sounds, announcements, and remote audio
- Read `README.md` for the full API reference.
