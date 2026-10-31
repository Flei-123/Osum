# kernel/ui/wm.fi split plan

State: wm.fi had 23996 lines, 851 fns, 573 consts, 166 statics (1590 items). Cut 1 (terminal self-tests) done: `kernel/ui/wm/vtest.fi` 699. Cut 2 done: `wm/wmlayout.fi` 816 (401 items: all S_/W_/K_/F_/E_/L_/DK_/FM_/CAP_ consts, WIN_BYTES, gs/ss/wat/wg/wsv) and `wm/wmgeom.fi` 133 (23 items: uisc, title_h, border, grip, cap_w, close_w, max_w/h, form, FORM_SLOTS, ...); wm.fi 21643.

## Facts (measured with tools/structure)
- Item call graph is a DAG. Only cycle: `backlum` <-> `bl_measure`. So every cut is solvable by moving items, no redesign needed.
- Firn imports must form a tree. A new module may import `ui.wm`, but then `wm.fi` cannot import it. Top-of-DAG clusters (nothing in wm calls them) can be cut first with `import ui.wm`. Everything else needs its dependencies cut below first.
- Module of a state-heavy cluster reaches window state only via `gs/ss` + `S_*`/`W_*` offsets (state lives in `kstate`, not in wm statics). So the base layer is mostly constants and 6 accessors.
- Exports: `wm.fi` has a 120-line export block; callers outside: kgui (489 uses), sysgui (267), gfx (39), wig (20). sysgui stays untouched, so every name it uses (`wm.<name>`) must stay exported by `wm.fi` until sysgui may change.
- A cut that moves items out must add the items it needs from wm to the export block (cut 1: 23 names).

## Clusters (rule-based, tools/structure/clusters.py)
`in` = names of other clusters that call into it. Order = fewest incoming first.

| cluster | lines | in | outside users |
|---|---:|---:|---|
| measure (mess*, measure_*) | 341 | 0 | kgui |
| pixelguard (pg_*) | 136 | 2 | - |
| shadow | 439 | 3 | kgui |
| overlay (fo_*, fps, cadence) | 545 | 3 | kgui |
| magnifier | 209 | 4 | sysgui |
| present (vsync, leser, sig, ph_*) | 464 | 6 | kgui, sysgui |
| trust (td_*, trust_*) | 601 | 7 | sysgui |
| switcher (sw_*) | 439 | 9 | gfx |
| cursor | 528 | 11 | kgui, wig |
| anim | 932 | 11 | kgui, sysgui |
| tabs (tt_*) | 554 | 11 | gfx, kgui, sysgui |
| blur | 1336 | 12 | gfx, kgui, sysgui, wig |
| term (emulator, scrollback, parser) | 2531 | 12 | gfx, kgui, sysgui |
| workarea (work_*, struts, maximize) | 506 | 14 | gfx, kgui, sysgui |
| glass | 1085 | 14 | kgui, sysgui |
| input (ev_*, on_mouse*, on_key, dnd_*) | 1563 | 23 | gfx, kgui, sysgui |
| lifecycle (create, destroy, init) | 461 | 25 | all |
| tiling (tile_*, snap_*, drag_*) | 2249 | 31 | gfx, kgui, sysgui |
| compositor (compose*, flush_*, cp_*, pl_*, lj_*) | 2330 | 31 | kgui, sysgui |
| heads (hd_*, hw_*) | 815 | 33 | gfx, kgui, sysgui |
| chrome (caption, title, paint_win) | 1645 | 41 | kgui, sysgui |
| focus / stack | 606 | 48 | all |
| shape (fill, blend, text, form) | 632 | 51 | kgui, sysgui, wig |
| base (consts, gs/ss, accessors, metrics) | 2088 | 987 | all |

## Target layout (kernel/ui/wm/*.fi, tree of imports, lowest first)
1. `wmlayout.fi` (DONE; named wmlayout because Firn module names are global by last path segment: `layout`/`geom` collide with spirv.layout / touchgest.geom) - all `S_*`, `W_*`, `K_*`, `F_*`, `E_*`, `L_*`, `DK_*`, `FM_*`, `CAP_*` constants, `gs/ss`, window table accessors (`wat`, `wg`, `wsv`, `win_*`). Mirror in `tools/arch/memmap.py` (reads offsets).
2. `wmgeom.fi` (DONE) - `uisc`, `title_h`, `border`, `grip`, `cap_w`, `close_w`, `max_w/h`, `form`. `outer_*`, `work_*`, `hd_*` stay in wm.fi (sysgui uses work_*; outer_* need `deko`/`iny`).
3. `draw.fi`, `shadow.fi`, `blur.fi`, `glass.fi` - pixel primitives and effects (no window logic).
4. `cursor.fi`, `anim.fi`, `measure.fi`, `overlay.fi`, `pguard.fi`, `mag.fi`.
5. `core.fi` - damage, regions, `valid`, `create/destroy`, focus and z-order, `raise_win` (what features need from the server).
6. Features importing core: `term/` (`emu.fi`, `parser.fi`, `scroll.fi`, `select.fi`, `vtest.fi`), `tabs.fi`, `trust.fi`, `switcher.fi`, `tiling/` (`tree.fi`, `snap.fi`, `drag.fi`, `hotkeys.fi`), `heads.fi`, `workarea.fi`, `chrome.fi`.
7. Top: `compose.fi` (`compose_rect`, `compose_one`, `flush_*`), `present.fi`, `present_cp.fi` (cp_/pl_/lj_), `input.fi` (`on_mouse*`, `on_key`, `poll`), and a thin `wm.fi` that re-exports nothing but keeps the public names for sysgui until it may change.

## Registries instead of special cases
- Lifecycle hooks: `destroy` calls `tt_forget`, `set_focus` calls `popups_dismiss_on_focus` and `tl_sel`. Replace with one hook table in `wm/hooks.fi` (`on_create`, `on_destroy`, `on_focus` slots holding function addresses), features register from `init`. This lets features sit above core without core importing them.
- Paint layers: `paint_win` calls `tt_paint`, `tt_paint_plus`, chrome pieces. Replace with a layer table (`order, painter`) filled at init.
- Mouse routing: `on_mouse_btn` (574 lines) calls `tt_press`, `trust`, `cap_*`, tiling hit tests. Replace with an ordered list of `(hit_test, handler)` entries.
- Key routing: `on_key`/`hotkeys` -> table of `(mask, key, action)` rows instead of if-chains.
- Serial reports (`*_say`, `*_say_reset`, `bild_say_reset`): each cluster owns its `say` function; `report.fi` iterates a table of them.

## Order of cuts (each: pure move, no behaviour, own gate run)
1. DONE `wm/vtest.fi` (terminal self-tests, top of DAG, only kgui calls them, 13 fns, 23 exports added).
2. DONE `wm/wmlayout.fi` + `wmgeom.fi`: `tools/structure/requalify.py` qualifies every use in wm.fi (`wmlayout.S_X`), prunes the export block, retargets kgui/gfx/vtest; sysgui stays untouched, so the 13 consts it uses (E_AXPRESS E_CLOSE E_DOWN E_KEY E_UP F_HIDDEN F_NODECO K_TERM L_DESK L_FLOAT L_MAX L_NORMAL L_TOAST) stay as `const X: u64 = wmlayout.X` aliases in wm.fi (drop them when sysgui may change). Locals named like a moved item (`form`) are skipped by hand: revert the qualification inside that fn. Tools: memmap.py W_OFF -> wmlayout.fi, a11y/fields.py E_AXPRESS, gates.tsv `kernel/ui/wm/*` added next to every `kernel/ui/wm.fi`.
3. DONE (cut 3) `wm/wmmeasure.fi` 186 (20 items), `wm/wmbase.fi` 514 (41 items: low layer win_x/y, inx/iny, outer_*, damage*, rgn_*, focus, valid, panel_win, blur_touch; wm.fi keeps 1-line wrappers for the 10 fns sysgui uses), `wm/wmshadow.fi` 336, `wm/wmoverlay.fi` 572, `wm/wmmag.fi` 150 (`say_mag` stays in wm.fi for sysgui). wm.fi 21644 -> 19508. `pguard` NOT cut: pg_* calls compose_rect/cp_on/time_us (closure 285 items) and compose calls pg_*; cut it together with the compositor.
4. DONE (cut 4) `wm/wmdraw.fi` 440 (33 items: fill_*, blend, mix8, mix24, fb_row, text, set_form, form shapes), `wm/wmgate.fi` 77 (input gate: darf/input_allowed, lock_space, sperre_an/lock_active, mods_of, hit), `wm/wmdamage.fi` 69 (damage_win, damage_win_ex, glass_touch), `wm/wmblur.fi` 935 (blur + backlum + win_opac), `wm/wmglass.fi` 677 (glass, box_take, SCHLEIER*), `wm/wmcursor.fi` 349, `wm/wmanim.fi` 417 (44 items; anim_tick, close_anim, minimize_anim, paint_drag_chrome, paint_win_drag stay in wm.fi: they call set_hidden/destroy/ev_push/chrome, cut them with core/chrome). wm.fi 19508 -> 15504. Wrappers kept in wm.fi for sysgui: fill, set_form, text, darf, lock_space, sperre_an, BL_*, backlum, set_opac, win_h, win_w, win_opac, tb_alpha_ist, open_anim, set_min_rect. Local named `tw` collides with fn tw (moved to wmanim): revert `wmanim.tw` where it is a local.
5. DONE (cut 5, partial) `wm/wmtrust.fi` 612 (59 items, trust_ask/cancel/poll wrappers), `wm/wmtabs.fi` 358 (30 items; tt_close_tab, tt_forget, tt_join, tt_press, tt_switch, tt_sync, tt_step stay: they call set_hidden/set_focus/raise_win/destroy/ev_push/resize_win/move_win), `wm/wmswitch.fi` 200 (19 items; sw_commit, sw_step, sw_tick, swipe_do, next/prev_window, paint_switcher stay), `wm/wmterm.fi` 1738 (140 items, term_cols/term_rows wrappers), `wm/wmpresent.fi` (36 items, frame_no/frame_us_n/frame_us_sum wrappers). wm.fi 15504 -> 12227. Not cut: core (lifecycle+focus: set_focus/set_hidden/raise_win/destroy call tt_forget, tl_sel, popups_dismiss_on_focus, tiling, workarea) and anim_tick/close_anim/minimize_anim/paint_*_drag.
   Hook table feasibility: Firn supports `fn(u64, u64) -> u64` fields in a `struct` filled with function names (idiom of kernel/fs/vfsops.fi `struct Ops`, `lookup: f_lookup`). Plan: `wm/wmhooks.fi` with `struct Hooks { on_destroy, on_focus, on_hide }`, one static instance, registered from wm `init`; core calls `hooks.on_destroy(state, i)` instead of `tt_forget`. This changes the call from direct to indirect, so disdiff will show those call sites; the cut is not byte-identical there.
6. `term/*` (2531 lines), then `tiling/*`.
7. `chrome`, `heads`, `workarea`, then `compose`, `present`, `input`; `wm.fi` left as facade < 1500 lines.
8. Each cut: English comments only where the Boss asks (default none), identifiers English with tools/english (rn.py, scoped_rename.py).

## Proof method (used for cut 1)
- `tools/structure/extract.py --names a,b,c --out kernel/ui/wm/x.fi --header h --apply` moves items, strips comments, qualifies dependencies with `wm.`; export block is extended by hand from `--deps`.
- Build kernel before and after (`tools/build-kernel.sh`, 15 s), `objdump -d -M intel --no-show-raw-insn`, then `tools/structure/disdiff.py before.dis after.dis old=new...`: per function normalised bodies must be equal.
- Known noise: `mov esi,<file id>` shifts by one when a source file is added (all functions with a panic site), and `_boot` (multiboot header bytes read as code). Cut 1 result: 13573 functions on both sides, 0 missing, 0 body diff after those two normalisations.
- Gates: k15, desktop quick, lockscene, alttab, tabstrip, fourbugs, comp/chrome.sh.
