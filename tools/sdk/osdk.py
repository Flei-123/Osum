#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import brand
import migrate
from manifest import PERMS, csv, short_of, lint, normalize, page

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TEMPLATE = os.path.join(HERE, "template")

SDK_MODULES = ["ulib", "actwire", "rpc", "actcli", "socsdk"]


def info_and_project(path):
    info = os.path.join(path, "INFO") if os.path.isdir(path) else path
    project = path if os.path.isdir(path) else os.path.dirname(os.path.abspath(path))
    return info, project


def cmd_check(args):
    info, proj = info_and_project(args.path)
    rep, f = lint(info, proj, strict=args.strict, system=args.system)
    for w in rep.warnings:
        print("warning: " + w)
    for e in rep.errors:
        print("error: " + e)
    if rep.errors or (args.strict and rep.warnings):
        print("osdk: %s refused (%d error(s), %d warning(s))" % (info, len(rep.errors), len(rep.warnings)))
        return 1
    print("osdk: %s ok (id %s, version %s, %d warning(s))" % (info, f.get("id"), f.get("version"), len(rep.warnings)))
    return 0


def cmd_manifest(args):
    info, proj = info_and_project(args.path)
    rep, f = lint(info, proj, system=args.system)
    if rep.errors:
        print("\n".join("error: " + e for e in rep.errors))
        return 1
    m = normalize(f)
    if args.format == "page":
        if "web" not in m:
            print("osdk: outputs has no web")
            return 1
        sys.stdout.write(page(m))
        return 0
    print(json.dumps(m, indent=1, sort_keys=True))
    return 0


def cmd_migrate(args):
    changed = 0
    for path in args.paths:
        info, _ = info_and_project(path)
        old = open(info, encoding="utf-8").read()
        new = migrate.migrate_text(old, os.path.basename(os.path.dirname(os.path.abspath(info))), args.kind)
        if new != old:
            changed += 1
            print("osdk: %s would change" % info if not args.write else "osdk: %s migrated" % info)
            if args.write:
                open(info, "w", encoding="utf-8").write(new)
    print("osdk: %d of %d INFO file(s) %s" % (changed, len(args.paths), "migrated" if args.write else "need migration"))
    return 0


def lit(m):
    name, text = m.group(1), m.group(2)
    n = len(text.encode()) + 1
    return 'var %s: [u8; %d] = "%s\\0"' % (name, n, text)


def slit(m):
    name, text = m.group(1), m.group(2)
    return 'static mut %s: [u8; %d] = "%s\\0"' % (name, len(text.encode()) + 1, text)


def expand(text, subst):
    for k, v in subst.items():
        text = text.replace("{{%s}}" % k, v)
    text = re.sub(r"\{\{SLIT:([a-z_0-9]+):(.*?)\}\}", slit, text)
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
    sub = {"PRODUCT": brand.PRODUKT, "ID": app_id, "SHORT": short, "NAME": name, "PERM": perm, "EXTRA": extra,
           "KIND": args.kind, "OUTPUTS": args.outputs, "AUTHOR": args.author}
    os.makedirs(os.path.join(d, "src"))
    for src, dst in (("INFO.in", "INFO"), ("README.md.in", "README.md"),
                     ("main-%s.fi.in" % args.kind, os.path.join("src", "main.fi"))):
        t = open(os.path.join(TEMPLATE, src)).read()
        open(os.path.join(d, dst), "w").write(expand(t, sub))
    shutil.copyfile(os.path.join(TEMPLATE, "symbol.txt"), os.path.join(d, "symbol.txt"))
    if "web" in csv(args.outputs):
        shutil.copyfile(os.path.join(TEMPLATE, "symbol.svg"), os.path.join(d, "symbol.svg"))
    rep, _ = lint(os.path.join(d, "INFO"), d)
    if rep.errors:
        print("osdk: the template produced a refused manifest: " + "; ".join(rep.errors))
        return 1
    print("osdk: created %s (%s, kind %s)" % (d, app_id, args.kind))
    return 0


def run(cmd, cwd=None, env=None):
    r = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True)
    return r.returncode, (r.stdout + r.stderr)


def import_closure(roots):
    seen, todo = [], list(roots)
    while todo:
        m = todo.pop()
        if m in seen:
            continue
        f = os.path.join(ROOT, "kernel", "user", m + ".fi")
        if not os.path.isfile(f):
            continue
        seen.append(m)
        for imp in re.findall(rb"^import ([a-z_0-9.]+)", open(f, "rb").read(), re.M):
            todo.append(imp.decode())
    return sorted(seen)


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
        gui = bool(re.search(r"^profile app\b", open(main_src).read(), re.M))
        mods = import_closure(["ulib", "wlib", "fuiapp", "fuiscene"] if gui else SDK_MODULES)
        for m in mods:
            shutil.copyfile(os.path.join(ROOT, "kernel", "user", m + ".fi"), os.path.join(work, m + ".fi"))
        for n in os.listdir(os.path.join(proj, "src")):
            if n.endswith(".fi"):
                if n[:-3] in mods:
                    print("osdk: src/%s shadows an SDK module" % n)
                    return 1
                shutil.copyfile(os.path.join(proj, "src", n), os.path.join(work, n))
        env = dict(os.environ, FIRNLIB=os.environ.get("FIRNLIB", os.path.join(ROOT, "lib")))
        gcs, optl = [], []
        if gui:
            env["FIRN_FUNCTION_SECTIONS"] = "1"
            gcs = ["--gc-sections"]
            optl = ["--opt-level=release-fast", "--no-pass=inline"]
        crt = []
        if not gui:
            rc, o = run(["as", "--64", "-o", os.path.join(work, "crt.o"), os.path.join(ROOT, "kernel", "user", "crt.s")])
            if rc:
                print(o)
                return 1
            crt = [os.path.join(work, "crt.o")]
        rc, o = run([firnc] + (["--profile=app"] + optl if gui else []) +
                    ["-c", os.path.join(work, "main.fi"), "-o", os.path.join(work, "main.o")], env=env)
        if rc:
            print("osdk: compile failed\n" + o)
            return 1
        elf = os.path.join(work, "app.elf")
        rc, o = run(["ld"] + gcs + ["-T", os.path.join(ROOT, "kernel", "user", "user.ld"), "--defsym=USER_ENTRY=_F0.u_start",
                     "-o", elf] + crt + [os.path.join(work, "main.o")])
        if rc:
            print("osdk: link failed\n" + o)
            return 1
        run(["strip", "--strip-all", elf])
        bundle = os.path.join(out, "apps", short + ".osp")
        os.makedirs(os.path.join(bundle, "data"), exist_ok=True)
        os.makedirs(os.path.join(out, "bin"), exist_ok=True)
        shutil.copyfile(elf, os.path.join(out, "bin", short + ".elf"))
        info = open(os.path.join(proj, "INFO")).read().rstrip("\n")
        want_net = "real" if "net" in csv(f.get("perm", "")) else "none"
        if "net" not in f:
            info = re.sub(r"^((?:revision|fassung)=.*)$", r"\1\nnet=" + want_net, info, count=1, flags=re.M)
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
    for k, (level, call, text) in PERMS.items():
        print("%-16s %-9s %-15s %s" % (k, level, call or "-", text))
    return 0


def main(argv):
    ap = argparse.ArgumentParser(prog="osdk.py")
    sp = ap.add_subparsers(dest="cmd", required=True)
    a = sp.add_parser("new")
    a.add_argument("id")
    a.add_argument("--kind", choices=["app", "service", "gui"], default="app")
    a.add_argument("--dir")
    a.add_argument("--name")
    a.add_argument("--perm")
    a.add_argument("--outputs", default="native")
    a.add_argument("--author", default="unknown")
    a.set_defaults(fn=cmd_new)
    a = sp.add_parser("check")
    a.add_argument("path")
    a.add_argument("--strict", action="store_true")
    a.add_argument("--system", action="store_true")
    a.set_defaults(fn=cmd_check)
    a = sp.add_parser("manifest")
    a.add_argument("path")
    a.add_argument("--format", choices=["json", "page"], default="json")
    a.add_argument("--system", action="store_true")
    a.set_defaults(fn=cmd_manifest)
    a = sp.add_parser("migrate")
    a.add_argument("paths", nargs="+")
    a.add_argument("--kind", choices=["app", "gui"], default="gui")
    a.add_argument("--write", action="store_true")
    a.set_defaults(fn=cmd_migrate)
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
