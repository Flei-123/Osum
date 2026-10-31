from norm import text


def entry_eq(a, b):
    if a.kind == "poll" or b.kind == "poll":
        if a.kind == "poll" and b.kind == "poll":
            return a.space == b.space and a.off == b.off and a.val == b.val
        p, q = (a, b) if a.kind == "poll" else (b, a)
        return q.kind in ("r32", "prph_r", "sram_r") and p.space == q.space and p.off == q.off and p.val == q.val
    return (a.kind, a.space, a.off, a.val, a.extra) == (b.kind, b.space, b.off, b.val, b.extra)


def last_hcmd(entries, upto):
    for i in range(min(upto, len(entries) - 1), -1, -1):
        if entries[i].kind == "hcmd":
            return entries[i]
    return None


def first_diff(a, b):
    n = min(len(a), len(b))
    for i in range(n):
        if not entry_eq(a[i], b[i]):
            return i
    if len(a) != len(b):
        return n
    return -1


def reg_name(e):
    return "%s %0*x" % (e.space, 4 if e.space == "host" else 8, e.off)


def report(a, b, idx, ctx_lines=3):
    if idx < 0:
        return "EQUAL (%d entries)" % len(a)
    ea = a[idx] if idx < len(a) else None
    eb = b[idx] if idx < len(b) else None
    lines = ["DIFF at entry %d" % idx]
    ref = ea or eb
    lines.append("  register: %s" % reg_name(ref))
    lines.append("  expected (a): %s" % (text(ea) if ea else "<end of trace>"))
    lines.append("  actual   (b): %s" % (text(eb) if eb else "<end of trace>"))
    ha = last_hcmd(a, idx)
    hb = last_hcmd(b, idx)
    lines.append("  last hcmd (a): %s" % (text(ha) if ha else "<none>"))
    lines.append("  last hcmd (b): %s" % (text(hb) if hb else "<none>"))
    lo = max(0, idx - ctx_lines)
    lines.append("  preceding (a):")
    for e in a[lo:idx]:
        lines.append("    " + text(e))
    return "\n".join(lines)
