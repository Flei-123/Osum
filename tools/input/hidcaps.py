# SPDX-License-Identifier: GPL-2.0-only
import re
from dataclasses import dataclass, field

KINDS = ("IN", "OUT", "FEAT")
LINE = re.compile(r"^(IN|OUT|FEAT) (BTN|VAL) (.*)$")
TOP = re.compile(r"\((0x[0-9a-fA-F]+)/(0x[0-9a-fA-F]+)\)")
EXPONENTS = {0: 0, 12: -4, 14: -2}


@dataclass(frozen=True)
class Cap:
    kind: str
    type: str
    rid: int
    page: int
    usage: int
    link: int
    bits: int = 1
    count: int = 1
    lmin: int = 0
    lmax: int = 1
    pmin: object = None
    pmax: object = None
    unitexp: object = None
    unit: object = None

    def label(self):
        return "%s %s rid=%d page=0x%x usage=0x%x link=%d" % (
            self.kind, self.type, self.rid, self.page, self.usage, self.link)


@dataclass(frozen=True)
class Caps:
    name: str
    top_page: int
    top_usage: int
    inlen: int
    outlen: int
    featlen: int
    nlink: int
    counts: dict = field(default_factory=dict)
    caps: tuple = ()

    def of(self, kind=None, type=None):
        return [c for c in self.caps
                if (kind is None or c.kind == kind) and (type is None or c.type == type)]

    def rids(self, kind):
        return sorted({c.rid for c in self.caps if c.kind == kind})


def parse_pairs(text):
    out = {}
    for token in text.split():
        key, _, value = token.partition("=")
        out[key] = int(value, 0)
    return out


def parse(text, name):
    top = None
    head = {}
    caps = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("#"):
            body = line.lstrip("# ").strip()
            if top is None:
                match = TOP.search(body)
                if match:
                    top = (int(match.group(1), 16), int(match.group(2), 16))
            if body.startswith("toplevel "):
                head = parse_pairs(body[len("toplevel "):])
            continue
        match = LINE.match(line)
        if not match:
            raise ValueError("unparsable caps line: %r" % line)
        kind, typ, rest = match.groups()
        pairs = parse_pairs(rest)
        if typ == "BTN":
            caps.append(Cap(kind, typ, pairs["rid"], pairs["page"], pairs["usage"], pairs["link"]))
        else:
            caps.append(Cap(kind, typ, pairs["rid"], pairs["page"], pairs["usage"], pairs["link"],
                            pairs["bits"], pairs["count"], pairs["lmin"], pairs["lmax"],
                            pairs["pmin"], pairs["pmax"], pairs["unitexp"], pairs["unit"]))
    if top is None:
        raise ValueError("no top-level usage in header of %s" % name)
    counts = {k: v for k, v in head.items() if k in ("inbtn", "inval", "outbtn", "outval", "featbtn", "featval")}
    return Caps(name, top[0], top[1], head["inlen"], head["outlen"], head["featlen"],
                head["nlink"], counts, tuple(caps))


def load(path):
    import os
    name = os.path.basename(path)
    if name.endswith(".caps"):
        name = name[:-5]
    with open(path, "r", encoding="utf-8") as handle:
        return parse(handle.read(), name)


def header_counts(caps):
    out = {}
    for kind in KINDS:
        prefix = kind.lower()
        out[prefix + "btn"] = len(caps.of(kind, "BTN"))
        out[prefix + "val"] = len(caps.of(kind, "VAL"))
    return out
