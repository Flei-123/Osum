# bench -- in-OS benchmark tool

`/bin/bench` (kernel/user/bench.fi, ring 3) measures the running system and prints a table or one JSON line.

    bench                table of all groups
    bench --json         one line: BENCHJSON {"schema":1,"commit":"<8hex|unknown>","arch":"x86_64","results":{...},"units":{...}}
    bench <group>...     boot mem idle size syscall fs memcpy cpu (or `all`)

Kernel side: `/proc/bench` (boot milestones in ms since kernel_main, kernel heap, trap count, `tsc.khz`).
Boot marks are rdtsc stamps in kstate `BM_BASE`=1800 (8 words, written by kmain.fi).

## Notes on the numbers (first QEMU/KVM run, fast image, 2 vCPU)
- `syscall.pipe_rtt_block_ns` (~9.4 ms) and `syscall.exec_exit_wait_us` (~9.7 ms) are bound by the 10 ms scheduler tick: a blocked
  reader wakes at the next tick. That is a real latency finding, not a measuring error (poll-based pipe rtt: ~15 us).
- `fs.meta_ops_s` ~100/s is tick bound as well (create/unlink wait for the tick).
- `alloc.*`: the brk region is only 448 KiB (BRK_BASE..MMAP_TOP), so the test grows 256 KiB, touches, shrinks, 8 rounds.
- `idle.cpu_busy_permille` and `idle.ctxsw_per_s` exist only with per-core counters (CS_COUNT > 0, i.e. firmware tables);
  the QEMU `-kernel` fast image has none -> keys are left out instead of printing a fake value.
- Port I/O per second stays host side (tools/portio, QEMU trace).

## Gate
`bash tools/bench/inos.sh` (~1.5 min): fast image + odbd, `odbc exec "bench --json"`, `tools/bench/check_inos.py`
(required keys, numeric, plausible ranges). Counter-proofs: doctored JSON (missing key, zero, string, schema 2, huge value) and the
same `bench` on a kernel built from the parent of the bench commit (no `/proc/bench`) -> checker red.
`BENCH_KEEP=<dir>` reuses builds, `BENCH_HOLD=<s>` keeps the guest up for manual `odbc` sessions, `BENCH_JSON_OUT=<file>` keeps the JSON.
