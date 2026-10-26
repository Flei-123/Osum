# ACPI, AML and platform events

State of the ACPI stack in `kernel/acpi/`, how events travel from the hardware to the desktop, what is measured where, and
how to run the gate. Older round reports (`docs/ROUNDAML.md`, `docs/RUNDE-ACPI-EREIGNISSE.md`) stay as history; this file is the
current description.

## Modules

| module | responsibility |
|---|---|
| `acpi.fi` | RSDP search, RSDT/XSDT walk, boot snapshot of all tables, MADT (CPUs, I/O APIC), table lookup by signature |
| `irqovr.fi` | MADT interrupt source overrides: ISA IRQ -> GSI, polarity, trigger |
| `amlns.fi` | namespace: nodes, names, search rules, heap |
| `amlobj.fi` | AML objects, operation regions (SystemMemory, SystemIO, PCI_Config, EmbeddedControl), fields, resource descriptors |
| `amlev.fi` | execution: terms, control flow, method calls, limits (steps, depth, stack) |
| `amlskip.fi`, `amlfail.fi` | tolerant loading: structural skipping of unevaluable operands, failure diagnostics |
| `aml.fi` | table loading, `_PRT` evaluation, namespace hold, evaluation entry points (`eval_node*`), snapshot at boot |
| `amlstr.fi` | string, buffer and BCD terms: `Concatenate`, `ConcatenateResTemplate`, `Mid`, `ToString`, `Match`, `ToBCD`, `FromBCD`, string compare, string to integer |
| `amlsys.fi` | predefined objects (`\_OSI` native method, `\_OS_`, `\_REV`, `\_GL_`), `Timer`, `Stall`, event counters (`Wait`, `Signal`, `Reset`) |
| `amlfield.fi` | field list creation, shared by the loader and by `Field` terms executed inside methods |
| `amlsweep.fi`, `amlconf.fi`, `amlfuzz.fi`, `amltest.fi` | test harness inside the kernel: method sweep, conformance runner, load fuzzer, dispatcher by command line word |
| `pm1.fi` | PM1a/PM1b fixed event registers (status, enable, clear) |
| `gpe.fi` | GPE blocks: ports, armed set, status scan, stray GPE disarming |
| `scistorm.fi` | storm guard bookkeeping: empty SCI entries, mask decision, polling cadence |
| `scidiag.fi` | SCI diagnostics: `scix`, `scireg`, `scisnap` lines |
| `acpiev.fi` | SCI handler and `pump`: dispatch of GPE methods and EC queries, lid, battery, AC, power button, Notify handling |
| `ec.fi`, `ecio.fi`, `ecsim.fi` | embedded controller: ports from `_CRS`, `_REG`, byte access, `_Qxx` query, software model |
| `acpibl.fi` | backlight `_BCL`, `_BCM`, `_BQC` |
| `acpidev.fi` | `/proc/acpi` |
| `acpidump.fi` | `/proc/acpidump` (every table as hex rows) |
| `dmar.fi` | DMAR table report |

`kernel/diag/cmdopt.fi` reads kernel command line words and numbers for test knobs (no kstate mode bits needed).

## AML interpreter: what it executes

Terms: arithmetic and logic, comparisons (integers, strings, buffers), `Index`/`DerefOf`/`RefOf`/`CondRefOf`, `Store` and
all conversions, `If`/`Else`/`While`/`Break`/`Continue`/`Return`, method calls (up to 7 arguments, 16 nested calls, 64
nested terms, stack guard), `Name`/`Alias`/`CreateXField`/`OperationRegion`/`Field` also inside methods, `Mutex`/`Event`
(single execution context: `Acquire` succeeds at once, `Wait` consumes a signal or times out), `Notify`, `Timer`,
`Stall` (up to 100 us), `Fatal` (ends the method with `ERR_FATAL`).

Operation regions: SystemMemory (identity-mapped memory), SystemIO, PCI_Config, EmbeddedControl. Fields of any width: up
to 64 bits read as integers, wider fields read and write as buffers.

Not supported, ends the method with a defined error: `Load`, `Unload`, `LoadTable`, `IndexField`, `BankField`, other
address spaces. `Sleep` reads its operand and does not delay.

Safety nets: every error is a number (`amlns.ERR_*`) with the failing opcode or region recorded; the loader is tolerant per
container; method results never keep heap memory that a name or field refers to.

## Boot flow

1. `acpi.snapshot` copies all tables into low memory (UEFI tables may sit in memory the kernel image would shadow).
2. `aml.stage` parses DSDT and SSDTs tolerantly, evaluates `_PRT`, drops the namespace again (4 KiB stay).
3. `acpiev.stage` builds the namespace a second time and keeps it (`aml.ns_hold`), then:
   finds lid, battery, AC and EC devices; collects `\_GPE._Lxx/_Exx` methods and arms exactly those GPE bits;
   enables the fixed power button event; routes the SCI.
4. `acpiev.pump` runs from the idle task and the desktop loop. All AML runs there, never in an interrupt handler.

## SCI routing and protection

The SCI line comes from the FADT (`SCI_INT`). Its GSI, polarity and trigger come from the MADT interrupt source override
for that IRQ (Intel client platforms and QEMU: active high, level; AMD server: active low, level). Without an override the
line is level, active low. Programming the wrong polarity makes an idle line look asserted: an interrupt storm without any
event.

Measured on the HP laptop with the previous kernel (26.10.2026): `/proc/hotkeys` showed `sci irq=193376019` at 3043 s
uptime and 199936347 at 3119 s (about 87 000 entries per second) with `events=0 gpe_fired=0`, CPU 0 busy 72 % while idle.
The MADT of a Surface Laptop 4 and of QEMU carry the SCI override with flags `0xd` (active high), the AMD server `0xf`.
The cause on the HP is the polarity hypothesis; it is not proven on that device, because the HP MADT was not readable
(`/proc/acpidump` covered AML tables only until now).

Handler `acpiev.irq` (`service`):

1. PM1: power button (clear, report), sleep button and RTC (clear), any other enabled status bit is stray: cleared and its enable bit switched off.
2. GPE: `gpe.scan` reads every status/enable byte of both blocks. Armed bits are cleared and queued for `pump`
   (method `_Lxx/_Exx`). Enabled bits without a method are stray: disabled and cleared.
3. An entry that found nothing counts as empty. After 256 empty entries in a row the line is masked, the register state is
   captured (`scisnap`), and `pump` polls PM1/GPE every 10 ms instead. Entries from a shared device vector never count.

EC events are polled every 10 ms (`ecio.poll_query` was called thousands of times per second before; the HP showed
`polls=59782176` in 3043 s).

## Diagnostics

- `/proc/acpi`: `rsdp`, `tables`, `aml_hold`, device list, then `scix` (routing, counters), `scireg` (live PM1 and GPE
  registers), `scisnap` (registers captured when a storm was cut).
- `/proc/hotkeys`: counters of keyboard, SCI, EC, WMI.
- `/proc/acpidump`: every table, rows `# SIG len=XXXXXXXX idx=NN` and `OFFSET HEX...`; `tools/acpi/fromdump.py` turns the
  text into table files.
- Serial lines: `acpiev: ready=...`, `acpiev: route ...`, `acpiev: ovr ...`, `acpiev: sci storm ...`, `acpiev: ev taste`.

## Kernel command line words

| word | effect |
|---|---|
| `acpiev` | verbose report |
| `noacpiev` | counter-proof: events not set up |
| `evself` | selftests (names, registers, options, MADT copy `XAPC`, diagnostics, EC poll rate) |
| `evwait` | keep the kernel alive for 9 s so events can arrive |
| `evdump` | one serial line per event |
| `evfake`, `evlid` | fake laptop (lid, battery, AC) from `tools/acpiev/asl/laptop.asl` |
| `scistorm` | test: enable the PM1 timer event so the status bit raises the SCI |
| `noscistray` | counter-proof: do not clear stray PM1 events |
| `noscistorm` | counter-proof: no storm guard |
| `scinoovr` | counter-proof: ignore MADT overrides (level, active low) |
| `ecsim`, `noec` | EC software model, EC driver off |

## Real firmware replay and the method sweep

`tools/acpi/prep_corpus.py` turns a machine directory of `tools/acpi/real/` into `-acpitable` files (a table above 65535 bytes
is cut at term boundaries, containers are split into `Scope` pieces). With the word `amlsweep` the kernel evaluates, after
all `_INI` methods, every method of the kinds `_STA _CRS _PRS _BIF _BIX _BST _PSR _LID _TMP _CRT _HOT _PSV _BCL _BQC _PRW _DOD
_PCL _PTS _WAK _TZP _DCK _EJ0 _Qxx _Lxx _Exx` (writes are blocked) and prints per kind how many ran and how many failed, which
error, and the first failing path with the opcode or region that caused it. The replay needs `-m 4096` so the firmware's NVS
addresses are RAM.

Measured with the sweep on the previous interpreter (HP tables, 26.10.2026): seven failures on `ConcatenateResTemplate`,
four on `Concatenate`, one `Match`, one `OperationRegion` executed inside a method, `\_SB.PAGD._STA` failing on the missing
`_OSI`. With the current interpreter the replay of the HP, Surface and AMD tables ends with no unsupported opcode; all
battery, backlight query and thermal-limit methods of the HP that do not depend on firmware memory run.

Remaining failures in the replay are data, not code: methods that read NVS or MMIO regions whose address the firmware
computes at boot (base 0xFFFFFFFF in QEMU) and thermal methods that need earlier initialisation.

## Conformance suite

`tools/acpi/asl/conform.asl` (compiled with `iasl -oa`, no constant folding) holds self-checking methods `Txxx` that return
0 on success; `amlconf` runs them and reports `pass`/`fail`; the method `TBAD` fails on purpose.

## Fuzzing

`amlfuzz=N` loads N copies of the firmware tables with `amlfuzzmut` (default 3) random byte edits (flip, replace, insert,
cut) in a scratch arena, evaluates up to 24 methods of each result with writes blocked, frees the arena and checks that no
frame leaked. `amlfuzzseed` selects the sequence. Result line: `amlfuzz: iters=N leaked=0 e<code>=count ...`.

## Gate

`bash tools/acpi/run.sh [--only name,...]` runs `tools/acpi/sections/NN-name.sh`; `ACPI_IMG=<kernel>` reuses an image,
`ACPI_BASE_IMG=<older kernel>` is for before/after lines. Helpers are in `tools/acpi/lib.sh`.

Real firmware tables live in `tools/acpi/real/` (see the README there). QEMU takes tables up to 65535 bytes through
`-acpitable`; `tools/acpi/retag.py` renames the signature (e.g. `XAPC`) so the kernel parses a real MADT next to its own.
