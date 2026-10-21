#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/desktop/serial.py -- de-interleave a guest serial log (r1350).

Several ring 3 programs write their `prefix: key=value ...` records to ONE serial port. Under
load the line lock is taken over (stale takeover), and a record is cut by another program's
record. Seen in real logs:

    taskbar: glas alpha=100 key=ffffffwm: rahmen x=24 y=40 w=562 h=415 r=8
    taskbar: text clock x=1229settings: preset i=4 id=papier ... sel=0
    settings: preset i=6 ... acc=1409085 base=17 fg=988970 bg=16777215 tw=41 t=20:30

A runner that reads these with `grep | tail -1 | grep -oE 'x=[0-9]+ y=...'` takes the second
match of a nested line ("taskbar: geom ... settings: rect ... x=216 y=100 w=81 h=30") or a
half record, and goes red for a reason that is not the product.

The cure is NOT to loosen a check. Every record is judged on its own and only an INTACT record
is handed to the checks:

  * the line is split at every record marker (`taskbar: `, `settings: `, ...). A piece that is
    followed by another marker in the same line was cut -> dropped. A piece in front of the
    first marker (the tail of some cut record) -> dropped.
  * a piece that is the end of its line must match the STRICT schema of its kind (every key
    exactly once, in order, numbers are numbers, nothing left over). Kinds without a schema are
    still refused when a key appears twice (a tail glued to another record).
  * what is not a record at all (kernel text, `wm: hold`) passes unchanged.

Usage:  serial.py selftest                prints "OK <what>" / "FAIL <what>" (doctored logs, incl. counter-proofs)
        serial.py clean IN OUT       writes OUT (intact lines) and OUT.torn (what was dropped);
                                     prints "serial: N lines, K torn" to stderr.
        serial.py check IN           exit 0 when nothing in IN is torn (diagnostics).
"""
import re
import sys

# every program that writes records to the serial port in the runs of this gate
PREFIXES = ("taskbar", "settings", "wlib", "wm", "launcher", "desktop", "explorer", "pwr",
            "ptrcfg", "fuiapp", "fuib", "fuiglyph", "qs", "desk", "ring3", "i18n", "dhcp",
            "widgetdemo")
# no look-behind on purpose: the cut lands anywhere, also behind a hex digit ("key=ffffffwm: ...")
MARK = re.compile(r"(?:%s): " % "|".join(PREFIXES))

N = r"-?[0-9]+"
# strict schemas: (kind-prefix, full regex of the REST after the kind). Fields in the order the
# program prints them (see the `say` calls in kernel/user/{taskbar,settings,wlib}.fi).
SCHEMAS = {
    "taskbar: geom ": rf"edge={N} x={N} y={N} w={N} h={N} vertical={N} thick={N} shown={N}",
    "taskbar: work ": rf" ?x={N} y={N} w={N} h={N}",
    "taskbar: conf ": rf"edge={N} ename=[a-z]+ height={N} width={N} autohide={N} ontop={N} align=[a-z]+ src=[a-z]+",
    "taskbar: text ": rf"[a-z]+ x={N} base={N} fg={N} bg={N} tw={N} t=.*",
    "taskbar: field ": rf"[a-z]+ x={N} y={N} w={N} h={N} lines={N} tw={N}",
    "taskbar: strut ": rf"edge={N} size={N} rc={N}",
    "settings: rect ": rf"name=[a-z]+ x={N} y={N} w={N} h={N}(?: ax={N} ay={N})?",
    "settings: taskbar ": rf"edge=[a-z]+ height={N} width={N} autohide={N} align={N} ontop={N} wrote={N}",
    "wlib: win ": rf"id={N} x={N} y={N} w={N} h={N} cx={N} cy={N}",
    "wm: win ": rf"nr={N} id={N} z={N} layer={N} hidden={N} deco={N} x={N} y={N} w={N} h={N} focus={N} strut={N} strutedge={N} max={N} ow={N} oh={N} t=\[.*\]",
    "wm: work ": rf"x={N} y={N} w={N} h={N} nolayer={N}",
    "wm: selftest ": rf"{N} / {N}  failed=0x[0-9a-f]+  mw={N}  max={N}",
}
SCHEMA_RE = {k: re.compile(v) for k, v in SCHEMAS.items()}
KV = re.compile(r"(?:^| )([a-z_][a-z0-9_]*)=")


def schema_for(seg):
    for kind, rx in SCHEMA_RE.items():
        if seg.startswith(kind):
            return rx, seg[len(kind):]
    return None, None


def intact(seg):
    """A piece that ended at a newline: is it a whole record?"""
    rx, rest = schema_for(seg)
    if rx is not None:
        return rx.fullmatch(rest) is not None
    # no schema: a key that appears twice means a tail was glued on
    # (free text after ` t=` and a second group after a double space do not count)
    head = re.split(r" t=|  ", seg, maxsplit=1)[0]
    keys = KV.findall(head)
    return len(keys) == len(set(keys))


def pieces(line):
    """-> list of (text, ended_by_newline, starts_at_marker)."""
    ms = [m.start() for m in MARK.finditer(line)]
    if not ms:
        return [(line, True, False)]
    out = []
    if ms[0] > 0:
        out.append((line[:ms[0]], False, False))
    for i, s in enumerate(ms):
        e = ms[i + 1] if i + 1 < len(ms) else len(line)
        out.append((line[s:e], i + 1 == len(ms), True))
    return out


def clean(data):
    keep, torn = [], []
    rows = data.split(b"\n")
    if rows and rows[-1] == b"":
        rows.pop()
    for raw in rows:
        line = raw.rstrip(b"\r").decode("latin-1")
        for text, ended, marked in pieces(line):
            if not marked:
                # a plain line stays; the tail of a cut record (it is in front of a marker) goes
                (keep if ended else torn).append(text)
            elif ended and intact(text):
                keep.append(text)
            else:
                torn.append(text)
    return keep, torn


GEOM_OK = "taskbar: geom edge=3 x=696 y=0 w=104 h=600 vertical=1 thick=104 shown=1"
RECT_EDGE = "settings: rect name=edge x=216 y=100 w=81 h=30 ax=218 ay=122"


def last(lines, prefix):
    hits = [l for l in lines if l.startswith(prefix)]
    return hits[-1] if hits else None


def selftest():
    """Doctored logs. The first group must be CLEANED, the second group (the counter-proofs)
    must NOT be: a wrong value in an INTACT record has to reach the checks unchanged."""
    res = []

    def case(name, cond):
        res.append(("OK " if cond else "FAIL ") + name)

    def run(text):
        keep, torn = clean(text.encode("latin-1"))
        return keep, torn

    # 1. nested: another record lands inside the geom record. The old `tail -1 | grep -oE` took
    #    the x/y/w/h of the INNER record as the bar's geometry.
    k, t = run(GEOM_OK + "\n"
               "taskbar: geom edge=3 x=696" + RECT_EDGE + " y=0 w=104 h=600 vertical=1 thick=104 shown=1\n")
    case("nested record: the intact geom is the last geom", last(k, "taskbar: geom ") == GEOM_OK)
    case("nested record: the inner record glued to the outer tail is not believed either",
         last(k, "settings: rect") is None)
    k2, _ = run(RECT_EDGE + "\n")
    case("nested record: the same inner record alone is believed", RECT_EDGE in k2)
    case("nested record: the cut outer record is counted as torn", len(t) >= 1)
    # 2. cut in the middle of the last number: must not be believed as w=76
    k, t = run("settings: rect name=win x=20 y=3 w=760launcher: apps=6\n0 h=500\n")
    case("cut record: 'w=760' without h is not a record", last(k, "settings: rect") is None)
    case("cut record: the other program's record is kept", "launcher: apps=6" in k)
    # 3. a tail glued onto another record (duplicate key) is refused
    k, t = run("settings: preset i=6 id=tafel bg=16317180 txt=1 acc=2 base=17 fg=3 bg=16777215 tw=41 t=20:30\n")
    case("glued tail: duplicate key -> torn", not k and len(t) == 1)
    # 4. only a torn record exists: nothing is invented
    k, t = run("taskbar: geom edge=3 x=696settings: rect name=edge x=216 y=100 w=81 h=30 ax=1 ay=2\n")
    case("only a torn geom: the log has NO geom", last(k, "taskbar: geom ") is None)
    # counter-proofs: damage is dropped, a real wrong state is not
    bad_geom = GEOM_OK.replace("x=696", "x=600")
    k, t = run(bad_geom + "\n")
    case("counter-proof: an intact record with a WRONG value is kept (the check will see it)",
         last(k, "taskbar: geom ") == bad_geom and not t)
    k, t = run(GEOM_OK + "\n" + bad_geom + "\n")
    case("counter-proof: the LAST intact record wins, also when it is wrong", last(k, "taskbar: geom ") == bad_geom)
    k, t = run("settings: rect name=win x=20 y=3 w=760 h=500\n")
    case("counter-proof: a whole rect record passes", last(k, "settings: rect") is not None and not t)
    k, t = run("kernel: panic at 0x1000\nwm: hold\nsome text without a marker\n")
    case("plain lines pass unchanged", k[:2] == ["kernel: panic at 0x1000", "wm: hold"] and not t)
    for r in res:
        print(r)
    return 0 if all(r.startswith("OK") for r in res) else 1


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    if sys.argv[1] == "selftest":
        return selftest()
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    mode, src = sys.argv[1], sys.argv[2]
    data = open(src, "rb").read()
    keep, torn = clean(data)
    if mode == "check":
        print("serial: %d lines, %d torn" % (len(keep), len(torn)), file=sys.stderr)
        return 0 if not torn else 1
    if mode == "clean":
        dst = sys.argv[3]
        with open(dst, "wb") as f:
            f.write(("\n".join(keep) + "\n").encode("latin-1"))
        with open(dst + ".torn", "wb") as f:
            f.write(("\n".join(torn) + "\n").encode("latin-1"))
        print("serial: %d lines, %d torn" % (len(keep), len(torn)), file=sys.stderr)
        return 0
    return 2


if __name__ == "__main__":
    sys.exit(main())
