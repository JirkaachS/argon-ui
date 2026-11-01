# Argon UI v2.0: final design specification

Status: final design, ready for implementation. Supersedes the three direction mockups.
Companion documents: `ARCHITECTURE_V2.md` (modules, scheduler, persistence, API plumbing) and the audits in `audit/`.
Clickable reference: `mockup.html` in this folder (open from disk; append `#skip` to skip the loader). Every number in this document is drawn in that mockup, and its "Inspect Roblox recipe" switch shows the instance recipe of any part on hover.

Conventions:
- px means pixels at UIScale 1. All `TextSize` values are whole numbers.
- `T` is `BackgroundTransparency` (or `ImageTransparency` / `Transparency` where stated).
- Token names are written `Surface`, `AccentHi` and so on. They resolve through `Theme.get` (ARCHITECTURE_V2 §5).
- "v1 Lnnn" cites `argon-UI/argon-ui.luau` v1.18.3.
- MUST, SHOULD and MAY carry their usual meaning.

---

## 0. Decision summary

### 0.1 Which direction won

| Direction | Next-gen look | UX | Feasibility | Sum |
|---|---|---|---|---|
| **Precision** | 7.8 | 7.6 | **8.5** | **23.9** |
| Native | 6.6 | **8.3** | 7.0 | 21.9 |
| Depth | **8.4** | 7.0 | 5.0 | 20.4 |

**Precision is the base.** It contributes the layout discipline, the shadow and stroke budget, pooled floating layers, the palette and popover craft, the honest loader and the instance diet.

It wears **Depth's material and light**:
- a tinted glass frame (0.14 instead of 0.22);
- an opaque sheet inset into the frame;
- opaque platters;
- Montserrat SemiBold display type;
- accent gradients only on active state;
- the orb loader;
- 12 themes with an accent override and a Solid / Tinted / Clear material choice.

It carries **Native's input parity**:
- state is never shown by colour alone;
- focus ring, gamepad hint bar and glyphs;
- a landscape-phone rail and a portrait sheet with bottom tabs;
- bottom sheets on phones;
- the reopen orb and a labelled quick dock;
- loader tips and error actions;
- a fixed layer order.

### 0.2 Grafts, and the weakness each one fixes

| # | From | Graft | Weakness fixed (judge) |
|---|---|---|---|
| G1 | Depth | Material stack: glass frame, opaque sheet, opaque platters. Default Tinted at **T 0.14**; Daylight defaults to Solid; Solid / Tinted / Clear is a user setting. | Precision "reads as a dark admin panel" and is "practically opaque". Depth's 0.22 bled stripes under nav labels; 0.14 halves that, and no text-dense surface is translucent. |
| G2 | Depth | Light only for active state: an `AccentHi→Accent` UIGradient on switch-on, slider fill, primary button and nav indicator. One pooled glow, at most 3 live. `AccentAlt` only on progress and loader bars. | Depth "could tip into gamer-RGB"; its always-on per-toggle glow broke the 3-glow budget. |
| G3 | Depth | Montserrat SemiBold 600 for page, dialog and section titles; Roboto for rows; RobotoMono for changing numbers. | Precision's "flat hierarchy, no display voice". |
| G4 | Precision | One grouped platter per section, inset dividers, no row fill until hover, a right-aligned control column, 28/32/40 px control heights. | Native's "card soup", and the lowest density. |
| G5 | Precision | Whole-px type with a 12 px floor; only Roboto 400, 500 and 700; sentence case. | Depth's 12.5 px status and 13.5 px textarea. |
| G6 | Native + feasibility | **Fill steps are the primary separator** (Surface/Sheet ≥ 1.15:1, Hover/Surface ≥ 1.12:1). The 1 px lit edge is polish, not structure. | Precision's hairlines at 0.92 transparency "vanish at fractional UIScale". |
| G7 | Precision | Shadows only on the window and floating layers. One **hollow, offset-matched** 9-slice shadow asset. | Depth's shadow "darkens what shows through" the translucent window. |
| G8 | Native | State never by colour alone: a check glyph in every switch knob, plus On/Off labels in High contrast, touch and gamepad. | The colour-only toggles of Precision and Depth. |
| G9 | Native | Focus ring: 2 px `Focus` UIStroke plus the pooled accent glow, spring-moved and re-parented into the topmost focus layer. A gamepad hint bar with platform glyphs. | Depth "keyboard focus was not demonstrated"; Native's ring drew above the palette scrim. |
| G10 | Native | Landscape-phone rail, portrait sheet with an M3 bottom tab bar, bottom sheets for every picker, Density Auto/Compact/Touch. | Precision has no landscape phone; its phone theme picker is a centred popover. |
| G11 | Native | Layer order `Base < Overlay < Toast < Modal < Popover < Tooltip < Boot`; the ring travels with focus; phone toasts are compact pills. | Toasts covering the phone sheet header, the palette and the reopen badge (all three mockups). |
| G12 | Precision | Changed dots, a "N changed · Reset tab" chip, Reset section, an Undo pill; value pills you can type into; palette results that act in place. | Native has no tab or section reset. |
| G13 | Native | Validation states the range ("Must be between 16 and 120") and clamps on Enter; Paste is type-checked and disabled with a reason. | Precision's out-of-range value "only shakes". |
| G14 | All (fix) | The close key is **Backspace / gamepad B** everywhere. No Esc keycap anywhere. | All three advertised Esc, which opens Roblox's menu (ARCHITECTURE_V2 §6.1). |
| G15 | Feasibility | Faces chosen by load cost. The loader and first frame use only engine-local faces; the two CDN faces are preloaded and font-swapped. | All three put CDN faces on the loader's first frame. |
| G16 | Feasibility | No subtree opacity animation: tab switch, pop-in and hand-over use an opaque **veil** plus Position. | All three faded whole subtrees (CanvasGroup in disguise). |
| G17 | Depth (fix) | Label and Paragraph get 16 px row padding; the colour-picker alpha thumb is inset so it never clips; the "auto" accent swatch is a plain swatch with an `A` glyph (no conic gradient); the stage never scrolls sideways. | Depth polish bugs. |
| G18 | UX (fix) | Palette ranking: word prefix, then substring, then a capped subsequence (at most 2 gaps, never across 3 words). Host `Keywords` are indexed. | "esp" returned "Teleport to spawn". |

### 0.3 What the owner gets

| Complaint | Answer |
|---|---|
| "Load times are awful" | No network, no yield and no decode before the first frame. `Create*` builds only state. Tabs mount in 4-8 ms slices. A 500-control hub opens in about 0.1-0.6 s with no frame over one slice. See §4 and §11. |
| "The loading is not the best" | Nothing for 150 ms, then an honest card that says what it is doing ("Building Combat · 155 of 212"), then a ghost morph into the already-built window. No fixed timers. |
| "Look more next-gen" | Glass frame, opaque sheet and platters, a lit edge, light only where something is active, a display voice, concentric radii, 12 themes, spring motion. |
| "Components next-gen, UX top tier" | Every control works by mouse, keyboard, touch and gamepad, with typed values, a context menu, changed tracking and reset/undo, validation that explains itself, and pickers that turn into bottom sheets on phones. |
| "Add things that make sense" | Command palette, quick dock and reopen orb, profiles, notifications with actions and an inbox, keybind conflicts, status chip and badges, key gate, density and scale. See §8. |

---

## 1. Principles (each one is testable)

1. **Text never sits on translucency it does not control.** Only the frame (E0) is translucent, and it carries only `Text` and `Text2`. Everything text-dense sits on the opaque sheet or opaque platters.
2. **Surfaces separate by fill steps, not hairlines.** Every hairline in this spec is redundant with a fill step or with spacing.
3. **Light means active.** Gradients and glows appear only on an element that is on, selected, focused, dragged or primary. Rest state is neutral.
4. **State is never colour alone.** Every binary state also has a shape (knob position plus a check glyph), text (On/Off, "3 of 5 selected"), or position.
5. **Every input works everywhere.** Each interaction lists its mouse, keyboard, touch and gamepad path. Nothing depends on hover.
6. **Honest loading.** The bar is determinate only when the total is known. The status names the real work. The window never appears half-built.
7. **Budgets are part of the design.** Instances per control, UIStrokes per control, live glows, CDN faces and running loops are capped (§11). The mockup's "Inspect Roblox recipe" shows that every effect is buildable from the allowed vocabulary.

---

## 2. Design tokens

### 2.1 Colour roles

All fills are **solid colours** computed per theme. The only translucent tokens are the material transparencies (§2.2), the glass veils (`Text` at a transparency, used only on the frame) and the scrim. Solid fills keep contrast computable and render the same at any UIScale.

| Token | v1 alias | Role | Used on |
|---|---|---|---|
| `Frame` | `Background`, `Sidebar` | E0 glass base | Window frame, sidebar, rail |
| `Sheet` | `Window` | Opaque content surface, inset into the frame | Topbar, page, TOC |
| `Surface` | `Surface` | E1 platter, at least 1.15:1 over Sheet | Section cards, stat tiles, list body |
| `Hover` | `Hover` | Row hover fill, at least 1.12:1 over Surface | Pooled hover frame, menu rows |
| `Active` | `Active` | Pressed and selected fill, about 1.26:1 over Surface | Pressed rows, selected list row, segmented indicator base |
| `Raised` | (new) | E2 floating layers | Popovers, menus, toasts, dialog, palette, loader card, keycaps |
| `Well` | `Input` | Recessed fields | Inputs, dropdown triggers, value pills, segmented and stepper tracks |
| `Track` | (new) | Switch-off track and slider groove, at least 1.6:1 over Surface | Switch, slider, progress track |
| `Border` | `Border` | Control edges, at least 1.4:1 over Surface | Well strokes, checkbox outline, popover stroke (light and high-contrast themes) |
| `BorderSoft` | `BorderSoft` | Dividers | Inset row dividers, topbar rule |
| `Text` | `Text` | Primary text (at least 10:1 on Surface) | Labels, titles, values |
| `Text2` | (new) | Secondary text (at least 9:1) | Nav labels, section headers, sidebar captions, value suffixes, **the only text role besides `Text` allowed on glass** |
| `Muted` | `Muted` | Descriptions (at least 4.8:1 on Surface, 4.5:1 on Hover and Raised) | Descriptions, meta, toasts' body |
| `Dim` | `Dim` | Placeholders and hints (at least 4.5:1 on Well, 3.5:1 on Surface) | Placeholders, keyboard hints |
| `Disabled` | (new) | Disabled text and glyphs (exempt) | Disabled controls |
| `Accent` | `Accent` | Brand and state colour | Gradient end, selection, progress |
| `AccentHi` | `AccentLight` | Light end of the active gradient | Gradient start, focus ring (dark themes) |
| `AccentDeep` | `AccentDark` | Pressed accent, slider fill start | Pressed primary, slider fill |
| `AccentAlt` | (new) | Second hue: **progress and loader bars only** | ProgressBar, loader bar |
| `AccentText` | (new) | Accent as text (at least 4.6:1 on Surface) | Links, changed dots, selected segment label |
| `OnAccent` | (new) | Ink on accent fills (at least 4.5:1 on **both** Accent and AccentHi) | Primary button text, checkbox check, badges |
| `AccentSoft` | (new) | Solid accent tint on Surface | Selected segment, listening keycap, active keybind-list row |
| `Focus` | (new) | Focus ring (at least 3:1 on Sheet and Surface) | Focus ring, focused field stroke |
| `Success` `Warning` `Danger` `Info` | v1 (Info new) | Status foreground (each at least 4.5:1 on Surface) | Icons, status text, toasts |
| `SuccessSoft` … `InfoSoft` | (new) | Solid status tints | Delta pills, callouts, toast icon plates |
| `OnStatus` | (new) | Ink on solid status fills | Danger button text |
| `Scrim` | (new) | `Frame` darkened, T 0.45 (dark) / 0.6 (light) | Behind dialogs and palette (window area only) |
| `Shadow` | (new) | Black | Shadow image tint |

Glass veils use the `Text` colour, so the polarity flips automatically in Daylight:

| Veil | Value | Used on |
|---|---|---|
| `GlassHover` | `Text` at T 0.94 | Sidebar item hover, search trigger fill |
| `GlassSelected` | `Text` at T 0.90 | Selected nav pill |
| `GlassLine` | `Text` at T 0.90 | The sidebar and sheet edge (never structural) |

### 2.2 Materials

`Prefs.Material` is `"Solid" | "Tinted" | "Clear"`. The default is **Tinted** for dark themes and **Solid** for Daylight. High contrast forces Solid, and the control shows "High contrast uses Solid" as its disabled reason.

| Layer | Solid | Tinted (default) | Clear (cap) |
|---|---|---|---|
| Frame (window, rail, phone sheet header) | 0 | **0.14** | 0.25 |
| Sheet | 0 | 0 | 0.06 |
| Platter (`Surface`), Raised, Well | 0 | 0 | 0 |
| Dock pill, reopen orb, quick dock (`Frame` colour) | 0 | 0.06 | 0.12 |
| HUD overlays (keybind list, watermark, player list) | 0 | 0.10 | 0.18 |

Window opacity in Settings maps onto these three steps. There is no free slider: the cap is part of the readability guarantee.

### 2.3 Built-in palettes (all 12, computed)

The 10 v1 theme names are kept with their v1 accents (`Accent`, `AccentLight`→`AccentHi` and `AccentDark`→`AccentDeep` are byte-identical to v1 L33-50, except where a validator rule had to move a value, which is marked ★ in §2.4). Two themes are added: **Daylight** (light) and **HighContrast** (also accepted as `"High contrast"`).

`bench/v2_final_palette.py` generates these values from a seed per theme and validates them. It writes `bench/v2_final_palette.json`, which the mockup consumes, and the tables below. `theme/Palettes.luau` MUST be generated from the same JSON.

| Token | Argon | Amethyst | Midnight | Emerald | Rose | Slate | Ember | Nord | Mono | Ocean | Daylight | HighContrast |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `Frame` | #0C0E16 | #100B1A | #080C15 | #080F0E | #130A10 | #0D1014 | #120B08 | #1E222B | #0C0C0E | #071018 | #E5E7EF | #000000 |
| `Sheet` | #11131C | #161022 | #0C121D | #0C1514 | #190E15 | #12161C | #18100C | #252A35 | #121214 | #0B161F | #F3F4F8 | #000000 |
| `Surface` | #1F212A | #241E2F | #1B202B | #1B2322 | #281D24 | #1F2329 | #261E1B | #2F343F | #202022 | #1A242C | #FFFFFF | #111111 |
| `Hover` | #282A32 | #2E2838 | #252A34 | #252D2C | #31272E | #282C31 | #2F2825 | #383C46 | #2A2A2C | #232D35 | #F0F1F6 | #262626 |
| `Active` | #31333B | #363040 | #2D323C | #2D3534 | #392F35 | #31353A | #37302D | #3F444D | #323234 | #2C363D | #E5E7EF | #343434 |
| `Raised` | #24262E | #292334 | #202630 | #1F2827 | #2C2229 | #24282D | #2B2420 | #343843 | #252527 | #1F2931 | #FFFFFF | #111111 |
| `Well` | #090A10 | #0C0814 | #060910 | #060B0A | #0E080C | #0A0C0F | #0E0806 | #161A20 | #09090A | #050C12 | #F3F4F8 | #000000 |
| `Track` | #43454D | #484253 | #3F444F | #3F4746 | #4C4148 | #42464C | #4B423E | #51565F | #444446 | #3D4850 | #C4C8D5 | #707070 |
| `Border` | #3B3C45 | #3F3A4A | #363C46 | #363F3E | #443940 | #3A3E44 | #423A35 | #484D56 | #3C3C3E | #353F47 | #D0D4E0 | #969696 |
| `BorderSoft` | #2E3038 | #332D3E | #292F39 | #27302F | #372C33 | #2C3035 | #352D29 | #3B3F4A | #2F2F31 | #263139 | #E7E9F0 | #606060 |
| `Text` | #F1F3F9 | #F5F0FF | #EEF4FF | #EEF9F6 | #FFEFF8 | #EEF3F9 | #FFF1E9 | #ECEFF4 | #F4F4F6 | #E9F6FC | #12141C | #FFFFFF |
| `Text2` | #C3C5CB | #C7C2D1 | #BFC5D0 | #BFCAC7 | #D0C1C9 | #C1C5CB | #CFC3BC | #D9DCE1 | #C5C5C7 | #BBC8CE | #363B4A | #F0F0F0 |
| `Muted` | #969DB1 | #B2A3CD | #929FB5 | #91ABA4 | #BC94AB | #9AA6B6 | #C4A392 | #B1BBC9 | #9F9FA8 | #92AFC0 | #565C70 | #D6D6D6 |
| `Dim` | #74798A | #877B9E | #6E798B | #6D827D | #907082 | #757F8C | #957B6E | #8A93A0 | #797980 | #6E8594 | #696F84 | #B4B4B4 |
| `Disabled` | #515562 | #605672 | #4D5565 | #4C5C59 | #664F5D | #535A64 | #68564D | #666D79 | #55555A | #4C5E6A | #AAAFBE | #787878 |
| `Accent` | #9970FF | #A76DFF | #58A6FF | #34D399 | #F472B6 | #7DC4FF | #FF8A4C | #88C0D0 | #E2E2E8 | #38BDD0 | #6B4AE6 | #FFE14D |
| `AccentHi` | #C3AAFF | #D2B2FF | #9BCDFF | #97F6D3 | #FBB6DC | #BADEFF | #FFBE96 | #BEE0E8 | #FFFFFF | #96E7F0 | #7C5DED | #FFF08A |
| `AccentDeep` | #5C3DB8 | #672DB7 | #235BB4 | #0F7658 | #BE185D | #3478BA | #BE4A1A | #4C8498 | #8C8C96 | #116E82 | #5233C9 | #E6C200 |
| `AccentAlt` | #45C8FF | #F472B6 | #7C8CFF | #38BDF8 | #FB923C | #94A3B8 | #FFD166 | #81A1C1 | #A1A1AA | #60A5FA | #1597D4 | #FFE14D |
| `AccentText` | #AC8BFF | #B787FF | #58A6FF | #34D399 | #F472B6 | #7DC4FF | #FF8A4C | #88C0D0 | #E2E2E8 | #38BDD0 | #5233C9 | #FFE14D |
| `OnAccent` | #07080D | #0A0710 | #05070D | #050908 | #0B060A | #080A0C | #0B0705 | #12141A | #070708 | #040A0E | #FFFFFF | #000000 |
| `AccentSoft` | #332E4C | #392B50 | #24364D | #1F3F35 | #482B3B | #2E3D4B | #493022 | #3E4B56 | #3F3F42 | #1E3C47 | #F0EDFC | #332D0F |
| `Focus` | #C3AAFF | #D2B2FF | #9BCDFF | #97F6D3 | #FBB6DC | #BADEFF | #FFBE96 | #BEE0E8 | #FFFFFF | #96E7F0 | #5233C9 | #FFE14D |
| `Success` | #4ADEA2 | #4ADEA2 | #4ADEA2 | #4ADEA2 | #4ADEA2 | #4ADEA2 | #4ADEA2 | #4ADEA2 | #4ADEA2 | #4ADEA2 | #148756 | #5CF2A6 |
| `Warning` | #F7BE4F | #F7BE4F | #F7BE4F | #F7BE4F | #F7BE4F | #F7BE4F | #F7BE4F | #F7BE4F | #F7BE4F | #F7BE4F | #A46A0E | #FFC24D |
| `Danger` | #FF657C | #FF657C | #FF657C | #FF657C | #FF657C | #FF657C | #FF657C | #FE6B81 | #FF657C | #FF657C | #D62E4B | #FF7A8C |
| `Info` | #60A5FA | #60A5FA | #60A5FA | #60A5FA | #60A5FA | #60A5FA | #60A5FA | #60A5FA | #60A5FA | #60A5FA | #2F74D0 | #7DBBFF |
| `SuccessSoft` | #263D3C | #2A3B40 | #223D3C | #223F35 | #2D3A37 | #263F3B | #2B3B2F | #334E4E | #263D35 | #21403E | #E8F5EF | #224232 |
| `WarningSoft` | #40392F | #443634 | #3C3830 | #3C3A29 | #47362A | #403A2E | #453622 | #4D4941 | #403829 | #3B3B32 | #F8F1E7 | #45381E |
| `DangerSoft` | #412B36 | #45293B | #3D2B37 | #3D2D30 | #482831 | #412D35 | #462929 | #4F3C48 | #422B30 | #3C2E38 | #FBEAED | #45282C |
| `InfoSoft` | #293549 | #2D334E | #25344A | #253742 | #303244 | #293748 | #2F333C | #37455B | #2A3442 | #24374B | #EAF1FA | #293645 |
| `OnStatus` | #07080D | #0A0710 | #05070D | #050908 | #0B060A | #080A0C | #0B0705 | #12141A | #070708 | #040A0E | #FFFFFF | #000000 |


Contrast (WCAG ratios; target in brackets):

| Pair (target) | Argon | Amethyst | Midnight | Emerald | Rose | Slate | Ember | Nord | Mono | Ocean | Daylight | HighContrast |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Text on Surface (>= 10.0) | 14.43 | 14.39 | 14.76 | 14.90 | 14.64 | 14.13 | 14.78 | 10.78 | 14.77 | 14.30 | 18.38 | 18.88 |
| Text2 on Surface (>= 9.0) | 9.27 | 9.24 | 9.44 | 9.54 | 9.38 | 9.11 | 9.45 | 9.01 | 9.45 | 9.20 | 11.16 | 16.57 |
| Muted on Surface (>= 4.8) | 5.91 | 6.90 | 6.09 | 6.54 | 6.15 | 6.39 | 7.00 | 6.41 | 6.18 | 6.84 | 6.64 | 12.99 |
| Muted on Hover (>= 4.5) | 5.28 | 6.09 | 5.38 | 5.77 | 5.43 | 5.69 | 6.18 | 5.67 | 5.46 | 6.10 | 5.89 | 10.41 |
| Muted on Raised (>= 4.5) | 5.58 | 6.51 | 5.68 | 6.17 | 5.80 | 6.02 | 6.53 | 6.01 | 5.83 | 6.45 | 6.64 | 12.99 |
| Dim on Surface (>= 3.5) | 3.69 | 4.11 | 3.70 | 3.94 | 3.74 | 3.87 | 4.15 | 3.99 | 3.75 | 4.10 | 4.98 | 9.11 |
| Dim on Well (>= 4.5) | 4.55 | 5.06 | 4.53 | 4.86 | 4.58 | 4.81 | 5.05 | 5.61 | 4.60 | 5.11 | 4.53 | 10.13 |
| AccentText on Surface (>= 4.6) | 6.03 | 6.08 | 6.45 | 8.34 | 6.13 | 8.42 | 6.99 | 6.21 | 12.58 | 7.02 | 7.85 | 14.50 |
| OnAccent on Accent (>= 4.5) | 5.82 | 5.99 | 7.97 | 10.41 | 7.59 | 10.61 | 8.61 | 9.18 | 15.59 | 8.88 | 5.60 | 16.13 |
| OnAccent on AccentHi (>= 4.5) | 10.00 | 11.02 | 12.05 | 15.67 | 12.27 | 14.17 | 12.50 | 13.13 | 20.11 | 14.22 | 4.51 | 18.08 |
| Focus on Sheet (>= 3.0) | 9.27 | 10.21 | 11.22 | 14.51 | 11.50 | 12.94 | 11.68 | 10.28 | 18.71 | 13.04 | 7.14 | 16.13 |
| Focus on Surface (>= 3.0) | 8.02 | 8.85 | 9.75 | 12.55 | 9.91 | 11.25 | 10.15 | 8.89 | 16.22 | 11.25 | 7.85 | 14.50 |
| Track on Surface (>= 1.6) | 1.67 | 1.67 | 1.67 | 1.69 | 1.67 | 1.67 | 1.67 | 1.68 | 1.68 | 1.68 | 1.67 | 3.81 |
| Border on Surface (>= 1.4) | 1.47 | 1.46 | 1.46 | 1.48 | 1.46 | 1.47 | 1.46 | 1.46 | 1.47 | 1.47 | 1.48 | 6.38 |
| Surface on Sheet (>= 1.08) | 1.16 | 1.15 | 1.15 | 1.16 | 1.16 | 1.15 | 1.15 | 1.16 | 1.15 | 1.16 | 1.10 | 1.11 |
| Hover on Surface (>= 1.06) | 1.12 | 1.13 | 1.13 | 1.13 | 1.13 | 1.12 | 1.13 | 1.13 | 1.13 | 1.12 | 1.13 | 1.25 |
| Danger on Surface (>= 4.5) | 5.65 | 5.67 | 5.75 | 5.65 | 5.72 | 5.56 | 5.76 | 4.51 | 5.72 | 5.56 | 4.83 | 7.57 |
| Success on Surface (>= 4.5) | 9.35 | 9.39 | 9.51 | 9.36 | 9.47 | 9.21 | 9.53 | 7.26 | 9.47 | 9.20 | 4.52 | 13.22 |
| Warning on Surface (>= 4.5) | 9.48 | 9.52 | 9.65 | 9.49 | 9.60 | 9.34 | 9.66 | 7.36 | 9.61 | 9.33 | 4.54 | 11.76 |
| Info on Surface (>= 4.5) | 6.30 | 6.33 | 6.41 | 6.31 | 6.38 | 6.20 | 6.42 | 4.89 | 6.38 | 6.20 | 4.64 | 9.37 |
| Text2/glass14-white | 7.65 | 7.67 | 7.87 | 7.93 | 7.80 | 7.49 | 7.82 | 7.42 | 7.90 | 7.65 | 9.32 | 13.67 |
| Text2/glass25-white | 5.10 | 5.11 | 5.24 | 5.29 | 5.20 | 5.00 | 5.21 | 5.07 | 5.26 | 5.11 | 9.55 | 9.13 |
| Muted/glass14-white | 4.88 | 5.73 | 5.08 | 5.44 | 5.12 | 5.25 | 5.79 | 5.27 | 5.16 | 5.69 | 5.55 | 10.72 |
| Text2/glass14-black | 11.30 | 11.26 | 11.45 | 11.67 | 11.38 | 11.19 | 11.41 | 12.20 | 11.51 | 11.35 | 6.59 | 18.43 |

Status colours (`Success`, `Warning`, `Danger`, `Info`) are unified across the dark themes. In v1 they varied slightly per theme (Amethyst, Slate, Ember, Nord, Mono, Ocean). A host that reads `GetColor("Success")` still gets a status green. The light and high-contrast themes have their own darker or brighter sets.


### 2.4 Contrast and the glass checks

Every target in the table above passes in all 12 themes. The last four rows are the glass checks. They composite `Frame` at the material's transparency over a pure white or pure black scene and measure the sidebar's text on it:
- `Text2` on Tinted glass over a white sky is at least 7.4:1 in every dark theme. At the Clear cap (0.25) it is at least 5.0:1.
- `Muted` on glass would be 4.9:1 in Argon. That is why **Muted is banned on glass** (principle 1). Sidebar captions use `Text2`.

Values the validator had to move (★):
- **Daylight:** `AccentHi` was darkened so that white ink keeps 4.5:1 on the whole gradient. `Success` and `Warning` were darkened to reach 4.5:1 as text on white. `Dim` was darkened for placeholders.
- **Nord:** `Danger` was lightened (4.38 → 4.5). `Text` on Nord Surface is 10.8:1, because Nord's surfaces are lighter by design. That is still above AAA.

### 2.5 Custom palettes: `AddTheme`, `CreateTheme`, `SetTheme(table)`, accent override

A host palette may contain any subset of the 18 v1 keys. `Theme.derive` (ARCHITECTURE_V2 §5.2) maps and fills the rest as follows. A host-given key is never adjusted; it is only reported by `Theme.validate`.

| New token | Derived from (when absent) |
|---|---|
| `Frame` | `Background`, else `Sidebar`, else `Window` darkened 25 % in OKLab L |
| `Sheet` | `Window` |
| `Surface` | `Surface`, then stepped toward white (or toward black in light mode) until Surface/Sheet ≥ 1.15 |
| `Hover`, `Active` | `Hover` and `Active`, then stepped to ≥ 1.12 and ≥ 1.26 over Surface |
| `Raised` | Sheet stepped to ≥ 1.22 over Sheet |
| `Well` | `Input`, else Frame mixed 25 % toward black |
| `Track` | mix(Surface, Text), stepped until ≥ 1.6 over Surface |
| `Border`, `BorderSoft` | `Border` and `BorderSoft`, then stepped to ≥ 1.4 and ≥ 1.18 over Surface |
| `Text2` | mix(Text, Surface, 0.22), stepped until ≥ 9 over Surface |
| `Muted`, `Dim` | v1 `Muted` and `Dim`, stepped toward Text until they meet the targets in §2.1 |
| `AccentHi`, `AccentDeep` | `AccentLight` and `AccentDark`, else Accent mixed 35 % toward white or black |
| `AccentAlt` | `Info` |
| `AccentText` | Accent stepped toward white (dark) or black (light) until ≥ 6 on Surface |
| `OnAccent` | Dark ink (Frame mixed 40 % toward black) or white, whichever has the higher **minimum** over Accent and AccentHi. If it is still below 4.5, AccentHi is moved toward Accent until it passes. |
| `Focus` | AccentHi (dark mode) or AccentDeep (light mode), stepped to ≥ 3 over Sheet |
| Status, `*Soft`, `OnStatus` | Status colours stepped to ≥ 4.5 on Surface. Soft = mix(Surface, status, 0.15). OnStatus = dark ink (dark mode) or white (light mode). |

Light mode is detected by the relative luminance of `Sheet` being above 0.5. In light mode:
- the lit edge is off;
- platters get a 1 px `Border` stroke (shadows are not enough on white);
- glass veils flip to dark (they use `Text`);
- the tooltip is inverted (`Text` fill with `Sheet` text).

**Accent override** (`Theme.setAccent(color)`, Appearance → Accent). It replaces `Accent` and re-derives `AccentHi`, `AccentDeep`, `AccentText`, `OnAccent`, `AccentSoft` and `Focus` with the rules above, on top of any theme. The picker offers:
- **Auto**: the theme's own accent, drawn as a plain swatch of that colour with an `A` glyph (no conic gradient);
- 8 presets: `#9970FF` `#58A6FF` `#38BDD0` `#34D399` `#F7BE4F` `#FF8A4C` `#F472B6` `#FF657C`;
- **Custom…**: the colour picker popover.

### 2.6 Light: gradients and the glow pool

| Use | Instance | Spec |
|---|---|---|
| Switch on, checkbox on | UIGradient on the track or box (white fill) | Colour `AccentHi` → `Accent`, Rotation 135 |
| Primary button | UIGradient | `AccentHi` → `Accent`, Rotation 90; pressed swaps to `Accent` → `AccentDeep` |
| Slider fill | UIGradient | `AccentDeep` (0) → `Accent` (0.55) → `AccentHi` (1), Rotation 0 |
| Nav indicator bar (3 px) | UIGradient | `AccentHi` → `Accent`, Rotation 90 |
| Progress and loader bar fill | UIGradient | `Accent` → `AccentAlt`, Rotation 0 (the only use of `AccentAlt`) |
| Lit edge | UIStroke 1 px `#FFFFFF` + child UIGradient, Rotation 90, Transparency keys `0: 0, 0.45: 0.75, 1: 1` | Stroke transparency: window 0.84, sheet 0.90, platter 0.93, Raised layers 0.86. Off in light themes. In High contrast it is replaced by a 1 px `Border` stroke (2 px `#FFFFFF` on Raised layers). |

**Glow pool.** There are 3 `ImageLabel`s per window that use the shadow asset (§2.10) tinted `Accent` at ImageTransparency 0.55. Each is re-parented to its owner, and each is hidden when its owner is hidden:

| Slot | Owner | When |
|---|---|---|
| 1 | Focus | The focus ring (keyboard or gamepad mode), or the dragged slider thumb or colour thumb |
| 2 | Nav | The selected nav indicator. This is the **only** persistent glow. |
| 3 | Moment | A 450 ms flash on a switch turning on, a primary button on hover, or the listening keycap |

There is no per-toggle glow. A theme change re-tints 3 images.

### 2.7 Radii (one UICorner per object, concentric where nested)

| Object | Radius |
|---|---|
| Window frame | **20** (24 for the phone sheet) |
| Sheet (inset 6) | 14 |
| Platter, stat tile, list body, callout | 14 |
| Pooled row hover (inset 4 inside the platter) | 10 |
| Loader card, key gate | 20 |
| Dialog, palette | 18 |
| Popover, menu, toast | 14 |
| Bottom sheet | 24 (the panel extends 28 px below the screen edge, so only the top corners show) |
| Well, input, dropdown trigger, button (32 px tall) | 10 |
| Well and button at 28 px | 8 |
| Segmented track 10, indicator 8; stepper 10 with 8 inner buttons | |
| Keycap 6; chip 6; checkbox 6; swatch 6 | |
| Nav item and selected pill | 10 |
| Switch, slider thumb, pills, badges, avatar, dock pill, reopen orb | full (height / 2) |
| Focus ring | target radius + 3 (offset 3 px) |

### 2.8 Spacing and density

Spacing uses a 4 pt scale: 2, 4, 6, 8, 10, 12, 16, 20, 24, 28, 32, 40.

`Prefs.Density` is `"Auto" | "Compact" | "Touch"`. **Auto** follows `UserInputService.PreferredInput` live (TouchFirst → Touch, Gamepad → Gamepad, otherwise Default). Gamepad is never chosen by hand: it is the Default layout plus the hint bar and larger targets.

| Metric | Compact | Default (mouse) | Touch | Gamepad |
|---|---|---|---|---|
| Row padding (vertical × horizontal) | 8 × 14 | 10 × 16 | 12 × 16 | 12 × 16 |
| Row min height, label only | 36 | 44 | 52 | 48 |
| Row min height, label + description | 48 | 56 | 64 | 60 |
| Control height (well, button, segmented, stepper) | 28 | 32 | 40 | 36 |
| Switch track, knob | 40×22, 16 | **44×24, 18** (v1 size, Name `Track`) | 52×30, 24 | 48×28, 22 |
| Slider hit band / thumb | 24 / 14 | 28 / 16 | 40 / 22 | 32 / 18 |
| Minimum hit target | 28 | 32 | 44 | 44 |
| Label / description size | 14 / 13 | 14 / 13 | 15 / 14 | 15 / 14 |
| Nav item height | 32 | 36 | 44 | 44 |
| Gap between sections | 20 | 24 | 24 | 24 |
| Section header height | 28 | 32 | 36 | 36 |

Fixed spacing:
- Sidebar 232 (rail 64), with padding 12. Topbar 52 (48 on landscape phones). Sheet inset 6.
- Page padding: 24 top, 28 sides, 40 bottom. Page column max 600 with the TOC, 680 without. TOC 160 wide, 24 gap.
- Header to first section 20. Section header to platter 8. Dividers are inset 16 on both sides.
- Text-to-control gap in a row 16. The control column width is 40 % of the row width, clamped to 160-260 for wells and 200-300 for sliders.
- Popover gap 6 from the trigger. Floating layers clamp 8 px inside the GUI.

### 2.9 Type

Faces are picked by **load cost** (from the local install's `content/fonts/families/*.json`):
- **Engine-local:** Roboto 400 and 700; RobotoMono 400; Montserrat 400, 500 and 700; BuilderSans 400, 500, 700 and 800; BuilderMono 400 and 700.
- **CDN (`rbxassetid`):** Roboto 500, Montserrat 600, every other RobotoMono weight, BuilderSans 600.

The default font set (`"Roboto"`, ARCHITECTURE_V2 open question 5) uses **two CDN faces in total**:

| Role | Family / weight | Size (mouse / touch) | Line | Colour | Face |
|---|---|---|---|---|---|
| `Page` | Montserrat SemiBold 600 | 22 / 20 (phone) | 28 | Text | CDN, preloaded, swap |
| `Dialog` | Montserrat SemiBold 600 | 18 | 24 | Text | CDN, preloaded, swap |
| `Section` | Montserrat SemiBold 600 | 14 | 20 | Text | CDN, preloaded, swap |
| `Brand` | Montserrat SemiBold 600 | 15 | 20 | Text | CDN, preloaded, swap |
| `LoaderTitle` | Montserrat Bold 700 | 16 | 22 | Text | **local** (frame 0) |
| `Label` | Roboto Medium 500 | 14 / 15 | 20 | Text | CDN, preloaded, swap |
| `Button` | Roboto Medium 500 | 14 (13 at 28 px) | 20 | per variant | CDN, preloaded, swap |
| `Nav` | Roboto Regular 400 (rest), Medium 500 (selected) | 14 / 15 | 20 | Text2 / Text | local / CDN |
| `Body` | Roboto Regular 400 | 13 / 14 | 18 | Muted | local |
| `Caption` | Roboto Regular 400 | 12 | 16 | Text2 or Muted | local |
| `Status` (loader) | Roboto Regular 400 | 13 | 18 | Muted | local |
| `Value` | RobotoMono Regular 400 | 13 / 14 | 18 | Text | local |
| `Stat` | RobotoMono Regular 400 | 26 | 32 | Text | local |
| `Key` (keycaps) | RobotoMono Regular 400 | 12 | 16 | Text | local |

- **Weights in use:** Roboto 400, 500 and 700 (700 only for the default-value emphasis in menus); Montserrat 600 and 700; RobotoMono 400. There is no ALL CAPS anywhere, no letter spacing and no size below 12.
- **Preload and swap.** `theme/Fonts` registers each text instance with a *role*, not a face. At `CreateWindow`, `Fonts.preload()` runs `TextService:GetTextBoundsAsync` for Roboto 500 and Montserrat 600 in two `task.spawn`s; these are the only yields, and they are off the caller's thread. Until a face resolves, its roles render with the local stand-in: Roboto 400 for 500, and Montserrat 700 for 600. On resolve, one repaint swaps `FontFace` for those roles only. Widths differ by less than 3 %, and nothing re-lays-out because every label truncates or wraps.
  - The loader's ready rule waits for both faces (or 800 ms since `CreateWindow`, whichever is first), so in practice the window is never seen with stand-ins.
- **Other font sets** keep v1's names (`GetFonts`):
  - **BuilderSans** is the zero-fetch set: BuilderSans 400/500/700, BuilderMono 400, and Montserrat 700 for display.
  - Ubuntu, Condensed (RobotoCondensed), Technical (SourceSansPro plus RobotoMono) and Gotham (GothamSSm) map their roles onto their own weights.

### 2.10 Elevation and the one shadow asset

| Level | What | Shadow | Edge |
|---|---|---|---|
| E0 | Window frame | `ShadowWindow`: offset (0, 20), spread 56, ImageTransparency 0.35 | Lit edge (0.84) |
| E0.5 | Sheet | none | Lit edge (0.90) |
| E1 | Platters, stat tiles | **none** | Fill step, plus a lit edge (0.93) in dark themes or a `Border` stroke in light themes |
| E2 | Popover, menu, toast, dialog, palette, loader card, dock, quick dock, keybind list | `ShadowFloat`: offset (0, 12), spread 36, ImageTransparency 0.45 | Lit edge (0.86) |
| HC | All levels | **no shadows** | A 1 px `Border` stroke (platters) or a 2 px white stroke (E0 and E2) |

**Asset `argon/shadow-hollow`** (one rbxassetid, 192×192 PNG, uploaded once and moderated once):
- A rounded rect of radius 20 at (56, 40)-(136, 120) casts a shadow offset (0, 20) with Gaussian σ 18 at alpha 0.6.
- The casting rect itself is then **erased**, so the centre is transparent and the PNG is a ring.
- `SliceCenter = Rect(76, 60, 116, 100)`. The ImageLabel sits at `target.Position - (56, 40)` with size `target.Size + (112, 112)`.
- Because the hole matches the window rect exactly, including the offset, the shadow never darkens the game seen through the translucent window.
- The same image tinted `Accent` is the glow (§2.6), and tinted `Accent` at 0.70 it is the loader orb's bloom.
- If the asset fails to load, nothing breaks: shadows and glows are simply absent.

Asset `argon/checker` (16×16, Tile 8 px) backs the alpha strip of the colour picker. It is the only other image the library ships apart from the Lucide sheets. The v1 base64 atlas and logo (v1 L97-156) are removed.

### 2.11 Motion

There is one `Motion` module (ARCHITECTURE_V2 §4.7) with one Heartbeat spring stepper, `a = -ω²(x - target) - 2ζω·v`. It disconnects when nothing moves.

| Token | Spec | Used for |
|---|---|---|
| `hover` | 100 ms Quad Out | Hover fills, icon tints |
| `press` | 60 ms; UIScale 0.97 on **buttons, keycaps and chips only** | Never on rows or text-bearing tiles, which would make glyphs re-snap |
| `state` | 140 ms Quart Out | Colours: track, check, label, stroke |
| `spring.snappy` | ζ 0.75, ω 24 (about 3 % overshoot, settles in about 0.25 s) | Switch knob, segmented indicator, nav indicator, focus ring, slider snap, chip row |
| `spring.gentle` | ζ 0.85, ω 18 (about 1 % overshoot, 0.38 s) | Window open, dialog, loader card, ghost morph, toast enter, bottom sheet |
| `spring.dock` | ζ 0.62, ω 18 (about 8 %) | Dock pill and reopen orb edge snap **only** |
| `knob.stretch` | The knob widens 18 → 24 px while pressed, then springs back on release | Switch |
| `pop.in` / `pop.out` | 160 ms Quint Out, UIScale 0.96 → 1 from the anchor side / 100 ms Quad In | Popover, menu, picker |
| `veil` | 140 ms Quad Out | The content veil on pop-in (starts at 40 ms), tab switch and hand-over |
| `rise` | 180 ms Quint Out, 6 px | Tab content, hand-over stagger (30 ms) |
| `dialog` | 220 ms in (gentle) / 140 ms Quad In out; scrim 180 ms | Dialog, palette, key gate |
| `toast` | in: gentle spring from 16 px plus a 120 ms veil; out: 140 ms fade of a pre-collected list (≤ 8 targets), then a 180 ms height collapse | Toasts |
| `tooltip` | 120 ms; delay 400 ms (mouse), 600 ms (focus), 0 ms when moving between tips within 300 ms | Tooltip |
| `ghost` | 260 ms gentle spring, Size and Position only | Loader hand-over, dock ↔ window morph |
| `loops` | Spinner 800 ms per turn (Linear); orb ring 900 ms per turn; orb bloom 1.6 s Sine (T 0.70 ↔ 0.85); skeleton 1.2 s (UIGradient Offset); keybind capture drain 5 s Linear | Each loop runs only while its owner is visible and pending |

**No subtree opacity.** Fading a subtree means one tween per descendant, so it is banned. The patterns are:
- **Pop-in:** the panel appears opaque under its UIScale pop, and a `Raised`-coloured *content veil* (one Frame, the topmost child) fades from T 0 to 1.
- **Tab switch:** a `Sheet`-coloured veil over the page fades out while the new page rises 6 px.
- **Exit fades** (toast, tooltip) tween at most 8 pre-collected objects.

**Reduced motion** (`Prefs.ReducedMotion`, or the host's `SetReducedMotion`):
- springs become instant;
- fades are capped at 100 ms;
- rises are 0 px;
- loops stop, so the orb ring stands still and the skeleton is static;
- glow flashes are skipped.

### 2.12 Icons

- Lucide glyphs come from `icons/IconData` (ARCHITECTURE_V2 §5.5): about 60 core glyphs resolve in O(1), and the full set of 1,573 is decoded lazily after open. There is no HttpGet.
- Sizes: 14 (chips, inline), 16 (rows, menus, section headers), 18 (nav, topbar), 20 (rail, toast type), 24 (empty states).
- Glyphs are tinted with `ImageColor3`. Default `Text2`; `Text` when active; status colours in toasts and callouts.
- Host tab icons accept Lucide names, `rbxassetid://`, or numbers (Rayfield).

---

## 3. The shell

### 3.1 ScreenGui and layer order

This supersedes the table in ARCHITECTURE_V2 §7.1. Layers are still created lazily, and `CreateWindow` still creates only `Base` and `Boot`.

| ZIndex | Layer | Holds | Why it sits here |
|---|---|---|---|
| 1 | `Base` | Shell (shadow + `Main`), dock pill, reopen orb, quick dock, Modal unlock button | |
| 2 | `Overlay` | Keybind list, watermark, player list | HUD under everything interactive |
| 3 | `Toast` | Toast stack, Undo pill | **Below** modals and popovers: a toast never covers the palette, a dialog, a sheet or a menu |
| 4 | `Modal` | Scrim, dialog, palette, key gate, phone "More" sheet | |
| 5 | `Popover` | Catcher, popover host, context menu, bottom sheets | Above Modal, because dialogs and the palette can open pickers |
| 6 | `Tooltip` | Tooltip singleton | |
| 7 | `Boot` | Loader card, ghost | Above everything while loading |

- **The focus ring has no layer.** It is one Frame that is **re-parented into the layer that owns the current focus trap** (Base, Modal or Popover) with the top ZIndex there. When a modal opens, focus moves into it and the ring moves with it, so the ring of a background control can never draw over a scrim. This was Native's bug.
- The ScreenGui uses `ScreenInsets = CoreUISafeInsets` (pcall) and `ZIndexBehavior = Sibling`. Every layer root has the same `UIScale` (the interface scale).
- **Phones:** while the portrait sheet is shown, toasts are rendered as **compact pills** that dock above the bottom tab bar (§7.6). They never overlap the sheet header (search, minimise), the palette input or the reopen orb.

### 3.2 Window anatomy (desktop)

```
Shell                 Frame, transparent; drag moves this one object
├ Shadow              ImageLabel argon/shadow-hollow (§2.10)
└ Main                Frame  Frame colour, T 0.14, UICorner 20, ClipsDescendants false
  ├ LitEdge           UIStroke 1 px white T 0.84 + UIGradient (§2.6)
  ├ Sidebar           Frame, transparent, 232 wide (64 in rail)
  │ ├ Brand           logo plate 28 (r 8) + name (Brand) + subtitle (Caption, Text2); drag handle
  │ ├ SearchTrigger   36 tall, GlassHover fill, r 10: search icon, "Search", keycaps Ctrl K
  │ ├ Nav             ScrollingFrame: group captions + items + one shared Indicator
  │ ├ Pinned          group of mirrored mini controls (§8.4), hidden when empty
  │ └ Profile         avatar 28 (rbxthumb) + display name + @name; opens the account menu
  ├ Sheet             Frame Sheet, UICorner 14, inset 6 (top, right, bottom); lit edge 0.90
  │ ├ Topbar          52: breadcrumb, status chip, bell, appearance, minimise
  │ ├ PageHost        one ScrollingFrame per mounted tab (inactive ones are Parent = nil)
  │ ├ TOC             160 wide, "On this page" scroll-spy (wide layout only)
  │ ├ HintBar         40, gamepad only
  │ └ PageVeil        Sheet-coloured Frame for tab switches
  ├ ResizeGrip        16×16 at the bottom-right (desktop only)
  └ Veil              Frame-coloured Frame for the hand-over
```

**Default size.** Width `max(min(gui.X - 160, 1080), min(720, gui.X - 16))`, height `max(min(gui.Y - 110, 700), min(440, gui.Y - 16))`, centred. A 1440-wide GUI gets 1080 (the Wide layout with TOC); 1180 gets 1020 (Standard); 860 gets 720 (Rail). `SetSize` keeps v1's clamps. The minimum is 560 × 400, and below it the window switches to the rail layout.

### 3.3 Sidebar

The sidebar sits on glass, so it uses only `Text` and `Text2`.

| Part | Spec | States |
|---|---|---|
| **Brand** | Logo plate 28×28 (r 8): the host logo, or the default Argon mark, over a `Surface` plate with a lit edge. Name in Brand 15 `Text`; subtitle in Caption 12 `Text2`, sentence case as given. Click opens the account menu; double-click recentres the window. | — |
| **SearchTrigger** | 36 tall, r 10, `GlassHover` fill. Search icon 16 `Text2`, "Search" 13 `Text2`, keycaps `Ctrl` `K` on the right (in gamepad mode, a `Y` glyph). Opens the palette. | hover T 0.92; focus ring |
| **Group caption** | 12 `Text2`, 8 px top and 4 px bottom margin, sentence case. Comes from the tab option `Group = "Tools"`. Tabs without a group fall under no caption. | — |
| **Nav item** | 36 tall (density table), r 10, padding 0 × 10: icon 18 + 10 gap + label (`Nav` role) + badge on the right. | rest: `Text2`, icon `Text2`; hover: `GlassHover`; selected: shared **Indicator** = a `GlassSelected` pill plus a 3 × 16 bar at x 0 with the `AccentHi→Accent` gradient plus glow slot 2, label `Text` Medium, icon `Text`; pressed: `GlassSelected` at T 0.86; focus ring |
| **Badge** | `Tab:SetBadge(n \| "New" \| true \| nil)`. A count uses a mono 12 pill (`AccentSoft` fill, `AccentText`), min 20 × 18. "New" uses the same pill. `true` is a 6 px `Accent` dot. | — |
| **Indicator motion** | The Indicator Frame springs (`spring.snappy`) to the selected item's Position/Size. When the item scrolls, the indicator is a child of the Nav canvas, so it follows for free. | |
| **Pinned** | Caption "Pinned", then one 32 px row per pin: icon 16, label 13 `Text2`, a mini control on the right. A switch is drawn 28×16. A button shows a play icon. A keybind shows its cap. **Bound to the element's state object**, so the mirror and the real control can never disagree (§8.4). | |
| **Profile** | Avatar 28 (`rbxthumb://type=AvatarHeadShot&id=…&w=48&h=48`, with an initials circle until it loads), display name 13 `Text`, `@name` 12 `Text2`, chevron. Opens the account menu: Settings, Keybinds, Profiles, Hide UI (shows the key), Unload. | |
| **Collapse** | A chevron button beside the brand collapses to the rail. The choice persists in `Prefs.SidebarCollapsed`. | |

**Rail (64).**
- Logo plate only, a 44×44 search icon button, and 44×44 nav icon buttons with the same indicator, now 44×44 with the bar on the left.
- A badge becomes a dot at the icon's top-right.
- The Pinned group collapses to a single pin icon that opens the quick dock popover.
- Tooltips show the tab name and its `Ctrl+N` shortcut.

### 3.4 Topbar (52)

Left to right:
- **Breadcrumb:** the group (13 `Text2`), then a `chevron-right` 14, then the tab name (14 Medium `Text`). With no group, only the tab name shows. In gamepad mode, `LB` and `RB` glyph caps flank the tab name.
- *(flex space)*
- **Status chip:** `Window:SetStatus(text?, tone?)`, 24 tall, r full. A 6 px tone dot plus 12 `Text2`, on a `<Tone>Soft` fill. Tones are `success`, `warning`, `danger`, `info` and `neutral`. It replaces v1's fake LIVE pill.
- **Bell:** 32×32 icon button. A 6 px `Danger` dot when there is unread inbox content. Opens the inbox popover (§7.6).
- **Appearance:** 32×32 `palette` icon. This is v1's `ThemeButton`, and it opens the Appearance popover (§7.8).
- **Minimise:** 32×32 `minus`. Hides the window (§3.7).

Interaction:
- The topbar's empty area and the sidebar brand are the **drag handle**. Dragging starts after a 6 px threshold and tracks only the starting InputObject (ARCHITECTURE_V2 §6.2). The window is clamped so at least 64 px of the topbar stays on screen. Position persists.
- **Resize:** the grip at the bottom-right, with a `Drag` session. Live layout runs on Heartbeat. Size persists.
- A `BorderSoft` hairline under the topbar appears only once the page has scrolled more than 4 px. The line is not structural; the page header scrolls under it.

### 3.5 Page

- **Header.** Title (`Page`, 22) and an optional tab description (`Body`, `Muted`, at most 2 lines).
  - On the right: the **changed chip** "9 changed · Reset tab". It is a 28 px text-button pair with a 6 px `AccentText` dot. It is hidden when nothing has changed.
  - Reset tab opens a Confirm when more than 3 values change. Otherwise it resets at once with an Undo pill.
- **Section header** (32). A 16 px icon (`Text2`, optional), the title (`Section`, `Text`), and an optional count chip. On the right:
  - "Reset section" (12 `Text2` text button). It is visible when the section has changes and the pointer is over the section or focus is inside it. It is always visible on touch.
  - The collapse chevron when the section has `Collapsible = true`.
- **Platter.** `Surface`, r 14, lit edge (or `Border` in light themes), no shadow. Rows stack inside with **inset dividers** (1 px `BorderSoft`, inset 16 on both sides, hidden above the first row).
- **Pooled hover.** One `Hover`-filled Frame plus UICorner 10 per platter. It moves instantly to the hovered row (inset 4) and fades in on the `hover` token. Rows have no fill, stroke or corner of their own. On touch it appears only while the finger is down.
- **TOC** (wide layout). "On this page" caption 12 `Text2`, then one 28 px item per section (13 `Text2`; the current one `Text` with a 2 px `Accent` bar on its left). Scroll-spy comes from `CanvasPosition`. A click smooth-scrolls through a tweened NumberValue (`rise` timing, 300 ms). A footer hint: "Right-click any row for reset, copy and pin" (touch: "Hold any row for options").
- **Section chip row** (standard, rail and phone layouts, and only when the tab has 3 or more sections). It is a horizontal ScrollingFrame under the page header: 28 px chips, 13 `Text2`, r full, the current chip in `GlassSelected`-style `Active` fill. It is sticky under the topbar once scrolled, with the same scroll-spy.
- **Empty tab:** an icon 24, "Nothing here yet" 14 Medium, and the host's empty text 13 `Muted`.

### 3.6 Layouts and breakpoints

The layout is decided from `layers:guiSize()` (inset-aware) and `Platform` (input kind). It is re-evaluated on resize and on `PreferredInput` change.

| Layout | Rule | Shape |
|---|---|---|
| **Wide** | Window width ≥ 1080, not phone | Sidebar 232; page column 600 + TOC 160 |
| **Standard** | 760 ≤ window width < 1080 | Sidebar 232; page column up to 680; section chip row |
| **Rail** | Window width < 760, or the user collapsed the sidebar | Rail 64; chip row |
| **Phone landscape** | Touch and short side < 500 and GUI width ≥ 600 | The window fills the GUI minus 8 px; rail 64 (no search button: search lives in the topbar, which frees a nav slot); topbar 48 (search and minimise icons, tab name 18); Touch density; chip row; every popover becomes a bottom sheet (a centred 560 px column); toasts as pills |
| **Phone portrait** | Touch and GUI width < 600 | A full-screen sheet under the insets (r 24 top corners only); header 52 (logo, tab name 18, search, minimise); a bottom tab bar; Touch density; stacked rows; bottom sheets; toast pills; overlays off |

**Bottom tab bar** (portrait).
- 64 tall plus the bottom inset, on the `Frame` colour at the material's transparency, with a lit top edge.
- Up to 4 tabs plus **More** (the More bottom sheet lists every tab). Each tab is a 24 px icon over a 12 px label.
- The selected tab gets an M3 **pill indicator**: 56×28, `AccentSoft`, r full, behind the icon, moved on `spring.snappy`. Its icon is `AccentText` and its label `Text`.

**Stacked rows** (portrait, or any row narrower than 420 px). Wide controls (Slider, Input, Dropdown, ColorPicker, TextArea, Segmented with more than 3 options) move under the label at full width. Switch, Checkbox, Stepper and Keybind stay inline.

### 3.7 Show, hide, toggle key, dock, reopen orb, quick dock

- **Toggle key.** Default `Insert` (v1). `ToggleUIKeybind`, `SetToggleKey`, and the Settings row "Menu key" all write `Prefs.MenuKey`. The gamepad binding is optional: Settings → "Pad menu button" offers **Hold View (0.4 s)** or None (ARCHITECTURE_V2 open question 4).
- **Hide** (key, minimise, or the account menu). It runs a 260 ms ghost morph from the window rect to the dock rect. The window is hidden, not destroyed. Popovers, tooltips and the palette close first.
- **First hide** in a session raises a toast: "Argon is hidden. Press Insert to reopen" (with the actual key name). On touch it says "Tap the Argon button to reopen". It is shown once per profile (`Prefs.SeenHideHint`).
- **Dock pill (keyboard and mouse).** 44 tall, r full, `Frame` at the dock transparency, lit edge, `ShadowFloat`. It holds: logo 24, name 13 Medium, the key cap (`Ins`), and a restore button.
  - It is shown when `OpenButton = "always"`, or when `OpenButton = "auto"` and the toggle key is `None`. Otherwise PC users get no pill, only the hint toast.
- **Reopen orb (touch).** 56×56, r full, the logo 28, and a 12 px key hint underneath only on keyboard devices. It is always shown on touch while the window is hidden (`OpenButton = "auto"`).
- **Placement and drag** (pill and orb):
  - default: the left edge at 30 % height, clear of the thumbstick (bottom-left) and the jump button (bottom-right);
  - dragging starts after 6 px (`UIDragDetector` where it exists, otherwise the manual InputObject drag);
  - on release it snaps to the nearest left or right edge on `spring.dock`, and the position persists in `Prefs.DockPosition`.
- **Quick dock.** Pinned controls (§8.4), at most 6 on PC and 4 on touch, shown **next to** the pill or orb as a vertical stack of 40 px labelled chips while the window is hidden:
  - a switch: mini switch 28×16 + label 13;
  - a button: icon + label;
  - every chip has a **text label** (truncated at 14 characters), never an icon alone.
  - The stack opens toward the screen centre and is never placed at the bottom centre (the Roblox hotbar).
- **Mouse unlock.** While the window is visible, a 1×1 `TextButton` with `Modal = true` sits in `Base`, so first-person and shift-lock games release the cursor. `MouseUnlock = false` opts out (ARCHITECTURE_V2 §10.5).

### 3.8 Focus mode, keyboard and gamepad

**Focus mode** is engaged by:
- the first arrow key or Tab while the pointer is over the window, or while focus is already active;
- any gamepad input while the window is visible.

The mouse leaving the window and moving for 300 ms disengages it. While it is active, the focus inputs are sunk with `ContextActionService:BindActionAtPriority` (Core + 1), so the character does not move.

**Ring.** One Frame: transparent fill, UIStroke 2 px `Focus`, UICorner = target radius + 3, offset 3 px outside the target, plus glow slot 1. It springs between targets on `spring.snappy`. It is shown only in focus mode (focus-visible), never on mouse clicks.

**Model.** Focus moves **in reading order** within the page, which is unambiguous because of the single column. It moves spatially between the sidebar, the page and the TOC. Inside a row, the row is the target; the row's control receives Left, Right, Space and Enter.

| Key (keyboard) | Pad | Action |
|---|---|---|
| ↑ ↓ (Tab, Shift+Tab) | D-pad ↑ ↓ | Previous or next row (crosses section boundaries; skips locked rows but announces them in the hint bar) |
| ← → | D-pad ← → | Adjust the focused control: slider ± Increment, stepper, segmented, switch off and on, dropdown previous and next option. On the sidebar, ← → move between the sidebar and the page. |
| Shift + ← → | (hold RT) | Step × 10 |
| Home / End | — | Minimum or maximum |
| Space / Enter | A | Activate: toggle, press, open the picker, start capture |
| Backspace | B | Close the topmost layer (§6.1 close-key policy), then leave focus mode |
| Shift+F10 or the context-menu key | X | Context menu for the focused row |
| Ctrl+K or / | Y | Command palette |
| Ctrl+1…9, Ctrl+[ ] | LB / RB | Switch tab |
| Ctrl+C / Ctrl+V | — | Copy or paste the focused row's value |
| Ctrl+Z | — | Undo the last reset or paste (while its Undo pill is alive) |

**Hint bar** (gamepad, 40 px, bottom of the sheet). It changes with the focused element, and the glyphs come from `UserInputService:GetImageForKeyCode`, so PlayStation users see their own symbols:
- a switch: "A Toggle · X Options · B Back · Y Search";
- a slider: "← → Adjust · A Type value · X Options";
- a dropdown: "A Open · X Options".
- When the palette is open: "A Go · X Run · B Close".

Traps:
- Dialogs, the palette, sheets and popovers trap focus.
- Closing returns focus to the trigger.
- A tooltip for the focused row shows after 600 ms.

### 3.9 Tab switching and lazy tabs

- **Switching.** The `PageVeil` (`Sheet` colour) snaps to T 0 over the page. The new page is parented and set to Y + 6. The veil fades to T 1 on the `veil` token, and the page rises on the `rise` token. No CanvasGroup and no per-descendant tweens. Popovers, menus and tooltips close (`layers:closeAll("tab")`).
- **Lazy mount.** If the target tab is not mounted, the scheduler mounts it first, at 8 ms per frame for that tab. If the mount takes more than 150 ms, the page shows **skeleton rows**: platters with 2 or 3 `Hover`-coloured bars per row and a 1.2 s shimmer (one UIGradient Offset tween per platter). The topbar also shows a 2 px `Accent` progress hairline. Rows replace skeletons section by section as they mount, with no veil.
- **Warm tabs** (mounted in the background after the reveal) open instantly.
- The last selected tab persists in `Prefs.LastTab` and is restored at the reveal if it exists by then.

---

## 4. The loader

### 4.1 Contract

`CreateWindow` never yields (except with the opt-in key gate, §4.8) and never touches the network. In order (ARCHITECTURE_V2 §10.1, with the design inputs here):
1. Options are normalised. Prefs are read synchronously, and theme, accent, material, font set, scale and density are applied **before the first `Instance.new`**.
2. The ScreenGui and the `Base` and `Boot` layers are created (5 instances).
3. The loader card is built in `Boot` at transparency 1 (≤ 26 instances). It uses only engine-local faces (§2.9).
4. The font preload is spawned (Roboto 500, Montserrat 600).
5. The shell job is queued in the scheduler (loading mode, 8 ms slices). The shell is built **unparented**, at its final size.
6. The host thread is captured (`coroutine.running()`), and the window returns. Measured target: ≤ 3 ms, ≤ 30 instances.

There is no `GetUserThumbnailAsync` (the avatar is an `rbxthumb://` URL), no `HttpGet` (icons are embedded), and no base64 decode or file write.

### 4.2 Card anatomy (≤ 26 instances, 2 images)

```
Card            Frame Raised, r 20, size min(380, gui.X - 32) × 104 (auto height), centred in the GUI area
├ Corner, LitEdge (UIStroke + UIGradient), Shadow (ShadowFloat)          5
├ Orb           60×60 Frame, transparent                                  1
│ ├ Bloom       ImageLabel shadow-hollow tinted Accent, T 0.70↔0.85 loop  1
│ ├ Ring        Frame 52×52 (r full, T 1) + UIStroke 3 px + UIGradient    3
│ │             (colour AccentHi→Accent→AccentAlt; transparency keys 0:0, 0.5:0, 0.52:1, 1:1, so it draws a half arc that rotates)
│ ├ RingTrack   Frame 52×52 + UIStroke 3 px Track (the full ring)         2
│ └ Plate       40×40 r full, UIGradient AccentHi→Accent; host Logo 26 inside   3
├ Title         TextLabel Montserrat 700 16 Text (host Name or LoadingScreen.Title)   1
├ Status        TextLabel Roboto 400 13 Muted, counts inline as Value runs (RichText)   1
├ Percent       TextLabel RobotoMono 400 13 Text2, right-aligned, hidden while indeterminate   1
├ Bar           Frame Track 3 px, inset 20 left/right, 16 from the bottom, r full     2
│ └ Fill        Frame + UIGradient Accent→AccentAlt, r full (its own corner, so no rounded clipping is relied on)   3
└ Tip           TextLabel 12 Text2, hidden until 2 s ("Tip: press Ctrl K to search every setting")   1
```

- The **ring is pure vocabulary** (the mockup draws it with a CSS conic mask only as a stand-in for this recipe): a circular Frame's UIStroke with a hard-edged transparency UIGradient draws an arc. Rotating the gradient (`UIGradient.Rotation`, 900 ms per turn) spins it, so no half-ring sprite is needed.
- The bloom is the only loader image apart from the host logo. If it has not loaded, the orb simply has no bloom.
- **Stall and error footers** are created on demand, so they are not counted above: a `BorderSoft` divider, a message line, and two full-width 36 px buttons.

### 4.3 States

| State | Enters when | Status text | Bar | Orb | Footer |
|---|---|---|---|---|---|
| (hidden) | 0-150 ms | — | — | — | — |
| **Initial** | 150 ms, not ready. Card in: UIScale 0.94 → 1 on `spring.gentle` plus a 160 ms fade of 5 objects. | "Starting" | Indeterminate: a 30 % segment moving within the track, with no overflow clipping (its width grows and shrinks at the ends) | Ring spins, bloom breathes | — |
| **Waiting** | The host thread is suspended, **no tab exists yet**, and there has been no activity for 250 ms | "Waiting for script" | Indeterminate | Same | — |
| **Building** | Create* work is counted for the active tab | "Building Combat · 155 of 212" (the counts in `Value` mono via RichText) | **Determinate** 0-85 % | Same | — |
| **Restoring** | `LoadConfiguration` is running (45 ms slices) | "Restoring settings · 72 of 96" | 85-100 % | Same | — |
| **Host-driven** | The host called `SetLoadingProgress(f, status)` (manual mode) or `SetLoadingStatus(text)` | The host's string **as given** (no upper-casing, D-fix) | `f` mapped onto 0-85 %, monotonic | Same | — |
| **Tip** | 2 s after the card shows | — | — | — | The tip line fades in (first `LoadingScreen.Tips` entry, rotating every 4 s; the default teaches Ctrl K) |
| **Stalled** | 8 s with no progress | "No progress for 8 s" with a clock icon 14 | Frozen | Ring slows to 1.8 s per turn | **Open now** (Primary) + **Copy log** (Secondary). The log lists the last 20 status lines with timestamps. |
| **Error** | `Window:Build(fn)` caught an error | "Build failed on Visuals" | Fill turns `Danger` | Ring `Danger`, stops; a 16 px `Danger` badge with `x` at the orb's bottom-right | A mono 12 error box (`DangerSoft`, r 10, at most 4 lines, scrollable) plus **Open anyway** (Primary) + **Copy error** (Secondary) |
| **Ready** | §4.5 | "Ready" | 100 % | Ring completes into a full circle (200 ms), then hand-over | — |

Status changes crossfade over 120 ms by tweening TextTransparency on the Status label only. Progress never moves backward: a lower host value is ignored.

### 4.4 Progress semantics

- **Counted work:** `units = mounted rows of the active tab + 1 for the shell`. The total is known once the host's synchronous build has registered the active tab (the first tab, or `Prefs.LastTab` if it exists by then).
- **Mapping:** shell plus active tab 0-85 %; restore 85-100 %; host fractions replace the counted 0-85 % part.
- **Determinate only with a known total.** Before that, the bar is indeterminate, there is no percent, and the status is "Starting" or "Waiting for script".
- **Other tabs never count.** They mount after the reveal.

### 4.5 Ready, and what happens when the host never reports

Ready requires **all** of:
- the shell is mounted;
- the active tab is mounted, or no tab exists;
- both fonts have resolved, or 800 ms have passed since `CreateWindow`;

and **one** of:
- (a) `FinishLoading()` was called;
- (b) the host thread is `dead`;
- (c) at least one tab exists and there has been no library activity (Create*, progress, restore) for **250 ms**.

| Host behaviour | Result |
|---|---|
| A synchronous build of any size | The thread is dead within the same frame, the active tab mounts in 1-6 frames, and **no card** is shown. The window enters at about 0.1-0.2 s. |
| A build followed by `LoadConfiguration()` | The restore keeps the thread busy, so the card appears at 150 ms in "Restoring", and the window reveals when the restore ends. |
| The host yields **before** creating any tab (`HttpGet` of its own data, `WaitForChild`) | Rule (c) cannot fire with zero tabs. The card shows "Waiting for script", then the stall footer at 8 s. |
| The host yields **in the middle** of the build | After 250 ms of quiet the window opens with the tabs built so far. Later tabs slide into the sidebar on the `rise` token, and later rows mount into their tabs. The active tab does not change under the user. |
| The host never calls `FinishLoading` in manual mode | The stall footer appears at 8 s. The watchdog opens the window 30 s **after the last progress** (D11). |
| The host thread dies with 0 tabs | The window opens with the empty state "This script hasn't added any tabs yet". |
| `LoadingScreen = "never"` | No card. The window is revealed at ready with the entrance animation. |
| `LoadingScreen = "always"` | The card shows at 0 ms instead of 150 ms. |
| Once shown | The card stays at least `LoadingMinimum` (0.4 s), so it never strobes. |

### 4.6 Hand-over (≈ 0.45 s; nothing with content is ever resized)

| t (ms) | Step |
|---|---|
| 0 | The card's content (orb, title, status, percent, bar, tip) fades out over 120 ms. That is 10 pre-collected objects. |
| 0 | An **empty ghost** is created at the card's rect: a Frame in the `Frame` colour at the material's transparency, r 20, lit edge and shadow, and no content. |
| 0-260 | The ghost morphs Position and Size to `Main`'s rect on the `ghost` token. The card's own background hides at 0. |
| 200 | `Main` (built at its final size during loading) is parented with its **Veil** (the `Frame` colour, T 0) on top. The ghost is destroyed at 260. |
| 220-400 | The Veil fades to T 1 (180 ms). The sidebar, topbar and page rise 6 px with a 30 ms stagger (`rise`). |
| 460 | Overlays, the dock, the hint bar and queued toasts appear. `OnLoaded` fires and the scheduler switches to interactive mode. |

**Fast path** (no card was shown): the Veil plus a UIScale 0.97 → 1 on `Base` (`spring.gentle`, 240 ms).

**Reduced motion:** a 120 ms Veil fade only.

### 4.7 Worked timeline: a 500-control hub (10 tabs × 50), synchronous, with `LoadConfiguration`

| t | What happens | On screen |
|---|---|---|
| 0 ms | `CreateWindow`: 2-3 ms, 26 instances, card at T 1, fonts preloading | Game only |
| 0-5 ms | 500 `Create*` calls: state only, about 1 µs each in the bench (`bench/v2_state_element_cost.luau`) | Game only |
| frame 1-2 | Shell mounted (≤ 8 ms per frame) | Game only |
| frame 2-7 | Active tab: 50 rows, about 6 frames at 8 ms | Game only |
| ≈ 0.12 s | `LoadConfiguration` starts (240 flags, 45 ms slices) | Game only |
| 150 ms | Not ready yet, so the card shows | "Restoring settings · 38 of 240", 87 % |
| ≈ 0.40 s | Restore done, and fonts resolved long before | Ready |
| 0.55 s | Card minimum held (150 + 400) | Hand-over |
| ≈ 1.0 s | Revealed and interactive | Window |
| +17 frames | Tabs 2-10 mount in the background at ≤ 4 ms per frame | Window stays at 60 fps |

**No startup frame exceeds about one slice (8 ms) of library work.** v1 built the same hub in 187-645 ms of uninterrupted work (perf.md §2.3), and at 1,200 controls the build grew quadratically to 1.7-2.6 s.

### 4.8 Key gate (opt-in; Rayfield `KeySystem` / `KeySettings`)

- **Shape.** The gate **morphs out of the card**. The card's Size springs from 380 × 104 to 420 × auto (`spring.gentle`), the orb shrinks to 40 px at the top-left, and the gate content fades in under a `Raised` veil.
- **Content:**
  - the title (host `KeySettings.Title` or the window name, Montserrat 700 16) and the subtitle "Enter your key to continue" (13 `Muted`);
  - a 44 px mono key field (`Well`, r 10) with a **Paste** icon button inside on the right (disabled when the clipboard is unreadable);
  - a "Remember this key on this device" checkbox (`SaveKey`);
  - the note (`KeySettings.Note`, 12 `Muted`, with a link icon when `GetKeyLink` exists);
  - **Get key** (Secondary: copies the link, then shows "Link copied" for 1.5 s) and **Continue** (Primary).
- **States:**
  - **Busy:** while `Validate(key)` runs in `task.spawn`, Continue shows a spinner and the field is read-only.
  - **Invalid:** the card shakes ±6 px (3 cycles in 0.3 s), the field stroke turns `Danger`, and the message line reads the Validate message or "That key didn't work".
  - **Accepted:** the gate morphs back into the card and loading continues.
- **Blocking** (default) yields `CreateWindow` until the key is accepted, as Rayfield does. This is the one documented yield (ARCHITECTURE_V2 §12.7).

### 4.9 Loader API (additive)

| API | Notes |
|---|---|
| `LoadingScreen = "auto" \| "always" \| "never" \| {Title, Subtitle, Logo, Tips = {string}}` | Rayfield `LoadingTitle` and `LoadingSubtitle` map to Title and Subtitle |
| `LoadingMinimum = 0.4` | Seconds the card stays once shown |
| `Loading = "manual"` / `ManualLoading = true` | v1 |
| `Window:SetLoadingProgress(fraction, status?)` | v1; switches to manual readiness |
| `Window:SetLoadingStatus(text)` | Status only, without making the bar host-driven |
| `Window:FinishLoading()` / `Window:IsLoading()` | v1 |
| `Window:OnLoaded(fn) -> Connection` | Fires after the hand-over (immediately if already open) |
| `Window:Build(fn)` | Runs `fn(window)` under xpcall. An error goes to the Error state. |

---

## 5. Rows: the shared anatomy and behaviour

Every control except Section, Divider, Space and Stat tiles is a **row** inside a section platter (ARCHITECTURE_V2 §8.8 `RowView`, amended here).

```
Root          TextButton "Control" (AutoButtonColor false, T 1, Selectable false); the hit target
├ Title       TextLabel Label role, Text, truncates (AutomaticSize none)
├ Changed     Frame 6×6 r full AccentText; created on first change           (on demand)
├ TipMarker   ImageButton info 14 Text2; only when Tooltip is set               (on demand)
├ Lock        ImageLabel lock 14 + reason chip; only when locked with a reason  (on demand)
├ Description TextLabel Body role, Muted, wrapped, at most 2 lines on desktop  (on demand)
├ StateText   TextLabel Caption "On"/"Off"; Toggle only, only with state labels (on demand)
├ Message     TextLabel 12, status colour + icon; validation and conflicts      (on demand)
└ <control>   right-aligned in the control column, vertically centred on the title band
```

- There is no per-row `UICorner`, `UIStroke` or hover Frame. The platter owns one pooled hover frame (§3.5), one `UICorner` and its lit-edge stroke.

**Text column.**
- Width is the row width minus padding, the control width and a 16 px gap.
- Descriptions wrap. The mockup uses `text-wrap: pretty`. In Luau, the control column is clamped so the text column never drops below 200 px, and if it would, the row **stacks** (§3.6). That removes the cramped early wraps and orphans the judges saw.

**Changed tracking.**
- `element.Default` is the value at `Create*` time (or `Default =` in the config). `changed = not Util.jsonEqual(value, Default)`.
- The dot sits 6 px after the title text. Clicking it resets, with an Undo pill. Its tooltip reads "Changed from default (90°). Click to reset".

**Tooltip.**
- The `Tooltip` text shows on hover over the title or the marker (400 ms), on focus (600 ms), and on a tap of the marker on touch.
- It anchors **above the title** (flips below), never over the row's own control column.

**Locked and disabled** (`Lock(reason?)`, `Unlock()`, `SetDisabled(bool)`; ARCHITECTURE_V2 §8.7).

| | Title | Control | Extra | Activation |
|---|---|---|---|---|
| Locked with a reason | `Text2` | `Disabled` colours | lock 14 + a reason **chip** (h 20, r 6, `Active` fill, 12 `Text2`, e.g. "Requires Premium") | A click shakes the chip ±3 px and shows the reason tooltip. The keyboard skips the row but the hint bar says "Locked: Requires Premium". |
| Locked, no reason | `Text2` | `Disabled` | lock 14 | Same, with the tooltip "Locked" |
| Disabled | `Disabled` | `Disabled` | none | Ignored; focus skips it |

**Context menu.** Right-click, a 450 ms long-press on touch, gamepad X, or Shift+F10 opens the row menu (§7.4). Every row supports it. Rows without a value show only the items that apply.

**Validation message.**
- `Message` sits under the description (12, an icon 12 + text) in `Danger` (error), `Warning` (conflict) or `Muted` (hint).
- Examples: "Must be between 16 and 120", "Must start with https://", and "Also used by Fly. Both will fire. [Swap] [Keep]".

**Search highlight.** When reached from the palette, the row's hover frame flashes `AccentSoft` twice (2 × 300 ms) and the focus ring pulses.

---

## 6. Components

The v1 API is unchanged for every control (config keys, defaults, callback payloads, `Set` coercion, persisted formats, ARCHITECTURE_V2 §11). The "API" lines list only what v2 adds. Instance counts are as mounted, without the description.

### 6.1 Section

- **API:** `Tab:CreateSection(nameOrTable)` (v1).
- **v2 additions:** `{Title, Icon, Description, Collapsible = false, Collapsed = false}`; `Section:Set(title)` (Rayfield gap); `Section:SetCollapsed(bool)`; `Section:Reset()`.
- **Instances:** 5 for the header (Frame, Icon, Title, ResetBtn on demand, Chevron on demand) plus 5 for the platter (Frame, UICorner, LitEdge stroke, gradient, HoverFill + corner, minus the shared ones).
- **Collapse:** the platter's Size Y is tweened with `ClipsDescendants` (the platter corner still draws, because the clip is rectangular and the corner belongs to the platter itself), using `spring.gentle`. The chevron rotates 0 → −90° on `state`.
- **Edge cases:**
  - An empty section shows nothing (no empty platter).
  - Collapsing a section that contains the focused row moves focus to its header.

### 6.2 Row (columns)

- **API:** `Tab:CreateRow(cfg)` (v1: Columns 1-4, Spacing, MinColumnWidth).
- **Layout.** A Row inside a platter splits the platter's content horizontally into equal columns separated by a 1 px vertical `BorderSoft` divider (inset 12 top and bottom). It is used for stat tiles and button groups.
- Columns stack when `(width - gaps) / cols < MinColumnWidth` (v1 rule). On phones they always stack.

### 6.3 Label

- **API:** `CreateLabel(text | {Text, Icon, Color, Style})` (Rayfield signature, ARCHITECTURE_V2 §11).
- **Anatomy:** Root (Frame) + Icon 16 (optional) + Text (Body 13, `Text2`, wrapped). **Padding 12 × 16, the same as rows** (G17). 2-3 instances.
- **Style** `"muted"|"info"|"success"|"warning"|"danger"` tints the icon (and the text for `danger`). No hover, and not focusable.

### 6.4 Paragraph

- **Anatomy:** Root + Title (Label role) + Body (Body 13, line 19, `Text2`) + optional Icon 16. Padding 12 × 16, with a 4 px gap between title and body.
- **API:** `Set(string | {Title, Content})` (D4).

### 6.5 Callout (new)

- **API:** `CreateCallout{Title, Content, Type = "info"|"success"|"warning"|"danger", Icon?, Action = {Text, Callback}?, Dismissible?}`.
- **Anatomy:** a box inset 8 inside the platter with r 10 and a `<Type>Soft` fill. Icon 18 in the status colour, Title 14 Medium `Text`, Body 13 `Text2`, an Action as an `AccentText` text button, and a Dismiss `x` 16. 5-7 instances.

### 6.6 Divider and Space

- **Divider:** a 1 px `BorderSoft` across the platter (not inset). With a label: 12 `Text2` at the left with 12 px gaps and the line flexing after it. `Set(visible)`.
- **Space:** `px` clamped to 4-80 (v1).

### 6.7 Button and ButtonGroup

**API.**
- `CreateButton{Name, Callback, Description?, Icon?, Variant = "Secondary"|"Primary"|"Ghost"|"Danger"|"DangerSoft", Shortcut?, Async?, HoldToConfirm?}`.
- `SetLoading(bool)` and `Set(name)` (Rayfield).
- `Tab:CreateButtonGroup{Buttons = {{Name, Callback, Variant, Icon}, …}}` (new): 2-3 buttons side by side in one row.

| Variant | Look |
|---|---|
| **Secondary** (default, v1 look) | An **action row**: the whole row is the button. Title + optional description + leading icon 16. On the right a `chevron-right` 16 `Text2`, or the `Shortcut` keycap. Hover is the pooled fill; pressed is `Active`. |
| **Primary** | A filled pill button, 36 tall (Touch 44), full row width inside the platter padding 8 × 12, r 10. `AccentHi→Accent` gradient, `OnAccent` label (Button role), and glow slot 3 on hover. |
| **Ghost** | Same size, no fill, label `AccentText`; hover fills `Hover` |
| **Danger** | `Danger` fill, `OnStatus` label |
| **DangerSoft** | `DangerSoft` fill, `Danger` label |

States:
- **Hover, press:** press is UIScale 0.97 on pill variants only.
- **Focus:** the ring.
- **Busy** (`SetLoading` or `Async`): a spinner 16 replaces the icon or chevron, the width is frozen, and re-entry is blocked.
- **Success flash:** when an Async callback returns true, a check icon shows for 1.2 s.
- **Disabled.**
- **Hold-to-confirm:** a fill sweeps across the button over 0.8 s; release before the end cancels. The label reads "Hold to delete".

Interactions:
- Mouse: click.
- Keyboard: Space or Enter.
- Touch: tap (hold for HoldToConfirm).
- Pad: A.

**Instances:** action row 4; pill 6.

### 6.8 Toggle (switch and checkbox)

**API.** v1, plus `Style = "Switch"|"Checkbox"` and `Keybind = "F"` (attaches a bind that flips it; shown as a keycap left of the switch).

**Switch anatomy (8 instances):**
- Root, Title;
- Track (Name `Track`, 44×24, r 12; fill `Track` when off, white with the gradient when on) + UICorner + UIGradient (enabled only when on);
- Knob (18, r 9, `#FFFFFF`; in Daylight a 1 px `Border` stroke) + UICorner;
- Check (`ImageLabel` Lucide `check` 12, `AccentDeep`, ImageTransparency 1 when off).

States:

| State | Track | Knob | Other |
|---|---|---|---|
| Off | `Track` | left (x 3), white at 88 % (ImageTransparency 0.12 on a white fill) | StateText "Off" `Text2` |
| On | gradient `AccentHi→Accent` | right, white | Check visible; StateText "On" `Text`; glow slot 3 flash 450 ms |
| Hover | Track lightens one step (`Active`) | — | Pooled row hover |
| Pressed | — | stretches to 24 px toward the travel direction | — |
| Focus | — | — | Ring on the row |
| Disabled / Locked | `Disabled` at 50 % | `Disabled` | Lock chip |

- **State labels** (On/Off text, 12) show when `Prefs.StateLabels = "Auto"` and the density is Touch or Gamepad or the theme is HighContrast, or when it is set to `"Always"`.
- **Checkbox** (6 instances): 20×20 r 6. Off: `Well` + 1 px `Border`. On: gradient + check 14 `OnAccent`. The same states apply.

Interactions:
- Mouse: click anywhere on the row.
- Keyboard: Space or Enter flips; ← off, → on.
- Touch: tap the row.
- Pad: A.
- The knob moves on `spring.snappy`, and the colour changes on `state`.

Edge cases:
- `Set` keeps v1's `v == true` coercion.
- Rapid clicks retarget the spring with no queue.
- An attached keybind obeys Lock.

### 6.9 Slider

**API.** v1, plus `OnRelease(value)`, `Ticks = auto|true|false`, and `Format = function(v) -> string`.

**Anatomy (10 instances):**
- Root, Title;
- Hit (transparent TextButton, 28 tall, spanning the groove);
- Groove (4 px `Track`, r 2) + corner;
- Fill (gradient) + corner;
- Thumb (16, white, r full, a 1 px UIStroke black at T 0.75 for definition) + corner;
- Value pill (`Well` 56×28, r 8; a TextBox in `Value` mono 13 `Text`, with the suffix in `Muted`).

**Ticks** are drawn when `(max - min) / Increment ≤ 12`: 2 px dots in `Track` at each step. They are on demand (n Frames).

States:
- Hover: the thumb grows to 18.
- Dragging: the thumb grows to 20 and takes glow slot 1, and the pill text turns `AccentText`.
- Focus: the ring is on the row, and ← → step.
- Disabled.

Interactions:
- **Mouse:** press anywhere on the hit band to jump-and-drag. The callback fires live, at most once per frame. The commit (autosave, changed dot) happens on release.
- **Wheel:** no wheel adjust. It would hijack page scroll.
- **Keyboard:** ← → step by `Increment`, Shift × 10, Home/End.
- **Typing:** click or tap the pill to type. Enter commits, Up/Down step, and focus loss commits. A value out of range **clamps and shows a 2 s hint** "Must be between 16 and 120"; a non-number reverts with "Enter a number".
- **Touch:** a horizontal-intent drag (ARCHITECTURE_V2 §6.2). Page scrolling is disabled for the drag. The thumb is 22 with a 40 px band.
- **Pad:** D-pad ← → (RT × 10); A types the value.

Edge cases:
- A reversed `Range` is swapped.
- `Increment ≤ 0` means continuous with 2 decimals.
- The maximum is always reachable.
- Suffix spacing follows ARCHITECTURE_V2 §11.

### 6.10 Stepper

- **Anatomy (8):** Root, Title, a Group (`Well` 108×32, r 10), Minus (32, r 8 inner, `minus` 16), Value (TextBox mono 13, editable), Plus.
- **States:** a button dims (`Disabled`) at its limit. Hover fills the inner button with `Hover`.
- **Interactions:**
  - Click; **hold to repeat** (350 ms, then 80 ms, faster after 1 s).
  - Keyboard ← → (Shift × 10); typing as for the Slider; pad D-pad.
  - Validation and clamping as for the Slider.

### 6.11 Segmented

- **Anatomy (7 + n):** Root, Title, Track (`Well`, r 10, padding 3) + corner, Indicator (`AccentSoft` fill, 1 px stroke `Accent` at T 0.5, r 8) + corner + stroke, and n labels (13 Medium; `Text2`, the selected one `AccentText`).
- The indicator springs to the selected label (`spring.snappy`). Selection is visible through fill, stroke **and** label colour, which fixes Precision's low-salience neutral pill.
- **Interactions:** click or tap; ← → when focused; pad D-pad.
- **Overflow:** more than 4 options or overflowing width → it renders as a Dropdown automatically, keeping the same API.
- **`Refresh`:** v1 semantics (no callback).

### 6.12 Input

**API.** v1, plus `Numeric`, `Min`, `Max`, `MaxLength`, `Validate(text) -> ok, message`, `Live`, `ClearButton = true`, `Icon`, and `Masked`.

**Anatomy (7, +2 on demand):** Root, Title, Field (`Well`, r 10, 32 tall) + corner + UIStroke 1 px `Border`, an optional leading Icon 16 `Text2`, and a TextBox (14 `Text`, placeholder `Dim`). On demand: a Clear button (`x` 14) and an EnterCap (`↵` keycap, shown while dirty).

| State | Field stroke | Other |
|---|---|---|
| Rest | `Border` | — |
| Hover | `Track` | — |
| Focused | `Focus` 1 px + glow slot 1 (soft) | Title tints `AccentText`; ↵ cap when dirty |
| Invalid | `Danger` | Message line in `Danger`: icon + text ("Must start with https://") |
| Disabled | none | Text `Disabled`; locked chip if a reason was given |
| Read-only | `BorderSoft` | Copy icon instead of Clear |

Interactions:
- The callback fires when the text changed **or** Enter was pressed (ARCHITECTURE_V2 §11).
- Typing never moves the character: TextBox focus already sinks input.
- **Touch:** the field is never auto-focused.
- **Pad:** A focuses it, which opens the on-screen keyboard.
- **Close key:** while the TextBox is focused, Backspace edits text. Clicking away or pad B (ReleaseFocus) leaves the field.

Edge cases:
- `MaxLength` shows a mono 12 counter (`Dim`, `Warning` at 90 %).
- `Numeric` with `Min`/`Max` clamps on commit and shows the range message.

### 6.13 TextArea

- Same as Input, plus a ScrollingFrame for the TextBox.
- `AutoGrow` between `MinHeight` (80) and `MaxHeight` (240). `Monospace = true` uses `Value` mono; the body otherwise stays Roboto (G-fix: no mono body by default).
- A counter shows with `MaxLength`. It commits on focus loss.
- It always stacks under its label.

### 6.14 Keybind

**API.** v1 (D3 Rayfield semantics), plus `Mode` (shown, not user-editable unless `ModeEditable = true`), `OnChanged(key)`, gamepad buttons and `MouseButton2/3`.

**Anatomy (6):** Root, Title, ModeText (12 `Text2`: "Hold", "Toggle" or "Press"), Cap (`Raised` h 24, r 6, 1 px `Border` stroke) + corner + KeyText (`Key` mono 12). In gamepad mode the KeyText becomes an ImageLabel glyph.

| State | Cap | Extra |
|---|---|---|
| Set | `Raised`, `Text` key | — |
| None | `Raised`, "None" `Dim` | — |
| Listening | `AccentSoft` fill, `Accent` T 0.5 stroke, "Press a key…" 12 `AccentText`, glow slot 3 | A 2 px `Accent` drain bar under the cap (5 s Linear). The hint line reads "Mouse buttons work · Backspace clears" (pad: "B clears"). |
| Conflict | `Raised` | Message (`Warning`): "Also used by Fly. Both will fire." with **Swap** and **Keep** text buttons |
| Active (held or toggled on) | Key `AccentText` | The keybind list row lights (§7.7) |

Capture interactions:
- Click, tap, Enter or A starts capture.
- Any key, MouseButton2/3 or pad button sets it.
- **Backspace or Delete set None.**
- A click outside or the 5 s timeout cancels and keeps the old key.
- Escape is not advertised. Pressing it also cancels, but Roblox opens its menu at the same time, so the hint never mentions it.

Conflict actions:
- **Swap** moves the other bind to this one's old key.
- **Keep** dismisses the message (both fire).
- Locked or destroyed binds never fire.

### 6.15 Dropdown (single, multi, searchable, virtualised)

**API.** v1, plus options as strings or `{Text, Description, Icon, Disabled, Divider}`, `Searchable` (auto when more than 8 options), `Source = "Players"|"Teams"`, `Options = function`, `Placeholder`, and `MaxVisibleChips = 2`.

**Trigger (7):** Root, Title, Field (`Well` 32, r 10, a 1 px `Border` stroke) + corner, Value (14 `Text`; placeholder "Select…" in `Dim`), Chevron (`chevrons-up-down` 16 `Text2`).
- **Multi:** up to 2 chips (h 22, r 6, `Raised`, 12 `Text`, with `x` 12) plus a "+N" chip. "3 selected" replaces them when the field is narrower than 160.
- **States:** hover stroke `Track`; open stroke `Focus`, chevron `Text`; disabled.

**Panel** (the pooled popover, `reuse = "dropdown"`):
- Width = max(trigger, 240), at most 360 tall. It opens below and flips above.
- **Search** (Searchable): a 36 px field at the top ("Filter 12 options", search icon). It is focused immediately on mouse and keyboard, and **never auto-focused on touch**.
- **Header (multi):** "3 of 12 selected" (12 `Text2`) on the left; **Select all · Clear** text buttons on the right.
- **List:** a VirtualList with rows of 32 (Touch 44). A row is a check (multi: checkbox 16; single: a check 14 on the selected row), an optional icon 16, Text 14, and an optional description 12 `Muted`. Hover `Hover`; keyboard highlight `Active`; disabled rows `Disabled`. Dividers are 1 px. The pool holds visible + 2 rows.
- **Empty filter:** "No options match 'flyy'" plus a **Clear filter** text button.
- **Footer hint** (keyboard mode only, 12 `Dim`): "↑ ↓ Move · Enter Select". On pad: "A Select · B Close".

Interactions:
- **Mouse:** click the trigger; click an option (single closes; multi stays open). Click outside or on the trigger closes.
- **Keyboard:** Enter, Space or ↓ opens. ↑ ↓ Home End move. Typing filters (or jumps to the first match without search). Enter selects, Space toggles (multi). Backspace (with an empty filter) or the close key closes.
- **Touch:** tap. On phones it becomes a **bottom sheet**: a grab handle 40×5, a header (title + `x`), the list at 52 px rows, Select all / Clear in the header, and a dim catcher.
- **Pad:** A opens and selects; B closes; ← → on the closed trigger step through options (single).

Edge cases:
- Unknown `Set` values are ignored.
- `Refresh` keeps v1 semantics.
- 10,000 options cost the same as 10 (virtualised).
- `Options = function` shows a spinner row while it resolves.

### 6.16 ColorPicker

**API.** v1, plus `Alpha = true`, `Presets`, and recents (shared, at most 6).

- **Trigger (6):** Root, Title, Field (`Well` 32, r 10), Swatch 20 (r 6, over the checker when alpha < 1), Hex (mono 13 `Text`), Alpha% (mono 13 `Text2`, only with Alpha).
- **Panel** (popover `reuse = "color"`, width 256):
  - **SV square** 232×140, r 10: a hue Frame, a white child with a transparency UIGradient 0→1 (Rotation 0), and a black child 1→0 (Rotation 90). Thumb 14: transparent, a 2 px white UIStroke and a 1 px black outer frame at T 0.6.
  - **Hue strip** 232×10, r full: a UIGradient with 7 keys, and a thumb 14 with a white stroke.
  - **Alpha strip** 232×10: the checker tiled, plus a colour gradient. **Thumbs travel within `[7, width - 7]`**, so they are never clipped (G17).
  - **Tabs** "Hex · RGB" (a mini segmented control). Hex is a field `#RRGGBB(AA)`; RGB is 3 number fields. Invalid input shows a `Danger` stroke and the previous value stays.
  - **Swatches:** 8 presets (the theme's accent set plus status colours) and up to 6 recents, 22 px, r 6. The selected one gets a 2 px `Focus` ring.
- **HSV state** is kept, so the hue survives a grey pick.
- **Interactions:**
  - Drag in the SV square, hue or alpha (`Drag` sessions). Each fires once per frame, and commits on release.
  - Keyboard: arrows move the SV thumb (1 %), Shift × 10; Tab cycles the parts.
  - Pad: D-pad moves the SV thumb; LB/RB adjust the hue.
  - Phone: a bottom sheet with the SV square at full width.

### 6.17 ProgressBar

- **Anatomy (8):** Root, Title, Value (mono 13 `Text2`, right), Track (6 px `Track`, r 3) + corner, Fill (gradient `Accent→AccentAlt`, r 3, its own corner) + corner + gradient.
- **Thresholds:** `{{0.9, "Danger"}}` recolours the fill solid (gradient off).
- **Indeterminate:** a segment 30 % wide moves **within** the track (its width grows from 0 at the start and shrinks to 0 at the end), so nothing overflows a rounded rail. 1.1 s InOutSine, running only while on screen.
- **Steps variant:** `Steps = 5` draws 5 segments with 3 px gaps.
- Never persisted (v1).

### 6.18 TelemetryCard and Stat

- **API:** v1 `CreateTelemetryCard` (Status, Icon, Rail kept), plus `Variant = "stat"` and `CreateStat{Label, Value, Unit, Delta, Status, Icon, Spark = {numbers}}`.
- **Stat tile anatomy (8-10):** a tile inside a Row column (no own stroke): Label 12 `Text2` + icon 14, Value (`Stat` mono 26 `Text`), Unit 13 `Muted`, a Delta pill (h 20, r full, `SuccessSoft` / `DangerSoft`, mono 12, `trending-up` / `trending-down` 12), and a Status pill.
- **Spark:** at most 12 bars, 3 px wide with 2 px gaps, height ∝ value, `Track` fill with the last bar `Accent`. Bars are used rather than rotated lines because they are cheaper.
- Live values use mono, so they never jitter.

### 6.19 List

- **API:** v1, plus keyed rows, `AddItem`, `RemoveItem`, `UpdateItem`, `EmptyText`, `EmptyAction = {Text, Callback}`, `Filter`, `MaxHeight` and `Rename = true` (ARCHITECTURE_V2 §11).
- **Anatomy:** Root, Title, an optional filter field, and a VirtualList (rows of 36, or 52 with descriptions). A row is: leading icon or avatar 24 (r 6 or full), Title 14, Description 12 `Muted`, and on the right up to **2 inline actions** (ghost icon buttons 28, shown on hover or focus on mouse, always shown on touch) plus an overflow `ellipsis` that opens a ContextMenu.
- **Selected row:** `Active` fill plus a 2 px `Accent` bar at the left (inset 6, r full).
- **Rename in place:** F2, double-click, or the menu "Rename". The title becomes a TextBox; Enter commits; the close key or click-away reverts.
- **Empty:** icon 24 `Text2`, `EmptyText` 13 `Muted`, and `EmptyAction` as a Secondary pill ("Add current position").
- **Danger actions:** `Danger` icon tint. Delete asks for a Confirm only when `ConfirmDelete`; otherwise it raises an Undo pill.

### 6.20 Image (new)

`CreateImage{Image, Height = 120, ScaleType = "Fit", Corner = 10, Caption?}` renders an image at r 10 inside the platter padding, with a Caption of 12 `Muted`.

### 6.21 Instance budget (mounted, no description)

| Control | v1 | v2 | UIStroke |
|---|---|---|---|
| Toggle (switch) | 9-10 (per-row corner + stroke + clip, v1 L1944-1947, L2283-2290) | **8** (with the check glyph) | 0 |
| Toggle (checkbox) | — | 6 | 1 (off-state box) |
| Button (action row / pill) | 7 | 4 / 6 | 0 |
| Slider | 12 | 10 | 1 (thumb) |
| Stepper | 10 | 8 | 0 |
| Segmented (3) | 12+ | 10 | 1 (indicator) |
| Keybind | 9 | 6 | 1 (cap) |
| Input | 9 | 7 | 1 |
| Dropdown (closed) | 10 | 7 | 1 |
| ColorPicker (closed) | 9 | 6 | 0 |
| Label / Paragraph | 4-6 | 2-4 | 0 |
| **Mixed average** (ARCHITECTURE_V2 workload) | ≈ 9.5 | **≈ 6.9** | **≈ 0.5 per control** (v1: 1.0+) |

There is one platter (Frame, UICorner, UIStroke, UIGradient, HoverFill, HoverCorner) per section. The `UIStroke` count stays under 0.6 per control because rows never own one.

---

## 7. Floating layers

All of them are pooled per window: the first open builds, later opens build 0 instances (ARCHITECTURE_V2 §7.3). All are `Raised`, opaque, with a lit edge and `ShadowFloat` (HighContrast: a 2 px white stroke, no shadow). All appear on `pop.in` under a content veil.

### 7.1 Popover service

- **Anchor:** the trigger's AbsolutePosition/Size, with a gap of 6. It prefers below and flips above. It is clamped 8 px inside the GUI and re-anchors on AbsolutePosition change (scrolling).
- **Catcher:** a transparent full-GUI TextButton behind the panel. It closes the panel on an outside click and **sinks** that click.
- **Phones:** every popover renders as a **bottom sheet**: grab handle 40×5 (`Track`, r full), an optional title row (16 Montserrat 600 + `x`), r 24 with the panel extended 28 px below the screen edge, a `Scrim`, and a swipe-down or tap outside to close. Landscape uses a centred 560 px column.

### 7.2 Tooltip

- **Look.** `Raised`, r 10, padding 8 × 10, max width 260, 12/16 `Text`. In Daylight it is inverted: `Text` fill with `Sheet` text.
- **Content.** A title in 12 Medium is optional. The shortcut keycaps go on the right.
- **Placement.** Above the anchor (title or marker), flipping below, and never over the anchor row's control column. Rows are single-column, so it covers at most the row above's text.
- **Timing.** `tooltip` token. It hides on scroll, pointer leave, or press.
- **Rail and nav.** Tooltips go to the right of the item.

### 7.3 Dialog, Confirm, Prompt

**Dialog anatomy.**
- In `Modal`: a Scrim covering the **window area only** (a child of the Modal layer sized to `Main`'s rect, r 20).
- Panel: width min(400, gui.X - 32), r 18, padding 20.
- Content: an optional icon plate 36 (`<Type>Soft`, r 10), title (`Dialog` 18), body 14/20 `Text2`, then the button row (right-aligned, 36 tall, 8 gap; `AutomaticSize X`).

Keys:
- **Enter activates the focused button. The `Enter` keycap is drawn on whichever button Enter will activate.**
- Destructive confirms focus **Cancel** first, so the cap sits on Cancel. Tab or arrows move it. This fixes Depth's mixed signals.
- `HoldToConfirm = true` makes the destructive button a 0.8 s hold.

Dismissal:
- The close key (Backspace / pad B), an outside click (`DismissOnOutside`, default true) and `x` all cancel.
- Every dismissal calls `OnCancel` (D18).
- Dialogs queue.

Variants:
- **Prompt** (new): `Window:Prompt{Title, Content, Placeholder, Default, Validate, OnSubmit, OnCancel}`. It adds an Input field with live validation. The Primary button is disabled while the field is invalid.
- **Phone:** under 480 px wide, dialogs render as bottom sheets with full-width buttons stacked (primary on top).

### 7.4 Context menu

The menu is width 248, r 14, padding 6. It has a header and items.

**Header** (two lines, 8 × 10):
- the flag name in mono 12 `Text2` (e.g. `Combat.FOV`, or "No flag");
- "Default: 90°" in 12 `Muted`, with the value in **Medium**.

**Items** (32 px, r 8, icon 16 + 14 text, shortcut keycaps on the right):

| Item | Notes |
|---|---|
| Reset to default | Disabled when unchanged |
| Copy value | `Ctrl C` |
| Paste value | `Ctrl V`. **Type-checked:** disabled with a reason line ("Clipboard isn't a number" or "Clipboard is empty") |
| Copy flag name | |
| Pin to quick dock / Unpin | Toggles and buttons only. Otherwise disabled with "Only switches and buttons can be pinned". |
| Bind a key… | Toggles and buttons; starts capture inline on the row |
| Show in palette | Opens the palette with the control's name |
| (List rows) Rename · Duplicate · Delete | `Danger` |

Placement:
- At the pointer, opening down-right and flipping at the edges.
- **If the pointer is inside the row's control column, the menu anchors to the left of that column** (its right edge 8 px left of the control), so it never covers the value it acts on.
- On phones it is a bottom sheet with 52 px items.
- The keyboard and pad use the focused row's rect.

### 7.5 Command palette

**Open.** Ctrl+K, `/`, the sidebar Search, the phone header search icon, or gamepad Y.

**Panel.**
- Modal layer with a scrim; width min(600, gui.X - 48); max height min(460, 70 % of the GUI); r 18; centred at 18 % from the top.
- Phone: a full-screen sheet with the input at the top.

**Input row (52).** Search icon 18, a TextBox (15 Roboto 400 `Text`; placeholder "Search settings and commands"), and on the right a scope chip when scoped ("in Combat ×").

**Results.**
- Groups, each with a 12 `Text2` caption: **Recent** (empty query: the last 5 used), **Best match** (top 1 when its score clearly leads), **Settings**, **Commands**.
- Rows are 44 tall (Touch 52), r 10, padding 0 × 12:
  - an icon plate 28 (`Active` fill, r 8; the highlighted row's plate turns `AccentSoft` with an `AccentText` icon);
  - the title (14, with matched characters in **Bold 700** through RichText);
  - a breadcrumb "Combat › Aim assist" (12 `Muted`);
  - on the right, a **live value chip** (mono 12, `Active` fill, r 6: "On", "90°", "RMB", "3 selected") or the shortcut keycaps for commands.
- The highlighted row has a `Hover` fill. Results come from the registry, so controls in **unbuilt tabs are found** (ARCHITECTURE_V2 §8.10).

**Ranking.**
- Per token of the query:
  - a **word prefix** of name, keyword or option scores 100;
  - a **substring** scores 60;
  - a **subsequence** scores at most 30, and only when the query has 3 or more characters, there are at most 2 gaps, and it does not span more than 2 words.
- Name hits weigh 1.0, host `Keywords` 0.8, option text 0.7, description and tooltip 0.5.
- A recent-use boost adds 15.
- Results scoring under 25 are hidden whenever any result scores 60 or more. So "esp" finds "ESP", "Box ESP" and "ESP colour", and no longer "Teleport to spawn" (G18).

**Keys.**

| Key | Action |
|---|---|
| ↑ ↓ | Move |
| Enter | **Go to** the control: switch tab (mounting if needed), scroll it into view, flash the row, pulse the ring twice. Commands run. |
| Ctrl+Enter | **Run in place**: toggle a switch, press a button, cycle a segmented control. The palette stays open and the chip updates. |
| ← → | **Adjust in place** a slider, stepper, segmented or switch result (Shift × 10) |
| Tab | Toggle the scope to the current tab |
| Backspace on an empty input / pad B | Close |

**Footer** (32, `BorderSoft` top rule). The hints follow the input:
- Keyboard: "↵ Go · Ctrl ↵ Run · ← → Adjust · Bksp Close".
- Touch: "Tap a result to jump to it · Hold to run it in place".
- Pad: glyphs "A Go · X Run · ← → Adjust · B Close".

**Empty state.** Icon 24 `search-x`, "No matches for 'flyy'" 14, and "Try fewer letters, or search a tab name" 13 `Muted`.

**Built-in commands:**
- Switch theme…, Toggle material, Interface scale…, Density…, Reduce motion;
- Show keybind list, Toggle watermark;
- Save profile as…, Load profile…;
- Open settings, Hide UI, Unload.

Hosts add more with `Window:RegisterCommand{Name, Description, Icon, Keywords, Shortcut, Callback}`, which returns a handle with `:Remove()`.

### 7.6 Notifications, Undo pill, inbox

**API.** `Argon:Notify{Title, Content|Description, Type, Icon|Image, Duration, Actions, Callback, Id, Position}` returns a handle `{Update, Dismiss, SetProgress}` (ARCHITECTURE_V2 §12.1). `Argon:Toast(text, type?, action?)` makes a small pill.

**Desktop card.**
- Width 340, `Raised`, r 14, padding 12 × 14, `ShadowFloat`, lit edge. **It follows the active theme**, so it is light in Daylight (Precision's bug).
- Content:
  - a type icon plate 28 (`<Type>Soft`, r 8, icon 16 in the status colour);
  - the title 14 Medium `Text`, an "x2" coalesce chip, and the time 12 `Dim` on the right;
  - the body 13 `Muted` (at most 4 lines, then "Show more");
  - actions (≤ 2: the first Secondary pill 28, the second Ghost);
  - a dismiss `x` 14 on hover or focus;
  - a 2 px timer bar inset 14 from the sides at the bottom (`Accent`, or the type colour for errors). It drains with the remaining time and **pauses on hover or focus**.
- **Types:** `info` (`info`), `success` (`circle-check`), `warning` (`triangle-alert`), `error` (`circle-x`), `loading` (spinner, no timer).

**Duration** `"auto"` = `clamp(2.5 + 0.06 × chars, 3, 9)` s. Errors × 1.5. At least 8 s with actions. `math.huge` is sticky.

**Stacking.**
- Top-right (`Prefs.NotificationPosition`: TopRight, BottomRight, TopCenter), 8 px gaps, at most **4**.
- Older ones collapse into a "+N more in inbox" chip (28, `Raised`) at the end of the stack.
- The same `Id` updates in place. Identical text within 2 s coalesces into "x2".
- The stack is pushed clear of the keybind list overlay. **It never covers the window topbar**: when the stack overlaps the window horizontally, it starts 8 px below the window's topbar (`Main.y + 52 + 8`), so the bell, Appearance and minimise stay reachable.

**Phones.**
- Toasts become **compact pills**: 36 tall, max width min(360, gui.X - 32), an icon 16 plus a one-line title, and a tap to expand into the inbox sheet.
- Portrait: they dock **above the bottom tab bar**.
- Landscape: they dock at the bottom centre of the window, 12 px above its edge.
- At most 1 visible, plus a "+N" count on the pill. They never overlap the sheet header, the palette or the reopen orb.

**Undo pill** (`Argon:Toast("Reset 9 settings", "info", {Text = "Undo", Callback = …})`).
- A 36 px pill at the bottom centre of the **window**: text 13 + an `AccentText` "Undo" + the `Ctrl Z` cap.
- It lasts 6 s, and a new one replaces the old.
- It sits in the Toast layer, below dialogs.

**Inbox.**
- The bell popover (width 340, max 420 tall) lists the last 30 notifications grouped "Today / Earlier", each as a compact row with its type icon, title, a body line and a time.
- "Clear all" is in the header. The empty state reads "You're all caught up".
- Opening it clears the unread dot.

### 7.7 Overlays (opt-in; off by default, ARCHITECTURE_V2 §12.4)

| Overlay | Look | Behaviour |
|---|---|---|
| **Keybind list** | Width 240, `Frame` at the HUD transparency, r 14, lit edge, `ShadowFloat`. Header "Keybinds" 13 Medium + count + a collapse chevron. Rows 28: name 13 `Text2`, mode 12 `Dim`, keycap. | Sizes to its content and hides when empty. **The active row** (a held or toggled-on bind) gets an `AccentSoft` fill and a 6 px `Accent` dot. No glow. Pad glyphs replace keys in gamepad mode. Auto-placed outside the window (bottom-right by default), draggable, position persisted. Hidden on phones. |
| **Watermark** | A 32 px pill at the top-left of the safe area: logo 16 · name 13 Medium · `144 fps` · `38 ms` · `21:42` (mono 12 `Text2`, `BorderSoft` separators) | Updates twice a second, only while visible. Off by default. |
| **Player list** | v1 features, restyled to this spec (rows 32, rbxthumb avatars) | Off by default (decided) |

### 7.8 Appearance popover (theme picker)

Opened from the topbar `ThemeButton`. Width 380, popover `reuse = "theme"`, clamped to the GUI height minus 16 with its own scroll, built once (ARCHITECTURE_V2 §12.6 test seams kept: `ThemeOptions`, one TextButton per theme named after it, and its UIStroke `Accent` when active).

**Theme grid:**
- 4 columns of **preview cards**, 52 tall (r 10). Each is a mini window drawn in the theme's **real colours**: the `Frame` strip on the left, a `Sheet` panel, two `Surface` bars with a `Text2` line each, an `Accent` gradient pill, and a mini switch in the on state.
- The name goes below (12 `Text2`; the selected one `Text`).
- The selected card gets a 2 px `Focus` ring plus a check badge.
- Groups: "Dark" (10 themes) and "Light and accessibility" (Daylight, High contrast).
- Hovering a card **previews** the theme live on the window (a 1-frame repaint of the visible components); moving away reverts; a click commits.

**Accent row:** Auto (the theme accent with an `A` glyph), 8 swatches, and "+" (opens the colour picker). A selected swatch gets a 2 px `Focus` ring.

**Material** (Solid / Tinted / Clear): a segmented control. It is disabled in High contrast with that reason.

**Further rows:**
- Interface scale: a stepper, 90-130 % in steps of 5 (one UIScale per layer root);
- Density: Auto / Compact / Touch;
- State labels: Auto / Always / Off;
- Reduce motion: a switch.

**Footer:** "More in Settings ›".

**Phone:** a bottom sheet with 2 columns of cards. (Precision opened a centred popover on phones; this fixes it.)

---

## 8. New features: spec and API

Every item here is additive. v1 scripts run unchanged.

### 8.1 Command palette

Automatic: every window has one. See §7.5.
- `Window:OpenPalette(query?)`
- `Window:RegisterCommand{Name, Description?, Icon?, Keywords?, Shortcut?, Callback} -> {Remove}`
- `Palette = false` (window option) disables it.

Every element accepts `Keywords = {"esp", "wallhack"}` for search.

### 8.2 Context menu, copy/paste, show in palette

Automatic on every row (§7.4).
- `ContextMenu = false` per element opts out.
- `Element:AddMenuItem{Text, Icon, Callback}` adds host items under a divider.

### 8.3 Change tracking, reset and undo

Automatic: changed dots, the page chip, Reset section and the Undo pill (§3.5, §5).
- `Element:Reset()`, `Section:Reset()`, `Tab:Reset()`, `Window:ResetAll()` (with a Confirm when called from the UI).
- `Element.Default`
- `Element:IsChanged()`
- `Tab:GetChangedCount()`

Undo keeps one level (the last reset or paste batch) for 6 s.

### 8.4 Pins, Pinned group, quick dock

Users pin from the context menu. Hosts may pre-pin with `Pinned = true` on a Toggle or Button.
- Pins persist per profile in `Prefs.Pins` (flag names).
- **Pinned sidebar group** (§3.3) and **quick dock** (§3.7) are two *views* on the element's single state object. Each subscribes to `element.changed`, so they cannot desync (the Depth mockup's mirror showed Off while the control was On).
- There are at most 6 pins on PC and 4 on touch. Pinning beyond the limit shows "Unpin one first".

### 8.5 Configuration profiles

`Window:CreateConfigManager(tab)`, also included in `CreateLibrarySettings`. Persistence is per ARCHITECTURE_V2 §13.3.

**Status line** (verified autosave): a dot plus "Saved · 2 s ago · ArgonUI/Nebula/PvP.json" (mono path, 12 `Muted`). Other states: "Saving…" and "Save failed: writefile is unavailable" (`Danger`).

**Profile rows** (List, 52): a coloured initial plate 28, the name 14, "24 settings · edited 5 m ago" 12 `Muted`, an **Active** tag, an **autoload star** (toggle), a **Load** pill, and an overflow menu (Rename via Prompt, Duplicate, Export, Delete).

**Actions:**
- **Delete** is hold-to-confirm (0.8 s) followed by a 6 s Undo toast.
- **Header:** "Save current as…" (Prompt) and "Import" (Prompt for an `ARGON2:` string, then a summary dialog: "12 settings will change, 2 unknown ignored", then Apply).
- **Footer:** "Copy current as code" (Export) and "Reset all…" (Confirm, `Danger`).

### 8.6 Notifications v2

See §7.6. The API is in ARCHITECTURE_V2 §12.1. Callback errors anywhere in the library are caught (`safeCall`) and shown as an `error` toast with **Copy error** and **Retry** (retry re-runs the callback with the same value).

### 8.7 Keybind v2

Modes, mouse and pad keys, capture with a drain bar, conflicts with Swap and Keep, and `Keybind = "F"` on toggles and buttons (§6.14). Rebinding the menu key happens in Settings.

### 8.8 Host status, tab badges, groups

- `Window:SetStatus(text?, tone?)`
- `Tab:SetBadge(n | "New" | true | nil)`
- `CreateTab(name, icon, {Group = "Tools", Description = "…"})`. The third argument is optional, and a table in place of the second argument also works.

### 8.9 Appearance, density, scale, reduced motion

| API | Values |
|---|---|
| `Window:SetScale(n \| "auto")` | 0.9-1.3 |
| `Window:SetDensity("auto" \| "compact" \| "touch")` | |
| `Window:SetMaterial("Solid" \| "Tinted" \| "Clear")` (new) | |
| `Window:SetReducedMotion(bool)` | |
| `Argon:SetAccent(Color3 \| nil)` (new) | `nil` clears the override |
| `Argon:CreateTheme{Accent, Mode, Neutral, Contrast, Name}` | ARCHITECTURE_V2 §5.2 |

All of these persist in Prefs and are applied before the first instance on the next run.

### 8.10 Key gate

`KeySystem` / `KeySettings` (Rayfield), plus `Validate`, `GetKeyLink` and `Blocking` (§4.8, ARCHITECTURE_V2 §12.7).

### 8.11 Build guard and loader API

See §4.9.

### 8.12 Callout, Stat, Image, ButtonGroup, Prompt

These are new content blocks (§6.5, §6.18, §6.20, §6.7, §7.3).

---

## 9. End-user Settings tab (`CreateLibrarySettings` v2)

Every row is a view over Prefs, not a user flag (ARCHITECTURE_V2 §12.5). The tab is called "Settings" and gets a `settings` icon; hosts place it last.

| Section | Rows |
|---|---|
| **Appearance** | Theme (dropdown with swatches; the full picker is in Appearance), Accent (swatches), Material (segmented), Interface scale (stepper %), Density (segmented), State labels (segmented), Reduce motion (switch), Typeface (dropdown: Roboto, Builder Sans, Ubuntu, Condensed, Technical, Gotham) |
| **Controls** | Menu key (keybind, writes `Prefs.MenuKey`), Pad menu button (segmented: None / Hold View), Reopen button (segmented: Auto / Always / Off), Mouse unlock (switch) |
| **Notifications** | Position (segmented: Top right / Bottom right / Top centre), Show callback errors (switch), Clear inbox (action) |
| **Overlays** | Keybind list (switch), Watermark (switch), Player list (switch), Overlay opacity (slider), Reset overlay positions (action) |
| **Profiles** | The config manager (§8.5) |
| **About** | Version, "Argon UI 2.0.0 · 1,573 icons" (12 `Muted`), "Copy diagnostics" (writes `Argon:GetPerfStats()` to the clipboard), and **Unload** (Danger action: Confirm, then `Window:Destroy()`) |

---

## 10. Input parity checklist (acceptance)

| Interaction | Mouse | Keyboard | Touch | Gamepad |
|---|---|---|---|---|
| Switch tab | click nav | Ctrl+1…9, Ctrl+[ ] | tap rail or bottom tab | LB / RB |
| Find a setting | Search field | Ctrl+K, / | header search | Y |
| Adjust a value | drag, or type in the pill | ← → (Shift × 10), typing | drag, or tap the pill | D-pad ← → |
| Row options | right-click | Shift+F10 | 450 ms hold | X |
| Close the top layer | outside click | Backspace | tap outside, swipe down | B |
| Hide or show the window | minimise / dock | Insert (rebindable) | minimise / orb | Hold View (opt-in) |
| Read a tooltip | hover | focus 600 ms | tap the marker | focus 600 ms |
| Unlock the cursor in first person | automatic (`Modal`) | — | — | — |

---

## 11. Budgets (checked by `tests/perf.luau` and `Argon:GetPerfStats()`)

| Budget | v1 (measured, perf.md) | v2 target |
|---|---|---|
| Network or yields before the first frame | HttpGet of 147.7 KB + `loadstring` (v1 L339-389, called from the first `drawIcon` at L1300) + `GetUserThumbnailAsync` (L1309) | **0** |
| Require-time decode and IO | +11 to +25 ms (base64 atlas + logo, L97-156) | **0** |
| `CreateWindow` | 4-43 ms, 184 instances | ≤ 3 ms, ≤ 30 instances |
| Loader timing | fixed `task.delay(.38)` / `(.93)` (L3352, L3359), a 392×108 pill growing into the window (L3182) | state-driven (§4.5); nothing with content is resized |
| Per-control API cost | 0.47-1.6 ms (eager) | ≤ 0.05 ms (state only) |
| Theme binding | `themeKeyForColor` linear scan per Color3 property (L178-183) into an ever-growing `_themeBindings` (L185-200), with a linear `unbindTheme` (L208-215): a quadratic build | token sentinels, per-component paint lists, no global registry |
| Instances per control | ≈ 9.5 | ≤ 7 average (§6.21) |
| UIStroke per control | ≥ 1.0 (per-row stroke, L1946) | ≤ 0.6 |
| Live glows | n/a | ≤ 3 per window |
| CDN faces on the first frame | 2-5 (directions) | **0** (2 preloaded) |
| Running loops when idle | RenderStepped + halo + 30 s prune (perf.md §2.6) | 0 |
| CanvasGroups | toasts (L1164), glow layer (L1282) | 0 |
| Dropdown open, 200 options | 12-20 ms, 611 instances, every time | ≤ 2 ms, ≤ 15 on the first open, 0 after |
| Theme switch, 400 built | 11-28 ms over 10 frames | ≤ 4 ms in 1 frame (visible components only) |
| Notification | 26 instances including a CanvasGroup | ≤ 12, pooled |

---

## 12. Traceability: every weakness the judges named

| Judge note | Where fixed |
|---|---|
| Depth: glass bleeds the scene under nav labels; Daylight Tinted is muddy | §2.2 (0.14 default, Daylight Solid, Clear cap 0.25), principle 1, §2.4 glass checks |
| Depth: colour discipline (dual accent, glows everywhere) | §2.6 (AccentAlt on bars only; 3-glow pool; no per-toggle glow) |
| Depth: Label padding about 2 px, clipped alpha thumb, orphan words, 24 px horizontal overflow | §6.3/§6.4, §6.16, §5 (text column ≥ 200 or stack), mockup stage `overflow-x: hidden` + verified scrollWidth |
| Depth: 12.5 px status; conic swatch; radius 26 bubbly | §2.9 (whole px), §2.5 (A-glyph swatch), §2.7 (window 20, controls 10) |
| Depth: translucent window + solid shadow darkens the scene | §2.10 hollow, offset-matched shadow |
| Depth: per-row atlas sprites, a gradient per keycap, many loops | §6 (UICorner Frames; gradients only on active parts), §2.11 (loops only while pending) |
| Precision: least "wow", flat hierarchy, Graphite/Arctic/Ember indistinct | G1-G3; 12 themes with distinct seeds and real-colour previews (§7.8) |
| Precision: thin generic loader; plain ghost | §4.2 orb card, tip, footers |
| Precision: toasts dark in Daylight; phone toasts cover the header | §7.6 themed toasts and phone pills; §3.1 layer order |
| Precision: no landscape phone; desktop hints on phone; centred theme picker on phone | §3.6, §7.5 input-aware footer, §7.8 bottom sheet |
| Precision: neutral segmented indicator | §6.11 AccentSoft indicator + stroke + AccentText label |
| Precision: out-of-range value only shakes | §6.9 clamp + range message |
| Precision: hairlines vanish at fractional scale; 5 px halo stroke; 3 px focus ring | G6 fill steps; glow slot instead of a second stroke; 2 px ring |
| Native: card soup, icon plates, low density | §5 rows in grouped platters; icons optional (section headers, not rows) |
| Native: tooltip covers a neighbour; toast and tooltip collide in landscape | §7.2 placement, §7.6 phone pills, §3.1 layering |
| Native: focus ring over the palette scrim | §3.1 the ring travels with the focus trap |
| Native: weak subsequence matches | §7.5 ranking |
| Native: no tab or section reset | §3.5, §8.3 |
| Native: mono textarea body | §6.13 |
| Native: press UIScale on text tiles | §2.11 `press` on buttons, keycaps and chips only |
| Native: equal-height two-column grid needs new engine paths | single column + TOC; Rows only for stat tiles and button groups |
| Native/Depth: quick dock icon-only; dock over the hotbar | §3.7 labelled chips, left-edge placement |
| All: Esc advertised | G14: Backspace / pad B everywhere; the mockup has no Esc keycap |
| All: CDN faces on frame 0 | §2.9 preload and swap; the loader uses local faces |
| All: subtree opacity fades | §2.11 veils |

---

## 13. The final mockup (`mockups/final.html`)

`final.html` is a single file that needs no build to view. Its source parts are in `mockups/final-src/`; `python -I mockups/final-src/build.py` concatenates them and injects the palette JSON from `bench/v2_final_palette.json`, so the mockup and `theme/Palettes.luau` share one source.

**Harness bar.**
- **Loader:** Replay, Ready under 150 ms, Waiting, Stalled, Error, Key gate, and Slow × 3.
- **Viewport:** Desktop 1440 (Wide), Laptop 1180 (Standard), Rail 860, Phone 844×390 (landscape rail), Phone 390×844 (portrait sheet).
- **Input:** Mouse, Keyboard, Touch, Gamepad.
- **Theme:** all 12. **Material:** Solid / Tinted / Clear. **Scene:** Dusk city or Bright stripes (the judge's stress test).
- **Open:** Palette, Appearance, Confirm, Prompt, Context menu, Toasts, Inbox, Hide / show, Key list + watermark.
- **Inspect Roblox recipe:** hover any part to see its instance recipe.

**Live stage.** A Roblox-like scene with the CoreGui top-bar buttons and a hotbar, and the window working end to end:
- toggles, sliders (drag, keys, typed values);
- dropdowns (single, multi, searchable, empty filter), the colour picker, keybind capture with conflict;
- the context menu, changed dots, Reset tab and section with Undo;
- the palette (ranking, groups, value chips, Enter, Ctrl+Enter, ← →);
- focus mode and gamepad hints, pins and the quick dock, the dock pill and reopen orb;
- toasts, the inbox, dialogs, prompt, the profiles manager, the Settings tab;
- lazy tab skeletons, and every layout.

**States board** (below the stage). Every component state is rendered with the same render functions:
- the loader (all states);
- switch, checkbox, slider, stepper, segmented, input, keybind, dropdown, colour picker;
- the button matrix, tooltip and lock, context menu, notifications, dialog, palette;
- the theme picker, profiles, dock and overlays, focus and gamepad;
- empty and skeleton states;
- phone layouts.

**How it was checked.**
- The mockup was driven in the session's own Browser pane tab and in headless Chrome through `final-check/cdp.py` (a copy of the judges' CDP driver, extended with element-relative clicks and drags). Captures are in `final-check/shots/`.
- Real input was used for: Ctrl+K and typing, ← → adjust inside the palette, Enter to jump, a slider drag, typing 999 into a value pill (clamped to 180 with "Must be between 30 and 180"), right-click → Pin, the segmented control, arrow-key focus mode, keybind capture, the stepper, Reset tab → Confirm, Ctrl+Z undo.
- Layouts were checked at all five viewports, with Daylight, High contrast and Ember, the bright-stripes scene, all loader states, the ghost hand-over (slow motion) and the board. There were 0 console errors and no horizontal page scroll (scrollWidth equals the viewport).

**Recommendation for `docs/preview.html`.** Rebuild it from `final-src` and keep the Inspect switch, so the docs demo can never show an effect the Luau build cannot make.

---

## 14. Evidence from v1 (confirmed and quantified)

| Known issue | Confirmed at | Quantified (perf.md, bench/) |
|---|---|---|
| (1) The first icon draw fetches and parses all of Lucide | `loadLucideIndex` L339-389. `game:HttpGet(LUCIDE_INDEX_URL)` at L374, `loadstring` at L344, cache `readfile` + `loadstring` at L362-371. The first caller is `drawIcon(searchIconHost, …)` at L1300, inside `CreateWindow`. | 147,702 bytes. 13.9-43 ms CPU for the parse, **plus** the network round trip (usually 100-500 ms; some executors block). v2 embeds 1,573 icons as about 15.8 KB of front-coded names (`bench/v2_icon_encoding.luau`), with O(1) core lookups. |
| (2) The avatar yields inside `CreateWindow` | `pcall(function() avatar.Image = Players:GetUserThumbnailAsync(…) end)` at L1309 | Typically 50-300 ms, and seconds when throttled. v2 uses `rbxthumb://` with no yield. |
| (3) The base64 atlas and logo are decoded and written on first run | `decodeBase64` L109-125; writes at L127-156 (L136, L150) | 48,456 bytes (16.4 % of the download); 9.3-11.5 ms decode; +11 to +25 ms on the first load. Removed in v2. |
| (4) Fixed loader timers and a pill that grows | `SPLASH_W, SPLASH_H = 392, 108` at L3182; `task.delay(.38, …)` at L3352 (expandShell); `task.delay(.93, openWindow)` at L3359; a 30 s watchdog at L3365 | A host build longer than 0.93 s shows a half-built window, and a short one waits for the timer. v2 is state-driven (§4.5). |
| (5) A colour scan per property and a growing binding list | `themeKeyForColor` L178-183 (linear over `THEME_KEY_ORDER`, then `pairs(C)`); `registerThemeBinding` L185-200 appends to `Argon._themeBindings`; `unbindTheme` L208-215 scans it linearly | Quadratic: tab 30 builds 7-11× slower than tab 1; 1,200 controls take 1,689-2,565 ms (perf.md §2.4). v2 uses explicit token sentinels and component-owned paint lists (ARCHITECTURE_V2 §5.3). |
