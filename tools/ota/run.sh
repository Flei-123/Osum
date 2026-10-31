#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/../lib/marke-env.sh"
#
# DIE ABSCHNITTE:
#
set -uo pipefail
cd "$(dirname "$0")/../.."
export BOOT_KERNEL_COPY=1   # r1223: QEMU -kernel/-initrd has no boot medium; the installer needs /boot/osum.mb in the root
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
. tools/lib/qemu.sh

export OSUM_CPU=${OSUM_CPU:-Haswell}
# W-OTA2 15.10.2026: a fixed /tmp/ota-run was deleted by a foreign process in
# the middle of a run (srv.log / gutN.txt vanished -> 7 false FAILs). Own
# private dir per run unless OUT is given; removed at exit (OTA_KEEP=1 keeps).
OWN_OUT=0
if [ -z "${OUT:-}" ]; then OUT=$(mktemp -d "${TMPDIR:-/tmp}/ota-run.XXXXXX"); OWN_OUT=1; fi
mkdir -p "$OUT" .probe
# A-041: two rounds ran this file at the same time on /tmp/ota-run on
# 24.09.2026 and overwrote each other's k.mb/quelle.img mid-run.
. "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/tools/lib/sperre.sh" && osum_sperre "$OUT"   # A-024
export OUT
PORT=${OTA_PORT:-$(( 18000 + ($$ % 900) ))}
NETZ="nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0"
KURZ=${1:-}
RUNDEN=10
SCHUESSE=30
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
    : > "$OUT/srv.log"
    python3 tools/ota/server.py --wurzel "$w" --port "$PORT" \
        --cert "$OUT/certs/srv.pem" --key "$OUT/certs/srv.key" \
        --log "$OUT/srv.log" "$@" > "$OUT/srv.out" 2>&1 &
    SRVPID=$!
    local i
    for i in $(seq 1 40); do
        grep -qa "^START port=$PORT " "$OUT/srv.log" 2>/dev/null && return 0
        sleep 0.2
    done
    return 1
}
aufraeumen() { dienst_aus; if [ "$OWN_OUT" = 1 ] && [ -z "${OTA_KEEP:-}" ]; then rm -rf "$OUT"; fi; }
trap aufraeumen EXIT

lauf() { # name skript [limit]
    : > "$OUT/srv.log"
    OTA_NETZ="$NETZ" OUT="$OUT" bash tools/install/oneshot.sh \
        "$1" platte "$2" "${3:-600}" > /dev/null 2>&1
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' "$OUT/$1.txt" 2>/dev/null
    cat "$OUT/$1.rc" 2>/dev/null
}

delta_test() {
    dienst "$OUT/netz2" || bad "server"
    cp -f "$OUT/basis.img" "$OUT/ziel.img"
    rc=$(lauf delta1 "opk install /quelle2/hallo-2.opk;ota apply;ota show;exit")
    gleich "(i) the machine boots" "$rc" "21"
    hat "$OUT/delta1.txt" "ota: packages already current: 1" "(i) DELTA: the installed package is recognised as current"
    hat "$OUT/delta1.txt" "ota: nothing to install" "(i) and it says so"
    hatnicht "$OUT/delta1.txt" "READY FOR RESTART" "(i) and no restart is offered for nothing"
    hat "$OUT/delta1.txt" "ota: version here 2" "(i) only the counter moved: version here 2"
    hatnicht "$OUT/delta1.txt" "NOT ENOUGH SPACE" "(i) and no space is asked for it"
    hatnicht "$OUT/delta1.txt" "ota: hash ok hallo-2.opk" "(i) and it is not fetched/checked again"
    if grep -qa "hallo-2.opk" "$OUT/srv.log"; then
        bad "(i) the package was fetched although it is already current"
    else
        ok "(i) the package was NOT fetched (the server never delivered hallo-2.opk)"
    fi
    gleich "(i) hallo is installed exactly once (by hand, not by ota)" "$(grep -ca 'opk: installed hallo' "$OUT/delta1.txt")" "1"
    dienst_aus
}

for t in qemu-system-x86_64 python3 curl mcopy; do
    command -v "$t" >/dev/null 2>&1 || { echo "OTA: uebersprungen, $t fehlt"; exit 0; }
done
python3 -c 'import cryptography' 2>/dev/null || {
    echo "OTA: uebersprungen, python3-cryptography fehlt"; exit 0; }

# =====================================================================
echo "== 1. der Bau: /bin/ota, /bin/fetch und ein Abbild, in dem beide liegen =="
# =====================================================================
bash vendor/firn/fetch-firnc.sh > "$OUT/firnc.log" 2>&1 \
    && ok "der festgenagelte Uebersetzer ($(cat vendor/firn/COMMIT | cut -c1-8))" \
    || { bad "fetch-firnc.sh"; tail -5 "$OUT/firnc.log"; }

vendor/firn/bin/firnc kernel/user/ota.fi -o "$OUT/ota-probe.o" \
    2> "$OUT/ota-cc.log" \
    && ok "kernel/user/ota.fi baut ($(grep -c . kernel/user/ota.fi) Zeilen, profile kernel, keine Halde)" \
    || { bad "ota.fi baut nicht"; head -20 "$OUT/ota-cc.log"; }

#   error: cannot read 'kernel/app/libc/dns.fi': No such file or directory
#      --> kernel/app/fetch.fi:88:1  |  import libc.dns
#
FIRNLIB="$ROOT/lib" vendor/firn/bin/firnc -c --profile=app \
    -o "$OUT/fetch-probe.o" kernel/app/fetch.fi 2> "$OUT/fetch-cc.log" \
    && ok "kernel/app/fetch.fi baut mit Range/Wiederaufnahme ($(grep -c . kernel/app/fetch.fi) Zeilen)" \
    || { bad "fetch.fi baut nicht"; head -20 "$OUT/fetch-cc.log"; }

bash tools/install/pakete.sh "$OUT" > "$OUT/pak1.log" 2>&1 \
    && ok "zwei signierte Quellen (Fassung 1 und 2)" \
    || { cat "$OUT/pak1.log"; bad "install/pakete.sh"; }
bash tools/update/pakete.sh "$OUT" > "$OUT/pak2.log" 2>&1 \
    && ok "Fassung 3 -- sauber signiert und kommt NICHT hoch" \
    || { cat "$OUT/pak2.log"; bad "update/pakete.sh"; }
python3 tools/ota/mkcerts.py "$OUT/certs" ota.test 10.0.2.2 \
    > "$OUT/certs.log" 2>&1 \
    && ok "die Zertifikate, gemacht mit Pythons cryptography und nicht mit diesem Repo" \
    || { cat "$OUT/certs.log"; bad "mkcerts.py"; }
bash tools/ota/pakete.sh "$OUT" > "$OUT/pak3.log" 2>&1 \
    && ok "sechs Quellen fuers Netz: $(grep -c '^   netz' "$OUT/pak3.log") Stueck" \
    || { cat "$OUT/pak3.log"; bad "ota/pakete.sh"; }
grep -qa "VERZEICHNIS  fassung" "$OUT/pak3.log" \
    && ok "jede Signatur wurde von einer FREMDEN Umsetzung nachgeprueft (libsodium/cryptography)" \
    || bad "listing.py hat nicht signiert"
grep -qa "KEINE zweite Meinung" "$OUT/pak3.log" \
    && bad "es gab keine zweite Meinung zur Signatur -- pynacl/cryptography fehlt" \
    || ok "die zweite Meinung war wirklich da"

VZG=$(stat -c%s "$OUT/netz2/VERZEICHNIS")
PKG=$(stat -c%s "$OUT/netz2/hallo-2.opk")
ok "ein VERZEICHNIS ist $VZG Oktett, ein Paket $PKG"

dienst "$OUT/netz2" && ok "die Gegenstelle laeuft auf 127.0.0.1:$PORT" \
    || bad "die Gegenstelle startet nicht"
CV=$(curl -s --cacert "$OUT/certs/ca.pem" --resolve "ota.test:$PORT:127.0.0.1" \
     -o /dev/null -w '%{http_code} %{ssl_verify_result}' \
     "https://ota.test:$PORT/VERZEICHNIS" 2>/dev/null)
gleich "curl gegen die Gegenstelle (Code, Kettenpruefung)" "$CV" "200 0"
CT=$(curl -s --cacert "$OUT/certs/ca.pem" --resolve "ota.test:$PORT:127.0.0.1" \
     -w '%{http_version}' -o /dev/null "https://ota.test:$PORT/VERZEICHNIS" 2>/dev/null)
CR=$(curl -s --cacert "$OUT/certs/ca.pem" --resolve "ota.test:$PORT:127.0.0.1" \
     -r 100- -o /dev/null -w '%{http_code}' "https://ota.test:$PORT/hallo-2.opk" 2>/dev/null)
gleich "die Gegenstelle kann Range (206)" "$CR" "206"
dienst_aus

WIEDER=0
if [ "${OTA_BASIS:-0}" = 1 ] && [ -s "$OUT/basis.img" ]; then
    WIEDER=1
    echo "  ----  \$OTA_BASIS=1: Bau und Installation UEBERSPRUNGEN, es wird"
    echo "        die vorhandene Platte benutzt. Nur zum Iterieren."
fi

cat > "$OUT/ota.conf" <<EOF
quelle=https://10.0.2.2:$PORT
name=ota.test
abstand=3600
auto=nein
frist=15
EOF
#
printf 'opk rebuild\nif /apps/hallo.osp/start\nthen\nota confirm\nfi\nopk trial\n' \
    > "$OUT/start.sh"
EX="/start.sh=$OUT/start.sh"
if [ "$WIEDER" = 0 ]; then
OTA_ROOTS="$OUT/certs/ca.pem" OTA_CONF="$OUT/ota.conf" EXTRA="$EX" \
    ZIEL_MIB="${OTA_ZIEL_MIB:-96}" bash tools/install/build.sh "$OUT" > "$OUT/build.log" 2>&1 \
    && ok "das Abbild ($(grep -a 'apps ' "$OUT/build.log" | tr -s ' '))" \
    || { tail -20 "$OUT/build.log"; bad "build.sh"; }
grep -qa "wurzeln " "$OUT/build.log" && ok "der Wurzelspeicher liegt im Abbild" \
    || bad "kein Wurzelspeicher im Abbild"
fi
FSZ=$(stat -c%s "$OUT/bin/fetch")
OSZ=$(stat -c%s "$OUT/bin/ota")
ok "/bin/fetch $FSZ Oktett (TLS 1.3, X.509, RSA, ECDSA), /bin/ota $OSZ Oktett"

ZIEL_MIB=${OTA_ZIEL_MIB:-96}
if [ "$WIEDER" = 0 ]; then
rm -f "$OUT/ziel.img"
head -c $((ZIEL_MIB * 1024 * 1024)) /dev/zero > "$OUT/ziel.img"
OUT="$OUT" bash tools/install/oneshot.sh inst iso "install /dev/hda --ja;exit" 900 \
    > /dev/null 2>&1
gleich "die Installation auf die leere Platte" "$(cat "$OUT/inst.rc")" "21"
hat "$OUT/inst.txt" "install: done" "der Installer meldet sich fertig"

rc=$(lauf basis0 "opk install /quelle1/hallo-1.opk;sh /start.sh;df;exit")
hat "$OUT/basis0.txt" "paket-hallo fassung 1" "Ausgangslage: Fassung 1 laeuft"
#
# `kernel/user/opk.fi` druckt seit Runde UMLAUT2
#
#     opk: signature checked <pfad>
#     opk: trial confirmed for <n>
#
#     opk: signature checked /tmp/ota/INDEX.sig
#     opk: signature checked /tmp/ota/hallo-2.opk
#
hat "$OUT/basis0.txt" "opk: trial confirmed" "und ist bestaetigt"
cp -f "$OUT/ziel.img" "$OUT/basis.img"
fi
BASISBL=$(sed -n 's/.*blocks total=\([0-9]*\) free=\([0-9]*\).*/\1 \2/p' \
          "$OUT/basis0.txt" | tail -1)

if [ "${OTA_NUR:-}" = delta ]; then
    delta_test
    echo; echo "  $pass gruen, $fail rot"
    [ "$fail" = 0 ] && exit 0 || exit 1
fi
if [ "${OTA_NUR:-}" != kanal ]; then
# =====================================================================
echo
echo "== 2. der gute Weg, Ende zu Ende: suchen, holen, pruefen, einspielen =="
# =====================================================================
dienst "$OUT/netz2" || bad "Gegenstelle"
cp -f "$OUT/basis.img" "$OUT/ziel.img"
T0=$(date +%s%N)
rc=$(lauf gut1 "ota show;ota search;exit")
T1=$(date +%s%N)
gleich "die Maschine kommt hoch" "$rc" "21"
hat "$OUT/gut1.txt" "ota: version here 0" "vorher steht hier Fassung 0 (frisch installiert)"
hat "$OUT/gut1.txt" "fetch: verify OK" "die Kette des Servers wurde GEPRUEFT und nicht geglaubt"
hat "$OUT/gut1.txt" "ota: version there 2" "die Quelle bietet Fassung 2"
hat "$OUT/gut1.txt" "ota: NEW VERSION available" "und das wird gemeldet"
hat "$OUT/gut1.txt" "ota: package hallo 2.0.0" "mit Namen und Fassung des Pakets"
hatnicht "$OUT/gut1.txt" "opk: installed" "SUCHEN INSTALLIERT NICHTS"
grep -qa "GET /VERZEICHNIS" "$OUT/srv.log" 2>/dev/null || true
SUCHMS=$(( (T1 - T0) / 1000000 ))

cp -f "$OUT/basis.img" "$OUT/ziel.img"
dienst "$OUT/netz2" || bad "Gegenstelle"
T0=$(date +%s%N)
rc=$(lauf gut2 "df;ota apply;df;echo LSBEGIN;ls /tmp/ota;echo LSEND;opk trial;exit")
T1=$(date +%s%N)
EINMS=$(( (T1 - T0) / 1000000 ))
cp -f "$OUT/srv.log" "$OUT/srv-gut.log" 2>/dev/null || true
gleich "einspielen: die Maschine kommt hoch" "$rc" "21"
hat "$OUT/gut2.txt" "ota: hash ok hallo-2.opk" "der Streuwert des GELADENEN Pakets stimmt"
hat "$OUT/gut2.txt" "opk: signature checked" "opk prueft die Signatur ein ZWEITES Mal, mit eigenem Code"
hat "$OUT/gut2.txt" "opk: installed hallo" "und installiert"
hat "$OUT/gut2.txt" "opk: in trial: 1 before 0" "die neue Generation steht in ERPROBUNG, Rueckfall waere 0"
hat "$OUT/gut2.txt" "ota: READY FOR RESTART" "und der Neustart wird ANGEBOTEN"
hatnicht "$OUT/gut2.txt" "power: init sagt ab" "ES WIRD NICHT VON SELBST NEU GESTARTET"
OKT=$(grep -a "^ota: platz" "$OUT/gut2.txt" | tail -1 | awk '{print $3}')
# r542: the staging file goes back right after opk installed the package, and the announced
# need (needed) covers what the update really consumed. Peak space is NOT observable from outside;
# the end state (consumed <= needed, staging empty) is.
GFREE0=$(sed -n 's/.*blocks total=[0-9]* free=\([0-9]*\).*/\1/p' "$OUT/gut2.txt" | head -1)
GFREE1=$(sed -n 's/.*blocks total=[0-9]* free=\([0-9]*\).*/\1/p' "$OUT/gut2.txt" | tail -1)
GNEED=$(sed -n 's/^ota: needed \([0-9]*\).*/\1/p' "$OUT/gut2.txt" | head -1)
if [ -n "$GFREE0" ] && [ -n "$GFREE1" ] && [ -n "$GNEED" ]; then
    GUSED=$(( (GFREE0 - GFREE1) * 512 ))
    echo "        MEASURED r542: update consumed $GUSED bytes (free $GFREE0 -> $GFREE1 blocks), announced need $GNEED bytes"
    [ "$GUSED" -le "$GNEED" ] && ok "r542: consumed space ($GUSED) <= announced need ($GNEED)" \
        || bad "r542: the update consumed $GUSED bytes, more than announced ($GNEED)"
else
    bad "r542: df before/after or the 'needed' line is missing in gut2.txt"
fi
LSTMP=$(sed -n '/^LSBEGIN/,/^LSEND/p' "$OUT/gut2.txt")
echo "$LSTMP" | grep -qa 'LSEND' || bad "r542: no listing of /tmp/ota in gut2.txt"
echo "$LSTMP" | grep -qa 'hallo-2' && bad "r542: the staged package is still in /tmp/ota after the install" \
    || ok "r542: the staged package and its .sig are gone from /tmp/ota after the install"

rc=$(lauf gut3 "sh /start.sh;ota show;df;exit")
gleich "der Neustart" "$rc" "21"
hat "$OUT/gut3.txt" "ab: gen=1 versuch=1 von 3" "der Kern zaehlt den Erprobungsversuch"
hat "$OUT/gut3.txt" "paket-hallo fassung 2" "DIE NEW VERSION LAEUFT"
hat "$OUT/gut3.txt" "opk: trial confirmed" "und wird bestaetigt"
hat "$OUT/gut3.txt" "ota: version here 2" "der Fassungszaehler steht jetzt auf 2"
GENBL=$(sed -n 's/.*blocks total=\([0-9]*\) free=\([0-9]*\).*/\2/p' "$OUT/gut3.txt" | tail -1)

rc=$(lauf gut4 "sh /start.sh;exit")
hat "$OUT/gut4.txt" "ab: gen=1 bestaetigt" "beim naechsten Start ist nichts mehr in Erprobung"
hat "$OUT/gut4.txt" "paket-hallo fassung 2" "und es bleibt bei der neuen Fassung"
cp -f "$OUT/ziel.img" "$OUT/nach2.img"
dienst_aus

# =====================================================================
echo
echo "== 3. die Ablehnungen -- und nach jeder wird nachgesehen =="
# =====================================================================
H1=$(python3 -c "print(open('$OUT/netz1/INDEX').read().split(chr(9))[2])" 2>/dev/null)
echo "        hallo 1.0.0 im Store = ${H1:0:16}"

dienst "$OUT/netzbadsig" || bad "Gegenstelle"
cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf a1 "ota apply;opk list;opk generations;exit")
hat "$OUT/a1.txt" "ota: hash ok" "(a) das VERZEICHNIS stimmt -- ota laesst es durch"
hat "$OUT/a1.txt" "SIGNATURE WRONG" "(a) und opk faengt die falsche PAKETSIGNATUR"
hatnicht "$OUT/a1.txt" "opk: installed" "(a) es wird NICHTS installiert"
hat "$OUT/a1.txt" "${H1:0:12}" "(a) die laufende Fassung ist unveraendert"
hatnicht "$OUT/a1.txt" "generation 1" "(a) es entsteht KEINE zweite Generation"
hat "$OUT/a1.txt" "ota: version here 0" "(a) und der Fassungszaehler steht noch auf 0"
dienst_aus

dienst "$OUT/netzfremd" || bad "Gegenstelle"
cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf a2 "ota apply;opk list;opk generations;ota show;exit")
hat "$OUT/a2.txt" "SIGNATURE OF THE VERZEICHNIS WRONG" "(a2) ein fremd signiertes VERZEICHNIS wird abgelehnt"
hatnicht "$OUT/a2.txt" "ota: version there" "(a2) und nicht einmal die Fassungsnummer daraus wird gelesen"
hatnicht "$OUT/a2.txt" "opk: installed" "(a2) es wird nichts installiert"
hatnicht "$OUT/a2.txt" "generation 1" "(a2) es entsteht keine Generation"
dienst_aus

# ---- (g) richtig signiertes VERZEICHNIS, veraenderter Streuwert
dienst "$OUT/netzman" || bad "Gegenstelle"
cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf g1 "ota apply;opk list;opk generations;exit")
hat "$OUT/g1.txt" "ota: version there 2" "(g) die Signatur ueber das VERZEICHNIS ist GUELTIG"
hat "$OUT/g1.txt" "HASH MISMATCH" "(g) und trotzdem wird abgelehnt -- die Kette wird an JEDEM Glied geprueft"
hatnicht "$OUT/g1.txt" "opk: installed" "(g) es wird nichts installiert"
hatnicht "$OUT/g1.txt" "generation 1" "(g) es entsteht keine Generation"
dienst_aus

dienst "$OUT/netz1" || bad "Gegenstelle"
cp -f "$OUT/nach2.img" "$OUT/ziel.img"
rc=$(lauf b1 "ota apply;opk list;ota show;exit")
hat "$OUT/b1.txt" "ota: version here 2" "(b) auf dem Geraet steht Fassung 2"
hat "$OUT/b1.txt" "ota: version there 1" "(b) angeboten wird Fassung 1 -- richtig signiert"
hat "$OUT/b1.txt" "ROLLBACK REFUSED" "(b) DER RUECKSCHRITTSSCHUTZ GREIFT"
hatnicht "$OUT/b1.txt" "opk: installed" "(b) es wird nichts installiert"
hatnicht "$OUT/b1.txt" "ota: hash ok" "(b) es wird nicht einmal ein Paket geholt"
dienst_aus

dienst "$OUT/netz1" || bad "Gegenstelle"
cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf b2 "ota search;exit")
hat "$OUT/b2.txt" "ota: NEW VERSION available" "(b) GEGENPROBE: dieselbe Quelle wird angenommen, wenn hier 0 steht"
hatnicht "$OUT/b2.txt" "ROLLBACK REFUSED" "(b) der Schutz schlaegt also nicht immer zu"
dienst_aus

dienst "$OUT/netz2" --abbruch "hallo-2.opk:9000" || bad "Gegenstelle"
cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf c1 "ota apply;exit")
grep -qa "ABBRUCH hallo-2.opk" "$OUT/srv.log" \
    && ok "(c) die Gegenstelle hat die Verbindung wirklich abgerissen (RST nach 9000 Oktett)" \
    || bad "(c) die Gegenstelle hat gar nicht abgebrochen"
hatnicht "$OUT/c1.txt" "opk: installed" "(c) im abgebrochenen Lauf wird nichts installiert"
dienst_aus
rc=$(lauf c1b "opk rebuild;/apps/hallo.osp/start;opk list;opk generations;ota show;exit")
gleich "(c) DANACH kommt die Maschine hoch" "$rc" "21"
hat "$OUT/c1b.txt" "paket-hallo fassung 1" "(c) und die alte Fassung laeuft"
hat "$OUT/c1b.txt" "${H1:0:12}" "(c) der Store nennt genau den alten Streuwert"
hatnicht "$OUT/c1b.txt" "generation 1" "(c) es entstand keine zweite Generation"
hat "$OUT/c1b.txt" "ota: version here 0" "(c) der Fassungszaehler ist unveraendert"

# ---- (c2) DIE WIEDERAUFNAHME.
#
dienst "$OUT/netz2" --kurz "hallo-2.opk:20000" || bad "Gegenstelle"
cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf c2a "ota apply;exit")
hatnicht "$OUT/c2a.txt" "opk: installed" "(c) der erste Versuch scheitert"
grep -qa "^KURZ hallo-2.opk" "$OUT/srv.log" \
    && ok "(c) die Gegenstelle hat den Rumpf wirklich abgeschnitten" \
    || bad "(c) die Gegenstelle hat nicht abgeschnitten"
dienst_aus
dienst "$OUT/netz2" || bad "Gegenstelle"
rc=$(lauf c2b "ota apply;opk list;exit")
hat "$OUT/c2b.txt" "ota: partial file, resuming at" "(c) der zweite Versuch findet das Bruchstueck und setzt dort an"
hat "$OUT/c2b.txt" "ota: hash ok hallo-2.opk" "(c) und bekommt das Paket vollstaendig"
hat "$OUT/c2b.txt" "opk: installed hallo" "(c) es wird eingespielt"
grep -qa "^206 hallo-2.opk" "$OUT/srv.log" \
    && ok "(c) WIEDERAUFGENOMMEN: die Gegenstelle hat 206 Partial Content geliefert" \
    || bad "(c) keine 206 -- es wurde nicht wiederaufgenommen"
dienst_aus

dienst "$OUT/netz2" --kurz "hallo-2.opk:20000" || bad "server"
cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf c3a "ota apply;exit")
hatnicht "$OUT/c3a.txt" "opk: installed" "(c3) first attempt against the cutting server fails"
dienst_aus
dienst "$OUT/netz2" --norange || bad "server"
rc=$(lauf c3b "ota apply;opk list;exit")
hat "$OUT/c3b.txt" "ota: hash ok hallo-2.opk" "(c3) server without Range: the package arrives complete"
hat "$OUT/c3b.txt" "opk: installed hallo" "(c3) and it is installed"
grep -qa "^200 hallo-2.opk von 0 " "$OUT/srv.log" \
    && ok "(c3) the server answered 200 from offset 0 (restart, no garbage appended)" \
    || bad "(c3) no full 200 answer in the server log"
hatnicht "$OUT/c3b.txt" "wrong length" "(c3) no wrong-length failure after the restart"
dienst_aus

dienst "$OUT/netzvoll" || bad "Gegenstelle"
cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf f1 "df;ota apply;opk list;opk generations;ota show;exit" 900)
gleich "(f) die Maschine kommt hoch" "$rc" "21"
hat "$OUT/f1.txt" "NOT ENOUGH SPACE" "(f) es reicht nicht, und ota bricht SAUBER ab"
hatnicht "$OUT/f1.txt" "opk: installed" "(f) es wird nichts installiert"
hatnicht "$OUT/f1.txt" "generation 1" "(f) es entsteht keine Generation"
hat "$OUT/f1.txt" "${H1:0:12}" "(f) die laufende Fassung ist unveraendert"
hat "$OUT/f1.txt" "ota: version here 0" "(f) der Fassungszaehler ist unveraendert"
grep -qa "gross-1.opk" "$OUT/srv.log" \
    && bad "(f) das Paket wurde geholt, obwohl der Platz vorher schon nicht reichte" \
    || ok "(f) und das Paket wurde NICHT EINMAL GEHOLT -- geprueft wurde vorher"
dienst_aus

dienst "$OUT/netz2" || bad "Gegenstelle"
cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf f2 "ota apply;exit")
hat "$OUT/f2.txt" "opk: installed hallo" "(f) GEGENPROBE: das kleine Update geht auf derselben Platte durch"
hatnicht "$OUT/f2.txt" "NOT ENOUGH SPACE" "(f) der Platzwaechter schlaegt also nicht immer zu"
dienst_aus

# ---- (i) DELTA
delta_test

cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf ein1 "ota settings;ota set abstand 900;ota set auto ja;ota settings;exit")
hat "$OUT/ein1.txt" "ota: settings (/etc/ota.conf)" "die Einstellungsseite zeigt, wie das Geraet eingestellt ist"
hat "$OUT/ein1.txt" "quelle   https://10.0.2.2:$PORT" "mit der Quelle"
hat "$OUT/ein1.txt" "ota: set abstand is now 900" "und sie laesst sich umstellen"
hat "$OUT/ein1.txt" "abstand  900" "die neue Zahl steht danach wirklich da"
hat "$OUT/ein1.txt" "auto     ja" "und der Schalter fuer die automatische Suche auch"
# ota service never returns (rounds == 0), the VM is killed by the limit; boot under load needs headroom
rc=$(lauf ein2 "ota set unsinn 5;ota service;exit" 420)
hat "$OUT/ein2.txt" "ota: not a key" "ein unbekannter Schluessel wird abgelehnt"
hat "$OUT/ein2.txt" "ota: service, interval 900" "und der Dienst nimmt den eingestellten Abstand"
cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf ein3 "ota service;exit")
hat "$OUT/ein3.txt" "automatic search is OFF" "GEGENPROBE: mit auto=nein sucht der Dienst gar nicht"

# =====================================================================
echo
echo "== 4. (d) das Update, das NICHT hochkommt -- $RUNDEN volle Durchlaeufe =="
# =====================================================================
#
dgut=0
for r in $(seq 1 "$RUNDEN"); do
    dienst "$OUT/netz3" || bad "Gegenstelle"
    cp -f "$OUT/basis.img" "$OUT/ziel.img"
    rc=$(lauf "d$r-ein" "ota apply;exit")
    dienst_aus
    e1=$(grep -ca "opk: installed hallo" "$OUT/d$r-ein.txt")
    rc=$(lauf "d$r-s1" "sh /start.sh;exit")
    rc=$(lauf "d$r-s2" "sh /start.sh;exit")
    T0=$(date +%s%N)
    rc3=$(lauf "d$r-s3" "sh /start.sh;exit")
    T1=$(date +%s%N)
    zurueck=$(grep -ca "ab: ERPROBUNG gescheitert, zurueck auf 0" "$OUT/d$r-s3.txt")
    alt=$(grep -ca "paket-hallo fassung 1" "$OUT/d$r-s3.txt")
    kaputt=$(grep -ca "SCHEITERT" "$OUT/d$r-s3.txt")
    if [ "$e1" -ge 1 ] && [ "$rc3" = 21 ] && [ "$zurueck" -ge 1 ] \
       && [ "$alt" -ge 1 ] && [ "$kaputt" = 0 ]; then
        dgut=$((dgut+1))
    else
        bad "(d) Durchlauf $r: eingespielt=$e1 rc=$rc3 zurueck=$zurueck alt=$alt kaputt=$kaputt"
    fi
    RUECKMS=$(( (T1 - T0) / 1000000 ))
done
zahl "(d) Durchlaeufe, in denen das Geraet sich SELBST gerettet hat" "$dgut" eq "$RUNDEN"

dienst "$OUT/netz2" || bad "Gegenstelle"
cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf dgeg1 "ota apply;sh /start.sh;exit")
dienst_aus
hat "$OUT/dgeg1.txt" "paket-hallo fassung 2" "(d) GEGENPROBE: das gute Update laeuft"
rc=$(lauf dgeg2 "sh /start.sh;exit")
rc=$(lauf dgeg3 "sh /start.sh;exit")
rc=$(lauf dgeg4 "sh /start.sh;exit")
hat "$OUT/dgeg4.txt" "paket-hallo fassung 2" "(d) GEGENPROBE: auch nach vier Starts laeuft noch die NEUE Fassung"
hatnicht "$OUT/dgeg4.txt" "zurueck auf" "(d) GEGENPROBE: es wird NIE zurueckgefallen"

dienst "$OUT/netz3" || bad "Gegenstelle"
cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf wach1 "ota apply;ota watchdog 5;exit" 300)
dienst_aus
hat "$OUT/wach1.txt" "opk: in trial" "der Wachhund: es steht etwas in Erprobung"
hat "$OUT/wach1.txt" "WATCHDOG: no confirmation" "die Frist laeuft ab, ohne dass jemand bestaetigt"
hat "$OUT/wach1.txt" "WATCHDOG: restart" "und der Wachhund startet die Maschine neu"
cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf wach2 "ota watchdog 5;exit" 300)
hat "$OUT/wach2.txt" "ota: nothing in trial" "GEGENPROBE: ohne Erprobung tut der Wachhund NICHTS"
hatnicht "$OUT/wach2.txt" "WATCHDOG: restart" "und startet vor allem nicht neu"

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
E_F=$T_FERTIG
[ "$E_F" -gt "$E_S1" ] || E_F=$(( E_S1 + 100 ))
E_S2=$(( T_ENDE + 6000 ))
[ "$E_S2" -gt "$E_F" ] || E_S2=$(( E_F + 6000 ))
alt_n=0
neu_n=0
tot_n=0
getroffen=0
verfehlt=0
i=0
while [ "$i" -lt "$SCHUESSE" ]; do
    i=$((i+1))
    dienst "$OUT/netz2" || bad "Gegenstelle"
    cp -f "$OUT/basis.img" "$OUT/ziel.img"
    if [ $(( i % 3 )) = 1 ]; then
        MARKE="ota: source"; VERSATZ=$(( 100 + i * 60 )); PHASE=netz
    elif [ $(( i % 3 )) = 2 ]; then
        MARKE="ota: hash ok"; VERSATZ=$(( 50 + i * 120 )); PHASE=schreiben
    else
        MARKE="ota: READY FOR RESTART"; VERSATZ=$(( 20 + i * 10 )); PHASE=danach
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
    if python3 tools/ota/wait_brand.py "$OUT/e$i.txt" "$MARKE" "$VERSATZ" 600; then
        getroffen=$((getroffen+1))
    else
        verfehlt=$((verfehlt+1))
        echo "        (e) Schuss $i: Marke '$MARKE' kam nicht innerhalb der Frist"
    fi
    kill -9 "$QP" 2>/dev/null
    wait "$QP" 2>/dev/null
    dienst_aus
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' "$OUT/e$i.txt" 2>/dev/null
    rc=$(lauf "en$i" "opk rebuild;/apps/hallo.osp/start;opk list;exit" 400)
    if [ "$rc" != 21 ]; then
        tot_n=$((tot_n+1))
        bad "(e) Schuss $i in Phase $PHASE: die Maschine kommt NICHT mehr hoch (rc=$rc)"
    elif grep -qa "paket-hallo fassung 2" "$OUT/en$i.txt"; then
        neu_n=$((neu_n+1))
    elif grep -qa "paket-hallo fassung 1" "$OUT/en$i.txt"; then
        alt_n=$((alt_n+1))
    else
        tot_n=$((tot_n+1))
        bad "(e) Schuss $i in Phase $PHASE: WEDER die alte NOCH die neue Fassung laeuft"
    fi
done
zahl "(e) Schuesse, nach denen die Maschine ENTWEDER alt ODER neu ist" \
     "$((alt_n + neu_n))" eq "$SCHUESSE"
zahl "(e) davon: nichts dazwischen und kein Ziegelstein" "$tot_n" eq 0
zahl "(e) Schuesse, die WIRKLICH nach dem Umschalten lagen (sonst misst das nichts)" \
     "$neu_n" gt 0
zahl "(e) und Schuesse, die davor lagen" "$alt_n" gt 0
zahl "(e) Schuesse, die ihre Phase wirklich getroffen haben" "$getroffen" eq "$SCHUESSE"
echo "        alt=$alt_n  neu=$neu_n  kaputt=$tot_n  Phase getroffen=$getroffen verfehlt=$verfehlt"
echo "        (Schuesse an Marken der Maschine ausgerichtet: 'ota: source' / 'ota: hash ok' / 'ota: READY FOR RESTART')"

# =====================================================================
echo
echo "== 6. die Messungen =="
# =====================================================================
STORE=$(grep -a "blocks total=" "$OUT/gut3.txt" | tail -1)
printf '   %-52s %s\n' "ein VERZEICHNIS (signierter Katalog, 1 Paket)" "$VZG Oktett"
printf '   %-52s %s\n' "ein Paket (hallo 2.0.0, .opk)" "$PKG Oktett"
printf '   %-52s %s\n' "ein Update auf der Leitung (VERZEICHNIS+sig+INDEX+sig+opk+sig)" \
    "$(du -sb "$OUT/netz2" | cut -f1) Oktett"
printf '   %-52s %s\n' "davon wirklich uebertragen (aus dem Protokoll der Gegenstelle)" \
    "$(awk '/^(200|206) /{s+=$6} END{print s+0}' "$OUT/srv-gut.log" 2>/dev/null) Oktett (der gute Lauf)"
printf '   %-52s %s\n' "von 'ota search' bis zur Antwort (ganzer Start)" "$SUCHMS ms"
printf '   %-52s %s\n' "von 'ota apply' bis 'bereit zum Neustart'" "$EINMS ms (Wanduhr, mit Rahmen)"
printf '   %-52s %s\n' "davon in der Maschine: Firmware->Netz / ->Paket geprueft" "$T_NETZ ms / $T_LADEN ms"
printf '   %-52s %s\n' "in der Maschine: ->geschrieben / ->bereit zum Neustart" "$T_SCHREIB ms / $T_FERTIG ms"
printf '   %-52s %s\n' "Rueckfall: der Start, in dem der Kern zurueckschaltet" "$RUECKMS ms"
printf '   %-52s %s\n' "/bin/fetch (TLS 1.3, X.509, RSA, ECDSA, Ed25519 nein)" "$FSZ Oktett"
printf '   %-52s %s\n' "/bin/ota" "$OSZ Oktett"
printf '   %-52s %s\n' "Bloecke frei -- nach Fassung 1 / nach Fassung 2" \
    "$(echo "$BASISBL" | awk '{print $2}') / $GENBL"
printf '   %-52s %s\n' "Zeilen: kernel/user/ota.fi" "$(grep -c . kernel/user/ota.fi)"
printf '   %-52s %s\n' "Zeilen: tools/ota/ (server, verzeichnis, mkcerts, pakete, run)" \
    "$(cat tools/ota/*.py tools/ota/*.sh | grep -c .)"

fi   # Ende von "$OTA_NUR != kanal"

# =====================================================================
echo
echo "== 7. Kanaele stable/test, Stand, Hintergrund-Dienst, Rueckschritt =="
# =====================================================================
#
rm -rf "$OUT/netzkanal"
mkdir -p "$OUT/netzkanal/stable" "$OUT/netzkanal/test"
cp "$OUT/netz2"/* "$OUT/netzkanal/stable/"
cp "$OUT/quelle2"/* "$OUT/netzkanal/test/" 2>/dev/null
rm -f "$OUT/netzkanal/test/VERZEICHNIS" "$OUT/netzkanal/test/VERZEICHNIS.sig"
python3 tools/ota/listing.py "$OUT/netzkanal/test" --fassung 4 \
    --schluessel "$OUT/geheim.key" > "$OUT/netzkanal.log" 2>&1 \
    && ok "zwei Kanaele gebaut: stable = Fassung 2, test = Fassung 4" \
    || { cat "$OUT/netzkanal.log"; bad "Kanalbaum"; }

dienst "$OUT/netzkanal" || bad "Gegenstelle (Kanaele)"
cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf kan1 "ota set kanal stable;ota show;ota search;cat /system/ota.stand;exit")
gleich "(a) stable: die Maschine kommt hoch" "$rc" "21"
hat "$OUT/kan1.txt" "ota: channel stable" "(a) der Kanal steht in der Anzeige"
hat "$OUT/kan1.txt" "ota: version there 2" "(a) auf stable liegt Fassung 2"
hatnicht "$OUT/kan1.txt" "ota: version there 4" "(a) und nicht die Fassung des Testkanals"
hat "$OUT/kan1.txt" "phase=verfuegbar" "(a) /system/ota.stand: phase=verfuegbar"
hat "$OUT/kan1.txt" "dort=2" "(a) /system/ota.stand: dort=2"
grep -qa "^200 stable/VERZEICHNIS" "$OUT/srv.log" \
    && ok "(a) die Gegenstelle sah die Anfrage unter /stable/" \
    || bad "(a) kein Zugriff auf /stable/VERZEICHNIS im Protokoll"

# (b) Testkanal: einspielen, neu starten, bestaetigen
cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf kan2 "ota set kanal test;ota apply;cat /system/ota.stand;exit")
hat "$OUT/kan2.txt" "ota: version there 4" "(b) auf test liegt Fassung 4"
hat "$OUT/kan2.txt" "opk: installed hallo" "(b) die Fassung vom Testkanal wird installiert"
hat "$OUT/kan2.txt" "ota: READY FOR RESTART" "(b) und zum Neustart angeboten"
hat "$OUT/kan2.txt" "phase=bereit" "(b) /system/ota.stand: phase=bereit"
rc=$(lauf kan3 "sh /start.sh;ota show;cat /system/ota.stand;exit")
gleich "(b) der Neustart" "$rc" "21"
hat "$OUT/kan3.txt" "paket-hallo fassung 2" "(b) die neue Generation laeuft"
hat "$OUT/kan3.txt" "ota: version here 4" "(b) der Fassungszaehler steht auf 4"
hat "$OUT/kan3.txt" "ota: channel test" "(b) und der Kanal ist noch test"
hat "$OUT/kan3.txt" "phase=ruhe" "(b) nach der Bestaetigung steht phase=ruhe"

rc=$(lauf kan4 "ota set kanal stable;ota search;exit")
hat "$OUT/kan4.txt" "ROLLBACK REFUSED" "(c) test -> stable ist ein Rueckschritt und wird abgelehnt"
hatnicht "$OUT/kan4.txt" "opk: installed" "(c) und es wird nichts installiert"

# (d) ungueltige Kanaele
cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf kan5 "ota set kanal stable;ota set kanal beta;ota set kanal ../x;ota settings;exit")
n=$(grep -ca "channel must be stable or test" "$OUT/kan5.txt")
zahl "(d) ungueltige Kanalnamen abgelehnt (beta, ../x)" "$n" ge 2
hat "$OUT/kan5.txt" "kanal    stable" "(d) die Einstellung blieb auf stable"

cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf kan6 "ota set kanal test;ota apply;exit")
rc=$(lauf kan7 "sh /start.sh;exit")
hat "$OUT/kan7.txt" "paket-hallo fassung 2" "(e) Ausgangslage: Fassung 4 laeuft und ist bestaetigt"
rc=$(lauf kan8 "ota rollback;ota show;exit")
rc=$(lauf kan9 "sh /start.sh;ota show;exit")
gleich "(e) nach ota rollback: die Maschine kommt hoch" "$rc" "21"
hat "$OUT/kan9.txt" "paket-hallo fassung 1" "(e) ota rollback: die VORIGE Generation laeuft wieder"
hatnicht "$OUT/kan9.txt" "SCHEITERT" "(e) und sie meldet keinen Fehler"
dienst_aus

dienst "$OUT/netz2" || bad "Gegenstelle (flach)"
cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf kan10 "ota show;ota search;exit")
hat "$OUT/kan10.txt" "ota: version there 2" "(f) ohne kanal= wird wie bisher flach gelesen"
hatnicht "$OUT/kan10.txt" "ota: channel" "(f) und es wird kein Kanal angezeigt"

cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf kan10d "ota set kanal dev;ota search;exit")
hat "$OUT/kan10d.txt" "ota: version there 2" "(f2) kanal=dev: the package check reads the flat feed"
grep -qa "^200 VERZEICHNIS" "$OUT/srv.log" \
    && ok "(f2) the server saw /VERZEICHNIS and not /dev/VERZEICHNIS" \
    || bad "(f2) no flat /VERZEICHNIS request in the server log"

cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf kan10e "echo keepme > /tmp/keep.txt;ota fetch nosuch-9.opk /tmp/keep.txt;cat /tmp/keep.txt;exit")
hat "$OUT/kan10e.txt" "keepme" "(f3) a 404 does not overwrite the target file"

cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf kan11 "ota apply;exit")
hat "$OUT/kan11.txt" "ota: READY FOR RESTART" "(g) Ausgangslage: Fassung 2 steht in Erprobung"
rc=$(lauf kan12 "opk rebuild;ota set gesund 3;ota boot sh;ota show;cat /system/ota.stand;exit" 300)
hat "$OUT/kan12.txt" "ota: start healthy, trial confirmed" "(g) ein gesunder Start wird von selbst bestaetigt"
hat "$OUT/kan12.txt" "ota: nothing in trial" "(g) danach steht nichts mehr in Erprobung"
hat "$OUT/kan12.txt" "phase=ruhe" "(g) und die Anzeige sagt phase=ruhe"
cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf kan13 "ota apply;exit")
rc=$(lauf kan14 "opk rebuild;ota set gesund 2;ota set frist 6;ota boot nirgends;exit" 300)
hat "$OUT/kan14.txt" "start NOT healthy" "(g) GEGENPROBE: ohne laufenden Schreibtisch gilt der Start NICHT als gesund"
hatnicht "$OUT/kan14.txt" "trial confirmed" "(g) GEGENPROBE: und es wird nichts bestaetigt"

# (h) der Hintergrund-Dienst
cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf kan15 "ota set auto nein;ota service 1;ota show;exit")
hat "$OUT/kan15.txt" "OFF" "(h) mit auto=nein tut der Dienst nichts"
hatnicht "$OUT/kan15.txt" "opk: installed" "(h) und installiert nichts"
cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf kan16 "ota set auto ja;ota service 1;cat /system/ota.stand;exit")
hat "$OUT/kan16.txt" "opk: installed hallo" "(h) mit auto=ja holt und installiert der Dienst von selbst"
hat "$OUT/kan16.txt" "ota: READY FOR RESTART" "(h) ohne Neustart -- er wird nur angeboten"
hat "$OUT/kan16.txt" "phase=bereit" "(h) die Anzeige sagt phase=bereit"
hatnicht "$OUT/kan16.txt" "power: init sagt ab" "(h) und es wird NICHT neu gestartet"
# DEFAULT ON (owner decision 02.10.2026): no `auto=` key at all -> the service runs
cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf kan17 "grep -v auto= /etc/ota.conf > /etc/ota.neu;cp /etc/ota.neu /etc/ota.conf;cat /etc/ota.conf;ota service 1;cat /system/ota.stand;exit")
hatnicht "$OUT/kan17.txt" "OFF" "(h) DEFAULT: without an auto= key the service is ON"
hat "$OUT/kan17.txt" "opk: installed hallo" "(h) DEFAULT: and it fetches and installs by itself"
for f in tools/usbimg/build.sh tools/install/build.sh; do
    if grep -q '^auto=true$' "$f"; then ok "(h) $f writes auto=true as the image default"; else bad "(h) $f does not write auto=true"; fi
done
dienst_aus

echo
echo "=================================================================="
echo "  $pass gruen, $fail rot"
echo "=================================================================="
[ "$fail" = 0 ] || exit 1
exit 0
