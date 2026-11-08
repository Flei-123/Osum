import sys

MAX_CMDS_PER_4096_PAGES = 600
MIN_SECTORS_PER_CMD = 64
MAX_CYCLES_PER_PAGE = 80000
PAGES = 4096


def parse(path):
    cells = {}
    snaps = {}
    for line in open(path, errors="replace"):
        f = line.split()
        if len(f) == 4 and f[0] == "DPC":
            cells[f[2]] = int(f[3])
            if f[2] == "blk.ahci_polls":
                snaps.setdefault(f[1], []).append(dict(cells))
    return snaps


def delta(snaps, tag):
    pairs = snaps.get(tag, [])
    if len(pairs) < 2:
        return None
    a, b = pairs[0], pairs[-1]
    return {k: b[k] - a[k] for k in b}


def main():
    d = delta(parse(sys.argv[1]), "map_seq")
    fails = 0
    if d is None or d["blk.run_cmds"] == 0:
        print("  FAIL  map_seq: no counters")
        print("CHECK: 0 passed, 1 failed")
        return 1
    cmds = d["blk.run_cmds"]
    per_cmd = d["blk.run_sectors"] // cmds
    per_page = d["blk.run_cycles"] // PAGES
    for name, value, ok, want in (
        ("map_seq read commands", cmds, cmds <= MAX_CMDS_PER_4096_PAGES, "<= %d" % MAX_CMDS_PER_4096_PAGES),
        ("map_seq sectors per command", per_cmd, per_cmd >= MIN_SECTORS_PER_CMD, ">= %d" % MIN_SECTORS_PER_CMD),
        ("map_seq cycles per 4 KiB page", per_page, per_page <= MAX_CYCLES_PER_PAGE, "<= %d" % MAX_CYCLES_PER_PAGE),
    ):
        print("  %s  %s: %d (want %s)" % ("OK  " if ok else "FAIL", name, value, want))
        fails += 0 if ok else 1
    print("CHECK: %d passed, %d failed" % (3 - fails, fails))
    return 1 if fails else 0


sys.exit(main())
