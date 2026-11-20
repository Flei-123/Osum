# w-honest94 — no false promises in the UI

## Audit (element, expected, actual, fix)
| Element | Expected | Actual | Fix |
|---|---|---|---|
| Store grid button "Open" (every installed app, e.g. Rechner = package `calc`) | app window opens | store spawned `/bin/<package>` (`/bin/calc` does not exist, program is `rechner`), result ignored, nothing happened | `open_app` now launches `/apps/<package>.osp/start` via `appreg.launch` (same path as start menu / taskbar), logs to launch.log |
| Store open failure | visible message with app name | none (return value dropped) | dialog "Could not open: <title>" (`store.openfail`, en+de) |
| Store detail page, installed + current app | Open button | no primary button at all (only Remove) | `Open` main button on the detail page (K_PRIMARY → `open_app`) |
| Store status texts (denied, pick app first, no bus, rejected, install error) | user sees them | written to `s_status`, which is never drawn anywhere | click-driven cases now show a notice dialog (`notice`) |
| All fUi controls in kernel/user (button, icon_button, toggle, tile creators with K_* keys) | handler exists | 0 without handler after scan; 6 hits checked by hand: 3 a11y fixture + widget gallery demo buttons (allowlisted with reason), K_TP_SW4 handled by default branch, qsnet K_SETTINGS handled in qs.fi | scan with cross-module lookup + allowlist `tools/noopaudit/allow.txt` |

## Gate
- `tools/noopaudit/run.sh` (host, quick, in gates.tsv as `noop-audit`): handler scan, store open-path audit, 3 mutants (K_ROWACT handler removed, `/bin/` path, silent failure) all red as expected.

## Not covered (open)
- No runtime click-through in QEMU yet (Start menu, tray flyouts, Settings pages, Explorer menus, context menus, Task Manager): only the static handler scan covers them.
- `set_status` messages in the Store that are polled each frame (job failed, busy, done) are still not drawn; the empty-state page covers the failed catalog case.
