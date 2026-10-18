# SPDX-License-Identifier: GPL-2.0-only
"""odbc command line. Port: --port / $ODB_PORT (see transport.py for spec strings)."""
import argparse
import glob
import os
import sys
import time
import zlib

from . import __version__
from . import proto
from .client import Session, Timeout, Closed
from .transport import TransportError

KEYS = "enter esc tab bs space up down left right del home end f1 f2 f3 f4 f5 f6 f7 f8 f9 f10 f11 f12".split()


def out_bytes(b):
    sys.stdout.buffer.write(b)
    sys.stdout.buffer.flush()


def open_session(ns):
    spec = ns.port or os.environ.get("ODB_PORT")
    if not spec:
        sys.exit("odbc: no port (use --port or $ODB_PORT), e.g. --port unix:/tmp/odb.sock")
    s = Session.open(spec, wait=ns.wait, token=ns.token or os.environ.get("ODB_TOKEN"))
    if not ns.no_hello:
        s.hello(timeout=ns.timeout)
    return s


def cmd_devices(ns):
    cands = []
    if ns.port or os.environ.get("ODB_PORT"):
        cands += (ns.port or os.environ["ODB_PORT"]).split(";")
    cands += ["unix:" + p for p in glob.glob("/tmp/odb*.sock") + glob.glob("/run/odb/*.sock")
              + glob.glob("/root/abbilder/*/odb.sock")]
    if sys.platform == "win32":
        try:
            cands += ["pipe:\\\\.\\pipe\\" + n for n in os.listdir("\\\\.\\pipe\\") if n.lower().startswith("odb")]
        except OSError:
            pass
    seen = set()
    found = 0
    for c in cands:
        if c in seen:
            continue
        seen.add(c)
        try:
            s = Session.open(c, token=ns.token or os.environ.get("ODB_TOKEN"))
            try:
                rtt = s.ping(timeout=1.5)
                h = s.hello(timeout=1.5)
                print("%s\tonline\trtt=%.1fms\t%s" % (c, rtt * 1000, h.get("os", "?")))
                found += 1
            finally:
                s.close()
        except (TransportError, Timeout, Closed, proto.AgentError, OSError) as e:
            print("%s\toffline\t%s" % (c, e))
    return 0 if found else 1


def cmd_exec(ns):
    cmd = " ".join(ns.command)
    s = open_session(ns)
    code = [0]

    def on(b, fl):
        (sys.stderr if fl & proto.FLAG_STDERR else sys.stdout).buffer.write(b)
        (sys.stderr if fl & proto.FLAG_STDERR else sys.stdout).buffer.flush()
    r, _ = s.call("exec", {"cmd": cmd, "cwd": ns.cwd}, on_data=on, timeout=ns.timeout)
    return int(r.get("code", "0"))


def cmd_shell(ns):
    if ns.command:
        return cmd_exec(ns)
    s = open_session(ns)
    print("odb shell (Ctrl-D to leave)", file=sys.stderr)
    while True:
        try:
            line = input("odb> ")
        except EOFError:
            return 0
        if not line.strip():
            continue

        def on(b, fl):
            out_bytes(b)
        r, _ = s.call("exec", {"cmd": line}, on_data=on, timeout=ns.timeout)


def cmd_push(ns):
    data = open(ns.local, "rb").read()
    s = open_session(ns)
    t0 = time.time()
    r, _ = s.call("push", {"path": ns.remote, "mode": ns.mode}, data=data, chunk=ns.chunk, timeout=ns.timeout)
    dt = max(time.time() - t0, 1e-9)
    want = zlib.crc32(data) & 0xFFFFFFFF
    got = r.get("crc32")
    if got is not None and int(got) != want:
        print("odbc: push crc mismatch (local %08x, agent %s)" % (want, got), file=sys.stderr)
        return 3
    print("pushed %d bytes in %.2fs (%.1f KiB/s)" % (len(data), dt, len(data) / 1024 / dt))
    return 0


def cmd_pull(ns):
    s = open_session(ns)
    t0 = time.time()
    r, body = s.call("pull", {"path": ns.remote}, timeout=ns.timeout)
    dt = max(time.time() - t0, 1e-9)
    if "crc32" in r and int(r["crc32"]) != zlib.crc32(body) & 0xFFFFFFFF:
        print("odbc: pull crc mismatch", file=sys.stderr)
        return 3
    if "size" in r and int(r["size"]) != len(body):
        print("odbc: pull size mismatch", file=sys.stderr)
        return 3
    with open(ns.local, "wb") as f:
        f.write(body)
    print("pulled %d bytes in %.2fs (%.1f KiB/s)" % (len(body), dt, len(body) / 1024 / dt))
    return 0


def cmd_shot(ns):
    s = open_session(ns)
    r, body = s.call("shot", {"fmt": ns.fmt}, timeout=ns.timeout)
    with open(ns.out, "wb") as f:
        f.write(body)
    print("shot %s %sx%s %d bytes -> %s" % (r.get("fmt", "?"), r.get("w", "?"), r.get("h", "?"), len(body), ns.out))
    return 0


def cmd_input(ns):
    s = open_session(ns)
    sub = ns.kind
    a = {"kind": sub}
    if sub == "type":
        a["text"] = " ".join(ns.args)
    elif sub == "key":
        a["keys"] = "+".join(ns.args)
    elif sub == "mouse":
        a["spec"] = " ".join(ns.args)
    else:
        a["spec"] = " ".join(ns.args)
    s.call("input", a, timeout=ns.timeout)
    print("ok")
    return 0


def _stream(ns, op, args):
    s = open_session(ns)
    r, _ = s.call(op, args, on_data=lambda b, f: out_bytes(b), timeout=ns.timeout)
    return r


def cmd_ps(ns):
    _stream(ns, "ps", {})
    return 0


def cmd_kill(ns):
    s = open_session(ns)
    s.call("kill", {"pid": ns.pid, "sig": ns.sig}, timeout=ns.timeout)
    print("ok")
    return 0


def cmd_logs(ns):
    _stream(ns, "logs", {"n": ns.n, "follow": 1 if ns.follow else None})
    return 0


def cmd_info(ns):
    s = open_session(ns)
    r, _ = s.call("info", {}, timeout=ns.timeout)
    for k, v in r.items():
        print("%s=%s" % (k, v))
    return 0


def cmd_crash(ns):
    _stream(ns, "crash", {"inject": 1 if ns.inject else None})
    return 0


def cmd_reboot(ns):
    s = open_session(ns)
    s.call("reboot", {"mode": "poweroff" if ns.off else "reboot"}, timeout=ns.timeout)
    print("ok")
    return 0


def cmd_ping(ns):
    s = Session.open(ns.port or os.environ.get("ODB_PORT"), wait=ns.wait)
    rtts = []
    for _ in range(ns.count):
        rtts.append(s.ping(timeout=ns.timeout))
    print("ping x%d: min %.2f avg %.2f max %.2f ms" % (len(rtts), min(rtts) * 1e3, sum(rtts) / len(rtts) * 1e3, max(rtts) * 1e3))
    return 0


def build_parser():
    p = argparse.ArgumentParser(prog="odbc", description="OrientOS debug agent client")
    p.add_argument("--port", "-p", help="transport spec (pipe:..., tcp:h:p, unix:path, tty:/dev/pts/N, com:COM3)")
    p.add_argument("--token", help="auth token ($ODB_TOKEN)")
    p.add_argument("--timeout", "-t", type=float, default=15.0, help="inactivity timeout per request (s)")
    p.add_argument("--wait", type=float, default=0.0, help="retry connecting for N seconds")
    p.add_argument("--no-hello", action="store_true")
    p.add_argument("--version", action="version", version="odbc " + __version__)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("devices").set_defaults(fn=cmd_devices)
    for name in ("exec", "shell"):
        sp = sub.add_parser(name)
        sp.add_argument("--cwd")
        sp.add_argument("command", nargs="*")
        sp.set_defaults(fn=cmd_shell if name == "shell" else cmd_exec)
    sp = sub.add_parser("push")
    sp.add_argument("local")
    sp.add_argument("remote")
    sp.add_argument("--mode", default="644")
    sp.add_argument("--chunk", type=int, default=4096)
    sp.set_defaults(fn=cmd_push)
    sp = sub.add_parser("pull")
    sp.add_argument("remote")
    sp.add_argument("local")
    sp.set_defaults(fn=cmd_pull)
    sp = sub.add_parser("shot")
    sp.add_argument("out", nargs="?", default="shot.png")
    sp.add_argument("--fmt", default="png")
    sp.set_defaults(fn=cmd_shot)
    sp = sub.add_parser("input")
    sp.add_argument("kind", choices=["type", "key", "mouse"])
    sp.add_argument("args", nargs="+")
    sp.set_defaults(fn=cmd_input)
    sub.add_parser("ps").set_defaults(fn=cmd_ps)
    sp = sub.add_parser("kill")
    sp.add_argument("pid")
    sp.add_argument("--sig", default="9")
    sp.set_defaults(fn=cmd_kill)
    sp = sub.add_parser("logs")
    sp.add_argument("-n", default="200")
    sp.add_argument("-f", "--follow", action="store_true")
    sp.set_defaults(fn=cmd_logs)
    sub.add_parser("info").set_defaults(fn=cmd_info)
    sp = sub.add_parser("crash")
    sp.add_argument("--inject", action="store_true", help="make the agent panic (testing only)")
    sp.set_defaults(fn=cmd_crash)
    sp = sub.add_parser("reboot")
    sp.add_argument("--off", action="store_true")
    sp.set_defaults(fn=cmd_reboot)
    sp = sub.add_parser("ping")
    sp.add_argument("-c", "--count", type=int, default=5)
    sp.set_defaults(fn=cmd_ping)
    return p


def main(argv=None):
    ns = build_parser().parse_args(argv)
    try:
        return ns.fn(ns) or 0
    except proto.AgentError as e:
        print("odbc: %s" % e, file=sys.stderr)
        return 4
    except (Timeout, Closed, TransportError) as e:
        print("odbc: %s: %s" % (type(e).__name__, e), file=sys.stderr)
        return 5
    except KeyboardInterrupt:
        return 130
