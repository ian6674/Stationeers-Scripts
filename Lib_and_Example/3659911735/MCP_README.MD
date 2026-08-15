# StationeersLua MCP Server

StationeersLua exposes an optional **MCP (Model Context Protocol)** server for AI editors such as Cursor, Windsurf, Claude Code, and VS Code Copilot.

This server gives AI tools access to:

- live chip/editor state
- chip source and error information
- StationeersLua documentation resources
- bundled `Examples/` sample scripts (as MCP resources next to the mod DLL)
- network-scoped chip discovery
- optional documentation and tools from companion mods via **`StationeersLua.LuaMcpRegistry`** (public API on the same **`StationeersLua.dll`**)

## Important split: REST vs MCP

StationeersLua exposes **two different HTTP surfaces**:

- **REST (`/api/*`)** for the VS Code extension only
- **MCP (JSON-RPC)** for AI editors only

AI editors should use the MCP endpoint.
The VS Code extension should use the REST endpoint.

## Default endpoint

```text
http://127.0.0.1:3030
```

The MCP JSON-RPC surface is disabled by default. Enable it in the in-game mod config under `[MCP Server]`:

- `Enabled = true` — enables the MCP JSON-RPC surface for AI editors
- `EnableExtensionApi = true` — enables the REST surface for the VS Code extension

Both share the same port. Either or both can be enabled independently.

## Multiplayer note

In multiplayer, the MCP server runs on the **host**.
Connect your AI editor to your **own local game client's** configured URL and port (`127.0.0.1` by default). In multiplayer the mod proxies network traffic in-game — you never connect directly to the host machine. Dedicated servers do not expose the HTTP/MCP listener.

## What the server exposes

### Tools

Typical tools include:

- `get_editor_state`
- `list_chips`
- `get_chip_code`
- `set_chip_code`
- `set_editor_code`
- `get_chip_errors`
- `list_library_modules`
- `list_search_docs_scopes` (enumerates valid `search_docs` scopes, including mod-registered needles)
- `search_docs` (scopes: `all`, `lua`, `ss`, plus mod-registered names; unknown scope returns an error)
- `search_stationpedia`
- `get_network_devices`
- `get_game_state`

### Resources

Typical resources include:

- `stationeers://lua/readme`
- `stationeers://lua/guide`
- `stationeers://lua/migration`
- `stationeers://lua/api/logic`
- `stationeers://lua/api/device`
- `stationeers://lua/api/memory`
- `stationeers://lua/api/persist`
- `stationeers://lua/api/network`
- `stationeers://lua/api/http`
- `stationeers://lua/api/utility`
- `stationeers://lua/api/events`
- `stationeers://lua/api/library`

### Bundled example scripts

At startup the server scans the mod’s `Examples/` folder (the same directory as the plugin DLL) and registers one MCP resource per `.lua`, `.ic10`, and `.md` file:

- `stationeers://lua/examples/index` — markdown table of all discovered files and their URIs
- `stationeers://lua/examples/<relative/path>` — e.g. `stationeers://lua/examples/NetworkAnalyser.lua`

Paths use forward slashes. Very large files may be truncated when read through MCP (payload cap); open the file under `Examples/` locally if needed.

The **ScriptedScreens** mod registers its shipped samples the same way under `stationeers://ss/examples/` (index at `stationeers://ss/examples/index`) when both mods are loaded.

## Recommended AI-editor workflow

1. Read this README/instructions first.
2. Use documentation resources before making code changes.
3. Use `get_editor_state` and `list_chips` to understand the current in-game scope.
4. Use `get_chip_code` and `get_chip_errors` before changing a chip.
5. Prefer `set_editor_code` when you want to update the in-game editor draft without exporting.
6. Use `set_chip_code` only when you intentionally want to export/compile to the chip.

## VS Code extension

The **Stationeers VS Code extension** uses the same REST API (`EnableExtensionApi`) for chip discovery, temp-file editing, save/push, and debugging. **MCP does not push into VS Code**; use the extension’s Chip Explorer and open/sync flows for IDE editing, and MCP or REST for AI-driven reads/writes to the game.

## Behavioral notes

- `get_editor_state` includes **`wireless_remote_access_only`** when scope comes from the **Wireless Development Board** alone (no IC motherboard editor open). Holder/chip selection fields are unset in that mode — the board is a network bridge, not a housing. Use `network_id` / `network_names` for the linked data network.
- Chip and library visibility is scoped to what the current in-game editor/network context can access.
- `set_chip_code` mirrors an actual export/write to the chip.
- `set_editor_code` updates the editor view without exporting.
- Documentation resources are the authoritative source for StationeersLua API details inside MCP clients.

## Troubleshooting

### The AI editor connects but shows no useful context

- Make sure you have a valid development context: either the in-game **IC editor** open, or a **Wireless Development Board** connected with **`AllowNetworkChipAccess`** enabled in config (see `GUIDE.MD` §29).
- Check whether you are connected to the correct host in multiplayer.
- Read `stationeers://lua/guide` and `stationeers://lua/readme` through the MCP client.

### The server is reachable but no chips are listed

- The current editor may not be open in-game.
- The selected network may not contain accessible Lua chips.
- The housing or host may be off or unavailable.

## LSP server (separate from MCP)

StationeersLua also includes a **Language Server Protocol (LSP)** server on a separate TCP port (default 3031). This is consumed by the VS Code extension for Stationeers-specific code intelligence (enum completions, diagnostics, `require()` suggestions, hover, signature help). The LSP server is independent of the MCP/REST HTTP server — they serve different purposes and run on different ports. Enable it with `EnableLspServer = true` in `[MCP Server]` config.

## Related docs

- `GUIDE.MD` — full StationeersLua scripting guide
- `MAPPING.MD` — IC10 to Lua migration reference
