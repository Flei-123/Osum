# STATUS-DESIGN3 -- file manager, task manager, command bar, disk manager (07.10.2026)

Branch `design3`. Written when the round ended; the numbers are the acceptance runs' own.

## What changed

**Gallery parts in fUi (Firn `lib/fui`, branch `fui-navkit`, mirrored in `lib/fui` here until the pin moves)**

* `navnum.fi` (integers only, works in a kernel-profile program): `size_text` ("354 B", "1.2 KB"), `mid_base`
  (the baseline that puts text on the centre line), `row_indent`, `thumb_len/off`, `heat_alpha`, `graph_y`,
  `sample_x`/`lerp_at` (a history curve that lands exactly on its samples).
* `navkit.fi` (painter): `paint_thumb` (a thin overlay scroll bar), `paint_heat`, `paint_graph` (curve + area +
  grid), `paint_bar`.
* `cmdbar.fi` (integers): the model of the icon command bar -- how many commands fit, where the groups part, the
  tooltip text "Copy (Ctrl+C)".
* Tests: `tests/1930_fui_navkit.fi`, `tests/1931_fui_cmdbar.fi`.

**The host (`kernel/user/fuiscene.fi`)** got, for every program: group headings and indentation in lists, right-aligned
columns, ellipsis for a cell that is too long, a hover plate, thin overlay scroll bars, tooltips (450 ms, with the
accessibility name set to the same text), the command bar (`cmd_begin/item/end`, overflow menu), `cv_graph`.

**File manager** -- one row above the list (two while there are two tabs): back / forward / up / refresh, the way as
crumbs with chevrons, a search field that filters while typing, then the commands as icons (new folder, cut, copy,
paste, rename, delete | view, more) with an overflow "..." when the window is narrow. The left side is ONE pane:
Quick access, This computer (Start, Trash, Network, Disk management), Volumes, and the folder tree of where you are.
The list has Name | Date modified | Type | Size (right-aligned, "1.2 KB"); rights moved to the properties dialog.
Rows are 32 points, the status line says "3 selected (12 KB)".

**Task manager** -- a sidebar of four pages: Processes (cards, list with heat cells, sums in the column heads, a
symbol per kind of process), Performance (CPU / memory / disk / network, each with a history curve, values, the cores
or the biggest programs), Startup (the services of /etc/inittab and whether they run), Details (one process).

**Editor (nedit)** -- the menu bar and the path row became one icon row (new, open, save | undo, redo | cut, copy,
paste | search | file menu) plus the path.

**Disk manager, reading only** (`docs/DISKS.md` stage D-0 / D-1): `lib/disks/table.fi` (MBR, GPT, protective MBR,
CRC32 checked), `/bin/diskctl list`, `/bin/disks` (a window: disks at the left, a map of the partitions, the list),
the file manager's "Disk management" entry opens it. Tests: `tools/disks/run.sh`.

## Not done (and why)

* Tabs in the title bar: needs the window decoration as a fUi scene tree (`docs/COMPOSITOR.md`, stages C-S1..).
* The editor's second row of replace / go-to commands (they are in the file menu behind the last icon).
* "This computer" as a view with occupancy bars (D-1 has the window; the file manager only opens it).
* Shrinking, growing, moving partitions: no stage after D-1 exists yet (`docs/DISKS.md` section 3).

## Measured

See the commit messages and `tools/midline/run.sh`, `tools/disks/run.sh`, `tools/toolbench/run.sh`.
