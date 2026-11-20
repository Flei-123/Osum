# Wine / Proton on Osum: feasibility (20.11.2026)

Method: Wine 11.0 (Alpine 3.24 package, musl, new-WoW64 build: `x86_64-unix`, `x86_64-windows`, `i386-windows`) was read at source level (gitlab.winehq.org master), traced with `strace -f` on Linux (`wine cmd /c echo`) and started inside Osum under QEMU (`tools/linuxapps/wine-gate.sh`, prep: `tools/linuxapps/prep-wine.sh`).

## Result in Osum today (QEMU KVM, main 9d4a7ce95)

| step | result |
|---|---|
| `wine --version` | ok (`wine-11.0`): ELF load of musl + libwine, dynamic linking, exit |
| `wineserver --version` | ok (`Wine 11.0`) |
| `wine64 cmd /c echo hello` | red: `preloader: failed to reserve range 0x10000-0x110000, 0x7f000000-0x7fff0000, 0x7ffffe000000-0x7fffffff0000`, then `err:virtual:virtual_alloc_first_teb wine: failed to map the shared user data: c0000018` (fixed mapping at 0x7ffe0000) |

Only ENOSYS seen: `userfaultfd` (323); Wine falls back silently (`kernel_writewatch_init` returns on failure, virtual.c:388).

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
| E1 | 64-bit console PE (`cmd /c echo`, mingw hello.exe) | blocker 1, prefix creation (wineboot) | red: single error, see above; gate marks it expected-red |
| E2 | Notepad (user32/gdi32) | E1, winewayland on wayd, fonts | open |
| E3 | 32-bit apps + Vulkan/DXVK hello triangle | blockers 3, 5 | open |
| E4 | Steam/Proton game | blocker 6 + E3 | open |

ArtCraft: no source in the repo. Web search (20.11.2026) says: Rust + Tauri desktop app (storytold/artcraft), Windows/macOS downloads, Linux built from source; licence information conflicts between sources, backend is a separate repo. A Tauri app on Linux needs WebKitGTK (a Linux-native route, not Wine); the Windows build would need WebView2 under Wine (not assessed).
