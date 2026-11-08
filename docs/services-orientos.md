# OrientOS backend for Firn `lib/services` v1

Status: rules + reply queue + thin backend skeleton landed; gate `services` (tools/services/run.sh).
Firn side: `lib/services` v1 (commit 52c0c4395, docs/services-contract.md) exists ONLY on Firn feature branches (checked 08.11.: not in Firn main ea7180d43, not in the Osum pin 04e18c93). The OrientOS backend is named in that contract as `lib/@orientos/services/svcos.fi`.
Manifest side: docs/manifest-v2.md (perm -> service call).

## Layout

| path | role |
|---|---|
| `lib/services/svcrules.fi` | status 0-6, capability bits 1-64, name/key rules, `store_dir`/`store_path` (`/data/<app>/services/<key>`), `status_name` |
| `lib/services/svcqueue.fi` | reply queue, 28-octet 4-aligned record heads (total, id, op, status, index, name_len, data_len), compaction, request ids |
| `kernel/user/services/svcosum.fi` | backend backend: `set_app caps copy_text paste_text message confirm file_open file_save store_set store_get store_remove store_has poll pending` |
| `kernel/user/services/svcdlg.fi` | spawn `/bin/dialogd`, read `<app folder>/services/dialog-<id>.reply`, queue the file result |
| `kernel/user/dialogd.fi`, `dialogd/{dlgdir,dlgpicker}.fi`, `lib/services/dlgproto.fi` | dialog window program: message/confirm/open/save, directory model, picker window, reply protocol (answer line, name line, content) |
| `kernel/user/dialogdemo.fi`, `tools/dialogd/{host.fi,run.sh,check.py,script.txt}` | proof app + host test + guest gate |
| `tools/services/{host.fi,run.sh}` | host test (54 checks) + 21 mutations + profile-kernel compile checks |

Module names are deliberately NOT `svc svcfile svcclip svcdialog svcstore svcos` (Firn module names are global by last component; the Firn names stay free for the pin lift).
Deviation from the contract: app names starting with `.` are refused (`..` would escape `/data`).
Guest-tested: gate `servicesguest` (tools/servicesguest/run.sh) boots QEMU and runs `kernel/user/svcproof.fi`: storage round trip, 64 KiB limit, key/app rules, app isolation, clipboard copy/paste, 4 mutated trees must go red. `svcosum.ensure_dirs` creates `/data` itself (fresh images have none).

## Call -> existing OrientOS code

| call | existing code | state |
|---|---|---|
| `svcdialog.message(kind,title,text,buttons,&answer)` | `kernel/user/dialog.fi` `show/show_message/show_warning/show_error` (kinds MESSAGE/CONFIRM, severities, answers YES/NO) through the action bus; `msgbox.fi` is the CLI door | `dialog.fi` shows the window-server trust prompt: NOT an app dialog. `svcosum.message` runs `dialogd` (`message` mode); `NO_BACKEND` and `CAP_DIALOG` off without `/bin/dialogd` |
| `svcdialog.confirm(title,text,&yes)` | `dialog.confirm` (same trust-prompt caveat) | done: `dialogd` `confirm` mode (Enter = yes, Esc = no) |
| `WM_TRUST` consent | `consent.fi` -> window-server dialog (docs/CONSENT.md); only for system confirmations (bus critical level, `elevate`) | NOT for app dialogs: an app dialog must not use the compositor-drawn trust prompt |
| `svcclip.copy_text` | transfer service `kernel/user/xfer.fi` (`set_text`, `get_text`, bus op SET/GET via `SYS_OSUM_BUS`), CLI `xclip`, history `cliphist` | done in `svcosum.copy_text` (text only, 16 KiB); rights `clipboard.write` enforced by the kernel table |
| `svcclip.paste_text(&id)` (async) | `xfer.get_text` (sync) | done in `svcosum.paste_text`: reply queued before return (`OP_CLIP_TEXT`, `NOT_FOUND` when empty) |
| `svcfile.open(accept,multiple,&id)` | explorer (`explorer.fi`, `explorer/exp*.fi`) has no picker mode; Firn side has `lib/fuishell/filechooser.fi` (fUi-drawn) | done: `svcosum.file_open` runs `/bin/dialogd` (open mode, accept list, single file) and queues `OP_FILE_ITEM` (name + content) + `OP_FILE_END`; never a path |
| `svcfile.save(name,mime,p,n)` | same picker; write through `fs` into the chosen place | done: `svcosum.file_save` stages the data as `dialog-<id>.in` in the app folder, `dialogd` writes the chosen file and replies with the name only |
| `svcstore.*` | per-app data folder `/data/<name>` (sandbox=files confines apps to it); `settingsd` is the SYSTEM settings provider (`settings.get/set` on the bus), NOT app storage | done in `svcosum.store_*`: files `/data/<name>/services/<key>`, written atomic via `/.tmp` + rename; key rules of the contract (1-64 `[A-Za-z0-9._-]`, 64 KiB) |
| `notify` (not in v1) | bus NOTIPOST (`notify.fi`, `notifc.fi`) | later `svcnotify` |
| `svc.caps()` | `svcosum.caps` | storage + async host always; clipboard bits when `xfer.available()`; dialog and FILE bits only when `dialogd` exists |

## Gaps (in order)

1. `dialogd`: multiple selection, mime in the accept list, sandbox=files inheritance for the picker.
2. Decide: `kernel/user/services/` stays the backend behind the Firn names, or a Firn `lib/@orientos/services/` platform dir calls it.
3. Pin lift of `vendor/firn` once `lib/services` is in Firn main (then rename or wrap: `svcosum` gets the Firn `svcos` function names).
4. Async host events: `svc.host_event(kind,status,id,q,p,n)` fed from the bus loop of the app (native replies are queued at once today).
5. Certus does not answer the `firn_web_*` service imports yet (Firn contract note), so web-side conformance needs Certus capability `services`.
6. done: gate `dialogd` (tools/dialogd/run.sh): host test, guest run with `dialogdemo` at scale 1 and 2, 2 mutated trees must go red.
