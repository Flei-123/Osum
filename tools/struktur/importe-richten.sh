#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."

TROCKEN=0
[[ ${1:-} == --trocken ]] && TROCKEN=1

declare -A ORT
while IFS= read -r rel; do
    m=$(basename "$rel" .fi)
    d=$(dirname "$rel")
    [[ $d == "." ]] && ORT[$m]="" || ORT[$m]="${d//\//.}."
done < <(python3 tools/struktur/huelle.py --liste kern
         python3 tools/struktur/huelle.py --liste uprog)

GEAENDERT=0
ZEILEN=0
while IFS= read -r f; do
    # -a: `kmain.fi` ist wegen eingebetteter Oktette "binaer".
    mapfile -t TREFFER < <(grep -aoE '^[ \t]*import[ \t]+[A-Za-z_][A-Za-z0-9_.]*([ \t]*//.*)?$' "$f" 2>/dev/null)
    [[ ${#TREFFER[@]} -eq 0 ]] && continue
    DIRTY=0
    for z in "${TREFFER[@]}"; do
        pfad=$(echo "$z" | sed -E 's|^[ \t]*import[ \t]+||; s|[ \t]*//.*$||; s|[ \t]*$||')
        modul=${pfad##*.}
        [[ -v ORT[$modul] ]] || continue
        soll="${ORT[$modul]}$modul"
        [[ $pfad == "$soll" ]] && continue
        eigen=$(dirname "${f#kernel/}")
        [[ $eigen == "." ]] && eigen="" || eigen="${eigen//\//.}."
        [[ $pfad == "$modul" && ${ORT[$modul]} == "$eigen" ]] && continue
        if [[ $pfad == *.* ]]; then
            praefix=${pfad%.*}
            [[ -d "kernel/${praefix//./\/}" ]] || continue
        fi
        if [[ $TROCKEN == 1 ]]; then
            echo "  $f: $pfad -> $soll"
        else
            sed -i -E "s|^([ \t]*)import[ \t]+${pfad//./\\.}([ \t]*)(//.*)?\$|\1import $soll\2\3|" "$f"
        fi
        ZEILEN=$((ZEILEN + 1))
        DIRTY=1
    done
    [[ $DIRTY == 1 ]] && GEAENDERT=$((GEAENDERT + 1))
done < <(find kernel -path kernel/user -prune -o -path kernel/app -prune -o \
         -name '*.fi' -type f -print)

if [[ $TROCKEN == 1 ]]; then
    echo "trocken: $ZEILEN Zeilen in $GEAENDERT Dateien waeren zu richten"
else
    echo "gerichtet: $ZEILEN import-Zeilen in $GEAENDERT Dateien"
fi
