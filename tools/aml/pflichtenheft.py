#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import glob
import os
import re
import subprocess
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HIER))
sys.path.insert(0, HIER)


def kannliste(path_2=None):
    path_2 = path_2 or os.path.join(ROOT, "kernel", "aml.fi")
    s = open(path_2, encoding="utf-8", errors="replace").read()
    m = re.search(r"fn report_can\(state: u64\) \{(.*?)\n\}", s, re.S)
    if not m:
        raise SystemExit("report_can nicht in %s gefunden" % path_2)
    body = m.group(1)
    can = set()
    for v in re.findall(r"ops\[\d+\] = (0x[0-9A-Fa-f]+) as u8", body):
        can.add(int(v, 16))
    for v in re.findall(r"ext\[\d+\] = (0x[0-9A-Fa-f]+) as u8", body):
        can.add(0x5B00 | int(v, 16))
    for o in range(0x60, 0x6F):
        can.add(o)
    for o in range(0x93, 0x96):
        can.add(0x9200 | o)
    return can


def uebersetzen():
    asl = os.path.join(HIER, "asl")
    if not os.path.isdir(asl):
        return []
    if not shutil_which("iasl"):
        print("NOTE: iasl missing -- the rebuilt tables will")
        print("         uebersprungen. `apt-get install acpica-tools`.")
        return []
    out = []
    for src in sorted(glob.glob(os.path.join(asl, "*.asl"))):
        target = src[:-4] + ".aml"
        r = subprocess.run(["iasl", "-p", src[:-4], src],
                           capture_output=True, text=True)
        if r.returncode != 0 or not os.path.exists(target):
            print("WARNUNG: iasl scheiterte an %s" % os.path.basename(src))
            continue
        out.append(target)
    return out


def shutil_which(x):
    from shutil import which
    return which(x)


def main(argv):
    import disasm

    tabellen = argv[1:]
    if not tabellen:
        tabellen = uebersetzen()
        tabellen += sorted(glob.glob(os.path.join(HIER, "brett", "*.bin")))
        tabellen += sorted(glob.glob(os.path.join(HIER, "brett", "*.aml")))
    if not tabellen:
        print("no tables -- nothing to measure")
        return 1

    can = kannliste()
    print("THE CAN-LIST OF THE INTERPRETER (kernel/acpi/aml.fi, report_can)")
    print("  %d Opcodes: %d einfache, %d erweiterte (0x5b), %d Paare (0x92)"
          % (len(can),
             len([x for x in can if x < 0x5B00]),
             len([x for x in can if 0x5B00 <= x < 0x9200]),
             len([x for x in can if x >= 0x9200])))
    print()

    gesamt = {}
    schlimm = set()
    for t in tabellen:
        names, count, errors, _m = disasm.parse_tables([t])
        if not count:
            continue
        missing = sorted(set(count) - can)
        for op, n in count.items():
            gesamt[op] = gesamt.get(op, 0) + n
        schlimm |= set(missing)
        short = os.path.basename(t)
        deck = 100 * len(set(count) & can) // max(1, len(count))
        print("%-22s %3d verschiedene Opcodes, Abdeckung %3d%%%s"
              % (short, len(count), deck,
                 "" if not missing else "   FEHLT: " +
                 ", ".join(disasm.op_text(o) for o in missing)))
        wichtig = [n for n, k, e in names
                   if n.split(".")[-1] in
                   ("_LID", "_BST", "_BIF", "_BIX", "_PSR", "_STA", "_PRW")
                   or re.search(r"_[LEQ][0-9A-F]{2}$", n.split(".")[-1])]
        if wichtig:
            print("        Ereignisnamen: " + ", ".join(sorted(
                set(w.split(".")[-1] for w in wichtig))))

    print()
    print("TOGETHER over all tables: %d different opcodes, %d pieces"
          % (len(gesamt), sum(gesamt.values())))
    if schlimm:
        print("NICHT ABGEDECKT (%d):" % len(schlimm))
        for op in sorted(schlimm):
            print("  %-34s %6d mal" % (disasm.op_text(op), gesamt.get(op, 0)))
        return 2
    print("NOT COVERED: none.")
    print()
    print("FINDING: for power button, lid and battery NO further opcode")
    print("is needed. What is missing is not in the language, but")
    print("in der Umgebung -- siehe docs/RUNDE-ACPI-EREIGNISSE.md:")
    print("  * der Adressraum EmbeddedControl (OperationRegion),")
    print("  * `_OSI` als aufrufbare Methode,")
    print("  * and above all the whole path SCI -> GPE -> `_Lxx` -> Notify.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
