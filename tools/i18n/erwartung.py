#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import translit  # noqa: E402

_RUECK = {}
for _a, _u in translit.STAEMME:
    _RUECK.setdefault(_u, _a)
_RUECK_RE = re.compile("|".join(
    re.escape(u) for u in sorted(_RUECK, key=len, reverse=True)))

UMLAUT = re.compile(r'[äöüÄÖÜß]')
STR = re.compile(r'"((?:\\.|[^"\\])*)"')

LAEUFER_ENDUNG = (".sh", ".py")
LAEUFER_ORT = ("tools", "tests")
AUS = ("tools/i18n/", "tools/umlaut/", "tools/look/umlaut.py")


def ruecklauf(s):
    return _RUECK_RE.sub(lambda m: _RUECK[m.group(0)], s)


def entschaerf(roh):
    t = roh.replace("\\n", " ").replace("\\t", " ")
    t = t.replace("\\0", "").replace('\\"', '"').replace("\\\\", "\\")
    return t


def saetze(wurzel):
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
    m = PRAEFIX.match(satz)
    if not m:
        return set()
    woerter = satz.split()
    if len(woerter) < 2:
        return set()
    aus = set()
    for n in range(2, min(len(woerter), 5) + 1):
        teil = woerter[:n]
        if not any(UMLAUT.search(w) for w in teil):
            continue
        p = ruecklauf(" ".join(teil))
        if p != " ".join(teil) and len(p) >= 10:
            aus.add(p)
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


def check(wurzel):
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
    only_nums = "--zahlen" in argv
    funde, n_s, n_p, n_l = check(wurzel)
    if not only_nums:
        for rel, nr, phrase, qd, qn, qs in funde:
            print("VERALTET  %s:%d sucht %r" % (rel, nr, phrase))
            print("          the text has been called %r since %s:%d" % (qd, qn, qs))
    print("erwartung: %d Saetze mit Umlaut, %d Phrasen, %d Laeufer, "
          "%d veraltete Erwartungen" % (n_s, n_p, n_l, len(funde)))
    return 1 if funde else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
