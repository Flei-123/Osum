#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import sys

ALLGEMEIN = [
    "kernel/app/provider.fi",
    "kernel/app/knetz.fi",
    "kernel/app/kspeicher.fi",
    "kernel/app/ksiegel.fi",
    "kernel/app/kjson.fi",
    "kernel/app/kmsg.fi",
    "kernel/app/kgegen.fi",
    "kernel/app/kjwt.fi",
    "kernel/app/account.fi",
]

PUSH = ["kernel/app/prov_jarvis.fi", "kernel/app/prov_xoffi.fi",
           "kernel/app/prov_own.fi", "kernel/app/prov_fleitec.fi"]

WOERTER = ["xoffi", "jarvis", "fleitec", "nexus"]

BRAND_AUF = "fn push_login"
BRAND_ZU = "^}"


def lines_der_anmeldung(text):
    lines = text.split("\n")
    in_ = False
    raus = set()
    for i, z in enumerate(lines, 1):
        if z.startswith(BRAND_AUF):
            in_ = True
        if in_:
            raus.add(i)
        if in_ and re.match(BRAND_ZU, z):
            in_ = False
    return raus


def kommentarfrei(line):
    i = line.find("//")
    return line if i < 0 else line[:i]


def check(root):
    verstoesse = []
    geprueft = 0
    for rel in ALLGEMEIN:
        path_2 = os.path.join(root, rel)
        if not os.path.exists(path_2):
            verstoesse.append((rel, 0, "die Datei fehlt"))
            continue
        text = open(path_2, encoding="utf-8").read()
        erlaubt = lines_der_anmeldung(text) if rel.endswith(("konto.fi", "account.fi")) \
            else set()
        for nr, line in enumerate(text.split("\n"), 1):
            geprueft += 1
            if nr in erlaubt:
                continue
            code = kommentarfrei(line).lower()
            if code.strip().startswith("import "):
                continue
            for w in WOERTER:
                if w in code:
                    verstoesse.append((rel, nr, w))
    return verstoesse, geprueft


def push_nums(root):
    aus = []
    for rel in PUSH:
        path_2 = os.path.join(root, rel)
        if not os.path.exists(path_2):
            continue
        text = open(path_2, encoding="utf-8").read()
        n = 0
        for line in text.split("\n"):
            code = kommentarfrei(line).lower()
            for w in WOERTER:
                if w in code:
                    n += 1
                    break
        aus.append((rel, len(text.split("\n")), n))
    return aus


def main():
    if len(sys.argv) < 2:
        print("split.py <wurzel> [--zahlen]")
        return 2
    root = sys.argv[1]
    zahlen = "--zahlen" in sys.argv
    verstoesse, geprueft = check(root)
    if zahlen:
        print("geprueft=%d dateien=%d verstoesse=%d"
              % (geprueft, len(ALLGEMEIN), len(verstoesse)))
        for rel, n, k in push_nums(root):
            print("ruecken %s zeilen=%d anbieterzeilen=%d" % (rel, n, k))
    for rel, nr, w in verstoesse:
        print("VERSTOSS %s:%d -- '%s' im allgemeinen Teil" % (rel, nr, w))
    return 1 if verstoesse else 0


if __name__ == "__main__":
    sys.exit(main())
