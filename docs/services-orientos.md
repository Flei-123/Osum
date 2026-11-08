# OrientOS backend for Firn `lib/services` v1

Status: mapping and gaps only. NO skeleton module yet: the pinned Firn toolchain (`vendor/firn/COMMIT` 33b67b5e) has no
`lib/services`; v1 is in the Firn main (52c0c4395, docs/services-contract.md, modules `services.svc svcfile svcclip svcdialog
svcstore`, native backend `svcos`) and ships with the next nightly after 0.1.4898. The OrientOS backend is named in that
contract as `lib/@orientos/services/svcos.fi` (CAP_ASYNC_HOST, requests to services, answers as `svc.host_event`).
Manifest side: docs/manifest-v2.md (perm -> service call).

## Call -> existing OrientOS code

| call | existing code | state |
|---|---|---|
| `svcdialog.message(kind,title,text,buttons,&answer)` | `kernel/user/dialog.fi` `show/show_message/show_warning/show_error` (kinds MESSAGE/CONFIRM, severities, answers YES/NO) through the action bus; `msgbox.fi` is the CLI door | ready; map `kind/buttons` to `dialog.show`, NONE/YES/NO to `OK/CANCELED` |
| `svcdialog.confirm(title,text,&yes)` | `dialog.confirm` | ready |
| `WM_TRUST` consent | `consent.fi` -> window-server dialog (docs/CONSENT.md); only for system confirmations (bus critical level, `elevate`) | NOT for app dialogs: an app dialog must not use the compositor-drawn trust prompt |
| `svcclip.copy_text` | transfer service `kernel/user/xfer.fi` (`set_text`, `get_text`, bus op SET/GET via `SYS_OSUM_BUS`), CLI `xclip`, history `cliphist` | ready; rights `clipboard.write` enforced by the kernel table |
| `svcclip.paste_text(&id)` (async) | `xfer.get_text` (sync) | ready; queue the reply at once like the native backends |
| `svcfile.open(accept,multiple,&id)` | explorer (`explorer.fi`, `explorer/exp*.fi`) has no picker mode; Firn side has `lib/fuishell/filechooser.fi` (fUi-drawn) | GAP: picker as separate process `dialogd` (line protocol of `std.dialog`) returning name + content, never a path |
| `svcfile.save(name,mime,p,n)` | same picker; write through `fs` into the chosen place | GAP, same |
| `svcstore.*` | per-app data folder `/data/<name>` (sandbox=files confines apps to it); `settingsd` is the SYSTEM settings provider (`settings.get/set` on the bus), NOT app storage | ready: files `/data/<name>/services/<key>`, written atomic; key rules of the contract (1-64 `[A-Za-z0-9._-]`, 64 KiB) |
| `notify` (not in v1) | bus NOTIPOST (`notify.fi`, `notifc.fi`) | later `svcnotify` |
| `svc.caps()` | -- | storage, dialog, clipboard now; FILE bits only when `dialogd` exists |

## Gaps (in order)

1. `dialogd` picker service (open/save, multiple, accept list) -- needed for editor/files proof app.
2. `lib/@orientos/services/svcos.fi` in the Firn tree needs Osum syscalls/bus from Firn `plat`; today these live in `kernel/user/*.fi`
   (profile kernel/app), not in `lib/`. Decide: thin Osum module `kernel/user/services/` behind the Firn names, or a Firn `@orientos` platform dir.
3. Pin lift of `vendor/firn` to a toolchain containing `lib/services` (blocks any compile here).
4. Async host events: `svc.host_event(kind,status,id,q,p,n)` fed from the bus loop of the app.
5. Certus does not answer the `firn_web_*` service imports yet (Firn contract note), so web-side conformance needs Certus capability `services`.

## Next step once the pin has `lib/services`

`kernel/user/services/svcosum.fi`: backend with the module and function names of `services.svcos` (caps, dialog via
`dialog.fi`, clipboard via `xfer.fi`, store under `/data/<name>/services/`, file ops `NO_BACKEND` until `dialogd`), plus a host
test like `tools/services/conformance.fi` (capability list, storage round trip, reply queue). Not written now: the API would be
compiled against a lib that is not in the pin.
