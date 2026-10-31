WIN_W = 440
WIN_H = 340

SAMPLE = {"origin": "github.com", "user": "alice", "from": "You"}
ROWS = [("app-window", "origin", "Website"), ("user-round", "user", "Account"), ("key-round", "from", "Requested by")]

CSS = """
:root { --layer: #F8FAFC; --card: #F1F5F9; --stroke: #CBD5E1; --stroke2: #CBD5E1; --accent: #2563EB; --sel: #CFDCFA; --text: #0F172A; --muted: #475569; --subtle: #94A3B8; }
.win { width: %(w)spx; height: %(h)spx; background: var(--layer); position: relative; }
.pad { position: absolute; left: 28px; right: 28px; top: 28px; }
.head { display: flex; align-items: center; height: 32px; }
.head h1 { font-size: 20px; font-weight: 700; letter-spacing: -0.2px; flex: 1; }
.note { font-size: 14px; color: var(--muted); height: 24px; line-height: 24px; margin-top: 5px; }
.body { position: absolute; left: 28px; right: 28px; top: 92px; }
.list { background: var(--card); border: 1px solid var(--stroke); border-radius: var(--r-card); overflow: hidden; }
.li { height: 40px; display: flex; align-items: center; padding: 0 14px 0 9px; gap: 12px; }
.li .nm { flex: 1; font-size: 14px; position: relative; left: -0.5px; }
.li .st { font-size: 13px; color: var(--muted); }
.li svg { color: var(--text); }
.hint { font-size: 13px; color: var(--muted); height: 24px; line-height: 24px; margin-top: 12px; }
.foot { position: absolute; left: 28px; right: 28px; bottom: 28px; height: 36px; display: flex; gap: 8px; }
.b { height: 36px; border-radius: 8px; display: flex; align-items: center; justify-content: center; font-size: 14px; box-sizing: border-box; }
.b.main { width: 140px; background: var(--accent); color: var(--on-accent); border: 1px solid #B4C4EC; }
.b.plain { width: 120px; background: var(--card); color: var(--text); border: 1px solid var(--stroke); }
""" % {"w": WIN_W, "h": WIN_H}


def page(t, base_css, icon):
    rows = "".join(
        f'<div class="li">{icon(ic, 18)}<span class="nm">{SAMPLE[k]}</span><span class="st">{label}</span></div>'
        for ic, k, label in ROWS)
    css = base_css(t) + CSS
    return (f'<!doctype html><html lang="en"><head><meta charset="utf-8"><style>{css}</style></head><body>'
            f'<div class="win"><div class="pad"><div class="head"><h1>Allow access?</h1></div>'
            f'<div class="note">A saved password is about to be shown.</div></div>'
            f'<div class="body"><div class="list">{rows}</div>'
            f'<div class="hint">No answer within a minute counts as Deny.</div></div>'
            f'<div class="foot"><div class="b main">Allow</div><div class="b plain">Deny</div></div></div></body></html>')


def register(pages, icon, base_css):
    pages["vaultprompt"] = ((lambda t: page(t, base_css, icon)), WIN_W, WIN_H)
