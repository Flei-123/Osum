# FEATURES-STAND -- everyday OS features: what exists, how complete (11.10.2026)

Read from the code at origin/main f4491e38 (no new measurements; "tests" = existing gate scripts).

| Feature | Where | State | Missing | Effort | Benefit |
|---|---|---|---|---|---|
| Light/dark switch | `settings.fi` (mode light/dark/auto, `light_start`/`dark_start`), `theme.fi` | complete (global, scheduled) | quick toggle tile in quick settings | S | M |
| Accent colour | `settings.fi` (`settings.theme.accent.*`, contrast check) | complete | none (worker `settings`/`tokens` own it) | - | - |
| Wallpaper chooser | `settings.fi` -> `/etc/wallpaper` (OSYM, <= 170 KB), `desktop.fi` paints it/gradient | works, one picture, stretched | file picker, fit modes, slideshow | M | M |
| Notification centre | `kernel/bus/bus.fi` ring of 16 (post/peek/take/total/new), bell with unread count + toast on the bar (`taskbar.fi`, `barpop.fi`), `notify.fi` CLI | **bell + toast only; no history panel, no clear, bell click does nothing** | list panel, clear, per-item read state | M | **H** |
| Quick settings | `qs.fi` (1.7 kLoC, scene window, 6 tiles: network, sound, brightness, battery, standby, tiling) | complete, keyboard + a11y | Do-not-disturb, light/dark tile | S | M |
| Window snap | `wm.fi` drag-to-edge with preview (2 px strip, halves/maximise), `tile.snap` 8 targets, keys `mod+arrows` (`assets/tiling.conf`) | complete for halves/quarters | snap-layout flyout at the maximise button, snap assist (fill other half) | M | M |
| Alt-Tab | `wm.fi` `next_window` via `A_NEXT_WIN` (server window list, ring from focus) | switches focus immediately on each press | overlay (icon + title list), hold-Alt/release-commits, Shift+Tab | M-L (needs Alt-held state in the kernel key path) | H |
| Desktop icons | `desktop.fi` (1.1 kLoC, raw window, not on the scene tree) | works | scene tree (fUi share), drag, grid | L | M |
| Task view (Win+Tab) | `taskview.fi` (303 lines, not read in detail) | exists | unknown | ? | ? |

## Ranking (benefit / effort)
1. Notification centre panel (history + clear) -- bell and data exist, only the panel is missing.
2. Alt-Tab overlay -- logic exists, needs held-Alt tracking + one overlay window.
3. Snap-layout flyout -- snap logic exists, only the flyout window + hover on the maximise button is new.
4. Quick-settings tiles (DND, dark toggle) -- small.
5. Desktop icons on the scene tree -- big, low urgency.

## Constraints
- Anything in `wm.fi` / kernel needs a restart on the Dell (no hot reload).
- Settings pages (`settings.fi`, `store.fi`, `lock.fi`, `glogin.fi`, `theme.fi`) belong to the workers `settings` / `tokens`.
