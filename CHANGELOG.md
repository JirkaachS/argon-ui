# Changelog

## 2.0.0 (2026-11-01)

Argon UI 2 is a rebuild. The public API is kept source-compatible with 1.18: every method, alias, option key, callback payload and saved-value format still works, and 1.x configuration files load unchanged. Underneath, the library is now about 80 small modules in `src/`, bundled by `build.luau` into the same single `argon-ui.luau`, so `loadstring(game:HttpGet(url))()` keeps working.

The design behind it is in [`design/v2/`](design/v2/).

### Faster loading

- **Nothing slow happens before the window can paint.** 1.x fetched and parsed the whole Lucide icon index with `HttpGet` + `loadstring` on the first icon, called `GetUserThumbnailAsync` synchronously inside `CreateWindow`, and decoded about 48 KB of base64 at load. 2.0 does none of that: all 1,573 Lucide icons are embedded as an 18 KB table, the avatar is an `rbxthumb://` URL, and there is no base64 or file write at load.
- **Controls are state first.** `Create*` builds a plain table in microseconds. Instances are created later by a frame-budgeted scheduler: the visible tab first, the others in the background after the window opens. Reading an instance field such as `element.Root` still works; it builds that control on the spot.
- **No quadratic slowdown.** 1.x scanned every colour against the palette and kept an ever-growing global binding list, so tab 30 built 7-11 times slower than tab 1. 2.0 records themed properties per component, with no global registry.
- **Nothing runs at idle.** One `InputBegan` handler per library (1.x had about 40, plus 43 `InputChanged` and 43 `InputEnded`), no `RenderStepped`/`Heartbeat` work, no endless tweens and no 30-second janitor.
- Measured numbers are in [`bench/RESULTS.md`](bench/RESULTS.md).

### An honest loader

- No fixed timers. Nothing is shown for the first 150 ms; a card appears only while real work is still pending, says what it is doing ("Building Combat · 155 of 212", "Restoring settings · 72 of 96"), and hands over to the already-built window with a short morph. A fast build opens with no card at all.
- The window opens when the host is done: its script finished, it called `FinishLoading`, or it built a tab and went quiet for 250 ms. Manual mode (`Loading = "manual"`, or any `SetLoadingProgress` call) still waits for `FinishLoading`; a stall footer with **Open now** and **Copy log** appears after 8 s without progress, and the watchdog opens the window 30 s after the **last** progress.
- New: `LoadingScreen = "auto" | "always" | "never" | {Title, Subtitle, Tips}`, `LoadingMinimum`, `Window:SetLoadingStatus(text)`, `Window:OnLoaded(fn)`, and `Window:Build(fn)`, which shows a build error on the loader with **Open anyway** and **Copy error**.

### A new look

- A tinted glass frame with an opaque sheet and grouped section platters, a lit edge, light only on active state (switch on, selected tab, primary button, focus), and Montserrat headings over Roboto rows. Radii are concentric (20/14/10).
- 12 themes: the ten 1.x themes with their accents kept, plus **Daylight** and **HighContrast**. Every theme meets the contrast targets in `design/v2/DESIGN_V2.md` (text 10:1 on platters, secondary text 9:1).
- Material choice (`Solid`, `Tinted`, `Clear`), an accent override (`Argon:SetAccent`), interface scale (`Window:SetScale`), density (`Window:SetDensity`: compact, touch) and reduced motion.
- Responsive layouts: wide (with an "On this page" table of contents), standard, a 64 px icon rail, phone landscape, and phone portrait with a bottom tab bar.

### New features

- **Command palette** (Ctrl+K, `/` over the window, the sidebar search, gamepad Y). It finds controls in tabs that were never opened; Enter goes to a control, Ctrl+Enter runs it in place, Left/Right adjust it in place. `Window:RegisterCommand{...}`, `Window:OpenPalette(query)`, and `Keywords = {...}` on any control.
- **Row context menu** (right-click, long-press, Shift+F10, gamepad X): reset to default, copy and paste value, copy flag name, pin, show in palette, plus `Element:AddMenuItem{...}`.
- **Change tracking with undo**: a dot on changed rows, "N changed · Reset tab" in the page header, Reset section, and an Undo pill (Ctrl+Z). `Element.Default`, `Element:IsChanged()`, `Element:Reset()`, `Section:Reset()`, `Tab:Reset()`, `Tab:GetChangedCount()`, `Window:ResetAll()`.
- **Pins**: pin switches and buttons to a Pinned sidebar group and a quick dock that stays on screen while the window is hidden. `Pinned = true` in a control config.
- **Profiles**: `SaveConfiguration(name)`, `LoadConfiguration(name)`, `ListConfigurations`, `RenameConfiguration`, `DeleteConfiguration(name)`, `SetAutoloadConfiguration`, `ExportConfiguration` (an `ARGON2:` code) and `ImportConfiguration`; `Window:CreateConfigManager(tab)` adds a manager.
- **Notifications v2**: `Type` (`info`, `success`, `warning`, `error`, `loading`), `Actions` (up to two buttons), `Id` (update in place), `Image`/`Icon`, automatic duration, a timer that pauses on hover, identical toasts coalescing, at most four on screen, and an inbox behind the topbar bell. `Notify` returns a handle with `Update`, `Dismiss` and `SetProgress`, and it now works before `CreateWindow`. `Argon:Toast(text, type, action)` for small notices.
- **Callback errors** become an error notification with **Copy error** and **Retry** instead of a silent warning.
- **Keyboard and gamepad**: focus mode with a focus ring, arrow-key navigation and adjustment, Ctrl+1-9 and Ctrl+[ ] to switch tabs, gamepad hint bar. Backspace and gamepad B close the top layer.
- **Dialogs**: `Window:Prompt{Title, Content, Placeholder, Default, Validate, OnSubmit, OnCancel}`; Enter activates the focused button; dialogs close on an outside click.
- **New controls and blocks**: `CreateCallout`, `CreateStat` (with sparkline), `CreateImage`, `CreateButtonGroup`, `CreateCheckbox` (a toggle with `Style = "Checkbox"`), button variants (`Primary`, `Ghost`, `Danger`, `DangerSoft`), `Keybind = "F"` on toggles and buttons.
- **Status and badges**: `Window:SetStatus(text, tone)`, `Tab:SetBadge(n | "New" | true)`, and tab groups with `CreateTab(name, icon, { Group = "...", Description = "..." })`.
- **Key gate**: Rayfield's `KeySystem` / `KeySettings`, plus `Validate` and `GetKeyLink`.
- **Settings tab**: `Window:CreateLibrarySettings(tab)` now covers appearance, window name and logo, the menu key, the reopen button, mouse unlock, notifications, overlays, profiles and diagnostics. The account menu and the palette open it even when the host never created one.
- **Overlays**: a watermark (fps, ping, time) next to the player list and the keybind list.
- `Window:SelectTab`, `GetActiveTab`, `IsVisible`, `SetMaterial`, `SetMouseUnlock`, `SetOpenButton`, `Destroy`; `Argon:SetVisibility`, `IsVisible`, `CreateTheme`, `GetPerfStats`; `Section:Set`, `SetCollapsed`; `Divider:Set`; `Button:Set`; `ColorPicker.Color`; `Paragraph:Set({Title, Content})`; `CreateLabel(text, icon, color)`.

### Changes you might notice when upgrading from 1.x

1. There is no pill loader and no 0.93 s minimum. A quick script opens with no loader card, and the window opens when your script is done.
2. The player list and keybind list overlays are off unless you enable them (`PlayerList = true`, `KeybindList = true`, or the setters). The keybind list shows every bind (active ones highlighted) and hides when there are none.
3. A Keybind whose config has `Callback` but no `OnPressed`/`Pressed` now calls `Callback()` on **press**, as Rayfield does (with `HoldToInteract`, `Callback(true)` on press and `Callback(false)` on release). Rebinds fire `OnChanged(key)`. Scripts that used `Callback` as a rebind listener should add `CallOnChange = true` or use `OnChanged`. Configs with `OnPressed` keep the 1.x behaviour.
4. Escape no longer clears a keybind during capture (Backspace or Delete do) and is never a close key, because Escape opens Roblox's own menu. Backspace and gamepad B close the top layer.
5. A notification's `Type` overrides the guess from its title, and the guess now matches whole words ("No errors found" is not an error).
6. No ALL CAPS: section headers, the subtitle and loader status show your text as given. The "LIVE" pill and the "ARGON / TAB" eyebrow are gone (`Window:SetStatus` adds a status chip if you want one).
7. `Dropdown:Set("unknown")` keeps the current selection instead of clearing it.
8. Input fires its callback on Enter even when the text did not change, and `RemoveTextAfterFocusLost` fires once and keeps the submitted text as `CurrentValue`.
9. Controls in a row no longer pad each other to equal height; `_balance()` and `_relayout()` are no-ops.
10. A slider suffix that is a word gets a space ("10 Bananas"); short suffixes stay attached ("50%", "3ms").
11. `PruneRegistries()` returns zero counts: there are no global registries left to prune. `Argon._themeBindings` and `Argon._connections` stay as empty tables.
12. The library settings rows are views over the window preferences instead of flags. The 1.x `ArgonUI*` flag names still work through `GetFlagValue` and `SetFlagValue`.
13. Window size: the default is `max(min(gui - 160, 1080), min(720, gui - 16))` wide by `max(min(gui - 110, 700), min(440, gui - 16))` tall; the sidebar is 232 px and collapses to a 64 px icon rail.
14. `LoadConfiguration()` returns `true` (with an info string) when there is no saved file yet, and when every value is parked for controls that do not exist yet.
15. `SetTheme(table)` is remembered as a custom theme across sessions. Theme changes made from the picker are saved.
16. `OnFlagChanged` unbinds by identity, so unbinding one listener never removes another.
17. `Element:Destroy()` releases the flag (its last value is kept for the next save) and any keybinds the control owned.
18. `SetVisible(false)` survives tab switches and search.
19. Lock and `SetDisabled` block every user path, including a control's keybind; a script's `Set` still works.
20. Closing a confirmation with x, the close key or an outside click calls `OnCancel`.
21. Colour values read from configuration files without the `__argonColor` marker are treated as 0-255 (Rayfield's format).
22. Reading a colour from an instance of a hidden tab right after a theme switch can return the old colour until that tab is shown; read `Argon:GetColor` or `Argon:GetPalette()` instead of instance colours.
23. Overlay transparency (0.12-0.8 in 1.x) now maps onto the frosted HUD range, so overlays stay readable.
24. `SetSmoothTransitions(false)` turns on reduced motion.
25. Technical keeps Sarpanch; the default typeface is still Roboto with Montserrat headings (BuilderSans is one of the six sets).

### Tests

- `tests/run.luau` is still the 1.x contract suite. Where 2.0 deliberately changes a pinned pixel value, colour or wording, the assertion was updated and commented with the reason; [`tests/README.md`](tests/README.md) lists every one.
- New suites: `tests/v2_core.luau` (lazy mounting, scheduler, idle cost, loader, input, persistence and profiles, change tracking, search, notifications, dialogs), `tests/controls_a.luau`, `tests/controls_b.luau`, `tests/display.luau` (control behaviour and instance budgets), `tests/readme.luau` (every README example runs), and `tests/run_all.luau` to run them all.
- `tests/sandbox.luau` now steps frames, computes `AbsoluteSize` and `AbsolutePosition`, has a class hierarchy, a recursive `Destroy`, the full enums the library reads, input simulation, executor profiles and metrics.

## 1.18.3

Last 1.x release. See the git history for earlier changes.
