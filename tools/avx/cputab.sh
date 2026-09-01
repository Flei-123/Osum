#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/avx/cputab.sh -- DIE `-cpu`-TABELLE AUS `docs/OTA.md`, NACHGEFAHREN.
#
# Der Befund, der Runde AVX ausgeloest hat, steht in `docs/OTA.md`,
# Abschnitt "WAS NOCH FEHLT", Punkt 1: dasselbe Abbild, derselbe Kern,
# nur ein anderes `-cpu` -- und ab `max` stirbt `/bin/fetch` mit
# `user fault: vector=6` (#UD). Dieses Skript faehrt genau diese Messung:
# EIN Startvorgang je Prozessormodell, mit `ota zeigen;ota suchen`, also
# mit einem echten TLS-1.3-Handschlag gegen `tools/ota/server.py`, einer
# gepruefte Zertifikatskette und einer Ed25519-Signatur.
#
# ES BAUT NICHTS UND ES IST KEIN ZWEITER PRUEFSTAND. Es setzt auf den
# Artefakten eines Laufes von `tools/ota/run.sh` auf (dessen
# `$OUT`-Verzeichnis): das installierte Abbild `basis.img`, die
# Zertifikate unter `certs/` und die signierten Quellen unter `netz2/`.
#
#   bash tools/avx/cputab.sh <OUT-Verzeichnis eines ota/run.sh-Laufes>
#
# VORHER und NACHHER entstehen so:
#
#   # vorher -- der Zweig `ota` allein
#   cd /pfad/osum-ota      && bash tools/ota/start.sh /root/ota-vor  --kurz
#   cd /pfad/osum-ota      && bash tools/avx/cputab.sh /root/ota-vor
#   # nachher -- derselbe Zweig mit `avx` hineinverschmolzen
#   cd /pfad/osum-avx-ota  && bash tools/ota/start.sh /root/ota-nach --kurz
#   cd /pfad/osum-avx-ota  && bash tools/avx/cputab.sh /root/ota-nach
#
# BRAUCHT DEN ZWEIG `ota`: `tools/ota/`, `kernel/app/fetch.fi` und
# `kernel/user/ota.fi` liegen dort. Auf `avx` allein gibt es sie nicht;
# in einem Baum, in dem beide verschmolzen sind, laeuft es.
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

# DERSELBE PORT WIE IM LAEUFER. Er steht in `/etc/ota.conf` IM ABBILD,
# das der Lauf installiert hat -- ein anderer Port hiesse, dass das
# Geraet ins Leere greift. Die Rechnung ist woertlich die aus
# `tools/ota/run.sh`.
PORT=$(( 18000 + $(printf '%d' "0x$(printf '%s' "$ROOT" | md5sum | cut -c1-3)") % 1000 ))
NETZ=${OTA_NETZ:-avxnet}

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
printf '%s\n' "---------------------------------------------------------------------"

for M in $MODELLE; do
    cp -f "$OUT/basis.img" "$OUT/ziel.img"
    dienst || { echo "Gegenstelle startet nicht"; exit 1; }
    NAME="cputab-$M"
    OSUM_CPU="$M" OTA_NETZ="$NETZ" OUT="$OUT" \
        bash tools/install/oneshot.sh "$NAME" platte \
        "ota zeigen;ota suchen;exit" 600 > /dev/null 2>&1
    RC=$(cat "$OUT/$NAME.rc" 2>/dev/null)
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' "$OUT/$NAME.txt" 2>/dev/null
    L="$OUT/$NAME.txt"
    MODE=$(grep -ao 'fpu: mode=[0-9]*' "$L" | head -1 | cut -d= -f2)
    XCR0=$(grep -ao 'xcr0=0x[0-9a-f]*' "$L" | head -1 | cut -d= -f2)
    SIZE=$(grep -ao 'size=[0-9]*' "$L" | head -1 | cut -d= -f2)
    if grep -qa "vector=6" "$L"; then
        ERG="#UD (vector=6) -- /bin/fetch tot"
    elif grep -qa "ota: NEUE FASSUNG verfuegbar" "$L"; then
        if grep -qa "fetch: verify OK" "$L"; then
            ERG="laeuft -- Kette geprueft, Fassung 2 gefunden"
        else
            ERG="laeuft, aber OHNE Kettenpruefung"
        fi
    else
        ERG="anders gescheitert -- siehe $L"
    fi
    printf '%-16s %-4s %-5s %-6s %-6s %s\n' \
        "$M" "${RC:-?}" "${MODE:--}" "${XCR0:--}" "${SIZE:--}" "$ERG"
    dienst_aus
done
printf '\nProtokolle: %s/cputab-*.txt\n' "$OUT"
