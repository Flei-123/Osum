#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/../lib/marke-env.sh"
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
    IASL=1; ok "iasl ist da -- die Gegenprobe der Vorabmessung ist moeglich"
else
    echo "  HINWEIS: iasl fehlt, die DSDT-Gegenprobe entfaellt"
fi

# ---------------------------------------------------- 1. die Speicherkarte
echo
echo "== 1. die Speicherkarte von kdata =="
if python3 tools/kernel/memmap.py kernel > "$TMPD/karte.txt" 2>&1; then
    ok "die Karte: $(tail -1 "$TMPD/karte.txt")"
else
    bad "tools/kernel/memmap.py meldet Kollisionen"
    sed 's/^/        /' "$TMPD/karte.txt" | head -10
fi
hat "$TMPD/karte.txt" "0 Kollisionen" "keine zwei Bereiche ueberschneiden sich"

v=$(grep -aE "^const SUSP_OFF: u64 = 0x[0-9A-Fa-f]+" kernel/lib/kstate.fi \
    | head -1 | grep -oE '0x[0-9A-Fa-f]+')
m=$(grep -aE "^const SUSP_MAX: u64 = 0x[0-9A-Fa-f]+" kernel/lib/kstate.fi \
    | head -1 | grep -oE '0x[0-9A-Fa-f]+')
if [ -n "$v" ] && [ "$((v))" -eq $((0x110000)) ]; then
    ok "SUSP_OFF = $v -- genau der zugeteilte Anfang"
else
    bad "SUSP_OFF = ${v:-fehlt}, zugeteilt war 0x110000"
fi
if [ -n "$v" ] && [ -n "$m" ] && [ "$((v + m))" -le $((0x113000)) ]; then
    ok "SUSP_OFF+SUSP_MAX = $(printf '0x%X' $((v + m))) bleibt in 0x113000"
else
    bad "der Bereich geht ueber 0x113000 hinaus -- das ist fremdes Land"
fi

# ---------------------------------------------------- 2. bauen
echo
echo "== 2. der Kern baut =="
if bash tools/build-kernel.sh "$TMPD/k.elf" > "$TMPD/build.txt" 2>&1; then
    ok "der Kern baut ($(stat -c%s "$TMPD/k.elf") Oktette)"
else
    bad "der Kern baut NICHT"
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
echo "== 3. die Vorabmessung: was bietet die Maschine wirklich an =="
lauf mess "osum suspmess acpiev" 300
if grep -aq 'susp: vorabmessung' "$TMPD/mess.txt"; then
    sed -n 's/^susp: vorabmessung/        /p' "$TMPD/mess.txt" | head -3
    ok "die Vorabmessung laeuft und berichtet"
else
    bad "die Vorabmessung hat nichts berichtet"
fi
hat "$TMPD/mess.txt" 'why=ok' "die Vorabmessung findet alles, was sie braucht"
hat_nicht "$TMPD/mess.txt" 'panic' "kein Ausnahmefehler im Messlauf"

K_S3=$(sed -n 's/.* s3=\([0-9]*,[0-9]*\).*/\1/p' "$TMPD/mess.txt" | head -1)
K_S4=$(sed -n 's/.* s4=\([0-9]*,[0-9]*\).*/\1/p' "$TMPD/mess.txt" | head -1)
K_PM1A=$(sed -n 's/.* pm1a=\(0x[0-9a-fA-F]*\).*/\1/p' "$TMPD/mess.txt" | head -1)
[ -n "$K_S3" ] && ok "der Kern liest \\_S3 = $K_S3" \
                || bad "der Kern findet kein \\_S3"
[ -n "$K_S4" ] && ok "der Kern liest \\_S4 = $K_S4" \
                || bad "der Kern findet kein \\_S4"
[ -n "$K_PM1A" ] && ok "PM1a_CNT = $K_PM1A aus der FADT" \
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
        ok "ein Abzug des ACPI-Bereichs liegt vor ($(stat -c%s "$TMPD/acpi.bin") Oktette)"
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
            ok "die DSDT ist herausgeschnitten ($(stat -c%s "$TMPD/dsdt.aml") Oktette)"
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
                    ok "\\_S3: der Kern sagt $K_S3, iasl sagt $I_S3 -- gleich"
                else
                    bad "\\_S3: der Kern sagt '${K_S3:-nichts}', iasl sagt '${I_S3:-nichts}'"
                fi
                if [ -n "$I_S4" ] && [ "$I_S4" = "$K_S4" ]; then
                    ok "\\_S4: der Kern sagt $K_S4, iasl sagt $I_S4 -- gleich"
                else
                    bad "\\_S4: der Kern sagt '${K_S4:-nichts}', iasl sagt '${I_S4:-nichts}'"
                fi
            else
                bad "iasl hat die DSDT nicht zerlegt"
            fi
        else
            bad "die DSDT liess sich nicht herausschneiden"
        fi
    else
        bad "der ACPI-Abzug ist nicht entstanden (QMP/pmemsave)"
    fi
fi

echo
echo "== 4. zwei Zyklen, byteweise verglichen =="
lauf zyk "osum suspend acpiev" 400
hat_nicht "$TMPD/zyk.txt" 'panic' "kein Ausnahmefehler im Zyklenlauf"
hat "$TMPD/zyk.txt" 'susp: == zyklus 1' "Zyklus 1 laeuft"
hat "$TMPD/zyk.txt" 'susp: == zyklus 2' "Zyklus 2 laeuft -- er findet, was der erste versteckt"

GLEICH=$(grep -ac '^susp: gleich$' "$TMPD/zyk.txt")
UNGL=$(grep -ac 'susp: UNGLEICH' "$TMPD/zyk.txt")
RGL=$(grep -ac 'susp: rahmen gleich' "$TMPD/zyk.txt")
RVER=$(grep -ac 'susp: RAHMEN VERLOREN' "$TMPD/zyk.txt")
if [ "$GLEICH" -ge 2 ]; then
    ok "der Zustand ist nach BEIDEN Zyklen identisch ($GLEICH von 2)"
else
    bad "der Zustand ist nur in $GLEICH von 2 Zyklen identisch"
fi
if [ "$UNGL" -eq 0 ]; then
    ok "kein Zyklus meldet einen veraenderten Zustand"
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
    ok "die Zyklen schreiben VERSCHIEDENE Abbilder ($S1 / $S2)"
else
    bad "beide Zyklen haben dieselbe Summe (${S1:-?} / ${S2:-?}) -- der zweite misst den ersten"
fi

if grep -aq 'susp: eingespielt' "$TMPD/zyk.txt"; then
    SCHIEF=$(awk '/susp: eingespielt/{
        s="";v="";
        if (match($0,/sum=0x[0-9a-f]+/))  s=substr($0,RSTART+4,RLENGTH-4);
        if (match($0,/soll=0x[0-9a-f]+/)) v=substr($0,RSTART+5,RLENGTH-5);
        if (s!=v) c++} END{print c+0}' "$TMPD/zyk.txt")
    if [ "$SCHIEF" -eq 0 ]; then
        ok "berechnete und gespeicherte Pruefsumme stimmen bei jedem Einspielen ueberein"
    else
        bad "$SCHIEF Einspielung(en) mit abweichender Pruefsumme"
    fi
else
    bad "es wurde nie etwas eingespielt"
fi

echo
echo "== 5. die Gegenprobe: ein beschaedigtes Abbild darf NICHT gelten =="
hat "$TMPD/zyk.txt" 'susp: == gegenprobe kaputt' "die Gegenprobe laeuft"
if grep -aq 'susp: KALTSTART, sauber' "$TMPD/zyk.txt"; then
    ok "das beschaedigte Abbild fuehrt zu einem sauberen Kaltstart"
else
    bad "das beschaedigte Abbild wurde NICHT abgewiesen -- Muell waere eingespielt worden"
fi
if grep -a 'KALTSTART' "$TMPD/zyk.txt" | grep -aq 'why=Pruefsumme falsch'; then
    ok "und zwar aus dem richtigen Grund: die Pruefsumme"
else
    bad "abgewiesen, aber nicht wegen der Pruefsumme"
    grep -a 'KALTSTART' "$TMPD/zyk.txt" | sed 's/^/        /' | head -2
fi

# ------------------------------------------- 6. was drumherum haengt
echo
echo "== 6. check-ui und das Abbild =="
if bash tools/check-ui.sh > "$TMPD/ui.txt" 2>&1 \
   && grep -aq 'CHECK-UI PASSED' "$TMPD/ui.txt"; then
    ok "tools/check-ui.sh PASSED"
else
    bad "tools/check-ui.sh ist NICHT mehr gruen"
    tail -6 "$TMPD/ui.txt" | sed 's/^/        /'
fi
mkdir -p "$TMPD/usb"
if bash tools/usbimg/build.sh "$TMPD/usb" > "$TMPD/usb.txt" 2>&1 \
   && [ -f "$TMPD/usb/${MARKE_DATEI}-usb.img" ]; then
    USZ=$(stat -c%s "$TMPD/usb/${MARKE_DATEI}-usb.img")
    if [ "$USZ" -gt $((4 * 1024 * 1024)) ]; then
        ok "tools/usbimg/build.sh baut das Abbild ($USZ Oktette)"
    else
        bad "das Abbild ist nur $USZ Oktette gross -- das ist kein startfaehiger Stick"
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
echo "== 7. der zugeteilte Raum der Runde SCHLAF =="
sv=$(grep -aE "^const SCHLAF_OFF: u64 = 0x[0-9A-Fa-f]+" kernel/lib/kstate.fi \
    | head -1 | grep -oE '0x[0-9A-Fa-f]+')
sm=$(grep -aE "^const SCHLAF_MAX: u64 = 0x[0-9A-Fa-f]+" kernel/lib/kstate.fi \
    | head -1 | grep -oE '0x[0-9A-Fa-f]+')
if [ -n "$sv" ] && [ "$((sv))" -eq $((0x121000)) ]; then
    ok "SCHLAF_OFF = $sv -- genau der zugeteilte Anfang"
else
    bad "SCHLAF_OFF = ${sv:-fehlt}, zugeteilt war 0x121000"
fi
if [ -n "$sv" ] && [ -n "$sm" ] && [ "$((sv + sm))" -le $((0x126000)) ]; then
    ok "SCHLAF_OFF+SCHLAF_MAX = $(printf '0x%X' $((sv + sm))) bleibt in 0x126000"
else
    bad "der Bereich geht ueber 0x126000 hinaus -- das ist fremdes Land"
fi
ausser=$(grep -aE "^const M_(SCHLAF|SCHLAFARM|SCHLAFPRUEF|SCHLAFHW|SCHLAFKAPUTT|NOSCHLAF|SCHLAFMESS): u64 = [0-9]+" \
    kernel/lib/kstate.fi | grep -oE '= [0-9]+' | grep -oE '[0-9]+' \
    | awk '$1 < 1020 || $1 > 1029' | wc -l)
anz=$(grep -acE "^const M_(SCHLAF|SCHLAFARM|SCHLAFPRUEF|SCHLAFHW|SCHLAFKAPUTT|NOSCHLAF|SCHLAFMESS): u64 = [0-9]+" \
    kernel/lib/kstate.fi)
if [ "$ausser" -eq 0 ] && [ "$anz" -ge 7 ]; then
    ok "alle $anz Modusindizes der Runde liegen in 1020..1029"
else
    bad "$ausser Modusindex/indizes liegen ausserhalb 1020..1029 (von $anz)"
fi

echo
echo "== 8. DER ECHTE ZYKLUS UEBER DEN HOCHLAUF (QEMU dazwischen aus) =="
zyklus z1 "" 400
A="$TMPD/z1-a.txt"; B="$TMPD/z1-b.txt"
hat_nicht "$A" 'panic' "kein Ausnahmefehler im Sicherungslauf"
hat_nicht "$B" 'panic' "kein Ausnahmefehler im Wiederanlauf"
hat "$A" 'schlaf: abbild steht' "Lauf A schreibt das Abbild"
hat "$A" 'schlaf: gast wird beendet' "Lauf A BEENDET den Gast -- der Speicher ist wirklich weg"

if grep -a 'schlaf: start' "$B" | grep -aq 'abbild=1'; then
    ok "der Hochlauf erkennt das Abbild VON SELBST (Starterkennung)"
else
    bad "der Hochlauf hat das Abbild nicht erkannt"
    grep -a 'schlaf: start' "$B" | sed 's/^/        /' | head -2
fi
if grep -a 'schlaf: start' "$B" | grep -aq 'why=ok'; then
    ok "und es gilt: why=ok"
else
    bad "das Abbild wurde verworfen"
fi

hat "$B" 'schlaf: gleich' "der Zustand ist nach dem Hochlauf IDENTISCH"
hat_nicht "$B" 'schlaf: UNGLEICH' "kein veraenderter Zustand"

HWA=$(grep -a 'schlaf: gesichert' -m1 "$A" >/dev/null 2>&1; \
      grep -a 'schlaf: start' "$B" | sed -n '1s/.* hw=\(0x[0-9a-f]*\).*/\1/p')
HWI=$(grep -a 'schlaf: start' "$B" | sed -n '1s/.* hwimg=\(0x[0-9a-f]*\).*/\1/p')
if [ -n "$HWA" ] && [ "$HWA" = "$HWI" ] && [ "$HWA" != "0x0" ]; then
    ok "die Hardware-Kennung ist ueber den Neustart stabil ($HWA)"
else
    bad "Hardware-Kennung: jetzt '${HWA:-?}', im Abbild '${HWI:-?}'"
fi

if grep -a 'schlaf: gesichert' "$A" | grep -aq 'regs=1'; then
    ok "PUNKT 2: der Registersatz (rsp/rbp/rbx/r12-15/rip/cr3) geht ins Abbild"
else
    bad "PUNKT 2: kein Registersatz im Abbild"
fi
if grep -a 'schlaf: gesichert' "$A" | grep -aq 'fpu=1'; then
    FSZ=$(grep -a 'schlaf: gesichert' "$A" | sed -n '1s/.*fpugroe=\([0-9]*\).*/\1/p')
    ok "PUNKT 3: der FPU/XSAVE-Bereich geht ins Abbild ($FSZ Oktette)"
else
    bad "PUNKT 3: kein FPU-Bereich im Abbild"
    grep -a 'fpuwhy' "$A" | sed 's/^/        /' | head -2
fi
if grep -a 'schlaf: gesichert' "$A" | grep -aq 'geraete=1'; then
    ok "PUNKT 5: Zeitgeber/Tastatur/Grafik gehen ins Abbild"
else
    bad "PUNKT 5: kein Geraetezustand im Abbild"
fi
if grep -a 'schlaf: gleich' "$B" | grep -aq 'regs=1 fpu=1 geraete=1'; then
    ok "und alle drei stehen nach dem Hochlauf wieder da"
else
    bad "nach dem Hochlauf fehlt einer der drei"
    grep -a 'schlaf: gleich' "$B" | sed 's/^/        /' | head -2
fi

FR=$(grep -a 'schlaf: gesichert' "$A" | sed -n '1s/.*rahmen=\([0-9]*\).*/\1/p')
FB=$(grep -a 'schlaf: start' "$B" | sed -n '1s/.* zurueck=\([0-9]*\).*/\1/p')
if [ -n "$FR" ] && [ "$FR" -gt 0 ]; then
    ok "PUNKT 4: $FR Rahmen Arbeitsspeicher gehen ins Abbild (nicht nur ein Muster)"
else
    bad "PUNKT 4: es gingen 0 Rahmen ins Abbild"
fi
if [ -n "$FR" ] && [ "$FR" = "$FB" ]; then
    ok "gesicherte == eingespielte Rahmen ($FR == $FB)"
else
    bad "gesichert $FR, eingespielt ${FB:-?} -- ein Rahmen ist unterwegs verloren"
fi

hat "$B" 'schlaf: rahmen gleich' "frei vorher == frei nachher (kein verlorener Rahmen)"
hat_nicht "$B" 'schlaf: RAHMEN VERLOREN' "keine Meldung ueber verlorene Rahmen"

echo
echo "== 9. DIE ZUSAGE, DIE REGISTER UND SEITENTABELLEN PRUEFT: WEITERRECHNEN =="
if grep -aq 'schlaf: weitergerechnet=1' "$B"; then
    R=$(grep -a 'schlaf: rechnung' "$B" | sed -n '1s/.*s=\([0-9]*\) schritt=\([0-9]*\) soll=\([0-9]*\).*/summe=\1 schritt=\2 soll=\3/p')
    ok "der Prozess rechnet nach dem Hochlauf RICHTIG weiter ($R)"
else
    bad "die Rechnung des Prozesses hat den Schlaf NICHT ueberlebt"
    grep -a 'schlaf: rechnung\|weitergerechnet' "$B" | sed 's/^/        /' | head -3
fi
RS=$(grep -a 'schlaf: rechnung' "$B" | sed -n '1s/.*s=\([0-9]*\) .*/\1/p')
if [ -n "$RS" ] && [ "$RS" -gt 0 ]; then
    ok "und die Rechnung ist nicht leer (summe=$RS)"
else
    bad "die Rechnung ist leer (summe=${RS:-?}) -- das prueft nichts"
fi

echo
echo "== 10. ZWEI ZYKLEN HINTEREINANDER, mit VERSCHIEDENEN Abbildern =="
zyklus z2 "schlaf" 400
A2="$TMPD/z2-a.txt"; B2="$TMPD/z2-b.txt"
hat "$A2" 'schlaf: == arm zyklus2' "der zweite Zyklus fuehrt einen ANDEREN Zustand"
hat "$B2" 'schlaf: gleich' "auch der zweite Zyklus kommt identisch zurueck"
hat "$B2" 'schlaf: weitergerechnet=1' "auch im zweiten Zyklus rechnet der Prozess weiter"
hat "$B2" 'schlaf: rahmen gleich' "auch im zweiten Zyklus kein verlorener Rahmen"
S1=$(grep -a 'schlaf: gesichert' "$A" | sed -n '1s/.*sum=\(0x[0-9a-f]*\).*/\1/p')
S2=$(grep -a 'schlaf: gesichert' "$A2" | sed -n '1s/.*sum=\(0x[0-9a-f]*\).*/\1/p')
if [ -n "$S1" ] && [ -n "$S2" ] && [ "$S1" != "$S2" ]; then
    ok "die zwei Zyklen schreiben VERSCHIEDENE Abbilder ($S1 / $S2)"
else
    bad "beide Zyklen haben dieselbe Summe (${S1:-?} / ${S2:-?}) -- der zweite misst den ersten"
fi
C1=$(grep -a 'schlaf: gleich' "$B" | sed -n '1s/.*cnt=\([0-9]*\).*/\1/p')
C2=$(grep -a 'schlaf: gleich' "$B2" | sed -n '1s/.*cnt=\([0-9]*\).*/\1/p')
if [ -n "$C1" ] && [ -n "$C2" ] && [ "$C1" != "$C2" ]; then
    ok "und die zurueckgeholten Zustaende sind verschieden (cnt $C1 / $C2)"
else
    bad "beide Zyklen holen denselben Zustand zurueck (${C1:-?} / ${C2:-?})"
fi

echo
echo "== 11. DIE GEGENPROBEN, DIE FEHLSCHLAGEN MUESSEN =="
zyklus gk "schlafkaputt" 400
GK="$TMPD/gk-b.txt"
if grep -a 'schlaf: start' "$GK" | grep -aq 'abbild=0'; then
    ok "das beschaedigte Abbild wird beim Hochlauf ABGEWIESEN"
else
    bad "das beschaedigte Abbild wurde eingespielt -- Muell im Speicher"
fi
if grep -a 'schlaf: KALTSTART' "$GK" | grep -aq 'why=Pruefsumme falsch'; then
    ok "und zwar aus dem RICHTIGEN Grund: die Pruefsumme"
else
    bad "abgewiesen, aber nicht wegen der Pruefsumme"
    grep -a 'schlaf: KALTSTART\|schlaf: start' "$GK" | sed 's/^/        /' | head -2
fi
hat_nicht "$GK" 'panic' "kein Ausnahmefehler beim Kaltstart nach dem Schaden"

zyklus gh "schlafhw" 400
GH="$TMPD/gh-b.txt"
if grep -a 'schlaf: start' "$GH" | grep -aq 'abbild=0'; then
    ok "ein Abbild mit FREMDER Hardware-Kennung wird abgewiesen"
else
    bad "das fremde Abbild wurde eingespielt"
fi
if grep -a 'schlaf: KALTSTART' "$GH" | grep -aq 'why=Hardware anders'; then
    ok "und zwar aus dem RICHTIGEN Grund: die Hardware-Kennung"
else
    bad "abgewiesen, aber nicht wegen der Hardware-Kennung"
    grep -a 'schlaf: KALTSTART\|schlaf: start' "$GH" | sed 's/^/        /' | head -2
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
if grep -a 'schlaf: KALTSTART' "$TMPD/gn-b.txt" | grep -aq 'why=abgeschaltet'; then
    ok "mit 'noschlaf' bleibt ein gueltiges Abbild liegen (bewusster Kaltstart)"
else
    bad "'noschlaf' hat die Starterkennung nicht abgeschaltet"
    grep -a 'schlaf: start\|KALTSTART' "$TMPD/gn-b.txt" | sed 's/^/        /' | head -2
fi

echo
echo "== 12. RUNDE WACH: laufen die Prozesse nach dem Hochlauf weiter? =="
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
    bad "Lauf A hat weniger als drei Prozesse angelegt (n=${WN:-?})"
fi
WVERSCH=$(printf '%s' "$WPIDS" | tr ',' '\n' | sort -u | grep -c .)
if [ "${WVERSCH:-0}" -ge 3 ]; then
    ok "und ihre pids sind VERSCHIEDEN ($WVERSCH verschiedene)"
else
    bad "die pids sind nicht verschieden: $WPIDS"
fi

if grep -a 'wach: zurueck' "$WB" | grep -aq 'why=ok'; then
    ok "der Wiederanlauf holt die Aufgaben zurueck (why=ok)"
else
    bad "der Wiederanlauf hat keine Aufgaben zurueckgeholt"
    grep -a 'wach: zurueck' "$WB" | sed 's/^/        /' | head -2
fi
WBACK=$(grep -a 'wach: zurueck' "$WB" | sed -n '1s/.*aufgaben=\([0-9]*\).*/\1/p')
WKST=$(grep -a 'wach: zurueck' "$WB" | sed -n '1s/.*kstapel=\([0-9]*\).*/\1/p')
if [ -n "$WBACK" ] && [ "$WBACK" -ge 3 ]; then
    ok "PUNKT 1: $WBACK Aufgabeneintraege stehen wieder in der Tafel"
else
    bad "PUNKT 1: es kamen ${WBACK:-0} Aufgaben zurueck"
fi
# 17 Rahmen je Aufgabe (KSTACK_FRAMES + 1 Wache).
if [ -n "$WKST" ] && [ -n "$WBACK" ] && [ "$WKST" -eq $((WBACK * 17)) ]; then
    ok "PUNKT 1: $WKST Kernstapelrahmen == $WBACK Aufgaben * 17"
else
    bad "die Kernstapelrahmen passen nicht: kstapel=${WKST:-?}, aufgaben=${WBACK:-?}"
fi

WLAUF=$(grep -a 'wach: weiterlauf' "$WB" | sed -n '1s/.*gelaufen=\([0-9]*\).*/\1/p')
if [ -n "$WLAUF" ] && [ "$WLAUF" -ge 3 ]; then
    ok "PUNKT 2: $WLAUF wiederangelaufene Prozesse waren auf dem Prozessor (T_RUNS>0)"
else
    bad "PUNKT 2: kein wiederangelaufener Prozess kam auf den Prozessor (gelaufen=${WLAUF:-0})"
fi

WVOR=$(grep -a 'wach: weiter ' "$WB" | sed -n '1s/.*vorher=\([0-9]*\).*/\1/p')
WNACH=$(grep -a 'wach: weiter ' "$WB" | sed -n '1s/.*nachher=\([0-9]*\).*/\1/p')
WSUM=$(grep -a 'wach: weiter ' "$WB" | sed -n '1s/.*summe=\([0-9]*\).*/\1/p')
WSOLL=$(grep -a 'wach: weiter ' "$WB" | sed -n '1s/.* soll=\([0-9]*\).*/\1/p')
if [ -n "$WVOR" ] && [ "$WVOR" -gt 0 ]; then
    ok "die Vergleichszahl kommt aus dem ABBILD (vorher=$WVOR, nicht 0)"
else
    bad "vorher=${WVOR:-?} -- gegen 0 verglichen misst diese Zusage nichts"
fi
if [ -n "$WVOR" ] && [ -n "$WNACH" ] && [ "$WNACH" -gt "$WVOR" ]; then
    ok "DIE ZUSAGE: der Zaehler STEIGT ueber den Ruhezustand hinweg ($WVOR -> $WNACH)"
else
    bad "der Zaehler ist nicht gestiegen: vorher=${WVOR:-?} nachher=${WNACH:-?}"
fi
if [ -n "$WSUM" ] && [ "$WSUM" = "$WSOLL" ] && [ "${WSUM:-0}" -gt 0 ]; then
    ok "und die Gegenrechnung stimmt: summe=$WSUM == n*(n+1)/2=$WSOLL"
else
    bad "die Gegenrechnung stimmt NICHT: summe=${WSUM:-?} soll=${WSOLL:-?}"
fi
WWEITER=$(grep -a 'wach: weiterlauf' "$WB" | sed -n '1s/.*weiterlauf=\([0-9]*\).*/\1/p')
WALLE=$(grep -a 'wach: weiterlauf' "$WB" | sed -n '1s/.*alle=\([0-9]*\).*/\1/p')
if [ -n "$WWEITER" ] && [ "$WWEITER" -ge 3 ]; then
    ok "MEHRERE PROZESSE: $WWEITER laufen nachweislich weiter (nicht nur einer)"
else
    bad "es laufen ${WWEITER:-0} Prozesse weiter -- verlangt sind mindestens drei"
fi
if [ "${WALLE:-0}" = "1" ]; then
    ok "und es sind ALLE Prozesse dieser Runde, nicht nur einige"
else
    bad "nicht alle wiederangelaufenen Prozesse dieser Runde rechnen weiter"
fi

if grep -aq 'schlaf: rahmen gleich' "$WB"; then
    ok "kein verlorener Rahmen -- auch mit Kernstapeln und Seitentafeln"
else
    bad "die Rahmenrechnung geht im Wach-Zyklus nicht auf"
    grep -a 'RAHMEN VERLOREN\|rahmen gleich' "$WB" | sed 's/^/        /' | head -2
fi
WWACH=$(grep -a 'rahmen gleich\|RAHMEN VERLOREN' "$WB" | sed -n '1s/.*wach=\([0-9]*\).*/\1/p')
if [ -n "$WWACH" ] && [ "$WWACH" -gt 0 ]; then
    ok "und der Wiederanlauf benennt seine eigenen $WWACH Rahmen (statt sie zu verschweigen)"
else
    bad "der Wiederanlauf zaehlt seine eigenen Rahmen nicht"
fi

hat "$WB" 'schlaf: gleich' "die Zusage der Vorrunde haelt: der Zustand ist identisch"
hat "$WB" 'schlaf: weitergerechnet=1' "und ihre Gegenrechnung haelt ebenfalls"

echo
echo "== 13. zwei Wach-Zyklen mit verschiedenen Zustaenden =="
wzyklus wz2 "wach schlaf" 400
W2B="$TMPD/wz2-b.txt"
hat_nicht "$W2B" 'panic' "kein Ausnahmefehler im zweiten Zyklus"
W2VOR=$(grep -a 'wach: weiter ' "$W2B" | sed -n '1s/.*vorher=\([0-9]*\).*/\1/p')
W2NACH=$(grep -a 'wach: weiter ' "$W2B" | sed -n '1s/.*nachher=\([0-9]*\).*/\1/p')
W2SUM=$(grep -a 'wach: weiter ' "$W2B" | sed -n '1s/.*summe=\([0-9]*\).*/\1/p')
W2SOLL=$(grep -a 'wach: weiter ' "$W2B" | sed -n '1s/.* soll=\([0-9]*\).*/\1/p')
if [ -n "$W2NACH" ] && [ -n "$W2VOR" ] && [ "$W2NACH" -gt "$W2VOR" ]; then
    ok "auch im zweiten Zyklus steigt der Zaehler ($W2VOR -> $W2NACH)"
else
    bad "im zweiten Zyklus steigt der Zaehler nicht"
fi
if [ -n "$W2SUM" ] && [ "$W2SUM" = "$W2SOLL" ] && [ "${W2SUM:-0}" -gt 0 ]; then
    ok "und die Gegenrechnung stimmt auch dort ($W2SUM)"
else
    bad "die Gegenrechnung des zweiten Zyklus stimmt nicht"
fi
S1=$(grep -a 'schlaf: start' "$WB"  | sed -n '1s/.*sum=\(0x[0-9a-f]*\).*/\1/p')
S2=$(grep -a 'schlaf: start' "$W2B" | sed -n '1s/.*sum=\(0x[0-9a-f]*\).*/\1/p')
if [ -n "$S1" ] && [ -n "$S2" ] && [ "$S1" != "$S2" ]; then
    ok "die beiden Zyklen haben VERSCHIEDENE Abbilder ($S1 != $S2)"
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
    ok "und es kommt KEINE Aufgabe in die Laufliste"
else
    bad "trotz 'nowach' kamen Aufgaben zurueck"
fi
if grep -a 'schlaf: start' "$WNB" | grep -aq 'abbild=1'; then
    ok "der SPEICHER kommt trotzdem zurueck (die Zusage der Vorrunde haengt nicht daran)"
else
    bad "'nowach' hat auch das Einspielen des Speichers verhindert"
fi
hat_nicht "$WNB" 'panic' "kein Ausnahmefehler mit 'nowach'"

echo
echo "== 15. der zugeteilte Raum der Runde WACH =="
wv=$(grep -aE "^const WACH_OFF: u64 = 0x[0-9A-Fa-f]+" kernel/lib/kstate.fi \
    | head -1 | grep -oE '0x[0-9A-Fa-f]+')
wm=$(grep -aE "^const WACH_MAX: u64 = 0x[0-9A-Fa-f]+" kernel/lib/kstate.fi \
    | head -1 | grep -oE '0x[0-9A-Fa-f]+')
if [ -n "$wv" ] && [ "$((wv))" -eq $((0x127000)) ]; then
    ok "WACH_OFF = $wv -- genau der zugeteilte Anfang"
else
    bad "WACH_OFF = ${wv:-fehlt}, zugeteilt war 0x127000"
fi
if [ -n "$wv" ] && [ -n "$wm" ] && [ "$((wv + wm))" -le $((0x12C000)) ]; then
    ok "WACH_OFF+WACH_MAX = $(printf '0x%X' $((wv + wm))) bleibt in 0x12C000"
else
    bad "der Bereich geht ueber 0x12C000 hinaus -- das ist fremdes Land"
fi
wausser=$(grep -aE "^const M_(WACH|WACHARM|WACHPRUEF|NOWACH|WACHMESS): u64 = [0-9]+" \
    kernel/lib/kstate.fi | grep -oE '= [0-9]+' | grep -oE '[0-9]+' \
    | awk '$1 < 1050 || $1 > 1059' | wc -l)
if [ "$wausser" -eq 0 ]; then
    ok "alle Modusindizes der Runde WACH liegen in 1050..1059"
else
    bad "$wausser Modusindex(e) der Runde WACH liegen ausserhalb"
fi

echo
echo "== SUSPEND+SCHLAF+WACH: $pass bestanden, $fail gescheitert =="
[ "$fail" -eq 0 ]
