import socket, struct, sys

ADDR = sys.argv[1]
PORT = int(sys.argv[2])
NAME = sys.argv[3]
RP = sys.argv[4]
GROUP = "224.0.0.251"


def label(s):
    b = s.encode()
    return bytes([len(b)]) + b


def name(*parts):
    return b"".join(label(p) for p in parts) + b"\0"


def rr(n, typ, rdata, ttl=120):
    return n + struct.pack(">HHIH", typ, 1, ttl, len(rdata)) + rdata


def answer(qid):
    svc = name("_ipp", "_tcp", "local")
    inst = name(NAME, "_ipp", "_tcp", "local")
    host = name("printer-1", "local")
    txt = bytes([len("rp=" + RP)]) + ("rp=" + RP).encode()
    recs = [
        rr(svc, 12, inst),
        rr(inst, 33, struct.pack(">HHH", 0, 0, PORT) + host),
        rr(inst, 16, txt),
        rr(host, 1, socket.inet_aton(ADDR)),
    ]
    head = struct.pack(">HHHHHH", qid, 0x8400, 0, len(recs), 0, 0)
    return head + b"".join(recs)


s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("", 5353))
mreq = struct.pack("4s4s", socket.inet_aton(GROUP), socket.inet_aton(ADDR))
s.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
print("responder ready", flush=True)
while True:
    data, peer = s.recvfrom(2048)
    if len(data) < 12:
        continue
    qid = struct.unpack(">H", data[:2])[0]
    if b"\x04_ipp\x04_tcp\x05local" not in data:
        continue
    print("query from %s:%d id=%04x" % (peer[0], peer[1], qid), flush=True)
    s.sendto(answer(qid), peer)
