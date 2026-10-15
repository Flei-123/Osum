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
