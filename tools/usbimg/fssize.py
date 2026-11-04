import os
import re
import sys

BLOCK = 512
MODE_SUFFIX = re.compile(r"@[0-7]{3,4}$")


def spec_source(spec):
    if "=" not in spec:
        return None
    path = MODE_SUFFIX.sub("", spec.split("=", 1)[1])
    return path if os.path.isfile(path) else None


def content_blocks(specs):
    total = 0
    for spec in specs:
        path = spec_source(spec)
        if path is None:
            total += 2
            continue
        size = os.stat(path).st_size
        data = (size + BLOCK - 1) // BLOCK
        total += data + data // 100 + 3
    return total


def main(argv):
    free_mib = int(argv[1])
    inodes = int(argv[2])
    blocks = content_blocks(argv[3:])
    blocks += inodes * 2
    blocks += blocks // 50
    blocks += free_mib * 1048576 // BLOCK
    print(blocks)


if __name__ == "__main__":
    main(sys.argv)
