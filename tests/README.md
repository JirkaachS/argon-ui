# Argon UI test suite

A functional test suite that runs the real `argon-ui.luau` outside Roblox.

`sandbox.luau` implements the small slice of the Roblox API the library touches
(instances, datatypes, enums, signals, a deterministic `task` scheduler, an
in-memory executor filesystem, and JSON), so the library's actual control logic and
persistence code execute unmodified.

## Running

Install [Lune](https://github.com/lune-org/lune), then from the repository root:

```sh
lune run tests/run.luau
```

The suite exits non-zero when anything fails.

## Coverage

- Library load, version, and neutral standalone defaults
- Window, tab, and section creation, including a custom `GuiName`
- All 18 controls, their values, rounding, clamping, and callbacks
- The newer components: `ProgressBar`, `Stepper`, `Segmented`, `TextArea`, `List`
- Section builders exposing every component
- Element helpers: `SetDesc`, `SetTooltip`, `Lock`, `Unlock`, `SetVisible`, `Destroy`
- Configuration save/load round-trip and verified writes
- Callbacks firing on restore even when a value equals the control default
- Pending flags for controls created after loading, and orphan values surviving a save
- Dropdown selections restoring once their options appear
- `SetFlagValue`, `GetFlags`, `OnFlagChanged`, `GetConfigurationStats`
- `ResetConfiguration` and `DeleteConfiguration`
- Custom file extensions not being double-appended
- Debounced autosave, and autosave enabling itself without `LoadConfiguration`
- Themes, notifications, dialogs, the library settings tab, and window controls
- No unexpected warnings or signal handler errors

## Limits

The sandbox models API surface, not rendering. Layout, tweening, input, and visual
behavior still need a real Roblox client.
