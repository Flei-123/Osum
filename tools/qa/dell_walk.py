#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/qa/dell_walk.py -- click through EVERY app of the start menu and write a protocol.

    dell_walk.py vm   <outdir> [--res 3440x1440] [--accel kvm] [--apps a,b,c]
    dell_walk.py echt <outdir> [--device osum-a4206b26eb96] [--apps a,b,c] [--dry]
    dell_walk.py eval <outdir> --runner <eh6 output dir>      (judge an existing VM run again)
    dell_walk.py list

Two modes, ONE app table (APPS below):

  vm    boots the stick machine (tools/design/eh6.sh, QEMU/KVM, 3440x1440) with a generated
        script (drehbuch) for tools/design/drive.py. Per app: open through the start menu,
        screenshot, maximise / restore / drag / close, screenshot after every step. The serial
        log is cut per step (drive.py `schritt`) and scanned for crash lines, the pictures are
        compared pixel by pixel (a step that changes nothing on the screen did not happen).
  echt  does the same on the real Dell through the bridge (POST /bruecke/auftrag on the local
        bridge server, see docs/BRUECKE.md): input = scan codes + mouse jobs, photo = PNG job,
        ps / log / jarvisd.log as the process and crash evidence. Needs the device online and
        `input = yes` in its /etc/jarvis/permissions.conf. See docs/QA-DELL-DURCHKLICK.md.

The protocol (<outdir>/protokoll.md + protokoll.json) gives each app OK / FEHLER and separates
  VM       = reproducible in the VM (a bug in the system, fix it here)
  NUR-DELL = can only be judged on the real machine (hardware, drivers, keyboard, I219 net);
             the VM run lists these as OFFEN and never as OK.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

# ---------------------------------------------------------------- the app table
# id      short name used in file names
# term    what is typed into the start menu search (the first hit is started with Return)
# bin     the program the launcher must start (`launcher: start <bin> pid=N` on the serial line)
# prog    firn program(s) that have to be in the image for the app to exist
# acts    extra drehbuch lines after the app is open (VM mode); every `foto` is judged
APPS = [
    dict(id="settings", osp="settings", name="Settings", term="settings", bin="settings", prog="settings settingsd",
         acts=["warte 3", "klick_body", "foto {id}-3-body", "taste tab", "warte 1", "foto {id}-4-tab"]),
    dict(id="explorer", osp="explorer", name="File Explorer", term="explorer", bin="explorer", prog="explorer",
         acts=["warte 3", "taste ctrl-n", "warte 3", "foto {id}-3-dialog", "taste esc", "warte 2",
               "foto {id}-4-dialog-zu"]),
    dict(id="terminal", osp="terminal", name="Terminal", term="terminal", bin="sh", prog="sh ls ps echo cat",
         acts=["warte 3", "klick_body", "tippe ls", "taste ret", "warte 2", "tippe ps", "taste ret",
               "warte 3", "foto {id}-3-ls-ps"]),
    dict(id="terminal2", osp="terminal", name="Terminal (second window)", term="terminal", bin="sh", prog="sh",
         known="multi-terminal: worker A (tools/term/multi.sh)",
         acts=["warte 3", "klick_body", "tippe echo zwei", "taste ret", "warte 2", "foto {id}-3-echo"]),
    dict(id="terminal3", osp="terminal", name="Terminal (third window)", term="terminal", bin="sh", prog="sh",
         known="multi-terminal: worker A (tools/term/multi.sh)",
         acts=["warte 3", "klick_body", "tippe echo drei", "taste ret", "warte 2", "foto {id}-3-echo"]),
    dict(id="editor", osp="editor", name="Editor", term="editor", bin="nedit", prog="nedit",
         acts=["warte 3", "klick_body", "tippe hallo", "warte 2", "foto {id}-3-getippt"]),
    dict(id="taskmgr", osp="taskmgr", name="Task Manager", term="task", bin="taskmgr", prog="taskmgr ps kill",
         acts=["warte 6", "foto {id}-3-nach-6s"]),
    dict(id="pdfview", osp="pdfview", name="PDF-Betrachter", term="pdf", bin="pdfview", prog="pdfview",
         acts=["warte 3", "foto {id}-3-leer"]),
    dict(id="store", osp="store", name="Programme (Store)", term="programme", bin="store", prog="store stored",
         acts=["warte 5", "foto {id}-3-nach-5s"]),
    dict(id="trashbin", osp="trashbin", name="Papierkorb", term="papierkorb", bin="trashbin", prog="trashbin",
         acts=["warte 3", "foto {id}-3-liste"]),
    dict(id="widgets", osp="widgets", name="Widgets", term="widgets", bin="widgetdemo", prog="widgetdemo",
         acts=["warte 3", "klick_body", "taste tab", "taste tab", "warte 1", "foto {id}-3-tab"]),
    dict(id="certus", osp="certus", name="Certus (browser)", term="certus", bin="certus", prog="",
         needs_special_build=True,
         acts=["warte 8", "foto {id}-3-nach-8s"]),
]
# tray / panel things that are not in the app list but a human clicks on them in the first minute
TRAY = [
    dict(id="netz", name="Control centre (network icon)", rect="netz"),
    dict(id="uhr", name="Clock", rect="uhr"),
    dict(id="glocke", name="Notifications", rect="glocke"),
]
# the installer is deliberately NOT started (it would partition a disk); the launcher is the menu itself
NOT_STARTED = ["installer", "launcher"]

# things only the real Dell can answer -- the VM protocol lists them as OFFEN, never as OK
NUR_DELL = [
    ("keyboard", "real keyboard layout, AltGr, Fn keys, key repeat (VM: QEMU sendkey, US layout)"),
    ("pointer", "touchpad / USB mouse speed, acceleration, scroll (VM: PS/2)"),
    ("net", "I219 link, DHCP lease, DNS, TLS to the bridge server (VM: user-mode NAT)"),
    ("display", "EDID 3440x1440, refresh rate, tearing, frame time with blur (VM: bochs VGA)"),
    ("gpu", "real memory bandwidth: window drag with glass, start menu blur"),
    ("sound", "Intel HDA codec on the Dell (VM: no card unless ton=ja)"),
    ("usb", "xHCI hot plug of a real stick / mouse / keyboard"),
    ("power", "S3 standby, lid, battery, fan, reboot on real firmware"),
    ("wlan", "no radio driver (roadmap N-005) -- cannot be walked at all"),
    ("camera", "no UVC driver (roadmap K-007) -- cannot be walked at all"),
]

CRASH_RE = re.compile(
    r"(panic|PANIC|page fault|#PF|#UD|#GP|general protection|double fault|SIGSEGV|SIGILL|SIGBUS|"
    r"segfault|killed by|stack smash|unhandled|[Oo]ops|FAULT|assert(ion)? fail|launcher: start refused|"
    r"elf: refused|no such program|exec failed|out of memory|OOM )")
# serial lines that look like a crash but are boot-time summaries or on purpose (extend with care)
CRASH_IGNORE = re.compile(r"^(tafel|disp|usb|USB|heap test|fb|osum|smp|wm: selftest|wm: termzeile|tile|"
                          r"pci|ttf|kbd|key|pwr|r3|wlib)\b|nofault|fault-test|fault_inject|FAIL 0")


# ---------------------------------------------------------------- helpers
def read(path):
    try:
        with open(path, "rb") as f:
            return f.read().decode("latin1")
    except OSError:
        return ""


def ppm_to_array(path):
    import numpy as np
    from PIL import Image
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.int16)


def pixel_diff(a, b, thresh=10):
    """Share (0..1) of pixels whose colour changed by more than `thresh` in any channel."""
    import numpy as np
    if a is None or b is None or a.shape != b.shape:
        return 1.0 if (a is None) != (b is None) else 0.0
    d = np.abs(a - b).max(axis=2)
    return float((d > thresh).sum()) / float(d.size)


def distinct_colours(a):
    import numpy as np
    flat = (a[:, :, 0].astype(np.int32) << 16) | (a[:, :, 1].astype(np.int32) << 8) | a[:, :, 2]
    return int(len(np.unique(flat[::7, ::7])))


def script_lines(apps, res, tray=True):
    """The drehbuch for tools/design/drive.py. `klick_body` is a macro: click in the middle of the
    screen (so the keyboard goes to the app that stands there), expanded here from the screen size."""
    w, h = (int(v) for v in res.split("x"))
    out = ["# generated by tools/qa/dell_walk.py -- do not edit",
           "warteauf 'launcher: ready' || 120", "warte 6", "taste esc", "warte 2",
           "schritt boot ready", "foto 00-desktop"]
    for a in apps:
        i = a["id"]
        out += ["", "# ---- %s" % a["name"], "schritt %s begin" % i,
                "foto %s-0-vorher" % i, "klickauf start", "warte 3", "foto %s-1-startmenu" % i,
                "marke 'launcher: start '", "tippe %s" % a["term"], "warte 2", "taste ret",
                "warteneu 'launcher: start ' || 20", "warte 8",
                "schritt %s opened" % i, "foto %s-2-offen" % i, "taste f12", "warte 2"]
        for line in a.get("acts", []):
            line = line.format(id=i)
            if line == "klick_body":
                line = "klick %d,%d" % (w // 2, h // 2 - 100)
            out.append(line)
        out += ["schritt %s acted" % i,
                # maximise, restore, drag, close: the caption buttons the window server reports
                "taste f12", "warte 2", "kappe fokus max", "warte 3", "foto %s-5-max" % i,
                "taste f12", "warte 2", "kappe fokus max", "warte 3", "foto %s-6-restore" % i,
                "taste f12", "warte 2", "ziehtitel fokus 160,90", "warte 3", "foto %s-7-gezogen" % i,
                "taste f12", "warte 2", "kappe fokus close", "warte 4", "schritt %s closed" % i,
                "foto %s-8-zu" % i, "schritt %s end" % i]
    if tray:
        for t in TRAY:
            i = t["id"]
            out += ["", "# ---- %s" % t["name"], "schritt %s begin" % i, "foto %s-0-vorher" % i,
                    "klickauf %s" % t["rect"], "warte 3", "schritt %s opened" % i, "foto %s-2-offen" % i,
                    "taste esc", "warte 2", "foto %s-8-zu" % i, "schritt %s end" % i]
    out += ["", "schritt walk end", "foto 99-ende"]
    return out


# ---------------------------------------------------------------- evaluation (VM)
def load_steps(out):
    steps = []
    for z in read(os.path.join(out, "schritte.tsv")).splitlines():
        p = z.split("\t")
        if len(p) == 3:
            steps.append((int(p[0]), float(p[1]), p[2].strip()))
    return steps


# The VM image carries no /bin/jarvisd (the bridge daemon is not built into the walk image), so the
# desktop's boot-time `desk: start /bin/jarvisd` is always followed by one loader refusal. That pair
# is a property of the walk image, not an app fault: drop exactly that pair, keep every other refusal.
JARVISD_PAIR = re.compile(r"(desk: start /bin/jarvisd[^\n]*\n)elf: refused, reason 1  no such file\n?")


def crash_lines(text):
    text = JARVISD_PAIR.sub(r"\1", text)
    hits = []
    for z in text.splitlines():
        if CRASH_RE.search(z) and not CRASH_IGNORE.search(z):
            hits.append(z.strip()[:160])
    return hits


def judge_app(a, out, serial, steps, shots):
    """Return (status, [reasons], info). status OK / FEHLER / SKIP."""
    i = a["id"]
    marks = {s[2]: s for s in steps}
    b, e = marks.get("%s begin" % i), marks.get("%s end" % i)
    reasons, info = [], {}
    if a.get("needs_special_build"):
        return "SKIP", ["not in the VM image (needs kernel/user/certus/build.sh); walk it on the Dell"], info
    if not b or not e:
        return "FEHLER", ["the walk never reached this app (driver or machine died before)"], info
    sl = serial[b[0]:e[0]]
    info["serial_bytes"] = len(sl)
    starts = re.findall(r"launcher: start (\S+)[^\n]*", sl)
    started = [s for s in starts if not s.startswith("refused")]
    m = re.search(r"launcher: start refused[^\n]*", sl)
    if m:
        reasons.append("launcher refused the start: " + m.group(0)[:100])
    if not started:
        reasons.append("no `launcher: start` line: the start menu did not start anything")
    else:
        info["started"] = started[-1]
        if ("/%s.osp/" % a["osp"]) not in started[-1] and a["bin"] not in started[-1] and not reasons:
            reasons.append("the launcher started `%s`, expected bundle `%s.osp`" % (started[-1], a["osp"]))
    crashes = [c for c in crash_lines(sl) if "launcher: start refused" not in c]
    if crashes:
        reasons.append("crash/error line(s) on the serial log: " + " | ".join(crashes[:2]))
    # r545: Settings says how many lines of the theme files it did not understand (the window shows the same number)
    if i == "settings":
        bad = re.findall(r"settings: shape file=[^\n]* bad=(\d+)", sl)
        if bad:
            info["bad_lines"] = int(bad[-1])
            if int(bad[-1]) > 0:
                reasons.append("Settings counts %s theme line(s) as not understood (settings: shape ... bad=)" % bad[-1])
    # r541: the widget layout must fit the (scaled) window: no rectangle outside it, none on another one
    # (at 3440x1440 the interface scale is 2; unscaled boxes put buttons on the text fields)
    if i == "widgets":
        g = re.search(r"widgetdemo: geom w=(\d+) h=(\d+)", sl)
        if not g:
            reasons.append("widgetdemo did not report its window geometry")
        else:
            import tempfile
            with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="latin-1") as tf:
                tf.write(sl)
            r = subprocess.run(["python3", "-I", os.path.join(ROOT, "tools/k15/layout.py"), tf.name,
                                "widgetdemo", g.group(1), g.group(2), "8"],
                               capture_output=True, text=True)
            os.unlink(tf.name)
            info["layout_rc"] = r.returncode
            # the rectangles must also FILL the scaled window: boxes laid out unscaled leave the right
            # 55 % and the bottom half empty while the text is drawn at scale 2 (no overlap among the
            # rectangles themselves, so layout.py alone cannot see it)
            rects = [tuple(int(v) for v in m) for m in re.findall(
                r"widgetdemo: rect id=\d+ kind=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)", sl)]
            if rects:
                right = max(x + w for x, y, w, h in rects)
                bottom = max(y + h for x, y, w, h in rects)
                info["layout_extent"] = "%dx%d of %sx%s" % (right, bottom, g.group(1), g.group(2))
                if right * 100 < int(g.group(1)) * 90 or bottom * 100 < int(g.group(2)) * 85:
                    reasons.append("widget rectangles reach only %dx%d of the %sx%s window (layout not scaled)" %
                                   (right, bottom, g.group(1), g.group(2)))
            if r.returncode != 0:
                reasons.append("widget layout wrong in the %sx%s window: %s" %
                               (g.group(1), g.group(2), " | ".join((r.stdout or r.stderr).strip().splitlines()[:2])))
    pre, post, closed = (shots.get("%s-%s" % (i, k)) for k in ("0-vorher", "2-offen", "8-zu"))
    d_open = pixel_diff(pre, post) if pre is not None and post is not None else None
    d_close = pixel_diff(post, closed) if post is not None and closed is not None else None
    info["diff_open"], info["diff_close"] = d_open, d_close
    if post is None:
        reasons.append("no picture after the start")
    elif d_open is not None and d_open < 0.003:
        reasons.append("the screen did not change after the start (diff %.4f): no window appeared" % d_open)
    if post is not None and distinct_colours(post) < 8:
        reasons.append("the picture after the start is blank (<8 colours)")
    for key, label, base in (("5-max", "maximise", "2-offen"), ("7-gezogen", "drag", "6-restore")):
        prev, cur = shots.get("%s-%s" % (i, base)), shots.get("%s-%s" % (i, key))
        if prev is not None and cur is not None:
            d = pixel_diff(prev, cur)
            info["diff_" + label] = d
            if d < 0.002:
                reasons.append("%s changed nothing on the screen (diff %.4f)" % (label, d))
    if d_close is not None and d_close < 0.003 and not a.get("keeps_open"):
        reasons.append("the window did not close (diff %.4f)" % d_close)
    return ("FEHLER" if reasons else "OK"), reasons, info


def judge_tray(t, out, serial, steps, shots):
    i = t["id"]
    marks = {s[2]: s for s in steps}
    b, e = marks.get("%s begin" % i), marks.get("%s end" % i)
    if not b or not e:
        return "FEHLER", ["not reached"], {}
    sl = serial[b[0]:e[0]]
    reasons = []
    pre, post = (shots.get("%s-%s" % (i, k)) for k in ("0-vorher", "2-offen"))
    if re.search(r"klickauf %s -> KEIN" % t["rect"], read(os.path.join(out, "..", "fahren.log")) +
                 read(os.path.join(out, "fahren.log"))):
        reasons.append("the taskbar never reported the rectangle `%s`" % t["rect"])
    elif pre is not None and post is not None and pixel_diff(pre, post) < 0.001:
        reasons.append("clicking changed nothing on the screen")
    crashes = crash_lines(sl)
    if crashes:
        reasons.append("crash/error line(s): " + " | ".join(crashes[:2]))
    return ("FEHLER" if reasons else "OK"), reasons, {}


def run_vm(args):
    out = os.path.abspath(args.outdir)
    os.makedirs(out, exist_ok=True)
    apps = [a for a in APPS if not args.apps or a["id"] in args.apps.split(",")]
    progs = ("desktop taskbar launcher explorer settings netview theme echo ls cat ps uname date df mkdir rm cp mv grep "
             "head tail wc find du chmod id whoami touch true false sleep kill sort uniq rmdir locate "
             "dhcp host ping netstat sh orientbus act axd")
    have = set(progs.split())
    for a in apps:
        for p in a["prog"].split():
            if p not in have:
                progs += " " + p
                have.add(p)
    with open(os.path.join(out, "drehbuch.txt"), "w") as f:
        f.write("\n".join(script_lines(apps, args.res, tray=not args.apps)) + "\n")
    runner = os.path.join(out, "run")
    env = dict(os.environ)
    env.setdefault("DESIGNBUILD", out + "-build")
    cmd = ["bash", os.path.join(ROOT, "tools/design/eh6.sh"), runner, "accel=" + args.accel,
           "res=" + args.res, "progs=" + progs, "drehbuch=" + os.path.join(out, "drehbuch.txt"),
           "halt=0", "tafel=nein", "tzrule=eu"]  # tzrule=eu: the personal image has `rule=eu` in /etc/time.conf
    print("vm: eh6.sh res=%s accel=%s progs=%d" % (args.res, args.accel, len(have)), flush=True)
    t0 = time.time()
    with open(os.path.join(out, "eh6.log"), "w") as lg:
        rc = subprocess.call(cmd, cwd=ROOT, env=env, stdout=lg, stderr=subprocess.STDOUT)
    print("vm: eh6.sh rc=%d in %.0f s" % (rc, time.time() - t0), flush=True)
    return evaluate_vm(runner, out, apps, args, rc)


def evaluate_vm(runner, out, apps, args, rc=0):
    serial = read(os.path.join(runner, "serial.txt"))
    steps = load_steps(runner)
    shots = {}
    for fn in sorted(os.listdir(runner)):
        if fn.endswith(".ppm"):
            try:
                shots[fn[:-4]] = ppm_to_array(os.path.join(runner, fn))
            except Exception as ex:  # a half-written picture counts as missing
                print("picture %s unreadable: %s" % (fn, ex))
    res = []
    for a in apps:
        st, why, info = judge_app(a, runner, serial, steps, shots)
        res.append(dict(kind="app", id=a["id"], name=a["name"], status=st, reasons=why, info=info,
                        scope="VM" if st == "FEHLER" else "-", known=a.get("known", "")))
    if not args.apps:
        for t in TRAY:
            st, why, info = judge_tray(t, runner, serial, steps, shots)
            res.append(dict(kind="tray", id=t["id"], name=t["name"], status=st, reasons=why, info=info,
                            scope="VM" if st == "FEHLER" else "-", known=""))
    glob_crash = crash_lines(serial)
    boot_ok = bool(re.search(r"^wm: hold|launcher: ready", serial, re.M))
    summary = dict(mode="vm", res=args.res, accel=args.accel, eh6_rc=rc, boot_ok=boot_ok,
                   serial_bytes=len(serial), crash_lines_total=len(glob_crash),
                   crash_samples=glob_crash[:8], steps=len(steps))
    write_protocol(out, res, summary)
    from PIL import Image
    shotdir = os.path.join(out, "fotos")
    os.makedirs(shotdir, exist_ok=True)
    for k in shots:
        if k.endswith(("-2-offen", "-8-zu", "-5-max")) or k in ("00-desktop", "99-ende"):
            Image.open(os.path.join(runner, k + ".ppm")).convert("RGB").save(os.path.join(shotdir, k + ".png"))
    if not getattr(args, "keep_ppm", False):           # the 15 MB ppm files are only kept on request
        for fn in os.listdir(runner):
            if fn.endswith(".ppm"):
                os.unlink(os.path.join(runner, fn))
    return 0 if all(r["status"] != "FEHLER" for r in res) else 1


def write_protocol(out, res, summary):
    ok = sum(1 for r in res if r["status"] == "OK")
    bad = sum(1 for r in res if r["status"] == "FEHLER")
    skip = sum(1 for r in res if r["status"] == "SKIP")
    summary.update(ok=ok, fehler=bad, skip=skip, total=len(res))
    with open(os.path.join(out, "protokoll.json"), "w") as f:
        json.dump(dict(summary=summary, results=res, nur_dell=[dict(id=k, what=v) for k, v in NUR_DELL]), f,
                  indent=1, default=str)
    L = ["# Dell walk protocol (%s)" % summary["mode"], "",
         "- result: **%d OK / %d FEHLER / %d SKIP** of %d" % (ok, bad, skip, len(res)),
         "- machine: %s" % json.dumps({k: v for k, v in summary.items() if k != "crash_samples"}),
         "", "| item | status | scope | why |", "|---|---|---|---|"]
    for r in res:
        why = "; ".join(r["reasons"]) if r["reasons"] else ""
        if r.get("known"):
            why += " [known: %s]" % r["known"]
        L.append("| %s | %s | %s | %s |" % (r["name"], r["status"], r["scope"], why.replace("|", "/")))
    L += ["", "## Only on the real Dell (OFFEN -- this run cannot say OK)", ""]
    L += ["- **%s**: %s" % (k, v) for k, v in NUR_DELL]
    if summary.get("crash_samples"):
        L += ["", "## Crash-like lines anywhere on the serial log", ""]
        L += ["- `%s`" % z for z in summary["crash_samples"]]
    with open(os.path.join(out, "protokoll.md"), "w") as f:
        f.write("\n".join(L) + "\n")
    print("\n".join(L[:5 + len(res)]))


# ---------------------------------------------------------------- echt mode (bridge)
# set-1 make codes for the keys the walk needs (break = make | 0x80)
SC = {c: v for c, v in zip("1234567890", range(2, 12))}
for _row, _base in (("qwertyuiop", 0x10), ("asdfghjkl", 0x1E), ("zxcvbnm", 0x2C)):
    for _n, _c in enumerate(_row):
        SC[_c] = _base + _n
SC.update({" ": 0x39, "ret": 0x1C, "esc": 0x01, "tab": 0x0F, "f12": 0x58, "+": 0x0D})


class Bruecke:
    """Local client of bruecke_server.py (127.0.0.1:8090). The device never talks to this script."""

    def __init__(self, device, base="http://127.0.0.1:8090", keyfile="/srv/bruecke/verwalter.key", dry=False):
        self.device, self.base, self.dry = device, base, dry
        self.vkey = read(keyfile).strip()
        self.log = []

    def _req(self, method, path, body=None, timeout=40):
        import urllib.request
        import urllib.error
        rq = urllib.request.Request(self.base + path, method=method,
                                    data=json.dumps(body).encode() if body is not None else None,
                                    headers={"X-Bruecke-Verwalter": self.vkey, "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(rq, timeout=timeout) as r:
                return r.status, dict(r.headers), r.read()
        except urllib.error.HTTPError as e:
            return e.code, dict(e.headers), e.read()
        except OSError as e:
            return 0, {}, str(e).encode()

    def online(self):
        st, _, body = self._req("GET", "/bruecke/geraete")
        if st != 200:
            return False, "bridge server: HTTP %s %s" % (st, body[:80])
        for g in json.loads(body).get("geraete", []):
            if self.device in json.dumps(g):
                alive = g.get("verbunden", g.get("lebt", g.get("online", False)))
                return bool(alive), json.dumps(g)[:200]
        return False, "device %s is not registered at the bridge" % self.device

    def job(self, art, ziel="", wert="", wait=True, timeout=60):
        if self.dry:
            self.log.append((art, ziel, wert))
            print("  [dry] %s %s %s" % (art, ziel, wert[:60]))
            return 200, "", b""
        st, _, body = self._req("POST", "/bruecke/auftrag",
                                dict(geraet=self.device, art=art, ziel=ziel, wert=wert, ttl_s=120))
        if st != 200:
            return st, "", body
        aid = json.loads(body)["id"]
        if not wait:
            return 200, "", b""
        end = time.time() + timeout
        while time.time() < end:
            st, hd, rump = self._req("GET", "/bruecke/holen?geraet=%s&id=%s" % (self.device, aid), timeout=35)
            if st == 200:
                return 200, hd.get("X-Bruecke-Status", ""), rump
            if st != 404:
                return st, "", rump
        return 0, "", b"timeout"

    def photo(self, path):
        """One photo. The screenshot permit of the Dell lasts ONE photo / 60 s (`jarvisctl screenshot`), so it is
        asked for before EVERY photo, never once per run (r547)."""
        self.job("command", "/bin/jarvisctl screenshot")
        st, status, body = self.job("photo")
        if st == 200 and body[:4] == b"\x89PNG":
            with open(path, "wb") as f:
                f.write(body)
            return True
        return self.dry

    def keys(self, text):
        codes = []
        for ch in text:
            c = SC.get(ch.lower())
            if c is not None:
                codes += [c, c | 0x80]
        if codes:
            self.job("input", "scan " + " ".join(str(c) for c in codes))

    def key(self, name):
        c = SC[name]
        self.job("input", "scan %d %d" % (c, c | 0x80))

    def click(self, x, y):
        self.job("input", "maus %d %d" % (x, y))
        self.job("input", "knopf 1 1")
        self.job("input", "knopf 1 0")


    def drag(self, x1, y1, x2, y2):
        self.job("input", "maus %d %d" % (x1, y1))
        self.job("input", "knopf 1 1")
        self.job("input", "maus %d %d" % ((x1 + x2) // 2, (y1 + y2) // 2))
        self.job("input", "maus %d %d" % (x2, y2))
        self.job("input", "knopf 1 0")


# ps of the Dell: `PID PPID STATE ... NAME`. Apps show up with the name `-` (the bundle's `start`), only the Terminal is
# `sh`, and the task manager calls them `start` -- so an app is recognised by a NEW PID, never by its name (r547).
PS_RE = re.compile(r"\s*(\d+)\s+(\d+)\s+(\S+)\s+\S+\s+\d+\s+\d+\s+\S+\s+(.*)")
PS_TOOLS = ("ps", "log", "kill", "tail", "jarvisctl", "cat", "head")


def parse_ps(text):
    """{pid: (ppid, state, name)} from the output of `/bin/ps`"""
    out = {}
    for z in text.splitlines():
        m = PS_RE.match(z)
        if m:
            out[int(m.group(1))] = (int(m.group(2)), m.group(3), m.group(4).strip())
    return out


def new_pids(before, after):
    """PIDs that appeared between two ps listings (tools like ps/log themselves excluded)"""
    return {k: v for k, v in after.items() if k not in before and v[2].split(" ")[0] not in PS_TOOLS}


def window_rect(before_png, after_png, thresh=30):
    """The window that appeared between two photos: bounding box (x0, y0, x1, y1) of the rows/columns that changed
    in most of their length -- the window frame, not the soft shadow. None when nothing changed. The title bar Y is
    taken from THIS box (every window stands somewhere else on the 1024x768 Dell)."""
    import numpy as np
    a, b = load_png(before_png), load_png(after_png)
    if a.shape != b.shape:
        return None
    m = np.abs(a - b).max(axis=2) > thresh
    if m.sum() < 400:
        return None
    rows, cols = m.sum(axis=1), m.sum(axis=0)
    ry = np.where(rows >= 0.5 * rows.max())[0]
    cx = np.where(cols >= 0.5 * cols.max())[0]
    if len(ry) == 0 or len(cx) == 0:
        return None
    return int(cx[0]), int(ry[0]), int(cx[-1]), int(ry[-1])


def buttons(rect):
    """Close / maximise / minimise button and the drag point from a window rect (the buttons sit right at the top of the
    title bar: 24 / 70 / 116 px from the right edge, 16 px below the top edge -- measured on the Dell photos)"""
    x0, y0, x1, y1 = rect
    ty = y0 + 16
    return dict(close=(x1 - 24, ty), maxi=(x1 - 70, ty), mini=(x1 - 116, ty), drag=(x0 + (x1 - x0) // 3, ty))


def png_size(path):
    with open(path, "rb") as f:
        d = f.read(32)
    return int.from_bytes(d[16:20], "big"), int.from_bytes(d[20:24], "big")


def load_png(path):
    import numpy as np
    from PIL import Image
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.int16)


LOCK_NAMES = ("lock", "login", "glogin")


def screen_locked(ps_text):
    """True when the lock screen / sign-in program is in the process list (typing into it would be typed into the
    password field). The NAME column is the last one."""
    for z in ps_text.splitlines():
        p = z.split()
        if len(p) >= 8 and p[0].isdigit() and p[-1] in LOCK_NAMES:
            return True
    return False


def run_echt(args):
    """The walk on the REAL Dell. r547: (1) a permit before EVERY photo (Bruecke.photo), (2) an app is a NEW PID in ps (the
    name is `-`), (3) per window: maximise, restore, drag, close with the buttons found in THE PHOTO (window_rect), then
    kill what is left, (4) three terminals, (5) OK / FEHLER per app and per window step in the protocol."""
    out = os.path.abspath(args.outdir)
    os.makedirs(out, exist_ok=True)
    br = Bruecke(args.device, dry=args.dry)
    if not args.dry:
        up, why = br.online()
        print("device check: %s (%s)" % ("ONLINE" if up else "OFFLINE", why))
        if not up:
            print("ABORT: the Dell is not online -- nothing was sent.")
            return 3
    if not args.dry:
        ps_txt = br.job("command", "/bin/ps")[2].decode("latin1")
        if screen_locked(ps_txt):
            print("ABORT: the lock screen / sign-in is running on the Dell -- nothing was typed (log in first).")
            return 3
    apps = [a for a in APPS if not args.apps or a["id"] in args.apps.split(",")]
    shotdir = os.path.join(out, "fotos")
    os.makedirs(shotdir, exist_ok=True)
    first = os.path.join(shotdir, "00-desktop.png")
    if not br.photo(first) and not args.dry:
        print("ABORT: no photo (is `screenshot = yes` in the permission list?)")
        return 3
    W, H = png_size(first) if os.path.exists(first) else (1024, 768)
    start = (24, H - 20)
    wait = (lambda t: None) if args.dry else time.sleep
    res, fails_in_row = [], 0

    def ps_now():
        return parse_ps(br.job("command", "/bin/ps")[2].decode("latin1"))

    for a in apps:
        i = a["id"]
        shot = lambda k: os.path.join(shotdir, "%s-%s.png" % (i, k))
        pre, post = shot("0-vorher"), shot("2-offen")
        reasons, steps = [], []
        ps0 = ps_now()
        br.photo(pre)
        br.click(*start)
        wait(3)
        br.keys(a["term"])
        br.key("ret")
        wait(10)
        br.photo(post)
        ps1 = ps_now()
        log = br.job("command", "/bin/log -l warn -n 40")[2].decode("latin1")
        if args.dry:
            rect = (100, 100, 700, 500)
        else:
            d = pixel_diff(load_png(pre), load_png(post))
            if d < 0.003:
                reasons.append("the screen did not change after the start (diff %.4f)" % d)
            rect = window_rect(pre, post)
        fresh = new_pids(ps0, ps1)
        if not fresh and not args.dry:
            reasons.append("no new process after the start (apps show as `-` in ps, the terminal as `sh`; looked for a new PID)")
        c = crash_lines(log)
        if c:
            reasons.append("kernel log: " + " | ".join(c[:2]))
        # ---- window steps: only when a window was found in the photo
        if rect is None and not args.dry:
            steps.append(("window", False, "no window found in the photo (nothing to maximise / drag / close)"))
        elif rect is not None and not reasons:
            bt = buttons(rect)
            # maximise
            br.click(*bt["maxi"])
            wait(2)
            mx = shot("3-max")
            br.photo(mx)
            r2 = window_rect(pre, mx) if not args.dry else (0, 0, W, H)
            steps.append(("maximise", bool(r2 and r2[2] - r2[0] >= 0.9 * W),
                          "window box after: %s (screen %dx%d)" % (r2, W, H)))
            # restore (the maximised window's buttons: same distance from the right edge, top edge 0)
            bm = buttons(r2 if r2 else (0, 0, W, H))
            br.click(*bm["maxi"])
            wait(2)
            rs = shot("4-restore")
            br.photo(rs)
            r3 = window_rect(pre, rs) if not args.dry else rect
            same = bool(r3 and abs(r3[0] - rect[0]) < 24 and abs(r3[1] - rect[1]) < 24 and abs(r3[2] - rect[2]) < 24)
            steps.append(("restore", same, "window box %s, before the maximise %s" % (r3, rect)))
            cur = r3 if r3 else rect
            # drag by the title bar
            bd = buttons(cur)
            dx, dy = (60, 60) if cur[2] + 60 < W and cur[3] + 60 < H - 40 else (-60, -60)
            br.drag(bd["drag"][0], bd["drag"][1], bd["drag"][0] + dx, bd["drag"][1] + dy)
            wait(2)
            dr = shot("5-ziehen")
            br.photo(dr)
            r4 = window_rect(pre, dr) if not args.dry else cur
            moved = bool(r4 and (abs(r4[0] - cur[0]) >= 30 or abs(r4[1] - cur[1]) >= 30))
            steps.append(("drag", moved, "window box %s -> %s" % (cur, r4)))
            # close with X
            bc = buttons(r4 if r4 else cur)
            br.click(*bc["close"])
            wait(3)
            zx = shot("6-x")
            br.photo(zx)
            ps2 = ps_now()
            gone = all(k not in ps2 for k in fresh)
            clean = (not args.dry) and pixel_diff(load_png(pre), load_png(zx)) < 0.02
            steps.append(("close (X)", gone or clean or args.dry,
                          "process gone: %s, screen like before: %s" % (gone, clean)))
        for n, ok, why in steps:
            if not ok:
                reasons.append("%s: %s" % (n, why))
        # ---- kill what is left (kill closes the window)
        ps3 = ps_now()
        for k in fresh:
            if k in ps3:
                br.job("command", "/bin/kill %d" % k)
        wait(3)
        br.photo(shot("8-zu"))
        if args.dry:
            continue
        for n, ok, why in steps:
            print("  step %-10s %s  %s" % (n, "OK    " if ok else "FEHLER", why))
        res.append(dict(kind="app", id=i, name=a["name"], status="FEHLER" if reasons else "OK",
                        reasons=reasons, info={"steps": ", ".join("%s=%s" % (n, "ok" if ok else "FEHLER") for n, ok, _ in steps)},
                        scope="DELL" if reasons else "-", known=a.get("known", "")))
        print("%-10s %s %s" % (i, res[-1]["status"], "; ".join(reasons)[:160]), flush=True)
        fails_in_row = fails_in_row + 1 if reasons else 0
        if fails_in_row >= 4:
            print("ABORT: 4 apps in a row failed -- the machine is probably hung (see Not-Aus in the doc)")
            break
    if args.dry:
        print("dry run: %d jobs planned" % len(br.log))
        return 0
    write_protocol(out, res, dict(mode="echt", device=args.device, res="%dx%d" % (W, H), steps=len(res)))
    return 0 if all(r["status"] != "FEHLER" for r in res) else 1


# ---------------------------------------------------------------- smoke mode (bridge, READ-ONLY)
# Only reads: no input, no write, no reboot. Safe on a machine that is installing or in use.
# Each check is one line `OK|FAIL <name>: <why>`; the photo is archived next to the protocol.
SMOKE_LOG_WORDS = ("panic", "fault", "refused", "failed")
SMOKE_DAEMONS = ("jarvisd", "taskbar", "starter", "desktop")


def run_smoke(args):
    from concurrent.futures import ThreadPoolExecutor
    out = os.path.abspath(args.outdir)
    os.makedirs(os.path.join(out, "fotos"), exist_ok=True)
    br = Bruecke(args.device, dry=args.dry)
    t0 = time.time()
    up, why = br.online()
    print("device check: %s (%s)" % ("ONLINE" if up else "OFFLINE", why[:120]))
    if not up and not args.dry:
        print("ABORT: the Dell is not online -- nothing was sent.")
        return 3
    res = []

    def check(name, ok, why):
        res.append((name, ok, why))
        print("%-5s %s: %s" % ("OK" if ok else "FAIL", name, why), flush=True)

    def cmd(c):
        st, status, body = br.job("command", c, timeout=args.timeout)
        txt = body.decode("latin1") if isinstance(body, bytes) else str(body)
        return st, txt

    cmds = ["/bin/uname -a", "/bin/cat /system/FASSUNG", "/bin/df", "/bin/ps"] + ["/bin/grep %s /proc/klog" % w for w in SMOKE_LOG_WORDS]
    # independent reads in parallel (the bridge answers each job on its own)
    with ThreadPoolExecutor(max_workers=4) as ex:
        got = dict(zip(cmds, ex.map(cmd, cmds)))
    for c in cmds[:2]:
        st, txt = got[c]
        check(c.split()[-1] if "cat" in c else "uname", st == 200 and "ende 0" in txt, txt.replace("\n", " | ")[:100])
    st, txt = got["/bin/df"]
    m = re.search(r"total=(\d+) free=(\d+).*size=(\d+)", txt, re.S)
    if m:
        tot, fre, bs = (int(x) for x in m.groups())
        check("df", fre * bs >= 20 * 1024 * 1024, "root %.0f MiB, free %.1f MiB (OTA needs ~20 MB for the live feed: sum + largest package + slack; < 20 MiB = stick RAM image)" % (tot * bs / 1048576, fre * bs / 1048576))
    else:
        check("df", False, "no df answer: " + txt[:80])
    st, txt = got["/bin/ps"]
    names = set(r.split()[-1] for r in txt.splitlines() if re.match(r"\s*\d+\s", r))
    miss = [d for d in SMOKE_DAEMONS if d not in names]
    check("session", True, "LOCKED (lock/login runs: `echt` would refuse)" if screen_locked(txt) else "desktop (no lock screen)")
    check("daemons", st == 200 and not miss, "missing: %s" % ", ".join(miss) if miss else "all of %s run" % ", ".join(SMOKE_DAEMONS))
    for w in SMOKE_LOG_WORDS:
        st, txt = got["/bin/grep %s /proc/klog" % w]
        hits = [z for z in txt.splitlines() if re.search(r"^\[\s*\d+\]", z)]
        hits = crash_lines("\n".join(hits)) if hits else []
        check("klog '%s'" % w, st == 200 and not hits, ("%d line(s), first: %s" % (len(hits), hits[0])) if hits else "none")
    shot = os.path.join(out, "fotos", "smoke.png")
    ok = br.photo(shot)
    if ok and not args.dry:
        try:
            a = load_png(shot)
            check("photo", distinct_colours(a) > 50, "%dx%d, %d colours" % (a.shape[1], a.shape[0], distinct_colours(a)))
        except Exception as e:
            check("photo", False, "unreadable PNG: %s" % e)
    else:
        check("photo", args.dry, "no photo (permit `screenshot = yes`?)")
    bad = [r for r in res if not r[1]]
    with open(os.path.join(out, "protokoll.md"), "w") as f:
        f.write("# Dell smoke (%s, %.0f s)\n\n- result: **%d OK / %d FAIL**\n\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), time.time() - t0, len(res) - len(bad), len(bad)))
        f.write("\n".join("- %s **%s**: %s" % ("OK" if o else "FAIL", n, w) for n, o, w in res) + "\n")
    print("smoke: %d OK / %d FAIL in %.0f s -> %s" % (len(res) - len(bad), len(bad), time.time() - t0, out))
    return 1 if bad else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mode", choices=["vm", "echt", "smoke", "list", "eval"])
    ap.add_argument("outdir", nargs="?", default="")
    ap.add_argument("--res", default="3440x1440")
    ap.add_argument("--accel", default="kvm")
    ap.add_argument("--apps", default="")
    ap.add_argument("--device", default="osum-a4206b26eb96")
    ap.add_argument("--dry", action="store_true")
    ap.add_argument("--timeout", type=int, default=90, help="smoke: seconds to wait per bridge job")
    ap.add_argument("--keep-ppm", dest="keep_ppm", action="store_true", help="keep the raw screenshots (15 MB each)")
    ap.add_argument("--runner", default="", help="eval: an existing eh6 output directory")
    args = ap.parse_args()
    if args.mode == "list":
        for a in APPS:
            print("%-10s %-28s term=%-10s bin=%s" % (a["id"], a["name"], a["term"], a["bin"]))
        print("not started: " + ", ".join(NOT_STARTED))
        return 0
    if not args.outdir:
        ap.error("outdir needed")
    if args.mode == "vm":
        return run_vm(args)
    if args.mode == "eval":
        sel = [a for a in APPS if not args.apps or a["id"] in args.apps.split(",")]
        return evaluate_vm(args.runner, os.path.abspath(args.outdir), sel, args)
    if args.mode == "smoke":
        return run_smoke(args)
    return run_echt(args)


if __name__ == "__main__":
    sys.exit(main())
