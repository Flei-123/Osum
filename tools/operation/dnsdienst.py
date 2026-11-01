#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/operation/dnsdienst.py -- DIE GEGENSTELLE FUER DEN AUFLOESER.

    dnsdienst.py --port 53 [--adresse 0.0.0.0]
                 --eintrag pkg.betrieb.test=10.0.2.2 [--eintrag ...]
                 [--boese txid|port|case|alle|klein] [--koeder 3]
                 [--log datei] [--tc pkg.betrieb.test]

Zwei Aufgaben in einem Programm, und die zweite ist die wichtigere.

1. EIN AUTORITATIVER NAMENSDIENST fuer ein paar erfundene Namen. Das
   Geraet in QEMU braucht einen Nameserver, der `pkg.betrieb.test`
   kennt; das echte DNS kennt ihn nicht, und einen Namen zu mieten, um
   einen Aufloeser zu messen, waere Unsinn.

2. EIN FAELSCHER. Mit `--boese` schickt dieser Dienst VOR der richtigen
   Antwort `--koeder` falsche: mit falscher Kennung, von einem falschen
   Quellport, oder mit veraenderter Gross-/Kleinschreibung in der
   zurueckgesendeten Frage. Jede davon ist genau das, was ein Angreifer
   erraten muesste. Ein Aufloeser, der eine davon annimmt, ist
   vergiftbar; einer, der beim ersten Fremdpaket aufgibt, ist es auch
   (dann genuegt einem Angreifer, SCHNELL zu sein statt richtig).

   Gemessen wird deshalb ZWEIERLEI: dass die richtige Adresse
   herauskommt, UND dass `host -v` die Koeder als `fremd` gezaehlt hat.
   Ohne die zweite Zahl waere der erste Haken auch dann gruen, wenn gar
   kein Koeder angekommen waere.

Das Format wird hier von Hand gebaut -- absichtlich, denn ein
Bibliotheks-DNS koennte die Faelschungen gar nicht erzeugen.
"""
import os
import random
import socket
import struct
import sys
import threading
import time

EINTRAEGE = {}
BOESE = None
KOEDER = 3
LOG = None
TC = set()
COUNTER = {"fragen": 0, "koeder": 0, "antworten": 0}


def protokoll(*w):
    z = " ".join(str(x) for x in w)
    if LOG:
        with open(LOG, "a") as f:
            f.write(z + "\n")
    else:
        sys.stderr.write(z + "\n")
        sys.stderr.flush()


def name_read(b, at):
    parts = []
    i = at
    spr = 0
    while True:
        if i >= len(b):
            return None, None
        c = b[i]
        if c == 0:
            i += 1
            break
        if c & 0xC0 == 0xC0:
            if spr > 4:
                return None, None
            target_2 = ((c & 0x3F) << 8) | b[i + 1]
            if spr == 0:
                ende = i + 2
            i = target_2
            spr += 1
            continue
        parts.append(b[i + 1:i + 1 + c])
        i += 1 + c
    if spr:
        return b".".join(parts), ende
    return b".".join(parts), i


def reply_build(ask, txid, qende, name, qtyp, broken_case=False,
                  txid_wrong=False, tc=False, small=False):
    q = bytearray(ask[:qende])
    if small:
        for i in range(12, qende):
            if 65 <= q[i] <= 90:
                q[i] += 32
    if broken_case:
        for i in range(12, qende):
            c = q[i]
            if 65 <= c <= 90 or 97 <= c <= 122:
                q[i] = c ^ 0x20
    header_id = (txid ^ 0x5A5A) & 0xFFFF if txid_wrong else txid
    ip = EINTRAEGE.get(name.decode("ascii", "replace").lower())
    fl = 0x8180
    if tc:
        fl |= 0x0200
    an = 0
    rd = b""
    if ip is None:
        fl = (fl & ~0x000F) | 3
    elif qtyp == 1 and not tc:
        an = 1
        rd = (b"\xc0\x0c" + struct.pack(">HHIH", 1, 1, 60, 4)
              + socket.inet_aton(ip))
    elif qtyp != 1:
        an = 0
    header = struct.pack(">HHHHHH", header_id, fl, 1, an, 0, 0)
    return bytes(header) + bytes(q[12:]) + rd


def bedienen(sock, daten, herkunft):
    if len(daten) < 12:
        return
    txid = struct.unpack(">H", daten[0:2])[0]
    name, ende = name_read(daten, 12)
    if name is None or ende + 4 > len(daten):
        return
    qtyp = struct.unpack(">H", daten[ende:ende + 2])[0]
    qende = ende + 4
    COUNTER["fragen"] += 1
    kn = name.decode("ascii", "replace").lower()
    protokoll("FRAGE", kn, "typ", qtyp, "txid", txid, "von", herkunft)

    if BOESE and BOESE != "klein":
        for i in range(KOEDER):
            art = BOESE
            if BOESE == "alle":
                art = ["txid", "port", "case"][i % 3]
            if art == "txid":
                p = reply_build(daten, txid, qende, name, qtyp,
                                  txid_wrong=True)
                sock.sendto(p, herkunft)
            elif art == "case":
                p = reply_build(daten, txid, qende, name, qtyp,
                                  broken_case=True)
                sock.sendto(p, herkunft)
            elif art == "port":
                wrong = dict(EINTRAEGE)
                echt = EINTRAEGE.get(kn)
                if echt:
                    EINTRAEGE[kn] = "6.6.6.6"
                p = reply_build(daten, txid, qende, name, qtyp)
                EINTRAEGE.update(wrong)
                s2 = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                s2.bind(("", 0))
                s2.sendto(p, herkunft)
                s2.close()
            COUNTER["koeder"] += 1
        time.sleep(0.01)

    p = reply_build(daten, txid, qende, name, qtyp, tc=(kn in TC),
                      small=(BOESE == "klein"))
    sock.sendto(p, herkunft)
    COUNTER["antworten"] += 1


def main():
    global BOESE, KOEDER, LOG
    port = 53
    adr = "0.0.0.0"
    pid = None
    i = 1
    while i < len(sys.argv):
        a = sys.argv[i]
        if a == "--port":
            i += 1
            port = int(sys.argv[i])
        elif a == "--adresse":
            i += 1
            adr = sys.argv[i]
        elif a == "--eintrag":
            i += 1
            k, _, v = sys.argv[i].partition("=")
            EINTRAEGE[k.lower()] = v
        elif a == "--boese":
            i += 1
            BOESE = sys.argv[i]
        elif a == "--koeder":
            i += 1
            KOEDER = int(sys.argv[i])
        elif a == "--log":
            i += 1
            LOG = sys.argv[i]
        elif a == "--pid":
            i += 1
            pid = sys.argv[i]
        elif a == "--tc":
            i += 1
            TC.add(sys.argv[i].lower())
        else:
            print(__doc__)
            return 2
        i += 1
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((adr, port))
    if pid:
        with open(pid, "w") as f:
            f.write(str(os.getpid()))
    protokoll("START port=%d eintraege=%d boese=%s koeder=%d"
              % (port, len(EINTRAEGE), BOESE, KOEDER))
    try:
        while True:
            d, h = s.recvfrom(4096)
            threading.Thread(target=bedienen, args=(s, d, h),
                             daemon=True).start()
    except KeyboardInterrupt:
        pass
    protokoll("ENDE %s" % COUNTER)
    return 0


if __name__ == "__main__":
    sys.exit(main())
