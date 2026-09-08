#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/wlan/fuzz.py -- verstuemmelte Rahmen, und was danach passieren muss.

WARUM DIESER LAUF DER WICHTIGSTE DER RUNDE IST, obwohl er nichts
nachrechnet.

Alles andere in `tools/wlan/vektoren.py` fragt: rechnet es richtig? Das
hier fragt: was tut es, wenn die Eingabe boesartig ist. Und das ist bei
WLAN keine akademische Frage:

  * Ein Beacon kommt von einem Geraet, das niemand kennt.
  * Er ist von niemandem beglaubigt.
  * Er kommt an, BEVOR es einen Schluessel gibt -- es gibt also keinen
    Punkt davor, an dem man ihn haette verwerfen koennen.
  * Jeder mit einer 20-Euro-Karte kann beliebig viele davon senden,
    mit beliebigem Inhalt.

Ein Zerleger fuer 802.11-Verwaltungsrahmen ist damit die groesste
Angriffsflaeche, die dieser Kernel je bekommen hat -- groesser als TCP,
weil TCP wenigstens einen Handschlag davor hat. Die Zusage, die hier
gemessen wird, ist deshalb nicht "das Ergebnis stimmt", sondern:

  1. ES GIBT IMMER EINE ANTWORT. Genau eine Zeile, nie ein Absturz, nie
     eine Endlosschleife.
  2. ES WIRD NIE NEBEN DEN PUFFER GEGRIFFEN. Gemessen mit valgrind:
     jeder Lesezugriff ausserhalb des Rahmens ist ein Fehler, den
     valgrind meldet, und die Zahl muss NULL sein.
  3. EIN ZWEIFELHAFTER RAHMEN WIRD ABGELEHNT UND NICHT GERATEN.
     Insbesondere darf ein abgeschnittener Beacon eines
     WPA2-Netzes NIE als offenes Netz durchgehen -- das waere aus
     einem Uebertragungsfehler eine unverschluesselte Verbindung.

    ./tools/wlan/fuzz.py             der volle Lauf
    ./tools/wlan/fuzz.py --schnell   weniger Faelle, ohne valgrind
"""
import os
import random
import subprocess
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
WURZEL = os.path.dirname(os.path.dirname(HIER))
ORAKEL = os.path.join(WURZEL, ".probe", "worakel")
MITSCHNITT = os.path.join(HIER, "mitschnitt.txt")

SCHNELL = "--schnell" in sys.argv
SAAT = 20260830  # fest, damit ein Fehler wiederholbar ist

pass_n = 0
fail_n = 0


def ok(t):
    global pass_n
    pass_n += 1
    print("  OK    %s" % t)


def bad(t):
    global fail_n
    fail_n += 1
    print("  FAIL  %s" % t)


def lies_mitschnitt():
    daten = {}
    liste = {}
    with open(MITSCHNITT, encoding="utf-8") as f:
        for z in f:
            z = z.strip()
            if not z or z.startswith("#"):
                continue
            k, _, v = z.partition(" ")
            if k in ("beacon", "daten", "beacon_db"):
                liste.setdefault(k, []).append(v)
            else:
                daten[k] = v
    daten.update(liste)
    return daten


def baue_faelle():
    """Aus den echten Rahmen die verstuemmelten machen."""
    m = lies_mitschnitt()
    quellen = []
    for b in m["beacon"]:
        quellen.append(("beacon", bytes.fromhex(b)))
    quellen.append(("beacon", bytes.fromhex(m["probeantwort"])))
    for d in m["daten"]:
        quellen.append(("ccmpdec", bytes.fromhex(d)))
    quellen.append(("eapol", bytes.fromhex(m["eapol1"])))
    quellen.append(("eapol", bytes.fromhex(m["eapol3"])))

    r = random.Random(SAAT)
    faelle = []
    # Welche Faelle unter valgrind laufen MUESSEN: die strukturellen.
    # Ein Zugriff daneben entsteht an einer Laengenrechnung, und die
    # sitzt bei den Kuerzungen, den gelogenen Laengenfeldern und den
    # widerspruechlichen Koepfen -- nicht darin, dass ein Oktett in der
    # Mitte einen anderen Wert hat.
    strukturell = []

    # 1. JEDE Kuerzung jedes Rahmens. Der Empfangspuffer war voll, das
    #    Funkteil hat abgeschnitten -- der haeufigste kaputte Rahmen
    #    ueberhaupt, und der einzige, der auch ohne Angreifer vorkommt.
    for befehl, roh in quellen:
        for n in range(0, len(roh) + 1):
            strukturell.append(len(faelle))
            faelle.append((befehl, roh[:n]))
            if befehl == "beacon":
                strukturell.append(len(faelle))
                faelle.append(("ies", roh[:n]))

    # 2. Jedes einzelne Oktett auf jeden der vier "interessanten" Werte.
    #    0x00 und 0xFF sind die Extreme jedes Laengenfeldes, 0x80 die
    #    Vorzeichengrenze, und ein zufaelliger Wert deckt den Rest ab.
    anzahl = 1 if SCHNELL else 4
    for befehl, roh in quellen:
        for i in range(len(roh)):
            for wert in ([0xFF] if SCHNELL
                         else [0x00, 0xFF, 0x80, r.randrange(256)]):
                v = bytearray(roh)
                v[i] = wert
                faelle.append((befehl, bytes(v)))

    # 3. Gezielt die Laengenfelder der Elementkette: JEDES Element
    #    bekommt der Reihe nach eine gelogene Laenge. Das ist der
    #    Angriff, den ein Mensch bauen wuerde.
    for befehl, roh in quellen:
        if befehl != "beacon":
            continue
        at = 36
        while at + 2 <= len(roh):
            for wert in (0xFF, 0xFE, 0x80, len(roh), 0x00):
                v = bytearray(roh)
                v[at + 1] = wert & 255
                strukturell.append(len(faelle))
                faelle.append(("beacon", bytes(v)))
                strukturell.append(len(faelle))
                faelle.append(("ies", bytes(v)))
            at += 2 + roh[at + 1]

    # 4. Reiner Unsinn: zufaellige Oktettfolgen jeder Laenge von 0 bis
    #    300. Nichts davon ist ein gueltiger Rahmen, und nichts davon
    #    darf etwas anderes tun als FAIL zu sagen oder eine
    #    wohlgeformte Zeile zu liefern.
    wie_oft = 2 if SCHNELL else 12
    for n in range(0, 300, 1 if not SCHNELL else 7):
        for _ in range(wie_oft):
            roh = bytes(r.randrange(256) for _ in range(n))
            strukturell.append(len(faelle))
            faelle.append((r.choice(["beacon", "ies", "eapol", "ccmpdec"]),
                           roh))

    # 5. Rahmen, deren KOPF sich selbst widerspricht: alle 16
    #    Kombinationen von ToDS, FromDS, QoS und Ordnungsbit auf einem
    #    zu kurzen Rahmen. Genau hier entscheidet sich die Kopflaenge,
    #    und genau hier greift ein Zerleger daneben, der sie aus dem
    #    Rahmen glaubt statt sie zu pruefen.
    grund = bytearray(bytes.fromhex(lies_mitschnitt()["daten"][0]))
    for bits in range(16):
        fc = 0x0008  # Datenrahmen
        if bits & 1:
            fc |= 0x0100  # ToDS
        if bits & 2:
            fc |= 0x0200  # FromDS
        if bits & 4:
            fc |= 0x0080  # QoS-Untertyp
        if bits & 8:
            fc |= 0x8000  # Ordnung
        for n in (0, 1, 2, 10, 23, 24, 25, 26, 29, 30, 31, 35, 36, 40):
            v = bytearray(grund[:n])
            if len(v) >= 2:
                v[0] = fc & 255
                v[1] = (fc >> 8) & 255
            strukturell.append(len(faelle))
            faelle.append(("ccmpdec", bytes(v)))
    return faelle, strukturell


TK = "15798d511beae0028313c8ab32f12c7e"


def zeile_fuer(befehl, roh):
    if befehl == "ccmpdec":
        return "ccmpdec %s %s" % (TK, roh.hex() if roh else "-")
    return "%s %s" % (befehl, roh.hex() if roh else "-")


def wohlgeformt(befehl, antwort):
    if antwort == "FAIL":
        return True
    if befehl == "ies":
        for teil in antwort.split(" "):
            if teil in ("KAPUTT", "LEER"):
                continue
            if ":" not in teil:
                return False
            a, b = teil.split(":", 1)
            if not a.isdigit() or not b.isdigit():
                return False
        return True
    if befehl in ("beacon", "eapol"):
        for teil in antwort.split(" "):
            if "=" not in teil:
                return False
        return True
    if befehl == "ccmpdec":
        if len(antwort) % 2 != 0:
            return False
        try:
            bytes.fromhex(antwort)
        except ValueError:
            return False
        return True
    return False


def main():
    if not os.path.exists(ORAKEL):
        print("  FAIL  %s gibt es nicht" % ORAKEL)
        return 1
    faelle, strukturell = baue_faelle()
    print("== der Fuzz-Lauf: %d verstuemmelte Rahmen ==" % len(faelle))
    zeilen = [zeile_fuer(b, r) for b, r in faelle]
    eingabe = ("\n".join(zeilen) + "\n").encode()

    p = subprocess.run([ORAKEL], input=eingabe, stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, timeout=1800)
    if p.returncode != 0:
        bad("das Orakel ist bei %d Faellen mit Code %d ausgestiegen"
            % (len(faelle), p.returncode))
        return 1
    ok("%d verstuemmelte Rahmen: das Orakel laeuft durch, Beendigungscode 0"
       % len(faelle))

    aus = p.stdout.decode(errors="replace").split("\n")
    while aus and aus[-1] == "":
        aus.pop()
    # Eine leere Eingabezeile erzeugt keine Antwort: der Fall mit der
    # Laenge 0 heisst `-` und ist eine Zeile, also muss die Zahl stimmen.
    if len(aus) == len(zeilen):
        ok("genau eine Antwortzeile je Frage: %d von %d" % (len(aus), len(zeilen)))
    else:
        bad("%d Antworten auf %d Fragen" % (len(aus), len(zeilen)))
        return 1

    schlecht = [(faelle[i][0], zeilen[i][:70], aus[i][:70])
                for i in range(len(aus))
                if not wohlgeformt(faelle[i][0], aus[i])]
    if not schlecht:
        ok("jede der %d Antworten ist entweder FAIL oder eine wohlgeformte "
           "Zeile -- keine halbe Ausgabe, kein Muell" % len(aus))
    else:
        for b, f, a in schlecht[:5]:
            bad("%s: '%s' -> '%s'" % (b, f, a))

    # DIE EINE INHALTLICHE ZUSAGE: kein verstuemmelter Beacon dieses
    # Netzes darf als OFFEN gemeldet werden. Das Netz ist WPA2; wer aus
    # einem kaputten Rahmen "offen" macht, baut aus einem
    # Uebertragungsfehler eine unverschluesselte Verbindung.
    offen = 0
    fuer_beacons = 0
    for i, (befehl, roh) in enumerate(faelle):
        if befehl != "beacon" or aus[i] == "FAIL":
            continue
        fuer_beacons += 1
        f = dict(x.split("=", 1) for x in aus[i].split(" ") if "=" in x)
        if f.get("sich") == "0" and f.get("ssid") == b"Coherer".hex():
            offen += 1
    if offen == 0:
        ok("von den %d verstuemmelten Beacons, die ueberhaupt durchgehen, "
           "meldet KEINER das Netz 'Coherer' als offen" % fuer_beacons)
    else:
        bad("%d verstuemmelte Beacons melden 'Coherer' als OFFENES Netz"
            % offen)

    # UND JETZT DER TEIL, DER OHNE WERKZEUG NICHT GEHT: greift
    # irgendetwas davon neben den Puffer? valgrind sieht jeden
    # Lesezugriff auf nicht zugewiesenen Speicher. Ohne diesen Lauf
    # waere "kein Zugriff daneben" eine Behauptung.
    if SCHNELL:
        print("  --    valgrind uebersprungen (--schnell)")
    else:
        # WARUM NICHT ALLE FAELLE UNTER VALGRIND, und was das kostet:
        # valgrind ist hier ungefaehr fuenfzigmal langsamer, und der
        # volle Satz braucht ohne ihn schon elf Sekunden -- vor allem,
        # weil `ccmpdec` auf einem 400-Oktett-Rahmen fuenfzig
        # AES-Bloecke rechnet und dieses AES bewusst ohne die grossen
        # Tabellen auskommt (lib/crypto/aes.fi). Zehn Minuten in jeder
        # Abnahme waeren der sichere Weg dazu, dass jemand den
        # Abschnitt abschaltet.
        #
        # Unter valgrind laufen deshalb ALLE STRUKTURELLEN Faelle: jede
        # Kuerzung jedes Rahmens, jedes gelogene Laengenfeld, jeder
        # widerspruechliche Kopf, jede zufaellige Oktettfolge. Genau
        # dort sitzt eine Laengenrechnung, und nur eine Laengenrechnung
        # kann daneben greifen. Ausgelassen werden die Faelle, in denen
        # ein Oktett MITTEN im Rahmen einen anderen Wert hat -- die
        # aendern kein Zugriffsmuster, nur ein Ergebnis, und das pruefen
        # die Zeilen darueber.
        #
        # Mit WLAN_VALGRIND=alle laeuft trotzdem der ganze Satz.
        if os.environ.get("WLAN_VALGRIND") == "alle":
            teil = list(range(len(faelle)))
            was = "alle %d" % len(teil)
        else:
            teil = sorted(set(strukturell))
            was = "die %d strukturellen von %d" % (len(teil), len(faelle))
        vein = ("\n".join(zeilen[i] for i in teil) + "\n").encode()
        try:
            v = subprocess.run(
                ["valgrind", "--error-exitcode=42",
                 "--errors-for-leak-kinds=none",
                 "--leak-check=no", "-q", ORAKEL],
                input=vein, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                timeout=3600)
        except FileNotFoundError:
            print("  --    valgrind ist nicht da -- der Lauf ist damit "
                  "UNVOLLSTAENDIG")
            v = None
        if v is not None:
            meldungen = v.stderr.decode(errors="replace").strip()
            if v.returncode == 0 and not meldungen:
                ok("valgrind ueber %s verstuemmelten Rahmen: NULL "
                   "ungueltige Zugriffe, NULL Lesevorgaenge auf "
                   "uninitialisiertem Speicher" % was)
            else:
                bad("valgrind meldet etwas (Code %d):\n%s"
                    % (v.returncode, meldungen[:2000]))

    print()
    print("WLAN-FUZZ: %d Zusagen, %d Fehler" % (pass_n, fail_n))
    return 1 if fail_n else 0


if __name__ == "__main__":
    sys.exit(main())
