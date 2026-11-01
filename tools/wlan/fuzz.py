#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import random
import subprocess
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
WURZEL = os.path.dirname(os.path.dirname(HIER))
ORAKEL = os.path.join(WURZEL, ".probe", "worakel")
MITSCHNITT = os.path.join(HIER, "mitschnitt.txt")

QUICK = ("--quick" in sys.argv or "--schnell" in sys.argv)
SAAT = 20260830

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
    strukturell = []

    for befehl, roh in quellen:
        for n in range(0, len(roh) + 1):
            strukturell.append(len(faelle))
            faelle.append((befehl, roh[:n]))
            if befehl == "beacon":
                strukturell.append(len(faelle))
                faelle.append(("ies", roh[:n]))

    anzahl = 1 if QUICK else 4
    for befehl, roh in quellen:
        for i in range(len(roh)):
            for wert in ([0xFF] if QUICK
                         else [0x00, 0xFF, 0x80, r.randrange(256)]):
                v = bytearray(roh)
                v[i] = wert
                faelle.append((befehl, bytes(v)))

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

    wie_oft = 2 if QUICK else 12
    for n in range(0, 300, 1 if not QUICK else 7):
        for _ in range(wie_oft):
            roh = bytes(r.randrange(256) for _ in range(n))
            strukturell.append(len(faelle))
            faelle.append((r.choice(["beacon", "ies", "eapol", "ccmpdec"]),
                           roh))

    grund = bytearray(bytes.fromhex(lies_mitschnitt()["daten"][0]))
    for bits in range(16):
        fc = 0x0008  # data frame
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
        print("  FAIL  %s does not exist" % ORAKEL)
        return 1
    faelle, strukturell = baue_faelle()
    print("== the fuzz run: %d mutilated frames ==" % len(faelle))
    zeilen = [zeile_fuer(b, r) for b, r in faelle]
    eingabe = ("\n".join(zeilen) + "\n").encode()

    p = subprocess.run([ORAKEL], input=eingabe, stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, timeout=1800)
    if p.returncode != 0:
        bad("the oracle exited on %d cases with code %d"
            % (len(faelle), p.returncode))
        return 1
    ok("%d mutilated frames: the oracle runs through, exit code 0"
       % len(faelle))

    aus = p.stdout.decode(errors="replace").split("\n")
    while aus and aus[-1] == "":
        aus.pop()
    if len(aus) == len(zeilen):
        ok("exactly one answer line per question: %d of %d" % (len(aus), len(zeilen)))
    else:
        bad("%d answers to %d questions" % (len(aus), len(zeilen)))
        return 1

    schlecht = [(faelle[i][0], zeilen[i][:70], aus[i][:70])
                for i in range(len(aus))
                if not wohlgeformt(faelle[i][0], aus[i])]
    if not schlecht:
        ok("each of the %d answers is either FAIL or a well-formed "
           "line -- no partial output, no garbage" % len(aus))
    else:
        for b, f, a in schlecht[:5]:
            bad("%s: '%s' -> '%s'" % (b, f, a))

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
        ok("of the %d mutilated beacons that get through at all, "
           "NONE reports the network 'Coherer' as open" % fuer_beacons)
    else:
        bad("%d mutilated beacons report 'Coherer' as an OPEN network"
            % offen)

    if QUICK:
        print("  --    valgrind uebersprungen (--quick)")
    else:
        # Tabellen auskommt (lib/crypto/aes.fi). Zehn Minuten in jeder
        # Abschnitt abschaltet.
        #
        #
        if os.environ.get("WLAN_VALGRIND") == "alle":
            teil = list(range(len(faelle)))
            was = "alle %d" % len(teil)
        else:
            teil = sorted(set(strukturell))
            was = "the %d structural of %d" % (len(teil), len(faelle))
        vein = ("\n".join(zeilen[i] for i in teil) + "\n").encode()
        try:
            v = subprocess.run(
                ["valgrind", "--error-exitcode=42",
                 "--errors-for-leak-kinds=none",
                 "--leak-check=no", "-q", ORAKEL],
                input=vein, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                timeout=3600)
        except FileNotFoundError:
            print("  --    valgrind is not there -- the run is thus "
                  "UNVOLLSTAENDIG")
            v = None
        if v is not None:
            meldungen = v.stderr.decode(errors="replace").strip()
            if v.returncode == 0 and not meldungen:
                ok("valgrind over %s mutilated frames: ZERO "
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
