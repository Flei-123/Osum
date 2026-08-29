#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/lib/parallel-patch.py -- test.sh parallelisieren, OHNE eine einzige
# `lauf "..."`-Zeile anzufassen.
#
# Das ist Absicht: die Runde `kvmfix` haengt genau eine neue `lauf`-Zeile in
# test.sh ein. Wenn diese Runde nur die MASCHINERIE austauscht (die
# Funktion `lauf` und die Schlussbilanz) und die Liste der Abschnitte
# Zeichen fuer Zeichen so laesst, wie sie ist, fuehren sich die beiden
# Zweige ohne Konflikt zusammen.

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TEST = ROOT / "test.sh"

NEU = r'''
# ======================================================================
# RUNDE TESTFAST -- DIE ABSCHNITTE LAUFEN GLEICHZEITIG.
#
# Bis zu dieser Runde arbeitete test.sh die Abschnitte streng nacheinander
# ab. Auf einem Wirt mit zwoelf Kernen lag damit die Maschine zu elf
# Zwoelfteln still, waehrend ein einzelnes QEMU rechnete.
#
#   $OSUM_JOBS   wieviele Abschnitte gleichzeitig. Standard: nproc/2.
#                OSUM_JOBS=1 ergibt das alte, streng serielle Verhalten --
#                dieselbe Reihenfolge, dieselbe Ausgabe, derselbe Weg
#                durch den Code.
#   $OSUM_ZEIT   0 schaltet die Zeitangabe je Abschnitt ab (Standard 1).
#
# DREI DINGE, DIE DABEI SCHIEFGEHEN KOENNTEN, UND WAS DAGEGEN GETAN IST:
#
#   1. GETEILTE ARBEITSVERZEICHNISSE. Nachgesehen: alle vierunddreissig
#      Laeufer holen sich ihr Verzeichnis mit `mktemp -d`, und jeder
#      Monitor-Socket liegt darin ($TMPD/mon*.sock). Es gibt keinen festen
#      Pfad, um den sich zwei streiten koennten. Die Protokolle gehen nach
#      .test-work/<name>.log, und die Namen sind paarweise verschieden.
#
#   2. DAS NETZ. Vier Abschnitte -- net, netmon, netview und tunnel --
#      bauen sich eine Netzwerk-Namensraum und ein veth-Paar. Die Namen
#      haengen zwar an $$ (k8net-$$, nv0-$$ ...), aber:
#        * net und netview nennen das ferne Ende BEIDE `v1`, und zwischen
#          `ip link add ... peer name v1` und `ip link set v1 netns <ns>`
#          existiert dieser Name GLOBAL. Zwei Laeufe, die sich dort
#          treffen, geben "RTNETLINK answers: File exists".
#        * netmon und netview rechnen ihren Anschluss BEIDE als
#          5800 + ($$ % 90) * 2 aus -- derselbe Wert ist moeglich.
#      Darum laufen genau diese vier untereinander SERIELL, ueber eine
#      Sperre (flock). Zu allem anderen laufen sie weiterhin gleichzeitig.
#      Entschaerft wird dabei nichts: jeder der vier macht genau das, was
#      er vorher gemacht hat.
#
#   3. DIE AUSGABE. Ein halbes Dutzend Laeufer, die gleichzeitig auf
#      dieselbe Konsole schreiben, ergibt Konfetti. Deshalb schreibt jeder
#      in SEIN Protokoll, und ausgegeben wird am Stueck und in der
#      REIHENFOLGE, IN DER DIE ABSCHNITTE IM SKRIPT STEHEN -- Abschnitt 5
#      erscheint vor Abschnitt 6, auch wenn 6 frueher fertig war. Die
#      Ausgabe eines parallelen Laufs ist damit dieselbe wie die eines
#      seriellen.

JOBS=${OSUM_JOBS:-$(( $(nproc 2>/dev/null || echo 2) / 2 ))}
[ "$JOBS" -ge 1 ] 2>/dev/null || JOBS=1
ZEIT=${OSUM_ZEIT:-1}

# Diese Abschnitte teilen sich Namen im Netz des Wirts und bleiben
# untereinander seriell. Siehe Punkt 2 oben.
SERIELL_RE='^tools/(net|netmon|netview|tunnel)/'
NETZSPERRE="$WORK/.netz.lock"
: > "$NETZSPERRE"

PASS=0
FAIL=0
FAILED=""
ZUSAGEN=0

# Die angemeldeten Abschnitte, in der Reihenfolge des Skripts.
A_TITEL=(); A_SKRIPT=(); A_NAME=(); A_MUSTER=()

ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); FAILED="$FAILED\n  $1"; echo "  FEHLER  $1"; }

# Zaehlt die Zusagen aus der Schlusszeile eines Laeufers
# ("NAME: 174 passed, 0 failed") auf die Gesamtsumme.
zusagen() {
    local log=$1
    local n
    # `[A-Z][A-Z0-9]*` und nicht `[A-Z]+`: der Laeufer von Runde K11
    # meldet sich als "K11:", und mit dem alten Muster waeren seine
    # Zusagen still unter den Tisch gefallen.
    n=$(grep -aoE '^[A-Z][A-Z0-9]*: [0-9]+ (passed|proofs)' "$log" | tail -1 | grep -oE '[0-9]+' | tail -1)
    [ -n "${n:-}" ] && ZUSAGEN=$((ZUSAGEN + n))
}

# EINEN Abschnitt wirklich ausfuehren. Schreibt Protokoll, Beendigungscode
# und Dauer; ruehrt KEINE Zaehler an (die gehoeren dem Hauptprozess).
abschnitt_ausfuehren() { # index
    local i=$1
    local skript=${A_SKRIPT[$i]} name=${A_NAME[$i]}
    local rc=0 s e
    s=$(date +%s%N)
    if [[ "$skript" =~ $SERIELL_RE ]]; then
        flock "$NETZSPERRE" bash "$skript" > "$WORK/$name.log" 2>&1 || rc=$?
    else
        bash "$skript" > "$WORK/$name.log" 2>&1 || rc=$?
    fi
    e=$(date +%s%N)
    printf '%s\n' "$rc"                > "$WORK/.rc.$i"
    printf '%s\n' "$(( (e - s) / 1000000 ))" > "$WORK/.ms.$i"
    : > "$WORK/.done.$i"
}

# EINEN fertigen Abschnitt ausgeben und verbuchen. Nur im Hauptprozess.
abschnitt_ausgeben() { # index
    local i=$1
    local titel=${A_TITEL[$i]} skript=${A_SKRIPT[$i]}
    local name=${A_NAME[$i]} muster=${A_MUSTER[$i]}
    local rc ms
    rc=$(cat "$WORK/.rc.$i" 2>/dev/null || echo 1)
    ms=$(cat "$WORK/.ms.$i" 2>/dev/null || echo 0)
    echo "== $titel =="
    grep -aE "$muster" "$WORK/$name.log" | sed 's/^ */   /'
    zusagen "$WORK/$name.log"
    if [ "$rc" -eq 0 ]; then
        ok
    else
        bad "$skript ist fehlgeschlagen (siehe .test-work/$name.log)"
        grep -aE '^  FAIL' "$WORK/$name.log" | head -12 | sed 's/^/     /'
    fi
    if [ "$ZEIT" = "1" ]; then
        printf '   [%s  %d,%03d s  %s]\n' \
            "$(grep -am1 '^accel: ' "$WORK/$name.log" | sed 's/^accel: //;s/ (.*//' || true)" \
            "$(( ms / 1000 ))" "$(( ms % 1000 ))" "$name"
    fi
}

# Ein Abschnitt: Nummer+Titel, Skript, Logname, Muster fuer die Zeilen,
# die auch bei Erfolg zu sehen sein sollen.
#
# Bei OSUM_JOBS=1 wird sofort ausgefuehrt und sofort ausgegeben -- genau
# wie frueher. Sonst wird der Abschnitt nur angemeldet; abgearbeitet wird
# alles zusammen in `abschnitte_abarbeiten` weiter unten.
lauf() { # titel skript logname muster
    local i=${#A_SKRIPT[@]}
    A_TITEL+=("$1"); A_SKRIPT+=("$2"); A_NAME+=("$3"); A_MUSTER+=("$4")
    if [ "$JOBS" -le 1 ]; then
        abschnitt_ausfuehren "$i"
        abschnitt_ausgeben "$i"
    fi
}

# Alle angemeldeten Abschnitte gleichzeitig abarbeiten, hoechstens $JOBS
# auf einmal -- und die Ergebnisse in der Reihenfolge des Skripts
# ausgeben. Bei OSUM_JOBS=1 ist hier nichts mehr zu tun.
abschnitte_abarbeiten() {
    local n=${#A_SKRIPT[@]} i
    [ "$JOBS" -le 1 ] && return 0
    [ "$n" -gt 0 ] || return 0

    echo "-- $n Abschnitte, $JOBS gleichzeitig" \
         "(OSUM_JOBS=1 fuer den alten seriellen Lauf) --"
    echo

    rm -f "$WORK"/.done.* "$WORK"/.rc.* "$WORK"/.ms.*

    # Der Verteiler laeuft im Hintergrund und haelt $JOBS Plaetze besetzt.
    (
        for ((i = 0; i < n; i++)); do
            while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do
                wait -n 2>/dev/null || break
            done
            abschnitt_ausfuehren "$i" &
        done
        wait
    ) &
    local verteiler=$!

    # Einsammeln in der Reihenfolge des Skripts.
    for ((i = 0; i < n; i++)); do
        while [ ! -f "$WORK/.done.$i" ]; do
            if ! kill -0 "$verteiler" 2>/dev/null; then
                # Der Verteiler ist weg. Entweder ist die Datei gerade
                # doch noch gekommen, oder dieser Abschnitt ist nie
                # gelaufen -- dann faellt er unten als Fehler auf.
                sleep 0.3
                [ -f "$WORK/.done.$i" ] || break
            fi
            sleep 0.2
        done
        abschnitt_ausgeben "$i"
    done
    wait "$verteiler" 2>/dev/null || true

    # Die Zeittabelle. Ohne sie ist jede Aussage ueber "schneller"
    # eine Behauptung.
    if [ "$ZEIT" = "1" ]; then
        echo
        echo "-- Zeit je Abschnitt, laengster zuerst --"
        for ((i = 0; i < n; i++)); do
            printf '%8d %s %s\n' "$(cat "$WORK/.ms.$i" 2>/dev/null || echo 0)" \
                "$(grep -am1 '^accel: ' "$WORK/${A_NAME[$i]}.log" 2>/dev/null | sed 's/^accel: //;s/ (.*//' || echo '?')" \
                "${A_NAME[$i]}"
        done | sort -rn | awk '{printf "   %6d,%03d s  %-5s %s\n", $1/1000, $1%1000, $2, $3}'
    fi
}
'''.lstrip("\n")


def main():
    txt = TEST.read_text()

    if "abschnitte_abarbeiten" in txt:
        print("test.sh ist schon umgebaut -- nichts zu tun")
        return 0

    # 1. Den alten Maschinerie-Block ersetzen: von `PASS=0` bis zum Ende
    #    der Funktion `lauf`.
    anfang = txt.index("\nPASS=0\n") + 1
    marke = "        grep -aE '^  FAIL' \"$WORK/$name.log\" | head -12 | sed 's/^/     /'\n    fi\n}\n"
    ende = txt.index(marke) + len(marke)
    txt = txt[:anfang] + NEU + txt[ende:]

    # 2. `abschnitte_abarbeiten` unmittelbar vor die Schlussbilanz.
    bilanz = '\necho\necho "=================================================================="\n'
    if bilanz not in txt:
        print("FEHLER: die Schlussbilanz sehe ich nicht", file=sys.stderr)
        return 1
    txt = txt.replace(
        bilanz,
        "\n# Hier laufen die angemeldeten Abschnitte -- bei OSUM_JOBS=1 sind sie\n"
        "# oben schon gelaufen und das hier tut nichts.\n"
        "abschnitte_abarbeiten\n" + bilanz,
        1)

    # 3. Eine Zeile in die Schlussbilanz, die sagt, WIE gemessen wurde.
    txt = txt.replace(
        'echo "=================================================================="\n',
        'echo "=================================================================="\n'
        'echo "gelaufen mit OSUM_JOBS=$JOBS, accel=${OSUM_ACCEL:-auto}"\n', 1)

    TEST.write_text(txt)
    print("test.sh umgebaut:")
    print("  * lauf() meldet an statt sofort auszufuehren (ausser OSUM_JOBS=1)")
    print("  * abschnitte_abarbeiten() vor der Schlussbilanz")
    print("  * keine einzige `lauf \"...\"`-Zeile angefasst")
    return 0


if __name__ == "__main__":
    sys.exit(main())
