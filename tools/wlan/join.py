#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from gegenstelle import Authenticator, Zugangspunkt, ptk_ableiten, pmk_aus_psk, ip2i
from weg import beacon_bauen

BIN = sys.argv[1]
PASS = 0
FAIL = 0

MAC = bytes([2, 0, 0, 0, 1, 0])
BSSID = bytes([2, 0, 0, 0, 0, 0])
SSID = b"OsumNetz"
PW = b"einpasswort123"
ANONCE = b"\x33" * 32
SNONCE = b"\x44" * 32
GTK = b"\x11" * 16
XID = 0x12345678
SNAP = bytes([0xAA, 0xAA, 3, 0, 0, 0, 0x88, 0x8E])


def ok(cond, text):
    global PASS, FAIL
    if cond:
        PASS += 1
        print("  OK    " + text)
    else:
        FAIL += 1
        print("  FAIL  " + text)


def le(b, o, n):
    return int.from_bytes(b[o:o + n], "little")


def mgmt(fc, a1, a2, a3, body):
    return struct.pack("<HH6s6s6sH", fc, 0, a1, a2, a3, 0) + body


def auth_resp(status):
    return mgmt(0x00B0, MAC, BSSID, BSSID, struct.pack("<HHH", 0, 2, status))


def assoc_resp(status):
    return mgmt(0x0010, MAC, BSSID, BSSID, struct.pack("<HHH", 0x0431, status, 0xC001))


def eapol_frame(eapol):
    return struct.pack("<HH6s6s6sH", 0x0208, 0, MAC, BSSID, BSSID, 0) + SNAP + eapol


def hx(b):
    return b.hex() if b else "-"


def ref_auth():
    return mgmt(0x00B0, BSSID, MAC, BSSID, struct.pack("<HHH", 0, 1, 0))


def ref_assoc(ch, ssid=SSID):
    body = struct.pack("<HH", 0x0431, 10) + bytes([0, len(ssid)]) + ssid
    body += bytes([1, 8, 0x82, 0x84, 0x8B, 0x96, 0x0C, 0x12, 0x18, 0x24, 50, 4, 0x30, 0x48, 0x60, 0x6C])
    body += bytes.fromhex("30140100000fac040100000fac040100000fac020000")
    return mgmt(0x0000, BSSID, MAC, BSSID, body)


def scenario(pw=PW, ap_pw=PW, beacon="ok", auth=0, assoc=0, skip=(), tamper_m3=False,
             ack_art=5, dhcp_key=None, ssid_beacon=SSID, offer_xid=XID, offer_art=2):
    pmk_ap = pmk_aus_psk(ap_pw, SSID)
    pmk_dev = pmk_aus_psk(pw, SSID)
    ap = Authenticator(SSID, ap_pw, BSSID, MAC, anonce=ANONCE, gtk=GTK,
                       boese={"mic3_falsch"} if tamper_m3 else None)
    m1 = ap.nachricht1()
    ap.snonce = SNONCE
    ap.ptk = ptk_ableiten(pmk_ap, BSSID, MAC, ANONCE, SNONCE)
    m3 = ap.nachricht3()
    tk = ap.ptk[32:48]
    zp = Zugangspunkt(dhcp_key or tk, BSSID, MAC)
    offer = zp.dhcp_antwort(offer_xid, art=offer_art, seq=1)
    ack = zp.dhcp_antwort(XID, art=ack_art, seq=2)
    if beacon == "ok":
        b = beacon_bauen(ssid_beacon, kanal=6, rsn=True, bssid=BSSID)
    elif beacon == "open":
        b = beacon_bauen(ssid_beacon, kanal=6, rsn=False, bssid=BSSID)
    else:
        b = b""
    parts = {
        "auth": auth_resp(auth),
        "assoc": assoc_resp(assoc) if auth == 0 else b"",
        "m1": eapol_frame(m1),
        "m3": eapol_frame(m3),
        "offer": offer,
        "ack": ack,
    }
    for k in skip:
        parts[k] = b""
    if assoc != 0:
        parts["m1"] = b""
    line = "join %s %s %s %s %s %s %s %s %s %s %s" % (
        SSID.hex(), pmk_dev.hex(), SNONCE.hex(), hx(b), hx(parts["auth"]), hx(parts["assoc"]),
        hx(parts["m1"]), hx(parts["m3"]), hx(parts["offer"]), hx(parts["ack"]), "")
    return line.strip(), zp, tk


def run(lines):
    p = subprocess.run([BIN], input=("\n".join(lines) + "\n").encode(), stdout=subprocess.PIPE)
    return p.stdout.decode().strip().split("\n")


def split_runs(out):
    runs = []
    cur = []
    for l in out:
        cur.append(l)
        if l.startswith("send "):
            runs.append(cur)
            cur = []
    return runs


class Result:
    def __init__(self, lines):
        self.cmds = [bytes.fromhex(l.split(" ")[1]) for l in lines if l.startswith("cmd ")]
        j = [l for l in lines if l.startswith("join ")][0].split()
        self.rc = int(j[2])
        self.detail = int(j[4])
        self.status = int(j[6])
        self.nets = int(j[8])
        self.may = int(j[10])
        self.keys = int(j[12])
        self.state = int(j[14])
        d = [l for l in lines if l.startswith("dhcp ")]
        self.dhcp = None
        if d:
            f = d[0].split()
            self.dhcp = {"rc": int(f[2]), "ip": int(f[4]), "mask": int(f[6]), "gw": int(f[8]),
                         "dns": int(f[10]), "kind": int(f[12])}
        self.send = int([l for l in lines if l.startswith("send ")][0].split()[1])
        self.ids = [c[0] for c in self.cmds]
        self.tx = [c[60:60 + le(c, 4, 2)] for c in self.cmds if c[0] == 0x1C]


def eapol_of(frame):
    return frame[32:]


def check_all():
    names = ["good", "wrong_pw", "auth_denied", "assoc_denied", "no_beacon", "other_ssid", "no_assoc",
             "no_m1", "no_m3", "bad_m3_mic", "open_net", "no_offer", "nak", "foreign_dhcp", "wrong_xid", "ack_as_offer"]
    scs = {
        "good": scenario(),
        "wrong_pw": scenario(pw=b"falschespasswort"),
        "auth_denied": scenario(auth=13),
        "assoc_denied": scenario(assoc=17),
        "no_beacon": scenario(beacon="none"),
        "other_ssid": scenario(ssid_beacon=b"Fremdnetz"),
        "no_assoc": scenario(skip=("assoc",)),
        "no_m1": scenario(skip=("m1",)),
        "no_m3": scenario(skip=("m3",)),
        "bad_m3_mic": scenario(tamper_m3=True),
        "open_net": scenario(beacon="open"),
        "no_offer": scenario(skip=("offer",)),
        "nak": scenario(ack_art=6),
        "foreign_dhcp": scenario(dhcp_key=bytes(16)),
        "wrong_xid": scenario(offer_xid=XID + 1),
        "ack_as_offer": scenario(offer_art=5),
    }
    out = run([scs[n][0] for n in names])
    runs = split_runs(out)
    ok(len(runs) == len(names), "all %d scenarios produced a result" % len(names))
    if len(runs) != len(names):
        print("\n".join(out[:20]))
        return
    r = {n: Result(runs[i]) for i, n in enumerate(names)}

    print("== full path: scan, auth, assoc, 4-way handshake, DHCP ==")
    g = r["good"]
    ok(g.rc == 0 and g.detail == 0, "join returns 0")
    ok(g.nets == 1 and g.may == 1, "one network found, data allowed")
    want_ids = [0x08, 0x28, 0x2B, 0x0C, 0x0D, 0x08, 0x18, 0x28, 0x1C, 0x1C, 0x18, 0x28, 0x1C, 0x1C, 0x1C, 0x1C, 0x1C]
    ok(g.ids == want_ids, "command sequence %s" % " ".join("%02x" % i for i in g.ids))
    ok(g.keys == 0, "software crypto: no key sent to firmware")
    ok(len(g.tx) == 7, "seven frames transmitted (auth, assoc, M2, M4, DHCP discover, DHCP request, data)")
    if len(g.tx) == 7:
        ok(g.tx[0] == ref_auth(), "auth request matches reference")
        ok(g.tx[1] == ref_assoc(6), "assoc request matches reference")
        ap = Authenticator(SSID, PW, BSSID, MAC, anonce=ANONCE, gtk=GTK)
        ap.nachricht1()
        good2 = good4 = False
        try:
            ap.nachricht2_pruefen(eapol_of(g.tx[2]))
            good2 = True
            ap.nachricht3()
            ap.nachricht4_pruefen(eapol_of(g.tx[3]))
            good4 = True
        except Exception as e:
            print("   ", e)
        ok(good2, "message 2 accepted by the independent authenticator")
        ok(good4, "message 4 accepted by the independent authenticator")
        ok(g.tx[2][1] & 0x40 == 0 and g.tx[3][1] & 0x40 == 0, "EAPOL frames go out unprotected")
        zp = scs["good"][1]
        plains = []
        for k in (4, 5):
            try:
                plains.append(zp.oeffnen(g.tx[k]))
            except Exception as e:
                print("   ", e)
        ok(len(plains) == 2 and g.tx[4][1] & 0x40 and g.tx[5][1] & 0x40,
           "DHCP frames are protected and open with the handshake key")
        if len(plains) == 2:
            ok(b"\x35\x01\x01" in plains[0] and XID.to_bytes(4, "big") in plains[0], "DHCP discover (type 1, xid)")
            offered = ip2i("192.168.0.50").to_bytes(4, "big")
            ok(b"\x35\x01\x03" in plains[1] and b"\x32\x04" + offered in plains[1], "DHCP request asks for the offered address")
        pn = [g.tx[k][24] | (g.tx[k][25] << 8) for k in (4, 5)]
        ok(pn[1] > pn[0], "packet numbers count up")
    ok(g.dhcp is not None and g.dhcp["rc"] == 0 and g.dhcp["ip"] == ip2i("192.168.0.50"), "DHCP lease: address 192.168.0.50")
    ok(g.dhcp is not None and g.dhcp["mask"] == ip2i("255.255.255.0") and g.dhcp["gw"] == ip2i("192.168.0.1")
       and g.dhcp["kind"] == 5, "DHCP lease: mask, gateway, ACK")
    ok(g.send > 0 and len(g.tx) == 7 and g.tx[6][1] & 0x40 != 0, "data frame goes out protected after the join")

    print("== counter checks ==")
    w = r["wrong_pw"]
    ok(w.rc == -111 and w.detail == 4, "wrong password: join fails with MIC error (rc %d detail %d)" % (w.rc, w.detail))
    ok(w.may == 0 and w.send == -1 and w.dhcp is None, "wrong password: no data allowed, no frame sent, no DHCP")
    ok(len(w.tx) == 3, "wrong password: no message 4 sent")
    if len(w.tx) >= 3:
        ap = Authenticator(SSID, PW, BSSID, MAC, anonce=ANONCE, gtk=GTK)
        ap.nachricht1()
        bad = False
        try:
            ap.nachricht2_pruefen(eapol_of(w.tx[2]))
        except Exception:
            bad = True
        ok(bad, "wrong password: the authenticator rejects message 2")
    b = r["bad_m3_mic"]
    ok(b.rc == -111 and b.detail == 4 and b.may == 0 and len(b.tx) == 3, "tampered message 3 MIC: rejected, no message 4, no data")
    a = r["auth_denied"]
    ok(a.rc == -112 and a.status == 13 and len(a.tx) == 1 and a.may == 0, "auth refused (status 13): clean abort after one frame")
    s = r["assoc_denied"]
    ok(s.rc == -113 and s.status == 17 and len(s.tx) == 2 and s.may == 0, "assoc refused (status 17): clean abort, no EAPOL")
    n = r["no_beacon"]
    ok(n.rc == -102 and n.nets == 0 and len(n.tx) == 0, "no beacon: zero networks, nothing transmitted")
    o = r["other_ssid"]
    ok(o.rc == -102 and o.nets == 1 and len(o.tx) == 0, "other SSID only: network listed but not joined")
    ok(r["no_assoc"].rc == -106 and r["no_assoc"].may == 0, "assoc response missing: timeout")
    ok(r["no_m1"].rc == -107, "message 1 missing: timeout")
    ok(r["no_m3"].rc == -108 and r["no_m3"].may == 0, "message 3 missing: timeout, no keys")
    p = r["open_net"]
    ok(p.rc == -103 and len(p.tx) == 0, "open network is refused before any frame is sent")
    ok(r["no_offer"].rc == 0 and r["no_offer"].dhcp["rc"] == -201, "DHCP offer missing: error -201")
    ok(r["nak"].dhcp is not None and r["nak"].dhcp["rc"] == -203, "DHCP NAK: error -203")
    ok(r["wrong_xid"].dhcp["rc"] == -201, "DHCP offer with a foreign xid is ignored")
    ok(r["ack_as_offer"].dhcp["rc"] == -201, "DHCP ACK where an offer belongs is refused")
    ok(r["foreign_dhcp"].dhcp is not None and r["foreign_dhcp"].dhcp["rc"] == -201, "DHCP reply under a foreign key is dropped")


check_all()
print("RESULT pass=%d fail=%d" % (PASS, FAIL))
sys.exit(1 if FAIL else 0)
