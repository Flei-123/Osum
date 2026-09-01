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
# Je Prozessormodell ZWEI Startvorgaenge: `ota suchen` (TLS 1.3,
# Kettenpruefung, Ed25519 ueber das VERZEICHNIS) und, wenn der
# durchkam, `ota einspielen` -- das Paket ueber die Leitung holen,
# seine SHA-256 gegen das signierte VERZEICHNIS halten und
# einspielen. Der zweite ist der Beweis: eine Pruefsumme, die
# stimmt, und nicht nur ein Handschlag, der zustande kam.
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

# DERSELBE PORT WIE IM LAEUFER, und er laesst sich nicht ausrechnen:
# `tools/ota/run.sh` nimmt `18000 + ($$ % 900)`, also seine eigene
# Prozessnummer. Die Zahl steht dafuer in `/etc/ota.conf` IM ABBILD, und
# von dort schreibt sie das Geraet in jede Zeile `ota: quelle
# https://10.0.2.2:<port>`. Also wird sie aus den Protokollen des Laufes
# GELESEN und nicht geraten -- ein anderer Port hiesse, dass das Geraet
# ins Leere greift, und der Lauf saehe aus wie ein Fehler dieser Runde.
PORT=${OTA_PORT:-$(grep -hao '10\.0\.2\.2:[0-9]*' "$OUT"/*.txt 2>/dev/null \
     | head -1 | cut -d: -f2)}
[ -n "${PORT:-}" ] || { echo "Port nicht gefunden -- \$OTA_PORT setzen"; exit 1; }
# DIE KERNWOERTER FUER DIE NETZKARTE, woertlich die aus
# `tools/ota/run.sh`. `$OTA_NETZ` traegt KEINEN Netzwerknamen, sondern
# die Zeile, die der Kern braucht, um die e1000 an QEMUs Benutzernetz zu
# haengen -- `oneshot.sh` schreibt sie in die `limine.conf` auf der
# Platte UND macht daraus die `-netdev`-Argumente. Steht hier etwas
# anderes, hat das Geraet keine Adresse und `fetch` meldet
# `no connection`.
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

# EIN Startvorgang mit einem Skript, Ergebnis im Protokoll.
start() { # <name> <skript>
    cp -f "$OUT/basis.img" "$OUT/ziel.img"
    dienst || { echo "Gegenstelle startet nicht"; exit 1; }
    OSUM_CPU="$M" OTA_NETZ="$NETZ" OUT="$OUT" \
        bash tools/install/oneshot.sh "$1" platte "$2" 600 > /dev/null 2>&1
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' "$OUT/$1.txt" 2>/dev/null
    dienst_aus
}

for M in $MODELLE; do
    # 1. SUCHEN: TLS 1.3, Kette geprueft, VERZEICHNIS mit Ed25519.
    start "cputab-$M-suchen" "ota zeigen;ota suchen;exit"
    RC=$(cat "$OUT/cputab-$M-suchen.rc" 2>/dev/null)
    L="$OUT/cputab-$M-suchen.txt"
    MODE=$(grep -ao 'fpu: mode=[0-9]*' "$L" | head -1 | cut -d= -f2)
    XCR0=$(grep -ao 'xcr0=0x[0-9a-f]*' "$L" | head -1 | cut -d= -f2)
    SIZE=$(grep -ao 'fpu: mode=.*' "$L" | head -1 \
           | grep -ao 'size=[0-9]*' | head -1 | cut -d= -f2)
    if grep -qa "vector=6" "$L"; then
        ERG="#UD (vector=6) -- /bin/fetch tot"
    elif grep -qa "ota: NEUE FASSUNG verfuegbar" "$L" \
         && grep -qa "fetch: verify OK" "$L"; then
        # 2. EINSPIELEN: das Paket holen, die SHA-256 gegen das
        #    signierte VERZEICHNIS halten und einspielen. DAS ist der
        #    Beweis, den die Runde verlangt -- nicht der Handschlag
        #    allein, sondern die Pruefsumme der geladenen Oktette.
        start "cputab-$M-spielen" "ota einspielen;exit"
        S="$OUT/cputab-$M-spielen.txt"
        RC2=$(cat "$OUT/cputab-$M-spielen.rc" 2>/dev/null)
        if grep -qa "vector=6" "$S"; then
            ERG="suchen ok, EINSPIELEN #UD (vector=6)"
        elif grep -qa "ota: streuwert stimmt" "$S" \
             && grep -qa "opk: installiert hallo" "$S"; then
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
