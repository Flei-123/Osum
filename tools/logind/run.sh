#!/usr/bin/env bash
#
#   bash tools/logind/run.sh [<build-dir>]
#
set -uo pipefail
SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)
cd "$SELF_DIR/../.." || { echo "== the tree is not reachable from $SELF_DIR" >&2; exit 1; }
[ -f tools/osum/mkfs.py ] || { echo "== $(pwd) is not the Osum tree" >&2; exit 1; }
ROOT_DIR=$(pwd)
mkdir -p "$ROOT_DIR/.logind-mess"

BUILD=${1:-/root/lg-img}
OK=0
FAIL=0

ok()   { echo "  OK    $*"; OK=$((OK + 1)); }
bad()  { echo "  FAIL  $*"; FAIL=$((FAIL + 1)); }
info() { echo "        $*"; }
section() { echo; echo "== $*"; }

# ---------------------------------------------------------------- bauen
if [ ! -f "$BUILD/osum.mb" ] || [ ! -f "$BUILD/root.img" ]; then
    section "0. build"
    bash tools/usbimg/build.sh "$BUILD" > "$ROOT_DIR/.logind-mess/build.log" 2>&1 \
        || { tail -20 "$ROOT_DIR/.logind-mess/build.log"; bad "the build failed"; \
             echo; echo "LOGIND: $OK passed, $FAIL failed"; exit 1; }
    ok "kernel and root built"
else
    section "0. using the existing build directory"
    info "$BUILD ($(stat -c%s "$BUILD/osum.mb") bytes kernel)"
fi

LISTING="$BUILD/liste.txt"
[ -f "$LISTING" ] || bash tools/mkfsfi/mkfs.sh list "$BUILD/root.img" > "$LISTING" 2>&1

section "1. the image carries what the login needs"
for f in /bin/glogin /bin/lock /bin/login /bin/passwd /bin/su \
         /bin/idlelock /etc/shadow /etc/passwd /etc/group \
         /etc/login.conf /etc/sperre.conf; do
    if grep -qE "(^|[[:space:]])${f}([[:space:]]|\$)" "$LISTING"; then
        ok "in the image: $f"
    else
        bad "MISSING in the image: $f"
    fi
done

SHADOW=$(bash tools/mkfsfi/mkfs.sh cat "$BUILD/root.img" /etc/shadow 2>/dev/null)
if echo "$SHADOW" | grep -q '\$osum1\$'; then
    ok "/etc/shadow has \$osum1\$ entries (PBKDF2)"
    info "$(echo "$SHADOW" | wc -l) lines, rounds $(echo "$SHADOW" | sed -n 's/.*\$osum1\$\([0-9]*\)\$.*/\1/p' | head -1)"
else
    bad "/etc/shadow has no \$osum1\$ entries"
fi
if grep -aq 'startkennwort' "$BUILD/root.img"; then
    bad "NEGATIVE CONTROL: 'startkennwort' is in PLAIN TEXT in the image"
else
    ok "NEGATIVE CONTROL: 'startkennwort' is NOT in plain text in the image"
fi
if grep -aq 'osumroot' "$BUILD/root.img"; then
    bad "NEGATIVE CONTROL: 'osumroot' is in PLAIN TEXT in the image"
else
    ok "NEGATIVE CONTROL: 'osumroot' is NOT in plain text in the image"
fi

# ========================================= 2. THE HOME DIRECTORY
section "2. the home directory of justin (docs/RUNDE-ANMELDUNG.md 5.4)"
HOME_DIR=$(bash tools/mkfsfi/mkfs.sh cat "$BUILD/root.img" /etc/passwd 2>/dev/null \
       | sed -n 's/^justin:[^:]*:[^:]*:[^:]*:[^:]*:\([^:]*\):.*/\1/p')
if [ "$HOME_DIR" = "/users/justin" ]; then
    ok "/etc/passwd names as home: $HOME_DIR"
else
    bad "/etc/passwd names another home: '$HOME_DIR'"
fi
for d in /users/justin/ /users/justin/config/; do
    if grep -qE "(^|[[:space:]])${d}([[:space:]]|\$)" "$LISTING"; then
        ok "in the image: $d"
    else
        bad "MISSING in the image: $d"
    fi
done
M=$(bash tools/mkfsfi/mkfs.sh meta "$BUILD/root.img" /users/justin 2>/dev/null)
if [ "$M" = "/users/justin 700 1000 1000" ]; then
    ok "it belongs to justin and only to him: $M"
else
    bad "wrong mode/owner: '$M' (expected '/users/justin 700 1000 1000')"
fi
M2=$(bash tools/mkfsfi/mkfs.sh meta "$BUILD/root.img" /users/justin/config 2>/dev/null)
if [ "$M2" = "/users/justin/config 700 1000 1000" ]; then
    ok "config/ too: $M2"
else
    bad "config/ wrong mode: '$M2'"
fi
MR=$(bash tools/mkfsfi/mkfs.sh meta "$BUILD/root.img" /users/root 2>/dev/null)
case "$MR" in
    *" 0 0") ok "NEGATIVE CONTROL: /users/root still belongs to root ($MR)" ;;
    *)       bad "NEGATIVE: /users/root no longer belongs to root ($MR)" ;;
esac

BEL="$ROOT_DIR/belege/logind"
mkdir -p "$BEL"

run_case() {
    # run_case <name> <seconds> <extra-kernel-words> <key ...>
    local name=$1 sek=$2 extra=$3; shift 3
    SEKUNDEN=$sek VORLAUF=${VORLAUF_LAUF:-22} APPEND_EXTRA="$extra" \
        bash tools/anmeldung/shot.sh "$BUILD" "$BEL/$name.png" "$@" \
        > "$BEL/$name.lauf" 2>&1
    echo "$BEL/$name.txt"
}

ink_percent() {
    python3 - "$1" <<'PY' 2>/dev/null
import sys
from PIL import Image
im=Image.open(sys.argv[1]).convert('RGB'); w,h=im.size
p=im.load(); n=0; t=0
for y in range(0,h,4):
    for x in range(0,w,4):
        t+=1
        if p[x,y]!=(0,0,0): n+=1
print(int(100*n/t))
PY
}

section "3. the login comes BEFORE the desktop (P-002)"
T3=$(run_case anmelden 100 "anmeldung" \
     '#foto:anmeldeschirm' \
     s t a r t k e n n w o r t ret @45 '#foto:desktop' meta_l @60 '#foto:menu')
if [ -f "$T3" ]; then
    grep -qa 'sign-in before desktop' "$T3" \
        && ok "the kernel starts the login before the desktop" \
        || bad "'sign-in before desktop' is not in the report"
    grep -qaE 'glogin: ready' "$T3" \
        && ok "the login screen is ready" \
        || bad "'glogin: ready' missing"
    grep -qa 'glogin: angemeldet als justin' "$T3" \
        && ok "angemeldet als justin" \
        || bad "'glogin: angemeldet als justin' missing"
    if grep -qa 'glogin: uid=1000' "$T3"; then
        ok "the desktop runs under uid=1000 and NOT as root"
    else
        bad "'glogin: uid=1000' missing -- the desktop would still be root"
        info "$(grep -a 'glogin: uid' "$T3" | head -2)"
    fi
    # W-U (r1059): the launcher starts hidden at boot, BEFORE the sign-in. Its footer user must be read again when the menu is
    # shown (Super after the sign-in), or it keeps "root" all session (z11).
    grep -qa 'launcher: uid=1000 user=justin' "$T3" \
        && ok "start menu: the footer user is justin after the sign-in (not root)" \
        || bad "'launcher: uid=1000 user=justin' missing -- the start menu would keep 'root' (r1059)"
    grep -qaE 'glogin: desktop pid=[0-9]+' "$T3" \
        && ok "and it started the desktop" \
        || bad "'glogin: desktop pid=' missing"
    if [ -f "$BEL/anmelden-desktop.png" ]; then
        TI=$(ink_percent "$BEL/anmelden-desktop.png")
        if [ -n "$TI" ] && [ "$TI" -ge 20 ]; then
            ok "PICTURE: the desktop is there ($TI % ink)"
        else
            bad "PICTURE: the screen is almost empty (${TI:-?} % ink)"
        fi
    else
        bad "PICTURE: no picture of the desktop was produced"
    fi
else
    bad "section 3: no report was produced"
fi

# ==================================== 4. A WRONG PASSWORD
section "4. a wrong password is rejected -- and delayed"
T4=$(run_case falsch 55 "anmeldung" \
     f a l s c h ret @30 '#foto:abgewiesen')
if [ -f "$T4" ]; then
    grep -qa 'glogin: rejected' "$T4" \
        && ok "the wrong password was rejected" \
        || bad "'glogin: rejected' missing"
    W=$(sed -n 's/.*glogin: gewartet \([0-9]*\) ms.*/\1/p' "$T4" | head -1)
    if [ -n "$W" ] && [ "$W" -ge 1000 ]; then
        ok "and then waited at least 1000 ms (measured: $W ms)"
    else
        bad "the delay is missing or too short (measured: '${W:-none}')"
    fi
    if grep -qa 'glogin: angemeldet' "$T4"; then
        bad "after a wrong password the login happened anyway"
    else
        ok "NEGATIVE CONTROL: no 'angemeldet' -- no way around the login"
    fi
    if grep -qaE 'startkennwort|osumroot' "$T4"; then
        bad "a password is in the serial capture"
    else
        ok "NEGATIVE: no password in the serial capture"
    fi
else
    bad "section 4: no report was produced"
fi

section "5. LOGOUT ends the session and brings back the login screen"
#
if grep -qE "(^|[[:space:]])/etc/uitrace([[:space:]]|\$)" "$LISTING"; then
    AB="$ROOT_DIR/.logind-mess/logout.log"
    if python3 pruef/logout_check.py "$BUILD" "$ROOT_DIR/belege/logind" > "$AB" 2>&1; then
        while IFS= read -r z; do
            ok "${z#  OK    }"
        done < <(grep '^  OK    ' "$AB")
        grep -E '^LOGOUT:' "$AB" | sed 's/^/        /'
    else
        bad "pruef/logout_check.py failed"
        grep -E '^  (OK|FAIL)|^LOGOUT:' "$AB" | tail -16 | sed 's/^/        /'
    fi
else
    bad "the image has no /etc/uitrace -- build with UITRACE=1"
    info "without the switch the surface reports nothing (build.sh:792)"
fi

section "6. NEGATIVE CONTROL: without 'anmeldung' the old path is unchanged"
T6=$(run_case ohne 45 "" @10 '#foto:direkt')
if [ -f "$T6" ]; then
    grep -qa 'desk: WITHOUT sign-in' "$T6" \
        && ok "without the word the kernel reports the old path" \
        || bad "'desk: WITHOUT sign-in' missing"
    grep -qaE 'desk: start /bin/desktop' "$T6" \
        && ok "and starts the desktop directly" \
        || bad "'desk: start /bin/desktop' missing"
    if grep -qaE 'start /bin/glogin|glogin: ready' "$T6"; then
        bad "without the word glogin ran anyway"
        info "$(grep -aE 'start /bin/glogin|glogin: ready' "$T6" | head -2)"
    else
        ok "NEGATIVE: glogin was not started (no 'start /bin/glogin')"
    fi
    if grep -qa 'logout:' "$T6"; then
        bad "without a session a logout ran anyway"
    else
        ok "NEGATIVE: no logout without a session"
    fi
else
    bad "section 6: no report was produced"
fi

# ============================================ 7. THE SURFACE
section "7. the surface keeps the rule"
if bash tools/check-ui.sh > "$ROOT_DIR/.logind-mess/ui.log" 2>&1; then
    ok "check-ui.sh PASSED"
    info "$(grep -E '^ +[0-9]+ (files|programs|Dateien|Programme)' "$ROOT_DIR/.logind-mess/ui.log" | head -2 | tr '\n' ' ')"
else
    bad "check-ui.sh FAILED"
    tail -12 "$ROOT_DIR/.logind-mess/ui.log"
fi

echo
echo "LOGIND: $OK passed, $FAIL failed"
echo "Belege: $BEL"
[ "$FAIL" = 0 ]
