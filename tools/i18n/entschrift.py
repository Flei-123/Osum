#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import subprocess
import sys

FALLBACK = [
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
    ("muss", "muss"),
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
FALLBACK.sort(key=lambda p: -len(p[0]))

_STR = re.compile(r'"((?:[^"\\]|\\.)*)"')
_BUF = re.compile(r'\[u8;\s*(\d+)\]')


def loese(text):
    aus = []
    new = text
    for asc, uml in FALLBACK:
        if asc == uml:
            continue
        if asc in new:
            new = new.replace(asc, uml)
            aus.append((asc, uml))
    return new, aus


def ask(root):
    umg = dict(os.environ, OSUM_ROOT=root)
    p = subprocess.run([sys.executable, "tools/i18n/sources.py", "--everything"],
                       capture_output=True, text=True, cwd=root, env=umg)
    aus = {}
    for z in p.stdout.split("\n"):
        t = z.split()
        if len(t) >= 3 and t[0] == "SICHTBAR":
            try:
                aus.setdefault(t[1], set()).add(int(t[2]))
            except ValueError:
                pass
    return aus


def bearbeite(path_2, zeilennummern, schreibe):
    with open(path_2, encoding="utf-8") as f:
        rows = f.read().split("\n")
    geaendert = 0
    bericht = []
    for nr in sorted(zeilennummern):
        if nr < 1 or nr > len(rows):
            continue
        alt = rows[nr - 1]
        funde = []

        def ersetze_str(m):
            inhalt = m.group(1)
            new_inhalt, gefunden = loese(inhalt)
            if gefunden:
                funde.extend(gefunden)
                return '"' + new_inhalt + '"'
            return m.group(0)

        new = _STR.sub(ersetze_str, alt)
        if not funde:
            continue
        m_alt = _STR.search(alt)
        m_new = _STR.search(new)
        if m_alt and m_new:
            d = len(m_new.group(1).encode("utf-8")) \
                - len(m_alt.group(1).encode("utf-8"))
            if d:
                mb = _BUF.search(new)
                if mb:
                    new = (new[:mb.start(1)] + str(int(mb.group(1)) + d)
                           + new[mb.end(1):])
        if new != alt:
            rows[nr - 1] = new
            geaendert += 1
            bericht.append((nr, alt.strip(), new.strip()))
    if geaendert and schreibe:
        with open(path_2, "w", encoding="utf-8") as f:
            f.write("\n".join(rows))
    return geaendert, bericht


def main(argv):
    schreibe = "--schreibe" in argv
    root = os.environ.get("OSUM_ROOT", ".")
    target = [a for a in argv[1:] if not a.startswith("--")]
    card = ask(root)
    if target:
        card = {d: n for d, n in card.items()
                 if any(d.endswith(z) or z in d for z in target)}
    ges = 0
    for file_2 in sorted(card):
        path_2 = os.path.join(root, file_2)
        if not os.path.exists(path_2):
            continue
        n, bericht = bearbeite(path_2, card[file_2], schreibe)
        if n:
            ges += n
            print("%s  %d Zeilen" % (file_2, n))
            for nr, a, b in bericht:
                print("   %5d - %s" % (nr, a[:96]))
                print("         + %s" % b[:96])
    print()
    print("entschrift: %d Zeilen in %d Dateien%s"
          % (ges, len([d for d in card]),
             "" if schreibe else "  (PROBELAUF -- nichts geschrieben)"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
