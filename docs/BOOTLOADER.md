# osboot — own boot loader (replaces Limine)

## Today (Limine)
- ESP root: `osum.mb`, `root.img`, `limine.conf` (+ `/boot/limine.conf`), `/EFI/BOOT/BOOTX64.EFI` (Limine), `limine-bios.sys`; BIOS stage via `limine bios-install` (tools/usbimg/build.sh).
- Protocol: multiboot1. `osum.mb` is ELF32 (i386), LOAD at 0x100000 (text) and 0x800000 (data+bss, ~17.5 MiB), entry 0x100030, header flags 7 (aligned modules, memory info, video mode 32 bpp).
- The kernel reads from the multiboot info: flags, cmdline (bit 2, boot words like `nmihard=`), modules (bit 3, `root.img`), memory map (bit 6), framebuffer (bit 12, offsets 88..115). RSDP: EBDA/0xE0000 scan, under UEFI scan of map types 3/4 (kernel/acpi/acpi.fi).
- OTA A/B: kernel/lib/ab.fi rewrites one byte `default_entry: N` in `/limine.conf` on the ESP (confirm/rollback).

## osboot (UEFI, x86_64)
- Sources: `boot/uefi/*.fi` (Firn, `--profile=kernel -c`), `boot/uefi/entry.s` (MS-ABI entry, `efi_call` thunk, handoff trampoline).
- Build: `tools/bootloader/build.sh <out>/BOOTX64.EFI` — firnc ELF object + `ld -m i386pep --subsystem 10` -> PE32+. Code is RIP-relative, no relocations needed.
- Modules: `efi` (table offsets, allocation), `con` (text out, keys), `fsys` (SimpleFileSystem of the boot volume), `cfg` (config), `menu` (entries, timeout, digits/arrows/Enter), `elf32` (multiboot ELF32 + header check), `mbinfo` (multiboot1 info, modules, RSDP copy, memory map, ExitBootServices), `video` (GOP), `tramp` (copy list, own identity page tables).
- Config `/osboot.cfg` (generate from limine.conf: `tools/bootloader/mkcfg.py limine.conf osboot.cfg [--timeout N] [--resolution WxH]`):
  ```
  timeout 5
  default 1
  resolution 1280x800
  entry OrientOS
  kernel /osum.mb
  module /root.img
  cmdline modfs osum ...
  ```
  `default` larger than the entry count falls back to 1 (slot B missing -> slot A).
- Handoff: segments are copied into place AFTER ExitBootServices by a trampoline in a low LoaderCode page (own 4 GiB identity map, own GDT, own stack), then long mode -> compat -> paging off -> EFER.LME off -> `jmp entry` with eax=0x2BADB002, ebx=mbi. Reason: under OVMF 0x800000 is ACPI NVS, so the kernel range cannot be allocated before exit (Limine overwrites it too).
- RSDP: taken from the EFI configuration table and copied into an ACPI-reclaim page below 1 GiB, so the unchanged kernel finds it in the map.
- Low allocations (mbi, module table, modules, map) are placed from 32 MiB upward (the kernel only maps the first GiB and uses windows near 1 GiB, e.g. fb `win=0x3e400000`).
- Errors (missing/broken config with line number, missing kernel/module, not ELF32, no multiboot header, kernel range not RAM, ExitBootServices failed) are printed and the loader returns to the firmware after 5 s — no hang.

## Gate and bench
- `tools/bootloader/run.sh` (STICK_IMG/KERNEL optional, else full stick build): login screen via osboot on OVMF q35+EHCI, i440fx+IDE, q35+NVMe; counter-proofs broken config (line number), missing kernel, missing config (message, return to firmware, no kernel line); `default` beyond the entry count boots entry 1; Limine control stick reaches login without osboot lines.
- `LOADER=osboot bash tools/ovmfboot/run.sh`: the OVMF cases of the ovmfboot gate with osboot (each limine.conf variant converted by mkcfg.py) plus "started by osboot" per UEFI boot; SeaBIOS cases stay on Limine.
- `tools/bootloader/bench.sh` (RUNS, MACH, BUS, WANT): time from QEMU start to `glogin: rect`, osboot and Limine alternating, both timeout 0.
- Former hang after `osum: from module` (i440fx+IDE): not the loader. The test stick carried a kernel without the IDE nIEN fix (c2c2b3da); the same stick hangs at the same line with Limine. The kernel reserves mbi page, module table, modules and map by whole frames, so loader data placement is safe.

## Open
- BIOS path (MBR + stage2), ab.fi/installer/usbimg switch to osboot.cfg (OTA flips only limine.conf today).
