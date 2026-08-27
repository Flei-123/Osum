<!-- SPDX-License-Identifier: GPL-2.0-only -->
# Round POWERMON — where the battery goes

Windows has a page called **Battery usage by app**. It shows a bar per
program and a percentage, and almost nobody who reads it knows what the
number is.

It is not a measurement. **Nothing in a laptop measures the current drawn
by one program.** There is no shunt resistor per process and there cannot
be one: the battery has a single gas gauge on a single pair of terminals,
and everything downstream of it is one circuit. What Windows does is
*estimate* — it weighs processor time, screen time, disk activity and
network activity against each other with coefficients and prints the
result in a column that looks like it came off an instrument.

This round does something better, and the difference is the whole point.

---

## The approach, and why it is not what Windows does

Round K18 taught this kernel to read `_BST`. The second field of `_BST`
is the **present rate of draw** — the real power the whole machine is
taking right now, in milliwatts, measured by the battery's own gas gauge
and handed over by the firmware. That number *is* a measurement.

So this round does not estimate the total. It **takes** the measured
total and **divides** it:

```
measured total (mW, from _BST)
  =  system floor  (measured while nothing ran)
  +  the rest, split between programs by processor time
```

The sum is right **by construction** — it cannot drift away from the
battery, because it never left it. Only the *split* is an approximation,
and it is the same approximation Windows makes, applied to a real number
instead of a modelled one.

That is why the page says, in the second line and not in a footnote:

> **measured total, proportionally attributed**

and never "this program draws 2.3 W". "This program is 34 percent of a
measured 6.8 W" is what actually happened, and it is what is printed.

---

## The floor, and the mistake a monitor makes without one

A large part of the draw belongs to no program at all: the backlight, the
radios, the chipset, the memory refresh, the fans. If a monitor
distributes the *whole* measured power over the running processes, then
whichever program happens to be awake gets the backlight hung around its
neck. Open a text editor on an idle laptop and the editor appears to draw
eight watts.

This is the commonest mistake in this kind of display. So the floor is
measured first:

> A sampling window in which **no process got a single timer tick** —
> only the idle task ran — is an **idle window**. The rate measured in an
> idle window is a measurement of the floor and of nothing else. The
> running mean of those samples is the floor, it is booked to *System*,
> and only `rate − floor` is ever split between programs.

If no idle window has happened yet, the floor is not guessed at: the flag
stays zero, the whole measured rate goes to *System*, and the page says
so.

**The mistake is demonstrated and not described.** `tools/powermon/run.sh`
section 5 runs the *same* workload against the *same* battery table
twice, once with the floor measured and once with `pmonnofloor`, and
reports how far apart the two displays end up. The numbers of a real run
are in the table further down.

---

## Why the arithmetic uses no division

Percentages have to be divided, and division loses remainders; add up
sixteen rounded percentages and you get 99 or 101. So nothing is divided
in the kernel. In each window of `dt` ticks, with `busy` the sum of the
per-process tick deltas:

```
for every process p:  E[p]   += attrib * dticks[p]
system:               E[sys] += floor * dt + attrib * (dt - busy)
```

Add those up:

```
sum(E) = attrib*busy + floor*dt + attrib*dt - attrib*busy
       = (floor + attrib) * dt
       = rate * dt
```

— the measured total over that window, exactly, in integers, with no
rounding anywhere. The run checks that identity on the numbers of a real
run rather than trusting the derivation: the sum of the per-program rows
has to equal the kernel's own total to the last milliwatt-tick, from
*both* sides of the system call.

The percentages a person sees are computed once, at the end, in ring 3,
and they are rounded **on the running sum** so that the differences
telescope and the column adds to exactly 100.

---

## A process is not a program

The task table has thirty-two slots and a machine runs more than
thirty-two programs in an afternoon. When slot 7 is handed from `ls` to
`cat`, `ls`'s record has to be cleared — or the two would be added
together, which is a lie in the plainest possible form.

Without a second table the energy in that record is simply gone, and the
run said so before the second table existed:

```
sum of the per-task rows   285100 mW-ticks
the machine's own total    302100 mW-ticks
```

Seventeen thousand of them had belonged to three `ls` processes whose
slots had been reused. So the split books **twice**, into the process row
and into the program row, out of the same number. The process rows say
what is running now; the **program rows** say where the charge went, and
they are what the table is built from — which is also the right answer,
because Windows calls its page "by app" and it is right to.

There are sixteen program rows. The sixteenth is called `other` and the
fifteenth `system`: a program table that silently drops the seventeenth
program is the same lie one level up, and kernel tasks that never had a
name did really use the processor.

A process that dies between two samples does not take its ticks with it
either. `exit` flushes them into the program row and into one global
counter, so that the window which pays for them also counts them as busy
— without that second number the same ticks would be paid twice, once as
the program's and once as "drawn while nothing ran".

---

## What was measured

All numbers below come from `tools/powermon/run.sh` on **QEMU 7.2 without
KVM (TCG), on an AMD EPYC**, on 27 August 2026. See the next section for
what these numbers do and do not prove.

### The measured draw comes from the firmware

| battery table (`tools/k18/ssdt.py`) | `/bin/powermon` reports |
|---|---|
| `--rate 1200` | `rate=1200`, `rateok=1` |
| `--rate 7700` | `rate=7700`, `rateok=1` |
| `--kein-akku` | `rate=0`, `rateok=0`, and the page prints `--` |

Change the table, change the answer. A number that follows the firmware
came from the firmware and not from the kernel. Without a battery the
page prints a dash and **not a zero** — a zero in milliwatts looks
exactly like a measurement, which is round K18's lesson inherited.

The kernel reports the same fourteen values on the serial line that ring
3 reads over `osum_pmon`, and the run compares them pairwise. Where they
part, the interface is broken.

### The floor against no floor — the same workload, the same battery

| | with the floor | with `pmonnofloor` |
|---|---|---|
| floor measured | yes, over several idle windows | no (`baseok=0`, `base=0`) |
| attributable | `rate − floor` | the **whole** measured rate |
| booked to programs | little or nothing | everything above zero |
| booked to *System* | nearly all of it | the remainder |

On this host, where the table is static, the floor equals the total and
**nothing at all can be attributed**. That is not a defect in the
arithmetic; it is the correct answer for a machine whose draw does not
respond to load, and the page says it in as many words rather than
showing an empty table with no explanation.

### The split follows the load and adds up

`burn` (`kernel/user/burn.fi`) holds the processor and makes no system
call inside its loop, so it is runnable on every timer tick. A run of
`burn 8` on a `pmonnofloor` kernel:

```
PROGRAM             CPU   SHARE       mJ  RUNS
system                105    96 %     1995     2
burn                    7     6 %      133     1
sh                      5     4 %       95     1
powermon                2     2 %       38     2

  Sum of the shares: 100 %
```

and the identity, checked from both sides in the same run:

```
kernel   proce = 226100 mW-ticks
ring 3   sum of the four program rows = 226100 mW-ticks
kernel   sum of its own p-rows        = 226100 mW-ticks
```

The counter-check is that a run in which `burn` never started has no row
for `burn`. A monitor that reports a program which did not run is as
broken as one that misses a program which did.

`ls` is worth a sentence of its own: it barely appears, because it spends
almost all of its life asleep on a disk and collects almost no timer
ticks. That is the **correct** answer for `ls` and it is also why a load
test needs a program like `burn` rather than a shell loop.

### Ageing, runtime, mains

| claim | table says | page says |
|---|---|---|
| ageing | last full 3000 of 6000 mWh design | `Health 50 %` |
| ageing, counter-check | last full = design | `Health 100 %` |
| runtime at 7700 mW | 3300 mWh remaining | 25 min |
| runtime at 1200 mW | 3300 mWh remaining | 165 min |
| on mains | `_PSR = 1` | `acrate` set, `batrate` stays 0 |
| on battery | `_PSR = 0` | `batrate` set, `acrate` stays 0 |

**The ageing number is the one Windows does not put in front of a
person.** It costs one division of two numbers that are already being
read, and it is the number that says whether a battery is worn out.

The runtime comes from the rate that was *just measured*, not from a mean
of the last hour. A mean is smoother and it is also wrong at exactly the
moment somebody looks — they look because something changed.

### What the bookkeeping itself costs

Measured, not asserted, because this code runs inside a timer interrupt.

| | cycles per sample |
|---|---|
| first draft, full ACPI table walk per sample | **12 800 000** |
| after caching where `_BST` was found | **≈ 175 000 – 435 000** |

The first draft re-searched every ACPI table octet by octet on every
sample: ten times a second, that is more power than the monitor could
ever explain. The fix is in `kernel/batt.fi`: the *address* where `_BST`,
`_PSR` and `_TMP` were found is remembered, and the next read goes
straight there. The tables live in reserved memory and do not move.

At ten samples a second and the slower figure, that is on the order of
four parts per thousand of a 1 GHz processor — and TCG is the slowest
case there is; on real silicon the same work is a fraction of it. The run
also checks that `burn` computed **exactly the same result** in the
counted and the uncounted run: if the accounting changed what the machine
computed, it changed the machine.

`nopowermon` is the counter-check: same image, same workload, no
accounting, `samples=0`, and `/bin/powermon` says the accounting is not
running instead of printing a table of zeros.

### The day file

`/etc/powermon.days`, plain text, readable with `cat`, self-capped at 90
days:

```
# osum powermon -- one line per day, newest last, at most 90.
# mJ is milliwatt-ticks divided by the tick rate: millijoules
# total = system + programs, and it is measured, not modelled
day=20260827 totalmJ=5130 systemmJ=5130 basemW=1900 samples=27 health=88 prog=system:0 prog=sh:0
```

About a hundred octets a day, so under ten kilobytes full. That matters
because OFS still has a **two-megabyte ceiling per volume** (round OFS3 is
lifting it), and a monitor that fills the disk it is monitoring is a bad
monitor. The day mark in the kernel is moved **only after** the file
really holds the day; the other order loses a day whenever the disk is
full, and the day it loses is the one somebody was about to look at.

---

## What QEMU cannot prove — and what has never been tested at all

This is the most important section in this document.

### Osum has never run on real hardware

Not once, in any round. Everything below that says "on a real machine"
is a statement about what the code is *built to do*, not about what has
been observed. It is marked **UNTESTED** where it matters.

### The measured total does not respond to load here — UNTESTED

`-device battery` arrived in QEMU 8.2. This host has QEMU 7.2, so the
only battery is the one `tools/k18/ssdt.py` writes into an ACPI table and
`-acpitable` hands over. `_BST` is a **static package in a static table**:
it reads 7700 mW while the machine idles and 7700 mW while it computes,
because it is a number in a file.

Consequences, stated plainly:

* **That the draw of a real machine rises under load is assumed and not
  tested.** It is a well-founded assumption — it is why a laptop fan
  spins up — but this round has not observed it, and the acceptance run
  says so in its own header.
* On this host the floor therefore equals the total, `attrib` is zero,
  and **no energy at all can be attributed to any program.** The page
  prints that fact instead of an empty table.
* Everything about the *split* — that shares follow processor time, that
  they add to a hundred, that the rows sum to the total — is measured and
  real, because `T_TICKS` is real. Everything about *watts per program*
  waits for hardware.

### `_BST` as a method — UNTESTED, and known not to work

On a real laptop `_BST` is a **method**: it reads six registers over the
embedded controller and computes a package. `kernel/batt.fi` reads
*constant* packages only — `Name(_BST, Package(4){...})` is found,
`Method(_BST){...}` is not. Round K18 says this and it is still true.
A correct implementation needs an AML interpreter, which is a round of
its own and more code than this whole kernel directory.

**So on the great majority of real laptops this round will report no
battery at all.** It will not report a wrong one — `BT_PRESENT` stays
zero and `BT_WHY` says why — but "no battery" is what a person would see.
That is the single largest gap in this round and it is not a small one.

### Brightness against power — the mechanism is built, the answer is not measured

The buckets are there (one per ten percent, mean measured draw in each),
they fill on every sample, and `powermon bright` prints them. On this
host **the column is flat**, because the table is static. The flat column
is the finding and it is printed rather than hidden.

This is the one place where the round would most like to say something
useful and cannot: brightness is the largest single thing a person can
turn down, and whether that is worth two watts or twenty on any given
machine is exactly what these buckets would answer — on hardware.

### Temperature

`_TMP` is read out of the same table and shown on the page. It is as real
as the table, which is to say: the run dictates it and the page repeats
it. On real hardware `_TMP` is usually a constant `Name` and would work;
the processor's own `IA32_THERM_STATUS` path from round K18 does **not**
work under TCG, which round K18 measured.

---

## What is missing, and what would come next

* **Disk and network per process.** Round NETMON is building per-process
  byte counters on a branch beside this one. This round deliberately did
  **not** build a second set: when NETMON lands, its counters get a
  column of their own **beside** the share, not folded into it with an
  invented coefficient. Guessing how many milliwatts a kilobyte costs is
  exactly the modelling this round exists to avoid.
* **DMA.** A process that sets a device copying and then sleeps gets no
  ticks and so no share, while the device draws current. Nothing here
  sees that.
* **Processor time is not energy.** Two tasks with the same ticks can
  draw very different power — one hammering the vector unit, one waiting
  on memory. Weighing that needs performance counters this host does not
  deliver: round K18 measured that `IA32_PERF_CTL`, `IA32_HWP_REQUEST`
  and `IA32_PM_ENABLE` read back as zero under TCG.
* **An AML interpreter**, without which real laptops stay invisible.
* **A pixel graph.** The window uses the widget library of round K15, and
  ring 3 has no call in this branch that paints into a widget window, so
  the graph is a row of block characters scaled against the highest rate
  seen. It says what a plot would say and it looks like what it is.
* **ICONS / I18N / THEME.** Those three rounds are on their own branches
  and are not in `main` yet. The window takes its colours from whatever
  theme `wlib.begin` resolved, so it already follows the scheme the
  person chose; the icons and the string catalogue attach at the same
  seam when those branches land. The strings of this round are kept in
  one place per function for exactly that reason.

---

## Files

| file | what it is |
|---|---|
| `kernel/pmon.fi` | the accounting: sampling, the floor, the exact split, the program table |
| `kernel/user/powermon.fi` | `/bin/powermon` — the page, `raw`, `graph`, `bright`, `day`, `reset`, `window` |
| `kernel/user/burn.fi` | `/bin/burn` — the load the split is measured against |
| `tools/powermon/run.sh` | the acceptance run |
| `kernel/batt.fi` | round K18's, plus `refresh()` and the remembered address of `_BST` |
| `kernel/kstate.fi` | `PMON_OFF = 0x5C000`, three pages |
| `kernel/sys.fi` | `SYS_OSUM_PMON = 1830`, and the two seams where a task gets a name |
| `kernel/elf.fi` | the one seam where a task becomes a program |
| `kernel/trap.fi` | one line, in front of `sched.on_tick` |

### Three collisions in one round, and what they cost

Worth writing down, because the pattern is the same one that has cost
this project four rounds:

1. **The scalars ran into the task table.** Thirty-six scalars are 288
   octets, not 256, so three of them were the first three words of task
   slot zero. The run said `windows=65` out of `samples=21` — a counter
   that cannot exceed another one did.
2. **`PR_PEND` landed on `PR_NAME`.** Field five of a program row is
   offset 40, and the name was at offset 40. The run said `panic: integer
   overflow in u64 * u64`, and the multiplier was the word `system` read
   as a number.
3. **`pmon.tick` stood behind `sched.on_tick`.** `on_tick` ends in
   `schedule_locked`, which switches stacks: everything after it runs not
   when the tick happens but whenever that task is next given the
   processor. The sampler fired twenty times in five seconds instead of
   fifty.

None of the three is visible in a diff. All three were found by a number
that could not be what it was.
