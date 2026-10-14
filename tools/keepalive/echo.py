#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/keepalive/echo.py -- throw-away echo server for the keepalive gate.
#   echo.py <port>   listens on 127.0.0.1 (the guest sees the host as 10.0.2.2) and echoes every octet.
import socket, sys, threading

def serve(c):
    try:
        while True:
            d = c.recv(4096)
            if not d:
                break
            c.sendall(d)
    except OSError:
        pass
    finally:
        c.close()

s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", int(sys.argv[1])))
s.listen(4)
while True:
    c, _ = s.accept()
    threading.Thread(target=serve, args=(c,), daemon=True).start()
