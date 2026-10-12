# FUI-CONTROLS — the standard controls of the scene toolkit (`kernel/user/fuiscene.fi`)

Every program that builds its window with `fuiscene` gets these. Colours come from the roles
(`R_TEXT`, `R_ACCENT`, `R_FIELD`, `R_BORDER`, ...) = the system theme, so light/dark/accent follow
automatically. Radii and spacing: see `docs/DESIGN-TOKENS.md` (`lib/fui/tokens.fi`).
`fuiscene.pump()` returns the key of the control that was used (0 = nothing); read the value with
`value_of(key)` / `entry_text(key)` / `table_sel(key)`.

| control | call | value | notes |
|---|---|---|---|
| search / text field | `entry(parent, key, w, buf)` + `entry_hint(key, p)` | `entry_text(key)`, `entry_set(key, p)` | caret, selection, clipboard by the host; the hint shows while empty; Ctrl+F style focus: `focus(key)` |
| list / table | `table(parent, key, w, h, cols, head, ...)`, `table_set_rows`, `table_sel` | selected row | rows, heads, multi-select, hover, drop (see the `table_*` functions) |
| check box | `check(parent, text, key, on)` | `value_of(key)` 0/1 | |
| toggle switch | `toggle(parent, text, key, on)` | `value_of(key)` 0/1 | same widget as `check`; pill track + knob, label left |
| segmented control | `segmented(parent, key0, names, stride, n, sel, w)` | program keeps `i`; `pump()` returns `key0 + i` | n = 2..8 segments, `names + i * stride` = NUL-terminated label, `w` = width of one segment; the chosen one is accent-filled, text `R_ONFILL`; Tab / Space / Enter / click, screen reader name = label. Rebuild with the new `sel` after a change |
| slider | `slider(parent, key, w, init)` + `slider_readout(key, lo, hi, pct)` | `value_of(key)` 0..1000 | the number right of the track is the one the handle shows, also while dragging |
| drop-down | `choice(parent, text, key)` | `value_of(key)` | |
| progress | `progress(parent, w, pct)`, `progress_set` | | |
| tile with own picture | `ftile`, `tile` | | callback paints; one callback slot per program |

Test: `tools/settingsui/run.sh` drives the Settings window (search field, list of pages, toggles,
segments, swatches) and checks the reported rectangles of each control.
