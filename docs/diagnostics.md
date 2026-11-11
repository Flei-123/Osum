# Diagnostics inventory (11.11.2026)

## What exists
- **klog** (`kernel/klog.fi`): ring of 510 entries x 128 B, levels DEBUG..ERROR, seq/ns/pid/core/source, serial level, warn counter (`KL_WARNS`).
- **Read paths:** `/dev/klog` (read/write), `/proc/klog`, syscall `SYS_KLOG` (`KL_LINE`, `KL_SEQ`, ...), `log` (legacy), `dmesg`, `klog`.
- **Persistence:** `kernel/diag/klogsave.fi` writes the ring to `/var/log/klog`, `.1`..`.3` (4 x 256 KiB, per-boot and per-size rotation, header `# klog boot N`). Triggers: `klogd` (every 1 s, flush on WARN+ and every 5 s), `klog -x`, kernel panic/hang report (`crash.ablegen`).
- **Crash/hang:** `kernel/diag/{crash,hang,stall,nmiguard,svcwatch,panicnote,safe}.fi`, reports in `/var/crash/<time>.txt`, tools `tools/nmi`, `tools/stall`.
- **Hardware/net:** `/proc/{usb,usbnet,pci,wlan,bench,sysmon,frames,drivers}`, `drvctl`, `lspci`, `regdump`, netdiag (`kernel/app`), `taskmgr`, ODB agent.

## Commands
- `dmesg [-n N] [-l LEVEL] [-s SUBSYSTEM] [-y MS] [-t] [-w] [-p]` — `-p` prints the previous boot from `/var/log/klog*`.
- `klog` — as dmesg plus `-z` stats, `-x` save now, `-a TEXT` add line, `-q LEVEL` threshold (root), `-F N` write N test lines.

## Missing vs Linux
- No hotplug/link event log with reason codes (DG-b), no `netdiag` command (DG-c), no sampling profiler/strace (DG-d), no `diag bundle` (DG-e), no `lsusb`/`lspci -v` (DG-f).
- No `/proc/kmsg` blocking reader; follow mode polls `SYS_KLOG` every 100 ms.
- Early-boot lines before `klogd` starts are only persisted if still in the ring (510 entries).
- Settings "System Log" page not built yet.

## Gate
`tools/klogpersist/run.sh` (QEMU NVMe root): save, previous boot, panic persistence, filters, rotation, mutant without panic save.
