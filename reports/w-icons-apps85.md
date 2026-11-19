# w-icons-apps85: icons for all programs + program inventory

## Icons
- New SVG glyphs (lucide, same 24 grid, stroke 2.2, gradient tile style of `tools/svg/mkapps.py`): flame (Firefox), screen-share (Remote control host), cast (FreeViewer viewer), mail (Mail).
- `tools/svg/apps.tsv` rows added; `bash tools/svg/apps.sh firefox xremote fvviewer mail` baked symbol.svg + symbol.osym (72) + symbol44/64.
- Packages used a 16x16 `symbol.txt` -> now one helper `tools/k15/mksymbol.py <dir> <out>` (joined 72/44/64 from symbol.osym, falls back to symbol.txt). Used by `pakete/bauen.sh`, `tools/xremote/*.sh`, `tools/xfx/mkstore.py`, `tools/mail/app.sh`. Old symbol.txt of firefox, xremote, fvviewer, mail, jarvismini removed.
- `tools/iconaudit`: now covers every package with `datei=symbol` (also xremote, which has no `datei=start`): vector symbol.osym required + listed in apps.tsv. Counter-proof changed accordingly.

## Task manager names + icons
- Processes are named after /bin/<prog>, not after the bundle (xfx, freeviewer-host, runbox, snipt, vaultui) -> letter tile and raw name.
- `tools/appreg/alias.tsv` got those 5 rows; `tools/appreg/build.py` now emits registry entries for alias rows too and a `title` file (apps.tab titel or bundle INFO name=).
- `kernel/user/appreg.fi`: `title_of(id, out, cap)`. `kernel/user/taskmgr.fi`: per-process title cached next to the icon (`shown_name`), falls back to the raw process name.
- Result: xfx shows as "Firefox" with the flame, freeviewer-host as "Remote control" with its icon.

## Inventory (/apps bundles + loader packages)
| Program | Purpose | Duplicate? | Decision |
|---|---|---|---|
| explorer, settings, terminal, store, taskmgr, trashbin, charmap, vplay, pdfview, vault, certus, firefox | core apps | no | listed |
| calc (Rechner) | calculator | no | listed |
| installer | copy system from stick | stick only | listed, `hideif=/etc/installed` (exists) |
| editor / nedit | text editor | nedit.osp = same program as editor.osp | nedit hidden (exists), editor listed |
| launcher | start menu search itself | - | hidden (exists) |
| run | Win+R box | hotkey | hidden (exists) |
| snip | Win+Shift+S | hotkey | hidden (exists) |
| cliphist | Win+V | hotkey | hidden (exists) |
| lock | Win+L | hotkey | hidden (exists) |
| viewer | image viewer, opened by file | - | hidden (exists) |
| disks | read-only disk view | Settings storage | hidden (exists) |
| top (Prozesse) | process list, console | duplicate of Task Manager | hidden (exists) |
| netmon (Netzmonitor), netview (Netzsicht) | net throughput / per-app net rights | overlap with each other + Task Manager | hidden (exists); merge into a tab = follow-up |
| themetest (Vorlagen), widgetdemo + widgets bundle | developer test programs | dev only | hidden (exists) |
| zip (Archive) | console zip | Explorer | hidden (exists) |
| **welcome** | first-run window | shown by first login | **now hidden**, still found by search |
| **osk** | on-screen keyboard | taskbar/tray toggle | **now hidden**, still found by search |
| xremote, fvviewer, mail, jarvismini | store packages | no | icons added |

- Nothing deleted: hidden = `menu=hidden` (bundles) or `hidden` column in apps.tab; search words still find them.
- Gate `tools/appsmenu/run.sh` pins this inventory (hidden vs listed) + registry alias titles/icons + counter-proof.

## Not done (needs a product decision or touches other workers' areas)
- Merging netmon/netview into Settings/Network or a Task Manager tab (real UI code).
- Dev switch that also removes dev programs from search; today they are only out of the program list.
