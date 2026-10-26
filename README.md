# Osum

Osum is an operating system kernel for x86-64, written from scratch in
[Firn](https://github.com/Flei-123/Firn), with no Rust, C or external
library in the kernel itself. The repository also contains the userland, the
desktop and the tools that build a bootable system from it. That system is
called **XoffiOS**; the kernel is called `osum` in every edition.

The product name is not hard-coded: it is set through the brand files
(`marke.conf`, overridable at build time), so a differently named edition
needs no source change.

## What it can do today

**Kernel** (`kernel/`)

- Boots through Multiboot on BIOS and UEFI from the same image.
- Own memory management, one address space per process, preemptive
  scheduler with SMP, signals, futexes, a capability/handle model
  (`kernel/ipc/cap.fi`).
- Kernel hardening: SMEP and SMAP, encrypted-boot support, AES-NI, Argon2.
- File systems (`kernel/fs/`): OFS (own), FAT, exFAT, ext4, NTFS, VFS with
  `/proc` and `/dev`; MBR and GPT partition tables.
- POSIX layer using the Linux x86-64 system call numbers; Linux programs are exercised in `tools/alpine/` and `tools/linuxapps/`.
- Power management: battery, ACPI, standby (S3), backlight, hotkeys.
- eBPF machine, verifier and hooks (`kernel/net/ebpf*.fi`).
- A hypervisor for AMD-V (`tools/hv/`).

**Drivers** (`kernel/drv/`)

- Storage: AHCI/SATA, NVMe, USB mass storage.
- USB: xHCI, EHCI, OHCI, HID, USB network adapters.
- Network: virtio-net, Intel e1000, Realtek r8169, SSH-2 server
  (`kernel/user/sshd.fi`), WireGuard, TCP/IP stack with sockets.
- Graphics: framebuffer, virtio-gpu, VMware SVGA, software 3D path.
- Audio: Intel HDA, AC'97, mixer.
- Input: PS/2, USB HID, I2C HID, touchpad configuration.

**Desktop and userland** (`kernel/ui/`, `kernel/user/`)

- Window server with tiling, TrueType text with anti-aliasing, themes,
  light and dark mode, graphical login, lock screen, taskbar, system tray.
- Own shell and the usual command-line tools (`ls`, `cp`, `grep`, `sed`,
  `diff`, `tar`, `gzip`, `find`, `ping`, `wget`, ...).
- Applications: file manager, text editor, settings, task manager, calculator,
  contacts, calendar, notes, image/PDF/media viewers, screenshots.
- The Certus web browser as an ordinary ring-3 program
  (`assets/apps/certus.osp`).
- Package store, application bundles (`*.osp`), over-the-air updates and a
  backup tool with deduplication.
- Installer that writes a bootable system to a disk, and a live mode that
  leaves the stick untouched.

**Images**

- `tools/usbimg/build.sh` builds a bootable USB image for BIOS and UEFI.
- `tools/build-kernel.sh --gui off` builds a kernel without any graphics code
  for server use.

## Not there yet

- No working WLAN radio driver; the protocol stack and the driver interface
  exist (`lib/wlan/`, `docs/WLAN.md`).
- No GPU driver for real graphics hardware and no OpenGL or Vulkan.
- Only x86-64 boots. The machine boundary for AArch64 and a first AArch64
  floor exist (`docs/ARCH.md`); the kernel itself is not ported.

## Building and running

Requirements: `bash`, `git`, `rustc` and `cargo` (to build the pinned Firn
compiler), `binutils`, `python3`, `qemu-system-x86_64`. The USB image
additionally needs `mtools`, `sgdisk` and a Limine checkout (`LIMINE_DIR`).

```sh
git clone https://github.com/Flei-123/Osum.git osum
cd osum
./vendor/firn/fetch-firnc.sh           # once: builds the pinned Firn compiler
export FIRNLIB="$PWD/lib"
bash tools/build-kernel.sh /tmp/k.mb   # kernel image
LIMINE_DIR=/path/to/limine bash tools/usbimg/build.sh /tmp/build  # bootable image: /tmp/build/orientos-usb.img
```

Run the acceptance suite (starts QEMU once per case; takes a long time):

```sh
./test.sh
```

Each section has its own runner: `bash tools/<name>/run.sh`. Every claim
is paired with a counter-check that has to fail when the property is switched
off.

## Layout

| Path | Contents |
|---|---|
| `kernel/` | the kernel, by area (`arch`, `mm`, `sched`, `fs`, `drv`, `net`, `ui`, ...) |
| `kernel/user/` | shell, tools, desktop and applications |
| `lib/libc/` | the libc, in Firn |
| `lib/wlan/` | WLAN protocol stack |
| `tools/` | one build or test runner per area |
| `assets/` | fonts, icons, themes, application bundles |
| `vendor/firn/` | the pinned Firn compiler (only the commit hash and a fetch script are in the repo) |
| `docs/` | design and measurement documents |

Source comments and the documents in `docs/` are partly written in German;
this README is the English entry point.

## Licence

Two licences; the dividing line is ring 0 against ring 3.

- **GPL-2.0-only** for the kernel, the ring-3 programs, tools and tests
  ([LICENSE](LICENSE)).
- **MIT** for the ring-3 libraries programs link against (`lib/libc/`,
  `kernel/user/crt.s`, `ulib.fi`, `wlib.fi` and others), so programs for
  Osum may use any licence, including closed source
  ([LICENSE.MIT](LICENSE.MIT)).

Every source file carries an `SPDX-License-Identifier` line, which is
authoritative for that file. Reasoning and file list:
[LICENSING.md](LICENSING.md); third-party material:
[THIRD_PARTY.md](THIRD_PARTY.md).
