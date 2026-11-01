#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import subprocess
import sys
from cryptography.hazmat.primitives.ciphers.aead import AESCCM

STA = bytes.fromhex("020000000022")
AP = bytes.fromhex("020000000001")
GW = bytes.fromhex("020000000077")
BCAST = bytes([0xFF] * 6)
TK = bytes(range(0x10, 0x20))
GTK = bytes(range(0xA0, 0xB0))
STA_IP = bytes([192, 168, 77, 50])
GW_IP = bytes([192, 168, 77, 1])
SNAP = bytes([0xAA, 0xAA, 0x03, 0, 0, 0])

results = []


def ok(cond, text):
    results.append(bool(cond))
    print(("  OK    " if cond else "  FAIL  ") + text)


def arp(op, sha, spa, tha, tpa):
    return bytes([0, 1, 8, 0, 6, 4, 0, op]) + sha + spa + tha + tpa


def eth(dst, src, etype, payload):
    return dst + src + etype.to_bytes(2, "big") + payload


def plain80211(fc1, a1, a2, a3, etype, payload, qos_tid=None):
    fc0 = 0x88 if qos_tid is not None else 0x08
    hdr = bytes([fc0, fc1, 0, 0]) + a1 + a2 + a3 + bytes([0x30, 0x00])
    if qos_tid is not None:
        hdr += bytes([qos_tid, 0])
    return hdr + SNAP + etype.to_bytes(2, "big") + payload


def ccmp(key, pn, keyid, fc1, a1, a2, a3, etype, payload, qos_tid=None):
    fc0 = 0x88 if qos_tid is not None else 0x08
    seq = bytes([0x30, 0x00])
    hdr = bytes([fc0, fc1 | 0x40, 0, 0]) + a1 + a2 + a3 + seq
    aad = bytes([fc0 & 0x8F, (fc1 & 0xC7) | 0x40]) + a1 + a2 + a3 + bytes([seq[0] & 0x0F, 0])
    prio = 0
    if qos_tid is not None:
        hdr += bytes([qos_tid, 0])
        aad += bytes([qos_tid & 0x0F, 0])
        prio = qos_tid & 0x0F
    pnb = pn.to_bytes(6, "little")
    head = bytes([pnb[0], pnb[1], 0, 0x20 | (keyid << 6), pnb[2], pnb[3], pnb[4], pnb[5]])
    nonce = bytes([prio]) + a2 + pn.to_bytes(6, "big")
    body = SNAP + etype.to_bytes(2, "big") + payload
    return hdr + head + AESCCM(key, tag_length=8).encrypt(nonce, body, aad)


def run(binary, lines):
    p = subprocess.run([binary], input="\n".join(lines) + "\n", capture_output=True, text=True, timeout=30)
    return p.stdout.splitlines()


def rx_expect(line, key, self_bit, eth_frame):
    head, _, rest = line.partition(" m=")
    m, _, tail = rest.partition(" ")
    want_tail = "self=%d eth=%s" % (self_bit, eth_frame.hex() if eth_frame else "-")
    return head == "R key=" + key and m.isdigit() and int(m) > 0 and tail == want_tail


def check_frames(binary):
    who_has = arp(1, STA, STA_IP, bytes(6), GW_IP)
    reply = arp(2, GW, GW_IP, STA, STA_IP)
    gw_asks = arp(1, GW, GW_IP, bytes(6), STA_IP)
    ip_payload = bytes([0x45, 0, 0, 28]) + bytes(range(24))
    echo = ccmp(GTK, 7, 1, 0x02, BCAST, AP, STA, 0x0806, who_has)
    unicast_reply = ccmp(TK, 3, 0, 0x02, STA, AP, GW, 0x0806, reply)
    group_ask = ccmp(GTK, 8, 1, 0x02, BCAST, AP, GW, 0x0806, gw_asks)
    qos_ip = ccmp(TK, 4, 0, 0x02, STA, AP, GW, 0x0800, ip_payload, qos_tid=5)
    group_with_ptk = ccmp(TK, 9, 0, 0x02, BCAST, AP, GW, 0x0806, gw_asks)
    unicast_with_gtk = ccmp(GTK, 10, 1, 0x02, STA, AP, GW, 0x0806, reply)
    lines = [
        "K " + TK.hex() + " " + GTK.hex(),
        "M " + STA.hex(),
        "T " + eth(BCAST, STA, 0x0806, who_has).hex() + " " + AP.hex(),
        "R " + echo.hex(),
        "R " + unicast_reply.hex(),
        "R " + group_ask.hex(),
        "R " + qos_ip.hex(),
        "R " + group_with_ptk.hex(),
        "R " + unicast_with_gtk.hex(),
        "F " + plain80211(0x01, BCAST, STA, STA, 0x0806, who_has).hex(),
        "F " + plain80211(0x02, STA, AP, STA, 0x0806, who_has).hex(),
        "F " + plain80211(0x02, BCAST, STA, AP, 0x0806, who_has).hex(),
        "F " + (bytes([0x80, 0x02, 0, 0]) + BCAST + AP + STA + bytes(2) + bytes(16)).hex(),
        "F " + plain80211(0x02, BCAST, AP, STA, 0x0806, who_has).hex(),
        "K " + TK.hex() + " -",
        "R " + group_ask.hex(),
        "R " + unicast_reply.hex(),
    ]
    out = run(binary, lines)
    if len(out) != len(lines):
        ok(False, "oracle answered %d of %d lines" % (len(out), len(lines)))
        return
    want_tx = bytes([0x08, 0x01, 0, 0]) + AP + STA + BCAST + bytes(2) + SNAP + bytes([0x08, 0x06]) + who_has
    ok(out[2] == "T out=" + want_tx.hex(), "ARP request leaves as ToDS frame to the AP (a1 bssid, a2 own, a3 broadcast)")
    ok(rx_expect(out[3], "gtk", 1, None), "AP echo of the own broadcast: group key, recognised as echo, not delivered")
    ok(rx_expect(out[4], "ptk", 0, eth(STA, GW, 0x0806, reply)), "unicast ARP reply: pairwise key, delivered as Ethernet")
    ok(rx_expect(out[5], "gtk", 0, eth(BCAST, GW, 0x0806, gw_asks)), "gateway broadcast who-has: group key, delivered")
    ok(rx_expect(out[6], "ptk", 0, eth(STA, GW, 0x0800, ip_payload)), "QoS unicast IPv4: QoS header skipped, delivered")
    ok(out[7].startswith("R key=gtk m=-1 "), "group frame sealed with the pairwise key is rejected")
    ok(out[8].startswith("R key=ptk m=-1 "), "unicast frame sealed with the group key is rejected")
    ok(out[9] == "F self=0", "ToDS frame with own address in a3 is no echo")
    ok(out[10] == "F self=0", "FromDS unicast with own address in a3 is no echo")
    ok(out[11] == "F self=0", "own address in a2 (not the source) is no echo")
    ok(out[12] == "F self=0", "management frame is no echo")
    ok(out[13] == "F self=1", "plain FromDS broadcast with own source in a3 is an echo")
    ok(out[15] == "R key=none m=-1 self=0 eth=-", "group frame before the group key is installed is dropped")
    ok(rx_expect(out[16], "ptk", 0, eth(STA, GW, 0x0806, reply)), "unicast still works without group key")


def check_ring(binary):
    frames = [bytes([0x10 + i]) * (60 + i) for i in range(24)]
    lines = ["L 1"] + ["O " + f.hex() for f in frames[:3]] + ["S"] + ["G"] * 4
    lines += ["O " + f.hex() for f in frames] + ["S"] + ["G"] * 24 + ["S"]
    lines += ["D 8"] + ["O " + f.hex() for f in frames[:9]] + ["S", "A 5 0", "A 5 0", "A 6 0", "A 6 1"]
    lines += ["G"] * 8 + ["S", "A 7 1", "A 7 0"]
    lines += ["D 1", "O " + frames[0].hex(), "O " + frames[1].hex(), "S", "G", "G"]
    lines += ["D 8", "O " + frames[2].hex(), "O " + frames[3].hex(), "L 0", "L 1", "S"]
    out = run(binary, lines)
    if len(out) != len(lines):
        ok(False, "ring oracle answered %d of %d lines" % (len(out), len(lines)))
        return
    i = 1
    ok(out[i:i + 3] == ["O ok=1"] * 3, "burst of 3 frames (echo + replies) all accepted")
    ok(out[4] == "S queued=3 drops=0 free=1 poll=1", "3 frames queued, no drop")
    got = out[5:8]
    ok(got == ["G n=%d data=%s" % (len(f), f.hex()) for f in frames[:3]], "frames come out in arrival order")
    ok(out[8] == "G n=0 data=-", "ring empty after 3 takes")
    i = 9
    ok(out[i:i + 24] == ["O ok=1"] * 24, "burst of 24 frames while the stack is not draining: all accepted")
    ok(out[i + 24] == "S queued=24 drops=0 free=1 poll=1", "24 frames queued, no drop, ring still free")
    i = i + 25
    ok(out[i:i + 24] == ["G n=%d data=%s" % (len(f), f.hex()) for f in frames], "24 queued frames come out in order")
    ok(out[i + 24] == "S queued=0 drops=0 free=1 poll=0", "ring empty and free again")
    i = i + 25
    ok(out[i] == "D ok", "depth 8 selected")
    ok(out[i + 1:i + 9] == ["O ok=1"] * 8 and out[i + 9] == "O ok=0", "9th frame is refused when 8 are queued")
    ok(out[i + 10] == "S queued=8 drops=1 free=0 poll=1", "overflow counted as drop, ring reports full")
    ok(out[i + 11:i + 15] == ["A ok=1", "A ok=0", "A ok=1", "A ok=0"], "full ring: one liveness read per second, none in legacy mode")
    i = i + 15
    ok(out[i:i + 8] == ["G n=%d data=%s" % (len(f), f.hex()) for f in frames[:8]], "8 queued frames come out in order")
    ok(out[i + 8] == "S queued=0 drops=1 free=1 poll=0", "ring empty and free again after the overflow")
    ok(out[i + 9:i + 11] == ["A ok=1", "A ok=1"], "free ring: reads allowed in both modes")
    i = i + 11
    ok(out[i] == "D ok" and out[i + 1] == "O ok=1" and out[i + 2] == "O ok=0", "depth 1: second frame refused (old single-slot behaviour)")
    ok(out[i + 3] == "S queued=1 drops=2 free=0 poll=1", "depth 1: drop counted")
    ok(out[i + 4] == "G n=%d data=%s" % (len(frames[0]), frames[0].hex()) and out[i + 5] == "G n=0 data=-", "depth 1: first frame kept")
    i = i + 6
    ok(out[i + 5] == "S queued=0 drops=2 free=1 poll=0", "link down empties the ring")


def main():
    binary = sys.argv[1]
    check_frames(binary)
    check_ring(binary)
    bad = results.count(False)
    print("RESULT pass=%d fail=%d" % (len(results) - bad, bad))
    sys.exit(1 if bad else 0)


main()
