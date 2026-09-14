#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/suspend/run.sh -- DIE ABNAHME DER RUNDE SUSPEND (K-018).
#
# ==================================================================
# WAS HIER GEMESSEN WIRD, UND WAS AUSDRUECKLICH NICHT
# ==================================================================
#
# Der Auftrag verlangt ZUERST MESSEN, DANN BAUEN. Die Vorabmessung
# steht im Kern (`kernel/susp.fi`, Schalter `suspmess`) und wird hier
# gegen eine ZWEITE, unabhaengige Quelle gehalten: `iasl -d` auf
# einem Abzug der DSDT aus DERSELBEN Maschine. Ein Kern, der sich
# selbst misst und sich selbst glaubt, misst nichts.
#
# Genau diese Gegenprobe hat in dieser Runde einen echten Fehler
# gefunden: die erste Fassung meldete "kein _S3", weil sie
# `amlns.node_at(state,0)` (eine ADRESSE) an `amlns.child` gab, das
# einen INDEX erwartet. Ohne den Abgleich mit iasl waere in den
# Bericht geschrieben worden, die Firmware koenne kein S3 -- sie kann
# es, und das Paket lautet {One, One, Zero, Zero}.
#
# DIE MESSLATTE, die fallen muss:
#
#   1. Die Speicherkarte hat 0 Kollisionen, und SUSP_OFF liegt in
#      seinem ZUGETEILTEN Bereich 0x110000..0x113000. Keine Seite
#      ausserhalb. (Fuenf Runden hintereinander haben sich dieselbe
#      freie Seite genommen; diese Stelle prueft genau das.)
#   2. Der Kern baut.
#   3. Die Vorabmessung des Kerns == das, was iasl in der DSDT sieht.
#   4. ZWEI volle Zyklen: ein Zustand geht schlafen, kommt zurueck
#      und ist DANACH IDENTISCH -- byteweise verglichen, nicht per
#      Augenschein. Der zweite Zyklus benutzt einen ANDEREN Zustand
#      als der erste; ein stehengebliebenes Abbild faellt sonst nicht
#      auf.
#   5. Frei vorher == frei nachher. Kein einziger verlorener Rahmen.
#   6. DIE GEGENPROBE, DIE FEHLSCHLAGEN MUSS: ein absichtlich
#      beschaedigtes Abbild (ein Oktett gekippt, Kopf unveraendert)
#      darf NICHT eingespielt werden, sondern muss zu einem sauberen
#      Kaltstart fuehren. Ein Ruhezustand, der Muell einspielt, ist
#      schlimmer als keiner.
#   7. tools/check-ui.sh bleibt PASSED, tools/usbimg/build.sh baut.
#
# WAS DIESE RUNDE NICHT ZUSAGT, und es steht hier und nicht in einer
# Fussnote: die Maschine wird NICHT wirklich abgeschaltet. Gemessen
# ist der TRAEGER -- Abbild, Pruefsumme, Wiedererkennung, Gegenprobe
# -- und dass ein definierter Zustand byteweise zurueckkommt. Die
# Sicherung der CPU-Register, des FPU/XSAVE-Bereichs, der
# Seitentabellen und der Geraetezustaende ist NICHT gebaut und steht
# als roter Punkt in docs/RUNDE-SUSPEND.md.
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

# DER ZUGETEILTE BEREICH. Diese Stelle hat dem Projekt fuenf
# Kollisionen beschert, jede davon still und erst nach dem Merge.
v=$(grep -aE "^const SUSP_OFF: u64 = 0x[0-9A-Fa-f]+" kernel/kstate.fi \
    | head -1 | grep -oE '0x[0-9A-Fa-f]+')
m=$(grep -aE "^const SUSP_MAX: u64 = 0x[0-9A-Fa-f]+" kernel/kstate.fi \
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

# Ein Lauf im Kern. Die Platte ist bei JEDEM Lauf frisch -- ein
# Abbild aus einem frueheren Lauf darf den naechsten nicht faerben.
lauf() { # name kommandozeile [zeitlimit]
    local name=$1 app=$2 t=${3:-300}
    rm -f "$TMPD/$name.img"
    qemu-img create -f raw "$TMPD/$name.img" 64M >/dev/null 2>&1
    # `isa-debug-exit` ist der Weg, auf dem dieser Kern den Gast
    # beendet (kernel/power.fi, Anschluss 0xF4). OHNE ihn laeuft QEMU
    # nach `kernel: done` weiter, bis `timeout` zuschlaegt -- unter
    # KVM gemessen: die Messung war fertig und richtig, der Abschnitt
    # stand trotzdem 300 Sekunden.
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

# DIE ZAHLEN, EINZELN. Sie stehen hier als Erwartung, damit ein
# stilles Verschwinden auffaellt -- eine Zeile "s3=NEIN" ist ein
# Ergebnis, aber keine bestandene Abnahme.
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

# --------------------- 3b. DIE GEGENPROBE GEGEN EINE ZWEITE QUELLE
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
                # Die ersten zwei Elemente des Pakets, aus dem
                # Disassemblat. One/Zero/0xNN kommen alle vor.
                # DER WIRT HAT NICHT ZWINGEND GAWK. `strtonum` ist
                # eine GNU-Erweiterung, und auf mawk (Debian-Vorgabe)
                # gibt es sie nicht -- gemessen: "awk: line 14:
                # function strtonum never defined", und beide Werte
                # kamen leer zurueck. Die Umwandlung macht deshalb
                # `printf` in der Shell und nicht awk.
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

# ------------------------------------------- 4. die zwei Zyklen
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

# DIE ZWEI ZYKLEN MUESSEN VERSCHIEDENE ABBILDER SCHREIBEN. Sonst
# misst der zweite ein stehengebliebenes Abbild des ersten und
# meldet gruen, ohne etwas getan zu haben.
S1=$(grep -a 'susp: gesichert' "$TMPD/zyk.txt" | sed -n '1s/.*sum=\(0x[0-9a-f]*\).*/\1/p')
S2=$(grep -a 'susp: gesichert' "$TMPD/zyk.txt" | sed -n '2s/.*sum=\(0x[0-9a-f]*\).*/\1/p')
if [ -n "$S1" ] && [ -n "$S2" ] && [ "$S1" != "$S2" ]; then
    ok "die Zyklen schreiben VERSCHIEDENE Abbilder ($S1 / $S2)"
else
    bad "beide Zyklen haben dieselbe Summe (${S1:-?} / ${S2:-?}) -- der zweite misst den ersten"
fi

# Die Summe beim Einspielen muss die des Kopfes sein.
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

# --------------------------- 5. die Gegenprobe, die fehlschlagen MUSS
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
# ACHTUNG, EINMAL SELBST HINEINGEFALLEN: `build.sh` nimmt ein
# AUSGABEVERZEICHNIS, keinen Dateinamen. Mit einem Dateinamen legt es
# ein Verzeichnis dieses Namens an, und `stat` auf die nicht
# vorhandene Datei meldete "12288 Oktette" -- eine gruene Zeile ohne
# Abbild dahinter. Geprueft wird deshalb die Datei, die wirklich
# entsteht, UND ihre Groesse.
mkdir -p "$TMPD/usb"
if bash tools/usbimg/build.sh "$TMPD/usb" > "$TMPD/usb.txt" 2>&1 \
   && [ -f "$TMPD/usb/orientos-usb.img" ]; then
    USZ=$(stat -c%s "$TMPD/usb/orientos-usb.img")
    if [ "$USZ" -gt $((4 * 1024 * 1024)) ]; then
        ok "tools/usbimg/build.sh baut das Abbild ($USZ Oktette)"
    else
        bad "das Abbild ist nur $USZ Oktette gross -- das ist kein startfaehiger Stick"
    fi
else
    bad "tools/usbimg/build.sh baut NICHT"
    tail -8 "$TMPD/usb.txt" | sed 's/^/        /'
fi

echo
echo "== SUSPEND: $pass bestanden, $fail gescheitert =="
[ "$fail" -eq 0 ]
