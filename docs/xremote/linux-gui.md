# X-Remote: the real FreeViewer GUI on OrientOS (15.11.2026)

Decision (Boss): no own fUi window; the unmodified Linux FreeViewer GUI (eframe 0.33 / egui 0.33) runs through the Linux ABI under wayd, like Firefox.

## Renderer choice
- FreeViewer already picks `eframe::Renderer::Glow` (OpenGL) unless `FV_RENDERER=dx` (wgpu). No code change needed for the GL path.
- wgpu needs a full Vulkan (compute, storage buffers, Wayland WSI): our Firn ICD covers a fUi subset only (docs/GPU-PLAN.md), so it is XL work.
- Chosen: glow + Mesa EGL on the wayland platform with llvmpipe (libgallium + LLVM from the Alpine Firefox root), buffers go through wl_shm. Everything is already in `/root/fxhp/fx-root` (libEGL, libgallium-26.1.6, libLLVM 22, libopus, libasound).

## Build (works)
- `tools/build-gui-musl.sh` in the FreeViewer repo (branch `osum-gui` off `osum-host-only`): `--no-default-features --features gui,osum-native`, target x86_64-unknown-linux-musl, `-crt-static` (dynamic musl, PT_INTERP `/lib/ld-musl-x86_64.so.1`), Alpine sysroot with `alsa-lib-dev opus-dev pkgconf` for pkg-config (`/root/fvsys/root`, hardlink copy of fx-root plus apk add).
- Result: 28.5 MB binary, NEEDED libopus, libasound, libgcc_s, libc.musl. Build ~11 min via heavy.

## Host vs GUI (no two hosts with one ID)
- The GUI already skips its own host when `service::running()` (Windows service); on non-Windows that stub returns false, so on OrientOS the GUI starts its own host and registers the same identity (seen in the run: `host: relay session failed`). Needed: an osum-native `service::running()` that is true while xremoted publishes `/run/xremote.info service=running`, and `published()` taking id/password from the system bus (`settings.get remote.id|remote.password`) because `/run/xremote.info` is root 0600. xremoted stays the only host; the GUI only shows ID/password and connects out.

## Measured in QEMU (tools/xremote/linuxgui.sh, wayd, kernel 772ccf12)
- Loader and binary start; winit connects to wayd and binds compositor/shm/seat/output/xdg_wm_base globals; xkbcommon works.
- Then the process is killed by a signal (`signal: pid=.. SIG? -- killed`) before any xdg_toplevel exists: crash inside EGL/llvmpipe initialisation (libgallium + LLVM 22 JIT). No window yet. Cause not identified.
- Also seen: libopus missing in the Firefox spec (added by `tools/xremote/guestlibs.py`).

## Next
1. Find the signal (kernel log of the signal number, `EGL_PLATFORM=surfaceless` probe, `GALLIUM_DRIVER=softpipe`/`LP_NUM_THREADS=0` to drop LLVM threads, a tiny EGL+GLES C probe with the same libs).
2. osum-native `service::running()` / `published()`; then screenshot gate (window.ppm), connect to a second guest through a local relay, key counters like tools/xremote keytest.
3. Package + start menu entry `X-Remote` + symbol (xfx style), libs in the package.
