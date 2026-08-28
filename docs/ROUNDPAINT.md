# Round PAINT — the mixing, the edge, the shadow, and what each costs

Justin asked why Windows 11 looks the way it does and OrientOS does not,
and whether it is the fault of the language Firn.

It is not Firn. It is also not, as the brief for this round assumed, a
missing colour mix — that turned out to be half true in a way that
matters, and the half that was false is where the interesting bug was.

**Every number below came out of a run.** Where a number is missing it
says so. Where a claim from a previous round turned out to be wrong it
says which one, and where a claim *of this round* was overturned by its
own measurement, that is in section 2.

---

## 0. THE RULE OF THIS ROUND, FIRST

> **A claim about the screen is a claim about pixels, and it is only
> worth making if the pixels were counted — and if the price is written
> next to it.** "Looks better" is not a result. Cycles, or pixels per
> second.

This is round LOOK's rule with one line added. Round LOOK proved that a
picture claim without pixel counting is worthless; this round adds that
a new capability without its price is half an answer.

### The honest limits, before the achievements

* **There is no GPU and this round did not invent one.** Everything is
  the CPU writing into a linear framebuffer.
* **The measuring machine has no `/dev/kvm`.** `ls /dev/kvm` says *No
  such file*. QEMU translates every guest instruction (TCG), and that
  hits `rep stosq` (one TCG building block, mapped onto the host's
  `memset`) and a thirty-instruction per-pixel loop *very* differently.
  Every ratio measured inside QEMU is therefore also measured natively
  on the host (`tools/paint/native.c`), and both numbers are printed.
  See section 2.
* **The glyph rasteriser was NOT improved**, and that is a decision out
  of a measurement, not an omission. Section 4.
* **The shadow is a linear falloff, not a Gaussian blur.** A blur needs
  a second full-screen buffer and two passes over it. At the four to six
  pixels a window shadow uses, the difference is not visible; the claim
  that it is not visible is an argument, not a measurement, and it is
  the one unmeasured claim in this document.
* **Nothing moves.** There is no frame clock in this system. Section 8
  writes down what a motion round would need and what it would cost, and
  builds none of it.

---

## 1. WHAT WAS ACTUALLY MISSING — the grep that asked the wrong three files

The brief measured:

```
grep -rn 'alpha|blend|antialias|coverage|subpixel' --include=*.fi \
     kernel/wig.fi kernel/ttf.fi kernel/fb.fi lib/
```

— zero hits, and concluded there is no colour mixing anywhere in the
drawing path. Re-measured across the whole tree:

| where | mixes? | since |
|---|---|---|
| `kernel/wm.fi` `blend` | **yes** | round K10 |
| `kernel/user/wlibc.fi` `blend` | **yes** | round K10 |
| `kernel/ttf.fi` rasteriser | **yes**, 4×4, 17 coverage levels | round K10 |
| `kernel/user/wlibc.fi` `rrect`/`rring`/`drop_shadow` | **yes** | round LOOK |
| **`kernel/fb.fi`** | **no** | — |
| **`kernel/wig.fi`** | **no** | — |

Two reasons the grep found nothing. This tree names the thing in German
— `Deckung`, `mischen`, `Kantenglaettung` — and two of the three files
searched have no business mixing anything (`wig.fi` moves rectangles;
it is a seam, not a painter).

So the true statement is narrower and more useful:

> **The bottom of the drawing path could set a pixel and read a pixel,
> and nothing else. Everything above it had learnt to mix; the floor had
> not.** And the compositor — the one place that knows what is *under* a
> window — never mixed at all.

That is what sections 2, 5 and 6 fix.

---

## 2. src-over IN `fb.fi`, AND A ROUNDING THAT WAS WRONG IN 48.67 % OF CASES

`fb.blend`, `fb.pixel_a`, `fb.hline_a`, `fb.fill_a`, three counters
(`blends`, `blend_reads`, `blend_skips`) and fourteen assertions checked
by the kernel itself (`fb.selftest3`, 14 of 14).

### 2.1 The rounding

src-over with premultiplied coverage *a* (0..255) is

```
out = (src * a + dst * (255 - a)) / 255
```

There were **four** copies of that line in this tree
(`kernel/wm.fi`, `kernel/user/wlibc.fi`, `tools/gfx/checkshot.py`, and
now `kernel/fb.fi`), and a **fifth** in `tools/icons/sheet.py` that had
always rounded differently. Three of them divided by 255 and *truncated*.

Measured over **all 256 · 256 · 256 = 16 777 216 triples** (a, src, dst)
against the exact, half-up rounded value — `tools/paint/blendcheck.py`:

| version | max error | mean | wrong |
|---|---|---|---|
| truncate (what stood there) | 1 | 0.4867 | **8 164 890 = 48.67 %** |
| `(num + 127) / 255` | 0 | 0 | 0 |
| `(t + (t>>8)) >> 8`, t = num + 128 | 0 | 0 | 0 |

Not a rounding *style*: on nearly half of all possible blends the system
put down a value that was one step off, always in the same direction.
Under a tolerance-based screenshot check that is invisible, which is
exactly why it survived three rounds.

All five now round the same way, and `blendcheck.py --quellen` checks
the five source locations as well as the arithmetic — a formula that
lives in five places is wrong in four of them the moment somebody edits
one.

### 2.2 AND THEN THE MEASUREMENT OVERTURNED THIS ROUND'S OWN REASONING

The first version of `fb.mix8` used the shift form and justified it in a
comment: *"a division is twenty to forty cycles on x86-64 and not
pipelined."* Both versions were then built and measured — same kernel,
same machine, same command line:

| | cycles per pixel (QEMU) | cycles per pixel (native) | image size |
|---|---|---|---|
| division `(num+127)/255` | **526** | **6.17** | 2 846 920 |
| shift `(t+(t>>8))>>8` | 646 | 6.65 | 2 846 920 |

The division wins by a fifth and does not cost one octet more. So the
division is what stands there, and the comment that argued against it
stands next to it with the numbers that beat it.

### 2.3 What the mixing costs

`paintbench` in the kernel, four passes over the whole screen, opaque
`fb.fill` (which is `rep stosq`) against blended `fb.fill_a` at a = 128
(a value that misses *both* shortcuts — measuring the fast path and
calling it a blend would be lying):

| | opaque | blended | per pixel |
|---|---|---|---|
| 800 × 600 = 480 000 px | 3 859 344 cyc | 310 107 776 cyc | 8.04 / 646 |
| 1024 × 768 = 786 432 px | 4 827 883 cyc | 493 105 316 cyc | 6.14 / 627 |

A factor of about 80 — and **that factor belongs to the emulator, not
to the arithmetic.** The same two loops compiled for the host
(`tools/paint/native.c`, `-O2 -fno-tree-vectorize`, 20 passes over
800×600):

```
   fuellen (opak)            428 985 cycles   0.894 per pixel
   mischen (schieben)      3 190 509 cycles   6.647 per pixel
   mischen (Division)      2 961 394 cycles   6.170 per pixel
   faktor mischen/opak     7.44
```

**7.4×, not 80×.** A full 800×600 blended fill costs about 3 million
cycles on real hardware — roughly a millisecond at 3 GHz. That is the
honest number, and it is why the shadow in section 6 is drawn as
outlines and not as an area.

---

## 3. THE BUG THIS ROUND ACTUALLY FOUND — two rounds on one address

Looking for three free words in `kernel/wm.fi` for the window's *form*:

```
const S_TILE: u64 = 0x180      // round TILING
const S_DECO: u64 = 0x180      // round THEME, ELEVEN words
```

Both go through the same `gs`/`ss` into the same block
(`kstate.WM_OFF`). This is round K7B's bug one level down — the font and
the signal table both on 0x2F000: each branch green on its own, no
shared *line*, only a shared *address*, and a text merge cannot see it.

Every one of the eleven colours `deco_push` writes also landed in a
tiling scalar:

| colour | also became |
|---|---|
| `DK_FRAME + 1` | `S_TILE` — tiling reads as ON |
| `DK_TITLE + 1` | `S_PVON` — a drag preview is on screen |
| `DK_TEXT + 1` | `S_PVX` — its coordinates are colours |
| `DK_FRAME_ON + 1` | `S_PVY` |
| `DK_TITLE_ON + 1` | `S_PVW` |
| `DK_TEXT_ON + 1` | `S_PVH` |
| … | `S_DROPN`, `S_DROPS`, `S_DROPE`, `S_DRAGT`, `S_HOTS` |

And the other way: **every keyboard shortcut incremented `S_HOTS` and
therefore changed the background colour of a terminal window.**

A second hit beside it: `S_DECON`, the write counter, sat on 0x1C0
because the block had eight words when it was written (*"acht Woerter,
0x180 .. 0x1B8"* — the comment was still there). Round MERGE grew it to
eleven and did not move the counter, so 0x1C0 was both the counter and
slot 8, the desktop background colour.

### 3.1 Measured with exactly one variable changed

`/root/paintrun/isolate` is branch `look` plus **only** the thirteen
relocated constants — not one other line:

```
look            wm: win nr=4 ... x=0   y=0   w=796 h=576   t=[Suchen]
look+relocation wm: win nr=4 ... x=190 y=110 w=440 h=300   t=[Suchen]
```

The search dialog filled the entire screen, because `DK_FRAME` landed in
`S_TILE`, the tiling manager read itself as enabled and `wm.create` put
every new window into the tree. **387 093 of 480 000 desktop pixels
(80.6 %) change from that relocation alone.**

That is a large part of the answer to "why does it look old". It was not
a design. It was two constants.

### 3.2 Found mechanically, not by reading

`tools/paint/scalars.py` reads every `const S_…: u64 = 0x…` of a file
and intersects them pairwise, taking the length from the comment or from
a length constant. **376 scalars in 67 files, 13 overlaps — all thirteen
in `wm.fi`, all thirteen these.** After the relocation: 0.

The checker had to learn what is *not* an offset first: `sched.fi`,
`ansi.fi` and `netmon.fi` write task states and field numbers as
`const S_x: u64 = 0, 1, 2`. The rule now: an offset is written in hex
and divisible by eight. Before that rule it reported 96 hits, 94 of them
false — and a checker with 94 false hits gets switched off.

New layout in `WM_OFF` (`WM_MAX` = 0x2000):

```
0x180 .. 0x1D0   THEME, eleven colour slots
0x1D8            THEME, the write counter
0x200 .. 0x258   TILING
0x280 .. 0x2B0   PAINT, the form and its counters
```

---

## 4. ANTI-ALIASING OF GLYPHS — measured, and deliberately left alone

`tools/paint/aacheck.py`, 28 characters in four sizes:

```
coverage levels per glyph    min 11, mean 15.6, max 17
levels along ONE edge        min  6, mean  8.0, max 12
```

So the glyphs are **not** a bitmask — `kernel/ttf.fi` has rastered with
4×4 sub-sampling since round K10, and the brief's expectation of "2 grey
values today" is true of the *compositor's* edges (section 5) and false
of the text.

How good is 4×4? The same algorithm at a higher sampling density —
identical bounding box, identical curve flattening, so the *only*
difference is the sampling — against 32×32 (1025 levels) as reference:

| density | levels | mean deviation | max |
|---|---|---|---|
| 4 × 4 | 17 | 3.282 of 255 (**1.287 %**) | 52 |
| 8 × 8 | 65 | 1.205 of 255 (0.473 %) | 24 |
| 16 × 16 | 257 | 0.481 of 255 (0.189 %) | 13 |

8×8 would be 2.72 times more accurate. **It was not adopted**, and the
reason is the measurement: 1.3 % of one coverage step is below the
threshold of visibility, while changing that number shifts *every*
rastered character in *every* pixel-exact screenshot in this tree. The
price is high and the gain is under the perception threshold. Rasterising
is cached per (glyph, size), so the *runtime* cost would have been
nearly nil — that was not the reason either way.

Against FreeType (through Pillow) the deviation is 20.66 of 255. That
number is **mostly hinting** — FreeType pulls stems onto the pixel grid
— and different curve flattening, not sampling; the 32×32 comparison
above is what proves it. `aacheck.py` therefore asserts a wide bound
(< 45) on the FreeType comparison, and a tight one (< 5) on the sampling.
A bound nobody can justify is a number that gets raised at the next
failure.

**No sub-pixel rendering.** It needs to know the order of the emitters
and it is wrong on a rotated panel — and `fb.fi` has had `set_rotation`
since round DISPLAY. Greyscale is honest.

---

## 5. ROUNDED WINDOW CORNERS — the token that was resolved and not drawn

docs/ROUNDLOOK.md, in its own list of honest limits:

> *"The top-level window frame is still square, and so is its shadow.
> `radius_window` and the window shadow are read out of the shape file,
> carried through the resolver and not drawn. Those pixels belong to the
> kernel's compositor, not to the widget library, and reaching them
> means widening a protocol."*

The protocol is now wider by exactly four numbers.

`WM_FORM` (2115) carries `radius`, `shadow strength`, `shadow reach`,
`shadow colour` — **resolved values, not a notion of form.** The kernel
never learns that a file called `modern.shape` exists; it learns that
the corner measures eight pixels. Same right as `WM_DECO`: only whoever
*is* a taskbar may set it, because otherwise any application could take
the shadow off any other window.

`wm.fill_round` fills the frame with the same 4×4 corner sampler that
`wlibc.corner_cov` uses in ring 3 — deliberately the same arithmetic,
because a dialog showing a window corner and a button corner with two
different curvatures is worse than two square ones. At radius 0 it is
call-for-call the old `fb.fill`.

Measured off the picture (`tools/paint/shadow.py ecke`, section 6): the
8×8 corner square carries **18** genuinely blended pixels on `modern`
and **0** on `classic`. That counter-test is in the runner — a
measurement that is always green measures nothing.

---

## 6. REAL WINDOW SHADOWS — the compositor *can* read what is underneath

Round LOOK wrote that it cannot. That was true of the **widget
library**: it paints into the buffer of its own window and sees nothing
below it. It is not true of the **window server**, and has not been
since round K10:

> **Every window already has its own buffer.** `W_BUF`, allocated in
> `wm.create` from the frame allocator (`mem.frame_run`) — *not* out of
> the 832 KiB a process gets. `compose` assembles bottom to top: the
> desktop background, then window by window in z-order. When `paint_win`
> runs for window *i*, everything below *i* is already finished in the
> framebuffer.

So part C of the brief was not a rebuild. The ground was there; nobody
had ever read it. **The memory question the brief asked to check first
does not arise**: no per-window buffer had to be allocated, because they
have existed for eleven rounds. A 796×576×4 buffer is 1.8 MiB and comes
out of the frame allocator, which is why the 832 KiB per-process limit
in `taskbar.fi` and the old 2 MiB OFS ceiling are both beside the point.

### How it is drawn, and what it costs

Not a convolution. `reach` nested rounded outlines, each one pixel
further out and each weaker than the last — a linear falloff — offset
one pixel downward per ring, which is what makes the thing read as
*above* rather than *glowing*.

The point is the complexity class: **perimeter × reach, not area.**

| | blended pixels |
|---|---|
| a 796 × 576 window, shadow as an area | 458 496 |
| the same window, `reach = 6` outlines | ≈ 17 000 |

At the native 6.17 cycles per blended pixel from section 2.3 that is
about 105 000 cycles — some 35 µs at 3 GHz — for a full repaint of a
window's shadow.

### The damage rectangle had to grow, and the first version forgot

A shadow lies *outside* the window rectangle. `wm.damage_win` now grows
by the reach on all four sides. Without that a dragged window leaves a
trail of grey edges across the desktop — the first draft did exactly
that, and it was visible immediately.

### Measured against the run that has no shadow

The first version of `tools/paint/shadow.py` read ONE row out of ONE
picture, found seven brightness steps to the left of the window and
reported green. The same seven steps were in the old picture too: what
it had measured was the desktop's own gradient. **A measurement that
cannot fail is not one.** Every assertion here therefore takes two
pictures — `classic` and `modern`, same machine, same window geometry,
one word different on the disk — and reads the pixels to the *right* of
the topmost window, where the desktop is and no second window's contents
can drift between runs.

Row y = 272, outer edge at x = 633:

```
ohne Schatten: 246 246 246 246 246 246 246 246 246
mit  Schatten: 201 208 216 223 231 238 246 246 246
Unterschied:    45  38  30  23  15   8   0   0   0
```

Six pixels darker, none lighter, the difference falling monotonically
outward from 45 to 8 brightness steps, and **zero from the seventh
pixel on** — `shadow_r = 6`, exactly as the shape file says. A shadow
that reached further than its token would be a colour bug; a shadow that
grew outward would not be a shadow.

And the corner, as blended pixels in the 8×8 corner square — pixels that
are neither the frame colour nor the background:

```
ohne Radius:  0 gemischte Bildpunkte
mit  Radius: 18 gemischte Bildpunkte
```

The counter-test is the same number: on `classic` it is **0 of 64**, and
if it were not, the assertion about `modern` would be measuring
nothing.

---

## 7. THE PROGRAM SYMBOLS IN THE TASKBAR BUTTONS

> *"wegen start terminal und suchen — warum sind das keine icons"*

The symbols have existed since round K15: `/apps/<name>.osp/symbol`,
format OSYM, drawn at the size they hang at. What was missing was the
sentence *"this window is that program"*. A window had a **title**, and
a title is translated, changes while the program runs (`Terminal -- sh`)
and is not unique.

### Two ways were possible; the choice is argued

1. **The server derives it from the program path.** Sounds cheaper. It
   is not: the path is in no task record, `procfs` reads `argv[0]`
   through the page table of the *foreign* process (`make_cmdline`) —
   once per window per repaint — and it answers *wrong* where it
   matters. `/bin/files` and `/bin/explorer` are the **same inode**
   (round K15), a program may be started through a shell script, and
   `sh` in a terminal window is not the program that owns the window.
2. **The program says so itself**, once, when it opens. This is what X11
   calls `WM_CLASS` and Windows calls `AppUserModelID`, for the same
   reason: only the application knows what it wants to appear as.

Chosen: (2). `W_APP` in the window record (24 octets), `WM_APP` (2116)
to set it — with `R_MANAGE` on the caller's **own** handle, not with the
taskbar right, because a window names itself the way it titles itself.
`WL_APP` in `WM_LIST`; the record grows from 104 to 128 octets, exactly
as round NETVIEW grew it from 96 to 104.

The taskbar does **not** use `appdir` for this. `appdir.load` reads the
whole directory including keywords and holds 16 576 octets of symbol
storage; a process has 832 KiB for everything and the taskbar runs as
long as the machine does. It keeps six slots keyed by name and reads
each file exactly **once** — the *no* is cached too, or every repaint
would reopen the same missing file.

Order inside a button: **symbol, mark, label.** The two pictures answer
different questions — the symbol says *which program*, the NETVIEW mark
says *which view of the network* — and both sit flush left, always in
the same place. A picture that moves with the length of the title has to
be searched for, and then it is no longer help.

**Fallback to plain text** when there is no symbol, the same rule the
network and the battery use. A program that never calls `WM_APP` changes
not one octet.

### Measured, off the taskbar screenshot (background 255,255,255)

| field | look | paint |
|---|---|---|
| Start button, x = 7..23 | 29 px | **172 px** |
| Terminal button, x = 75..91 | 6 px | **185 px** |

and out of the symbol itself, as the bar reports it:

```
taskbar: sym btn=0 app=terminal w=16 ink=196
taskbar: sym btn=1 app=launcher w=16 ink=196
```

The Start button's label moves from x = 18 to x = 27 as a result.

---

## 8. MOTION — checked, not built

`grep -rniE '\banimat|\beasing\b|\btween\b|\bvsync\b' --include=*.fi kernel/`
finds **0**. There is no motion in this system, and this round did not
add any. What a later round would need:

### 8.1 There is no frame clock, and that is the first thing missing

Repainting today is **demand-driven**. `wm.compose` runs when something
asks it to: out of a system call (`WM_SIZE` composes before returning),
and out of the boot loop in `kmain.fi`, which is literally

```
while runden < 500 {
    wm.poll(state)
    wm.compose(state)
    sched.sleep_ticks(state, 1)
    runden = runden + 1
}
```

— a fixed number of rounds at `time.TICK_HZ` = 100, and then it ends.
After boot nothing composes on a clock. A motion round needs a
**permanent** compositor round at a known rate; 60 Hz is not reachable
from a 100 Hz tick without either raising `TICK_HZ` or driving the
compositor off the APIC timer directly.

### 8.2 A time source that is cheap enough to read per frame

There is one: `arch.cycles()` (`rdtsc`) with `apic.tsc_hz` for the
conversion, both already used by `paintbench`. Motion must be a function
of **elapsed time**, not of frame number — otherwise every animation
runs at a different speed depending on load, and the acceptance runs of
this repository are exactly the environment where load varies.

### 8.3 Damage tracking during a movement — the expensive part

Today's damage rectangle is the union of what changed since the last
compose. During a movement *something changes every frame*, and the
union of a window's start and end position is close to the whole
screen. Two consequences, both measurable in advance from section 2.3:

* a full-screen blended repaint costs about **3 million cycles**
  natively (800×600), so at 60 Hz that is roughly 180 million cycles per
  second — about 6 % of one 3 GHz core for a *single* full-screen
  animation, and considerably more in QEMU, where the acceptance runs
  live;
* a window shadow is redrawn every frame of a move: ≈ 17 000 blended
  pixels ≈ 105 000 cycles per frame, 6.3 million per second at 60 Hz.
  Cheap next to the full-screen repaint, but it is not free, and it is
  the reason the damage rectangle in section 6 had to grow.

The honest way to make it affordable is the one every compositor uses:
**per-frame damage, not per-move damage** — the union of the window
rectangle at frame *n* and at frame *n−1*, not at the start and end of
the gesture.

### 8.4 What it would be worth

Windows 11's window animations are 150–250 ms. At 60 Hz that is nine to
fifteen frames. Anything that only fades *opacity* (menus, the quick
settings panel) already has everything it needs after this round —
`fb.fill_a` with a rising `a` is exactly that, and it costs the numbers
in section 2.3. Anything that *moves* needs 8.1 and 8.3 first.

One page, as asked. No code.

---

## 9. WHAT ELSE THIS ROUND FOUND

* **`tools/look/shot.sh` had its build directory as a literal**,
  `/root/lookrun/build`. Two worktrees of this repository — the one
  under test and the one it is measured against — shared one kernel and
  one set of programs. It was found by the measurement itself: a
  screenshot that was supposed to come from the *old* branch showed the
  *new* branch's window shadow, and the two pictures differed in 0 of
  3720 pixels in the band where the shadow lives. A baseline that is the
  thing it is compared against is worse than no baseline. Now keyed on
  the absolute path of the tree, outside the repository.
* **`tools/desktop/run.sh` asserted `WM_MAXNR = 2113`** and had been red
  since round MERGE handed out 2114. A red assertion everybody has
  learned to step over is worse than no assertion; it now names 2112 to
  2116 individually.

---

## 10. THE ACCEPTANCE

`./test.sh` before and after, full runs on the same machine, compared
section by section with `tools/look/compare.py` (which round LOOK wrote
for exactly this).

```
baseline (e0a9fec)   31 sections passed, 5 FAILED, 3188 assertions
after    (04fcd5b)   31 sections passed, 6 FAILED, 3197 assertions
```

Five sections were red **before** this round started and are red after
it: `k14`, `k16`, `icons`, `netview`, `tunnel/pakete`. This round adds
one green section (`paint`, 36 of 36). The extra red one in the "after"
column is `theme` — and it is a flake; see below.

`compare.py` reports two sections as newly red:

```
25  ... NETVIEW 147/23 ...   |  ... NETVIEW 145/24 ...   <== NEWLY RED
27  THEME   91/0             |  THEME   90/4             <== NEWLY RED
```

Both were re-run in isolation, on **both** branches, on the same
machine. Both are timing flakes of the full run, not damage:

| section | baseline, isolated | paint, isolated | verdict |
|---|---|---|---|
| `netview` | 147 passed / 23 failed | **148 passed / 22 failed** | one *better* than the baseline |
| `theme` | 91 / 0 | **91 / 0** | identical |

The `netview` failure lists were diffed line by line (numbers masked):
the `paint` list is the baseline list **minus one entry**
(`9d: the running filtered window kept its view`). Not a single failure
in it is new.

`theme` fails in the full run at exactly the place its own source
comment warns about. `tests/theme/run.sh` reads `G_AVG` off the serial
line, on which five processes write at once since rounds DESKTOP and
TASKBAR; the script already takes the last *fully formed* line. Under
the load of a complete `./test.sh` no fully formed line arrived at all,
so `gsw`/`gdet`/`gpnt` came up empty and four assertions fell over. The
same test alone: `THEME: 91 bestanden, 0 durchgefallen`. The same test
in the earlier full run of this branch (`AFTER3`): `91 / 0`. The
flakiness is real and pre-existing; this round did not cause it and did
not fix it. It is written down here rather than hidden, and it is the
one thing a later round should fix — the measurement lines of
`themetest` need a channel that is not shared.

### The one thing that really went red, and what it taught

An earlier full run of this branch found a genuine regression:

```
FAIL  dark:  button 1, mark-filtered: falsch 54 von 54
FAIL  light: button 1, mark-filtered: falsch 54 von 54
```

Every one of the 54 ink pixels of the network mark was in the wrong
place — because the program symbol of section 7 now sits in front of it.
That was not the bug. **The bug was a duplicated number:** the taskbar
*drew* the mark at `x + 3` and *reported* it as `kx[i] + 3` — two copies
of one calculation in two places, and the runner looks for the mark
where the report claims it is.

Fixed by deleting the copy: the position is computed in exactly one
place — the one that paints — and the report reads it back. The
isolated re-run above (148 / 22) is the proof.

**No test was weakened.** Two assertions were brought back into contact
with reality instead of being switched off:

* `tools/desktop/run.sh` asserted `WM_MAXNR = 2113` and had been red
  since round MERGE handed out 2114. It now names 2112..2116
  individually — so the next round that adds a call has to touch that
  line.
* `tools/paint/aacheck.py` compares against FreeType with a wide bound
  (< 45) *and says why*: that comparison contains hinting. The tight
  bound (< 5) is on the thing the round actually controls, the sampling.
  A bound nobody can justify is a number that gets raised at the next
  failure.

---

## 11. THE FILES

| file | what it is |
|---|---|
| `tools/paint/blendcheck.py` | src-over against the exact value, all 16 777 216 triples, and the five source locations against each other |
| `tools/paint/native.c` | the same arithmetic on the host, without QEMU |
| `tools/paint/aacheck.py` | coverage levels per glyph and per edge; 4×4 against 32×32 |
| `tools/paint/scalars.py` | two rounds on one address, mechanically |
| `tools/paint/shadow.py` | shadow ramp, corner steps and symbol ink, read out of a screenshot |
| `tools/paint/run.sh` | section 26 of the acceptance |

---

## 12. THE PICTURES

`docs/shots/paint/`, all four 800×600, `scheme=day mode=light`, same
disk image, same programs:

| file | what it is |
|---|---|
| `1-vorher-modern.png` | branch `look`, `shape=modern`. The search dialog fills the whole screen — that is the address collision of section 3, not a design. Square frame, no shadow, text-only taskbar buttons. |
| `2-nur-adressen-umgelegt.png` | `look` plus **only** the thirteen relocated constants. The dialog is back at 190,110 440×300. Still square, still no shadow, still text-only. 387 093 of 480 000 pixels differ from picture 1. |
| `3-nachher-modern.png` | branch `paint`. Rounded frame (18 blended corner pixels), six-pixel shadow, program symbols in the buttons (172 and 185 ink pixels). |
| `4-nachher-classic.png` | branch `paint`, `shape=classic`. Square corner (0 blended corner pixels), no shadow — the promise that the old appearance is untouched. |

Picture 2 exists so that the two changes are not confused with each
other. Most of what "looks different" between 1 and 3 is picture 2.
