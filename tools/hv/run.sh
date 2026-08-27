#!/usr/bin/env bash
# tools/hv/run.sh -- DER BEWEIS, DASS DIESER KERNEL EINEN FREMDEN
# PROZESSOR FUEHREN KANN.
#
# Runde K12 baut einen Hypervisor. Nicht als Nachbau fremder
# Schnittstellen -- das waere eine Arbeit ohne Ende -- sondern als
# Virtualisierung des PROZESSORS: Steuerblock, Gastzustand, Abfangbits,
# Eintritt, Austritt, Austrittsgrund. Diese Aufgabe ist endlich, sie
# steht vollstaendig in den Handbuechern, und wenn sie stimmt, stimmt
# sie fuer JEDES Gastsystem -- weil ein Gastsystem nichts anderes sieht
# als einen Prozessor.
#
# ================= WARUM AMD-V UND NICHT INTEL VT-x =================
#
# Der Auftrag sagte "Intel zuerst". Das geht hier nicht, und das ist
# GEMESSEN und nicht vermutet -- Abschnitt 0 dieses Laeufers misst es bei
# jedem Lauf neu:
#
#   qemu-system-x86_64 -accel tcg -cpu qemu64,+vmx
#     -> "warning: TCG doesn't support requested feature: CPUID.01H:ECX.vmx"
#   qemu-system-x86_64 -accel tcg -cpu qemu64,+svm
#     -> keine Warnung
#
# QEMUs Softwareemulation kann VMX NICHT. Sie kann SVM. Der Rechner, auf
# dem dieses Projekt gemessen wird, hat kein /dev/kvm -- es gibt also
# keine Beschleunigung, hinter der ein echtes VT-x steckte. Ein VMX-Wirt
# waere hier NICHT MESSBAR, und dieses Projekt misst. Das ist der ganze
# Grund; die Sache selbst ist dieselbe.
#
# ==================== WAS HIER GEMESSEN WIRD ====================
#
#   1. DER PROZESSOR KANN ES, UND ZWAR NACHGEZAEHLT. CPUID 0x8000000A
#      sagt, was da ist: verschachtelte Seitentabellen ja, "nrip save"
#      nein, "decode assists" nein. Was fehlt, muss der Wirt selbst tun --
#      und beides tut er: RIP weiterruecken und Befehle selbst lesen.
#   2. EIN GAST LAEUFT WIRKLICH. Nicht "er stuerzt nicht ab" -- er meldet
#      ueber einen vereinbarten Weg (`vmmcall`) Zahlen zurueck, und jede
#      einzelne wird hier nachgelesen.
#   3. DIE VERSCHACHTELTE SEITENTABELLE TRAEGT, und zwar doppelt: der
#      zweite Gast geht SELBST in den geschuetzten Modus, baut sich seine
#      EIGENE zweistufige Seitentabelle, schaltet sein eigenes Paging ein
#      und liest durch eine selbstgebaute virtuelle Adresse den Wert
#      zurueck, den er dort hingeschrieben hat. Damit haengen ZWEI
#      Uebersetzungen hintereinander -- die des Gasts und die des Wirts.
#   4. DER WIRT BEHAELT DIE MASCHINE. Ein Gast, der `cli` sagt und im
#      Kreis laeuft, wird vom Zeitgeber des Wirts eingeholt. Ein Gast,
#      der einen Dreifachfehler baut, stirbt allein.
#   5. RING 3 FUEHRT EINE GASTMASCHINE -- ueber ein Handle mit Rechten
#      und keinen zweiten Weg.
#   6. UND JEDE ZUSAGE HAT EINE GEGENPROBE, in der die Messung
#      ZUSAMMENBRICHT:
#         ohne `hv`   der Kernel verhaelt sich Zeile fuer Zeile wie vorher
#         `nonpt`     ohne verschachtelte Tabellen laeuft der Gast in den
#                     Speicher des Wirts und kommt nie zurueck
#         `gastfrei`  ohne V_INTR_MASKING behaelt der Laeufer den Prozessor
#         `nosvm`     ohne EFER.SVME gibt es nichts von alledem
#         -cpu qemu64 CPUID bietet keine NPT an, und der Wirt SAGT es
#   7. BEIDE UEBERSETZER. firnc0 und firnc1 bauen denselben Kernel, und er
#      sagt beide Male dasselbe.
#
# Verwendung:  bash tools/hv/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

has()    { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' sollte nicht da sein" || ok "$3"; }

# Eine Zahl aus einer `schluessel=wert`-Zeile der Ausgabe.
feld() { # datei schluessel
    grep -aoE "(^|[ ])$2=[0-9]+" "$1" | tail -1 | cut -d= -f2
}

num() { # name ist op soll
    local name=$1 ist=$2 op=$3 soll=$4
    case "$op" in
        eq) [ "${ist:-x}" = "$soll" ] && ok "$name ($ist)" \
                || bad "$name: $ist statt $soll" ;;
        gt) [ "${ist:-0}" -gt "$soll" ] 2>/dev/null && ok "$name ($ist)" \
                || bad "$name: $ist ist nicht > $soll" ;;
    esac
}

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "HV: skipped, qemu-system-x86_64 is not available"
    exit 0
fi

# `-cpu max` ist NICHT beliebig: `-cpu qemu64` meldet in CPUID 0x8000000A
# KEINE verschachtelten Seitentabellen (gemessen: svm_feat_edx = 0).
# Gegenprobe E unten misst genau das.
CPU=max

run_kernel() { # abbild anhang ausgabe zeitlimit
    timeout "${4:-150}" qemu-system-x86_64 -kernel "$1" -cpu "$CPU" -m 256 \
        -append "$2" -serial "file:$3" -display none -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    return $?
}

BASIS="osum nokbd nofs"
APPEND="$BASIS hv gastlauf gastmess gastcr"

# ------------------------------------------------------------ Abschnitt 0
#
# Was die Umgebung ueberhaupt kann. Diese Zusagen stehen VOR allem
# anderen, denn sie sind der Grund fuer die Bauart dieser Runde. Wer sie
# ueberspringt, baut ins Blaue.
echo "== 0. was diese Umgebung ueberhaupt kann =="

probe_feature() { # feature datei
    ( qemu-system-x86_64 -accel tcg -machine q35 -cpu "qemu64,+$1" \
        -display none -serial none -monitor none -S -no-reboot \
        > "$2" 2>&1 & echo $! > "$TMPD/pid" )
    sleep 1.5
    kill "$(cat "$TMPD/pid")" 2>/dev/null
    sleep 0.2
}

probe_feature vmx "$TMPD/vmx.txt"
if grep -qa "TCG doesn't support requested feature: CPUID.01H:ECX.vmx" "$TMPD/vmx.txt"; then
    ok "TCG kann VT-x NICHT -- das ist der Grund, warum diese Runde AMD-V ist"
else
    bad "TCG meldet vmx nicht mehr als fehlend -- die Begruendung dieser Runde pruefen"
    head -3 "$TMPD/vmx.txt" | sed 's/^/        /'
fi

probe_feature svm "$TMPD/svm.txt"
if grep -qa "doesn't support requested feature" "$TMPD/svm.txt"; then
    bad "TCG kann SVM nicht mehr -- dann ist diese Runde nicht messbar"
else
    ok "TCG kann SVM -- die Grundlage dieser Runde"
fi

# Die beiden Zahlen, die zusammengehoeren MUESSEN: der Datenbereich steht
# in `boot.s` UND in `kstate.fi`. Runde K12 hat ihn wachsen lassen, weil
# er voll war -- geht das auseinander, nullt der Kernel weniger, als er
# benutzt, und der Fehler zeigt sich irgendwo ganz anders.
KB=$(grep -oE 'KDATA_SIZE, 0x[0-9A-Fa-f]+' kernel/arch/x86_64/boot.s | grep -oE '0x[0-9A-Fa-f]+')
KS=$(grep -oE 'KDATA_SIZE: u64 = 0x[0-9A-Fa-f]+' kernel/kstate.fi | grep -oE '0x[0-9A-Fa-f]+$')
[ "$KB" = "$KS" ] && ok "kdata ist in boot.s und kstate.fi dieselbe Zahl ($KB)" \
    || bad "kdata: boot.s sagt $KB, kstate.fi sagt $KS"

python3 tools/kernel/karte.py kernel > "$TMPD/karte.txt" 2>&1 \
    && ok "die Karte von kdata ist ueberschneidungsfrei ($(tail -1 "$TMPD/karte.txt"))" \
    || { bad "die Karte von kdata kollidiert"; sed 's/^/        /' "$TMPD/karte.txt" | head -6; }

# Die Zusagen, die der Kernel selbst meldet. Sie stehen hier im
# KLARTEXT, damit eine geloeschte oder umbenannte Zusage auffaellt und
# nicht nur eine kleinere Gesamtzahl.
ZUSAGEN=(
 "the processor can do svm"
 "svm switched on, rc = 0"
 "it can do nested page tables"
 "guest 1 signed off with 0x1234"
 "guest 1 was told the host's cpu name"
 "guest 1 sees the hypervisor bit in cpuid 1"
 "guest 1 read the pattern through the npt"
 "guest 1 took the interrupt the host threw"
 "guest 1 printed through a port it has"
 "guest 2 signed off with 0x2222"
 "guest 2 read back through its OWN page table"
 "guest 2 really turned on pe and paging"
 "guest 2 runs on its own cr3 0x2000"
 "guest 4 signed off with 0x3333"
 "guest 4 read back what it wrote after the npf"
 "the host laid a frame under it on demand"
 "guest 5 still reported 0x4444 before it"
 "guest 5 was shut down by a triple fault"
 "and the host's syscall path is untouched"
 "the host took the runaway guest's processor"
 "and the runaway guest counted onwards"
 "every frame of every guest came back"
)

for stufe in 0 1; do
    echo "== Stufe $stufe: firnc$stufe =="
    IMG="$TMPD/osum$stufe.mb"
    if ! bash tools/build-kernel.sh "$IMG" --stufe "$stufe" > "$TMPD/build$stufe.log" 2>&1; then
        bad "firnc$stufe: der Kernel laesst sich nicht bauen"
        sed 's/^/        /' "$TMPD/build$stufe.log" | head -10
        continue
    fi
    ok "firnc$stufe: Kernel gebaut ($(stat -c%s "$IMG") Oktette)"

    OUT="$TMPD/hv$stufe.txt"
    rc=0
    run_kernel "$IMG" "$APPEND" "$OUT" 200 || rc=$?
    if [ "$rc" -eq 21 ]; then
        ok "firnc$stufe: der Kernel beendet sich selbst (21), keine Ausnahme"
    else
        bad "firnc$stufe: Beendigungscode $rc, erwartet 21"
        tail -20 "$OUT" | sed 's/^/        /'
        continue
    fi

    # 1. Jede einzelne Zusage des Kernels, im Klartext nachgelesen.
    for z in "${ZUSAGEN[@]}"; do
        has "$OUT" "hv: OK  $z" "firnc$stufe: $z"
    done
    hasnot "$OUT" "hv: BAD" "firnc$stufe: keine einzige Zusage ist rot"

    # 2. DER GAST HAT WIRKLICH GEREDET. Der Text kommt aus dem Gast durch
    #    einen Anschluss, den es fuer ihn nicht gibt, und der Wirt hat ihn
    #    Oktett fuer Oktett abgefangen und weitergereicht.
    has "$OUT" "gast| hallo vom gast" \
        "firnc$stufe: der Gast hat durch einen Anschluss geredet, den es nicht gibt"

    # 3. DIE AUSTRITTE, NACH GRUND GEZAEHLT. Das ist die Zeile, die diese
    #    Runde ausmacht: nicht "es lief", sondern wie oft und weswegen.
    num "firnc$stufe: cpuid-Austritte"           "$(feld "$OUT" cpuid)"    eq 2
    num "firnc$stufe: Anschluss-Austritte"       "$(feld "$OUT" ioio)"     eq 16
    num "firnc$stufe: vmmcall-Austritte"         "$(feld "$OUT" vmmcall)"  gt 500
    num "firnc$stufe: Seitenfehler des Gasts"    "$(feld "$OUT" npf)"      eq 1
    num "firnc$stufe: Dreifachfehler"            "$(feld "$OUT" shutdown)" eq 1
    num "firnc$stufe: Steuerregister-Austritte"  "$(feld "$OUT" crwr)"     eq 3
    num "firnc$stufe: Unterbrechungen des Wirts" "$(feld "$OUT" intr)"     gt 8
    num "firnc$stufe: kein zurueckgewiesener Eintritt" "$(feld "$OUT" err)"   eq 0
    num "firnc$stufe: kein unbehandelter Grund"  "$(feld "$OUT" other)"    eq 0
    num "firnc$stufe: Austritte insgesamt"       "$(feld "$OUT" total)"    gt 600

    # 4. KEIN RAHMEN GEHT VERLOREN. Ein Wirt, der bei jeder Gastmaschine
    #    Rahmen liegen laesst, ist ein Wirt mit einem Leck -- und ein Leck
    #    sieht man nur, wenn man zaehlt.
    num "firnc$stufe: kein Rahmen verloren" "$(feld "$OUT" leak)" eq 0

    # 5. WAS EIN AUSTRITT KOSTET. Die Zahl ist eine Zahl UNTER QEMUs
    #    Softwareemulation und keine Aussage ueber echte Hardware; was sie
    #    beweist, ist, dass gemessen wurde und nicht geschaetzt.
    num "firnc$stufe: der Preis eines Austritts ist gemessen" \
        "$(feld "$OUT" per-exit)" gt 0
    echo "        bench: $(grep -a '^hv: bench' "$OUT" | tail -1 | sed 's/^hv: //')"
    echo "        exits: $(grep -a '^hv: exits' "$OUT" | tail -1 | sed 's/^hv: //')"
    echo "        cpu:   $(grep -a '^hv: cpu' "$OUT" | tail -1 | sed 's/^hv: //')"

    # 6. RING 3. Vierzehn Zusagen aus einem Programm ohne Sonderrechte.
    has "$OUT" "hvuser: 14 / 14" "firnc$stufe: Ring 3 fuehrt eine Gastmaschine, 14/14"
    has "$OUT" "hv: ring 3 exit=0" "firnc$stufe: und meldet es mit seinem Beendigungscode"
    num "firnc$stufe: Ring 3 sah die Austritte des Gasts" \
        "$(grep -aoE 'hvuser: exits=[0-9]+' "$OUT" | tail -1 | cut -d= -f2)" gt 10
    # Das Muster, das der Gast durch die verschachtelte Seitentabelle
    # gelesen hat, ist bis nach Ring 3 durchgekommen -- ohne dass dieses
    # Programm je eine physische Adresse in der Hand gehabt haette.
    num "firnc$stufe: das NPT-Muster kam bis nach Ring 3" \
        "$(grep -aoE 'hvuser: value=[0-9]+' "$OUT" | tail -1 | cut -d= -f2)" eq 23130

    # 7. DER UEBRIGE KERNEL IST DERSELBE.
    has "$OUT" "kernel: done" "firnc$stufe: der Kernel laeuft bis zum Ende durch"
done

# ------------------------------------------------------- die Gegenproben
echo "== die Gegenproben =="

# A. OHNE DAS WORT `hv` PASSIERT NICHTS. Eine Zeile, sonst nichts -- und
#    der uebrige Kernel verhaelt sich Zeile fuer Zeile wie vorher.
OFF="$TMPD/off.txt"
rc=0
run_kernel "$TMPD/osum0.mb" "$BASIS" "$OFF" 150 || rc=$?
[ "$rc" -eq 21 ] && ok "ohne 'hv': der Kernel beendet sich selbst (21)" \
    || bad "ohne 'hv': Beendigungscode $rc statt 21"
has    "$OFF" "hv: skipped" "ohne 'hv': genau die eine Zeile"
hasnot "$OFF" "hv: OK" "ohne 'hv': keine einzige Zusage"
hasnot "$OFF" "gast|" "ohne 'hv': kein Gast hat geredet"
hasnot "$OFF" "hvuser:" "ohne 'hv': kein Programm in Ring 3"
has    "$OFF" "kernel: done" "ohne 'hv': der uebrige Kernel ist unberuehrt"

# B. OHNE VERSCHACHTELTE SEITENTABELLEN BRICHT ALLES ZUSAMMEN. Der Gast
#    hat dann keinen eigenen physischen Adressraum: er laeuft unmittelbar
#    im Speicher des WIRTS, faengt an, dort Unfug auszufuehren, und kommt
#    nie zurueck. Genau das ist der Beweis, dass die Uebersetzung nicht
#    beilaeufig ist, sondern alles traegt.
NPT="$TMPD/nonpt.txt"
rc=0
run_kernel "$TMPD/osum0.mb" "$BASIS hv nonpt" "$NPT" 25 || rc=$?
if [ "$rc" -eq 124 ]; then
    ok "GEGENPROBE nonpt: ohne NPT kommt der erste Gast nie zurueck (Zeitlimit)"
else
    bad "GEGENPROBE nonpt: Beendigungscode $rc -- erwartet war der Zusammenbruch (124)"
fi
has    "$NPT" "hv: OK  it can do nested page tables" "nonpt: bis dahin lief alles"
hasnot "$NPT" "guest 1 signed off" "nonpt: aber KEIN Gast meldet sich mehr ab"

# C. OHNE V_INTR_MASKING GEHOERT DIE MASCHINE DEM GAST. Der Laeufer sagt
#    `cli` und dreht sich im Kreis. MIT V_INTR_MASKING holt der Zeitgeber
#    des Wirts ihn ein (oben gemessen). OHNE es entscheidet das Flag DES
#    GASTS ueber die physische Unterbrechung -- und der Gast hat es zu.
FREI="$TMPD/gastfrei.txt"
rc=0
run_kernel "$TMPD/osum0.mb" "$BASIS hv gastlauf gastfrei" "$FREI" 25 || rc=$?
if [ "$rc" -eq 124 ]; then
    ok "GEGENPROBE gastfrei: ohne V_INTR_MASKING behaelt der Laeufer den Prozessor"
else
    bad "GEGENPROBE gastfrei: Beendigungscode $rc -- erwartet war 124"
fi
hasnot "$FREI" "the host took the runaway guest" "gastfrei: der Wirt holt ihn NICHT ein"

# D. OHNE EFER.SVME GIBT ES NICHTS DAVON.
NOS="$TMPD/nosvm.txt"
rc=0
run_kernel "$TMPD/osum0.mb" "$BASIS hv nosvm" "$NOS" 150 || rc=$?
[ "$rc" -eq 21 ] && ok "GEGENPROBE nosvm: der Kernel lebt auch ohne SVM (21)" \
    || bad "GEGENPROBE nosvm: Beendigungscode $rc statt 21"
has    "$NOS" "counter-check nosvm: SVM stays off" "nosvm: der Kernel sagt es selbst"
hasnot "$NOS" "hv: guest" "nosvm: keine einzige Gastmaschine"
hasnot "$NOS" "gast|" "nosvm: kein Gast hat geredet"

# E. UND DIE UMGEBUNG SELBST: mit `-cpu qemu64` meldet CPUID KEINE
#    verschachtelten Seitentabellen. Der Wirt muss das SAGEN und darf
#    nicht behaupten, er koenne es. (Dass QEMU die Tabellen dann
#    trotzdem benutzt, wenn man NP_ENABLE setzt, ist eine Eigenheit von
#    QEMU und keine Zusage dieses Kernels -- deshalb wird hier nur die
#    Auskunft geprueft und nicht der Zusammenbruch.)
Q64="$TMPD/qemu64.txt"
rc=0
timeout 150 qemu-system-x86_64 -kernel "$TMPD/osum0.mb" -cpu qemu64 -m 256 \
    -append "$BASIS hv" -serial "file:$Q64" -display none -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 21 ] && ok "GEGENPROBE -cpu qemu64: der Kernel lebt (21)" \
    || bad "GEGENPROBE -cpu qemu64: Beendigungscode $rc statt 21"
has "$Q64" "np=no" "-cpu qemu64: der Wirt MELDET, dass CPUID keine NPT anbietet"
has "$Q64" "hv: BAD it can do nested page tables" \
    "-cpu qemu64: und die Zusage darueber wird ROT, statt stillzuschweigen"

# F. DAS WORT MUSS EIN WORT SEIN -- und das ist keine Feinheit, sondern
#    ein Fehler, den Gegenprobe A dieser Runde WIRKLICH GEFUNDEN hat.
#
#    QEMU stellt der Multiboot-Kommandozeile den PFAD DES ABBILDS voran:
#
#      mb: flags=0x24f  cmd=/tmp/tmp.aBhvXk12/osum0.mb osum nokbd nofs
#
#    Die Laeufer bauen in ein Verzeichnis aus `mktemp -d`, und dessen
#    Name ist zufaellig. Enthielt er die zwei Buchstaben `hv`, fand die
#    urspruengliche Teilzeichenkettensuche das Wort dieser Runde IM PFAD
#    -- und der Kernel schaltete den Hypervisor ein, obwohl auf der
#    Kommandozeile nichts davon stand. Gegenprobe A wurde rot, weil der
#    Kernel 20 Zusagen meldete, wo er haette schweigen sollen.
#
#    Von hier an wird genau das gemessen, statt sich auf den Zufall zu
#    verlassen: das Abbild wird in ein Verzeichnis gelegt, dessen Name
#    die zwei Buchstaben ENTHAELT, und der Kernel muss trotzdem schweigen.
WORTDIR="$TMPD/ein-pfad-mit-hv-darin"
mkdir -p "$WORTDIR"
cp "$TMPD/osum0.mb" "$WORTDIR/k.mb"
WORT="$TMPD/wort.txt"
rc=0
timeout 150 qemu-system-x86_64 -kernel "$WORTDIR/k.mb" -cpu "$CPU" -m 256 \
    -append "$BASIS" -serial "file:$WORT" -display none -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 21 ] && ok "das Wort ist ein WORT: der Kernel lebt (21)" \
    || bad "das Wort ist ein WORT: Beendigungscode $rc statt 21"
grep -qa "cmd=$WORTDIR" "$WORT" \
    && ok "der Pfad mit 'hv' darin steht wirklich in der Kommandozeile" \
    || bad "der Pfad steht nicht in der Kommandozeile -- die Probe misst nichts"
has    "$WORT" "hv: skipped" "und der Kernel schweigt trotzdem"
hasnot "$WORT" "hv: OK" "kein Wort im Pfad hat die Runde eingeschaltet"

# Und die Gegenprobe zur Gegenprobe: MIT dem Wort auf der Kommandozeile
# laeuft aus DEMSELBEN Pfad alles.
WORT2="$TMPD/wort2.txt"
rc=0
timeout 200 qemu-system-x86_64 -kernel "$WORTDIR/k.mb" -cpu "$CPU" -m 256 \
    -append "$BASIS hv" -serial "file:$WORT2" -display none -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 21 ] && ok "mit dem Wort laeuft aus demselben Pfad alles (21)" \
    || bad "mit dem Wort: Beendigungscode $rc statt 21"
has "$WORT2" "hv: OK  every frame of every guest came back" \
    "und zwar vollstaendig"

echo
echo "HV: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
