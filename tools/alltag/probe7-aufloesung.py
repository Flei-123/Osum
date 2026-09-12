#!/usr/bin/env python3
# tools/alltag/probe7-aufloesung.py -- RUNDE ALLTAG: die Probe-Aufloesung der
# Konflikte alltag -> merge7 (8c31a08), wie in STATUS-ALLTAG.md beschrieben.
# Aufruf: python3 tools/alltag/probe7-aufloesung.py <wegwerf-worktree>
# NACH `git merge --no-commit --no-ff alltag` dort. Danach fehlen noch zwei
# schliessende Klammern in kernel/user/wlib.fi (on_down K_LEINWAND, on_up
# LE_UP) -- siehe Bericht. Wegwerf-Werkzeug, kein Teil der Abnahme.
"""Probe-Aufloesung der sechs Konfliktdateien alltag -> merge7 (WEGWERF-Baum).

Regeln je (Datei, Konfliktnummer):
  head    -- die merge7-Seite gewinnt
  both    -- beide Seiten hintereinander (HEAD zuerst)
  union   -- Exportliste: HEAD-Seite + die Bezeichner, die nur alltag hat
  keysdel -- wlib-Exportliste, Sonderfall: KEY_SDEL vor die HEAD-Seite
  buildsh -- GUI=/CLI=-Zeilen: HEAD-Liste + die alltag-Namen angehaengt
"""
import re, sys, os

ROOT = sys.argv[1] if len(sys.argv) > 1 else "/root/osum-probe7"
RULES = {
    "kernel/proc.fi":       ["head"],
    "kernel/sys.fi":        ["union", "both", "bothclose"],
    "lib/libc/kcall.fi":    ["union", "both"],
    "kernel/user/wlib.fi":  ["union", "both", "keysdel", "both", "both", "both"],
    "tools/loader/apps.tab": ["both"],
    "tools/loader/build.sh": ["buildsh"],
}
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")

def idents(lines):
    out = []
    for l in lines:
        s = l.split("//")[0]
        for m in IDENT.finditer(s):
            out.append(m.group(0))
    return out

def resolve(path, rules):
    src = open(os.path.join(ROOT, path), encoding="utf-8").read().split("\n")
    out, i, k = [], 0, 0
    while i < len(src):
        if src[i].startswith("<<<<<<< "):
            j = i + 1; head = []
            while not src[j].startswith("======="):
                head.append(src[j]); j += 1
            j += 1; other = []
            while not src[j].startswith(">>>>>>> "):
                other.append(src[j]); j += 1
            rule = rules[k]; k += 1
            if rule == "head":
                out += head
            elif rule == "both":
                out += head + other
            elif rule == "bothclose":
                out += head + ["    }"] + other
            elif rule == "union":
                have = set(idents(head))
                neu = [x for x in idents(other) if x not in have]
                out += head
                if neu:
                    out.append("    " + ", ".join(neu) + ",")
            elif rule == "keysdel":
                out += ["    KEY_SDEL,"] + head
            elif rule == "buildsh":
                for l in head:
                    if l.startswith("GUI="):
                        l = l[:-2] + ' rechner papierkorb viewer snip lock"}'
                    elif l.startswith("CLI="):
                        l = l[:-2] + ' zip"}'
                    out.append(l)
            else:
                raise SystemExit("unbekannte Regel " + rule)
            i = j + 1
            continue
        out.append(src[i]); i += 1
    if k != len(rules):
        raise SystemExit(f"{path}: {k} Konflikte, {len(rules)} Regeln")
    text = "\n".join(out)
    # Umnummerierung
    if path in ("kernel/sys.fi", "lib/libc/kcall.fi"):
        text = text.replace("const SYS_OSUM_SPERRE: u64 = 1850", "const SYS_OSUM_SPERRE: u64 = 1870")
        text = text.replace("//   1850  osum_sperre", "//   1870  osum_sperre")
        text = text.replace("SYS_OSUM_SPERRE: kernel 1850", "SYS_OSUM_SPERRE: kernel 1870")
        text = text.replace("RUNDE ALLTAG: 1850, DIE SPERRE", "RUNDE ALLTAG: 1870, DIE SPERRE (1850 gehoert seit Runde TON dem AUDGET)")
    if path == "kernel/user/wlib.fi":
        text = text.replace("const K_BILD: u64 = 15", "const K_BILD: u64 = 16")
        text = text.replace("const K_SLIDER: u64 = 16", "const K_SLIDER: u64 = 17")
    open(os.path.join(ROOT, path), "w", encoding="utf-8").write(text)
    print(f"{path}: {k} Konflikte aufgeloest ({', '.join(rules)})")

for p, r in RULES.items():
    resolve(p, r)
# lock.fi hat keine Konfliktmarken, aber die Nummer
lp = os.path.join(ROOT, "kernel/user/lock.fi")
t = open(lp, encoding="utf-8").read()
n = t.count("const SYS_SPERRE: u64 = 1850")
open(lp, "w", encoding="utf-8").write(t.replace("const SYS_SPERRE: u64 = 1850", "const SYS_SPERRE: u64 = 1870"))
print(f"kernel/user/lock.fi: {n} Nummer(n) 1850 -> 1870")
