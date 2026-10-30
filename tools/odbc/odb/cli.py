# SPDX-License-Identifier: GPL-2.0-only
"""odbc command line. Port: --port / $ODB_PORT (see transport.py for spec strings)."""
import argparse
import glob
import os
import shutil
import signal
import sys
import threading
import time

from . import __version__
from . import frame as F
from . import proto
from .client import Session, Timeout, Closed, read_token_file
from .transport import TransportError
from . import img as IMG


def out_bytes(b):
    sys.stdout.buffer.write(b)
    sys.stdout.buffer.flush()


def err_bytes(b):
    sys.stderr.buffer.write(b)
    sys.stderr.buffer.flush()


def get_token(ns):
    if ns.token:
        return ns.token
    tf = ns.token_file or os.environ.get("ODB_TOKEN_FILE")
    if tf:
        try:
            return read_token_file(tf)
        except OSError as e:
            sys.exit("odbc: cannot read token file %s: %s" % (tf, e.strerror or e))
    return os.environ.get("ODB_TOKEN")


def port_spec(ns):
    if getattr(ns, "net", None):
        return "udp:" + ns.net
    return ns.port or os.environ.get("ODB_PORT")


def open_session(ns, spec=None, login=True):
    spec = spec or port_spec(ns)
    if not spec:
        sys.exit("odbc: no port (use --port, --net or $ODB_PORT), e.g. --port unix:/tmp/odb.sock")
    s = Session.open(spec, wait=ns.wait, token=get_token(ns))
    if login:
        s.login(timeout=ns.hello_timeout)
    return s


def candidates(ns):
    c = []
    p = port_spec(ns)
    if p:
        c += p.split(";")
    c += ["unix:" + x for x in sorted(glob.glob("/tmp/odb*.sock") + glob.glob("/run/odb/*.sock")
                                      + glob.glob("/root/abbilder/*/odb.sock"))]
    if sys.platform == "win32":
        try:
            c += ["pipe:\\\\.\\pipe\\" + n for n in os.listdir("\\\\.\\pipe\\") if n.lower().startswith("odb")]
        except OSError:
            pass
    return list(dict.fromkeys(c))


def cmd_devices(ns):
    found = 0
    for c in candidates(ns):
        try:
            s = Session.open(c, token=get_token(ns))
            try:
                rtt = s.ping(timeout=1.5)
                h = s.hello(timeout=1.5)
                print("%s\tonline\trtt=%.1fms\t%s %s\tfeatures=%s" % (
                    c, rtt * 1000, h.get("os", "?"), h.get("kernel", ""), h.get("features", "")))
                found += 1
            finally:
                s.close()
        except (TransportError, Timeout, Closed, proto.AgentError, OSError) as e:
            print("%s\toffline\t%s" % (c, e))
    return 0 if found else 1


def cmd_exec(ns):
    s = open_session(ns)
    stdin = None
    if ns.stdin:
        stdin = sys.stdin.buffer.read() if ns.stdin == "-" else open(ns.stdin, "rb").read()
    cmd = " ".join(ns.command)
    r, _, _ = s.exec(cmd=None if ns.argv else cmd, argv=ns.command if ns.argv else None, cwd=ns.cwd,
                     env=ns.env, timeout_ms=ns.timeout_ms, stdin=stdin, on_out=out_bytes, on_err=err_bytes,
                     timeout=ns.timeout)
    sig = r.geti("signal", 0)
    return 128 + sig if sig else r.geti("exit", 0)


def cmd_shell(ns):
    if ns.command:
        return cmd_exec(ns)
    s = open_session(ns)
    interactive = sys.stdin.isatty() and os.name == "posix"
    old = None
    if interactive:
        import termios
        import tty
        old = termios.tcgetattr(0)
        tty.setraw(0)
        print("odb shell: Ctrl-] leaves\r", file=sys.stderr)
    stop = threading.Event()
    fidbox = {}

    def reader(fid):
        fidbox["fid"] = fid
        while not stop.is_set():
            b = os.read(0, 1024) if interactive else sys.stdin.buffer.read1(1024)
            if not b:
                s.end_stream(fid, proto.STDIN)
                return
            if b"\x1d" in b:
                s.cancel(fid)
                return
            s.send_stream(fid, proto.STDIN, b)

    def on_frame(f):
        if f.type == F.DATA:
            st, b = proto.dec_data(f.payload)
            if st == proto.STDOUT:
                out_bytes(b)

    def start(fid):
        threading.Thread(target=reader, args=(fid,), daemon=True).start()
    try:
        size = shutil.get_terminal_size((80, 24))
        if interactive and hasattr(signal, "SIGWINCH"):
            def winch(_sig, _frm):
                sz = shutil.get_terminal_size((80, 24))
                s.send_resize(sz.columns, sz.lines)
            signal.signal(signal.SIGWINCH, winch)
        r = s.request("shell", {"cols": size.columns, "rows": size.lines}, on_frame=on_frame, on_start=start, timeout=3600)
        return r.geti("exit", 0)
    except proto.AgentError as e:
        if e.code == "ECANCEL":
            return 0
        raise
    finally:
        stop.set()
        if old is not None:
            import termios
            termios.tcsetattr(0, termios.TCSADRAIN, old)


def cmd_push(ns):
    data = open(ns.local, "rb").read()
    s = open_session(ns)
    t0 = time.time()
    s.push(data, ns.remote, mode=ns.mode, timeout=ns.timeout)
    dt = max(time.time() - t0, 1e-9)
    print("pushed %d bytes in %.2fs (%.1f KiB/s, %d rewinds)" % (len(data), dt, len(data) / 1024 / dt, s.stats["rewinds"]))
    return 0


def cmd_pull(ns):
    s = open_session(ns)
    t0 = time.time()
    r, body = s.pull(ns.remote, timeout=ns.timeout)
    dt = max(time.time() - t0, 1e-9)
    with open(ns.local, "wb") as f:
        f.write(body)
    print("pulled %d bytes in %.2fs (%.1f KiB/s, %d rewinds)" % (len(body), dt, len(body) / 1024 / dt, s.stats["rewinds"]))
    return 0


def cmd_shot(ns):
    s = open_session(ns)
    t0 = time.time()
    r, body = s.collect_stream("shot", {"format": ns.format, "scale": ns.scale,
                                        "display": ns.display or None,
                                        "pattern": 1 if ns.pattern else None,
                                        "quant": ns.quant}, proto.SHOT, timeout=ns.timeout)
    want = r.geti("bytes")
    if want is not None and want != len(body):
        print("odbc: shot incomplete (%d of %d bytes)" % (len(body), want), file=sys.stderr)
        return 3
    with open(ns.out, "wb") as f:
        f.write(body)
    print("shot %s %sx%s %d bytes in %.2fs -> %s" % (r.get("format", "?"), r.get("w", "?"), r.get("h", "?"),
                                                    len(body), time.time() - t0, ns.out))
    return 0


def cmd_input(ns):
    s = open_session(ns)
    a = [("kind", ns.kind)]
    if ns.kind == "key":
        a += [("key", ns.args[0]), ("mods", ns.mods), ("action", ns.action)]
    elif ns.kind == "text":
        a += [("text", " ".join(ns.args)), ("delay_ms", ns.delay_ms), ("layout", getattr(ns, "layout", None))]
    elif ns.kind == "mouse":
        if ns.rel:
            a += [("dx", ns.args[0]), ("dy", ns.args[1])]
        elif len(ns.args) >= 2:
            a += [("x", ns.args[0]), ("y", ns.args[1])]
        a += [("button", ns.button), ("action", ns.action)]
    elif ns.kind == "scroll":
        a += [("dy", ns.args[0])]
    r = s.request("input", a, timeout=ns.timeout)
    print("ok n=%s" % r.get("n", "?"))
    return 0


def cmd_ps(ns):
    s = open_session(ns)
    _, body = s.collect_stream("ps", {"full": 1 if ns.full else None}, proto.STDOUT, timeout=ns.timeout)
    out_bytes(body)
    return 0


def cmd_stacks(ns):
    s = open_session(ns)
    _, body = s.collect_stream("stacks", {"pid": ns.pid}, proto.STDOUT, timeout=ns.timeout)
    out_bytes(body)
    return 0


def cmd_ls(ns):
    s = open_session(ns)
    _, body = s.collect_stream("ls", {"path": ns.path}, proto.STDOUT, timeout=ns.timeout)
    out_bytes(body)
    return 0


def cmd_cat(ns):
    s = open_session(ns)
    off = ns.offset
    while True:
        r, body = s.collect_stream("cat", {"path": ns.path, "offset": off, "len": 8192}, proto.FILE, timeout=ns.timeout)
        out_bytes(body)
        size = r.geti("size", 0)
        off += len(body)
        if not body or off >= size:
            return 0


def cmd_kill(ns):
    s = open_session(ns)
    s.request("kill", {"pid": ns.pid, "sig": ns.sig}, timeout=ns.timeout)
    print("ok")
    return 0


def cmd_logs(ns):
    s = open_session(ns)
    items = {"lines": ns.lines, "src": ns.src, "name": ns.name, "follow": 1 if ns.follow else None}
    try:
        s.collect_stream("logs", items, proto.LOG, sink=out_bytes, timeout=3600 if ns.follow else ns.timeout)
    except KeyboardInterrupt:
        pass
    except proto.AgentError as e:
        if e.code != "ECANCEL":
            raise
    return 0


def cmd_info(ns):
    s = open_session(ns)
    r = s.request("info", {"idle_ms": ns.idle_ms}, timeout=ns.timeout)
    for k, v in r.pairs:
        print("%s=%s" % (k, v.decode("utf-8", "replace")))
    return 0


def cmd_crash(ns):
    s = open_session(ns)
    if ns.op == "list":
        _, body = s.collect_stream("crashdump", {"op": "list"}, proto.STDOUT, timeout=ns.timeout)
        out_bytes(body)
    elif ns.op == "get":
        r, body = s.file_download("crashdump", {"op": "get", "id": ns.id}, timeout=ns.timeout)
        with open(ns.out or ("crash-%s.bin" % ns.id), "wb") as f:
            f.write(body)
        print("crash %s: %d bytes" % (ns.id, len(body)))
    else:
        s.request("crashdump", {"op": "clear", "id": ns.id}, timeout=ns.timeout)
        print("ok")
    return 0


def cmd_reboot(ns):
    s = open_session(ns)
    s.request("shutdown" if ns.off else "reboot", {"mode": "force" if ns.force else None,
                                                    "poweroff": 1 if ns.off else None}, timeout=ns.timeout)
    print("ok")
    return 0


def cmd_ping(ns):
    s = Session.open(port_spec(ns), wait=ns.wait)
    r = [s.ping(timeout=ns.timeout) for _ in range(ns.count)]
    print("ping x%d: min %.2f avg %.2f max %.2f ms" % (len(r), min(r) * 1e3, sum(r) / len(r) * 1e3, max(r) * 1e3))
    return 0


def cmd_wait(ns):
    """Wait until the agent answers hello (boot finished). Exit 0 on success, 1 on timeout."""
    spec = port_spec(ns)
    end = time.time() + ns.limit
    last = None
    while time.time() < end:
        try:
            s = Session.open(spec, token=get_token(ns))
            try:
                s.ping(timeout=1.0)
                h = s.login(timeout=2.0)
                print("agent up after %.1fs: %s %s" % (ns.limit - (end - time.time()), h.get("os"), h.get("kernel")))
                return 0
            finally:
                s.close()
        except (TransportError, Timeout, Closed, OSError) as e:
            last = e
            time.sleep(1.0)
    print("odbc: no agent within %ds (%s)" % (ns.limit, last), file=sys.stderr)
    return 1


def cmd_imgdiff(ns):
    """Host-only: compare two shot PNGs. Exit 0 = at most --max-frac of the pixels differ, 1 = more, 2 = unreadable."""
    try:
        a = IMG.decode_png(open(ns.a, "rb").read())
        b = IMG.decode_png(open(ns.b, "rb").read())
        region = tuple(int(v) for v in ns.region.split(",")) if ns.region else None
        d = IMG.diff(a, b, tol=ns.tol, region=region)
    except (OSError, ValueError) as e:
        print("odbc: imgdiff: %s" % e, file=sys.stderr)
        return 2
    print("changed=%d pixels=%d frac=%.5f bbox=%s" % (d["changed"], d["pixels"], d["frac"], d["bbox"]))
    return 0 if d["frac"] <= ns.max_frac else 1


def cmd_serve(ns):
    """Long-lived relay: keeps a one-client upstream (VBox uart2 pipe) open for many odbc commands."""
    from .proxy import serve
    spec = port_spec(ns)
    if not spec:
        sys.exit("odbc serve: needs --port <upstream>")
    return serve(spec, ns.listen, wait=ns.wait)


def build_parser():
    p = argparse.ArgumentParser(prog="odbc", description="Osum debug bridge client")
    p.add_argument("--port", "-p", help="pipe:\\\\.\\pipe\\odb | tcp:h:p | unix:path | tty:/dev/pts/N | com:COM3 ($ODB_PORT)")
    p.add_argument("--net", help="kernel ODB over LAN: <ip>[:port] (UDP, default port 6970)")
    p.add_argument("--token", help="auth token ($ODB_TOKEN)")
    p.add_argument("--token-file", help="file with the token ($ODB_TOKEN_FILE)")
    p.add_argument("--timeout", "-t", type=float, default=15.0, help="seconds without answer before giving up")
    p.add_argument("--hello-timeout", type=float, default=5.0)
    p.add_argument("--wait", type=float, default=0.0, help="retry opening the transport for N seconds")
    p.add_argument("--version", action="version", version="odbc " + __version__)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("devices", help="probe known endpoints").set_defaults(fn=cmd_devices)
    for name in ("exec", "shell"):
        sp = sub.add_parser(name)
        sp.add_argument("--cwd")
        sp.add_argument("--env", action="append")
        sp.add_argument("--timeout-ms", type=int)
        sp.add_argument("--stdin", help="file or - ")
        sp.add_argument("--argv", action="store_true", help="no shell: pass words as argv")
        sp.add_argument("command", nargs="*")
        sp.set_defaults(fn=cmd_shell if name == "shell" else cmd_exec)
    sp = sub.add_parser("push")
    sp.add_argument("local")
    sp.add_argument("remote")
    sp.add_argument("--mode", default="644")
    sp.set_defaults(fn=cmd_push)
    sp = sub.add_parser("pull")
    sp.add_argument("remote")
    sp.add_argument("local")
    sp.set_defaults(fn=cmd_pull)
    sp = sub.add_parser("shot")
    sp.add_argument("out", nargs="?", default="shot.png")
    sp.add_argument("--format", default="png", choices=["png", "ppm", "raw"])
    sp.add_argument("--scale", type=int, default=None, help="percent; omitted = agent default (50)")
    sp.add_argument("--display", type=int, default=0)
    sp.add_argument("--quant", type=int, default=None, help="drop N low bits (0-6) of each colour octet: lossy, much smaller PNG (default 0 = lossless)")
    sp.add_argument("--pattern", action="store_true", help="agent test image (no screen needed)")
    sp.set_defaults(fn=cmd_shot)
    sp = sub.add_parser("input")
    sp.add_argument("kind", choices=["key", "text", "mouse", "scroll"])
    sp.add_argument("args", nargs="+")
    sp.add_argument("--mods")
    sp.add_argument("--action")
    sp.add_argument("--button")
    sp.add_argument("--delay-ms", type=int)
    sp.add_argument("--layout", choices=["us", "de", "uk", "fr", "es", "it", "ru", "us-intl", "de-at", "ch-de", "pt", "pt-br", "pl", "tr", "nl", "ch-fr", "se", "auto"], help="text: keyboard layout (default = the guest's own)")
    sp.add_argument("--rel", action="store_true", help="mouse: args are dx dy")
    sp.set_defaults(fn=cmd_input)
    sp = sub.add_parser("ps")
    sp.add_argument("--full", action="store_true")
    sp.set_defaults(fn=cmd_ps)
    sp = sub.add_parser("stacks", help="kernel stacks per task (kernel ODB, --net)")
    sp.add_argument("pid", nargs="?", type=int, default=0)
    sp.set_defaults(fn=cmd_stacks)
    sp = sub.add_parser("ls", help="list a directory (kernel ODB, --net)")
    sp.add_argument("path", nargs="?", default="/var/log")
    sp.set_defaults(fn=cmd_ls)
    sp = sub.add_parser("cat", help="print a file (kernel ODB, --net)")
    sp.add_argument("path")
    sp.add_argument("--offset", type=int, default=0)
    sp.set_defaults(fn=cmd_cat)
    sp = sub.add_parser("kill")
    sp.add_argument("pid")
    sp.add_argument("--sig", default="TERM")
    sp.set_defaults(fn=cmd_kill)
    sp = sub.add_parser("logs")
    sp.add_argument("-n", "--lines", type=int, default=200)
    sp.add_argument("--src", choices=["kernel", "app", "all"])
    sp.add_argument("--name")
    sp.add_argument("-f", "--follow", action="store_true")
    sp.set_defaults(fn=cmd_logs)
    sp = sub.add_parser("info")
    sp.add_argument("--idle-ms", type=int, help="idle sample window")
    sp.set_defaults(fn=cmd_info)
    sp = sub.add_parser("crash", help="crash dumps: list | get <id> [out] | clear <id>")
    sp.add_argument("op", choices=["list", "get", "clear"], nargs="?", default="list")
    sp.add_argument("id", nargs="?")
    sp.add_argument("out", nargs="?")
    sp.set_defaults(fn=cmd_crash)
    sp = sub.add_parser("reboot", help="reboot (or --off: shutdown)")
    sp.add_argument("--off", action="store_true")
    sp.add_argument("--force", action="store_true")
    sp.set_defaults(fn=cmd_reboot)
    sp = sub.add_parser("ping")
    sp.add_argument("-c", "--count", type=int, default=5)
    sp.set_defaults(fn=cmd_ping)
    sp = sub.add_parser("serve", help="keep --port open and relay it to local clients (VBox single-client pipe)")
    sp.add_argument("--listen", default="tcp:127.0.0.1:4710", help="tcp:host:port | unix:path (default %(default)s)")
    sp.set_defaults(fn=cmd_serve)
    sp = sub.add_parser("imgdiff", help="host only: compare two shot PNGs (changed pixels, bounding box)")
    sp.add_argument("a")
    sp.add_argument("b")
    sp.add_argument("--tol", type=int, default=8, help="per-channel difference that counts as changed (default %(default)s)")
    sp.add_argument("--region", help="x,y,w,h")
    sp.add_argument("--max-frac", type=float, default=0.0, help="exit 0 if the changed fraction is at most this")
    sp.set_defaults(fn=cmd_imgdiff)
    sp = sub.add_parser("wait", help="wait until the agent answers (boot done)")
    sp.add_argument("limit", type=int, nargs="?", default=120)
    sp.set_defaults(fn=cmd_wait)
    return p


def main(argv=None):
    ns = build_parser().parse_args(argv)
    if ns.cmd == "crash" and ns.op in ("get", "clear") and not ns.id:
        sys.exit("odbc: crash %s needs an id" % ns.op)
    try:
        return ns.fn(ns) or 0
    except proto.AgentError as e:
        print("odbc: %s" % e, file=sys.stderr)
        return 4
    except (Timeout, Closed, TransportError) as e:
        print("odbc: %s: %s" % (type(e).__name__, e), file=sys.stderr)
        return 5
    except OSError as e:
        print("odbc: %s" % e, file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        return 130
