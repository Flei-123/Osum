# The taskbar in the layout of Windows 11 (r316 stage 0, r385)

Reference: `assets/ref/` (Justin's picture of the Windows 11 bar: start button
and pinned apps in the middle with a small strip under the running program,
language `DEU` over `DE`, the clock with time over date and a four-digit year).

Everything is switched by `/etc/taskbar.conf` and OFF by default, so no
existing bar moves:

| key | value | what |
|---|---|---|
| `align=center` | already there | start button and pins in the middle |
| `labels=never` | already there | symbol only, no text on the buttons |
| `clock_lines=2`, `clock_date=1` | already there | time over date |
| `clock_year4=1` | new | `06.10.2026` instead of `06.10.26` |
| `tray_language=1` | new | the sixth status field: `DEU` over `DE` from the interface language (`msg.lang`) |
| `pins=a,b,c,...` | up to 10 now (was 6) | pinned apps |

The writer of the file (`conf_write`) now keeps the keys that are not about the
edge (labels, clock, language); before, a change of the edge in Settings dropped
them and a Windows-11-style bar went back to the defaults.

Not yet (the rest of r381): task-view button, tray chevron, badge counts on the
pins, Wi-Fi/volume glyph row, 60 % battery text (the VM has no battery and
`hide_missing` removes the field). The bar is still the ring-3 program
`taskbar.fi`; r381 puts its rectangles on the scene tree.

Test: `tools/win11bar/run.sh` (11/0): pins centred, no label, language field
present with `DEU`/`DE`, clock two lines with four-digit year, the strip under
the running program in the photo (`docs/shots/win11bar/desktop.png`); the
counter-proof builds the same with the default conf: no language field, one
line clock, two-digit year.
