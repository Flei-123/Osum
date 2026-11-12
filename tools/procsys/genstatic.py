#!/usr/bin/env python3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "kernel/fs/procfs/static.txt"
TARGET = ROOT / "kernel/fs/procfs/pfstatic.fi"
SECTION = "== "


def load_files():
    files = []
    for line in SOURCE.read_text().splitlines():
        if line.startswith(SECTION):
            files.append([line[len(SECTION):], b""])
        elif files:
            files[-1][1] += line.encode() + b"\n"
        else:
            sys.exit("text before the first section")
    names = [name for name, _ in files]
    if len(set(names)) != len(names):
        sys.exit("duplicate file name")
    return files


def literal(data):
    out = []
    for byte in data:
        if 32 <= byte < 127 and byte not in (34, 92):
            out.append(chr(byte))
        else:
            out.append("\\x%02x" % byte)
    return "".join(out)


def render(files):
    blob = b"".join(body for _, body in files) or b"\n"
    offsets, lengths, at = [], [], 0
    for _, body in files:
        offsets.append(at)
        lengths.append(len(body))
        at += len(body)
    top = sum(1 for name, _ in files if name.startswith("top/"))
    count = len(files)
    return (
        "// SPDX-License-Identifier: GPL-2.0-only\n"
        "profile kernel\n\n"
        "import fs.procfs.pfwrite\n\n"
        "export { make, TOP_COUNT, NET_COUNT }\n\n"
        f"const TOP_COUNT: u64 = {top}\n"
        f"const NET_COUNT: u64 = {count - top}\n\n"
        f'static mut blob: [u8; {len(blob)}] = b"{literal(blob)}"\n\n'
        f"static mut offsets: [u64; {count}] = [{', '.join(map(str, offsets))}]\n\n"
        f"static mut lengths: [u64; {count}] = [{', '.join(map(str, lengths))}]\n\n"
        "fn make(state: u64, index: u64) -> u64 {\n"
        f"    if index >= {count} {{\n        return 0\n    }}\n"
        "    return pfwrite.w_bytes(state, 0, ((&blob[0]) as u64) + offsets[index as usize], lengths[index as usize])\n"
        "}\n"
    )


def main():
    files = load_files()
    names = [name for name, _ in files]
    if names != sorted(names, key=lambda n: n.split("/")[0] != "top"):
        sys.exit("top files first, then net")
    text = render(files)
    if "--check" in sys.argv:
        if not TARGET.exists() or TARGET.read_text() != text:
            sys.exit("pfstatic.fi is stale: run tools/procsys/genstatic.py")
        return
    TARGET.write_text(text)


main()
