#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""TLS front for a throw-away bruecke_server.py instance (tools/stab/net.sh).

jarvisd talks HTTPS to /bruecke/draht. This script terminates TLS 1.3 (test
certificate from tools/hwnet/mkcerts.py), forwards each request to the plain
HTTP instance of the bridge server and logs one line per connection:

    CONN <monotonic seconds> <handshake ms> <first word of the body or ->

The log is what tools/stab/net.sh measures: the number of connections while
the device is idle (each one is a full TLS handshake on the guest) and the gap
between the end of a network outage and the next connection.
"""
import argparse
import http.client
import socket
import ssl
import sys
import threading
import time


def read_request(conn):
    buf = b""
    while b"\r\n\r\n" not in buf:
        chunk = conn.recv(65536)
        if not chunk:
            return None
        buf += chunk
    head, _, rest = buf.partition(b"\r\n\r\n")
    lines = head.split(b"\r\n")
    clen = 0
    for ln in lines[1:]:
        k, _, v = ln.partition(b":")
        if k.strip().lower() == b"content-length":
            clen = int(v.strip() or b"0")
    while len(rest) < clen:
        chunk = conn.recv(65536)
        if not chunk:
            break
        rest += chunk
    return lines, rest[:clen]


def handle(raw, ctx, args, log, lock):
    t0 = time.monotonic()
    try:
        conn = ctx.wrap_socket(raw, server_side=True)
    except Exception as e:  # handshake failed
        with lock:
            log.write("HSFAIL %.3f %s\n" % (time.monotonic(), type(e).__name__))
            log.flush()
        raw.close()
        return
    hs_ms = (time.monotonic() - t0) * 1000
    try:
        req = read_request(conn)
        if req is None:
            return
        lines, body = req
        first = body.split(b" ", 1)[0].split(b"\n", 1)[0][:16].decode("latin1") or "-"
        headers = {}
        for ln in lines[1:]:
            k, _, v = ln.partition(b":")
            headers[k.strip().decode()] = v.strip().decode()
        path = lines[0].split(b" ")[1].decode()
        up = http.client.HTTPConnection("127.0.0.1", args.upstream, timeout=60)
        fwd = {"X-Draht": headers.get("X-Draht", ""), "Content-Length": str(len(body))}
        up.request("POST", path, body=body, headers=fwd)
        resp = up.getresponse()
        data = resp.read()
        out = ("HTTP/1.1 %d OK\r\nContent-Length: %d\r\nConnection: close\r\n\r\n"
               % (resp.status, len(data))).encode() + data
        conn.sendall(out)
        with lock:
            log.write("CONN %.3f %.0f %s\n" % (time.monotonic(), hs_ms, first))
            log.flush()
        up.close()
    except Exception as e:
        with lock:
            log.write("ERR %.3f %s\n" % (time.monotonic(), type(e).__name__))
            log.flush()
    finally:
        try:
            conn.close()
        except Exception:
            pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cert", required=True)
    ap.add_argument("--key", required=True)
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--upstream", type=int, required=True)
    ap.add_argument("--log", required=True)
    args = ap.parse_args()
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_3
    ctx.load_cert_chain(args.cert, args.key)
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", args.port))
    srv.listen(16)
    log = open(args.log, "a")
    lock = threading.Lock()
    log.write("START %.3f\n" % time.monotonic())
    log.flush()
    while True:
        raw, _ = srv.accept()
        threading.Thread(target=handle, args=(raw, ctx, args, log, lock), daemon=True).start()


if __name__ == "__main__":
    main()
