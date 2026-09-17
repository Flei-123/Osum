#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/struktur/importe-richten.sh -- jede import-Zeile auf den Ort
# bringen, an dem die Datei WIRKLICH liegt.
#
#   bash tools/struktur/importe-richten.sh [--trocken]
#
# Statt beim Verschieben zu raten, welche Aufrufer es gibt, liest
# dieses Skript den Baum, wie er IST: fuer jedes Modul den Ort, und
# danach fuer jede import-Zeile den Pfad, der dorthin fuehrt.
#
# WARUM ES DAS GIBT: `kernel/kmain.fi` enthaelt eingebettete Oktette
# (ein Abbild), und `grep -rl` haelt die Datei deshalb fuer BINAER --
# ohne `-a` taucht sie in keiner Trefferliste auf. Genau das ist
# passiert: 45 import-Zeilen der Wurzel blieben beim ersten Umzug
# stehen, und der Bau brach mit "cannot read 'kernel/time.fi'" ab.
# Ein Werkzeug, das den Ist-Zustand liest, kann diesen Fehler nicht
# noch einmal machen.
#
# Es aendert NUR Zeilen der Form `import <pfad>.<modul>` bzw.
# `import <modul>` -- und nur dann, wenn der Pfad nicht schon stimmt.
set -uo pipefail
cd "$(dirname "$0")/../.."

TROCKEN=0
[[ ${1:-} == --trocken ]] && TROCKEN=1

# 1. Wo liegt welches Modul? NUR die Dateien, die das Abbild wirklich
# erreicht (`huelle.py`). Sonst faenge man sich `kernel/core.fi` ein --
# eine Datei ausserhalb des Abbilds, deren Name mit den FREMDEN
# Paketmodulen `fui.core` und `std.core` zusammenfaellt. Die duerfen
# NICHT umgeschrieben werden: sie kommen aus `lib/`, nicht aus
# `kernel/`.
declare -A ORT
while IFS= read -r rel; do
    m=$(basename "$rel" .fi)
    d=$(dirname "$rel")
    [[ $d == "." ]] && ORT[$m]="" || ORT[$m]="${d//\//.}."
done < <(python3 tools/struktur/huelle.py --liste kern
         python3 tools/struktur/huelle.py --liste uprog)

# 2. Jede .fi durchgehen und die import-Zeilen richten.
GEAENDERT=0
ZEILEN=0
while IFS= read -r f; do
    # -a: `kmain.fi` ist wegen eingebetteter Oktette "binaer".
    mapfile -t TREFFER < <(grep -aoE '^[ \t]*import[ \t]+[A-Za-z_][A-Za-z0-9_.]*([ \t]*//.*)?$' "$f" 2>/dev/null)
    [[ ${#TREFFER[@]} -eq 0 ]] && continue
    DIRTY=0
    for z in "${TREFFER[@]}"; do
        # Ein Nachsatz (`import time // ...`) bleibt erhalten -- genau
        # diese eine Zeile in `kernel/wm.fi` hat den ersten Umzug
        # auflaufen lassen, weil das Muster am Zeilenende endete.
        pfad=$(echo "$z" | sed -E 's|^[ \t]*import[ \t]+||; s|[ \t]*//.*$||; s|[ \t]*$||')
        modul=${pfad##*.}
        # Nur Module, die es im Kernbaum gibt (lib/-Module wie `utf8`
        # liegen ausserhalb und bleiben unberuehrt).
        [[ -v ORT[$modul] ]] || continue
        soll="${ORT[$modul]}$modul"
        [[ $pfad == "$soll" ]] && continue
        # SUCHORDNUNG DES UEBERSETZERS, SCHRITT 1: neben der
        # importierenden Datei. Liegt das Ziel im SELBEN Verzeichnis,
        # ist der nackte Name richtig -- `kernel/arch/x86_64/smp.fi`
        # schreibt `import apic`, und das findet `apic.fi` nebenan.
        # Diese Zeilen duerfen NICHT angefasst werden.
        eigen=$(dirname "${f#kernel/}")
        [[ $eigen == "." ]] && eigen="" || eigen="${eigen//\//.}."
        [[ $pfad == "$modul" && ${ORT[$modul]} == "$eigen" ]] && continue
        # FREMDE PAKETE BLEIBEN FREMD. Ein Pfad mit einem Praefix, das
        # KEIN Verzeichnis unter kernel/ ist, zeigt nach `lib/` --
        # `libc.errno`, `fui.painter`, `std.core`, `crypto.sha256`
        # aus `lib/crypto/`. Solche Zeilen gehoeren nicht dieser Runde.
        # (Ein Lauf ohne diese Pruefung hat `libc.errno` in 32
        # Programmen zu `lib.errno` gemacht.)
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
