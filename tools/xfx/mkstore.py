#!/usr/bin/env python3
import argparse
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "linuxapps"))
sys.path.insert(0, os.path.join(HERE, "..", "lib"))
import opkpfad
import packsplit

META = {
    "name": "firefox",
    "title": "Firefox",
    "summary": "Web browser",
    "category": "Internet",
    "icon": "firefox",
}

RECIPE = """name=firefox
fassung={version}
titel=Firefox
info=Web browser
keys=firefox,browser,web,internet
handle=konsole
datei=start {start}
datei=xfx.manifest {manifest}
datei=user.js {userjs}
datei=store.meta {meta}
"""


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def collect_parts(pack_dir, out_dir, limit):
    prebuilt = os.path.join(pack_dir, "parts")
    tar_path = os.path.join(pack_dir, "firefox.tar")
    if os.path.isfile(os.path.join(prebuilt, "firefox.tar.part000")):
        names = sorted(n for n in os.listdir(prebuilt) if n.startswith("firefox.tar.part"))
        for name in names:
            shutil.copy(os.path.join(prebuilt, name), os.path.join(out_dir, name))
        return names
    packsplit.split(tar_path, out_dir, limit)
    return sorted(n for n in os.listdir(out_dir) if n.startswith("firefox.tar.part"))


def write_manifest(path, pack_dir, out_dir, part_names):
    tar_path = os.path.join(pack_dir, "firefox.tar")
    lines = ["tar %d %s" % (os.path.getsize(tar_path), sha256_file(tar_path))]
    for index, name in enumerate(part_names):
        part = os.path.join(out_dir, name)
        lines.append("part %03d %d %s" % (index, os.path.getsize(part), sha256_file(part)))
    with open(path, "w") as handle:
        handle.write("\n".join(lines) + "\n")


def write_meta(path, version):
    fields = dict(META)
    fields["version"] = version
    with open(path, "w") as handle:
        for key in ("name", "title", "summary", "category", "icon", "version"):
            handle.write("%s=%s\n" % (key, fields[key]))


def run(cmd):
    subprocess.run(cmd, check=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pack", required=True)
    parser.add_argument("--xfx-elf", required=True)
    parser.add_argument("--user-js", required=True)
    parser.add_argument("--key", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--version", default="1.0.0")
    parser.add_argument("--limit", type=int, default=packsplit.DEFAULT_LIMIT)
    args = parser.parse_args()
    args.xfx_elf = os.path.abspath(args.xfx_elf)
    args.user_js = os.path.abspath(args.user_js)
    opk = opkpfad.pfad()
    os.makedirs(args.out, exist_ok=True)
    work = tempfile.mkdtemp(prefix="mkstore.")
    try:
        part_names = collect_parts(args.pack, args.out, args.limit)
        manifest = os.path.join(work, "xfx.manifest")
        meta = os.path.join(work, "store.meta")
        recipe = os.path.join(work, "firefox.rezept")
        write_manifest(manifest, args.pack, args.out, part_names)
        write_meta(meta, args.version)
        with open(recipe, "w") as handle:
            handle.write(RECIPE.format(version=args.version, start=args.xfx_elf,
                                       manifest=manifest, userjs=args.user_js, meta=meta))
        package = os.path.join(args.out, "firefox-%s.opk" % args.version.split(".")[0])
        run([sys.executable, "-I", opk, "bauen", recipe, "-o", package])
        shutil.copy(meta, os.path.join(args.out, "store.meta"))
        run([sys.executable, "-I", opk, "quelle", args.out, "--schluessel", args.key])
        packages = sorted(os.path.join(args.out, n) for n in os.listdir(args.out) if n.endswith(".opk"))
        run([sys.executable, "-I", os.path.join(HERE, "..", "update", "signpak.py"), args.key] + packages
            + [os.path.join(args.out, "store.meta")])
        print("mkstore: %d parts, package %s" % (len(part_names), os.path.basename(package)))
    finally:
        shutil.rmtree(work, ignore_errors=True)


main()
