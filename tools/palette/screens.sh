#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
[ -w /dev/kvm ] && export OSUM_ACCEL=kvm
command -v swtpm >/dev/null 2>&1 || { echo "PALETTE-SCREENS: swtpm missing"; exit 1; }
OUT=$(mktemp -d)
SWPIDS=()
cleanup() { for p in "${SWPIDS[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done; [ -n "${SCREENS_KEEP:-}" ] && cp -r "$OUT" "$SCREENS_KEEP" 2>/dev/null; rm -rf "$OUT"; }
trap cleanup EXIT
pass=0; fail=0
B=tools/alltag/build.sh

python3 - "$OUT" <<'PY'
import binascii, hashlib, sys
d = sys.argv[1]
it, salt = 1024, bytes(range(8))
dk = hashlib.pbkdf2_hmac("sha256", b"geheim12", salt, it, 32)
rec = "$osum1$%d$%s$%s" % (it, binascii.hexlify(salt).decode(), binascii.hexlify(dk).decode())
open(d + "/shadow", "w").write("justin:%s:1000:0:99999:7:::\nroot:%s:0:0:99999:7:::\n" % (rec, rec))
open(d + "/passwd", "w").write("root:x:0:0:root:/root:/bin/sh\njustin:x:1000:1000:Justin:/users/justin:/bin/sh\n")
PY
echo on > "$OUT/uiblink"
printf 'kib=64\npasses=1\nlanes=1\n' > "$OUT/kdf"
cat > "$OUT/vuihost.script" <<EOS
/bin/vaultd /secrets 30000 &
sleep 3000
/bin/pinctl set root 482915
/bin/vaultctl create pw=correct-horse-battery
/bin/vaultctl tpmenroll pin=482915
/bin/vaultctl lock
/bin/vaultui
EOS

shoot_login() {
    local app=$1 scheme=$2 nm=$1-$2
    bash "$B" "$OUT/$nm" scheme="$scheme" mode=dark kbd=yes uitrace=yes warten=12 bloecke=32768 \
        extra="wigapp=/bin/$app wighalt=100" progs="$app theme sh echo ls cat" \
        xfile=/etc/shadow="$OUT/shadow" xfile=/etc/uiblink="$OUT/uiblink" passwdfile="$OUT/passwd" \
        xfile=/etc/wallpaper=assets/wallpaper-sea.osym \
        mon=warte\ 3 mon=sendkey\ a mon=warte\ 1 mon=sendkey\ b mon=warte\ 1 mon=mouse_move\ -4000\ -4000 mon=warte\ 1 \
        > "$OUT/$nm.log" 2>&1
}

shoot_vault() {
    local scheme=$1 nm=vault-$1
    local sock="$OUT/tpm-$nm.sock"
    mkdir -p "$OUT/st-$nm"
    swtpm socket --tpmstate "dir=$OUT/st-$nm" --ctrl "type=unixio,path=$sock" --tpm2 --log "file=$OUT/sw-$nm.log" &
    SWPIDS+=($!)
    local _i
    for _i in $(seq 50); do [ -S "$sock" ] && break; sleep 0.1; done
    bash "$B" "$OUT/$nm" scheme="$scheme" mode=dark kbd=yes uitrace=yes lang=en \
        "accel=${OSUM_ACCEL:-tcg}" "waitfor=vaultui: ready" \
        "extra=osum vfs bus wighalt=120 wigapp=/bin/vuihost" \
        "progs=vaultui vaultd vaultctl pinctl vuihost theme" \
        xdir=/proc xdir=/dev xdir=/secrets xdir=/etc/vault \
        "xfile=/etc/vuihost.script=$OUT/vuihost.script" "xfile=/etc/vault/kdf=$OUT/kdf" \
        "xfile=/etc/wallpaper=assets/wallpaper-sea.osym" \
        "qemu=-chardev socket,id=chrtpm,path=$sock -tpmdev emulator,id=tpm0,chardev=chrtpm -device tpm-tis,tpmdev=tpm0" \
        warten=4 mon=warte\ 6 > "$OUT/$nm.log" 2>&1
}

judge() {
    local case=$1 scheme=$2 want=$3 nm=$1-$2
    if [ ! -s "$OUT/$nm/desktop.ppm" ]; then
        echo "  FAIL  $nm: no screenshot"; fail=$((fail+1)); return
    fi
    if python3 -I tools/palette/screens.py "$case" "$OUT/$nm/desktop.ppm" > "$OUT/$nm.txt" 2>&1; then got=green; else got=red; fi
    if [ "$got" = "$want" ]; then
        echo "  OK    $nm is $got as expected"; pass=$((pass+1))
        [ "$want" = green ] && sed 's/^/        /' "$OUT/$nm.txt"
    else
        echo "  FAIL  $nm is $got, expected $want"; sed 's/^/        /' "$OUT/$nm.txt"; fail=$((fail+1))
    fi
}

for app in glogin lock; do
    echo "== $app =="
    shoot_login "$app" day
    judge "$app" day green
    shoot_login "$app" night
    judge "$app" night red
done
echo "== vault =="
shoot_vault day
judge vault day green
shoot_vault night
judge vault night red

echo
echo "PALETTE-SCREENS: $pass passed, $fail failed"
[ "$fail" = 0 ]
