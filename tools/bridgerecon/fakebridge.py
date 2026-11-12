#!/usr/bin/env python3
import argparse
import socket
import ssl
import struct
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOLD_LIMIT_S = 300.0
POLL_STEP_S = 0.5
NONCE_HEX = "00112233445566778899aabbccddeeff"
DNS_TTL = 60

lock = threading.Lock()
config = {}


def record(text):
    with lock:
        with open(config["log"], "a") as f:
            f.write("%.2f %s\n" % (time.time(), text))


def stall_active():
    try:
        with open(config["stall"]) as f:
            return time.time() < float(f.read().strip())
    except (OSError, ValueError):
        return False


def parse_messages(body):
    messages = []
    i = 0
    while i < len(body):
        j = body.find(b"\n", i)
        if j < 0:
            break
        fields = body[i:j].decode("utf-8", "replace").split()
        if not fields:
            i = j + 1
            continue
        try:
            length = int(fields[-1])
        except ValueError:
            length = 0
        messages.append(fields[:-1])
        i = j + 1 + length
    return messages


def answer_for(messages):
    out = b""
    for words in messages:
        if not words:
            continue
        if words[0] == "hello":
            out += ("challenge %s 0\n" % NONCE_HEX).encode()
        elif words[0] == "proof":
            out += b"welcome 0\n"
    return out


def hold_until_closed(connection):
    start = time.time()
    connection.settimeout(POLL_STEP_S)
    while time.time() - start < HOLD_LIMIT_S:
        try:
            data = connection.recv(1)
        except socket.timeout:
            continue
        except (OSError, ssl.SSLError):
            break
        if not data:
            break
    return time.time() - start


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length) if length else b""
        messages = parse_messages(body)
        names = ",".join(m[0] for m in messages if m) or "-"
        if stall_active():
            record("REQ-STALLED %s" % names)
            held = hold_until_closed(self.connection)
            record("HOLD %.1f" % held)
            return
        reply = answer_for(messages)
        record("REQ %s" % names)
        if reply:
            record("ANSWER %s" % reply.split()[0].decode())
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(reply)))
        self.end_headers()
        self.wfile.write(reply)


def dns_answer(query, address):
    end = 12
    while end < len(query) and query[end] != 0:
        end += query[end] + 1
    question = query[12:end + 5]
    header = query[:2] + struct.pack(">HHHHH", 0x8180, 1, 1, 0, 0)
    record_a = struct.pack(">HHHIH", 0xC00C, 1, 1, DNS_TTL, 4) + socket.inet_aton(address)
    return header + question + record_a


def serve_dns(address):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((address, 53))
    while True:
        query, peer = sock.recvfrom(512)
        sock.sendto(dns_answer(query, address), peer)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cert", required=True)
    parser.add_argument("--key", required=True)
    parser.add_argument("--bind", required=True)
    parser.add_argument("--log", required=True)
    parser.add_argument("--stall", required=True)
    args = parser.parse_args()
    config["log"] = args.log
    config["stall"] = args.stall
    threading.Thread(target=serve_dns, args=(args.bind,), daemon=True).start()
    server = ThreadingHTTPServer((args.bind, 443), Handler)
    server.daemon_threads = True
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(args.cert, args.key)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    record("READY")
    server.serve_forever()


if __name__ == "__main__":
    sys.exit(main())
