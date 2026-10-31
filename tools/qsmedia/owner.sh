#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

BASE=$(grep -m1 '^BASE=' tools/qsmedia/run.sh | sed -E 's/^BASE="(.*)"$/\1/')

cat > "$TMPD/ev.sh" <<'EOS'
echo ==EV-FOREIGN==
act call media.control cmd=pause owner=user:Demo
echo rc=$?
echo ==EV-OWN==
act call media.publish title=Mine state=playing
act call media.control cmd=pause
echo rc=$?
echo ==EV-END==
EOS

cat > "$TMPD/dreh.txt" <<'DEOF'
warteauf 'launcher: ready' || 120
warte 6
klick 300,200
warte 1
tippe act call media.publish title=Demo-Song state=playing artist=Tester app=Demo
taste ret
warte 4
tippe act grant app:ev media.control write 60
taste ret
warte 4
tippe /apps/ev.prog/start /t/ev.sh
taste ret
warte 10
foto 01-owner
DEOF

D="$TMPD/o"
for try in 1 2; do
    rm -rf "$D"
    EH_MKFS_EXTRA="/apps/ /apps/ev.prog/ /t/ /apps/ev.prog/start=$DESIGNBUILD/sh.elf /t/ev.sh=$TMPD/ev.sh" \
        bash tools/design/eh6.sh "$D" res=1280x800 accel=kvm progs="$BASE mediad" drehbuch="$TMPD/dreh.txt" tafel=nein > "$TMPD/o.log" 2>&1
    grep -aq '==EV-END==' "$D/serial.txt" 2>/dev/null && break
done
S="$D/serial.txt"
if ! grep -aq '==EV-END==' "$S" 2>/dev/null; then
    bad "the app script did not finish: $(tail -n 3 "$TMPD/o.log" | tr '\n' ' ')"
    echo "QSMEDIA-OWNER: $pass passed, $fail failed"; exit 1
fi
foreign=$(sed -n '/==EV-FOREIGN==/,/==EV-OWN==/p' "$S" | tr -d '\r')
own=$(sed -n '/==EV-OWN==/,/==EV-END==/p' "$S" | tr -d '\r')
if echo "$foreign" | grep -aq 'not_owner'; then ok "an app with a grant cannot steer another owner's session (err not_owner)"; else bad "no not_owner for the foreign session: $(echo "$foreign" | tr '\n' '|' | cut -c1-200)"; fi
if echo "$own" | grep -aq 'not_owner'; then bad "an app was refused for its own session"; else ok "the same app may steer its own session"; fi
if grep -aqE 'panic|EXCEPTION' "$S"; then bad "a panic or exception"; else ok "no panic, no exception"; fi
echo "QSMEDIA-OWNER: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
