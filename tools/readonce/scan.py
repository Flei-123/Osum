#!/usr/bin/env python3
import os
import re
import sys

ROOTS = ("kernel/user", "lib")
CALL = re.compile(r"(?<![\w.])(?:io\.read\(|ulib\.sys\(\s*(?:ulib\.)?SYS_READ,)")
SKIP_FILES = ("lib/libc/io.fi", "kernel/user/ulib.fi")
LIMIT = 4096
FN = re.compile(r"^\s*(?:pub\s+)?fn\s+(\w+)")
CONST = re.compile(r"^\s*(?:pub\s+)?const\s+(\w+)\s*:\s*\w+\s*=\s*(0x[0-9a-fA-F]+|\d+)")


def read_lines(path):
    with open(path, "rb") as handle:
        return handle.read().decode("utf-8", "replace").split("\n")


def indent_of(line):
    return len(line) - len(line.lstrip(" "))


def call_text(lines, start, col):
    text = ""
    depth = 0
    seen = False
    index = start
    pos = col
    while index < len(lines):
        segment = lines[index][pos:]
        for ch in segment:
            text += ch
            if ch == "(":
                depth += 1
                seen = True
            elif ch == ")":
                depth -= 1
                if seen and depth == 0:
                    return text
        text += " "
        index += 1
        pos = 0
    return text


def last_arg(text):
    inner = text[text.index("(") + 1:text.rindex(")")]
    depth = 0
    cut = 0
    for i, ch in enumerate(inner):
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth -= 1
        elif ch == "," and depth == 0:
            cut = i + 1
    return inner[cut:].strip()


def in_loop(lines, row):
    base = indent_of(lines[row])
    for back in range(row - 1, max(row - 60, -1), -1):
        line = lines[back]
        if not line.strip():
            continue
        level = indent_of(line)
        if level < base:
            stripped = line.strip()
            if stripped.startswith(("while ", "while(", "loop", "for ")):
                return True
            if FN.match(line):
                return False
            base = level
    return False


def resolve(arg, consts):
    arg = arg.strip()
    if re.fullmatch(r"0x[0-9a-fA-F]+|\d+", arg):
        return int(arg, 0)
    if arg in consts:
        return consts[arg]
    return None


def scan(path):
    lines = read_lines(path)
    consts = {}
    for line in lines:
        match = CONST.match(line)
        if match:
            consts[match.group(1)] = int(match.group(2), 0)
    found = []
    current = "-"
    for row, line in enumerate(lines):
        match = FN.match(line)
        if match:
            current = match.group(1)
        stripped = line.strip()
        if stripped.startswith("//") or "read_full" in line:
            continue
        hit = CALL.search(line)
        if not hit:
            continue
        text = call_text(lines, row, hit.start())
        if "(" not in text or ")" not in text:
            continue
        size = last_arg(text)
        value = resolve(size, consts)
        if value is not None and value <= LIMIT:
            continue
        if in_loop(lines, row):
            continue
        found.append((path, current, row + 1, size))
    return found


def collect():
    result = []
    for root in ROOTS:
        for base, _dirs, files in os.walk(root):
            for name in sorted(files):
                path = os.path.join(base, name)
                if name.endswith(".fi") and path not in SKIP_FILES:
                    result.extend(scan(path))
    return sorted(result)


def main():
    allow_path = "tools/readonce/allow.txt"
    allowed = set()
    if os.path.exists(allow_path):
        with open(allow_path) as handle:
            allowed = {l.split("#")[0].strip() for l in handle if l.split("#")[0].strip()}
    bad = 0
    for path, fn, row, size in collect():
        key = "%s:%s" % (path, fn)
        if key in allowed:
            continue
        bad += 1
        print("SINGLE-READ %s:%d fn %s size %s" % (path, row, fn, size))
    print("flagged: %d" % bad)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
