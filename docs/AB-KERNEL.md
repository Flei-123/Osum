# Kernel A/B (r104) -- finding, 15.10.2026

## What exists
- `kernel/lib/ab.fi` + `/system/TRIAL` (old name `/system/ERPROBUNG` is still read; generation file `/system/CURRENT`, old `/system/AKTUELL`; opk/ota write the new names and remove the old file, ab_boot rewrites whichever exists in place; a slot-B kernel older than this change only knows the old names): trial counter for the USERLAND generation (3 boots without `opk trial ok` -> previous generation). Gate: `tools/update/run.sh` section 4, `tools/ota/run.sh`.
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

## Status 15.10.2026 (W-UPDATE2): option 2 built
- `ab.esp_flip` (kernel/lib/ab.fi): when `ab_boot` rolls the generation back (attempts used up), the kernel mounts the ESP of its boot disk on `/mnt` (first GPT EFI/FAT32 partition of the root device), looks for a line `default_entry: N` at a line start in `/limine.conf` and rewrites the digit to `1` (ONE byte = one sector write), then unmounts (FAT sync). Serial: `ab: esp: default_entry set to 1`; other outcomes: `no gpt`, `mount failed`, `no limine.conf`, `no default_entry`, `default_entry is 1`.
- Arming a slot B is NOT automated yet: nothing writes `osum-b.mb` / `default_entry: 2` / the matching `/system/ERPROBUNG` (that is the OTA kernel-update path, ring 3 needs an ESP write). The kernel half is measured with a hand-armed disk: `tools/abkern/run.sh`.
- Limits unchanged: only kernels that reach `ab_boot` are caught (a kernel that dies earlier still needs option 1, the EFI selector). Single-digit `default_entry` only.

## Status 14.11.2026 (W-HP-FALLBACK9): option 1 built inside osboot
- `boot/uefi/trycount.fi`: when the default entry is not entry 1, osboot reads `/osboot.try` (one digit + newline) on the ESP, boots entry 1 when the digit is >= 2 (`osboot: trial slot failed, falling back to slot 1`), else writes digit+1 and boots the default entry. The count happens before the kernel runs, so kernels that die before `ab_boot` (panic, reset, hang) are covered.
- Reset: `ota` (`otatrial.counter_reset`) writes `0` when it arms the trial (`su_conf_arm`), when it promotes (`su_conf_unarm`) and when it finds the trial lost on slot 1 (`su_finish`, which also puts `default_entry` back to 1 and writes `/var/log/ota-rollback.log`).
- `ab_boot` turns on `crashrestart` (M_PANICBOOT) for every trial attempt so a panic resets after 20 s; the NMI hang detector (default on) resets after a hard hang. Both end in a power cycle that osboot counts.
- `ota boot` health: `desktop` running needs `taskbar` too (when `/bin/taskbar` exists).
- Gate: `tools/abkernel/run.sh`. Limit: UEFI only; BIOS loader has no counter.

