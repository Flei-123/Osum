#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
ACC=$([ -e /dev/kvm ] && echo kvm || echo tcg)
PROGS="sh cat echo sleep svcprobe"
finish() { [ -n "${SVCWATCH_KEEP:-}" ] && { mkdir -p "$SVCWATCH_KEEP"; cp "$D"/*.klar "$SVCWATCH_KEEP/" 2>/dev/null; }; echo "SVCWATCH: $pass passed, $fail failed"; [ "$fail" = 0 ]; exit $?; }
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
mkdir -p "$D/bin"
bash tools/sync/build.sh "$D/bin" 0 $PROGS > "$D/b.txt" 2>&1 && ok "programs build" || { bad "programs"; head -10 "$D/b.txt"; finish; }
K="${KERNEL:-}"
if [ -z "$K" ]; then
    K="$D/k.mb"
    ./tools/build-kernel.sh "$K" --stufe 0 > "$D/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel"; tail -8 "$D/k.txt"; finish; }
fi
script() {
    echo "svcprobe 6 $1"
    for i in $(seq 1 14); do echo "echo ==P$i=="; echo "cat /proc/watchdog"; echo "sleep 2"; done
    echo "echo ==END=="
}
mkimg() {
    local name=$1
    script "$2" > "$D/$name.sh"
    python3 tools/osum/mkfs.py build "$D/$name.img" 20000 /lib/ \
        "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
        /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ \
        $(for p in $PROGS; do echo "/bin/$p=$D/bin/$p.elf"; done) \
        "/t/s.sh=$D/$name.sh" > "$D/mkfs-$name.txt" 2>&1 || tail -3 "$D/mkfs-$name.txt"
}
runvm() {
    local name=$1 img=$2 secs=$3 words=$4
    cp "$D/$img.img" "$D/d-$name.img"
    (timeout -s KILL "$secs" qemu-system-x86_64 -accel "$ACC" -machine q35 -cpu Skylake-Client -smp 2 -m 1024 -kernel "$K" \
        -append "osum vfs $words script=sh /t/s.sh;exit" \
        -serial "file:$D/o-$name.txt" -display none \
        -global ICH9-LPC.noreboot=false -watchdog-action reset \
        -drive "file=$D/d-$name.img,format=raw,if=ide,index=0" </dev/null >/dev/null 2>&1) 2>/dev/null
    tr -cd '\11\12\15\40-\176' < "$D/o-$name.txt" > "$D/$name.klar"
    rm -f "$D/d-$name.img" "$D/o-$name.txt"
}
mkimg stuck stuck; mkimg alive alive; mkimg gone exit
runvm stuck stuck 75 "wdt=10" &
runvm alive alive 75 "wdt=10" &
runvm gone gone 75 "wdt=10" &
runvm off stuck 75 "wdt=10 nosvcwatch" &
wait
boots() { grep -ac '^wdt: \(armed\|off\|absent\|failed\)' "$D/$1.klar"; }
boots_until_end() { sed -n '1,/^==END==/p' "$D/$1.klar" | grep -ac '^wdt: \(armed\|off\|absent\|failed\)'; }
has() { grep -qa -- "$2" "$D/$1.klar"; }
first_boot() { cat "$D/$1.klar"; }
echo "== a. watched service blocks, shell keeps making syscalls =="
first_boot stuck | grep -qa 'svcwatch: watch pid' && ok "probe is watched" || bad "no watch line"
first_boot stuck | grep -qa 'svcwatch: pid [0-9]* silent [0-9]* s, not feeding' && ok "silence reported" || bad "no silence line"
[ "$(boots stuck)" -ge 2 ] && ok "watchdog resets the machine ($(boots stuck) boots)" || bad "no reset: $(boots stuck) boots"
grep -a '^wdt: armed' "$D/stuck.klar" | sed -n 2p | grep -q 'last_boot=watchdog' && ok "second boot names the watchdog" || bad "second boot without last_boot=watchdog"
echo "== b. watched service alive =="
[ "$(boots_until_end alive)" = 1 ] && has alive "==END==" && ok "one boot until the end" || bad "boots before end: $(boots_until_end alive)"
has alive 'svc_watched 1' && ok "/proc/watchdog counts the watched service" || bad "svc_watched 1 missing"
has alive 'silent [0-9]* s, not feeding' && bad "alive service reported silent" || ok "no silence line"
echo "== c. watched service exits =="
[ "$(boots_until_end gone)" = 1 ] && has gone "==END==" && ok "exited service is dropped, one boot" || bad "boots before end: $(boots_until_end gone)"
has gone 'svc_watched 0' && ok "watched count back to 0" || bad "svc_watched 0 missing"
echo "== d. counter-proof nosvcwatch (old rule) =="
has off 'svcwatch: off (nosvcwatch)' && ok "probe refused by nosvcwatch" || bad "no off line"
[ "$(boots_until_end off)" = 1 ] && has off "==END==" && ok "old rule keeps feeding although the service is stuck" || bad "boots before end: $(boots_until_end off)"
finish
