#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import hashlib
import http.server
import random
import socketserver
import ssl
import sys

BLOCK = 1 << 20
BASE = random.Random(20261028).randbytes(BLOCK)


def block(index):
    return index.to_bytes(8, "little") + BASE[8:]


def stream(size, start=0):
    index = start // BLOCK
    skip = start % BLOCK
    left = size - start
    while left > 0:
        data = block(index)[skip:]
        skip = 0
        data = data[:left]
        left -= len(data)
        index += 1
        yield data


def digest(size):
    h = hashlib.sha256()
    for data in stream(size):
        h.update(data)
    return h.hexdigest()


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def do_GET(self):
        name, _, query = self.path.partition("?")
        size = int(query.split("=")[1]) if "=" in query else 0
        start = 0
        rng = self.headers.get("Range")
        if rng and rng.startswith("bytes="):
            start = int(rng[6:].split("-")[0])
        try:
            if name == "/plain":
                self.send_response(206 if start else 200)
                self.send_header("Content-Length", str(size - start))
                if start:
                    self.send_header("Content-Range", "bytes %d-%d/%d" % (start, size - 1, size))
                self.send_header("Connection", "close")
                self.end_headers()
                for data in stream(size, start):
                    self.wfile.write(data)
            elif name == "/chunked":
                self.send_response(200)
                self.send_header("Transfer-Encoding", "chunked")
                self.send_header("Connection", "close")
                self.end_headers()
                for data in stream(size):
                    self.wfile.write(b"%x\r\n" % len(data) + data + b"\r\n")
                self.wfile.write(b"0\r\n\r\n")
            else:
                self.send_error(404)
        except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
            pass
        self.close_connection = True


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True


def main(argv):
    if argv[1] == "sha":
        print(digest(int(argv[2])))
        return 0
    port = int(argv[2])
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_3
    ctx.load_cert_chain(argv[3], argv[4])
    server = Server(("0.0.0.0", port), Handler)
    server.socket = ctx.wrap_socket(server.socket, server_side=True)
    print("START port=%d" % port, flush=True)
    server.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
