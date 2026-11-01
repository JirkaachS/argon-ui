# Argon UI 2.0 vs 1.18.3: load and performance

Measured with [`compare.luau`](compare.luau), which drives both libraries through the public API only, so the same script runs against each. Both ran on the same machine, one after the other, inside the Lune sandbox from `tests/`. Every timing is the median of three runs. Network round trips cannot be timed in the sandbox, so `HttpGet`, thumbnail and `loadstring` calls are counted instead.

## In short

- **Opening a hub is about twice as fast, and the game no longer freezes while it builds.** In the usual flow (create the window, build 4 tabs of 40 controls, restore settings, no `FinishLoading`), 1.x spends 89 ms of uninterrupted script time and then opens on its fixed 0.93 s timer. 2.0 spends 3 ms, then opens 0.40 s later, with no frame over about 7 ms.
- **Building controls is about 80 times faster.** 400 `Create*` calls take 4.5 ms instead of 359 ms, and the 10th tab builds as fast as the first; in 1.x it was 3.3 times slower, and the gap kept growing with every control.
- **Less of everything on screen:** 9.7 instances per control instead of 25.9 (3,877 instead of 10,346 for 400 controls), and 87 instances for 20 notifications instead of 1,740.
- **Nothing on the critical path touches the network.** 1.x made an `HttpGet` (the Lucide index) and two thumbnail calls inside `CreateWindow`; 2.0 makes none.
- **Nothing runs while the menu sits idle.** 1.x kept 127 input handlers, a per-frame handler, 6 endless tweens and 2 timers; 2.0 keeps one input handler.
- **What got worse:** the file is about twice the size (567 KB instead of 293 KB), so it takes about 36 ms longer to compile. 1.x also downloaded the 148 KB Lucide index on first run, so the first-run download is about 567 KB against 440 KB.

## The numbers

| Measure | 1.18.3 | 2.0.0 |
|---|---:|---:|
| bundle size | 292,757 B | 567,168 B |
| compile (median of 5) | 14.24 ms | 50.38 ms |
| load (compile + top level) | 16.18 ms | 51.75 ms |
| instances created at load | 0 | 0 |
| timers queued at load | 1 | 0 |
| CreateWindow | 5.34 ms | 1.09 ms |
| instances after CreateWindow | 391 | 35 |
| HttpGet calls during CreateWindow | 1 | 0 |
| thumbnail calls during CreateWindow | 2 | 0 |
| Create* for 400 controls (10 tabs x 40) | 358.96 ms | 4.51 ms |
| instances created by the Create* calls | 10,306 | 0 |
| first tab build | 17.20 ms | 0.69 ms |
| last tab build | 58.66 ms | 0.48 ms |
| last tab / first tab | 3.26x | 0.71x |
| LoadConfiguration (280 flags) | 16.89 ms | 4.56 ms |
| FinishLoading call | 0.02 ms | 12.07 ms |
| frames until the window is open after FinishLoading | 1 | 1 |
| library work in the 600 frames after (background mounting) | 1.64 ms | 76.97 ms |
| worst single frame after FinishLoading | 0.18 ms | 4.53 ms |
| instances once every tab is built | 10,346 | 3,877 |
| instances per control (everything mounted, structure included) | 25.87 | 9.69 |
| SetTheme with everything built (synchronous part) | 8.76 ms | 1.03 ms |
| theme catch-up over the next 30 frames | 0.04 ms | 5.79 ms |
| 20 notifications | 34.12 ms | 1.59 ms |
| instances created by 20 notifications | 1,740 | 87 |
| idle: `InputBegan` handlers | 41 | 1 |
| idle: `InputChanged` handlers | 43 | 0 |
| idle: `InputEnded` handlers | 43 | 0 |
| idle: `Heartbeat` + `RenderStepped` handlers | 1 | 0 |
| idle: endless tweens running | 6 | 0 |
| idle: timers pending | 2 | 0 |
| usual flow (4 tabs x 40): script time from `CreateWindow` to the end of the script | 89.35 ms | 2.78 ms |
| usual flow: frames after the script until the window is open | 56 | 24 |
| usual flow: the same in seconds at 60 fps | 0.93 s | 0.40 s |
| usual flow: worst frame until the window is open | 0.15 ms | 7.34 ms |

No run of either version produced a warning or a handler error.

## Reading the table

- **Work moved out of your script and into frames.** In 1.x every `Create*` call built its instances on the spot, so all of it landed in your script's single uninterrupted run, where Roblox cannot draw a frame. In 2.0 a `Create*` call only records state; the scheduler builds the visible tab first and the rest in budgeted slices (8 ms per frame while loading, 4 ms after). That is why 2.0's `FinishLoading` (12 ms: it builds what is left of the visible tab before revealing it) and its background mounting (77 ms spread over many frames) cost more than 1.x's, while 1.x's 359 ms arrived as one frozen frame.
- **The 1.x window opens on a timer, not when it is ready.** Its 0.93 s timer starts at `CreateWindow`, so a slow build eats into it and a fast one still waits. 2.0 opens when the script is done (its thread ended, it called `FinishLoading`, or it built a tab and went quiet for 250 ms) plus the hand-over.
- **Compile time is the price of the bigger file.** 2.0 embeds all 1,573 Lucide icons (about 18 KB), the twelve themes, and the new features (palette, profiles, change tracking, dialogs, overlays, the key gate). The file is already stripped of comments and indentation.

## Reproducing

From the repository root, with `git show 05514a5:argon-ui.luau > v1.luau` for the 1.x bundle:

```sh
lune run bench/compare.luau -- v1.luau
lune run bench/compare.luau -- argon-ui.luau
lune run bench/compare.luau -- v1.luau 4 40 flow
lune run bench/compare.luau -- argon-ui.luau 4 40 flow
```

Each run prints one line per measure. Times vary from run to run and between machines; compare runs made one after the other on the same machine.
