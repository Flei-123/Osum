# WLAN-AX201 -- Intel Wi-Fi 6 AX201 (and the CH336/CH339 USB Ethernet dongle) on HOLO-LAPTOP-3

Status 15.10.2026 (W-AX201): analysis + milestone M1 (identify only). No radio works yet.

## 1. The two devices (read from Windows on HOLO-LAPTOP-3, not guessed)

| item | value |
|---|---|
| WLAN | `PCI\VEN_8086&DEV_A0F0&SUBSYS_00748086&REV_20`, "Intel(R) Wi-Fi 6 AX201 160MHz", Windows service `Netwtw10`, driver 24.30.1.1 |
| USB Ethernet | `USB\VID_1A86&PID_5394&REV_0100`, "USB2.0 Ethernet Adapter", Windows service `WCHUSBNICA64` (wch.cn 1.7.2025.7), compatible ids `Class_FF&SubClass_FF&Prot_FF` |

## 2. AX201 feasibility

* Linux driver: `iwlwifi`, `A0F0` maps to `iwl_qu_long_latency_mac_cfg` (`pcie/drv.c`, `/* Qu devices */`;
  siblings 34F0/3DF0/4DF0 medium latency, 43F0 long, 02F0/06F0 plain). The Windows laptop is Tiger Lake; the
  AX201 is **CNVi**: MAC in the PCH, only the RF part on the M.2 module. To the OS it is still an ordinary
  PCI function with a BAR0 CSR block.
* Firmware (needed, runs on the MAC's embedded processor): `iwlwifi-QuZ-a0-hr-b0-77.ucode`
  (`cfg/22000.c`: `IWL_QUZ_A_HR_B_FW_PRE`, `IWL_22000_UCODE_API_MAX = 77`; Qu variants `Qu-b0-hr-b0`, `Qu-c0-hr-b0`).
  Exact file for this laptop is chosen by `CSR_HW_REV` type + RF id (M3); QuZ is the expected one, **not yet
  confirmed on the machine** (needs M1 run on real hardware: `hw_rev`, `rf_id`).
* Effort (honest): the gen2 driver is about 186k lines in total (docs/WLAN-BEFUND.md); a minimal station-only
  driver needs context-info boot, command queue, RX queue, TX queue, MAC context, scan, auth/assoc commands and
  key install, roughly 4-6 kLoC of Firn plus a lot of hardware debugging without QEMU support (QEMU has no
  Intel WLAN device). Realistic: weeks of focused work, every milestone after M1 needs the real laptop.
  The 802.11/WPA2 half (`lib/wlan/*`, CCMP, 4-way handshake) already exists and is tested.
* Nothing can be emulated, so M1-M3 gates are host tests against a CSR simulation. Real proof = laptop.

## 3. Firmware licence and repository policy

* linux-firmware `WHENCE`: `Licence: Redistributable. See LICENCE.iwlwifi_firmware for details`.
  The Intel licence (as remembered, **text not re-read this session**) allows redistribution of the binary
  *unmodified* with the notice and forbids reverse engineering. Policy: **the blob is NOT checked in.**
* We pin the **SHA-256 of the file** (a hash is not a redistribution) in `lib/wlan/iwl_probe.fi`
  (`fw_digest_pinned`); the file comes from the user's own Linux/firmware package or from
  `git.kernel.org/.../linux-firmware.git` at install time (same model as AR9271, docs/WLAN-TREIBER.md).
* Measured 15.10.2026: `intel/iwlwifi/iwlwifi-QuZ-a0-hr-b0-77.ucode`, 1 406 720 bytes,
  SHA-256 `39d79587dd035bc84172b6bcf6de81217560088b0ceb06304d5121ba56db8d83`, header magic `IWL\n`,
  name `release/core74::563a6e92`, `ver` 77, 182 TLVs, walk ends exactly at EOF (Python cross-check).

## 4. Milestones

| M | content | gate | state |
|---|---|---|---|
| M1 | PCI id table, BAR0 sanity, read `CSR_HW_REV`/`CSR_HW_RF_ID`/`GP_CNTRL`, firmware container + digest pin (no register writes) | `tools/wlan/iwl.sh` (31 checks, +4 with the real blob) | **done (library + host gate)** |
| M1b | kernel glue: `pci.scan` -> `iwl_probe.probe_run` on the mapped BAR0, serial line `wifi-pci: Intel Qu ... rev=0x.. rf=0x..`, Dell-style `pci.list` naming | real laptop, one boot | open (needs laptop) |
| M2 | power/reset: `CSR_GP_CNTRL` INIT_DONE / MAC_ACCESS_REQ handshake, `CSR_RESET` SW_RESET, `CSR_FUNC_SCRATCH` / HW_IF_CONFIG, PRPH access via HBUS target regs, interrupts masked | CSR simulation + laptop | **library + host gate done** (`lib/wlan/iwl_pwr.fi`, `tools/wlan/iwlm2.sh`); kernel glue + laptop open |
| M3 | firmware load: parse TLVs (SEC_RT/SEC_INIT/CSCHEME, API flags), DRAM copies, **context info** (see correction below), start ROM, wait for ALIVE | laptop | **TLV/section parser, context-info page, fw-kick sequence: library + host gate done**; DRAM copy in kernel + ALIVE wait open (laptop) |
| M4 | command queue (TFD ring in DMA memory), `INIT_COMPLETE`, NVM / MAC address, regulatory | laptop | TFD + ring codec (`lib/wlan/iwl_ctxt.fi`) host-tested; commands/notifications open (laptop) |
| M5 | RX queue, interrupts (MSI-X), scan (passive then active), beacon parse via `lib/wlan` | laptop + any AP | open |
| M6 | MAC/PHY/binding contexts, station add, auth+assoc commands, TX path | laptop | open |
| M7 | WPA2-PSK: key install (CCMP via firmware or `lib/wlan/ccmp.fi`), 4-way handshake already in `lib/wlan/wpa.fi` | laptop + AP | open |

Protocol source: Linux `drivers/net/wireless/intel/iwlwifi/{pcie/gen1_2/trans*.c, iwl-csr.h, iwl-trans.h, fw/api/*}`.
CSR values in M1 were re-read from `iwl-csr.h` (CSR_HW_REV 0x028, RF_ID 0x09c, GP_CNTRL 0x024, RESET 0x020,
MBOX_SET 0x088, DRAM_INT_TBL 0x0A0, GP1 0x054). The dash/step split of `CSR_HW_REV` (dash = rev&3,
step = rev>>2&3) is from memory; `CSR_HW_REV_STEP_DASH = rev & 0xF` was re-read. Expect REV ~0x354 (QuZ) on the
laptop (recollection of Linux logs, unverified).

Open facts that only the laptop can answer: real `hw_rev`/`rf_id`, BAR0 size, whether firmware leaves the
device in D0, and whether the BIOS has CNVi enabled in the OS-visible form.

## 5. USB Ethernet 1A86:5394

* Not ECM, NCM or RNDIS: device class `FF/FF/FF`, vendor driver `WCHUSBNICA64`. The existing NCM/ECM/RNDIS
  path (`kernel/usb/usb.fi`, `kernel/drv/net/usbnet.fi`) will **not** pick it up by class; adding the id to a
  match table does nothing.
* Linux mainline has no driver for it (the mainline `ch9200` is 1a86:e092, a different chip; `ch341` is serial).
  Out-of-tree: `ch397` (gitee.com/ydong08/ch397, MIT, 2025): table `5397 CH397, 5396 CH396, 5395 CH339,
  5394 CH336`. So 5394 is a **CH336** by that table, not a CH339 (that is 5395); same family and protocol.
* Protocol (from that single source, unverified on hardware): vendor control requests `0x10` info, `0x11/0x12`
  read/write register, `0x15/0x16` PHY, MAC at registers `0x40000714` (4 octets) and `0x40000710` (2 octets),
  select configuration 1; bulk frames carry a 4-octet LE length and 4 more octets (TX zero), padded to 4,
  60..1518 octets, several frames per bulk-IN transfer.
* Done: `lib/usbnet/ch397.fi` (id table, request codes, TX wrap / RX walk) + `tools/ch397/run.sh`
  (20 checks, host only). Not done: xHCI glue in `usb.fi` (vendor-class attach, config 1, MAC read, bulk pipes
  into `usbnet`), plus a USB capture with the real dongle to confirm the framing. Needs the dongle plugged in.

## M1b -- kernel glue (15.10.2026, W-IWL)
- `kernel/drv/net/iwl.fi`: after `pci.scan`/APIC init (`kmain`, right after `hw.stage`) every PCI function that
  `iwl_probe.family_of` knows gets BAR0 mapped (`apic.map_device`) and the four CSRs READ. No device register is written;
  the only write is the PCI command Memory-Space bit if the firmware left it off (logged `iwl: memory space was off`).
- Serial: `iwl: hw_rev=0x.. rf_id=0x.. id=8086:a0f0 mac=.. rf=.. bdf=.. gp=.. if=..`, or `iwl: no device`, or `iwl: err=<dead|bar|map> ...`.
- `/proc/wlan` (procfs `G_WLAN`) and the `wlan` section of `/bin/sysinfo` show the same without gp/if.
- Gate `tools/wlan-ax201-glue/run.sh` (QEMU): no-device and foreign-device (edu) paths. The path "device present, values read" is NOT
  testable in QEMU (no Intel a0f0); it runs for the first time on HOLO-LAPTOP-3. Test steps: reports/TESTANLEITUNG-LAPTOP.md.

## M2/M3 prep without hardware (16.10.2026, W-LCWIFI)
Gate `tools/wlan-ax201-m2/run.sh` (-> `tools/wlan/iwlm2.sh`, host only, 27 checks + 9 counter-probes, no QEMU).
- `lib/wlan/iwl_fw.fi`: TLV walk into `FwInfo` (flags, phy_sku, num_cpu, api/capa words index 0, paging size, IML) and the SEC_RT / SEC_INIT
  section lists split LMAC (CPU1) / UMAC (CPU2) / PAGING by the two separator markers (0xFFFFCCCC, 0xAAAABBBB). Cross-checked
  byte for byte against an independent Python parser (`tools/wlan/iwlfw_ref.py`) on a synthetic blob, 8 hostile blobs, and the real
  blob when `WLAN_AX201_FW` is set (not available on the server yet -> **real-blob run is open**).
- `lib/wlan/iwl_pwr.fi` (M2): int mask/ack, STOP_MASTER wait, SW reset, INIT_DONE + CLOCK_READY wait, MAC_ACCESS_REQ grab/put
  (CLOCK_READY and not GOING_TO_SLEEP), PRPH read/write through HBUS, `fw_kick` (CTXT_INFO_BA lo/hi, ALIVE unmask, UREG_CPU_INIT_RUN).
  Tested against a CSR model with delayed handshakes that also flags PRPH access without MAC access. A stuck master never leads to a reset.
- `lib/wlan/iwl_ctxt.fi` (M3/M4): context-info page (1776 octets), `ctxt_fill_dram` maps the parsed sections to umac/lmac/virtual lists,
  TFD (128 octets, 20 TBs, 36-bit address, 12-bit length), TFD ring `Txq` (wrap, full/empty, reclaim, HBUS_WRPTR value), command header.
  Found + fixed while testing: ring index math underflowed (u64 panic) on wrap.
- `lib/wlan/scanfmt.fi`: scan results as lines `ssid ch=N sec=... rssi=-NN` from `connect.Sitzung` (real beacons from the Wireshark capture);
  SSID sanitised, whole lines only. Not yet wired into `/proc/wlan` (needs a running driver that fills a Sitzung).
- Already existing and gated before (tools/wlan/run.sh): 802.11 frame codec, beacon/RSN parser, CCMP, WPA2-PSK 4-way handshake (real capture), `device.Geraet` seam.

**Correction to the M3 row text above:** for Qu/QuZ/AX200 (device family < AX210) Linux uses the *old* `struct iwl_context_info`
(`pcie/ctxt-info.c`), NOT the gen3 `prph_scratch/prph_info/IML` variant (`ctxt-info-gen3.c`, AX210+). The layout in `iwl_ctxt.fi` follows that old struct.

**Unconfirmed (from memory, needs the Linux source or the laptop):** TLV type numbers, separator values, context-info field offsets and
control-flag bits, TFD layout, CSR/HBUS/UREG register numbers and bit values, the exact init order. The gates prove internal consistency,
bounds and handshake handling -- NOT that the silicon agrees. **Needs laptop:** everything past `fw_kick` (ALIVE, INIT_COMPLETE, NVM, scan, assoc).
Not done: iwl host-command codecs (scan/MAC-context/station/TX-cmd) and the RX descriptor -- layouts are too uncertain without the headers.
