# Dell, 04.10.2026 (evening): four window bugs

Image 518422a on Justin's Dell (i-series, one core reported, 9 GB RAM). Justin's list:

1. After several programs are open, no further one can be opened.
2. The title text sits closer to the top edge of the title bar than to the bottom edge.
3. A window pushed a little over the screen edge jumps right back.
4. The resize cursor shows at the right and bottom edge, not at the top and left (and corners).

## Bridge state when this was written

The Dell answered the bridge (`system`: 26 live tasks, uptime 20 min, `fork failed` for every
`befehl`). Screenshots, clicks and typing need a permit that only the person at the machine can
issue (`jarvisctl screenshot`, `jarvisctl eingabe`) -- and `jarvisctl` is a program, so it needs
a free task slot too. With the old image the Dell could not be steered. Everything below was
reproduced and measured in a VM with the Dell's own image (and with the stick machine
`tools/design/eh6.sh`), never on the Dell itself.

## 1. No further program (cause: corpses keep their task slot)

* The task table has `MAX_TASKS = 32` slots, slot 0 never given out. The system itself holds
  about 18 of them (boot, one idle task per core, `orientbus settingsd stored axd ota sntp
  taskbar starter jarvisd sh desktop` ...). The Dell showed `aufgaben 26` (live) and every `fork`
  failed: the other slots were corpses.
* A program that ends stays in its slot as a corpse until its creator calls `wait4`. Nobody does:
  the start menu, the taskbar and the file manager start programs with `SYS_EXEC` and never
  wait; the boot task (parent of the login screen and `dhcp`) never waits. VM, Dell image:
  `kill` of three programs started from the menu -> three corpses (`ps`: `zombie`), plus the
  login screen and `dhcp` from boot.
* Fix (`kgui.zombie_wache`, every 16th round of the desktop loop): a corpse is taken away when
  (1) its parent is the boot task, (2) its parent is gone or a corpse, (3) its parent ignores
  `SIGCHLD` (POSIX auto-reap; `ulib.ignore_children()`, called by the start menu and the
  taskbar), (4) nobody picked it up for 3000 ticks (safety net). A parent that waits normally
  (the shell, settings) is not touched before rule 4. Living children of a reaped corpse fall
  to the boot task (their parent slot would be given to a stranger otherwise).
* Limit, measured with the Dell image in a VM (4 cores, no network): the FIRST limit is not the
  task table but the **window table**: `MAX_WIN` was 16. The system itself holds five windows
  (desktop, panel, quick settings, start menu, terminal); after nine more windows (nine file
  managers) the sixteenth slot (`wm: fen i=15`) was taken and no further program got a window;
  the taskbar showed ten buttons (`MAXK = 10`). Now `MAX_WIN = 32` (the window table fills the four
  pages it always had; the event rings moved to their own four pages `kstate.EVR_OFF = 0x10C000`, a hole of
  the map between the extension pages and the suspend pages. NOT 0x144000: those pages are assigned in
  `kstate.fi` to pending branches -- a first try there booted into `#UD` in two of four stick-machine runs) and the taskbar shows up to 16
  window buttons. The task table is the second limit: 31 usable slots, the system holds ~18 of
  them (4 cores) -- about 13 programs at the same time, ~17 on a one-core Dell. Raising
  `MAX_TASKS` is NOT done: ten per-task tables (capabilities, signals, descriptors, handles,
  async queues, accessibility rights, groups, contexts ...) are sized for 32 in `kstate.fi`;
  roadmap item.
* Clear message: `elf.R_NOSLOT` (task table full -> `-EAGAIN`, serial `elf: refused, reason
  30  task table full (limit reached)`) instead of `R_NOMEM`; the start menu keeps itself open
  and shows a dialog "Too many programs ... Close one and try again." (`launcher.full.*`).
* Test: `tools/zreap/run.sh` (stick machine): start the file manager from the menu, kill it from
  the terminal, 34 times (more than the free slots). Counter-proof: kernel word `nozreap`.

## 2. Title text not centred

Baseline was `border + ascent`: the line box started at the top of the bar and all spare height
ended below the text. First try (centre ascent + descent) still left 3 px above / 5 px below on
the pictures, because titles are mostly ascenders. Now the ink (a tall letter, 4/5 of the font
size, 12 rows at 15 px) is centred between the border and the bottom of the bar, descenders kept
inside (`wm.title_base`); same formula at every ui scale. Counter-proof: `nowinfix`.

## 3. A window may stick out

`drag_klemmen` kept the whole window on the work area at release. Now it may stick out left,
right and bottom; it only has to keep a handle: the title bar stays in the work area vertically,
at least 96 px (times ui scale) stay in sight horizontally. The snap strip at the screen edge was
16 px; now 2 px (times scale), the pointer must be AT the edge. The server writes `wm: abgelegt
id= x= y=` after every drop. Counter-proof: `nowinfix`.

## 4. Resize cursor at all eight grips

The grips themselves worked since ECHTHARDWARE-5, but the cursor (`margin_cursor`) knew only
right, bottom and their corner. Now press and cursor use ONE rule (`grip_mask`): left/right
`8 px * scale`, top `border + 3 px` (was +2), bottom `8 px`; arrows: horizontal, vertical,
NW-SE, NE-SW. A maximised window has no grips. A resize now follows the pointer at the distance
it was grabbed (before, the top edge was set to the pointer as the top of the CONTENT, 22 px
below the edge: a 30 px drag moved the window top by 8). `wm: form= x= y=` and `wm: gezogen
id= x= y= w= h=` are on the serial line.

## Test

`tools/fourbugs/run.sh [uiscale]` (stick machine; `tools/fourbugs/check.py` reads the serial
line and the pictures): cursor shape at the eight grips against the grip rule, eight resizes
with exact end positions, three drops (stick out right / bottom clamp / top-left clamp), title
gaps above and below within 1 px. Run twice: fixes on, and `nowinfix` (old behaviour), which
must fail several checks.
