# LINUX-COMPAT — Linux-Programme auf OrientOS (Analyse + Plan, 12.10.2026)

Nur Analyse. Basis origin/main 69747e75. Belege: `docs/RUNDE-UNTERBAU-FIREFOX.md` (Stand 09.10., Messung), `docs/RUNDE-WAYLAND.md`, `docs/RUNDE-GPU3D.md`, `kernel/sys/sys.fi`, `kernel/fs/unixsock.fi`. Nicht neu gemessen (keine schweren Läufe). Schätzungen sind markiert.

## 1. IST
* **Binärkompatibilität**: statische + dynamische ELF (musl, `PT_INTERP`/`ld-musl`) laufen; `dlopen` fremder .so aus Datei 18/0 (`t_dl`), dynlader 36/0, `mprotect`/W^X/JIT-RX ok.
* **Da (sys.fi)**: `clone` (Fäden = pthread) + `futex` (ohne Warteschlange: Poll alle 10 ms, kein REQUEUE/PI), `memfd_create` (+Siegel, MFD_FRAMES), AF_UNIX + `sendmsg/recvmsg` + SCM_RIGHTS, `socketpair` (nur STREAM), `poll/ppoll/select/pselect6`, `pipe2`, `ioctl` (nur tty), `fallocate`, `tkill`, `vfork`/posix_spawn, `/proc/self/{maps,status}`, `/proc/meminfo`.
* **Da seit 13.10. (main cf430b3b)**: `epoll_*` (LT, ET inkl. Drain+Refill, ONESHOT), `eventfd2`, `timerfd_*`, `signalfd4`, `inotify_*` (Ereignisse IN_CREATE/DELETE/MOVED_FROM/MOVED_TO fuer open(O_CREAT)/mkdir/unlink/rmdir/rename; IN_MODIFY/IN_ATTRIB/IN_DELETE_SELF noch nicht), `setitimer`, `sigaltstack`, `sigsuspend`. Grenzen: 16 fds/Prozess, EP_MAX 80, IN_WMAX 24, Pfad 56 Byte, Namen 15 Zeichen. Weiter **fehlt**: NSIG=32 (keine RT-Signale), `MAP_SHARED` auf Datei (ENODEV), `CLONE_FILES`, `/dev/dri`, `/dev/shm`, `/dev/pts`; `/sys` und `/proc` nur teilweise.
* **Unterbau-Suite 320 PASS / 348 Proben (13.10.)**: t_events 60 Checks (2 GAP: socketpair DGRAM, tcp ohne Netz), t_signals 24/24; Rest siehe tools/unterbau (Limits-Tabellen, busybox-Proben).
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
| E | EIGENER Grafikstack in Firn: CPU-Raster zu Vulkan-Teilmenge (SPIR-V) + später GL 3.3/EGL als libvulkan/libEGL/libGLESv2-kompatible .so; kein LLVM, kein Mesa; HW-Backend später | Vulkan-Teilmenge für Daidalos-RHI: L; wgpu/eframe: XL; GL 3.3 inkl. GLSL-Compiler: XL; Intel-HW-Backend: XL (+ DRM-Kernel aus B/D bleibt nötig) |

### Weg E im Detail (Belege + Bewertung)
* **Daidalos-RHI als Test-Client** (`/root/projects/daidalos/src/rhi_vulkan*.cpp`, 4971 Zeilen): Vulkan **1.3** (`apiVersion`), Dynamic Rendering (`vkCmdBeginRendering`), Graphics-Pipelines, Push-Constants, Blit, Swapchain über Xlib/Wayland/Win32-Surface; **kein** `vkCreateComputePipelines`/`vkCmdDispatch` im RHI (0 Treffer). Shader = vorkompiliertes GLSL→SPIR-V (`shaders/*.spv`: mesh, lines, particle). CI nutzt lavapipe (`.github/workflows/ci.yml`). Kleine, bekannte Teilmenge = guter erster Prüfstein.
* **Was in Firn schon da ist**: `kernel/gfx/r3dsoft.fi` (1201 Z., Dreiecke/Tiefe/Textur/Licht, ohne Shader, ohne Kantenglättung), `lib/mc/mc_raster.fi` (650 Z., Einzelkern, f64, Randfunktionen ganzzahlig, feste Auswahlreihenfolge), `lib/gpu/gl33.fi` (1011 Z.) + `vk.fi`/`vkplat.fi` sind **Client-Wrapper** (rufen fremdes GL/Vulkan per dynlib), **kein** Backend. Ein Shader-Kern (SPIR-V-Interpreter/JIT) existiert **nicht**.
* **Tempo-Beleg**: 1240×720 in 10,5 ms ohne / 6,2 ms mit Cache (`docs/GAP-ANALYSE-0710.md`, Worker-Messung) ist der **2D-fUi-Rasterer** (Rechtecke/Text), **nicht** Fragment-Shading. Übertragbarkeit auf SPIR-V: unbekannt. Schätzung (ungemessen): Interpreter ~100 ns/Pixel → ~90 ms/Bild bei 0,9 Mpx Einzelkern; mit eigenem JIT/SIMD und 4 Kernen Faktor 10–30 besser. lavapipe-Vergleichswert auf diesem Wirt: nicht gemessen (unbekannt).
* **Minimale Teilmenge** — Daidalos: Instance/Device/Swapchain (Present via `wl_shm`, kein dmabuf), Graphics-Pipeline, SPIR-V Vert/Frag, Dynamic Rendering, Descriptor-Sets, Push-Constants, Blit. wgpu/eframe zusätzlich (aus Allgemeinwissen, ungeprüft): Compute + Storage-Buffer, mehr SPIR-V-Capabilities, Vulkan-1.1+-Funktionsliste, Sync2; eframe kann alternativ glow (GL 3.3/GLES + EGL) — GL braucht einen **GLSL-Compiler** (Mesa-Teil, groß), Vulkan nur SPIR-V.
* **Wichtig**: E spart LLVM/Mesa-Port, **nicht** die Linux-ABI: jede .so läuft im Linux-Prozess (dlopen, Fäden, mmap, futex/epoll aus Teil 1). Ob `firnc` eine C-ABI-Shared-Lib (.so mit Export-Tabelle) erzeugen kann: unbekannt (zu prüfen). Auch Intel-HW (später) braucht den DRM-Kern aus B/D.
* **Viele Linux-Programme brauchen gar kein GPU-API** (Allgemeinwissen, ungeprüft): Firefox mit Software-WebRender, GTK mit Cairo-Renderer, Qt mit `QT_QUICK_BACKEND=software`, foot — alle nur `wl_shm`. Daher zählt zuerst die Syscall-Seite.

**Empfehlung (Reihenfolge)**: 1) Syscall-Lücken + Kerngrenzen + Prüfstein-Reihe (Kap. 3), Programme mit Software-Renderer (Wayland `wl_shm`) — löst die Boss-Frage „Linux-Programme gehen" ohne GPU. 2) **Weg E-Minimal**: Vulkan-Teilmenge mit SPIR-V-Interpreter, Test = Daidalos-RHI; vorher lavapipe-Basismessung (Tempo-Ziel). Grund: unser Code, kein LLVM-Port (C++/LLVM auf OrientOS wäre selbst XL, unbekannt), kontrollierbar. 3) Danach wgpu-Teilmenge (Compute) und SPIR-V-JIT/SIMD/mehrkernig. 4) Intel-KMS-Modesetting (Haswell, DRM-Grundstein), dann HW-Backend (E-HW oder Linux-i915 via D). **A (Mesa-Software)** nur Rückfall, falls E bei Features (GLSL, Compute) hängt; C ist in E aufgegangen.

## 3. Prüfstein-Rezept (Plan, Reihenfolge)
1. **busybox** (/bin/sh POSIX `-c`, system/popen) — 2. **python3** (Fäden, mmap, dlopen) — 3. **curl** (+ TLS, resolv.conf, /etc/ssl; braucht Netz im Gast) — 4. **git** (fork, pipes, rename, flock, mmap) — 5. **foot/Terminal** (Wayland shm, epoll, timerfd, ptmx/pts) — 6. **GTK/Qt** (glib epoll/eventfd, fontconfig, dmabuf optional) — 7. **Firefox** (alle Kerngrenzen aus Kap. 5.1).

## 4. Roadmap (Gruppe 'Linux-Kompat', Priorität P0 hoch)
P0 epoll/eventfd/timerfd/signalfd; P0 Kerngrenzen (fds, Fäden, Rohr, Stapel, Adressraum); P0 Prüfstein-Reihe busybox→python3→curl→git; P1 Signale (RT, sigaltstack, setitimer); P1 Dateisystem (ftruncate/flock/symlink, /dev/shm,/dev/pts,/proc,/sys); P1 Demand-Paging + MAP_SHARED Datei; P1 Weg E Vulkan-Teilmenge + SPIR-V-Interpreter (Daidalos-RHI als Test), lavapipe-Basismessung; P2 wgpu-Teilmenge/SPIR-V-JIT; P3 Mesa-Software nur als Rückfall; P2 linux-dmabuf; P2 inotify; P2 DRM/KMS Haswell; P3 3D-Weg D/B.

## 5. Prüfstein busybox (13.10.2026, gemessen: tools/unterbau/run.sh, Abschnitt 3c)
busybox 1.36.1 dynamisch (musl, `/root/bbdyn/busybox`, 152752 Oktette), Kernel main 34eef244 + Runde UNTERBAU-2 (Zweig staff/orientos-mv6hbib2), VM/KVM, ein Kern.

| Prüfung | Ergebnis |
|---|---|
| `busybox sh /etc/bb.sh` (20 Proben) | 12 ok / 8 offen |
| ok | echo, `$(...)`, expr, Pipe + Applet, for-Schleife, `sh -c`, Exit-Status, grep, sed, sha256sum, `/proc/loadavg`, date |
| offen | `sort -r \| head` leer, `mkdir`/`touch` (kein Ergebnis), `>` in neues Verzeichnis, awk leer, `uptime`, `df`, `free`, `ps` scheitern |
| busybox als `/bin/sh`: `system()` / `popen()` (t_proc) | beide PASS (vorher FAIL mit Osum-Shell) |
| Hinweis | dieses busybox hat `$((..))` abgeschaltet (Syntaxfehler, Skript bricht ab) — kein Kernproblem |
Ursachen der offenen Proben sind NICHT geklärt (je Applet `strace`-artig prüfen; Verdacht: `mkdir`-Aufruf, `/proc/uptime|mounts` Format, `sysinfo`-Felder, `/proc/<pid>/stat` Felder).
