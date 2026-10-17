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

Optional path routing (repeatable): --route /api/kontakte=127.0.0.1:18471
sends connections whose FIRST request line starts with that path prefix to
another backend (the mock address book, tools/anbfleitec/buch.py); their
bytes go to DIR/book-c2s.log and DIR/book-s2c.log, never to the broker logs.
The guest opens one connection per request (Connection: close).
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


def pick(conn, target, routes):
    """Read the first request line; return (backend, prefix-of-log, bytes read)."""
    if not routes:
        return target, "", b""
    buf = b""
    try:
        while b"\r\n" not in buf and len(buf) < 8192:
            chunk = conn.recv(8192)
            if not chunk:
                break
            buf += chunk
    except OSError:
        pass
    parts = buf.split(b" ", 2)
    path = parts[1].decode("latin-1") if len(parts) > 1 else ""
    for prefix, dest in routes:
        if path == prefix or path.startswith(prefix + "/") or path.startswith(prefix + "?"):
            return dest, "book-", buf
    return target, "", buf


def handle(conn, target, logdir, lock, routes=()):
    target, pre, first = pick(conn, target, routes)
    try:
        up = socket.create_connection(target, timeout=10)
    except OSError:
        conn.close()
        return
    if first:
        with lock:
            with open(logdir + "/" + pre + "c2s.log", "ab") as f:
                f.write(first)
        up.sendall(first)
    t1 = threading.Thread(target=pump, args=(conn, up, logdir + "/" + pre + "c2s.log", lock), daemon=True)
    t2 = threading.Thread(target=pump, args=(up, conn, logdir + "/" + pre + "s2c.log", lock), daemon=True)
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
    ap.add_argument("--route", action="append", default=[], help="/prefix=host:port")
    a = ap.parse_args()
    routes = []
    for r in a.route:
        pfx, dest = r.split("=", 1)
        dh, dp = dest.rsplit(":", 1)
        routes.append((pfx, (dh, int(dp))))
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
        threading.Thread(target=handle, args=(c, (th, int(tp)), a.log, lock, routes), daemon=True).start()


if __name__ == "__main__":
    main()
