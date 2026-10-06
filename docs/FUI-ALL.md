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

## 5. Design rule: surface steps and the main button (Justin, 02.10.2026)

A widget with a border never has the fill of what it sits on. The rule
lives in the central token layers, not in programs:

| token (layer 2, `wlibc.fi` + `tools/theme/model.py`) | light | dark |
|---|---|---|
| `surface` (base, the window) | n50 | n900 |
| `surface-raised` (card, menu) | n0 | n800 |
| `control` (button face) | n200 | n700 |
| `control-hover` | n300 | n600 |
| `control-pressed` | n400 | n500 |
| `field` (text field, list, check box) | n100 | n950 |
| `border` | n300 (was n200) | n700 |

- `C_BUTTON_FACE/HOVER/PRESSED` map to the control steps, `C_INPUT_BG` and
  `C_LIST_BG` to `field`. Four new text pairings (text on control, hover,
  pressed, field) join the 17: 21 pairings, all checked by `model.py` and by
  the kernel (`tools/themestore/run.sh`).
- The main button of a form is the accent (blue): `wlib.primary(id, true)`
  (flag `F_HAUPT`, accent / hover / pressed fill and `on-accent` label, also
  on the old path that paints the part of a button above the band), and
  `fuiapp.button_main` / `fuiscene.button_main` on fUi directly. Marked so:
  settings (Übernehmen x3), calc (=), lock, login (Anmelden).
- `high contrast` keeps its collapsed surfaces (the border is the text colour),
  but `control` and `field` now step off them by one ramp step (light: n100 /
  n200 / n300 for the control states, dark: n800 / n700 / n600), so the rule
  holds there too (03.10.2026, r120).
- `surface-sunken` moved because it was the fill of `field` (a list with a
  scroll track: the track vanished into the list): light n100 -> n200, dark
  n950 -> n1000. It is the scroll track and the top of the desktop gradient.
- THE RULE IS MEASURED, not just stated: `tools/theme/model.py fill <scheme>
  <light|dark>` prints the OKLab distance of every field / control pair
  against surface, surface-raised, overlay (and field against sunken); all
  must be >= 0.012 (the same number as fUi's `themefile.check_fill_distinct`).
  `tests/theme/run.sh` section 5b runs it for the five schemes in both modes,
  with a counter-check (a scheme whose light steps all fall together MUST
  violate it). The kernel binds the same tokens as the model (section 4), so
  the model's measurement is the kernel's. Templates (`assets/themes/*.preset`)
  pick a scheme and a mode, so they are covered by the same table.
- Screens before / after in both modes: `belege/design/` (`tools/design/
  surfaces.sh before|after`).
- Acceptances adjusted on purpose: `themestore` window-corner smoothing
  thresholds 6/12 -> 3/6 (a staircase still measures 0), the flat-overpaint
  counter-test also overpaints the button's face colour (a main button is
  accent-filled), `loginui` focus ring = dark edge that differs from the
  face (the accent-filled button is dark too).

## 6. Stage 2: programs on fUi's scene tree (`kernel/user/fuiscene.fi`), 02.10.2026

Decision (Justin): everything is built with fUi, nothing stays on wlib.
Stage 1 ("wlib paints with fUi") was already done; the work that is left is
the retained widget model, the layout and the events. They move program by
program to the host in `fuiscene.fi` (scene tree + `control.Panel` +
`plat.fuiwirt`), and `wlib`/`wlibc`/the painting in `wm.fi` disappear when the
last program has left them.

**The model is "describe again".** A program hands over `build()`; the tree
is rebuilt whenever the program calls `refresh()`. Nodes the program wants to
hear from carry a KEY; `pump()` answers with the key of the activated node.
Text fields, table selection and check / slider values live in the host by
key, so they survive a rebuild; focus is found again by key.

Building blocks: boxes (`row`, `column`, `space`), `label`, `button`,
`button_main` (accent), `tab`, flat menu-bar buttons, `entry`, `check`,
`slider`, `choice`, `table` / `table_blob` (one painted node: header, rows,
selection, keys, header clicks; a list is a table of one column), one popup
menu overlay (`menu_open`), and `say_rects` / `say_texts` which write the
lines `tools/design/messen.py` and `tools/alltag/shotcheck.py` read.

Lessons paid for (all in `fuiscene.fi` comments): `scene_new()` /
`sheet_new()` return ~100 KB by value and kill a user stack silently --
static memory plus `scene_reset`; a static cannot hold a function address --
store it at `open`; `wlib.begin` must run before the window; a node's style is
recomputed from the stylesheet each frame (colours go through
`sheet_rule(sel_id)`); box `grow` / fixed width of a row do not reach their
children in the pinned fUi -- compute pixel widths; the 4-point grid
(`messen.py`, 92 %) wants gaps and sizes in multiples of 4.

Ported so far: `calc`, `papierkorb` (and `scenedemo`). Acceptances:
alltag raster 100 % for both.

## 7. Stage 2, round F-5: the mid-sized programs, 02.10.2026 (night)

On the scene tree now (nothing of them is left on wlib's widgets):
`taskmgr`, `storage` (/bin/speicher), `viewer`, `snip`, `installer`,
`powermon`. Together with
`calc`, `papierkorb`, `netmon`, `lock`, `glogin`.

New building blocks in `fuiscene.fi` (all state by KEY, so a rebuild keeps
it):

| block | what |
|---|---|
| `canvas(parent, key, w, h, draw)` | a node the PROGRAM paints; `cv_rect/cv_round/cv_ring/cv_text` in theme roles, `cv_rgb` for an exact colour (treemap tiles) |
| `image(parent, key, w, h)` | a picture from memory: zoom (`image_set_zoom`, `image_fit` never over 100 %), quarter turns, pan by dragging, `image_click` (thumbnails), `image_tool` = a drag draws a frame in IMAGE pixels (`image_sel_*`, snip) |
| `table_single(key, on)` | one click on a row answers the key (a task list); `HEAD_ROW` as the selection = no row selected |
| `dialog_ok_x/y/w/h` | where the first dialog button stands (tests press it) |
| `hide(on)`, `handle()`, `set_app`, `raise`, `build_now` | what the old wlib window calls were |
| `compact(node)` | a tool-bar button with 8-point inner margin |
| `ax_action(key, name)` | the bus action a node stands for |

### 7.1 Accessibility tree and bus actions for scene windows

A fUi window has ONE canvas widget in wlib's list, so wlib's tree was empty
for it. `fuiscene.open` now hands wlib two functions (`wlib.ax_set_hooks`):
one writes the nodes of the scene tree behind wlib's own (96 octets, same
format: role, state, place, value, name, bus action), one takes a press.
Node ids are `AXP_BASE (0x8000) + node index`. A reader presses a button or a
check box; the next `pump` answers its key, exactly like a click. Tabs are
refused by the kernel like in a wlib window (buttons and check boxes only).
Test: `bash tools/a11y/scene.sh` (13/0): tabs, field, button, label are in the
tree; two presses of the main button change the counter label; a tab press
is refused. `tools/a11y/run.sh` stays 58/0.

### 7.2 The caret (known defect, fixed)

`render.draw_field` places the text pieces and the caret with `field_x_of`,
which measures through a function pointer that returns `f64` -- in a ring-3
program that call comes back as 0.0 (measured: `tb_x_of` 0, `field_meas`
called directly 37). Effect: caret at the left end; with the caret inside
a text the part after it was painted over the part before it.
`fuiapp.field_paint` draws the text as one piece (caret at the end for the
call, caret drawing off) and measures the caret with a direct `field_meas`
call. A press in a field puts the caret at the closest character boundary
(`fuiscene.entry_click`, direct calls as well). Used by lock, login and every
scene field. The cause (f64 through a function pointer) is a Firn item.

### 7.3 Full-width panels (known defect, fixed)

`painter.raster_window` needs `(bx - ax) + 1` columns; the app painter was
initialised with exactly the canvas width, so a shape as wide as the canvas
was dropped. `fuib.app_bind` now reserves `w + 2` columns (and re-inits when
the width grows, not only the height).

### 7.4 Acceptances

* toolbench (taskmgr): 28/6 on main (sections 6 and 8 red on main already:
  the 20-second hold ends before the click plan reaches the question; the
  control centre part is qs) -- same 28/6 with fUi. With `wighalt=120` the
  plan reaches the question ("frage pid=") and the answer button.
  `tools/toolbench/klickplan.py ja` reads the new report
  `taskmgr: dialog ok x= y= w= h=` (the question is an overlay of the same
  window now, not a second window).
* storage: the tile probe measures the tiles IN THE PICTURE; tile colours are
  exact RGB (`cv_rgb` swaps R/B like the theme colours do).
* Design rule honoured by the tokens: fields, tables, picture boxes use the
  `field` step, tool-bar buttons the `control` step, the main action (Sichern,
  OK) the accent.

### 7.5 Installer, powermon, and what else changed

* `installer`: the disk table and the partition table are blob tables, the
  two ways are tabs, the two questions are in-window dialogs (state machine
  instead of a blocking wait loop: "Ja" on the first opens the second,
  "Ja" on the second sets `los`), the progress is `fuiscene.repaint_now()`
  between the steps (the installation still runs in ONE go, see the long
  comment in the file). Old behaviour kept: on the "daneben" way one
  question. NOTE (read from the code, not measured): the old code set `frage = 2`
  BEFORE showing that single question, and its loop starts the writing
  when `frage == 2` -- so on that way the question seems not to have held
  anything back. The new code starts only on the answer. `tools/install/abnahme.sh` (full chain: install, reboot from the
  disk, file survives, root block flipped).
* `powermon`: label, table, close button.
* `fuiscene.set_value` writes the live node's widget too. Before, `val_sync`
  (run before the rebuild) compared the OLD tree's slider with the NEW
  stored value and read the difference as a drag by the user: the viewer's
  zoom crept to 89 %.
* `say_rects` no longer needs the trace switch (programs call it once at
  start; the repeated calls of taskmgr stay behind `melde` / trace), tables
  are reported as kind 6, sliders as kind 17.
* Acceptance runs: `tools/alltag/run.sh` section 9 builds a 16 MiB image
  (`bloecke=32768`): eleven programs that each carry the scene host no
  longer fit 8 MiB. `tools/toolbench/run.sh` holds the window server for
  120 s (`wighalt=120`).
* Firn: the caret bug was a compiler bug (regalloc `CallIndirect` ignored
  floating point), fixed in Firn main `93a688d77`, test
  `tests/2002_calli_float.fi`. OrientOS' pin (`vendor/firn/COMMIT`) is older;
  `fuiapp.field_paint` works on both.

## 8. Stage F-6/F-7: freunde, the start menu and the settings window on the scene tree (03.10.2026)

New pieces of `fuiscene` (what the big programs needed first):

* **Frameless layer windows**: `open_plain(x, y, w, h, title, layer, build)`,
  `keys_always` (the window also gets keys while it is not the focus
  window), `has_focus`, `hide`, `focus(key)`, `set_flags`/`begin`.
* **Every key counted**: `key_seq` / `key_any` (the old `last_key` only knows
  keys nobody took). A click into a text field is NOT an activation, Enter
  is.
* **Lists**: `table_list` (one row per line, no header), `table_two` (two
  lines per row: name bold 15, description 12 muted, baselines 20 and 46
  under the row top), `table_icons` (one word per row: bit 63 = icon of the
  icon font, "OSYM" picture, else a colour tile), `table_click_only`,
  `table_prep`, geometry getters for the acceptance reports. The glyphs of
  the two-line rows are placed one by one on whole pixels with
  `wlibc.pen_x` (the running sum `text_at` uses): the k15 ink check
  (tolerance 0) passes.
* **`memo`**: a multi-line field (Enter, Up/Down, Home/End, scrolling).
* **Resizing**: the window can be dragged to another size (`fuiapp.resize`
  makes a new pixel buffer, the tree is described again).
* **Settings helpers**: `card`, `label_wrap`, `canvas2`, `cv_*_rgb`,
  `row_stretch`, `set_dense`; more slots (fields 24, tables 8, values 24).

Programs:

* `freunde`: the chat is a second PAGE of the same window (the scene host
  holds one window per process).
* `launcher` (start menu): plain window on `L_MENUE`, search field, two-line
  list with pictures, the power menu is a popup of the window, the two
  questions are in-window dialogs (focus on "Cancel").
* `settings`: 15 pages, each a `page_*` builder; keys `K_*`; choice values
  in `kval`; the text of the fields is copied to and from the program's own
  buffers around each event (`pull_entries` / `push_entries`); the theme
  tiles are painted by `draw_tile`.

Still open: taskbar, explorer, nedit, qs (see the roadmap); the scene tree
ignores `wlibc.ui_scale` (HiDPI); right click / context menus, multiple
selection, drag and drop, a dialog with an entry, closable tabs and a
progress bar are missing for the explorer.

## 9. Stage F-8/F-9: the file manager and the editor on the scene tree (03.10.2026)

New pieces of `fuiscene` (all state by KEY, like the rest):

* **Several rows marked**: `table_multi(key)` -- Ctrl+click toggles, Shift+click
  and Shift+arrow mark a range, Ctrl+A is `table_sel_all`, the bits are read with
  `table_sel_has/num`. A plain click is a new beginning. The cursor row
  (`table_sel`) is still the keyboard's place; with no row marked at all it is
  drawn as the selection (the Delete key then acts on it, as before).
* **Scroll bar** on every table that has more rows than room (click or drag on
  it). The wheel is not delivered by the window server yet (roadmap).
* **Drag and drop**: `table_drag(key)` makes a press on a row and a move to
  another row answer `KEY_DRAG` (`drag_key`, `drag_row`); the program puts the
  payload on the system's drag place (`wlib.drag_put`) and hangs the label at
  the pointer (`drag_shield`). `drop_accept(true)` makes wlib fire `K_DROP`,
  which `fuiapp` turns into `EV_DROP` and `pump` into `KEY_DROP` (`drop_key`,
  `drop_row`, `drop_x/y`). `table_drop_filter(key, f)` says which rows may take
  a drop -- they get a ring while the pointer is over them. A stale payload (a
  drag that ended on the desktop) is dropped at the next press.
* **Dialogs**: besides the two-button question there are `dialog_entry` (a text
  field, `dialog_entry_text`), `dialog_choice` (up to four answers side by side,
  Esc = `dialog_cancelled`), `dialog_busy` + `dialog_set_text` + `repaint_now`
  (a job that runs between two pumps, with a progress bar) and
  `dialog_progress`.
* **Nodes**: `icon_button` (a glyph of the icon font, the label is only the name
  for a reader), `tab_close` (a tab with its cross), `progress`, `editor`.
* **Keys nobody took** (`key_free_seq` / `key_free`): not a text field, not the
  text area. A field also hands on the keys it does not edit with (function
  keys, control letters), so Ctrl+L works with the path field in focus.
* `table_own(key)`: the table answers only through its own press/key handling
  (the host's "a click activates the node" would open a folder on ONE click).
  `table_exact(key)`: the cell texts on whole pixels like the system's text.
* A popup is moved back into the window when it would stick out.

`fuied.fi` is the text area of wlib (`K_TEXTAREA`: the line table, caret,
selection, undo, keys, syntax colours) with the widget list taken out: the host
tells it how many rows and columns fit (`ed_size`) and it paints with fUi's
painter and the mono font on a grid of cells. `nedit` runs on it.

`explorer.fi` keeps its logic (model, acts, places, backup) and has a new top:
`build()` describes menu bar, tool bar, crumbs or path field, tabs, places, tree,
files, status line; `behandeln(key)` is what the old event loop did. The
parameter lists `(baum, tab, stat, fpfad)` stayed -- they are keys now.

Acceptances changed on purpose: `tools/explorer2/run.sh` runs with `uitrace=yes`
(without it the run was blind and red already on main), `tools/design/drive.py`
finds menu titles, context-menu rows and table rows from the new reports,
`tools/clip2/run.sh` looks for `fuiscene.drop_accept`, `tools/check-ui.sh` lists
the host modules (`fuiapp`, `fuiscene`, `fuied`, `lock`, `wlib`) as files that
may touch fUi directly (four of them were red on main).

**HiDPI (`ui_scale`)**: the scene tree now describes everything in design points
and multiplies by the integer `wlibc.ui_scale()` (`s_S`, read at start; `sp(n)`,
`spf(x)`, `scale()`). Fixed sizes (row, head, icon, scrollbar, dialog plate,
memo line height) are functions of `s_S`; the width/height the program sees are
in design points (`width()`/`height()`). `fuied` (the editor grid) scales its
cells the same way. The header text of the first table column sits over the
NAMES (after the row icon), not over the icons.

## 10. The task bar's pop-ups and the translucent windows (05.10.2026)

* **Quick settings** (`qs.fi`, 2 895 -> 1 700 lines) are window 1 of the task bar's
  scene host: a card with four tiles (`fuiscene.tile`: fUi's button face plus the
  program's own glyph and label lines), two sliders of fUi, a separator and a
  footer of icon buttons. The old band loop, the hit tests by hand and the poll
  of the window's event ring are gone. The serial lines the acceptance runs
  read (`qs: open`, `qs: kachel`, `qs: sym`, `qs: hell ...`, `qs: tile ...`) are
  the same words; their numbers now come from the tree. Acceptance:
  `tools/qsfui/run.sh` (20/0, ui_scale 1 and 2: tiles 117 points wide, labels
  inside their tiles read by `kachel.py` from the panel's OWN rectangles with a
  counter-proof, a click on a tile reaches the system and the tile turns accent,
  a click in the slider sets the brightness and the knob moves, Escape and
  Super+A close it). `tools/toolbench/klickplan.py` finds a tile by the same
  rectangles; its run holds 120 s like section 6 (the Dunkelmodus checks of
  section 8 were red on main for the 20 s hold alone).
* **Tooltip and toast** (`barpop.fi`) are one hidden scene window each, windows 2
  and 3 of the bar. Created at the largest size they will need; every showing
  is text -> `WM_SIZE` (a window may shrink below its created size and grow back
  for free) -> repaint -> `WM_MOVE` -> show. `fuiscene.win_size`,
  `wlib.note_resize`, and `fuiapp.resize` for windows down to 16 x 8 pixels are
  the new pieces. Acceptance: `tools/barpop/run.sh` (10/0: the bubble and the toast
  stand where they report, the rectangle differs from the picture without them,
  they are gone afterwards). The old `wlib.tip_win_*` / `toast_win_*` are dead
  code now (roadmap).
* **Text plates for translucent scene windows** (`fuiapp.plate`, called by
  `fuiscene.plates` when `window_alpha < 100`). wlib marks every pixel that
  carries text with `PLATTE` (the top octet) and the window server takes a
  marked pixel unchanged; a fUi window paints into its own buffer and had no
  mark, so foreign text (the terminal under the settings) ran through the tab
  row. The mark is set in the canvas after the picture: text lines, and the
  bounding box of the tabs.
* **Window frosting for big windows**: `wm.GLASS_PX` 460 800 -> 655 360. The
  settings window is 760 x 640 since its page stands on the scene tree; 486 400
  pixels did not fit the old strip and `glass_prepare` refused it -- the window
  got no frosting at all.
* **Alpha line of the bar**: `wm: glas alpha_soll= alpha_ist=` was written once
  at the start of the hold (`px=0`); it is written when the bar is mixed
  (first blit, then every 240th). The settings page re-reports a lifted value.
* **Checkers**: themestore 287/11 -> **298/0** (KVM by default; the overlap area
  is capped at the bar's height; the glass band comes from the window's own
  `cx/cy`; the counter-proofs narrow buttons around THEIR text and draw their
  line where the probe has ten pixels of room). Check box labels report where
  the TEXT starts (they reported the node's left edge and the box's accent fill
  counted as the label's ground).

## 11. What is fUi and what is not (measured 05.10.2026 evening, branch fui-login)

Lines of the programs' own source (`kernel/user`), grouped by how their window
is built. All of them paint with fUi's painter since stage 1; the question here
is whether the window is a fUi **scene tree**.

| group | programs | lines | share |
|---|---|---|---|
| scene tree (`fuiscene`) | explorer, settings, nedit (+`fuied`), launcher (start menu), taskmgr, calc, viewer, snip, pdfview, installer, freunde, papierkorb, storage, store, netmon, powermon | 28 739 | 67.2 % |
| scene tree, windows of the task bar | quick settings (`qs`), tooltip and toast (`barpop`) | 1 937 | 4.5 % |
| scene tree (r372/r373/r374, this round) | lock screen, sign-in screen (`glogin`), certus placeholder, a11ydemo, themetest (its gui test) | 3 243 | 7.6 % |
| wlib widgets (old toolkit) | widgetdemo (the K15 anchor) | 495 | 1.2 % |
| own painting routine, fUi painter | the task bar itself (7 321), the desktop (1 008) | 8 329 | 19.5 % |

So **79 %** of the GUI programs' lines are described as a scene tree (before
this round 70 %); by number **21 of 24** programs with a window are scene trees (the three
others: widgetdemo, the bar, the desktop). Nothing of the lock screen or the sign-in screen
paints by hand any more, and neither keeps a wlib fallback.

Under all of them:

* **wlib** (12 822 lines) is still the layer every fUi program sits on: window
  creation, the event pump, the accessibility export, the clipboard and drag
  plumbing. Its **widget list** (button, entry, list, menus, dialogs ...) has
  exactly ONE user left: `widgetdemo`, the application the K15 acceptance
  (`tools/k15/run.sh`, 258 checks, nine of its ten sections) measures the
  widget library on, with counter-proofs (`nohit`, `noclip`, `nodirty`,
  `nofocus`, `nomouse`). The list can go when `widgetdemo` and K15 move to a
  scene-tree equivalent -- a rewrite of the acceptance, not of a program.
  *Not replaced.*
* **The window server** (`kernel/ui/wm.fi`, 14 212 lines) draws frame, title bar
  and hover plates with `fb.*` fills; the **terminal** is a text grid of the
  kernel (`ansi`, `wm`). *Not replaced.*
* **The bar itself** (`taskbar.fi`, 7 321 lines): its own layout (`layout`,
  450 lines of pixel rules for both orientations, field widths snapped to the
  grid, shortening, hiding of missing hardware) and its own painting
  (`paint_band`, 800 lines), hit testing (`click`, `hover_step`), drag, auto
  hide. Most acceptance runs measure its pixels (themestore 298, look, glyphe,
  netview, toolbench). The way in, in this order: (1) a tree whose nodes sit at
  the rectangles `layout()` already computes, each node painted by the existing
  painters through a draw callback (pixel-identical, a11y nodes and focus for
  free), (2) click/hover/drag handled by the host (`pump` keys) instead of
  `click()`, (3) the layout itself in flex boxes, (4) the window of the bar
  from `fuiscene.win_open_plain`. *Not started.*

## 12. Round r372-r374: lock screen, sign-in screen and the small programs (05.10.2026)

* **Lock screen** (`lock.fi`, 794 -> 476 lines): `fuiscene.open_plain` on layer
  `L_TOP`, a column (name, question, password field + eye, main button). The
  kernel side is unchanged: it locks, this program asks and tells it to open;
  a crash still locks and never unlocks. `tools/lockscene/run.sh` 13/0: tree,
  grid 100 %, wrong then right password, only wrong passwords (counter-proof),
  the eye through the keyboard, crash.
* **Sign-in screen** (`glogin.fi`, 1 835 -> 1 342 lines): card with the question,
  the user (label, list or name field), password field with eye, "Anmelden",
  "Anderer Benutzer"; clock, network and power at the bottom right with the
  network text / power choice as cards. The trace lines of the old screen
  (`glogin: rect`, `wlib: focus`, `wlib: caret`, `wlib: eye`) are written from
  the tree, so `tools/loginui/run.sh` (stick, USB mouse and keyboard, PS/2) and
  `tools/loginscene/run.sh` (20/0: tree, grid 97 %, Tab chain, caret, eye,
  wrong/right password, other user, quick access, counter-proofs) measure the
  same screen. **Different on purpose:** the host puts every button into the Tab
  chain, so the eye and the two quick-access icons are Tab stops now
  (Kennwort, Auge, Anmelden, Anderer Benutzer, Netzwerk, Ein/Aus); before the
  chain had three. Shift+Tab (also sticky Shift, then Tab) now goes back in
  every scene window (the host did not know `KEY_BTAB`).
* **Certus placeholder, a11ydemo, themetest (gui test)**: three labels; the
  measuring app of the accessibility tree (entry, password field, check box,
  three buttons with bus actions, list); the window the theme-switching cost is
  measured on. `tools/a11y/run.sh` 58/0 with them.
* **Found on the way, fixed: the scene host exported a secret field's TEXT as
  the node's name.** The lock screen, the sign-in screen and the installer
  would have shown a typed password to every reader of the tree. A secret
  field is now role `password`, state `protected`, only the name the program
  gave it (`fuiscene.ax_name`), value 0; `tools/a11y/scene.sh` holds the canary
  `GEHEIMNIS7` in a secret field and finds it nowhere (25/0). Disabled controls
  also export "not enabled" now (a press on them is refused by the kernel).
* **Host additions:** `fuiscene.caret_on()`, `fuiscene.ax_name`, Shift+Tab; the
  program asks `AXI_ON` every 4 steps instead of 64 (a program that sleeps in
  its idle loop took seconds to notice the first reader).
* **Clipboard in the fields of the scene host (r379):** Ctrl+C / Ctrl+X copy
  and cut what is selected (a one-line field knows one selection: everything,
  Ctrl+A), Ctrl+V pastes at the caret or over the selection. A SECRET field
  gives nothing out, not on copy and not on cut. `tools/sceneclip/run.sh` 6/0
  (copy, cut, replace, secret field + canary, counter-proof without a
  selection). This was the one feature the wlib fields had and the scene fields
  did not (K15 section 7); it has to be there before the wlib widget list can go.
* **Size tripwire (`tools/progsize/run.sh`):** every scene-tree program carries
  fUi's scene host (~1.6 MB), the file manager is the largest at 2 133 536
  octets -- a file of an OFS format-2 image holds 2 134 016 at most, and 26
  image builders (K15 among them) still build format 2. The clipboard made it
  2 137 632 and `mkfs` refused it (K15 and the alltag file-manager runs went
  red); the clipboard and the password names were then cut down to fit again
  (480 octets of room, the code segment 121 octets before its page boundary).
  The tripwire fails when the room drops below 256 octets. The way out for good:
  move the 26 builders to format 3 (K15 section 15d pins format 2's layout, so
  K15 itself needs a format-2 image) or share the host between programs.
* Test helper: `tools/alltag/build.sh passwdfile=<host file>` puts a whole
  `/etc/passwd` (accounts with uid >= 1000) on the disk.

## 13. Stage 1 of the task bar (r381, 06.10.2026)

The bar (`taskbar.fi`, ~7 600 lines) is **window 0 of the scene host** now, and its
rectangles are **nodes of a tree**. Painting is not rewritten (that is stage 2): every
rectangle is still painted by the bar's own painters into the same one-band surface, so
the pictures of `look`, `themestore`, `glyphe`, `netview`, `alltag` ... are the proof that
nothing moved.

What changed:

* **The window.** `fuiscene.open_plain` instead of a raw `WM_CREATE`; its buffer holds the
  area of the largest configuration (a vertical bar `V_MAX` wide or a horizontal one
  `h_max()` high, laid out as screen-width x rows). `qs.init` no longer calls
  `foreign_main()`: window 0 is a real one, the quick settings, tooltip, toast and the task
  view card are windows 1..4.
* **The picture.** `wlibc.push` (a band into the window server) is `bar_push` now: the band is
  copied into `bar_r`, a retained picture of the whole bar. The host paints the tree first and
  then calls the program's **overlay** (`fuiscene.set_overlay`, between the scene and the focus
  ring): `bar_overlay` copies `bar_r` over everything. So what the host draws on top (the focus
  ring) lands on the bar's own picture, and nothing is lost when the host repaints for any reason.
* **The tree.** One row per line of the bar (a horizontal bar is one row), spacers where
  there is room between two rectangles, a **ghost button** (`fuiscene.ghost_button`: a button
  whose face the program covers with its own picture) for each rectangle: start, task view,
  chevron, every pin, every window button, every status field, every extension widget. A node
  carries the name a screen reader says (title, pin name, the text of the field, "Network" for
  the icon-only network field) and a bus action (`taskbar.start`, `taskbar.taskview`,
  `taskbar.chevron`, `taskbar.pin.<name>`, `taskbar.quick`). It is rebuilt after every paint.
* **The pointer** is not the host's: `fuiscene.set_raw` gives every pointer / key event of window
  0 to `bar_raw` first (the old `EV_DOWN` code, unchanged: right click, a press on a pin that
  becomes a drag after six pixels, `click`), and `raw_take()` makes the host skip it. The drag, the
  hide and the hover logic still poll the pointer, as before.
* **The keyboard (new): Super+T** gives the keyboard to the bar (`WS_KEYS`, wlib's keyboard focus to
  the bar's canvas, focus on the first node); Tab / Shift+Tab walk the nodes, the focus ring is the
  host's, Enter or Space presses the focused node (the same as a click in its middle), Escape, a
  press of the pointer or an activation give the keyboard back. While it is on the window server
  hands keys to the bar AND the focused program, so it ends at the first use.

Rules found on the way:

* **The tree is for reading.** `ax_press` (kernel/sys/sysgui.fi) presses buttons of application
  windows only (layer L_NORMAL, reason 5 otherwise): no program with the bus right can press the
  start button or a quick-settings tile. The nodes of the bar are names and places; a press from
  the bus is refused (`tools/barscene` checks that it is, and that the bar sees no click).
* A custom painter (`node_set_draw`) runs AFTER what the node's kind paints: a ghost button's face
  and label are painted, then the overlay covers them. A node kind that paints nothing would be
  cleaner (roadmap).
* wlib hands Tab to a canvas only while the canvas is its focus widget, and the last window that
  opened holds it (`fuiscene.focus_canvas`).
* The bar's size: 2 126 160 octets of the 2 134 016 of an OFS format-2 file (page-granular: the
  conf writer's twenty copies of four statements were folded into `wk_num` / `wk_txt` and the
  sort of the nodes works on an index array to stay under it; `tools/progsize` watches the bar).

Test: `tools/barscene/run.sh` (29/0): the tree with the names, the bus actions, a node at the
rectangle the bar traced (within one pixel), a press refused by the target rule and no click, the
keyboard path Super+T, Tab, Enter that opens the task view card. Counter-proof
`BARROOT=<old tree>`: the bar of the older tree has no tree.

Not done (stage 2 and on): painting the rectangles from fUi's widgets instead of the bar's
painters (`paint_band`, 800 lines), the layout in flex boxes instead of `layout()`, the pointer
through the host, auto-hide and drag in the host. Lines on the scene tree (by window): the bar
now counts as a scene window for its tree and events, not yet for its painting.
