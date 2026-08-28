# Round CUSTOMRES -- resolutions the list does not contain

*Osum, branch `customres`, off `mergeline` (adaa9c7). Every number in
this file comes from a run that is reproducible with
`bash tools/customres/run.sh` on QEMU 7.2.22 with `-accel kvm`. Where a
number would be different on real hardware, section 7 says so and says
why.*

The question this round answers, as it was asked: *"Kann man auch
benutzerdefinierte Auflösungen erstellen wie im NVIDIA-Control-Panel?"*

---

## 1. Why the answer was no

Round DISPLAY replaced two constants with a real probe. It asks the card
twenty-two times, keeps what the card accepts and what this kernel can
map, and offers the result as a list. That was the right thing to build
and it is not being undone here.

But the list is still a list, and its source is still a table in the
source code:

```
fn cand_count() -> u64 { return 22 }
fn cand(i: u64) -> u64 { if i == 0 { return (320 << 16) | 200 } ... }
```

1400x1050 is not in it. The card takes it -- measured below -- and the
kernel can map it. `set_mode(1400, 1050, 32)` nevertheless returned
`E_NOMODE`, because `set_mode` begins with `find_mode`, and `find_mode`
searches the list. **The filter, not the hardware, was the limit.**

That is exactly the gap the NVIDIA control panel fills with its "custom
resolution" page, and it is why the question was a good one.

---

## 2. What this round built

| file | what |
| --- | --- |
| `kernel/vmode.fi` (+550 lines) | `set_mode` split into `switch_to` + list lookup; `check_custom`/`set_custom` with three gates that each name their number; sorted insertion into the list; a `poll` guarded against a second reverter; nine assertions of its own |
| `kernel/dispsave.fi` (new, 320 lines) | `/system/BILDMODUS` -- a confirmed mode survives the reboot, and a trial counter takes it away again |
| `kernel/tasks.fi` | the idle task calls `vmode.poll` -- this is what makes the fifteen seconds actually elapse |
| `kernel/sys.fi` | `DS_CUSTOM`, `DS_CHECK`, `DS_SAVE`; `DS_CONFIRM` now also writes the file; `DG_CUSTWHY`/`DG_CUSTNUM` and the seven fields about the saved mode |
| `kernel/kmain.fi` | the words `dispeigen`, `dispeigenbad`, `dispeigenfrist`, the boot stage that applies the saved mode, and `disp: kacheln` |
| `kernel/user/dispctl.fi` | `eigen`, `pruefen`, `speichern`, `testc`, and the reason as a **sentence** |
| `kernel/user/einstellungen.fi` | three entry fields, two buttons, and the line that names the gate and the number |
| `tools/customres/run.sh` (new) | the acceptance run, nine sections |

No new syscall number. The round fits into the three that round DISPLAY
already owns (1810..1812); what grew is the field table behind them.

---

## 3. Three gates, and each one says its number

`check_custom` runs the same three gates `probe` runs on every candidate.
The difference is that it says which one bit, with the number that
decided.

```
0  taken
1  the card's registers did not accept the number   (num = what stayed)
2  does not fit in the card's video memory          (num = octets needed)
3  this kernel cannot map it                        (num = octets needed)
4  this kernel does not draw that colour depth      (num = the depth)
5  the numbers are outside what a screen is         (num = the offender)
6  there is no mode driver at all (`disp` is missing)
```

The numbers are the same ones `cand_why` uses, so one legend serves both.

### The order is different from `probe`'s, and that is measured

`probe` asks the card first, because it is enumerating and the card gives
the shortest answer. For a *single* user entry that is the worse order,
and here is the measurement that says so -- the same kernel, the same
command line, a card with 4 MiB:

```
disp: vram=4096 KiB  probed=22  refused=13  toobig=0  unmappable=0
disp: out   1280x1024  reason=1
disp: out   1920x1080  reason=1
disp: out   2560x1440  reason=1     ... thirteen of them, all reason 1
```

**Thirteen candidates rejected by "the registers", none by "too big for
the video memory" -- when the video memory is exactly what they are too
big for.** QEMU's register check contains its own memory check, so gate 1
always fires first and gate 2 is unreachable. A user reading "the
registers refused" learns nothing; a user reading "needs 9 216 000
octets, the card has 8 388 608" knows what to buy.

So `check_custom` computes what it can compute -- depth, video memory,
map limit -- and asks the card last. That costs nothing: the two
arithmetic gates are three multiplications.

### Measured, on the default card (16 MiB)

```
disp: eigen 1400x1050x 32  rc=0  why=0  num=5880000
      vram=16777216  maplimit=12582912  custom=1  panel=1400x1050  us=13897
disp: eigen 2560x1440x 32  rc=8  why=3  num=14745600
      vram=16777216  maplimit=12582912  custom=0  panel=800x600     us=1
disp: eigen 1366x768x 32   rc=4  why=1  num=1360
      vram=16777216  maplimit=12582912  custom=0  panel=800x600     us=5003
disp: eigen 1400x1050x 16  rc=6  why=4  num=16
      vram=16777216  maplimit=12582912  custom=0  panel=800x600     us=0
```

Read the second and third lines together, because they are the whole
point:

* **2560x1440 fails on this kernel, not on the card.** 14 745 600 octets
  needed; the card has 16 777 216 and would take it; the eight 2 MiB
  window slots carry 12 582 912. The message says all three numbers.
* **1366x768 fails on the card, not on this kernel.** And the number it
  reports is `1360` -- not the anchor value, but *what QEMU actually left
  in the register*. QEMU rounds VBE widths down to a multiple of eight,
  so 1366 becomes 1360 and stays there. The user gets told what the card
  made of their number, and `/bin/dispctl` adds the hint that follows
  from it.

And the same 2560x1440 against a smaller card, same kernel, same command
line, `-device VGA,vgamem_mb=8`:

```
disp: eigen 2560x1440x 32  rc=7  why=2  num=14745600  vram=8388608
```

The reason changed from 3 to 2 and the fault moved from the kernel to the
card, without a line of the message being written twice. **A diagnosis
that changes with the machine is a measurement; one that always reads the
same is a string.**

### What the user reads

`/bin/dispctl eigen 2560 1440`:

```
dispctl: abgelehnt -- dieser Kernel kann es nicht einblenden. Noetig
14745600 Oktette, 12582912 gehen.
  (acht 2-MiB-Fensterplaetze, geteilt mit apic.fi)
```

`/bin/dispctl eigen 1366 768`:

```
dispctl: abgelehnt -- die Karte nimmt diese Zahl nicht an. Sie hat
daraus gemacht: 1360
  (Hinweis: die Breite ist kein Vielfaches von 8)
```

Every number in those lines comes out of the kernel through
`DG_CUSTNUM`, `DG_VRAM` and `DG_MAPLIMIT`. The program computes none of
them; if it did, there would be two truths about the same failure.

### And the screen is untouched

`check_custom` reads registers back without ever writing `VBE_ENABLE`,
and restores the running mode through the same path `set_mode` uses --
the "striped carpet" lesson of round DISPLAY, section 3, now in one
function (`wieder_hin`) so it only has to be right once. That is what
lets the settings page check while the user is still typing. Measured:
after three rejected requests in a row, the photograph is still 800x600,
field 1 is still pure red, and the text line is still pixel-exact against
the font.

### A custom mode joins the list

If the switch stands, the mode is inserted into the list in sorted order
and `customs` counts up. That is what the NVIDIA panel does too, and it
is not cosmetic: without it `current()` would answer "unknown" for the
mode that is *on the screen*, the settings list would point at nothing,
and the way back would have to be found somewhere else.

---

## 4. The safety net, and the part of it that did not work

Round DISPLAY built the deadline correctly: fifteen seconds, the same as
Windows, the old geometry remembered, `poll` puts it back. Two things
were wrong with it anyway, and both were found by testing rather than by
reading.

### 4.1 The countdown did not count

`vmode.poll` was reached from exactly one place: `do_dispset`. So the
fifteen seconds only elapsed while some program was calling into the
display. **That is precisely backwards.** The person the net exists for
is looking at a black screen; they are calling nothing.

Measured on this branch, before the fix -- a program in ring 3 switches
and then sleeps:

```
script=dispctl eigen 1400 1050;sleep 22;dispctl raw
    panelw=1400   pending=1   reverts=0      <- 22 seconds later
```

`kernel/tasks.fi` now calls `vmode.poll` in the idle loop, on every wake
from `hlt`/`mwait`. Same run, after:

```
    panelw=1400   pending=1                  <- right after the switch
    panelw=800    pending=0   reverts=1      <- after `sleep 22`
    switches=2    confirms=0
```

Nothing but `/bin/sleep` ran in between, and `/bin/sleep` makes no
display call at all. **What put the mode back was the idle task, or it
was nobody.**

It is not in the timer interrupt, and the reason is round K18's: `poll`
rewrites page tables and paints a whole screen, and doing that in the
timer filled the kernel stack to within 112 octets. The idle task is task
context with its own stack, and the timer wakes it a hundred times a
second. The first comparison in `poll` is one word of `kdata` against
zero; an idle loop with no deadline open costs exactly that.

### 4.2 The way back went through the list

`revert` called `set_mode`, and `set_mode` starts with `find_mode`. With
custom resolutions the *old* mode need not be in the list either -- and
then the net would have torn at the one moment it exists for.

`set_mode` is now `find_mode` + `switch_to`; `revert` is `switch_to` with
the old numbers and no new deadline. A mode that was on the screen a
moment ago does not need a list entry to prove it works.

### 4.3 In the picture

`dispeigenfrist`: switch to 1400x1050, confirm nothing, wait.

```
disp: eigen 1400x1050x 32  rc=0 ... panel=1400x1050
disp: confirm pend=1  left=14
disp: confirm pend=0  after=1  panel=800x600
disp: sw=2  fail=2  rev=1
```

and the screenshot afterwards is 800 x 600 with the K7 test pattern
pixel-exact. `docs/shots/customres/nach-der-frist-800x600.png`.

---

## 5. Surviving the reboot -- and a counter to undo it

The fifteen seconds save the switch. **They do not save the next boot**,
and that is a different failure with the same ending: confirm a mode on
the monitor at your desk, start the machine on a different monitor, and
there is nobody there to answer a deadline, because the settings program
starts seconds later if at all.

So: the same shape as `kernel/ab.fi` (round UPDATE, the A/B boot).
`/system/BILDMODUS`, exactly 31 octets, fixed width:

```
w=00001400 h=00001050 t=32 v=0\n
```

Fixed width is not cosmetic -- the paragraph is in `ab.fi` and it holds
here: a file whose length never changes goes into exactly one data block,
and a sector reaches the disk whole or not at all. `w=0` means "none",
which is how the record is retired without touching its length.

Each boot raises `v` **before** switching -- a counter a hanging boot
does not reach never counts. At `v + 1 >= 3` the mode is not applied and
the boot mode stays. The fallback costs nothing because it does nothing:
the saved mode is applied *after* the root is mounted, so "do not apply
it" means "stay in the mode the machine already booted in".

And the mode goes through **all three gates** on the way in. A file is not
a warrant: the monitor may be a different one and the card smaller.

### Measured, five boots on the same disk image

```
START 1  dispctl eigen 1400 1050; dispctl behalten
         disp: save none                       (nothing on the disk yet)
         panelw=1400   pending 1 -> 0
START 2  disp: save on 1400x1050x 32  v=1
         panelw=1400   customs=1   savetry=1   saveapp=1
START 3  disp: save on 1400x1050x 32  v=2
         panelw=1400   savetry=2
START 4  disp: save aufgebraucht  v=2  (Startmodus bleibt)
         panelw=800
START 5  disp: save none
         panelw=800
```

Boot 5 is the counter-check that matters: the record is retired, so the
fallback happens once and does not turn into a loop.

And the other direction -- confirming resets it:

```
after the reboot  savetry=1
dispctl behalten  savetry=0
```

### Why confirming is a human act, and stays one

The counter is set to zero by `osum_dispset(DS_CONFIRM)` -- the
"Behalten" button, or `dispctl behalten`. Not automatically. This is the
uncomfortable part of the round and it is written down rather than
smoothed over:

**Every automatic mark would prove that the card accepted the mode.** "The
kernel got this far", "the registers read back", "a program checked in" --
all of them are statements about the machine. The case this counter
exists for is the one where the card accepts the mode and *the monitor
stays dark*. There is no measurement inside the computer for that. There
is a person, or there is nothing.

The cost is one click after the first reboot with a new mode. The
alternative is a counter that clears itself in exactly the situation it
was built for.

---

## 6. What it costs

| | measured |
| --- | --- |
| switch to a custom mode | 13 897 us (register write, remap, back buffer, redraw) |
| a rejected mode, gate 2 or 3 (arithmetic only) | 0-1 us -- the card is never asked |
| a rejected mode, gate 1 (the card is asked) | 5 003 us, almost all of it restoring the running mode |
| `poll` with no deadline open | one `kdata` word compared against zero |

The 5 ms for a rejected width is worth a sentence: asking the card costs a
full mode reset on the way back, because writing `XRES` while
`VBE_ENABLE` is on recomputes the live scanout pitch. That is why the two
arithmetic gates run first -- and why the settings page can check on every
keystroke without the screen so much as flickering.

---

## 7. Real hardware

The full analysis is in `docs/DISPLAY.md`, addendum A4. The short form:

* **The picture works.** On metal the framebuffer comes from the loader
  (Limine, Multiboot flag bit 12, `SRC_MB`), at whatever resolution the
  firmware set through UEFI GOP or VBE.
* **Nothing in this round works.** `vmode.probe` needs the Bochs adapter's
  ISA ports 0x1CE/0x1CF, and no real display engine answers there.
  Measured on two graphics devices that are not that adapter:
  `-vga cirrus` and `-vga none -device bochs-display` both give
  `fb: kein Rahmenpuffer` -- the second one with the *same* PCI ID
  1234:1111 and the *same* 16 MiB aperture, found on the bus, and still
  no screen, because it is the MMIO-only variant with no port pair.
* So: no mode list, no custom resolution, no deadline, and
  `/system/BILDMODUS` is read and applied to nothing.

Two paths out, in `docs/DISPLAY.md` A4: write the confirmed numbers into
the loader's config (cheap, but loses the runtime switch and therefore
the net), or a display driver for one GPU family (Intel is the only one
documented).

One thing found on the way and deliberately **not** changed: brightness,
contrast, gamma, saturation, rotation and scaling need no card at all --
they are arithmetic in `fb.present` -- but they sit behind the same
`vmode.ready` gate and are therefore dead on metal too. Splitting the
gate means rewriting a good assertion in `tools/display/run.sh`, and that
belongs to the round that boots this on metal. It is written down so it
is a decision and not an oversight.

---

## 8. What does not work, and why

* **Colour depths other than 32.** Unchanged from `docs/DISPLAY.md` 8.1,
  and now with its own reason code: a custom mode at 16 bit is refused
  with gate 4 and the number 16. The card can do 4/8/15/16/24/32
  (`depths=0x101018110`, measured); this kernel draws four octets per
  pixel everywhere.
* **Widths that are not a multiple of eight**, under QEMU. Not a rule
  this kernel invented -- it reports what the card did with the number.
* **Anything above 12 582 912 octets**, i.e. 2560x1080 is the largest
  mode that fits. `docs/DISPLAY.md` A3 has the full account of why, what
  it would cost to change, and the measurement that says the payoff would
  be real (with 64 MiB of video memory QEMU's registers accept 3840x2160,
  and only this kernel's window is left in the way).
* **Free entry below 320x200 or above 8192.** Refused as gate 5 before
  the card is asked. The lower bound is the smallest mode the candidate
  list already offered.
* **Two custom resolutions at once**, i.e. per-monitor. There is one
  framebuffer; see `docs/DISPLAY.md` 8.4.

---

## 9. Reproducing this

```
bash tools/customres/run.sh          # nine sections, screenshots
bash tools/display/run.sh            # round DISPLAY, unchanged: 145 / 0
```

Words on the kernel command line, all off by default and all requiring
`disp`:

| word | what |
| --- | --- |
| `dispeigen` | set 1400x1050 -- a resolution in no candidate list |
| `dispeigenbad` | ask for three impossible ones and report gate + number |
| `dispeigenfrist` | switch to a custom mode, confirm nothing, let it run out |

From ring 3:

```
dispctl eigen 1400 1050        set it
dispctl pruefen 2560 1440      only check -- does not touch the screen
dispctl behalten               answer the deadline AND save it
dispctl speichern              save the running mode without a deadline
dispctl testc                  the ten assertions of this round
```

Screenshots in `docs/shots/customres/`.
