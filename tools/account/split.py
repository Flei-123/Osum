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
    zeilen = text.split("\n")
    in_ = False
    raus = set()
    for i, z in enumerate(zeilen, 1):
        if z.startswith(BRAND_AUF):
            in_ = True
        if in_:
            raus.add(i)
        if in_ and re.match(BRAND_ZU, z):
            in_ = False
    return raus


def kommentarfrei(zeile):
    i = zeile.find("//")
    return zeile if i < 0 else zeile[:i]


def check(wurzel):
    verstoesse = []
    geprueft = 0
    for rel in ALLGEMEIN:
        pfad = os.path.join(wurzel, rel)
        if not os.path.exists(pfad):
            verstoesse.append((rel, 0, "die Datei fehlt"))
            continue
        text = open(pfad, encoding="utf-8").read()
        erlaubt = lines_der_anmeldung(text) if rel.endswith(("konto.fi", "account.fi")) \
            else set()
        for nr, zeile in enumerate(text.split("\n"), 1):
            geprueft += 1
            if nr in erlaubt:
                continue
            code = kommentarfrei(zeile).lower()
            if code.strip().startswith("import "):
                continue
            for w in WOERTER:
                if w in code:
                    verstoesse.append((rel, nr, w))
    return verstoesse, geprueft


def push_nums(wurzel):
    aus = []
    for rel in PUSH:
        pfad = os.path.join(wurzel, rel)
        if not os.path.exists(pfad):
            continue
        text = open(pfad, encoding="utf-8").read()
        n = 0
        for zeile in text.split("\n"):
            code = kommentarfrei(zeile).lower()
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
    wurzel = sys.argv[1]
    zahlen = "--zahlen" in sys.argv
    verstoesse, geprueft = check(wurzel)
    if zahlen:
        print("geprueft=%d dateien=%d verstoesse=%d"
              % (geprueft, len(ALLGEMEIN), len(verstoesse)))
        for rel, n, k in push_nums(wurzel):
            print("ruecken %s zeilen=%d anbieterzeilen=%d" % (rel, n, k))
    for rel, nr, w in verstoesse:
        print("VERSTOSS %s:%d -- '%s' im allgemeinen Teil" % (rel, nr, w))
    return 1 if verstoesse else 0


if __name__ == "__main__":
    sys.exit(main())
