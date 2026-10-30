# osboot — own boot loader (replaces Limine)

## Today (Limine)
- ESP root: `osum.mb`, `root.img`, `limine.conf` (+ `/boot/limine.conf`), `/EFI/BOOT/BOOTX64.EFI` (Limine), `limine-bios.sys`; BIOS stage via `limine bios-install` (tools/usbimg/build.sh).
- Protocol: multiboot1. `osum.mb` is ELF32 (i386), LOAD at 0x100000 (text) and 0x800000 (data+bss, ~17.5 MiB), entry 0x100030, header flags 7 (aligned modules, memory info, video mode 32 bpp).
- The kernel reads from the multiboot info: flags, cmdline (bit 2, boot words like `nmihard=`), modules (bit 3, `root.img`), memory map (bit 6), framebuffer (bit 12, offsets 88..115). RSDP: EBDA/0xE0000 scan, under UEFI scan of map types 3/4 (kernel/acpi/acpi.fi).
- OTA A/B: kernel/lib/ab.fi rewrites one byte `default_entry: N` in `/limine.conf` on the ESP (confirm/rollback).

## osboot (UEFI, x86_64)
- Sources: `boot/uefi/*.fi` (Firn, `--profile=kernel -c`), `boot/uefi/entry.s` (MS-ABI entry, `efi_call` thunk, handoff trampoline).
- Build: `tools/bootloader/build.sh <out>/BOOTX64.EFI` — firnc ELF object + `ld -m i386pep --subsystem 10` -> PE32+. Code is RIP-relative, no relocations needed.
- Modules: `efi` (table offsets, allocation), `con` (text out, keys), `fsys` (SimpleFileSystem of the boot volume), `cfg` (config), `menu` (entries, timeout, digits/arrows/Enter), `elf32` (multiboot ELF32 + header check), `mbinfo` (multiboot1 info, modules, RSDP copy, memory map, ExitBootServices), `video` (GOP init + multiboot framebuffer tags), `splash` (logo, spinner, key window), `limine_cfg` (limine.conf reader), `tramp` (copy list, own identity page tables).
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
- Errors (missing/broken config with line number, missing kernel/module, not ELF32, no multiboot header, kernel range not RAM, ExitBootServices failed) are printed. With a single entry the loader returns to the firmware after 5 s; with several entries it opens the menu with a 5 s countdown on the next untried entry (slot fallback) and only returns to the firmware when every entry failed.

## Default boot: no menu, logo + spinner (r2309)
- Config keys (all optional): `menu hidden|shown` (default hidden), `keywait <ms>` (key window, default 300, also the minimum logo time), `logo <path>` (default `/osboot.logo`).
- Hidden menu: the screen is filled black, the logo is drawn centered (integer scale `(height+540)/1080`), eight dots rotate below it (80 ms timer event, advanced between 256 KiB read chunks and during the key window). Text output is hidden (attribute black on black) but still goes to the serial console; errors and the menu reveal it again.
- Menu only on Esc, F8 (SimpleTextInputEx scan codes 0x17/0x12), or any keystroke that reports Shift in `KeyShiftState`, read during the key window (keys pressed before the loader started are still buffered); or after a failed entry. `menu shown` keeps the old behaviour (timeout from the config).
- Logo file `/osboot.logo` (`tools/bootloader/mklogo.py <png> <out> [--height 192]`): magic `OBL1`, u32 width, u32 height (little endian), then width*height RGBA bytes. The product name is not part of the loader; the image comes from `assets/marke/start-quelle.png`.
- Entries: `/osboot.cfg` (full or options only). If it has no `entry`, the loader reads `/limine.conf` itself (multiboot1 entries, `default_entry`, `timeout`, `path`/`module_path`/`cmdline`), so `kernel/lib/ab.fi` and OTA keep flipping/arming slots in `limine.conf` unchanged.
- Switch: `OSBOOT=1 bash tools/usbimg/build.sh <out>` puts osboot at `/EFI/BOOT/BOOTX64.EFI` (Limine stays at `/EFI/limine/BOOTX64.EFI` as fallback), writes `/osboot.cfg` (options only) + `/osboot.logo` to the ESP and `/boot/{BOOTX64.EFI,osboot.cfg,osboot.logo}` into the root; the installer copies `osboot.cfg`/`osboot.logo` when present. Default stays Limine.
- r2310 (logo seamless into the kernel) prepared: the framebuffer base/pitch/size are already in the multiboot info (flags bit 12) and the logo stays on screen until the kernel's first frame; the kernel can detect it by `osboot` in the loader name (not set yet) or a boot word and skip clearing the screen.
## Gate and bench
- `tools/bootloader/run.sh` (STICK_IMG/KERNEL optional, else full stick build): login screen via osboot on OVMF q35+EHCI, i440fx+IDE, q35+NVMe; counter-proofs broken config (line number), missing kernel, missing config (message, return to firmware, no kernel line); `default` beyond the entry count boots entry 1; Limine control stick reaches login without osboot lines.
- `LOADER=osboot bash tools/ovmfboot/run.sh`: the OVMF cases of the ovmfboot gate with osboot (each limine.conf variant converted by mkcfg.py) plus "started by osboot" per UEFI boot; SeaBIOS cases stay on Limine.
- `tools/bootloader/bench.sh` (RUNS, MACH, BUS, WANT): time from QEMU start to `glogin: rect`, osboot and Limine alternating, both timeout 0.
- Former hang after `osum: from module` (i440fx+IDE): not the loader. The test stick carried a kernel without the IDE nIEN fix (c2c2b3da); the same stick hangs at the same line with Limine. The kernel reserves mbi page, module table, modules and map by whole frames, so loader data placement is safe.

## BIOS stage in the installer
- `kernel/user/instbios.fi` loads `/boot/osboot-stage0.bin` (440 B) and `/boot/osboot-stage2.bin` from the root image (built into it by `OSBOOT=1 tools/usbimg/build.sh`); `instkern.gpt_write` puts stage0 into the MBR (parameters at 424: ESP LBA, stage2 LBA 256, sector count, magic) and stage2 at LBA 256. Without those files the installer falls back to the Limine BIOS stages.
- `bash tools/install/bios.sh <image-dir>` (`OSBOOT=1 BOOT_KERNEL_COPY=1 tools/usbimg/build.sh <dir>` first; `DISK_IMG=` reuses an installed disk): install, host-side checks, SeaBIOS (AHCI, IDE) and OVMF boot, counter-proofs with zeroed stage2 / stage0.

## Open
- Logo under BIOS.
