# The lock screen: what it is and what it seals (r382)

Question (Justin, 06.10.2026): is the lock screen a window of its own or an
overlay over the other windows? Can one get past it with Alt+Tab, a click,
window shortcuts? Are the windows behind it hidden (picture, a11y tree,
bridge)? Are there tests? Build what is missing.

## What it is

* **A screen-filling frameless scene-tree window** of the program `lock`
  (`kernel/user/lock.fi`, `fuiscene.open_plain(0, 0, w, h, ..., L_TOP, ...)`).
  The program only shows the password question and checks the password
  (`pw.check_hash`). It is NOT where the security sits ("Das ist KEINE
  Sicherheit", head of lock.fi).
* **The lock itself is the kernel's**: `kstate SP_ON` (switched by
  `osum_sperre` op 1, Win+L in `drv/hid/kbd.fi`, lid, standby, logout) and
  `SP_PID`/`SP_SLOT` (who the locker is). The window server decides with
  `wm.darf(i)` (`kernel/ui/wm.fi`): while locked, **only windows of the locker
  are painted** (`compose`), get keys (`on_key`), get pointer events
  (`on_mouse`), may be written (`fwin_target`), may be pressed through the
  a11y tree (`ax_press`, refuse 4). A crash locks, it never unlocks: the kernel
  restarts `/bin/lock` (`kgui.sperre_wache`).

So it is not an overlay: windows behind it are not drawn at all (the photo,
and with it the screenshot of the bridge, shows the lock screen only).

## What was open before r382 (found by reading the code, measured by the test)

| Way round | Before | Now |
|---|---|---|
| Alt+Tab (`tile_action A_NEXT_WIN`) | raised and focused a window behind the lock | dropped, line `wm: hot gesperrt` |
| close / snap / full screen shortcuts, `osum_tiledo` syscall | acted on the focused window behind the lock (it could be closed) | `tile_action` returns false while locked |
| plugin shortcuts (`wmplug.key_owner`) | plugin heard keys while locked | not while locked |
| a11y tree (`AX_READ`) with the read right (screen reader, bridge) | every node of every window behind the lock, with names | node of anyone but the locker reads as an empty node |
| a11y events (`AX_EVENT`) | focus/value events of windows behind the lock | dropped |
| window table (`WM_LIST`, `WM_FWIN FW_LIST`) | titles, sizes, owners of all windows | only the locker's |
| pointer shape over edges of a hidden window | showed the resize arrows | flat |
| drag/resize running when the lock came | went on moving a window | ended |
| **claim the lock: `osum_sperre` op 4** | any program could register as the locker while unlocked (then owned the next lock) or after the locker died (then unlock with op 2, no password) | only the program that switched the lock on (op 1) or the one the kernel started for it |

Still true and measured: the right password opens it, a wrong one does not, a
crash does not.

## Tests

`tools/lockseal/run.sh` (43/0; with the OLD kernel and the same programs:
27/0 passed, 15 failed -- the counter-proof, `KROOT=/root/fb-osum`):
a victim window with names (Save, Add note, Hello tree, Password ...), a
tiling table (Alt+Tab, Alt+Q close, F11), a root probe (`a11ydemo lockprobe`)
that reads the tree, events and window table, tries to be the locker and to
unlock, and calls the tiling syscall; the host sends Alt+Tab, Alt+Q, F11, F12,
Alt+F4, Ctrl+Alt+Del, Super+D, Super+Tab, Alt+Esc and clicks into the place of
the victim, and takes photos before the lock, at the lock and after the attacks.
`tools/lockscene` (15/0) keeps the password logic and the crash case.

Not covered and said so: the serial console and the QEMU monitor are the host's,
not the guest's.

## The locker is killed (r390, 06.10.2026) -- measured, and it was open

The first version of this document said the race "is closed by the op-4 rule but not
measured". Measured, it was not closed. `tools/lockrace/run.sh`: a root probe kills the
locker the kernel started itself (the zombie of a child of the kernel's guard is reaped
within ~16 turns, so its task slot is free again almost at once), then for two seconds
starts bursts of tiny `lockclaim` programs, each asking `osum_sperre` op 4 and, if that
worked, op 2, while it reads the window table all the time.

* **Old kernel:** a child that landed in the freed slot passed op 4 (slot equal, the old pid
  gone) and opened the lock with op 2 WITHOUT the password: `won=1 state=0`, and the
  victim window showed in the table 8 times (`tools/lockrace` 8 passed, 15 failed).
* **Why:** `SP_SLOT` / `SP_PID` named the dead locker until `kgui.sperre_wache` noticed (every
  32nd turn) and started a new one.
* **Fix:** `sched.lock_gone(state, task)`, called by `exit_task` and by the kill path of
  `uio.fi` under the same hold of `L_SCHED`: if the task is the one the lock names, `SP_PID`
  becomes 0 and `SP_SLOT` a slot no task can have (0xFFFF). The lock stays ON (nobody is
  allowed to draw: `wm.darf` is false without a locker), op 4 is refused for everyone, and the
  guard starts a new locker as before (its pid is 0).
* **Now:** `won=0`, `victim_seen=0`, the lock still on after the race, the lock screen is back
  within 7 s (the new locker is a big program loaded from the disk), the right password still
  opens it (`tools/lockrace` 23/0; `KROOT=<old tree>` is the counter-proof). `lockseal` 43/0 and
  `lockscene` 15/0 are unchanged.
* To reach the case the first locker (started by the shell, a child of `sh` whose zombie stays
  in the table) is killed once (`a11ydemo lockrace warm`); the race runs against the second
  one.

## The look (r383) and its measurements

Lock screen and sign-in screen use the Windows 11 layout on the blurred sea
wallpaper (`kernel/user/signin.fi`, `backdrop.fi`; the wallpaper is Justin's own
photo, default `/etc/wallpaper`). Round avatar, name, one line of status, the
password field with the eye and the accent-filled arrow, the user bottom left,
language / network / power bottom right.

* **Focus mark of the arrow:** fUi's own focus ring is the accent colour, which
  vanishes on the accent-filled arrow (found by `tools/loginui`: the Tab chain
  saw no ring on "Anmelden"). `fuiapp.halo_in` paints a white ring two points
  inside the face; `glogin.fi` and `lock.fi` call it when the tile has the focus.
* **`tools/loginui` (31/0):** the ring detector now reads the accent ring on
  plain tiles (on their edge: the neighbours touch) and the white ring in
  accent tiles; two rings at once or none = the picture was taken mid-repaint,
  so it is taken again (up to 4 times); the second eye click waits up to 6 s.
* **`tools/desktop`:** the image is built with `--v3` (/bin/settings has
  2 151 680 octets, over the 2 134 016 of format 2). The test is red on main
  for other reasons too (it still waits for the `battery`/`net` texts that the
  bar no longer paints without hardware): the same 18 failures on main
  830f3947 and on this branch.
