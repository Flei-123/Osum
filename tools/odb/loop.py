#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/odb/loop.py -- one continuous agent round trip over ODB, repeated N times, with a time per step.

One persistent odbc Session (hello+auth once) drives a booted ODB=1 desktop image:
  ping, info, exec (stdout + exit code), push/pull (sha256 compared on the host), ps,
  shot of the login screen, `input text` + `input key Enter` (login 'startkennwort'), desktop check (process list +
  shot differs from the login screen), start the Terminal with a mouse click on the taskbar icon, type a command
  into the GUI terminal (special characters on the guest's own keyboard layout), read the effect back with exec,
  terminal region of the shot before/after compared pixel-wise.
Every step is timed. A failed step is recorded and the run goes on (so a hang shows up as a FAIL with its timeout,
not as a stuck script). Exit code 0 = every check of every round passed.

  python3 -I tools/odb/loop.py --port unix:<dir>/odb.sock --token-file <f> [--rounds 5] [--out <dir>] [--json f]

Geometry: fractions of the screen (src_w x src_h from the first shot), measured on the 1280x800 desktop image:
the taskbar Terminal icon and the console window. See UI below.
"""
import argparse
import hashlib
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "odbc"))
from odb import img as IMG            # noqa: E402
from odb import proto                 # noqa: E402
from odb.client import Session, read_token_file   # noqa: E402

PASSWORD = "startkennwort"
# fractions of the screen: (x, y) of the Terminal icon in the taskbar; (x, y, w, h) of the Terminal window
UI = {"term_icon": (0.409, 0.970), "term_win": (0.020, 0.050, 0.440, 0.520), "term_click": (0.200, 0.300)}


class Run:
    def __init__(self, ns):
        self.ns = ns
        tok = read_token_file(ns.token_file) if ns.token_file else None
        self.s = Session.open(ns.port, wait=30, token=tok)
        self.s.login(timeout=10.0)
        self.rows = []          # dict per step
        self.round = 0
        self.fail = 0
        self.src = None         # (w, h) of the guest screen
        os.makedirs(ns.out, exist_ok=True)

    # ---- bookkeeping --------------------------------------------------------
    def rec(self, step, t0, ok, detail=""):
        dt = time.time() - t0
        self.rows.append({"round": self.round, "step": step, "seconds": round(dt, 3), "ok": bool(ok), "detail": detail})
        if not ok:
            self.fail += 1
        print("  %s r%d %-26s %7.2fs  %s" % ("OK  " if ok else "FAIL", self.round, step, dt, detail), flush=True)
        return ok

    def step(self, name, fn):
        """Run fn() -> (ok, detail). An exception is a failed step; the loop goes on."""
        t0 = time.time()
        try:
            ok, detail = fn()
        except Exception as e:   # noqa: BLE001 -- a failed step must not end the whole run
            ok, detail = False, "%s: %s" % (type(e).__name__, e)
        return self.rec(name, t0, ok, detail)

    # ---- helpers ------------------------------------------------------------
    def exec(self, cmd, timeout=30):
        r, out, err = self.s.exec(cmd=cmd, timeout=timeout)
        return r.geti("exit", -1), out.decode("utf-8", "replace"), err.decode("utf-8", "replace")

    def procs(self):
        """{name: pid}: ps lines are `pid ppid state rss_kb name` (docs/ODB.md); kernel threads have no name."""
        _, body = self.s.collect_stream("ps", {}, proto.STDOUT, timeout=20)
        d = {}
        for l in body.decode("utf-8", "replace").splitlines():
            f = l.split("\t")
            if len(f) >= 5 and f[4]:
                d[f[4]] = int(f[0])
        return d

    def shot(self, name, scale=None):
        items = {"format": "png", "scale": scale or self.ns.scale, "quant": self.ns.quant or None}
        r, body = self.s.collect_stream("shot", items, proto.SHOT, timeout=120)
        want = r.geti("bytes")
        if want is not None and want != len(body):
            raise RuntimeError("shot incomplete %d of %d" % (len(body), want))
        if self.src is None:
            self.src = (r.geti("src_w", 0), r.geti("src_h", 0))
        with open(os.path.join(self.ns.out, "r%d-%s.png" % (self.round, name)), "wb") as f:
            f.write(body)
        return IMG.decode_png(body), r

    def key(self, name, mods=None):
        self.s.request("input", [("kind", "key"), ("key", name), ("mods", mods), ("action", "press")], timeout=30)

    def text(self, t, delay_ms=15):
        self.s.request("input", [("kind", "text"), ("text", t), ("delay_ms", delay_ms)], timeout=60)

    def click(self, fx, fy):
        w, h = self.src
        self.s.request("input", [("kind", "mouse"), ("x", int(fx * w)), ("y", int(fy * h)), ("button", "left"),
                                 ("action", "click")], timeout=30)

    def region(self, im, frac):
        """Pixel region (x, y, w, h) of a decoded shot for a fractional rectangle."""
        w, h = im[0], im[1]
        return (int(frac[0] * w), int(frac[1] * h), int(frac[2] * w), int(frac[3] * h))

    def wait_for(self, pred, limit, every=1.0):
        end = time.time() + limit
        while time.time() < end:
            v = pred()
            if v:
                return v
            time.sleep(every)
        return None


def desktop_up(p):
    return "desktop" in p and "glogin" not in p


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", required=True)
    ap.add_argument("--token-file")
    ap.add_argument("--rounds", type=int, default=5)
    ap.add_argument("--out", default="odbloop-out")
    ap.add_argument("--json")
    ap.add_argument("--scale", type=int, default=25, help="shot scale percent (the line is slow: 25 = 320x200 of 1280x800)")
    ap.add_argument("--quant", type=int, default=0, help="shot colour bits dropped (0 = lossless)")
    ap.add_argument("--password", default=PASSWORD)
    ap.add_argument("--no-terminal", action="store_true", help="skip the GUI terminal part")
    ns = ap.parse_args()
    R = Run(ns)
    s = R.s
    print("agent: %s %s features=%s" % (s.hello_info.get("os"), s.hello_info.get("kernel"), s.hello_info.get("features")))
    t_all = time.time()
    st = {}

    for rnd in range(1, ns.rounds + 1):
        R.round = rnd
        t_round = time.time()
        print("== round %d ==" % rnd, flush=True)

        def st_ping():
            t = [s.ping(timeout=5.0) for _ in range(5)]
            return max(t) < 2.0, "avg %.1f ms max %.1f ms" % (sum(t) / len(t) * 1e3, max(t) * 1e3)
        R.step("ping x5", st_ping)

        def st_info():
            r = s.request("info", {}, timeout=20)
            return r.get("os") == "OrientOS", "cpus=%s mem_free=%d MiB idle=%s%% overruns=%s" % (
                r.get("cpus"), r.geti("mem_free_kb", 0) // 1024, r.get("idle_pct"), r.get("uart_overruns"))
        R.step("info", st_info)

        def st_exec():
            tag = "odbloop-%d-%d" % (rnd, int(time.time()))
            code, out, _ = R.exec("echo " + tag)
            c2, _, _ = R.exec("exit 3")
            return code == 0 and out.strip() == tag and c2 == 3, "stdout ok, exit 3 -> %d" % c2
        R.step("exec", st_exec)

        def st_pushpull():
            data = os.urandom(65536)
            sha = hashlib.sha256(data).hexdigest()
            t0 = time.time()
            s.push(data, "/tmp/odbloop.bin", timeout=60)
            t1 = time.time()
            _, back = s.pull("/tmp/odbloop.bin", timeout=60)
            t2 = time.time()
            R.exec("rm -f /tmp/odbloop.bin")
            return hashlib.sha256(back).hexdigest() == sha, "push %.1f KiB/s pull %.1f KiB/s rewinds=%d" % (
                64 / (t1 - t0), 64 / (t2 - t1), s.stats["rewinds"])
        R.step("push+pull 64KiB", st_pushpull)

        # ---- login screen or desktop ----------------------------------------------------------------
        p = R.procs()
        if not desktop_up(p):
            def st_shot_login():
                im, r = R.shot("login")
                st["login"] = im
                return True, "%sx%s of %sx%s, %s bytes" % (r.get("w"), r.get("h"), r.get("src_w"), r.get("src_h"), r.get("bytes"))
            R.step("shot login screen", st_shot_login)

            def st_login():
                R.text(ns.password)
                R.key("Enter")
                ok = R.wait_for(lambda: desktop_up(R.procs()), 120)
                return bool(ok), "desktop process up" if ok else "no desktop within 120 s"
            R.step("login (text+Enter)", st_login)
            time.sleep(4)

        def st_desktop():
            p = R.procs()
            im, r = R.shot("desktop")
            st["desktop"] = im
            ok = desktop_up(p) and "taskbar" in p
            extra = ""
            if "login" in st:
                d = IMG.diff(st["login"], im, tol=12)
                ok = ok and d["frac"] > 0.2
                extra = ", %.0f%% of the pixels differ from the login screen" % (d["frac"] * 100)
            return ok, "desktop+taskbar running, %d processes%s" % (len(p), extra)
        R.step("desktop check", st_desktop)

        if ns.no_terminal or "desktop" not in st:
            print("  round %d: %.1f s" % (rnd, time.time() - t_round))
            continue

        # ---- Terminal -----------------------------------------------------------------------------
        def term_visible(im):
            """The console window is a bright (white) panel; the wallpaper in that corner is dark/blue."""
            m = IMG.mean_rgb(im, R.region(im, UI["term_win"]))
            return min(m) > 200, m

        def st_term_open():
            im, _ = R.shot("term0")
            vis, m = term_visible(im)
            if vis:
                return True, "window already shown"
            R.click(*UI["term_icon"])
            for _ in range(6):
                time.sleep(2)
                im, _ = R.shot("term1")
                vis, m = term_visible(im)
                if vis:
                    st["term_before"] = im
                    return True, "window shown after the icon click, mean rgb %s" % (tuple(int(v) for v in m),)
            return False, "window not shown, mean rgb %s" % (tuple(int(v) for v in m),)
        R.step("start terminal (click)", st_term_open)

        def st_term_cmd():
            R.click(*UI["term_click"])          # focus
            time.sleep(0.5)
            before, _ = R.shot("typed0")
            tag = "ODBLOOP%d-%d" % (rnd, int(time.time()) % 100000)
            # '>' and '/' differ between layouts: this proves `input text` follows the guest keyboard layout
            R.text("echo %s > /tmp/odbloop.txt" % tag)
            R.key("Enter")
            got = ""
            for _ in range(10):
                time.sleep(0.5)
                code, got, _ = R.exec("cat /tmp/odbloop.txt 2>/dev/null")
                if got.strip() == tag:
                    break
            if got.strip() != tag:
                return False, "file has %r, expected %r" % (got.strip()[:40], tag)
            after, _ = R.shot("typed1")
            d = IMG.diff(before, after, tol=12, region=R.region(after, UI["term_win"]))
            st["typed_frac"] = d["frac"]
            return d["frac"] > 0.002, "typed text reached the shell (file ok), terminal region changed %.2f%%" % (d["frac"] * 100)
        R.step("type into terminal", st_term_cmd)

        def st_stable():
            a, _ = R.shot("stable0")
            b, _ = R.shot("stable1")
            # the terminal region is static between two shots; the clock/CPU widgets live outside it
            d = IMG.diff(a, b, tol=12, region=R.region(a, UI["term_win"]))
            return d["frac"] < 0.01, "two shots of the idle terminal differ in %.2f%%" % (d["frac"] * 100)
        R.step("shot compare (idle)", st_stable)
        print("  round %d: %.1f s" % (rnd, time.time() - t_round), flush=True)

    total = time.time() - t_all
    print("== done: %d rounds, %.1f s, %d failed steps ==" % (ns.rounds, total, R.fail))
    # per-step summary (mean of the rounds)
    names = []
    for r in R.rows:
        if r["step"] not in names:
            names.append(r["step"])
    print("== mean seconds per step ==")
    summary = {}
    for n in names:
        v = [r["seconds"] for r in R.rows if r["step"] == n]
        summary[n] = {"n": len(v), "mean": round(sum(v) / len(v), 3), "max": max(v), "fail": sum(1 for r in R.rows if r["step"] == n and not r["ok"])}
        print("  %-26s n=%d mean %.2fs max %.2fs fail %d" % (n, len(v), summary[n]["mean"], summary[n]["max"], summary[n]["fail"]))
    if ns.json:
        with open(ns.json, "w") as f:
            json.dump({"rounds": ns.rounds, "seconds": round(total, 1), "failed": R.fail, "steps": summary, "rows": R.rows}, f, indent=1)
    return 1 if R.fail else 0


if __name__ == "__main__":
    sys.exit(main())
