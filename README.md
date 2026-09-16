# Osum

An operating system kernel for x86-64, written from scratch in **Firn**
(an own programming language, see `../firn`). Boots via Multiboot on BIOS
and UEFI, with its own memory management, processes, filesystem, drivers
and window server. On top of it sits **OrientOS** — the desktop and the
applications.

**Started:** 19 Aug 2026 (first commit of this repository; the kernel
itself is older and came out of the Firn repository).

## Where it stands (16 Sep 2026)

**Size:** 1,445 commits, 419 own `.fi` files, **344,119 lines**
(excluding `vendor/`).

**Kernel**
- Boots BIOS and UEFI via Multiboot.
- Own memory management, one address space per process, preemptive
  scheduler. SMP: 3.54× speedup on 4 cores.
- OFS (own filesystem), FAT32, MBR/GPT, VFS with `/proc` and `/dev`.
- POSIX layer using Linux x86-64 syscall numbers, plus an own
  handle/capability model (`kernel/cap.fi`).
- SMEP/SMAP enabled, panic reports with resolved symbols in `/var/crash`.

**Networking**
- virtio-net, e1000, Realtek RTL8168/8169. TCP/IP stack and sockets.
- Measured against a real Linux kernel: 75 checks, `ping` 10/10, 1 MiB
  over TCP with no retransmit loss, recovery at 10 % packet loss.
- SSH-2 server; a real OpenSSH client logs in.

**Desktop**
- Window server, mouse, TrueType with antialiasing, tiling window model,
  light/dark mode, theme system with colour and shape tokens.
- **Login and lock screen:** graphical login before the desktop, PBKDF2
  password store (`$osum1$`, 8192 rounds, per-account salt), lock screen,
  idle lock, and logout that really ends the session.
- **Taskbar:** pinned programs on the left (visible even when the program
  is not running), reorderable by dragging, order kept in
  `/etc/taskbar.conf` — survives a reboot.
- **Status area on the right:** WLAN, sound, battery with percentage,
  two-line clock with date.
- **Window layers as on Windows:** the taskbar always stays on top,
  windows may be pushed underneath. Maximising stops at the work area.
- **Fullscreen with F11:** whole screen without decoration, returning to
  exactly the previous geometry.
- The window server runs in ring 0, not as a separate process.

**Userland**
- Own shell (`if`/`for`/`while`/`case`/functions), ~25 standard tools
  (`find`, `sed`, `diff`, `patch`, `tar`, `gzip`, …).
- File manager (`explorer.fi`), text editor, settings, taskbar,
  calculator, snipping tool, image viewer, media playback (WAV, MP3),
  recycle bin.
- ZIP/TAR/GZIP natively (real deflate/inflate, CRC-32).
- Backup with content addressing and deduplication, crypto-erase in 20 ms.
- **Certus (an own web browser) runs as an ordinary ring-3 program.**

**Installation and removable media**
- Installs onto a disk from the desktop: GPT/EFI written, root copied,
  and the system boots from the disk without the stick. Acceptance run
  `tools/install/abnahme.sh`: 35 checks, 0 failures.
- USB sticks are mounted and ejected at runtime under `/medien/usbN`.
  The filesystem is detected by content, ejecting reports `E_BUSY` while
  files are open, and pulling a stick without ejecting clears the table
  without writing. Acceptance run `tools/hotplug/run.sh`: 33 checks, 0
  failures — driven through the QEMU monitor with `device_add`, the same
  change a hand at the connector makes.

**Third-party software**
- Statically linked musl binaries for Linux run unmodified.
- Lua 5.4.7 complete, busybox with 15 measured applets, SQLite creates
  databases.

**Real hardware**
- The USB image boots via BIOS and UEFI on real hardware.
- AHCI/SATA, Realtek networking and Intel HDA audio measured on bare metal.
- Up to 2560×1080, EDID-based scaling.

## What is still missing

- **WLAN** — there is no radio driver. Frames, profiles and the MAC
  layers exist (`lib/wlan/`, 10 files), but Osum does not connect to any
  network: firmware loading, scanning, the WPA2/WPA3 handshake, the
  regulatory domain and a driver per chip family are all absent.
- **No GPU driver, no OpenGL or Vulkan.** There is virtio-gpu
  (`kernel/vgpu.fi`) and a software 3D path (`kernel/r3dsoft.fi`), but
  nothing for real graphics hardware.
- **Drag and drop has no target** — the source hands over, nobody accepts.
- No NTP and no timezone database; only a fixed offset via `tz=`.
- No standby (S3), no Bluetooth, no printing, no PDF viewer, no video
  decoding.
- The kernel is not part of the A/B update switch yet.
- Only x86-64 — there is no architectural obstacle to an aarch64 port.

The full list with stable IDs lives outside this repository, in the
roadmap files (`OFFEN.md`, `ERLEDIGT.md`, `INVENTAR.md`).

## Building and running

Requires: `bash`, `git`, `rustc`/`cargo`, `binutils`, `python3`,
`qemu-system-x86_64`.

```sh
git clone <this repo> osum
cd osum
FIRN_REPO=/path/to/firn ./vendor/firn/fetch-firnc.sh   # once: fetch the Firn compiler
./test.sh                                              # full acceptance, QEMU per case
```

Start the kernel with a screen:

```sh
qemu-system-x86_64 -kernel /tmp/k.mb -m 256 -append "osum gfx" \
   -serial stdio -vga std
```

With windows, mouse and fonts (the image needs `/lib/mono.ttf` and
`/lib/sans.ttf`):

```sh
python3 tools/osum/mkfs.py build /tmp/d.img 4096 /lib/ \
   /lib/mono.ttf=assets/osum-mono.ttf /lib/sans.ttf=assets/osum-sans.ttf
qemu-system-x86_64 -kernel /tmp/k.mb -m 256 -append "gfx wm wmhold" \
   -serial stdio -vga std -drive file=/tmp/d.img,format=raw,if=ide,index=0
```

Individual sections: `bash tools/<name>/run.sh`.

## Layout

| Path | Contents |
|---|---|
| `kernel/*.fi` | the kernel |
| `kernel/user/*.fi` | shell, tools, userland library |
| `lib/libc/*.fi` | the libc |
| `tools/` | one test runner per section |
| `assets/` | fonts, icons, application bundles (`*.osp`) |
| `vendor/firn/` | pinned Firn compiler (only the hash and a fetch script are in the repo) |
| `docs/` | round reports, archive |

Firn is not vendored as source: `vendor/firn/COMMIT` pins one Firn
commit, `vendor/firn/fetch-firnc.sh` fetches and builds it.

A note on language: the source comments, commit messages and the reports
in `docs/` are written in German. This README is the English entry point.

## Licence

Two licences, and the dividing line is ring 0 against ring 3:

- **MIT** for the ring-3 libraries (`lib/libc/`, `kernel/user/crt.s`,
  `ulib.fi`, `wlib.fi` and others). Programs for Osum may ship under any
  licence, including closed source. Full text: `LICENSE.MIT`.
- **GPL-2.0-only** for the kernel and for the ring-3 programs, tools and
  tests. Full text: `LICENSE`.

Details and the file list: `LICENSING.md`, `THIRD_PARTY.md`.
