# Hypervisor feasibility (r2488)

Probe: `/proc/vmxcaps`, `/proc/dmar` (read-only). QEMU gate: `tools/hvprobe/run.sh`. Raw data: `h0-feasibility.md`, `h0-qemu-probe.txt`.

## Table

| Item | HP EliteBook x360 1030 G2 (i5-7200U) | Dell |
|---|---|---|
| Reachable | yes, measured live 31.10. via bridge | NOT MEASURED (not connected) |
| CPUID.1 eax | 0x806e9 (Kaby Lake U) | not measured |
| VMX (CPUID.1 ECX[5]) | 1 | not measured |
| IA32_FEATURE_CONTROL (0x3A) | 0x1: lock=1, VMXON-outside-SMX=0 | not measured |
| VMX usable now | NO: locked with VMX disabled (VMXON would #GP) | not measured |
| VMCS rev / size / memtype | rev 4, 0x400 bytes, WB | not measured |
| True controls (basic bit 55) | yes | not measured |
| EPT (sec. ctl bit 1) | yes | not measured |
| VPID (bit 5) | yes | not measured |
| Unrestricted guest (bit 7) | yes | not measured |
| EPT caps (0x48C) | 4-level walk, WB+UC, 2M + 1G pages, A/D bits, exec-only, INVEPT single+all | not measured |
| INVVPID | yes (individual, single, all, single-retain-globals) | not measured |
| Other sec. controls | RDTSCP, x2APIC virt, WBINVD exit, PAUSE-loop, RDRAND/RDSEED exit, INVPCID, VMFUNC, PML, #VE, XSAVES, mode-based EPT exec | not measured |
| APIC reg virt / virt int delivery (bits 8, 9) | no | not measured |
| VMCS shadowing (bit 14) | no (earlier h0 note said yes: wrong, 0x005fbcff has bit 14 clear) | not measured |
| VT-d (ACPI DMAR) | none: `/proc/dmar: none`, VT-d off in BIOS | not measured |

Decode source: allowed-1 dword of MSR 0x48B = 0x005fbcff; MSR 0x48C = 0x00000f0106734141.

## Server (dev host)
- AMD EPYC 7571, `kvm_amd nested=1`, no `kvm_intel`: Intel VMX not testable here, only AMD-V (`kernel/arch/x86_64/hv.fi`).
- QEMU TCG (`qemu64`, `max`): VMX=0, MSRs read 0 without #GP. Proves probe is fault-safe only.

## Recommendation
- **HP:** hardware fully capable (EPT, VPID, unrestricted guest, 2M/1G EPT). Blocker is BIOS only: F10, enable Virtualization Technology (VTx) and VT-d, cold power cycle, re-read `cat /proc/vmxcaps` (expect 0x3A = 0x5) and `cat /proc/dmar` (expect DRHD).
- **Intel VMX backend:** build against the HP (only Intel test machine). Use EPT with 2M pages, VPID, unrestricted guest; do not rely on APICv or VMCS shadowing.
- **Passthrough (8265 etc.):** only after VT-d shows in DMAR; today no DMA isolation.
- **Dell:** connect and repeat the same two `cat` commands; nothing is claimed until then.
