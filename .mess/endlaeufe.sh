#!/usr/bin/env bash
# .mess/endlaeufe.sh -- die beiden Schlussmessungen der Runde TESTFAST,
# gestartet erst dann, wenn der Wirt WIRKLICH frei ist.
#
# Auf diesem Rechner laufen mehrere Runden gleichzeitig. Waehrend der
# ersten Messungen lagen zeitweise vier volle Abnahmen nebeneinander
# (Last 10-12 auf 12 Kernen). Eine GESAMTZEIT, die unter solcher Last
# genommen wird, misst die anderen Runden mit und ist als Aussage ueber
# diese Runde wertlos. Also: warten, bis kein fremdes test.sh mehr
# laeuft und die Last unter 2 liegt, und dann erst messen.
#
#   Lauf C (nachher): OSUM_JOBS=6, accel=auto -> kvm
#   Lauf V (vorher):  OSUM_JOBS=1, OSUM_ACCEL=tcg
#
# NACHEINANDER, nicht gleichzeitig -- sonst messen sich die beiden
# gegenseitig.

set -u
cd /root/tf-osum
MESS=/root/tf-osum/.mess
PROT=$MESS/endlaeufe-protokoll.txt

sage() { echo "[$(date +%H:%M:%S)] $*" >> "$PROT"; }

fremde() {
    # test.sh-Prozesse, die NICHT zu dieser Runde gehoeren
    local n=0 p
    for p in $(pgrep -f 'bash \./?test\.sh' 2>/dev/null); do
        local cwd
        cwd=$(readlink "/proc/$p/cwd" 2>/dev/null)
        case "$cwd" in
            /root/tf-osum|/root/tf-osum-a) ;;
            "") ;;
            *) n=$((n + 1)) ;;
        esac
    done
    echo "$n"
}

: > "$PROT"

# WARUM NICHT AUF RUHE GEWARTET WIRD: der erste Versuch tat genau das --
# warten, bis kein fremdes test.sh mehr laeuft und die Last unter 2 ist.
# Nach einer halben Stunde war klar, dass das nie eintritt: auf diesem
# Wirt laufen dauernd mehrere Runden nebeneinander, und waehrend des
# Wartens kamen sogar noch welche dazu. Wer auf Ruhe wartet, misst nie.
#
# Also der ehrliche Weg statt des schoenen: BEIDE Laeufe nacheinander
# unter derselben Art von Grundlast, und die Last wird alle 30 s
# mitgeschrieben (.mess/last-C.txt, .mess/last-V.txt). Damit steht im
# Bericht nicht nur die Zeit, sondern auch, was der Wirt daneben tat.
# NACHEINANDER und nicht gleichzeitig -- sonst messen sich die beiden
# Laeufe gegenseitig.

lastschreiber() {
    while :; do
        printf '%s load=%s fremd=%s\n' "$(date +%H:%M:%S)" \
            "$(cut -d' ' -f1-3 /proc/loadavg)" "$(fremde)" >> "$1"
        sleep 30
    done
}

sage "Start ohne auf Ruhe zu warten -- die Last wird mitgeschrieben"
sage "Grundlast jetzt: $(cut -d' ' -f1-3 /proc/loadavg), fremde Abnahmen: $(fremde)"

# ---- Lauf C: nachher (KVM, parallel) --------------------------------
sage "Lauf C startet: OSUM_JOBS=6, accel=auto"
lastschreiber "$MESS/last-C.txt" & LS=$!
s=$(date +%s)
OSUM_JOBS=6 OSUM_WORK=/root/tf-osum/.work-C \
    bash test.sh > "$MESS/C-kvm-parallel.log" 2>&1
rc=$?
e=$(date +%s)
kill $LS 2>/dev/null
sage "Lauf C fertig nach $((e - s)) s, rc=$rc"
echo "$((e - s))" > "$MESS/C-dauer.txt"

sleep 20

# ---- Lauf V: vorher (TCG, seriell) ----------------------------------
sage "Lauf V startet: OSUM_JOBS=1, OSUM_ACCEL=tcg"
lastschreiber "$MESS/last-V.txt" & LS=$!
s=$(date +%s)
OSUM_JOBS=1 OSUM_ACCEL=tcg OSUM_WORK=/root/tf-osum/.work-V \
    bash test.sh > "$MESS/V-tcg-seriell.log" 2>&1
rc=$?
e=$(date +%s)
kill $LS 2>/dev/null
sage "Lauf V fertig nach $((e - s)) s, rc=$rc"
echo "$((e - s))" > "$MESS/V-dauer.txt"

sage "beide Endlaeufe durch"
