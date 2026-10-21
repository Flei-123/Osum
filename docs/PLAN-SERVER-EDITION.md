# PLAN-SERVER-EDITION — OrientOS Server Edition (Proxmox/LXC style), 21.10.2026

PLAN ONLY, no feature code. Base: origin/main 8520ca01. Every number below was measured on 21.10.2026 on the build server (AMD EPYC 7571, KVM, QEMU) unless marked "doc" (taken from an older round doc) or "not measured". Measurement scripts: /root/abbilder/srvplan (removed after the run; commands are reproduced in section 2).
Legend: Effort S = hours, M = about a day, L = days, XL = weeks. Owner: H = haiku worker (mechanical), S = sonnet worker (kernel/design). `rNNNN` = roadmap item. Rules as everywhere: new code English only, no comments, small modules, every gate with a counter-proof, heavy runs only via `/root/jarvis/bin/heavy`.

## 0. Verdict in five lines
1. The server build **exists, is in main and builds in 34 s**: `tools/server/build.sh` (kernel `--gui off` + 60 programs + 10 MiB disk). Kernel 6 141 832 B vs 8 700 384 B with GUI (-2 558 552 B, -29.4 %).
2. A headless image **boots to a shell on the serial line in 1.34-1.45 s** (3 runs, KVM, direct multiboot) and idles at **16.2 MiB** used frames (constant at -m 128/256/512). Desktop OrientOS idles at 190.2 MB, Alpine 111.2 MB, Debian 177.8 MB (doc, tools/bench/ref.sh).
3. **Containers (`ctr`) are in main and green: 52/0 in 40 s** (root jail, memory limit, process view). A container really executes programs from its own root (measured: `ctr exec 1 /bin/ls /bin` lists only the container's two files).
4. The default server image is **not a server yet**: it has no `/bin/init`, `svc`, `sshd`, `dhcp`, `ctr`, `ota` in its program list, no `/etc/inittab` (init then exits and the machine halts: measured), no `/proc`, OFS v2 with max file 2 134 016 B.
5. Hypervisor (`hv.fi`, 3 445 lines) boots a real Linux 6.12 up to "cannot mount root" (doc HV3), **AMD-V only**, no virtio devices for guests. Proxmox-VM-equivalent is the longest road (XL); LXC-equivalent is the short road (M-L steps).

## 1. Inventory with evidence

### 1a. Server build (docs/ROUNDSERVERBUILD.md)
| Question | Answer | Evidence |
|---|---|---|
| In main? | yes | `kernel/gfx/gfx.fi`, `gfx-aus.fi`, `kernel/drv/con/sercon.fi`, `tools/server/{build,run,console,count,moved}.py/sh`, gate `server` (nightly, gates.tsv:157) |
| Builds? | yes, 34 s for `bash tools/server/build.sh <dir>` (kernel + 60 programs + disk); `build-kernel.sh --gui on` 24 s (cache) | measured |
| Kernel size | gui=off **6 141 832 B**, gui=on **8 700 384 B**, delta **2 558 552 B (29.4 %)** | measured (round doc 2021: 2 109 692 vs 2 849 604, 25.9 %; kernel has since grown 2.9x) |
| Userland | 60 programs, 3 775 080 B; with 14 extra server tools (init svc sshd dhcp ctr ota stress ctrkill reboot shutdown backup sntp host dnswt) 74 programs, 5 164 472 B | measured |
| Headless boot | yes: `qemu -kernel k.mb -append "osum console=ttyS0"` -> `sh: ready` in **1.34 / 1.38 / 1.45 s** (KVM, 1 vCPU, IDE, no bootloader) | measured, 3 runs |
| Idle RAM | frames not free: 4136 / 4139 / 4142 at -m 128 / 256 / 512 = **16.2 MiB**; with init + shell + virtio-net 4999 frames = 19.5 MiB; GUI kernel on the same disk 6986 frames = **27.3 MiB** (+11.1 MiB for fb/wm/ttf/tiles) | measured via `top` (I_FRAMES_FREE) |
| No wayd/wmd/fUi/compositor/gfx drivers needed | yes: round gate counts 739 GUI symbols in the GUI kernel, 0 in the server kernel; `build.sh` refuses a disk containing schreibtisch/leiste/explorer/launcher/...; server disk has no program importing `wlib` | gate (22/0 in the round doc); the disk guard ran green in my build. I did not re-run the 22-check gate itself (see 4) |
| Serial console | `console=ttyS0`: line discipline, echo, backspace, Ctrl-U/C/D, IRQ vector 36 (COM1/COM2) | doc + my 3 boots |
| Services | `init.fi` (1 072 lines): `/etc/inittab` with targets (konsole/grafik), respawn with fail counter (5 fast deaths -> failed), per-service `log=`, `netz` option (wait for IP), `/etc/fstab`, `svc` list/start/stop/restart/shutdown/reboot; `sshd.fi` (2 035 lines, Ed25519/X25519/ChaCha20, pty, gate tools/sshd, 600+ cases against the Linux client); `dhcp.fi` (1 357 lines); `ota.fi` (3 781 lines, signed feed, A/B + trial boot via ESP); `backup.fi` (TRESOR: save/list/restore/get/verify, encrypted) | doc + `svc` run on my image: `sh running ... 1/1 Dienste laufen` |
| Network | virtio-net works: `ping 10.0.2.2` 20 ms with `nic nip=10.0.2.15/24 ngw=10.0.2.2`; drivers e1000, r8169, iwl, usbnet; without a NIC `ping` -> errno -19 | measured |
| Disk drivers | AHCI, NVMe, virtio-blk, IDE | `kernel/drv/blk` |

**Findings (all measured, all fixable in SRV-1):**
- F1 `tools/server/build.sh` PROGS has no init/svc/sshd/dhcp/ctr/ota/backup/sntp. The documented server cannot be managed remotely out of the box.
- F2 With `/bin/init` present and no `/etc/inittab`, init prints `/etc/inittab fehlt` and the kernel halts (`osum: sh exit=1`). The server image has no inittab, ziel, `/var/log`, `/run`.
- F3 `svc` needs `/run/svc.state` (`/run` absent -> error).
- F4 `mount proc /proc proc` -> `mount: cannot mount`; `/proc/meminfo` does not exist in the plain server boot (desktop installs boot with `vfs`; server path not wired).
- F5 `mkfs.py build` creates OFS **v2**: `maxfile=2134016`, 128 inodes. A Linux rootfs (python stdlib, libc, Alpine packages) does not fit; OFS v3 (installed disk) is needed. The OFS limit of 130 MiB per file (r1366) applies to v3.
- F6 `cp` creates files without the exec bit; `ctr exec` of a copied program fails (`exec scheitert`) until `chmod 755` (measured both ways, with/without chmod).
- F7 Network only via kernel command line (`nip=`/`ngw=`); `dhcp` exists but is not started by any inittab line.

### 1b. Containers (docs/RUNDE-CONTAINER.md, commit 9eaeb9ae)
In main (ancestor check true; merge 9018826e). Gate `container` (full tier), run today: **`CONTAINER: 52 passed, 0 failed` in 40 s**.
| Stage | State | Measured / evidence |
|---|---|---|
| 1 own root (`ctr.jail`/`fold`, applied in `uio.resolve`) | done | 4 breakout ways blocked, counter-proof: same command in host reads the secret |
| 2 limits: memory (frames, only smaller), CPU share (slice length) | done; `procs` built but **not measured** | stress 96 frames blocked at limit 64, passes at 32 and without limit |
| 3 own process view (pstat, kill x2 doors, ESRCH) | done | host sees 4, container sees 1 |
| 4 network | only the `netview` mode per container (real/filtered/faked/none), **no own IP** | doc section 6 |
| 5 tool `ctr` (create/set/start/stop/exec/destroy/show/list) | done | my run: create, `set 1 mem 64`, `start`, `exec 1 /bin/ls /bin` -> `./ ../ ls cat` |
Costs: kernel +5 236 B (+0.086 %), 256 B per container, **MAX_CTR = 8**, MAX_TASKS = 32 (8 containers x 4 tasks is already the whole machine). Gaps from the doc (still open): own network, own pids (pid 1 per container), own users (T_UID global), mount table per container, tar images with layers, limits for files/sockets/IO, `procs`+`cpu` gate, kernel bug = escape (same boundary as LXC).
Related roadmap items already existing: r745 LC-C1 .. r752 LC-C8, r1145 (S2), r898 AR-3, r410.

### 1c. Hypervisor (kernel/arch/x86_64/hv.fi, vmcb.fi, vdev.fi; docs/RUNDE-HV2/HV3)
- `hv.fi` 3 445 lines, `vmcb.fi` 323, `vdev.fi` 925. AMD-V (SVM) with nested paging; **no Intel VT-x** (QEMU TCG cannot do VMX; host here has svm, 64 flags in cpuinfo).
- State (doc HV3): a Debian Linux 6.12.101-rt bzImage runs 192 512 exits, writes 25 953 bytes to the emulated UART, and stops at "VFS: Unable to mount root fs" (no disk, no initramfs). Gate `tools/hv/run.sh`: 162 passed / 0 failed, `hv: proofs 36/36` (doc); my re-run is in section 4.
- Missing: virtio-blk/net/console device models (only legacy devices), initramfs/rootfs, ACPI + IOAPIC for SMP guests, TSC/HPET, snapshots, Intel VT-x. Existing items: r752 LC-C8, r1146 (S3).
- Conclusion: a Proxmox *VM* is XL. The container path gets a usable server much earlier.

### 1d. Linux userland in a container (how far does it run)
- Measured by the unterbau/stones round (doc LINUX-COMPAT sec. 5, master plan sec. 9): busybox 1.36.1 dynamic (musl) **55 ok / 1 open** (`ip`: no AF_NETLINK), python3 3.12.7 11/11, curl 8.10.1 http ok, git 2.46.2 basics ok; unterbau 710 PASS / 3 FAIL / 4 GAP of 717.
- Not measured: running these *inside* a `ctr` root (musl loader path `/lib/ld-musl-x86_64.so.1`, `/proc`, `/dev` inside the jail, uts name). glibc/Debian userland: no evidence at all (only the musl dynamic loader exists). -> SRV-6.
- Shared limits with the desktop Linux-apps work: OFS file size (LA-1, r1366), MAX_TASKS (LA-2, r1367), futex without wait queue (poll every 10 ms), `*at` calls without real dirfd (r754).

## 2. Server vs desktop: the build measurement (question "no wayd/wmd/fUi/gfx?")
Commands (reproducible): `bash tools/server/build.sh <dir>` (34 s), `bash tools/build-kernel.sh <dir>/gui.mb --stufe 0 --gui on` (24 s), then QEMU `-accel kvm -cpu host -kernel k.mb -m 256 -display none -serial unix:... -append "osum console=ttyS0"` with `tools/server/console.py`-style waiting for `sh: ready`.
| | OrientOS server (measured) | OrientOS desktop (metrics) | Alpine virt (ref) | Debian 13 cloud (ref) | TinyCore (ref) |
|---|---|---|---|---|---|
| Kernel | 6.14 MB | 8.44 MB (osum.mb 8437 KB) / 8.70 MB stage 0 | - | - | - |
| Image | 10 MiB disk + 6.1 MB kernel | 146 MB | 66 MB | 389.9 MB | 23.3 MB |
| Boot to prompt | 1.34-1.45 s (no loader, no menu) | 24.5 s to login (20 s Limine menu + 1 s loader + 3.5 s kernel) | 3.6 s | 16.4 s | 2.1 s |
| Idle RAM | 16.2 MiB (19.5 with init+NIC) | 190.2 MB | 111.2 MB | 177.8 MB | 80.7 MB |
Caveat: the server boot number is kernel-to-shell with QEMU direct boot; the references include their bootloaders (ref.sh, 2 vCPU, 1536 MiB), so compare the kernel part (desktop 3.5 s) only. Idle RAM = frames not free, not Linux MemAvailable. A bootable installed server (Limine, GPT, A/B) is not measured yet -> SRV-2.
Confirmed: a server image needs none of wayd, wmd, fUi, compositor, gfx drivers (0 of 739 GUI symbols; GUI adds 2.56 MB kernel and 11.1 MiB RAM).

## 3. Gap list vs Proxmox + LXC
Rating: OK = works and measured, PART = exists with holes, NONE = missing.
| Area | Proxmox/LXC has | OrientOS today | Rating | Milestone |
|---|---|---|---|---|
| Image/boot | installer ISO, ZFS/LVM, GRUB | `--gui off` kernel, OFS v2 test disk, no server installer/loader entry | PART | SRV-1, SRV-2 |
| Management CLI | `pct`, `qm`, `pvesh` | `ctr`, `svc`, `ota`, `backup` as separate tools, German output | PART | SRV-10 |
| API | REST (pveproxy) | none; orientbus/rpcd local only; outbound bridge jarvisd | NONE | SRV-10 |
| Web UI | ExtJS GUI on 8006 | none (no HTTP server, TLS server side unverified) | NONE | SRV-11 |
| Remote shell | ssh, noVNC/xterm.js | `sshd` with pty (gate tools/sshd), serial console | PART | SRV-3 |
| Start/stop/autostart | `onboot`, order, delays | `ctr start/stop` flips a state; no autostart, no ordered shutdown, stop does not kill processes (not measured) | PART | SRV-5 |
| Console/attach | `pct enter/console` | `ctr exec` (fork, enter, execve), no pty attach | PART | SRV-5 |
| Templates/images | `pveam`, tar.zst templates | directory tree only; `tar`, `gzip` exist | NONE | SRV-5 |
| FS isolation | mount ns, overlay, ZFS clones | jail string in `uio.resolve` (breakout-proof by fold), no mount table per ctr, no overlay | PART | SRV-8, SRV-9 |
| Snapshots/clones | ZFS/LVM/qcow2 | none (OFS has a journal, no CoW) | NONE | SRV-9 |
| Backups | vzdump + PBS | `backup.fi` (encrypted, verify, single file restore) works on trees, no ctr wrapper, no schedule | PART | SRV-9 |
| Resource limits | cgroups v2: cpu, mem, io, pids | mem + cpu share measured; procs built not measured; io/files/sockets none | PART | SRV-8 |
| Container network | veth + bridge + NAT, IPs, DHCP, DNS | none: one global stack, no loopback device, only `netview` modes | NONE | SRV-7 |
| Firewall | nftables/pve-firewall | eBPF engine (`ebpf*.fi`) with verifier limits (no tnum), socket hook built not attached | PART | SRV-7 |
| Security | caps, seccomp, apparmor, userns | T_UID global, no caps, no seccomp, no userns, no_new_privs missing | NONE | SRV-8 |
| Monitoring | RRD graphs, status | `ctr show`/`top`, kernel counters; taskmgr S5 planned (MON) | PART | SRV-12 |
| Updates host | apt + kernel + reboot | OTA signed, A/B + trial boot via ESP (UPD plan), kernel updatable only via `ota system` | PART | SRV-13 |
| Updates containers | apt inside | none | NONE | SRV-13 |
| Cluster/HA | corosync, pmxcfs, live migration | none | NONE | SRV-15 (optional) |
| VMs | KVM/QEMU | hv.fi AMD-V only, Linux panics at root | PART | SRV-14 |
| Linux userland | any distro | musl dynamic ELF OK (busybox 55/1, python 11/11); in-container unmeasured; glibc unknown | PART | SRV-6 |
| Server hardware | any | NVMe/AHCI, e1000/r8169, virtio; no 10G/Mellanox, no IPMI/BMC, ECC/MCE unknown | PART | SRV-16 |
| Dauerbetrieb | watchdog, logrotate | fail-counter in init; no watchdog, no logrotate, no 7-day soak | NONE | SRV-4 |

## 4. Verification runs of this plan (21.10.2026)
- `tools/server/build.sh`: ok 34 s. `tools/container/run.sh`: 52/0, 40 s. 3x headless boot: 1.34/1.38/1.45 s. Idle RAM at 3 memory sizes. Network ping, `svc`, `ctr create/set/start/exec` on an extended image.
- `tools/hv/run.sh` and `tools/server/run.sh` (22 checks) results: see the report of this worker (`reports/20261021-140345_orientos-w-srv-plan-server-edition-n.md`).

## 5. Milestones
IDs below are new roadmap items (group "SRV"); existing items they cover are named so nothing is counted twice.
| ID | Task | Dep | Eff | Risk | Owner | Gate (with counter-proof) |
|---|---|---|---|---|---|---|
| SRV-0 | Scoreboard `tools/server/measure.sh`: build time, kernel/disk size, boot-to-prompt (3 runs), idle frames, network ping; writes metrics and a BENCH-1 column "server" | BENCH-1 (r1419) optional | S | low | H | one command, numbers stored; counter-proof: GUI kernel gives bigger numbers |
| SRV-1 | Make the image a server: default PROGS incl. init svc sshd dhcp ctr ota backup sntp host dnswt netstat; `/etc/inittab` (serial login respawn, dhcp `netz`, sshd), `/etc/ziel`=konsole, `/var/log`, `/run`, hostname, OFS v3 root (fixes F1-F7, `cp` keeps mode or `install` tool, /proc mounted) | - | M | low | S | `tools/server/boot.sh`: boots through init, `svc` shows services running, login on serial, `/proc/meminfo` reads; counter-proof: image without inittab must fail the gate |
| SRV-2 | Headless installer + loader: GPT + ESP + OFS v3 root, Limine entry with `console=ttyS0`, no menu wait, A/B kernel slots, runs on SeaBIOS + UEFI | SRV-1, UPD-1..3 (r1421-r1423) | M | med | S | install to blank disk, reboot, serial login, rollback on a bad kernel; counter-proof: broken kernel in slot B falls back |
| SRV-3 | Remote admin over ssh: host key at first boot, `authorized_keys`, non-root admin user, `scp`-style file copy (check what `sshd` lacks: sftp/exec/port-forward), ssh in inittab | SRV-1 | M | med | S | `tools/sshd/run.sh` against the real server image with OpenSSH client; counter-proof: wrong key refused |
| SRV-4 | Unattended operation: watchdog (software + i6300esb/virtio on QEMU, real HW via ACPI/TCO later), logrotate, panic -> reboot, kernel log to disk, time sync (`sntp`), `/etc/net.conf` instead of cmdline, soak test run in stages (heavy cap is 180 min: soak runs outside heavy on a private VM, report uptime) | SRV-1 | L | med | S | watchdog kills a hung init in QEMU and the machine reboots; 24 h soak first, 7 days later (r1144); counter-proof: no watchdog = hang stays |
| SRV-5 | Container runtime v1: tar/tar.gz template unpack (`ctr create --template`), hostname (uts), autostart list `/etc/ctr/*.conf` driven by init, ordered start/stop with kill of all processes, `ctr exec -t` with pty attach, MAX_CTR 8 -> 64, MAX_TASKS up (r344, LA-2 r1367), measure `procs` and `cpu` limits in the gate (closes the 2 unmeasured items) | LC-C1 (r745), LA-2 | L | high (kernel tables) | S | container gate extended (new `ctr2` gate): template unpack, autostart after reboot, stop leaves 0 processes, cpu share 10 vs 90 measured within 20 %; counter-proof: without limit the shares are equal |
| SRV-6 | Linux userland in a container: Alpine minirootfs (musl, busybox) as template; per-ctr `/proc` and `/dev` (null zero urandom tty pts), musl loader inside the jail, uts name; then 20+ busybox probes, python3 stone, curl stone **inside** the container. Debian/glibc: probe only, result into the plan | SRV-5, LA stones (done), LC-F1 (r753) | M | med | S | `tools/server/alpine-ctr.sh`: busybox probes pass inside ctr; counter-proof: same probe fails outside the jail path |
| SRV-7 | Container network: virtual netdev (veth pair), loopback device, L2 bridge with learning, IP per container (second address / per-ctr stack view), NAT masquerade + port forward, DHCP + DNS for containers, write-side netlink for `ip` | SRV-5, LC-C5 (r749); collides with netzplus/ebpf files | XL | high | S | QEMU: two containers ping each other and the host, one reaches the QEMU gateway through NAT, host:8080 forwards to ctr:80; counter-proof: with `net none` nothing passes, ctr A cannot see ctr B's sockets without the bridge |
| SRV-8 | Isolation + limits: pid namespace (virtual pids, pid 1 per ctr), uid mapping/userns, capabilities, `no_new_privs`, seccomp (cBPF -> eBPF), mount table per ctr (bind mounts), device whitelist, limits for files/sockets/IO/disk quota, escape suite that counts attempts | SRV-5, LC-C2/C3/C4/C7 (r746, r747, r748, r751) | XL | high (sys.fi/proc.fi shared with W-LA) | S | `tools/container` escape suite >= 30 attempts, `escapes=` equals attempts, 0 successes; counter-proof: each protection switched off lets its attempt pass |
| SRV-9 | Storage: (a) `ctr backup/restore` wrapper over `backup.fi` with verify + schedule (M), (b) clone from template without copying (layers/overlay, LC-C6 r750 interim "unpack layers without union") (L), (c) snapshots (journal today, no CoW: design decision), (d) per-ctr quota | SRV-5, TRESOR (done) | L | med | S | backup -> destroy -> restore -> `verify` byte-identical; clone of a 20 MB template in < 1 s and 0 extra data blocks; counter-proof: flipped byte in the backup is detected |
| SRV-10 | Management CLI + API: one umbrella tool (`osumctl`: ctr, svc, ota, backup, net, host) with English output and `--json`, local API over unix socket/orientbus (rpcd), auth = unix permissions; remote via ssh first, HTTPS API later (needs TLS server side: unverified, check `lib/tls`) | SRV-5 | M-L | med | S | JSON contract tests for every command; counter-proof: non-root user is refused on write commands |
| SRV-11 | Web UI: registry-driven (route manifest of lib/nav -> sidebar, pages = containers, storage, network, tasks, updates). Two ways, Boss decides: (A) HTTP(S) server in Firn serving a small SPA on the API, (B) native fUi "Server Manager" app that talks to the API (desktop edition as client), (C) reuse the JARVIS bridge (outbound, no inbound port) | SRV-10, TK-3..6 (r1447-r1450), HTTP server lib (missing) | XL | high | S | page load, create/start/stop a container via UI in QEMU, screenshot gate; counter-proof: unauthenticated request gets 401 |
| SRV-12 | Monitoring: per-container counters (mem peak, cpu ticks, procs, net bytes, deny counts) as machine-readable `/proc`-like files, metrics endpoint (text), simple alerts via notify, taskmgr kernel counters (MON-1, TM-S5) as common source | SRV-5, MON-1 (r1403), TM-S5 | M | low | S | counters equal the stress probe's known load within 5 %; counter-proof: idle ctr reports ~0 |
| SRV-13 | Updates: server OTA on A/B with health check (ssh/API answers within N s, else rollback), `ctr update` for container templates from the signed feed (opk reuse), kernel stays separate; re-measure AVX-512 on Zen 4/5 HW (fetch died on AVX-512 before RUNDE-AVX) | SRV-2, UPD-1..5 (r1421-r1425) | L | med | S | VM: update, reboot, health fails on purpose -> rollback; counter-proof: unsigned package refused |
| SRV-14 | Hypervisor to VMs (Proxmox-VM part): virtio-blk, virtio-net, virtio-console as *device models*, initramfs/rootfs for guest, ACPI + IOAPIC (SMP guests), TSC/HPET, then snapshots; Intel VT-x as separate step (servers are often Intel) | HV3 (done), r752, r1146 | XL | high | S | Debian guest reaches an initramfs shell on the serial line; counter-proof: without virtio-blk it panics as today |
| SRV-15 | Cluster (optional, park): membership, replicated config, restart-migration of containers on shared storage | SRV-10, SRV-9 | XL | high | S | parked until SRV-1..10 are green |
| SRV-16 | Server hardware: NIC drivers (Intel i40e/ixgbe, Broadcom, Mellanox), NVMe multi-queue check, RAID/mirror (mdraid-like), IPMI/BMC, ECC/MCE reporting, more than 8 CPUs; driven by the real target machine | SRV-2, Boss: target hardware | XL | high | S | on real hardware only; QEMU models where they exist |

## 6. Order and critical path
```
Phase S0  SRV-0                                  (hours, anytime, behind Phase 0 of the desktop plan)
Phase S1  SRV-1 -> SRV-2 || SRV-3                (a manageable headless machine; M each)
Phase S2  SRV-4 || SRV-5 -> SRV-6 || SRV-9a      (containers with Linux userland + backup)   <== SERVER MVP
Phase S3  SRV-10 -> SRV-12 -> SRV-13             (API, monitoring, updates)
Phase S4  SRV-7 || SRV-8                         (network + isolation; XL, touches shared kernel files)
Phase S5  SRV-11 (UI), SRV-9b/c, SRV-14 (VMs), SRV-16 (hardware), SRV-15 (park)
```
- **Server MVP** = SRV-0..6 + SRV-9a + SRV-10 (CLI part): headless install, ssh, init services, containers from templates with an Alpine userland, backup/restore. Estimate: 14-22 worker-days (writer's estimate from the S/M/L scale, not measured).
- It must not block the desktop: SRV work touches `kernel/user/{ctr,init,svc}.fi`, `kernel/sched/ctr.fi`, `tools/server`, `tools/container`; collisions with W-LA (sys.fi, proc.fi, MAX_TASKS) and W-STAB (ota.fi) must be resolved by one-worker-per-file; start SRV-5 only after LA-2 landed.
- Parallelism: SRV-2 || SRV-3, SRV-6 || SRV-9a, SRV-7 || SRV-8 (but both want `sys.fi`: sequence them).

## 7. Dependencies
- **Linux compat (LA / LC):** SRV-5 needs LA-2 (MAX_TASKS) and LC-C1; SRV-6 needs the stones (done), LC-F1 and LC-F2 (`*at` dirfd, glibc/Go); SRV-7 needs LC-C5; SRV-8 needs LC-C2/C3/C4/C7; SRV-14 = LC-C8. LA-1 (OFS file size) is also the server's file limit.
- **Toolkit:** SRV-11 uses the navigation toolkit (route manifest, sidebar, search) from TK-3..6; the server manager pages are one more `ROUTES` manifest, not a new framework. SRV-10's CLI shares the manifest style of `lib/settingsman` (errors, rollback).
- **UPD / OTA:** SRV-2 and SRV-13 reuse UPD-1..5 and `ota system` (A/B slots on the ESP).
- **MON / TM:** SRV-12 consumes the kernel counters of MON-1 and Task Manager S5; no second counter system.
- **BENCH:** SRV-0 adds a server column to BENCH-1.

## 8. Risks
1. **MAX_TASKS = 32 and MAX_CTR = 8** (kernel tables, kdata offsets): containers multiply tasks; raising them touches kdata layout (see the CTR_OFF map fix in the container round). Biggest technical risk; shared with Firefox (LA-2).
2. **One global network stack** (inet.fi, netdev.fi): per-container IPs and bridge touch the files netzplus/ebpf work on. Needs a design spike before SRV-7 (S).
3. **Global T_UID**: uid 0 in a container is uid 0 on the host today; admin calls require "caller in host" instead. Real userns is large (LC-C7).
4. **Kernel-shared isolation**: like LXC, a kernel bug escapes. No VM boundary until SRV-14 (AMD-V only).
5. **Soak vs heavy cap**: 7-day uptime cannot run under `heavy` (max 180 min): needs a private VM outside the wrapper or staged runs; report honestly.
6. **No HTTP/TLS server side verified**: SRV-11 option A needs it; option C (bridge) avoids inbound ports.
7. **OFS** (v2 test disk 2 MB files; v3 130 MiB; journal, no CoW): clones/snapshots need a design decision; wrong choice costs weeks.
8. **Intel-only servers**: hv.fi is AMD-V; if the target is Intel, SRV-14 grows by a VT-x port.
9. **German legacy in server tools** (`ctr.fi`, `init.fi` comments, "angelegt", "fehlt"): English ratchet counts them; new server code English, old text migrated when touched (ENG plan).
10. **Time/hardware:** real-hardware validation is Boss-only (no server hardware connected; laptop offline).

## 9. Decisions for the Boss (recommendation first)
1. Container first (LXC style, SRV-5..9) before VMs (SRV-14): **yes** — usable server in about 3 weeks of worker time vs months.
2. Management UI: **CLI + API + ssh first (SRV-10), web UI later via the JARVIS bridge or a native fUi Server Manager** — no inbound HTTP server until needed.
3. Target hardware for SRV-16: which server (Intel/AMD, NICs)? Needed before SRV-14 and SRV-16.

## 10. Roadmap map
| WS | IDs -> roadmap |
|---|---|
| SRV | SRV-0..16 -> r1462-r1478 (group "SRV"). Existing and kept: r1143-r1148 (Server-OS epic S1-S5, now sub-tasks of SRV), r745-r752 (LC-C1..C8), r898 (AR-3), r410, r344 |
