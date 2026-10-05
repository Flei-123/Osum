#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""wol.py -- send a Wake-on-LAN magic packet.

    wol.py <mac> [--broadcast 192.168.178.255 ...] [--port 9] [--count 3] [--from-ip 192.168.178.50]

Run it on a machine that sits in the SAME network (same broadcast domain) as the
machine to wake. A packet sent from the JARVIS server in another house never arrives:
the Dell and the server are in different home networks (see docs/BRIDGE-OFFLINE.md).

The magic packet is 6 x 0xFF followed by the MAC 16 times. It goes out as UDP to ports 9 and 7
(the two usual ones), to every --broadcast address (default 255.255.255.255).
Windows (PowerShell, no Python needed):

    $mac='AA:BB:CC:DD:EE:FF'; $b=[byte[]](,0xFF*6)+([byte[]]($mac -split '[:-]' | % {[Convert]::ToByte($_,16)})*16)
    $u=New-Object Net.Sockets.UdpClient; $u.EnableBroadcast=$true; $u.Send($b,$b.Length,'255.255.255.255',9) | Out-Null
"""
import argparse, re, socket, sys


def magic_packet(mac):
    h = re.sub(r"[^0-9a-fA-F]", "", mac)
    if len(h) != 12:
        raise ValueError("a MAC has 12 hex digits")
    return b"\xff" * 6 + bytes.fromhex(h) * 16


def send(mac, targets, port=9, count=3, from_ip=None):
    pk = magic_packet(mac)
    sent = []
    for t in targets:
        for p in sorted({port, 7}):
            for _ in range(count):
                s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                try:
                    s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
                    if from_ip:
                        s.bind((from_ip, 0))
                    s.sendto(pk, (t, p))
                except OSError as e:
                    sent.append("%s:%d ERROR %s" % (t, p, e))
                    break
                finally:
                    s.close()
            else:
                sent.append("%s:%d x%d" % (t, p, count))
    return sent


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("mac")
    ap.add_argument("--broadcast", action="append", default=[])
    ap.add_argument("--port", type=int, default=9)
    ap.add_argument("--count", type=int, default=3)
    ap.add_argument("--from-ip", default=None)
    a = ap.parse_args()
    try:
        out = send(a.mac, a.broadcast or ["255.255.255.255"], a.port, a.count, a.from_ip)
    except ValueError as e:
        print("error:", e)
        return 2
    print("\n".join(out))
    return 1 if any("ERROR" in x for x in out) else 0


if __name__ == "__main__":
    sys.exit(main())
