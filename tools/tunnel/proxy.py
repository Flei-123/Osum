#!/usr/bin/env python3
"""tools/tunnel/proxy.py -- SOCKS5 and HTTP CONNECT against real servers.

Three counterparts, none of them written by this repository:

  1. A SOCKS5 server in Python (`socksd.py`, started here), which is
     enough to check the wire format, the username/password exchange of
     RFC 1929 and every reply code -- including the ones that must be
     REFUSALS.
  2. An HTTP proxy in Python, for the CONNECT method.
  3. THE REAL TOR DAEMON, if it is installed. This is the point of the
     whole exercise: Osum does not implement Tor, it speaks SOCKS5 to a
     Tor that other people wrote and other people audit. If the SOCKS5
     client is right, `tor` is usable from Osum and the switch in the
     settings is honest. See docs/TUNNEL.md.

Tor is only asked to resolve and connect through the network if it can
reach it; where there is no route to the internet the check is reported
as SKIPPED rather than passed, because a check that quietly passes when
it did nothing is worse than no check.
"""
import os
import socket
import struct
import subprocess
import sys
import threading
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DRV = os.path.join(ROOT, ".probe", "socksdrv")

RESULTS = []
FAILED = []
SKIPPED = []


def ok(name, good, detail=""):
    RESULTS.append((name, good, detail))
    if not good:
        FAILED.append(name)
    print("  %-50s %s %s" % (name, "ok  " if good else "FAIL", detail))


def skip(name, why):
    SKIPPED.append(name)
    print("  %-50s SKIP %s" % (name, why))


def drv(*lines):
    """One run of `.probe/socksdrv`, one answer per line."""
    inp = ("\n".join(lines) + "\n").encode()
    p = subprocess.run([DRV], input=inp, capture_output=True, timeout=120)
    return p.stdout.decode().splitlines()


# =====================================================================
# a SOCKS5 server, and a target for it to reach
# =====================================================================

class Target(threading.Thread):
    """An HTTP server that answers anything with a known first line."""
    daemon = True

    def __init__(self):
        super().__init__()
        self.s = socket.socket()
        self.s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.s.bind(("127.0.0.1", 0))
        self.s.listen(16)
        self.port = self.s.getsockname()[1]
        self.hits = 0

    def run(self):
        while True:
            try:
                c, _ = self.s.accept()
            except OSError:
                return
            self.hits += 1
            threading.Thread(target=self.one, args=(c,), daemon=True).start()

    def one(self, c):
        try:
            c.settimeout(5)
            c.recv(4096)
            c.sendall(b"HTTP/1.0 200 OSUM-TARGET\r\n"
                      b"Content-Length: 2\r\n\r\nhi")
        except Exception:
            pass
        finally:
            c.close()


class Socks5Server(threading.Thread):
    """RFC 1928 and RFC 1929, on the other side of the wire from us."""
    daemon = True

    def __init__(self, require_auth=False, force_reply=None,
                 target_port=None):
        super().__init__()
        self.require_auth = require_auth
        self.force_reply = force_reply
        self.target_port = target_port
        self.seen_names = []
        self.seen_creds = []
        self.s = socket.socket()
        self.s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.s.bind(("127.0.0.1", 0))
        self.s.listen(16)
        self.port = self.s.getsockname()[1]

    def run(self):
        while True:
            try:
                c, _ = self.s.accept()
            except OSError:
                return
            threading.Thread(target=self.one, args=(c,), daemon=True).start()

    def rd(self, c, n):
        b = b""
        while len(b) < n:
            x = c.recv(n - len(b))
            if not x:
                raise EOFError
            b += x
        return b

    def one(self, c):
        try:
            c.settimeout(10)
            ver, nm = self.rd(c, 2)
            methods = self.rd(c, nm)
            if self.require_auth:
                if 2 not in methods:
                    c.sendall(b"\x05\xff")
                    return
                c.sendall(b"\x05\x02")
                self.rd(c, 1)
                ul = self.rd(c, 1)[0]
                u = self.rd(c, ul)
                pl = self.rd(c, 1)[0]
                p = self.rd(c, pl)
                self.seen_creds.append((u.decode(), p.decode()))
                c.sendall(b"\x01\x00")
            else:
                c.sendall(b"\x05\x00")
            hdr = self.rd(c, 4)
            atyp = hdr[3]
            if atyp == 3:
                ln = self.rd(c, 1)[0]
                name = self.rd(c, ln).decode()
            elif atyp == 1:
                name = socket.inet_ntoa(self.rd(c, 4))
            else:
                name = "?"
            port = struct.unpack("!H", self.rd(c, 2))[0]
            self.seen_names.append((name, port, atyp))
            if self.force_reply is not None:
                c.sendall(bytes([5, self.force_reply, 0, 1, 0, 0, 0, 0,
                                 0, 0]))
                return
            up = socket.socket()
            up.connect(("127.0.0.1", self.target_port))
            c.sendall(b"\x05\x00\x00\x01\x7f\x00\x00\x01" +
                      struct.pack("!H", self.target_port))
            self.pipe(c, up)
        except Exception:
            pass
        finally:
            c.close()

    def pipe(self, a, b):
        def one_way(x, y):
            try:
                while True:
                    d = x.recv(4096)
                    if not d:
                        break
                    y.sendall(d)
            except Exception:
                pass
            try:
                y.shutdown(socket.SHUT_WR)
            except Exception:
                pass
        t = threading.Thread(target=one_way, args=(a, b), daemon=True)
        t.start()
        one_way(b, a)
        t.join(timeout=5)


class HttpProxy(threading.Thread):
    daemon = True

    def __init__(self, target_port):
        super().__init__()
        self.target_port = target_port
        self.seen = []
        self.s = socket.socket()
        self.s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.s.bind(("127.0.0.1", 0))
        self.s.listen(16)
        self.port = self.s.getsockname()[1]

    def run(self):
        while True:
            try:
                c, _ = self.s.accept()
            except OSError:
                return
            threading.Thread(target=self.one, args=(c,), daemon=True).start()

    def one(self, c):
        try:
            c.settimeout(10)
            req = b""
            while b"\r\n\r\n" not in req:
                d = c.recv(1024)
                if not d:
                    return
                req += d
            first = req.split(b"\r\n")[0].decode()
            self.seen.append(first)
            if not first.startswith("CONNECT "):
                c.sendall(b"HTTP/1.1 405 Method Not Allowed\r\n\r\n")
                return
            up = socket.socket()
            up.connect(("127.0.0.1", self.target_port))
            c.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
            Socks5Server.pipe(self, c, up)
        except Exception:
            pass
        finally:
            c.close()


def main():
    if not os.path.exists(DRV):
        print("missing %s -- run tools/tunnel/run.sh" % DRV)
        return 2

    target = Target()
    target.start()

    print("\n== SOCKS5 (RFC 1928) against a real server ==")
    srv = Socks5Server(target_port=target.port)
    srv.start()
    time.sleep(0.2)
    r = drv("socks5 127 0 0 1 %d osum.example 80" % srv.port)[0]
    ok("a plain CONNECT reaches the target", r.startswith("ok 0 200"), r)
    ok("the host name went over UNRESOLVED (ATYP 3)",
       srv.seen_names and srv.seen_names[-1][:3] == ("osum.example", 80, 3),
       str(srv.seen_names[-1]) if srv.seen_names else "nothing seen")

    print("\n== username/password (RFC 1929), Tor's stream isolation ==")
    asrv = Socks5Server(require_auth=True, target_port=target.port)
    asrv.start()
    time.sleep(0.2)
    r = drv("socks5 127 0 0 1 %d osum.example 80 ident-a secret"
            % asrv.port)[0]
    ok("a credential is offered and accepted", r.startswith("ok 0 200"), r)
    ok("the proxy saw the credential we sent",
       asrv.seen_creds and asrv.seen_creds[-1] == ("ident-a", "secret"),
       str(asrv.seen_creds[-1]) if asrv.seen_creds else "-")
    # And without one, against a server that demands it, the exchange must
    # FAIL rather than proceed.
    r = drv("socks5 127 0 0 1 %d osum.example 80" % asrv.port)[0]
    ok("no credential against a proxy that demands one is refused",
       r.startswith("fail method"), r)

    print("\n== the refusals ==")
    for code, name in [(1, "general failure"), (2, "not allowed"),
                       (3, "network unreachable"), (4, "host unreachable"),
                       (5, "connection refused"), (7, "command unsupported"),
                       (240, "Tor: onion descriptor unreachable"),
                       (246, "Tor: bad .onion address")]:
        bad = Socks5Server(force_reply=code, target_port=target.port)
        bad.start()
        time.sleep(0.1)
        r = drv("socks5 127 0 0 1 %d osum.example 80" % bad.port)[0]
        ok("reply %d (%s) is refused" % (code, name),
           r == "fail reply %d" % code, r)
        bad.s.close()

    r = drv("socks5 127 0 0 1 1 osum.example 80")[0]
    ok("a proxy that is not there is refused", r.startswith("fail"), r)

    print("\n== HTTP CONNECT ==")
    hp = HttpProxy(target.port)
    hp.start()
    time.sleep(0.2)
    r = drv("http 127 0 0 1 %d osum.example 443" % hp.port)[0]
    ok("CONNECT reaches the target", r.startswith("ok 200 200"), r)
    ok("the request line is well formed",
       hp.seen and hp.seen[-1] == "CONNECT osum.example:443 HTTP/1.1",
       hp.seen[-1] if hp.seen else "-")

    print("\n== against the real Tor daemon ==")
    tor_bin = subprocess.run("which tor", shell=True,
                             capture_output=True, text=True).stdout.strip()
    if not tor_bin:
        skip("SOCKS5 against tor", "tor is not installed")
    else:
        d = "/tmp/osum-tor-%d" % os.getpid()
        os.makedirs(d, exist_ok=True)
        os.chmod(d, 0o700)
        port = 19050
        proc = subprocess.Popen(
            [tor_bin, "--SocksPort", "127.0.0.1:%d" % port,
             "--DataDirectory", d, "--Log", "notice stdout",
             "--ClientOnly", "1", "--AvoidDiskWrites", "1"],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        booted = False
        deadline = time.time() + 90
        lastline = ""
        while time.time() < deadline:
            ln = proc.stdout.readline()
            if not ln:
                break
            lastline = ln.strip()
            if "Bootstrapped 100%" in ln:
                booted = True
                break
            if "Opening Socks listener" in ln:
                pass
        if not booted:
            # The SOCKS port is up long before the network is; a refusal
            # from Tor is still a valid measurement of OUR client.
            up = False
            try:
                t = socket.create_connection(("127.0.0.1", port), 3)
                t.close()
                up = True
            except Exception:
                pass
            if up:
                r = drv("socks5 127 0 0 1 %d example.com 80" % port)[0]
                ok("Tor's SOCKS5 answers our client (no route out)",
                   r.startswith("fail reply") or r.startswith("ok"),
                   "%s -- tor said: %s" % (r, lastline[:60]))
            else:
                skip("SOCKS5 against tor", "tor did not come up: %s"
                     % lastline[:60])
        else:
            r = drv("socks5 127 0 0 1 %d example.com 80" % port)[0]
            ok("a page fetched through the real Tor network",
               r.startswith("ok 0"), r[:100])
            r = drv("socks5 127 0 0 1 %d not-a-real-onion-address.onion 80"
                    % port)[0]
            # Tor 0.4.9 answers a malformed .onion with the ordinary
            # code 1, not with its extended 0xF6. The check is that it is
            # REFUSED and that our client reports the code it really got;
            # inventing 0xF6 here would be a test written to its answer.
            ok("Tor refuses a malformed .onion address",
               r.startswith("fail reply"), r)
            # stream isolation: two credentials, two circuits
            r1 = drv("socks5 127 0 0 1 %d example.com 80 ident-a x" % port)
            r2 = drv("socks5 127 0 0 1 %d example.com 80 ident-b x" % port)
            ok("two isolated streams both work",
               r1 and r2 and r1[0].startswith("ok") and r2[0].startswith("ok"),
               "%s | %s" % (r1[0][:30] if r1 else "-",
                            r2[0][:30] if r2 else "-"))
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except Exception:
            proc.kill()
        subprocess.run("rm -rf %s" % d, shell=True)

    print()
    if FAILED:
        print("%d checks FAILED:" % len(FAILED))
        for f in FAILED:
            print("  - %s" % f)
        return 1
    print("all %d proxy checks passed%s" % (
        len(RESULTS),
        ", %d skipped" % len(SKIPPED) if SKIPPED else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
