# wlib / wlibc -> fuiscene migration (M4, Osum r41)

Status: closed. `wlib`/`wlibc` are deleted (`docs/wlibc-migration.md` step 12); the module names below are historical and map to `uitheme/th*`, `fuiapp/hostui/host*`, `uikit/*`.

Goal: one UI toolkit. Apps use `fuiscene` + `kernel/user/uikit` only; the old widget toolkit `wlib`
is deleted; `wlibc` shrinks to the platform layer below fuiscene and then disappears under a new name.
Spec: `docs/ui-system.md` (wins on conflict).

## What the old toolkit is

| module | size | what it really is | fate |
|---|---|---|---|
| `wlib` (+ `wlib/wlax wlbase wldraw wlevent wlstate wlwidget`, `wlibkey`) | ~11 k lines, 296 facade fns | widget toolkit: buttons, lists, fields, menus, event loop, a11y, key codes | **delete**: every user moves to fuiscene controls |
| `wlibc` `wctheme` + `wcpal` | ~1.8 k lines | theme: roles `T_*`, `C_*`, metrics `M_*`, theme file, accent, dark mode, icons | **move** to one theme module (`uitheme`) used by fuiscene, fuib, uikit and apps |
| `wlibc` `wcpaint` + `wcgfx` drawing part | ~2 k lines | raw primitives (rect, frame, rrect, glyphs, text) | only inside components (fuiscene, fuib, uikit); apps go through components |
| `wlibc` `wcpaint` + `wcgfx` platform part | ~2 k lines | window/surface/head ops, cursor, mouse, a11y channel, clipboard, drag, notify, bus | **stays** as platform layer below fuiscene (renamed later); services part becomes the services module (ecosystem L3) |

fuiscene itself is built on wlibc today (`fscore` 32 refs, `fsrun` 10, `fsdraw` 8, `fuib` 60, `fuiapp` 5,
`uikit/uisurface` 8). So wlibc cannot be deleted before its theme and platform parts have new homes.

**The fUi host itself runs on wlib**: `fuiapp` (~50 distinct wlib symbols: window table, canvas widget, `step` event
loop, keys, drop), `fsrun` (a11y roles `AXR_*`, focus, clipboard), `fscore`/`fsctl`/`fsdraw` (window position,
keys `KEY_*`, `ICON_TAG`). A scene window is a wlib window with one canvas. So "delete wlib" = (a) apps stop
calling wlib (they call `fuiscene` / `fuiapp` / `fuiapp/apphost`), (b) the host part of wlib (window table, canvas,
event step, keys, a11y) moves into `kernel/user/fuiapp/` and `fuiscene/`, (c) the widget part (`wldraw`,
`wlwidget` buttons/lists/fields) is deleted once no program builds wlib widgets.

`kernel/user/fuiapp/apphost.fi` is the app-facing host facade (window origin, client origin, `paintdirect`,
`key_mod`, `icon_id`). Today it forwards to wlib; the wlib host code moves behind it step by step. It is excluded
from the wlib ratchet like the toolkit itself.

## Plan (dependency order)

1. **Inventory + ratchet** (this file, `tools/uicheck/wlibuse.py`, baseline `tools/uicheck/wlib_baseline.tsv`):
   wlib score per file may only shrink; checked by `tools/uicheck/run.sh`.
2. **Unused imports** (done 08.11.: 10 programs) and **single-symbol users** via `fuiapp/apphost` (done 08.11.:
   osktest, scenedemo, diskact, backdrop, fvviewer): drop `import wlib` / `import wlibc` where no symbol is used (no pixel change).
3. **Leaf programs** (P1, then P2): replace wlib widgets/events with fuiscene controls; one program per landing,
   gated by uicheck + the program's own gate + desktop quick (heavy, one at a time).
4. **Theme module** (done 08.11. for roles + `theme()`): move `T_*` roles + `theme()` from `wctheme` into `uitheme`; `wlibc.theme` becomes a forwarder,
   fuiscene/fuib/uikit import `uitheme` directly. One role per meaning (table in docs/ui-system.md §1).
5. **Shared modules** (P3: imported by other files) after their users are on fuiscene.
6. **wlib delete**: when the wlib score is 0, remove `wlib.fi`, `wlib/`, `wlibkey.fi`.
7. **wlibc shim**: platform part renamed, services part moved; delete `wlibc.fi` facade.

Rules: pixel parity unless a unification decision is written below (single role per element).
No colour literals, no raw draw outside components, English code, no comments.

## Unification decisions

- 08.11.: no look change so far (both landings are call-for-call identical, pixel parity by construction).
- 08.11. (landing 5): modules with a `profile kernel` header that are only built inside app programs and pull in the
  scene host (calpop, taskview, notifc, traypop, qs, barpop, expmodell, exporte, fpsov, testmark, expakt) now say
  `profile app`. No kernel twin of `fuiapp/apphost` is needed: the host below it is app-only (std.rt). This also fixes
  the stub compile of fpsov, testmark, expakt (r3235). Lock screen closes through `fuiscene.close()`.
- 08.11. (landing 6): `kernel/user/uitheme.fi` owns the `T_*` roles and `theme()` (reads the token table in
  `wlibc/wcbase`); `wlibc` and `wctheme` forward to it; fuiscene, fuib, fuiapp, uikit/uisurface and the apps that
  used `wlibc.T_*` / `wlibc.theme()` import `uitheme` directly. Same numbers, same table: pixel parity.
- 08.11. (landing 7, host part step 1): key numbers moved `wlibkey.fi` -> `kernel/user/fuiapp/hostkey.fi`, a11y wire
  constants (`AXN_* AXR_* AXS_* AXP_BASE`) -> `kernel/user/fuiapp/hostax.fi`; `wlib`/`wlax` forward to them. fuiapp,
  fsrun, fscore, fsctl, fsdraw, pdfview, tabsnode use them directly (117 host refs). `fuiapp/apphost` is `profile kernel`
  (pure forwards), so kernel-header modules may import it too.
- 08.11. (landing 8, host part step 2): the scene runtime (`fsrun`, `fsctl`, `fsdraw`) reaches the window host only
  through `fuiapp/apphost` (begin, window_app/title, focus, clipboard, resize, drop, drag, a11y hooks, trace, ICON_TAG);
  no fuiscene file imports wlib any more. `glogin` closes through `fuiscene.close()`, `themetest` repaints through
  `apphost.dirty_every()/paint_all()`. Pure forwards: pixel parity. German wlib names get English host names
  (`zug_auf` -> `drag_begin`, `win_fokus` -> `win_focused`).
- 08.11. (landing 8, host part step 3): `fuiapp.fi` (window table users: windows, canvas, step, drop, shared buffers,
  relayout) also calls only `fuiapp/apphost`; apphost is now the single place that imports wlib for the fUi host.
  Next: replace the apphost forward bodies with the moved wlib host code (window table, canvas, step, drop).
- 08.11. (landing 8, settings): settings, setaccount, setcore take key numbers from `fuiapp/hostkey` and window
  position / theme switch count from `fuiapp/apphost`; left on wlib: widget kinds `K_*` and tile fields `TL_*` (widgets).

- 08.11. (landing 10): programs that took only key numbers or host calls from wlib switch to `fuiapp/hostkey` /
  `fuiapp/apphost`: rowlist, store, launcher, taskmgr, fuied, explorer (expmenu, expwork), fuiscene/fscore. apphost gains
  drop_count, drag_put, CT_TEXT/CT_PATH, noti_new, nominsize, win_keys, win_cap_strip, win_cap_w, win_strip_h,
  win_strip_drag (pure forwards, pixel parity). Ratchet 20 / 430 -> 12 / 281.

- 08.11. (landing 11): winopts and a11ydemo reach windows, steps and a11y counters through `fuiapp/apphost`
  (window_opts, win_handle, ax_presses, ax_flush, MAXWN); pure forwards, the a11y counter-probe is unchanged.

- 08.11. (landing 12, host part step 4): the boot flag files of the host (`/etc/paintlog`, `/etc/fulldamage`,
  `/etc/paintdirect`, `/etc/nominsize`, `/etc/noglass`, `/etc/eyeold`) are one registry in `kernel/user/fuiapp/hostflags.fi`
  (`on(flag)`, probed once, cached); `wlstate` and `fuiapp/apphost` read it (six copies of the same probe gone). First
  apphost bodies that no longer go through wlib. Same files, same caching: no look change.
- 08.11. (r3234 finding): a popup-window menu for taskbar_ctx/desktop cannot be a plain scene window yet: the window
  manager dismisses popup-layer windows with EV_CLOSE, and the scene host's event step is still wlib's (`wlax` step:
  EV_CLOSE on a non-menu window clears its handle). Needed first: a host flag "dismiss instead of close" in the moved
  host step (r3233); then `uikit` popup menu = hidden `fuiscene.win_open_plain(.., L_POPUP, ..)` window whose tree is the
  in-scene menu (`fuiscene.menu_open` at 0,0; picks via `menu_pick`, Esc via the scene popup), sized like the wlib menu
  (rows text width + 24, min 60), placed with `uikit/uiflyout.clamp_axis`.
- 08.11. (landing 13): `desktop.fi` no longer imports `wlib` (`draw_point` -> `wlibc.px`, the dead `wlib.feed_key` removed:
  the desktop owns no wlib window). No program outside the toolkit imports the wlib family any more; the wlib ratchet
  baseline is empty. `wlib` itself stays only because `fuiapp/apphost` forwards the host part (window table, canvas,
  event step, keys, a11y) to it; deleting `wlib` = moving those bodies behind `apphost`/`fuiscene`. `wlibc` is still
  imported by 75 files (theme, platform, drawing parts) and stays until its parts have new homes.

- 09.11. (landing 14, wlibc plan): `docs/wlibc-migration.md` holds the wlibc plan (12 steps). Step 1 done: theme constants and
  metric/type forwards live in `uitheme`; `wlibuse.py` ratchets both families (wlibc baseline 73 files, score 1673).

## Inventory

Priority: **P1** leaf (no other file imports it) with unused imports or <= 10 refs, **P2** leaf, **P3** shared
module (migrate after its users). "scene" = file already imports fuiscene/fuiapp (mixed). Regenerate with
`python3 tools/uicheck/wlibuse.py doc`.

<!-- INVENTORY:START (generated by tools/uicheck/wlibuse.py doc) -->

Files importing the toolkit: **76** (wlib family: 0, wlibc family only: 76). References: window 1155, theme 387, text 154, icon 60, other 49, draw 47, services 37, a11y 29, widgets 5.

| category | replacement |
|---|---|
| window | fuiscene host (fsrun, fuiapp); platform API stays below fuiscene |
| theme | uitheme roles (planned, today wlibc.theme) / fuiscene.R_* |
| text | fuiscene.label / fscore text metrics |
| icon | fuiscene icon / lib/icons.fi + lib/appicon.fi |
| other | check by hand |
| draw | fuiscene controls, uikit.uisurface (no raw draw in apps) |
| services | platform services module (clipboard, drag, notify, bus): move, not UI |
| a11y | fuiscene a11y tree (scene nodes) |
| widgets | fuiscene controls (button, field, table, menu, dialog, toggle) |

### taskbar (owner: w-tray-icons / w-taskbar-preview-ram)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/barpop.fi` | P3 shared | 0 / 33 | yes | - | 3 / taskbar | **text** ascent_of F_UI; **theme** L_TIP; **window** ui_scale win_state WS_HIDDEN px_ui sys3w WM_MOVE |
| `user/calpop.fi` | P3 shared | 0 / 36 | yes | - | 3 / taskbar | **text** F_UI text_w ascent_of; **theme** L_MENU; **window** ui_scale win_state WS_HIDDEN sys3w head_bx mouse_btn px_ui WM_INFO +8 |
| `user/fpsov.fi` | P3 shared | 0 / 30 | yes | - | 1 / taskbar | **text** ascent_of F_UI; **theme** win_round L_TIP; **window** ui_scale px_ui win_state WS_HIDDEN head_bx head_bw sys3w WM_MOVE |
| `user/notecard.fi` | P3 shared | 0 / 20 | yes | - | 4 / taskbar | **text** F_UI text_w ascent_of; **theme** C_ACCENT C_WARNING C_DANGER type_px C_ON_ACCENT; **window** px_ui ui_scale TY_CAPTION |
| `user/notifc.fi` | P3 shared | 0 / 50 | yes | - | 4 / taskbar | **services** noti_total noti_count noti_peek noti_ noti_prio noti_take; **theme** L_MENU; **window** ui_scale win_state WS_HIDDEN mouse_x mouse_y sys3w mouse_btn WM_INFO +7 |
| `user/qs.fi` | P3 shared | 0 / 87 | yes | - | 5 / taskbar | **text** F_UI text_w fit text_h ascent_of; **theme** theme_dark theme_set_mode L_MENU; **window** ui_scale px_ui win_state WS_HIDDEN sys3w WM_MOVE mouse_btn MODE_DARK +10 |
| `user/qsmedia.fi` | P3 shared | 0 / 6 | yes | - | 1 / taskbar | **text** text_h ascent_of F_UI; **window** ui_scale px_ui |
| `user/taskbar.fi` | P2 leaf | 0 / 26 | yes | - | 0 / taskbar | **other** TY_BODY; **text** ascent_of F_UI; **theme** L_TOP L_NORMAL deco_push form_push theme_sum theme_reload type_px theme_poll; **window** win_state WS_LAYER screen_w screen_h WS_DECO mouse_x mouse_y |
| `user/taskbar/tbhover.fi` | P3 shared | 0 / 79 | no | - | 4 / taskbar | **draw** blend; **icon** icon_vec icon_draw_fit icon_draw_sc icon_draw icon_mid_ink; **other** TY_BODY; **text** text_w F_UI F_HIDDEN text_h; **theme** mix type_px C_BUTTON_FACE radius metric M_DIVIDER C_TEXT_MUTED C_TASKBAR_BG +4; **window** ui_scale mouse_x mouse_y EL_FLAT WE_TOP mouse_btn sys3w sys5 +16 |
| `user/taskbar/tbinput.fi` | P3 shared | 0 / 49 | no | - | 1 / taskbar | **services** drag_an; **theme** L_TOP L_NORMAL; **window** head_field head_present mouse_x mouse_y work_x work_y work_w work_h +14 |
| `user/taskbar/tblayout.fi` | P3 shared | 0 / 37 | no | - | 5 / taskbar | **icon** icon_h icon_w icon_vec icon_ink_wid icon_ok app_icon; **other** TY_BODY; **text** text_w F_UI F_HIDDEN; **theme** type_px snap_up L_NORMAL; **window** ui_scale win_list WL_LAYER WL_ID WL_FLAGS WL_FOCUS WL_NETV WL_TITLE +1 |
| `user/taskbar/tbmetrics.fi` | P3 shared | 0 / 60 | no | - | 7 / taskbar | **icon** icon_have; **other** TY_BODY; **text** text_w F_UI; **theme** C_TASKBAR_BG space type_px metric M_CTRL_H snap C_WARNING tb_alpha_fx +4; **window** ui_scale TY_CAPTION WE_LEFT WE_RIGHT EL_FLAT WE_TOP |
| `user/taskbar/tbpaint.fi` | P3 shared | 0 / 74 | yes | - | 2 / taskbar | **draw** clip_set; **icon** icon_mid_ink icon_ink_w icon_ink_h icon_draw icon_at icon_w icon_ink_hgt icon_ink_top +3; **other** TY_BODY; **text** text_w F_UI; **theme** C_BORDER C_TASKBAR_BG type_px C_DANGER C_BUTTON_FACE; **window** EL_FLAT surf_rows win_act mouse_btn WA_TOGGLE WA_RAISE win_state WS_KEYS +11 |
| `user/taskbar/tbpopup.fi` | P3 shared | 0 / 15 | no | - | 3 / taskbar | **services** noti_total noti_peek noti_prio; **window** win_act mouse_btn ui_scale mouse_x mouse_y WA_HIDE WA_RAISE start_head_set +1 |
| `user/taskbar/tbpreview.fi` | P3 shared | 0 / 1 | no | - | 1 / taskbar | **window** mouse_btn |
| `user/taskbar/tbstatus.fi` | P3 shared | 0 / 26 | no | - | 6 / taskbar | **services** noti_new noti_post; **theme** metric shape_file shape_name shape_id shape_keys M_CTRL_H M_RADIUS_PANEL M_RADIUS_BUTTON +5; **window** edge_name edge_by_name ui_scale work_x work_y work_w work_h |
| `user/taskbar_ctx.fi` | P3 shared | 0 / 2 | no | - | 3 / taskbar | **window** mouse_x mouse_y |
| `user/taskview.fi` | P3 shared | 0 / 49 | yes | - | 4 / taskbar | **theme** L_NORMAL L_MENU; **window** ui_scale win_state WS_HIDDEN win_act sys3w head_bx head_by head_bw +15 |
| `user/testmark.fi` | P3 shared | 0 / 24 | yes | - | 1 / taskbar | **text** ascent_of F_UI; **theme** win_round L_TIP; **window** ui_scale px_ui win_state WS_HIDDEN head_bx head_bw sys3w WM_MOVE |
| `user/traypop.fi` | P3 shared | 0 / 40 | yes | - | 2 / taskbar | **text** ascent_of F_UI; **theme** L_MENU; **window** ui_scale win_state WS_HIDDEN sys3w WM_INFO mouse_btn px_ui WI_ID +11 |

### settings (owner: w-settings-win11-confirm)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/settings.fi` | P2 leaf | 0 / 17 | yes | - | 0 / settings | **text** chars; **theme** theme_reload set_radius set_tb_alpha set_win_alpha set_tb_blur radius tb_alpha tb_blur; **window** ui_scale screen_w screen_h win_alpha display_mode_set |
| `user/settings/setaccount.fi` | P3 shared | 0 / 1 | yes | - | 6 / settings | **window** px_ui |
| `user/settings/setarrange.fi` | P3 shared | 0 / 57 | yes | - | 2 / settings | **window** head_field head_count head_present screen_w screen_h head_scale head_scale_set head_place +1 |
| `user/settings/setbuild.fi` | P3 shared | 0 / 15 | yes | - | 1 / settings | **text** text_w F_UI; **theme** set_shadow_on theme_reload shape_id transparency zieh_lift zieh_tilt zieh_swing blur_staerke +1; **window** edge_name edge_by_name px_ui |
| `user/settings/setcore.fi` | P3 shared | 0 / 78 | yes | - | 9 / settings | **draw** shadow_an; **other** aa_pixels; **text** text_w F_UI; **theme** theme_probe_comp metric tb_alpha theme_bad_keys theme_accent_ok theme_probe_metric M_RADIUS_BUTTON M_SHADOW +30; **window** win_alpha win_info WI_TB_ALPHA_IST TRANS_OFF TRANS_STRONG px_ui |
| `user/settings/setsystem.fi` | P3 shared | 0 / 15 | yes | - | 4 / settings | **draw** shadow_an; **theme** tb_alpha tb_blur radius space; **window** head_field screen_w screen_h head_count head_present head_scale win_alpha |

### components (fuiscene, fuib, fuiapp, uikit) (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/fuiapp.fi` | P3 shared | 0 / 4 | no | - | 35 / 57 | **theme** L_TOP platte platte_ink pick_on |
| `user/fuib.fi` | P3 shared | 1 / 52 | no | - | 11 / 58 | **draw** rrect rframe rring clip_y0 clip_y1 drop_shadow clip_set clip_x0 +3; **theme** metric theme_gen theme_dark C_TITLEBAR_TEXT M_RADIUS_BUTTON M_RADIUS_PANEL M_RADIUS_WINDOW M_RADIUS_INPUT +5; **widgets** canvas; **window** band_y surface surf_w surf_rows ui_scale |
| `user/fuiscene/fscore.fi` | P3 shared | 0 / 37 | yes | - | 6 / 57 | **text** F_UI text_w F_BOLD text_h ascent_of pen_x; **theme** C_ACCENT C_ON_ACCENT; **window** px_ui_at win_act sys3w WM_INFO WI_ID WA_RAISE win_alpha_fx win_info +3 |
| `user/fuiscene/fsctl.fi` | P3 shared | 0 / 3 | yes | - | 4 / 57 | **text** text_w F_UI text_h |
| `user/fuiscene/fsdraw.fi` | P3 shared | 0 / 11 | yes | - | 3 / 57 | **text** F_UI text_w ascent_of; **theme** C_TITLEBAR_OFF_TEXT theme_live C_TITLEBAR_OFF_BG C_TITLEBAR_BG |
| `user/fuiscene/fsfit.fi` | P3 shared | 0 / 4 | yes | - | 1 / 57 | **window** win_info WI_INY work_y work_h |
| `user/fuiscene/fsrun.fi` | P3 shared | 0 / 13 | yes | - | 2 / 57 | **services** drag_an drag_drop; **text** text_w F_UI; **window** win_scale_pct cursor_scene_mode cursor_shape sys3w WM_SIZE |
| `user/uikit/uipopmenu.fi` | P3 shared | 0 / 26 | yes | - | 4 / desktop taskbar | **theme** L_MENU; **window** win_state WS_HIDDEN ui_scale screen_h sys3w mouse_btn px_ui screen_w +8 |
| `user/uikit/uisurface.fi` | P3 shared | 0 / 9 | yes | - | 4 / 57 | **theme** aa_old win_round; **window** ui_scale |

### shared modules (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/appdir.fi` | P3 shared | 0 / 2 | no | - | 3 / explorer launcher | **icon** app_icon |
| `user/backlum.fi` | P3 shared | 0 / 23 | no | - | 3 / 13 | **window** win_damage win_backlum shm_buffer shm_last_fd sys5 WM_CREATE win_opts shm_close +6 |
| `user/displaymode.fi` | P3 shared | 0 / 15 | no | - | 4 / settings taskbar | **window** head_count head_present head_field head_scale display_mode_mirrored display_mode_connected display_mode_set head_place +1 |
| `user/fuied.fi` | P3 shared | 0 / 17 | yes | - | 4 / 57 | **services** clip_take clip_put; **text** px_mono text_h mono_cell ascent_of F_MONO; **window** map_surface ui_scale |
| `user/fuiglyph.fi` | P3 shared | 1 / 7 | no | - | 9 / 58 | **text** glyph_source text_at gload F_UI kern26; **widgets** begin; **window** start |
| `user/signin.fi` | P3 shared | 0 / 19 | yes | - | 2 / glogin lock | **text** F_UI F_BOLD text_w ink_w ink_h ink_l ink_t; **theme** transparency; **window** TRANS_OFF TRANS_STRONG TRANS_SUBTLE |
| `user/template.fi` | P3 shared | 0 / 32 | no | - | 5 / 59 | **theme** radius tb_alpha tb_blur theme_accent_own theme_scheme_file theme_mode shape_file theme_probe +6; **window** MODE_AUTO MODE_LIGHT MODE_DARK edge_by_name edge_name win_alpha ACCENT_BLACK |
| `user/theme.fi` | P3 shared | 0 / 10 | no | - | 8 / 59 | **theme** theme_semantic_name_at theme_probe_pairs theme_probe_pair_fg theme_probe_pair_bg theme_probe_pair theme_reload; **window** MODE_LIGHT MODE_DARK edge_name |
| `user/uitheme.fi` | P3 shared | 0 / 5 | no | - | 27 / 66 | **other** wcbase; **theme** T_COUNT C_COUNT; **window** tok paint_base |

### themetest (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/themetest.fi` | P2 leaf | 0 / 119 | yes | - | 0 / themetest | **theme** theme_semantic C_WINDOW_BG theme_semantic_name_at theme_live theme_set_mode theme_reload theme_frame_begin theme_frame_end +28; **window** S_TEXT_PRIMARY S_SURFACE S_TEXT_SECONDARY S_ON_ACCENT S_ACCENT S_SURFACE_RAISED S_SURFACE_SUNKEN S_SURFACE_HOVER +22 |

### desktop (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/desktop.fi` | P2 leaf | 0 / 80 | yes | - | 0 / desktop | **draw** clip_set px push; **other** EV_CLOSE EV_DOWN EV_MOVE EV_UP EV_KEY; **theme** L_DESK C_DESKTOP_TOP C_DESKTOP_BOTTOM theme_sum L_MENU theme_reload theme_poll theme_scheme_keys; **window** win_state sys3w shm_unmap set_band surf_rows screen_w screen_h WM_CLOSE +20 |
| `user/widgetboard.fi` | P3 shared | 0 / 19 | no | - | 1 / desktop | **other** TY_BODY; **theme** metric snap_up snap M_PAD_X M_PAD_Y type_lh C_ACCENT C_PANEL_BG +3; **window** EL_FLAT |

### jarvismini (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/jarvismini.fi` | P2 leaf | 0 / 56 | yes | - | 0 / jarvismini | **text** F_UI text_w ascent_of; **window** win_info ui_scale win_backlum px_ui WI_WORKX WI_WORKY WI_WORKW WI_WORKH +16 |

### a11ydemo (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/a11ydemo.fi` | P2 leaf | 0 / 54 | yes | - | 0 / a11ydemo | **a11y** ax_info ax_perm ax_read ax_event ax_begin ax_send ax_end ax_set +2; **other** AXP_MINE AXI_LEAKS AXI_COUNT AXI_FOREIGN AXP_GRANT AXI_GEN AXC_HIGH AXC_MAG +4; **theme** theme_contrast; **window** sys3w WM_INFO WI_ID |

### icont (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/icont.fi` | P2 leaf | 1 / 45 | no | - | 0 / icont | **draw** rect get px blend clip_set; **icon** icon_at icon_small icon_ink_w icon_box icon_large icon_ink_h icon_taskbar icon_have; **widgets** fi; **window** surf_w surf_rows start |

### winfloat (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/winfloat.fi` | P2 leaf | 0 / 43 | no | - | 0 / winfloat | **other** EV_KEY; **theme** L_FLOAT L_TOP L_NORMAL; **window** win_state WS_LAYER start sys3w shm_buffer shm_last_fd sys5 WM_CREATE +6 |

### launcher (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/launcher.fi` | P2 leaf | 0 / 40 | yes | - | 0 / launcher | **text** text_h; **theme** C_TEXT_MUTED metric M_ROW L_MENU; **window** screen_h head_field screen_w win_move start_head_get start_head_set head_bh set_head_bounds +9 |

### winopts (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/winopts.fi` | P2 leaf | 0 / 36 | yes | - | 0 / winopts | **theme** L_TOP L_NORMAL; **window** win_set_opac sys3w WM_INFO win_state WS_LAYER WI_INX WI_INY sys5 +2 |

### shmtest (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/shmtest.fi` | P2 leaf | 0 / 34 | no | - | 0 / shmtest | **window** sys3w WM_INFO shm_buffer shm_last_fd sys5 WM_CREATE shm_close win_damage +9 |

### snipt (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/snipgrab.fi` | P3 shared | 0 / 14 | no | - | 2 / snipt | **text** F_HIDDEN; **window** map_surface start screen_w screen_h sys3w WM_LIST WL_BYTES WL_ID +5 |
| `user/snipsave.fi` | P3 shared | 0 / 5 | no | - | 1 / snipt | **draw** BT_TEXT; **other** BT_IMAGE; **services** clip_hist_typ clip_put_typ |
| `user/snipt.fi` | P1 leaf small | 0 / 4 | yes | - | 0 / snipt | **theme** L_TOP L_NORMAL; **window** win_state WS_KEYS |

### wmd (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/wmd.fi` | P2 leaf | 0 / 21 | no | - | 0 / wmd | **draw** WIG_GLYPH WIG_KERN; **window** sys3w sys5 shm_close layer_rank start shm_buffer mouse_x mouse_y +2 |

### snip (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/snip.fi` | P2 leaf | 0 / 20 | yes | - | 0 / snip | **draw** BT_TEXT; **other** BT_IMAGE; **services** clip_hist_typ clip_put_typ; **text** F_HIDDEN; **window** start map_surface screen_w screen_h sys3w WM_LIST WL_BYTES WL_ID +5 |

### floatlock (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/floatlock.fi` | P2 leaf | 0 / 15 | no | - | 0 / floatlock | **theme** L_FLOAT; **window** start shm_buffer shm_last_fd sys5 WM_CREATE win_opts shm_close win_damage +5 |

### mbg (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/mbg.fi` | P2 leaf | 0 / 14 | no | - | 0 / mbg | **other** EV_DOWN; **window** win_damage start screen_w screen_h shm_buffer shm_last_fd sys5 WM_CREATE +4 |

### scaledemo (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/scaledemo.fi` | P2 leaf | 0 / 13 | yes | - | 0 / scaledemo | **window** win_info WI_INX head_hot win_scale_pct WI_INY WI_CAPW |

### decodemo (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/decodemo.fi` | P1 leaf small | 0 / 10 | yes | - | 0 / decodemo | **window** win_info WI_X WI_Y WI_INX WI_INY win_state WS_DECO |

### explorer (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/explorer/expnav.fi` | P3 shared | 0 / 2 | yes | - | 1 / explorer | **window** map_surface |
| `user/explorer/expwork.fi` | P3 shared | 0 / 7 | yes | - | 2 / explorer | **text** text_w F_UI; **theme** metric M_PAD_X; **window** ui_scale |

### installer (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/installer.fi` | P1 leaf small | 0 / 9 | yes | - | 0 / installer | **text** text_w F_UI; **window** px_ui |

### glogin (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/glogin.fi` | P1 leaf small | 2 / 6 | yes | - | 0 / glogin | **theme** L_TOP; **widgets** say_rects begin; **window** screen_w screen_h screen_refresh |

### fvviewer (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/fvviewer.fi` | P1 leaf small | 0 / 6 | yes | - | 0 / fvviewer | **services** clip_put clip_take |

### lock (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/lock.fi` | P1 leaf small | 0 / 6 | yes | - | 0 / lock | **theme** L_TOP; **window** screen_w screen_h screen_refresh |

### nedit (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/nedit.fi` | P1 leaf small | 0 / 6 | yes | - | 0 / nedit | **text** text_w F_UI; **window** map_surface px_ui |

### osk (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/osk.fi` | P1 leaf small | 0 / 6 | yes | - | 0 / osk | **theme** L_FLOAT; **window** screen_w work_y work_h screen_h win_move |

### freunde (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/freunde.fi` | P1 leaf small | 0 / 4 | yes | - | 0 / freunde | **theme** C_SUCCESS C_DANGER C_WARNING C_TITLEBAR_OFF_TEXT |

### storage (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/storage.fi` | P1 leaf small | 0 / 3 | yes | - | 0 / storage | **text** text_w F_UI; **window** px_ui |

### charmap (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/charmap.fi` | P1 leaf small | 0 / 2 | yes | - | 0 / charmap | **services** clip_put clip_take |

### taskmgr (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/taskmgr.fi` | P1 leaf small | 0 / 2 | yes | - | 0 / taskmgr | **icon** icon_ok app_icon |

### viewer (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/viewer.fi` | P1 leaf small | 0 / 1 | yes | - | 0 / viewer | **window** map_surface |

<!-- INVENTORY:END -->
