# SPDX-License-Identifier: GPL-2.0-only
import io
import os
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from odb import frame as F  # noqa: E402
from odb import proto  # noqa: E402
from odb.client import Session, Timeout  # noqa: E402
from odb.mock import MockAgent  # noqa: E402
from odb.transport import SocketTransport, open_transport  # noqa: E402


def pair(**kw):
    a, b = socket.socketpair()
    agent = MockAgent(**kw)
    agent.serve_bg(SocketTransport(b).start())
    return Session(SocketTransport(a).start()), agent


class Proto(unittest.TestCase):
    def test_kv_escape(self):
        d = {"cmd": "echo a\nb\\c\r", "x": "1"}
        self.assertEqual(proto.dec_kv(proto.enc_kv(d)), d)

    def test_req(self):
        op, a = proto.dec_req(proto.enc_req("exec", {"cmd": "ls -l\n", "cwd": None}))
        self.assertEqual((op, a), ("exec", {"cmd": "ls -l\n"}))


class SessionOverMock(unittest.TestCase):
    def test_ping_hello_info(self):
        s, _ = pair()
        self.assertLess(s.ping(), 1.0)
        self.assertEqual(s.hello()["agent"], "mock-odbd")
        r, _ = s.call("info")
        self.assertEqual(r["screen"], "1024x768")

    def test_exec_stdout_stderr_code(self):
        s, _ = pair()
        got = []
        r, _ = s.call("exec", {"cmd": "cat /nope"}, on_data=lambda b, f: got.append((b, f)))
        self.assertEqual(r["code"], "1")
        self.assertEqual(got, [(b"cat: no such file\n", proto.FLAG_STDERR)])
        r, body = s.call("exec", {"cmd": "echo hi there"})
        self.assertEqual(body, b"hi there\n")

    def test_push_pull_roundtrip_sizes(self):
        s, ag = pair()
        for n in (0, 1, 4095, 4096, 4097, 300000):
            blob = os.urandom(n)
            r, _ = s.call("push", {"path": "/f%d" % n}, data=blob, chunk=1000 + n % 3000)
            self.assertEqual(int(r["crc32"]), zlib.crc32(blob) & 0xFFFFFFFF)
            self.assertEqual(ag.fs["/f%d" % n], blob)
            r, body = s.call("pull", {"path": "/f%d" % n})
            self.assertEqual(body, blob)

    def test_agent_error(self):
        s, _ = pair()
        with self.assertRaises(proto.AgentError) as c:
            s.call("pull", {"path": "/missing"})
        self.assertEqual(c.exception.code, 2)
        with self.assertRaises(proto.AgentError):
            s.call("frobnicate")

    def test_token(self):
        a, b = socket.socketpair()
        MockAgent(token="s3cret").serve_bg(SocketTransport(b).start())
        s = Session(SocketTransport(a).start(), token="wrong")
        with self.assertRaises(proto.AgentError) as c:
            s.hello()
        self.assertEqual(c.exception.code, 13)
        with self.assertRaises(proto.AgentError):
            s.call("info")                     # still locked
        s.token = "s3cret"
        s.hello()
        s.call("info")

    def test_noise_and_slow_uart(self):
        s, _ = pair(noise_every=2, chunk=7)
        for i in range(10):
            r, body = s.call("exec", {"cmd": "echo n%d" % i})
            self.assertEqual(body, ("n%d\n" % i).encode())
        self.assertGreater(s.dec.garbage, 0)

    def test_corrupt_reply_then_recover(self):
        s, _ = pair(corrupt_every=2)
        ok = timeouts = 0
        for i in range(8):
            try:
                s.call("info", timeout=0.5)
                ok += 1
            except Timeout:
                timeouts += 1
        self.assertGreater(timeouts, 0)
        self.assertGreater(ok, 0)
        self.assertGreater(s.dec.bad_crc, 0)

    def test_ping_unanswered_times_out(self):
        a, b = socket.socketpair()
        s = Session(SocketTransport(a).start())
        with self.assertRaises(Timeout):
            s.ping(timeout=0.3)
        b.close()

    def test_big_stream(self):
        s, _ = pair()
        r, body = s.call("exec", {"cmd": "big 1000000"})
        self.assertEqual(len(body), 1000000)

    def test_interleaved_stale_ids_ignored(self):
        s, _ = pair()
        s.send(F.Frame(F.DATA, 999, b"stale"))
        r, body = s.call("exec", {"cmd": "echo x"})
        self.assertEqual(body, b"x\n")


class Transports(unittest.TestCase):
    def test_unix_and_tcp(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "o.sock")
            srv = socket.socket(socket.AF_UNIX)
            srv.bind(p)
            srv.listen(1)
            ag = MockAgent()
            threading.Thread(target=lambda: ag.serve_bg(SocketTransport(srv.accept()[0]).start()), daemon=True).start()
            s = Session(open_transport("unix:" + p))
            self.assertEqual(s.hello()["proto"], "1")
            s.close()
        srv = socket.socket()
        srv.bind(("127.0.0.1", 0))
        srv.listen(1)
        port = srv.getsockname()[1]
        threading.Thread(target=lambda: ag.serve_bg(SocketTransport(srv.accept()[0]).start()), daemon=True).start()
        s = Session(open_transport("tcp:127.0.0.1:%d" % port))
        r, _ = s.call("info")
        self.assertIn("uptime_s", r)

    @unittest.skipIf(sys.platform == "win32", "pty is posix-only")
    def test_pty(self):
        import pty
        import tty
        master, slave = pty.openpty()
        tty.setraw(slave)
        name = os.ttyname(slave)
        from odb.transport import TtyTransport
        ag = MockAgent()
        ag.serve_bg(TtyTransport(master).start())
        s = Session(open_transport("tty:" + name))
        self.assertEqual(s.hello()["agent"], "mock-odbd")
        blob = os.urandom(20000)
        r, _ = s.call("push", {"path": "/p"}, data=blob)
        self.assertEqual(ag.fs["/p"], blob)

    def test_connect_retry_fails_cleanly(self):
        from odb.transport import TransportError
        with self.assertRaises(TransportError):
            open_transport("unix:/nonexistent/odb.sock", wait=0.3)


class CliEndToEnd(unittest.TestCase):
    """Run the real CLI as a subprocess against a mock on a unix socket."""

    @classmethod
    def setUpClass(cls):
        cls.d = tempfile.mkdtemp()
        cls.sock = os.path.join(cls.d, "odb.sock")
        cls.srv = subprocess.Popen([sys.executable, "-I", "-c", "import sys; sys.path.insert(0, sys.argv[1]); from odb.mock import main; main(sys.argv[2:])",
                                    HERE, "--unix", cls.sock], stdout=subprocess.PIPE)
        cls.srv.stdout.readline()

    @classmethod
    def tearDownClass(cls):
        cls.srv.terminate()
        cls.srv.wait()
        import shutil
        shutil.rmtree(cls.d, ignore_errors=True)

    def odbc(self, *a, expect=0):
        p = subprocess.run([sys.executable, "-I", os.path.join(HERE, "odbc.py"), "--port", "unix:" + self.sock, "-t", "5"] + list(a),
                           capture_output=True, timeout=30)
        self.assertEqual(p.returncode, expect, p.stderr.decode())
        return p

    def test_commands(self):
        self.assertIn(b"screen=1024x768", self.odbc("info").stdout)
        self.assertEqual(self.odbc("exec", "echo", "hello").stdout, b"hello\n")
        self.odbc("exec", "false", expect=1)
        self.assertIn(b"taskbar", self.odbc("ps").stdout)
        self.assertIn(b"odbd up", self.odbc("logs").stdout)
        self.odbc("input", "type", "hello")
        self.odbc("kill", "7")
        self.odbc("kill", "7", expect=4)
        self.odbc("reboot")
        self.odbc("ping", "-c", "3")

    def test_push_pull_shot(self):
        src = os.path.join(self.d, "a.bin")
        dst = os.path.join(self.d, "b.bin")
        open(src, "wb").write(os.urandom(70000))
        self.odbc("push", src, "/x/a.bin")
        self.odbc("pull", "/x/a.bin", dst)
        self.assertEqual(open(src, "rb").read(), open(dst, "rb").read())
        png = os.path.join(self.d, "s.png")
        self.odbc("shot", png)
        self.assertEqual(open(png, "rb").read(8), b"\x89PNG\r\n\x1a\n")

    def test_devices_lists_offline(self):
        p = subprocess.run([sys.executable, "-I", os.path.join(HERE, "odbc.py"), "--port", "unix:" + self.sock + ";unix:/nonexistent.sock", "devices"],
                           capture_output=True, timeout=30)
        out = p.stdout.decode()
        self.assertIn("online", out)
        self.assertIn("offline", out)
        self.assertEqual(p.returncode, 0)

    def test_no_port_fails(self):
        p = subprocess.run([sys.executable, "-I", os.path.join(HERE, "odbc.py"), "info"], capture_output=True,
                           env={k: v for k, v in os.environ.items() if k != "ODB_PORT"})
        self.assertNotEqual(p.returncode, 0)


if __name__ == "__main__":
    unittest.main()
