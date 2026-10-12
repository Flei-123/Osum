# fUi grid / list geometry (`lib/fui/grid.fi`)

`import fui.grid` -- integer arithmetic for a tile grid or a list, no widgets, no heap.

| call | meaning |
|---|---|
| `grid_cols(avail_w, cell_w, gap)` | columns that fit (>= 1) |
| `grid_rows(n, cols)`, `grid_content_h(n, cols, cell_h, gap)` | rows / height of all rows |
| `grid_cell_x/y(i, cols, cell_*, gap)` | top-left of item i inside the grid |
| `grid_first(scroll_y, cols, cell_h, gap)`, `grid_count(n, first, view_h, scroll_y, cols, cell_h, gap)` | VIRTUAL grid: build only the items in view |
| `grid_scroll_to(i, scroll_y, view_h, cols, cell_h, gap)` | smallest scroll change that shows item i |
| `grid_pages`, `grid_page_of`, `grid_page_first`, `grid_page_count` | PAGED grid (fixed items per page) |
| `grid_move(i, n, cols, dir)` | arrow key target (`GRID_LEFT/RIGHT/UP/DOWN`), i at an edge |

Users: `kernel/user/store.fi` (paged grid + arrow keys). Test: `bash tools/grid/run.sh` (host build, independent Python model,
walks items one by one; 11 checks over ~2000 cases). Progress bars already exist: `fuiscene.progress/progress_set`.
