# SNIP -- screenshot tool (L-008 / r762)

Program: `kernel/user/snip.fi` (`/bin/snip`). Gate: `tools/snip/run.sh`.

| Want | How |
|---|---|
| Whole screen -> file + clipboard | `Print` key (taskbar runs `snip -q`) |
| Region picker | `Win+Shift+S` (taskbar runs `snip -r`): frozen picture, drag a rectangle, `Sichern` |
| Window / full screen / delay | GUI buttons `Fenster`, `Vollbild`, delay chooser; CLI `-a fenster`, `-v <sec>` |
| Exact region, no GUI | `snip -g x y w h -o file.png` |
| Editor | `Ausschnitt` (crop), `Rechteck`, `Pfeil`, `Stift`, `Marker`, `Verpixeln` |

Files: `/bilder/Screenshots/Screenshot-N.png` (PNG via `kernel/user/image.fi` png_write, stored deflate).

Clipboard: the bus gets type `BT_IMAGE|BT_TEXT`; payload = `bild:<path>` (the clipboard holds 4 KiB, a PNG does not fit).
A real pixel clipboard needs a bigger bus slot (open).

Print key: `kbd.fi` latches E0 37 as HK_KEY=336; taskbar `hotkey_step` reads it like Super+letter.

Open: freeform select, free-hand pen (the pen draws a line between the selection corners), true dimmed overlay window.
