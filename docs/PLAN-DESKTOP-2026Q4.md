# PLAN-DESKTOP-2026Q4 — master plan for a daily-usable desktop (21.10.2026)

PLAN ONLY, nothing is built until the Boss says go. Base: main 74483629. Sources: STATUS-ALLTAG, ARCHITECTURE-DESKTOP, TOOLKIT-PLAN, HOST-PREVIEW, SELFUPDATE, GPU-PLAN (G1, merged), reports M1/M2/M3/W3-W6/T1/G1, project metrics, roadmap. T1 (task manager) is a plan only (S0-S6 = r1380-r1386, nothing built). SETTINGS-REDESIGN.md (P2) was not finished when this plan was written: Settings numbers are marked "pending".
Legend: Effort S = hours, M = about a day, L = days (docs/GPU-PLAN.md uses a larger scale, S = days ... XL = months; its values are quoted as written there). Owner: H = haiku worker (mechanical, docs, tables, translation), S = sonnet worker (design, kernel, UI, proofs). `rNNNN` = roadmap item. Existing items are referenced, not duplicated; new items carry the task ID at the start of their roadmap text (group = workstream; ID map in section 15). Other planners keep their IDs: `T1-Sn` (task manager), `GPU-n` (GPU-PLAN.md numbering, r1374-r1379).
Rules: every gate with a counter-proof; heavy runs only via `/root/jarvis/bin/heavy`; merge to main only when green; ALL NEW CODE fully English (identifiers, file names, comments, log/error texts, commits; UI strings only via i18n de/en catalogs). Docs and roadmap texts may be German or English.

## Workstreams at a glance
| WS | Goal | State (evidence) | Ampel |
|---|---|---|---|
| STAB | no blank bar, no freeze | r1364 Boss-VM bar empty, not reproducible in QEMU / VBox Test-VM (W6); VBox burn 1 of 3 runs; Boss-VM idle 47-62 % host core | red |
| SHELL | Win11-grade taskbar / start / menus | desktop 116/0, win11bar 11/0, barctx 10/0; r1359, r1353 open | yellow |
| SET | redesigned Settings | settings.fi 11 472 lines, 19 built-in pages; P2 doc pending | yellow |
| TM | Win11 task manager | taskmgr.fi 2 440 lines, already a fUi scene-tree app; toolbench 38/0; T1 plan S0-S6 ready (r1380-r1386), nothing built | yellow |
| MON | profiler, overlay, flicker detector | debug.fps overlay on branches only (r1018, r1031); flicker checks scattered (lockflicker, menuflick, settingsflick) | red |
| TK | host preview, templates, registries | preview 19/0, sdk gui 18/0; loop 12-15 min (goal < 30 s) | yellow |
| ARCH | layers, small files, registries | lint 0 violations (arch 7/0); 16 files > 4 000 lines (7 "giants" in ARCHITECTURE-DESKTOP 1.2); 153 clones | yellow |
| GPU | SW Vulkan -> Intel probe -> (VM 3D parked) | SWR 10/0, SPIR-V 36/0, no /dev/dri, no Vulkan loader; 4000 triangles 194.8 ms on 1 core; GPU-PLAN merged | red |
| LA | Firefox on OrientOS | unterbau 710/3/4 of 717, foot 12/0, GTK4 16/3, Firefox image does not build (libxul 155 MB > OFS 130 MiB) | red |
| BENCH | numbers vs Mint | RAM 190 vs 1802 MB, boot 24.5 vs 53.7 s; app start and VBox idle vs Mint unmeasured | yellow |
| UPD | apps live, reboot only for kernel | OTA 161/0, osupdate gate (kernel + system files, trial + rollback); replacing a RUNNING program unmeasured; Boss-VM never updated | yellow |
| ENG | all code English | German left: 16 998 identifiers, 85 691 comment lines, 5 369 log texts, 82 file names; ratchet RED on main | red |

## 1. STAB — Stability
Goal: Boss-VM shows a full taskbar after every cold boot; any freeze leaves evidence. State: W6 (21.10.): worktree was 82 commits behind, Boss-VM state only, cold boot cf6b + `--uart1 file` still to do (laptop offline, bossswap pending). Red on old main too: lockscene 13/2, lockseal, pci 96/2, actionbus gui 63/8, vmsvga desktop 11/1. Existing: r1364 (umbrella), r331, r1133/r1134/r1308, r1324, merge debt r1315/r1325/r1332/r1269/r1306/r1252/r1285.
| ID | Task | Dep | Eff | Risk | Owner | Gate / acceptance |
|---|---|---|---|---|---|---|
| STAB-1 | Boss-VM diagnostic kit: cold boot cf6b, UART1 to file, collect `taskbar:` lines, diff vs Test-VM, one report | laptop online | S | low | S | report names cause or rules out conf/geometry/icons |
| STAB-2 | Shell supervisor + health line (restart dead taskbar/launcher, one `taskbar: health` serial line per boot) | r331 | M | med | S | kill taskbar in QEMU: back < 3 s, 0 panics; pixel gate for bar content (pins, tray, start mark) in quick |
| STAB-3 | Freeze detector: stall watchdog (input arrives, no frame > 1 s) dumps tasks + last syscalls to serial/ODB | - (relates r1308, r873, r606) | M | med | S | planted spin turns gate red; clean run green |
| STAB-4 | Red-gate triage: fix or mark expected-red with owner/date | - | M | low | S | no "red on old main" left in reports |
| STAB-5 | VBox soak gate: 30 min scripted input, 0 stalls > 1 s, idle < 30 % host core; closes r1133/r1134/r1308 | STAB-3, laptop | L | high | S | 5 of 5 runs, Boss-VM and Test-VM |

## 2. SHELL — taskbar, start menu, context menus
Goal: feels like Windows 11, no hard-coded menu rows. State: ctxreg done for start, desktop, bar, explorer item menu (r1352, explctx 10/0); open r1359 (explorer bg/drive/restore/backup), r1353 + r1351 (wlib slots, MAXWN 9), r1015 (tray), corner radius 12 px vs 8 px.
| ID | Task | Dep | Eff | Risk | Owner | Gate |
|---|---|---|---|---|---|---|
| SHELL-1 | finish r1359, r1353, r1351, r1015 (existing items) | - | M | low | S | explctx, barctx, startctx |
| SHELL-2 | Win11 parity audit: measured table (bar height, icon size, menu radius/spacing, animation) + pixel gates for the diffs + corner radius change | D4 | M | low | H | docs/SHELL-PARITY.md, midline 50/0, design 10/0 |
| SHELL-3 | Start menu: recommended/recent from extreg, pin reorder by drag, search ranking | ARCH-4 | M | med | S | startctx 6/0, menualive 9/0, new reorder case |
| SHELL-4 | Bar: window previews, jump-list entries (`bar.button`), badges | ARCH-4 | M | med | S | barctx, win11bar, screenshot diff |

## 3. SET — Settings redesign (details: docs/SETTINGS-REDESIGN.md by P2, pending)
Goal: one navigation + search, every page a manifest page. State: settings.fi 11 472 lines, 19 built-in `page_*`, SETTINGS manifest exists (acct_bind pattern), settingsnarrow 3/3.
| ID | Task | Dep | Eff | Risk | Owner | Gate |
|---|---|---|---|---|---|---|
| SET-1 | Land SETTINGS-REDESIGN.md after review, freeze the information architecture | P2 | S | low | H | reviewed doc |
| SET-2 | New shell: navigation view, global search, breadcrumbs | TK-2, SET-1 | L | med | S | settingsnarrow, a11y scene.sh, midline, screenshots |
| SET-3 | Page migration in 3 batches (A Display/Sound/Network, B Personalization/Apps/Accounts, C System/Update/Privacy), one page per commit; same mechanism as ARCH-5 (r1346) | SET-2 | L | med | S/H | per page settings gate + i18n lint; settings.fi <= 3 000 lines |
| SET-4 | Gate set: all pages light/dark, scale 1/2, narrow, search finds every page | SET-1 | M | low | H | screenshot diff green on main |

## 4. TM — Task Manager (Win11 style; plan T1 = reports/20261021-131454_orientos-t1-task-manager-win11-fui.md)
State (T1, 21.10.): `taskmgr.fi` (2 440 lines) is ALREADY a fUi scene-tree app (226 fuiscene calls, 0 direct paint calls): redesign + extension, not a port. Today 5 pages (Processes, Performance, Startup, Details, Benchmark). Compile baseline 8.2 s, ELF 967 984 B (1 166 032 B below the OFS file limit). Not obtainable from the kernel today, shown as "—" never 0: per-process disk/net/GPU, disk activity, GPU load, thread count, owner uid, priority change. Nothing built, no gate run (r443/r459 done, toolbench 38/0). The roadmap items exist already (r1380-r1386); this plan adds no TM tasks, only links.
| ID | Roadmap | Task | Dep | Eff | Risk | Owner | Gate |
|---|---|---|---|---|---|---|---|
| T1-S0 | r1380 | Baseline: toolbench + desktop quick on main, numbers + screenshots as fixed BASE | - | S | low | H | numbers stored |
| T1-S1 | r1381 | Processes page (7 columns, groups, heat, search, sort, End task, ctxreg menu), no kernel change | S0 | M | low | S | toolbench green, new taskmgrctx gate |
| T1-S2 | r1382 | Performance page: tile list, 60 s graph, details grid | S1 | M | low | S | taskmgr2 gate |
| T1-S3 | r1383 | Navigation rail with 8 pages, icons, Benchmark into Settings; P1 adds keyboard handling | S2 | M | low | S | taskmgr2 a11y tree |
| T1-S4 | r1384 | Gates tools/taskmgr2 + counter-proofs, written WITH S1-S3 | S1 | M | low | S | gates.tsv line, BASE build goes red |
| T1-S5 | r1385 | Kernel counters: uid, threads, per-process disk/net, setprio (needs Boss OK) | Boss | L | med | S | extends toolbench section 2 |
| T1-S6 | r1386 | FPS per window (wm.fi per-window present counter), same change as MON-1 | S1 | M | med | S | present.sh 28/0 stays green |
Links: GPU column stays "—" until `/proc/gpu` (GPU-4, r1377); MON-1 (r1403) extends S6 (one worker for wm.fi); MON-3 (r1405) supersedes the optional overlay of S6; one worker owns taskmgr.fi. T1 asked the Boss separately: go for S1, kernel counters S5 yes/no; Benchmark page location (proposal: in Settings).

## 5. MON — system monitor, overlay, profiler, flicker detector
Goal: any slowness or flicker is measurable in one command. State: debug.fps overlay and 60 Hz pacing exist only on branches (r1018, r1031, r1019); flicker checks are separate scripts; latency, idlebudget, vboxlag gates exist.
| ID | Task | Dep | Eff | Risk | Owner | Gate |
|---|---|---|---|---|---|---|
| MON-1 | Frame profiler core: ring of frame times and present latency per window in wmd, `/proc/frames`; builds on the per-window counter of T1-S6 (r1386), same wm.fi change, ONE worker | T1-S6 | M | med | S | overhead < 0.5 % measured on/off |
| MON-2 | `sysmon` sampler (1 Hz CPU/RAM/disk/net, ring history), one source for TM, overlay, powermon, netmon | - | M | low | S | gate with counter-proof |
| MON-3 | Developer overlay Ctrl+Shift+F (fps, frame ms, frame-time sparkline, CPU, RAM), one Settings switch, merges r1018/r1019/r1031, supersedes the optional overlay of T1-S6 | MON-1, MON-2 | M | low | S | on < 1 % CPU, pixel check, off = identical frame |
| MON-4 | `uiprof` + flicker detector library: pixel-diff series from screenshots, pass/fail + PNG strip; unify lockflicker/menuflick/settingsflick | - | M | med | S | planted flicker must turn it red |
| MON-5 | Frame budget in desktop quick: 0 frames > 32 ms in scripted scenarios (menu, drag, settings scroll) | MON-1 | S | low | S | quick gate |

## 6. TK — Toolkit (host preview, templates, registries)
Existing: r1326 osdk run, r1327 compile cache, r1328 template + gallery, r1329 widgets, r1330 extension points, r1331/r1356 host runner, r1357, r74 SVG. Measured: loop 12-15 min vs goal < 30 s; preview 19/0 (wireframe only).
| ID | Task | Dep | Eff | Risk | Owner | Gate |
|---|---|---|---|---|---|---|
| TK-1 | Author docs: tokens, accent override, density (T6) | - | S | low | H | doc + example app |
| TK-2 | Controls for the Q4 redesigns: NavigationView, tabs node, virtual list, sparkline node, info bar | r1329 | L | med | S | widget gallery screenshots + a11y |

## 7. ARCH — architecture / modularization
Existing: ARCH-1 done (r1342), ARCH-2 r1343, ARCH-3 r1344, ARCH-4 r1345 (extreg), ARCH-5 r1346, ARCH-6 r1347, ARCH-7 r1348, ARCH-8 r1349, r1337 (wlib split). Evidence: 0 L1/A1/P1 violations, 947 import edges, 0 cycles, 153 cloned bodies (about 2 243 lines).
| ID | Task | Dep | Eff | Risk | Owner | Gate |
|---|---|---|---|---|---|---|
| ARCH-9 | Quiet-window procedure for the mass `git mv` (announce, merge/rebase all open branches, move, ELF diff 10/10, unfreeze) | ARCH-2 steps 2-3 | S | med | S | ELF identical, desktop quick green |
Order: ARCH-2 cmd/test/base/services early (low risk); toolkit/shell/apps move only inside the quiet window; ARCH-4 before SHELL-3/4; ARCH-8 splits double as English-migration points (ENG-5).

## 8. GPU (details: docs/GPU-PLAN.md, merged; its tasks are r1374-r1379)
State (GPU-PLAN section 1): virtio-gpu 2D + VMSVGA 2D, no 3D anywhere, no DRM/dmabuf (`/dev/dri` missing), no Vulkan loader or ICD. SWR 10/0 (1240x720 textured quad 31.8 ms on 1 core, 9.7 ms on 4), SPIR-V front end 36/0 (VM 1.7-6.8 ns per op and pixel). Lowering is fragment-only without discard/loops/UBO and one texture, so the fUi shaders cannot run yet. Firn already has a complete host Vulkan client that only needs `libvulkan.so.1`. Real-GPU facts (Haswell) are UNVERIFIED until the PRM check (GPU-5).
Order (GPU-PLAN section 3): (1) software Vulkan stage A, (2) `/proc/gpu`, (3) Intel H0 probe, then display-only KMS on the Dell, (4) software Vulkan stage B (speed), (5) Intel H2-H6 only if still wanted (XL), (6) VM 3D parked, AMD/NVIDIA not planned.
| ID | Roadmap | Task | Dep | Eff (G1 scale) | Risk | Owner | Gate |
|---|---|---|---|---|---|---|---|
| GPU-1 | r1374 | SPIR-V lowering for the fUi shaders (discard + late-Z, vertex stage, 3+ samplers; loops/UBO stay r733/r732) | r683, r684 | L | high | S | spirv gate 36/0 + new shaders, bit-exact |
| GPU-2 | r1375 | Vulkan WSI for OrientOS in Firn vkplat: offscreen read-back into wl_shm (or Wayland surface) | GPU-1 | S-M | med | S | window shows a frame |
| GPU-3 | r1376 | Dummy-ICD loadability test: 10-function Firn `.so` in the OrientOS dynamic loader (risk R1, do FIRST) | - | S | med | S | vkEnumerateInstanceVersion from a guest client |
| GPU-4 | r1377 | `/proc/gpu` metrics + Task Manager GPU page ("n/a", never 0 %) | - | S | low | S | numbers equal counter source |
| GPU-5 | r1378 | Intel Gen7.5 H0 read-only probe on the Dell, verify Haswell assumptions against the PRM | Dell online | S | low | S | PCI ID, BARs, GTT recorded |
| GPU-6 | r1379 | VM 3D (SVGA3D/virgl): PARKED until the software ICD works and laptop VBox 3D is measured | GPU-M1 | - | - | - | decision only |
| GPU-M1 | r1412 | Option-1 milestone gate: Vulkan-lite client (vkcube-like) renders through SWR in the guest, >= 30 fps at 640x480 on 4 cores, bit-exact | GPU-1..3 | L | high | S | gate with counter-proof |
Existing items kept: r36, r33, r38, r502, r669, r673, r675, r682-r685, r732, r733, r737, r738, r772 (L-018 Intel KMS), r954-r971 (VMSVGA). Risks (GPU-PLAN 6): firnc `.so` loading unproven (GPU-3 first); discard/loops change the SPIR-V model; software Vulkan may be slower than the CPU painter (61 vs 30-35 ms at 1080p), so it stays opt-in until measured.

## 9. LA — Linux apps / Firefox path
State (M1/M2, main 280e1fa6): unterbau 710 PASS/3 FAIL/4 GAP of 717, foot 12/0, GTK4 16/3 (r796), Firefox 0 runs. Contradiction M2 (32 tasks) vs M1 (limits no FAIL) open. Existing: r1366 LA-1, r1367 LA-2, r1368 LA-3, r1369, r1370, r1371, r1372, r1373, r796. Estimate F2-F5: 20-45 days (writer's estimate).
| ID | Task | Dep | Eff | Risk | Owner | Gate |
|---|---|---|---|---|---|---|
| LA-7 | Re-measure MAX_TASKS contradiction (t_limits), write real number into STATUS-ALLTAG | - | S | low | H | measured value |
| LA-8 | Stage gate tools/linuxapps/gate.sh (F3 version, F4 headless screenshot, F5 window), expected-red per stage, prints first failing syscall | r1366 | M | low | S | gate runs, red stages listed |
| LA-9 | Memory design: demand-paged file mappings (libxul 155 MB copied today), MAP_NORESERVE; measure, then design | r1366 | M | high | S | measured RSS vs Linux reference |

## 10. BENCH — benchmarks vs Mint
Existing: r1365 app start, r1332 VBox compare, r1218 menu timeout (20 s). Mint 22.3 reference measured (53.7 s boot, 1802 MB RAM, 0.7 % idle).
| ID | Task | Dep | Eff | Risk | Owner | Gate |
|---|---|---|---|---|---|---|
| BENCH-1 | Scoreboard script: boot, RAM, idle CPU, input to frame, app start x4, image size for OrientOS / Mint / Debian, same QEMU config, writes archive table + metrics | r1365 | M | low | H | one command, table updated |
| BENCH-2 | VBox idle CPU Boss-VM vs Test-VM automated (hostcpu.ps1), goal < 30 % | STAB-1, laptop | M | med | S | 5 runs |

## 11. UPD — updates without reboot
Goal: app packages swap live; reboot only when kernel/loader changed. State: SELFUPDATE stage 1 (kernel slot B + trial + rollback, system files overlay r1245), osupdate gate; replacing a RUNNING program unmeasured (r566, T10); Boss-VM update never run (r1269, r1310, r1316, r1317).
| ID | Task | Dep | Eff | Risk | Owner | Gate |
|---|---|---|---|---|---|---|
| UPD-1 | Live app swap: versioned path + atomic rename, running instance keeps old binary, next start new, optional `act reload`; first measure r566 | r566 | M | med | S | apply with running app: 0 reboots, new version at restart |
| UPD-2 | Shell/system programs (taskbar, launcher, login, settings): supervised restart after update, session kept | STAB-2, UPD-1 | M | high | S | QEMU gate, user session survives |
| UPD-3 | "Restart needed" only for kernel/loader; other updates show "applied" | UPD-1 | S | low | S | Settings Update page cases |
| UPD-4 | Gate scenarios: app-only, shell restart, kernel (reboot + rollback) with counter-proofs | UPD-1 | M | med | S | osupdate + feedtest extended |
| UPD-5 | First real Boss-VM update with measured time and space | STAB-1, laptop | S | med | S | numbers in STATUS-ALLTAG |

## 12. ENG — English code migration (Boss rule 21.10.2026)
Rule: new and touched files fully English at once; legacy step by step, file by file at every refactor/split; mechanical rename with proof; guard baseline only goes down (ratchet).
MEASURED 21.10. with `python3 -I tools/english/count.py` (10.7 s, 1 core, main b5be5d0d): identifiers 16 998 (3 461 names), comment lines 85 691, log texts 5 369, German file names 82, 928 files with German. `baseline.json` says 16 119 / 85 795 / 5 308 / 68 (875 files): `count.py --check` is RED on main: 146 places, +885 identifiers, +388 comment lines, +94 log texts, +14 file names, 56 new files with German (e.g. lib/fv/fvaes.fi 111, fvaesni.fi 137 comment lines).
Three scanners disagree (project metrics): count.py 16 998 / 85 691 / 5 369; guard test.sh 58b 8 360 / 86 173 / 13 019 strings; cross-cutting scanner 3 190 / 90 328 / 14 146 strings.
By area (identifiers / comment lines / log texts): kernel/user 9 295 / 19 521 / 333 (196 files); tools 281 / 19 338 / 4 835 (505 files); kernel/ui 1 624 / 7 346 / 15; kernel/drv 407 / 5 091; kernel/sys 339 / 3 942; kernel/gfx 498 / 3 094; kernel/app 1 990 / 1 471; kernel/fs 299 / 2 889; lib/wlan 637 / 953. Heaviest files: wm.fi 4 563, sys.fi 3 654, kgui.fi 3 294, wlib.fi 3 165, kstate.fi 2 215, kmain.fi 1 975, taskbar.fi 1 793, explorer.fi 1 617, settings.fi 1 494, fb.fi 1 420.
Existing: r449, r456 (guard), r463 (stages 3+), r193, r339, r338, r161, r885. OrientStore has its own baseline (tests/check_english.sh).
| ID | Task | Dep | Eff | Risk | Owner | Gate |
|---|---|---|---|---|---|---|
| ENG-1 | One canonical scanner and one metric set (count.py); retire or align the two others; update project metrics | - | S | low | H | one number per category in project metrics |
| ENG-2 | Repair the ratchet: translate the 56 new files / regressions, `--check` green, `--update`, wire `--check` into the quick tier | ENG-1 | M | low | H | `count.py --check` exit 0 on main |
| ENG-3 | New-code gate: `count.py --diff origin/main` mandatory before every merge (worker brief + skill); UI strings only via i18n catalogs | ENG-2 | S | low | S | planted German line blocks merge |
| ENG-4 | Identifier rename in batches with apply.py, biggest first: explorer 935, wm 691, kgui 800, jarvisd 647, settings 575, wlib 534, ota 382; proof = rebuild and `cmp` ELF (names must not reach binaries) | ENG-3 | L | med | S | ELF identical or documented diff, desktop quick |
| ENG-5 | Comment translation per file (translated, not shortened), order by weight; do each giant at its ARCH-8 split | ARCH-8 | L | low | H | comments-only diff (ELF identical) |
| ENG-6 | Log/error texts 5 369: tools scripts first (4 835), then kernel logs; keep wire strings and formats; anchored serial greps updated in the same commit | ENG-3 | M | med | H | gates grep new texts, green |
| ENG-7 | German file names 82 (+14): `git mv` with alias for bridge names (modrename.py) | ENG-3 | M | med | S | alias tests, ELF diff |
| ENG-8 | UI strings lint: no literal UI text in .fi outside catalogs (de/en), quick tier | ENG-3 | M | med | S | i18nlint extended + counter-proof |

## 13. Phases, critical path, parallel groups
| Phase | Content |
|---|---|
| P0 (days 1-3) | STAB-1..4, ENG-1..3, LA-7, SET-1, BENCH-1, T1-S0, GPU-3, GPU-5 (Dell online). No new features until r1364 is explained. |
| P1 (week 1-2) | ARCH-2 steps 2-3 + ARCH-9, T1-S1/S2/S4 (+S6 with MON-1), MON-1/2/4, UPD-1, TK-2 start, SHELL-1/2, ENG-4 start, GPU-4, GPU-1 start |
| P2 (week 2-4) | ARCH-2 step 4 in the quiet window, ARCH-4, SET-2, SET-3A, SHELL-3/4, T1-S3, MON-3/5, UPD-2/3/4, LA-1 start, GPU-1/2 |
| P3 (week 4-8) | SET-3B/C, ARCH-3/5-8, LA-1 to LA-3, GPU-M1, T1-S5 (if Boss OK), ENG-5/6/7 |
| P4 (> 8 weeks) | LA F4/F5 (Firefox window), Intel display-only KMS (r772, after GPU-5), software Vulkan stage B, ENG-5 long tail, STAB-5 |
Exit criteria: P0 = r1364 explained (cause or ruled out with evidence), `count.py --check` green and in quick, STATUS-ALLTAG refreshed; P1 = quick tier green (desktop 116/0, arch 7/0), T1 Processes page merged; P2 = Settings shell + first batch, live app swap measured; P3 = Firefox `--version` green, GPU-M1; P4 = Firefox window, soak STAB-5.
Capacity: heavy gates max 4 per OrientOS group (server max 8); docs/measurement tasks do not count.
Critical paths: (a) STAB-1 (laptop) -> STAB-2 -> UPD-2 -> UPD-4; (b) LA-7 -> LA-1 (L) -> LA-3 -> F4/F5 (20-45 days); (c) TK-2 -> SET-2 -> SET-3; (d) ARCH-9 -> ARCH-2 step 4 -> ARCH-8 -> ENG-5; (e) GPU-3 -> GPU-1 -> GPU-2 -> GPU-M1.
Parallel groups (no shared files): A stability + guard (STAB, ENG-1..3); B moves (ARCH-2/9, only in the quiet window); C docs and measurements (GPU-1, SET-1, BENCH-1, LA-7, GPU-5); D toolkit + monitor (TK-2, MON); E updates (UPD); F Linux apps (LA); G GPU. Collision rule: SHELL/SET/TM edit taskbar.fi/settings.fi/taskmgr.fi: one worker per file (wm.fi: T1-S6 + MON-1 together); ARCH-2 step 4 only when no branch touches these files.
Never in this plan: WLAN driver (r21, L, practically not planned), Bluetooth, camera, video decoder, SMB, IPv6 (see STATUS-ALLTAG).

## 14. Decisions for the Boss (recommendation first)
1. Go order: start Phase 0 now (stability + English guard, no new features until the empty bar is explained)? Recommended: yes.
2. Browser: Firefox path (OFS big files first) instead of own browser Certus (blocked, r935-r938, r572)? Recommended: Firefox path, park Certus.
3. GPU order: software Vulkan first (testable here), then only READ the real Intel card (probe) and bring up the display, VM 3D parked until the software path works? Recommended: yes (GPU-PLAN section 3). Alternatives: VM 3D before Intel, or Intel first.
4. Window corner radius: 8 px like Windows 11 (now 12 px)? Recommended: 8 px.
5. Updates: apps swap live, shell restarts itself after an update (bar blinks once), reboot only for kernel? Recommended: yes.
Also open with the Boss (asked by T1): go for task manager slice S1 and kernel counters S5. P2 questions will be listed in its own document.

## 15. Task ID map (roadmap)
| WS | IDs -> roadmap |
|---|---|
| STAB | STAB-1..5 -> r1387-r1391 (existing r1364, r331, r1133, r1134, r1308, r1324) |
| SHELL | SHELL-2..4 -> r1392-r1394 (SHELL-1 = existing r1359, r1353, r1351, r1015) |
| SET | SET-1..4 -> r1395-r1398 |
| TM | T1-S0..S6 -> r1380-r1386 (planner T1) |
| MON | MON-1..5 -> r1403-r1407 |
| TK | TK-1..2 -> r1408-r1409 (existing r1326-r1331, r1356, r1357) |
| ARCH | ARCH-9 -> r1410 (existing ARCH-1..8 -> r1342-r1349) |
| GPU | GPU-1..6 -> r1374-r1379 (planner G1); GPU-M1 -> r1412 |
| LA | LA-7..9 -> r1416-r1418 (existing LA-1..6 -> r1366-r1371) |
| BENCH | BENCH-1..2 -> r1419-r1420 |
| UPD | UPD-1..5 -> r1421-r1425 |
| ENG | ENG-1..8 -> r1426-r1433 |
New by this plan: 39 roadmap items (r1387-r1398, r1403-r1410, r1412, r1416-r1433); 8 duplicates of T1/G1 items were removed again.
