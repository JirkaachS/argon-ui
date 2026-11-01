# Argon UI v2 audit: display controls, interaction system, themes, notifications, config UX

Area: Label, Paragraph, TelemetryCard, ProgressBar, List, Section, Row, Divider, Space; descriptions, tooltips, locks, SetVisible; Dialog/Confirm; Notify; theme system and picker; fonts; per-tab search and jump rail; CreateLibrarySettings; configuration UX.

Source: `argon-ui.luau` v1.18.3 (read-only; line numbers below refer to it).
Evidence scripts (all runnable, nothing in the repo was touched):

- `bench/controlsB_contrast.py` (WCAG 2.x contrast of every palette, parsed straight from the source) -> `bench/controlsB_contrast.json`
- `bench/controlsB_probe.luau` (runs the real library in the repo's Lune sandbox with a stubbed Lucide index) -> `bench/controlsB_probe.out.txt`
- `bench/controlsB_probe2.luau` (theme picker, row balance) -> `bench/controlsB_probe2.out.txt`

Sandbox timings are relative only (the sandbox Instance is a Lua metatable); instance/connection/binding counts are exact.

---

## 1. Summary

1. **Visibility is not a state, it is a side effect.** `element:SetVisible(false)` is undone the next time the tab is selected or the search box is cleared, because `_filter` writes `Root.Visible` for every element (l.1730-1749, called from `_select` l.1690). Every "show sub-options only when X is on" menu is broken. Search also only matches control titles and shows a blank page when nothing matches.
2. **The palettes look flat and fail contrast.** Dim (descriptions, placeholders, captions) is 3.1-4.2:1 on its surface in all 10 themes. White ink on Accent (selected segment, toggle knob, active tab icon, primary dialog button) is 1.29-3.43:1 in all 10 themes. Mono is 1.29:1, so the selected segment and primary buttons are unreadable. Card, hover, border and toggle-off track deltas are 1.05-1.28:1, which is why the UI reads as murky and why state changes are hard to see. There are only 18 tokens: no OnAccent, Info, Overlay, Focus or Disabled. There is no light theme.
3. **Preferences have two sources of truth and are applied too late.** Theme, font and title are saved both in `__argon` and as `CreateLibrarySettings` flags. A theme or title set through the public API reverts on the next launch (probe: Ocean -> Argon). Prefs are only applied by `LoadConfiguration`, after the whole UI is built. So every launch repaints every binding twice (2 x `SetTheme`), and the loader always shows the default title, contrary to the comment at l.1236.
4. **Notifications are guesswork.** Severity comes from title keywords: "Incomplete download" -> success, "Unsaved changes" -> success, "No errors found" -> danger. `Type`, `Image`/`Icon`, `Actions` and click callbacks are ignored. The call returns a raw CanvasGroup with no Update or Dismiss. There is no hover-pause, de-dupe or length-aware duration. Each toast costs 26 instances. Notifications sent before `CreateWindow` are dropped.
5. **Rayfield source compatibility breaks in this area.** `Paragraph:Set({Title,Content})` renders `table: 0x...`. `Section:Set` and `Divider:Set` do not exist, so they throw. Label icon and colour arguments and Notify `Image` are ignored.
6. **Quadratic paths that hit load time:** `List:AddItem` rebuilds and deep-copies every row (150 adds = 90,600 instances / 67,950 connections vs 1,200 / 900 for one `SetItems`). The jump rail is rebuilt on every `CreateSection` of the active tab (16 sections = 135 chips built). The theme picker is rebuilt on every open (130 instances), and one pick runs `SetTheme` twice.
7. **The interaction layer is mouse-only and leaky.** Tooltips are hover-only, stay on screen after the window is hidden, and are rebuilt on every hover. Lock is purely visual: a locked Keybind still fires its hotkey. Dialogs have no Esc, Enter or outside click. The X button skips `OnCancel`. The dialog text is drawn on the bare scrim while the panel grows (no ClipsDescendants). There is no on-screen reopen once the window is hidden, so a phone user who presses "-" is stranded.
8. **No configuration UX exists for end users.** There is one file, with no profiles, import/export, reset UI, save status, per-control reset, or rebindable/persisted menu key (Insert only, which many laptops lack).

What is good and should be kept: the self-sizing text controls (AutomaticSize + UIListLayout), the tooltip placement logic (beside the row, flips sides), the three-tier lock badge, the idempotent Confirm, `registerThemeRender` for state-driven objects, `OnThemeChanged`/`GetColor`/`Palette` for host frames, Row's collapse-to-stack threshold, and `PruneRegistries`.

---

## 2. Measurements

### 2.1 WCAG contrast per theme (bench/controlsB_contrast.py)

Text targets: 4.5:1 (AA, body/small). Non-text component and state targets: 3:1 (WCAG 1.4.11). Hover/Surface and Surface/Window are not WCAG items. They are listed to show how weak the elevation steps are.

| Theme | Text/Surface | Muted/Surface | Dim/Surface | Dim/Hover | Dim/Input | White/Accent | White/Danger | BorderSoft/Surface | Input/Surface | Hover/Surface | Surface/Window |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Argon | 16.15 | 6.62 | 3.32 | 3.12 | 3.47 | 3.43 | 2.84 | 1.16 | 1.05 | 1.06 | 1.06 |
| Midnight | 16.40 | 6.77 | 3.08 | 2.87 | 3.26 | 2.53 | 2.84 | 1.18 | 1.06 | 1.07 | 1.07 |
| Emerald | 16.36 | 7.18 | 3.58 | 3.30 | 3.81 | 1.92 | 2.84 | 1.24 | 1.06 | 1.08 | 1.08 |
| Rose | 16.42 | 6.90 | 3.23 | 3.01 | 3.38 | 2.65 | 2.84 | 1.17 | 1.05 | 1.07 | 1.06 |
| Amethyst | 15.57 | 7.47 | 3.66 | 3.32 | 3.88 | 3.35 | 2.66 | 1.21 | 1.06 | 1.10 | 1.08 |
| Slate | 15.15 | 6.84 | 3.47 | 3.11 | 3.69 | 1.87 | 2.73 | 1.21 | 1.06 | 1.11 | 1.09 |
| Ember | 16.13 | 7.64 | 3.83 | 3.54 | 4.03 | 2.34 | 2.81 | 1.19 | 1.05 | 1.08 | 1.07 |
| Nord | 9.85 | 5.85 | 3.24 | 2.70 | 3.66 | 2.00 | 4.09 | 1.22 | 1.13 | 1.20 | 1.19 |
| Mono | 16.13 | 6.75 | 3.41 | 3.13 | 3.60 | 1.29 | 2.67 | 1.18 | 1.06 | 1.09 | 1.07 |
| Ocean | 15.23 | 7.29 | 3.80 | 3.39 | 4.07 | 2.24 | 2.69 | 1.28 | 1.07 | 1.12 | 1.10 |

- Text and Muted pass everywhere.
- **Dim fails AA in 10/10 themes** on Surface, Window, Input, Sidebar and Hover. Dim is the colour of every description (l.2004), placeholder (l.1301, 2761), list description (l.2820), caption (NAVIGATION, JUMP TO, THEMES), tab count, empty-list text and the notification close X.
- **White on Accent fails in 10/10 themes**, and 7/10 fail even the 3:1 large-text bar. It is used for the active segment label (l.2716), the toggle knob (l.2292), the active tab icon (l.1723), primary and danger dialog buttons (l.1624), and List action hover ink (l.2828).
- Nord's Danger used as text on Surface is 2.77:1.
- **Effective backgrounds** follow the real compositing: control = Surface at .08 over the section body, which is Background at .56 over Window, which is Window with the .78 shade gradient (l.1281, 1765, 1946). Effective Dim-on-control is 3.10-3.86:1, essentially the same as nominal.

Suggested v2 token values that keep each theme's hue (script output):

| Theme | Dim now | Dim v2 (>=4.5 on Hover) | OnAccent (ink on Accent) | OnDanger |
|---|---|---|---|---|
| Argon | 98,106,128 | 125,132,151 (4.79 on Surface) | dark 5.76:1 | dark 6.98 |
| Midnight | 87,101,126 | 122,134,156 (4.93) | dark 7.89 | dark 7.03 |
| Emerald | 87,119,111 | 113,141,134 (4.91) | dark 10.26 | dark 6.95 |
| Rose | 132,91,115 | 158,122,143 (4.88) | dark 7.53 | dark 7.04 |
| Amethyst | 124,107,153 | 146,131,171 (5.02) | dark 5.87 | dark 7.40 |
| Slate | 103,114,130 | 131,141,155 (5.03) | dark 10.39 | dark 7.13 |
| Ember | 140,110,95 | 156,128,114 (4.87) | dark 8.45 | dark 7.03 |
| Nord | 126,138,156 | 172,180,193 (5.43) | dark 7.76 | white 4.09 |
| Mono | 108,108,118 | 135,135,144 (4.98) | dark 15.34 | dark 7.42 |
| Ocean | 94,124,143 | 118,145,162 (5.07) | dark 8.66 | dark 7.22 |

"dark" means the theme's own Background colour. Every built-in accent wants dark ink, not white.

### 2.2 Cost per display/interaction element (bench/controlsB_probe.luau, Lucide stubbed so icons are one ImageLabel)

| Element | Instances | Theme bindings | Connections | Counts as a "control" |
|---|---|---|---|---|
| Section (incl. its jump-rail chip rebuild) | 18 | 10 | 6 | no |
| Label | 10 | 5 | 0 | **yes** |
| Paragraph | 12 | 6 | 0 | **yes** |
| TelemetryCard | 16 | 6 | 0 | **yes** |
| ProgressBar | 10 | 7 | 0 | yes |
| Divider (plain / labelled) | 4 / 6 | 3 / 5 | 0 | **yes** |
| Space | 3 | 2 | 0 | **yes** |
| List, 10 rows x 2 actions | 90 | 77 | 61 | yes |
| Toggle bare / +Description / +Tooltip | 9 / 10 / 11 | 3 / 4 / 5 | 3 / 6 / 6 | yes |
| Toggle + Desc + Tooltip + Lock | 23 | 12 | 11 | yes |
| Notification toast | 26 | ~12 | 3 | n/a |

Without Lucide, the polyline fallback makes Label 71 instances and Paragraph 73: the "info" glyph alone is 31 Frames plus 31 UICorners.

### 2.3 Scenario results

| Probe | Result |
|---|---|
| B1 `SetVisible(false)`, then switch tab away and back | `Visible=true`. Also true after typing in search and clearing it. |
| B1 search for a word that only appears in a Description | no match. Search for a non-existent word: all sections hidden, **no empty state** |
| B2 TelemetryCard after `SetTheme("Emerald")` | title (52,211,153), status pill **(153,112,255): still Argon's accent** |
| B2 `SetStatus("STALE", Warning)` then `SetTheme` | title snaps back to Accent, pill stays Warning (split colour) |
| B3 `ProgressBar:SetColor(red)` then `SetTheme` | fill becomes the new Accent; the custom colour is lost |
| B4 `Paragraph:Set({Title=..., Content=...})` (Rayfield form) | `CurrentValue="table: 0x000001a27dc604b8"`, title unchanged |
| B5 `Section:Set("x")`, `Divider:Set(false)` | both throw (methods do not exist). `Label:Set(text, icon, color)` ignores icon and colour |
| B6 Notify titles | Incomplete download -> SUCCESS, Unsaved changes -> SUCCESS, No errors found -> DANGER, `Type="error"` ignored -> info |
| B7 Notify | `Image` ignored; returns `CanvasGroup`; 20 identical toasts = 520 instances; `Notify` before `CreateWindow` returns nil; stack x-offset fixed at -304 |
| B8 Dialog panel | `ClipsDescendants=nil`: title, body and buttons render without a panel behind them while it grows from 0 (and while it shrinks on close) |
| B9 Confirm closed with the X | `OnCancel` fired 0 times |
| B24 two Confirms | both visible, stacked; Esc closes nothing |
| B24 Dialog button "Подтвердить удаление" | 301 px wide (width = `#bytes*7+28`, l.1625) |
| B10 ColorPicker built while Mono is active | hex text bound to `AccentLight` (Mono's AccentLight is pure white). After `SetTheme("Argon")` the text is (195,170,255), not white |
| B11 tooltip open, then `Window:SetVisibility(false)` | tooltip still parented to the ScreenGui and visible |
| B12 locked Keybind, key pressed | `OnPressed` fired 1 time |
| B13 atlas available (getcustomasset), Lucide offline | padlock, "info" chip and notification "circle-check" all draw the **activity** cell (rect 0,0) |
| B14 `AddTheme` after `CreateLibrarySettings` | not in the theme dropdown (10 options) |
| B15 cold start with saved title "Renamed Hub" / Ocean | before `LoadConfiguration`: title "Probe Hub", theme Argon. `LoadConfiguration` runs `SetTheme` twice over 528 bindings |
| B15b `Window:SetTheme("Ocean")` + `Window:SetTitle(...)`, save, reload | theme **Argon**, title **"Prefs Hub"**: both reverted by the stale settings flags |
| B16 16 sections built on the active tab | 16 rail rebuilds, **135 chips** built for 16 needed |
| B17 150 x `List:AddItem` | **90,600 instances, 67,950 connections**, 6.3-11.5 s sandbox. One `SetItems(150)`: 1,200 / 900, 0.11 s |
| B18 300 controls | 2,061 theme bindings, 131 renderers, 1,045 connections. `SetTheme` = 5 frame yields (~84 ms of mixed-theme UI) |
| probe2 opening the theme picker | 130 instances rebuilt on every open; one swatch click = 2 x `SetTheme` |
| probe2 Row with a Paragraph and a Toggle | balance reads `Size.Y.Offset`, which is 0 for auto-height controls, so the toggle is never matched to the paragraph |
| probe2 hidden 76 px Segmented in a Row | its visible neighbour toggle still grows to 76 px |

---

## 3. Findings

Severity is for v2 planning. Kind uses the shared taxonomy.

### CB-01 SetVisible is overwritten by search and tab switches (high, bug)
- **Where:** `element:SetVisible` l.1948; `tab:_filter` l.1730-1756; `_select` calls `search.Text="" tab:_filter("")` at l.1690.
- **Evidence:** probe B1. Hidden -> `Visible=true` after switching tabs, and again after search + clear. Rows (l.1741-1748) and sections (l.1749) use the same overwrite, and the tab count still includes hidden controls.
- **v2:**
  - Keep `Hidden`, `FilteredOut` and `Collapsed` as separate element state, and compute `Root.Visible = not Hidden and not FilteredOut and not CollapsedParent` in one function.
  - Rows, sections, jump chips and tab counts derive from that function.
  - Add declarative `VisibleWhen` / `EnabledWhen` rules (`{Flag="Aimbot", Equals=true}` or `function(flags) ... end`), re-evaluated from the flag-change bus. This is the most common reason scripts call SetVisible.

### CB-02 Two sources of truth for UI prefs: API changes revert on reload (high, bug)
- **Where:** `CreateLibrarySettings` flags `ArgonUITheme`, `ArgonUIFont`, `ArgonUIWindowTitle`, etc. (l.2941-2959). `_exportUIPreferences` l.1517. `LoadConfiguration` applies `__argon` first (l.1038-1046), then the flags (l.1076-1099).
- **Evidence:** probe B15b. `Window:SetTheme("Ocean")` / `Window:SetTitle(...)` -> reload -> theme Argon, title default, because the setters do not update the settings controls, whose flags then win.
- **v2:** prefs live in exactly one place (`__argon` / meta file). Settings controls are views: they read from and write to the prefs store and are not user-config flags. Each setter updates its control silently. Migration: if legacy `ArgonUI*` flags exist in a file, fold them into prefs once.

### CB-03 Saved prefs are applied after the build, causing a double full repaint and the default title on the loader (high, loader/perf)
- **Where:** l.1236-1242 read `self._uiPreferences`, which is always `{}` on a fresh `loadstring`. `LoadConfiguration` is the only writer (l.1039) and needs `_configuration`, which only `CreateWindow` sets (l.1233). The theme dropdown callback at l.2943-2946 calls `SetTheme` again.
- **Evidence:** probe B15. On a cold start the title is "Probe Hub" (saved: "Renamed Hub") and the theme is Argon (saved: Ocean). `LoadConfiguration` runs `SetTheme` twice, each over every binding (528 in a 106-control UI; 2,061 in the 300-control UI). Font is applied twice the same way (l.1523 + l.2949).
- **v2:** in `CreateWindow`, synchronously `readfile` + `JSONDecode` the prefs block (sub-millisecond) and apply theme, font, title, scale and accent **before the first instance is created**. `LoadConfiguration` then only restores control values. One `SetTheme` per user action.

### CB-04 Ink on accent and danger fills is unreadable (high, a11y/visual)
- **Where:** white literals at l.1624 (dialog buttons), l.1723 (active tab icon), l.2292 (toggle knob), l.2716 (active segment), l.2828 (List action hover).
- **Evidence:** contrast table. White/Accent is 1.29 (Mono) to 3.43 (Argon). White/Danger is 2.66-2.84 in 9/10 themes. Mono's selected segment and primary button are white on (226,226,232).
- **v2:** add `OnAccent`, `OnDanger`, `OnSuccess`, `OnWarning` tokens. Dark ink (theme Background) gives 5.8-15.3:1 on every built-in accent. Add a contrast validator in `AddTheme`/`CreateTheme` that picks the ink automatically for custom palettes.

### CB-05 Dim fails AA in every theme and carries most secondary text (medium-high, a11y)
- **Evidence:** 3.08-4.18:1 on Surface, Window, Input and Sidebar; 2.70-3.54:1 on Hover. Descriptions are Dim at 11 px (l.2004), so the smallest text also has the lowest contrast.
- **v2:** use the per-theme Dim values in section 2.1 (>=4.5:1 even on Hover). Rename the token roles to text.primary / secondary / tertiary / disabled, and allow sub-AA only for disabled text.

### CB-06 Palettes are flat: no elevation, state or border contrast; 18 tokens; no light theme (high, visual)
- **Where:** palettes l.23-46.
- **Evidence:**
  - Surface/Window 1.06-1.19, so cards barely separate from the page.
  - Hover/Surface 1.06-1.20, so hover feedback is near-invisible.
  - BorderSoft/Surface 1.16-1.28, so control edges are near-invisible.
  - Input/Surface 1.05-1.13, so the toggle-off track (l.2286) is invisible; only the knob shows.
  - Success, Warning and Danger are byte-identical in Argon, Midnight, Emerald and Rose.
  - No OnAccent, Info, Overlay/Scrim, Shadow, Focus, Selection, Disabled or ElevatedSurface tokens.
  - All 10 themes are dark variants that differ mainly by hue.
- **v2 token set (legacy keys kept as aliases):**
  - Neutral ramp with a minimum step of about 1.12:1 between bg, window, surface, elevated and hover.
  - border.subtle at about 1.4:1 and border.strong at about 2:1 against surface.
  - text.primary/secondary/tertiary/disabled.
  - accent / accent.hover / accent.subtle (tint) / accent.text / onAccent / focus.
  - success, warning, danger and info, each with fg, bg-tint, border and on.
  - overlay, shadow.
- **Generator:** `Argon:CreateTheme({Accent=Color3, Neutral="cool"|"warm"|"neutral", Mode="dark"|"light", Contrast="normal"|"high"})` derives every token with guaranteed ratios.
- **Ship:** at least one light theme ("Daylight") and one high-contrast theme, and let the user pick an accent independently of the neutral palette.

### CB-07 Theme binding by Color3 equality mis-binds literal colours (medium, bug)
- **Where:** `themeKeyForColor` l.178-183, called by `create()` for every Color3 property (l.275-281). Mono AccentLight is pure white (l.46).
- **Evidence:** probe B10. A ColorPicker hex label built under Mono is bound to AccentLight and turns (195,170,255) after switching to Argon. The same happens to the logo fallback strokes (l.458-460), the colour-popup white layer and cursor (l.2882, 2884), and white dialog ink, whenever they are built while Mono is active. Any custom palette containing white or black has the same problem.
- **v2:** bind by token, not by value. Constructors pass token names (e.g. `theme={BackgroundColor3="Surface"}`, or a `T.Surface` sentinel resolved in `create`). Literal Color3 values are never bound. This also removes the 18-key scan per property and lets one binding record per object replace one per property.

### CB-08 TelemetryCard status pill and ProgressBar colour ignore theme changes (medium, bug)
- **Where:** l.2584-2586 unbind the pill and never register a renderer. `SetStatus` recolours the title, which is still Accent-bound (l.2595-2600). `ProgressBar:SetColor` tweens a fill that stays Accent-bound (l.2631, 2655).
- **Evidence:** probe B2/B3. The pill keeps the old theme's accent. A custom status or bar colour is lost or split on the next theme switch.
- **v2:** each state-driven element keeps `{tokenOrColor}` state and re-renders from it in its theme renderer. `SetColor`/`SetStatus` accept a token name ("Warning") or a Color3 override that persists across themes.

### CB-09 Offline icon fallback draws the wrong glyph for lock, info and notification severities (medium, bug)
- **Where:** `drawIcon` l.426-430. The atlas lookup falls back to `ICON_ATLAS_RECTS.activity` **before** the polyline table is consulted. The atlas has no lock, info or circle-* cells (l.75-94), so the polylines added for exactly these glyphs (l.68-73) are unreachable whenever the atlas loaded. "lock" (l.2058) has no polyline either.
- **Evidence:** probe B13. With getcustomasset present and Lucide offline, the padlock, label info chip and toast check all render the activity cell (rect 0,0).
- **v2:** ship the 20-30 glyphs the library itself uses (lock, info, circle-check/x, alert, x, chevrons, search, help, copy, rotate-ccw, ...) in one bundled atlas, resolved by exact name, then Lucide, then a neutral "square" placeholder. Never substitute an unrelated glyph.

### CB-10 Lock is cosmetic; locked controls still act (medium, bug/ux)
- **Where:** `Lock` l.2035-2100 only adds a scrim. The Keybind hotkey path (l.2433-2441) and any other non-pointer path ignore `Locked`. The badge uses Warning amber (l.2051-2058). When it collapses to "LOCKED" or the bare padlock, the reason has no tooltip.
- **Evidence:** probe B12: locked keybind -> `OnPressed` fired 1 time.
- **v2:**
  - `SetDisabled(bool)` (dimmed, no badge) and `Lock(reason | {Reason, Icon, Variant="blocked"|"premium"})` are separate states.
  - Both block every user path: pointer, hotkeys, steppers, text focus. Programmatic `Set` still works.
  - The badge uses a neutral token, or Accent for "premium".
  - Hovering or tapping the badge shows the full reason.

### CB-11 Tooltips: mouse-only, leak past window hide, rebuilt per hover (medium, ux)
- **Where:** l.2112-2223. Opens only on `root.MouseEnter`. The marker is a 14x14 `TextLabel` "?" (l.2119), so it cannot be tapped. The tooltip is parented to the ScreenGui and only closed by `MouseLeave`. A new frame tree is built on every hover (l.2210-2213).
- **Evidence:** probe B11: the tooltip is still visible after `SetVisibility(false)`.
- **v2:** one pooled tooltip instance per window. Delay 350 ms, with a 100 ms skip-delay once a tooltip is open. 120 ms fade plus a 4 px slide. Close on scroll, tab switch, window hide and Esc. Touch: long-press the row (500 ms) or tap a Lucide `circle-help` ImageButton (16 px glyph, 32 px hit area). Max width 280, RichText.

### CB-12 Dialog: unclipped open/close animation, no keyboard, X skips OnCancel, byte-length button widths (medium, visual/ux)
- **Where:**
  - Panel created without `ClipsDescendants` (l.1583) and tweened from height 0 with Back easing (l.1610).
  - Close tweens it back to 0 (l.1598).
  - Button width is `#title*7+28` (l.1625).
  - Raw `TextSize=10` labels (l.1625).
  - The X button only calls `Close` (l.1617).
- **Evidence:** probe B8/B9/B24. `ClipsDescendants=nil`. OnCancel fires 0 times on X. A Cyrillic label gets a 301 px button. Two Confirms stack. Esc does nothing.
- **v2:**
  - Clip the panel. Open with scale .96->1 plus fade (160 ms Quint, no overshoot).
  - Esc = cancel, Enter = primary, outside click = cancel (configurable). Every dismissal path calls `OnCancel`.
  - Buttons auto-size (AutomaticSize X + padding) with 13 px labels.
  - Queue dialogs, or stack them with only the top one interactive.
  - Add `Window:Prompt{Title, Placeholder, Validate}`, needed for renaming profiles.
  - Below 480 px width, render as a bottom sheet.

### CB-13 Notifications: keyword guessing, no API surface, heavy and fixed in place (high, ux/api)
- **Where:** l.1142-1219, container at l.1368.
- **Evidence:** probe B6/B7.
  - Severity is a substring match on the title (l.1153-1156) with no negation or word boundaries. `Type`, `Image`, `Icon`, `Actions` and click callbacks are ignored.
  - Returns the CanvasGroup.
  - Fixed 4 s regardless of length; no hover pause; no de-dupe (20 identical = 520 instances).
  - The cap destroys the oldest toast instantly (l.1217); toasts that are mid-dismiss count toward the cap.
  - x-offset fixed at -304 even when the overlays are hidden.
  - Nothing is queued before a window exists.
  - The close target is 20x20 px (l.1182).
  - The CanvasGroup's Size is tweened on dismiss (l.1204), the stale-buffer rescale the window code deliberately avoids (l.1271-1279).
- **v2:**
  - `Notify{Title, Content, Type="info"|"success"|"warning"|"error"|"loading", Icon|Image, Duration=number|false|"auto", Actions={{Title, Callback, Variant}}, Callback, Id}`.
  - "auto" duration = 3.5 s + 50 ms per character, capped at 10 s, x1.5 for errors.
  - Hover pauses the timer. Click or swipe dismisses.
  - The same `Id` updates the toast in place, so a loading toast can turn into success or error. Identical toasts within 2 s collapse into one with a xN counter.
  - Returns a handle `{Instance, Update, Dismiss, SetProgress}`.
  - The keyword heuristic stays only as a fallback, with word boundaries and a negation guard.
  - `Position` option. The placement follows overlay visibility. Phones get a full-width top-centre stack.
  - A notification layer that exists before `CreateWindow` and queues early toasts.
  - Pooled frames and per-element fades instead of a resized CanvasGroup.

### CB-14 Rayfield compatibility gaps in display controls (high, api)
- **Where:** `Paragraph:Set` l.2563 (`tostring` of the table), `CreateSection` l.1758-1785 (no `Set`), `CreateDivider` l.2606-2616 (no `Set`), `CreateLabel(value)` l.2257 (single argument), `Notify` ignores `Image`.
- **Evidence:** probe B4/B5.
- **v2:**
  - `Paragraph:Set(string | {Title, Content})`.
  - `Section:Set(name)`; `Divider:Set(visible)`.
  - `CreateLabel(text, icon, color, ignoreTheme)` and `Label:Set(text, icon, color)`.
  - Notify `Image` maps to the icon.
  - Add a compat test per Rayfield signature to `tests/`.

### CB-15 List is quadratic and rebuilds everything (high, perf)
- **Where:** `SetItems` destroys and rebuilds all rows (l.2793-2837). `AddItem` deep-copies all items and calls `SetItems` (l.2843-2845). Each action button adds 3 global connections (l.2828-2830).
- **Evidence:** probe B17. 150 x `AddItem` = 90,600 instances / 67,950 connections, vs 1,200 / 900 for one `SetItems`. Record identity passed to callbacks changes after every `AddItem`, because the items are copied.
- **v2:**
  - Keyed rows (`Id`) with `AddItem`, `RemoveItem`, `UpdateItem(id, patch)` and diffing `SetItems`.
  - A row pool with virtualization: only visible rows are instantiated. A 156 px viewport holds about 5 rows, so the instance count is constant.
  - Optional built-in filter box above N rows. Sort. Single or multi selection.
  - Leading icon or avatar (`rbxthumb://`) and a trailing badge.
  - Two inline actions, the rest behind a "..." menu, revealed on hover.
  - An empty state with icon, text and an optional action.
  - Auto height up to `MaxHeight`, and scroll chaining to the page.
  - 12-13 px action labels; today they are `TextSize=9`, l.2827.

### CB-16 Jump rail churn and missing scroll-spy (medium, perf/ux)
- **Where:** `CreateSection` calls `_refreshSectionMenu` whenever the tab is active (l.1783). Each call destroys and rebuilds every chip (l.2978-2997). A chip click sets `CanvasPosition` instantly (l.2992-2995).
- **Evidence:** probe B16: 16 sections -> 16 rebuilds, 135 chips (4 instances and 3 connections each).
- **v2:**
  - Coalesce rebuilds with one `task.defer` per tab and build lazily on first show.
  - Highlight the section in view from `CanvasPosition` (scroll-spy) and scroll smoothly with a tweened NumberValue.
  - Fade masks on overflow. Skip sections whose controls are all hidden.
  - Offer a vertical outline on windows at least 1100 px wide.

### CB-17 Search is title-only, per-tab, with no empty state (medium, ux)
- **Where:** l.1730-1756 matches `element.Name` and section name only. The "/" shortcut at l.3098 can collide with Roblox chat's "/" focus.
- **Evidence:** probe B1: a Description-only word matches nothing, and a no-match query leaves a blank page.
- **v2:**
  - A global command palette (Ctrl+K, plus "/" only while the window is visible and no TextBox is focused) that indexes tabs, sections, titles, descriptions, tooltips, dropdown options and paragraph text, with fuzzy ranking.
  - Results show a "Tab > Section" breadcrumb. Enter switches tab, expands the section, scrolls to the control and flashes a focus ring for 600 ms.
  - The per-tab filter stays as a quick filter with "No controls match 'x'" and a clear button, and it respects `Hidden`.

### CB-18 Theme picker: rebuilt per open, double SetTheme per pick, no preview depth, stale lists (medium, ux/perf)
- **Where:** `ToggleThemePicker` rebuilds the grid on every open (l.3065-3069, 3033-3057). `chooseTheme` calls `SetTheme`, then `SetFlagValue`, whose callback calls `SetTheme` again (l.3024-3031 -> l.883 -> l.2945). Swatches show only the accent trio (l.3046). No outside-click or Esc close (only l.3062 and l.3133 hide it). The settings dropdown snapshots `GetThemes()` (l.2943).
- **Evidence:** probe2: 130 instances per open and 2 `SetTheme` per click. Probe B14: a theme added later is missing from the dropdown.
- **v2:**
  - Build once and re-render on an `OnThemesChanged` signal.
  - Cards with a mini window preview (window, surface and text bars plus an accent chip), grouped Dark / Light.
  - An accent row (8 presets plus a custom picker) and Font / Text size segmented controls in the same popover.
  - Close on outside click, Esc and tab switch.
  - One `SetTheme` per pick; the prefs store is written directly (see CB-02).

### CB-19 Typography: 14 sizes, unscaled button labels, uppercase micro-labels (medium, visual)
- **Where:**
  - `readableSize` l.559-564 is only applied in `text()`. TextButtons and TextBoxes created through `create()` keep raw sizes: list actions 9, dialog buttons 10, segmented 10, jump chips 10, keybind 10, search 12.
  - Sizes used: 8, 8.5, 9, 9.5, 10, 10.5, 11, 12, 12.5, 13, 15, 16, 17, 21 through `text()`, plus raw 9-19. That is **14 distinct rendered sizes**, including fractional ones that Roblox renders in whole-pixel steps (the owner hit the same TextSize-is-whole-pixels behaviour in another project).
  - Many UPPERCASE GothamBlack/Bold captions at 10-11 px (sections l.1764, eyebrow l.1315, NAVIGATION, JUMP TO, THEMES, divider labels, telemetry titles). Roblox has no letter-spacing, so they set tight and hard to read.
  - The README still says "One modern typeface throughout (BuilderSans)", but the default is Roboto + Montserrat (l.494, 514).
- **v2:**
  - A whole-pixel type scale of 6 tokens: caption 11, secondary 12, body 13, emphasis 14 semibold, section title 15, page title 20-22. It is applied through one path for every text-bearing class.
  - Sentence-case section titles; uppercase only for 1-2 word eyebrows.
  - User "Text size" (90/100/115/130%) and "Interface scale" (UIScale) settings.

### CB-20 Display controls: weak hierarchy, card-in-card, counted as controls (medium, visual)
- **Where:**
  - Label (l.2257-2270) and Paragraph (l.2551-2566) are near-identical cards, each with a mandatory info chip.
  - Every control is a bordered card (l.1946) inside a bordered section card (l.1765-1766), so a section draws N+1 strokes.
  - Divider labels sit in a fixed 30% slot between fixed 34% lines with no truncation (l.2610-2613), leaving uneven gaps and overflow.
  - `base()` increments the tab count for Label, Paragraph, Telemetry, Divider and Space (l.2232; probe table 2.2).
- **v2:**
  - Sections become one grouped card with hairline separators between rows, plus edge-to-edge hover rows. Drop per-control strokes.
  - **Label** is a plain text row (optional icon, colour, `Style`: muted/info/success/warning/danger). **Paragraph** is title plus body with optional "show more". Add a **Callout/Alert** (tinted, optional action and dismiss).
  - The Divider hugs its label (UIFlexItem lines).
  - Space uses spacing tokens.
  - Only interactive controls count toward the tab badge.

### CB-21 TelemetryCard and ProgressBar are thin for the "dashboard" use case (low-medium, feature)
- **Where:** TelemetryCard is a title plus free text (l.2568-2604). ProgressBar has no indeterminate state, thresholds or segments (l.2623-2658).
- **v2:**
  - **StatCard**: big value, label, delta with a coloured up/down arrow, a status pill (token-driven), and an optional pooled sparkline. `SetValue`, `SetDelta`, `Push(sample)`; `Set(text)` stays for compatibility.
  - **ProgressBar**: `Indeterminate`, `Thresholds={{.9,"Danger"}}`, `Steps`, a compact inline variant, and an ETA/format helper.
  - Add a **KeyValue/Stats** grid for "Uptime 4m / Items 128"-style readouts.

### CB-22 Row balance ignores auto-height and hidden controls (low, bug)
- **Where:** `balance` reads `Size.Y.Offset` and checks `Parent` only (l.1827-1856).
- **Evidence:** probe2. A Paragraph's natural height reads as 0, so its neighbour never matches it. A hidden 76 px Segmented still pads its visible neighbour from 54 to 76.
- **v2:** balance from the measured content height (`AbsoluteSize` / layout content size) and skip hidden elements. Add `Tab:CreateGrid{MinColumnWidth}` (auto-fit column count) next to fixed-column Rows.

### CB-23 Section component is minimal (medium, feature)
- **Where:** l.1758-1785: name only.
- **Missing:**
  - `Set`, `SetVisible`, collapse
  - description, icon, header actions
  - truncation (the header text has no `TextTruncate`, l.1764)
- **v2:**
  - `CreateSection{Title, Description, Icon, Collapsible=true, Collapsed=false, Actions}`. Collapse state is persisted in prefs.
  - `Section:Set`, `SetVisible`, `Collapse`/`Expand`, and a `Reset` action that resets the section's controls to their defaults.

### CB-24 No configuration UX for end users (high, feature)
- **Where:**
  - One path per window (`configPath` l.758-767).
  - `DeleteConfiguration`/`ResetConfiguration` are API-only (l.933-954). The settings tab explicitly removed all config controls (l.2961-2966).
  - The menu toggle key is settable only through `SetToggleKey` (l.1398). It is not in the settings tab and not persisted (l.1517-1518), and it defaults to Insert (l.1385), which many laptops lack.
  - Element defaults are not recorded, so per-control reset is impossible.
  - Save failures only `warn()` (l.777).
- **Evidence:** probe B14: no menu-key control and no profile, import or export API.
- **v2:**
  - A **Configuration** section in `CreateLibrarySettings`, also available as `Window:CreateConfigManager(tab)`:
    - A profile list (List with Load / Overwrite / Rename / Delete / Set autoload) plus a "New profile" input.
    - Export to the clipboard (`setclipboard`; plain JSON or `ARGON1:`+base64) and Import from a pasted string, with a summary ("12 settings changed, 2 unknown").
    - Reset all to defaults, behind a Confirm.
    - A live "Saved 2 s ago / Saving... / Save failed: reason" line from `GetConfigurationStats`.
  - Files: the current `<Folder>/<FileName>` stays the "Default" profile (compat), others live in `<Folder>/profiles/<name>.json`, and `<Folder>/argon.meta.json` holds `{Autoload, LastProfile, Prefs}`.
  - Every element records `Default`. `element:Reset()` and a section reset action. An optional "modified" dot on changed controls.
  - A rebindable, persisted menu key in settings.

### CB-25 Touch, keyboard and gamepad gaps in the interaction layer (high, ux; overlaps the shell area)
- **Where:** no `TouchEnabled`, `KeyboardEnabled` or `GamepadEnabled` checks and no Escape handling anywhere (grep: only the keybind listener at l.2438 mentions Escape). The hide button (l.1341, 3093) leaves only the keyboard toggle (l.3095-3099) as a way back. Hit targets are 14-20 px (tooltip marker, toast close, dialog X 24 px).
- **Evidence:** code reading. A phone user who taps "-" cannot reopen the menu.
- **v2:**
  - A draggable floating reopen pill (logo) whenever the window is hidden on a touch device.
  - Esc closes the topmost layer (popover -> palette -> dialog -> tooltip).
  - Gamepad: `Selectable` plus `GuiService.SelectedObject` navigation with a focus ring token.
  - Minimum 32-40 px hit areas; long-press for tooltips.

---

## 4. v2 blueprint for this area (condensed)

1. **One theme engine:** tokens (section CB-06), binding by token (CB-07), renderers for state, validator and generator, a light and a high-contrast theme, a user accent, and an `OnThemesChanged` signal. Apply prefs before the first instance (CB-03). Switch with one pass, without chunked "wave" repaints of mixed themes; the 300-control UI needed only 5 yields, so a single pass is affordable.
2. **One visibility model:** Hidden x Filtered x Collapsed, plus `VisibleWhen`/`EnabledWhen` (CB-01), Disabled vs Locked enforced on every input path (CB-10).
3. **One overlay layer manager:** tooltip, popover, dialog, palette, toast. It handles z-order, Esc, outside-click, closing on window hide, a pooled tooltip, and mobile sheet variants (CB-11, CB-12, CB-18, CB-25).
4. **Display set:** Label (plain), Paragraph, Callout, StatCard, Stats grid, ProgressBar+, keyed virtual List, flexible Divider, token Space, Section+ (collapsible, grouped-card look), Row + Grid (CB-14, CB-15, CB-20 to CB-23).
5. **Notifications v2** (CB-13): typed, actionable, updatable, pooled, positioned; keyword fallback only.
6. **Search v2** (CB-17): command palette plus quick filter with an empty state; jump rail with scroll-spy (CB-16).
7. **Settings and config v2** (CB-02, CB-24): Appearance (theme cards, accent, font, text size, interface scale, reduced motion), Window (menu key, mobile reopen button), Overlays, Notifications (position, duration, mute), Configuration (profiles, import/export, reset, save status), About (version, icon source status).
8. **Rayfield compat tests** for every display-control signature (CB-14).
