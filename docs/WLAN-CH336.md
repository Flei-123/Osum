# CH336 USB Ethernet dongle (1A86:5394) behind a USB hub

Dongle of the Boss: "USB2.0 Ethernet Adapter", `USB\VID_1A86&PID_5394 REV_0100`, class FF/FF/FF, Windows `WCHUSBNICA64.sys` 1.7.2025.7, 100 Mbps. At the HP it sits behind the WCH USB 2.0 hub `1A86:809D` together with a card reader `349C:0418`.

## Source for the protocol (read 24.10.2026)

* `ch397.c` V1.4 (07.2024), WCH Linux driver, fetched from `gitee.com/ydong08/ch397/driver/ch397.c` (repo says MIT, file header says GPL-2.0+; used as a specification only, nothing copied).
* No second independent source exists (searched: no WCH GitHub repo for CH336/CH339, no mainline driver, `ch9200` is another chip). The framing is therefore confirmed against ONE vendor source, never against silicon.

## What the vendor source does vs. our driver

| Item | Vendor source | OrientOS before | OrientOS now |
|---|---|---|---|
| Requests | 0x10 info, 0x11 rd reg, 0x12 wr reg, 0x15 phy rd, 0x16 phy wr, 0x1E write MAC cfg (fw >= 0x37), 0x1F autoneg | 0x10, 0x11 only | all used except 0x1F/0x16 |
| Register address | wValue = low 16, wIndex = high 16 | same | same |
| PHY read | wValue 0x0740, wIndex = MII register, 2 octets | not used | link, ANAR, LPA read |
| Delay after each control request | 10 ms | none | 10 ms |
| TX header | u32 LE = padded length (frame >= 60, total rounded to 4, +4 if total is 512/1024, header = total - 8) | header = unrounded length | header = total - 8 |
| RX header | u32 LE length, 60..1522, 8 octets overhead, data padded to 4 | max 1518 | max 1522 |
| RX frame split across transfers | handled (state machine) | frame dropped | carry buffer (`usbnet.fi` `ch_next`) |
| Link | interrupt endpoint, bit 6 of byte 0 | none | PHY BMSR polled once a second (`ch336.fi`) |
| MAC config | on link change: copy speed (bit 7) and duplex (bit 8) from the autoneg result, write with 0x1E (fw >= 0x37) or reg 0x40000700 | none | `ch397.media_cfg`, `ch336.apply_media` |
| RX mode | `PBD|PUF|PAM` set, `RA` clear; hash regs 0x40000730/34 = all ones | none | same, at bring-up |
| Configuration | forces configuration value 1 | first matching | unchanged (open) |

## Hub path

`kernel/usb/usb.fi` has a hub driver (`hub_start`, `hub_scan`, route string, TT slot/port for slow devices). Older docs saying "driver=none" are stale. Measured in QEMU with a full-speed `usb-hub` (keyboard, mouse, now also `usb-net`, gate `tools/usbnet/qemu.sh`, runs `hub` and `nohub`). QEMU has no high-speed hub, so the real case (high-speed device behind a high-speed hub: speed 3, no TT, EP0 64) is code-reviewed only, not run.

## What stays a hypothesis without silicon

* Everything in the table above; the vendor source is the only reference.
* Interrupt endpoint is not used; link comes from PHY registers.
* Bulk-IN transfer length 2048 with carry; the real device may pack differently.
* The dongle and the card reader share one hub: both must enumerate.

## Diagnostics for the next photo

* Serial/boot: `usb: hub p=<port> ports=<n> slot=<s>`, `usb: port=<p> route=<r> speed=<s> ... id=1a86:5394 ... driver=ch336`, `usb: ch336 info=<8 octets>`, `usb: ch336 <mac>`, `usb: ch336 link=up|down bmsr=.. anar=.. lpa=.. cfg=.. fw=..`, or `usb: ch336 failed step=N` (1 info, 2 mac, 3 attach, 4 mac cfg).
* `cat /proc/drivers`: USB list (now names `driver=ch336`), then `usbnet: ready mode=3 link=.. bmsr=.. cfg=.. fw=.. rx=.. tx=.. err=.. drop=..`, then `net: ip=.. gw=..`.
* `cat /proc/net/dev` for the counters.
