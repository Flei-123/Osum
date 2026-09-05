#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/kernel/symtab.py -- DIE SYMBOLE UND DIE QUELLZEILEN IN DAS ABBILD.

WAS DAS PROBLEM WAR. Eine toedliche Ausnahme in Ring 0 druckt seit Runde
BLECHKERN eine Rueckverfolgung, und sie sieht so aus:

    kspur:     0x143aa1   0x1621c0   0x11e934   0x1058bc   0x100f21

Das sind Adressen. Wer sie lesen will, braucht DAS ABBILD, aus dem
dieser Kern gebaut wurde, `objdump -d` und Geduld -- und Justin steht mit
einem Fotoapparat vor einem Brett, auf dem eine andere Fassung laeuft als
die im Arbeitsbaum.  Genau daran ist die Runde EINSPRUNG zwei Stunden
haengengeblieben, und der Kommentar dort sagt es in aller Deutlichkeit.

WAS DIESES WERKZEUG DARAUS MACHT:

    kspur:  sched.irq_restore+0x11 (sched.fi:1046)
            wm.mess_kol+0x79 (wm.fi:4312)
            ...

Dafuer braucht der Kern zwei Tabellen IN SICH SELBST -- auf der Platte
liegt zum Zeitpunkt einer Panik vielleicht nichts Lesbares mehr:

  1. DIE SYMBOLTABELLE.  Adresse -> Name.  Sie kommt aus `nm` und ist
     das, was Linux `kallsyms` nennt.
  2. DIE ZEILENTABELLE.  Adresse -> Datei:Zeile.  Sie kommt aus
     `.debug_line`, das der Firn-Uebersetzer seit `compiler/src/dwarf_line.rs`
     selbst erzeugt.  DWARF im Kern zu entschluesseln waere ein
     Zustandsautomat mit Sonderopcodes -- also wird er HIER
     abgewickelt und das Ergebnis als flache, sortierte Tabelle
     abgelegt.  Der Kern macht daraus eine Binaersuche in zwanzig Zeilen.

WIE ES IN DAS ABBILD KOMMT: dieses Werkzeug schreibt eine
Assemblerdatei mit dem Symbol `osym_tab` im Abschnitt `.rodata`.
`tools/build-kernel.sh` bindet ZWEIMAL: der erste Durchgang mit einem
leeren Stummel (`kernel/arch/x86_64/osym.s`), damit `osym_tab` ueberhaupt
aufgeloest wird, der zweite mit der wirklichen Tabelle.

WARUM DAS GEHT, OBWOHL DIE TABELLE DAS ABBILD GROESSER MACHT: sie liegt
in `.rodata`, und `.rodata` kommt im Bindeskript NACH `.text` und
`.utext`.  Keine einzige Funktionsadresse verschiebt sich dadurch, und
genau das prueft `build-kernel.sh` nach dem zweiten Durchgang nach --
es vergleicht die Symbole des zweiten Abbilds mit denen, die es
eingebaut hat, und bricht ab, wenn eine Adresse gewandert ist.

WAS ES KOSTET.  Rund 60 KiB Symbole und rund 500 KiB Zeilen, zusammen
etwa ein Achtel des Abbilds.  Das ist viel, es steht hier, und es laesst
sich abstellen: `tools/build-kernel.sh --ohne-symbole` baut ohne beides,
und dann sagt der Panik-Bildschirm wieder nur Adressen.  Was NICHT geht,
ist die Tabelle auf der Platte zu lassen und erst beim Lesen des
Berichts aufzuloesen -- der Panik-Bildschirm entsteht in einem Kern, der
gerade gestorben ist; er kann nichts mehr von einer Platte holen.

Aufruf:
    python3 tools/kernel/symtab.py ABBILD.elf AUSGABE.s
"""
import re
import struct
import subprocess
import sys

MAGIC = 0x314D59534F  # "OSYM1", kleines Ende zuerst

# Der Kopf der Tabelle, 96 Oktette.  Jede Zahl ist ein Versatz VOM ANFANG
# von `osym_tab` -- damit ist die Tabelle verschiebbar und der Kern
# braucht nur EINE Adresse (`lea rax, [rip + osym_tab]`).
HDR = 96


def symbole(elf):
    """Adresse -> Name, aus `nm`, nur was im Text steht und ausfuehrbar ist."""
    aus = subprocess.run(["nm", "-n", elf], capture_output=True, text=True)
    if aus.returncode != 0:
        raise SystemExit("nm ist fehlgeschlagen: " + aus.stderr.strip())
    roh = []
    for zeile in aus.stdout.splitlines():
        teile = zeile.split()
        if len(teile) != 3:
            continue
        adr, art, name = teile
        if art not in ("T", "t"):
            continue
        roh.append((int(adr, 16), lesbar(name)))
    # Gleiche Adresse mehrfach (Aliasse wie `_boot`/`_start`): der erste
    # Name gewinnt, und zwar der KUERZERE -- `trap.entry` sagt mehr als
    # `_F0.trap__entry`, und beide zeigen auf denselben Befehl.
    raus = []
    for adr, name in roh:
        if raus and raus[-1][0] == adr:
            if len(name) < len(raus[-1][1]):
                raus[-1] = (adr, name)
            continue
        raus.append((adr, name))
    return raus


def lesbar(name):
    """`_F0.trap__entry` -> `trap.entry`.

    firnc0 stellt jedem Symbol `_F0.` voran, firnc1 `_F1.`
    (docs/SELF_HOSTING.md im Firn-Repo), und ein Modulname wird mit
    zwei Unterstrichen angehaengt.  Auf einem Panik-Bildschirm zaehlt
    jede Spalte; die vier Zeichen des Praefixes sagen nichts, was der
    Leser nicht schon weiss.
    """
    if name.startswith("_F0.") or name.startswith("_F1."):
        name = name[4:]
    return name.replace("__", ".")


def zeilen(elf):
    """Adresse -> (Datei, Zeile), aus `.debug_line`.

    `readelf --debug-dump=decodedline` wickelt den Zustandsautomaten
    des DWARF-Zeilenprogramms ab und druckt das Ergebnis als Tabelle.
    Zusammengefasst wird hier: zwei aufeinanderfolgende Eintraege mit
    derselben Datei und derselben Zeile sind EIN Bereich (aus 126419
    Rohzeilen werden so 64477).
    """
    aus = subprocess.run(["readelf", "--debug-dump=decodedline", elf],
                         capture_output=True, text=True)
    if aus.returncode != 0:
        return []
    roh = []
    for zeile in aus.stdout.splitlines():
        teile = zeile.split()
        if len(teile) < 3 or not teile[2].startswith("0x"):
            continue
        try:
            nr = int(teile[1])
            adr = int(teile[2], 16)
        except ValueError:
            continue
        roh.append((adr, teile[0], nr))
    roh.sort()
    raus = []
    for adr, datei, nr in roh:
        if raus and raus[-1][0] == adr:
            raus[-1] = (adr, datei, nr)
            continue
        if raus and raus[-1][1] == datei and raus[-1][2] == nr:
            continue
        raus.append((adr, datei, nr))
    return raus


def blob(syms, lns):
    """Die Oktette der Tabelle bauen.  Aufbau -- er steht auch in
    `kernel/ksymtab.fi`, und die beiden muessen zusammenpassen:

        0   u64 Kennung 'OSYM1'
        8   u64 Zahl der Symbole
        16  u64 Zahl der Zeileneintraege
        24  u64 Versatz der Symboladressen (je u32)
        32  u64 Versatz der Namensverweise (je u32 in den Namensblock)
        40  u64 Versatz des Namensblocks
        48  u64 Versatz der Zeilentabelle (je 8: u32 Adresse, u32 gepackt)
        56  u64 Versatz der Dateiverweise (je u32)
        64  u64 Zahl der Dateien
        72  u64 Versatz des Dateinamenblocks
        80  u64 niedrigste Adresse
        88  u64 hoechste Adresse

    GEPACKT heisst: (Dateinummer << 20) | Zeilennummer.  Zwanzig Bits
    fassen 1048575 Zeilen; die laengste Datei dieses Baums hat 10216.
    Zwoelf Bits fassen 4096 Dateien; es sind 113.
    """
    namen = bytearray(b"\0")
    nvers = {}

    def leg_ab(s):
        b = s.encode("utf-8", "replace") + b"\0"
        if b in nvers:
            return nvers[b]
        p = len(namen)
        namen.extend(b)
        nvers[b] = p
        return p

    sym_adr = bytearray()
    sym_nam = bytearray()
    for adr, name in syms:
        sym_adr += struct.pack("<I", adr & 0xFFFFFFFF)
        sym_nam += struct.pack("<I", leg_ab(name))

    dateien = []
    dvers = {}
    zeil = bytearray()
    for adr, datei, nr in lns:
        if datei not in dvers:
            dvers[datei] = len(dateien)
            dateien.append(datei)
        f = dvers[datei]
        if nr > 0xFFFFF:
            nr = 0xFFFFF
        if f > 0xFFF:
            f = 0xFFF
        zeil += struct.pack("<II", adr & 0xFFFFFFFF, (f << 20) | nr)

    dnamen = bytearray(b"\0")
    dvers2 = {}

    def leg_datei(s):
        b = s.encode("utf-8", "replace") + b"\0"
        if b in dvers2:
            return dvers2[b]
        p = len(dnamen)
        dnamen.extend(b)
        dvers2[b] = p
        return p

    dat_ver = bytearray()
    for d in dateien:
        dat_ver += struct.pack("<I", leg_datei(d))

    o_sadr = HDR
    o_snam = o_sadr + len(sym_adr)
    o_str = o_snam + len(sym_nam)
    o_zeil = ausrichten(o_str + len(namen))
    o_dver = o_zeil + len(zeil)
    o_dstr = o_dver + len(dat_ver)

    lo = syms[0][0] if syms else 0
    hi = syms[-1][0] if syms else 0
    kopf = struct.pack("<12Q", MAGIC, len(syms), len(lns), o_sadr, o_snam,
                       o_str, o_zeil, o_dver, len(dateien), o_dstr, lo, hi)
    assert len(kopf) == HDR
    b = bytearray(kopf)
    b += sym_adr
    b += sym_nam
    b += namen
    while len(b) < o_zeil:
        b.append(0)
    b += zeil
    b += dat_ver
    b += dnamen
    return bytes(b)


def ausrichten(n):
    return (n + 7) & ~7


def schreib_s(pfad, daten, syms, lns):
    with open(pfad, "w") as f:
        f.write("/* SPDX-License-Identifier: GPL-2.0-only */\n")
        f.write("/* ERZEUGT von tools/kernel/symtab.py -- NICHT VON HAND"
                " AENDERN.\n")
        f.write("   %d Symbole, %d Zeileneintraege, %d Oktette. */\n"
                % (len(syms), len(lns), len(daten)))
        f.write("    .section .rodata\n")
        f.write("    .align 8\n")
        f.write("    .globl osym_tab\n")
        f.write("osym_tab:\n")
        for i in range(0, len(daten), 32):
            stueck = daten[i:i + 32]
            f.write("    .byte " + ",".join(str(x) for x in stueck) + "\n")


def main():
    if len(sys.argv) != 3:
        sys.stderr.write(__doc__)
        return 1
    elf, aus = sys.argv[1], sys.argv[2]
    syms = symbole(elf)
    if not syms:
        sys.stderr.write("symtab: nm hat kein einziges Textsymbol geliefert\n")
        return 1
    lns = zeilen(elf)
    daten = blob(syms, lns)
    schreib_s(aus, daten, syms, lns)
    sys.stderr.write("symtab: %d Symbole, %d Zeilen, %d Oktette\n"
                     % (len(syms), len(lns), len(daten)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
