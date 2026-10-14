# OrientOS laptop features — what works now (14.10.2026)

Legend: MAIN = in main and gate green; BRANCH = built, gates pending; MODEL = pure model/protocol, not wired into kernel; DOC = assessment only. Real-hardware checks are the Boss's job.

| # | Feature | State | Gate / evidence | Missing |
|---|---------|-------|-----------------|---------|
| L-001 | Pointer accel, speed, natural scroll | BRANCH staff/orientos-mv8mlfzl | ptrcfg 18/0, hid 56/1 (as main) | merge, Settings page seen on screen, disk reload test |
| L-002 | Touchpad gestures (tap, edge, palm, 3-finger, pinch) | MODEL lib/touchgest | touchgest 58/0 | wire into hidin (r797), real touchpad |
| L-003 | Multi monitor (extend/mirror/arrange) | MODEL lib/monitors | monitors 87/0 | fb/vgpu scanouts, wm compose per output (r757) |
| L-004 | Per-monitor scale, HDMI/DP audio | MODEL | monitors 87/0 | hda.fi skips HDMI pins (r758) |
| L-005 | Lid action per AC/battery | MAIN f376c93d | power 39/0 (QEMU fake laptop), k18 170/0, actionbus 306/0 | real lid GPE on hardware, hibernate (S4) |
| L-006 | Battery/AC status + tray | MAIN (model + powerd); taskbar icon BRANCH staff/orientos-r782-taskbar-traypower | power 39/0 | taskbar gates icons/barscene/win11bar |
| L-007 | Screen-off/standby timers per source, profiles | MAIN (timers) | power 39/0 | brightness keys/_BCM, Settings page (r783) |
| L-008 | Screenshot (Print, Win+Shift+S, region, delay, editor) | BRANCH w-mg1-snip | snip 12/0; desktop red also on main | freeform, dimmed overlay, pixel clipboard, desktop/alltag/kernel gates |
| L-009 | Touchscreen / pen | not started | - | uses touchgest + absolute pointer |
| L-010 | On-screen keyboard | not started | - | - |
| L-011 | PIN + biometrics security model | DOC docs/LAPTOP-HW-FEASIBILITY.md | - | PIN impl (r253/r765) |
| L-012 | UVC camera | DOC | - | M/L, xHCI isochronous |
| L-013/014 | Fingerprint, IR face | DOC | - | hardware, proprietary sensors |
| L-015 | USB tethering | MODEL lib/usbnet (RNDIS/ECM) | usbnet 53/0 | xhci async bulk, netdev kind usb (r769) |
| L-016 | Bluetooth | DOC | - | btusb/HCI |
| L-017 | WLAN | DOC (honest: firmware + chip driver) | - | - |
| L-018 | GPU KMS Intel/AMD | DOC | - | - |

Boss-only real-hardware tests: lid close/open + battery values (tools/acpiev/brett.sh), touchpad thresholds, Dell login flicker with `presentlog`.
