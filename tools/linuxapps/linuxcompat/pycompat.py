import ctypes
import ctypes.util
import fcntl
import hashlib
import http.server
import json
import mmap
import os
import queue
import resource
import select
import signal
import socket
import sqlite3
import ssl
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
import zipfile

LOOPBACK = "127.0.0.1"
TICK_SECONDS = 0.02
WAIT_SECONDS = 10
MAP_BYTES = 1 << 16
ROW_COUNT = 500
WORKER_COUNT = 4
ITEM_COUNT = 100


def ctypes_libc():
    libc = ctypes.CDLL(ctypes.util.find_library("c") or "libc.so")
    return "pid=%s" % (libc.getpid() == os.getpid())


def ssl_context():
    context = ssl.create_default_context()
    return "tls=%s" % (context.minimum_version is not None)


def sqlite_file():
    with tempfile.TemporaryDirectory() as directory:
        connection = sqlite3.connect(os.path.join(directory, "t.db"))
        connection.execute("pragma journal_mode=wal")
        connection.execute("create table t(a integer primary key, b text)")
        connection.executemany("insert into t(b) values (?)", [("x%d" % i,) for i in range(ROW_COUNT)])
        connection.commit()
        count = connection.execute("select count(*) from t").fetchone()[0]
        connection.close()
        return "rows=%d" % count


def mmap_file():
    with tempfile.TemporaryFile() as handle:
        handle.write(b"\0" * MAP_BYTES)
        handle.flush()
        mapping = mmap.mmap(handle.fileno(), MAP_BYTES)
        mapping[:6] = b"mapped"
        mapping.flush()
        mapping.close()
        handle.seek(0)
        return handle.read(6).decode()


def flock_pair():
    with tempfile.NamedTemporaryFile() as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        other = open(handle.name)
        try:
            fcntl.flock(other, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return "unexpected"
        except BlockingIOError:
            return "locked"
        finally:
            other.close()


def fork_pipe():
    read_end, write_end = os.pipe()
    pid = os.fork()
    if pid == 0:
        os.close(read_end)
        os.write(write_end, b"child")
        os._exit(0)
    os.close(write_end)
    data = os.read(read_end, 16)
    os.waitpid(pid, 0)
    return data.decode()


def epoll_pair():
    left, right = socket.socketpair()
    poller = select.epoll()
    poller.register(right.fileno(), select.EPOLLIN)
    left.send(b"x")
    events = poller.poll(WAIT_SECONDS)
    return "events=%d" % len(events)


def itimer():
    fired = []
    signal.signal(signal.SIGALRM, lambda number, frame: fired.append(number))
    signal.setitimer(signal.ITIMER_REAL, TICK_SECONDS)
    deadline = time.time() + WAIT_SECONDS
    while not fired and time.time() < deadline:
        time.sleep(TICK_SECONDS)
    return "fired=%d" % len(fired)


def rlimits():
    soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
    return "nofile=%s" % (soft > 0)


class PingHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = b"pong"
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def http_loopback():
    server = http.server.ThreadingHTTPServer((LOOPBACK, 0), PingHandler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    url = "http://%s:%d/" % (LOOPBACK, server.server_address[1])
    body = urllib.request.urlopen(url, timeout=WAIT_SECONDS).read()
    server.shutdown()
    return body.decode()


def zip_roundtrip():
    with tempfile.TemporaryDirectory() as directory:
        path = os.path.join(directory, "a.zip")
        with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
            archive.writestr("a.txt", "zipped" * 100)
        with zipfile.ZipFile(path) as archive:
            return archive.read("a.txt")[:6].decode()


def subprocess_pipe():
    command = ["/bin/sh", "-c", "echo child-$((6*7))"]
    result = subprocess.run(command, capture_output=True, text=True, timeout=WAIT_SECONDS)
    return result.stdout.strip()


def threads_queue():
    work = queue.Queue()
    results = queue.Queue()

    def worker():
        while True:
            item = work.get()
            if item is None:
                return
            results.put(item * 2)

    pool = [threading.Thread(target=worker) for _ in range(WORKER_COUNT)]
    for thread in pool:
        thread.start()
    for number in range(ITEM_COUNT):
        work.put(number)
    for _ in pool:
        work.put(None)
    for thread in pool:
        thread.join()
    return "sum=%d" % sum(results.get() for _ in range(ITEM_COUNT))


def hashing():
    return hashlib.sha256(b"abc").hexdigest()[:8]


def json_roundtrip():
    data = {"a": list(range(1000)), "b": {"c": "d"}}
    return "same=%s" % (json.loads(json.dumps(data)) == data)


def venv_create():
    with tempfile.TemporaryDirectory() as directory:
        target = os.path.join(directory, "v")
        subprocess.run([sys.executable, "-m", "venv", "--without-pip", target], check=True, timeout=60)
        return "venv=%s" % os.path.exists(os.path.join(target, "bin", "python"))


CASES = {
    "ctypes": ctypes_libc,
    "ssl": ssl_context,
    "sqlite": sqlite_file,
    "mmap": mmap_file,
    "flock": flock_pair,
    "forkpipe": fork_pipe,
    "epoll": epoll_pair,
    "itimer": itimer,
    "rlimit": rlimits,
    "http": http_loopback,
    "zip": zip_roundtrip,
    "subprocess": subprocess_pipe,
    "threads": threads_queue,
    "hash": hashing,
    "json": json_roundtrip,
    "venv": venv_create,
}

name = sys.argv[1] if len(sys.argv) > 1 else ""
if name not in CASES:
    print("FAIL unknown case")
    sys.exit(2)
print("OK", CASES[name]())
