# The terminal window: what it understands (r462, 07.10.2026)

Justin's Dell photo of 07.10.2026 19:05 showed the console editor (`/bin/edit`) in a terminal window with its control sequences printed as
text (`~[19;1H[K`, `[7m`, `[24;1H[K^O Write`, `[?25h[?25l`) and a screen that overwrote itself.

## Two causes

1. **An image from before r400.** The VT subset (cursor addressing, erase, reverse video, `?25`) went into the kernel terminal on
   07.10.2026 09:42 (`3ec0436a`). A machine running an older build prints every sequence as characters. The photo shows exactly that.
2. **Nobody told the tty the size of its window.** `tty.set_winsize` was never called: `TIOCGWINSZ` answered the default 80 x 24, and
   `/bin/edit` drew a 24-row screen of 80 columns into a window of 56 columns x 20 rows. With the VT subset in place this still gave a
   broken screen: the help line wrapped, the status line and the help line landed on the same last row. Reproduced on current main with
   `tools/term/run.sh` (picture before: `docs/shots/term/before-*.png` in the commit of this round).

## What was changed

* `tty.do_ioctl(TIOCGWINSZ)`: a tty whose output goes to a terminal window answers with the **live size of that window's grid**
  (`wm.term_size`, through `gfx.wm_term_size`).
* `kgui.winch_wache`: every tick, a terminal window whose grid changed sends SIGWINCH to the foreground group of its tty.
* The escape machine (`kernel/ui/wm.fi`, `term_esc_take` / `term_csi`) is now a fuller VT100 / xterm subset with **per-window** state
  (a second terminal window no longer inherits half a sequence of the first):

  | group | sequences |
  |---|---|
  | cursor | `CSI n A B C D E F G d a e` `` ` `` `H f`, save / restore `ESC 7` `ESC 8` `CSI s` `CSI u`, `ESC D` `ESC E` `ESC M`, CR LF BS |
  | erase | `CSI J` (0 1 2 3), `CSI K` (0 1 2), `CSI n X` |
  | edit | `CSI n @` `P` `L` `M` `S` `T` |
  | region | `CSI t ; b r`: a line feed on the last row of the region scrolls only the region; a bad pair resets it |
  | attributes | `CSI m`: 0, 1, 4, 7, 22, 24, 27, 30-37, 40-47, 38 / 48 ; 5 ; n (the 16 first), 39, 49, 90-97, 100-107; `38 ; 2` is dropped |
  | modes | `CSI ? 1049 h / l` (alternate screen with the main screen saved), `?47`, `?1047`, `?7 h / l` (wrap); `?25`, `?1`, `?12`, `?2004` ... are accepted and dropped |
  | strings | `OSC` / `DCS` / `PM` / `APC` up to BEL or `ESC \` are swallowed |
  | everything else | swallowed up to its final octet; **an unknown sequence never shows up as characters** |

* The automatic wrap is deferred like on a real terminal (the 80th character of a row does not scroll the screen yet).
* The grid of a terminal window is six frames now: characters, attributes, colours, and the same three of the main screen while the
  alternate screen is up. Cells have 16 colours, underline, bold (bright), reverse.

## Tests

* `wm: vttest7 / 7` (old) and `wm: vttest2 32 / 32` (new, 32 cases in `wm.vt2_selftest`: every sequence above, deferred wrap, `?7 l`,
  the grid size) at boot; `tools/wm/run.sh` reads them.
* `tools/term/run.sh`: boots the desktop of the stick, starts `edit /etc/passwd` in the terminal window and reads the **cells** of the
  window (`wm: termzeile`): no sequence octet is text in any row, the help line stands on the last rows of the real window, no row is wider
  than the window; pictures in `docs/shots/term/`.
* `tools/k11` (the editor acceptance, screen against serial capture row by row) stays green.

## Not done

* Replies to status requests (`CSI 6n`, `CSI c`): the terminal does not write into the tty input.
* 256 colours beyond the first 16, true colour: dropped (the colour of the cell stays).
* Tab stops, insert mode (`CSI 4 h`), origin mode, double-width characters, the saved cursor of the alternate screen is one slot.
