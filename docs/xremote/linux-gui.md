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

## Signal found and fixed (kernel)
- The kill was SIGSYNCCALL (musl, signal 34), not EGL: the first `membarrier(PRIVATE_EXPEDITED)` returns EINVAL, musl falls back to `__synccall`, installs a SIGSYNCCALL handler with `sigaction` in one thread and `tgkill`s every sibling. Our kernel kept one handler table per task (copied at `clone`), so siblings still had SIG_DFL and the default action killed the whole group.
- Fix: `signal.do_sigaction` writes the new action into every live task of the thread group (`share_action`, kernel/sched/signal.fi). Gate: `tools/unterbau/t_sigshare.c` (handler installed after the thread started runs in the sibling; counter-proof on the old kernel in fixed.txt).
- `membarrier` itself stays EINVAL on purpose: musl then takes the signal path, which is a real barrier on all cores.

## Gate (tools/xremote/linuxgui.sh)
- QEMU, wayd, real FreeViewer GUI: `wayd: window` marker, no signal/fault after `FVGUI start`, `screendump` after FVGUI_PAINTWAIT, pixel check in the window rectangle (dark panel share, blue accent pixels) by `linuxgui_check.py`.
- `FVGUI_SERVICE=1`: guest runs orientbus + settingsd + a fake `/run/xremote.info|state` (service=running, id=123456789); the check OCRs the window (tesseract) for the ID and asserts the GUI did not start its own host.
- Needs: `KERNEL=<k0.img>`, `FVGUI_LIBS="$(cat /root/fvsys/extra.txt)"` (Mesa libs missing from the Firefox spec), WD `/root/fxhp`.

## osum-native service (FreeViewer branch osum-gui)
- `src/osum/xhost.rs`: `service::running()` is true while `settings.get remote.service` answers `running`; `published()` returns `remote.id` / `remote.password` from the system bus (`/bin/act call settings.get key=...`, because `/run/xremote.info` is root 0600). A background thread refreshes a cache every 3 s so the UI thread never forks. xremoted stays the only host.

## Package size
- Libs in the guest: libLLVM 183 MB (zstd -3: 66 MB), libgallium 42 MB (13 MB); libgallium NEEDs libLLVM even for softpipe, so LLVM cannot be dropped without a Mesa rebuild.
- In the test image Firefox and the GUI already share ONE copy (`/usr/lib` of the Alpine root). For the Store: ship Mesa as one shared runtime package (`/apps/mesa.osp/lib`, loaded through LD_LIBRARY_PATH) that both Firefox and X-Remote GUI use, instead of two copies. The package system has no dependency field yet (roadmap).
