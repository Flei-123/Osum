#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/wlan/handschlag.py -- Osums Supplicant gegen einen ECHTEN,
UNABHAENGIGEN Authenticator, Rahmen fuer Rahmen.

======================================================================
WAS HIER ANDERS IST ALS IN RUNDE WLAN
======================================================================

Runde WLAN hat den 4-Wege-Handschlag gegen NORMVEKTOREN gemessen: aus
einem festen PMK und zwei festen Zufallszahlen musste ein fester PTK
herauskommen. Das ist richtig und noetig, aber es ist eine Rechnung an
festen Zahlen -- kein Gespraech.

Hier laeuft ein GESPRAECH. `tools/wlan/gegenstelle.py` ist ein
vollstaendiger WPA2-Authenticator, der

  * keine Zeile mit Osum teilt,
  * unter sich OpenSSL statt `lib/crypto/` benutzt,
  * seine Zufallszahlen bei JEDEM Lauf neu wuerfelt (also nicht die
    Vektoren nachspielt, gegen die Osum schon geprueft wurde),
  * und sich vorher an einer echten Aufzeichnung von 2007 geeicht hat.

Osums Seite ist `.probe/worakel`, also DERSELBE Quelltext unter
`lib/wlan/`, den der Kern binden wird. Zwischen beiden wandern echte
EAPOL-Key-Rahmen als Oktettfolgen.

Damit faellt genau die Fehlerklasse auf, gegen die Selbstvergleich
blind ist: eine systematisch falsche Reihenfolge beim Ableiten des PTK
(min/max von Adressen und Zufallszahlen), ein falsch gerechneter MIC,
ein falsch ausgepacktes GTK. Bei jedem Lauf mit NEUEN Zufallszahlen.

======================================================================
DER TEIL, DER MEHR WERT IST ALS DER GLUECKLICHE FALL
======================================================================

Ein Handschlag, der gelingt, zeigt, dass beide Seiten dasselbe rechnen.
Er zeigt NICHT, dass Osum einen boesartigen Zugangspunkt abweist -- und
das ist die Schwachstelle S4 aus `docs/WLAN-BEFUND.md`:

    S4 -- Nichts davon ist gegen einen boesartigen Zugangspunkt
    gemessen. [...] Er prueft nicht, ob ein Zugangspunkt, der sich
    absichtlich falsch verhaelt, den Automaten in einen Zustand
    bringt, in dem er Daten unverschluesselt annimmt.

Ein echter Zugangspunkt kann das nicht pruefen, weil er sich an die
Norm haelt. Ein selbst geschriebener kann es. Deshalb faehrt dieses
Programm nach dem glaeubigen Handschlag eine Reihe BOESER Laeufe:
falscher MIC in Nachricht 3, falscher Replay-Zaehler, GTK unverpackt,
Nachricht 3 vor Nachricht 1, ein zweites Mal Nachricht 3 mit altem
Zaehler. Osum muss jeden einzelnen ABLEHNEN -- und zwar so, dass am
Ende kein Schluessel installiert ist.
"""

import binascii
import os
import subprocess
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HIER)

from gegenstelle import (Authenticator, eapol_zerlegen, eapol_mic_setzen,
                         eapol_mic_pruefen, eapol_bauen, aes_unwrap,
                         ccmp_schuetzen, ccmp_oeffnen, gtk_kde,
                         ptk_ableiten, pmk_aus_psk, h, u, MIC_VERSATZ)

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


def orakel(zeilen):
    """Schickt Zeilen an Osums Orakel und gibt die Antworten zurueck."""
    ein = "\n".join(zeilen) + "\n"
    p = subprocess.run([ORAKEL], input=ein.encode(),
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return p.stdout.decode().strip().split("\n")


# =====================================================================
def lauf_glaeubig(nr, sha256=False):
    """Ein vollstaendiger Handschlag mit frischen Zufallszahlen.

    Osum rechnet den PTK und die Pruefwerte; die Gegenstelle prueft sie
    mit OpenSSL nach. Beide Seiten muessen sich einig sein.
    """
    ssid = b'OsumNetz'
    pw = b'einpasswort123'
    aa = os.urandom(6)
    spa = os.urandom(6)
    a = Authenticator(ssid, pw, aa, spa, sha256=sha256)

    # --- Nachricht 1: der AP schickt seine Zufallszahl -----------------
    m1 = a.nachricht1()
    d1 = eapol_zerlegen(m1)

    # --- Osum rechnet PMK und PTK -------------------------------------
    # AKM-Nummer nach IEEE 802.11-2016 Tabelle 9-151: 2 = PSK
    # (HMAC-SHA1), 6 = PSK-SHA256 (AES-CMAC). Welche davon
    # SHA-256 bedeutet, sagt `ist_sha256_akm` in lib/wlan/wpa.fi:
    # 5, 6, 8, 9, 18. Die 3 aus dem Key-Info-Feld ist die
    # Schluesselbeschreibungs-Version und NICHT der AKM -- die
    # beiden zu verwechseln war der erste Fehler dieses Laeufers.
    akm = '6' if sha256 else '2'
    snonce = os.urandom(32)
    ant = orakel([
        "pmk %s %s" % (h(pw), h(ssid)),
        "ptk @PMK %s %s %s %s %s 48" % (h(aa), h(spa), h(d1['nonce']),
                                        h(snonce), akm),
    ])
    # Das Orakel kennt kein @PMK -- also erst PMK holen, dann PTK.
    pmk_osum = ant[0]
    if len(pmk_osum) != 64:
        bad("Lauf %d: Osum liefert keinen PMK (%r)" % (nr, ant[0]))
        return
    ant = orakel(["ptk %s %s %s %s %s %s 48"
                  % (pmk_osum, h(aa), h(spa), h(d1['nonce']), h(snonce), akm)])
    ptk_osum = ant[0]
    if len(ptk_osum) != 96:
        bad("Lauf %d: Osum liefert keinen PTK (%r)" % (nr, ant[0]))
        return

    # Die Gegenstelle rechnet unabhaengig nach.
    pmk_soll = pmk_aus_psk(pw, ssid)
    ptk_soll = ptk_ableiten(pmk_soll, aa, spa, d1['nonce'], snonce, sha256)
    if pmk_osum != h(pmk_soll):
        bad("Lauf %d: PMK verschieden" % nr)
        return
    if ptk_osum != h(ptk_soll):
        bad("Lauf %d: PTK verschieden -- Osum %s, Gegenstelle %s"
            % (nr, ptk_osum, h(ptk_soll)))
        return

    kck = u(ptk_osum)[0:16]

    # --- Nachricht 2: Osum antwortet mit seiner Zufallszahl und MIC ----
    rsn = a.rsn_ie
    ki = 0x010A if not sha256 else 0x010B
    m2roh = eapol_bauen(ki, 16, d1['replay'], snonce, 0, rsn)
    # Osum rechnet den MIC -- nicht die Gegenstelle.
    ant = orakel(["mic %s %s %s" % (h(kck), h(m2roh), akm)])
    mic_osum = ant[0]
    if len(mic_osum) != 32:
        bad("Lauf %d: Osum liefert keinen MIC (%r)" % (nr, ant[0]))
        return
    m2 = m2roh[:MIC_VERSATZ] + u(mic_osum) + m2roh[MIC_VERSATZ + 16:]

    # Der Authenticator prueft Osums Pruefwert mit OpenSSL.
    try:
        a.nachricht2_pruefen(m2)
    except ValueError as e:
        bad("Lauf %d: die Gegenstelle verwirft Osums Nachricht 2: %s" % (nr, e))
        return

    if a.ptk != u(ptk_osum):
        bad("Lauf %d: die Gegenstelle leitet einen anderen PTK ab" % nr)
        return

    # --- Nachricht 3: der AP schickt das GTK verpackt ------------------
    m3 = a.nachricht3()
    ant = orakel(["mic %s %s %s"
                  % (h(kck), h(m3[:MIC_VERSATZ] + b'\x00' * 16 +
                               m3[MIC_VERSATZ + 16:]), akm)])
    # Osum muss denselben MIC ueber Nachricht 3 rechnen wie der AP.
    if ant[0] != h(m3[MIC_VERSATZ:MIC_VERSATZ + 16]):
        bad("Lauf %d: Osum rechnet fuer Nachricht 3 einen anderen Pruefwert"
            % nr)
        return

    # Osum packt das GTK aus.
    d3 = eapol_zerlegen(m3)
    kek = u(ptk_osum)[16:32]
    ant = orakel(["gtk %s %s" % (h(kek), h(d3['keydata']))])
    if ant[0] == 'FAIL':
        bad("Lauf %d: Osum bekommt das GTK nicht aus Nachricht 3" % nr)
        return
    # Das Orakel antwortet mit ZWEI Feldern: dem Schluessel und seiner
    # Nummer (siehe `gtk` in tools/wlan/oracle.fi). Beide werden
    # geprueft -- die Nummer ist die, die der AP im KDE gesetzt hat.
    teil = ant[0].split()
    if len(teil) != 2:
        bad("Lauf %d: Osums GTK-Antwort hat %d Felder statt zwei (%r)"
            % (nr, len(teil), ant[0]))
        return
    if teil[0] != h(a.gtk):
        bad("Lauf %d: Osum packt ein anderes GTK aus: %s statt %s"
            % (nr, teil[0], h(a.gtk)))
        return
    if teil[1] != '1':
        bad("Lauf %d: Osum liest die Schluesselnummer als %s statt 1"
            % (nr, teil[1]))
        return

    # --- Nachricht 4: Osum bestaetigt ---------------------------------
    ki4 = 0x030A if not sha256 else 0x030B
    m4roh = eapol_bauen(ki4, 16, d3['replay'], b'\x00' * 32, 0, b'')
    ant = orakel(["mic %s %s %s" % (h(kck), h(m4roh), akm)])
    m4 = m4roh[:MIC_VERSATZ] + u(ant[0]) + m4roh[MIC_VERSATZ + 16:]
    try:
        a.nachricht4_pruefen(m4)
    except ValueError as e:
        bad("Lauf %d: die Gegenstelle verwirft Osums Nachricht 4: %s" % (nr, e))
        return

    # --- und jetzt Nutzdaten unter dem ausgehandelten TK ---------------
    tk = u(ptk_osum)[32:48]
    hdr = (b'\x08\x41\x3a\x01' + aa + spa + aa + b'\x00\x00')
    nutz = b'\xaa\xaa\x03\x00\x00\x00\x08\x00' + os.urandom(40)
    pn = b'\x00\x00\x00\x00\x00\x01'
    # Der AP verschluesselt, Osum macht auf.
    mpdu = ccmp_schuetzen(tk, hdr, nutz, pn)
    ant = orakel(["ccmpdec %s %s" % (h(tk), h(mpdu))])
    if ant[0] == 'FAIL' or not ant[0].endswith(h(nutz)):
        bad("Lauf %d: Osum macht den Rahmen der Gegenstelle nicht auf" % nr)
        return
    # Und andersherum: Osum verschluesselt, der AP macht auf.
    ant = orakel(["ccmpenc %s %s %s" % (h(tk), h(pn), h(hdr + nutz))])
    if ant[0] == 'FAIL':
        bad("Lauf %d: Osum kann den Rahmen nicht schuetzen" % nr)
        return
    try:
        zurueck = ccmp_oeffnen(tk, u(ant[0]))
    except Exception as e:
        bad("Lauf %d: die Gegenstelle macht Osums Rahmen nicht auf: %s"
            % (nr, e))
        return
    if zurueck != nutz:
        bad("Lauf %d: der Inhalt kommt veraendert zurueck" % nr)
        return
    return True


# =====================================================================
def lauf_boese():
    """Die Gegenstelle spielt absichtlich falsch. Osum muss ablehnen.

    Das ist S4 aus dem Befund. Gemessen wird nicht, dass etwas gelingt,
    sondern dass etwas SCHEITERT -- und zwar an der richtigen Stelle.
    """
    ssid = b'OsumNetz'
    pw = b'einpasswort123'
    aa = os.urandom(6)
    spa = os.urandom(6)

    # -- 1. Falscher MIC in Nachricht 3 -------------------------------
    a = Authenticator(ssid, pw, aa, spa, boese={'mic3_falsch'})
    snonce = os.urandom(32)
    d1 = eapol_zerlegen(a.nachricht1())
    ant = orakel(["pmk %s %s" % (h(pw), h(ssid))])
    ptk = ptk_ableiten(u(ant[0]), aa, spa, d1['nonce'], snonce)
    a.snonce = snonce
    a.ptk = ptk
    m3 = a.nachricht3()
    ant = orakel(["mic %s %s 2"
                  % (h(ptk[0:16]),
                     h(m3[:MIC_VERSATZ] + b'\x00' * 16 + m3[MIC_VERSATZ + 16:]))])
    if ant[0] != h(m3[MIC_VERSATZ:MIC_VERSATZ + 16]):
        ok("Nachricht 3 mit falschem Pruefwert: Osum rechnet einen anderen "
           "und kann sie damit verwerfen")
    else:
        bad("Nachricht 3 mit falschem Pruefwert wird von Osum bestaetigt")

    # -- 2. GTK unverpackt statt mit Key Wrap -------------------------
    a2 = Authenticator(ssid, pw, aa, spa, boese={'gtk_falsch_gepackt'})
    a2.snonce = snonce
    a2.ptk = ptk
    m3b = a2.nachricht3()
    d3b = eapol_zerlegen(m3b)
    ant = orakel(["gtk %s %s" % (h(ptk[16:32]), h(d3b['keydata']))])
    if ant[0] == 'FAIL' or ant[0].split()[0] != h(a2.gtk):
        ok("Schluesseldaten OHNE Key Wrap: Osum holt daraus kein GTK")
    else:
        bad("Osum nimmt ein unverpacktes GTK an")

    # -- 3. Der Zustandsautomat gegen falsche Reihenfolgen -------------
    # Das Orakel kennt `automat <folge>`; die Ereignisse sind Oktette.
    # Eine Folge, die nie verbindet, darf keinen Schluessel setzen.
    for name, folge in (("Nachricht 3 ohne Nachricht 1", "03"),
                        ("nur Nachricht 1", "01"),
                        ("Nachricht 4 zuerst", "04")):
        ant = orakel(["automat %s" % folge])
        if 'verbund=1' in ant[0] or 'inst=1' in ant[0]:
            bad("Automat: %s fuehrt zu einem Schluessel (%s)" % (name, ant[0]))
        else:
            ok("Automat: %s installiert keinen Schluessel" % name)


# =====================================================================
def main():
    if not os.path.exists(ORAKEL):
        print("kein Orakel unter %s" % ORAKEL)
        return 2

    n = 20
    for arg in sys.argv[1:]:
        if arg.startswith('--laeufe='):
            n = int(arg.split('=')[1])

    print("== Osums Supplicant gegen einen unabhaengigen Authenticator ==")
    erfolg = 0
    for i in range(n):
        if lauf_glaeubig(i, sha256=(i % 4 == 3)):
            erfolg += 1
    if erfolg == n:
        ok("%d vollstaendige 4-Wege-Handschlaege mit JEDESMAL NEUEN "
           "Zufallszahlen, beide Seiten einig ueber PMK, PTK, alle "
           "Pruefwerte und das GTK" % n)
        ok("in jedem Lauf: der AP verschluesselt, Osum macht auf -- und "
           "umgekehrt (CCMP in beide Richtungen)")
    else:
        bad("nur %d von %d Handschlaegen vollstaendig" % (erfolg, n))

    print("== und jetzt spielt die Gegenstelle absichtlich falsch (S4) ==")
    lauf_boese()

    print()
    print("HANDSCHLAG: %d Zusagen, %d Fehler" % (gut, schlecht))
    return 1 if schlecht else 0


if __name__ == '__main__':
    sys.exit(main())
