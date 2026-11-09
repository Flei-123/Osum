#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re, sys, os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
import glob
SRC = "".join(open(p, encoding="latin1").read() for p in [os.path.join(ROOT, "kernel/user/settings.fi")] + sorted(glob.glob(os.path.join(ROOT, "kernel/user/settings/*.fi"))))
PAGES = [
    ("appearance", "R_DARST", "page_darst", "Personalisation"), ("screen", "R_SCREEN", "page_screen", "Display"),
    ("time", "R_TIME", "page_time", "Time & Language"), ("network", "R_NET", "page_network", "Network"),
    ("users", "R_BENUT", "page_benut", "Accounts"), ("netview", "R_NETV", "page_netv", "Network"),
    ("language", "R_SPRACHE", "page_sprache", "Time & Language"), ("presets", "R_VORL", "page_vorl", "Personalisation"),
    ("accounts", "R_ACCOUNT", "page_accounts", "Accounts"), ("sync", "R_SYNC", "page_sync", "Accounts"),
    ("bridge", "R_BRIDGE", "page_bridge", "System"), ("system", "R_SYSTEM", "page_system", "System"),
    ("approights", "R_RECHTE", "page_rechte", "About"), ("log", "R_PROTO", "page_proto", "About"),
    ("updates", "R_UPDATE", "page_update", "Update"), ("mouse", "R_MOUSE", "page_mouse", "System"),
    ("power", "R_ENERGIE", "page_energie", "System"), ("about", "R_INFO", "page_info", "About"),
    ("apps", "R_APPS", "page_apps", "System"),
    ("password", "R_PASSW", "page_passw", "Accounts"), ("pin", "R_PIN", "page_pin", "Accounts"),
    ("transfer", "R_VTRANS", "page_vtrans", "Personalisation"),
    ("sound", "R_SOUND", "page_sound", "System"),
    ("developer", "R_DEV", "page_developer", "System"),
]
INTERACTIVE = ("button", "button_main", "toggle", "choice", "entry", "slider", "table_list")

funcs = {}
for m in re.finditer(r"^fn (\w+)\(", SRC, re.M):
    funcs[m.group(1)] = m.start()
order = sorted(funcs.items(), key=lambda kv: kv[1])
body = {}
for i, (n, s) in enumerate(order):
    e = order[i + 1][1] if i + 1 < len(order) else len(SRC)
    body[n] = SRC[s:e]

def reach(fn, seen):
    if fn in seen or fn not in body:
        return
    seen.add(fn)
    for c in re.findall(r"\b(\w+)\(", body[fn]):
        if c in body and c != fn and not c.startswith(("page_pkg", "nav_", "key_", "tab_")):
            reach(c, seen)

def count(fn):
    seen = set()
    reach(fn, seen)
    cnt = {}
    for f in seen:
        for k in re.findall(r"fuiscene\.(\w+)\(", body[f]):
            cnt[k] = cnt.get(k, 0) + 1
    ctl = sum(cnt.get(k, 0) for k in INTERACTIVE)
    lab = sum(cnt.get(k, 0) for k in ("label", "label_wrap", "label_muted"))
    return ctl, lab, cnt, len(body[fn].splitlines()), sorted(seen)

def main():
    md = "--md" in sys.argv
    limit = 12
    if "--limit" in sys.argv:
        limit = int(sys.argv[sys.argv.index("--limit") + 1])
    rows = []
    for pid, rc, fn, cat in PAGES:
        ctl, lab, cnt, nl, seen = count(fn)
        rows.append((pid, rc, cat, ctl, lab, cnt, nl, len(seen)))
    if md:
        print("| Page id | Const | Category | Controls | of which buttons | toggles | choices | entries | sliders | lists | labels | fn lines |")
        print("|---|---|---|---|---|---|---|---|---|---|---|---|")
    over = 0
    for pid, rc, cat, ctl, lab, cnt, nl, nf in rows:
        b = cnt.get("button", 0) + cnt.get("button_main", 0)
        t = cnt.get("toggle", 0); c = cnt.get("choice", 0)
        e = cnt.get("entry", 0); s = cnt.get("slider", 0); l = cnt.get("table_list", 0)
        if ctl > limit: over += 1
        if md:
            print(f"| {pid} | {rc} | {cat} | **{ctl}** | {b} | {t} | {c} | {e} | {s} | {l} | {lab} | {nl} |")
        else:
            print(f"{pid:11s} ctl={ctl:3d} btn={b:2d} tog={t} cho={c:2d} ent={e:2d} sld={s} lst={l} lab={lab:3d} fn_lines={nl}")
    tot = sum(r[3] for r in rows)
    if "--check" in sys.argv and over:
        print(f"FAIL: {over} page(s) over the limit {limit}")
        print(f"total controls (static, constructor sites): {tot}")
        sys.exit(1)
    print(("\n" if md else "") + f"total controls (static, constructor sites): {tot}; pages over limit {limit}: {over}")

main()
