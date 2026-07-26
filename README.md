# Argon UI

Argon UI is a standalone Roblox UI library in a single Luau file. No dependencies, no host script: load it, create a window, add controls.

**Documentation: https://jirkaachs.github.io/argon-ui/**

```luau
local Argon = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/JirkaachS/argon-ui/main/argon-ui.luau"
))()

local Window = Argon:CreateWindow({
    Name = "My Hub",
    ConfigurationSaving = { Enabled = true, FolderName = "MyHub", FileName = "config" },
})

local Tab = Window:CreateTab("Main", "zap")
Tab:CreateSection("Farming")
Tab:CreateToggle({
    Flag = "AutoFarm",
    Name = "Auto farm",
    Callback = function(enabled) print("auto farm:", enabled) end,
})

Argon:LoadConfiguration()
```

Keep a copy of `argon-ui.luau` beside your script if you want an offline fallback for the hosted URL.

## Features

- Tabbed window with sections, per-tab search, and a `SECTIONS` navigator for long pages
- 18 controls, including progress bars, steppers, segmented pickers, text areas, and data lists
- Configuration persistence with verified writes, deferred flag hydration, and change listeners
- Five built-in themes plus custom palettes, applied live
- Draggable player and keybind overlays that can stay on screen while the window is hidden
- Modal dialogs, notifications, tooltips, descriptions, locked states, and element visibility
- Drag-resizable window with a `560 x 400` minimum and responsive sidebar collapse
- Vector icon atlas with no operating-system glyph fallback
- Rayfield-style API shape, so existing menus usually only need their loader swapped

## Controls

| Group | Controls |
| --- | --- |
| Input | `Toggle`, `Input`, `TextArea`, `Keybind` |
| Choice | `Dropdown`, `Segmented`, `ColorPicker` |
| Numeric | `Slider`, `Stepper` |
| Action | `Button` |
| Display | `ProgressBar`, `List`, `TelemetryCard`, `Label`, `Paragraph` |
| Layout | `Section`, `Divider`, `Space` |

Every `Create*` method has a prefix-free alias (`Tab:Toggle`, `Section:Dropdown`, and so on).

## Persistence

Any control given a `Flag` is saved to `FolderName/FileName` shortly after it changes, and each write is read back to confirm it landed.

```luau
Argon:LoadConfiguration()             -- restores values, reapplies callbacks, enables autosave
Argon:GetFlagValue("AutoFarm")
Argon:SetFlagValue("FlySpeed", 220)
Argon:OnFlagChanged(function(flag, value) print(flag, value) end)
Argon:GetConfigurationStats()
Argon:ResetConfiguration()
```

Restored values always run their callback once, even when the stored value equals the control default, and values whose control does not exist yet are retained rather than dropped.

## Overlays

The player list and active-keybind panels are draggable and can be pinned so they remain visible after the main window is hidden.

```luau
Window:SetOverlaysAlwaysVisible(true)
Window:ToggleOverlaysAlwaysVisible()
Window:TogglePlayerList()
Window:ToggleKeybindList()
```

`Window:CreateLibrarySettings(tab)` adds theme, overlay, pin, logo, and transition controls in one call.

## Tests

`tests/` runs the real library outside Roblox against a small Roblox API sandbox. Install [Lune](https://github.com/lune-org/lune), then:

```sh
lune run tests/run.luau
```

The suite covers control behavior, the configuration round-trip, deferred flag hydration, autosave timing, pinned overlays, themes, dialogs, and window controls. See `tests/README.md`.

## Browser preview

Open `argon-ui-preview.html`, or the hosted [preview](https://jirkaachs.github.io/argon-ui/preview.html), to explore the visual system without Roblox. Press `/` to focus search and `Insert` to hide or restore the window.

## Themes

Ten built-in palettes: `Argon`, `Amethyst`, `Midnight`, `Emerald`, `Rose`, `Slate`, `Ember`, `Nord`, `Mono`, `Ocean`. Register your own with `Argon:AddTheme(name, palette)` and apply it using `Argon:SetTheme(name)` or `Window:SetTheme(name)`.

## Icons

Icons come from the official [Lucide](https://lucide.dev) set, fetched once and cached on disk, with a bundled atlas as an offline fallback.

```luau
Window:CreateTab("Mining", "pickaxe")
local icon = Argon:GetIcon("shield-check")   -- { Image, ImageRectOffset, ImageRectSize }
```

![Argon UI logo](argon-ui-logo.svg)
