import collections

Row = collections.namedtuple("Row", "id group kind expected command")
KINDS = ("eq", "re", "skip", "ext")


def load(path):
    rows = []
    for number, line in enumerate(open(path, encoding="utf-8"), 1):
        line = line.rstrip("\n")
        if not line or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) != 5:
            raise SystemExit("%s:%d: expected 5 tab-separated fields, got %d" % (path, number, len(fields)))
        row = Row(*fields)
        if row.kind not in KINDS:
            raise SystemExit("%s:%d: unknown kind %r" % (path, number, row.kind))
        if any(r.id == row.id for r in rows):
            raise SystemExit("%s:%d: duplicate id %r" % (path, number, row.id))
        rows.append(row)
    return rows
