# Argon UI v2.0: architecture

Lead-engineer design for the v2 rebuild of `argon-ui.luau` (v1.18.3, 3,369 lines).

**Inputs.**
- The audit reports in `argon-UI-v2-work/audit/`:
  - `perf.md` and `api.md`, read in full;
  - `shell.md`, `controlsA.md`, `controlsB.md` and `market.md`, read for features.
- The v1 source, `tests/run.luau` (294 pass) and `tests/sandbox.luau`.

**Two benches added for this document.** Both are in `argon-UI-v2-work/bench/`:
- `v2_icon_encoding.luau` encodes the **real** latte-soft `lib/Icons.luau` (147,702 bytes, downloaded 2026-10-31 and parsed with patterns, never executed).
- `v2_state_element_cost.luau` measures a state-only `Create*`.

**Line references.** `L123` refers to v1 `argon-ui.luau`. `run.L123` refers to `tests/run.luau`.

**How to use this document.**
- Sections 4-15 are the contracts. Each module's interface is specified so that the work units in section 17 can be built in parallel against it.
- Where a section says **MUST**, a reviewer rejects code that deviates.
- Where it says **default**, the value may be tuned without changing this document.

---

## 0. Summary

v2 keeps v1's public API (every name, alias, option key, callback payload and saved-value format in `api.md` §1-14) and replaces everything under it.

1. **Nothing slow runs on the load path.**
   - Loading the library creates no instances, does no IO and starts no timers.
   - `CreateWindow` reads the saved preferences synchronously, draws only the layer roots and a loader card at transparency 1 (≤ 34 instances), spawns the font preload, and returns within 3 ms.
   - There are no network calls and no yields on the caller's thread. Icons come from a 15.8 KB front-coded map of all 1,573 Lucide 48 px icons embedded at build time. Avatars are `rbxthumb://` URLs. The two CDN font faces are preloaded off-thread (§5.4).
2. **Elements are state first.**
   - `Create*` builds a plain state table: about 1 µs measured, against 470-1,600 µs in v1. It returns a fully working element: `Set`, flags, callbacks, `Lock`, change tracking and search all work with zero instances.
   - Instances are **mounted** later by a frame-budgeted scheduler: the active tab first, then hovered tabs, then the rest.
   - `element.Root` and every other instance field still work, because reading one forces a synchronous mount of that element.
3. **Ownership replaces the global registries.**
   - Each component owns a `Scope` (janitor) with its instances, connections, tweens and a flat theme paint list.
   - There is no `_themeBindings`, no colour-equality scanning and no `unbindTheme`. v1's quadratic build is gone by construction.
   - Global input is one `InputBegan` connection per library. Drag handlers connect on drag start and disconnect on drag end. Nothing runs at idle except the explicit exemptions in §9.7.
4. **One service per concern.** These are written once and shared by every control:
   - the theme engine (tokens, derived roles, contrast validation, generator, materials, light and high-contrast themes);
   - the motion system (DESIGN's motion tokens, three springs, reduced motion) and the three-slot glow pool;
   - the input router (key dispatch, close-key policy, drag, focus engine for keyboard and gamepad);
   - the layer manager (popovers, tooltip, dialogs, palette, toasts, z-order, dismiss stack, coordinates under the interface scale);
   - virtualised lists;
   - change tracking with reset and a single-level undo;
   - persistence (v1 files plus profiles, import/export and a single preferences store).
5. **The loader tells the truth.**
   - No fixed timers. The card appears only when real work (a mount, a restore, or a script that has not made a tab yet) is still pending 150 ms after `CreateWindow`, and once shown it stays 0.25 s, counted through the start of the hand-over.
   - Progress is counted from real work.
   - A ghost frame morphs into an already-built window in at most 300 ms.
   - Touch devices get a reopen orb, and PC users a dock pill on request, so a hidden window can always be reopened.
6. **Delivery.**
   - The source moves to `argon-UI/src/` (about 65 small modules).
   - A deterministic Lune `build.luau` bundles it into the same single `argon-ui.luau` (module wrapper functions plus a local `require` shim), so `loadstring(game:HttpGet(raw))()` keeps working.

The decisions that change observable behaviour are listed in §14.5. Questions for the owner are in §18.

---

## 1. Goals, scope and budgets

### 1.1 The owner's complaints and where each one is fixed

| Complaint | Root cause (measured in the audits) | Fixed by |
|---|---|---|
| "load times for a lot of features are awful" | Quadratic `unbindTheme` (`perf` §2.4). Eager build of 13.8 instances per control. Popups and lists rebuilt on every use (dropdown(200) is 611 instances per open; `AddItem` is O(n²)). | §4.8, §8, §9 (state first plus lazy mount), §7.3 and §7.5 (pooled and virtual), §8.8 (instance diet) |
| "the loading is not the best" | HttpGet plus loadstring of the Lucide index and `GetUserThumbnailAsync` inside `CreateWindow` before the loader exists. Fixed 0.38 s and 0.93 s timers. Pill-to-window resize with content inside. | §10.1-10.3, §5.5 |
| "the look needs to be more next-gen and more user friendly" | Flat palettes (Hover/Surface 1.06-1.20:1). White ink on accent at 1.29-3.43:1. Text at 8-11 px, ALL CAPS micro-labels. A card inside a card. Fake chrome (LIVE, ARGON ONLINE). | §5 (tokens and derivation), §8.8 (grouped rows), §10.4 (shell) |
| "components need to be next-gen and top-tier UX" | No focus or keyboard. No gamepad. Hover-only states. 8-26 px hit targets. Popups off-screen. No pressed, loading or error states. | §6, §7, §8.4-8.7, §11 |
| "add things that make sense" | Gaps against Rayfield, WindUI and Obsidian (`market` §4) | §11 and §12: command palette, dock pill, profiles, typed notifications, context menu, collapsible sections, VisibleWhen and EnabledWhen, Callout, Stat and Image blocks, theme generator, UI scale |

### 1.2 Scope of 2.0, and stretch items for 2.1

**2.0 (MUST):**
- everything in this document and in DESIGN_V2 unless marked *(2.1)*;
- a public API that is a source-compatible superset of v1;
- the Rayfield gaps from `api` §15 closed;
- the features DESIGN_V2 §0.3 promises the owner, each with an owner in §17:

| Feature | DESIGN | Module | Unit |
|---|---|---|---|
| Notification inbox and the topbar bell with its unread dot | §3.4, §7.6 | `feature/Toast` (inbox model and popover); the bell button in `shell/Shell` | WU10, WU6 |
| Pins: the Pinned sidebar group and the quick dock | §3.3, §3.7, §8.4 | `feature/Pins` (model, limits, `Prefs` per profile); views in `shell/Shell` and `shell/Dock` | WU6 |
| Watermark and its Settings row | §7.7, §9 | `feature/Overlays` | WU10 |
| Stat sparkline (`Spark`) | §6.18 | `display/TelemetryCard` | WU9 |
| Tab group captions: `CreateTab(name, icon, {Group, Description})` | §3.3, §8.8 | `container/Tab` (state); captions and breadcrumb in `shell/Shell` | WU5, WU6 |
| Change tracking, Reset tab/section, Undo pill, Ctrl+Z | §3.5, §8.3 | `component/Changes`; the pill in `feature/Toast` | WU5, WU10 |
| `ButtonGroup` | §6.7 | `controls/ButtonGroup` | WU7 |

**2.1 (designed for, not built):**
- localisation;
- "what's new" announcement;
- two-thumb range slider;
- keybind modifier combos;
- `CreateTabGroup` (collapsible group containers; 2.0 only draws captions from the `Group` option);
- Paragraph "show more";
- engine `StyleSheet` token mapping.

### 1.3 Budgets

Times are **Lune ms**, comparable with the v1 column measured in `perf.md`. Counts are exact and transfer 1:1 to a client.
- **CI time gates** fail at **1.5x** the budget, to absorb machine noise.
- **Count gates** are exact. The per-kind instance counts are listed part by part in §8.8; `tests/perf.luau` asserts each one, and the mixed figures below follow from them.
- The real-client goals are confirmed with MicroProfiler labels (§16.6).
- **This table and DESIGN_V2 §11 carry the same numbers.** A change to one is a change to both.

| Area | v1 measured | v2 budget (Lune gate) | Real-client goal |
|---|---|---|---|
| Bundle size | 296 KB | ≤ 180 KB target, **gate 200 KB** | |
| Compile (`luau.compile`) | 16-23 ms | ≤ 0.75x v1 on the same machine | |
| Work at require time | +11-25 ms decode, 2 file writes, prune loop | **0 instances, 0 IO, 0 timers, 0 connections**, ≤ 2 ms top level | |
| Network calls or yields on the caller's thread before the first loader frame | up to 2 | **0** (the sandbox trips on HttpGet, thumbnail calls and `task.wait`; the two font-preload threads are spawned, §5.4) | card can paint on the frame after `CreateWindow` |
| CDN font faces on the first frame | 2-5 | **0** (the loader uses engine-local faces only) | |
| `CreateWindow` | 4-43 ms, 184 instances | **≤ 3 ms, ≤ 34 instances** (5 layer instances + a ≤ 27-instance card; prefs read included) | |
| Shell when built | 184 instances | ≤ 120 instances for 10 tabs, built unparented | parented once |
| `Create*` (state only) | 470-1,600 µs | **median ≤ 10 µs; 500 calls ≤ 8 ms** (measured feasibility: about 1 µs) | |
| Library Lua work per frame | unbounded (whole build in one frame) | **≤ 8 ms while loading, ≤ 4 ms interactive**, minus `Create*` and restore time already spent that frame (§9.4) | no frame over about 8 ms of library work |
| Mount one 40-control tab | 12-110 ms, grows with the tab index | **≤ 8 ms total**, sliced | ready within 2 frames |
| Scaling | quadratic: tab 30 is 7-11x tab 1 | **linear**: tab N within 1.2x of tab 1; 1,200 `Create*` ≤ 15 ms | |
| Instances per control, by kind | 7-12 (see DESIGN §6.21) | **exact per-kind counts, §8.8** | |
| Instances per control, mixed workload (`perf_workload` 10 x 40, all tabs mounted) | 13.8 (structure included) | **≤ 11.2 including structure** (computed 11.1 = 352 control + 93 structure instances per tab); **≤ 8.8 controls only** | |
| UIStroke per control (same workload) | 1.8 | **≤ 0.6** (computed 0.4: wells, caps, segmented indicators and one lit edge per section) | |
| Live glows per window | n/a | **≤ 3** (core/Glow slots) | |
| Global theme or font bindings | 3,253 + 1,256 | **0** (per-component paint lists) | |
| Connections per mounted control | 4.5 | ≤ 3, **0 global** | |
| Global handlers at idle (UIS InputChanged / InputBegan / InputEnded) | 43 / 21 / 43 | **0 / 1 / 0 per library** | 0 Lua calls per mouse move |
| RenderStepped or Heartbeat at idle | 1, forever | **0**, except the watermark's frame counter while it is enabled and visible (§9.7) | |
| Infinite tweens at rest, or any tween while hidden | 1 | **0** | |
| Timers at idle | 30 s prune | **0**, except the autosave debounce while dirty, visible toasts and the Undo pill, and the watermark's 0.5 s refresh while it is enabled and visible (§9.7) | |
| Periodic sweeps | 12-36 ms every 30 s | **none** | |
| Lua size or position listeners (400 controls) | 270 | ≤ 1 per page scroller (width and scroll-spy), ≤ 1 per virtualised scroller, plus 1 for the GUI size | |
| Relayout writes per resize frame (first wave) | 634 | **≤ 20**; a stacked-row flip (DESIGN §3.6) writes once per mounted wide row of the visible tab, only on the frame the row width crosses 420 px | |
| Theme switch, 400 built | 11-28 ms, 10-frame wipe | **≤ 4 ms in one frame**, on-screen components only (a loading window counts as on-screen) | |
| Theme preview on hover (DESIGN §7.8) | n/a | ≤ 1 repaint per frame, window-local, no `Theme.changed` | |
| Theme picker (Appearance) open | 17-57 ms | ≤ 1 ms after the first open; first open ≤ 130 instances | |
| Dropdown open, any option count | 12-20 ms, 611 instances per open (200 options) | **≤ 2 ms; ≤ 60 instances on the first dropdown open in the window, 0 after** | |
| Dropdown filter keystroke, 10k options | 0.08-0.19 ms at 200 | ≤ 0.5 ms | |
| Colour picker open | 0.5-1.4 ms, +2 leaked handlers | ≤ 1 ms, 0 new handlers | |
| `List:SetItems(200)` | 27-77 ms, 1,600 instances | **≤ 5 ms, ≤ 20 live rows** | |
| `List:AddItem` (200 rows) | 28-118 ms | **≤ 0.3 ms** | |
| Notification | 0.3-1.3 ms, 26 instances, 1 CanvasGroup | **≤ 0.2 ms pooled, ≤ 16 instances per card (actions on demand), 0 CanvasGroups** | |
| Tooltip hover | 6 new instances | 0 (singleton) | |
| Tab switch | 0.4-1 ms plus chip rebuild | ≤ 1 ms when prewarmed; ≤ 8 ms sliced when cold | the parenting frame is checked in §16.6 |
| Player join, 50 players | 302 instances, 50 thumbnail calls | ≤ 8 instances, 0 API calls; 0 work while the overlay is disabled | |
| Keybind press | overlay rebuild, 7 instances | 0 instances | |
| Script re-executed 5 times | handlers x5, 5 prune loops | identical to one execution | |
| `LoadConfiguration`, 280 flags (library side) | 19-34 ms | ≤ 10 ms, sliced at 8 ms, one deferred overlay refresh | |
| Loader: ready → interactive | fixed 0.93 s timer | **≤ 0.3 s** (fast path 0.24 s; hand-over ≤ 0.3 s) | |
| Loader: 500 controls + `LoadConfiguration` of 240 flags, synchronous host | 0.93 s fixed, then a half-built window | **revealed and interactive ≤ 0.6 s** | |
| CanvasGroups at rest | 1 window-sized plus 1 per toast | **0** | |

---

## 2. Repository layout and module tree

Distribution stays **one file**: `argon-UI/argon-ui.luau`, generated and committed. Nobody hand-edits it.

```
argon-UI/
  argon-ui.luau            GENERATED bundle (raw URL unchanged)            [build output]
  build.luau               bundler: lint, strip, wrap, emit, --check       WU1
  tools/
    devload.luau           loads src/ under Lune without bundling (unit tests)   WU1
    gen_icons.luau         Lucide -> src/icons/IconData.luau generator      WU2
    palette.json           palette seeds + computed values (copied from argon-UI-v2-work/bench/v2_final_palette.json)   WU2
    gen_palette.py         palette generator + validator (from bench/v2_final_palette.py); writes palette.json and src/theme/PaletteData.luau   WU2
    gen_assets.py          shadow/glow/checker PNG generator (exact geometry, §5.6) + upload record   WU2
    assets/                generated PNGs and assets.lock.json (ids, sha256, owner, moderation state)   WU2
  src/
    init.luau              the Argon facade (public library table)          WU11
    meta.luau              { Version = "2.0.0", Build = ... }               WU11
    core/
      Env.luau             executor/Studio detection, services, fs probes, clipboard, gui parent, clock, safe enums   WU1
      Signal.luau          tiny signal (Connect/Once/Fire/DisconnectAll), connection objects                WU1
      Scope.luau           janitor: instances, connections, tweens, timers, child scopes, paint list        WU1
      Util.luau            copy, clamp, round-to-step, keyName, utf8 helpers, xcall + error hook            WU1
      Token.luau           token sentinels (colour, font role, text role), paint records                    WU1
      Factory.luau         Instance factory with token props; parent-last; diagnostics counters             WU1
      Scheduler.luau       frame-budgeted job queue, priorities, flush, frame-shared budget                 WU1
      Motion.luau          DESIGN motion tokens, tween helper, three springs, loops, reduced motion          WU1
      Glow.luau            three-slot glow pool per window (focus, nav, moment)                              WU1
    component/
      Component.luau       base class: lifecycle, view-field proxy, mount/theme/destroy                      WU1
      Element.luau         control base: common API, visibility, commit path, lock/disabled, tooltip, desc, menu, error   WU5
      RowView.luau         row anatomy (root/title/title row/description/markers/control column), hover pooling        WU5
      Changes.luau         change tracking: changed set, tab/section counters, reset, single-level undo batch           WU5
    container/
      Tab.luau             tab state (Group, Description), page skeleton, mount job, quick filter, section metadata     WU5
      Section.luau         section state, header, platter, dividers, collapse, reset, builders               WU5
      Row.luau             multi-column row (flex wrap), Use(i), legacy _balance/_relayout                   WU5
      Registry.luau        per-window element registry, search index, VisibleWhen/EnabledWhen               WU5
    theme/
      Color.luau           sRGB/OKLab conversion, mix, lighten, contrast ratio                               WU2
      PaletteData.luau     GENERATED by tools/gen_palette.py (the 12 built-in palettes)                      WU2
      Palettes.luau        built-in palettes from PaletteData + v1 aliases + Rayfield names                  WU2
      Theme.luau           live palette, derive/validate/create, materials, switch protocol, preview, listeners   WU2
      Fonts.luau           font sets, roles, faces, preload and swap, font version                          WU2
      Metrics.luau         spacing, radii, type scale, densities, window size, interface scale              WU2
      Assets.luau          GENERATED asset ids (shadow-hollow, glow-hollow, glow-blob, checker) + fallbacks  WU2
    icons/
      Icons.luau           resolver: names, aliases, asset ids, lazy decode, apply()                         WU2
      IconData.luau        GENERATED by tools/gen_icons.luau                                                  WU2
    input/
      Platform.luau        PreferredInput, density, touch/gamepad detection, signal                          WU3
      Router.luau          the single InputBegan; key map, lookup and conflicts; toggle keys; close-key and shortcut sinks; hold tracking   WU3
      Drag.luau            drag sessions (InputObject-tracked, per-frame coalesced)                           WU3
      Focus.luau           focus engine: roving focus, ring, CAS sink, gamepad map, hint content (Focus.hints)   WU3
    layers/
      Layers.luau          ScreenGui layer frames, z-order, scale-aware coordinates, dismiss stack, outside-click catcher   WU3
      Popover.luau         anchored popover host (one per window, pooled) and phone bottom sheets            WU3
      Tooltip.luau         singleton tooltip per window                                                       WU3
      VirtualList.luau     recycled-row virtual list                                                          WU3
      ContextMenu.luau     menu built on Popover + VirtualList                                                WU3
    persist/
      FS.luau              fs wrappers (read/write/exists/folders/list/delete), path joins                  WU4
      Codec.luau           value encode/normalise per type, colour interop, base64, export envelope          WU4
      Store.luau           flag registry, pending flags, commit bus, autosave, save/load, stats             WU4
      Prefs.luau           single UI-preferences store (global + per-profile keys), meta file, legacy folding   WU4
      Profiles.luau        named profiles, autoload, rename/duplicate/delete, import/export, counts         WU4
    shell/
      Window.luau          window object, public window API, feature hooks, lifecycle                        WU6
      Shell.luau           sidebar (groups, Pinned), topbar (bell), sheet, page host, TOC + chip row (JumpRail), hint bar, breakpoints   WU6
      Loader.luau          loader card, readiness rules, progress model, ghost hand-off                      WU6
      Dock.luau            dock pill, reopen orb, quick dock (pins view)                                     WU6
      Cursor.luau          drawn cursor layer (only while needed)                                             WU6
    feature/
      Pins.luau            pin model: pin/unpin, limits, per-profile persistence, data for the two views     WU6
      Toast.luau           notifications (pooled), phone pills, inbox, Undo pill, callback-error toasts, copy sheet   WU10
      Dialog.luau          Dialog/Popup/Confirm/Prompt                                                        WU10
      Palette.luau         command palette and global search                                                 WU10
      Overlays.luau        player list, keybind list and watermark overlays                                  WU10
      Settings.luau        settings content: built-in settings sheet, CreateLibrarySettings, CreateConfigManager   WU10
      ThemePicker.luau     Appearance popover (topbar ThemeButton), live preview                             WU10
      KeyGate.luau         KeySystem / KeySettings access gate                                               WU10
    controls/              Button ButtonGroup Toggle Slider Stepper Segmented Keybind                        WU7
                           Input TextArea Dropdown ColorPicker                                               WU8
    display/               Label Paragraph TelemetryCard(+Stat, Spark) Divider Space ProgressBar List Callout Image   WU9
    compat/
      Options.luau         CreateWindow option normalisation (Rayfield + v1 aliases)                         WU11
      Rayfield.luau        keybind/label/paragraph/theme-name/icon-id compatibility rules                    WU11
      Aliases.luau         alias tables: builders, window, element                                           WU11
  tests/                   sandbox + suites (section 16)                                                     WU12
  docs/src/                copy of argon-UI-v2-work/mockups/final-src (the v2 preview's source)              WU12
  README.md  CHANGELOG.md  docs/  argon-ui-preview.html                                                      WU12
```

**Logical module names** are paths without the extension, used verbatim in `require`: for example `require("core/Signal")` or `require("controls/Toggle")`.

**Singletons.** Modules hold per-load state at module level: `Scheduler`, `Router`, `Theme`, `Store`, `Motion`, `Icons` and `Platform`. One `loadstring` is one library instance, so module-level state is per library instance by construction. Windows are instances, and the per-window services (`Glow`, `Changes`, `Pins`, the layer set, the popover host, the tooltip) hang off the window.

---

## 3. Conventions (all units)

1. **Module format.**
   - Each file is a plain Luau module that ends in `return <value>`.
   - Dependencies are taken only through `local X = require("<logical name>")` with a **string literal**. The bundler rejects anything else.
   - Top-level code MUST NOT:
     - create instances;
     - connect signals;
     - read files;
     - call `task.*`;
     - touch services except through `core/Env`'s lazy getters.
   - Top-level varargs (`...`) are forbidden, because they would see the wrapper's arguments.
2. **No yields and no network on the critical path.** Load, `CreateWindow`, `CreateTab`, `Create*` and the setters MUST NOT call, on the caller's thread:
   - `task.wait`, `wait`;
   - `:Wait()`, `WaitForChild`;
   - `HttpGet`, `GetUserThumbnailAsync`, `GetTextBoundsAsync`, `PreloadAsync`, `loadstring`;
   - any `*Async` method.

   `build.luau` enforces this with an allowlist (§15.4). The only allowed yield sites are:
   - `persist/Store` restore slicing (only when `coroutine.isyieldable()`);
   - `theme/Fonts` font preload: `TextService:GetTextBoundsAsync`, **only inside a `task.spawn`ed function** (two threads per library load, §5.4);
   - `feature/KeyGate` (opt-in blocking gate, §12.7);
   - `feature/KeyGate`'s `GrabKeyFromSite` fetch, which runs in its own spawned thread.
3. **Executor globals are optional.** They are read only through `core/Env`, each one `pcall`-guarded and cached:
   - `getgenv`, `gethui`, `syn.protect_gui`, `protectgui`;
   - `readfile`, `writefile`, `isfile`, `isfolder`, `makefolder`, `delfile`, `listfiles`, plus the `syn.*` aliases;
   - `setclipboard` / `toclipboard`, `getclipboard`;
   - `getcustomasset`.

   Nothing may error when any of them is missing (plain Studio or PlayerGui). A copy action with no `setclipboard` opens the copy sheet (§12.1) instead of failing silently.
4. **Instances.**
   - Created only through `core/Factory`.
   - `Parent` is set last, and only the root of a subtree is parented into a live tree.
   - Key parts have stable `Name`s that tests use: `Control`, `Title`, `Description`, `TipMarker`, `Track`, `Knob`, `Hit`, `Fill`, `Thumb`, `Value`, `Field`, `Swatch`, `Pill`, `Body`, `Header`, `PageGroup`, `Page`, `JumpRail`, `Indicator`, and so on.
   - `ClipsDescendants` only where content can overflow: pages, popover bodies, virtual lists, collapsing platters, the labelled divider.
   - No CanvasGroup anywhere. No subtree transparency animation: fades use one veil Frame or at most 8 pre-collected objects (DESIGN §2.11).
   - **Input never falls through.** `Main`, every floating panel (popover, menu, toast card, Undo pill, dialog, palette, key gate, loader card), every bottom sheet, the dock pill, the reopen orb and the quick-dock chips have `Active = true`, so a click on glass, padding or a header never reaches the 3D world (tools, ClickDetectors). The tooltip keeps `Active = false`.
   - **Coordinates under the interface scale** follow §7.1: every placement routine converts through `layers:toLocal` and `layers:localSize`.
5. **Text.**
   - Whole-pixel `TextSize` from `theme/Metrics`. Nothing below 12 px.
   - Font only through font-role tokens (§5.1, §5.4).
   - Sentence case. No ALL CAPS anywhere (DESIGN §2.9).
6. **Colours** come only through tokens (§4.5). A literal `Color3` is allowed only for host-supplied colours, and is then never repainted by a theme switch unless the component re-renders it from state. Disabled and locked looks are token re-renders inside `_render`, never transparency writes (§8.7).
7. **Callbacks.**
   - Host callbacks run through `Util.xcall(fn, ctx, ...)`, which is `xpcall` with `debug.traceback`.
   - On error, `warn("[Argon UI] <Type> \"<Name>\" (flag <Flag>) callback error: <msg>")` is emitted once per distinct message per element (rate-limited), the element enters the `error` state (§8.4), and `Util`'s error hook raises the callback-error toast (§12.1).
8. **Setters** return `self` (D14). Getters never mount.
9. **No library branding in the host UI.** No "ARGON ONLINE", no "ARGON / TAB", no "LIVE" pill unless the host sets one through `Window:SetStatus`. User-facing text names the window (`Name`), never "Argon": for example the first-hide toast reads "Nebula Hub is hidden". Only Settings → About names the library and its version.
10. **Profiling labels.** `debug.profilebegin("Argon/<phase>")` / `debug.profileend()` are wrapped in a cached capability check (`Env.profile`) around mount slices, theme switches, restores, popover opens, tab-switch parenting and the font swap.
11. **Style.**
    - Tabs for indentation.
    - `--!nocheck` is allowed.
    - Comments are free (they are stripped from the bundle).
    - Every public function has a one-line doc comment.
12. **Precedence.** Visual, motion, metric and UX values come from DESIGN_V2 and are not restated as alternatives anywhere in the code. A module that needs a value DESIGN does not give asks for it to be added there first.

---

## 4. Core primitives (WU1)

### 4.1 `core/Env`

```lua
Env.services : {             -- lazy getters (resolved on first access, cached)
  Players, TweenService, UserInputService, RunService, HttpService, CoreGui,
  GuiService, ContextActionService, TextService, ContentProvider }
Env.localPlayer() -> Player?
Env.genv() -> table                          -- getgenv() or shared or _G (first that works)
Env.has(name: string) -> boolean             -- executor function present (incl. syn.* alias)
Env.fn(name: string) -> function?            -- e.g. Env.fn("readfile"); nil when missing
Env.guiParent() -> Instance                  -- gethui() -> CoreGui (if parenting allowed) -> PlayerGui
Env.protectGui(gui: ScreenGui) -> ()         -- syn.protect_gui / protectgui, pcall'd
Env.setClipboard(text: string) -> boolean
Env.clock() -> number                        -- os.clock (overridable by tests via Env._clock)
Env.enum(enumName: string, item: string, fallback: string?) -> EnumItem?   -- pcall'd; never errors
Env.isStudio : boolean                       -- RunService:IsStudio(), pcall'd
Env.profile : boolean                        -- debug.profilebegin usable
Env.trySetParent(inst, parent) -> boolean    -- pcall(Parent=) for CoreGui permission probing
```

- `guiParent` rule: `gethui()` when present. Otherwise **attempt** `CoreGui` when the actual ScreenGui is parented (through `trySetParent`, so no probe instance is needed), and fall back to `LocalPlayer:FindFirstChildOfClass("PlayerGui")`.
- The cursor ScreenGui and any extra ScreenGui use the same parent as the window's.

### 4.2 `core/Signal`

```lua
Signal.new() -> Signal
signal:Connect(fn) -> Connection          -- Connection { Connected: boolean, Disconnect: () -> () }
signal:Once(fn) -> Connection
signal:Fire(...) -> ()                     -- handlers run in order; errors are caught and warned with the signal's label
signal:DisconnectAll() -> ()
signal:Count() -> number                   -- diagnostics
```

- `Fire` iterates a snapshot. Handlers added during `Fire` do not run until the next `Fire`.
- No threads are spawned, so this is cheaper than BindableEvent and needs no yield.

### 4.3 `core/Scope` (janitor)

```lua
Scope.new(label: string?, parent: Scope?) -> Scope   -- parent:destroy() destroys children first
scope:add(item: Instance | Connection | Scope | Tween | () -> ()) -> item
scope:connect(signal: RBXScriptSignal | Signal, fn) -> Connection
scope:instance(inst: Instance) -> Instance           -- add + returns inst (Factory calls this)
scope:delay(seconds, fn) -> handle                   -- task.delay, cancelled on destroy; handle:cancel()
scope:tween(inst, tokenName, props) -> Tween?        -- Motion.tween, tracked, cancelled on destroy
scope:child(label?) -> Scope
scope:paint(inst, prop, token)                       -- append to scope.paints (flat array of triples)
scope:repaint()                                      -- re-apply scope.paints from Theme/Fonts (recursive into children)
scope:clear()                                        -- destroy contents, keep scope usable
scope:destroy()                                      -- idempotent; sets scope.dead = true
scope.paints : {any}                                 -- {inst1, "BackgroundColor3", tokenA, inst2, ...}
scope.dead : boolean
```

- `destroy` order:
  1. child scopes, in reverse;
  2. connections (Disconnect);
  3. tweens (Cancel);
  4. timers (cancel);
  5. functions;
  6. instances (Destroy, root-most first; descendants go with them).
- Cost is O(size of the scope). There is no global list anywhere.
- `Scope.liveCount` (module-level integer) is the only global, and it exists for diagnostics.

### 4.4 `core/Util`

```lua
Util.copy(v) -> v                       -- deep copy, tables only
Util.shallow(t) -> t
Util.clamp(x, a, b) -> number           -- swaps a/b when a > b
Util.roundToStep(x, min, step) -> number  -- v1 rule: floor((x-min)/step+.5)*step+min, then rounded to step's decimals
Util.decimals(step) -> number
Util.keyName(v) -> string               -- EnumItem -> Name; "Enum.KeyCode.X" -> "X"; ""/"Unknown" -> "None"
Util.keyCode(v) -> Enum.KeyCode?        -- accepts EnumItem, "K", "RightShift", "Enum.KeyCode.K"; nil if unknown
Util.trim(s), Util.truncate(s, n), Util.utf8len(s), Util.utf8sub(s, i, j)
Util.xcall(fn, ctx: string, ...) -> (ok, ...)   -- xpcall + traceback; warn with ctx on failure
Util.warnOnce(key, msg)
Util.jsonEqual(a, b) -> boolean         -- structural compare (replaces 2x JSONEncode, L2487)
```

### 4.5 `core/Token` and `core/Factory`: the instance factory with token props

**Tokens are sentinels, not values.** `Token.T.Surface` is a unique frozen table `{kind="color", name="Surface"}`. The same applies to:
- fonts: `Token.F.Body`, `Token.F.BodyMedium`, `Token.F.BodySemibold`, `Token.F.Display`, `Token.F.Mono`;
- text sizes: `Token.TS.Body`, and so on.

```lua
Token.T : {[ColorTokenName]: Sentinel}       -- full list in section 5.1
Token.F : {[FontRole]: Sentinel}
Token.TS : {[TextRole]: Sentinel}
Token.isToken(v) -> boolean
Token.resolve(sentinel) -> Color3 | Font | number   -- delegates to registered resolvers
Token.setResolvers({ color = (name)->Color3, font = (role)->Font, size = (role)->number })  -- set by theme/Theme at init
Token.version() -> number                   -- bumps on theme, font or density change
```

```lua
Factory.new(scope: Scope, className: string, props: {[string]: any}?, parent: Instance?) -> Instance
Factory.text(scope, className, props, parent) -> Instance   -- same, plus text defaults (font Body, size Body, BackgroundTransparency 1, TextXAlignment Left)
Factory.corner(scope, parent, radius: number | "full") -> UICorner
Factory.stroke(scope, parent, token, transparency?, thickness?) -> UIStroke
Factory.padding(scope, parent, l, r?, t?, b?) -> UIPadding
Factory.list(scope, parent, props) -> UIListLayout
Factory.stats() -> { created: number, byClass: {[string]: number}, propWrites: number }   -- debug builds only (flag)
```

Rules (MUST):
- For each prop: if `Token.isToken(value)`, write `Token.resolve(value)` and call `scope:paint(inst, prop, value)`. Otherwise write the value as-is. **No colour-equality inference anywhere.**
- `FontFace` accepts a font sentinel. `TextSize` accepts a size sentinel. Both are recorded in the paint list, so font and density switches reuse the same repaint pass.
- `Parent` is applied last, from the `parent` argument (or `props.Parent`).
- `scope:instance(inst)` is called for every created root. Children are destroyed with their root, so only roots need tracking: Factory tracks an instance only when its parent is nil or is not owned by the same scope.
- Factory never connects signals.

### 4.6 `core/Scheduler`: frame-budgeted mounting

```lua
type Job = {
  key: any?,                 -- dedupe key (e.g. tab); enqueue with an existing key re-prioritises
  priority: number,          -- 0 shell, 1 active tab, 2 prefetch (hovered tab), 3 background tabs, 4 idle
  run: (deadline: number) -> boolean,   -- do work until Env.clock() >= deadline; return true when finished
  label: string?,            -- profiler / stats label
}
Scheduler.enqueue(job: Job) -> Job
Scheduler.bump(key, priority) -> ()          -- e.g. hover prefetch
Scheduler.cancel(key) -> ()
Scheduler.flush(key?) -> ()                  -- run matching jobs (or all) to completion now, ignoring budget
Scheduler.setMode(mode: "loading" | "interactive" | "paused") -> ()
Scheduler.noteForeground(seconds: number) -> ()   -- called by Create*/setters: library work spent outside slices this frame
Scheduler.idle() -> boolean                  -- queue empty
Scheduler.drained : Signal                   -- fires when the queue becomes empty
Scheduler.stats() -> { pending: number, lastSliceMs: number, maxSliceMs: number, slices: number, mode: string }
```

- **Heartbeat connection only while the queue is non-empty.** It connects on the first enqueue and disconnects when the queue drains. This gives zero idle work.
- **Per-frame budget:**
  - `loading` = 8 ms, `interactive` = 4 ms, `paused` = 0 (only priority 0-1 run, with a 4 ms budget, while the window is hidden and a tab is being forced);
  - minus `foreground` time noted since the last Heartbeat;
  - with a floor of 1 ms, so progress never stops.
- **Order:** highest priority first, FIFO within a priority. A job yields back to the queue when it returns false; `run` checks the deadline between units of work, where a unit is one element mount (about 0.05-0.3 ms).
- **Fallback:** if `RunService.Heartbeat` is unavailable, `task.defer` chaining is used (one slice per resumption).
- Re-entrancy: `flush` called from inside a running job runs inline. A job MUST tolerate `run` after its own state was partially forced by a sync mount (idempotent unit checks).

### 4.7 `core/Motion`

Tokens: these are the only durations, easings and springs in the codebase. **Values are DESIGN_V2 §2.11** and are copied here only so the module contract is complete; DESIGN wins on any difference.

| Token | Spec | Used for | Reduced motion |
|---|---|---|---|
| `hover` | 0.10 Quad Out | hover fills, icon tints | 0.10 fade |
| `press` | 0.06; UIScale 0.97 on buttons, keycaps and chips only (never rows) | press feedback | colour only, no scale |
| `state` | 0.14 Quart Out | colours: track, check, label, stroke | 0.10 |
| `spring.snappy` | ζ 0.75, ω 24 rad/s (≈ 3 % overshoot, settles ≈ 0.25 s) | switch knob and its fill wipe, segmented indicator, nav indicator, focus ring, slider snap, chip row | snap |
| `spring.gentle` | ζ 0.85, ω 18 rad/s (≈ 1 % overshoot, ≈ 0.38 s) | window open, dialog, loader card, ghost morph, toast enter, bottom sheet | snap |
| `spring.dock` | ζ 0.62, ω 18 rad/s (≈ 8 %) | dock pill and reopen orb edge snap **only** | snap |
| `knob.stretch` | knob width 18 → 24 px while pressed, springs back on release | switch | off |
| `pop.in` / `pop.out` | 0.16 Quint Out, UIScale 0.96 → 1 from the anchor side / 0.10 Quad In | popover, menu, picker | 0.10 fade of the content veil only |
| `veil` | 0.14 Quad Out | content veil on pop-in (starts at 40 ms), tab switch, hand-over | 0.10 |
| `rise` | 0.18 Quint Out, 6 px; 30 ms stagger | tab content, hand-over | 0 px |
| `dialog` | 0.22 in (`spring.gentle`) / 0.14 Quad In out; scrim 0.18 | dialog, palette, key gate | 0.10 fade |
| `toast` | in: `spring.gentle` from 16 px + 0.12 veil; out: 0.14 fade of ≤ 8 pre-collected objects, then a 0.18 height collapse | toasts, Undo pill | 0.10 fade |
| `tooltip` | 0.12 fade; delay 0.40 (mouse), 0.60 (focus), 0 when moving between tips within 0.30 | tooltip | 0.10 |
| `ghost` | 0.26 `spring.gentle`, Size and Position only | loader hand-over, dock ↔ window morph | 0 (veil only) |
| `progress` | 0.18 Quad Out | bars | 0 |
| loops | spinner 0.8 s/turn Linear; orb ring 0.9 s/turn; orb bloom 1.6 s Sine (T 0.70 ↔ 0.85); skeleton 1.2 s (UIGradient Offset); keybind capture drain 5 s Linear; indeterminate bar 1.1 s InOutSine | owners only while visible and pending | stopped (static) |

```lua
Motion.tween(inst, token: string, props, opts: {delay: number?, direction: string?, animated: boolean?}?) -> Tween?
   -- duration 0 (reduced motion, animated == false) => sets props directly and returns nil
Motion.spring(inst, prop: string, target: number | UDim2 | Vector2, token: "spring.snappy"|"spring.gentle"|"spring.dock") -> handle
   -- one shared Heartbeat drives all springs; connected only while any spring is moving
   -- several props may follow one spring: handle:follow(inst2, prop2, map: (x) -> any) (switch knob + gradient Offset)
Motion.loop(inst, token, props) -> handle     -- loops above only; handle:stop(); MUST be stopped by the owner's scope
Motion.setReduced(on: boolean) -> ()           -- from Prefs.ReducedMotion (SetSmoothTransitions(false) == reduced, §10.6)
Motion.reduced : boolean
Motion.duration(token) -> number
Motion.active() -> number                      -- running springs + loops (diagnostics; 0 at rest)
```

Rules:
- Every tween starts from the current value (Roblox cancels a running tween on the same property).
- `Back` and `Elastic` are not used; overshoot comes only from the springs.
- Easing enums are resolved once through `Env.enum`, falling back to `Quad`.
- `ColorSequence` and `NumberSequence` are never tweened. Colour transitions on gradient-filled parts tween a tweenable proxy instead: `UIGradient.Offset` (the switch fill wipe), the part's `BackgroundColor3` multiplying a white-keyed gradient (the pressed primary button), or they snap (ProgressBar thresholds). See §11.
- Loops are allowed only for the loops in the table. They are owned by a scope and stopped when their owner hides (`component:_onHidden`).
- **Visibility gate.** `Motion.tween` takes an `animated` decision from the caller. Components pass `animated = self:_onScreen()` (window visible or loading, tab active and element mounted). Off-screen state changes set props directly.

### 4.8 `component/Component`: base class and lifecycle

Every Element, Section, Tab, Row and feature component derives from this.

```lua
Component.extend(spec: {
  ClassName: string,                  -- e.g. "Toggle"
  viewFields: {string}?,              -- instance-valued fields served by mounting (see 8.2)
  methods: {[string]: function}?,     -- public + private methods (shared per class, not per object)
}) -> Class

Class.new(fields: table) -> object    -- setmetatable(fields, Class._meta); no instances
object:_mount(ctx: MountCtx) -> ()    -- idempotent; creates self._scope, calls Class.build(self, ctx), parents root last
object:_ensureMounted() -> ()         -- sync mount incl. ancestors (via ctx resolver supplied by owner)
object:_render(animated: boolean) -> ()  -- state -> view; no-op when unmounted
object:_applyTheme() -> ()            -- self._scope:repaint(); self:_render(false); stamps self._themeVersion
object:_onShown() -> ()               -- theme/font version catch-up; resume owned loops
object:_onHidden() -> ()              -- stop owned loops and pending tweens
object:_destroy() -> ()               -- unregister, scope:destroy(), detach from owner lists; idempotent
object._mounted : boolean
object._scope : Scope?                -- created at mount
object._themeVersion : number
```

```lua
type MountCtx = {
  window: Window,
  parent: Instance,          -- where the root goes (section body / row column holder / layer)
  layoutOrder: number,       -- creation order within the parent
  density: "mouse" | "touch" | "gamepad",
  animated: false,           -- mounting never animates
}
```

The lifecycle is the same for everything:
1. **create state** (`Class.new`, about 1 µs);
2. **mount view** (scheduler or forced);
3. **update** (`_render` after state changes);
4. **theme** (`_applyTheme` on version change);
5. **destroy**.

### 4.9 `core/Glow`: the three-slot glow pool

DESIGN §2.6 caps live glows at 3 per window. Focus (WU3), the shell's nav indicator (WU6) and the controls (WU7-WU8) all use them, so one core module owns them.

```lua
Glow.attach(window) -> GlowPool             -- per window; creates nothing until the first acquire
type GlowOpts = {
  shape: "hollow" | "blob",                 -- hollow: glow-hollow 9-slice, child of the target, drawn around it
                                            -- blob: glow-blob stretched, sibling under the target (ZIndex - 1)
  radius: number?,                          -- target corner radius (hollow), for the SliceScale rule below
  transparency: number?,                    -- default 0.55 (DESIGN §2.6); the loader bloom uses 0.70
  duration: number?,                        -- moment flashes: auto-release after n seconds (0.45)
}
pool:acquire(slot: 1 | 2 | 3, owner: any, target: GuiObject, opts: GlowOpts) -> handle
   -- slot 1 Focus (ring, dragged thumb), 2 Nav (selected indicator, the only persistent glow), 3 Moment (flashes)
   -- a new owner takes the slot over: the previous owner's handle goes dead (handle.alive == false)
pool:release(slot, owner) -> ()             -- no-op when owner no longer holds the slot
pool:sync(slot) -> ()                       -- blob only: re-copy the target's Position/Size after the owner moved it
pool:retint() -> ()                         -- Accent changed: 3 ImageColor3 writes at most
pool:live() -> number                       -- 0-3 (diagnostics, GetPerfStats)
```

- One `ImageLabel` per slot, created on its first `acquire` and then reused. It is hidden (`Visible = false`) on release and when its target's window hides, never destroyed until the window is.
- **Hollow** (`Assets.glowHollow`, §5.6): parented **inside** the target with ZIndex below the target's other children, so its transparent hole sits exactly over the target and only the halo outside it shows. `SliceScale = s = clamp(min(w, h) / 80, 0.15, 1)`, `Position = (0, -40s, 0, -40s)`, `Size = (1, 80s, 1, 80s)`. Used for rectangular targets of at least 6 px: the focus ring, the primary button, keycaps, switch tracks and wells.
- **Blob** (`Assets.glowBlob`): parented next to the target in its parent with `ZIndex = target.ZIndex - 1`, sized `target + 2 × max(8, 0.5 × min(w, h))`, centred on the target. Used for small or round opaque targets where a 9-slice would collide: the 3 × 16 nav bar (inside the Indicator, under the bar) and the slider and colour thumbs.
- Reduced motion skips moment flashes (slot 3) entirely. HighContrast never glows (`acquire` returns a dead handle).
- No glow runs a loop. The loader orb's bloom uses the same blob image, but as one of the card's own parts (§10.2), outside the pool; its breathing is a `Motion.loop` owned by the card.

---
## 5. Theme, type and icons (WU2)

### 5.1 Token names

The names, roles and values are DESIGN_V2 §2.1 (colours), §2.9 (type) and §2.8 (sizes). This section fixes the identifiers.

**Colour tokens.**

| Group | Tokens (v1 alias in brackets) |
|---|---|
| Surfaces | `Frame` (`Background`, `Sidebar`), `Sheet` (`Window`), `Surface`, `Hover`, `Active`, `Raised`, `Well` (`Input`), `Track` |
| Lines | `Border`, `BorderSoft` |
| Text | `Text`, `Text2`, `Muted`, `Dim`, `Disabled` |
| Accent | `Accent`, `AccentHi` (`AccentLight`), `AccentDeep` (`AccentDark`), `AccentAlt`, `AccentText`, `OnAccent`, `AccentSoft`, `Focus` |
| Status | `Success`, `Warning`, `Danger`, `Info`, `SuccessSoft`, `WarningSoft`, `DangerSoft`, `InfoSoft`, `OnStatus` |
| Effects | `Scrim`, `Shadow` |

- **v1 aliases stay readable and writable.** Every palette table also carries the six v1 keys (`Background`, `Sidebar`, `Window`, `Input`, `AccentLight`, `AccentDark`) with the value of the token they alias, so `Argon.Themes.X.Window`, `GetColor("Input")` and `GetPalette().Background` keep working. `Theme.add`/`AddTheme` and `SetTheme(table)` map v1 keys onto the v2 tokens before deriving (DESIGN §2.5: `Frame` = `Background`, else `Sidebar`, else `Window` darkened).
- `OnSuccess`, `OnWarning` and `OnDanger` from the first draft do not exist: there is one `OnStatus` ink (DESIGN §2.1).
- **Glass veils** are not tokens: `GlassHover`, `GlassSelected` and `GlassLine` are the `Text` colour at a fixed transparency (DESIGN §2.1) and are painted as `{Text, transparency}` pairs.
- **Material transparencies** come from `Theme.material(layer)` (§5.2), not from colour tokens.

**Font roles** (`Token.F`). The face per role comes from the active font set (§5.4); the default set is shown.

| Role | Default face | Load |
|---|---|---|
| `Page`, `Dialog`, `Section`, `Brand` | Montserrat SemiBold 600 | CDN: preloaded; Montserrat Bold 700 (local) stands in until it resolves |
| `LoaderTitle` | Montserrat Bold 700 | local (frame 0) |
| `Label`, `Button`, `NavSelected` | Roboto Medium 500 | CDN: preloaded; Roboto Regular 400 (local) stands in |
| `Nav`, `Body`, `Caption`, `Status` | Roboto Regular 400 | local |
| `Strong` | Roboto Bold 700 (menus' default-value emphasis, palette match highlight) | local |
| `Value`, `Stat`, `Key` | RobotoMono Regular 400 | local |

**Text roles** (`Token.TS`, px at scale 1, whole numbers). Compact and Default use the first column; Touch and Gamepad the second.

| Role | Compact / Default | Touch / Gamepad |
|---|---|---|
| `Page` | 22 | 22 (20 on phones) |
| `Dialog` | 18 | 18 |
| `Section` | 14 | 14 |
| `Brand` | 15 | 15 |
| `LoaderTitle` | 16 | 16 |
| `Label` | 14 | 15 |
| `Button` | 14 (13 on 28 px controls) | 14 |
| `Nav` | 14 | 15 |
| `Body` | 13 | 14 |
| `Caption` | 12 | 12 |
| `Status` | 13 | 13 |
| `Value` | 13 | 14 |
| `Stat` | 26 | 26 |
| `Key` | 12 | 12 |

### 5.2 Palettes, derivation, validation, generator, materials

- `theme/PaletteData` is **generated** by `tools/gen_palette.py` from `tools/palette.json` (both copied into the repo from `argon-UI-v2-work/bench/`, so the repo no longer depends on the work folder). It holds the 12 built-ins of DESIGN §2.3: the 10 v1 names with their v1 accents, **Daylight** (light) and **HighContrast** (also accepted as `"High contrast"`). The mockup and `PaletteData` are generated from the same JSON; `tests/theme.luau` compares a hash of the JSON with the one recorded in the generated header.
- `theme/Palettes` adds the v1 alias keys (§5.1) and approximations of Rayfield's theme names that Argon lacks: `Default`, `AmberGlow`, `Bloom`, `DarkBlue`, `Green`, `Light` (alias of Daylight), `Serenity`. These are generated with `Theme.create` at first use, not stored as literals.

```lua
Theme.palette : {[string]: Color3}      -- THE live table; Argon.Palette == Theme.palette (mutated in place)
Theme.name : string                      -- Argon.CurrentTheme
Theme.version : number
Theme.themes : {[string]: {[string]: Color3}}   -- Argon.Themes; values are complete derived palettes incl. v1 alias keys
Theme.changed : Signal                   -- (palette, name)
Theme.listChanged : Signal               -- fires on AddTheme/CreateTheme (theme pickers re-render)
Theme.get(token: string) -> Color3       -- accepts v1 alias names
Theme.derive(partial: {[string]: Color3}, base: string?) -> {[string]: Color3}
Theme.validate(p) -> { ok: boolean, issues: {{token: string, against: string, ratio: number, target: number}} }
Theme.add(name: string, partial) -> palette                  -- Argon:AddTheme (asserts as in v1)
Theme.create(spec: { Accent: Color3, Neutral: "cool"|"warm"|"neutral"?, Mode: "dark"|"light"?, Contrast: "normal"|"high"?, Name: string? }) -> palette
Theme.set(nameOrTable) -> (boolean, string?)                 -- Argon:SetTheme; table -> registered as "Custom" AND kept in Prefs.CustomTheme (D23)
Theme.setAccent(color: Color3?) -> ()                        -- Argon:SetAccent: override on top of any theme (nil clears); Prefs.Accent
Theme.setMaterial(m: "Solid"|"Tinted"|"Clear") -> ()         -- Window:SetMaterial; Prefs.Material; HighContrast forces Solid
Theme.material(layer: "Frame"|"Sheet"|"Dock"|"HUD") -> number   -- the transparency for the current material (DESIGN §2.2)
Theme.withPalette(p, fn) -> ()                               -- runs fn synchronously with Token resolution bound to p (window-local preview, §5.3)
Theme.list() -> {string}                                     -- sorted
Theme.contrast(a: Color3, b: Color3) -> number               -- WCAG ratio
```

**Derivation** (`Theme.derive`, DESIGN §2.5). Each rule applies only when the token is absent; host-given tokens are never adjusted, only reported by `validate`. Light mode is detected by the relative luminance of `Sheet` above 0.5.

| Token | Rule when absent |
|---|---|
| `Frame` | `Background`, else `Sidebar`, else `Window` darkened 25 % in OKLab L |
| `Sheet` | `Window` |
| `Surface` | `Surface`, then stepped toward white (dark) or black (light) until Surface/Sheet ≥ 1.15 |
| `Hover`, `Active` | `Hover` and `Active`, then stepped to ≥ 1.12 and ≥ 1.26 over Surface |
| `Raised` | Sheet stepped to ≥ 1.22 over Sheet |
| `Well` | `Input`, else Frame mixed 25 % toward black |
| `Track` | mix(Surface, Text), stepped until ≥ 1.6 over Surface |
| `Border`, `BorderSoft` | `Border` and `BorderSoft`, then stepped to ≥ 1.4 and ≥ 1.18 over Surface |
| `Text2` | mix(Text, Surface, 0.22), stepped until ≥ 9 over Surface |
| `Muted`, `Dim` | v1 `Muted` and `Dim`, stepped toward Text until they meet the targets below |
| `Disabled` | mix(Surface, Muted, 0.42) |
| `AccentHi`, `AccentDeep` | `AccentLight` and `AccentDark`, else Accent mixed 35 % toward white or black |
| `AccentAlt` | `Info` |
| `AccentText` | Accent stepped toward white (dark) or black (light) until ≥ 6 on Surface |
| `OnAccent` | dark ink (Frame mixed 40 % toward black) or white, whichever has the higher **minimum** over Accent and AccentHi; if still below 4.5, AccentHi is moved toward Accent until it passes |
| `AccentSoft` | mix(Surface, Accent, 0.16) |
| `Focus` | AccentHi (dark) or AccentDeep (light), stepped to ≥ 3 over Sheet |
| `Info` | (96, 165, 250) dark / (47, 116, 208) light |
| Status | stepped to ≥ 4.5 on Surface |
| `<Status>Soft` | mix(Surface, status, 0.15) |
| `OnStatus` | dark ink (dark mode) or white (light mode) |
| `Scrim` | `Frame` darkened; drawn at T 0.45 (dark) / 0.6 (light) |
| `Shadow` | black |

The accent override re-derives `AccentHi`, `AccentDeep`, `AccentText`, `OnAccent`, `AccentSoft` and `Focus` with the same rules on top of the active theme.

**Validation targets** (DESIGN §2.1 and the §2.3 contrast table; every built-in passes them):

| Pair | Target |
|---|---|
| Text on Surface | ≥ 10 |
| Text2 on Surface | ≥ 9 |
| Muted on Surface / on Hover and Raised | ≥ 4.8 / ≥ 4.5 |
| Dim on Surface / on Well | ≥ 3.5 / ≥ 4.5 |
| AccentText on Surface | ≥ 4.6 |
| OnAccent on Accent **and** on AccentHi | ≥ 4.5 |
| Status colours on Surface | ≥ 4.5 |
| Focus on Sheet and on Surface | ≥ 3 |
| Track on Surface | ≥ 1.6 |
| Border on Surface | ≥ 1.4 |
| Surface on Sheet | generated dark palettes ≥ 1.15; validation floor ≥ 1.08 (Daylight 1.10 and HighContrast 1.11 add a `Border` stroke on platters instead) |
| Hover on Surface | generated dark palettes ≥ 1.12; validation floor ≥ 1.06 |
| Text2 on Frame glass at the Tinted (0.14) / Clear (0.25) cap over white | ≥ 7.4 / ≥ 5.0 (Muted is banned on glass) |

`Theme.add` and `Theme.create` **adjust** failing derived tokens. Host-given tokens are reported through `validate` only, as a once-per-theme `Util.warnOnce` when `Argon.Debug` is on.

**Materials** (DESIGN §2.2). `Prefs.Material` is `"Solid" | "Tinted" | "Clear"`; the default is Tinted for dark themes and Solid for Daylight; HighContrast forces Solid.

| Layer (`Theme.material`) | Solid | Tinted | Clear |
|---|---|---|---|
| `Frame` (window, rail, phone header, tab bar) | 0 | 0.14 | 0.25 |
| `Sheet` | 0 | 0 | 0.06 |
| `Dock` (dock pill, reopen orb, quick dock) | 0 | 0.06 | 0.12 |
| `HUD` (keybind list, watermark, player list) | 0 | 0.10 | 0.18 |

Platters, `Raised` layers and wells are always opaque.

### 5.3 Theme switching protocol (live, explicit, state-aware)

`Theme.set(x)`:
1. Resolve the palette. Copy its values into `Theme.palette` in place, so `Argon.Palette` stays the same object.
2. Bump `version`.
3. Fire `changed`.

Each window listens to `changed` and repaints **synchronously, on-screen components only**: the shell scope, the active tab's mounted elements, open layers, the dock and the glow pool (`pool:retint()`). **A loading window counts as on-screen**: its shell and active tab are repainted even though `Main` is still hidden behind the loader, so a theme applied during the build (a restore, a host `SetTheme`) is never stale at the reveal. Each repaint is `obj:_applyTheme()`, that is `scope:repaint()` followed by `_render(false)`.

Components that are mounted but not visible (inactive tabs, closed pooled popovers) are stamped stale and catch up in `_onShown()`. Unmounted components need nothing.

There are no chunked waves: `controlsB` §4.1 measured that one pass is affordable, and the budget is ≤ 4 ms for 400 controls with about 40 on screen.

**State-dependent colours** never sit in the static paint list. Toggle tracks and their fill gradient, the selected tab, segmented pills, status pills, ProgressBar custom colours and swatches keep `{token | Color3}` in state and resolve it in `_render`. So:
- `SetColor("Warning")` follows themes;
- `SetColor(Color3)` stays fixed (CB-08).

**Every row root is painted.** `RowView` paints `Root.BackgroundColor3` with the `Hover` token even though the root's `BackgroundTransparency` is 1 (the pooled hover fill draws the hover, §8.8). So a script that recolours `el.Root` and then switches theme sees the theme's `Hover` again, and the v1 regression test keeps its meaning (§16.2).

**Stale reads are documented.** Reading a colour from an instance of a hidden tab right after `SetTheme` returns the old colour until that tab is shown (the catch-up is lazy). Scripts that need theme colours read `Argon:GetColor` or `GetPalette`, never instance properties. This is listed in the CHANGELOG (§14.5).

**Live preview** (DESIGN §7.8, owned by `feature/ThemePicker`, WU10). Hovering a theme card repaints **this window's on-screen components** inside `Theme.withPalette(previewPalette, fn)`:
- no `Theme.changed`, no `version` bump, no `Prefs` write, no `Argon.CurrentTheme` change, so host `OnThemeChanged` listeners never fire during a sweep;
- hidden components are not stamped stale (they never saw the preview);
- the repainted components are recorded, and the revert repaints exactly those under the real palette;
- hover changes are coalesced: an 80 ms hover delay, then at most one preview repaint per frame (one `task.defer`), so sweeping across 12 cards costs one repaint per frame, not a preview plus a revert per card;
- only a click calls `Theme.set`.

`Argon:OnThemeChanged(fn)` is `Theme.changed:Connect` and returns an unbind function by identity, as in v1. `GetColor(key, fallback)` and `GetPalette()` keep v1 semantics and accept the v1 alias names.

### 5.4 Fonts, type scale and metrics

- `theme/Fonts` keeps v1's six sets: Roboto (default, Roboto body plus Montserrat display), BuilderSans, Ubuntu, Condensed, Technical, Gotham. It adds a fixed `Mono` family, `rbxasset://fonts/families/RobotoMono.json`.
- `Fonts.set(name)` (`Argon:SetFont`):
  - ignores unknown names silently, as v1 does;
  - bumps `Token.version`;
  - triggers the same repaint path as a theme switch.
- `GetFonts`, `GetFontLabel` and `CurrentFont` are unchanged.

```lua
Fonts.face(role: FontRole) -> Font              -- cached per (set, role)
Fonts.set(name) -> boolean; Fonts.current : string; Fonts.list() -> {string}; Fonts.label(name?) -> string?
Metrics.space = {4, 8, 12, 16, 20, 24, 32}
Metrics.radius = { window = 16, card = 12, row = 8, control = 8, small = 6, full = "full" }
Metrics.rowHeight(kind: "default"|"tall"|"compact", density) -> number   -- mouse 44, touch 52, gamepad 48; tall = +20
Metrics.hit(density) -> number                    -- 32 / 44 / row
Metrics.textSize(role, density) -> number
Metrics.windowDefault(guiSize: Vector2) -> Vector2
   -- width  clamp(gui.X - 32, min(560, gui.X - 16), 980)
   -- height clamp(gui.Y - 40, min(400, gui.Y - 16), 660)
```

**Interface scale** is one `UIScale` per layer root, with the same factor on every layer. It is not applied through TextSize.
- Sources, in order: `Prefs.Scale`, else the `Scale` window option, else `"auto"`.
- `"auto"` is 1.15 when the GUI's short side is under 500 px and touch is the input, 1.1 when the GUI is 1,440 px tall or more, and 1.0 otherwise.
- The range is clamped to 0.8-1.5.

### 5.5 Icon resolver and the embedded Lucide map

**Data (measured on the real file).** `lib/Icons.luau` has one `48px` set of 1,573 icons on **9 sheets**, all with 48x48 cells, using **20 distinct x offsets and 25 distinct y offsets** (for example 0, 49, 98, ..., 967). There is no 16px set. So each icon is three base-36 digits: sheet index, x index and y index.

**Generated module** `src/icons/IconData.luau`. It is produced by `tools/gen_icons.luau` and never hand-edited:

```lua
-- GENERATED by tools/gen_icons.luau v1 from latte-soft/lucide-roblox@<commit> lib/Icons.luau (sha256 <hex>, 1573 icons)
return {
  format = 1,
  cell = 48,
  sheets = { 16898612629, 16898612819, ... },        -- 9 asset ids, sorted
  xs = { 0, 49, 98, ... },                            -- 20 values
  ys = { 0, 49, 98, ... },                            -- 25 values
  core = { search = "6ij", lock = "4ij", ... },       -- ~60 glyphs the library itself draws, plain table (no decode)
  aliases = { ["user-search"] = "user-round-search", loader = "loader-circle", ... },  -- v1 LUCIDE_ALIASES + renames
  packed = [==[
0a-arrow-down<code3>
2rrow-...<code3>
...]==],
}
```

- `packed` is a **front-coded** sorted list:
  - line i is `prefixLen (1 base-36 char) .. suffix .. code3`;
  - names are sorted bytewise;
  - the prefix is shared with the previous name, capped at 35 characters.
- Measured: **15,821 bytes**, against 23,481 plain and 147,702 for the v1 runtime download. Compile is 0.18-0.22 ms, and a full decode into a hash table is 1.2-2.1 ms in Lune (`bench/v2_icon_encoding.luau`).
- The core set is the icon names used by `src/`. The generator takes them from a constant list in the generator, kept in sync by a build lint that greps `Icons.apply(..., "<literal>")` and the `icon = "<literal>"` fields:

  `search, x, check, chevron-down, chevron-up, chevron-right, chevron-left, lock, info, circle-help, circle-check, circle-x, circle-alert, triangle-alert, loader-circle, minus, plus, copy, clipboard-paste, rotate-ccw, ellipsis, settings, palette, keyboard, users, bell, menu, panel-left, maximize-2, minimize-2, grip-vertical, search-x, star, pencil, trash-2, download, upload, eye, eye-off, activity, zap, circle-dashed, square-dashed, external-link, folder, file, sun, moon, gamepad-2, mouse-pointer-2, hand, command, corner-down-left, arrow-up, arrow-down, list-filter`

```lua
type IconSpec = { Image: string, ImageRectOffset: Vector2?, ImageRectSize: Vector2? }
Icons.resolve(nameOrId: string | number) -> (IconSpec, boolean)   -- spec, known; unknown -> fallback glyph, false
Icons.get(name) -> IconSpec?                     -- nil for unknown (Argon:GetIcon v1 semantics, no fallback)
Icons.has(name) -> boolean
Icons.apply(img: ImageLabel | ImageButton, nameOrId, colorToken?) -> boolean   -- sets Image/Rect props (+ ImageColor3 token)
Icons.decode() -> ()                             -- full table now; idempotent (scheduler idle job after reveal)
Icons.fallback = "circle-dashed"
```

**Resolution order:**
1. A number, `"rbxassetid://n"`, `"rbxthumb://..."` or `"http(s)://..."` is used as a raw image with no rect. This is Rayfield's numeric tab images.
2. Alias map.
3. `core` (O(1), no decode).
4. The full map, decoded lazily on the first non-core lookup, or earlier by an idle scheduler job enqueued at reveal. After that every lookup is O(1).
5. Unknown: the fallback glyph, `known=false`, recorded once in `Icons.missing`. There is no warning unless `Argon.Debug` is set.

- `IconSpec`s are cached per name.
- There is **no base64 atlas and no runtime HttpGet**. The v1 `ICON_ATLAS` and `ARGON_LOGO` blobs (48,456 bytes) are deleted.
- The default **logo**, when the host gives none, is the first letter of the window `Name` set in `Display` on an `Accent` plate with `OnAccent` ink: 3 instances, no asset, no branding. `Logo`, `Icon`, `SetLogo` and saved-logo semantics are otherwise v1.
- Glyphs are always one `ImageLabel`. The polyline fallback and text glyphs ("→", "–", "×", "?") are removed.

**Opt-in Lucide fetch.** `Argon:FetchIcons()` is **not** provided; the embedded map is complete. When Lucide adds icons, the generator is re-run. This is a release task, not a runtime one.

---

## 6. Input (WU3)

### 6.1 `input/Router`: one handler, key dispatch and the close-key policy

There is exactly **one** `UserInputService.InputBegan` connection per library load. It is connected when the first window is created and disconnected when the last window is destroyed. `InputEnded` is connected **only while a Hold-mode key is down** and disconnected when no hold is active.

```lua
type KeyEntry = {
  key: Enum.KeyCode | Enum.UserInputType,     -- keyboard key, mouse button (MouseButton2/3) or gamepad button
  owner: any,                                 -- element/window (for Lock/Destroy checks)
  mode: "Press" | "Toggle" | "Hold",
  onPress: ((input) -> ())?,
  onRelease: ((input) -> ())?,                -- Hold mode
  enabled: (() -> boolean)?,                  -- e.g. not Locked/Disabled, window not destroyed
  allowWhileTyping: boolean?,                 -- default false
  priority: number?,                          -- toggle key 100, palette 90, focus nav 80 (only when focus mode), keybinds 50
}
Router.bind(entry: KeyEntry) -> handle        -- handle:rebind(newKey), handle:unbind(); O(1) via map[key] = {entries}
Router.layerKey(fn: (input) -> boolean) -> handle   -- close-key / nav consumers (Layers + Focus); return true = consumed
Router.lastInputKind : "mouse" | "touch" | "keyboard" | "gamepad"
Router.inputKindChanged : Signal
Router.stats() -> { handlers: number, holdActive: boolean, entries: number }
```

**Dispatch** for each `InputBegan(input, gameProcessed)`:
1. Update `lastInputKind`, which drives focus-visible, hover suppression and density hints.
2. If a TextBox is focused (`UserInputService:GetFocusedTextBox()`), skip everything except entries with `allowWhileTyping`.
3. Offer the input to the `layerKey` consumers, top-down. This covers close keys and focus navigation (§6.3).
4. `gameProcessed` inputs are dropped for keybinds (v1 parity), except the toggle key on gamepad.
5. Look up `map[input.KeyCode]`, or `map[input.UserInputType]` for mouse and gamepad, in O(1). For each entry in priority order with `enabled()` true, call `onPress`. In Hold mode, record the held key and connect `InputEnded` if it is not already connected.

**The toggle key** is a `KeyEntry` owned by the window.
- `ToggleUIKeybind`, `SetToggleKey` and `Prefs.MenuKey` all normalise through `Util.keyCode`. A string "K", "RightShift" or "Enum.KeyCode.K" works (D1).
- The default is `Insert`.
- An optional gamepad toggle: `GamepadToggle = "HoldSelect"` (hold ButtonSelect for 0.4 s) or a KeyCode. The default is none (§18).

**Close-key policy** (one rule everywhere):
- **Backspace** (when no TextBox is focused) and **gamepad B** close the **topmost dismissible layer**, in this order:
  1. context menu or popover;
  2. command palette;
  3. dialog (= cancel);
  4. tooltip;
  5. clearing the quick filter;
  6. leaving focus mode.
- They **never hide the window**. Only the toggle key, the minimise button and the dock do that.
- **Escape is not bound by default.** Roblox opens its own game menu on Esc, so binding it would close a popover and open the Roblox menu at the same time.
- Hosts may opt in with `CloseKeys = {"Backspace", "Escape"}`.
- Outside clicks and the trigger itself also close popovers (§7.3).
- In keybind capture, Backspace or Delete set `None`. Capture is cancelled by:
  - a click outside the pill;
  - a 5 s timeout;
  - Escape, which is harmless there.

**Other global shortcuts.** These are active only while the window is visible and no TextBox is focused:

| Key | Action |
|---|---|
| Ctrl+K, or `/` | command palette |
| Ctrl+1 to Ctrl+9 | jump to tab N |
| Ctrl+] / Ctrl+[ | next / previous tab |

### 6.2 `input/Drag`: drag sessions

```lua
type DragHandlers = {
  onStart: ((pos: Vector2, input: InputObject) -> ())?,
  onMove: (pos: Vector2, delta: Vector2, input: InputObject) -> (),   -- coalesced: at most once per Heartbeat
  onEnd: ((pos: Vector2, cancelled: boolean) -> ())?,
  intent: "any" | "horizontal" | "vertical"?,   -- touch: start only after 6 px movement along the axis with |d_axis| > |d_other|
  lockScroll: ScrollingFrame?,                  -- ScrollingEnabled=false for the duration
  threshold: number?,                           -- px before onStart (window drag 6)
}
Drag.begin(input: InputObject, handlers: DragHandlers) -> session   -- call from a GuiObject.InputBegan
session:cancel()
Drag.active() -> number                        -- diagnostics: open sessions (0 at rest)
```

- Calling `Drag.begin` connects `UIS.InputChanged` and `UIS.InputEnded` for this session only, and disconnects them on end.
- For touch, it follows **only the starting `InputObject`** (`input == startInput`), so the thumbstick finger never moves the window (`shell` T1).
- For the mouse, it follows `MouseMovement`.
- `onMove` is coalesced to one call per frame with the latest position. This keeps 120 raw moves per drag down to one callback per frame (`controlsA` slider findings).
- Shared by the slider, colour SV square and hue/alpha strips, window move and resize, overlay drag, dock drag and the dropdown sheet swipe.

### 6.3 `input/Focus`: keyboard and gamepad focus engine

Argon uses its own roving focus, not `GuiService.SelectedObject`. `SelectedObject` only covers PlayerGui, while the window lives in CoreGui or `gethui` (`market` §6.6).

```lua
type Focusable = {                -- implemented by Element (8.4) and by layer components
  _focusKind: "button" | "value" | "text" | "list" | "none",
  _focusRoot: () -> GuiObject?,   -- mounted instance to ring (forces mount)
  _activate: (() -> ())?,         -- Enter/Space/A
  _adjust: ((steps: number) -> ())?,   -- Left/Right (+-1), Shift x10, Home/End = -inf/+inf
  _contextMenu: (() -> ())?,      -- Shift+F10 / gamepad X
}
Focus.attach(window) -> FocusController
controller:enter(reason) / controller:leave()      -- focus mode
controller:focus(item: Focusable, opts: {visible: boolean, scroll: boolean}) -> ()
controller:move(dir: "next" | "prev" | "first" | "last") -> ()
controller:trap(layerOrNil) -> ()                  -- dialogs/palette/popovers restrict the roving set
controller:pulse(item, times: number) -> ()        -- palette "go to" highlight
controller.current : Focusable?
```

**Focus mode** starts when any of these happens:
- the palette opens;
- a navigation key is pressed while the pointer is over the window;
- a control is clicked;
- the window opens while `PreferredInput == Gamepad`.

It ends on a click outside the window, on window hide, or through the close-key chain.

While focus mode is on, `ContextActionService:BindActionAtPriority("ArgonFocus", sink, false, Enum.ContextActionPriority.High.Value + 1, ...)` sinks Up, Down, Left, Right, Enter, Space, Tab, PageUp, PageDown, Home and End, plus DPad, ButtonA, ButtonB, ButtonX, ButtonY, ButtonL1 and ButtonR1, so the character does not move. It is unbound when focus mode leaves. Everything is pcall'd; if CAS is unavailable, keys are not sunk.

**Keyboard map** (`market` §6.6, minus Esc):

| Key | Action |
|---|---|
| Up / Down (and Tab / Shift+Tab, best effort) | Move focus |
| Left / Right | Adjust (Shift for ×10) |
| Home / End | Minimum / maximum |
| Enter / Space | Activate |
| Shift+F10 | Context menu |

**Gamepad map** (`market` §6.7):

| Input | Action |
|---|---|
| D-pad or left stick | Move focus (350 ms initial repeat, then 90 ms) |
| A | Activate |
| B | Close key |
| X | Context menu |
| Y | Palette |
| LB / RB | Previous / next tab |
| LT / RT | Page up / down |
| D-pad Left / Right on a value | Adjust, with hold-repeat that accelerates after 1 s |

**Ring.**
- One `Frame` with a `UIStroke` (2 px, `Focus` token) and a `UICorner` (element radius + 2), in the `Focus` layer.
- It is sized to the element plus 4 px and moved with the `spring` token.
- Shown only when `Router.lastInputKind` is `keyboard` or `gamepad` (focus-visible).
- The focused row is scrolled into view with a 24 px margin.

**Hint bar.** A 32 px strip at the bottom of the window, shown only while `PreferredInput == Gamepad`, with glyph text chips such as "A Select · B Back · X Options · Y Search".

### 6.4 `input/Platform`: input kind and density

```lua
Platform.preferred() -> "mouse" | "touch" | "gamepad"   -- UserInputService.PreferredInput when present (pcall), else TouchEnabled/GamepadEnabled/KeyboardEnabled heuristics
Platform.density() -> "mouse" | "touch" | "gamepad"     -- = preferred unless Prefs.Density overrides ("compact"=mouse)
Platform.changed : Signal                               -- PreferredInput change -> windows re-run responsive + re-render rows (heights)
Platform.isPhone(guiSize: Vector2) -> boolean           -- touch and (short side < 500 or width < 600)
```

- **Hover** visuals are suppressed when `lastInputKind == "touch"`, which removes sticky hover.
- **Long-press** (450 ms, implemented in `Element`) opens the tooltip, or the context menu when there is no tooltip.

---

## 7. Layers (WU3)

### 7.1 ScreenGui structure and z-order

One `ScreenGui` per window:
- `Name = GuiName`;
- `DisplayOrder = options.DisplayOrder or 100`;
- `ZIndexBehavior = Sibling`, `ResetOnSpawn = false`;
- `ScreenInsets = CoreUISafeInsets` when the property exists (pcall), otherwise `IgnoreGuiInset = false`;
- the attribute `ArgonUI = true`.

Its children are full-screen, transparent layer frames, in this ZIndex order:

| ZIndex | Layer | Holds |
|---|---|---|
| 1 | `Base` | Shadow, window `Main`, dock pill |
| 2 | `Overlay` | player and keybind overlays, host status HUD *(2.1)* |
| 3 | `Modal` | scrim, dialogs, palette, key gate |
| 4 | `Popover` | outside-click catcher, popover host, context menu |
| 5 | `Toast` | `Notifications` container (the v1 field name) |
| 6 | `Tooltip` | tooltip singleton |
| 7 | `Focus` | focus ring |
| 8 | `Boot` | loader card and ghost |

- Every layer root has its own `UIScale`, all set from the scale preference.
- **Layers are created lazily.** `CreateWindow` creates only the ScreenGui, `Boot` and `Base`, each with its UIScale: 5 instances. Each other layer, with its UIScale, is created on its first use (first popover, first toast and so on). This keeps `CreateWindow` within its 30-instance budget.
- **The cursor ScreenGui is lazy too.** It is created when the cursor driver first needs it or when `window.CursorGui` is read (a view field).
- The cursor stays in its own `GuiName.."Cursor"` ScreenGui with `DisplayOrder = 2147483647` (v1 parity).

```lua
Layers.create(window) -> LayerSet           -- { gui, Boot, Base } now; layers:get(name) creates Overlay/Modal/Popover/Toast/Tooltip/Focus on first use
layers:get(name: "Base"|"Overlay"|"Modal"|"Popover"|"Toast"|"Tooltip"|"Focus"|"Boot") -> Frame
layers:setScale(n) -> ()
layers:guiSize() -> Vector2                 -- gui.AbsoluteSize (inset-aware); one AbsoluteSize listener -> layers.resized Signal
layers.resized : Signal
-- dismiss stack
layers:push(entry: { id: string, kind: "popover"|"menu"|"palette"|"dialog"|"tooltip"|"filter", close: (reason: string) -> (), trap: boolean? }) -> handle
layers:pop(handle) -> ()
layers:closeTop(reason: "closekey" | "outside" | "hide" | "tab") -> boolean
layers:closeAll(reason) -> ()               -- window hide, tab switch (popovers/menus/tooltips only for "tab")
```

### 7.2 Outside-click catcher

- There is one transparent full-screen `TextButton` in the `Popover` layer (`AutoButtonColor=false`, `Text=""`, `Modal=false`). It is visible only while a popover or menu is open.
- Its `MouseButton1Down` and its touch `InputBegan` call `closeTop("outside")`. Because it is an active button, the click is sunk and not passed to the game.
- Dialogs use their own scrim in the `Modal` layer instead. It covers the **window area only** (`market` anti-pattern 6), so the window can still be dragged.

### 7.3 `layers/Popover`: one host per window, pooled

```lua
type PopoverSpec = {
  owner: any,                              -- element; previous owner's onClose runs before a new open
  anchor: GuiObject,                       -- trigger (mounted)
  content: (host: Frame, scope: Scope) -> Vector2?,   -- first open builds content into a pooled body; returns desired size
  reuse: string?,                          -- pool key ("dropdown", "color", "theme", "menu"): content built once per window, then rebound
  bind: ((host: Frame) -> ())?,            -- rebind data on every open (pooled content)
  width: number | "anchor"?,               -- default "anchor" (min 220)
  maxHeight: number?,                      -- default min(content, 300, space available)
  side: "below" | "above" | "auto"?,       -- default auto (below, flip above when space < h + 8)
  sheetOnPhone: boolean?,                  -- bottom sheet under 520 px width (dropdown, colour)
  onClose: ((reason: string) -> ())?,
}
Popover.attach(window) -> PopoverHost
host:open(spec) -> handle                  -- closes any current popover first (exactly one open per window)
host:close(reason) -> ()
host:isOpen(owner?) -> boolean
host:reposition() -> ()
```

- **Placement.** Below the anchor with a 6 px gap. Flip above when the space below is less than the height plus 8. Shift horizontally to stay ≥ 8 px inside `layers:guiSize()`, which is the GUI area, not the camera viewport.
- **Following.** While open, the host listens to the anchor's `AbsolutePosition` and `AbsoluteSize` (2 connections, in the popover's scope) and repositions. It closes when the anchor leaves its page's visible rectangle, or when the owner is locked, destroyed or hidden.
- **Closing** happens on:
  - the close key;
  - an outside click;
  - the trigger being clicked again (toggle);
  - another popover opening;
  - window hide;
  - tab switch;
  - the owner's `Destroy`.
- **Look.**
  - `Raised` fill, radius 12.
  - A 1 px white `UIStroke` at 0.88 transparency with a vertical transparency `UIGradient` (the lit edge).
  - One shared 9-slice shadow (`rbxassetid://1316045217`, v1's asset).
- **Motion.** `popIn` / `popOut` on transparency and a 4 px offset. No size tween with content.
- **Pooling.** Each `reuse` key's content is built on its first open in that window and kept, hidden, afterwards. A reopen is reposition, `bind(data)` and fade.
- **Instances.** The host itself (frame, corner, stroke, gradient, shadow and catcher) is about 7 instances, created on the first open of any popover in the window.

### 7.4 `layers/Tooltip`: a singleton per window

```lua
Tooltip.attach(window) -> TooltipHost
host:schedule(target: Element, text: string, how: "hover" | "focus" | "long-press") -> ()   -- hover 400 ms (skip-delay 100 ms when one is open), focus 0 ms, long-press immediate
host:hide() -> ()
window._tooltip -> TextLabel's parent Frame while visible, else nil   -- v1 test seam kept
```

- One Frame with a corner and a wrapped RichText `TextLabel`, max width 280, built on the first show.
- Placement: right of the row, then left, below and above, using offset positions (v1's tooltip tests stay meaningful).
- `Active = false`.
- Closes on mouse leave, scroll, tab switch, window hide and the close key.
- The marker is an `ImageButton` "TipMarker" with the `circle-help` glyph: 16 px visual, 32 px hit area (44 on touch). It is tappable.

### 7.5 `layers/VirtualList`: recycled rows

```lua
type VirtualListSpec = {
  parent: GuiObject,
  rowHeight: number,                        -- fixed; variable heights are out of scope (List uses 30/44 per mode)
  overscan: number?,                        -- default 2
  createRow: (scope: Scope, parent: Frame) -> RowView,   -- builds one pooled row
  bindRow: (row: RowView, item: any, index: number) -> (),
  maxHeight: number?,                       -- auto height up to this, then scroll
  emptyView: ((scope, parent) -> GuiObject)?,
}
VirtualList.new(scope, spec) -> VL
vl:setData(items: {any}) -> ()              -- O(visible) re-render
vl:refreshIndex(i) / vl:refreshVisible()
vl:scrollTo(index, align: "nearest" | "center")
vl:count() -> number
vl.scroller : ScrollingFrame                -- CanvasSize = n * rowHeight; one CanvasPosition listener
```

- Live rows are capped at `ceil(viewport / rowHeight) + overscan * 2`.
- Rows are created lazily up to the cap and rebound on scroll.
- Used by the Dropdown options, the List control, the palette results, the profiles list, the player overlay and the context menu (when it has more than 12 items).

### 7.6 `layers/ContextMenu`

```lua
ContextMenu.open(window, anchorOrPoint: GuiObject | Vector2, items: {
  { Text: string, Icon: string?, Shortcut: string?, Danger: boolean?, Disabled: boolean?, Callback: () -> () } | "divider"
}) -> handle
```

- Built on `Popover` with `reuse = "menu"`.
- Keyboard: Up/Down highlight and Enter activates.
- Element rows supply the standard items (§8.4): Reset to default, Copy value, Paste value, Copy flag.

---

## 8. Element model and containers (WU5)

### 8.1 Lifecycle in one picture

```
Tab:CreateToggle(cfg)
  -> Toggle.new(owner, cfg)                       ~1 us, 0 instances
       state: Name, Type, CurrentValue, Flag, _cfg, _callback, _default, _order, visibility bits
       Store.register(flag, el)                    pending value -> silent set + one callback (v1 hydration)
       owner.Elements/insert, tab._elements, Registry.add(el), tab:_noteElement(el) -> Scheduler.enqueue(tab job)
  <- element (fully usable: Set/Get/OnChanged/Lock/SetVisible/Destroy/flags/search)

Scheduler slice (Heartbeat, <= budget)            or forced by reading el.Root / el._title / ...
  -> tab:_ensureSkeleton() (page + section cards)  -> el:_mount(ctx)
       RowView.mount + Class.build -> render(false) -> applyVisibility -> stamp theme/font version
       parent root into section body (LayoutOrder = el._order)

Set / Lock / SetVisible / theme / font change     -> state first; _render(animated = on screen) if mounted
Destroy                                            -> Store.unregister, owner lists, Registry.remove, scope:destroy
```

### 8.2 View-field proxy: instance fields stay valid

Every class declares `viewFields`. The base `__index` serves methods from the class table first. Then, for a key in `viewFields` while `rawget(self, "_mounted")` is false, it calls `self:_ensureMounted()` and returns `rawget(self, key)`. After the mount these fields are raw, so later reads have zero overhead.

**Base `viewFields` for every Element:**
- `Root`;
- `_title`, `_description`, `_tipMarker`;
- `_lock`, which is mounted on demand;
- `_stroke`, which is always nil in v2 but kept for scripts that read it.

**Per-class extras:**

| Class | Extra fields |
|---|---|
| Toggle | `_track`, `_knob` |
| TelemetryCard | `Status`, `Icon`, `Rail` |
| Tab | `TabButton`, `Accent`, `IconBox`, `Icon`, `ButtonTitle`, `Count`, `Page`, `PageGroup` |
| Section | `Root`, `Body`, `Layout` |
| Row | `Root`, `Layout`, plus each `Columns[i].Holder` (columns are small tables with their own proxy) |
| Window | `ScreenGui` (always raw), `Main`, `Shadow`, `Sidebar`, `Content`, `TabList`, `PageHost`, `Notifications`, `PlayerListOverlay`, `KeybindListOverlay`, `CursorGui` |

`_ensureMounted()` mounts the chain in order: shell, then the tab skeleton, then the section card, then the row, then the element. It runs synchronously with no budget, so a script that touches instances degrades to eager building of exactly what it touched.

### 8.3 `Element.define`: what a control module implements

```lua
Element.define(spec: {
  Type: string,                         -- "Toggle" (Element.Type field)
  height: "default" | "tall" | "auto" | number,   -- natural height role (Metrics.rowHeight) or px
  flaggable: boolean?,                  -- registers config.Flag with Store
  counts: boolean?,                     -- counts toward tab badge (interactive controls only; CB-20)
  viewFields: {string}?,
  init: (self, config: table) -> (),    -- state only: CurrentValue/_default/options...; MUST NOT create instances
  build: (self, view: RowView, scope: Scope) -> (),   -- add control parts to view (view.Root, view.Title exist)
  render: (self, animated: boolean) -> (),            -- state -> view (idempotent)
  normalize: ((self, raw: any) -> any)?,              -- Set coercion (e.g. Slider round/clamp)
  equals: ((a: any, b: any) -> boolean)?,             -- default ==; Dropdown uses Util.jsonEqual
  payload: ((self) -> any)?,                           -- callback arg; default CurrentValue
  encode: ((self) -> any)?,                            -- persisted JSON value; default payload
  decode: ((self, raw: any) -> any)?,                  -- from Codec.normalize output to Set input
  restoreCallback: ((self) -> ())?,                    -- what LoadConfiguration fires (default: Callback(payload)); Keybind overrides (D3)
  search: ((self) -> string?)?,                        -- extra searchable text (options, content)
  focus: { kind: "button"|"value"|"text"|"list"|"none", activate: ((self) -> ())?, adjust: ((self, steps: number) -> ())? }?,
  menu: ((self, items: {any}) -> ())?,                 -- append context-menu items
  methods: {[string]: function}?,                      -- public API (Set, Refresh, ...)
  aliases: {[string]: string}?,                        -- e.g. { SetContent = "Set" }
}) -> ElementClass

ElementClass.create(owner: Section | RowColumn, config: any) -> Element   -- what Tab/Section builders call
```

### 8.4 Common element API, state and states

**Public (v1, unchanged names):**
- `Name`, `Type`, `Flag`, `CurrentValue`, `Section`, `Row`, `Locked`, `LockReason`, `HasTooltip`;
- `SetVisible(bool)`, `SetTitle(text)`, `SetDesc(text)`, `SetTooltip(text)` (and `Tooltip`);
- `Lock(reason?)`, `Unlock()`, `SetLocked(bool, reason?)`, `Destroy()`.

**Added in v2:**

| Method | Behaviour |
|---|---|
| `Get()` | Returns the value |
| `GetDefault()` | Returns the default |
| `Reset()` | Sets the default, with commit source `"user"` |
| `OnChanged(fn)` | Returns a `Connection`; fires on every committed change with `(value, source)` |
| `SetCallback(fn)` | Replaces the callback |
| `SetDisabled(bool)` | Disables the control |
| `IsDisabled()` | Reports it |
| `SetLoading(bool)` | Where meaningful |
| `Focus()` | Focuses the control |
| `Flash(token?)` | Highlights the control |
| `SetIcon(name)` | Where meaningful |

Every setter returns `self` (D14).

**State bits** (private):
- `_hidden` (SetVisible), `_filtered` (quick filter), `_whenHidden` (VisibleWhen);
- `_disabled`, `_whenDisabled` (EnabledWhen);
- `_locked`, `_loading`, `_error`;
- `_hover`, `_pressed`, `_focused`, which exist only while mounted.

**Interaction state machine.** There is one per element and it is the only place visual state is decided. `Element:_visualState()` returns, by priority, one of:
1. `locked`
2. `disabled`
3. `loading`
4. `error`
5. `pressed`
6. `focused`
7. `hover`
8. `rest`

The visuals for each are in `market` §6.4.
- Hover comes from `MouseEnter` / `MouseLeave`, and only when `Router.lastInputKind ~= "touch"`.
- Pressed comes from `InputBegan` / `InputEnded` of `MouseButton1` or `Touch` on the root.

**Context menu** (right-click, long-press, Shift+F10 or gamepad X):
- Reset to default (when the value differs);
- Copy value (`Env.setClipboard`, plus an internal clipboard);
- Paste value (when the internal clipboard holds a compatible type);
- Copy flag (when flagged);
- the control's own items (`spec.menu`).

### 8.5 Visibility model (D7, CB-01)

```
visible(el) = not (el._hidden or el._filtered or el._whenHidden)
row visible = any child visible
section visible = (any element or row visible) and not section._hidden
                   (collapsed sections keep the header visible and hide only the body)
```

- `Element:_applyVisibility()` is the **only** writer of `Root.Visible`. It notifies its row and section, which recount in O(own children).
- The search filter sets `_filtered` and never touches `_hidden`.
- The tab badge counts only `counts` elements that are visible.
- **`VisibleWhen` and `EnabledWhen`** config keys take one of:
  - `{Flag = "X", Equals = v}`;
  - `{Flag = "X", NotEquals = v}`;
  - `{Flag = "X", In = {...}}`;
  - `{All = {...}}` or `{Any = {...}}`;
  - `function(flags) -> boolean` together with `Flags = {"X", "Y"}`, which declares the dependencies.

  `container/Registry` keeps `dependents[flag] = {el...}` and re-evaluates only those elements on `Store.flagChanged`. Evaluation reads `Argon:GetFlagValue`, so it works before any instance exists.

### 8.6 Commit path and callbacks

There is one function, `Element:_setValue(raw, opts: {silent: boolean?, source: "user"|"api"|"restore"|"drag"|"commit"})`:
1. `v = normalize(raw)`. If `equals(v, CurrentValue)` and this is not a restore, return.
2. Store the value. Mirror it into compat fields: Dropdown `CurrentOption` (the same table as `CurrentValue`), Keybind `CurrentKeybind`, ColorPicker `Color`.
3. `_render(onScreen)`.
4. If `silent`, stop here.
5. For `source == "drag"`:
   - the live callback is throttled to at most one per frame by `Drag`;
   - flag listeners fire;
   - **no** flash and **no** autosave.

   The drag end calls `_setValue(v, {source = "commit"})`, which runs the full commit and fires `config.OnRelease` / `OnCommit` when present.
6. Full commit, in v1 order (`api` §6):
   1. `Store.commit(el)`, which fires the flag listeners;
   2. flash (`Accent` hairline on the row's left edge, `state` token, with no extra tween objects at rest);
   3. autosave scheduling;
   4. `Util.xcall(config.Callback, ctx, payload)`;
   5. `OnChanged` connections fire.

On a callback error, `_error = true` and a small `Danger` dot appears after the title with the message as its tooltip. With `RevertOnError = true`, the value reverts silently.

### 8.7 Lock and Disabled (D26, CB-10)

- **`Lock(reason | {Reason, Icon, Variant = "blocked"|"premium"})`** draws a scrim (a `TextButton` that sinks input) plus a badge:
  - the badge is `Frame` with `AutomaticSize X`, a `UISizeConstraint` and `MaxSize` set from the row width;
  - the icon and label inside it are chosen once per reason with `TextService:GetTextSize` (synchronous), not size listeners;
  - the fields are `_lock = {Root, Badge, Label, Icon}` (v1 shape).
- **`SetDisabled(true)`** draws no badge. Content goes to 0.5 transparency and the root gets `Interactable = false` (pcall).
- **Both block every user path:**
  - pointer;
  - keybind hotkeys (the Router entry's `enabled()`);
  - focus activation and adjustment;
  - popovers, which close when the owner locks.

  Programmatic `Set`, `SetFlagValue` and restores still apply.

### 8.8 `component/RowView`: standard anatomy and the instance diet

Sections are **one grouped card**. Rows inside it have no fill, no stroke and no per-row corner at rest (`market` §6.11). Hover fills the row with radius 8, inset 4 px inside the card.

```lua
type RowView = {
  Root: TextButton,        -- Name "Control"; AutoButtonColor false; BackgroundColor3 = T.Hover; BackgroundTransparency 1 at rest
  Corner: UICorner,        -- radius 8 (hover fill shape)
  Title: TextLabel,        -- Name "Title"; F.BodyMedium; TS.Label; T.Text; truncates
  Description: TextLabel?, -- Name "Description"; created on demand; F.Body; TS.Body; T.Muted; wrapped; AutomaticSize Y
  TipMarker: ImageButton?, -- on demand
  trailingX: number,       -- px reserved on the right by the control (title width = 1, -(14 + trailingX + 12))
}
RowView.mount(el, ctx: MountCtx, opts: { height: number, trailing: number, interactive: boolean }) -> RowView
RowView.setDescription(view, text?) -> ()   -- Root.AutomaticSize=Y when present; trailing widgets stay in the top band (anchored to y = height/2)
RowView.setTooltip(view, text?) -> ()
```

- Display-only elements (Label, Paragraph, Divider and so on) use a `Frame` root with the same `Name = "Control"`.
- **Description layout** uses no Lua listeners:
  - the title is at y 0 to H;
  - the description is absolutely positioned at `y = H - 6` with `AutomaticSize Y`;
  - the Root has `AutomaticSize Y` and a bottom `UIPadding` of 10 px, created with the description.
- **Instance budget per control (mounted, no description).** The mixed-workload average must be ≤ 7.

| Control | Parts | Instances |
|---|---|---|
| Button | Root, Corner, Title, Icon | 4 |
| Toggle (switch) | Root, Corner, Title, Track, TrackCorner, Knob, KnobCorner | 7 |
| Toggle (checkbox) | Root, Corner, Title, Box, BoxCorner, Check | 6 |
| Slider | Root, Corner, Title, Value(TextBox), Hit, Groove, GrooveCorner, Fill, Thumb, ThumbCorner | 10 |
| Stepper | Root, Corner, Title, Minus, Value, Plus, PillCorner(x2) | 8 |
| Segmented (3) | Root, Corner, Title, Track, TrackCorner, Indicator, IndicatorCorner, 3 labels | 10 |
| Keybind | Root, Corner, Title, Pill, PillCorner | 5 |
| Input | Root, Corner, Title, Field, FieldCorner, FieldStroke, TextBox | 7 (+1 clear button on demand) |
| TextArea | Root, Corner, Title, Field, FieldCorner, FieldStroke, Scroller, TextBox | 8 |
| Dropdown (closed) | Root, Corner, Title, Field, FieldCorner, Value, Chevron | 7 |
| ColorPicker (closed) | Root, Corner, Title, Swatch, SwatchCorner, Hex | 6 |
| Label | Root, Text (+Icon) | 2-3 |
| Paragraph | Root, Title, Body (+Icon) | 3-4 |
| Divider | Root, Line (+Label, Line) | 2-4 |
| Space | Root | 1 |
| ProgressBar | Root, Corner, Title, Value, Track, TrackCorner, Fill, FillCorner | 8 |
| TelemetryCard | Root, Corner, Icon, Title, Content, Status, StatusCorner | 7 |
| Callout | Root, Corner, Icon, Title, Body | 5 |
| List | Root, Corner, Title, VirtualList scroller, live rows | 4 + rows (each ≤ 4) |

UIStroke is used only by input wells (Input, TextArea), one per section card at 0.94 transparency, and the focus ring. That gives about 0.2 per control.

### 8.9 Tab, Section and Row data model

**Tab** (`container/Tab`):

```lua
Tab = { Name, IconName, Window, Group?, _elements = {}, _sections = {}, _controlCount = 0, _currentSection = nil,
        _skeleton = false, _mountedCount = 0, _job = nil, _badge = nil, _visibleCount = 0 }
tab:CreateSection(nameOrCfg) -> Section     -- v1 + {Title, Description, Icon, Collapsible, Collapsed, Actions}
tab:CreateRow(cfgOrNumber) -> Row
tab:Create<Control>(cfg) / tab:<Control>(cfg)   -- aliases per api section 4; a control before any section auto-creates "General"
tab:Select() -> tab                          -- = window:SelectTab(tab)
tab:SetBadge(textOrNumber?) -> tab           -- host badge on the sidebar item
tab:_filter(query) -> ()                     -- quick filter (v1 seam; sets _filtered; empty state "No controls match 'x'")
tab:_ensureSkeleton() -> ()                  -- PageGroup Frame + Page ScrollingFrame + UIListLayout + UIPadding + section cards
tab:_mountJob() -> Job                       -- mounts _elements in creation order within the deadline
tab:_onShow() / tab:_onHide()                -- PageGroup.Parent = PageHost / nil (detached), theme catch-up, loops
```

**Section** (`container/Section`):

```lua
Section = { Name, Elements = {}, Rows = {}, Tab, _collapsed = false, _hidden = false, _desc = nil, _icon = nil }
section:Set(name) -> section                 -- Rayfield
section:SetVisible(bool) / :Collapse() / :Expand() / :ToggleCollapsed() / :IsCollapsed()
section:Reset() -> section                   -- every element:Reset()
section:<Builder>(...)                       -- every Tab builder except Section, CreateX and X forms, plus Row/CreateRow (v1 semantics, _build swaps tab._currentSection)
```

- The card is a header (title in `Section` role 13 SemiBold, sentence case, `Muted`; optional icon and chevron) placed **outside** a `Body` frame.
- The `Body` frame has `Surface` fill, a radius-12 corner, a vertical `UIListLayout` (padding 2) and a `UIPadding` of 4.
- The collapsed state is persisted in `Prefs.CollapsedSections[tabName.."/"..sectionName]`.

**Row** (`container/Row`). The v1 contract is kept:
- `Columns[i] = {Holder, Layout, Section}`, with `Holder.LayoutOrder = i`;
- round-robin placement, `Use(i)`;
- `Elements`, `Owner`, `Root`, `Layout`;
- a column count clamped to 1-4, spacing 0-24 and `MinColumnWidth` 80-400.

v2 lays the row out with **engine flex**:
- `Root` has a horizontal `UIListLayout` with `Wraps = true` and `HorizontalFlex = Fill`.
- Each holder has a `UIFlexItem` (`FlexMode = Fill`) and a `UISizeConstraint` with `MinSize.X = MinColumnWidth`.
- Narrow windows wrap the columns into a stack with **zero Lua listeners**. v1 used 14 per two-column row of ten controls.
- Line-height balancing (`_rowPad`) is dropped: rows no longer have per-control borders, so unequal neighbour heights are not visible.
- `_balance()` and `_relayout()` remain as no-op methods that return the row (test seam).
- If `Wraps` or `UIFlexItem` is unavailable (pcall on creation), the fallback is a single `AbsoluteSize` listener on `Root` that toggles `FillDirection`, coalesced through one deferred pass per frame.

### 8.10 `container/Registry`: per-window registry and search index

```lua
Registry.new(window) -> Registry
reg:add(el) / reg:remove(el)
reg:all() -> {Element}                         -- creation order
reg:search(query: string, limit: number) -> {{el: Element, score: number, ranges: {{number, number}}}}
reg:dependents(flag) -> {Element}
reg:commands() -> {Command}                    -- RegisterCommand entries + built-ins
```

- **Indexed text.** Each element has a lazily built `el._searchText`, invalidated by `SetTitle`, `SetDesc`, `SetTooltip` and `Refresh`. It combines:
  - `Name` (weight 3);
  - section and tab name (2);
  - Description and Tooltip (1);
  - options and paragraph content (1, from `spec.search`);
  - `config.Keywords` (2).
- **Ranking:** word-prefix > contiguous substring > subsequence, plus a recency boost from the palette's recent list.
- 2,000 elements search in ≤ 2 ms (gate).
- Unmounted tabs are searchable. This is the reason the index lives on state, not instances.

---

## 9. The lazy, time-sliced build strategy

### 9.1 What each public call costs

| Call | Work | Instances | Budget |
|---|---|---|---|
| `loadstring(...)()` | define modules, build `Argon` | 0 | ≤ 2 ms top level |
| `CreateWindow` | normalise options, destroy the previous same-name window, read prefs (sync readfile + JSONDecode), apply theme, font and scale, create the ScreenGui with its layers and the loader card, bind the toggle key, enqueue the shell job at priority 0 | ≤ 30 | ≤ 3 ms |
| `CreateTab` | state, plus a sidebar-item job when the shell is mounted | 0 | ≤ 10 µs |
| `CreateSection` / `CreateRow` | state | 0 | ≤ 10 µs |
| `Create<Control>` | `Element.create`, Store register, lists, registry, note the tab job | 0 | median ≤ 10 µs |
| `Set` / `Lock` / `SetVisible` before mount | state only | 0 | ≤ 5 µs |
| Reading an instance field | sync mount of that element's chain | its own | as mount |

`Create*` and the setters call `Scheduler.noteForeground(elapsed)` (two `Env.clock()` reads). The scheduler then shrinks the next slice, so library work never exceeds the per-frame budget even when the host builds synchronously (§9.4).

### 9.2 The mount pipeline

1. **Shell job** (priority 0). Builds `Main` **unparented**: the sidebar, topbar, page host and the sidebar items for the tabs that exist. It then parents `Main` into `Base` with `Visible = false` behind the loader. This is 1-2 slices, and the shell is ≤ 120 instances.
2. **Active tab job** (priority 1).
   - `tab:_ensureSkeleton()`: the PageGroup is built **detached** (`Parent = nil`), with its page, list layout and section cards.
   - It then mounts elements in creation order until the deadline.
   - When done, the PageGroup is parented into `PageHost` **once**.
   - If the hand-off needs the page before the job finishes, the remaining elements mount behind a skeleton shimmer of 1-2 frames.
3. **Hover prefetch.** `MouseEnter` on a sidebar item calls `Scheduler.bump(tab, 2)`. Focus-moving onto a tab does the same.
4. **Background tabs** (priority 3) are mounted in creation order **only after the reveal**, at the interactive budget (4 ms), detached. Turn this off with `Prewarm = false`, in which case tabs mount on their first visit only.
5. **Idle** (priority 4) runs `Icons.decode()`, the palette index warm-up, the theme-picker previews if the picker is likely to be used, and so on.

**Tab switch:**
- an inactive PageGroup is **detached** (`Parent = nil`), so resizes and layout never touch it (`perf` §5);
- the new tab's PageGroup is attached;
- if it is not fully mounted, its job is flushed up to the visible viewport (about 15 rows) synchronously (≤ 4 ms), and the rest continues at priority 1.

### 9.3 Priorities and fairness

| Priority | Work |
|---|---|
| 0 | shell |
| 1 | active tab, or a tab being forced |
| 2 | hovered or focused tab |
| 3 | other tabs |
| 4 | idle |

Within the same priority, jobs run FIFO. The loader's progress for "Building <Tab> · n of m" comes from the active tab job's counters.

### 9.4 The frame-shared budget (why no frame exceeds about 8 ms)

- The host's synchronous `Create*` burst is state only. Measured, 500 calls take 0.47 ms in Lune (`bench/v2_state_element_cost.luau`), against a budget of 8 ms.
- The scheduler's slice in the same frame gets `budget - foregroundSpentThisFrame`, with a minimum of 1 ms.
- Restore callbacks (`LoadConfiguration`) are host time. The library slices them at 8 ms when `coroutine.isyieldable()`, as v1 does at 45 ms, now tighter. They are reported to the loader.
- Host callbacks fired by user interaction are outside any budget, but the library adds at most one render per frame per element.

### 9.5 Worked timeline: a 500-control hub (10 tabs x 50), synchronous host, no saved config

| t | Event |
|---|---|
| 0 ms | `CreateWindow`: about 2 ms, 26 instances, card hidden (transparency 1) until 150 ms. The shell job is queued. |
| 0-3 ms | The host makes 500 `Create*` calls: about 0.5-5 ms of library work, 0 instances. |
| frame 1 | The shell job runs (≤ 8 ms minus foreground) and continues in frame 2 if needed. |
| frames 2-6 | The active tab (50 controls at about 0.15 ms each in Lune) is mounted at about 8 ms per frame. |
| about 0.1 s | The host thread is dead (its script finished) and the active tab is mounted, so it is **ready before 150 ms**: no card is shown. The window enters (veil fade plus a UIScale of 0.97 to 1 on the `window` token). |
| after reveal | Tabs 2-10 mount in the background at 4 ms per frame: about 450 x 0.15 ms is about 68 ms of work, roughly 17 frames, never more than 4 ms per frame. |
| idle | The scheduler drains, Heartbeat disconnects, and Lua work is 0 per frame. |

With `LoadConfiguration()` after the build, the restore callbacks run in 8 ms slices. The host's thread stays suspended, so the card appears at 150 ms with "Restoring settings 120/240" and a determinate bar, and the reveal follows the restore.

### 9.6 Forced mounts and graceful degradation

- A script that reads `el.Root` for every element right after creation forces an eager build. That is linear: there is no global registry scan, so the cost is O(own size) per element.
- **Destroy before mount** removes state only: no instances, no scope.
- **Set during mount** is safe, because mount ends with `_render(false)` from the current state.

### 9.7 Idle guarantees (all MUST, checked by `tests/perf.luau`)

After the reveal, when the scheduler has drained:
- no Heartbeat, RenderStepped or Stepped connections are owned by the library;
- exactly 1 `UIS.InputBegan`, 0 `InputChanged`, 0 `InputEnded`;
- 0 running tweens or springs;
- 0 pending `task.delay` timers, except the autosave debounce while dirty and the toast timers while toasts are visible.

While the window is hidden:
- loops are stopped (`_onHidden`);
- the cursor driver is disconnected;
- background mounting is paused unless `Prewarm = "always"`.

---

## 10. Window, shell and loader (WU6)

### 10.1 `CreateWindow` sequence (≤ 3 ms, ≤ 30 instances, no yields)

1. `options = Options.normalize(options)` (§14.3):
   - string toggle keys;
   - `Icon` becomes `Logo`;
   - `LoadingTitle` becomes `LoadingScreen`;
   - `KeySystem`;
   - the `PlayerList` and `KeybindList` defaults.
2. **Re-execution.** `Env.genv().__ArgonUI.windows[guiName]` holds the previous window with this `GuiName`, from this or an earlier load. If there is one, call its `:Destroy()`. That destroys its scopes, its Router entries and its library runtime once that runtime has no windows left. Also destroy any leftover ScreenGui with the same name and the attribute `ArgonUI` (v1 rule).
3. **Library state** (D9, single configuration):
   - `table.clear(Argon.Flags)` and `table.clear(Argon._pendingFlags)` **in place**, so cached references stay valid;
   - close the persistence gate;
   - `Store.configure(options.ConfigurationSaving)`;
   - arm the 4 s gate fallback (v1).
4. **Prefs first** (CB-03).
   - `Prefs.loadForWindow(config)` reads the meta file, or the v1 file's `__argon`, synchronously when `readfile` exists (well under 1 ms for typical files), then merges a pre-assigned `Argon._uiPreferences`.
   - It applies theme, accent, font, scale, title, subtitle, logo and reduced motion **before the first instance**.
   - Options are overridden only by **present** keys (D2).
5. `Layers.create(window)`: the ScreenGui with its `Boot` and `Base` layers and their UIScales (5 instances), then `Env.protectGui`, then parented once. The other layers are lazy (§7.1).
6. `Loader.create(window)`: the card in `Boot` (≤ 16 instances), at transparency 1, with the 150 ms reveal timer armed.
7. Bind the toggle key (Router), connect `layers.resized` to responsive, and set the mouse-unlock state.
8. `Scheduler.setMode("loading")` and enqueue the shell job.
9. Capture `hostThread = coroutine.running()`.
10. Return the window. Its methods live in a class metatable, so a test can still monkeypatch a method as a raw field (the run.L1335 pattern).

### 10.2 Loader rules (`shell` §4, adopted)

**States:** `boot` → `building` → `restoring` → `handoff` → `open`. `IsLoading()` is true until `handoff` begins.

**Ready** means **all** of:
- the shell and the active tab are mounted (or the window has no tabs yet);
- and **one** of:
  - (a) `FinishLoading()` was called;
  - (b) the host thread is `dead`;
  - (c) there has been no library activity (`Create*`, `SetLoadingProgress` or restore) for **250 ms**, measured by a single re-arming `task.delay(0.25)` check, after at least one frame.

  A suspended or running host thread is treated as idle-capable. In a real client, Heartbeat never observes the host thread running.

**Manual mode** (`Loading = "manual"`, `ManualLoading = true`, or any host call to `SetLoadingProgress`) disables (b) and (c) until `FinishLoading`.
- Internal restore reporting calls `window:SetLoadingProgress(f, status, "restore")`. The third argument marks it as internal, so it does **not** flip manual mode, but it still goes through the (monkeypatchable) method.

**Card visibility:**
- not shown if ready within **150 ms**;
- once shown, kept at least **400 ms** (`LoadingMinimum`);
- `LoadingScreen = "always"` shows it immediately; `"never"` never shows it.

**Progress** is monotonic and comes from:
- host fractions mapped onto 0-85 %;
- the restore, which takes 85-100 %;
- otherwise the active tab's mount counter.

The bar is **determinate** only when a total is known. Otherwise it is an indeterminate sweep (a `Motion.loop` owned by the card). The percentage is shown only when determinate.

**Status text** is sentence case, for example "Building Combat · 32 of 50", "Restoring settings 120/240" or "Waiting for script…". v1 upper-cased host status strings; v2 shows host strings **as given**.

**Stall.** After 8 s without progress, the card shows "Still working…" with an **Open now** button, which calls `FinishLoading`.

**Watchdog.** At 30 s **since the last progress** (D11), it calls `FinishLoading`.

**Overlays** stay hidden until `open` (v1 rule).

**API:**
- unchanged: `SetLoadingProgress(f, status)`, `FinishLoading()`, `IsLoading()`;
- new: `SetLoadingStatus(text)`, `OnLoaded(fn) -> Connection`, `Build(fn)`, `LoadingScreen = "auto"|"always"|"never"|{Title, Subtitle, Logo, Tips}`, `LoadingMinimum`.
  - `Build(fn)` runs `fn` with xpcall. On error the card shows the error with "Open anyway" and "Copy error".
  - In `LoadingScreen`, Tips rotate after 2 s.
- Rayfield `LoadingTitle` / `LoadingSubtitle` map to `LoadingScreen.Title` / `Subtitle`.

**Card anatomy** (≤ 16 instances):
- Frame, Corner, lit-edge Stroke, Gradient, Shadow;
- logo plate (2-3);
- title;
- status;
- bar track, track corner, fill, fill corner;
- percent.

The card is `min(360, gui.X - 32)` wide and 96 px tall, centred.

### 10.3 Hand-off (no resize of anything with content)

1. `Main` is already built at its final size and position, hidden. It is made visible under a **veil**: a window-coloured Frame, the top child of `Main`, at transparency 0.
2. If the card was shown:
   - a **ghost** (an empty Frame with the window colour, corner, stroke and shadow) morphs from the card's rectangle to `Main`'s rectangle in 0.24 s (`ghost` token);
   - the card's content fades out in the first 0.12 s;
   - then the ghost and card are destroyed.
3. The veil fades out over 0.18 s (`veil` token). Sidebar, topbar and page rise 6 px with a 30 ms stagger.
4. Overlays, the dock and the hint bar appear. Focus goes to the first tab, or to the palette if the host asked for it.
5. `Scheduler.setMode("interactive")`, the background tabs are enqueued, `OnLoaded` fires, and the card scope is destroyed.

If the card never showed, step 2 becomes `window` token entrance: a `UIScale` of 0.97 to 1 on `Base`, plus the veil.

### 10.4 Shell layout and breakpoints (`shell` §5)

All sizing reads `layers:guiSize()`, which is inset-aware. The camera viewport is never used.

| Breakpoint | Rule | Layout |
|---|---|---|
| Wide | ≥ 1100 px | sidebar 220, content plus jump rail |
| Medium | 760-1100 px | sidebar 200, or a user-collapsed rail of 64 |
| Narrow | < 760 px | icon rail 64 with tooltips |
| Phone | `Platform.isPhone` | full-screen sheet; topbar (title, palette, minimise); horizontal tab strip; 52 px rows; overlays off; toasts top-centre |

- **Sidebar:**
  - brand (logo plus title; the subtitle is optional, sentence case, `Muted` 12);
  - a palette trigger ("Search… Ctrl K", which replaces v1's per-tab search box; the quick filter stays reachable as `/`-less filtering inside the palette scope);
  - tab items, with a single shared selection indicator (an `AccentSoft` pill plus a 3 px `Accent` bar) moved by the `spring` token;
  - the profile row (rbxthumb avatar 48 plus display name, which opens an account menu: settings, unload);
  - a collapse chevron (`Prefs.SidebarCollapsed`).
- **Topbar (52 px):**
  - a breadcrumb "Title / Tab" (`Page` role for the tab name);
  - an optional host status chip (`Window:SetStatus(text?, tone?)`, off by default);
  - `ThemeButton` (keeps its v1 name; opens the appearance popover);
  - minimise (Lucide `minus`, 32 px hit area).

  The topbar is the drag handle: 6 px threshold, clamped so at least 64 px of it stays on screen. Double-click recentres.
- **Jump rail:**
  - section chips with a keyed diff (no rebuilds);
  - scroll-spy from `CanvasPosition`;
  - smooth scroll with a tweened NumberValue;
  - hidden while filtering and with one section (v1 tests).
- **Resize:** a bottom-right grip using a `Drag` session. Size and position persist in `Prefs.WindowSize` / `WindowPosition`. `SetSize` keeps v1's clamp rules.

### 10.5 Dock, open button, mouse unlock and cursor

- **Dock pill** (`shell/Dock`, the market F1 "OpenButton"):
  - 44 px, logo plus title, plus a key hint on PC; draggable; snaps to the nearest edge with a spring; position in `Prefs.DockPosition`;
  - default placement on the left edge at 30 % height;
  - `OpenButton = "auto"` (default) shows it whenever the window is hidden and the preferred input is not keyboard and mouse, **or** the toggle key is `None`. `true` always shows it; `false` never does.
  - `Window:SetOpenButton(opts)`.
  - The first hide on PC shows a toast: "Press Insert to reopen" (the actual key name).
- **Mouse unlock:** while the window is visible, a hidden 1x1 `TextButton` in `Base` has `Modal = true`, and it is removed on hide. `MouseUnlock = false` opts out (`shell` S4).
- **Cursor** (`shell/Cursor`, v1 semantics: `Cursor = nil|"auto"|true|false`, `SetCursorVisible`, `IsCursorDrawn`, `_cursorMode`). The `RenderStepped` driver is connected **only** while it is needed (window visible and (mode `true`, or mode `"auto"` and `MouseIconEnabled == false`)). It is re-evaluated on visibility and on `MouseIconEnabled` change, so idle cost is 0 otherwise.

### 10.6 Window API: v1 kept, v2 added

**Kept (v1, `api` §3.2):**
- `SetVisibility`, `ToggleVisibility`, `Toggle`, `Open`, `Close`, `SetToggleKey`;
- `SetTitle`, `SetSubtitle`, `GetTitle`, `GetSubtitle`, `SetLogo`, `SetFont`, `GetFonts`, `SetTheme`, `GetThemes`, `SetSize`;
- `SetPlayerListVisible`, `SetKeybindListVisible`, `TogglePlayerList`, `ToggleKeybindList`;
- `SetOverlaysAlwaysVisible` and its alias `SetOverlaysPinned`, `ToggleOverlaysAlwaysVisible`, `AreOverlaysAlwaysVisible`;
- `SetOverlayTransparency`, `SetOverlayScale`, `SetSmoothTransitions`, `ResetOverlayPositions`;
- `Dialog` and its alias `Popup`, `Confirm`;
- `CreateTab`, `CreateLibrarySettings`, `SetThemePickerVisible`, `ToggleThemePicker`;
- `SetCursorVisible`, `IsCursorDrawn`;
- `SetLoadingProgress`, `FinishLoading`, `IsLoading`;
- every private seam that the tests use (§16.3).

**Added:**

| Method | Behaviour |
|---|---|
| `IsVisible()` | Reports visibility |
| `SelectTab(tabOrNameOrIndex)` | Switches tab |
| `GetActiveTab()` | Returns the active tab |
| `SetScale(n \| "auto")` / `GetScale()` | Interface scale |
| `SetDensity("auto" \| "compact" \| "touch")` | Row density |
| `SetReducedMotion(bool)` | Reduced motion |
| `SetOpenButton(opts)` | Dock pill options |
| `SetStatus(text?, tone?)` | Host status chip |
| `RegisterCommand{Name, Description, Icon, Keywords, Shortcut, Callback}` | Returns a handle |
| `OpenPalette(query?)` | Opens the command palette |
| `Prompt{Title, Content, Placeholder, Default, Validate, OnSubmit, OnCancel}` | Text prompt |
| `CreateConfigManager(tab)` | Profiles UI |
| `SetLoadingStatus`, `OnLoaded`, `Build` | §10.2 |
| `SetMouseUnlock(bool)` | Mouse unlock |
| `Destroy()` | Destroys the window |

---

## 11. Controls (WU7, WU8, WU9)

All controls:
- use `Element.define` (§8.3);
- keep v1's config keys, defaults, callback payloads, `Set` coercion and persisted formats (`api` §7);
- take the instance budgets in §8.8;
- follow the state model in §8.4.

The table lists only v2 additions and decisions.

| Control | Unit | v2 additions and decisions |
|---|---|---|
| **Button** | WU7 | `Variant = "Secondary"` (default) \| `"Primary"` \| `"Ghost"` \| `"Danger"`. `Icon`. `Set(name)` for Rayfield (alias of `SetTitle`). `SetLoading(bool)`: spinner, frozen width, re-entry blocked. `Async = true` runs the callback in `task.spawn` with loading shown until it returns. Press feedback is the `Active` fill on the `press` token. Focus kind is button. |
| **Toggle** | WU7 | `Style = "Switch"` (default) \| `"Checkbox"`. The track stays **44x24** and keeps the Name `Track`, so v1 tests that look up the track still work. The knob moves on the spring. `Set` keeps v1's `v == true` coercion. Keyboard: Space and Enter flip it, Left and Right set off and on. Optional `Keybind = "F"` attaches a Router entry that flips the toggle. That entry is not persisted unless `KeybindFlag` is given. |
| **Slider** | WU7 | The Hit band is 24 px (32 on touch) over a 6 px groove, with a 16 px thumb and a 40 px touch halo. `Drag` uses `intent = "horizontal"` on touch, plus `lockScroll` on the page. The callback fires live, throttled to one per frame. New `OnRelease(value)`. Commit (flash and autosave) happens on release. An editable **value pill** in `Mono`. Arrow keys step by Increment; Shift steps by 10x; Home and End go to the limits. Validation: a reversed `Range` is swapped; `Increment <= 0` means continuous with 2 decimals (no NaN, `controlsA`); the maximum is always reachable. **Suffix spacing:** v1 rendering is kept (no space) unless the suffix starts with a letter and is longer than 2 characters. So Rayfield's "Bananas" gives "10 Bananas", while "%", "x" and "ms" stay attached. |
| **Stepper** | WU7 | Hold-to-repeat: 350 ms, then 80 ms, accelerating after 1 s. Minus and plus dim at the limits. `Range` and `Increment` are validated as for the Slider. Left and Right adjust. |
| **Segmented** | WU7 | The sliding indicator moves on the spring; selected text uses `OnAccent`-safe ink on `AccentSoft`. Left and Right move the selection. `Refresh` keeps v1 semantics: no callback. |
| **Keybind** | WU7 | **Modes and Rayfield semantics (D3):** see §14.3. `Mode = "Press" \| "Toggle" \| "Hold"`, where v1 `Toggle = true` means Toggle and Rayfield `HoldToInteract = true` means Hold. Capture accepts keyboard keys, `MouseButton2` / `MouseButton3` and gamepad buttons. Backspace or Delete set None; a click outside, a 5 s timeout or Escape cancel. `OnChanged(key)` fires on rebind. Conflicts with another binding on the same key show a `Warning` hint under the row (not blocking). The key list overlay updates in place. Locked or destroyed binds never fire (Router `enabled()` and `unbind` on Destroy). |
| **Input** | WU8 | v1 elision rules are kept. **Callback when the text changed OR Enter was pressed** (Rayfield fires on every FocusLost; v1 fired only on change; this keeps both use cases without click-away noise). `RemoveTextAfterFocusLost` clears the box silently, so the callback fires once and `CurrentValue` keeps the submitted text (D13). New: `Numeric`, `Min`, `Max`, `MaxLength` (with a counter), `Validate(text) -> ok, message` (error state), `Live = true` (an `OnChanged` debounced at 0.2 s), `ClearButton` (default true). The focus ring is the field stroke in `Focus`. Text is never auto-focused on touch. |
| **TextArea** | WU8 | A `ScrollingFrame` (`AutomaticCanvasSize = Y`) holds the TextBox. The caret is kept in view with `CursorPosition` and `TextBounds`. `AutoGrow` between `MinHeight` and `MaxHeight` (v1 `Height` is the fixed size when `AutoGrow` is off). `Monospace`, `MaxLength` with a counter. `GetLines` is kept. Commits on FocusLost. |
| **Dropdown** | WU8 | A shared `Popover` (`reuse = "dropdown"`) with a VirtualList of 36 px rows (48 on touch). The search box is shown when there are more than 8 options and is never auto-focused on touch. Keyboard: Up/Down, Home/End, Enter, Space (multi), and typing filters. Options are strings or `{Text, Description, Icon, Disabled, Divider}`; `CurrentOption` holds **text** values (persisted format unchanged). Multi-select gets a "Select all · Clear" header, and the field shows "A, B +N". **Unknown `Set` values are ignored** rather than clearing the selection (`controlsA` §12; no warning, so the existing test passes because it accepts either outcome). `Refresh(new, keepCurrent)` keeps v1 semantics (a deferred `_desiredOption` is applied and its callback fired), but the commit now goes through `_setValue` with source `"restore"`, so flag listeners and autosave also run (D12). `Source = "Players" \| "Teams"` refreshes on open. `Options = function() -> {..}` runs in `task.spawn` with a spinner row (no yield on the caller). On phones it opens as a bottom sheet. Change detection uses `Util.jsonEqual` instead of 2x JSONEncode. |
| **ColorPicker** | WU8 | A shared popover (`reuse = "color"`) containing: an SV square (2 ImageLabels with UIGradients, built once), a hue strip, an optional alpha strip (`Alpha = true`), a hex input (`#RRGGBB` or `#RRGGBBAA`), 8 presets (theme accents) and 6 recent colours. HSV is kept in state, so hue survives a grey pick. `.Color` mirrors `CurrentValue` (Rayfield). The persisted format is v1's `{__argonColor, R, G, B}` plus `A` when alpha is used; v1 ignores the extra key. Drags use `Drag` sessions, so no handlers leak. |
| **Label** | WU9 | `CreateLabel(text \| {Text\|Title\|Name, Icon, Color, Style}, icon?, color?, ignoreTheme?)` (Rayfield). `Set(text, icon?, color?)`, with `SetContent` as an alias. `Style = "muted" \| "info" \| "success" \| "warning" \| "danger"`. A plain text row, not a card. `Tooltip` and `Description` are now honoured (D15). |
| **Paragraph** | WU9 | `Set(string \| {Title, Content})` (D4). `Description` stays an alias for content (D15 keep). The Icon is optional; v1's mandatory info chip is gone (`Icon = "info"` still works). *(2.1: "show more")* |
| **TelemetryCard** | WU9 | v1 fields `Status`, `Icon` and `Rail` are kept (lazy). `SetStatus(text, colorOrToken)` re-renders from state (CB-08). New `Variant = "stat"`: big `Value`, `Label`, `Delta` with an up or down arrow, `SetValue` and `SetDelta`. `CreateStat(cfg)` is an alias that creates the stat variant. |
| **Divider** | WU9 | `Set(visible)` (Rayfield). The label hugs its text (flex lines). |
| **Space** | WU9 | `px` is clamped to 4-80 (v1). |
| **ProgressBar** | WU9 | `Indeterminate` (the sweep loop runs only while on screen). `Thresholds = {{0.9, "Danger"}}`. `SetColor(Color3 \| token)` persists across themes. Still never persisted (v1). |
| **List** | WU9 | Virtualised (`layers/VirtualList`; 30 px rows, or 44 px when any item has a Description). Keyed rows: the key is `Id`, else `Title`. `SetItems` diffs, and `AddItem`, `RemoveItem(idOrIndex)` and `UpdateItem(idOrIndex, patch)` are O(1) plus a visible refresh. **Record identity is kept**, so callbacks receive the same table (CB-15). Actions: up to 2 inline, the rest behind "…" (ContextMenu); `Style = "danger" \| "warning"` and `Color` are kept, with 12 px labels. `EmptyText` plus `EmptyAction = {Text, Callback}`. `Filter = true` adds a filter box above 8 rows. `Icon` and `Avatar = userId` (rbxthumb) per row. `MaxHeight`. |
| **Callout** (new) | WU9 | `CreateCallout{Title, Content, Type = "info"\|"success"\|"warning"\|"danger", Icon?, Action = {Text, Callback}?, Dismissible?}`. Tinted with `<Type>Soft`. |
| **Image** (new) | WU9 | `CreateImage{Image = id\|url, Height = 120, ScaleType = "Fit", Corner = 8, Caption?}`, plus `Set(image)`. |

---

## 12. Feedback and features (WU10)

### 12.1 Notifications (`feature/Toast`)

```lua
Argon:Notify{ Title, Content|Description, Type = "info"|"success"|"warning"|"error"|"loading"?,
              Icon|Image?, Duration = number | "auto" | false | math.huge,  -- default "auto"
              Actions = {{ Text|Title, Callback, Variant? }}? (<= 2), Callback?, Id?, Position? }
  -> ToastHandle { Instance: Frame, Update(opts) -> handle, Dismiss() -> (), SetProgress(f) -> handle }
Argon:Toast(text, type?) -> ToastHandle        -- small centred pill
```

- **Severity:** `Type` wins. Rayfield `Image` maps to the icon. Without a `Type`, v1's keyword guess is a fallback that matches **whole words** and has negation guards ("No errors found" is not an error).
- **Duration:** `"auto"` is `clamp(2.5 + 0.06 × chars, 3, 9)` seconds, ×1.5 for errors, and at least 8 s with actions. Hover or focus pauses the timer. On touch, a swipe dismisses.
- **Stacking:**
  - at most 4 visible; older ones collapse into a "+N more" chip;
  - the same `Id` updates in place (a loading toast can become success);
  - identical toasts within 2 s collapse with "×N".
- **Pooling:**
  - 5 pooled plain `Frame` cards, with no CanvasGroup;
  - one tween drives the progress hairline;
  - the exit is a fade, then a height collapse on the `collapse` token, and capped toasts exit the same way.
- **Before `CreateWindow`:** a standalone toast host ScreenGui (`ArgonUINotify`) is created lazily. The first `CreateWindow` reparents the container into the window's `Toast` layer and exposes it as `window.Notifications` (D19).
- **Placement:**
  - `TopRight` by default, pushed clear of pinned overlays;
  - `TopCenter` on phones;
  - `Prefs.NotificationPosition` overrides.
- **Return value:** a handle. For compat, the handle forwards `.Parent`, `.AutomaticSize` and `:GetDescendants()` reads to `Instance` through `__index`, so v1 code that treated the return as an instance keeps working.

### 12.2 Dialogs (`feature/Dialog`)

- `Dialog` / `Popup` and `Confirm` keep v1 config keys and returns: `{Root, Panel, Title, Body, Visible, Show, Close, Destroy}`.
- **New `Prompt`.**
- **Modal layer.** A scrim over the window area only. The panel is clipped and opens on `dialogIn` (UIScale 0.95 to 1 plus fade; no Back easing).
- **Buttons** auto-size with `AutomaticSize X` and 13 px labels. Destructive confirms focus **Cancel** first.
- **Keys:** Enter triggers the primary button. The close key, an outside click (`DismissOnOutside`, default true) and X all cancel, and **every dismissal path calls `OnCancel`** (D18).
- **Stacking:** dialogs queue; only the top one is interactive.
- **Phones:** under 480 px wide, a dialog renders as a bottom sheet.

### 12.3 Command palette (`feature/Palette`)

- **Opens with** Ctrl+K, `/`, the sidebar search button or gamepad Y.
- **Panel:**
  - 560 x `min(440, 70 % of the GUI height)`, in the `Modal` layer with a scrim at 0.35;
  - a 44 px input;
  - VirtualList rows of 40 px (48 on touch);
  - groups: Best match, Settings, Commands, Recent.
- **Search:** `Registry:search` with matched characters bolded through RichText. Each row shows a "Tab › Section" breadcrumb and a live value chip.
- **Keys:**
  - Enter goes to the control: select the tab, mount if needed, scroll into view, `Focus:pulse` twice;
  - Ctrl+Enter or gamepad X runs it in place (flip a toggle, press a button);
  - Left and Right adjust a slider result.
- **Built-in commands:** theme, scale, density, reduced motion, overlays, save profile, open settings.
- **Empty states:** as in `market` §6.10.

### 12.4 Overlays (`feature/Overlays`)

- The player list and the keybind list keep v1's fields and setters, and their persisted positions in `__argon.OverlayPositions`.
- **The defaults change (decided):** `PlayerList` and `KeybindList` are **off unless the host enables them** (`shell` O1). This is a behaviour change for v1 hosts that relied on them being on.
- **Player rows:**
  - keyed by UserId, with `rbxthumb` avatars, so a join is ≤ 8 instances and 0 API calls;
  - `Players.PlayerAdded` / `PlayerRemoving` are connected **only while the player overlay is enabled**.
- **Keybind list:**
  - rows keyed by Router entry and updated in place, with one deferred refresh per frame;
  - sizes to its content and hides when empty.
- **Placement and look:**
  - overlays auto-place outside the window rectangle and clamp to the GUI area;
  - they raise on interaction and follow the layer scale;
  - names are `PlayerOverlay` and `KeybindOverlay`.

### 12.5 Library settings and config manager (`feature/Settings`)

`CreateLibrarySettings(tab)` (once per window, as in v1) builds these sections. **Every control is a view over `Prefs`**, not a user flag (CB-02):

| Section | Contents |
|---|---|
| Appearance | theme cards (`ThemePicker` content reused), accent row, font, scale, density, reduced motion |
| Window | menu key (a Keybind writing `Prefs.MenuKey`), open button mode, title/subtitle rename, logo |
| Overlays | v1 toggles, opacity, scale, reset positions, overlay hotkeys |
| Notifications | position, mute |
| Configuration | the config manager |
| About | version, icon count |

- Legacy `ArgonUI*` names (`api` §8) resolve through `Store.virtualFlags` (§13.4).
- **`CreateConfigManager(tab)`:**
  - a profile list (List control with actions Load, Overwrite, Rename (Prompt), Delete (Confirm plus a 6 s Undo toast), and a star for autoload);
  - "Save current as…";
  - Export (to the clipboard, or into a read-only TextArea when there is no clipboard);
  - Import (Prompt, then a summary: "12 settings changed, 2 unknown", then Apply);
  - Reset all (Confirm);
  - a live status line ("Saved 2 s ago", "Saving…" or "Save failed: reason") from `Store.stats()`.

### 12.6 Theme picker (`feature/ThemePicker`)

- Opened from the topbar `ThemeButton`. A popover with `reuse = "theme"`.
- Content:
  - cards with a mini window preview (window, surface and text bars plus an accent chip), grouped Dark and Light;
  - an accent row (8 presets plus custom through the ColorPicker popover);
  - font and scale segmented controls.
- Built once and re-rendered on `Theme.listChanged`.
- **One `Theme.set` per pick**, persisted through `Prefs` (D16).
- Keeps `ToggleThemePicker()` (returns the open state, or false when the picker is disabled) and `SetThemePickerVisible`.
- v1 test seam: `Window.ThemePicker` (lazy) gives the popover content frame, holding `ThemeOptions` with one `TextButton` per theme named after the theme. Each one carries a UIStroke whose colour is `Accent` when that theme is active.

### 12.7 Key gate (`feature/KeyGate`, Rayfield parity, opt-in)

- `KeySystem = true` with `KeySettings = {Title, Subtitle, Note, FileName, SaveKey, GrabKeyFromSite, Key = string|{string}}`. Argon adds `Validate = function(key) -> ok, message`, `GetKeyLink = url`, and `Blocking = true` (default).
- The gate card is drawn in the `Modal` layer **before** the shell reveal:
  - a 44 px input;
  - "Get key", which copies `GetKeyLink`;
  - Continue;
  - a ±6 px error shake over 0.3 s;
  - the remembered key read from `<Folder>/<FileName>.key` when `SaveKey` is set;
  - a busy state while `Validate` runs, in `task.spawn`.
- **The only documented yield in `CreateWindow`.** With `Blocking = true`, `CreateWindow` yields until the key is accepted (Rayfield semantics: a gated script must not run ungated). The loader card and the gate are on screen **before** the yield, and there is no network before first paint.
- `GrabKeyFromSite` fetches with `HttpGet` in a spawned thread **after** the gate is visible.
- `Blocking = false` returns immediately and holds the reveal until `OnKeyAccepted`.
- A rejected or closed gate leaves the window destroyed and makes `CreateWindow` return a **stub window**. Every method on the stub is a no-op, so the host script continues without erroring.

---

## 13. Persistence (WU4)

### 13.1 Files and formats

| File | Content | Compatibility |
|---|---|---|
| `<Folder>/<FileName>[<Ext>]` | The **Default profile**: a JSON object of `flag -> value` plus `"__argon"` (prefs mirror) | Exactly v1's path rule (`configPath`, L741-750) and format, so v1 reads v2 files and v2 reads v1 files |
| `<Folder>/<Base>.profiles/<Name><Ext>` | Named profiles, in the same format as Default | New |
| `<Folder>/<Base>.meta.json` | `{"v":2,"Prefs":{...},"Autoload":"Default"\|name,"LastProfile":name}` | New. `<Base>` is FileName without its extension. |
| `<Folder>/<FileName>.key` | Saved key-gate key (`SaveKey`) | Rayfield-like |

- `Folder` is `FolderName or Argon.DefaultFolder`. `Ext` is `FileExtension or ".rfld"` and is appended only when FileName has no extension (v1).
- Profile names are sanitised to `[%w _%-]`, up to 40 characters. "Default" is reserved for the main file.
- `listfiles` results are normalised: split on `/` and `\`, keep the basename, strip the extension.

**Per-type persisted values.** These are v1 (`api` §7) and owned by each control's `encode` and `decode`:

| Control | Persisted as |
|---|---|
| Toggle | JSON boolean |
| Slider, Stepper | number |
| Input, TextArea | string |
| Segmented | string |
| Dropdown | array of strings |
| Keybind | key-name string |
| ColorPicker | `{__argonColor=true,R,G,B[,A]}` with channels 0-1 |
| ProgressBar, List, display blocks | not persisted |

**Reading foreign values** (`persist/Codec.normalize`) uses v1's wrapper unwrapping (L840-866), with one change:
- **D25:** a colour table **without** `__argonColor` is read as 0-255. That is Rayfield's packing; v1 Argon always wrote the marker.

### 13.2 `persist/Store`: flags, commit bus, save and load

```lua
Store.configure(cfg: {Enabled, FolderName, FileName, FileExtension}?) -> ()   -- per CreateWindow (D9: last window wins)
Store.flags : {[string]: Element}            -- == Argon.Flags (same table forever; cleared in place)
Store.pending : {[string]: any}               -- == Argon._pendingFlags
Store.register(flag, el) -> ()                -- v1 registerFlag: duplicate warns "[Argon UI] Duplicate configuration flag replaced: X"; pending -> applyRestore
Store.unregister(el) -> ()                    -- D8: remove from flags; last value moved to pending (kept for saves)
Store.applyRestore(el, raw) -> (ok, err)      -- silent set (decode) + el:_restoreCallback() exactly once + listeners
Store.commit(el) -> ()                        -- flag listeners + autosave scheduling (called by Element commit)
Store.get(flag) -> any; Store.set(flag, value) -> (ok, err)     -- GetFlagValue / SetFlagValue (v1 semantics)
Store.snapshot() -> {[string]: any}           -- GetFlags
Store.onFlagChanged(fn) -> unbind             -- D6: unbind by identity
Store.flagChanged : Signal                    -- (flag, value, el) for Registry VisibleWhen
Store.setReady(value, saveNow) -> (ok, err?)  -- SetPersistenceReady
Store.save(profile: string?) -> (ok, pathOrErr)             -- verified write (v1 L973-1017) + __argon mirror
Store.load(profile: string?, opts: {window: Window?}?) -> (ok, info)
Store.delete(profile?) -> (ok, pathOrErr); Store.reset() -> (ok, err)
Store.stats() -> ConfigStats                  -- v1 GetConfigurationStats fields + {Profile, Autoload, SaveState: "idle"|"pending"|"saving"|"failed"}
Store.virtualFlags : {[string]: string}       -- "ArgonUITheme" -> "Theme", ... (13 legacy names, api section 8)
```

**Autosave** works as in v1:
- it requires `ready`, not loading, not destroyed, and a path;
- it is debounced to 0.35 s with a token;
- the gate is opened by `LoadConfiguration`, `SetPersistenceReady(true)`, or the 4 s fallback after `CreateWindow`.

In v2 it is also scheduled by a topbar theme pick (D16), because all prefs setters schedule a **meta** save. Meta saves are not gated by the flag gate: prefs were read at `CreateWindow`, so nothing can be clobbered.

**`Store.load` order** (v1 L1019-1126 with fixes):
1. Without `readfile`, return false. With a missing file, open the gate and return **`true, "no saved configuration"`** (D10, with a distinguishable info string).
2. Decode the file. Fold the `__argon` keys into Prefs **only if no meta file exists** (migration). Fold the legacy `ArgonUI*` flags into Prefs once and drop them.
3. Flags run in v1 order: non-booleans first, then booleans, alphabetical within each group.
   - A registered flag goes through `applyRestore`.
   - An unregistered flag goes to `pending` and is counted as missing.
4. Progress goes through `window:SetLoadingProgress(base + span*i/n, ("Restoring settings %d/%d"):format(i, n), "restore")` on the loading window, about 40 times, as in v1.
5. When `coroutine.isyieldable()`, it yields (`task.wait()`) after every 8 ms of work. That is one of the allowlisted yield sites. Callbacks slower than 25 ms are collected and warned, as in v1.
6. If all flags were merely parked (deferred hydration), return **true** with the info "N value(s) waiting for controls" (D10).
7. `_lastConfigStats = {path, total, applied, missing, failed, slowest}` (v1).

### 13.3 `persist/Profiles`

```lua
Profiles.list() -> {{Name: string, Path: string, Autoload: boolean}}      -- "Default" first
Profiles.save(name) -> (ok, err); Profiles.load(name) -> (ok, info)       -- load = Store.load(name); sets LastProfile
Profiles.rename(old, new) -> (ok, err); Profiles.delete(name) -> (ok, err)   -- Default cannot be renamed/deleted (delete = reset)
Profiles.setAutoload(name?) -> (); Profiles.getAutoload() -> string?
Profiles.export(name?) -> string            -- "ARGON2:" .. base64(JSON {v=2, profile=name, flags={...}})
Profiles.import(text, opts: {apply: boolean?, saveAs: string?}) -> (ok, summary: {changed: number, unknown: number, invalid: number})
   -- accepts ARGON2 strings, raw JSON objects (v1 / Rayfield files); applies through Store.set (callbacks fire)
```

The Argon facade adds optional profile arguments, and existing calls still behave exactly as in v1:
- `SaveConfiguration(name?)`, `LoadConfiguration(name?)` and `DeleteConfiguration(name?)`;
- `LoadConfiguration()` with no name loads `Autoload or "Default"`.

New facade methods: `ListConfigurations`, `RenameConfiguration`, `SetAutoloadConfiguration`, `GetAutoloadConfiguration`, `ExportConfiguration` and `ImportConfiguration`.

### 13.4 `persist/Prefs`: one source of truth (CB-02, CB-03)

```lua
Prefs.loadForWindow(storeCfg) -> PrefsTable     -- sync read: meta.Prefs -> file.__argon (migration) -> {}; then merge Argon._uiPreferences
Prefs.get(key) -> any; Prefs.set(key, value) -> () -- fires Prefs.changed(key, value); schedules meta save; mirrors into __argon at next flag save
Prefs.changed : Signal
Prefs.export() -> table                          -- the __argon block (v1 keys + v2 keys)
Prefs.table : PrefsTable                         -- == Argon._uiPreferences (alias kept for tests)
```

**`PrefsTable` keys:**
- v1 keys: `Theme`, `Font`, `Title`, `Subtitle`, `Logo`, `PlayerListEnabled`, `KeybindListEnabled`, `OverlaysAlwaysVisible`, `OverlayTransparency`, `OverlayScale`, `SmoothTransitions`, `OverlayPositions`;
- v2 keys: `Accent`, `CustomTheme`, `Scale`, `Density`, `ReducedMotion`, `MenuKey`, `OpenButton`, `DockPosition`, `WindowPosition`, `WindowSize`, `SidebarCollapsed`, `LastTab`, `CollapsedSections`, `NotificationPosition`, `PaletteRecent`.

Rules:
- A pref overrides a `CreateWindow` option **only when the key is present** (D2).
- Window setters (`SetTheme`, `SetTitle` and the rest) write Prefs, and the settings controls are views over Prefs. So an API change survives a reload, and the theme is set once per action.
- `Store.virtualFlags` makes `GetFlagValue` and `SetFlagValue("ArgonUITheme", ...)` read and write the corresponding pref.

---

## 14. Compatibility layer (WU11)

### 14.1 The `Argon` facade (`src/init.luau`)

**Fields:**

| Field | Value |
|---|---|
| `Version` | `"2.0.0"` |
| `Flags` | `Store.flags` |
| `DefaultFolder` | `"ArgonUI"` |
| `AssetFolder` | `"ArgonUI"`, kept but unused |
| `Themes` | `Theme.themes` |
| `Palette` | `Theme.palette`, live |
| `CurrentTheme` / `CurrentFont` | live getters through `__index` |
| `Debug` | false |

**v1 methods, all kept:**
- `CreateWindow`, `Notify`, `Destroy`;
- `LoadConfiguration`, `SaveConfiguration`, `SetPersistenceReady`;
- `GetFlagValue`, `SetFlagValue`, `GetFlags`, `OnFlagChanged`;
- `GetConfigurationStats`, `DeleteConfiguration`, `ResetConfiguration`;
- `AddTheme`, `GetThemes`, `SetTheme`, `GetColor`, `GetPalette`, `OnThemeChanged`;
- `SetFont`, `GetFonts`, `GetFontLabel`;
- `GetIcon`, `HasIcon`;
- `PruneRegistries` (now a no-op returning zero counts, see §16.3);
- `_fireThemeListeners`.

**Added:**

| Method | Behaviour |
|---|---|
| `CreateTheme(spec)` | Theme generator |
| `SetVisibility(bool)` / `IsVisible()` | Rayfield; act on the last window |
| `Toast(text, type?)` | Small centred pill |
| `GetPerfStats()` | §16.5 |
| Profile methods | §13.3 |
| `SetReducedMotion(bool)` | Library-wide |

**`Argon:Destroy()`:**
1. saves (pcall);
2. destroys every window (scopes, Router entries, ScreenGuis);
3. disconnects the Router;
4. clears the scheduler;
5. clears `Flags`, `_pendingFlags` and the flag listeners in place;
6. removes itself from `Env.genv().__ArgonUI`.

It is idempotent. After it, a new `CreateWindow` works again: v2 has no janitor to restart, so D17 is resolved by construction.

### 14.2 `compat/Aliases`

| Kind | Aliases |
|---|---|
| Tab builders | `CreateX` and `X` for all 19 builders in `api` §4, plus the new ones: `Callout`/`CreateCallout`, `Image`/`CreateImage`, `Stat`/`CreateStat`, `Checkbox`/`CreateCheckbox` (= Toggle with Style Checkbox). `ColorPicker` and `Colorpicker`. |
| Section builders | everything above except `Section`, plus `Row`/`CreateRow` |
| Row builders | everything except `Row` |
| Window | `Popup` = `Dialog`, `SetOverlaysPinned` = `SetOverlaysAlwaysVisible`, `Toggle` / `Open` / `Close` / `ToggleVisibility` |
| Element | `Tooltip` = `SetTooltip`; `SetContent` = `Set` on Label, Paragraph and TelemetryCard; `Button:Set` = `SetTitle`; `Dropdown:SetOptions` = `Refresh`; `Colorpicker` |

The builders are generated from one table, so a new control is added in exactly one place.

### 14.3 `compat/Options` and `compat/Rayfield`: the rules

| Rayfield or v1 usage | v2 rule |
|---|---|
| `ToggleUIKeybind = "K"` / EnumItem / `"Enum.KeyCode.K"` | `Util.keyCode`; an unknown value keeps Insert (D1) |
| `LoadingTitle`, `LoadingSubtitle` | `LoadingScreen = {Title, Subtitle}` |
| `Icon` (window) | `Logo` (a number becomes an asset id) |
| `KeySystem`, `KeySettings` | §12.7 |
| `Discord`, `DisableRayfieldPrompts`, `DisableBuildWarnings`, `ShowText` | accepted and ignored (documented) |
| `PlayerList` / `KeybindList` | default **false** in v2 (§12.4); an explicit value is honoured; prefs override only when present (D2) |
| `CreateTab(name, 4483362458)` | `Icons.resolve(number)` gives a raw image |
| **Keybind** `{Callback}` with no `OnPressed` / `Pressed` / `CallOnChange` | **Rayfield mode.** `Callback()` fires on **press**, with no arguments. With `HoldToInteract`, `Callback(true)` fires on press and `Callback(false)` on release. Rebinds fire `OnChanged(key)` only. **A restore fires nothing** (D3). |
| Keybind with `OnPressed` / `Pressed` | **v1 mode.** `Callback(keyName)` fires on rebind and on restore (v1); `OnPressed(keyName, active)` fires on press |
| Keybind with `CallOnChange = true` | `Callback(keyName)` fires on rebind (Rayfield), and nothing fires on restore |
| `Paragraph:Set({Title, Content})` | supported (D4) |
| `CreateLabel(text, icon, color, ignoreTheme)`, `Label:Set(text, icon, color)` | supported |
| `Section:Set(name)`, `Divider:Set(bool)`, `Button:Set(name)`, `ColorPicker.Color` | supported (D5) |
| `Notify{Image}` | icon (`Icons.resolve`) |
| Rayfield theme names | `Theme.set` resolves through `Palettes.rayfield[name]`, generated on demand. They are not listed in `GetThemes()` unless used. |
| `Window.ModifyTheme(t)` | `Theme.set(Theme.derive(merge(current, t)))` |

### 14.4 Contract defects (`api` §16): decisions

| ID | Decision |
|---|---|
| D1 | **Fix**: string toggle keys normalised |
| D2 | **Fix**: prefs override only when present |
| D3 | **Fix**: keybind modes per §14.3 |
| D4 | **Fix**: `Paragraph:Set` and Label signatures |
| D5 | **Fix**: missing Rayfield methods added |
| D6 | **Fix**: unbind by identity |
| D7 | **Fix**: visibility model (§8.5) |
| D8 | **Fix**: Destroy unregisters the flag (value moved to pending), unbinds Router entries, closes owned popovers, destroys the scope, and removes the element from `row.Elements` |
| D9 | **Keep single configuration**, but clear in place. One configuration per load (last window). Documented. |
| D10 | **Fix**: true with info |
| D11 | **Fix**: watchdog counts from the last progress |
| D12 | **Decided**: Refresh never fires on a dropped selection (Rayfield). Applying a deferred desired option fires the callback **and** listeners and autosave (single commit path). |
| D13 | **Fix**: silent clear |
| D14 | **Fix**: every `Set` returns self |
| D15 | **Fix** Tooltip and Description on display controls. **Keep** `Description` as the content alias on Paragraph and TelemetryCard. |
| D16 | **Fix**: picker persists through Prefs |
| D17 | **Moot**: no janitor |
| D18 | **Fix**: every dismissal calls `OnCancel` |
| D19 | **Fix**: pre-window toast host |
| D23 | **Fix**: custom palette persisted in `Prefs.CustomTheme` and restored |
| D25 | **Fix**: 0-255 without the marker |
| D26 | **Decided**: Lock and Disabled block user paths including hotkeys; programmatic `Set` is allowed |

### 14.5 Behaviour changes v1 users can notice (CHANGELOG, written by WU12)

1. There is no pill loader and no 0.93 s minimum. The card appears only for work over 150 ms, and the window opens when the host's script is done.
2. Overlays (player list and keybind list) are **off by default**.
3. Keybind `Callback` without `OnPressed` now fires on **press** (Rayfield). Scripts that used `Callback` as a rebind listener should switch to `OnChanged` or `CallOnChange = true`.
4. **Escape** no longer clears a keybind during capture; Backspace or Delete do. Escape is not a close key by default (Backspace and gamepad B are).
5. Notification `Type` overrides the title guess. The title guess now matches whole words.
6. Section headers, the subtitle and the loader status are in sentence case. There is no ALL CAPS chrome. "LIVE", "ARGON ONLINE" and "ARGON / TAB" are gone (`Window:SetStatus` restores a status chip if the host wants one).
7. `Dropdown:Set("unknown")` keeps the current selection instead of clearing it.
8. Input fires its callback on Enter even when the text is unchanged. `RemoveTextAfterFocusLost` fires once.
9. Rows no longer pad neighbours to equal height (`_balance` is a no-op).
10. Slider suffixes that are words get a space ("10 Bananas").
11. `PruneRegistries` returns zeros; there is nothing to prune.
12. Library-settings controls are no longer flags. The `ArgonUI*` names still resolve through `GetFlagValue` and `SetFlagValue`.
13. The default window size and the sidebar widths change (220, 200 and a 64 px rail, against 232 and 72).

### 14.6 Internals kept as seams (so tests and power users keep working)

The structure is described in §16.3.

| Object | Seams kept |
|---|---|
| `Argon` | `_windows`, `_pendingFlags`, `_uiPreferences`, `_lastConfigStats`, `_persistenceReady`, `_loadingConfig` |
| Window | `_select`, `_refreshSectionMenu`, `_setJumpRailFiltered` (dot call), `_refreshOverlayVisibility`, `_refreshKeybindOverlay`, `_exportUIPreferences`, `_applyUIPreferences`, `_relayout`, `_loadingProgress`, `_cursorMode`, `_tooltip`, `_visible`, `_toggleKey` (an EnumItem) |
| Tab | `_sections`, `_elements`, `_controlCount`, `_filter` |
| Row | `_balance`, `_relayout` (no-ops) |
| Element | `_description`, `_tooltipText`, `_tipMarker`, `_title`, `_lock`, `_callback` |

All of them are documented as internal and not part of the semver contract.

---

## 15. Build script and icon generator

### 15.1 `build.luau` (WU1): steps

`lune run build.luau [--check] [--debug] [--where <bundleLine>]`

1. **Collect.** Every `src/**/*.luau`, logical name = path relative to `src/` without the extension, with forward slashes. `src/init.luau` is the entry.
2. **Parse requires.** A Luau-aware lexer finds `require("<literal>")`. Non-literal `require` is an error, and so is a missing module. The build computes the dependency graph and rejects cycles (`a -> b -> a`), printing the path.
3. **Lint** (errors), using a token scan that skips strings and comments:
   - forbidden everywhere: `loadstring`, `getfenv`, `setfenv`, the bare legacy globals `wait(`, `delay(` and `spawn(` (a token not preceded by `.` or `:`, so `task.delay` is fine), `GetUserThumbnailAsync`, `GetTextBoundsAsync`, `Instance.new` (outside `core/Factory`), `CanvasGroup`, top-level `...`;
   - forbidden outside an allowlist (`persist/Store` slicing and `feature/KeyGate`): `task.wait`, `:Wait(`, `WaitForChild`, `HttpGet`, `PreloadAsync`;
   - `TextSize =` with a non-integer literal;
   - every core icon literal must exist in `IconData.core` (the generator list).
4. **Strip** (default). A lexer-aware pass removes comments (`--`, `--[[ ]]`, `--[=[ ]=]`) and leading indentation, but **keeps every newline**, so each module's line numbers are unchanged. Long strings are left byte-identical, including the icon `packed` data. Trailing whitespace is removed. `--debug` keeps comments and writes `build/argon-ui.debug.luau` (git-ignored).
5. **Emit**, deterministically: LF line endings, modules in sorted logical-name order, no timestamps.

```lua
--!nocheck
--!optimize 2
-- Argon UI 2.0.0 | generated by build.luau from src/ (sha256 of sources: <64 hex>) | do not edit
-- https://github.com/<owner>/argon-UI | MIT
-- @map core/Env=14 core/Factory=96 core/Motion=171 ... init=4410
local __M, __C, __L = {}, {}, {}
local function __require(name)
	local cached = __C[name]
	if cached ~= nil then return cached end
	local loader = __M[name]
	if loader == nil then error("[Argon UI] internal module missing: " .. tostring(name), 2) end
	if __L[name] then error("[Argon UI] circular require: " .. name, 2) end
	__L[name] = true
	local value = loader(__require)
	__L[name] = nil
	if value == nil then value = true end
	__C[name] = value
	return value
end
__M["core/Env"] = function(require)
<module source, stripped, lines preserved>
end
...
return __require("init")
```

   - The wrapper's parameter is named `require`, so each module's `require("x")` resolves to the shim lexically. There are no globals and no `getfenv`.
   - The `@map` line gives each module's first bundle line. `--where 1234` prints `core/Scope.luau:56`, so errors reported against the bundle (`argon-ui:1234`) can be traced.
   - Modules are evaluated lazily on first `require`, so emission order does not matter at runtime. It is sorted only for byte-determinism.
6. **Verify.**
   - `luau.compile(bundle)` must succeed; report the compile time (median of 5).
   - Load the bundle in the test sandbox and check `Argon.Version == meta.Version`.
   - Fail when the size is over **200 KB**, and warn over 180 KB.
   - Print the size and the share of the 15.8 KB icon data.
7. `--check` regenerates in memory and exits 1 if `argon-ui.luau` differs byte-for-byte (CI and pre-commit). The version comes from `src/meta.luau`.

**Luau limits respected:** each module is one function (≤ 200 locals, enforced by the compile check). The main chunk has 5 locals.

### 15.2 `tools/devload.luau` (WU1)

`devload.load(srcDir, environment)` evaluates `src/` without bundling, using the same `__require` shim and `luau.load` with `environment`. Module unit tests use it to load a single module (for example `core/Scheduler` against a fake clock) with real line numbers.

### 15.3 `tools/gen_icons.luau` (WU2)

`lune run tools/gen_icons.luau --source <path/to/Icons.luau> | --fetch <commit-sha>`

1. **Input.**
   - `--source` reads a local file.
   - `--fetch` uses `@lune/net` against `https://raw.githubusercontent.com/latte-soft/lucide-roblox/<sha>/lib/Icons.luau`. A **pinned commit** is required for reproducibility; the sha is written to the header.
   - Record the sha256 of the input.
2. **Parse without executing.** Pattern-scan `["48px"]={...}` for `name={assetId,{w,h},{x,y}}` entries (as in `bench/v2_icon_encoding.luau`).
   - Assert that every cell is 48x48.
   - Assert there are ≤ 36 sheets and ≤ 36 distinct x and y values. If an axis exceeds 36, switch to two base-36 digits for that axis and bump `format`.
3. **Encode.**
   - Sheets sorted; `xs` and `ys` sorted.
   - `code3 = b36(sheet) .. b36(xIndex) .. b36(yIndex)`.
   - Names sorted bytewise and front-coded (prefix ≤ 35).
   - `packed` is wrapped in `[==[ ]==]`. Assert the data contains no `]==]`.
4. **Core and aliases.**
   - `CORE_NAMES` is the list in §5.5. Each must exist, otherwise the build fails.
   - `ALIASES` combines v1's `LUCIDE_ALIASES` (L391-398) and a curated rename list (for example `alert-triangle -> triangle-alert`, `help-circle -> circle-help`). Every target must exist.
5. **Emit** `src/icons/IconData.luau` with a header naming the generator version, repo, commit, input sha256, icon count and byte sizes.
6. **Self-test.** Decode the output and compare every entry against the parsed input (asset id and offsets). Exit 1 on any mismatch.

### 15.4 Yield and network allowlist (enforced by the lint)

| Module | Allowed call | Why |
|---|---|---|
| `persist/Store` | `task.wait()` only inside `load`, only when `coroutine.isyieldable()` | slicing host restore callbacks (v1 does the same at 45 ms) |
| `feature/KeyGate` | `task.wait`, signal `:Wait()` inside the **opt-in** blocking gate; `HttpGet` inside a spawned thread for `GrabKeyFromSite` | Rayfield semantics; the gate is painted first |

---

## 16. Test strategy (WU12)

### 16.1 Sandbox extensions (`tests/sandbox.luau`)

Each item lists what is added, then why.

1. **Enums.**
   - Added: the full `EasingStyle` (Linear, Sine, Back, Quad, Quart, Quint, Bounce, Elastic, Exponential, Circular, Cubic) and `EasingDirection`; the full `KeyCode` list, including gamepad codes; `UserInputType`, `UserInputState`, `PreferredInput`, `ScreenInsets`, `FontWeight`, `AutomaticSize`, `FillDirection`, `HorizontalAlignment`, `VerticalAlignment`, `UIFlexMode`, `ItemLineAlignment`, `ContextActionPriority`, `ContextActionResult`, `ScaleType`, `SortOrder`, `TextTruncate`, `ResamplerMode`, `ThumbnailType`, `ThumbnailSize`.
   - Added: `sandbox.strictEnums = true`, which makes unknown members **error**, as in Roblox.
   - Why: today `Quart` silently resolves to nil (`api` §17.3).
2. **Class tree.**
   - Added: `IsA` with the real hierarchy (`GuiObject`, `GuiButton`, `TextBox`, `GuiBase2d`, `LayerCollector`, `UIComponent`, `UIConstraint`, `UILayout`).
   - Why: the Popover and Focus code test `IsA("GuiButton")`.
3. **Destroy.**
   - Added: recursive destroy; `Parent` locked afterwards; every connection on the destroyed instances' signals disconnected (`Connected = false`); `Destroying` fired.
   - Why: makes the leak tests real (today's "dead connections" test is vacuous).
4. **Signals.**
   - Added: `Once` really disconnects; `Connection.Connected`; `sandbox.handlerCount(signal)`; `Signal:Wait()` **errors**, recorded in `sandbox.yields`.
   - Why: the idle-handler gates, and the no-yield tripwire.
5. **Task.**
   - Added: `task.defer` is **queued** and flushed at the end of `step`/`advance` and by `sandbox.flushDeferred()`; `task.wait` increments `sandbox.yields` and records the traceback; `coroutine.isyieldable` is supported.
   - Why: real defer semantics, and catching yields on the critical path.
6. **Frames.**
   - Added: `sandbox.step(frames = 1, dt = 1/60)` fires RenderStepped, Stepped and Heartbeat, advances the clock, runs due delays and deferred work. `sandbox.advance(seconds)` steps frames at 1/60 (capped at 600 per call) as well as running delays. `Env._clock` is overridden with the sandbox clock.
   - Why: the Scheduler, springs, the loader 250 ms rule and the drag coalescing.
7. **Layout-lite.**
   - Added: `AbsoluteSize` and `AbsolutePosition` computed from the parent chain (Scale × parent + Offset; AnchorPoint), ignoring AutomaticSize and layouts. ScreenGui `AbsoluteSize` = viewport − 36 px top inset unless `IgnoreGuiInset` or `ScreenInsets ~= CoreUISafeInsets`. `GetPropertyChangedSignal("AbsoluteSize")` fires on `setViewport`.
   - Why: responsive breakpoints and popover clamping become testable.
8. **Tripwires.**
   - Added: `HttpGet` and `HttpGetAsync`, `GetUserThumbnailAsync`, `PreloadAsync` and `loadstring` are counted, and they **raise** when `sandbox.forbidNetwork` is set. `sandbox.metrics()` reports instances created and live (by class), property writes, Color3 writes, tweens (and looping ones), timers, and handlers per global signal.
   - Why: the perf and critical-path gates.
9. **Input simulation.**
   - Added: `sandbox.input.key(code, {ctrl, shift}, gameProcessed)`, `.keyUp`, `.click(guiButton, {button = 1|2})`, `.hover(gui, on)`, `.drag(gui, from, to, steps, {kind = "Mouse"|"Touch", id})`, `.longPress(gui, seconds)`, `.focusTextBox(tb)` / `.typeText(tb, text, enter)`, `sandbox.setPreferredInput(kind)`, `sandbox.setTouch(bool)`.
   - Why: router, focus, drag, tooltip and palette tests.
10. **Services.**
    - Added: `GuiService` (props), `ContextActionService` (Bind, BindActionAtPriority and Unbind are recorded, and `sandbox.cas.bound()` reports them), `TextService:GetTextSize` (0.55 × size × utf8 length by size), `ContentProvider`, Players helpers (`sandbox.addPlayer(id, name)`, `removePlayer`), `setclipboard` capture (`sandbox.clipboard`).
    - Why: overlays, focus and context-menu copy.
11. **Executor profiles.**
    - Added: `sandbox.setExecutor("full"|"none"|"nofs"|"noclipboard"|"syn")`, which adds or removes the fs globals, `getgenv`, `gethui`, `setclipboard`, `syn.*`. `"none"` also makes CoreGui parenting fail, so the code falls back to PlayerGui.
    - Why: "nothing errors when globals are missing".
12. **Compatibility.** The sandbox API stays a superset, so `tests/run.luau` keeps its current helpers (`sandbox.load`, `files`, `advance`, `setViewport`, `environment`).

### 16.2 `tests/run.luau`: what changes and why

`run.luau` stays the **v1 functional contract suite**. Most groups keep their assertions; the ones below change. Line ranges are `run.L`.

| Group (lines) | Change | Why |
|---|---|---|
| Version (L44) | `"1.18.3"` becomes `"2.0.0"` | version |
| Dropdown unknown option (L93) | tighten to "ignored, selection kept" | v2 decision (§14.5 item 7); the weak test accepted either |
| Rows: line heights equalised and idempotent; lone control keeps 54 px (L242-275) | replace with "`_balance()` returns the row, no Lua size listeners, holders have UIFlexItem; a lone control keeps `Metrics.rowHeight`" | balancing dropped (§8.9); heights from Metrics |
| Rows: `_relayout` re-entry (L277-296) | keep as "callable, idempotent" | no-op seam |
| State colours: `trackOf` (L316) | keep (the track is still a 44x24 Frame); also accept `Name == "Track"` | the instance changed, the size did not |
| State colours: theme switch polling loop | keep; it passes immediately | switch is synchronous |
| Descriptions: slider natural height 72; "bar is an Active Frame of height 8" (L362-367) | natural height becomes `Metrics.rowHeight("tall")`; look up the `Hit` band (24 px) instead of an 8 px bar | new geometry |
| Tooltips: delay window 0-0.35 s (L476-490) | becomes 0-0.45 s (hover delay 0.4); the marker is found by `Name == "TipMarker"` (an ImageButton), not `Text == "?"` | motion token; text glyphs removed |
| List actions: three buttons in order (L417-438) | keep. `InlineActions` defaults to **3**, so v1 layouts stay inline. Rows are found through `list:_rowView(index)` because rows are pooled. | virtualisation |
| Themes: "10 built-ins" (L781) | "≥ 12, including the 10 v1 names" | Daylight and HighContrast |
| Themes: recoloured control follows the theme (L824) | the expected root colour is the `Hover` token (the row hover fill) | grouped rows have no Surface root |
| Theme picker (L832-887) | path `Window.Content.ThemePicker` becomes `Window.ThemePicker` (lazy). "Swatches show their own palettes" checks the preview bars' `Window`, `Surface` and `Accent` colours instead of 3 dots. The active outline and external restyle are kept. | popover in the Popover layer |
| Active tab theming (L960-991) | "active `IconBox` is Accent" becomes "the active tab icon's ImageColor3 is `Accent`, `ButtonTitle` is `Text`; inactive titles are `Muted`" | shared indicator, no solid accent plate (contrast fix) |
| Text growth: `SetStatus` recolours the stroke (L1024-1030) | becomes "recolours the pill fill tint and text" | the pill has no stroke |
| Notifications: layer parent (L1074) | `Notifications:IsDescendantOf(ScreenGui)` and not of `Main` | Toast layer frame |
| Notifications: toast counting by `CanvasGroup` (L1082-1095) | count children named `Toast` | no CanvasGroups |
| Notifications: plate 32x32 (L1106) | keep | |
| Notifications: cap 5 (L1112) | becomes ≤ 4 visible plus a "+N" chip | spec |
| Typography: section headers use Montserrat; section text upper-cased "LOOK AND FEEL" (L1190-1200) | the page title uses the display face; section headers are the body face in **sentence case** | type scale, no ALL CAPS |
| Loader: pill narrower than 400 (L1251-1259); viewport change does not stretch the pill (L1288-1302) | `window._loader.Card` is narrower than 400 and stays ≤ 360 after `setViewport`; `Main` is **already** at full size while loading | ghost hand-off design |
| Loader: overlays stay behind the cover (L1261-1276) | **fix the vacuous test**: read `held.PlayerListOverlay.Visible == false` while loading | `api` §17.4 |
| Loader: final width 772 at 800 px (L1304-1313) | expected `Metrics.windowDefault(guiSize).X` (768 at an 800 px wide GUI) | new metric |
| Restore progress: "RESTORING CONFIGURATION i/n" (L1335-1345) | pattern becomes `"Restoring settings %d+/%d+"`; still ≥ 12 reports through the monkeypatched `SetLoadingProgress` | sentence case |
| Composition (L1359-1437) | "only CanvasGroup is Glow" and "Mono has no tinted group" become "**no** CanvasGroup anywhere"; Loader is found under the ScreenGui; sidebar widths come from `Metrics`; Main stays a Frame with a UIGradient; SquareEdge is kept | design |
| Rename (L1439-1502) | the subtitle display is no longer upper-cased; "settings registers `ArgonUIWindowTitle`... flags" becomes "`GetFlagValue("ArgonUIWindowTitle")` returns the pref and `Argon.Flags.ArgonUIWindowTitle == nil`" | prefs single source (CB-02) |
| Registry pruning (L1541-1596) | **replace**: "12 toasts dismissed leave live scopes, instances and connections at their baseline (`GetPerfStats`)"; "`PruneRegistries()` returns zero counts"; "no periodic timers pending after 31 s" | no global registries, no janitor |
| All other groups | unchanged | contract |

### 16.3 Internals the tests touch, and how v2 serves them

| Internal (`api` §17.2) | v2 |
|---|---|
| `Argon.Version`, `DefaultFolder`, `Themes.<T>.<K>`, `CurrentTheme`, `CurrentFont`, `Flags.<f>` (identity) | kept |
| `Argon._pendingFlags`, `_windows`, `_lastConfigStats`, `_uiPreferences` (assignable before `CreateWindow`) | kept: `Store.pending`, the window list, Store stats, `Prefs.table` |
| `Argon._themeBindings`, `_connections`, `_lastPruneStats`, `PruneRegistries` | `_themeBindings` and `_connections` are **empty tables** (never grow); `PruneRegistries` returns zeros; tests move to `GetPerfStats()` |
| Window `ScreenGui`, `Main`, `Sidebar`, `Content`, `Content.TopBar.ThemeButton`, `Content.JumpRail`, `TopBar`, `Notifications`, overlays, `CursorGui`, `Tabs`, `ActiveTab` | kept as fields (lazy view fields for shell parts) |
| `Content.ThemePicker.ThemeOptions.<Name>` | moved: `Window.ThemePicker.ThemeOptions.<Name>` |
| `_tooltip`, `_loadingProgress`, `_cursorMode`, `_select`, `_refreshSectionMenu`, `_exportUIPreferences`, `_applyUIPreferences`, `SetLoadingProgress` as a monkeypatchable method | kept (§14.6) |
| Tab `_sections[i].Elements`, `_controlCount`, `_filter`, `IconBox`, `ButtonTitle`, `Page`, `PageGroup` | kept; `IconBox` is the icon holder Frame (transparent) |
| Row `Columns[i].Holder`, `Root`, `_balance`, `_relayout`, holder `LayoutOrder`, `element.Root.Parent == holder` | kept |
| Element `Root`, `_description`, `_tooltipText`, `_tipMarker`, `_title`, `_lock.{Root,Badge,Icon}`, `HasTooltip`, `Locked`, `LockReason`, `Type`, `CurrentValue`, `CurrentOption`, `CurrentKeybind`, `Items`, `Status` | kept |
| Pinned geometry: toggle 44x24 (kept); toggle row 54 (becomes 44); slider 72 (becomes tall); list rows 44 (kept); plate 32 (kept); sidebar 232/72 (becomes Metrics); shell 772 (becomes Metrics); pill < 400 (becomes the card) | changed tests read `Metrics` instead of literals |

### 16.4 New suites (each runs in its own `lune` process; `tests/run_all.luau` aggregates)

| Suite | Covers |
|---|---|
| `tests/compat.luau` | Every row of `api` §15 and §14.3: string toggle key; Rayfield keybind press, hold and restore semantics; `Paragraph:Set` with a table; Label args; `Section:Set`; `Divider:Set`; `Button:Set`; `.Color`; `Argon:SetVisibility` / `IsVisible`; numeric tab icon; `LoadingTitle`; Notify `Image`; Rayfield theme names; a Rayfield `.rfld` with 0-255 colours; every v1 alias resolves; every v1 window and element method exists |
| `tests/lazy.luau` | `Create*` makes 0 instances; `Set`/`Get`/`Lock`/`SetVisible`/`OnChanged`/flags before mount; `el.Root` forces a mount of that element only; the active tab mounts first; hidden tabs are detached (`PageGroup.Parent == nil`); a cold tab switch mounts the viewport synchronously; Destroy before mount; a theme switch with unmounted or hidden tabs catches up on show; search finds unmounted controls; `VisibleWhen` / `EnabledWhen` |
| `tests/input.luau` | 1 InputBegan handler at idle for 1 and for 5 windows and executions; keybind Press / Toggle / Hold; locked and destroyed binds never fire; toggle key rebinding and Prefs.MenuKey; close-key chain order; Escape not bound by default; drag follows only its own touch input; slider callback ≤ 1 per frame plus one `OnRelease`; focus Up/Down/Left/Right/Enter; CAS bound only in focus mode; gamepad map |
| `tests/layers.luau` | One popover open at a time; the previous owner's state is reset (the `controlsA` chevron bug); outside click; flip and clamp inside a 800x600 GUI; following the anchor; pooling (0 instances on reopen); dropdown with 10k options (≤ 40 instances, filter ≤ 0.5 ms); the colour picker leaks no handlers over 50 opens; tooltip singleton; dialog dismiss paths all call `OnCancel`; z-order of layers |
| `tests/persist.luau` | A v1 file loads unchanged; v2 writes a v1-readable file; prefs applied before the first instance (title and theme on the loader); D2, D6, D10, D25; profiles CRUD, autoload, rename and delete; export → import round trip; import of a Rayfield file; legacy `ArgonUI*` folding; meta file; executor profile `"none"` (no fs) produces no errors and no writes |
| `tests/loader.luau` | Ready within 150 ms means no card; card shown means ≥ 400 ms; idle 250 ms rule; host-thread-dead rule; manual mode; watchdog from the last progress (D11); stall prompt at 8 s; restore mapping 85-100 %; **0 network or yields before the first loader frame** (tripwires on); hand-off leaves no card or ghost instances behind |
| `tests/theme.luau` | All built-ins meet the §5.2 targets; `AddTheme` partial derivation; `CreateTheme` light and dark meet the targets; `SetTheme(table)` persists as `CustomTheme`; the switch repaints on-screen components only (count paints); 0 global bindings; fonts switch through the same path |
| `tests/perf.luau` | The budget gates of §1.3 on the `perf_workload` mix (10x40) and on 500/1,200 scaling; counts exact, times at 1.5x |
| `tests/build.luau` | `build.luau --check` passes; the lint catches a planted forbidden call (fixture under `tests/fixtures/`); the icon data self-test; every core name resolves; size ≤ 200 KB |

### 16.5 `Argon:GetPerfStats()` (public diagnostics; tests and the owner use the same numbers)

```lua
{
  liveScopes, liveInstances, mountedElements, pendingElements, elements,
  globalHandlers = { InputBegan, InputChanged, InputEnded, Heartbeat, RenderStepped },
  springs, loops, dragSessions, popoversOpen,
  scheduler = { pending, lastSliceMs, maxSliceMs, mode },
  lastThemeSwitchMs, lastMountMs, iconsDecoded, bundleVersion,
}
```

### 16.6 Real-client verification (cannot be done in Lune)

The owner runs `tests/client_bench.luau`, adapted from `bench/shell_client_bench.luau`, in a live client with the MicroProfiler open. It checks:
- the `Argon/mount <tab>` slices are ≤ 4 ms interactive and ≤ 8 ms loading;
- `Argon/theme` is ≤ 4 ms;
- no `Argon/*` label appears at idle;
- the time from `CreateWindow` to first loader paint is under 2 frames;
- text renders crisply at UIScale 1.0, 1.15 and 1.5;
- touch behaviour on a phone: the dock pill reopens the window; the thumbstick does not move the window.

---

## 17. Work breakdown (12 units, disjoint files)

**File rules.**
- Every file under `src/` has exactly one owner.
- Shared interfaces are frozen in this document. A unit that needs an interface change opens a change to this file first, and the owner of the affected module agrees.
- `argon-ui.luau` is generated output. It is committed only by WU11 at the integration milestones.

| ID | Title | Files owned (exclusive) | Depends on | Delivers / acceptance |
|---|---|---|---|---|
| **WU1** | Core runtime, component base, bundler | `build.luau`, `tools/devload.luau`, `src/core/Env.luau`, `src/core/Signal.luau`, `src/core/Scope.luau`, `src/core/Util.luau`, `src/core/Token.luau`, `src/core/Factory.luau`, `src/core/Scheduler.luau`, `src/core/Motion.luau`, `src/component/Component.luau` | none | §4 and §15.1-15.2 exactly. Unit tests through devload: Scope destroy order; Scheduler budget, priorities, flush and Heartbeat disconnect when drained; Motion reduced mode and a single spring connection; Factory token recording with no inference. `build.luau` emits a deterministic bundle, `--check`, lint and `@map`. |
| **WU2** | Theme engine, fonts, metrics, icons, icon generator | `src/theme/Color.luau`, `src/theme/Palettes.luau`, `src/theme/Theme.luau`, `src/theme/Fonts.luau`, `src/theme/Metrics.luau`, `src/icons/Icons.luau`, `src/icons/IconData.luau` (generated), `tools/gen_icons.luau` | WU1 (Signal, Token) | §5. Every built-in passes `validate`. `Theme.create` meets the targets. `IconData` is generated from a pinned commit and self-tested. `Icons.resolve` follows the §5.5 order. The decode is ≤ 2.5 ms (gate) and lazy. |
| **WU3** | Input and layers | `src/input/Platform.luau`, `src/input/Router.luau`, `src/input/Drag.luau`, `src/input/Focus.luau`, `src/layers/Layers.luau`, `src/layers/Popover.luau`, `src/layers/Tooltip.luau`, `src/layers/VirtualList.luau`, `src/layers/ContextMenu.luau` | WU1, WU2 | §6 and §7. Idle handlers 0/1/0. Close-key chain. Touch drag tracks its own InputObject. Popover rules 1-7 plus pooling. VirtualList holds ≤ visible+4 rows for 10k items. Focus ring and CAS sink only in focus mode. |
| **WU4** | Persistence | `src/persist/FS.luau`, `src/persist/Codec.luau`, `src/persist/Store.luau`, `src/persist/Prefs.luau`, `src/persist/Profiles.luau` | WU1 | §13. Byte-compatible v1 files. D2, D6, D8 (unregister), D10, D25. Profiles, export/import, meta, virtual flags, legacy folding. The restore slices at 8 ms only when yieldable. Works with no fs at all. |
| **WU5** | Element base and containers | `src/component/Element.luau`, `src/component/RowView.luau`, `src/container/Tab.luau`, `src/container/Section.luau`, `src/container/Row.luau`, `src/container/Registry.luau` | WU1-WU4 | §8 and §9.1-9.3. `Element.define` contract; view-field proxy; visibility model; commit path; Lock and Disabled; context menu; tooltip and description; the Tab mount job with detached pages; Section collapse; Row flex; search index ≤ 2 ms for 2k elements; VisibleWhen and EnabledWhen. Ships **one reference control** (a minimal Toggle in a test fixture) so WU7-WU9 can start. |
| **WU6** | Window, shell, loader, dock, cursor | `src/shell/Window.luau`, `src/shell/Shell.luau`, `src/shell/Loader.luau`, `src/shell/Dock.luau`, `src/shell/Cursor.luau` | WU1-WU5 | §10. `CreateWindow` ≤ 3 ms and ≤ 30 instances with no yields; re-execution destroys the previous same-name window; prefs before the first instance; loader rules and hand-off; breakpoints and phone sheet; dock and open button; mouse unlock; cursor driver only when needed; the v1 window API and seams. |
| **WU7** | Controls A | `src/controls/Button.luau`, `src/controls/Toggle.luau`, `src/controls/Slider.luau`, `src/controls/Stepper.luau`, `src/controls/Segmented.luau`, `src/controls/Keybind.luau` | WU5 (WU3 Drag and Router) | §11 rows for these controls. v1 semantics and formats. Keybind modes (D3). Instance budgets in §8.8. Keyboard and gamepad adjust and activate. |
| **WU8** | Controls B (text and popover controls) | `src/controls/Input.luau`, `src/controls/TextArea.luau`, `src/controls/Dropdown.luau`, `src/controls/ColorPicker.luau` | WU5, WU3 (Popover, VirtualList) | §11 rows. Dropdown virtualised and pooled (≤ 2 ms open, 0 instances on reopen); ColorPicker with no leaks, alpha, presets and recents; Input D13 and validation; TextArea scrolling and AutoGrow. |
| **WU9** | Display blocks and List | `src/display/Label.luau`, `src/display/Paragraph.luau`, `src/display/TelemetryCard.luau`, `src/display/Divider.luau`, `src/display/Space.luau`, `src/display/ProgressBar.luau`, `src/display/List.luau`, `src/display/Callout.luau`, `src/display/Image.luau` | WU5, WU3 (VirtualList, ContextMenu) | §11 rows. D4, D5 and D15. List keyed, virtual, with `AddItem` ≤ 0.3 ms and `SetItems(200)` ≤ 5 ms. Stat variant. Callout and Image. |
| **WU10** | Notifications, dialogs, palette, overlays, settings, theme picker, key gate | `src/feature/Toast.luau`, `src/feature/Dialog.luau`, `src/feature/Palette.luau`, `src/feature/Overlays.luau`, `src/feature/Settings.luau`, `src/feature/ThemePicker.luau`, `src/feature/KeyGate.luau` | WU3, WU4, WU5, WU6 | §12. Typed, pooled and updatable toasts plus the pre-window host; dialogs with every dismissal calling `OnCancel`; Prompt; command palette over the Registry; keyed overlays (rbxthumb, idle when disabled); settings as views over Prefs plus the config manager; the theme picker built once; the key gate opt-in and blocking per §12.7. |
| **WU11** | Facade, compatibility, integration | `src/init.luau`, `src/meta.luau`, `src/compat/Options.luau`, `src/compat/Rayfield.luau`, `src/compat/Aliases.luau`, and commits of the generated `argon-ui.luau` | all (stubs from day 1) | §14. The Argon table with every v1 member; option normalisation; Rayfield rules; aliases generated from one table; `GetPerfStats`; `Destroy`; re-execution registry in `getgenv`. Integration: `lune run build.luau && lune run tests/run_all.luau` is green. |
| **WU12** | Sandbox, tests, perf gates, docs | `tests/sandbox.luau`, `tests/run.luau`, `tests/run_all.luau`, `tests/compat.luau`, `tests/lazy.luau`, `tests/input.luau`, `tests/layers.luau`, `tests/persist.luau`, `tests/loader.luau`, `tests/theme.luau`, `tests/perf.luau`, `tests/build.luau`, `tests/client_bench.luau`, `tests/fixtures/**`, `tests/README.md`, `README.md`, `CHANGELOG.md`, `docs/index.html`, `docs/preview.html`, `argon-ui-preview.html` | none to start (writes against this spec); final runs need all | §16. Sandbox extensions first (week 1), so every unit can test. `run.luau` edits per §16.2. New suites. Perf gates. README (BuilderSans doc drift fixed; Rayfield compatibility table; the "Loading a big interface" section rewritten); CHANGELOG (§14.5); docs and preview restyled to v2 tokens, keeping keyboard parity with the library. |

### 17.1 Milestones and integration order

| Milestone | Work | Notes |
|---|---|---|
| **M0** (days 1-3) | WU1 core and build; WU12 sandbox extensions | WU11 lands a stub `init.luau` so the bundle builds from day 1 |
| **M1** (days 3-8) | WU2, WU3 and WU4 in parallel against WU1 | WU5 starts on `Element` and `RowView` with stubbed Theme and Store |
| **M2** (days 6-12) | WU5 complete with the reference Toggle; WU6 window and loader | First end-to-end: `CreateWindow` → `CreateTab` → `CreateToggle` → mount → theme switch → save and load |
| **M3** (days 10-18) | WU7, WU8, WU9 and WU10 in parallel | |
| **M4** (days 16-22) | WU11 integration | `run.luau` at the §16.2 deltas, all new suites green, perf gates green, `build --check` clean, README and CHANGELOG, real-client checklist (§16.6) run by the owner |

### 17.2 Interface freeze points

Each of these is a contract. A change needs this document updated first.

| Interface | Owner |
|---|---|
| `Element.define` spec (§8.3) | WU5 |
| `RowView` (§8.8) | WU5 |
| `PopoverSpec` (§7.3) | WU3 |
| `KeyEntry` (§6.1) | WU3 |
| `DragHandlers` (§6.2) | WU3 |
| `VirtualListSpec` (§7.5) | WU3 |
| `Store` (§13.2) | WU4 |
| `Prefs` keys (§13.4) | WU4 |
| `Token` names (§5.1) | WU2 |
| `Scope` (§4.3) | WU1 |
| `Scheduler.Job` (§4.6) | WU1 |
| `Motion` tokens (§4.7) | WU1 |
| `Layers` names and z-order (§7.1) | WU3 |
| `MountCtx` (§4.8) | WU1 |

---

## 18. Open questions for the owner (defaults chosen; say if you want them changed)

1. **Overlays default to off** (player and keybind lists). Default: off, which is a behaviour change. The alternative is to keep them on, as in v1.
2. **Close key.** Default: Backspace and gamepad B. Escape is not bound, because Esc opens Roblox's menu. The alternative is to also bind Escape.
3. **Key gate blocking `CreateWindow`.** Default: block, as Rayfield does, and only when the host opts in with `KeySystem = true`.
4. **Gamepad toggle.** Default: none unless the host sets one. The alternative is to hold ButtonSelect for 0.4 s by default.
5. **Default typeface.** Default: Roboto body plus Montserrat display, as the code has it today, with the README fixed. The alternative is BuilderSans throughout.
6. **Phone layout.** Default: a full-screen sheet with a top tab strip in 2.0. The alternative is the icon rail only in 2.0, with the sheet in 2.1.
7. **Inline list actions.** Default: 3 (v1 parity). Market research suggests 2 plus overflow.
