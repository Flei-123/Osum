# GPU status: what each display path can do (16.10.2026)

Scope: the paths OrientOS/Osum has for putting pixels on a screen in a VM or on a PC.
"Measured" = a gate in `tools/` proves it. "QEMU only" = proven only against QEMU's device model.

| Capability | virtio-gpu (`kernel/drv/gpu/vgpu.fi`) | bochs-vbe / std-vga (`kernel/gfx/vmode.fi`) | Firmware LFB (UEFI/GOP, Limine) |
|---|---|---|---|
| Mode switch at runtime | Follows the back buffer: `vgpu.resize` rebuilds resource + scan-out (hooked into `vmode.switch_to`) | Yes, VBE dispi registers, custom sizes within VRAM (`tools/customres`, `tools/display`: green) | No (size fixed by firmware) |
| Host window resize / hotplug | Config-change event -> `GET_DISPLAY_INFO` -> `vmode.follow_host` -> resize. Measured, **QEMU only** (`tools/vgpuhw`, VNC SetDesktopSize) | No host event exists on this device | No |
| EDID | Read per head (`GET_EDID`, maker, preferred mode, mm, scale), `tools/vgpuheads` | `vmode.edid_probe` only if the card exposes it; QEMU std-vga with `edid=on` | Not read |
| Multiple heads | Mirror (SET_SCANOUT per head) and extend (own rect per head), `tools/vgpuheads`, `tools/vgpuext`; QEMU only | One head | One head |
| Hardware cursor | Cursor queue (UPDATE/MOVE_CURSOR). Measured: 59 moves, 0 octets through the resource, no pointer pixels in screendump (`tools/vgpuhw`, QEMU only) | No cursor plane: pointer painted by the compositor | No cursor plane |
| Dirty-rect flush | `TRANSFER_TO_HOST_2D` + `RESOURCE_FLUSH` for the dirty rect only; 48x48 rect = 9216 octets/frame (`tools/vgpuhw`) | Copy of dirty rows/rect into the LFB, diff flush against a shadow copy (`fb.flush_rect`, `tools/vboxlag`) | Same copy path as bochs |
| Octets per frame | Rect size (see above); whole screen only when everything is dirty (control `wmruhe`: 1.92 MB at 800x600) | Diff flush: pointer phases <= 64 KB/frame, idle < 100 KB/s (`tools/vboxlag`, VBox-like VM) | Same as bochs |
| Vsync / tearing | Resource flush is atomic per rect (no tearing inside the rect) | None (copy into live LFB) | None |
| VirtualBox | Not available (VBox uses VBoxVGA/VMSVGA) | VBoxVGA is a different device; bochs paths not applicable | Used on UEFI boot |

## What was added in this round
- `vgpu.resize(w,h)`: unref the old resource, create + attach the same back buffer at the new size, SET_SCANOUT (+ mirrors), full transfer/flush.
  Before this, a mode switch while virtio-gpu was active left the resource at the old size (stale geometry).
- `vmode.follow_host(w,h)`: refuses < 640x480 and anything `check_custom` refuses, otherwise `switch_to` without a confirmation deadline.
- `gfx.gpu_ereignis` calls it after a display event (single-head mode). Extend mode keeps its own `relayout` path.
- Kernel word `vgpuhw` + `tools/vgpuhw/run.sh`: pointer moves, dirty-rect octets, host resize via VNC, byte-compare against `novgpu`, three controls
  (`nohwcur`, `wmruhe`, no resize request).

## Open
- The host size is NOT applied at boot (only on a later event). The device default (xres/yres) differs from the fbtest/boot size.
- After a size change the window server (wm) must re-lay out; only the kernel/frame buffer side is checked by `vgpuhw`.
- No real GTK/SDL window drag and no VirtualBox test (VMSVGA driver is a separate worker).
- Resizing in extend mode (multi-head) is not handled by `vgpu.resize` (returns false).
