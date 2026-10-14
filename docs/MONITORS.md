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

## What is NOT done (honest)
1. **Kernel still has one framebuffer.** `fb.fi` = one address/geometry/back buffer; `wm.fi`
   (17.8k lines) composes into one surface at (0,0) and uses `fb.width()` ~20 times for "the screen".
   Wiring = every such call must name an output; the compose pass runs per output rect.
2. **vgpu.fi** reads `num_scanouts` and `GET_DISPLAY_INFO` but takes the **first connected** scanout
   only and issues `SET_SCANOUT` with scanout_id 0. Needs: per-scanout resource, `SET_SCANOUT` per id,
   EVENT_DISPLAY per output. QEMU side is ready (`-device virtio-gpu-pci,max_outputs=2`, measured by the gate).
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
