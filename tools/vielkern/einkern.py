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

RUNDE GLYPHE: DIE ZWEITE BAUFORM DESSELBEN FEHLERS.

Der Zeichenweg hat den Fehler noch einmal gehabt, und dieses Werkzeug
hat ihn NICHT gesehen -- weil er nicht `state + kstate.X_OFF` heisst.
`kernel/wig.fi` holt seine Seite ueber einen eigenen Zugriff:

    fn base(state: u64) -> u64 { return state + kstate.WIG_OFF }
    ...
    let stage: u64 = base(state) + STAGE_OFF     <-- derselbe Puffer

Textlich steht dort kein `kstate.`, also fiel die Buehne durch das
Raster -- und mit ihr der Fehler, an dem Runde MERGE-6 gescheitert ist
(`panic: integer overflow in 'u64 * u64'`, ein Ring-3-Programm tot in
einem von fuenf Laeufen mit vier Kernen). Seit dieser Runde sucht das
Werkzeug deshalb ZWEI Formen:

  1. `state + kstate.<X>_OFF`  -- die alte, und
  2. `<zugriff>(state) + <KONST>` in jeder Datei, die einen solchen
     Zugriff auf eine kdata-Seite selbst definiert.

Was als Sperre gilt, ist um die drei Namen dieser Runde erweitert:
`wig.buehne_an` (die Buehnensperre), `ttf.tafel_an` (der
Glyphenspeicher) und `stage_of(` -- der letzte ist KEINE Sperre,
sondern die Aufloesung JE KERN: er gibt die Seite DIESES Kerns
(`kstate.WIGST_OFF + cpu.here(state) * STAGE_MAX`), und damit gibt es
nichts mehr zu teilen. Er steht mit diesem Satz hier und nicht als
stille Ausnahme.

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
                    r"|serial\.zeile_an\("
                    # RUNDE GLYPHE: die drei Namen des Zeichenwegs.
                    r"|buehne_an\(|buehne_wenn_|tafel_an\(|stage_of\(")

# RUNDE GLYPHE: die zweite Bauform -- eine Seite, die die Datei ueber
# einen EIGENEN Zugriff holt. Der Zugriff selbst wird hier gesucht ...
BASISZUGRIFF = re.compile(
    r"fn (\w+)\(state: u64\) -> u64 \{\s*\n\s*return state \+ kstate\.(\w+_OFF)")
# ... und das hier ist sein Gebrauch als ARBEITSFLAECHE. `+ 0x` und
# `+ <kleinbuchstaben>` faengt es nicht: nur benannte Konstanten, also
# genau das, was eine Runde sich als Puffer hinlegt.
def puffer2(zugriff):
    return re.compile(r"\b%s\(state\)\s*\+\s*([A-Z][A-Z0-9_]*)" % zugriff)

# Diese Dateien laufen nachweislich nur auf einem Kern oder nur vor dem
# Start der Anwendungskerne. Sie stehen mit BEGRUENDUNG hier und nicht
# als stille Ausnahme.
RUHIG = {
    "kmain.fi": "laeuft vor smp.probe, also bevor es zweite Kerne gibt",
}

# RUNDE GLYPHE: EINE Stelle, die den geteilten Puffer mit Absicht
# anfasst -- und sie steht hier mit Namen, so wie `inode_get_blind` und
# `race_core` in tools/vielkern/run.sh. Wer eine zweite dazutut, muss
# sie hier eintragen und begruenden.
MITWISSEN = {
    ("kernel/wig.fi", "stage_of"):
        "gibt die Buehne DIESES Kerns (kstate.WIGST_OFF + cpu.here * "
        "STAGE_MAX). Die GETEILTE Seite kommt darin nur unter "
        "`glyphblind`/`glyphsperre` vor -- das sind die zwei "
        "Gegenproben, und ohne sie misst der Nachweis nichts.",
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
    mitwissen = []
    for wurzel, _, dateien in os.walk(os.path.join(WURZEL, "kernel")):
        for d in sorted(dateien):
            if not d.endswith(".fi"):
                continue
            if nur and d != nur:
                continue
            pfad = os.path.join(wurzel, d)
            kurz = os.path.relpath(pfad, WURZEL)
            roh = open(pfad, "rb").read().decode("utf-8", "surrogateescape")
            # RUNDE GLYPHE: hat die Datei einen eigenen Zugriff auf eine
            # kdata-Seite? Dann ist `<zugriff>(state) + KONST` derselbe
            # geteilte Puffer, nur anders geschrieben.
            zweite = [(z, seite, puffer2(z))
                      for z, seite in BASISZUGRIFF.findall(roh)]
            for fn, leib in sorted(funktionen(pfad).items()):
                text = "\n".join(leib)
                treffer = PUFFER.findall(text)
                for zugriff, seite, muster in zweite:
                    if fn == zugriff:
                        continue
                    treffer = treffer + ["%s+%s" % (seite, k)
                                         for k in muster.findall(text)]
                if not treffer:
                    continue
                eintrag = (kurz, fn, sorted(set(treffer)))
                if (kurz, fn) in MITWISSEN:
                    mitwissen.append(eintrag)
                    continue
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
    if liste and mitwissen:
        print("== MITWISSEN: mit Absicht am geteilten Puffer ==")
        for k, f, p in mitwissen:
            print("   %-24s %-22s %s" % (k, f, ",".join(p)))
            print("      %s" % MITWISSEN[(k, f)])
        print()
    dat_offen = sorted(set(k for k, _, _ in offen))
    print("einkern gesperrt=%d offen=%d mitwissen=%d dateien=%s"
          % (len(gesperrt), len(offen), len(mitwissen),
             ",".join(dat_offen) or "-"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
