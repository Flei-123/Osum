# wlib / wlibc -> fuiscene migration (M4, Osum r41)

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

## Inventory

Priority: **P1** leaf (no other file imports it) with unused imports or <= 10 refs, **P2** leaf, **P3** shared
module (migrate after its users). "scene" = file already imports fuiscene/fuiapp (mixed). Regenerate with
`python3 tools/uicheck/wlibuse.py doc`.

<!-- INVENTORY:START (generated by tools/uicheck/wlibuse.py doc) -->

Files importing the toolkit: **78** (wlib family: 20, wlibc family only: 58). References: window 1127, theme 387, widgets 237, text 154, events 125, draw 81, icon 60, other 49, a11y 46, services 39.

| category | replacement |
|---|---|
| window | fuiscene host (fsrun, fuiapp); platform API stays below fuiscene |
| theme | uitheme roles (planned, today wlibc.theme) / fuiscene.R_* |
| widgets | fuiscene controls (button, field, table, menu, dialog, toggle) |
| text | fuiscene.label / fscore text metrics |
| events | fuiscene event loop (fsrun) |
| draw | fuiscene controls, uikit.uisurface (no raw draw in apps) |
| icon | fuiscene icon / lib/icons.fi + lib/appicon.fi |
| other | check by hand |
| a11y | fuiscene a11y tree (scene nodes) |
| services | platform services module (clipboard, drag, notify, bus): move, not UI |

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
| `user/taskbar/tbhover.fi` | P3 shared | 11 / 79 | no | - | 4 / taskbar | **draw** draw_board draw_bar blend draw_point draw_edge3; **icon** icon_vec icon_draw_fit icon_draw_sc icon_draw icon_mid_ink; **other** TY_BODY; **text** text_w F_UI F_HIDDEN text_h; **theme** mix type_px C_BUTTON_FACE radius metric M_DIVIDER C_TEXT_MUTED C_TASKBAR_BG +4; **widgets** MR_BUTTON; **window** ui_scale mouse_x mouse_y EL_FLAT WE_TOP mouse_btn sys3w sys5 +16 |
| `user/taskbar/tbinput.fi` | P3 shared | 0 / 49 | no | - | 1 / taskbar | **services** drag_an; **theme** L_TOP L_NORMAL; **window** head_field head_present mouse_x mouse_y work_x work_y work_w work_h +14 |
| `user/taskbar/tblayout.fi` | P3 shared | 0 / 37 | no | - | 5 / taskbar | **icon** icon_h icon_w icon_vec icon_ink_wid icon_ok app_icon; **other** TY_BODY; **text** text_w F_UI F_HIDDEN; **theme** type_px snap_up L_NORMAL; **window** ui_scale win_list WL_LAYER WL_ID WL_FLAGS WL_FOCUS WL_NETV WL_TITLE +1 |
| `user/taskbar/tbmetrics.fi` | P3 shared | 10 / 60 | no | - | 7 / taskbar | **draw** draw_text_w draw_ascent draw_board draw_text; **events** noti_post; **icon** icon_have; **other** TY_BODY; **text** text_w F_UI; **theme** C_TASKBAR_BG space type_px metric M_CTRL_H snap C_WARNING tb_alpha_fx +4; **widgets** MR_BUTTON; **window** ui_scale TY_CAPTION WE_LEFT WE_RIGHT EL_FLAT WE_TOP |
| `user/taskbar/tbpaint.fi` | P3 shared | 22 / 74 | yes | - | 2 / taskbar | **a11y** step; **draw** draw_board clip_set draw_area draw_line draw_text; **events** menu_win win_count; **icon** icon_mid_ink icon_ink_w icon_ink_h icon_draw icon_at icon_w icon_ink_hgt icon_ink_top +3; **other** TY_BODY; **text** text_w F_UI; **theme** C_BORDER C_TASKBAR_BG type_px C_DANGER C_BUTTON_FACE; **widgets** MR_BUTTON win_x win_y win_w win_h; **window** EL_FLAT surf_rows win_act mouse_btn WA_TOGGLE WA_RAISE win_state WS_KEYS +11 |
| `user/taskbar/tbpopup.fi` | P3 shared | 0 / 15 | no | - | 3 / taskbar | **services** noti_total noti_peek noti_prio; **window** win_act mouse_btn ui_scale mouse_x mouse_y WA_HIDE WA_RAISE start_head_set +1 |
| `user/taskbar/tbpreview.fi` | P3 shared | 0 / 1 | no | - | 1 / taskbar | **window** mouse_btn |
| `user/taskbar/tbstatus.fi` | P3 shared | 0 / 26 | no | - | 6 / taskbar | **services** noti_new noti_post; **theme** metric shape_file shape_name shape_id shape_keys M_CTRL_H M_RADIUS_PANEL M_RADIUS_BUTTON +5; **window** edge_name edge_by_name ui_scale work_x work_y work_w work_h |
| `user/taskbar_ctx.fi` | P3 shared | 9 / 2 | no | - | 3 / taskbar | **a11y** step menu_open; **events** feed_key menu_at menu_close; **widgets** MAXWN; **window** mouse_x mouse_y |
| `user/taskview.fi` | P3 shared | 0 / 49 | yes | - | 4 / taskbar | **theme** L_NORMAL L_MENU; **window** ui_scale win_state WS_HIDDEN win_act sys3w head_bx head_by head_bw +15 |
| `user/testmark.fi` | P3 shared | 0 / 24 | yes | - | 1 / taskbar | **text** ascent_of F_UI; **theme** win_round L_TIP; **window** ui_scale px_ui win_state WS_HIDDEN head_bx head_bw sys3w WM_MOVE |
| `user/traypop.fi` | P3 shared | 0 / 40 | yes | - | 2 / taskbar | **text** ascent_of F_UI; **theme** L_MENU; **window** ui_scale win_state WS_HIDDEN sys3w WM_INFO mouse_btn px_ui WI_ID +11 |

### settings (owner: w-settings-win11-confirm)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/settings.fi` | P2 leaf | 25 / 17 | yes | - | 0 / settings | **text** chars; **theme** theme_reload set_radius set_tb_alpha set_win_alpha set_tb_blur radius tb_alpha tb_blur; **widgets** K_BUTTON K_SLIDER K_TABS K_CHOICE K_MENUBAR; **window** ui_scale screen_w screen_h win_alpha display_mode_set |
| `user/settings/setaccount.fi` | P3 shared | 19 / 1 | yes | - | 6 / settings | **widgets** TL_SURFACE TL_ACCENT TL_FRAME TL_TEXT TL_NAME TILE_FIELDS TL_EDGE TL_TASKBAR +4; **window** px_ui |
| `user/settings/setarrange.fi` | P3 shared | 0 / 57 | yes | - | 2 / settings | **window** head_field head_count head_present screen_w screen_h head_scale head_scale_set head_place +1 |
| `user/settings/setbuild.fi` | P3 shared | 0 / 15 | yes | - | 1 / settings | **text** text_w F_UI; **theme** set_shadow_on theme_reload shape_id transparency zieh_lift zieh_tilt zieh_swing blur_staerke +1; **window** edge_name edge_by_name px_ui |
| `user/settings/setcore.fi` | P3 shared | 26 / 78 | yes | - | 9 / settings | **draw** shadow_an; **other** aa_pixels; **text** text_w F_UI; **theme** theme_probe_comp metric tb_alpha theme_bad_keys theme_accent_ok theme_probe_metric M_RADIUS_BUTTON M_SHADOW +30; **widgets** TILE_FIELDS TL_SURFACE TL_ACCENT TL_TEXT TL_RAISED TL_ONACCENT TL_FRAME TL_TASKBAR +10; **window** win_alpha win_info WI_TB_ALPHA_IST TRANS_OFF TRANS_STRONG px_ui |
| `user/settings/setsystem.fi` | P3 shared | 0 / 15 | yes | - | 4 / settings | **draw** shadow_an; **theme** tb_alpha tb_blur radius space; **window** head_field screen_w screen_h head_count head_present head_scale win_alpha |

### shared modules (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/appdir.fi` | P3 shared | 0 / 2 | no | - | 3 / explorer launcher | **icon** app_icon |
| `user/backlum.fi` | P3 shared | 0 / 23 | no | - | 3 / 13 | **window** win_damage win_backlum shm_buffer shm_last_fd sys5 WM_CREATE win_opts shm_close +6 |
| `user/displaymode.fi` | P3 shared | 0 / 15 | no | - | 4 / settings taskbar | **window** head_count head_present head_field head_scale display_mode_mirrored display_mode_connected display_mode_set head_place +1 |
| `user/fuied.fi` | P3 shared | 28 / 17 | yes | - | 4 / 54 | **draw** set_keymod key_shift key_ctrl; **events** KEY_UP KEY_DOWN KEY_PGUP KEY_PGDN KEY_CTRL_X KEY_LEFT KEY_RIGHT KEY_HOME +10; **services** clip_take clip_put; **text** px_mono text_h mono_cell ascent_of F_MONO; **widgets** fi; **window** map_surface ui_scale |
| `user/fuiglyph.fi` | P3 shared | 1 / 7 | no | - | 9 / 57 | **text** glyph_source text_at gload F_UI kern26; **widgets** begin; **window** start |
| `user/signin.fi` | P3 shared | 0 / 19 | yes | - | 2 / glogin lock | **text** F_UI F_BOLD text_w ink_w ink_h ink_l ink_t; **theme** transparency; **window** TRANS_OFF TRANS_STRONG TRANS_SUBTLE |
| `user/template.fi` | P3 shared | 0 / 32 | no | - | 5 / 58 | **theme** radius tb_alpha tb_blur theme_accent_own theme_scheme_file theme_mode shape_file theme_probe +6; **window** MODE_AUTO MODE_LIGHT MODE_DARK edge_by_name edge_name win_alpha ACCENT_BLACK |
| `user/theme.fi` | P3 shared | 0 / 10 | no | - | 8 / 58 | **theme** theme_semantic_name_at theme_probe_pairs theme_probe_pair_fg theme_probe_pair_bg theme_probe_pair theme_reload; **window** MODE_LIGHT MODE_DARK edge_name |
| `user/uitheme.fi` | P3 shared | 0 / 5 | no | - | 28 / 65 | **other** wcbase; **theme** T_COUNT C_COUNT; **window** tok paint_base |

### components (fuiscene, fuib, fuiapp, uikit) (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/fuiapp.fi` | P3 shared | 0 / 4 | no | - | 34 / 54 | **theme** L_TOP platte platte_ink pick_on |
| `user/fuib.fi` | P3 shared | 1 / 52 | no | - | 11 / 57 | **draw** rrect rframe rring clip_y0 clip_y1 drop_shadow clip_set clip_x0 +3; **theme** metric theme_gen theme_dark C_TITLEBAR_TEXT M_RADIUS_BUTTON M_RADIUS_PANEL M_RADIUS_WINDOW M_RADIUS_INPUT +5; **widgets** canvas; **window** band_y surface surf_w surf_rows ui_scale |
| `user/fuiscene/fscore.fi` | P3 shared | 27 / 37 | yes | - | 5 / 54 | **events** paint_all; **text** F_UI text_w F_BOLD text_h ascent_of pen_x; **theme** C_ACCENT C_ON_ACCENT; **widgets** win_x win_y win_fokus handle win_cap_strip win_strip_h win_cap_w resize_seq +8; **window** px_ui_at win_act sys3w WM_INFO WI_ID WA_RAISE win_alpha_fx win_info +3 |
| `user/fuiscene/fsctl.fi` | P3 shared | 0 / 3 | yes | - | 4 / 54 | **text** text_w F_UI text_h |
| `user/fuiscene/fsdraw.fi` | P3 shared | 0 / 11 | yes | - | 3 / 54 | **text** F_UI text_w ascent_of; **theme** C_TITLEBAR_OFF_TEXT theme_live C_TITLEBAR_OFF_BG C_TITLEBAR_BG |
| `user/fuiscene/fsrun.fi` | P3 shared | 0 / 13 | yes | - | 1 / 54 | **services** drag_an drag_drop; **text** text_w F_UI; **window** win_scale_pct cursor_scene_mode cursor_shape sys3w WM_SIZE |
| `user/uikit/uisurface.fi` | P3 shared | 0 / 9 | yes | - | 4 / 54 | **theme** aa_old win_round; **window** ui_scale |

### themetest (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/themetest.fi` | P2 leaf | 0 / 119 | yes | - | 0 / themetest | **theme** theme_semantic C_WINDOW_BG theme_semantic_name_at theme_live theme_set_mode theme_reload theme_frame_begin theme_frame_end +28; **window** S_TEXT_PRIMARY S_SURFACE S_TEXT_SECONDARY S_ON_ACCENT S_ACCENT S_SURFACE_RAISED S_SURFACE_SUNKEN S_SURFACE_HOVER +22 |

### desktop (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/desktop.fi` | P2 leaf | 15 / 75 | no | - | 0 / desktop | **a11y** menu_open step; **draw** clip_set draw_point push; **events** menu_at menu_close feed_key; **other** EV_CLOSE EV_DOWN EV_MOVE EV_UP EV_KEY; **theme** L_DESK C_DESKTOP_TOP C_DESKTOP_BOTTOM theme_sum theme_reload theme_poll theme_scheme_keys; **widgets** MAXWN win_x win_y win_w win_h; **window** sys3w shm_unmap win_state set_band surf_rows screen_w screen_h WM_CLOSE +19 |
| `user/widgetboard.fi` | P3 shared | 6 / 19 | no | - | 1 / desktop | **draw** draw_text_w draw_board draw_text draw_frame; **other** TY_BODY; **theme** metric snap_up snap M_PAD_X M_PAD_Y type_lh C_ACCENT C_PANEL_BG +3; **widgets** MR_PANEL; **window** EL_FLAT |

### widgetdemo (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/widgetdemo.fi` | P2 leaf | 106 / 7 | no | - | 0 / widgetdemo | **a11y** menu_open step dlg_open; **events** text_x text_base text_fg text_bg rect_x rect_y rect_w rect_h +14; **services** clip_put clip_take; **theme** theme_count theme_selfg; **widgets** size text_of box_end button value MAXWN box_v entry +27; **window** ui_scale mouse_x mouse_y |

### a11ydemo (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/a11ydemo.fi` | P2 leaf | 8 / 54 | yes | - | 0 / a11ydemo | **a11y** ax_info ax_perm ax_read ax_event ax_begin ax_send ax_end ax_set +4; **events** ax_presses window draw_all win_handle; **other** AXP_MINE AXI_LEAKS AXI_COUNT AXI_FOREIGN AXP_GRANT AXI_GEN AXC_HIGH AXC_MAG +4; **theme** theme_contrast; **widgets** begin; **window** sys3w WM_INFO WI_ID |

### jarvismini (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/jarvismini.fi` | P2 leaf | 0 / 56 | yes | - | 0 / jarvismini | **text** F_UI text_w ascent_of; **window** win_info ui_scale win_backlum px_ui WI_WORKX WI_WORKY WI_WORKW WI_WORKH +16 |

### launcher (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/launcher.fi` | P2 leaf | 10 / 40 | yes | - | 0 / launcher | **events** KEY_DOWN KEY_UP KEY_ESC theme_now KEY_LEFT KEY_RIGHT; **text** text_h; **theme** C_TEXT_MUTED metric M_ROW L_MENU; **window** screen_h head_field screen_w win_move start_head_get start_head_set head_bh set_head_bounds +9 |

### explorer (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/explorer/expmenu.fi` | P3 shared | 20 / 0 | yes | - | 1 / explorer | **events** KEY_ESC KEY_BS KEY_DEL KEY_SDEL noti_new; **widgets** drop_count KEY_F5 KEY_F2 KEY_OLD_ENTER KEY_OLD_UP KEY_OLD_LEFT KEY_OLD_RIGHT KEY_CTRL_H +3 |
| `user/explorer/expnav.fi` | P3 shared | 0 / 2 | yes | - | 1 / explorer | **window** map_surface |
| `user/explorer/expwork.fi` | P3 shared | 20 / 7 | yes | - | 2 / explorer | **events** drag_put; **text** text_w F_UI; **theme** metric M_PAD_X; **widgets** icon_id icon_tint CT_PATH CT_TEXT; **window** ui_scale |

### winopts (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/winopts.fi` | P2 leaf | 12 / 36 | yes | - | 0 / winopts | **events** window_opts window; **theme** L_TOP L_NORMAL; **widgets** MAXWN handle begin; **window** win_set_opac sys3w WM_INFO win_state WS_LAYER WI_INX WI_INY sys5 +2 |

### icont (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/icont.fi` | P2 leaf | 1 / 45 | no | - | 0 / icont | **draw** rect get px blend clip_set; **icon** icon_at icon_small icon_ink_w icon_box icon_large icon_ink_h icon_taskbar icon_have; **widgets** fi; **window** surf_w surf_rows start |

### winfloat (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/winfloat.fi` | P2 leaf | 0 / 43 | no | - | 0 / winfloat | **other** EV_KEY; **theme** L_FLOAT L_TOP L_NORMAL; **window** win_state WS_LAYER start sys3w shm_buffer shm_last_fd sys5 WM_CREATE +6 |

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

### taskmgr (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/taskmgr.fi` | P2 leaf | 13 / 2 | yes | - | 0 / taskmgr | **events** KEY_DEL; **icon** icon_ok app_icon; **widgets** icon_id icon_tint KEY_OLD_LEFT KEY_OLD_RIGHT |

### mbg (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/mbg.fi` | P2 leaf | 0 / 14 | no | - | 0 / mbg | **other** EV_DOWN; **window** win_damage start screen_w screen_h shm_buffer shm_last_fd sys5 WM_CREATE +4 |

### scaledemo (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/scaledemo.fi` | P2 leaf | 0 / 13 | yes | - | 0 / scaledemo | **window** win_info WI_INX head_hot win_scale_pct WI_INY WI_CAPW |

### store (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/store.fi` | P2 leaf | 12 / 0 | yes | - | 0 / store | **events** KEY_LEFT KEY_RIGHT KEY_UP KEY_DOWN KEY_ESC KEY_PGDN KEY_PGUP; **widgets** KEY_CTRL_F |

### scenedemo (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/rowlist.fi` | P3 shared | 11 / 0 | yes | - | 1 / scenedemo | **events** KEY_UP KEY_DOWN KEY_PGUP KEY_PGDN KEY_HOME KEY_END |

### decodemo (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/decodemo.fi` | P1 leaf small | 0 / 10 | yes | - | 0 / decodemo | **window** win_info WI_X WI_Y WI_INX WI_INY win_state WS_DECO |

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

### viewer (owner: w-m4-wlib-migration)

| file | prio | wlib / wlibc refs | scene | unused imports | importers / programs | symbols by category |
|---|---|---|---|---|---|---|
| `user/viewer.fi` | P1 leaf small | 0 / 1 | yes | - | 0 / viewer | **window** map_surface |

<!-- INVENTORY:END -->
