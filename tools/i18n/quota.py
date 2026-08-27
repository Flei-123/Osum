#!/usr/bin/env python3
# tools/i18n/quota.py -- WIEVIEL IST WIRKLICH UEBERSETZT?
#
#   python3 tools/i18n/quota.py [locale-verzeichnis]
#
# Englisch ist die Quellsprache: locale/en/messages legt fest, welche
# Schluessel es gibt. Jede andere Sprache wird dagegen gehalten:
#
#   * Wieviele der englischen Schluessel sie hat (die Abdeckung).
#   * Welche ihr FEHLEN -- sie erscheinen zur Laufzeit auf Englisch,
#     was richtig ist und trotzdem gezaehlt gehoert.
#   * Welche sie ZUSAETZLICH hat -- die kann sie nicht brauchen, es gibt
#     keinen englischen Text, fuer den sie einspringen koennten. Genau
#     das zaehlt `msg.unknown()` auch zur Laufzeit.
#   * Wieviele ihrer Texte mit dem englischen IDENTISCH sind. Das ist
#     kein Fehler -- "Start", "Name:", "us\nde" und "800 x 600" sind in
#     beiden Sprachen dasselbe --, aber es ist die Zahl, an der man
#     sieht, ob jemand eine Datei kopiert und nicht uebersetzt hat.
#   * Und die LAENGSTEN Texte, weil `msg.fi` einen Platz von VALW
#     Oktetten je Schluessel hat und ein laengerer abgeschnitten wird.
import os
import sys

VALW = 96  # muss mit kernel/user/msg.fi uebereinstimmen
KEYW = 40


def lies(pfad):
    aus = {}
    fehler = []
    for nr, zeile in enumerate(open(pfad, encoding="utf-8"), 1):
        z = zeile.rstrip("\n")
        if not z.strip() or z.lstrip().startswith("#"):
            continue
        if "=" not in z:
            fehler.append((nr, z))
            continue
        k, v = z.split("=", 1)
        k = k.strip()
        # Genau EIN Leerzeichen vorne wird geschluckt, hinten keines --
        # dieselbe Regel wie in msg.parse, weil "Adresse: " mit Absicht
        # auf einem Leerzeichen endet.
        if v.startswith(" "):
            v = v[1:]
        aus[k] = v
    return aus, fehler


def main():
    wurzel = sys.argv[1] if len(sys.argv) > 1 else "locale"
    en, fehler_en = lies(os.path.join(wurzel, "en", "messages"))
    if not en:
        print("keine Quellsprache unter %s/en/messages" % wurzel)
        return 1
    schlecht = 0
    zeilen = []
    codes = sorted(d for d in os.listdir(wurzel)
                   if os.path.isdir(os.path.join(wurzel, d)) and d != "en")
    for code in codes:
        p = os.path.join(wurzel, code, "messages")
        if not os.path.exists(p):
            continue
        de, fehler = lies(p)
        fehlt = [k for k in en if k not in de]
        zuviel = [k for k in de if k not in en]
        gleich = [k for k in de if k in en and de[k] == en[k]]
        deckung = (len(en) - len(fehlt)) * 100 // len(en)
        zeilen.append("%s: %d von %d Schluesseln = %d%% abgedeckt, "
                      "%d fehlen, %d unbekannt, %d gleich wie Englisch"
                      % (code, len(en) - len(fehlt), len(en), deckung,
                         len(fehlt), len(zuviel), len(gleich)))
        for k in fehlt:
            zeilen.append("    fehlt in %s: %s" % (code, k))
        for k in zuviel:
            zeilen.append("    UNBEKANNT in %s: %s" % (code, k))
            schlecht += 1
        for nr, z in fehler:
            zeilen.append("    kaputte Zeile %s:%d: %s" % (p, nr, z))
            schlecht += 1
        # Die Plaetze.
        for k, v in sorted(de.items()):
            roh = v.replace("\\n", "\n").replace("\\t", "\t") \
                   .replace("\\\\", "\\")
            n = len(roh.encode("utf-8"))
            if n + 1 > VALW:
                zeilen.append("    ZU LANG (%d von %d Oktetten): %s = %s"
                              % (n, VALW - 1, k, v))
                schlecht += 1
        for k in de:
            if len(k) + 1 > KEYW:
                zeilen.append("    SCHLUESSEL ZU LANG (%d von %d): %s"
                              % (len(k), KEYW - 1, k))
                schlecht += 1
    for nr, z in fehler_en:
        zeilen.append("    kaputte Zeile en:%d: %s" % (nr, z))
        schlecht += 1
    lang_en = max((len(v.encode("utf-8")) for v in en.values()), default=0)
    kopf = ("Englisch: %d Schluessel, laengster Text %d Oktette, "
            "laengster Schluessel %d"
            % (len(en), lang_en, max(len(k) for k in en)))
    print(kopf)
    for z in zeilen:
        print(z)
    return 1 if schlecht else 0


sys.exit(main())
