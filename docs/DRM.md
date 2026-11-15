# DRM: one GPU interface for Osum (state 15.11.2026, w-drm43)

Goal: one Linux-DRM-uAPI-compatible kernel DRM layer (`kernel/gfx/drm/`). Native Osum drivers AND the linuxkpi shim
(`compat/linuxkpi/`) register as backends of the same layer; libdrm/Mesa talk to `/dev/dri/card0` + `/dev/dri/renderD128`
with the standard ioctls. No second DRM implementation.

## 1. What already exists (read 15.11., not built in this round)
| Part | Where | State |
|---|---|---|
| linuxkpi shim, kernel-internal DRM for the driver | `compat/linuxkpi/shim/src/drm_core.c` (dev alloc/register/put), `drm_kms.c` (connector, modes, simple pipe, atomic check/commit, EDID), `drm_vram.c` (8 VRAM GEM objects, fb_create, XRGB/BGRX), `drm_fbdev.c` (in-module boot client: dumb buffer, fb, commit, paints 4-colour test picture), `pci.c`, `heap.c`, `printk.c`, `resource.c`, `string.c` (1543 lines C) | works for unmodified `bochs.c` (Linux 6.12.101, fetched + sha256-pinned, never in repo) |
| Shim to kernel seam | `compat/linuxkpi/shim/include/osum/osum_if.h`: `k_abi k_puts k_pcicfg_read k_pcicfg_write k_pcibar k_ioremap k_frames k_frames_free` | NO display/KMS export: the picture is painted by the shim itself, the kernel never sees the shim's framebuffer |
| Build / package / gates | `compat/linuxkpi/{fetch.sh,sources.tsv,build.sh,closure.py,pack.sh,hostbuild.sh,hosttest/,run.sh,gate.sh}`; tiers `native`/`compat` (`docs/DRIVER-TIERS.md`, `tools/tiers/run.sh`) | `run.sh`: QEMU bochs-display, tiers native+compat, screendump pixel-exact, unload/reload, counter-proofs |
| Display class (output only) | `kernel/gfx/displayclass.fi` `DisplayOps` (ready, present, panic_present, frames, vram, hw_cursor; kinds FB/VGPU/VMSVGA) | used by `gfx.fi`; no modes, no buffers, no clients |
| Native display drivers | `kernel/gfx/vmode.fi` + `fb/` (bochs VBE / GOP), `kernel/drv/gpu/vgpu.fi` (virtio-gpu 2D), `vmsvga.fi`, `drv/gpu/intel/` (igmode/igflip/igflush, HP HD 620 plane flip) | each talks to `gfx`/`fb` directly; none exposes KMS objects |
| 3D experiments | `kernel/drv/gpu/vgpu3d*.fi` (virgl capset/context/clear/draw, kernel-internal), `lib/vulkan/*.fi` (Firn software Vulkan on SWR), `tools/gpu3d` | not reachable through any device node |
| Userspace uAPI | none: no `/dev/dri`, no DRM ioctls, no GEM handles, no PRIME, no syncobj (t_procfs reports `path_dev_dri` GAP) | to build (section 3) |

## 2. Kernel seams found (where the new layer plugs in)
- **ioctl:** `kernel/sys/sys.fi` around line 1643: `SYS_IOCTL` goes to `sysioctl.owns/do_ioctl`, else `systerm.do_ioctl`. Add one route before systerm: file kind `K_DRM` -> `drm.drmioctl.dispatch`.
- **open:** `kernel/sys/sysfd.fi` FS_DEV branch (next to `devfs.is_fb` / `open_devfb`): `/dev/dri/*` -> `open_devdri` allocating `file.K_DRM` (new kind in `kernel/fs/file.fi`, ino = DRM client id, low bit = render minor).
- **mmap:** `kernel/sys/sysmem.fi` `map_fd`: `K_DRM` -> fake offset -> GEM object -> `map_shm_obj(state, me, shm, wok, len, prot)` (existing; same path as memfd). GEM pages = existing shm objects (`unixsock.shm_new_any/shm_grow/shm_set_size/shm_frame/shm_unref`), so no new allocator.
- **close:** `file.open_teardown` cannot import the DRM layer (cycle: `unixsock` imports `file`). Plan: leaf module `drm/drmgone.fi` (imports only `sync.atomic`) gets the closed client id from teardown; the DRM layer reaps GEM objects/fbs of gone clients at the next DRM call/open.
- **devfs:** `kernel/fs/devfs.fi` is 956 lines (if-chain of names). Put `/dev/dri` naming in a new `kernel/fs/devdri.fi` (lookup `dri`, `dri/card0`, `dri/renderD128`, readdir, attr N_CHR, `st_rdev` = makedev(226,0) / makedev(226,128) = `0xE200` / `0xE280` so libdrm's major check works). devfs readdir loop bound `node > D_KMSG` must become `node > D_LAST`.
- **locking:** run handlers under `sync.fslock.enter/leave` (nestable L_FS) until the fd/handle SMP race fix (r3684, `kernel/sync/fdlock.fi`) lands.

## 3. Stage 1 cut (one layer, backends registered)
Module layout `kernel/gfx/drm/` (built, repo licence GPL-2.0-only until the Boss decides):
| File | Job |
|---|---|
| `drmuapi.fi` | ioctl numbers ('d' = 0x64, nr), caps, struct offsets (below) |
| `drmioctl.fi` | dispatch: type check, `size = (req>>16)&0x3FFF`, copy_in if dir&1, handler by nr, copy_out if dir&2 (like Linux `drm_ioctl`) |
| `drmcore.fi` | VERSION, GET_UNIQUE, GET_CAP, SET_CLIENT_CAP, SET/DROP_MASTER |
| `drmclient.fi` + `drmgone.fi` | client ids, minor, reap |
| `drmgem.fi` | handle table -> shm object, size, fake mmap offset, CREATE/MAP/DESTROY_DUMB, GEM_CLOSE |
| `drmfb.fi` | ADDFB, ADDFB2 (XR24/AR24), RMFB, DIRTYFB |
| `kmsobj.fi` | GETRESOURCES, GETCONNECTOR, GETENCODER |
| `kmscrtc.fi` | GETCRTC, SETCRTC, PAGE_FLIP (no event yet: flag 1 -> EOPNOTSUPP), DIRTYFB, fb_gone |
| `kmsmode.fi` | modeinfo of the active backend (fake blanking, 60 Hz) |
| `kmsreg.fi` | `KmsOps` registry (`ready, width, height, refresh, scanout(shm, w, h, pitch), release, tag`), 4 slots, last ready backend wins |
| `kmsgfx.fi` | backend for every display `gfx` drives (vmode/bochs, virtio-gpu, vmsvga): scanout = copy GEM rows into `gfx.fb_draw_at` + `dirty_all` + `flush`; first scanout turns the console echo off, `release` restores it. Registered lazily at the first DRM open |
| later: `prime.fi`, `syncobj.fi`, `syncfile.fi` | PRIME fd<->handle (dma-buf as shm fd), syncobj binary + timeline, sync_file |

Shim reuse (no second DRM): add kernel exports `k_kms_register(ops)` / `k_kms_unregister` to `osum_if.h` + `kernel/lib/ksym.fi`. The shim's `drm_dev_register` registers its `drm_device` as a `KmsOps` backend whose dumb_create/fb_create/atomic_commit are the existing `drm_vram.c`/`drm_kms.c` functions; `drm_fbdev.c` stays the boot client only when no userspace master exists. Native backends (`kmsgfx`, later true per-driver KMS for vgpu/vmsvga/intel) register the same struct.

### uAPI struct layouts (x86_64, from Linux include/uapi/drm, byte offsets)
- `drm_version` (0x00, 64): ints major 0, minor 4, patch 8; name_len 16, name 24, date_len 32, date 40, desc_len 48, desc 56.
- `drm_get_cap` (0x0C, 16): capability 0, value 8. Caps: DUMB_BUFFER 1, DUMB_PREFERRED_DEPTH 3, DUMB_PREFER_SHADOW 4, PRIME 5, TIMESTAMP_MONOTONIC 6, ADDFB2_MODIFIERS 0x10, CRTC_IN_VBLANK_EVENT 0x12, SYNCOBJ 0x13, SYNCOBJ_TIMELINE 0x14.
- `drm_set_client_cap` (0x0D, 16); `drm_gem_close` (0x09, 8): handle 0.
- `drm_mode_card_res` (0xA0, 64): fb/crtc/connector/encoder ptrs 0/8/16/24; counts 32/36/40/44; min_w 48, max_w 52, min_h 56, max_h 60.
- `drm_mode_crtc` (0xA1 get, 0xA2 set, 104): set_connectors_ptr 0, count_connectors 8, crtc_id 12, fb_id 16, x 20, y 24, gamma_size 28, mode_valid 32, mode 36.
- `drm_mode_modeinfo` (68): clock 0; u16 hdisplay 4, hsync_start 6, hsync_end 8, htotal 10, hskew 12, vdisplay 14, vsync_start 16, vsync_end 18, vtotal 20, vscan 22; vrefresh 24, flags 28, type 32, name[32] 36.
- `drm_mode_get_encoder` (0xA6, 20): id 0, type 4, crtc_id 8, possible_crtcs 12, possible_clones 16.
- `drm_mode_get_connector` (0xA7, 80): encoders/modes/props/prop_values ptrs 0/8/16/24; count_modes 32, count_props 36, count_encoders 40, encoder_id 44, connector_id 48, type 52, type_id 56, connection 60, mm_w 64, mm_h 68, subpixel 72.
- `drm_mode_fb_cmd` (0xAE, 28): fb_id, width, height, pitch, bpp, depth, handle. RMFB 0xAF (u32).
- `drm_mode_crtc_page_flip` (0xB0, 24): crtc_id, fb_id, flags, reserved, user_data 16. `drm_mode_fb_dirty_cmd` (0xB1, 24).
- `drm_mode_create_dumb` (0xB2, 32): height 0, width 4, bpp 8, flags 12, handle 16, pitch 20, size 24. MAP_DUMB 0xB3 (16): handle 0, offset 8. DESTROY_DUMB 0xB4 (4).
- `drm_mode_fb_cmd2` (0xB8, 104): fb_id 0, width 4, height 8, pixel_format 12, flags 16, handles 20, pitches 36, offsets 52, modifier 72.
- Object ids share one namespace: plan connector 0x30, encoder 0x31, crtc 0x32, primary plane 0x33, fbs from 0x100.

## 4. Gates (planned)
- `tools/drm/run.sh`: musl C test in the unterbau harness (`tools/unterbau/image.sh` build_image/boot) + QEMU monitor screendump: VERSION, GET_CAP, GETRESOURCES, CREATE/MAP_DUMB, mmap + fill, ADDFB2, SETCRTC -> screendump pixel check; mutants: SETCRTC skipped = no picture, wrong mmap offset refused, closed fd reaps handles. Later libdrm `modetest` (musl) when libdrm is packaged.
- Stage 2 with the shim backend: `compat/linuxkpi/run.sh` extended: same C test against lkpi-bochs (compat tier) and the native backend (no package).

## 5. Status
- Stage 1 built (w-drm43, branch staff/orientos-mwi6u6t9): modules above + `kernel/fs/devdri.fi`; seams: `file.K_DRM` (29) + teardown -> `drmgone.mark`, devfs lookup/readdir/attr (`/dev/dri` dir, rdev 226:0 / 226:128), `sysfd.open_devdri`, `sys.fi` ioctl route by file kind, `sysmem.map_drm` -> `map_shm_obj`. Handlers run under `fslock`.
- Gate `tools/drm/run.sh` (static musl `t_drm.c`, `-append gfx`, screendump quadrants): 25/0 incl. counter-proofs (no SETCRTC = no picture, render node refused, closed fd reaps handles, bad mmap offset refused).
- Not yet: fstat of the DRM fd has no rdev (libdrm checks it), no fb listing in GETRESOURCES, no vblank/flip events, no planes/properties/atomic, the kernel desktop is not paused when a master scans out (only the console echo), shim not registered (r3726: Firn fn values vs C function pointers need a C-ABI trampoline in ksym).
