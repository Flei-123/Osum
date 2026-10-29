#!/usr/bin/env python3
import gzip
import os
import sys

DEFAULT_LIMIT = 3900000
MIN_SLICE = 1 << 20
SAFETY = 0.97


def gz_size(blob):
    return len(gzip.compress(blob, 9, mtime=0))


def next_slice(handle, guess, limit):
    start = handle.tell()
    size = guess
    while True:
        handle.seek(start)
        blob = handle.read(size)
        if not blob:
            return b"", 0
        packed = gz_size(blob)
        if packed <= limit or size <= MIN_SLICE:
            return blob, packed
        size = max(MIN_SLICE, int(size * limit / packed * SAFETY))


def split(tar_path, out_dir, limit):
    parts = []
    guess = 8 << 20
    with open(tar_path, "rb") as handle:
        while True:
            blob, packed = next_slice(handle, guess, limit)
            if not blob:
                break
            name = "%s.part%03d" % (os.path.basename(tar_path), len(parts))
            with open(os.path.join(out_dir, name), "wb") as out:
                out.write(blob)
            parts.append((name, len(blob), packed))
            if len(blob) < guess:
                guess = len(blob)
            else:
                guess = int(len(blob) * limit / max(packed, 1) * SAFETY)
            handle.seek(sum(p[1] for p in parts))
    return parts


def main(argv):
    tar_path, out_dir = argv[1], argv[2]
    limit = int(argv[3]) if len(argv) > 3 else DEFAULT_LIMIT
    os.makedirs(out_dir, exist_ok=True)
    parts = split(tar_path, out_dir, limit)
    for name, raw, packed in parts:
        print("%s %d %d" % (name, raw, packed))
    print("parts %d max_gz %d" % (len(parts), max(p[2] for p in parts)))


if __name__ == "__main__":
    main(sys.argv)
