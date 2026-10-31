#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/../lib/marke-env.sh"
#
# DIE ABSCHNITTE:
#
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
. tools/lib/qemu.sh

export OSUM_CPU=${OSUM_CPU:-Haswell}
OUT=${OUT:-/tmp/ota-run}
mkdir -p "$OUT" .probe
export OUT
PORT=${OTA_PORT:-$(( 18000 + ($$ % 900) ))}
NETZ="nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0"
KURZ=${1:-}
RUNDEN=10
SCHUESSE=6
if [ "$KURZ" = "--kurz" ]; then RUNDEN=3; SCHUESSE=10; fi
if [ "$KURZ" = "--probe" ]; then RUNDEN=1; SCHUESSE=2; fi

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
gleich() { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', erwartet '$3'"; fi; }
hat() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hatnicht() { grep -qaF "$2" "$1" && bad "$3 -- '$2' steht da und sollte nicht" || ok "$3"; }
zahl() { local n=$1 v=$2 o=$3 w=$4
    if [ -z "${v:-}" ]; then bad "$n: keine Zahl (erwartet $o $w)"; return; fi
    if [ "$v" -"$o" "$w" ] 2>/dev/null; then ok "$n: $v"; else bad "$n: $v, erwartet $o $w"; fi
}

SRVPID=""
dienst_aus() {
    if [ -n "$SRVPID" ]; then kill "$SRVPID" 2>/dev/null; wait "$SRVPID" 2>/dev/null; fi
    SRVPID=""
}
dienst() { # <wurzel> [weitere Schalter...]
    dienst_aus
    local w=$1; shift
    python3 tools/ota/server.py --wurzel "$w" --port "$PORT" \
        --cert "$OUT/certs/srv.pem" --key "$OUT/certs/srv.key" \
        --log "$OUT/srv.log" "$@" > "$OUT/srv.out" 2>&1 &
    SRVPID=$!
    local i
    for i in $(seq 1 40); do
        grep -qa "^START" "$OUT/srv.log" 2>/dev/null && return 0
        sleep 0.2
    done
    return 1
}
aufraeumen() { dienst_aus; }
trap aufraeumen EXIT

lauf() { # name skript [limit]
    : > "$OUT/srv.log"
    OTA_NETZ="$NETZ" OUT="$OUT" bash tools/install/oneshot.sh \
        "$1" platte "$2" "${3:-600}" > /dev/null 2>&1
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' "$OUT/$1.txt" 2>/dev/null
    cat "$OUT/$1.rc" 2>/dev/null
}

for t in qemu-system-x86_64 python3 curl mcopy; do
    command -v "$t" >/dev/null 2>&1 || { echo "OTA: uebersprungen, $t fehlt"; exit 0; }
done
python3 -c 'import cryptography' 2>/dev/null || {
    echo "OTA: uebersprungen, python3-cryptography fehlt"; exit 0; }

# =====================================================================
echo
echo "== 5. (e) der Stromausfall: $SCHUESSE Schuesse mitten ins Einspielen =="
# =====================================================================
#
dienst "$OUT/netz2" || bad "Gegenstelle"
OUT="$OUT" bash tools/ota/zeitprobe.sh "$OUT/zeitmarken" > "$OUT/zeitprobe.log" 2>&1
dienst_aus
T_NETZ=0; T_LADEN=0; T_SCHREIB=0; T_FERTIG=0; T_ENDE=0
. "$OUT/zeitmarken" 2>/dev/null || true
zahl "(e) die Zeitprobe hat den ganzen Einspielvorgang gesehen" "$T_FERTIG" gt 0
echo "        gemessen: netz $T_NETZ ms, paket geprueft $T_LADEN ms, geschrieben $T_SCHREIB ms, bereit $T_FERTIG ms"
E_MAX=$(( T_ENDE + 1000 ))
[ "$E_MAX" -gt 2000 ] || E_MAX=27000
E_S0=$T_LADEN
[ "$E_S0" -gt 0 ] || E_S0=14000
E_S1=$T_SCHREIB
[ "$E_S1" -gt "$E_S0" ] || E_S1=$(( E_S0 + 9000 ))
E_S2=$(( T_ENDE + 3000 ))
[ "$E_S2" -gt "$E_S1" ] || E_S2=$(( E_S1 + 4000 ))
alt_n=0
neu_n=0
tot_n=0
i=0
while [ "$i" -lt "$SCHUESSE" ]; do
    i=$((i+1))
    dienst "$OUT/netz2" || bad "Gegenstelle"
    cp -f "$OUT/basis.img" "$OUT/ziel.img"
    if [ $(( i % 3 )) = 1 ]; then
        MS=$(( 500 + (i * (E_MAX - 500)) / SCHUESSE ))
    elif [ $(( i % 3 )) = 2 ]; then
        MS=$(( E_S0 + (i * (E_S1 - E_S0)) / SCHUESSE ))
    else
        MS=$(( E_S1 + (i * (E_S2 - E_S1)) / SCHUESSE ))
    fi
    OVMF=$(ls /usr/share/OVMF/OVMF_CODE.fd /usr/share/ovmf/OVMF.fd 2>/dev/null | head -1)
    cp -f /usr/share/OVMF/OVMF_VARS.fd "$OUT/e.vars.fd" 2>/dev/null || true
    {
        echo "timeout: 0"; echo "verbose: yes"; echo
        echo "/${MARKE_PRODUKT}"; echo "    protocol: multiboot1"
        echo "    path: boot():/osum.mb"
        echo "    cmdline: osum vfs nokbd nosched noproc nofs noring3 $NETZ script=ota apply;exit"
    } > "$OUT/e.conf"
    mcopy -o -i "$OUT/ziel.img@@1048576" "$OUT/e.conf" ::/limine.conf 2>/dev/null
    : > "$OUT/e$i.txt"
    $QEMU_X86 -machine pc -cpu "$OSUM_CPU" -m 512 -display none -no-reboot \
        -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF" \
        -drive "if=pflash,format=raw,unit=1,file=$OUT/e.vars.fd" \
        -serial "file:$OUT/e$i.txt" \
        -drive "file=$OUT/ziel.img,format=raw,if=ide,index=0" \
        -netdev user,id=otan0 -device e1000,netdev=otan0,mac=52:54:00:0a:0b:0c \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1 &
    QP=$!
    python3 -c "import time;time.sleep($MS/1000.0)"
    kill -9 "$QP" 2>/dev/null
    wait "$QP" 2>/dev/null
    dienst_aus
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' "$OUT/e$i.txt" 2>/dev/null
    rc=$(lauf "en$i" "opk rebuild;/apps/hallo.osp/start;opk list;exit" 400)
    if [ "$rc" != 21 ]; then
        tot_n=$((tot_n+1))
        bad "(e) Schuss $i bei ${MS} ms: die Maschine kommt NICHT mehr hoch (rc=$rc)"
    elif grep -qa "paket-hallo fassung 2" "$OUT/en$i.txt"; then
        neu_n=$((neu_n+1))
    elif grep -qa "paket-hallo fassung 1" "$OUT/en$i.txt"; then
        alt_n=$((alt_n+1))
    else
        tot_n=$((tot_n+1))
        bad "(e) Schuss $i bei ${MS} ms: WEDER die alte NOCH die neue Fassung laeuft"
    fi
done
zahl "(e) Schuesse, nach denen die Maschine ENTWEDER alt ODER neu ist" \
     "$((alt_n + neu_n))" eq "$SCHUESSE"
zahl "(e) davon: nichts dazwischen und kein Ziegelstein" "$tot_n" eq 0
zahl "(e) Schuesse, die WIRKLICH nach dem Umschalten lagen (sonst misst das nichts)" \
     "$neu_n" gt 0
zahl "(e) und Schuesse, die davor lagen" "$alt_n" gt 0
echo "        alt=$alt_n  neu=$neu_n  kaputt=$tot_n  (Schuesse zwischen 500 und $E_MAX ms, verdichtet auf $E_S0..$E_S1 ms und $E_S1..$E_S2 ms)"

echo "  $pass gruen, $fail rot"
[ "$fail" = 0 ] || exit 1
exit 0
