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

# EIN HOLER JE BAUM ZUGLEICH. Starten mehrere Laeufer in einem frischen
# Baum gleichzeitig, raeumten sie sich gegenseitig lib/ weg ("rm: cannot
# remove vendor/firn/lib: Directory not empty", gemessen 23.09.2026 mit
# bridge+posix+hda). Der zweite wartet hier und findet danach "aktuell".
exec 9>"$HIER/.holen.lock"
flock 9


# RUNDE FUI-KERNTEXT: fUis Schriftleser unter einem ZWEITEN NAMEN.
# kernel/gfx/fuiink.fi rastert die Schrift des Kerns mit fUis
# lib/font/ttf.fi. Der Kurzname `ttf` gehoert im Kern aber schon
# kernel/gfx/ttf.fi, und Firn erlaubt je Uebersetzungseinheit EIN Modul je
# Kurzname. Also bekommt dieselbe Datei hier einen Verweis `fuittf.fi`
# daneben -- keine Kopie, keine zweite Fassung, und nichts davon liegt im
# Kernbaum (Pruefer, die kernel/** ablaufen oder kopieren, sehen es nicht).
zweitnamen() {
    if [[ -f $HIER/lib/font/ttf.fi && ! -e $HIER/lib/font/fuittf.fi ]]; then
        ln -s ttf.fi "$HIER/lib/font/fuittf.fi"
    fi
}
FORCE=0
[[ ${1:-} == --force ]] && FORCE=1

if [[ $FORCE -eq 0 && -x $HIER/bin/firnc && -x $HIER/bin/firnc1 \
      && -f $HIER/.gebaut && $(cat "$HIER/.gebaut") == "$MARKE" ]]; then
    zweitnamen
    echo "firnc ist aktuell ($KURZ, Flicken $PSUM)"
    exit 0
fi

# --- A-023: ERST IN DEN GESCHWISTER-ARBEITSBAEUMEN NACHSEHEN.
#
# bin/ und lib/ sind nicht eingecheckt und liegen in JEDEM Arbeitsbaum
# einzeln. Ein frischer `git worktree add` hat sie also nicht -- und der
# Pin in COMMIT zeigt auf die ALTE Firn-Historie, die es in /root/firn
# nicht mehr gibt (siehe HERKUNFT.md). Gemessen 23.09.2026: jeder Laeufer
# in einem neuen Baum meldete "der Kern baut nicht", obwohl am Baum
# nichts fehlte ausser dieser Kette.
#
# Ein anderer Arbeitsbaum DESSELBEN Repos, dessen `.gebaut` genau
# dieselbe MARKE traegt (Commit UND Flickenstand), hat eine Kette, die
# aus demselben Quelltext mit denselben Flicken entstanden ist. Die wird
# uebernommen -- und nur die: eine andere Marke heisst anderer
# Uebersetzer, und dann wird weiter unten wie bisher gebaut.
# `--force` ueberspringt das bewusst.
if [[ $FORCE -eq 0 ]]; then
    while read -r baum; do
        [[ -n $baum ]] || continue
        quelle="$baum/vendor/firn"
        [[ $(cd "$quelle" 2>/dev/null && pwd) == "$HIER" ]] && continue
        [[ -x $quelle/bin/firnc && -x $quelle/bin/firnc1 && -d $quelle/lib \
           && -f $quelle/.gebaut ]] || continue
        [[ $(cat "$quelle/.gebaut") == "$MARKE" ]] || continue
        echo ">> Firn $KURZ (Flicken $PSUM) aus dem Arbeitsbaum $baum uebernommen"
        rm -rf "$HIER/bin" "$HIER/lib"
        cp -a "$quelle/bin" "$HIER/bin"
        cp -a "$quelle/lib" "$HIER/lib"
        printf '%s\n' "$MARKE" > "$HIER/.gebaut"
        zweitnamen
        exit 0
    done < <(git -C "$HIER" worktree list --porcelain 2>/dev/null \
             | sed -n 's/^worktree //p')
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
# ROUND ROADMAP-5: since the history rewrite of 18.09.2026 the pinned
# commit is in NO live Firn repository any more -- only in the bundle
# taken before the rewrite. A new patch changes the mark, no sibling tree
# has it, and without this fallback nothing could be built at all.
if [[ -z $FIRN ]]; then
    for b in ${FIRN_BUNDLE:-} "$HOME/repo-backup/firn-vor-rewrite.bundle"; do
        [[ -f $b ]] || continue
        klon=${TMPDIR:-/tmp}/firn-pin-repo
        [[ -d $klon/.git ]] || git clone -q --no-checkout "$b" "$klon" || continue
        if git -C "$klon" cat-file -e "$COMMIT^{commit}" 2>/dev/null; then
            echo ">> Firn $KURZ aus dem Buendel $b"
            FIRN=$klon; break
        fi
    done
fi
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
#
# RUNDE GLYPHE: DER UNGEFLICKTE STAND WIRD VORHER WEGGELEGT.
#
# vendor/net/BLOBS nennt die Streuwerte, die Firn im Baum des
# festgenagelten Commits stehen hat -- also den Stand VOR den Flicken.
# Abschnitt 1 von ./test.sh prueft dagegen. Legt man die Flicken auf,
# ohne das Original zu behalten, misst der Pruefer den geflickten Stand
# gegen den ungeflickten Sollwert und ist dauerhaft rot -- oder man
# zieht BLOBS nach und verliert damit genau die Zusage, die er geben
# soll: dass sich der Stack unter uns nicht geaendert hat.
#
# Also: die Dateien, die ein Flicken anfasst, kommen vorher unveraendert
# nach lib/.roh/. Dort liest der Pruefer sie.
if [[ -d $HIER/patches ]]; then
    rm -rf "$HIER/lib/.roh"
    for f in "$HIER"/patches/*.patch; do
        [[ -e $f ]] || continue
        # Welche Dateien fasst dieser Flicken an? (die +++-Zeilen)
        while read -r ziel; do
            [[ -n $ziel ]] || continue
            [[ -f $HIER/lib/$ziel ]] || continue
            mkdir -p "$HIER/lib/.roh/$(dirname "$ziel")"
            [[ -e $HIER/lib/.roh/$ziel ]] || cp -p "$HIER/lib/$ziel" "$HIER/lib/.roh/$ziel"
        done < <(sed -n 's|^+++ [ab]/||p' "$f" | sed 's/\t.*//')
        echo ">> Flicken: $(basename "$f")"
        patch -p1 -d "$HIER/lib" -i "$f" --silent \
            || { echo "Flicken $(basename "$f") passt nicht auf Firn $KURZ" >&2
                 exit 1; }
    done
fi

# --- DIE SYMLINKS INNERHALB VON lib/ WIEDER EINHAENGEN.
#
# RUNDE 31, gemessen. `cp -rL` oben loest ALLE Verweise auf, auch die
# acht, die NICHT aus lib/ herausfuehren: lib/std/rt.fi -> ../rt/rt.fi
# und seine Geschwister. Aus EINER Datei werden dadurch ZWEI, und weil
# der Uebersetzer die Symbole einer Datei nach ihrem MODULNAMEN benennt
# (rt__Buf, rt__ld8, ...), sind `import std.rt` und `import rt.rt`
# danach zwei Module, die dieselben Namen anmelden:
#
#     error: struct 'rt__Buf' is already declared
#
# Vierzig solche Fehler, und kein einziger davon im eigenen Quelltext.
# Es fiel bis Runde 31 niemandem auf, weil kein Programm dieser Platte
# BEIDE Namen zog. fUi tut es: lib/fui/* importiert `std.rt`, und
# lib/paint/png.fi -- das fUi fuer die Bildausgabe braucht -- `rt.rt`.
#
# WARUM ERST HIER, NACH DEN FLICKEN: `patch` weigert sich, einen Symlink
# zu aendern ("File firnc1/rt.fi is not a regular file -- refusing to
# patch"), und 0002 fasst rt.fi in ALLEN DREI Verzeichnissen getrennt
# an. Also erst auf echten Dateien flicken, dann zusammenhaengen. Der
# Inhalt ist danach derselbe -- die drei Fassungen sind Oktett fuer
# Oktett gleich, das ist ja der Grund, warum sie im Firn-Baum Verweise
# sind.
#
# Die Liste kommt aus dem Firn-Baum SELBST, nicht aus dem Kopf: was dort
# ein Verweis ist, wird hier einer; was aus lib/ hinausfuehrt
# (lib/rc/rc.fi -> ../../tests/modules/rc.fi), bleibt Kopie, sonst waere
# es hier tot.
if [[ -d $BAU/lib ]]; then
    ( cd "$BAU/lib" && find . -type l -printf '%p\t%l\n' ) |
    while IFS=$'\t' read -r ort ziel; do
        [[ -e "$HIER/lib/$(dirname "$ort")/$ziel" ]] || continue
        # Sicherung: der Verweis darf den Inhalt nicht veraendern.
        if ! cmp -s "$HIER/lib/$ort" "$HIER/lib/$(dirname "$ort")/$ziel"; then
            echo "Symlink $ort wuerde den Inhalt aendern -- bleibt Kopie" >&2
            continue
        fi
        rm -f "$HIER/lib/$ort"
        ln -s "$ziel" "$HIER/lib/$ort"
    done
fi

echo ">> firnc1 bauen (der Uebersetzer in Firn, von firnc0 uebersetzt)"
FIRNLIB="$HIER/lib" "$HIER/bin/firnc" "$BAU/bin/firnc1.fi" -o "$HIER/bin/firnc1"

zweitnamen
echo "$MARKE" > "$HIER/.gebaut"
rm -rf "$BAU"
echo ">> fertig: vendor/firn/bin/firnc + bin/firnc1 + lib ($KURZ, Flicken $PSUM)"
