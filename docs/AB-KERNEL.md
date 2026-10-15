# Kernel A/B (r104) -- finding, 15.10.2026

## What exists
- `kernel/lib/ab.fi` + `/system/ERPROBUNG`: trial counter for the USERLAND generation (3 boots without `opk trial ok` -> previous generation). Gate: `tools/update/run.sh` section 4, `tools/ota/run.sh`.
- `ota boot` / `ota watchdog`: confirm after a healthy desktop, reboot on a hang.

## What does NOT exist: a kernel that fails before `ab_boot`
Needs a boot counter that lives OUTSIDE the kernel being tried. Checked 15.10.2026:
- Limine 9.6.7 (`vendor` binaries in OrientOS repo): no boot-once, no counter. Config strings: DEFAULT_ENTRY, TIMEOUT, ... no ONCE/NEXT.
- No kexec in the kernel (`grep -ri kexec kernel` empty).
- UEFI `BootNext` needs runtime-services SetVariable: not used by the kernel.

## Options (ranked)
1. Tiny EFI selector app as the first Limine/firmware entry: reads `\EFI\orientos\AB` (counter + slot), increments, chainloads Limine with `limine-a.conf` or `limine-b.conf` (two Limine copies, each with its own kernel file `osum-a.mb` / `osum-b.mb`). Kernel clears the counter after a healthy boot (needs FAT write from ring 3 = installer code path). UEFI only; BIOS keeps userland-only rollback.
2. Kernel-side flip: the trial kernel (slot B) writes `default_entry` back to A in the ESP `limine.conf` when `ab_boot` sees 3 failed tries. Covers kernels that reach `ab_boot` only (same limit as today, but for kernel changes).
3. BootNext via UEFI runtime variables (needs runtime services in kernel).

Recommendation: 2 first (small, KVM-testable: broken kernel that panics after ab_boot), 1 for the early-death case.
Not started: both need ESP writes from the running system and a two-slot installer layout.
