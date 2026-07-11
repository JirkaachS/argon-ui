# Argon UI

`argon-ui.luau` is the local UI dependency for the menu. Keep it in the same executor workspace as the script you run.

- `menu.luau` remains the original menu entry.
- `menu-argon.luau` is the separate Argon UI migration build.

The migration build downloads the latest library from the public `JirkaachS/argon-ui` GitHub repository. A neighboring `argon-ui.luau` remains available as an offline fallback.

## Hosted Usage

```luau
local Argon = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/JirkaachS/argon-ui/main/argon-ui.luau"
))()
```

`menu-argon.luau` already uses this hosted endpoint automatically.

## Design

- Rayfield-compatible window, tab, control, notification, flag, and configuration APIs.
- Orion-style section grouping for large feature sets.
- WindUI-inspired glass surfaces, spacious controls, search, gradients, and motion.
- MacLib-inspired compact navigation, pill states, restrained window chrome, and responsive collapse.
- Code-native Lucide-style navigation icons with no operating-system glyph fallback.
- Drag-resizable windows with a viewport-aware `560 x 400` minimum size.
- A `SECTIONS` navigator for direct jumps inside long tabs.
- Clipped and truncated control content so long keys and webhook URLs stay contained.

![Argon UI logo](argon-ui-logo.svg)

## Supported API

- `CreateWindow`, `CreateTab`, and `CreateSection`
- `CreateButton`, `CreateToggle`, `CreateSlider`, and `CreateDropdown`
- `CreateInput`, `CreateKeybind`, and `CreateLabel`
- Element `Set` methods and dropdown `Refresh`
- `Notify`, `SaveConfiguration`, `LoadConfiguration`, and `Destroy`
- `Window:SetLogo`, `Window:SetTheme`, and `Window:SetTitle`
- `Rayfield.Flags` compatibility for live profile resets
- Runtime themes, modal dialogs, descriptions, tooltips, locked states, and element visibility
- `CreateColorPicker`, `CreateParagraph`, `CreateDivider`, and `CreateSpace`
- WindUI-style aliases such as `Tab:Section()`, `Section:Toggle()`, and `Section:Colorpicker()`

The interface toggles with `Insert`. Press `/` while it is open to focus the active-tab search.

## Browser Preview

Open `argon-ui-preview.html` in any modern browser to preview the visual system without Roblox. The standalone preview includes responsive desktop/mobile layouts, tab search, toggles, sliders, dropdowns, inputs, keybind capture, buttons, and animated notifications.

- Press `/` to focus search.
- Press `Insert` to hide or restore the preview.
- Resize the browser to inspect the compact navigation layout.

## WindUI Extensions

```luau
local Window = Argon:CreateWindow({
    Name = "Argon Utility",
    Theme = "Midnight",
    Logo = "rbxassetid://YOUR_LOGO_ASSET_ID",
})

local Tab = Window:CreateTab("Settings", "settings")
local Section = Tab:Section({ Title = "Appearance" })

Section:Dropdown({
    Name = "Theme",
    Options = Argon:GetThemes(),
    CurrentOption = { "Midnight" },
    Callback = function(value)
        Window:SetTheme(value[1])
    end,
})

local Accent = Section:Colorpicker({
    Name = "Accent color",
    Color = Color3.fromRGB(153, 112, 255),
    Callback = function(color)
        print(color)
    end,
})

Accent:SetTooltip("Choose a custom accent")
Accent:Lock("Premium")
Accent:Unlock()

Window:Dialog({
    Title = "Save changes?",
    Content = "Your interface settings will be persisted.",
    Buttons = {
        { Title = "Cancel" },
        { Title = "Save", Variant = "Primary", Callback = function() end },
    },
})

-- Replace the logo at runtime with an asset ID or Roblox image URI.
Window:SetLogo("rbxassetid://YOUR_OTHER_LOGO_ASSET_ID")
```

Built-in themes are `Argon`, `Amethyst`, `Midnight`, `Emerald`, and `Rose`. Add custom palettes with `Argon:AddTheme(name, palette)` and apply them using `Argon:SetTheme(name)` or `Window:SetTheme(name)`.
