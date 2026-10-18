# SPDX-License-Identifier: GPL-2.0-only
"""Byte-stream transports for odbc. Every transport has a reader thread that
pushes chunks into a queue, so read(timeout) works the same on Windows named
pipes, sockets and ttys.

Spec strings (--port / ODB_PORT):
  pipe:\\\\.\\pipe\\name   Windows named pipe (VirtualBox uart ... --uart-mode client|server)
  tcp:host:port          TCP socket (qemu -serial tcp:..., later odbd over the network)
  unix:/path/sock        Unix socket (qemu -chardev socket,path=..)
  tty:/dev/pts/N | com:COM3[,115200]   pty / serial port
  file:/path             regular file/fifo (read+write)
"""
import os
import queue
import socket
import sys
import threading
import time


WAKE_ENABLE = os.environ.get("ODB_WAKE", "1") != "0"
WAKE_IDLE_S = 8.0   # > any in-transfer wait (rewind timer 2 s); the agent sleeps after 3 s of silence
WAKE_BYTES = 160
WAKE_PAUSE_S = 0.05


class TransportError(OSError):
    pass


class Transport:
    def __init__(self):
        self.q = queue.Queue()
        self.closed = False
        self.eof = False
        self._t = None
        self.rx_bytes = 0
        self.tx_bytes = 0
        self.last_act = 0.0   # monotonic time of the last byte in either direction (0 = never)

    # subclasses: _read_blocking() -> bytes (b'' = EOF), _write(data), _close()
    def start(self):
        self._t = threading.Thread(target=self._pump, daemon=True)
        self._t.start()
        return self

    def _pump(self):
        try:
            while not self.closed:
                d = self._read_blocking()
                if not d:
                    break
                self.q.put(d)
        except Exception:
            pass
        self.eof = True
        self.q.put(None)

    def read(self, timeout=0.1):
        """Return bytes, b'' on timeout, None on EOF."""
        try:
            d = self.q.get(timeout=timeout)
        except queue.Empty:
            return b""
        if d is None:
            self.q.put(None)
            return None
        self.rx_bytes += len(d)
        self.last_act = time.monotonic()
        return d

    def write(self, data):
        # Wake preamble (docs/ODB.md "idle agent"): after WAKE_IDLE_S of silence the agent may poll slowly (sleeping
        # between polls to stay off the CPU) and a 16-byte UART FIFO would lose the head of a frame. Zero octets are
        # garbage to the frame resync; the pause lets the agent wake before the real frame starts.
        now = time.monotonic()
        if WAKE_ENABLE and now - self.last_act > WAKE_IDLE_S:
            self._write(b"\x00" * WAKE_BYTES)
            time.sleep(WAKE_PAUSE_S)
        self.last_act = time.monotonic()
        self.tx_bytes += len(data)
        self._write(data)

    def drain(self):
        n = 0
        while True:
            try:
                d = self.q.get_nowait()
            except queue.Empty:
                return n
            if d is None:
                self.q.put(None)
                return n
            n += len(d)

    def close(self):
        self.closed = True
        try:
            self._close()
        except Exception:
            pass


class SocketTransport(Transport):
    def __init__(self, sock):
        super().__init__()
        self.s = sock

    def _read_blocking(self):
        return self.s.recv(65536)

    def _write(self, data):
        self.s.sendall(data)

    def _close(self):
        try:
            self.s.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        self.s.close()


class FdTransport(Transport):
    """Unbuffered file object (named pipe, tty, fifo)."""

    def __init__(self, f):
        super().__init__()
        self.f = f

    def _read_blocking(self):
        r = getattr(self.f, "read1", None)
        if r:
            return r(65536)
        return self.f.read(1)

    def _write(self, data):
        self.f.write(data)
        try:
            self.f.flush()
        except Exception:
            pass

    def _close(self):
        self.f.close()


class TtyTransport(Transport):
    def __init__(self, fd):
        super().__init__()
        self.fd = fd

    def _read_blocking(self):
        return os.read(self.fd, 65536)

    def _write(self, data):
        mv = memoryview(data)
        while mv:
            n = os.write(self.fd, mv)
            mv = mv[n:]

    def _close(self):
        os.close(self.fd)


def _retry(fn, wait, what):
    end = time.time() + wait
    last = None
    while True:
        try:
            return fn()
        except OSError as e:
            last = e
            if time.time() >= end:
                raise TransportError("%s: %s" % (what, last))
            time.sleep(0.2)


class WinHandleTransport(Transport):
    """Windows named pipe / COM port. A synchronous handle serialises I/O, so a
    blocked ReadFile would block our writes: poll instead (PeekNamedPipe for
    pipes, zero read timeouts for COM) and sleep 2 ms when idle."""

    def __init__(self, f, kind):
        super().__init__()
        import ctypes
        import msvcrt
        self.f = f
        self.kind = kind
        self._wq = None
        self.k32 = ctypes.windll.kernel32
        self.h = msvcrt.get_osfhandle(f.fileno())
        self.ct = ctypes
        if kind == "com":
            class TO(ctypes.Structure):
                _fields_ = [(n, ctypes.c_ulong) for n in
                            ("ri", "rm", "rc", "wm", "wc")]
            to = TO(0xFFFFFFFF, 0, 0, 0, 0)
            self.k32.SetCommTimeouts(self.h, ctypes.byref(to))

    def _read_blocking(self):
        ct = self.ct
        while not self.closed:
            if self.kind == "pipe":
                avail = ct.c_ulong(0)
                ok = self.k32.PeekNamedPipe(self.h, None, 0, None, ct.byref(avail), None)
                if not ok:
                    return b""            # broken pipe = peer gone
                n = avail.value
            else:
                n = 4096
            if n:
                buf = ct.create_string_buffer(min(n, 65536))
                got = ct.c_ulong(0)
                ok = self.k32.ReadFile(self.h, buf, len(buf), ct.byref(got), None)
                if not ok:
                    return b""
                if got.value:
                    return buf.raw[:got.value]
            time.sleep(0.002)
        return b""

    def _write(self, data):
        # A real VBox uart2 pipe stops accepting data while the guest side is not reading (agent not up, UART FIFO
        # full): WriteFile then blocks forever and no client timeout could fire. Hand the bytes to a writer thread
        # (daemon, may stay blocked at exit) so the session timeouts and Ctrl-C keep working.
        if self._wq is None:
            self._wq = queue.Queue()
            threading.Thread(target=self._writer, daemon=True).start()
        self._wq.put(bytes(data))

    def _writer(self):
        try:
            while not self.closed:
                d = self._wq.get()
                mv = memoryview(d)
                while mv and not self.closed:
                    n = self.f.write(mv)
                    mv = mv[n:] if n else mv
        except Exception:
            self.eof = True
            self.q.put(None)

    def _close(self):
        # do not close a handle another thread is blocked in WriteFile on: the process is about to exit anyway
        try:
            if self._wq is None or self._wq.empty():
                self.f.close()
        except Exception:
            pass


def open_pipe(path, wait=0.0):
    f = _retry(lambda: open(path, "r+b", buffering=0), wait, "pipe " + path)
    if sys.platform == "win32":
        return WinHandleTransport(f, "pipe").start()
    return FdTransport(f).start()


def open_tcp(hostport, wait=0.0):
    host, _, port = hostport.rpartition(":")
    s = _retry(lambda: socket.create_connection((host or "127.0.0.1", int(port)), timeout=3), wait, "tcp " + hostport)
    s.settimeout(None)
    return SocketTransport(s).start()


def open_unix(path, wait=0.0):
    def c():
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            s.connect(path)
        except OSError:
            s.close()
            raise
        return s
    return SocketTransport(_retry(c, wait, "unix " + path)).start()


def open_tty(spec, wait=0.0):
    path, _, baud = spec.partition(",")
    if sys.platform == "win32":
        # COMx: raw open works for virtual ports and USB serial at the preset baud
        p = path if path.startswith("\\\\.\\") else "\\\\.\\" + path
        f = _retry(lambda: open(p, "r+b", buffering=0), wait, "com " + path)
        return WinHandleTransport(f, "com").start()
    import termios
    fd = _retry(lambda: os.open(path, os.O_RDWR | os.O_NOCTTY), wait, "tty " + path)
    try:
        a = termios.tcgetattr(fd)
        a[0] = 0
        a[1] = 0
        a[2] = (a[2] & ~(termios.CSIZE | termios.PARENB | termios.CSTOPB)) | termios.CS8 | termios.CLOCAL | termios.CREAD
        a[3] = 0
        a[6][termios.VMIN] = 1
        a[6][termios.VTIME] = 0
        if baud:
            sp = getattr(termios, "B" + baud, None)
            if sp is not None:
                a[4] = a[5] = sp
        termios.tcsetattr(fd, termios.TCSANOW, a)
    except termios.error:
        pass  # pty or similar
    return TtyTransport(fd).start()


def open_file(path, wait=0.0):
    f = _retry(lambda: open(path, "r+b", buffering=0), wait, "file " + path)
    return FdTransport(f).start()


def open_transport(spec, wait=0.0):
    if spec.startswith("pipe:"):
        return open_pipe(spec[5:], wait)
    if spec.startswith("\\\\.\\pipe\\"):
        return open_pipe(spec, wait)
    if spec.startswith("tcp:"):
        return open_tcp(spec[4:], wait)
    if spec.startswith("unix:"):
        return open_unix(spec[5:], wait)
    if spec.startswith(("tty:", "com:")):
        return open_tty(spec.split(":", 1)[1], wait)
    if spec.startswith("file:"):
        return open_file(spec[5:], wait)
    if spec.upper().startswith("COM"):
        return open_tty(spec, wait)
    if os.path.exists(spec):
        return open_unix(spec, wait) if _is_sock(spec) else open_tty(spec, wait)
    raise TransportError("unknown transport spec: %r" % spec)


def _is_sock(p):
    import stat
    return stat.S_ISSOCK(os.stat(p).st_mode)
