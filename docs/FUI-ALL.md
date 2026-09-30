# FUI-ALL — everything in OrientOS painted by fUi

Order from Justin (30.09.2026): every part of OrientOS is built on fUi.
This file is the inventory (measured, not estimated) and the stage plan.
Roadmap items: fUi r41 (wlib replaced), r42 (wm buttons via fui/core),
r56 (fUi's text setter), r61 (Firn pin), r64 (themes via fUi themefile),
OrientOS r216 (split the giant files).

## 1. Inventory (measured 30.09.2026 on main 96e092fa)

| what | size |
|---|---|
| `kernel/user/wlib.fi` (retained widget list, event loop, layout, dialogs, paint layer) | 12 604 lines |
| `kernel/user/wlibc.fi` (surface, pixels, theme table, syscalls) | 6 926 lines |
| `kernel/user/fuib.fi` (the bridge wlib -> fUi) | 808 lines |
| `kernel/ui/wm.fi` (window server) | 13 952 lines |
| `kernel/ui/kgui.fi` | 9 255 lines |
| `kernel/sys/sys.fi` | 15 703 lines |
| user programs in `kernel/user` | 213 files |
| programs importing `wlib` / `wlibc` | 24 / 27 (34 files in total) |
| programs importing fUi directly | 0 (only through `fuib`) |

Calls into wlib per program (top): settings 589, explorer 311, nedit 137,
launcher 109, widgetdemo 105, calc 103, taskmgr 102, glogin 100,
installer 98, viewer 89, snip 72, taskbar 69, storage 60, netmon 50,
freunde 48, a11ydemo 42, papierkorb 35, lock 30, qs 30, themetest 30.

Direct `wlibc` paint primitives inside `wlib.fi` before stage 1:
rect 24, rrect 10, px 10, rring 8, hline 8, frame 8, rframe 5,
drop_shadow 5, frame3 2, vline 2 (plus comment mentions) — about 70 live
call sites where wlib painted by itself, next to the ~60 that already
went through `fuib` (tafel/area/ring/draw).

Outside wlib: `wlibc.px` 56, `wlibc.rect` 8, `wlibc.text_at` 4 (taskbar,
qs, themetest, a11ydemo, desktop, icont paint parts of themselves).

Window server: the caption glyphs (minimise/maximise/restore/close) are
already drawn by `fui/core` (`cap_*`, cached per size); the frame,
title bar and hover plates are still `fb.*` fills (fb.fill 15,
fb.pixel 17, fb.pixel_a 7) — r42 rest.

## 2. Stages

0. **Firn pin** (r61) — the new fUi needs the current compiler.
   `vendor/firn/COMMIT` c8bf10fe = Firn main + `#[arch]` restored in both
   compilers. Patches 0003/0004/0008 gone, TLS + crypto moved to
   `lib/` (`lib/FROM-FIRN.md`).
1. **wlib paints nothing itself** — every primitive of wlib's paint layer
   is a `fuib` call drawn by fUi's painter (`fuib.rect/hline/vline/dot/
   frame/frame3/rrect/rring/rframe/shadow`), honouring wlibc's clip. The
   bridge calls `tafel/ring/draw` now honour the clip as well. Left for
   1b: the two image blits (icon cells, image widget) — they go to
   `fui.uiimage`.
2. **Compat layer -> fUi widgets**: wlib's retained list keeps its API,
   but each widget kind is an fUi widget (`fui.widget` + `wave2`) with its
   own state; then program by program to fUi directly: login, lock
   screen, explorer, settings, terminal, taskbar, start menu, installer,
   store.
3. **Password field from fUi**: fUi text field in secret mode (eye to
   reveal, copy refused, value and length never in the a11y export —
   fUi r99/r108), replacing `wlib.password`.
4. **Themes**: dark mode, accent and blur from fUi themes
   (`fui.themefile`, r64) instead of the theme store in wlibc/vorlage.
5. **App tree**: fUi's scene tree (docs/APP-TREE.md) as the source of the
   OrientOS accessibility tree (S-007/S-008 already on main) and of the
   action ids on the action bus (fUi r104).
6. **Speed** measured every stage: frame time, memory, boot — no step
   backwards.

After every stage: k14, k15, k16, a11y, actionbus (+gui, image),
userland, loginui green or not worse than main.

## 3. What stage 0, 1 and 1b changed (measured 30.09.2026)

- **Stage 0b**: Firn pin 489dcae8 — firnc1 (the compiler written in
  Firn) now accepts `#[inline]`/`#[no_inline]` and ports
  `__include_str` (file relative to the source, bytes become a text
  literal; Firn test 1663 passes under firnc1 from any working
  directory). Before, fUi's `canvas.fi`/`gpu.fi` made every fUi program
  "not core" for firnc1. firnc1 still stops on other constructs in the
  full fUi (widgetdemo exits 1 in the type checker); no acceptance suite
  builds those programs with firnc1 (userland section 7 builds its 28
  CLI programs), so this is a Firn item, not an OrientOS blocker.
- **Stage 1**: every paint primitive in `wlib.fi` goes through `fuib`
  (fUi painter, wlibc clip honoured). `grep` for wlibc
  rect/rrect/rring/hline/vline/frame/rframe/frame3/drop_shadow/px in
  wlib: 0 live call sites outside the fallbacks.
- **Stage 1b**: the icon cell (1:1) and the image widget (zoom, pan,
  quarter turns) are drawn by `fui.uiimage` / `fui.transform`
  (`fuib.icon`, `fuib.picture`); the old pixel loops stay only as the
  fallback before a surface exists.
- **r42 (window server buttons)**: glyphs were already `fui.core`; the
  rounded button surfaces and every other round corner in the kernel and
  in wlibc go through `lib/ecke.fi`, whose sixteen probes now ARE
  `core.corner_coverage`. `tools/fui/eckecmp.fi`: 42 924 corner pixels
  (r = 0..48, inside and outside the shortcuts), 0 differ from before.
- **Size**: 174/174 programs build (the 5 "failures" are libraries
  without `main`, as on main). The 22 wlib programs grew by ~5.2 KB
  each (+0.18 % of the object), 114 KB over all.
- **Paint time**: `wlib.paint_all` counts TSC cycles per frame; a build
  with `FIRN_OSUM_PAINTTIME=1` prints `wlib: paint frames=32
  avg_kcyc=… max_kcyc=… prims=…` once per program. Normal builds print
  nothing.

## 4. Stage 2: the first program ON fUi (lock screen), 30.09.2026

- `kernel/user/fuiapp.fi`: window (wlib's, so window server, a11y tree
  and event pump stay the system's), ONE `wlib.canvas` over the client
  area with the program's own buffer, fUi bound to it
  (`fuib.app_bind`), events in fUi terms (`next`), clock (`now_ms`).
- `lock.fi` paints label, text box (secret mode), button and eye with
  fUi's widgets and `fui.textbuf`; the bullets are a second buffer
  (`render.secret_mask`). The old wlib form stays as the emergency
  fallback (`u_gui_wlib`) if fUi refuses the canvas.
- Found on the way: a program's fUi painter had NO font (`fuib.s_fm`
  was never set), so every fUi text was silently invisible. Fix:
  `fuiglyph.fontset(role)` builds the `metrics.FontSet` from the fonts
  fuiglyph already loaded.
- fUi's `icon.stroke` is not exported -> the struck-through eye uses a
  local stepped line. Lucide's `eye` cannot be imported next to
  OrientOS's own `icons` module (same module name) -- open item.
- `lock` prints `lock: rect id=..` lines (like `wlib.say_rects`) so
  `tools/design/messen.py` still measures the 4-pixel grid (100 %).
