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
| 5 | selection | contrast of the plate against the list ground; text on the plate | 4.7 : 1 plate (solid accent), white on blue | 1.26 : 1 tint + 3 px accent bar; text 13.0 : 1 |
| 6 | slider handle | handle = widget height | 28 px | 20 px |
| 7 | dropdown labels | labels cut off on the Appearance page | 5 of 5 | 0 (width from the face + `pad_x` 12) |
| 8 | text on the accent, dark mode | contrast of the Run / Apply label | 2.52 : 1 | see 4.2 |
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
`assets/src/`), cut by `tools/design/mkfont.py` to the same 339 characters, no hinting,
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

(see the end of this file, filled in from the runs)
