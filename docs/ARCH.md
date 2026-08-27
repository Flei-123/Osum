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

---

## 2. Where the line runs

```
kernel/*.fi                 the kernel. No knowledge of a machine.
kernel/arch/arch.fi         THE BOUNDARY. One file. It asks the questions,
                            and ONE LINE IN IT names the machine.
kernel/arch/x86_64/         the x86-64 answers. 9 assembly and 8 Firn files,
                            6,853 lines.
kernel/arch/aarch64/        the AArch64 answers. 9 assembly files,
                            1,528 lines. No Firn yet, see section 6.
```

The one line is

```firn
import arch.x86_64.machine
```

in `kernel/arch/arch.fi`. Firn's module system addresses a module under the
LAST part of its path (`compiler/src/modules.rs`), so everything below that
line says `machine.out8(...)` and does not know which machine it got. When
the AArch64 side can be compiled from Firn, that line becomes
`import arch.aarch64.machine` and nothing above the boundary changes. That
is the only test of whether a boundary is in the right place.

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

**Which files were deliberately NOT moved, and why.** `serial.fi` (38
importers), `kstate.fi` (55), `sched.fi` (18), `mem.fi` (14), `cpu.fi` (11),
`atomic.fi` (9), `fb.fi`, `wm.fi`, `font.fi`, `kbd.fi`, `fs.fi` — every one
of them is either being edited on another branch right now (OFS3, DISPLAY,
TILING, I18N, …) or has so many importers that moving it would collide with
every branch at once. They are machine layer and they belong behind the
line; moving them is the first job of the next round, when fewer branches
are open.

---

## 4. What the AArch64 side does, measured

Built by `tools/arm/build.sh`, run by `tools/arm/run.sh`:
**39 proofs, 0 failures**, of which 6 are counter-checks.

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
without complaint and do something else entirely. In Osum, `atomic.fi` and
`virtio.fi` are exactly this case: they pass the register check and would
die in the assembler. They are counted as NOT ported in section 6.

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

`tools/arch/a64probe.sh`, with the WIP compiler of the parallel Firn round
ARM-FREESTANDING (`/root/firn-arm`, commit `cbf17d3a0`, "the two axes of a
target"). **Not** with the compiler `vendor/firn/COMMIT` pins — that one
answers `--target=aarch64-linux` with "does not support the kernel profile
yet (round 80)". The number below is a number about that binary on that day.

The control run matters: with `--target=x86_64-none`, `kernel/kmain.fi` and
everything it imports compiles freestanding with **0 errors**. So the
compiler is not the variable.

Of the 53 modules under `kernel/` that pass the control:

| | modules | lines |
|---|---:|---:|
| unchanged for `aarch64-none` (no inline assembly, no error) | **31** | 24,178 |
| pass the register check but carry x86 instructions the assembler would reject (section 5.4) | 2 | 1,178 |
| rejected by the compiler outright | 20 | 18,605 |
| **share unchanged** | **58.5 %** | **55.0 %** |

The 31: `acpi`, `batt`, `bootmod`, `cap`, `cpu`, `devfs`, `elf`, `errno`,
`fat`, `file`, `font`, `fs`, `ftype`, `hw`, `inet`, `kbd`, `kstate`, `mnt`,
`netsvc`, `nidx`, `ofs`, `part`, `perm`, `procfs`, `serial`, `sys`, `ttf`,
`tty`, `uio`, `vfs`, `vfsops`.

`serial.fi` is in that list **because of step B**: before this round it held
two `asm` blocks with x86 register names, and now it forwards across the
boundary. That is one file's worth of evidence that the boundary is in a
useful place, and it is the only such evidence this round produced.

`kernel/arch/x86_64/` is not counted. Those files are x86 by construction —
counting them would be measuring how portable a port is.

---

## 7. The weak memory model

x86-64 is TSO: a store is never seen out of order with an older store, a
load never with an older load. AArch64 promises neither. Code that ran
correctly on x86 by accident is wrong here, and it does not announce itself
— it produces a value that is stale on one processor out of four, rarely.

`kernel/atomic.fi` states the problem in its own header, in 2025:

> On x86-64 an ALIGNED 64-bit read or write is atomic in the hardware …
> So `load` and `store` below are `__mmio_read64`/`__mmio_write64` and
> nothing else, and the pair is a correct atomic load/store on this
> architecture. **On a machine with a weaker memory model it would not be,
> and then this file is the one place that has to change.**

This is that machine. What the audit found, and it is not all bad news.

### 7.1 The lock TAKE is already right — measured, not assumed

`atomic.cas` is `__atomic_swap`, and the AArch64 back end lowers it to

```
.La64_cas:  ldaxr x9, [x10]      // load-ACQUIRE exclusive
            cmp   x9, x11
            b.ne  out
            stlxr w14, x13, [x10]  // store-RELEASE exclusive
            cbnz  w14, .La64_cas
out:        clrex
```

`__atomic_add` the same. So `lock_take` and `lock_try` carry acquire
semantics on AArch64 for free, and nothing after them can be hoisted above
them. Read out of `--emit=asm`, not out of a manual.

### 7.2 The lock GIVE is wrong, and it is the one real defect

```firn
fn store(p: u64, v: u64) { __mmio_write64(p as *mut u64, v) }
fn lock_give(state: u64, id: u64) { store(slot(state, id) + OWNER, 0) }
```

`__mmio_write64` lowers to a plain `str` on AArch64 — measured, no `stlr`
anywhere in the emitted text. On x86 that is a correct release, because the
hardware will not move it ahead of the stores it protects. **On AArch64 the
unlocking store can become visible before the data the holder wrote.**
Another processor takes the lock, reads the protected structure, and sees
what was there before.

That is one function. `kernel/arch/aarch64/atomic.S` already has the answer
— `stlr` plus `dsb ishst` plus `sev` — and the same file's `lock_take` uses
`wfe` so the waiters really sleep. What is missing is the Firn side, and it
is missing because the compiler cannot yet build it.

`atomic.load` has the same gap in the other direction: a plain `ldr`, where
a lock-free reader needs `ldar`. It is used lock-free in exactly two places,
both found:

* `kernel/time.fi:331..337`, `mono_ns` — the monotonic clock's
  compare-and-swap loop reads the cell with `atomic.load` before and after
  the CAS. The CAS is fine; the two reads are not ordered.
* `kernel/arch/x86_64/smp.fi`, the bring-up handshake, see below.

### 7.3 A store-store fence that was written by hand, and does not exist here

`kernel/arch/x86_64/smp.fi:509..511`:

```firn
atomic.store(sp(state, S_DONE), 0)
atomic.barrier()
atomic.store(sp(state, S_PHASE), ph)
```

Whoever wrote that knew what they were doing — and `atomic.barrier()` is
`asm("mfence")`, which does not exist on AArch64 and, per section 5.4, would
pass the compiler and die in the assembler.

### 7.4 A handshake with no fence at all, which x86 made correct by accident

`kernel/arch/x86_64/smp.fi:257..285`. The parameter block for a processor
that is about to be woken is filled:

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

and the woken processor reads CR3, the stack and the entry point out of that
block. **There is no barrier between filling the block and waking the
processor.** On x86-64 that is correct and needs no barrier: stores are seen
in program order. On AArch64 the wake-up can overtake the block, and the new
processor starts with a stack pointer that has not been written yet. On the
receiving side, `atomic.load(param + P_FLAG)` is a plain `ldr`, so the
waiting loop can also read a stale flag for ever.

Nothing is wrong with this code today. It is the clearest example in the
whole kernel of the thing that has to be looked for: **the absence of a
barrier is not visible in the source.** There are 22 `atomic.store` /
`atomic.load` call sites outside `atomic.fi`, all but two of them in
`smp.fi`, and every one of them will have to be read this way.

### 7.5 What the scheduler needs

`kernel/sched.fi` accesses shared state only inside `lock_take` /
`lock_give` — thirteen bracketed regions, checked. **So the scheduler needs
no change of its own once `lock_give` is a store-release.** What it does
need is the six x86 instructions in it: `pushfq/pop/cli` and `sti` for
`irq_save`/`irq_restore` (`arch.fi` already has `irq_save`/`irq_restore`,
`gic.S` already has the AArch64 form), `mov rax, cr3` and `mov cr3, rax` on
the switch path (`arch.page_root` / `arch.page_root_set` exist), `hlt` in
the idle loop (`arch.idle`), and `call rax` into the assembly switch.
Every one of those has a name on the other side already.

### 7.6 The device drivers

`nvme.fi` and `virtio.fi` fill a descriptor in memory and then write a
doorbell register. On x86 the older store is visible first, guaranteed. On
AArch64 the device can read a descriptor that is still in a store buffer.
`arch.barrier_device()` exists for exactly that call site and is `sfence` on
x86 and `dsb sy` on AArch64. It is not yet called anywhere: rerouting
`nvme.fi`'s and `virtio.fi`'s hot paths through the boundary costs two extra
call frames per access (section 8) and there is nothing on AArch64 yet to
measure the change against. Named here so it is not forgotten.

---

## 8. What the boundary costs

Measured, not assumed. The pinned compiler at the optimisation level
`tools/build-kernel.sh` uses does not inline across modules, so

```
serial__out8 -> arch__dev_out8 -> machine__out8 -> `out dx, al`
```

is three frames where it used to be one, and the image grew from 1,707,416
to 1,710,220 octets (**+2,804, +0.16 %**). Read off the disassembly of
`_F0.serial__out8`.

Whether that matters: an `out` to a device port is a bus cycle, hundreds of
processor cycles, and two extra calls are single digits. For the MMIO forms
it is a worse trade, which is why nothing in the fast paths of `nvme.fi` or
`virtio.fi` was rerouted this round. Claiming a boundary is free when it is
not is how a boundary gets torn out again three rounds later.

---

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

1. **The freestanding AArch64 target, finished and pinned.** Part 1 exists
   (`aarch64-none`, the kernel profile accepted). What section 5.4 shows is
   still open: the register check has to become an instruction check, or
   every operand-less x86 `asm` block in the kernel is a landmine. And
   `vendor/firn/COMMIT` has to move, which is the moment this repository
   stops measuring against a compiler it does not control.
2. **`__mmio_read`/`__mmio_write` need acquire/release forms**, or
   `atomic.fi` needs `__atomic_load_acquire`/`__atomic_store_release`.
   Section 7.2 cannot be fixed in Firn without them.
3. **The rest of the move**: `serial.fi`, `kstate.fi`, `sched.fi`,
   `mem.fi`, `cpu.fi`, `atomic.fi`, `fb.fi`, `blk.fi`, `pci.fi`,
   `virtio.fi`, `nvme.fi`, `time.fi`, `rand.fi`, `proc.fi`, `signal.fi`.
   Best done when fewer branches are open (section 3).
4. **An AArch64 `machine.fi` in Firn**, answering `arch.fi` question for
   question. The assembly in `kernel/arch/aarch64/` is the specification for
   it and every function in it already has the right name.
5. **virtio-mmio as a driver, not as a count.** Section 4 proves the slots
   are there and that attaching a device changes what they say. Reading a
   block off one of them is the next honest step, and it is the step that
   makes a RAM disk and then a shell possible.
