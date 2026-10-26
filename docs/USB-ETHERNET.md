# USB Ethernet (R-013)

State of the USB network adapters in the kernel, what was measured, what is new and what is NOT verified on real hardware.

## Drivers

| chip / function | USB ids | protocol lib | kernel mode (`usbnet.fi`) | QEMU gate |
|---|---|---|---|---|
| CDC-ECM | class 02/06 | -- | 0 | `tools/usbecm` (QEMU `usb-net`) |
| RNDIS | class 02/02/ff, E0/01/03, EF/04/01 | `lib/usbnet/rndis.fi` | 1 | `tools/usbrndis`, `tools/usbhot` (QEMU `usb-net`) |
| CDC-NCM | class 02/0D | `lib/usbnet/ncm.fi` | 2 | `tools/usbredir` cases `ncm`, `ncm-multi`, `android-ncm` (usbredir gadget, QEMU has no NCM model) |
| WCH CH336/CH397 | 1A86:5394 ... | `lib/usbnet/ch397.fi`, `kernel/drv/net/ch336.fi` | 3 | `tools/usbredir` cases `ch336*` |
| ASIX AX88772 | 0B95:7720/772A/772B/7E2B | `lib/usbnet/ax88772.fi`, `ax88772_drv.fi` | 4 | `tools/ax88772drv` (fake device) |
| ASIX AX88179 / AX88178A (new) | 0B95:1790/178A and 11 OEM ids of the Linux table | `lib/usbnet/ax88179.fi`, `ax88179_drv.fi` | 5 | `tools/usbeth` (emulated chip behind usbredir) |
| Realtek RTL8152 / RTL8153 A+B (new) | 0BDA:8152/8153, Microsoft 045E:07AB/07C6, Samsung 04E8:A101, Lenovo 17EF:304F/3054/3062/3069 | `lib/usbnet/rtl8153.fi`, `rtl8153_drv.fi` | 6 | `tools/usbeth` (emulated chip behind usbredir) |

Registry: `kernel/drv/net/usbvnic.fi` (`chip_for` by vendor/product id, `start` = bring-up, serial lines `usb: ax88179 <mac>`,
`usb: rtl8153 <mac>`, `usb: <name> failed step=N`). `kernel/usb/usb.fi` takes the vendor configuration first (like CH336: the
vendor interface FF/FF/00 wins over the ECM configuration the chips also offer), `usbnet.fi` carries the data plane. The module
`lib/usbnet/le.fi` holds the little-endian helpers of the new libs.

## Measured before the change (origin/main 86b03ca5)

| gate | result |
|---|---|
| `tools/usbecm` | 13 ok / 0 fail |
| `tools/usbrndis` | 12 ok / 0 fail |
| `tools/usbnet` | 71 promises / 0 errors |
| `tools/usbvendor` | 6 passed / 0 failed |
| `tools/usbhot` | 19 ok / 0 fail |
| `tools/usbredir` (ncm ncm-multi android-rndis android-ncm hotplug replug none ch336) | 47 ok / 0 fail |

QEMU (`-device help`): `usb-net` is the only network model and offers RNDIS, CDC-ECM and a Subset configuration. There is no NCM
and no vendor-chip model, so NCM and the vendor chips are tested through `tools/usbredir/usbdev.py` (USB device emulated in Python
behind `-device usb-redir`, its Ethernet side is a helper QEMU with slirp).

## What the new chips do

AX88179 (`ax88179_178a.c` of Linux): reset sequence (PHY power, IPRL, clock select), node id read and write back, bulk-in queue
control, pause levels, checksum offload on, RX control `0x03AA`, medium mode `0x0133`, PHY autonegotiation restart. Link: the PHY
status register is polled by the driver housekeeping (1 s while down, 3 s while up); on a change the medium mode and the bulk-in
bundling table row are programmed for the speed and the USB link speed. TX header: 8 octets (length, `0x80008000` padding flag plus one
zero octet when `len + 8` is a multiple of the packet size). RX: bundles are walked backwards from the 4 octet trailer (entry count,
entry array offset), 2 entries per packet (packet and dummy), 2 octet IP alignment header, 8 octet padding; CRC/drop errors and runts
are skipped and counted.

RTL8152/RTL8153: register space PLA/USB through vendor request 5 (4-aligned dwords with byte enables), chip family from `PLA_TCR0`,
wait for autoload, PHY power-up through the OCP window, first-init (RXDY gate, Teredo off, NIC reset, BMU reset, OOB exit, FIFO
thresholds) or the RTL8152 exit-OOB sequence, family specific extras (RTL8153B), autonegotiation. On link up: RX early timeout and size
per family and USB speed, IFG, packet filter reset, CR RE+TE, RXDY gate released, multicast hash all ones, RCR broadcast + physical + multicast.
TX descriptor: 8 octets (`len | FS | LS`, 0). RX: 24 octet descriptor, length including the 4 octet FCS, 8 octet alignment.

Receive buffer: both chips bundle many frames in one bulk-in transfer, so `usbnet.fi` allocates a separate 64 KiB-aligned-safe buffer
(28 KiB for AX88179, 16 KiB for RTL) only when such a chip attaches; the other modes keep the 2 KiB buffer.

Two adapters: `MAX_UNITS` stays 1. The second adapter is NOT attached any more: `usbnet.fi` prints `usbnet: second adapter ignored` and the
first keeps working (before this change the second one silently replaced the first). Two units would need per-unit control blocks
(every cell accessor of `usbnet.fi` is unit-less) and are open.

## Gates

`/root/jarvis/bin/heavy bash tools/usbeth/run.sh [case...]` (default: host checks and all cases):

* host: libs compile for the kernel profile; `tools/usbeth/oracle.fi` (golden bytes of framing, tables, link classes) with 18 counter-proofs
  (the oracle goes red when a bound, a flag or a table entry is broken); the device models refuse a reference driver that skips a step.
* QEMU: bound driver, MAC, link, DHCP + ping + DNS + HTTP (4000 octet body over TCP) through the chip, register writes equal the independent
  Python transcription `tools/usbeth/refdrv.py` write for write, 6-frame bursts are all counted by the guest, late link, no link, hot plug,
  unplug, unknown product id, unknown chip version, no device, two adapters, hot add/remove of QEMU `usb-net` (ECM and RNDIS) while running.

## UNTESTED ON REAL HARDWARE

* AX88179 / AX88178A / RTL8152 / RTL8153: the chips are MODELS written by the same person from the same Linux sources. A green gate proves the driver
  does what the transcription says and that framing and register sequences are self-consistent, not that silicon accepts them.
* Not implemented (Linux does it, the chip may need it on some boards): EEPROM/eFuse handling, LED setup, EEE, auto detach, jumbo MTU (AX88179);
  firmware and PHY patch load, U1/U2/LPM and power-cut handling, ALDPS, EEE, runtime suspend, `r8153_hw_phy_cfg` (RTL); the interrupt
  endpoint (link is polled), checksum/TSO offload use, VLAN, multicast hash (all-multicast is accepted), suspend/resume, SuperSpeed endpoint
  companion handling beyond what `usb.fi` already does.
* Real adapters to try (needs Justin): any AX88179 dongle (0B95:1790) and any RTL8153 dongle (0BDA:8153). Serial/screen lines to report:
  `usb: ax88179 <mac>` / `usb: rtl8153 <mac>` or `... failed step=N`, `usbnet: link up 1000`, `/proc/usbnet` (`mode=5` / `mode=6`).
* `/proc/usbnet` and `/proc/usb*` print the driver as a number or `none` for the new drivers: the name table lives in `kernel/fs/procfs.fi`
  (`w_driver`), which another worker owns; add `ax88179` / `rtl8153` there after that merge. Error kind 7 of `/proc/usbnet` (`axlen`) is
  shared by AX88772 and the new chips.
* NCM and the other usbredir gadgets are also emulations; a real NCM phone/dongle was never run.

## Hardware seen (26.10.2026)

* HOLO-LAPTOP-3 (Windows): no USB Ethernet; USB devices are the Intel bluetooth and a Surface camera hub (045E:0990); the only adapters are
  the Intel Wi-Fi 6 AX201.
* HP-ORIENTOS (OrientOS live stick): WCH CH336 dongle 1A86:5394 behind a hub (1A86:809D), a second device 349C:0418; running in `mode=3`.
  No ASIX/Realtek adapter is connected anywhere.
