from dataclasses import dataclass
from model import READ_KINDS, DEFAULT_KEEP
from fold import strip_bar, fold_windows


@dataclass
class Entry:
    kind: str
    space: str
    off: int
    val: int
    count: int = 1
    extra: str = ""
    line: int = 0
    seq: int = 0


def text(e):
    if e.kind == "poll":
        return "poll %s %0*x until %08x" % (e.space, 4 if e.space == "host" else 8, e.off, e.val)
    width = 4 if e.space == "host" else 8
    tail = " " + e.extra if e.extra else ""
    return "%s %s %0*x %08x%s" % (e.kind, e.space, width, e.off, e.val, tail)


def text_counted(e):
    if e.kind == "poll":
        return text(e) + "  (x%d)" % e.count
    return text(e)


def host_extra(rec):
    d = rec.ctx.get("d", "")
    return "d=" + d if d else ""


def to_entries(recs, keep):
    out = []
    for r in recs:
        if r.kind not in keep:
            continue
        extra = host_extra(r) if r.space == "host" else ""
        out.append(Entry(r.kind, r.space, r.off, r.val, 1, extra, r.line, r.seq))
    return out


def fold_polls(entries):
    out = []
    for e in entries:
        last = out[-1] if out else None
        same = last is not None and e.kind in READ_KINDS and last.space == e.space and last.off == e.off \
            and (last.kind == e.kind or (last.kind == "poll" and last.extra == e.kind))
        if same:
            if last.kind != "poll":
                out[-1] = Entry("poll", last.space, last.off, e.val, 2, last.kind, last.line, last.seq)
            else:
                last.count += 1
                last.val = e.val
        else:
            out.append(e)
    return out


def normalize(recs, bar=0, keep=DEFAULT_KEEP):
    recs = strip_bar(list(recs), bar)
    recs = fold_windows(recs)
    return fold_polls(to_entries(recs, keep))
