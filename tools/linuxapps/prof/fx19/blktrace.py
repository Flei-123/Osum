import collections
import re
import sys

PAGE = 4096
SECTOR = 512
META_LIMIT = 3 << 20
REGION = 32 << 20
EVENT = re.compile(r"blk_co_(preadv|pwritev) .*offset (\d+) bytes (\d+)")
COUNTER = re.compile(r"FX19 (\d+) (begin|png|rc) blk\.ahci_(read|write)_cmds (\d+)")


def load_events(path):
    events = []
    for line in open(path, errors="ignore"):
        match = EVENT.search(line)
        if match:
            events.append((match[1], int(match[2]), int(match[3])))
    return [e for e in events if e[0] == "preadv"], [e for e in events if e[0] == "pwritev"]


def load_counters(path):
    counters = {}
    for line in open(path, errors="ignore"):
        match = COUNTER.match(line.strip())
        if match:
            counters[(int(match[1]), match[2], match[3])] = int(match[4])
    return counters


def pages_of(event):
    return range(event[1] // PAGE, (event[1] + event[2] + PAGE - 1) // PAGE)


def size_histogram(events):
    return sorted(collections.Counter(e[2] // SECTOR for e in events).items(), key=lambda kv: -kv[1])[:10]


def report_reads(window, before):
    pages = collections.Counter(p for e in window for p in pages_of(e))
    earlier = {p for e in before for p in pages_of(e)}
    meta = [e for e in window if e[1] < META_LIMIT]
    print("reads %d bytes %d meta_cmds %d data_cmds %d" % (len(window), sum(e[2] for e in window), len(meta), len(window) - len(meta)))
    print("read size histogram (sectors, count)", size_histogram(window))
    print("distinct pages %d page reads %d pages read more than once %d" % (len(pages), sum(pages.values()), sum(1 for c in pages.values() if c > 1)))
    print("pages also read before the window", sum(1 for p in pages if p in earlier))
    print("most repeated pages (sector, count)", [(p * PAGE // SECTOR, c) for p, c in pages.most_common(12)])
    regions = collections.Counter()
    for e in window:
        regions[e[1] // REGION] += e[2] // SECTOR
    print("read sectors per 32 MiB region", sorted(regions.items()))
    return pages


def report_writes(window, upto):
    written = {p for e in upto for p in pages_of(e)}
    print("writes %d bytes %d" % (len(window), sum(e[2] for e in window)))
    print("write size histogram (sectors, count)", size_histogram(window))
    return written


def main():
    reads, writes = load_events(sys.argv[1])
    counters = load_counters(sys.argv[2])
    run = int(sys.argv[3])
    start, end = sys.argv[4:6] if len(sys.argv) > 5 else ("begin", "png")
    r0, r1 = counters[(run, start, "read")], counters[(run, end, "read")]
    w0, w1 = counters[(run, start, "write")], counters[(run, end, "write")]
    print("trace reads %d writes %d, window %s->%s of run %d" % (len(reads), len(writes), start, end, run))
    pages = report_reads(reads[r0:r1], reads[:r0])
    written = report_writes(writes[w0:w1], writes[:w1])
    print("window pages written earlier or inside the window", sum(1 for p in pages if p in written))


if __name__ == "__main__":
    main()
