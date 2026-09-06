#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# kernel/user/certus/bau.sh -- /bin/certus BAUEN. Runde CERTUS-AUF-OSUM.
#
# ============================================== WAS HIER ZUSAMMENKOMMT
#
# Certus ist der Browser aus dem Firn-Baum (Zweig `osum` in
# $CERTUS_REPO, rund 105.000 Zeilen: HTML, CSS, Layout, JavaScript,
# Schriftrasterer, TLS, Bilder, PDF). Er hat vier Rueckwaende fuer sein
# Fenster -- X11, Win32, Android und seit dieser Runde OSUM
# (lib/fenster/osum.fi). Die Osum-Rueckwand redet nicht mit dem
# Fensterserver, sondern mit der WIDGET-BIBLIOTHEK dieses Systems:
# kernel/user/wlib.fi und kernel/user/wlibc.fi.
#
# Damit stossen zwei Profile aufeinander, und das ist der ganze Grund,
# warum dieses Skript existiert:
#
#   * Osums Ring-3-Bibliotheken sind `profile kernel` -- sie duerfen
#     `asm(...)`, aber nicht das Schluesselwort `syscall`.
#   * Certus ist `profile app` -- er hat einen Sammler (Gc), also
#     `syscall`, aber kein `asm`.
#   * Das Profil haengt an der WURZELDATEI (compiler/src/prof.rs).
#
# Ein Programm, das beides bindet, gibt es also nicht, solange in den
# Bibliotheken `asm` steht. `entkern.py` macht daraus Kopien ohne
# Assembler: jeder Block wird durch den Aufruf einer `extern fn`
# ersetzt, und die Ruempfe liegen in kernel/user/sysstub.s -- acht
# Befehlsfolgen, die genau das tun, was die `asm`-Bloecke taten.
#
# Es sind KOPIEN und keine Aenderung an wlib/wlibc/libc: die 52
# Programme dieser Platte werden weiter Zeile fuer Zeile aus dem
# Original gebaut, mit crt.o und ohne diese Datei. `entkern.py` bricht
# ab, wenn ein Muster nicht genau einmal passt -- eine stille
# Teilumformung waere schlimmer als keine.
#
# ================================================== DER UEBERSETZER
#
# NICHT der festgenagelte (vendor/firn/COMMIT): Certus braucht seinen
# eigenen, aktuellen (compiler/target/release/firnc im Certus-Baum),
# weil sein Quelltext dem Uebersetzer voraus ist. Der Kern von Osum
# wird davon NICHT angefasst -- er kommt weiter aus vendor/firn. Zwei
# Uebersetzer in einem Abbild, jeder fuer das, was er gebaut hat.
#
#     kernel/user/certus/bau.sh <ziel.elf>
#
# Umgebung: CERTUS_REPO (Vorgabe /root/certus-sammeln), CERTUS_FIRNC.
set -euo pipefail
cd "$(dirname "$0")/../../.."
ROOT=$(pwd)

ZIEL=${1:-$ROOT/.certus-bau/certus.elf}
CERTUS_REPO=${CERTUS_REPO:-/root/certus-sammeln}
FIRNC=${CERTUS_FIRNC:-$CERTUS_REPO/compiler/target/release/firnc}
BAU=${CERTUS_BAU:-$ROOT/.certus-bau}

[ -d "$CERTUS_REPO/lib/browser" ] || {
    echo "kein Certus-Baum in $CERTUS_REPO (CERTUS_REPO setzen)" >&2; exit 2; }
[ -x "$FIRNC" ] || {
    echo "kein Uebersetzer: $FIRNC" >&2
    echo "  (cd $CERTUS_REPO/compiler && cargo build --release)" >&2; exit 2; }
[ -f "$CERTUS_REPO/lib/fenster/osum.fi" ] || {
    echo "$CERTUS_REPO hat keine Osum-Rueckwand -- falscher Zweig? (git checkout osum)" >&2
    exit 2; }

rm -rf "$BAU"
mkdir -p "$BAU"

# 1. DIE BIBLIOTHEK, AUS DER `import` liest. Sie ist die VEREINIGUNG
#    zweier Baeume: die Pakete von Certus (browser, css, js, ...) und
#    die von Osum (libc, icons, utf8). Sie ueberschneiden sich nicht.
for d in "$CERTUS_REPO"/lib/*; do
    ln -sfn "$d" "$BAU/$(basename "$d")"
done
rm -f "$BAU/fenster" "$BAU/libc"
cp -r "$ROOT/lib/libc" "$BAU/libc"
cp "$ROOT/lib/icons.fi" "$ROOT/lib/utf8.fi" "$BAU/"
cp "$ROOT/kernel/user/ulib.fi" "$ROOT/kernel/user/wlib.fi" \
   "$ROOT/kernel/user/wlibc.fi" "$BAU/"

# 2. DIE FENSTERSCHICHT. `import fenster.rueck` wird NEBEN DER
#    WURZELDATEI aufgeloest (Suchregel 2) -- also liegt hier ein
#    Verzeichnis `fenster/` mit der Osum-Rueckwand als `rueck.fi`.
mkdir -p "$BAU/fenster"
for f in "$CERTUS_REPO"/lib/fenster/*.fi; do
    ln -sfn "$f" "$BAU/fenster/$(basename "$f")"
done
ln -sfn "$CERTUS_REPO/lib/fenster/osum.fi" "$BAU/fenster/rueck.fi"

# 3. ASSEMBLER RAUS.
python3 "$ROOT/kernel/user/certus/entkern.py" "$BAU" > "$BAU/entkern.log"

# 4. DIE WURZELDATEI.
cp "$CERTUS_REPO/lib/osum/certus_main.fi" "$BAU/certus_main.fi"

# 5. UEBERSETZEN. Kein crt.o: `firnc -c` legt seinen eigenen `_start`
#    hinein (vier Befehle, dieselben wie in crt.s), und zwei davon
#    waeren ein Binderfehler. Dafuer sysstub.o -- die acht Tueren.
cd "$BAU"
FIRNLIB="$BAU" "$FIRNC" -c -o "$BAU/certus.o" certus_main.fi
as --64 -o "$BAU/sysstub.o" "$ROOT/kernel/user/sysstub.s"
ld -T "$ROOT/kernel/user/user.ld" -o "$BAU/certus.dbg" \
    "$BAU/certus.o" "$BAU/sysstub.o"
mkdir -p "$(dirname "$ZIEL")"
cp "$BAU/certus.dbg" "$ZIEL"
strip --strip-all "$ZIEL"

echo "certus: $(stat -c%s "$ZIEL") Oktette -> $ZIEL"
