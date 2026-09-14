#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/aml/pflichtenheft.py -- WELCHE AML-OPCODES DIE EREIGNISSE BRAUCHEN.

WARUM ES DIESES PROGRAMM GIBT.

Ein vollstaendiger AML-Interpreter ist eine Lebensaufgabe: die
Spezifikation kennt weit ueber zweihundert Opcodes, und die
Betriebssysteme, die AML wirklich ausfuehren, haben dafuer je eine
sechsstellige Zahl von Zeilen liegen.  Osum braucht drei Dinge --
Einschalttaste, Deckel, Akku -- und nicht mehr.

Die Frage ist also nicht "wie baut man einen AML-Interpreter", sondern
"WELCHEN AUSSCHNITT muss er koennen, damit diese drei Dinge gehen".
Das ist eine MESSUNG und keine Schaetzung, und sie laeuft wie das
Pflichtenheft des Assemblers in Runde ASM: nicht raten, welche Befehle
vorkommen koennten, sondern die Tabellen nehmen, die es wirklich gibt,
und zaehlen.

WAS GEZAEHLT WIRD

  1. Die Tabellen von QEMU (`tools/aml/run.sh` zieht sie mit `amldump`
     aus der laufenden Maschine).  Das ist die Grundlage, auf der hier
     gemessen werden KANN.
  2. Nachgebaute Laptop-Tabellen unter `tools/aml/asl/`.  Sie stehen im
     Repo als ASL-Quelltext und werden mit `iasl` uebersetzt; sie bilden
     nach, was auf einem echten Brett in der DSDT steht -- ein Deckel
     (`_LID`), ein Akku (`_BST`/`_BIF`/`_BIX`), eine Einschalttaste und
     die GPE-Methoden `_Lxx`/`_Exx`/`_Qxx`, die beim Ereignis laufen.

     DAS IST EIN NACHBAU UND KEIN BRETT.  Er ist nach ACPI 6.4 Kapitel
     9.4, 10.2 und 5.6.4 geschrieben und deckt ab, was die Fassungen
     dieser Kapitel verlangen -- aber eine echte Firmware darf mehr
     tun, und was Justins Brett wirklich hinlegt, weiss erst, wer es
     dort ausliest.  `tools/aml/brett.sh` ist der Weg dafuer.

  3. Was der Interpreter KANN, wird nicht abgeschrieben, sondern aus
     `kernel/aml.fi` (Funktion `report_can`) ABGELESEN -- derselben
     Liste, die er zur Laufzeit auf die serielle Leitung legt.

Aufruf:
    python3 tools/aml/pflichtenheft.py [TABELLE.aml ...]

Ohne Argumente werden die uebersetzten Tabellen unter tools/aml/asl/
genommen (und, falls vorhanden, alles unter tools/aml/brett/).
"""
import glob
import os
import re
import subprocess
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
WURZEL = os.path.dirname(os.path.dirname(HIER))
sys.path.insert(0, HIER)


def kannliste(pfad=None):
    """Die KANN-Liste aus kernel/aml.fi ablesen."""
    pfad = pfad or os.path.join(WURZEL, "kernel", "aml.fi")
    s = open(pfad, encoding="utf-8", errors="replace").read()
    m = re.search(r"fn report_can\(state: u64\) \{(.*?)\n\}", s, re.S)
    if not m:
        raise SystemExit("report_can nicht in %s gefunden" % pfad)
    body = m.group(1)
    can = set()
    for v in re.findall(r"ops\[\d+\] = (0x[0-9A-Fa-f]+) as u8", body):
        can.add(int(v, 16))
    for v in re.findall(r"ext\[\d+\] = (0x[0-9A-Fa-f]+) as u8", body):
        can.add(0x5B00 | int(v, 16))
    for o in range(0x60, 0x6F):      # Local0..7, Arg0..6
        can.add(o)
    for o in range(0x93, 0x96):      # LNotEqual/LLessEqual/LGreaterEqual
        can.add(0x9200 | o)
    return can


def uebersetzen():
    """Die ASL-Quellen unter tools/aml/asl/ mit iasl uebersetzen."""
    asl = os.path.join(HIER, "asl")
    if not os.path.isdir(asl):
        return []
    if not shutil_which("iasl"):
        print("HINWEIS: iasl fehlt -- die nachgebauten Tabellen werden")
        print("         uebersprungen. `apt-get install acpica-tools`.")
        return []
    out = []
    for src in sorted(glob.glob(os.path.join(asl, "*.asl"))):
        ziel = src[:-4] + ".aml"
        r = subprocess.run(["iasl", "-p", src[:-4], src],
                           capture_output=True, text=True)
        if r.returncode != 0 or not os.path.exists(ziel):
            print("WARNUNG: iasl scheiterte an %s" % os.path.basename(src))
            continue
        out.append(ziel)
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
        print("keine Tabellen -- nichts zu messen")
        return 1

    can = kannliste()
    print("DIE KANN-LISTE DES INTERPRETERS (kernel/aml.fi, report_can)")
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
        fehlt = sorted(set(count) - can)
        for op, n in count.items():
            gesamt[op] = gesamt.get(op, 0) + n
        schlimm |= set(fehlt)
        kurz = os.path.basename(t)
        deck = 100 * len(set(count) & can) // max(1, len(count))
        print("%-22s %3d verschiedene Opcodes, Abdeckung %3d%%%s"
              % (kurz, len(count), deck,
                 "" if not fehlt else "   FEHLT: " +
                 ", ".join(disasm.op_text(o) for o in fehlt)))
        # Die Namen, um die es in dieser Runde geht.
        wichtig = [n for n, k, e in names
                   if n.split(".")[-1] in
                   ("_LID", "_BST", "_BIF", "_BIX", "_PSR", "_STA", "_PRW")
                   or re.search(r"_[LEQ][0-9A-F]{2}$", n.split(".")[-1])]
        if wichtig:
            print("        Ereignisnamen: " + ", ".join(sorted(
                set(w.split(".")[-1] for w in wichtig))))

    print()
    print("ZUSAMMEN ueber alle Tabellen: %d verschiedene Opcodes, %d Stueck"
          % (len(gesamt), sum(gesamt.values())))
    if schlimm:
        print("NICHT ABGEDECKT (%d):" % len(schlimm))
        for op in sorted(schlimm):
            print("  %-34s %6d mal" % (disasm.op_text(op), gesamt.get(op, 0)))
        return 2
    print("NICHT ABGEDECKT: keine.")
    print()
    print("BEFUND: fuer Einschalttaste, Deckel und Akku braucht es KEINEN")
    print("weiteren Opcode. Was fehlt, liegt nicht in der Sprache, sondern")
    print("in der Umgebung -- siehe docs/RUNDE-ACPI-EREIGNISSE.md:")
    print("  * der Adressraum EmbeddedControl (OperationRegion),")
    print("  * `_OSI` als aufrufbare Methode,")
    print("  * und vor allem der ganze Weg SCI -> GPE -> `_Lxx` -> Notify.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
