# LICENSING.md -- why this repository is under two licences

Decision of 27 August 2026. Justin (Flei123) is the sole author of Osum,
Firn and OrientOS, so the change needed nobody else's agreement.

Until this date the whole repository was MIT (`LICENSE.MIT.old`, kept
verbatim so the change is visible in the tree and not only in the history).
It is now:

* **GPL-2.0-only** for the kernel and for the Ring 3 programs,
* **MIT** for the Ring 3 libraries a program links against.

The machine readable answer for any single file is its
`SPDX-License-Identifier:` line. This document says why the line runs where
it does. The same reasoning, in the same words, is in `firn/LICENSING.md`
and `orientos/LICENSING.md`.

---

## 1. Why GPL and not MIT

MIT lets anybody take the work, close it and sell it without giving
anything back. For a library that is often the right trade. For an
operating system it is not: the point of building one is that it stays
open. Whoever ships a changed Osum has to ship the changes.

## 2. Why version 2 ONLY, and not version 3, and not "or later"

**GPLv3 section 6 requires "Installation Information" for User Products:**
ship GPLv3 software inside a consumer device and you must also ship
whatever a user needs to install their own modified version on it --
including the signing keys.

That would make one specific thing legally impossible: **binding firmware
to the machine it came with, as a theft deterrent.** A device that only
runs software signed for it is worthless to a thief. Under GPLv3 section 6
the manufacturer would have to hand out the keys that defeat exactly that.

**Linux is GPLv2-only for this reason**, stated publicly by Linus Torvalds
when GPLv3 was drafted; Android carries GPLv2-only for the kernel and
permissive licences above it for the same practical reason. Osum follows
that path deliberately.

**"or any later version" is left out on purpose.** With that clause the
Free Software Foundation could effectively relicense this work later by
publishing a GPLv4. Every header and every SPDX line therefore says
`GPL-2.0-only`, never `GPL-2.0-or-later`.

**The cost, stated honestly:** GPL-2.0-only is **incompatible with
Apache-2.0** (Apache's patent-termination clause is an additional
restriction that GPLv2 clause 6 forbids) and with GPLv3. This kernel can
never absorb Apache-2.0 or GPLv3 source. Section 5 checks what that costs
today. The answer is: nothing.

## 3. Why the Ring 3 libraries have to be MIT

A program for Osum is a standalone ELF file. To exist at all it links:

* **`kernel/user/crt.s`** -- the entry stub. `_start`, the argument block,
  the way out. Every single binary contains it, and its own header says so:
  "the four instructions a user program cannot write in Firn".
* **`kernel/user/ulib.fi`** -- the standard library of Ring 3, imported by
  **77** files in this repository alone.
* **`lib/libc/**`** -- the libc from round K4 that sits under `ulib`.
* **`kernel/user/wlib.fi` and `wlibc.fi`** -- the widget library. Every
  program with a window links them.

If those were GPL, **every program ever written for Osum or OrientOS would
be GPL**. Nobody would write one. That is not a side effect worth
accepting; it is the difference between an operating system and a museum
piece.

Firn solves the same problem the same way (`firn/LICENSING.md` section 3):
GCC needs a separate "Runtime Library Exception" document for it, and the
simpler route is taken here -- the libraries are just MIT. The answer fits
in one sentence:

> You may write a program for Osum, link it against the Ring 3 libraries,
> and ship it under any licence you like, including a closed one.

---

## 4. The boundary, file by file

Rule: **anything a Ring 3 program links against is a library, and libraries
are MIT.** Programs and the kernel are GPL. In case of doubt, MIT.

The dividing line is mechanical and can be checked: a Ring 3 **program**
defines `fn u_start`; a Ring 3 **library** does not. On `main` that gives
70 programs and 8 libraries, and the split below follows it exactly.

Counts are regular files on `main`.

### MIT -- 18 files

| path | lines | why |
|---|---:|---|
| `kernel/user/crt.s` | 121 | the entry stub. In **every** binary |
| `kernel/user/user.ld` | -- | the linker script that gives a program its three segments. Used to produce every binary |
| `kernel/user/ulib.fi` | 613 | the Ring 3 standard library. Imported by 77 files |
| `kernel/user/tools.fi` | -- | the shared output buffer under `find`, `sed`, `diff`, `tar`, `gzip`. Imported by 31 |
| `kernel/user/wlib.fi` | 2,843 | the widget library. Buttons, text fields, lists, focus |
| `kernel/user/wlibc.fi` | 862 | the drawing core under it |
| `kernel/user/pw.fi` | -- | the user database (`/etc/passwd`, `/etc/shadow`). Imported by 8 |
| `kernel/user/nidx.fi` | -- | the name index. Imported by 5 |
| `kernel/user/appdir.fi` | -- | the application directory. Imported by 2 |
| `kernel/user/flate.fi` | -- | deflate and gzip, RFC 1951/1952. Imported by 2 |
| `lib/libc/**` | 1,690 | 8 files: `kcall`, `errno`, `text`, `io`, `mem`, `proc`, `stdio`, `net` |

### GPL-2.0-only -- everything else

| path | files / lines | why |
|---|---|---|
| `kernel/**.fi` except the ten above | ~130 files | the kernel. Runs in Ring 0. Nothing links it |
| `kernel/boot.s`, `hv.s`, `isr.s`, `smp.s`, `start.s`, `switch.s` | 6 | kernel assembly |
| `kernel/kernel.ld`, `kernel/linker.ld` | 2 | the kernel's own linker scripts |
| `kernel/user/<program>.fi` | 70 files | the shell, the editor, the file manager, `ls`, `cat`, `sed`, `tar`, `ping`, `wget`, ... Applications, not libraries. Each defines `u_start` |
| `tools/**` | 51 files | host test runners. Never on the machine |
| `test.sh`, `docs/**` | | |

**One judgement call worth flagging:** `pw.fi`, `nidx.fi`, `appdir.fi` and
`flate.fi` are borderline. They are system-facing helpers written for the
shipped tools, not general-purpose libraries -- but they have no `u_start`,
other programs import them, and a third-party program could reasonably want
any of the four. The rule "in case of doubt, MIT" decided it. Flip them if
you disagree; nothing else moves if you do.

**`power.fi` deliberately stayed GPL.** It looks like a library from the
import graph but its header says "RUNDE K18: /bin/power, das
Bedienprogramm" and it defines `u_start`. It is a program.

---

## 5. Does GPL-2.0-only conflict with anything already in the tree?

Checked against every entry in `THIRD_PARTY.md`.

### 5.1 The one real rule: Apache-2.0 is out

GPL-2.0-only cannot be combined with Apache-2.0 -- Apache's patent
retaliation clause is a "further restriction" that GPLv2 clause 6 forbids.
Nothing in this repository is Apache-2.0, and nothing may become
Apache-2.0.

### 5.2 The two DejaVu fonts -- compatible, and STILL non-compliant

`assets/osum-mono.ttf` (14,604 octets) and `assets/osum-sans.ttf` (18,676
octets) carry DejaVu glyph outlines under the **Bitstream Vera / DejaVu
licence**. That licence is permissive and **GPL-2.0-compatible**, so the
licence change creates no new problem here.

**But the defect found in round INVENTORY is untouched and it now matters
more, because the file that used to say "everything here is MIT" now says
"everything here is GPL" -- and neither statement was ever true of these
two files:**

* there is **no licence text** anywhere near them, and
* `tools/ttf/schnitt.py` keeps seven TrueType tables and `name` is not one
  of them, so **the copyright notice has been deleted out of the font
  files**, which is precisely what the Bitstream Vera licence requires to
  travel with them.

The same applies to the 1,520 octets of 8x16 bitmaps inside
`kernel/font.fi`, rasterised from DejaVu Sans Mono.

**This is now the top open item in this repository.** The fix is one file:
`assets/FONT-LICENSE.txt` with the Bitstream Vera text plus a line saying
what was cut from what. See `THIRD_PARTY.md` section 4.

### 5.3 The icon font of round ICONS -- checked, and it is fine

Round ICONS (branch `icons`, not merged at the time of writing) adds
`assets/osum-icons.ttf`, 13,584 octets, cut from **Lucide**.

**Lucide is ISC**, not Apache-2.0. `assets/icons/LICENSE.lucide` is present
in that branch, it is the real ISC text, and `tools/icons/run.sh:108-113`
FAILS THE BUILD if it is missing or does not look like Lucide's licence.
That is exactly how the DejaVu fonts should have been handled.

**ISC is GPL-2.0-compatible.** No conflict. Two remarks for that round:

1. `tools/icons/build.py` writes "a font with the seven tables
   `kernel/ttf.fi` reads, and nothing else" -- so `osum-icons.ttf` has no
   `name` table either, the same as the DejaVu pair. For ISC the notice
   requirement is met by `LICENSE.lucide` being distributed with the font;
   make sure it is **copied onto the ISO** and not only kept in the
   repository.
2. `lib/icons.fi` (generated) is imported by `kernel/user/wlibc.fi`, which
   is MIT. **`lib/icons.fi` therefore has to be MIT too** when that branch
   merges -- otherwise the widget library drags GPL into every Ring 3
   program that draws an icon. Note it in `tools/icons/build.py` so the
   generated header carries the right SPDX line.

### 5.4 Everything else

* `vendor/firn/`, `vendor/net/` -- Justin's own code, pinned by commit and
  blob hash. Firn's runtime is MIT, Firn's compiler is GPL-2.0-only. The
  three network files (`wire.fi`, `tcp.fi`, `stack.fi`, 2,646 lines) that
  the kernel compiles in are GPL-2.0-only on the Firn side and are linked
  into a GPL-2.0-only kernel. **Consistent, no conflict.**
* `as`, `ld` (binutils, GPL-3.0), `gcc`, `qemu`, `mkfs.vfat`, SeaBIOS,
  OVMF -- build and test tools. The GPL binds distribution of the tool, not
  of its output. No conflict.
* `tools/net/bruecke.c` -- own C. GPL-2.0-only with everything else in
  `tools/`.

**Result: nothing has to be removed or replaced because of this licence
change.** The one thing that has to be *added* is the DejaVu licence text
(5.2), and that was already true yesterday.

---

## 6. What this changes for somebody using Osum

| you want to ... | may you? |
|---|---|
| write a program for Osum and sell it closed | **yes.** `ulib`, `wlib`, `wlibc`, the libc and `crt.s` are MIT |
| use the widget library in a closed program | **yes.** MIT |
| ship a changed kernel | not closed. GPL-2.0-only -- publish your changes |
| fork one of the 70 Ring 3 programs | yes, under GPL-2.0-only |
| ship a device that runs Osum and only boots signed firmware | **yes.** That is the entire reason for GPLv2 instead of GPLv3 |
| take Apache-2.0 code into the kernel | **no.** Incompatible. Look for MIT, BSD or ISC |
