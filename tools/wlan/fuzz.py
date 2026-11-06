#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import random
import subprocess
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(os.path.dirname(HIER))
ORAKEL = os.path.join(REPO_ROOT, ".probe", "worakel")
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


def read_capture():
    payload = {}
    entries = {}
    with open(MITSCHNITT, encoding="utf-8") as f:
        for z in f:
            z = z.strip()
            if not z or z.startswith("#"):
                continue
            k, _, v = z.partition(" ")
            if k in ("beacon", "daten", "beacon_db"):
                entries.setdefault(k, []).append(v)
            else:
                payload[k] = v
    payload.update(entries)
    return payload


def build_cases():
    m = read_capture()
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

    for command, roh in quellen:
        for n in range(0, len(roh) + 1):
            strukturell.append(len(faelle))
            faelle.append((command, roh[:n]))
            if command == "beacon":
                strukturell.append(len(faelle))
                faelle.append(("ies", roh[:n]))

    total = 1 if QUICK else 4
    for command, roh in quellen:
        for i in range(len(roh)):
            for value in ([0xFF] if QUICK
                         else [0x00, 0xFF, 0x80, r.randrange(256)]):
                v = bytearray(roh)
                v[i] = value
                faelle.append((command, bytes(v)))

    for command, roh in quellen:
        if command != "beacon":
            continue
        at = 36
        while at + 2 <= len(roh):
            for value in (0xFF, 0xFE, 0x80, len(roh), 0x00):
                v = bytearray(roh)
                v[at + 1] = value & 255
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

    why = bytearray(bytes.fromhex(read_capture()["daten"][0]))
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
            v = bytearray(why[:n])
            if len(v) >= 2:
                v[0] = fc & 255
                v[1] = (fc >> 8) & 255
            strukturell.append(len(faelle))
            faelle.append(("ccmpdec", bytes(v)))
    return faelle, strukturell


TK = "15798d511beae0028313c8ab32f12c7e"


def row_for(command, roh):
    if command == "ccmpdec":
        return "ccmpdec %s %s" % (TK, roh.hex() if roh else "-")
    return "%s %s" % (command, roh.hex() if roh else "-")


def wohlgeformt(command, response):
    if response == "FAIL":
        return True
    if command == "ies":
        for part in response.split(" "):
            if part in ("BROKEN", "EMPTY"):
                continue
            if ":" not in part:
                return False
            a, b = part.split(":", 1)
            if not a.isdigit() or not b.isdigit():
                return False
        return True
    if command in ("beacon", "eapol"):
        for part in response.split(" "):
            if "=" not in part:
                return False
        return True
    if command == "ccmpdec":
        if len(response) % 2 != 0:
            return False
        try:
            bytes.fromhex(response)
        except ValueError:
            return False
        return True
    return False


def main():
    if not os.path.exists(ORAKEL):
        print("  FAIL  %s does not exist" % ORAKEL)
        return 1
    faelle, strukturell = build_cases()
    print("== the fuzz run: %d mutilated frames ==" % len(faelle))
    rows = [row_for(b, r) for b, r in faelle]
    input_text = ("\n".join(rows) + "\n").encode()

    p = subprocess.run([ORAKEL], input=input_text, stdout=subprocess.PIPE,
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
    if len(aus) == len(rows):
        ok("exactly one answer line per question: %d of %d" % (len(aus), len(rows)))
    else:
        bad("%d answers to %d questions" % (len(aus), len(rows)))
        return 1

    defective = [(faelle[i][0], rows[i][:70], aus[i][:70])
                for i in range(len(aus))
                if not wohlgeformt(faelle[i][0], aus[i])]
    if not defective:
        ok("each of the %d answers is either FAIL or a well-formed "
           "line -- no partial output, no garbage" % len(aus))
    else:
        for b, f, a in defective[:5]:
            bad("%s: '%s' -> '%s'" % (b, f, a))

    # Uebertragungsfehler eine unverschluesselte Verbindung.
    is_open = 0
    for_beacons = 0
    for i, (command, roh) in enumerate(faelle):
        if command != "beacon" or aus[i] == "FAIL":
            continue
        for_beacons += 1
        f = dict(x.split("=", 1) for x in aus[i].split(" ") if "=" in x)
        if f.get("sich") == "0" and f.get("ssid") == b"Coherer".hex():
            is_open += 1
    if is_open == 0:
        ok("of the %d mutilated beacons that get through at all, "
           "NONE reports the network 'Coherer' as open" % for_beacons)
    else:
        bad("%d mutilated beacons report 'Coherer' as an OPEN network"
            % is_open)

    if QUICK:
        print("  --    valgrind uebersprungen (--quick)")
    else:
        # Tabellen auskommt (lib/crypto/aes.fi). Zehn Minuten in jeder
        # Abschnitt abschaltet.
        #
        #
        if os.environ.get("WLAN_VALGRIND") == "alle":
            part = list(range(len(faelle)))
            was = "alle %d" % len(part)
        else:
            part = sorted(set(strukturell))
            was = "the %d structural of %d" % (len(part), len(faelle))
        vein = ("\n".join(rows[i] for i in part) + "\n").encode()
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
