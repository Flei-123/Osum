# SPDX-License-Identifier: GPL-2.0-only
"""Long-lived relay between one upstream byte stream and short-lived local clients.

A VirtualBox uart2 server pipe serves ONE client and stays busy after it left (ERROR_PIPE_BUSY until the VM restarts),
so every `odbc` process that opens the pipe itself works exactly once. `odbc serve` opens the pipe once and keeps it;
each odbc command then connects to the local TCP/unix listener instead (`--port tcp:127.0.0.1:4710`).

The relay is a dumb byte pipe: frames, auth and resync stay end to end. One client at a time; a new client replaces the
old one (a stale client must never block the next command). Upstream bytes with no client attached are dropped.
"""
import os
import socket
import threading
import time

from .transport import TransportError, open_transport

DEFAULT_LISTEN = "tcp:127.0.0.1:4710"


def make_listener(spec):
    """tcp:host:port | unix:path -> bound, listening socket."""
    if spec.startswith("unix:"):
        path = spec[5:]
        if os.path.exists(path):
            os.unlink(path)
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.bind(path)
    else:
        hp = spec[4:] if spec.startswith("tcp:") else spec
        host, _, port = hp.rpartition(":")
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind((host or "127.0.0.1", int(port)))
    s.listen(4)
    return s


class Proxy:
    def __init__(self, upstream, listener):
        self.up = upstream            # a started Transport
        self.ls = listener
        self.client = None
        self.lock = threading.Lock()
        self.stop = threading.Event()
        self.clients_served = 0
        self.up_bytes = 0             # upstream -> client bytes relayed
        self.dropped = 0              # upstream bytes with no client attached

    def start(self):
        threading.Thread(target=self._up_pump, daemon=True).start()
        threading.Thread(target=self._accept, daemon=True).start()
        return self

    def _set_client(self, c):
        with self.lock:
            old, self.client = self.client, c
        if old is not None:
            try:
                old.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            old.close()

    def _up_pump(self):
        while not self.stop.is_set():
            d = self.up.read(0.2)
            if d is None:
                self.stop.set()       # upstream gone: the VM went away
                break
            if not d:
                continue
            with self.lock:
                c = self.client
            if c is None:
                self.dropped += len(d)
                continue
            try:
                c.sendall(d)
                self.up_bytes += len(d)
            except OSError:
                with self.lock:
                    if self.client is c:
                        self.client = None

    def _accept(self):
        self.ls.settimeout(0.2)
        while not self.stop.is_set():
            try:
                c, _ = self.ls.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            c.settimeout(None)
            self._set_client(c)
            self.clients_served += 1
            threading.Thread(target=self._client_pump, args=(c,), daemon=True).start()

    def _client_pump(self, c):
        try:
            while not self.stop.is_set():
                d = c.recv(65536)
                if not d:
                    break
                self.up.write(d)
        except OSError:
            pass
        with self.lock:
            if self.client is c:
                self.client = None
        try:
            c.close()
        except OSError:
            pass

    def wait(self):
        while not self.stop.is_set():
            time.sleep(0.2)

    def close(self):
        self.stop.set()
        self._set_client(None)
        try:
            self.ls.close()
        except OSError:
            pass
        self.up.close()


def serve(upstream_spec, listen_spec=DEFAULT_LISTEN, wait=0.0, announce=print):
    """Open upstream once, listen locally, relay until upstream closes or Ctrl-C. Returns an exit code."""
    try:
        up = open_transport(upstream_spec, wait)
    except TransportError as e:
        announce("odbc serve: %s" % e)
        return 5
    try:
        ls = make_listener(listen_spec)
    except OSError as e:
        announce("odbc serve: cannot listen on %s: %s" % (listen_spec, e))
        up.close()
        return 2
    px = Proxy(up, ls).start()
    announce("odbc serve: %s <-> %s (use --port %s)" % (upstream_spec, listen_spec,
                                                         listen_spec if listen_spec.startswith(("tcp:", "unix:")) else "tcp:" + listen_spec))
    try:
        px.wait()
    except KeyboardInterrupt:
        pass
    px.close()
    return 0
