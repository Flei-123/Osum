<!-- SPDX-License-Identifier: GPL-2.0-only -->
# App rights & energy modes (W-APPRIGHTS, 15.10.2026)

Goal: apps like on Android/HyperOS. Per app: own rights, own energy mode, an "App info" page
(storage, network use, battery share, permissions, notifications, Force stop / Uninstall / Clear data).

## 1. Inventory (what exists today, measured by reading the tree at 653f0299)

| Piece | State | Where |
|---|---|---|
| App identity | **done.** Sticky kernel label `app:<name>` per task, set from the bundle path `/apps/<n>.osp|.prog`; SYSTEM bundles stay unlabelled (= the user). Cannot be cleared or widened. | `kernel/sched/origin.fi`, `SYS_OSUM_ORIGIN` (1990) |
| Manifest v2 (`perm=`) | **lint only.** `osdk` checks `perm=` names (`net notify clipboard.read clipboard.write fs.home audio.play`); only `net` has an effect. (r609, r646) | `tools/sdk/osdk.py`, `docs/SDK.md` |
| Network per app | **done.** `net=real|filtered|faked|none` in INFO, enforced by netview per process; derived from `perm=net` by `osdk build`. | `kernel/net/netview.fi`, `kernel/user/appdir.fi` (A_NET) |
| Network use per app | **done.** netmon books sent/received per program and period. | `kernel/net/netmon.fi`, `docs/NETMON.md` |
| Battery share per app | **done.** powermon splits the *measured* `_BST` rate by CPU ticks into 16 program rows (honest: "measured total, proportionally attributed"). | `kernel/pwr/pmon.fi`, `docs/POWERMON.md` |
| Limits | **partial.** Containers (`ctr`): memory frames, CPU share 1..100, process count, net view, own root dir. 8 containers max (r410, r746). | `kernel/sched/ctr.fi`, `kernel/user/ctr.fi` |
| Bus rights | **done.** Broker decides by client (= origin label): `settings.<area>.write`, event rights, grants with seconds/permanent, audit. | `kernel/user/orientbus.fi`, `docs/ACTION-BUS.md` |
| Microphone | capture path + indicator + global mute exist; **no per-app right** (r625, r641): any process may read. | `kernel/drv/snd/mic.fi`, `SYS_OSUM_AUDREAD` (1855) |
| Camera | UVC protocol lib only, no driver (r7, r809) -> right can be modelled, not tested. | `lib/uvc` |
| Location / contacts / phone | no subsystem exists. A right without a service behind it is a lie -> model the bit, ship it when the service exists. | - |
| File access | no per-app isolation: an app sees the whole tree. Containers have a root, but apps do not run in one. | S-010 (r47) |
| Task table | 32 slots (MAX_TASKS, r344). Container table 8. Program rows in powermon 16. All three limit an "all apps" page. | `kernel/lib/kstate.fi` |
| Pause/freeze of one process | **not verified in this inventory**; signals exist, a stop/continue state for a whole app is unproven. Must be checked in stage 5. | `kernel/sched` |
| Standby | S3 works in QEMU (K-004b/c). Per-app standby is not S3; do not mix. | `docs/STANDBY-MEHRKERN.md` |

Summary: **identity, network, network counters and battery attribution already exist.** Missing are
(1) a *kernel-enforced* grant table for the other rights, (2) file isolation, (3) energy *modes* that act, (4) the page.

## 2. Rights model

- **Declared** by the app: `perm=` in INFO (manifest v2). The ceiling: a right that is not declared can never be granted.
- **Granted** by the person: one bit per (app, right) in a kernel table, default **deny** for every gated right.
  Only an *unlabelled* process (= the person's tools: Settings, `apprights` CLI) may change the table. A labelled
  process (any app, any child of an app) gets `EPERM`, same stickiness argument as `origin.fi`.
- **Enforced** at the kernel chokepoint of each right, using the caller's label, *not* in the bus alone:
  a right that only the bus checks is bypassed by an app that skips the bus.
  Unlabelled callers (the person, system tools) are never gated (no regression for the shipped image).
- **Persisted** in `/etc/apprights.conf` (`app right[,right]` lines); loaded at login by a root helper. (stage 2)
- Rights, with the chokepoint and when it is real:

| Right | Bit | Chokepoint | Real when |
|---|---|---|---|
| `mic` | 0 | `SYS_OSUM_AUDREAD` | stage 1 (this round) |
| `camera` | 1 | UVC open | camera driver exists |
| `net` | 2 | netview (exists) | mirror: grant toggles the view real/none |
| `fs.home` | 3 | VFS open (path outside the app's data dir) | stage 3 |
| `notify` | 4 | notification post | stage 2 |
| `clipboard.read/write` | 5/6 | clip syscalls | stage 2 |
| `audio.play` | 7 | `AUDWRITE` | stage 2 |
| `location`, `contacts`, `phone` | 8..10 | none yet | when a service exists |

- Data folder: `/data/<app>/` created at install, the only writable place for the app without `fs.home`.
  Enforcement = container root per app (reuses `ctr` root + `CTRENTER`) -> needs more than 8 containers (see 5).
  "Clear data" = remove that folder; "Storage" = its size (`du`).

## 3. Energy modes per app

Modes (user choice, stored next to the rights): **Unrestricted / Optimized (default) / Restricted**.
Only mechanisms that the kernel can actually act on are offered:

| Knob | Unrestricted | Optimized | Restricted | Mechanism |
|---|---|---|---|---|
| CPU share while not in front | none | `ctr` cpu 50 | cpu 10 | existing `X_CPUSH` per container |
| Wakeups (timers) | free | coalesced to >= 1 s | >= 30 s | timer slack per label (new, kernel) |
| Pause when unused | no | after 3 days | after 10 min in background | freeze whole app (needs stop state, stage 5) |
| On pause | - | drop temp files in `/data/<app>/tmp` | + revoke runtime rights (`mic camera location`), hold notifications | rights table + notify queue |
| Network in background | free | free | `none` view while unfocused | netview switch |

"Not in front" = no window of the app is focused. The window manager knows; it must tell the kernel
(one syscall/op `app foreground = <label>`). That is a new kernel interface -> stage 4.

Battery per app: **no new measurement.** Page shows powermon's share ("34 % of a measured 6.8 W"), plus netmon bytes and
wakeups (new counter, stage 4). Never "this app draws X W".

## 4. App-info page (fUi, Settings -> Apps -> <app>)

Rows in Android order: header (name, version) / Storage (data size) + **Clear data** / Network (netmon bytes, allow/deny) /
Battery (powermon share, mode picker) / **Pause app activity when unused** (switch) / Permissions (list with allow/deny from
the table, ceiling from `perm=`) / Notifications (on/off) / Clear defaults / **Force stop** (`kill` by label) / **Uninstall** (`opk`).
Settings talks through the bus: new area `settings.apps.write` (reuses r224 rights, journal, undo). The page only reads
tables the kernel already keeps. Needs Settings-page slots (`msg.fi` SLOTS 768 full, see KNOWLEDGE).

## 5. Stages (each checkable in QEMU, each with a gate and a counter-probe)

| # | Stage | Gate | Effort |
|---|---|---|---|
| 1 | Grant table in kernel + `mic` enforcement at `AUDREAD` + CLI `apprights`. **Done this round.** | `tools/apprights` | S (done) |
| 2 | `/etc/apprights.conf` persistence + loader at login; `perm=` ceiling read from INFO (appdir A_PERM); enforce `clipboard.*`, `audio.play`, `notify`; map `net` onto netview | extend gate | M |
| 3 | Per-app data dir + `fs.home` via container root; raise MAX_CTR / MAX_TASKS (r344) | gate: app cannot open `/etc/passwd` without right | L, kernel |
| 4 | Foreground notification wm -> kernel, per-app wakeup counter, CPU share by mode | gate: counter + share measured | M, kernel |
| 5 | Freeze/unfreeze app, "pause when unused", revoke + temp cleanup, notification hold | gate: frozen app makes no progress, thaw continues | L, kernel (check stop state first) |
| 6 | App-info page in fUi + `settings.apps.*` bus area + Force stop / Uninstall / Clear data | Klick-Gate | M-L |
| 7 | Manifest enforcement r226 (store refuses packages without manifest) | store gate | S |

Rough total after stage 1: 4-6 weeks of focused work, of which stages 3 and 5 are the real kernel work.

## 6. What is NOT promised

- No per-process current measurement (impossible, see POWERMON.md).
- No hardware test: camera, location, phone have no driver/service; their bits are reserved, not enforced.
- Without file isolation (stage 3) an app can still read files directly; `mic`/`net` are real, "Storage" permission is not yet.
- Rights granted to a *service* app act for everything it forks (label is sticky) - intended.

## 7. Stage 1 as built

- `lib/apprights/policy.fi`: right names/bits, grant table (16 apps), `allows(label, bit)`. Importable from kernel and host.
- Kernel: `SYS_OSUM_ORIGIN` ops `2 = RIGHTS_SET` (unlabelled caller only) and `3 = RIGHTS_GET`; `do_audread` returns `-EACCES`
  for a labelled `app:<n>` task without `mic`.
- `/bin/apprights set|get|trymic|trygrant` (`kernel/user/apprights.fi`). Gate `tools/apprights/run.sh`.

## 7. Status AR-1b / AR-2 (15.10.2026)

- `/bin/apprights` is in the usbimg PROGS (62 KiB). `apprights load` runs at desktop start (kgui `desk_start`, right after `sntp boot`).
- **Ceiling** = `perm=` of `/apps/<n>.osp|.prog/INFO`. `load` registers it per app (ORIGIN op 4); no `perm=` line = ceiling 0;
  SYSTEM bundles (root file `SYSTEM`) are the person's own tools and get no table slot. A grant above the ceiling is refused
  (`set fail 1`, nothing changes); lowering a ceiling clamps the grants at once. Only an unlabelled caller can set a ceiling.
- **Persistence** `/etc/apprights.conf`: `<app> <right>[,<right>]`, only apps with a grant. `apprights set` rewrites it; `load`
  applies it, clamps lines above the ceiling and skips (counts) bad lines.
- **Enforced in the kernel** (label `app:<name>`, unlabelled never gated): `mic` (AUDREAD), `audio.play` (AUDWRITE),
  `clipboard.write` / `clipboard.read` / `notify` (do_bus: CLIPSET / CLIPGET / NOTIPOST), `net` (netview.view_of: no grant = view none,
  in force at the next call, revoke too). Not gated: CLIPINFO (metadata), drag-and-drop, reading notifications.
- Declared-only: `camera fs.home location contacts phone` (no service / no isolation yet).
- Gates: `apprights` (stage 1), `apprights-host` (lib + 12 mutations), `apprights2` (QEMU, restart over the same disk, ceiling, enforcement, 3 counter-probes).
- Known limits: `load` runs asynchronously after the desktop starts, an app started in the first moments runs at default deny; the conf is
  rewritten in place (no atomic rename); the table holds 16 apps.
