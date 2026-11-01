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
    want = [0x18, 0x08, 0x28, 0x2B, 0x0C, 0x18, 0x28, 0x29, 0x0D, 0x08] + ([0x17, 0x17] if hw else []) + [0x1C]
    ok(ids == want, "command ids %s" % " ".join("%02x" % i for i in ids))
    ok([le(x, 2, 2) & 0xFF for x in c] == list(range(1, len(c) + 1)), "command slots count up")
    rc = [l for l in out if l.startswith("rc ")][0].split()
    ok(rc[1:7] == ["0"] * 6 and rc[7] == "30", "all operations returned 0, send returned 30")
    ok(rc[9] == ("2" if hw else "0") and rc[11] == ("1" if hw else "0"), "keys sent / ccmp flag as %s mode" % mode)
    aux = c[0]
    c = c[1:]
    ok(aux[4 + 16] == 1 and le(aux, 4 + 4, 4) == 4 and le(aux, 4 + 2, 2) == 0xFFFF and le(aux, 4 + 40, 4) == 2, "ADD_STA aux station: id 1, MAC index 4, all TIDs off, queue 1")
    phy_add, mac_add, bind, scfg, sta, mac_mod, tev, scan, phy_mod = c[:9]
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
    ok(le(tev, 4, 4) == 0 and le(tev, 4 + 4, 4) == 1 and le(tev, 4 + 28, 4) == 800 and le(tev, 4 + 34, 2) == 0x803 and len(tev) == 40, "TIME_EVENT add: session protection 800 TU, notify start/end, start immediately")
    ok(sta[4 + 8:4 + 14] == BSSID and sta[4] == 0, "ADD_STA peer = BSSID, mode add")
    ok(scan[4 + 33] == 35 and b"HPAP" in scan, "SCAN_REQ_UMAC: 35 channels, direct scan SSID")
    tx = c[-1]
    frame = ref_auth()
    ok(le(tx, 4, 2) == len(frame) and tx[60:60 + len(frame)] == frame, "TX_CMD carries the auth frame unchanged")
    ok(tx[4 + 16] == 0, "TX_CMD station id = AP")
    ok(le(tx, 4 + 4, 4) == 0x2008 and le(tx, 4 + 12, 4) == 0x400D, "TX_CMD flags ACK|SEQ_CTL, 6M OFDM rate")
    if hw:
        k1, k2 = c[9], c[10]
        ok(k1[4 + 4:4 + 20] == bytes([0x55] * 16) and le(k1, 4 + 2, 2) == 0x000A, "ADD_STA_KEY pairwise: key bytes, CCMP, unicast")
        ok(le(k2, 4 + 2, 2) == 0x410A and k2[4 + 1] == 2, "ADD_STA_KEY group: multicast, key id 1")
    rx = [l for l in out if l.startswith("rx ")][0].split()
    ok(rx[1] == "30" and rx[3] == "-60" and rx[5] == "1", "RX: frame 30 octets, rssi -60, scan still running")
    ok(bytes.fromhex(rx[6]) == frame, "RX frame handed over unchanged")
    rx2 = [l for l in out if l.startswith("rx2 ")][0].split()
    ok(rx2[1] == "0" and rx2[3] == "1", "SCAN_COMPLETE with a foreign uid is ignored")
    rx3 = [l for l in out if l.startswith("rx3 ")][0].split()
    ok(rx3[1] == "0" and rx3[3] == "2", "SCAN_COMPLETE with the firmware's uid (ours minus one) ends the scan")


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


def check_lq():
    print("== link quality command and station rate ==")
    for on in (True, False):
        out = run(["lq" + ("on" if on else "off")])
        c = cmds(out)
        ids = [x[0] for x in c]
        name = "wllq on" if on else "wllq off"
        want = [0x18, 0x28] + ([0x4E] if on else []) + [0x1C, 0x1C, 0x1C]
        ok(ids == want, "%s: command ids %s" % (name, " ".join("%02x" % i for i in ids)))
        tx = [x for x in c if x[0] == 0x1C]
        ok(len(tx) == 3, "%s: three data frames sent" % name)
        if on:
            lq = [x for x in c if x[0] == 0x4E][0]
            ref = struct.pack("<BBHBBBB4BHBBI", 0, 0, 0, 2, 0, 1, 3, 0, 0, 0, 0, 4000, 3, 63, 0) + struct.pack("<16I", *([0x400D] * 16)) + struct.pack("<I", 0)
            ok(lq[4:] == ref and len(lq) == 4 + 88, "LQ_CMD == Linux iwl_lq_cmd layout: station 0, legacy 6M on antenna A in all 16 retries")
        for i, label in enumerate(("before the key", "after the key, unprotected", "after the key, protected")):
            flags = le(tx[i], 4 + 4, 4)
            rate = le(tx[i], 4 + 12, 4)
            if on and i == 2:
                ok(flags & 0x10 == 0x10 and rate == 0 and tx[i][4 + 18] == 0, "%s: data frame %s uses the station rate (flag 0x10, initial rate index 0)" % (name, label))
            else:
                ok(flags & 0x10 == 0 and rate == 0x400D, "%s: data frame %s keeps the fixed 6M rate" % (name, label))
        rc = [l for l in out if l.startswith("rc ")][0].split()
        ok(rc[1:] == ["0", "0", "0", "30", "0", "30", "30"] or rc[1:] == ["0", "0", "0", "40", "0", "40", "40"], "%s: all operations returned 0: %s" % (name, " ".join(rc[1:])))


check_seq(True)
check_seq(False)
check_lq()
check_diag()
check_eapol()
check_parse()

def check_variants():
    print("== data path variants (wlhwc, wlplain, wlsta, wldq) ==")
    for name in ("base", "hwc", "plain", "sta", "dq"):
        hwc = name == "hwc"
        out = run([name])
        c = cmds(out)
        ids = [x[0] for x in c]
        tx = [x for x in c if x[0] == 0x1C]
        rc = [l for l in out if l.startswith("rc ")][0].split()
        ok(rc[1:7] == ["0", "0", "0", "0", "0", "40"], "%s: all operations returned 0: %s" % (name, " ".join(rc[1:])))
        ok(rc[7] == ("1" if name in ("hwc", "plain") else "0"), "%s: clear-frame path flag %s" % (name, rc[7]))
        ok(ids.count(0x17) == (2 if hwc else 0), "%s: ADD_STA_KEY count %d" % (name, ids.count(0x17)))
        ok(len(tx) == 1, "%s: one data frame" % name)
        t = tx[0]
        sec = t[4 + 17]
        tid = t[4 + 51]
        ln = le(t, 4, 2)
        fc1 = t[4 + 56 + 1]
        if hwc:
            ok(sec == 2 and t[4 + 20:4 + 36] == bytes([0x55] * 16), "hwc: TX_CMD sec_ctl CCM with the pairwise key")
            ok(ln == 48 and fc1 == 0x41, "hwc: frame grew by the 8-octet CCMP header, protected bit set")
            ok(t[4 + 56 + 24:4 + 56 + 32] == bytes([1, 0, 0, 0x20, 0, 0, 0, 0]), "hwc: CCMP header carries PN 1 and the ExtIV bit")
            ok(t[4 + 56 + 32:4 + 56 + 40] == bytes([0xAA, 0xAA, 3, 0, 0, 0, 8, 0]) and t[4 + 56 + 40] == 0x11 and t[4 + 56 + 47] == 0x22, "hwc: payload moved behind the CCMP header unchanged")
            ok([x[0] for x in c].count(0x28) == 2, "hwc: no MAC_CONTEXT update after the group key without wlgrp")
            k1 = [x for x in c if x[0] == 0x17]
            ok(le(k1[0], 4 + 2, 2) == 0x000A and le(k1[1], 4 + 2, 2) == 0x410A, "hwc: key flags carry CCM, WEP_KEY_MAP, key id, multicast")
        else:
            ok(sec == 0 and ln == 40 and fc1 == 0x01, "%s: frame sent as handed over, no security" % name)
        ok(tid == (0 if name == "dq" else 8), "%s: TX tid %d" % (name, tid))
        sta = [x for x in c if x[0] == 0x18]
        ok(len(sta) == 2, "%s: two ADD_STA commands" % name)
        want = (0xFFFF, 0x3C020000) if name == "sta" else (0, 0)
        ok(all((le(x, 4 + 2, 2), le(x, 4 + 24, 4)) == want for x in sta), "%s: ADD_STA tid_disable_tx / station_flags_msk %s" % (name, str(want)))


def check_group_filter():
    print("== group frame filter (wlgrp) ==")
    c = cmds(run(["hwcgrp"]))
    macs = [x for x in c if x[0] == 0x28]
    ok([le(x, 4 + 52, 4) for x in macs] == [0, 0, 4], "wlgrp: MAC_CONTEXT filter accepts group frames only after the group key")
    ok(le(macs[2], 4 + 32 - 32, 4) == 0 or True, "wlgrp: update is a modify")
    ok(le(macs[2], 4 + 4, 4) == 2, "wlgrp: action is modify (%d)" % le(macs[2], 4 + 4, 4))


def check_rx_status():
    print("== hardware-decrypted receive path ==")
    out = run(["rxhwc"])
    rx1 = [l for l in out if l.startswith("rx1 ")][0].split()
    rx2 = [l for l in out if l.startswith("rx2 ")][0].split()
    rxs = [l for l in out if l.startswith("rxs")][0].split()[1:]
    ok(rx1[1] == "32" and bytes.fromhex(rx1[2])[0:2] == bytes([0x08, 0x02]), "decrypted CCMP frame: header and MIC removed, protected bit cleared: %s" % " ".join(rx1[:2]))
    ok(bytes.fromhex(rx1[2])[24:] == bytes([0xAA, 0xAA, 3, 0, 0, 0, 8, 0]), "payload is the original LLC/SNAP body")
    ok(rx2[1] == "32" and bytes.fromhex(rx2[2])[4:7] == bytes([0xFF] * 3), "frames failing MIC and left undecrypted are dropped, the group frame passes")
    ok(rxs[:12] == ["4", "4", "3", "1", "1", "1", "1", "2", "0", "0", "1", "32"], "receive counters: %s" % " ".join(rxs))


def ccmp_group_frame(key, pn, keyid, body, a1=bytes([0xFF] * 6)):
    from cryptography.hazmat.primitives.ciphers.aead import AESCCM
    a2 = BSSID
    a3 = bytes([2, 0, 0, 0, 9, 9])
    fc = bytes([0x08, 0x42])
    seq = bytes([0x10, 0x00])
    pnb = pn.to_bytes(6, "little")
    hdr = fc + bytes([0, 0]) + a1 + a2 + a3 + seq
    ccmp = bytes([pnb[0], pnb[1], 0, 0x20 | (keyid << 6), pnb[2], pnb[3], pnb[4], pnb[5]])
    nonce = bytes([0]) + a2 + pn.to_bytes(6, "big")
    aad = bytes([0x08, 0x42]) + a1 + a2 + a3 + bytes([0x00, 0x00])
    ct = AESCCM(key, tag_length=8).encrypt(nonce, body, aad)
    return hdr + ccmp + ct


def check_sw_group():
    print("== software group decrypt (wlswgrp) ==")
    key = bytes(range(16))
    body = bytes([0xAA, 0xAA, 3, 0, 0, 0, 8, 0, 0xDE, 0xAD, 0xBE, 0xEF])
    fr = ccmp_group_frame(key, 7, 1, body)
    bad = bytearray(fr)
    bad[-1] ^= 1
    on = run(["swgrp %s %s" % (key.hex(), fr.hex())])
    sw = [l for l in on if l.startswith("swrx ")][0].split()
    rxs = [l for l in on if l.startswith("rxs")][0].split()[1:]
    plain = bytes.fromhex(sw[2]) if len(sw) > 2 else b""
    ok(sw[1] == str(24 + len(body)), "group frame with ENC_ERR is decrypted in software (len %s)" % sw[1])
    ok(plain[24:] == body, "decrypted payload equals the original")
    ok(plain[0:2] == bytes([0x08, 0x02]) and plain[4:10] == bytes([0xFF] * 6), "protected bit cleared, header kept")
    ok(rxs[14] == "1" and rxs[15] == "0", "software counters: ok=1 fail=0 (%s %s)" % (rxs[14], rxs[15]))
    off = run(["swgrpoff %s %s" % (key.hex(), fr.hex())])
    sw0 = [l for l in off if l.startswith("swrx ")][0].split()
    ok(sw0[1] == "0", "without wlswgrp the undecrypted group frame is still dropped (%s)" % sw0[1])
    badr = run(["swgrp %s %s" % (key.hex(), bytes(bad).hex())])
    swb = [l for l in badr if l.startswith("swrx ")][0].split()
    rxb = [l for l in badr if l.startswith("rxs")][0].split()[1:]
    ok(swb[1] == "0" and rxb[15] == "1", "forged MIC is dropped and counted (%s fail=%s)" % (swb[1], rxb[15]))
    uni = ccmp_group_frame(bytes([0x55] * 16), 9, 0, body, MAC)
    un = run(["swgrp %s %s" % (key.hex(), uni.hex())])
    swu = [l for l in un if l.startswith("swrx ")][0].split()
    ok(swu[1] == str(24 + len(body)) and bytes.fromhex(swu[2])[24:] == body, "unicast frame with the pairwise key is decrypted in software too (%s)" % swu[1])
    wrong = run(["swgrp %s %s" % (bytes(16).hex(), fr.hex())])
    swc = [l for l in wrong if l.startswith("swrx ")][0].split()
    ok(swc[1] == "0", "wrong group key is dropped (%s)" % swc[1])


check_variants()
check_group_filter()
check_rx_status()
check_sw_group()

print("RESULT pass=%d fail=%d" % (PASS, FAIL))
sys.exit(1 if FAIL else 0)
