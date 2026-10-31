ROW_W = 324
ROW_H = 56
PAD = 8
WIN_W = ROW_W + 2 * PAD
WIN_H = ROW_H + 2 * PAD

CSS = """
.win { width: %(w)spx; height: %(h)spx; background: var(--panel); position: relative; }
.plate { position: absolute; top: %(pad)spx; height: %(rh)spx; background: var(--plate); border: 1px solid var(--line); border-radius: var(--r-ctl); }
.info { left: %(pad)spx; width: 186px; }
.cover { position: absolute; left: 7px; top: 7px; width: 40px; height: 40px; border-radius: var(--r-ctl); background: var(--accent); display: flex; align-items: center; justify-content: center; color: var(--on-accent); }
.t1 { position: absolute; left: 57px; top: 10px; font-size: 14px; line-height: 17px; color: var(--text); white-space: nowrap; }
.t2 { position: absolute; left: 57px; top: 27px; font-size: 14px; line-height: 17px; color: var(--muted); white-space: nowrap; }
.btn { width: 40px; }
.glyph { position: absolute; left: 12px; top: 20px; width: 14px; height: 14px; }
.bar { position: absolute; background: var(--text); width: 2px; height: 14px; top: 0; }
.tri { position: absolute; top: 0; width: 0; height: 0; border-top: 7px solid transparent; border-bottom: 7px solid transparent; }
""" % {"w": WIN_W, "h": WIN_H, "pad": PAD, "rh": ROW_H}


def glyph(kind):
    if kind == "prev":
        return ('<div class="glyph"><div class="bar" style="left:0"></div>'
                '<div class="tri" style="left:3px;border-right:11px solid var(--text)"></div></div>')
    if kind == "next":
        return ('<div class="glyph"><div class="bar" style="right:0"></div>'
                '<div class="tri" style="left:0;border-left:11px solid var(--text)"></div></div>')
    return ('<div class="glyph"><div class="bar" style="left:2px"></div>'
            '<div class="bar" style="right:2px"></div></div>')


def page(t, base_css, icon):
    c = t["light"]
    css = base_css(t) + ":root { --panel:%s; --plate:%s; --line:%s; --text:%s; --muted:%s; --accent:%s; --on-accent:%s; }" % (
        c["panel"], c["plate"], c["line"], c["text"], c["muted"], c["accent"], c["on_accent"]) + CSS
    btns = "".join(
        f'<div class="plate btn" style="left:{PAD + x}px">{glyph(k)}</div>'
        for x, k in ((192, "prev"), (238, "pause"), (284, "next")))
    info = (f'<div class="plate info"><div class="cover">{icon("volume-2", 20, "#FFFFFF", 2)}</div>'
            f'<div class="t1">Demo-Song</div><div class="t2">Tester</div></div>')
    return (f'<!doctype html><html lang="en"><head><meta charset="utf-8"><style>{css}</style></head><body>'
            f'<div class="win">{info}{btns}</div></body></html>')


def register(pages, icon, base_css):
    pages["qsmedia"] = ((lambda t: page(t, base_css, icon)), WIN_W, WIN_H)
