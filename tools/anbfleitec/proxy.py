#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/anbfleitec/proxy.py -- TLS 1.3 terminator in front of the REAL broker.

    proxy.py --listen 10.9.0.1:8443 --to 127.0.0.1:18470 --cert good.pem
             --key good.key --log DIR

fleitec-id speaks plain HTTP on loopback; the OrientOS client only speaks
HTTPS. This proxy splices the decrypted bytes both ways and writes them to
DIR/c2s.log (client -> broker) and DIR/s2c.log (broker -> client), so that
interop.sh can read the tokens the broker handed out (host side only) and see
which calls reached it (e.g. POST /oidc/revoke). It changes nothing.
"""
import argparse
import socket
import ssl
import threading


def pump(src, dst, path, lock):
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            with lock:
                with open(path, "ab") as f:
                    f.write(data)
            dst.sendall(data)
    except OSError:
        pass
    finally:
        for s in (src, dst):
            try:
                s.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass


def handle(conn, target, logdir, lock):
    try:
        up = socket.create_connection(target, timeout=10)
    except OSError:
        conn.close()
        return
    t1 = threading.Thread(target=pump, args=(conn, up, logdir + "/c2s.log", lock), daemon=True)
    t2 = threading.Thread(target=pump, args=(up, conn, logdir + "/s2c.log", lock), daemon=True)
    t1.start(); t2.start()
    t1.join(); t2.join()
    conn.close(); up.close()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--listen", required=True)
    ap.add_argument("--to", required=True)
    ap.add_argument("--cert", required=True)
    ap.add_argument("--key", required=True)
    ap.add_argument("--log", required=True)
    a = ap.parse_args()
    lh, lp = a.listen.rsplit(":", 1)
    th, tp = a.to.rsplit(":", 1)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_3
    ctx.load_cert_chain(a.cert, a.key)
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((lh, int(lp)))
    srv.listen(16)
    lock = threading.Lock()
    while True:
        c, _ = srv.accept()
        try:
            c = ctx.wrap_socket(c, server_side=True)
        except (ssl.SSLError, OSError):
            continue
        threading.Thread(target=handle, args=(c, (th, int(tp)), a.log, lock), daemon=True).start()


if __name__ == "__main__":
    main()
