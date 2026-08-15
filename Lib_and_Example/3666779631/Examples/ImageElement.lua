-- ImageElement.lua
-- Example: Displaying remote images (PNG, JPG, animated GIF) on a ScriptedScreens surface.
--
-- Usage:
--   Place this script in a ScriptedScreens Lua chip inside a console.
--   The server must have AllowRemoteImages = True in the ScriptedScreens config.
--
-- Supports:
--   - PNG and JPG (with transparency)
--   - Animated GIFs (plays automatically)
--   - Images are cached per URL (LRU cache, configurable size)
--   - Multiplayer: server sets the URL, each client downloads independently
--
-- Image props:
--   url = HTTP/HTTPS URL to a PNG, JPG, or GIF image

local ui = ss.ui.surface("main")
ss.ui.activate("main")

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
    props = { text = "Image Element Demo", font_size = 18 },
    style = { color = "#FFFFFF" },
})

-- Static PNG image with transparency
ui:element({
    id = "logo",
    type = "image",
    rect = { x = 0.02, y = 0.10, w = 0.46, h = 0.55 },
    props = {
        url = "https://upload.wikimedia.org/wikipedia/commons/4/47/PNG_transparency_demonstration_1.png",
    },
})

ui:element({
    id = "logo_label",
    type = "label",
    rect = { x = 0.02, y = 0.66, w = 0.46, h = 0.04 },
    props = { text = "PNG with transparency", font_size = 12 },
    style = { color = "#AAAAAA" },
})

-- Animated GIF
ui:element({
    id = "animation",
    type = "image",
    rect = { x = 0.52, y = 0.10, w = 0.46, h = 0.55 },
    props = {
        url = "https://upload.wikimedia.org/wikipedia/commons/2/2c/Rotating_earth_%28large%29.gif",
    },
})

ui:element({
    id = "gif_label",
    type = "label",
    rect = { x = 0.52, y = 0.66, w = 0.46, h = 0.04 },
    props = { text = "Animated GIF", font_size = 12 },
    style = { color = "#AAAAAA" },
})

-- Dynamic swap button: changes the left image on click
ui:element({
    id = "swap_btn",
    type = "button",
    rect = { x = 0.02, y = 0.72, w = 0.46, h = 0.06 },
    props = { text = "Swap Image" },
    style = { bg = "#3B82F6", text = "#FFFFFF" },
}):on("click", function()
    -- Update the image URL in-place (no rebuild needed)
    ui:get("logo"):set_props({
        url = "https://upload.wikimedia.org/wikipedia/commons/thumb/4/4f/SVG_Logo.svg/512px-SVG_Logo.svg.png",
    })
    ui:get("logo_label"):set_props({ text = "Swapped PNG" })
end)

ui:commit()
