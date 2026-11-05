# LIVEDESIGN — edit on the server, see it on the HP

One command: `bash tools/livedesign/run.sh <program> [out.png] [--no-run] [--no-photo]`
(`vendor/firn/bin/firnc` is fetched on first use). It prints the screenshot path.

## Pipeline

1. Build: `tools/sync/build.sh` for the one program (object cache, `LIVEDESIGN_DIR` default `/tmp/livedesign`).
2. Push: `tools/livedesign/push.py` talks to the local bridge server (`127.0.0.1:8090`, `verwalter.key`), job `write` with a `b64:` payload to `/tmp/ld-<program>`. The target device is the only connected `osum-*` one (`LIVEDESIGN_DEVICE` overrides).
3. Swap + restart: `/bin/jarvisctl swap <src> /bin/<program> --run` (allowlisted command). The swap is hash-verified, the old file stays as `<dst>.old` (`swap --undo` puts it back), `--run` stops old instances of the same name and starts the new one as the session user.
4. Screenshot: `jarvisctl screenshot` then job `photo`, PNG written to the output path.

## New in `jarvisctl swap`

- `--run`: restart the program after the swap (`kernel/user/ctlrun.fi`).
- Parts: a source named `<name>.p0` means "concatenate `<name>.p00`, `<name>.p01`, ... into the destination". The parts are removed after a successful swap. The sha256 is printed and checked by `push.py`.

## Why chunks

The HP freezes its first CPU while a file write syscall runs (IF=0). One 646 KB write (`widgetdemo`, base64 over the bridge) lasted longer than the 10 s hang watchdog and reset the HP (`/var/crash/*-hang.txt`: `reason: watchdog`, `hard-peer`, `cpu 0 last-tick-ms=10304`, kernel `c594ad1e`). Parts of 64 KiB (`LIVEDESIGN_CHUNK`) stay far below the limit; swap itself copies in 4 KiB writes. Bridge writes are limited to 4 MiB per file.

## Measured at the HP (30.10.2026, Xoffi build 4203, bridge via store.fleitec.com)

| Step | widgetdemo (646 KB) |
|---|---|
| build, object cache hit | 0.4 s |
| build, cache miss (one source line changed) | 6.8 s |
| upload, 10 parts | 10.7 s |
| swap + stop + start | 2.4-3.4 s |
| screenshot (permit + photo) | 4.6 s |
| total, cache hit | 19.1 s |

A small program (116 KB `jarvisctl`) uploads in 1.9-3.5 s. Total with a cache miss: build 6.8 s + the measured push/photo time of the cache-hit run (12.3 s) is about 19-26 s; a measured cache-miss end-to-end run on the HP was not possible (HP went silent after the first run).

## Limits

- The loop swaps programs only. Kernel, window manager (`wm.fi`) and `wmd` need a kernel update + reboot.
- After the watchdog reset the swapped `/bin/jarvisctl` was the old file again (112096 bytes, cause not established: the HP `df` shows a 60 GB root, so this is not a RAM disk by size). Treat every reboot as "push again"; `jarvisctl` itself has to be pushed again once with `LIVEDESIGN_CHUNK=200000 python3 -I tools/livedesign/push.py jarvisctl <elf> x.png --no-run --no-photo` because an old `jarvisctl` does not know parts or `--run`.
- `input` is off on the HP, so the program is started but nobody can log in or click through it. The screenshot shows whatever the session shows: at the login screen the new program is running behind it.
- A program must stay below the 16 MiB swap limit.

## Can `firnc` run directly on OrientOS/HP?

Not measured on the HP: `/bin/firnc` is not in the HP `command_allowed` list, and the HP stopped answering before a replacement test (swap of a wrapper onto an allowlisted name was deliberately not done). What is known:

- `/bin/firnc` (1.44 MB) and `/bin/fas` (86 KB) are in the HP image (`/root/abbilder/hp-stick33`). `tools/k16/run.sh` runs firnc on Osum in QEMU: reads a `.fi`, writes `.s`, `fas` assembles it. Needs at most 9 MiB address space (3 MiB image window + 6 MiB arena) and 504 KiB stack (gate asserts it).
- A GUI program imports `lib/` (3.1 MB) and the Firn library `vendor/firn/lib` (29.6 MB) plus `kernel/user` (8.7 MB) as source. That tree would have to sit on the device. Space is no problem on the HP root (`df`: 122880000 blocks of 512 B, 99 % free), but every change would also have to be copied there, so the sources would be pushed instead of one 0.1-0.6 MB binary.
- Server build of one program takes 0.4-7 s (cache hit / miss). A device-side build would first be limited by the 26 KiB/s-class file writes (see above) and by the single-core firnc1 run.

Verdict: not sensible now. The server build + 19 s push is faster and needs no sources on the device. It becomes interesting once the library tree is on the HP root and `firnc` is on the allowlist; the first measurement to take then is `firnc` on `widgetdemo.fi` with `fas`, wall time and peak RAM.
