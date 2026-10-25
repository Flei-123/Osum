#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
import os
import re
import select
import socket
import subprocess
import sys
import tempfile
import time

BINARY = os.path.abspath(sys.argv[1])
PASS = 0
FAIL = []


def ok(title, good, got=""):
    global PASS
    if good:
        PASS += 1
    else:
        FAIL.append((title, got))


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    p = s.getsockname()[1]
    s.close()
    return p


def sh(d, *a):
    subprocess.run(a, check=True, capture_output=True, cwd=d)


def make_certs(d):
    sh(d, "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", "ca.key",
       "-out", "ca.crt", "-subj", "/CN=Rekey CA", "-days", "30")
    with open(os.path.join(d, "ext.cnf"), "w") as f:
        f.write("subjectAltName=DNS:localhost\nbasicConstraints=CA:FALSE\n")
    sh(d, "openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", "ec.key")
    sh(d, "openssl", "req", "-new", "-key", "ec.key", "-subj", "/CN=localhost", "-out", "ec.csr")
    sh(d, "openssl", "x509", "-req", "-in", "ec.csr", "-CA", "ca.crt", "-CAkey", "ca.key",
       "-CAcreateserial", "-out", "ec.crt", "-days", "30", "-extfile", "ext.cnf")


class Peer:
    def __init__(self, d, port, ciphersuites):
        self.p = subprocess.Popen(
            ["stdbuf", "-o0", "openssl", "s_server", "-accept", str(port), "-cert", os.path.join(d, "ec.crt"),
             "-key", os.path.join(d, "ec.key"), "-tls1_3", "-ciphersuites", ciphersuites],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        for _ in range(100):
            try:
                socket.create_connection(("127.0.0.1", port), timeout=0.2).close()
                break
            except OSError:
                time.sleep(0.05)
        self.buf = b""

    def readline(self, timeout=20):
        end = time.time() + timeout
        while b"\n" not in self.buf:
            left = end - time.time()
            if left <= 0:
                return None
            r, _, _ = select.select([self.p.stdout], [], [], left)
            if not r:
                return None
            chunk = os.read(self.p.stdout.fileno(), 65536)
            if not chunk:
                return None
            self.buf += chunk
        line, self.buf = self.buf.split(b"\n", 1)
        return line.decode(errors="replace")

    def send(self, text):
        self.p.stdin.write(text.encode())
        self.p.stdin.flush()

    def stop(self):
        try:
            self.p.stdin.close()
        except OSError:
            pass
        self.p.terminate()
        try:
            self.p.wait(timeout=3)
        except subprocess.TimeoutExpired:
            self.p.kill()


def scenario(d, name, rounds, rekey_after, refuse, every, plan, suite="TLS_AES_128_GCM_SHA256"):
    port = free_port()
    peer = Peer(d, port, suite)
    client = subprocess.Popen(
        [BINARY, "127.0.0.1", str(port), "localhost", os.path.join(d, "ca.crt"),
         str(rounds), str(rekey_after), str(refuse), str(every)],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    seen = []
    served = 0
    while served < rounds:
        line = peer.readline(15)
        if line is None:
            break
        m = re.match(r"^c(\d+) ", line)
        if not m:
            continue
        i = int(m.group(1))
        seen.append(i)
        for cmd in plan(i):
            peer.send(cmd + "\n")
            time.sleep(0.05)
        peer.send("s%d\n" % i)
        served += 1
    try:
        out = client.communicate(timeout=20)[0].decode()
    except subprocess.TimeoutExpired:
        client.kill()
        out = client.communicate()[0].decode()
    peer.stop()
    res = {}
    for ln in out.splitlines():
        parts = ln.split(" ", 1)
        if len(parts) == 2 and parts[1].isdigit():
            res[parts[0]] = int(parts[1])
        elif ln.startswith("ERR"):
            res["ERR"] = ln
    return res, seen, out


def main():
    d = tempfile.mkdtemp()
    make_certs(d)

    def server_updates(i):
        cmds = []
        if i % 5 == 2:
            cmds.append("k")
        if i % 7 == 3:
            cmds.append("K")
        return cmds

    n = 60
    expect_k = len([i for i in range(n) if i % 5 == 2]) + len([i for i in range(n) if i % 7 == 3])
    expect_big_k = len([i for i in range(n) if i % 7 == 3])
    for suite in ("TLS_AES_128_GCM_SHA256", "TLS_CHACHA20_POLY1305_SHA256"):
        r, seen, out = scenario(d, "server", n, 0, 0, 0, server_updates, suite)
        ok("A %s: all rounds echoed" % suite, r.get("ROUNDS") == n and r.get("MISMATCH") == 0, out)
        ok("A %s: server updates taken" % suite, r.get("REKEYSIN") == expect_k, out)
        ok("A %s: requested updates answered" % suite, r.get("REKEYSOUT") == expect_big_k, out)

    r, seen, out = scenario(d, "client", 56, 0, 0, 4, lambda i: [])
    ok("B client-initiated updates survive", r.get("ROUNDS") == 56 and r.get("MISMATCH") == 0, out)
    ok("B client rekeys counted", r.get("REKEYSOUT") == 13, out)

    r, seen, out = scenario(d, "auto", 100, 10, 0, 0, lambda i: [])
    ok("C automatic rekey after N records", r.get("ROUNDS") == 100 and r.get("MISMATCH") == 0, out)
    ok("C automatic rekey count", r.get("REKEYSOUT", 0) >= 8, out)

    r, seen, out = scenario(d, "both", 120, 11, 0, 6, server_updates)
    ok("D both directions mixed", r.get("ROUNDS") == 120 and r.get("MISMATCH") == 0, out)
    ok("D mixed rekeys on both sides", r.get("REKEYSOUT", 0) > 15 and r.get("REKEYSIN", 0) > 15, out)

    r, seen, out = scenario(d, "refuse", 30, 0, 1, 0, server_updates)
    ok("E counter: refusing client stops at the first key update",
       r.get("ROUNDS", 0) < 30 and "ERR" in r, out)
    ok("E counter: refusing client rotated nothing", r.get("REKEYSIN") == 0, out)

    for t, g in FAIL:
        print("  FAIL", t, "|", g.strip().replace("\n", " ; ")[:200])
    print("  tls13rekey: %d ok, %d failed" % (PASS, len(FAIL)))
    return 1 if FAIL else 0


sys.exit(main())
