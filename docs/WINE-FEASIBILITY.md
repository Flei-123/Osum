# Wine / Proton on Osum: feasibility (20.11.2026)

Method: Wine 11.0 (Alpine 3.24 package, musl, new-WoW64 build: `x86_64-unix`, `x86_64-windows`, `i386-windows`) was read at source level (gitlab.winehq.org master), traced with `strace -f` on Linux (`wine cmd /c echo`) and started inside Osum under QEMU (`tools/linuxapps/wine-gate.sh`, prep: `tools/linuxapps/prep-wine.sh`).

## Result in Osum today (QEMU KVM, main 651a0115f, 20.11.2026)

| step | result |
|---|---|
| `wine --version`, `wineserver --version` | ok |
| prefix (`wineboot --init`, ~800 DLL copies) | ok, ~6.5 min in the guest |
| `wine64 cmd /c echo`, mingw `hello.exe` | ok (E1 green, `tools/linuxapps/wine-gate.sh` 5/5) |
| `wine64 notepad` on wayd (winewayland) | red: `waylanddrv` starts and talks to wayd (optional protocols missing only), but clients get `nodrv_CreateWindow: The explorer process failed to start.` (no `GraphicsDriver`/`DriverError` registry value found, win32u driver.c `load_desktop_driver`); no window ever created (`tools/linuxapps/wine-notepad.sh`, expected red) |

Measurements (this run):
- Prefix prebuilt on the host (`tools/linuxapps/mkprefix.sh`, bwrap, 25 s; 425 MB, 72 MB when 1435 DLLs are symlinks to /usr/lib/wine): does NOT remove the startup cost. `wine64 cmd /c echo` with the prebuilt prefix still needs 217 s (symlinked prefix, console kernel) to 339 s (real files, GUI kernel).
- Profile (`tools/linuxapps/wine-prof.sh`, RIP sampling during that warm start): 69 % of samples are guest idle (`tasks__idle`), 15 % port I/O of which most is the serial trace (`fremdtrace`, `sys: ERR` lines; 14995 failing mmap probes, 6393 readlink EINVAL, 1064 getxattr, 408 ENOENT opens in one start). Startup is wait-bound, not CPU-bound: next step is finding which wait (futex/poll/nanosleep timeouts between wineserver, wineboot, services.exe, explorer) and running without `fremdtrace`.
- A symlinked prefix leaves orphans after a timeout kill that exhaust the 1024-entry open file table (`can't create pipe: Too many open files in system`).

Copy-on-write (r3903, main 4b469aad4): private file mappings that follow a shared object now carry `PAGE_COW` (+`PAGE_COWW` when the mmap asked for write); `mprotect(PROT_WRITE)` and a write fault copy the page (`procspace.cow_write`, `procfault.cow_fault`), read-only private pages still fault. `tools/unterbau/t_cowprivate.c` 17/17 (old main: 3 pass, `mprotect_write` EACCES, then crash).

## What Wine needs (source-verified unless marked)

| area | Wine uses | Osum |
|---|---|---|
| IPC | AF_UNIX stream socket to wineserver, fd passing via `sendmsg`/`recvmsg` SCM_RIGHTS (ntdll/unix/server.c) | present (scmrace gate) |
| wineserver loop | `epoll_create`/`epoll_ctl`, `poll`, `fcntl(F_SETLK/F_GETLK)` file locks (server/fd.c) | present |
| sync | `futex` FUTEX_WAIT/WAKE_PRIVATE; `/dev/ntsync` ioctls when `linux/ntsync.h` exists (sync.c) | futex present; ntsync device missing (optional, Wine falls back to wineserver) |
| foreign process memory | `process_vm_readv/writev`, ptrace fallback (server/ptrace.c) | both present |
| TEB | `arch_prctl(ARCH_SET_GS/GET_GS/SET_FS)` | present |
| signals | SIGSEGV/SIGUSR1/SIGSYS handlers `SA_SIGINFO\|SA_RESTART\|SA_ONSTACK`, `sigaltstack`, `tgkill` | present (not stress-tested with Wine) |
| memory | many `PROT_NONE`+`MAP_NORESERVE` reservations, `MAP_FIXED`/`MAP_FIXED_NOREPLACE`, `MAP_SHARED` file view at fixed 0x7ffe0000, `madvise(DONTNEED)`, `mprotect`, optional `userfaultfd`+`/proc/self/pagemap` | **BLOCKER**: fixed maps only in Osum windows, no fixed file `MAP_SHARED` |
| 32-bit apps (WoW64) | compat-mode code segment, `modify_ldt`/`set_thread_area` for the 32-bit TEB, selectors read at run time (no hard-coded 0x23/0x33) | `set_thread_area`, `modify_ldt` ENOSYS; GDT has user code32 at 0x18, code64 at 0x28 (boot.s) but no compat-mode signal/return path measured |
| graphics | winewayland.drv needs libwayland-client, wayland-egl, EGL, xkbcommon (dlls/winewayland.drv/Makefile.in); Vulkan through the host ICD | `wayd` exists (16 clients); Vulkan ICD exists (tools/vulkan, SWR/lavapipe path); EGL/wayland-egl not verified |
| GPU for games | DXVK (D3D9-11 to Vulkan), VKD3D-Proton (D3D12 to Vulkan) | needs a usable Vulkan driver; today software only (SWR: 31 ms/frame at 1240x720 on 1 core) |

## Blockers, ranked

| # | blocker | effort | note |
|---|---|---|---|
| 1 | Arbitrary fixed mappings below 2 GiB and at the top of the 47-bit space; fixed file `MAP_SHARED` | L (VM layout: per-process VMA table) | every Windows program, even a console `.exe`, needs 0x7ffe0000 (user_shared_data is part of the Windows ABI) |
| 2 | Stable multi-process Wine (wineserver + clients, SMP) | M | scmrace shows 1 flake in 6 runs |
| 3 | 32-bit Windows apps: compat mode, LDT | L | skip for 64-bit-only first |
| 4 | Display: winewayland on wayd (+ EGL or null-GL path) | M | |
| 5 | Vulkan with real GPU for DXVK/VKD3D | L (G-012) | software Vulkan is too slow for games |
| 6 | Steam/Proton: glibc runtime, pressure-vessel (bwrap: user+mount namespaces, `pivot_root`), `futex_waitv` | L | Proton fsync needs `futex_waitv`; ntsync alternative |

## Licences (checked)

| component | licence | source |
|---|---|---|
| Wine | LGPL 2.1 or later | `LICENSE`, `README.md` in wine master |
| DXVK | zlib | GitHub licence API |
| VKD3D-Proton | LGPL 2.1 | GitHub licence API |
| Proton (Valve glue) | BSD-style (`LICENSE.proton`), contained components keep their own licence | `LICENSE`, `LICENSE.proton` in Proton repo |
| Winetricks | LGPL 2.1 | GitHub licence API |

All run as separate user-space programs: no conflict with the GPL-2.0-only kernel; ship as separate package with source offer (LGPL).

## Stages

| stage | goal | needs | status |
|---|---|---|---|
| E0 | Wine loader starts | ELF/musl/libwine | done: `wine --version`, `wineserver --version` green in `wine-gate.sh` |
| E1 | 64-bit console PE (`cmd /c echo`, mingw hello.exe) | blocker 1, prefix creation (wineboot) | done: gate 5/5 green |
| E2 | Notepad (user32/gdi32) | E1, winewayland on wayd, fonts | red: explorer cannot publish the graphics driver (see above); gate `wine-notepad.sh` ready |
| E3 | 32-bit apps + Vulkan/DXVK hello triangle | blockers 3, 5 | assessed, see E3 section |
| E4 | Steam/Proton game | blocker 6 + E3 | open |

ArtCraft: no source in the repo. Web search (20.11.2026) says: Rust + Tauri desktop app (storytold/artcraft), Windows/macOS downloads, Linux built from source; licence information conflicts between sources, backend is a separate repo. A Tauri app on Linux needs WebKitGTK (a Linux-native route, not Wine); the Windows build would need WebView2 under Wine (not assessed).

## E3 assessment (20.11.2026, desk study + repo facts, nothing run)

32-bit (WoW64): Wine 11 new-WoW64 runs 32-bit code inside the 64-bit process (compat-mode far jump). Needed from the kernel: compat-mode user segment (GDT 0x18 exists), 32-bit TEB selector (`modify_ldt`/`set_thread_area`, both in the t_sysall table as not implemented), signal frames for 32-bit context, fixed maps below 4 GiB. Blocker, effort L; none of it measured yet.

Vulkan: DXVK README lists no minimum Vulkan version and no required extensions (needs a recent driver; `VK_EXT_graphics_pipeline_library` optional). vkd3d-proton needs Vulkan 1.3, full descriptor indexing (>= 1,000,000 UpdateAfterBind descriptors), `samplerMirrorClampToEdge`, `shaderDrawParameters`, `VK_EXT_robustness2`, `VK_KHR_push_descriptor`. Our ICD is exercised with API 1.1 (tools/vulkan/client.c) and a 1.3 draw client (tools/vulkan/draw.c, 7 draws against lavapipe); descriptor indexing, robustness2 and push descriptors are not verified. Wine's `winevulkan` also needs `libvulkan.so.1` in the guest (`err:vulkan:vulkan_init_once Failed to load libvulkan.so.1` in the Notepad run) and a WSI surface through winewayland, which does not load yet.

Blockers in order: (1) winewayland driver publish (E2), (2) Wine startup latency (wait-bound, 200-340 s), (3) 32-bit kernel support, (4) libvulkan loader + ICD feature set for vkd3d-proton, (5) real GPU for playable speed.
