#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only

import binascii
import os
import subprocess
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HIER)

from gegenstelle import (Authenticator, build_eapol, set_eapol_mic,
                         eapol_zerlegen, gtk_kde, aes_wrap, pmk_aus_psk,
                         ptk_ableiten, h, u, MIC_OFFSET)

ORAKEL = os.environ.get('ORAKEL', os.path.join(HIER, '..', '..',
                                               '.probe', 'worakel'))
gut = 0
defective = 0


def ok(t):
    global gut
    gut += 1
    print("  OK    %s" % t)


def bad(t):
    global defective
    defective += 1
    print("  FAIL  %s" % t)


def orakel(row):
    p = subprocess.run([ORAKEL], input=(row + "\n").encode(),
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return p.stdout.decode().strip()


def felder(response):
    d = {}
    for part in response.split():
        if '=' in part:
            k, v = part.split('=', 1)
            d[k] = v
    return d


# ---------------------------------------------------------------------
# ---------------------------------------------------------------------

def build_beacon(ssid, channel_no=6, rsn=True, bssid=b'\x02\x00\x00\x00\x00\x00'):
    fc = b'\x80\x00'
    duration = b'\x00\x00'
    target = b'\xff\xff\xff\xff\xff\xff'
    header = fc + duration + target + bssid + bssid + b'\x00\x00'
    fest = b'\x00' * 8 + b'\x64\x00' + b'\x11\x04'
    ies = bytes([0, len(ssid)]) + ssid
    ies += bytes([1, 8]) + b'\x82\x84\x8b\x96\x24\x30\x48\x6c'
    ies += bytes([3, 1, channel_no])
    if rsn:
        ies += u('30140100000fac040100000fac040100000fac020000')
    return header + fest + ies


def build_handshake(pmk, aa, spa, snonce, gtk=b'\x11' * 16,
                     broken=None):
    anonce = b'\x33' * 32
    ptk = ptk_ableiten(pmk, aa, spa, anonce, snonce)
    kck, kek = ptk[0:16], ptk[16:32]
    m1 = build_eapol(0x008A, 16, 1, anonce, 0, b'')
    kd = u('30140100000fac040100000fac040100000fac020000') + gtk_kde(gtk, 1)
    while len(kd) % 8:
        kd += b'\xdd'
    verpackt = aes_wrap(kek, kd)
    m3 = build_eapol(0x13CA, 16, 2, anonce, 0, verpackt)
    if broken == 'mic':
        pass
    else:
        m3, _ = set_eapol_mic(m3, kck, False)
    return m1, m3, ptk, gtk


def main():
    if not os.path.exists(ORAKEL):
        print("no oracle at %s" % ORAKEL)
        return 2

    ssid = b'OsumNetz'
    pw = b'einpasswort123'
    pmk = pmk_aus_psk(pw, ssid)
    aa = b'\x02\x00\x00\x00\x00\x00'
    spa = b'\x02\x00\x00\x00\x01\x00'
    snonce = b'\x44' * 32

    print("== the believing path: it MUST go all the way through ==")
    m1, m3, ptk, gtk = build_handshake(pmk, aa, spa, snonce)
    bk = build_beacon(ssid, rsn=True)
    a = felder(orakel("path %s %s %s %s %s %s %s"
                      % (h(bk), h(pmk), h(spa), h(aa), h(m1),
                         h(snonce), h(m3))))
    if a.get('netze') == '1' and a.get('chosen') == '1' \
            and a.get('m1') == '1' and a.get('m3') == '1' \
            and a.get('data') == '1' and a.get('skeys') == '2':
        ok("scan finds the network, choice works, messages 1 and 3 pass, "
           "and afterwards EXACTLY TWO keys are in the device (PTK and GTK)")
    else:
        bad("the believing path does not go through: %s" % a)

    print("== and now it lies (T4) ==")

    bo = build_beacon(ssid, rsn=False)
    a = felder(orakel("path %s %s %s %s %s %s %s"
                      % (h(bo), h(pmk), h(spa), h(aa), h(m1),
                         h(snonce), h(m3))))
    if a.get('netze') == '1' and a.get('chosen') == '0' \
            and a.get('skeys') == '0':
        ok("an OPEN network is found and NAMED, but not "
           "chosen -- and no key goes into the device")
    else:
        bad("an open network gets too far: %s" % a)

    m1b, m3b, _, _ = build_handshake(pmk, aa, spa, snonce, broken='mic')
    a = felder(orakel("path %s %s %s %s %s %s %s"
                      % (h(bk), h(pmk), h(spa), h(aa), h(m1b),
                         h(snonce), h(m3b))))
    if a.get('m1') == '1' and a.get('m3') == '0' \
            and a.get('data') == '0' and a.get('skeys') == '0':
        ok("message 3 with wrong check value: no key in the device, "
           "no data allowed")
    else:
        bad("a message 3 with wrong MIC gets too far: %s" % a)

    incorrect = pmk_aus_psk(b'daspasswortistfalsch', ssid)
    a = felder(orakel("path %s %s %s %s %s %s %s"
                      % (h(bk), h(incorrect), h(spa), h(aa), h(m1),
                         h(snonce), h(m3))))
    if a.get('m3') == '0' and a.get('data') == '0' \
            and a.get('skeys') == '0':
        ok("the wrong password: the handshake fails at message 3, "
           "no key in the device")
    else:
        bad("a wrong password still leads to a key: %s" % a)

    # --- 4. Gar keine Nachricht 3.
    a = felder(orakel("path %s %s %s %s %s %s -"
                      % (h(bk), h(pmk), h(spa), h(aa), h(m1), h(snonce))))
    if a.get('m1') == '1' and a.get('m3') == '0' \
            and a.get('data') == '0' and a.get('skeys') == '0':
        ok("handshake aborts after message 1: no key, "
           "no data -- there is no half connection")
    else:
        bad("an aborted handshake leaves something behind: %s" % a)

    kein = u('08413a01') + aa + spa + aa + u('0000') + b'\xaa' * 20
    a = felder(orakel("path %s %s %s %s %s %s %s"
                      % (h(kein), h(pmk), h(spa), h(aa), h(m1),
                         h(snonce), h(m3))))
    if a.get('netze') == '0' and a.get('chosen') == '0' \
            and a.get('skeys') == '0':
        ok("a data frame as beacon: no network in the list, no choice")
    else:
        bad("a data frame is taken as a network: %s" % a)

    # --- 6. Ein abgeschnittenes Beacon.
    for schnitt in (10, 20, 30, 40):
        a = felder(orakel("path %s %s %s %s %s %s %s"
                          % (h(bk[:schnitt]), h(pmk), h(spa), h(aa),
                             h(m1), h(snonce), h(m3))))
        if a.get('skeys', 'x') != '0':
            bad("a beacon truncated to %d octets leads to a "
                "key: %s" % (schnitt, a))
            break
    else:
        ok("beacons truncated to 10, 20, 30 and 40 octets: none leads "
           "to a key in the device")

    print()
    print("WEG: %d Zusagen, %d Fehler" % (gut, defective))
    return 1 if defective else 0


if __name__ == '__main__':
    sys.exit(main())
