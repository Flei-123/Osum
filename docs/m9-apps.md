# M9: OrientOS apps on fuiscene over the services contract

Goal (ecosystem roadmap L3 + M9): file manager, settings, notes (and later the terminal) run on `fuiscene` and reach files, dialogs, clipboard and storage only through the services layer (`kernel/user/services/svcosum.fi`, contract: docs/services-orientos.md).

## Inventory (main 44f861559)

| app | source | on fuiscene | services used today | notes |
|---|---|---|---|---|
| explorer | `explorer.fi` + `explorer/exp{base,menu,nav,work}.fi`, 5.9k lines | yes (`fuiscene`, `fuiapp.apphost`, `uitheme`) | none: raw `libc.io`, own confirm via `fuiscene.dialog_open`, clipboard through xfer directly | also the model behind the `dialogd` picker (`dialogd/dlgdir.fi`) |
| settings | `settings.fi` + `settings/*.fi`, 11.9k lines | yes | none: system settings go over the bus (`settingsd`), not app storage; 3 files still use `wlibc` | provider side stays bus, only UI state and confirms can use services |
| svcedit (editor) | `svcedit.fi` + `svcedit/*.fi` | yes (`fuiscene.editor`, `fuied`) | open, save, confirm, store (recent) | first services app, gate `svcedit` |
| nedit (old editor) | `nedit.fi`, 1.2k lines, latin-1 binary | yes | none | to be retired in favour of svcedit once Open-with and shortcuts match |
| notepad (new) | `notepad.fi` + `notepad/np*.fi` | yes (`table_list`, `fuiscene.editor`) | store (index + note per key), confirm | gate `notepad`; `notes.fi` is the action-bus demo, not an app |
| terminal | `term.fi` (spawner), `termfull.fi` (error window), kernel tty window | error window only | n/a | stays a kernel tty window until a fUi terminal widget exists (ecosystem M10) |

## Services gaps found

| call | needed by | state |
|---|---|---|
| `store` key listing | notepad, later explorer view state | DONE: `svcosum.store_keys(out, max, &len)`, synchronous, newline-separated; notepad lists `note-<id>` keys, titles come from the first line of each note |
| `notify` | explorer (copy progress, done), settings (restart needed) | missing in contract v1; bus `NOTIPOST` exists (`notify.fi`) |
| clipboard file list (uri-list) | explorer copy/paste | missing: `svcosum.copy_text` is text only, 16 KiB |
| confirm with custom buttons / progress | explorer delete + replace dialogs | `message` has kind/buttons, no progress |
| picker: multi-select, mime accept | explorer "Open with", attachments | dialogd gap 1 |
| async host events | all long calls | calls are synchronous today (gap 4 in services-orientos.md) |
| open-with / launch by type | explorer, svcedit | handlers.conf exists, no service call |

## Order, small to large

1. **notepad** (this branch): list + editor, storage and confirm through svcosum, gate `tools/notepad`. Proves store + confirm in a multi-document app.
2. **store key listing** (`svcosum.store_keys`, queue reply): removes the index workaround in notepad; small, host test + guest check in `servicesguest`.
3. **svcedit replaces nedit**: file association (handlers.conf) opens svcedit, Ctrl+F/Replace parity, then delete `nedit.fi`.
4. **settings adopts services**: confirm through `svcosum.confirm` for destructive resets, last page via `store`; finish the 3 `wlibc` files (wlibc step 12 branch).
5. **notify call** (`svcosum.notify` over `NOTIPOST`, contract v2 item with Firn), then explorer progress + done toasts.
6. **explorer adopts services**: confirm/replace dialogs through `svcosum`, clipboard file list type, view state in store; picker model shared with `dlgdir`.
7. **terminal**: kernel tty window stays; revisit when the fUi terminal widget (M10, `pty/vt`) is available. Needs coordination with the fUi project (dispatch only when that widget starts).

## Rules for every step

- Only shared components and palette roles (`uikit/uisurface`, `fuiscene` widgets); no colour literals; ratchets `tools/uicheck/ratchet.py`, `tools/palette/ratchet.py` must not grow.
- One gate per app: guest script, serial checks, scale 1 + 2, two mutants that must turn red.
- App code only talks to `services.svcosum` (never `libc.io` for user documents).

## notepad design

- Storage: app folder `/data/notepad/services/`: key `note-<id>` (UTF-8 text, max 64 KiB, max 32 notes shown); the list comes from `store_keys`, a blank unsaved note is not persisted.
- Keys: Ctrl+N new, Ctrl+S save, Ctrl+D delete (confirm dialog via `dialogd`); switching notes and creating a note autosave a modified note.
- Serial events (`notepad: ...`): `ready rows=`, `state`, `saved id= status= len= title=`, `new`, `select`, `delete status= answer= rows=`, `shortcut`.

## explorer over services (M9-6 plan, sizes small to large)

1. View state in the store: `explorer/expview.fi` keeps `view` (sort key, direction, view mode, last folder) through `svcosum.store_get/store_set`; `svcosum.set_app` before the first call. Gate: guest run, change sort, reopen, same state; mutant without store write turns red.
2. Delete confirm through `svcosum.confirm` (blocking, dialogd) instead of `fuiscene.dialog_open` in `expwork.fi` line ~1910; keep the in-scene dialog as the `NO_BACKEND` fallback. Needs the explorer2/3/4 gates for the old path.
3. Clipboard file list (uri-list) in `svcosum` plus `xfer`, then copy/paste between explorer windows.
4. Picker mode: `dlgdir.fi` and explorer share one directory model; `explorer --pick` replaces the dialogd-only list.
Each step: palette and uicheck ratchets must not grow; explorer2, explorer3, explorer4, explctx gates stay green.
