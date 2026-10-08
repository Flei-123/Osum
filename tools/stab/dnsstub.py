#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Tiny DNS stub for tools/stab/net.sh: every A query is answered with one address.

    dnsstub.py <address> <port>

Runs inside the private network namespace of the test, where the guest (QEMU
user networking) reaches the host loopback as 10.0.2.2.
"""
import socket
import struct
import sys

addr = socket.inet_aton(sys.argv[1])
port = int(sys.argv[2]) if len(sys.argv) > 2 else 53
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(("127.0.0.1", port))
while True:
    data, peer = s.recvfrom(512)
    if len(data) < 12:
        continue
    qend = 12
    while qend < len(data) and data[qend] != 0:
        qend += data[qend] + 1
    qend += 5  # root label + type + class
    question = data[12:qend]
    qtype = struct.unpack(">H", data[qend - 4:qend - 2])[0]
    flags = 0x8180
    if qtype == 1:
        ans = b"\xc0\x0c" + struct.pack(">HHIH", 1, 1, 60, 4) + addr
        resp = data[:2] + struct.pack(">HHHHH", flags, 1, 1, 0, 0) + question + ans
    else:
        resp = data[:2] + struct.pack(">HHHHH", flags, 1, 0, 0, 0) + question
    s.sendto(resp, peer)
