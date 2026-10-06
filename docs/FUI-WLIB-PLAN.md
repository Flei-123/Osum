# Plan: replace wlib (client library) and wm.fi (window server) by fUi (06.10.2026)

Measured on main 689d3229. Roadmap: fUi r41 (wlib replaced), r42 (wm buttons via fui/core).

## 1. Where we are (measured)

| what | now |
|---|---|
| files that use `wlib.` | 47 (34 of them are scene programs: `fuiscene` / `fuiapp`) |
| scene programs that still use wlib directly | none for painting; they use it for the **window**: `step`, `begin`, `window_app/plain`, `win_x/y/w/h`, `set_focus`, `canvas`, `handle`, `resize_seq`, `ax_set_hooks`, keys (`KEY_*`), `paint_all/draw_all`, `idle_sleep_on` |
| distinct `wlib.` symbols used by scene programs | 195 (most are `KEY_*`, `AXR_*`, `AXN_*` constants) |
| distinct `wlibc.` symbols used by scene programs | 157 (theme table, `px_ui`, `F_UI`, metric, text measure, clip) |
| programs that use wlib widgets for real | `widgetdemo` (94 calls); `exporte` 10, `expmodell` 9, `modul` 9, `expakt` 4, `desktop` 3 |
| `wlib.fi` / `wlibc.fi` / `fuib.fi` | 12 735 / 7 006 / 1 240 lines |
| `wm.fi` (window server in the kernel) | 14 250 lines, 593 functions, ~45 round blocks |
| `taskbar.fi` | 8 149 lines, 2 126 176 of 2 134 016 octets of an OFS format-2 file |

**What this means:** the widget side of wlib is already dead for scene programs. What keeps wlib alive is
(1) the *window* API under `fuiscene`, (2) the theme / metric / text-measure table in `wlibc`, (3) the
programs that never moved (`widgetdemo`, export dialogs, `modul`, `desktop`), (4) the bar's painters.

## 2. Hard limit found first: program size (in the TEST images, not in the product)

`taskbar` is 7 840 octets under the OFS **format-2** file limit (2 134 016). The stick (`tools/usbimg/build.sh`,
`--v3`) and `tools/design/*.sh` already build format 3 and have no such limit; the limit bites in the 82 test
builders, 127 `mkfs.py build` calls of which have no `--v3` (k15, alltag, sync, module ...). Stage 2 of the bar
adds code before it removes code, so **step 0 is: every builder that puts a scene program on a disk uses `--v3`**
(first k15, alltag, win11bar, barscene, loginui, themestore; then the rest), checked by `tools/progsize`
(which keeps the format-2 number as an early warning for what is left).

## 3. Stages (each ends green on: loginui, look, themestore, alltag, barscene, win11bar, k15, a11yscene)

W0. **Size**: the builders above go to `--v3`. Gate: those six runners green with `taskbar` > 2 134 016 octets (a throw-away padding test).

W1. **`fuiwin` — the window client of fUi.** One small module `kernel/user/fuiwin.fi` that owns what scene
    programs take from wlib: open/close/resize/focus/hide a window, the surface (canvas), key and pointer
    events, `idle_sleep`, the a11y hooks, drag-and-drop hooks, clipboard. `fuiscene` / `fuiapp` call `fuiwin`
    instead of `wlib`. wlib keeps working next to it (same syscalls). Gate: scene programs no longer name `wlib.`
    except through a shim; counted by `grep`. Size of the module: the 195 symbols are ~60 functions + constants.

W2. **`fuimet` — theme, metrics and text measure** out of `wlibc` (`theme`, `px_ui`, `F_UI`, `metric`, `text_w`,
    `ui_scale`, `clip_set`): fUi already has a theme file (r64) and its own metrics; `wlibc` becomes a forwarding
    shim. Gate: pictures of `look` / `themestore` / `glyphe` unchanged (they are the proof).

W3. **Last wlib widget programs to the scene tree**: `widgetdemo` (495 lines, 94 calls), `exporte`, `expmodell`,
    `modul`, `expakt`, `desktop` (1 008 lines). Gate: `widgetdemo` = r380, `desktop` 100/0 after the move.

W4. **Delete `wlib.fi` + `fuib.fi`**; `wlibc.fi` shrinks to the surface/syscall part (rename `fuisurf`).
    Gate: no file imports `wlib`; boot, memory and frame time measured, no step backwards.

W5. **Bar stage 2** (r381 follow-up): paint the bar's rectangles from fUi widgets (`paint_band` 800 lines gone),
    layout in flex boxes instead of `layout()`, pointer through the host, auto-hide and drag in the host.
    Needs W0 and W1.

W6. **wm.fi, server side — in this order, each a separate merge:**
    1. caption + frame + hover plates from `fui/core` (r42 rest: `fb.fill` 15, `fb.pixel` 17, `fb.pixel_a` 7);
    2. window list, z-order, focus and snap as a *tree* (the a11y tree of the desktop) instead of arrays;
    3. glass / blur / shadow as scene effects (the one place with `menuhover` and `themestore` counter-proofs);
    4. move the server out of the kernel image (`wm.fi` -> `wmd` program) only after 1-3: the lock rule
       (`wm.darf`, `docs/LOCKSEAL.md`) must stay in the kernel; `lockseal` 43/0 is the gate.

## 4. Order and cost (honest)

W0 first (small, unblocks everything). W1 and W2 can run in parallel (different files). W3 after W1. W5 after W0+W1.
W6 is the big one: ~14 000 lines, do not start 4 before 1-3 are in main. Every stage is a worktree + `heavy` runs,
no stage touches the Dell.

## 5. What is NOT in this plan

A new compositor, GPU acceleration, Wayland-style clients: not needed for "everything on fUi".
