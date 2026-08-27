# The machine boundary

Round ARM, 27 August 2026. Osum was an x86-64 kernel. This round does not
make it an AArch64 kernel — it draws the line between "the kernel" and "this
processor", pushes the x86-64 code behind that line without changing a
single thing it does, and builds the first working AArch64 side underneath
it. What runs today on `qemu-system-aarch64 -M virt` is not Osum; it is the
floor Osum will stand on, and everything it claims about itself is measured
by `tools/arm/run.sh`.

Everything below is a number that was taken, or a limit that was hit. Where
something does not work, it says so and says why.

---

## 0. What changed in round OSUM-ARM2

Round ARM was blocked on one thing and said so: the pinned Firn compiler
answered `--target=aarch64-linux` with *"does not support the kernel profile
yet (round 80)"*, so the whole AArch64 side had to be written in assembly and
the one real defect it found could not be fixed. Firn's round
ARM-FREESTANDING removed that answer. This is what came of it.

| | round ARM | round OSUM-ARM2 |
|---|---|---|
| pinned compiler | `c66c6bcd` (no freestanding AArch64) | `a751b3dbf` (`aarch64-none`) |
| the x86 image under the new pin | — | **octet for octet identical**, sha256 `e3699d9b…` both ways |
| the AArch64 side | 1,166 lines of assembly | **688 lines of Firn**, 419 of assembly |
| what drives the UART, MMU, GIC, timer, faults | hand-written A64 | compiled Firn, `--target=aarch64-none` |
| the line in `arch.fi` that names the machine | one, had to be edited | **none** — `#[arch(…)]` and `--target=` |
| `atomic.fi` | 4 asm blocks, `lock_give` a plain `str` on ARM | **0 asm blocks**, `lock_give` a `stlr` |
| modules compiling for `aarch64-none` unchanged | 31 of 53 (58.5 %) | **40 of 55 (72.7 %)**, 67.3 % by lines |
| `tools/arm/run.sh` | 39 proofs | **48 proofs**, 0 failures |
| measured with | a work-in-progress binary from another repository | the compiler this repository pins |

Three findings of round ARM are now closed, and it is worth saying which:

* **§7.2, the release store.** Fixed and proved, `tools/arch/order.sh`,
  15 proofs. See §7 below, which has been rewritten.
* **§6, the borrowed compiler.** The number is now measured with the pinned
  build.
* **§2, the switch.** There is no line to edit any more.

Two are still open and are named again in §10: the barrier-less SMP
handshake in `smp.fi` (§7.4) and the compiler's register-only check on
inline assembly (§5.4).

---

## 1. How big the job really is

Before anything was moved, `tools/arch/inventory.py` counted it. The tool
strips comments (a first version called `sys.fi` machine dependent because
the WORD `syscall` appears in a comment, and `hw.fi` because it says `IRQ`
forty-two times while describing hardware it never touches), keeps string
literals — inline assembly lives in a string — and counts LINES OF CODE
carrying a mark of one machine.

State of `main` before this round, 68 files, 50,720 lines:

| class | files | lines | share | machine lines |
|---|---:|---:|---:|---:|
| INDEPENDENT — not one marked line | 23 | 20,422 | 40.3 % | 0 |
| SEAM — 1..15 marked lines | 28 | 20,155 | 39.7 % | 154 |
| DEPENDENT — more than 15 | 7 | 4,186 | 8.3 % | 206 |
| X86-ONLY — no counterpart on `-M virt` | 10 | 5,957 | 11.7 % | 256 |
| **total** | **68** | **50,720** | 100 % | **616** |

Plus `kernel/user/`: 79 files, 26,444 lines, of which **five files carry a
machine mark at all**, fourteen lines in total.

**616 machine lines out of 50,720, and 14 out of 26,444 in the userland.**
That is the honest size of the problem and it is much smaller than the file
list suggests — but the 616 are not evenly spread, and the seven DEPENDENT
files plus the ten x86-only ones are 20 % of the kernel by line count.

The full per-file table:

| file | lines | machine lines | class | marks | what it is |
|---|---:|---:|---|---|---|
| `sys.fi` | 6141 | 0 | INDEPENDENT | mmio:37 | the system call gate — the numbers are Linux', the entry is x86 |
| `fat.fi` | 2007 | 0 | INDEPENDENT | mmio:10 | |
| `fs.fi` | 1464 | 0 | INDEPENDENT | mmio:2 | |
| `ttf.fi` | 1386 | 0 | INDEPENDENT | — | |
| `procfs.fi` | 1226 | 0 | INDEPENDENT | mmio:2 | |
| `elf.fi` | 1161 | 0 | INDEPENDENT | mmio:2 | |
| `inet.fi` | 1135 | 0 | INDEPENDENT | mmio:3 | |
| `tty.fi` | 756 | 0 | INDEPENDENT | mmio:12 | |
| `netsvc.fi` | 605 | 0 | INDEPENDENT | — | |
| `vfs.fi` | 530 | 0 | INDEPENDENT | — | |
| `ftype.fi` | 505 | 0 | INDEPENDENT | — | |
| `part.fi` | 498 | 0 | INDEPENDENT | mmio:2 | |
| `file.fi` | 494 | 0 | INDEPENDENT | — | |
| `devfs.fi` | 486 | 0 | INDEPENDENT | — | |
| `cap.fi` | 364 | 0 | INDEPENDENT | — | |
| `mnt.fi` | 327 | 0 | INDEPENDENT | mmio:2 | |
| `bootmod.fi` | 309 | 0 | INDEPENDENT | — | |
| `perm.fi` | 285 | 0 | INDEPENDENT | — | |
| `nidx.fi` | 191 | 0 | INDEPENDENT | — | |
| `ofs.fi` | 178 | 0 | INDEPENDENT | — | |
| `vfsops.fi` | 138 | 0 | INDEPENDENT | — | |
| `font.fi` | 130 | 0 | INDEPENDENT | — | |
| `errno.fi` | 106 | 0 | INDEPENDENT | — | |
| `kcore.fi` | 360 | 15 | SEAM | asm:4 port:13 | std.core in the kernel, over the same ports |
| `start.s` | 193 | 15 | SEAM | creg:7 desc:1 page:8 | startup: stack, page tables, the jump into the kernel |
| `serial.fi` | 174 | 14 | SEAM | asm:2 port:14 | the serial console (16550 here, PL011 there) |
| `sched.fi` | 1143 | 13 | SEAM | asm:7 creg:8 mmio:18 page:5 | the scheduler; its LOGIC is portable, the switch under it is not |
| `guard.fi` | 392 | 13 | SEAM | asm:6 creg:9 | SMEP/SMAP (PAN/PXN on AArch64) |
| `smp.fi` | 1000 | 11 | SEAM | asm:4 desc:7 intc:2 mmio:6 | starting the further processors |
| `trap.fi` | 348 | 9 | SEAM | asm:1 creg:7 mmio:1 port:2 | what an exception does once it has arrived |
| `smp.s` | 159 | 9 | SEAM | creg:9 page:1 | the trampoline of the further processors |
| `pci.fi` | 591 | 8 | SEAM | asm:2 mmio:2 port:8 | configuration space over the ports 0xCF8/0xCFC |
| `kmain.fi` | 3737 | 5 | SEAM | asm:4 creg:1 desc:1 mmio:3 page:1 | the start of the kernel proper |
| `virtio.fi` | 925 | 4 | SEAM | asm:2 intc:2 mmio:11 | virtio over PCI; on `-M virt` the same device is MMIO |
| `nvme.fi` | 698 | 4 | SEAM | asm:2 intc:2 mmio:10 | NVMe — MMIO plus DMA; the doorbell needs a barrier |
| `isr.s` | 504 | 4 | SEAM | desc:4 | the exception and interrupt entry points |
| `rand.fi` | 385 | 4 | SEAM | asm:4 mmio:2 | the entropy source — cycle counter and timer jitter |
| `atomic.fi` | 253 | 4 | SEAM | asm:4 mmio:2 | atomic operations, barriers, and the lock built on them |
| `time.fi` | 360 | 3 | SEAM | asm:1 creg:1 mmio:6 port:2 | the clock and the cycle counter |
| `wm.fi` | 1882 | 2 | SEAM | asm:2 mmio:7 | the window server; the two `asm` lines are a fence pair |
| `uprog.fi` | 1850 | 2 | SEAM | asm:2 mmio:13 | the built-in ring 3 programs, assembled in |
| `kstate.fi` | 979 | 2 | SEAM | desc:2 mmio:6 | the kernel's own state, per-processor block included |
| `mem.fi` | 603 | 2 | SEAM | asm:2 mmio:6 | physical frames and the page table format |
| `wig.fi` | 499 | 2 | SEAM | asm:2 mmio:6 | the window calls |
| `uio.fi` | 484 | 2 | SEAM | port:2 | copying across the ring boundary |
| `cpu.fi` | 163 | 2 | SEAM | intc:2 mmio:3 | processor identification |
| `signal.fi` | 1143 | 1 | SEAM | asm:1 mmio:43 | the signal frame — a register set of one machine |
| `hw.fi` | 736 | 1 | SEAM | intc:1 | |
| `ansi.fi` | 345 | 1 | SEAM | asm:1 | the console, over the serial port |
| `tasks.fi` | 133 | 1 | SEAM | asm:1 | the task bodies of round 59, with `hlt` in them |
| `switch.s` | 116 | 1 | SEAM | desc:1 | the context switch |
| `apic.fi` | 575 | 47 | DEPENDENT | asm:7 creg:13 intc:19 mmio:9 page:8 port:10 | the interrupt controller (GIC on AArch64) |
| `proc.fi` | 1058 | 36 | DEPENDENT | asm:9 creg:11 mmio:8 page:34 | address spaces and the ring change |
| `blk.fi` | 443 | 34 | DEPENDENT | asm:2 mmio:6 port:34 | ATA over ports, NVMe over MMIO |
| `fb.fi` | 1520 | 27 | DEPENDENT | asm:10 creg:3 mmio:13 page:8 port:16 | the frame buffer, over the ports 0x1CE/0x1CF |
| `user.fi` | 268 | 23 | DEPENDENT | asm:7 creg:17 mmio:10 page:7 | the way into ring 3 / EL0 |
| `idt.fi` | 175 | 23 | DEPENDENT | asm:5 desc:5 mmio:12 port:15 | the exception table plus PIC/PIT |
| `core.fi` | 147 | 16 | DEPENDENT | asm:4 mmio:3 port:14 | the minimal kernel of round 52 |
| `hv.fi` | 1843 | 142 | X86-ONLY | asm:10 creg:21 mmio:12 page:5 svm:116 | AMD-V/SVM with a VMCB |
| `pwr.fi` | 1043 | 38 | X86-ONLY | asm:8 creg:32 mmio:1 | IA32_PERF_CTL, HWP, monitor/mwait |
| `vmcb.fi` | 271 | 21 | X86-ONLY | mmio:8 svm:21 | the VMCB layout, field for field |
| `ps2m.fi` | 610 | 16 | X86-ONLY | asm:4 port:12 | the PS/2 auxiliary port at 0x60/0x64 |
| `hv.s` | 545 | 15 | X86-ONLY | creg:9 page:2 svm:6 | the AMD-V world switch and the guests |
| `boot.s` | 246 | 15 | X86-ONLY | creg:7 desc:1 page:8 | the Multiboot header and the climb into long mode |
| `power.fi` | 188 | 8 | X86-ONLY | asm:5 mmio:2 port:5 | ACPI shutdown through the PM1 block |
| `kbd.fi` | 287 | 1 | X86-ONLY | port:1 | the PS/2 keyboard at port 0x60 |
| `batt.fi` | 487 | 0 | X86-ONLY | mmio:12 | battery and mains out of ACPI objects |
| `acpi.fi` | 437 | 0 | X86-ONLY | mmio:7 | ACPI tables found through the BIOS/EBDA |

Reproduce with `./tools/arch/inventory.py`.

### And where it stands now

The same tool on the same tree after two rounds. `kernel/` no longer contains
the machine layer at all -- it is in `kernel/arch/`, counted separately.

| class | files | lines | share | machine lines |
|---|---:|---:|---:|---:|
| INDEPENDENT | 30 | 24,198 | 54.8 % | 0 |
| SEAM | 15 | 13,741 | 31.1 % | 73 |
| DEPENDENT | 4 | 3,174 | 7.2 % | 111 |
| X86-ONLY | 6 | 3,052 | 6.9 % | 63 |
| **total** | **55** | **44,165** | 100 % | **247** |

616 machine lines became 247, and 23 INDEPENDENT files became 30. The
difference did not evaporate: 6,853 lines of it moved into
`kernel/arch/x86_64/`, 835 into `kernel/arch/` and 1,373 into
`kernel/arch/aarch64/`, where it is machine code on purpose and says so in
its path.

---

## 2. Where the line runs

```
kernel/*.fi                 the kernel. No knowledge of a machine.
kernel/arch/arch.fi         THE BOUNDARY. It asks the questions.
kernel/arch/machine.fi      BOTH MACHINES ANSWER, in one file, one
                            `#[arch(...)]` pair per operation.
kernel/arch/x86_64/         what only x86-64 has: the APIC, the IDT, the
                            descriptor tables, SMEP/SMAP, ring 3, SMP,
                            the hypervisor. 8 Firn and 6 assembly files.
kernel/arch/aarch64/        what only AArch64 has: amain.fi (the kernel
                            side, in Firn), virt.fi/virt.inc (the
                            addresses), start.S, vectors.S, switch.S.
kernel/kmain.fi             the root of the x86-64 build.
kernel/kmain_a64.fi         the root of the AArch64 build.
```

**No line names a machine.** Round ARM had one -- an
`import arch.x86_64.machine` in `arch.fi` that would have had to be edited to
build for the other side -- because `#[arch(...)]` did not exist yet. It does
now, so `kernel/arch/machine.fi` carries both bodies of every operation and
`--target=` alone decides which half is compiled. A boundary you have to edit
is a switch.

What the attribute does, measured before it was relied on: the body that does
not belong to the active machine is **dropped before it is checked** -- an
`asm("out dx, al", in("dx") …)` inside an `#[arch(x86_64)]` function does not
even produce an "unknown register name 'dx'" when building for aarch64. And
the compiler insists that every NAME has a body for the machine being built,
so this file cannot quietly forget half of itself.

What each side answers:

| subject | x86-64 | AArch64 |
|---|---|---|
| startup | `boot.s` + `start.s`: Multiboot, protected mode → long mode | `start.S`: already 64-bit, descends EL2 → EL1 |
| page tables | `machine.fi` `page_root`, CR3 | `mmu.S`: TTBR0 **and** TTBR1, MAIR, TCR |
| exception entry | `isr.s`: 256 stubs, picked by NUMBER | `vectors.S`: 16 entries, picked by SITUATION |
| what an exception does | `trap.fi` | `probe.S` `arch_exception` |
| interrupt controller | `apic.fi`: local APIC + I/O APIC | `gic.S`: GICv2 distributor + CPU interface |
| timer | `idt.fi`: 8254, calibrated against nothing | `timer.S`: CNTFRQ_EL0 states the rate |
| context switch | `switch.s`: 7 registers, `ret` finds its way | `switch.S`: 13 registers, x30 by hand |
| barriers, atomics | `machine.fi`, and TSO does most of it | `atomic.S`: acquire/release, `dmb`, `dsb` |
| device registers | `in`/`out`, an address space of their own | memory, a device attribute, and a barrier |
| serial console | `serial.fi` → 16550 at 0x3F8 | `uart.S` → PL011 at 0x09000000 |
| storage/network | `virtio.fi` over PCI | virtio over MMIO, 32 fixed slots |
| starting the others | `smp.s` + `smp.fi`: INIT/SIPI | PSCI — not done this round |

---

## 3. What moved, exactly

Ten branches are running in this repository at the same time. So: the moves
are `git mv`, nothing was rewritten while it was moved, and here is the
complete list so the other branches can rebase without guessing.

**Commit `Round ARM, step B1`** — six files, no line of assembly changed:

```
kernel/boot.s    -> kernel/arch/x86_64/boot.s
kernel/start.s   -> kernel/arch/x86_64/start.s
kernel/isr.s     -> kernel/arch/x86_64/isr.s
kernel/switch.s  -> kernel/arch/x86_64/switch.s
kernel/smp.s     -> kernel/arch/x86_64/smp.s
kernel/hv.s      -> kernel/arch/x86_64/hv.s
```

and the fourteen scripts that name them by path: `tools/build-kernel.sh`,
`tools/core/run.sh`, `tools/freestanding/run.sh`, `tools/hv/run.sh`,
`tools/k18/run.sh`, `tools/kernel/run.sh`, `tools/kernel/karte.py`,
`tools/net/run.sh`, `tools/osum/run.sh`, `tools/pci/run.sh`,
`tools/posix/run.sh`, `tools/smp/run.sh`, `tools/unix/run.sh`,
`tools/userland/run.sh`.

**Commit `Round ARM, step B2+B3`** — eight Firn modules:

```
kernel/apic.fi   -> kernel/arch/x86_64/apic.fi
kernel/idt.fi    -> kernel/arch/x86_64/idt.fi
kernel/trap.fi   -> kernel/arch/x86_64/trap.fi
kernel/guard.fi  -> kernel/arch/x86_64/guard.fi
kernel/user.fi   -> kernel/arch/x86_64/user.fi
kernel/smp.fi    -> kernel/arch/x86_64/smp.fi
kernel/hv.fi     -> kernel/arch/x86_64/hv.fi
kernel/vmcb.fi   -> kernel/arch/x86_64/vmcb.fi
```

Nineteen `import` lines in `kernel/*.fi` become `import arch.x86_64.<name>`.
The USE sites do not change at all — `apic.eoi(...)` is still
`apic.eoi(...)`, because the module keeps its short name. Inside
`kernel/arch/x86_64/` the imports of the moved modules also do not change:
the search runs relative to the importing file first. One path in
`tools/gfx/run.sh` follows.

New files: `kernel/arch/arch.fi`, `kernel/arch/x86_64/machine.fi`,
`kernel/arch/aarch64/*` (9), `tools/arm/*` (4), `tools/arch/*` (3).
`kernel/serial.fi` keeps its exports and its signatures; the bodies of
`out8`, `in8` and `io_wait` now forward across the boundary.

**Round OSUM-ARM2** moved one more file and deleted six:

```
kernel/arch/x86_64/machine.fi -> kernel/arch/machine.fi   (it is both machines now)

deleted, because kernel/arch/aarch64/amain.fi says the same in Firn:
  kernel/arch/aarch64/probe.S   kernel/arch/aarch64/uart.S
  kernel/arch/aarch64/mmu.S     kernel/arch/aarch64/gic.S
  kernel/arch/aarch64/timer.S   kernel/arch/aarch64/atomic.S
```

New: `kernel/kmain_a64.fi`, `kernel/arch/aarch64/amain.fi`,
`kernel/arch/aarch64/virt.fi`, `tools/arch/order.sh`, `tools/arch/a64gap.sh`.
Changed bodies, no changed signatures: `atomic.fi`, `tasks.fi`, `virtio.fi`,
`nvme.fi`, `mem.fi`, `blk.fi`, `ansi.fi`, `wm.fi`, `wig.fi` -- each of them
gained `import arch.arch` and lost its inline assembly. `vendor/firn/COMMIT`
moved from `c66c6bcd` to `a751b3dbf`.

**Which files were deliberately NOT moved, and why.** `serial.fi` (38
importers), `kstate.fi` (55), `sched.fi` (18), `mem.fi` (14), `cpu.fi` (11),
`atomic.fi` (9), `fb.fi`, `wm.fi`, `font.fi`, `kbd.fi`, `fs.fi` — every one
of them is either being edited on another branch right now (OFS3, DISPLAY,
TILING, I18N, …) or has so many importers that moving it would collide with
every branch at once. They are machine layer and they belong behind the
line; moving them is the first job of the next round, when fewer branches
are open.

### The x86-64 path did not move -- the numbers

The promise of a boundary is that nothing changes behaviour. That is not
something you can inspect; it has to be run. So: `./test.sh` in a **pristine
worktree of `main`** and in the branch, at the same time, on the same
machine. Round OSUM-ARM2's run, on a quiet machine:

```
BEFORE (main)          20 sections passed, 3 failed, 2170 proofs
AFTER  (branch arm)    21 sections passed, 3 failed, 2218 proofs
```

and runner for runner:

| runner | before | after | | runner | before | after |
|---|---|---|---|---|---|---|
| FREESTANDING | 41/0 | 41/0 | | UNIX | 107/0 | 107/0 |
| CORE | 46/0 | 46/0 | | NET | 75/0 | 75/0 |
| KERNEL | 176/0 | 176/0 | | GUARD | 55/0 | 55/0 |
| OSUM | 130/0 | 130/0 | | K11 | 85/0 | 85/0 |
| PCI | 98/0 | 98/0 | | WM | 103/0 | 103/0 |
| POSIX | 134/0 | 134/0 | | HV | 114/0 | 114/0 |
| SMP | 59/0 | 59/0 | | K13 | 87/12 | 87/12 |
| USERLAND | 91/0 | 91/0 | | K14 | 137/13 | 137/13 |
| CAPS | 67/0 | 67/0 | | K16 | 39/3 | 39/3 |
| BOOT | 20/0 | 20/0 | | K15 | 251/0 | 251/0 |
| GFX | 76/0 | 76/0 | | K18 | 170/0 | 170/0 |
| | | | | **ARM** | -- | **48/0** |

`diff` on the two lists of tallies has exactly one line in it, and it is the
new section. **2218 - 2170 = 48**, which is the ARM section and nothing else.
So: the tree that moved sixteen files, rewired nine modules through a new
boundary, replaced 1,166 lines of AArch64 assembly with Firn and changed the
compiler it is built with produces, on x86-64, the same numbers as the tree
that did none of that.

**It is not 24 sections green, and it was not before this round either.**
Three runners fail on untouched `main` with exactly the numbers they fail
with here: `K13` 87/12 (`su`, `id` and the `noperm` counter-checks), `K14`
137/13 (the `novfs` counter-checks and the root disk comparison), `K16` 39/3
(`fas` cannot bind five programs, and the compiler source is not where the
runner looks for it). Inherited, not caused, and this round did not go
looking for their cause.

**And a note on the measuring machine**, because the first attempt at this
was noisy. Under heavy load -- five other acceptance runs at once -- `PCI`,
`SMP`, `NET`, `USERLAND` and `GFX` flake in BOTH trees, in both directions,
with failures like "no such file: big.ppm" and "the shell never said it was
ready". They are the runners that photograph the screen through the QEMU
monitor or wait on a serial line with a time limit. The table above was taken
on a quiet machine and every runner in it is stable. A separate finding from
the same hunt, and nothing to do with ARM: running the suite with `TMPDIR` on
a tmpfs turns `tools/kernel/run.sh` from 176/0 into 151/23, in both trees.
With the ordinary `TMPDIR` it is 176/0 again, in 87 seconds. Worth knowing
before somebody debugs it as a regression.

### The new section 25

`./test.sh` grew one section: `tools/arm/run.sh`, **39 proofs, 0 failures**.
It does not build Osum for AArch64 — see section 6 for why it cannot yet.

---

---

## 4. What the AArch64 side does, measured

Built by `tools/arm/build.sh`, run by `tools/arm/run.sh`:
**48 proofs, 0 failures**, of which 6 are counter-checks.

**And it is Firn.** `kernel/kmain_a64.fi` -> `kernel/arch/aarch64/amain.fi`
is compiled with `--target=aarch64-none` and drives the UART, builds the page
tables, brings up the GIC, arms the timer, handles the exceptions and runs
the two tasks. 688 lines of Firn against 419 lines of assembly, and the
assembly is the same three things it is on x86-64: the machine before there
is a stack (`start.S`, plus `osum_panic`), the sixteen vector entries of
0x80 octets each (`vectors.S`), and swapping the stack pointer under a
running function (`switch.S`). The runner checks the claim rather than
repeating it: 111 symbols in the image carry firnc0's `_F0.` prefix,
`_F0.amain__kmain` and `_F0.arch__dev_write32` among them, and the kernel
prints `language=firn` on a line it produced itself.

Two more lines than round ARM had, and both are about the boundary rather
than the hardware:

| what | the number |
|---|---|
| `arch.has_io_ports()` | **0** here. The same source line answers 1 on x86-64. |
| `arch.atomic_store` then `arch.atomic_load` | 0x5ec0de out and back -- a `stlr` and an `ldar` on this machine, a plain store and load on the other |

| what | the number |
|---|---|
| first octet on the PL011 | 54.8 ms median of 5 (49.7 .. 61.0), QEMU's own start included — an upper bound |
| to the last line | 1077.2 ms median of 5 (1066.9 .. 1086.6); 1000 ms of that is the 100 timer ticks at 100 Hz |
| image | 85,256 octets, ELF64 AArch64, entry 0x40080000 |
| exception level | EL1, read out of `CurrentEL` |
| deliberate `svc #0` | caught at vector entry 4, ESR_EL1 class 0x15, `eret` returns |
| MMU | SCTLR_EL1.M reads back 1 out of the processor |
| a page mapped by hand | VA 0x80000000 through three levels, `0x0badc0de0ddba11` written through the mapping and read back through the physical address |
| TTBR1 | the same octet at 0x40080000 and at 0xffffff8040080000 |
| CNTFRQ_EL0 | 62,500,000 Hz, stated by the machine, nothing calibrated |
| timer interrupts | 100 of them, INTID 27, through the GICv2 |
| context switches | 20, pattern `ABABABABABABABABABAB` |
| virtio-mmio | 32 slots answer with 0x74726976; 0 name a device with nothing attached, 2 with a disk and a net card attached |
| addresses | all 11 checked against the device tree QEMU dumps (`tools/arm/dtb.py`) |

The counter-checks, because a property without one is a claim:

| switch | what must happen | what happened |
|---|---|---|
| `-DNO_MMU` | the page proof must not come out right | data abort, ESR 0x96000050 (class 0x25), FAR 0x80000000, and no page line printed at all |
| `-DNO_AF` | descriptors without the access flag must not work | the machine goes SILENT after `svc=` — see section 5 |
| `-DNO_TIMER_IRQ` | the tick count must never be reached | the run has to be stopped by the time limit |
| `-DNO_EOI` | acknowledged but never finished | exactly one interrupt, then nothing; the run stalls after `freq=` |
| no devices attached | 0 virtio device IDs | 0 |
| two devices attached | 2 | 2 |

---

## 5. The traps

Round 80 of the compiler documented two that are worth their weight:
`.align 8` means 8 octets on x86 and 2^8 = 256 on AArch64, and syscall 1 is
`write` on x86 and `io_destroy` on ARM. Here are the ones this round hit, in
the order of how expensive they were.

### 5.1 The vector table entries are 128 octets, and nothing says so

The first `vectors.S` put the whole register save inside each of the sixteen
entries — about 200 octets each. `.balign 128` in front of an entry that is
already longer than 128 simply starts the NEXT one late, and everything
shifts. The assembler said nothing. **What it looked like from outside: a
deliberate `svc #0` at EL1h reported as entry 2 instead of entry 4, with the
correct ESR value attached.** Nothing crashed; a number was quietly wrong,
in a way a table of function pointers on x86 cannot be wrong. Each entry is
now four instructions and jumps to a common part.

### 5.2 The access flag is not optional, and it fails in silence

Bit 10 of a descriptor (AF) clear means "never touched", and the hardware
takes an access flag fault the first time the page is used. `-DNO_AF` builds
descriptors identical in every other bit. The result is not a wrong value
and not a fault report: **the machine goes dead.** The instruction after
`mmu_init` cannot be fetched, the fault vector cannot be fetched either, and
the processor loops in an exception it can never take. The x86 page table
format has no such bit and nothing reminds you to set it.

### 5.3 `TG0` and `TG1` encode the same granule with different numbers

In TCR_EL1, a 4 KiB granule is `TG0 = 0` and `TG1 = 2`. One digit. A wrong
one gives a translation fault on the first high-half address and no other
symptom.

### 5.4 The compiler checks registers, not instructions

Measured with `tools/arch/a64gap.sh`. The AArch64 back end refuses
`in("dx")` with "unknown register name". It does not look at the mnemonic.
So this compiles for `aarch64-none` without a word:

```firn
fn fence() { asm("mfence") }
fn halt()  { asm("hlt") }
```

and `aarch64-linux-gnu-as` says, three steps later,
`unknown mnemonic 'mfence'`. **`hlt` is the dangerous one: AArch64 HAS an
instruction of that name, it takes an immediate, and it means "trap to the
debugger" and not "wait for an interrupt".** `asm("hlt #0")` would assemble
without complaint and do something else entirely. In Osum this hit `atomic.fi` and `virtio.fi`; both went through the boundary
in round OSUM-ARM2 and the class is down to one module. The compiler gap
itself is unchanged and is item 3 of section 10 -- one module in that class
is one too many, because the class is invisible without this test.

### 5.5 There are no I/O ports, and that is a concept, not a keyword

`in`/`out` address a separate sixteen-bit space with their own instructions
that the processor does not reorder against memory. AArch64 has neither.
`kernel/fb.fi` drives the graphics through the ports 0x1CE/0x1CF, `blk.fi`
drives ATA through 34 port lines, `pci.fi` reaches configuration space
through 0xCF8/0xCFC. None of that is a rewrite of syntax; each one needs a
different way of finding the device in the first place. This is why
`arch.fi` speaks of `dev_out8`/`dev_read32` and offers `has_io_ports()`: a
caller that genuinely needs a port asks, and on the machine that has none it
gets `false` and must be rewritten rather than silently writing into 0x3F8.

### 5.6 QEMU does not hand over the device tree with `-kernel <ELF>`

x0 arrives as 0. Measured, printed as `dtb=0x0000000000000000` in every run.
That is why `virt.inc` holds the addresses as constants and why
`tools/arm/dtb.py` exists to check them against what QEMU dumps — a device
tree parser would have nothing to parse. A Raspberry Pi and U-Boot DO pass
the pointer, so the parser is work for a later round and the constants are a
QEMU-only shortcut, named as one.

### 5.7 Use the virtual timer

The physical timer of the architecture is reachable from EL1 only if EL2
lets it through (`CNTHCTL_EL2.EL1PCEN`). CNTV_* is readable at EL1 either
way, and with `CNTVOFF_EL2 = 0` it counts the same ticks. INTID 27.

### 5.8 GICC_EOIR is not optional either

Reading GICC_IAR takes the interrupt and raises the running priority.
Writing the number back to GICC_EOIR lowers it. Skip the second and the
controller never delivers anything of equal or lower priority again — the
machine goes quiet with no message. That is the `-DNO_EOI` counter-check,
and it stalls after `freq=`, one interrupt in.

---

## 6. How much of the kernel already compiles for AArch64

`tools/arch/a64probe.sh`, **with the compiler this repository pins**
(`vendor/firn/COMMIT` = `a751b3dbf`). Round ARM had to borrow a
work-in-progress binary from the Firn repository for this number and said so;
it does not any more.

The control run matters: with `--target=x86_64-none`, `kernel/kmain.fi` and
everything it imports compiles freestanding with **0 errors**. So the
compiler is not the variable.

A module counts as unchanged only if it produces no error of its own AND
holds no inline assembly at all. The second condition is not pedantry -- see
§5.4: the back end checks register NAMES, not instructions, so `asm("mfence")`
passes the compiler and dies in the assembler.

Of the 55 modules under `kernel/` that pass the control:

| | round ARM | now | lines now |
|---|---:|---:|---:|
| unchanged for `aarch64-none` | 31 of 53 | **40 of 55** | 30,155 |
| pass the register check, carry x86 instructions | 2 | 1 | 533 |
| rejected by the compiler outright | 20 | 14 | 14,135 |
| **share unchanged** | 58.5 % | **72.7 %** | **67.3 %** |

The nine that crossed over in this round, and what it took:

| module | what it held | what it says now |
|---|---|---|
| `atomic.fi` | `pause`, `mfence`, `cli`, `hlt` | `arch.pause`, `arch.barrier`, `arch.irq_off`, `arch.idle` |
| `tasks.fi` | `pause` | `arch.pause` |
| `virtio.fi` | `pause`, `lfence` | `arch.pause`, `arch.barrier_read` |
| `nvme.fi` | `pushfq/pop`, `hlt` | `arch.irq_are_on`, `arch.idle` |
| `mem.fi` | `pushfq/pop/cli`, `sti` | `arch.irq_save`, `arch.irq_restore` |
| `blk.fi` | `in ax, dx` / `out dx, ax` | `arch.dev_in16` / `arch.dev_out16` |
| `ansi.fi` | `lea rax, [rip + kdata]` | `arch.kdata_base` |
| `wm.fi` | `rep stosq`, `rep movsq` | `arch.fill_words`, `arch.copy_words` |
| `wig.fi` | `rep movsb` (twice) | `arch.copy_octets` |

Two of those are worth a sentence each.

**`blk.fi` did not become portable, and that is the honest outcome.** ATA
lives in the I/O port space and there is no such space here. What changed is
that the driver now asks the boundary for a port access instead of emitting
one, and on AArch64 the boundary answers with `brk #1` -- a synchronous
exception whose return address points at the caller. A driver for a disk this
machine does not have should stop loudly at the instruction, not write into
whatever happens to sit at 0x1F0.

**`wm.fi` and `wig.fi` gave up a hot path, and it was measured.** `rep stosq`
and `rep movsq` are one instruction on x86-64 and the window server's fill
and blit run on them. `arch.fill_words` keeps exactly that instruction on
x86-64 -- the same octets -- and is a loop on AArch64. The x86 image got
3,728 octets SMALLER for it, because four copies of the same asm block became
one function. A better AArch64 loop (`ldp`/`stp` pairs, or FEAT_MOPS `cpy` on
a newer core) now has ONE place to land instead of four.

`kernel/arch/x86_64/` is not counted. Those files are x86 by construction --
counting them would be measuring how portable a port is.

**What is left, and why.** The fourteen that the compiler still rejects are
`fb.fi` (the graphics ports 0x1CE/0x1CF), `pci.fi` (0xCF8/0xCFC), `proc.fi`
and `sched.fi` (CR3 and the ring change), `sys.fi`'s caller `kmain.fi`,
`signal.fi` (an indirect `call rax` into the assembly), `rand.fi`
(`cpuid`/`rdrand`/`rdseed`), `time.fi` (`rdtsc` calibration), `uprog.fi`
(`syscall`), `pwr.fi`, `power.fi`, `ps2m.fi`, `core.fi` and `kcore.fi` (the
round-52 demo kernels, which are x86 on purpose). Every one of those needs a
DECISION about the hardware, not a rewrite of a line -- which is exactly the
boundary between what this round could finish and what the next one has to
design.

## 7. The weak memory model

x86-64 is TSO: a store is never seen out of order with an older store, a load
never with an older load. AArch64 promises neither. Code that ran correctly
on x86 by accident is wrong here, and it does not announce itself -- it
produces a value that is stale on one processor out of four, rarely.

`kernel/atomic.fi` stated the problem in its own header, in 2025:

> On x86-64 an ALIGNED 64-bit read or write is atomic in the hardware …
> So `load` and `store` below are `__mmio_read64`/`__mmio_write64` and
> nothing else, and the pair is a correct atomic load/store on this
> architecture. **On a machine with a weaker memory model it would not be,
> and then this file is the one place that has to change.**

Round ARM found that the sentence was half right and could not act on it.
This round did.

### 7.1 The lock TAKE was already right -- measured, not assumed

`atomic.cas` is `__atomic_swap`, and the AArch64 back end lowers it to

```
.La64_cas:  ldaxr x9, [x10]        // load-ACQUIRE exclusive
            cmp   x9, x11
            b.ne  out
            stlxr w14, x13, [x10]  // store-RELEASE exclusive
            cbnz  w14, .La64_cas
out:        clrex
```

`__atomic_add` the same. So `lock_take` and `lock_try` carry acquire
semantics on AArch64 for free.

### 7.2 The lock GIVE was wrong. It is not any more.

Before:

```firn
fn store(p: u64, v: u64) { __mmio_write64(p as *mut u64, v) }
fn lock_give(state: u64, id: u64) { store(slot(state, id) + OWNER, 0) }
```

`__mmio_write64` lowers to a plain `str` on AArch64 -- no `stlr` anywhere in
the emitted text. On x86 that is a correct release. On AArch64 the unlocking
store can become visible before the data the holder wrote, and another
processor takes the lock and reads what was there before.

After: `atomic.load` and `atomic.store` go through `arch.atomic_load` and
`arch.atomic_store`, and `kernel/arch/machine.fi` answers with the same two
MMIO forms on x86-64 -- octet for octet what round K5 wrote -- and with
`ldar`/`stlr` on AArch64. `kernel/atomic.fi` now holds **zero inline assembly
blocks**; it had four.

`tools/arch/order.sh` reads all of that out of the emitted assembler of both
machines. **15 proofs, 0 failures**, and three of them are the checks that
make the other twelve mean something:

* **x86-64 did not get slower for it.** `atomic_store` is a plain store, no
  `lock` prefix, no `xchg`. A release store that quietly became a locked
  instruction would be correct and forty times slower, and nobody would
  notice for a year.
* **`idle` on AArch64 is `wfi` and NOT `hlt`.** `hlt` exists here and means
  "trap to the debugger" (§5.4).
* **The counter-check to the method itself:** a plain `__mmio_write64`
  compiled for aarch64 still comes out as a bare `str`. If it did not, the
  `stlr` above would prove nothing about the boundary, because the compiler
  would be emitting release stores by itself.

### 7.3 A store-store fence written by hand, in an instruction that does not exist here

`kernel/arch/x86_64/smp.fi:509..511`:

```firn
atomic.store(sp(state, S_DONE), 0)
atomic.barrier()
atomic.store(sp(state, S_PHASE), ph)
```

Whoever wrote that knew what they were doing. `atomic.barrier()` is now
`arch.barrier()`, which is `mfence` on x86-64 and `dmb sy` on AArch64, so
this line has stopped being a landmine. The file itself is still x86-only --
it starts processors with INIT/SIPI -- but the ordering it relies on now has
a name on both machines.

### 7.4 STILL OPEN: a handshake with no fence at all

`kernel/arch/x86_64/smp.fi:257..285`. The parameter block for a processor
about to be woken is filled:

```firn
atomic.store(param + P_CR3,   ...)
atomic.store(param + P_KDATA, state)
atomic.store(param + P_ENTRY, ...)
...
atomic.store(param + P_STACK, top)
atomic.store(param + P_CPU,   k)
atomic.store(param + P_FLAG,  0)
wake(state, cpu.apic_id(state, k), base >> 12)
```

and the woken processor reads CR3, the stack and the entry point out of it.
**There is no barrier between filling the block and waking the processor.**
On x86-64 that is correct and needs none. On AArch64 the wake-up can overtake
the block and the new processor starts with a stack pointer that has not been
written yet.

Since 7.2 the individual stores are release stores on AArch64, which happens
to close most of this hole -- a release store cannot be reordered before the
stores that precede it. That is luck, not design, and it is written down here
as luck. The `wake()` itself is an MMIO write to the APIC and is not ordered
against them by anything. The fix is one `arch.barrier_device()` before
`wake`, and it is not in this round because there is no second processor on
the AArch64 side to measure it with, and a barrier added blind is a comment
with a cost.

### 7.5 What the scheduler needs

`kernel/sched.fi` touches shared state only inside `lock_take`/`lock_give` --
thirteen bracketed regions, checked. **So the scheduler needs no change of
its own now that `lock_give` is a store-release.** What it still needs is the
six x86 instructions in it: `pushfq/pop/cli` and `sti`
(`arch.irq_save`/`irq_restore` exist), `mov rax, cr3` and `mov cr3, rax`
(`arch.page_root`/`page_root_set` exist), `hlt` (`arch.idle` exists), and
`call rax` into the assembly switch. Every one has a name on the other side
already; what is missing is an AArch64 task structure to point them at.

### 7.6 The device drivers

`nvme.fi` and `virtio.fi` fill a descriptor and then write a doorbell. On x86
the older store is visible first, guaranteed. On AArch64 the device can read
a descriptor still sitting in a store buffer. `arch.barrier_device()` exists
for exactly that call site -- `sfence` on x86, `dsb sy` on AArch64 -- and
`amain.fi` uses it after every device register write. In `nvme.fi` and
`virtio.fi` it is still not called: they run on hardware this machine does
not have, and putting a barrier in a path nothing exercises would be a
change nobody could measure. Named so it is not forgotten.


## 8. What the boundary costs

Measured, not assumed, and the answer changed sign in this round.

Round ARM: the pinned compiler does not inline across modules, so
`serial.out8` went from one frame to three and the x86 image grew by 2,804
octets (+0.16 %).

Round OSUM-ARM2, after nine more modules crossed:

```
1,710,512 octets   before this round's rewiring
1,706,784 octets   after
   -3,728 octets   (-0.22 %)
```

The image got SMALLER. The reason is not clever code generation, it is that
four copies of `rep movsq`/`rep stosq` inline assembly in `wm.fi` and
`wig.fi` became one function each. An interface that removes duplication pays
for its own call frames; one that does not, does not. Both numbers are in
here because only having the second one would be a nicer story than the
truth.

For a device port the trade was never in doubt: an `out` is a bus cycle,
hundreds of processor cycles, and two extra calls are single digits. For the
MMIO forms it is a worse trade, and that is why the fast paths of `nvme.fi`
and `virtio.fi` still hold their own `__mmio_*` calls.


## 9. What deliberately stays out

* **The hypervisor.** `kernel/arch/x86_64/hv.fi` and `hv.s`, 2,388 lines,
  AMD-V with a VMCB. The AArch64 counterpart is EL2 and is not the same
  design in another notation. It is not ported, it will not be ported by
  the next round either, and `arch.fi` has no entry for it — putting an
  interface in front of something with one implementation for ever is
  decoration.
* **SMP on AArch64.** The others are woken with PSCI `CPU_ON` rather than
  INIT/SIPI. `start.S` parks them in a `wfe` loop and that is all. Nothing
  in section 4 involves a second processor, so nothing in section 4 is a
  claim about one.
* **Graphics on AArch64.** `-M virt` has no VGA and no 0x1CE/0x1CF; a frame
  buffer there means either `ramfb` or a virtio-gpu, and both want the
  device tree that section 5.6 says we do not get. Untouched.
* **The device tree.** See 5.6. The addresses are constants checked against
  a dump.
* **The historical round documents.** `docs/ROUND52.md`, `ROUND59.md`,
  `ROUNDK5.md` and the rest still say `kernel/boot.s`. They describe what
  was true in their round and they were left alone on purpose; the moves are
  in section 3.

---

## 10. What the next round needs

1. **An AArch64 process.** Everything below the scheduler now has a name on
   both machines (§7.5); what does not exist is a task on this side -- a
   context in the task table, a page table per address space, and the drop to
   EL0 that is this machine's ring 3. `kernel/arch/x86_64/user.fi` is 268
   lines and it is the shape of what has to be written.
2. **`smp.fi`'s missing barrier (§7.4)**, and a second processor on the ARM
   side to measure it with. PSCI `CPU_ON` instead of INIT/SIPI; `start.S`
   already parks the others in a `wfe` loop.
3. **The instruction check in the compiler (§5.4).** The register-only check
   still lets operand-less x86 mnemonics through to the assembler. One module
   is still in that class, and it is one module too many.
4. **A driver for virtio-mmio.** §4 proves the slots are there and that
   attaching a device changes what they say. Reading a block off one of them
   is the step that makes a RAM disk, then a file system, then a shell.
5. **`fb.fi` and `pci.fi`**, which are the two biggest remaining refusals and
   are refusals of the same kind: both find their hardware through the port
   space. On `-M virt` there is no VGA and no PCI configuration space at
   0xCF8 -- there is a device tree, and §5.6 says why we do not have it yet.
   That is a design decision, not a rewrite.
6. **`firnc1` on AArch64.** The self-hosted compiler refuses
   `--target=aarch64-*` and says so, so `tools/arm/build.sh` has no
   `--stufe 1`. Until it does, the ARM image is built by one compiler and the
   x86 image by two, and only the x86 one has that particular check under it.
