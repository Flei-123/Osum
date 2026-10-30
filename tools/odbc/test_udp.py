# SPDX-License-Identifier: GPL-2.0-only
import socket
import threading
import unittest

from odb import frame as F
from odb.client import Session


class UdpServer:
    def __init__(self):
        self.s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.s.bind(("127.0.0.1", 0))
        self.s.settimeout(3)
        self.port = self.s.getsockname()[1]
        self.sizes = []
        self.t = threading.Thread(target=self.run, daemon=True)
        self.t.start()

    def run(self):
        try:
            data, addr = self.s.recvfrom(65536)
        except OSError:
            return
        self.sizes.append(len(data))
        dec = F.Decoder()
        for f in dec.feed(data):
            self.s.sendto(F.encode(F.Frame(F.PONG, f.id, f.payload)), addr)


class UdpTransportTest(unittest.TestCase):
    def test_ping_one_datagram_per_frame(self):
        srv = UdpServer()
        s = Session.open("udp:127.0.0.1:%d" % srv.port)
        try:
            self.assertLess(s.ping(timeout=2.0), 2.0)
        finally:
            s.close()
        self.assertEqual(srv.sizes, [F.OVERHEAD + 4])

    def test_default_port(self):
        from odb.transport import open_udp
        t = open_udp("127.0.0.1")
        try:
            self.assertEqual(t.s.getpeername()[1], 6970)
        finally:
            t.close()


if __name__ == "__main__":
    unittest.main()
