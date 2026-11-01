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
done < <(python3 tools/structure/shell.py --liste kern
         python3 tools/structure/shell.py --liste uprog)

GEAENDERT=0
ZEILEN=0
while IFS= read -r f; do
    # -a: `kmain.fi` ist wegen eingebetteter Oktette "binaer".
    mapfile -t TREFFER < <(grep -aoE '^[ \t]*import[ \t]+[A-Za-z_][A-Za-z0-9_.]*([ \t]*//.*)?$' "$f" 2>/dev/null)
    [[ ${#TREFFER[@]} -eq 0 ]] && continue
    DIRTY=0
    for z in "${TREFFER[@]}"; do
        path=$(echo "$z" | sed -E 's|^[ \t]*import[ \t]+||; s|[ \t]*//.*$||; s|[ \t]*$||')
        modul=${path##*.}
        [[ -v ORT[$modul] ]] || continue
        expected="${ORT[$modul]}$modul"
        [[ $path == "$expected" ]] && continue
        eigen=$(dirname "${f#kernel/}")
        [[ $eigen == "." ]] && eigen="" || eigen="${eigen//\//.}."
        [[ $path == "$modul" && ${ORT[$modul]} == "$eigen" ]] && continue
        if [[ $path == *.* ]]; then
            praefix=${path%.*}
            [[ -d "kernel/${praefix//./\/}" ]] || continue
        fi
        if [[ $TROCKEN == 1 ]]; then
            echo "  $f: $path -> $expected"
        else
            sed -i -E "s|^([ \t]*)import[ \t]+${path//./\\.}([ \t]*)(//.*)?\$|\1import $expected\2\3|" "$f"
        fi
        ZEILEN=$((ZEILEN + 1))
        DIRTY=1
    done
    [[ $DIRTY == 1 ]] && GEAENDERT=$((GEAENDERT + 1))
done < <(find kernel -path kernel/user -prune -o -path kernel/app -prune -o \
         -name '*.fi' -type f -print)

if [[ $TROCKEN == 1 ]]; then
    echo "dry run: $ZEILEN lines in $GEAENDERT files would need fixing"
else
    echo "gerichtet: $ZEILEN import-Zeilen in $GEAENDERT Dateien"
fi
