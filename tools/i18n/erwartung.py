#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/i18n/erwartung.py -- ABNAHMEN, DIE NACH DEM ALTEN TEXT SUCHEN.

Runde UMLAUT2, zweiter Nachtrag. Der Fehler, gegen den dieses Stueck
antritt, ist NICHT im System -- er ist in der ABNAHME:

    kernel/user/tiling.fi:   "tiling: Einträge gelesen"
    tools/tiling/run.sh:     grep -aoE '^[0-9]+ tiling: Eintraege'

Beides stand gleichzeitig im Baum. Das Programm sagte das Richtige, die
Abnahme suchte den alten Satz, fand nichts, und die Zusage

    "Kern sagt 21, /bin/tiling sagt ''"

wurde rot -- ohne dass am System irgendetwas fehlte. Eine Umstellung
auf echte Umlaute laesst genau diese Sorte Leiche zurueck, und sie ist
besonders unangenehm: der Laeufer wird ROT, also sieht es aus wie ein
echter Fehler, und wer ihn sucht, sucht ihn am falschen Ende.

DIE REGEL. Steht ein Satz mit Umlaut im Baum, darf KEIN Abnahmeskript
nach seiner ASCII-Umschrift suchen.

WIE OHNE FEHLALARM. Ein Laeufer redet in zwei Sprachen zugleich: er
sucht nach Zeichenketten UND beschreibt auf Deutsch, was er tut --

    num "Eintraege, die aus tiling.conf gelesen wurden" "$bd" eq "$soll"
    bad "vfsall aendert nichts an der Zahl der Verrichtungen"

Das sind BESCHREIBUNGEN. Sie duerfen ASCII bleiben (docs/I18N.md nimmt
die Abnahmesprache aus), und ein Pruefer, der sie anmeckert, wird beim
naechsten Mal abgeschaltet. Dasselbe gilt fuer EINGABEN: `opk zurueck 0`
in einer Befehlszeile ist eine getippte Marke und genau richtig so.

Es wird deshalb nur nach Saetzen gesucht, die ein PROGRAMMPRAEFIX
tragen -- `tiling: `, `fas: `, `opk: `. Das ist die Form, in der ein
Programm auf die Leitung schreibt, es ist die Form, nach der eine
Abnahme greppt, und es ist die einzige Form, die in einer Beschreibung
oder einer Befehlszeile nichts zu suchen hat. Jede gepruefte Phrase
MUSS das Praefix enthalten:

    Satz    "tiling: Einträge gelesen"
    Phrasen "tiling: Eintraege" | "tiling: Eintraege gelesen"

    Treffer:      grep '^[0-9]+ tiling: Eintraege'   -> ROT
    kein Treffer: "Eintraege, die aus tiling.conf"   -> still
    kein Treffer: "opk zurueck 0" in einer Eingabe   -> still

  erwartung.py            die Funde
  erwartung.py --zahlen   nur die Bilanz
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import translit  # noqa: E402

# Rueckwaerts: aus "Größe" wieder "Groesse". Laengste Umlautform zuerst,
# sonst frisst "größ" das laengere "größt".
_RUECK = {}
for _a, _u in translit.STAEMME:
    _RUECK.setdefault(_u, _a)
_RUECK_RE = re.compile("|".join(
    re.escape(u) for u in sorted(_RUECK, key=len, reverse=True)))

UMLAUT = re.compile(r'[äöüÄÖÜß]')
STR = re.compile(r'"((?:\\.|[^"\\])*)"')

# Wo Abnahmen stehen. Die Laeufer sind Shell, ein paar Pruefer Python.
LAEUFER_ENDUNG = (".sh", ".py")
LAEUFER_ORT = ("tools", "tests")
# Sich selbst und die Werkzeuge dieser Runde nicht lesen: sie fuehren
# beide Schreibungen absichtlich nebeneinander.
AUS = ("tools/i18n/", "tools/umlaut/", "tools/look/umlaut.py")


def ruecklauf(s):
    """Die ASCII-Umschrift eines Satzes mit Umlauten."""
    return _RUECK_RE.sub(lambda m: _RUECK[m.group(0)], s)


def entschaerf(roh):
    """Firn-Literal -> der Text, den es traegt (ohne \\0-Auffuellung)."""
    t = roh.replace("\\n", " ").replace("\\t", " ")
    t = t.replace("\\0", "").replace('\\"', '"').replace("\\\\", "\\")
    return t


def saetze(wurzel):
    """Jeder Satz MIT Umlaut, der im Baum auf dem Schirm landen kann."""
    aus = []
    for ort in ("kernel", "lib"):
        p0 = os.path.join(wurzel, ort)
        for d, _, fs in os.walk(p0):
            for f in fs:
                if not f.endswith(".fi"):
                    continue
                p = os.path.join(d, f)
                with open(p, encoding="utf-8", errors="replace") as fh:
                    for nr, z in enumerate(fh, 1):
                        for m in STR.finditer(z):
                            t = entschaerf(m.group(1)).strip()
                            if UMLAUT.search(t):
                                aus.append((os.path.relpath(p, wurzel),
                                            nr, t))
    for unter in ("locale/de", ):
        p0 = os.path.join(wurzel, unter)
        if not os.path.isdir(p0):
            continue
        for f in sorted(os.listdir(p0)):
            p = os.path.join(p0, f)
            if not os.path.isfile(p):
                continue
            with open(p, encoding="utf-8", errors="replace") as fh:
                for nr, z in enumerate(fh, 1):
                    if z.lstrip().startswith("#") or "=" not in z:
                        continue
                    t = z.split("=", 1)[1].strip()
                    if UMLAUT.search(t):
                        aus.append((os.path.relpath(p, wurzel), nr, t))
    p0 = os.path.join(wurzel, "assets", "apps")
    if os.path.isdir(p0):
        for d in sorted(os.listdir(p0)):
            p = os.path.join(p0, d, "INFO")
            if not os.path.isfile(p):
                continue
            with open(p, encoding="utf-8", errors="replace") as fh:
                for nr, z in enumerate(fh, 1):
                    if "=" not in z or z.lstrip().startswith("#"):
                        continue
                    k, t = z.split("=", 1)
                    if k.strip() in ("keys", ):
                        continue
                    t = t.strip()
                    if UMLAUT.search(t):
                        aus.append((os.path.relpath(p, wurzel), nr, t))
    return aus


PRAEFIX = re.compile(r'^([a-z][a-z0-9_]{1,15}):\s')


def phrasen(satz):
    """Die Phrasen der Umschrift, die das Programmpraefix TRAGEN.

    Ohne Praefix keine Phrase: nur `tiling: ...` ist eine Zeile, die ein
    Programm schreibt und eine Abnahme sucht. Alles andere ist
    Beschreibung oder Eingabe und geht diesen Pruefer nichts an.
    """
    m = PRAEFIX.match(satz)
    if not m:
        return set()
    woerter = satz.split()
    if len(woerter) < 2:
        return set()
    aus = set()
    # Immer beim Praefix anfangen, sonst faellt die Verankerung weg.
    for n in range(2, min(len(woerter), 5) + 1):
        teil = woerter[:n]
        if not any(UMLAUT.search(w) for w in teil):
            continue
        p = ruecklauf(" ".join(teil))
        if p != " ".join(teil) and len(p) >= 10:
            aus.add(p)
            # RUNDE ROADMAP-3: auch ohne Satzzeichen am Ende. "ota: das
            # ist kein Schlüssel: quelle ..." ergab nur die Phrase mit
            # Doppelpunkt, und `tools/ota/run.sh` suchte sie ohne --
            # 0 Funde, obwohl der Laeufer veraltet war.
            q = p.rstrip(":;,.!?")
            if q != p and len(q) >= 10:
                aus.add(q)
    return aus


def laeufer(wurzel):
    for ort in LAEUFER_ORT:
        p0 = os.path.join(wurzel, ort)
        if not os.path.isdir(p0):
            continue
        for d, _, fs in os.walk(p0):
            for f in sorted(fs):
                if not f.endswith(LAEUFER_ENDUNG):
                    continue
                p = os.path.join(d, f)
                rel = os.path.relpath(p, wurzel)
                if any(rel.startswith(a) for a in AUS):
                    continue
                yield p, rel


def pruefe(wurzel):
    """-> (Funde, Zahl der Saetze, Zahl der Phrasen, Zahl der Laeufer)."""
    alle = saetze(wurzel)
    plan = {}
    for datei, nr, satz in alle:
        for p in phrasen(satz):
            plan.setdefault(p, (datei, nr, satz))
    funde = []
    n_l = 0
    for p, rel in laeufer(wurzel):
        n_l += 1
        with open(p, encoding="utf-8", errors="replace") as fh:
            for nr, z in enumerate(fh, 1):
                if z.lstrip().startswith("#"):
                    continue
                for phrase, (qd, qn, qs) in plan.items():
                    if phrase in z:
                        funde.append((rel, nr, phrase, qd, qn, qs))
    return funde, len(alle), len(plan), n_l


def main(argv):
    wurzel = os.path.abspath(
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
    nur_zahlen = "--zahlen" in argv
    funde, n_s, n_p, n_l = pruefe(wurzel)
    if not nur_zahlen:
        for rel, nr, phrase, qd, qn, qs in funde:
            print("VERALTET  %s:%d sucht %r" % (rel, nr, phrase))
            print("          der Text heisst seit %s:%d %r" % (qd, qn, qs))
    print("erwartung: %d Saetze mit Umlaut, %d Phrasen, %d Laeufer, "
          "%d veraltete Erwartungen" % (n_s, n_p, n_l, len(funde)))
    return 1 if funde else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
