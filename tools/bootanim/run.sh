#!/usr/bin/env bash
set -u
cd "$(dirname "$0")/../.."
pass=0; fail=0
ok()  { echo "  OK    $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; fail=$((fail+1)); }
STYLES="ignite sunrise particle reactor mix"
W=640; H=360; FPS=60
BUDGET_MS=${BOOTANIM_BUDGET_MS:-70}
H_DIR=$(mktemp -d)
trap 'rm -rf "$H_DIR"' EXIT
. tools/lib/firnenv.sh

frame() {
    "$H_DIR/render" "$H_DIR/logo" "$H_DIR/target" "$1" $W $H $(($2 + 1)) $FPS "$2" > "$H_DIR/$1-$2.raw"
}

echo "== host: every style renders, moves, ends on the login picture =="
"$FIRNC" --profile=app --opt-level=release-fast tools/bootanim/render.fi -o "$H_DIR/render" > "$H_DIR/build.log" 2>&1 && ok "renderer builds" || { bad "renderer does not build"; grep -v '^warning' "$H_DIR/build.log" | head; }
python3 tools/bootloader/mklogo.py assets/marke/signet-1024.png "$H_DIR/logo" > /dev/null
ffmpeg -v error -y -i assets/ref/sea-wallpaper.jpg -vf "scale=$W:$H:force_original_aspect_ratio=increase,crop=$W:$H" -pix_fmt bgr0 -f rawvideo "$H_DIR/target"
for s in $STYLES; do
    frame "$s" 30; frame "$s" 90; frame "$s" 150; frame "$s" 290
    python3 -I tools/bootanim/shots.py moved "$H_DIR/$s-30.raw" "$H_DIR/$s-90.raw" ${W}x$H && ok "$s: picture changes over time" || bad "$s: frozen"
    python3 -I tools/bootanim/shots.py lit "$H_DIR/$s-150.raw" ${W}x$H && ok "$s: scene is lit" || bad "$s: scene dark"
    python3 -I tools/bootanim/shots.py equal "$H_DIR/$s-290.raw" "$H_DIR/target" ${W}x$H && ok "$s: ends on the login picture" || bad "$s: end differs from the login picture"
    python3 -I tools/bootanim/shots.py equal "$H_DIR/$s-90.raw" "$H_DIR/target" ${W}x$H && bad "$s: counter-proof, mid frame accepted as login picture" || ok "$s: counter-proof, mid frame is not the login picture"
done
python3 -I tools/bootanim/shots.py moved "$H_DIR/mix-90.raw" "$H_DIR/mix-90.raw" ${W}x$H && bad "counter-proof: identical frames accepted as moving" || ok "counter-proof: identical frames rejected"
frame bogus 90
cmp -s "$H_DIR/bogus-90.raw" "$H_DIR/mix-90.raw" && ok "unknown style name falls back to the default (mix)" || bad "unknown style name not mapped to the default"

echo "== host: frame budget at 1920x1080 (release-fast, ${BUDGET_MS} ms) =="
ffmpeg -v error -y -i assets/ref/sea-wallpaper.jpg -vf "scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080" -pix_fmt bgr0 -f rawvideo "$H_DIR/target"
for s in $STYLES; do
    t0=$(date +%s%N)
    "$H_DIR/render" "$H_DIR/logo" "$H_DIR/target" "$s" 1920 1080 150 $FPS 120 > /dev/null
    ms=$(( ($(date +%s%N) - t0) / 30000000 ))
    [ "$ms" -le "$BUDGET_MS" ] && ok "$s: $ms ms per frame" || bad "$s: $ms ms per frame over budget"
done

if [ -z "${BOOTANIM_HOST_ONLY:-}" ]; then
    . tools/bootloader/lib.sh
    D=$(mktemp -d /root/abbilder/bootanimgate.XXXXXX)
    trap 'rm -rf "$H_DIR" "$D"' EXIT
    osb_prepare "$D" || { echo "BOOTANIM: prepare failed"; exit 1; }
    for s in $STYLES; do
        echo "== QEMU osboot: style $s =="
        python3 tools/bootloader/mkcfg.py "$D/limine.conf" "$D/$s.cfg" --timeout 0 --keywait 12000 --logo /osboot.logo --anim "$s" > /dev/null
        osb_with_cfg "$D" "$s" "$D/$s.cfg"
        osb_start "$D" "$s" "$D/$s.base" q35 ehci
        if osb_wait_text "$D" "$s" "osboot" 60; then
            sleep 2
            osb_shot "$D" "$s" "${s}A"
            sleep 2
            osb_shot "$D" "$s" "${s}B"
            python3 -I tools/bootanim/shots.py moved "$D/${s}A.ppm" "$D/${s}B.ppm" && ok "$s: animates in the loader" || bad "$s: frozen in the loader"
            python3 -I tools/bootanim/shots.py lit "$D/${s}B.ppm" && ok "$s: loader scene is lit" || bad "$s: loader screen dark"
            [ -n "${EVID:-}" ] && mkdir -p "$EVID" && ffmpeg -v error -y -i "$D/${s}B.ppm" "$EVID/qemu-$s.png"
        else
            bad "$s: osboot did not start"
        fi
        osb_stop "$D" "$s"
        rm -f "$D/$s.base"
    done
fi
echo "bootanim: $pass passed, $fail failed"
[ "$fail" = 0 ]
