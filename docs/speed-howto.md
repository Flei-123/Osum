# Speed matrix: how to measure and lower a budget

One shared yardstick for every speed worker: `docs/speed-osum-vs-linux.tsv` (columns `test linux osum ratio budget status`, times in microseconds per operation).

## Measure
- Full matrix + gate: `/root/jarvis/bin/heavy bash tools/speedcmp/gate.sh` (about 50 tests, Osum and Debian 13 boot concurrently in the same QEMU/KVM setup, median of 5 boots, red tests are re-run once and the lower ratio wins). Needs the Debian image in `SPEEDCMP_CACHE` (default `/root/abbilder/speedcmp-cache/debian.qcow2`).
- Only some tests, own kernel, keeps the committed table untouched:
  `SPEED_KERNEL=<osum.mb> SPEED_ONLY="file_read_4mib_warm fstat" SPEED_RUNS=5 SPEED_OUT=<dir> SPEED_MATRIX_ONLY_OUT=1 bash tools/speedcmp/measure.sh`, then
  `python3 tools/speedcmp/matrix.py build <dir> --tsv <dir>/m.tsv`.
- Osum side only (A/B of two kernels, started at the same time): `tools/speedcmp/osum.sh <outdir> <bench-binary>` with `SPEED_KERNEL`, `SPEED_ONLY`.
- Knobs: `SPEED_SMP` (2), `SPEED_MEM` (1024), `SPEED_RUNS` (5), `OSUM_DRIVE`/`LINUX_DRIVE` (ahci|ide|virtio|nvme), `SPEED_OSUM_WORDS`, `SPEED_DISK_BLOCKS` (393216), `SPEED_RERUN=0` (no outlier rerun).
- Noise: Osum and Linux boots run concurrently, server load is logged every 10 s in `load.log` (mean and max go into the table notes). Compare only values from the same run, never against old tables.

## Add a test
1. Write the bench function in `tools/speedcmp/sb*.h` (module per area: `sbio.h` files, `sbmeta.h` metadata/mm, `sbproc.h` process/ipc/net), print with `measure`/`measure_timed`; on setup failure call `emit_fail(name)`.
2. Add one row to `tools/speedcmp/tests.tsv` (test, group, label).
3. Run the gate with `--ratchet` once: the new test gets budget = ratio x 1.25 (rounded up).

## Lower a budget
- Budgets live in `tools/speedcmp/budgets.tsv` (`test budget`; `-` = not gated, e.g. unsupported). Target for every test is 1.0.
- Rule: a budget may only go down. `gate.sh --ratchet` lowers budgets to measured ratio x 1.25 where the measurement improved, never raises. The gate is red if a ratio is above its budget, if a gated test fails or has no data, or if a budget is higher than on `origin/main`.
- After your optimization: run the gate with `--ratchet`, commit the new `budgets.tsv` plus the regenerated `docs/speed-osum-vs-linux.*` in the same commit as the fix.

## Metrics and Firefox share
- `gate.sh --metrics` writes `docs/speed-metrics.jsonl` (one `project_metric` record per test: key `speed <test>`, value ratio, project OrientOS). Set `SPEED_METRIC_CMD=<script>` to have `matrix.py metrics` call it per test (args: key value unit target note).
- Which gaps cost Firefox the most: `python3 tools/speedcmp/fxshare.py --samples <samples.txt> --elf <osum.mb.elf> --t0 <start>` (kernel stack samples from `tools/linuxapps/prof/walltime.sh`) or `--hist <handler<TAB>samples file>`. Sorts by share of wall time x (1 - 1/ratio) = time saved at ratio 1.0. Handler-to-test mapping in `tools/speedcmp/fxmap.tsv`.

## Reading the table
- `status`: `pass` ratio <= 1.0, `ratchet` above 1.0 but within budget, `red` over budget, `fail` Osum could not run the test, `nodata`, `nobudget` (run `--ratchet`), `unsupported` (budget `-`).
- Cold reads drop the page cache on Linux through `/proc/sys/vm/drop_caches`; Osum has no such knob, so the bench evicts by writing and reading an 8 MiB spill file.
