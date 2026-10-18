# SPDX-License-Identifier: GPL-2.0-only
import os
import random
import struct
import sys
import unittest
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from odb import frame as F  # noqa: E402


class FrameCodec(unittest.TestCase):
    def test_spec_vectors(self):
        # docs/ODB.md section 2 test vectors
        self.assertEqual(zlib.crc32(b"123456789") & 0xFFFFFFFF, 0xCBF43926)
        self.assertEqual(F.encode(F.Frame(F.PING, 0, b"hi")).hex(), "4f44423101060000000000000200000068692d574d30")
        from odb import proto
        req = F.Frame(F.REQ, 1, proto.enc_req("hello", [("ver", 1), ("client", "odbc")]))
        self.assertEqual(F.encode(req).hex(),
                         "4f44423101010000010000001a0000000568656c6c6f0376657201003106636c69656e7404006f646263aa891c76")
        self.assertEqual(F.Decoder().feed(bytes.fromhex(F.encode(req).hex())), [req])

    def test_type_numbers(self):
        self.assertEqual((F.REQ, F.RESP, F.DATA, F.END, F.ERR, F.PING, F.PONG, F.CANCEL, F.ACK), tuple(range(1, 10)))
        self.assertEqual((F.FLAG_RETRY, F.FLAG_LAST), (1, 2))

    def test_unknown_type_passes_through(self):
        f = F.Frame(77, 5, b"x")
        self.assertEqual(F.Decoder().feed(F.encode(f)), [f])

    def test_wrong_version_is_false_match(self):
        raw = bytearray(F.encode(F.Frame(F.PING, 1, b"a")))
        raw[4] = 2
        f = F.Frame(F.PONG, 2, b"b")
        d = F.Decoder()
        self.assertEqual(d.feed(bytes(raw) + F.encode(f)), [f])

    def test_golden(self):
        raw = F.encode(F.Frame(F.PING, 0x01020304, b"hi", flags=0x0506))
        self.assertEqual(raw[:4], b"ODB1")
        self.assertEqual(raw[4], 1)
        self.assertEqual(raw[5], F.PING)
        self.assertEqual(raw[6:8], b"\x06\x05")
        self.assertEqual(raw[8:12], b"\x04\x03\x02\x01")
        self.assertEqual(raw[12:16], b"\x02\x00\x00\x00")
        self.assertEqual(raw[16:18], b"hi")
        self.assertEqual(struct.unpack("<I", raw[18:])[0], zlib.crc32(raw[:18]) & 0xFFFFFFFF)
        self.assertEqual(len(raw), F.OVERHEAD + 2)

    def test_roundtrip_all_types(self):
        for t in range(1, 10):
            f = F.Frame(t, 7, b"\x00\xffODB1\x00", flags=3)
            self.assertEqual(F.Decoder().feed(F.encode(f)), [f])

    def test_empty_and_max_payload(self):
        for n in (0, 1, F.MAX_PAYLOAD):
            f = F.Frame(F.DATA, 1, os.urandom(n))
            self.assertEqual(F.Decoder().feed(F.encode(f)), [f])
        with self.assertRaises(F.FrameError):
            F.encode(F.Frame(F.DATA, 1, b"x" * (F.MAX_PAYLOAD + 1)))

    def test_byte_by_byte(self):
        fs = [F.Frame(F.DATA, i, os.urandom(i * 7)) for i in range(1, 20)]
        blob = b"".join(F.encode(f) for f in fs)
        d = F.Decoder()
        got = []
        for b in blob:
            got += d.feed(bytes([b]))
        self.assertEqual(got, fs)
        self.assertEqual(d.garbage, 0)

    def test_leading_garbage_and_partial_magic(self):
        f = F.Frame(F.REQ, 9, b"\x04info")
        d = F.Decoder()
        self.assertEqual(d.feed(b"junk OD"), [])
        self.assertEqual(d.feed(b"B"), [])
        self.assertEqual(d.feed(F.encode(f)), [f])      # "ODB" + frame magic: resync finds the real one
        self.assertGreaterEqual(d.garbage, 6)

    def test_bad_crc_resync(self):
        a, b = F.Frame(F.DATA, 1, b"first"), F.Frame(F.DATA, 2, b"second")
        ra = bytearray(F.encode(a))
        ra[F.HDR_LEN + 1] ^= 0xFF
        d = F.Decoder()
        self.assertEqual(d.feed(bytes(ra) + F.encode(b)), [b])
        self.assertEqual(d.bad_crc, 1)

    def test_magic_inside_payload_of_corrupt_frame(self):
        inner = F.encode(F.Frame(F.PING, 5, b"in"))
        outer = bytearray(F.encode(F.Frame(F.DATA, 1, b"aa" + inner + b"zz")))
        outer[-1] ^= 1                       # outer crc broken, inner frame still intact
        d = F.Decoder()
        got = d.feed(bytes(outer))
        self.assertEqual([x.id for x in got], [5])

    def test_oversize_len_rejected(self):
        hdr = F.HDR.pack(F.MAGIC, 1, F.DATA, 0, 1, 65537)
        f = F.Frame(F.PING, 3, b"ok")
        d = F.Decoder()
        self.assertEqual(d.feed(hdr + F.encode(f)), [f])
        self.assertEqual(d.bad_hdr, 1)

    def test_truncated_then_continue(self):
        f = F.Frame(F.DATA, 1, b"x" * 100)
        raw = F.encode(f)
        d = F.Decoder()
        self.assertEqual(d.feed(raw[:50]), [])
        self.assertEqual(d.feed(raw[50:]), [f])

    def test_fuzz_noise_between_frames(self):
        rnd = random.Random(1234)
        fs = [F.Frame(rnd.choice([F.DATA, F.REQ, F.END]), rnd.randrange(1, 1 << 32),
                      bytes(rnd.randrange(256) for _ in range(rnd.randrange(0, 300)))) for _ in range(300)]
        blob = bytearray()
        for f in fs:
            blob += bytes(rnd.randrange(256) for _ in range(rnd.randrange(0, 12))).replace(b"O", b"o")
            blob += F.encode(f)
        d = F.Decoder()
        got = []
        i = 0
        while i < len(blob):
            n = rnd.randrange(1, 40)
            got += d.feed(bytes(blob[i:i + n]))
            i += n
        self.assertEqual(got, fs)

    def test_fuzz_random_bytes_never_crash(self):
        rnd = random.Random(99)
        d = F.Decoder()
        for _ in range(2000):
            d.feed(bytes(rnd.randrange(256) for _ in range(rnd.randrange(1, 200))))
        # a good frame after arbitrary garbage must still decode
        f = F.Frame(F.END, 77, b"done")
        out = d.feed(F.encode(f) * 2)
        self.assertEqual(out[-1], f)
        self.assertLess(len(d.buf), F.HDR_LEN + F.MAX_PAYLOAD + F.CRC_LEN + 1)

    def test_fuzz_bitflips_detected(self):
        rnd = random.Random(7)
        f = F.Frame(F.DATA, 5, bytes(range(200)))
        raw = F.encode(f)
        ok = 0
        for _ in range(500):
            b = bytearray(raw)
            b[rnd.randrange(len(b))] ^= 1 << rnd.randrange(8)
            res = F.Decoder().feed(bytes(b) + F.encode(F.Frame(F.PING, 1)))
            self.assertNotIn(f, [x for x in res if x.type == F.DATA and x.payload != f.payload] + [None])
            if f in res:
                ok += 1
        self.assertEqual(ok, 0)


if __name__ == "__main__":
    unittest.main()
