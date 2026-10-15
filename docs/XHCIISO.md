# xHCI isochronous transfers (r813)

## What exists
- `lib/xhciiso/iso.fi`: pure arithmetic, host-tested (`tools/xhciiso/run.sh`): endpoint context words
  (type ISOC OUT = 1 / IN = 5, **CErr = 0**, interval, Mult, Max Burst, Max ESIT), wMaxPacketSize split,
  TBC / TLBPC, Isoch TRB words (type 5, IOC, ISP, SIA), completion-code classes.
- `kernel/drv/usb/xhci.fi`:
  - `isoc_open(slot, dci, in_dir, speed, wMaxPacketSize, ss_burst, ss_attrs, bInterval)` -- ring + record
    (up to 4 isoc endpoints, records in the scalar page 0x200..0x400)
  - `isoc_fill_ctx(slot, dci)` -- writes the endpoint context into the input context (then Configure Endpoint)
  - `isoc_queue(slot, dci, buf, len)` -- ONE TD = one Isoch TRB (IOC, SIA = start at next service opportunity);
    refuses when the TD does not fit one service interval or when 12 TDs are pending (ring has 15 usable slots)
  - `isoc_pending`, `isoc_stat(ISO_QUEUED | ISO_EVENTS | ISO_BYTES | ISO_UNDER | ISO_MISSED | ISO_ERR)`
  - the event handler keeps isoc events OUT of the controller error counter: ring underrun/overrun,
    missed service and other codes have their own counters; bytes = TRB length - residue.
- Test bed in `kernel/usb/usb.fi`: word `isoctest` binds the audio CONTROL interface of a USB audio device
  to `DRV_ISOTEST`: finds the streaming alt setting with an isoc OUT endpoint (`iso_data`), configures it,
  SET_INTERFACE, feeds 200 TDs of a 1 kHz square wave, prints one `usb: isoc alt=.. mps=.. queued=.. events=.. bytes=.. under=.. missed=.. err=..` line.
- Gate `tools/xhciisoq/run.sh` (QEMU `qemu-xhci` + `usb-audio` with the wav backend; the wav file is checked for the tone).

## Not covered (honest)
- Isochronous IN: the code path exists (`in_dir`, ISP, endpoint type 5) but QEMU 7.2 `usb-audio` has no capture
  path and there is no `usb-camera` -> untested. A camera driver (r814) must prove it on hardware.
- Super speed bursts (TBC > 0, Mult) and high speed multi-packet TDs: arithmetic is host-tested, not run in QEMU.
- Several TDs per TRB chain (TD larger than one TRB): not needed for audio/video frames of one service interval.
- Real timing: QEMU paces frames with its own clock; underrun behaviour on real hardware is unmeasured.
- Endpoint stop / reset for isoc (Stop Endpoint + Set TR Dequeue) when the stream ends: not done; the test just stops queueing.
