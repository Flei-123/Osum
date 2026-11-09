# wlibc migration (delete wlibc / wlib)

Goal: no program imports `wlibc` or `wlib`; both modules are deleted. Spec: `docs/ui-system.md`.
Companion: `docs/wlib-migration.md` (wlib widget toolkit, finished for apps; host part behind `fuiapp/apphost`).
Ratchet: `python3 tools/uicheck/wlibuse.py check` (families `wlib` and `wlibc`, baselines
`tools/uicheck/wlib_baseline.tsv`, `wlibc_baseline.tsv`, score per file = imports + refs + unused imports, may only shrink;
`update` after a migration step, `selftest` proves growth is flagged). Run by `tools/uicheck/run.sh`.

## What wlibc is

| file | lines | content |
|---|---|---|
| `wlibc.fi` | 1834 | facade, ~640 exports, forwards to the five parts below |
| `wlibc/wcbase.fi` | 350 | token/metric/semantic tables (`tok`, `met`, `sem`), role ids `C_* S_* M_*` |
| `wlibc/wcpal.fi` | 108 | dark palette values |
| `wlibc/wcgfx.fi` | 1860 | metrics, type scale, shapes, transparency, spacing, text measuring, window-info calls |
| `wlibc/wcpaint.fi` | 1943 | surface, heads/screens, mouse, window protocol calls, clipboard/drag/notify/bus, raw drawing, a11y channel, `ui_scale` |
| `fuiapp/hosthead.fi` | 280 | screen size, heads, display mode, mouse, surface/band state and `map_surface` (host side, step 9) |
| `fuiapp/hostwin.fi` | 230 | `win_*`, `work_*`, `edge_*`, `shm_*`, `layer_rank` window protocol calls (host side, step 9) |
| `fuiapp/hoststart.fi` | 40 | `start` (surface bring-up) |
| `uitheme/th*.fi` | 1130 | former `wctheme`: `thbase` shared state, `thquery` reads, `thfile` file parsing, `thapply` apply + setters, `thload` reload/poll, `thprobe` probes, `thpush` decoration/form/ansi push |

Import graph: `wcbase` <- `wcpal` <- `wcgfx`; `wcgfx` imports `wcpaint`; `uitheme` imports `wcbase`, `wcgfx`;
`wlibc` imports `uitheme`, the `uitheme/th*` modules and `fuiapp/hosthead`; `th*` order: `thquery` < `thfile` < `thapply` < `thload` < `thprobe` < `thpush`; `wcpaint`/`wcgfx` import `hosthead`/`hostwin`, `hoststart` sits on top of `thload`. Bodies must move out of `wcgfx`/`wcpaint`/`wctheme` into their new homes before
the facade can go; forwards come first so each step is pixel-neutral.

## Measured use (09.11., main 6b9430b48 + step 1)

73 importing files, 1600 refs, 302 distinct symbols after step 1 (was 76 files / 395 symbols). `wlibc.<sym>` or
`wcgfx.<sym>`-style refs, grouped by what the symbol really is:

| group | distinct | refs | files | target home |
|---|---|---|---|---|
| window calls (`win_* sys3w sys5 head_* screen_* mouse_* work_* shm_* map_surface surface*`) | 65 | 613 | 53 | `fuiapp/hostwin.fi` (window/surface calls) + `fuiapp/hosthead.fi` (heads, screens, mouse, work area); reached by apps through `fuiapp/apphost` |
| window protocol constants (`L_* WS_* WM_* WI_* WA_* WE_* WL_* WO_*`) | 63 | 297 | 40 | `fuiapp/hostwinp.fi` (wire constants only, like `hostax`, `hostkey`) |
| scale (`ui_scale px_ui px_ui_at win_scale_pct`) | 4 | 181 | 33 | `uiscale.fi`, a leaf module (kernel profile) |
| theme state (`theme_* tb_* edge_* work_* platte* pick_on set_* deco_push form_push`) | 73 | 168 | 17 | `uitheme/` submodules (file, accent, mode, probe, edges) behind `uitheme` |
| text (`F_UI F_BOLD F_MONO text_w text_h ascent_of ink_* fit chars mono_cell glyph*`) | 20 | 154 | 31 | `fuiscene/fscore` text metrics (already used by controls); apps measure through `fuiscene` |
| icons (`icon_* app_icon`) | 22 | 60 | 7 | import `icons` / `appicon` directly (wlibc only forwards them) |
| services (`clip_* drag_* noti_* bus_* BT_*`) | 21 | 55 | 14 | services module (`svcclip`, `svcnoti`, `svcbus`; ecosystem L3) |
| a11y channel (`ax_* AX_* AXP_* AXI_*`) | 22 | 48 | 1 | `fuiapp/hostax.fi` (a11ydemo only) |
| raw draw (`rect frame rrect rframe rring drop_shadow clip_* blend px`) | 11 | 28 | 6 | components only: `fuib`, `uikit/uisurface`; `wmd`/`snip*` keep a private raw module `uidraw.fi` |

Already done: roles/metrics/type/mode constants and `theme()` live in `uitheme` (step 1 below).

Biggest files by refs: themetest 119, qs 87, desktop 80, tbhover 79, setcore 78, tbpaint 74, tbmetrics 60, setarrange 57,
jarvismini 56, a11ydemo 54, fuib 52, notifc 50. All others <= 50.

## Steps (dependency order, one landing each)

1. **DONE** Theme constants + pure forwards (`C_* S_* M_* TY_* MODE_* ACCENT_* EL_* N_* R_* MO_* SHDW_* TRANS_*`, `metric`,
   `type_px/lh/base`, `snap`, `snap_up`, `space`, `radius`, `shape_*`, `transparency`, `win_alpha*`, `win_round`, `aa_old`,
   `elev_*`, `grid`, `hit_min`, `motion`, `shade`, `grad_room`) in `uitheme`; 32 files read them from `uitheme`; `freunde`
   and `widgetboard` drop `import wlibc`. wlibc ratchet added (73 files, score 1673).
2. **DONE** Scale: `uiscale.fi` (leaf, imports only `ulib`) owns `ui_scale`, `px_ui`, `px_ui_at`, `win_scale_pct`, `PX_UI0`;
   wlibc no longer exports them (no forwards: Certus does not use them); 38 files switch; wlibc ratchet 74 -> 72 files, score 1673 -> 1490.
3. **DONE** Window protocol constants (`L_* WS_* WM_* WI_* WA_* WE_* WL_* WO_*`, 97 names incl. `WS_SCALE`, `WI_SCALEPCT`) in `fuiapp/hostwinp.fi`
   (leaf, wire constants only); wlibc and its parts no longer define or export them (no forwards: Certus does not use them);
   `uiscale` drops its private copies; 48 files switch; Certus staging seds `import fuiapp.hostwinp` to `import hostwinp`.
4. **DONE** Text metrics: `uitext.fi` owns `F_UI F_MONO F_ICON F_BOLD`, `text_w`, `text_h`, `ascent_of`, `mono_cell`, `ink_l/t/w/h`
   (bodies out of `wcgfx`/`wcpaint`/`wctheme`; reads the glyph cache through `wcpaint.gfind/gkey/kern26/source_glyph`);
   wlibc no longer exports them (no forwards: Certus does not use them); 34 files switch; apps that only measure for layout
   can move to `fuiscene` labels later.
5. **DONE** Icons: `uiicon.fi` owns `icon_*` and `app_icon` (bodies out of `wctheme`; imports `icons`, `appicon`, `uitheme`, `uiscale`, `uitext`);
   wlibc no longer forwards them (Certus does not use them); 10 files switch.
6. **DONE** a11y channel: `ax_*` (10 calls), `AX_* AXI_* AXP_* AXC_*` and `EV_AXPRESS` live in `fuiapp/hostax.fi` (bodies out of `wcpaint`, constants out of `wlibc`; `hostax` imports `ulib`);
   wlibc no longer exports them (no forwards: Certus does not use them); `a11ydemo`, `wlax`, `wctheme` switch; Certus staging copies `hostax` and seds its import.
7. **DONE** Services: `svcclip.fi` (clipboard, drag, `BT_*`, owns the `noclip` flag via `set_noclip`), `svcnoti.fi` (notification ring), `svcbus.fi` (bus calls, `bus_da`) are leaf modules (import `ulib`/`xfer`);
   bodies out of `wcpaint`, forwards and `WIG_CLIPSET/GET` exports out of `wlibc` (no forwards: Certus does not use them); 13 files switch.
8. **DONE** `wctheme` split into `kernel/user/uitheme/` (eight modules, 51-258 lines each, plus `wlibc/wcstart.fi` for the surface bring-up);
   `wctheme.fi` deleted, `wlibc.fi` forwards to the new modules; no other file imported `wctheme`. Dis proof: `themetest` and `desktop`
   disassembly before/after identical per function (map `wctheme__x` -> `<module>__x`, 7113 / 7291 functions, 0 body diffs). Certus staging copies `uitheme/`.
   Open follow-up: `uitheme` can now own the bodies (drop forwards in `wlibc.fi`), `settings*`, `template`, `theme`, `themetest`, `taskbar*`, `desktop`, `fuib`, `fsdraw` switch to `uitheme`/`thquery` calls.
9. **DONE (host part)** Window/head calls: `hosthead.fi` owns the surface/band/screen/head/mouse state (`s_surf s_sw s_srows s_scap s_band s_pinned s_scr_* s_ready s_hb_*`, `WIG_SCREEN`, `SURF_*`) and `screen_* head_* display_mode_* mouse_* surf_* band_y set_band set_head_bounds start_head_* map_surface ready`;
   `hostwin.fi` owns `win_*` (protocol calls), `work_*`, `edge_*`, `shm_*`, `layer_rank`, `MFD_FRAMES` and the panel flag `s_panel`; `hoststart.fi` owns `start` (was `wlibc/wcstart.fi`); `uitheme/thedge.fi` folded into `hostwin`.
   Bodies out of `wcpaint`/`wcgfx`/`wcstart`/`wcbase`; wlibc no longer exports them (only the `screen_w`/`screen_h` forwards stay: `lib/window/osum.fi` in Firn/Certus calls `wlibc.screen_w/h`); 54 files switch by script;
   `ulib.sys` replaces the private `sys3w` in the new modules. Certus staging copies `hosthead`/`hostwin`/`hoststart`, seds the `fuiapp.hosthead` import and runs `wlibc_asm`+`EXT` over them. wlibc ratchet 60 files / score 900 -> 43 / 341.
9b. **DONE** Theme calls: the 83 `wlibc.theme_* tb_* edge_* work_* set_* deco_push form_push` forwards and 25 `WF_* R_COUNT BLUR_MAX SHAPE_MODERN PAIR_COUNT` constants into `uitheme/th*` are gone from `wlibc.fi`; 19 importers (`themetest`, `settings*`, `template`, `theme`, `taskbar*`, `desktop`, `fuib`, `fsdraw`, `wlib/*`, `qs`, `a11ydemo`) call `thquery.* thapply.* thload.* thprobe.* thpush.*` directly (script, call-for-call). The ratchet no longer counts the `th*` modules as wlibc (they are `uitheme`). wlibc ratchet 43 files / 341 -> 35 / 184; `wlibc.fi` 1002 -> ~620 lines. `apphost` has no wlibc call left (it forwards to `wlib`, whose bodies move in step 11).
10. **Raw draw**: components only; `fuib` uses `uikit/uisurface` primitives; `wmd`, `snip*`, `icont`, `desktop` get `uidraw`.
11. **wlib host bodies**: replace the forward bodies in `fuiapp/apphost` with the moved wlib host code (see wlib-migration.md),
    delete `wlib.fi`, `wlib/`.
12. **Delete wlibc**: `wlibc.fi`, `wlibc/*`; remove the Certus staging sed in `kernel/user/certus/build.sh`; update
    `splitstems.py`, `layers.tsv`, `i18n/scan.py`, gates.tsv paths, SDK template.

Rules: every step is call-for-call identical (pixel parity); gate per step = buildall, uicheck, palette, k15 (scene programs),
desktop quick, plus the touched program's own gate; `python3 tools/uicheck/wlibuse.py update` after the step.

## Certus dependency (not changed from here)

`/root/certus-ui/lib/window/osum.fi` imports `wlib` and `wlibc` directly (907 lines). `kernel/user/certus/build.sh` stages
`fuiapp/wlib*` back under the old names with sed, so steps 1-10 do not break it, but steps 11 and 12 need Certus off wlib.
Used: `wlib.button entry tabs canvas2 canvas_new canvas_event leinwand box_h box_v box_end size step begin window window_app
draw_all closed close alive counts text_of fired_kind`, constants `K_ENTRY K_BUTTON KEY_* LE_DOWN LE_MOVE LE_KEY MAXWN MAXWD`,
`wlibc.screen_w screen_h px_ui`.
Task for the Certus project (a sub-worker may not dispatch, so it is listed in the roadmap): replace in `osum.fi` the
`KEY_*` by `fuiapp/hostkey`, `screen_w/screen_h/px_ui` by `uiscale`/`apphost`, window/canvas/step/draw_all/close/alive/counts by
`fuiapp/apphost`, widgets `button/entry/tabs/box_*` by `fuiscene` controls or delete if dead; list anything missing in `apphost`
for the OrientOS side. Land only with Certus quick green. Certus compile itself is red on old main (stale `.fui-win`, old
`/root/firnc-gc`, `fuib` vs `painter` name clash).
