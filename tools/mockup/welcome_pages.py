WIN_W = 520
WIN_H = 420

TEXT = {
    "lang": {"head": "Choose your language", "note": "The change applies at once."},
    "net": {"head": "Connect to Wi-Fi", "note": "Pick a network. You can skip this and connect later."},
    "done": {"head": "All set", "note": "You can find these steps later in Settings."},
}

NETS = [
    ("HomeNet-5G", "Saved", 4, False),
    ("Office", "Secured", 3, True),
    ("Fritz-Box-72", "Secured", 2, False),
    ("Cafe Guest", "Open", 1, False),
]

LANGS = ["English", "Deutsch"]

DONE_ROWS = [("rotate-cw", "Updates"), ("sun", "Display"), ("settings", "Open settings")]

CSS = """
:root { --layer: #F8FAFC; --card: #F1F5F9; --stroke: #CBD5E1; --stroke2: #CBD5E1; --accent: #2563EB; --sel: #CFDCFA; --text: #0F172A; --muted: #475569; --subtle: #94A3B8; }
.win { width: %(w)spx; height: %(h)spx; background: var(--layer); position: relative; }
.pad { position: absolute; left: 28px; right: 28px; top: 28px; }
.head { display: flex; align-items: center; height: 32px; }
.head h1 { font-size: 20px; font-weight: 700; letter-spacing: -0.2px; flex: 1; }
.note { font-size: 14px; color: var(--muted); height: 24px; line-height: 24px; margin-top: 5px; }
.body { position: absolute; left: 28px; right: 28px; top: 92px; }
.field { display: flex; gap: 4px; align-items: center; }
.field .box { flex: 1; height: 36px; border-radius: var(--r-ctl); background: var(--card); border: 1px solid var(--stroke); border-bottom-color: var(--stroke2);
  display: flex; align-items: center; padding: 0 12px; }
.field .chev { width: 36px; height: 36px; border-radius: var(--r-ctl); display: flex; align-items: center; justify-content: center; border: 1px solid var(--stroke); background: var(--card); }
.list { background: var(--card); border: 1px solid var(--stroke); border-radius: var(--r-card); overflow: hidden; }
.li { height: 40px; display: flex; align-items: center; padding: 0 14px 0 9px; gap: 12px; position: relative; }
.li.sel { background: var(--sel); margin: 0 3px; border-radius: 8px; padding: 0 11px 0 6px; }
.li.sel .st { color: var(--text); }
.li.sel::before { content: ''; position: absolute; left: 0; top: 11px; width: 3px; height: 16px; border-radius: 2px; background: var(--accent); }
.li .nm { flex: 1; font-size: 14px; position: relative; left: -0.5px; }
.li .st { font-size: 13px; color: var(--muted); }
.li .lk { margin-left: 0; display: flex; }
.li svg { color: var(--text); }
.li.sel svg.lead { color: var(--accent); }
.pw { display: flex; gap: 8px; align-items: center; margin-top: 12px; }
.pw .box { width: 340px; height: 36px; border-radius: var(--r-ctl); background: var(--card); border: 1px solid var(--stroke); border-bottom: 1px solid var(--stroke);
  display: flex; align-items: center; padding: 0 12px; color: var(--text); letter-spacing: 2px; }
.pw .go { height: 36px; width: 110px; justify-content: center; padding: 0; border-radius: 8px; background: var(--accent); color: var(--on-accent); font-weight: 400; font-size: 14px; border: 1px solid #B4C4EC; box-sizing: border-box; display: flex; align-items: center; }
.check { display: flex; align-items: center; gap: 8px; margin-top: 18px; font-size: 14px; }
.check .cb { width: 20px; height: 20px; border-radius: 4px; background: var(--accent); display: flex; align-items: center; justify-content: center; color: var(--on-accent); }
.foot { position: absolute; left: 28px; right: 28px; bottom: 28px; height: 40px; display: flex; align-items: center; justify-content: space-between; }
.nb { width: 40px; height: 40px; border-radius: var(--r-ctl); display: flex; align-items: center; justify-content: center; color: var(--text); }
.nb.off { color: var(--subtle); }
.nb.go { color: var(--text); }
.dots { display: flex; gap: 8px; }
.dots i { width: 8px; height: 8px; border-radius: 4px; background: var(--stroke2); }
.dots i.on { background: var(--accent); width: 20px; }
.rbtn { width: 36px; height: 36px; border-radius: var(--r-ctl); display: flex; align-items: center; justify-content: center; color: var(--text); }
""" % {"w": WIN_W, "h": WIN_H}


def dots(active):
    return '<div class="dots">' + "".join(f'<i class="{"on" if k == active else ""}"></i>' for k in range(3)) + "</div>"


def frame(t, base_css, icon, step, body, head_extra=""):
    key = ("lang", "net", "done")[step]
    txt = TEXT[key]
    back = f'<div class="nb{" off" if step == 0 else ""}">{icon("arrow-left", 20, None, 1.8)}</div>'
    fwd = f'<div class="nb go">{icon("check" if step == 2 else "arrow-right", 20, None, 1.8)}</div>'
    css = base_css(t) + CSS
    return (f'<!doctype html><html lang="de"><head><meta charset="utf-8"><style>{css}</style></head><body>'
            f'<div class="win"><div class="pad"><div class="head"><h1>{txt["head"]}</h1>{head_extra}</div>'
            f'<div class="note">{txt["note"]}</div></div><div class="body">{body}</div>'
            f'<div class="foot">{back}{dots(step)}{fwd}</div></div></body></html>')


def page_lang(t, base_css, icon):
    body = (f'<div class="field"><div class="box">{LANGS[0]}</div><div class="chev">{icon("chevron-down", 18)}</div></div>')
    return frame(t, base_css, icon, 0, body)


def page_net(t, base_css, icon):
    rows = ""
    for k, (name, state, bars, sel) in enumerate(NETS):
        lock = f'<span class="lk">{icon("lock", 14)}</span>' if state == "Secured" else ""
        rows += (f'<div class="li{" sel" if k == 1 else ""}">{icon("wifi", 18)}<span class="nm">{name}</span>'
                 f'<span class="st">{state}</span>{lock}</div>')
    body = (f'<div class="list">{rows}</div>'
            f'<div class="pw"><div class="box"></div><div class="go">Connect</div></div>')
    refresh = f'<div class="rbtn">{icon("rotate-cw", 18)}</div>'
    return frame(t, base_css, icon, 1, body, refresh)


def page_done(t, base_css, icon):
    rows = "".join(
        f'<div class="li">{icon(i, 18)}<span class="nm">{label}</span>{icon("chevron-right", 14)}</div>' for i, label in DONE_ROWS)
    body = (f'<div class="list">{rows}</div>'
            f'<div class="check"><div class="cb">{icon("check", 14, None, 3)}</div><span>Show at start</span></div>')
    return frame(t, base_css, icon, 2, body)


def register(pages, icon, base_css):
    for name, fn in (("welcome-lang", page_lang), ("welcome", page_net), ("welcome-done", page_done)):
        pages[name] = ((lambda t, f=fn: f(t, base_css, icon)), WIN_W, WIN_H)
