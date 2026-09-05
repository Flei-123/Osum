#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/ota/plattform.py -- WOFUER ein Paket ist, in einem Wort.

Runde STORE-MOBIL. Das VERZEICHNIS einer Auslieferung bekommt je
Paketzeile eine sechste Spalte:

    paket  <name> <fassung> <sha256> <oktette> <datei> <plattform>

und `plattform` ist eines dieser Woerter:

    osum-x86_64     fuer OrientOS auf x86-64
    osum-aarch64    fuer OrientOS auf AArch64
    osum-any        fuer jede OrientOS-Maschine (Daten, Skripte, Vorlagen)

Dieselben Woerter benutzt der Katalog des Speichers (`index.json`,
/root/orientstore, Feld `ziele`), damit ein Telefon und ein
OrientOS-Rechner mit EINEM Vokabular arbeiten.

WOHER DAS WORT KOMMT, in dieser Reihenfolge:

  1. `plattform=` in den Metadaten des Pakets -- wenn ein Rezept es
     ausdruecklich sagt;
  2. `arch=` in den Metadaten (die Schreibweise des Speichers);
  3. die NUTZLAST: steckt ein ELF darin, sagt sein Kopf (`e_machine`),
     fuer welche Maschine es uebersetzt wurde. Das ist der Normalfall
     fuer alles, was `tools/laden/pakete.sh` baut, denn `opk.py` schreibt
     heute weder `arch=` noch `plattform=`;
  4. kein ELF: `osum-any`.

Ein ELF fuer eine Maschine, die OrientOS nicht kennt, ist ein FEHLER
und keine Vermutung -- das Werkzeug bricht ab und sagt, welche Zahl es
gelesen hat.

Warum die Kennung OTA2 bleibt: die Spalte ist keine Sicherheitsaussage.
Ein Geraet von vor dieser Runde liest die Felder 0 bis 4 und ignoriert
die sechste Spalte; ein Geraet DIESER Runde blendet Zeilen OHNE die
Spalte aus und sagt das. Was ein altes Geraet dabei verliert, ist nur
die Auswahl -- es installiert, wie bisher, alles.
"""
import struct

ELF_MASCHINE = {62: "x86_64", 183: "aarch64"}
WOERTER = ("osum-x86_64", "osum-aarch64", "osum-any")


def teile(roh):
    """(meta, daten) eines .opk, oder ValueError."""
    if len(roh) < 64 or roh[0:8] != b"OPKG0001":
        raise ValueError("keine OPKG-Datei (Kennung fehlt)")
    ml, dl = struct.unpack_from("<QQ", roh, 8)
    return roh[64:64 + ml], roh[64 + ml:64 + ml + dl]


def elf_maschine(oktette):
    """e_machine eines ELF-Kopfes als Zahl, oder None (kein ELF)."""
    if len(oktette) < 20 or oktette[0:4] != b"\x7fELF":
        return None
    (em,) = struct.unpack_from("<H", oktette, 18)
    return em


def maschinen_im_archiv(daten):
    """Alle e_machine-Zahlen der ELF-Dateien im deterministischen Archiv
    von `opk.py` (`archiv_bauen`). Leer, wenn keine ELF darin ist oder
    die Nutzlast kein solches Archiv ist."""
    aus = set()
    i = 0
    try:
        while i < len(daten):
            typ = chr(daten[i])
            i += 1
            _modus, nl = struct.unpack_from("<HH", daten, i)
            i += 4 + nl
            (n,) = struct.unpack_from("<Q", daten, i)
            i += 8
            if typ not in "fd" or n > len(daten) - i:
                return set()
            if typ == "f":
                em = elf_maschine(daten[i:i + 20])
                if em is not None:
                    aus.add(em)
            i += n
    except struct.error:
        return set()
    return aus


def aus_meta(meta):
    """`plattform=` oder `arch=` aus den Metadaten, sonst None."""
    plattform = arch = None
    for z in meta.decode("utf-8", "replace").split("\n"):
        if z.startswith("plattform="):
            plattform = z[10:].strip()
        elif z.startswith("arch="):
            arch = z[5:].strip()
    if plattform:
        return plattform
    if arch and arch != "any":
        return "osum-" + arch
    return None


def plattform_von_roh(roh, name="?"):
    meta, daten = teile(roh)
    p = aus_meta(meta)
    if p is not None:
        if p not in WOERTER:
            raise SystemExit("plattform: %s nennt %r -- bekannt sind %s"
                             % (name, p, ", ".join(WOERTER)))
        return p
    ems = maschinen_im_archiv(daten)
    if not ems:
        return "osum-any"
    woerter = sorted(set(ELF_MASCHINE.get(e, "elf-%d" % e) for e in ems))
    fremd = [w for w in woerter if w.startswith("elf-")]
    if fremd:
        raise SystemExit("plattform: %s traegt ein ELF fuer eine Maschine, "
                         "die OrientOS nicht kennt (e_machine %s)"
                         % (name, ", ".join(w[4:] for w in fremd)))
    if len(woerter) > 1:
        raise SystemExit("plattform: %s traegt ELF-Dateien fuer MEHRERE "
                         "Maschinen (%s) -- ein Paket, eine Maschine"
                         % (name, ", ".join(woerter)))
    return "osum-" + woerter[0]


def plattform_von_opk(pfad):
    with open(pfad, "rb") as f:
        return plattform_von_roh(f.read(), pfad)


if __name__ == "__main__":
    import sys
    for p in sys.argv[1:]:
        print("%-40s %s" % (p, plattform_von_opk(p)))
