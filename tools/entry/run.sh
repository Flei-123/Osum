#!/usr/bin/env bash
#
#     RIP 0x000000000010049C   CS 0x0008   ERR 0x0
#     RSP 0x000000004007F000   CR2 0x000000004007EFF8
#
#     000000000010046d <enter_user_task>:
#       10046d: mov  %rdi,%rcx
#       100470: mov  $0x202,%r11
#       100477: mov  %rsi,%rsp
#       ...
#       10049c: sysretq          <-- HIER
#

set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' steht da und darf nicht" || ok "$3"; }

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "EINSPRUNG: uebersprungen, qemu-system-x86_64 fehlt"
    exit 0
fi
bash vendor/firn/fetch-firnc.sh >/dev/null || {
    echo "vendor/firn/fetch-firnc.sh fehlgeschlagen"; exit 1; }

MONO=assets/osum-mono.ttf
SANS=assets/osum-sans.ttf
BASE="gfx wm wig desk wmhold wiglong nokbd nosched noproc nofs"

echo "== 1. Kern und Programme bauen =="
bash tools/build-kernel.sh "$TMPD/k0.mb" --stufe 0 > "$TMPD/b0.log" 2>&1 \
    && ok "Kern gebaut ($(stat -c%s "$TMPD/k0.mb") Oktette)" \
    || { bad "Der Kern baut nicht"; sed 's/^/        /' "$TMPD/b0.log" | head -12; }
[ -f "$TMPD/k0.mb" ] || { echo "EINSPRUNG: $pass bestanden, $((fail+1)) gescheitert"; exit 1; }

echo "== 2. DER BEWEIS AM ABBILD: das sysretq in enter_user_task =="
SYSRET_ADDR=$(objdump -d "$TMPD/k0.mb.elf" 2>/dev/null \
    | awk '/<enter_user_task>:/{f=1} f && /sysretq/{gsub(":","",$1); print "0x"$1; exit}')
if [ -n "$SYSRET_ADDR" ]; then
    ok "enter_user_task endet auf sysretq bei $SYSRET_ADDR (Justins RIP war 0x10049c)"
else
    bad "kein sysretq in enter_user_task gefunden"
fi

PROGS="desktop taskbar settings launcher dhcp explorer widgetdemo locate sh echo ls cat edit"
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s uebersetzt nicht"
rc=0
for p in $PROGS; do
    UPROF=""; UCRT="$TMPD/crt.o"
    grep -qa '^profile app' "kernel/user/$p.fi" && { UPROF=--profile=app; UCRT=""; }
    vendor/firn/bin/firnc $UPROF -c "kernel/user/$p.fi" -o "$TMPD/$p.o" > "$TMPD/e$p" 2>&1 || {
        bad "firnc uebersetzt $p.fi nicht"; sed 's/^/        /' "$TMPD/e$p" | head -6; rc=1; continue; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
        -o "$TMPD/$p.elf" $UCRT "$TMPD/$p.o" 2>"$TMPD/ld.err" \
        || { bad "ld scheitert an $p"; rc=1; continue; }
    strip --strip-all "$TMPD/$p.elf"
done
[ $rc = 0 ] && ok "$(echo $PROGS | wc -w) Programme gebaut"

python3 tools/k15/tree.py "$TMPD/baum" > "$TMPD/baum.log" 2>&1 \
    && ok "Verzeichnisbaum gebaut" || bad "tools/k15/tree.py fehlgeschlagen"

printf '# taskbar.conf\nedge=bottom\nheight=40\nwidth=100\nautohide=0\nontop=1\n' > "$TMPD/tb.conf"
ARGS=(build "$TMPD/disk.img" 32768 /lib/
    "/lib/mono.ttf=$MONO" "/lib/sans.ttf=$SANS" /bin/)
for p in $PROGS; do ARGS+=("/bin/$p=$TMPD/$p.elf"); done
ARGS+=("/bin/files@/bin/explorer")
ARGS+=(/etc/ "/etc/theme=$TMPD/baum/theme" "/etc/taskbar.conf=$TMPD/tb.conf")
while read -r z; do ARGS+=("$z"); done < <(python3 tools/k15/bundle.py assets/apps "$TMPD/buendel" nur="$PROGS")
while read -r z; do ARGS+=("$z"); done < "$TMPD/baum/liste"
if python3 tools/osum/mkfs.py "${ARGS[@]}" > "$TMPD/mkfs.txt" 2>&1; then
    ok "Abbild gebaut"
else
    bad "mkfs.py fehlgeschlagen"
    sed 's/^/        /' "$TMPD/mkfs.txt" | head -5
    echo
    echo "EINSPRUNG: $pass bestanden, $fail gescheitert (ohne Abbild abgebrochen)"
    exit 1
fi

lauf() { # name extra
    local name=$1 extra=$2
    local out="$TMPD/$name.txt"
    rm -f "$out"
    cp -f "$TMPD/disk.img" "$TMPD/live-$name.img"
    timeout 240 $QEMU_X86 -kernel "$TMPD/k0.mb" -m 256 \
        -append "$BASE $extra" -serial "file:$out" -display none -no-reboot \
        -vga std \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/$name.qemu" 2>&1 &
    local pid=$! i=0
    while [ $i -lt 1400 ]; do
        grep -qaE '^wm: hold' "$out" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1; i=$((i+1))
    done
    sleep 1
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
}

echo "== 3. Der Regellauf: der Schreibtisch startet =="
lauf regel ""
has "$TMPD/regel.txt" "wm: hold" "Regellauf: der Fensterserver kommt bis 'wm: hold'"
hasnot "$TMPD/regel.txt" "elf: entry abgelehnt" "Regellauf: kein Einsprung wird abgelehnt"
hasnot "$TMPD/regel.txt" "*** EXCEPTION" "Regellauf: keine Ausnahme"

echo "== 4. MIT KAPUTTEM EINSPRUNG -- JUSTINS FALL =="
lauf knall "einsprung"
has "$TMPD/knall.txt" "elf: entry abgelehnt" "der kaputte Einsprung wird abgelehnt, und zwar laut"
has "$TMPD/knall.txt" "DEAD000000000000" "und die abgelehnte Anschrift steht dabei"
hasnot "$TMPD/knall.txt" "*** EXCEPTION" "KEINE Ausnahme -- die Maschine lebt (vor dieser Runde: #GP am sysretq)"
hasnot "$TMPD/knall.txt" "#GP" "kein #GP"
has "$TMPD/knall.txt" "wm: hold" "und der Fensterserver laeuft weiter bis 'wm: hold'"

n=$(grep -ac 'elf: entry abgelehnt' "$TMPD/knall.txt" 2>/dev/null || echo 0)
if [ "${n:-0}" -ge 1 ]; then
    ok "abgelehnte Einspruenge: $n"
else
    bad "kein einziger Einsprung abgelehnt -- der Schalter greift nicht"
fi

echo
echo "EINSPRUNG: $pass bestanden, $fail gescheitert"
[ "$fail" = 0 ]
