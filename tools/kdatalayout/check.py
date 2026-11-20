import re
import sys

CONST_RE = re.compile(r"^const (\w+): u64 = ([^/\n]+?)\s*(?://.*)?$", re.M)

LAYOUTS = [
    {
        "file": "kernel/pwr/pmon.fi",
        "region": "kstate.PMON_MAX",
        "tables": [
            ("TASKS", "TBYTES", "kstate.MAX_TASKS"),
            ("BUCKETS", "BBYTES", "NBUCKET"),
            ("WAPP", "1", "WAPP_MAX"),
            ("WSEK", "1", "8"),
            ("RING", "RBYTES", "NSAMPLE"),
            ("PROGS", "PRBYTES", "NPROG"),
        ],
    },
    {
        "file": "kernel/net/netmon.fi",
        "region": "kstate.NETMON_MAX",
        "tables": [
            ("TASKS", "TBYTES", "kstate.MAX_TASKS"),
            ("SOCKS", "SBYTES", "NSOCK"),
            ("PROGS", "PBYTES", "NPROG"),
        ],
    },
    {
        "file": "kernel/bus/bus.fi",
        "region": "kstate.BUS_MAX",
        "tables": [
            ("SVCS", "SVC_BYTES", "SVC_MAX"),
            ("SUBS", "SUB_BYTES", "SUB_MAX"),
            ("MSGS", "MSG_BYTES", "MSG_MAX"),
            ("SEGS", "SEG_BYTES", "SEG_MAX"),
            ("HIST", "HIST_BYTES", "HIST_MAX"),
            ("NOTIS", "NOTI_BYTES", "NOTI_MAX"),
            ("MIMES", "MIME_BYTES", "MIME_MAX"),
        ],
    },
    {
        "file": "kernel/bus/bus.fi",
        "region": "kstate.BUSBOX_MAX",
        "tables": [("0", "BOX_BYTES", "kstate.MAX_TASKS")],
    },
]


class Consts:
    def __init__(self, root, override=None):
        self.root = root
        self.override = override or {}
        self.files = {}

    def table(self, path):
        if path not in self.files:
            text = self.override.get(path)
            if text is None:
                with open(f"{self.root}/{path}") as handle:
                    text = handle.read()
            self.files[path] = dict(CONST_RE.findall(text))
        return self.files[path]

    def value(self, path, expr):
        expr = expr.strip()
        def sub(match):
            qualified, name = match.group(1), match.group(2)
            target = "kernel/lib/kstate.fi" if qualified else path
            return str(self.value(target, self.table(target)[name]))
        resolved = re.sub(r"\b(kstate\.)?([A-Z][A-Z0-9_]+)\b", sub, expr)
        if not re.fullmatch(r"[0-9a-fA-Fx+*\-() ]+", resolved):
            raise ValueError(f"cannot evaluate {expr!r} in {path}")
        return eval(resolved)


def check(root, override=None):
    consts = Consts(root, override)
    problems = []
    count = 0
    for layout in LAYOUTS:
        path = layout["file"]
        region = consts.value(path, layout["region"])
        spans = []
        for offset, stride, items in layout["tables"]:
            start = consts.value(path, offset)
            size = consts.value(path, stride) * consts.value(path, items)
            spans.append((start, start + size, offset))
        spans.sort()
        for (a0, a1, an), (b0, b1, bn) in zip(spans, spans[1:]):
            count += 1
            if a1 > b0:
                problems.append(f"{path}: {an} [{a0:#x},{a1:#x}) overlaps {bn} [{b0:#x},{b1:#x})")
        count += 1
        if spans[-1][1] > region:
            problems.append(f"{path}: {spans[-1][2]} ends at {spans[-1][1]:#x}, region {layout['region']} is {region:#x}")
    return count, problems


if __name__ == "__main__":
    root = sys.argv[1]
    total, issues = check(root)
    for issue in issues:
        print("FAIL", issue)
    print(f"KDATALAYOUT: {total - len(issues)} ok, {len(issues)} fail")
    sys.exit(1 if issues else 0)
