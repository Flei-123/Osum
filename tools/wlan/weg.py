#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/wlan/weg.py -- der ganze Weg, und was passiert, wenn jemand
unterwegs luegt.

======================================================================
WARUM ES DIESE DATEI GIBT: T4 AUS docs/WLAN.md
======================================================================

`docs/WLAN.md` Abschnitt 7 sagt ueber diese Runde selbst:

    T4 -- `verbinden.fi` ist gegen keinen boesartigen Verlauf
    gemessen. Der Handschlag ist es, der Automat darunter ist es
    erschoepfend, aber der Draht dazwischen -- die Datei, die beides
    verbindet -- hat nur den glaeubigen Weg gesehen.

Genau dort sitzen aber die drei Fehler, die `verbinden.fi` ueberhaupt
zu verhindern versucht:

  * ein Beacon wird ausgewertet, aber die Sicherheitsart nicht
    geprueft, und der Rechner haengt sich an ein offenes Netz;
  * der Handschlag gelingt, aber der Schluessel geht nicht ins Geraet,
    und danach fliegt alles im Klartext;
  * es wird ein Schluessel installiert, obwohl der Handschlag nie
    fertig wurde.

Diese Datei prueft jeden davon, indem sie luegt.

DIE ZAHL, AUF DIE ES ANKOMMT, ist `skeys` -- wie viele Schluessel
wirklich im GERAET liegen. Nicht, was ein Merker sagt, sondern was
unten angekommen ist. In jedem boesen Fall muss sie NULL sein.
"""

import binascii
import os
import subprocess
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HIER)

from gegenstelle import (Authenticator, eapol_bauen, eapol_mic_setzen,
                         eapol_zerlegen, gtk_kde, aes_wrap, pmk_aus_psk,
                         ptk_ableiten, h, u, MIC_VERSATZ)

ORAKEL = os.environ.get('ORAKEL', os.path.join(HIER, '..', '..',
                                               '.probe', 'worakel'))
gut = 0
schlecht = 0


def ok(t):
    global gut
    gut += 1
    print("  OK    %s" % t)


def bad(t):
    global schlecht
    schlecht += 1
    print("  FAIL  %s" % t)


def orakel(zeile):
    p = subprocess.run([ORAKEL], input=(zeile + "\n").encode(),
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return p.stdout.decode().strip()


def felder(antwort):
    d = {}
    for teil in antwort.split():
        if '=' in teil:
            k, v = teil.split('=', 1)
            d[k] = v
    return d


# ---------------------------------------------------------------------
# Ein Beacon bauen. Die Sicherheitsart steckt im RSN-Element, und genau
# damit wird gleich gelogen.
# ---------------------------------------------------------------------

def beacon_bauen(ssid, kanal=6, rsn=True, bssid=b'\x02\x00\x00\x00\x00\x00'):
    fc = b'\x80\x00'
    dauer = b'\x00\x00'
    ziel = b'\xff\xff\xff\xff\xff\xff'
    kopf = fc + dauer + ziel + bssid + bssid + b'\x00\x00'
    fest = b'\x00' * 8 + b'\x64\x00' + b'\x11\x04'
    ies = bytes([0, len(ssid)]) + ssid
    ies += bytes([1, 8]) + b'\x82\x84\x8b\x96\x24\x30\x48\x6c'
    ies += bytes([3, 1, kanal])
    if rsn:
        # RSN: CCMP als Paar- und Gruppenchiffre, AKM PSK
        ies += u('30140100000fac040100000fac040100000fac020000')
    return kopf + fest + ies


def handschlag_bauen(pmk, aa, spa, snonce, gtk=b'\x11' * 16,
                     kaputt=None):
    """Baut Nachricht 1 und 3 so, wie ein Zugangspunkt sie schickt."""
    anonce = b'\x33' * 32
    ptk = ptk_ableiten(pmk, aa, spa, anonce, snonce)
    kck, kek = ptk[0:16], ptk[16:32]
    m1 = eapol_bauen(0x008A, 16, 1, anonce, 0, b'')
    kd = u('30140100000fac040100000fac040100000fac020000') + gtk_kde(gtk, 1)
    while len(kd) % 8:
        kd += b'\xdd'
    verpackt = aes_wrap(kek, kd)
    m3 = eapol_bauen(0x13CA, 16, 2, anonce, 0, verpackt)
    if kaputt == 'mic':
        # MIC bleibt null -- ein Fremder, der den Schluessel nicht hat
        pass
    else:
        m3, _ = eapol_mic_setzen(m3, kck, False)
    return m1, m3, ptk, gtk


def main():
    if not os.path.exists(ORAKEL):
        print("kein Orakel unter %s" % ORAKEL)
        return 2

    ssid = b'OsumNetz'
    pw = b'einpasswort123'
    pmk = pmk_aus_psk(pw, ssid)
    aa = b'\x02\x00\x00\x00\x00\x00'
    spa = b'\x02\x00\x00\x00\x01\x00'
    snonce = b'\x44' * 32

    print("== der glaeubige Weg: er MUSS ganz durchgehen ==")
    m1, m3, ptk, gtk = handschlag_bauen(pmk, aa, spa, snonce)
    bk = beacon_bauen(ssid, rsn=True)
    a = felder(orakel("weg %s %s %s %s %s %s %s"
                      % (h(bk), h(pmk), h(spa), h(aa), h(m1),
                         h(snonce), h(m3))))
    if a.get('netze') == '1' and a.get('wahl') == '1' \
            and a.get('m1') == '1' and a.get('m3') == '1' \
            and a.get('daten') == '1' and a.get('skeys') == '2':
        ok("Suchlauf findet das Netz, Wahl geht, Nachricht 1 und 3 gehen, "
           "und danach liegen GENAU ZWEI Schluessel im Geraet (PTK und GTK)")
    else:
        bad("der glaeubige Weg geht nicht durch: %s" % a)

    print("== und jetzt wird gelogen (T4) ==")

    # --- 1. Ein OFFENES Netz. Es darf gar nicht erst gewaehlt werden.
    bo = beacon_bauen(ssid, rsn=False)
    a = felder(orakel("weg %s %s %s %s %s %s %s"
                      % (h(bo), h(pmk), h(spa), h(aa), h(m1),
                         h(snonce), h(m3))))
    if a.get('netze') == '1' and a.get('wahl') == '0' \
            and a.get('skeys') == '0':
        ok("ein OFFENES Netz wird gefunden und BENANNT, aber nicht "
           "gewaehlt -- und kein Schluessel geht ins Geraet")
    else:
        bad("ein offenes Netz kommt zu weit: %s" % a)

    # --- 2. Nachricht 3 mit falschem Pruefwert. Ein Fremder.
    m1b, m3b, _, _ = handschlag_bauen(pmk, aa, spa, snonce, kaputt='mic')
    a = felder(orakel("weg %s %s %s %s %s %s %s"
                      % (h(bk), h(pmk), h(spa), h(aa), h(m1b),
                         h(snonce), h(m3b))))
    if a.get('m1') == '1' and a.get('m3') == '0' \
            and a.get('daten') == '0' and a.get('skeys') == '0':
        ok("Nachricht 3 mit falschem Pruefwert: kein Schluessel im Geraet, "
           "keine Daten erlaubt")
    else:
        bad("eine Nachricht 3 mit falschem MIC kommt zu weit: %s" % a)

    # --- 3. Der falsche PMK (also das falsche Passwort).
    falsch = pmk_aus_psk(b'daspasswortistfalsch', ssid)
    a = felder(orakel("weg %s %s %s %s %s %s %s"
                      % (h(bk), h(falsch), h(spa), h(aa), h(m1),
                         h(snonce), h(m3))))
    if a.get('m3') == '0' and a.get('daten') == '0' \
            and a.get('skeys') == '0':
        ok("das falsche Passwort: der Handschlag scheitert an Nachricht 3, "
           "kein Schluessel im Geraet")
    else:
        bad("ein falsches Passwort fuehrt trotzdem zu einem Schluessel: %s" % a)

    # --- 4. Gar keine Nachricht 3.
    a = felder(orakel("weg %s %s %s %s %s %s -"
                      % (h(bk), h(pmk), h(spa), h(aa), h(m1), h(snonce))))
    if a.get('m1') == '1' and a.get('m3') == '0' \
            and a.get('daten') == '0' and a.get('skeys') == '0':
        ok("Handschlag bricht nach Nachricht 1 ab: kein Schluessel, "
           "keine Daten -- eine halbe Verbindung gibt es nicht")
    else:
        bad("ein abgebrochener Handschlag hinterlaesst etwas: %s" % a)

    # --- 5. Ein Beacon, das gar keines ist (ein Datenrahmen).
    kein = u('08413a01') + aa + spa + aa + u('0000') + b'\xaa' * 20
    a = felder(orakel("weg %s %s %s %s %s %s %s"
                      % (h(kein), h(pmk), h(spa), h(aa), h(m1),
                         h(snonce), h(m3))))
    if a.get('netze') == '0' and a.get('wahl') == '0' \
            and a.get('skeys') == '0':
        ok("ein Datenrahmen als Beacon: kein Netz in der Liste, keine Wahl")
    else:
        bad("ein Datenrahmen wird als Netz aufgenommen: %s" % a)

    # --- 6. Ein abgeschnittenes Beacon.
    for schnitt in (10, 20, 30, 40):
        a = felder(orakel("weg %s %s %s %s %s %s %s"
                          % (h(bk[:schnitt]), h(pmk), h(spa), h(aa),
                             h(m1), h(snonce), h(m3))))
        if a.get('skeys', 'x') != '0':
            bad("ein auf %d Oktette gekuerztes Beacon fuehrt zu einem "
                "Schluessel: %s" % (schnitt, a))
            break
    else:
        ok("Beacons auf 10, 20, 30 und 40 Oktette gekuerzt: keines fuehrt "
           "zu einem Schluessel im Geraet")

    print()
    print("WEG: %d Zusagen, %d Fehler" % (gut, schlecht))
    return 1 if schlecht else 0


if __name__ == '__main__':
    sys.exit(main())
