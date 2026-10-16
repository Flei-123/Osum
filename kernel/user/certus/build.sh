#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# kernel/user/certus/build.sh -- /bin/certus BAUEN. Runde CERTUS-AUF-OSUM.
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
#     kernel/user/certus/build.sh <ziel.elf>
#
# Umgebung: CERTUS_REPO (Vorgabe /root/certus-sammeln), CERTUS_FIRNC.
# STATE 16.10.2026 (W-CERTUS-IMG): THIS SCRIPT DOES NOT PRODUCE A BINARY AT main YET.
#   Fixed here: new Certus layout (lib/window, lib/osum), Osum's new asm blocks
#   (map_fd, bus5, rdtsc -> sysstub.s), wlib's import closure (fuiglyph, fuib, ecke),
#   merged lib dirs (paint, font, svg, ... from the shared Firn tree), wlib.canvas2 name drift.
#   Still open: Certus uses a Sept-2026 FORK of fUi/font/paint/canvas, Osum's wlib
#   (fuib) needs the CURRENT Firn versions (painter_fill_raster, matrix.mat_get,
#   canvas_set_gpu, raster_finish_band, `as%` casts need Osum's newer firnc).
#   Two versions of one module family cannot live in one compile. FUI_MODE=firn
#   and CERTUS_FIRNC=vendor/firn/bin/firnc try the other side (also red).
set -euo pipefail
cd "$(dirname "$0")/../../.."
ROOT=$(pwd)

ZIEL=${1:-$ROOT/.certus-bau/certus.elf}
CERTUS_REPO=${CERTUS_REPO:-/root/certus-ui}
FIRNC=${CERTUS_FIRNC:-/root/firnc-gc/compiler/target/release/firnc}
BAU=${CERTUS_BAU:-$ROOT/.certus-bau}

[ -d "$CERTUS_REPO/lib/browser" ] || {
    echo "kein Certus-Baum in $CERTUS_REPO (CERTUS_REPO setzen)" >&2; exit 2; }
[ -x "$FIRNC" ] || {
    echo "kein Uebersetzer: $FIRNC" >&2
    echo "  (cd $CERTUS_REPO/compiler && cargo build --release)" >&2; exit 2; }
# New Certus layout (>= 0.6x): backend files live in lib/osum/{window,dlg,media}
# and lib/window/osum.fi; old layout (lib/fenster/osum.fi) is still accepted.
if [ -f "$CERTUS_REPO/lib/osum/window/backend.fi" ]; then
    LAYOUT=new
elif [ -f "$CERTUS_REPO/lib/fenster/osum.fi" ]; then
    LAYOUT=old
else
    echo "$CERTUS_REPO has no Osum backend -- wrong branch/tree?" >&2; exit 2
fi

rm -rf "$BAU"
mkdir -p "$BAU"

# 1. LIBRARY ROOT FOR `import`: union of Certus (browser, css, js, ...) and
#    Osum (libc, icons, utf8) trees; they do not overlap.
for d in "$CERTUS_REPO"/lib/*; do
    ln -sfn "$d" "$BAU/$(basename "$d")"
done
# Newer Certus trees keep patched copies of fui/rt/std in hidden dirs and take the
# rest (std, rc, gc, ...) from the shared Firn tree (FIRN_SHARED, default /root/firn).
for pair in fui:.fui-win rt:.rt-win std:.std-win; do
    if [ -d "$CERTUS_REPO/${pair#*:}" ]; then
        ln -sfn "$CERTUS_REPO/${pair#*:}" "$BAU/${pair%%:*}"
    fi
done
FIRN_SHARED=${FIRN_SHARED:-/root/firn}
if [ -d "$FIRN_SHARED/lib" ]; then
    for d in "$FIRN_SHARED"/lib/*; do
        [ -e "$BAU/$(basename "$d")" ] || ln -sfn "$d" "$BAU/$(basename "$d")"
    done
fi
# Directories where Certus' tree and the shared Firn tree each hold part of a module family:
# merge them (Certus files win, missing ones come from Firn).
for sub in $(ls "$CERTUS_REPO/lib"); do
    case "$sub" in fui|rt|std|libc|window|dlg|media|osum|windows) continue ;; esac
    if [ -d "$CERTUS_REPO/lib/$sub" ] && [ -d "$FIRN_SHARED/lib/$sub" ]; then
        rm -f "$BAU/$sub"; mkdir -p "$BAU/$sub"
        for f in "$CERTUS_REPO/lib/$sub"/* "$FIRN_SHARED/lib/$sub"/*; do
            [ -e "$BAU/$sub/$(basename "$f")" ] || ln -sfn "$f" "$BAU/$sub/$(basename "$f")"
        done
    fi
done
rm -f "$BAU/fenster" "$BAU/libc"
cp -r "$ROOT/lib/libc" "$BAU/libc"
cp "$ROOT/lib/icons.fi" "$ROOT/lib/utf8.fi" "$BAU/"
cp "$ROOT/kernel/user/ulib.fi" "$ROOT/kernel/user/wlib.fi" \
   "$ROOT/kernel/user/wlibc.fi" "$BAU/"
# wlib now pulls in more Osum modules (fuiglyph, fuib, ecke, ...): copy the
# top-level import closure from kernel/user and lib (entkern.py de-asms them).
python3 - "$ROOT" "$BAU" <<'PYEOF'
import os, re, shutil, sys
root, bau = sys.argv[1], sys.argv[2]
todo = ['wlib', 'wlibc', 'ulib']
seen = set(todo)
while todo:
    name = todo.pop()
    for line in open(os.path.join(bau, name + '.fi'), encoding='latin1'):
        m = re.match(r'import ([a-z0-9_]+)\s*$', line)
        if not m or m.group(1) in seen:
            continue
        mod = m.group(1)
        seen.add(mod)
        for d in ('kernel/user', 'lib'):
            src = os.path.join(root, d, mod + '.fi')
            if os.path.exists(src):
                if not os.path.exists(os.path.join(bau, mod + '.fi')):
                    shutil.copy(src, os.path.join(bau, mod + '.fi'))
                todo.append(mod)
                break
PYEOF
# fUi: Certus uses a patched fork (fui.uipaint); Osum's wlib bridge (fuib) imports
# fui.painter. Merge: fork files + painter.fi derived from uipaint.fi + Osum extras.
FUI_MODE=${FUI_MODE:-fork}   # fork = Certus' patched copy (.fui-win); firn = current shared Firn fUi (what Osum's fuib expects)
if [ "$FUI_MODE" = firn ]; then
    rm -f "$BAU/fui"; mkdir -p "$BAU/fui"
    for f in "$ROOT"/lib/fui/* "${FIRN_SHARED:-/root/firn}"/lib/fui/*; do
        [ -e "$BAU/fui/$(basename "$f")" ] || ln -sfn "$f" "$BAU/fui/$(basename "$f")"
    done
    sed 's/\bpainter\./uipaint./g' "${FIRN_SHARED:-/root/firn}/lib/fui/painter.fi" > "$BAU/fui/uipaint.fi"
elif [ -d "$CERTUS_REPO/.fui-win" ]; then
    rm -f "$BAU/fui"; mkdir -p "$BAU/fui"
    for f in "$CERTUS_REPO"/.fui-win/*; do ln -sfn "$f" "$BAU/fui/$(basename "$f")"; done
    sed 's/\buipaint\./painter./g' "$CERTUS_REPO/.fui-win/uipaint.fi" > "$BAU/fui/painter.fi"
    for f in "$ROOT"/lib/fui/* "${FIRN_SHARED:-/root/firn}"/lib/fui/*; do
        [ -e "$BAU/fui/$(basename "$f")" ] || ln -sfn "$f" "$BAU/fui/$(basename "$f")"
    done
fi

# 2. WINDOW LAYER. `import window.backend` / `dlg.*` / `media.*` resolve NEXT TO
#    THE ROOT FILE (search rule 2), so these dirs are real dirs here.
if [ "$LAYOUT" = new ]; then
    for sub in window dlg media; do
        rm -f "$BAU/$sub"
        mkdir -p "$BAU/$sub"
        # shared files of the Certus tree first, then the Osum backend files on top
        for f in "$CERTUS_REPO/lib/$sub"/*; do
            [ -e "$f" ] && ln -sfn "$f" "$BAU/$sub/$(basename "$f")"
        done
        if [ -d "$CERTUS_REPO/lib/osum/$sub" ]; then
            for f in "$CERTUS_REPO/lib/osum/$sub"/*; do
                ln -sfn "$(readlink -f "$f")" "$BAU/$sub/$(basename "$f")"
            done
        fi
    done
    # Name drift: Certus' own English rename called wlib's canvas widget `canvas2`;
    # Osum's wlib calls it `canvas` (same signature: pixels, width, height).
    # (rm first: the entry is a symlink into the Certus tree and `>` would write THROUGH it)
    rm -f "$BAU/window/osum.fi" "$BAU/window/backend.fi"
    sed 's/wlib\.canvas2(/wlib.canvas(/g' "$CERTUS_REPO/lib/window/osum.fi" > "$BAU/window/osum.fi"
    ln -sfn osum.fi "$BAU/window/backend.fi"
else
    mkdir -p "$BAU/fenster"
    for f in "$CERTUS_REPO"/lib/fenster/*.fi; do
        ln -sfn "$f" "$BAU/fenster/$(basename "$f")"
    done
    ln -sfn "$CERTUS_REPO/lib/fenster/osum.fi" "$BAU/fenster/rueck.fi"
fi

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
