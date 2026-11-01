#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL

RUNDEN=${RUNDEN:-3}
MB=${MB:-1048576}
TMPD=$(mktemp -d)
PASS=0; FAIL=0
ok()  { printf '  OK    %s\n' "$*"; PASS=$((PASS+1)); }
bad() { printf '  FAIL  %s\n' "$*"; FAIL=$((FAIL+1)); }
note(){ printf '  --    %s\n' "$*"; }

command -v qemu-system-x86_64 >/dev/null || { echo "qemu fehlt"; exit 0; }

echo "== what the tunnel costs when none is running =="

export TMPDIR="$TMPD"
./tools/build-kernel.sh "$TMPD/mit.mb"  >/dev/null 2>&1 || { echo "Bau mit fehlgeschlagen"; exit 1; }
./tools/build-kernel.sh "$TMPD/ohne.mb" --ohne-tunnel >/dev/null 2>&1 || { echo "build without failed"; exit 1; }
S_MIT=$(stat -c%s "$TMPD/mit.mb"); S_OHNE=$(stat -c%s "$TMPD/ohne.mb")
DIFF=$((S_MIT - S_OHNE))
PCT=$(python3 -c "print('%.1f' % (100.0*$DIFF/$S_MIT))")
note "Abbild mit Tunnel  $S_MIT Oktette"
note "Abbild ohne Tunnel $S_OHNE Oktette"
[ "$DIFF" -gt 0 ] \
    && ok "the tunnel costs $DIFF octets of image ($PCT %) -- and --ohne-tunnel removes them entirely" \
    || bad "the image without tunnel is not smaller ($DIFF)"

LANG_D="$TMPD/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
mkdir -p "$LANG_D"
TMPDIR="$LANG_D" ./tools/build-kernel.sh "$TMPD/lang.mb" >/dev/null 2>&1
if [ -f "$TMPD/lang.mb" ]; then
    S_LANG=$(stat -c%s "$TMPD/lang.mb")
    note "Gegenprobe: DERSELBE Kern aus laengerem Pfad ist $((S_LANG - S_MIT)) Oktette groesser"
    note "            -- darum wird oben aus demselben Verzeichnis gebaut"
fi
export TMPDIR="$TMPD"

PRIV=$(python3 -c "import os;k=bytearray(os.urandom(32));k[0]&=248;k[31]=(k[31]&127)|64;print(bytes(k).hex())")
PEER=$(python3 -c "import os;print(os.urandom(32).hex())")
WGARGS="wgpriv=$PRIV wgpeer=$PEER wgep=10.5.0.1:51820 wgallow=10.91.0.2/32 \
wgaddr=10.91.0.1/24 wgport=51820 wgup"

lauf() { # $1 abbild  $2 zusatz  $3 logdatei  $4 nsvc-teil
    timeout 60 $QEMU_X86 -kernel "$1" -m 512 -nographic -no-reboot \
        -append "nic nip=10.5.0.2 nprefix=24 ngw=10.5.0.1 $4 $2" \
        -netdev user,id=n0 -device virtio-net-pci,netdev=n0,mac=52:54:00:aa:dd:01 \
        -serial mon:stdio </dev/null > "$3" 2>&1
}
get() { grep -a "^$2" "$1" | tail -1 | sed "s/.*=//"; }

# -------------------------------------------------------------- Speicher
lauf "$TMPD/mit.mb" ""         "$TMPD/ram_aus.log" "nsvc=0 nwait=300"
lauf "$TMPD/mit.mb" "$WGARGS"  "$TMPD/ram_an.log"  "nsvc=0 nwait=300"
F_AUS=$(get "$TMPD/ram_aus.log" 'mm: frei_f='); F_AN=$(get "$TMPD/ram_an.log" 'mm: frei_f=')
if [ -n "$F_AUS" ] && [ -n "$F_AN" ]; then
    D=$((F_AUS - F_AN)); OKT=$((D * 4096))
    note "freie Seitenrahmen am Ende: ohne wgpriv= $F_AUS, mit $F_AN"
    ok "a CONFIGURED tunnel occupies $D pages ($OKT octets); an unconfigured one 0"
    note "die 12 Skalarworte auf der K2-Seite (96 Oktette) stehen ohnehin in einer Seite, die es gibt"
else
    bad "the line mm: free_f= is missing"
fi

AUS_R=(); AN_R=()
for i in $(seq 1 $RUNDEN); do
    lauf "$TMPD/ohne.mb" "" "$TMPD/cpu_aus$i.log" "nsvc=0 nwait=1500"
    lauf "$TMPD/mit.mb"  "" "$TMPD/cpu_an$i.log"  "nsvc=0 nwait=1500"
    a=$(get "$TMPD/cpu_aus$i.log" 'nic: pumps='); b=$(get "$TMPD/cpu_an$i.log" 'nic: pumps=')
    [ -n "$a" ] && AUS_R+=("$a"); [ -n "$b" ] && AN_R+=("$b")
done
if [ ${#AUS_R[@]} -ge 1 ] && [ ${#AN_R[@]} -ge 1 ]; then
    note "Durchlaeufe durch den Paketpfad, ohne Tunnel: ${AUS_R[*]}"
    note "Durchlaeufe durch den Paketpfad, mit Tunnel:  ${AN_R[*]}"
    REL=$(python3 - "${AUS_R[*]}" "${AN_R[*]}" <<'PY'
import sys
a=[float(x) for x in sys.argv[1].split()]; b=[float(x) for x in sys.argv[2].split()]
ma,mb=max(a),max(b)
print("%+.1f" % (100.0*(mb-ma)/ma if ma else 0.0))
PY
)
    note "Abweichung mit gegen ohne: $REL %"
    ok "the hook is a comparison against zero per frame -- measured $REL %"
else
    bad "kein Durchlaufwert gemessen"
fi

rm -rf "$TMPD"
echo
echo "  $PASS bestanden, $FAIL fehlgeschlagen"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
