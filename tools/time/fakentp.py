#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/time/fakentp.py -- an NTP server that says what the test wants.

    fakentp.py --port 12300 --log f --time 2026-10-02T12:00:00Z [more times...]
                [--mode ok|spoof|kod|li3|short|wrongmode]

Every request is answered with the NEXT time of the list (the last one
repeats). Modes are the faulty answers the client must refuse:

    ok         a good answer (mode 4, stratum 2, originate echoed)
    spoof      the originate field is NOT the client's nonce
    kod        stratum 0 (kiss-o'-death)
    li3        leap indicator 3 (server clock unsynchronised)
    short      a 40-octet packet
    wrongmode  mode 3 instead of 4

The log gets one line per request: `REQ n time=<unix> mode=<mode>`.
"""
import calendar
import socket
import struct
import sys
import time

NTP_UNIX = 2208988800


def parse(t):
    return calendar.timegm(time.strptime(t, "%Y-%m-%dT%H:%M:%SZ"))


def main():
    port = 12300
    log = None
    mode = "ok"
    times = []
    a = sys.argv[1:]
    i = 0
    while i < len(a):
        if a[i] == "--port":
            port = int(a[i + 1]); i += 2
        elif a[i] == "--log":
            log = a[i + 1]; i += 2
        elif a[i] == "--mode":
            mode = a[i + 1]; i += 2
        elif a[i] == "--time":
            i += 1
            while i < len(a) and not a[i].startswith("--"):
                times.append(parse(a[i])); i += 1
        else:
            i += 1
    if not times:
        times = [int(time.time())]
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("127.0.0.1", port))
    lf = open(log, "a", buffering=1) if log else sys.stdout
    lf.write("START port=%d mode=%s times=%d\n" % (port, mode, len(times)))
    n = 0
    while True:
        data, addr = s.recvfrom(512)
        if len(data) < 48:
            continue
        t = times[min(n, len(times) - 1)]
        n += 1
        li, vn, md, st = 0, 4, 4, 2
        if mode == "kod":
            st = 0
        if mode == "li3":
            li = 3
        if mode == "wrongmode":
            md = 3
        first = (li << 6) | (vn << 3) | md
        origin = data[40:48]
        if mode == "spoof":
            origin = bytes(b ^ 0xFF for b in origin)
        secs = (t + NTP_UNIX) & 0xFFFFFFFF  # 32 bits: era 1 starts in 2036
        pkt = struct.pack("!BBBb", first, st, 6, -20) + struct.pack("!II", 0, 0) \
            + struct.pack("!I", 0x4C4F434C) + struct.pack("!II", secs, 0) \
            + origin + struct.pack("!II", secs, 0) + struct.pack("!II", secs, 0)
        if mode == "short":
            pkt = pkt[:40]
        s.sendto(pkt, addr)
        lf.write("REQ %d time=%d mode=%s\n" % (n, t, mode))


if __name__ == "__main__":
    main()
