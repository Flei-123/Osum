#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/kernel/syscalls.py -- DIE AUFRUFNUMMERN, GEGENGELESEN.

WARUM ES DIESES PROGRAMM GIBT, in einem Satz: in Runde MERGE hatten
zwei Zweige unabhaengig voneinander die Nummer 1320 vergeben, und
gemerkt hat es niemand, bis das Verschmelzen zwei `if number == ...`
mit demselben Wert nebeneinanderstellte -- der zweite war ab da tot.
Der Kommentar darueber steht bis heute in `kernel/sys.fi` bei
`SYS_OSUM_HOTKEY`.

Eine Nummer doppelt zu vergeben ist der einzige Fehler dieser Art, der
sich NICHT durch Ausprobieren findet: der Kernel baut, der Testlauf ist
gruen, und genau ein Aufruf tut still etwas anderes als er soll. Also
wird er nicht ausprobiert, sondern nachgezaehlt -- vor dem Bauen, aus
dem Quelltext, in beiden Tabellen.

DIE BEIDEN TABELLEN. Osum hat zwei Listen derselben Zahlen:

    kernel/sys.fi        was der Kernel annimmt (`dispatch`)
    lib/libc/kcall.fi    was Ring 3 losschickt

Sie muessen uebereinstimmen, und sie stehen absichtlich getrennt: die
libc ist eine Bibliothek und kein Teil des Kernels. Zwei Listen sind
zwei Gelegenheiten, sich zu unterscheiden -- dieses Programm ist die
dritte Stelle, die beide gegeneinander haelt, und die einzige, die
nichts anderes tut.

WAS GEPRUEFT WIRD

  1. KEINE NUMMER ZWEIMAL, in keiner der beiden Dateien. Das ist die
     Pruefung, wegen der es das Programm gibt.
  2. KEIN NAME MIT ZWEI NUMMERN. Steht `SYS_OSUM_SHARE` im Kernel auf
     1322 und in der libc auf 1320, ruft Ring 3 ins Leere.
  3. KEINE NUMMER MIT ZWEI NAMEN, auch wenn beide dieselbe meinen --
     ein zweiter Name fuer dieselbe Nummer ist der Anfang genau des
     Fehlers, der oben steht.
  4. WAS IN DER LIBC STEHT, MUSS DER KERNEL KENNEN. Andersherum nicht:
     der Kernel darf Aufrufe haben, fuer die es noch keine Huelle gibt.

DIE AUSNAHMEN, und jede mit einem Grund, nicht mit einem Achselzucken:

  SYS_MARK (1), SYS_LEAVE (2)   Sie sind KEINE Aufrufnummern. Sie
      gelten nur waehrend der Exkursion von Runde 59
      (`kstate.EXCURSION`), also in einem Zustand, in dem der Kernel
      ueberhaupt keine gewoehnlichen Aufrufe annimmt -- `dispatch`
      fragt sie ab, BEVOR es irgendetwas anderes ansieht, und kehrt
      zurueck. Sie teilen sich die Zahlen deshalb absichtlich mit
      `SYS_WRITE` und `SYS_OPEN`.

Aufruf:
    python3 tools/kernel/syscalls.py            prueft
    python3 tools/kernel/syscalls.py --liste    schreibt die Tabelle
    python3 tools/kernel/syscalls.py --frei 1200 1300
                                                zeigt die freien Nummern
                                                in einem Bereich
    python3 tools/kernel/syscalls.py --zweige   dasselbe ueber ALLE
                                                Zweige des Repos (git),
                                                damit eine neue Nummer
                                                auch dann frei ist, wenn
                                                eine andere Runde gerade
                                                parallel laeuft
"""
import os
import re
import subprocess
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
WURZEL = os.path.dirname(os.path.dirname(HIER))

KERN = "kernel/sys.fi"
LIBC = "lib/libc/kcall.fi"

# Namen, die aussehen wie eine Aufrufnummer und keine sind. Der Grund
# steht oben im Kopf; er gehoert dazu, sonst ist eine Ausnahmeliste nur
# eine Liste der Faelle, die jemand nicht verstehen wollte.
KEINE_NUMMER = {
    "SYS_MARK": "Marke der Exkursion (Runde 59), gilt nur bei EXCURSION",
    "SYS_LEAVE": "Marke der Exkursion (Runde 59), gilt nur bei EXCURSION",
}

MUSTER = re.compile(
    r"^[ \t]*const[ \t]+(SYS_[A-Z0-9_]+)[ \t]*:[ \t]*u64[ \t]*=[ \t]*(\d+)",
    re.M)


def lies(pfad):
    """Alle `const SYS_...: u64 = <zahl>` einer Datei, Zeile mitgezaehlt."""
    with open(pfad, "rb") as f:
        roh = f.read().decode("latin1")
    aus = {}
    for m in MUSTER.finditer(roh):
        zeile = roh.count("\n", 0, m.start()) + 1
        aus[m.group(1)] = (int(m.group(2)), zeile)
    return aus


def ohne_ausnahmen(tab):
    return {n: v for n, v in tab.items() if n not in KEINE_NUMMER}


def pruefe(wurzel):
    fehler = []
    kp = os.path.join(wurzel, KERN)
    lp = os.path.join(wurzel, LIBC)
    for p in (kp, lp):
        if not os.path.exists(p):
            fehler.append("Datei fehlt: %s" % p)
    if fehler:
        return fehler, {}, {}
    kern = lies(kp)
    libc = lies(lp)

    for name, tab, datei in (("kernel", kern, KERN), ("libc", libc, LIBC)):
        echt = ohne_ausnahmen(tab)
        nach_zahl = {}
        for n, (v, z) in echt.items():
            nach_zahl.setdefault(v, []).append((n, z))
        for v in sorted(nach_zahl):
            wer = nach_zahl[v]
            if len(wer) > 1:
                fehler.append(
                    "%s: die Nummer %d ist %d mal vergeben -- %s"
                    % (datei, v, len(wer),
                       ", ".join("%s (Zeile %d)" % (n, z) for n, z in wer)))

    for n in sorted(set(ohne_ausnahmen(kern)) & set(ohne_ausnahmen(libc))):
        if kern[n][0] != libc[n][0]:
            fehler.append(
                "%s trägt im Kernel %d (Zeile %d) und in der libc %d (Zeile %d)"
                % (n, kern[n][0], kern[n][1], libc[n][0], libc[n][1]))

    nur_libc = sorted(set(ohne_ausnahmen(libc)) - set(ohne_ausnahmen(kern)))
    for n in nur_libc:
        fehler.append(
            "%s steht in der libc (%d), aber der Kernel kennt ihn nicht"
            % (n, libc[n][0]))

    return fehler, kern, libc


def belegt(kern, libc):
    z = set(v for v, _ in ohne_ausnahmen(kern).values())
    z |= set(v for v, _ in ohne_ausnahmen(libc).values())
    return z


def zweige_belegt(wurzel):
    """Jede Nummer, die IRGENDEIN Zweig dieses Repos vergibt.

    Eine Nummer, die auf `mergeline` frei ist, aber auf einem Zweig
    neben uns schon vergeben, ist beim Verschmelzen genau der Fehler von
    Runde MERGE. Also wird nicht der eigene Baum gefragt, sondern git.
    """
    aus = {}
    try:
        zweige = subprocess.run(
            ["git", "-C", wurzel, "branch", "--format=%(refname:short)"],
            capture_output=True, text=True, check=True).stdout.split()
    except Exception as e:
        return None, "git nicht erreichbar: %s" % e
    for b in zweige:
        for datei in (KERN, LIBC):
            try:
                roh = subprocess.run(
                    ["git", "-C", wurzel, "show", "%s:%s" % (b, datei)],
                    capture_output=True, check=True).stdout.decode("latin1")
            except Exception:
                continue
            for m in MUSTER.finditer(roh):
                if m.group(1) in KEINE_NUMMER:
                    continue
                aus.setdefault(int(m.group(2)), set()).add(b)
    return aus, None


def main():
    args = sys.argv[1:]
    wurzel = WURZEL

    if args and args[0] == "--zweige":
        tab, err = zweige_belegt(wurzel)
        if err:
            print(err)
            return 2
        print("Nummern >= 1000, ueber ALLE Zweige gesehen:")
        for v in sorted(x for x in tab if x >= 1000):
            print("  %5d  %s" % (v, " ".join(sorted(tab[v]))))
        frei = [v for v in range(1000, 2200) if v not in tab]
        bloecke = []
        an = None
        vor = None
        for v in frei:
            if an is None:
                an = v
            elif v != vor + 1:
                bloecke.append((an, vor))
                an = v
            vor = v
        if an is not None:
            bloecke.append((an, vor))
        print("FREI auf JEDEM Zweig:")
        for a, b in bloecke:
            print("  %d..%d (%d Nummern)" % (a, b, b - a + 1))
        return 0

    fehler, kern, libc = pruefe(wurzel)

    if args and args[0] == "--frei":
        von = int(args[1]) if len(args) > 1 else 1000
        bis = int(args[2]) if len(args) > 2 else von + 100
        b = belegt(kern, libc)
        frei = [v for v in range(von, bis) if v not in b]
        print("frei in %d..%d: %s" % (von, bis - 1,
                                      " ".join(str(v) for v in frei)))
        return 0

    if args and args[0] == "--liste":
        alle = {}
        for n, (v, _) in kern.items():
            alle.setdefault(v, []).append("kernel:" + n)
        for n, (v, _) in libc.items():
            alle.setdefault(v, []).append("libc:" + n)
        for v in sorted(alle):
            print("%6d  %s" % (v, " ".join(sorted(alle[v]))))
        return 0

    n_kern = len(ohne_ausnahmen(kern))
    n_libc = len(ohne_ausnahmen(libc))
    if fehler:
        for f in fehler:
            print("KOLLISION: %s" % f)
        print("syscalls: %d im Kernel, %d in der libc, %d FEHLER"
              % (n_kern, n_libc, len(fehler)))
        return 1
    print("syscalls: %d im Kernel, %d in der libc, %d gemeinsam, "
          "keine Nummer doppelt, kein Name mit zwei Nummern"
          % (n_kern, n_libc,
             len(set(ohne_ausnahmen(kern)) & set(ohne_ausnahmen(libc)))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
