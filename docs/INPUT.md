# INPUT — touch screen, touchpad, pen (state 26.10.2026)

Ist-Stand only. "Measured" = a gate in this tree ran it (QEMU/KVM, synthetic or captured reports). No touch hardware has run OrientOS yet; see section 7.

## 1. Layers

| Layer | Files | Job |
|---|---|---|
| Transport | `kernel/usb/usb.fi` (USB HID class), `kernel/drv/hid/i2chid.fi` (HID over I2C: DesignWare/LPSS via PCI, ACPI `PNP0C50` via AML or byte search) | get the report descriptor and the input reports; register the device |
| Registry | `kernel/drv/hid/inreg.fi`, rows in `lib/touchev/quirk.fi` | per slot: bus, vid, pid, quirk flags |
| Input mode | `kernel/drv/hid/hidmode.fi`, `lib/touchev/inmode.fi` | a Windows Precision Touchpad starts in mouse mode: the descriptor's Device Mode (digitizer 0x52) and Surface/Button switch (0x57, 0x58) feature fields are set (3 and 1) with SET_REPORT after the descriptor is parsed: I2C command-register frame, USB class request `0x21 0x09`, wValue `0x03<id>` |
| Descriptor parser | `kernel/drv/hid/hidrep.fi` (+ reference parser `tools/hid/descs.py`) | descriptor -> field table (page, usage, bit offset, size, range), kind (kbd, mouse, pad, touch, pen) |
| Report -> contacts | `kernel/drv/hid/hidbits.fi`, `hidcontact.fi`, `hidframe.fi` | one digitizer report -> contacts (tip, confidence, id, x, y, pressure, width, height, count, buttons); `hidframe` joins the reports of one frame when Contact Count is larger than the slots of a report (hybrid mode: first report carries the total, continuation reports carry 0) |
| Tracker | `kernel/drv/hid/hidev.fi` -> `lib/touchev/track.fi` | slots, DOWN/MOVE/UP, x/y normalized to 0..65535, quirks (swap, invert, single touch, palm) |
| Event ring | `kernel/drv/hid/evring.fi`, `/proc/touchev` (`kernel/fs/procfs.fi`) | 128 normalized records; a read drains them |
| Gestures | touch screen: `lib/touchgest/direct.fi`; touch pad: `lib/touchgest/gest.fi`; shared `lib/touchgest/geom.fi` | tap, double tap, long press, drag, scroll, pinch, 3/4-finger swipe, palm rejection; every threshold is an option |
| Pointer / window server | `kernel/drv/hid/hidin.fi` (`touch`, `pad`, `touch_apply`, `gest_apply`) -> `gfx.mouse_*` | gesture events as mouse packets, wheel steps, Ctrl+wheel zoom, swipe actions |
| App API | `lib/touchev/api.fi`, demo `kernel/user/touchdemo.fi` | `open`, `refill_from`, `poll`, `next_gesture`, accessors |

One input path: PS/2, USB-HID and I2C-HID all end in `hidin.report(state, slot, buf, len)`. The window server does not know the bus.

## 2. Record format (`lib/touchev/record.fi`, little endian)

Snapshot = 16-byte header (`TEV1`, count, dropped since last read, seq of the first record) + count x 24-byte record.

| Offset | Field |
|---|---|
| 0 | type: 1 DOWN, 2 MOVE, 3 UP, 4 GESTURE |
| 1 | slot 0..9 (255 for gestures) |
| 2 | device: 1 touch screen, 2 touch pad, 3 pen |
| 3 | flags: 1 palm, 2 barrel, 4 eraser, 8 hover; for gestures the gesture kind (1 tap, 2 long, 3 drag begin, 4 drag, 5 drag end, 6 scroll, 7 pinch, 8 swipe) |
| 4, 6 | x, y normalized 0..65535 (after quirks) |
| 8, 10 | x, y in pointer pixels (0 for touch pads) |
| 12, 14 | pressure, size, normalized (0 = unknown) |
| 16 | time in ms |
| 20, 22 | signed args. Tap: a = tap count, b = button mask. Scroll: a, b = dx, dy px. Pinch: a = distance change px, b = zoom steps. Swipe: a = direction (1 left, 2 right, 3 up, 4 down), b = fingers |

Every record is global: there is no per-window routing and no per-app right yet.

## 3. App API

```
import touchev.api
let fd = open("/proc/touchev")      // ulib.sys(SYS_OPEN ...)
let n  = read(fd, buf, 3088)        // drains the ring
api.open()
api.refill_from(buf, n)             // false and counted when the header is wrong or the snapshot is short
while api.poll() { api.ev_type(); api.ev_slot(); api.ev_x(); api.ev_x_px(); api.ev_a() }
api.next_gesture()                  // skips raw records, returns the gesture kind (0 = none), gesture_a()/gesture_b()
```

`kernel/user/touchdemo.fi` is the complete example.

## 4. Gesture options (data, `lib/touchgest/direct.fi`)

`direct.set_opt(slot, O_*, value)` per device, defaults in `opt_default`, bounds in `opt_min`/`opt_max`:
`O_ENABLED 1`, `O_SLOP_PX 12`, `O_LONG_MS 650`, `O_DTAP_MS 300`, `O_DTAP_PX 32`, `O_WHEEL_PX 40`, `O_NATURAL 0`, `O_PINCH 1`, `O_PINCH_STEP_PX 48`, `O_SWIPE 1`, `O_SWIPE_PX 120`, `O_HSCROLL 1`, `O_PALM_SIZE 0` (off), `O_LONG 1`.
Touch pad options (`lib/touchgest/gest.fi`) come from `/etc/touchpad.conf` (`tpcfg.fi`) and `/etc/mouse.conf`. There is no config file for the touch screen options yet; the kernel uses the defaults.

## 5. Add a quirk (one row)

`lib/touchev/quirk.fi`, table `ROWS`, four numbers per row: bus (0 any, 1 USB, 2 I2C, 3 Bluetooth, 4 virtual), vid, pid (0xFFFF = any), flags. Replace a free row (`0xFF, 0, 0, 0`):

```
    0, 0x045e, 0x0c32, 16,
```

Flags: 1 swap x/y, 2 invert x, 4 invert y, 8 ignore confidence, 16 single touch, 32 ignore device, 64 no palm. All matching rows are OR-ed. A row applies to every HID collection of that vid:pid (the Surface touch screen and pen share 045e:0c32). `quirk.add_row` does the same at run time. `/proc/inputdevs` shows the result per slot: `hid4 kind=16 vid=0x.. pid=0x.. bus=2 q=0x..`.

## 6. Add a transport (under 20 lines)

```
let raw: u64 = hidrep.raw_of(state, slot)          // slot 0..2 USB, 3..7 I2C (hidrep.MAX_DEV 8)
// copy the report descriptor (<= hidrep.RAW_MAX bytes) to raw
if hidrep.parse(state, slot, raw, len) != hidrep.E_OK { return false }
let _q: u64 = inreg.register(slot, quirk.B_xxx, vid, pid)
hidin.reset_dev(state, slot)
// for every input report (with the report-id byte when the descriptor uses ids):
let ok: bool = hidin.report(state, slot, buf, len)
```

Nothing else is needed: the kind comes from the descriptor, contacts, tracker, ring, gestures and pointer follow.

## 7. Measured and not measured

Measured (gate `tools/input/run.sh`, QEMU/KVM):
- `lib/touchgest`: 269 promises, 0 errors (touch screen machine `direct.fi`: 86 promises, 22 broken-lib controls).
- `lib/touchev`: 264 promises, 0 errors.
- Touch screen kernel traces after moving the gesture logic into `direct.fi`: byte-identical to the old inline code (36 lines, `touchsim`).
- Surface Laptop 4 capture (`tools/input/corpus/holo-laptop-3`, 2026-10-26, see 8): the three synthesized descriptors parse in the kernel parser (kind pad / touch / pen) and the example reports produce exactly the events an independent Python model computes (`tools/input/corpus_kernel.py`), including the three quirk experiments.
- Input mode: for the Surface descriptors the kernel plans two feature reports (id 7 payload `03`, id 8 payload `03`) and builds I2C frames that equal an independent model of the HID-over-I2C SET_REPORT format (`corpus: inmode` / `corpus: i2c` lines).
- Hybrid mode: a synthetic touch screen with 2 contact slots per report and 3 contacts per frame produces the events of the joined frame only (`tools/input/synthetic.py`, 7 events).
- Ring-3 demo app reads `/proc/touchev` through the API; the second read finds the ring drained (`tools/input/e2e.sh`).

Not measured:
- Any real device accepting the input-mode SET_REPORT (I2C write and USB control transfer are spec-only, like the rest of the I2C-HID register path).
- Any real touch screen, touch pad or pen on OrientOS. The timing of taps and long presses on real hardware is unknown.
- The descriptors of the corpus are synthesized from HidP capabilities, not the raw descriptors of the device (Windows does not expose them to user mode).
- Pressure/size normalization with real devices; palm rejection beyond the HID confidence bit; touch screen settings page.

## 8. Hardware findings

HOLO-LAPTOP-3 = Surface Laptop 4 (Windows). Its input is not I2C-HID:
- Touch pad and keyboard: Surface Aggregator (`vid 045e pid 09ae/09af`, virtual HID). The pad itself is a standard Windows Precision Touchpad (5 contacts, x 0..2227, y 0..1459, feature reports for input mode).
- Touch screen and pen: Intel Precise Touch & Stylus (PCI `8086:a0d0`, `vid 045e pid 0c32`). HID shows a single-contact touch screen (tip, x, y 15 bit) and a pen with pressure and tilt; multi-touch frames come as vendor reports (7488 bytes). OrientOS needs two more transports (Surface Aggregator, IPTS) before this machine works; they are not built.

HP stick (`/proc/inputdevs`, build 6358e3d4, 26.10.2026): `i2c_ctrls=0 i2c_devs=0 hid_devs=0`. The LPSS functions `8086:9d60..9d62` are present with PCI class 0x1180, the DSDT contains `PNP0C50`, `WCOM48..` and `ALP0..`. Why `find_ctrls` found no controller is unknown. `/proc/inputdevs` now lists every candidate (`cand<N> bdf= id= bar0= comp= ok=`); the next boot of an HP stick built from this tree shows which step failed.

## 9. Gate

`bin/heavy bash tools/input/run.sh` runs: touchgest, touchev, corpus checks, touchsim, corpus replay in the kernel, ring checks, registry lines, end-to-end demo. Regression gates touched by the move: `tools/hid`, `tools/i2csim`, `tools/touchsim`, `tools/usbhid`, `tools/hidweg`, `tools/hidpunkte`, `tools/hidwheel`, `tools/ptrcfg`.

Capture script for a new machine: `tools/input/capture/hid-caps.ps1` (PowerShell, no admin) writes `%TEMP%\hid-caps.txt`; `tools/input/caps2desc.py` turns a `.caps` file into a descriptor.
