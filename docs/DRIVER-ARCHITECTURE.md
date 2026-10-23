# DRIVER-ARCHITECTURE — real drivers for OrientOS (23.10.2026, W-DRVDOC)

Docs only. Base: main `cb57e734`. Facts are read from the tree (paths given) or from existing docs; nothing was run for this file. "REAL" = ran on physical hardware and a log/photo exists. "Unmeasured" = code only.
Target machine: HP EliteBook x360 1030 G2 (`docs/PLAN-HP-LAPTOP.md`), not yet booted.

## 1. Current state

### 1.1 Per driver

Evidence key: **REAL** = physical machine, **QEMU** = QEMU device model, **FAKE** = host/guest fake device or simulator, **—** = none.

| Driver | Files (lines) | REAL hardware | QEMU | Fake gate / counts | Notes |
|---|---|---|---|---|---|
| NVMe | `kernel/drv/blk/nvme.fi` (1000) | Detected on AMD board 03.09.2026: `hwdiag: disk NVMe bdf=0x100 c0a9:5426` (`docs/BLECH-BEREIT.md` §3). Data path on real SSD: not shown there | Yes, multi-namespace `tools/metal` 72/0 | `tools/s3dev` 24/0 (resume), `tools/pci` 96/2 (2 red also on old main) | MSI-X; no hot-plug |
| AHCI/SATA | `kernel/drv/blk/ahci.fi` (1791) | Detected on AMD board (`1022:43c8`). Dell 9020: RAID mode, `AHCI init failed, why=8` on old kernel; fix r558 in main, unmeasured on Dell (`docs/DEVLOOP.md`) | Yes, `tools/ahci` | `fakeraid` word: RST warning line gated (`tools/hwinv/guest.sh`, `tools/ovmfboot` 44/0) | MSI only; Intel RST/RAID: no driver (r-gap), message only |
| xHCI | `kernel/drv/usb/xhci.fi` (2643), `kernel/usb/usb.fi` (4570) | **REAL 03.09.2026**: 2 controllers, BIOS handoff `usbleg: gut=2`, kbd+mouse bound, MSI-X on hc1, `events=36 irqs=23` (`BLECH-BEREIT.md` §0.1). Dell: stick boots, input works | Yes | `tools/xhci`, `tools/usbhot` 19/0, `tools/hidweg` 31/0 | Hub driver missing (`driver=none`); isochronous only a test (`tools/xhciiso`) |
| EHCI/OHCI | `ehci.fi` (1624), `ohci.fi` (979) | — | Yes | — | EHCI stick not a `blk` device (`REALHW.md` Part D) |
| USB MSC | in `usb.fi` (BOT+SCSI) | **REAL**: stick boot is the install path (Dell, AMD board) | Yes | `tools/usbhot` 19/0 | `kernel/wechsel.fi` is the hot-plug seam |
| e1000 / I217 / I219 | `kernel/drv/net/e1000.fi` (2755) | **REAL partial**: Dell 9020 I217-LM `8086:153A` — boot hang fixed 24.09.2026 (`REALHW.md` Round NIC9020). I219 laptop: never | Yes (82540/82574; I219 path forced with `nicich`/`nicflush`) | `tools/hwnet` §5, `tools/stab/flush.sh` 6/0 (model only) | MSI only on PCH |
| RTL8168 | `r8169.fi` (1484) | **REAL**: bound on AMD board (`netdev: bestand 09:00.0 10ec:8168 -> r8169`); traffic on real wire unmeasured | `tools/rtl` 67/0 | — | |
| HDA audio | `kernel/drv/snd/hda.fi` (3243), `audio.fi`, `mix.fi` | — (HP codec unknown, Pin config/jack r624) | Yes | `tools/hda` + `cap.sh` 45/0 (capture), `s3dev` | no IOMMU awareness |
| VMSVGA / virtio-gpu | `kernel/drv/gpu/vmsvga.fi` (1655), `vgpu.fi` (2260) | **Boss VM (VirtualBox, VMSVGA)** runs daily: host CPU idle 17–25 % of a core (KNOWLEDGE metrics). Not a physical GPU | Yes | `tools/vmsvga` 46/0, `vgpuheads` 17/0, `vgpuext` 22/0 | virtual devices only |
| Intel HD 620 (HP) | none | **REAL GOP only**: framebuffer from firmware worked on AMD/NVIDIA board (`BLECH-BEREIT.md` §4) | — | `tools/backlum` (host generator) | no mode-set, no backlight (r32/r33/r36) |
| GPU / SWR | `lib/gpu`, `lib/spirv`, `tools/gpu3*` | — | software only | SWR 10/0, SPIR-V 36/0 | CPU rasterizer, no GPU driver (r36) |
| PS/2 | `kernel/drv/hid/kbd.fi`, `ps2m.fi` | Dell 9020 (stick input) yes; HP laptop EC/i8042 unmeasured | Yes | `tools/ps2hid`, i8042-off boot in `tools/ovmfboot` | modern AMD boards have none |
| USB HID | `hidin.fi`, `hidrep.fi` | **REAL** (see xHCI) | Yes | `tools/hid` 57/0, `tools/usbhid` | |
| I2C-HID | `kernel/drv/hid/i2chid.fi` (1247) | — | no QEMU LPSS-I2C | `tools/i2csim` 18/0 (simulated DesignWare) | LPSS PCI wake-up code exists (HP-6), ACPI device match unmeasured |
| AX88772 etc. | `lib/usbnet/ax88772*.fi`, `ch397.fi`, `kernel/drv/net/usbnet.fi` (715) | — | ECM `usbecm` 8/0, RNDIS `usbrndis` 12/0 | `tools/usbvendor` 6/0, `tools/ax88772drv`, `tools/ch397` 20, `tools/ncm` 74 (host) | one USB NIC at a time |
| WLAN Intel | `kernel/drv/net/iwl.fi` (604), `lib/wlan/iwl_*.fi`, `kernel/drv/net/iwl_fake.fi` | — | none (QEMU has no WLAN) | `tools/iwlfh` 23/0, `tools/wlan/fh8000.sh` 56/0, `tools/wlan` 184 checks, `wlan-ax201-m2` 27/0, `fakewlan` boot gate | family 8000 loader modelled (`PLAN-8000-LOADER.md`), ALIVE never seen on silicon |
| ACPI tables | `kernel/acpi/acpi.fi` (650) | **REAL** on AMD board/Dell: MADT, IOAPIC, FADT | Yes | `tools/acpiev` | |
| AML interpreter | `aml*.fi` (~4200 total), `acpiev.fi` (1921), `acpidev.fi` | — (Dell has no battery) | Yes | `tools/aml/run.sh`, `tools/acpiev` | matches PNP0C50, PNP0C0D, PNP0C0A, ACPI0003 (`acpidev.fi:196`); battery/lid on laptop unmeasured |
| S3 | `kernel/pwr/s3.fi` (898), `s3dev.fi` | — | `s3` 55/0, `s3dev` 24/0, `s3smp` 23/0 | | S0ix machines unmeasured |

### 1.2 Structure (what exists today)

| Aspect | Today | Evidence |
|---|---|---|
| Kernel vs ring 3 | All hardware drivers are **ring 0**, compiled into `osum.mb`. Ring 3 has only protocol code (`lib/wlan`, `lib/usbnet`, `lib/hwinv`) that the kernel calls or tests on the host | `kernel/drv/*` tree, 38 332 lines in `kernel/drv/*/*.fi` |
| Loadable modules | `.omod` loader prototype: ELF `ET_REL`, Ed25519, ABI number, 25 failure reasons. One slot used (PS/2 mouse). Gate `tools/module/run.sh` 74/0 | `kernel/ldr/module.fi` (1189), `docs/RUNDE-MODUL.md` |
| Bus enumeration | PCI scan table (`pci.scan`, entries with vendor/device/class/BARs/MSI/MSI-X cap offsets), USB enumeration, ACPI namespace walk. **Each driver has its own `supports()` / class check**; no common match table | `kernel/bus/pci.fi`, `usb.fi` `DRV_*` constants, `netdev.fi` `KIND_*` |
| Binding | NIC: fixed `KIND_*` table in `netdev.fi`; USB: `DRV_*` per device; block: `rootsel.fi` order NVMe > AHCI > USB > IDE | files above |
| Hot-plug | USB only (`usb.port_watch`, `wechsel.fi`, `/medien/usbN`, 8 slots). PCI hot-plug: none | `docs/HOTPLUG.md` |
| DMA / IOMMU | Physical addresses given straight to devices. **No IOMMU code**: `kernel/diag/hw.fi` only reads AMD IVRS (measure, no repair). No Intel DMAR/VT-d parser exists | `hw.fi` ~l. 1275; `grep DMAR kernel` = comment only |
| Interrupts | MSI-X > MSI > legacy IOAPIC pin; `usb: hcN melde=msi-x|msi|intx`. Polling fallback. Gate `eingabe:` status line | `BLECH-BEREIT.md` §5, `pci.fi` `E_MSI`/`E_MSIX` |
| Firmware loading | VFS lookup `/lib/firmware/intel/iwlwifi/...` by PCI id (`iwl_fwsel.dev_path`), TLV parse (`iwl_fw.fi`). Blobs never checked in; SHA-256 pin only. No generic API | `iwl.fi` header, `PLAN-8000-LOADER.md` |
| Power | ACPI shutdown, S3 (QEMU), battery via AML unmeasured | `s3.fi`, `batt.fi` |

### 1.3 Honest summary

- REAL on silicon: boot, framebuffer (GOP), xHCI+HID, USB stick, Realtek bind, NVMe/AHCI **detect**, Dell I217 init, ACPI tables.
- QEMU only: NVMe/AHCI data paths on real disks (unmeasured), e1000 PCH, HDA, S3, all of WLAN and I2C-HID (fake only).
- No driver at all: Intel HD 620 mode-set/backlight, WLAN firmware boot on silicon, Bluetooth, UVC camera (isochronous test only), Intel RST, hub, IOMMU.

## 2. Comparison with Linux, Windows, Android

| Topic | Linux | Windows | Android | OrientOS today |
|---|---|---|---|---|
| Driver model | Bus-driver model: `struct device_driver` + bus `match`/`probe`/`remove`; ID tables (`pci_device_id`, `acpi_device_id`, `usb_device_id`, `of_match_table`) | WDM (IRP stack, `DriverEntry`, AddDevice); **WDF**: KMDF (kernel) and UMDF (user mode, host process) | Linux kernel + vendor modules; **HAL** (HIDL → AIDL) in separate vendor processes | per-driver `supports()`, fixed tables |
| Discovery | PCI scan, ACPI (`_HID`, `_CID`), Device Tree, USB core | PnP manager enumerates, bus drivers create PDOs, **INF** selects function driver | as Linux, plus Treble VINTF manifests | PCI/USB/ACPI scans, hard-coded matching |
| Loadable | Yes, `.ko`, `modprobe`, `depends`, `udev` via modalias | Yes, `.sys`, service key, signed | Yes, vendor/ODM/system modules; **GKI** keeps core kernel fixed | `.omod` prototype, 1 slot |
| User-space drivers | Yes but niche: VFIO, UIO, libusb, FUSE | **UMDF 2** is standard for USB/sensor/portable devices | HALs are user-space; kernel part stays Linux | none |
| Stable ABI | **No** in-kernel ABI (only user ABI). `EXPORT_SYMBOL` | **Yes** for WDF/NDIS/WDDM (versioned interfaces) | **KMI** for GKI (symbol lists), HAL interfaces versioned | ABI number in `ksym.fi` (13 symbols) |
| Isolation | none in kernel; IOMMU+VFIO only for passthrough | KMDF: none; UMDF: process boundary; HVCI/driver block list | SELinux domains for HALs, kernel unchanged | none; no IOMMU |
| Firmware | `request_firmware()` + `/lib/firmware`, udev fallback, linux-firmware package | in driver package (INF/`.sys`/`.bin`), WU distributes | `/vendor/firmware`, partitions | VFS path + SHA pin |
| Network | `cfg80211` (config API) + `mac80211` (soft-MAC) + driver; fullmac drivers use cfg80211 only. iwlwifi `mvm` for 7000/8000/9000 | **NDIS** miniport + Native WiFi (WDI/WCL) | Linux stack + `wificond`, Wi-Fi HAL | `lib/wlan` (own soft-MAC) + `device.fi` 4 functions |
| Graphics | **DRM/KMS** (atomic modeset, GEM, i915) | **WDDM**: dxgkrnl + miniport (KMD) + UMD | DRM/KMS + gralloc/HWC HAL | GOP framebuffer, VMSVGA, software raster |
| Events | udev uevents, netlink | PnP notifications | ueventd | system bus `kernel/bus/bus.fi`, `wechsel.fi` |
| Hardware description | ACPI/DT | ACPI | DT mostly | AML interpreter |

Takeaways for a small OS:
- A **match table + probe/remove contract** (Linux/Windows) is cheap and removes the per-driver `supports()` copies.
- A **stable ABI** is expensive (Windows/Android). OrientOS already has an ABI number and signing; keep it small.
- **User-space drivers** (UMDF, HAL) are only honest with an IOMMU. `docs/MODUL-BEFUND.md` §7 reached the same conclusion: ring 0 modules first, ring 3 after IOMMU.
- Linux's `request_firmware` and the cfg80211/mac80211 split map directly onto what OrientOS already has (`lib/wlan` is the mac80211 role; `device.fi` is the driver ops).

## 3. Recommendation for OrientOS

No big refactor. Everything below is additive and each step has its own gate.

### 3.1 Modular driver interface (small)

| # | Piece | Content | Builds on |
|---|---|---|---|
| D1 | **Driver registry** `kernel/bus/drvreg.fi` | One table: name, bus (PCI/USB/ACPI), match rows (vendor/device/class+mask; USB class/vid/pid; ACPI `_HID`/`_CID`), probe, remove, suspend, resume, required rights. Existing drivers register their current `supports()` rows first (no behavior change). Output: `/proc/drivers`, one boot line per bind/skip with reason | `pci.fi` entries, `usb.fi` `DRV_*`, `netdev.fi` `KIND_*` |
| D2 | **ACPI device enumeration** | Walk namespace, list devices with `_HID`/`_CID`/`_UID`/`_CRS` (I2C address, GpioInt) into the same registry; add to `hwinv` (HP-3) | `acpidev.fi`, `aml*.fi` |
| D3 | **Firmware loader** `fw.request(name, sha256)` | Lookup `/lib/firmware/<vendor>/<name>`, verify pinned SHA-256, return mapped buffer, one error line per failure. Blobs stay out of git | `iwl_fwsel.fi`, `iwl_fw.fi` |
| D4 | **Capability rights** | A driver declares needed rights (MMIO range, IRQ, DMA window, firmware, ACPI object). Enforced for `.omod` modules at load; for built-in drivers only logged | `module.fi`, `rechte.conf` model |
| D5 | **DMA window API** | All device DMA goes through one allocator (`dma.alloc(bits, align)`), so an IOMMU can be added later without touching drivers | `mm` frame allocator |
| D6 | **Intel DMAR (VT-d) parse + report** | Measure first, like IVRS in `hw.fi`: table present, translation on/off, pre-boot DMA protection. Needed before any ring-3 driver on the HP | `kernel/diag/hw.fi` |
| D7 | **Ring-3 drivers** | Only after D5+D6 produce a working IOMMU. First candidates: HDA, USB-NIC (`MODUL-BEFUND.md` §6). Storage and display stay ring 0 | — |
| D8 | **Test rule** | Each driver ships a fake device gate (QEMU device, host simulator, or `fake*` kernel word) **and** a hardware checklist (below) | existing `fakewlan`, `fakeraid`, `i2csim` |

### 3.2 Hardware checklist template (per driver, goes into its doc)

1. Boot line with PCI/ACPI id and bind result (from `/proc/drivers`).
2. Register read-back line that proves the BAR is mapped (no writes yet).
3. Interrupt mode line (`msi-x|msi|intx|poll`) and counter > 0 after a stimulus.
4. One functional stimulus with a number (e.g. 100 blocks read and compared, 20 pings, 1 key press).
5. Unplug/suspend/resume result or an explicit "not supported".
6. Failure path: driver fails -> boot continues, one error line (as `nic: init failed: e1000 step N`).
7. Photo or serial log stored in `docs/` with image version (`FASSUNG`).

### 3.3 Order for the HP EliteBook x360 1030 G2

| Step | What | Why first | Status today |
|---|---|---|---|
| 1 | Boot + inventory (`hwinv`) + storage verdict (BIOS AHCI, RST warning) | nothing else can be judged without it | code in main, never run on the HP |
| 2 | **Keyboard**: i8042 via ACPI/EC; fallback USB keyboard | login needs keys (`tools/inputlogin`) | PS/2 code ok, laptop path unmeasured |
| 3 | **Touchpad**: LPSS I2C (DesignWare) + ACPI match (`PNP0C50`, `_CRS` I2C address + GpioInt) + I2C-HID | pointer without USB mouse | `i2chid.fi` 18/0 on simulator only |
| 4 | **Display**: keep GOP; add backlight (Intel `BLC_PWM_*` registers or ACPI `_BCM`); mode-set later | usable screen first, brightness keys next | GOP only |
| 5 | USB-network dongle/tethering (ECM/RNDIS/AX88772) | network before WLAN | QEMU ok, real dongle never |
| 6 | Battery, lid, power button (AML `PNP0C0A/0D/0C`) | laptop use | AML ok, unmeasured |
| 7 | **WLAN Intel 8265 (family 8000)**: FH chunk loader, ALIVE, NVM read, then mac80211-role code | biggest item, needs firmware blob + silicon | modelled (`fh8000.sh` 56/0) |
| 8 | Audio HDA codec of the HP (verbs, pin config) | after the above | controller ok, codec unknown |
| 9 | Touchscreen (I2C-HID, same stack as step 3) | cheap after step 3 | none |
| 10 | Bluetooth (USB HCI + firmware), camera (UVC), S3/S0ix, TB | last | missing |

### 3.4 Linux drivers to read as reference (read-only)

| Area | Path in the Linux tree | Use for |
|---|---|---|
| WLAN 8265 | `drivers/net/wireless/intel/iwlwifi/` — `pcie/trans.c` (`iwl_pcie_load_given_ucode_8000`), `iwl-fh.h`, `fw/`, `cfg/8000.c`, **`mvm/`** (8000 family uses mvm, not `dvm`) | loader sequence, ALIVE, NVM, command set |
| I2C-HID | `drivers/hid/i2c-hid/i2c-hid-core.c`, `i2c-hid-acpi.c` | descriptor, power on, reset, `_DSM` for HID descriptor address |
| I2C controller | `drivers/i2c/busses/i2c-designware-*.c` | register sequence, timing, FIFO |
| LPSS glue | `drivers/mfd/intel-lpss*.c` | PCI function -> I2C/UART instance, reset/clock register at +0x200 |
| GPIO / IRQ for touchpad | `drivers/pinctrl/intel/pinctrl-intel.c`, `pinctrl-sunrisepoint.c` | GpioInt to interrupt line on Kaby Lake PCH |
| Keyboard | `drivers/input/serio/i8042.c`, `drivers/input/keyboard/atkbd.c`, quirk list `i8042-acpipnpio.h` | EC keyboard quirks |
| Battery, lid, button | `drivers/acpi/battery.c`, `button.c`, `ac.c` | `_BIF/_BIX/_BST`, lid `_LID`, events |
| Backlight | `drivers/gpu/drm/i915/display/intel_backlight.c`, `drivers/acpi/acpi_video.c` | PWM registers, `_BCM`/`_BQC` |
| Display (later) | `drivers/gpu/drm/i915/display/` (modeset, GMBUS/EDID) | mode-set on HD 620 |
| NVMe / AHCI details | `drivers/nvme/host/pci.c`, `drivers/ata/ahci.c`, `libahci.c` | quirks seen on real parts |
| NIC | `drivers/net/ethernet/intel/e1000e/` (`ich8lan.c`) | already used for the I217 fix |
| HDA | `sound/pci/hda/hda_intel.c`, `patch_realtek.c`, `hda_generic.c` | codec quirks, pin config |
| Firmware API | `drivers/base/firmware_loader/main.c` | semantics for D3 |
| Wi-Fi stack | `net/mac80211/`, `net/wireless/` | state machine reference |

### 3.5 License caution

- Linux drivers are **GPL-2.0**. Read them as a specification, write own code in Firn, **do not copy** code, tables of macros, or comments. Record the reading date and file in the plan doc (as `PLAN-8000-LOADER.md` does).
- Register offsets and sequences are facts; verify each with a second source or hardware before relying on it.
- **Firmware blobs** (`iwlwifi-8265-*.ucode`, HDA/BT blobs) have their own redistribution license (Intel `LICENCE.iwlwifi_firmware`: redistribution allowed with conditions, no modification). Do not check them into git or the image without reading the license; ship SHA-256 pin + download step, as the plans already say.
- Windows driver packages (INF/SYS) must not be disassembled or reused.

### 3.6 Out of scope here

IOMMU implementation itself (D6 is only measuring), a stable public driver ABI, full DRM/KMS clone, hot-plug of PCI devices.
