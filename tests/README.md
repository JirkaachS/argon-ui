# Argon UI test suites

Functional tests that run the real `argon-ui.luau` outside Roblox.

`sandbox.luau` implements the slice of the Roblox API the library touches, so the library's own code runs unmodified: instances with a class hierarchy, computed `AbsoluteSize` and `AbsolutePosition`, a recursive `Destroy`, datatypes with their operators, the enums the library reads, signals, a frame-stepped `task` scheduler and `RunService`, tweens, `TextService`, `ContextActionService`, an in-memory executor filesystem and clipboard, JSON, input simulation (keys, pads, clicks, drags, typing), executor profiles (`full`, `none`, `nofs`, `noclipboard`), network counters and instance metrics.

## Running

Install [Lune](https://github.com/lune-org/lune) (0.8 or later), then from the repository root:

```sh
lune run tests/run_all.luau
```

That first checks that `argon-ui.luau` is what `src/` builds to, then runs every suite, each in its own process. To test another bundle, pass its path: `lune run tests/run_all.luau -- path/to/bundle.luau` (each suite also takes the path the same way). Every suite exits non-zero when anything fails.

| Suite | What it covers |
| --- | --- |
| `run.luau` | The 1.x contract: every control, values, rounding, clamping and callbacks; sections, rows and builders; element helpers; the configuration round-trip, verified writes, deferred flags, autosave timing; themes and the picker; notifications; dialogs; the library settings tab; overlays; the loader; window controls; warnings and handler errors. |
| `v2_core.luau` | Loading does nothing slow; `CreateWindow` instance and yield budgets; lazy mounting and the scheduler; the loader's quiet rule; idle cost; theme contrast, derivation, accents; the input router and keybinds; the row context menu; change tracking and undo; palette search; `VisibleWhen`; profiles, export and import; notifications and the inbox; dialogs and prompts; the phone tab bar; re-execution and teardown; running with no executor functions. |
| `controls_a.luau` | Button, ButtonGroup, Slider, Stepper, Segmented and Keybind: behaviour, keyboard and pad paths, locks, and instance budgets. |
| `controls_b.luau` | Input, TextArea, Dropdown and ColorPicker: behaviour, popovers, persistence formats, and instance budgets. |
| `display.luau` | Label, Paragraph, TelemetryCard and Stat, Divider, Space, ProgressBar, List, Callout and Image. |
| `readme.luau` | Runs every `luau` example in the top-level `README.md`, so the documentation cannot drift from the API. |

## Where 2.0 changed a 1.x assertion

`run.luau` keeps every 1.x behaviour test. Where 2.0 deliberately changes a pinned pixel value, colour or wording, the assertion was updated and marked with a `-- v2:` comment that gives the reason:

- `Dropdown:Set` with an unknown option keeps the current selection (1.x cleared it).
- Rows lay out with engine flex (`UIFlexItem` and wrapping), so there is no Lua balancing pass; `_balance()` and `_relayout()` return the row. Controls in a row no longer pad each other to equal height.
- A row has no fill of its own; its root carries the `Hover` token (the hover fill).
- The off switch track uses the `Track` token instead of the input well colour.
- A row is 44 px tall without a description and grows with one; the description sits in the text column, left of the control, instead of under it.
- The tooltip hover delay is 0.40 s, and the tooltip marker is an info glyph (an `ImageButton` named `TipMarker`) instead of a `?` text glyph.
- `GetThemes` also lists `Daylight` and `HighContrast`.
- The theme picker lives in the popover layer; `Window.ThemePicker` is its content frame. The theme button sits in the topbar's Actions group, so the tests find it recursively.
- The keybind list sizes to its content and hides when there are no binds, so the overlay test gives it one.
- The active tab is marked by one shared indicator (a glass pill and a 3 px bar with the accent gradient) instead of per-tab accents.
- Toast cards are plain frames named `Toast`, and the status colour is on the type icon.
- Sentence case everywhere: the settings heading, the loader status ("n of m"), the subtitle as given.
- The loader has no fixed timers: the loader block was rewritten around the quiet rule, manual mode, overlays hidden while loading, and the card size.
- The overlay check reads the overlays themselves (the 1.x test looked for names nothing had, so it could not fail).
- The default window width follows `max(min(gui - 160, 1080), min(720, gui - 16))`: 720 at an 800 px GUI.
- The narrow layout is a 64 px icon rail.
- No `CanvasGroup` anywhere (glows are pooled images, fades use one veil frame).
- The library settings rows are views over the window preferences instead of flags; the 1.x `ArgonUI*` flag names still read and write through `GetFlagValue` and `SetFlagValue`.
- There are no global registries to prune: `PruneRegistries` returns zero counts, and the registry checks became "transient UI leaves nothing behind". Notification cards are pooled, so the leak check fills the pool once and then requires a second burst to add nothing.

## Limits

The sandbox models the API surface and simple layout, not rendering. Text metrics are approximate, and `UIListLayout`, `UIFlexItem` and automatic sizing are not simulated, so pixel positions inside lists are not checked. Visual behaviour, tweens and real input still need a Roblox client.
