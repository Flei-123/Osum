# Layers

One direction only: a layer imports itself and the layers BELOW it, never above.

| rank | layer | what | where |
|---|---|---|---|
| 0 | ext | the pinned Firn library (`std.rt`, `std.io`, `fui.*`) | `vendor/firn/lib` (not in the tree) |
| 1 | std | what every program links: libc, byte/text/path helpers, the program runtime, transfer/message modules | `lib/libc`, `lib/std`, `lib/utf8.fi`, `lib/urilist.fi`, `kernel/user/{ulib,xfer,msg}.fi` |
| 2 | syslib | protocol and device libraries without UI | rest of `lib/*` |
| 3 | framework | UI toolkits: fUi, nav kit, wlib/wlibc, scene runtime | `lib/fui`, `lib/nav`, `kernel/user/{wlib,wlibc,fuiscene}` and their facade files |
| 4 | kernel | ring 0: arch, mm, sched, fs, drivers, net, sys calls, kernel GUI | `kernel/*` except `kernel/user` |
| 5 | app | programs and services | `kernel/user/**` |

The kernel never imports `kernel/user`, programs never import `kernel/*`; both only share ranks 1-3.
The map is `tools/layers/layers.tsv` (longest prefix wins, `dir/.` = files directly in `dir`). A file without a rule fails the gate: new directories must be registered.

## Gate

`bash tools/layers/run.sh` (quick, host, seconds). It fails on a NEW upward import, a NEW file in an import cycle, a NEW giant file (> 2000 lines), a NEW loose file in the repo root, an unmapped file, or growth of the duplicate/shared counters. Counter-probes build synthetic trees with each violation and must fail. `python3 tools/layers/layers.py update` tightens `baseline.json` after a cleanup (refuses to grow without `--force`). `layers.py report` prints the counters, `layers.py table` the unit table below.

## Audit (counted by the gate)

| finding | count | note |
|---|---|---|
| upward imports | 0 | was 40 edges: 1 real (`libc.clockapi` -> `ntp.abi`; `abi.fi` moved to `lib/libc/clockabi.fi`) + 39 from facade files that sit in `kernel/user` (mapped to their true layer by file rule) |
| files in import cycles | 324 | ONE strongly connected group, all ring-0 (drv, ui, acpi, fs, diag, net, bus, block, sched, sys, arch, gfx); 33 directory units in 2 groups |
| giant files (> 2000 lines) | 39 | mostly `kernel/sys`, `kernel/drv`, `kernel/ui`, `kernel/user` |
| loose files in repo root | 62 | `BEFUND-*`, `STATUS-*`, `*-STATUS.md`, logs: belong under `docs/` |
| shared modules inside `kernel/user` | 115 | imported by >= 2 files but live beside the programs: belong in `lib/` (flat imports make the move a rewrite of every importer) |
| duplicated function bodies | 605 groups, 1518 copies (was 667 / 1866) | `ld8` 10 copies, `st8` 7, `lower` 14, `zero` 11, `rd` 9; rest are mmio variants with other types and thin wrappers |

## Std library (`lib/libc`)

Existing: kcall, errno, io, stdio, mem, text, proc, net, dns, dnswire, icmp, clockapi.
Added: `octets` (8/16/32/64 bit LE and BE loads/stores, zero), `numeric` (min/max/clamp/abs), `hexdigit`, `pathname` (base_name, parent_length, join, extension), `fileops` (exists, read_all, write_file, copy_file), `textsearch` (starts_with, ends_with, find_text, equal_fold), `locks` (atomics, spin lock, futex mutex), `clockapi` (+ ticks, uptime_sec, sleep_ms), `clockabi`.
Test: `bash tools/libc/run.sh` (host suite + broken-module counter-proofs).
Threads: `lib/jobs` is the thread pool (clone + futex); a `libc.threads` wrapper is still open.

### Rename `lib/libc` -> `lib/std`: NOT done

Not mechanical. `lib/std` already exists and overlays the pinned Firn `std.*` (595 imports of `std.rt/io/net/fs/...`). A flat use-name is the last path component, so `libc.io` would become `std.io` and collide with Firn's `std.io` (111 importers), likewise `std.net`, `std.fs`, `std.str`. A rename needs the Firn modules renamed first.

## Waves still open

1. Dup helper migration is done for exact matches (`tools/layers/migrate/migrate.py`, `EXT=1` also rewrites `stem.name(` call sites and drops exports; `buildall.sh` compares the compile result of all programs against a baseline). Open: wrapper inlining (`fn f(x) { return mod.f(x) }`), `libc.threads`.
2. Move the 115 shared modules out of `kernel/user` into `lib/` (std/syslib/framework by the map).
3. Split the 39 giant files; break the ring-0 cycle by giving `kernel/lib` the shared interfaces.
4. Move root clutter under `docs/`.

## Unit table

| unit | layer | files |
|---|---|---|
| lib | std | 7 |
| lib/libc | std | 20 |
| lib/std | std | 15 |
| lib/apprights | syslib | 3 |
| lib/audio | syslib | 8 |
| lib/bt | syslib | 1 |
| lib/bulkren | syslib | 1 |
| lib/color | syslib | 1 |
| lib/crypto | syslib | 21 |
| lib/dbgsrv | syslib | 3 |
| lib/disks | syslib | 6 |
| lib/entropy | syslib | 4 |
| lib/fv | syslib | 9 |
| lib/gpu | syslib | 6 |
| lib/hwcheck | syslib | 1 |
| lib/hwinv | syslib | 6 |
| lib/jobs | syslib | 1 |
| lib/keymap | syslib | 1 |
| lib/mail | syslib | 3 |
| lib/modpolicy | syslib | 2 |
| lib/monitors | syslib | 2 |
| lib/net | syslib | 3 |
| lib/netdiag | syslib | 6 |
| lib/netui | syslib | 1 |
| lib/ntfsshrink | syslib | 18 |
| lib/ntp | syslib | 5 |
| lib/oracleio | syslib | 1 |
| lib/pdfread | syslib | 8 |
| lib/pngfit | syslib | 5 |
| lib/power | syslib | 3 |
| lib/settingsman | syslib | 1 |
| lib/smb | syslib | 11 |
| lib/socks | syslib | 1 |
| lib/spirv | syslib | 5 |
| lib/ssh | syslib | 3 |
| lib/stickwr | syslib | 1 |
| lib/svg | syslib | 9 |
| lib/sync | syslib | 1 |
| lib/tls | syslib | 11 |
| lib/touchev | syslib | 5 |
| lib/touchgest | syslib | 3 |
| lib/tpm | syslib | 4 |
| lib/tz | syslib | 3 |
| lib/usbnet | syslib | 10 |
| lib/uvc | syslib | 1 |
| lib/vault | syslib | 18 |
| lib/vaultd | syslib | 15 |
| lib/wg | syslib | 1 |
| lib/wlan | syslib | 66 |
| lib/xhciiso | syslib | 1 |
| kernel/user/fuiscene | framework | 6 |
| kernel/user/wlib | framework | 6 |
| kernel/user/wlibc | framework | 5 |
| lib/fui | framework | 18 |
| lib/nav | framework | 8 |
| kernel | kernel | 9 |
| kernel/acpi | kernel | 31 |
| kernel/app | kernel | 32 |
| kernel/arch | kernel | 19 |
| kernel/block | kernel | 14 |
| kernel/bus | kernel | 17 |
| kernel/crypto | kernel | 5 |
| kernel/diag | kernel | 21 |
| kernel/drv | kernel | 85 |
| kernel/fs | kernel | 39 |
| kernel/gfx | kernel | 17 |
| kernel/ipc | kernel | 9 |
| kernel/ldr | kernel | 9 |
| kernel/lib | kernel | 11 |
| kernel/mm | kernel | 1 |
| kernel/net | kernel | 29 |
| kernel/pwr | kernel | 9 |
| kernel/sched | kernel | 17 |
| kernel/sync | kernel | 1 |
| kernel/sys | kernel | 14 |
| kernel/ui | kernel | 64 |
| kernel/uprog | kernel | 3 |
| kernel/usb | kernel | 6 |
| kernel/user | app | 446 |
| kernel/user/certus | app | 1 |
| kernel/user/explorer | app | 4 |
| kernel/user/lineedit | app | 6 |
| kernel/user/mkfs | app | 9 |
| kernel/user/odbd | app | 3 |
| kernel/user/orientbus | app | 4 |
| kernel/user/ota | app | 4 |
| kernel/user/settings | app | 7 |
| kernel/user/taskbar | app | 8 |
