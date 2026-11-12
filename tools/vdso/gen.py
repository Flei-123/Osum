#!/usr/bin/env python3
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
TARGET = ROOT / "kernel/sched/vdsoimg.fi"
DATA_OFFSET = 0xF00
WORDS_PER_FUNCTION = 24
SHDR_FIELDS_OFFSET = 0x28


def build(workdir):
    obj = workdir / "vdso.o"
    lib = workdir / "vdso.so"
    subprocess.run(["as", "--64", "-o", str(obj), str(HERE / "vdso.S")], check=True)
    subprocess.run([
        "ld", "-shared", "--hash-style=sysv", "-z", "norelro", "-z", "max-page-size=4096",
        "-soname", "linux-vdso.so.1", "-T", str(HERE / "vdso.ld"),
        "--version-script", str(HERE / "vdso.map"), "-o", str(lib), str(obj),
    ], check=True)
    return lib.read_bytes()[:DATA_OFFSET]


def strip_sections(image):
    patched = bytearray(image)
    patched[SHDR_FIELDS_OFFSET:SHDR_FIELDS_OFFSET + 8] = struct.pack("<Q", 0)
    patched[0x3A:0x40] = struct.pack("<HHH", 0, 0, 0)
    return bytes(patched)


def words(image):
    padded = image + b"\0" * (-len(image) % 8)
    return [(i, struct.unpack_from("<Q", padded, i)[0]) for i in range(0, len(padded), 8)]


def render(image):
    nonzero = [(off, val) for off, val in words(image) if val != 0]
    chunks = [nonzero[i:i + WORDS_PER_FUNCTION] for i in range(0, len(nonzero), WORDS_PER_FUNCTION)]
    out = ["import libc.regio", "", "export { write_image, IMAGE_BYTES }", ""]
    out.append("const IMAGE_BYTES: u64 = %d" % len(image))
    out.append("")
    for n, chunk in enumerate(chunks):
        out.append("fn part_%d(frame: u64) {" % n)
        for off, val in chunk:
            out.append("    regio.write64(frame + %d, 0x%016X)" % (off, val))
        out.append("}")
        out.append("")
    out.append("fn write_image(frame: u64) {")
    for n in range(len(chunks)):
        out.append("    part_%d(frame)" % n)
    out.append("}")
    return "\n".join(out) + "\n"


def main():
    with tempfile.TemporaryDirectory() as tmp:
        image = strip_sections(build(Path(tmp)))
    text = render(image)
    if "--check" in sys.argv:
        if TARGET.read_text() != text:
            sys.exit("vdsoimg.fi out of date: run python3 tools/vdso/gen.py")
        return
    TARGET.write_text(text)


main()
