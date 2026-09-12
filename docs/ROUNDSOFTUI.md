# Round SOFTUI — soft, modern, and paid for in microseconds

Justin looked at what round LOOK produced and named six things, in
order, and then added a seventh in capitals because two rounds had got
it wrong before: **the window buttons are Windows buttons, not macOS
ones.** No three coloured circles. A stroke, a square, a cross, top
right, with a grey hover field and a red close button.

He also ruled out the obvious way to make an interface look soft.
Frosted glass is off the table, and it is off the table for a reason
that was *measured* in an earlier round: a full-screen blur costs 296 ms
per frame on one core at full resolution and 31 ms even at quarter
scale, and it would need a backdrop readback the compositor cannot do.
So this round makes the interface soft **without reading the backdrop
anywhere**, and says so where it would have been convenient to cheat.

**Every number below came out of a run.** Where a number is missing it
says so. Where this round's own reasoning was overturned by its own
measurement, that is in sections 2 and 5, and both times the first
version was mine.

---

## 0. THE RULE OF THIS ROUND

> **A claim about the screen is a claim about pixels, a new capability
> is worth its price in cycles, and `classic` has to come out of the
> other end unchanged.**

That is round LOOK's rule plus round PAINT's, plus the one condition
that lets a round like this be landed at all. The third part is not a
formality: this round touched the compositor, the widget library, the
taskbar and the settings program. Section 1 is the proof.

### The honest limits, before the achievements

* **In a dark scheme the window shadow is nearly invisible, and it is
  measured rather than hidden.** On `night`/`dark` the desktop is
  `#020617` and the deepest shadow pixel is six levels away from it
  (against 58 in `day`/`light`). The focus difference is still a factor
  of two — six against three — but anyone who says "you can see which
  window is focused by its shadow" is saying something about the light
  scheme. Section 5.
* **The gradient is six brightness steps and on a white title bar it is
  six steps of grey, not of colour.** It is deliberately at the edge of
  perception; if you cannot see it in the screenshot, that is the
  intended result and section 4 gives the numbers to check it with.
* **The taskbar pill is drawn at the bottom edge of a tile even when the
  bar is on the left or the right.** It reads correctly there but it is
  not what a vertical bar wants; nobody measured a vertical bar for this
  round.
* **`wlib.card` has no notion of "inside".** A card is painted before
  the controls that sit on it and the two are held together by their
  coordinates, not by a parent-child relation. That is enough for the
  settings page and it is not a layout container.
* **The three caption buttons have no keyboard route.** They are mouse
  targets.

---

## 1. `classic` IS UNCHANGED, AND HERE IS THE PICTURE THAT SAYS SO

The comparison is against `d4c2742` — this branch's parent, after the
three merges (`paint`, `look`, `themestore`) and before the first line
of round SOFTUI. Not against `mergeline`: `mergeline` has neither
`paint` nor `themestore`, and the difference would then be their work
and not mine.

```
gleich: unterschiedlich 0 von 480000 Bildpunkten -- IDENTISCH
gleich: ausgenommen (die Uhr) 740,572 bis 800,600
gleich: ausgenommen (angegeben) 26,62 bis 586,442
```

Two rectangles are excluded and both are named in the report:

1. **The clock in the taskbar.** It shows the real time.
2. **The client area of the terminal window.** The kernel mirrors its
   own serial log onto the screen (`fb: console mirrored to screen`),
   and that log contains the size of the kernel, frame addresses and the
   numbers from `fbbench`. The kernel got bigger this round, so those
   lines legitimately differ — and under `-accel kvm` the `fbbench`
   numbers are fourteen times smaller than under TCG, which is a fact
   about the accelerator and not about the interface.

Everything else — desktop, taskbar, window frames, title bars, launcher,
search window — is compared without mercy and comes out identical.

The mechanism that makes this possible is not discipline, it is the
token default: every one of the nine new tokens defaults to the value
the code already contained, and `classic.shape` writes those same values
down explicitly. `radius_panel = 0` and a loud divider mean `wlib.card`
paints *nothing at all* — not a surface-coloured rectangle over a
surface-coloured window, nothing.

---

## 2. THE SHADOW: WHAT WAS EXPENSIVE WAS NOT WHAT I THOUGHT

### 2.1 What round PAINT left

`paint_shadow` drew `reach` nested outlines, each one pixel further out
and each weaker than the last. Every ring re-sampled its four corners:
for each of the `(r+k)²` points of a corner square, **two** calls to
`corner_cov`, each up to sixteen sub-samples. At `r=10, reach=7` that is
`4 · Σ(10+k)² = 4 · 1610` corner points × 2 samplings — **every frame**,
although nothing about the corner changes between two frames.

> A shadow is a function of the FORM, not of the time.

### 2.2 The nine-slice mask

The shadow is point-symmetric in its four corners and constant per
distance along its four straight runs. So it falls apart into exactly
two tables, computed **once** when the form tokens change:

* one **corner square** of side `S = r + reach` holding coverage,
  mirrored into all four corners by reading it forwards or backwards,
* one **strip** of `reach` coverage values for top, bottom, left and
  right.

`shbuild` counts the builds. It reads **1** for a whole run.

The mask holds **coverage, not colour**. What is underneath is added
when the pixel is mixed — `fb.pixel_a` reads the one pixel it is about
to write and never an area. That is the difference from a backdrop
readback, and it is why this is allowed under this round's terms.

### 2.3 AND THEN THE FIRST VERSION MEASURED ALMOST NOTHING

The first mask walked the corner table pixel by pixel through
`fb.pixel_a`. Measured, in one run, on the same machine:

| | full compose | shadow costs |
|---|---|---|
| no shadow at all | 946 µs | — |
| rings (round PAINT) | 2210 µs | **1264 µs** |
| mask, per pixel | 2089 µs | **1143 µs** |

Eleven per cent, where a factor of four was expected. The sampling was
gone; the **bookkeeping** was not. `fb.pixel_a` fetches width, height
and draw target out of the state block, bumps two counters and marks the
row dirty: six state accesses for three arithmetic steps. Round PAINT
had already written this down for `hline_a` — *"the bounds are checked
ONCE instead of per point"* — there was simply no case with a varying
coverage yet.

### 2.4 `fb.hline_mask`, and the row-oriented shadow

So: not "which pixel of the table goes where", but "which **runs** does
this scanline have". `fb.hline_mask` mixes a run with one coverage
octet per pixel, checks its bounds once, and walks the table with a step
of `+1` or `-1` — which is how one table serves all four corners.

Final measurement, all three in **one run**, same machine, same timer,
same picture, `-accel kvm`:

```
wmbench2: ohne    full=946 us
wmbench2: maske   full=1676 us  shadowpx=19928  aapx=64
wmbench2: ringe   full=2210 us  shadowpx=19276  aapx=594
```

| | shadow costs | mixed pixels | corner samplings |
|---|---|---|---|
| rings | **1264 µs** | 19 276 | 594 |
| mask | **730 µs** | 19 928 | 64 |

**Factor 1.73 in time — while mixing 652 pixels MORE.** The mask has no
gaps: the rings lie on whole pixels, their arcs overlap on the diagonals
and leave holes on the axes, whereas the mask reads the true distance to
the window edge in sixteenths of a pixel. At whole distances it produces
the identical octet the old ring produced — the ramp is the same formula
— and something better in between.

The 64 remaining corner samplings are the window's **own** rounded
corner. The shadow's contribution to `aapx` is zero: it is out of the
per-frame path entirely, which is the actual result of this section.

Per window: **365 µs against 632 µs.** Two decorated windows are on the
screen.

The old path is still there, reachable through `wm.set_shadow_old`, and
that is the only reason it may stay: a before/after from two runs is two
machines.

---

## 3. THE THREE CAPTION BUTTONS

Windows, not macOS, and the check is a picture and not a line in a log.
`tools/softui/knoepfe.py` computes where the fields are — the same
arithmetic as `wm.cap_x0` — and reads out the 10 × 10 glyph box of each:

```
fenster 'Suchen' bei 190,110  knoepfe ab x=542 y=112 h=19
min: strich ok  (zeile 5 voll, neun leer)
max: quadrat ok  (rand 36 von 36, inneres 0)
close: kreuz ok  (20 von 20 Diagonalpunkten, 0 Kantenpunkte)
hover: rot ok  flaeche #dc2626 auf 475 von 570 punkten, kreuz hell auf 10 von 10
macos: keine kreise  (1 Farbfamilie(n) mit mehr als 40 Punkten im Balken: [0])
```

The hover state needs a pointer, so `tools/softui/hover.py` drives one
there over the QEMU monitor **without clicking** — a click on the cross
closes the window and then there is nothing left to photograph.

The macOS counter-check went wrong once and the way it went wrong is
worth keeping. Its first version sorted saturated colours into cubes of
32 levels and found five "groups" — all five were the red of the hovered
close button and its antialiasing. A red button is exactly what this
round is supposed to build; the macOS style is **red AND yellow AND
green next to each other**. So it counts colour *families*, six of sixty
degrees, and more than one is the suspicion.

The maximise button draws **two offset squares** when the window is
maximised, because the button then means "restore".

---

## 4. THE GRADIENT, AND WHY IT DARKENS THE TOP

The first rule was "the gradient always runs AWAY from the text
colour", so that it could never lower the contrast. The picture refuted
it: in the light scheme the title bar is `#ffffff`, there is no lighter
than white, and the bar came out **completely flat** — all nineteen rows
`255,255,255`, counted. A rule that does nothing on half the themes is
not a rule.

So the other direction, which is also the better one: **the top row is
the darkest, the bottom row carries the theme colour unchanged.** That
is a soft inner shadow at the top edge — what a rounded edge under light
from above does. Downwards there is always room, and where there is not,
`grad_room` takes only as much as the colour has: no channel may clip,
or the hue slides.

The measured effect on contrast:

| | before | after |
|---|---|---|
| `#0f172a` on `#ffffff` (light) | 17.85 | **17.04** |
| light text on a dark bar (dark) | — | goes **up** |

Neither is anywhere near the smallest pair in the system. Section 6.

The same arithmetic runs in two rings — the compositor shades the title
bar, the taskbar shades itself — so the rule is written down once in
words and twice in code, and the runner reads both bars out of the same
picture.

---

## 5. THE FOCUS, WITHOUT A LOUD COLOUR

`tone=0` takes the accent off the window chrome. The focused title bar
becomes the *raised* surface with ordinary window text on it; the
unfocused one is the plain surface with muted text. What tells them
apart is the shadow — which is why this round had to build a second
shadow (`shadow_off`, `shadow_off_r`) before it could take the colour
away.

Measured out of the picture, `day`/`light`:

```
aktiv   'Suchen'         tiefe=58  weite=7   grund #f1f5f9
inaktiv 'Terminal -- sh' tiefe=23  weite=4   grund #f3f7fa
titel: kein akzent -- 'Suchen'         #f9f9f9, spanne 0
titel: kein akzent -- 'Terminal -- sh' #f2f4f6, spanne 4
```

Factor **2.5 in depth** and **1.75 in reach**, and neither title bar has
a channel spread above 4 — they are greys, not blues.

And the honest half, `night`/`dark`:

```
aktiv   tiefe=6  weite=6   grund #020617
inaktiv tiefe=3  weite=2   grund #070c1e
```

The ratio survives; the absolute depth does not. A shadow on a
near-black desktop has almost nothing to darken. This is a real weakness
of "focus by shadow" in a dark scheme and this round does not fix it —
it measures it and writes it down. The measuring tool had to be fixed
first: its first version averaged the three channels, which divided the
six levels of the dark scheme by three and reported `tiefe=0` for a
shadow that was plainly there. **A measure that divides the difference
it is looking for by three is the wrong measure.**

---

## 6. THE CONTRAST, TWICE

The bar this round had to clear — 5.16 for `day+modern`, 12.36 for
`night+modern` — is the pair `on-accent / accent`: white text on the
accent blue, which up to this round was the title bar of every focused
window.

**In the token model both numbers are unchanged, and they have to be:
this round did not touch a single colour.** `tone` decides which *role*
the chrome reads, not what any role resolves to.

The interesting number is the other one, out of the picture:

| | model, `on-accent/accent` | measured on the title bar |
|---|---|---|
| `day` + `modern` | 5.16 (unchanged) | **16.96** (`#0f172a` on `#f9f9f9`) |
| `night` + `modern` | 12.36 (unchanged) | **15.08** (`#f8fafc` on `#182335`) |

The title text is now more than three times as legible in the light
scheme as it was, and the gradient is inside that measurement — the
`#f9f9f9` is the darkened top row, not the theme colour.

The smallest *text* pair in the whole system is untouched: 4.61 in
`day/light` (`danger` on `surface`) and 5.70 in `night/dark`.

---

## 7. TWO BUGS THAT ONLY THIS ROUND'S TOOLS COULD FIND

### 7.1 A page went back to the pool while ring 3 could still write it

Running QEMU with `-accel kvm` was in the brief. Under TCG the default
CPU is `qemu64` and it has no SMAP; with `-cpu host` it has, round GUARD
switches it on as it should, and the image stopped booting:

```
*** EXCEPTION 14 #PF  err=0x3  cr2=0x78b000
    rip=0x1217fc  rdi=0x78b000
```

`err=0x3` is: the page is present, it was a write, and it came from
ring 0. Those three bits are exactly what SMAP sets when the kernel
writes into a **user** page without opening the window. `0x78b000` is
the stack of the ring-3 excursion and `rip` points into the frame
allocator: `user.run` hands the stack frame back with `mem.frame_free`,
and the allocator threads its free list **into** the frame — into a page
that is still mapped for ring 3.

**This is not only an SMAP problem.** The frame goes back into the
general pool while it stays mapped into ring 3. Whatever comes out of
that pool next — a page table, a window buffer, a file block — then sits
at an address a ring-3 program may write. Without SMAP nobody notices;
with SMAP the machine falls over in the same second. A mode-dependent
bug of exactly the kind round CERTUS found in the window.

The fix is the missing counterpart, `user.unmap_user`: clear the user
bit on the **leaf** before the frame goes back. Reproduced on the merge
base, so it is older than this round. With it, `-accel kvm -cpu host`
boots with `cr4=0x300020 smep=1 smap=1`.

### 7.2 The configuration reader had a maximum file size

Round LOOK raised this buffer from 1536 to 4096 because a documented
shape file was 4459 octets and the reader saw only comment. Round SOFTUI
added nine tokens with their measurements and `modern.shape` became 6981
octets. Same symptom, just as quiet:

```
taskbar: shape file=modern name= id=0 keys=0 ctrl_h=26
```

`keys=0`, the resolver falls back to `classic`, and a round about how
the system looks renders in the old shape while every other line of the
log says `modern`.

Going from 4096 to 8192 buys exactly one more round. So `kv_read` now
takes the file in pieces and carries the unfinished last line into the
next one: **the buffer bounds a line, not a file.**

### 7.3 And `drop_shadow` never drew a shadow

`wlibc.drop_shadow` painted each of its rings as an `rframe` with the
same colour for the border *and* for the interior:

```
rframe(ox, oy, w + 2i, h + 2i, r + i, 1, c, c)
```

`rframe` fills the interior — that is its job and it says so in its own
comment. So the "shadow" was a **solid filled rectangle** in shadow
colour. It never showed because its only caller (the preview tile of
round THEMESTORE) painted a window over it immediately. The card of this
round does not: it is smaller than its shadow, and the picture came out
with the window surface at `(0, 0, 1)` instead of `(248, 250, 252)`.

Second bug in the same line: the mixed colour was computed **once** from
**one** pixel at the left edge and then written everywhere, so a shadow
crossing two backgrounds had the same colour on both — that is, the
wrong one on one of them.

Both fixed: one pixel wide, nothing filled, every pixel mixed against
what lies under *it*.

---

## 8. WHAT THE SIX POINTS BECAME

| Justin's point | where it lives | measured |
|---|---|---|
| 1 rounded corners 10 / 12 / 8 | `modern.shape`, four radius tokens | shape file, 24 keys read |
| 2 soft shadows, precomputed, focus by depth | `wm.shadow_build` / `shadow_mask` | § 2, § 5 |
| 3 subtle gradients in title bar and taskbar | `wm.paint_title`, `taskbar.paint_band` | § 4 |
| 4 more air, content in cards | `spacing_*` tokens, `wlib.card` | § 1 (classic), pictures |
| 5 muted colours, accent only where active | `tone` token, `deco_push` | § 5, § 6 |
| 6 take the frames back | `divider=25`, `tone=0`, `frame3` gone from the bar | pictures |
| + taskbar centred, round tiles, running pill | `taskbar.button_sym`, `taskbar.pill` | picture 3 |
| + **Windows** caption buttons | `wm.paint_caption` | § 3 |

Pictures in `docs/shots/softui/`:

| file | what it shows |
|---|---|
| `1-desktop-zwei-fenster.png` | two overlapping windows, focused and not — the shadow difference |
| `2-einstellungen-karten.png` | the settings page with two cards |
| `3-taskleiste-mittig.png` | the taskbar, centred, round tiles, accent pill under the running window |
| `4a-knoepfe-ruhe.png` | the three caption buttons at rest |
| `4b-knoepfe-hover-rot.png` | the same three with the close button hovered — red field, white cross |
| `5-vollbild-hover.png` | the whole screen the close-up was cut from |

All of them go through `tools/softui/check.py`, which holds the serial
log up against the picture and asks three questions a log cannot answer:
is there ink where a label was reported, does a label reach past the
right edge of its window, and do two different labels overlap. It found
its own first bug immediately — eleven "overlaps" that were each a label
compared with **itself**, because a screen is built several times per
run and every label is reported more than once. A checker that reports
itself is noise.

Result on all four pictures: **0 objections.**

`tools/softui/run.sh`: **25 passed, 0 failed.**

---

## 9. ONE RED SECTION THAT IS NOT THIS ROUND'S

`tools/look/run.sh` section A2a — the word `Übernehmen` in the theme
probe window — fails. It fails on the **parent commit** too, and there
it fails worse:

```
parent d4c2742    10 characters, 526 ink pixels checked, 526 wrong
branch softui     10 characters, 526 ink pixels checked, 518 wrong
```

Measured with the same (corrected) `umlaut.py` on both trees, or it
would not be a comparison. The position is right in both cases — x=158,
y=337, recomputed from `ax`/`ay` — so it is the colour that is being
compared against: the report says `bg=#ffffff` and something else is
under the text. It came in with the `themestore` merge. It is not fixed
here, and it is written down here so that nobody attributes it to this
round and nobody thinks it is done.
