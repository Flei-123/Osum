#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/jarvismini/stub.py -- plain TCP chat stub for JARVIS Mini (W-S5 gate).

    stub.py <port> [bind-address]

Sends one greeting line on connect. Every received line is answered with THREE lines (so the box grows):
`stub: got '<line>'`, `second line of the answer`, `third line of the answer`. Prints `stub: rx <line>` on stdout for the gate.
"""
import socket, sys, threading

def serve(conn):
    conn.sendall(b"Hello, I am the stub.\n")
    buf = b""
    while True:
        d = conn.recv(256)
        if not d:
            return
        buf += d
        while b"\n" in buf:
            ln, buf = buf.split(b"\n", 1)
            print("stub: rx", ln.decode("latin1"), flush=True)
            conn.sendall(("stub: got '%s'\nsecond line of the answer\nthird line of the answer\n" % ln.decode("latin1")).encode("latin1"))

def main():
    port = int(sys.argv[1])
    addr = sys.argv[2] if len(sys.argv) > 2 else "127.0.0.1"
    s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((addr, port)); s.listen(4)
    print("stub: listening", port, flush=True)
    while True:
        c, _ = s.accept()
        threading.Thread(target=serve, args=(c,), daemon=True).start()

main()
