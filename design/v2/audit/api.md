# Argon UI v2: public API compatibility contract and test dependencies

Audit of `argon-ui.luau` v1.18.3 (3,369 lines), `tests/run.luau` (1,614 lines, 294 pass / 0 fail on lune 0.8.9, re-run 2026-10-31), `tests/sandbox.luau`, `README.md` and `docs/index.html`.

Line numbers (`L123`) refer to `argon-ui.luau` unless prefixed `run.` (tests/run.luau), `sb.` (tests/sandbox.luau) or `docs.` (docs/index.html).

Behaviour marked **[probed]** was executed against the untouched library through the repo sandbox. The probe scripts are `argon-UI-v2-work/bench/api_probe.luau`, `api_probe2.luau` and `api_probe3.luau`; run them with `lune run <file>` from `argon-UI-v2-work/bench`.

Rayfield statements come from Rayfield's public documentation and source as I know them. They are not fetched live here, so check them against the current Rayfield before you treat them as hard requirements.

How to use this document:

- **Section 1 to 14** describe what v1 does today. Treat it as the compatibility contract: a v2 script loader must accept every call shape listed here and give the same observable results, except where Section 16 recommends a deliberate fix.
- **Section 15** is the Rayfield compatibility matrix.
- **Section 16** lists the contract defects found, with recommended v2 decisions.
- **Section 17** lists the test suite's assertions and every internal it reaches into.
- **Section 18** compares the README and docs with the code.

---

## 0. Module shape and load-time side effects

- `loadstring(game:HttpGet(url))()` returns the single `Argon` table (L3369). There is no constructor. All state is module-global: one `Flags` table, one configuration and one palette `C` per load.
- Work done at load time:
  - `prepareIconAtlas()` and `prepareBrandLogo()` (L155-156) run only when `getcustomasset`/`getsynasset` **and** `writefile` exist. On first run they decode about 17 KB of base64 atlas plus about 30 KB of logo in pure Luau, then call `writefile` to `ArgonUI/argon-ui-icons-v2.png` and `ArgonUI/argon-ui-logo-v1.png`.
  - `schedulePrune()` (L261-268) starts a recursive 30 s `task.delay` janitor.
- Executor globals consulted:
  - `getgenv`
  - `gethui` (GUI parent, else `CoreGui`, L587-591)
  - `syn.protect_gui` (L1254, L1377)
  - `readfile`, `writefile`, `isfile`, `isfolder`, `makefolder`, `delfile`, `listfiles`, each with a `syn.*` alias fallback through `FS_ALIASES` (L726-740)
  - `getcustomasset` / `getsynasset`
  - `loadstring` (Lucide index, L344)
  - `game:HttpGet` (Lucide index, L374)
- The v2 loader must keep returning a table with the same field and method names, and must keep working when any of these globals is missing. Today every one of them is optional and wrapped in `pcall`.

## 1. `Argon` (library) surface

### 1.1 Public fields

| Field | Value / semantics | Line |
|---|---|---|
| `Argon.Flags` | `flag -> element` map of every registered control. **Replaced with a new table by every `CreateWindow`** (L1226). | L21, L805 |
| `Argon.Version` | `"1.18.3"`. Asserted by the test suite (run.L44). | L21 |
| `Argon.DefaultFolder` | `"ArgonUI"`. Config folder fallback when `ConfigurationSaving.FolderName` is missing (L761). Asserted (run.L46). | L21 |
| `Argon.AssetFolder` | `"ArgonUI"`. **Dead field**: the icon and logo cache uses the `ASSET_FOLDER` constant, so changing this has no effect. | L21 |
| `Argon.Themes` | `name -> palette` (18 Color3 keys). Ten built-ins: Argon, Amethyst, Midnight, Emerald, Rose, Slate, Ember, Nord, Mono, Ocean. | L32-46 |
| `Argon.Palette` | The **live** palette table `C`. `SetTheme` mutates it in place. | L675 |
| `Argon.CurrentTheme` | Name of the active theme, or `"Custom"` after `SetTheme(table)`. | L627 |
| `Argon.CurrentFont` | Font-set key, default `"Roboto"`. | L514 |

Palette keys (fixed order, `THEME_KEY_ORDER`, L173-177): Background, Window, Sidebar, Surface, Hover, Active, Input, Border, BorderSoft, Text, Muted, Dim, Accent, AccentLight, AccentDark, Success, Warning, Danger.

### 1.2 Public methods

| Method | Returns | Semantics | Line |
|---|---|---|---|
| `CreateWindow(options)` | window | See section 2. Resets `Flags`, `_pendingFlags`, persistence gating and `_destroyed`. | L1221 |
| `Notify(options)` | toast `CanvasGroup` or **nil when no window exists** | See section 10. | L1145 |
| `Destroy()` | nil | Saves (pcall), disconnects every tracked connection, destroys every window's `ScreenGui` and `CursorGui`, clears `_connections`, `_windows`, `Flags`, `_pendingFlags`, `_flagListeners`. Idempotent. Does not clear theme listeners, bindings or renderers. | L1128 |
| `LoadConfiguration()` | `ok, warning-or-reason` | See section 8. | L1019 |
| `SaveConfiguration()` | `true, path` / `false, reason` | Verified write. See section 8. | L973 |
| `SetPersistenceReady(value, saveImmediately)` | `true` or the result of `SaveConfiguration` | Opens or closes the autosave gate and bumps the save token. | L966 |
| `GetFlagValue(flag)` | value | Dropdown: a copy of `CurrentOption`. Keybind: `CurrentKeybind`. Other controls: `CurrentValue`. Unregistered flag: the raw pending value. | L890 |
| `SetFlagValue(flag, value)` | `ok, err` | Registered: applies the value through `applyFlagValue` (silent `Set` followed by exactly one callback and the flag listeners), then autosaves. Unregistered: parks the value in `_pendingFlags`, autosaves, and returns `false, "flag is not registered yet; value stored"`. | L900 |
| `GetFlags()` | table | Snapshot of every registered flag plus pending ones. | L912 |
| `OnFlagChanged(fn)` | unbind function | `fn(flag, value, element)`. Fires on user edits, `Set`, `SetFlagValue` and restores. Asserts that `fn` is a function. **Unbind is index-based and buggy** (section 16, D6). | L957 |
| `GetConfigurationStats()` | table | `{Path, Enabled, Ready, Loading, RegisteredFlags, PendingFlags, LastError, LastAutosaveError, LastSaveAt, LastLoadAt, LastLoad}`. `LastLoad = {path,total,applied,missing,failed,slowest}`. The timestamps come from `os.clock()`. | L920 |
| `DeleteConfiguration()` | `true, path` / `false, reason` | Needs `delfile`. Returns `true` when the file is already absent. | L933 |
| `ResetConfiguration()` | as Delete | Suspends autosave during the call, bumps the token, clears pending flags, deletes the file and clears `_lastConfigStats`. **Does not reset control values.** | L946 |
| `AddTheme(name, palette)` | merged palette | Asserts a non-empty string name and a table palette. Merges the palette's Color3 values onto a copy of `Themes.Argon`; any other value is ignored. | L607 |
| `GetThemes()` | sorted array of names | | L616 |
| `SetTheme(nameOrTable)` | `true` / `false, "Unknown theme: x"` | Mutates `C` in place. Calls the renderers synchronously, then repaints bindings in a `task.spawn` that yields every 350 bindings, then fires the theme listeners. **Does not autosave** (`Window:SetTheme` does). | L623 |
| `GetColor(key, fallback)` | Color3 | Live palette lookup. Unknown key returns `fallback or C.Text`. | L676 |
| `GetPalette()` | table | Detached shallow snapshot. | L682 |
| `OnThemeChanged(fn)` | unbind function | `fn(palette, themeName)`, where `palette` is the live `C`. A non-function argument returns a no-op unbind (it does not assert, unlike `OnFlagChanged`). | L688 |
| `SetFont(name)` | `Argon` (chainable) | One of the `FONT_ORDER` keys: Roboto, BuilderSans, Ubuntu, Condensed, Technical, Gotham. An unknown name is ignored silently. Repaints every recorded `FontFace`. **Does not autosave** (`Window:SetFont` does). | L543 |
| `GetFonts()` | array | `FONT_ORDER`. | L535 |
| `GetFontLabel(name?)` | string or nil | For example `"Roboto + Montserrat"`. | L541 |
| `GetIcon(name)` | `{Image, ImageRectOffset, ImageRectSize}` or nil | Lucide spritesheet entry. **On first call it blocks on `HttpGet` and `loadstring` of the whole Lucide index** (or `readfile` + `loadstring` from `ArgonUI/lucide-icons.luau`). Returns nil offline; it never returns the bundled atlas. | L401 |
| `HasIcon(name)` | bool | `GetIcon(name) ~= nil`. | L416 |
| `PruneRegistries()` | `{bindings, renderers, fonts, connections}` counts removed | Compacts dead entries and stores the result in `_lastPruneStats`. Also runs every 30 s. | L232 |

Internal method that is still reachable: `_fireThemeListeners()` (L699).

### 1.3 Internal state with observable effects

| Field | Role | Line |
|---|---|---|
| `_pendingFlags` | Stored values whose control is not built yet. Carried into saves and hydrated on `registerFlag`. | L808-816, L986-988 |
| `_uiPreferences` | The `__argon` block from the last load. Read by `CreateWindow` **before drawing** (title, subtitle, font, overlay prefs). | L1239-1242, L1380 |
| `_configuration` | The last window's `ConfigurationSaving` table. | L1233 |
| `_persistenceReady`, `_loadingConfig`, `_saveToken`, `_destroyed` | Autosave gate and debounce. | L769-779 |
| `_lastConfigError`, `_lastAutosaveError`, `_lastSaveAt`, `_lastLoadAt`, `_lastConfigPath`, `_lastConfigStats`, `_lastRestoreCost` | Diagnostics. | |
| `_themeBindings`, `_themeRenderers`, `_themeListeners`, `_themeToken` | Theme engine. | L185-219 |
| `_flagListeners`, `_connections`, `_windows`, `_lastPruneStats` | | |

## 2. `Argon:CreateWindow(options)`: options

| Key | Type / default | Semantics | Line |
|---|---|---|---|
| `Name` | string, `"Argon UI"` | Sidebar brand, loader title and default title. A **saved rename** (`_uiPreferences.Title`) takes precedence. | L1241 |
| `Subtitle` | string, `"Control Center"` | Shown upper-cased. A saved rename takes precedence. | L1242 |
| `Logo` | `"rbxassetid://n"`, `"rbxthumb://..."` or a number | Any other string falls back to the bundled logo, or to a drawn "A" when that logo is unavailable. A saved `Logo` preference takes precedence. | L452-473, L1293 |
| `Theme` | string or palette table | Applied with `Argon:SetTheme`. A saved `__argon.Theme` re-applies over it on load. | L1234 |
| `Font` | font-set key | `Argon:SetFont`. A saved font takes precedence. | L1235, L1240 |
| `GuiName` (alias `ScreenGuiName`) | `"ArgonUI"` | ScreenGui name. Any existing child of the parent with the same name **and attribute `ArgonUI`** is destroyed. A second ScreenGui is created as `GuiName.."Cursor"`. | L1246-1255, L1375 |
| `ToggleUIKeybind` | EnumItem, default `Enum.KeyCode.Insert` | **Strings are not normalised** (defect D1). `Window:SetToggleKey` does normalise them. | L1385, L3097 |
| `ConfigurationSaving` | `{Enabled, FolderName, FileName, FileExtension}`, default `{Enabled=false}` | See section 8. **Global**: the last window created wins. | L1233, L758-767 |
| `Loading` = `"manual"` or `ManualLoading` = true | false | Keeps the loader up until `FinishLoading` (or the 30 s watchdog fires). | L3326 |
| `PlayerList` | bool, default true | **Ignored after construction** (defect D2). It also moves the notification column to x=-304 unless both overlay options are false. | L1368, L1385, L1527 |
| `KeybindList` | bool, default true | Same defect as `PlayerList`. | same |
| `OverlaysAlwaysVisible` | bool, default false | Pins the overlays while the window is hidden. A saved preference wins. | L1385 |
| `Cursor` | `nil`/`"auto"` (default), `true`, `false` | `"auto"` draws the pointer only when `UserInputService.MouseIconEnabled == false`. Any other truthy value behaves like `"auto"`. | L3151-3158 |
| `ThemePicker` | bool, default true | `false` hides the topbar swatch button, and `ToggleThemePicker()` then returns `false`. | L1334, L3071 |

Ignored Rayfield keys: `LoadingTitle`, `LoadingSubtitle`, `Icon`, `ShowText`, `KeySystem`, `KeySettings`, `Discord`, `DisableRayfieldPrompts`, `DisableBuildWarnings` (section 15).

Side effects of `CreateWindow`:

- Global state reset (L1223-1227), then `task.delay(4)` opens the autosave gate unless a load is in progress (L1230-1232).
- `Players:GetUserThumbnailAsync` is called **synchronously** (L1309).
- The player list is built immediately, with per-row async thumbnails.
- `responsive()` is bound to the viewport.
- The loader starts (section 9).

## 3. Window object

### 3.1 Public fields

These are instance references, and the test suite reads several of them (section 17.2):

- `ScreenGui` (named `GuiName`, `DisplayOrder` 100, attribute `ArgonUI`)
- `CursorGui` (`DisplayOrder` 2147483647, `IgnoreGuiInset` true)
- `Main`: a plain `Frame` named `ArgonWindow`, carrying a UIGradient
- `Shadow`
- `Sidebar`: has a UICorner and a child `SquareEdge` of size (0,16,1,0)
- `Content`: holds children `TopBar`, `JumpRail` and `ThemePicker` (with `ThemeOptions`)
- `TabList`, `PageHost`
- `Notifications`: parented to `ScreenGui`, not to `Main`
- `Tabs`: array
- `ActiveTab`
- `PlayerListOverlay`, `KeybindListOverlay`: overlay root Frames, **unnamed** (their Name is "Frame")

### 3.2 Public methods (all at L1387-1520 unless noted)

| Method | Returns | Notes |
|---|---|---|
| `SetVisibility(bool)` | nil | `false` closes any dropdown or colour popup and hides `Main` and `Shadow`, then refreshes the overlays. |
| `ToggleVisibility()`, `Toggle()`, `Open()`, `Close()` | nil | `Window:Toggle` toggles visibility; `Tab:Toggle` creates a toggle (same name, different meaning). |
| `SetToggleKey(keyOrName)` | nil | Accepts an EnumItem or a key name (strips `Enum.KeyCode.`). An unknown name keeps the previous key. |
| `SetTitle(s)` / `SetSubtitle(s)` | self | Trims, truncates to 40 chars; an empty string restores the host default. Autosaves. |
| `GetTitle()` / `GetSubtitle()` | string | |
| `SetLogo(v)` | self | Autosaves. |
| `SetFont(name)` | self | Autosaves only when the font actually changed. |
| `GetFonts()` | array | |
| `SetTheme(name)` | `ok, err` | Autosaves when `ok`. |
| `GetThemes()` | array | |
| `SetSize(Vector2 or {w,h} or {X=,Y=})` | self | Clamped to [min(560, vw-20) .. min(1200, vw-20)] by [min(400, vh-20) .. min(820, vh-20)], with floors of 360 and 340. Marks the window as user-sized and re-runs the layout. |
| `SetPlayerListVisible(bool)` / `SetKeybindListVisible(bool)` | self | Autosaves. |
| `TogglePlayerList()` / `ToggleKeybindList()` | self | |
| `SetOverlaysAlwaysVisible(bool)` (alias `SetOverlaysPinned`) | self | Autosaves. |
| `ToggleOverlaysAlwaysVisible()` | self | |
| `AreOverlaysAlwaysVisible()` | bool | |
| `SetOverlayTransparency(n)` | self | Clamped to .12-.8, default .38. Autosaves. |
| `SetOverlayScale(n)` | self | Clamped to .75-1.4. Autosaves. |
| `SetSmoothTransitions(bool)` | self | Autosaves. |
| `ResetOverlayPositions()` | self | Autosaves. |
| `Dialog(config)` (alias `Popup`) | dialog | L1580. See section 10. |
| `Confirm(configOrString)` | dialog | L1638. |
| `CreateTab(name, icon)` | tab | L1694. `name` defaults to "Tab", `icon` to "activity". The first tab is auto-selected. |
| `CreateLibrarySettings(tab)` | tab | L2934. Once per window; a nil tab returns nil. See section 12. |
| `SetThemePickerVisible(bool)` | bool | L3059. The button also hides itself when the window is narrower than 520 px. |
| `ToggleThemePicker()` | new open state (bool) | L3065. Returns `false` when the button is hidden. |
| `SetCursorVisible(true/false/nil)` | self | L3170. `nil` means "auto". |
| `IsCursorDrawn()` | bool | L3175. |
| `SetLoadingProgress(fraction, status?)` | self | L3330. See section 9. |
| `FinishLoading()` | self | L3348. Idempotent. |
| `IsLoading()` | bool | L3349. |

Private but reachable, and used by the tests:

- `_select(tab)` (L1654)
- `_refreshSectionMenu()` (L2978)
- `_setJumpRailFiltered(bool)`, called with dot syntax (L2971)
- `_refreshOverlayVisibility()` (L1477)
- `_refreshKeybindOverlay()` (L1558)
- `_exportUIPreferences()` (L1517)
- `_applyUIPreferences(t)` (L1520)
- `_relayout` (L3140)

Private fields:

- `_loading`, `_loadingManual`, `_loadingProgress`, `_loadingExpanded`, `_shellSize`
- `_visible`, `_toggleKey`, `_userSized`, `_minSize`
- `_keybindEntries`, `_tabTransitionToken`
- `_logo`, `_title`, `_subtitle`, `_defaultTitle`, `_defaultSubtitle`
- `_smoothTransitions`, `_overlayTransparency`, `_overlayScale`
- `_playerListEnabled`, `_keybindListEnabled`, `_overlaysAlwaysVisible`
- `_themePickerEnabled`, `_cursorMode`
- `_dropdownPopup`, `_colorPopup`, `_tooltip`, `_librarySettingsCreated`

Built-in input handling:

- The toggle key flips visibility (L3097).
- `/` focuses the tab search while the window is visible (L3098).
- The topbar drags the window and a bottom-right grip resizes it (L3075-3092). There are no edge handles, despite what docs.L517 says.
- A "–" button hides the window (L3093).

There is no Escape handling, no `Window:Destroy`, and no public tab-select method.

## 4. Tab object (L1694-2932)

Builders. Each Create* name has a prefix-free alias assigned at L2906-2925:

| Create* method | Alias(es) |
|---|---|
| `CreateSection` | `Section` |
| `CreateRow` | `Row` |
| `CreateLabel` | `Label` |
| `CreateButton` | `Button` |
| `CreateToggle` | `Toggle` |
| `CreateSlider` | `Slider` |
| `CreateInput` | `Input` |
| `CreateKeybind` | `Keybind` |
| `CreateDropdown` | `Dropdown` |
| `CreateParagraph` | `Paragraph` |
| `CreateTelemetryCard` | `TelemetryCard` |
| `CreateDivider` | `Divider` |
| `CreateSpace` | `Space` |
| `CreateProgressBar` | `ProgressBar` |
| `CreateStepper` | `Stepper` |
| `CreateSegmented` | `Segmented` |
| `CreateTextArea` | `TextArea` |
| `CreateList` | `List` |
| `CreateColorPicker` | `ColorPicker` and `Colorpicker` |

The aliases are copies of the function values. Both `Tab:Toggle{}` and `Tab.Toggle(Tab, {})` work.

Placement rules:

- `Tab:CreateX` goes into the **most recent section created on that tab** (`tab._currentSection`).
- A control created before any section auto-creates a section called "General" (L1798, L1945).
- `CreateSection(nameOrTable)` accepts a string or `{Title=}`/`{Name=}` and makes the new section current (L1758-1785).

Fields:

- Public: `Name`, `IconName`, `Window`, `TabButton`, `Accent`, `IconBox`, `Icon`, `ButtonTitle`, `Count` (shows `_controlCount`, which counts Labels, Dividers and Spaces too), `Page` (ScrollingFrame), `PageGroup` (plain Frame).
- Private: `_elements`, `_sections`, `_controlCount`, `_currentSection`, `_renderState`, `_updateCount`, `_filter(query)`.

Search (`_filter`, L1730-1756):

- Case-insensitive plain substring match on `element.Name` **or** `section.Name`.
- It **writes `Root.Visible` on every element**, so it overrides `SetVisible` (defect D7).
- A row is visible when any of its children is visible.
- `_select(tab)` always clears the search and calls `_filter("")`.

## 5. Section and Row

**Section** (L1758-1785):

- Fields: `Name`, `Elements`, `Root`, `Body`, `Layout`, `Rows`.
- Builders: every Tab builder **except `Section`/`CreateSection`**, in both the `CreateX` and the `X` form, plus `Row`/`CreateRow`.
- A section builder temporarily swaps `tab._currentSection` and restores it afterwards (`section:_build`, L1769-1774), so `Section:Toggle{}` does not change where later `Tab:CreateX` calls go.
- Builder errors propagate (`error(msg, 2)`).
- There is no `Section:Set` (Rayfield gap).

**Row** (`Tab:CreateRow(cfg)` / `Section:Row(cfg)`, L1796-1942):

- `cfg` may be a number (column count) or a table:

  | Key | Default | Clamp |
  |---|---|---|
  | `Columns` | 2 | 1-4 |
  | `Spacing` | 7 | 0-24 |
  | `MinColumnWidth` | 200 | 80-400 |
  | `Name` | owner section's name | |

- Fields: `Name`, `Columns` (array of `{Holder, Layout, Section}`, where `Holder.LayoutOrder` is the column index), `Elements`, `Owner`, `Root`, `Layout`.
- Methods:
  - `Use(i)` (returns the row) sends the next control to column `i`.
  - Every section builder except `Row` (no nested rows).
- Private: `_next`, `_balance()`, `_relayout()`, `_build`.
- Behaviour:
  - Controls are distributed round-robin.
  - Each control is added to the owning section's `Elements` (so search and counts include it) and gets `element.Row = row`.
  - Columns stack vertically when `(width - gaps)/cols < MinColumnWidth`.
  - Controls on the same visual line are padded to the tallest one (`_rowPad`).

## 6. Common element contract (`base()`, L1944-2247)

Every Create* returns an element table.

Fields:

| Field | Meaning |
|---|---|
| `Name` | `tostring(config.Name or "Control")`, used by search. For a Button with no Name it is `"Control"` while the visible title says "Button". |
| `Root` | Frame named `Control` |
| `Section` | The section, or a row column's pseudo-section |
| `Type` | Control type string |
| `Flag` | Set when the control is flagged |
| `CurrentValue` | Present on every control |
| `Row` | Set when the control lives in a row |
| `Locked`, `LockReason` | Lock state |
| `HasTooltip` | Tooltip state |

Private fields: `_stroke`, `_callback` (= `config.Callback`), `_title`, `_description`, `_tooltipText`, `_tipMarker`, `_lock{Root,Badge,Label,Icon,Gauge,Fit}`, `_rowPad`, `_onDestroy`, and others.

| Method | Returns | Semantics |
|---|---|---|
| `SetVisible(bool)` | self | Sets `Root.Visible`. **Undone by the next tab switch or search clear** (D7). |
| `SetTitle(text)` | self | Updates `Name` and the title label. |
| `SetDesc(text)` | self | Puts a wrapped description under the control's natural "band". Children are pinned into the band, the row grows to fit, and an empty string hides it and shrinks the row. |
| `SetTooltip(text)` (alias `element:Tooltip(text)`) | self | Adds a "?" marker after the title. Opens after 0.28 s, anchored beside the row (right, left, below or above) at `window._tooltip`; one tooltip per window. An empty string hides the marker. |
| `Lock(reason?)` | self | A dimming scrim (a TextButton that swallows clicks), plus a padlock badge with three width tiers (reason, "LOCKED", icon only). Locking again only updates the reason. **Visual only**: programmatic `Set`, restore and keybind hotkeys still act (D26). |
| `Unlock()` | self | |
| `SetLocked(bool, reason?)` | self | |
| `Destroy()` | nil | Removes the control from its section, the tab and the count. **Does not unregister its Flag or disconnect its global input listeners** (D8). |

Config keys read by `base` for every control that passes `config` to it:

| Key (alias) | Effect |
|---|---|
| `Tooltip` (`Tip`) | Deferred `SetTooltip` |
| `Description` (`Desc`) | Deferred `SetDesc` |
| `Callback` | Becomes `_callback`, used by restores |

Controls that pass `config`: Button, Toggle, Slider, Input, Keybind, Dropdown, ProgressBar, Stepper, Segmented, TextArea, List, ColorPicker.

Controls that **do not** pass it, so `Tooltip` and `Description` are ignored at construction (the methods still work afterwards): Label, Paragraph, TelemetryCard, Divider, Space (D15).

Commit path for user and programmatic edits (`changed()`, L831-838), in this order:

1. Flag listeners fire (`element.Flag` only).
2. The border flashes.
3. Autosave is scheduled.
4. **Then** `config.Callback` runs through `safeCall`, which turns errors into `warn("[Argon UI] Callback error: ...")`.

`Set(v, true)` (silent) skips all four steps.

## 7. Controls

Values in the Height column are natural heights. The tests pin some of them (section 17.2). Every `Set(v, silent)` fires only when the value changed and `silent` is falsy.

### Label: `CreateLabel(text)` (L2257). Type `Label`. Height: auto.
- Accepts a string only. A table argument renders as `"table: 0x..."` **[probed]**.
- `Set(text)` and `SetContent(text)` return self and also update `Name`.
- Not flaggable.

### Button: `CreateButton{Name, Callback, Tooltip, Description}` (L2272). Type `Button`. Height 50.
- `Callback()` runs with no arguments on click.
- **No `Set` method** (Rayfield's `Button:Set(name)` is missing; `SetTitle` exists).

### Toggle: `CreateToggle{Name="Toggle", Flag, CurrentValue=false, Callback(bool)}` (L2283). Type `Toggle`. Height 54.
- `Set(v, silent)` uses `v == true` strictly: `Set("true")` stores `false` **[probed]**. Returns nil.
- Persisted as a JSON boolean.

### Slider: `CreateSlider{Name, Flag, Range={0,100}, Increment=1, Suffix, CurrentValue=min, Callback(number)}` (L2306). Type `Slider`. Height 72.
- `Set` accepts a number or a string containing a number (the first numeric run).
- Rounding: `floor((v-min)/inc+.5)*inc+min`, then rounded to the increment's decimal places, then clamped.
- `Set` returns nil.
- The display is `value..Suffix` with no space (Rayfield inserts a space).
- The value box can be edited (commits on FocusLost).
- The callback fires on **every** drag movement that changes the value.
- Persisted as a number.

### Input: `CreateInput{Name="Input", Flag, CurrentValue="", PlaceholderText="Enter value...", RemoveTextAfterFocusLost, Callback(string)}` (L2352). Type `Input`. Height 74.
- `Set` returns self.
- The callback fires on FocusLost **only when the text changed** (Rayfield fires on every FocusLost).
- Elided display while unfocused: drop `^https?://`. If the rest is 38 characters or fewer, show it in full; otherwise show the first 24 + "…" + the last 10. The real text comes back on focus.
- A clear (x) button runs `Set("")`.
- With `RemoveTextAfterFocusLost`, the callback fires twice (`"text"`, then `""`) and `""` is what gets persisted **[probed]** (D13).
- Persisted as a string.

### Keybind: `CreateKeybind{...}` (L2414). Type `Keybind`. Height 54.

| Config key | Default | Meaning |
|---|---|---|
| `Name` | | Title |
| `Flag` | | Persistence |
| `CurrentKeybind` | `"None"` | String or EnumItem |
| `Callback(keyName)` | | Fires on **rebind** |
| `OnPressed` (alias `Pressed`) | | `(keyName, active)` on press |
| `Toggle` | false | Latch instead of a 0.18 s pulse |
| `Active` | false | Initial overlay state |
| `DisplayInKeybindList` | true | Show in the overlay |

- Fields: `CurrentKeybind` (and `CurrentValue`, the same string).
- Methods:
  - `Set(keyOrName, silent)` returns nil and refreshes the overlay.
  - `SetActive(bool)` returns self.
  - `SetOverlayVisible(bool)` returns self.
- Listening: click the button, then press a keyboard key. Escape or Backspace sets `"None"`.
- Hotkey matching: keyboard only, by `KeyCode.Name`; `gameProcessed` input is ignored.
- The overlay lists only **active** binds.
- **On `LoadConfiguration` the Callback runs once with the key name** **[probed]** (D3).
- Rayfield's `HoldToInteract` and `CallOnChange` are not read.
- Persisted as the key-name string.

### Dropdown: `CreateDropdown{Name, Flag, Options={}, CurrentOption (string or table), MultipleOptions=false, Callback(tableCopy)}` (L2451). Type `Dropdown`. Height 58.
- Fields: `Options` (copy), `CurrentOption`, `CurrentValue` (**the same table reference** as `CurrentOption`), `_desiredOption`.
- `Set(v, silent)`:
  - Accepts a string or an array. Values not in `Options` are dropped; single-select keeps the first match.
  - Remembers the requested value as `_desiredOption`.
  - When nothing matched and the control is flagged, parks the request in `_pendingFlags`.
  - Change is detected by comparing JSON encodings. Returns nil.
  - `Set("unknown")` on a populated dropdown clears the selection and fires `Callback({})` **[probed]**.
- `Refresh(newOptions, keepCurrent=true)` returns self:
  - Keeps the selected values that are still present.
  - When none survive, applies `_desiredOption` if it is now present, and **fires the Callback without listeners or autosave**.
  - When the selection was dropped, **fires nothing** **[probed]** (D12).
- `SetOptions` is an alias of `Refresh`. `GetSelected()` returns a copy.
- The popup is 226 px tall regardless of the option count, has a filter box, closes on pick in single-select mode and toggles items in multi-select mode.
- Display: "Select..." when empty; with more than two selections in multi mode, "first  +N".
- Persisted as a JSON array.

### Paragraph: `CreateParagraph{Title|Name="Information", Content|Description="", Icon="info"}` or a string (taken as the content) (L2551). Type `Paragraph`. Height: auto.
- `Set(text)` and `SetContent(text)`, both returning self.
- **`Set({Title,Content})` (Rayfield's form) renders `"table: 0x..."`** **[probed]** (D4).

### TelemetryCard: `CreateTelemetryCard{...}` or a string (taken as the title) (L2568). Type `TelemetryCard`. Height: auto.

| Config key | Default |
|---|---|
| `Title` / `Name` | `"Telemetry"` (shown upper-cased) |
| `Content` / `Description` | `"Waiting for data..."` |
| `Status` | `"LIVE"` |
| `Icon` | `"activity"` |
| `Accent` | the Color3 accent at build time |

- Fields: `Status` (TextLabel with AutomaticSize X), `Icon`, `Rail`.
- Methods: `Set` / `SetContent(text)`, and `SetStatus(text, color?)` (a colour recolours the pill, its stroke, the icon and the title).

### Divider: `CreateDivider(stringOr{Title|Name} or nil)` (L2606). Type `Divider`. Height 29 with a label, 15 without.
- **No `Set`** (Rayfield's `Divider:Set(bool)` is missing).

### Space: `CreateSpace(px=10)` (L2618). Type `Space`. Height: `px` clamped to 4-80.

### ProgressBar: `CreateProgressBar{...}` (L2623). Type `ProgressBar`. Height 64.

| Config key | Default | Meaning |
|---|---|---|
| `Name` | `"Progress"` | Title |
| `Minimum` | 0 | |
| `Maximum` | 100 | |
| `CurrentValue` | `Minimum` | |
| `Format(value, max, ratio)` | | Returns the readout string |
| `ShowValue` | false | Readout shows the value |
| `Suffix` | | Used with `ShowValue` |
| `Callback(number)` | | Fires on change |

- Methods: `Set(v, silent)` (clamped, returns self), `SetRange(min, max)` (silent re-clamp), `SetColor(Color3)`, `Increment(n=1)`.
- **No Flag, no listeners and no autosave**; it is never persisted (asserted in run.L683).

### Stepper: `CreateStepper{Name, Flag, Range={0,100}, Increment=1, Suffix, CurrentValue=min, Callback(number)}` (L2660). Type `Stepper`. Height 54.
- Rounds like the Slider. `Set` returns self.
- The minus and plus buttons dim at the limits; the text box is editable.
- Persisted as a number.

### Segmented: `CreateSegmented{Name (optional), Flag, Options (stringified, default {"None"}), CurrentOption|CurrentValue, Callback(string)}` (L2697). Type `Segmented`. Height 76 with a title, 48 without.
- `CurrentOption` or `CurrentValue` may be a string or a table (the first entry is used); the default is the first option.
- `Set(v)` accepts a string or `table[1]`. An unknown value is rejected and, when the control is flagged, parked in `_pendingFlags`. Returns self.
- `Refresh(options, keepCurrent)` resets to the first option when the current one is missing or `keepCurrent == false`. It fires no callback.
- Persisted as a string.

### TextArea: `CreateTextArea{Name="Notes", Flag, CurrentValue, PlaceholderText="Enter text...", Height=104 (72-320), Callback(string)}` (L2754). Type `TextArea`.
- `Set` returns self. `GetLines()` returns the non-empty lines.
- Commits on FocusLost.
- Persisted as a string.

### List: `CreateList{Name="List", Height=156 (80-420), EmptyText="No items", Items, Callback(record, item)}` (L2781). Type `List`.
- Field: `Items` (normalised records).
- `SetItems(items)`, `AddItem(item)` and `Clear()` all return self.
- A string item becomes `{Title=item}`.
- Record keys: `Title`/`Name`, `Description` (a 44 px row instead of 30 px), `Color` (title tint), `Actions`, `Action`, `Callback`.
  - `Actions` is an array of `{Label|Title, Callback(record,item), Style="danger"|"warning", Color}` or of plain strings (which use `record.Callback`).
  - `Action` is a single label that uses `record.Callback`.
- Button widths: 78 px for up to two actions, 58 px for more; they are laid out right-aligned without overlap.
- With no actions and a list-level `Callback`, the whole row is clickable.
- Not flaggable.

### ColorPicker: `CreateColorPicker{Name="Color picker", Flag, Color|CurrentValue (Color3, default the accent), Callback(Color3)}` (L2851). Type `ColorPicker`. Height 58.
- `Set(Color3 or "#RRGGBB"/"RRGGBB")` returns nil.
- The popup has an HSV square, a hue strip and a hex box. There is no alpha.
- **No `.Color` field** (Rayfield reads `Picker.Color`) **[probed]**.
- Persisted as `{"__argonColor":true,"R":0..1,"G":0..1,"B":0..1}`.

## 8. Flags and persistence contract

### Registration (`registerFlag`, L801-818)
- An empty or nil flag does nothing.
- A duplicate flag warns `"[Argon UI] Duplicate configuration flag replaced: X"` (the test suite tolerates this warning) and the newest control wins.
- When the flag has a pending value, it is applied immediately: a silent `Set`, then exactly one callback and the listeners, with `_loadingConfig` held so no autosave happens. On success the pending entry is cleared.

### Path (`configPath`, L758-767)

    (FolderName or Argon.DefaultFolder) .. "/" .. FileName

- `FileName` defaults to `"Argon"`.
- `FileExtension` (default `".rfld"`) is appended **only** when `FileName` does not already match `%.[%w_%-]+$`.
- `Enabled` must be truthy.

### File format (JSON object, L983-997)
- `flag -> value`, using the per-control formats in section 7.
- Pending and orphan flags are written first, and live controls overwrite them.
- One reserved key, `"__argon"`, holds UI preferences exported from **the last window only**:

      {Theme, Font, Title, Subtitle, Logo, PlayerListEnabled, KeybindListEnabled,
       OverlaysAlwaysVisible, OverlayTransparency, OverlayScale, SmoothTransitions,
       OverlayPositions={Players={XS,XO,YS,YO}, Keybinds={...}}}

- A flag literally named `__argon` is skipped on save and load.

### Reading foreign formats (`normalizeConfigValue`, L840-866)
- Table wrappers `{CurrentValue}`, `{CurrentOption}`, `{CurrentKeybind}`, `{Keybind}`, `{Object}`, `{Color}` and `{Value}` are unwrapped.
- ColorPicker accepts `{R,G,B}`, `{r,g,b}` or `{1,2,3}`. When any channel is greater than 1 the values are treated as 0-255; otherwise as 0-1 (D25).

### Verified write (`SaveConfiguration`, L973-1017)
1. Requires `writefile`.
2. `ensureFolder(folder)`.
3. JSON-encode.
4. Write.
5. Read back and compare byte-for-byte when `readfile` exists; otherwise check `isfile`.
6. Any failure sets `_lastConfigError` and returns `false, reason`.
7. Success returns `true, path` and records `_lastSaveAt`.

### Autosave (`scheduleSave`, L769-779)
- Requires all of: `_persistenceReady`, not `_loadingConfig`, not `_destroyed`, and a path.
- Debounced to **0.35 s** by a token.
- A failure warns `"[Argon UI] Configuration autosave failed: ..."`.
- Triggered by:
  - every `changed()` commit
  - `SetFlagValue`
  - window preference setters: `SetTitle`, `SetSubtitle`, `SetLogo`, `SetFont` (only on change), `SetTheme`, the overlay setters, `SetSmoothTransitions`, `ResetOverlayPositions`
  - releasing an overlay drag
- **Not triggered by** `Argon:SetTheme`, `Argon:SetFont`, the topbar theme picker without a library-settings tab (D16), `ProgressBar` or `Dropdown:Refresh`.

### Gate
- Closed by `CreateWindow`.
- Opened by any of: `LoadConfiguration` (also when the file is missing), `SetPersistenceReady(true)`, or the **4 s fallback** after `CreateWindow` (L1230).

### Load (`LoadConfiguration`, L1019-1126)

Requirements and early exits:
- Requires `readfile`.
- Missing file: opens the gate and returns `false, "configuration file does not exist: path"`.
- Invalid JSON returns `false`.

Order of work:
1. Copy `__argon` into `_uiPreferences` and apply it to **every** window with `_applyUIPreferences`.
2. Restore flags in a fixed order: **non-booleans first, then booleans**, alphabetical within each group.
3. A flag whose control exists is applied with `applyFlagValue`: a silent `Set`, then **exactly one callback even when the value equals the default**, then the listeners.
4. A flag whose control is missing is copied into `_pendingFlags` and counted as missing.

Progress and timing:
- When a window is still loading, progress goes to its `SetLoadingProgress` as `"RESTORING CONFIGURATION i/n"`, about 40 times per restore (every flag when there are fewer than 40). Progress runs from the current `_loadingProgress` (or .8) up to .995.
- The restore yields (`task.wait`) every 45 ms of work.
- Callbacks slower than 25 ms are collected and reported with `warn("[Argon UI] Slowest restore callbacks: ...")`.

Return values:
- `false, "configuration contained N flag(s), but none matched the current UI registry"` when no flag applied, **even if they were all parked successfully** (D10).
- Otherwise `true, warning-or-nil`. The warning summarises failures and unknown flags, and the summary is also `warn`ed.

### Other operations
- **Reset/Delete**: see section 1.2.
- **Destroy** saves first.

### Reserved names

| Kind | Names |
|---|---|
| Flags | `__argon` |
| Library-settings flags | `ArgonUIWindowTitle`, `ArgonUIWindowSubtitle`, `ArgonUITheme`, `ArgonUIFont`, `ArgonUIPlayerList`, `ArgonUIKeybindList`, `ArgonUIOverlaysAlwaysVisible`, `ArgonUIPlayerListKey`, `ArgonUIKeybindListKey`, `ArgonUISmoothTransitions`, `ArgonUIOverlayOpacity`, `ArgonUIOverlayScale`, `ArgonUICustomLogo` |
| ScreenGuis | `GuiName`, `GuiName.."Cursor"` |
| Cache files in `ArgonUI/` | `argon-ui-icons-v2.png`, `argon-ui-logo-v1.png`, `lucide-icons.luau` |

## 9. Loader contract (L3177-3366)

1. The window starts covered: `_loading = true`, `Main` is shrunk to a **392x108 pill** (`SPLASH_W`, `SPLASH_H`), and the sidebar, content, glow, shadow and overlays are hidden.
2. The pill shows: the logo plate, the title and subtitle (saved renames win), a status line ("INITIALIZING INTERFACE"), a counting percentage and a progress rail.
3. Non-manual hosts:
   - at 0.38 s the status becomes "OPENING CONTROL CENTER" and the shell grows;
   - at **0.93 s** `openWindow()` runs.
4. Manual mode: `Loading = "manual"` or `ManualLoading = true`, **or any call to `SetLoadingProgress`**, which sets `_loadingManual = true`.
5. `SetLoadingProgress(f, status)`:
   - `f` is clamped to [0,1] and progress is monotonic (`max` with the previous value, floor .08);
   - the status is upper-cased;
   - the shell is **not** expanded;
   - after loading has finished, the call is a no-op.
6. `FinishLoading()` sets the status to "OPENING <SUBTITLE>" and the bar to 100%, expands for 0.42 s if needed, reveals the shell and fades the cover. The cover is destroyed after 0.32 s, then `responsive()` and the overlay refresh run.
7. The **watchdog** at `task.delay(30, openWindow)` is measured from `CreateWindow`, not from the last progress report **[probed]** (D11).
8. Overlays stay hidden while `_loading` is set (L1481-1485).

## 10. Notifications and dialogs

### `Argon:Notify{...}` (L1145-1219)

| Key | Default |
|---|---|
| `Title` | `"Notification"` |
| `Content` / `Description` | `""` |
| `Duration` | 4 (seconds) |

- Severity is chosen by substrings of the lower-cased title:

  | Title contains | Accent | Glyph |
  |---|---|---|
  | "error" or "failed" | Danger | circle-x |
  | "warn" or "wait" | Warning | triangle-alert |
  | "success", "complete" or "saved" | Success | circle-check |
  | anything else | Accent | info |

- The toast is built on the **last created window's** `Notifications` layer, which stays visible while the window is hidden.
- The toast is a CanvasGroup with AutomaticSize Y. The stack is capped at 5 (oldest destroyed first), and each toast has a close button and a timer bar.
- Returns the toast.
- With no window, returns **nil and shows nothing** (D19).
- `Image` and `Actions` are not supported.

### `Window:Dialog{...}` (alias `Popup`) (L1580-1632)

| Key | Default / meaning |
|---|---|
| `Title` | `"Confirm action"` |
| `Content` / `Description` | Body text |
| `Buttons` | default `{{Title="Okay", Variant="Primary"}}` |
| `Show` | true |
| `Transient` | true: destroyed after close |

- Each button: `{Title|Name, Variant="Primary"|"Danger", Primary=bool, Danger=bool, Callback(dialog), AutoClose=true}`.
- Returns `dialog = {Root, Panel, Title, Body, Visible, Show(), Close(), Destroy()}`.
- The dialog has a close button (x) and no Escape or click-outside handling.

### `Window:Confirm(cfgOrString)` (L1638-1653)

| Key | Default / meaning |
|---|---|
| `Title` | `"Confirm"` |
| `Content` / `Description` | `"This cannot be undone."` |
| `CancelText` | `"Cancel"` |
| `ConfirmText` | `"Confirm"` |
| `Variant` | `"Danger"` |
| `OnConfirm` (alias `Callback`) | Fires at most once |
| `OnCancel` | Cancel button only |

- The x close button **does not** call `OnCancel` (D18).

## 11. Overlays, cursor, theme picker

- **Overlays** (L1437-1579):
  - The player list sits at (1,-18,0,72) and is 270x262; the active-binds list sits at (1,-18,0,348) and is 270x214.
  - Each is draggable by its header and collapsible with "-"/"+".
  - Visibility = `not _loading and (_visible or _overlaysAlwaysVisible) and <enabled>`.
  - Positions persist in `__argon.OverlayPositions`.
- **Cursor** (L3151-3175): a RenderStepped loop draws an arrow image at `GetMouseLocation` while the cursor is wanted.
- **Theme picker** (L3001-3073):
  - The button is three dots in AccentLight, Accent and AccentDark.
  - `Content.ThemePicker` (popover) contains `ThemeOptions`, a grid with one TextButton per theme **named after the theme**. Each button holds three palette dots, a `ThemeName` label and a UIStroke whose colour is the accent when that theme is active.
  - Clicking calls `Argon:SetTheme(name)` and, when the library-settings tab exists, writes the choice through the `ArgonUITheme` flag.

## 12. `Window:CreateLibrarySettings(tab)` (L2934-2968)

Adds, in this order, a section "Argon UI Library" containing:

1. An intro label.
2. Input `ArgonUIWindowTitle` and input `ArgonUIWindowSubtitle` (rename fields).
3. Dropdown `ArgonUITheme`. Its options are captured at creation, so themes added later are missing.
4. Dropdown `ArgonUIFont`.
5. Toggles `ArgonUIPlayerList`, `ArgonUIKeybindList` and `ArgonUIOverlaysAlwaysVisible`.
6. Keybinds `ArgonUIPlayerListKey` and `ArgonUIKeybindListKey`, which use `OnPressed`.
7. Toggle `ArgonUISmoothTransitions`.
8. Slider `ArgonUIOverlayOpacity` (20-88) and slider `ArgonUIOverlayScale` (75-140).
9. Input `ArgonUICustomLogo`.
10. Button "Reset Overlay Positions".

UI preferences are therefore persisted **twice**: in `__argon` and in these flags.

## 13. Themes and fonts

- **Theme repaint model:** see L185-219 and L623-670.
  - Any Color3 property passed to `create()` that equals a palette entry is bound to that key.
  - Controls whose colour depends on state opt out with `unbindTheme` and register a renderer: toggle track and knob, input well, keybind text, dropdown text, segmented pills, tab buttons, colour swatch, theme-picker dots, telemetry status.
- `SetTheme(table)` records the theme as `"Custom"`, which cannot be restored from `__argon.Theme` (D23).
- **Fonts** (L493-556):

  | Key | Body face | Display face |
  |---|---|---|
  | Roboto (default) | Roboto | Montserrat |
  | BuilderSans | BuilderSans | BuilderSans |
  | Ubuntu | Ubuntu | Ubuntu |
  | Condensed | RobotoCondensed | Oswald |
  | Technical | Sarpanch | Sarpanch |
  | Gotham | GothamSSm | GothamSSm |

  The `Enum.Font` weight decides the face: GothamBlack maps to the display face, Bold; Gotham, GothamMedium and GothamBold map to the body face as Regular, Medium and SemiBold.

## 14. Icons

- `Window:CreateTab(name, icon)`, `Paragraph.Icon` and `TelemetryCard.Icon` take **Lucide names**.
- Resolution order (`drawIcon`, L418-443):
  1. Lucide spritesheet (network or disk cache)
  2. the bundled atlas (18 names, only when `getcustomasset` exists)
  3. drawn polylines (22 names)
  4. the "activity" glyph as the final fallback
- **Numeric asset ids, which Rayfield accepts for tab images, render the activity glyph** **[probed]**.
- `"lock"` (used by `Lock`) and `"info"` are not in the bundled atlas.

---

## 15. Rayfield compatibility matrix

| Rayfield usage | Argon v1.18.3 | Status |
|---|---|---|
| `CreateWindow{Name, Theme, ConfigurationSaving{Enabled,FolderName,FileName}}` | supported | OK |
| `ToggleUIKeybind = "K"` (documented string form) | stored raw; comparing an EnumItem to a string never matches, so **neither K nor Insert toggles** **[probed]** | BROKEN (D1) |
| `LoadingTitle`, `LoadingSubtitle` | ignored. docs.L505 lists `LoadingTitle` as an option. | GAP |
| `Icon` (window), `ShowText`, `Discord`, `DisableRayfieldPrompts`, `DisableBuildWarnings` | ignored | GAP (cosmetic) |
| `KeySystem` / `KeySettings` | ignored: a key-gated script runs **ungated** | GAP (behavioural) |
| `Window:CreateTab(name, imageId)` | the number becomes `IconName = "4483362458"`, which renders the activity glyph | GAP |
| `Window.ModifyTheme(...)` | missing | GAP |
| `Rayfield:SetVisibility(bool)` / `Rayfield:IsVisible()` | missing on `Argon` (exists as `Window:SetVisibility`; no `IsVisible` anywhere) | GAP (calling it errors) |
| `Rayfield:Destroy()` / `LoadConfiguration()` / `Flags` | supported | OK |
| `Rayfield:Notify{Title, Content, Duration, Image}` | `Image` ignored; nothing shown before `CreateWindow`; default duration 4 (Rayfield examples use 6.5) | PARTIAL |
| `Tab:CreateSection(name)` then `Section:Set(name)` | `Set` missing | GAP (errors) |
| `Tab:CreateDivider()` then `Divider:Set(bool)` | missing | GAP (errors) |
| `CreateButton{Name, Callback}` then `Button:Set(name)` | missing (`SetTitle` exists) | GAP (errors) |
| `CreateToggle` / `Toggle:Set(bool)` | supported | OK |
| `CreateSlider{Range, Increment, Suffix, CurrentValue}` / `Set` | supported (no space before the suffix) | OK |
| `CreateInput{CurrentValue, PlaceholderText, RemoveTextAfterFocusLost}` / `Set` | supported; callback fires only on change; double callback with `RemoveTextAfterFocusLost` | PARTIAL (D13) |
| `CreateDropdown{Options, CurrentOption, MultipleOptions}` / `Set` / `Refresh` | supported; `Refresh` callback semantics differ | PARTIAL (D12) |
| `CreateKeybind{CurrentKeybind, HoldToInteract, Callback}` | `Callback` fires on **rebind**, not on press; press goes to `OnPressed`; `HoldToInteract` / `CallOnChange` ignored; restore runs `Callback(keyName)` | BROKEN (D3) |
| `CreateColorPicker{Color}` / `Set(Color3)` / `.Color` | `.Color` field missing | PARTIAL |
| `CreateLabel(text, icon, color, ignoreTheme)` / `Label:Set(text, icon, color)` | text only | PARTIAL |
| `CreateParagraph{Title, Content}` / `Paragraph:Set{Title, Content}` | `Set` with a table renders "table: 0x..." | BROKEN (D4) |
| Rayfield theme names (Default, AmberGlow, Bloom, DarkBlue, Green, Light, Serenity) | `SetTheme` returns false and the theme silently stays Argon (Amethyst and Ocean exist under the same names but look different) | GAP |
| Rayfield config files (`.rfld`, colours `{R,G,B}` 0-255) | read correctly except near-black colours (D25); Argon writes colours Rayfield cannot read | OK one way |

docs.L1290-1310 says "the rest of the script can stay as it is". The rows marked BROKEN and GAP show that this is not true for keybinds, paragraphs, sections, dividers, buttons, string toggle keys and key systems.

---

## 16. Contract defects (decide deliberately in v2)

Each item gives the evidence and the recommended v2 decision. **Keep** means v2 must reproduce the v1 behaviour. **Fix** means change it, with a compat note in the changelog.

1. **D1: string `ToggleUIKeybind` breaks visibility toggling.** L1385 stores the option raw and L3097 compares `input.KeyCode == window._toggleKey`. **[probed]** With `"K"`, neither K nor Insert toggles the window. Combined with the "–" hide button (L3093), the window can then never be reopened. **Fix:** normalise through the `SetToggleKey` logic (L1398); accept a string, an EnumItem, or `"Enum.KeyCode.X"`.
2. **D2: `PlayerList=false` / `KeybindList=false` are ignored.** `window:_applyUIPreferences(savedPreferences)` (L1537) runs with an empty table and sets `_playerListEnabled = (nil ~= false) = true` (L1527). **[probed]** Both overlays appear even when the options are false. **Fix:** a saved preference overrides only when it is present; otherwise fall back to the option.
3. **D3: Keybind Callback semantics.** Press goes to `OnPressed`/`Pressed` (L2442), while `Callback` fires on rebind (L2426) and on every restore (L878-885). **[probed]** A Rayfield action callback never runs on keypress but does run once at startup. **Fix:** v2 adds `OnChanged` for rebinds. When a config has `Callback` but neither `OnPressed` nor `CallOnChange`, `Callback` is treated as the press handler (Rayfield semantics). Implement `HoldToInteract` (`Callback(true/false)` while held). A restore must not invoke a press handler.
4. **D4: Paragraph and Label `Set` signatures.** `Paragraph:Set(table)` and `CreateLabel(table)` render "table: 0x..." (L2563, L2257). **[probed]** **Fix:** `Paragraph:Set({Title, Content})` updates both; `Label:Set(text, icon, color)`; `CreateLabel` accepts `{Text|Title|Name}`.
5. **D5: missing Rayfield methods and fields.** `Section:Set`, `Divider:Set(bool)`, `Button:Set(name)`, `ColorPicker.Color`, `Argon:SetVisibility` / `Argon:IsVisible`, `Window.ModifyTheme`, numeric tab image ids, and the `Notify` `Image` key. **Fix:** add all of them; they are cheap.
6. **D6: `OnFlagChanged` unbind is index-based.** L960-963 captures `#_flagListeners` when subscribing. **[probed]** After `u1(); u2()` the second listener keeps firing. **Fix:** remove by identity, as `OnThemeChanged` already does (L692-696).
7. **D7: `SetVisible(false)` is overwritten** by `_filter` (L1736), which `_select` calls on every tab switch (L1690). **[probed]** The element reappears after a tab switch or after the search is cleared. **Fix:** keep a separate `_hidden` state and AND it with the search match.
8. **D8: `Destroy` leaks contract state.** The element stays in `Argon.Flags` (it is still saved and `GetFlagValue` returns a stale value), it is not removed from `row.Elements`, and its global `UserInputService` handlers stay connected. **[probed]** A destroyed keybind's hotkey still fires `OnPressed`. **Fix:** unregister the flag (move its last value to pending), and give each element its own connection cleanup list (a maid).
9. **D9: `CreateWindow` replaces global state.** L1223-1227 assigns a new `Flags` table, clears pending values, closes the persistence gate and swaps the configuration. A second window drops the first window's flags, and a script that cached `Argon.Flags` holds a stale table. `Notify`, `SaveConfiguration`'s `__argon` and the autosave all target the last window. The test suite depends on this (run.L1531 comment, L913, L915). **Decide:** keep single-configuration semantics, but clear in place (`table.clear`) so references stay valid, and document that only one window is supported. Alternatively, make configurations per window and update the tests.
10. **D10: `LoadConfiguration` reports failure for the deferred-hydration pattern.** When every stored flag is merely pending (load called before the UI is built), it returns `false` and sets `LastError` (L1113-1116), while the values do hydrate later. **[probed]** A missing file also returns `false`. **Fix:** return `true` plus info in both cases, keeping a distinguishable reason string.
11. **D11: the loader watchdog counts from `CreateWindow`.** L3365. **[probed]** A host that reports progress steadily for 35 s is uncovered at 30 s, mid-build. **Fix:** reset the 30 s deadline on every `SetLoadingProgress`.
12. **D12: `Dropdown:Refresh` bypasses the commit path.** Dropping the selection fires no callback, listener or autosave; applying a desired option fires the callback but no listener or autosave (L2490-2508). **[probed]** **Fix:** route through a single commit function; decide whether Refresh fires (Rayfield does not fire callbacks on Refresh).
13. **D13: `RemoveTextAfterFocusLost`** fires `Callback("text")` and then `Callback("")`, and persists `""` (L2400-2401). **[probed]** **Fix:** clear the box without calling `Set("")`, so the callback fires once and `CurrentValue` keeps the submitted text (Rayfield behaviour). Alternatively, never persist this field.
14. **D14: inconsistent `Set` returns and coercion.** Toggle, Slider, Keybind, Dropdown and ColorPicker return nil; the other controls return self. Toggle uses `== true`. **Fix:** every `Set` returns self.
15. **D15: `Tooltip`/`Description` ignored** on Label, Paragraph, TelemetryCard, Divider and Space (`base` gets no config, L2258, L2553, L2570, L2608, L2619). On Paragraph and TelemetryCard, `Description` is an alias for **content**. **Keep the alias** (scripts rely on it); **fix** Tooltip for these controls.
16. **D16: a topbar theme pick is not persisted** without the library-settings tab. `chooseTheme` (L3024-3031) calls `Argon:SetTheme`, which never schedules a save. **[probed]** **Fix:** schedule a save from the picker, or from `Argon:SetTheme` when it is called from the UI.
17. **D17: the janitor dies after `Destroy`.** `schedulePrune` returns without rescheduling when `_destroyed` is set (L262-266), and `CreateWindow` does not restart it. **[probed]** **Fix:** restart it from `CreateWindow`, or use one long-lived Heartbeat budgeted sweep.
18. **D18: closing a Confirm with x skips `OnCancel`** (L1589, L1617, L1645). **Fix:** treat x and Escape as cancel.
19. **D19: `Notify` before `CreateWindow` returns nil silently** (L1147-1148). **Fix:** create the notification layer lazily on its own ScreenGui at first `Notify`, as Rayfield does.
20. **D20: duplicate warnings and global input listeners.** Every Slider, ColorPicker popup, overlay and keybind connects its own `UserInputService.InputChanged`/`InputEnded`/`InputBegan` listener, and these are never released until `Destroy`. This belongs in the performance audit, but `Destroy` and `element:Destroy` semantics depend on it. **Fix:** use one shared input router.
21. **D23: `SetTheme(table)` persists as "Custom"**, which cannot be restored (L627, L1522). **Fix:** register the table under a stable name, or persist the palette itself.
22. **D25: colour interop ambiguity.** `{R=1, G=0, B=0}` from a Rayfield file (0-255 scale) is read as 0-1, so it becomes pure red instead of near-black (L860). **Fix:** treat files without `__argonColor` as 0-255.
23. **D26: Lock is visual only.** `Set`, `SetFlagValue`, restores and keybind hotkeys still act on a locked control. **[probed]** **Decide and document.** Recommended: block user input paths (including hotkeys) but allow programmatic `Set`.
24. **Dead or misleading fields.** `Argon.AssetFolder` (unused). `Argon._librarySettingsCreated = nil` in `Destroy` (L1139) is dead, because the flag lives on the window. `Window:Toggle` (visibility) and `Tab:Toggle` (create a toggle) share a name.

---

## 17. Test-suite dependencies (`tests/run.luau`)

### 17.1 Behaviours asserted (grouped)

The sandbox file is listed in 17.3.

- **Load and identity:** the library loads; `Version == "1.18.3"`; `Flags` is a table; `DefaultFolder == "ArgonUI"` (run.L37-46).
- **Window, tab and section:** `CreateWindow` with `GuiName` names the ScreenGui; `CreateTab` and `CreateSection` succeed (run.L48-67).
- **Controls:**
  - Toggle stores its value and fires its callback.
  - Slider rounds to the increment (43 becomes 45 with step 5) and clamps high.
  - Input stores text.
  - Dropdown selects, and an unknown option is "ignored" (weak assertion).
  - Keybind stores the key.
  - ColorPicker parses hex.
  - Button, Label, Paragraph, Divider and Space report their `Type`.
  - `Telemetry:SetContent` works (run.L69-113).
- **Newer components** (run.L115-161):
  - ProgressBar: `Set`, `Increment`, clamp at `Maximum`, `SetRange` keeps the value, `SetColor`.
  - Stepper: initial value 0.45, `Set(1.23)` gives 1.25, clamps to the minimum, fires its callback.
  - Segmented: initial value, `Set`, the callback receives a string, unknown values are rejected, `Refresh` keeps a valid value or resets to the first option.
  - TextArea: `GetLines` skips blank lines.
  - List: strings are normalised; `AddItem` and `Clear` work.
- **Section builders** expose ProgressBar, Stepper, Segmented, TextArea, List, Label, TelemetryCard and Toggle, and `section:Toggle` builds (run.L163-169).
- **Rows** (run.L171-305):
  - Builders return `Columns`; the shorthands exist; distribution is round-robin; column `LayoutOrder` is 1 then 2; the third control wraps to column 1.
  - Row controls work and register their flags; they join the section's `Elements` and the tab count.
  - `Columns` is clamped to 4 and 1; `Use(3)` works; a bare number works; `Section:Row` works.
  - Search hides a row with no matches, keeps a row with one match, and restores everything when cleared.
  - Line heights are equalised and idempotent; a lone control keeps 54 px.
  - `_relayout` does not re-enter itself and settles on one size.
  - Row controls follow a theme switch.
- **State-driven colours** (run.L307-351): toggle tracks keep Accent or Input through theme switches and silent restores; the colour picker keeps the user's colour.
- **Descriptions** (run.L353-400): the slider row grows past 72 px; the description sits below the track and fits inside the row; the toggle track is pinned into its band (scale 0); clearing the description shrinks the row.
- **List actions** (run.L402-453): three buttons in build order with no overlap; the danger tint differs; each button runs its own callback; the legacy `Action` string still works.
- **Tooltips** (run.L455-558):
  - `Tooltip` and `Tip` are accepted; a tooltip costs no row height and creates no `_description`; `SetTooltip` can update.
  - The 0.28 s delay holds (no tooltip at 0, one at 0.35 s), the tooltip is wrapped, uses offset positions, is `Active == false`, does not follow the pointer, closes on leave, an empty tooltip shows nothing, and leaving before the delay cancels it.
  - The "?" marker exists, `HasTooltip` is set, an untipped control has no marker, the marker is parented to `Root`, stays within the title's space, and hides when the tooltip is cleared.
- **Locks** (run.L560-595): `Locked`, `LockReason`, `_lock.Badge`, `_lock.Icon`; locking again keeps the same scrim; the UISizeConstraint has max ≥ min; the scrim is translucent; `Unlock` clears all of it; `SetLocked` works.
- **Confirm** (run.L597-661): two buttons, "Cancel" then "Confirm"; confirm runs and cancel does not; it fires once on a double click; custom texts work; the transient dialog is removed after 0.4 s; the danger tint differs.
- **Element helpers** (run.L663-670): `SetDesc`, `SetTooltip`, `Lock`, `Unlock`, `SetVisible` and `Destroy` do not error.
- **Configuration** (run.L672-763):
  - Save writes `TestHub/config.rfld`, with the toggle, stepper, segmented and textarea values; the ProgressBar is not persisted.
  - Load restores and fires callbacks; a callback fires for an unchanged default.
  - Unknown flags are retained; a late control hydrates and fires its callback; an orphan survives save.
  - A dropdown's deferred selection is applied on `Refresh` and fires its callback.
  - `OnFlagChanged` fires and unbinds (single listener only); `SetFlagValue`; `GetFlags`.
  - Stats report `Path`, `Ready` and `RegisteredFlags >= 8`.
  - `ResetConfiguration` removes the file and clears pending flags.
- **Custom extension:** `settings.json` is not double-appended (run.L765-779).
- **Themes** (run.L781-831): 10 built-ins; Amethyst differs from Argon; `SetTheme`, `AddTheme`, `GetColor` and its fallback, a detached `GetPalette`, `OnThemeChanged` fire and unbind; a recoloured control follows the next theme.
- **Theme picker** (run.L832-887): the panel starts closed; Toggle opens it; one swatch per theme; swatches show their own palettes; picking switches the theme; the active swatch is outlined; an external switch restyles the picker; Toggle closes it; `SetThemePickerVisible` false/true.
- **Misc:** `Notify`, `Dialog` and `CreateLibrarySettings` run; window controls (`Close`/`Open`, `SetTitle`/`SetLogo`, overlay setters, `SetSize`) do not error (run.L889-909).
- **Autosave gating and debounce** (run.L911-929): a new window is gated (`Ready == false`, no write at 0.4 s); it self-enables by 5 s; writes are debounced (none immediately, one after 0.4 s) with the current value.
- **Overlays** (run.L931-958): visible when open, hidden with the window, pinned stay visible, `AreOverlaysAlwaysVisible`, toggling while hidden, reopening, export and apply of preferences.
- **Active tab theming** (run.L960-991): the active `IconBox` is Accent and repaints; the title is Text; inactive tabs are Active.
- **Text growth** (run.L993-1032): Label, Paragraph and Telemetry have AutomaticSize Y roots and a wrapped AutomaticSize Y body; `Label:Set`; the status pill has AutomaticSize X; `SetStatus` recolours the text and stroke.
- **Input elision** (run.L1034-1067): the full value is stored; the display is elided, keeps head and tail and drops the scheme; focus restores the full text; blur commits and re-elides; short values are shown whole; a silent `Set` updates the display.
- **Notifications** (run.L1069-1116): the layer is parented to the ScreenGui and stays visible when the window is hidden; a toast is built while hidden; AutomaticSize Y; severity tint on the 32x32 plate; the stack is capped at 5.
- **Jump rail** (run.L1118-1166): exists; hidden with one section; shown with more; one chip per section in order with the exact section name; ScrollingDirection X; hidden while filtering; no "SECTIONS" button.
- **Typography** (run.L1168-1214): labels and button labels have a Roboto `FontFace`; section headers use Montserrat; `SetFont("Ubuntu")` repaints and switching back restores; an unknown font is refused; `GetFonts` has Roboto and not Inter.
- **Loader** (run.L1216-1314):
  - Starts covered; progress holds it past 2 s; progress is monotonic (`_loadingProgress >= .8`).
  - `FinishLoading` uncovers it and is idempotent; a silent host opens by 2 s; `Loading = "manual"` holds for 3 s.
  - The pill is narrower than 400 px during the build; overlays stay hidden (vacuous, see 17.4); the shell is wider than 400 px after finishing.
  - A viewport change does not stretch the pill; the final width is 772 for an 800 px viewport.
- **Restore progress** (run.L1316-1357): at least 12 `"RESTORING CONFIGURATION i/n"` reports for 12 flags; final progress in (.98, 1); `_lastConfigStats` applied == total and failed == 0.
- **Composition** (run.L1359-1437): no CanvasGroup carries its own UIGradient; `Main` is a Frame with a UIGradient; `PageGroup` is a Frame; `Loader` is a Frame; the sidebar has a UICorner and a 16 px `SquareEdge`; `SetSize` switches the sidebar 232 → 72 → 232; the only CanvasGroup is `Glow`; Mono has no tinted group.
- **Rename** (run.L1439-1502): host name and subtitle are used; `SetTitle` trims; `SetSubtitle`; the stored subtitle keeps its case and the display is upper-cased; an empty value restores the default; `Title` and `Font` are exported; a saved rename shows on the loader before load; the library-settings panel registers `ArgonUIWindowTitle`, `ArgonUIWindowSubtitle` and `ArgonUIFont`.
- **Cursor** (run.L1504-1528): a separate `CursorGui` with a higher `DisplayOrder` and `IgnoreGuiInset`; `Cursor = false` opts out; `SetCursorVisible(false)` sets `_cursorMode = false`; `SetCursorVisible()` sets `"auto"`.
- **Theme picker opt-out** (run.L1530-1539).
- **Registry pruning** (run.L1541-1596): transient toasts leave dead bindings; `PruneRegistries` drops them and reports `stats.bindings > 0`; no connection has `Connected == false`; a second pass drops nothing; a theme switch still repaints after pruning; the janitor runs within 31 s.
- **Hygiene** (run.L1598-1606): no `warn()` apart from "unknown/retired flag" and "Duplicate configuration flag"; no errors in signal handlers.

### 17.2 Internals and structure the tests reach into

v2 must either keep each of these or change the test on purpose.

**Library internals**

| What | Tests | Expectation |
|---|---|---|
| `Argon.Version` | L44 | `"1.18.3"`; must be updated to the v2 version |
| `Argon.DefaultFolder` | L46 | `"ArgonUI"` |
| `Argon.Themes.<T>.<Key>` | many | palette tables keyed by theme, then by colour key |
| `Argon.CurrentTheme` / `Argon.CurrentFont` | L860, L1209, L1426, L1488 | strings |
| `Argon._pendingFlags` | L763 | empty after `ResetConfiguration` |
| `Argon._windows` | L1072, L1349 | array; the last entry is the newest window |
| `Argon._lastConfigStats` | L1354 | `{applied, total, failed}` |
| `Argon._uiPreferences` | L1321, L1442, L1481, L1489 | assignable; read by `CreateWindow` (`Title`, `Subtitle`, `Font`) |
| `Argon._themeBindings` | L1548-1577 | array of `{Object=Instance}`; **grows** with transient UI; pruning removes entries whose `Object.Parent` is nil |
| `Argon._connections` | L1568 | array of connections with a `.Connected` field |
| `Argon._lastPruneStats` | L1592-1595 | set by the janitor within 31 s |
| `Argon:PruneRegistries()` | L1547, L1559, L1576 | returns a table with `.bindings` |
| `Argon.Flags.<flag>` | L197, L915, L1499-1501 | the element object (identity comparison) |

**Window internals**

| What | Tests | Expectation |
|---|---|---|
| `ScreenGui` (`Name`, children, descendants) | many | |
| `Main` | L1257, L1283, L1381, L1384 | `.Size.X.Offset`, `ClassName == "Frame"`, a UIGradient child |
| `Sidebar` | L1399-1413, L1459 | UICorner, `SquareEdge`, width 232 or 72, a descendant label with upper-cased text |
| `Content.TopBar.ThemeButton` | L879, L884, L1535 | |
| `Content.ThemePicker.ThemeOptions.<ThemeName>` | L833-886 | a TextButton per theme holding a UIStroke and Frame dots |
| `Content.JumpRail` | L1121-1159 | holds a ScrollingFrame with TextButton chips (`LayoutOrder`, `Text`) |
| `TopBar` | L1161 | must not contain a TextButton with text "SECTIONS" |
| `Notifications` | L1074-1115 | `Parent == ScreenGui`, `Visible`, CanvasGroup children |
| `PlayerListOverlay` / `KeybindListOverlay` | L939-952 | `.Visible` |
| `CursorGui` | L1509-1515 | `DisplayOrder`, `IgnoreGuiInset` |
| `Tabs`, `ActiveTab` | | |
| `_tooltip` | L479-527 | the live tooltip instance or nil; has a TextLabel child; offset-only `Position`; `Active == false` |
| `_loadingProgress` | L1230, L1350 | number |
| `_cursorMode` | L1523, L1527 | `false` or `"auto"` |
| `_playerOverlayVisible` | L1266 | read but never asserted |
| `_select(tab)`, `_refreshSectionMenu()` | L1124, L1131, L1166 | callable |
| `_exportUIPreferences()` | L955, L1473 | returns `{OverlaysAlwaysVisible, Title, Font}` |
| `_applyUIPreferences(t)` | L957 | callable |
| `SetLoadingProgress` | L1335-1341 | **monkeypatched as a table field**: `LoadConfiguration` must call `loader:SetLoadingProgress(...)` through the window table, and must choose the loader by `_loading` |

**Tab internals**

| What | Tests | Expectation |
|---|---|---|
| `_sections[i].Elements` | L199 | array |
| `_controlCount` | L204 | ≥ 4 |
| `_filter(q)` | L224-233, L1155 | callable |
| `IconBox.BackgroundColor3` | L969-988 | Accent when active, Active when inactive |
| `ButtonTitle` | L980, L1170, L1200, L1583 | `TextColor3` and `FontFace.Family` |
| `Page` descendants | L1193 | |
| `PageGroup.ClassName` | L1387 | `"Frame"` |

**Row internals**

| What | Tests |
|---|---|
| `Columns` (count; `[i].Holder`) | L177, L208, L214 |
| `Root` | L181-233, L277-296 |
| `_balance()` | L242-263 |
| `_relayout()` | L281-295 |
| Holder `LayoutOrder` | L185 |
| `element.Root.Parent` is the holder; `holder.Parent` is `row.Root` | L180-221 |

**Element internals**

| What | Tests |
|---|---|
| `Root` (`Size`, `Visible`, `BackgroundColor3`, `AutomaticSize`, children, descendants, `MouseEnter`/`MouseLeave` signals) | many |
| `_description` | L362-400, L465 |
| `_tooltipText` | L462-475 |
| `_tipMarker` (`Text "?"`, `Visible`, `Parent`, `Position`, `Size`) | L531-557 |
| `_title` (`Position`, `AbsoluteSize`) | L544 |
| `HasTooltip`, `Locked`, `LockReason` | |
| `_lock.Root`, `_lock.Badge` (UISizeConstraint child), `_lock.Icon` | L570-588 |
| `Type`, `CurrentValue`, `CurrentOption`, `CurrentKeybind`, `Items`, `Status` | |

**Pinned geometry and structure.** Any visual redesign breaks these unless the tests are rewritten.

| Pinned value | Tests |
|---|---|
| Toggle track found as a Frame of exactly 44x24 | L318, L386 |
| Toggle row height 54 | L265 |
| Slider natural height 72 | L362 |
| Slider bar is an `Active` Frame of height 8 | L367 |
| List rows with a description are 44 px; action TextButtons are ordered by `Position.X.Offset` | L417-438 |
| Notification severity plate is a 32x32 Frame | L1106 |
| Notify returns a CanvasGroup with AutomaticSize Y | L1099 |
| Sidebar is 232 / 72 px; `SquareEdge` is (0,16,1,0) | L1401-1413 |
| Shell width is viewport − 28 (772 at 800) | L1313 |
| Pill is narrower than 400 px | L1259, L1286, L1302 |
| Section header text is upper-cased (`"LOOK AND FEEL"`) | L1194 |
| Confirm buttons are found by `Text`; "×" is excluded | L602 |
| The only CanvasGroup is named `Glow` | L1421 |
| The loader is a Frame named `Loader` | L1392 |

**Timings pinned by `sandbox.advance`**

| Timing | Tests |
|---|---|
| Autosave debounce < 0.4 s | L926 |
| Persistence fallback < 5 s | L919 |
| Tooltip delay between 0 and 0.35 s | L476-490 |
| Dialog teardown < 0.4 s | L648 |
| Non-manual loader opens < 2 s | L1239 |
| Janitor period < 31 s | L1594 |
| Reveal sequence < 1.5 s | L774, L1285 |

**Global-state reliance.** The suite builds about 20 windows and depends on `CreateWindow` resetting `Flags` and the persistence gate. It runs the opt-out window last on purpose (comment at run.L1531). Section 16 D9 covers this.

### 17.3 Sandbox semantics v2 must respect, or extend the sandbox for

`tests/sandbox.luau` behaves differently from a real client in these ways:

- **Scheduling and services**
  - `task.spawn` and `task.defer` run **synchronously** (sb.L709-716). `task.wait` returns immediately.
  - `task.delay` is queued and runs only through `sandbox.advance`. Delays scheduled from inside an `advance` are not run in that same call (sb.L728-738).
  - `TweenService:Create():Play()` applies the goals instantly (sb.L549-559).
  - `HttpGet` returns `""`, so the Lucide index never loads and `loadstring` is never reached.
  - There is no `getcustomasset`, so the atlas and logo paths are skipped.
- **Instances**
  - Any class name and any property work, so typos in property names are invisible.
  - `IsA` knows only the class's own name and `GuiObject`/`GuiBase2d` for 8 classes (sb.L252-263). `IsA("GuiButton")` and `IsA("TextBox")` on a subclass return false.
  - `AbsoluteSize` is the offset size when the Size is offset-only, otherwise 980x660. `AbsolutePosition` is always (0,0).
  - `Destroy` sets `Parent = nil` on the root only: descendants keep their parent, and connections are never disconnected. The "dead connections" test is therefore trivially true.
- **Signals**
  - `Signal.Once` behaves like `Connect` (it never auto-disconnects) and `Signal:Wait` returns nil.
- **Enums and type checks**
  - Unknown members return nil instead of erroring (sb.L86-93). `Enum.EasingStyle.Quart`, `Cubic`, `Circ`, `Elastic` and `Bounce` are all **missing**, and the library's default `Quart` becomes nil silently. `Enum.KeyCode` has only 44 keys.
  - `typeof(ColorSequence)` returns `"table"`, so gradient theme bindings never register in tests.
- **JSON**
  - `JSONEncode` sorts keys and uses `%d` for integral numbers.
- **Consequence for v2**
  - New Roblox APIs (UIFlexItem, `GuiObject.Interactable`, `TextService:GetTextBoundsAsync`, `Instance:AddTag`, `RunService:BindToRenderStep` with real ordering, and so on) need sandbox support before tests can exercise them.

### 17.4 Weak or vacuous tests (fix when touching them)

- **run.L1261-1276, "overlays stay behind the cover".** It looks for ScreenGui children named `PlayerOverlay`/`KeybindOverlay`. Nothing has those names (the overlays are unnamed Frames, **[probed]**), so `hidden` is always true. It should read `held.PlayerListOverlay.Visible`.
- **run.L93.** It accepts either outcome for an unknown dropdown option. v1 actually clears the selection and fires `Callback({})` **[probed]**.
- **run.L1566-1573, "dead connections dropped".** Always true, because sandbox connections never disconnect.
- **run.L738-744.** Covers a single listener only, so it misses D6.
- **run.L663-670, "element helpers".** These only check that the calls do not error.
- **Missing coverage:** no test exercises keybind press semantics, `RemoveTextAfterFocusLost`, `SetVisible` persistence, `Destroy` cleaning `Flags`, `ToggleUIKeybind` strings, `PlayerList = false`, `Notify` without a window, or the watchdog under steady progress.

---

## 18. README and docs compared with the implementation

### Documented but not implemented, or wrong
- README L42 says the whole UI uses BuilderSans. The code default is **Roboto body plus Montserrat display** (L493-514), and BuilderSans is one of six selectable sets. docs.L1358 repeats the BuilderSans claim, which contradicts docs.L1331.
- docs.L505 lists the `LoadingTitle` window option. **It is not implemented** (nothing reads it).
- docs.L517 says "Drag the window edges to resize". There is only a bottom-right corner grip (L3075).
- README L139 says a host "that reports but forgets `FinishLoading` is opened by a watchdog after 30 seconds". The watchdog counts from `CreateWindow` regardless of reports (D11).
- README L44 says "no operating-system glyph fallback". Several controls draw text glyphs instead of vector icons: "→" (Button, L2275), "–" (hide, L1341), "×" (dialog close, L1589), "-"/"+" (stepper and overlay collapse) and "?" (tooltip marker).
- README L246 implies `GetIcon` falls back to the bundled atlas. `GetIcon` returns nil offline; only `drawIcon` falls back.
- docs.L1290-1310 claims a drop-in Rayfield migration. See the BROKEN and GAP rows in section 15.

### Implemented but not documented in the README (the docs site covers some)
- **Window options:** `Subtitle`, `Font`, `ScreenGuiName`, `Loading = "manual"` / `ManualLoading` (essential for big hosts, and missing from the README example), `PlayerList`, `KeybindList`, `OverlaysAlwaysVisible`, `FileExtension`.
- **Library:** `SaveConfiguration`, `SetPersistenceReady`, `DeleteConfiguration`, `GetFlags`, `Destroy`, `SetFont`, `GetFonts`, `GetFontLabel`, `CurrentFont`, `GetThemes`, `CurrentTheme`, `HasIcon`, `PruneRegistries`, `Version`, `DefaultFolder`.
- **Window:** `SetVisibility`, `ToggleVisibility`, `Open`, `Close`, `Toggle`, `SetToggleKey`, `SetTitle`, `SetSubtitle`, `GetTitle`, `GetSubtitle`, `SetLogo`, `SetFont`, `SetTheme`, `GetThemes`, `SetSize`, `SetPlayerListVisible`, `SetKeybindListVisible`, `SetOverlaysPinned`, `AreOverlaysAlwaysVisible`, `SetOverlayTransparency`, `SetOverlayScale`, `SetSmoothTransitions`, `ResetOverlayPositions`, `Dialog`, `Popup` (buttons, variants, `AutoClose`, `Transient`, `Show`), `IsLoading`, `IsCursorDrawn`.
- **Confirm keys:** `CancelText`, `OnCancel`, `Variant`, `Callback`, `Description`.
- **Elements:** `SetTitle`, `SetVisible`, `Destroy`, the `Tip`/`Desc` aliases, the `Locked`/`LockReason`/`HasTooltip` fields, `Keybind` `OnPressed`/`Pressed`/`Toggle`/`Active`/`DisplayInKeybindList`/`SetActive`/`SetOverlayVisible`, `Dropdown:SetOptions`/`GetSelected`, `ProgressBar` `Format`/`ShowValue`/`SetRange`/`SetColor`/`Increment`, `TelemetryCard` `Status`/`Accent`/`SetStatus`, `List` `Height`/`EmptyText`/`Callback(record,item)`/string actions/`record.Color`, `TextArea` `Height`/`GetLines`, `Segmented` `Refresh`, `Row` `Name`.
- **Persistence details:** the `.rfld` default, the reserved `__argon` key, the 13 `ArgonUI*` flags, the restore order (booleans last), the 0.35 s debounce and the 4 s gate fallback.
- **`CreateLibrarySettings`** also adds the rename fields, the typeface picker, the overlay hotkeys, opacity and scale sliders, and a reset-positions button. The README lists only "theme, overlay, pin, logo, and transition".

### Tests README
- Says "All 18 controls". The count matches (README L49-56). Rows are an extra layout primitive on top of those 18.

---

## 19. Recommended contract decisions for the v2 implementers (summary)

1. **Freeze** every public name and alias in sections 1-14, including the lowercase-p `Colorpicker`, `Popup`, `SetOverlaysPinned`, `Tip`, `Desc` and the Content/Description aliases. Keep every per-control persisted value format, so a v1 `.rfld` loads unchanged in v2. Keep `__argon`.
2. **Fix, with a changelog note:** D1-D8, D10-D13, D16-D19 and D25. Each one is cheap, and each makes Rayfield scripts and README examples behave the way the docs already claim.
3. **Decide explicitly:** D9 (single vs per-window configuration; at minimum `table.clear` instead of replacing `Argon.Flags`), D12 (whether `Refresh` fires callbacks) and D26 (what Lock blocks).
4. **Expose public diagnostics** (`Argon:GetDiagnostics()` returning counts of bindings, connections and controls plus the last prune result) and a public `Window:SelectTab(tab)` / `Tab:Select()`. The tests can then drop most of the `_themeBindings`, `_select`, `_filter` and `_lastPruneStats` coupling.
5. **Rewrite the pinned-geometry tests** (section 17.2) as behaviour tests before the visual redesign lands: "the track is the Accent colour" instead of "find a 44x24 Frame". Otherwise every pixel change in v2 shows up as a test failure.
6. **Extend the sandbox:**
   - full EasingStyle and KeyCode enums;
   - `IsA` hierarchy;
   - `Destroy` that clears descendants and disconnects;
   - deferred `task.defer`;
   - a fake `HttpGet` with a latency counter, so a network call on the critical path becomes a test failure;
   - an optional `getcustomasset`.
