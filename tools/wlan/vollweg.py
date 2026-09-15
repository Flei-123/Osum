#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/wlan/vollweg.py -- DER GANZE WEG, UND WO ER ABBRICHT.

======================================================================
WAS DIESE DATEI MISST UND WARUM SIE GEBRAUCHT WURDE
======================================================================

`tools/wlan/weg.py` (Runde WLAN-2) misst den Weg bis zu dem Punkt, an
dem die Schluessel im Geraet liegen. Das ist die Haelfte der Frage.
Die andere Haelfte ist die, die ein Mensch meint, wenn er sagt "der
Rechner ist im WLAN":

  * Geht ein VERSCHLUESSELTES Datenpaket hinaus -- und ist es wirklich
    verschluesselt, also mit gesetztem Geschuetzt-Bit?
  * Kommt eines ZURUECK, das sich mit demselben Schluessel oeffnen
    laesst?
  * Bekommt der Rechner eine ADRESSE (DHCP)?
  * Kommt auf eine Anfrage eine ANTWORT (HTTP)?

Erst wenn das durchlaeuft, ist alles ausser dem Treiber bewiesen.

======================================================================
WAS DIESE DATEI AUSDRUECKLICH NICHT BEHAUPTET
======================================================================

**Sie behauptet NICHT, dass Osum sich mit einem WLAN verbindet.** Die
Gegenseite ist `tools/wlan/gegenstelle.py` und nicht die Luft; das
Geraet ist `lib/wlan/testdevice.fi` und keine Karte.
`docs/RUNDE-WLAN3.md` Abschnitt 1 rechnet vor, dass es auf diesem
Rechner keine Karte gibt und keine geben kann.

Was sie behauptet, ist genau das hier: **alles oberhalb der Naht ist
gemessen.** Am Tag, an dem eine Karte kommt, ist die offene Frage nur
noch der Treiber -- und nicht zusaetzlich die Frage, ob der Rest
zusammenpasst.

======================================================================
DIE GEGENPROBEN SIND DER EIGENTLICHE INHALT
======================================================================

Eine Abnahme, die immer gruen ist, misst nichts. Deshalb ist der
groessere Teil dieser Datei damit beschaeftigt, den Weg ABSICHTLICH
kaputtzumachen und nachzusehen, dass er dann WIRKLICH abbricht -- und
zwar sauber, ohne Absturz und ohne dass ein Schluessel oder ein
Datenpaket durchkommt.

Die Zahl, auf die es dabei ankommt, ist wie in `weg.py` `skeys`: wie
viele Schluessel wirklich im GERAET liegen. Nicht, was ein Merker
sagt.
"""

import os
import subprocess
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HIER)

from gegenstelle import (Zugangspunkt, eapol_bauen, eapol_mic_setzen,
                         aes_wrap, gtk_kde, pmk_aus_psk, ptk_ableiten,
                         h, u, ip2i, MIC_VERSATZ)
from weg import beacon_bauen, handschlag_bauen

ORAKEL = os.environ.get('ORAKEL',
                        os.path.join(HIER, '..', '..', '.probe', 'worakel'))

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
# Der Aufbau. Er ist bei jedem Fall derselbe -- nur EINE Zutat wird
# jeweils gefaelscht, damit klar ist, woran es lag.
# ---------------------------------------------------------------------

SSID = b'OsumNetz'
PW = b'einpasswort123'
AA = b'\x02\x00\x00\x00\x00\x00'
SPA = b'\x02\x00\x00\x00\x01\x00'
SNONCE = b'\x44' * 32
XID = 0x12345678


def aufbau(pw=PW, gtk=b'\x11' * 16, kaputt=None):
    pmk = pmk_aus_psk(pw, SSID)
    m1, m3, ptk, g = handschlag_bauen(pmk, AA, SPA, SNONCE, gtk=gtk,
                                      kaputt=kaputt)
    return pmk, m1, m3, ptk


def zeile_bauen(beacon, pmk, m1, m3, ein, dhcp, http):
    def f(x):
        return h(x) if x else '-'
    return "vollweg %s %s %s %s %s %s %s %s %s %s" % (
        h(beacon), h(pmk), h(SPA), h(AA), f(m1), h(SNONCE), f(m3),
        f(ein), f(dhcp), f(http))


def lauf(pw=PW, beacon=None, kaputt=None, tk_falsch=False,
         ohne_m3=False, pn_wiederholt=False, http_kaputt=False,
         dhcp_fremd=False):
    """Einen ganzen Durchlauf fahren und die Felder zurueckgeben.

    `pw` ist das Passwort, das OSUM benutzt. Der ZUGANGSPUNKT benutzt
    immer das richtige (PW).

    DAS IST DER UNTERSCHIED, DER DIE GEGENPROBE ERST ZU EINER MACHT,
    und der erste Anlauf dieser Datei hat ihn nicht gemacht: dort
    wurde der ganze Handschlag AUS dem falschen Passwort gebaut --
    also rechneten beide Seiten mit demselben falschen PMK, waren sich
    einig, und der Weg lief zu Recht durch. Gemessen wurde damit
    nichts ausser der eigenen Rechenart.

    Ein falsches Passwort heisst: der Zugangspunkt bleibt bei seinem,
    und NUR Osum rechnet mit einem anderen. Genau dann muss der
    Pruefwert von Nachricht 3 durchfallen.
    """
    # Die Nachrichten des Zugangspunktes -- immer mit dem RICHTIGEN
    # Passwort gebaut.
    pmk_echt, m1, m3, ptk = aufbau(pw=PW, kaputt=kaputt)
    # Und das, womit Osum rechnet.
    pmk = pmk_aus_psk(pw, SSID)
    tk = ptk[32:48]
    if tk_falsch:
        tk = bytes((b ^ 0xFF) for b in tk)
    ap = Zugangspunkt(tk, AA, SPA)
    if beacon is None:
        beacon = beacon_bauen(SSID, rsn=True)
    ein = ap.echo()
    if pn_wiederholt:
        # Dieselbe Paketnummer ein zweites Mal -- der Zaehler wird
        # zurueckgedreht.
        ap.pn = 1
        ein = ap.echo()
    dh = ap.dhcp_antwort(XID)
    if dhcp_fremd:
        # Eine DHCP-Antwort, die mit einem FREMDEN Schluessel
        # verschluesselt ist -- also von jemandem, der den Handschlag
        # nicht gefuehrt hat.
        fremd = Zugangspunkt(bytes(16), AA, SPA)
        dh = fremd.dhcp_antwort(XID)
    ht = ap.http_antwort(status=b'200 OK')
    if http_kaputt:
        ht = ap.http_antwort(rumpf=b'x', status=b'500 Fehler')
    if ohne_m3:
        m3 = None
    return felder(orakel(zeile_bauen(beacon, pmk, m1, m3, ein, dh, ht)))


def main():
    if not os.path.exists(ORAKEL):
        print("kein Orakel unter %s" % ORAKEL)
        return 2

    # =================================================================
    print("== 1. DER GANZE WEG: er MUSS Schritt fuer Schritt durchgehen ==")
    # =================================================================
    a = lauf()

    if a.get('netze') == '1':
        ok("SCHRITT 1 -- Suchlauf: der Zugangspunkt wird gefunden "
           "(1 Netz in der Liste)")
    else:
        bad("Suchlauf findet den Zugangspunkt nicht: %s" % a)

    if a.get('wahl') == '1' and a.get('kanal') == '6':
        ok("SCHRITT 2 -- Netzwahl: das Netz wird gewaehlt und das Geraet "
           "auf Kanal 6 gestellt (der Kanal aus dem Beacon)")
    else:
        bad("Netzwahl oder Kanal falsch: %s" % a)

    if a.get('m1') == '1':
        ok("SCHRITT 3 -- Handschlag Nachricht 1: der PTK wird aus PMK, "
           "beiden Adressen und beiden Zufallszahlen abgeleitet")
    else:
        bad("Nachricht 1 geht nicht durch: %s" % a)

    if a.get('m3') == '1' and a.get('skeys') == '2':
        ok("SCHRITT 4 -- Handschlag Nachricht 3: Pruefwert stimmt, GTK "
           "ausgepackt, und GENAU ZWEI Schluessel liegen im Geraet "
           "(PTK und GTK)")
    else:
        bad("Nachricht 3 oder die Schluessel stimmen nicht: %s" % a)

    if a.get('darf') == '1':
        ok("SCHRITT 5 -- der Automat steht auf VERBUNDEN und erlaubt "
           "Daten (darf_daten)")
    else:
        bad("der Automat erlaubt keine Daten: %s" % a)

    if int(a.get('tx', '-1')) > 0 and a.get('gesch') == '1':
        ok("SCHRITT 6 -- ein Datenpaket geht HINAUS: %s Oktette, und das "
           "Geschuetzt-Bit ist gesetzt (es ist wirklich verschluesselt, "
           "nicht nur behauptet)" % a['tx'])
    else:
        bad("das Datenpaket geht nicht verschluesselt hinaus: %s" % a)

    if int(a.get('rx', '-1')) > 0 and a.get('et') == '2048':
        ok("SCHRITT 7 -- ein Datenpaket kommt HEREIN: %s Oktette, mit "
           "demselben Schluessel geoeffnet, LLC/SNAP sagt EtherType "
           "0x0800 (IPv4)" % a['rx'])
    else:
        bad("das hereinkommende Datenpaket geht nicht auf: %s" % a)

    if a.get('dart') == '5' and a.get('ip') == str(ip2i('192.168.0.50')):
        ok("SCHRITT 8 -- DHCP: die Antwort ist ein ACK (Art 5) und traegt "
           "die Adresse 192.168.0.50")
    else:
        bad("DHCP bringt keine Adresse: %s" % a)

    if a.get('maske') == str(ip2i('255.255.255.0')) \
            and a.get('tor') == str(ip2i('192.168.0.1')):
        ok("SCHRITT 8b -- DHCP: Maske 255.255.255.0 und Tor 192.168.0.1 "
           "kommen mit")
    else:
        bad("Maske oder Tor fehlen: %s" % a)

    if a.get('http') == '200' and int(a.get('rumpf', '-1')) > 0:
        ok("SCHRITT 9 -- HTTP: eine Anfrage wird mit 200 beantwortet, der "
           "Rumpf beginnt bei Oktett %s" % a['rumpf'])
    else:
        bad("HTTP kommt nicht an: %s" % a)

    if a.get('grund') == '0':
        ok("der ganze Weg laeuft OHNE einen einzigen Fehlergrund durch "
           "(grund=0)")
    else:
        bad("es bleibt ein Fehlergrund stehen: %s" % a)

    # =================================================================
    print()
    print("== 2. DIE GEGENPROBEN: hier MUSS der Weg abbrechen ==")
    # =================================================================

    # --- 1. Das falsche Passwort.
    a = lauf(pw=b'daspasswortistfalsch')
    if a.get('m3') == '0' and a.get('skeys') == '0' \
            and a.get('darf') == '0' and a.get('dhcp') == '0' \
            and a.get('http') == '0':
        ok("FALSCHES PASSWORT: der Handschlag scheitert an Nachricht 3, "
           "KEIN Schluessel im Geraet, kein Datenpaket, kein DHCP, "
           "kein HTTP")
    else:
        bad("ein falsches Passwort kommt zu weit: %s" % a)

    # --- 2. Ein beschaedigter Handschlag (Nachricht 3 mit falschem MIC).
    a = lauf(kaputt='mic')
    if a.get('m1') == '1' and a.get('m3') == '0' \
            and a.get('skeys') == '0' and a.get('darf') == '0':
        ok("BESCHAEDIGTER HANDSCHLAG (Nachricht 3 ohne gueltigen "
           "Pruefwert): sauberer Abbruch, kein Schluessel, kein Absturz")
    else:
        bad("ein beschaedigter Handschlag hinterlaesst etwas: %s" % a)

    # --- 3. Gar keine Nachricht 3.
    a = lauf(ohne_m3=True)
    if a.get('m1') == '1' and a.get('m3') == '0' \
            and a.get('skeys') == '0' and a.get('dhcp') == '0':
        ok("HANDSCHLAG BRICHT NACH NACHRICHT 1 AB: kein Schluessel, "
           "keine Adresse -- eine halbe Verbindung gibt es nicht")
    else:
        bad("ein abgebrochener Handschlag kommt zu weit: %s" % a)

    # --- 4. Ein offenes Netz.
    a = lauf(beacon=beacon_bauen(SSID, rsn=False))
    if a.get('netze') == '1' and a.get('wahl') == '0' \
            and a.get('skeys') == '0' and a.get('darf') == '0':
        ok("OFFENES NETZ: es wird gefunden und BENANNT, aber nicht "
           "gewaehlt -- und nichts geht darueber")
    else:
        bad("ein offenes Netz kommt zu weit: %s" % a)

    # --- 5. Die Antworten sind mit einem FREMDEN Schluessel gebaut.
    #
    # Das ist der Fall, um den es bei CCMP eigentlich geht: jemand
    # sendet auf demselben Kanal und gibt sich als der Zugangspunkt
    # aus, hat aber den Handschlag nicht gefuehrt.
    a = lauf(tk_falsch=True)
    if int(a.get('rx', '0')) <= 0 and a.get('dhcp') == '0' \
            and a.get('http') == '0':
        ok("FREMDER SCHLUESSEL: der Handschlag gelingt, aber die Rahmen "
           "eines Fremden gehen NICHT auf -- kein DHCP, kein HTTP")
    else:
        bad("Rahmen mit einem fremden Schluessel kommen durch: %s" % a)

    # --- 6. Eine DHCP-Antwort von einem Fremden.
    a = lauf(dhcp_fremd=True)
    if a.get('dhcp') == '0' and a.get('ip') == '0':
        ok("FREMDE DHCP-ANTWORT: sie ist mit einem anderen Schluessel "
           "verschluesselt und wird verworfen -- KEINE Adresse")
    else:
        bad("eine fremde DHCP-Antwort bringt eine Adresse: %s" % a)

    # --- 7. Eine HTTP-Antwort, die keine 200 ist.
    #
    # Gegenprobe zur Gegenprobe: `http=200` darf nicht deshalb
    # dastehen, weil dort IMMER 200 steht.
    a = lauf(http_kaputt=True)
    if a.get('http') == '500':
        ok("EINE ANDERE HTTP-ANTWORT wird auch als andere gelesen (500 "
           "statt 200) -- das Feld ist nicht fest verdrahtet")
    else:
        bad("der HTTP-Status wird nicht wirklich gelesen: %s" % a)

    # --- 8. Verstuemmelte Beacons.
    beacon = beacon_bauen(SSID, rsn=True)
    schlimm = None
    for schnitt in (8, 12, 16, 20, 24, 30, 36, 44):
        a = lauf(beacon=beacon[:schnitt])
        if a.get('skeys', 'x') != '0' or a.get('dhcp', 'x') != '0':
            schlimm = (schnitt, a)
            break
    if schlimm is None:
        ok("ACHT VERSTUEMMELTE BEACONS (auf 8..44 Oktette gekuerzt): "
           "keines fuehrt zu einem Schluessel oder zu einer Adresse")
    else:
        bad("ein auf %d Oktette gekuerztes Beacon kommt zu weit: %s"
            % schlimm)

    # --- 9. Jedes einzelne Oktett der DHCP-Antwort kippen.
    #
    # Das ist die Zusage, die CCMP wirklich gibt: KEINE Aenderung am
    # Schluesseltext darf unbemerkt durchgehen.
    pmk, m1, m3, ptk = aufbau()
    ap = Zugangspunkt(ptk[32:48], AA, SPA)
    echt = ap.dhcp_antwort(XID)
    ein = ap.echo()
    ht = ap.http_antwort()
    durch = 0
    geprueft = 0
    # Der 802.11-Kopf (24) und der CCMP-Kopf (8) sind nicht
    # verschluesselt; gekippt wird der Schluesseltext dahinter.
    for i in range(32, len(echt)):
        kaputt = bytearray(echt)
        kaputt[i] ^= 0x01
        geprueft += 1
        b = felder(orakel(zeile_bauen(beacon, pmk, m1, m3, ein,
                                      bytes(kaputt), ht)))
        if b.get('dhcp') != '0':
            durch += 1
    if durch == 0:
        ok("JEDES EINZELNE OKTETT der DHCP-Antwort gekippt (%d Faelle): "
           "KEINES geht durch, keine Adresse wird uebernommen"
           % geprueft)
    else:
        bad("%d von %d gekippten DHCP-Antworten kommen durch"
            % (durch, geprueft))

    # --- 10. Der Rahmen wird gekuerzt.
    durch = 0
    geprueft = 0
    for schnitt in range(24, len(echt), 7):
        geprueft += 1
        b = felder(orakel(zeile_bauen(beacon, pmk, m1, m3, ein,
                                      echt[:schnitt], ht)))
        if b.get('dhcp') != '0':
            durch += 1
    if durch == 0:
        ok("DIE DHCP-ANTWORT AN %d STELLEN ABGESCHNITTEN: keine davon "
           "bringt eine Adresse" % geprueft)
    else:
        bad("%d von %d abgeschnittenen Antworten kommen durch"
            % (durch, geprueft))

    # =================================================================
    print()
    print("== 3. GEGEN DIE ECHTE AUFZEICHNUNG: Pakete, die niemand "
          "fuer Osum gebaut hat ==")
    # =================================================================
    #
    # Das ist die staerkste Zusage, die diese Runde geben kann, und
    # der Grund ist der aus dem Kopf von `gegenstelle.py`: gegen den
    # eigenen systematischen Denkfehler hilft kein Selbstvergleich.
    # `tools/wlan/mitschnitt.txt` haelt Rahmen aus `wpa-Induction.pcap`
    # fest -- einer Aufzeichnung eines echten WPA2-Netzes, die es seit
    # Jahren gibt und die niemand mit Blick auf Osum gebaut hat.
    #
    # [gemessen, 15.09.2026] Zwei der vier verschluesselten Rahmen
    # darin sind ein echter DHCP-Austausch. Sie werden mit dem
    # Schluessel aus dem echten Handschlag geoeffnet und durch
    # `lib/wlan/llc.fi` geschickt.
    mitschnitt = os.path.join(HIER, 'mitschnitt.txt')
    if not os.path.exists(mitschnitt):
        bad("tools/wlan/mitschnitt.txt fehlt")
    else:
        from gegenstelle import ccmp_oeffnen
        daten = []
        mp = {}
        for ln in open(mitschnitt):
            ln = ln.strip()
            if not ln or ln.startswith('#'):
                continue
            k, _, v = ln.partition(' ')
            if k == 'daten':
                daten.append(u(v))
            else:
                mp[k] = v
        pmk_e = pmk_aus_psk(mp['passwort'].encode(), mp['netz'].encode())
        e1 = u(mp['eapol1'])
        e2 = u(mp['eapol2'])
        tk_e = ptk_ableiten(pmk_e, u(mp['aa']), u(mp['spa']),
                            e1[17:49], e2[17:49])[32:48]

        # --- der echte DHCP-Request
        pt = ccmp_oeffnen(tk_e, daten[0])
        b = felder(orakel("ipdhcp %s" % h(pt)))
        if b.get('et') == '2048' and b.get('ipsum') == '1' \
                and b.get('udpsum') == '1' and b.get('dart') == '3' \
                and b.get('qport') == '68' and b.get('zport') == '67':
            ok("ECHTER DHCP-REQUEST aus wpa-Induction.pcap: LLC/SNAP, "
               "IPv4- UND UDP-Pruefsumme stimmen, es ist ein Request "
               "(Art 3) von Port 68 an 67")
        else:
            bad("der echte DHCP-Request wird falsch gelesen: %s" % b)

        # --- das echte DHCP-Ack
        pt = ccmp_oeffnen(tk_e, daten[1])
        b = felder(orakel("ipdhcp %s" % h(pt)))
        if b.get('dart') == '5' \
                and b.get('yiaddr') == str(ip2i('192.168.0.50')) \
                and b.get('maske') == str(ip2i('255.255.255.0')) \
                and b.get('tor') == str(ip2i('192.168.0.1')) \
                and b.get('server') == str(ip2i('192.168.0.1')) \
                and b.get('miete') == '86400':
            ok("ECHTES DHCP-ACK aus derselben Aufzeichnung: Adresse "
               "192.168.0.50, Maske 255.255.255.0, Tor und Server "
               "192.168.0.1, Mietdauer 86400 s -- Oktett fuer Oktett "
               "das, was damals wirklich auf dem Draht stand")
        else:
            bad("das echte DHCP-Ack wird falsch gelesen: %s" % b)

        if b.get('ipsum') == '1' and b.get('udpsum') == '1':
            ok("beide Pruefsummen des echten Ack rechnen auf null auf "
               "-- die Pruefsummenrechnung stimmt gegen fremde Pakete")
        else:
            bad("die Pruefsummen des echten Ack stimmen nicht: %s" % b)

        # --- Gegenprobe: ein gekipptes Oktett MUSS die Pruefsumme
        #     brechen. Sonst prueft sie nichts.
        kaputt = bytearray(pt)
        kaputt[20] ^= 0x01        # irgendwo im IP-Kopf
        b2 = felder(orakel("ipdhcp %s" % h(bytes(kaputt))))
        if b2.get('ipsum') == '0':
            ok("ein einziges gekipptes Oktett im IP-Kopf des echten "
               "Pakets bricht die Pruefsumme -- sie wird wirklich "
               "gerechnet und nicht nur gemeldet")
        else:
            bad("eine gekippte IP-Pruefsumme faellt nicht auf: %s" % b2)

    print()
    print("VOLLWEG: %d Zusagen, %d Fehler" % (gut, schlecht))
    return 1 if schlecht else 0


if __name__ == '__main__':
    sys.exit(main())
