# GPU plan: from software rasteriser to a GPU driver (21.10.2026)

Status: **analysis + plan only. No code was written for this plan.** Boss rule: plan first, then build.
Scope: what OrientOS has, what the options cost, in which order to build them, how Firn's host Vulkan backend fits,
and what the Task Manager needs to show GPU columns.

Conventions
- **Measured** = a gate or a run in this repo/session proves it. **Documented** = stated in an existing repo doc.
- **Unverified** = from general knowledge (Mesa, Intel/AMD/NVIDIA, VirtualBox), not checked here. Treat as a question to verify, not as a fact.
- Effort: **S** = days, **M** = 1-2 weeks, **L** = weeks, **XL** = months+. These are judgement labels, not measurements.
- Related docs (not repeated here): `GFX-STACK.md` (SWR spec + Daidalos call list), `LINUX-COMPAT.md` (ways A-E), `GPU-STATUS.md` (2D paths),
  `VIRTIOGPU.md`, `VMSVGA.md`, `RUNDE-GPU3D.md` (why virgl cannot run on the build server), `LAPTOP-HW-FEASIBILITY.md` (L-018).

---

## 1. Current state (evidence)

| Area | State | Evidence |
|---|---|---|
| GPU driver for real hardware | **None.** No i915/AMD/NVIDIA, no KMS, no mode switch, no 3D. Boot framebuffer (UEFI GOP/Limine) only. `kernel/gfx/grafik.fi` prints `treiber=KEINER 3d=KEINES opengl=NEIN vulkan=NEIN`. | `README.md`, `docs/AUFSETZEN.md`, `grafik.fi:577` |
| Display paths in VMs | virtio-gpu 2D (`kernel/drv/gpu/vgpu.fi`, 2260 lines): dirty-rect flush, cursor queue, EDID per head, mirror/extend. VMSVGA (`vmsvga.fi`, 1655 lines): FIFO UPDATE rects, cursor, host resize hints. Bochs VBE fallback. | `docs/GPU-STATUS.md`; gates `tools/vgpuhw`, `vgpuheads` 17/0, `vgpuext` 22/0, `vmsvga` 46/0, `vmsvgaresize` 31/0 |
| 3D in VMs | **Not used.** `vmsvga.fi` knows no `CAP_3D` / GMR / SVGA3D (grep: only RECT_COPY, CURSOR, EXTENDED_FIFO, DISPLAY_TOPOLOGY caps). virtio-gpu: 2D commands only. virgl cannot even start on the build server (QEMU 7.2.22 built without OpenGL, no `/dev/dri`, host is an LXC container). | `RUNDE-GPU3D.md` section 1 (9 probes, all negative) |
| Software rasteriser (SWR) | `lib/gpu/swr/{raster,shader,scene}.fi` (974 lines): 1/16-pixel fixed point edges, top-left rule, perspective-correct attributes, Early-Z, nearest texture, 16-row bands on `jobs.parallel_for`. Gate `tools/gfx/run.sh`: **10 ok / 0 fail (re-run 21.10.2026)**. | `GFX-STACK.md` section 3 |
| SWR speed | 1240x720, 1 core, textured quad (0.89 Mpx): **31.8 ms/frame** native, 34.7 ms with shader VM; 4 cores 9.7 ms. 4000 random triangles (3.1 Mpx): 194.8 ms on 1 core, 30.7 ms on 8. Scaling 1 to 8 cores 3.1x-6.3x. | project metrics, `GFX-STACK.md` |
| Shader VM cost | MAD chain **1.3 ns** per op and pixel (goal <0.5 with SIMD/JIT). SPIR-V-lowered programs **1.7 ns** (arithmetic/branch) to **6.8 ns** (with sin/cos/exp2/log2 via f64 libm) per instruction and pixel (release-fast, 320x200, 1 core). The 21.10. gate run printed 12-14 ns because it builds with the default (overflow-checked) opt level on a loaded host; not comparable. | project metrics; `tools/spirv/run.sh` output |
| SPIR-V front-end | `lib/spirv/{parse,validate,lower,spv}.fi` (2720 lines): parser, validator, lowering to the SWR VM. Gate `tools/spirv/run.sh`: **36 ok / 0 fail (re-run 21.10.2026)**: glslang modules validate and lower, VM program == hand-written program bit-identical, f64 reference match (63/63 pixels within 3/255), fuzz 3000 mutations/shader + 2000 random buffers with no crash and none accepted. | gate output |
| **SPIR-V lowering limits** | **Fragment stage only** (`L_STAGE`). No uniform blocks / push constants / SSBO (`L_UNSUPPORTED`), **no loops, no discard (OpKill), no function calls**, no switch, ONE bound texture, no derivatives. If-conversion only. | header of `lib/spirv/lower.fi`; test shaders `nolower_{discard,loop,ubo}.frag` |
| SWR limits | No clipping (w<=0 dropped), scissor, blending, stencil, MSAA, mip/bilinear, index buffers, tile binning, late-Z, float targets. | `GFX-STACK.md` section 4 |
| Wayland | `wayd` (Ring 3): wl_compositor, wl_shm (memfd + SCM_RIGHTS), xdg_shell, seat, output. Gates `tools/wayland/run.sh` 52/0, `input.sh` 73/0, `foot.sh` 12/0. **No linux-dmabuf, no DRM** (`/dev/dri` missing). GPU clients can only present through `wl_shm`. | `LINUX-COMPAT.md`, KNOWLEDGE.md (21.10.) |
| Linux ABI under it | Unterbau suite 710 PASS / 3 FAIL / 4 GAP of 717 (main 280e1fa6); dynlader 35/1 (`dlopen` of foreign `.so` works: `t_dl` 18/0). foot runs; GTK4 16/3; Firefox blocked by the 130 MiB file limit (r1366). | project metrics |
| Vulkan loader / ICD on OrientOS | **None.** No `libvulkan.so.1`, no ICD json, no `vk_icd*` entry points. Nothing in the repo exports Vulkan. | grep for "vulkan" in `kernel/`, `lib/`, `tools/`: only comments, the validator and a test script |
| Task Manager | Pages CPU, memory, disk, network, Bench. Sources: `SYS_PMON` (1830, process names), `SYS_PSTAT` (per-process), `SYS_CPUSTAT` (1840, per core), `SYS_SYSINFO`, `SYS_NETMON` (1320), `/proc/bench`. **No GPU page, no GPU source in the kernel.** | `kernel/user/taskmgr.fi` |

### Firn side (host, not OrientOS)
- Firn has a complete **Vulkan client**: `lib/gpu/vk.fi` (1642 lines), `vk_*.fi`, `vkplat.fi` and the fUi backend `lib/fui/gpu_vk.fi` (1963 lines).
  It loads the loader at run time with `dynlib.open("libvulkan.so.1")` (fallback `libvulkan.so`; `FIRN_VK_LIB` overrides the name). It never links Vulkan statically.
- Measured on the host (`docs/fui-gpu-path.md` in the Firn repo): Iris Xe laptop, 1920x1080 hello frame, CPU painter 11.9 ms, GL 1.0-1.4 ms, **Vulkan present 1.8 ms**, Vulkan read-back 16.5 ms.
  lavapipe (CPU Vulkan) 1080p page: **61 ms** vs CPU painter 30-35 ms (after the one-command-buffer-per-frame fix, 7244 to 121 submits). **A real GPU timing of the fUi page is untested.**
- Parity gate `tools/fui/gpuparity.sh`: CPU vs Vulkan (lavapipe) mean error 0.005, max 11 (without text). Validation layer clean (W42-b).
- Firn can build C-ABI `.so` files (`firnc --pic -c` + `ld -shared`; gate 134, 12 checks from C and Python), including v128 SIMD. So an ICD written in Firn is possible **on Linux**. Untested: loading such a `.so` on OrientOS.
- The fUi fragment shader (`lib/fui/gpu_fs.glsl`, 303 lines) uses `discard` (many places), a `for` loop, a `uniform vec4[8]` array and three samplers. **Today's SPIR-V lowering cannot run it** (no discard, no loops, no UBO arrays, one texture). The Vulkan SPIR-V variant (`spv/gpu_vk.frag.spv`) was not disassembled here; assume the same features.
- The window layer of the Vulkan backend creates **X11** surfaces (xlib/xcb, `vkplat.fi`). OrientOS has no X11. Two ways: add a Wayland-surface variant, or render offscreen and use the existing **read-back** path (no WSI needed, 16.5 ms at 1080p on Iris Xe, copy into a `wl_shm` buffer).

### Not known / not measured
- Whether `firnc`-built `.so` files load and run in the OrientOS dynamic loader (dynlader gate has 1 open failure; Firn `.so` case never run there).
- lavapipe baseline on this server for Daidalos shaders (r673 asked for it first).
- Real-GPU behaviour of anything above. The Dell was offline at the last measurement; no OrientOS run on Intel graphics exists.
- Which GPUs the owner's machines really have (see section 3: only facts from repo docs and the task brief are used).

---

## 2. Options

### Option 1: software Vulkan on OrientOS (SPIR-V to SWR, "lavapipe in Firn")
What: a `libvulkan.so.1` (Firn `.so`) that implements a Vulkan subset on SWR. The first target is the call list the host fUi backend and Daidalos need
(`GFX-STACK.md` section 6: 83 functions, 81 without Win32/Xlib, Vulkan 1.3 dynamic rendering + sync2). Firn's host backend then runs **unchanged** because it only needs `libvulkan.so.1` to exist.
Shortcut: ship the implementation **as** `libvulkan.so.1` (monolithic ICD, no separate loader). A real Vulkan loader + ICD json for third-party apps (wgpu, vulkaninfo) comes later (loader is Apache-2.0, could be reused, **unverified** that it builds on OrientOS).

Pieces and effort (S/M/L/XL):
| Piece | Effort | Notes |
|---|---|---|
| Entry-point table, instance/device/queue/memory/buffer/image objects (CPU memory, one queue) | M | pure bookkeeping; call list known |
| Command recording + submit executor (draw, barrier, copy, blit, dynamic rendering) | M | barriers can be no-ops at first (single executor) |
| Pipeline state to SWR state (blend, scissor, clip, depth func, cull) | M | needs SWR gaps: clipping, blending, scissor |
| SPIR-V **vertex** stage lowering + attribute fetch | M | not present at all today |
| Lowering gaps for fUi shaders: **discard + late-Z**, loops (unroll), UBO/push-constant arrays, 3+ samplers | L | SPIR-V work is the bulk; discard and loops change the "straight-line VM" model (header of `lower.fi`) |
| Descriptor sets, samplers (bilinear, repeat/clamp), image formats | M | |
| WSI: present via offscreen read-back + `wl_shm`, or VK_KHR_wayland_surface | S-M | read-back path already exists in Firn |
| Daidalos mesh/PBR shaders (2087 ops, 4 loops, 1 kill, 11 image reads) | L | speed risk: estimate ~1 s/frame at 0.9 Mpx on 1 core (unmeasured estimate from `GFX-STACK.md`) until SIMD/JIT |
| Compute (wgpu/eframe), storage buffers, derivatives | L-XL | later; not needed for fUi or Daidalos RHI |
| Performance: SIMD (v128 f32) or JIT for the VM | L | goal VM cost <0.5 ns/op/pixel |

Value: **real, immediate, testable in QEMU/KVM today** (no GPU needed). It makes Firn's fUi Vulkan path, Daidalos and later wgpu apps run.
Honest limit: it is **a CPU**. lavapipe on the host was slower than the CPU painter for fUi (61 vs 30-35 ms). The gain is compatibility and a correct reference, not speed. It is also the **front-end reused by any hardware backend** (Option 3).
Total: **L** for fUi/Daidalos subset, **XL** with compute + GL.

### Option 2: 3D in VMs (VMSVGA / virtio-gpu 3D)
What: use the host GPU through the hypervisor's paravirtual 3D.
- **VMSVGA SVGA3D (VirtualBox):** driver would need `CAP_3D`, GMR memory objects, the SVGA3D command set over the FIFO, and a guest renderer that emits those commands (no Mesa on OrientOS). Whether the owner's VirtualBox build has the 3D backend enabled, and which host API it uses, is **unverified**.
- **virtio-gpu 3D (virgl / Venus):** needs host QEMU with OpenGL and a render node. Measured **not possible on the build server** (`RUNDE-GPU3D.md`). Guest side also needs a command encoder (virgl = Gallium/GL; Venus = Vulkan, **unverified** version/host requirements).
Effort: **L** each, plus a guest-side renderer that does not exist. Test coverage: only on the owner's laptop (VirtualBox), where host load is forbidden by project rules; QEMU path blocked here.
Value: low now. It accelerates VMs only; it does not help the real Dell/laptop goal; and it needs the Option-1 front-end (or Mesa) to produce commands anyway.
Decision: **park.** Re-evaluate when Option 1 works and the laptop VirtualBox 3D support is measured.

### Option 3: real hardware
**3a. Intel (HD 4600 / Haswell, Gen7.5; later Gen9+, Iris Xe Gen12).** The owner's Dell OptiPlex 9020 is the reference box (task brief: Haswell HD 4600, Intel PRM available; **not verified on the device**; no GPU PCI ID is recorded in the repo docs). Iris Xe is the owner's laptop (Firn doc); whether OrientOS ever ran natively on it is not recorded.
Work packages (Gen7.5 knowledge below is **unverified, from memory; check each item against the PRM volumes before relying on it**):
| Step | Effort | Notes |
|---|---|---|
| H0 identify: PCI ID, BARs (MMIO + aperture), stolen memory size, GGC/GTT size | S | read-only probe, no risk |
| H1 display-only KMS: GMBUS/DDC EDID, pipes/planes/transcoders/PLL/DDI, eDP power + backlight, hot-plug | L | already roadmapped as L-018 / r772 |
| H2 memory manager: global GTT (and PPGTT), page tables, cache/coherency, fences, GEM-like buffer objects | L | OrientOS Ring 0/Ring 3 split decides where it lives |
| H3 command submission: render ring buffer, hardware context, batch buffers, seqno/interrupts, hang recovery/reset | L | Gen7.5 is ring-based (execlists/GuC arrive later; **unverified**) |
| H4 3D pipeline state: 3DSTATE_* packets, binding tables, surface/sampler state, vertex fetch, URB/thread setup, PS/VS dispatch | L | |
| H5 shader compiler: SPIR-V (or the SWR IR) to the Intel EU ISA (SIMD8/16 kernels, register allocation, send messages for sampler/memory) | **XL** | biggest single item; PRM EU ISA volume is the reference |
| H6 Vulkan front-end on the HW backend (reuse Option 1 objects, replace executor) | M | only after Option 1 |
No Haswell GuC/HuC firmware blob is expected (**unverified**); Gen9+/Gen12 need display and GuC/HuC firmware (licensing and loading unknown).
Total for a working accelerated Vulkan on Haswell: **XL**, years of effort by the project's own LINUX-COMPAT estimate. Without the shader compiler, hardware only gives display (H1) and maybe fixed-function blits.
Mesa alternative (unverified): crocus (GL) / hasvk (Vulkan) for Haswell, iris/anv for Gen8+. They need `/dev/dri` + libdrm ioctls + an i915-compatible kernel side (LINUX-COMPAT ways B/D, XL) and a working C++ runtime and threads.

**3b. AMD.** amdgpu is hundreds of thousands of lines plus mandatory firmware (PSP, SMU, DMCUB); `LAPTOP-HW-FEASIBILITY.md` says "not realistic". Effort **XL+**. Not planned.
**3c. NVIDIA** (the owner's desktop has a GA106 per `DAILY-DRIVER.md` A4). Modern NVIDIA needs signed firmware loaded through a vendor-controlled path; open documentation of the compute/graphics engines is incomplete (**unverified**, general knowledge). Effort **XL+, practically not feasible**. Not planned.

---

## 3. Recommended order

1. **Option 1, stage A (M-L): "fUi on software Vulkan".**
   Goals in order: (a) SWR gaps for the fUi pipeline (clipping, blend, scissor, discard/late-Z); (b) SPIR-V vertex stage + the lowering gaps listed above; (c) `libvulkan.so.1` as a Firn `.so` with the 83-function subset; (d) WSI by offscreen read-back into `wl_shm`; (e) gate in QEMU: `vulkaninfo`-like smoke, fUi zoo page on OrientOS == host lavapipe image (reuse `gpuparity` idea), then Daidalos `ui.frag` etc. in the order of `GFX-STACK.md` section 6.
   Why first: it is the only step that is testable on the build server, it exercises the dynamic loader / Firn `.so` question, and every later hardware backend reuses the front-end.
2. **Metrics interface (S): `/proc/gpu`** (section 5). Cheap, independent, gives the Task Manager a truthful "GPU: software, N %" before any hardware driver exists.
3. **Intel H0 probe (S) then H1 display-only KMS (L)** on the Dell: gives real mode setting/multi-monitor (G-007/L-018) and finds out the real PCI IDs, GTT size and stolen memory. No rendering yet.
4. **Option 1, stage B (L): performance** (SIMD/JIT for the shader VM, tile binning, 4-8 core scaling) so that the software path is usable for real apps; compute + storage buffers for wgpu.
5. **Intel H2-H6 (XL)** only if (1)-(4) are green and the owner still wants hardware rendering. Decide at that point whether the EU compiler is built from scratch or an existing compiler is ported (the latter needs a C++ runtime on OrientOS, unknown).
6. **VM 3D (Option 2)** and AMD/NVIDIA: parked / not planned.

Reasoning for not starting hardware first: with no GPU in the build server there is no way to test it here (as `VIRTIOGPU.md` and `RUNDE-GPU3D.md` already concluded); the Dell is not always online; without the Option-1 front-end the hardware path would have no API on top.

---

## 4. How Firn's existing host Vulkan backend fits

- **Same code, new runtime.** The backend (`lib/gpu/vk*.fi`, `lib/fui/gpu_vk.fi`) calls only the public Vulkan C API through `libvulkan.so.1`. Option 1 provides that name on OrientOS; the backend needs no change except the surface layer.
- **Surface layer (`vkplat.fi`):** add an OrientOS/Wayland variant, or select the read-back path (`FUI_GPU` policy already supports "Vulkan first, any device" and read-back; software devices are accepted with `FUI_GPU=1`, refused with `vk`). Without this the backend asks for xlib/xcb extensions and falls back to the CPU painter. The fallback chain (`lib/plat/gpuchain.fi`) is already tested and keeps the desktop alive if the ICD fails.
- **Test oracle:** lavapipe on the Linux host renders the same SPIR-V; its output is the reference for the OrientOS software ICD (same method as the host parity gate, mean 0.005 / max 11).
- **Validation:** the backend's opt-in validation layer run (`FUI_GPU_VALIDATE=1`, W42-b) gives conformance feedback for the new ICD without a conformance suite. Not a full CTS run (none exists here).
- **Hardware later:** the backend never sees the difference between software ICD and a Gen7.5 backend. Real-GPU timing of the fUi page is still **untested even on the host** (only lavapipe, plus Iris Xe hello-frame numbers).
- **Open:** the fUi shaders must lower (discard, loop, UBO array, 3 samplers) or be rewritten to a simpler variant for the software ICD. Rewriting the shader for the software path is a fast stopgap (S) but forks the shader sources.

---

## 5. Task Manager GPU columns: what is needed

Today there is no GPU data source at all. Honest definition per backend (what can be known without a hardware engine):

| Backend | Utilisation (per mille) | VRAM total / used | Notes |
|---|---|---|---|
| Boot LFB / Bochs VBE | none (`n/a`) | LFB size / back-buffer bytes | no engine |
| virtio-gpu 2D | none (host side is invisible); show present rate and bytes/frame (already counted) | `n/a` (host memory) | |
| VMSVGA | none; `VRAM_SIZE` register is known (`S_VRAMSZ`) | `VRAM_SIZE` / back-buffer bytes | FIFO busy flag exists but means "host not done", not load |
| SWR software ICD | CPU time of rasteriser jobs / wall time x cores (honest label "software") | system RAM used by Vulkan objects | measurable from `jobs` workers |
| Intel Gen7.5 (future) | render ring busy time: seqno wait vs idle, or RC6 residency counters (**unverified**, check PRM) | shared system memory: GTT size / bound pages | no dedicated VRAM; stolen memory is fixed |

**Proposed interface (stub-free, text like `/proc/bench`; not built):**
```
/proc/gpu                      one `key value` per line, integers only (same parser as the Bench page)
  gpu.count 1
  gpu0.kind 0|1|2|3            0 framebuffer only, 1 paravirtual (virtio-gpu/VMSVGA), 2 software ICD, 3 hardware
  gpu0.name <token>            fb | virtio | vmsvga | swr | gen7
  gpu0.util_pm -1..1000        per mille busy over the last window; -1 = not measurable (kind 0/1)
  gpu0.util_src 0..3           0 unknown, 1 engine counter, 2 software CPU time, 3 ring busy
  gpu0.vram_total_bytes 0|N    0 = not applicable
  gpu0.vram_used_bytes  N
  gpu0.frames N                presented frames since boot
  gpu0.present_bytes N         bytes transferred to the display since boot
  gpu0.hw_cursor 0|1
per process (later): sys PMON kind 3 -> per-process GPU time in ns, same slot as the name/CPU queries
```
Rules for the Task Manager: show **"n/a" (muted)** for `-1`/`0`, never `0 %`; label software utilisation as such; read via the existing `/proc/...` text path so no new syscall is needed for the first version; per-process GPU needs the kernel (or the ICD in Ring 3) to attribute busy time to a pid, which only exists once Option 1 or a hardware driver exists.
Effort: kernel `procfs` node (S) + Task Manager page (S) + gate (S). It can ship before any rendering backend, because the paravirtual paths already hold the numbers.

---

## 6. Risks and open questions
- **R1** `firnc` `.so` loaded by the OrientOS dynamic loader: unproven. Test early (a 10-function dummy ICD in Step 1a is enough). Gate `tools/dynlader` has 1 open failure.
- **R2** SPIR-V model change: discard and loops break the straight-line, if-converted VM. Needs a VM with per-lane masks and loop support, or an unroller (r733).
- **R3** Speed: software Vulkan can be slower than the existing CPU painter for 2D UI (lavapipe: 61 vs 30-35 ms at 1080p). It must stay an opt-in/compat path until measured otherwise.
- **R4** The build server has no GPU and no DRM; hardware work needs the Dell online (and Haswell identity confirmed) or the laptop (no host load allowed).
- **R5** Hardware facts in section 2/3a are from memory, not from the PRM. First task of H0 is to confirm them against the documents.
- **R6** Licensing: Mesa and Vulkan-Loader (MIT/Apache) are compatible with the GPL-2.0-only kernel (LINUX-COMPAT); firmware blobs (Intel GuC/HuC/DMC, AMD, NVIDIA) are a separate question.

## 7. Roadmap items (see the project roadmap; existing items reused, not duplicated)
Already there: r36 (G-012 no GPU driver), r33 (vsync), r38 (QEMU OpenGL), r502 (Wayland W5 GPU/EGL), r669 (Mesa software), r673/r675/r682-r685/r732/r733/r737/r738 (Weg E: Vulkan subset, SPIR-V, SWR gaps, UBO, loops, API layer), r772 (L-018 Intel/AMD KMS), r954-r971 (VMSVGA).
Added by this plan: discard + multi-texture + vertex-stage lowering; Vulkan WSI/surface for OrientOS (read-back or Wayland); `/proc/gpu` + Task Manager GPU page; Intel Gen7.5 H0 probe + PRM verification; VM-3D decision (parked); dummy-ICD loadability test (R1).
