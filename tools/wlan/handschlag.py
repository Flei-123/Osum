#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only

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
    ein = "\n".join(zeilen) + "\n"
    p = subprocess.run([ORAKEL], input=ein.encode(),
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return p.stdout.decode().strip().split("\n")


# =====================================================================
def lauf_glaeubig(nr, sha256=False):
    ssid = b'OsumNetz'
    pw = b'einpasswort123'
    aa = os.urandom(6)
    spa = os.urandom(6)
    a = Authenticator(ssid, pw, aa, spa, sha256=sha256)

    # --- Nachricht 1: der AP schickt seine Zufallszahl -----------------
    m1 = a.nachricht1()
    d1 = eapol_zerlegen(m1)

    # --- Osum rechnet PMK und PTK -------------------------------------
    # (HMAC-SHA1), 6 = PSK-SHA256 (AES-CMAC). Welche davon
    # SHA-256 bedeutet, sagt `ist_sha256_akm` in lib/wlan/wpa.fi:
    akm = '6' if sha256 else '2'
    snonce = os.urandom(32)
    ant = orakel([
        "pmk %s %s" % (h(pw), h(ssid)),
        "ptk @PMK %s %s %s %s %s 48" % (h(aa), h(spa), h(d1['nonce']),
                                        h(snonce), akm),
    ])
    pmk_osum = ant[0]
    if len(pmk_osum) != 64:
        bad("Run %d: Osum returns no PMK (%r)" % (nr, ant[0]))
        return
    ant = orakel(["ptk %s %s %s %s %s %s 48"
                  % (pmk_osum, h(aa), h(spa), h(d1['nonce']), h(snonce), akm)])
    ptk_osum = ant[0]
    if len(ptk_osum) != 96:
        bad("Run %d: Osum returns no PTK (%r)" % (nr, ant[0]))
        return

    pmk_soll = pmk_aus_psk(pw, ssid)
    ptk_soll = ptk_ableiten(pmk_soll, aa, spa, d1['nonce'], snonce, sha256)
    if pmk_osum != h(pmk_soll):
        bad("Run %d: PMK differs" % nr)
        return
    if ptk_osum != h(ptk_soll):
        bad("Run %d: PTK differs -- Osum %s, peer %s"
            % (nr, ptk_osum, h(ptk_soll)))
        return

    kck = u(ptk_osum)[0:16]

    rsn = a.rsn_ie
    ki = 0x010A if not sha256 else 0x010B
    m2roh = eapol_bauen(ki, 16, d1['replay'], snonce, 0, rsn)
    ant = orakel(["mic %s %s %s" % (h(kck), h(m2roh), akm)])
    mic_osum = ant[0]
    if len(mic_osum) != 32:
        bad("Run %d: Osum returns no MIC (%r)" % (nr, ant[0]))
        return
    m2 = m2roh[:MIC_VERSATZ] + u(mic_osum) + m2roh[MIC_VERSATZ + 16:]

    try:
        a.nachricht2_pruefen(m2)
    except ValueError as e:
        bad("Run %d: the peer rejects Osum's message 2: %s" % (nr, e))
        return

    if a.ptk != u(ptk_osum):
        bad("Run %d: the peer derives a different PTK" % nr)
        return

    m3 = a.nachricht3()
    ant = orakel(["mic %s %s %s"
                  % (h(kck), h(m3[:MIC_VERSATZ] + b'\x00' * 16 +
                               m3[MIC_VERSATZ + 16:]), akm)])
    if ant[0] != h(m3[MIC_VERSATZ:MIC_VERSATZ + 16]):
        bad("Run %d: Osum computes a different check value for message 3"
            % nr)
        return

    d3 = eapol_zerlegen(m3)
    kek = u(ptk_osum)[16:32]
    ant = orakel(["gtk %s %s" % (h(kek), h(d3['keydata']))])
    if ant[0] == 'FAIL':
        bad("Run %d: Osum does not get the GTK from message 3" % nr)
        return
    teil = ant[0].split()
    if len(teil) != 2:
        bad("Run %d: Osum's GTK answer has %d fields instead of two (%r)"
            % (nr, len(teil), ant[0]))
        return
    if teil[0] != h(a.gtk):
        bad("Run %d: Osum unwraps a different GTK: %s instead of %s"
            % (nr, teil[0], h(a.gtk)))
        return
    if teil[1] != '1':
        bad("Run %d: Osum reads the key number as %s instead of 1"
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
        bad("Run %d: the peer rejects Osum's message 4: %s" % (nr, e))
        return

    tk = u(ptk_osum)[32:48]
    hdr = (b'\x08\x41\x3a\x01' + aa + spa + aa + b'\x00\x00')
    nutz = b'\xaa\xaa\x03\x00\x00\x00\x08\x00' + os.urandom(40)
    pn = b'\x00\x00\x00\x00\x00\x01'
    mpdu = ccmp_schuetzen(tk, hdr, nutz, pn)
    ant = orakel(["ccmpdec %s %s" % (h(tk), h(mpdu))])
    if ant[0] == 'FAIL' or not ant[0].endswith(h(nutz)):
        bad("Run %d: Osum does not open the peer's frame" % nr)
        return
    ant = orakel(["ccmpenc %s %s %s" % (h(tk), h(pn), h(hdr + nutz))])
    if ant[0] == 'FAIL':
        bad("Run %d: Osum cannot protect the frame" % nr)
        return
    try:
        zurueck = ccmp_oeffnen(tk, u(ant[0]))
    except Exception as e:
        bad("Run %d: the peer does not open Osum's frame: %s"
            % (nr, e))
        return
    if zurueck != nutz:
        bad("Run %d: the content comes back changed" % nr)
        return
    return True


# =====================================================================
def lauf_boese():
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
        ok("message 3 with wrong check value: Osum computes a different one "
           "and can thus discard it")
    else:
        bad("message 3 with wrong check value is accepted by Osum")

    # -- 2. GTK unverpackt statt mit Key Wrap -------------------------
    a2 = Authenticator(ssid, pw, aa, spa, boese={'gtk_falsch_gepackt'})
    a2.snonce = snonce
    a2.ptk = ptk
    m3b = a2.nachricht3()
    d3b = eapol_zerlegen(m3b)
    ant = orakel(["gtk %s %s" % (h(ptk[16:32]), h(d3b['keydata']))])
    if ant[0] == 'FAIL' or ant[0].split()[0] != h(a2.gtk):
        ok("key data WITHOUT key wrap: Osum gets no GTK from it")
    else:
        bad("Osum nimmt ein unverpacktes GTK an")

    for name, folge in (("message 3 without message 1", "03"),
                        ("only message 1", "01"),
                        ("message 4 first", "04")):
        ant = orakel(["automat %s" % folge])
        if 'verbund=1' in ant[0] or 'inst=1' in ant[0]:
            bad("state machine: %s leads to a key (%s)" % (name, ant[0]))
        else:
            ok("state machine: %s installs no key" % name)


# =====================================================================
def main():
    if not os.path.exists(ORAKEL):
        print("no oracle at %s" % ORAKEL)
        return 2

    n = 20
    for arg in sys.argv[1:]:
        if arg.startswith('--laeufe='):
            n = int(arg.split('=')[1])

    print("== Osum's supplicant against an independent authenticator ==")
    erfolg = 0
    for i in range(n):
        if lauf_glaeubig(i, sha256=(i % 4 == 3)):
            erfolg += 1
    if erfolg == n:
        ok("%d complete 4-way handshakes with NEW "
           "nonces, both sides agree on PMK, PTK, all "
           "check values and the GTK" % n)
        ok("in every run: the AP encrypts, Osum opens -- and "
           "and vice versa (CCMP in both directions)")
    else:
        bad("only %d of %d handshakes complete" % (erfolg, n))

    print("== and now the peer deliberately plays false (S4) ==")
    lauf_boese()

    print()
    print("HANDSCHLAG: %d Zusagen, %d Fehler" % (gut, schlecht))
    return 1 if schlecht else 0


if __name__ == '__main__':
    sys.exit(main())
