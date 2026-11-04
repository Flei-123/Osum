# Consent dialogs: inventory and unification

## Before (what the Boss saw)
| Place | Mechanism | Look |
|---|---|---|
| Start Taskmanager / Store / Installer / diskctl / drvctl (`ulib.needs_root`) | `/bin/elevate` own fUi window, kernel `execas: priv` | window "Administrator rights needed", Allow/Cancel, mouse+Tab |
| Install/update/remove in Store (`store.*`) | action bus, level critical, parked token -> window server dialog `WM_TRUST` (compositor-drawn, real keyboard/mouse only) | "<product> - Confirmation (from the system)", J/N |
| Settings critical keys, `settings.update.*` | same bus + `WM_TRUST` | same |
| App rights (`net`, `fs.home`, ...) | kernel label `app:<name>` + grant table (apprights), changed from Settings via bus | no dialog of its own |
| Disk write unlock (`wunlock`, `diskact`) | typed confirmation (CLI / fUi entry) | intentionally different (destructive) |
| Device pairing (tray) | tray popup | local pairing, not privilege |
| `busy.alert/confirm`, explorer delete | in-window fUi modal | app-local questions |

Difference: elevate was a normal window of a root helper (can be covered, is clickable by synthetic input); the bus dialog is drawn by the compositor above everything and answers only on real input.

## Now
- `/bin/elevate` asks through `kernel/user/consent.fi` -> `WM_TRUST`, the same dialog as bus confirmations.
- Text builder `kernel/user/trusttext.fi` has two registries: `META` (action pattern -> rights, publisher/signature phrase) and `RIGHTS` (id -> de/en text); new action `system.elevate`.
- Dialog shows: one-sentence action, publisher/trust line, rights list (max 3), details (request, action, level, from, args), J/Allow N/Deny, Enter/Tab/Esc.
- Limits raised for the longer text (TR_BYTES 1024, trust_buf 1040, TD_IN 1104, TD_DET_MAX 8).
- Serial markers of elevate kept: `elevate: ready|allowed|denied|start`.

## Not done yet
- Password/PIN field for admin consent (the compositor dialog has no text field).
- Dim backdrop (secure desktop look).
- Generic dialog API: done, see docs/ui/dialog-api.md (dialog.fi, menu.fi, /bin/msgbox, gate tools/dialog).
- Store still starts through elevate (`needs_root`), then asks again on install.
