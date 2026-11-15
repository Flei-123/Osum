#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import sys


def read_lines(path: str) -> list[str]:
    with open(path, encoding="utf-8") as handle:
        return handle.read().split("\n")


def write_lines(path: str, lines: list[str]) -> None:
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines))


def insert_at_start(path: str, name: str, statement: str) -> int:
    lines = read_lines(path)
    head = re.compile(r"^fn\s+" + re.escape(name) + r"\(.*\{\s*$")
    hits = [index for index, line in enumerate(lines) if head.match(line)]
    if len(hits) != 1:
        print(f"mutant: {len(hits)} matches for fn {name} in {path}", file=sys.stderr)
        return 1
    lines.insert(hits[0] + 1, "    " + statement)
    write_lines(path, lines)
    return 0


def move_after(path: str, moved: str, anchor: str) -> int:
    lines = read_lines(path)
    source = [index for index, line in enumerate(lines) if moved in line]
    target = [index for index, line in enumerate(lines) if anchor in line]
    if len(source) != 1 or len(target) != 1 or source[0] > target[0]:
        print(f"mutant: cannot move '{moved}' after '{anchor}' in {path}", file=sys.stderr)
        return 1
    line = lines.pop(source[0])
    lines.insert(target[0], line)
    write_lines(path, lines)
    return 0


def main() -> int:
    if len(sys.argv) < 5:
        print("usage: mutant.py insert|move <file> <a> <b>", file=sys.stderr)
        return 2
    mode, path, first, second = sys.argv[1:5]
    if mode == "insert":
        return insert_at_start(path, first, second)
    if mode == "move":
        return move_after(path, first, second)
    return 2


sys.exit(main())
