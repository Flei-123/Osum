#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/struktur/pfade.sh -- ZEIGT EIN PFAD INS LEERE?
#
#   ./tools/struktur/pfade.sh [--streng]
#
# Ein Werkzeug, das `grep -aE '^const FOO' kernel/fb.fi` schreibt, faellt
# nach einem Umzug NICHT aus: `grep` findet nichts, die Variable ist
# leer, und der Vergleich danach ist still falsch. Genau das ist in
# Runde STRUKTUR passiert -- und in Runde ARM davor schon einmal, mit
# `hv.fi`, als der Kartenpruefer mitten in der Abnahme an einem KeyError
# starb.
#
# Darum diese Probe: sie sammelt jeden Pfad der Form `kernel/....fi` aus
# den Werkzeugen und der Doku und sieht nach, ob es die Datei GIBT.
#
# ZWEI SORTEN TREFFER, und sie werden auseinandergehalten:
#
#   * WERKZEUGE (tools/, test.sh) -- ein toter Pfad ist hier ein Fehler,
#     denn ein Skript liest ihn. Beendigungscode 1.
#   * DOKU (docs/, README.md) -- ein toter Pfad ist hier eine veraltete
#     Zeile. Sie wird gemeldet, aber sie laesst die Probe nur mit
#     --streng fallen: die RUNDENBERICHTE unter docs/ beschreiben mit
#     Absicht den Baum von damals, und einen abgeschlossenen Messbericht
#     nachtraeglich umzuschreiben ist keine Pflege, sondern
#     Geschichtsfaelschung.
#
# BEKANNT UND NICHT VON DIESER RUNDE: zehn Pfade zeigen schon auf `main`
# ins Leere -- kernel/apic.fi, guard.fi, hv.fi, idt.fi, smp.fi, trap.fi,
# user.fi, vmcb.fi (die liegen seit Runde ARM unter arch/x86_64/),
# kernel/arch/x86_64/machine.fi und kernel/user/schummel.fi. Sie stehen
# in der Ausgabe unter ALT.
set -uo pipefail
cd "$(dirname "$0")/../.."

STRENG=0
[[ ${1:-} == --streng ]] && STRENG=1

# Die zehn, die es schon vor dieser Runde gab. Wer einen davon aufraeumt,
# streicht ihn hier -- die Liste soll kuerzer werden, nicht laenger.
ALTLASTEN="kernel/apic.fi kernel/guard.fi kernel/hv.fi kernel/idt.fi
           kernel/smp.fi kernel/trap.fi kernel/user.fi kernel/vmcb.fi
           kernel/arch/x86_64/machine.fi kernel/user/schummel.fi"

ist_altlast() {
    for a in $ALTLASTEN; do [[ $1 == "$a" ]] && return 0; done
    return 1
}

# NUR CODE, KEINE KOMMENTARE. Ein Skript LIEST einen Pfad nur in einer
# Code-Zeile; steht `kernel/kbd.fi` in einem Kommentar, ist das fast immer
# eine ABSICHTLICHE Nennung des alten Ortes ("frueher lag das hier") --
# und die soll nach dem Umzug stehen bleiben duerfen, sonst zwingt diese
# Probe dazu, die eigene Umzugsgeschichte zu loeschen. Genau daran hat
# sich der erste Entwurf dieses Skripts verschluckt: er meldete vier
# TOT-Treffer, und alle vier standen in den Kommentaren von umzug.sh,
# pruefe.sh und dieser Datei hier.
# Preis, offen benannt: auskommentierter Code wird nicht mehr geprueft.
KEIN_KOMMENTAR='^[[:space:]]*([#]|//|\*|--)'

# EINE AUSNAHME, und sie muss im Skript selbst stehen: wer die Zeile
#     PFADE-AUSNAHME
# in eine Datei schreibt, nimmt sie hier heraus. Das ist kein Schlupfloch
# fuer Bequeme, sondern noetig fuer Skripte, die absichtlich Pfade
# nennen, die es NICHT geben soll -- `tools/struktur/gegenprobe.sh`
# baut genau solche Pfade ein, um zu pruefen, dass die Probe sie findet.
# (Auch das ist gemessen: ohne die Ausnahme meldete diese Datei drei
# TOT-Treffer aus der Gegenprobe -- richtig erkannt, falsch gewertet.)
AUSNAHME='PFADE-AUSNAHME'

sammle() { # verzeichnisse...
    local d
    for d in $(grep -rlI -E 'kernel/[A-Za-z0-9_/-]+\.fi' "$@" 2>/dev/null); do
        grep -qF "$AUSNAHME" "$d" && continue
        grep -hE 'kernel/[A-Za-z0-9_/-]+\.fi' "$d" 2>/dev/null | grep -vE "$KEIN_KOMMENTAR"
    done | grep -oE 'kernel/[A-Za-z0-9_/-]+\.fi' | sort -u
}

# und dieselbe Ausnahme beim Zeigen der Fundstelle
fundstelle() { # pfad
    local d
    for d in $(grep -rlI -F "$1" tools/ test.sh 2>/dev/null); do
        grep -qF "$AUSNAHME" "$d" && continue
        grep -n -F "$1" "$d" | sed "s|^|$d:|"
    done | grep -vE "^[^:]*:[0-9]+:[[:space:]]*([#]|//|\*|--)"
}

fehler=0; alt=0; doku=0
echo "PFADE: zeigt ein kernel/-Pfad ins Leere?"

echo "  ---- Werkzeuge (tools/, test.sh) ----"
for p in $(sammle tools/ test.sh); do
    [[ -f $p ]] && continue
    if ist_altlast "$p"; then
        echo "        ALT  $p (aelter als Runde STRUKTUR)"; alt=$((alt+1))
    else
        echo "        TOT  $p"
        fundstelle "$p" | head -3 | sed 's/^/             /'
        fehler=$((fehler+1))
    fi
done
[[ $fehler -eq 0 ]] && echo "        ok -- kein toter Pfad in den Werkzeugen"

echo "  ---- Doku (README.md, docs/ARCH.md) ----"
for p in $(sammle README.md docs/ARCH.md); do
    [[ -f $p ]] && continue
    if ist_altlast "$p"; then
        echo "        ALT  $p"; alt=$((alt+1))
    else
        echo "        VERALTET  $p"; doku=$((doku+1))
    fi
done
[[ $doku -eq 0 ]] && echo "        ok -- kein toter Pfad in der aktiven Doku"

echo "PFADE: $fehler tot, $doku veraltet, $alt alt (bekannt)"
if [[ $fehler -gt 0 ]]; then exit 1; fi
if [[ $STRENG -eq 1 && $doku -gt 0 ]]; then exit 1; fi
exit 0
