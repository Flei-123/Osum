#!/usr/bin/env python3

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

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
            print(f"  ??  {rel}: does not exist")
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

    if not pruefen:
        rest = subprocess.run(
            ["grep", "-rn", "--include=*.sh", "qemu-system-x86_64", "."],
            cwd=ROOT, capture_output=True, text=True).stdout.splitlines()
        schlimm = [z for z in rest
                   if "timeout" in z and "-accel" not in z
                   and not any(s in z for s in SPERRE)]
        if schlimm:
            print("\nWARNING -- these lines still start without -accel:")
            for z in schlimm:
                print("   " + z)
        else:
            print("control run: no start without -accel left "
                  "(ausser den drei gesperrten Dateien).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
