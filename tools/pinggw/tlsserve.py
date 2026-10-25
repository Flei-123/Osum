# SPDX-License-Identifier: GPL-2.0-only
import os
import ssl
import struct
import time

MSS = 1200
RESPONSE_BODY = b"nettest ok\n"


class TlsServer:
    def __init__(self, cert, key, port, gw_mac, builders, send, log):
        self.port = port
        self.gw_mac = gw_mac
        self.ip_packet, self.eth, self.pseudo_checksum = builders
        self.send = send
        self.log = log
        self.ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        self.ctx.load_cert_chain(cert, key)
        self.conn = None

    def segment(self, c, flags, seq, payload=b"", options=b""):
        offset = (20 + len(options)) // 4
        seg = struct.pack("!HHIIBBHHH", self.port, c["sport"], seq & 0xFFFFFFFF, c["rcv"] & 0xFFFFFFFF,
                          offset << 4, flags, 65535, 0, 0) + options + payload
        seg = seg[:16] + struct.pack("!H", self.pseudo_checksum(c["dst"], c["src"], 6, seg)) + seg[18:]
        return self.eth(c["mac"], self.gw_mac, 0x0800, self.ip_packet(c["dst"], c["src"], 6, seg))

    def emit(self, c, flags, payload=b"", options=b""):
        self.send(self.segment(c, flags, c["snd"], payload, options))
        c["snd"] += len(payload) + (1 if flags & 0x03 else 0)

    def flush(self, c):
        data = c["out"].read()
        for i in range(0, len(data), MSS):
            self.emit(c, 0x18, data[i:i + MSS])
            time.sleep(0.002)

    def pump(self, c):
        if not c["done"]:
            try:
                c["ssl"].do_handshake()
                c["done"] = True
                self.log.write("TLS-HANDSHAKE-DONE\n")
            except ssl.SSLWantReadError:
                pass
            except ssl.SSLError as e:
                self.log.write("TLS-HANDSHAKE-ERROR %s\n" % e.reason)
                c["done"] = None
        if c["done"] and not c["replied"]:
            try:
                c["request"] += c["ssl"].read(4096)
            except ssl.SSLWantReadError:
                pass
            except ssl.SSLError:
                pass
            if b"\r\n\r\n" in c["request"]:
                self.log.write("HTTP-GET %s\n" % c["request"].split(b"\r\n")[0].decode("latin-1"))
                head = b"HTTP/1.1 200 OK\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % len(RESPONSE_BODY)
                c["ssl"].write(head + RESPONSE_BODY)
                c["replied"] = True
        self.flush(c)
        if c["replied"] and not c["fin_sent"]:
            try:
                c["ssl"].unwrap()
            except ssl.SSLError:
                pass
            self.flush(c)
            self.emit(c, 0x11)
            c["fin_sent"] = True

    def handle(self, frame):
        if frame[14 + 9] != 6 or len(frame) < 54:
            return False
        sport, dport, seq, ack = struct.unpack("!HHII", frame[34:46])
        if dport != self.port:
            return False
        flags = frame[47]
        hlen = (frame[46] >> 4) * 4
        payload = frame[34 + hlen:14 + struct.unpack("!H", frame[16:18])[0]]
        src_ip, dst_ip, src_mac = frame[26:30], frame[30:34], frame[6:12]
        if flags & 0x02:
            self.log.write("TCP-SYN dst=%s port=%d\n" % (".".join(map(str, dst_ip)), dport))
            inc, out = ssl.MemoryBIO(), ssl.MemoryBIO()
            self.conn = {"sport": sport, "src": src_ip, "dst": dst_ip, "mac": src_mac,
                         "rcv": (seq + 1) & 0xFFFFFFFF, "snd": int.from_bytes(os.urandom(4), "big"),
                         "inc": inc, "out": out, "ssl": self.ctx.wrap_bio(inc, out, server_side=True),
                         "done": False, "request": b"", "replied": False, "fin_sent": False}
            self.emit(self.conn, 0x12, options=bytes([2, 4]) + struct.pack("!H", MSS))
            return True
        c = self.conn
        if c is None or c["sport"] != sport or c["src"] != src_ip:
            return True
        if flags & 0x04:
            self.conn = None
            return True
        if payload and seq == c["rcv"]:
            c["rcv"] = (c["rcv"] + len(payload)) & 0xFFFFFFFF
            c["inc"].write(payload)
            self.send(self.segment(c, 0x10, c["snd"]))
            self.pump(c)
        elif payload:
            self.send(self.segment(c, 0x10, c["snd"]))
        if flags & 0x01 and seq + len(payload) == c["rcv"]:
            c["rcv"] = (c["rcv"] + 1) & 0xFFFFFFFF
            self.send(self.segment(c, 0x10, c["snd"]))
            if not c["fin_sent"]:
                self.emit(c, 0x11)
                c["fin_sent"] = True
        return True
