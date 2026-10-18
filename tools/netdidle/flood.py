#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/netdidle/flood.py -- background chatter on a QEMU `-netdev dgram` link.

    flood.py <qemu-local-port> <frames-per-second> <seconds> [<source-port>]

QEMU connect()s its datagram socket to the `remote` address, so frames from any other
source port are silently dropped (this is why the first gate saw rx_f=0): the sender
must bind the very port QEMU was given as `remote.port` / `udp=`.

Sends broadcast ARP requests (the kind a bridged VirtualBox NIC sees all day:
ARP, mDNS, SSDP) as raw Ethernet frames, one UDP datagram each.
"""
import socket
import struct
import sys
import time


def frame(i):
    src = bytes([0x02, 0x00, 0x00, 0x00, (i >> 8) & 0xFF, i & 0xFF])
    eth = b"\xff" * 6 + src + b"\x08\x06"
    arp = struct.pack("!HHBBH", 1, 0x0800, 6, 4, 1) + src + bytes([10, 0, 2, 100 + (i % 100)]) + b"\x00" * 6 + bytes([10, 0, 2, 15])
    return (eth + arp).ljust(60, b"\x00")


def main():
    port, fps, secs = int(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3])
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    if len(sys.argv) > 4:
        s.bind(("127.0.0.1", int(sys.argv[4])))
    end = time.time() + secs
    i = 0
    while time.time() < end:
        s.sendto(frame(i), ("127.0.0.1", port))
        i += 1
        time.sleep(1.0 / fps)
    print("sent %d frames" % i)


main()
