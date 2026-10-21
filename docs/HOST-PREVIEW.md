# HOST-PREVIEW — see a fUi window without booting a guest (TOOLKIT-PLAN T3, r1326)

Slice 1 (21.10.2026). Gate: `bash tools/preview/run.sh` (19 checks, ~10 s, no VM, no kernel change).

## What it is
- `tools/preview/axpng.py` renders an **a11y.tree dump** (`act call a11y.tree window=<title>`, axd.fi `line()`)
  to a PNG on the host. The tree is what a screen reader gets: role, place, size, state, name, bus action, value.
- It is a **wireframe**: places/sizes/roles/names/states are exact (they come from the tree); colours and the font
  are an approximation of the theme (light/dark, `--dark`). Not pixel truth. Final look = guest screenshot.
- `tools/preview/watch.sh <prog>` = save loop: on every save of `kernel/user/<prog>.fi` (or of the dump file) it
  compiles with `tools/sync/build.sh` (scenedemo 8.4 s, MEASURED) and re-renders. A compile error is printed, the loop goes on.

## Use
```
# 1. get a dump once (guest, bus up):  act call a11y.tree window=Szenenbaum   -> save the node lines to a file
#    (a whole serial log works too: other lines are ignored; the LAST dump of the window wins)
python3 tools/preview/axpng.py dump.txt --list                 # windows in the dump
python3 tools/preview/axpng.py dump.txt --window Szenen -o a.png [--dark] [--scale 2]
python3 tools/preview/axpng.py dump.txt --window Szenen --json  # parsed nodes (for checks)
bash tools/preview/watch.sh scenedemo --dump dump.txt --window Szenen --out /tmp/p.png   # loop
bash tools/preview/watch.sh scenedemo --once ...                 # one round, exit 1 on red
```
- Hand-edit the dump (move a node, change a name) to try a layout; the picture follows the tree.
- Fixture: `tests/preview/scenedemo.tree` = real output of `tools/a11y/scene.sh` (5 window dumps incl. a two-window program).
- Roles drawn: button, check, entry, password (dots), tab (selected = accent bar), list/table, choice, slider, menubar,
  separator, scrollbar, label; other roles as outlined box. Hidden nodes are skipped; nodes outside the window rect are drawn (finding).

## Gate (tools/preview/run.sh)
1 parse (5 dumps, roles/rects/flags/act/name, windows kept apart) · 2 pixel checks at tree coordinates (button face,
entry fill + text, tab accent bar, dark theme) · 3 counter-proofs (moved button, removed node, unknown window -> exit 1,
different PNG) · 4 `watch.sh --once` builds scenedemo and leaves a PNG; a broken source copy (`USRC=`) -> `BUILD FAIL`, exit 1.

## Limits / next
- Needs one guest dump per program (the program itself does not run on the host: Ring-3 ELF with the Osum syscall ABI).
- Not a scene description: no layout engine on the host. A real host runner (fuiscene compiled for a host target with a
  software painter) is the 2-3 week item of TOOLKIT-PLAN 4.5; this slice covers "see + diff the tree" now.
- Next: `osdk run` (push + restart + shot) can feed `watch.sh --dump` from the guest tree after each push.
