import sys

MAX_CMDS_PER_4096_PAGES = 600
MIN_SECTORS_PER_CMD = 64
MAX_CYCLES_PER_PAGE = 80000
MAX_READ_SEQ_CMDS = 200
MIN_READ_SEQ_SECTORS_PER_CMD = 200
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


def measured(snaps, tag):
    d = delta(snaps, tag)
    if d is None or d["blk.run_cmds"] == 0:
        return None
    return d["blk.run_cmds"], d["blk.run_sectors"] // d["blk.run_cmds"], d["blk.run_cycles"] // PAGES


def main():
    snaps = parse(sys.argv[1])
    seq = measured(snaps, "map_seq")
    read = measured(snaps, "read_seq")
    if seq is None or read is None:
        print("  FAIL  no counters")
        print("CHECK: 0 passed, 1 failed")
        return 1
    checks = (
        ("map_seq read commands", seq[0], seq[0] <= MAX_CMDS_PER_4096_PAGES, "<= %d" % MAX_CMDS_PER_4096_PAGES),
        ("map_seq sectors per command", seq[1], seq[1] >= MIN_SECTORS_PER_CMD, ">= %d" % MIN_SECTORS_PER_CMD),
        ("map_seq cycles per 4 KiB page", seq[2], seq[2] <= MAX_CYCLES_PER_PAGE, "<= %d" % MAX_CYCLES_PER_PAGE),
        ("read_seq read commands", read[0], read[0] <= MAX_READ_SEQ_CMDS, "<= %d" % MAX_READ_SEQ_CMDS),
        ("read_seq sectors per command", read[1], read[1] >= MIN_READ_SEQ_SECTORS_PER_CMD, ">= %d" % MIN_READ_SEQ_SECTORS_PER_CMD),
    )
    fails = 0
    for name, value, ok, want in checks:
        print("  %s  %s: %d (want %s)" % ("OK  " if ok else "FAIL", name, value, want))
        fails += 0 if ok else 1
    print("CHECK: %d passed, %d failed" % (len(checks) - fails, fails))
    return 1 if fails else 0


sys.exit(main())
