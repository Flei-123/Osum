# Global hotkeys (W-S3, stage S3 of docs/APP-WINDOW-OPTS.md)

Portal model: the app registers a NAMED bus action (`jarvismini.toggle`); the ring-3 helper `hotkeyd` (a `wmplug` plugin named
`hotkey`, rights 0x410 in `/etc/wmplug.conf`) owns the KEY and calls the action through the bus (`actcli`, same door as `act call`).
The app never sees keys.

- Config `/etc/hotkeys.conf`: `ctrl+alt+j jarvismini.toggle`. Start: `wmplug enable hotkey` (autostart line in `/etc/wmplug.autostart`).
- Right `hotkey` (policy bit 4096, `P_HOTKEY`, NOT in `P_SAFE`; `osdk.py` word `hotkey`): checked when the line is read AND on every press
  (revoked right -> `hotkeyd: denied ... reason=revoked`).
- Kernel: `WM_PLUG_KEY(key, mods | 0x100)` ADDS a key (up to 4 extra per plugin, table at wmplug page 0x0C00). Errors: `E_RIGHTS` no R_ACT_KEY,
  `E_WRONGTYPE` already held (conflict, never overwritten), `E_EXHAUSTED` table full, `E_UNSUPPORTED` the tile tree binds the key (system key).
- Helper rules: binding must contain Ctrl+Alt; own duplicates -> `conflict held-by=<action>`; lock screen drops shortcuts before any plugin (`wm: hot gesperrt`).
- Serial lines: `hotkeyd: bound|conflict|refused <spec> <action> ...`, `fired`, `ok`/`failed`, `denied`.
- Test target: `/bin/jarvismini serve` (`a.jarvismini`, action `jarvismini.toggle`, `etc/actions.d/jarvismini.actions`). Gate: `tools/hotkey/run.sh`.

## Alt+Tab switcher (W1d, kernel `wm.fi`, gate `tools/alttab`)

- Alt+Tab opens a panel over the windows: one tile per switchable window (scaled picture of the window buffer + title), most recently used first
  (z-order from the top, focused window first). The SECOND window is selected. Tab = next, Alt+Shift+Tab = previous, Esc = close without a change,
  releasing Alt switches (`raise` + `set_focus`). While the panel is open no window is raised or focused and no key reaches a window.
- Alt release is read from the keyboard state (`kbd` `KB_OLD`) once per tick (`sw_tick`); if Alt is already up when the first Tab is handled
  (a quick tap) the panel opens and commits in the same call. Screen lock closes the panel (`sw_tick`); `wm: hot gesperrt` still drops the keys.
- Serial lines: `wm: switcher open|step|commit|cancel n=<windows> sel=<index> win=<slot>`.
- Only while Alt+Tab is the stock `next-window` binding; a `tiling.conf` rebind or a plugin that owns the key wins. Minimised windows are not listed
  (same filter as before: `wechselbar`). The panel is painted by the kernel compositor (`paint_switcher`); when S6 moves the chrome into `wmd` it
  becomes a scene window there (docs/COMPOSITOR.md).
- The touchpad 3-finger swipe still switches directly (`swipe_do`, no panel).
