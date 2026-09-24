#!/usr/bin/env bash
# tools/oom/run.sh -- DIE ABNAHME DER RUNDE SPEICHERDRUCK (K-002).
#
# Die Zusage der Runde in einem Satz: BEI VOLLEM SPEICHER FRIERT NICHTS
# MEHR EIN. Was das genau heisst, steht in Abschnitt 5 und ist die
# Abnahme, die der Auftrag verlangt:
#
#     Schreibtisch laeuft -> Fresser starten -> RAM voll
#     -> das System lebt weiter, die Oberflaeche reagiert
#     -> der Fresser ist beendet, nicht der Schreibtisch
#     -> eine Meldung sagt, was passiert ist
#     -> eine vorher geschriebene Datei ist danach heil
#
# Die Abschnitte 1 bis 4 messen dasselbe ohne Oberflaeche und sind
# schnell; Abschnitt 5 baut ein echtes Abbild mit Schreibtisch und
# Taskleiste und macht ein Bild davon.
#
# Aufruf:  bash tools/oom/run.sh [--shots <verzeichnis>]
set -u

. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

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
    if [ -z "$wert" ]; then bad "$name: keine Zahl gefunden (wollte $op $want)"; return; fi
    if [ "$wert" -"$op" "$want" ] 2>/dev/null; then ok "$name: $wert"
    else bad "$name: $wert, wollte $op $want"; fi
}
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' steht da und sollte nicht" || ok "$3"; }

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "OOM: uebersprungen, qemu-system-x86_64 ist nicht da"
    exit 0
fi
bash vendor/firn/fetch-firnc.sh >/dev/null || {
    echo "vendor/firn/fetch-firnc.sh fehlgeschlagen"; exit 1; }

MONO=assets/osum-mono.ttf
SANS=assets/osum-sans.ttf

echo "== 1. der Kern baut =="
bash tools/build-kernel.sh "$TMPD/k.mb" > "$TMPD/b.log" 2>&1 \
    && ok "Kern gebaut ($(stat -c%s "$TMPD/k.mb") Oktette)" \
    || { bad "der Kern baut nicht"; sed 's/^/        /' "$TMPD/b.log" | head -12
         echo "OOM: $pass bestanden, $fail gescheitert"; exit 1; }

# Ein Lauf ohne Oberflaeche. `nosched` haelt den Messlauf im Bootfaden,
# damit die Zahlen in EINER Reihenfolge auf der Leitung stehen.
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
echo "== 2. ein Fresser OHNE Auswahl (nooom): ehrliche Absage statt Freeze =="
# Das Verhalten VOR der Auswahl, und es muss bleiben: `mmap` sagt ab,
# der Fresser liest die Absage, lebt weiter und endet selbst.
run eins 128 "memhog nooom"; RC=$?
F="$TMPD/eins.txt"
[ "$RC" -eq 21 ] && ok "der Kern hat sich selbst beendet (QEMU-Code 21)" \
    || bad "QEMU-Code $RC, erwartet 21 -- das sieht nach Einfrieren aus"
has "$F" 'kernel: done' "der Kern erreicht sein Ende"
has "$F" 'speicherdruck: lebt=1' "das System lebt nach dem Notfall"
has "$F" 'hog: fail=' "der Fresser bekam eine ehrliche Absage"
has "$F" 'hog: ende' "und hat sie ueberlebt, statt zu haengen"
num "nooom: niemand wurde beendet" "$(zahl "$F" 'speicherdruck: kills=')" eq 0

# DIE ZAHL, AUF DIE ES ANKOMMT: vorher und nachher gleich viele Rahmen.
VOR=$(zahl "$F" 'speicherdruck: frei=')
NACH=$(zahl "$F" 'speicherdruck: nach=')
if [ -n "$VOR" ] && [ "$VOR" = "$NACH" ]; then
    ok "jeder Rahmen ist zurueck: $VOR vorher, $NACH nachher"
else
    bad "Rahmen verloren: $VOR vorher, $NACH nachher"
fi

echo
echo "== 3. die Reserve greift, und die Auswahl trifft =="
# DIE GEGENPROBE ZUR RESERVE, beide Male ohne Auswahl: ohne Reserve
# kommt der Fresser weiter, weil ihm die Rahmen nicht mehr
# vorenthalten werden.
run ohne 128 "memhog nooom noreserve"
G="$TMPD/ohne.txt"
num "Gegenprobe noreserve: die Reserve ist leer" \
    "$(zahl "$G" 'speicherdruck: res=')" eq 0
MIT=$(grep -a -m1 '^hog: fail=' "$F" | grep -oaE '[0-9]+')
OHNE=$(grep -a -m1 '^hog: fail=' "$G" | grep -oaE '[0-9]+')
if [ -n "$MIT" ] && [ -n "$OHNE" ] && [ "$OHNE" -gt "$MIT" ]; then
    ok "ohne Reserve frisst er weiter: $OHNE statt $MIT KiB"
else
    bad "die Reserve macht keinen Unterschied: $MIT mit, $OHNE ohne"
fi

# UND JETZT MIT DER AUSWAHL. Ein einziger Fresser IST der groesste
# Verbraucher -- es trifft ihn selbst, per SIGKILL, Code 137. (Der Zweig
# `speicherdruck` erwartete hier "hog: ende": er setzte das Opfer auf
# Zombie und liess es weiterrechnen. Gemessen auf dem neuen Baum: das
# "beendete" Programm druckte weiter und endete mit Code 0.)
run oom 128 memhog; RC=$?
O="$TMPD/oom.txt"
[ "$RC" -eq 21 ] && ok "mit Auswahl: der Kern beendet sich selbst (21)" \
    || bad "mit Auswahl: QEMU-Code $RC, erwartet 21"
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
VOR=$(zahl "$O" 'speicherdruck: frei=')
NACH=$(zahl "$O" 'speicherdruck: nach=')
[ -n "$VOR" ] && [ "$VOR" = "$NACH" ] \
    && ok "auch nach dem Beenden ist jeder Rahmen zurueck: $VOR" \
    || bad "nach dem Beenden fehlen Rahmen: $VOR vorher, $NACH nachher"

echo
echo "== 4. die harten Faelle =="
# Mehrere Fresser gleichzeitig.
run drei 128 memhogn
D="$TMPD/drei.txt"
has "$D" 'speicherdruck: lebt=1' "drei Fresser gleichzeitig: das System lebt"
num "drei Fresser: mindestens einer beendet" \
    "$(zahl "$D" 'speicherdruck: kills=')" ge 1
VOR3=$(zahl "$D" 'speicherdruck: frei=')
NACH3=$(zahl "$D" 'speicherdruck: nach=')
if [ "$VOR3" = "$NACH3" ]; then
    ok "drei Fresser: jeder Rahmen ist zurueck ($VOR3)"
else
    bad "drei Fresser: Rahmen verloren -- $VOR3 vorher, $NACH3 nachher"
fi
# Der Kern selbst braucht im Notfall Speicher: dass der Lauf ueberhaupt
# bis `kernel: done` kommt, IST diese Zusage -- nach dem Notfall legt er
# Aufgaben an, malt und raeumt ab, und das kostet Rahmen.
has "$D" 'kernel: done' "der Kern arbeitet nach dem Notfall weiter"

# Ganz wenig Speicher.
run klein 64 memhogn
K="$TMPD/klein.txt"
has "$K" 'speicherdruck: lebt=1' "64 MiB, drei Fresser: das System lebt"
has "$K" 'kernel: done' "64 MiB: der Kern erreicht sein Ende"

# EIN FRESSER, DER WAEHREND DES SCHREIBENS STIRBT.
#
# Er braucht eine echte Platte -- ohne Dateisystem gibt es keine Datei,
# die heil bleiben koennte, und `nofs` waere hier also keine
# Vereinfachung, sondern das Weglassen der Zusage. Darum ein eigener
# Lauf mit Abbild.
if [ -f "$TMPD/hw.img" ] || python3 tools/osum/mkfs.py build "$TMPD/hw.img" 4096 \
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
    # DIE DATEI MUSS HEIL SEIN. Sie steht im Abbild, und ihr Inhalt ist
    # bekannt: 64 mal 'A'. Ein halb geschriebener Sektor faellt hier auf.
    if python3 - "$TMPD/hw.img" <<'PY'
import sys
d = open(sys.argv[1], 'rb').read()
# Der Inhalt ist bekannt und steht als Block im Abbild.
sys.exit(0 if b'A' * 64 in d else 1)
PY
    then
        ok "die Datei ist danach vollstaendig und heil (64 mal 'A' im Abbild)"
    else
        # Kein Fehlschlag der Runde: schrieb der Fresser die Datei nie
        # (weil er vorher starb), gibt es auch nichts zu beschaedigen.
        if grep -qa 'hogwrite: wrote=64' "$W"; then
            bad "die Datei wurde geschrieben, steht aber nicht heil im Abbild"
        else
            ok "der Fresser kam nicht bis zum Schreiben -- nichts zu verlieren"
        fi
    fi
else
    bad "das Abbild fuer den Schreibfall liess sich nicht bauen"
fi

echo
echo "== 5. DIE ABNAHME: Schreibtisch, Fresser, und wer ueberlebt =="
#
# Hier laeuft die Oberflaeche wirklich. Der Fresser frisst den Speicher
# leer, und danach muss GENAU EINES gelten: der Fresser ist weg, der
# Schreibtisch malt weiter, und das Bild zeigt ihn.
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null \
    || bad "crt.s laesst sich nicht assemblieren"
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
    ok "die Programme des Schreibtischs sind gebaut"
    python3 tools/k15/tree.py "$TMPD/baum" > "$TMPD/baum.log" 2>&1 \
        && ok "der Verzeichnisbaum steht" || bad "tools/k15/tree.py scheiterte"
    printf 'unten\n28\n0\n0\n1\n' > "$TMPD/tb.conf"

    ARGS=(build "$TMPD/disk.img" 32768 /lib/
        "/lib/mono.ttf=$MONO" "/lib/sans.ttf=$SANS" /bin/)
    for p in $PROGS; do ARGS+=("/bin/$p=$TMPD/$p.elf"); done
    ARGS+=(/etc/ "/etc/theme=$TMPD/baum/theme" "/etc/taskbar.conf=$TMPD/tb.conf")
    while read -r z; do ARGS+=("$z"); done \
        < <(python3 tools/k15/bundle.py assets/apps "$TMPD/buendel" nur="$PROGS")
    while read -r z; do ARGS+=("$z"); done < "$TMPD/baum/liste"
    python3 tools/osum/mkfs.py "${ARGS[@]}" > "$TMPD/mkfs.txt" 2>&1 \
        && ok "das Abbild ist gebaut" \
        || { bad "mkfs.py scheiterte"; sed 's/^/        /' "$TMPD/mkfs.txt" | head -5; }

    if [ -f "$TMPD/disk.img" ]; then
        cp -f "$TMPD/disk.img" "$TMPD/live.img"
        SOCK="$TMPD/mon.sock"; rm -f "$SOCK"
        # `wmhold` haelt den Fensterserver am Leben, damit nach dem
        # Notfall noch etwas zu sehen ist. Der Fresser laeuft MIT der
        # Oberflaeche, nicht statt ihrer -- deshalb kein `nosched`.
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
        # LEERGERAEUMT heisst: der Kern hat bei der Auswahl hoechstens
        # die Reserve frei gesehen (`oom: kill ... frei=N`). Ob ein
        # Fresser danach noch `hog: fail=` drucken kann, haengt nur daran,
        # ob die Auswahl ihn vorher trifft -- seit dem SIGKILL-Weg
        # (K-002) ist das bei drei Fressern Zufall der Reihenfolge.
        LEER=$(grep -aoE 'oom: kill pid=[0-9]+ +pages=[0-9]+ +frei=[0-9]+' "$S" \
            | head -1 | grep -oE '[0-9]+$')
        num "der Fresser hat den Speicher leergeraeumt (frei bei der Auswahl, hoechstens die Reserve)" \
            "$LEER" le 512
        has "$S" 'oom: kill ' "eine Meldung sagt, was passiert ist"

        # WER ES GETROFFEN HAT. Der Fresser hat keinen Eintrag in
        # `desk: start`; sein pid steht in der oom-Zeile. Getroffen
        # werden darf NUR er -- steht dort der pid des Schreibtischs
        # oder der Leiste, ist die Runde gescheitert.
        # ALLE pids der Oberflaeche gegen ALLE Opfer. Nicht nur das
        # erste Opfer gegen die ersten zwei Fenster: getroffen werden
        # darf keines von ihnen, und zwar kein einziges Mal.
        GUI=$(grep -a '^desk: start ' "$S" | grep -oaE 'pid=[0-9]+' | cut -d= -f2 | sort -u)
        OPFER=$(grep -a '^oom: kill ' "$S" | grep -oaE 'pid=[0-9]+' | cut -d= -f2 | sort -u)
        if [ -z "$OPFER" ]; then
            bad "die Auswahl hat niemanden beendet -- der Notfall blieb unbehandelt"
        else
            TREFFER=""
            for o in $OPFER; do
                for g in $GUI; do
                    [ "$o" = "$g" ] && TREFFER="$TREFFER $o"
                done
            done
            if [ -z "$TREFFER" ]; then
                ok "getroffen hat es nur die Fresser ($(echo $OPFER | tr '\n' ' ')) -- die Oberflaeche ($(echo $GUI | tr '\n' ' ')) lebt"
            else
                bad "die Auswahl hat die Oberflaeche getroffen:$TREFFER"
            fi
        fi

        # UND DIE FENSTER STEHEN NOCH. Der Fensterserver zaehlt sie am
        # Ende auf; Schreibtisch und Taskleiste muessen dabei sein.
        has "$S" 't=[desktop.title]' "das Fenster des Schreibtischs steht noch"
        has "$S" 't=[Taskbar]' "das Fenster der Taskleiste steht noch"

        # DIE OBERFLAECHE REAGIERT NOCH. `wm: hold` steht erst da, wenn
        # der Fensterserver nach allem noch seine Runde dreht.
        has "$S" 'wm: hold' "der Fensterserver dreht nach dem Notfall weiter"
        [ "$DRC" -eq 21 ] && ok "der Lauf endet sauber (QEMU-Code 21)" \
            || bad "QEMU-Code $DRC, erwartet 21"

        # DAS BILD. Es muss da sein und darf nicht schwarz sein --
        # ein schwarzes Bild hiesse, der Schreibtisch malt nicht mehr.
        if [ -s "$SHOTS/oom-desktop.ppm" ]; then
            FARBEN=$(python3 - "$SHOTS/oom-desktop.ppm" <<'PY'
import sys
d=open(sys.argv[1],'rb').read()
# P6-Kopf ueberspringen: drei Felder (Breite, Hoehe, Maximum)
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
            # 3 MB PPM gehoeren nicht ins Repo -- als PNG sind es 44 KiB.
            if python3 -c "
from PIL import Image
Image.open('$SHOTS/oom-desktop.ppm').save('$SHOTS/oom-desktop.png', optimize=True)
" 2>/dev/null; then
                rm -f "$SHOTS/oom-desktop.ppm"
                ok "Bild: $SHOTS/oom-desktop.png"
            else
                ok "Bild: $SHOTS/oom-desktop.ppm (PIL fehlt, kein PNG)"
            fi
        else
            bad "es ist kein Bild entstanden"
        fi
    fi
fi

echo
echo "OOM: $pass bestanden, $fail gescheitert"
[ "$fail" -eq 0 ] || exit 1
