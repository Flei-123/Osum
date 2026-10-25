#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import argparse
import socket
import struct
import sys
import time

GW_MAC = bytes.fromhex("525400112233")
GW_IP = bytes([192, 168, 1, 1])
LEASE_IP = bytes([192, 168, 1, 50])
BCAST = b"\xff" * 6


def checksum(data):
    if len(data) % 2:
        data += b"\0"
    total = sum(struct.unpack("!%dH" % (len(data) // 2), data))
    while total >> 16:
        total = (total & 0xFFFF) + (total >> 16)
    return (~total) & 0xFFFF


def ip_packet(src, dst, proto, payload):
    head = struct.pack("!BBHHHBBH4s4s", 0x45, 0, 20 + len(payload), 0, 0, 64, proto, 0, src, dst)
    head = head[:10] + struct.pack("!H", checksum(head)) + head[12:]
    return head + payload


def eth(dst, src, kind, payload):
    return dst + src + struct.pack("!H", kind) + payload


def dhcp_reply(request, kind, mask):
    xid = request[4:8]
    chaddr = request[28:34]
    body = struct.pack("!BBBB4sHH4s4s4s4s", 2, 1, 6, 0, xid, 0, 0x8000, b"\0" * 4, LEASE_IP, GW_IP, b"\0" * 4)
    body += chaddr + b"\0" * 10 + b"\0" * 64 + b"\0" * 128 + b"\x63\x82\x53\x63"
    opts = bytes([53, 1, kind, 54, 4]) + GW_IP + bytes([51, 4]) + struct.pack("!I", 3600)
    opts += bytes([1, 4]) + mask + bytes([3, 4]) + GW_IP + bytes([6, 4]) + GW_IP + b"\xff"
    udp = struct.pack("!HHHH", 67, 68, 8 + len(body) + len(opts), 0) + body + opts
    return eth(BCAST, GW_MAC, 0x0800, ip_packet(GW_IP, b"\xff" * 4, 17, udp))


def dhcp_kind(frame):
    opts = frame[14 + 20 + 8 + 240:]
    i = 0
    while i + 1 < len(opts) and opts[i] != 255:
        if opts[i] == 0:
            i += 1
            continue
        if opts[i] == 53:
            return opts[i + 2]
        i += 2 + opts[i + 1]
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--local", type=int, required=True)
    ap.add_argument("--remote", type=int, required=True)
    ap.add_argument("--mask", default="255.255.255.0")
    ap.add_argument("--log", required=True)
    ap.add_argument("--secs", type=int, default=150)
    ap.add_argument("--no-echo", action="store_true")
    a = ap.parse_args()
    mask = bytes(int(x) for x in a.mask.split("."))
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("127.0.0.1", a.local))
    sock.settimeout(0.5)
    out = ("127.0.0.1", a.remote)
    log = open(a.log, "w", buffering=1)
    end = time.time() + a.secs
    while time.time() < end:
        try:
            frame, _ = sock.recvfrom(2048)
        except socket.timeout:
            continue
        if len(frame) < 34:
            continue
        kind = struct.unpack("!H", frame[12:14])[0]
        src_mac = frame[6:12]
        if kind == 0x0806 and len(frame) >= 42:
            op = struct.unpack("!H", frame[20:22])[0]
            spa, tpa = frame[28:32], frame[38:42]
            if op == 1 and tpa == GW_IP:
                log.write("ARP-GW-ASK from %s\n" % ".".join(map(str, spa)))
                reply = struct.pack("!HHBBH", 1, 0x0800, 6, 4, 2) + GW_MAC + GW_IP + src_mac + spa
                sock.sendto(eth(src_mac, GW_MAC, 0x0806, reply), out)
            elif op == 1:
                log.write("ARP-OTHER-ASK %s\n" % ".".join(map(str, tpa)))
        elif kind == 0x0800:
            proto = frame[23]
            dst_ip = frame[30:34]
            src_ip = frame[26:30]
            if proto == 17 and frame[14 + 20 + 2:14 + 20 + 4] == b"\x00\x43":
                k = dhcp_kind(frame)
                if k in (1, 3):
                    log.write("DHCP %s mask=%s\n" % ("DISCOVER" if k == 1 else "REQUEST", a.mask))
                    sock.sendto(dhcp_reply(frame[14 + 20 + 8:], 2 if k == 1 else 5, mask), out)
            elif proto == 1 and frame[34] == 8:
                via_gw = frame[0:6] == GW_MAC
                log.write("ECHO dst=%s via_gw=%d\n" % (".".join(map(str, dst_ip)), 1 if via_gw else 0))
                if via_gw and not a.no_echo:
                    icmp = bytearray(frame[34:14 + struct.unpack("!H", frame[16:18])[0]])
                    icmp[0] = 0
                    icmp[2:4] = b"\0\0"
                    icmp[2:4] = struct.pack("!H", checksum(bytes(icmp)))
                    sock.sendto(eth(src_mac, GW_MAC, 0x0800, ip_packet(dst_ip, src_ip, 1, bytes(icmp))), out)
    log.write("PEER-END\n")


if __name__ == "__main__":
    sys.exit(main())
