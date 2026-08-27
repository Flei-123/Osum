#!/usr/bin/env python3
"""tools/tunnel/amnezia.py -- the AmneziaWG obfuscation, measured.

WHAT COULD BE MEASURED HERE AND WHAT COULD NOT, said first because the
second half is the more important one.

COULD NOT: an interoperability test against the real AmneziaWG. The
kernel module is not packaged for this machine, and `amneziawg-go` --
the userspace implementation -- needs `/dev/net/tun`, which cannot be
created in the container this repository is measured in (`mknod:
Operation not permitted`, the same finding round K8 wrote down about
tap devices). So NOTHING in this file proves that Osum's AmneziaWG
would complete a handshake with Amnezia's own client. That claim is not
made anywhere in this round. docs/TUNNEL.md repeats it.

COULD: three things that are worth having anyway.

  1. THE OBFUSCATION IS A REAL CHANGE TO THE WIRE. The same handshake,
     with the parameters on, is sent to a STOCK Linux WireGuard. Linux
     must ignore it completely -- no response, no handshake counted. If
     Linux still answered, the parameters would be decoration.
  2. THE TWO ENDS AGREE WITH EACH OTHER. Two instances of
     `lib/wg/proto.fi` with the same parameters complete a handshake and
     carry traffic. That is what an Amnezia profile does in practice:
     both ends are configured from the same file.
  3. THE PACKETS LOOK THE WAY THE PARAMETERS SAY. The initiation is
     148 + S1 octets and begins with H1; the response is 92 + S2 and
     begins with H2; the transport packets begin with H4. These are read
     off the wire, not off the source.

Plus the constraint checks the upstream README states, which this round
enforces rather than trusts: H1..H4 pairwise distinct, and
S1 + 148 != S2 + 92.
"""
import base64
import os
import re
import socket
import struct
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PEER = os.path.join(ROOT, ".probe", "peer")

NS = "awgt%d" % os.getpid()
V0 = "awv%d" % (os.getpid() % 10000)
V1 = V0 + "p"
HOST_IP = "10.92.0.1"
NS_IP = "10.92.0.2"
WG_PORT = 51820
OUR_PORT = 51821

# The values Amnezia's own kernel module README recommends: Jc in 4..12,
# Jmin 8, Jmax 80, S1/S2 in 15..150, H1..H4 in 5..2147483647.
JC, JMIN, JMAX = 8, 8, 80
S1, S2 = 39, 121
H1, H2, H3, H4 = 1020325451, 1457133905, 1730964285, 1904583849

RESULTS = []
FAILED = []


def ok(name, good, detail=""):
    RESULTS.append((name, good, detail))
    if not good:
        FAILED.append(name)
    print("  %-52s %s %s" % (name, "ok  " if good else "FAIL", detail))


def sh(cmd, check=True, ns=False):
    if ns:
        cmd = "ip netns exec %s %s" % (NS, cmd)
    p = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if check and p.returncode != 0:
        raise RuntimeError("%s\n%s%s" % (cmd, p.stdout, p.stderr))
    return p.stdout.strip()


class Peer:
    def __init__(self):
        self.p = subprocess.Popen([PEER], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, bufsize=0)

    def cmd(self, *a):
        self.p.stdin.write((" ".join(str(x) for x in a) + "\n").encode())
        self.p.stdin.flush()
        out = b""
        while not out.endswith(b"\n"):
            c = self.p.stdout.read(1)
            if not c:
                raise RuntimeError("peer died")
            out += c
        return out.decode().strip()

    def close(self):
        try:
            self.p.stdin.close()
            self.p.wait(timeout=5)
        except Exception:
            self.p.kill()


def now_us():
    return int(time.monotonic() * 1_000_000)


def rnd64():
    return os.urandom(64).hex()


def clamped():
    k = bytearray(os.urandom(32))
    k[0] &= 248
    k[31] = (k[31] & 127) | 64
    return bytes(k)


def le32(b, off):
    return struct.unpack_from("<I", b, off)[0]


def teardown():
    subprocess.run("ip netns del %s" % NS, shell=True, capture_output=True)
    subprocess.run("ip link del %s" % V0, shell=True, capture_output=True)


# =====================================================================
# 1. the parameter constraints
# =====================================================================
def check_constraints():
    p = Peer()
    p.cmd("init", clamped().hex())
    good = p.cmd("awg", JC, JMIN, JMAX, S1, S2, H1, H2, H3, H4)
    ok("a valid parameter set is accepted", good == "ok", good)
    # H values must be pairwise distinct.
    r = p.cmd("awg", JC, JMIN, JMAX, S1, S2, H1, H1, H3, H4)
    ok("two equal headers are refused", r == "no", r)
    # S1 + 148 must not equal S2 + 92, i.e. S1 + 56 != S2.
    r = p.cmd("awg", JC, JMIN, JMAX, 39, 39 + 56, H1, H2, H3, H4)
    ok("S1 + 56 == S2 is refused (equal padded sizes)", r == "no", r)
    r = p.cmd("awg", 200, JMIN, JMAX, S1, S2, H1, H2, H3, H4)
    ok("Jc above 128 is refused", r == "no", r)
    r = p.cmd("awg", JC, 90, 80, S1, S2, H1, H2, H3, H4)
    ok("Jmin above Jmax is refused", r == "no", r)
    p.close()


# =====================================================================
# 2. the packets look the way the parameters say
# =====================================================================
def check_shape():
    p = Peer()
    ours = clamped()
    theirs = clamped()
    p.cmd("use", 0)
    a_pub = p.cmd("init", ours.hex())
    p.cmd("use", 1)
    b_pub = p.cmd("init", theirs.hex())
    p.cmd("use", 0)
    p.cmd("awg", JC, JMIN, JMAX, S1, S2, H1, H2, H3, H4)
    p.cmd("peer", b_pub)
    p.cmd("allow", 0, 0, 0)
    p.cmd("endpoint", 0, 1, 51820)
    p.cmd("use", 1)
    p.cmd("awg", JC, JMIN, JMAX, S1, S2, H1, H2, H3, H4)
    p.cmd("peer", a_pub)
    p.cmd("allow", 0, 0, 0)
    p.cmd("use", 0)

    init = bytes.fromhex(p.cmd("handshake", 0, rnd64(), int(time.time()),
                               time.time_ns() % 10**9, now_us()))
    ok("the initiation is 148 + S1 octets", len(init) == 148 + S1,
       "%d, expected %d" % (len(init), 148 + S1))
    ok("the initiation's type word is H1", le32(init, S1) == H1,
       "%d" % le32(init, S1))
    ok("octet 0 is NOT the WireGuard type 1", le32(init, 0) != 1,
       "0x%08x" % le32(init, 0))

    p.cmd("use", 1)
    r = p.cmd("recv", init.hex(), now_us(), rnd64())
    ok("the other end read the obfuscated initiation",
       r.startswith("init 0"), r.split()[0])
    if not r.startswith("init 0"):
        p.close()
        return
    resp = bytes.fromhex(r.split()[2])
    ok("the response is 92 + S2 octets", len(resp) == 92 + S2,
       "%d, expected %d" % (len(resp), 92 + S2))
    ok("the response's type word is H2", le32(resp, S2) == H2,
       "%d" % le32(resp, S2))

    p.cmd("use", 0)
    r = p.cmd("recv", resp.hex(), now_us(), rnd64())
    ok("the obfuscated handshake completed", r == "resp 0", r)

    # 208 octets, a multiple of 16: WireGuard pads the plaintext to a
    # multiple of 16 before encrypting, and the true length is recovered
    # from the inner IP header, not from the tunnel. A payload that is
    # already a multiple of 16 keeps the comparison below honest; the
    # padding itself is checked separately.
    payload = os.urandom(208)
    data = bytes.fromhex(p.cmd("send", 0, payload.hex(), now_us()))
    ok("a transport packet's type word is H4", le32(data, 0) == H4,
       "%d" % le32(data, 0))
    p.cmd("use", 1)
    r = p.cmd("recv", data.hex(), now_us(), rnd64())
    ok("the payload came through the obfuscated tunnel",
       r.startswith("data 0") and r.split()[2] == payload.hex(),
       r.split()[0])

    # And a payload that is NOT a multiple of 16 must come back padded
    # with zeroes to the next multiple -- that is the protocol, not a bug.
    p.cmd("use", 0)
    odd = os.urandom(200)
    d2 = bytes.fromhex(p.cmd("send", 0, odd.hex(), now_us()))
    p.cmd("use", 1)
    r2 = p.cmd("recv", d2.hex(), now_us(), rnd64())
    got = bytes.fromhex(r2.split()[2]) if r2.startswith("data") else b""
    ok("a 200 octet payload is padded to 208 with zeroes",
       got == odd + bytes(8), "%d octets back" % len(got))

    # And the same two ends with the parameters OFF must not read the
    # obfuscated packets -- which is the same statement as check 3, made
    # against our own code instead of Linux's.
    q = Peer()
    q.cmd("init", clamped().hex())
    q.cmd("peer", a_pub)
    r = q.cmd("recv", init.hex(), now_us(), rnd64())
    ok("a plain WireGuard end cannot parse it", r == "none", r)
    q.close()
    p.close()


# =====================================================================
# 3. a stock Linux WireGuard ignores the obfuscated handshake
# =====================================================================
def check_against_linux():
    teardown()
    sh("ip netns add %s" % NS)
    sh("ip link add %s type veth peer name %s" % (V0, V1))
    sh("ip link set %s netns %s" % (V1, NS))
    sh("ip addr add %s/24 dev %s" % (HOST_IP, V0))
    sh("ip link set %s up" % V0)
    sh("ip addr add %s/24 dev %s" % (NS_IP, V1), ns=True)
    sh("ip link set %s up" % V1, ns=True)

    linux_priv = sh("wg genkey")
    linux_pub = sh("echo '%s' | wg pubkey" % linux_priv)
    ours = clamped()
    p = Peer()
    our_pub_hex = p.cmd("init", ours.hex())
    our_pub_b64 = base64.b64encode(bytes.fromhex(our_pub_hex)).decode()

    conf = "/tmp/awgt-%d.conf" % os.getpid()
    open(conf, "w").write(
        "[Interface]\nPrivateKey = %s\nListenPort = %d\n\n"
        "[Peer]\nPublicKey = %s\nAllowedIPs = 10.93.0.1/32\n"
        % (linux_priv, WG_PORT, our_pub_b64))
    os.chmod(conf, 0o600)
    sh("ip link add wg0 type wireguard", ns=True)
    sh("wg setconf wg0 %s" % conf, ns=True)
    sh("ip addr add 10.93.0.2/24 dev wg0", ns=True)
    sh("ip link set wg0 up", ns=True)
    os.unlink(conf)

    p.cmd("peer", base64.b64decode(linux_pub).hex())
    p.cmd("allow", 0, 0, 0)
    p.cmd("endpoint", 0, 1, WG_PORT)

    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind((HOST_IP, OUR_PORT))
    s.settimeout(2.0)

    # First WITHOUT the obfuscation, so the check below means something:
    # the very same code, the very same keys, must succeed here.
    plain = bytes.fromhex(p.cmd("handshake", 0, rnd64(), int(time.time()),
                                time.time_ns() % 10**9, now_us()))
    s.sendto(plain, (NS_IP, WG_PORT))
    answered_plain = True
    try:
        s.recvfrom(4096)
    except socket.timeout:
        answered_plain = False
    ok("control: plain WireGuard, Linux answers", answered_plain,
       "answered" if answered_plain else "silent")

    # Now the same handshake with the parameters on.
    p.cmd("awg", JC, JMIN, JMAX, S1, S2, H1, H2, H3, H4)
    before = sh("wg show wg0 latest-handshakes", ns=True).split()
    before = before[-1] if before else "0"
    obf = bytes.fromhex(p.cmd("handshake", 0, rnd64(), int(time.time()),
                              time.time_ns() % 10**9, now_us()))
    for _ in range(4):
        s.sendto(obf, (NS_IP, WG_PORT))
    silent = True
    try:
        s.recvfrom(4096)
        silent = False
    except socket.timeout:
        pass
    ok("a stock Linux WireGuard ignores the obfuscated handshake", silent,
       "silent" if silent else "it answered -- the obfuscation is a no-op")

    p.close()
    s.close()
    teardown()


def main():
    if os.geteuid() != 0:
        print("this needs root: it creates a network namespace")
        return 2
    print("\n== AmneziaWG 1.0 parameters ==")
    check_constraints()
    print("\n== the shape of the obfuscated packets ==")
    check_shape()
    print("\n== against a stock Linux WireGuard ==")
    check_against_linux()
    print()
    if FAILED:
        print("%d checks FAILED:" % len(FAILED))
        for f in FAILED:
            print("  - %s" % f)
        return 1
    print("all %d AmneziaWG checks passed" % len(RESULTS))
    print("NOTE: no interoperability test against the real AmneziaWG was")
    print("      possible on this machine. See the header of this file.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        teardown()
        print("harness error: %s" % e)
        raise
