# H0 hypervisor feasibility (r2395 / r2396)

Scope: read and measure only. No kernel behavior change. Probe: `/proc/vmxcaps` (kernel/diag/vmxcaps.fi, read-only, fault-safe MSR reads via arch/msr) and `tools/hvprobe/run.sh`.

## Verdict

| Machine | VMX/SVM | EPT/VPID/UG | VT-d | Verdict |
|---|---|---|---|---|
| HP EliteBook x360 1030 G2 (i5-7200U, Kaby Lake) | not measured (probe not on the device) | not measured | MEASURED: no DMAR ACPI table, `/proc/dmar: none`, `hwinv iommu=none` | BIOS switch needed (VT-d); VT-x/EPT per Intel spec, to be confirmed with one probe boot |
| Dell | not measured | not measured | not measured | Bridge: device not connected |
| Server (QEMU host) | AMD EPYC 7571 + `/dev/kvm`, `kvm_amd nested=1`, no `kvm_intel` | NPT only | n/a | Intel VMX cannot be measured here; only SVM nested works |

## Measured facts

### HP (bridge, read-only: hwinv, /proc/dmar, /proc/pcie)
- ACPI tables present: DSDT FACP SSDT RTMA UEFI TPM2 MSDM SLIC WSMT HPET APIC MCFG DBGP DBG2 NHLT ASF! FPDT BGRT. DMAR is missing. HP firmware hides DMAR when VT-d is disabled in BIOS; so: VT-d is off or not offered.
- No DRHD, no capability register, no interrupt remapping can be read until DMAR exists.
- Kernel flags in `/proc/cpuinfo` are a fixed string; no VMX info there. Ring 3 `cpuid` is possible but no installed binary reports it (`sysinfo`, `lspci`, `regdump` are blocked by the command allowlist).
- Intel 8265 (8086:24fd) is at 3a:00.0, alone behind root port 00:1c.4 (8086:9d14). Root port 1c.4 exposes extended capabilities AER(0001) and ACS(000d)@140; the endpoint has AER, DSN, LTR, L1SS. The card reader 3b:00.0 (10ec:522a) sits behind a different root port (00:1c.5).
- Isolation: 8265 is the only function below its root port and the port has ACS, so it forms its own IOMMU group once VT-d is on. Without DMAR there is no isolation today.
- Other functions: 00:14.0 xHCI, 00:14.2, 00:15.x and 00:1f.x are on the PCH root complex and share a group on this chipset (no ACS on the PCH functions).

### Server QEMU
- `/sys/module/kvm_intel` absent; `/sys/module/kvm_amd/parameters/nested` = 1. CPU is AMD EPYC.
- Probe boots in QEMU TCG (`tools/hvprobe/run.sh`, logs in `h0-qemu-probe.txt`): `-cpu qemu64` and `-cpu max` report CPUID.1:ECX[5]=0 (no VMX), and all MSR 0x3A / 0x480..0x491 read 0 (TCG returns 0, no #GP). This proves the probe runs without crashing; it is not Intel data.
- CPUID 0x8000000A works (SVM rev 1, 16 ASIDs; with `max`, EDX shows NPT).
- Existing hypervisor code (`kernel/arch/x86_64/hv.fi`) is AMD-V only for this reason.

## Expected for i5-7200U (Intel ARK, NOT measured)
- VT-x, EPT, VT-d: supported by the SKU. EPT 2 MiB pages, A/D bits, VPID, unrestricted guest: Skylake-family cores support them. 1 GiB EPT pages: also on Skylake-family, to be confirmed.
- IA32_FEATURE_CONTROL lock bit and VMX-outside-SMX bit depend on BIOS; HP normally sets both when VT-x is on.

## Risks
- VT-d off: no DMA isolation for the 8265 or anything else; passthrough would be unsafe.
- Firmware may lock FEATURE_CONTROL with VMX off; then only a BIOS change helps.
- A VMX host is a second implementation next to AMD-V; VMX can only be tested on real Intel hardware (HP) because the dev server is AMD (nested Intel is impossible).
- HP DMAR reading needs the probe kernel on the device (feed + apply), which was not allowed in this task.

## Next step
1. Ship the probe kernel to the HP in the next regular feed; run `cat /proc/vmxcaps` and `cat /proc/dmar`.
2. If DMAR stays `none`: enter BIOS (F10), enable "Virtualization Technology (VTx)" and "VTd", re-read.
3. Connect the Dell and repeat.
