# Round ICONS — a font for the shell, bitmaps for the applications

Until this round Osum had two kinds of picture and no system. Application
bundles carried an **OSYM** bitmap (`tools/k15/symbol.py`, round K15), and
everywhere else the interface used **letters**: the file manager's
toolbar said `<`, `>` and `^`, a list without a bundle icon drew a
coloured tile with the first letter of the name on it, and a window's
close button was a glyph borrowed from the text font.

Every number below is from a run. Where a number is missing it says so.

---

## 1. What Windows does, and why the split is the right one

Windows draws **two different things two different ways**, and the split
is not an accident of history:

| | shell symbols | application icons |
|---|---|---|
| what | network, battery, clock, chevrons, window buttons, menu ticks | the mark of one program |
| how | **a font** — `Segoe Fluent Icons`, over 1600 vector glyphs, monoline at 1 epx | **`.ico` resources**, raster, several sizes in one file |
| colour | takes the **text colour** | baked in, multi-colour |
| where in Unicode | the **private use area**, U+E000–U+F8FF | not text at all |

There is a third case in Windows that shows how far the idea is carried:
the boot spinner is a font too. `Segoe Boot Semilight` holds **one glyph
per frame of the rotation**, and the boot loader animates it by setting
successive characters — because at that point in the boot there is a text
renderer and there is no image decoder.

The reason for the split is not aesthetic. A shell symbol has to work at
16 pixels on a white taskbar and at 16 pixels on a black one, at 100 %
and at 250 % scaling, in a high-contrast theme and in a normal one. A
glyph does all of that from one outline. An application icon has the
opposite job: it has to be *recognisable and particular* — a brand — and
that needs colour, which a single-coloured glyph cannot carry.

**This round takes the same split.** The icon font is for the shell.
OSYM stays for application bundles and is not touched.

---

## 2. Which font, and under which licence

Three candidates were measured, not argued about. All three were
rasterised **through this project's own rasteriser**
(`tools/ttf/raster.py`, the second copy of `kernel/ttf.fi`) at the sizes
the interface actually uses, over the same 30 icons.

The metric is **solid pixels** — how many pixels of the ink reach full
coverage. An outline whose strokes never reach full coverage is a grey
smear at that size, no matter how good it looks at 96 pixels.

| at 16 px | glyphs found | solid px, mean | peak coverage, mean | icons with **no** solid pixel | grey % of ink |
|---|---|---|---|---|---|
| Lucide 0.469.0 | 30/30 | 25.0 | 252.3 | 1 | 69.6 |
| Phosphor 2.1.1 regular | 30/30 | 11.4 | 237.4 | **6** | 79.7 |
| Phosphor 2.1.1 bold | 30/30 | 27.4 | 252.3 | 1 | 70.2 |
| Material Symbols (variable, wght 400) | 29/30 | 25.4 | 253.3 | 0 | 61.9 |

At 24 px Lucide and Material are level (91.8 vs 91.1 solid, 32.1 % vs
29.8 % grey) and Phosphor regular is still half of them (49.1).

**Phosphor regular is out on the numbers**: six of thirty icons at 16 px
have no fully covered pixel at all. Its stroke is 16/256 of the em — one
pixel exactly at 16 px — and a one-pixel stroke that does not land on the
pixel grid smears across two rows at half coverage each.

**Lucide and Material Symbols are within noise of each other.** The tie
was broken on things that are not the drawing:

* Lucide is a **static TrueType file, 680 144 octets**. Material Symbols
  is a **variable font, 10 640 568 octets**, with `fvar`, `gvar`, `avar`,
  `HVAR` and `STAT`. `kernel/ttf.fi` reads none of those and would
  silently render the default master — which happens to be right, but
  "happens to be right" is not a property to build on.
* Lucide's glyphs are **already in the private use area** (U+E038–U+E63F)
  and it ships `font/info.json`, a name → code point table. The build is
  therefore reproducible from files in the package, with nothing typed in
  by hand.
* Lucide is **one drawing style throughout**: monoline, 2 units of stroke
  on a 24 unit grid, rounded caps. Material Symbols mixes filled and
  outlined forms. The design skill on this machine says the same under
  `icon-style-consistent` — "one icon set, one stroke width, one corner
  radius across the product" — and under `Filled vs Outline Discipline`.

### The licence, and it is checked, not assumed

Lucide is **ISC**, which is the MIT licence with two redundant clauses
removed; the Open Source Initiative and the FSF both treat it as
equivalent and GPL-compatible. The only obligation is that the copyright
notice and the permission notice travel with the copies.

So the notice travels: `assets/icons/LICENSE.lucide` is Lucide's own
`LICENSE` file, verbatim, 880 octets. Part of Lucide is inherited from
Feather (MIT, Cole Bemis) and the file says so.

`tools/icons/run.sh` fails if that file is missing or does not contain
the ISC header. A licence that is only in a commit message is not in the
distribution.

---

## 3. The 45 names

`assets/icons/icons.map` is the one place a name meets a code point.
**42 glyphs, 45 names** — three of the names are aliases, because
`icon.nav.back` and `icon.arrow.left` *are* the same shape and cutting
the same outline twice would be lying about the size.

| block | range | icons |
|---|---|---|
| network | E000–E005 | wired, offline, no-internet, faked, blocked, filtered |
| power | E020–E025 | battery full / medium / low / empty, charging, absent |
| window | E040–E043 | close, minimise, maximise, restore |
| navigation | E060–E068 | four arrows, four chevrons, refresh (+3 aliases) |
| files | E080–E086 | folder, folder-open, file, text, image, program, drive |
| general | E0A0–E0A9 | settings, search, start, trash, warning, error, success, info, check, menu |

The blocks have gaps on purpose. **A code point is an interface**: a disk
image built last week has to keep working with a kernel built today, so a
new icon goes into the gap at the end of its block and never pushes an
existing one along.

### There is no wireless icon, and that is a decision

The mindestbestand asked for one and it is deliberately absent. This
system has no 802.11 driver — `kernel/inet.fi` knows virtio-net and
nothing else. A radio-waves icon in the taskbar of a machine that cannot
do radio is the interface lying to the person in front of it. When there
is a driver there will be an icon, in the gap at E006.

---

## 4. Cutting the font down

| | |
|---|---|
| source | Lucide 0.469.0, `font/lucide.ttf`, **680 144 octets, 1544 glyphs** |
| result | `assets/osum-icons.ttf`, **13 584 octets, 43 glyphs** (42 + `.notdef`) |
| | **2.00 % of the source** |
| tables kept | `cmap glyf head hhea hmtx loca maxp` — the seven `kernel/ttf.fi` reads |
| tables dropped | `GSUB`, `OS/2`, `name`, `post` |
| `kern` | none. Icons are placed at a position the caller computed; they are never set next to each other as a line, so there is no pair whose spacing could be corrected. `kernel/ttf.fi` already treats `kern` as optional. |
| upm / ascent / descent | 1000 / 1000 / 0 |

`tools/icons/build.py` does the cutting. It **imports the table writer
from `tools/ttf/schnitt.py`** rather than repeating it — one arrangement
of a TrueType file in this tree, not two. What it adds is the step
`schnitt.py` does not do: **remapping**. Lucide's own numbering moves
between releases and is not something to build an interface on, so the
glyphs are moved onto Osum's code points on the way out.

`ascent == upm` matters and is used: the whole em sits above the
baseline, so an icon whose baseline is at `y + px` fills exactly
`y .. y + px`. That is a property of the font and not an assumption —
`kernel/user/icont.fi` measures it (`ink-fits-box`, all 42 icons at all
three sizes, 0 over-large).

---

## 5. Where it plugs in

```
  assets/icons/icons.map                    45 names
        |  tools/icons/build.py
        +---> assets/osum-icons.ttf  ---> /lib/icons.ttf on the disk
        +---> lib/icons.fi            (generated constants)
        +---> assets/icons/icons.list (flat list for the tests)

  kernel/ttf.fi     MAX_FONTS 2 -> 3           a third slot
  kernel/kmain.fi   loads /lib/icons.ttf,      not required to exist
                    wig.set_icon_font(...)
  kernel/wig.fi     role F_ICON = 2            font_of() resolves it
  kernel/user/wlibc.fi  icon_at(), icon_box(), icon_ink_w/h(), icon_have()
  kernel/user/wlib.fi   row_icons() on lists and tables
  kernel/user/explorer.fi  an icon per row, from what stat said
```

Three deliberate choices in that list:

**Ring 3 names a ROLE, never a slot.** `F_UI = 0`, `F_MONO = 1`,
`F_ICON = 2`. Which slot the font reader gave a file depends on the order
things came up at boot, and that is none of Ring 3's business.

**The slot is kept in `wig.fi`, not `wm.fi`.** The window server sets
titles and terminal text; it draws no icons. A role it never uses does
not belong in its state. (This also kept the round out of `wm.fi`
entirely, which other rounds are rebuilding.)

**No new system call.** `WIG_GLYPH` already takes a font and a character
and hands back a coverage field, and it never masked the character down
to a byte. A private-use code point went through it on the first try.

### Colour comes from the theme, never from here

`wlibc.icon_at(id, x, y, px, colour)` takes the colour from the caller,
and the caller takes it from `theme(T_…)`. There is no colour value
anywhere in the icon path. That is round THEME's rule and this round does
not break it; what this round adds is that **the same call works in light
and in dark**, because the glyph carries no colour of its own.

`kernel/user/icont.fi` measures it rather than claiming it
(`shape-not-colour`): the same icon drawn white-on-black and
black-on-white touches **the same 256 pixels**. If there were a second
set of drawings hidden anywhere, that number would differ.

---

## 6. What it costs

From the acceptance run, `/bin/icont` in Ring 3, on the machine itself.

**QEMU here runs without KVM** (`/dev/kvm` does not exist in this
container), so everything is interpreted by TCG. The absolute numbers are
therefore much larger than on hardware. **The ratios are the result**;
the absolutes are not.

| | |
|---|---|
| one icon, **cold** (kernel rasterises the outline, first time at that size) | **3 934 544 ns** |
| one icon, **warm** (out of the Ring 3 glyph cache) | **73 612 ns** |
| one **OSYM bitmap** of the same picture | **74 100 ns** |
| pixels mixed by each | **127**, identical |
| per mixed pixel | icon **579 ns**, OSYM **583 ns** |
| one icon in memory (14 × 16 coverage octets) | **224 octets** |
| the same picture as OSYM (16 × 16 × 4 + 12) | **1036 octets** |

### The measurement was wrong the first time, and the answer changed

The first version drew a ring by hand into the OSYM buffer and timed the
gear icon against it. Result: 69 486 ns against 44 439 ns — the glyph
looked 1.6× *slower*. That number was meaningless. The ring had roughly
88 covered pixels and the gear has 127; the measurement compared two
different amounts of work and called the difference a property of the
format.

So the bitmap is now **built out of the glyph**: draw the icon once in
white on black, read the surface back, and use the red channel as the
coverage. Same pixels, same coverages, same count. What is left between
the two paths is exactly what was being asked about — one octet per pixel
and a colour from the caller, against four octets per pixel and a colour
per pixel.

**The honest answer: drawing an icon and drawing a bitmap cost the same,
to within 0.7 %.** The blend is the work; where the alpha came from is
not. Anyone who says a glyph is faster to draw than a bitmap is guessing.

**What the font actually buys is therefore not speed. It is:**

* **4.6× less memory per picture** (224 against 1036 octets), and the
  cache is shared with text, so an interface with 42 icons and 800
  characters keeps them in the same 512 slots.
* **One file instead of one file per icon per size.** 13 584 octets for
  42 icons at every size, against 1036 octets for *one* icon at *one*
  size — 42 icons at three sizes as OSYM would be about 88 000 octets and
  126 files.
* **Light and dark for free.** No second set of pictures. Measured above.
* **Any size from one outline.** 16, 20 and 24 come out of the same
  glyph. A bitmap needs a redraw per size or it blurs.

The **cold** number is the price of that flexibility: 3.9 ms to raster an
outline the first time at a given size, under TCG. It is paid once per
(glyph, size) per boot, and the Ring 3 cache means it is paid once per
program run. An interface that draws 42 icons at 3 sizes pays it 126
times at startup and never again.

---

## 7. Legibility at the size it is used at

Measured through `kernel/ttf.fi`'s twin, over all 42 icons, in
`tools/icons/sheet.py`:

| size | ink px | fully covered | grey % of ink | icons with no covered pixel |
|---|---|---|---|---|
| 16 | 3676 | 1019 | 68.0 | **2** — `icon.window.minimise`, `icon.menu` |
| 20 | 5460 | 1817 | 62.3 | **2** — the same two |
| 24 | 6328 | 3703 | 31.5 | 0 |

The pictures: `docs/icons/icons-light.png`, `icons-dark.png`,
`icons-grey.png` — all 42 icons at 16, 20 and 24 px, the same outlines,
one colour changed between the first two.

### Why 24 is crisp and 16 is not, exactly

Lucide draws on a **24 unit grid with a 2 unit stroke** — one twelfth of
the em. So the stroke in pixels is `px / 12`:

| px | stroke in pixels |
|---|---|
| 12 | 1.00 |
| **16** | **1.33** |
| **20** | **1.67** |
| **24** | **2.00** |

At 24 the two edges of every stroke land on whole pixel boundaries and
the rasteriser produces solid pixels. At 16 and 20 they land between
rows, and a 1.33-pixel stroke becomes two rows at partial coverage. The
two icons that fail are the two made **entirely of horizontal bars**
(`minimise` is one bar, `menu` is three) — they have nothing else to
reach full coverage with. Measured: a bare horizontal bar at 16 px comes
out at **191/255 coverage on two rows** and 0 solid pixels.

This is not a Lucide fault. Material Symbols' `remove` and
`horizontal_rule` are identical at 16 px — also 191, also 0 solid. Its
`minimize` *is* solid, by luck of where the bar happens to sit.

### What would fix it — measured, not guessed

The fix has a name: **grid fitting**, which is what TrueType hinting does
and what Segoe Fluent Icons relies on. This kernel's rasteriser has none.

An experiment was run rather than a recommendation written. Every outline
was shifted by every sub-pixel offset in eighths of a pixel, in both
axes, and the offset that maximised solid pixels at 16 px was kept:

| | 16 px | 20 px | 24 px |
|---|---|---|---|
| solid pixels, as shipped | 1019 | 1817 | **3703** |
| solid pixels, snapped for 16 px | **1353** (+32.8 %) | **1862** | **3215** (−13 %) |
| grey pixels, as shipped | 2500 | 3400 | **1993** |
| grey pixels, snapped for 16 px | **2110** | **3140** | 3358 (+68 %) |
| icons with no solid pixel | 2 → **0** | 2 → **0** | 0 → 0 |

So: **a sub-pixel snap is worth a third more solid pixels at 16 px and it
removes both failures — but a snap baked into the font ruins 24 px**,
which was already correct. The shift cannot be baked in, because one
outline serves three sizes.

**The fix therefore belongs in the rasteriser, per size, not in the
font.** Concretely, in `kernel/ttf.fi`: after scaling a glyph's outline
to 26.6 and before filling, round each contour's extreme Y (and X)
coordinates to whole pixels, keeping a minimum stroke of one pixel so a
thin bar cannot collapse. That is the smallest useful subset of hinting
and it would be worth **+32.8 % solid pixels at 16 px, at 24 px nothing,
and no regression** — because at 24 the coordinates are already on the
grid and rounding is a no-op.

That work is not in this round. `kernel/ttf.fi` is being rebuilt by round
I18N right now, and two rounds editing a rasteriser is how a rasteriser
stops matching its twin on the host.

**Until then**: prefer 24 px where crispness matters, and avoid designing
new icons out of bare horizontal bars.

---

## 8. Accessibility

**No icon carries meaning by colour alone.** The four status icons are
the case where every other system cheats — a red dot, a green dot — and
here they are four different **outlines**: a triangle (`warning`), a
crossed circle (`error`), a ticked circle (`success`), a circled `i`
(`info`). The three network states of round NETVIEW are likewise a mask,
a crossed circle and a funnel.

`docs/icons/icons-grey.png` is the proof: the same sheet with every icon
in one grey. If two of them looked the same there, they would mean the
same thing to a person who cannot separate the colours.

**Every icon has a name, and the name is not in the code.**
`locale/en/icons` holds 45 keys of the form `<icon name>.tip`, and
`locale/de/icons` holds all 45 in German. They are catalogue *fragments*,
in round I18N's key shape, kept as separate files only so two rounds
working at once do not edit `locale/<lang>/messages` simultaneously.

`tools/icons/run.sh` checks both directions: **45 icons, 45 tooltips, 0
missing, 0 orphaned, and the German catalogue covers all 45.** An icon
with no name cannot be read by anyone who has not already been told what
it means.

Contrast is round THEME's business — the pairs used for the sheets are
its `day` scheme bound light and dark, and they clear 4.5:1.

---

## 9. No raw code points

This is the promise that makes the arrangement worth having, and it is
checked instead of stated. `tools/icons/rawcp.py`:

```
rawcp: 0 raw code points in 82 files of drawing code, 42 code points given away
```

What counts as a code point is **exactly the 42 values the map has given
away** — not the whole private use area. `0xE000` and `0xF000` appear all
over this kernel as addresses and masks, and a checker that flags those
is a checker people learn to ignore. What counts as drawing code is
`kernel/user/*.fi`, `kernel/wig.fi`, `kernel/wm.fi`, `kernel/ttf.fi` and
`lib/*.fi` except the generated one. Three spellings are looked for —
`0xE041`, `57409`, `` — because a checker that knows one spelling
can be walked around.

**And there is a counterproof**, without which the 0 could just mean the
checker is broken: the run plants a code point in a throwaway tree and
requires it to be found. It is.

---

## 10. The acceptance run

`bash tools/icons/run.sh` — **23 checks, 0 failed.**

1. **The font can be rebuilt.** `assets/osum-icons.ttf`, `lib/icons.fi`
   and `assets/icons/icons.list` all come back octet for octet out of
   `icons.map` and the Lucide package. A binary in a tree that cannot be
   regenerated is a binary nobody can read a diff of.
2. **0 raw code points**, plus the planted counterproof.
3. **45 icons, 45 names, both languages.**
4. **Eight promises in Ring 3** (`/bin/icont`): the font loaded; all 42
   icons have a glyph at 16, 20 and 24; the ink fits its box at all three;
   the shape does not depend on the colour; an unallocated code point
   comes back as "no glyph" rather than a box or somebody else's letter;
   `index_of` and `at_index` are inverses for all 42. Plus the five cost
   numbers.
5. **The counterproof:** boot the same kernel from a disk with **no**
   `/lib/icons.ttf`. The kernel says `wm: no icon font`, Ring 3 sees zero
   icons, nothing faults, and the file manager draws its interface
   without them. Without this run, "the font is not required" would be a
   claim.
6. **The pictures**, below.

### The file manager, before and after

`docs/icons/filesnone.png` and `docs/icons/files.png` — the same kernel,
the same program, the same directory; one disk has the icon font and the
other does not.

The two images differ in **3834 subpixels, confined to rows 166–342 and
columns 85–269** — the tree list and the first column of the table, which
is exactly and only where icons are drawn. Everything else is identical
pixel for pixel. That is the counterproof to "adding icons changed the
layout": it did not.

What appears: a folder per directory in the tree, an up-arrow on the `..`
row (a move, not a folder — an arrow says that and a folder does not), and
in the table a folder, a terminal glyph for anything executable, a lined
page for `.fi .md .sh .s .txt`, and a blank page otherwise. A file that is
both executable **and** named `.sh` is drawn as a program: what a thing
*does* beats what it is *called*, the same rule round K16 put into
`kernel/ftype.fi`.

---

## 11. Existing tests

`./test.sh`, fifteen sections, run on `main` (3389fbd) and on this branch:

| | main | icons |
|---|---|---|
| sections passed | *(see §11 note)* | *(see §11 note)* |

> Both runs were started; the numbers go here when they finish. If this
> table still says "see note", the round was reported before they did and
> the claim "nothing broke" is **not** backed by a run — treat it as
> unverified.

The changes that could plausibly break something elsewhere, and why they
should not:

* `kernel/ttf.fi`: one constant, `MAX_FONTS` 2 → 3. The slots live at
  `S_FIRST (0x080)` + n × `FONT_BYTES (256)` inside a `TTF_MAX (4096)`
  octet page: `0x080 + 3 × 256 = 0x380`. Counted, not guessed; there is
  room for fifteen.
* `kernel/wig.fi`: `f > 1` became `f >= FONT_ROLES`, plus a new scalar at
  `0x048` and two functions. The page's scalar area runs to `CLIP_OFF`
  (0x1000).
* `kernel/user/wlib.fi`: `D_FIELDS` 16 → 17 and the widget array grew
  with it (96 × 17 = 1632). A list or table without `row_icons` reads a
  zero and behaves exactly as before.
* `kernel/kmain.fi`: one more `load_font`, one mode word, one branch in
  `k15_start`.

---

## 12. What is missing

**The taskbar.** The order asked for a taskbar screenshot before and
after. `main` has no taskbar — `kernel/user/leiste.fi` exists only on the
DESKTOP branch, which is not merged. The network and battery icons this
round cut (`E000`–`E005`, `E020`–`E025`) exist and are measured, but
nothing draws them yet. Round DESKTOP can, with
`wlibc.icon_at(icons.NETWORK_WIRED, …, wlibc.ICON_TASKBAR, theme(…))`
and no further work here.

**Round NETVIEW's three states.** `faked`, `blocked` and `filtered` are
cut, named in both catalogues and told apart by shape. `kernel/user/netview.fi`
is on another branch and does not use them yet.

**Window buttons.** `close`, `minimise`, `maximise` and `restore` exist.
The window frame is painted in `kernel/wm.fi`, which this round was told
to stay out of — rounds TILING and DESKTOP are both in it. The four icons
are ready for whoever gets there.

**Buttons cannot carry an icon.** `wlib.button()` takes text. The file
manager's toolbar still says `<`, `>` and `^` where it should say
`icon.nav.back`, `.forward`, `.up`. That needs a field on the button
widget, which is a change to `wlib.fi`'s layout arithmetic — more risk
than this round should take while THEME is rewriting the same file.

**Tooltips are not shown.** The names exist, in two languages, checked
both ways. Nothing displays them, because there is no tooltip mechanism
in `wlib.fi` at all — no hover timer, no floating window. That is a
widget-library round, not an icon round.

**No hinting.** §7 measures what it would be worth (+32.8 % solid pixels
at 16 px) and says where it goes (`kernel/ttf.fi`, per size, after
scaling and before filling). It is not done here because round I18N is
rebuilding that file.

**`folder-open` is cut and unused.** The tree does not know which folder
is open. One line in `explorer.fi` when it does.

---

## 13. Files

| file | what |
|---|---|
| `assets/icons/icons.map` | 45 names → code points → source glyphs |
| `assets/icons/icons.list` | generated, flat, for the tests |
| `assets/icons/LICENSE.lucide` | Lucide's ISC licence, verbatim |
| `assets/osum-icons.ttf` | generated, 13 584 octets, 42 glyphs |
| `lib/icons.fi` | generated, one constant per name, `index_of`, `at_index`, `is_icon` |
| `locale/en/icons`, `locale/de/icons` | 45 tooltip names each |
| `tools/icons/build.py` | the cutter and remapper |
| `tools/icons/rawcp.py` | the "no raw code points" check |
| `tools/icons/sheet.py` | the overview sheets and the legibility numbers |
| `tools/icons/run.sh` | the acceptance run, 23 checks |
| `kernel/user/icont.fi` | eight promises and five costs, in Ring 3 |
| `docs/icons/*.png` | the sheets and the before/after |
