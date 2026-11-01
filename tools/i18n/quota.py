#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import sys

VALW = 192
KEYW = 48


def read_2(path_2):
    aus = {}
    error = []
    for nr, line in enumerate(open(path_2, encoding="utf-8"), 1):
        z = line.rstrip("\n")
        if not z.strip() or z.lstrip().startswith("#"):
            continue
        if "=" not in z:
            error.append((nr, z))
            continue
        k, v = z.split("=", 1)
        k = k.strip()
        if v.startswith(" "):
            v = v[1:]
        aus[k] = v
    return aus, error


def main():
    wurzel = sys.argv[1] if len(sys.argv) > 1 else "locale"
    en, error_en = read_2(os.path.join(wurzel, "en", "messages"))
    if not en:
        print("no source language under %s/en/messages" % wurzel)
        return 1
    bad_2 = 0
    zeilen = []
    codes = sorted(d for d in os.listdir(wurzel)
                   if os.path.isdir(os.path.join(wurzel, d)) and d != "en")
    for code in codes:
        p = os.path.join(wurzel, code, "messages")
        if not os.path.exists(p):
            continue
        de, error = read_2(p)
        missing = [k for k in en if k not in de]
        zuviel = [k for k in de if k not in en]
        eq = [k for k in de if k in en and de[k] == en[k]]
        deckung = (len(en) - len(missing)) * 100 // len(en)
        zeilen.append("%s: %d von %d Schluesseln = %d%% abgedeckt, "
                      "%d fehlen, %d unbekannt, %d gleich wie Englisch"
                      % (code, len(en) - len(missing), len(en), deckung,
                         len(missing), len(zuviel), len(eq)))
        for k in missing:
            zeilen.append("    fehlt in %s: %s" % (code, k))
        for k in zuviel:
            zeilen.append("    UNBEKANNT in %s: %s" % (code, k))
            bad_2 += 1
        for nr, z in error:
            zeilen.append("    kaputte Zeile %s:%d: %s" % (p, nr, z))
            bad_2 += 1
        for k, v in sorted(de.items()):
            roh = v.replace("\\n", "\n").replace("\\t", "\t") \
                   .replace("\\\\", "\\")
            n = len(roh.encode("utf-8"))
            if n + 1 > VALW:
                zeilen.append("    ZU LANG (%d von %d Oktetten): %s = %s"
                              % (n, VALW - 1, k, v))
                bad_2 += 1
        for k in de:
            if len(k) + 1 > KEYW:
                zeilen.append("    SCHLUESSEL ZU LANG (%d von %d): %s"
                              % (len(k), KEYW - 1, k))
                bad_2 += 1
    for nr, z in error_en:
        zeilen.append("    kaputte Zeile en:%d: %s" % (nr, z))
        bad_2 += 1
    lang_en = max((len(v.encode("utf-8")) for v in en.values()), default=0)
    header = ("Englisch: %d Schluessel, laengster Text %d Oktette, "
            "laengster Schluessel %d"
            % (len(en), lang_en, max(len(k) for k in en)))
    print(header)
    for z in zeilen:
        print(z)
    return 1 if bad_2 else 0


sys.exit(main())
