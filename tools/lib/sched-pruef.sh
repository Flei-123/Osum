#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/lib/sched-pruef.sh -- die PARALLELMASCHINERIE von test.sh pruefen,
# ohne eine einzige Minute QEMU zu verbrennen.
#
#   bash tools/lib/sched-pruef.sh
#
# WARUM DAS HIER LIEGT UND NICHT IN /tmp: die erste Fassung dieser Pruefung
# lag in /tmp und war nach einem Neustart des Wirts weg -- mitten in der
# Messung. Eine Pruefung, die man nach einem Neustart neu schreiben muss,
# ist keine.
#
# GEPRUEFT WIRD:
#   1. dass parallel schneller ist als seriell (mit bekannten Schlafzeiten),
#   2. dass BEIDE Wege dieselbe Bilanz liefern (PASS/FAIL/Zusagen),
#   3. dass die Ausgabe in BEIDEN Faellen in der Reihenfolge des Skripts
#      steht -- auch wenn ein spaeterer Abschnitt frueher fertig ist,
#   4. dass die vier Netz-Abschnitte sich NIE ueberschneiden (die Zeitspur
#      wird nachgerechnet, nicht geglaubt),
#   5. dass ein durchgefallener Abschnitt in beiden Faellen durchfaellt.
#
# Die Stubs schlafen absichtlich RUECKWAERTS (der erste am laengsten),
# damit die Reihenfolge der Ausgabe nicht zufaellig stimmt.

set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

STUB=$(mktemp -d)
trap 'rm -rf "$STUB"' EXIT

# --- die Stub-Laeufer -------------------------------------------------
# name:schlaf:rc:zusagen:netz
STUBS=(
    "s1:4:0:10:0"
    "s2:3:0:8:0"
    "s3:2:0:7:net"       # liegt unter tools/net/    -> Netzsperre
    "s4:2:0:6:netmon"    # liegt unter tools/netmon/ -> Netzsperre
    "s5:1:1:5:0"     # faellt absichtlich durch
    "s6:1:0:5:0"
    "s7:0:0:4:0"
)

mkdir -p "$STUB/tools"
for e in "${STUBS[@]}"; do
    IFS=: read -r n sl rc zu netz <<< "$e"
    # WICHTIG: das Sperrmuster in test.sh ist ^tools/(net|netmon|netview|
    # tunnel)/ -- es haengt am VERZEICHNIS. Ein Stub unter tools/nets3/
    # matcht NICHT (nach "net" muss ein Schraegstrich kommen). Genau
    # darueber ist diese Pruefung beim ersten Lauf gestolpert; die
    # Netz-Stubs muessen wirklich unter tools/net/ und tools/netmon/
    # liegen, sonst prueft man nichts.
    d="$STUB/tools/$n"; [ "$netz" != 0 ] && d="$STUB/tools/$netz"
    mkdir -p "$d"
    cat > "$d/run.sh" <<STUBEOF
#!/usr/bin/env bash
echo "accel: tcg (Stub)"
echo "START \$(date +%s%N)"
sleep $sl
echo "ENDE \$(date +%s%N)"
echo "${n^^}: $zu passed, 0 failed"
exit $rc
STUBEOF
    chmod +x "$d/run.sh"
done

# --- ein test.sh-Verschnitt, der GENAU die Maschinerie von test.sh nimmt
# Herausgeschnitten wird der Block zwischen den beiden Markierungen, damit
# diese Pruefung nicht eine ZWEITE Kopie des Schedulers pruef, sondern die
# echte. Faellt das hier durch, ist test.sh kaputt, nicht diese Datei.
sed -n '/^JOBS=\${OSUM_JOBS/,/^}$/p' "$ROOT/test.sh" > "$STUB/maschinerie.sh"
# bis zum Ende von abschnitte_abarbeiten
python3 - "$ROOT/test.sh" "$STUB/maschinerie.sh" <<'PYEOF'
import re, sys
t = open(sys.argv[1], encoding='utf-8').read()
a = t.index('JOBS=${OSUM_JOBS')
e = t.index('echo "== 1. der festgenagelte Uebersetzer')
open(sys.argv[2], 'w', encoding='utf-8').write(t[a:e])
PYEOF

lauf_einen() { # jobs -> gibt Ausgabe auf stdout
    local jobs=$1
    (
        cd "$STUB"
        cat > lauf.sh <<'LEOF'
set -uo pipefail
ROOT=$(pwd)
WORK="${OSUM_WORK:-$ROOT/.test-work}"
mkdir -p "$WORK"
LEOF
        cat maschinerie.sh >> lauf.sh
        {
            for e in "${STUBS[@]}"; do
                IFS=: read -r n sl rc zu netz <<< "$e"
                d="tools/$n"; [ "$netz" != 0 ] && d="tools/$netz"
                echo "lauf \"$n. Stub $n\" $d/run.sh $n '^START|^ENDE'"
            done
            echo 'abschnitte_abarbeiten'
            echo 'echo "BILANZ PASS=$PASS FAIL=$FAIL ZUSAGEN=$ZUSAGEN"'
        } >> lauf.sh
        OSUM_JOBS=$jobs OSUM_WORK="$STUB/.w$jobs" bash lauf.sh
    )
}

echo "== Stub-Pruefung der Parallelmaschinerie =="
echo

s=$(date +%s%N); A=$(lauf_einen 1); e=$(date +%s%N); MS1=$(( (e-s)/1000000 ))
s=$(date +%s%N); B=$(lauf_einen 4); e=$(date +%s%N); MS4=$(( (e-s)/1000000 ))

FEHLER=0
melde() { if [ "$1" = ok ]; then echo "  OK    $2"; else echo "  FAIL  $2"; FEHLER=$((FEHLER+1)); fi; }

# 1. schneller
echo "  seriell (OSUM_JOBS=1): $MS1 ms"
echo "  parallel (OSUM_JOBS=4): $MS4 ms"
[ "$MS4" -lt "$MS1" ] && melde ok "parallel ist schneller als seriell" \
                      || melde no "parallel ist NICHT schneller ($MS4 >= $MS1)"

# 2. gleiche Bilanz
b1=$(printf '%s\n' "$A" | grep '^BILANZ')
b4=$(printf '%s\n' "$B" | grep '^BILANZ')
echo "  seriell:  $b1"
echo "  parallel: $b4"
[ "$b1" = "$b4" ] && melde ok "beide Wege liefern dieselbe Bilanz" \
                  || melde no "die Bilanzen weichen ab"
[ "$b1" = "BILANZ PASS=6 FAIL=1 ZUSAGEN=45" ] \
    && melde ok "und es ist die erwartete Bilanz (6/1/45)" \
    || melde no "die serielle Bilanz ist nicht 6/1/45: $b1"

# 3. Reihenfolge
o1=$(printf '%s\n' "$A" | grep -oE '^== s[0-9]' | tr -d '\n')
o4=$(printf '%s\n' "$B" | grep -oE '^== s[0-9]' | tr -d '\n')
[ "$o1" = "$o4" ] && melde ok "die Ausgabereihenfolge ist identisch" \
                  || melde no "die Reihenfolge weicht ab"

# 4. Netz-Abschnitte ueberschneiden sich nie
python3 - "$STUB/.w4" <<'PYEOF'
import sys, pathlib, re
w = pathlib.Path(sys.argv[1])
sp = {}
for n in ('s3', 's4'):
    t = (w / (n + '.log')).read_text()
    a = int(re.search(r'START (\d+)', t).group(1))
    e = int(re.search(r'ENDE (\d+)', t).group(1))
    sp[n] = (a, e)
(a1, e1), (a2, e2) = sp['s3'], sp['s4']
if e1 <= a2 or e2 <= a1:
    print("  OK    die zwei Netz-Abschnitte ueberschnitten sich nie "
          "(Zeitspur nachgerechnet)")
else:
    print("  FAIL  die zwei Netz-Abschnitte liefen GLEICHZEITIG")
    sys.exit(1)
PYEOF
[ $? -eq 0 ] || FEHLER=$((FEHLER+1))

# 5. der durchgefallene faellt in beiden durch
for x in "$A" "$B"; do
    printf '%s\n' "$x" | grep -q 'FEHLER  tools/s5/run.sh' || FEHLER=$((FEHLER+1))
done
[ "$FEHLER" -eq 0 ] && melde ok "der absichtlich rote Stub ist in beiden rot"

echo
if [ "$FEHLER" -eq 0 ]; then
    echo "SCHED: alles gruen"
    exit 0
fi
echo "SCHED: $FEHLER Pruefung(en) fehlgeschlagen"
exit 1
