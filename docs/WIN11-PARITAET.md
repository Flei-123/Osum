# WIN11-PARITAET — where OrientOS still behaves differently from Windows 11 (23.10.2026, W-WIN11)

Boss wish: the UI should behave very much like Windows 11. This list is the gap analysis; the roadmap group is `Win11-Parität` (project orientos).
Status words: **done** = measured by a gate, **partial** = exists but differs, **missing** = not there. "Checked" means read in code or seen on a screenshot
this round; "assumed" means from the known Windows 11 behaviour and not yet checked here.

Priorities (boss, 23.10.): **P1** visible at once: tray flyout, snap, hover/active pill in the taskbar (W-TBHOVER runs in parallel), windows overlap cleanly
(W-REPAINT). **P2** quick settings / calendar / notifications, snap layouts, Win+arrows. **P3** animations, widgets.
Not here: touchpad settings/gestures (W-TPSET), flicker (W-FLICKER).

## P1

| # | Area | Windows 11 | OrientOS now | Status |
|---|---|---|---|---|
| 1 | Tray overflow flyout | small acrylic card, icons in a **grid** (about 4-6 per row), hover plate, pressed state, right click = item menu, closes on click outside / Esc | was: rows with a wide button + "..." button per item (screenshot `reports/…-shots/tray-before.png`); closes on outside click + Esc already | **this round: grid, tiles with fUi face (hover/press), right-click menu** |
| 2 | Tray chevron | `^` centred in a square button left of the tray icons | `glyph_button` centres the glyph by its ink (`icon_mid_ink`); looked fine on the 1280x800 shot | checked, gate `tools/midline` covers the bar |
| 3 | Window snap by dragging | title bar to left/right edge = half, top edge = maximize, corner = quarter, preview | only in tile mode (`S_TILE`, off by default); floating windows had **no** snap | **this round: floating snap, preview, corners** |
| 4 | Drag a maximized window | restores old size, pointer keeps its place on the title bar | the maximized window just moved, still full-size | **this round** |
| 5 | Taskbar hover / active pill | hover plate, accent pill under the active app, dot for running | W-TBHOVER (parallel worker) | other worker |
| 6 | Windows overlap cleanly | no tearing / stale strips when windows overlap | W-REPAINT (parallel worker), D-018 on real hardware | other worker |

## P2

| # | Area | Windows 11 | OrientOS now | Status |
|---|---|---|---|---|
| 7 | Win+Arrows | Left/Right half, Up max, Down restore/minimize; **second press moves on**: Win+Left then Win+Up = top-left quarter; Win+Shift+Arrow = other monitor | Left/Right half, Up max, Down restore/minimize exist (`win_arrow`); no quarters via two keys, no monitor move | partial |
| 8 | Snap Layouts | hover/long press on the maximize button shows a layout picker (halves, thirds, quarters) | `lib` tree knows every layout (`tile.snap`), but no flyout at the maximize button, only edge snap | missing |
| 9 | Snap Assist | after a snap the free half offers thumbnails of other windows | missing | missing |
| 10 | Snap groups | the snapped windows stay together in the taskbar / task view | tile mode only | missing |
| 11 | Quick settings | one card: Wi-Fi, Bluetooth, airplane, battery saver, brightness + volume sliders, edit/pencil | `qs.fi` exists (tiles + sliders); no Wi-Fi/BT toggles (no drivers, r21/r6); not compared tile by tile | partial, assumed |
| 12 | Calendar / clock flyout | month grid + agenda + notifications above the calendar | `calpop.fi` + `notifc.fi` are two separate popups | partial, assumed |
| 13 | Notifications | toast with buttons, slide-in, notification centre groups per app, Do-not-disturb | `notify.fi` toast + `notifc.fi` history; no actions on toasts, no slide | partial, assumed |
| 14 | Flyouts close by swipe/drag | quick settings and calendar close with a swipe to the edge (touch) | not built | missing |
| 15 | Alt+Tab | acrylic panel with thumbnails, wraps, Esc | done (`tools/alttab`) | done |
| 16 | Win+Tab / task view | desktops, thumbnails | `taskview.fi` exists; virtual desktops missing | partial |
| 17 | Win+D, Win+E, Win+R, Win+L, Win+I, Win+A, Win+N, Win+V | show desktop, explorer, run, lock, settings, quick settings, notifications, clipboard history | only Win+arrows and Alt+Tab found in `wm.fi`; the rest is not bound by default (`etc/hotkeys.conf` knows Ctrl+Alt only) | missing, checked |
| 18 | Task bar | centred icons, 48 px, start left of apps, search | `win11bar` gate: centred, labels never, capsule tray (r387); search box missing | partial |
| 19 | Start menu | pinned grid, recommended, search, power button | exists (`startmenu`), compared in earlier rounds | partial |
| 20 | Context menus | rounded 8 px, icons, separators, "Show more options" | `ctxreg` menus, rounded; no icons column | partial, assumed |
| 21 | Window chrome | 8 px radius, Mica title bar, snap flyout at maximize | radius 12 (design decision open, roadmap), caption buttons ok | partial |

## P3

| # | Area | Windows 11 | OrientOS now | Status |
|---|---|---|---|---|
| 22 | Window animations | open / close / minimize / maximize easing 150-250 ms | minimize animation exists (`minimize_anim`); no open/close/maximize easing | partial |
| 23 | Start menu / flyout animation | slide up + fade | none | missing |
| 24 | Widgets board | Win+W | not planned | missing |
| 25 | Touch keyboard | slides in on focus | P-010 | missing |
| 26 | Snap/drag shadow + translucent preview | filled translucent rectangle | 3 px frame only | missing |

## What this round changed (W-WIN11)

* **Tray flyout** (`kernel/user/traypop.fi`): overflow items are a grid of 52-point tiles (6 per row), tile face from fUi (hover + pressed), glyph centred in the
  tile, right click on a tile opens its menu (the "..." column is gone), Esc and click outside close it (already there, kept). Serial `traypop: tile i= x= y= w= h=`.
* **Floating window snap** (`kernel/ui/wm.fi`: `float_hover`, `float_drop`, `float_unmax`, `snap_zone`, `snap_rect`): edge 2 px at scale 1 (`2 * uisc`), corner zone
  64 px along the edge; preview = the existing frame preview; drop docks the window, the way back is saved once in `W_SAVE` (Win+Down and the maximize button restore).
  Dragging a maximized or snapped window further than 5 px restores its old size and keeps the pointer's place on the title bar. Kernel word `nosnap` = old behaviour
  (counter-proof). Gate: `tools/snap/run.sh`.
