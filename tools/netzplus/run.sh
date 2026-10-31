#!/usr/bin/env bash
#
#   bash tools/netzplus/run.sh
#
#     Fenster / Umlaufzeit
#
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
. tools/lib/qemu.sh

export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
LDSCRIPT=kernel/kernel.ld

TMPD=${NZP_ARB:-$(mktemp -d)}
mkdir -p "$TMPD"
export TMPD
[ -n "${NZP_ARB:-}" ] || trap 'rm -rf "$TMPD"' EXIT

. tools/netzplus/mess.sh

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

num() {
    local t=$1 v=$2 op=$3 w=$4
    if [ -z "$v" ]; then bad "$t: keine Zahl gefunden (erwartet $op $w)"; return; fi
    case "$op" in
        eq) [ "$v" -eq "$w" ] && ok "$t: $v" || bad "$t: $v, erwartet $w";;
        ge) [ "$v" -ge "$w" ] && ok "$t: $v" || bad "$t: $v, erwartet >= $w";;
        gt) [ "$v" -gt "$w" ] && ok "$t: $v" || bad "$t: $v, erwartet > $w";;
        le) [ "$v" -le "$w" ] && ok "$t: $v" || bad "$t: $v, erwartet <= $w";;
    esac
}

for t in qemu-system-x86_64 ip tc gcc nc python3 ethtool; do
    command -v "$t" >/dev/null || { echo "NETZPLUS: $t fehlt"; exit 1; }
done

# =====================================================================
echo "== 1. bauen: Kernel mit dem geflickten Stack =="
# =====================================================================
if nzp_build; then
    ok "firnc0: Kernel + Netzdienst gebaut ($(stat -c%s "$TMPD/k0.mb") Oktette)"
else
    bad "der Kernel laesst sich nicht bauen"
    echo "NETZPLUS: $pass passed, $fail failed"
    exit 1
fi

if grep -q "RUNDE NETZPLUS" vendor/firn/lib/net/tcp.fi 2>/dev/null; then
    ok "vendor/firn/lib/net/tcp.fi traegt die Aenderung dieser Runde"
else
    bad "der Flicken 0006 ist NICHT aufgelegt -- ./vendor/firn/fetch-firnc.sh"
fi
s1=""
while read -r want name; do
    case "$want" in \#*|"") continue;; esac
    roh="vendor/firn/lib/.roh/$name"
    [ -f "$roh" ] || roh="vendor/firn/lib/$name"
    got=$(git hash-object "$roh" 2>/dev/null)
    [ "$got" = "$want" ] || s1="$s1 $name;"
done < vendor/net/BLOBS
[ -z "$s1" ] && ok "vendor/net/BLOBS: der Stand unter den Flicken ist der des Pins" \
             || bad "BLOBS stimmt nicht mehr:$s1"

# =====================================================================
echo "== 2. die Aushandlung: was steht nach dem Handschlag im TCB? =="
# =====================================================================
durchsatz "$TMPD/a.txt" 1048576 "" "" "" ""
A="$TMPD/a.txt"
if [ -z "$(val "$A" octets)" ]; then
    bad "der erste Lauf lieferte keine Zahlen -- Draht oder Wirt, nicht der Stack"
    echo "     (Gegenprobe: bash tools/net/run.sh faellt dann genauso)"
    tail -3 "$A" 2>/dev/null | sed 's/^/     /'
    echo "NETZPLUS: $pass passed, $fail failed"
    exit 1
fi
num "Fensterskalierung ausgehandelt (ws_ok)" "$(val "$A" ws_ok)" eq 1
num "der Faktor der Gegenseite (Linux bietet 10)" "$(val "$A" snd_ws)" ge 1
num "unser eigener Faktor (rcv_ws)" "$(val "$A" rcv_ws)" eq 2
num "Zeitstempel ausgehandelt (ts_ok)" "$(val "$A" ts_ok)" eq 1
num "SACK ausgehandelt (sack_ok)" "$(val "$A" sack_ok)" eq 1
num "angekuendigtes Fenster groesser als das 16-Bit-Feld" "$(val "$A" rcv_wnd)" gt 65535
num "der Empfangspuffer ist wirklich 256 KiB" "$(val "$A" rcv_cap)" eq 262144
num "PAWS hat auf gesunder Strecke NICHTS verworfen" "$(val "$A" paws)" eq 0
num "jedes Oktett kam an" "$(val "$A" octets)" eq 1048576
num "Pruefsummenfehler" "$(val "$A" csum)" eq 0
KIB0=$(val "$A" kib_per_s)
ok "Durchsatz ohne Verzoegerung: $KIB0 KiB/s"

# =====================================================================
echo "== 3. die Gegenprobe: DERSELBE Kernel ohne Fensterskalierung =="
durchsatz "$TMPD/w0.txt" 1048576 50ms "" "" "nzws=0"
durchsatz "$TMPD/w1.txt" 1048576 50ms "" "" ""
W0="$TMPD/w0.txt"; W1="$TMPD/w1.txt"
num "ohne Skalierung: ws_ok ist 0" "$(val "$W0" ws_ok)" eq 0
num "ohne Skalierung: das Fenster passt ins 16-Bit-Feld" "$(val "$W0" rcv_wnd)" le 65535
num "ohne Skalierung kamen trotzdem alle Oktette an" "$(val "$W0" octets)" eq 1048576
num "mit Skalierung: ws_ok ist 1" "$(val "$W1" ws_ok)" eq 1
num "mit Skalierung kamen alle Oktette an" "$(val "$W1" octets)" eq 1048576
K0=$(val "$W0" kib_per_s); K1=$(val "$W1" kib_per_s)
if [ -n "$K0" ] && [ -n "$K1" ] && [ "$K0" -gt 0 ]; then
    ok "bei 100 ms Umlaufzeit: ohne Skalierung $K0 KiB/s, mit $K1 KiB/s"
    num "ohne Skalierung bleibt es unter dem Deckel Fenster/RTT (640 KiB/s)" "$K0" le 900
    num "mit Skalierung wird dieser Deckel ueberschritten" "$K1" gt 900
else
    bad "eine der beiden Messungen lieferte keine Zahl"
fi

# =====================================================================
echo "== 4. Durchsatz ueber eine Strecke mit Laufzeit =="
# =====================================================================
for d in 10ms 25ms; do
    durchsatz "$TMPD/d$d.txt" 1048576 "$d" "" "" ""
    D="$TMPD/d$d.txt"
    num "bei $d Verzoegerung kamen alle Oktette an" "$(val "$D" octets)" eq 1048576
    ok "  Durchsatz bei $d (Umlauf ~$(( ${d%ms} * 2 )) ms): $(val "$D" kib_per_s) KiB/s"
done

# =====================================================================
echo "== 5. Verlust: SACK und die Wiederholung =="
durchsatz "$TMPD/l5.txt" 262144 5ms "5%" "" ""
L="$TMPD/l5.txt"
num "durch 5 % Verlust: jedes Oktett, in Ordnung" "$(val "$L" octets)" eq 262144
num "Segmente ausser der Reihe" "$(val "$L" ooo)" ge 1
num "SACK-Bloecke, die Osum GESENDET hat" "$(val "$L" sack_tx)" ge 1
ok "  Durchsatz bei 5 % Verlust: $(val "$L" kib_per_s) KiB/s (sauber: $KIB0 KiB/s)"
num "PAWS hat auch hier nichts faelschlich verworfen" "$(val "$L" paws)" eq 0

durchsatz "$TMPD/l1.txt" 262144 5ms "1%" "" ""
L1="$TMPD/l1.txt"
num "durch 1 % Verlust: jedes Oktett" "$(val "$L1" octets)" eq 262144
ok "  Durchsatz bei 1 % Verlust: $(val "$L1" kib_per_s) KiB/s"

# =====================================================================
echo "== 6. die Optionen einzeln abschalten =="
durchsatz "$TMPD/t0.txt" 262144 "" "" "" "nzts=0"
T0="$TMPD/t0.txt"
num "ohne Zeitstempel: ts_ok ist 0" "$(val "$T0" ts_ok)" eq 0
num "ohne Zeitstempel kamen alle Oktette an" "$(val "$T0" octets)" eq 262144
num "ohne Zeitstempel verwirft PAWS nichts (es ist aus)" "$(val "$T0" paws)" eq 0

durchsatz "$TMPD/s0.txt" 262144 "" "" "" "nzsack=0"
S0="$TMPD/s0.txt"
num "ohne SACK: sack_ok ist 0" "$(val "$S0" sack_ok)" eq 0
num "ohne SACK kamen alle Oktette an" "$(val "$S0" octets)" eq 262144
num "ohne SACK wurde auch kein Block gesendet" "$(val "$S0" sack_tx)" eq 0

echo
echo "NETZPLUS: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
