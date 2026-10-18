# SPDX-License-Identifier: GPL-2.0-only
import hashlib
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
from odb.client import Session, Timeout, auth_mac  # noqa: E402
from odb.mock import MockAgent  # noqa: E402
from odb.transport import SocketTransport, open_transport, TransportError  # noqa: E402

TOKEN = "0123456789abcdef-mock"


def pair(token=TOKEN, login=True, sess_token=TOKEN, **kw):
    a, b = socket.socketpair()
    kw.setdefault("resend_s", 0.3)
    agent = MockAgent(token=token, **kw)
    agent.serve_bg(SocketTransport(b).start())
    s = Session(SocketTransport(a).start(), token=sess_token, retry_s=0.3, ack_timeout=0.3)
    if login:
        s.login()
    return s, agent


class Auth(unittest.TestCase):
    def test_hello_fields(self):
        s, _ = pair(login=False)
        h = s.hello()
        self.assertEqual((h.get("agent"), h.get("auth"), h.geti("maxchunk")), ("odbd", "token", 32768))
        self.assertEqual(len(bytes.fromhex(h.get("nonce"))), 16)
        self.assertIn("exec", h.get("features"))

    def test_mac_known_answer(self):
        nonce = "00" * 16
        import hmac
        want = hmac.new(b"tok", b"ODB1-auth" + bytes(16), hashlib.sha256).hexdigest()
        self.assertEqual(auth_mac("tok", nonce), want)

    def test_not_authenticated_before_auth(self):
        s, _ = pair(login=False)
        s.hello()
        with self.assertRaises(proto.AgentError) as c:
            s.request("info")
        self.assertEqual(c.exception.code, "EAUTH")
        s.ping()
        s.request("ping")

    def test_wrong_token(self):
        s, ag = pair(login=False, sess_token="wrong-token-wrong-token")
        with self.assertRaises(proto.AgentError) as c:
            s.login()
        self.assertEqual(c.exception.code, "EAUTH")
        self.assertEqual(ag.bad_auth, 1)
        with self.assertRaises(proto.AgentError):
            s.request("info")

    def test_no_token_given(self):
        s, _ = pair(login=False, sess_token=None)
        with self.assertRaises(proto.AgentError) as c:
            s.login()
        self.assertEqual(c.exception.code, "EAUTH")

    def test_nonce_changes_per_hello(self):
        s, _ = pair(login=False)
        self.assertNotEqual(s.hello().get("nonce"), s.hello().get("nonce"))

    def test_agent_without_token_refuses_all(self):
        s, _ = pair(login=False, token="")
        with self.assertRaises(proto.AgentError):
            s.login()


class Commands(unittest.TestCase):
    def test_ping_rtt(self):
        s, _ = pair(login=False)
        self.assertLess(s.ping(), 1.0)

    def test_info(self):
        s, _ = pair()
        r = s.request("info")
        self.assertEqual(r.get("screen"), "1024x768")
        self.assertEqual(r.getall("idle_core"), ["0:98", "1:96"])
        self.assertEqual(r.geti("idle_pct"), 97)

    def test_exec_streams_and_exit(self):
        s, _ = pair()
        r, out, err = s.exec(cmd="echo hi there")
        self.assertEqual((out, r.geti("exit")), (b"hi there\n", 0))
        r, out, err = s.exec(cmd="cat /nope")
        self.assertEqual((err, r.geti("exit")), (b"cat: no such file\n", 1))
        r, out, err = s.exec(argv=["echo", "a", "b"])
        self.assertEqual(out, b"a b\n")

    def test_exec_stdin(self):
        s, _ = pair()
        blob = os.urandom(100000)
        r, out, err = s.exec(cmd="cat", stdin=blob)
        self.assertEqual(out, blob)

    def test_exec_big_output(self):
        s, _ = pair()
        r, out, _ = s.exec(cmd="big 1000000")
        self.assertEqual(len(out), 1000000)

    def test_busy(self):
        s, _ = pair()

        def start(fid):
            s.send(F.Frame(F.REQ, s.new_id(), proto.enc_req("info")))   # second request while exec runs
        s.request("exec", {"cmd": "sleep 0.5"}, on_start=start)
        self.assertEqual([proto.err_from(f.payload).code for f in s.stray if f.type == F.ERR], ["EBUSY"])

    def test_cancel(self):
        s, _ = pair()
        box = {}

        def start(fid):
            box["fid"] = fid
            threading.Timer(0.2, lambda: s.cancel(fid)).start()
        with self.assertRaises(proto.AgentError) as c:
            s.request("exec", {"cmd": "sleep 30"}, on_start=start, timeout=5)
        self.assertEqual(c.exception.code, "ECANCEL")
        s.request("info")                      # agent usable again

    def test_ps_kill(self):
        s, ag = pair()
        r, body = s.collect_stream("ps", {}, proto.STDOUT)
        lines = body.decode().splitlines()
        self.assertEqual(lines[0].split("\t")[:3], ["pid", "ppid", "uid"])
        self.assertEqual(r.geti("count"), 4)
        s.request("kill", {"pid": 7, "sig": "KILL"})
        self.assertEqual(ag.killed, [(7, "KILL")])
        with self.assertRaises(proto.AgentError) as c:
            s.request("kill", {"pid": 7})
        self.assertEqual(c.exception.code, "ENOENT")

    def test_logs_and_follow_cancel(self):
        s, _ = pair()
        r, body = s.collect_stream("logs", {"lines": 2}, proto.LOG)
        self.assertEqual(body.count(b"\n"), 2)
        got = []

        def start(fid):
            threading.Timer(0.7, lambda: s.cancel(fid)).start()
        with self.assertRaises(proto.AgentError):
            s.request("logs", {"follow": 1}, on_frame=lambda f: got.append(f), on_start=start, timeout=5)
        self.assertGreaterEqual(len(got), 2)

    def test_shot_formats(self):
        s, _ = pair()
        r, png = s.collect_stream("shot", {"format": "png"}, proto.SHOT)
        self.assertEqual((png[:8], r.geti("w"), r.geti("bytes")), (b"\x89PNG\r\n\x1a\n", 8, len(png)))
        r, ppm = s.collect_stream("shot", {"format": "ppm"}, proto.SHOT)
        self.assertTrue(ppm.startswith(b"P6"))
        r, raw = s.collect_stream("shot", {"format": "raw"}, proto.SHOT)
        self.assertEqual(len(raw), 8 * 8 * 4)

    def test_input_kinds(self):
        s, ag = pair()
        s.request("input", {"kind": "key", "key": "Enter", "mods": "ctrl+shift"})
        s.request("input", {"kind": "text", "text": "hallo"})
        s.request("input", {"kind": "mouse", "x": 10, "y": 20, "button": "left", "action": "click"})
        self.assertEqual([i["kind"] for i in ag.inputs], ["key", "text", "mouse"])
        self.assertEqual(ag.inputs[2]["x"], "10")

    def test_crashdump(self):
        s, ag = pair()
        r, body = s.collect_stream("crashdump", {"op": "list"}, proto.STDOUT)
        self.assertIn(b"c1", body)
        r, data = s.file_download("crashdump", {"op": "get", "id": "c1"})
        self.assertEqual(data, ag.crashes["c1"])
        s.request("crashdump", {"op": "clear", "id": "c1"})
        with self.assertRaises(proto.AgentError):
            s.request("crashdump", {"op": "get", "id": "c1"})

    def test_reboot_shutdown(self):
        s, ag = pair()
        s.request("reboot", {"mode": "force"})
        self.assertEqual(ag.rebooted, "reboot:force")
        s.request("shutdown", {"poweroff": 1})
        self.assertEqual(ag.rebooted, "shutdown:normal")

    def test_allow_list_and_unknown(self):
        s, _ = pair(allow="info,exec")
        s.request("info")
        with self.assertRaises(proto.AgentError) as c:
            s.request("kill", {"pid": 1})
        self.assertEqual(c.exception.code, "EACCES")
        with self.assertRaises(proto.AgentError) as c:
            s.request("frobnicate")
        self.assertEqual(c.exception.code, "EUNSUP")

    def test_unknown_frame_type(self):
        s, _ = pair()
        s.send(F.Frame(99, 42, b"?"))
        f = s.poll(1.0)
        self.assertEqual((f.type, f.id), (F.ERR, 42))
        self.assertEqual(proto.err_from(f.payload).code, "EUNSUP")

    def test_shell_session(self):
        s, _ = pair()
        out = bytearray()

        def start(fid):
            def feed():
                time.sleep(0.1)
                s.send_stream(fid, proto.STDIN, b"echo one\n")
                time.sleep(0.2)
                s.send_stream(fid, proto.STDIN, b"exit\n")
            threading.Thread(target=feed, daemon=True).start()

        def on_frame(f):
            if f.type == F.DATA:
                out.extend(proto.dec_data(f.payload)[1])
        r = s.request("shell", {"cols": 80, "rows": 24}, on_frame=on_frame, on_start=start, timeout=5)
        self.assertEqual(r.geti("exit"), 0)
        self.assertIn(b"one\n", out)


class FileTransfer(unittest.TestCase):
    def test_push_pull_sizes(self):
        s, ag = pair()
        for n in (0, 1, 4095, 32768, 32769, 300000):
            blob = os.urandom(n)
            r = s.push(blob, "/f%d" % n)
            self.assertEqual(r.get("sha256"), hashlib.sha256(blob).hexdigest())
            self.assertEqual(ag.fs["/f%d" % n], blob)
            r, body = s.pull("/f%d" % n)
            self.assertEqual(body, blob)

    def test_small_window_and_chunk(self):
        s, ag = pair(window=4096, maxchunk=1000)
        blob = os.urandom(50000)
        s.login()
        s.push(blob, "/w")
        self.assertEqual(s.pull("/w")[1], blob)
        self.assertEqual(s.maxchunk, 1000)

    def test_push_refuses_overwrite_without_flag(self):
        s, ag = pair()
        with self.assertRaises(proto.AgentError) as c:
            s.push(b"x", "/etc/motd", overwrite=False)
        self.assertEqual(c.exception.code, "EACCES")

    def test_pull_missing(self):
        s, _ = pair()
        with self.assertRaises(proto.AgentError) as c:
            s.pull("/missing")
        self.assertEqual((c.exception.code, c.exception.errno), ("ENOENT", 2))

    def test_push_with_dropped_frames_rewinds(self):
        s, ag = pair(drop_prob=0.15, window=8192, maxchunk=2048)
        blob = os.urandom(60000)
        s.push(blob, "/lossy", timeout=60)
        self.assertEqual(ag.fs["/lossy"], blob)

    def test_pull_with_dropped_frames(self):
        s, ag = pair(window=8192, maxchunk=2048)
        ag.fs["/big"] = os.urandom(60000)
        ag.drop_prob = 0.15
        r, body = s.pull("/big", timeout=60)
        self.assertEqual(body, ag.fs["/big"])

    def test_pull_with_corrupt_frames(self):
        s, ag = pair(window=8192, maxchunk=2048)
        ag.fs["/big"] = os.urandom(40000)
        ag.corrupt_every = 5
        r, body = s.pull("/big", timeout=60)
        self.assertEqual(body, ag.fs["/big"])
        self.assertGreater(s.dec.bad_crc, 0)


class Robustness(unittest.TestCase):
    def test_noise_and_slow_uart(self):
        s, _ = pair(noise_every=2, chunk=7)
        for i in range(8):
            r, out, _ = s.exec(cmd="echo n%d" % i)
            self.assertEqual(out, ("n%d\n" % i).encode())
        self.assertGreater(s.dec.garbage, 0)

    def test_lost_response_is_retried(self):
        s, ag = pair()
        ag.drop_every = 2                      # every second reply frame is lost
        for _ in range(6):
            s.request("info", timeout=10)
        self.assertGreater(s.stats["retries"], 0)
        self.assertEqual(sum(1 for c, _ in ag.log if c == "info"), 6)   # cached answer, no double execution

    def test_lost_request_is_retried(self):
        a, b = socket.socketpair()
        s = Session(SocketTransport(a).start(), token=TOKEN, retry_s=0.2)
        ag = MockAgent()
        tr = SocketTransport(b).start()
        # swallow the first REQ frame, then let the agent see everything
        first = F.Decoder().feed(b"")
        got = []
        ag.serve_bg(tr)

        def drop_first():
            pass
        # simplest: wrap transport write to drop the first frame
        orig = s.t.write
        n = {"i": 0}

        def w(d):
            n["i"] += 1
            if n["i"] > 1:
                orig(d)
        s.t.write = w
        s.login()
        self.assertGreaterEqual(s.stats["retries"], 1)

    def test_timeout_when_agent_silent(self):
        a, b = socket.socketpair()
        s = Session(SocketTransport(a).start(), retry_s=0.1, retries=2)
        with self.assertRaises(Timeout):
            s.request("hello", timeout=0.5)
        with self.assertRaises(Timeout):
            s.ping(timeout=0.2)
        b.close()

    def test_stale_ids_ignored(self):
        s, _ = pair()
        s.send(F.Frame(F.PONG, 999, b"stale"))
        r, out, _ = s.exec(cmd="echo x")
        self.assertEqual(out, b"x\n")


class Transports(unittest.TestCase):
    def test_unix_and_tcp(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "o.sock")
            srv = socket.socket(socket.AF_UNIX)
            srv.bind(p)
            srv.listen(1)
            ag = MockAgent()
            th = threading.Thread(target=lambda: ag.serve_bg(SocketTransport(srv.accept()[0]).start()), daemon=True)
            th.start()
            s = Session(open_transport("unix:" + p), token=TOKEN)
            self.assertEqual(s.login().get("agent"), "odbd")
            s.close()
            srv.close()
        srv = socket.socket()
        srv.bind(("127.0.0.1", 0))
        srv.listen(1)
        port = srv.getsockname()[1]
        threading.Thread(target=lambda: ag.serve_bg(SocketTransport(srv.accept()[0]).start()), daemon=True).start()
        s = Session(open_transport("tcp:127.0.0.1:%d" % port), token=TOKEN)
        s.login()
        self.assertIn("uptime_ms", s.request("info").as_dict())
        s.close()
        srv.close()

    @unittest.skipIf(sys.platform == "win32", "pty is posix-only")
    def test_pty(self):
        import pty
        import tty
        from odb.transport import TtyTransport
        master, slave = pty.openpty()
        tty.setraw(slave)
        ag = MockAgent()
        ag.serve_bg(TtyTransport(master).start())
        s = Session(open_transport("tty:" + os.ttyname(slave)), token=TOKEN)
        s.login()
        blob = os.urandom(40000)
        s.push(blob, "/p")
        self.assertEqual(ag.fs["/p"], blob)
        s.close()

    def test_connect_retry_fails_cleanly(self):
        with self.assertRaises(TransportError):
            open_transport("unix:/nonexistent/odb.sock", wait=0.3)
        with self.assertRaises(TransportError):
            open_transport("bogus:thing")


class CliEndToEnd(unittest.TestCase):
    """The real CLI as a subprocess against the mock agent on a unix socket."""

    @classmethod
    def setUpClass(cls):
        cls.d = tempfile.mkdtemp()
        cls.sock = os.path.join(cls.d, "odb.sock")
        cls.tokf = os.path.join(cls.d, "tok")
        open(cls.tokf, "w").write(TOKEN + "\n")
        cls.srv = subprocess.Popen([sys.executable, "-I", os.path.join(HERE, "odb", "mock.py"), "--unix", cls.sock],
                                   stdout=subprocess.PIPE)
        cls.srv.stdout.readline()

    @classmethod
    def tearDownClass(cls):
        cls.srv.terminate()
        cls.srv.wait()
        cls.srv.stdout.close()
        import shutil
        shutil.rmtree(cls.d, ignore_errors=True)

    def run_odbc(self, *a, expect=0, port=None, token=True, stdin=None):
        cmd = [sys.executable, "-I", os.path.join(HERE, "odbc.py"), "--port", port or ("unix:" + self.sock), "-t", "8"]
        if token:
            cmd += ["--token-file", self.tokf]
        p = subprocess.run(cmd + list(a), capture_output=True, timeout=60, input=stdin)
        self.assertEqual(p.returncode, expect, p.stderr.decode())
        return p

    def test_commands(self):
        self.assertIn(b"screen=1024x768", self.run_odbc("info").stdout)
        self.assertEqual(self.run_odbc("exec", "echo", "hello").stdout, b"hello\n")
        self.run_odbc("exec", "false", expect=1)
        self.assertEqual(self.run_odbc("exec", "--stdin", "-", "cat", stdin=b"piped").stdout, b"piped")
        self.assertIn(b"taskbar", self.run_odbc("ps").stdout)
        self.assertIn(b"odbd up", self.run_odbc("logs").stdout)
        self.run_odbc("input", "text", "hello")
        self.run_odbc("input", "key", "Enter", "--mods", "ctrl")
        self.run_odbc("input", "mouse", "5", "6", "--button", "left", "--action", "click")
        self.run_odbc("kill", "7")
        self.run_odbc("kill", "7", expect=4)
        self.run_odbc("reboot")
        self.run_odbc("ping", "-c", "3")
        self.assertIn(b"c1", self.run_odbc("crash", "list").stdout)
        self.run_odbc("wait", "5")

    def test_push_pull_shot_crash(self):
        src, dst = os.path.join(self.d, "a.bin"), os.path.join(self.d, "b.bin")
        open(src, "wb").write(os.urandom(150000))
        self.run_odbc("push", src, "/x/a.bin")
        self.run_odbc("pull", "/x/a.bin", dst)
        self.assertEqual(open(src, "rb").read(), open(dst, "rb").read())
        png = os.path.join(self.d, "s.png")
        self.run_odbc("shot", png)
        self.assertEqual(open(png, "rb").read(8), b"\x89PNG\r\n\x1a\n")
        cd = os.path.join(self.d, "c.bin")
        self.run_odbc("crash", "get", "c1", cd)
        self.assertIn(b"panic", open(cd, "rb").read())

    def test_wrong_token_and_no_token(self):
        p = subprocess.run([sys.executable, "-I", os.path.join(HERE, "odbc.py"), "--port", "unix:" + self.sock,
                            "--token", "not-the-right-token", "info"], capture_output=True, timeout=60)
        self.assertEqual(p.returncode, 4)
        self.assertIn(b"EAUTH", p.stderr)
        self.run_odbc("info", token=False, expect=4)

    def test_devices(self):
        out = self.run_odbc("devices", port="unix:%s;unix:/nonexistent.sock" % self.sock, token=False).stdout.decode()
        self.assertIn("online", out)
        self.assertIn("offline", out)

    def test_no_port_fails(self):
        p = subprocess.run([sys.executable, "-I", os.path.join(HERE, "odbc.py"), "info"], capture_output=True,
                           env={k: v for k, v in os.environ.items() if k != "ODB_PORT"})
        self.assertNotEqual(p.returncode, 0)


if __name__ == "__main__":
    unittest.main()
