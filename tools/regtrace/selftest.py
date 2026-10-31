import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from model import parse_text, render
from norm import normalize, text
from diffing import first_diff, report

passed = 0
failed = 0


def check(name, cond, detail=""):
    global passed, failed
    if cond:
        passed += 1
        print("  OK    " + name)
    else:
        failed += 1
        print("  FAIL  " + name + (" :: " + detail if detail else ""))


def lines(entries):
    return [text(e) for e in entries]


def trace(*rows):
    return parse_text("\n".join("%d %d %s" % (i, i * 10, r) for i, r in enumerate(rows)))


def unit_tests():
    t = trace("w32 csr 00000024 00000008", "r32 csr 00000024 0000000c")
    check("parse: render round trip", [render(r) for r in t] == ["0 0 w32 csr 00000024 00000008", "1 10 r32 csr 00000024 0000000c"])
    n = normalize(trace("w32 csr 00000448 0300a02c", "r32 csr 00000450 00000011", "w32 csr 00000444 03000100", "w32 csr 0000044c 00000001"))
    check("fold: prph read + write pairs", lines(n) == ["prph_r prph 0000a02c 00000011", "prph_w prph 00000100 00000001"], str(lines(n)))
    n = normalize(trace("w32 csr 0000040c 00800000", "r32 csr 0000041c 00000001", "r32 csr 0000041c 00000002"))
    check("fold: sram read auto-increments by 4", lines(n) == ["sram_r sram 00800000 00000001", "sram_r sram 00800004 00000002"], str(lines(n)))
    n = normalize(trace("w32 csr 10000024 00000008"), bar=0x10000000)
    check("normalize: BAR base removed", lines(n) == ["w32 csr 00000024 00000008"])
    n = normalize(trace("r32 csr 00000024 00000000", "r32 csr 00000024 00000004", "r32 csr 00000024 00000008"))
    check("polls: reads of one register fold to poll until last value", lines(n) == ["poll csr 00000024 until 00000008"], str(lines(n)))
    a = normalize(trace("r32 csr 00000024 00000000", "r32 csr 00000024 00000008", "w32 csr 00000020 00000001"))
    b = normalize(trace("r32 csr 00000024 00000008", "w32 csr 00000020 00000001"))
    check("diff: poll equals a single read with the final value", first_diff(a, b) == -1)
    c = normalize(trace("r32 csr 00000024 00000004", "w32 csr 00000020 00000001"))
    check("diff: poll with another final value differs", first_diff(a, c) == 0)
    x = normalize(trace("w32 csr 00000024 00000008", "irq csr 00000008 00000001", "r32 csr 00000024 00000008"))
    y = normalize(trace("w32 csr 00000024 00000008", "r32 csr 00000024 00000008"))
    check("normalize: irq and unknown kinds are dropped by default", first_diff(x, y) == -1)
    p = normalize(trace("w32 csr 00000020 00000001", "hcmd host 010c 00000004 v=0 d=01020304", "w32 csr 00000024 00000008"))
    q = normalize(trace("w32 csr 00000020 00000001", "hcmd host 010c 00000004 v=0 d=01020304", "w32 csr 00000024 0000000c"))
    idx = first_diff(p, q)
    rep = report(p, q, idx)
    check("diff: first difference found at the right entry", idx == 2, str(idx))
    check("diff: report names register, both values, last hcmd",
          "csr 00000024" in rep and "00000008" in rep and "0000000c" in rep and "last hcmd (a): hcmd host 010c" in rep, rep)
    r = normalize(trace("w32 csr 00000020 00000001", "hcmd host 010c 00000004 v=0 d=01020305", "w32 csr 00000024 00000008"))
    check("diff: hcmd payload difference found", first_diff(p, r) == 1)
    check("diff: shorter trace reported", first_diff(p, p[:2]) == 2)
    check("diff: identical traces equal", first_diff(p, normalize(trace("w32 csr 00000020 00000001", "hcmd host 010c 00000004 v=0 d=01020304", "w32 csr 00000024 00000008"))) == -1)


def x_tests():
    t = trace("r32 csr 00000008 00000000 x=2", "r32 csr 00000008 00000000", "w32 csr 00000024 00000001")
    n = normalize(t)
    check("x=: run-length count folds into poll", [text(e) for e in n] == ["poll csr 00000008 until 00000000", "w32 csr 00000024 00000001"] and n[0].count == 4, str([(text(e), e.count) for e in n]))
    one = normalize(trace("r32 csr 00000008 00000000", "w32 csr 00000024 00000001"))
    check("x=: single read equals compressed run in diff", first_diff(n, one) == -1)


def firn_dump_tests(d):
    def load(name):
        with open(os.path.join(d, name), "r", encoding="utf-8") as f:
            return f.read()

    off = load("off.txt")
    check("firn: trace off -> no records, size 0", off.strip() == "OFF size=0", off)
    on = load("on.txt")
    recs = parse_text(on)
    check("firn: trace on -> header + 6 records", on.startswith("# regtrace v1 osum first_seq=0 records=6") and len(recs) == 6, on)
    check("firn: record kinds in order", [r.kind for r in recs] == ["w32", "r32", "hcmd", "rx", "dma_desc", "irq"], str([r.kind for r in recs]))
    check("firn: hcmd wid, length and payload", recs[2].off == 0x010C and recs[2].val == 8 and recs[2].ctx.get("d") == "05060708090a0b0c", str(recs[2]))
    check("firn: dma_desc carries the 64-bit address", recs[4].val == 0x23456789 and recs[4].ctx.get("ah") == "00000001", str(recs[4]))
    check("firn: timestamps from the clock hook", all(r.t_us == 7 for r in recs))
    ov = load("overflow.txt")
    orecs = parse_text(ov)
    check("firn: ring overflow keeps the newest records", ov.startswith("# regtrace v1 osum first_seq=32 records=8") and len(orecs) == 8, ov.splitlines()[0])
    check("firn: overflow sequence contiguous", [r.seq for r in orecs] == list(range(32, 40)), str([r.seq for r in orecs]))
    check("firn: overflow last value is the newest", orecs[-1].val == 0x13 and orecs[-2].val == 0x13, str(orecs[-2:]))
    rp = load("repeat.txt")
    rrecs = parse_text(rp)
    check("firn: identical reads compress to one record with x=", len(rrecs) == 4 and rrecs[1].ctx.get("x") == "0000012b", rp)
    check("firn: repeat header counts records not reads", rp.startswith("# regtrace v1 osum first_seq=0 records=4"), rp.splitlines()[0])
    rn = normalize(rrecs)
    check("firn: compressed polls normalize like the expanded loop", [text(e) for e in rn] == ["w32 csr 00000024 00000008", "poll csr 00000008 until 00000004", "w32 csr 00000024 00000008"], str([text(e) for e in rn]))
    chunked = load("on.txt")
    full = load("on_full.txt")
    check("firn: chunked read equals a single read", chunked == full)


if __name__ == "__main__":
    unit_tests()
    x_tests()
    if len(sys.argv) > 1:
        firn_dump_tests(sys.argv[1])
    print("RESULT pass=%d fail=%d" % (passed, failed))
    sys.exit(1 if failed else 0)
