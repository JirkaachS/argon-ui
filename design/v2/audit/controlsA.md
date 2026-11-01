# Argon UI v1.18.3 — interactive controls audit (controlsA)

Scope: Button, Toggle, Slider, Input, TextArea, Keybind, Dropdown (single, multi, search, popup), ColorPicker, Stepper, Segmented, plus the shared element base (`base()` 1944-2247: SetDesc, Lock, SetTooltip, SetVisible, Destroy) and the helpers they lean on (`safeCall` 157, `hover` 787, `changed` 831, `create` 275).
All line numbers refer to `argon-ui.luau` (v1.18.3).

Evidence: besides reading the code, I ran three probes against the real library in the Lune sandbox (copied, not modified):

- `bench/controlsA_probe.luau` (output: `controlsA_probe.out.txt` next to it)
- `bench/controlsA_probe2.luau` (keybind overlay cost, applied text sizes)
- `bench/controlsA_probe3.luau` (multi-select highlight)

Run any of them with `lune run <path>`. The sandbox models the API, not rendering, so the probes back up counts, state and logic. Anything about how things look or feel to touch is from reading the code, and I say so where it matters.

---

## 0. Summary

The controls work for mouse users on desktop who never resize, scroll or rebind anything. Past that they fall apart in three ways:

1. **Correctness bugs that users will hit**:
   - Hidden controls come back on every tab switch.
   - Destroyed keybinds keep firing.
   - Rayfield-style keybind callbacks never run.
   - The colour picker leaks two global input handlers every time it opens.
   - Dropdown popups get stuck or open off-screen, and the multi-select highlight inverts.
   - Typing a hex code desyncs the colour picker.
   - `RemoveTextAfterFocusLost` fires the callback a second time with `""`.
   - TextArea can't scroll.
   - A reversed Range crashes the constructor.
2. **No interaction model beyond the mouse**:
   - No keyboard focus, Tab, arrows, Enter or Escape, and nothing deliberate for gamepad.
   - Hover is the only state, and it sticks on touch.
   - Hit targets of 8 px (slider track), 13 px (hue strip), 20 px (clear button) and 24-26 px (stepper, segmented).
   - The docs preview (`argon-ui-preview.html`) has slider arrow keys, Escape-to-close, outside-click close and focus rings. The Luau library has none of these, so the docs promise more than the library does.
3. **Per-interaction cost**:
   - Every drag step runs the user callback, a stroke tween, two `task.delay` timers and an autosave reschedule.
   - Dropdown popups are rebuilt from scratch on every open: 1,566 instances, 1,502 connections and about 1,000 theme bindings for 500 options.
   - Each Slider adds 2 permanent global `UserInputService` handlers and each Keybind adds 1.

Visually the controls are clean but flat and small:

- Value text is 10-11 px. The probe found TextBox/TextButton sizes of 10, 10, 10, 11 and 11.5 on Slider, Keybind, Segmented, Stepper and Input.
- The off-state toggle track and the slider groove sit at a 1.05-1.13:1 contrast ratio against the row in all 10 themes.
- No control has a pressed, focus, loading, error or success state.

---

## 1. Shared element base (base() 1944-2247, helpers)

### Anatomy
- Every control is a `Frame` row: Surface at transparency .08, 10 px corner, BorderSoft stroke, and `ClipsDescendants=true` (1946).
- The row clips its children, so a focus ring or glow drawn outside the row would be cut off. Popups get round this by parenting to the ScreenGui.

### Probe numbers (P1)

| Control | Instances | Theme bindings | Connections | Global UIS handlers |
| --- | --- | --- | --- | --- |
| Button | 7 | 5 | 3 | 0 |
| Toggle | 9 | 3 | 3 | 0 |
| Slider | 16 | 10 | 6 | **2** |
| Input | 15 | 8 | 5 | 0 |
| TextArea | 8 | 7 | 2 | 0 |
| Keybind | 8 | 6 | 4 | **1** |
| Dropdown (closed) | 20 | 10 | 1 | 0 |
| ColorPicker (closed) | 8 | 4 | 1 | 0 (+2 leaked per open) |
| Stepper | 12 | 10 | 9 | 0 |
| Segmented (3 options) | 14 | 4 | 3 | 0 |
| Toggle with Description and Tooltip | 12 | 6 | 9 | 0 |

### Bugs

- **SetVisible is overwritten by search and tab switches.**
  - `element:SetVisible` (1948) writes `Root.Visible` directly.
  - `tab:_filter` (1736) writes `element.Root.Visible = match` for every element, and `_select` calls `tab:_filter("")` on every tab switch (1690).
  - So any control hidden with `SetVisible(false)` reappears as soon as the user switches tabs or clears the search box. The probe confirmed this: after `SetVisible(false)` and a switch to another tab and back, `Visible` is true again.
  - v2: track the user's visibility (`_userHidden`) separately from the filter result (`_filterHidden`), and set `Visible = not (userHidden or filterHidden)`.
- **Destroy leaks.**
  - `element:Destroy` (2225-2231) destroys the Root and removes the element from the section and tab lists. It does not disconnect anything the element connected:
    - the Slider's `UserInputService` InputChanged and InputEnded handlers (2346-2347)
    - the Keybind's `UserInputService.InputBegan` handler (2435), which keeps firing (see Keybind)
    - the hover and description closures
  - It also leaves `Argon.Flags[flag]` pointing at the dead element. In the probe, `GetFlagValue("Doomed")` still returned the destroyed toggle's value, and SaveConfiguration keeps saving it.
  - It does not close a popup the element owns.
  - The probe destroyed a slider and released 0 of its 2 global handlers.
  - v2: give each element a Maid/Janitor, so every connection, tween and popup it owns is released on Destroy, and unregister its flag (moving the value to `_pendingFlags` if it should survive).
- **Lock is only visual.**
  - `Lock` (2035-2100) lays an Active TextButton scrim (ZIndex 28) over the row.
  - It does not stop the following, all confirmed in the probe or by reading:
    - the Keybind still fires `OnPressed` while locked (probe)
    - a popup that was already open stays usable
    - `Set` from code still runs
    - `GuiObject.InputBegan` on Frames such as the slider bar is not guarded in code; whether the scrim swallows it should be checked in Studio
  - v2: gate input in code (`if self.Locked then return end` in every handler), set `Interactable=false` where available, and close popups the element owns on Lock. Add a separate `SetDisabled` (greyed, no badge) next to `Lock(reason)`.
- **Set return values are inconsistent.**
  - Toggle, Slider, Keybind, Dropdown and ColorPicker `Set` return nothing.
  - Input, TextArea, Stepper and Segmented return self (probe P7).
  - So chaining works on some controls and not others.
- **Callback errors are silent and have no context.**
  - `safeCall` (157-161) warns `"[Argon UI] Callback error: ..."` without the control name or flag, and with no traceback, because it uses `pcall` rather than `xpcall`.
  - The control has already committed the new value, so the UI shows a state the feature failed to apply.
  - v2: use `xpcall(debug.traceback)`, put the element name and flag in the warning, flash the row's stroke Danger, add a small "!" badge with the error as its tooltip, and allow an opt-in `RevertOnError`.
- **changed() runs on every value step, including every drag move.**
  - `changed` (831-838) tweens the stroke to Accent and queues a `task.delay(.25)` to fade it back.
  - `scheduleSave` (769-779) queues another `task.delay(.35)` each time.
  - The probe measured 120 tweens and 240 queued delays for 120 drag moves (see Slider).
  - v2: flash on commit only, and coalesce saves to the end of a drag.
- **hover() is mouse-only and stale.**
  - `hover` (787-797) tweens on MouseEnter and MouseLeave. On touch, MouseEnter fires on tap and MouseLeave often doesn't fire, so rows stay highlighted (known Roblox behaviour; not reproduced in the sandbox).
  - There is no pressed state anywhere except the Button's post-click flash.
  - The `normal` colour is a snapshot taken at hover-bind time. That is what breaks the multi-select highlight (see Dropdown).
  - v2: one state machine per interactive surface (rest, hover, pressed, focused, disabled), driven by InputBegan and InputEnded with an input-type check, that reads tokens live.
- **Tooltips are hover-only.**
  - `SetTooltip` (2112-2223) opens on `root.MouseEnter`, so touch and gamepad users never see it. The README admits this.
  - v2: long-press (about 450 ms) opens it on touch, gamepad selection opens it after a delay, and the "?" marker becomes tappable.
- **Small text.**
  - `create()` passes `TextSize` through raw, and only `text()` applies `readableSize`.
  - Interactive values therefore render at 10 px on the Slider value, Keybind pill, Segmented buttons and Dropdown options, and at 11-11.5 px on the Stepper, Input and TextArea (probe 2).
  - 11.5 is also not a whole-pixel size.
  - v2: 13 px values, 14 px titles, 12 px helper text, and whole numbers only.

### What is missing for top tier (applies to every control)

- **Keyboard focus model.**
  - Nothing in the file handles `KeyCode.Tab`, `Return`, arrow keys or `Escape` for controls. The only keys handled are the toggle key and `/` (3095-3099).
  - There is no focus ring, and nothing is reachable without a mouse.
  - v2: a focus manager per window.
    - Tab and Shift+Tab move through the focusable controls in the active tab, but only while the window has focus, because Roblox uses Tab for the player list.
    - Focus shows as a 2 px Accent ring plus a soft outer glow.
    - Enter or Space activates; arrow keys, Home and End adjust; Escape cancels or closes.
- **Gamepad.**
  - No `SelectionImageObject` and no `NextSelection` wiring.
  - Sliders, the SV square and the hue strip are Frames, so the gamepad can't select or adjust them.
  - Keybinds reject anything that isn't `UserInputType.Keyboard` (2436).
  - v2: a themed selection ring, ordered NextSelection, D-pad left and right to adjust the selected slider, stepper or segmented control, A to activate, and B to close a popup.
- **Context menu.**
  - Right-click, or a 500 ms long-press, on any row gives: Reset to default, Copy value, Paste value, Copy flag, and Bind key (for toggles and buttons).
  - "Default" means the config value captured at creation. v1 stores none.
  - Copy uses `setclipboard` when it exists, with an internal clipboard as fallback.
- **Uniform API.**
  - `:Get()` and `:Reset()`.
  - `:OnChanged(fn)`, a per-element signal that returns a disconnect handle.
  - `:SetCallback(fn)`, `:SetDisabled(bool)`, and `:SetLoading(bool)` where it applies.
  - `Set` always returns self.

---

## 2. Button (2272-2281)

**Anatomy:** a 50 px row with a 13 px title and a 32x32 accent chip holding a literal `"→"` text glyph (2275). That glyph doesn't come from the Lucide or atlas icon system the README advertises. A full-row transparent TextButton is the hit target (2276), which is good: the whole 50 px row is clickable.

**States:**

- Rest and hover only: row to Hover, chip to filled (2277-2278).
- No pressed state. The Active flash runs on `MouseButton1Click` after release (2279), so holding the mouse down shows nothing, and the feedback lands after the fact.
- No focus, disabled (only the Lock scrim), loading, success or error state.

**Behaviour and bugs:**

- The callback runs synchronously inside the click handler with no busy guard. A callback that yields (an HTTP call, `task.wait`) can be clicked again and run concurrently. Rapid double-clicks run it twice.
- Uses `MouseButton1Click` rather than `Activated`, so gamepad and touch activation semantics are left to chance.
- **Rayfield compatibility gap:** there is no `Button:Set(newName)`. The probe found `Set` is nil. Rayfield scripts that rename a button with `Button:Set("...")` error with "attempt to call a nil value". Only `SetTitle` exists.
- Every button looks identical: no variant, no icon, no way to mark a destructive action.

**v2 Button:**

- `Variant`: Primary, Secondary (default, the current look), Ghost, Danger or Subtle.
- `Icon` (a Lucide name) replaces the arrow.
- `Layout`: Row (default) or Inline. Add `Tab:CreateButtonGroup({...})` so 2-4 buttons share one row.
- Pressed state: on `MouseButton1Down`, shrink to 0.98 with a UIScale and darken.
- **Loading state:** the callback runs in `task.spawn`. While it's running the chip shows a spinner and clicks are ignored. A ✓ or ✕ flash for about 1.2 s follows, based on the `xpcall` result. `SetLoading(bool)` covers manual control.
- `Confirm = true` or `{Title, Content}` routes the click through `Window:Confirm`. Optionally `HoldToConfirm = 0.8` gives a press-and-hold fill for destructive actions, which also works well on touch.
- `Cooldown = seconds` shows a draining bar and ignores clicks until it ends.
- New API: `Button:Set(name)` (Rayfield), `:Fire()`, `:SetCallback()`, `:SetVariant()`, `:SetLoading()`.

---

## 3. Toggle (2283-2304)

**Anatomy:** a 54 px row, a 44x24 track and an 18 px knob on the right (2286-2287), with the whole row as the hit target (2288), which is good.

**Visual quality:**

- When off, the track is `C.Input` on a `C.Surface` row with no stroke. That is a **1.05-1.13:1 contrast ratio in all 10 themes** (probe P9), so the off track is effectively invisible and only the grey knob shows.
- When on, the track is Accent and the knob white.
- No knob shadow, no press stretch, and no icon in the knob.

**States:**

- Rest and hover only (`hover(root)` at 2299).
- No pressed, focused, disabled-styled, loading or error state.

**Behaviour:**

- `Set(value)` coerces with `value==true` (2296), so `Set("true")` or `Set(1)` turns the toggle off. Config values are booleans, so that path is safe.
- Rapid clicks each fire the callback, which is acceptable.
- `render(true)` tweens even when the value didn't change.
- The theme repaint handles state correctly (2300-2302).
- `Set` returns nothing.

**v2 Toggle:**

- `Style = "Switch"` (default) or `"Checkbox"`, the checkbox using the Lucide `check` icon. Checkbox mode suits dense lists and 3-4 column rows.
- A visible off track: a dedicated `Track` token, or a BorderSoft stroke at 1.5:1 or better.
- On MouseButton1Down the knob widens by 4 px (iOS-style).
- When on, the knob carries a tiny check, for colour-blind users.
- **Attached keybind:** `Keybind = "F"` puts a mini key pill on the toggle row that flips it. This is the most common pattern in script hubs and today it needs two controls.
- Async callbacks: if the callback returns `false` or errors, revert the toggle with a Danger shake (opt-in).
- Space or Enter toggles when focused; gamepad A toggles.
- `Set` returns self.

---

## 4. Slider (2306-2350)

**Anatomy:**

- A 72 px row with a 13 px title and an editable value box on the right: a TextBox, 59x26, TextSize 10 (2310).
- The track is 8 px tall at y=47 (2315), with an accent fill and a 16 px white handle with a 2 px accent stroke (2316-2317).
- Typing an exact value works: FocusLost parses with a `[-%d%.]+` fallback (2333, 2348).

**Probe P2 results:**

- `Range={100,0}` throws `invalid argument #3 to 'clamp'` at 2320, so the constructor crashes and the whole tab build aborts.
- `Increment=0` gives `CurrentValue = nan`. `(v-min)/0` is infinite, `math.floor(inf) * 0` is NaN, and NaN is then clamped and rendered.
- `Range={0,10}, Increment=3, CurrentValue=10` gives 9. The maximum can never be reached.
- `Suffix="Bananas"` renders `"10Bananas"`. Rayfield renders `"10 Bananas"`, so v1 has no space (2330).
- `Set("abc")` and `Set(5)` both return nothing.
- **A drag of 120 mouse moves produced 120 callbacks, 120 tweens and 240 queued `task.delay` timers** (the `changed()` stroke fade plus the autosave reschedule).
- **The hit area is the 8 px bar** (`bar.InputBegan`, 2345). The handle is 16 px, the row isn't draggable, and the effective touch target is about 8-16 px against a 40 px target.
- `Set(0)` during a drag is overwritten by the next pointer move. Nothing arbitrates between script writes and the user's drag.
- **Any** `MouseButton1` or `Touch` InputEnded anywhere stops the drag (2347). A second finger lifting, or an unrelated touch, ends a mouse drag. The handler doesn't track which InputObject started it.

**From reading the code (Roblox behaviour, not measurable in the sandbox):**

- On touch, `bar.InputBegan` jumps the value immediately (2345). A vertical swipe that starts on a slider changes its value while the user is only scrolling the page.
- The page ScrollingFrame isn't locked during a drag, so vertical finger jitter scrolls the page under the slider.
- Each slider holds 2 permanent global UIS handlers. 100 sliders means 200 Lua calls on **every** mouse move, even when nothing is being dragged.
- The value box has no TextTruncate or ClipsDescendants, so a long value or suffix overflows the 59 px pill.
- Focusing the box doesn't select its text, and Escape doesn't revert.
- No ticks, no min and max labels, no bubble over the thumb while dragging, no fine (Shift) or coarse step, no arrow keys or mouse wheel, no double-click to reset.
- Decimal snapping finds decimals with `tostring(increment):match("%.(%d+)")` (2321). That breaks if the number ever prints in exponent form. Use an explicit `Decimals` option.

**v2 Slider:**

- **Shared drag controller.**
  - One module-level UIS InputChanged and InputEnded pair serves every slider, the SV square, the hue and alpha strips and the overlays.
  - It tracks the starting InputObject (the touch id) and sets `page.ScrollingEnabled=false` while dragging.
  - On touch, the drag only starts after horizontal intent: moved more than 6 px with |dx| > |dy|. A drag that starts on the thumb is allowed immediately.
- **Callbacks.**
  - `Callback` fires at most once per frame, coalesced on Heartbeat.
  - New `OnRelease` (alias `OnCommit`) fires on drag end.
  - Stroke flash and autosave happen on release only.
- **Hit area.** An invisible hit frame of 32 px or more around the track, a 20 px thumb with a 40 px touch halo, and clicking on the track's row band seeks.
- **Value pill.**
  - Click to edit; text is selected on focus; Enter commits, Escape reverts.
  - Invalid input shakes the pill with a Danger stroke.
  - New options `Prefix`, `Suffix` (adds a space unless the suffix starts with `%`), `Decimals` and `Format(value)`.
- **Ticks.** With `Ticks = true`, or automatically when `(max-min)/increment <= 20`. Optional `ShowRange` min and max labels.
- **Thumb.** Grows by 2 px while dragging and shows a value bubble above it.
- **Keyboard.** Arrow keys ±step, Shift ±10 steps, Ctrl for fine (step/10 when `Increment` allows it), PageUp and PageDown ±10%, Home and End. The mouse wheel works while hovered with Shift held, so it doesn't hijack page scroll.
- **Validation.**
  - Swap a reversed Range and warn.
  - Treat `Increment <= 0` as continuous.
  - Snap the last step to `max`.
  - Clamp `CurrentValue`.
- **Range slider:** `CreateRangeSlider`, or `Range=true` with `CurrentValue={a,b}`.
- Double-click the thumb or use the context menu to reset to default.

---

## 5. Input (2352-2412)

**Anatomy:**

- A 74 px row with an 11 px muted title on top.
- A recessed 34 px well (C.Background) holding a TextBox at 11.5 px.
- A 20x20 clear button that **is only visible when the field isn't focused** (2381): you can't clear while typing, which is exactly when you'd want to.

**States:**

- Focus: the stroke turns Accent and the well turns Input (2390-2395). This is the best focus state among the controls.
- No error, valid, disabled, read-only or loading state.

**Probe P3 results:**

- **`RemoveTextAfterFocusLost=true` fires the callback twice: `"hello"`, then `""`** (2400-2401). The `""` call also goes through `changed()`, so an empty string is autosaved. In Rayfield the callback runs once and the box is cleared visually. Any "send message" or "run command" input gets a spurious empty call.
- **The elided display corrupts multi-byte text.** `elide()` (2373-2377) slices by bytes (`#`, `:sub`). A 20-character CJK value displays as invalid UTF-8 (37 bytes), and emoji, Cyrillic or accented names can show broken glyphs.
- `https://a.co` displays as `a.co` even though it fits: the scheme is always stripped (2374).
- The clear button is 20x20, half of the 40 px target.

**From reading the code:**

- The callback only fires on FocusLost. `enterPressed` is ignored, so clicking away commits just as Enter does. There's no cancel or Escape-revert path and no live, debounced `OnChanged` mode.
- No `MaxLength`, character counter, numeric mode, password or masked mode, validation, prefix or suffix, or copy button (for webhooks and IDs, where `setclipboard` exists).
- `Set` while the user is typing overwrites their text in place (`refresh()` writes `input.Text` while `editing` is true).

**v2 Input:**

- **Commit and change.** `Callback` commits on Enter or blur, as today. New `OnChanged(text)` is debounced at 150 ms. Escape reverts to the last committed value.
- **`RemoveTextAfterFocusLost`** calls the callback once, then clears silently. This is a compat fix.
- **Clear button.** Visible whenever there is text (focused or not), with a 28 px hit area. **Copy** with `Copy = true`. A prefix icon with `Icon = "link"`.
- **Typed modes:**
  - `Numeric = true` with `Min`, `Max` and `Decimals`: rejects non-numeric keystrokes and offers up and down arrow keys.
  - `Masked = true` shows the text as dots, with a reveal eye.
  - `MaxLength` shows a `12/32` counter in the corner.
- **Validation.** `Validate = function(text) return ok, message end` gives a Danger stroke plus helper text under the field, and the commit is refused while invalid.
- **Suggestions.** `Suggestions = function(text) return {...} end` opens an autocomplete popover, for example for player names, built on the shared popover from the Dropdown section.
- **Elide.** Slice by UTF-8 codepoints (`utf8.offset`), keep the scheme when the value fits, and allow `Elide = false`.
- **Set during editing.** Defer it until blur, or apply it and keep the caret position.

---

## 6. TextArea (2754-2779)

**Anatomy:** a row of 72-320 px (default 104) holding a well (`C.Input`, not the `C.Background` used by Input, so the two are inconsistent) and a multi-line TextBox at 11 px.

**Bugs and gaps (from reading the code):**

- **It can't scroll.**
  - The well is a clipping Frame (2759) and the TextBox has a fixed size with TextWrapped and Top alignment (2761).
  - Text past roughly 4 lines at the default height is clipped, and the caret moves out of view, so you type blind.
  - Nothing grows the box and there is no ScrollingFrame.
- **The focus ring isn't theme-aware.** Focus only tweens the stroke (2774). The stroke's Color binding is still registered as BorderSoft, so switching theme while focused paints over the focus ring.
- **No focus background change**, unlike Input.
- **`Set` overwrites text while the user is typing.**
- **Commit only on FocusLost:** no live mode, no Escape revert, no counter, no max length, no monospace option.
- **`GetLines` (2769-2773)** drops blank lines and keeps `\r`.

**v2 TextArea:**

- **Layout.** A ScrollingFrame wrapper with `AutomaticCanvasSize=Y`, and the caret kept in view by scrolling to the cursor using `TextBounds` and `CursorPosition`. `AutoGrow` from MinHeight to MaxHeight before it scrolls.
- **Input options.** `Monospace = true` (RobotoMono or Code), `MaxLength` with a counter, `OnChanged` (debounced), and Escape to revert.
- **Consistency.** The same focus treatment as Input.
- **API.** `GetLines(keepEmpty)`.

---

## 7. Keybind (2414-2449)

**Anatomy:**

- A 54 px row with a 77x28 pill at TextSize 10 (2417).
- The pill shows the raw KeyCode name: `"LeftControl"`, `"KeypadEight"`, `"RightBracket"`.
- An unbound key shows the literal `"None"` in accent colour, which reads like a key named None.

**Probe P4 results:**

- **Rayfield semantics are broken.**
  - A Rayfield-style `CreateKeybind{CurrentKeybind="Q", HoldToInteract=false, Callback=...}` **never calls Callback when Q is pressed** (probe: 0 calls).
  - In v1 `Callback` fires on *rebinding* (2426), and pressing the key fires `OnPressed`/`Pressed` (2442). In Rayfield, `Callback` is the press handler (with a `held` bool when `HoldToInteract` is true).
  - Every keybind in a migrated Rayfield script silently does nothing.
  - `HoldToInteract` is ignored entirely: there's no InputEnded handling.
- **Destroyed keybinds keep firing `OnPressed`** (probe: count went from 1 to 2 after `Destroy`). The global InputBegan connection (2435) is never disconnected, and `_onDestroy` (2430) only removes the overlay entry. A UI that rebuilds keybinds dynamically gets duplicate or ghost actions.
- **Locked keybinds still fire** (probe).
- **Capturing a key also triggers that key.**
  - While rebinding B, pressing F (A's key) also fired A's `OnPressed`.
  - Rebinding to `Insert` toggled the whole window closed (true to false).
  - Every keybind and the window's toggle handler (3095-3099) listen to the same InputBegan, and capture doesn't sink the input.
- **No conflict detection.** B and A could both be bound to F with no warning, and so can the window's ToggleUIKeybind.
- **Mouse buttons can't be bound** (MouseButton2 left it still listening), **and neither can gamepad buttons** (`UserInputType~=Keyboard` returns early, 2436).
- **Escape *clears* the bind to None** (2438) instead of cancelling, so there's no keyboard way to back out of a rebind without losing the old key. Clicking the pill again does cancel.

**Probe 2 (overlay cost):**

- The overlay is rebuilt from scratch on every `Set` and every `SetActive` (1558-1577).
- One press of a momentary bind rebuilds it twice (on press and 0.18 s later), creating 49 instances.
- One press on a key shared by 3 toggle binds created 42 instances.

**From reading the code:**

- Capture mode never times out, and clicking elsewhere doesn't cancel it. A user who clicks the pill and walks away has their next movement key (W) captured.
- `processed` keys can't be captured (2436).
- `overlayEntry.Name` is captured once at creation (2419), so `SetTitle` doesn't update the overlay.
- No modifiers (Ctrl+K), and the toggle-mode latch state isn't exposed or persisted.

**v2 Keybind:**

- **Compatibility rule.**
  - When `OnPressed`/`Pressed` is absent, `Callback` is the **press** handler (Rayfield semantics).
  - With `HoldToInteract=true`, `Callback(held)` fires on both press and release.
  - When `OnPressed` is present, the v1 meaning holds (Callback means rebind).
  - New `OnChanged(key)` reports rebinds unambiguously.
  - Document this as the one deliberate behaviour change. It only affects v1 scripts that used `Callback` for rebind notifications without `OnPressed`.
- **`Mode = "Press" | "Toggle" | "Hold"`** (v1 `Toggle=true` maps to `Mode="Toggle"`). Expose `:IsActive()`, and optionally persist the toggle state.
- **Combos and devices.** Bindings can be keys, mouse buttons (`MouseButton2`, `MouseButton3`) and gamepad buttons (`ButtonX`, `DPadUp`, ...), with Ctrl/Shift/Alt modifiers. Stored as `"LeftControl+K"`, so a bare key name still parses.
- **Friendly labels.** Ctrl, Shift, Alt, Num 8, RMB, MMB, gamepad glyphs, and an em-dash (or "Unbound" in Dim) instead of "None". The pill sizes to its text.
- **Capture UX.**
  - A pulsing accent ring with the hint "Press a key — Esc cancel, Backspace clear".
  - Auto-cancel after 6 s and on any click outside.
  - Capture **sinks** the input: a module-level `capturing` flag that every dispatcher and the window toggle respect.
- **Conflicts.** On assign, check every keybind, every toggle's attached key and the window toggle key. Show an inline warning chip ("Also used by: Fly", with Swap and Keep) and honour `AllowConflicts=false`.
- **Shared dispatcher.** One UIS InputBegan and InputEnded pair for all binds (combo to entries), released on element Destroy, respecting Lock and the window's `processed` and TextBox-focus rules.
- **Overlay.** Update the affected row incrementally instead of rebuilding the whole overlay. Update entry names on `SetTitle`.

---

## 8. Dropdown (2451-2549)

**Anatomy:**

- A 58 px row with the title in the left 45% at 11 px muted, truncated (2455).
- A 37 px select button in the right 55% (2456), with the selected text at 11 px and a chevron.
- Multi-select shows `"A, B"`, or `"A  +N"` for more than 2 (2470).
- In a half-width row column the select button is about 110 px wide, so the value is mostly an ellipsis.

**Probe P5 results:**

- **Popup state is global and visuals get stuck.**
  - With A open, clicking B closes A's popup but **doesn't open B**, so a second click is needed.
  - **A's chevron stays at 180° and its stroke stays Accent.** B's `closePopup` (2511-2515) destroys the shared `window._dropdownPopup` and resets *B's own* stroke and chevron.
  - The ColorPicker's `openPicker` destroys the dropdown popup directly (2877) and leaves the same stuck visuals.
  - Opening a dropdown doesn't close the colour popup, so both can be open at once.
- **An unknown value clears the selection.**
  - `Set({"Typo"})` emptied `CurrentOption`, **fired the callback with `{}`**, and parked `"Typo"` into `Argon._pendingFlags.DDA` (2486), which is then saved into the config.
  - Rayfield ignores unknown values. A single typo in script code wipes the user's choice and pollutes the save file.
- **`Refresh` that removes the selected option changes the value silently.** `CurrentOption` became `{}` with no callback and no `changed()` (2506). But the restore branch (2496-2503) *does* fire the callback, without `changed()`, so flag listeners are skipped.
- **Popup placement is fixed.**
  - It always opens below the button (2521), with no flip and no Y clamp. A dropdown at y=1000 on a 1080 viewport opened with its popup spanning y=1043 to 1269, mostly off-screen.
  - **The popup is 226 px tall regardless of option count** (2544): two options sit in a mostly empty panel.
  - It is positioned once, in ScreenGui space, at open time. It **doesn't follow** the trigger when the page scrolls or the window is dragged or resized.
  - X is clamped against `workspace.CurrentCamera.ViewportSize` (2519) while the gui has `IgnoreGuiInset=false` (1252), so the coordinate spaces differ by the topbar inset.
- **No outside-click close and no Escape.** The only things that close it are clicking the trigger again, switching tabs (1662), hiding the window (1389) or opening a colour picker.
- **The whole list is rebuilt on every open and never virtualised.** Opening a 500-option dropdown created **+1,566 instances, +1,502 connections and +1,034 theme bindings**. Closing and reopening rebuilt all of it again (+2,068 bindings since the first open, pruned only by the 30 s timer at 261-268). The sandbox took about 38 ms per open, and a live client will be slower, since every property write crosses into the engine. Player, item and teleport-location lists are where this hurts.
- **The multi-select highlight inverts after hover (probe 3).**
  - Each option's `hover()` snapshots its colour at build time (2532).
  - After toggling an option and moving the mouse off, a newly selected option goes back to Surface (looks unselected), and a deselected one goes back to Active (looks selected).

**From reading the code:**

- The filter box is always present, even for 2 options, and isn't focused automatically. There's no "No results" state and no empty-options state (just a blank panel).
- No keyboard navigation (arrows, Enter, Escape, type-ahead).
- Selected rows have no checkmark, only a colour change.
- Single-select can't be cleared from the UI, and there's no "Select all / Clear" for multi.
- `Refresh` while the popup is open leaves stale rows. Clicking one sets a value that no longer exists and clears the selection.
- Locking or destroying the element doesn't close its popup.
- The popup has no ClipsDescendants while it grows from 0 to 226 px with Back easing (2544), so the filter field shows above an empty, still-growing panel.
- Change detection runs `HttpService:JSONEncode` on every `Set` (2487-2488). Cheap, but it will throw if options are Instances.

**v2 Dropdown:**

- **Trigger.**
  - An adaptive split that gives the value at least 55% of the width; in a narrow column the label goes above the value.
  - Multi-select shows **chips with an ×** and a `+N` overflow chip.
  - A clear (×) button when `AllowNone = true` or in multi mode.
- **One shared Popover service per window, used by Dropdown, ColorPicker, Input suggestions and the context menu.**
  - It anchors to the trigger and re-anchors on AbsolutePosition changes while open.
  - It flips above when there isn't room below, and clamps to `gui.AbsoluteSize`.
  - It closes on outside click (via a transparent full-screen catcher), Escape, window hide, tab switch, the trigger scrolling out of view, or the owner being locked or destroyed.
  - Exactly one popover is open at a time, and the previous owner's visuals are restored through its own close callback.
- **Height.** `min(rows * rowH + header, 300)` with a 36 px row height (touch-friendly).
- **Search.** Shown automatically above 8 options (override with `Searchable`). Focused automatically on desktop (`KeyboardEnabled and not TouchEnabled`), with the match highlighted and a "No results" row.
- **Keyboard.** Up and Down move the highlight, Enter picks, Space toggles in multi, Escape closes, Home and End jump, and type-ahead works when there is no search box.
- **Virtualised list.** About 12 recycled row instances in a ScrollingFrame with `CanvasSize = n * rowH`. Only text and selection are rebound on scroll. Built once, then hidden rather than destroyed between opens, so the cost stays constant at any option count.
- **Rows.**
  - A Lucide `check` on selected rows.
  - Option entries can be strings or `{Text, Value, Icon, Description, Disabled}`, and group headers are supported.
  - Multi mode gets a "Select all / Clear" header with a count, plus `MaxSelected`.
- **Semantics.**
  - `Set` with an unknown value keeps the current selection and warns. Values are only parked into pending flags *while a config is loading*.
  - `Refresh` rebuilds an open popup and reports a selection change through `changed()` plus the callback, consistently.
  - Per-element popup state.
- **Option sources.** `Options = function() return ... end` is evaluated on each open, and `Special = "Players"` gives a live player list with avatars.

---

## 9. ColorPicker (2851-2905)

**Anatomy:**

- A 58 px row with an 80x30 swatch button (2855) and a hex label in **always-white** text (2857).
- The popup (2879-2897) is 250x201 and holds a 116 px SV square (two gradient overlays), a **13 px hue strip** (2885), and a 31 px hex TextBox.
- No alpha, no presets, no RGB or HSV fields.

**Probe P6 results:**

- **White label on a light swatch:** a `#FFFFFF` swatch carries white `#FFFFFF` text, so it's unreadable on white, yellow and pastel colours.
- **Two global handlers leak on every open.** `openPicker` connects `UserInputService.InputChanged` and `InputEnded` (2894-2895) each time it opens and never disconnects them. **25 open and close cycles left 50 extra global handlers.** Each runs on every mouse move for the rest of the session and holds the destroyed popup's instances. `PruneRegistries` (232-257) only drops connections that report `Connected == false`, and these never do.
- **The popup is never clamped.** With the swatch at x=60 the popup opened at **x=-110**, off-screen. It is placed at `absolute.X-170, absolute.Y+38` (2879) with no viewport check on either axis, so it also spills off the bottom near the screen edge. There's no outside-click or Escape close, and it doesn't follow scroll or drag.
- **Hex entry desyncs the picker.**
  - Typing `#00FF00` set the value, but **the SV cursor didn't move and the square still showed red hue**.
  - The next hue nudge produced `1,1,1` (white) instead of a green variant.
  - `h, s, v` are popup-local copies taken at open (2878), and `hexBox.FocusLost` (2896) only calls `element:Set`. An external `Set` while the popup is open desyncs it the same way.
- **The hex parser** accepts only 6 digits. `#FFF` was rejected silently: no error state, the text just reverts.
- **`Set` returns nothing.**

**From reading the code:**

- **Hue is lost on black or grey.** It's re-derived from the Color3 on every open (2878), so a colour dragged to v=0 or s=0 reopens with the hue reset to red.
- **The InputChanged handler doesn't filter by input type** (2894). A gamepad thumbstick InputChanged (Position in the -1..1 range) during a drag snaps the colour to the corner, and a second touch drives it.
- **Every drag step runs the callback plus `changed()`**, the same cost as the slider.
- **Popup pop-in.** The popup isn't ClipsDescendants while it grows from 0 to 201 px, so the square and strip draw at full size before their background reaches them.
- **Small targets.** The 13 px hue strip is a very small target for touch.

**v2 ColorPicker:**

- **Swatch.** A checkerboard underlay for alpha. The hex ink switches to black or white by luminance, or the hex moves next to the swatch. The swatch is 36 px tall and the whole row opens the picker.
- **Popover.** The shared popover from section 8: clamped, flips, follows the trigger, closes on outside click and Escape.
- **Persistent HSV state.** Keep `h, s, v` and `a` in the element. Hex and RGB entry and external `Set` update the cursors live, and hue survives black and grey.
- **Strips.** The hue strip, and an optional **alpha strip** (`Alpha = true` or `Transparency = 0.3`), are 14 px visually with 36 px invisible hit bands. The callback becomes `callback(color, alpha)`; the first argument stays a Color3 for compatibility.
- **Entry.**
  - The hex field accepts `#RGB`, `#RRGGBB`, `#RRGGBBAA`, `r,g,b` and `rgb(r,g,b)`, validated live with a Danger stroke while invalid.
  - An RGB / HSV tab with numeric fields.
- **Colour sources.**
  - A preset row: the theme accents plus user `Presets`.
  - **Recent colours**, the last 8, kept in UI preferences. Roblox can't sample screen pixels, so recents stand in for an eyedropper.
  - Copy and paste of colours between pickers (`setclipboard` plus an internal clipboard).
- **Optional `Rainbow` mode** (hue cycle with a speed setting), a staple of script-hub colour pickers.
- **Dragging.** Uses the shared drag controller (no per-open connections). Callbacks are throttled to one per frame, and changes are committed and saved on release.

---

## 10. Stepper (2660-2695)

**Anatomy:**

- A 54 px row with a 112x30 group (2667).
- **26x24 minus and plus buttons** (2668-2669) using ASCII `"-"` and `"+"` glyphs.
- A 50 px value TextBox at 11 px.
- The ends dim to 0.55 transparency at the bounds (2681-2682), which is good.

**Probe P8 and code:**

- `Range={10,0}` crashes the constructor (2673), the same clamp error as the Slider.
- Hit targets are 26x24, well under 40.
- No press-and-hold auto-repeat: getting from 0 to 100 takes 100 clicks. No Shift ×10, no arrow keys, no mouse wheel, no drag-to-scrub.
- The value box has no focus ring, doesn't select its text, has no Escape revert, and has no TextTruncate, so a long suffix overflows.
- The rounding code is a copy of the Slider's (2672-2678).
- `Set` returns self.

**v2 Stepper:**

- **Size.** A 36 px group with 34x30 buttons (40 px or more of hit area) using Lucide `minus` and `plus` icons.
- **Repeat.** Press-and-hold auto-repeat: first repeat at 400 ms, then every 90 ms, accelerating to 40 ms. Shift steps ×10.
- **Input.** Up and Down arrow keys when focused or hovered, the mouse wheel while hovered, and optional `Scrub = true` (drag horizontally on the value).
- **Shared numeric model with the Slider:** `Decimals`, `Format`, `Prefix` and `Suffix`, Range validation, and `Wrap = true` to cycle around the ends.

---

## 11. Segmented (2697-2752)

**Anatomy:**

- A 76 px row with a title, or 48 px without one.
- A 32 px strip with 3 px padding holds **26 px-tall equal-width buttons** at TextSize 10 with TextTruncate (2739).
- The active segment turns Accent with white text (2715-2716). There is no moving indicator: each button cross-fades its colour on its own.

**Probe P8 and code:**

- **Options are converted to strings.** With numeric options `{1,2,3}` the callback receives the string `"2"` (2700, 2722), so a script comparing with `== 2` never matches.
- **A typo is saved into the config.** `Set("nope")` parks `"nope"` into `_pendingFlags.Seg` (2724), and it gets saved.
- **Empty `Options`** render a selectable `"None"` segment (2701) that fires the callback with `"None"`.
- **`Refresh` dropping the current option** switches to option 1 silently, with no callback and no save (2745).
- **Truncation.** With 5 or more options in a half-width row, labels collapse to `"Op…"` with no way to read them.
- No keyboard or gamepad support. Hit height is 26 px.

**v2 Segmented:**

- **Visuals.** A **sliding indicator**: one accent pill that tweens Position and Size to the selected segment, with Quint easing over about 180 ms. This alone makes the control feel modern. Optional icons per segment, with icon-only segments getting a tooltip.
- **Size.** A 38 px strip with segments 32 px or taller.
- **Overflow.** When the segments would be narrower than about 56 px, the control turns into a compact dropdown automatically, so it works at any width.
- **Input.** Left and Right arrows when focused, and the D-pad or shoulder buttons on gamepad.
- **Modes.** `Multiple = true` for a toggle-group mode.
- **Data.**
  - `Options` entries can be `{Text, Value, Icon}`.
  - String callbacks stay the default for compatibility; numeric values are returned only when `Value` is given.
  - Empty options render a disabled "No options" state.
  - An unknown `Set` is ignored with a warning; values are only parked while a config is loading.
  - `Refresh` reports changes.

---

## 12. Rayfield compatibility checklist (controls)

| Rayfield usage | Argon v1 | v2 action |
| --- | --- | --- |
| `Keybind.Callback` runs on key press, `HoldToInteract` passes `held` | Runs on rebind; press needs `OnPressed`; `HoldToInteract` ignored | Compatibility rule in section 7 |
| `Button:Set("New name")` | Missing (nil) | Add as an alias of SetTitle |
| `Input` with `RemoveTextAfterFocusLost` calls back once | Calls back twice (`"text"`, then `""`) | Clear silently |
| `Slider Suffix` renders `"10 Bananas"` | `"10Bananas"` | Insert a space unless the suffix starts with `%` |
| `Dropdown:Set` with an unknown option is ignored | Clears the selection, fires `{}`, pollutes the config | Ignore and warn |
| `ColorPicker:Set(Color3)`, `Toggle:Set(bool)`, `Dropdown:Refresh(t)` | Works | Keep |

---

## 13. Docs and preview parity

`argon-ui-preview.html` (the docs demo, also `docs/preview.html`) implements behaviour the shipped library does not have:

- slider arrow keys, Home and End (preview ~1202-1214)
- `role="slider"`, `tabindex` and `:focus-visible` rings (26, 160, 707)
- Escape closing dropdowns, pickers and dialogs (1408-1418)
- pointer capture for drags (1189, 1268)

Anyone who evaluates Argon from the docs will expect these in game. v2 should either implement them for real (recommended, see the focus model in section 1) or keep the preview faithful to the library.

---

## 14. v2 control architecture (what fixes most of the above at once)

1. **`Control` base class** with:
   - a Maid
   - a state machine (`rest`, `hover`, `pressed`, `focused`, `disabled`, `locked`, `loading`, `error`)
   - token-driven painting, so no per-property theme bindings or `unbindTheme` special cases
   - `Default`, `Get`, `Set` (returns self), `Reset`, `OnChanged`, `SetDisabled`, `SetLoading`, and a context menu
2. **Window-level services**, one each:
   - a `Popover` (anchor, flip, clamp, follow, outside-click and Escape, one open at a time)
   - a `DragController` (one UIS pair, tracks the InputObject, locks page scroll, checks touch intent, delivers once per frame)
   - a `KeyDispatcher` (one UIS pair; combos, modes, conflicts; respects capture and Lock)
   - a `FocusManager` (Tab order, focus ring, gamepad selection)
3. **Commit semantics**:
   - live callbacks are throttled to one per frame
   - a separate `OnRelease`/commit callback
   - flashes and autosave happen on commit only
4. **Sizing tokens**:
   - 40 px minimum hit targets (invisible halos where the visual is smaller)
   - 13 px value text, 14 px titles, 12 px helper text, whole-pixel sizes only
   - visible tracks (a `Track` token at 1.5:1 or better against Surface)
5. **Robust inputs**: validate Range (swap) and Increment (at least epsilon), make the maximum reachable, parse values UTF-8-safely, and make `safeCall` use xpcall with the element context.
