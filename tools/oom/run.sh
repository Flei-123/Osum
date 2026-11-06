#!/usr/bin/env bash
#
# Aufruf:  bash tools/oom/run.sh [--shots <verzeichnis>]
set -u

. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
TMPD=$(mktemp -d)
. tools/lib/summary.sh; summary_begin OOM
trap 'summary_guard; rm -rf "$TMPD"; summary_exit_status || exit 1' EXIT
trap 'exit 1' HUP INT TERM

SHOTS="docs/shots/oom"
while [ $# -gt 0 ]; do
    case "$1" in
        --shots) SHOTS=$2; shift 2 ;;
        *) echo "unbekannte Option: $1" >&2; exit 1 ;;
    esac
done
mkdir -p "$SHOTS"

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() { local name=$1 wert=$2 op=$3 want=$4
    if [ -z "$wert" ]; then bad "$name: no number found (wanted $op $want)"; return; fi
    if [ "$wert" -"$op" "$want" ] 2>/dev/null; then ok "$name: $wert"
    else bad "$name: $wert, wollte $op $want"; fi
}
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' steht da und sollte nicht" || ok "$3"; }

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    summary_note "skipped, qemu-system-x86_64 is not there"
    exit 0
fi
bash vendor/firn/fetch-firnc.sh >/dev/null || {
    echo "vendor/firn/fetch-firnc.sh fehlgeschlagen"; exit 1; }

MONO=assets/osum-mono.ttf
SANS=assets/osum-sans.ttf

echo "== 1. der Kern baut =="
bash tools/build-kernel.sh "$TMPD/k.mb" > "$TMPD/b.log" 2>&1 \
    && ok "Kern gebaut ($(stat -c%s "$TMPD/k.mb") Oktette)" \
    || { bad "the kernel does not build"; sed 's/^/        /' "$TMPD/b.log" | head -12
         summary_emit "$pass" "$fail" 0; exit 1; }

run() { # name ram worte
    local name=$1 ram=$2 worte=$3
    timeout 300 $QEMU_X86 -kernel "$TMPD/k.mb" -m "$ram" \
        -append "$worte nokbd nofs nosched" \
        -serial "file:$TMPD/$name.raw" -display none -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    local rc=$?
    tr -d '\000' < "$TMPD/$name.raw" > "$TMPD/$name.txt"
    return $rc
}
zahl() { grep -a -m1 "^$2" "$1" | sed "s/^$2//" | grep -oaE '[0-9]+' | head -1; }

echo
echo "== 2. a hog WITHOUT selection (nooom): an honest refusal instead of a freeze =="
run eins 128 "memhog nooom"; RC=$?
F="$TMPD/eins.txt"
[ "$RC" -eq 21 ] && ok "the kernel ended itself (QEMU code 21)" \
    || bad "QEMU code $RC, expected 21 -- this looks like a freeze"
has "$F" 'kernel: done' "der Kern erreicht sein Ende"
has "$F" 'speicherdruck: lebt=1' "das System lebt nach dem Notfall"
has "$F" 'hog: fail=' "der Fresser bekam eine ehrliche Absage"
has "$F" 'hog: ende' "und hat sie ueberlebt, statt zu haengen"
num "nooom: niemand wurde beendet" "$(zahl "$F" 'speicherdruck: kills=')" eq 0

BEFORE=$(zahl "$F" 'speicherdruck: frei=')
AFTER=$(zahl "$F" 'speicherdruck: nach=')
if [ -n "$BEFORE" ] && [ "$BEFORE" = "$AFTER" ]; then
    ok "every frame is back: $BEFORE before, $AFTER after"
else
    bad "frames lost: $BEFORE before, $AFTER after"
fi

echo
echo "== 3. the reserve takes hold, and the selection hits =="
run ohne 128 "memhog nooom noreserve"
G="$TMPD/ohne.txt"
num "Gegenprobe noreserve: die Reserve ist leer" \
    "$(zahl "$G" 'speicherdruck: res=')" eq 0
WITH=$(grep -a -m1 '^hog: fail=' "$F" | grep -oaE '[0-9]+')
WITHOUT=$(grep -a -m1 '^hog: fail=' "$G" | grep -oaE '[0-9]+')
if [ -n "$WITH" ] && [ -n "$WITHOUT" ] && [ "$WITHOUT" -gt "$WITH" ]; then
    ok "without the reserve it keeps eating: $WITHOUT instead of $WITH KiB"
else
    bad "the reserve makes no difference: $WITH with, $WITHOUT without"
fi

run oom 128 memhog; RC=$?
O="$TMPD/oom.txt"
[ "$RC" -eq 21 ] && ok "with selection: the kernel ends itself (21)" \
    || bad "with selection: QEMU code $RC, expected 21"
RES=$(zahl "$O" 'speicherdruck: res=')
HITS=$(zahl "$O" 'speicherdruck: hits=')
num "die Reserve steht" "$RES" ge 64
num "sie hat wirklich abgewiesen (hits)" "$HITS" ge 1
has "$O" 'oom: kill ' "der Kern sagt, wen es getroffen hat"
num "genau ein Prozess beendet" "$(zahl "$O" 'speicherdruck: kills=')" eq 1
num "vorher synchronisiert" "$(zahl "$O" 'speicherdruck: syncs=')" ge 1
has "$O" 'SIGKIL -- killed' "das Opfer stirbt am gewoehnlichen SIGKILL"
num "und sein Code ist 137 (128 + 9)" "$(zahl "$O" 'speicherdruck: code=')" eq 137
hasnot "$O" 'hog: ende' "der Getroffene rechnet NICHT weiter"
BEFORE=$(zahl "$O" 'speicherdruck: frei=')
AFTER=$(zahl "$O" 'speicherdruck: nach=')
[ -n "$BEFORE" ] && [ "$BEFORE" = "$AFTER" ] \
    && ok "even after the kill every frame is back: $BEFORE" \
    || bad "frames are missing after the kill: $BEFORE before, $AFTER after"

echo
echo "== 4. die harten Faelle =="
# Mehrere Fresser gleichzeitig.
run drei 128 memhogn
D="$TMPD/drei.txt"
has "$D" 'speicherdruck: lebt=1' "drei Fresser gleichzeitig: das System lebt"
num "drei Fresser: mindestens einer beendet" \
    "$(zahl "$D" 'speicherdruck: kills=')" ge 1
BEFORE3=$(zahl "$D" 'speicherdruck: frei=')
AFTER3=$(zahl "$D" 'speicherdruck: nach=')
if [ "$BEFORE3" = "$AFTER3" ]; then
    ok "three hogs: every frame is back ($BEFORE3)"
else
    bad "three hogs: frames lost -- $BEFORE3 before, $AFTER3 after"
fi
has "$D" 'kernel: done' "der Kern arbeitet nach dem Notfall weiter"

# Ganz wenig Speicher.
run klein 64 memhogn
K="$TMPD/klein.txt"
has "$K" 'speicherdruck: lebt=1' "64 MiB, drei Fresser: das System lebt"
has "$K" 'kernel: done' "64 MiB: der Kern erreicht sein Ende"

if [ -f "$TMPD/hw.img" ] || bash tools/mkfsfi/mkfs.sh build "$TMPD/hw.img" 4096 \
        > "$TMPD/hwmkfs.txt" 2>&1; then
    timeout 300 $QEMU_X86 -kernel "$TMPD/k.mb" -m 128 \
        -append "hogwrite nokbd nosched" \
        -serial "file:$TMPD/datei.raw" -display none -no-reboot \
        -drive "file=$TMPD/hw.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -d '\000' < "$TMPD/datei.raw" > "$TMPD/datei.txt"
    W="$TMPD/datei.txt"
    has "$W" 'hogwrite: start' "der Fresser mit offener Datei lief"
    has "$W" 'speicherdruck: lebt=1' "Fresser mit offener Datei: das System lebt"
    has "$W" 'kernel: done' "der Kern erreicht sein Ende"
    if python3 - "$TMPD/hw.img" <<'PY'
import sys
d = open(sys.argv[1], 'rb').read()
sys.exit(0 if b'A' * 64 in d else 1)
PY
    then
        ok "the file is complete and intact afterwards (64 times 'A' im Abbild)"
    else
        if grep -qa 'hogwrite: wrote=64' "$W"; then
            bad "the file was written but is not intact in the image"
        else
            ok "the hog did not get as far as writing -- nothing to lose"
        fi
    fi
else
    bad "the image for the write case could not be built"
fi

echo
echo "== 5. THE ACCEPTANCE: desktop, hogs, and who survives =="
#
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null \
    || bad "crt.s cannot be assembled"
PROGS="desktop taskbar launcher sh echo ls cat"
BUILT=1
for p in $PROGS; do
    UPROF=""; UCRT="$TMPD/crt.o"
    grep -qa '^profile app' "kernel/user/$p.fi" && { UPROF=--profile=app; UCRT=""; }
    vendor/firn/bin/firnc $UPROF -c "kernel/user/$p.fi" -o "$TMPD/$p.o" \
        > "$TMPD/e$p" 2>&1 || {
        bad "firnc uebersetzt $p.fi nicht"; sed 's/^/        /' "$TMPD/e$p" | head -5
        BUILT=0; continue; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
        -o "$TMPD/$p.elf" $UCRT "$TMPD/$p.o" 2>"$TMPD/ld.err" || {
        bad "ld scheitert an $p"; BUILT=0; continue; }
    strip --strip-all "$TMPD/$p.elf"
done

if [ "$BUILT" = 1 ]; then
    ok "the desktop programs are built"
    python3 tools/k15/tree.py "$TMPD/baum" > "$TMPD/baum.log" 2>&1 \
        && ok "the directory tree is ready" || bad "tools/k15/tree.py scheiterte"
    printf 'unten\n28\n0\n0\n1\n' > "$TMPD/tb.conf"

    ARGS=(build "$TMPD/disk.img" 32768 /lib/
        "/lib/mono.ttf=$MONO" "/lib/sans.ttf=$SANS" /bin/)
    for p in $PROGS; do ARGS+=("/bin/$p=$TMPD/$p.elf"); done
    ARGS+=(/etc/ "/etc/theme=$TMPD/baum/theme" "/etc/taskbar.conf=$TMPD/tb.conf")
    while read -r z; do ARGS+=("$z"); done \
        < <(python3 tools/k15/bundle.py assets/apps "$TMPD/buendel" nur="$PROGS")
    while read -r z; do ARGS+=("$z"); done < "$TMPD/baum/liste"
    bash tools/mkfsfi/mkfs.sh "${ARGS[@]}" > "$TMPD/mkfs.txt" 2>&1 \
        && ok "the image is built" \
        || { bad "mkfs.py scheiterte"; sed 's/^/        /' "$TMPD/mkfs.txt" | head -5; }

    if [ -f "$TMPD/disk.img" ]; then
        cp -f "$TMPD/disk.img" "$TMPD/live.img"
        SOCK="$TMPD/mon.sock"; rm -f "$SOCK"
        timeout 300 $QEMU_X86 -kernel "$TMPD/k.mb" -m 256 \
            -append "gfx wm wig desk wmhold wiglong memhogn nokbd nosched noproc nofs" \
            -serial "file:$TMPD/desk.raw" -display none -no-reboot \
            -vga std -monitor "unix:$SOCK,server,nowait" \
            -drive "file=$TMPD/live.img,format=raw,if=ide,index=0" \
            -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
            > "$TMPD/desk.qemu" 2>&1 &
        QPID=$!
        i=0
        while [ $i -lt 1600 ]; do
            grep -qaE '^wm: hold' "$TMPD/desk.raw" 2>/dev/null && break
            kill -0 "$QPID" 2>/dev/null || break
            sleep 0.15; i=$((i + 1))
        done
        python3 tools/gfx/screenshot.py "$SOCK" "$SHOTS/oom-desktop.ppm" 25 \
            > "$TMPD/shot.log" 2>&1
        wait "$QPID"; DRC=$?
        rm -f "$SOCK"
        tr -d '\000' < "$TMPD/desk.raw" > "$TMPD/desk.txt"
        S="$TMPD/desk.txt"

        has "$S" 'desk: start /bin/desktop' "der Schreibtisch ist gestartet"
        has "$S" 'desk: start /bin/taskbar' "die Taskleiste ist gestartet"
        LEER=$(grep -aoE 'oom: kill pid=[0-9]+ +pages=[0-9]+ +frei=[0-9]+' "$S" \
            | head -1 | grep -oE '[0-9]+$')
        num "der Fresser hat den Speicher leergeraeumt (frei bei der Auswahl, hoechstens die Reserve)" \
            "$LEER" le 512
        has "$S" 'oom: kill ' "eine Meldung sagt, was passiert ist"

        GUI=$(grep -a '^desk: start ' "$S" | grep -oaE 'pid=[0-9]+' | cut -d= -f2 | sort -u)
        OPFER=$(grep -a '^oom: kill ' "$S" | grep -oaE 'pid=[0-9]+' | cut -d= -f2 | sort -u)
        if [ -z "$OPFER" ]; then
            bad "the selection killed nobody -- the emergency stayed unhandled"
        else
            TREFFER=""
            for o in $OPFER; do
                for g in $GUI; do
                    [ "$o" = "$g" ] && TREFFER="$TREFFER $o"
                done
            done
            if [ -z "$TREFFER" ]; then
                ok "only the hogs were hit ($(echo $OPFER | tr '\n' ' ')) -- die Oberflaeche ($(echo $GUI | tr '\n' ' ')) lebt"
            else
                bad "the selection hit the surface:$TREFFER"
            fi
        fi

        has "$S" 't=[desktop.title]' "das Fenster des Schreibtischs steht noch"
        has "$S" 't=[Taskbar]' "das Fenster der Taskleiste steht noch"

        has "$S" 'wm: hold' "der Fensterserver dreht nach dem Notfall weiter"
        [ "$DRC" -eq 21 ] && ok "the run ends cleanly (QEMU code 21)" \
            || bad "QEMU-Code $DRC, erwartet 21"

        if [ -s "$SHOTS/oom-desktop.ppm" ]; then
            FARBEN=$(python3 - "$SHOTS/oom-desktop.ppm" <<'PY'
import sys
d=open(sys.argv[1],'rb').read()
i=2; felder=0
while felder<3 and i<len(d):
    while i<len(d) and d[i] in b' \t\r\n': i+=1
    if i<len(d) and d[i:i+1]==b'#':
        while i<len(d) and d[i] not in b'\r\n': i+=1
        continue
    while i<len(d) and d[i] not in b' \t\r\n': i+=1
    felder+=1
i+=1
px=d[i:]
print(len(set(px[k:k+3] for k in range(0,min(len(px),300000),3))))
PY
)
            num "das Bild hat mehr als eine Farbe (der Schreibtisch malt)" \
                "$FARBEN" ge 3
            if python3 -c "
from PIL import Image
Image.open('$SHOTS/oom-desktop.ppm').save('$SHOTS/oom-desktop.png', optimize=True)
" 2>/dev/null; then
                rm -f "$SHOTS/oom-desktop.ppm"
                ok "Bild: $SHOTS/oom-desktop.png"
            else
                ok "Image: $SHOTS/oom-desktop.ppm (PIL missing, no PNG)"
            fi
        else
            bad "no image was produced"
        fi
    fi
fi

echo
summary_emit "$pass" "$fail" 20 || exit 1
[ "$fail" -eq 0 ] || exit 1
