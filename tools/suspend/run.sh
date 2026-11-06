#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/../lib/brand-env.sh"
#
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL
ROOT=$(pwd)

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

hat() { # datei muster beschreibung
    if grep -aq "$2" "$1" 2>/dev/null; then ok "$3"; else bad "$3"; fi
}
hat_nicht() { # datei muster beschreibung
    if grep -aq "$2" "$1" 2>/dev/null; then bad "$3"; else ok "$3"; fi
}

echo "== 0. preconditions =="
command -v qemu-system-x86_64 >/dev/null 2>&1 || {
    echo "SUSPEND: uebersprungen, qemu-system-x86_64 fehlt"; exit 0; }
ok "qemu is present ($OSUM_QEMU_ACCEL)"
IASL=0
if command -v iasl >/dev/null 2>&1; then
    IASL=1; ok "iasl is present -- the control run of the pre-measurement is possible"
else
    echo "  NOTE: iasl is missing, the DSDT control run is skipped"
fi

# ---- 1. memory map
echo
echo "== 1. the memory map of kdata =="
if python3 tools/kernel/memmap.py kernel > "$TMPD/karte.txt" 2>&1; then
    ok "the map: $(tail -1 "$TMPD/karte.txt")"
else
    bad "tools/kernel/memmap.py meldet Kollisionen"
    sed 's/^/        /' "$TMPD/karte.txt" | head -10
fi
hat "$TMPD/karte.txt" "0 collisions" "no two ranges overlap"

v=$(grep -aE "^const SUSP_OFF: u64 = 0x[0-9A-Fa-f]+" kernel/lib/kstate.fi \
    | head -1 | grep -oE '0x[0-9A-Fa-f]+')
m=$(grep -aE "^const SUSP_MAX: u64 = 0x[0-9A-Fa-f]+" kernel/lib/kstate.fi \
    | head -1 | grep -oE '0x[0-9A-Fa-f]+')
if [ -n "$v" ] && [ "$((v))" -eq $((0x110000)) ]; then
    ok "SUSP_OFF = $v -- exactly the allocated start"
else
    bad "SUSP_OFF = ${v:-fehlt}, allocated was 0x110000"
fi
if [ -n "$v" ] && [ -n "$m" ] && [ "$((v + m))" -le $((0x113000)) ]; then
    ok "SUSP_OFF+SUSP_MAX = $(printf '0x%X' $((v + m))) stays within 0x113000"
else
    bad "the range extends beyond 0x113000 -- that is foreign territory"
fi

# ---- 2. build
echo
echo "== 2. the kernel builds =="
if bash tools/build-kernel.sh "$TMPD/k.elf" > "$TMPD/build.txt" 2>&1; then
    ok "the kernel builds ($(stat -c%s "$TMPD/k.elf") octets)"
else
    bad "the kernel does NOT build"
    grep -viE 'warning|^\s+\||^\s+=|note:' "$TMPD/build.txt" | tail -10 | sed 's/^/        /'
    echo "== SUSPEND: $pass passed, $fail failed =="
    exit 1
fi

lauf() { # name kommandozeile [zeitlimit]
    local name=$1 app=$2 t=${3:-300}
    rm -f "$TMPD/$name.img"
    qemu-img create -f raw "$TMPD/$name.img" 64M >/dev/null 2>&1
    timeout "$t" $QEMU_X86 -kernel "$TMPD/k.elf" -m 512 -append "$app" \
        -serial "file:$TMPD/$name.txt" -display none -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        -drive "file=$TMPD/$name.img,format=raw,if=ide,index=0" \
        > /dev/null 2>&1
    return 0
}

# ---- 3. premeasure
echo
echo "== 3. the pre-measurement: what the machine really offers =="
lauf mess "osum suspmess acpiev" 300
if grep -aq 'suspend: premeasure' "$TMPD/mess.txt"; then
    sed -n 's/^suspend: premeasure/        /p' "$TMPD/mess.txt" | head -3
    ok "the pre-measurement runs and reports"
else
    bad "the pre-measurement reported nothing"
fi
hat "$TMPD/mess.txt" 'why=ok' "the premeasure finds everything it needs"
hat_nicht "$TMPD/mess.txt" 'panic' "no exception in the measure run"

K_S3=$(sed -n 's/.* s3=\([0-9]*,[0-9]*\).*/\1/p' "$TMPD/mess.txt" | head -1)
K_S4=$(sed -n 's/.* s4=\([0-9]*,[0-9]*\).*/\1/p' "$TMPD/mess.txt" | head -1)
K_PM1A=$(sed -n 's/.* pm1a=\(0x[0-9a-fA-F]*\).*/\1/p' "$TMPD/mess.txt" | head -1)
[ -n "$K_S3" ] && ok "the kernel reads \\_S3 = $K_S3" \
                || bad "the kernel finds no \\_S3"
[ -n "$K_S4" ] && ok "the kernel reads \\_S4 = $K_S4" \
                || bad "the kernel finds no \\_S4"
[ -n "$K_PM1A" ] && ok "PM1a_CNT = $K_PM1A from the FADT" \
                  || bad "no PM1a_CNT"
hat "$TMPD/mess.txt" 'facs=0x[0-9a-f]*[1-9a-f]' "FACS present (room for the wake vector)"

if [ "$IASL" = 1 ]; then
    echo
    echo "== 3b. same DSDT, read by iasl instead of the kernel =="
    cat > "$TMPD/dump.py" <<'PY'
import socket, json, subprocess, time, os, sys
sock=sys.argv[1]; kern=sys.argv[2]; out=sys.argv[3]
if os.path.exists(sock): os.unlink(sock)
p=subprocess.Popen(['qemu-system-x86_64','-accel','tcg','-kernel',kern,
  '-m','512','-append','osum nopwr','-display','none','-no-reboot',
  '-qmp','unix:%s,server,nowait'%sock],
  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
for _ in range(200):
    if os.path.exists(sock): break
    time.sleep(0.1)
time.sleep(12)
try:
    s=socket.socket(socket.AF_UNIX); s.connect(sock)
    f=s.makefile('rw'); f.readline()
    def cmd(c):
        f.write(json.dumps(c)+'\n'); f.flush()
        while True:
            l=f.readline()
            if not l: return None
            r=json.loads(l)
            if 'return' in r or 'error' in r: return r
    cmd({"execute":"qmp_capabilities"})
    cmd({"execute":"pmemsave","arguments":
         {"val":0x1ff00000,"size":0x100000,"filename":out}})
    cmd({"execute":"quit"})
except Exception as e:
    print("dump fehlgeschlagen:", e)
try: p.wait(timeout=30)
except Exception: p.kill()
PY
    if python3 "$TMPD/dump.py" "$TMPD/qmp.sock" "$TMPD/k.elf" \
            "$TMPD/acpi.bin" > "$TMPD/dump.log" 2>&1 \
       && [ -s "$TMPD/acpi.bin" ]; then
        ok "a dump of the ACPI region exists ($(stat -c%s "$TMPD/acpi.bin") octets)"
        python3 - "$TMPD/acpi.bin" "$TMPD/dsdt.aml" <<'PY'
import sys
d=open(sys.argv[1],'rb').read()
i=d.find(b'DSDT')
if i < 0:
    sys.exit(1)
ln=int.from_bytes(d[i+4:i+8],'little')
open(sys.argv[2],'wb').write(d[i:i+ln])
PY
        if [ -s "$TMPD/dsdt.aml" ]; then
            ok "the DSDT is cut out ($(stat -c%s "$TMPD/dsdt.aml") octets)"
            ( cd "$TMPD" && iasl -d dsdt.aml >/dev/null 2>&1 )
            if [ -f "$TMPD/dsdt.dsl" ]; then
                paket() { # datei name -> "a,b"
                    local roh
                    roh=$(awk -v want="Name (_$2," '
                        index($0, want) > 0 {f=1; n=0; next}
                        f && /^[[:space:]]*\}/ {exit}
                        f {
                            gsub(/[ \t,]/,"");
                            if ($0=="") next;
                            if ($0=="One" || $0=="Zero" || $0 ~ /^0x[0-9A-Fa-f]+$/) {
                                n++;
                                printf "%s ", $0;
                                if (n==2) exit;
                            }
                        }' "$1")
                    local a b i=0 out=""
                    for w in $roh; do
                        case "$w" in
                            One)  v=1 ;;
                            Zero) v=0 ;;
                            0x*)  v=$((w)) ;;
                            *)    continue ;;
                        esac
                        i=$((i+1))
                        if [ $i -eq 1 ]; then out="$v"; else out="$out,$v"; fi
                    done
                    [ $i -ge 2 ] && printf '%s' "$out"
                }
                I_S3=$(paket "$TMPD/dsdt.dsl" S3)
                I_S4=$(paket "$TMPD/dsdt.dsl" S4)
                if [ -n "$I_S3" ] && [ "$I_S3" = "$K_S3" ]; then
                    ok "\\_S3: the kernel says $K_S3, iasl says $I_S3 -- gleich"
                else
                    bad "\\_S3: the kernel says '${K_S3:-nichts}', iasl says '${I_S3:-nichts}'"
                fi
                if [ -n "$I_S4" ] && [ "$I_S4" = "$K_S4" ]; then
                    ok "\\_S4: the kernel says $K_S4, iasl says $I_S4 -- gleich"
                else
                    bad "\\_S4: the kernel says '${K_S4:-nichts}', iasl says '${I_S4:-nichts}'"
                fi
            else
                bad "iasl did not disassemble the DSDT"
            fi
        else
            bad "the DSDT could not be cut out"
        fi
    else
        bad "the ACPI dump was not created (QMP/pmemsave)"
    fi
fi

echo
echo "== 4. two cycles, compared byte by byte =="
lauf zyk "osum suspend acpiev" 400
hat_nicht "$TMPD/zyk.txt" 'panic' "no exception in the cycle run"
hat "$TMPD/zyk.txt" 'suspend: == cycle 1' "cycle 1 runs"
hat "$TMPD/zyk.txt" 'suspend: == cycle 2' "cycle 2 runs -- it finds what the first hides"

SAME_N=$(grep -ac '^suspend: equal$' "$TMPD/zyk.txt")
UNGL=$(grep -ac 'suspend: UNEQUAL' "$TMPD/zyk.txt")
RGL=$(grep -ac 'suspend: frames equal' "$TMPD/zyk.txt")
RVER=$(grep -ac 'suspend: FRAMES LOST' "$TMPD/zyk.txt")
if [ "$SAME_N" -ge 2 ]; then
    ok "the state is identical after BOTH cycles ($SAME_N of 2)"
else
    bad "the state is identical in only $SAME_N of 2 cycles"
fi
if [ "$UNGL" -eq 0 ]; then
    ok "no cycle reports a changed state"
else
    bad "$UNGL cycle(s) report UNEQUAL"
    grep -a 'UNEQUAL' "$TMPD/zyk.txt" | sed 's/^/        /' | head -4
fi
if [ "$RGL" -ge 2 ] && [ "$RVER" -eq 0 ]; then
    ok "free before == free after, in both cycles ($RGL of 2)"
else
    bad "frames are lost (equal=$RGL lost=$RVER)"
    grep -a 'FRAMES LOST\|before\|after' "$TMPD/zyk.txt" | sed 's/^/        /' | head -6
fi

S1=$(grep -a 'suspend: saved' "$TMPD/zyk.txt" | sed -n '1s/.*sum=\(0x[0-9a-f]*\).*/\1/p')
S2=$(grep -a 'suspend: saved' "$TMPD/zyk.txt" | sed -n '2s/.*sum=\(0x[0-9a-f]*\).*/\1/p')
if [ -n "$S1" ] && [ -n "$S2" ] && [ "$S1" != "$S2" ]; then
    ok "the cycles write DIFFERENT images ($S1 / $S2)"
else
    bad "both cycles have the same sum (${S1:-?} / ${S2:-?}) -- the second measures the first"
fi

if grep -aq 'suspend: restored' "$TMPD/zyk.txt"; then
    SCHIEF=$(awk '/susp: eingespielt/{
        s="";v="";
        if (match($0,/sum=0x[0-9a-f]+/))  s=substr($0,RSTART+4,RLENGTH-4);
        if (match($0,/soll=0x[0-9a-f]+/)) v=substr($0,RSTART+5,RLENGTH-5);
        if (s!=v) c++} END{print c+0}' "$TMPD/zyk.txt")
    if [ "$SCHIEF" -eq 0 ]; then
        ok "computed and stored checksum match on every restore"
    else
        bad "$SCHIEF restore(s) with differing checksum"
    fi
else
    bad "nothing was ever restored"
fi

echo
echo "== 5. the control run: a corrupted image must NOT be accepted =="
hat "$TMPD/zyk.txt" 'suspend: == control broken' "the control run runs"
if grep -aq 'suspend: COLD START, clean' "$TMPD/zyk.txt"; then
    ok "the corrupted image leads to a clean cold start"
else
    bad "the corrupted image was NOT rejected -- garbage would have been restored"
fi
if grep -a 'COLD START' "$TMPD/zyk.txt" | grep -aq 'why=checksum wrong'; then
    ok "and for the right reason: the checksum"
else
    bad "rejected, but not because of the checksum"
    grep -a 'COLD START' "$TMPD/zyk.txt" | sed 's/^/        /' | head -2
fi

# ---- 6. surroundings
echo
echo "== 6. check-ui and the image =="
if bash tools/check-ui.sh > "$TMPD/ui.txt" 2>&1 \
   && grep -aq 'CHECK-UI PASSED' "$TMPD/ui.txt"; then
    ok "tools/check-ui.sh PASSED"
else
    bad "tools/check-ui.sh is NOT green any more"
    tail -6 "$TMPD/ui.txt" | sed 's/^/        /'
fi
mkdir -p "$TMPD/usb"
if bash tools/usbimg/build.sh "$TMPD/usb" > "$TMPD/usb.txt" 2>&1 \
   && [ -f "$TMPD/usb/${MARKE_DATEI}-usb.img" ]; then
    USZ=$(stat -c%s "$TMPD/usb/${MARKE_DATEI}-usb.img")
    if [ "$USZ" -gt $((4 * 1024 * 1024)) ]; then
        ok "tools/usbimg/build.sh builds the image ($USZ octets)"
    else
        bad "the image is only $USZ octets -- that is not a bootable stick"
    fi
else
    bad "tools/usbimg/build.sh baut NICHT"
    tail -8 "$TMPD/usb.txt" | sed 's/^/        /'
fi

zyklus() {
    local name=$1 extra=${2:-} t=${3:-400}
    rm -f "$TMPD/$name.img"
    qemu-img create -f raw "$TMPD/$name.img" 64M >/dev/null 2>&1
    timeout "$t" $QEMU_X86 -kernel "$TMPD/k.elf" -m 512 \
        -append "osum schlafarm $extra acpiev" \
        -serial "file:$TMPD/$name-a.txt" -display none -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        -drive "file=$TMPD/$name.img,format=raw,if=ide,index=0" \
        > /dev/null 2>&1
    # LAUF B -- DERSELBE Datentraeger, NEUER QEMU.
    timeout "$t" $QEMU_X86 -kernel "$TMPD/k.elf" -m 512 \
        -append "osum schlafpruef acpiev" \
        -serial "file:$TMPD/$name-b.txt" -display none -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        -drive "file=$TMPD/$name.img,format=raw,if=ide,index=0" \
        > /dev/null 2>&1
    return 0
}

echo
echo "== 7. the allocated space of round SLEEP =="
sv=$(grep -aE "^const SCHLAF_OFF: u64 = 0x[0-9A-Fa-f]+" kernel/lib/kstate.fi \
    | head -1 | grep -oE '0x[0-9A-Fa-f]+')
sm=$(grep -aE "^const SCHLAF_MAX: u64 = 0x[0-9A-Fa-f]+" kernel/lib/kstate.fi \
    | head -1 | grep -oE '0x[0-9A-Fa-f]+')
if [ -n "$sv" ] && [ "$((sv))" -eq $((0x121000)) ]; then
    ok "SCHLAF_OFF = $sv -- exactly the allocated start"
else
    bad "SCHLAF_OFF = ${sv:-fehlt}, allocated was 0x121000"
fi
if [ -n "$sv" ] && [ -n "$sm" ] && [ "$((sv + sm))" -le $((0x126000)) ]; then
    ok "SCHLAF_OFF+SCHLAF_MAX = $(printf '0x%X' $((sv + sm))) stays within 0x126000"
else
    bad "the range extends beyond 0x126000 -- that is foreign territory"
fi
ausser=$(grep -aE "^const M_(SCHLAF|SCHLAFARM|SCHLAFPRUEF|SCHLAFHW|SCHLAFKAPUTT|NOSCHLAF|SCHLAFMESS): u64 = [0-9]+" \
    kernel/lib/kstate.fi | grep -oE '= [0-9]+' | grep -oE '[0-9]+' \
    | awk '$1 < 1020 || $1 > 1029' | wc -l)
anz=$(grep -acE "^const M_(SCHLAF|SCHLAFARM|SCHLAFPRUEF|SCHLAFHW|SCHLAFKAPUTT|NOSCHLAF|SCHLAFMESS): u64 = [0-9]+" \
    kernel/lib/kstate.fi)
if [ "$ausser" -eq 0 ] && [ "$anz" -ge 7 ]; then
    ok "all $anz mode indices of the round lie in 1020..1029"
else
    bad "$ausser mode indexes lie outside 1020..1029 (of $anz)"
fi

echo
echo "== 8. THE REAL CYCLE ACROSS THE BOOT (QEMU off in between) =="
zyklus z1 "" 400
A="$TMPD/z1-a.txt"; B="$TMPD/z1-b.txt"
hat_nicht "$A" 'panic' "no exception in the save run"
hat_nicht "$B" 'panic' "no exception in the resume run"
hat "$A" 'sleep: image ready' "run A writes the image"
hat "$A" 'sleep: guest shutting down' "run A ENDS the guest -- the memory is really gone"

if grep -a 'sleep: start' "$B" | grep -aq 'image=1'; then
    ok "the boot detects the image BY ITSELF (start detection)"
else
    bad "the boot did not detect the image"
    grep -a 'sleep: start' "$B" | sed 's/^/        /' | head -2
fi
if grep -a 'sleep: start' "$B" | grep -aq 'why=ok'; then
    ok "and it is accepted: why=ok"
else
    bad "the image was discarded"
fi

hat "$B" 'sleep: equal' "the state is IDENTICAL after boot"
hat_nicht "$B" 'sleep: UNEQUAL' "no changed state"

HWA=$(grep -a 'sleep: saved' -m1 "$A" >/dev/null 2>&1; \
      grep -a 'sleep: start' "$B" | sed -n '1s/.* hw=\(0x[0-9a-f]*\).*/\1/p')
HWI=$(grep -a 'sleep: start' "$B" | sed -n '1s/.* hwimg=\(0x[0-9a-f]*\).*/\1/p')
if [ -n "$HWA" ] && [ "$HWA" = "$HWI" ] && [ "$HWA" != "0x0" ]; then
    ok "the hardware id is stable across the restart ($HWA)"
else
    bad "hardware id: now '${HWA:-?}', in the image '${HWI:-?}'"
fi

if grep -a 'sleep: saved' "$A" | grep -aq 'regs=1'; then
    ok "PUNKT 2: the register set (rsp/rbp/rbx/r12-15/rip/cr3) goes into the image"
else
    bad "PUNKT 2: no register set in the image"
fi
if grep -a 'sleep: saved' "$A" | grep -aq 'fpu=1'; then
    FSZ=$(grep -a 'sleep: saved' "$A" | sed -n '1s/.*fpusize=\([0-9]*\).*/\1/p')
    ok "PUNKT 3: the FPU/XSAVE area goes into the image ($FSZ octets)"
else
    bad "PUNKT 3: no FPU area in the image"
    grep -a 'fpuwhy' "$A" | sed 's/^/        /' | head -2
fi
if grep -a 'sleep: saved' "$A" | grep -aq 'devices=1'; then
    ok "PUNKT 5: timer/keyboard/graphics go into the image"
else
    bad "PUNKT 5: no device state in the image"
fi
if grep -a 'sleep: equal' "$B" | grep -aq 'regs=1 fpu=1 devices=1'; then
    ok "and all three are back after the boot"
else
    bad "after the boot one of the three is missing"
    grep -a 'sleep: equal' "$B" | sed 's/^/        /' | head -2
fi

FR=$(grep -a 'sleep: saved' "$A" | sed -n '1s/.*frames=\([0-9]*\).*/\1/p')
FB=$(grep -a 'sleep: start' "$B" | sed -n '1s/.* back=\([0-9]*\).*/\1/p')
if [ -n "$FR" ] && [ "$FR" -gt 0 ]; then
    ok "PUNKT 4: $FR frames of main memory go into the image (not just a pattern)"
else
    bad "PUNKT 4: 0 frames went into the image"
fi
if [ -n "$FR" ] && [ "$FR" = "$FB" ]; then
    ok "saved == restored frames ($FR == $FB)"
else
    bad "saved $FR, restored ${FB:-?} -- a frame was lost on the way"
fi

hat "$B" 'sleep: frames equal' "free before == free after (no lost frame)"
hat_nicht "$B" 'sleep: FRAMES LOST' "no message about lost frames"

echo
echo "== 9. THE PROMISE THAT CHECKS REGISTERS AND PAGE TABLES: KEEP COMPUTING =="
if grep -aq 'sleep: computed_on=1' "$B"; then
    R=$(grep -a 'sleep: compute' "$B" | sed -n '1s/.*s=\([0-9]*\) step=\([0-9]*\) want=\([0-9]*\).*/sum=\1 step=\2 want=\3/p')
    ok "the process keeps computing CORRECTLY after the boot ($R)"
else
    bad "the process computation did NOT survive the sleep"
    grep -a 'sleep: compute\|computed_on' "$B" | sed 's/^/        /' | head -3
fi
RS=$(grep -a 'sleep: compute' "$B" | sed -n '1s/.*s=\([0-9]*\) .*/\1/p')
if [ -n "$RS" ] && [ "$RS" -gt 0 ]; then
    ok "and the computation is not empty (summe=$RS)"
else
    bad "the computation is empty (summe=${RS:-?}) -- that checks nothing"
fi

echo
echo "== 10. TWO CYCLES IN A ROW, with DIFFERENT images =="
zyklus z2 "schlaf" 400
A2="$TMPD/z2-a.txt"; B2="$TMPD/z2-b.txt"
hat "$A2" 'sleep: == arm cycle2' "the second cycle carries a DIFFERENT state"
hat "$B2" 'sleep: equal' "the second cycle also comes back identical"
hat "$B2" 'sleep: computed_on=1' "the process keeps computing in the second cycle too"
hat "$B2" 'sleep: frames equal' "no lost frame in the second cycle either"
S1=$(grep -a 'sleep: saved' "$A" | sed -n '1s/.*sum=\(0x[0-9a-f]*\).*/\1/p')
S2=$(grep -a 'sleep: saved' "$A2" | sed -n '1s/.*sum=\(0x[0-9a-f]*\).*/\1/p')
if [ -n "$S1" ] && [ -n "$S2" ] && [ "$S1" != "$S2" ]; then
    ok "the two cycles write DIFFERENT images ($S1 / $S2)"
else
    bad "both cycles have the same sum (${S1:-?} / ${S2:-?}) -- the second measures the first"
fi
C1=$(grep -a 'sleep: equal' "$B" | sed -n '1s/.*cnt=\([0-9]*\).*/\1/p')
C2=$(grep -a 'sleep: equal' "$B2" | sed -n '1s/.*cnt=\([0-9]*\).*/\1/p')
if [ -n "$C1" ] && [ -n "$C2" ] && [ "$C1" != "$C2" ]; then
    ok "and the restored states differ (cnt $C1 / $C2)"
else
    bad "both cycles restore the same state (${C1:-?} / ${C2:-?})"
fi

echo
echo "== 11. THE CONTROL RUNS THAT MUST FAIL =="
zyklus gk "schlafkaputt" 400
GK="$TMPD/gk-b.txt"
if grep -a 'sleep: start' "$GK" | grep -aq 'image=0'; then
    ok "the corrupted image is REJECTED at boot"
else
    bad "the corrupted image was restored -- garbage in memory"
fi
if grep -a 'sleep: COLD START' "$GK" | grep -aq 'why=checksum wrong'; then
    ok "and for the RIGHT reason: the checksum"
else
    bad "rejected, but not because of the checksum"
    grep -a 'sleep: COLD START\|sleep: start' "$GK" | sed 's/^/        /' | head -2
fi
hat_nicht "$GK" 'panic' "no exception on cold start after the damage"

zyklus gh "schlafhw" 400
GH="$TMPD/gh-b.txt"
if grep -a 'sleep: start' "$GH" | grep -aq 'image=0'; then
    ok "an image with a FOREIGN hardware id is rejected"
else
    bad "the foreign image was restored"
fi
if grep -a 'sleep: COLD START' "$GH" | grep -aq 'why=hardware differs'; then
    ok "and for the RIGHT reason: the hardware id"
else
    bad "rejected, but not because of the hardware id"
    grep -a 'sleep: COLD START\|sleep: start' "$GH" | sed 's/^/        /' | head -2
fi
hat_nicht "$GH" 'panic' "no exception on cold start after foreign id"

rm -f "$TMPD/gn.img"
qemu-img create -f raw "$TMPD/gn.img" 64M >/dev/null 2>&1
timeout 400 $QEMU_X86 -kernel "$TMPD/k.elf" -m 512 \
    -append "osum schlafarm acpiev" -serial "file:$TMPD/gn-a.txt" \
    -display none -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    -drive "file=$TMPD/gn.img,format=raw,if=ide,index=0" > /dev/null 2>&1
timeout 400 $QEMU_X86 -kernel "$TMPD/k.elf" -m 512 \
    -append "osum schlafpruef noschlaf acpiev" \
    -serial "file:$TMPD/gn-b.txt" -display none -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    -drive "file=$TMPD/gn.img,format=raw,if=ide,index=0" > /dev/null 2>&1
if grep -a 'sleep: COLD START' "$TMPD/gn-b.txt" | grep -aq 'why=disabled'; then
    ok "with 'noschlaf' a valid image stays (deliberate cold start)"
else
    bad "'noschlaf' did not disable the start detection"
    grep -a 'sleep: start\|COLD START' "$TMPD/gn-b.txt" | sed 's/^/        /' | head -2
fi

echo
echo "== 12. ROUND AWAKE: do the processes keep running after the boot? =="
wzyklus() { # name extra-arm timeout
    local name=$1 extra=${2:-} t=${3:-400}
    rm -f "$TMPD/$name.img"
    qemu-img create -f raw "$TMPD/$name.img" 64M >/dev/null 2>&1
    timeout "$t" $QEMU_X86 -kernel "$TMPD/k.elf" -m 512 \
        -append "osum wacharm schlafarm $extra acpiev" \
        -serial "file:$TMPD/$name-a.txt" -display none -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        -drive "file=$TMPD/$name.img,format=raw,if=ide,index=0" \
        > /dev/null 2>&1
    timeout "$t" $QEMU_X86 -kernel "$TMPD/k.elf" -m 512 \
        -append "osum wachpruef schlafpruef acpiev" \
        -serial "file:$TMPD/$name-b.txt" -display none -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        -drive "file=$TMPD/$name.img,format=raw,if=ide,index=0" \
        > /dev/null 2>&1
    return 0
}
wzyklus wz1 "" 400
WA="$TMPD/wz1-a.txt"; WB="$TMPD/wz1-b.txt"
hat_nicht "$WA" 'panic' "no exception in the save run (wake)"
hat_nicht "$WB" 'panic' "no exception in the resume run (wake)"
hat_nicht "$WB" 'EXCEPTION' "no CPU exception in the resume run (wake)"

WN=$(grep -a 'wake: procs' "$WA" | sed -n '1s/.*n=\([0-9]*\).*/\1/p')
WPIDS=$(grep -a 'wake: procs' "$WA" | sed -n '1s/.*pids=\([0-9,]*\).*/\1/p')
if [ -n "$WN" ] && [ "$WN" -ge 3 ]; then
    ok "run A creates $WN processes, pids=$WPIDS"
else
    bad "Run A created fewer than three processes (n=${WN:-?})"
fi
WVERSCH=$(printf '%s' "$WPIDS" | tr ',' '\n' | sort -u | grep -c .)
if [ "${WVERSCH:-0}" -ge 3 ]; then
    ok "and their pids are DIFFERENT ($WVERSCH different)"
else
    bad "the pids are not different: $WPIDS"
fi

if grep -a 'wake: back' "$WB" | grep -aq 'why=ok'; then
    ok "the restart brings the tasks back (why=ok)"
else
    bad "the restart brought back no tasks"
    grep -a 'wake: back' "$WB" | sed 's/^/        /' | head -2
fi
WBACK=$(grep -a 'wake: back' "$WB" | sed -n '1s/.*tasks=\([0-9]*\).*/\1/p')
WKST=$(grep -a 'wake: back' "$WB" | sed -n '1s/.*kstack=\([0-9]*\).*/\1/p')
if [ -n "$WBACK" ] && [ "$WBACK" -ge 3 ]; then
    ok "PUNKT 1: $WBACK task entries are back in the table"
else
    bad "PUNKT 1: there came back ${WBACK:-0} tasks"
fi
KSF=$(grep -aoE '^const KSTACK_FRAMES: u64 = [0-9]+' kernel/sched/sched.fi | grep -oE '[0-9]+$')
KSF=$(( ${KSF:-0} + 1 ))
if [ -n "$WKST" ] && [ -n "$WBACK" ] && [ "$KSF" -gt 1 ] && [ "$WKST" -eq $((WBACK * KSF)) ]; then
    ok "PUNKT 1: $WKST kernel stack frames == $WBACK tasks * $KSF"
else
    bad "the kernel stack frames do not match: kstapel=${WKST:-?}, tasks=${WBACK:-?}"
fi

WLAUF=$(grep -a 'wake: resumed' "$WB" | sed -n '1s/.*ran=\([0-9]*\).*/\1/p')
if [ -n "$WLAUF" ] && [ "$WLAUF" -ge 3 ]; then
    ok "PUNKT 2: $WLAUF restarted processes were on the CPU (T_RUNS>0)"
else
    bad "PUNKT 2: no restarted process got onto the CPU (ran=${WLAUF:-0})"
fi

WVOR=$(grep -a 'wake: resume ' "$WB" | sed -n '1s/.*before=\([0-9]*\).*/\1/p')
WNACH=$(grep -a 'wake: resume ' "$WB" | sed -n '1s/.*after=\([0-9]*\).*/\1/p')
WSUM=$(grep -a 'wake: resume ' "$WB" | sed -n '1s/.*sum=\([0-9]*\).*/\1/p')
WSOLL=$(grep -a 'wake: resume ' "$WB" | sed -n '1s/.* want=\([0-9]*\).*/\1/p')
if [ -n "$WVOR" ] && [ "$WVOR" -gt 0 ]; then
    ok "the reference number comes from the IMAGE (before=$WVOR, not 0)"
else
    bad "before=${WVOR:-?} -- compared against 0 this promise measures nothing"
fi
if [ -n "$WVOR" ] && [ -n "$WNACH" ] && [ "$WNACH" -gt "$WVOR" ]; then
    ok "THE PROMISE: the counter RISES across the standby ($WVOR -> $WNACH)"
else
    bad "the counter did not rise: before=${WVOR:-?} after=${WNACH:-?}"
fi
if [ -n "$WSUM" ] && [ "$WSUM" = "$WSOLL" ] && [ "${WSUM:-0}" -gt 0 ]; then
    ok "and the cross-check matches: sum=$WSUM == n*(n+1)/2=$WSOLL"
else
    bad "the cross-check does NOT match: sum=${WSUM:-?} expected=${WSOLL:-?}"
fi
WWEITER=$(grep -a 'wake: resumed' "$WB" | sed -n '1s/.*resumed=\([0-9]*\).*/\1/p')
WALLE=$(grep -a 'wake: resumed' "$WB" | sed -n '1s/.*all=\([0-9]*\).*/\1/p')
if [ -n "$WWEITER" ] && [ "$WWEITER" -ge 3 ]; then
    ok "SEVERAL PROCESSES: $WWEITER demonstrably keep running (not just one)"
else
    bad "${WWEITER:-0} processes keep running -- at least three are required"
fi
if [ "${WALLE:-0}" = "1" ]; then
    ok "and they are ALL processes of this round, not just some"
else
    bad "not all restarted processes of this round keep computing"
fi

if grep -aq 'sleep: frames equal' "$WB"; then
    ok "no lost frame -- also with kernel stacks and page tables"
else
    bad "the frame accounting does not add up in the awake cycle"
    grep -a 'sleep: FRAMES LOST\|sleep: frames equal' "$WB" | sed 's/^/        /' | head -2
fi
WWACH=$(grep -a 'sleep: frames equal\|sleep: FRAMES LOST' "$WB" | sed -n '1s/.*wake=\([0-9]*\).*/\1/p')
if [ -n "$WWACH" ] && [ "$WWACH" -gt 0 ]; then
    ok "and the restart names its own $WWACH frames (instead of hiding them)"
else
    bad "the restart does not count its own frames"
fi

hat "$WB" 'sleep: equal' "the promise of the previous round holds: the state is identical"
hat "$WB" 'sleep: computed_on=1' "and its cross-check holds too"

echo
echo "== 13. two awake cycles with different states =="
wzyklus wz2 "wach schlaf" 400
W2B="$TMPD/wz2-b.txt"
hat_nicht "$W2B" 'panic' "no exception in the second cycle"
W2BEFORE=$(grep -a 'wake: resume ' "$W2B" | sed -n '1s/.*before=\([0-9]*\).*/\1/p')
W2AFTER=$(grep -a 'wake: resume ' "$W2B" | sed -n '1s/.*after=\([0-9]*\).*/\1/p')
W2SUM=$(grep -a 'wake: resume ' "$W2B" | sed -n '1s/.*sum=\([0-9]*\).*/\1/p')
W2SOLL=$(grep -a 'wake: resume ' "$W2B" | sed -n '1s/.* want=\([0-9]*\).*/\1/p')
if [ -n "$W2AFTER" ] && [ -n "$W2BEFORE" ] && [ "$W2AFTER" -gt "$W2BEFORE" ]; then
    ok "the counter rises in the second cycle too ($W2BEFORE -> $W2AFTER)"
else
    bad "the counter does not rise in the second cycle"
fi
if [ -n "$W2SUM" ] && [ "$W2SUM" = "$W2SOLL" ] && [ "${W2SUM:-0}" -gt 0 ]; then
    ok "and the cross-check matches there too ($W2SUM)"
else
    bad "the cross-check of the second cycle does not match"
fi
S1=$(grep -a 'sleep: start' "$WB"  | sed -n '1s/.*sum=\(0x[0-9a-f]*\).*/\1/p')
S2=$(grep -a 'sleep: start' "$W2B" | sed -n '1s/.*sum=\(0x[0-9a-f]*\).*/\1/p')
if [ -n "$S1" ] && [ -n "$S2" ] && [ "$S1" != "$S2" ]; then
    ok "the two cycles have DIFFERENT images ($S1 != $S2)"
else
    bad "both cycles have the same image ($S1 / $S2)"
fi

echo
echo "== 14. control: 'nowach' leaves the processes =="
rm -f "$TMPD/wn.img"
qemu-img create -f raw "$TMPD/wn.img" 64M >/dev/null 2>&1
timeout 400 $QEMU_X86 -kernel "$TMPD/k.elf" -m 512 \
    -append "osum wacharm schlafarm acpiev" \
    -serial "file:$TMPD/wn-a.txt" -display none -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    -drive "file=$TMPD/wn.img,format=raw,if=ide,index=0" > /dev/null 2>&1
timeout 400 $QEMU_X86 -kernel "$TMPD/k.elf" -m 512 \
    -append "osum wachpruef schlafpruef nowach acpiev" \
    -serial "file:$TMPD/wn-b.txt" -display none -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    -drive "file=$TMPD/wn.img,format=raw,if=ide,index=0" > /dev/null 2>&1
WNB="$TMPD/wn-b.txt"
if grep -a 'wake: back' "$WNB" | grep -aq 'why=disabled'; then
    ok "'nowach' switches off the task resume"
else
    bad "'nowach' did not disable the resume"
    grep -a 'wake: back' "$WNB" | sed 's/^/        /' | head -2
fi
if grep -a 'wake: back' "$WNB" | grep -aq 'tasks=0'; then
    ok "and NO task enters the run list"
else
    bad "trotz 'nowach' kamen tasks"
fi
if grep -a 'sleep: start' "$WNB" | grep -aq 'image=1'; then
    ok "the MEMORY still comes back (the promise of the previous round does not depend on it)"
else
    bad "'nowach' also prevented restoring the memory"
fi
hat_nicht "$WNB" 'panic' "no exception with 'nowach'"

echo
echo "== 15. the allocated space of round AWAKE =="
wv=$(grep -aE "^const WACH_OFF: u64 = 0x[0-9A-Fa-f]+" kernel/lib/kstate.fi \
    | head -1 | grep -oE '0x[0-9A-Fa-f]+')
wm=$(grep -aE "^const WACH_MAX: u64 = 0x[0-9A-Fa-f]+" kernel/lib/kstate.fi \
    | head -1 | grep -oE '0x[0-9A-Fa-f]+')
if [ -n "$wv" ] && [ "$((wv))" -eq $((0x127000)) ]; then
    ok "WACH_OFF = $wv -- exactly the allocated start"
else
    bad "WACH_OFF = ${wv:-fehlt}, allocated was 0x127000"
fi
if [ -n "$wv" ] && [ -n "$wm" ] && [ "$((wv + wm))" -le $((0x12C000)) ]; then
    ok "WACH_OFF+WACH_MAX = $(printf '0x%X' $((wv + wm))) stays within 0x12C000"
else
    bad "the range extends beyond 0x12C000 -- that is foreign territory"
fi
wausser=$(grep -aE "^const M_(WACH|WACHARM|WACHPRUEF|NOWACH|WACHMESS): u64 = [0-9]+" \
    kernel/lib/kstate.fi | grep -oE '= [0-9]+' | grep -oE '[0-9]+' \
    | awk '$1 < 1050 || $1 > 1059' | wc -l)
if [ "$wausser" -eq 0 ]; then
    ok "all mode indices of round AWAKE lie in 1050..1059"
else
    bad "$wausser mode index(es) of the WAKE round lie outside"
fi

echo
echo "== 16. FREEZE on 4 cores: CPU-bound tasks are stopped before the copy =="
fzrun() { # name extra-words
    local name=$1 extra=$2
    rm -f "$TMPD/$name.img"
    qemu-img create -f raw "$TMPD/$name.img" 64M >/dev/null 2>&1
    timeout 300 $QEMU_X86 -kernel "$TMPD/k.elf" -m 512 -smp 4 \
        -append "osum wacharm schlafarm wachburn smpfrueh $extra acpiev" \
        -serial "file:$TMPD/$name-a.txt" -display none -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        -drive "file=$TMPD/$name.img,format=raw,if=ide,index=0" > /dev/null 2>&1
    timeout 300 $QEMU_X86 -kernel "$TMPD/k.elf" -m 512 -smp 4 \
        -append "osum wachpruef schlafpruef wachburn smpfrueh $extra acpiev" \
        -serial "file:$TMPD/$name-b.txt" -display none -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        -drive "file=$TMPD/$name.img,format=raw,if=ide,index=0" > /dev/null 2>&1
}
fzfield() { grep -a '^wake: freeze' "$1" | sed -n "1s/.* $2=\([0-9]*\).*/\1/p"; }
fzrun fz1 ""
F1="$TMPD/fz1-a.txt"
hat_nicht "$F1" 'EXCEPTION' "no CPU exception in the freeze save run"
if [ "$(fzfield "$F1" cores)" = "4" ]; then ok "four cores online when the tasks are frozen"; else bad "cores=$(fzfield "$F1" cores), expected 4"; fi
if [ "${F1RUN:=$(fzfield "$F1" running)}" -ge 1 ] 2>/dev/null; then ok "$F1RUN marked tasks were running on other cores at the moment of marking"; else bad "no marked task was running on another core: the probe measures nothing (running=${F1RUN:-?})"; fi
if [ "$(fzfield "$F1" stray)" = "0" ] && [ "$(fzfield "$F1" timeout)" = "0" ]; then ok "freeze waited until every marked task left its core (stray=0)"; else bad "stray tasks after freeze: $(grep -a '^wake: freeze' "$F1" | head -1)"; fi
if [ "$(fzfield "$F1" marked)" -ge 8 ] 2>/dev/null && [ "$(fzfield "$F1" marked)" -le "$(fzfield "$F1" limit)" ] 2>/dev/null; then ok "marked=$(fzfield "$F1" marked) within the capacity limit=$(fzfield "$F1" limit)"; else bad "marking outside the capacity: $(grep -a '^wake: freeze' "$F1" | head -1)"; fi
hat "$F1" 'wake: image written=1' "the task image is written completely with burners (disk capacity respected)"
hat "$TMPD/fz1-b.txt" 'wake: back .*why=ok' "the frozen burners come back on restart"
FB=$(grep -a 'wake: burners' "$TMPD/fz1-b.txt" | sed -n '1s/.*found=\([0-9]*\).*/\1/p')
FR=$(grep -a 'wake: burners' "$TMPD/fz1-b.txt" | sed -n '1s/.*rising=\([0-9]*\).*/\1/p')
if [ -n "$FB" ] && [ "$FB" -ge 1 ] && [ "$FB" = "$FR" ]; then ok "all $FB restored burners keep computing"; else bad "burners found=${FB:-0} rising=${FR:-0}"; fi

fzrun fz2 "nofreezewait"
F2="$TMPD/fz2-a.txt"
if [ "$(fzfield "$F2" stray)" -ge 1 ] 2>/dev/null; then ok "control 'nofreezewait': stray=$(fzfield "$F2" stray) -- the check goes RED without the wait"; else bad "control 'nofreezewait' stays quiet, the stray check is blind: $(grep -a '^wake: freeze' "$F2" | head -1)"; fi

fzrun fz3 "freezetmo"
F3="$TMPD/fz3-a.txt"
if [ "$(fzfield "$F3" timeout)" = "1" ] && [ "$(fzfield "$F3" orphans)" = "0" ] && [ "$(fzfield "$F3" restored)" -ge 1 ] 2>/dev/null; then ok "timeout path: thaw restores $(fzfield "$F3" restored) tasks, no task left running without a core"; else bad "timeout path wrong: $(grep -a '^wake: freeze' "$F3" | head -1)"; fi
fzrun fz4 "freezetmo oldthaw"
F4="$TMPD/fz4-a.txt"
if [ "$(fzfield "$F4" orphans)" -ge 1 ] 2>/dev/null; then ok "control 'oldthaw': orphans=$(fzfield "$F4" orphans) -- the old restore strands tasks"; else bad "control 'oldthaw' shows no stranded task: $(grep -a '^wake: freeze' "$F4" | head -1)"; fi

echo
echo "== SUSPEND+SLEEP+WAKE: $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
