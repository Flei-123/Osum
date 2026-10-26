#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/preview/axpng.py -- host preview of an Osum window: the a11y tree
dump (`act call a11y.tree window=<title>`) rendered to a PNG, no VM needed.

  python3 tools/preview/axpng.py <dump.txt> -o out.png [--window TITLE] [--dark]
                                 [--scale N] [--list] [--json]

Input: any text that contains node lines of axd.fi `line()`:
    node.<i>=<role> win<id> <x>,<y> <w>x<h> <flags|-> "<name>" [act=..] [value=..]
(a serial log is fine: other lines are ignored). The tree is the same one a
screen reader gets, so the picture is a WIREFRAME: right places, roles, names,
states; colours and fonts are an approximation of the theme, NOT pixel truth.
Use it to see/test layout without booting a guest; use the guest screenshot
for the final look.

--json prints the parsed nodes (machine check); --list prints the windows.
Exit 1 when no node of the window was found.
"""
import argparse, json, re, sys

NODE = re.compile(
    r'node\.(\d+)=(\w+) win(\d+) (-?\d+),(-?\d+) (\d+)x(\d+) (\S+) "((?:[^"\\]|\\.)*)"'
    r'(?: act=(\S+))?(?: value=(-?\d+))?')

THEMES = {
    "light": dict(bg=(243, 243, 243), face=(253, 253, 253), border=(200, 200, 200),
                  text=(28, 28, 28), muted=(110, 110, 110), accent=(0, 95, 184),
                  field=(255, 255, 255)),
    "dark": dict(bg=(32, 32, 32), face=(55, 55, 55), border=(90, 90, 90),
                 text=(240, 240, 240), muted=(170, 170, 170), accent=(96, 165, 232),
                 field=(45, 45, 45)),
}


def parse(text):
    nodes = []
    for m in NODE.finditer(text):
        i, role, wid, x, y, w, h, fl, name, act, val = m.groups()
        nodes.append(dict(i=int(i), role=role, win=int(wid), x=int(x), y=int(y),
                          w=int(w), h=int(h),
                          flags=[] if fl == "-" else fl.split(","),
                          name=name.replace('\\"', '"'), act=act or "",
                          value=int(val) if val is not None else None))
    return nodes


def windows(nodes):
    return [n for n in nodes if n["role"] == "window"]


def pick(nodes, title):
    """Last dump of the wanted window: the window node plus the nodes that
    follow it with the same window id (a log may hold several dumps)."""
    ws = [n for n in windows(nodes) if not title or title in n["name"]]
    if not ws:
        return None, []
    wn = ws[-1]
    pos = max(k for k, n in enumerate(nodes) if n is wn)
    out = [wn]
    for n in nodes[pos + 1:]:
        if n["role"] == "window" or n["win"] != wn["win"]:
            break
        out.append(n)
    return wn, out


def render(win, nodes, theme="light", scale=1, pad=8):
    from PIL import Image, ImageDraw, ImageFont
    th = THEMES[theme]
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 12 * scale)
        bold = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 12 * scale)
    except OSError:
        font = bold = ImageFont.load_default()
    ox, oy = win["x"], win["y"]
    # canvas = window rect united with every node (nodes may stick out: that is a finding)
    right = max([win["x"] + win["w"]] + [n["x"] + n["w"] for n in nodes])
    bottom = max([win["y"] + win["h"]] + [n["y"] + n["h"] for n in nodes])
    W, H = (right - ox + 2 * pad) * scale, (bottom - oy + 2 * pad) * scale
    img = Image.new("RGB", (W, H), (120, 120, 120))
    d = ImageDraw.Draw(img)

    def box(n):
        x = (n["x"] - ox + pad) * scale
        y = (n["y"] - oy + pad) * scale
        return x, y, x + n["w"] * scale - 1, y + n["h"] * scale - 1

    def text(n, col, f=font, center=False, name=None):
        x0, y0, x1, y1 = box(n)
        s = n["name"] if name is None else name
        tw = d.textlength(s, font=f)
        tx = x0 + ((x1 - x0 - tw) / 2 if center else 6 * scale)
        d.text((tx, (y0 + y1) / 2), s, fill=col, font=f, anchor="lm")

    x0, y0, x1, y1 = box(win)
    d.rectangle((x0, y0, x1, y1), fill=th["bg"], outline=th["border"])
    for n in nodes[1:]:
        if "hidden" in n["flags"]:
            continue
        r, b = n["role"], box(n)
        en = "enabled" in n["flags"]
        tcol = th["text"] if en or r in ("label", "tab") else th["muted"]
        if r == "button":
            d.rounded_rectangle(b, 4 * scale, fill=th["face"], outline=th["border"])
            text(n, tcol, center=True)
        elif r == "check":
            s = min(n["h"], 16) * scale
            cy = (b[1] + b[3]) // 2
            d.rectangle((b[0], cy - s // 2, b[0] + s, cy + s // 2), outline=th["border"],
                        fill=th["accent"] if "checked" in n["flags"] else th["field"])
            d.text((b[0] + s + 6 * scale, cy), n["name"], fill=tcol, font=font, anchor="lm")
        elif r in ("entry", "password"):
            d.rectangle(b, fill=th["field"], outline=th["border"])
            if "focused" in n["flags"]:
                d.rectangle((b[0], b[3] - scale, b[2], b[3]), fill=th["accent"])
            text(n, tcol, name=n["name"] if r == "entry" else "•" * 8)
        elif r == "tab":
            sel = "selected" in n["flags"]
            d.rectangle(b, fill=th["face"] if sel else th["bg"], outline=th["border"])
            if sel:
                d.rectangle((b[0] + 4 * scale, b[3] - 2 * scale, b[2] - 4 * scale, b[3]), fill=th["accent"])
            text(n, tcol, bold if sel else font, center=True)
        elif r in ("list", "table"):
            d.rectangle(b, fill=th["field"], outline=th["border"])
            text(n, th["muted"])
        elif r == "choice":
            d.rectangle(b, fill=th["face"], outline=th["border"])
            text(n, tcol)
            cy = (b[1] + b[3]) // 2
            d.polygon([(b[2] - 14 * scale, cy - 2 * scale), (b[2] - 6 * scale, cy - 2 * scale),
                       (b[2] - 10 * scale, cy + 3 * scale)], fill=th["muted"])
        elif r == "slider":
            cy = (b[1] + b[3]) // 2
            d.rectangle((b[0], cy - scale, b[2], cy + scale), fill=th["border"])
            frac = max(0, min(1000, n["value"] or 0)) / 1000
            kx = int(b[0] + frac * (b[2] - b[0]))
            d.ellipse((kx - 6 * scale, cy - 6 * scale, kx + 6 * scale, cy + 6 * scale), fill=th["accent"])
        elif r == "menubar":
            d.rectangle(b, fill=th["face"], outline=th["border"])
        elif r == "separator":
            d.line((b[0], b[1], b[2], b[3]), fill=th["border"])
        elif r == "scrollbar":
            d.rectangle(b, fill=th["border"])
        elif r == "label":
            text(n, tcol)
        else:
            d.rectangle(b, outline=th["border"])
            text(n, th["muted"])
        if "focused" in n["flags"] and r not in ("entry", "password"):
            d.rectangle((b[0] - scale, b[1] - scale, b[2] + scale, b[3] + scale), outline=th["accent"])
    return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dump")
    ap.add_argument("-o", "--out")
    ap.add_argument("--window", default="")
    ap.add_argument("--dark", action="store_true")
    ap.add_argument("--scale", type=int, default=1)
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    nodes = parse(open(a.dump, "rb").read().decode("latin-1"))
    if a.list:
        for w in windows(nodes):
            print(f'win{w["win"]} {w["x"]},{w["y"]} {w["w"]}x{w["h"]} "{w["name"]}"')
        return 0
    win, ns = pick(nodes, a.window)
    if not win:
        print("no window" + (f' matching "{a.window}"' if a.window else "") + " in dump", file=sys.stderr)
        return 1
    if a.json:
        json.dump(ns, sys.stdout, indent=1)
        print()
    if a.out:
        render(win, ns, "dark" if a.dark else "light", a.scale).save(a.out)
        print(f'{a.out}: window "{win["name"]}" {win["w"]}x{win["h"]}, {len(ns) - 1} nodes')
    return 0


if __name__ == "__main__":
    sys.exit(main())
