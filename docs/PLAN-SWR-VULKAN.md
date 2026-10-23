# PLAN-SWR-VULKAN -- software Vulkan on OrientOS (one page, 22.10.2026)

Detail: `docs/GPU-PLAN.md` (options, risks), `docs/GFX-STACK.md` (measurements, Vulkan call list). This page is the short plan.

## State (measured)
- Rasteriser `lib/gpu/swr/{raster,shader,scene}.fi`: fill rule, depth, texture bit-exact, VM = native, 1 = 4 threads; `tools/gfx/run.sh` 10/0.
- SPIR-V `lib/spirv/{parse,validate,lower,spv}.fi`: parser, validator, lowering to SWR bytecode; `tools/spirv/run.sh` 36/0 (glslang + spirv-val cross-check, fuzz, f64 reference).
- Speed (release-fast): 1240x720 textured quad 31.8 ms on 1 core (9.7 ms on 4); 4000 triangles 194.8 ms on 1 core (30.7 ms on 8); shader VM 1.3 ns per op and pixel; lowered SPIR-V 1.7 ns (arithmetic) to 6.8 ns (sin/cos/exp2/log2).
- ICD loading: a 10-function Firn `.so` named `libvulkan.so.1` loads in the Osum loader (`tools/gpu3` 9/0, r1376).

## Gaps
- Rasteriser: no clipping, mip, MSAA, stencil, tile binning (r683). Done 23.10.: scissor, source-over blending (submission order, thread independent), 8-bit bilinear (`lib/gpu/swr/pixel.fi`, `tools/gfx` 21/0).
- Lowering: loops, UBO/push constants, derivatives (2x2 quads) missing (r732, r733); transcendental ops slow (r738).
- No Vulkan API layer (83 functions needed by the Daidalos RHI, GFX-STACK ch. 6), no WSI into `wl_shm` (r1375, r737).
- No guest client has rendered through the ICD yet (r1412).

## Stages
1. **A -- fUi on software Vulkan:** lowering for the fUi shaders (discard + late-Z, vertex stage, 3+ samplers), clipping + blending + bilinear (r1374, r684, r683). Gate: fUi frame through SWR equals the native frame.
2. **B -- API layer + WSI:** Instance/Device/Pipeline/Swapchain as `libvulkan.so.1`, offscreen read-back into `wl_shm` (r737, r1375). Gate: `vulkaninfo`-like client lists the device in the guest.
3. **C -- milestone:** a vkcube-like client renders in the guest, >= 30 fps at 640x480 on 4 cores (r1412).
4. **D -- speed:** Firn SIMD or x86-64 JIT for the VM after measuring the real `mesh.frag`, tile binning, f32 transcendentals (r738, r675). Then compute + storage buffers for wgpu (T2).

## Rules
- Every gate has a counter-proof (variant that bypasses the new code must go red).
- Measure with `--opt-level=release-fast`; default `firnc` checks overflow and is 4x slower.
- Real GPU drivers and VM 3D (VMSVGA/virtio-gpu 3D) stay parked until stage C is green (GPU-PLAN option 2/3).
