# DESIGN-TOKENS — one place for the numbers of the look (11.10.2026, round W-TOKENS)

Source of truth for the NEW code: **`lib/fui/tokens.fi`** (integers only, nothing imported, works in
`profile kernel` and `profile app`). Check: `bash tools/tokens/run.sh` (80 claims, seconds, no QEMU:
the library is built for the build host by `tools/tokens/host.fi` and compared with an independent
Python model, true-sRGB contrast, scale 1 = scale 2 / 2).

## 1. How to use it (for every program, also settings / store / lock / login)

```firn
import fui.tokens                         // resolves through $FIRNLIB = lib/ (same as fui.navnum)

let s: u64 = wlibc.ui_scale()             // 1 or 2 (fuiscene: S.s_S / fuiscene.scale())
let r: u64 = tokens.radius(tokens.R_MEDIUM, s)       // 8 * s  (button, field, list item)
let g: u64 = tokens.space(tokens.SP_3, s)            // 12 * s
let dark: bool = wlibc.theme_dark()
let acc: u64 = 0x2563EB                              // the user's accent as 0xRRGGBB
let hov: u64 = tokens.acc_hover(acc, dark)           // derived: hover / press / ring / disabled / on-accent
let ring: u64 = tokens.acc_ring(acc, dark)
let fill: u64 = tokens.state_fill(tokens.ST_HOVER, true, acc, dark)   // one answer for every control
```

* Colours are `0xRRGGBB`, NOT byte-swapped. A fUi `Colors` field holds the R and B bytes swapped (see
  `swap_rb` in `kernel/user/fuib.fi`); a wlibc rect takes `0xRRGGBB` as is.
* Lengths are points; the function multiplies by the scale (`s` = 1 or 2). Never multiply twice.
* Every program gets the **same** hover / press / focus / disabled look by asking `state_fill` / `acc_*`
  and by never mixing colours itself.
* A new widget: a11y name + keyboard operation (project rule), states from the table below.
* Glass: `tokens.glass_blur(kind, s, off)` etc. tell a surface HOW MUCH frosting it wants; the frosting itself
  is done by the window server (`kernel/ui/wm.fi`, `blur_flaeche`, cached) — see section 4.

## 2. The tokens

| group | token | value (points at scale 1; scale 2 = x2) | use |
|---|---|---|---|
| radius | `R_SMALL` / `R_MEDIUM` / `R_LARGE` / `R_FULL` | 4 / 8 / 12 / pill | tag, checkbox / button, field, list item / card, popup, menu |
| spacing | `SP_1`..`SP_6` | 4 / 8 / 12 / 16 / 24 / 32 | inside a control / in a group / between groups / card padding / page margin |
| elevation | `E_LOW` / `E_MID` / `E_HIGH` | dy 2/4/8, reach 6/12/24, alpha 14/22/32 % (+14 in dark) | card at rest / menu, popup / dialog |
| type | `T_CAPTION`..`T_DISPLAY` | 12 / 15 / 15 / 18 / 24 | help text / body / strong / title / headline (same five as wlibc `TY_*`) |
| motion | `D_FAST` / `D_NORMAL` / `D_SLOW` | 100 / 160 / 300 ms | hover fade / menu / page; `ease_out`, `ease_in_out`, `ease_at(elapsed, total)` on thousandths |
| neutral | `N_BASE`..`N_PRESS` | light F3F3F3 FFFFFF FCFCFC FFFFFF D6D6D6 1B1B1B 5E5E5E A0A0A0 EAEAEA DEDEDE; dark 202020 2B2B2B 323232 2D2D2D 454545 F5F5F5 A8A8A8 6E6E6E 383838 2A2A2A | Fluent-like layers (base < surface < raised), text 16.8:1 light / 14.9:1 dark |
| accent | `acc_hover/press/ring/disabled/on` | light: hover 8 % black, press 18 % black; dark: hover 14 % white, press 14 % black; ring 35 % black / 55 % white; disabled 38 % over the surface; on-accent = better of white/black | derived for ANY accent |
| states | `ST_NORMAL/HOVER/PRESS/FOCUS/OFF` | focus keeps the normal fill, the 2-point ring shows it | button, toggle, slider handle, dropdown, textbox, list item, card, tab |
| glass | `G_BAR/MENU/QS/TIP/TOAST` | blur radius 8 (4 for tip/toast), tint = base (bar) / raised (others) at 72-82 % light, 78 % dark, grain 3 | frosted surfaces; blur 0 under `noglass` |

The accent default `2563EB` and the 4-grid / 2-4-6-8-12-16 radii are those of
`design-system/references/primitive-tokens.md` (ui-ux-pro-max skill); the neutrals follow the Windows 11
Fluent layer greys.

## 3. Audit — where the numbers lived before (measured on origin/main f4491e38)

| layer | file | what is there | state |
|---|---|---|---|
| raw ramps | `assets/schemes/*.scheme` (day, night, midnight, paper, contrast) | neutral 0..1000, accent (`accent=2563eb`), status | fine, user-selectable accent via `template`/`theme.conf` |
| semantic roles | `kernel/user/wlibc.fi` `T_BG..T_MENU` (18 roles), `bind_neutral/bind_accent` | colours by role; hover/press (`T_BTNHI/T_BTNDN`) are scheme entries, **not derived from the accent** | `tokens.acc_*` is the derivation for new code |
| form | `assets/shapes/{osum,modern,classic}.shape` -> `wlibc.M_*` | radius 8/8/8/6 (window/panel/button/field; W-D: was 12/10), spacing 4/8/16/24 (+pad 12/8, gap 12), shadow 32/8/12/4, focus 2, font 15, motion 160, blur 8, tint 22, noise 3 | the radii are **four** values (12/10/8/6); tokens give **three** (12/8/4) — the shape file keeps the four for the existing windows |
| fUi bridge | `kernel/user/fuib.fi` `theme_new()` | fills fUi `Colors` (roles, no accent states) and `Shape` (radii, pad, gap) from wlibc | the ONLY seam to the vendor fUi widgets (button, toggle, slider, textbox, ... are painted by `fui.render.draw_widget`, vendor/firn — pinned, not editable here) |
| scene host | `kernel/user/fuiscene.fi` | `sp(N)` with literal N: **173 uses, 112 on the 4-grid (65 %)**; off-grid: `sp(10)` x14, `sp(14)` x12, `sp(15)` x11, `sp(6)` x10, `sp(22)` x6, `sp(2)` x6, `sp(5)`, `sp(13)`, `sp(18)` ... ; radii come from the shape (`rb/rf/rp`), no literals | spacing literals remain; on-grid ones can move to `tokens.space` |
| start menu | `kernel/user/launcher.fi` | `sp(N)`: 39 uses, 20 on the 4-grid; off-grid `sp(14)` x5, `sp(5)`, `sp(2)` x4, `sp(54)`, `sp(22)`, `sp(38)` | tile sizes, fine |
| tooltip/toast | `kernel/user/barpop.fi` | pad 6 / 10 points, stripe 3 points, plate = `T_MENU` + 1 px `T_LINE`, radius = `wlibc.win_round` | off-grid pads |
| quick settings | `kernel/user/qs.fi` | 10 direct `wlibc.theme(T_*)` reads, 14 raw `wlibc` primitive calls (docs/FUI-STAND.md) | tiles not nodes yet |
| task bar | `kernel/user/taskbar.fi` | 41 direct `wlibc.theme(T_*)` reads, own paint (1 238 lines) | roadmap FUI-ALL section 11 |
| window server | `kernel/ui/wm.fi` | `FM_*` slots (radius, shadow, blur radius/tint/noise, alpha) fed from `wlibc.form_one` | glass lives here, cached (`blur_slot`, `blur_cache_on`) |
| CLI | `kernel/user/theme.fi` | the preset store (`theme list/show/apply`), NOT a token store | name collision only |

Inconsistencies found: (1) three radius sets (shape 12/10/8/6, fUi `Shape`, popups `win_round`); (2) hover/press
of an accent control comes from the scheme file, so a user accent keeps the scheme's hover (no derived
shade); (3) type sizes exist twice (`wlibc.TY_*`, shape `font=15`); (4) popup paddings 6 / 10 are off the
4-grid; (5) no named elevation levels — the shadow is one pair (`shadow`, `shadow2`) for all windows.

## 4. Glass (acrylic) — what exists, what this round adds

Exists (RUNDE BLUR / GLAS): the window server blurs what is BEHIND a window of layer `L_TOP`, `L_MENUE`,
`L_POPUP`, `L_TIP` (not `L_TOAST`, by design) with a two-pass box filter, SIMD, **cached** per window
(`blur_slot`, hit-rate counters `blur_treffer/blur_fehl`), clipped to the rounded shape (`blur_flaeche`), tint and
grain from `FM_BLURTINT/FM_BLURNOISE`. Radius 0 = off: `blur=0` in `/etc/theme.conf` (the "Darstellung" page slider)
turns every frosted surface into a flat plate. Measured: blur per call 0.97 ms, start menu open/close largest frame
13.1 ms (target <= 16).

Fallback: `blur=0` (setting) — and the token `glass_blur(.., off = true)` returns 0 for every surface.

(Progress of this round is in `reports/20261011-W-TOKENS.md`.)
