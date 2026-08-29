#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/themestore/model.py -- a preset, resolved ON THE HOST.

`tools/theme/model.py` is the second implementation of the token
system: it resolves the same three layers in Python that
`kernel/user/wlibc.fi` resolves in Firn, and the two are compared token
for token.  This file adds the one step a PRESET needs on top: read the
seven keys, pick the scheme file they name, and hand the answer to that
same resolver.

It exists so that `tools/themestore/run.sh` can say "the system and the
host compute the same contrast" and mean it.  It does not re-implement
the arithmetic; if it did, the comparison would be worthless.

    model.py pair <preset>              -> "<txt> <min>"   (hundredths)
    model.py pairscheme <scheme> <mode> [accent]
    model.py onepair <preset> <fg> <bg> -> one ratio, hundredths
    model.py table <preset> [<preset> ...]  the documentation table
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
spec = importlib.util.spec_from_file_location(
    "thememodel", os.path.join(ROOT, "tools", "theme", "model.py"))
M = importlib.util.module_from_spec(spec)
spec.loader.exec_module(M)

# THE SEVENTEEN PAIRINGS, in the order `wlibc.pairs_init` puts them in.
# Two lists that have to agree is exactly the sort of thing that drifts,
# so `run.sh` compares them index by index and not as a set.
PAIRS = [p for p in M.TEXT_PAIRS if p[2] == "normal"]


def read_preset(path):
    out = {"name": "", "scheme": "day", "mode": "auto", "shape": "",
           "accent": "", "edge": "bottom", "align": "left"}
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip()
    return out


def resolve_of(scheme_path, mode, accent):
    sch = M.read_scheme(scheme_path)
    if mode == "auto":
        mode = sch.get("mode", "light")
    return M.resolve(sch, mode == "dark", accent or None)


def numbers(res):
    sem = res["sem"]
    txt = M.contrast100(sem[M.S["text-primary"]], sem[M.S["surface"]])
    rs = [M.contrast100(sem[M.S[fg]], sem[M.S[bg]]) for fg, bg, _ in PAIRS]
    return txt, min(rs), rs


def scheme_path(name):
    return os.path.join(ROOT, "assets", "schemes", "%s.scheme" % name)


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    cmd = argv[1]
    if cmd == "pair":
        p = read_preset(argv[2])
        res = resolve_of(scheme_path(p["scheme"]), p["mode"], p["accent"])
        txt, mn, _ = numbers(res)
        print("%d %d" % (txt, mn))
        return 0
    if cmd == "pairscheme":
        mode = argv[3] if len(argv) > 3 else "light"
        acc = argv[4] if len(argv) > 4 else ""
        res = resolve_of(argv[2], mode, acc)
        txt, mn, _ = numbers(res)
        print("%d %d" % (txt, mn))
        return 0
    if cmd == "onepair":
        p = read_preset(argv[2])
        res = resolve_of(scheme_path(p["scheme"]), p["mode"], p["accent"])
        fg, bg = argv[3], argv[4]
        print(M.contrast100(res["sem"][M.S[fg]], res["sem"][M.S[bg]]))
        return 0
    if cmd == "table":
        print("| Vorlage | Schema | Modus | Form | Akzent | Kante | "
              "Ausricht. | Text auf Grund | schlechtestes Textpaar | Latte |")
        print("|---|---|---|---|---|---|---|---|---|---|")
        for path in argv[2:]:
            p = read_preset(path)
            sch = M.read_scheme(scheme_path(p["scheme"]))
            res = resolve_of(scheme_path(p["scheme"]), p["mode"], p["accent"])
            txt, mn, _ = numbers(res)
            bar = 700 if sch.get("contrast") == "high" else 450
            print("| **%s** | `%s` | %s | %s | %s | %s | %s | %.2f:1 | "
                  "**%.2f:1** | %.1f:1 |"
                  % (p["name"], p["scheme"], p["mode"], p["shape"],
                     p["accent"] or "(Schema)", p["edge"], p["align"],
                     txt / 100.0, mn / 100.0, bar / 100.0))
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
