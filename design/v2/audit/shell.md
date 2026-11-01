# Argon UI v2 audit: loader and window shell

Scope: everything between `loadstring(...)()` and a usable window, plus the window frame and its furniture (sidebar, brand, search, tab list, profile card, topbar, LIVE pill, theme picker, hide button, section jump rail, page host), drag, resize, hide and the toggle key, responsive behaviour, phones and tablets, gamepad, the custom cursor, scaling, z-order, the shadow, and the player and keybind overlays.

Source of truth: `argon-UI/argon-ui.luau` v1.18.3. Line numbers below refer to that file. Nothing in the repo was changed.

How this was checked:
- I read `CreateWindow` (1221-3367) and the helpers it calls: `create` (275), theme bindings (178-219), `loadLucideIndex` (339-389), `drawIcon` (418), `mountLogo` (452), the asset decode (109-156), `Notify` (1145), and the loader progress inside `LoadConfiguration` (1056-1080).
- I ran the real library in the repo's own Lune sandbox, read-only. The bench scripts are in `argon-UI-v2-work/bench/`:
  - `shell_profile.luau` records what is on screen while `CreateWindow` yields, the shell's footprint, the auto-mode loader timeline, a 500-control build, and the layout at 8 viewports.
  - `shell_bugs.luau` reproduces 8 shell bugs. All 8 reproduce.
  - `shell_decode_base64.luau` times the first-run asset decode.
  - `shell_theme_key_cost.luau` times `themeKeyForColor` with real `Color3` userdata.
  - `shell_compile_cost.luau` times compiling the 296 KB source.
  - `shell_client_bench.luau` is a script to paste into a real client. It measures what the sandbox cannot: network, real instance cost and real frames.
- I opened the browser preview (`argon-ui-preview.html`) at 1366x768 and at 844x390 (a phone held sideways), and hid the window there.

---

## 1. What the user actually sees today

The loader is built at the **end** of `CreateWindow` (`splash`, 3183). Everything before it is built straight into a visible, full-size window. The ScreenGui is parented at 1255. `main` is created at 980x660 with `Visible = true` at 1280.

`CreateWindow` also yields twice before the loader exists:

| When | Line | What is on screen at that moment (measured in the sandbox) |
|---|---|---|
| First `drawIcon` (the search icon) calls `loadLucideIndex`. On a first run this is `game:HttpGet` of the whole lucide-roblox `Icons.luau`. On later runs it is `readfile` plus `loadstring` of the same file. | 1300 -> 374 / 368 | ScreenGui parented, a **980x660 window visible**, 38 instances: shadow, window, glow, sidebar, brand, half a search box. No loader. |
| `Players:GetUserThumbnailAsync` for the profile card (synchronous, inside `pcall`) | 1309 | Same half-built 980x660 window, 48 instances. No loader. |

A host that builds without yielding (most Rayfield-style scripts) then freezes the client for the whole build. No frame renders during that time, so the half-built window from the last yield stays frozen on screen. Only after the build do the timers get to run.

Auto-mode timeline (`shell_profile.luau` section 3, tweens resolved instantly):

```
t=0.00s  window= 392x108 loader=true  bar= 72%  percent text=0%    status='INITIALIZING INTERFACE'
t=0.38s  window= 980x660 loader=true  bar=100%  percent text=0%    status='OPENING CONTROL CENTER'   <- pill stretched to full size
t=0.60s  window= 980x660 loader=true  bar=100%  percent text=0%    status='OPENING CONTROL CENTER'   <- still a 980x660 cover laid out for 392x108
t=0.93s  window= 980x660 loader=true  bar=100%  percent text=100%  sidebar visible=true          <- reveal starts
t=1.30s  window= 980x660 loader=false                                                            <- cover destroyed (0.93 + 0.32)
```

From the user's side, the sequence is:
1. A half-built full-size window appears.
2. It shrinks into a 392x108 pill. If the host built synchronously for more than 0.38 s, the pill is not seen at all.
3. The pill grows back into a large dark rectangle with the pill's text in its corners.
4. 0.55 s later the content fades in.

For a large synchronous host, steps 3 and 4 happen in the same frame, because both overdue timers fire together. The loader never shows real progress unless the host calls `SetLoadingProgress` and yields between steps, as the README recommends.

## 2. Measurements

| What | Result | Source |
|---|---|---|
| Compile the library (`loadstring` cost, desktop) | **21.9 ms** for 296,126 bytes | `shell_compile_cost.luau` |
| Base64 payloads (logo 256x256 + atlas 384x192) inside the source | 48,456 chars = **16.4 % of the file** downloaded and compiled on every run | `shell_decode_base64.luau` |
| First-run decode (current `decodeBase64`) | **11.1 ms** (logo 7.1 + atlas 4.0). A lookup-table and buffer decoder takes 2.4 ms. | `shell_decode_base64.luau` |
| Shell alone (`CreateWindow`, no tabs) | **184 instances**, 86 theme bindings, 30 connections, 2 ScreenGuis | `shell_profile.luau` §2 |
| 500 controls (10 tabs x 5 sections x 10 controls; toggle, slider, dropdown, button and keybind mix) | **5,796 instances** (11.6 per control: 1,544 UICorner, 1,440 Frame, 1,064 UIStroke, 870 TextLabel), **+3,282 theme bindings**, **+1,782 connections** | `shell_profile.luau` §4 |
| `themeKeyForColor` per call (real `Color3`) | 0.4 µs (first key), 3.1 µs (10th key), 5.4 µs (last key), **10.3 µs on a miss**. A hex-map lookup takes 0.66 µs. | `shell_theme_key_cost.luau` |
| `themeKeyForColor` share of a 500-control build | about 26 ms on a desktop CPU. It is real but not the main cost. The main cost is 5.8k instances created synchronously in one run. | `shell_theme_key_cost.luau` |
| `SetTheme` repaint at 500 controls | 3,368 bindings, which takes about 10 frames (one `task.wait` per 350 bindings, line 664) | `shell_profile.luau` §4 |
| Lucide index | **Not measured.** I did not download it without permission. It covers every icon in 3 sprite sizes and is compiled on every launch, even from cache, to use about 20 icons. `shell_client_bench.luau` times it cold and warm. | 339-389 |

Layout at common viewports (`shell_profile.luau` §5). The window is opened and not resized by hand. "Overflow" is how far the window runs past the GUI area under the 58 px top-bar inset, because `IgnoreGuiInset=false` (1252) but sizing uses `Camera.ViewportSize`.

| Viewport | Window | Sidebar | Page area | Overflow | Overlays cover the window's right edge by |
|---|---|---|---|---|---|
| 1920x1080 | 980x660 | 232 full | 550 px | 0 | 0 px |
| **1366x768** (most common laptop) | 980x660 | 232 full | 550 | 0 | **95 px** |
| 1280x720 | 980x660 | 232 full | 550 | 0 | **138 px** |
| 1024x768 (tablet, landscape) | 980x660 | 232 full | 550 | 0 | **266 px** |
| **844x390** (phone, landscape) | 816x370 | **232 full** (not compact, because 816 >= 760) | **260 px** | **38 px** | 274 px |
| 740x360 | 712x340 | 72 compact | 230 | 38 | 274 |
| 390x844 (phone, portrait) | 370x660 | 72 compact | 550 | 0 | 278 px (all of it) |

The preview at 1366x768 matches the overlap: the player list and active-binds cards sit on top of the right-hand control column. At 844x390 the preview shows the full sidebar, about 130 px of chrome, and the bottom of the window off-screen.

## 3. Findings

Severity: **critical** blocks a class of users. **High** is visible to most users, or breaks a promise. **Medium** is a clear UX or visual defect. **Low** is polish or debt.

### Loader

**L1 (high, loader). A half-built full-size window flashes before the loader, then collapses into the pill.**
- Where: 1255 (GUI parented first), 1280 (`main` 980x660 visible), 1300 (first icon yields for the Lucide index), 1309 (thumbnail yields), 3183/3189 (loader created and window shrunk only at the end).
- Evidence: `shell_profile.luau` §1. The window is visible at 980x660 with 38 and then 48 instances, and no loader exists during either yield.
- v2 fix:
  - Build the loader first, at the top of `CreateWindow`.
  - Build the shell with `main.Visible=false`, or unparented, and parent it once.
  - Never yield inside `CreateWindow`.
  - Load the avatar with a `rbxthumb://type=AvatarHeadShot&id=<id>&w=48&h=48` content URL, which needs no yield.
  - Draw icons from a bundled table, with no network on the critical path (see L4).

**L2 (high, loader). Auto mode runs on fixed timers and ignores what the host is doing.**
- Where: 3351-3365. The bar goes to 72 % at once, to 100 % at 0.38 s, and the window opens at 0.93 s. It does not matter whether the host has finished.
- Effects:
  - A tiny host waits about 1.3 s for no reason.
  - A host that yields (key system, HTTP) gets a half-built window at 0.93 s.
  - A synchronous host never sees the loader animate, because no frames render during its build. Both timers then fire together after the build.
  - The bar is fake: it is driven by time, not by work.
- v2 fix: finish when the host is actually done. Track the host's thread from `coroutine.running()` at `CreateWindow`, and finish when it is dead. If it is still alive, finish when it is suspended and no `Create*` call has happened for about 250 ms. Report progress from real work. See section 4.

**L3 (high, perf). A big host freezes the client, and the loader cannot show it.**
- Where: every `Create*` builds its instances at once. 500 controls means 5,796 instances, 3,282 bindings and 1,782 connections in one run (`shell_profile.luau` §4).
- Evidence: the sandbox build takes 575 ms with mock instances, so that number is relative only. A real client is a guess: roughly 10-40 µs per instance with parenting and property writes, so 60-230 ms on desktop and 3-5x that on phones. `shell_client_bench.luau` measures it.
- v2 fix:
  - Lazy tabs. `Create*` records a descriptor and returns a live element object right away; `Set` and `Get` work on its state.
  - Only the active tab's controls are built into instances, in 6 ms slices per frame. Other tabs build on first visit or in idle slices.
  - Fewer instances per control: a 9-slice rounded rectangle with a border is one ImageLabel instead of Frame + UICorner + UIStroke.

**L4 (high, perf). The Lucide index is on the critical path every launch.**
- Where: `loadLucideIndex` (339) runs from the first `drawIcon` (1300).
- Cost: a first run blocks on `game:HttpGet` of the full index. Every later run does `readfile` plus `loadstring` of the whole index (all icons, 3 sizes) to draw about 20 icons. If the fetch fails, `LUCIDE_SET=false` for the session and icons fall back with nothing visible to the user.
- v2 fix:
  - Bundle a curated table of `{assetId, offset}` entries for every icon the library uses, plus a few hundred common ones, as a few KB of literals.
  - Load the full index only when a host asks for an unknown name. Do it in the background with `task.spawn`, draw a placeholder, and swap the image in when it arrives.
  - Cache the index as JSON. `HttpService:JSONDecode` is native and much faster than compiling Luau.

**L5 (medium, bug). The percent label disagrees with the bar in auto mode.**
- Where: `percentValue` (3221) changes only in `SetLoadingProgress` and `openWindow`. Auto mode tweens `progressFill` to 0.72 and then 1.0 (3351, 3356) but never `percentValue`.
- Evidence: §1 timeline. The bar is at 72-100 % while the label reads "0%" until 0.93 s, then it jumps to 100 %.
- v2 fix: drive both from one value. Show a percentage only when progress is known (determinate).

**L6 (high, visual). The pill is stretched to full size while still laid out as a pill.**
- Where: the auto path, `task.delay(.38) -> expandShell()` (3352-3357).
- Detail: this is the exact "black silhouette" the code comments call a mistake (3299-3302, 3315-3317). It still ships on the default path, for 0.55 s on every launch.
- Evidence: §1 timeline at t=0.38-0.93: window 980x660, loader up, sidebar hidden.
- v2 fix: never resize a cover that has content in it. Morph an empty "ghost" frame (background, corner and stroke only) from the card's bounds to the window's bounds. Reveal the real window, already laid out, by fading a window-coloured veil.

**L7 (medium, loader). The avatar thumbnail blocks `CreateWindow`.**
- Where: 1309 calls `Players:GetUserThumbnailAsync` synchronously.
- Evidence: §1, a yield inside `CreateWindow` while the half-built window is visible. On a slow or failing request this adds network round trips before the loader even exists.
- v2 fix: use the `rbxthumb://` content URL, which needs no call, or `task.spawn`.

**L8 (medium, ux). The watchdog is 30 s, silent, with no way out.**
- Where: 3365.
- Detail: a manual-mode host that errors or stalls mid-build leaves the user looking at a pill for 30 s. There is no message, no "open anyway", and no error.
- v2 fix: after 8 s with no progress, show "Still working..." and an **Open now** button on the card. Keep the 30 s hard watchdog. If the host thread is dead, open at once. Offer an optional `Window:Build(fn)` that pcall-wraps the build and shows the error on the card with Open anyway and Copy error.

**L9 (low, bug). The status text and comments are inconsistent.**
- Where:
  - Auto mode hardcodes "OPENING CONTROL CENTER" (3355), while manual mode uses `"OPENING "..subtitle` (3311).
  - Comments still describe a "286x58 pill" (3114, 3315; tests/run.luau 1253), but `SPLASH_W,SPLASH_H=392,108` (3182).
- v2 fix: one status source. Delete the stale comments.

**L10 (low, perf). The first-run asset decode is cheap, but it is 16 % of every download.**
- Where: 109-156, 34-107.
- Evidence: 11.1 ms to decode once (2.4 ms with a lookup table). The 48 KB of base64 is fetched and compiled on every run (22 ms to compile the whole file).
- v2 fix: use uploaded image asset ids for the logo and atlas, and keep base64 only as an opt-in offline build. At minimum, move the payloads into a separate module that is fetched only when `getcustomasset` exists and the cached file is missing.

**L11 (low, perf). Theme-key resolution scans the palette on every property of every instance.**
- Where: `create` (275) calls `registerThemeBinding`, which calls `themeKeyForColor` (178): up to 18 `==` and then a `pairs` walk on a miss.
- Evidence: 10.3 µs per miss and 3.1 µs per average hit, about 26 ms at 500 controls, plus 3.3k binding records that are kept until pruning every 30 s.
- v2 fix: style tokens by name (`Theme.bind(obj, "BackgroundColor3", "Surface")`) rather than reverse-mapping colours. If reverse mapping stays, use a `ToHex` map that is rebuilt on `SetTheme` (0.66 µs per call). Store bindings per window and drop them with the window.

### Window, hide and toggle

**S1 (critical, ux). Phones and tablets cannot reopen a hidden window.**
- Where: the hide button (1341, 3093) and the toggle key (3095-3099). Insert is the only way back, and there is no on-screen restore control.
- Evidence: `shell_bugs.luau` #8. With `TouchEnabled` and no keyboard, the window hidden leaves **0 tappable controls**. The preview shows the same: an empty screen.
- Impact: a mobile user who taps "–" loses the menu until they re-execute or rejoin.
- v2 fix: hiding becomes "minimise to dock". A small draggable pill (logo and title, plus the key hint on PC) snaps to a screen edge. Its position is saved, it is always shown on touch devices while hidden, and it is optional on PC. Tapping it restores the window. The first time a user hides the window on PC, show a toast: "Hidden. Press Insert to reopen".

**S2 (high, bug). A Rayfield-style string keybind breaks the toggle.**
- Where: `_toggleKey=options.ToggleUIKeybind or Enum.KeyCode.Insert` (1385) stores the string as-is, and 3097 compares it with `input.KeyCode`. `SetToggleKey` (1398) handles strings, but the constructor does not.
- Evidence: `shell_bugs.luau` #1. With `ToggleUIKeybind="K"` the key never toggles. Combined with the hide button, a migrated Rayfield script can hide the window and never get it back.
- v2 fix: normalise through `SetToggleKey`. Accept `Enum.KeyCode`, `"K"` or `"RightShift"`.

**S3 (high, ux). The menu key is not user-facing.**
- Where: there is no "Menu key" control in `CreateLibrarySettings` (2934-2967), the key is not in `_exportUIPreferences` (1517), and it is not shown anywhere in the UI.
- Impact: Insert is missing on Mac keyboards and many laptops.
- v2 fix:
  - Add a "Menu key" keybind in library settings and save it.
  - Show the key in the hide button tooltip and in the dock pill.
  - Support a gamepad binding.

**S4 (high, ux). The mouse stays locked in first-person and shift-lock games.**
- Where: there is no `Modal` element and no `MouseBehavior` handling anywhere in the file.
- Impact: in first-person, shift-lock or `LockCenter` games the cursor stays captured, so the open menu cannot be clicked. LinoriaLib solves this with a `Modal` TextButton.
- v2 fix: while the window is visible, keep a hidden `TextButton{Modal=true}`. Remove it when hidden, and give it an option for games that manage the mouse themselves.

**S5 (medium, ux). Hiding is instant, with no state kept and no motion.**
- Where: `SetVisibility` (1387-1393) flips `Visible`.
- v2 fix: a 160 ms fade and scale (0.98 -> 1) on open and close. Keep the tab and scroll position. Honour reduced motion.

**S6 (low, bug). Hiding during the loader leaves an orphan shadow.**
- Where: `reveal()` sets `shadow.Visible=true` with no condition (3291).
- Evidence: `shell_bugs.luau` #2. After Insert during the loader: `main.Visible=false`, `shadow.Visible=true`, so a dark halo floats over the game.
- v2 fix: one `Shell` container that holds the shadow and the window. Visibility applies to the container.

**S7 (medium, bug). The window position and size are not saved, not clamped, and cannot be reset.**
- Where: drag (3079-3091) moves by offset with no viewport clamp. `_exportUIPreferences` (1517) saves overlay positions but not the window's.
- Evidence: `shell_bugs.luau` #5. The saved keys contain no window position or size.
- Impact: a window dragged off-screen, or stranded after a resolution change, can only be recovered by re-executing.
- v2 fix:
  - Save the window position and size.
  - Clamp to the GUI area on load, after a drag and after a viewport change, keeping at least 48 px of topbar on screen.
  - Double-click the topbar to re-centre or maximise.
  - Add a "Reset window" command.

**S8 (low, ux). The resize limits ignore big screens.**
- Where: `SetSize` caps the window at 1200x820 (1427). Resizing works only from a 30x30 corner grip (3075).
- v2 fix: the cap is the GUI area minus a margin. Allow edge resizing with a resize cursor, or offer "Compact", "Comfortable" and "Large" presets.

### Touch, gamepad and cursor

**T1 (high, bug). A window drag follows any finger.**
- Where: drag reads every `UserInputService.InputChanged` touch (3085-3091). Overlays (1459) and sliders (2346) have the same pattern.
- Evidence: `shell_bugs.luau` #7. With one finger on the topbar, moving the movement-stick finger made the window jump by (-420, 600). Lifting that finger also ends the drag (3092).
- v2 fix: remember the `InputObject` from `InputBegan` and only follow `input == dragInput`. One shared drag helper should be used everywhere.

**T2 (high, ux). The phone layout is a desktop window squeezed onto the screen.**
- Where: `responsive` (3102-3138).
- Problems:
  - Breakpoints use window width only: compact below 760. An 844x390 phone gets the full 232 px sidebar and a 260 px page area.
  - Sizing uses `Camera.ViewportSize`, but the GUI has `IgnoreGuiInset=false`, so the window overflows by 38 px under the top bar.
  - Touch targets are 28 px (theme and hide buttons, 1334/1341).
  - Labels are 10-11 px.
- v2 fix:
  - Size from the ScreenGui's `AbsoluteSize`, which already accounts for the inset, and respect safe areas.
  - Breakpoints: >=1100 px full sidebar; 760-1100 px sidebar 200; <760 px icon rail. A phone (touch and height <500) gets a full-screen sheet with a top segmented tab bar, or a bottom tab bar in portrait.
  - 44 px minimum targets on touch.
  - On touch, hide the overlays by default.

**T3 (medium, ux). The compact icon rail has no labels and no tooltips.**
- Where: compact hides `ButtonTitle` (3130). There are no hover tooltips or long-press labels for tabs.
- v2 fix: hover tooltips on PC and long-press labels on touch. Add a manual collapse chevron so a user can choose the rail at any width, and save the choice.

**T4 (medium, a11y). There is no gamepad support.**
- Where: no `Selectable` setup, no `GuiService.SelectedObject` use, no gamepad toggle. Insert is unreachable from a controller.
- v2 fix:
  - Selection groups for the tab list, page and topbar, with a visible focus ring.
  - DPad and stick navigation; ButtonA activates, ButtonB backs out.
  - L1 and R1 switch tabs.
  - A configurable gamepad toggle, such as holding Select for 0.5 s.
  - Keyboard focus rings as well.

**T5 (low, perf). The custom cursor runs every frame for the library's lifetime.**
- Where: a `RenderStepped` handler (3159) runs even while the window is hidden. It exits early, so the cost is tiny.
- Notes: the cursor is only useful when `MouseIconEnabled` is false, and it does not unlock the mouse (see S4).
- v2 fix: connect it only while the window is visible and the cursor is wanted. Respect the hotspot of the arrow image.

### Responsive layout, scale, search and navigation

**R1 (medium-high, ux). There is no UI scale and no DPI awareness.**
- Where: there is no `UIScale` on the window. The size is fixed at 980x660, capped at 1200x820. The smallest shell text renders at 10-11 px (`readableSize`, 559): the "NAVIGATION" caption, the brand subtitle, "JUMP TO", tab counts, overlay meta, the loader subtitle.
- Impact: on 1440p and 4K monitors the window is a small island with tiny text. On phones the 10 px labels are hard to read.
- v2 fix: one `UIScale` on the shell. The default scale is automatic from the GUI height (720 -> 0.9, 1080 -> 1.0, 1440 -> 1.2, 2160 -> 1.5). Add a user slider from 80 to 150 %. Use whole `TextSize` values with a 12 px minimum and 14 px for control text.

**R2 (medium, bug). `/` focuses a search box that is hidden.**
- Where: 3098 calls `search:CaptureFocus()` while `searchFrame.Visible=false` in compact mode (3126).
- Evidence: `shell_bugs.luau` #3. Typing filters the page invisibly. `/` is also Roblox's chat hotkey, so the two may fight over focus (verify in a client).
- v2 fix: `Ctrl+K` (or `/` only while the pointer is over the window) opens a command palette that works at every width.

**R3 (medium, feature). Search is per tab, with no global search and no results state.**
- Where: `_filter` (1730) matches only the active tab, by name. The placeholder reads "Search this tab". There is no "no results" message, no highlighting and no jump to other tabs.
- v2 fix: a command palette (Raycast or Linear style).
  - It searches every tab, section, control name, description and tooltip.
  - It ranks fuzzy matches and shows the result's breadcrumb.
  - Enter jumps to the control: switch tab, scroll, and pulse a highlight.
  - Results can also be actions: theme, scale, reset window, rebind menu key.

**R4 (medium, ux). The section jump rail is weak.**
- Where: 1347-1356, 2978-2999.
- Problems:
  - The strip scrolls horizontally with `ScrollBarThickness=0`, so on PC with a mouse wheel the chips past the edge are probably unreachable (verify in a client).
  - No chip shows which section is active.
  - The jump is instant (`CanvasPosition` is set directly).
  - The whole rail disappears while a search filter is active.
- v2 fix: scroll-spy highlight of the active chip, an eased scroll, and overflow fades with chevrons. At >=1100 px, move it to a right-side "On this page" list.

**R5 (medium, ux). The breadcrumb hardcodes the library brand.**
- Where: `eyebrow.Text="ARGON / "..tab.Name:upper()` (1680). The initial text "ARGON / DASHBOARD" and title "Dashboard" (1315-1316) show before any tab exists.
- Evidence: `shell_bugs.luau` #4. A window named "Space Hub" shows "ARGON / MAIN".
- v2 fix: `Title / Tab` from the window's own name, and an empty state when no tab exists.

### Overlays, notifications and z-order

**O1 (high, ux). The overlays are on by default and cover the window on common laptops.**
- Where: `_playerListEnabled` and `_keybindListEnabled` default to true (1385). The cards are 270 px wide at `right -18`, top 72 and 348 (1472-1473).
- Evidence: the §2 table. They cover 95 px of the window at 1366x768, 138 px at 1280x720 and 266 px at 1024x768. The preview at 1366x768 shows them over the control column.
- v2 fix:
  - Default them to off unless the host enables them.
  - On first show, place them outside the window's rectangle when there is room. When there is not, dock them as collapsible tabs on the screen edge.
  - Clamp them to the GUI area.
  - Raise whichever surface the user is interacting with.

**O2 (medium, perf). The player list rebuilds everything on each join or leave.**
- Where: `refreshPlayers` (1542) destroys all rows, rebuilds them, and re-requests a thumbnail for every player on every `PlayerAdded`/`PlayerRemoving` (1578).
- Impact: in a 30-player server, one join means 30 thumbnail calls and about 240 new instances. Bindings grow until the next prune.
- v2 fix: keep one row per player and add or remove only that row. Use `rbxthumb://` URLs, which need no call. Virtualise the list beyond about 20 rows. Add search and a "friends first" sort.

**O3 (low, ux). The keybind overlay wastes space and uses text glyphs.**
- Problems:
  - The card stays 214 px tall to say "No binds active" (1576).
  - The collapse button uses `-` and `+` text (1446, 1452).
  - The hide button is an en-dash glyph (1341).
- v2 fix: size the card to its content and hide it when empty, with an option. Use real icons (chevron, minimise) from the same icon set.

**O4 (medium, bug). The notification column ignores the screen width.**
- Where: `Position=UDim2.new(1,-304,0,16)`, 340 wide (1368). The 304 px offset is applied whenever overlays exist, even if they are later turned off.
- Evidence: `shell_bugs.luau` #6. On a 390 px phone the column spans x = -254..86, so it is mostly off-screen.
- v2 fix: on narrow screens, show toasts top-centre with width `min(340, guiWidth-32)`. On desktop, anchor them to the free corner, and re-anchor when the overlays change.

**O5 (low-medium, ux). Z-order is fixed by constant ZIndex values, and popups do not follow their trigger.**
- Where: shadow 1, window 2, overlays 70, dropdown 80, colour picker 84, tooltip 96, toasts 100, dialog 105, with `ZIndexBehavior.Sibling` (1252).
- Problems:
  - The overlays always draw over the window, and clicking the window does not raise it.
  - Dropdown and colour popups are positioned once in absolute screen coordinates (2521, 2879). They do not follow a window drag or a page scroll, and they clamp against the camera viewport rather than the GUI area.
  - The theme popover closes only through its own button: no outside click and no Escape (3065-3070).
  - Dialogs have no Escape or Enter handling and no focus trap (1580).
- v2 fix: one layer manager with named layers: base, overlay, popover, toast, modal, cursor. Popovers anchor to their trigger and reposition on drag or scroll. They close on outside click, Escape, gamepad B, scroll or drag.

**O6 (low, perf). The shadow is three separate image layers that must be kept in sync by hand.**
- Where: three ImageLabels (1262-1269), a sibling of `main`. It is synced manually in drag, `SetSize`, `responsive` and the loader.
- v2 fix: one 9-slice soft-shadow image inside a common `Shell` container, so drag moves one object.

### Visual design and docs

**V1 (medium, visual). The topbar and profile card show fake status.**
- Where:
  - The "LIVE" pill has a breathing halo that tweens forever (1320-1329). It always says LIVE and means nothing.
  - "ARGON ONLINE" in the profile card (1311) is a fixed label in Success green.
- Impact: both use the colour for "ok" on something that is not a state, take space in the two most valuable spots of the shell, and leak the library's brand into every host.
- v2 fix: remove both. Offer a host-driven status slot (`Window:SetStatus(text, "success" | "warning" | "danger" | nil)`, hidden by default). Turn the profile card into a real menu: settings, menu key, theme, scale, unload.

**V2 (medium, visual). The look reads as a 2020-era dashboard template.**
- Problems:
  - Uppercase 9-10 px micro-labels everywhere.
  - Accent "glow" discs (1282-1284) and multiply-gradients on every surface.
  - Chrome stacked before the first control: 72 brand + 38 search + 24 caption = 146 px in the sidebar, and 70 topbar + 40 jump rail = 110 px in the content column, out of 660.
  - Tab counts that nobody needs.
- v2 fix:
  - Calmer surfaces and hairline borders.
  - An 8 pt spacing grid.
  - Sentence-case labels at 12 px or more.
  - Accent colour only for state and selection.
  - A 52 px topbar holding the breadcrumb, the command palette trigger ("Search or jump to... Ctrl K") and icon buttons (settings, minimise).
  - A 220 px sidebar with optional tab groups.
  - Content at most 760 px wide, auto-flowing into two columns at >=1000 px.
  - An optional Lighting `BlurEffect` behind the window for frosted depth, off by default.

**V3 (low-medium, a11y). `Dim` text fails contrast.**
- Evidence: `Dim` (98,106,128) on Window, Sidebar, Surface and Input measures 3.52, 3.60, 3.32 and 3.47:1. Small text needs 4.5:1. It is used for the small labels listed in R1, the search placeholder and the `/` hint.
- For comparison, `Muted` measures 6.6-7.2:1.
- v2 fix: raise `Dim` to at least 4.5:1 in every theme, and add a palette validator to the test suite.

**V4 (medium, docs). The browser preview no longer matches the library.**
- Differences: the preview's loader is a centred card with an orbiting dot, while the library's is a 392x108 pill. The preview's topbar has Pin-overlays and Notification buttons the library lacks. The preview window is 1060x700; the library's is 980x660.
- Also: the README says "One modern typeface throughout (BuilderSans)", but the default is Roboto with Montserrat (493-516).
- Impact: the owner and users judge the look from a demo that is not the product.
- v2 fix: generate the preview from the same layout spec, or at least check it against the library in CI.

## 4. Recommended v2 loader experience

Goal: the user never sees a half-built window, never waits for a timer, always sees honest motion, and the window that appears is complete and crisp.

### What it shows
- A centred card in the GUI area: `min(360, guiWidth-32)` wide and about 96 px tall. It contains:
  - A 44 px logo plate.
  - The window title (16 px semibold).
  - A status line (12 px, Muted): "Building Combat · 212 controls", "Restoring settings 120/240", "Caching icons (first launch)".
  - A 3 px bar along the bottom. It is **determinate** only when the total is known (host fractions, configuration restore). Otherwise it is an **indeterminate** sweeping segment.
  - A percentage only when the bar is determinate.
- No fake progress, no hardcoded "CONTROL CENTER", no brand leak.
- Reduced motion (a saved preference) turns off the sweep and the breathing.
- Optional `LoadingScreen = { Title, Subtitle, Logo, Tips = {...} }`. Tips rotate only if loading lasts longer than 2 s.

### How it reports progress
Progress comes from four sources, merged into one value that only ever moves forward:
1. **Library work units.** Each `CreateTab`, `CreateSection` and `Create*` bumps a counter. While building the active tab, progress = built / registered.
2. **Configuration restore.** The existing `LoadConfiguration` reporting (1056-1080) is kept: about 40 reports and 45 ms slices.
3. **Asset warm-up.** `ContentProvider:PreloadAsync` for the logo and icon sprite sheets runs in the background. It never blocks, and appears only as a status line.
4. **The host.** `SetLoadingProgress(fraction, status)` is unchanged. It maps onto 0-85 %, with configuration restore taking 85-100 %. Once the host reports, it drives the bar, as today.

### How it hands over
1. The window is already laid out at its final size underneath the card and hidden.
2. An empty "ghost" frame (window colour, corner, stroke and shadow, no content) morphs from the card's rectangle to the window's rectangle in about 240 ms (Quint out). The card's content fades out in the first 120 ms.
3. The real window appears under a window-coloured veil that fades out in 180 ms. Sidebar, topbar and page rise 6 px with a 30 ms stagger.
4. Overlays and the dock pill appear after the hand-off. Focus goes to the first tab, or to the search box if the host asks.

No resize of anything with content in it. No CanvasGroup on text. One relayout.

### Timing rules
- **Do not show the card at all if ready within 150 ms.** Go straight to the window's entrance animation. This removes the flash for small or warm scripts.
- **Once shown, keep it at least 400 ms**, so it never strobes.
- **Ready** means one of:
  - (a) the host called `FinishLoading`;
  - (b) the host's thread, captured with `coroutine.running()` at `CreateWindow`, is dead;
  - (c) the host's thread is suspended and no `Create*`, `SetLoadingProgress` or restore activity has happened for 250 ms, after at least one frame;
  - and in each case, the active tab has finished building.
- **Manual mode** (`Loading="manual"`, or once any `SetLoadingProgress` call has happened) ignores (b) and (c) until `FinishLoading`.
- **Stall UI:** 8 s with no progress shows "Still working... **Open now**". The hard watchdog stays at 30 s.
- **Errors:** an optional `Window:Build(function() ... end)` wrapper catches the error and shows it on the card with Open anyway and Copy error.

### How long it lasts when the host does nothing
- The host creates the window and nothing else, and its thread ends: ready at the next frame. That is under 150 ms, so there is **no card**: the window enters (about 200 ms) with an empty state ("No tabs yet"). Total about 0.2 s, against 1.3 s today.
- The host creates the window and then yields for something slow, such as a key system or HTTP, with no `Create*` calls: by rule (c), the card appears at 150 ms with "Waiting for script...". The window opens 250 ms after the last activity, so roughly 0.4-0.65 s after `CreateWindow`.
- If the host's thread is suspended in a long wait after creating tabs, the 250 ms idle rule opens the window. Hosts that want to keep the card up use manual mode, exactly as today.

### How it behaves with 500 controls
Assuming lazy tabs (L3):
- `Create*` records descriptors (about 10-20 µs each, about 10 ms for 500) and returns working element objects. `Set`, `Get` and flags work at once.
- The active tab (about 50 controls, about 580 instances at today's density, about 250 after the instance diet) builds in 6 ms slices per frame. The card shows "Building Main · 50 of 500" with a determinate bar for that work.
- `LoadConfiguration` applies values to descriptors at once and fires host callbacks in 45 ms slices: "Restoring settings 120/240".
- Hand-off at about 0.3-0.6 s, depending on callback cost.
- The remaining 9 tabs build in idle slices (at most 4 ms per frame) in priority order: tabs the user hovers first. Any tab that is clicked before it is built builds right then, behind a skeleton shimmer that lasts 1-2 frames.
- The client never freezes for more than one slice. At 30-60 fps, the card's animation keeps moving the whole time.

If lazy building cannot ship in v2.0, the fallback is a time budget inside `Create*` while loading. It yields with `task.wait()` once 8 ms have passed since the last yield. The loader then animates and counts, at a cost of about one frame per 8 ms of work. This is safe in executor threads, and it stops as soon as loading is done.

### API (source-compatible)
- Unchanged: `SetLoadingProgress(fraction, status)`, `FinishLoading()`, `IsLoading()`, `Loading = "manual"`, `ManualLoading = true`.
- New:
  - `LoadingScreen = "auto" | "always" | "never" | {Title, Subtitle, Logo, Tips}`
  - `Window:SetLoadingStatus(text)`
  - `Window:OnLoaded(callback)`
  - `Window:Build(fn)`
  - `LoadingMinimum` (default 0.4)

## 5. Recommended v2 shell

**Structure.** One ScreenGui with these named layers:
- `Base`: the Shell, which holds the shadow, the window and the dock pill.
- `Overlay`
- `Popover`
- `Toast`
- `Modal`

The cursor stays in its own ScreenGui at the maximum `DisplayOrder`. One `UIScale` on Base, Overlay and Popover follows the scale preference.

**Sizing.** Everything is computed from the ScreenGui's `AbsoluteSize`, which is inset-aware, and respects safe areas:

| Breakpoint | Layout |
|---|---|
| Wide (>=1100 px) | Sidebar 220, content plus an "On this page" list, two-column auto-grid |
| Medium (760-1100 px) | Sidebar 200 or a user-collapsed rail, one column |
| Narrow (<760 px) | Icon rail with tooltips |
| Phone (touch, and height <500 or width <600) | Full-screen sheet. A top bar with title, palette and close. A horizontal tab strip, or a bottom tab bar in portrait. 44 px targets. Overlays off. Toasts top-centre. |

**Topbar (52 px).**
- Left: breadcrumb `Title / Tab`.
- Middle: a command palette trigger, "Search or jump to... Ctrl K".
- Right: optional host status slot, settings popover (theme, accent, font, scale, density, transparency, menu key, reduced motion), minimise.
- No LIVE pill, and no theme dots as a primary action.
- The topbar is the drag handle. Double-click re-centres or maximises.

**Sidebar.**
- Brand: logo and title. The subtitle is optional.
- Tab groups: optional `Window:CreateTabGroup` or a `Group` field on `CreateTab`.
- Badges set by the host: `Tab:SetBadge`.
- A collapse chevron, with the choice saved.
- The profile card becomes an account menu: avatar, display name, settings, unload.
- No "NAVIGATION" caption, and tab counts only as search results.

**Minimise and dock.** Minimising collapses the window into a 44 px dock pill (logo and title, plus the key hint on PC) that the user can drag. It snaps to edges and saves its position. It is always available on touch, and optional on PC (`Dock = "auto" | "always" | "never"`). The first time a user hides the window on PC, a toast names the key.

**Input.**
- One drag helper that tracks the `InputObject` (T1), clamps to the GUI area and saves positions.
- Modal mouse unlock while the window is open (S4).
- Keyboard:
  - `Ctrl+K` opens the palette.
  - `Ctrl+1` to `Ctrl+9` switch tabs.
  - `Esc` closes the topmost popover or dialog.
  - Arrow keys work in lists.
- Gamepad selection groups with focus rings, L1 and R1 for tabs, B to back out, and a configurable toggle (T4).

**Overlays.**
- Off by default, unless the host turns them on.
- They auto-place outside the window and dock to screen edges when space is short.
- The keybind list sizes to its content and hides when empty.
- Player rows are keyed (O2).
- They raise on interaction and follow the shell's scale.

**Persistence.** Window position, size, sidebar state, scale, menu key, dock position, last tab and reduced motion all join `__argon` preferences.

## 6. Priority order for v2

1. S1 dock and restore, S2 string keybind, S4 Modal mouse unlock, T1 touch-safe drag. These are lock-outs and input-blocking bugs.
2. L1, L2, L6, L7 and L4: loader-first `CreateWindow` with no yields, thread- and idle-aware finish, ghost hand-off, bundled icons. This fixes "the loading is not the best".
3. L3 lazy tabs and the instance diet. This fixes "load times for a lot of features are awful".
4. T2 and R1: inset-aware breakpoints, a phone sheet layout and UI scale.
5. O1 and O4: overlay defaults and placement, and toast placement.
6. R3 command palette and global search, R4 jump rail, T3 rail tooltips and manual collapse, S7 saved and clamped window.
7. V1, V2, V3: the visual refresh and contrast.
8. T4 gamepad, O5 layer manager, O2 keyed player list.
9. L5, L8, L9, L10, L11, S5, S6, S8, O3, O6, V4: cleanup and docs.
