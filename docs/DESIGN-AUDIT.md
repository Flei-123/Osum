# DESIGN-AUDIT -- why OrientOS looks worse than a Win11 / Fluent / browser UI, measured (r399)

Order from Justin (07.10.2026): "the look is bad compared with a modern Windows / Rust /
browser app; the old stand looked better -- make an honest analysis and fix the biggest gaps."
This file is the analysis, the fixes, and the numbers. Pictures are in
`docs/shots/design-audit/`; the tools that made and measure them are `tools/design/`
(`audit.sh`, `screens.sh`, `check.py`, `measure.py`, `mkboards.py`, `mkfont.py`, `mkicons.py`,
`run.sh`).

## 0. The honest short version

* The **system** (tokens, radii, spacing, motion, 32-bit framebuffer, scaling, hover/press/focus
  states) is not the problem -- it is a three-layer design system that already follows
  Fluent's numbers (section 3). What made it look cheap are **ten concrete things on the
  surface**, each of them measured below:
  1. the **face**: DejaVu Sans -- 6.8 % wider than Inter with 2 447 kerning pairs, the look of
     2005 (Verdana's cousin);
  2. the **wallpaper** was stretched with the nearest neighbour (every source pixel a 3x3 block,
     6 % distorted) while the lock screen showed the same file smooth;
  3. **frosted surfaces** (start menu, tooltips) painted a grey blurred rectangle behind their
     rounded corners -- Justin's own finding from real hardware, still there;
  4. **program icons** were 16x16 pixel drawings on a 40 px bar (24 px in Windows) and 16 px in
     the start menu;
  5. a **selection** was a solid accent plate with white text (Windows 10 / GTK2), no soft tint;
  6. a **slider handle** as tall as the widget (28 px disc on a 4 px track);
  7. **dropdown labels** cut off ("me...", "stro...") -- five of five on the Appearance page;
  8. dark mode: the **text on the accent** was white on a light blue (2.5 : 1);
  9. the **spacing tokens** of the shape file never reached the fUi programs (fUi kept its own
     copy of the same numbers);
  10. **no depth**: windows have no shadow (default off since ECHTHARDWARE-6) -- *not changed*,
      see section 5.
* The **old stand** did not look better in the parts compared (start menu, settings, explorer,
  dialog, quick settings, dark mode): its settings page overlapped cards in dark mode, the
  explorer had fat scroll bars, the dialog was a bare box. What it had and the scene tree
  lost: slider **value read-outs** (12, 100 %), a focus ring on the search field. Both are on
  the roadmap.

## 1. Evidence (pictures, same machine, same clock)

`tools/design/audit.sh` boots ONE machine per tree (the shipping bar configuration: height 40,
no labels, sea wallpaper, scheme `day`, shape `osum`, 1280x800, KVM) and drives it through the
views with `tools/design/views.txt`; `tools/design/screens.sh` boots lock and sign-in screens
alone. Three stands were photographed:

| stand | tree | what it is |
|---|---|---|
| old | `ce8bce36` (02.10.2026) | before settings / explorer / launcher moved to the fUi scene tree |
| main | `3e35808b` | main at the start of this round |
| after | this branch | |

Boards (`docs/shots/design-audit/vergleich-*.png`) put the three side by side; the detail
boards zoom into one cause each. Win11 reference crops (Wikimedia Commons screenshots, and
Justin's own bar `assets/ref/win11-taskbar-ref.png`) were laid beside them for the review but
are **not** in the repository (third-party screenshots of a proprietary UI).
The Dell was not touched.

## 2. Causes -- measured, not guessed

| # | candidate | measurement | before | after |
|---|---|---|---|---|
| 1 | face, width | advance of "Search programs  Einstellungen Darstellung Dateimanager Write and change text" at 15 px (PIL on the cut font) | 614.6 px (DejaVu) | 572.8 px (Inter) |
| 1 | face, kerning | pairs in the `kern` table | 2 447 | 10 900 (GPOS flattened with HarfBuzz) |
| 1 | face, rendering | ink width of "Search programs" in the screenshot vs Chromium rendering the same face at 15 px | -- | 120 px = 120 px, ink mass 341 vs 323 (5 % heavier: linear coverage, no contrast boost) |
| 2 | wallpaper | share of equal horizontal neighbour pixels in the tree line (1280x800 crop) | 0.721 | 0.491 |
| 2 | wallpaper | aspect | 16:9 stretched to 16:10 (6 % distortion) | cover, centred (like the lock screen) |
| 3 | frosting at rounded corners | pixels more than one pixel outside the arc of the start menu corner that differ from the picture without the menu | 17 of 17 | 0 of 17 |
| 4 | icons | ink height in the bar / in the start menu | 14-16 px / 16 px | 24 px / 30 px |
| 2 | wallpaper, cost | a full repaint of the desktop (`desktop: paint ticks=`, 1280x800, KVM, loaded host) | 28 ticks (nearest neighbour; a 199 px picture) | 41 ticks (cover + bilinear) -- once at start and on theme change, never per frame |
| 5 | selection | contrast of the plate against the list ground; text on the plate | 4.7 : 1 plate (solid accent), white on blue | 1.26 : 1 tint + 3 px accent bar; text 13.0 : 1 |
| 6 | slider handle | handle = widget height | 28 px | 20 px |
| 7 | dropdown labels | labels cut off on the Appearance page | 5 of 5 | 0 (width from the face + `pad_x` 12) |
| 8 | text on the accent, dark mode | contrast of the Run / Apply label (Run button, dark, pixels) | 2.52 : 1 | 7.96 : 1 |
| 9 | spacing tokens | `pad_x`, `pad_y`, `gap` of the shape file in fUi's theme | not wired (fUi default) | wired in `fuib.theme_new` |

Candidates that are **not** a cause (measured, so nobody chases them again):

* **Framebuffer depth / banding**: the card reports depths `0x101018110` (4 to 32 bit), the
  system runs 32 bit (`docs/DISPLAY.md`); a screenshot of the desktop has 41 063 colours.
* **Anti-aliasing of shapes**: `corner_cov` 4x4 and fUi's exact coverage; `tools/look` and
  `tools/softui` measure corners and edges and were green before and after.
* **Hover / press / focus states and motion**: they exist (hover tween 120 ms: serial lines
  `wlib: anim was=4 ... p=250 / 583 / 916 / 1000 dur=12`).
* **HiDPI scaling**: `ui_scale()` and the 4K / 1440p runs of earlier rounds; the only scaling
  defect found was the wallpaper (a 480x270 source is 8x on 4K -- bilinear now matters more).

## 3. The design system, in one place

Nothing new was invented; the audit found where the pipeline leaked and closed it.

```
assets/schemes/*.scheme   layer 1  raw ramps (neutral 0..1000, accent, status)         one file per scheme
        |
kernel/user/wlibc.fi      layer 2  semantic roles (surface, text-primary, accent,       bind_neutral / bind_accent
        |                           selection, ...) bound for light and for dark
        |                  layer 3  component -> role table (comp_map_init)
assets/shapes/*.shape     form     radii by role, spacing 4 grid, ctrl_h, row, font,     one file per shape
        |                           motion, divider, focus ring, shadow, blur
kernel/user/fuib.fi       bridge   theme_new(): colours, radii, border, and (r399)       the ONLY seam to fUi
        |                           pad_x / pad_y / gap  --> fui.theme Colors + Shape
kernel/ui/wm.fi          window server form slots FM_* (window radius, shadows, blur)
assets/osum-sans*.ttf     type     Inter (r399), TY_CAPTION..TY_DISPLAY = 12/15/15/18/24 px
assets/apps/*.osp/symbol.osym   icons  vector art baked to 32x32 (r399)
```

`tools/theme/model.py` (second implementation of layers 1-3) and `tools/themestore` compare
the Firn binding and the Python model token for token; r399 changed the selection binding in
both (section 4.3).

## 4. What changed

### 4.1 Face (`assets/osum-sans.ttf`, `osum-sans-bold.ttf`)
Inter 4.0 Regular / SemiBold (SIL OFL, `assets/LICENSE-OFL-inter.txt`, sources in
`assets/src/`), cut by `tools/design/mkfont.py` to the same 339 characters (`assets/src/osum-sans.cps`; U+00AD, U+0149 and U+FFFD, which Inter lacks, are mapped to a hyphen, an n and a question mark), no hinting,
GPOS pair kerning flattened with HarfBuzz into a format-0 `kern` table (the 10 900 strongest
pairs, the subtable length is 16 bit). The cut is reproducible octet for octet
(`tools/wm/run.sh` part 3, `tools/i18n/run.sh`). `THIRD_PARTY.md` 4.1a.

### 4.2 Surfaces
* `kernel/user/desktop.fi`: wallpaper cover + bilinear (fixed point 16.16) for pictures at least
  200 px wide; narrower pictures are patterns (the test harnesses use 120x90 chequers) and keep
  the nearest-neighbour stretch.
* `kernel/ui/wm.fi` `blur_flaeche`: pixels outside the corner arc of the window (radius
  `FM_RADIUS`) keep the unblurred picture. This is the "rectangle behind the rounded surface"
  Justin reported on real hardware (`tools/design/cornercheck.py` measures the other half of
  it, a fill outside the arc).
* `kernel/user/fuiapp.fi` `panel`: popup, menu and dialog cards float on a soft shadow made of six
  growing translucent plates, painted inside the window's own canvas (nothing is drawn outside
  the window rectangle -- the reason window shadows are off, section 5).
* text on the accent: `fuib.theme_new` binds `text_on_accent` to the *on-accent* role, no longer to
  the selection text (the selection is a tint now).
* desktop module text is centred on its capitals (`kernel/user/modul.fi`).

### 4.3 Selection
`wlibc.bind_accent`: `selection` = 22 % accent over the raised surface, `on-selection` = normal
text; the high-contrast schemes keep the solid accent plate. The list painters of the scene host
draw a 3 px accent indicator bar (`fuiscene.sel_bar`). `tools/theme/model.py` mirrors the binding.

### 4.4 Icons
`tools/design/mkicons.py` draws every bundle's icon from a Lucide glyph (ISC) on a rounded
gradient tile, supersampled and reduced with Lanczos, 32x32, true alpha, into
`assets/apps/<bundle>.osp/symbol.osym`; `tools/k15/bundle.py` takes it before `symbol.txt`.
`wlibc.icon_draw_fit` draws such a picture into a square of any size (area-averaged,
premultiplied); the bar draws it at 24 points, the start menu at 32 (`fuiscene.row_icon`,
`icon_col`). 16x16 drawings are told apart by size and keep their integer scale.

### 4.5 Controls
Slider handle 20 px; the three dropdowns of the Appearance page 100 px wide with `pad_x` 12
(`assets/shapes/osum.shape`, wired into fUi); fUi spacing tokens from the shape file.

### 4.6 Test builders
The file manager passed the 2 134 016 octets a format-2 file may hold; `tools/osum/mkfs.py`
now builds format 3 by itself when (and only when) a source file is bigger than that, so no
runner needs its own `--v3` and every image built before stays octet for octet the same.

## 5. What was NOT changed, and why

* **Window shadows stay off.** ECHTHARDWARE-5/6 traced "comb streaks" at window edges to
  the write-combining frame buffer of the Dell and switched the shadow off by default; the fix
  (`sfence` before every slot remap) was never confirmed on that machine. Windows 11 has
  shadows; re-enabling them is a one-line default but needs a test on the Dell.
* The console editor (`/bin/edit`, "Editor" in the start menu) prints raw VT sequences into the
  kernel terminal, which has no VT parser (`kernel/ui/wm.fi` `term_putc`): the picture shows
  `[?25l[1;1H[7m edit New file ...`. "Editor+" (`nedit`) is the windowed one.
* Settings: the slider **value read-outs** of the old stand are gone; the explorer toolbar shows
  two up arrows and "Start" twice; the kernel terminal has no inner padding; title bars are 22 px
  with 12 px text (Win11: 32 px); the bar is left-aligned (Win11 layout is `taskbar.conf` only).

## 6. Tests

Final state of this branch, each suite started through `/root/jarvis/bin/heavy`, compared with `main`
`3e35808b` (the numbers of the right column are the ones recorded for main, or measured in this
round where they say so). Runs on a loaded host; the interactive ones (click tests) are
load-sensitive and were repeated when they flickered.

| suite | main | this branch |
|---|---|---|
| `tools/themestore` | 298/0 | **298/0** |
| `tools/look` | 41/0 | **41/0** |
| `tools/softui` | 24/0 | **24/0** |
| `tools/alltag` | 44/0 | **44/0** |
| `tools/k15` | 258/0 | **258/0** (menu baseline and vector-icon checks adapted, see below) |
| `tools/desktop` (sections 1-8; section 9 re-runs `wm` 108/0 and `k15`, which was run on its own) | 104/0 | **104/0** |
| `tools/barscene` / `win11bar` / `barpop` | 29/0, 25/0, 10/0 | **29/0, 25/0, 10/0** |
| `tools/qsfui`, `paint`, `explorer2` | 20/0, 36/0, 49/0 | **20/0, 36/0, 49/0** |
| `tools/lockscene`, `loginscene`, `a11y/scene.sh` | 15/0, 21/0, 25/0 | **15/0, 21/0, 25/0** |
| `tools/wm` | 107/0 | **108/0** (one more: the Inter cut is reproducible) |
| `tools/fourbugs`, `menuhover`, `menualive` | 26/0, 14/0, 9/0 | **26/0, 14/0, 9/0** (`menuhover` once showed a blind counter-proof under load; the repeat is 14/0) |
| `tools/toolbench` | 34/3 (28/6 measured under load in this round) | 35/2 -- the interactive taskmgr checks flicker under load, on main too |
| `tools/i18n` | stops at `mkfs` (file manager over the format-2 limit) | gets through; 12 stale failures remain (settings reports of the old `wlib` page, the message-quota check -- identical output on main) |
| `tools/dmodul` | stops at `mkfs` | 9/1 (`2-gezogen.png` missing: a picture timing issue, not a measurement) |
| **`tools/design/run.sh`** (new) | 4/6 (counter-proof on the pictures of main) | **10/0** |

Changes to the harnesses, all with their reason on the line:
`tools/k15/run.sh` (the baseline of a popup row is `4 + the height of "l"`, read out of the face with
the second rasteriser: 16 for DejaVu, 15 for Inter, measured by trying baselines 14..20 against the
picture: 0 wrong at 15; the vector icons are compared by their opaque pixels), `tools/k15/icon.py`,
`tools/theme/model.py` and `tools/themestore/run.sh` (selection binding; the radius slider is found by
its width), `tools/wm/run.sh` and `tools/i18n/run.sh` (the cut of the face), `tools/osum/mkfs.py`
(format 3 by itself when a file is too big).

## 7. Round 2 (07.10.2026): r400 - r403, the rest of the list

What section 5 left open, built:

| item | what | measured / checked by |
|---|---|---|
| **r401 slider read-outs** | `fuiscene.slider_readout(key, lo, hi, pct)` tells the host the range once per build; `readouts()` (called from `paint`) writes the number right of the track (12, 100 %, 100 %, 8 on the Appearance page), so it is always the number the handle shows, also while dragging | picture `03-einstellungen` of the audit run; a first version died with `panic: integer overflow in 'u64 - u64'` (label height 24 > node height 20) -- found by the same run, fixed |
| **r400 console editor** | a VT100 subset in the kernel terminal (`wm.fi` `term_esc_take` / `term_csi`): cursor position `H f`, `A B C D G d`, erase `J K`, reverse video `7 / 27 / 0 m`, private sequences (`?25h/l`) swallowed, unknown sequences dropped whole, a sequence cut in two writes works. The grid has a second frame with one attribute octet per cell (bit 0 = reverse) | kernel self-test `wm: vttest 7 / 7`, and `tools/wm/run.sh` checks it (108/0 + 1). `/bin/edit` writes exactly these sequences (`esc_num`, `clear_eol`, `reverse_on`, `cursor`) |
| **r402 title bar / chrome** | three shape numbers (`title_bar`, `cap_w`, `frame`; `osum.shape`: 32 / 46 / 1) through `wlibc` -> `WF_*` -> `wm.FM_*`; `classic` and `modern` do not say them and keep 19 / 30 / 2. Caption buttons: hover plate, **held** plate (deeper), they act on **release** over the same button (press on one, leave, release elsewhere = nothing). Alt+F4 closes the window with the focus the way its close button does | `tools/deco/run.sh` (new): measures the bar (32), the buttons (46), the title's room above and below, red close plate, soft plates, held, release elsewhere, release on the button, Alt+F4 |
| **r402 start menu** | Windows 11 layout: search field with hint on top, "Pinned" grid (6 columns of 100 x 88 tiles), "Recommended" (the recent ones first; a programme is never shown twice), user and power button at the bottom. Typing turns the window into the result list; "All apps" shows the whole list, "Back" returns. The old list window stays: argument `liste` or `startmenu=list` in `/etc/taskbar.conf` (the k15 runs use it) | `tools/startmenu/run.sh` (new) |
| **r403 hover / press transitions** | not measured in this round (they are the system's tween, 120 ms, as in section 2) | still open |
| **r399 window shadows** | the switch exists since ECHTHARDWARE-6: `shadow=on` in `/etc/theme.conf`, default **off**; the Apply button used to **drop** the line when it rewrote the file -- now it is written back (`theme_conf_write`) and the Appearance page has a check box. **Not turned on by default: only the Dell can say whether the comb streaks are gone** | `docs/DESIGN-AUDIT.md` section 5 stays true: the default is off until the Dell test |

### What a user sees

* the title bar is 32 points high, the buttons 46 x 32 (the size every Windows user knows), the frame one point,
* the close button is red on hover, the others a soft grey plate, held a deeper plate,
* the start menu is the Windows 11 one,
* the console editor draws a screen instead of `[?25l[1;1H[7m ...`,
* the sliders show their numbers.
