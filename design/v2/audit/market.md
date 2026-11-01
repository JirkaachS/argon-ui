# Argon UI v2: market scan and UX target

This report covers what "next-gen", "top-tier UX" and "add things that make sense" should mean for Argon v2. It answers four questions: (a) which features to add or upgrade, (b) which UX patterns to adopt and their exact specs, (c) which competitor mistakes to avoid, and (d) what makes a Roblox UI feel premium rather than cheap.

All `Lnnn` references point to `argon-ui.luau` (v1.18.3). Per-control bugs are covered in depth in the sibling audit `audit/controlsA.md`. This file only repeats them where they shape the product direction.

## 0. Method and sources

**Code.** I read the whole library apart from the base64 block. I measured three things from it:
- **Palette contrast:** WCAG 2.x ratios for every built-in theme, parsed from L23-46.
- **Text sizes:** every `text()` and `TextSize=` call site.
- **Fixed hit sizes:** every `TextButton` that uses `fromOffset`.

The numbers are in section 2.

**Web.** WebSearch and WebFetch both worked in this session. I used:
- **Rayfield:** the docs index `docs.sirius.menu/llms.txt`, plus the Gen2 pages: windows, notifications, elements overview, tabs, dropdowns and saving. Also the Rayfield issue list at `github.com/SiriusSoftwareLtd/Rayfield/issues`.
- **WindUI:** the README, `main.client.lua`, the issue list, and issues #43, #77 and #88 in full.
- **Obsidian:** `docs.mspaint.cc/obsidian` and `Example.lua` from the repo.
- **Fluent:** the README and the issue list.
- **Roblox API reference:** `UserInputService.PreferredInput` and `UIDragDetector`.

**Own knowledge.** These pages were not fetchable (the M3 site is JS-rendered and the HIG was not reachable), so the following come from what I already know, not from quotes:
- Material 3 easing and duration tokens. M3 Expressive spring values exist only as community transcriptions that disagree with each other.
- The Apple HIG 44 pt target and the visionOS / Liquid Glass concentric-corner rule.
- Radix and shadcn interaction specs.
- Raycast's command palette.
- Linear's three-variable theme generator.
- Vercel Geist "materials".
- Steam Big Picture and Xbox focus conventions.
- Details on Orion, Kavo, Luna and classic Linoria. These come from memory plus reposts, so treat them as secondary.

---

## 1. What "next-gen" should mean for Argon

Six properties, each one testable:

1. **Instant.**
   - The window chrome is on screen in the same frame `CreateWindow` returns.
   - The first tab is usable in under 200 ms for a 300-control script.
   - There are no artificial timers. Big lists are virtualized and heavy work is time-sliced.
   - Today the floor is 0.93 s even for a five-control script (section 2.2).
2. **Works with every input.**
   - The same script is first-class on mouse, touch, gamepad and keyboard.
   - On a phone the window can always be reopened.
   - Focus is visible.
   - Hit targets follow the input type that `UserInputService.PreferredInput` reports.
3. **Findable.**
   - One search covers every tab, as a command palette.
   - Controls can be pinned.
   - Recent items are remembered.
4. **Forgiving.**
   - Every control can be reset to its default.
   - Destructive actions offer undo or hold-to-confirm, not a stack of dialogs.
   - Named profiles let users experiment without losing a setup.
   - Errors are shown on the control, not in the console.
5. **Quiet and legible.**
   - Contrast meets the targets in 6.1.
   - Rendered text is never below 12 px, and body text is 13-14 px.
   - One accent colour, fewer boxes (grouped lists instead of a box inside a box), one icon system.
   - No fake status chrome.
6. **Expressive where it counts.** The motion budget goes on:
   - the selection indicator and toggle knob (spring),
   - popover origin scaling,
   - toasts with actions,
   - skeletons while work is pending.

   Nothing else moves without a reason.

---

## 2. Baseline: v1.18.3 as a user experiences it

### 2.1 Strengths to keep (several are ahead of the market)

| Strength | Where | Market comparison |
| --- | --- | --- |
| `CreateRow`: columns collapse below `MinColumnWidth`, and a line grows to its tallest control | L1796-1942 | Rayfield Gen2's groups do something similar but forbid inputs, keybinds and colour pickers inside them. Argon's rows are better. |
| `Lock(reason)`: dimming scrim plus a padlock badge that changes tier with width | L2035-2110 | Gen2 has `Lock(reason)` that swaps the description text. Argon's is visually richer. |
| Tooltips with flip/anchor placement and an open delay | L2112-2224 | Obsidian has `Tooltip`/`DisabledTooltip`. Argon's placement logic is more careful. |
| Verified autosave, deferred flag hydration, flags kept for controls not yet built | L769-1127 | No competitor documents read-back verification. |
| List rows with several actions each | L2781-2848 | Unique. |
| `Window:Confirm` with Cancel as the default | L1638-1653 | Matches the Radix AlertDialog convention. |
| Cursor layer for games that hide the engine cursor | L3149-3175 | Obsidian has `ShowCustomCursor`. Argon's auto-detection is better. |
| Pinned player and keybind overlays | L1437-1579 | Obsidian/Linoria have a keybind menu. Few have a player overlay. |
| Live re-theming that is correct even mid-animation | L600-705 | Rayfield issue #46 (the theme dropdown highlights the previous theme) shows how others get this wrong. |

### 2.2 User-visible problems (measured or read from code)

| # | Problem | Evidence | What the user feels |
| --- | --- | --- | --- |
| P1 | **Hiding the window on touch cannot be undone.** The "–" button hides it, and the only way back is a keyboard key. There is no on-screen reopen button. | `hide` L1341 → `SetVisibility(false)` L3093. The reopen path is only `input.KeyCode==window._toggleKey` (L3095-3097). | A phone or tablet user taps "–" once and the menu is gone until the script is executed again. Rayfield ("Show Rayfield" button), WindUI (`OpenButton`) and Obsidian (`MobileButtonsSide`) all solve this. |
| P2 | **The loader delays every script by at least 0.93 s, and on first run it flashes a half-built full-size window.** | Pill at L3187, expand at 0.38 s (L3352), open at 0.93 s (L3359), splash destroyed at about 1.25 s (L3296). Contents are hidden until then (L3185). On first run, `drawIcon("search")` at L1300 calls `loadLucideIndex()`, which runs `game:HttpGet` (L374) *before* the splash exists (L3183). By then the 980x660 `main` frame (L1280) and part of the sidebar are already parented (L1255). `GetUserThumbnailAsync` (L1309) yields the same way. | First run, in order: a full-size dark half-window, then a collapse into a pill, then a grow back out. Every run: nothing can be clicked for 0.93-1.25 s, however fast the build was. With `Loading="manual"`, nothing is visible until `FinishLoading` or the 30 s watchdog. (Read from code; confirm in a live client.) |
| P3 | **Notification type is guessed from words in the title.** | L1153-1156 does substring matching on `error`/`failed`/`warn`/`wait`/`success`/`complete`/`saved`. | "Unsaved changes" turns green. "Awaiting server" turns amber. There is no `Type` or `Icon` option, no actions, no hover-pause, a 20x20 close button (L1182), and the stack cap destroys the oldest card with no exit animation (L1213-1217). Rayfield's `Image` option is ignored. |
| P4 | **Contrast is too low in every theme** (measured, WCAG 2.x). | Table below; themes from L23-46. | Descriptions and placeholders are hard to read. Hover feedback is nearly invisible. Text on the accent colour (primary buttons, the active segment, the active tab glyph) fails in every theme, and is unreadable on Mono. |
| P5 | **Text is small.** | 32 of 57 `text()` call sites ask for ≤10 px; `readableSize` (L559-564) only adds +1/+2, so they render at 10-11 px. Ten raw `TextSize=9/10` values set through `create()` skip `readableSize` entirely: dialog buttons L1625, tooltip marker L2119, slider value L2310, keybind L2417, dropdown filter and options L2525/L2531, segmented L2739, list actions L2827 (9 px), hex box L2888, jump chips L2988. Fractional sizes (8.5, 9.5, 10.5, 11.5, 12.5) are used at 7 sites, and Roblox renders TextSize in whole pixels. | Hard to read at 1080p. Tiny on a phone, because there is no UI scale (`UIScale` appears once, on overlay cards only, L1440). |
| P6 | **Hit targets are small.** | 20x20 (toast close L1182, input clear L2361), 26x24 (stepper L2668-2669), 28x28 (hide and theme buttons L1334/L1341), 22 px tall list actions (L2827). | Misses on touch (44 pt is the convention) and fiddly with a mouse. |
| P7 | **Popovers behave unlike any modern UI.** The dropdown is always 226 px tall (L2544), even with 2 options, and always opens downward (L2521). It is placed in absolute coordinates under the ScreenGui, so it detaches when the page scrolls. There is no outside-click dismiss (L2546) and no keyboard support. The colour picker opens at `X-170` with no clamp (L2879). | L2516-2546, L2876-2898 | Menus open off-screen near the bottom edge, float away from their control, and only close by clicking the trigger again. |
| P8 | **No keyboard focus and no gamepad navigation.** | Zero references to `Selectable`, `GuiService`, `Gamepad` or `ContextActionService`. | Controller users cannot use the menu at all. Keyboard users get only `/` and the toggle key. |
| P9 | **Search covers the current tab only, matches only names, and has no empty state.** | Placeholder "Search this tab" (L1301). Matches `Name` plus section name only (L1735). Cleared on every tab switch (L1690). Sections hide and leave a blank page (L1749). | Users cannot find a setting when they don't know which tab it is on, which is the main reason to search. |
| P10 | **Fake and library-branded chrome.** | A "LIVE" pill with a breathing halo (L1317-1329), "ARGON ONLINE" under the avatar (L1311), the eyebrow "ARGON / <TAB>" (L1315, L1680), and a tab badge counting *controls* (L1702, L1729). | It means nothing to the end user and brands the host's hub as Argon. It reads as template filler. |
| P11 | **Text glyphs mixed in with Lucide icons.** | "→" on buttons (L2275), "–" for hide (L1341), "×" for dialog close (L1589), "-"/"+" on the stepper (L2668-2669). | Glyph weights and baselines differ from the icon set. This is a typical "cheap" tell. |
| P12 | **The window can be dragged off-screen.** | L3089 has no clamp, and there is no reset. | On touch, a stray drag loses the window. |
| P13 | **Boxes inside boxes inside boxes.** A section card (fill and stroke, L1765-1766) holds control rows, each with its own fill, corner and stroke (L1946-1947), and inputs add a third well inside. | | Visual noise, and 2 extra instances per control (perf). Linear, Geist and iOS settings pages use one card with divided rows instead. |
| P14 | **No light or high-contrast theme.** All 10 palettes are dark. There is no theme editor, only the `AddTheme` API. | L32-46 | WindUI and Fluent ship a Light theme. Obsidian's ThemeManager has a live editor. |
| P15 | **Rayfield migration gaps.** Argon reads none of these: `KeySystem`/`KeySettings`, `LoadingTitle`/`LoadingSubtitle`, Notify `Image`, keybind `HoldToInteract`, window `Icon`. | grep: 0 matches for each | A Rayfield script that relied on its key gate silently opens without one. Hold keybinds act as taps, and loader text and notification icons disappear. That breaks the README's "usually only need their loader swapped" (README L45). |

**Measured contrast for P4** (WCAG ratio; AA needs 4.5 for small text and 3.0 for UI parts):

| Theme | Dim on Surface (descriptions L2004, placeholders) | Muted on Surface | White on Accent | Hover vs Surface | Surface vs Window |
| --- | --- | --- | --- | --- | --- |
| Argon | 3.32 | 6.62 | 3.43 | 1.06 | 1.06 |
| Midnight | 3.08 | 6.77 | 2.53 | 1.07 | 1.07 |
| Emerald | 3.58 | 7.18 | 1.92 | 1.08 | 1.08 |
| Rose | 3.23 | 6.90 | 2.65 | 1.07 | 1.06 |
| Amethyst | 3.66 | 7.47 | 3.35 | 1.10 | 1.08 |
| Slate | 3.47 | 6.84 | 1.87 | 1.11 | 1.09 |
| Ember | 3.83 | 7.64 | 2.34 | 1.08 | 1.07 |
| Nord | 3.24 | 5.85 | 2.00 | 1.20 | 1.19 |
| Mono | 3.41 | 6.75 | **1.29** | 1.09 | 1.07 |
| Ocean | 3.80 | 7.29 | 2.24 | 1.12 | 1.10 |

What this means:
- Descriptions should use `Muted`, which is fine everywhere, not `Dim`.
- Text on the accent colour needs a computed `OnAccent` role: white or near-black, whichever reaches 4.5:1.
- The step from Surface to Hover needs about 1.12:1 or more before hover reads as a state.

---

## 3. The market

### 3.1 Profiles

**Rayfield classic (Sirius, 2022).** Argon's API family.
- **Praised for:** a simple API, a clean look, a built-in key system, notifications, config saving, and a "Show Rayfield" button for restoring a hidden window on mobile or PC.
- **Open issues:**
  - Dropdown search request (#16)
  - "Mobile dragging is really weird" (#27)
  - Executors without `game:GetObjects()` (#47; the UI is loaded as a model asset)
  - The theme dropdown highlights the previous theme (#46)
  - No component descriptions (#10)
- **Detectability:** the docs have "anti-detection" and "secure mode" pages because its asset references are detectable. That is out of scope here, but the lesson for Argon is to avoid loading UI from external assets.

**Rayfield Gen2.** A ground-up rebuild that the Sirius docs now recommend over classic. This is Argon's most direct competitor, because the API family is shared. Features:
- **Layout and window:**
  - `sidebarLayout`.
  - A collapsed pill or round icon badge while hidden (`showName`, `showIcon`, `showIconOnly`).
  - Window `CreateSection` to group tabs in the rail.
  - Groups and grids (`direction` row or column, nesting).
- **Messages:**
  - `Notify`: a bottom-right card. The default duration is set automatically from text length, between 3 and 9 s. Hovering pauses it, clicking dismisses it, and at most 6 are shown.
  - `Toast`: a top- or bottom-centre pill, with an optional avatar.
  - `Popup` modal and `Tags` beside the title.
- **Elements:**
  - Named configs: `Save(name)`, `Load(name)`, `ListConfigs`, `DeleteConfig`, plus a Configurations section in the settings tab.
  - `Lock(reason)`, `Unlock`, `IsLocked`. `Set` still works on a locked element.
  - Reordering: `MoveTo`, `MoveUp`, and so on.
  - Element types `Stat` (an animated number), `Progress` and `Console` (monospace log).
- **Platform:**
  - Localization (`locale`, `translations`, `translator`).
  - Six themes.
  - Heartbeat uptime monitoring.

**WindUI (Footagesus, beta).** The current "pretty and mobile-friendly" favourite. In issue #88 the reporter says they can't switch away because it works well on mobile.
- **Window:**
  - `OpenButton` (draggable, `OnlyMobile`, `Scale`, `Color`).
  - `Tag` and topbar `ButtonsType`.
  - A window search bar (`HideSearchBar`).
  - `SetUIScale`.
  - 10+ themes including Light.
- **Elements:**
  - Section `Box`/`Opened` (collapsible boxed sections).
  - Toggle `Type="Checkbox"` and Input `Type="Textarea"`.
  - Dropdown items with `Title`, `Desc`, `Icon` and `Type="Divider"`, plus `AllowNone`.
  - Colorpicker `Transparency`.
  - Paragraph with `Image`, `Thumbnail` and `Buttons`.
  - `Image`, `Code`, and `Group`/`Space` columns.
  - `Locked`/`LockedTitle`.
- **Other:** `ConfigManager` (named configs with autoload) and a key system.

Complaints, mostly about performance:
- #88 "load too slow when script bigger": still laggy with every animation disabled.
- #77: a 5-6 s freeze when a dropdown is built from a table.
- #43: refreshing a dropdown with 100+ values freezes the UI. A fork fixed an O(N²) refresh.
- #89 "window animation is laggy".
- #96 "Animation make the game lag".
- Plus "Ui not loading" (#112), "Failed to create folder" (#111), and requests for a "disable all effects" switch.

**WindUI is proof that the market rewards Argon's exact v2 goals.** Users pick it for looks and mobile support, then fight its load times.

**Obsidian (deivid, for the mspaint hub) and Linoria.** The power-user favourite: dense, keyboard-heavy, LinoriaLib API. Features:
- **Display:** DPI scale presets (`SetDPIScale`, 50-200 %), a custom cursor, `NotifySide`.
- **Keybinds:**
  - A keybind menu with `Mode` set to Always, Toggle, Hold or Press, plus `SyncToggleState`.
  - Chained `AddColorPicker`/`AddKeyPicker` on a toggle row.
- **Toggles and buttons:** `Risky` toggles, `Tooltip` and `DisabledTooltip`, a `DoubleClick` confirm on buttons.
- **Dropdowns:** `Searchable`, `SpecialType` of Player or Team, `DisabledValues`, `MaxVisibleDropdownItems`, `FormatDisplayValue`.
- **Sliders:** `Compact`, `HideMax`.
- **Layout:** Groupbox with `Collapsed`, `Description` and `IconName`; Tabboxes.
- **Other elements:** a key tab (`AddKeyTab`/`AddKeyBox`), Image, Video, Viewport and UIPassthrough elements, dialogs, overlays, a draggable label.
- **Lifecycle and addons:** `Unload`/`OnUnload`, and SaveManager (autoload, subfolders, ignore indexes) and ThemeManager as separate add-on files.

Classic Linoria adds a watermark and dependency boxes, which show or hide controls based on other controls' state. Complaints from memory, for the Linoria lineage: small, dense text, a dated look, and add-ons fetched as separate files.

**Fluent (dawid-scripts).**
- **Praised for:** the Windows 11 look and the "Acrylic" blur.
- **Features:** Dark, Darker, Light and colour themes; dialogs; keybind modes; SaveManager and InterfaceManager add-ons with autoload.
- **How Acrylic works:** it is a port of richie0866's acrylic module. Script comments in the wild say it needs graphics quality 8+ and "may be detectable".
- **Open issues:**
  - Documentation (#52, #53)
  - Dropdowns not updating (#61)
  - Keybinds not working (#55)
  - The mobile and tablet keyboard freezes on Input (#37)
  - The window can't be dragged while a dialog is open (#30)
  - Configs fail when the script is obfuscated (#49)
  - Requests for a theme maker (#62, #40)
  - An outdated Lucide table (#32)

The README lists only three generic features.

**Luna (Nebula Softworks).** Secondhand sources only.
- Sirius-style look.
- Three label styles: plain, info and warning.
- A key system since Beta 6.
- Lucide and Material icons.
- A "home tab" dashboard.
- Config and theme saving, and a loading screen.

**Orion and Kavo.** From knowledge.
- Still widely copied, but unmaintained.
- Desktop-first, fixed-size windows, no mobile reopen, no dropdown search.
- Kavo has no config saving.
- They show what "cheap" looks like today: legacy fonts, flat greys, tiny toggles.

### 3.2 Feature matrix

"yes", "partial" or "no". "?" means not verified this session.

| Capability | Argon 1.18 | Rayfield classic | Rayfield Gen2 | WindUI | Obsidian / Linoria | Fluent |
| --- | --- | --- | --- | --- | --- | --- |
| Named config profiles plus autoload | **no** (one file, L758-767) | no | yes (with UI) | yes | yes (SaveManager) | yes (SaveManager) |
| Key / access gate | **no** | yes | ? | yes | yes (key tab) | no |
| Reopen button on touch | **no** (P1) | yes | yes (pill/badge) | yes (`OpenButton`) | yes | ? |
| Whole-UI scale / DPI | **no** | no | ? | yes | yes (50-200 %) | no |
| Light theme | **no** | yes | ? | yes | ? | yes |
| Theme editor UI | no (API only) | no | no | no | yes (ThemeManager) | no |
| Notification icon / type explicit | **no** (guessed, P3) | yes (`Image`) | yes | yes | no | yes |
| Hover-pause, auto duration | no | no | yes | ? | no | no |
| Toast pill and card | no | no | yes | no | no | no |
| Search across all tabs | **no** (per tab, P9) | no | ? | yes (window search bar) | no | no |
| Dropdown search | yes | no (#16) | yes | ? | yes | no |
| Dropdown rich options (desc / icon / divider / disabled) | no | no | no | yes | partial (disabled values) | no |
| Large-list dropdown without freezes | ? (rebuilds on every open) | ? | ? | **no** (#43, #77) | ? | ? |
| Keybind modes (Hold / Toggle / Always) | partial (`Toggle` only, keyboard only) | Hold | ? | ? | yes (4 modes) | yes |
| Keybind list overlay | yes | no | no | no | yes | no |
| Watermark / status HUD | no | no | no | no | Linoria yes | no |
| Dependency (show or lock by state) | manual `Lock` | no | no | no | Linoria yes | no |
| Collapsible sections | no | no | no | yes | yes | no |
| Grid / columns | yes (`CreateRow`) | no | yes (groups) | yes (`Group`) | yes (left/right) | no |
| Image / Code / Console / Stat blocks | no | no | Console, Stat | Image, Code | Image, Video, Viewport | no |
| Lock with visible reason | **yes** | no | yes | yes (`LockedTitle`) | `DisabledTooltip` | no |
| Tooltips | **yes** | no | ? | yes | yes | no |
| Localization | no | no | yes | ? | no | no |
| Gamepad / keyboard focus navigation | no | no | ? | ? | ? | no |
| Command palette | no | no | no | no | no | no |

Gamepad and keyboard navigation, the command palette, large-list performance and contrast-safe theming are **open ground**. Nobody in this market does them well, so they are Argon v2's best differentiators. Config profiles, a reopen button, UI scale, a light theme, explicit notification types and keybind modes are **table stakes**: their absence is what makes Argon feel behind.

---

## 4. (a) Ranked features to add or upgrade

Ranking weighs user pain × how many users it reaches, divided by effort.

**Effort scale** (one developer who knows the codebase, inside the v2 rebuild): **S** ≤ 1 day, **M** 1-3 days, **L** 3-6 days.

**Tier key:**
- **TS** = table stakes. Missing it makes Argon look behind.
- **DF** = differentiator. Nobody does it well yet.

| Rank | Feature | User problem it solves | Tier | Effort |
| --- | --- | --- | --- | --- |
| 1 | Touch-safe hide plus a floating Open button | Hiding on a phone is permanent (P1) | TS | S |
| 2 | Instant shell, lazy tab pages, skeletons, no artificial waits | 0.93-1.25 s dead time and a first-run flash (P2); WindUI's #1 complaint | TS (DF in execution) | L |
| 3 | Readability: whole-UI scale, a text floor, contrast-safe roles (`OnAccent`, Hover step) | Small text, unreadable accent labels (P4, P5) | TS | M |
| 4 | Shared popover engine (anchor, flip, clamp, follow scroll, outside-dismiss, Esc, one at a time, shadow) | Menus open off-screen and detach (P7). Every overlay control depends on this. | TS (foundation) | M |
| 5 | Dropdown v2: virtualized, keyboard, rich options, chips, async/player sources, bottom sheet on phone | Freezes with big lists (WindUI #43, #77), missing options and states | TS + DF | M |
| 6 | Config profiles manager (named, autoload, import/export string) | One file only; users can't keep a "safe" and an "experimental" setup | TS | M |
| 7 | Notifications v2 (Type/Icon/Image, actions, hover-pause, auto duration, coalesce by `Id`, `Update`/`Dismiss`, toast pill, optional inbox) | Wrong colours from title guessing (P3), no way to act on a notice | TS + DF | M |
| 8 | Global search and command palette (Ctrl+K and `/`) | Can't find a setting without knowing its tab (P9) | DF | M |
| 9 | Keyboard focus mode and gamepad navigation | Controllers are unusable; no keyboard flow (P8) | DF (TS on console) | L |
| 10 | Rayfield parity: `KeySystem`/`KeySettings` gate, `LoadingTitle`/`LoadingSubtitle`, Notify `Image`, `HoldToInteract`, window `Icon` | Migrated scripts silently lose behaviour, including their access gate (P15) | TS (API promise) | M |
| 11 | Keybind v2 (Mode Toggle/Hold/Press/Always, mouse and gamepad buttons, modifiers, conflict warning, Esc cancels, capture timeout) | Keyboard-only binds; Esc wipes the bind; no hold mode | TS | M |
| 12 | Information architecture: collapsible sections, sidebar tab groups, host-set badges, remove fake chrome, grouped-list rows | Long pages, noise (P10, P13) | TS | S-M |
| 13 | Themes: Light and High-contrast built-ins, seed-based generator, live theme editor plus export/import | Dark only (P14); custom themes need code | TS + DF | M |
| 14 | Component state upgrade (button variants and busy state, checkbox, input validation / numeric / mask, slider keyboard / reset / range, colour alpha and swatches) | Controls lack the states users expect from apps (details in controlsA.md) | TS | M-L |
| 15 | Reduce-effects / reduced-motion switch plus a motion budget | WindUI users ask to "disable all effects"; motion sickness; low-end devices | TS | S |
| 16 | Content blocks: `Image`, `Code`/`Console`, `Stat`, `Callout`, window `Tag` | Hosts fake these with Paragraphs | TS | M |
| 17 | Declarative dependencies (`DependsOn`) | Hand-written `Lock`/`SetVisible` wiring that drifts out of date | DF | S |
| 18 | Per-control context menu (Reset to default, Copy/Paste value, Copy flag, Pin) plus undo toasts | No way back after experimenting | DF | M |
| 19 | Quick dock: pinned controls in a floating mini bar while the window is hidden | On touch, the big window covers the game; users only need 3-5 toggles mid-session | DF | M |
| 20 | Watermark / status HUD (title, FPS, ping, clock, custom fields) | Standard in the Linoria lineage | TS (power users) | S |
| 21 | Localization (`Locale`, `Translations`, `Argon:SetLocale`) | Non-English audiences; Gen2 has it | DF | M |
| 22 | Announcement / "What's new" shown once per version | Hosts can't tell users about changes; WindUI #101 asks for a welcome pop-up | DF | S |

### 4.1 Specs and API sketches for the top items

All of these are additive option keys, so existing scripts keep working.

**F1. Open button and touch-safe hide (rank 1).**

```lua
Argon:CreateWindow({ Name = "My Hub",
    OpenButton = { Enabled = "auto", Icon = nil, Text = nil, Draggable = true, Side = "Left" } })
Window:SetOpenButton({ Enabled = true })   -- returns the button handle
```

- **When it shows.** `"auto"` shows the button whenever the window is hidden and `PreferredInput ~= KeyboardAndMouse`. It also shows on every input type if the toggle key is `None`.
- **Size.** A 48x48 round badge, or a pill up to 160 px wide when `Text` is set.
  - Fill: `Window` at 0.06 transparency.
  - Stroke: 1 px white at 0.85.
  - Shadow: the 9-slice shadow from section 7.
  - Contents: the logo or icon at 22 px.
- **Position.**
  - Placed under `ScreenInsets = CoreUISafeInsets`, so it never sits under the Roblox top bar.
  - Defaults to the left edge at 30 % height, clear of the thumbstick (bottom-left) and jump button (bottom-right).
  - After a drag it snaps to the nearest vertical edge with a spring (ζ 0.8).
  - The position is saved with the UI preferences.
- **Dragging.** Prefer `UIDragDetector` with `BoundingUI` set to the screen. Fall back to a manual drag with a 6 px threshold so taps aren't read as drags. This is the fix for Rayfield's "Mobile dragging is really weird" (#27).
- **Hide and minimise.** The "–" button becomes "Minimise to button". The first time, a toast says how to reopen ("Tap the badge or press Insert").

**F2. Instant shell (rank 2).** The UX contract; the perf audits cover the implementation.

| Moment | Contract |
| --- | --- |
| Frame 0 (`CreateWindow` returns) | Shell at its final size: sidebar, brand, search trigger, topbar. Tabs appear as `CreateTab` is called. No shrink-and-grow pill. |
| Icons | Drawn from the bundled atlas immediately. The Lucide index is never fetched on the critical path. |
| Avatar | An initials circle in the user's colour; the headshot fades in (0.2 s) when the async fetch returns. |
| Tab content | Built on first visit, plus idle-time pre-building in tab order, in ≤4 ms slices per frame. A tab whose build takes more than 150 ms shows skeleton rows; under 150 ms shows nothing, so there is no flash. |
| Window open | 0.28 s (UIScale 0.97→1 plus shadow fade). Clickable from the first frame of the animation. |
| `SetLoadingProgress` / `FinishLoading` | Kept. They drive a 2 px progress hairline under the topbar and a status line in place of the subtitle. The content area shows skeletons. Only `Loading = "manual"` keeps a blocking cover, and that cover sits inside the content area, not over the window. |
| Rayfield `LoadingTitle`/`LoadingSubtitle` | Shown in that cover when given. |
| Never | Minimum-duration timers, staggered entrances that block input, network or file I/O before first paint. |

The lazy model stays source-compatible. `Create*` returns the element handle immediately, with its value, flag and methods live. Only the instances are deferred, so search, flags, `Set` and `LoadConfiguration` all work on tabs that haven't been built yet.

**F3. Readability and scale (rank 3).**
- **Scale.** `CreateWindow({ Scale = "auto" | number })` and `Window:SetScale(n)` (0.8-1.5), plus a slider in `CreateLibrarySettings`. One `UIScale` on the window root, and the same factor on the popover, toast and overlay layers.
- **Auto scale rules** (by viewport short side):
  - under 500 px (phone) → 1.15 with touch density;
  - 500-800 px → 1.0;
  - ≥ 1440 px tall → 1.1.
- **Text.**
  - A text floor of 12 px rendered for captions, 13-14 px for body, 14 px for control labels (see 6.1).
  - TextSize is always a whole number, including after scaling.
  - Text sizes are no longer passed as fractions.
- **Roles.** New palette roles `OnAccent`, `AccentSoft`, `Focus`, `Scrim` and `Raised`, derived automatically when a custom theme omits them (section 6.1).

**F4. Popover engine (rank 4).** One module used by the dropdown, colour picker, theme menu, context menu, tooltip and command palette. Spec in 6.9.

**F5. Dropdown v2 (rank 5).**
- **Trigger.** 36 px tall (44 on touch). Shows the value, or for multi-select up to 2 chips plus "+N". The chevron rotates 180° in 0.16 s.
- **Popover.**
  - Width: `max(trigger, 220)`.
  - Height fits the content: `min(rows × 32 + chrome, 8.5 rows, space available)`.
  - A half row stays visible at the bottom, so it's obvious the list scrolls.
- **Virtualization.** A pool of `visibleRows + 2` row instances, repositioned on `CanvasPosition` change. `Refresh` with 10,000 options costs O(N) table work and **zero** new instances.
- **Keyboard.**
  - Up/Down move the highlight; Home/End jump.
  - Enter selects; Space toggles in multi mode.
  - Typing goes to the filter.
  - Esc closes, and clears the filter first if it has text.
- **Touch.**
  - Below 520 px viewport width the dropdown opens as a bottom sheet with 48 px rows.
  - The filter field is **not** auto-focused, so the keyboard doesn't jump up (Fluent #37).
- **Options.**
  - `Options` accepts strings or `{ Text, Description, Icon, Disabled, Divider = true }`.
  - `Source = "Players"` / `"Teams"` auto-refreshes on PlayerAdded and PlayerRemoving (Obsidian's `SpecialType`).
  - `Options = function() ... end` loads asynchronously, with a spinner row.
- **Multi-select.** A "Select all · Clear" header row, and a check icon on selected rows.

**F6. Config profiles (rank 6).** Every existing signature keeps working because the `name` argument is optional. `DeleteConfiguration` already exists at L933, and `LoadConfiguration` at L1019 takes no name today.

```lua
Argon:SaveConfiguration(name?)  Argon:LoadConfiguration(name?)
Argon:ListConfigurations()  --> { {Name, Modified, Autoload} }
Argon:DeleteConfiguration(name?)  Argon:RenameConfiguration(old, new)
Argon:SetAutoloadConfiguration(name)  -- loaded by LoadConfiguration() with no argument
Argon:ExportConfiguration(name?) --> string (JSON, base64)   Argon:ImportConfiguration(str, name)
Window:CreateConfigSection(tab)   -- also added by CreateLibrarySettings
```

- **UI.** A `List` with per-row Load / Rename / Delete actions (the existing row-actions component), a "Save current as…" input plus primary button, and an autoload star per row.
- **Delete.** Uses hold-to-confirm, with an Undo toast lasting 6 s.
- **Copy.** "Copy" uses `setclipboard` when available. When it isn't, a read-only text area is shown instead.
- **Empty state.** "No saved profiles yet" with the save action.

**F7. Notifications v2 (rank 7).** Spec in 6.12.

```lua
local n = Argon:Notify({ Title = "Profile saved", Content = "PvP", Type = "success", Icon = "save",
    Duration = "auto", Id = "save", Actions = { { Text = "Undo", Callback = undo } } })
n:Update({ Content = "PvP (2)" })  n:Dismiss()
Argon:Toast({ Title = "Copied", Icon = "copy" })   -- small centred pill
```

- `Type` wins over everything else. The keyword guess stays only as a fallback for old scripts, with whole-word matching so "Unsaved" no longer turns green.
- `Image` (Rayfield) is an alias for `Icon`.

**F8. Command palette (rank 8).** Spec in 6.13. A host API for custom commands:

```lua
Window:RegisterCommand({ Name = "Rejoin server", Icon = "refresh-cw", Keywords = { "reconnect" }, Callback = fn })
```

**F9. Focus and gamepad (rank 9).** Specs in 6.5-6.7. Argon runs its own focus engine (roving index over the element registry, plus its own ring). It does not rely on `GuiService` selection, because `SelectedObject` only covers PlayerGui and the window lives in CoreGui or `gethui()`. While focus mode is active, navigation input is sunk with `ContextActionService:BindActionAtPriority`, so the character doesn't jump when the user presses A or Space on a control.

**F10. Rayfield parity (rank 10).**
- **Key gate.** `KeySystem = true, KeySettings = { Title, Subtitle, Note, FileName, SaveKey, GrabKeyFromSite, Key = {...} }` shows a provider-agnostic access gate:
  - a centred card with a 44 px input, "Get key" (copies `Note`/link to the clipboard), "Continue";
  - an error shake (±6 px, 3 cycles in 0.3 s) and a Danger message on a wrong key;
  - a remembered key that skips the gate next time.
- **Validation.** A generic `Validate = function(key) return ok, message end` covers custom checks, with a busy state while it runs.
- **Other options.** `LoadingTitle`/`LoadingSubtitle` feed the F2 cover. `HoldToInteract` maps to `Mode = "Hold"`. Window `Icon` maps to `Logo`.

**F11. Keybind v2 (rank 11).**

```lua
Tab:CreateKeybind({ Name = "Toggle overlay", CurrentKeybind = "Q", Mode = "Toggle",
    AllowMouse = true, AllowGamepad = true, Callback = fn, OnChanged = fn })
```

- **Mapping.** `Toggle = true` maps to `Mode = "Toggle"`.
- **Capture.**
  - Shows "Press a key…" with a 5 s countdown ring.
  - Esc **cancels** and keeps the old key. This changes L2438, where Esc clears the bind. Backspace or Delete clears to None.
  - Mouse buttons 2-5 and gamepad buttons are accepted.
  - Modifier chords such as `Ctrl+Q` are accepted.
- **Conflicts.** A duplicate binding shows an inline warning: "Also used by: Speed toggle".
- **Keybind list overlay.** Shows mode and state, for example `Q · Hold · Active`.

**F12. Information architecture (rank 12).**
- **Sections.** `Tab:CreateSection({ Name, Icon, Description, Collapsible = true, Collapsed = false })`. The header is a 36 px row with a chevron, and the collapsed state is saved per section.
- **Sidebar groups.** `Window:CreateTabGroup("Combat")` (or `Window:CreateSection`, as in Gen2) adds a 12 px caption in the rail.
- **Badges.** `Tab:SetBadge(n | "dot" | nil)` is host-controlled and replaces the control count.
- **Removed.** The "LIVE" pill, "ARGON ONLINE" and the "ARGON /" eyebrow. Replacements:
  - the eyebrow shows the tab group or nothing;
  - the profile line shows `@username`;
  - the status pill appears only if the host calls `Window:SetStatus("Connected", "success")`.

**F13. Themes (rank 13).**
- **Generator.** `Argon:CreateTheme({ Base = Color3, Accent = Color3, Contrast = 0.0-1.0, Mode = "Dark" | "Light" })` builds a full palette by stepping lightness in OKLab, Linear's three-variable method. It enforces the section 6.1 contrast targets and computes `OnAccent`.
- **New built-ins.** "Daylight" (light) and "High Contrast".
- **Editor.** `Window:CreateThemeEditor(tab)` gives seed pickers, a live preview, "Save as theme", and theme export/import as a string.
- **Picker.** The topbar theme picker shows Surface, Accent and Text in each swatch instead of three accent dots. The current dots make similar themes look identical.

**F15. Reduce effects (rank 15).**
- `Argon:SetReducedMotion(true)`, plus a settings toggle, plus `CreateWindow({ ReducedMotion = "auto" })`.
- **Effect.** Slides, scales and springs become instant. Fades are capped at 0.1 s. Loops (spinner excepted) and shimmer stop. Window translucency drops to 0.
- **Motion budget.** At most 3 looping tweens on screen at once. Spinners count; decoration doesn't loop.

**F16. Content blocks (rank 16).**
- `Tab:CreateImage({ Image, AspectRatio, Caption, Radius })`.
- `Tab:CreateCode({ Title, Content, MaxLines = 200, Copy = true })`, with `:Append(line)` and `:Clear()`.
  - RobotoMono at 13 px, line numbers optional, auto-scroll that pauses while the user has scrolled up.
- `Tab:CreateStat({ Name, Value, Format, Trend = true })`.
  - The number animates over 0.4 s in tabular mono.
  - The delta shows in green or red with an arrow icon.
- `Tab:CreateCallout({ Type, Title, Content, Action })`.
- `Window:CreateTag({ Text, Color, Icon })`: a pill beside the title.

**F17. Dependencies (rank 17).**

```lua
Tab:CreateSlider({ Name = "Music volume", Flag = "Volume",
    DependsOn = { Flag = "MusicEnabled", Equals = true, Mode = "Lock", Reason = "Turn music on first" } })
```

- `Mode = "Hide"` collapses the control with a 0.16 s height tween.
- `"Lock"` reuses the existing badge.
- `Equals` accepts a value, a list, or a predicate function.

**F18. Context menu and undo (rank 18).**
- **Opening it.** Right-click, a 450 ms long-press on touch, or X on a gamepad.
- **Items.**
  - "Reset to default (60)", showing the default value.
  - "Copy value" / "Paste value", using an internal clipboard (`setclipboard` too when available).
  - "Copy flag name".
  - "Pin to quick dock".
- **Undo.** Any reset or paste raises a toast with **Undo** (6 s).

**F19. Quick dock (rank 19).**
- **What it holds.** Pinned toggles, buttons and steppers render as 40 px icon-plus-label chips in a draggable floating bar. The bar is visible while the window is hidden, and its position and pins are saved.
- **Limits.** At most 6 chips. Overflow goes into a "…" menu.

---

## 5. Where Argon is already ahead, and how to market it

The README should lead with:
- Rows that collapse.
- Lock with a reason.
- Verified autosave.
- Tooltips that never cover the control.
- Pinned overlays.
- Single file, no add-on downloads (Fluent and Obsidian need separate files).

Plus, after v2:
- An instant first paint.
- The command palette.
- Gamepad support.
- 10k-option dropdowns.

These are concrete claims a user can test in seconds. Competitors advertise "modern" and "beautiful".

---

## 6. (b) UX patterns to adopt, with concrete specs

### 6.1 Tokens

**Spacing.** A 4 px grid.
- Tokens: 4, 8, 12, 16, 20, 24, 32.
- Window padding: 20 on desktop, 12 below 760 px wide.
- Row padding: 14 horizontal.
- Gap between rows: 0. Rows are divided by hairlines (6.11).
- Gap between sections: 20.
- Gap from section header to card: 8.

**Radii.** Concentric. The rule: inner radius = outer radius − inset, minimum 4.

| Element | Radius |
| --- | --- |
| Window | 16 |
| Cards, sections, popovers, toasts, dialogs | 12 |
| Rows and row hover fills (4 px inset in the card) | 8 |
| Inputs, wells, buttons, chips | 8 at 36 px tall, 6 at 28-32 px |
| Toggle tracks, pills, avatars, open badge | full (height / 2) |

Today the radii are 16 → 13 → 10 → 9, with 8 px insets. Those aren't concentric, so the gaps at the corners are uneven.

**Type scale.** Whole pixels at scale 1. Faces must load in a live client.

| Role | px | Weight | Face |
| --- | --- | --- | --- |
| Caption / meta / breadcrumb | 12 | Medium | Body (Roboto or BuilderSans) |
| Description / body | 13 (desktop), 14 (touch) | Regular | Body |
| Control label | 14 | Medium | Body |
| Value readout, keybind, hex, stats, code | 13 | Medium | RobotoMono (tabular, so digits don't jitter while dragging) |
| Section header | 13 | SemiBold, **sentence case** | Body |
| Window brand | 15 | SemiBold | Display (Montserrat or BuilderSans) |
| Dialog title | 17 | SemiBold | Display |
| Page title | 20 | SemiBold | Display |

What changes from today:
- The 8-10 px ALL CAPS GothamBold/Black micro-labels (NAVIGATION, JUMP TO, LIVE, ARGON ONLINE) are dropped. Roblox has no letter-spacing control, so small uppercase text reads cramped.

**Colour roles.** New roles, derived automatically when a theme omits them:

| Role | Definition | Target |
| --- | --- | --- |
| `OnAccent` | White or Background, whichever has higher contrast on Accent | ≥ 4.5:1 |
| `AccentSoft` | Accent at 0.86 transparency over Surface (selection fills) | — |
| `Focus` | AccentLight (or Accent in light themes) | ≥ 3:1 against Window and Surface |
| `Raised` | Window lightened 4 % (L in OKLab) for popovers and toasts | ≥ 1.12:1 vs Window |
| `Scrim` | Background, used at 0.35 transparency | — |
| `Hover` | Surface stepped so Hover/Surface ≥ 1.12:1 | today 1.06-1.20 |
| `Surface` | Surface/Window ≥ 1.15:1 | today 1.06-1.19 |

Text targets:
- `Text` ≥ 7:1 on Surface.
- `Muted` ≥ 4.5:1. Use it for descriptions.
- `Dim` ≥ 3:1. Only for text ≥ 14 px or non-essential hints. Placeholders should use `Muted` at 0.2 transparency.

Status colours (Success, Warning, Danger) are used only for status, never for decoration.

### 6.2 Hit targets and density

| Input (`PreferredInput`) | Row height | Minimum hit area | Minimum icon-button visual | Gap between targets |
| --- | --- | --- | --- | --- |
| KeyboardAndMouse | 40 (compact) / 44 (default) | 32x32 | 24x24 visual inside a 32x32 hit area | 4 |
| Touch | 52 | 44x44 | 32x32 | 8 |
| Gamepad | 48 (the whole row is the focus target) | the row | — | — |

How hit areas grow:
- Hit areas grow with an invisible `TextButton` bigger than the visual. Visuals don't change.
- A slider's visual track can stay 4-6 px, but its input frame is 24 px tall (32 on touch).
- While a slider is being dragged, `ScrollingEnabled = false` on the page, so a vertical wobble doesn't scroll it.
- Density follows `PreferredInput` live, via `GetPropertyChangedSignal("PreferredInput")`. A tablet that plugs in a controller switches to gamepad density.

### 6.3 Motion

Durations in seconds. M3 standard and emphasized easings map to Roblox `Quart Out` and `Quint`/`Exponential Out`, with M3's short and medium duration bands (50-400 ms).

| Token | Duration | Roblox easing | Use |
| --- | --- | --- | --- |
| `hover` | 0.10 | Quad Out | fill, stroke and icon tint changes |
| `press` | 0.06 down / 0.14 up | Quad Out | `UIScale` 1 → 0.97 → 1 on buttons and rows |
| `state` | 0.16 | Quart Out | toggle track colour, checkbox fill, segmented label colour |
| `spring` (spatial) | settles in about 0.25 s | spring stepper, ζ 0.8, ω 20 rad/s (about 1.5 % overshoot) | toggle knob, segmented pill, tab indicator, slider snap, open-badge edge snap |
| `pop-in` | 0.18 | Quint Out, `UIScale` 0.96 → 1 from the anchor side, plus fade | dropdown, menus, colour picker, palette (tooltip 0.12) |
| `pop-out` | 0.10 | Quad In | all popovers |
| `page` | 0.22 | Quint Out, 8 px slide, **no CanvasGroup** | tab switch |
| `dialog` | 0.24 in / 0.14 out | Quint Out / Quad In, `UIScale` 0.95 → 1, scrim 0.18 | dialogs, key gate |
| `window` | 0.28 | Quint Out, `UIScale` 0.97 → 1, shadow fade | open/close, minimise to badge |
| `toast` | 0.30 in, 0.16 out plus 0.18 height collapse | spring in from 16 px off the edge; Quad In out | notifications |
| `shimmer` | 1.2 s loop | Linear (UIGradient `Offset`) | skeletons only |
| `spinner` | 0.8 s per turn | Linear | busy states only |

Rules:
- **Interruptible.** Always tween from the current value. Roblox cancels a running tween on the same property, so never wait for one to finish.
- **Stagger.** At most 20 ms per item, at most 6 items, and never blocking input.
- **Back easing.** Roblox `Back` overshoots about 10 %. That is fine for an 18 px knob and wrong for a 380 px dialog panel (L1610 uses Back for the dialog). Use the spring stepper for anything bigger than a chip.
- **Spring stepper.** One shared `Heartbeat` connection drives all active springs: `a = -ω²(x - target) - 2ζω·v`. It disconnects when nothing is moving.
- **Reduced motion.** Spatial tokens become 0. Fades are at most 0.10 s.

### 6.4 State model, the same for every control

| State | Visual (dark themes) |
| --- | --- |
| Rest | The row has no fill. Label `Text`, description `Muted`. |
| Hover (mouse only) | Row fill `Hover` (≥ 1.12:1), radius 8, inset 4 px, `hover` token. Never shown on touch (avoids sticky hover). |
| Pressed | `UIScale` 0.97 on the interactive part plus `Active` fill, `press` token. |
| Focus-visible | Ring (6.5). Shown only after keyboard or gamepad input. |
| Selected / on | `AccentSoft` fill or `Accent` track; label stays `Text`; the glyph turns `Accent`. |
| Disabled | Content at 0.5 transparency, no hover, `Interactable = false`. The reason appears in the tooltip or description. |
| Locked | Today's scrim and badge, plus `Interactable = false`. |
| Busy | Spinner replaces the icon, width is frozen, re-entry is blocked, and the callback runs in `task.spawn`. |
| Error | 1 px `Danger` stroke on the field plus a 12 px `Danger` message under it. A shake (±4 px, 0.24 s) only on submit. |
| Changed from default | A 4 px `Accent` dot after the label. A click on the dot opens "Reset to default". |

### 6.5 Focus treatment

- **Ring.** A separate ring frame per window, moved to the focused element: the element's size + 4 px (a 2 px gap), radius = element radius + 2, and a 2 px `Focus` `UIStroke` at transparency 0.
- **Animation.** It travels between elements with the `spring` token, so focus is easy to follow across a page. It appears with a 0.10 s fade.
- **When it shows.** Only when the last input was a key or a gamepad, the same idea as CSS `:focus-visible`. A mouse click focuses without showing the ring.
- **Scrolling.** The focused row is scrolled into view with a 24 px margin.
- **Trapping.** Focus is trapped in the dialog, palette and open popover. Closing them returns focus to the trigger.

### 6.6 Keyboard map

Roblox has its own key conventions:
- Tab toggles the CoreGui player list.
- Arrow keys and WASD move the character.
- `/` opens chat in some games.

So navigation keys only act inside **focus mode**. Focus mode starts when the palette is opened, when a nav key is pressed while the cursor is over the window, or when a control is clicked. It ends on Esc, on a click outside the window, or when the window hides. While it is active, `ContextActionService:BindActionAtPriority(…, Enum.ContextActionPriority.High.Value + 1, …)` sinks arrows, Enter, Space and Tab. Text boxes keep their own handling.

| Key | Action |
| --- | --- |
| Host toggle key (default Insert) | Show or hide the window (kept) |
| Ctrl+K, or `/` while not typing | Command palette |
| Esc | Close the topmost layer: popover → dialog → palette → clear search → leave focus mode. It never hides the window. |
| Ctrl+1 to Ctrl+9 | Jump to tab N |
| Ctrl+] / Ctrl+[ (also Ctrl+Tab) | Next / previous tab |
| Up / Down | Previous / next control (roving). In lists and menus, previous / next item. |
| Left / Right | Adjust the value: slider and stepper ±1 step, segmented ±1 option, toggle off/on |
| Shift + Left / Right, PageUp / PageDown | ±10 steps |
| Home / End | Minimum / maximum, or first / last item |
| Enter, Space | Activate: toggle, press a button, open a dropdown or colour picker, start keybind capture |
| Shift+F10, or the Menu key | Context menu for the focused control |
| Inside a dropdown | Up/Down highlight, Enter select, Space toggle (multi), type to filter, Esc close (clears the filter first) |
| Keybind capture | Any key binds. Esc cancels and keeps the old key; Backspace/Delete set None. 5 s timeout. |
| Destructive dialog | Focus starts on **Cancel**. Enter activates the focused button, Esc cancels. |

### 6.7 Gamepad map

Xbox naming. Roblox reports these as `KeyCode.Button*` and `DPad*`.

| Input | Action |
| --- | --- |
| Host toggle (default none; suggest hold ButtonSelect for 0.4 s) | Show or hide. A plain ButtonSelect press already toggles Roblox's own GUI selection, which is why a hold is needed. |
| D-pad / left stick | Move focus. Stick repeat: 350 ms initial delay, then 90 ms. |
| A | Activate |
| B | Back: close the layer, or leave focus mode |
| X | Context menu (reset / copy / pin) |
| Y | Command palette |
| LB / RB | Previous / next tab |
| LT / RT | Page up / down |
| Right stick | Scroll the page freely |
| D-pad Left / Right on a value | Adjust ±1 step (hold to repeat; accelerates after 1 s) |

- **Hint bar.** A 32 px bar at the bottom of the window shows glyph chips for the current context, for example "A Select · B Back · X Options · Y Search". It shows only while `PreferredInput == Gamepad`.
- **Opening.** If the window opens while `PreferredInput == Gamepad`, focus mode starts automatically on the last focused control.

### 6.8 Touch

- **Hit areas.** 44x44 minimum (6.2).
- **Hover.** Nothing depends on hover. Hover visuals are suppressed on touch.
- **Long-press (450 ms).** Shows the tooltip, or the context menu if the control has no tooltip. It releases without activating the control. Today the README admits that tooltips need a mouse.
- **Window drag.** By the title bar only, with a 6 px threshold. The window is clamped so at least 64 px of the title bar stays on screen (fixes P12). Double-tapping the title bar centres the window.
- **Dropdowns and colour pickers below 520 px width.** These become bottom sheets:
  - full width minus 16 px;
  - radius 16 at the top;
  - a grab handle (36x4 at 0.6 transparency);
  - swipe down more than 80 px to close.
- **Toasts.** Top centre on phones, swipe sideways to dismiss. The Open button and dock stay clear of the bottom corners, where the thumbstick and jump button are.
- **Insets.** `ScreenInsets = CoreUISafeInsets` on the overlay and toast layer.
- **Text fields.** Never call `CaptureFocus` on touch automatically.

### 6.9 Popover rules (one engine)

1. **Anchor.** Anchored to the trigger. Preferred side below, with a 6 px offset. Flips above when the space below is less than the popover height plus 8. Shifted horizontally to stay at least 8 px inside the viewport.
2. **Size.** Height fits the content, capped by the space available. Scrolls inside when capped.
3. **Following.** Follows the trigger on scroll and window drag, recomputed on `AbsolutePosition` change. It closes if the trigger scrolls out of the visible page.
4. **Dismissal.**
   - Outside click or tap closes it. A transparent full-screen catcher sits behind the popover, so the click is not passed to the game.
   - Esc and B close it.
   - Opening another popover closes the current one.
   - Hiding the window closes it.
5. **Look.** `Raised` fill, a white 1 px stroke at 0.88, radius 12, and the shared 9-slice shadow (section 7).
6. **Motion.** The `pop-in` token from the anchor side.
7. **Hover-opened popovers** (tooltips): 500 ms open delay, 300 ms skip delay when moving between controls (Radix defaults are 700/300), and no delay on focus-visible.

### 6.10 Empty, loading and error states

| Where | State | Content |
| --- | --- | --- |
| Palette / search | No results | `search-x` icon (24, `Dim`), "No matches for 'foo'" (14 `Text`), "Try fewer letters" (13 `Muted`) |
| Palette | Empty query | Recent (5) and Pinned |
| Tab search (if kept) | Filtered empty | The same block, plus a "Search all tabs" button that opens the palette |
| List | Empty | Icon plus `EmptyText`, plus an optional `EmptyAction = { Text, Callback }` button |
| Dropdown | No options / filtered | "No options" / "No match · Clear filter" |
| Config profiles | Empty | "No saved profiles yet" plus primary "Save current as…" |
| Notification inbox | Empty | "You're all caught up" |
| Any async area | Waiting < 150 ms | Nothing, so there is no flicker |
| Any async area | Waiting 150 ms to 1 s | Skeleton rows: `Surface` bars 12 px tall, radius 6, shimmer token |
| Any async area | Waiting > 1 s | Skeleton plus a status line ("Loading players…") |
| Callback error | Caught by `safeCall` | Today it only `warn`s (L157-161). Proposed: a small Danger dot on the control, and a toast "Auto farm failed: <message>" with a "Copy error" action. Host opt-out: `ShowCallbackErrors = false`. |

### 6.11 Layout: grouped lists instead of a box inside a box

- **Sections.** A section is **one** card (radius 12, `Surface`, no stroke or a white stroke at 0.94).
- **Rows.** Rows inside a card have no fill and no stroke at rest. They are separated by 1 px `BorderSoft` dividers at 0.4 transparency, inset 14 px on the left. Hover fills the row (radius 8, inset 4).
- **Wells.** Inputs keep a well (`Input` fill, 1 px stroke) because they are editable surfaces.
- **Instances.** This saves a `UICorner` and a `UIStroke` per control, about 2 instances × N.
- **Section headers.** Sit outside the card: 13 SemiBold `Muted`, sentence case, an optional 16 px icon, and the chevron when collapsible. The 3x10 accent bar (L1763) goes.
- **Sidebar selection.** One shared indicator moves between tabs with the spring token: an `AccentSoft` pill (radius 8) plus a 3 px `Accent` bar. This replaces the per-tab `Accent` frames (L1698) and the solid accent icon plate with a white glyph, whose contrast is 1.29-3.43:1.

### 6.12 Notifications (full spec)

- **Position.** Configurable: `TopRight` (default on desktop), `BottomRight`, `TopCenter` (default on phone), `BottomCenter`, `BottomLeft`. Pushed clear of pinned overlays, as L1368 already does.
- **Width.** 340 on desktop; `min(360, viewport − 32)` on phone.
- **Anatomy.**
  - A 32 px plate (type colour soft) holding a 18-20 px icon.
  - Title: 14 SemiBold.
  - Body: 13 `Muted`, wrapped, at most 4 lines, then "Show more".
  - An optional row of up to 2 actions (28 px, Ghost plus Primary).
  - Close: a 24 px visual in a 32 px hit area. Shown on hover on desktop and always on touch.
  - A 2 px progress hairline at the bottom that pauses on hover or focus.
- **Duration.**
  - `"auto"` = clamp(2.5 + 0.06 × characters, 3, 9) s.
  - `Type = "error"` is ×1.5.
  - A notification with actions stays at least 8 s.
  - `math.huge` makes it sticky.
- **Stack.**
  - At most 4 visible. Older ones collapse into a "+N more" chip that opens the inbox.
  - A second notification with the same `Id` updates in place and shows "×2". This dedupes spam.
- **Motion.**
  - Enter: `toast` spring. Exit: fade, then height collapse, so neighbours slide rather than jump.
  - Capped items leave with the same exit animation; today they are destroyed instantly (L1217).
- **Inbox (optional).** `Window:SetNotificationInbox(true)`: a bell in the topbar with an unread dot, the last 50 entries, "Clear all", and an empty state.
- **Accessibility.** Type is never shown by colour alone: each type has its own icon (`info`, `circle-check`, `triangle-alert`, `circle-x`).

### 6.13 Command palette (Raycast-style)

- **Opening.** Ctrl+K, `/`, the sidebar search field (now a button labelled "Search… Ctrl K"), or Y on a gamepad.
- **Panel.**
  - 560 x `min(440, 70 % of viewport height)`, centred horizontally, top edge at 18 % of window height.
  - `Raised` fill, shadow, scrim at 0.35 over the window area only.
- **Input.** 44 px, 15 Regular, placeholder "Search settings and commands".
- **Rows.**
  - 40 px tall (48 on touch).
  - A 16 px icon, then the title with the matched characters bolded through RichText.
  - On the right, the breadcrumb "Tab › Section" (12 `Muted`) and a live value chip ("On", "60 %", "Q").
- **Groups.** Best match, Settings, Commands (host-registered plus built-ins: theme, scale, overlays, save profile), Recent.
- **Matching.**
  - Weighting: word-prefix > contiguous substring > subsequence (fuzzy), plus a boost for recent use.
  - Fields searched: `Name`, `Description`, `Tooltip`, section, tab, dropdown and segmented options, `Keywords`.
  - The index is built from the element registry, so it works for tabs that haven't been built yet (F2).
- **Actions.**
  - Enter goes to the control: switch tab, scroll it into view, and pulse the focus ring twice (2 × 0.4 s).
  - Ctrl+Enter, or X on a gamepad, runs it in place: flip a toggle, press a button.
  - Left/Right on a slider result adjusts it in place.
- **Footer hint bar.** Glyphs follow `PreferredInput`, for example "↵ Go to · Ctrl ↵ Run · Esc Close" or "A Go to · X Run · B Close".
- **Empty states.** As in 6.10.

---

## 7. (c) Anti-patterns to avoid (seen in competitors, and in Argon itself)

1. **Faking blur by touching the game world.** Fluent's Acrylic is a port of richie0866's acrylic module. Script comments in the wild say it needs graphics quality 8+ and "may be detectable". A UI library must never change Workspace, Lighting or the Camera. Argon's "glass" look should come from the recipe in section 8.
2. **Loading UI from external assets or extra files at runtime.**
   - Rayfield classic loads its UI through `game:GetObjects` (issue #47).
   - Fluent and Obsidian download add-ons separately (SaveManager, ThemeManager, InterfaceManager).
   - Argon itself fetches the Lucide index over HTTP on first icon draw (L339-389).

   Ship one file with icons bundled.
3. **Animation nobody budgeted.** WindUI #89 and #96 say the animations lag. #88 says it is still slow with them off. Users end up asking for "disable all effects". Budget motion (6.3, F15) and measure it.
4. **Rebuilding a whole list on every change.** WindUI #43 (an O(N²) refresh) and #77 (a 5-6 s freeze). Argon's dropdown rebuilds all options on every open (L2529-2540). Virtualize.
5. **Splash screens with minimum timers.** Argon's 0.93 s floor (L3359), and loading screens in Luna and WindUI. Never make a ready UI wait; show progress only for real pending work.
6. **Modals that block everything.** Fluent can't drag the window while a dialog is open (#30). Key gates often grab focus with no way out. Dialogs should cover only the window area, allow dragging the window, and close with Esc or B.
7. **Auto-focusing text fields on touch.** Fluent's mobile keyboard freezes on Input (#37). Never auto-focus on touch: no dropdown filter, no palette input.
8. **Guessing meaning from text.** Argon picks notification severity from words in the title (L1153-1156). Use explicit types.
9. **Status chrome that means nothing.** Argon's "LIVE" breathing pill, "ARGON ONLINE" and "ARGON / TAB" (P10). Decoration that looks like status wears trust down.
10. **Text glyphs as icons.** "→", "–", "×", "+" (P11), and Kavo/Orion-era UIs in general. Use one icon family at one stroke weight.
11. **Dense micro-type.** 9-11 px ALL CAPS labels (Linoria lineage, and Argon's captions). Small uppercase text without letter-spacing looks cramped and fails on phones.
12. **Window chrome that can be lost.** Unclamped dragging (Argon L3089) and no reopen button on touch (Argon P1, Kavo, Orion). Rayfield #27 shows the drag needs a threshold and bounds.
13. **Settings forced into the host's UI.** Some libraries auto-inject a settings tab. Argon's opt-in `CreateLibrarySettings` is right; keep it opt-in.
14. **Hover-only information.** Tooltips as the only home for key information, and hover-only affordances. Argon's README already says to use `Description` for anything required. Keep that, and add long-press.
15. **Separate "Save" buttons.** Old Orion and Kavo menus need the user to press save. Argon's verified autosave is right. Profiles must not bring manual saving back. Use "Save current as…" for *new* profiles only.
16. **Colour-only state.** Toggles whose on/off differs only by hue, and severity shown by colour alone. Pair colour with position (the knob), icon or text.
17. **Branding the host.** The library's name shown in the host's UI. Argon does this in the eyebrow and profile line; Rayfield classic does it in its prompts. Library branding belongs only in the docs.
18. **Everything in dropdowns.** Dropdowns for 2-3 options. In the docs, recommend `Segmented` for ≤4 options and `Dropdown` for 5+.

---

## 8. (d) Premium vs cheap with Roblox's rendering tools

**Premium, and how to build each one in Roblox:**

| Quality | Recipe (only fills, UICorner, UIStroke, UIGradient, 9-slice images, TweenService, UIScale, layouts) |
| --- | --- |
| Depth without blur | Exactly three elevation levels. Window (E0) → cards (E1, Surface/Window ≥ 1.15:1) → popovers and toasts (E2 `Raised` plus shadow). Each step ≥ 1.12:1 contrast; no further levels. |
| Lit glass edge | On E0 and E2: a 1 px white `UIStroke` at transparency 0.85, with a child `UIGradient` (Rotation 90, Transparency keys 0 → 0.0, 0.35 → 0.7, 1 → 1.0). The top edge catches light and fades down the sides. This is the visionOS / Liquid Glass cue without backdrop blur. |
| One real shadow | One pre-blurred rounded-rect PNG, 9-sliced (e.g. 128x128 with a 32 px blur, `SliceCenter` 48..80). Black, `ImageTransparency` 0.5, offset (0, 8), size +40 for the window; +24 at 0.6 for popovers and toasts. Not three stacked layers (L1263-1269) and never per row. |
| Translucency that stays readable | No blur means translucent text surfaces show busy 3D noise through them. Only the E0 shell may be translucent (user setting, capped at 0.25). Cards and text surfaces stay ≥ 0.96 opaque. |
| Soft glow, if any | A pre-blurred radial PNG tinted Accent at 0.92 transparency. Never `Frame` circles; today's hard-edged discs (L1283-1284) read as stamped circles. Or leave the glow out. |
| Subtle texture | Optional: one 128 px tileable noise `ImageLabel` (Tile, 0.97 transparency) over the window background. It hides banding in dark gradients. One instance. |
| Gradients that respect themes | `UIGradient` multiplies, so only use white → grey shading (`shadeGradient`, L317-320 already does this right) or transparency sequences. Never colour pairs baked from one theme. |
| Crisp text | Whole TextSize; no `CanvasGroup` on anything that holds text or gets resized (the library's own comments at L1271-1279 learned this); pixel-aligned positions (avoid `AnchorPoint` 0.5 on odd sizes); RobotoMono for numbers. |
| One accent, used sparingly | Accent only for selection, primary action, focus and progress, about 10 % of pixels at most. Everything else neutral. |
| Consistent geometry | 4 px grid, concentric radii (6.1), equal paddings. Icons exactly 16 or 20 px, centred optically. |
| Feedback within one frame | Every press gets `UIScale` 0.97 at once; hover within 0.10 s. Nothing waits for a callback before showing it was pressed. |
| Physical motion | A spring on knobs and indicators, decelerating entrances and accelerating exits. Nothing loops except progress. |
| Quiet chrome | No fake telemetry, no library branding. Empty states say what to do next. |

**Cheap (avoid):**
- Neon outlines on every box.
- Rainbow or animated gradients that loop forever.
- Multiple overlapping glows.
- Hard-edged `Frame` shadows or pure-black drop shadows on every row.
- Legacy Roblox fonts, or mixing more than two families.
- Fractional or tiny text; ALL CAPS micro-labels.
- Text glyphs as icons; emoji in the UI.
- Elastic bounces on large panels; transitions over 400 ms; staggered entrances that delay input.
- Hover fills you can barely see (1.06:1).
- White text on a light accent (Mono, 1.29:1).
- A window that doesn't fit a phone; clipped text.
- A splash screen that hides a ready UI.
- The library's own name in the host's UI.

---

## 9. Source compatibility and open questions for the owner

**Compatibility.** Every proposal above is additive (new option keys and methods) or a visual change. Behaviour changes that existing scripts could notice:
- **Loader.** No more pill or 0.93 s delay; `SetLoadingProgress`/`FinishLoading` keep working (F2).
- **Notification colour.** `Type` overrides the guess. The keyword guess stays as a fallback, with whole-word matching (F7).
- **Keybind Escape.** Esc cancels instead of clearing; Backspace clears (F11). This matches every desktop app, but it is a change.
- **Rayfield keys.** `KeySystem` and the other Rayfield keys start working (F10). A script that passed them expecting a gate gets one. That is the intent.

**Open questions.**
1. **Fake chrome.** Should "LIVE", "ARGON ONLINE" and the eyebrow go entirely, or become host-controlled (`Window:SetStatus`)? Recommendation: host-controlled, off by default.
2. **Default typeface.** Roboto body with Montserrat display (today) or BuilderSans throughout (the README says BuilderSans, L42, while the code defaults to Roboto, L514)? This is doc drift either way, so pick one.
3. **Key gate.** Does the owner want it at all? It is table stakes for script hubs and needed for Rayfield parity, but it is a policy choice for the owner.
4. **Gamepad toggle default.** None (host sets it) or hold ButtonSelect?
5. **Phone layout.** Under 520 px wide, should the window become full-screen with the tab rail as a bottom bar (iOS-style)? Recommended for v2.1. v2.0 can ship with the compact 72 px rail that exists today.
