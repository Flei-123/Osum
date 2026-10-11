# ACCEL — what OrientOS lacks to develop faster (analysis + plan, 11.10.2026)

Method: 5 read-only sub-agents (A kernel, B dev loop, C QA, D libs/APIs, E process; raw output: `data/projects_kb/orientos/reports/ACCEL-raw.txt`),
then the manager re-measured on `origin/main` (f4491e38) with `git grep`/`git ls-tree`, `du`, `heavy.conf` and one timed kernel build.
**Caveat:** the sub-agents had no shell and read an OLD tree (branch runde-clip2, Aug/Sep docs). Their claims were checked; corrections are marked **[korr]**.
Unknown = `unbekannt`. Effort S/M/L/XL, lever on dev speed 1-5. Effort/phase numbers are estimates.

## 1. Measured facts (manager, origin/main f4491e38, 11.10.2026)
| What | Value | How |
|---|---|---|
| Kernel build (`tools/build-kernel.sh`, gui=on, tunnel=on) | **58.5 s wall, 43.6 s user, 77 % CPU = single-threaded**, 467 MB RSS, image 8.49 MB (elf 10.4 MB), 116 279 symtab lines | `time heavy bash tools/build-kernel.sh` |
| Source size | kernel/user 188 954 lines, tools 166 424, docs 78 691, kernel/ui 34 129 (`wm.fi` **17 548**), kernel/drv 28 167, kernel/sys 19 091, lib 34 317, kernel/net 10 672, kernel/mm 1 292, kernel/diag 4 094 | `git grep -c ''` |
| Window server in ring 3 | `kernel/user/wmd.fi` 1 887 lines (shadow/chrome compositor, S5/S6 gates exist), **[korr]** A-02 "unbekannt" is wrong; `docs/COMPOSITOR.md` exists | git ls-tree |
| Gates | **345** shell scripts in `tools/`, **158** `run.sh`, 179 tool dirs; `test.sh` 1 760 lines, **90** `lauf` sections (sub-agent said 36 = outdated) | git ls-tree / grep |
| `pruef/` at repo root | 600 files (probe/selbst/durchklick one-offs) | git ls-tree |
| a11y | `tools/a11y/` exists, A11y-Abnahme 58/0, `uitrace` used in 4+ kernel files **[korr]** D-29/B-16 "not found" | git grep |
| Unterbau suite 249/315 | lives ONLY on branch `unterbau` (`tools/unterbau`, 20 files), **not on main** — results/fixes unmerged | git ls-tree unterbau |
| Debug primitives | ptrace: 0 hits; gdbstub/kdb: 0 hits (only `bsect.fi` mentions); inotify/file watching: 0 hits; WebSocket: 0 hits; `crash.fi` writes `/var/crash/*.txt` with backtrace (needs working fs) | git grep |
| Security | NX/SMEP/SMAP in `guard.fi`; ASLR only in bzload/hv (kernel image, not processes); `mprotect` has `do_mprotect` since RUNDE FREMDLAND (semantics per-page not verified) | git grep |
| TLS 1.2 / IPv6 | strings present in `lib/tls`, `lib/wg`, `host.fi`; actual support level `unbekannt` | git grep |
| Repo hygiene | 53 local + 35 remote branches, **32 remote branches not merged**, 23 worktrees, `.git` 226 MB, repo root has 4 `0x…` dump files + ~12 `.*-shots` dirs | git branch / worktree |
| Disk | / 128 G, 108 G used (88 %), block at 90 %. **OrientOS is NOT the main consumer**: `/root/abbilder` 636 MB (88 files), staff_wt 987 MB, each `/root/osum-*` ≈ 113 MB (r537 232, ota-run 260). Big: `projects/u_LEr0ak0rPw/hotel` 15 G, `riemannlab` 7.9 G, `/root/projects` 5.7 G, `jarvis/downloads` 4.9 G, `.claude/projects` 4.3 G, containerd 6.2 G, android-sdk 3 G, /tmp 1.8 G | `du -x` |
| Server | 20 cores, 39 GB RAM (18 free), heavy: 8 slots, load ≤ 40, 90 min limit; queue was 0 at 19:52, 14 earlier | heavy.conf / --status |
| Dev velocity | 341 commits on main in 7 days | git log |

## 2. Findings (by area; verified items only; IDs from sub-agents kept where still valid)
### A Kernel / platform
| ID | Finding | Evidence | Impact | Eff | Lever | Dep |
|---|---|---|---|---|---|---|
| A-01 | Window server still mostly ring 0: `wm.fi` 17 548 lines in kernel; WM bug = kernel panic, every WM test = kernel rebuild (58 s) + boot. wmd (1 887 lines) only does shadow/chrome/compose parts. | wc, wmd.fi, COMPOSITOR.md | Slow, risky iteration on the most-edited area | XL | 5 | A-12 |
| A-04 | Crash report exists (`crash.fi`: regs, symbolised backtrace, last 50 klog lines) but only when fs works. No raw-partition/ring-buffer dump surviving warm reboot (pstore/kdump analogue). | kernel/diag/crash.fi | Dell hangs/panics need a photo of the screen | M | 4 | — |
| A-06 | No interactive debugger: no ptrace, no gdbstub/kdb. Only QEMU `-d`, serial lines, klog. Dell has no UART (LSR 0xFF). | git grep 0 hits | Triple faults/hangs cost hours | M | 4 | A-04 |
| A-08 | Hang detection = measurement line only; no watchdog with reset+dump. | RUNDE-HAENGER | Each hang = photo round-trip with Boss | S | 4 | A-04 |
| A-12 | Moving window server to ring 3 needs per-window shared buffers + Wayland/wmd path (partly there: shared/shadow/chrome gates). | docs/COMPOSITOR.md | Biggest structural speed lever (stability + test time) | XL | 5 | A-01 |
| A-14 | No Wi-Fi driver (stack done, `lib/wlan/device.fi` seam, chip unknown), no USB classes beyond HID/storage, no native GPU modesetting (virtio/GOP/Bochs only), no AML interpreter. | kernel/drv, STATUS-WLAN2 | Real-hardware gaps; not dev-speed but blocks daily use | L-XL | 2 | Boss: photo of `wifi-usb:` line |
| A-20 | W^X for processes / ASLR / sandbox: partly (NX, SMEP/SMAP; mprotect real now), per-process ASLR and seccomp-like sandbox missing; roadmap S-010. | guard.fi | Security debt, blocks Store trust model | M | 2 | D-17 |
| A-22 | Kernel memory map by hand (`kdata *_OFF`, `memmap.py` ~127 ranges); branch collisions seen (S_PXSUM, WL_SCRATCH). | MERGE-9 reports | Merge conflicts | S | 3 | E-10 |
| A-24 | Tick 100 Hz (`sleep_ms(1)` = 10 ms); kernel stack 78 % full; futex without wait queue. | AUDIO §5b, VIELKERN | Latent bugs/perf | M | 3 | — |
| A-30 | No tracing/profiler (ftrace/perf-like, sampling): `pmon`, `netmon`, eBPF exist, kernel function trace `unbekannt`. | git grep | Perf work (frame time) by guesswork | M | 3 | — |

### B Dev tempo
| ID | Finding | Evidence | Impact | Eff | Lever | Dep |
|---|---|---|---|---|---|---|
| B-01 | **No build cache**: kernel is recompiled whole on every build (58.5 s, single-thread). `firnc` has no partial compile / per-module cache. Gates rebuild the kernel again (each gate calls the same build). | measured; build-kernel.sh | ~1 min × (every gate × every worker); `freestanding` 40 s / `core` 62 s are compiler-bound (TESTFAST) | M | 5 | key = source hash + `vendor/firn/COMMIT` + FIRNLIB |
| B-02 | Kernel images could be built ONCE per commit and reused by all gates (artifact store keyed by hash) — today each `run.sh` builds its own. | tools/*/run.sh calling build-kernel | Gate time −1 min each, disk | M | 5 | B-01 |
| B-03 | No data-driven "affected gates" map (file → gate). `OSUM_NUR` is manual and not an acceptance. | test.sh, TESTFAST | Workers run too many or too few gates | M | 4 | C-02 |
| B-04 | Dell test loop = burn stick → boot → photo. Remote path exists (bridge2: shot/input/shell, `dell_walk smoke`, OTA) but needs an INSTALLED disk; Stick root is RAM-only. Measured: command 3.3 s, kernel OTA ~9 min, root ~30 min (write throughput 26 KiB/s). | KNOWLEDGE, DELLWALK.md | Real-hardware iteration is hours | M | 5 | install on Dell (Boss), r581 write speed |
| B-05 | `opk` slow: 130 s / 569 KB package, 8 packages 35 min (cause unmeasured: SHA-512/256 vs OFS journal). | RUNDE-LADEN | OTA dev loop | M | 4 | TSC profile |
| B-06 | No userland hot reload: `ota` ends with "ready for reboot"; no dev-push "replace binary + respawn app" (bridge has write/exec but no dev profile). | OTA.md, BRIDGE.md | Every app change = reboot or package path | M | 4 | init respawn |
| B-07 | Logs: klog ring only 510×128 B, volatile; no persistent `/var/log` for kernel, no network export (netconsole). Dell has no serial. | klog.fi | Post-mortem impossible without photo | S-M | 4 | A-04 |
| B-08 | Inspector for fUi scene tree exists partly (a11y names, `uitrace`) but not as a bridge API (`ui dump`: windows, rects, text); tests use OCR/pixel search. | tools/a11y | Fragile UI tests | M | 4 | — |
| B-09 | Netlock for net gates is host-global (`/tmp/osum-netz.lock`, veth `v1`, ports by PID): parallel runs wait on each other (>10 min seen). | TESTFAST | Queue stalls | M | 3 | `unshare -n` per run |
| B-10 | Images not reproducible (mkfs.vfat serial), no OTA delta (inhalt-addressed store `pakete/<sha256>.opk` ready for it), package buffer static 2 MiB. | BLECH-BEREIT, RUNDE-LADEN | Big transfers over 26 KiB/s | L | 3 | — |
| B-11 | Kernel cannot be hot-updated (no kexec/A-B for kernel). | OTA.md | Kernel change = reboot | L | 3 | — |

### C QA
| ID | Finding | Evidence | Impact | Eff | Lever | Dep |
|---|---|---|---|---|---|---|
| C-01 | **No pipeline tiers**: one full `test.sh` (90 sections, serial sum ≈ 5200 s in TESTFAST era, now larger). | test.sh | Worker picks gates ad hoc → branches sit "gates open" (w-vblank, w-cursor …) | M | 5 | C-02 |
| C-02 | **No gate manifest** (name, command, duration, disk, needs-net, needs-kvm, owner paths, tier). 158 run.sh + 345 scripts in tools/ without metadata. | git ls-tree | Cannot schedule, tier, or detect flaky | M | 5 | — |
| C-03 | Known-red baseline is prose (KNOWLEDGE.md: term/multi, usbimg 44/4, ahci 2.3/7.5, lockseal flaky, aacorner scale 2, look rawcolour, pci 96/2, dell_walk Settings). No `expected-red` file; each worker re-proves "red on old main". | KNOWLEDGE.md | Every merge costs a control run | S | 5 | C-02 |
| C-04 | Time-based asserts calibrated on TCG (kernel ticks, smp 1300 ms) → false red under load/KVM. | TESTFAST | Flakes | M | 3 | — |
| C-05 | **Fuzzing only 2 places** (`tools/codec/fuzz.py`, `tools/wlan/fuzz.py`) + fsrobust corruptions; no syscall/ELF/TTF/PDF/net/fs-metadata fuzzer, no corpus/coverage. (PDF fuzz exists inside PDF-Betrachter-Abnahme per KB — separate script not found.) | git grep fuzz | Memory bugs found late | L | 4 | C-09 |
| C-06 | No perf-regression gate with history; frame-time/boot/IO numbers only in project_metric and reports. | stationaer.sh, KB | Slowdowns noticed by Boss, not by CI | M | 4 | C-02 |
| C-07 | Visual regression ad hoc (`*-shots` dirs in repo root, checkshot.py); no reference images per app with thresholds and approve flow. Repo root polluted with shots/dumps. | repo root | UI regressions slip (layout at uiscale 2) | L | 4 | — |
| C-08 | No heap guard / leak counter in kernel; canary + Firn runtime checks exist. | tools/hardening | Heisenbugs | L | 4 | — |
| C-09 | Crash triage manual (diag txt read by hand). Symbolisation exists (`ksymtab`, `.elf`) but no dedupe/bisect script. | .mess/diag | Hours per crash | M | 4 | — |
| C-10 | Real-hardware regression series missing; VM cannot show EDID/DHCP/firmware bugs (14 errors at uiscale=2 invisible). `dell_walk smoke` is the start. | BEFUND-ECHTHARDWARE-1 | Boss finds bugs | XL | 5 | install on Dell |
| C-11 | Test data / junk: 600 files in `pruef/`, `0x…` files, shots in repo; images only in `/root/abbilder`. | repo | Slow clones, confusion | S | 2 | — |
| C-12 | Unterbau suite (249/315) not on main → POSIX gaps not tracked by CI. | branch unterbau | Libc/POSIX work invisible | S | 4 | merge branch |

### D Libs / frameworks / APIs
| ID | Finding | Evidence | Impact | Eff | Lever | Dep |
|---|---|---|---|---|---|---|
| D-01 | **No SDK / project template / app manifest v2**: `assets/apps/*.osp/` has only INFO(name,info,keys,fassung), start.txt, symbol; no permissions, min-OS, services, file handlers, deps; no `osum new/build`. | assets/apps/*.osp | Third parties (and AI workers) cannot add apps quickly | L | 5 | D-02, A-20 |
| D-02 | C toolchain only as recipe (musl static + `start.s` + `osum.ld` + `osum_main.c`, base 0x40100000); no `osum-gcc` wrapper/headers package. | tools/foreign/README | Porting C software is manual | S-M | 4 | — |
| D-03 | IPC bus (syscall 1960, 22 ops: send/recv, pub/sub, segments, clipboard, DnD, notify) but **no request/reply, no blocking recv, no activation, no IDL**. | docs/SYSTEMBUS.md | No service API (D-Bus/FIDL-like) → app services impossible | L | 5 | init |
| D-04 | `dlopen(file)` missing (`mmap(fd)` only for /dev/fb, fixed `INTERP_BASE`). | RUNDE-DYNLADER §10 | No plugins, no Python/JS extensions, no GUI toolkits | L | 5 | file-backed mmap |
| D-05 | Init: inittab, max 16 services, no dependencies except `netz`, no user services/socket-bus activation. | docs/INIT.md | App services limited | M | 4 | D-03 |
| D-06 | Store chain not end-to-end: no key revocation/rotation, secret key unencrypted on build machine, no deltas, no dependency resolver, HTTPS/DNS not fully in standard image. | docs/UPDATE (STATUS) | Store cannot ship to users | L | 4 | B-10 |
| D-07 | fUi: node limit/virtualised list/tree/table/dialog **unbekannt** (not verified); `wlib` has list/table/tabs/menu. Settings/Store redesign workers are exercising this right now. | wlib, FUI-STAND | Big lists in Store/Explorer | M | 4 | Store redesign report |
| D-08 | No app-facing canvas API (paths, gradients, alpha), no 3D app API (software `r3d` only), no GPU. | kernel/gfx | Games/graphics apps | L | 3 | — |
| D-09 | POSIX gaps: futex wake-up without queue, fds copied on clone (not shared), `F_SETLKW` doesn't wait, tick 100 Hz. **[korr]** mprotect now implemented. | FREMDLAND | Portability | M | 3 | — |
| D-10 | Net API: no WebSocket, no inotify-like file watching, TLS 1.2/IPv6 `unbekannt`, no DNS resolver config in images; Certus WebView widget `unbekannt`. | git grep | App dev blocked | M-L | 3 | — |
| D-11 | Language bindings: only Firn + C(musl); Lua/QuickJS run as console programs; no binding to wlib/bus/audio. | FREMDLAND | Scripting apps | L | 3 | D-04, D-03 |
| D-12 | i18n only de/en (72 keys), no RTL/CJK/plurals; printing absent; accessibility API exists (a11y baum) but no screen reader (P-016). | I18N.md | Later | XL | 2 | — |

### E Process
| ID | Finding | Evidence | Impact | Eff | Lever | Dep |
|---|---|---|---|---|---|---|
| E-01 | `heavy` works (8 slots, FIFO, load ≤ 40, 90 min, disk block 90 %). Peaks: queue 14 waiting. A 58 s single-thread build and 8-core box: slots are not the limit, **gate length + duplicate builds are**. | heavy.conf, build time | Waiting | S | 4 | B-02 |
| E-02 | **Disk pressure is not OrientOS**: OrientOS dirs ≈ 3 GB total (abbilder 636 MB, staff_wt 987 MB, osum-* worktrees ~113 MB each). Real hogs: other users' `hotel` 15 GB, `riemannlab` 7.9 GB, `/root/projects` 5.7 GB, `jarvis/downloads` 4.9 GB, `.claude/projects` 4.3 GB, containerd 6.2 GB, android-sdk 3 GB. | `du -x` | 88 % → workers blocked at 90 % | S | 5 | Boss decides what to purge/extend |
| E-03 | Branch flood: 32 remote branches unmerged, 23 worktrees, 53 local branches; same unmerged set repeats in every report (w-vblank, w-cursor, w-caret, w-login, w-present, r537, unterbau, jarvisd-idle, w-img, w5-inst). | git branch | "Gates open" debt; knowledge lost | M | 4 | merge policy |
| E-04 | Merge by hand per worker; parallel workers all rebase onto fast-moving main (341 commits / 7 days); no merge queue → conflicts + re-runs. | git log | Rework | M | 4 | C-01 |
| E-05 | Full-gate ≈ 10+ min per branch; flaky (lockseal, term/multi) and known-red cause control runs. | KNOWLEDGE.md | Time | M | 5 | C-02, C-03 |
| E-06 | No nightly full run on main; regressions found by chance. | — | Hidden red | M | 4 | C-01 |
| E-07 | Docs sprawl: ~50 STATUS-*.md in root + 175 files in docs/ + 600 in `pruef/`; workers re-read the same stuff. KNOWLEDGE.md (6 KB) is the only curated index. | git ls-tree | Reading cost, duplicated work | S | 3 | — |
| E-08 | 1 064 entries in `/root`, 20 `/root/osum-*` worktrees never reaped. | ls | Disk/confusion | S | 3 | reaper |

## 3. TOP 20 — fastest progress per effort
| # | Item | Why | Eff | Lever |
|---|---|---|---|---|
| 1 | **E-02** free disk (purge hotel/riemannlab/downloads/containerd/.claude logs or extend LVM; Boss decides) | Prevents hard blocks at 90 % | S | 5 |
| 2 | **C-03** `expected-red` baseline file + gate compares vs baseline | Kills control runs per merge | S | 5 |
| 3 | **B-01/B-02** build cache + one kernel image per commit shared by gates (key: source+firn commit) | −1 min per gate run, −disk | M | 5 |
| 4 | **C-02/C-01** gate manifest (tier, owner paths, duration, needs) + quick/full/nightly | Everything else depends on it | M | 5 |
| 5 | **E-03/E-04** merge debt: finish w-vblank/w-cursor/w-caret/w-login-rb/unterbau, then reaper for merged worktrees | Stops knowledge loss, disk | M | 4 |
| 6 | **B-03** affected-gates map (file → gate) from manifest | Quick gate in minutes | M | 4 |
| 7 | **A-04/A-08** crash dump to raw partition/ring buffer + watchdog reset+dump | Dell hangs without photo | M | 4 |
| 8 | **B-07** persistent kernel log + netconsole (UDP) to server | Real-hw post-mortem | S-M | 4 |
| 9 | **B-04/C-10** install on Dell (Boss OK) → OTA loop + nightly `dell_walk smoke` | Real-hardware series | M | 5 |
| 10 | **D-01** App manifest v2 + SDK template + `osum new/build` | Parallel app work for workers | L | 5 |
| 11 | **D-03** RPC layer on bus (request/reply, blocking recv, activation) | Service architecture | L | 5 |
| 12 | **C-12** merge unterbau (POSIX 249/315) into main, add to full gate | POSIX gaps tracked | S | 4 |
| 13 | **B-06** dev-push (replace binary + respawn) via bridge dev profile | App iteration without reboot | M | 4 |
| 14 | **B-08** `ui dump` bridge command (scene tree, names, rects) | Replaces OCR in tests | M | 4 |
| 15 | **C-06** perf gate with history + thresholds (frame time, boot, IO) | Catches regressions early | M | 4 |
| 16 | **C-05** fuzz harness (ELF, TTF, PDF, syscall, net) with corpus | Memory bugs early | L | 4 |
| 17 | **A-12/A-01** continue WM → ring 3 (wmd) | Stability + test speed | XL | 5 |
| 18 | **D-04** file-backed mmap / `dlopen` | Plugins, Python/JS | L | 5 |
| 19 | **B-05** profile `opk` (35 min / 8 pkgs), then fix write path (r581, 26 KiB/s) | OTA speed | M | 4 |
| 20 | **C-07** visual regression references per app | UI changes safe | L | 4 |

## 4. Plan (estimates)
- **Phase 1 — 2 weeks (est.):** #1 disk, #2 baseline file, #12 unterbau merge, #5 merge debt + reaper script (report only, never delete unmerged), start #4 manifest (generate from existing 158 run.sh: name, tier guess), #3 build cache prototype (hash key), #8 persistent klog. Target: quick gate < 5 min, no control runs, disk < 80 %.
- **Phase 2 — 2 months (est.):** #3/#6 cache + affected map in use, nightly full on main (#E-06), #7 crash dump + watchdog, #9 Dell install + nightly smoke, #13/#14 dev-push + `ui dump`, #15 perf gate, #10 manifest v2 + SDK template, merge queue (E-04). Target: full gate < 30 min parallel, Dell regression nightly.
- **Phase 3 — 6 months (est.):** #11 RPC/IDL on bus, #18 dlopen, #17 WM to ring 3, #16 fuzzers, #20 visual refs, Store chain (D-06 revocation/delta), Wi-Fi driver (after chip photo).

## 5. External role models (from sub-agents' WebSearch, not all pages opened)
- Fuchsia: `fx serve`/package update without reboot, `zxdb`, `fx test`; perf dashboards — https://fuchsia.dev/docs/concepts/packages/package_update , https://fuchsia.dev/fuchsia-src/development/performance/skia_perf
- Haiku: KDL kernel debugger, app_server crash ≠ panic (model for WM out of kernel), Kits API — https://www.haiku-os.org/docs/develop/debugging/index.html , https://api.haiku-os.org
- Redox: per-recipe rebuild `make rp.<name>`, GDB via QEMU, relibc — https://doc.redox-os.org/book/quick-workflow.html , https://github.com/redox-os/relibc
- seL4: QEMU+GDB, CI matrix with hardware labels — https://docs.sel4.systems/projects/sel4-tutorials/debugging-guide , https://www.sel4.systems/Summit/2022/slides/d3_03_The_seL4_GitHub_test_suite_Gerwin_Klein.pdf
- Linux: kdump, pstore, kselftest/KUnit, livepatch, ccache — https://docs.kernel.org/admin-guide/kdump/index.html , https://docs.kernel.org/dev-tools/kunit/index.html
- syzkaller (syscall fuzzing + dashboard) — https://github.com/google/syzkaller
- Chromium CQ (path-based try jobs, dry run), bors / merge queue, Bazel remote cache — https://chromium.googlesource.com/chromium/src/+/main/docs/infra/cq.md , https://bazel.build

## 6. Unknown / not measured
- Gate wall-clock of a typical branch (only 58 s kernel build measured; per-gate runtimes not re-measured), whole `test.sh` duration today.
- TLS 1.2 / IPv6 real support, fUi node limit and virtualisation, Certus WebView widget, ext4/NTFS write support level (kernel build says ext4=an, ntfs=an), kdump-like Linux details (unverified).
- Whether `firnc` has any internal caching; cost split inside the 58 s.
- Real Dell behaviour for everything (not installed; no measurement possible).
- Sub-agent items not re-verified (A-14 driver details, Hz tick, stack fill 78 %).
