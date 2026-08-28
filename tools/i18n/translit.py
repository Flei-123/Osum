#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/i18n/translit.py -- in Sprachdateien stehen ECHTE ZEICHEN.

WOFUER DIESE PRUEFUNG DA IST. Bis Runde I18N konnte dieses System kein
"ue" auf den Bildschirm bringen, und deshalb stand im ganzen Baum die
UMSCHRIFT: "aendern", "Groesse", "schliessen", "Menue". Seit I18N kann
die Schrift es (339 Zeichen, `assets/osum-sans.ttf`) und der Rasterer
auch. Damit ist die Umschrift kein Notbehelf mehr, sondern ein FEHLER --
und ein Fehler, den niemand bemerkt, weil die Zeile ja lesbar bleibt.
Genau so ist "Text schreiben und aendern" ein halbes Jahr lang auf dem
Schirm gestanden, waehrend zwei Zeilen darueber "Ausfuehren" schon
richtig als "Ausführen" erschien.

Eine Zusage, die ein Mensch mit dem Auge nachsehen muss, ist keine.
Deshalb diese hier.

WAS GEPRUEFT WIRD

  1. locale/de/*        JEDER Wert rechts vom "=" und jeder Kommentar.
  2. assets/apps/*.osp/INFO   `name=` und `info=` -- das sind die
                        Beschriftungen im Starter, also Bildschirmtext.
  3. Die LAENGEN, die diese Texte tragen: der Katalog-Wert gegen VALW
     und der Schluessel gegen KEYW aus kernel/user/msg.fi, und die
     INFO-Datei gegen die 1023 Oktette, die `appdir.eine_datei` liest.

WARUM EINE WORTLISTE UND KEIN MUSTER. "ae", "oe", "ue" und "ss" kommen
in richtigem Deutsch dauernd vor: Prozess, Adresse, Klasse, Messung,
Wasser, muss, dass, Poesie, aktuell, Dueren. Ein Muster auf die
Buchstabenpaare wuerde jede zweite Zeile anmeckern und waere nach einer
Woche abgeschaltet. Gesucht werden also STAEMME, die es im Deutschen nur
als Umschrift gibt -- und jeder Fund nennt den Ersatz, damit man ihn
nicht nachschlagen muss.

WAS ERLAUBT BLEIBT. Ein Kommentar darf UEBER die Umschrift reden. Dafuer
muss das Wort in Anfuehrungszeichen stehen ("ue" statt "ü") -- was in
Anfuehrungszeichen steht, ist ein ZITAT und kein Text. Das ist die
gleiche Regel wie sonst im Baum: ein Beispiel wird gezeigt, nicht
verwendet.

  tools/i18n/translit.py            prueft und meldet
  tools/i18n/translit.py --zaehle   dazu die Zahl der echten Umlaute

rc=0 alles sauber, rc=1 Umschrift gefunden, rc=2 etwas passt nicht mehr
in seinen Puffer.
"""
import glob
import os
import re
import sys

# ------------------------------------------------------------------
# Staemme, die es im Deutschen NUR als Umschrift gibt -> was hingehoert.
# Bewusst NICHT dabei: muss, dass, Fluss, Schloss, Prozess, Adresse,
# Klasse, Masse, Messung, Wasser, besser, Kongress, Interesse -- alles
# richtig geschrieben, alles mit "ss", und kein Fall fuer diese Liste.
# ------------------------------------------------------------------
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
    ("Umschrift-x",  "Umschrift-x"),  # nie ein Treffer, haelt die Liste stabil
]
STAEMME = [s for s in STAEMME if s[0] != "Umschrift-x"]
# Laengste zuerst, damit "Vorgetaeusch" vor "taeusch" greift.
_ORD = sorted(STAEMME, key=lambda s: len(s[0]), reverse=True)
_RE = re.compile("|".join(re.escape(s[0]) for s in _ORD))
_ERSATZ = dict(STAEMME)

# Was in Anfuehrungszeichen steht, ist ein ZITAT.
_ZITAT = re.compile(r'"[^"]*"')


def finde(text, zitate_zaehlen=True):
    """-> Liste (stamm, ersatz) fuer jeden Fund ausserhalb von Zitaten."""
    if not zitate_zaehlen:
        text = _ZITAT.sub(lambda m: " " * len(m.group(0)), text)
    aus = []
    for m in _RE.finditer(text):
        s = m.group(0)
        aus.append((s, _ERSATZ[s]))
    return aus


# ------------------------------------------------------------------
# Die Puffergrenzen, die diese Texte tragen -- aus dem Quelltext
# gelesen, nicht abgeschrieben. Eine abgeschriebene Zahl ist genau die
# Zahl, die beim naechsten Mal nicht mitwandert.
# ------------------------------------------------------------------
def grenzen(wurzel):
    msg = open(os.path.join(wurzel, "kernel/user/msg.fi"),
               encoding="utf-8").read()
    aus = {}
    for name in ("KEYW", "VALW", "SLOTS", "FILE_MAX"):
        m = re.search(r"^const %s: u64 = (\d+)" % name, msg, re.M)
        if not m:
            raise SystemExit("msg.fi: const %s nicht gefunden" % name)
        aus[name] = int(m.group(1))
    ad = open(os.path.join(wurzel, "kernel/user/appdir.fi"),
              encoding="utf-8").read()
    m = re.search(r"io\.read\(fd, \(&buf\[0 as usize\]\) as u64, (\d+)\)", ad)
    if not m:
        raise SystemExit("appdir.fi: die Leselaenge fuer INFO nicht gefunden")
    aus["INFO_READ"] = int(m.group(1))
    return aus


def main(argv):
    wurzel = os.environ.get("OSUM_ROOT", ".")
    zaehle = "--zaehle" in argv
    g = grenzen(wurzel)
    print("translit: KEYW=%d VALW=%d SLOTS=%d FILE_MAX=%d INFO_READ=%d"
          % (g["KEYW"], g["VALW"], g["SLOTS"], g["FILE_MAX"], g["INFO_READ"]))

    fehler = []
    eng = []
    umlaute = 0
    geprueft = 0

    # ---- 1. die Sprachdateien
    for pfad in sorted(glob.glob(os.path.join(wurzel, "locale/de/*"))):
        rel = os.path.relpath(pfad, wurzel)
        for nr, zeile in enumerate(
                open(pfad, encoding="utf-8").read().split("\n"), 1):
            umlaute += sum(1 for c in zeile if c in "äöüÄÖÜß")
            ist_komm = zeile.lstrip().startswith("#")
            if ist_komm:
                # Ein Kommentar darf die Umschrift ZITIEREN, nicht benutzen.
                treffer = finde(zeile, zitate_zaehlen=False)
            elif "=" in zeile:
                geprueft += 1
                k, v = zeile.split("=", 1)
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
                fehler.append("%s:%d  %-14s -> %-14s | %s"
                              % (rel, nr, stamm, ersatz, zeile.strip()[:56]))
        if len(open(pfad, "rb").read()) >= g["FILE_MAX"]:
            eng.append("%s  %d Oktette >= FILE_MAX %d"
                       % (rel, os.path.getsize(pfad), g["FILE_MAX"]))

    # ---- 2. die Buendel-Beschriftungen
    for d in sorted(glob.glob(os.path.join(wurzel, "assets/apps/*.osp"))):
        pfad = os.path.join(d, "INFO")
        if not os.path.exists(pfad):
            continue
        rel = os.path.relpath(pfad, wurzel)
        roh = open(pfad, "rb").read()
        if len(roh) > g["INFO_READ"]:
            eng.append("%s  %d Oktette > die %d, die appdir liest -- der "
                       "Rest der Datei ist fuer das System nicht da"
                       % (rel, len(roh), g["INFO_READ"]))
        for nr, zeile in enumerate(roh.decode("utf-8").split("\n"), 1):
            umlaute += sum(1 for c in zeile if c in "äöüÄÖÜß")
            if not zeile.startswith(("name=", "info=")):
                continue
            geprueft += 1
            for stamm, ersatz in finde(zeile.split("=", 1)[1]):
                fehler.append("%s:%d  %-14s -> %-14s | %s"
                              % (rel, nr, stamm, ersatz, zeile.strip()[:56]))

    print("translit: geprueft=%d umschrift=%d eng=%d umlaute=%d"
          % (geprueft, len(fehler), len(eng), umlaute))
    for z in fehler:
        print("    UMSCHRIFT  " + z)
    for z in eng:
        print("    ZU ENG     " + z)
    if zaehle:
        print("translit: echte Umlautzeichen in locale/de + assets/apps: %d"
              % umlaute)
    if fehler:
        return 1
    if eng:
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
