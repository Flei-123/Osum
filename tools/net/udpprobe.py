#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/net/udpprobe.py -- round K8: UDP, and a counter-check inside it.

Five datagrams of 1400 octets each. Osum sends them back REVERSED, not
merely echoed -- so a wire that mirrored frames, or a stack that answered
without ever looking at the payload, would fail this and an echo test
would not.

    udpprobe.py <a.b.c.d> <port>
"""
import socket, sys
host, port = sys.argv[1], int(sys.argv[2])
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(8)
ok = 0
for i in range(5):
    msg = bytes(((i * 37 + j) & 0xFF) for j in range(1400))
    s.sendto(msg, (host, port))
    try:
        d, a = s.recvfrom(4096)
    except Exception:
        print("timeout on", i)
        continue
    if d == msg[::-1]:
        ok += 1
    else:
        print("mismatch on", i, len(d))
print("udp_ok", ok)
