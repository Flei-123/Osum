# SPDX-License-Identifier: GPL-2.0-only
"""odbc serve: one upstream open, many short-lived odbc clients (VBox uart2 pipe is single-client)."""
import os
import socket
import subprocess
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from odb.client import Session  # noqa: E402
from odb.mock import MockAgent  # noqa: E402
from odb.proxy import Proxy, make_listener  # noqa: E402
from odb.transport import SocketTransport, open_transport  # noqa: E402

TOKEN = "0123456789abcdef-mock"


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    p = s.getsockname()[1]
    s.close()
    return p


class ProxyInProcess(unittest.TestCase):
    def setUp(self):
        a, b = socket.socketpair()
        self.agent = MockAgent(token=TOKEN, resend_s=0.3)
        self.agent.serve_bg(SocketTransport(b).start())
        ls = make_listener("tcp:127.0.0.1:0")
        self.port = ls.getsockname()[1]
        self.px = Proxy(SocketTransport(a).start(), ls).start()

    def tearDown(self):
        self.px.close()

    def sess(self):
        return Session(open_transport("tcp:127.0.0.1:%d" % self.port, 3), token=TOKEN, retry_s=0.3, ack_timeout=0.3)

    def test_many_sequential_clients(self):
        for _ in range(4):
            s = self.sess()
            s.login()
            self.assertEqual(s.request("info").geti("cpus"), 2)
            s.close()
        self.assertEqual(self.px.clients_served, 4)

    def test_client_dropped_mid_session_then_next_works(self):
        s = self.sess()
        s.login()
        s.close()                      # leaves without a goodbye
        s = self.sess()
        s.login()
        s.ping()
        s.close()

    def test_new_client_replaces_stale_one(self):
        stale = socket.create_connection(("127.0.0.1", self.port), 3)
        time.sleep(0.2)
        s = self.sess()
        s.login()
        s.ping()
        s.close()
        stale.close()

    def test_wrong_token_through_proxy(self):
        from odb import proto
        s = Session(open_transport("tcp:127.0.0.1:%d" % self.port, 3), token="x" * 20, retry_s=0.3, ack_timeout=0.3)
        with self.assertRaises(proto.AgentError):
            s.login()
        s.close()
        s = self.sess()
        s.login()                      # right token still works afterwards
        s.close()


class ProxyCli(unittest.TestCase):
    def test_serve_subprocess(self):
        with tempfile.TemporaryDirectory() as d:
            sock = os.path.join(d, "up.sock")
            tok = os.path.join(d, "tok")
            with open(tok, "w") as f:
                f.write(TOKEN)
            mock = subprocess.Popen([sys.executable, "-I", os.path.join(HERE, "odb", "mock.py"), "--unix", sock,
                                     "--token-file", tok], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            port = free_port()
            serve = None
            try:
                for _ in range(50):
                    if os.path.exists(sock):
                        break
                    time.sleep(0.1)
                serve = subprocess.Popen([sys.executable, "-I", os.path.join(HERE, "odbc.py"), "--port", "unix:" + sock,
                                          "serve", "--listen", "tcp:127.0.0.1:%d" % port],
                                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                for rnd in range(3):   # three separate odbc processes, one upstream connection
                    r = subprocess.run([sys.executable, "-I", os.path.join(HERE, "odbc.py"), "--port",
                                        "tcp:127.0.0.1:%d" % port, "--wait", "10", "--token-file", tok, "info"],
                                       capture_output=True, text=True, timeout=30)
                    self.assertEqual(r.returncode, 0, r.stderr)
                    self.assertIn("cpus=2", r.stdout)
            finally:
                for p in (serve, mock):
                    if p:
                        p.terminate()
                        p.wait(5)

    def test_serve_without_port_is_clean(self):
        r = subprocess.run([sys.executable, "-I", os.path.join(HERE, "odbc.py"), "serve"], capture_output=True,
                           text=True, timeout=20, env={"PATH": os.environ.get("PATH", "")})
        self.assertNotEqual(r.returncode, 0)
        self.assertNotIn("Traceback", r.stderr)


if __name__ == "__main__":
    unittest.main()
