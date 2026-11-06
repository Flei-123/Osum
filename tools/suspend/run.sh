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

echo "== 0. die Vorbedingungen =="
command -v qemu-system-x86_64 >/dev/null 2>&1 || {
    echo "SUSPEND: uebersprungen, qemu-system-x86_64 fehlt"; exit 0; }
ok "qemu ist da ($OSUM_QEMU_ACCEL)"
IASL=0
if command -v iasl >/dev/null 2>&1; then
    IASL=1; ok "iasl is present -- the control run of the pre-measurement is possible"
else
    echo "  NOTE: iasl is missing, the DSDT control run is skipped"
fi

# ---------------------------------------------------- 1. die Speicherkarte
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
    ok "SUSP_OFF+SUSP_MAX = $(printf '0x%X' $((v + m))) bleibt in 0x113000"
else
    bad "the range extends beyond 0x113000 -- that is foreign territory"
fi

# ---------------------------------------------------- 2. bauen
echo
echo "== 2. der Kern baut =="
if bash tools/build-kernel.sh "$TMPD/k.elf" > "$TMPD/build.txt" 2>&1; then
    ok "der Kern baut ($(stat -c%s "$TMPD/k.elf") octets)"
else
    bad "the kernel does NOT build"
    grep -viE 'warning|^\s+\||^\s+=|note:' "$TMPD/build.txt" | tail -10 | sed 's/^/        /'
    echo "== SUSPEND: $pass bestanden, $fail gescheitert =="
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

# ------------------------------------------- 3. die Vorabmessung
echo
echo "== 3. the pre-measurement: what the machine really offers =="
lauf mess "osum suspmess acpiev" 300
if grep -aq 'susp: vorabmessung' "$TMPD/mess.txt"; then
    sed -n 's/^susp: vorabmessung/        /p' "$TMPD/mess.txt" | head -3
    ok "the pre-measurement runs and reports"
else
    bad "the pre-measurement reported nothing"
fi
hat "$TMPD/mess.txt" 'why=ok' "die Vorabmessung findet alles, was sie braucht"
hat_nicht "$TMPD/mess.txt" 'panic' "kein Ausnahmefehler im Messlauf"

K_S3=$(sed -n 's/.* s3=\([0-9]*,[0-9]*\).*/\1/p' "$TMPD/mess.txt" | head -1)
K_S4=$(sed -n 's/.* s4=\([0-9]*,[0-9]*\).*/\1/p' "$TMPD/mess.txt" | head -1)
K_PM1A=$(sed -n 's/.* pm1a=\(0x[0-9a-fA-F]*\).*/\1/p' "$TMPD/mess.txt" | head -1)
[ -n "$K_S3" ] && ok "der Kern liest \\_S3 = $K_S3" \
                || bad "the kernel finds no \\_S3"
[ -n "$K_S4" ] && ok "der Kern liest \\_S4 = $K_S4" \
                || bad "the kernel finds no \\_S4"
[ -n "$K_PM1A" ] && ok "PM1a_CNT = $K_PM1A from the FADT" \
                  || bad "kein PM1a_CNT"
hat "$TMPD/mess.txt" 'facs=0x[0-9a-f]*[1-9a-f]' "die FACS liegt vor (Platz fuer den Aufwachvektor)"

if [ "$IASL" = 1 ]; then
    echo
    echo "== 3b. dieselbe DSDT, gelesen von iasl statt vom Kern =="
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
hat_nicht "$TMPD/zyk.txt" 'panic' "kein Ausnahmefehler im Zyklenlauf"
hat "$TMPD/zyk.txt" 'susp: == zyklus 1' "Zyklus 1 laeuft"
hat "$TMPD/zyk.txt" 'susp: == zyklus 2' "Zyklus 2 laeuft -- er findet, was der erste versteckt"

SAME_N=$(grep -ac '^susp: gleich$' "$TMPD/zyk.txt")
UNGL=$(grep -ac 'susp: UNGLEICH' "$TMPD/zyk.txt")
RGL=$(grep -ac 'susp: rahmen gleich' "$TMPD/zyk.txt")
RVER=$(grep -ac 'susp: RAHMEN VERLOREN' "$TMPD/zyk.txt")
if [ "$SAME_N" -ge 2 ]; then
    ok "the state is identical after BOTH cycles ($SAME_N von 2)"
else
    bad "the state is identical in only $SAME_N of 2 cycles"
fi
if [ "$UNGL" -eq 0 ]; then
    ok "no cycle reports a changed state"
else
    bad "$UNGL Zyklus/Zyklen melden UNGLEICH"
    grep -a 'UNGLEICH' "$TMPD/zyk.txt" | sed 's/^/        /' | head -4
fi
if [ "$RGL" -ge 2 ] && [ "$RVER" -eq 0 ]; then
    ok "frei vorher == frei nachher, in beiden Zyklen ($RGL von 2)"
else
    bad "Rahmen gehen verloren (gleich=$RGL verloren=$RVER)"
    grep -a 'RAHMEN VERLOREN\|vorher\|nachher' "$TMPD/zyk.txt" | sed 's/^/        /' | head -6
fi

S1=$(grep -a 'susp: gesichert' "$TMPD/zyk.txt" | sed -n '1s/.*sum=\(0x[0-9a-f]*\).*/\1/p')
S2=$(grep -a 'susp: gesichert' "$TMPD/zyk.txt" | sed -n '2s/.*sum=\(0x[0-9a-f]*\).*/\1/p')
if [ -n "$S1" ] && [ -n "$S2" ] && [ "$S1" != "$S2" ]; then
    ok "the cycles write DIFFERENT images ($S1 / $S2)"
else
    bad "both cycles have the same sum (${S1:-?} / ${S2:-?}) -- the second measures the first"
fi

if grep -aq 'susp: eingespielt' "$TMPD/zyk.txt"; then
    SCHIEF=$(awk '/susp: eingespielt/{
        s="";v="";
        if (match($0,/sum=0x[0-9a-f]+/))  s=substr($0,RSTART+4,RLENGTH-4);
        if (match($0,/soll=0x[0-9a-f]+/)) v=substr($0,RSTART+5,RLENGTH-5);
        if (s!=v) c++} END{print c+0}' "$TMPD/zyk.txt")
    if [ "$SCHIEF" -eq 0 ]; then
        ok "computed and stored checksum match on every restore"
    else
        bad "$SCHIEF Einspielung(en) mit abweichender Pruefsumme"
    fi
else
    bad "nothing was ever restored"
fi

echo
echo "== 5. the control run: a corrupted image must NOT be accepted =="
hat "$TMPD/zyk.txt" 'susp: == gegenprobe kaputt' "die Gegenprobe laeuft"
if grep -aq 'susp: KALTSTART, sauber' "$TMPD/zyk.txt"; then
    ok "the corrupted image leads to a clean cold start"
else
    bad "the corrupted image was NOT rejected -- garbage would have been restored"
fi
if grep -a 'KALTSTART' "$TMPD/zyk.txt" | grep -aq 'why=Pruefsumme falsch'; then
    ok "and for the right reason: the checksum"
else
    bad "rejected, but not because of the checksum"
    grep -a 'KALTSTART' "$TMPD/zyk.txt" | sed 's/^/        /' | head -2
fi

# ------------------------------------------- 6. was drumherum haengt
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
        ok "tools/usbimg/build.sh baut das Abbild ($USZ octets)"
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
    ok "SCHLAF_OFF+SCHLAF_MAX = $(printf '0x%X' $((sv + sm))) bleibt in 0x126000"
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
    bad "$ausser Modusindex/indizes liegen ausserhalb 1020..1029 (von $anz)"
fi

echo
echo "== 8. THE REAL CYCLE ACROSS THE BOOT (QEMU off in between) =="
zyklus z1 "" 400
A="$TMPD/z1-a.txt"; B="$TMPD/z1-b.txt"
hat_nicht "$A" 'panic' "kein Ausnahmefehler im Sicherungslauf"
hat_nicht "$B" 'panic' "kein Ausnahmefehler im Wiederanlauf"
hat "$A" 'sleep: abbild steht' "Lauf A schreibt das Abbild"
hat "$A" 'sleep: gast wird beendet' "Lauf A BEENDET den Gast -- der Speicher ist wirklich weg"

if grep -a 'sleep: start' "$B" | grep -aq 'abbild=1'; then
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

hat "$B" 'sleep: equal' "der Zustand ist nach dem Hochlauf IDENTISCH"
hat_nicht "$B" 'sleep: UNEQUAL' "kein veraenderter Zustand"

HWA=$(grep -a 'sleep: saved' -m1 "$A" >/dev/null 2>&1; \
      grep -a 'sleep: start' "$B" | sed -n '1s/.* hw=\(0x[0-9a-f]*\).*/\1/p')
HWI=$(grep -a 'sleep: start' "$B" | sed -n '1s/.* hwimg=\(0x[0-9a-f]*\).*/\1/p')
if [ -n "$HWA" ] && [ "$HWA" = "$HWI" ] && [ "$HWA" != "0x0" ]; then
    ok "the hardware id is stable across the restart ($HWA)"
else
    bad "Hardware-Kennung: jetzt '${HWA:-?}', im Abbild '${HWI:-?}'"
fi

if grep -a 'sleep: saved' "$A" | grep -aq 'regs=1'; then
    ok "PUNKT 2: der Registersatz (rsp/rbp/rbx/r12-15/rip/cr3) geht ins Abbild"
else
    bad "PUNKT 2: no register set in the image"
fi
if grep -a 'sleep: saved' "$A" | grep -aq 'fpu=1'; then
    FSZ=$(grep -a 'sleep: saved' "$A" | sed -n '1s/.*fpugroe=\([0-9]*\).*/\1/p')
    ok "PUNKT 3: der FPU/XSAVE-Bereich geht ins Abbild ($FSZ octets)"
else
    bad "PUNKT 3: no FPU area in the image"
    grep -a 'fpuwhy' "$A" | sed 's/^/        /' | head -2
fi
if grep -a 'sleep: saved' "$A" | grep -aq 'geraete=1'; then
    ok "PUNKT 5: Zeitgeber/Tastatur/Grafik gehen ins Abbild"
else
    bad "PUNKT 5: no device state in the image"
fi
if grep -a 'sleep: equal' "$B" | grep -aq 'regs=1 fpu=1 geraete=1'; then
    ok "and all three are back after the boot"
else
    bad "after the boot one of the three is missing"
    grep -a 'sleep: equal' "$B" | sed 's/^/        /' | head -2
fi

FR=$(grep -a 'sleep: saved' "$A" | sed -n '1s/.*frames=\([0-9]*\).*/\1/p')
FB=$(grep -a 'sleep: start' "$B" | sed -n '1s/.* zurueck=\([0-9]*\).*/\1/p')
if [ -n "$FR" ] && [ "$FR" -gt 0 ]; then
    ok "PUNKT 4: $FR frames of main memory go into the image (not just a pattern)"
else
    bad "PUNKT 4: 0 frames went into the image"
fi
if [ -n "$FR" ] && [ "$FR" = "$FB" ]; then
    ok "gesicherte == eingespielte Rahmen ($FR == $FB)"
else
    bad "saved $FR, restored ${FB:-?} -- a frame was lost on the way"
fi

hat "$B" 'sleep: frames equal' "frei vorher == frei nachher (kein verlorener Rahmen)"
hat_nicht "$B" 'sleep: FRAMES LOST' "keine Meldung ueber verlorene Rahmen"

echo
echo "== 9. THE PROMISE THAT CHECKS REGISTERS AND PAGE TABLES: KEEP COMPUTING =="
if grep -aq 'sleep: computed_on=1' "$B"; then
    R=$(grep -a 'sleep: compute' "$B" | sed -n '1s/.*s=\([0-9]*\) schritt=\([0-9]*\) soll=\([0-9]*\).*/summe=\1 schritt=\2 soll=\3/p')
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
hat "$A2" 'sleep: == arm zyklus2' "der zweite Zyklus fuehrt einen ANDEREN Zustand"
hat "$B2" 'sleep: equal' "auch der zweite Zyklus kommt identisch zurueck"
hat "$B2" 'sleep: computed_on=1' "auch im zweiten Zyklus rechnet der Prozess weiter"
hat "$B2" 'sleep: frames equal' "auch im zweiten Zyklus kein verlorener Rahmen"
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
    bad "beide Zyklen holen denselben Zustand zurueck (${C1:-?} / ${C2:-?})"
fi

echo
echo "== 11. THE CONTROL RUNS THAT MUST FAIL =="
zyklus gk "schlafkaputt" 400
GK="$TMPD/gk-b.txt"
if grep -a 'sleep: start' "$GK" | grep -aq 'abbild=0'; then
    ok "the corrupted image is REJECTED at boot"
else
    bad "the corrupted image was restored -- garbage in memory"
fi
if grep -a 'sleep: KALTSTART' "$GK" | grep -aq 'why=Pruefsumme falsch'; then
    ok "and for the RIGHT reason: the checksum"
else
    bad "rejected, but not because of the checksum"
    grep -a 'sleep: KALTSTART\|sleep: start' "$GK" | sed 's/^/        /' | head -2
fi
hat_nicht "$GK" 'panic' "kein Ausnahmefehler beim Kaltstart nach dem Schaden"

zyklus gh "schlafhw" 400
GH="$TMPD/gh-b.txt"
if grep -a 'sleep: start' "$GH" | grep -aq 'abbild=0'; then
    ok "an image with a FOREIGN hardware id is rejected"
else
    bad "the foreign image was restored"
fi
if grep -a 'sleep: KALTSTART' "$GH" | grep -aq 'why=Hardware anders'; then
    ok "and for the RIGHT reason: the hardware id"
else
    bad "rejected, but not because of the hardware id"
    grep -a 'sleep: KALTSTART\|sleep: start' "$GH" | sed 's/^/        /' | head -2
fi
hat_nicht "$GH" 'panic' "kein Ausnahmefehler beim Kaltstart nach fremder Kennung"

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
if grep -a 'sleep: KALTSTART' "$TMPD/gn-b.txt" | grep -aq 'why=abgeschaltet'; then
    ok "mit 'noschlaf' bleibt ein gueltiges Abbild liegen (bewusster Kaltstart)"
else
    bad "'noschlaf' hat die Starterkennung nicht abgeschaltet"
    grep -a 'sleep: start\|KALTSTART' "$TMPD/gn-b.txt" | sed 's/^/        /' | head -2
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
hat_nicht "$WA" 'panic' "kein Ausnahmefehler im Sicherungslauf (wach)"
hat_nicht "$WB" 'panic' "kein Ausnahmefehler im Wiederanlauf (wach)"

WN=$(grep -a 'wach: prozesse' "$WA" | sed -n '1s/.*n=\([0-9]*\).*/\1/p')
WPIDS=$(grep -a 'wach: prozesse' "$WA" | sed -n '1s/.*pids=\([0-9,]*\).*/\1/p')
if [ -n "$WN" ] && [ "$WN" -ge 3 ]; then
    ok "Lauf A legt $WN Prozesse an, pids=$WPIDS"
else
    bad "Run A created fewer than three processes (n=${WN:-?})"
fi
WVERSCH=$(printf '%s' "$WPIDS" | tr ',' '\n' | sort -u | grep -c .)
if [ "${WVERSCH:-0}" -ge 3 ]; then
    ok "and their pids are DIFFERENT ($WVERSCH different)"
else
    bad "the pids are not different: $WPIDS"
fi

if grep -a 'wach: zurueck' "$WB" | grep -aq 'why=ok'; then
    ok "the restart brings the tasks back (why=ok)"
else
    bad "the restart brought back no tasks"
    grep -a 'wach: zurueck' "$WB" | sed 's/^/        /' | head -2
fi
WBACK=$(grep -a 'wach: zurueck' "$WB" | sed -n '1s/.*aufgaben=\([0-9]*\).*/\1/p')
WKST=$(grep -a 'wach: zurueck' "$WB" | sed -n '1s/.*kstapel=\([0-9]*\).*/\1/p')
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

WLAUF=$(grep -a 'wach: weiterlauf' "$WB" | sed -n '1s/.*gelaufen=\([0-9]*\).*/\1/p')
if [ -n "$WLAUF" ] && [ "$WLAUF" -ge 3 ]; then
    ok "PUNKT 2: $WLAUF restarted processes were on the CPU (T_RUNS>0)"
else
    bad "PUNKT 2: no restarted process got onto the CPU (ran=${WLAUF:-0})"
fi

WVOR=$(grep -a 'wach: weiter ' "$WB" | sed -n '1s/.*vorher=\([0-9]*\).*/\1/p')
WNACH=$(grep -a 'wach: weiter ' "$WB" | sed -n '1s/.*nachher=\([0-9]*\).*/\1/p')
WSUM=$(grep -a 'wach: weiter ' "$WB" | sed -n '1s/.*summe=\([0-9]*\).*/\1/p')
WSOLL=$(grep -a 'wach: weiter ' "$WB" | sed -n '1s/.* soll=\([0-9]*\).*/\1/p')
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
WWEITER=$(grep -a 'wach: weiterlauf' "$WB" | sed -n '1s/.*weiterlauf=\([0-9]*\).*/\1/p')
WALLE=$(grep -a 'wach: weiterlauf' "$WB" | sed -n '1s/.*alle=\([0-9]*\).*/\1/p')
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
WWACH=$(grep -a 'sleep: frames equal\|sleep: FRAMES LOST' "$WB" | sed -n '1s/.*wach=\([0-9]*\).*/\1/p')
if [ -n "$WWACH" ] && [ "$WWACH" -gt 0 ]; then
    ok "and the restart names its own $WWACH frames (instead of hiding them)"
else
    bad "the restart does not count its own frames"
fi

hat "$WB" 'sleep: equal' "die Zusage der Vorrunde haelt: der Zustand ist identisch"
hat "$WB" 'sleep: computed_on=1' "und ihre Gegenrechnung haelt ebenfalls"

echo
echo "== 13. two awake cycles with different states =="
wzyklus wz2 "wach schlaf" 400
W2B="$TMPD/wz2-b.txt"
hat_nicht "$W2B" 'panic' "kein Ausnahmefehler im zweiten Zyklus"
W2BEFORE=$(grep -a 'wach: weiter ' "$W2B" | sed -n '1s/.*vorher=\([0-9]*\).*/\1/p')
W2AFTER=$(grep -a 'wach: weiter ' "$W2B" | sed -n '1s/.*nachher=\([0-9]*\).*/\1/p')
W2SUM=$(grep -a 'wach: weiter ' "$W2B" | sed -n '1s/.*summe=\([0-9]*\).*/\1/p')
W2SOLL=$(grep -a 'wach: weiter ' "$W2B" | sed -n '1s/.* soll=\([0-9]*\).*/\1/p')
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
    bad "beide Zyklen haben dasselbe Abbild ($S1 / $S2)"
fi

echo
echo "== 14. Gegenprobe: 'nowach' laesst die Prozesse liegen =="
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
if grep -a 'wach: zurueck' "$WNB" | grep -aq 'why=abgeschaltet'; then
    ok "'nowach' schaltet den Wiederanlauf der Aufgaben ab"
else
    bad "'nowach' hat den Wiederanlauf nicht abgeschaltet"
    grep -a 'wach: zurueck' "$WNB" | sed 's/^/        /' | head -2
fi
if grep -a 'wach: zurueck' "$WNB" | grep -aq 'aufgaben=0'; then
    ok "and NO task enters the run list"
else
    bad "trotz 'nowach' kamen tasks"
fi
if grep -a 'sleep: start' "$WNB" | grep -aq 'abbild=1'; then
    ok "the MEMORY still comes back (the promise of the previous round does not depend on it)"
else
    bad "'nowach' hat auch das Einspielen des Speichers verhindert"
fi
hat_nicht "$WNB" 'panic' "kein Ausnahmefehler mit 'nowach'"

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
    ok "WACH_OFF+WACH_MAX = $(printf '0x%X' $((wv + wm))) bleibt in 0x12C000"
else
    bad "the range extends beyond 0x12C000 -- that is foreign territory"
fi
wausser=$(grep -aE "^const M_(WACH|WACHARM|WACHPRUEF|NOWACH|WACHMESS): u64 = [0-9]+" \
    kernel/lib/kstate.fi | grep -oE '= [0-9]+' | grep -oE '[0-9]+' \
    | awk '$1 < 1050 || $1 > 1059' | wc -l)
if [ "$wausser" -eq 0 ]; then
    ok "all mode indices of round AWAKE lie in 1050..1059"
else
    bad "$wausser Modusindex(e) der Runde WACH liegen ausserhalb"
fi

echo
echo "== SUSPEND+SCHLAF+WACH: $pass bestanden, $fail gescheitert =="
[ "$fail" -eq 0 ]
