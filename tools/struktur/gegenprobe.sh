#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/struktur/gegenprobe.sh -- HAT DIE PROBE UEBERHAUPT ZAEHNE?
#
#   ./tools/struktur/gegenprobe.sh          (still, nur die Bilanz)
#   ./tools/struktur/gegenprobe.sh -v       (jede Meldung zeigen)
#
# `tools/struktur/run.sh` meldet "19 passed, 0 failed". Das ist genau so
# viel wert wie die Frage, ob es ueberhaupt jemals "failed" sagen KANN.
# Eine gruene Probe, die nichts prueft, ist schlimmer als keine: sie
# erzeugt Vertrauen, das sie nicht deckt.
#
# Und das ist kein Gedankenspiel. Diese Runde hatte genau diesen Fall:
# `memmap.py` prueft Vektorkollisionen seit Runde K10 -- und hat die
# Kollision `VEC_MOUSE = 46` / `VEC_NET + 1 = 46` trotzdem nicht
# gesehen, weil die eine Seite eine RECHNUNG war und der Prueferblick
# nur auf Konstanten lag. Der Prueferschein war gruen, der Fehler war da.
#
# Darum bricht dieses Skript die Ordnung ABSICHTLICH -- je einmal pro
# Zusage, in einem WEGWERFBAUM (git worktree, /tmp) -- und verlangt,
# dass run.sh genau das meldet und mit 1 endet. Der eigene Baum wird
# dabei nicht angefasst.
# PFADE-AUSNAHME -- dieses Skript nennt mit ABSICHT Pfade, die es nicht
# gibt (kernel/fb.fi, kernel/drivers/net/hw.fi): es baut sie ein, um zu
# pruefen, dass die Probe sie findet. `pfade.sh` nimmt jede Datei mit
# diesem Wort heraus, sonst meldete sie hier drei Treffer, die genau das
# Gegenteil eines Fehlers sind.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

LAUT=0
[[ ${1:-} == -v ]] && LAUT=1

if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "GEGENPROBE: uebersprungen -- kein git-Baum (das ist in einer Kopie normal)"
    exit 0
fi

BAUM=$(mktemp -d /tmp/struktur-gegenprobe.XXXXXX)
aufraeumen() { git worktree remove --force "$BAUM" > /dev/null 2>&1; rm -rf "$BAUM"; }
trap aufraeumen EXIT

rmdir "$BAUM"
if ! git worktree add -q --detach "$BAUM" HEAD > /dev/null 2>&1; then
    echo "GEGENPROBE: uebersprungen -- kein Wegwerfbaum moeglich"
    exit 0
fi
# Die Probe selbst kommt aus dem ARBEITSBAUM, nicht aus HEAD: sonst
# pruefte sich die zuletzt geaenderte Fassung nie selbst.
mkdir -p "$BAUM/tools/struktur"
cp "$ROOT"/tools/struktur/run.sh "$ROOT"/tools/struktur/pfade.sh "$BAUM/tools/struktur/"

cd "$BAUM"
pass=0; fail=0

probe() { # name  bruch  erwartetes-muster
    git checkout -q -- . 2>/dev/null
    git clean -qfd -e tools/struktur 2>/dev/null
    eval "$2"
    local aus rc
    aus=$(STRUKTUR_IN_GEGENPROBE=1 bash tools/struktur/run.sh 2>&1); rc=$?
    if [ $rc -ne 0 ] && printf '%s' "$aus" | grep -qE "$3"; then
        pass=$((pass+1)); printf '  OK    faellt: %s\n' "$1"
        [ $LAUT = 1 ] && printf '%s' "$aus" | grep -E "$3" | head -1 | sed 's/^/          /'
    else
        fail=$((fail+1))
        printf '  FAIL  BLIND: %s -- run.sh haette fallen muessen (rc=%d)\n' "$1" "$rc"
        printf '%s' "$aus" | grep -E 'FAIL|failed' | head -3 | sed 's/^/          /'
    fi
    return 0
}

echo "GEGENPROBE: bricht die Ordnung -- meldet run.sh es?"

# 1. Der Rueckfall, gegen den diese ganze Runde gerichtet ist.
probe "ein Treiber liegt wieder flach in kernel/" \
      'touch kernel/kbd.fi' \
      'liegt wieder flach'

# 2. Zwei Module gleichen Namens -- der Fehler kaeme erst beim Binden.
probe "doppelter Modulname in der Kerneinheit" \
      'cp kernel/hw.fi kernel/drivers/net/hw.fi' \
      'doppelte Modulnamen'

# 3. Regel 1: eine Stelle mehr am Kern vorbei als im Bestand.
probe "eine Stelle mehr ruft nvme direkt" \
      'printf "\nfn xx() { nvme.blocks(state) }\n" >> kernel/hwid.fi' \
      'nvme wird [0-9]+ mal am Kern vorbei'

# 4. Regel 2: ein Chiptreiber schert bei einem Namen aus.
probe "e1000 schreibt einen Pflichtnamen anders" \
      'sed -i "s/^fn tx_room_on/fn tx_platz_on/" kernel/drivers/net/e1000.fi' \
      'e1000.fi fehlen Namen'

# 5. Regel 3: DER FEHLER DIESER RUNDE, wieder eingebaut.
probe "ein Treiber rechnet sich wieder einen Vektor aus" \
      'printf "\nfn yy() { let v: u64 = VEC_NET + c }\n" >> kernel/drivers/net/virtio.fi' \
      'Vektor wird ausserhalb'

# 6. --gui off: die Leerfassung haelt nicht mehr Schritt.
probe "gfx.fi bekommt eine Funktion, gfx-aus.fi nicht" \
      'printf "\nfn neu_gfx() { }\n" >> kernel/drivers/gfx/gfx.fi' \
      'gfx-aus.fi fehlen'

# 7. --gui off zoege Grafik in ein Abbild, das keine haben soll.
probe "neue Datei in drivers/gfx/ fehlt in GFX_DATEIEN" \
      'echo "// leer" > kernel/drivers/gfx/neu.fi' \
      'GFX_DATEIEN fehlt'

# 8. Und ein toter Pfad im CODE eines Werkzeugs (nicht im Kommentar).
probe "ein Werkzeug liest einen Pfad, den es nicht mehr gibt" \
      'printf "#!/usr/bin/env bash\nB=\$(grep -aE %s kernel/fb.fi | head -1)\n" "^const FB" > tools/tot_tmp.sh' \
      'pfade.sh'

# Und die Gegenrichtung: ohne Bruch muss sie gruen sein, sonst zeigt
# dieses Skript nur, dass run.sh IMMER faellt.
git checkout -q -- . 2>/dev/null; git clean -qfd -e tools/struktur 2>/dev/null
if STRUKTUR_IN_GEGENPROBE=1 bash tools/struktur/run.sh > /dev/null 2>&1; then
    pass=$((pass+1)); echo "  OK    und am unversehrten Baum ist sie gruen"
else
    fail=$((fail+1)); echo "  FAIL  run.sh faellt schon am unversehrten Baum -- die Brueche oben beweisen nichts"
    STRUKTUR_IN_GEGENPROBE=1 bash tools/struktur/run.sh 2>&1 | grep -E 'FAIL' | head -5 | sed 's/^/          /'
fi

echo "GEGENPROBE: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
