#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/lib/umstellen.py -- die qemu-Aufrufe der Laeufer auf $QEMU_X86
# umstellen. EINMALIG benutzt; steht hier, damit nachvollziehbar ist,
# WELCHE Zeilen angefasst wurden und welche nicht.
#
#   bash: python3 tools/lib/umstellen.py [--pruefen]
#
# Regel, nach der eine Zeile umgestellt wird:
#   * sie enthaelt `qemu-system-x86_64`
#   * UND sie enthaelt `timeout`  (also ein echter Start, keine Abfrage)
#   * UND sie enthaelt KEIN `-accel`  (wer selbst waehlt, behaelt seine Wahl)
#   * UND die Datei steht nicht auf der Sperrliste unten
#
# Damit bleiben ausgeschlossen:
#   `command -v qemu-system-x86_64`     -- Vorhandenheitsabfrage
#   `echo "... qemu-system-x86_64 ..."` -- Text
#   `for t in qemu-system-x86_64 ...`   -- Werkzeugliste
#   `qemu-system-x86_64 -device help`   -- Faehigkeitsabfrage (k17)
#   `-accel tcg`, `-accel "tcg,thread=..."` -- hv und smp

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# Dateien, die GAR NICHT angefasst werden.
SPERRE = {
    "tools/hv/run.sh":  "testet den eigenen Hypervisor, setzt -accel tcg selbst",
    "tools/smp/run.sh": "misst tcg,thread=single gegen multi",
    "tools/arm/run.sh": "qemu-system-aarch64, falscher Bogen fuer KVM",
}

SOURCE_LINE = ". tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL\n"
CD_RE = re.compile(r'^cd "\$\(dirname "\$0"\)/\.\./\.\."\s*$')


def laeufer():
    """Die Skripte, die test.sh wirklich aufruft."""
    txt = (ROOT / "test.sh").read_text(errors="replace")
    namen = re.findall(r"^\s+((?:tools|tests)/[a-z0-9]+/[a-z]+\.sh)\s", txt, re.M)
    return sorted(set(namen))


def umstellen(pfad: Path, pruefen: bool):
    rel = str(pfad.relative_to(ROOT))
    if rel in SPERRE:
        return 0, f"uebersprungen ({SPERRE[rel]})"

    zeilen = pfad.read_text(errors="replace").splitlines(keepends=True)
    treffer = 0
    for i, z in enumerate(zeilen):
        if "qemu-system-x86_64" not in z:
            continue
        if "timeout" not in z:
            continue
        if "-accel" in z:
            continue
        zeilen[i] = z.replace("qemu-system-x86_64", "$QEMU_X86")
        treffer += 1

    if treffer == 0:
        return 0, "keine passende Zeile"

    # `. tools/lib/qemu.sh` direkt nach dem cd ins Repo-Wurzelverzeichnis.
    if not any("tools/lib/qemu.sh" in z for z in zeilen):
        for i, z in enumerate(zeilen):
            if CD_RE.match(z):
                zeilen.insert(i + 1, SOURCE_LINE)
                break
        else:
            return -1, "FEHLER: kein 'cd \"$(dirname \"$0\")/../..\"' gefunden"

    if not pruefen:
        pfad.write_text("".join(zeilen))
    return treffer, "ok"


def main():
    pruefen = "--pruefen" in sys.argv
    gesamt = 0
    for rel in laeufer():
        p = ROOT / rel
        if not p.exists():
            print(f"  ??  {rel}: gibt es nicht")
            continue
        n, wie = umstellen(p, pruefen)
        if n > 0:
            gesamt += n
            print(f"  OK  {rel}: {n} Aufrufe -> $QEMU_X86")
        elif n == 0:
            print(f"  --  {rel}: {wie}")
        else:
            print(f"  !!  {rel}: {wie}")
            return 1

    print(f"\n{gesamt} qemu-Aufrufe umgestellt"
          f"{' (nur geprueft)' if pruefen else ''}")

    # Gegenprobe: nach dem Umbau darf in den umgestellten Dateien kein
    # nacktes `timeout ... qemu-system-x86_64` ohne -accel mehr stehen.
    if not pruefen:
        rest = subprocess.run(
            ["grep", "-rn", "--include=*.sh", "qemu-system-x86_64", "."],
            cwd=ROOT, capture_output=True, text=True).stdout.splitlines()
        schlimm = [z for z in rest
                   if "timeout" in z and "-accel" not in z
                   and not any(s in z for s in SPERRE)]
        if schlimm:
            print("\nWARNUNG -- diese Zeilen starten noch ohne -accel:")
            for z in schlimm:
                print("   " + z)
        else:
            print("Gegenprobe: kein Start ohne -accel mehr uebrig "
                  "(ausser den drei gesperrten Dateien).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
