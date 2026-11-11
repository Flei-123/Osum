import sys

import registry

PREAMBLE = """B=/bin/busybox
$B ln -s /usr/bin/python3 /bin/python3
"""


def emit(row):
    return 'echo "AMB %s"\no=$( ( %s ) 2>&1 | $B tail -n 1 )\necho "AM %s $o"\n' % (row.id, row.command, row.id)


def main(registry_paths, out_path):
    lines = [PREAMBLE]
    for path in registry_paths:
        lines += [emit(r) for r in registry.load(path) if r.kind in ("eq", "re")]
    lines.append('echo "AM end"\n')
    open(out_path, "w", encoding="utf-8").write("".join(lines))


if __name__ == "__main__":
    main(sys.argv[2:], sys.argv[1])
