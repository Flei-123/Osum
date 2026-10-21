#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/wlan/lw2.py -- LW-2 gate: group key rekey (lib/wlan/groupkey.fi) against an independent Python model.

usage: python3 -I tools/wlan/lw2.py <path to lw2 oracle binary>
Frames are built with hashlib/hmac and `cryptography` (RFC 3394 key wrap, AES-CMAC), never with the Firn code.
Exit 0 = all checks OK.
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


def mic_of(kck, akm, frame):
    z = frame[:81] + b"\0" * 16 + frame[97:]
    if akm in (5, 6, 8, 9, 18):  # SHA-256 based AKMs use AES-CMAC
        c = cmac.CMAC(algorithms.AES(kck))
        c.update(z)
        return c.finalize()
    return hmac.new(kck, z, hashlib.sha1).digest()[:16]


def eapol(ptk, akm, counter, data=b"", ki=None, ver=2, corrupt_mic=False):
    if ki is None:
        ki = 0x1380 | ver  # group, ACK, MIC, Secure, Encrypted key data
    body = (bytes([2]) + struct.pack(">HH", ki, 0) + struct.pack(">Q", counter)
            + b"\x11" * 32 + b"\0" * 16 + b"\0" * 8 + b"\0" * 8 + b"\0" * 16
            + struct.pack(">H", len(data)) + data)
    fr = bytes([2, 3]) + struct.pack(">H", len(body)) + body
    mic = mic_of(ptk[:16], akm, fr)
    if corrupt_mic:
        mic = bytes([mic[0] ^ 1]) + mic[1:]
    return fr[:81] + mic + fr[97:]


def kde(idx, gtk):
    return bytes([0xDD, 4 + 2 + len(gtk), 0x00, 0x0F, 0xAC, 0x01, idx & 3, 0]) + gtk


def pad8(b):
    if len(b) % 8:
        b = b + b"\xdd" + b"\0" * ((8 - (len(b) + 1) % 8) % 8)
    return b


def wrapped(ptk, idx, gtk, kek=None):
    return aes_key_wrap(kek or ptk[16:32], pad8(kde(idx, gtk)))


def expect_m2(ptk, akm, m1):
    ver = m1[6] & 7
    ki = ver | 0x300
    body = (bytes([m1[4]]) + struct.pack(">HH", ki, 0) + m1[9:17] + b"\0" * 32 + b"\0" * 16
            + b"\0" * 8 + b"\0" * 8 + b"\0" * 16 + b"\0\0")
    fr = bytes([m1[0], 3]) + struct.pack(">H", len(body)) + body
    return fr[:81] + mic_of(ptk[:16], akm, fr) + fr[97:]


def run(binpath, script):
    r = subprocess.run([binpath], input=script.encode(), capture_output=True, timeout=60)
    return r.stdout.decode().splitlines()


def parse(line):
    d = {}
    for kv in line.split()[1:]:
        if "=" in kv:
            k, v = kv.split("=", 1)
            d[k] = v
    return d


def main():
    binpath = sys.argv[1]

    def rnd(n, s):
        return hashlib.sha256(s.encode()).digest()[:n]

    ptk = rnd(32, "ptk-a") + rnd(16, "ptk-a2")
    gA, gB, gC, gD = rnd(16, "gA"), rnd(16, "gB"), rnd(16, "gC"), rnd(16, "gD")
    cmds = []  # (script line, tag)

    def S(p, akm=2, conn=1):
        cmds.append(("S " + p.hex() + " %d %d" % (akm, conn), "S"))

    def N(fr):
        cmds.append(("N " + fr.hex(), "N"))

    def R(fr, tag):
        cmds.append(("R " + fr.hex(), tag))

    # ---- session 1: normal rekey life ----
    S(ptk)
    N(eapol(ptk, 2, 2, ki=0x13C8 | 2))
    f_a = eapol(ptk, 2, 3, wrapped(ptk, 1, gA))
    R(f_a, "a")
    R(f_a, "b")                                           # exact replay
    R(eapol(ptk, 2, 2, wrapped(ptk, 1, gA)), "c")         # older counter, valid MIC
    R(eapol(ptk, 2, 4, wrapped(ptk, 2, gB), corrupt_mic=True), "d")
    f_e = eapol(ptk, 2, 4, wrapped(ptk, 2, gB))
    R(f_e, "e")
    R(eapol(ptk, 2, 5, wrapped(ptk, 2, gB)), "f")         # same key again: answered, not reinstalled
    R(eapol(ptk, 2, 6, wrapped(ptk, 2, gC)), "g")         # same id, new key: installed
    R(eapol(ptk, 2, 7, wrapped(ptk, 3, gD, kek=rnd(16, "wrongkek"))), "h")
    R(eapol(ptk, 2, 7, wrapped(ptk, 3, gD)), "i")         # counter 7 was not consumed by the failure
    R(eapol(ptk, 2, 8, wrapped(ptk, 0, gA)), "j")         # 5th key: device table full -> refused
    # ---- other sessions ----
    S(ptk, 2, 0)
    R(eapol(ptk, 2, 3, wrapped(ptk, 1, gA)), "k")         # not connected
    S(ptk)
    R(eapol(ptk, 2, 3, wrapped(ptk, 1, gA), ki=0x13C8 | 2), "l")  # pairwise bit set
    S(ptk)
    other = bytes([0xDD, 14, 0x00, 0x0F, 0xAC, 0x04]) + b"\x55" * 16  # PMKID KDE, no GTK
    R(eapol(ptk, 2, 3, aes_key_wrap(ptk[16:32], pad8(other))), "m")
    S(ptk)
    R(f_a[:60], "n")                                      # truncated
    S(ptk)
    N(eapol(ptk, 2, 10, ki=0x13C8 | 2))
    R(eapol(ptk, 2, 10, wrapped(ptk, 1, gA)), "o")
    R(eapol(ptk, 2, 11, wrapped(ptk, 1, gA)), "p")
    S(ptk, 6)
    f_q = eapol(ptk, 6, 3, wrapped(ptk, 1, gA), ver=3)
    R(f_q, "q")                                           # AKM 6 / AES-CMAC
    S(ptk)
    w = bytearray(wrapped(ptk, 1, gA))
    w[5] ^= 0x40
    R(eapol(ptk, 2, 3, bytes(w)), "r")                    # damaged key data, MIC recomputed over it
    S(ptk)
    R(eapol(ptk, 2, 3, wrapped(ptk, 1, gA), ki=(0x1380 & ~0x80) | 2), "s")  # no ACK bit
    S(ptk)
    R(eapol(ptk, 2, 3, wrapped(ptk, 1, gA + gB)), "t")    # 32 octet group key (not CCMP-128)
    S(ptk)
    R(eapol(ptk, 2, 3, wrapped(ptk, 1, gA), ki=(0x1380 & ~0x1000) | 2), "u")  # key data not marked encrypted

    out = run(binpath, "\n".join(c[0] for c in cmds) + "\n")
    check("oracle printed one line per command", len(out) == len(cmds))
    res = {}
    for (script, tag), line in zip(cmds, out):
        if tag not in ("S", "N"):
            d = parse(line)
            d["m2"] = d.get("m2", "-")
            res[tag] = d

    def ok(t, **kw):
        return t in res and all(res[t].get(k) == str(v) for k, v in kw.items())

    check("a accepted: rc=99 inst=1 keys=1 id=1", ok("a", rc=99, inst=1, skeys=1, kid=1, err=0))
    check("a GTK is the new key", res["a"]["gtk"] == gA.hex())
    check("a message 2 == model (MIC, flags, counter echoed)", res["a"]["m2"] == expect_m2(ptk, 2, f_a).hex())
    check("b exact replay rejected (-4), nothing installed", ok("b", rc=-4, inst=1, skeys=1, err=4))
    check("c older counter with valid MIC rejected", ok("c", rc=-4, inst=1, skeys=1))
    check("d bad MIC rejected (-5), no key", ok("d", rc=-5, inst=1, skeys=1, err=5) and res["d"]["gtk"] == gA.hex())
    check("e counter 4 after the bad-MIC try accepted", ok("e", rc=99, inst=2, skeys=2, kid=2) and res["e"]["gtk"] == gB.hex())
    check("e message 2 == model", res["e"]["m2"] == expect_m2(ptk, 2, f_e).hex())
    check("f same key again: answered but NOT reinstalled", ok("f", rc=99, inst=2, skeys=2, kid=2))
    check("g same key id, new octets: installed", ok("g", rc=99, inst=3, skeys=3, kid=2) and res["g"]["gtk"] == gC.hex())
    check("h wrong KEK (valid MIC): unwrap error -6, no change", ok("h", rc=-6, inst=3, skeys=3, err=6) and res["h"]["gtk"] == gC.hex())
    check("i same counter as the failed h is still usable", ok("i", rc=99, inst=4, skeys=4, kid=3) and res["i"]["gtk"] == gD.hex())
    check("j device refuses (table full): -8, session GTK unchanged", ok("j", rc=-8, inst=4, skeys=4, err=8) and res["j"]["gtk"] == gD.hex())
    check("k not connected: -1, nothing installed", ok("k", rc=-1, inst=0, skeys=0, err=1))
    check("l pairwise (message 3 shaped) frame is not a group message", ok("l", rc=-3, inst=0, skeys=0, err=3))
    check("m key data without GTK KDE: -7", ok("m", rc=-7, inst=0, skeys=0, err=7))
    check("n truncated frame: -2", ok("n", rc=-2, inst=0, skeys=0, err=2))
    check("o counter equal to pairwise message 3 counter: -4", ok("o", rc=-4, inst=0, skeys=0, err=4))
    check("p counter above message 3 counter: accepted", ok("p", rc=99, inst=1, skeys=1))
    check("q AKM 6 (AES-CMAC, version 3) accepted, message 2 == model",
          ok("q", rc=99, inst=1) and res["q"]["m2"] == expect_m2(ptk, 6, f_q).hex())
    check("r damaged wrapped key data: -6 (RFC 3394 integrity)", ok("r", rc=-6, inst=0, skeys=0))
    check("s frame without ACK is not group message 1", ok("s", rc=-3, inst=0, skeys=0))
    check("t 32 octet key: -7 (CCMP-128 only)", ok("t", rc=-7, inst=0, skeys=0))
    check("u key data not marked encrypted: -3", ok("u", rc=-3, inst=0, skeys=0))

    # ---- capability elements (lib/wlan/caps.fi): an 8265-like 2x2 AC access point ----
    mcsset = bytes([0xFF, 0xFF, 0, 0, 0, 0, 0, 0, 0, 0]) + struct.pack("<H", 300) + bytes([0, 0, 0, 0])
    htcap = bytes([45, 26]) + struct.pack("<H", 0x0002 | 0x0020 | 0x0040 | 0x0001) + bytes([0x17]) + mcsset + bytes(2 + 4 + 1)
    htop = bytes([61, 22, 36, 0x05]) + bytes(20)
    vhtcap = bytes([191, 12]) + struct.pack("<I", 0x00000020 | 0x1000) + struct.pack("<H", 0xFFFA) + struct.pack("<H", 867) + struct.pack("<H", 0xFFFA) + struct.pack("<H", 867)
    vhtop = bytes([192, 5, 1, 42, 0]) + struct.pack("<H", 0xFFFC)
    ies = htcap + htop + vhtcap + vhtop
    o2 = run(binpath, "C " + ies.hex() + "\nC " + ies[:len(ies) - 3].hex() + "\nP " + ies[:len(ies) - 3].hex() + "\nC " + (bytes([45, 20]) + bytes(20) + htop).hex() + "\n")
    d = parse(o2[0]) if o2 else {}
    check("caps: 4 elements recognised", d.get("seen") == "4" and d.get("bad") == "0" and d.get("rc") == "4")
    check("caps: HT 40 MHz + SGI + LDPC + 2 streams", d.get("w40") == "1" and d.get("sgi20") == "1" and d.get("sgi40") == "1" and d.get("ldpc") == "1" and d.get("nss") == "2" and d.get("rx") == "300" and d.get("ampdu") == "3")
    check("caps: HT operation primary 36, secondary above, 40 allowed", d.get("prim") == "36" and d.get("off") == "1" and d.get("opw40") == "1")
    check("caps: VHT 80 MHz SGI, MCS 0-9 on 2 streams, stream 3 absent", d.get("vht") == "1" and d.get("sgi80") == "1" and d.get("w160") == "0" and d.get("vnss") == "2" and d.get("mcs") == "22333333" and d.get("subf") == "1")
    check("caps: VHT operation 80 MHz, centre 42", d.get("vop") == "1" and d.get("vw") == "1" and d.get("seg0") == "42")
    check("caps: HT 2x2 40 MHz SGI = 300 Mbps (spec table MCS15)", d.get("ht40") == "300000" and abs(int(d.get("ht20", "0")) - 144444) <= 1)
    check("caps: VHT 2x2 80 MHz SGI = 866.7 Mbps (the 8265's 867), long GI 780 Mbps", abs(int(d.get("v80", "0")) - 866667) <= 1 and d.get("v80l") == "780000")
    check("caps: best rate at 20/40/80 MHz", d.get("b80") == d.get("v80") and int(d.get("b40", "0")) == 400000 and abs(int(d.get("b20", "0")) - 173332) <= 2)
    check("caps: VHT 20 MHz drops MCS 9 for 2 streams (2 x 86.7 -> 2 x 78 Mbps)", abs(int(d.get("v20", "0")) - 173332) <= 2)
    d2 = parse(o2[1]) if len(o2) > 1 else {}
    d3 = parse(o2[2]) if len(o2) > 2 else {}
    check("caps: truncated blob -> rc -1, earlier elements kept, rest absent", d2.get("rc") == "-1" and d2.get("ht") == "1" and d2.get("vop") == "0")
    check("caps: result independent of the octets beyond the blob (poison A5 vs 5A)", len(o2) > 2 and o2[1] == o2[2])
    d4 = parse(o2[3]) if len(o2) > 3 else {}
    check("caps: HT element with wrong length counted bad, ignored", d4.get("ht") == "0" and d4.get("bad") == "1" and d4.get("op") == "1")
    print("RESULT pass=%d fail=%d" % (passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
