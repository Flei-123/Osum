#!/usr/bin/env python3
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
ICON_DIRS = [os.environ.get("LUCIDE_DIR", "/root/icon-src/lucide/icons"), os.path.join(REPO, "assets/icons/svg")]

STATE_LABEL = {"install": "Installieren", "open": "Öffnen", "update": "Aktualisieren"}


def icon(name, size=20, stroke=None, width=2):
    for d in ICON_DIRS:
        p = os.path.join(d, name + ".svg")
        if os.path.exists(p):
            body = open(p, encoding="utf-8").read()
            body = re.sub(r"<!--.*?-->", "", body, flags=re.S)
            inner = re.search(r"<svg[^>]*>(.*)</svg>", body, re.S).group(1)
            col = stroke or "currentColor"
            return (f'<svg width="{size}" height="{size}" viewBox="0 0 24 24" fill="none" stroke="{col}" '
                    f'stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round">{inner}</svg>')
    raise SystemExit("icon missing: " + name)


def base_css(t):
    c = t["light"]
    f = t["font"]
    font_dir = os.path.join(REPO, "assets/src")
    return f"""
@font-face {{ font-family: 'Inter'; src: url('file://{font_dir}/Inter-Regular.ttf'); font-weight: 400; }}
@font-face {{ font-family: 'Inter'; src: url('file://{font_dir}/Inter-SemiBold.ttf'); font-weight: 600; }}
:root {{ --bg:{c['bg']}; --layer:{c['layer']}; --card:{c['card']}; --stroke:{c['stroke']}; --stroke2:{c['stroke_strong']};
  --text:{c['text']}; --muted:{c['muted']}; --subtle:{c['subtle']}; --accent:{c['accent']}; --on-accent:{c['on_accent']};
  --hover:{c['hover']}; --sel:{c['selected']}; --shadow:{c['shadow']};
  --r-ctl:{t['radius']['control']}px; --r-card:{t['radius']['card']}px; --r-icon:{t['radius']['icon']}px; }}
* {{ box-sizing: border-box; margin: 0; padding: 0; }}
html, body {{ width: 100%; height: 100%; overflow: hidden; }}
body {{ font-family: '{f['family']}', sans-serif; font-size: {f['body']}px; line-height: {f['line']}; color: var(--text);
  background: var(--bg); -webkit-font-smoothing: antialiased; }}
.ibtn {{ width: 32px; height: 32px; border-radius: var(--r-ctl); display: inline-flex; align-items: center; justify-content: center; color: var(--text); }}
.ibtn.off {{ color: var(--subtle); }}
.ibtn.hover {{ background: var(--hover); }}
.search {{ height: 32px; border-radius: var(--r-ctl); background: var(--card); border: 1px solid var(--stroke); border-bottom-color: var(--stroke2);
  display: flex; align-items: center; gap: 8px; padding: 0 10px; color: var(--subtle); }}
.btn {{ height: 28px; padding: 0 14px; border-radius: var(--r-ctl); font-weight: 600; font-size: 12px; display: inline-flex; align-items: center; justify-content: center;
  border: 1px solid var(--stroke); background: var(--card); color: var(--text); min-width: 96px; }}
.btn.accent {{ background: var(--accent); color: var(--on-accent); border-color: var(--accent); }}
"""


def appicon(a, size):
    g = f"linear-gradient(145deg, {a['c1']}, {a['c2']})"
    inner = int(size * 0.56)
    return (f'<div class="aicon" style="width:{size}px;height:{size}px;background:{g};border-radius:{max(6, size // 4)}px">'
            f'{icon(a["icon"], inner, "#FFFFFF", 2.2)}</div>')


def state_control(a):
    st = a["state"]
    if st == "busy":
        return (f'<div class="prog"><div class="bar"><div style="width:{a["pct"]}%"></div></div>'
                f'<span>{a["pct"]} %</span></div>')
    cls = "btn accent" if st in ("install", "update") else "btn"
    return f'<div class="{cls}">{STATE_LABEL[st]}</div>'


def store(t):
    rail = [("house", "Start", False), ("layout-grid", "Apps", True), ("palette", "Designs", False), ("download", "Bibliothek", False)]
    rail_html = "".join(
        f'<div class="rail-item{" sel" if s else ""}">{icon(i, 20)}<span>{l}</span>{"<i></i>" if s else ""}</div>' for i, l, s in rail)
    chips = ["Alle", "Produktivität", "Internet", "System", "Kreativ", "Entwicklung"]
    chips_html = "".join(f'<div class="chip{" on" if k == 0 else ""}">{c}</div>' for k, c in enumerate(chips))
    cards = "".join(
        f'<div class="card">{appicon(a, 48)}<div class="meta"><div class="name">{a["name"]}</div>'
        f'<div class="cat">{a["cat"]}</div><div class="desc">{a["desc"]}</div></div>'
        f'<div class="act">{state_control(a)}</div></div>' for a in t["apps"])
    css = base_css(t) + """
.win { display: flex; width: 860px; height: 560px; background: var(--bg); }
.rail { width: 68px; padding-top: 8px; display: flex; flex-direction: column; gap: 4px; align-items: center; }
.rail-item { position: relative; width: 60px; height: 52px; border-radius: var(--r-ctl); display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 2px; color: var(--muted); font-size: 11px; }
.rail-item.sel { background: var(--card); color: var(--text); font-weight: 600; box-shadow: var(--shadow); }
.rail-item.sel i { position: absolute; left: 0; top: 16px; width: 3px; height: 20px; border-radius: 2px; background: var(--accent); }
.rail-item.sel svg { color: var(--accent); }
.main { flex: 1; display: flex; flex-direction: column; background: var(--layer); border-top-left-radius: var(--r-card); border-left: 1px solid var(--stroke); border-top: 1px solid var(--stroke); margin-top: 8px; overflow: hidden; position: relative; }
.top { padding: 12px 24px 0; display: flex; justify-content: center; }
.top .search { width: 420px; }
.head { padding: 16px 24px 0; }
.head h1 { font-size: 20px; font-weight: 600; letter-spacing: -0.2px; }
.chips { display: flex; gap: 8px; padding: 12px 24px 4px; }
.chip { height: 28px; padding: 0 12px; border-radius: 14px; border: 1px solid var(--stroke); background: var(--card); display: flex; align-items: center; font-size: 12px; color: var(--text); }
.chip.on { background: var(--accent); border-color: var(--accent); color: var(--on-accent); font-weight: 600; }
.grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; padding: 12px 24px 24px; }
.card { background: var(--card); border-radius: var(--r-card); box-shadow: var(--shadow); padding: 14px; display: grid; grid-template-columns: 48px 1fr; grid-template-rows: auto 28px; column-gap: 12px; row-gap: 10px; height: 128px; }
.aicon { display: flex; align-items: center; justify-content: center; box-shadow: inset 0 0 0 1px rgba(255,255,255,0.12), 0 1px 2px rgba(0,0,0,0.12); }
.meta { min-width: 0; }
.name { font-size: 14px; font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.cat { font-size: 12px; color: var(--muted); }
.desc { font-size: 12px; color: var(--muted); margin-top: 2px; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; line-height: 1.35; }
.act { grid-column: 1 / 3; display: flex; justify-content: flex-end; align-items: center; }
.prog { display: flex; align-items: center; gap: 8px; width: 150px; font-size: 12px; color: var(--muted); }
.prog .bar { flex: 1; height: 4px; border-radius: 2px; background: var(--sel); overflow: hidden; }
.prog .bar div { height: 100%; background: var(--accent); border-radius: 2px; }
.scroller { flex: 1; overflow: hidden; position: relative; }
.thumb { position: absolute; right: 3px; top: 132px; width: 3px; height: 120px; border-radius: 2px; background: #8A8A8A; opacity: .55; }
"""
    return f"""<!doctype html><html lang="de"><head><meta charset="utf-8"><style>{css}</style></head><body>
<div class="win"><div class="rail">{rail_html}</div><div class="main">
<div class="top"><div class="search">{icon('search', 16)}<span>Apps, Designs und Schriften suchen</span></div></div>
<div class="scroller"><div class="head"><h1>Apps</h1></div><div class="chips">{chips_html}</div>
<div class="grid">{cards}</div><div class="thumb"></div></div></div></div></body></html>"""


def explorer(t):
    nav = [("house", "Start", False), ("monitor", "Desktop", False), ("download", "Downloads", False), ("file-text", "Dokumente", True),
           ("image", "Bilder", False), ("music", "Musik", False), (None, None, None), ("hard-drive", "Dieser PC", False), ("hard-drive", "System (C:)", False)]
    nav_html = ""
    for i, l, s in nav:
        if i is None:
            nav_html += '<div class="sep"></div>'
            continue
        color = "#E8A92A" if i in ("download", "file-text", "image", "music", "monitor") else None
        nav_html += f'<div class="nav{" sel" if s else ""}">{icon(i, 16, color)}<span>{l}</span></div>'
    rows = [("d", "Projekte", "29.10.2026 18:04", "Dateiordner", ""), ("d", "Rechnungen", "27.10.2026 09:12", "Dateiordner", ""),
            ("d", "Schule", "24.10.2026 16:40", "Dateiordner", ""), ("f", "Bewerbung.pdf", "30.10.2026 11:02", "PDF-Dokument", "248 KB"),
            ("f", "Einkaufsliste.txt", "30.10.2026 08:15", "Textdokument", "1 KB"), ("f", "Notizen.txt", "28.10.2026 21:37", "Textdokument", "4 KB"),
            ("i", "Urlaub.png", "12.10.2026 14:20", "PNG-Bild", "1,8 MB"), ("f", "Vertrag.pdf", "02.10.2026 10:00", "PDF-Dokument", "512 KB"),
            ("f", "Zeitplan.txt", "01.10.2026 07:45", "Textdokument", "2 KB")]
    row_html = ""
    for k, (kind, n, d, ty, sz) in enumerate(rows):
        if kind == "d":
            ic = '<span class="fold"></span>'
        elif kind == "i":
            ic = icon("image", 16, "#0F6CBD")
        else:
            ic = icon("file-text" if n.endswith(".pdf") else "file", 16, "#C42B1C" if n.endswith(".pdf") else "#5D5D5D")
        row_html += (f'<div class="row{" sel" if k == 3 else ""}{" hov" if k == 5 else ""}"><div class="c0">{ic}<span>{n}</span></div>'
                     f'<div class="c1">{d}</div><div class="c2">{ty}</div><div class="c3">{sz}</div></div>')
    crumbs = ["Dieser PC", "Dokumente"]
    crumb_html = "".join(f'<span class="crumb{" hov" if k == 0 else ""}">{c}</span><span class="chev">{icon("chevron-right", 12)}</span>' for k, c in enumerate(crumbs))
    cmds = [("Neu", "plus"), (None, "scissors"), (None, "copy"), (None, "clipboard"), (None, "pencil"), (None, "trash-2"), ("Sortieren", "arrow-up-down"), ("Anzeigen", "layout-grid")]
    cmd_html = ""
    for label, ic in cmds:
        try:
            sv = icon(ic, 16)
        except SystemExit:
            sv = ""
        cmd_html += f'<div class="cmd">{sv}{f"<span>{label}</span>" if label else ""}</div>'
        if label == "Neu" or ic == "trash-2":
            cmd_html += '<div class="vsep"></div>'
    css = base_css(t) + """
.win { width: 900px; height: 560px; background: var(--layer); display: flex; flex-direction: column; }
.bar { height: 48px; display: flex; align-items: center; gap: 4px; padding: 0 8px; background: var(--bg); }
.addr { flex: 1; height: 32px; border-radius: var(--r-ctl); background: var(--card); border: 1px solid var(--stroke); display: flex; align-items: center; gap: 2px; padding: 0 8px; margin: 0 6px; }
.addr .lead { color: var(--muted); display: flex; margin-right: 4px; }
.crumb { padding: 2px 6px; border-radius: var(--r-ctl); }
.crumb.hov { background: var(--hover); }
.chev { color: var(--subtle); display: flex; }
.bar .search { width: 220px; }
.cmdbar { height: 44px; display: flex; align-items: center; gap: 2px; padding: 0 12px; border-bottom: 1px solid var(--stroke); background: var(--layer); }
.cmd { height: 32px; min-width: 32px; padding: 0 8px; border-radius: var(--r-ctl); display: flex; align-items: center; gap: 6px; }
.vsep { width: 1px; height: 20px; background: var(--stroke); margin: 0 6px; }
.body { flex: 1; display: flex; min-height: 0; }
.pane { width: 196px; padding: 6px 4px; border-right: 1px solid var(--stroke); }
.nav { height: 30px; border-radius: var(--r-ctl); display: flex; align-items: center; gap: 10px; padding: 0 12px; position: relative; }
.nav.sel { background: var(--sel); }
.nav.sel::before { content: ''; position: absolute; left: 0; top: 8px; width: 3px; height: 14px; border-radius: 2px; background: var(--accent); }
.sep { height: 1px; background: var(--stroke); margin: 6px 8px; }
.list { flex: 1; padding: 0 8px; }
.hdr, .row { display: grid; grid-template-columns: 1fr 150px 120px 80px; align-items: center; }
.hdr { height: 32px; color: var(--muted); font-size: 12px; padding: 0 12px; }
.hdr div + div, .row div + div { padding-left: 12px; }
.hdr div + div { border-left: 1px solid var(--stroke); }
.row { height: 32px; padding: 0 12px; border-radius: var(--r-ctl); color: var(--muted); font-size: 12px; }
.row .c0 { display: flex; align-items: center; gap: 10px; color: var(--text); font-size: 13px; }
.row .c3 { text-align: right; padding-right: 4px; }
.row.sel { background: #CCE4F7; }
.row.hov { background: var(--hover); }
.fold { width: 16px; height: 13px; border-radius: 2px; background: linear-gradient(#FFD45C, #FFC83D); position: relative; box-shadow: inset 0 -1px 0 #E8A92A; }
.fold::before { content: ''; position: absolute; left: 0; top: -2px; width: 7px; height: 3px; border-radius: 2px 2px 0 0; background: #E8A92A; }
.status { height: 26px; display: flex; align-items: center; padding: 0 14px; font-size: 12px; color: var(--muted); border-top: 1px solid var(--stroke); }
"""
    return f"""<!doctype html><html lang="de"><head><meta charset="utf-8"><style>{css}</style></head><body><div class="win">
<div class="bar"><div class="ibtn">{icon('arrow-left', 16)}</div><div class="ibtn off">{icon('arrow-right', 16)}</div><div class="ibtn">{icon('arrow-up', 16)}</div><div class="ibtn">{icon('rotate-cw', 16)}</div>
<div class="addr"><span class="lead">{icon('monitor', 16)}</span><span class="chev">{icon('chevron-right', 12)}</span>{crumb_html}</div>
<div class="search">{icon('search', 16)}<span>Dokumente durchsuchen</span></div></div>
<div class="cmdbar">{cmd_html}</div>
<div class="body"><div class="pane">{nav_html}</div><div class="list"><div class="hdr"><div>Name</div><div>Änderungsdatum</div><div>Typ</div><div>Größe</div></div>{row_html}</div></div>
<div class="status">9 Elemente · 1 ausgewählt</div></div></body></html>"""


PAGES = {"store": (store, 860, 560), "explorer": (explorer, 900, 560)}


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "out")
    os.makedirs(out, exist_ok=True)
    tokens = json.load(open(os.path.join(HERE, "tokens.json"), encoding="utf-8"))
    for name, (fn, w, h) in PAGES.items():
        with open(os.path.join(out, name + ".html"), "w", encoding="utf-8") as f:
            f.write(fn(tokens))
        print(f"{name} {w} {h}")


if __name__ == "__main__":
    main()
