# Argon UI v1.18.3: performance and load-time audit

Area: everything that makes loading the library, opening the window, building tabs and controls, and using features slow, janky or memory-hungry.
Source audited: `argon-ui.luau` (v1.18.3, 3,369 lines, 296,126 bytes), read in full except the base64 blob lines 97-107. The repo was not modified: `git status` is clean.
Benches: `bench/perf_*.luau`. Raw output: `perf_results-v1.txt` in the same folder.
Date: 2026-10-31. Lune 0.8.9.

---

## Summary

1. **Network and yields run before the loader exists.** `CreateWindow` parents the ScreenGui at line 1255, builds a full-size 980x660 window, and then yields twice:
   - the first `drawIcon` (line 1300) calls `loadLucideIndex`, which runs `game:HttpGet` on a 147,702-byte `Icons.luau` (line 374) and then `loadstring`s it, at a CPU cost of 14-43 ms in Lune;
   - `GetUserThumbnailAsync` runs synchronously at line 1309.

   The loader pill is created only at lines 3183-3187, so during those yields the player sees a half-built, full-size window. Then it snaps down to a 392x108 pill and grows back.
2. **Build time is quadratic.** `unbindTheme` (lines 208-215) scans the whole `_themeBindings` list linearly. It runs about 43 times per 40-control tab, while the list grows by about 325 entries per tab. Measured builds:

   | Controls | Build time (Lune ms) |
   |---|---|
   | 200 | 77-133 |
   | 400 | 187-645 (median about 320) |
   | 800 | 832-1,414 |
   | 1,200 | 1,689-2,565 |

   Tab 30 takes 7-11x as long to build as tab 1. Timing each control kind confirms the cause: only controls that call `unbindTheme` get slower as more is built (Segmented goes from 1.0 to 10-12 ms per tab, Toggle from 1.1 to 9 ms). Controls that never call it stay flat (Button and Divider 0.2-0.5 ms).
3. **Everything is built at once, eagerly, into a live tree.**
   - 400 controls produce 5,516 instances (13.8 per control) and 36,374 property writes, in one uninterrupted run.
   - The library never slices the work. The README asks the host to add `task.wait()` instead.
   - Unless the host opts into manual loading, fixed timers at 0.38 s and 0.93 s reveal the window whatever state the build is in (lines 3351-3363).
4. **Popups and lists are rebuilt from scratch on every use.**

   | Action | Lune ms | Instances created | Other cost |
   |---|---|---|---|
   | Open a 200-option dropdown (every open) | 12-20 | 611 | 602 connections, 407 theme bindings |
   | `List:SetItems` with 200 rows | 27-77 | 1,600 | 1,200 connections, 1,400 bindings |
   | `List:AddItem` on a 200-row list | 28-118 | rebuilds all rows | |
   | Open the theme picker (400 controls built) | 17-57 | grid rebuilt | |
   | Open the theme picker (after popups bloat the registry) | 155-248 | grid rebuilt | |

5. **Idle work never stops, and it leaks.**
   - Every slider adds 2 permanent global `UserInputService` handlers and every keybind adds 1. Every colour-picker open adds 2 more that are never disconnected.
   - With 400 controls, 43 `InputChanged` handlers run on every mouse move, even while the window is hidden. After 50 picker opens there are 53.
   - Re-executing a script stacks everything: after 5 runs there are 55 `InputChanged`, 25 `InputBegan` and 5 `RenderStepped` handlers, plus 5 prune loops running forever.
   - The status halo tween loops forever, even while the window is hidden.
   - The 30-second prune sweep costs 12-36 ms of unsliced Lune time per tick.
6. **Theme switching works by guessing colours.** `create()` runs `themeKeyForColor`, a linear scan of the palette, on every `Color3` write: 4,141 scans for 400 controls. The result is 3,253 per-property bindings and 1,256 font bindings. A switch then repaints them at 350 per frame (line 664), which is a visible 10-frame wipe.
7. **v2 can hit every target below** without changing the public API. The design: no network and no yields at load, the loader drawn first, a component model with lazy, frame-budgeted mounting, per-component ownership with token theming instead of colour scans and global lists, one input router, pooled and virtualised popups and lists, engine-side flex layout instead of Lua size listeners, and zero work while idle. Each target is set against a measured v1 number (section 7).

---

## 1. Method, and which numbers are proxies

- The benches load the **real** `argon-ui.luau` through the repo's own `tests/sandbox.luau`, which is required read-only from `../../argon-UI/tests/sandbox`. The library is not modified.
- `perf_harness.luau` instruments the sandbox from outside:
  - wraps `Instance.new` to count instances per class, property writes, `Color3` writes, `FontFace` writes and `GetPropertyChangedSignal` subscriptions;
  - wraps `TweenService:Create` to count tweens, and infinite ones (`RepeatCount = -1`);
  - wraps `task.defer`, `task.delay` and `task.spawn`;
  - counts `GetUserThumbnailAsync` calls;
  - reads `Argon._connections`, `_themeBindings` and `_themeRenderers`, and the handler lists of the global `UserInputService` and `RunService` signals.
- `FONT_BINDINGS` is a private local. Its size is measured as the number of `FontFace` writes during `SetFont(current)`, which rewrites every surviving binding (lines 543-556).
- Executor emulation:
  - `loadstring` is mapped to `luau.load`, a real bytecode compile, the same work an executor does;
  - `getcustomasset` is provided for the atlas paths;
  - `game:HttpGet` serves a synthetic Lucide index padded to the **real size**. A HEAD request on 2026-10-31 to `raw.githubusercontent.com/latte-soft/lucide-roblox/master/lib/Icons.luau` returned `Content-Length: 147702`. The synthetic file has the same shape: 16px, 48px and 256px tables of `{assetId, {w,h}, {x,y}}`.
- The main workload (`perf_workload.luau`) is 10 tabs x 40 mixed controls, 400 in total: 4 sections per tab, and the 4th section of each tab built through a 2-column `Row`. The mix covers all 18 kinds plus Description and Tooltip variants. 280 controls have flags.
- **Exact numbers** that transfer 1:1 to a real client: instance counts, property-write counts, binding, connection and handler counts, subscriptions, tweens, timers, network calls and yields.
- **Proxy numbers** (all times in ms): Lune CPU time of the library's Luau logic plus the sandbox's Lua stand-ins for instances. Real `Instance.new` and property writes are C++ calls with extra engine work (change signals, layout invalidation, text shaping, rendering) that is **not** included. Use the times for relative comparisons and as regression gates, not as client frame times. The machine was noisy, so every time is reported as the range across 2-15 runs.
- The sandbox has **no layout engine.** `AbsoluteSize` and `AbsoluteContentSize` never change on their own, so the relayout cascades in section 5 cannot run. `perf_resize.luau` fires each subscribed size signal once to measure the first wave as a lower bound.
- `Instance:Destroy()` does not disconnect connections in the sandbox, but it does in Roblox. So `PruneRegistries` reclaims nothing here (`connections pruned = 0`); in a client it reclaims connections to destroyed instances, but never global `UserInputService` ones.

---

## 2. Measured numbers

### 2.1 Library load (require time)

| Metric | v1 |
|---|---|
| Source size | 296,126 bytes, 3,369 lines |
| Base64 atlas + logo payload | 48,456 bytes (16.4%): atlas 17,628, logo 30,828 |
| Full-line comments | 41,775 bytes (14.1%) |
| Compile (`luau.compile`, the same work as an executor's `loadstring`) | 16.4-23.1 ms |
| Compile with comments and base64 stripped (205,888 bytes) | 13.7-20.9 ms |
| `sandbox.load` (compile + top level), atlas cached or no `getcustomasset` | 16.3-23.7 ms |
| `sandbox.load` on first run with `getcustomasset` (decode + 2 x `writefile`) | 32.7-48.8 ms (**+11 to +25 ms**) |
| `decodeBase64` alone (atlas + logo, giving 13,221 + 23,120 bytes of PNG) | 9.3-11.5 ms |
| Work started at require time | the 30-second prune loop (line 268); atlas and logo prepared (lines 155-156) |

### 2.2 CreateWindow

| Metric | v1 |
|---|---|
| CreateWindow, Lucide index fetched and parsed inside it (first `drawIcon`, line 1300) | 15.6-43 ms |
| CreateWindow with the index already parsed | 3.9-7.3 ms |
| First `Argon:GetIcon` (HttpGet + `loadstring` of 147.7 KB + cache write) | 13.9-43 ms CPU, **plus the network round trip** |
| `GetIcon` after the parse | 1.4-3.9 µs per call |
| Network calls and yields before any loader pixel | up to **2**: HttpGet of `Icons.luau` (when not cached; when GitHub is unreachable nothing is cached, so it **retries every launch**) and `GetUserThumbnailAsync` (line 1309) |
| Instances | 184: Frame 62, UICorner 42, TextLabel 23, UIStroke 12, ImageLabel 11, UIGradient 8, UIListLayout 7, CanvasGroup 1 |
| Property writes / `Color3` writes (each runs `themeKeyForColor`) | 1,220 / 102 |
| Theme bindings / renderers / `Argon._connections` | 86 / 1 / 30 |
| Global handlers: UIS InputChanged / InputBegan / InputEnded / RenderStepped | 3 / 1 / 3 / 1 |
| Infinite tweens started | 6: 5 on the loader, plus the status halo (line 1328), **which runs forever** |
| Timers | 0.38 s (expand), 0.93 s (auto-open), 4 s (autosave fallback), 30 s (watchdog), 30 s (prune) |
| Window state after 0.93 s without manual loading | open (`IsLoading() == false`) |

### 2.3 The big build: 10 tabs x 40 controls

| Metric | v1 |
|---|---|
| Build time | **187-645 ms** across 15 runs, median about 320 ms; 0.47-1.6 ms per control |
| Per-tab time, tab 1 to tab 10 (typical run) | 16 15 18 19 21 29 34 39 35 45 ms; worst run 33 to 110 ms |
| Instances created | **5,516 (13.8 per control)**; 5,657 live descendants of the ScreenGui |
| By class | UICorner 1,499 · Frame 1,410 · TextLabel 900 · **UIStroke 729** · TextButton 419 · UIListLayout 160 · UIPadding 139 · TextBox 100 · ImageLabel 90 · UIGradient 40 · ScrollingFrame 30 |
| Property writes | **36,374 (90.9 per control)** |
| `Color3` writes, each a `themeKeyForColor` palette scan | 4,141 |
| `Argon._themeBindings` / `_themeRenderers` / `FONT_BINDINGS` | **3,253** / 191 / **1,256** |
| `Argon._connections` | 1,797 |
| Global UIS handlers: InputChanged / InputBegan / InputEnded | **43 / 21 / 43** |
| Lua size listeners | **220** `AbsoluteSize` + **50** `AbsoluteContentSize` subscriptions |
| Tweens / `task.defer` / `task.delay` during the build | 306 / 240 / 2 |

### 2.4 Scaling: the quadratic build

| Build | Total (Lune ms, range) | Tab 1 → last tab |
|---|---|---|
| 5 x 40 (200) | 77-133 | 15-20 → 18-36 |
| 10 x 40 (400) | 187-645 | 12-33 → 40-110 |
| 20 x 40 (800) | 832-1,414 | 17-22 → 84-162 |
| 30 x 40 (1,200) | 1,689-2,565 | 16-18 → 133-177 |

Experiments that pin the growth on `unbindTheme`:

- **Per kind, per tab** (`perf_kinds.luau`, ms per tab for tabs 1 → 12):

  | Kind | `unbindTheme` calls per control | Tab 1 → tab 12 |
  |---|---|---|
  | Segmented | 6 (2 per pill) | 1.0 → 10.1 |
  | Toggle | 2 | 1.1 → 9.0 |
  | Input | 2 | 0.6 → 4.3 |
  | Keybind | 1 | 0.3 → 2.7 |
  | Dropdown | 1 | 0.4 → 3.0 |
  | ColorPicker | 1 | 0.3 → 1.9 |
  | Button, Divider, Label, ProgressBar, TextArea, Paragraph, Slider | 0 | flat at 0.2-0.8 |

- **Pre-filling the list** with inert bindings, then timing one 40-control tab: about 2,000 entries → 19-46 ms; 12,000 → 36-64 ms; 32,000 → 63-115 ms.
- **The scan itself:** one `unbindTheme` call over 4,000 bindings costs 0.36 ms on a compact heap. Inside the real build it costs about 1-2.5 ms per call (inferred from the per-kind growth), because the bindings are scattered across a 19 MB heap.
- **Heap size alone is not the cause:** adding 300k junk tables does not change per-tab time.

### 2.5 Features and interactions

| Action | Lune ms | Instances created | Other effects |
|---|---|---|---|
| Dropdown with 200 options, **open** | 11.8-19.6 | **611** | 602 connections, 407 theme bindings, 4,081 property writes, **on every open** |
| Same dropdown, reopen (median of 20) | 11-22 | 611 | rebuilt every time; after 21 opens: **12,677 connections, 8,647 bindings** retained until the 30 s prune |
| Dropdown filter keystroke (200 rows) | 0.08-0.19 | 0 | fine (toggles `Visible`) |
| `dropdown:Set` x 200 | 3.8-11.2 | 0 | 2 x `JSONEncode` per call (lines 2487-2488) |
| Colour picker, open | 0.46-1.36 | 24 | **+2 global UIS handlers per open, never disconnected** |
| Colour picker, 50 opens | | | `InputChanged` handlers 3 → **53** |
| `List:SetItems`, 200 rows with 2 actions | **27-77** | **1,600** | 1,200 connections, 1,400 bindings |
| `SetItems` again (destroy + rebuild) | 33-90 | 1,600 | |
| `List:AddItem` on a 200-row list | **28-118** | 1,600+ | copies the array and rebuilds every row |
| `SetItems` with 200 plain strings | 6.3-34 | | |
| Theme switch, 400 controls built | 10.9-28 (synchronous renderers + binding pass) | | in a client: **10 frames** of staggered repaint (3,223 bindings / 350 per frame) |
| `SetFont`, 400 controls built | 1.7-2.5 | | 1,256 `FontFace` writes |
| Theme picker open, 3,313 bindings | **17-57** | about 130 | grid destroyed and rebuilt on every open; 60 `unbindTheme` scans |
| Theme picker open, about 10k bindings (after the popups above) | **155-248** | about 130 | |
| Theme picker open, 505 bindings | 5.8 | | |
| Sidebar search keystroke (40-control tab) | 0.09-0.24 | 0 | fine |
| Tab switch | 0.37-1.05 | jump-rail chips rebuilt | `_refreshSectionMenu` destroys and recreates every chip |
| Notification | 0.30-1.34 each | **26 per toast, including a CanvasGroup** | 3 connections, 2 tweens, an icon draw; 50 toasts in a burst take 15-67 ms |
| Tooltip hover | 0.75-2.5 | 6 per hover | built on hover, destroyed on leave |
| Keybind press (20 binds) | 0.13-0.35 | 7 | keybind overlay destroyed and rebuilt; twice per press when `Toggle = false` |
| Player join, 50-player server | 8.7-8.8 | **302** | **50 `GetUserThumbnailAsync` calls**, +201 bindings, even when the overlay is hidden or disabled |
| Slider drag | 0.017-0.023 per move | | 120 moves → 84 tweens + 168 `task.delay` timers |
| `SaveConfiguration`, 280 flags | 0.7-3.3 | | write + read-back verify |
| `LoadConfiguration`, 280 flags | 19-34 (library side only) | | host callbacks not included |

### 2.6 Idle and background

| Metric | v1 |
|---|---|
| Lua handlers run per mouse move, 400 controls, window visible **or hidden** | 43; sandbox fan-out 5-13 µs per event |
| Lua handlers run per key press | 21 |
| RenderStepped handlers | 1 per window, per execution: `pcall` + closure allocations every frame while visible |
| Infinite tweens at rest | 1 (status halo, line 1328), kept while hidden |
| Periodic work | `PruneRegistries` every 30 s, 12-36 ms in one unsliced block for 400 controls |
| Size listeners, first wave after a resize (lower bound) | **274 handlers, 634 property writes**, 14.7-20 ms in Lune; in a client each write triggers another wave |
| Handlers after 1 vs 5 script executions, 2-tab hub (InputChanged / InputBegan / RenderStepped) | 11/5/1 → **55/25/5**; 5 prune loops and 5 watchdogs alive |

### 2.7 Per-control cost (one control, Lucide icons available)

`inst` = instances, `crnr` = UICorner, `strk` = UIStroke, `props` = property writes, `bind` = theme bindings, `conn` = `Argon._connections`, `UIS` = permanent global input handlers, `size subs` = Lua `AbsoluteSize` / `AbsoluteContentSize` listeners.

| Control | inst | crnr | strk | props | bind | conn | UIS | tweens | size subs |
|---|---|---|---|---|---|---|---|---|---|
| CreateTab | 14 | 3 | 0 | 92 | 4 | 4 | 0 | 0 | 1 |
| CreateSection | 10 | 2 | 1 | 47 | 4 | 0 | 0 | 0 | 0 |
| Toggle | 9 | 3 | 1 | 49 | 3 | 3 | 0 | 2 | 0 |
| Toggle + Description | 10 | 3 | 1 | 66 | 4 | 6 | 0 | 2 | 2 |
| Toggle + Tooltip | 11 | 4 | 1 | 67 | 5 | 6 | 0 | 2 | 1 |
| Slider | 16 | 5 | 4 | 84 | 10 | 6 | **2** | 0 | 0 |
| Slider + Description | 17 | 5 | 4 | 101 | 11 | 9 | **2** | 0 | 2 |
| Button | 7 | 2 | 1 | 45 | 5 | 3 | 0 | 0 | 0 |
| Dropdown (closed) | 11 | 2 | 2 | 77 | 6 | 1 | 0 | 0 | 0 |
| Input | 15 | 5 | 2 | 93 | 8 | 5 | 0 | 0 | 0 |
| Keybind (includes the overlay rebuild) | 8 | 2 | 2 | 60 | 6 | 4 | **1** | 0 | 0 |
| ColorPicker (closed) | 8 | 2 | 2 | 54 | 4 | 1 | 0 (+2 per open) | 0 | 0 |
| Paragraph | 12 | 2 | 1 | 82 | 6 | 0 | 0 | 0 | 0 |
| Stepper | 12 | 4 | 2 | 81 | 10 | 9 | 0 | 0 | 0 |
| Segmented (3 options) | 14 | 5 | 1 | 103 | 4 | 3 | 0 | 6 | 0 |
| Label | 10 | 2 | 1 | 69 | 5 | 0 | 0 | 0 | 0 |
| ProgressBar | 10 | 3 | 2 | 61 | 7 | 0 | 0 | 1 | 0 |
| Divider | 6 | 1 | 1 | 44 | 5 | 0 | 0 | 0 | 0 |
| TextArea | 8 | 2 | 2 | 56 | 7 | 2 | 0 | 0 | 0 |
| List (5 rows, 1 action each) | 40 | 12 | 1 | 309 | 32 | 16 | 0 | 0 | 1 |
| TelemetryCard | 16 | 2 | 2 | 116 | 6 | 0 | 0 | 0 | 0 |
| Row(2), empty | 6 | 0 | 0 | 32 | 0 | 4 | 0 | 0 | 4 |
| Toggle inside a Row | 9 | 3 | 1 | 53 | 3 | 4 | 0 | 2 | 1 |
| `Lock()` (adds to a 7-instance Button) | +11 | +2 | +1 | +94 | +6 | +2 | 0 | 0 | 2 |
| Notify (one toast) | 26 (**CanvasGroup**) | 7 | 2 | 142 | 12 | 3 | 0 | 2 | 0 |
| Dialog | 15 | 3 | 3 | 112 | 10 | 7 | 0 | 3 | 0 |

When Lucide is unavailable and there is no `getcustomasset` (polyline fallback, lines 431-441), each icon becomes 1 Frame plus a line Frame + UICorner per segment and a cap per point. A tab costs **47** instances instead of 14, and a closed Dropdown 20 instead of 11.

---

## 3. What a player sees on first launch today (400-control hub)

The order follows the code. Network times are typical ranges, not measurements.

1. **`loadstring(game:HttpGet(raw))()`** downloads 296 KB, of which 90 KB is comments and base64. Compiling takes 16-23 ms. On first run with `getcustomasset`, the base64 is decoded and written at require time: +11 to +25 ms (lines 155-156).
2. **`CreateWindow`** parents the ScreenGui (line 1255), then builds the shadow, a full-size 980x660 `main` (line 1280), the glow CanvasGroup and the sidebar. All of this is live and visible.
3. At **line 1300** the first icon triggers the Lucide fetch: HttpGet of 147.7 KB, usually 100-500 ms depending on executor and region (some executors block the client instead of yielding), then a 14-43 ms parse.
4. At **line 1309** `GetUserThumbnailAsync` yields again, typically 50-300 ms and seconds when throttled.

   **During steps 3 and 4, a half-built full-size window is on screen with no loader.**
5. The loader is created **only at the end** (lines 3183-3187), and the window snaps from 980x660 down to a 392x108 pill.
6. The host builds 400 controls in **one block of about 0.2-0.65 s (Lune proxy)**. No frame renders during it, so the loader's "working" animation is frozen. The README tells hosts to add `task.wait()` themselves.
7. The 0.38 s and 0.93 s timers are already overdue, so they fire on the next resume. The shell expands by **tweening `main.Size`** (lines 3280-3288). For 0.42-0.52 s that resizes a container holding about 5,600 instances every frame, and the 270 Lua size listeners fire on every one of those frames: this is the relayout storm, right during the reveal.
8. `LoadConfiguration` takes 19-34 ms of library time plus the host callbacks. Each restored keybind rebuilds the keybind overlay, and each dropdown runs 2 `JSONEncode`s.

---

## 4. Ranked hotspots

Severity is impact on what the owner reports: load time, loader quality, feature latency, and jank.

| # | Sev | Hotspot | Where | Evidence |
|---|---|---|---|---|
| 1 | critical | Network and yields on the critical path, before the loader exists; a half-built full-size window is visible meanwhile | `loadLucideIndex` 339-389 (HttpGet 374, `loadstring` 344) reached from `drawIcon` 418-443 via line 1300; `GetUserThumbnailAsync` 1309; GUI parented 1255; loader only at 3183-3187 | 147,702 B fetched; 14-43 ms parse; 2 yields measured in CreateWindow; a failed fetch is never cached (`LUCIDE_SET=false` lasts one session), so every launch retries |
| 2 | critical | Quadratic build from the `unbindTheme` linear scan | 208-215; callers 1715-1717, 2301, 2405, 2447, 2460, 2586, 2741 (x2 per Segmented pill), 2903, 3041-3051 | 200 → 1,200 controls: 77-133 → 1,689-2,565 ms; tab 30 is 7-11x tab 1; per-kind and pre-fill experiments in 2.4 |
| 3 | high | Eager, synchronous, unsliced build into a live tree; timer-driven reveal | every `create()` 275-294 parents into a live GUI; no mount queue; timers 3351-3363; README "Loading a big interface" | 5,516 instances and 36,374 property writes in one block; window open after 0.93 s regardless of the build |
| 4 | high | Popups and overlays rebuilt on every open; garbage retained until the 30 s prune | dropdown 2516-2545; theme picker 3033-3057 and 3065-3070; tooltip 2208-2219; chips 2978-2997; colour picker 2876-2898 | dropdown(200): 611 instances, 602 connections, 407 bindings per open; theme picker 17-57 ms (155-248 ms when bloated); 6 instances per tooltip hover |
| 5 | high | Global input handlers per control, never disconnected; re-execution leaks the whole previous instance | slider 2346-2347; keybind 2435; colour picker 2894-2895 (per **open**); overlays 1459/1464; window drag 3085-3092; re-exec 1247-1251 only destroys the GUI | 43 InputChanged / 21 InputBegan handlers for 400 controls; +2 per picker open; 5 executions → 55/25/5 handlers and 5 prune loops |
| 6 | high | List has no virtualisation and no incremental updates | `SetItems` 2792-2842; `AddItem` 2843-2845 | 200 rows: 27-77 ms, 1,600 instances, 1,200 connections; `AddItem` 28-118 ms |
| 7 | high | Heavy instance recipe: 13.8 instances per control; corners and strokes everywhere; Frame root plus transparent overlay button | `base` 1944-2247; `corner`/`stroke` 296-302; every `Create*` | UICorner 1,499 (27%), UIStroke 729 (13%) of 5,516 |
| 8 | medium | Theming by colour inference; huge per-property registries; staggered repaint | `themeKeyForColor` 178-183; `registerThemeBinding` 185-201; `create()` 280; `SetTheme` 623-670 (350 per frame at 664); fonts 513-556 | 4,141 palette scans; 3,253 theme bindings + 1,256 font bindings; 10-frame wipe; 191 renderers run synchronously |
| 9 | medium | Lua relayout listeners and nested AutomaticSize | Row 1869-1903, 1918, 1922; `SetDesc` 1995, 2021-2022; tooltip marker 2134-2135, 2163; `Lock` 2094-2097 | 220 + 50 size subscriptions; one wave = 274 handlers, 634 writes; the shell-expand tween (3280-3288) and resize drag (3085-3087) fire it every frame |
| 10 | medium | Base64 atlas and logo in the source, decoded in pure Luau at require time | 97-107, 109-125, 127-156 | 48,456 B (16.4%) of the download; 9-12 ms decode + 2 file writes on first run; only serves 18 fallback icons and a logo |
| 11 | medium | CanvasGroups: one per toast (AutomaticSize, then a Size tween on dismiss) and a permanent full-window glow group | 1164, 1202-1205; 1282-1284 | 1 render target per toast (cap 5); a 980x660 target kept for two decorative discs |
| 12 | medium | Player overlay rebuilds every row and re-requests every avatar on each join or leave, even when disabled | 1542-1557, 1578 | 302 instances + 50 thumbnail calls + 201 bindings per join at 50 players |
| 13 | medium | Notifications are not pooled | 1145-1219 | 26 instances, 3 connections, an icon draw and 2 tweens per toast; the cap is enforced by a `GetChildren` scan |
| 14 | low | Idle per-frame and periodic work | RenderStepped 3159-3169; halo 1328-1329; prune 261-268 | runs while hidden; prune 12-36 ms per 30 s, unsliced; `pcall` closures allocated every frame |
| 15 | low | Keybind overlay rebuilt on every `Set`, `SetActive` and create | 1558-1577, 2425, 2428, 2441, 2448 | 7 instances per press; rebuilt once per keybind during restore |
| 16 | low | Dropdown `Set` compares with 2 x `JSONEncode` | 2487-2488 | 19-56 µs per call |
| 17 | low | New Tween object per hover and per change; `changed()` starts a tween and 2 timers per value change | `hover` 787-797; `changed` 831-838; `scheduleSave` 769-779 | slider drag: 84 tweens and 168 timers per 120 moves |
| 18 | low | Lucide index keeps all 3 size tables in memory and uses only 48px | 342-349 | about 3 x 1,000 entries parsed; 2/3 never used |

---

## 5. Roblox-side costs the sandbox cannot show

These follow from the code. They are reasoned, not measured. Confirm them in v2 with MicroProfiler labels (see 6.10).

- **Constructing into a live tree.** The ScreenGui is parented at line 1255, before anything is built. Every later `create()` that sets `Parent` inserts into a live, rendered hierarchy, which fires ancestry and descendant events and invalidates layout once per insertion. Building a subtree unparented and parenting its root once batches all of that into one invalidation.
- **Layout passes.**
  - The chains are deep: section root (AutomaticSize Y) → body (AutomaticSize Y) → controls, inside a page UIListLayout whose `AbsoluteContentSize` handler writes `CanvasSize` (`bindCanvas` 581-585). Paragraph, Label, TelemetryCard, toast, tooltip and the lock badge are AutomaticSize too.
  - The comment at 1859-1861 admits nested AutomaticSize "settles a frame late".
  - The Lua listeners (Row relayout and balance, `fitDescription`, `placeMarker`, `Lock.fit`) **write sizes from inside size-changed handlers**, so one engine layout pass becomes several, and the re-entrancy guard at 1868-1871 only stops nesting, not repeated waves on later frames.
  - Every row also listens to its section body's size (line 1903), so any height change in a section re-runs every row in it.
- **Hidden tabs.** Inactive pages are `Visible = false` (line 1686) but stay parented, keep all their Lua listeners connected, and keep `AbsoluteSize` updated. A window resize therefore touches all 10 pages, not just the visible one. Whether the engine fully skips layout for invisible subtrees is internal; v2 should not depend on it.
- **Animating `main.Size`.**
  - `expandShell` (3280-3288) and resize-drag `SetSize` (3087) resize the container of the entire UI on every frame of the tween or drag: a full relayout plus all size listeners, per frame.
  - Tab transitions tween `Position` instead (1669, 1676), which is fine because only `AbsolutePosition` changes.
- **Render cost.**
  - A visible 40-control tab holds about 550 instances, including about 75 UIStrokes and about 150 UICorners. Strokes and rounded corners are extra geometry per object.
  - The glow CanvasGroup (1282) holds a window-sized offscreen render target: about 2.5 MB RGBA at 980x660 at 1x, and more on high-DPI screens. It exists for two semi-transparent circles.
  - Each toast is a CanvasGroup whose size keeps changing: AutomaticSize while the text settles, then the 0.2 s Size tween on dismiss. A group that changes size re-allocates and re-rasterises its target. The window comment at 1271-1279 describes the same problem.
- **Text.** 900 TextLabels use `FontFace` families that load asynchronously. `SetFont` rewrites 1,256 faces, so every text object re-shapes.
- **Tweens.** TweenService steps every live tween each frame. Hover, changed and state tweens are new objects every time (garbage), and the looping halo never ends.
- **Input fan-out.** Each mouse-move event crosses into Luau once per connected `InputChanged` handler, 43 to 55+ times, and each handler reads `InputObject` properties through the C++ bridge. High-polling mice deliver several events per frame. It all happens with the window hidden too.
- **Network.**
  - `GetUserThumbnailAsync` is a web call; it is cached after the first call in a session, but here it runs synchronously in `CreateWindow`.
  - In a full server, the player overlay issues 50 calls per join (1550).
  - `game:HttpGet` behaviour depends on the executor; some block the client thread.
- **Memory.**
  - Luau side: 1,797 connection closures, plus `_themeBindings`, `_themeRenderers` and `FONT_BINDINGS` entries, each pinning an Instance until the next prune.
  - Popups multiply this between prunes: one dropdown(200) open adds 602 connections and 407 bindings.
  - Global UIS connections are never pruned (`UserInputService` is never destroyed), and their closures pin destroyed popup instances: the colour-picker leak.

---

## 6. v2 performance architecture

### 6.1 Distribution and require time: no network, no IO, no decode
- **Build step** (`tools/build.luau`, Lune): strip comments and emit `dist/argon-ui.luau`. Readable `src/` stays the source of truth. Target ≤ 180 KB, down from 296 KB.
- **Embed a compact Lucide map** generated at build time, 48px set only:
  - format `name=sheet.col.row;`, with the sheet asset ids in a small array;
  - measured: **24 KB** for 1,100 icons, **0.24 ms** to compile, **0.9-1.8 ms** to build the full lookup table lazily on the first `GetIcon`;
  - compare v1: 147.7 KB over the network plus a 14-43 ms `loadstring`.

  Remove the runtime `HttpGet`/`loadstring` path entirely. For unknown names, either fall back to a generic glyph or offer an opt-in asynchronous `Argon:FetchIcons()` that never blocks the UI.
- **Delete the base64 atlas and logo.** Lucide already provides the 18 fallback icons as public Roblox assets. Ship the logo as an uploaded `rbxassetid`, or keep the Frame-drawn mark the code already has (lines 455-460). No `getcustomasset`, `writefile` or `makefolder` at require time.
- **Nothing runs at require time** except table definitions. No prune loop (ownership replaces it, see 6.4) and no timers.
- **Re-execution safety:** at load, call `getgenv().__ArgonUI` (when present) `:Destroy()`, which disconnects the router and scheduler and destroys every scope, then register the new instance there.

### 6.2 Window: draw the loader first, never yield
- `CreateWindow` creates **only the loader card**, at most 25 instances, parents it and returns. The shell, sidebar and topbar are built **unparented** and parented once, at their final size, when revealed.
- **No `main.Size` tween with content inside.** Animate the loader card on its own, then show the shell with position and transparency tweens on a few top-level frames. Position changes do not trigger relayout.
- **Avatars without yields:** `rbxthumb://type=AvatarHeadShot&id=<UserId>&w=48&h=48` set as `Image`, with zero API calls. Use the same for player-list rows.
- **The reveal is driven by the mount queue, not timers.** The window opens once the active tab is mounted (within 1-2 frames for typical hubs); the other tabs mount in the background. Keep `SetLoadingProgress`/`FinishLoading` and `Loading = "manual"` for hosts doing their own asynchronous work, plus the 30 s watchdog.

### 6.3 Component model: lazy, budgeted mounting
- Every `Create*` returns its element object **immediately**, backed by a state table: `Set`, `CurrentValue`, `Refresh`, `Lock`, callbacks and flags all work without any instances. Calling the API costs **≤ 0.05 ms per control**.
- **Mounting** (creating instances) happens per tab, through a single `Scheduler`:
  - frame budget: 4 ms per frame while the window is visible and the user is interacting, 8 ms while the loader is up, stopped (and its Heartbeat disconnected) when the queue is empty;
  - priority: active tab, then a tab whose button is hovered (prefetch), then the rest in order;
  - hidden tabs are **detached** (`Parent = nil`) instead of `Visible = false`, so resizes never reach them.
- **Compatibility shim:** `element.Root` and other instance fields are served through `__index` and force a synchronous mount of that element's tab on first access. Scripts that poke instances keep working; everyone else gets lazy mounting.
- Construction recipe: create the children, set properties, set `Parent` last. Build a tab's page while it is detached and parent it once.

### 6.4 Ownership instead of global registries
- Each component owns a **Scope** (a maid): its instances, connections, timers, tweens and theme hook. `Destroy` is O(own size). There is no `_connections` list, no `_themeBindings` list, no `FONT_BINDINGS` and no `unbindTheme`, so **the quadratic scan disappears by construction**.
- A popup's transient connections live in the popup's scope and are released on close.

### 6.5 Token theming
- Components **declare** tokens, `Theme.bind(scope, obj, "BackgroundColor3", "Surface")`, or implement `applyTheme(palette)` for state-driven parts. Colours are never inferred from values: `themeKeyForColor` and per-property bindings are removed.
- A theme switch increments `themeVersion` and repaints **mounted, visible** components synchronously, in one frame. Detached and unmounted components compare the version when shown or mounted. Fonts work the same way (`fontVersion`).
- Optional: when the engine's UI-styling objects exist (feature-detected with `pcall(Instance.new, "StyleSheet")`), map tokens to stylesheet tokens so the engine applies switches natively. Treat this as an enhancement only; executor and CoreGui support is unverified.

### 6.6 Input: one router, zero idle handlers
- One `InputBegan` connection per window. Keybinds dispatch through a `KeyCode → {entries}` map in O(1); the toggle key and `/` go through the same router.
- `InputChanged`/`InputEnded` are **connected on drag start and disconnected on drag end** (slider, colour square and hue, window drag and resize, overlay drag). Nothing runs at idle.
- The cursor driver connects `RenderStepped` only while it is actually needed (engine cursor off and window visible), re-evaluated on visibility change and on `MouseIconEnabled` change, instead of polling every frame.

### 6.7 Pooled popups and virtualised lists
- **One popup layer per window**, built once. Dropdown, colour picker and context menus reuse it: opening means reposition, set data, tween. The dropdown option list is **virtualised**: about 10 recycled rows (visible plus overscan) for any option count. Filtering rebuilds the data array and re-renders the pooled rows.
- **Tooltip:** one instance per window, retargeted.
- **Theme picker:** built once and re-rendered on theme change. **Jump chips:** keyed diff.
- **Keybind overlay:** rows keyed by entry and updated in place, with a dirty flag and one deferred refresh per frame, so a restore of N keybinds refreshes once.
- **Player list:** a row per `UserId`; join adds one row, leave removes one; `rbxthumb` avatars; **no work while the overlay is disabled**.
- **List:** virtualised above about 30 rows (fixed row heights of 30 and 44 already exist). `SetItems` diffs by key (`Id` or `Title`), and new `AddItem`, `RemoveItem` and `UpdateItem` are O(1). The `AddItem` signature stays.
- **Notifications:** a pool of 5 plain-Frame toasts (no CanvasGroup), each recycled with its own scope; one tween drives the progress bar.

### 6.8 Layout handled by the engine
- **Rows:** use `UIListLayout` flex (`Wraps = true`, `HorizontalFlex`, `ItemLineAlignment = Stretch`) with `UIFlexItem` and a minimum-width constraint. Columns wrap when narrow and line heights match, with **zero Lua listeners** where v1 needs 14 per 2-column row of 10 controls (12 `AbsoluteSize` + 2 `AbsoluteContentSize`).
- **Description and tooltip marker:** AutomaticSize Y with a vertical `UIListLayout`; the title and marker sit in a horizontal AutomaticSize X list. No `pinIntoBand` and no `ChildAdded` hook.
- **Lock badge tiers:** use `TextService:GetTextSize` once per reason (a pure function), not `AbsoluteSize` listeners.
- **Any measurement that remains** goes through a per-frame coalescer, `markDirty(component)` plus one deferred pass per frame, and never writes sizes from inside size handlers.
- **No CanvasGroup at rest.** Replace the glow with one ImageLabel using a soft radial asset, or drop it.

### 6.9 Animation and idle
- A small animator that reuses one Tween per (object, property set), or drives springs from a single RenderStepped connection that exists **only while something is animating**.
- **No infinite tweens at rest.** The status dot pulses once on state change. Loader loops stop with the loader.
- **When the window is hidden:** pause all animation, disconnect drag handlers, and stop scheduler mounting unless it is prewarming. Overlays that are still pinned keep only what they need.
- A **Reduced motion** setting doubles as an accessibility option.

### 6.10 Diagnostics
- `Argon:GetPerfStats()` returns live instance count, mounted and pending controls, connections, global handlers, last mount ms and last theme-switch ms.
- `debug.profilebegin("Argon/mount <tab>")` labels make the phases visible in the MicroProfiler. That is the real-client confirmation of the proxy numbers in this report.
- Keep `perf_*.luau` as a **CI budget gate** that fails when a budget in section 7 regresses (counts are exact; time gates set at 1.5x the budget to absorb noise).

---

## 7. Budgets v2 should hit

Time budgets are in Lune ms, so they are comparable with the v1 column. The real-client goal is the third column.

| Area | v1 measured | v2 budget (Lune gate) | Real-client goal |
|---|---|---|---|
| Download size | 296 KB (90 KB comments + base64) | ≤ 180 KB | |
| Compile (`luau.compile`) | 16-23 ms | ≤ 0.75x v1 on the same machine (about ≤ 14 ms) | |
| Require-time work | +11 to +25 ms decode/write on first run, prune loop, 2 file writes | **0 IO, 0 timers, ≤ 2 ms** | |
| Network calls or yields before the first loader frame | up to 2 (Lucide HttpGet, thumbnail) | **0** | loader visible on the frame after `CreateWindow` |
| `CreateWindow` | 4-43 ms, 184 instances, loader built last | **≤ 3 ms, ≤ 30 instances**; shell parented once at reveal | |
| Full shell when revealed | 184 instances | ≤ 120 instances | |
| API cost per control (lazy) | 0.47-1.6 ms (eager build) | **≤ 0.05 ms** | |
| 400-control script completes (all `Create*` calls) | 187-645 ms | **≤ 25 ms** | no startup frame longer than about 33 ms |
| Mounting one 40-control tab | 12-110 ms (grows with the tab index) | **≤ 8 ms**, sliced into frames of at most 4 ms | tab ready within 2 frames |
| Scaling | quadratic: 1,200 controls 1,689-2,565 ms; tab 30 = 7-11x tab 1 | **linear**: tab N within 1.2x of tab 1; 1,200 controls API ≤ 75 ms | |
| Instances per control (average, mixed) | 13.8 | **≤ 7** | |
| UIStroke per control | 1.8 | **≤ 0.3** | |
| Per-property theme bindings | 3,253 + 1,256 font | **0** (one theme hook per component) | |
| Connections per mounted control | 4.5 | ≤ 3, none global | |
| Global input handlers at idle (400 controls) | 43 InputChanged / 21 InputBegan / 43 InputEnded | **0 / 1 / 0** per window | 0 Lua calls per mouse move at idle |
| RenderStepped at idle | 1, forever | **0** | |
| Infinite tweens at rest | 1 (also while hidden) | **0** | |
| Periodic sweeps | 12-36 ms every 30 s | **none** | |
| Lua size listeners (400 controls) | 220 + 50 | **≤ 1 per scrolling container** (about 12) | |
| First-wave relayout writes after a resize | 634 | ≤ 20 | no size tweens on containers with content |
| Theme switch (400 built) | 11-28 ms, 10-frame wipe | **≤ 4 ms, 1 frame**, visible components only | |
| Theme picker open | 17-57 ms (155-248 ms bloated) | **≤ 1 ms** after the first open | |
| Dropdown open, 200 options | 12-20 ms, 611 instances, 602 connections, 407 bindings, every time | **≤ 2 ms, ≤ 15 instances on the first open, 0 after** | |
| Dropdown filter keystroke | 0.08-0.19 ms | ≤ 0.5 ms (any option count, virtualised) | |
| Colour picker open | 0.5-1.4 ms, +2 permanent global handlers | ≤ 1 ms, 0 new handlers | |
| `List:SetItems(200)` | 27-77 ms, 1,600 instances | **≤ 5 ms**, instances capped near the viewport (≤ 20 rows) | |
| `List:AddItem` (200 rows) | 28-118 ms | **≤ 0.3 ms** | |
| Notification | 0.3-1.3 ms, 26 instances incl. a CanvasGroup | **≤ 0.2 ms, ≤ 12 instances, 0 CanvasGroups**, pooled | |
| Tooltip hover | 6 new instances per hover | 0 (singleton) | |
| Tab switch | 0.4-1 ms + chip rebuild | ≤ 1 ms when prewarmed; ≤ 8 ms with a mount | |
| Player join (50 players) | 302 instances, 50 thumbnail calls | **≤ 8 instances, 0 API calls**; 0 work while disabled | |
| Keybind press | full overlay rebuild (7 instances) | in-place update, 0 instances | |
| Re-execution (5x) | handlers x5, 5 prune loops | **identical to one execution** | |
| `LoadConfiguration`, 280 flags (library side) | 19-34 ms | ≤ 10 ms; one deferred overlay refresh | |
| CanvasGroups at rest | 1 window-sized + 1 per toast | **0** | |

---

## 8. Bench files and how to reproduce

Everything is in `bench/`:

| File | Measures |
|---|---|
| `perf_harness.luau` | Loads the real library through `../../argon-UI/tests/sandbox.luau`; instrumentation, a synthetic 147.7 KB Lucide index, and the executor stand-ins |
| `perf_workload.luau` | The 10 x 40 mixed-control workload (public v1 API only) |
| `perf_load.luau` | Source composition, compile, the base64 decode, and load in `plain`, `atlas-first` and `atlas-cached` modes |
| `perf_window.luau` | CreateWindow in `http`, `cache`, `nolucide` and `preparsed` modes; counts, timers, auto-open |
| `perf_build.luau` | The big build (`count` for instrumented counts; optional tab and per-tab arguments), theme, font, theme picker, search, tab switch, idle fan-out, prune, save and load, 50 notifications |
| `perf_kinds.luau` | Per-kind build time by tab (the `unbindTheme` signature) |
| `perf_scaling.luau` | Build time against pre-filled `_themeBindings` size |
| `perf_controls.luau` | Per-control cost table (`lucide`, `atlas` or `vector` icon modes) |
| `perf_popups.luau` | Dropdown(200), colour-picker leak, List 200, keybind press, tooltip, theme picker |
| `perf_resize.luau` | Relayout first-wave proxy |
| `perf_players.luau` | Player-overlay churn at 50 players |
| `perf_drag.luau` | Slider drag cost and autosave |
| `perf_reexec.luau` | Handler build-up across 5 executions |
| `perf_iconmap.luau` | The v2 embedded compact icon map (size, compile, lazy index) |
| `perf_run_all.sh` | Runs everything (each bench in its own `lune` process) into `perf_results-v1.txt` |

Run: `sh bench/perf_run_all.sh`. It takes about 1-2 minutes, needs Lune 0.8.9 on PATH, and never writes into the repo.
