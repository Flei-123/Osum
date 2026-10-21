# ARCHITECTURE-DESKTOP — structure + modularity of kernel/user (21.10.2026)

Doc + two read-only scripts + one migration helper; NO source file changed. Numbers MEASURED on main 1c5c34c7 unless marked ESTIMATE.
Related, not repeated here: docs/TOOLKIT-PLAN.md (SDK, loop time, widgets: roadmap r1326-r1332), r1337 (split wlib.fi into modules; Firn has no re-export), docs/ACTION-BUS.md, docs/SETTINGS-MANIFEST.md, docs/ARCH.md (that one is the AArch64 machine boundary, not this).

Tools (all `python3 -I`, run from the repo root):

| script | what |
|---|---|
| `tools/arch/deps.py` | import graph, cycles (`--cycles`), fan-in (`--fanin`), closure (`--closure taskbar`), regions of one file (`--regions wlib`), cloned function bodies (`--clones`), shared /etc paths (`--coupling`), dot/json |
| `tools/arch/layers.py` | layer table + rules L1/A1/P1/S1; `--strict` fails on any violation; `tools/arch/run.sh` = gate with counter-proofs (baseline is empty) |
| `tools/arch/migrate.py` | `--plan/--apply/--check`: move `kernel/user/*.fi` into layer folders and leave flat symlinks (section 2) |

## 1. Ist-Analyse

### 1.1 Numbers
- `kernel/user`: 285 `.fi`, 225 950 lines, 219 programs (`fn u_start`), flat, no subfolder except `certus/`, `settings.d/`.
- Import graph: 947 edges, **0 cycles**, 0 unresolved (24 stdlib imports `std.* fui.* font.* paint.* plat.*` live inside firnc).
- Fan-in: `ulib` 276, `wlibc` 48, `fuiscene` 41, `wlib` 40, `tools` 39, `msg` 25, `pw` 19, `actwire` 19, `fuiapp` 17.
- Cost of the stack: `ls` pulls 3 053 lines (6 modules); `calc` 39 631 (19); `taskbar` 57 750 (31); `explorer` 60 749 (41). `wlib` is in the closure of 53 files, `wlibc` of 66.
- 29 programs import BOTH `wlib` and `fuiscene` (two toolkits in one binary: wlib widgets are old, fuiscene is the scene host). That is the real size driver (TOOLKIT-PLAN T12).
- The import graph is already layer-clean (section 3: 6 violations). The mess is INSIDE the big files and in non-import coupling (1.4), not in who imports whom.

### 1.2 The seven giants: responsibilities (line ranges from `deps.py --regions`, function names)

**wlib.fi — 13 102 lines, 528 fn** (widget library; imports wlibc, fuib, fuiglyph, icons)
| lines | responsibility |
|---|---|
| 848-1547 | frame/blink/log/debug switches, small helpers, `tl_*` (title line) |
| 1564-2398 | window object: `window_*`, `win_*` (open, resize, dirty rects, event pump) |
| 2405-3175 | layout box (`box_*`) and canvas/graph/list basics |
| 3192-5253 | image + widgets: image_, slider_, tile_, focus, paint_ (≈85 fn, the widget zoo) |
| 5263-5954 | selection/drag-drop (`sel_ drop_ drag_`) |
| 6163-6488 | tabs (`tab_*`, menubar) |
| 6540-8128 | paint, tooltips, `zug_*` (pull-strip), animation (`anim_`), `draw_*` |
| 8146-9204 | input dispatch `on_*`/key |
| 9219-11277 | **text area**: `ln_*` (lines) + `ta_*` (58 fn, ≈2 000 lines) + highlight `hl_/kw_` — duplicated in `fuied.fi` |
| 11513-11933 | popup menu (`menu_*`) and dialogs (`dlg_*`) |
| 11985-12134 | theme glue |
| 12297-12722 | rect/text/clip/drag/notifications |
| 12726-13072 | accessibility tree (`ax_*`, 19 fn) |
**wlibc.fi — 7 963 lines** (paint core, imported by 66 files)
| 427-1436 | window-server client: `win_*`, layers, `shm_`, screen/heads, clipboard, mouse |
| 1452-2987 | strip canvas, `v*` primitives, ink/text/cursor/glyph, clip/drag/noti |
| 3068-4305 | bus glue, ramps/colour math (`ramp_ mulf_`) |
| 4336-7339 | **theme engine** (`theme_*` 64 fn, conf, fx, shapes) — lives in the paint core |
| 7387-7892 | built-in icons (21 fn) |
**taskbar.fi — 9 195 lines, 186 fn**
| 380-1241 | metrics (pad/gap/height), tray glyph/colour helpers, debug |
| 1241-1900 | config: `conf_read/conf_write` of /etc/taskbar.conf (own parser), text/shield (`schild_`) |
| 1900-2300 | geometry, apply, icon loading |
| 2300-3144 | hover state, clock, battery warning, status build, demo hooks |
| 3144-3925 | plugin fields (`plugbar_*`), text fitting, `layout()` |
| 3925-6113 | list read, symbols, button/pill/badge painting, `paint()` |
| 6113-6615 | preview, pin drag, edge docking, autohide, launcher window |
| 6615-7568 | hover text, **`rechtsklick` + `kontext_step`** (hard-coded 3 entries), tooltip, toast, hotkeys |
| 7568-8045 | start bundle, show-desktop, snip, `click()` |
| 8045-8560 | scene tree of the bar (`bi_*`, `bar_*`), multi-head `spawn_bar/heads_step` |
| 8554-9195 | `u_start`, `main` loop |
**settings.fi — 11 473 lines, 313 fn**: 1029-1110 debug; 1110-5024 appearance/taskbar/mouse-rate state + helpers (`tb_ stufe_ glatt_ rate_` ≈120 fn); 5037-6609 system/update/bus/rights pages data; 6617-8516 `page_*` builders (darst, vorl, sync, bruecke, system, rechte, maus, energie, apps, info, proto, update, screen, time, netz, benut, netv, sprache, konto); 8527-9794 package pages (`pkg_*`) + sidebar/nav; 9795-11473 `u_start` + event loop.
**fuiscene.fi — 8 411 lines, 479 fn** (scene host): 294-873 entry/strip/key; 877-1179 memo; 1191-3561 node/set/menu/pop/draw; 3588-3773 tips/cmd bar; 3797-6357 **tables** (88+42 fn); 6395-6764 canvas/pane; 6793-7100 a11y; 7177-8123 image/editor/dialogs/context menu; 8131-8404 window pump.
**explorer.fi — 6 310 lines, 178 fn**: 346-396 debug; 417-1282 model/scan/nav/tabs; 1317-5443 tabs, preview, context menu (`cm_*`), dialogs, actions, drag; 5458-6294 UI build, `rechtsklick`, `u_start`. (Explorer-2 pieces already split: expmodell, expakt, expdlg, exporte, fileop — the family pattern to copy.)
**orientbus.fi — 4 873 lines, 130 fn** (action-bus broker): 217-549 pools/helpers; 549-943 manifest loader; 961-1148 policy+decide; 1148-1455 audit; 1486-1786 list/describe/JSON; 1786-2585 arg check, forward, adapters (window/keys); 2585-3195 `do_call`, undo, events/subscribe; 3195-3540 whoami/confirm/grant/stat; 3540-3930 tally + dry-run; 3928-4532 rights/revoke/block + trusted ask; 4532-4873 catalog/reload/serve/check.

### 1.3 Duplicates (`deps.py --clones`: identical normalized function bodies >= 4 lines)
153 cloned bodies, ≈2 243 redundant lines. Biggest:
- `fuied.fi` ↔ `wlib.fi` text area: `ta_*`, `ln_*`, `hl_run`, `kw_hat` ≈ 560 lines, byte-equal bodies (second implementation of the same editor).
- `flate.fi` ↔ `inflate.fi`: `dynamic_trees setup construct fixed_trees decode` ≈ 220 lines.
- `pw.fi` ↔ `sha.fi` `ktab` (69); `fsrv/fsrw` `set_num`; `opk/ota` `file_read/file_write`; `glogin/login` `wartezeit`; `idlelock/lock` `leerlauf_grenze`; `wlibc/wmd` `shade`.
- Boilerplate: `dbg_setup` ×4 (desktop, explorer, launcher, taskbar), `say/sayn/nl` ×6 (desktop explorer launcher qs settings taskbar), `hexval` ×7 variants, `lower` ×9, `line` ×6, `net_glyph` ×3 (glogin, signin, taskbar).
- Same function NAME in several files (`--dups`): 466 names — mostly harmless (module-scoped).

### 1.4 Coupling that is not an import (`deps.py --coupling`)
Shell, apps and services talk through files; each reader has its OWN parser. 43 paths are used by >= 2 files. Worst:
- `/etc/taskbar.conf`: taskbar (9 refs, own `conf_read/conf_write`), launcher (7, `lp_tbconf`), settings (5), template (5), glogin (1).
- `/etc/theme`, `/etc/theme.conf`, `/etc/wallpaper`, `/etc/time.conf` (7 files), `/etc/uitrace` (8), `/run/svc.cmd` (8), `/etc/sperre.conf`, `/etc/network.conf`, `/etc/ota.conf`.
- Consequence: a new config key means editing 3-5 files. -> one `conf` module per file format in `base` (section 5, step 3).

## 2. Can the build take subfolders? (MEASURED)
firnc resolves `import a.b` as `<dir of the importing file>/a/b.fi`, then `$FIRNLIB/a/b.fi`. `FIRNLIB` is ONE directory (a `:` list does not work). `..` does not work. The use-name is the last component (`import toolkit.ulib` -> `ulib.say`). The importing file's directory is taken from the PATH given to firnc — a symlink is NOT resolved to its target.

Consequences (all tested in a scratch tree):
| try | result |
|---|---|
| `import toolkit.ulib` from `apps/x.fi`, no FIRNLIB help | fails (looks in `apps/toolkit/`) |
| qualified imports with `FIRNLIB` = stage dir (symlinks to `lib/*` + `toolkit/`) | works (62 KB .o, links with user.ld) |
| **flat symlinks `kernel/user/wlib.fi -> toolkit/wlib.fi`, compile `kernel/user/taskbar.fi`** | **works, imports unchanged** |
| compile the real path `apps/x.fi` with flat imports | fails (siblings missing) unless FIRNLIB has a flat view |

**Decision: move the files into layer folders, keep every old flat name as a relative symlink (generated by `tools/arch/migrate.py`).**
- Source needs NO edit (imports stay `import wlib`); the ~120 gate scripts that build `kernel/user/$p.fi` (`tools/sync/build.sh`, `tools/usbimg/build.sh` line 394 `[ -f ... ]`, oom/sshd/userland/systembus/netzui/customres/unterbau ...) and the 498 files that mention a path keep working.
- PROOF (scratch copy of kernel/user migrated, 285 files moved): built taskbar, explorer, settings, launcher, desktop, glogin, ls, orientbus, odbd, wmd with `tools/sync/build.sh` flat vs migrated: **10 of 10 ELFs byte-identical** (taskbar 1 222 896 B ...). `tools/fui/share.py` prints 81.1 % on both trees.
- Gegenproben that `cp -a kernel/user $T/x` and `sed -i` a module: `sed -i` replaces the COPIED flat symlink by a regular file and the build uses it (tested: injected syntax error in flat `ulib.fi` is hit by `ls` and `cat`). Works.
- Lint/graph tools skip symlinks (`os.path.islink`), so nothing is counted twice. Scanners that walk with `followlinks` or `find -L` would double count: before the real move run `tools/english/count.py`, `tools/i18n/scan.py`, `tools/fui/share.py` on both trees and compare (gate in section 5).
- Later (optional, step 8): qualified imports `import toolkit.wlib` + a staged `FIRNLIB` in build.sh when two layers need the same module name. Not needed now (flat names are unique).
- Firn has no re-export (r1337): moving a file never needs a facade; splitting wlib.fi does (r1337 owns that).
- `PROGS` in `tools/usbimg/build.sh` is names only -> unchanged. New program: put the file in its layer folder + the flat symlink (`migrate.py --apply` for new files is not needed: `ln -s apps/foo.fi kernel/user/foo.fi`; `migrate.py --check` finds a missing link).

Target layout (`kernel/user/`):
```
base/      ulib msg nv pw grp sha tools nidx appdir act* image gif jpeg flate inflate unix template instkonto ...   (50 files)
toolkit/   wlibc wlib fuib fuiglyph fuiapp fuiscene fuied winopts winfloat backdrop                              (10)
services/  orientbus odbd settingsd stored social sshd wayd wmd powerd hotkeyd wmplug dhcp sntp svc rpcd init ota opk ...  (38)
shell/     desktop taskbar launcher glogin login signin lock idlelock barpop traypop calpop taskview notifc qs runbox welcome ... (25)
apps/      explorer(+exp*) settings term nedit calc taskmgr store mail pdfview viewer mp3 disks storage netmon wlan vpn installer ... (36)
cmd/       ls cat cp mv rm grep ... (74 CLI programs)
test/      gate drivers, demos (k13t ... plug*, hello*, bench) (52)
```
Inside later (after the giants are split): `toolkit/{wlib,fui,scene}/`, `shell/{taskbar,startmenu,lock,login}/`, `apps/{explorer,settings}/`. `certus/` and `settings.d/` stay (data, not .fi modules); `crt.s sysstub.s user.ld` stay flat.
The exact assignment is `layers.TABLE` in tools/arch/layers.py (`layers.py --table` prints it).

## 3. Layers and rules
| layer | may import |
|---|---|
| lib | lib |
| base | lib, base |
| cmd | lib, base |
| toolkit | lib, base, toolkit |
| services | lib, base, services |
| shell | lib, base, toolkit, shell |
| apps | lib, base, toolkit, apps (never shell) |
| test | everything |
Rules (the lint checks 1-4; 5-8 are review rules):
1. **L1** the table above (apps do not import shell; toolkit knows no apps/shell; base has no GUI; cmd is GUI-free).
2. **A1** app -> app only inside a family (explorer family: explorer expakt exporte fileop expdlg expmodell massren trashbin; mp3 family; edit family). Shared code goes down to toolkit/base.
3. **P1** a file with `fn u_start` is a program and is never imported (leaf). A library has no `u_start`.
4. **S1** report files > 4 000 lines (today: wlib, settings, taskbar, fuiscene, wlibc, explorer, orientbus). Target <= 3 000.
5. Shell and apps talk to each other only through the action bus, config files owned by one module (1.4) or `spawn` — never by import.
6. A program's `u_start` + event loop is <= 300 lines; pages/screens are separate modules (`apps/settings/page_*.fi`).
7. A config file format has ONE reader module in `base` (`conf_taskbar`, `conf_theme` ...); consumers call it.
8. Names: layer folder = lower case, file = `<area>_<part>.fi` (`taskbar_paint.fi`, `settings_page_mouse.fi`); one prefix per module; no two modules share a last component (firnc use-name).

Result (21.10.2026, r1342): `python3 -I tools/arch/layers.py` = **L1 0, A1 0, P1 0**. The 6 former L1 violations were fixed without behaviour change:
| was | fix |
|---|---|
| `presence` -> `wlibc` (services imports toolkit) | it only used 6 bus wrappers: now local wrappers over `ulib.bus5` (same syscall, base); binary 144 KB -> 33 KB |
| `wmd` -> `wlibc` (services imports toolkit) | `wmd` is the window manager / compositor (composes chrome with the paint core): classified **shell**, not a service |
| `template` -> `wlibc` (base imports toolkit) | it is the theme preset store on the theme engine in `wlibc`: classified **toolkit** (importers qs, settings, theme are shell/apps) |
| `certus` -> `wlib`/`fuiscene` (base imports toolkit) | it is a GUI program: classified **apps** |
| `disks` -> `diskscan` (apps imports services) | `diskscan` is a pure library (ulib, libc.io, disks.table): classified **base** |
Still open (not required by the lint): `wlibc` mixes the window-server client with the paint core (a `wmclient` split would let `wmd` return to services).
Gate: `bash tools/arch/run.sh` (tier quick, `tools/qa/gates.tsv` row `arch`): `layers.py --strict` must be 0, baseline file is empty, and 4 planted violations (base->toolkit, service->toolkit, app->shell, import of a program) in a scratch copy of kernel/user must turn it red.

## 4. Registries (extension points)
Principle: **the shell asks a registry, the registry reads manifests, the click becomes an action-bus call.** No app name or app action appears in shell code; rights, audit and undo come from the bus for free. Reuse the existing manifest style (line based, `manifest 1`, unknown line = skipped + counted, whole file refused on a malformed KNOWN line, fixed tables) — same as `lib/settingsman/manifest.fi` and ACTIONS.

Existing pieces (do not rebuild):
- INFO (`/apps/<app>.osp/INFO`, appdir.fi): name, info, keys, version.
- ACTIONS (orientbus): `menu`/`menuext` -> `act list --menu file|dir <name>` -> explorer "Actions" sub menu (D1, `explorer.actions_menu`@3583, gate tools/actmenu).
- SETTINGS (settingsman): `page/field` per package, rendered by settings (`pkg_*`@8527+), catalogue limits 8 apps/24 pages.
- fui.tray (`lib/fui/tray.fi`): item registration with menu entries and overflow; the bar turns clicks into bus messages.
- wmplug (`WM_PLUG_*`): plugin text fields on the bar (`plugbar_read`).

New: one manifest `/apps/<app>.osp/EXTEND` (and `/etc/extend.d/*.extend` for system entries), parsed by a `base` module `extreg` (static tables, limits like settingsman, `add_pkg` rejects a mismatching `app`). Line format:
```
manifest 1
app notes
ctx   file    notes.open   menu.notes.open   action=notes.open  ext=txt,md  group=open  order=20
ctx   dir     notes.index  menu.notes.index  action=notes.index
ctx   bar.button  ...                          # right click on a taskbar button of THIS app
start section notes.recent menu.notes.recent action=notes.recent_list   # a recommended row provider
start pin     notes                                                      # default pin (user list wins)
tray  item    notes.tray   menu.notes.tray   icon=notes  system=false
tray  menu    notes.tray   menu.notes.new    action=notes.new
page  -> stays in SETTINGS (already a manifest)
```
Words: surface = `file dir bg bar.button bar.pin start.tile start.row desktop`; `label` is a message-catalogue key; `action` is an ACTIONS name in the app's own namespace; `when=` (later) a small predicate list (`ext= kind= selected>1`).
API (module `extreg`, layer base): `extreg.load_all()`, `extreg.query(surface, subject_ptr, out)` -> sorted entries (group, order), `extreg.invoke(entry, subject)` -> `actcli` bus call. Reload on `act reload` (already exists) so installing an app shows its entries without restarting the shell.

Where the code is today -> what changes:
| extension point | today | change |
|---|---|---|
| context menu, taskbar | `taskbar.rechtsklick`@6827 + `kontext_step`@6896: item index (0/1/2) hard-coded -> `pin_exec`/`app_exec`/`WA_HIDE`/`angeheftet` | entries = built-in list + `extreg.query("bar.button"/"bar.pin", app)`; chosen entry id -> dispatch table instead of `if r == 0 ... else if r == 1` |
| context menu, start | `launcher.ctx_open`@876, `ctx_pick`@903 (start/unpin/pin to taskbar), `ctx_items` 200-byte buffer | same pattern with `start.tile`/`start.row` |
| context menu, files | `explorer.rechtsklick`@5710 + `ctx_wahl`@3495 + `actions_menu`@3583 (bus actions, already registry-like) | DONE for the item menu (r1352): rows from `ctxreg` context `CTX_EXPLORER_ITEM` (15 built-in rows, action id = old row number, + `explorer|label|prog` lines of /etc/ctxmenu.conf; `explorer: ctxreg n=`, gate tools/explctx). Still hard-coded: `explorer.context.bg/.drive/.restore/.backup` popups; then route through `extreg.query("file"/"dir"/"bg")` so ONE source (ACTIONS menu + EXTEND ctx) |
| start menu entries | `appdir.fi` (24 apps, 16 KiB arena) reads INFO; pins `/etc/startpins.conf` (`pins_read/pins_write`@644/692); taskbar pins `/etc/taskbar.conf pins=` (own parser in taskbar AND launcher) | `start pin/section` in EXTEND; pins file read by one `conf_pins` module (rule 7) |
| settings pages | built-in `page_*` builders (19) + `pkg_*` pages from SETTINGS; `accounts.settings` already a manifest page | migrate built-in pages one by one to manifest + adapter (the `acct_bind` pattern); no new format |
| tray items | `taskbar.status_build`@2905 (net/sound/battery fixed), `traypop.fi` flyout, `fui.tray` model, `plugbar` | system items register through `tray ... system=true`; app items already via fui.tray; EXTEND gives static default placement |
Relation to roadmap: r1330 (T8: keys in INFO) is the SDK/osdk side — implement it as `EXTEND` as specified here and let `osdk check` lint it; this doc adds the shell side and the data format.

## 5. Migration order (risk + proof)
Gates named here already exist: desktop (`DESKTOP_QUICK=1 heavy bash tools/desktop/run.sh`, 104/0), posix (150/0), startctx (6/0), loginscene/lockscene, tools/qa/gates.sh, ELF diff (`tools/sync/build.sh` flat vs new, `cmp` — proven byte-identical in section 2), screenshot diff (`tools/desktop/run.sh --shots`, compare PNG sets).
| # | step | risk | proof |
|---|---|---|---|
| 0 | land tools/arch + this doc (done here) | none | `layers.py` runs; `migrate.py --check` |
| 1 | `layers.py --baseline-check` into gates.tsv (quick) | none | gate green on main |
| 2 | `git mv` of the leaf layers `cmd/` (74) and `test/` (52) + flat symlinks (`migrate.py --apply --only cmd,test`) | low (no GUI) | posix 150/0, `build.sh` ELF diff of 10 cmds, `migrate.py --check`, scanners (english/i18n/share) equal |
| 3 | `base/` + `services/` (88 files) | low-medium (path greps in tools) | ELF diff for orientbus/odbd/sshd/wmd, ota/osupdate gate quick, ODB gate |
| 4 | `toolkit/` + `shell/` + `apps/` (71 files) | medium: Gegenproben that patch sources, parallel workers editing taskbar/wlib (git rename conflicts) | do it in a quiet window (no open branches touching these files; `git mv` keeps history); desktop 104/0, startctx, loginscene, screenshot diff empty, ELF diff 10/10 |
| 5 | one conf module per config file (taskbar.conf, theme, time, pins) removing 4-5 parsers | medium (behaviour) | desktop 104/0, startctx 6/0, settings/theme gates, screenshot diff |
| 6 | extreg + EXTEND parser; taskbar bar/pin menu on the registry (replace `r == 0/1/2`) | medium | tools/actmenu, startctx, new gate `tools/extreg` (host parser tests + 1 QEMU boot), desktop 104/0 |
| 7 | start menu entries + explorer menus on extreg; settings built-in pages to manifests (one per commit) | medium-high (many pages) | per page: settings gate + a11y scene.sh; screenshot diff |
| 8 | split giants (owners: r1337 wlib; then fuied text area -> delete duplicate ≈560 lines; taskbar -> `shell/taskbar/{conf,layout,paint,hover,menu,main}`; settings -> `apps/settings/page_*`; orientbus -> 6 modules; wlibc theme engine -> toolkit/theme) | high for wlib/wlibc (700 call sites, no re-export), medium others | ELF size delta, desktop 104/0, posix 150/0, latency/idlebudget numbers unchanged |
| 9 | optional: qualified imports + staged FIRNLIB, remove flat symlinks, rewrite tool paths with a script | medium | all gate scripts green without the symlinks |
Rule for every step: one commit per step, `git mv` only (history), gates before merge, no behaviour change in steps 2-4.
Order logic: 2-4 are mechanical and unblock the lint; 5-7 are the extension points the Boss asked for; 8 is the long tail and runs in parallel with other work.

## 6. Open points
- Step 4 collides with parallel work on taskbar.fi / wlib.fi: schedule when those branches are merged.
- `wlibc` split (wmclient vs paint) decides whether `services` may import any toolkit file.
- EXTEND vs keys in INFO (r1330): this doc proposes a separate line manifest (ACTIONS/SETTINGS style); INFO stays key=value.
- No gate yet for `migrate.py --check`; add with step 2.
