#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/sdk/osdk.py -- the OrientOS app SDK on the host (docs/SDK.md).

    osdk.py new <id> [--kind app|service] [--dir DIR] [--name NAME] [--perm a,b]
    osdk.py check <project-dir | INFO file> [--strict]
    osdk.py build <project-dir> --out DIR
    osdk.py perms                       the permission catalogue

`new` makes a project from tools/sdk/template (INFO = manifest v2,
src/main.fi, symbol.txt, README.md). `check` lints the manifest.
`build` checks, compiles src/*.fi with the SDK modules next to it,
links, and writes a bundle tree + the mkfs lines:

    DIR/bin/<short>.elf
    DIR/apps/<short>.osp/{INFO,symbol.txt,data/}
    DIR/mkfs.lines          one mkfs.py argument per line

The bundle does NOT carry the SYSTEM marker (tools/k15/bundle.py adds it
for images' own apps): a third-party app is labelled by the kernel
(docs/ACTION-BUS.md 5.2) and must not act as the user.
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TEMPLATE = os.path.join(HERE, "template")

# kernel/user modules a project may import (the SDK surface, docs/SDK.md)
SDK_MODULES = ["ulib", "actwire", "rpc"]

# the launcher keys (kernel/user/appdir.fi) + the v2 keys
KEYS_V1 = ["name", "info", "exec", "icon", "keys", "fassung", "net"]
KEYS_V2 = ["manifest", "id", "version", "author", "license", "min_os", "perm",
           "service", "actions", "opens", "needs"]
REQUIRED = ["name", "info", "fassung", "manifest", "id", "version"]

# permission -> (enforced by the system today?, what it means)
PERMS = {
    "net": (True, "network access; build writes net=real, else net=none (netview, docs/NETVIEW.md)"),
    "notify": (False, "post notifications (bus NOTIPOST)"),
    "clipboard.read": (False, "read the clipboard (bus CLIPGET)"),
    "clipboard.write": (False, "write the clipboard (bus CLIPSET)"),
    "fs.home": (False, "read/write the user's home"),
    "audio.play": (False, "play sound"),
}

SYSTEM_APPS_DIR = os.path.join(ROOT, "assets", "apps")


class Report:
    def __init__(self):
        self.errors = []
        self.warnings = []

    def err(self, line, msg):
        self.errors.append("line %d: %s" % (line, msg) if line else msg)

    def warn(self, line, msg):
        self.warnings.append("line %d: %s" % (line, msg) if line else msg)


def parse_info(text, rep):
    """key=value lines; '#' comments; returns {key: (value, lineno)}."""
    out = {}
    for no, raw in enumerate(text.split("\n"), 1):
        line = raw.rstrip("\r")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if "=" not in line:
            rep.err(no, "not a key=value line: %r" % line[:40])
            continue
        k, v = line.split("=", 1)
        k = k.strip()
        if k in out:
            rep.err(no, "duplicate key '%s' (first at line %d)" % (k, out[k][1]))
            continue
        out[k] = (v.strip(), no)
    return out


def short_of(app_id):
    return app_id.rsplit(".", 1)[-1]


def system_names():
    try:
        return {n[:-4] for n in os.listdir(SYSTEM_APPS_DIR) if n.endswith(".osp")}
    except OSError:
        return set()


def csv(v):
    return [x.strip() for x in v.split(",") if x.strip()]


def lint(info_path, project=None):
    """Manifest v2 lint. Returns (Report, fields)."""
    rep = Report()
    try:
        data = open(info_path, "rb").read()
    except OSError as e:
        rep.err(0, "cannot read %s: %s" % (info_path, e))
        return rep, {}
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        rep.err(0, "INFO is not UTF-8")
        return rep, {}
    f = parse_info(text, rep)
    known = set(KEYS_V1 + KEYS_V2)
    for k, (v, no) in f.items():
        if k not in known and not k.startswith("x-"):
            rep.err(no, "unknown key '%s' (custom keys start with x-)" % k)
    for k in REQUIRED:
        if k not in f:
            rep.err(0, "missing required key '%s'" % k)
    if "manifest" in f and f["manifest"][0] != "2":
        rep.err(f["manifest"][1], "manifest=%s: this tool reads manifest=2" % f["manifest"][0])
    # launcher keys must stand within the first 1023 octets (appdir / bundle.py)
    last = -1
    pos = 0
    for raw in data.split(b"\n"):
        for key in (b"name=", b"info=", b"keys=", b"fassung=", b"net=", b"exec=", b"icon="):
            if raw.startswith(key):
                last = max(last, pos + len(raw))
        pos += len(raw) + 1
    if last >= 1023:
        rep.err(0, "launcher keys end at octet %d; appdir reads 1023 -- move comments behind them" % last)
    short = None
    if "id" in f:
        v, no = f["id"]
        if not re.fullmatch(r"[a-z][a-z0-9]*(\.[a-z][a-z0-9-]*){1,5}", v):
            rep.err(no, "id '%s': reverse-DNS, lower case, 2-6 parts (org.example.app)" % v)
        else:
            short = short_of(v)
            if not re.fullmatch(r"[a-z][a-z0-9]{0,15}", short):
                rep.err(no, "last part of id ('%s') is the bundle name: [a-z][a-z0-9]{0,15}" % short)
                short = None
            elif short in system_names():
                rep.err(no, "bundle name '%s' collides with a system app" % short)
    if "version" in f and not re.fullmatch(r"\d{1,4}\.\d{1,4}\.\d{1,4}", f["version"][0]):
        rep.err(f["version"][1], "version '%s': MAJOR.MINOR.PATCH" % f["version"][0])
    if "name" in f:
        n = f["name"][0]
        if not (1 <= len(n) <= 31):
            rep.err(f["name"][1], "name: 1..31 characters")
    if "info" in f and not (1 <= len(f["info"][0]) <= 80):
        rep.err(f["info"][1], "info: 1..80 characters")
    if "fassung" in f and not re.fullmatch(r"\d{1,6}", f["fassung"][0]):
        rep.err(f["fassung"][1], "fassung: a whole number (raise it with every release)")
    if "min_os" in f and not re.fullmatch(r"\d{1,6}(\.\d{1,6}){0,2}", f["min_os"][0]):
        rep.err(f["min_os"][1], "min_os: 1-3 dotted numbers")
    elif "min_os" in f:
        rep.warn(f["min_os"][1], "min_os is declared only: the OS has no version number to compare yet")
    if "net" in f:
        if f["net"][0] not in ("real", "filtered", "faked", "none"):
            rep.err(f["net"][1], "net: real|filtered|faked|none")
        if "perm" in f and ("net" in csv(f["perm"][0])) != (f["net"][0] != "none"):
            rep.err(f["net"][1], "net=%s contradicts perm" % f["net"][0])
    if "perm" in f:
        seen = set()
        for p in csv(f["perm"][0]):
            if p not in PERMS:
                rep.err(f["perm"][1], "unknown permission '%s' (osdk.py perms)" % p)
            elif p in seen:
                rep.err(f["perm"][1], "permission '%s' twice" % p)
            elif not PERMS[p][0]:
                rep.warn(f["perm"][1], "perm '%s' is declared only: the system does not enforce it yet" % p)
            seen.add(p)
    if "service" in f:
        for s in csv(f["service"][0]):
            if len(s) > 16:
                rep.err(f["service"][1], "service '%s': a bus name has at most 16 octets" % s)
            elif not re.fullmatch(r"[a-z][a-z0-9.]*", s):
                rep.err(f["service"][1], "service '%s': [a-z][a-z0-9.]*" % s)
            elif short and s != short and not s.startswith(short + "."):
                rep.err(f["service"][1], "service '%s' is outside the app's namespace '%s'" % (s, short))
    if "opens" in f:
        for e in csv(f["opens"][0]):
            if not re.fullmatch(r"[a-z0-9]{1,8}", e):
                rep.err(f["opens"][1], "opens '%s': a file extension, 1..8 of [a-z0-9]" % e)
    if "needs" in f:
        for n in csv(f["needs"][0]):
            if not re.fullmatch(r"(os|app:[a-z][a-z0-9.-]*)>=\d{1,6}(\.\d{1,6}){0,2}", n):
                rep.err(f["needs"][1], "needs '%s': os>=N or app:<id>>=N" % n)
    if "actions" in f:
        rel = f["actions"][0]
        if project:
            p = os.path.join(project, rel)
            if ".." in rel or os.path.isabs(rel):
                rep.err(f["actions"][1], "actions: a path inside the project")
            elif not os.path.isfile(p):
                rep.err(f["actions"][1], "actions file '%s' missing" % rel)
            else:
                r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "actionbus", "manifest.py"),
                                    "check", p], capture_output=True, text=True)
                if r.returncode != 0:
                    rep.err(f["actions"][1], "actions file refused: " + (r.stdout + r.stderr).strip().split("\n")[-1])
                elif short:
                    m = re.search(r"^app\s+(\S+)", open(p).read(), re.M)
                    if not m or m.group(1) != short:
                        rep.err(f["actions"][1], "ACTIONS 'app' must be '%s'" % short)
    return rep, {k: v[0] for k, v in f.items()}


def cmd_check(args):
    p = args.path
    info = os.path.join(p, "INFO") if os.path.isdir(p) else p
    proj = p if os.path.isdir(p) else os.path.dirname(os.path.abspath(p))
    rep, f = lint(info, proj)
    for w in rep.warnings:
        print("warning: " + w)
    for e in rep.errors:
        print("error: " + e)
    if rep.errors or (args.strict and rep.warnings):
        print("osdk: %s refused (%d error(s), %d warning(s))" % (info, len(rep.errors), len(rep.warnings)))
        return 1
    print("osdk: %s ok (id %s, version %s, %d warning(s))" % (info, f.get("id"), f.get("version"), len(rep.warnings)))
    return 0


def lit(m):
    name, text = m.group(1), m.group(2)
    n = len(text.encode()) + 1
    return 'var %s: [u8; %d] = "%s\\0"' % (name, n, text)


def expand(text, subst):
    # a literal may contain a placeholder: expand those first
    for k, v in subst.items():
        text = text.replace("{{%s}}" % k, v)
    return re.sub(r"\{\{LIT:([a-z_0-9]+):(.*?)\}\}", lit, text)


def cmd_new(args):
    app_id = args.id
    if not re.fullmatch(r"[a-z][a-z0-9]*(\.[a-z][a-z0-9-]*){1,5}", app_id):
        print("osdk: id must look like org.example.app")
        return 1
    short = short_of(app_id)
    name = args.name or short.capitalize()
    d = args.dir or short
    if os.path.exists(d):
        print("osdk: %s exists" % d)
        return 1
    perm = args.perm or ""
    extra = ""
    if args.kind == "service":
        extra = "service=%s" % short
    sub = {"ID": app_id, "SHORT": short, "NAME": name, "PERM": perm, "EXTRA": extra}
    os.makedirs(os.path.join(d, "src"))
    for src, dst in (("INFO.in", "INFO"), ("README.md.in", "README.md"),
                     ("main-%s.fi.in" % args.kind, os.path.join("src", "main.fi"))):
        t = open(os.path.join(TEMPLATE, src)).read()
        open(os.path.join(d, dst), "w").write(expand(t, sub))
    shutil.copyfile(os.path.join(TEMPLATE, "symbol.txt"), os.path.join(d, "symbol.txt"))
    rep, _ = lint(os.path.join(d, "INFO"), d)
    if rep.errors:
        print("osdk: the template produced a refused manifest: " + "; ".join(rep.errors))
        return 1
    print("osdk: created %s (%s, kind %s)" % (d, app_id, args.kind))
    return 0


def run(cmd, cwd=None, env=None):
    r = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True)
    return r.returncode, (r.stdout + r.stderr)


def cmd_build(args):
    proj = os.path.abspath(args.path)
    rep, f = lint(os.path.join(proj, "INFO"), proj)
    for w in rep.warnings:
        print("warning: " + w)
    if rep.errors:
        for e in rep.errors:
            print("error: " + e)
        print("osdk: build stopped, the manifest is refused")
        return 1
    short = short_of(f["id"])
    firnc = os.path.join(ROOT, "vendor", "firn", "bin", "firnc")
    if not os.access(firnc, os.X_OK):
        print("osdk: %s missing (bash vendor/firn/fetch-firnc.sh)" % firnc)
        return 1
    main_src = os.path.join(proj, "src", "main.fi")
    if not os.path.isfile(main_src):
        print("osdk: src/main.fi missing")
        return 1
    out = os.path.abspath(args.out)
    work = tempfile.mkdtemp(prefix="osdk-")
    try:
        # SDK modules + project sources side by side: a program finds its
        # `import ulib` only next to itself (tools/sync/build.sh)
        for m in SDK_MODULES:
            shutil.copyfile(os.path.join(ROOT, "kernel", "user", m + ".fi"), os.path.join(work, m + ".fi"))
        for n in os.listdir(os.path.join(proj, "src")):
            if n.endswith(".fi"):
                if n[:-3] in SDK_MODULES:
                    print("osdk: src/%s shadows an SDK module" % n)
                    return 1
                shutil.copyfile(os.path.join(proj, "src", n), os.path.join(work, n))
        env = dict(os.environ, FIRNLIB=os.environ.get("FIRNLIB", os.path.join(ROOT, "lib")))
        rc, o = run(["as", "--64", "-o", os.path.join(work, "crt.o"), os.path.join(ROOT, "kernel", "user", "crt.s")])
        if rc:
            print(o)
            return 1
        rc, o = run([firnc, "-c", os.path.join(work, "main.fi"), "-o", os.path.join(work, "main.o")], env=env)
        if rc:
            print("osdk: compile failed\n" + o)
            return 1
        elf = os.path.join(work, "app.elf")
        rc, o = run(["ld", "-T", os.path.join(ROOT, "kernel", "user", "user.ld"), "--defsym=USER_ENTRY=_F0.u_start",
                     "-o", elf, os.path.join(work, "crt.o"), os.path.join(work, "main.o")])
        if rc:
            print("osdk: link failed\n" + o)
            return 1
        run(["strip", "--strip-all", elf])
        bundle = os.path.join(out, "apps", short + ".osp")
        os.makedirs(os.path.join(bundle, "data"), exist_ok=True)
        os.makedirs(os.path.join(out, "bin"), exist_ok=True)
        shutil.copyfile(elf, os.path.join(out, "bin", short + ".elf"))
        # INFO: the launcher keys stay; net= is derived from perm
        info = open(os.path.join(proj, "INFO")).read().rstrip("\n")
        want_net = "real" if "net" in csv(f.get("perm", "")) else "none"
        if "net" not in f:
            info = re.sub(r"^(fassung=.*)$", r"\1\nnet=" + want_net, info, count=1, flags=re.M)
        open(os.path.join(bundle, "INFO"), "w").write(info + "\n")
        open(os.path.join(bundle, "data", "README"), "w").write(
            "%s %s -- built with osdk\n" % (f["id"], f["version"]))
        sym_src = os.path.join(proj, "symbol.txt")
        sym = os.path.join(bundle, "symbol")
        rc, o = run([sys.executable, os.path.join(ROOT, "tools", "k15", "icon.py"), sym_src, sym])
        if rc:
            print("osdk: symbol.txt refused\n" + o)
            return 1
        shutil.copyfile(sym_src, os.path.join(bundle, "symbol.txt"))
        tgt = "/apps/%s.osp" % short
        lines = ["/apps/", tgt + "/", "%s/INFO=%s" % (tgt, os.path.join(bundle, "INFO")),
                 "%s/symbol=%s" % (tgt, sym), tgt + "/data/",
                 "%s/data/README=%s" % (tgt, os.path.join(bundle, "data", "README")),
                 "%s/start=%s" % (tgt, os.path.join(out, "bin", short + ".elf"))]
        if "actions" in f:
            lines.append("%s/ACTIONS=%s" % (tgt, os.path.join(proj, f["actions"])))
        open(os.path.join(out, "mkfs.lines"), "w").write("\n".join(lines) + "\n")
        print("osdk: built %s %s -> %s (%d octets), net=%s" % (
            f["id"], f["version"], out, os.path.getsize(os.path.join(out, "bin", short + ".elf")),
            f.get("net", want_net)))
        return 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


def cmd_perms(_):
    for k, (enf, text) in PERMS.items():
        print("%-16s %-10s %s" % (k, "enforced" if enf else "declared", text))
    return 0


def main(argv):
    ap = argparse.ArgumentParser(prog="osdk.py")
    sp = ap.add_subparsers(dest="cmd", required=True)
    a = sp.add_parser("new")
    a.add_argument("id")
    a.add_argument("--kind", choices=["app", "service"], default="app")
    a.add_argument("--dir")
    a.add_argument("--name")
    a.add_argument("--perm")
    a.set_defaults(fn=cmd_new)
    a = sp.add_parser("check")
    a.add_argument("path")
    a.add_argument("--strict", action="store_true")
    a.set_defaults(fn=cmd_check)
    a = sp.add_parser("build")
    a.add_argument("path")
    a.add_argument("--out", required=True)
    a.set_defaults(fn=cmd_build)
    a = sp.add_parser("perms")
    a.set_defaults(fn=cmd_perms)
    args = ap.parse_args(argv[1:])
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
