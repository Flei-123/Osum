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

## The rest of the layout (r387, 06.10.2026) -- also off by default

| key | what |
|---|---|
| `taskview=1` | a task view button (icon `icons.TASKVIEW`, two overlapping windows) between the start button and the first pin. A click opens a card in the middle of the screen with one button per open window (title); a click on a button puts that window in front (and brings it back from the bar if it was minimised), Escape or a click outside closes the card. Code: `kernel/user/taskview.fi`, window 4 of the bar's scene host -- only the bar may list and raise other programs' windows (`WM_LIST` / `WM_ACT` need a window on layer L_TOP), so it cannot be a program of its own. |
| `tray_chevron=1` | a chevron (up) as the leftmost thing of the tray. Click: opens the tray (down): the sound field shows its percentage again and the widgets of extensions come back; closed, they sit behind the chevron. |
| `tray_group=1` | network, sound and battery as ONE capsule: no gap between the three fields, one plate behind them, a click anywhere on it opens the quick settings. While the tray is closed, network and sound are icons only (network always was; the sound field loses its percentage); the battery keeps its percentage. |
| `badges=N` | a count (accent disc, top right of the pin) on a pinned program that has N or more windows open; `badges=2` is the usual value, `badges=1` shows it for every running pin. 0 = off. |

Serial lines for the runners: `taskbar: taskview x= y= w= h=`, `taskbar: chevron x= y= w= h= open=`,
`taskbar: group x= w=`, `taskbar: badge txt= n= x= y= w= h=`, and `taskview: open n= x= y= w= h=`,
`taskview: row <i> id= title=`, `taskview: raise id= rc=`, `taskview: shut <why>`.

Found on the way and fixed:

* **The conf buffer was 256 octets.** The reader stopped at 255, so the pins line of a bar with
  four or more pins (the last line of the file) was cut off or lost; the writer built the file in the
  same 256 octets and ran over their end once all the keys and ten pins were there. Now 1024.
* **Settings threw the keys away.** Its writer (`tb_write`) wrote its six keys and nothing else: one
  change of the edge or the height in Settings removed the pins, labels, clock keys, language field and
  every key of this layout. `tb_keep` copies the lines of the old file whose key Settings does not own.
* **`hide_missing` was not written** by the bar's own writer (a drag of the bar dropped it).
* `conf_write` writes its keys through two helpers (`wk_num`, `wk_txt`); the twenty copies of four
  statements cost 2 kilooctets of the 8 the task bar has below the format-2 file limit
  (`tools/progsize` now watches the bar too).

Test: `tools/win11bar/run.sh` (A-C as before; D: positions of the new things and the counter-proof that the
default conf has none of them; E: a click on the pin starts the program and the count appears, a click on the
chevron opens the tray, a click on the task view button opens the card; F: photos -- the count in the picture,
the card in the picture). Photos: `docs/shots/win11bar/{tray,badge,taskview}.png`.

Still not done: the Wi-Fi glyph (there is no Wi-Fi driver, r21), the keyboard glyph and the sync glyph of the
reference, the notification count of an application on its pin (the count is the number of windows).
