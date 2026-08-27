# Addendum TASKBAR — the bar has a position

Branch `taskbar-edge`, on top of round DESKTOP. 27 August 2026.

Justin asked whether the taskbar can be dragged to another screen edge,
the way Windows 10 could and Windows 11 no longer can. It could not.
`kernel/user/leiste.fi` had no position at all: the bar was at the bottom
because `py = sh - PH` stood in the source, and there was nothing to
change. This addendum gives it one, in the two ways one expects — by
dragging it, and by setting it — and gives the window server the concept
that makes either of them useful: a **work area**.

---

## 1. What is new

| | |
|---|---|
| Edges | `bottom`, `top`, `left`, `right`. Left and right are a **vertical bar** with a different layout, not a rotated rectangle. |
| Set by dragging | press on an empty part of the bar, pull towards an edge, let go. A preview **rectangle** follows the pointer. |
| Set in the settings | `/bin/einstellungen`, page *Darstellung*: edge, thickness, auto-hide, always-on-top. |
| One place for the state | `/etc/taskbar.conf`. Both writers write it, the bar reads it — at start and twice a second afterwards, so a change in the settings arrives without a restart. |
| Thickness | two keys, `height` for a horizontal bar and `width` for a vertical one, because they are two different numbers. |
| Auto-hide | the bar slides out to a two-pixel sliver and comes back when the pointer touches the edge. |
| Always on top | on: layer `L_TOP`. Off: the ordinary layer — other windows may cover it. |
| Work area | the server subtracts every reserved edge from the screen; maximized windows fill the remainder and **follow it** when it changes. |

`/etc/taskbar.conf`:

```
# taskbar.conf -- written by /bin/leiste and /bin/einstellungen
edge=left
height=28
width=104
autohide=0
ontop=1
```

---

## 2. The work area — the interface the round TILING will need

This is the part that is not about the taskbar. X11 has had it since
1997 under the name `_NET_WM_STRUT`: a window declares how many pixels of
which screen edge it occupies, the window manager subtracts every such
reservation from the screen, and what is left is the **work area**. All
layout arithmetic uses the work area and not the screen.

Here it is one word in the window record and four scalars for the
result:

```
W_STRUT  == 0                          this window reserves nothing
W_STRUT  == (edge + 1) | (size << 8)   it reserves `size` pixels of `edge`
```

**In the server** (`kernel/wm.fi`, one block, marked
`ADDENDUM TASKBAR`):

| call | what it does |
|---|---|
| `work_x/y/w/h(state)` | the free rectangle. Never degenerate: a strut that would leave less than 64 × 64 is refused and the work area stays the screen. |
| `set_strut(state, i, edge, size)` | declare (`size > 0`) or clear (`size == 0`). Recomputes the work area **and refits every maximized window** in the same call. |
| `maximize(state, i, on)` | fill the work area, not the screen, and remember where the window was. **This is the one call a tiling layout replaces**; the work area underneath it stays. |
| `is_max`, `win_strut_edge`, `win_strut_size` | read back. |
| `recalc_work(state)` | recompute from scratch. Called by `set_strut`, by `set_hidden`, by `destroy` and by `init`. |

**The rule, and it is the whole design:** whoever changes a strut, a
screen size, or the visibility of a window that holds a strut calls
`recalc_work`, and `recalc_work` refits the maximized windows. Nobody
caches the work area anywhere else. There is exactly one copy of this
state, and `tools/desktop/rects.py` checks that the copy the taskbar
reads back through `WM_INFO` is the same one the server holds.

**In the system call table** (`kernel/sys.fi`):

| number | call | who may |
|---:|---|---|
| 2112 | `WM_STRUT (h, edge, size)` | root, with `R_MANAGE` |
| 2113 | `WM_SIZE (h, wh)` | the owner, with `R_MANAGE` |
| — | `WM_STATE (h, WS_MAXIMIZED, 0/1)` | the owner |
| — | `WM_INFO (h, WI_WORKX..WI_WORKH)` | **anyone with a handle** |

Reserving an edge is a privilege; knowing where the free rectangle is
is not. A tiling window manager needs only the last row of that table.

**For TILING specifically:** the root rectangle of the frame tree is
`work_x/y/w/h`, not the screen, and it changes at exactly one moment —
when `recalc_work` runs. If the tree needs to be told, the hook goes
into `refit_max`, which is four lines long and already exists for
exactly this purpose.

### What had to change in `kernel/wm.fi`, listed separately

The instruction was to stay out of the window server where possible. The
diff there is:

| change | lines | why it could not be elsewhere |
|---|---:|---|
| `W_STRUT`, `W_SAVE` in the window record | 2 | the reservation belongs to the window |
| `EDGE_*`, `F_MAXIMIZED`, seven scalars | 12 | the work area is server state |
| `recalc_work`, `refit_max`, `fit_work`, `set_strut`, `maximize`, `is_max`, readers | ~200 | the arithmetic |
| hooks in `init`, `create`, `destroy`, `set_hidden` | 12 | a strut has to disappear with its window |
| self-tests 22–30 | ~90 | |
| **fix**: `title_text` read the title through `WM_OFF` | 1 | see section 7 |

Nothing in the compositor, the hit test, the event path or the input
handling was touched.

---

## 3. A vertical bar is not a rotated horizontal one

At the left and right edge the start button sits at the top, the window
buttons stack downwards, and the three status fields sit at the bottom,
one above the other. The interesting part is the text.

Each status field measures its own string (`text_w`) against the width
it has. If it fits, one line. If not, it **wraps** at a sensible
character — the last dot of an address, the space of `Battery 87%` — and
becomes two lines. Only if a half still does not fit is it shortened,
and then the **shortened** text is what the bar reports, so that what the
runner checks character by character is what is on the screen. Nothing
is silently clipped.

At the measured default (`width=104`, UI font 15 px) nothing had to wrap:

| field | text | lines |
|---|---|---:|
| `net` | `no network` | 1 |
| `battery` | `no battery` | 1 |
| `clock` | `07:25` | 1 |

(The machine under test has no battery and no DHCP lease; those are the
honest strings, not placeholders. A percentage this machine cannot
measure is not printed as zero.)

---

## 4. What was measured

`bash tools/desktop/run.sh` — **102 claims, 0 failures**, eleven QEMU
boots, real mouse packets through the QEMU monitor, eight screenshots
through `screendump`. They are committed as PNG under
[`docs/shots/taskbar/`](shots/taskbar): `bottom`, `top`, `left`,
`right`, `nostrut`, `after-drag`, `autohide`, `settings`.

### 4.1 The four edges, by arithmetic

`tools/desktop/rects.py` takes three independent numbers — the server's
window table, the server's work area, and the work area the taskbar reads
back from ring 3 — and checks that the bar is on its edge, that the work
area is the screen minus the bar exactly, that the maximized window IS
the work area, and that the two rectangles share no pixel and leave no
gap.

| edge | bar rectangle | work area | maximized window | overlap |
|---|---|---|---|---:|
| bottom | 0, 572, 800, 28 | 0, 0, 800, 572 | 0, 0, 800, 572 | **0 px** |
| top | 0, 0, 800, 28 | 0, 28, 800, 572 | 0, 28, 800, 572 | **0 px** |
| left | 0, 0, 104, 600 | 104, 0, 696, 600 | 104, 0, 696, 600 | **0 px** |
| right | 696, 0, 104, 600 | 0, 0, 696, 600 | 0, 0, 696, 600 | **0 px** |

Window area + bar area = 800 × 600 in every row: no overlap, and no gap
either.

### 4.2 The counter-test

Same picture, kernel started with the word `nostrut`:

| | |
|---|---|
| work area | 0, 0, 800, 600 — the whole screen |
| maximized window | 0, 0, 800, 600 |
| overlap with the bar | **22 400 px** — the bar is completely covered |

And `rects.py --nostrut` applied to the *normal* run fails, as it must:
a checker that accepts both states checks nothing.

### 4.3 The text, per character

Position and both colours come from what the application reported;
every inked pixel of every glyph is recomputed in the picture against a
second, independent rasterization (`tools/gfx/schau.py tkette`).
Tolerance zero. This is the lesson of round K7B, where text was "87 per
cent correct" while every letter was missing.

| edge | `Start` | clock | battery | net | window button | total |
|---|---:|---:|---:|---:|---:|---:|
| bottom | 200 / **0** | 210 / **0** | 406 / **0** | 435 / **0** | 458 / **0** | 1709 / **0** |
| top | 200 / **0** | 210 / **0** | 406 / **0** | 435 / **0** | 458 / **0** | 1709 / **0** |
| left | 200 / **0** | 216 / **0** | 406 / **0** | 435 / **0** | 361 / **0** | 1618 / **0** |
| right | 200 / **0** | 216 / **0** | 406 / **0** | 435 / **0** | 361 / **0** | 1618 / **0** |

(inked pixels checked / wrong — **6654 pixels, 0 wrong**, tolerance zero)

The window button reads `Terminal -- sh` at the horizontal edges and
`Terminal -- ` at the vertical ones: 98 pixels of button width instead
of 132, so the label was shortened — and the SHORTENED text is what was
reported and what was checked. That is the difference between shortening
and clipping.

### 4.4 Dragging

Real mouse packets: press at (520, 586) on an empty part of the bottom
bar, pull to the left edge, release.

| | |
|---|---|
| preview rectangles drawn | 2 (edge 0 → edge 2) |
| after release | `taskbar: drag done edge=2 written=1` |
| new geometry | x=0 y=0 w=104 h=600, `vertical=1` |
| new work area | x=104 y=0 w=696 h=600 |
| `/etc/taskbar.conf` **read back out of the disk image** | `edge=left` |

### 4.5 It survives a restart

The same disk image, booted a second time, no monitor input:

| | |
|---|---|
| `taskbar: conf ... ename=left src=file` | the bar comes up on the left |
| rectangles | bar 0,0,104,600 — work 104,0,696,600 — maximized 104,0,696,600, overlap 0 |

### 4.6 Auto-hide

| | |
|---|---:|
| pointer leaves the bar → bar slides out | yes |
| pointer reaches the edge → **bar stands there again after** | **60 ms** |
| reservation while out, and while in | **2 px, both** |
| work area with auto-hide on | 800 × 598 |

The reservation is a sliver in **both** states on purpose. Reserving the
full height while the bar is out and nothing while it is in would resize
every maximized window twice a second as the pointer wanders past;
Windows keeps a sliver for the same reason.

**About that millisecond number.** Ticks are 10 ms in this kernel
(`kernel/time.fi`, `TICK_HZ = 100`), so the resolution of the figure is
ten milliseconds and not one. What is timed is resize + move + reserve +
draw — the work the user waits for. The first version also had the whole
layout report inside the timed region and measured 230 ms, most of which
was the serial line; that was a measurement of the logging, and it was
moved out.

### 4.7 The settings write the same file

Three real clicks in `/bin/einstellungen`: open the drop-down, take the
row `right`, press *Uebernehmen*.

| | |
|---|---|
| `settings: menu took i=6 row=3` | the row was really clicked |
| `settings: taskbar edge=right ... wrote=1` | the file was really written |
| `taskbar: conf ... ename=right` | the **taskbar**, a different process, re-read it |
| `taskbar: geom x=696 y=0 w=104 h=600` | and moved |

Nothing passes between the two processes but `/etc/taskbar.conf`.

---

## 5. Two defects found on the way, both older than this addendum

**1. Every window title on the screen was empty.** Round DESKTOP moved
the window table out of `WM_OFF` into `DSK_OFF` and changed `wat()` and
`set_title()` accordingly — but `title_text()`, twelve hundred lines
further down, kept adding `kstate.WM_OFF` on top of an offset that
already carried `DSK_OFF`. It read zeros. Three claims in
`tools/wm/run.sh` said so in plain words ("LEER: K l i c k m i c h") and
the round shipped anyway. Measured, not guessed:

| tree | `tools/wm/run.sh` |
|---|---|
| `main` (3389fbd) | 103 passed, 0 failed |
| round DESKTOP (d7bdcfc) | 100 passed, **3 failed** — the three titles |
| this branch | 103 passed, 0 failed — the one-line fix |

**2. `kernel/user/leiste.fi` had never been compiled.** Round DESKTOP
wrote 695 lines of taskbar and no runner to build them; the file did not
parse (`*%` at the start of a continuation line). Neither did
`einstellungen.fi` build against the library after this addendum touched
it. Both are in the build list of `tools/desktop/run.sh` now, out of
**both** compilers, and the kernel image is checked for their symbols to
show they live in ring 3.

**3. The choice widgets in `/bin/einstellungen` never opened.** `wlib`
fires `K_CHOICE` with index `0x1000` and leaves it to the application to
open the menu; the application did not. Resolution, time zone and DHCP
were pictures of drop-downs. They work now — the same handler serves the
taskbar edge.

---

## 6. Self-tests and the older runners

| | `main` (3389fbd) | round DESKTOP (d7bdcfc) | this branch |
|---|---:|---:|---:|
| `wm.selftest` | 17 / 17 | **20 / 21** | **30 / 30** |
| `tools/wm/run.sh` | **103 passed, 0 failed** | 100 passed, **3 failed** | **103 passed, 0 failed** |
| `tools/k15/run.sh` | 251 passed, 0 failed | — | **251 passed, 0 failed** |
| `tools/desktop/run.sh` | did not exist | did not exist | **102 passed, 0 failed** |

All three numbers were measured, not assumed: `main` and `d7bdcfc` were
checked out into their own worktrees and run.

Claims 22–30 in `wm.selftest` are the new ones: work area without a
strut, a bottom strut, maximize into the work area, disjointness, moving
the strut to another edge and the window following, the `nostrut`
counter-test, clearing a strut, a strut disappearing with its window,
and restoring a maximized window to where it was.

The counter-tests on the command line are unchanged and still reachable:
`nolayer`, `nomin`, and now `nostrut` and `wmax`.

---

## 7. What is NOT proven

- **Nothing here was run on real hardware.** Every number comes from
  QEMU with `-vga std` at 800 × 600. The mouse is a PS/2 device driven
  through the QEMU monitor.
- **Only one screen.** There is no multi-monitor concept in this system,
  so "which screen does the bar sit on" is not a question that has been
  asked, let alone answered.
- **The thickness limits are limits.** A window never gets a bigger
  buffer than it was created with, so the bar is created at 128 × 600 and
  `width` is capped at 128 and `height` at 40. Beyond that `WM_SIZE`
  refuses — correctly, and audibly, but it refuses.
- **The preview is an outline, not a translucent sheet.** Four thin
  always-on-top windows. A filled 128 × 600 window is 300 kilooctets of
  buffer and this process has 832 for the bar, the preview and the
  drawing surface together. There is no alpha blending between windows
  in this compositor at all.
- **The drag is measured along one path only** — bottom to left. The
  other five pairs are not driven by mouse; what is driven for all four
  edges is the configuration path.
- **Auto-hide has no delay and no animation.** The bar disappears the
  moment the pointer leaves its rectangle and appears the moment the
  pointer touches the edge. Windows waits about a third of a second and
  slides; this does neither.
- **The millisecond figure has 10 ms resolution** and was taken once, on
  a loaded build machine. It is an order of magnitude, not a benchmark.
- **`ontop=0` is only exercised through the file.** It is read, it is
  applied (`WS_LAYER` to `L_NORMAL`), and the window server's own
  self-tests cover the layers — but there is no measurement in this
  runner that shows an ordinary window covering the bar.
- **The user interface is half German.** The tab is still called
  *Darstellung* and the buttons still say *Uebernehmen*; everything this
  addendum added is English. The parallel round RENAME owns that
  translation, and the same round renames `leiste.fi` to `taskbar.fi`,
  which is why this file still carries its old name.
- **The clock is not a clock.** It is the hardware clock plus an offset
  from `/etc/time.conf`. This kernel can read the RTC and not set it.
