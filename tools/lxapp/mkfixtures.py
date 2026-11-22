import hashlib
import io
import os
import sys
import tarfile

OUT = sys.argv[1]
STUB = open(os.path.join(OUT, "xfxstub.elf"), "rb").read()


def add_dirs(archive, names):
    for name in names:
        info = tarfile.TarInfo(name)
        info.type = tarfile.DIRTYPE
        info.mode = 0o755
        archive.addfile(info)


def add_file(archive, name, data, mode):
    info = tarfile.TarInfo(name)
    info.size = len(data)
    info.mode = mode
    archive.addfile(info, io.BytesIO(data))


def make_tar(path, dirs, name, data, mode):
    with tarfile.open(path, "w", format=tarfile.USTAR_FORMAT) as archive:
        add_dirs(archive, dirs)
        add_file(archive, name, data, mode)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def write_package(name, tar_path, parts, flip=False):
    raw = open(tar_path, "rb").read()
    digest = sha(raw)
    if flip:
        digest = ("0" if digest[0] != "0" else "1") + digest[1:]
    cuts = [len(raw) * k // parts for k in range(parts + 1)]
    lines = ["tar %d %s" % (len(raw), digest)]
    for k in range(parts):
        chunk = raw[cuts[k]:cuts[k + 1]]
        open(os.path.join(OUT, "%s.part%03d" % (name, k)), "wb").write(chunk)
        lines.append("part %03d %d %s" % (k, len(chunk), sha(chunk)))
    open(os.path.join(OUT, name + ".manifest"), "w").write("\n".join(lines) + "\n")


def write_config(name, text):
    open(os.path.join(OUT, name + ".lx.app"), "w").write(text)


def app(name, flip=False):
    path = os.path.join(OUT, name + ".tar")
    make_tar(path, ["usr", "usr/bin"], "usr/bin/" + name, STUB, 0o755)
    write_package(name, path, 2, flip)
    write_config(name, "exec=%s one two\nproc=%s\ncheck=/usr/bin/%s\nenv=STUB_MARK=yes\n" % (name, name, name))


app("stubapp")
app("badapp", flip=True)
runtime_path = os.path.join(OUT, "linuxrt.tar")
make_tar(runtime_path, ["lib"], "lib/ld-musl-x86_64.so.1", b"musl", 0o755)
write_package("linuxrt", runtime_path, 1)
write_config("linuxrt", "kind=runtime\nproc=linuxrt\ncheck=/lib/ld-musl-x86_64.so.1\n")
open(os.path.join(OUT, "passwd"), "w").write("root:x:0:0:root:/:/bin/sh\njustin:x:1000:1000:Justin:/home/justin:/bin/sh\n")
open(os.path.join(OUT, "group"), "w").write("root:x:0:\njustin:x:1000:\n")
