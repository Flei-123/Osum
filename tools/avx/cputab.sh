#!/usr/bin/env bash
#
#   bash tools/avx/cputab.sh <OUT-Verzeichnis eines ota/run.sh-Laufes>
#
# VORHER und NACHHER entstehen so:
#
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

OUT=${1:?"Aufruf: cputab.sh <OUT eines ota/run.sh-Laufes>"}
[ -d "$OUT" ] || { echo "$OUT gibt es nicht"; exit 1; }
[ -f "$OUT/basis.img" ] || {
    echo "$OUT/basis.img fehlt -- erst tools/ota/run.sh laufen lassen"; exit 1; }
[ -f "$OUT/certs/srv.pem" ] || { echo "$OUT/certs fehlt"; exit 1; }
[ -d "$OUT/netz2" ] || { echo "$OUT/netz2 fehlt"; exit 1; }
[ -f tools/ota/server.py ] || {
    echo "tools/ota/ fehlt -- dieses Skript braucht den Zweig 'ota'"; exit 1; }

PORT=${OTA_PORT:-$(grep -hao '10\.0\.2\.2:[0-9]*' "$OUT"/*.txt 2>/dev/null \
     | head -1 | cut -d: -f2)}
[ -n "${PORT:-}" ] || { echo "Port nicht gefunden -- \$OTA_PORT setzen"; exit 1; }
NETZ=${OTA_NETZ:-"nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0"}

SRVPID=""
dienst_aus() {
    if [ -n "$SRVPID" ]; then kill "$SRVPID" 2>/dev/null; wait "$SRVPID" 2>/dev/null; fi
    SRVPID=""
}
trap dienst_aus EXIT
dienst() {
    dienst_aus
    : > "$OUT/cputab-srv.log"
    python3 tools/ota/server.py --wurzel "$OUT/netz2" --port "$PORT" \
        --cert "$OUT/certs/srv.pem" --key "$OUT/certs/srv.key" \
        --log "$OUT/cputab-srv.log" > "$OUT/cputab-srv.out" 2>&1 &
    SRVPID=$!
    local i
    for i in $(seq 1 40); do
        grep -qa "^START" "$OUT/cputab-srv.log" 2>/dev/null && return 0
        sleep 0.2
    done
    return 1
}

MODELLE=${OSUM_CPUS:-"qemu64 Nehalem Westmere SandyBridge Haswell Skylake-Server max"}

echo "cputab: OUT=$OUT  Port=$PORT  Netz=$NETZ"
printf '\n%-16s %-4s %-5s %-6s %-6s %s\n' \
    "-cpu" "rc" "mode" "xcr0" "size" "Ergebnis"
printf '%s\n' "--------------------------------------------------------------------------------"

start() { # <name> <skript>
    cp -f "$OUT/basis.img" "$OUT/ziel.img"
    dienst || { echo "Gegenstelle startet nicht"; exit 1; }
    OSUM_CPU="$M" OTA_NETZ="$NETZ" OUT="$OUT" \
        bash tools/install/oneshot.sh "$1" platte "$2" 600 > /dev/null 2>&1
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' "$OUT/$1.txt" 2>/dev/null
    dienst_aus
}

for M in $MODELLE; do
    start "cputab-$M-suchen" "ota show;ota search;exit"
    RC=$(cat "$OUT/cputab-$M-suchen.rc" 2>/dev/null)
    L="$OUT/cputab-$M-suchen.txt"
    MODE=$(grep -ao 'fpu: mode=[0-9]*' "$L" | head -1 | cut -d= -f2)
    XCR0=$(grep -ao 'xcr0=0x[0-9a-f]*' "$L" | head -1 | cut -d= -f2)
    SIZE=$(grep -ao 'fpu: mode=.*' "$L" | head -1 \
           | grep -ao 'size=[0-9]*' | head -1 | cut -d= -f2)
    if grep -qa "vector=6" "$L"; then
        ERG="#UD (vector=6) -- /bin/fetch tot"
    elif grep -qa "ota: NEW VERSION available" "$L" \
         && grep -qa "fetch: verify OK" "$L"; then
        start "cputab-$M-spielen" "ota apply;exit"
        S="$OUT/cputab-$M-spielen.txt"
        RC2=$(cat "$OUT/cputab-$M-spielen.rc" 2>/dev/null)
        if grep -qa "vector=6" "$S"; then
            ERG="suchen ok, EINSPIELEN #UD (vector=6)"
        elif grep -qa "ota: hash ok" "$S" \
             && grep -qa "opk: installed hallo" "$S"; then
            ERG="laeuft -- Kette geprueft, Streuwert stimmt, eingespielt (rc=$RC2)"
        else
            ERG="suchen ok, einspielen gescheitert -- siehe $S"
        fi
    else
        ERG="anders gescheitert -- siehe $L"
    fi
    printf '%-16s %-4s %-5s %-6s %-6s %s\n' \
        "$M" "${RC:-?}" "${MODE:--}" "${XCR0:--}" "${SIZE:--}" "$ERG"
done
printf '\nProtokolle: %s/cputab-*.txt\n' "$OUT"
