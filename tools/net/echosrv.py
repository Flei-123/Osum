#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/net/echosrv.py -- round K8: the Linux end of the active test.

Osum opens the connection for once, and this is what it opens it to: an
ordinary python socket on the Linux kernel, which sends back exactly
what it was given. `run.sh` reads the two lines it prints -- the peer
(which has to be Osum with an ephemeral port of its own) and how many
octets went through.

    echosrv.py <port> [octets, then it stops]
"""
import socket, sys
port = int(sys.argv[1])
limit = int(sys.argv[2]) if len(sys.argv) > 2 else 0
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("0.0.0.0", port))
s.listen(4)
s.settimeout(120)
try:
    c, a = s.accept()
except Exception as e:
    print("no connection:", e, flush=True)
    sys.exit(1)
print("peer", a, flush=True)
c.settimeout(120)
total = 0
try:
    while True:
        d = c.recv(65536)
        if not d:
            break
        c.sendall(d)
        total += len(d)
        if limit and total >= limit:
            break
except Exception as e:
    print("err", e, flush=True)
print("echoed", total, flush=True)
try:
    c.shutdown(socket.SHUT_WR)
except Exception:
    pass
c.close()
s.close()
