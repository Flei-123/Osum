#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/wlan/link.py -- LW-2 wiring gate: lib/wlan/link.fi (EAPOL dispatch, group key after message 3, capability
summary per network) against an independent Python model.

usage: python3 -I tools/wlan/link.py <path to link oracle binary>
Keys, MICs and frames come from hashlib/hmac/cryptography, never from the Firn code. Exit 0 = all checks OK.
"""
import hashlib
import hmac
import struct
import subprocess
import sys

from cryptography.hazmat.primitives import cmac
from cryptography.hazmat.primitives.ciphers import algorithms
from cryptography.hazmat.primitives.keywrap import aes_key_wrap

passed = failed = 0


def check(name, ok):
    global passed, failed
    if ok:
        passed += 1
        print("  OK    " + name)
    else:
        failed += 1
        print("  FAIL  " + name)


def rnd(n, s):
    return hashlib.sha256(s.encode()).digest()[:n]


def prf384(key, a, b):
    out = b""
    i = 0
    while len(out) < 48:
        out += hmac.new(key, a + b"\0" + b + bytes([i]), hashlib.sha1).digest()
        i += 1
    return out[:48]


def ptk_of(pmk, aa, spa, anonce, snonce):
    data = min(aa, spa) + max(aa, spa) + min(anonce, snonce) + max(anonce, snonce)
    return prf384(pmk, b"Pairwise key expansion", data)


def mic_of(kck, frame):
    z = frame[:81] + b"\0" * 16 + frame[97:]
    return hmac.new(kck, z, hashlib.sha1).digest()[:16]


def frame_of(ki, counter, nonce, data, kck=None, corrupt=False):
    body = (bytes([2]) + struct.pack(">HH", ki, 0) + struct.pack(">Q", counter) + nonce + b"\0" * 16
            + b"\0" * 8 + b"\0" * 8 + b"\0" * 16 + struct.pack(">H", len(data)) + data)
    fr = bytes([2, 3]) + struct.pack(">H", len(body)) + body
    if kck is not None:
        m = mic_of(kck, fr)
        if corrupt:
            m = bytes([m[0] ^ 1]) + m[1:]
        fr = fr[:81] + m + fr[97:]
    return fr


def pad8(b):
    if len(b) % 8:
        b = b + b"\xdd" + b"\0" * ((8 - (len(b) + 1) % 8) % 8)
    return b


def kde(idx, gtk):
    return bytes([0xDD, 6 + len(gtk), 0x00, 0x0F, 0xAC, 0x01, idx & 3, 0]) + gtk


RSN = bytes([48, 20, 1, 0, 0x00, 0x0F, 0xAC, 4, 1, 0, 0x00, 0x0F, 0xAC, 4, 1, 0, 0x00, 0x0F, 0xAC, 2, 0, 0])


def wrapped(ptk, idx, gtk, with_rsn=False):
    return aes_key_wrap(ptk[16:32], pad8((RSN if with_rsn else b"") + kde(idx, gtk)))


def beacon(ssid, bssid, ch, extra=b"", privacy=True):
    hdr = struct.pack("<HH", 0x0080, 0) + b"\xff" * 6 + bssid + bssid + struct.pack("<H", 0)
    body = b"\0" * 8 + struct.pack("<HH", 100, 0x0011 if privacy else 0x0001)
    ies = bytes([0, len(ssid)]) + ssid + bytes([1, 4, 0x82, 0x84, 0x8B, 0x96]) + bytes([3, 1, ch])
    if privacy:
        ies += RSN
    return hdr + body + ies + extra


def run(binpath, lines):
    r = subprocess.run([binpath], input=("\n".join(lines) + "\n").encode(), capture_output=True, timeout=60)
    return r.stdout.decode().splitlines()


def kv(line):
    d = {}
    for t in line.split()[1:]:
        if "=" in t:
            k, v = t.split("=", 1)
            d[k] = v
    return d


def main():
    binpath = sys.argv[1]
    pmk, aa, spa = rnd(32, "pmk"), bytes.fromhex("020000000a01"), bytes.fromhex("020000000b02")
    an, sn = rnd(32, "anonce"), rnd(32, "snonce")
    ptk = ptk_of(pmk, aa, spa, an, sn)
    kck = ptk[:16]
    gA, gB = rnd(16, "gA"), rnd(16, "gB")
    m1 = frame_of(0x008A, 1, an, b"")
    m3 = lambda ctr, idx, g, **k: frame_of(0x13CA, ctr, an, wrapped(ptk, idx, g, True), kck, **k)
    grp = lambda ctr, idx, g, **k: frame_of(0x1382, ctr, rnd(32, "gn"), wrapped(ptk, idx, g), kck, **k)
    S = "S %s %s %s 2" % (pmk.hex(), aa.hex(), spa.hex())
    E = lambda fr: "E %s %s" % (sn.hex(), fr.hex())
    script = [
        S,
        E(grp(1, 1, gA)),                       # 1 group frame before the connection
        E(m1),                                  # 2 message 1
        E(m3(2, 1, gA)),                        # 4 message 3
        E(grp(3, 1, gA)),                       # 5 rekey with the SAME key as message 3
        E(grp(3, 1, gA)),                       # 6 replay
        E(grp(4, 2, gB)),                       # 7 new key
        E(grp(5, 2, gB)),                       # 8 same key again
        "X",
        E(grp(6, 2, gB)),                       # 9 after link_reset the group state is forgotten
        E(frame_of(0x030A, 2, an, b"", kck)),   # 10 message 2 shaped (STA -> AP), not ours
        E(m1[:60]),                             # 11 truncated
        S,
        E(m1),
        E(m3(2, 1, gA)),
        E(grp(2, 2, gB)),                       # 12 counter equal to message 3's counter
        E(grp(3, 2, gB, corrupt=True)),         # 13 bad MIC group frame
        S,
        E(m1),
        E(m3(2, 1, gA, corrupt=True)),          # 14 message 3, bad MIC: dropped, handshake must survive
        E(m3(2, 1, gA)),                        # 15 the real message 3 afterwards
    ]
    out = run(binpath, script)
    check("oracle printed one line per command", len(out) == len(script))
    r = [kv(l) for l in out]
    # indexes: 0 S, 1..13 first part (13 = X is index 9)
    check("group frame before the handshake: refused -1 (kind group), nothing installed",
          r[1].get("rc") == "-1" and r[1].get("kind") == "5" and r[1].get("skeys") == "0")
    check("message 1 -> PTK length 48, kind 1", r[2].get("rc") == "48" and r[2].get("kind") == "1")
    check("message 3 with bad MIC refused, no key installed, no GTK remembered",
          r[-2].get("rc") == "-1" and r[-2].get("kind") == "3" and r[-2].get("skeys") == "0" and r[-2].get("haveg") == "0")
    check("forged message 3 does NOT abort the handshake (state stays 6 = message 2 sent, not 9 = error)",
          r[-2].get("st") == "6")
    check("the real message 3 after the forged one completes the handshake (rc 1, 2 keys, state 8, GTK remembered)",
          r[-1].get("rc") == "1" and r[-1].get("skeys") == "2" and r[-1].get("st") == "8" and r[-1].get("haveg") == "1")
    check("message 3 accepted (PTK model == library PTK): rc 1, 2 keys, connected (state 8)",
          r[3].get("rc") == "1" and r[3].get("skeys") == "2" and r[3].get("st") == "8")
    check("message 3 GTK remembered for the rekey logic (id 1, octets)",
          r[3].get("haveg") == "1" and r[3].get("kid") == "1" and r[3].get("gtk") == gA.hex())
    check("rekey with the GTK of message 3: answered (99) but NOT installed again",
          r[4].get("rc") == "99" and r[4].get("kind") == "5" and r[4].get("inst") == "0" and r[4].get("skeys") == "2")
    check("rekey replay refused (-4)", r[5].get("rc") == "-4" and r[5].get("inst") == "0")
    check("rekey with a new key installed", r[6].get("rc") == "99" and r[6].get("inst") == "1"
          and r[6].get("skeys") == "3" and r[6].get("gtk") == gB.hex())
    check("same new key again: answered, not reinstalled", r[7].get("rc") == "99" and r[7].get("inst") == "1" and r[7].get("skeys") == "3")
    check("link_reset", out[8] == "X ok")
    check("after link_reset the same key counts as new again", r[9].get("rc") == "99" and r[9].get("inst") == "1" and r[9].get("skeys") == "4")
    check("message-2-shaped frame: kind 9, refused", r[10].get("rc") == "-1" and r[10].get("kind") == "9")
    check("truncated frame: kind 9, refused", r[11].get("rc") == "-1" and r[11].get("kind") == "9")
    check("group counter equal to message 3's counter refused (-4)", r[15].get("rc") == "-4" and r[15].get("inst") == "0")
    check("group frame with bad MIC refused (-5), keys unchanged", r[16].get("rc") == "-5" and r[16].get("skeys") == "2")

    # ---- capability summary per network ----
    mcsset = bytes([0xFF, 0xFF, 0, 0, 0, 0, 0, 0, 0, 0]) + struct.pack("<H", 300) + bytes([0, 0, 0, 0])
    htcap = bytes([45, 26]) + struct.pack("<H", 0x0002 | 0x0020 | 0x0040 | 0x0001) + bytes([0x17]) + mcsset + bytes(2 + 4 + 1)
    htop = bytes([61, 22, 36, 0x05]) + bytes(20)
    vhtcap = bytes([191, 12]) + struct.pack("<I", 0x00000020 | 0x1000) + struct.pack("<H", 0xFFFA) + struct.pack("<H", 867) + struct.pack("<H", 0xFFFA) + struct.pack("<H", 867)
    vhtop = bytes([192, 5, 1, 42, 0]) + struct.pack("<H", 0xFFFC)
    ac = htcap + htop + vhtcap + vhtop
    bss1, bss2 = bytes.fromhex("0200000000a1"), bytes.fromhex("0200000000a2")
    bs = [
        S,
        "B -50 " + beacon(b"home", bss1, 36, ac).hex(),
        "B -60 " + beacon(b"home", bss2, 6, b"").hex(),                 # weaker, no capabilities: must not overwrite
        "B -40 " + beacon(b"home", bss2, 6, htcap + htop).hex(),        # stronger, HT 40 MHz only
        "B -70 " + beacon(b"cafe", bss1, 1, b"", privacy=False).hex(),   # legacy
        "B -45 " + beacon(b"he", bss1, 44, ac + bytes([255, 18, 35]) + bytes(17)).hex(),  # HE present
        "B -45 " + beacon(b"bad", bss1, 44, bytes([45, 20]) + bytes(20)).hex(),            # HT element with the wrong length
        "B -45 " + beacon(b"trunc", bss1, 44, ac[:40]).hex()[:-4],                       # cut mid-element
    ]
    o = run(binpath, bs)
    q = [kv(l) for l in o]
    check("oracle printed one line per beacon command", len(o) == len(bs))
    check("beacon with HT+VHT: standard 2 (VHT), width 80, 866.7 Mbit/s (the 8265's 867)",
          q[1].get("ok") == "1" and q[1].get("s0") == "2" and q[1].get("w0") == "80" and abs(int(q[1].get("r0", "0")) - 866667) <= 1)
    check("weaker beacon of the same SSID without capabilities does not overwrite", q[2].get("n") == "1" and q[2].get("r0") == q[1].get("r0") and q[2].get("w0") == "80")
    check("stronger beacon of the same SSID with HT only: standard 1, width 40, 300 Mbit/s",
          q[3].get("n") == "1" and q[3].get("s0") == "1" and q[3].get("w0") == "40" and q[3].get("r0") == "300000")
    check("legacy network: standard 0, width 20, no rate", q[4].get("n") == "2" and q[4].get("s1") == "0" and q[4].get("w1") == "20" and q[4].get("r1") == "0")
    check("HE element present -> standard 3, VHT numbers kept", q[5].get("n") == "3" and q[5].get("ok") == "1")
    check("HT element with the wrong length ignored: standard 0", q[6].get("n") == "4")
    check("beacon cut in the middle of an element: no extra network", q[7].get("n") == q[6].get("n") or q[7].get("ok") == "0")
    print("RESULT pass=%d fail=%d" % (passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
