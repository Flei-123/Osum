# AHCI driver layout

`kernel/drv/blk/ahci.fi` is the public facade (one-line wrappers, `resume`). The code lives in `kernel/drv/blk/ahci/`, lowest layer first. Firn has no re-export and module names are global by last path segment, hence the `ahci_` prefix.

| Module | Job |
|---|---|
| `ahci_defs` | register/bit/timing constants, scalar-page slots, memory-map offsets (read by `tools/kernel/memmap.py`), shared statics (`idle_known`, `wait_polls`) |
| `ahci_state` | scalar-page accessors (`blocks`, `mode`, `dead`, ...), `ident`, `buffer`, log tag |
| `ahci_clock` | TSC deadlines: `timeout`, `expired`, `usec`, `tnow` |
| `ahci_hook` | test hooks (`slowsata`, `lostsig`, `oldsata`) that distort port registers |
| `ahci_reg` | port register access (`prd`, `pwr`), MMIO helpers |
| `ahci_present` | controller presence, RAID class, IDE fallback |
| `ahci_wait` | MSI arm/disable, IRQ handler, `sti;hlt` sleep, lost-interrupt fallback, `wait_done` |
| `ahci_lock` | per-driver lock and its counters |
| `ahci_recover` | error path: `recover` (stop/restart port), `kill` (HBA reset, S3 simulation) |
| `ahci_port` | port stop/arm/setup, `await_idle` |
| `ahci_cmd` | command header, H2D FIS, PRDT |
| `ahci_run` | issue one command, verdict, counters |
| `ahci_ident` | IDENTIFY DEVICE decode (capacity, sector size) |
| `ahci_link` | per-port link state machine: COMRESET, verdict per poll |
| `ahci_scan` | `find_disk`: arm all ports, COMRESET together, poll, pick the lowest ATA port, log |
| `ahci_xfer` | block and multi-block read/write, flush, bounce buffer |
| `ahci_hba` | BIOS handoff, HBA reset, Intel PCS repair, controller logging |
| `ahci_init` | `init` / `init_inner` bring-up sequence (`why` = 1..10) |

`resume` (after S3) = `init` again when the driver was in AHCI mode; `kill` simulates power loss.

## Why the scan looks like this (Dell OptiPlex 9020, class 01:04)

- All waits are TIME based (TSC). A loop count is calibrated against one machine (KVM ~1.5 us per register read, real chipset ~0.8 us) and made the Dell give up after 80 ms per port.
- PxSIG is filled from the first D2H FIS. After the HBA reset the device sends it while PxCMD.FRE is still 0 and the controller drops it. So every port is armed first (command list, FIS area, FRE, SUD/POD) and COMRESET (PxSCTL.DET = 1 for >= 1 ms, then 0) comes afterwards. QEMU fills PxSIG at reset, which is why it never failed there.
- All ports are scanned at the same time. Verdicts: EMPTY (DET stays 0 for `EMPTY_US`), ATA, OTHER (ATAPI, port multiplier: seen, never chosen), BROKEN, NOSIG (link up, idle, no signature after 3 COMRESETs: tried with IDENTIFY). The lowest ATA port wins; the scan stops as soon as an ATA disk is ready and no lower port is undecided.
- A port with a half-negotiated link (DET = 1) for `STUCK_US` gets another COMRESET (at most 3). A spinning-up HDD (BSY) is waited for up to `READY_US`.
- Everything the scan saw goes to the klog (`grep ahci /proc/klog`).

## Other design notes

- Transfers go through the driver's own page-aligned bounce buffer A for single blocks: the FAT writer's buffers are not always physically contiguous (QEMU q35 install, 27.09.2026, wrong bytes in scattered sectors).
- No FLUSH CACHE after every write (w-disklag): durability is the caller's job at journal commit points, `sync` and shutdown (`blk.flush`). The test word `ahcislow` brings the per-write flush back.
- Bring-up failures leave `why`: 1 no controller, 2 BAR5 not memory, 3 cannot map, 4 CAP unreadable, 5 BIOS handoff, 6 HBA reset, 7 no ports, 8 no ATA disk on any port, 9 port setup, 10 IDENTIFY.
