#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import select
import socket
import sys
import threading
import time

BIG = 65536
CHUNK = 4096
GAP = 0.06


def pattern():
    return bytes(((i * 7 + 3) & 255) for i in range(BIG))


def log(path, text):
    with open(path, "a") as f:
        f.write(text + "\n")


def peer_closed(c):
    r, _, _ = select.select([c], [], [], 0)
    if not r:
        return False
    try:
        return c.recv(64, socket.MSG_PEEK) == b""
    except OSError:
        return True


def serve_big(c, path):
    data = pattern()
    sent = 0
    while sent < BIG:
        if peer_closed(c):
            log(path, "big abort at=%d" % sent)
            return
        c.sendall(data[sent:sent + CHUNK])
        sent += CHUNK
        time.sleep(GAP)
    log(path, "big done")


def serve_hold(c, path):
    c.sendall(b"H")
    log(path, "hold open")
    c.settimeout(300)
    while True:
        try:
            d = c.recv(64)
        except OSError:
            break
        if not d:
            break
        if b"PING" in d:
            c.sendall(b"P")
            log(path, "hold ping")
    log(path, "hold closed")


def handle(c, path):
    try:
        c.settimeout(60)
        line = c.recv(16)
        if line.startswith(b"BIG"):
            serve_big(c, path)
        elif line.startswith(b"HOLD"):
            serve_hold(c, path)
    except OSError as e:
        log(path, "error %s" % e)
    finally:
        c.close()


def udp_echo(u, path):
    while True:
        d, a = u.recvfrom(256)
        u.sendto(d, a)
        log(path, "udp echo %d" % len(d))


def main():
    portfile, path = sys.argv[1], sys.argv[2]
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    while True:
        s.bind(("0.0.0.0", 0))
        port = s.getsockname()[1]
        u = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            u.bind(("0.0.0.0", port + 1))
            break
        except OSError:
            s.close()
            s = socket.socket()
    s.listen(8)
    threading.Thread(target=udp_echo, args=(u, path), daemon=True).start()
    with open(portfile, "w") as f:
        f.write(str(port))
    while True:
        c, _ = s.accept()
        threading.Thread(target=handle, args=(c, path), daemon=True).start()


if __name__ == "__main__":
    main()
