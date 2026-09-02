#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/struktur/run.sh -- RUNDE STRUKTUR: BLEIBT DIE ORDNUNG, DIE HIER
# ENTSTANDEN IST, AUCH DANN STEHEN, WENN NIEMAND MEHR DARAN DENKT?
#
#   ./tools/struktur/run.sh
#
# Ein Verzeichnisbaum ist keine Zusage. `kernel/drivers/net/e1000.fi` an
# den richtigen Ort zu legen kostet einen Nachmittag; die naechste Runde
# legt eine neue Datei flach nach `kernel/`, und in einem halben Jahr
# sieht der Baum wieder aus wie vorher. Was eine Ordnung haelt, ist nicht
# der Umzug, sondern die Probe, die den Rueckfall MELDET.
#
# Diese Runde hat dafuer drei Regeln aufgestellt (kernel/drivers/README.md).
# Alle drei sind hier maschinell gepruefte Zusagen -- und zwei davon
# stehen nicht aus Geschmack da, sondern weil ihr Bruch schon einmal
# einen echten Fehler erzeugt hat:
#
#   * `VEC_MOUSE = 46` und `VEC_NET + 1 = 46`: die PS/2-Maus und die
#     zweite Netzkarte lagen auf demselben Unterbrechungsvektor, und der
#     Mauszweig in trap.fi stand davor. Eine zweite Netzkarte waere als
#     Maus behandelt worden und haette nie eine Unterbrechung gesehen.
#     Ursache: der VEKTOR WURDE GERECHNET, an zwei Stellen, aus je einer
#     treiberinternen Einheitsnummer. Regel 3 verbietet genau das.
#   * `memmap.py` starb nach dem Umzug an einem KeyError, weil es
#     `kernel/*.fi` las und die Treiber nicht mehr sah -- derselbe Unfall
#     wie in Runde ARM. Darum laeuft es hier mit.
#
# Was hier NICHT geprueft wird: ob der Kern laeuft. Das tun die anderen
# Abschnitte. Diese Probe liest nur den Baum und ist in unter einer
# Sekunde fertig -- billig genug, um bei jedem Lauf dabei zu sein.
set -uo pipefail
cd "$(dirname "$0")/../.."

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

# Code-Zeilen, keine Kommentare. Ein Kommentar, der den ALTEN Ort nennt
# ("frueher lag das in kernel/kbd.fi"), ist Absicht und kein Rueckfall.
KEIN_KOMMENTAR='^[[:space:]]*([#]|//|\*|--)'
code() { grep -vE "$KEIN_KOMMENTAR"; }

# Die Chiptreiber je Klasse: Klasse:Schnittstelle:Chip[,Chip...]
KLASSEN="net:netdev:virtio,e1000
         blk:blk:nvme,ahci
         usb:usb:xhci"

echo "== 1. liegt noch alles dort, wo es hingehoert? =="

# Kein Treiber flach in kernel/. Der Umzug hat 17 Dateien bewegt; taucht
# einer der Namen wieder direkt unter kernel/ auf, ist er zurueckgefallen.
zurueck=0
for f in kernel/drivers/*/*.fi; do
    n=$(basename "$f")
    if [ -f "kernel/$n" ]; then
        bad "kernel/$n liegt wieder flach -- gehoert nach $(dirname "$f")/"
        zurueck=$((zurueck+1))
    fi
done
[ "$zurueck" -eq 0 ] && ok "kein Treiber liegt flach in kernel/ ($(ls kernel/drivers/*/*.fi | wc -l) Dateien in $(ls -d kernel/drivers/*/ | wc -l) Klassen)"

# Der Modulname IST der Dateiname. Zwei gleichnamige Dateien irgendwo im
# Kernbaum ergaeben doppelte Symbole -- und zwar erst beim Binden, weit
# weg von der Ursache.
# NICHT mitgezaehlt: kernel/user/. Das sind die Nutzerprogramme, und sie
# sind eine EIGENE Uebersetzungseinheit (uprog.fi, "nothing out of the
# kernel may be called here"). Dass es kernel/netview.fi UND
# kernel/user/netview.fi gibt, ist Absicht: der Dienst im Kern und das
# Programm, das ihn anzeigt. Erst als der erste Entwurf dieser Probe die
# beiden Baeume in einen Topf warf, meldete er fuenf "Fehler", von denen
# keiner einer war.
KERNEINHEIT() { find kernel -name '*.fi' -not -path 'kernel/user/*'; }
doppelt=$(KERNEINHEIT | xargs -n1 basename | sort | uniq -d)
if [ -z "$doppelt" ]; then
    ok "alle $(KERNEINHEIT | wc -l) Modulnamen der Kerneinheit sind eindeutig (kernel/user/ zaehlt eigen)"
else
    bad "doppelte Modulnamen in der Kerneinheit: $(echo "$doppelt" | tr '\n' ' ')"
fi

# ------------------------------------------------ der ehrliche Bestand
#
# Regel 1 gilt ab heute, sie gilt nicht rueckwirkend. `nvme.` wird 25
# mal direkt gerufen (21 mal in `kernel/hw.fi`, 3 mal in `hwid.fi`, 1
# mal in `trap.fi`), `ahci.` 22 mal (alle in `hw.fi`). Diese beiden
# Zahlen sind GEMESSEN, nicht geschaetzt: `git grep` gegen `main`
# liefert exakt dieselben 25 und 22 -- diese Runde hat also keine
# einzige Stelle hinzugefuegt. Es ist auch nicht rein willkuerlich:
# hw.fi FINDET die Platten (probe, init, MSI-X scharfstellen), waehrend
# `blk.fi` sie danach LIEST und SCHREIBT; die Naht liegt hinter der
# Erkennung, nicht davor.
#
# Diese Zahlen zu verschweigen waere bequem und falsch. Sie hier
# festzunageln ist das Ehrlichste, was geht: der Bestand darf bleiben,
# aber er darf nicht WACHSEN. Wer eine Stelle hinzufuegt, faellt.
# Wer eine wegraeumt, setzt die Zahl herunter -- sie soll kleiner
# werden, nicht groesser.
declare -A BESTAND=( [nvme]=25 [ahci]=22 )   # gemessen gegen main, 02.09.2026

echo
echo "== 2. Regel 1: der Kern nennt keinen Chip beim Namen =="

# Der Kern ruft netdev./blk./gfx. -- die Schnittstelle der Klasse. Wer
# ausserhalb der eigenen Klasse `virtio.` oder `nvme.` schreibt, hat die
# Tabelle uebersprungen, und der naechste Chip braucht ein `if`.
for eintrag in $KLASSEN; do
    klasse=${eintrag%%:*}; rest=${eintrag#*:}
    schnitt=${rest%%:*}; chips=${rest#*:}
    for chip in ${chips//,/ }; do
        # ueberall in der Kerneinheit ausser in der eigenen Klasse.
        # `.fi` ausgenommen: `import drivers.blk.nvme` ist kein Aufruf.
        treffer=$(grep -rn "\b$chip\.[a-z_0-9]" kernel --include='*.fi' 2>/dev/null \
                    | grep -v "^kernel/drivers/$klasse/" \
                    | grep -v "^kernel/user/" \
                    | grep -vE "^[^:]*:[0-9]+:[[:space:]]*(//|\*)" \
                    | grep -vE "^[^:]*:[0-9]+:[[:space:]]*import " \
                    | grep -vE "\b$chip\.fi\b")
        anzahl=$(printf '%s' "$treffer" | grep -c . )
        bestand=${BESTAND[$chip]:-0}
        if [ "$anzahl" -eq 0 ]; then
            ok "$chip wird nur innerhalb von drivers/$klasse/ beim Namen genannt (Naht: $schnitt)"
        elif [ "$anzahl" -le "$bestand" ]; then
            # Bestand, aelter als diese Runde -- siehe BESTAND oben.
            ok "$chip: $anzahl Aufrufe am Kern vorbei, alle aus dem Bestand (erlaubt: $bestand, waechst nicht)"
        else
            bad "$chip wird $anzahl mal am Kern vorbei gerufen, erlaubt sind $bestand aus dem Bestand -- die Naht $schnitt wird umgangen:"
            printf '%s\n' "$treffer" | head -5 | sed 's/^/          /'
        fi
    done
done

echo
echo "== 3. Regel 2: je Chip eine Datei, mit denselben Namen =="

# Die Pflichtnamen werden nicht hier gepflegt, sondern AUS DER
# SCHNITTSTELLE gelesen: was netdev.fi exportiert und mit `_on` endet,
# muss jeder Netztreiber koennen. Eine Liste, die man von Hand pflegt,
# ist nach der uebernaechsten Runde falsch.
for eintrag in $KLASSEN; do
    klasse=${eintrag%%:*}; rest=${eintrag#*:}
    schnitt=${rest%%:*}; chips=${rest#*:}
    sdatei="kernel/drivers/$klasse/$schnitt.fi"
    [ -f "$sdatei" ] || { bad "Schnittstellendatei $sdatei fehlt"; continue; }

    for chip in ${chips//,/ }; do
        cdatei="kernel/drivers/$klasse/$chip.fi"
        [ -f "$cdatei" ] || { bad "$cdatei fehlt"; continue; }
        # welche Namen ruft die Schnittstelle wirklich AUF diesem Chip auf?
        # NUR Code, und `import drivers.blk.nvme` ist kein Aufruf: der
        # erste Entwurf las aus `nvme.fi` den "Namen" `fi` heraus und
        # meldete ihn bei allen fuenf Chips als fehlend.
        gerufen=$(code < "$sdatei" \
                    | grep -vE '^[[:space:]]*import ' \
                    | grep -oE "\b$chip\.[a-z_0-9]+" \
                    | sed "s/^$chip\.//" | grep -vxE 'fi' | sort -u)
        fehlt=""
        anzahl=0
        for name in $gerufen; do
            anzahl=$((anzahl+1))
            grep -qE "^[[:space:]]*(pub )?(fn|def|fun|const|let)[[:space:]]+$name\b" "$cdatei" \
                || fehlt="$fehlt $name"
        done
        if [ -z "$fehlt" ]; then
            ok "$chip.fi liefert alle $anzahl Namen, die $schnitt.fi auf ihm ruft"
        else
            bad "$chip.fi fehlen Namen, die $schnitt.fi ruft:$fehlt"
        fi
    done
done

echo
echo "== 4. Regel 3: ein Vektor wird vergeben, nicht gerechnet =="

# DER FEHLER DIESER RUNDE, als Zusage: `virtio.fi` rechnete `VEC_NET + c`
# aus der Nummer der virtio-Karte, `e1000.fi` rechnete `45 + u` aus der
# Nummer der e1000-Karte. Bei GEMISCHTEN Karten bekamen beide die 45.
# Seither vergibt `netdev.vec_of(c)` den Vektor aus der GLOBALEN
# Kartennummer, und die Treiber bekommen ihn uebergeben.
rechner=$(grep -rn 'VEC_[A-Z_]*[[:space:]]*+\|4[0-9][[:space:]]*+[[:space:]]*u\b' \
            kernel --include='*.fi' 2>/dev/null \
          | grep -vE "^[^:]*:[0-9]+:[[:space:]]*(//|\*)" \
          | grep -v '^kernel/drivers/net/netdev.fi:')
if [ -z "$rechner" ]; then
    ok "kein Treiber rechnet sich einen Vektor aus -- nur netdev.vec_of vergibt"
else
    bad "ein Vektor wird ausserhalb von netdev.vec_of gerechnet:"
    printf '%s\n' "$rechner" | sed 's/^/          /'
fi

grep -qE '^[[:space:]]*fn[[:space:]]+vec_of' kernel/drivers/net/netdev.fi \
    && ok "netdev.vec_of ist die eine Stelle, die Vektoren vergibt" \
    || bad "netdev.vec_of fehlt -- dann vergibt sie niemand"

# Und die Gegenrichtung: aus dem Vektor die Karte. Ohne sie muesste der
# Unterbrechungsbehandler wieder selbst rechnen.
grep -qE '^[[:space:]]*fn[[:space:]]+card_of_vec' kernel/drivers/net/netdev.fi \
    && ok "netdev.card_of_vec loest den Vektor wieder auf" \
    || bad "netdev.card_of_vec fehlt"

echo
echo "== 5. die Speicher- und Vektorkarte =="

# memmap.py ist genau das Werkzeug, das der Umzug zerbrochen hat (es las
# kernel/*.fi und sah die Treiber nicht mehr). Es hier laufen zu lassen
# haelt zweierlei fest: dass es den Baum noch findet, und dass sich
# weder Bereiche noch Vektoren ueberschneiden.
karte=$(python3 tools/kernel/memmap.py 2>&1)
letzte=$(printf '%s' "$karte" | tail -1)
case "$letzte" in
    *"0 Kollisionen"*) ok "memmap.py: $letzte" ;;
    *) bad "memmap.py: $letzte"; printf '%s\n' "$karte" | tail -8 | sed 's/^/          /' ;;
esac

echo
echo "== 6. zeigt ein Pfad ins Leere? =="

pfadlauf=$(bash tools/struktur/pfade.sh 2>&1)
pfadrc=$?
letzte=$(printf '%s' "$pfadlauf" | tail -1)
if [ "$pfadrc" -eq 0 ]; then
    ok "pfade.sh: $letzte"
else
    bad "pfade.sh: $letzte"
    printf '%s\n' "$pfadlauf" | grep -A1 'TOT' | head -10 | sed 's/^/          /'
fi

echo
echo "== 7. die Leerfassung der Grafik =="

# `--gui off` baut Osum ohne eine Zeile Grafik, indem gfx-aus.fi an die
# Stelle von gfx.fi tritt. Fehlt dort ein Name, den gfx.fi hat, faellt
# nicht diese Probe, sondern der Bau -- aber erst nach Minuten, und nur
# in der Fassung, die seltener gebaut wird. Hier kostet es Millisekunden.
namen() { grep -oE '^[[:space:]]*(pub )?(fn|def|fun)[[:space:]]+[a-z_0-9]+' "$1" \
            | sed 's/.*[[:space:]]//' | sort -u; }
nur_an=$(comm -23 <(namen kernel/drivers/gfx/gfx.fi) <(namen kernel/drivers/gfx/gfx-aus.fi) | tr '\n' ' ')
nur_aus=$(comm -13 <(namen kernel/drivers/gfx/gfx.fi) <(namen kernel/drivers/gfx/gfx-aus.fi) | tr '\n' ' ')
if [ -z "${nur_an// }" ] && [ -z "${nur_aus// }" ]; then
    ok "gfx-aus.fi deckt gfx.fi Name fuer Name ab ($(namen kernel/drivers/gfx/gfx.fi | wc -l) Funktionen)"
else
    [ -n "${nur_an// }" ]  && bad "gfx-aus.fi fehlen: $nur_an"
    [ -n "${nur_aus// }" ] && bad "gfx-aus.fi hat zuviel: $nur_aus"
fi

# Und die Liste, aus der `--gui off` loescht, muss den Baum kennen.
lueckenhaft=""
for f in kernel/drivers/gfx/*.fi; do
    n=$(basename "$f")
    [ "$n" = "gfx.fi" ] && continue      # wird ersetzt, nicht geloescht
    [ "$n" = "gfx-aus.fi" ] && continue  # ist die Ersatzfassung selbst
    grep -q "drivers/gfx/$n" tools/build-kernel.sh || lueckenhaft="$lueckenhaft $n"
done
if [ -z "$lueckenhaft" ]; then
    ok "GFX_DATEIEN in build-kernel.sh kennt jede Datei in drivers/gfx/"
else
    bad "GFX_DATEIEN fehlt:$lueckenhaft -- --gui off zoege Grafik in ein Abbild ohne Grafik"
fi

echo
echo "== 8. hat diese Probe Zaehne? =="

# Eine gruene Probe ist so viel wert wie die Frage, ob sie ueberhaupt
# rot werden KANN. `gegenprobe.sh` bricht jede der Zusagen oben genau
# einmal -- in einem WEGWERFBAUM, nicht hier -- und verlangt, dass
# dieses Skript es meldet. Ohne das waere Abschnitt 1-7 eine Behauptung.
#
# STRUKTUR_IN_GEGENPROBE ist die Rekursionssperre: gegenprobe.sh ruft
# run.sh, und run.sh ruft gegenprobe.sh. Ohne die Sperre liefen die
# beiden bis zum Speicherende umeinander.
if [ "${STRUKTUR_IN_GEGENPROBE:-0}" = "1" ]; then
    ok "Gegenprobe: laeuft gerade selbst (nicht erneut)"
elif [ "${OSUM_OHNE_GEGENPROBE:-0}" = "1" ]; then
    ok "Gegenprobe: abgeschaltet (OSUM_OHNE_GEGENPROBE=1)"
else
    gp=$(STRUKTUR_IN_GEGENPROBE=1 bash tools/struktur/gegenprobe.sh 2>&1)
    gprc=$?
    gpletzte=$(printf '%s' "$gp" | tail -1)
    case "$gpletzte" in
        *uebersprungen*) ok "$gpletzte" ;;
        *) if [ "$gprc" -eq 0 ]; then ok "$gpletzte"
           else bad "$gpletzte"
                printf '%s\n' "$gp" | grep -E 'BLIND|FAIL' | head -5 | sed 's/^/          /'
           fi ;;
    esac
fi

echo
echo "== 9. die Bilanz =="
printf 'STRUKTUR: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
