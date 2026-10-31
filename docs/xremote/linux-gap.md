# X-Remote host on Osum via Linux compatibility: feasibility (31.10.2026, measured)

Scope: FreeViewer/X-Remote 0.30.0 (repo c72836d) as an unmodified Rust Linux x86_64 host running on Osum through the Linux ABI layer, shipped as a Store/OTA package (not built into the image). Nothing was built into Osum; this is a measurement.

## 1. The binary

| Item | Result |
|---|---|
| Build | `cargo build --release --locked --features license --bin freeviewer`, LTO off, via heavy, 2m36s. 36.9 MB stripped, PIE |
| Target | `x86_64-unknown-linux-gnu`: glibc, interpreter `/lib64/ld-linux-x86-64.so.2`, symbols up to `GLIBC_2.35` |
| NEEDED | libopus.so.0, libgbm.so.1, libxcb.so.1, libasound.so.2, libgcc_s.so.1, libm.so.6, libc.so.6 (+ transitive: libdrm, libwayland-server, libexpat, libXau, libXdmcp, libffi, libbsd, libmd) |
| Runtime `dlopen` (GUI only, not needed for `--headless`) | libvulkan.so.1, libEGL.so.1, libX11, libwayland-client/-egl, libxkbcommon(-x11) |
| Host mode | `freeviewer --headless` (no window, prints ID); env `FV_RELAY`, `FV_PASSWORD`, `FV_ALLOW_INSECURE_RELAY=1` for a `ws://` test relay; `FV_TESTHOST=1` replaces capture + input with a synthetic 640x480 screen |
| musl build | target `x86_64-unknown-linux-musl` installed; build with default features FAILS at `alsa-sys` ("pkg-config has not been configured to support cross-compilation"); `pipewire-sys`/`libspa-sys` (xcap) and `audiopus_sys` are next in line. Needs a host-only Cargo feature that drops cpal/xcap/pipewire/eframe, or an Alpine sysroot with dev files |

Osum's working Linux userland is musl (`ld-musl-x86_64.so.1`, Alpine roots, tools/linuxapps). A glibc binary needs glibc `ld.so` + libs in the package; a musl-dynamic build is the natural fit.

## 2. What the host does on Linux (strace -f, local node relay)

Verified end to end on Linux: relay register, ID, auth, E2E AES-GCM, frames to a second `freeviewer --connect` process. Works with the synthetic screen and with real X11 capture (Xvfb).

66 distinct syscalls (union of 4 traces, ~104k calls in the X11 host trace):
futex (WAIT_BITSET/WAKE/WAIT/UNLOCK_PI), mmap/mprotect/munmap/madvise/brk, clone3 (threads: CLONE_VM|FS|FILES|SIGHAND|THREAD|SYSVSEM|SETTLS|PARENT_SETTID|CHILD_CLEARTID; one CLONE_VM|CLONE_VFORK for `hostname`), rseq, set_robust_list, sigaltstack, rt_sigaction/sigprocmask, prctl (PR_SET_NAME, PR_CAPBSET_READ), sched_getaffinity, prlimit64, epoll_create1/ctl/wait, eventfd2, pipe2, poll/ppoll, socket/connect/sendto/recvfrom/sendmsg/recvmsg/getsockopt/setsockopt/shutdown/getpeername (AF_INET non-blocking stream, AF_UNIX stream incl. abstract names), ioctl FIONBIO, fcntl (F_GETFD/SETFL/DUPFD_CLOEXEC), openat/newfstatat/statx/readlink/symlink/mkdir/umask/getdents64/ftruncate/lseek/pread64, memfd_create, getrandom, clock_nanosleep, execve+wait4 (`hostname`), uname, getuid/gid/pid/tid, arch_prctl, set_tid_address.
Files read: `/sys/devices/system/cpu/online`, `/proc/self/maps`, `/proc/self/cgroup`, `/sys/fs/cgroup/**/cpu.max` (Rust std/tokio CPU count), `~/.config/freeviewer/*`, `~/.Xauthority`, `/usr/share/alsa/alsa.conf`, `/dev/snd/*`.
Not used: shmget/shmat (no MIT-SHM), uinput, DRM ioctls, pipewire, Wayland sockets, ffmpeg. Threads: one tokio worker per CPU plus helpers (~100 on the 96-core build server).
Network: relay over `wss://` (rustls + webpki roots, no system CA bundle), DNS via tokio `getaddrinfo`, update check, public-IP probes to 1.1.1.1:443 / 8.8.8.8:443.
Capture: xcap over X11 (new X connection per frame: 3278 `connect` calls in 30 s). Input: enigo over X11 XTEST. Neither exists on Osum (no X server; wayd is Wayland only, no screencopy / virtual-pointer / virtual-keyboard protocols).

## 3. Gap table against Osum (main 36877969: kernel/sys/sys.fi, tools/unterbau, tools/wayland, tools/linuxapps, tools/dynlader)

ok = implemented; partial = present with known limits; missing = absent; unknown = untested.

| Need | Osum | Status |
|---|---|---|
| glibc `ld.so` as PT_INTERP via execve | `elf: interp /lib64/...` then execve ENOEXEC (nr59 e8) | missing (section 4) |
| glibc `ld.so` started explicitly | maps binary + 16 libs, then user fault `rip=0x4011dca0 cr2=0x0` inside ld.so | partial (section 4) |
| Large file mappings (36.9 MB, 4.2 MB) | worked | ok |
| futex WAIT_BITSET/WAKE | present, polled every 10 ms, no REQUEUE | partial |
| FUTEX_UNLOCK_PI | no PI | missing (seen once) |
| clone THREAD/FILES/SETTLS | present | ok |
| clone3 (435) | not in table; glibc falls back to clone | missing, tolerated |
| rseq (334) | ENOSYS seen in trace; glibc tolerates | missing, tolerated |
| statx (332) | not in table; glibc falls back to newfstatat | missing, tolerated |
| restart_syscall (219) | not in table | missing, rare |
| sigaltstack, set_robust_list, sched_getaffinity, prlimit64, madvise | present | ok |
| openat family, newfstatat, readlink, symlink, mkdir, getdents64, ftruncate, pread64 | present (LC_OPENAT..LC_READLINKAT) | ok |
| epoll LT/ET, eventfd2, pipe2, ppoll/poll | present; EP_MAX 80 | partial |
| ~100 tokio threads | MAX_TASKS 128 (t_limits 124 threads) | partial |
| AF_UNIX stream, sendmsg/recvmsg, SCM_RIGHTS | present; abstract-namespace names untested | partial |
| AF_INET non-blocking connect, SO_ERROR, TLS client | present (curl/https stone) | ok |
| DNS via glibc getaddrinfo/NSS | musl resolver ok; glibc NSS dlopen untested | unknown |
| `/proc/self/maps`, `/sys/devices/system/cpu/online`, cgroup `cpu.max` | maps without names; cpu/online present; cgroup absent | partial |
| `/dev/snd`, ALSA | none; libasound errors are non-fatal (audio off) | missing, tolerated |
| memfd_create | present with seals | ok |
| X11 socket / XTEST | no X server | missing, not planned |
| Screen capture | native `osum_shot` (1841): SH_INFO/SH_ARM/SH_GRAB, one-shot permit from taskbar/root; wayd has no screencopy | native path exists, no Linux API |
| Input injection | native `SYS_TIPP` (keys, mouse), emergency stop `input off`; no uinput / virtual-pointer / virtual-keyboard | native path exists, no Linux API |
| `hostname` helper (execve) | busybox in package | ok if shipped |
| Store/OTA package with "newest release" feed | stones/OTA exist, feed for foreign binaries not built | missing |

## 4. Run under Osum (QEMU KVM, kernel stufe 0 of main, Alpine base + Debian glibc 2.36 libs + the binary)

`tools/linuxapps/run.sh` with a custom spec and guest script. Result:
1. `/lib64/ld-linux-x86-64.so.2 --list /opt/fv/freeviewer`: ld.so starts, maps the binary and 16 libraries (9 ENOENT `openat` probes while searching, expected), `rseq` ENOSYS (tolerated), then `user fault: vector=14 err=0x5 cr2=0x0 rip=0x4011dca0` inside ld.so, "Segmentation fault". Cause not identified (candidates: auxv entries glibc expects such as AT_RANDOM/AT_PLATFORM/AT_HWCAP2/AT_MINSIGSTKSZ, TLS setup, cpuid-based cpu features).
2. `/opt/fv/freeviewer --version` and `--headless`: `elf: interp /lib64/ld-linux-x86-64.so.2`, then execve returns ENOEXEC (`sys: FAIL nr59 e8`); busybox ash then tries the file as a script. A glibc-interpreter binary is rejected at exec although ld.so runs when started by hand. Reason code in kernel/ldr/elf.fi not yet read out.
3. No host logic ran. No NIC in this harness, so no relay test.

Artifacts (server): /root/jarvis/data/staff_wt/orientos/x1-out/ (freeviewer-glibc, strace-*.txt, osum1/ser.clean).

## 5. Verdict and plan

Feasible, not trivial. Session logic is plain Rust + tokio + rustls and needs 66 syscalls; a naive table scan flagged 17 as missing but 12 exist (epoll, openat, ...). Real misses are clone3, rseq, statx, restart_syscall and PI futex, all survivable by glibc. Blockers: (a) glibc exec/ld.so path, or instead a musl-dynamic build; (b) no capture/input backend that fits Osum; (c) the default build pulls GUI/audio/PipeWire libs.

Recommended route: musl-dynamic build with a host-only Cargo feature plus an Osum backend (native `osum_shot` + `SYS_TIPP`) instead of fixing glibc.

- X2 (r2459) FreeViewer: feature `host-only` (no eframe/wgpu, cpal, xcap, pipewire, rfd, arboard), runtime-selected `osum` capture/input backend, musl-dynamic build against an Alpine sysroot, headless host + `--connect` test through the Osum NIC to a relay.
- X3 (r2460) Osum kernel, optional glibc target: execve ENOEXEC for glibc PIE interp (kernel/ldr/elf.fi), ld.so crash at rip 0x4011dca0 (auxv/TLS), clone3/rseq/statx/restart_syscall stubs, FUTEX_UNLOCK_PI, abstract AF_UNIX names, cgroup cpu.max fallback.
- X4 (r2461) Capture/input bridge: helper over AF_UNIX using the permit from the taskbar, `osum_shot` grab and `SYS_TIPP`, with Super+Esc / `input off` stop; or screencopy + virtual-pointer/keyboard in wayd.
- X5 (r2462) Packaging: Store/OTA package pulling the newest signed release from the FreeViewer feed (Ed25519, `version-xoffi.json`), install under `/apps`, Settings switch, gate `tools/xremote/run.sh` (Rust client `--connect` against the Osum host with a local node relay).

## 6. Re-measurement X3 (31.10.2026, tools/unterbau/t_x3.c, QEMU KVM, kernel of main d0e7a932)

| Need | Measured | Status |
|---|---|---|
| FUTEX_LOCK_PI / UNLOCK_PI / TRYLOCK_PI | implemented in kernel/sched/futex.fi, t_futex pi_* PASS | ok (table row in section 3 is stale) |
| statx | implemented, t_misc statx_* PASS | ok (stale) |
| clone3 (435), rseq (334) | ENOSYS, glibc falls back to clone / runs without rseq | ok, tolerated |
| restart_syscall (219) | EINTR | ok |
| abstract AF_UNIX (stream + dgram) | before: bind/connect EINVAL; fix in sa_un keeps the leading NUL and the exact length | fixed on branch |
| getsockname / getpeername on AF_UNIX | before: EBADF; fix returns bound name, accepted sockets borrow the listener name | fixed on branch |
| auxv AT_PLATFORM / AT_HWCAP / AT_EXECFN | before: missing (0); fix adds them plus AT_HWCAP2 (0) | fixed on branch |
| cgroup cpu.max, /proc/self/mountinfo, /sys/fs/cgroup | ENOENT, clean | ok |
| cpuid, xgetbv, ymm state across switches, TLS (fs base, per-thread) | PASS | ok |
| name table size | UNAME_MAX 16 abstract + path names together | open |
