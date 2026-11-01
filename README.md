<div align="center">

<img src="argon-ui-logo.svg" width="110" alt="Argon UI logo">

# Argon UI

### A fast, modern single-file UI library for Roblox Luau scripts

No dependencies and no host script. One `.luau` file: load it, create a window, add controls. The API is shaped like Rayfield's, so existing menus usually only need their loader swapped.

[![Docs](https://img.shields.io/badge/docs-argon--ui-5865f2?style=for-the-badge)](https://jirkaachs.github.io/argon-ui/)
[![Live preview](https://img.shields.io/badge/live-preview-23a55a?style=for-the-badge)](https://jirkaachs.github.io/argon-ui/preview.html)
[![Language: Luau](https://img.shields.io/badge/luau-single%20file-00a2ff?style=for-the-badge)](argon-ui.luau)
[![Stars](https://img.shields.io/github/stars/JirkaachS/argon-ui?style=for-the-badge)](https://github.com/JirkaachS/argon-ui/stargazers)

**[Documentation](https://jirkaachs.github.io/argon-ui/)** · **[Try it in your browser](https://jirkaachs.github.io/argon-ui/preview.html)** · [Controls](#controls) · [Command palette](#command-palette) · [Themes](#themes) · [Upgrading from 1.x](#upgrading-from-1x) · [FAQ](#faq)

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

That is the whole setup. The window opens by itself as soon as your script is done building. Keep a copy of `argon-ui.luau` beside your script if you want an offline fallback for the hosted URL.

## Why Argon UI

Most Roblox UI libraries give you a window and a list of toggles and stop there. Argon UI is built for hubs that outgrew that: hundreds of controls, long tabs, sessions that need to survive a rejoin, and games that fight your menu.

- **It opens fast, however big the hub is.** `Create*` calls only record what you asked for. The visible tab is built first, in small slices that never hold up a frame, and the other tabs are built quietly after the window is open. Nothing is downloaded, decoded or written to disk before the window can draw.
- **A loader that tells the truth.** No fixed timers. A quick script opens with no loader at all; a big one shows what is actually happening ("Building Combat · 155 of 212", "Restoring settings · 72 of 96") and opens the moment the work is done.
- **Find anything.** The command palette (Ctrl+K) finds any control in any tab, even tabs you never opened, and can change it in place.
- **Undo, reset, profiles.** Changed rows are marked, every tab can be reset, Ctrl+Z undoes, and settings can be saved as named profiles and shared as a code.
- **Persistence that round-trips.** Writes are read back to confirm they landed, values for controls that do not exist yet are kept, and restored values fire their callback once.
- **Notifications outside the window**, with types, buttons, progress and an inbox, so a background feature can report while the menu is hidden.
- **Its own cursor**, for games that hide the engine pointer behind their own.
- **Keyboard, gamepad and touch** work everywhere: focus ring, arrow keys, shoulder buttons, long-press menus, phone layouts.
- **Rayfield-compatible API**, 12 live-switchable themes, 1,573 [Lucide](https://lucide.dev) icons built in, and a browser preview that is a working reimplementation rather than a screenshot.

## Features

- Tabbed window with sections, rows of up to four columns, tab groups, badges, and a jump rail and "On this page" list for long pages
- 22 control builders: switches, checkboxes, sliders, steppers, segmented pickers, dropdowns, colour pickers, keybinds, inputs, text areas, buttons, button groups, lists, progress bars, telemetry and stat cards, callouts, images, labels, paragraphs, dividers and spacers
- Command palette, row context menus, change tracking with undo, pins and a quick dock
- Named configuration profiles with autoload, export and import
- Typed notifications with actions, progress, update in place and an inbox
- Dialogs, confirmations and prompts; tooltips, descriptions, locks and conditional visibility
- 12 themes plus your own, accent override, three materials, interface scale and density
- Player list, keybind list and watermark overlays that can stay on screen while the window is hidden
- Key system (Rayfield's `KeySystem` settings)
- Responsive: wide, standard, icon rail and phone layouts, with a `560 x 400` minimum window

## Controls

| Group | Builders |
| --- | --- |
| Input | `Toggle`, `Checkbox`, `Input`, `TextArea`, `Keybind` |
| Choice | `Dropdown`, `Segmented`, `ColorPicker` |
| Numeric | `Slider`, `Stepper` |
| Action | `Button`, `ButtonGroup` |
| Display | `Label`, `Paragraph`, `Callout`, `Image`, `ProgressBar`, `List`, `TelemetryCard`, `Stat` |
| Layout | `Section`, `Row`, `Divider`, `Space` |

Every `Create*` method has a prefix-free alias (`Tab:Toggle`, `Section:Dropdown`, and so on), and every control config also accepts:

| Key | What it does |
| --- | --- |
| `Description` | A line of text under the title. |
| `Tooltip` | The same text without spending row height; an info mark after the title shows it on hover or focus. |
| `Keywords` | Extra words the command palette matches. |
| `Pinned` | On toggles and buttons: pins it to the sidebar and the quick dock. |
| `VisibleWhen` / `EnabledWhen` | Shows or enables the control only when other flags match, e.g. `{ Flag = "Mode", Equals = "Advanced" }`. |
| `Keybind` | On toggles and buttons: a key that flips or presses it, e.g. `Keybind = "F"`. |

Buttons take `Variant = "Primary" | "Ghost" | "Danger" | "DangerSoft"`, `HoldToConfirm = true` (hold for 0.8 s, for destructive actions) and `Async = true` (a spinner while the callback runs, a check when it returns `true`). Sliders take `Ticks` and a `Format` function for the value.

## Rows

A tab with ninety controls is a single column you scroll blind, and the related ones end up screens apart. `CreateRow` splits the section body into columns and hands controls out round-robin, so the pair you build together sits side by side.

```luau
local row = Tab:CreateRow({ Columns = 2 })
row:CreateToggle({ Flag = "Chams", Name = "Chams", CurrentValue = false })
row:CreateSlider({ Flag = "ChamsOpacity", Name = "Opacity %", Range = { 5, 100 }, Increment = 1, CurrentValue = 60 })

-- or, when the pairing matters more than the balance
row:Use(2):CreateToggle({ Name = "Pin me right", CurrentValue = false })
```

`Columns` accepts 1 to 4 and may be passed bare (`Tab:CreateRow(2)`). `Spacing` sets the gap, and `MinColumnWidth` (default 200) is the width below which columns wrap back into one stack, so a resized window and a phone get a readable layout from the same calls. Rows carry the same shorthands as sections and join the owning section for search.

Best suited to compact controls: toggles, sliders, steppers, keybinds, colour pickers, buttons, inputs, dropdowns and short segmented pickers. Lists and text areas want the full width.

## Command palette

Press **Ctrl+K**, press `/` with the pointer over the window, click the search field in the sidebar, or press **Y** on a gamepad. Type a few letters of any control, in any tab, including tabs that were never opened.

- **Enter** goes to the control and highlights it. **Ctrl+Enter** runs it in place (flips a switch, presses a button). **Left** and **Right** adjust sliders, steppers and pickers without leaving the palette.
- Recent picks come first. `Keywords = { ... }` on a control adds words it should match.
- Add your own commands:

```luau
local command = Window:RegisterCommand({
    Name = "Rejoin server",
    Icon = "rotate-ccw",
    Keywords = { "reconnect", "server hop" },
    Callback = function() rejoin() end,
})
command.Remove()            -- take it out again

Window:OpenPalette("speed") -- open it from code, pre-filled
```

## Changes, undo and pins

Every control knows its default. A changed row gets a dot, the page header says "3 changed · Reset tab", and a reset or a profile load can be undone with the Undo pill or Ctrl+Z.

```luau
toggle:IsChanged()      -- true when the value differs from the default
toggle:Reset()          -- back to the default
Tab:GetChangedCount()
Tab:Reset()
Window:ResetAll()
```

Right-click a row (long-press on touch, Shift+F10 or gamepad X) for its menu: reset to default, copy and paste the value, copy the flag name, pin, and show in the palette. Add your own items with `element:AddMenuItem({ Text = "Explain", Callback = function() ... end })`.

Pinned switches and buttons get a Pinned group at the top of the sidebar and a quick dock that stays on screen while the window is hidden, so the three toggles you use mid-fight are one tap away.

## Tooltips, locks and confirmations

`Tooltip` carries the same explanatory text as `Description` without spending row height on it, which matters once controls share a row. A control with a tooltip is marked with a small info glyph after its title. The panel wraps, sizes to its content, and opens beside the row it explains, flipping when there is no room. It opens after a short delay so sweeping down a column does not strobe, and immediately when you move from one tooltip to the next. Keep `Description` for anything a user must read before acting.

```luau
Tab:CreateToggle({ Name = "Kill Aura", Tooltip = "Hits every nearby enemy. Cannot run with Aimbot.", CurrentValue = false })
```

`Lock` states a precondition on the control itself instead of failing after the click. The row is dimmed and shows a padlock chip with the reason; a click on the row shows the reason instead of changing the value, and the control's keybind is blocked too. A script's own `Set` still works.

```luau
element:Lock("enter a container ID")   -- greyed, with the reason on the row
element:SetLocked(conquestIsOn, "Conquest Auto-Hop is on")
element:Unlock()
```

`Window:Confirm` is a one-shot gate for destructive actions. Cancel has the focus, the confirm button is tinted as a danger, and the dialog destroys itself once a choice is made. Closing it any other way (the x, Backspace, gamepad B, a click outside) calls `OnCancel`.

```luau
Window:Confirm({
    Title = "Empty container?",
    Content = "Every item type is pulled out at full quantity. There is no undo.",
    ConfirmText = "Empty it",
    OnConfirm = function() emptyContainer() end,
})

Window:Prompt({
    Title = "Rename profile",
    Placeholder = "Profile name",
    Validate = function(text) return #text >= 2, "Use at least 2 letters" end,
    OnSubmit = function(text) print("new name:", text) end,
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

`Style` accepts `danger` and `warning`, or pass an explicit `Color`. A single `Action = "Load"` with a row-level `Callback` still works. Long lists only build the rows that are on screen.

## Loading a big interface

You do not have to do anything. While your script builds, the window stays hidden; it opens when your script finishes, or when it has built a tab and gone quiet for a quarter of a second. Nothing is shown for the first 150 ms, so a quick script opens with no loader card at all. A big one gets a small card that says what is being built and restored.

To drive the loader yourself, report progress and finish:

```luau
local Window = Argon:CreateWindow({ Name = "My Hub", Loading = "manual" })

for index, spec in ipairs(tabsToBuild) do
    Window:SetLoadingProgress(index / #tabsToBuild, "Building " .. spec.Name)
    buildTab(spec)
end

Argon:LoadConfiguration()
Window:FinishLoading()
```

Progress never goes backwards. `Window:SetLoadingStatus(text)` changes only the text, `Window:OnLoaded(fn)` runs once the window is open, and `Window:Build(fn)` runs your builder and shows any error on the loader with **Open anyway** and **Copy error** buttons. If a manual build stops reporting for 8 seconds, the card offers **Open now**; 30 seconds after the last progress the window opens by itself.

`LoadingScreen = "never"` skips the card entirely, `"always"` shows it even for a quick build, and `{ Title = ..., Subtitle = ..., Tips = { ... } }` brands it. `LoadingTitle` and `LoadingSubtitle` (Rayfield's names) still work.

## Notifications

`Argon:Notify` shows a card in the top-right corner. It is deliberately not tied to window visibility, and it works before `CreateWindow`.

```luau
Argon:Notify({ Title = "Saved", Content = "Configuration written.", Type = "success" })

local job = Argon:Notify({
    Id = "download",
    Title = "Downloading map",
    Type = "loading",
    Actions = { { Text = "Cancel", Callback = function() cancelDownload() end } },
})
job:SetProgress(0.4)
job:Update({ Title = "Map ready", Type = "success" })
```

`Type` is `info`, `success`, `warning`, `error` or `loading`; without it the type is guessed from whole words in the title ("Save failed" reads as an error, "No errors found" does not). The duration follows the length of the text unless you pass `Duration`, and the timer pauses while the pointer is over the card. Identical cards within two seconds merge into one with a count, at most four are on screen, and everything also lands in the inbox behind the bell in the topbar. Notifying again with the same `Id` updates the card in place.

An error inside one of your callbacks becomes an error card with **Copy error** and **Retry** instead of a silent warning in the console. Turn that off in the Settings tab.

## Text and inputs

`Label`, `Paragraph`, `Callout` and `TelemetryCard` size themselves to their content. A long body wraps and the row grows; a short one does not leave an empty slot behind.

`Input` shows an elided value while it is not focused, dropping the scheme and keeping the informative head and tail, and restores the real text for editing on focus. `CurrentValue` is always the full string, so a saved webhook URL round-trips exactly even though the field never displays it in full. The callback fires when the text changed or when Enter is pressed.

```luau
local field = Tab:CreateInput({ Flag = "Webhook", Name = "Webhook URL", PlaceholderText = "https://…" })
field:Set("https://discord.com/api/webhooks/1523331338155982949/RvztQ8kLmNoPqRs")
print(field.CurrentValue)   -- the whole URL, not the elided display
```

## Persistence and profiles

Any control given a `Flag` is saved to `FolderName/FileName` shortly after it changes, and each write is read back to confirm it landed. 1.x configuration files load unchanged.

```luau
Argon:LoadConfiguration()             -- restores values, runs callbacks once, enables autosave
Argon:GetFlagValue("AutoFarm")
Argon:SetFlagValue("FlySpeed", 220)
Argon:OnFlagChanged(function(flag, value) print(flag, value) end)
Argon:GetConfigurationStats()
Argon:ResetConfiguration()
```

Restored values always run their callback once, even when the stored value equals the control default, and values whose control does not exist yet are kept rather than dropped.

Profiles are named configurations next to the main file:

```luau
Argon:SaveConfiguration("PvP")             -- save the current values as a profile
Argon:LoadConfiguration("PvP")
Argon:ListConfigurations()                 -- { { Name = "Default", ... }, { Name = "PvP", ... } }
Argon:RenameConfiguration("PvP", "Arena")
Argon:SetAutoloadConfiguration("Arena")    -- loaded by LoadConfiguration() from now on
local code = Argon:ExportConfiguration("Arena")   -- an "ARGON2:..." string to share
Argon:ImportConfiguration(code)
Argon:DeleteConfiguration("Arena")

Window:CreateConfigManager(Tab)            -- a ready-made manager with all of the above
```

Window preferences (theme, accent, scale, size and position, overlays, pins) are kept in a small `.meta.json` file beside the configuration, so they survive even without `ConfigurationSaving`.

## Overlays

A player list, a keybind list and a watermark (fps, ping, time). They are draggable and can stay on screen while the main window is hidden. All three are off unless you turn them on.

```luau
Argon:CreateWindow({ Name = "My Hub", PlayerList = true, KeybindList = true })
Window:SetWatermarkVisible(true)
Window:SetOverlaysAlwaysVisible(true)
Window:TogglePlayerList()
Window:ToggleKeybindList()
```

The keybind list shows every keybind (active ones highlighted) and hides itself when there are none.

## Settings tab

`Window:CreateLibrarySettings(tab)` adds a complete settings page in one call: theme, material, scale, density, reduced motion and typeface; the window name and logo; the menu key, the reopen button and mouse unlock; notifications; overlays; profiles; and a diagnostics copy. The account menu and the palette can open it even if you never create one.

## Themes

Twelve built-in themes: `Argon`, `Amethyst`, `Midnight`, `Emerald`, `Rose`, `Slate`, `Ember`, `Nord`, `Mono`, `Ocean`, plus the light `Daylight` and `HighContrast`. Each one meets fixed contrast targets for text and secondary text. Rayfield theme names (`Default`, `AmberGlow`, `Bloom`, `DarkBlue`, `Green`, `Serenity`, `Light`) map to the closest theme.

```luau
Argon:SetTheme("Nord")
Argon:SetAccent(Color3.fromRGB(255, 120, 60))   -- your accent on any theme; nil to go back
Window:SetMaterial("Clear")                     -- "Solid", "Tinted" or "Clear"
Window:SetScale(1.1)                            -- 0.75 to 1.5
Window:SetDensity("Compact")                    -- "Compact", "Touch", or "Auto" to follow the device

Argon:CreateTheme({ Name = "Coral", Accent = Color3.fromRGB(255, 111, 97), Mode = "Dark" })
Argon:AddTheme("Mine", { Accent = Color3.fromRGB(0, 200, 160) })   -- missing keys are derived
```

Every window gets a theme picker in the topbar. Hovering a theme previews it on the window, and the picker also sets the accent, material, scale and density. `ThemePicker = false` in `CreateWindow` hides the button; `Window:ToggleThemePicker()` opens it from code.

Every control the library builds re-themes itself. If your script builds its own frames outside the library, read the live palette instead of baking in colours:

```luau
local rowColour = Argon:GetColor("Surface")

local unbind = Argon:OnThemeChanged(function(palette, themeName)
    myFrame.BackgroundColor3 = palette.Surface
end)
```

`Argon:GetColor(key, fallback)` resolves a single key, `Argon:GetPalette()` returns a detached snapshot, and `Argon.Palette` is the live table. Main keys: `Frame`, `Sheet`, `Surface`, `Hover`, `Well`, `Border`, `Text`, `Text2`, `Muted`, `Accent`, `AccentHi`, `AccentDeep`, `Success`, `Warning`, `Danger`. The 1.x names (`Background`, `Window`, `Sidebar`, `Input`, `AccentLight`, `AccentDark`, `Dim`, and so on) still work.

## Icons

All 1,573 [Lucide](https://lucide.dev) icons are built in. Nothing is fetched, so icons draw on the first frame, offline too.

```luau
Window:CreateTab("Mining", "pickaxe")
local icon = Argon:GetIcon("shield-check")   -- { Image, ImageRectOffset, ImageRectSize }
Argon:HasIcon("shield-check")                 -- true
```

A Roblox asset id (`"rbxassetid://..."` or a number) works anywhere an icon name does.

## Keyboard and gamepad

| Keys | What they do |
| --- | --- |
| Insert (or your `ToggleUIKeybind`) | Hide or show the window |
| Ctrl+K, `/` | Command palette |
| Ctrl+1 to 9, Ctrl+[ and ] | Switch tabs |
| Arrow keys, Tab | Move the focus ring; Left and Right adjust the focused control |
| Enter, Space | Activate the focused control |
| Shift+F10 | Row menu |
| Ctrl+Z | Undo the last reset or profile load |
| Backspace | Close the top popup, menu or dialog |
| Gamepad | L1/R1 tabs, Y palette, X row menu, B back |

Escape is left alone on purpose: in Roblox it opens the game menu.

## Upgrading from 1.x

Replace the file; your script and your users' saved configurations keep working. A few things look or behave differently on purpose, for example the loader has no fixed timers, the overlays are off by default, Escape no longer closes things, and a keybind's `Callback` fires on press as in Rayfield. [`CHANGELOG.md`](CHANGELOG.md) lists every one.

## FAQ

### Can I port a Rayfield script to Argon UI?

Usually by swapping the loader. The API shape follows Rayfield's, including `CreateWindow`, `CreateTab`, `CreateSection`, the `Create*` control methods with `Flag`, `CurrentValue` and `Callback`, Rayfield's theme names and its `KeySystem` settings. Anything Argon adds is optional.

### What does it need to run?

An environment that provides `loadstring` and `game:HttpGet` (or the file pasted into a LocalScript in Studio). The window goes into `gethui()`, `CoreGui` or `PlayerGui`, whichever is available. Configuration saving needs file functions (`writefile`, `readfile`, `isfile`); without them the library runs fine and simply does not persist.

### Is it fast with hundreds of controls?

Yes. That is what 2.0 was rebuilt for. A window with 400 controls is created without building any of them up front, the visible tab is built first, and the library does no work at all while it sits idle. Measured numbers against 1.x are in [`bench/RESULTS.md`](bench/RESULTS.md).

### Does it work on a phone or a small window?

Yes. Rows wrap to a single stack below `MinColumnWidth`, the sidebar becomes an icon rail on narrow windows, phones get their own landscape and portrait layouts, and every control has a touch size. Tooltips also open on a long-press, but put anything essential in `Description`.

### Is it one file on purpose?

The file you load is one file, so it drops into a single-file script and can be vendored beside it. The source is split into small modules in `src/` and bundled into `argon-ui.luau` by `build.luau`.

### How do I try it without opening Roblox?

Open the [live preview](https://jirkaachs.github.io/argon-ui/preview.html). It is a working reimplementation rather than a screenshot: sliders drag, the colour picker has a real HSV square, the palette searches, rows wrap as the window narrows, and all twelve themes apply live.

### How do I know a change did not break anything?

`tests/` runs the real library outside Roblox against a Roblox API sandbox. Install [Lune](https://github.com/lune-org/lune), then `lune run tests/run_all.luau`. See [`tests/README.md`](tests/README.md).

## Contributing

Issues and pull requests are welcome. Edit the modules in `src/`, then:

```sh
lune run build.luau            # writes argon-ui.luau
lune run tests/run_all.luau    # every suite
```

Commit the rebuilt `argon-ui.luau` together with your change. The design behind 2.0 is in [`design/v2/`](design/v2/).

---

<sub>Also useful if you searched for: Roblox UI library, Luau GUI library, Rayfield alternative, Roblox script hub UI, Roblox menu library single file, Luau interface library with config saving, Roblox UI library with themes, Lucide icons for Roblox, responsive Roblox GUI, Roblox command palette, fast Roblox UI library.</sub>
