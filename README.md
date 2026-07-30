<div align="center">

<img src="argon-ui-logo.svg" width="110" alt="Argon UI logo">

# Argon UI

### A modern single-file UI library for Roblox Luau scripts

No dependencies, no host script, no build step. One `.luau` file: load it, create a window, add controls. The API is shaped like Rayfield's, so existing menus usually only need their loader swapped.

[![Docs](https://img.shields.io/badge/docs-argon--ui-5865f2?style=for-the-badge)](https://jirkaachs.github.io/argon-ui/)
[![Live preview](https://img.shields.io/badge/live-preview-23a55a?style=for-the-badge)](https://jirkaachs.github.io/argon-ui/preview.html)
[![Language: Luau](https://img.shields.io/badge/luau-single%20file-00a2ff?style=for-the-badge)](argon-ui.luau)
[![Stars](https://img.shields.io/github/stars/JirkaachS/argon-ui?style=for-the-badge)](https://github.com/JirkaachS/argon-ui/stargazers)

**[Documentation](https://jirkaachs.github.io/argon-ui/)** · **[Try it in your browser](https://jirkaachs.github.io/argon-ui/preview.html)** · [Controls](#controls) · [Rows](#rows) · [Themes](#themes) · [FAQ](#faq)

Every control in the docs is shown as a [mockup](https://jirkaachs.github.io/argon-ui/#mockups) next to the call that produces it.

</div>

---

## Quick start

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

## Why Argon UI

Most Roblox UI libraries give you a window and a list of toggles and stop there. Argon UI is built for hubs that outgrew that: hundreds of controls, long tabs, sessions that need to survive a rejoin, and games that fight your menu.

- **Responsive rows.** `CreateRow` splits a section into up to four columns so related controls sit side by side instead of screens apart, and collapses back to one stack when the window narrows.
- **A loader that waits for you.** Report progress while you build and the window stays covered until it is actually finished, instead of revealing a half-assembled interface.
- **Its own cursor.** When a game hides the engine pointer and draws its own in `PlayerGui`, that pointer sits behind `CoreGui` and you click blind. Argon draws a cursor above everything it owns.
- **Persistence that actually round-trips.** Writes are read back to confirm they landed, flags for controls that do not exist yet are retained rather than dropped, and restored values always fire their callback once.
- **Notifications outside the window.** A background feature reporting a result is useless if the card only appears while the menu happens to be open, so notifications are independent of window visibility.
- **Text that fits.** Labels, paragraphs and cards size to their content, so nothing clips and nothing leaves dead space.
- **Rayfield-compatible API shape**, ten live-switchable themes, official [Lucide](https://lucide.dev) icons, and a browser preview that is a working reimplementation rather than a screenshot.

## Features

- Tabbed window with sections, per-tab search, and a scrollable section jump rail for long pages
- 18 controls, including progress bars, steppers, segmented pickers, text areas and data lists
- Configuration persistence with verified writes, deferred flag hydration and change listeners
- Ten built-in themes plus custom palettes, applied live, with a swatch picker in the topbar
- Draggable player and keybind overlays that can stay on screen while the window is hidden
- Modal dialogs, tooltips, descriptions, locked states and element visibility
- Drag-resizable window with a `560 x 400` minimum and responsive sidebar collapse
- One modern typeface throughout (BuilderSans), on buttons and text boxes as well as labels
- Vector icon atlas with no operating-system glyph fallback

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

## Rows

A tab with ninety controls is a single column you scroll blind, and the related ones end up screens apart. `CreateRow` splits the section body into equal columns and hands controls out round-robin, so the pair you build together sits side by side.

```luau
local row = Tab:CreateRow({ Columns = 2 })
row:CreateToggle({ Flag = "Chams", Name = "Chams", CurrentValue = false })
row:CreateSlider({ Flag = "ChamsOpacity", Name = "Opacity %", Range = { 5, 100 }, Increment = 1, CurrentValue = 60 })

-- or, when the pairing matters more than the balance
row:Use(2):CreateToggle({ Name = "Pin me right", CurrentValue = false })
```

`Columns` accepts 1 to 4 and may be passed bare (`Tab:CreateRow(2)`). `Spacing` sets the gap, and `MinColumnWidth` (default 200) is the width below which columns collapse back into one stack, so a resized window and a phone get a readable layout from the same calls. Rows carry the same shorthands as sections, join the owning section for search, and hide themselves when everything in them is filtered out.

Controls on the same visual line grow to the tallest of that line, so a toggle beside a titled segmented strip reads as one line instead of leaving a ragged gap.

Best suited to compact controls: toggles, sliders, steppers, keybinds, colour pickers, buttons, inputs, dropdowns and short segmented pickers. Lists and text areas want the full width.

## Tooltips, locks and confirmations

`Tooltip` carries the same explanatory text as `Description` without spending row height on it, which matters once controls share a row. A control with a tooltip is marked with a small `?` after its title, so the hint is discoverable rather than hidden. The panel wraps, sizes to its content, and anchors beside the row it explains, to the right by preference, flipped left when there is no room, above or below when neither side fits, so it never covers what you are pointing at. It opens after a short delay so sweeping down a column does not strobe. Keep `Description` for anything a user must read before acting, since a tooltip needs a mouse.

```luau
Tab:CreateToggle({ Name = "Kill Aura", Tooltip = "Hits every nearby enemy. Cannot run with Aimbot.", CurrentValue = false })
```

`Lock` states a precondition on the control itself instead of failing after the click. The row is dimmed and gets a padlock badge carrying the reason; on a narrow column the badge collapses to `LOCKED` and then to the padlock alone, so it never buries the title.

```luau
element:Lock("enter a container ID")   -- greyed, with the reason on the row
element:SetLocked(conquestIsOn, "Conquest Auto-Hop is on")
element:Unlock()
```

`Window:Confirm` is a one-shot gate for destructive actions. Cancel is the default, the confirm button is tinted as a danger, and the dialog destroys itself once a choice is made.

```luau
Window:Confirm({
    Title = "Empty container?",
    Content = "Every item type is pulled out at full quantity. There is no undo.",
    ConfirmText = "Empty it",
    OnConfirm = function() emptyContainer() end,
})
```

## List row actions

A list row can carry several buttons instead of one, which beats a selectable list plus a stack of buttons that act on "whatever is selected".

```luau
Tab:CreateList({ Name = "Profiles", Items = {
    { Title = "Mining", Description = "saved snapshot", Actions = {
        { Label = "Load",   Callback = function(row) load(row.Title) end },
        { Label = "Rename", Style = "warning", Callback = function(row) rename(row.Title) end },
        { Label = "Delete", Style = "danger",  Callback = function(row) remove(row.Title) end },
    } },
} })
```

`Style` accepts `danger` and `warning`, or pass an explicit `Color`. A single `Action = "Load"` with a row-level `Callback` still works.

## Loading a big interface

Building several hundred controls is thousands of instances in one uninterrupted run, and Roblox cannot render a frame while that happens. Report progress and the loader waits for you instead of uncovering a window that is still assembling itself.

```luau
local Window = Argon:CreateWindow({ Name = "My Hub" })

for index, spec in ipairs(tabsToBuild) do
    Window:SetLoadingProgress(index / #tabsToBuild, "Building " .. spec.Name)
    buildTab(spec)
    task.wait()   -- one frame, so the client stays responsive
end

Argon:LoadConfiguration()
Window:FinishLoading()
```

Progress is monotonic, so a lower value than the last is ignored. A window that never reports keeps the original timed behaviour, and one that reports but forgets `FinishLoading` is opened by a watchdog after 30 seconds.

## Cursor

Some games draw their own pointer: they set `UserInputService.MouseIconEnabled` to `false` and render an image in `PlayerGui`, which sits below `CoreGui`. That pointer disappears behind the menu and you click blind. When the engine cursor is off, Argon draws its own above everything it owns.

```luau
Argon:CreateWindow({ Name = "My Hub", Cursor = "auto" })  -- default
Window:SetCursorVisible(false)   -- never
Window:SetCursorVisible(true)    -- always
Window:SetCursorVisible()        -- automatic again
```

## Notifications

`Argon:Notify` shows a card in the top-right corner. It is deliberately not tied to window visibility: a notification that only appears while the menu happens to be open is useless for reporting what a background feature just did.

```luau
Argon:Notify({ Title = "Saved", Content = "Configuration written.", Duration = 4 })
```

The accent and the glyph come from the title: titles containing *error* or *failed* read red, *warn* or *wait* amber, *success*, *complete* or *saved* green. The card grows to fit its body rather than clipping at a fixed height, and the stack is capped at five so a burst cannot run off the screen.

## Text and inputs

`Label`, `Paragraph` and `TelemetryCard` size themselves to their content. A long body wraps and the row grows; a short one does not leave an empty slot behind.

`Input` shows an elided value while it is not focused, dropping the scheme and keeping the informative head and tail, and restores the real text for editing on focus. `CurrentValue` is always the full string, so a saved webhook URL round-trips exactly even though the field never displays it in full.

```luau
local field = Tab:CreateInput({ Flag = "Webhook", Name = "Webhook URL", PlaceholderText = "https://…" })
field:Set("https://discord.com/api/webhooks/1523331338155982949/RvztQ8kLmNoPqRs")
print(field.CurrentValue)   -- the whole URL, not the elided display
```

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

`Window:CreateLibrarySettings(tab)` adds theme, overlay, pin, logo and transition controls in one call.

## Themes

Ten built-in palettes: `Argon`, `Amethyst`, `Midnight`, `Emerald`, `Rose`, `Slate`, `Ember`, `Nord`, `Mono`, `Ocean`. Register your own with `Argon:AddTheme(name, palette)` and apply it using `Argon:SetTheme(name)` or `Window:SetTheme(name)`.

Every window gets a theme picker in the topbar. The button wears the active palette rather than an icon, three overlapping `AccentLight`/`Accent`/`AccentDark` dots, so it reads as a swatch and as a readout of what is applied. Clicking it opens a grid of every registered theme, each option previewing its own palette, with the active one outlined in its accent.

```luau
local Window = Argon:CreateWindow({ Name = "My Hub", ThemePicker = false })  -- opt out

Window:SetThemePickerVisible(true)   -- bring it back
Window:ToggleThemePicker()           -- open or close the panel; returns the new state
```

When `CreateLibrarySettings` is present the picker writes through that tab's `ArgonUITheme` flag, so the dropdown stays in step and the choice survives the next `LoadConfiguration`.

Every control the library builds re-themes itself, including ones that were hovered or mid-animation when the theme changed. If your script builds its own frames outside the library, read the live palette instead of baking in colours:

```luau
local rowColour = Argon:GetColor("Surface")
local hoverColour = Argon:GetColor("Hover")

local unbind = Argon:OnThemeChanged(function(palette, themeName)
    row.BackgroundColor3 = palette.Surface
end)
```

`Argon:GetColor(key, fallback)` resolves a single palette key, `Argon:GetPalette()` returns a detached snapshot, and `Argon.Palette` is the live table. Keys: `Background`, `Window`, `Sidebar`, `Surface`, `Hover`, `Active`, `Input`, `Border`, `BorderSoft`, `Text`, `Muted`, `Dim`, `Accent`, `AccentLight`, `AccentDark`, `Success`, `Warning`, `Danger`.

## Icons

Icons come from the official [Lucide](https://lucide.dev) set, fetched once and cached on disk, with a bundled atlas as an offline fallback.

```luau
Window:CreateTab("Mining", "pickaxe")
local icon = Argon:GetIcon("shield-check")   -- { Image, ImageRectOffset, ImageRectSize }
```

## FAQ

### Can I port a Rayfield script to Argon UI?

Usually by swapping the loader. The API shape follows Rayfield's, including `CreateWindow`, `CreateTab`, `CreateSection` and the `Create*` control methods with `Flag`, `CurrentValue` and `Callback`. Anything Argon adds, rows, tooltips, locks, steppers, progress bars, is optional and additive.

### What does it need to run?

An environment that provides `loadstring` and `game:HttpGet`, plus `CoreGui` access for the window. Configuration saving needs file functions (`writefile`, `readfile`, `isfile`); without them the library runs fine and simply does not persist.

### Does it work on a phone or a small window?

Yes. Rows collapse to a single stack below `MinColumnWidth`, the sidebar collapses on narrow windows, and the window has a `560 x 400` minimum. Note that tooltips need a pointer, so put anything essential in `Description`.

### Is it one file on purpose?

Yes. No requires, no module tree, no build step, so it drops into a single-file script and can be vendored beside it for an offline fallback.

### How do I try it without opening Roblox?

Open the [live preview](https://jirkaachs.github.io/argon-ui/preview.html). It is a working reimplementation rather than a screenshot: sliders drag, the colour picker has a real HSV square, dropdowns filter, rows collapse as the window narrows, tooltips and locks behave as in game, and all ten palettes apply live. Press `/` to focus search, `Insert` to hide or restore the window, `Esc` to close whatever is open.

### How do I know a change did not break anything?

`tests/` runs the real library outside Roblox against a small Roblox API sandbox. Install [Lune](https://github.com/lune-org/lune), then `lune run tests/run.luau`. The suite covers control behaviour, the configuration round-trip, deferred flag hydration, autosave timing, pinned overlays, themes, dialogs and window controls. See [`tests/README.md`](tests/README.md).

## Contributing

Issues and pull requests are welcome. Run the test suite before opening one, and keep the library a single file.

---

<sub>Also useful if you searched for: Roblox UI library, Luau GUI library, Rayfield alternative, Roblox script hub UI, Roblox menu library single file, Luau interface library with config saving, Roblox UI library with themes, Lucide icons for Roblox, responsive Roblox GUI.</sub>
