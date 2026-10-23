# LINUX-COMPAT-VS-VINIX — wo OrientOS gegen Vinix steht (Analyse, 14.10.2026)

Nur Analyse + kleine Syscall-Ergänzungen (Kap. 4). Basis origin/main 69faec01.
Vinix-Quelle: README von https://github.com/vlang/vinix (WebFetch 14.10.2026). **Nur dort Belegtes steht als Fakt, alles andere „unbekannt".**
OrientOS-Quelle: Repo (sys.fi, tools/*, docs/RUNDE-*). Schätzungen sind als *Schätzung* markiert, nicht gemessen.
Ältere Analyse: `docs/LINUX-COMPAT.md` (einzelne Punkte dort sind überholt, z. B. NSIG, 512 fds).

## 1. Was Vinix kann (laut README)

| Bereich | Vinix (belegt) |
|---|---|
| Ziel | V-OS, „source-level compatibility with Linux", amd64 + arm64, echte Hardware; **pre-alpha**, nicht für Alltag |
| Userland | Alpine-musl-Userland; `pkg` installiert Alpine-Pakete bei Bedarf |
| Mitgeliefert | X.org + Mesa, GTK, Python, V, GCC, git, curl |
| Auf Abruf | Firefox, Chromium, LibreOffice, GIMP, FFmpeg, Blender, OBS, tmux, OpenJDK 25, Go, Ruby, Minecraft Java, Chocolate Doom (Ton über `/dev/dsp`) |
| Grafik | Framebuffer-Desktop (ui2), X.org; Hyprland auf aarch64; Android-Apps über Android Translation Layer (optional) |
| Kernel-Zutaten für Chromium | kleines procfs, `SO_PASSCRED`/`SCM_CREDENTIALS` auf Unix-Sockets, Userspace-Traps als `SIGTRAP`, Sockets read-write |
| Hypervisor | experimentell Intel VT-x als `/dev/hypervisor`, 1 vCPU, ≤ 2 MiB je VM; **kein** `/dev/kvm` |
| Echtzeit/NUMA | SCHED_FIFO/RR/DEADLINE und NUMA als Roadmap-Punkte |
| **Namespaces / seccomp-bpf** | **nicht implementiert** (README: Browser laufen ohne Sandbox) |
| **Docker/Container** | **nicht erwähnt** |
| Bekannte Fehler | SMP-Scheduler-Fehler (LibreOffice), Minecraft mit 1 vCPU |
| Syscall-Liste | **unbekannt** (README nennt keine) |

→ „Vinix-Niveau" heißt in der Praxis: **Alpine-/musl-Programme laufen, inkl. Browser ohne Sandbox.** Docker-artige Container hat Vinix selbst nicht.

## 2. Was OrientOS hat (Repo-Stand)

| Bereich | OrientOS | Beleg |
|---|---|---|
| ELF | statisch + dynamisch (musl `ld-musl` als PT_INTERP), `dlopen` fremder .so 18/0, W^X/JIT-RX | tools/dynlader 36/0, t_dl |
| Syscalls | Linux-x86-64-Nummern; ~200 `SYS_*` + `UB_*` + `EV_*` (epoll, eventfd2, timerfd, signalfd4, inotify) + Osum-Aufrufe ≥ 1000; unbekannte Nummer → `-ENOSYS` | kernel/sys/sys.fi (19229 Z.) |
| Fäden/Prozesse | `clone` (VM/FS/FILES/SIGHAND/THREAD/SETTLS/TID), `fork`, `vfork`, `execve`, `wait4`, futex (ohne echte Warteschlange), `set_robust_list` = Stub (0) | sys.fi 409ff, futex.fi |
| Signale | NSIG = 65 (RT 32..64), sigaltstack, sigsuspend, setitimer, `sigqueue` | signal.fi |
| Speicher | mmap/munmap/mprotect/mremap/madvise/msync/mlock*, `memfd_create` (+Siegel), Demand-Paging für private Dateimappings (ab 16 Seiten, t_flazy), `MAP_SHARED` auf Datei = ENODEV | sys.fi, t_mem |
| Grenzen | 512 fds/Prozess, 1024 offene Dateien, Rohr 64 KiB, Stapel 10 MiB, **32 Aufgaben (MAX_TASKS)**, ~185 MiB anonymer Speicher je Prozess | t_limits, RUNDE-UNTERBAU-FIREFOX |
| Sockets | AF_UNIX (STREAM+DGRAM-socketpair, SCM_RIGHTS), AF_INET (TCP/UDP), AF_NETLINK (nur RTM_GET*-Dumps), `getsockopt/setsockopt`; **kein `SO_PEERCRED`/`SCM_CREDENTIALS`** | unixsock.fi, netlink.fi |
| Dateisystem | OFS v3 (Journal), FAT/ext4/NTFS lesend; symlink/readlink/rename/link/flock(Stub)/fallocate; **kein** `/dev/shm`, `/dev/pts`, `/dev/dri`; `/proc` + `/sys` nur Teile | ofs.fi, procfs.fi |
| Prüfsteine (gemessen) | busybox 56/0, python3 3.12 11/11, curl 8.10 (TLS), git 2.46, foot-Stones laden; GTK4-Kette gebaut (tools/gtk) | docs/LINUX-COMPAT.md Kap. 5–7 |
| Unterbau-Suite | 495/0 im Volllauf (14.10., W-MERGE5), POSIX-Gate 150/0 | tools/unterbau, tools/posix |
| Wayland | `wayd` (Ring 3): compositor, shm, seat, output, xdg-shell, subcompositor, data-device; 52/0; **kein dmabuf, kein Xorg/XWayland** | tools/wayland |
| Container (LXC-Stil) | `ctr`: eigene Wurzel (Pfad-Falten), RAM-Limit, CPU-Anteil, Prozesslimit (gebaut, ungemessen), Prozesssicht, netview; max 8 Container; Gate 52/0 | kernel/sched/ctr.fi, tools/container |
| Capabilities | **Objekt-Capabilities** (Handle-Tabelle, native ABI ≥ 2000) — **nicht** Linux-`capget/capset` | kernel/ipc/cap.fi, tools/caps |
| eBPF | eigener Interpreter + Prüfer + Maps + 2 Netzhaken; Osum-Syscalls 1405–1409, **kein Linux-`bpf(2)`** | kernel/net/ebpf*.fi, tools/ebpf |
| Härtung | Kanarienvogel-Heap-Prüfung (`buf_grow` bei OOM), Beweisläufer; **kein seccomp, kein ASLR-Nachweis (unbekannt)** | tools/hardening |
| Hypervisor | VT-x, `VM_CREATE/RUN/…` (1500–1504); startet unverändertes Debian-Linux 6.12 bis zum Mangel der Wurzel (HV3). Kein Datenträger/virtio-Gerät für den Gast | docs/RUNDE-HV3.md |
| Audio/Hotkeys/Tray | eigene Osum-Aufrufe (OSUM_AUD*); **kein `/dev/dsp`, kein ALSA** | sys.fi |

## 3. Vergleich + Lücken (Reihenfolge nach Nutzen)

| # | Lücke gegen „Vinix-Niveau" | Vinix | OrientOS | Aufwand (*Schätzung*) |
|---|---|---|---|---|
| 1 | Deskriptortabelle geteilt zwischen Fäden (`CLONE_FILES`) | unbekannt | fehlt (`t_threads.fd_table_shared_between_threads`) | M |
| 2 | ≥ 64 Fäden / Aufgaben (`MAX_TASKS`=32 in ~20 festen Tabellen) | SMP da | fehlt | L |
| 3 | `*at`-Aufrufe (openat, newfstatat, unlinkat, mkdirat, renameat, readlinkat …) für glibc/Go/neuere musl | ja (Alpine läuft) | **fehlten komplett** → jetzt für `AT_FDCWD`/absolut (Kap. 4) | S |
| 4 | `MAP_SHARED` auf Datei, Demand-Paging, Seitenpuffer | unbekannt | fehlt | L |
| 5 | Adressraum für Browser (GiB-Reserven, `PROT_NONE`-Reserve) | Firefox/Chromium laufen | 185 MiB, 0 MiB Reserve | L |
| 6 | `/dev/shm` (`shm_open`), `/dev/pts`, `/proc/self/exe`, `/sys/devices/system/cpu` | procfs klein | fehlen | S–M je |
| 7 | `SO_PEERCRED`/`SCM_CREDENTIALS` (Chromium, D-Bus, Wayland-Compositoren) | ja | fehlt | S |
| 8 | `SIGTRAP` für Userspace-Traps (Chromium) | ja | unbekannt | S |
| 9 | Paketfeed für Alpine (`pkg`/apk) statt handgebauter Steine | ja (`pkg`) | nein (Steine + OPK-Feed) | M |
| 10 | X11 (X.org/XWayland) | ja | nein, nur Wayland | L |
| 11 | OpenGL/Vulkan (Mesa) | ja (Mesa) | nein; Plan Weg E in LINUX-COMPAT.md | XL |
| 12 | `/dev/dsp` (OSS-Ton) | ja | nein | M |
| 13 | echte Futex-Warteschlange (REQUEUE/PI) | unbekannt | Poll alle 10 ms | M |
| 14 | Namespaces / seccomp | **nein** | nein (nur `ctr`) | siehe Kap. 5 |

**Empfohlene Reihenfolge:** 3 (billig, erledigt) → 7 → 6 (`/dev/shm`, `/proc/self/exe`) → 1 → 2 → 4/5 (zusammen, Speicher-Umbau) → 9 → 10/11. Container (Kap. 5) erst nach 1–3, weil Docker/Go-Binaries genau diese Aufrufe brauchen.

## 4. Firefox-Unterbau — Stand + Nächstes (Task C)

`t_limits` (gemessen 13./14.10.): fds ≥ 256 PASS, Fäden ≥ 64 PASS (nach W-LIMITS), anon ≥ 256 MiB PASS, Reserve ≥ 4 GiB PASS; Dateischreiben nach /tmp **880 KiB/s** (Ziel 10000, r742 offen).

| Voraussetzung | Stand | Anmerkung |
|---|---|---|
| `memfd_create` | da (+Siegel) | Wayland-shm läuft |
| `shm_open` / `/dev/shm` | **fehlt** | t_procfs.shm_* nicht in accept.txt; braucht Gerätedatei + tmpfs-Pfad im VFS (M) |
| `eventfd`/`epoll`/`inotify`/`timerfd`/`signalfd` | da | inotify ohne IN_MODIFY/IN_ATTRIB |
| `getrandom` | da | |
| `sched_*` | da (nur SCHED_OTHER; RT abgelehnt) | |
| `mremap`/`madvise`/`mlock`/`msync` | da (mremap ohne FIXED/DONTUNMAP) | |
| `futex` robust | `set_robust_list` = Stub 0; `get_robust_list` fehlt; kein Aufräumen beim Tod | S–M |
| `/proc/self/*` | `maps`, `status`; `exe`, `limits`, `fd`, `cpuinfo`-Felder fehlen | S je |
| `SO_PEERCRED` | fehlt | S |
| SysV shm (`shmget/shmat`) | fehlt | nur für X11-MIT-SHM, Firefox nutzt memfd → niedrig |
| seccomp | `prctl(PR_GET_SECCOMP)`=0, `PR_SET_NO_NEW_PRIVS` akzeptiert, `seccomp(2)` = ENOSYS | Stub-Antworten reichen für Firefox mit `MOZ_DISABLE_CONTENT_SANDBOX`; echte Filter siehe Kap. 5 |
| `*at`-Familie | fehlte | Kap. 6 |

## 5. Containers — Machbarkeit (Docker-Stil) — Task B

**Ausgangslage (belegt):** `kernel/sched/ctr.fi` (8 Container) ist ein *anderes* Modell als Linux: EIN Feld `T_CTR`, Wurzel als Pfadpräfix (`ctr.fold` → ausbruchssicher gegen `..`), RAM-Limit in Rahmen (`proc.map_page`), CPU-Anteil (`sched.budget_for`), Prozesssicht, `netview`. Linux-Namespaces/cgroups/overlayfs/seccomp/veth: **0 Treffer** in `kernel/`. `tools/caps` = Objekt-Capabilities (andere Baustelle), `tools/hardening` = Heap-Härtung, `tools/ebpf` = eBPF-Maschine (Klassik-Befehlssatz + Prüfer, Netzhaken). Vinix hat **nichts davon**.

Ehrliche Lücken laut `docs/RUNDE-CONTAINER.md` Kap. 6: kein eigenes Netz je Container (keine eigene IP), keine eigenen pids, `T_UID` global, keine Einhängetafel je Container, kein Abbild-Format, `procs`-/`cpu`-Grenze ungemessen.

Aufwand: **S** ≤ 1 Tag, **M** eine Runde, **L** mehrere Runden. Alles *Schätzung*.

| Baustein | Aufwand | Kerndateien | Risiken / Anmerkung |
|---|---|---|---|
| `NO_NEW_PRIVS` real (Bit je Aufgabe, vererbt) | S | sys.fi (`do_prctl` ~7125), proc.fi (clone/exec) | heute nur Antwort „1"; Voraussetzung für seccomp |
| `clone3` | S | sys.fi (`dispatch`, Dünnschicht auf `do_clone`) | heute ENOSYS (glibc/Go fallen zurück); Pflicht, sobald `CLONE_NEW*` gebraucht wird |
| Linux-Capabilities (`capget/capset`, Bounding-Set) | S (Stub) / M (echt) | sys.fi, ipc/perm.fi, ctr.fi | Prüfungen sind uid-0-basiert und verstreut; Objekt-Caps (cap.fi) nicht vermischen |
| `chroot(2)` je Prozess | S–M | uio.resolve, ctr.fi, sched.fi (Feld je Aufgabe) | Wurzel gilt heute je Container; per-Prozess-Feld → `kdata`-Offsets, K2-Skalarseite nicht erweitern ohne Gegenprüfung |
| `pivot_root` | M | wie chroot + mnt.fi | braucht Mount-Tafel je Container; sonst nur Alias zu chroot |
| `uts`-Namespace (hostname) | S | sys.fi (`do_uname` 7073, `sethostname` fehlt), ctr.fi (Name-Feld X_NAME da) | trivial; X_NAME existiert schon |
| `ipc`-Namespace | S–M | unixsock.fi, share.fi | sysv-IPC fehlt ganz; AF_UNIX-Pfade sind per Wurzel schon getrennt |
| `pid`-Namespace (eigene pid 1, virtuelle pids) | M–L | proc.fi, signal.fi, sys.fi (getpid/wait4/kill/tgkill), procfs.fi | nur 32 Aufgaben; Abbildung virtuell↔real in jedem pid-Aufruf; `ctr.visible` schon Basis |
| `mnt`-Namespace (Mount-Tafel je Container, bind-mount) | M–L | fs/mnt.fi, vfs.fi, uio.resolve | bind-mount fehlt als Primitive; Mounts sind global |
| `user`-Namespace (uid/gid-Abbildung) | L | multiuser (setuid & Co. in sys.fi), perm.fi, ctr.fi | `T_UID` global; jede Rechteprüfung müsste abbilden; hohe CVE-Fläche bei Fehlern |
| `net`-Namespace + veth + Bridge | L | net/netdev.fi, inet.fi, netview.fi, netlink.fi | nur ein NIC `eth0`, **kein Loopback-Gerät**, ein IP-Stack; Netlink schreibend fehlt (RTM_NEW*); NAT/nft fehlt; berührt Dateien von netzplus/ebpf |
| `cgroup`-Namespace | S | procfs/cgroupfs | nur Fassade |
| cgroups v2 (cpu.max/memory.max/pids.max) | M | neues fs/cgroupfs.fi, vfs.fi, ctr.fi | Werte gibt es schon (X_MEMLIM/X_CPUSH/X_PROCLIM); fehlt die Dateischnittstelle `/sys/fs/cgroup` und Hierarchie (flach, max 8 → Docker will verschachteln); io.max fehlt |
| `unshare`/`setns` | M | sys.fi, ctr.fi, procfs (`/proc/<pid>/ns/*`) | erst sinnvoll, wenn mindestens uts/pid/mnt da sind; heute nur `OSUM_CTRNEW/CTRENTER` (Einbahn) |
| overlayfs | L | vfs.fi, ofs.fi, uio.resolve | Union-Lookup, Whiteouts, Copy-up, readdir-Mischung, rename; keine xattrs. Zwischenlösung S–M: Schichten entpacken (tar/OCI → Verzeichnis), kein Union |
| seccomp (Strict + BPF-Filter) | M | sys.fi (`dispatch` Einstieg, `do_prctl`), ebpf.fi, proc.fi | Linux nutzt *klassisches* BPF; `ebpf.fi` spricht eBPF → cBPF→eBPF-Übersetzer nötig; Filter muss bei fork/clone/exec erben; Kosten im heißen Syscall-Pfad; Zeiger-Argumente nie dereferenzieren (TOCTOU) |
| Linux-`bpf(2)` | M | sys.fi → ebpf*.fi | heute Osum-eigene Nummern; nur nötig für Tools wie bpftrace/cilium |
| OCI-Laufzeit („`ctr run bundle`") ohne Namespaces: Abbild entpacken + `ctr` + Limits | **M** | kernel/user/ctr.fi, tar.fi | schnellster Weg zu „Container starten"; Isolation = bestehendes `ctr` (stärker als Vinix) |
| Linux-Gast per Hypervisor (Debian + dockerd in VM) | L | hv, virtio-blk/net für Gast (HV3 Kap. 7) | Alternative zu allem oben: echtes Docker ohne Kern-Namespaces; braucht Gast-Datenträger + Netz, 1 Gast-Kern |

**Docker-Gesamtbewertung:** unverändertes `dockerd`/`runc` = **L, mehrere Runden** (pid+mnt+net+user-NS, cgroupfs, overlayfs, seccomp, veth/Bridge, nft, plus Go-Laufzeit: clone3, ≥ 64 Fäden, RT-Signale, `CLONE_FILES`). Realistische Staffel:
1. **Stufe A (M):** OCI-/tar-Abbild entpacken + `ctr` starten (kein Docker-Daemon), `uts`, `clone3`, `NO_NEW_PRIVS` real.
2. **Stufe B (M):** cgroupfs-Fassade über `ctr`-Limits, Linux-Caps-Stub, `chroot`.
3. **Stufe C (L):** pid-/mnt-NS, `pivot_root`, bind-mount, seccomp.
4. **Stufe D (L):** net-NS + veth + Bridge + NAT, overlayfs, user-NS.
Alternativ zu C+D: Linux-Gast per Hypervisor (L, aber nutzt vorhandenen HV3).

**Hauptrisiken:** feste Tabellen (`MAX_TASKS`=32, `MAX_CTR`=8, K2-Skalarseite) bremsen jede Verschachtelung; `T_UID`/Pfadwurzel sind global → Rechteprüfung im ganzen Kern anfassen; alle Container teilen den Kern (kein Schutz gegen Kernfehler, bei Linux ebenso).

## 6. Neu in dieser Runde (Task C: billige Syscalls)

| Aufruf (Nr.) | Verhalten | Test |
|---|---|---|
| `openat` (257), `mkdirat` (258), `newfstatat` (262, inkl. `AT_SYMLINK_NOFOLLOW`, `AT_EMPTY_PATH`), `unlinkat` (263, inkl. `AT_REMOVEDIR`), `renameat` (264), `renameat2` (316, nur flags=0, sonst `-EINVAL`), `linkat` (265), `symlinkat` (266), `readlinkat` (267) | leiten auf die vorhandenen `do_*` um (inkl. inotify-Ereignisse). r807: ein Verzeichnis-Deskriptor merkt sich beim `open` seinen Pfad (ein Frame, `OF_X1`, frei in `file.open_teardown`); ein relativer Pfad mit echtem `dirfd` wird dagegen aufgelöst (`uio.set_atbase`, `uio.resolve`). Auch `faccessat`/`faccessat2`/`fchmodat`/`fchownat`/`utimensat`. Grenze: `renameat`/`linkat` mit zwei VERSCHIEDENEN echten Verzeichnissen (oder cwd-relativ neben dirfd-relativ) → `-ENOSYS`; Test `tools/unterbau/t_openat.c` | `tools/unterbau/t_fsat.c` |

Code: `kernel/sys/sys.fi` (`lc_is_at`, `lc_dir_ok`, `lc_at` am Dateiende, Einhängepunkt hinter `UB_PIPE2` in `dispatch`). Nicht umgesetzt (Begründung): `statx` (Strukturumsetzung, M), `getcpu` (keine Quelle für die aktuelle CPU-Nummer im Kern), `capget/capset`, `SO_PEERCRED`, `/dev/shm`, `get_robust_list` — alle als Roadmap-Punkte LC-F1/LC-C7.
