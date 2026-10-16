#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/jarvismini/fakesrv.py -- a fake JARVIS server for the JARVIS Mini gate (TLS + login + WebSocket), the host side of /bin/jmlink.

    fakesrv.py <port> <cert.pem> <key.pem> <logfile>

Same protocol as the real server (public/mini.html): POST /api/login {"username","password"} -> {"token"} (only justin / geheim),
then GET /?role=ui&dev=..&token=.. with a WebSocket upgrade (token must match). Every event is ONE log line the gate reads:
    fake: login ok user=justin | fake: login bad user=<name> | fake: ws open | fake: ws refused
    fake: msg <text> images=<n> files=<n> imgmagic=<first base64 chars> | fake: ws closed
The reply to a message: one `token` frame ("pong from fake") + `done`.
"""
import base64, hashlib, json, re, socket, ssl, struct, sys, threading, time

port, cert, key, logf = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
TOKEN = "tok-fake-" + "x" * 40  # the real one is a JWT (long); jmlink wants >= 20 characters
lock = threading.Lock()


def log(s):
    with lock:
        with open(logf, "a") as f:
            f.write("fake: " + s + "\n")


def read_head(c):
    buf = b""
    while b"\r\n\r\n" not in buf:
        d = c.recv(4096)
        if not d:
            return None, b""
        buf += d
        if len(buf) > 65536:
            return None, b""
    h, _, rest = buf.partition(b"\r\n\r\n")
    return h.decode("latin1"), rest


def recv_n(c, n, pre=b""):
    buf = pre
    while len(buf) < n:
        d = c.recv(65536)
        if not d:
            break
        buf += d
    return buf


def ws_frame(op, payload):
    n = len(payload)
    if n < 126:
        h = bytes([0x80 | op, n])
    elif n < 65536:
        h = bytes([0x80 | op, 126]) + struct.pack(">H", n)
    else:
        h = bytes([0x80 | op, 127]) + struct.pack(">Q", n)
    return h + payload


def ws_read(c, state):
    def need(n):
        while len(state["b"]) < n:
            d = c.recv(65536)
            if not d:
                raise EOFError
            state["b"] += d
        out, state["b"] = state["b"][:n], state["b"][n:]
        return out
    h = need(2)
    op, ln = h[0] & 15, h[1] & 127
    if ln == 126:
        ln = struct.unpack(">H", need(2))[0]
    elif ln == 127:
        ln = struct.unpack(">Q", need(8))[0]
    mask = need(4) if h[1] & 128 else b"\0\0\0\0"
    data = bytearray(need(ln))
    for i in range(len(data)):
        data[i] ^= mask[i & 3]
    return op, bytes(data), bool(h[0] & 128)


def handle(c):
    try:
        head, rest = read_head(c)
        if head is None:
            return
        line = head.split("\r\n")[0]
        hd = {}
        for l in head.split("\r\n")[1:]:
            k, _, v = l.partition(":")
            hd[k.strip().lower()] = v.strip()
        if line.startswith("POST /api/login"):
            body = recv_n(c, int(hd.get("content-length", "0")), rest)
            try:
                j = json.loads(body.decode("utf8"))
            except Exception:
                j = {}
            if j.get("username") == "justin" and j.get("password") == "geheim":
                log("login ok user=justin")
                out = json.dumps({"token": TOKEN}, separators=(",", ":")).encode()
                c.sendall(b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % len(out) + out)
            else:
                log("login bad user=%s" % j.get("username", "?"))
                out = b'{"error":"bad login"}'
                c.sendall(b"HTTP/1.1 401 Unauthorized\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % len(out) + out)
            return
        m = re.match(r"GET /\?(\S*) HTTP", line)
        if m and hd.get("upgrade", "").lower() == "websocket":
            if ("token=" + TOKEN) not in m.group(1):
                log("ws refused")
                c.sendall(b"HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
                return
            acc = base64.b64encode(hashlib.sha1((hd["sec-websocket-key"] + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest())
            c.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + acc + b"\r\n\r\n")
            log("ws open")
            c.sendall(ws_frame(1, json.dumps({"type": "info", "version": "fake"}, separators=(",", ":")).encode()))
            st = {"b": rest}
            while True:
                op, data, fin = ws_read(c, st)
                if op == 8:
                    break
                if op == 9:
                    c.sendall(ws_frame(10, data))
                    continue
                if op in (1, 0):
                    try:
                        j = json.loads(data.decode("utf8"))
                    except Exception:
                        continue
                    if j.get("type") == "message":
                        imgs, files = j.get("images") or [], j.get("files") or []
                        magic = (imgs[0]["data"][:12] if imgs else (files[0]["data"][:12] if files else "-"))
                        log("msg %s images=%d files=%d imgmagic=%s" % (j.get("text", "").replace("\n", " "), len(imgs), len(files), magic))
                        c.sendall(ws_frame(1, json.dumps({"type": "token", "content": "pong from fake\n"}, separators=(",", ":")).encode()))
                        c.sendall(ws_frame(1, json.dumps({"type": "done"}, separators=(",", ":")).encode()))
            return
        c.sendall(b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
    except (EOFError, ConnectionError, ssl.SSLError, OSError):
        pass
    finally:
        log("ws closed") if False else None
        try:
            c.close()
        except OSError:
            pass


ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(cert, key)
srv = socket.socket()
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", port))
srv.listen(8)
print("fake: listening", flush=True)
while True:
    raw, _ = srv.accept()
    try:
        raw.settimeout(120)
        c = ctx.wrap_socket(raw, server_side=True)
    except (ssl.SSLError, OSError) as e:
        log("tls failed %s" % type(e).__name__)
        raw.close()
        continue
    threading.Thread(target=handle, args=(c,), daemon=True).start()
