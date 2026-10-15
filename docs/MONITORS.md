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

## Kernel wiring, round 2 (r815 + r819, 15.10.2026) — EXTEND over several heads
- Word `vgpuextend` (default OFF, M_VGPUEXT) + at least 2 connected heads: the desktop stays **ONE wide resource** (the fb back
  buffer, `fbres=` = bounding box of the heads) and **every head scans out its own rect of it** (`SET_SCANOUT` with r.x/r.y/r.w/r.h,
  `vgpu.ext_place`). Zero copy: `TRANSFER_TO_HOST_2D`/`RESOURCE_FLUSH` of the dirty rect are unchanged, the host refreshes every
  scanout the rect touches. Why not one resource per head: `TRANSFER` uses the resource stride, a head-sized resource could not read a
  sub-rect of the wide back buffer without a copy per frame (or a scatter list per scanline, 512-byte command limit).
- Placement = `lib/monitors/layout.fi` `pack_row` (left to right in head order, tops at 0). A head that does not fit the fb is cut
  (`extc`) or skipped; a refusal is counted in `exte`. One head + the word -> old path (whole desktop on the head), `ext=0`.
- Serial: `... ext=1  extp=2  exte=0  extc=0` and `vgpu: ext head N rect=X,Y WxH`. Accessors: `vgpu.ext_active/ext_x/ext_y/ext_w/ext_h/ext_head_at`.
- **wm today = SPAN:** `fb.width()` is the whole desktop, so windows can sit/move on any head; taskbar and maximize still span ALL heads
  (not per output). The real per-output compositor step (taskbar per head, maximize/snap to the window's head via `ext_head_at`,
  cursor clamp to the rect union) is open (roadmap).
- Desktop size is still taken from `fbres=`/the boot mode, not from the heads: nothing sizes the fb to the bounding box yet.
- **r819 bug found and fixed:** with a virtio-gpu `fb.flush` returns at once; only `vgpu.present` (via `gfx.bild_fertig`) sends dirty
  rects to the host. `gfx_hold` (fbtest harness) never called it, so every vgpu screendump of the harness was BLACK (also the mirrored heads of r808).
  Now `gfx_hold` calls `gfx.bild_fertig` after its last flush.
- Gate `tools/vgpuext/run.sh` (22/0): extend counters + rects, screendump pixel checks (head 0 red square + magenta box, head 1 ONLY
  its cyan box, not black, differs), mirror not black + identical + red square on head 1, controls (1 head, desktop too small).

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

## r826 window server per output (wm.fi)

- Head rects live in ONE place: the pointer driver's head table (`ps2m.set_head`); `wm.heads_sync` fills it from the vgpu extend table (after `wm.init` when extend is on, and from `gfx.gpu_ereignis` after every successful `vgpu.relayout`). Fewer than two heads = model off, behaviour identical to a single screen.
- Home head of a window = head its outer rect overlaps most (`win_head`); none = primary. `head_work(hd)` = work area of one head, computed from scratch (packed x|y|w|h, 16 bit each); a strut counts only for heads its window overlaps, the measuring band only for the head at the desktop origin.
- `maximize`/`fit_work`, `fullscreen` and `drag_klemmen` use the home head; `recalc_work` feeds `work_*` and the tile tree from the primary head; edge docking works on the primary head only.
- `heads_sync`: windows on no head come to the primary head, others keep their title bar reachable, fullscreen windows refit, maximized ones refit via `recalc_work`, pointer re-clamped.
- Gate: `tools/wmheads/run.sh` (words `hdtest`, `hdhot`; test bed `wm.hd_demo`).
- Open: taskbar instance per head (`--head` in taskbar.fi), tile tree per head, real hardware.
