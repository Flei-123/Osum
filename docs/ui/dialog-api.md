# Dialog API (system dialogs and popup menus)

One data-driven API for every question the system asks a person. Modules: `kernel/user/dialog.fi`, `kernel/user/consent.fi`, `kernel/user/trusttext.fi` (message text registries), `kernel/user/menu.fi` (popup menus), CLI `/bin/msgbox`.

## Where each dialog lives
| Kind | API | Drawn by | Answers to |
|---|---|---|---|
| System message / question | `dialog.show_message`, `show_warning`, `show_error`, `confirm`, `show` | window server (`WM_TRUST`, above all windows) | real keyboard/mouse only |
| Consent for an action (admin start, install, critical setting) | `dialog.consent_ask` -> `consent.ask` | same dialog, text from the `trusttext` registries (REG, META, RIGHTS) | real keyboard/mouse only |
| App-local modal inside a window | `busy.alert/confirm`, `fuiscene.dialog_*` | the app (fUi scene) | the app |
| Popup menu inside a window | `menu.show/choose` (over `fuiscene.menu_open`) | the app | the app |

Rule: the system asks through `dialog`/`consent` (the Boss sees one look: UAC style, also for Task Manager admin start, installer, Store start via `/bin/elevate`, bus confirmations for Store install and critical Settings). Questions that only concern one window stay in that window.

## dialog.fi
```
dialog.show_message(title, text) -> answer
dialog.show_warning(title, text) -> answer
dialog.show_error(title, text) -> answer
dialog.confirm(title, text) -> bool            // default focus = No
dialog.show(kind, severity, title, text, details) -> answer
dialog.consent_ask(client, action, args, rights) -> answer
```
- `answer`: `ANSWER_YES` (1), `ANSWER_NO` (2), `ANSWER_NONE` (0: no window server, timeout 120 s, cancelled). A message box acknowledges with either 1 or 2.
- `kind`: `KIND_MESSAGE` (J/N both close), `KIND_CONFIRM` (J = yes, N / Esc = no, Enter on the default focus = no).
- Title line: `<product> - <severity prefix><title>`; panel width = 512 px x `uiscale` (reduced if the screen is too narrow).
- `severity`: `SEV_INFO`, `SEV_WARNING`, `SEV_ERROR`, `SEV_CRITICAL`; shown as a title prefix (Warnung:/Fehler:/Kritisch:, en: Warning:/Error:/Critical:).
- `details`: optional, first line = label, rest = lines behind the D key.
- Extension points: table `KINDS` (labels + hint, de/en) and `SEVERITIES` in `dialog.fi`; consent text in `trusttext.fi` (`REG`, `META`, `RIGHTS`).

## menu.fi
```
menu.show(x, y, w, items) -> bool     // items: lines separated by \n (max 24 rows)
menu.pick() -> index+1 | 0            // 0 = nothing picked
menu.choose(x, y, w, items) -> index+1 | 0   // blocking, pumps the scene
```

## /bin/msgbox
```
msgbox [-c] [-l info|warning|error|critical] [-d details] <title> <text>
msgbox --consent <client> <action> [args]
```
Serial line `msgbox: answer=y|n|0`. Exit code: 0 yes/acknowledged, 1 no, 2 usage, 3 no answer.

## Gate
`bash tools/dialog/run.sh [dir]`: German scale 1 and English scale 2; message, confirm (Enter = no, Y = yes), warning/error/critical, consent, wrong key keeps the window open; screenshots `<dir>/<cfg>/*.png`. Counter-proofs: identical dialogs give identical pixels (stable method), severities differ, no answer without a key press.

## Not covered
- No password/PIN field and no dimmed backdrop yet (Roadmap r2866).
- Typed-confirmation dialogs for destructive disk actions (`wunlock`, `diskact`) stay different on purpose.
