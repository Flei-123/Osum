# Osum vs Linux: analysis (11.11.2026, main 26c582d0b, server load 27-47)

Run: `/root/jarvis/bin/heavy bash tools/speedcmp/run.sh` (env: SPEED_RUNS, SPEED_SMP, SPEED_MEM, OSUM_DRIVE/LINUX_DRIVE = ahci|ide|virtio|nvme, SPEED_KERNEL = prebuilt osum.mb, SPEED_OSUM_WORDS, SPEEDCMP_CACHE keeps the Debian download, SPEED_OUT keeps the raw serial logs). Table: `docs/speed-osum-vs-linux.md` / `.tsv`.

## Three largest gaps
1. **Warm file reads (480x for 4 MiB, 95x for 512 KiB; file mmap per page 574x with 8 MiB, 4.8x with 512 KiB).** The page cache has 256 slots (`kernel/fs/pcache.fi`: SETS 32 x WAYS 8 = 1 MiB). A 4 MiB or 8 MiB working set cycles through it and every read goes to the disk again: 8x the data costs 41x the time. Even a hit is slow (64 us per 4 KiB page). Fix candidates: size the cache from RAM, cheaper hit path.
2. **File write (244x for 4 MiB, 82x with fsync).** About 13 ms per 64 KiB write call, 5 MB/s. Same cache limit plus a slow write path; `write 64 B /dev/null` alone costs 16.6 us (41x), `read /dev/zero` 6 us (12x), so the generic read/write layer (`sysfd.file_io_loop`, `do_write`) has a high fixed cost.
3. **exec (200x) and fork (26x), thread create (20x).** exec of a dynamic musl binary needs libc.so (about 700 KB) through gap 1; fork and thread create are dominated by page allocation: anon first-touch fault costs 12 us against 0.95 us on Linux (13x). The in-OS numbers (exec 1.5 ms, fork 50 us, getpid 265 cycles) are for small kernel-linked programs; the Linux-ABI ELF path is far slower.

## Further findings
- Per-syscall fixed cost 1.6 us (about 5000 cycles) from an ELF program against 265 cycles in the in-kernel hbench; getpid and lseek are equal, so it is the entry/exit path, not the work. Needs a profile (frameprof).
- Pipe round trip equals Linux (26 vs 31 us) but one earlier run with `nosched` on 2 vCPUs gave 2 ms: cross-CPU wake latency is not stable.
- Linux numbers are also slowed by the loaded server (getpid 240 ns).

## Caveats
- Osum boots with `nosched noproc nofs` (as tools/unterbau); a run without those words gave the same picture.
- Same disk type (AHCI) on both sides, but IDE showed the same read/write cliff on Osum.
