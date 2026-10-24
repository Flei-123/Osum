#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/usbimg/settingsprobe.sh -- CLICK PROBE of a package page in Settings (r149), on the real USB image.
#
#   /root/jarvis/bin/heavy bash tools/usbimg/settingsprobe.sh [workdir]
#
# Builds the stick image (UITRACE=1: the windows report their rectangles), boots it, opens Settings
# from the start menu, clicks the sidebar entry of the package page "Activity"
# (/apps/social.prog/SETTINGS, rect `ptaba`), then clicks the first control of the page (the switch
# "Share my activity") TWICE: the first click must ask for confirmation (the action is critical),
# the second one confirms. Every step is read from the serial line (`settings: stand ... status=[..]`)
# and photographed. The work directory is removed at the end when it was not given.
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d /tmp/spprobe-XXXX); trap 'rm -rf "$OUT"' EXIT; fi
mkdir -p "$OUT"
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  OK    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "SETTINGSPROBE: skipped, qemu missing"; exit 0; }
KVM=()
[ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)

UITRACE=1 bash tools/usbimg/build.sh "$OUT/bau" > "$OUT/build.txt" 2>&1 \
    && ok "image builds (uitrace on)" || { bad "image does not build"; tail -5 "$OUT/build.txt"; echo "SETTINGSPROBE: $pass passed, $fail failed"; exit 1; }
python3 tools/osum/mkfs.py list "$OUT/bau/root.img" > "$OUT/files.txt" 2>/dev/null
grep -q '/apps/social.prog/SETTINGS' "$OUT/files.txt" \
    && ok "/apps/social.prog/SETTINGS is on the image" || bad "/apps/social.prog/SETTINGS is missing on the image"

S="$OUT/serial.txt"; SOCK="$OUT/mon.sock"
: > "$S"
timeout 400 qemu-system-x86_64 "${KVM[@]}" -m 512 \
    -kernel "$OUT/bau/osum.mb" -initrd "$OUT/bau/root.img" \
    -append "modfs osum vfs gfx wm wig desk wmhold wighalt=300 nokbd nosched fbres=1920x1200 lang=en" \
    -serial "file:$S" -display none -no-reboot -vga std \
    -monitor "unix:$SOCK,server,nowait" > "$OUT/qemu.log" 2>&1 &
QPID=$!
i=0
while [ $i -lt 800 ]; do
    grep -qaE '^wm: hold' "$S" 2>/dev/null && break
    kill -0 "$QPID" 2>/dev/null || break
    sleep 0.3; i=$((i+1))
done
grep -qaE '^wm: hold' "$S" && ok "desktop is up (wm: hold)" || { bad "desktop never came up"; kill "$QPID" 2>/dev/null; echo "SETTINGSPROBE: $pass passed, $fail failed"; exit 1; }

drive() { python3 -u tools/design/drive.py "$SOCK" "$S" "$OUT" "$1" >> "$OUT/drive.log" 2>&1; }
status_of() { grep -a 'settings: stand' "$S" | tail -1 | sed -n 's/.* pkg=\[\(.*\)\].*/\1/p'; }

# 1. open Settings, click the package tab
cat > "$OUT/d1" <<'E'
warte 6
klickauf start
warteauf launcher: tile || 30
warte 2
foto 00-start
klickauf start_Settings
warteauf settings: ready || 60
warte 4
foto 01-settings
taste f12
warte 3
klickauf cap_max
warte 5
foto 01b-maximized
klickauf srectptaba
warte 4
foto 02-activity
E
drive "$OUT/d1"
grep -aq 'settings: rect name=ptaba ' "$S" && ok "sidebar entry of the package page is reported (ptaba)" || bad "no rect ptaba reported"
for t in ptabb ptabc; do
    grep -aq "settings: rect name=$t " "$S" && ok "sidebar entry $t is reported (App rights / Privacy)" || bad "no rect $t reported"
done
grep -aq 'settings: rect name=ptabd ' "$S" && bad "a fourth package tab appeared (ptabd)" || ok "exactly three package tabs on this image"
PF=$(grep -a 'settings: rect name=pf' "$S" | tail -n 20 | sed -n 's/.*name=\(pf[a-z][a-z]\) .*/\1/p' | awk '!s[$0]++' | head -1)
[ -n "$PF" ] && ok "page controls are reported (first: $PF)" || bad "no control of the page reported (pf..)"
n0=$(grep -ac 'settings: stand' "$S")

# 2. first click: the question
if [ -n "$PF" ]; then
cat > "$OUT/d2" <<E
klickauf srect$PF
warte 4
foto 03-ask
E
drive "$OUT/d2"
st1=$(status_of)
echo "       status after click 1: [$st1]"
case "$st1" in
    *"click again"*|*"nochmal klicken"*) ok "click 1 asks for confirmation" ;;
    *) bad "click 1 did not ask (status [$st1])" ;;
esac
# 3. second click: confirm
cat > "$OUT/d3" <<E
klickauf srect$PF
warte 4
foto 04-confirmed
E
drive "$OUT/d3"
st2=$(status_of)
echo "       status after click 2: [$st2]"
case "$st2" in
    *"Done."*|*"Erledigt"*) ok "click 2 confirms and the action runs" ;;
    *) bad "click 2 did not end in Done (status [$st2])" ;;
esac
fi
pf_since() { tail -n +"$(( $1 + 1 ))" "$S" | sed -n 's/^settings: rect name=\(pf[a-z][a-z]\) .*/\1/p' | awk '!s[$0]++'; }
probe_text_field() {
    local tab="$1" field="$2" text="$3" tag="$4"
    cat > "$OUT/d_$tag" <<E
klickauf srect$field
warte 1
tippe $text
taste ret
warte 4
foto $tag-ask
E
    drive "$OUT/d_$tag"
    local a; a=$(status_of)
    echo "       $tag status after Enter 1: [$a]"
    case "$a" in
        *"click again"*|*"nochmal klicken"*|*"Enter again"*|*"Enter nochmal"*) ok "$tag: Enter 1 asks for confirmation (critical action)" ;;
        *) bad "$tag: Enter 1 did not ask (status [$a])" ;;
    esac
    cat > "$OUT/d_${tag}2" <<E
taste ret
warte 4
foto $tag-done
E
    drive "$OUT/d_${tag}2"
    local b; b=$(status_of)
    echo "       $tag status after Enter 2: [$b]"
    case "$b" in
        *"Done."*|*"Erledigt"*) ok "$tag: Enter 2 confirms and the action runs" ;;
        *) bad "$tag: Enter 2 did not end in Done (status [$b])" ;;
    esac
}

# 4. page App rights (ptabb) and page Privacy (ptabc)
off=$(wc -l < "$S")
cat > "$OUT/d4" <<'E'
klickauf srectptabb
warte 4
foto 05-rights
E
drive "$OUT/d4"
RF=$(pf_since "$off" | tr '\n' ' ')
echo "       rights page controls: [$RF]"
[ -n "$RF" ] && ok "App rights: the page controls are reported" || bad "App rights: no control reported (pf..)"
RFL=($RF)
if [ "${#RFL[@]}" -ge 2 ]; then
    probe_text_field ptabb "${RFL[$((${#RFL[@]}-2))]}" "app:probe contacts.read" allow
    probe_text_field ptabb "${RFL[$((${#RFL[@]}-1))]}" "app:probe contacts.read" deny
fi
off=$(wc -l < "$S")
cat > "$OUT/d5" <<'E'
klickauf srectptabc
warte 4
foto 06-privacy
E
drive "$OUT/d5"
PV=$(pf_since "$off" | tr '\n' ' ')
echo "       privacy page controls: [$PV]"
[ -n "$PV" ] && ok "Privacy: the page controls are reported" || bad "Privacy: no control reported (pf..)"
PVL=($PV)
if [ "${#PVL[@]}" -ge 2 ]; then
    probe_text_field ptabc "${PVL[$((${#PVL[@]}-2))]}" "app:probe" entry
fi
if [ "$fail" != 0 ]; then
    echo "--- diagnosis: serial (settings/desk/wm lines) ---"; grep -aE '^(settings|desk|wm): ' "$S" | head -30 | cut -c1-160
    echo "--- diagnosis: launcher lines ---"; grep -aE '^launcher: (geom|tile)' "$S" | head -n 12 | cut -c1-160
    echo "--- diagnosis: drive.log ---"; tail -n 25 "$OUT/drive.log" 2>/dev/null | cut -c1-160
fi
c=$(grep -acE 'ABSTURZ|EXCEPTION|PANIC' "$S"; true)
[ "$c" = 0 ] && ok "no crash lines" || bad "crash lines: $c"
kill "$QPID" 2>/dev/null; wait "$QPID" 2>/dev/null
echo "SETTINGSPROBE: $pass passed, $fail failed"
[ "$fail" = 0 ]
