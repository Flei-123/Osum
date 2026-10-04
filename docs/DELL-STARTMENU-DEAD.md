# Dell 9020: the start menu is a dead picture (04.10.2026)

Image a6dd7fa, real hardware, USB keyboard + mouse. Justin's photo, 13:30: the start menu is open
("Programm suchen:"), the highlight sticks on "Editor" while the pointer is on "Datei-Explorer",
nothing can be clicked, nothing can be typed, the taskbar says `CPU 100%`, the terminal behind
still shows the boot-time `fetch: ... sha256` lines.

## What the Dell said (read over the bridge, read-only, 14:17)

    (ticks are 1/100 s; uptime 10 832 s = ~1 083 000 ticks per core)
    ps:  24 zombie starter    1845 ticks      <- the start menu's process is DEAD after 18 s of CPU
         56 zombie lock     755922 ticks      <- an earlier lock screen: 2.1 HOURS of CPU
        129 run    lock     237308 ticks      <- the lock screen NOW: 40 min of CPU, still burning
         1 ready boot       133449 ticks      <- the kernel desktop loop; core 0's idle task: 0 ticks
    screen: the lock screen (idle lock after 300 s), the Dell is locked right now.
    => core 0 was ~92 % lock screen: the taskbar's "CPU 100 %" is the lock screen's spin.

## Causes (each one reproduced in a VM with the Dell's own image)

1. **A process that ends leaves its windows behind.** `SYS_EXIT` closes files and sockets, nothing
   closes windows. The launcher ("starter", started hidden) ends -- the Dell shows 1845 ticks =
   ~18 s of CPU: it loops in `wlib.step`, which only yields when idle (~4.5 us per round), and every
   fUi program had a limit of 4 000 000 rounds. Its window stays. Super toggles that picture; every
   key and click goes into a window nobody serves. (VM: `kill <pid of starter>`, Super, type "te":
   the field stays empty -- exactly the photo.)
2. **Idle programs burn a core.** `wlib.step` yields and comes straight back when nothing else is
   ready. Hidden launcher: 92 % of a core (measured, eh6 machine); the lock screen the same, for as
   long as the screen is locked (Dell: 2.1 h of CPU in one lock).
3. **The kernel desktop loop spins on core 0.** (VM, Dell image: the boot task holds ~97 % of core 0
   in 30 s with nothing on the screen; on the Dell it is ~12 % next to the lock screen.)
   `sleep_ticks(1)` hands the core straight back (~8 rounds per tick), the core's idle task never
   runs. The taskbar's "CPU" reads core 0 only.

## Fixes (branch dell-launcher-dead)

* `kgui.fenster_wache`: every round, a window whose owner task is a corpse (or gone) is destroyed
  (not while the lock stands). The next Super/Start finds no window and starts a fresh launcher.
  Counter-proof: kernel word `nowinsweep`.
* `wlib.step`: after 200 quiet rounds in a row it sleeps one tick per round, for programs that ask
  (`fuiapp.next` asks: launcher, lock screen, settings, file manager ...). Demo programs and tests
  that count rounds keep the spin (k15 relies on `widgetdemo` ending by its round limit).
  The round limits of launcher/settings/installer/storage/pdfview/store are gone.
* `sched.idle_wait`: the desktop loop waits for the next interrupt (`sti; hlt`) instead of
  spinning; the ticks that fall into the wait are booked to the core's idle task (`ps` and the
  taskbar gauge both see an idle core). Counter-proof: kernel word `nohltidle`.

## Test

`tools/menualive/run.sh` (the stick's machine, `tools/design/eh6.sh`): hidden launcher < 10 % of a
core, desktop loop < 15 %, kill the launcher from the terminal -> window swept -> Super -> type
"file" + Enter starts the file manager; counter-proof with `nowinsweep nohltidle` (dead menu,
loop at 90 %+).

## Not shipped by the OTA feed

The feed carries the 14 packages of `tools/loader/apps.tab`. Kernel, launcher, taskbar and `wlib`
are part of the image: this fix reaches the Dell as a new image (stick, or `dell-update.py` over the
bridge with the old version kept as "Previous version"), not as a feed stand.
