#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import itemgraph  # noqa: E402

RULES = [
    ("term", r"^(term_|cell_|tsel_|tcur_|sb_|tp_|tc_|vt_|vt2_|grid_|diag|failbits|pass_ok|selftest$|selftest_max|tkicks|tcopies|tpastes|tpaste_|mon_hotkey|attr_clear|bind_tty|tty_of|key_tty|NO_TTY|TERM_|TC_|TSEL_|SB_|TP_|VT_)"),
    ("tabs", r"^(tt_|TT_)"),
    ("trust", r"^(td_|trust_|TD_|TRUST_)"),
    ("switcher", r"^(sw_|SW_|swipe_|swipes_|paint_switcher|next_window|prev_window|wechselbar)"),
    ("tiling", r"^(nd_|tl_|tile_|snap_|float_|leaf_at|fit_rect|paint_bar|paint_preview|pv_|preview_|set_preview|kachelbar|win_tabbed|save_geom|restore_geom|reframe|place_win|hot_take_raw|win_arrow|damage_tile|set_tile_on|tiled|plugkeys|hotkeys|TL_|ND_|SNAP_|screen_|on_screen_resize|drag_hover|drag_begin|drag_end|drag_klemmen|rumpf_neu|gest_action)"),
    ("magnifier", r"^(mag_|say_mag|paint_mag|MAG_)"),
    ("overlay", r"^(fo_|fps_|cad_|cadence_|present_driver|present_count|repaint_hotkey|mon_apply|last_paint_tsc|FO_|CAD_)"),
    ("measure", r"^(mess|measure_|MESS_)"),
    ("blur", r"^(blur_|bl_|backlum|rim_mix|deckt_schirm|recip_of|bdiv|win_opac|set_opac|win_durch|fb_row_mix|BLUR_|BL_)"),
    ("glass", r"^(glass_|glas_|glastest|selftest_glas|selftest_damage|damagetest|tb_alpha|hell_von|fb_row|schlieren_say|rahmen_say|panel_grows|set_noglasgrow|blur_line|GLASS_|GL_)"),
    ("chrome", r"^(cap_|cg_|paint_title|deco_title|deco_schrift|grad_room|nodeco_radius|rund_|paint_caption|lum3|shade24|mix24|paint_close_classic|paint_win$|title_|damage_caption|CAP_|CG_)"),
    ("shadow", r"^(shadow_|mask_run|edge_run|isqrt|ring_round|paint_shadow|SHADOW_|SH_)"),
    ("anim", r"^(anim_|ease_out|open_anim|close_anim|minimize_anim|set_min_rect|min_rect_w|swing_|abklingen|zieh_|ohne_fr|set_noanim|drag_lift|drag_tilt|drag_swing|drag_scale|lift_px|drag_paint_on|paint_drag_chrome|paint_win_drag|paint_win_anim|damage_win_lift|is_dragged|drag_px|swings|ANIM_)"),
    ("present", r"^(present|pend_|pending|presents|skipped|set_vsync|vsync_on|set_leser|liest|risse|tear_|riss_|verworfen|before_|leser_tick|set_sig|sig_|frame_no|paint_sig|ph_|without_sig|pxsum|frame_us|frame_ueber|frame_fach)"),
    ("pixelguard", r"^(pg_)"),
    ("compositor", r"^(compose|flush_|rects_merge|cp_|pl_|lj_|CP_|PL_|LJ_|time_us|wm_note|detach_buf|attach_buf|win_shm|shared_ok|kern_shared|sh_stat|tab_plain|tab_object|chrome_object|tab_publish|damage_rect|bild_say|tw$)"),
    ("heads", r"^(hd_|hw_|head_|win_head|win_work|heads_sync|display_mode|set_display_mode|HD_|HW_)"),
    ("workarea", r"^(work_|struts|workcalcs|nostrut|set_nostrut|set_strut|win_strut|recalc_work|is_max|fit_work|refit_max|maximize|fullscreen|full_say|is_full|unter_leiste)"),
    ("cursor", r"^(cursor_|cur_|shape|margin_cursor|grip_mask|set_shape|hwcur|hw_an|hw_zeigen|hw_bewegen|paint_cursor|set_cursor|curx|cury)"),
    ("input", r"^(ev_|on_mouse|on_key|poll|ps2_poll|hit$|wheel_out|hwheel_out|dnd_|popup_outside|mods_of|win_keys|downs|moves_seen|hits_seen|sperre|lock_space|darf|input_seen|set_keys|keyin|popups_dismiss)"),
    ("lifecycle", r"^(create|destroy|init$|set_app|win_app|set_title|valid|count)"),
    ("focus", r"^(focus|set_focus|raise_win|zslot|move_to_z|at_z|topmost|top_visible|close_top|close_term|set_layer|set_hidden|set_deco$|layer_rank|move_win|resize_win|keep_resized|resize_clear)"),
    ("shape", r"^(fill_|px_clip|hline_a_clip|ring_|form|set_form|aa_px|paint_reset|shape|wpixel|wget|fill$|fill_words|copy_words|blend|mix8|text$|draw_glyph|blit_in|fb_glyph|imax|imin)"),
]


def classify(name):
    for cl, pat in RULES:
        if re.search(pat, name):
            return cl
    return None


def main():
    path = sys.argv[1]
    first = int(sys.argv[2])
    raw, lines = itemgraph.load(path)
    items = itemgraph.with_refs(lines, itemgraph.parse_items(lines, first))
    by = {it["name"]: it for it in items}
    cl = {}
    for it in items:
        c = classify(it["name"])
        if c:
            cl[it["name"]] = c
    users = {n: set() for n in by}
    for n, it in by.items():
        for u in it["uses"]:
            users[u].add(n)
    for rounds in range(6):
        for n, it in by.items():
            if n in cl:
                continue
            us = {cl.get(x) for x in users[n]}
            if us and None not in us:
                cl[n] = us.pop() if len(us) == 1 else "base"
    unassigned = [n for n in by if n not in cl]
    for n in unassigned:
        cl[n] = "base"
    sizes = {}
    for n, it in by.items():
        sizes[cl[n]] = sizes.get(cl[n], 0) + it["end"] - it["head"]
    edges = {}
    for n, it in by.items():
        for u in it["uses"]:
            if cl[u] != cl[n]:
                edges.setdefault((cl[n], cl[u]), set()).add(u)
    return by, cl, sizes, edges


if __name__ == "__main__":
    by, cl, sizes, edges = main()
    for c, s in sorted(sizes.items(), key=lambda x: -x[1]):
        print("%-11s %6d" % (c, s))
    for (a, b), names in sorted(edges.items()):
        print("%s -> %s (%d)" % (a, b, len(names)))
