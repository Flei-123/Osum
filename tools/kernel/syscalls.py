#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import subprocess
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
WURZEL = os.path.dirname(os.path.dirname(HIER))

def _finde(name):
    for stamm, verz, names_2 in os.walk(os.path.join(WURZEL, "kernel")):
        verz[:] = [d for d in verz if d not in ("user", "app")]
        if name in names_2:
            return os.path.relpath(os.path.join(stamm, name), WURZEL)
    return os.path.join("kernel", name)


KERN = _finde("sys.fi")
LIBC = "lib/libc/kcall.fi"

NO_NUMBER = {
    "SYS_MARK": "Marke der Exkursion (Runde 59), gilt nur bei EXCURSION",
    "SYS_LEAVE": "Marke der Exkursion (Runde 59), gilt nur bei EXCURSION",
}

MUSTER = re.compile(
    r"^[ \t]*const[ \t]+(SYS_[A-Z0-9_]+)[ \t]*:[ \t]*u64[ \t]*=[ \t]*(\d+)",
    re.M)


def lies(pfad):
    with open(pfad, "rb") as f:
        roh = f.read().decode("latin1")
    aus = {}
    for m in MUSTER.finditer(roh):
        zeile = roh.count("\n", 0, m.start()) + 1
        aus[m.group(1)] = (int(m.group(2)), zeile)
    return aus


def without_exceptions(tab):
    return {n: v for n, v in tab.items() if n not in NO_NUMBER}


def check_2(wurzel):
    error = []
    kp = os.path.join(wurzel, KERN)
    lp = os.path.join(wurzel, LIBC)
    for p in (kp, lp):
        if not os.path.exists(p):
            error.append("Datei fehlt: %s" % p)
    if error:
        return error, {}, {}
    kern = lies(kp)
    libc = lies(lp)

    for name, tab, datei in (("kernel", kern, KERN), ("libc", libc, LIBC)):
        echt = without_exceptions(tab)
        nach_num = {}
        for n, (v, z) in echt.items():
            nach_num.setdefault(v, []).append((n, z))
        for v in sorted(nach_num):
            wer = nach_num[v]
            if len(wer) > 1:
                error.append(
                    "%s: die Nummer %d ist %d mal vergeben -- %s"
                    % (datei, v, len(wer),
                       ", ".join("%s (Zeile %d)" % (n, z) for n, z in wer)))

    for n in sorted(set(without_exceptions(kern)) & set(without_exceptions(libc))):
        if kern[n][0] != libc[n][0]:
            error.append(
                "%s trägt im Kernel %d (Zeile %d) und in der libc %d (Zeile %d)"
                % (n, kern[n][0], kern[n][1], libc[n][0], libc[n][1]))

    only_libc = sorted(set(without_exceptions(libc)) - set(without_exceptions(kern)))
    for n in only_libc:
        error.append(
            "%s steht in der libc (%d), aber der Kernel kennt ihn nicht"
            % (n, libc[n][0]))

    return error, kern, libc


def belegt(kern, libc):
    z = set(v for v, _ in without_exceptions(kern).values())
    z |= set(v for v, _ in without_exceptions(libc).values())
    return z


def zweige_belegt(wurzel):
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
                if m.group(1) in NO_NUMBER:
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
        print("numbers >= 1000, seen across ALL branches:")
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

    error, kern, libc = check_2(wurzel)

    if args and args[0] == "--frei":
        von = int(args[1]) if len(args) > 1 else 1000
        bis = int(args[2]) if len(args) > 2 else von + 100
        b = belegt(kern, libc)
        frei = [v for v in range(von, bis) if v not in b]
        print("frei in %d..%d: %s" % (von, bis - 1,
                                      " ".join(str(v) for v in frei)))
        return 0

    if args and args[0] == "--liste":
        all_ = {}
        for n, (v, _) in kern.items():
            all_.setdefault(v, []).append("kernel:" + n)
        for n, (v, _) in libc.items():
            all_.setdefault(v, []).append("libc:" + n)
        for v in sorted(all_):
            print("%6d  %s" % (v, " ".join(sorted(all_[v]))))
        return 0

    n_kern = len(without_exceptions(kern))
    n_libc = len(without_exceptions(libc))
    if error:
        for f in error:
            print("KOLLISION: %s" % f)
        print("syscalls: %d in the kernel, %d in libc, %d ERRORS"
              % (n_kern, n_libc, len(error)))
        return 1
    print("syscalls: %d in the kernel, %d in libc, %d common, "
          "keine Nummer doppelt, kein Name mit zwei Nummern"
          % (n_kern, n_libc,
             len(set(without_exceptions(kern)) & set(without_exceptions(libc)))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
