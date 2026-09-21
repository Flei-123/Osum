#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# pruef/anim-ab.sh -- PUNKT 3, DIE GEGENPROBE IN EINER ZAHL.
#
#   bash pruef/anim-ab.sh <arbeitsbaum> <ausgabe>
#
# Baut in ARBEITSBAUM einen Kern, startet ihn mit `wmhold`, laesst den
# Schreibtisch mit Taskleiste und Startmenue hochfahren -- und liest
# `anim=` und `frames=` aus `wm: vsync=...`.
#
# WARUM DAS DIE RICHTIGE ZAHL IST. `anim` zaehlt, wie oft `anim_start`
# eine Bewegung ANGEMELDET hat, `frames`, wie viele Zwischenbilder
# `anim_tick` dafuer gezeichnet hat. Beides ist im Server gezaehlt und
# nicht im Bild geraten -- und beides war vor dieser Runde bei einem
# gewoehnlichen Hochfahren 0, weil open_anim/close_anim/minimize_anim
# nirgends aufgerufen wurden.
#
# OHNE `wmanim`. Dieser Schalter ist eine VORFUEHRUNG: der Kern ruft
# dort selbst open_anim und close_anim auf. Er wuerde auf beiden
# Baeumen dieselbe Zahl liefern und damit nichts ueber diese Runde
# sagen. Gemessen wird deshalb das normale Hochfahren, in dem
# ausschliesslich Ring 3 Fenster anlegt.
set -uo pipefail
BAUM=${1:?usage: anim-ab.sh <arbeitsbaum> <ausgabe>}
OUT=${2:?usage: anim-ab.sh <arbeitsbaum> <ausgabe>}
cd "$BAUM"
mkdir -p "$OUT"
export LOOKBUILD="$OUT/build"
bash tools/look/shot.sh "$OUT/lauf" lang=de user=de accel=kvm \
    > "$OUT/lauf.log" 2>&1
echo "== $BAUM =="
grep -ao 'anim=[0-9]*  frames=[0-9]*' "$OUT/lauf.log" | tail -1
rm -f "$OUT/lauf/disk.img"
