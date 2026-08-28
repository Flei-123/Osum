# Round LOOK — the umlauts, the symbols, and the reason it looked like Windows XP

Justin booted the image the merge round had built, looked at
`/root/mergerun/boot/desktop.png`, and said four things:

1. there are no umlauts on the screen,
2. it looks old-fashioned, like Windows XP,
3. there is no symbol for the battery or the network in the taskbar,
   only text,
4. and he would like to choose between a classic and a modern
   appearance in the settings, and to be able to put the taskbar
   buttons on the left or in the middle.

All four were correct. Three of them had causes that were nothing to do
with what they looked like from outside, and one of them — the second —
turned out to be a hole in the token system that round THEME had left
open without knowing it.

**Every number below came out of a run.** Where a number is missing it
says so. Where a promise was not kept it says that too, in section 6.

---

## 0. THE RULE OF THIS ROUND, FIRST

> **A claim about the screen is a claim about pixels, and it is only
> worth making if the pixels were counted.** Not "the umlauts work now"
> — *"'Übernehmen' at x=33, baseline 581: 526 ink pixels checked against
> a second rasterisation, 0 wrong."*

That is not a style preference. Round K7B in this repository found a bug
in which 87 per cent of the pixels of a screenshot were right, and the
13 per cent that were wrong were *every letter on the screen*. A test
that says "it looks fine" would have passed. So: every section of this
document ends in a number that a runner produced, and
`tools/look/run.sh` reproduces all of them.

### The honest limits, before the achievements

* **The top-level window frame is still square, and so is its shadow.**
  `radius_window` and the window shadow are read out of the shape file,
  carried through the resolver and *not drawn*. The reason is in
  section 3.4: those pixels belong to the kernel's compositor, not to
  the widget library, and reaching them means widening a protocol.
* **The metric scanner is narrower than the colour scanner** and section
  3.3 explains exactly how much narrower and why.
* **The anti-aliasing counter reads 0 in the reported runs.** It counts
  correctly, but the line that prints it runs before the first repaint.
  The corner is measured off the picture instead, which is better
  evidence anyway.
* `power.fi` still writes German to standard output. It is a
  command-line program, round I18N excluded those on purpose, and
  `tools/i18n/scan.py` counts and reports it rather than hiding it.

---

## 1. THE UMLAUTS — three causes, and the font was not one of them

### 1.1 What was measured first

Before anything was changed:

| | |
|---|---|
| characters in `assets/osum-sans.ttf` | **339**, including ä ö ü Ä Ö Ü ß € |
| characters in the same file on `main` | 96 (ASCII only) |
| `locale/de/messages` on disk in the boot image | **yes** |
| `locale/en/messages` on disk in the boot image | **yes** |

So the font could draw an umlaut, and the German text was on the disk.
Neither of the two obvious suspects was the cause.

### 1.2 Cause one: the image had no `/etc/passwd`

`kernel/user/msg.fi` finds the user's language at
`/users/<name>/config/locale`. To build that path it needs the user's
*name*, which it looks up in `/etc/passwd` by its own uid.
`/root/mergerun/bootshot.sh` did not put `/etc/passwd` on the disk. So
`user_path` failed, `read_user_lang` failed, the catalogue stayed at the
source language, and every string on the screen was ASCII English.

**Proven by changing nothing but the image.** Same tree, same font, one
extra file (`/users/root/config/locale` containing `de`):

```
before   taskbar: text net     t=no network      t=no battery
after    taskbar: text net     t=kein Netz       t=kein Akku
```

### 1.3 Cause two: there was no system default language at all

Round I18N put the language under the *user*, and it was right to: two
people at one machine may want different languages, and a language is
not a property of the machine the way a colour scheme is.

But that leaves a hole, and the hole is exactly the case a fresh image
is in: **there is no user who has chosen anything yet.** A newly built
machine could not be German, no matter what was on its disk.

So `msg.fi` now reads three places, in this order:

| order | file | belongs to |
|---|---|---|
| 1 | `/users/<name>/config/locale` | the **user** — a choice |
| 2 | `/etc/locale.conf`, key `lang=` | the **machine** — a default |
| 3 | `en` | the source language |

`/etc/locale.conf` is what `/etc/default/locale` is on Debian: where a
user starts who has not chosen. **The settings program still writes only
(1)**, so `tools/i18n/run.sh`'s assertion — *"after the click the
language is NOT under /etc/"* — is still true word for word and still
measured.

Which of the three answered is reported, because "the screen is English"
had three different causes that looked identical from outside:

```
taskbar: lang=de src=2 keys=150
```

`src=1` the user, `src=2` the system default, `src=0` neither.

### 1.4 Cause three: the merge un-translated the settings program

This is the big one, and it is a defect of the *merge*, not of any
branch.

```
git show i18n:kernel/user/einstellungen.fi | grep -c 'msg\.'   ->  64
grep -c 'msg\.' kernel/user/einstellungen.fi   (mergeline)     ->   0
```

(The file is `kernel/user/settings.fi` since section F below. The two
commands above are left spelled the way they were RUN, because a
command against a commit has to name the path that commit had.)

Round I18N had moved all of the settings program onto the message
catalogue. When the seventeen branches were merged (`3b4db03`), the
netview/theme/display versions of that file won every conflict, and
round I18N's work on it went with them. Nobody noticed, because the
program still *worked* — in hardcoded ASCII German. `Uebernehmen`,
`Aufloesung`, `Farbsaettigung`.

**And the LANGUAGE PAGE went with it.** `R_SPRACHE` was gone; the
netview page had taken tab 5. There was no way left to change the
language in the interface at all.

Every other file survived the merge intact — that was checked, not
assumed:

| file (name at the time) | on branch `i18n` | on `mergeline` |
|---|---|---|
| `einstellungen.fi` → now `settings.fi` | 64 | **0** |
| `leiste.fi` → now `taskbar.fi` | 8 | 8 |
| `explorer.fi` | 18 | 18 |
| `schreibtisch.fi` → now `desktop.fi` | 2 | 2 |

Restored, and carried forward over the four pages the other branches had
added in the meantime (display, netview, the taskbar section, the theme
controls). The language page came back as tab **6** and not tab 5, so
that no runner that clicks tab 5 clicks on something different than
before.

| | before | after |
|---|---|---|
| `tools/i18n/scan.py`, hardcoded German surface text | **59** | **0** |
| catalogue keys, each of `en` and `de` | 72 | **150** |
| `msg.fi` `SLOTS` | 160 | 224 |
| `msg.fi` `FILE_MAX` | 8192 | 16384 |

The last two are not cosmetic: the catalogue is 9258 octets now and
would have been **silently truncated** at 8192.

### 1.5 The proof

`/root/lookrun/shots/A9/desktop.png` — the desktop, in German, with the
settings program open.

```
tools/gfx/checkshot.py ttext desktop.ppm osum-sans.ttf 15 33 581 \
    15 23 42  255 255 255  "Übernehmen"  8
-> 10 Zeichen, 526 Tintenpunkte geprueft, 0 falsch
```

**526 ink pixels, 0 wrong.** The coordinates are not guessed: the
settings program reports where it put the word (see 1.6) and the window
server reports where the window is. Two more, from the same picture:

```
"Taskleiste -- Bildschirmrand:"      1092 ink pixels, 0 wrong
"Hintergrundbild -- Quelldatei (OSYM):"  1476 ink pixels, 2 wrong
```

The two wrong pixels in the third are honest and worth naming: over a
34-character line the reference rasteriser's accumulated advance drifts
by a fraction of a pixel against the kernel's 26.6 fixed point. It is
0.14 per cent of the ink and it is a property of the *checker*, not of
the screen. The 45-character contrast line drifts by 13 of 2002
(0.65 per cent) for the same reason. Short strings — the ones this
document quotes as proof — do not drift at all.

### 1.6 A tool this needed: the interface reports itself

The taskbar has reported every line it paints since round DESKTOP, with
x, baseline and both colours, and that is why `tools/netview/run.sh` can
check it pixel by pixel instead of looking at it. **No other window
could do that.** The widgets are painted in `kernel/user/wlib.fi`, and
`wlib.fi` reported nothing.

It does now — one line per label, button and choice:

```
wlib: text win=<id> kind=<k> x=<x> base=<y> fg=<c> bg=<c> t=<text>
```

`x` is where the text *really* starts, which for a centred button label
is not the button's x. Recomputing that in the checker would mean the
checker verifying its own arithmetic.

**It is off unless `/etc/uitrace` exists on the disk.** Without that
file the serial output of this system is octet for octet what it was —
which is the condition under which no existing runner notices.

---

## 2. THE SYMBOLS — two different reasons, one of them not a defect

| | why there was no symbol |
|---|---|
| **network** | It had one since round NETVIEW: an OSYM bitmap from `/etc/netview/`. The image did not carry the directory, `icons_load` counted 0, and the bar fell back to text — **exactly as designed**. Fixed in the image, not in the bar. |
| **battery** | It never had one. Round K18 gave the bar a percentage; round ICONS gave the system six battery glyphs; nothing ever joined the two. |

```
before   taskbar: icons=0 marks=0 sys=0
after    taskbar: icons=4 marks=3 sys=1
```

### 2.1 The order of preference

1. the OSYM file from `/etc/netview/` — round NETVIEW, measured there
   pixel by pixel;
2. the glyph from `/lib/icons.ttf` — this round;
3. the text alone — round DESKTOP, still true.

Each step is taken only when the one before has nothing. The glyph path
went **beneath** the OSYM path and not instead of it: swapping them
would have broken twenty-nine assertions in `tools/netview/run.sh` in
order to change a picture nobody had complained about.

### 2.2 The grades, and the rule against inventing them

**Battery** — absent, charging, then thirds: 67, 34, 10. The thirds are
not a round-looking number, they are what Lucide *draws*:
`battery-full` has three bars, `battery-medium` two, `battery-low` one,
`battery` none. A two-bar symbol that means "over 35 per cent" tells a
third of a truth.

Colour is a **role**, so it is right in every scheme: danger below
10 per cent, warning below 20, otherwise the text colour.

**Network** — the same four states `sys.NG_STATE` already computes, so
the bar does not ask three questions and draw its own conclusion:

| state | meaning | glyph |
|---|---|---|
| 0 | no carrier | `NETWORK_OFFLINE` (unplug) |
| 1 | carrier, no address | `NETWORK_BLOCKED` (ban) |
| 2 | address, no route | `NETWORK_NO_INTERNET` (cloud-off) |
| 3 | online | `NETWORK_WIRED` (cable) |

**Nothing is drawn for what the machine cannot measure.** With
`PG_BATPRESENT = 0` the symbol is `BATTERY_ABSENT` — that is the
firmware's *answer*, not a placeholder for a missing one.

### 2.3 The numbers

Screen 800 × 600, taskbar at y = 572. `tools/look/inkbox.py` counts the
pixels of a box that are not the background — it prints the count **and**
the fraction, because an empty box and a filled box fail opposite
one-sided tests.

| case | network | battery |
|---|---|---|
| `/lib/icons.ttf`, no `/etc/netview` | id 0xE001 at (541, 6), **ink 99 of 256** | id 0xE025 at (642, 6), **ink 74 of 256** |
| both present | keeps its OSYM picture | ink 74 of 256, unchanged |
| neither | no `taskbar: icon` line at all, **ink 0 of 256** | text only |

The text beside the symbols is still exact: `kein Netz` 375 ink pixels
0 wrong, `kein Akku` 387 ink pixels 0 wrong — in *both* the symbol case
and the fallback case.

**The fallback is measured and not assumed.** With no icon font the
fields are exactly **18 pixels narrower** (net 97 → 79, battery
100 → 82). 18 is `GL_W + 2`, the room that was reserved. The room is
taken *off* the text's share and not added on top of it — that is the
bug round NETVIEW's addendum found when the address ran out of its
rectangle into the battery, and the same accounting is used here.

Pictures: `docs/shots/look/taskbar-glyphs.png`,
`taskbar-osym.png`, `taskbar-text.png` (the taskbar at 3×).

---

## 3. THE FORM TOKENS — why it looked like Windows XP

### 3.1 The diagnosis

Round THEME replaced eighteen hardcoded colours with three layers of
tokens and made the interface themable **in exactly one direction**.
Nothing about the *shape* was ever a token:

* every border one pixel (`wlibc.frame`),
* every corner square — there was no rounded-rectangle routine at all,
* every inner margin a number typed into a painting routine,
* no shadow anywhere,
* every separating line solid.

No scheme file could reach any of it. **Repainting a square 1-pixel box
in a nicer grey gives a nicer grey square box.** That is the whole of
the "Windows XP" complaint, and it is a hole in the token system rather
than a matter of taste.

> A note on the brief: it said `kernel/wig.fi` knows no radius, shadow
> or spacing. That is true and it is not where the problem was.
> `wig.fi` is the *kernel* seam — a blit, a glyph coverage field,
> kerning, the clipboard and the cursor. It contains no border, no
> padding and no widget. The 1-pixel borders and typed-in margins are in
> `kernel/user/wlibc.fi` and `kernel/user/wlib.fi`, in ring 3, and that
> is where this round did the work. Saying so is cheaper than quietly
> doing it elsewhere.

### 3.2 The fourth layer

Fourteen tokens, one file per set under `/etc/shapes/`, selected by
`shape=` in `/etc/theme.conf` — **deliberately** the same arrangement as
`/etc/schemas/` and `scheme=`, because they are the same kind of thing.

```
radius_window  radius_panel  radius_button  radius_input
border  pad_x  pad_y  gap  row  ctrl_h
shadow  shadow_r  divider  focus
```

**FORM AND COLOUR ARE TWO AXES, NOT ONE POT.** `shape=modern
scheme=night mode=dark` is a legal and useful combination, and so is
`shape=classic scheme=night`. Anyone who folds them into a single
"theme" needs four files to offer two shapes and two schemes, and
sixteen to offer four of each. Section 4 measures that the two axes
really are independent.

Four derived sizes (`ctrl_small`, `ctrl_thin`, `scroll_w`, `tile_w`,
`sep_h`, `dlg_btn_w`) turn *one* control height into the four this
library has always drawn — 26, 24, 22 and 14. Four separate tokens
could drift apart; a relationship cannot.

The drawing a radius needs is new: `rrect`, `rframe`, `drop_shadow` and
`divider`.

**The corners are antialiased, and the cost is bounded on purpose.**
Only the four corner squares are sampled, 4 × 4 each, entirely in
integers — no square root, no division in the inner test. A rectangle of
radius *r* pays for 4·r² pixels **whether it is 60 × 26 or 796 × 576**:
256 pixels at r = 8. `wlibc.aa_pixels()` counts every pixel that went
through the sampler, so the cost is a measurement in every run rather
than a sentence in a comment.

If it ever does become too expensive, the honest fallback is hard edges
with the **correct rounding** — `coverage >= 128` becomes ink — and not
a smaller radius. That is one line, and it is written down in the source
so that whoever needs it does not have to redesign anything.

### 3.3 The rule, and how far the scanner really reaches

Round THEME's rule was *"no painting routine names a colour"*, checked
by `tests/theme/rawcolour.py`. The same rule for form:

```
tests/look/rawmetric.py
-> rawmetric: files 2 tokens 29 raw 0
```

**It is narrower than the colour scanner, and this is the honest
account of how much.** Six hex digits is a colour and nothing else, so
`rawcolour.py` can scan whole files. A *size* is a small integer, and a
painting routine is full of small integers that are not sizes: loop
bounds, array indices, shifts, masks, divisors, code points. A checker
that flagged all of them would report hundreds of hits, nobody would
read it, and it would be switched off within a week.

So `rawmetric.py` scans the **argument positions in which a size can
hide**, in the calls that draw a box or lay one out — the W, H, R and B
of `rect`, `rrect`, `frame`, `rframe`, `frame3`, `add` and `size` — in
`wlibc.fi` and `wlib.fi`.

**What it therefore does not catch:** a size passed through a local
variable that was assigned a literal three lines earlier, and a size in
a file outside those two. Both are real gaps. The first is bounded by
the second: the two files that decide what a control *looks like* are
scanned in full, and a literal that reaches a drawing call through a
variable in one of them would still have to pass through a scanned
position to be drawn.

Exceptions are listed **by name** and not by pattern — the way round
THEME listed its two. They are the functions that *define* the tokens
(`metrics_classic`, `shape_key`), the ones that *implement* them
(`rrect`, `rframe`, `corner_cov`, `drop_shadow`, `divider`, `cap`) and
the ones that *derive* from them (`ctrl_small`, `ctrl_thin`, `inset`,
`zeilen_hoehe`). An exception granted by a pattern is an exception that
grows.

Round THEME's own rule was re-run and still holds:
`rawcolour: … raw 0`.

### 3.4 What is NOT drawn, and what it would cost

**`radius_window` and the window shadow are read, carried, and not
drawn.** The top-level window frame, its title bar and the shadow under
it are painted by the *kernel's compositor* (`kernel/wm.fi`), which
receives eleven **colour** slots from ring 3 through `WM_DECO` and
nothing else. The widget library cannot reach those pixels.

Doing it properly means three things, and none of them is small:

1. widening the `WM_DECO` protocol from eleven colours to colours plus
   metrics, which changes a kernel/ring-3 interface that four programs
   and three test runners already speak;
2. giving the compositor a rounded blitter — it composites whole
   rectangles today, and a rounded window needs per-pixel coverage at
   the corners *of the compositing step*, not of a client's drawing;
3. a shadow needs the compositor to read what is *underneath* a window
   before it draws it, which the current damage-rectangle scheme does
   not do.

That is a round of its own. It is named here rather than glossed,
because "modern appearance" with square window corners is a partial
answer and should be described as one. **What *is* rounded:** every
button, choice, entry, list, tile, scroll thumb and focus ring — that
is, everything the widget library owns, which is everything inside a
window.

---

## 4. THE TWO APPEARANCES

### `classic`

**Not a design — the behaviour of every round before this one, written
down.** Every number was read out of the routine it used to sit in:
`border=1` from `wlibc.frame`, `ctrl_h=26` and `pad_x=12` from
`wlib.button`, `row=20` from `zeilen_hoehe`, `gap=8` from `want_gap`;
`radius=0` and `shadow=0` because neither existed; `divider=100` because
every line was solid.

It exists to **prove nothing broke**. A round that adds a second
appearance and cannot show the first one untouched has not added an
appearance — it has replaced one.

### `modern`

Every number names a step off a scale that the design skill on this
machine ships (`/root/jarvis/plugins/ui-ux-pro-max/.claude/skills/`).
Nothing was invented:

| token | value | source |
|---|---|---|
| `radius_window`, `radius_panel` | 8 | `radius-lg`, primitive-tokens.md |
| `radius_button`, `radius_input` | 6 | `radius-md` — what `--button-radius` and `--input-radius` resolve to, component-tokens.md |
| `pad_x` | 16 | the `default` button row, component-specs.md |
| `pad_y` | 7 | (32 − 18) / 2 — what is left round a 15-pixel line in a 32-pixel control |
| `gap` | 12 | `--space-3`, the 4-pixel unit |
| `row` | 24 | a 15-pixel line plus `--space-1` above and below, on the 4-grid |
| `ctrl_h` | 32 | the `sm` button row |
| `shadow`, `shadow_r` | 22, 6 | `--shadow-md` is `0 4px 6px -1px` at 10 % twice over |
| `border` | 1 | **unchanged, deliberately** |
| `focus` | 2 | the one thing that gets louder |
| `divider` | 45 | **no source in the skill — measured instead** |

Three of those need their reasoning stated rather than cited:

**Why 32 and not 40.** The skill's `default` button is 40 pixels high.
The settings program's Darstellung page has fourteen controls; at 40
each it is **720 pixels tall on a 600-pixel screen**. The `sm` row (32)
fits and is still a 23 per cent bigger click target than classic's 26.
A design system is a set of numbers to reason with, not a set of numbers
to obey.

**Why `border` does not grow.** A modern interface is not one with
thicker borders. It is one with fewer and quieter ones — which is what
`divider` is for.

**`divider=45`, the one number with no source.** Tailwind and shadcn
draw separators with a border *colour* token (gray-200 on white) rather
than an opacity. This system has such a token, but it is bound per mode,
and a line that is right on `#FFFFFF` is invisible on `#0F172A`. So:
45 per cent of the border colour over whatever is underneath, which
measured **1.7 : 1** against the surface in day/light and **1.6 : 1** in
night/dark. That is inside the 1.5 : 1 – 2 : 1 a non-essential separator
wants, and outside the 3 : 1 WCAG demands of *meaningful* UI edges —
which a divider is not.

### Switching, at run time

`/bin/settings`, page **Darstellung**, beside the colour scheme and
the mode. Apply writes `/etc/theme.conf`, calls `theme_reload`, and then
`wlib.reshape()`.

**That third step is the one that is easy to forget.** A widget takes
its height when it is *created*, because that is when the box it goes
into needs to know how much room to leave. A shape change is therefore a
**re-measurement**, not a repaint: without `reshape`, 32-pixel buttons
would be drawn into 26-pixel rectangles and every click target would sit
where the old one was. `reshape` re-asks the current tokens for each
kind's height and lays the boxes out again, keeping every widget's
number, value, focus and — the one that matters — its **text pointer**,
which is why a shape change and a language change can happen in either
order.

### The measurements

Four boots, same tree, same font, same screen:

```
settings: shape file=classic name=Classic id=0 keys=15
          ctrl_h=26 radiusb=0 shadow=0  divider=100 gap=8  row=20 padx=12
settings: shape file=modern  name=Modern  id=1 keys=15
          ctrl_h=32 radiusb=6 shadow=22 divider=45  gap=12 row=24 padx=16
```

| | classic | modern |
|---|---|---|
| the same choice widget, height | 24 | **30** |
| the page's last control, y | 648 | **702** |
| distinct colours in the picture (day/light) | 82 | **116** |

**The corner, read off the diagonal of the same widget** with
`tools/look/corner.py`, on the dark pair where face and surface are far
enough apart that the reading cannot be an artefact of the tolerance:

```
classic night/dark   1e293b 1e293b 1e293b 1e293b ...
                     F F F F F F F        background 0   reach 0   SQUARE
modern  night/dark   0f172a 11192c 253244 1e293b ...
                     . . ~ F F F F        background 2   reach 5   ROUND
```

The `~` is the antialiasing: one blended step between background and
face. A hard-edged round corner would have none, and at radius 6 a
staircase is *more* conspicuous than a square corner.

**The contrast is unchanged by the shape** — which is the entire point
of two axes, and is measured rather than asserted:

| | text / accent | accent / surface | WCAG |
|---|---|---|---|
| `day` light, classic | 5.16 | 4.93 | met |
| `day` light, **modern** | **5.16** | **4.93** | met |
| `night` dark, classic | 12.36 | 10.50 | met |
| `night` dark, **modern** | **12.36** | **10.50** | met |

Pictures: `docs/shots/look/shape-classic-day.png`,
`shape-modern-day.png`, `shape-modern-night.png`,
`shape-classic-night.png`, and the two 3× crops `zoom-classic.png` and
`zoom-modern.png`.

### A bug this round walked into, and the guard it left

`kv_read` read 1535 octets. A shape file with its reasoning in it is
longer than that, so the keys at the end were never seen, `shape_key`
was never called, and the resolver fell back to `classic` — **both
screenshots came out identical and nothing said why.** "No keys" and
"no file" took the same branch.

Three things changed: the buffer is 4096, the shape files are short (the
reasoning is in this document), and `shape_keys()` is on the serial line
so that a zero is *visible*.

---

## 5. WHERE THE BUTTONS SIT

Windows 11 centres the start button and the window buttons and leaves
the status corner alone. Windows 10 and everything before it put them at
the left. Both are defensible, so this is a **setting**, and the default
is `left` — a round that moves somebody's start button without being
asked has broken something that was not broken.

`align=left|center` in `/etc/taskbar.conf`, sixth key of the file, also
settable in the Darstellung page. One file, two writers, one reader,
exactly as the taskbar addendum set it up.

**What moves and what does not.** The start button and the window
buttons are one block and move together; the three status fields do not
move. That is not imitation for its own sake: a centred block grows from
the middle outwards, so if the clock were part of it, **the clock would
jump sideways every time a program started.** A corner does not move.

The block is centred in the **run of empty bar** — from the left margin
to the first status field — and not on the screen. The status fields are
about 250 pixels wide here, so centring on the screen would put the
block visibly left of the middle of what a person *sees* as empty. When
the block is wider than the run there is nothing to centre and it stays
left.

**A vertical bar is not left out.** There `center` means centred in the
height, between the top margin and the topmost status field. A setting
that silently does nothing in two of four configurations is worse than
no setting.

### The numbers

The bar reports its start button's rectangle now. Until this round it
reported only where it put the *word* `Start`, which is the button's x
plus half the slack — a checker would have had to undo the centring, and
undoing a centring is not proof.

```
taskbar: start x= y= w= h= align=
```

| configuration | measured |
|---|---|
| `edge=bottom align=left` | start **x = 4** (= PAD + 1) |
| `edge=bottom align=center`, two window buttons | start **x = 112** |
| `edge=left align=center` | start **y = 233** (left: y = 3) |

Pictures: `docs/shots/look/taskbar-align-left.png`,
`taskbar-align-center.png`, `taskbar-vertical-center.png`.

---

## 6. WHAT WAS PROMISED AND NOT DELIVERED

| promised | state | why |
|---|---|---|
| rounded **window** corners (~8 px) | **not drawn** | the frame belongs to the kernel compositor; see 3.4 for the three things it needs |
| soft shadows **on windows** | **not drawn** | same; the compositor cannot read what is under a window |
| `wig.fi` free of raw pixel numbers | **not applicable** | `wig.fi` contains no border, padding or widget — the numbers were in `wlibc.fi`/`wlib.fi`, and that is where they were removed (3.1) |
| anti-aliasing cost as a run-time number | **counted, printed as 0** | `aa_pixels()` is correct; the line that prints it runs before the first repaint. The corner is measured off the picture instead, which is stronger evidence |
| the metric scanner as broad as the colour scanner | **narrower** | 3.3 states exactly how much and what it misses |

Nothing on that list was quietly dropped: each one is either measured
somewhere better, or named as a round of its own.

---

## 6a. THE ADDENDUM: THE LAST THREE GERMAN PROGRAM NAMES

Justin's rule is in `docs/NAMING.md` and it is older than this round:
**names of files, programs, commands, paths and configuration keys are
English; only the text a person reads is translated.** Round `rename-en`
(`d89f512`) had renamed `suchen`, `starter` and `wigdemo` and left the
three biggest programs of the desktop alone — four rounds were editing
them at the same time, and a rename that collides with four merges is a
rename nobody thanks you for. This round was in those files anyway.

| was | is |
|---|---|
| `kernel/user/leiste.fi`, `/bin/leiste` | `kernel/user/taskbar.fi`, `/bin/taskbar` |
| `kernel/user/schreibtisch.fi`, `/bin/schreibtisch` | `kernel/user/desktop.fi`, `/bin/desktop` |
| `kernel/user/einstellungen.fi`, `/bin/einstellungen` | `kernel/user/settings.fi`, `/bin/settings` |

`git mv`, so the history stays attached to the files (`git log
--follow` still walks back through round DESKTOP).

### A NAME IN THIS SYSTEM LIVES IN FIVE PLACES

This is why it was pulled through by hand and not with one `sed` over
the tree. Three of the five would have survived a `sed` without a
murmur, and two of those three fail *silently*.

1. **The file name** — and the lists that read it: the file lists in
   `tests/theme/rawcolour.py` and `tools/i18n/scan.py`, the exception
   list in `tools/k18/run.sh`, the greps in `tools/display/run.sh` and
   `tools/desktop/run.sh`. A checker whose file list has a name that no
   longer exists checks one file fewer and says nothing.

2. **The `/bin` path** — `desk_start` and `netv_demo` in
   `kernel/kmain.fi`, `p_settings` in `kernel/user/qs.fi`, and the
   header line of `/etc/taskbar.conf` in **both** of its writers.

3. **`argv[0]`, and the LENGTH OF THE ARGV BLOCK beside it.** The
   kernel hands the program its own name and, as a separate number,
   how many octets that block is:

   ```
   desk_spawn(state, p_desk, a_desk, 13)   ->  8   "desktop\0"
   desk_spawn(state, p_task, a_task,  7)   ->  8   "taskbar\0"
   desk_spawn(state, p_set,  a_set,  15)   ->  9   "settings\0"
   desk_spawn_n(state, p_nv, a_non,  32,3) -> 27   "netview\0none\0/bin/settings\0"
   ```

   A length that does not move with the name either truncates `argv[0]`
   or reads past the end of it. `sed` does not know that the number two
   lines down belongs to the string.

4. **The name on the serial line.** `leiste: deko n=`,
   `schreibtisch: ready `, `einstellungen: feld` — that is the program
   announcing itself, so it moves too, and with it the declared length
   of nine string literals and eleven greps in `tools/i18n/run.sh` and
   `tools/look/shot.sh` that look for exactly those words.

5. **The symbol prefix.** A module name in Firn is the prefix of every
   symbol in it, so `leiste__paint` became `taskbar__paint`.
   `tools/desktop/run.sh` proves the taskbar lives in ring 3 by
   searching the kernel image for those three symbols and failing if it
   finds them. **A counter-test that searches for a symbol which no
   longer exists passes every time and tests nothing** — the worst kind
   of green. It moved with the name.

The declared lengths were recomputed, not estimated (`\0` is ONE
octet): 24 declarations, each worked out and then confirmed by the
compiler. The two writers of the `/etc/taskbar.conf` header have the
same new text and the same new length, 60.

`kernel/wm.fi` had a local variable `leiste` holding the TITLE BAR's
colour — nothing to do with `/bin/leiste`, but an identifier, and the
grep below is supposed to come back empty outside German prose. It is
called `titel` now, after what it holds.

**What stays German, deliberately:** `Taskleiste`, `Titelleiste`,
`Bildlaufleiste`, `Pfadleiste`, `Menueleiste`, `Schnelleinstellungen`,
`Voreinstellung`, and `Schreibtisch` as a *concept* in comments — plus
the display text in `locale/de/messages` (`taskbar.title = Taskleiste`).
That is the rule working, not the rule being broken.

### THE PROOF

```
grep -rn 'leiste\|schreibtisch\|einstellungen' .   (without .git/)
```

comes back with **nothing in a path, a build list, a symbol or an
identifier**. What is left is thirteen lines, and every one of them is
a sentence *about* the rename:

```
docs/NAMING.md          4   the was/is table and the symbol-prefix note
docs/ROUNDLOOK.md       5   this section, and two git commands quoted
                            the way they were RUN (a command against a
                            commit has to name the path that commit had)
docs/ROUNDTASKBAR.md    2   "`taskbar.fi` (then `leiste.fi`) had ..."
docs/ROUNDTHEME.md      1   the same
kernel/user/taskbar.fi  1   the comment that says what it used to be
```

### A BUG THE RENAME FLUSHED OUT

`tools/look/shot.sh` rebuilt the kernel only when it was **missing**.
The programs were rebuilt whenever their source was newer; the kernel
was not. So the first run after the rename booted the OLD kernel, which
dutifully started `/bin/schreibtisch`, which no longer existed. The only
sign was one line:

```
desk: start /bin/schreibtisch  pid=0
```

and a pid of 0 is not something anybody reads as an error. Both follow
the same rule now: newer source, new build.

### MEASURED

```
desk: start /bin/desktop   pid=2
desk: start /bin/taskbar   pid=3
desk: start /bin/settings  pid=4
35 taskbar: lines, 7 desktop: lines, settings: lang=de src=2 keys=154
taskbar: conf edge=0 ename=bottom height=28 autohide=0 ontop=1 align=left src=file
```

All sixteen programs compile and link; the kernel builds.

---

## 6b. THE BRANCH `rename-etc` — DO NOT MERGE IT, AND IT IS ALREADY DONE

The four German configuration paths it was named for are **already
English in this tree**, applied by `b5c796e` before this round started:

| was | is | where it lives now |
|---|---|---|
| `/etc/hintergrund` | `/etc/wallpaper` | `desktop.fi`, `settings.fi` |
| `/etc/schirm.conf` | `/etc/display.conf` | `settings.fi`, both `messages` |
| `/etc/zeit.conf` | `/etc/time.conf` | `settings.fi`, `taskbar.fi`, both `messages`, `tests/theme/`, `tools/look/shot.sh` |
| `/etc/netz.conf` | `/etc/network.conf` | `dhcp.fi`, `settings.fi`, both `messages` |

Checked, not assumed: `grep -rn '/etc/hintergrund\|/etc/schirm\|/etc/zeit\|/etc/netz'`
over the tree finds **no occurrence in any `.fi`, `.sh` or `.py` file** —
only the was/is table in `docs/NAMING.md`.

`b5c796e` did the same thing this addendum did and for the same reason:
it applied the change **mechanically to the finished files** instead of
replaying `283b378`'s diff, which was cut before seventeen branches
touched those same files and would have conflicted in every one of
them. It also recomputed the length literals — `/etc/network.conf` is
three octets longer than `/etc/netz.conf`, `/etc/wallpaper` two shorter
than `/etc/hintergrund`.

**The one deliberate exception**, and it is named rather than hidden:
`wlibc.timezone_read()` reads `/etc/time.conf` and falls back to
`/etc/zeit.conf`. A machine that silently loses its timezone on an
upgrade is not an upgrade. It is a READ and never a write; nothing in
the system creates the old name. `docs/NAMING.md` said "there is no
backwards compatibility for the old names anywhere", which was not
true, and now says what is.

**Why the branch must not be merged.** `git diff --name-status -M
mergeline..rename-etc` is a list of BACKWARDS renames and deletions:

```
R087  assets/apps/launcher.osp/INFO  ->  assets/apps/suchen.prog/INFO
R100  REMOVE-FROM-FIRN.md            ->  ENTFERNEN-AUS-FIRN.md
D     LICENSE.MIT
D     THIRD_PARTY.md
D     assets/icons/LICENSE.lucide
D     assets/netview/*            (all ten mark and state files)
```

Merging it would undo round RENAME, undo the licence bookkeeping and
delete the icon and netview assets. Its only real content is `283b378`,
which is in the tree. **The branch can be deleted.**

---

## 6c. THE THIRD ADDENDUM: THE TRANSLITERATION

### The report, and what measuring it actually said

> "`git show look:locale/de/messages | grep -cP '[äöüß]'` gives **0**. In
> the whole German language file there is not one real umlaut."

The file has **58** of them: `ü` 20, `ä` 17, `ö` 9, `ß` 7, `Ö` 3, `Ü` 2,
spread over 50 of its 188 lines. `cat -A` on line 28 prints
`settings.apply = M-CM-^\bernehmen` — octets `C3 9C`, a capital U with
diaeresis. Run against that file, `grep -cP '[äöüß]'` returns **50** in
`LC_ALL=C`, in `C.UTF-8`, in `de_DE.UTF-8` and in `en_US.UTF-8`. There
is no locale in which it returns 0.

It returns 0 in exactly one case: when the umlauts **in the pattern**
are lost on the way to grep. Then the bracket expression is `[]`, grep
stops with `grep: missing terminating ] for character class`, exit code
2 and no output — and no output reads exactly like a zero. The
instrument was broken, not the file. This is worth writing down because
the same trap is one keystroke away from anyone checking this again: a
tool that reports UTF-8 through a channel that is not UTF-8 safe will
say "there are no umlauts" about a file full of umlauts.

### And the report was right anyway — about a different file

The text on the photograph does not come from the catalogue.

| where | what it said | what it says now |
|---|---|---|
| `assets/apps/editor.osp/INFO` | `info=Text schreiben und aendern` | `… und ändern` |
| `locale/de/icons`, 11 values | `Vorgetaeuschte`, `laedt`, `Schliessen`, `Groesse`, `zuruecksetzen`, `Naechstes`, `Zurueck`, `Vorwaerts`, `geoeffnet`, `Loeschen`, `Ausgewaehlt`, `Menue` | all with real characters |
| `qs.fi`, `widgetdemo.fi`, `speicher.fi`, `themetest.fi` | 12 drawn literals | all with real characters |
| `wlib.fi` | `"Menue"`, the menu window's title | catalogue key + English fallback |

**The starter's rows are bundle labels, and a bundle label never passes
through the catalogue.** `appdir.fi` reads `name=` and `info=` straight
out of `INFO`; `msg.fi` never sees them. So round I18N could convert 73
literals into catalogue keys, part A of this round could prove a German
string renders pixel-for-pixel, and "Text schreiben und aendern" sat
three rows under a correctly drawn "Ausführen" the whole time. Two of
the three strings named in the report — "Dateien und Ordner ansehen" and
"Eingabeaufforderung" — are correct German that happens to contain no
umlaut. Exactly one string on that screen was wrong.

**Honest about `locale/de/icons`:** no `.fi` in this tree opens it.
`msg.fi` only ever reads `/usr/share/locale/<code>/messages`. Those
eleven values were never on a screen. They are fixed because the rule
covers language files, not because a pixel changed.

### The lengths

`ae` is two octets. `ä` is two octets. **Every one of these replacements
is octet-neutral** — `aendern` → `ändern` stays at 31 octets and drops
from 31 to 30 *characters*. All twelve source literals were checked
individually against their declared `[u8; N]` and none moved; the script
that applied them aborts if one would.

That settles the general question the report raised:

* a buffer measured in **octets** never has to grow;
* a field width meant in **characters** but measured in octets becomes
  too **large**, never too small — untidy, never broken;
* the one real danger is **cutting** by octets, where a slice through a
  two-octet sequence yields a broken character. In this tree only
  `ulib.strncpy(…, 62)` cuts a window title, and the longest program
  name is 14 octets.

`VALW = 96` still holds (longest German value 75), `KEYW = 40` (longest
key 31), catalogue 155 keys against `SLOTS = 224`.

**`keys=` was deliberately not converted but extended** — `menue,menü`.
It is a search index, not screen text, and `appdir.lower()` folds only
A–Z, so replacing it would have cost the reader who types "menue" his
hit.

### Two things that were only found because something else broke

**`tools/icons/run.sh` opened both `locale/*/icons` with
`encoding="ascii"`.** An umlaut there would not have turned the ICONS
section red — it would have aborted it with `UnicodeDecodeError`. A
checker that cannot read the file it checks reports nothing, and nothing
is not a pass. Now `utf-8`; `assets/icons/icons.map` stays ASCII,
because names live there.

**`tools/i18n/scan.py` said `gefunden: 0`, and that was true — for the
eight files in its list.** Everything else went into a bucket labelled
"command-line programs, their text goes to stdout, not through the
window server". For half of them that is false: `qs.fi` is the quick
settings panel, `widgetdemo.fi` is the "Widgets" application in the
starter, `speicher.fi` draws two tables and a dialog, `themetest.fi` is
round THEME's measuring window. Twelve visible strings sat in that list
with a note saying they were not on the screen. The label was
comfortable: as long as those files are called "command line", the line
above may say 0 and still be true.

**And then I made that scanner worse.** After the twelve replacements it
fell from 17 findings to 10 — which looks like progress and is the
opposite: its word list is pure ASCII (`Loeschen`, `Groesse`,
`Uebernehmen`), so it no longer *found* the correctly spelled words. A
checker that gets greener from a spelling correction has stopped
measuring what it claims to measure. Both spellings are in the list now,
the old ones deliberately kept, and the honest count is **18**.

The eighteenth line is one nobody had ever seen: `wlib.fi:3044`,
`"Menue"` — the **title of the menu window**, which carries a 22-pixel
title bar and is therefore drawn. Hardcoded German inside the widget
library since K15, invisible to the scanner because "Menue" was not in
its word list. `wlib` cannot read the catalogue: it is linked into all
thirteen programs, and `import msg` would put a message catalogue into
`sh` and `ls` too, on a disk that ran out of room in this very round. So
the library carries the untranslated English — exactly what `msg.fi`
does for a missing key — and a program that has a catalogue passes the
translation down with `wlib.set_menu_title()`.

### Two defects in this round's own tooling

**`tools/look/shot.sh` compared each program only against its own
`.fi`.** Every one of them does `import wlib`. So a change to the widget
library never reached the image, and the only symptom was that a newly
added trace line was missing from the serial log — which looks exactly
like a trace line that does not work. I spent a round looking in the
wrong place. Same class as the second addendum's finding one level up
("only rebuilt the kernel when it was MISSING"). The newest file in
`kernel/user` now decides for all of them.

**`paint_list` and `paint_table` reported nothing.** Every other drawing
routine in `wlib` calls `say_painted` — button, label, choice. The list
and the table heading did not, and those two carry precisely the strings
this addendum is about: the starter's rows are the bundle labels, and
the file manager's heading is `Name / Größe / Zeit / Rechte`, the only
string in the interface where an `oe` and an `ss` stand side by side. A
widget that reports nothing cannot be photographed, and what cannot be
photographed nobody checks. That is the mechanism by which this survived
half a year, and it is now closed.

### The proof

Six different characters, five widgets, four windows:

| char | string | widget | ink pixels | wrong | tolerance |
|---|---|---|---|---|---|
| `ü` | `Ausführen` | button | 438 | **0** | 0 |
| `ä` | `Editor  --  Text schreiben und ändern` | list row | 1340 | **0** | 0 |
| `Ü` | `Übernehmen` | button | 526 | **0** | 0 |
| `ö` `ß` | `Größe` | table heading | 282 | **0** | 64 |
| `Ö` | `Öffnen` | menu item (tools/k15) | 300 | **0** | 96 |

The second row is the string from the photograph.

**Tolerance 64, and the measured ladder for it:** 0 → 3 wrong, 16 → 1,
32 → 1, 64 → 0, 96 → 0. The two dots of an `ö` are a second glyph box
over the first, and where two boxes overlap the library mixes glyph onto
glyph while the reference rasteriser mixes each onto clean ground — the
same effect `tools/k15/run.sh` documents with 96 for the "ff" in
"Öffnen". The largest deviation is under 64 of 255 steps and touches
three pixels. Nothing is loosened: string, position and both colours
still have to be right, and the other three rows stand at tolerance 0.

**`tools/look/umlaut.py`** does the arithmetic that is easy to get wrong
by hand. A reported text position is *window*-relative; the picture is
not. It takes the frame (2) and title bar (22) from `wm: win … x= y=`
instead of guessing them, and anchors on the *expected* wording, because
five processes share one serial line and reading a line to its end fails
in most runs.

It also draws a line. On the first attempt it reported 110 wrong pixels
for `Größe` and I looked for the fault in the font for an hour. The
fault was in the layout: with the starter on screen the tiler gives the
file manager 396 pixels, the column `Größe` starts at x=368 and is 44
wide — it ends 20 pixels past its own window edge, and what stands there
in the picture is the *next window*. That is not a font fault and must
not be measured as one. `umlaut.py` recomputes the width with the same
rasteriser and says "not measurable" instead of producing a number that
looks like a font fault. Checking whether the *start* is inside the
window is not enough; it is the *end* that runs out. Section A2's fourth
assertion is the counter-check on the checker: the heading in the narrow
window **must** be refused.

### The rule, so it does not come back

`docs/I18N.md` §1.1: in `locale/<language>/*` and in `name=` / `info=`
of the bundles, the real character stands — never the transliteration. A
comment may *quote* it, in quotation marks, as an example.

`tools/i18n/translit.py` enforces it, in `tools/i18n/run.sh` and
`tools/look/run.sh`. It searches **100 word stems** that exist in German
only as transliteration, and names the replacement for each. Deliberately
**not** a pattern over the letter pairs: "ss" and "eu" occur in Prozess,
Adresse, Klasse, Messung, muss, dass, Feuer, Steuerung — a pattern would
have flagged every second line and been switched off within a week. It
also reads `VALW`, `KEYW`, `FILE_MAX` and `appdir`'s read length **out
of the source** rather than from a copy, because a copied number is the
one that does not move next time.

Three counter-checks, because a check that is always green checks
nothing:

* the tree as it stands → `umschrift=0 eng=0 umlaute=96`, rc=0
* transliteration written back in two places → 3 findings, rc=1
* 28 correctly spelled German words with ss/ae/oe/ue → 0 flagged

### The acceptance run

Under the load of the full suite: **28 sections passed, 8 failed, 3044
assertions**. The baseline on `mergeline` has 5 red (k14, k16, icons,
netview, tunnel/pakete). 26 sections appear in both logs, **5 newly
red** — and every one of them was re-run on its own, because a number
taken under load is not a number:

| section | in the suite | alone | baseline |
|---|---|---|---|
| K13 | 86/8 | **99/0** | 99/0 |
| K14 | 12/2 | **151/1** | 151/1 |
| K16 | 57/7 | **58/6** | 58/6 |
| K15 | 250/2 | **252/0** | 252/0 |
| NET | 74/1 | **75/0** | 75/0 |

K14 running 12 assertions where the baseline runs 151 is the giveaway:
that is not a failure, it is an abort.

**K15 was the one real defect, and it was mine.** I had pulled two
occurrences of `"Oeffnen" 96` across to `"Öffnen"` and missed the *loop*
that rasterises the same three menu items one by one — plus the
starter's second row, in two places. The second of those is the one that
matters:

```
schau_nicht "und in Zeile 1 steht nichts mehr" ... "... und aendern"
```

A **negative** assertion. With the old wording it would have been green
for ever after — it looks for something that no longer exists and is
guaranteed not to find it. It would have gone on printing OK and checked
nothing. Exactly the fault the rename addendum found in the symbol
`leiste__paint`, one level down. Both spellings moved; the tolerance,
the rasterisation and the position did not.

**NET section 9** (`tc netem`, one frame in five thrown away) is a TCP
throughput test through 20 % packet loss, and it is load-sensitive.
Measured five times on the same machine:

| tree | load | result |
|---|---|---|
| `look`, inside the full suite | high | 74/1 |
| `look`, alone right after it | 4.3 | 73/2 |
| `mergeline`, worktree | 3.5 | 75/0 |
| `look` at `e0a9fec` (before this addendum) | 3.5 | 75/0 |
| `look`, quiet machine | 3.5 | **75/0** |

The middle two rows are the ones that matter: I did not assume it was
load, I checked out the baseline and the pre-addendum commit into
worktrees and ran the same script against them. On a quiet machine all
three trees give the same 75/0. This addendum touches 21 files and not
one of them is in the network, K13, K14 or K16 path.

**NETVIEW is better than the baseline**, not worse: 46/117 → 148/22.

`tools/look/run.sh`: **38 passed, 0 failed** (33/0 before this addendum).

### Found on the way, not fixed

`appdir.eine_datei` reads **1023 octets** of an `INFO` file.
`assets/apps/explorer.osp/INFO` is **1020** long and its `fassung=`
field ends at 1019. **Three octets of headroom.** One more comment line
in that file and a field disappears silently — no error, no warning, the
program simply has no version. `translit.py` reports it from now on.
Fixing it means either a larger buffer on that stack frame or a shorter
comment, and neither belongs in an addendum about spelling.

---

## 7. HOW TO RUN IT

```
bash tools/look/run.sh              # every number above, from real boots

bash tools/look/shot.sh /tmp/x  shape=modern scheme=night mode=dark \
                                lang=de align=center edge=bottom
                                    # one image, booted, photographed

python3 tests/look/rawmetric.py     # no painting routine names a size
python3 tests/theme/rawcolour.py    # and none names a colour
python3 tools/i18n/scan.py          # and none holds German text

grep -rn 'leiste\|schreibtisch\|einstellungen' . | grep -v '^./.git/'
                                    # section 6a: only sentences about
                                    # the rename come back
grep -rn '/etc/hintergrund\|/etc/schirm\|/etc/zeit\|/etc/netz' .
                                    # section 6b: only docs/NAMING.md
```

Three of these runners are NOT in `./test.sh` and were not put there by
this round: `tools/desktop/run.sh`, `tools/i18n/run.sh` and
`tools/look/run.sh`. That is worth knowing, because the first two are
the ones that exercise the three renamed programs hardest. They were run
by hand for this addendum and their numbers are in the report; adding
sections to the acceptance suite is a decision for whoever owns it, not
something a rename should do on the way past.

`tools/look/shot.sh` builds the image the system is **supposed** to
have — `/lib/icons.ttf`, `/etc/passwd`, `/etc/schemas/`, `/etc/shapes/`,
`/etc/theme.conf`, `/etc/locale.conf`, `/etc/netview/` and the message
catalogues — with every knob of this round as an argument, so that a
claim about a variant is a claim about a picture that was really taken.

## 8. LICENCES

No third-party material was added by this round. The icon glyphs used in
section 2 are the Lucide subset that round ICONS brought in (ISC,
`assets/icons/LICENSE.lucide`, recorded in `THIRD_PARTY.md`); the design
values in section 4 are numbers read from documentation, which are not
copyrightable subject matter, and their source is cited per value. Every
file this round added carries an `SPDX-License-Identifier: GPL-2.0-only`
header, matching the repository. Apache-2.0 material (Material Symbols)
was not used and remains incompatible.
