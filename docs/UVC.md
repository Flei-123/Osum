# UVC camera (r809) -- protocol half

`lib/uvc/uvc.fi` + gate `tools/uvc/run.sh` (87 checks, 12 mutation controls).

Done (host-testable): configuration descriptor parse (VC/VS interface, MJPEG + uncompressed
formats, frames, isoc alternate settings incl. high-bandwidth multiplier, bulk streaming),
`pick_frame`/`pick_alt`, 26 byte VS_PROBE/VS_COMMIT build + answer validation, payload-header
frame assembler (FID, EOF, ERR, overflow), `jpeg_ok`, `yuy2_to_xrgb`.

NOT done (honest): no driver. Missing steps, in order:
1. `kernel/drv/usb/xhci.fi`: isochronous transfers (ISOCH TRBs, TD per frame, interval, Evaluate/Configure
   with the chosen alt setting). Bulk streaming works with `xhci.bulk`/`int_queue` today.
2. `kernel/usb/usb.fi`: bind class 0x0E (VC=1, VS=2); `parse_config` -> SET_INTERFACE(alt) ->
   SET_CUR/GET_CUR PROBE -> SET_CUR COMMIT -> read endpoint -> `asm_feed` per packet.
3. Test device: QEMU 7.2 has no `usb-camera` (added in QEMU 10: `-device usb-camera` + `-cameradev builtin`).
   Until then only real hardware (laptop built-in webcam is UVC behind xHCI/USB 2.0 hub).
4. App: frame -> `yuy2_to_xrgb` / MJPEG decoder (lib/photo/jpegenc exists for encoding only).
