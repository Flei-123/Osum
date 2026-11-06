#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import glob
import os
import re
import sys

STAEMME = [
    ("aendern",      "ändern"),
    ("aendert",      "ändert"),
    ("Aenderung",    "Änderung"),
    ("geaendert",    "geändert"),
    ("unveraendert", "unverändert"),
    ("Groesse",      "Größe"),
    ("groesse",      "größe"),
    ("groesser",     "größer"),
    ("groesst",      "größt"),
    ("fuer",         "für"),
    ("Fuer",         "Für"),
    ("fuehr",        "führ"),
    ("Fuehr",        "Führ"),
    ("ueber",        "über"),
    ("Ueber",        "Über"),
    ("uebersetz",    "übersetz"),
    ("Uebersetz",    "Übersetz"),
    ("uebergang",    "übergang"),
    ("uebernehm",    "übernehm"),
    ("uebernomm",    "übernomm"),
    ("schliess",     "schließ"),
    ("Schliess",     "Schließ"),
    ("ausschliess",  "ausschließ"),
    ("zurueck",      "zurück"),
    ("Zurueck",      "Zurück"),
    ("waehl",        "wähl"),
    ("Waehl",        "Wähl"),
    ("gewaehl",      "gewähl"),
    ("loesch",       "lösch"),
    ("Loesch",       "Lösch"),
    ("oeffn",        "öffn"),
    ("Oeffn",        "Öffn"),
    ("geoeffn",      "geöffn"),
    ("naechst",      "nächst"),
    ("Naechst",      "Nächst"),
    ("laedt",        "lädt"),
    ("laeuft",       "läuft"),
    ("laesst",       "lässt"),
    ("Laenge",       "Länge"),
    ("laenge",       "länge"),
    ("laenger",      "länger"),
    ("Schluessel",   "Schlüssel"),
    ("schluessel",   "schlüssel"),
    ("moegl",        "mögl"),
    ("Moegl",        "Mögl"),
    ("hoech",        "höch"),
    ("Hoech",        "Höch"),
    ("traeger",      "träger"),
    ("Traeger",      "Träger"),
    ("traegt",       "trägt"),
    ("zaehl",        "zähl"),
    ("Zaehl",        "Zähl"),
    ("gehoer",       "gehör"),
    ("Gehoer",       "Gehör"),
    ("stuetz",       "stütz"),
    ("Stuetz",       "Stütz"),
    ("pruef",        "prüf"),
    ("Pruef",        "Prüf"),
    ("Flaeche",      "Fläche"),
    ("flaeche",      "fläche"),
    ("Oberflaeche",  "Oberfläche"),
    ("erklaer",      "erklär"),
    ("Erklaer",      "Erklär"),
    ("waehrend",     "während"),
    ("Waehrend",     "Während"),
    ("spaeter",      "später"),
    ("taeusch",      "täusch"),
    ("Taeusch",      "Täusch"),
    ("vorgetaeusch", "vorgetäusch"),
    ("Vorgetaeusch", "Vorgetäusch"),
    ("vorwaerts",    "vorwärts"),
    ("Vorwaerts",    "Vorwärts"),
    ("rueckwaerts",  "rückwärts"),
    ("Menue",        "Menü"),
    ("menue",        "menü"),
    ("Knoepfe",      "Knöpfe"),
    ("knoepfe",      "knöpfe"),
    ("Buendel",      "Bündel"),
    ("buendel",      "bündel"),
    ("haeng",        "häng"),
    ("Haeng",        "Häng"),
    ("abhaeng",      "abhäng"),
    ("Massnahm",     "Maßnahm"),
    ("massnahm",     "maßnahm"),
    ("Strasse",      "Straße"),
    ("strasse",      "straße"),
    ("gross",        "groß"),
    ("Gross",        "Groß"),
    ("heiss",        "heiß"),
    ("Heiss",        "Heiß"),
    ("aeuss",        "äuß"),
    ("Aeuss",        "Äuß"),
    ("muessen",      "müssen"),
    ("koenn",        "könn"),
    ("Koenn",        "Könn"),
    ("wuerd",        "würd"),
    ("duerf",        "dürf"),
    ("ausfuehr",     "ausführ"),
    ("Ausfuehr",     "Ausführ"),
    ("durchfuehr",   "durchführ"),
    ("liess",        "ließ"),
    ("Liess",        "Ließ"),
    ("hiess",        "hieß"),
    ("Hiess",        "Hieß"),
    ("fliess",       "fließ"),
    ("Fliess",       "Fließ"),
    ("faeng",        "fäng"),
    ("Faeng",        "Fäng"),
    ("gaeng",        "gäng"),
    ("Gaeng",        "Gäng"),
    ("geraet",       "gerät"),
    ("Geraet",       "Gerät"),
    ("GERAET",       "GERÄT"),
    ("bloeck",       "blöck"),
    ("Bloeck",       "Blöck"),
    ("saettig",      "sättig"),
    ("Saettig",      "Sättig"),
    ("rueck",        "rück"),
    ("Rueck",        "Rück"),
    ("itaet",        "ität"),
    ("waerm",        "wärm"),
    ("Waerm",        "Wärm"),
    ("fueg",         "füg"),
    ("Fueg",         "Füg"),
    ("haelt",        "hält"),
    ("Haelt",        "Hält"),
    ("traeg",        "träg"),
    ("Traeg",        "Träg"),
    ("schlaeg",      "schläg"),
    ("Schlaeg",      "Schläg"),
    ("saetze",       "sätze"),
    ("Saetze",       "Sätze"),
    ("staend",       "ständ"),
    ("Staend",       "Ständ"),
    ("aendr",        "ändr"),
    ("haeng",        "häng"),
    ("Haeng",        "Häng"),
    ("koerp",        "körp"),
    ("Koerp",        "Körp"),
    ("hoer",         "hör"),
    ("Hoer",         "Hör"),
    ("stoer",        "stör"),
    ("Stoer",        "Stör"),
    ("bloed",        "blöd"),
    ("froeh",        "fröh"),
    ("kuerz",        "kürz"),
    ("Kuerz",        "Kürz"),
    ("stueck",       "stück"),
    ("Stueck",       "Stück"),
    ("zurueckset",   "zurückset"),
    ("gruen",        "grün"),
    ("Gruen",        "Grün"),
    ("wuensch",      "wünsch"),
    ("Wuensch",      "Wünsch"),
    ("gueltig",      "gültig"),
    ("Gueltig",      "Gültig"),
    ("verfueg",      "verfüg"),
    ("Verfueg",      "Verfüg"),
    ("genueg",       "genüg"),
    ("Genueg",       "Genüg"),
    ("uebrig",       "übrig"),
    ("Uebrig",       "Übrig"),
    ("ueblich",      "üblich"),
    ("Ueblich",      "Üblich"),
    ("aehnlich",     "ähnlich"),
    ("Aehnlich",     "Ähnlich"),
    ("naeher",       "näher"),
    ("Naeher",       "Näher"),
    ("spuel",        "spül"),
    ("fuell",        "füll"),
    ("Fuell",        "Füll"),
    ("gefuell",      "gefüll"),
    ("schluess",     "schlüss"),
    ("Schluess",     "Schlüss"),
    ("Umschrift-x",  "Umschrift-x"),
]
STAEMME = [s for s in STAEMME if s[0] != "Umschrift-x"]
_ORD = sorted(STAEMME, key=lambda s: len(s[0]), reverse=True)
_RE = re.compile("|".join(re.escape(s[0]) for s in _ORD))
_FALLBACK = dict(STAEMME)

_ZITAT = re.compile(r'"[^"]*"')


def finde(text, zitate_count=True):
    if not zitate_count:
        text = _ZITAT.sub(lambda m: " " * len(m.group(0)), text)
    aus = []
    for m in _RE.finditer(text):
        s = m.group(0)
        aus.append((s, _FALLBACK[s]))
    return aus


def grenzen(root):
    msg = open(os.path.join(root, "kernel/user/msg.fi"),
               encoding="utf-8").read()
    aus = {}
    for name in ("KEYW", "VALW", "SLOTS", "FILE_MAX"):
        m = re.search(r"^const %s: u64 = (\d+)" % name, msg, re.M)
        if not m:
            raise SystemExit("msg.fi: const %s nicht gefunden" % name)
        aus[name] = int(m.group(1))
    ad = open(os.path.join(root, "kernel/user/appdir.fi"),
              encoding="utf-8").read()
    m = re.search(r"io\.read(?:_full)?\(fd, \(&buf\[0 as usize\]\) as u64, (\d+)\)", ad)
    if not m:
        raise SystemExit("appdir.fi: die Leselaenge fuer INFO nicht gefunden")
    aus["INFO_READ"] = int(m.group(1))
    return aus


def main(argv):
    root = os.environ.get("OSUM_ROOT", ".")
    zaehle = "--zaehle" in argv
    g = grenzen(root)
    print("translit: KEYW=%d VALW=%d SLOTS=%d FILE_MAX=%d INFO_READ=%d"
          % (g["KEYW"], g["VALW"], g["SLOTS"], g["FILE_MAX"], g["INFO_READ"]))

    error = []
    eng = []
    umlaute = 0
    geprueft = 0

    for path_2 in sorted(glob.glob(os.path.join(root, "locale/de/*"))):
        rel = os.path.relpath(path_2, root)
        for nr, line in enumerate(
                open(path_2, encoding="utf-8").read().split("\n"), 1):
            umlaute += sum(1 for c in line if c in "äöüÄÖÜß")
            ist_komm = line.lstrip().startswith("#")
            if ist_komm:
                treffer = finde(line, zitate_count=False)
            elif "=" in line:
                geprueft += 1
                k, v = line.split("=", 1)
                k, v = k.strip(), v.strip()
                if len(k.encode()) >= g["KEYW"]:
                    eng.append("%s:%d  Schluessel %d Oktette >= KEYW %d  %s"
                               % (rel, nr, len(k.encode()), g["KEYW"], k))
                if len(v.encode()) >= g["VALW"]:
                    eng.append("%s:%d  Wert %d Oktette >= VALW %d  %s"
                               % (rel, nr, len(v.encode()), g["VALW"], v[:40]))
                treffer = finde(v)
            else:
                continue
            for stamm, ersatz in treffer:
                error.append("%s:%d  %-14s -> %-14s | %s"
                              % (rel, nr, stamm, ersatz, line.strip()[:56]))
        if len(open(path_2, "rb").read()) >= g["FILE_MAX"]:
            eng.append("%s  %d Oktette >= FILE_MAX %d"
                       % (rel, os.path.getsize(path_2), g["FILE_MAX"]))

    for d in sorted(glob.glob(os.path.join(root, "assets/apps/*.osp"))):
        path_2 = os.path.join(d, "INFO")
        if not os.path.exists(path_2):
            continue
        rel = os.path.relpath(path_2, root)
        roh = open(path_2, "rb").read()
        if len(roh) > g["INFO_READ"]:
            eng.append("%s  %d Oktette > die %d, die appdir liest -- der "
                       "Rest der Datei ist fuer das System nicht da"
                       % (rel, len(roh), g["INFO_READ"]))
        for nr, line in enumerate(roh.decode("utf-8").split("\n"), 1):
            umlaute += sum(1 for c in line if c in "äöüÄÖÜß")
            if line.startswith("keys="):
                woerter = [w.strip() for w in
                           line.split("=", 1)[1].split(",")]
                for w in woerter:
                    if not w:
                        continue
                    t = finde(w)
                    if not t:
                        continue
                    geprueft += 1
                    soll = w
                    for stamm, ersatz in t:
                        soll = soll.replace(stamm, ersatz)
                    if soll not in woerter:
                        error.append(
                            "%s:%d  keys= hat '%s', aber nicht '%s' "
                            "-- die Umlautform gehoert DANEBEN, nicht "
                            "statt dessen" % (rel, nr, w, soll))
                continue
            if not line.startswith(("name=", "info=")):
                continue
            geprueft += 1
            for stamm, ersatz in finde(line.split("=", 1)[1]):
                error.append("%s:%d  %-14s -> %-14s | %s"
                              % (rel, nr, stamm, ersatz, line.strip()[:56]))

    print("translit: geprueft=%d umschrift=%d eng=%d umlaute=%d"
          % (geprueft, len(error), len(eng), umlaute))
    for z in error:
        print("    UMSCHRIFT  " + z)
    for z in eng:
        print("    ZU ENG     " + z)
    if zaehle:
        print("translit: echte Umlautzeichen in locale/de + assets/apps: %d"
              % umlaute)
    if error:
        return 1
    if eng:
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
