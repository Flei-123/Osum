# Round DISPLAY -- the screen

*Osum, branch `display`. Every number in this file comes from a run that
is reproducible with `bash tools/display/run.sh`. Where a number was
measured under QEMU/TCG and would look different on real hardware, it
says so.*

---

## 1. What was there before

`kernel/fb.fi` knew exactly two resolutions:

```
const WIDTH_STD:  u64 = 800
const HEIGHT_STD: u64 = 600
const WIDTH_BIG:  u64 = 1024
const HEIGHT_BIG: u64 = 768
```

They were switchable only through the boot word `fbbig`, and the
settings program said so in plain words on its "Bildschirm" page: *"Der
Bildmodus wird beim Start gesetzt; im Betrieb kann dieser Kernel ihn
nicht wechseln."* That sentence was true and it is now gone.

There was no mode list, no EDID, no runtime mode change, no gamma ramp,
no rotation, and no GPU driver of any kind. The two numbers had a real
justification -- 800x600x4 = 1 920 000 octets fit into one 2 MiB tile,
1024x768x4 = 3 145 728 need two -- but a justification is not a driver.

## 2. What this round built

| file | what |
| --- | --- |
| `kernel/vmode.fi` (new, 1180 lines) | mode list, EDID, mode switch with rollback, confirmation deadline, gamma/brightness/contrast ramp |
| `kernel/fb.fi` (+700 lines) | window remapping, panel/image split, rotation, scaling, lookup-table transfer path |
| `kernel/sys.fi` | three calls for ring 3: 1810 `osum_dispget`, 1811 `osum_dispset`, 1812 `osum_dispstr` |
| `kernel/user/dispctl.fi` (new) | `/bin/dispctl` -- the same thing from ring 3, one number per line |
| `kernel/user/settings.fi` | the "Bildschirm" page rebuilt: the list comes from the card, Apply applies, the confirmation counts down |
| `tools/display/run.sh` (new) | the acceptance run, eleven sections |

Two pages of `kdata` are taken, `0x5A000` (scalars and mode list) and
`0x5B000` (lookup table and EDID block). Both are entered in
`tools/kernel/memmap.py`; the collision checker reports 54 areas and 0
collisions.

---

## 3. Asking the card, instead of writing down two numbers

The Bochs VBE interface (ports `0x1CE`/`0x1CF`) has two things round K7
did not use:

1. **Read-back.** What you write into `XRES`, `YRES` or `BPP` can be
   read out again. QEMU's `vbe_ioport_write_data` only stores a value if
   it passes its own check; a rejected value leaves the **old** one
   standing, and that is what the probe recognises. It does **not** set
   the mode: as long as `VBE_ENABLE` is zero, those registers are three
   numbers and nothing more. That is why the probe can ask 22 times in a
   row without the screen so much as flickering.
2. **`VBE_DISPI_INDEX_VIDEO_MEMORY_64K` (index 0x0A).** The card says how
   much video memory it has, in units of 64 KiB.

A third limit does not come from the card but from this kernel, and it is
the one that actually bites -- see section 5.

### Measured: what QEMU 7.2.22 with `-vga std` accepts

```
disp: vram=16384 KiB  depths=0x101018110  maplimit=12582912
      probed=22  refused=2  toobig=0  unmappable=2
disp: modes 18
   320x200    640x400    640x480    800x600    1024x768   1152x864
   1280x720   1280x800   1280x1024  1360x768   1440x900   1600x900
   1600x1200  1680x1050  1920x1080  1920x1200  2048x1152  2560x1080
disp: out   1366x768    reason=1   (the registers refused the width)
disp: out   2560x1440   reason=3   (this kernel cannot map it)
disp: out   2560x1600   reason=3
disp: out   3840x2160   reason=1   (the registers refused the width)
```

Read that carefully, because it contains one genuinely surprising
result and one embarrassing one:

* **16 MiB of video memory, and not one candidate failed on it**
  (`toobig=0`). The VRAM check is implemented and correct, but on this
  machine it never fires. On a card with 4 MiB it would; the assertion in
  `vmode.selftest` covers the arithmetic either way.
* **1366x768 is refused, 1360x768 is not.** QEMU rounds VBE widths down
  to a multiple of 8; 1366 is not, 1360 is. This is not a guess -- the
  probe wrote 1366 and read back 640, the anchor value. It is exactly the
  kind of thing a table of "standard resolutions" in the source code
  would have got wrong, silently, for years.
* **3840x2160 is refused by the registers**, not by memory: QEMU's
  `VBE_DISPI_MAX_XRES` cuts in before the VRAM check ever runs.
* **The colour-depth mask `0x101018110`** means the card accepts 4, 8,
  15, 16, 24 and 32 bits. All six. See section 8 for why this kernel
  still refuses to switch to any of them but 32.

### What the probe cannot tell you

Read-back only tells you what the registers **store**, not what the card
will do when `VBE_ENABLE` is finally written. QEMU's `vbe_fixup_regs`
runs at that point and can still clamp. The probe therefore also computes
the memory requirement itself, and `set_mode` reads the registers back a
second time after enabling. If that second read disagrees, the switch is
rolled back (section 5). A non-destructive probe cannot be complete; this
one is honest about which of its three gates rejected each candidate, and
that is the best that is available without flashing the screen 22 times.

### Two things this got wrong first, because they are worth writing down

**Probing changes the picture that is on the screen.** The probe writes
different numbers into `XRES` and `YRES` twenty-two times. As long as
`VBE_ENABLE` stays on, that is not a quiet register access: QEMU
immediately recomputes the line length of the *live* scanout
(`VBE_VIRT_WIDTH`) from `XRES`, and it stays recomputed. Writing `XRES`
and `YRES` back afterwards is **not enough** -- the card kept scanning
out with a different pitch than the kernel believed, and the screenshot
showed a striped carpet instead of four colour fields, shifting by a
fixed amount every few rows. The kernel thought it was correct: every
number in its own state was right (`disp: geom 800x600 pitch=3200 panel=800x600 ppitch=3200`). The fix is to restore the old mode through
the *same* path `set_mode` uses -- off, numbers, on -- and then read the
line length back and compare it with the one `fb.fi` keeps, remapping if
they disagree. Only a screenshot found this; no assertion on the kernel's
own numbers could have.

**`disp` is a substring of `dispctl`.** `fb.fi` matches its command-line
words as substrings, which was fine until this round added a counter-check
that boots *without* the word `disp` and runs `script=dispctl raw`. The
kernel found `disp` inside `dispctl`, probed the card, and the section
that was supposed to prove that nothing happens without the word proved
the opposite. `vmode.find_word` requires a whole word. A test that goes
green for the wrong reason is worse than no test.

---

## 4. EDID -- and the part where DDC/I2C does *not* happen

The task asked for EDID over DDC/I2C. **That is not what this does, and
the difference matters.**

The honest path to a monitor's own data is DDC/I2C: two pins in the
connector, a small memory in the monitor, and the computer clocking it
out bit by bit. *Which registers wiggle those two pins is known only to
the GPU driver.* On Intel it is documented (the GMBUS registers). On
NVIDIA and AMD it is not in any public document. **There is no generic
DDC path**, and this round does not pretend otherwise.

What it does instead: QEMU places the EDID block it generates at offset 0
of the card's third address region (BAR2, `-device VGA,edid=on`, and `on`
is the default). `vmode.edid_probe` maps that region, copies 128 octets,
checks the `00 FF FF FF FF FF FF 00` header and the checksum, and parses
the manufacturer, the model name and the native resolution out of the
first detailed timing descriptor. That is **reading a block out of device
memory, not an I2C transaction.**

### Measured

```
disp: edid ok  nat=1280x800  ven=RHT  mod=QEMU Monitor
```

Checksum and header are verified twice: once in the kernel, and once in
`tools/display/run.sh`, which re-computes them in Python from the raw
octets the kernel dumped. A kernel confirming its own check has proved
nothing.

On a machine where BAR2 does not exist or cannot be mapped, `edid_why`
reports why (1 = no memory region, 2 = not mappable, 3 = wrong header,
4 = bad checksum) and the mode list from section 3 carries alone. It is
the more dependable of the two sources anyway: it says what the **card**
can do, not what the **monitor** would like.

One thing the EDID read cost, and it was worth writing down: reading it
takes a 2 MiB window slot, and the first version of this round never gave
it back. Those same eight slots limit the largest mappable mode, and one
occupied slot in the middle cut the longest contiguous run from six tiles
to four. The result was a mode list that offered 2048x1152 and a
`set_mode` that then failed with `E_MAPFAIL`. **A list that offers
something that does not work is worse than a shorter list.** `fb.unmap_slot`
gives the slot back; `maplimit` rose from 10 485 760 to 12 582 912 octets
and 2560x1080 became reachable.

---

## 5. Switching the mode while the kernel is running

The hard part is not writing the registers. The hard part is everything
afterwards: the framebuffer gets bigger and needs more of the eight 2 MiB
window slots, the back buffer no longer fits, and the window server holds
windows at coordinates that no longer exist.

`vmode.set_mode` runs in an order chosen so that **every** failure falls
back onto a state that already exists, rather than one that would have to
be reconstructed:

1. Check. Nothing is touched.
2. Allocate the new back buffer. The old one stays until the switch
   stands -- a freed buffer that the window server is still drawing into
   is somebody else's memory.
3. Set the mode. If that fails, **nothing has been remapped yet**: old
   mode back, new buffer released, done.
4. Remap. If *that* fails, the old slots were just freed and the old
   geometry is guaranteed to fit back into the space it came from.
5. Only now install the new buffer and free the old one.

No black screen is left behind at any of those points. Section 6 of the
acceptance run photographs it.

### Measured

```
fb: 800x600x32  pitch=3200  src=vbe  phys=0xfd000000  huge=1
disp: switch 800x600 -> 1024x768   rc=0  us=10646  panel=1024x768
disp: switch 1024x768 -> 800x600   rc=0  us=...    panel=800x600
disp: sw=2  fail=0  rev=0
```

and the screenshots: the *before* image is 800 x 600, the *after* image is
1024 x 768, both with the K7 test pattern verified pixel by pixel against
the font (`schau.py text ... "OSUM K7 FRAMEBUFFER 01234"`). The pixel at
(1023, 767) exists in the second image and does not exist in the first.

**10.6 ms** for one switch, under QEMU/TCG. That covers the register
write, freeing and re-taking the window slots, a `cr3` reload, allocating
the back buffer, and clearing and redrawing the screen.

### The failure case

```
disp: switch 800x600 -> 4096x4096  rc=2  us=302  panel=800x600
disp: sw=0  fail=1  rev=0
```

`rc=2` is `E_NOMODE`. The screenshot after that attempt is still
800 x 600, field 1 is still pure red, and the text line is still
pixel-exact. The counter-check is in the runner as well: the same
assertion against black fails, so "no black screen" is a measurement and
not a phrase.

### The confirmation deadline

A mode the monitor cannot display is, without a way back, a dead
computer. So `set_mode` arms a deadline of **15 000 ms** (the same as
Windows), remembers the old geometry, and `vmode.poll` puts it back if
nobody confirms.

```
disp: confirm pend=1  left=15
disp: confirm pend=0  after=1  panel=800x600
```

Two details that are easy to get wrong and were got wrong once here:

* **`poll` must not run in the interrupt path.** It rewrites page tables
  and paints a whole screen. That is the lesson of round K18, where
  recomputing the screen in the timer filled the kernel stack to within
  112 octets. It is called from the syscall path instead, in task
  context, on the task's stack.
* **The safety net must not depend on the program whose screen just went
  black.** The settings dialog counts down and offers two buttons, but the
  kernel reverts on its own even if that program never answers again.

---

## 6. Brightness, contrast, gamma, saturation

This is the part of a graphics-card control panel that genuinely works
without a graphics driver, and the reason is arithmetic, not access:
brightness, contrast and gamma are three operations on **one channel
value**, and three operations on a value between 0 and 255 are a table
with 256 entries. Whether that table sits in the card's output stage
(where it costs nothing) or in `fb.present` (where it costs what is
measured below) is a question about the driver, not about the maths. The
Bochs adapter has no palette for 32-bit modes, so the table sits here.

Order is contrast around the midpoint 128, then brightness, then gamma.
Gamma is computed with integer arithmetic only -- a binary search on
`y^gamma = x` in 16.16 fixed point, because this kernel has no floating
point and is not getting any.

**Saturation is not a lookup table**, and that is where it gets more
expensive. It mixes the channels: it needs the grey value of the pixel,
which depends on all three. So it is a per-pixel computation, with the
Rec.601 weights 77/150/29 (that is 0.299/0.587/0.114 times 256, summing
to exactly 256 so the shift by 8 is exact).

`vmode.selftest` checks fifteen properties of this, including the two
that distinguish a gamma curve from a brightness change: gamma 2.20
raises the midpoint above 150 while leaving 0 at 0 and 255 at 255, and
gamma 0.45 lowers it below 90 with the same endpoints. It also checks the
table is monotonic -- a curve that dips would be an arithmetic error that
is invisible in the picture.

### Measured cost, at the largest mode the list offers

```
disp: bench 2560x1080  px=2764800
      flush=8407 us   lut=496670 us   lutline=6938 us
      sat=1445486 us  rot90=895268 us
```

| path | per full frame | per pixel |
| --- | --- | --- |
| `rep movsq`, no arithmetic (round K7) | 8 407 us | 3 ns |
| through the lookup table | 496 670 us | 179 ns |
| one text line (16 rows) through the table | 6 938 us | 169 ns |
| plus saturation | 1 445 486 us | 522 ns |
| 90-degree rotation, no table | 895 268 us | 323 ns |

**These numbers are bad, and here is why they are bad.** Two reasons,
both of them honest and neither of them fixable inside this round:

1. **There is no KVM on the machine this was measured on** (`/dev/kvm`
   does not exist; QEMU falls back to TCG). Every instruction of the
   per-pixel loop is emulated. `rep movsq`, by contrast, becomes a single
   host `memcpy` in TCG -- which is why the ratio 1:73 between the fast
   path and the table path overstates the real difference by a large
   factor.
2. **`firnc` is a bootstrap compiler with no register allocator.** Every
   intermediate value goes to the stack. The disassembly of `fb.present`
   shows roughly 40 instructions per pixel where ten would do.

What *is* under this round's control was done and measured:

* Hoisting the three colour shifts and the three table bases out of the
  loop and inlining the lookups: **195 938 us -> 95 669 us** at 800x600.
  That is a 2x improvement from removing six function calls per pixel.
* A dedicated straight-line path for the case that actually occurs
  (no rotation, no scaling, table on) which honours the **dirty
  rectangle**. This is the number that matters in practice: a console
  writing one line costs 16 screen rows, not 1080. Measured: **6 938 us
  instead of 496 670 us**, a factor of 72.
* And when there is no rotation, no scaling, no table and no saturation,
  `flush` takes the K7 `rep movsq` path unchanged. The condition is one
  comparison against four scalars. `fbbench` before and after this round
  is the same.

---

## 7. Rotation and scaling

Rotation is done when transferring the back buffer to the panel, not by
the card -- the Bochs adapter cannot rotate. The consequence is a split
that runs through the whole of `fb.fi` from this round on:

* **the panel** (`S_PWIDTH`/`S_PHEIGHT`/`S_PPITCH`) is what the card
  scans out, what `S_ADDR` is the size of, and what `/dev/fb` sees;
* **the image** (`S_WIDTH`/`S_HEIGHT`/`S_PITCH`) is what `pixel`, `fill`,
  `putc` and the window server draw into.

Without rotation and without scaling they are identical, and every
measurement from rounds K7 to K18 is unchanged.

Measured: with rotation 90 the panel stays 800x600 and the image becomes
600x800; the screenshot is 800x600, and the red field that sits at image
(50,50) is found at panel (749,50). The counter-check -- that it is *not*
at (50,50) -- is in the runner too.

Rotation and scaling require a back buffer. Without one you would be
reading from and writing into the same surface. `set_rotation` returns
false if there is none.

The three scaling policies are the ones a monitor has in its own
electronics and a driver panel calls "full screen / aspect ratio /
no scaling": `SCALE_FULL`, `SCALE_ASPECT`, `SCALE_NONE`. They only do
anything when the image is deliberately a different size from the panel
(`fb.set_logical`); when the card is set to the chosen resolution --
the normal case -- there is nothing to scale, and the settings page says
so rather than offering a control that does nothing.

**One thing that this cost, stated plainly:** the rotated and scaled path
transfers the *whole* panel every time. A changed image row is a panel
*column* after a quarter turn, and a column cannot be described by the
existing dirty-rectangle arithmetic. So a rotated screen pays a full
frame on every update. The number is in the table above and is not talked
down.

---

## 8. What does **not** work, and why

This is the section the round is measured against, so it names things
rather than gesturing at them.

### 8.1 Colour depths other than 32 bit

The card accepts 4, 8, 15, 16, 24 and 32 bit (`depths=0x101018110`,
measured). This kernel refuses to switch to any of them but 32, and
`set_mode` returns `E_DEPTH` with that as its own reason.

Why: `fb.pixel` writes a 32-bit word, `fb.hline` puts two pixels in one
64-bit word, the back buffer is sized as width times four, `blit`,
`scroll`, the font renderer, the window server and `/dev/fb` all assume
four octets per pixel. What is missing is not a register write -- it is a
second set of drawing primitives for 8- and 16-bit formats plus a palette
for the indexed modes. The card's capability is **reported** because it is
true; the switch is **refused** because the kernel would draw garbage.

### 8.2 Anything that needs a real GPU driver

None of the following is implemented, and none of it is implementable
through the Bochs VBE interface, at any effort:

| feature | what it actually needs |
| --- | --- |
| G-Sync / FreeSync / VRR | control over the display timing generator and the ability to change the vertical blanking interval per frame. VBE exposes a resolution, not a timing. |
| DSR / DLDSR / supersampling | rendering at a higher resolution and filtering down -- i.e. a 3D pipeline to render with in the first place. |
| forced anti-aliasing (MSAA/FXAA override) | intercepting an application's 3D calls. There is no 3D API in this system to intercept. |
| shader cache | shaders. |
| power management mode ("prefer maximum performance") | the GPU's own clock and voltage registers. |
| per-application 3D profiles | see above, twice. |
| Surround / multiple monitors on one GPU | see 8.4. |

The screen is a linear framebuffer that the CPU writes into. Everything
in that table is a property of a rendering engine that does not exist.

### 8.3 Why an NVIDIA driver is not a realistic path

Not "hard" -- practically closed, and for two separate reasons:

* **The registers are undocumented.** NVIDIA publishes no programming
  manual for the display engine or the command processor. Nouveau's
  knowledge came from years of reverse engineering, and it lags each
  generation by a long way.
* **Newer cards will not run unsigned firmware.** From Maxwell (GM20x)
  onwards the GPU's own microcontroller (falcon) only executes
  NVIDIA-signed firmware. Without it, clocks cannot be raised and large
  parts of the engine stay unavailable. That is not a documentation
  problem that effort can solve; it is a signature you do not have the
  key for.

**The realistic paths, in the order a project like this should take
them:**

1. **virtio-gpu** for virtual machines. The specification is public
   (OASIS virtio 1.x), the command set is small (`RESOURCE_CREATE_2D`,
   `SET_SCANOUT`, `TRANSFER_TO_HOST_2D`, `RESOURCE_FLUSH`), and this
   kernel already has a virtio transport in `kernel/virtio.fi` from
   round K8. It brings real multi-scanout, proper resize, and EDID over
   the `GET_EDID` command instead of a memory region. This is the next
   step, and it is the cheapest one by a wide margin.
2. **UEFI GOP** as the generic fallback on real hardware: ask the
   firmware for the mode list before exiting boot services, hand the
   chosen framebuffer to the kernel through the loader. That is the same
   `SRC_MB` path `fb.fi` already has; what is missing is the loader side.
   No per-vendor knowledge needed, and no mode changes after boot.
3. **Intel integrated graphics** if a native driver is ever wanted. The
   programmer's reference manuals are public per generation. The order of
   work is: GMBUS/DDC for real EDID, then the display pipeline (planes,
   pipes, transcoders, PLLs) for real mode setting, then -- separately and
   much later -- the render engine.
4. **AMD** sits between the two: `amdgpu` register headers are published,
   but the driver is large and the firmware blobs are still required.

No effort estimates in person-months are given here, deliberately. The
steps above are the content; how long they take depends on who does them.

### 8.4 Multiple monitors

Not supported, and here is precisely what is missing rather than a
shrug:

* **The Bochs VBE interface has exactly one scanout.** There is one
  `XRES`, one `YRES`, one framebuffer base. There is no second one to
  configure. Multi-head would require a different device -- QEMU's
  `secondary-vga`, or virtio-gpu, which has `SET_SCANOUT` per output.
* **The kernel has one framebuffer.** `fb.fi` keeps one address, one
  geometry, one back buffer and one dirty rectangle in one `kdata` page.
  Two screens means all of that becomes an array, and every caller of
  `fb.width()` has to say *which* screen it means.
* **The window server has one coordinate space.** `wm.fi` composes into
  one surface starting at (0,0). A desktop spanning two panels needs a
  global coordinate space, a per-window mapping onto outputs, and a
  compose pass per output.
* **There is no output object.** Connector, EDID per connector, enabled
  or not, position in the global space -- none of that exists as a
  concept. It is the piece to build first, and it should be built
  together with virtio-gpu rather than bolted onto VBE.

---

## 9. What the next round needs

1. **virtio-gpu.** Everything above points at it: multi-scanout, real
   resize, EDID over a command instead of a BAR, and a transport that
   already exists in this tree.
2. **A repaint notification.** Changing rotation or resolution reinterprets
   the back buffer, and whoever drew into it has to draw again. This round
   found that the hard way -- the test pattern came out as a striped
   carpet -- and worked around it by drawing after switching. `wm.fi`
   needs an event for it, and the settings page and every application
   need to handle it.
3. **A partial-transfer path for the rotated case.** A dirty rectangle in
   image space is a rotated rectangle in panel space; that is describable,
   it just is not described yet. It would take the rotated screen from a
   full frame per update down to the same 16 rows the unrotated one costs.
4. **The 8/16-bit drawing primitives**, if the colour-depth setting is
   ever to do more than report.
5. **A measurement with KVM.** Every timing in section 6 is TCG. The
   ratios between the paths are trustworthy; the absolute numbers are not
   a statement about hardware.

---

## 10. Reproducing this

```
bash tools/display/run.sh
```

Eleven sections. The mode list, the EDID block (re-checked outside the
kernel), the runtime switch with a screenshot before and after, the
failure case with a screenshot proving the screen is not black, the
deadline expiring on its own, rotation in the picture, the cost per
frame, the same numbers again from ring 3 through `/bin/dispctl`, and the
counter-check that removes the word `disp` and expects every one of those
to disappear.

Words on the kernel command line, all of them off by default:

| word | what |
| --- | --- |
| `disp` | probe the card, report the list, count the assertions |
| `dispbig` | switch to 1024x768 at runtime |
| `dispback` | ...and back to 800x600 |
| `dispbad` | ask for a mode that does not exist |
| `dispbench` | measure the cost of the table per frame |
| `disprot` | stop with the screen rotated 90 degrees, for the photo |
| `dispconfirm` | switch, do not confirm, let the deadline run out |
| `dispedid` | dump the raw EDID block |

---

## 11. State of the acceptance run

```
DISPLAY: 140 passed, 0 failed
```

The rounds that came before are unchanged: `tools/gfx/run.sh` reports
76 passed, 0 failed with this branch in the tree, including its thirteen
kernel-side assertions about the framebuffer and its pixel-exact
comparison of the whole screen against the serial transcript.

### The state of the other suites, measured and not assumed

| suite | on this branch | note |
| --- | --- | --- |
| `tools/gfx/run.sh` | 76 passed, 0 failed | the framebuffer of round K7, unchanged |
| `tools/kernel/run.sh` | 176 passed, 0 failed | |
| `tools/osum/run.sh` | 130 passed, 0 failed | |
| `tools/userland/run.sh` | 91 passed, 0 failed | |
| `tools/k18/run.sh` | 169 passed, **1 failed** | not this round -- see below |
| `tools/wm/run.sh` | 99 passed, **4 failed** | not this round -- see below |

Those five failures were **already there before this round touched
anything**, and that is a measurement, not a claim: `tools/wm/run.sh`
checked out at commit `d7bdcfc` (branch `desktop`, the merge parent)
gives the same *99 passed, 4 FAILED* with the same four assertions. They
belong to round DESKTOP, which raised `MAX_WIN` from 8 to 16 and added
three assertions to `wm.selftest` (its runner still expects 17, and gets
20) and changed the title bar rendering (three pixel-exact title
comparisons come out blank). The single K18 failure is the same story:
round DESKTOP's taskbar `kernel/user/taskbar.fi` declares
`SYS_PWRGET: u64 = 1750`, and the K18 runner asserts that no file outside
its own round names a number from 1750..1799.

This round merged `desktop` because the settings program it needed a page
in lives there. Fixing another round's assertions is that round's work,
not this one's -- but pretending they are green would be worse.

One practical note for whoever runs these: they are QEMU under TCG and
they are slow. Running six of the suites in parallel on a twelve-core
machine made several of them fail with `exit code 0, expected 21` and
`'fb: hold' is missing` -- the sixty-second wait for the hold marker
simply ran out. Run them one at a time; the failures were the harness
starving, not the kernel.
