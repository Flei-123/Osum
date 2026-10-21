#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""STAB-1 host part: one report from two serial logs (boss VM vs test VM / QEMU).

  python3 tools/stab/report.py --boss boss.txt --test test.txt [--out report.md]

Reads the `taskbar:` and `desk:` lines of each log, judges every boot on its own (did the bar come
up: ready, STEHT geometry, health line with pins/size, icons) and then diffs the two boots by class
(conf, geometry, icons, health, shape, lang). The last line says which class explains a blank bar,
or that conf / geometry / icons are ruled out. Exit 0 = report written, 2 = a log is unreadable.
"""
import argparse
import re
import sys

VOLATILE = re.compile(r"\b(pid|t|mono|paints|gap|gen)=\S*|\bt=.*$")


def read(path):
    with open(path, "rb") as f:
        raw = f.read().decode("latin1")
    raw = re.sub(r"\x1b\[[0-9;=?]*[a-zA-Z]", "", raw).replace("\r", "")
    tb, desk, other = [], [], []
    for ln in raw.split("\n"):
        if ln.startswith("taskbar: "):
            tb.append(ln)
        elif ln.startswith("desk: "):
            desk.append(ln)
        elif re.search(r"PANIC|panic:|double fault|general protection", ln):
            other.append(ln)
    return tb, desk, other


def fields(line):
    return dict(re.findall(r"(\w+)=(\S*)", line))


def first(lines, word):
    for ln in lines:
        if ln.startswith("taskbar: " + word):
            return ln
    return None


def judge(tb, desk, other):
    f = {}
    h = first(tb, "health")
    f["health"] = fields(h) if h else None
    s = first(tb, "STEHT")
    f["steht"] = fields(s) if s else None
    f["ready"] = first(tb, "ready") is not None
    f["icons"] = fields(first(tb, "icons") or "")
    f["conf"] = fields(first(tb, "conf") or "")
    f["shape"] = fields(first(tb, "shape") or "")
    f["lang"] = fields(first(tb, "lang") or "")
    f["size"] = fields(first(tb, "size") or "")
    f["respawn"] = [d for d in desk if "respawn" in d or "killed" in d]
    f["panics"] = other
    f["bar_ok"] = bool(
        f["ready"] and f["steht"] and f["health"]
        and int(f["health"].get("pins", "0") or 0) > 0
        and int(f["health"].get("w", "0") or 0) > 0 and int(f["health"].get("h", "0") or 0) > 0)
    return f


def norm(lines):
    return {VOLATILE.sub("", ln).strip() for ln in lines}


def diff_class(a, b):
    return {k: (a.get(k), b.get(k)) for k in sorted(set(a) | set(b)) if a.get(k) != b.get(k)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--boss", required=True)
    ap.add_argument("--test", required=True)
    ap.add_argument("--out")
    a = ap.parse_args()
    try:
        bt, bd, bo = read(a.boss)
        tt, td, to = read(a.test)
    except OSError as e:
        print("report: %s" % e, file=sys.stderr)
        return 2
    jb, jt = judge(bt, bd, bo), judge(tt, td, to)
    out = []
    w = out.append
    w("# STAB-1 report: boss VM vs test VM")
    for name, j, t in (("boss", jb, bt), ("test", jt, tt)):
        w("## %s: %d taskbar lines" % (name, len(t)))
        w("- bar up: %s (ready=%s steht=%s health=%s)" % (
            "YES" if j["bar_ok"] else "NO", j["ready"], bool(j["steht"]), j["health"]))
        w("- icons: %s" % (j["icons"] or "missing"))
        w("- respawns/kills: %d, panics: %d" % (len(j["respawn"]), len(j["panics"])))
    classes = {}
    for k in ("conf", "steht", "icons", "shape", "lang", "size"):
        d = diff_class(jb[k] or {}, jt[k] or {})
        for vol in ("keys", "dateien", "kleinste", "marks"):
            d.pop(vol, None) if k in ("icons", "lang") else None
        classes[k] = d
    classes["health"] = diff_class({k: v for k, v in (jb["health"] or {}).items() if k not in ("paints", "mono")},
                                   {k: v for k, v in (jt["health"] or {}).items() if k not in ("paints", "mono")})
    w("## diff by class (boss, test)")
    for k, d in classes.items():
        w("- %s: %s" % (k, "same" if not d else "; ".join("%s boss=%s test=%s" % (f, x, y) for f, (x, y) in d.items())))
    only_b = sorted(norm(bt) - norm(tt))
    only_t = sorted(norm(tt) - norm(bt))
    w("## lines only in boss (%d)" % len(only_b))
    out.extend("- " + x for x in only_b[:40])
    w("## lines only in test (%d)" % len(only_t))
    out.extend("- " + x for x in only_t[:40])
    # verdict
    if jb["bar_ok"]:
        verdict = "boss bar came up in this boot; no blank bar reproduced (run more cold boots)"
    elif not jb["ready"] and not jb["steht"]:
        verdict = "boss: taskbar never got to ready/STEHT -> died or hung before painting (look at desk: lines, panics)"
    elif classes["conf"]:
        verdict = "boss differs in conf: " + ", ".join(classes["conf"])
    elif classes["steht"] or classes["size"]:
        verdict = "boss differs in geometry: " + ", ".join(list(classes["steht"]) + list(classes["size"]))
    elif classes["icons"]:
        verdict = "boss differs in icons: " + ", ".join(classes["icons"])
    elif jb["health"] is None:
        verdict = "boss never printed the health line (bar loop did not run) although ready"
    else:
        verdict = "conf, geometry and icons ruled out (same as test); health pins/size: %s" % jb["health"]
    w("## verdict")
    w("- " + verdict)
    text = "\n".join(out) + "\n"
    if a.out:
        with open(a.out, "w") as f:
            f.write(text)
    sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
