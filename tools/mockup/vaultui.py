WIN_W = 440
WIN_H = 300

CSS = """
:root { --layer: #F8FAFC; --card: #F1F5F9; --stroke: #CBD5E1; --stroke2: #CBD5E1; --accent: #2563EB; --text: #0F172A; --muted: #475569; --subtle: #94A3B8; }
.win { width: %(w)spx; height: %(h)spx; background: var(--layer); position: relative; }
.pad { position: absolute; left: 28px; right: 28px; top: 28px; }
.head { display: flex; align-items: center; height: 32px; }
.head h1 { font-size: 20px; font-weight: 700; letter-spacing: -0.2px; flex: 1; }
.note { font-size: 14px; color: var(--muted); height: 24px; line-height: 24px; margin-top: 5px; }
.body { position: absolute; left: 28px; right: 28px; top: 92px; }
.entry { height: 40px; border-radius: var(--r-ctl); background: var(--card); border: 1px solid var(--stroke); border-bottom-color: var(--stroke2);
  display: flex; align-items: center; padding: 0 12px; font-size: 14px; color: var(--subtle); }
.msg { font-size: 14px; color: var(--muted); height: 24px; line-height: 24px; margin-top: 12px; }
.foot { position: absolute; left: 28px; right: 28px; bottom: 28px; height: 36px; display: flex; gap: 8px; }
.b { height: 36px; border-radius: 8px; display: flex; align-items: center; justify-content: center; font-size: 14px; box-sizing: border-box; }
.b.main { width: 140px; background: var(--accent); color: var(--on-accent); border: 1px solid #B4C4EC; }
.b.off { width: 140px; background: #E2E8F0; color: #F8FAFC; border: 1px solid var(--stroke); }
.b.plain { width: 120px; background: #E2E8F0; color: var(--text); border: 1px solid var(--stroke); }
""" % {"w": WIN_W, "h": WIN_H}


def page(t, base_css, off=False):
    css = base_css(t) + CSS
    return (f'<!doctype html><html lang="en"><head><meta charset="utf-8"><style>{css}</style></head><body>'
            f'<div class="win"><div class="pad"><div class="head"><h1>Unlock your vault</h1></div>'
            f'<div class="note">Enter your PIN to open the saved logins.</div></div>'
            f'<div class="body"><div class="entry">{"" if off else "PIN"}</div>'
            f'<div class="msg">{"The vault service is not running." if off else "The PIN has 4 to 12 digits."}</div></div>'
            f'<div class="foot"><div class="b {"off" if off else "main"}">Unlock</div><div class="b plain">Cancel</div></div></div></body></html>')


def register(pages, icon, base_css):
    pages["vaultui"] = ((lambda t: page(t, base_css)), WIN_W, WIN_H)
    pages["vaultui-nosvc"] = ((lambda t: page(t, base_css, True)), WIN_W, WIN_H)
