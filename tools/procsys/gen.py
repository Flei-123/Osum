#!/usr/bin/env python3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "kernel/fs/procfs/sysreg.txt"
TARGET = ROOT / "kernel/fs/procfs/pfsystab.fi"
OFFSET_LIMIT = 0x2000
TREES = ("sys/", "net/")


def load_rows():
    rows = []
    for line in SOURCE.read_text().splitlines():
        if not line.strip():
            continue
        path, kind, value = line.split("|", 2)
        if kind not in ("n", "t", "p"):
            sys.exit("bad kind: " + line)
        rows.append((path, kind, value.replace("\\t", "\t")))
    return rows


def check_rows(rows):
    seen = set()
    for path, _, _ in rows:
        if not path.startswith(TREES):
            sys.exit("unknown tree: " + path)
        if path in seen:
            sys.exit("duplicate: " + path)
        seen.add(path)
    order = [path.split("/", 1)[0] for path, _, _ in rows]
    if order != sorted(order, key=TREES_ORDER.index):
        sys.exit("rows must be grouped sys first, then net")


TREES_ORDER = ["sys", "net"]


def encode(rows):
    data = bytearray(b"\n")
    for path, kind, value in rows:
        data += f"{path}|{kind}|{value}\n".encode()
    if len(data) >= OFFSET_LIMIT:
        sys.exit("table too large")
    return bytes(data)


def literal(data):
    out = []
    for byte in data:
        if 32 <= byte < 127 and byte not in (34, 92):
            out.append(chr(byte))
        else:
            out.append("\\x%02x" % byte)
    return "".join(out)


def render(data):
    return (
        "// SPDX-License-Identifier: GPL-2.0-only\n"
        "profile kernel\n\n"
        "export { base, LEN }\n\n"
        f"const LEN: u64 = {len(data)}\n\n"
        f'static mut tab: [u8; {len(data)}] = b"{literal(data)}"\n\n'
        "fn base() -> u64 {\n    return (&tab[0]) as u64\n}\n"
    )


def main():
    rows = load_rows()
    check_rows(rows)
    text = render(encode(rows))
    if "--check" in sys.argv:
        if not TARGET.exists() or TARGET.read_text() != text:
            sys.exit("pfsystab.fi is stale: run tools/procsys/gen.py")
        return
    TARGET.write_text(text)


main()
