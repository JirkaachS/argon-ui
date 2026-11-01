# Argon UI 2: design documents

These are the documents Argon UI 2 was built from. The code in `src/` follows them; where the code and a document disagree, the code is the current truth and the document is history.

| File | What it is |
|---|---|
| [`DESIGN_V2.md`](DESIGN_V2.md) | The look and the UX: tokens, type, metrics, motion, every component and state, layouts, loading, budgets. |
| [`ARCHITECTURE_V2.md`](ARCHITECTURE_V2.md) | Modules and contracts: state-first elements, the scheduler, scopes and theming, input, layers, persistence, the bundler, the test plan. |
| [`RECONCILIATION.md`](RECONCILIATION.md) | The two documents above were written in parallel. This file records the decision taken wherever they disagreed, and who owns each feature. |
| [`mockup.html`](mockup.html) | The clickable reference the design numbers were drawn in. Open it from disk; add `#skip` to the URL to skip the loader. The "Inspect Roblox recipe" switch shows the instance recipe of any part on hover. |
| [`audit/`](audit/) | The audits of 1.18.3 that started the rebuild: public API (`api.md`), controls (`controlsA.md`, `controlsB.md`), shell (`shell.md`), performance (`perf.md`) and a survey of other Roblox UI libraries (`market.md`). |

## Which document wins

1. `DESIGN_V2.md` wins on every visual, motion, metric and UX value.
2. `ARCHITECTURE_V2.md` wins on module contracts.
3. `RECONCILIATION.md` wins over both where it states a decision.

## Reading notes

- "v1 Lnnn" and "L123" cite `argon-ui.luau` as it was at 1.18.3 (commit `05514a5`): `git show 05514a5:argon-ui.luau`.
- Some paths point into the design workspace, which is not part of this repository: `mockups/` (the three direction mockups and the source of `mockup.html`), `bench/v2_*` (design-time probes) and `final-check/` (browser captures). The palette generator lives on as [`tools/gen_palette.py`](../../tools/gen_palette.py), the bench as [`bench/compare.luau`](../../bench/compare.luau), and the docs preview as [`docs/preview.html`](../../docs/preview.html).
- The shadow and glow images still use the 1.x asset (`rbxassetid://1316045217`); `RECONCILIATION.md` R13 describes the planned dedicated images.
