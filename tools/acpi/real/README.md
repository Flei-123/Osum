# Real firmware tables

Raw ACPI tables of real machines, one directory per machine, one file per table (`SIG`, `SSDT1`, `SSDT2`, ...).
Used by the ACPI gate (`bash tools/acpi/run.sh`) as test data: parsers are checked against independent parsers of the
same bytes, and the AML loader replays the namespace tables.

| directory | machine | capture | tables |
|---|---|---|---|
| `hp-827d` | HP laptop (board 827D, Kaby Lake-U, Insyde/HPQOEM firmware) | read-only `/proc/acpidump` of an OrientOS live stick on the device, 26.10.2026 | AML only: `DSDT`, `SSDT1`..`SSDT16` |
| `surface-laptop-4` | Microsoft Surface Laptop 4 (Tiger Lake) | Windows: `GetSystemFirmwareTable` (APIC, MCFG, DMAR, LPIT) and the registry copies under `HKLM\HARDWARE\ACPI` (FADT as `FACP`, DSDT, SSDTs) | `DSDT`, `SSDT1`..`SSDT8`, `FACP`, `APIC`, `MCFG`, `DMAR`, `LPIT` |
| `amd-server` | AMD EPYC server (Proxmox host) | `/sys/firmware/acpi/tables` | `DSDT`, `SSDT1`..`SSDT5`, `FACP`, `APIC` |

Not stored on purpose: license tables (`MSDM`, `SLIC`) and anything that can carry serial numbers or keys.

## Interrupt source overrides seen in these MADTs

| machine | IRQ 0 | SCI (IRQ 9) |
|---|---|---|
| surface-laptop-4 | GSI 2, bus default | GSI 9, flags `0xd` (active high, level) |
| amd-server | GSI 2, bus default | GSI 9, flags `0xf` (active low, level) |
| QEMU (`pc`, `q35`) | GSI 2, bus default | GSI 9, flags `0xd` (active high, level) |

## Replay

QEMU takes tables of at most 65535 bytes through `-acpitable`. Give a table another signature with
`python3 tools/acpi/retag.py IN OUT SIG4` (it fixes the checksum), for example `XAPC` for a MADT that the kernel parses
next to its own (`acpiev: xapc ...` lines in `evself` mode).
