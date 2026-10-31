#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from gegenstelle import Authenticator, ptk_ableiten, pmk_aus_psk, eapol_zerlegen

BIN = sys.argv[1]
PASS = 0
FAIL = 0


def ok(cond, text):
    global PASS, FAIL
    if cond:
        PASS += 1
        print("  OK    " + text)
    else:
        FAIL += 1
        print("  FAIL  " + text)


def run(lines):
    p = subprocess.run([BIN], input=("\n".join(lines) + "\n").encode(), stdout=subprocess.PIPE)
    return p.stdout.decode().strip().split("\n")


def le(b, o, n):
    return int.from_bytes(b[o:o + n], "little")


MAC = bytes([2, 0, 0, 0, 1, 0])
BSSID = bytes([2, 0, 0, 0, 0, 0])
SSID = b"OsumNetz"


def ref_auth():
    return struct.pack("<HH6s6s6sHHHH", 0x00B0, 0, BSSID, MAC, BSSID, 0, 0, 1, 0)


def ref_assoc(ch):
    body = struct.pack("<HH", 0x0431, 10) + bytes([0, len(SSID)]) + SSID
    if ch <= 14:
        body += bytes([1, 8, 0x82, 0x84, 0x8B, 0x96, 0x0C, 0x12, 0x18, 0x24, 50, 4, 0x30, 0x48, 0x60, 0x6C])
    else:
        body += bytes([1, 8, 0x8C, 0x12, 0x98, 0x24, 0xB0, 0x48, 0x60, 0x6C])
    body += bytes.fromhex("30140100000fac040100000fac040100000fac020000")
    return struct.pack("<H", 0) + b"\x00\x00" + BSSID + MAC + BSSID + b"\x00\x00" + body


def check_build():
    print("== management frames ==")
    for ch in (6, 36):
        out = run(["build %d %s %s %s" % (ch, SSID.hex(), MAC.hex(), BSSID.hex())])
        d = dict(l.split(" ", 1) for l in out)
        ok(bytes.fromhex(d["auth"]) == ref_auth(), "auth request == reference (ch %d)" % ch)
        ok(bytes.fromhex(d["assoc"]) == ref_assoc(ch), "assoc request == reference (ch %d)" % ch)


def cmds(out):
    return [bytes.fromhex(l.split(" ")[1]) for l in out if l.startswith("cmd ")]


def check_seq(hw):
    mode = "hw" if hw else "sw"
    print("== command sequence (%s crypto) ==" % mode)
    out = run(["seq" + mode])
    c = cmds(out)
    ids = [x[0] for x in c]
    want = [0x18, 0x08, 0x28, 0x2B, 0x0C, 0x18, 0x28, 0x0D, 0x08] + ([0x17, 0x17] if hw else []) + [0x1C]
    ok(ids == want, "command ids %s" % " ".join("%02x" % i for i in ids))
    ok([le(x, 2, 2) & 0xFF for x in c] == list(range(1, len(c) + 1)), "command slots count up")
    rc = [l for l in out if l.startswith("rc ")][0].split()
    ok(rc[1:7] == ["0"] * 6 and rc[7] == "30", "all operations returned 0, send returned 30")
    ok(rc[9] == ("2" if hw else "0") and rc[11] == ("1" if hw else "0"), "keys sent / ccmp flag as %s mode" % mode)
    aux = c[0]
    c = c[1:]
    ok(aux[4 + 16] == 1 and le(aux, 4 + 4, 4) == 4 and le(aux, 4 + 2, 2) == 0xFFFF and le(aux, 4 + 40, 4) == 2, "ADD_STA aux station: id 1, MAC index 4, all TIDs off, queue 1")
    phy_add, mac_add, bind, scfg, sta, mac_mod, scan, phy_mod = c[:8]
    ok(le(phy_add, 4 + 4, 4) == 1 and phy_add[4 + 17] == 1 and phy_add[4 + 16] == 1 and len(phy_add) == 4 + 36, "PHY_CONTEXT add, v1 layout 36 octets, 2.4 GHz channel 1")
    ok(le(phy_mod, 4 + 4, 4) == 2 and phy_mod[4 + 17] == 6 and phy_mod[4 + 16] == 1, "PHY_CONTEXT modify channel 6 2.4 GHz")
    ok(le(mac_add, 4 + 8, 4) == 5 and mac_add[4 + 16:4 + 22] == MAC, "MAC_CONTEXT add: BSS station, own address")
    ok(mac_mod[4 + 24:4 + 30] == BSSID and le(mac_mod, 4 + 4, 4) == 2, "MAC_CONTEXT modify carries the BSSID")
    ok(le(bind, 4 + 20, 4) == 0 and le(bind, 4 + 8, 4) == 0, "BINDING add links MAC 0 and PHY 0")
    for name, w in (("SCAN_CFG", scfg), ("SCAN_REQ_UMAC", scan)):
        ok(w[1] == 1 and le(w, 4, 2) == len(w) - 8 and w[6] == 0 and w[7] == 0, "%s uses the wide header (group 1, payload length)" % name)
    scfg = scfg[:4] + scfg[8:]
    scan = scan[:4] + scan[8:]
    nchan = le(scfg, 4, 4) >> 26
    ok(nchan == 35 and scfg[4 + 36:4 + 36 + 4] == bytes([1, 2, 3, 4]), "SCAN_CFG lists 35 channels")
    ok(le(scfg, 4, 4) & 0x3FFFFFF == 0x2EF09 and le(scfg, 4 + 12, 4) == 0x0FFF0FFF and scfg[4 + 24:4 + 28] == bytes([10, 110, 44, 90]) and scfg[4 + 34] == 1 and scfg[4 + 35] == 0xF, "SCAN_CFG flags/rates/dwell/aux id/channel flags as iwlwifi legacy config v1")
    ok(sta[4 + 8:4 + 14] == BSSID and sta[4] == 0, "ADD_STA peer = BSSID, mode add")
    ok(scan[4 + 33] == 35 and b"HPAP" in scan, "SCAN_REQ_UMAC: 35 channels, direct scan SSID")
    tx = c[-1]
    frame = ref_auth()
    ok(le(tx, 4, 2) == len(frame) and tx[60:60 + len(frame)] == frame, "TX_CMD carries the auth frame unchanged")
    ok(tx[4 + 16] == 0, "TX_CMD station id = AP")
    ok(le(tx, 4 + 4, 4) == 0x2008 and le(tx, 4 + 12, 4) == 0x400D, "TX_CMD flags ACK|SEQ_CTL, 6M OFDM rate")
    if hw:
        k1, k2 = c[8], c[9]
        ok(k1[4 + 4:4 + 20] == bytes([0x55] * 16) and le(k1, 4 + 2, 2) == 0x0002, "ADD_STA_KEY pairwise: key bytes, CCMP, unicast")
        ok(le(k2, 4 + 2, 2) == 0x4102 and k2[4 + 1] == 2, "ADD_STA_KEY group: multicast, key id 1")
    rx = [l for l in out if l.startswith("rx ")][0].split()
    ok(rx[1] == "30" and rx[3] == "-60" and rx[5] == "1", "RX: frame 30 octets, rssi -60, scan still running")
    ok(bytes.fromhex(rx[6]) == frame, "RX frame handed over unchanged")
    rx2 = [l for l in out if l.startswith("rx2 ")][0].split()
    ok(rx2[1] == "0" and rx2[3] == "2", "SCAN_COMPLETE notification ends the scan")


def key_frames(wrong_kck=False):
    ap = Authenticator(SSID, b"einpasswort123", BSSID, MAC, anonce=b"\x33" * 32, gtk=b"\x11" * 16)
    m1 = ap.nachricht1()
    snonce = b"\x44" * 32
    pmk = pmk_aus_psk(b"einpasswort123", SSID)
    ptk = ptk_ableiten(pmk, BSSID, MAC, b"\x33" * 32, snonce)
    kck = ptk[:16]
    kuse = bytes(16) if wrong_kck else kck
    out = run(["m2 %s %s %s" % (m1.hex(), snonce.hex(), kuse.hex())])
    m2 = bytes.fromhex(out[0].split()[1]) if len(out[0].split()) > 1 else b""
    return ap, m1, kuse, m2


def check_eapol():
    print("== EAPOL messages 2 and 4 against the independent authenticator ==")
    ap, m1, kck, m2 = key_frames()
    good2 = False
    try:
        ap.nachricht2_pruefen(m2)
        good2 = True
    except Exception as e:
        print("   ", e)
    ok(good2, "message 2: replay counter, nonce, MIC accepted")
    ok(struct.unpack(">H", m2[5:7])[0] == 0x010A, "message 2 key info: AES, pairwise, MIC")
    ok(len(m2) == 99 + 22 and m2[-22:-20] == b"\x30\x14", "message 2 carries the RSN element")
    m3 = ap.nachricht3()
    out = run(["m4 %s %s" % (m3.hex(), kck.hex())])
    m4 = bytes.fromhex(out[0].split()[1])
    good4 = False
    try:
        ap.nachricht4_pruefen(m4)
        good4 = True
    except Exception as e:
        print("   ", e)
    ok(good4 and struct.unpack(">H", m4[5:7])[0] == 0x030A, "message 4: replay counter and MIC accepted, secure bit set")
    ap2, m1b, kckb, m2b = key_frames(wrong_kck=True)
    bad = False
    try:
        ap2.nachricht2_pruefen(m2b)
    except Exception:
        bad = True
    ok(bad, "control: message 2 with a wrong KCK is rejected")


def check_parse():
    print("== response parsing ==")
    auth_ok = struct.pack("<HH6s6s6sHHHH", 0x00B0, 0, MAC, BSSID, BSSID, 0, 0, 2, 0)
    auth_bad = struct.pack("<HH6s6s6sHHHH", 0x00B0, 0, MAC, BSSID, BSSID, 0, 0, 2, 13)
    assoc_ok = struct.pack("<HH6s6s6sHHHH", 0x0010, 0, MAC, BSSID, BSSID, 0, 0x0431, 0, 0xC001)
    assoc_bad = struct.pack("<HH6s6s6sHHHH", 0x0010, 0, MAC, BSSID, BSSID, 0, 0x0431, 17, 0xC001)
    snap = bytes([0xAA, 0xAA, 3, 0, 0, 0, 0x88, 0x8E])
    data = struct.pack("<HH6s6s6sH", 0x0208, 0, MAC, BSSID, BSSID, 0) + snap + b"\x02\x03\x00\x00"
    for name, f, want in (("auth ok", auth_ok, "auth 0 assoc -1 aid 0 eapol -1"),
                          ("auth refused", auth_bad, "auth 13 assoc -1 aid 13 eapol -1"),
                          ("assoc ok", assoc_ok, "auth -1 assoc 0 aid 1 eapol -1"),
                          ("assoc refused", assoc_bad, "auth -1 assoc 17 aid 1 eapol -1"),
                          ("EAPOL data frame", data, "auth -1 assoc -1 aid 0 eapol 32")):
        got = run(["parse %s %s" % (f.hex(), BSSID.hex())])[0]
        ok(got == want, "%s -> %s" % (name, got))
    foreign = struct.pack("<HH6s6s6sHHHH", 0x00B0, 0, MAC, MAC, BSSID, 0, 0, 2, 0)
    got = run(["parse %s %s" % (foreign.hex(), BSSID.hex())])[0]
    ok(got.startswith("auth -1"), "auth response from a foreign transmitter is ignored")


check_build()
def check_diag():
    print("== setup failure diagnosis ==")
    expect = [(6, 0x18, 0x00), (1, 0x08, 0x40), (2, 0x28, 0x42), (3, 0x2B, 0x46), (4, 0x0C, 0x4E)]
    out = run(["failstep %d" % i for i in range(6)])
    for i, (step, cmd, okm) in enumerate(expect):
        f = out[i].split(" ")
        ok(f[:2] == ["failstep", "rc"] and f[2] == "-70" and f[4] == str(step) and f[6] == "-70" and f[8] == str(cmd) and f[10] == str(okm),
           "command %d failing is reported as step %d cmd %d: %s" % (i, step, cmd, out[i]))
    for i in range(5):
        f = out[i].split(" ")
        ok(f[12] == "0" and f[14] == "5", "setup retry after failure at command %d resends only the missing steps (5 commands total): %s" % (i, out[i]))
    f = out[5].split(" ")
    ok(f[2] == "0" and f[4] == "0" and f[6] == "0" and f[10] == "94", "all steps ok: no failed step, ok mask 0x5e: " + out[5])


check_seq(True)
check_seq(False)
check_diag()
check_eapol()
check_parse()
print("RESULT pass=%d fail=%d" % (PASS, FAIL))
sys.exit(1 if FAIL else 0)
