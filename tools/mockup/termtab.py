FRAME = "#3F3F46"
BODY = "#09090B"
TEXT = "#FAFAFA"
TITLE_TOP = "#222225"
TITLE_BOTTOM = "#27272A"
WIN_W = 376
WIN_H = 34
TAB_X = 11
TAB_W = 148
TAB_PITCH = 150
TAB_Y = 4
CELL = 32
LABEL_PX = 15
TEXT_Y = 5

CSS = """
body { background: %(body)s; }
.win { position: absolute; left: 0; top: 0; width: %(w)spx; height: %(h)spx; background: %(frame)s; overflow: hidden; }
.bar { position: absolute; left: 1px; top: 1px; right: 0; height: 32px; background: linear-gradient(%(t0)s, %(t1)s); }
.tab { position: absolute; top: %(ty)spx; width: %(tw)spx; height: 40px; border-radius: 6px; background: %(body)s; }
.accent { position: absolute; left: 6px; right: 6px; top: 26px; height: 3px; border-radius: 1px; background: %(frame)s; }
.label { position: absolute; left: 8px; top: %(ly)spx; font: 400 %(px)spx/18px 'Inter', sans-serif; color: %(text)s; white-space: nowrap; }
.cell { position: absolute; width: %(cell)spx; text-align: center; font: 400 %(px)spx/18px 'Inter', sans-serif; color: %(text)s; }
.sep { position: absolute; left: 0; right: 0; top: 33px; height: 1px; background: %(frame)s; }
""" % {"w": WIN_W, "h": WIN_H, "frame": FRAME, "body": BODY, "text": TEXT, "t0": TITLE_TOP, "t1": TITLE_BOTTOM,
       "ty": TAB_Y, "ly": TEXT_Y, "tw": TAB_W, "px": LABEL_PX, "cell": CELL}


def tab(k):
    x = TAB_X + k * TAB_PITCH
    return (f'<div class="tab" style="left:{x}px"><div class="accent"></div><div class="label">Terminal {k + 1}</div></div>'
            f'<div class="cell" style="left:{x + TAB_W - CELL}px;top:{TAB_Y + TEXT_Y}px">x</div>')


def page(t, base_css):
    css = base_css(t) + CSS
    plus = f'<div class="cell" style="left:{TAB_X + TAB_PITCH}px;top:{TAB_Y + TEXT_Y}px">+</div>'
    return (f'<!doctype html><html lang="en"><head><meta charset="utf-8"><style>{css}</style></head><body>'
            f'<div class="win"><div class="bar"></div>{tab(0)}{plus}<div class="sep"></div></div></body></html>')


def register(pages, icon, base_css):
    pages["termtab"] = ((lambda t: page(t, base_css)), WIN_W, WIN_H)
