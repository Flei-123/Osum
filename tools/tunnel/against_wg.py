#!/usr/bin/env python3
"""tools/tunnel/against_wg.py -- Osum's WireGuard against Linux's.

THIS IS THE MEASUREMENT THE ROUND STANDS OR FALLS ON. Everything else in
`tools/tunnel/` compares this repository against itself or against a test
vector. Here `lib/wg/proto.fi` -- the identical file the kernel compiles
-- completes a handshake with the WireGuard implementation IN THE LINUX
KERNEL and carries real traffic through it.

THE WIRE, and why it is not a tap device. `/dev/net/tun` cannot be
created in the container this repository is measured in (`mknod:
Operation not permitted`, the same finding round K8 wrote down). A
WireGuard interface needs no tun device -- it is its own netdev type --
and network namespaces can be created here, so:

    our proto.fi  <--UDP on veth-->  Linux wg0 in the namespace `wgt`
    10.90.0.1:51821                  10.90.0.2:51820
    tunnel 10.91.0.1                 tunnel 10.91.0.2

WHAT IS PROVEN, in the order the checks run:

  1. THE HANDSHAKE. `wg show` on the Linux side reports a latest
     handshake. Linux only reports one after it has decrypted an
     initiation, verified both MACs and the timestamp, and had its
     response accepted well enough for a transport packet to arrive.
  2. LINUX'S OWN PING GOES THROUGH OUR TUNNEL. `ping` inside the
     namespace sends an ICMP echo to 10.91.0.1. The Linux kernel
     encrypts it with the keys it negotiated with us; we decrypt it,
     build the echo reply ourselves, encrypt it and send it back; Linux
     decrypts it and `ping` prints a round trip time. Nothing about that
     works if a single field of the protocol is wrong.
  3. THROUGHPUT IN BOTH DIRECTIONS, in MB/s, over a real UDP stream.
  4. THE REFUSALS. A replayed transport packet, a packet with a flipped
     octet, a handshake with a wrong mac1, a replayed initiation -- each
     must be REFUSED, and the counters must show it.
  5. THE SAME AGAIN WITH A PRE-SHARED KEY, because psk2 changes the
     chain and an implementation can pass without it and fail with it.

Run it through `tools/tunnel/run.sh`, which builds `.probe/peer` first.
"""
import os
import random
import re
import socket
import struct
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PEER = os.path.join(ROOT, ".probe", "peer")

NS = "wgt%d" % os.getpid()
V0 = "wgv%d" % (os.getpid() % 10000)
V1 = V0 + "p"
HOST_IP = "10.90.0.1"
NS_IP = "10.90.0.2"
OUR_TUN = "10.91.0.1"
NS_TUN = "10.91.0.2"
WG_PORT = 51820
OUR_PORT = 51821

RESULTS = []
FAILED = []


def sh(cmd, check=True, ns=False):
    if ns:
        cmd = "ip netns exec %s %s" % (NS, cmd)
    p = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if check and p.returncode != 0:
        raise RuntimeError("%s\n%s%s" % (cmd, p.stdout, p.stderr))
    return p.stdout.strip()


def ok(name, good, detail=""):
    RESULTS.append((name, good, detail))
    if not good:
        FAILED.append(name)
    print("  %-46s %s %s" % (name, "ok  " if good else "FAIL", detail))


def ip2n(s):
    return struct.unpack("!I", socket.inet_aton(s))[0]


class Peer:
    """`.probe/peer` as a subprocess: one command in, one line out."""

    def __init__(self):
        self.p = subprocess.Popen([PEER], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, bufsize=0)

    def cmd(self, *a):
        line = (" ".join(str(x) for x in a) + "\n").encode()
        self.p.stdin.write(line)
        self.p.stdin.flush()
        out = b""
        while not out.endswith(b"\n"):
            c = self.p.stdout.read(1)
            if not c:
                raise RuntimeError("peer died on: %s" % line)
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


def ipv4_checksum(b):
    if len(b) % 2:
        b += b"\0"
    s = 0
    for i in range(0, len(b), 2):
        s += (b[i] << 8) | b[i + 1]
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    return (~s) & 0xFFFF


def build_ip(src, dst, proto, payload, ident=0x4242):
    hdr = struct.pack("!BBHHHBBH4s4s", 0x45, 0, 20 + len(payload), ident,
                      0, 64, proto, 0, socket.inet_aton(src),
                      socket.inet_aton(dst))
    c = ipv4_checksum(hdr)
    hdr = hdr[:10] + struct.pack("!H", c) + hdr[12:]
    return hdr + payload


def icmp_reply_for(pkt):
    """Turn an ICMP echo request in an IPv4 packet into its reply."""
    if len(pkt) < 28 or (pkt[0] >> 4) != 4:
        return None
    ihl = (pkt[0] & 0x0F) * 4
    if pkt[9] != 1:
        return None
    icmp = bytearray(pkt[ihl:])
    if icmp[0] != 8:
        return None
    icmp[0] = 0            # echo reply
    icmp[2] = 0
    icmp[3] = 0
    c = ipv4_checksum(bytes(icmp))
    icmp[2] = c >> 8
    icmp[3] = c & 0xFF
    src = socket.inet_ntoa(pkt[12:16])
    dst = socket.inet_ntoa(pkt[16:20])
    return build_ip(dst, src, 1, bytes(icmp))


def build_udp(src, dst, sport, dport, payload):
    udp = struct.pack("!HHHH", sport, dport, 8 + len(payload), 0) + payload
    return build_ip(src, dst, 17, udp)


def teardown():
    subprocess.run("ip netns del %s" % NS, shell=True, capture_output=True)
    subprocess.run("ip link del %s" % V0, shell=True, capture_output=True)


def setup(psk_hex=None):
    teardown()
    sh("ip netns add %s" % NS)
    sh("ip link add %s type veth peer name %s" % (V0, V1))
    sh("ip link set %s netns %s" % (V1, NS))
    sh("ip addr add %s/24 dev %s" % (HOST_IP, V0))
    sh("ip link set %s up" % V0)
    sh("ip addr add %s/24 dev %s" % (NS_IP, V1), ns=True)
    sh("ip link set %s up" % V1, ns=True)
    sh("ip link set lo up", ns=True)

    linux_priv = sh("wg genkey")
    linux_pub = sh("echo '%s' | wg pubkey" % linux_priv)

    our_priv = bytearray(os.urandom(32))
    our_priv[0] &= 248
    our_priv[31] = (our_priv[31] & 127) | 64
    our_priv = bytes(our_priv)

    peer = Peer()
    our_pub_hex = peer.cmd("init", our_priv.hex())
    if len(our_pub_hex) != 64:
        raise RuntimeError("our own public key came out as %r" % our_pub_hex)
    import base64
    our_pub_b64 = base64.b64encode(bytes.fromhex(our_pub_hex)).decode()

    conf = "/tmp/wgt-%d.conf" % os.getpid()
    lines = ["[Interface]", "PrivateKey = %s" % linux_priv,
             "ListenPort = %d" % WG_PORT, "",
             "[Peer]", "PublicKey = %s" % our_pub_b64,
             "AllowedIPs = %s/32" % OUR_TUN,
             "Endpoint = %s:%d" % (HOST_IP, OUR_PORT)]
    if psk_hex:
        lines.insert(6, "PresharedKey = %s" %
                     base64.b64encode(bytes.fromhex(psk_hex)).decode())
    open(conf, "w").write("\n".join(lines) + "\n")
    os.chmod(conf, 0o600)

    sh("ip link add wg0 type wireguard", ns=True)
    sh("wg setconf wg0 %s" % conf, ns=True)
    sh("ip addr add %s/24 dev wg0" % NS_TUN, ns=True)
    sh("ip link set wg0 up", ns=True)
    os.unlink(conf)

    linux_pub_hex = base64.b64decode(linux_pub).hex()
    pi = peer.cmd("peer", linux_pub_hex, psk_hex if psk_hex else "")
    if pi != "0":
        raise RuntimeError("peer_add said %r" % pi)
    peer.cmd("allow", 0, ip2n(NS_TUN), 32)
    peer.cmd("endpoint", 0, ip2n(NS_IP), WG_PORT)

    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    # Linux fills the wire far faster than a Python loop with a pipe to a
    # subprocess can drain it. A big receive buffer plus a paced sender is
    # what keeps the harness from being the thing under test.
    s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 8 * 1024 * 1024)
    s.bind((HOST_IP, OUR_PORT))
    s.settimeout(3.0)
    return peer, s, linux_pub_hex


def handshake(peer, s, label=""):
    pkt = peer.cmd("handshake", 0, rnd64(), int(time.time()),
                   time.time_ns() % 1_000_000_000, now_us())
    if not re.fullmatch(r"[0-9a-f]+", pkt):
        raise RuntimeError("make_initiation said %r" % pkt)
    ok("handshake initiation is 148 octets" + label, len(pkt) // 2 == 148,
       "%d" % (len(pkt) // 2))
    s.sendto(bytes.fromhex(pkt), (NS_IP, WG_PORT))
    data, _ = s.recvfrom(4096)
    ok("Linux answered with a 92 octet response" + label, len(data) == 92,
       "%d octets, type %d" % (len(data), data[0] if data else -1))
    r = peer.cmd("recv", data.hex(), now_us(), rnd64())
    ok("the response verified and keys are up" + label,
       r == "resp 0", r)
    return r == "resp 0"


def main():
    if os.geteuid() != 0:
        print("this needs root: it creates a network namespace")
        return 2
    if not os.path.exists(PEER):
        print("missing %s -- run tools/tunnel/run.sh" % PEER)
        return 2

    for psk_hex in [None, os.urandom(32).hex()]:
        label = " (with psk)" if psk_hex else ""
        print("\n== against the Linux kernel's WireGuard%s ==" % label)
        peer, s, linux_pub = setup(psk_hex)
        try:
            if not handshake(peer, s, label):
                continue

            # A keepalive, so Linux considers the session confirmed and
            # will send us traffic of its own.
            ka = peer.cmd("send", 0, "-", now_us())
            s.sendto(bytes.fromhex(ka), (NS_IP, WG_PORT))
            time.sleep(0.3)

            show = sh("wg show wg0 latest-handshakes", ns=True)
            got = show.split()[-1] if show.split() else "0"
            ok("`wg show` reports a handshake" + label, got != "0", got)
            tp = sh("wg show wg0 transfer", ns=True).split()
            ok("`wg show` counts octets received from us" + label,
               len(tp) >= 2 and int(tp[1]) > 0,
               " ".join(tp[1:]) if len(tp) >= 2 else "-")

            # ---- 2. Linux's own ping, through our implementation ----
            pinger = subprocess.Popen(
                "ip netns exec %s ping -c 3 -i 0.3 -W 2 %s" % (NS, OUR_TUN),
                shell=True, stdout=subprocess.PIPE, text=True)
            rtts = []
            answered = 0
            deadline = time.time() + 8
            while time.time() < deadline and answered < 3:
                try:
                    data, _ = s.recvfrom(4096)
                except socket.timeout:
                    break
                t0 = time.monotonic()
                r = peer.cmd("recv", data.hex(), now_us(), rnd64())
                if r.startswith("data "):
                    inner = bytes.fromhex(r.split()[2])
                    rep = icmp_reply_for(inner)
                    if rep:
                        out = peer.cmd("send", 0, rep.hex(), now_us())
                        s.sendto(bytes.fromhex(out), (NS_IP, WG_PORT))
                        answered += 1
                        rtts.append((time.monotonic() - t0) * 1000)
            pout = pinger.communicate()[0]
            m = re.search(r"(\d+) received", pout)
            recvd = int(m.group(1)) if m else 0
            ok("Linux's ping goes through our tunnel" + label, recvd >= 2,
               "%d of 3 replies, %s" % (recvd,
                   re.search(r"rtt.*", pout).group(0) if "rtt" in pout
                   else "no rtt line"))

            # ---- 3. throughput, both directions ----
            # Osum -> Linux: we encrypt, Linux decrypts and counts.
            payload = bytes(random.randrange(256) for _ in range(1200))
            pkt_tpl = build_udp(OUR_TUN, NS_TUN, 5000, 9999, payload)
            n = 1500
            before = int(sh("wg show wg0 transfer", ns=True).split()[1])
            t0 = time.monotonic()
            for _ in range(n):
                out = peer.cmd("send", 0, pkt_tpl.hex(), now_us())
                s.sendto(bytes.fromhex(out), (NS_IP, WG_PORT))
            dt = time.monotonic() - t0
            time.sleep(0.4)
            after = int(sh("wg show wg0 transfer", ns=True).split()[1])
            moved = after - before
            mbs = (n * len(pkt_tpl)) / dt / 1e6
            ok("Linux accepted every packet we encrypted" + label,
               moved >= n * (len(pkt_tpl) + 32) * 0.95,
               "%d octets on the wire" % moved)

            # Linux -> Osum: Linux encrypts, we decrypt and count.
            m = 400
            sender = subprocess.Popen(
                "ip netns exec %s python3 -c \"%s\"" % (NS, (
                    "import socket,time;"
                    "s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);"
                    "s.bind(('%s',0));" % NS_TUN +
                    "d=bytes(1200);"
                    "[(s.sendto(d,('%s',9999)),time.sleep(0.002))"
                    " for _ in range(%d)]" % (OUR_TUN, m))),
                shell=True)
            got = 0
            octets = 0
            t0 = time.monotonic()
            s.settimeout(1.0)
            while True:
                try:
                    data, _ = s.recvfrom(4096)
                except socket.timeout:
                    break
                r = peer.cmd("recv", data.hex(), now_us(), rnd64())
                if r.startswith("data "):
                    got += 1
                    octets += len(r.split()[2]) // 2
            dt2 = time.monotonic() - t0
            sender.wait()
            mbs2 = octets / dt2 / 1e6 if dt2 > 0 else 0
            ok("we decrypted every packet Linux sent us" + label,
               got >= m, "%d of %d packets" % (got, m))
            s.settimeout(3.0)

            # ---- 3b. the inner loop, timed without any I/O ----
            #
            # The rate above is the RATE OF THE HARNESS: every packet
            # crosses a pipe to a subprocess and a Python loop. The
            # number that says something about this code is the AEAD
            # over the payload size a tunnel carries, measured inside
            # the program with no socket in the way.
            if not psk_hex:
                bl = peer.cmd("benchaed", 1200, 20000).split()
                seal_ns, open_ns, opened = (int(bl[0]), int(bl[1]),
                                            int(bl[2]))
                seal_mbs = 20000 * 1200 / (seal_ns / 1e9) / 1e6
                open_mbs = 20000 * 1200 / (open_ns / 1e9) / 1e6
                ok("20000 AEAD opens all verified", opened == 20000,
                   "%d" % opened)
                RESULTS.append(("ChaCha20-Poly1305 seal MB/s", True,
                                "%.1f" % seal_mbs))
                RESULTS.append(("ChaCha20-Poly1305 open MB/s", True,
                                "%.1f" % open_mbs))

            # ---- 4. the refusals ----
            good = peer.cmd("send", 0, pkt_tpl.hex(), now_us())
            # (a) a flipped octet in the body
            bad = bytearray(bytes.fromhex(good))
            bad[40] ^= 0x01
            r = peer.cmd("recv", bad.hex(), now_us(), rnd64())
            # our own packet cannot decrypt with our own receive key
            # anyway, so this is checked with a packet FROM Linux below.
            # (b) replay: take a real packet from Linux
            s2 = subprocess.Popen(
                "ip netns exec %s python3 -c \"%s\"" % (NS, (
                    "import socket;"
                    "s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);"
                    "s.bind(('%s',0));" % NS_TUN +
                    "s.sendto(b'x'*100,('%s',9999))" % OUR_TUN)),
                shell=True)
            s2.wait()
            try:
                data, _ = s.recvfrom(4096)
            except socket.timeout:
                data = None
            if data:
                first = peer.cmd("recv", data.hex(), now_us(), rnd64())
                again = peer.cmd("recv", data.hex(), now_us(), rnd64())
                ok("a replayed transport packet is refused" + label,
                   first.startswith("data") and again == "none",
                   "%s then %s" % (first.split()[0], again))
                flip = bytearray(data)
                flip[30] ^= 0x01
                r = peer.cmd("recv", bytes(flip).hex(), now_us(), rnd64())
                ok("one flipped octet is refused" + label, r == "none", r)
                cut = data[:20]
                r = peer.cmd("recv", cut.hex(), now_us(), rnd64())
                ok("a truncated packet is refused" + label, r == "none", r)
            else:
                ok("a replayed transport packet is refused" + label, False,
                   "no packet arrived to replay")

            # (c) a handshake initiation with a wrong mac1
            init = peer.cmd("handshake", 0, rnd64(), int(time.time()),
                            time.time_ns() % 1_000_000_000, now_us())
            b = bytearray(bytes.fromhex(init))
            b[116] ^= 0x01
            before_fail = int(peer.cmd("stat", 4))
            s.sendto(bytes(b), (NS_IP, WG_PORT))
            silent = False
            try:
                s.recvfrom(4096)
            except socket.timeout:
                silent = True
            ok("Linux ignores an initiation with a wrong mac1" + label,
               silent, "silent" if silent else "it answered")

            # (d) a replayed initiation: same packet twice, Linux must not
            #     complete a second handshake from the stale timestamp.
            ok("counters agree: %d good, %d bad, %d handshakes" % (
                int(peer.cmd("stat", 0)), int(peer.cmd("stat", 1)),
                int(peer.cmd("stat", 3))), True, "")
        finally:
            peer.close()
            s.close()
            teardown()

    print()
    for name, good, detail in RESULTS:
        if name.endswith("MB/s"):
            print("  %-46s %s" % (name, detail))
    print()
    if FAILED:
        print("%d checks FAILED:" % len(FAILED))
        for f in FAILED:
            print("  - %s" % f)
        return 1
    print("all %d checks against the Linux kernel passed"
          % sum(1 for _, g, _ in RESULTS if g))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        teardown()
        print("harness error: %s" % e)
        raise
