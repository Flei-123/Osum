#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only

import os
import subprocess
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HIER)

from gegenstelle import (Zugangspunkt, build_eapol, set_eapol_mic,
                         aes_wrap, gtk_kde, pmk_aus_psk, ptk_ableiten,
                         h, u, ip2i, MIC_OFFSET)
from path_run import build_beacon, build_handshake

ORAKEL = os.environ.get('ORAKEL',
                        os.path.join(HIER, '..', '..', '.probe', 'worakel'))

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

SSID = b'OsumNetz'
PW = b'einpasswort123'
AA = b'\x02\x00\x00\x00\x00\x00'
SPA = b'\x02\x00\x00\x00\x01\x00'
SNONCE = b'\x44' * 32
XID = 0x12345678


def aufbau(pw=PW, gtk=b'\x11' * 16, broken=None):
    pmk = pmk_aus_psk(pw, SSID)
    m1, m3, ptk, g = build_handshake(pmk, AA, SPA, SNONCE, gtk=gtk,
                                      broken=broken)
    return pmk, m1, m3, ptk


def build_row(beacon, pmk, m1, m3, ein, dhcp, http):
    def f(x):
        return h(x) if x else '-'
    return "vollweg %s %s %s %s %s %s %s %s %s %s" % (
        h(beacon), h(pmk), h(SPA), h(AA), f(m1), h(SNONCE), f(m3),
        f(ein), f(dhcp), f(http))


def lauf(pw=PW, beacon=None, broken=None, tk_wrong=False,
         without_m3=False, pn_wiederholt=False, http_broken=False,
         dhcp_foreign=False):
    # Passwort gebaut.
    pmk_echt, m1, m3, ptk = aufbau(pw=PW, broken=broken)
    pmk = pmk_aus_psk(pw, SSID)
    tk = ptk[32:48]
    if tk_wrong:
        tk = bytes((b ^ 0xFF) for b in tk)
    ap = Zugangspunkt(tk, AA, SPA)
    if beacon is None:
        beacon = build_beacon(SSID, rsn=True)
    ein = ap.echo()
    if pn_wiederholt:
        # zurueckgedreht.
        ap.pn = 1
        ein = ap.echo()
    dh = ap.dhcp_reply(XID)
    if dhcp_foreign:
        alien = Zugangspunkt(bytes(16), AA, SPA)
        dh = alien.dhcp_reply(XID)
    ht = ap.http_reply(status=b'200 OK')
    if http_broken:
        ht = ap.http_reply(body_bytes=b'x', status=b'500 Fehler')
    if without_m3:
        m3 = None
    return felder(orakel(build_row(beacon, pmk, m1, m3, ein, dh, ht)))


def main():
    if not os.path.exists(ORAKEL):
        print("no oracle at %s" % ORAKEL)
        return 2

    # =================================================================
    print("== 1. THE WHOLE PATH: it MUST pass step by step ==")
    # =================================================================
    a = lauf()

    if a.get('netze') == '1':
        ok("STEP 1 -- scan: the access point is found "
           "(1 network in the list)")
    else:
        bad("scan does not find the access point: %s" % a)

    if a.get('chosen') == '1' and a.get('channel') == '6':
        ok("STEP 2 -- network choice: the network is chosen and the device "
           "set to channel 6 (the channel from the beacon)")
    else:
        bad("network choice or channel wrong: %s" % a)

    if a.get('m1') == '1':
        ok("STEP 3 -- handshake message 1: the PTK is derived from PMK, "
           "beiden Adressen und beiden Zufallszahlen abgeleitet")
    else:
        bad("message 1 does not go through: %s" % a)

    if a.get('m3') == '1' and a.get('skeys') == '2':
        ok("STEP 4 -- handshake message 3: check value matches, GTK "
           "unwrapped, and EXACTLY TWO keys are in the device "
           "(PTK und GTK)")
    else:
        bad("message 3 or the keys do not match: %s" % a)

    if a.get('allowed') == '1':
        ok("STEP 5 -- the state machine is CONNECTED and allows "
           "data (may_pass_data)")
    else:
        bad("the state machine allows no data: %s" % a)

    if int(a.get('tx', '-1')) > 0 and a.get('gesch') == '1':
        ok("STEP 6 -- a data packet goes OUT: %s octets, and the "
           "protected bit is set (it is really encrypted, "
           "not just claimed)" % a['tx'])
    else:
        bad("the data packet does not go out encrypted: %s" % a)

    if int(a.get('rx', '-1')) > 0 and a.get('et') == '2048':
        ok("STEP 7 -- a data packet comes IN: %s octets, with "
           "opened with the same key, LLC/SNAP says EtherType "
           "0x0800 (IPv4)" % a['rx'])
    else:
        bad("the incoming data packet does not open: %s" % a)

    if a.get('dart') == '5' and a.get('ip') == str(ip2i('192.168.0.50')):
        ok("STEP 8 -- DHCP: the answer is an ACK (type 5) and carries "
           "die Adresse 192.168.0.50")
    else:
        bad("DHCP brings no address: %s" % a)

    if a.get('maske') == str(ip2i('255.255.255.0')) \
            and a.get('tor') == str(ip2i('192.168.0.1')):
        ok("SCHRITT 8b -- DHCP: Maske 255.255.255.0 und Tor 192.168.0.1 "
           "kommen mit")
    else:
        bad("Maske oder Tor fehlen: %s" % a)

    if a.get('http') == '200' and int(a.get('body', '-1')) > 0:
        ok("STEP 9 -- HTTP: a request is answered with 200, the "
           "body starts at octet %s" % a['body'])
    else:
        bad("HTTP does not arrive: %s" % a)

    if a.get('reason') == '0':
        ok("the whole path runs through WITHOUT a single failure reason "
           "(reason=0)")
    else:
        bad("a failure reason remains: %s" % a)

    # =================================================================
    print()
    print("== 2. THE COUNTER-CHECKS: the path MUST abort here ==")
    # =================================================================

    a = lauf(pw=b'daspasswortistfalsch')
    if a.get('m3') == '0' and a.get('skeys') == '0' \
            and a.get('allowed') == '0' and a.get('dhcp') == '0' \
            and a.get('http') == '0':
        ok("WRONG PASSWORD: the handshake fails at message 3, "
           "NO key in the device, no data packet, no DHCP, "
           "no HTTP")
    else:
        bad("a wrong password gets too far: %s" % a)

    a = lauf(broken='mic')
    if a.get('m1') == '1' and a.get('m3') == '0' \
            and a.get('skeys') == '0' and a.get('allowed') == '0':
        ok("DAMAGED HANDSHAKE (message 3 without a valid "
           "check value): clean abort, no key, no crash")
    else:
        bad("a damaged handshake leaves something behind: %s" % a)

    # --- 3. Gar keine Nachricht 3.
    a = lauf(without_m3=True)
    if a.get('m1') == '1' and a.get('m3') == '0' \
            and a.get('skeys') == '0' and a.get('dhcp') == '0':
        ok("HANDSHAKE ABORTS AFTER MESSAGE 1: no key, "
           "no address -- there is no half connection")
    else:
        bad("an aborted handshake gets too far: %s" % a)

    a = lauf(beacon=build_beacon(SSID, rsn=False))
    if a.get('netze') == '1' and a.get('chosen') == '0' \
            and a.get('skeys') == '0' and a.get('allowed') == '0':
        ok("OPEN NETWORK: it is found and NAMED, but not "
           "gewaehlt -- und nichts geht darueber")
    else:
        bad("an open network gets too far: %s" % a)

    #
    a = lauf(tk_wrong=True)
    if int(a.get('rx', '0')) <= 0 and a.get('dhcp') == '0' \
            and a.get('http') == '0':
        ok("FOREIGN KEY: the handshake succeeds, but the frames "
           "of a stranger do NOT open -- no DHCP, no HTTP")
    else:
        bad("frames with a foreign key get through: %s" % a)

    a = lauf(dhcp_foreign=True)
    if a.get('dhcp') == '0' and a.get('ip') == '0':
        ok("FOREIGN DHCP ANSWER: it is encrypted with another key "
           "and is dropped -- NO address")
    else:
        bad("a foreign DHCP answer brings an address: %s" % a)

    #
    a = lauf(http_broken=True)
    if a.get('http') == '500':
        ok("A DIFFERENT HTTP ANSWER is also read as different (500 "
           "instead of 200) -- the field is not hard-wired")
    else:
        bad("the HTTP status is not really read: %s" % a)

    # --- 8. Verstuemmelte Beacons.
    beacon = build_beacon(SSID, rsn=True)
    schlimm = None
    for schnitt in (8, 12, 16, 20, 24, 30, 36, 44):
        a = lauf(beacon=beacon[:schnitt])
        if a.get('skeys', 'x') != '0' or a.get('dhcp', 'x') != '0':
            schlimm = (schnitt, a)
            break
    if schlimm is None:
        ok("EIGHT MUTILATED BEACONS (truncated to 8..44 octets): "
           "none leads to a key or to an address")
    else:
        bad("a beacon truncated to %d octets gets too far: %s"
            % schlimm)

    #
    # Schluesseltext darf unbemerkt durchgehen.
    pmk, m1, m3, ptk = aufbau()
    ap = Zugangspunkt(ptk[32:48], AA, SPA)
    echt = ap.dhcp_reply(XID)
    ein = ap.echo()
    ht = ap.http_reply()
    durch = 0
    geprueft = 0
    for i in range(32, len(echt)):
        broken = bytearray(echt)
        broken[i] ^= 0x01
        geprueft += 1
        b = felder(orakel(build_row(beacon, pmk, m1, m3, ein,
                                      bytes(broken), ht)))
        if b.get('dhcp') != '0':
            durch += 1
    if durch == 0:
        ok("EVERY SINGLE OCTET of the DHCP answer flipped (%d cases): "
           "NONE gets through, no address is taken"
           % geprueft)
    else:
        bad("%d of %d flipped DHCP answers get through"
            % (durch, geprueft))

    durch = 0
    geprueft = 0
    for schnitt in range(24, len(echt), 7):
        geprueft += 1
        b = felder(orakel(build_row(beacon, pmk, m1, m3, ein,
                                      echt[:schnitt], ht)))
        if b.get('dhcp') != '0':
            durch += 1
    if durch == 0:
        ok("THE DHCP ANSWER TRUNCATED AT %d POINTS: none of them "
           "brings an address" % geprueft)
    else:
        bad("%d of %d truncated answers get through"
            % (durch, geprueft))

    # =================================================================
    print()
    print("== 3. AGAINST THE REAL CAPTURE: packets nobody "
          "built for Osum ==")
    # =================================================================
    #
    #
    # `lib/wlan/llc.fi` geschickt.
    mitschnitt = os.path.join(HIER, 'mitschnitt.txt')
    if not os.path.exists(mitschnitt):
        bad("tools/wlan/mitschnitt.txt fehlt")
    else:
        from gegenstelle import ccmp_open
        payload = []
        mp = {}
        for ln in open(mitschnitt):
            ln = ln.strip()
            if not ln or ln.startswith('#'):
                continue
            k, _, v = ln.partition(' ')
            if k == 'daten':
                payload.append(u(v))
            else:
                mp[k] = v
        pmk_e = pmk_aus_psk(mp['passwort'].encode(), mp['netz'].encode())
        e1 = u(mp['eapol1'])
        e2 = u(mp['eapol2'])
        tk_e = ptk_ableiten(pmk_e, u(mp['aa']), u(mp['spa']),
                            e1[17:49], e2[17:49])[32:48]

        # --- der echte DHCP-Request
        pt = ccmp_open(tk_e, payload[0])
        b = felder(orakel("ipdhcp %s" % h(pt)))
        if b.get('et') == '2048' and b.get('ipsum') == '1' \
                and b.get('udpsum') == '1' and b.get('dart') == '3' \
                and b.get('qport') == '68' and b.get('zport') == '67':
            ok("ECHTER DHCP-REQUEST aus wpa-Induction.pcap: LLC/SNAP, "
               "IPv4 AND UDP checksums match, it is a request "
               "(Art 3) von Port 68 an 67")
        else:
            bad("the real DHCP request is read wrongly: %s" % b)

        # --- das echte DHCP-Ack
        pt = ccmp_open(tk_e, payload[1])
        b = felder(orakel("ipdhcp %s" % h(pt)))
        if b.get('dart') == '5' \
                and b.get('yiaddr') == str(ip2i('192.168.0.50')) \
                and b.get('maske') == str(ip2i('255.255.255.0')) \
                and b.get('tor') == str(ip2i('192.168.0.1')) \
                and b.get('server') == str(ip2i('192.168.0.1')) \
                and b.get('miete') == '86400':
            ok("REAL DHCP ACK from the same capture: address "
               "192.168.0.50, Maske 255.255.255.0, Tor und Server "
               "192.168.0.1, lease 86400 s -- octet for octet "
               "what really was on the wire back then")
        else:
            bad("the real DHCP ack is read wrongly: %s" % b)

        if b.get('ipsum') == '1' and b.get('udpsum') == '1':
            ok("both checksums of the real ack sum to zero "
               "-- the checksum computation holds against foreign packets")
        else:
            bad("the checksums of the real ack do not match: %s" % b)

        #     brechen. Sonst prueft sie nichts.
        broken = bytearray(pt)
        broken[20] ^= 0x01
        b2 = felder(orakel("ipdhcp %s" % h(bytes(broken))))
        if b2.get('ipsum') == '0':
            ok("a single flipped octet in the IP header of the real "
               "packet breaks the checksum -- it is really "
               "computed and not just reported")
        else:
            bad("a flipped IP checksum goes unnoticed: %s" % b2)

    print()
    print("VOLLWEG: %d Zusagen, %d Fehler" % (gut, defective))
    return 1 if defective else 0


if __name__ == '__main__':
    sys.exit(main())
