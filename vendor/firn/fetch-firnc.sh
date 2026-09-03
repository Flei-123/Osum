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

# DIE MARKE IST COMMIT **UND** FLICKENSTAND, und das ist kein Luxus.
#
# vendor/firn/lib/ ist nicht eingecheckt und liegt in JEDEM Arbeitsbaum
# einzeln. Stuende in `.gebaut` nur der Commit, waere ein Baum, dessen
# lib/ noch ungeflickt ist, "aktuell" -- und man bekaeme aus demselben
# Quelltext zwei verschiedene Kerne. GEMESSEN, 03.09.2026: 3 844 792
# gegen 3 844 744 Oktette, und im kleineren fehlte der Rundruf-Zweig,
# also DHCP. Deshalb geht der Flickenstand in die Marke: aendert sich
# einer, wird neu gebaut.
PSUM=$( { cat "$HIER"/patches/*.patch 2>/dev/null || true; } | sha256sum | cut -c1-16)
MARKE="$COMMIT $PSUM"

FORCE=0
[[ ${1:-} == --force ]] && FORCE=1

if [[ $FORCE -eq 0 && -x $HIER/bin/firnc && -x $HIER/bin/firnc1 \
      && -f $HIER/.gebaut && $(cat "$HIER/.gebaut") == "$MARKE" ]]; then
    echo "firnc ist aktuell ($KURZ, Flicken $PSUM)"
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
# -L: die Firn-Bibliothek enthaelt neun Symlinks, und einer davon
# (lib/rc/rc.fi) zeigt AUS lib heraus in tests/. Als Symlink kopiert
# waere er hier tot; aufgeloest ist die Bibliothek in sich geschlossen.
cp -rL "$BAU/lib" "$HIER/lib"

# --- DIE FLICKEN DIESES REPOS AUF DIE FIRN-BIBLIOTHEK.
#
# vendor/firn/lib/ ist NICHT eingecheckt und wird oben mit `rm -rf`
# weggeraeumt. Was Osum an der Bibliothek geaendert hat, liegt deshalb
# als Flicken unter vendor/firn/patches/ -- eingecheckt, mit Begruendung
# im Kopf jeder Datei -- und wird HIER aufgelegt. Ohne diesen Block waere
# jede solche Aenderung beim naechsten `--force` still verschwunden.
#
# Sie werden in Namensreihenfolge aufgelegt, und ein Flicken, der nicht
# passt, bricht den Bau ab: eine halb geflickte Bibliothek ist schlimmer
# als eine ungeflickte, weil der Fehler dann anderswo auftaucht.
if [[ -d $HIER/patches ]]; then
    for f in "$HIER"/patches/*.patch; do
        [[ -e $f ]] || continue
        echo ">> Flicken: $(basename "$f")"
        patch -p1 -d "$HIER/lib" -i "$f" --silent \
            || { echo "Flicken $(basename "$f") passt nicht auf Firn $KURZ" >&2
                 exit 1; }
    done
fi

echo ">> firnc1 bauen (der Uebersetzer in Firn, von firnc0 uebersetzt)"
FIRNLIB="$HIER/lib" "$HIER/bin/firnc" "$BAU/bin/firnc1.fi" -o "$HIER/bin/firnc1"

echo "$MARKE" > "$HIER/.gebaut"
rm -rf "$BAU"
echo ">> fertig: vendor/firn/bin/firnc + bin/firnc1 + lib ($KURZ, Flicken $PSUM)"
