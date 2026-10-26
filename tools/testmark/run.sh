#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
printf 'testmode=1\n' > "$TMPD/on.conf"
printf 'testmode=0\n' > "$TMPD/off.conf"
cat > "$TMPD/s.txt" <<'DEOF'
warteauf 'taskbar: steht|taskbar: geom' || 120
warte 14
foto 01
DEOF
run_one() {
    mkdir -p "$TMPD/$1"
    EH_ETC_EXTRA="$2" EH_MKFS_EXTRA="/proc/" DESIGNBUILD="$TMPD/$1/build" bash tools/design/eh6.sh "$TMPD/$1/o" res=1280x800 accel=kvm tafel=nein "extra=vfs lang=en" \
        drehbuch="$TMPD/s.txt" > "$TMPD/$1/o.log" 2>&1
    rm -rf "$TMPD/$1/build"
}
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
run_one a "/etc/drvstore.conf=$TMPD/on.conf@0644" &
run_one b "/etc/drvstore.conf=$TMPD/off.conf@0644" &
run_one c "" &
wait
SA="$TMPD/a/o/serial.txt"; SB="$TMPD/b/o/serial.txt"; SC="$TMPD/c/o/serial.txt"
if [ -n "${TESTMARK_OUT:-}" ]; then
    mkdir -p "$TESTMARK_OUT"
    for r in a b c; do cp "$TMPD/$r/o/serial.txt" "$TESTMARK_OUT/serial-$r.txt" 2>/dev/null; cp "$TMPD/$r/o/"*.ppm "$TESTMARK_OUT/$r-" 2>/dev/null; done
fi
grep -aq 'testmark: shown' "$SA" && ok "A: testmode=1 -> watermark shown" || bad "A: no 'testmark: shown'"
grep -aq 'testmark: hidden' "$SA" && bad "A: watermark hidden again" || ok "A: watermark stays"
grep -aq 'testmark: \(shown\|hidden\|no window\)' "$SB" && bad "B COUNTER-PROOF: watermark with testmode=0" || ok "B COUNTER-PROOF: testmode=0 -> no watermark"
grep -aq 'testmark: \(shown\|hidden\|no window\)' "$SC" && bad "C COUNTER-PROOF: watermark without config" || ok "C COUNTER-PROOF: no config -> no watermark"
n=$(grep -ac 'ABSTURZ\|EXCEPTION\|panic' "$SA" "$SB" "$SC" | awk -F: '{s+=$2} END{print s+0}')
[ "$n" = 0 ] && ok "no crash or panic" || bad "crash lines: $n"
echo "TESTMARK: $pass passed, $fail failed"
[ "$fail" = 0 ]
