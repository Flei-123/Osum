# Apps cleanup (16.10.2026, worker W5)

## Editor merge (done)
Before: two start menu entries for text editing -- "Editor" (`/bin/edit`, console program, opened in a terminal window)
and "Editor+" (`/bin/nedit`, windowed: tabs, line numbers, syntax colours).
Now: ONE entry **Editor** = `assets/apps/editor.osp` -> `/bin/nedit` (Notepad-like window). `assets/apps/nedit.osp` is gone.
* `/bin/edit` stays in the image as a command-line tool (repair a config without the desktop): `edit <file>` in a terminal.
* Explorer: double click on `.txt .md .log .conf .cfg .ini .json .csv .xml .html .css .js .py .fi .sh .c .h .toml .yaml .yml`
  starts `/bin/nedit <file>` (`is_text_file` in `kernel/user/explorer.fi`, next to the `.pdf` association).
  The kernel file-type table (`kernel/fs/ftype.fi`, used by `tools/k16`) still names `/bin/edit` for `.txt/.md/.log`; unchanged on purpose
  (k16 gate), the Explorer does not use it for opening.
* Locale key `editor.info` now belongs to the windowed Editor. Store: no separate "Editor+" entry.
* Gates: `tools/appsmerge/run.sh` (static, counter-proof on old main 2 ok / 7 fail), `tools/guieditor/run.sh` and
  `tools/term/editwin.sh` adapted, `tools/qa/dell_walk.py` has one Editor entry.

## PDF viewer: Certus or own viewer? (decision)
Checked `/root/certus-ui` (read only): Certus has no PDF reader (hits for "pdf" are only bidi tables, sha1 and docs).
**Decision: the own viewer `/bin/pdfview` stays** (`kernel/user/pdfview.fi`, `docs/PDFVIEW.md`): own parser, zoom, fit width/page,
page navigation, search with highlighting, panning. The Explorer already opens `.pdf` with it.
Open (roadmap): Edge-like single toolbar (open / page n of N / zoom / search in one row), page thumbnails side panel,
Ctrl+F / Ctrl+scroll zoom. Not done in this round: the layout change needs the 111-check PDF gates re-run on the Dell image.

## Other doubled / superfluous entries (list, not removed)
* **Widgets** (`widgets.osp` -> `widgetdemo`): developer demo of all controls, in the start menu of the daily image. Used as test
  target by many gates (systembus, icons, hidpunkte, dell_walk) -> hide from the menu (`versteckt`), keep the program.
* **Search** (`launcher.osp`): is the Win-key start menu itself; an app entry for it is redundant.
* **Install OrientOS** (`installer.osp`): only useful on the stick; hide on an installed disk.
* **Welcome** (`welcome.osp`): first-run page; reachable from Settings instead of a permanent start menu entry.
* Mixed languages in names: "Programme", "PDF-Betrachter", "Papierkorb", "Willkommen" are German, the rest English
  (W3 design audit: choose one, locale keys `*.name`).
* Console helpers `term`, `termfull`, `dualcli`, `locate`, `netview` are programs, not menu apps -- fine.
