# Multiple monitors (L-003 r757, L-004 r758) — status 14.10.2026

Gate: `bash tools/monitors/run.sh` (87 promises incl. 6 negative controls, host only, no kernel boot).

## What exists now
- `lib/monitors/layout.fi` — the **output object** that `docs/DISPLAY.md` 8.4 asked for first:
  up to 8 outputs, global desktop in physical pixels (negative positions allowed), modes
  **extend / mirror / single**, per-output rect, enable/disable, primary, hotplug (unplug re-packs,
  primary moves), arrangement with **overlap and detach refusal** (rolled back), `place_beside`
  (right/left/below/above, edge or centred), hit test, cursor clamp (pulls a cursor out of a gap
  back to the nearest screen), window home = output with the largest overlap, mirror letterbox
  (largest integer-percent fit, centred).
- **Per-monitor scale (L-004):** default from EDID width (dpi → 100/125/150/175/200/250/300 %),
  settable per output, logical size = physical × 100 / scale; scale never moves rects.
- **HDMI/DP audio decision (L-004):** `edid_has_audio` (CEA-861 extension, basic-audio bit) and
  `audio_pin` (HDA `GET_PIN_SENSE` presence bit 31 **and** ELD-valid bit 30 **and** EDID audio).
  No sound to a monitor without audio, with the cable out, with ELD not yet valid, or switched off.

## Kernel wiring, round 1 (r808, 15.10.2026) — vgpu output table, EDID, mirror
- `kernel/drv/gpu/vgpu.fi` keeps an **output table** (8 heads, like `layout.fi` MAX_OUT): connected flag, rect, size from
  `GET_DISPLAY_INFO` for **all** heads (before: only the first one was read).
- **EDID per head:** `VIRTIO_GPU_F_EDID` is negotiated; `GET_EDID` (0x010A) per connected head, base block checked
  (header + checksum) and parsed: maker letters, preferred mode (first DTD), physical size in mm (bytes 21/22, cm),
  suggested UI scale (same rule and snap table as `layout.default_scale`). Never fatal: a bad EDID leaves the head at 100 %.
- **Mirror:** every further connected head gets `SET_SCANOUT` (scanout_id = head) with the **same resource** as head 0.
  `RESOURCE_FLUSH` of that resource then refreshes all heads. Serial: `vgpu: ... heads=2 mirr=1 merr=0`,
  one `vgpu: head N WxH edid=XXX pref=WxH mm=WxH scale=P` line per head.
- Test bed word `vgpuheads` (default OFF): QEMU **without a GUI backend** (no gtk/sdl module here) never flags head >= 1 as
  `enabled`, so with the word the driver treats every scanout the device has as connected. Without the word only
  heads the device reports as enabled are used (what real hardware / a GUI QEMU gives).
- Gate: `tools/vgpuheads/run.sh` (QEMU `max_outputs=2` + control `max_outputs=1`; `screendump` of head 0 and head 1 are
  non-black and byte-identical).
- Not wired yet: `lib/monitors/layout.fi` itself (extend/arrangement) — the kernel has no per-output compositor.

## What is NOT done (honest)
1. **Kernel still has one framebuffer.** `fb.fi` = one address/geometry/back buffer; `wm.fi`
   (17.8k lines) composes into one surface at (0,0) and uses `fb.width()` ~20 times for "the screen".
   Wiring = every such call must name an output; the compose pass runs per output rect.
2. **vgpu.fi**: table + EDID + mirror done (see above). Still needs: a per-scanout resource for EXTEND, hotplug
   (EVENT_DISPLAY re-reads the table but does not re-run `SET_SCANOUT` for new heads). QEMU side is ready (`-device virtio-gpu-pci,max_outputs=2`, measured by the gate).
3. **Settings → Display arrangement canvas** (drag rectangles → `set_position`) is not built; the model
   API for it is.
4. **HDA HDMI:** `hda.fi` skips digital pins by design. Needs: digital converter + IEC958 format,
   ELD read (`GET_HDMI_ELD`), pin presence polling/unsolicited events, then call `audio_pin`.
5. Per-monitor scale in the UI toolkit (fUi layout would ask its window's output for the scale).

## Order of the next rounds
1. Kernel: output table in `fb.fi` (array instead of scalars, `fb.width(out)`), feed from `layout.fi`.
2. vgpu: per-scanout `SET_SCANOUT` with 2 outputs in QEMU, boot test `scanout=2` + screendump of both.
3. wm: compose per output; cursor uses `clamp_x/clamp_y`; windows get their home output.
4. Settings canvas; persistence of the arrangement (key=value like other settings).
5. HDA HDMI pin + ELD.
