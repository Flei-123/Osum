#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/i18n/entschrift.py -- Umschrift in SICHTBAREN Texten aufloesen.

    entschrift.py [--schreibe] [datei ...]

WARUM.

`tools/i18n/quellen.py --alle` zaehlt in kernel/** die Stellen, an denen
ein SICHTBARER Text noch Umschrift traegt ("Geraet" statt "Gerät").
Gemessen am 14.09.2026: SICHTBAR=125 in 30 Dateien. Die Zusage des
Abschnitts `umlaut` lautet null.

Von Hand ist das 125-mal dieselbe Handbewegung, und genau dabei
passiert der Fehler, der teuer ist:

DIE PUFFER SIND IN OKTETTEN BEMESSEN, NICHT IN ZEICHEN.

    var n5: [u8; 15] = "platte_bloecke\\0"

`bloecke` (7 Oktette) wird zu `blöcke` (7 Oktette: b l ö=2 c k e) --
hier bleibt die Zahl gleich. Aber `groesser` (8) wird zu `größer`
(7: g r ö=2 ß=2 e r), und `Geraet` (6) wird zu `Gerät` (6). Die Zahl
in `[u8; N]` muss also NEU GERECHNET werden, und zwar aus der
UTF-8-Laenge der neuen Zeichenkette plus den Null-Oktetten, die schon
dastanden. Wer sie stehenlaesst, bekommt entweder einen abgeschnittenen
Text oder einen Uebersetzerfehler -- und im schlimmsten Fall einen
Puffer, der ein Oktett zu klein ist und beim Schreiben ueberlaeuft.

WIE GERECHNET WIRD.

Fuer jede Zeile der Form

    var NAME: [u8; N] = "TEXT"

ist N die Zahl der Oktette, die dastehen: len(TEXT.encode()) einschliess-
lich der `\\0` am Ende. Die Differenz zwischen alter und neuer
UTF-8-Laenge wird auf N addiert. Steht in der Zeile kein `[u8; N]`
(ein Aufruf wie `ablehnen(aus, "...")`), wird nur der Text ersetzt.

SICHERHEIT. Ohne `--schreibe` wird NICHTS veraendert; das Programm
zeigt nur, was es taete. Ersetzt wird ausschliesslich innerhalb von
Zeichenketten in Zeilen, die `quellen.py` als SICHTBAR meldet -- Namen
von Funktionen, Marken und Mitschnitte bleiben unangetastet.
"""
import os
import re
import subprocess
import sys

# Die Umschriften, die aufzuloesen sind. Laengster Stamm zuerst, damit
# "groesser" nicht als "oe" in der Mitte zerfaellt.
ERSATZ = [
    ("Oberflaeche", "Oberfläche"), ("oberflaeche", "oberfläche"),
    ("Bloecke", "Blöcke"), ("bloecke", "blöcke"),
    ("Bloecken", "Blöcken"), ("bloecken", "blöcken"),
    ("groesser", "größer"), ("Groesser", "Größer"),
    ("groesste", "größte"), ("Groesste", "Größte"),
    ("Groesse", "Größe"), ("groesse", "größe"),
    ("schliess", "schließ"), ("Schliess", "Schließ"),
    ("heisst", "heißt"), ("Heisst", "Heißt"),
    ("liess", "ließ"), ("Liess", "Ließ"),
    ("laesst", "lässt"), ("Laesst", "Lässt"),
    ("Geraet", "Gerät"), ("geraet", "gerät"),
    ("Zaehler", "Zähler"), ("zaehler", "zähler"),
    ("zaehl", "zähl"), ("Zaehl", "Zähl"),
    ("waehl", "wähl"), ("Waehl", "Wähl"),
    ("naechst", "nächst"), ("Naechst", "Nächst"),
    ("Laenge", "Länge"), ("laenge", "länge"),
    ("haengt", "hängt"), ("haengen", "hängen"),
    ("Rueck", "Rück"), ("rueck", "rück"),
    ("zurueck", "zurück"), ("Zurueck", "Zurück"),
    ("ueber", "über"), ("Ueber", "Über"),
    ("pruef", "prüf"), ("Pruef", "Prüf"),
    ("fuer", "für"), ("Fuer", "Für"),
    ("muss", "muss"),  # unveraendert, steht nur der Vollstaendigkeit halber
    ("oeffn", "öffn"), ("Oeffn", "Öffn"),
    ("loesch", "lösch"), ("Loesch", "Lösch"),
    ("aufloes", "auflös"), ("Aufloes", "Auflös"),
    ("moeglich", "möglich"), ("Moeglich", "Möglich"),
    ("noetig", "nötig"), ("Noetig", "Nötig"),
    ("koennen", "können"), ("Koennen", "Können"),
    ("kuerz", "kürz"), ("Kuerz", "Kürz"),
    ("fuehr", "führ"), ("Fuehr", "Führ"),
    ("Schluessel", "Schlüssel"), ("schluessel", "schlüssel"),
    ("Menue", "Menü"), ("menue", "menü"),
    ("Knoepfe", "Knöpfe"), ("knoepfe", "knöpfe"),
    ("Stueck", "Stück"), ("stueck", "stück"),
    ("zusaetzlich", "zusätzlich"), ("Zusaetzlich", "Zusätzlich"),
    ("spaeter", "später"), ("Spaeter", "Später"),
    ("aendern", "ändern"), ("Aendern", "Ändern"),
    ("aenderung", "änderung"), ("Aenderung", "Änderung"),
    ("unveraendert", "unverändert"),
    ("erklaer", "erklär"), ("Erklaer", "Erklär"),
    ("waehrend", "während"), ("Waehrend", "Während"),
    ("gehoert", "gehört"), ("Gehoert", "Gehört"),
    ("hoer", "hör"), ("Hoer", "Hör"),
    ("stoer", "stör"), ("Stoer", "Stör"),
    ("Ausfuehr", "Ausführ"), ("ausfuehr", "ausführ"),
    ("uebernehmen", "übernehmen"), ("Uebernehmen", "Übernehmen"),
    ("uebergabe", "übergabe"), ("Uebergabe", "Übergabe"),
    # ZWEITE RUNDE: die Staemme, die nach dem ersten Lauf uebrigblieben.
    ("hoechstens", "höchstens"), ("Hoechstens", "Höchstens"),
    ("hoech", "höch"), ("Hoech", "Höch"),
    ("laeuft", "läuft"), ("Laeuft", "Läuft"),
    ("Datentraeger", "Datenträger"), ("datentraeger", "datenträger"),
    ("traeger", "träger"), ("Traeger", "Träger"),
    ("heisse", "heiße"), ("Heisse", "Heiße"),
    ("veraendert", "verändert"), ("Veraendert", "Verändert"),
    ("gueltig", "gültig"), ("Gueltig", "Gültig"),
    ("endgueltig", "endgültig"),
    ("gruen", "grün"), ("Gruen", "Grün"),
    ("Anschlaege", "Anschläge"), ("anschlaege", "anschläge"),
    ("schlaege", "schläge"), ("Schlaege", "Schläge"),
    ("verfuegbar", "verfügbar"), ("Verfuegbar", "Verfügbar"),
    ("verfueg", "verfüg"), ("Verfueg", "Verfüg"),
    ("bloed", "blöd"), ("Bloed", "Blöd"),
    ("wuerde", "würde"), ("Wuerde", "Würde"),
    ("wuerd", "würd"), ("Wuerd", "Würd"),
    ("Eintraege", "Einträge"), ("eintraege", "einträge"),
    ("traege", "träge"), ("Traege", "Träge"),
    ("gross", "groß"), ("Gross", "Groß"),
    ("GERAET", "GERÄT"),
]
ERSATZ.sort(key=lambda p: -len(p[0]))

_STR = re.compile(r'"((?:[^"\\]|\\.)*)"')
_BUF = re.compile(r'\[u8;\s*(\d+)\]')


def loese(text):
    """Umschrift in TEXT aufloesen. -> (neu, [(alt, neu), ...])"""
    aus = []
    neu = text
    for asc, uml in ERSATZ:
        if asc == uml:
            continue
        if asc in neu:
            neu = neu.replace(asc, uml)
            aus.append((asc, uml))
    return neu, aus


def stellen(wurzel):
    """Die SICHTBAR-Funde von quellen.py -> {datei: {zeilennr}}."""
    umg = dict(os.environ, OSUM_ROOT=wurzel)
    p = subprocess.run([sys.executable, "tools/i18n/quellen.py", "--alle"],
                       capture_output=True, text=True, cwd=wurzel, env=umg)
    aus = {}
    for z in p.stdout.split("\n"):
        t = z.split()
        if len(t) >= 3 and t[0] == "SICHTBAR":
            try:
                aus.setdefault(t[1], set()).add(int(t[2]))
            except ValueError:
                pass
    return aus


def bearbeite(pfad, zeilennummern, schreibe):
    with open(pfad, encoding="utf-8") as f:
        zeilen = f.read().split("\n")
    geaendert = 0
    bericht = []
    for nr in sorted(zeilennummern):
        if nr < 1 or nr > len(zeilen):
            continue
        alt = zeilen[nr - 1]
        # Nur INNERHALB von Zeichenketten ersetzen.
        funde = []

        def ersetze_str(m):
            inhalt = m.group(1)
            neu_inhalt, gefunden = loese(inhalt)
            if gefunden:
                funde.extend(gefunden)
                # Die Puffergroesse mitziehen: Differenz in OKTETTEN.
                return '"' + neu_inhalt + '"'
            return m.group(0)

        neu = _STR.sub(ersetze_str, alt)
        if not funde:
            continue
        # Puffergroesse neu rechnen, falls die Zeile eine hat.
        m_alt = _STR.search(alt)
        m_neu = _STR.search(neu)
        if m_alt and m_neu:
            d = len(m_neu.group(1).encode("utf-8")) \
                - len(m_alt.group(1).encode("utf-8"))
            if d:
                mb = _BUF.search(neu)
                if mb:
                    neu = (neu[:mb.start(1)] + str(int(mb.group(1)) + d)
                           + neu[mb.end(1):])
        if neu != alt:
            zeilen[nr - 1] = neu
            geaendert += 1
            bericht.append((nr, alt.strip(), neu.strip()))
    if geaendert and schreibe:
        with open(pfad, "w", encoding="utf-8") as f:
            f.write("\n".join(zeilen))
    return geaendert, bericht


def main(argv):
    schreibe = "--schreibe" in argv
    wurzel = os.environ.get("OSUM_ROOT", ".")
    ziel = [a for a in argv[1:] if not a.startswith("--")]
    karte = stellen(wurzel)
    if ziel:
        karte = {d: n for d, n in karte.items()
                 if any(d.endswith(z) or z in d for z in ziel)}
    ges = 0
    for datei in sorted(karte):
        pfad = os.path.join(wurzel, datei)
        if not os.path.exists(pfad):
            continue
        n, bericht = bearbeite(pfad, karte[datei], schreibe)
        if n:
            ges += n
            print("%s  %d Zeilen" % (datei, n))
            for nr, a, b in bericht:
                print("   %5d - %s" % (nr, a[:96]))
                print("         + %s" % b[:96])
    print()
    print("entschrift: %d Zeilen in %d Dateien%s"
          % (ges, len([d for d in karte]),
             "" if schreibe else "  (PROBELAUF -- nichts geschrieben)"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
