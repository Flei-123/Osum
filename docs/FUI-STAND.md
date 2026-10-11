# FUI-STAND — what runs on fUi's scene tree and what does not

Measured 11.10.2026 on main d22dbc46 with `python3 tools/fui/share.py` (new; counts `kernel/user/*.fi`, only files that open a window).
Scene tree = the window is built with `fuiscene.open*` (fUi layout, widgets, focus, a11y by the host).

| part | file(s) | lines | scene tree | missing for 100 % |
|---|---|---|---|---|
| sign-in screen | glogin | 1 488 | yes (7 ghost nodes) | - |
| lock screen | lock | 644 | yes (7 ghost nodes) | - |
| task bar | taskbar | 8 263 | PARTIAL: tree-building functions 418 lines; 1 238 lines in `paint*`, own layout/click/hover/drag | its own layout + painting + hit testing into flex nodes (docs/FUI-ALL.md section 11: not started) |
| start menu | launcher | 2 121 | yes (5 ghost nodes) | - |
| file manager | explorer | 5 381 | yes | - |
| settings | settings | 7 968 | yes (1 own paint function) | - |
| installer | installer | 2 181 | yes | - |
| store | store | 597 | yes (backends bstore 2 074 / stored 918 have no window) | - |
| task manager | taskmgr (+taskview) | 2 630 | yes (5 ghost nodes, 1 own paint function: graphs) | graphs as nodes |
| snip (screenshot tool; no separate paint program) | snip | 763 | yes | - |
| PDF viewer | pdfview | 811 | yes | - |
| text viewer / editor | viewer, nedit (+fuied 1 996) | 2 462 | yes | - |
| quick settings | qs | 1 707 | yes, but 14 direct `wlibc` primitive calls + 3 `painter.` calls (own tiles) | tiles as nodes |
| tooltip + toast | barpop | 253 | yes | - |
| popups of fUi programs (context menu, dialog, tooltip inside a program) | fuiscene.fi `pop_paint`/`dlg_paint`/`tip_paint` | 99 | painted by the host itself (not nodes) | nodes in the tree |
| desktop | desktop | 1 141 | NO: own painting, no `fuiscene` call | scene program with icon nodes |
| calculator | calc | 1 261 | yes | - |
| small (netmon, powermon, storage, disks, friends, trash, certus, demos) | 12 files | 7 596 | yes | - |
| widget demo (K15 anchor) | widgetdemo | 502 | NO: wlib widget list | K15 acceptance moves to a scene equivalent |
| terminal | kernel/ui/wm.fi (text grid, `cell_paint`) | part of 17 549 | NO: kernel text grid; draws NO cursor at all (`CSI ?25` is dropped) | ring-3 terminal or kernel cursor (see roadmap) |
| window frame, title bar, buttons | kernel/ui/wm.fi (`fb.*` fills; wmd shadow compositor in ring 3 for part) | in 17 549 | NO | docs/COMPOSITOR.md S6 |

**Share (tools/fui/share.py): 38 281 of 47 769 lines of GUI programs = 80.1 %** (before: 79 % on 05.10.). The task bar counts only its tree-building
functions; wm.fi, wlib (12 903 lines, the layer under every program), fuiscene.fi (7 285) and the helper files are not counted.
Windows by number: all but task bar (partial), desktop and widgetdemo are scene trees.

## Text fields and the caret
Every text field of every scene program (sign-in, lock, start-menu search, explorer rename, settings, installer, pdfview, calc) is one fUi
`KIND_TEXTBOX` drawn by `fuiapp.field_paint`; the memo of `fuied` has its own caret code. The blink is in the host (`fuiscene.pump`, 500 ms).
The terminal is NOT a fUi field: the kernel text grid draws no caret.
