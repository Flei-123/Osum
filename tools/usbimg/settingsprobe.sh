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
timeout 1500 qemu-system-x86_64 "${KVM[@]}" -m 512 \
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

dlg_n() { grep -ac 'wm: trusted dialog up no=' "$S"; }
ans_n() { grep -ac 'wm: trusted dialog answer=1 ' "$S"; }
answer_dialog() {
    local i try a0
    for i in $(seq 1 40); do [ "$(dlg_n)" -gt "$1" ] && break; sleep 1; done
    [ "$(dlg_n)" -gt "$1" ] || return 1
    a0=$(ans_n)
    sleep 2
    for try in 1 2 3 4; do
        printf 'taste j\nwarte 3\n' > "$OUT/dj"
        drive "$OUT/dj"
        for i in 1 2 3 4 5 6; do [ "$(ans_n)" -gt "$a0" ] && return 0; sleep 1; done
    done
    return 1
}
pf_since() { tail -n +"$(( $1 + 1 ))" "$S" | sed -n 's/^settings: rect name=\(pf[a-z][a-z]\) .*/\1/p' | awk '!s[$0]++'; }
ask_and_answer() {
    local tag="$1" st
    st=$(status_of)
    echo "       $tag status after the first action: [$st]"
    case "$st" in
        *"click again"*|*"nochmal klicken"*|*"system confirmation"*|*"Bestaetigungsdialog"*) ok "$tag: the action asks for confirmation" ;;
        *) bad "$tag: the action did not ask (status [$st])" ;;
    esac
    if answer_dialog "$2"; then ok "$tag: the system dialog took the yes"; else bad "$tag: no trusted dialog answered"; fi
}
probe_text_field() {
    local field="$1" text="$2" tag="$3" d0
    d0=$(dlg_n)
    cat > "$OUT/d_$tag" <<EOT
klickauf srect$field
warte 1
tippe $text
foto $tag-typed
taste ret
warte 4
foto $tag-ask
EOT
    drive "$OUT/d_$tag"
    ask_and_answer "$tag" "$d0"
}

# 2. first click: the question, answered in the trusted dialog (the window's own second click is refused: use_dialog)
if [ -n "$PF" ]; then
D0=$(dlg_n)
cat > "$OUT/d2" <<EOT
klickauf srect$PF
warte 4
foto 03-ask
EOT
drive "$OUT/d2"
ask_and_answer share "$D0"
fi

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
    probe_text_field "${RFL[$((${#RFL[@]}-2))]}" "app:probe contacts.read" allow
    probe_text_field "${RFL[$((${#RFL[@]}-1))]}" "app:probe contacts.read" deny
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
    probe_text_field "${PVL[$((${#PVL[@]}-2))]}" "app:probe" entry
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
