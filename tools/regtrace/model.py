import re
from dataclasses import dataclass, field

RAW_KINDS = ("r32", "w32")
READ_KINDS = ("r32", "prph_r", "sram_r")
DEFAULT_KEEP = ("r32", "w32", "prph_r", "prph_w", "sram_r", "sram_w", "hcmd")


@dataclass
class Rec:
    seq: int
    t_us: int
    kind: str
    space: str
    off: int
    val: int
    ctx: dict = field(default_factory=dict)
    line: int = 0


def parse_line(text, lineno=0):
    text = text.strip()
    if not text or text.startswith("#"):
        return None
    parts = text.split()
    if len(parts) < 6:
        raise ValueError("line %d: need 6 fields: %r" % (lineno, text))
    seq, t_us, kind, space, off, val = parts[:6]
    ctx = {}
    for tok in parts[6:]:
        k, _, v = tok.partition("=")
        ctx[k] = v
    return Rec(int(seq), int(t_us), kind, space, int(off, 16), int(val, 16), ctx, lineno)


def parse_text(text):
    out = []
    for n, raw in enumerate(text.splitlines(), 1):
        rec = parse_line(raw, n)
        if rec is not None:
            out.append(rec)
    return out


def parse_file(path):
    with open(path, "r", encoding="utf-8") as f:
        return parse_text(f.read())


def render(rec):
    ctx = "".join(" %s=%s" % kv for kv in rec.ctx.items())
    width = 4 if rec.space == "host" else 8
    return "%d %d %s %s %0*x %08x%s" % (rec.seq, rec.t_us, rec.kind, rec.space, width, rec.off, rec.val, ctx)
