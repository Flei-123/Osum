# fUi scene host: several windows in one program

`kernel/user/fuiscene.fi` used to be a one-window host: one scene, one
stylesheet, one set of tables and entries, all in module statics. A program
that needs more than one window (the task bar: bar, preview, tooltip, toast,
quick settings) could not be put on it.

## How it works now

* ALL the state of one window is `struct Ctx` and the selected window is the
  static `S` (so the code of the host did not change, only `s_x` became
  `S.s_x`).
* Every other window is a **saved copy of a `Ctx` in heap memory**. Selecting
  a window = copy `S` out, copy the other window in (2 x ~260 KB, a few tens
  of microseconds). `win_busy(i)` looks into the saved copy, so a window that
  has nothing to do is never switched to.
* `fuiapp` keeps eight words per window (window number, canvas widget, pixel
  buffer, size ...); `fuiapp.win_save/win_load` move them, and `win_load`
  points fUi's one painting canvas at the window's pixels again.
* The canvas events of `wlib` are one ring for the process; word 0 of an event
  is the canvas widget. `wlib.canvas_event_for(widget)` takes one canvas's
  events out and leaves the others in place, so every window reads only its own.
* Accessibility: node ids are `AXP_BASE + window * 256 + node`; the hook
  collects the nodes of all windows, a press selects the window it belongs to
  and puts the previously selected one back.

## API (all in `fuiscene`)

```
open(...) / open_plain(...)          window 0, as before
win_open(x,y,w,h,title,build)        another framed window   -> number | BADWIN
win_open_plain(x,y,w,h,title,layer,build)   a frameless one on a layer
win_select(i) / win_cur() / win_count()
pump_all()      one system step, then every busy window takes its events,
                rebuilds, paints; returns the first key a window answered
hit_win()       which window that key came from (that window is selected)
pump_win(i)     one step of ONE window, for a program with its own loop
pump_aux(i)     the same for a program whose main window is NOT a scene window
                (the task bar): never waits, the program's own loop does the step
foreign_main()  reserve window 0 for such a foreign main window (never pumped, no
                a11y nodes); the scene windows are 1..
win_close(i)    take a window off the screen (its number stays taken)
quit()/alive()  the program ends when ANY window said quit
```

Every other function works on the **selected** window. A program does

```
let tip: u64 = fuiscene.win_open_plain(x, y, w, h, title, layer, build_tip)
...
let key: u64 = fuiscene.pump_all()
if key == 90 && fuiscene.hit_win() == tip { ... }
fuiscene.win_select(tip)      // talk to that window
fuiscene.refresh()
fuiscene.win_select(0)
```

## The bar's quick settings, tooltip and toast are on it (05.10.2026)

The task bar (`taskbar.fi`) keeps its own raw window as window 0
(`fuiscene.foreign_main()`, called by `qs.init`) and has three scene windows:

| window | what | layer | created | life |
|---|---|---|---|---|
| 1 | quick settings (`qs.fi`): card, tiles, two sliders, separator, footer | `L_MENUE` | at start, hidden | shown on Super+A / a click on the icon group |
| 2 | tooltip (`barpop.fi`) | `L_TIP` | at start, hidden, 480 x 40 points | text -> `WM_SIZE` -> repaint -> `WM_MOVE` -> show |
| 3 | toast (`barpop.fi`) | `L_TIP` | at start, hidden, 640 x 64 points | the same |

Why this works now although it did not: nothing is opened and closed per hover.
A window can **shrink** below the size it was created with and grow back up to it
for free (the server keeps the buffer, `wm.resize_win`); growing past it allocates a
new buffer and leaks the old one, so a pop-up that changes its size is created at its
largest. `fuiscene.win_size` sends `WM_SIZE` and tells wlib at once
(`wlib.note_resize`, the same book-keeping as the `E_RESIZE` handler -- the bar does
not call `wlib.step` every turn and cannot wait for the event); the next `pump_aux`
rebinds fUi to a buffer of the new size (`fuiapp.resize`, which now accepts windows
down to 16 x 8 pixels).

The panel is pumped with `fuiscene.pump_aux` only while it is open -- an idle
panel costs the bar nothing. While it is open the bar's loop also calls
`wlib.step()`: that feeds the window's pointer and key events to its canvas. Two
details that cost an afternoon:

* the window server gives the keyboard to a window that asked for it (`WS_KEYS`)
  only when the window is **visible** at that moment: `qs.open_at` sets `WS_KEYS`
  again after `WS_HIDDEN 0` (the bar may not raise its own window, `WM_ACT`
  answers `E_RIGHTS`);
* a tile is a **button face of fUi plus the program's own picture**
  (`fuiscene.tile`: plate, hover, press, focus ring, accent fill when on; the
  callback paints the glyph and the label lines), a pop-up is **one canvas node**
  painted with the same calls (`cv_round_rgb`, `cv_ring_rgb`, `cv_text_rgb`).

Still not a tree: **the bar itself** (start button, window buttons, pins, status
fields, clock) -- 7 400 lines of its own layout and painting. It is painted with
fUi's painter through `wlib.draw_*`, but it is not a scene.

## Limits

* At most `MAXWIN` = 6 windows (the task bar uses four: its own and three scene windows).
* Tables, text fields, the text area and the editor use tables that live in
  `fuied` (global): a program uses them in window 0 only. Windows 1.. are for
  labels, buttons, cards, canvases, progress bars: panels, tips, toasts.
* A window costs about 260 KB of heap.

## Measured

`tools/a11y/scene.sh` section 5 starts `scenedemo multi` (two windows): both
windows have their own tree, a press through the tree in window 2 reaches the
program, and the program changes the labels of both windows.
