#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/fvviewer/tlsterm.py -- minimal TLS terminator for the GUI gate: tlsterm.py <listen-port> <target-port> <cert.pem> <key.pem>
# (socat 1.7.4 pins the ECDH group and refuses the x25519-only ClientHello of the Firn TLS client: "no suitable key share")
import socket, ssl, sys, threading

def pump(a, b):
    try:
        while True:
            d = a.recv(65536)
            if not d:
                break
            b.sendall(d)
    except (OSError, ssl.SSLError):
        pass
    for s in (a, b):
        try:
            s.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass

def serve(c, ctx, target):
    try:
        t = ctx.wrap_socket(c, server_side=True)
        u = socket.create_connection(("127.0.0.1", target))
    except (OSError, ssl.SSLError) as e:
        sys.stderr.write("tlsterm: %s\n" % e); sys.stderr.flush()
        c.close(); return
    threading.Thread(target=pump, args=(t, u), daemon=True).start()
    pump(u, t)

def main():
    lp, tp, cert, key = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3], sys.argv[4]
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_3
    ctx.load_cert_chain(cert, key)
    ls = socket.socket(); ls.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    ls.bind(("127.0.0.1", lp)); ls.listen(16)
    while True:
        c, _ = ls.accept()
        threading.Thread(target=serve, args=(c, ctx, tp), daemon=True).start()

main()
