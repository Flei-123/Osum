#!/usr/bin/env python3
import argparse
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "..", "..", "lib"))
sys.path.insert(0, HERE)
import apkdb
import opkpfad
import packsplit

RUNTIME = "linuxrt"
RUNTIME_CONFIG = "kind=runtime\nproc=linuxrt\ncheck=/lib/ld-musl-x86_64.so.1\n"
BIN_DIR = "/usr/bin"
PROC_NAME_MAX = 8
EXCLUDED = {"apk-tools", "alpine-keys", "alpine-baselayout", "alpine-baselayout-data", "scanelf", "ssl_client", "busybox", "busybox-binsh", "busybox-suid"}
SKIP_PREFIXES = ("var/cache", "var/lib", "lib/apk", "etc/apk", "usr/include", "usr/share/doc", "usr/share/man", "usr/share/info", "usr/share/locale")
REGISTRY = os.path.join(ROOT, "tools", "linuxapps", "store-apps.tsv")
ICON_REGISTRY = os.path.join(ROOT, "tools", "svg", "apps.tsv")
APP_COLUMNS = ("name", "title", "summary", "category", "icon", "keys", "command", "env")


def read_registry(path=REGISTRY):
    apps = []
    for line in open(path, encoding="utf-8"):
        if line.strip() and not line.startswith("#"):
            fields = line.rstrip("\n").split("\t")
            fields += [""] * (len(APP_COLUMNS) - len(fields))
            apps.append(dict(zip(APP_COLUMNS, fields)))
    return apps


def icon_dirs(path=ICON_REGISTRY):
    dirs = {}
    for line in open(path, encoding="utf-8"):
        fields = line.rstrip("\n").split("\t")
        if len(fields) >= 6:
            dirs[fields[0]] = os.path.join(ROOT, fields[5])
    return dirs


def icon_bundle(key):
    bundle = icon_dirs().get(key)
    if bundle is None or not os.path.isdir(bundle):
        raise SystemExit("mkpkgs: icon %s is not in the icon registry" % key)
    return bundle


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def plan(packages, apps):
    closures = {app["name"]: [p for p in apkdb.closure(packages, [app["name"]]) if p not in EXCLUDED] for app in apps}
    users = {}
    for name, members in closures.items():
        for member in members:
            users.setdefault(member, set()).add(name)
    shared = sorted(p for p, who in users.items() if len(who) > 1)
    own = {name: [p for p in members if p not in shared] for name, members in closures.items()}
    return shared, own


def files_of(packages, names, root):
    out = set()
    for name in names:
        for path in packages[name]["files"]:
            full = os.path.join(root, path)
            if not path.startswith(SKIP_PREFIXES) and (os.path.islink(full) or os.path.isfile(full)):
                out.add(path)
    return sorted(out)


def make_tar(root, files, tar_path):
    listing = tar_path + ".list"
    write(listing, "\n".join(files) + "\n")
    subprocess.run(["tar", "-C", root, "--no-recursion", "--numeric-owner", "-cf", tar_path, "-T", listing], check=True)
    os.unlink(listing)


def split_with_manifest(tar_path, out_dir, limit):
    packsplit.split(tar_path, out_dir, limit)
    base = os.path.basename(tar_path)
    parts = sorted(n for n in os.listdir(out_dir) if n.startswith(base + ".part"))
    lines = ["tar %d %s" % (os.path.getsize(tar_path), sha256_file(tar_path))]
    for index, name in enumerate(parts):
        part = os.path.join(out_dir, name)
        lines.append("part %03d %d %s" % (index, os.path.getsize(part), sha256_file(part)))
    return "\n".join(lines) + "\n", len(parts)


def write(path, text):
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


def recipe_text(fields, files, needs):
    lines = ["name=%s" % fields["name"], "version=%s" % fields["version"], "titel=%s" % fields["title"],
             "info=%s" % fields["summary"], "keys=%s" % fields["keys"], "handle=konsole"]
    lines += ["braucht=%s" % need for need in needs]
    lines += ["datei=%s %s" % (name, path) for name, path in files]
    return "\n".join(lines) + "\n"


def build_symbol(bundle, out):
    subprocess.run([sys.executable, "-I", os.path.join(ROOT, "tools", "k15", "mksymbol.py"), bundle, out], check=True)


def meta_text(fields):
    return "".join("%s=%s\n" % (k, fields[k]) for k in ("name", "title", "summary", "category", "icon", "version"))


def app_config(app):
    command = app["command"].split()[0]
    lines = ["exec=%s" % app["command"], "proc=%s" % command[:PROC_NAME_MAX], "check=%s/%s" % (BIN_DIR, command)]
    lines += ["env=%s" % item for item in app["env"].split() if item]
    return "\n".join(lines) + "\n"


def build_package(fields, config, needs, tar_path, args, work, out_dir):
    pkg_work = os.path.join(work, fields["name"])
    os.makedirs(pkg_work)
    manifest, count = split_with_manifest(tar_path, out_dir, args.limit)
    texts = {"lx.manifest": manifest, "store.meta": meta_text(fields), "lx.app": config}
    files = [("start", args.launcher)]
    for name, text in texts.items():
        write(os.path.join(pkg_work, name), text)
        files.append((name, os.path.join(pkg_work, name)))
    symbol = os.path.join(pkg_work, "symbol")
    build_symbol(icon_bundle(fields["icon"]), symbol)
    files.append(("symbol", symbol))
    recipe = os.path.join(pkg_work, "pkg.rezept")
    write(recipe, recipe_text(fields, files, needs))
    package = os.path.join(out_dir, "%s-%s.opk" % (fields["name"], fields["version"].split(".")[0]))
    subprocess.run([sys.executable, "-I", opkpfad.path_2(), "bauen", recipe, "-o", package], check=True)
    shutil.copy(os.path.join(pkg_work, "store.meta"), os.path.join(out_dir, fields["name"] + ".store.meta"))
    return count


def sign(out_dir, key):
    opk = opkpfad.path_2()
    subprocess.run([sys.executable, "-I", opk, "quelle", out_dir, "--schluessel", key], check=True)
    packages = sorted(os.path.join(out_dir, n) for n in os.listdir(out_dir) if n.endswith(".opk"))
    subprocess.run([sys.executable, "-I", os.path.join(ROOT, "tools", "update", "signpak.py"), key] + packages, check=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--launcher", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--key")
    parser.add_argument("--apps")
    parser.add_argument("--version", default="1.0.0")
    parser.add_argument("--limit", type=int, default=packsplit.DEFAULT_LIMIT)
    args = parser.parse_args()
    args.launcher = os.path.abspath(args.launcher)
    apps = read_registry()
    if args.apps:
        apps = [a for a in apps if a["name"] in args.apps.split(",")]
    packages = apkdb.parse(args.root)
    shared, own = plan(packages, apps)
    os.makedirs(args.out, exist_ok=True)
    work = tempfile.mkdtemp(prefix="lxstore.")
    try:
        runtime_tar = os.path.join(work, RUNTIME + ".tar")
        make_tar(args.root, files_of(packages, shared, args.root), runtime_tar)
        runtime = {"name": RUNTIME, "title": "Linux runtime", "summary": "Shared libraries for Linux apps", "keys": "linux,runtime",
                   "category": "System", "icon": "terminal", "version": args.version}
        counts = {RUNTIME: build_package(runtime, RUNTIME_CONFIG, [], runtime_tar, args, work, args.out)}
        for app in apps:
            tar_path = os.path.join(work, app["name"] + ".tar")
            make_tar(args.root, files_of(packages, own[app["name"]], args.root), tar_path)
            counts[app["name"]] = build_package(dict(app, version=args.version), app_config(app), [RUNTIME], tar_path, args, work, args.out)
        if args.key:
            sign(args.out, args.key)
        for name, count in counts.items():
            print("lxstore: %s %d parts" % (name, count))
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
