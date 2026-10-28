#!/usr/bin/env python3
import gzip
import hashlib
import os
import sys
import tarfile

SKIP_PREFIXES = ("/bin/", "/usr/bin/", "/usr/sbin/")
FIXED_MTIME = 1760000000


def parse_spec(path):
    files, links = [], []
    for raw in open(path, encoding="utf-8").read().splitlines():
        line = raw.strip()
        if not line or line.startswith(SKIP_PREFIXES):
            continue
        head = line.split("=", 1)[0]
        if "->" in head:
            dest, target = line.split("->", 1)
            links.append((dest, target))
        elif "=" in line:
            dest, rest = line.split("=", 1)
            host, _, mode = rest.partition("@")
            if os.path.isfile(host):
                files.append((dest, host, int(mode or "644", 8)))
    return files, links


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_tar(files, out_path):
    with tarfile.open(out_path, "w", format=tarfile.USTAR_FORMAT) as tar:
        for dest, host, mode in files:
            info = tar.gettarinfo(host, arcname=dest.lstrip("/"))
            info.mode, info.mtime = mode, FIXED_MTIME
            info.uid = info.gid = 0
            info.uname = info.gname = ""
            with open(host, "rb") as handle:
                tar.addfile(info, handle)


def write_gzip(src, dst):
    with open(src, "rb") as fin, open(dst, "wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, compresslevel=9, mtime=0) as fout:
            for chunk in iter(lambda: fin.read(1 << 20), b""):
                fout.write(chunk)


def write_base_spec(full_spec, packed, out_path):
    kept = []
    for raw in open(full_spec, encoding="utf-8").read().splitlines():
        line = raw.strip()
        if not line:
            continue
        head = line.split("=", 1)[0]
        dest = head.split("->", 1)[0]
        if dest not in packed or line.endswith("/@755"):
            kept.append(line)
    with open(out_path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(kept) + "\n")


def parse_extras(argv):
    extras = []
    for idx, arg in enumerate(argv):
        if arg == "--extra":
            dest, rest = argv[idx + 1].split("=", 1)
            host, _, mode = rest.partition("@")
            extras.append((dest, host, int(mode or "644", 8)))
    return extras


def main(argv):
    spec, out_dir = argv[1], argv[2]
    os.makedirs(out_dir, exist_ok=True)
    files, links = parse_spec(spec)
    files.extend(parse_extras(argv))
    if len(argv) >= 5 and argv[3] == "--base-spec":
        packed = {dest for dest, _, _ in files} | {dest for dest, _ in links}
        write_base_spec(argv[4], packed, os.path.join(out_dir, "base.spec"))
    tar_path = os.path.join(out_dir, "firefox.tar")
    gz_path = tar_path + ".gz"
    write_tar(files, tar_path)
    write_gzip(tar_path, gz_path)
    with open(os.path.join(out_dir, "firefox.links"), "w", encoding="utf-8") as handle:
        handle.writelines("%s %s\n" % pair for pair in links)
    manifest = [
        "files %d" % len(files),
        "links %d" % len(links),
        "tar %d %s" % (os.path.getsize(tar_path), sha256_file(tar_path)),
        "gz %d %s" % (os.path.getsize(gz_path), sha256_file(gz_path)),
    ]
    with open(os.path.join(out_dir, "firefox.manifest"), "w", encoding="utf-8") as handle:
        handle.write("\n".join(manifest) + "\n")
    print("\n".join(manifest))


if __name__ == "__main__":
    main(sys.argv)
