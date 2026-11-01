#!/usr/bin/env python3
import hashlib
import os
import subprocess
import sys

CHUNK = 4096


def image_cat(image, path):
    result = subprocess.run(
        ["python3", os.path.join("tools", "osum", "mkfs.py"), "cat", image, path],
        capture_output=True)
    return result.stdout if result.returncode == 0 else None


def parse_snapshot(text):
    entries = {}
    lines = text.split("\n")
    current = None
    longest = 0
    continuations = 0
    ended = False
    header = lines[0] if lines else ""
    for ln in lines[1:]:
        longest = max(longest, len(ln))
        if ln.startswith("/"):
            fields = ln.split("\t")
            current = fields[0]
            entries[current] = {"size": int(fields[3]), "hashes": [h for h in fields[4].split(",") if h and h != "-"]}
        elif ln.startswith("+"):
            continuations += 1
            entries[current]["hashes"].extend(h for h in ln[1:].split(",") if h)
        elif ln.startswith("end\t"):
            ended = True
    return header, entries, longest, continuations, ended


def chunk_names(data):
    return [hashlib.sha256(data[i:i + CHUNK]).hexdigest() for i in range(0, len(data), CHUNK)]


def main(argv):
    image, snap_path, source_dir = argv[1], argv[2], argv[3]
    raw = image_cat(image, snap_path)
    if raw is None:
        print("snapshot=missing")
        return 1
    header, entries, longest, continuations, ended = parse_snapshot(raw.decode("latin-1"))
    print("header=%s" % header.split(" ")[0])
    print("ended=%d" % (1 if ended else 0))
    print("continuation_lines=%d" % continuations)
    print("longest_line=%d" % longest)
    good = 0
    total = 0
    for name in sorted(os.listdir(source_dir)):
        total += 1
        data = open(os.path.join(source_dir, name), "rb").read()
        entry = entries.get("/" + name)
        if entry and entry["size"] == len(data) and entry["hashes"] == chunk_names(data):
            good += 1
        else:
            print("MISMATCH %s" % name)
    print("entries_match=%d/%d" % (good, total))
    return 0


sys.exit(main(sys.argv))
