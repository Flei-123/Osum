#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/vielkern/einkern.py -- DIE EIN-KERN-RESTE, AN DER QUELLE GEZAEHLT.

    einkern.py [--liste] [--nur <datei.fi>]

WORUM ES GEHT. Ein Puffer in der Datenseite (`state + kstate.X_OFF`)
gehoert der GANZEN MASCHINE. Solange nur ein Kern darin arbeitet, ist
das die billigste und schnellste Loesung, die es gibt -- kein
Allokator, keine Sperre, kein Stapelplatz. Sobald zwei Kerne
gleichzeitig hineinschreiben, ist es ein stiller Datenverlust: der eine
liest heraus, was der andere hineingelegt hat, und beide halten das
Ergebnis fuer ihres.

Es ist dieselbe Fehlerform wie `KSTACK_CUR` (Runde VIELKERN 1) und wie
`fs.buf_in` (Runde VIELKERN 3) -- ein Wort fuer die ganze Maschine, das
nur deshalb hielt, weil nie zwei Kerne gleichzeitig hinsahen. Seit
`r3alle` sehen sie hin.

WAS DAS WERKZEUG TUT. Es liest die Kernquellen, findet jede Funktion,
die einen solchen Puffer als ARBEITSFLAECHE nimmt (also `let x: u64 =
state + kstate.<NAME>_OFF ...`), und fragt fuer jede: liegt zwischen
dem Betreten der Funktion und dem Gebrauch des Puffers eine Sperre?

Bekannte Sperren:
  * `fs.enter(state)` / `enter(state)`  -> atomic.L_FS
  * `atomic.lock_take(state, ...)`      -> die genannte Sperre
  * `serial.zeile_an(...)`              -> die Zeilensperre aus
    VIELKERN 3, je Kern wiedereintrittsfaehig und begrenzt. Sie ist
    seit Runde MERGE-6 auch der Riegel um den Ausgabeweg aus Ring 3
    (`sys.conout`), und sie deckt dort BEIDES ab: den geteilten Puffer
    und die Reihenfolge der Zeichen.
  * `sched.irq_save()` allein zaehlt NICHT. Sie haelt die
    Unterbrechungen DIESES Kerns an und sagt ueber den Nachbarkern
    nichts aus. Genau dieser Irrtum steht in mehreren Kommentaren des
    Baums.

WAS ES NICHT KANN. Es liest Text und keine Ablaeufe. Eine Funktion, die
ihren Puffer nur unter einer Sperre BEKOMMT (weil jeder Aufrufer sie
haelt), steht hier trotzdem -- und eine, die ihn nur auf einem Kern
benutzt, auch. Deshalb gibt es zwei Listen: `GESPERRT` und `OFFEN`, und
`OFFEN` ist eine Liste zum ANSEHEN, keine Fehlerliste. Die Zahl darunter
ist der Vertrag: sie darf nicht wachsen, ohne dass jemand es aufschreibt.
"""
import os
import re
import sys

WURZEL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")

# Die Puffer der Datenseite, die als ARBEITSFLAECHE benutzt werden --
# nicht die Tafeln (TASK_OFF, CPU_OFF, WM_OFF ...), die je Eintrag
# gehoeren, sondern die, in die geschrieben und gleich danach wieder
# gelesen wird.
PUFFER = re.compile(
    r"state\s*\+\s*kstate\.("
    r"NAME_OFF|BLOCK_OFF|EARG_OFF|FS_OFF|OFS3_OFF|LOAD_OFF|CONSOLE_OFF"
    r")")

SPERRE = re.compile(r"\benter\(state\)|\bfs\.enter\(|atomic\.lock_take\("
                    r"|serial\.zeile_an\(")

# Diese Dateien laufen nachweislich nur auf einem Kern oder nur vor dem
# Start der Anwendungskerne. Sie stehen mit BEGRUENDUNG hier und nicht
# als stille Ausnahme.
RUHIG = {
    "kmain.fi": "laeuft vor smp.probe, also bevor es zweite Kerne gibt",
}


def funktionen(pfad):
    """{name: [zeilen]} -- die Funktionen einer Firn-Datei."""
    roh = open(pfad, "rb").read().decode("utf-8", "surrogateescape")
    aus = {}
    name = None
    leib = []
    for z in roh.split("\n"):
        m = re.match(r"^fn (\w+)\(", z)
        if m:
            if name:
                aus[name] = leib
            name = m.group(1)
            leib = []
        elif name is not None:
            if z == "}":
                aus[name] = leib
                name = None
                leib = []
            else:
                leib.append(z)
    if name:
        aus[name] = leib
    return aus


def main(argv):
    liste = "--liste" in argv
    nur = None
    for i, a in enumerate(argv):
        if a == "--nur" and i + 1 < len(argv):
            nur = argv[i + 1]

    gesperrt = []
    offen = []
    for wurzel, _, dateien in os.walk(os.path.join(WURZEL, "kernel")):
        for d in sorted(dateien):
            if not d.endswith(".fi"):
                continue
            if nur and d != nur:
                continue
            pfad = os.path.join(wurzel, d)
            kurz = os.path.relpath(pfad, WURZEL)
            for fn, leib in sorted(funktionen(pfad).items()):
                text = "\n".join(leib)
                treffer = PUFFER.findall(text)
                if not treffer:
                    continue
                eintrag = (kurz, fn, sorted(set(treffer)))
                if SPERRE.search(text) or d in RUHIG:
                    gesperrt.append(eintrag)
                else:
                    offen.append(eintrag)

    if liste:
        print("== GESPERRT: der Puffer wird unter einer Sperre benutzt ==")
        for k, f, p in gesperrt:
            print("   %-24s %-22s %s" % (k, f, ",".join(p)))
        print()
        print("== OFFEN: kein Sperrwort im Rumpf ==")
        for k, f, p in offen:
            print("   %-24s %-22s %s" % (k, f, ",".join(p)))
        print()
    dat_offen = sorted(set(k for k, _, _ in offen))
    print("einkern gesperrt=%d offen=%d dateien=%s"
          % (len(gesperrt), len(offen), ",".join(dat_offen) or "-"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
