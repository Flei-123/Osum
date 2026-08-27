# THIRD_PARTY.md -- Osum (the kernel)

What in this repository is NOT written here. Round INVENTORY,
27 August 2026.

**Base of every number in this file:** branch `main`, commit `3389fbd`
("README: translate to English"). Counted with `git ls-tree -r main` and
`git show main:<path> | wc -l`. The parallel rounds on their own branches
(`k17-usb2`, `i18n`, `icons`, `display`, `ofs3`, `speicher`, `netview`,
`taskbar-edge`, ...) are **not** covered; whatever they bring in has to be
added here when it lands.

**The one distinction that matters** is marked on every entry:

* **RUNTIME** -- the foreign part is inside the kernel image or the root
  filesystem and runs on the machine. These are the only entries that limit
  independence.
* **BUILD** -- needed to produce the image, gone afterwards.
* **TEST** -- needed only to measure. Never shipped.

An overview across all four repositories lives in the OrientOS repository,
`THIRD_PARTY_OVERVIEW.md` (branch `inventory`).

---

## 0. Summary in numbers

| | files | lines |
|---|---:|---:|
| kernel and userland, Firn (`kernel/**.fi`) | 140 | **75,280** |
| assembly written here (`kernel/*.s`, `kernel/user/crt.s`) | 7 | 1,884 |
| libc from round K4 (`lib/libc/*.fi`) | 8 | 1,690 |
| host test tools (`tools/**.py`, `tools/**.sh`) | 51 | 16,837 |
| **foreign SOURCE CODE in the repository** | **0** | **0** |

A search for `SPDX-License`, `Licensed under` and `Copyright (c)` over
`kernel/`, `lib/` and `tools/` returns **nothing**. There is no vendored
foreign source in this tree.

**Foreign material that IS shipped -- 34,800 octets, all of it glyph
shapes:**

| what | where | octets | origin |
|---|---|---:|---|
| proportional font | `assets/osum-sans.ttf` | 18,676 | cut out of **DejaVu Sans** |
| monospace font | `assets/osum-mono.ttf` | 14,604 | cut out of **DejaVu Sans Mono** |
| console bitmap font | inside `kernel/font.fi` (130 lines) | 1,520 | rasterised from **DejaVu Sans Mono** |

That is the complete list. Everything else in the shipped system is written
here or comes from Justin's own Firn repository.

### What to replace first

1. **The fonts (section 4).** They are the only foreign thing that runs, and
   the licence notice they are supposed to carry has been stripped out of the
   files. Two actions, and the first one is urgent and free:
   **(a)** put the Bitstream Vera / DejaVu licence text next to them, today;
   **(b)** draw own outlines later, if independence for the shipped system is
   the goal. 95 glyphs is a bounded job.
2. **Nothing else.** `as`, `ld`, `qemu`, `mkfs.vfat`, `objdump` are
   development tools. Building your own assembler or your own emulator to
   test your own kernel is not a goal; it moves the bug into the instrument.

---

## 1. Rust crates

**None.** There is no `Cargo.toml` in this repository.

`rustc`/`cargo` appear once each in the shell scripts, and only indirectly:
the Firn compiler stage 0 is a Rust program, and it is built out of the
pinned Firn checkout by `vendor/firn/hole-firnc.sh`. Nothing in this
repository is Rust. Licence of the Rust toolchain: Apache-2.0 OR MIT
(upstream); no copy here. **Stage: BUILD.**

---

## 2. Python packages

**None outside the standard library.** 24 Python files under `tools/`,
4,804 lines, and the complete set of imports on `main` is:

`sys` (22), `re` (7), `os` (7), `struct` (5), `time` (3), `socket` (3, plus
2x `socket, sys`), `subprocess` (1), `glob` (1), `argparse` (1) -- plus two
local modules of this repository (`import raster`,
`import symbol as symmod`). Nothing else.

That is worth stating plainly because it was a decision and not an accident.
`tools/ttf/schnitt.py:19-23`: "REPRODUZIERBAR UND OHNE FREMDE BIBLIOTHEK.
Kein fontTools, kein FreeType -- reines `struct`."

**Stage: BUILD/TEST.** No Python is shipped.

---

## 3. `vendor/` -- pinned, but NOT third party

Both entries under `vendor/` point at Justin's own Firn repository. They are
listed here so that nobody mistakes a `vendor/` directory for foreign code.

### 3.1 `vendor/firn/` -- the compiler and the Firn library

* **Tracked here:** exactly two files -- `vendor/firn/COMMIT` and
  `vendor/firn/hole-firnc.sh`. The compiler binary is deliberately not
  checked in ("2,8 MB Binaerdatei pro Version in der Historie",
  `hole-firnc.sh` header).
* **Pin:** `vendor/firn/COMMIT` =
  `c66c6bcd5f30d632d74e20facb6a5757c6043379`.
* **What gets unpacked:** the whole Firn library of that commit into
  `vendor/firn/lib/` -- 171 `.fi` files, 5.2 MB on disk.
* **Origin and licence:** the Firn repository, MIT, same author.
  **Not third party.**
* **Stage:** BUILD (the compiler), **RUNTIME** for the library modules the
  kernel imports -- but that is own code.

### 3.2 `vendor/net/` -- the TCP/IP stack, pinned by blob hash

* **Tracked here:** `vendor/net/HERKUNFT.md` and `vendor/net/BLOBS`
  (451 octets).
* **What it pins:** three files that come out of `vendor/firn/COMMIT` and
  are compiled into the kernel:

  | file | blob | lines |
  |---|---|---:|
  | `lib/net/wire.fi` | `0dd4c71cfd88424f0d1149f41342458468cd53bd` | 492 |
  | `lib/net/tcp.fi` | `201b5a3972d0e05bb5d6b74c4298e42f1732685d` | 1,555 |
  | `lib/net/stack.fi` | `136851a057d18cad35aeba10c59f9e6b83ba9426` | 599 |

  Section 1 of `./test.sh` recomputes the three blob hashes against what
  `hole-firnc.sh` actually unpacked.
* **Origin and licence:** written in Firn round K3b, merged into Osum's
  history as `c8ce865`. Same author, MIT. **Not third party.**
* **Stage:** **RUNTIME**, and own code. 2,646 lines.

The kernel imports 58 modules by name; the three above are the only ones that
come from outside `kernel/` and `lib/libc/`.

---

## 4. Fonts -- the only foreign material in the shipped system

### 4.1 `assets/osum-mono.ttf` (14,604 octets), `assets/osum-sans.ttf` (18,676 octets)

* **Where they end up:** `tools/k15/bauen.sh:46` puts them into the image as
  `/lib/mono.ttf` and `/lib/sans.ttf`. `kernel/ttf.fi` reads them at runtime
  and `kernel/wm.fi` draws with them. **They are an installed part of the
  product.**
* **Origin -- this is the finding:** they are **cut out of DejaVu Sans Mono
  and DejaVu Sans on the host** by `tools/ttf/schnitt.py` (409 lines). The
  script keeps seven tables (`head`, `hhea`, `maxp`, `hmtx`, `cmap`, `loca`,
  `glyf`, plus `kern` if present) and 95 glyphs out of 6,253. Reading the two
  files back confirms it: `osum-mono.ttf` has exactly
  `cmap glyf head hhea hmtx loca maxp`, `osum-sans.ttf` the same plus `kern`.
  `tools/wm/run.sh:219-226` rebuilds both from
  `/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf` and
  `DejaVuSans.ttf` and compares octet for octet:
  "osum-mono.ttf entsteht Oktett fuer Oktett neu aus DejaVu Sans Mono".
* **The glyph outlines are not own work.** The cutting, the packing and the
  reproducibility are; the shapes are DejaVu's.
* **Licence:** the **Bitstream Vera Fonts Licence / DejaVu Fonts Licence**.
  It is permissive -- use, modify and redistribute, including subsetted --
  but it has two conditions, and the second one is the problem:
  * the copyright notice and the licence must be distributed with the font;
  * the fonts may not be sold on their own.

  **Finding 1: there is no licence file anywhere near these fonts.**
  `find` over the repository turns up exactly one `LICENSE`, and it is
  Osum's own MIT file.
  **Finding 2: the notice has been removed from the font files themselves.**
  Both files have **no `name` table at all** -- `schnitt.py` does not copy
  one. The `name` table is where a TrueType file carries its copyright
  string, so the subsetting step deleted the exact thing the licence requires
  to travel along. This is not a formality: the font is redistributed with
  its notice stripped.
* **What they are for:** text in the window server -- window titles in the
  proportional face, terminal and editor content in the monospace face
  (`docs/ROUNDK10W.md`).
* **Cost of replacing, and whether it is worth it:** drawing 95 monospace and
  95 proportional glyphs (more once round I18N widens the range past ASCII)
  is real design work but it is bounded and it needs no new technology --
  `schnitt.py` and `kernel/ttf.fi` already handle whatever gets fed in.
  **It is worth it**, because this is the single item that keeps the shipped
  system from being entirely own work. Until then the fix is trivial and
  should happen immediately: add `assets/FONT-LICENSE.txt` with the
  Bitstream Vera text and a line in `assets/` saying what was cut from what.
* **Known fragility, already documented:** `docs/ROUNDK10W.md:745-748` --
  "Der Schriftschnitt haengt an DejaVu auf dem Wirt. Liegt es nicht unter
  `/usr/share/fonts/truetype/dejavu`, wird die Reproduktion uebersprungen."
* **Stage:** **RUNTIME.**

### 4.2 `kernel/font.fi` -- 1,520 octets of foreign glyph bitmaps, linked into the kernel

* **What / where:** `kernel/font.fi`, 130 lines. 95 glyphs, 8x16, 0x20 to
  0x7E, 16 octets each = 1,520 octets, copied into the data segment at boot.
  No font reader involved.
* **Origin:** the file says it itself, `kernel/font.fi:7-13` -- the glyphs
  come from OrientOS' old `kernel/src/drivers/font.rs` (Rust, 221 lines) and
  were rasterised there once **from DejaVu Sans Mono**
  ("Bitstream-Vera-Lizenz, freie Weitergabe erlaubt"). `docs/ROUNDK7.md:139`
  repeats it. `tools/gfx/run.sh` compares the table against the Rust source
  octet for octet, so "portiert" really means portiert.
* **Licence:** same as 4.1 -- Bitstream Vera / DejaVu. **No licence file, and
  a bitmap has nowhere to carry a notice.**
* **What it is for:** the boot console before the window server exists.
* **Cost of replacing:** 1,520 octets of 8x16 bitmaps. This is the **cheapest
  independence win in the entire project** -- an evening with a bitmap font
  editor, and one foreign item disappears from the kernel binary.
* **Stage:** **RUNTIME**, inside the kernel image.

### 4.3 `assets/apps/*` -- own

Twenty tracked files under `assets/apps/{editor,explorer,suchen,terminal,widgets}.prog/`:
`INFO`, `start.txt`, `symbol.txt`, `daten/LIESMICH`. Between 175 and 1,021
octets each. All written here. The `symbol.txt` files are the OSYM icon
format, own design. **Own work, RUNTIME.**

### 4.4 A note on round ICONS

The parallel round ICONS is bringing in a free symbol font. On branch `icons`
at the time of writing, `git diff main..icons` is **empty** and
`git ls-tree -r icons -- assets` shows the same two `.ttf` files as `main` --
nothing has landed yet. When it does, it belongs in section 4 with its
origin, its exact licence, its octet count, and the same two questions:
does the licence require a notice, and is the notice in the file.

---

## 5. C libraries and the toolchain

Everything in this section is BUILD or TEST. Nothing here reaches the
machine.

### 5.1 GNU binutils -- `as`, `ld`, and the linker scripts

* **Usage:** 130 occurrences of `as` and 124 of `ld` across the shell
  scripts. `firnc` emits assembly text and calls `as` and `ld` itself
  (see the Firn repository, `compiler/src/target.rs`); this repository adds
  its own linker scripts on top: `kernel/kernel.ld`, `kernel/linker.ld`,
  `kernel/user/user.ld` -- **written here**.
* Also used in tests: `objdump` (20), `readelf` (12), `objcopy` (11).
* **Licence:** GPL-3.0-or-later. Not in this repository, taken from the host.
  **No licence file here.** The GPL applies to the tools, not to what they
  assemble.
* **Cost of replacing:** an x86-64 assembler and an ELF linker. Bounded work,
  no benefit while they are only used at development time. **Do not.**
* **Stage:** BUILD. Named as the one build dependency without which there is
  no image at all.

### 5.2 QEMU

* 86 occurrences of `qemu-system-x86_64` in the shell scripts. `./test.sh`
  (26,069 octets) drives the whole kernel through it.
* **Licence:** GPL-2.0 (upstream). Not here.
* **What it is for:** every measurement in `docs/ROUND*.md` -- boot,
  scheduling, virtio-net, NVMe, SMP, the window server screenshots.
* **Cost of replacing:** **do not.** An emulator written by the same person
  who wrote the kernel will agree with the kernel about the bugs they share.
  QEMU's independence is its whole value.
* **Stage:** TEST.

### 5.3 `mkfs.vfat` (dosfstools)

* 8 occurrences in the shell scripts.
* **What it is for:** producing a FAT image from outside, so that
  `kernel/fat.fi` (2,007 lines) is read against a filesystem it did not
  create. Same idea as `tools/osum/mkfs.py` being a second implementation of
  OFS.
* **Licence:** GPL-3.0-or-later. Not here.
* **Stage:** TEST.

### 5.4 `gcc`, `mtools`

* `gcc` (7 occurrences) compiles exactly one C file in this repository:
  **`tools/net/bruecke.c`** -- the round K8 wire between QEMU and Linux
  (`AF_PACKET` over a `veth` pair, because `/dev/net/tun` does not exist in
  the container this repository is measured in). **Own C code**, not foreign.
* `mtools` (1 occurrence) -- FAT image handling on the host.
* **Licences:** GCC GPL-3.0-with-exception, mtools GPL-3.0. Not here.
* **Stage:** TEST.

### 5.5 Firmware used for testing -- SeaBIOS and OVMF

* `README.md:90`: the ISO is started "through SeaBIOS **and** through OVMF",
  and the ISO itself is built by OrientOS. `docs/OSUM-K2.md:114` notes that
  the PCI BARs the kernel reads were assigned by SeaBIOS.
* **Licences:** SeaBIOS LGPL-3.0, OVMF/EDK II BSD-2-Clause-Patent. Neither is
  in this repository; both come with QEMU / the `ovmf` package.
* **Why it is not a dependency of the product:** real hardware brings its own
  firmware. These two are stand-ins for it during testing.
* **Stage:** TEST. (The bootloader that IS shipped -- Limine -- belongs to
  the OrientOS repository; see `orientos/THIRD_PARTY.md` section 2.)

---

## 6. Built here from somebody else's specification

**Not foreign code.** Implementing a written standard is own work. The list
exists so the difference between foreign CODE and a foreign IDEA is visible
at a glance. Every line below is Firn written in this repository.

| what | where | lines | specification |
|---|---|---:|---|
| POSIX syscalls, Linux x86-64 numbers | `kernel/sys.fi` | 6,141 | Linux x86-64 syscall ABI, POSIX.1 |
| FAT12/16/32 | `kernel/fat.fi` | 2,007 | Microsoft FAT32 File System Specification |
| TrueType reader and rasteriser | `kernel/ttf.fi` | 1,386 | Apple TrueType / OpenType reference |
| ELF64 loader | `kernel/elf.fi` | 1,161 | System V gABI, ELF-64 |
| Signals | `kernel/signal.fi` | 1,143 | POSIX.1 |
| Hardware virtualisation (SVM) | `kernel/hv.fi`, `kernel/vmcb.fi`, `kernel/hv.s` | 1,843 + | AMD64 APM vol. 2 (SVM) |
| ACPI tables | `kernel/acpi.fi` | | ACPI Specification |
| Local APIC, IO-APIC | `kernel/apic.fi` | | Intel SDM vol. 3 |
| Interrupt descriptor table, traps | `kernel/idt.fi`, `kernel/trap.fi`, `kernel/isr.s` | | Intel SDM vol. 3 |
| SMP bring-up | `kernel/smp.fi`, `kernel/smp.s` | | Intel MP / ACPI MADT |
| PCI configuration space | `kernel/pci.fi` | | PCI Local Bus / PCIe base spec |
| NVMe | `kernel/nvme.fi` | | NVM Express base specification |
| virtio-net | `kernel/virtio.fi` | | OASIS virtio 1.x |
| GPT and MBR partitions | `kernel/part.fi` | | UEFI spec (GPT), MBR convention |
| PS/2 keyboard and mouse | `kernel/kbd.fi`, `kernel/ps2m.fi` | | IBM PS/2 / 8042 |
| 16550 serial | `kernel/serial.fi` | | 16550 UART datasheet |
| ANSI terminal escapes, line discipline | `kernel/ansi.fi`, `kernel/tty.fi` | | ECMA-48, POSIX termios |
| Multiboot1 entry | `kernel/boot.s`, `kernel/bootmod.fi` | | GNU Multiboot Specification |
| gzip / deflate in userland | `kernel/user/gzip.fi`, `flate.fi`, `gunzip.fi` | | RFC 1951, 1952 |
| `tar` | `kernel/user/tar.fi` | | POSIX ustar |
| `sed`, `diff`, `patch`, `grep`, `find` | `kernel/user/*.fi` | | POSIX.1-2017 utilities |
| Shell with `if`/`for`/`while`/`case`/functions | `kernel/user/sh.fi` | 2,191 | POSIX shell command language |
| TCP/IP | in the Firn library, see 3.2 | 2,646 | RFC 791, 792, 793, 826, 768 |
| **OFS**, the filesystem | `kernel/ofs.fi`, `kernel/fs.fi` | 1,464 + | **own design**, no foreign spec |
| **The window protocol** (`wig`) | `kernel/wig.fi`, `kernel/wm.fi` | 1,882 + | **own design** |
| **The OSYM icon format** | `assets/apps/*/symbol.txt`, `tools/k15/symbol.py` | | **own design** |

The two lines at the bottom are worth noticing: OFS, the window protocol and
the icon format have no foreign specification behind them at all.

---

## 7. This repository's own licence

**`LICENSE`, MIT, "Copyright (c) 2026 Justin (Flei123)".** Present, and
`README.md:536-538` points at it.

**Caveat:** the MIT text covers the code. It does not cover
`assets/osum-mono.ttf`, `assets/osum-sans.ttf` and the glyph table inside
`kernel/font.fi`, which are under the Bitstream Vera / DejaVu licence
(section 4). Right now the repository presents them as if they were MIT. An
`EXCEPTIONS` paragraph in `LICENSE` naming those three fixes it.

---

## 8. Open items -- things this round could not settle

1. **The exact wording of the DejaVu licence that applies.** The Bitstream
   Vera licence and the DejaVu licence are close but not identical, and
   `kernel/font.fi` and `docs/ROUNDK7.md` say "Bitstream-Vera" while the
   files came out of DejaVu. Which text has to be shipped is a question for
   the upstream `LICENSE` of the `fonts-dejavu` package. **Must be checked.**
2. **Round ICONS** -- the symbol font it is pulling in has not landed on any
   branch yet (section 4.4). Origin and licence unknown.
3. **Branches not covered.** `k17-usb2` (xHCI), `i18n` (which widens the font
   range past ASCII and therefore touches section 4 directly), `display`,
   `ofs3`, `speicher`, `netview`, `taskbar-edge`, `tresor`, `tiling`,
   `theme`, `install`, `format`, `diskmap`, `rename-en`. Each has to be
   re-checked against this file before it merges.
