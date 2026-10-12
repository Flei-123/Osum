# LINUX-COMPAT — Linux-Programme auf OrientOS (Analyse + Plan, 12.10.2026)

Nur Analyse. Basis origin/main 69747e75. Belege: `docs/RUNDE-UNTERBAU-FIREFOX.md` (Stand 09.10., Messung), `docs/RUNDE-WAYLAND.md`, `docs/RUNDE-GPU3D.md`, `kernel/sys/sys.fi`, `kernel/fs/unixsock.fi`. Nicht neu gemessen (keine schweren Läufe). Schätzungen sind markiert.

## 1. IST
* **Binärkompatibilität**: statische + dynamische ELF (musl, `PT_INTERP`/`ld-musl`) laufen; `dlopen` fremder .so aus Datei 18/0 (`t_dl`), dynlader 36/0, `mprotect`/W^X/JIT-RX ok.
* **Da (sys.fi)**: `clone` (Fäden = pthread) + `futex` (ohne Warteschlange: Poll alle 10 ms, kein REQUEUE/PI), `memfd_create` (+Siegel, MFD_FRAMES), AF_UNIX + `sendmsg/recvmsg` + SCM_RIGHTS, `socketpair` (nur STREAM), `poll/ppoll/select/pselect6`, `pipe2`, `ioctl` (nur tty), `fallocate`, `tkill`, `vfork`/posix_spawn, `/proc/self/{maps,status}`, `/proc/meminfo`.
* **Fehlt (kein Treffer in kernel/ und lib/)**: `epoll_*`, `eventfd2`, `timerfd_*`, `signalfd4`, `inotify_*` (alle ENOSYS, `t_events`). Außerdem NSIG=32 (keine RT-Signale), `sigaltstack`, `sigsuspend`, `setitimer`, `MAP_SHARED` auf Datei (ENODEV), `CLONE_FILES` (fd-Tabelle je Faden kopiert), `/dev/dri`, `/dev/shm`, `/dev/pts`; `/sys` und `/proc` nur teilweise. Echtzeit-Signale/ioctl-Familien (DRM, V4L, input): unbekannt/nicht vorhanden.
* **Unterbau-Suite 249/315**: 66 offen (Stand 09.10., seither nicht neu gemessen). t_events 8 (epoll, eventfd, timerfd, signalfd, inotify, DGRAM, recv, tcp im Testlauf ohne Netz); t_procfs 29 (meist Dateien fehlen im Abbild: /etc/ssl, fonts, zoneinfo, cpuinfo-Felder, /sys); t_signals 7; t_misc 9 (ftruncate, flock, dup3>15, PR_GET_NAME); t_mem 4 (MAP_SHARED, 256 MiB/1 GiB Reservierung, pread>4096); t_limits 6 (Tabellen); t_threads 1; t_proc 2.
* **Firefox-Unterbau (`t_limits`)**: 13 fds/Prozess (Soll ≥256), 28 Fäden (≥64), 185 MiB anon (≥256), 0 MiB PROT_NONE-Reserve (JS-Engine will GiB), Stapel ~500 KiB (8 MiB), Rohr 512 B (64 KiB), Dateischreiben 26 KiB/s (≥10000). Adressraum ~198 MiB, kein Demand-Paging, fork kopiert alles. Das sind Kern-Layoutfragen, die größte Arbeit.
* **Wayland (`wayd`, 52/0)**: Ring-3-Server; wl_compositor, wl_shm(+pool via memfd/SCM_RIGHTS), wl_surface, wl_seat, wl_output, xdg_wm_base/surface/toplevel. Unveränderter `weston-simple-shm` läuft. Fehlt: **linux-dmabuf** (kein Treffer), Subcompositor/Viewporter u. a. Protokolle (unbekannt, nicht gegrept), echte Data-Device-Pfade teilweise.
* **GPU heute**: kein DRM, kein OpenGL/Vulkan. Vorhanden: Software-Raster `kernel/gfx/r3dsoft.fi`, virtio-gpu 2D (`docs/VIRTIOGPU.md`); virgl scheitert am Test-QEMU ohne OpenGL.

## 2. GPU/Vulkan — fertige Bausteine (Antwort auf Boss-Frage: ja, gibt es; sie hängen aber an der Linux-ABI)
* **Mesa** (MIT): GL/GLES/EGL/Vulkan. Software: `llvmpipe`/`lavapipe` (braucht LLVM + volle Linux-ABI + Fäden, viel Speicher), `softpipe`/`swrast` ohne LLVM (langsam). HW: `iris`/`anv` (Intel Haswell am Dell 9020 → Gen7.5 = `crocus`/`hasvk`, nicht iris/anv: **Haswell: crocus (GL), hasvk (Vulkan, eingeschränkt)** — aus Mesa-Wissen, nicht im Repo belegt), `radeonsi`/`radv`, `nouveau`/NVK. Alle HW-Treiber brauchen `/dev/dri` + libdrm-ioctls (GEM, execbuf) + KMS-Kerneltreiber.
* **Weitere**: libdrm (MIT), GBM/EGL (Mesa), Vulkan-Loader (Apache-2.0), wgpu (MIT/Apache), SwiftShader (Apache-2.0, CPU-Vulkan, braucht C++/Fäden/JIT), virtio-gpu/virgl (Mesa-Treiber `virgl`; braucht Host-QEMU mit OpenGL).
* **Lizenz**: Mesa MIT, Linux-DRM/i915 GPL-2.0 (mit Osum GPL-2.0-only kompatibel).

| Weg | Inhalt | Aufwand (Schätzung) |
|---|---|---|
| A | Mesa-Software (lavapipe/llvmpipe, später softpipe) auf Syscall-Lücken-Fix, plus Wayland-EGL-Pfad (wl_shm statt dmabuf) | M–L (Syscalls) + L (Mesa/LLVM-Portierung) |
| B | DRM-Kernelschicht (/dev/dri, GEM, ioctl-ABI) + Linux-Treiber-Port i915 Haswell, später amdgpu/Xe/nouveau | XL |
| C | Eigener Intel-Treiber + Firn-GL (`lib/gpu`, GL 3.3), Mesa umgangen | XL (für GL 3.3), Linux-Apps nutzen es nicht ohne Mesa-Shim |
| D | linuxkpi-artige Hülle (Linux-Treiber unverändert laufen lassen, wie FreeBSD drm-kmod) | XL, aber Treiber-Zugewinn dauerhaft |

**Empfehlung (Reihenfolge)**: 1) Syscall-Lücken + Kerngrenzen (Teil 1; ohne das läuft nichts, auch kein Mesa) und Prüfstein-Reihe; 2) Mesa-Software (A) → Linux-GL/Vulkan-Apps laufen langsam, aber überhaupt; 3) Intel-KMS-Modesetting (Haswell) als DRM-Grundstein; 4) 3D über Weg D/B (Linux-i915 via Hülle, Mesa crocus/hasvk), C nur als Notlösung. Begründung: Mesa-HW braucht dieselbe ABI wie Software-Mesa; erst die ABI, dann der Treiber.

## 3. Prüfstein-Rezept (Plan, Reihenfolge)
1. **busybox** (/bin/sh POSIX `-c`, system/popen) — 2. **python3** (Fäden, mmap, dlopen) — 3. **curl** (+ TLS, resolv.conf, /etc/ssl; braucht Netz im Gast) — 4. **git** (fork, pipes, rename, flock, mmap) — 5. **foot/Terminal** (Wayland shm, epoll, timerfd, ptmx/pts) — 6. **GTK/Qt** (glib epoll/eventfd, fontconfig, dmabuf optional) — 7. **Firefox** (alle Kerngrenzen aus Kap. 5.1).

## 4. Roadmap (Gruppe 'Linux-Kompat', Priorität P0 hoch)
P0 epoll/eventfd/timerfd/signalfd; P0 Kerngrenzen (fds, Fäden, Rohr, Stapel, Adressraum); P0 Prüfstein-Reihe busybox→python3→curl→git; P1 Signale (RT, sigaltstack, setitimer); P1 Dateisystem (ftruncate/flock/symlink, /dev/shm,/dev/pts,/proc,/sys); P1 Demand-Paging + MAP_SHARED Datei; P1 Mesa-Software; P2 linux-dmabuf; P2 inotify; P2 DRM/KMS Haswell; P3 3D-Weg D/B.
