#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/keymap/run.sh -- R-011: keyboard layouts as data, dead keys, compose, caps lock, runtime switching.
#   bash tools/keymap/run.sh                  host part + QEMU part (use /root/jarvis/bin/heavy for the QEMU part)
#   KEYMAP_HOST_ONLY=1 bash tools/keymap/run.sh   host part only (seconds)
# 1. the generated data is what tools/hid/kbdgen.py makes from the xkb data
# 2. host build of the kernel modules (tools/keymap/host.fi), dump, comparison with libxkbcommon (tools/keymap/oracle.py)
# 3. COUNTER-PROOFS: a damaged dump, a damaged table, a damaged engine must make the oracle fail
# 4. QEMU, USB keyboard through QMP (tools/keymap/drive.py): /etc/keyboard.conf at boot, AltGr, dead keys, caps lock, compose,
#    Ctrl+Alt+L, Win+Space, AZERTY; a self test program for KB_SET/KB_COUNT and the config file
# 5. COUNTER-PROOF of the QEMU part: the tree before this round must fail the dead key / compose / conf facts
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
T=$(mktemp -d)
OLDWT=""
trap 'cd "$ROOT"; [ -n "$OLDWT" ] && git worktree remove --force "$OLDWT" >/dev/null 2>&1; rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 || { echo "KEYMAP: fetch-firnc.sh failed"; exit 1; }
FIRNC="$ROOT/vendor/firn/bin/firnc"

host_build() {
    local lib=$1 out=$2
    FIRNLIB="$lib" "$FIRNC" --profile=app tools/keymap/host.fi -o "$out" > "$out.build" 2>&1
}
make_lib() {
    local dir=$1
    mkdir -p "$dir/lib"
    cp -a kernel/drv "$dir/lib/drv"
    cp -a lib/keymap "$dir/lib/keymap"
}

echo "== 1. generated data"
python3 -I tools/hid/kbdgen.py --check && ok "kbdnames.fi, kbdlay.fi, kbdcomb.fi are what kbdgen.py makes from the xkb data" \
    || bad "generated data is stale (run python3 tools/hid/kbdgen.py)"

echo "== 2. host engine against libxkbcommon"
mkdir -p "$T/good/lib"
ln -s "$ROOT/kernel/drv" "$T/good/lib/drv"
ln -s "$ROOT/lib/keymap" "$T/good/lib/keymap"
if host_build "$T/good/lib" "$T/host"; then
    ok "tools/keymap/host.fi builds against the kernel modules"
    "$T/host" > "$T/dump.txt"
    layouts=$(head -1 "$T/dump.txt" | awk '{print $2}')
    [ "${layouts:-0}" -ge 10 ] && ok "$layouts layouts in the registry" || bad "only ${layouts:-0} layouts"
    python3 -I tools/keymap/oracle.py "$T/dump.txt" > "$T/oracle.txt"; orc=$?
    sed 's/^/        /' "$T/oracle.txt"
    [ "$orc" = 0 ] && ok "oracle: all sections agree with xkb" || bad "oracle found differences"
else
    bad "host build failed"; grep -v '^warning' "$T/host.build" | head -20
    echo "KEYMAP: $pass passed, $fail failed"; exit 1
fi
a=$(grep -c "^L 1 16 2 64 64$" "$T/dump.txt")
[ "$a" = 1 ] && ok "de: AltGr+Q = @ (64)" || bad "de: AltGr+Q is not @"
b=$(grep -c "^D [0-9]* 101 0 234 0$" "$T/dump.txt")
[ "$b" -ge 1 ] && ok "dead circumflex + e = ê (234) in the dump" || bad "no dead + e = ê in the dump"

echo "== 3. counter-proofs (the oracle must fall)"
sed 's/^L 1 16 2 64 64$/L 1 16 2 65 65/' "$T/dump.txt" > "$T/dump-bad.txt"
python3 -I tools/keymap/oracle.py "$T/dump-bad.txt" > /dev/null; [ $? != 0 ] && ok "a damaged dump entry is detected" || bad "damaged dump not detected"
make_lib "$T/bad1"
python3 -I - "$T/bad1/lib/drv/hid/kbdcomb.fi" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
i = s.index("static mut DEAD_TAB")
m = re.compile(r"\d+").search(s, s.index("\n", i))
s = s[:m.start()] + str(int(m.group()) + 1) + s[m.end():]
open(p, "w").write(s)
PY
host_build "$T/bad1/lib" "$T/host1" && "$T/host1" > "$T/dump1.txt" && python3 -I tools/keymap/oracle.py "$T/dump1.txt" > /dev/null
[ $? != 0 ] && ok "a damaged dead key table entry is detected" || bad "damaged dead key table not detected"
make_lib "$T/bad2"
sed -i 's/return kbdcompose.feed(kbdmap.plain_char(e))/return kbddead.feed(e)/' "$T/bad2/lib/drv/hid/kbdinput.fi"
host_build "$T/bad2/lib" "$T/host2" && "$T/host2" > "$T/dump2.txt" && python3 -I tools/keymap/oracle.py "$T/dump2.txt" > /dev/null
[ $? != 0 ] && ok "a switched off compose state machine is detected" || bad "broken compose not detected"
make_lib "$T/bad3"
sed -i '0,/return spacing(id)/s//return 0/' "$T/bad3/lib/drv/hid/kbddead.fi"
host_build "$T/bad3/lib" "$T/host3" && "$T/host3" > "$T/dump3.txt" && python3 -I tools/keymap/oracle.py "$T/dump3.txt" > /dev/null
[ $? != 0 ] && ok "a broken double dead key is detected" || bad "broken double dead key not detected"

if [ -n "${KEYMAP_HOST_ONLY:-}" ]; then
    echo; echo "KEYMAP: $pass passed, $fail failed (host part only)"; [ "$fail" = 0 ]; exit
fi
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "KEYMAP: QEMU part skipped, no qemu"; echo "KEYMAP: $pass passed, $fail failed"; [ "$fail" = 0 ]; exit; }

echo "== 4. QEMU: desktop image, USB keyboard through QMP"
printf 'keyboard.layout=de\n' > "$T/keyboard.conf"
printf 'tray_language=1\n' > "$T/taskbar.conf"
run_tree() {
    local tree=$1 out=$2
    mkdir -p "$out"
    ( cd "$tree" && bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
      ALLTAGBUILD="$out.build" bash tools/alltag/build.sh "$out" kbd=no warten=1 uitrace=yes lang=en \
        extra="modfs osum wmshell wmdauer usb hidgen lang=en" hold=no waitfor="eingabe: ber=" \
        progs="desktop taskbar sh echo ls cat" xfile=/etc/keyboard.conf="$T/keyboard.conf" tbconf="$T/taskbar.conf" \
        qemu="-device qemu-xhci -device usb-kbd -qmp unix:$out/qmp.sock,server,nowait" \
        hook="python3 $ROOT/tools/keymap/drive.py $out/qmp.sock $out/serial.txt $out 8" ) > "$out.log" 2>&1
}
fact() { [ "$(grep -a "^$2=" "$1" 2>/dev/null | tail -1 | cut -d= -f2)" = 1 ] && ok "$3" || bad "$3 ($2 != 1)"; }
run_tree "$ROOT" "$T/new" || { bad "build/run failed"; tail -n 15 "$T/new.log"; echo "KEYMAP: $pass passed, $fail failed"; exit 1; }
S="$T/new/serial.txt"; F="$T/new/scenes.txt"
fact "$F" conf_applied "boot: /etc/keyboard.conf applied (kbdconf: apply de)"
fact "$F" tray_shows_de "tray: lang=en but the layout is de -> the tray cell says DEU"
fact "$F" altgr_q_at "de: AltGr+Q = @"
fact "$F" dead_circumflex_waits "de: ^ waits for the next key"
fact "$F" circumflex_e "de: ^ then e = ê"
fact "$F" dead_acute_waits "de: ´ waits for the next key"
fact "$F" acute_e "de: ´ then e = é"
fact "$F" dead_grave_waits "de: \` waits for the next key"
fact "$F" grave_space_is_grave "de: \` then Space = \` (one key, the accent alone)"
fact "$F" dead_then_x_waits "de: ^ waits"
fact "$F" dead_then_x_two_keys "de: ^ then x = ^ and x"
fact "$F" dead_twice_waits "de: ^ waits (twice)"
fact "$F" dead_twice_accent "de: ^ twice = ^"
fact "$F" dead_diaeresis_waits "de: AltGr+ü is a dead key"
fact "$F" diaeresis_u "de: AltGr+ü then u = ü"
fact "$F" caps_a "de: Caps Lock + a = A"
fact "$F" caps_umlaut "de: Caps Lock + ä = Ä"
fact "$F" caps_off "de: Caps Lock off again"
fact "$F" compose_armed "compose: right Ctrl tap arms it"
fact "$F" compose_first "compose: first key waits"
fact "$F" compose_o_c "compose: o c = ©"
fact "$F" menu_armed "compose: the Menu key arms it (USB usage 0x65)"
fact "$F" menu_compose_first "compose: first key waits"
fact "$F" menu_compose_o_c "compose via Menu: o c = ©"
fact "$F" iso_key_less "de: the ISO key (0x56 / USB 0x64) types <"
fact "$F" combo_next_uk "Ctrl+Alt+L: de -> uk"
fact "$F" combo_next_fr "Ctrl+Alt+L: uk -> fr"
fact "$F" azerty_q_is_a "fr: the Q key types a"
fact "$F" azerty_a_is_q "fr: the A key types q"
fact "$F" azerty_2_is_eacute "fr: the 2 key types é"
fact "$F" tray_shows_fr "tray: after Ctrl+Alt+L the tray cell says FR"
fact "$F" win_space_next_es "Win+Space: fr -> es"
fact "$F" es_ntilde "es: the ; key types ñ"
fact "$F" tray_shows_es "tray: after Win+Space the tray cell says ES"
grep -qa "^hk: super+ " "$S" && bad "Win+Space leaked as a hotkey" || ok "Win+Space is not a hotkey"

echo "== 4b. QEMU: self test program (KB_SET, KB_COUNT, /etc/keyboard.conf round trip)"
D="$T/self"
mkdir -p "$D"
( ALLTAGBUILD="$D.build" bash tools/alltag/build.sh "$D" shot=no desk=no script="kbdconft;exit" progs="kbdconft sh" \
    extra="nokbd nosched noproc nofs noring3 osum" ) > "$D.log" 2>&1
P=$(grep -aoE 'kbdconft: pass=[0-9]+' "$D/serial.txt" | tail -1 | sed 's/.*=//')
Fl=$(grep -aoE 'kbdconft: pass=[0-9]+ fail=[0-9]+' "$D/serial.txt" | tail -1 | sed 's/.*fail=//')
[ "${P:-0}" -ge 8 ] && [ "${Fl:-9}" = 0 ] && ok "kbdconft: $P checks, 0 failed" || { bad "kbdconft: pass=${P:-?} fail=${Fl:-?}"; grep -a "kbdconft:" "$D/serial.txt" | head -12; tail -n 8 "$D.log"; }

echo "== 5. COUNTER-PROOF: the tree before this round"
BASE=${KEYMAP_BASE:-$(git merge-base HEAD origin/main 2>/dev/null)}
if [ -n "$BASE" ] && git rev-parse -q --verify "$BASE^{commit}" >/dev/null 2>&1; then
    OLDWT="$T/basetree"
    git worktree add -q --detach "$OLDWT" "$BASE" 2>/dev/null
    mkdir -p "$OLDWT/tools/keymap"
    cp tools/keymap/drive.py "$OLDWT/tools/keymap/drive.py"
    run_tree "$OLDWT" "$T/old" || { echo "        (old tree run failed)"; tail -n 6 "$T/old.log"; }
    FO="$T/old/scenes.txt"
    [ -s "$T/old/serial.txt" ] && ok "old kernel booted (counter-proof is a real run)" || bad "old run produced no serial"
    red=$(grep -c "=0$" "$FO" 2>/dev/null || echo 0)
    [ "$red" -ge 10 ] && ok "counter-proof: the old tree fails $red of the facts" || bad "counter-proof: the old tree fails only $red facts"
    for k in conf_applied circumflex_e acute_e compose_o_c azerty_q_is_a; do
        [ "$(grep -a "^$k=" "$FO" 2>/dev/null | cut -d= -f2)" = 1 ] && bad "old tree already did: $k" || ok "old tree cannot: $k"
    done
else
    bad "no base commit for the counter-proof"
fi
echo
echo "KEYMAP: $pass passed, $fail failed"
[ "$fail" = 0 ]
