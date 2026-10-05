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

## Why the task bar's tooltip, toast and quick settings are not on it yet

* A scene window cannot be opened and closed per hover: `wlib` never frees the
  widget slots (`MAXWD` = 224) of a closed window, and every scene window costs a
  few. Overlays of changing size need window re-use and a programmatic resize
  first (roadmap).
* The quick settings (`qs.fi`, 2900 lines) are measured to the pixel by
  `tools/netview/kachel.py` and `checkshot.py` at the places `qs: sym` reports:
  those checkers have to be rewritten together with the panel.

## Limits

* At most `MAXWIN` = 6 windows.
* Tables, text fields, the text area and the editor use tables that live in
  `fuied` (global): a program uses them in window 0 only. Windows 1.. are for
  labels, buttons, cards, canvases, progress bars: panels, tips, toasts.
* A window costs about 260 KB of heap.

## Measured

`tools/a11y/scene.sh` section 5 starts `scenedemo multi` (two windows): both
windows have their own tree, a press through the tree in window 2 reaches the
program, and the program changes the labels of both windows.
