# OrientOS backend for Firn `lib/services` v1

Status: rules + reply queue + thin backend skeleton landed; gate `services` (tools/services/run.sh).
Firn side: `lib/services` v1 (commit 52c0c4395, docs/services-contract.md) exists ONLY on Firn feature branches (checked 08.11.: not in Firn main ea7180d43, not in the Osum pin 04e18c93). The OrientOS backend is named in that contract as `lib/@orientos/services/svcos.fi`.
Manifest side: docs/manifest-v2.md (perm -> service call).

## Layout

| path | role |
|---|---|
| `lib/services/svcrules.fi` | status 0-6, capability bits 1-64, name/key rules, `store_dir`/`store_path` (`/data/<app>/services/<key>`), `status_name` |
| `lib/services/svcqueue.fi` | reply queue, 28-octet 4-aligned record heads (total, id, op, status, index, name_len, data_len), compaction, request ids |
| `kernel/user/services/svcosum.fi` | backend skeleton: `set_app caps copy_text paste_text message confirm store_set store_get store_remove store_has poll pending` |
| `tools/services/{host.fi,run.sh}` | host test (54 checks) + 21 mutations + profile-kernel compile checks |

Module names are deliberately NOT `svc svcfile svcclip svcdialog svcstore svcos` (Firn module names are global by last component; the Firn names stay free for the pin lift).
Deviation from the contract: app names starting with `.` are refused (`..` would escape `/data`).
Not run-tested: `svcosum.fi` storage and clipboard in a guest (compile-checked only; needs QEMU).

## Call -> existing OrientOS code

| call | existing code | state |
|---|---|---|
| `svcdialog.message(kind,title,text,buttons,&answer)` | `kernel/user/dialog.fi` `show/show_message/show_warning/show_error` (kinds MESSAGE/CONFIRM, severities, answers YES/NO) through the action bus; `msgbox.fi` is the CLI door | `dialog.fi` shows the window-server trust prompt: NOT an app dialog. `svcosum.message` answers `NO_BACKEND`, `CAP_DIALOG` stays off until `dialogd` |
| `svcdialog.confirm(title,text,&yes)` | `dialog.confirm` (same trust-prompt caveat) | `NO_BACKEND` until `dialogd` |
| `WM_TRUST` consent | `consent.fi` -> window-server dialog (docs/CONSENT.md); only for system confirmations (bus critical level, `elevate`) | NOT for app dialogs: an app dialog must not use the compositor-drawn trust prompt |
| `svcclip.copy_text` | transfer service `kernel/user/xfer.fi` (`set_text`, `get_text`, bus op SET/GET via `SYS_OSUM_BUS`), CLI `xclip`, history `cliphist` | done in `svcosum.copy_text` (text only, 16 KiB); rights `clipboard.write` enforced by the kernel table |
| `svcclip.paste_text(&id)` (async) | `xfer.get_text` (sync) | done in `svcosum.paste_text`: reply queued before return (`OP_CLIP_TEXT`, `NOT_FOUND` when empty) |
| `svcfile.open(accept,multiple,&id)` | explorer (`explorer.fi`, `explorer/exp*.fi`) has no picker mode; Firn side has `lib/fuishell/filechooser.fi` (fUi-drawn) | GAP: picker as separate process `dialogd` (line protocol of `std.dialog`) returning name + content, never a path |
| `svcfile.save(name,mime,p,n)` | same picker; write through `fs` into the chosen place | GAP, same |
| `svcstore.*` | per-app data folder `/data/<name>` (sandbox=files confines apps to it); `settingsd` is the SYSTEM settings provider (`settings.get/set` on the bus), NOT app storage | done in `svcosum.store_*`: files `/data/<name>/services/<key>`, written atomic via `/.tmp` + rename; key rules of the contract (1-64 `[A-Za-z0-9._-]`, 64 KiB) |
| `notify` (not in v1) | bus NOTIPOST (`notify.fi`, `notifc.fi`) | later `svcnotify` |
| `svc.caps()` | `svcosum.caps` | storage + async host always; clipboard bits when `xfer.available()`; dialog and FILE bits only when `dialogd` exists |

## Gaps (in order)

1. `dialogd` picker/dialog service (open/save, multiple, accept list, message/confirm) -- needed for the editor/files proof app.
2. Decide: `kernel/user/services/` stays the backend behind the Firn names, or a Firn `lib/@orientos/services/` platform dir calls it.
3. Pin lift of `vendor/firn` once `lib/services` is in Firn main (then rename or wrap: `svcosum` gets the Firn `svcos` function names).
4. Async host events: `svc.host_event(kind,status,id,q,p,n)` fed from the bus loop of the app (native replies are queued at once today).
5. Certus does not answer the `firn_web_*` service imports yet (Firn contract note), so web-side conformance needs Certus capability `services`.
6. Guest test of `svcosum` (storage round trip, clipboard) once a proof app imports it.
