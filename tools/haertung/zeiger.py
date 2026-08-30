#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/haertung/zeiger.py -- WELCHER SYSTEMAUFRUF PRUEFT SEINE ZEIGER?

Die Frage dieser Runde war nicht, ob `proc.user_ok` existiert -- es
existiert seit Runde 62 --, sondern ob es an JEDER noetigen Stelle auch
wirklich aufgerufen wird. Bei einer Datei von 340 KiB und Argumenten,
die fuenf Ebenen tief weitergereicht werden, ist das durch Hinsehen
nicht zu beantworten.

WIE DAS HIER ARBEITET:

  1. Alle Systemaufrufnummern einlesen und aus den Verteilern in
     `kernel/sys.fi` die Zuordnung Nummer -> Behandler lesen.
  2. Von JEDEM ARGUMENT eines Behandlers aus verfolgen, was damit
     geschieht -- ueber Modulgrenzen und Aufrufebenen hinweg, indem die
     ARGUMENTSTELLE mitgefuehrt wird (Argument 3 von `do_read` wird zu
     Argument 3 von `read_of` und so weiter).
  3. Drei Ausgaenge je Argument:
       GEPRUEFT  es erreicht `proc.user_ok` oder eine der gepruefen
                 Zugriffsfunktionen (`sys.copy_in`, `copy_out`,
                 `fetch_name`, `peek`, `poke`, `user_word`, ...).
       ROH       es wird als Adresse benutzt (`kstate.get8` und
                 Verwandte, `__mmio_read64`), ohne dass auf dem Weg
                 geprueft wurde. Das ist die Liste, die zaehlt.
       SKALAR    es wird nie als Adresse benutzt -- eine Zahl, ein
                 Dateizeiger, ein Merkmal. Da ist nichts zu pruefen,
                 und es als Luecke zu zaehlen waere Zahlenkosmetik.

  DIE GRENZE, ausdruecklich: das ist eine Erreichbarkeitsaussage ueber
  den Aufrufgraphen, kein Beweis. Ein `if` davor, das den Zeiger schon
  aussortiert, sieht es nicht. Deshalb stehen die Angriffsfaelle in
  tools/haertung/run.sh daneben -- die probieren es wirklich aus.
  Dieses Werkzeug sagt, WO man hinsehen muss.
"""
import os, re, sys, json

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
KERN = os.path.join(WURZEL, "kernel")

# Die gepruefte Zugriffsschicht, MODULSCHARF. Ein blosser Name reicht
# nicht: `get32` heisst in `kstate` "lies vier Oktette irgendwo" und in
# `sys` "lies vier Oktette aus dem Nutzerraum, nachdem du geprueft
# hast". Wer beide zusammenwirft, bekommt 122 von 122 geprueft heraus --
# eine Zahl, die zu gut ist, um wahr zu sein.
SENKEN = {
    ("proc", "user_ok"),
    ("sys", "copy_in"), ("sys", "copy_out"),
    ("sys", "fetch_name"), ("sys", "user_word"),
    ("sys", "peek"), ("sys", "poke"),
    ("sys", "get32"), ("sys", "put32"),
    ("sys", "get16"), ("sys", "put16"),
}

# Ein Zugriff auf Speicher an einer Adresse, die aus dem Argument kommt.
# NICHT dazu gehoeren `kstate.get`/`kstate.set`: die nehmen einen
# VERSATZ in die Zustandsregion des Kerns, keine Adresse. Sie mit
# aufzunehmen war die zweite zu gute Zahl dieses Werkzeugs -- danach galt
# jeder Tabellenindex als roher Zeiger.
ROH = {
    ("kstate", "get8"), ("kstate", "get16"), ("kstate", "get32"),
    ("kstate", "set8"),
}
ROH_NACKT = {"__mmio_read64", "__mmio_write64"}

def dateien():
    for w, _, ns in os.walk(KERN):
        for n in ns:
            if n.endswith(".fi"):
                yield os.path.join(w, n)

def lies(p):
    with open(p, "rb") as f:
        return f.read().decode("utf-8", "replace")

def ohne_kommentar(t):
    return re.sub(r"//[^\n]*", "", t)

def klammer_ende(text, i):
    """i zeigt auf '{' oder '(' -- gib den Versatz der passenden zu."""
    auf = text[i]; zu = "}" if auf == "{" else ")"
    t, j = 0, i
    while j < len(text):
        if text[j] == auf: t += 1
        elif text[j] == zu:
            t -= 1
            if t == 0: return j
        j += 1
    return len(text) - 1

def zerlege(text):
    """{ (modul, fn): (parameternamen, rumpf) }"""
    aus = {}
    for m in re.finditer(r"\bfn\s+([A-Za-z_]\w*)\s*\(", text):
        name = m.group(1)
        po = m.end() - 1
        pe = klammer_ende(text, po)
        params = []
        for st in text[po + 1:pe].split(","):
            st = st.strip()
            if not st: continue
            params.append(st.split(":")[0].strip())
        i = text.find("{", pe)
        if i < 0: continue
        j = klammer_ende(text, i)
        aus[name] = (params, text[i:j + 1])
    return aus

def argumente(rohtext):
    """Argumente eines Aufrufs, oberste Klammerebene."""
    teile, t, akt = [], 0, ""
    for c in rohtext:
        if c in "([": t += 1
        elif c in ")]": t -= 1
        if c == "," and t == 0:
            teile.append(akt.strip()); akt = ""
        else:
            akt += c
    if akt.strip(): teile.append(akt.strip())
    return teile

def main():
    mod = {}
    for p in dateien():
        name = os.path.basename(p)[:-3]
        mod.setdefault(name, {})
        mod[name].update(zerlege(ohne_kommentar(lies(p))))

    sys_t = ohne_kommentar(lies(os.path.join(KERN, "sys.fi")))

    nummern = {}
    for m in re.finditer(r"\bconst\s+(SYS_\w+|CAP_\w+|H_SYS_\w+)\s*:\s*u64\s*=\s*(\d+)", sys_t):
        nummern[m.group(1)] = int(m.group(2))

    zuord = {}
    for m in re.finditer(r"number\s*==\s*(SYS_\w+|CAP_\w+|H_SYS_\w+)\s*\{\s*\n?\s*return\s+([A-Za-z_][\w.]*)\s*\(", sys_t):
        roh = m.group(2)
        mm, ff = (roh.split(".")[-2], roh.split(".")[-1]) if "." in roh else ("sys", roh)
        zuord.setdefault(m.group(1), (mm, ff))

    def verfolge(m0, f0, idx, tiefe=0, gesehen=None):
        """Was geschieht mit Argument `idx` von m0.f0?  -> 'geprueft'|'roh'|'skalar'"""
        if gesehen is None: gesehen = set()
        if tiefe > 6 or (m0, f0, idx) in gesehen: return "skalar"
        gesehen.add((m0, f0, idx))
        eintrag = mod.get(m0, {}).get(f0)
        if not eintrag: return "skalar"
        params, rumpf = eintrag
        if idx >= len(params): return "skalar"
        pname = params[idx]
        wort = re.compile(r"\b%s\b" % re.escape(pname))
        ergebnis = "skalar"
        for c in re.finditer(r"(?:([A-Za-z_]\w*)\.)?([A-Za-z_]\w*)\s*\(", rumpf):
            zm, zf = (c.group(1) or m0), c.group(2)
            ae = klammer_ende(rumpf, c.end() - 1)
            args = argumente(rumpf[c.end():ae])
            stellen = [k for k, a in enumerate(args) if wort.search(a)]
            if not stellen: continue
            if (zm, zf) in SENKEN: return "geprueft"
            if (zm, zf) in ROH or zf in ROH_NACKT:
                ergebnis = "roh"; continue
            if zf in mod.get(zm, {}):
                for k in stellen:
                    r = verfolge(zm, zf, k, tiefe + 1, gesehen)
                    if r == "geprueft": return "geprueft"
                    if r == "roh": ergebnis = "roh"
        return ergebnis

    # Namen, die nach einem Zeiger aussehen. Kein Beweis, ein Filter fuer
    # die Durchsicht von Hand: ein rohes Argument namens `buf` ist ein
    # Fund; eines namens `fd` ist ein Dateizeiger und wird gleich als
    # Index in eine Kerntabelle gelegt. Wer beides gleich zaehlt, bekommt
    # 64 Verdaechtige und sieht keinen davon an.
    ZEIGERNAMEN = ("buf", "ptr", "addr", "out", "dst", "src", "path",
                   "name", "set", "fds", "base", "args", "block",
                   "zeiten", "old", "new", "oa", "na")

    zeilen, roh_liste, roh_verdacht = [], [], []
    for name in sorted(nummern, key=lambda n: nummern[n]):
        h = zuord.get(name)
        if not h: continue
        params = mod.get(h[0], {}).get(h[1], ([], ""))[0]
        gepr, rohs = [], []
        for k, pn in enumerate(params):
            if pn in ("state", "me", "number", "frame"): continue
            r = verfolge(h[0], h[1], k)
            if r == "geprueft": gepr.append(pn)
            elif r == "roh": rohs.append(pn)
        zeilen.append((nummern[name], name, "%s.%s" % h, gepr, rohs))
        if rohs:
            roh_liste.append((nummern[name], name, "%s.%s" % h, rohs))
            v = [x for x in rohs if any(z in x.lower() for z in ZEIGERNAMEN)]
            if v:
                roh_verdacht.append((nummern[name], name, "%s.%s" % h, v))

    if "--json" in sys.argv:
        print(json.dumps({"zeilen": zeilen, "roh": roh_liste}, ensure_ascii=False)); return 0

    print("%-6s %-25s %-24s %-22s %s" % ("Nr","Systemaufruf","Behandler","geprueft","ROH"))
    print("-" * 100)
    for nr, name, h, gepr, rohs in zeilen:
        print("%-6d %-25s %-24s %-22s %s" % (nr, name, h,
              ",".join(gepr) or "-", ",".join(rohs) or "-"))
    print("-" * 100)
    mitz = [z for z in zeilen if z[3] or z[4]]
    print("Systemaufrufe mit Behandler:            %d" % len(zeilen))
    print("davon mit mindestens einem Zeiger:      %d" % len(mitz))
    print("   davon alle Zeiger geprueft:          %d" % len([z for z in mitz if not z[4]]))
    print("   davon mit ROHEM Zeiger:              %d" % len(roh_liste))
    print("Systemaufrufe ohne jeden Zeiger:        %d" % (len(zeilen) - len(mitz)))
    for nr, name, h, rohs in roh_liste:
        print("   ROH: %-25s %-24s %s" % (name, h, ",".join(rohs)))
    print()
    print("ROHE ARGUMENTE MIT ZEIGERVERDAECHTIGEM NAMEN: %d" % len(roh_verdacht))
    print("(das ist die Liste, die von Hand durchzusehen ist -- alles")
    print(" andere sind Dateizeiger, Merkmale, Kennungen und Indizes)")
    for nr, name, h, v in roh_verdacht:
        print("   PRUEFEN: %-25s %-24s %s" % (name, h, ",".join(v)))
    return 0

if __name__ == "__main__":
    sys.exit(main())
