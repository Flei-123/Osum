# VMSVGA (VMware SVGA II) -- research note + integration map for the OrientOS driver

Status 16.10.2026: research done, driver `kernel/drv/gpu/vmsvga.fi` NOT written yet.
Goal: VirtualBox 7 with graphics controller "VMSVGA" (PCI 15ad:0405) and NO guest additions:
free resolution, update rectangles instead of full refresh, hardware cursor. VBoxVGA = Bochs VBE
(`kernel/gfx/vmode.fi`) stays the fallback.

HONESTY: only QEMU 7.2.22 (`-vga vmware`, `-device vmware-svga`) exists on the build server.
Everything marked [VBOX?] is from memory of the VirtualBox device and MUST be checked on a real VirtualBox.

## 1. Sources (read in this session)
- Register / FIFO / command numbers: Mesa `src/gallium/drivers/svga/include/svga_reg.h`
  (same numbers as Linux `drivers/gpu/drm/vmwgfx/device_include/svga_reg.h`).
- QEMU v7.2.0 `hw/display/vmware_vga.c` (what the emulator really implements).
- Local copies: /root/jarvis/data/projects_kb/orientos/reports/vmsvga-ref/

## 2. PCI and ports
- Vendor 0x15AD, device 0x0405, class 03:00 (QEMU). BAR0 = I/O (16 ports), BAR1 = framebuffer VRAM (memory),
  BAR2 = FIFO (memory; QEMU 64 KiB, VirtualBox bigger [VBOX?]).
- Ports (relative to BAR0): INDEX +0, VALUE +1, BIOS +2, IRQSTATUS +8. Access is 32 bit (`outl/inl`), and the VALUE
  port is UNALIGNED (+1): QEMU allows it explicitly (`.valid.unaligned = true`, min access 4).
- Register access = `outl(BAR0+0, index); inl/outl(BAR0+1, value)`. Needs PCI command bits IO + MEM (+ bus master not needed
  for FIFO-only use).

## 3. Registers (index: name)
0 ID, 1 ENABLE, 2 WIDTH, 3 HEIGHT, 4 MAX_WIDTH, 5 MAX_HEIGHT, 6 DEPTH, 7 BITS_PER_PIXEL, 8 PSEUDOCOLOR, 9 RED_MASK,
10 GREEN_MASK, 11 BLUE_MASK, 12 BYTES_PER_LINE, 13 FB_START, 14 FB_OFFSET, 15 VRAM_SIZE, 16 FB_SIZE,
17 CAPABILITIES, 18 MEM_START, 19 MEM_SIZE, 20 CONFIG_DONE, 21 SYNC, 22 BUSY, 23 GUEST_ID, 25 CURSOR_X, 26 CURSOR_Y,
27 CURSOR_ON, 29 SCRATCH_SIZE, 30 MEM_REGS, 32 PITCHLOCK, 33 IRQMASK, 34 NUM_GUEST_DISPLAYS, 35..40 DISPLAY_*
(topology), 45 TRACES. (24 was CURSOR_ID in old headers, DEAD in new ones; QEMU still takes it as CURSOR_ID.)
- Negotiation: write ID = 0x90000002 (SVGA_ID_2), read back; equal -> SVGA II. QEMU 7.2 accepts only ID_0/1/2
  (NOT ID_3 = 0x90000003). Version mismatch -> give up (fallback path).
- Mode: write WIDTH, HEIGHT, BITS_PER_PIXEL (must be 32 in QEMU, else it clears CONFIG_DONE), ENABLE=1; then read
  BYTES_PER_LINE and FB_OFFSET (QEMU: 0, stride = width*4, no padding) and FB_START (= BAR1 address).
  Limits: QEMU MAX 2368x1770; REG MAX_WIDTH/MAX_HEIGHT report the host limit; VRAM_SIZE bounds w*h*4.
  QEMU applies WIDTH/HEIGHT lazily (display refresh calls `vmsvga_check_size`), so re-read after a short wait.
- FIFO bring-up (Linux `vmw_fifo_init` convention, from memory -- verify): FIFO[MIN] = max(4096, MEM_REGS*4) bytes
  (MEM_REGS only with CAP_EXTENDED_FIFO), FIFO[MAX] = MEM_SIZE, FIFO[NEXT_CMD] = FIFO[STOP] = MIN; then CONFIG_DONE = 1.
  QEMU checks MIN/MAX/NEXT/STOP against its 64 KiB FIFO. QEMU runs the FIFO on a SYNC write (reg 21) (and, from memory,
  in its display refresh): write the command, advance NEXT_CMD, write SYNC = 1.
- Capabilities (reg 17): RECT_COPY 0x2, CURSOR 0x20, CURSOR_BYPASS 0x40, CURSOR_BYPASS_2 0x80, ALPHA_CURSOR 0x200,
  3D 0x4000, EXTENDED_FIFO 0x8000, MULTIMON 0x10000, PITCHLOCK 0x20000, IRQMASK 0x40000, DISPLAY_TOPOLOGY 0x80000,
  GMR 0x100000, TRACES 0x200000, GMR2 0x400000, SCREEN_OBJECT_2 0x800000.
  QEMU 7.2 reports: RECT_COPY | (CURSOR | CURSOR_BYPASS | CURSOR_BYPASS_2 if the display supports cursors).
  NO ALPHA_CURSOR, NO EXTENDED_FIFO in QEMU.

## 4. FIFO (u32 words, ring between MIN and MAX bytes)
- Header regs: 0 MIN, 1 MAX, 2 NEXT_CMD, 3 STOP; extended (needs CAP_EXTENDED_FIFO): 4 CAPABILITIES, 5 FLAGS, 6 FENCE,
  7 3D_HWVERSION, 8 PITCHLOCK, 9 CURSOR_ON, 10 CURSOR_X, 11 CURSOR_Y, 12 CURSOR_COUNT, 13 CURSOR_LAST_UPDATED,
  14 RESERVED, 15 CURSOR_SCREEN_ID, 16 DEAD.
- FIFO caps (word 4): FENCE 1<<0, ACCELFRONT 1<<1, PITCHLOCK 1<<2, VIDEO 1<<3, CURSOR_BYPASS_3 1<<4, ESCAPE 1<<5,
  RESERVE 1<<6, SCREEN_OBJECT 1<<7, GMR2 1<<8, SCREEN_OBJECT_2 1<<9, DEAD 1<<10.
- Commands: 1 UPDATE {x,y,w,h}; 3 RECT_COPY {sx,sy,dx,dy,w,h}; 19 DEFINE_CURSOR {id,hotX,hotY,w,h,andDepth,xorDepth,
  and-mask scanlines, xor scanlines}; 22 DEFINE_ALPHA_CURSOR {id,hotX,hotY,w,h, w*h ARGB u32}; 25 UPDATE_VERBOSE.
  Every command is a u32 command number followed by u32 arguments; write at NEXT_CMD, wrap at MAX -> MIN, publish by
  storing the new NEXT_CMD last (after a write barrier).
- QEMU 7.2 handles UPDATE, RECT_COPY, DEFINE_CURSOR (bpp 1 and 32). It CONSUMES BUT IGNORES DEFINE_ALPHA_CURSOR
  (prints "Unknown command"). UPDATE copies VRAM->display surface; since 7.x the surface IS the VRAM
  (`qemu_create_displaysurface_from`), so a screendump never shows stale pixels: QEMU cannot prove that the update
  rectangles are complete. The gate needs a kernel-side check for that (see 7).

## 5. Cursor
- Shape: ALPHA_CURSOR cap -> DEFINE_ALPHA_CURSOR (same BGRA tile as `vgpu.cursor_bild_fuellen`, built from
  `cursor.karte_bauen/cursor.deck`); else DEFINE_CURSOR with 32 bit xor image + 1 bit and-mask (QEMU path).
- Position/visibility: if CAP_EXTENDED_FIFO and FIFO caps has CURSOR_BYPASS_3 [VBOX?: expected on VirtualBox]:
  write FIFO[CURSOR_ON]=1, FIFO[CURSOR_X], FIFO[CURSOR_Y], then FIFO[CURSOR_COUNT]++ (host polls the counter).
  Else legacy registers: CURSOR_X, CURSOR_Y, then CURSOR_ON = 1 (SHOW) / 0 (HIDE) (QEMU path -> `dpy_mouse_set`).
  CURSOR_ON 2/3 = REMOVE_FROM_FB / RESTORE_TO_FB (bypass 2, not needed).
- QEMU screendumps do NOT contain the hardware cursor: "no software pointer in the picture" is testable by screendump,
  "pointer moves" only by the kernel counters (cursor defs / moves).

## 6. Resize
- Guest driven (works in QEMU and VirtualBox): new WIDTH/HEIGHT/BPP + ENABLE, read BYTES_PER_LINE, `fb.remap`.
  The VRAM address (BAR1) never changes, only the number of 2 MiB windows (`vmode.switch_to` does the same for VBE).
- Host driven (VirtualBox window resize / "Auto-resize") [VBOX?, UNVERIFIED]: without guest additions VirtualBox does NOT
  resize on its own; the hint arrives through display topology registers (CAP_DISPLAY_TOPOLOGY, regs 34..40) and the
  SVGA_REG_MSHINT/IRQ path of newer devices. Read Linux `vmwgfx_ldu.c` / `vmwgfx_kms.c` (`vmw_du_connector_detect`,
  `vmw_du_update_layout`) before writing the poll. QEMU has NO host resize hint at all.

## 7. Integration map (where the code goes) -- found by reading the tree
- Detect+init: `kernel/ui/kgui.fi` `graphics()` right after `fb.init`/`fb.set_shadow` and the `vgpu.init` block:
  `if !novgpu && !vgpu.bereit && !novmsvga { vmsvga.init }`. Order: virtio-gpu > vmsvga > Bochs VBE > firmware LFB
  (`fb.init` "Weg 1" = multiboot/Limine LFB, "Weg 2" = Bochs VBE `vbe_set`). On VirtualBox the LFB usually comes from the
  loader (Weg 1); VMSVGA shares the VRAM (BAR1) with it, so ENABLE with the SAME size first, resize later.
- Word `novmsvga`: add a mode bit next to `kstate.M_NOVGPU` (see `kstate.fi` + the word parser in `kmain`).
- State page: own kdata page like `VGPU_OFF=0xF2000` (check `tools/kernel/memmap.py` for a free range).
- Frame boundary: `gfx.fi` `bild_fertig` -> add `vmsvga.present`. The copy into VRAM stays `fb.flush_rect` (VRAM is device
  memory, no zero-copy as with virtio-gpu); add an accumulator for the bounding box of the spans the diff path REALLY wrote
  (`first/last` per row in `flush_rect`), also in the non-diff branches, `flush`, `flush_stripe`, `flush_rows`, `present`.
  One UPDATE per frame with that box. Keep the shadow logic as is (`shadow_inval` on mode switch).
- Waage: `fb.tx_add` is already called per copied span; count UPDATE rectangles/pixels in new counters and print them in a
  `vmsvga:` line like `vgpu.say` (`okt= rect= bilder=`).
- Cursor hooks: `kernel/ui/wm.fi` ~14046..14103 call `vgpu.cursor_bereit/zeigen/bewegen/aus/an`; add the vmsvga twins
  behind the same functions.
- Mode switch: `vmode.fi` `switch_to` is Bochs-only (`vbe_set`, `S_LFB`); give it a backend switch to `vmsvga.set_mode`.
  Branch `staff/orientos-vmode-shadow` (shadow reallocated on bigger mode) must stay compatible.
- Build: `kernel/gfx/gfx.fi` + `gfx-aus.fi` (`--gui off` stub) import the driver like `drv.gpu.vgpu`.

## 8. Gate plan (`tools/vmsvga/run.sh`, patterns: tools/vgpuheads, tools/vgpuext, tools/vboxlag)
1. Detection line `vmsvga: bdf=.. id=0x90000002 caps=.. fifo=.. vram=..` in `-vga vmware` / `-device vmware-svga`.
2. Three or more modes (e.g. 800x600, 1024x768, 1280x720): screendump (first console) pixel-equal to
   a reference taken with `novmsvga`+Bochs at the same size.
3. Hardware cursor: no pointer pixels in the screendump near the mouse position; counters show defs once, moves per step.
4. Pointer move: octets per frame <= 64 KB (same urteil as tools/vboxlag), idle < 100 KB/s.
5. Update-rect completeness (QEMU cannot show it): kernel debug word compares back buffer and VRAM outside the sent
   rectangle at `present` and prints `vmsvga: verify bad=N` (expect 0).
6. Counter-proof: word `novmsvga` -> old path, the same measurement must FAIL (more octets / no UPDATE counters).
7. Regress, one at a time: tools/vgpuheads, tools/vgpuext, tools/vboxlag unchanged green.
