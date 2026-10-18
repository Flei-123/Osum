# SPDX-License-Identifier: GPL-2.0-only
import os
import random
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from odb import proto  # noqa: E402


class Tlv(unittest.TestCase):
    def test_roundtrip_and_lists(self):
        b = proto.enc_tlv([("arg", ["ls", "-l", "/"]), ("cwd", "/tmp"), ("skip", None), ("n", 5), ("b", True)])
        t = proto.dec_tlv(b)
        self.assertEqual(t.getall("arg"), ["ls", "-l", "/"])
        self.assertEqual(t.get("cwd"), "/tmp")
        self.assertNotIn("skip", t)
        self.assertEqual(t.geti("n"), 5)
        self.assertEqual(t.get("b"), "1")
        self.assertEqual([k for k, _ in t.pairs], ["arg", "arg", "arg", "cwd", "n", "b"])

    def test_binary_and_utf8_values(self):
        t = proto.dec_tlv(proto.enc_tlv({"text": "grüße €", "raw": b"\x00\xff"}))
        self.assertEqual(t.get("text"), "grüße €")
        self.assertEqual(t.getb("raw"), b"\x00\xff")

    def test_limits(self):
        proto.enc_tlv({"k": b"x" * 65535})
        with self.assertRaises(proto.ProtoError):
            proto.enc_tlv({"k": b"x" * 65536})
        with self.assertRaises(proto.ProtoError):
            proto.enc_tlv({"k" * 256: "v"})

    def test_truncated_rejected(self):
        b = proto.enc_tlv({"key": "value"})
        for n in range(1, len(b)):
            with self.assertRaises(proto.ProtoError):
                proto.dec_tlv(b[:n])

    def test_fuzz_never_crashes(self):
        rnd = random.Random(5)
        for _ in range(3000):
            b = bytes(rnd.randrange(256) for _ in range(rnd.randrange(0, 40)))
            try:
                proto.dec_tlv(b)
            except proto.ProtoError:
                pass
            try:
                proto.dec_req(b)
            except proto.ProtoError:
                pass

    def test_req(self):
        cmd, a = proto.dec_req(proto.enc_req("exec", {"cmd": "ls -l\n", "cwd": None}))
        self.assertEqual((cmd, a.get("cmd")), ("exec", "ls -l\n"))
        self.assertEqual(proto.enc_req("hello", [("ver", 1)])[:6], b"\x05hello")

    def test_streams(self):
        self.assertEqual(proto.dec_data(proto.enc_data(2, b"err")), (2, b"err"))
        self.assertEqual(proto.dec_file(proto.enc_file(2**40 + 5, b"abc")), (2**40 + 5, b"abc"))
        self.assertEqual(proto.enc_file(1, b"")[:9], b"\x03\x01\x00\x00\x00\x00\x00\x00\x00")
        self.assertEqual(proto.dec_ack(proto.enc_ack(3, 70000)), (3, 70000))
        st, t = proto.dec_end(proto.enc_end(3, {"size": 9}))
        self.assertEqual((st, t.geti("size")), (3, 9))

    def test_err(self):
        e = proto.err_from(proto.enc_tlv([("code", "ENOENT"), ("msg", "gone"), ("errno", 2)]))
        self.assertEqual((e.code, e.msg, e.errno), ("ENOENT", "gone", 2))


if __name__ == "__main__":
    unittest.main()
