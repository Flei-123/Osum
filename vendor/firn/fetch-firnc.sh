#!/usr/bin/env bash
# vendor/firn/fetch-firnc.sh -- besorgt den FESTGENAGELTEN Firn-Uebersetzer.
#
# Warum festgenagelt: Firn wird gerade aktiv weiterentwickelt. Wuerde Osum
# immer gegen den neuesten Stand bauen, waere bei jedem Fehler unklar, ob er
# aus dem Kernel oder aus dem Uebersetzer kommt. Deshalb: EIN Commit, hier
# eingetragen in vendor/firn/COMMIT, und nachgezogen wird erst, wenn
# ./test.sh gruen ist.
#
# Der Uebersetzer selbst wird NICHT eingecheckt (mehrere MB Binaerdatei pro
# Version in der Historie). Eingecheckt ist nur der Commit-Hash; dieses
# Skript baut daraus:
#
#   vendor/firn/bin/firnc    firnc0 -- der Uebersetzer in Rust
#   vendor/firn/bin/firnc1   firnc1 -- der Uebersetzer in Firn, von firnc0 gebaut
#   vendor/firn/lib/         die Firn-Bibliothek des gleichen Commits (std, ...)
#
# Warum bin/ + lib/ nebeneinander: beide Uebersetzer suchen ein `import`
# zuletzt in `<Verzeichnis der Uebersetzerdatei>/../lib`. Damit findet
# `import std.core` die Firn-Bibliothek, ohne dass ein Testlaeufer etwas
# dafuer tun muss -- und $FIRNLIB bleibt frei fuer die libc dieses Repos
# (lib/libc, `import libc.io`).
#
#   ./vendor/firn/fetch-firnc.sh          baut, wenn noetig
#   ./vendor/firn/fetch-firnc.sh --force  baut in jedem Fall neu
set -euo pipefail
cd "$(dirname "$0")"
HIER=$(pwd)

COMMIT=$(cat COMMIT)
KURZ=${COMMIT:0:8}

FORCE=0
[[ ${1:-} == --force ]] && FORCE=1

if [[ $FORCE -eq 0 && -x $HIER/bin/firnc && -x $HIER/bin/firnc1 \
      && -f $HIER/.gebaut && $(cat "$HIER/.gebaut") == "$COMMIT" ]]; then
    echo "firnc ist aktuell ($KURZ)"
    exit 0
fi

# --- Wo liegt das Firn-Repo? Es wird NUR zum Bauen gebraucht; sobald
# bin/firnc, bin/firnc1 und lib/ stehen, laeuft dieses Repo ohne es.
kandidaten=()
[[ -n ${FIRN_REPO:-} ]] && kandidaten+=("$FIRN_REPO")
kandidaten+=("$HIER/../../../firn" "$HIER/../../firn" "$HIER/../../../../firn" "$HOME/firn")
FIRN=""
for k in "${kandidaten[@]}"; do
    if [[ -d $k/.git ]] && git -C "$k" cat-file -e "$COMMIT^{commit}" 2>/dev/null; then
        FIRN=$(cd "$k" && pwd); break
    fi
done
if [[ -z $FIRN ]]; then
    echo "Das Firn-Repo mit dem Commit $KURZ wurde nicht gefunden." >&2
    echo "Gesucht in: ${kandidaten[*]}" >&2
    echo "Pfad ueber FIRN_REPO=/pfad/zu/firn setzen." >&2
    exit 1
fi

# Der Baubaum liegt bewusst AUSSERHALB dieses Repos.
BAU=${FIRN_BAU_DIR:-${TMPDIR:-/tmp}}/firn-pin-$KURZ

# `git archive` statt `git worktree`: legt NICHTS im Firn-Repo an. Dort
# laufen parallel Arbeitsbaeume anderer Runden, die nicht angefasst werden
# duerfen.
echo ">> Firn $KURZ aus $FIRN auspacken"
rm -rf "$BAU"
mkdir -p "$BAU"
git -C "$FIRN" archive "$COMMIT" | tar -x -C "$BAU"

HOST=$(rustc -vV | sed -n 's/^host: //p')

echo ">> firnc0 bauen (Ziel $HOST)"
( cd "$BAU/compiler" && cargo build --release --target "$HOST" >/dev/null )

mkdir -p "$HIER/bin"
rm -f "$HIER/bin/firnc" "$HIER/bin/firnc1" "$HIER/.gebaut"
cp -f "$BAU/compiler/target/$HOST/release/firnc" "$HIER/bin/firnc"
rm -rf "$HIER/lib"
# RUNDE CERTUS: DIE VERWEISE BLEIBEN VERWEISE, BIS AUF DEN EINEN.
#
# Bis hierher stand hier `cp -rL`, und der Satz darueber lautete, die
# Bibliothek sei danach "in sich geschlossen". Sie war es, und sie war
# dabei KAPUTT: von den neun symbolischen Verweisen in lib/ zeigen acht
# INNERHALB von lib (lib/std/rt.fi -> ../rt/rt.fi und so weiter). `-L`
# macht daraus zwei echte Dateien mit demselben Inhalt -- und weil ein
# Firn-Modul nach seinem DATEINAMEN heisst, sind lib/rt/rt.fi und
# lib/std/rt.fi danach zwei Module namens `rt`. Ein Programm, das beide
# Wege benutzt (jedes, das `import std.rt` UND `import rt.rt` im
# Abhaengigkeitsbaum hat -- also der ganze Browser, weil lib/paint/png.fi
# den zweiten Weg nimmt), bricht mit
#
#     error: function 'rt__heap_alloc' is already declared
#
# und vierzig weiteren ab. Gemessen am 28.08.2026: 40 Fehler.
#
# Also wird jetzt mit `-a` kopiert -- die Verweise bleiben Verweise --
# und danach wird GENAU DER EINE aufgeloest, der aus lib herauszeigt
# (lib/rc/rc.fi -> ../../tests/modules/rc.fi). Der Rest ist in sich
# geschlossen, weil er es vorher schon war.
cp -a "$BAU/lib" "$HIER/lib"
while IFS= read -r l; do
    ziel=$(readlink -f "$l" 2>/dev/null) || continue
    case "$ziel" in
        "$HIER/lib"/*) ;;                 # zeigt in lib -- bleibt Verweis
        *) [ -f "$ziel" ] && { rm -f "$l"; cp "$ziel" "$l"; } ;;
    esac
done < <(find "$HIER/lib" -type l)

echo ">> firnc1 bauen (der Uebersetzer in Firn, von firnc0 uebersetzt)"
FIRNLIB="$HIER/lib" "$HIER/bin/firnc" "$BAU/bin/firnc1.fi" -o "$HIER/bin/firnc1"

echo "$COMMIT" > "$HIER/.gebaut"
rm -rf "$BAU"
echo ">> fertig: vendor/firn/bin/firnc + bin/firnc1 + lib ($KURZ)"
