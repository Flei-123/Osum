#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    bundle.py <assets/apps> <arbeitsverzeichnis> [only=<programmliste>]
    bundle.py --lint <assets/apps>      (host check: every bundle has INFO, start.txt, data/README, a symbol)
"""

import os
import shutil
import subprocess
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HIER)
import symjoin  # noqa: E402


INFO_LIMIT = 1023


def angaben_stehen_vorn(file_path):
    roh = open(file_path, "rb").read()
    last_item = -1
    for line_text in (b"name=", b"info=", b"keys=", b"revision=", b"fassung=", b"net=",
                  b"exec=", b"icon="):
        p = roh.find(line_text)
        if p > last_item:
            last_item = p
    if last_item < 0:
        return (0, INFO_LIMIT)
    ende = roh.find(b"\n", last_item)
    return (len(roh) if ende < 0 else ende, INFO_LIMIT)


def start_von(file_path):
    for line_text in open(os.path.join(file_path, "start.txt"), encoding="ascii"):
        line_text = line_text.strip()
        if line_text and not line_text.startswith("#"):
            return line_text
    raise SystemExit("buendel: %s/start.txt nennt kein Programm" % file_path)


def console_von(file_path):
    return os.path.isfile(os.path.join(file_path, "console.txt"))


REQUIRED_FILES = ("INFO", "start.txt", os.path.join("data", "README"))


def lint_bundle(path):
    problems = []
    for rel in REQUIRED_FILES:
        if not os.path.isfile(os.path.join(path, rel)):
            problems.append("%s: missing %s" % (path, rel))
    has_symbol = (os.path.isfile(os.path.join(path, "symbol.osym"))
                  or os.path.isfile(os.path.join(path, "symbol.txt")))
    if not has_symbol:
        problems.append("%s: missing symbol.osym or symbol.txt" % path)
    return problems


def lint_all(source):
    problems = []
    for name in sorted(os.listdir(source)):
        if name.endswith(".osp"):
            problems.extend(lint_bundle(os.path.join(source, name)))
    return problems


def main(argv):
    if len(argv) >= 3 and argv[1] == "--lint":
        problems = lint_all(argv[2])
        for line in problems:
            print("bundle lint: " + line, file=sys.stderr)
        print("bundle lint: %d problem(s)" % len(problems))
        return 1 if problems else 0
    if len(argv) < 3:
        print(__doc__)
        return 2
    source_dir, arbeit = argv[1], argv[2]
    problems = lint_all(source_dir)
    if problems:
        for line in problems:
            print("bundle lint: " + line, file=sys.stderr)
        return 1
    only = None
    for a in argv[3:]:
        if a.startswith("nur="):
            only = set("/bin/" + w for w in a[4:].split())
    os.makedirs(arbeit, exist_ok=True)
    line_list = ["/apps/"]
    for name in sorted(os.listdir(source_dir)):
        if not name.endswith(".osp"):
            continue
        file_path = os.path.join(source_dir, name)
        if only is not None and start_von(file_path) not in only:
            continue
        ende, limit = angaben_stehen_vorn(os.path.join(file_path, "INFO"))
        if ende >= limit:
            print("bundle: %s/INFO -- the entries end only at octet %d,"
                  " appdir.eine_datei liest nur %d. Der Starter wuerde dieses"
                  " Buendel stumm uebergehen. Kommentar hinter die Angaben."
                  % (file_path, ende, limit), file=sys.stderr)
            return 1
        target_dir = "/apps/%s" % name
        line_list.append(target_dir + "/")
        line_list.append("%s/INFO=%s" % (target_dir, os.path.join(file_path, "INFO")))
        sym = os.path.join(arbeit, name + ".symbol")
        fertig = os.path.join(file_path, "symbol.osym")
        if os.path.isfile(os.path.join(file_path, "symbol.svg")) and not os.path.isfile(fertig):
            print("bundle: %s has symbol.svg but no baked symbol.osym (run tools/svg/apps.sh)" % file_path, file=sys.stderr)
            return 1
        if os.path.isfile(fertig):
            with open(sym, "wb") as out:
                out.write(symjoin.joined(file_path))
        else:
            r = subprocess.run([sys.executable, os.path.join(HIER, "icon.py"),
                                os.path.join(file_path, "symbol.txt"), sym],
                               capture_output=True, text=True)
            if r.returncode != 0:
                print(r.stdout + r.stderr, file=sys.stderr)
                return 1
        line_list.append("%s/symbol=%s" % (target_dir, sym))
        brand_name = os.path.join(arbeit, "SYSTEM")
        if not os.path.exists(brand_name):
            with open(brand_name, "w") as f:
                f.write("shipped with the {{PRODUCT}} image; see docs/ACTION-BUS.md 5.2\n")
        line_list.append("%s/SYSTEM=%s" % (target_dir, brand_name))
        line_list.append("%s/data/" % target_dir)
        line_list.append("%s/data/README=%s"
                      % (target_dir, os.path.join(file_path, "data", "README")))
        if (console_von(file_path) and only is not None and "/bin/term" in only
                and not os.environ.get("OSUM_NOCONSOLE")):
            skript = os.path.join(arbeit, name + ".start")
            with open(skript, "w") as f:
                f.write("#!/bin/term -c%s\n" % start_von(file_path))
            line_list.append("%s/start=%s" % (target_dir, skript))
        else:
            line_list.append("%s/start@%s" % (target_dir, start_von(file_path)))
    for z in line_list:
        print(z)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
