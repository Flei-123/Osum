# TOOLKIT-PLAN — gaps in fUi / SDK and the road to a <30 s app loop (21.10.2026)

Plan + measurement only, no build. Sources: docs/SDK.md, docs/FUI-STAND.md, docs/FUI-CONTROLS.md, docs/DEVLOOP.md,
docs/DEV-LOOP-VBOX.md, tools/sdk/{osdk.py,run.sh,template}, kernel/user/fuiscene.fi.
Estimates are marked ESTIMATE; numbers marked MEASURED were taken on the build server (load ~9, 64 cores) on 21.10.2026.

## 1. What exists
- `osdk new/check/build/perms` (host, python): manifest v2 lint (14 refusal cases), bundle `apps/<short>.osp`, rpc service template. `tools/sdk/run.sh` 28/0.
- fUi scene tree (`fuiscene`, `fuiapp`): 80.1 % of GUI program lines; controls: entry, table/list, check, toggle, segmented, slider, choice, progress, tile.
- Action bus (`act`, manifests, `act reload`), RPC (`rpc.fi`, 20-30 us round trip), permissions (8 enforced).
- Signed OTA feed per program (delta), store backend with signature+hash check.

## 2. Gaps (what a third-party author hits)
| # | area | gap | evidence |
|---|---|---|---|
| T1 | Templates | The only app template is a TEXT program (`ulib.say`). No GUI template (window + fuiscene + one button/list), no template with an action manifest, no settings page template. | tools/sdk/template/main-app.fi.in |
| T2 | Build | `osdk build` only compiles; no `run`/`deploy` (push to a VM, start, screenshot). | osdk.py has new/check/build/perms |
| T3 | Preview | **Slice 1 done 21.10.2026 (docs/HOST-PREVIEW.md, `tools/preview/run.sh` 19/0): a11y-tree dump -> PNG + compile watch.** Still open: host runner without a guest dump. Original gap: No host preview: a GUI change needs a guest (QEMU/VBox) to be seen. No scene-tree renderer on the host. | docs/DEVLOOP.md, tools/fui = only share.py/kernvergleich.py/eckecmp.fi |
| T4 | Widgets | Missing as dedicated controls: tabs inside a window body (only 1 hit in fuiscene.fi; the title-bar tab strip is wm), tree view, split pane, dedicated scroll container/virtual list, radio group, spin box, date/time picker, multi-line text area (only fuied's memo), menu bar. Context menu + dialogs exist but are painted by the host (`pop_paint`/`dlg_paint`), not nodes. | FUI-CONTROLS.md, FUI-STAND.md |
| T5 | Icons | Raster icons only; SVG source format missing (roadmap r74 D-017). Apps ship no icon set API. | roadmap r74 |
| T6 | Theming | Roles (`R_*`) follow system theme — good. Missing: app-level accent override, per-app density, documented token list for authors (docs/DESIGN-TOKENS.md is internal). | FUI-CONTROLS.md |
| T7 | Docs | No "write your first GUI app" guide; no widget gallery; examples = system programs (explorer 5 381 lines) — too big to learn from. widgetdemo is the K15 wlib list, not the scene tree (FUI-STAND). | FUI-STAND.md |
| T8 | Extension points | Start menu, context menu, settings pages: not extensible by apps. Action manifests give bus actions only. No "contribute a context-menu entry / settings page / start-menu section" key in INFO. | SDK.md manifest keys |
| T9 | Packaging | `osdk build` emits `bin/` + `apps/` + `mkfs.lines` for the image builder; no signed `.opk` from the SDK, no "publish to dev feed" and no store listing metadata (screenshots, description). | SDK.md |
| T10 | Reload | "Replace a running program" after OTA is UNMEASURED (docs/DEVLOOP.md row A). No `act reload` for the app binary, only manifests. | DEVLOOP.md line 76 |
| T11 | Sandbox | `fs.home` declared only (S-010); toolkit gives no safe file picker portal. | SDK.md |
| T12 | Large scene programs | Every scene program carries the scene host (~1.6 MB); SDK app size is tied to that. | FUI-ALL.md |

## 3. Cycle time "app change -> visible" (MEASURED / documented)
| step | today | source |
|---|---|---|
| edit -> compile one program (`tools/sync/build.sh <dir> 0 calc`, 2 runs) | 7.7 s (calc), 11.0 s (explorer) | MEASURED |
| `osdk build` of a small text app | 0.2 s | MEASURED (3 runs) |
| full image (`tools/usbimg/build.sh`) | ~9-11 min (+ heavy queue 5-30 min) | KNOWLEDGE / DEV-LOOP-VBOX |
| image -> laptop -> VM boot to login | ~8 s transfer + ~25 s | DEV-LOOP-VBOX |
| kernel round (kernel only) | ~1-2 min | KNOWLEDGE |
| OTA path: overlay publish + `ota apply` + `act reload` + app restart | not measured end to end; needs installed disk (stick has 5.4 MB free) | DEVLOOP.md |
| **Standard loop today** | **~12-15 min (no queue) up to ~45 min**; with feed overlay (no full image) ESTIMATE 2-4 min | derived |
| laptop offline | server QEMU instead, not VBox-faithful | DEV-LOOP-VBOX |

Not measured today (laptop HOLO-LAPTOP-3 offline, no device): OTA path end to end, boot-to-login in VBox.

## 4. What brings the loop under 30 s
Budget (ESTIMATE): compile 8-11 s + push 1-2 s + restart app 1 s + screenshot 2 s = 12-16 s. Needs:
1. **`osdk run <project> --target <vm>`** (compile only that program, push `.elf` via jarvisd/bridge write into `/tmp` or the app dir, kill + restart the app, return a screenshot). Bridge already does commands 3.3 s and photos 1.6 s (DEVLOOP.md). Needs the app run from a writable path and `exec` in the bridge command list. ESTIMATE 3-5 days.
2. **Incremental compile cache for apps** (the kernel already has a build cache: warm 1.7 s vs cold 40 s, buildcache-test). Same for `sync/build.sh`: scene host as a precompiled module, only app source recompiled. Target compile < 3 s. ESTIMATE 3-5 days; risk: firnc whole-program model.
3. **Warm VM**: keep one VM booted (snapshot) so no boot is in the loop; `ota`-free push as in 1. Already the rule in DEV-LOOP-VBOX (one test VM).
4. **Live reload in the app** (`act reload app`): re-exec self on a bus event, keep the window rect. Removes manual restart; ESTIMATE 2 days.
5. **Host preview** (fUi scene tree rendered on the host to PNG from a `.fi` scene description or from the `a11y.tree` dump) gives < 5 s for layout work without any VM. Biggest effort (ESTIMATE 2-3 weeks); a cheap first step is rendering the a11y scene dump of a running guest app (exists: tools/a11y/scene.sh).

## 5. Priorities (roadmap)
P0 (loop): `osdk run` (push+restart+shot), app compile cache, measure OTA/replace of a running program (T10).
P1 (authors): GUI app template + 2 small examples (list app, settings-style app), "first app" guide, widget gallery in the scene tree.
P1 (widgets): scrollable/virtual list container, tabs node, radio group, multi-line text area, dialogs + context menu as nodes (FUI-STAND already lists them).
P2: extension points in INFO (`menu.context=`, `settings.page=`, `launcher.section=`), `osdk pack` -> signed opk + dev feed publish, SVG icons, theming docs/tokens for authors.
P3: host preview renderer, tree view, split pane, spin/date picker, file picker portal with the `fs.home` sandbox.

Acceptance for the goal: `osdk run` loop measured with a median of 5 runs on a warm VBox VM, target < 30 s from saved file to screenshot; gate in tools/sdk/run.sh.
