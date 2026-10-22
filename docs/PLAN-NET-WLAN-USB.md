# PLAN-NET-WLAN-USB -- wireless and USB network (one page, 22.10.2026)

Detail: `docs/PLAN-LAPTOP-WLAN.md` (milestones LW-1..LW-9), `docs/PLAN-8000-LOADER.md` (Intel 8265 loader), `docs/USBNET.md`, `docs/PLAN-HP-LAPTOP.md`. This page is the short plan.

## State (measured, gates)
- USB net: CDC-ECM (`tools/usbecm` 8/0), RNDIS (`tools/usbrndis` 12/0, `tools/usbnet` 53/0 protocol models), NCM (`tools/ncm` 74, host only), CH397 (`tools/ch397` 20, host only). Driver `kernel/drv/net/usbnet.fi`, bring-up in `kernel/usb/usb.fi`.
- 802.11 host half `lib/wlan`: scan, auth, assoc, WPA2 4-way, CCMP, DHCP, HTTP against a Python peer (`tools/wlan/run.sh`).
- Intel 8265 (HP EliteBook x360 1030 G2, family 8000): FH chunk loader model `tools/wlan/fh8000.sh` 56/0, kernel glue with fake CSR window `tools/iwlfh` 23/0.
- AX201 (Surface, CNVi): library M1..M3 (`tools/wlan-ax201-m2` 27/0), no real silicon proof.
- Nothing has talked to a real radio yet.

## Gaps
- USB: RNDIS keepalive/indications, hot unplug in the real loop, link notification, only one NIC, vendor chips (CH336 1A86:5394, ASIX AX88772/179, RTL8153, ipheth) (r1486, r1495).
- WLAN host: group-key rekey wiring, HT/VHT/HE capability parsing, WPA3-SAE, 802.11w (r1487, r1497, r1525, r1493).
- 8265: ALIVE wait, NVM read, command queue, RX queue, scan/assoc/TX on real HP (r1527, HP-9c).
- AX201: firmware lookup/load glue, command ring, station setup (r1488, r1489, r1492).
- OS side: `KIND_WLAN` netdev, `/proc/wlan`, Settings pages `network/wifi` + `network/usb`, tray state (r1491, r1490, r1538).

## Stages
1. **Online without radio:** finish USB net (keepalive, unplug, vendor chips) -- gates `usbecm`, `usbrndis`, new `tools/usbvendor` with oracles. Boss test: dongle or phone tethering at the HP.
2. **WLAN in QEMU:** `KIND_WLAN` + `/proc/wlan` + `wlan connect` to DHCP over a fake device; netui model + Settings pages (agree with W-NAV).
3. **8265 on the real HP:** run `iwlboot` (HP-9c), read the ALIVE line, then NVM and commands. Needs the HP and one stick boot.
4. **AX201 and extras:** same command layer for Surface; WPA3-SAE, 802.11w, Bluetooth PAN (after r6).

## Rules
- No iwlwifi copy (GPL): own code from the specification; firmware blobs never checked in, SHA-256 pin only.
- Green host gates prove internal consistency only; real silicon decides. Every stage needs a counter-proof gate.
- Boss test per stage: boot the stick, send the `iwl:`/`usb:` boot lines (`reports/TESTANLEITUNG-LAPTOP.md`).
