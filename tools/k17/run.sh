#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/k17/run.sh -- DER BEWEIS, DASS OSUM USB KANN.
#
# Bis zu dieser Runde hatte Osum zwei Eingabegeraete, und beide haengen am
# 8042: die Tastatur an IRQ 1 (Runde 59) und die Maus an IRQ 12 (Runde
# K10). Auf einem Laptop von 2026 gibt es diesen Baustein nicht mehr. Im
# Kopf von `kernel/ps2m.fi` steht seit K10 der Satz, der diese Runde
# ausgeloest hat: "Ein USB-HID-Weg braucht davor einen xHCI-Treiber,
# Endpunkte, Deskriptoren und eine Warteschlange; das ist eine Runde fuer
# sich."
#
# WAS HIER GEMESSEN WIRD, UND WARUM SO:
#
#   1. DIE TASTATUR WIRD ZWEIMAL GEMESSEN, MIT DEMSELBEN TEST. Einmal
#      mit `-device usb-kbd`, einmal mit dem PS/2-Geraet -- dieselbe
#      Folge von `sendkey`-Befehlen aus dem QEMU-Monitor, dieselbe
#      Shell, dasselbe Plattenabbild. Danach werden die `key:`-Zeilen
#      und der Mitschnitt der Shell OKTETT FUER OKTETT verglichen. Das
#      ist die eigentliche Zusage dieser Runde: nicht "USB liefert
#      Zeichen", sondern "USB liefert DIESELBEN Zeichen".
#      UND DAZU DER GEGENBEWEIS, dass in Lauf A wirklich USB geliefert
#      hat: `usb: keys=N` zaehlt NUR die Tasten, die durch `usb.press`
#      gegangen sind. Ohne diese Zahl waere der Vergleich wertlos --
#      QEMU koennte die Tasten in beiden Laeufen an den PS/2-Regler
#      geschickt haben, und beide Seiten waeren gleich UND falsch.
#   2. DIE LEHRE AUS B3: EIN VERGLEICH ZWEIER LEERER SEITEN IST KEIN
#      TEST. Vor jedem Oktettvergleich wird geprueft, dass BEIDE Seiten
#      nicht leer sind und mindestens so viele Zeilen haben, wie sie
#      haben muessen. Ist eine leer, faellt die Zusage -- sie wird
#      ausdruecklich NICHT als bestanden gezaehlt.
#   3. DIE LEHRE AUS K7B: NICHT STATISTISCH MESSEN. Hier wird nichts
#      gegen eine Flaeche gerechnet. Der Zeiger steht nach zehn
#      Bewegungen an EINEM Punkt, und der Punkt ist ausgerechnet, nicht
#      geschaetzt: mx=200, my=120, mclk=1.
#   4. DER STICK WIRD VON AUSSEN NACHGELESEN. Das Abbild kommt von
#      `mkfs.vfat` und `sfdisk`, die Datei darin von `mcopy`. Osum liest
#      sie und schreibt eine eigene -- und danach holt `mtools` auf dem
#      WIRT diese Datei wieder heraus und `cmp` vergleicht sie. "Das
#      Schreiben hat keinen Fehler gemeldet" ist keine Messung.
#   5. ABZIEHEN IM BETRIEB. Ein Deskriptor bleibt OFFEN, das Geraet
#      verschwindet, und danach MUSS jeder Zugriff -ENODEV geben --
#      und der Prozess, der ihn gemacht hat, MUSS weiterlaufen und auf
#      der Wurzel weiterschreiben koennen. Gemessen aus Ring 3
#      (`/bin/k17`), nicht aus dem Mitschnitt des Kerns.
#   6. JEDE ZUSAGE HAT EINE GEGENPROBE. `nousb` (gar kein Baum),
#      `nohid` (kein Eingabetreiber), `nomsc` (kein Blockgeraet),
#      `usbnoirq` (der Meldevektor bleibt maskiert -- die Uebertragung
#      laeuft, die Meldung nicht, und keine Taste kommt an), `usbpoll`
#      (derselbe maskierte Vektor, aber der Kern sieht selbst nach --
#      und die Ereignisse kommen trotzdem an), ein Lauf ohne `-device
#      qemu-xhci`, einer ohne Geraete daran und einer ohne das Wort
#      `usb`.
#
# Gemessen wie in den Runden 59 bis K16: QEMU je Fall, mit Zeitlimit,
# serielle Ausgabe gegen Erwartungen, Beendigungscode aus
# `isa-debug-exit` (21 = der Kernel hat sich selbst beendet).
#
# Aufruf:  bash tools/k17/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
FC1=${FIRNC1:-vendor/firn/bin/firnc1}
ULD=kernel/user/user.ld
BLOCKS=4096
PROGS="sh cat echo ls cp rm mkdir wc grep head true false ps mount umount k17"

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

num() { # name wert op soll
    if [ -z "${2:-}" ]; then bad "$1: keine Zahl gefunden (erwartet $3 $4)"; return; fi
    if [ "$2" -"$3" "$4" ] 2>/dev/null; then ok "$1: $2"
    else bad "$1: $2, erwartet $3 $4"; fi
}
gleich() { # name soll ist
    if [ "$2" = "$3" ]; then ok "$1 ($2)"
    else
        bad "$1"
        printf '        soll: %s\n' "$(printf '%s' "$2" | head -c 300)"
        printf '        ist : %s\n' "$(printf '%s' "$3" | head -c 300)"
    fi
}
hat() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hat_nicht() { grep -qaF "$2" "$1" && bad "$3 -- '$2' steht da und sollte nicht" || ok "$3"; }

# ZWEI DATEIEN VERGLEICHEN -- UND ZUERST PRUEFEN, DASS SIE NICHT LEER
# SIND. Das ist die Lehre aus Runde B3 in ihrer pruefbaren Form: ein
# `cmp` ueber zwei leere Dateien geht immer durch und sagt nichts. Die
# Mindestzahl von Zeilen steht deshalb als Argument da, und eine zu
# kurze Seite laesst die Zusage FALLEN statt sie zu bestehen.
gleiche_datei() { # name a b mindestzeilen
    local na nb
    na=$(wc -l < "$2" 2>/dev/null || echo 0)
    nb=$(wc -l < "$3" 2>/dev/null || echo 0)
    if [ "${na:-0}" -lt "$4" ] || [ "${nb:-0}" -lt "$4" ]; then
        bad "$1 -- eine Seite ist zu kurz ($na und $nb Zeilen, mindestens $4)"
        return
    fi
    if cmp -s "$2" "$3"; then
        ok "$1 ($na Zeilen, Oktett fuer Oktett)"
    else
        bad "$1"
        diff "$2" "$3" | head -8 | sed 's/^/        /'
    fi
}

# Eine Zahl aus einer `k17: name = zahl`-Zeile von /bin/k17.
wert() { grep -a -m1 "^k17: $2 = " "$1" 2>/dev/null | sed 's/.* = //' | tr -d '\r\000'; }
sagt() { # datei name soll beschreibung
    local got
    got=$(wert "$1" "$2")
    if [ -z "$got" ]; then bad "$4 -- keine Zeile 'k17: $2 ='"; return; fi
    if [ "$got" = "$3" ]; then ok "$4 ($2 = $got)"
    else bad "$4 -- $2 = $got, erwartet $3"; fi
}
# Eine Zahl aus der Zusammenfassung `usb: keys=... reports=...`.
uz() { grep -a "^usb: keys=" "$1" 2>/dev/null | tail -1 | tr -d '\000' \
        | grep -oE "$2=[0-9]+" | tail -1 | cut -d= -f2; }
# Eine Zahl aus der Zeile `usb: devices=... enums=... cmds=...`.
us() { grep -a "^usb: devices=" "$1" 2>/dev/null | tail -1 | tr -d '\000' \
        | grep -oE "$2=[0-9]+" | tail -1 | cut -d= -f2; }
number_in() { grep -aE "^const $2: u64 = [0-9]+" "$1" | head -1 \
        | sed -E 's/^const [A-Za-z0-9_]+: u64 = ([0-9]+).*/\1/'; }

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "vendor/firn/fetch-firnc.sh fehlgeschlagen"; exit 1; }
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "K17: uebersprungen, qemu-system-x86_64 fehlt"
    exit 0
fi
if ! qemu-system-x86_64 -device help 2>&1 | grep -q 'qemu-xhci'; then
    echo "K17: uebersprungen, dieses QEMU kennt qemu-xhci nicht"
    exit 0
fi
for w in mkfs.vfat mcopy mdir mtype sfdisk; do
    command -v "$w" >/dev/null 2>&1 || {
        echo "K17: uebersprungen, $w fehlt (dosfstools/mtools/util-linux)"
        exit 0
    }
done

# ============================================== 1. die Nummern und die Karte

echo "== 1. die Nummern, die Vektoren und die Karte von kdata =="

# Die zwei Aufrufnummern dieser Runde. 1700 gehoert seit Runde K14 der
# Einhaengetafel; der Vorrat dieser Runde faengt deshalb bei 1701 an.
for n in 1701 1702; do
    grep -qE "= $n( |$)" kernel/sys.fi && ok "die Aufrufnummer $n steht in kernel/sys.fi" \
        || bad "die Aufrufnummer $n fehlt in kernel/sys.fi"
done
stat_nr=$(number_in kernel/sys.fi "SYS_OSUM_USBSTAT")
pull_nr=$(number_in kernel/sys.fi "SYS_OSUM_USBPULL")
for v in "$stat_nr" "$pull_nr"; do
    if [ "${v:-0}" -ge 1701 ] && [ "${v:-0}" -le 1749 ]; then
        ok "die Nummer $v liegt im zugeteilten Vorrat 1701..1749"
    else
        bad "die Nummer ${v:-fehlt} liegt AUSSERHALB von 1701..1749"
    fi
done
# UND NIRGENDS SONST IM BAUM. Drei Runden arbeiten gleichzeitig an
# diesem Kernel; eine Nummer, die zweimal vorkommt, ist genau die Art
# Fehler, die erst beim Verschmelzen auffaellt.
doppelt=$(grep -rn "u64 = 170[12]$" kernel/ lib/ 2>/dev/null \
    | grep -cv 'USBSTAT\|USBPULL\|USB_MINNR\|USB_MAXNR' || true)
num "andere Verwendungen der Nummern 1701/1702 im Baum" "${doppelt:-0}" eq 0

# RUNDE MERGE: `trap.fi` und `boot.s` liegen seit Runde ARM unter
# `kernel/arch/x86_64/`. Dieser Laeufer suchte sie an der alten Stelle,
# fand nichts und meldete drei Fehler ueber Dinge, die unveraendert da
# waren.
# Der Vektor. 43, und keiner sonst -- `karte.py` rechnet die
# Vektortafel seit Runde K10 nach.
grep -q 'const VEC_XHCI: u64 = 43' kernel/arch/x86_64/trap.fi \
    && ok "der Meldevektor des Reglers ist 43 (kernel/arch/x86_64/trap.fi)" \
    || bad "VEC_XHCI ist nicht 43 in kernel/arch/x86_64/trap.fi"
grep -q 'const VEC_XHCI: u64 = 43' kernel/xhci.fi \
    && ok "und dieselbe Zahl steht im Treiber" \
    || bad "VEC_XHCI in kernel/xhci.fi passt nicht"

# Die Speicherkarte. `karte.py` rechnet seit dieser Runde AUCH die
# Untergliederung des USB-Bereichs nach -- sie ist kein eigener
# kdata-Bereich, kann sich aber selbst ueberschneiden.
if python3 tools/kernel/memmap.py kernel > "$TMPD/karte.txt" 2>&1; then
    ok "die Speicherkarte von kdata: $(tail -1 "$TMPD/karte.txt")"
else
    bad "tools/kernel/memmap.py meldet Kollisionen"
    sed 's/^/        /' "$TMPD/karte.txt" | head -10
fi
hat "$TMPD/karte.txt" "0 Kollisionen" "keine zwei Bereiche ueberschneiden sich"
k17off=$(grep -aE '^const K17_OFF: u64 = 0x[0-9A-Fa-f]+' kernel/kstate.fi | grep -oE '0x[0-9A-Fa-f]+')
k17max=$(grep -aE '^const K17_MAX: u64 = 0x[0-9A-Fa-f]+' kernel/kstate.fi | grep -oE '0x[0-9A-Fa-f]+')
gleich "der Vorrat dieser Runde faengt bei 0x50000 an" "0x50000" "$k17off"
gleich "und ist acht Seiten gross" "0x8000" "$k17max"
# kdata musste dafuer wachsen -- und die Zahl steht ZWEIMAL.
a=$(grep -aE '^const KDATA_SIZE: u64 = 0x[0-9A-Fa-f]+' kernel/kstate.fi | grep -oE '0x[0-9A-Fa-f]+')
b=$(grep -aE '\.set KDATA_SIZE, 0x[0-9A-Fa-f]+' kernel/arch/x86_64/boot.s | grep -oE '0x[0-9A-Fa-f]+' | head -1)
gleich "KDATA_SIZE steht in kstate.fi und boot.s gleich" "$a" "$b"
# Der Vorrat dieser Runde endet bei 0x58000. Als K17 zuerst geschrieben
# wurde, WAR das die Grenze; Runde K18 hat kdata inzwischen auf 0x60000
# gehoben und ihre zwei Seiten dahinter gelegt. Geprueft wird deshalb,
# was wirklich gilt: der Vorrat dieser Runde liegt VOLLSTAENDIG in kdata.
GG="$TMPD/kernel-gg"; mkdir -p "$GG"
ende17=$(( $(printf '%d' "$k17off") + $(printf '%d' "$k17max") ))
if [ "$ende17" -le "$(printf '%d' "$a")" ]; then
    ok "der Vorrat dieser Runde endet bei $(printf '0x%X' "$ende17"), KDATA_SIZE ist $a"
else
    bad "der Vorrat endet bei $(printf '0x%X' "$ende17"), KDATA_SIZE ist nur $a"
fi

# ---------------------------------------------------- der Modusvektor
#
# Der erste Anlauf dieser Runde ist GENAU HIER gescheitert: K17 und K18
# hatten unabhaengig voneinander dieselben sieben Bits genommen (1<<47
# bis 1<<53), und danach waren im ganzen u64 nur noch vier frei. Seit
# der Vorarbeit zu dieser Runde ist der Modus ein Vektor aus Woertern,
# ein Wort je Untersystem, und ein Modusname ist ein Bitindex
# (Wort * 64 + Bit). Die neun Schalter dieser Runde liegen in Wort 6.
for n in M_USB M_NOUSB M_USBPOLL M_NOHID M_NOMSC M_UNPLUG M_NOUSBIRQ \
         M_USBSTICK M_USBHOLD; do
    v=$(number_in kernel/kstate.fi "$n")
    if [ -n "${v:-}" ] && [ "$v" -ge 384 ] && [ "$v" -le 447 ]; then
        ok "$n liegt in Wort 6 des Modusvektors (Index $v)"
    else
        bad "$n hat den Index ${v:-fehlt}, erwartet 384..447 (Wort 6)"
    fi
done
# UND KEINE EINZIGE MASKE MEHR IM KERNEL. Solange irgendwo `mode & M_X`
# steht, kann eine Runde wieder eine Maske erfinden.
masken=$(grep -rac 'kstate\.MODE) &\|& kstate\.M_' kernel/*.fi 2>/dev/null \
        | awk -F: '{s+=$2} END {print s+0}')
num "Stellen im Kernel, die den Modus noch als MASKE lesen" "${masken:-1}" eq 0

# GEGENPROBE ZUM MODUSPRUEFER, zweimal -- ohne sie prueft er nur das,
# woran jemand gedacht hat.
cp kernel/*.fi "$GG/"
sed -i 's/^const M_USB: u64 = 384/const M_USB: u64 = 321/' "$GG/kstate.fi"
if python3 tools/kernel/memmap.py "$GG" > "$TMPD/karte-gg3.txt" 2>&1; then
    bad "GEGENPROBE: M_USB auf den Index von M_PWR gelegt und der Pruefer schweigt"
else
    ok "GEGENPROBE: zwei Modusnamen auf einem Index -- der Pruefer schlaegt an"
fi
cp kernel/*.fi "$GG/"
sed -i 's/^const M_USB: u64 = 384/const M_USB: u64 = 140737488355328/' "$GG/kstate.fi"
if python3 tools/kernel/memmap.py "$GG" > "$TMPD/karte-gg4.txt" 2>&1; then
    bad "GEGENPROBE: eine alte Maske als Modusindex und der Pruefer schweigt"
else
    ok "GEGENPROBE: eine vergessene Maske (1<<47) hinter dem Vektor -- der Pruefer schlaegt an"
fi

# GEGENPROBE ZUM KARTENPRUEFER: ein Stueck des USB-Bereichs aus seinem
# Bereich herausgelegt MUSS auffallen. Ohne diese Zeile prueft die neue
# Karte nur das, woran jemand gedacht hat.
cp kernel/*.fi "$GG/"
sed -i 's/^const EVT_OFF: u64 = 0x52000/const EVT_OFF: u64 = 0x4C000/' "$GG/xhci.fi"
if python3 tools/kernel/memmap.py "$GG" > "$TMPD/karte-gg.txt" 2>&1; then
    bad "GEGENPROBE: EVT_OFF auf 0x4C000 gelegt und der Pruefer schweigt"
else
    ok "GEGENPROBE: ein Ring ausserhalb des Vorrats -- der Kartenpruefer schlaegt an"
fi
# Und eine zweite: zwei Stuecke INNERHALB des Bereichs uebereinander.
cp kernel/*.fi "$GG/"
sed -i 's/^const DESC_OFF: u64 = 0x56000/const DESC_OFF: u64 = 0x55000/' "$GG/usb.fi"
if python3 tools/kernel/memmap.py "$GG" > "$TMPD/karte-gg2.txt" 2>&1; then
    bad "GEGENPROBE: DESC_OFF auf die Uebertragungsringe gelegt, Pruefer schweigt"
else
    ok "GEGENPROBE: zwei Stuecke des USB-Bereichs uebereinander -- der Pruefer schlaegt an"
fi

# DIE SCHICHT HAT SICH NICHT VERBREITERT. `fs.fi`, `fat.fi` und `vfs.fi`
# kennen kein USB -- das ist die Zusage von `blk.fi` aus Runde 62, zum
# dritten Mal (nach NVMe in K2 und dem ATA-Sklaven in K14).
for f in fs.fi fat.fi vfs.fi ofs.fi part.fi; do
    n=$(grep -acE '(^|[^a-z_])usb\.' "kernel/$f" 2>/dev/null || true)
    if [ "${n:-0}" -eq 0 ]; then ok "kernel/$f ruft kein usb.* -- die Blockschicht traegt es"
    else bad "kernel/$f ruft usb.* ($n mal)"; fi
done

# ================================================================ 2. bauen

echo "== 2. bauen: der Kern und die Programme, aus beiden Uebersetzern =="
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null \
    || bad "crt.s laesst sich nicht assemblieren"
baue() { # stufe
    local s=$1 cc p rc=0
    if [ "$s" = 0 ]; then cc="$FIRNC"; else cc="$FC1"; fi
    bash tools/build-kernel.sh "$TMPD/k$s.mb" --stufe "$s" > "$TMPD/k$s.log" 2>&1 || {
        bad "firnc$s: der Kern laesst sich nicht bauen"
        sed 's/^/        /' "$TMPD/k$s.log" | head -12
        return 1
    }
    for p in $PROGS; do
        "$cc" "kernel/user/$p.fi" -o "$TMPD/$p$s.o" > "$TMPD/e$p$s" 2>&1 || {
            bad "firnc$s uebersetzt $p.fi nicht"
            sed 's/^/        /' "$TMPD/e$p$s" | head -8
            rc=1
            continue
        }
        ld -T "$ULD" --defsym=USER_ENTRY="_F$s.u_start" \
            -o "$TMPD/$p$s.elf" "$TMPD/crt.o" "$TMPD/$p$s.o" 2>"$TMPD/ld.err" || {
            bad "firnc$s: ld scheitert an $p"; rc=1; continue; }
        strip --strip-all "$TMPD/$p$s.elf"
    done
    return $rc
}
baue 0 || { echo "K17: $pass passed, $((fail+1)) failed"; exit 1; }
ok "firnc0: der Kern ($(stat -c%s "$TMPD/k0.mb") Oktette) und $(echo $PROGS | wc -w) Programme"
if baue 1; then
    ok "firnc1: dasselbe aus dem Uebersetzer, der in Firn geschrieben ist"
else
    bad "firnc1 baut diese Runde nicht"
fi
zeilen=$(cat kernel/xhci.fi kernel/usb.fi | wc -l)
num "Zeilen Treiber, die diese Runde geschrieben hat" "$zeilen" gt 1200

# Die Wurzelplatte.
MKARGS=""
for p in $PROGS; do MKARGS="$MKARGS /bin/$p=$TMPD/${p}0.elf"; done
python3 tools/osum/mkfs.py build "$TMPD/root.img" "$BLOCKS" \
    /bin/ /proc/ /dev/ /mnt/ /usb/ $MKARGS > "$TMPD/mkfs.log" 2>&1 \
    && ok "die Wurzelplatte steht: $(tail -1 "$TMPD/mkfs.log")" \
    || { bad "mkfs.py scheitert"; sed 's/^/        /' "$TMPD/mkfs.log" | head -5; }

# Der Stick: ein FAT32 von den ECHTEN Linux-Werkzeugen, in einer
# MBR-Tafel von `sfdisk`, mit einer Datei von `mcopy` darin.
printf 'von linux auf den stick\n' > "$TMPD/host.txt"
dd if=/dev/zero of="$TMPD/fat.img" bs=1M count=48 status=none
mkfs.vfat -F 32 -s 1 -n USBSTICK "$TMPD/fat.img" >/dev/null 2>&1 \
    && ok "mkfs.vfat hat ein FAT32 fuer den Stick angelegt" \
    || bad "mkfs.vfat scheitert"
mcopy -i "$TMPD/fat.img" "$TMPD/host.txt" ::host.txt \
    && ok "mcopy hat host.txt hineingelegt (24 Oktette)" \
    || bad "mcopy scheitert"
dd if=/dev/zero of="$TMPD/stick.img" bs=1M count=64 status=none
printf 'label: dos\nstart=2048, type=c\n' | sfdisk "$TMPD/stick.img" >/dev/null 2>&1 \
    && ok "sfdisk hat eine MBR-Tafel geschrieben (Typ 0x0C, FAT32 LBA)" \
    || bad "sfdisk scheitert"
dd if="$TMPD/fat.img" of="$TMPD/stick.img" bs=512 seek=2048 conv=notrunc status=none

# ============================================================== die Laeufe

XHCI=(-device qemu-xhci,id=xhci)
KBD=(-device usb-kbd)
MOUSE=(-device usb-mouse)

lauf() { # name kernel kommandozeile [qemu-argumente...]
    local name=$1 img=$2 app=$3
    shift 3
    cp "$TMPD/root.img" "$TMPD/live-$name.img"
    cp "$TMPD/stick.img" "$TMPD/live2-$name.img"
    timeout 240 qemu-system-x86_64 -kernel "$img" -m 256 -append "$app" \
        -serial "file:$TMPD/$name.txt" -display none -no-reboot -vga std \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        "$@" -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    echo $?
}
lauf_stick() { # name kernel kommandozeile [weitere qemu-argumente...]
    local name=$1 img=$2 app=$3
    shift 3
    cp "$TMPD/root.img" "$TMPD/live-$name.img"
    cp "$TMPD/stick.img" "$TMPD/live2-$name.img"
    timeout 240 qemu-system-x86_64 -kernel "$img" -m 256 -append "$app" \
        -serial "file:$TMPD/$name.txt" -display none -no-reboot -vga std \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        "$@" -drive "id=stk,file=$TMPD/live2-$name.img,format=raw,if=none" \
        -device usb-storage,drive=stk \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    echo $?
}

# Ein Lauf, in dem von aussen die MAUS bewegt wird.
mauslauf() { # name kernel kommandozeile marke monitordatei [qemu-args...]
    local name=$1 img=$2 app=$3 marke=$4 mon=$5
    shift 5
    local sock="$TMPD/mon-$name.sock"
    rm -f "$sock" "$TMPD/$name.txt" "$TMPD/$name.rc"
    cp "$TMPD/root.img" "$TMPD/live-$name.img"
    ( timeout 240 qemu-system-x86_64 -kernel "$img" -m 256 -append "$app" \
        -serial "file:$TMPD/$name.txt" -display none -no-reboot -vga std \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -monitor "unix:$sock,server,nowait" \
        "$@" -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
      echo $? > "$TMPD/$name.rc" ) &
    local pid=$!
    # Warten, bis der Kern stillhaelt -- sonst faellt die erste Bewegung
    # in einen Kern, der noch aufzaehlt.
    local i=0
    while [ $i -lt 600 ]; do
        grep -qa "$marke" "$TMPD/$name.txt" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1; i=$((i+1))
    done
    python3 tools/wm/monitor.py "$sock" "$mon" > "$TMPD/$name.monlog" 2>&1
    wait $pid 2>/dev/null
    rm -f "$sock"
    RC=$(cat "$TMPD/$name.rc" 2>/dev/null || echo 99)
}

# Ein Lauf, in dem GETIPPT wird (ueber tools/k11/keys.py, Runde K11):
# die Tasten gehen als echte `sendkey`-Befehle in die laufende Maschine.
tastenlauf() { # name kernel kommandozeile marke -- tasten... -- qemu-args...
    local name=$1 img=$2 app=$3 marke=$4
    shift 4
    [ "${1:-}" = "--" ] && shift
    local tasten=()
    while [ $# -gt 0 ] && [ "$1" != "--" ]; do tasten+=("$1"); shift; done
    [ "${1:-}" = "--" ] && shift
    local sock="$TMPD/mon-$name.sock"
    rm -f "$sock" "$TMPD/$name.txt" "$TMPD/$name.rc"
    cp "$TMPD/root.img" "$TMPD/live-$name.img"
    ( timeout 240 qemu-system-x86_64 -kernel "$img" -m 256 -append "$app" \
        -serial "file:$TMPD/$name.txt" -display none -no-reboot -vga std \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -monitor "unix:$sock,server,nowait" \
        "$@" -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
      echo $? > "$TMPD/$name.rc" ) &
    local pid=$!
    python3 tools/k11/keys.py "$sock" "$TMPD/$name.txt" "$marke" \
        "${tasten[@]}" > "$TMPD/$name.tasten" 2>&1
    wait $pid 2>/dev/null
    rm -f "$sock"
    RC=$(cat "$TMPD/$name.rc" 2>/dev/null || echo 99)
}

# ====================================== 3. der Regler kommt hoch

echo "== 3. der Regler: ueber PCI gefunden, aufgesetzt, Meldungen =="
rc=$(lauf_stick hc "$TMPD/k0.mb" "usb nokbd nosched noproc nofs" \
    "${XHCI[@]}" "${KBD[@]}" "${MOUSE[@]}")
num "der Kern beendet sich selbst (21)" "$rc" eq 21
H="$TMPD/hc.txt"
hat "$H" "class=0c:03:30 usb" "PCI findet den Regler an seiner KLASSE (0c:03:30 = xHCI)"
hat "$H" "usb: xhci slots=" "der Regler ist aufgesetzt und meldet sich"
ports=$(grep -a 'usb: xhci' "$H" | grep -oE 'ports=[0-9]+' | cut -d= -f2)
slots=$(grep -a 'usb: xhci' "$H" | grep -oE 'slots=[0-9]+' | cut -d= -f2)
ctx=$(grep -a 'usb: xhci' "$H" | grep -oE 'ctx=[0-9]+' | cut -d= -f2)
num "Anschluesse, die der Regler SELBST meldet (HCSPARAMS1)" "$ports" ge 4
num "Steckplaetze, die er anbietet" "$slots" ge 4
gleich "die Groesse eines Zusammenhangs, aus HCCPARAMS1 gelesen" "32" "$ctx"
irqs=$(uz "$H" irqs)
evts=$(uz "$H" events)
num "Meldungen des Reglers, wirklich auf Vektor 43 angekommen" "${irqs:-0}" ge 10
num "Ereignisse, die aus dem Ereignisring geholt wurden" "${evts:-0}" ge 10
gleich "jede Meldung hat mindestens ein Ereignis gebracht" "1" \
    "$([ "${evts:-0}" -ge "${irqs:-0}" ] && echo 1 || echo 0)"
num "Fehler des Reglers im ganzen Lauf" "$(uz "$H" xhcierr)" eq 0
num "Zusagen, die die Schicht ueber sich selbst macht" "$(uz "$H" selftest)" eq 8

# GEGENPROBE 1: kein Regler an der Maschine.
rc=$(lauf kein "$TMPD/k0.mb" "usb nokbd nosched noproc nofs")
num "ohne -device qemu-xhci beendet sich der Kern trotzdem sauber" "$rc" eq 21
hat "$TMPD/kein.txt" "usb: no controller" "und sagt, dass keiner da ist"
hat_nicht "$TMPD/kein.txt" "usb: xhci slots=" "und setzt nichts auf"
# GEGENPROBE 2: `nousb` -- der Baum bleibt ganz aus.
rc=$(lauf_stick nousb "$TMPD/k0.mb" "usb nousb nokbd nosched noproc nofs" \
    "${XHCI[@]}" "${KBD[@]}" "${MOUSE[@]}")
num "mit nousb beendet sich der Kern sauber" "$rc" eq 21
hat "$TMPD/nousb.txt" "usb: nousb" "die Gegenprobe sagt es"
hat_nicht "$TMPD/nousb.txt" "usb: port=" "und KEIN Geraet wird aufgezaehlt"
hat_nicht "$TMPD/nousb.txt" "usb: keys=" "und es gibt keine Zahlen dieser Runde"
# GEGENPROBE 3: ohne das Wort `usb` bleibt der Kern der von Runde K16.
rc=$(lauf_stick ohne "$TMPD/k0.mb" "nokbd nosched noproc nofs" \
    "${XHCI[@]}" "${KBD[@]}" "${MOUSE[@]}")
num "ohne das Wort usb beendet sich der Kern sauber" "$rc" eq 21
hat "$TMPD/ohne.txt" "usb: skipped" "und meldet genau eine Zeile"
hat_nicht "$TMPD/ohne.txt" "usb: xhci" "und setzt den Regler NICHT auf"

# ============================================ 4. die Aufzaehlung

echo "== 4. die Aufzaehlung: drei Geraete, an ihrer Klasse erkannt =="
hat "$H" "class=03:01:01 driver=kbd" "die Tastatur, an Klasse 03:01:01 (HID/Boot/Tastatur)"
hat "$H" "class=03:01:02 driver=mouse" "die Maus, an Klasse 03:01:02 (HID/Boot/Maus)"
hat "$H" "class=08:06:50 driver=msc" "der Stick, an Klasse 08:06:50 (Massenspeicher/SCSI/BOT)"
num "aufgezaehlte Geraete" "$(uz "$H" devices)" eq 3
num "Aufzaehlungen, die durchgelaufen sind" "$(us "$H" enums)" eq 3
# Jedes Geraet hat einen EIGENEN Steckplatz bekommen -- eine Nummer,
# die der REGLER vergeben hat, nicht der Treiber.
sl=$(grep -a 'usb: port=' "$H" | grep -oE 'slot=[0-9]+' | cut -d= -f2 | sort -u | wc -l)
num "verschiedene Steckplaetze fuer drei Geraete" "$sl" eq 3
pt=$(grep -a 'usb: port=' "$H" | grep -oE 'port=[0-9]+' | cut -d= -f2 | sort -u | wc -l)
num "verschiedene Anschluesse" "$pt" eq 3
# Die Paketgroesse des Steuerungsendpunkts kommt aus dem Deskriptor --
# also hat der Treiber ihn wirklich gelesen.
num "Kommandos an den Regler (Steckplatz, Adresse, Endpunkte)" \
    "$(us "$H" cmds)" ge 9

# GEGENPROBE: `nohid` -- die Geraete werden gefunden, aber kein
# Eingabetreiber nimmt sie an.
rc=$(lauf_stick nohid "$TMPD/k0.mb" "usb nohid nokbd nosched noproc nofs" \
    "${XHCI[@]}" "${KBD[@]}" "${MOUSE[@]}")
num "mit nohid beendet sich der Kern sauber" "$rc" eq 21
hat_nicht "$TMPD/nohid.txt" "driver=kbd" "GEGENPROBE nohid: keine Tastatur"
hat_nicht "$TMPD/nohid.txt" "driver=mouse" "GEGENPROBE nohid: keine Maus"
hat "$TMPD/nohid.txt" "driver=msc" "aber der Stick wird weiter angenommen"
# GEGENPROBE: `nomsc`.
rc=$(lauf_stick nomsc "$TMPD/k0.mb" "usb nomsc nokbd nosched noproc nofs" \
    "${XHCI[@]}" "${KBD[@]}" "${MOUSE[@]}")
num "mit nomsc beendet sich der Kern sauber" "$rc" eq 21
hat_nicht "$TMPD/nomsc.txt" "driver=msc" "GEGENPROBE nomsc: kein Blockgeraet"
hat "$TMPD/nomsc.txt" "driver=kbd" "aber die Tastatur wird weiter angenommen"

# ================================= 5. DIE TASTATUR, ZWEIMAL DERSELBE TEST

echo "== 5. die Tastatur: derselbe Test ueber USB und ueber PS/2 =="
TASTEN=(text:"echo hallo" ret warte:0.8 text:"echo zwei drei" ret warte:0.8 text:exit ret warte:0.8)

tastenlauf kbdusb "$TMPD/k0.mb" "osum usb nosched noproc" "osum: bin " \
    -- "${TASTEN[@]}" -- "${XHCI[@]}" "${KBD[@]}"
num "der USB-Lauf beendet sich selbst (21)" "$RC" eq 21
tastenlauf kbdps2 "$TMPD/k0.mb" "osum nosched noproc" "osum: bin " \
    -- "${TASTEN[@]}" --
num "der PS/2-Lauf beendet sich selbst (21)" "$RC" eq 21

# DER GEGENBEWEIS ZUERST: hat im USB-Lauf wirklich die USB-Tastatur
# geliefert? `usb: keys=` zaehlt NUR, was durch `usb.press` ging.
kus=$(uz "$TMPD/kbdusb.txt" keys)
num "Tasten, die durch den USB-Weg gegangen sind" "${kus:-0}" ge 24
hat_nicht "$TMPD/kbdps2.txt" "usb: keys=" "im PS/2-Lauf gibt es diesen Weg gar nicht"

grep -a '^key: ' "$TMPD/kbdusb.txt" | tr -d '\000' > "$TMPD/kbdusb.keys"
grep -a '^key: ' "$TMPD/kbdps2.txt" | tr -d '\000' > "$TMPD/kbdps2.keys"
gleiche_datei "DIESELBEN ZEICHEN: die key-Zeilen beider Laeufe" \
    "$TMPD/kbdusb.keys" "$TMPD/kbdps2.keys" 24
gleich "so viele key-Zeilen, wie der USB-Treiber Tasten gezaehlt hat" \
    "$(wc -l < "$TMPD/kbdusb.keys")" "${kus:-0}"

# UND DIE SHELL SIEHT DASSELBE. Der Mitschnitt zwischen `sh: ready` und
# `sh: bye`, ohne die Zeilen des Laders (die tragen Adressen) und ohne
# die Zeilen dieser Runde (die gibt es im PS/2-Lauf nicht).
schale() { sed -n '/sh: ready/,/sh: bye/p' "$1" | tr -d '\000' \
    | grep -avE '^(elf:|usb:|k17:)'; }
schale "$TMPD/kbdusb.txt" > "$TMPD/kbdusb.sh"
schale "$TMPD/kbdps2.txt" > "$TMPD/kbdps2.sh"
gleiche_datei "DIESELBE SHELL-SITZUNG, Oktett fuer Oktett" \
    "$TMPD/kbdusb.sh" "$TMPD/kbdps2.sh" 8
grep -qa '^hallo$' "$TMPD/kbdusb.sh" \
    && ok "und darin steht wirklich, was getippt wurde ('hallo')" \
    || { bad "'hallo' steht nicht im Mitschnitt des USB-Laufs"
         head -12 "$TMPD/kbdusb.sh" | sed 's/^/        /'; }
grep -qa '^zwei drei$' "$TMPD/kbdusb.sh" \
    && ok "und die zweite Zeile, mit einem Leerzeichen darin" \
    || bad "'zwei drei' fehlt"

# GEGENPROBE: der Meldevektor bleibt maskiert. Der Regler bewegt die
# Daten weiter -- aber niemand sagt es dem Kernel, und dann kommt keine
# Taste an.
tastenlauf kbdnoirq "$TMPD/k0.mb" "osum usb usbnoirq nosched noproc" "osum: bin " \
    -- text:"echo hallo" ret warte:1.5 text:exit ret warte:1.0 \
    -- "${XHCI[@]}" "${KBD[@]}"
num "GEGENPROBE usbnoirq: der Kern beendet sich trotzdem" "$RC" eq 21
num "GEGENPROBE usbnoirq: Tasten ueber den USB-Weg" "$(uz "$TMPD/kbdnoirq.txt" keys)" eq 0
grep -qa '^hallo$' "$TMPD/kbdnoirq.txt" \
    && bad "GEGENPROBE usbnoirq: die Shell hat trotzdem etwas getippt bekommen" \
    || ok "GEGENPROBE usbnoirq: die Shell bekommt kein Zeichen"

# GEGENPROBE ZUR GEGENPROBE: derselbe maskierte Vektor, aber der Kern
# sieht selbst nach. Dann kommen die Ereignisse wieder an -- also lag es
# an der MELDUNG und nicht daran, dass die Uebertragung nicht liefe.
: > "$TMPD/leer.mon"
mauslauf kbdpoll "$TMPD/k0.mb" \
    "usb usbnoirq usbpoll usbhold nokbd nosched noproc nofs" \
    "k17: hold" "$TMPD/leer.mon" "${XHCI[@]}" "${KBD[@]}"
num "GEGENPROBE usbpoll: der Kern beendet sich sauber" "$RC" eq 21
num "GEGENPROBE usbpoll: Meldungen auf Vektor 43" "$(uz "$TMPD/kbdpoll.txt" irqs)" eq 0
num "GEGENPROBE usbpoll: Ereignisse trotzdem geholt" \
    "$(uz "$TMPD/kbdpoll.txt" events)" ge 10

# ==================================================== 6. die Maus

echo "== 6. die Maus: zehn Bewegungen und ein Klick, auf den Punkt =="
M="$TMPD/maus.mon"
{
    for i in 1 2 3 4 5 6 7 8; do echo "mouse_move -100 -100"; echo "warte 0.25"; done
    echo "mouse_move 100 60"; echo "warte 0.35"
    echo "mouse_move 100 60"; echo "warte 0.35"
    echo "mouse_button 1"; echo "warte 0.5"
    echo "mouse_button 0"; echo "warte 1.0"
} > "$M"
mauslauf maus "$TMPD/k0.mb" "usb usbhold nokbd nomouse nosched noproc nofs" \
    "k17: hold" "$M" "${XHCI[@]}" "${MOUSE[@]}"
num "der Mauslauf beendet sich selbst (21)" "$RC" eq 21
hat "$TMPD/maus.txt" "k17: hold" "der Kern haelt still, bevor der Zeiger bewegt wird"
gleich "der Zeiger steht danach auf x=200 (acht Anschlaege, dann 2 x 100)" \
    "200" "$(uz "$TMPD/maus.txt" mx)"
gleich "und auf y=120 (2 x 60)" "120" "$(uz "$TMPD/maus.txt" my)"
gleich "genau EIN Klick, gezaehlt an der Flanke im PS/2-Paketpfad" \
    "1" "$(uz "$TMPD/maus.txt" mclk)"
num "Berichte, die die Maus geschickt hat" "$(uz "$TMPD/maus.txt" reports)" ge 10
gleich "so viele PS/2-Pakete wie Berichte -- jeder Bericht wird EIN Paket" \
    "$(uz "$TMPD/maus.txt" reports)" "$(uz "$TMPD/maus.txt" mpkt)"
gleich "die Taste ist am Ende wieder losgelassen" "0" "$(uz "$TMPD/maus.txt" mbtn)"

# GEGENPROBE: derselbe Lauf ohne Maus am Bus. Der Zeiger darf sich nicht
# bewegen -- und wenn er es doch tut, hat der PS/2-Regler geliefert und
# die ganze Messung oben waere wertlos.
mauslauf mausohne "$TMPD/k0.mb" "usb usbhold nokbd nomouse nosched noproc nofs" \
    "k17: hold" "$M" "${XHCI[@]}" "${KBD[@]}"
num "GEGENPROBE: der Lauf ohne USB-Maus beendet sich sauber" "$RC" eq 21
num "GEGENPROBE: Berichte ohne Maus am Bus" "$(uz "$TMPD/mausohne.txt" moves)" eq 0
num "GEGENPROBE: PS/2-Pakete ohne Maus am Bus" "$(uz "$TMPD/mausohne.txt" mpkt)" eq 0

# ============================================ 7. der Stick

echo "== 7. der Stick: eingehaengt, gelesen, beschrieben -- von aussen geprueft =="
rc=$(lauf_stick stick "$TMPD/k0.mb" \
    "osum usb usbstick vfs nokbd nosched noproc script=k17" "${XHCI[@]}")
num "der Sticklauf beendet sich selbst (21)" "$rc" eq 21
S="$TMPD/stick.txt"
hat "$S" "usb: msc blocks=" "der Treiber hat READ CAPACITY gestellt"
hat "$S" "QEMU" "und INQUIRY liefert den Herstellernamen aus dem Geraet"
hat "$S" "k17: stick parts=1" "die MBR-Tafel des Sticks wurde gelesen"
hat "$S" "mount=1" "und das FAT32 darauf ist eingehaengt"
sagt "$S" ready 1 "Ring 3 sieht den Baum"
sagt "$S" msc 1 "Ring 3 sieht den Stick"
sagt "$S" bsize 512 "und seine Blockgroesse"
sagt "$S" blocks 131072 "und seine Groesse in Bloecken (64 MiB)"
sagt "$S" hostlen 24 "die Datei des WIRTS ist 24 Oktette lang"
sagt "$S" hostok 1 "und ihr Inhalt stimmt Oktett fuer Oktett"
sagt "$S" wrote 14 "Osum schreibt 14 Oktette auf den Stick"
sagt "$S" reread 14 "und liest sie unmittelbar danach wieder"
sagt "$S" devdiff 1 "Stick und Wurzel haben zwei verschiedene st_dev"
sagt "$S" mscerr 0 "kein einziger Fehler im Bulk-Only-Transport"
num "SCSI-Befehle ueber den Stick" "$(wert "$S" mscio)" ge 20

# DIE EIGENTLICHE ZUSAGE: was Osum geschrieben hat, holt der WIRT wieder
# heraus. Nicht "das Schreiben hat keinen Fehler gemeldet".
mtype -i "$TMPD/live2-stick.img@@1048576" ::neu.txt > "$TMPD/vonaussen.txt" 2>/dev/null
printf 'osum-war-hier\n' > "$TMPD/soll.txt"
if [ -s "$TMPD/vonaussen.txt" ]; then
    gleiche_datei "WAS OSUM SCHRIEB, LIEST MTOOLS AUF DEM WIRT WIEDER" \
        "$TMPD/soll.txt" "$TMPD/vonaussen.txt" 1
else
    bad "mtools findet ::neu.txt nicht im Abbild des Sticks"
fi
mdir -i "$TMPD/live2-stick.img@@1048576" :: > "$TMPD/mdir.txt" 2>&1
hat "$TMPD/mdir.txt" "host" "und host.txt liegt unveraendert daneben"
if command -v fsck.fat >/dev/null 2>&1; then
    # `fsck.fat` kennt die `@@versatz`-Schreibweise von mtools nicht --
    # die Partition wird deshalb herausgeschnitten und fuer sich geprueft.
    dd if="$TMPD/live2-stick.img" of="$TMPD/nach.part" bs=512 skip=2048 \
        status=none
    if fsck.fat -n "$TMPD/nach.part" > "$TMPD/fsck.txt" 2>&1; then
        ok "fsck.fat: das Dateisystem ist nach Osums Schreibzugriff noch eines"
    else
        bad "fsck.fat meckert"; head -6 "$TMPD/fsck.txt" | sed 's/^/        /'
    fi
else
    ok "(fsck.fat fehlt -- uebersprungen)"
fi

# UND AUS DER SHELL: /dev/usb0 ist ein Blockgeraet, und `mount` nimmt es.
rc=$(lauf_stick shellmount "$TMPD/k0.mb" \
    "osum usb vfs nokbd nosched noproc script=mount /dev/usb1 /usb vfat;ls /usb;cat /usb/host.txt;umount /usb" \
    "${XHCI[@]}")
num "der Lauf mit mount aus der Shell beendet sich selbst" "$rc" eq 21
hat "$TMPD/shellmount.txt" "host.txt" "/bin/mount haengt /dev/usb0 ein und ls sieht die Datei"
hat "$TMPD/shellmount.txt" "von linux auf den stick" "und cat liest sie"

# GEGENPROBE: ohne Stick am Bus gibt es weder Geraet noch /dev/usb0.
rc=$(lauf ohnestick "$TMPD/k0.mb" \
    "osum usb vfs nokbd nosched noproc script=ls /dev" \
    "${XHCI[@]}" "${KBD[@]}")
num "GEGENPROBE ohne Stick: der Kern beendet sich sauber" "$rc" eq 21
hat_nicht "$TMPD/ohnestick.txt" "usb: msc blocks=" "GEGENPROBE: kein Massenspeicher"
# NUR DIE ZEILE VON `ls /dev` ANSEHEN. Der erste Entwurf hat die ganze
# Ausgabe durchsucht -- und `usb` steht dort auch in der Kommandozeile,
# die der Kern beim Start ausgibt. Die Zusage war damit immer rot, und
# zwar aus einem Grund, der mit dem Geraeteverzeichnis nichts zu tun hat.
devzeile() { sed -n '/sh: ready/,$p' "$1" | tr -d '\000' \
    | grep -a '^\./ \.\./ null' | tail -1; }
devA=$(devzeile "$TMPD/ohnestick.txt")
if [ -z "$devA" ]; then
    bad "GEGENPROBE: `ls /dev` hat gar nichts ausgegeben"
elif printf '%s' "$devA" | grep -qE '(^| )usb( |$)'; then
    bad "GEGENPROBE: /dev/usb steht im Verzeichnis, obwohl kein Stick da ist"
else
    ok "GEGENPROBE: /dev/usb steht NICHT im Verzeichnis ($devA)"
fi
# UND DIE GEGENPROBE ZUR GEGENPROBE: mit Stick steht er da. Sonst
# prueft die Zeile darueber nur, dass irgendetwas fehlt.
rc=$(lauf_stick mitstick "$TMPD/k0.mb" \
    "osum usb vfs nokbd nosched noproc script=ls /dev" "${XHCI[@]}")
num "der Lauf MIT Stick beendet sich sauber" "$rc" eq 21
devB=$(devzeile "$TMPD/mitstick.txt")
if printf '%s' "$devB" | grep -qE '(^| )usb( |$)'; then
    ok "mit Stick steht /dev/usb im Verzeichnis ($devB)"
else
    bad "mit Stick fehlt /dev/usb im Verzeichnis: $devB"
fi

# ================================== 8. abziehen im Betrieb

echo "== 8. abziehen im Betrieb: ENODEV, und der Kern laeuft weiter =="
sagt "$S" openfd 1 "vor dem Abziehen ist ein Deskriptor auf dem Stick offen"
sagt "$S" pull 1 "das Geraet wird abgezogen, WAEHREND er offen ist"
sagt "$S" afterread 19 "lesen auf dem OFFENEN Deskriptor: -ENODEV (19)"
sagt "$S" afterwrite 19 "schreiben darauf: -ENODEV"
sagt "$S" afteropen 19 "und ein neues Oeffnen desselben Pfades: -ENODEV"
sagt "$S" mscgone 0 "der Stick meldet sich nicht mehr als da"
sagt "$S" unplugs 1 "der Kern hat genau EIN Abziehen verbucht"
sagt "$S" rootwrite 14 "danach schreibt derselbe Prozess auf der WURZEL weiter"
sagt "$S" rootread 14 "und liest, was er geschrieben hat"
sagt "$S" done 1 "und kommt bis zum Ende"
hat_nicht "$S" "*** EXCEPTION" "kein einziger Ausnahmefehler in diesem Lauf"
hat_nicht "$S" "user fault" "und kein Prozess ist gestorben"
hat "$S" "kernel: done" "der Kern kommt an sein eigenes Ende"
hat "$S" "usb: unplug port=" "und sagt auf der Leitung, welcher Anschluss es war"

# GEGENPROBE: derselbe Pfad, aber NICHT abgezogen -- dann liest er.
# Sonst misst der Test seinen Hintergrund.
rc=$(lauf_stick nopull "$TMPD/k0.mb" \
    "osum usb usbstick vfs nokbd nosched noproc script=wc /usb/host.txt;cat /usb/host.txt" \
    "${XHCI[@]}")
num "GEGENPROBE ohne Abziehen: der Kern beendet sich sauber" "$rc" eq 21
hat "$TMPD/nopull.txt" "von linux auf den stick" "GEGENPROBE: ohne Abziehen liest derselbe Pfad die Datei"
hat_nicht "$TMPD/nopull.txt" "usb: unplug port=" "GEGENPROBE: und nichts wird abgezogen"

# ANSTECKEN IM BETRIEB: der Kern sieht viermal je Sekunde nach. Gemessen
# wird, dass der Weg da ist und im Regellauf NICHT anschlaegt -- ein
# Zaehler, der ohne Stecker hochlaeuft, waere Rauschen.
num "Anstecken im Betrieb im Regellauf (darf nicht anschlagen)" \
    "$(uz "$H" hotplugs)" eq 0
grep -qa 'usb.unplug_check' kernel/arch/x86_64/trap.fi \
    && ok "der Zeitgeber sieht wirklich nach (kernel/arch/x86_64/trap.fi)" \
    || bad "im Zeitgeber steht kein Blick auf die Anschluesse"

# ======================================= 9. dieselben Zahlen aus firnc1

echo "== 9. dasselbe aus dem Uebersetzer, der in Firn geschrieben ist =="
if [ -f "$TMPD/k1.mb" ]; then
    rc=$(lauf_stick stick1 "$TMPD/k1.mb" \
        "osum usb usbstick vfs nokbd nosched noproc script=k17" "${XHCI[@]}")
    num "firnc1: der Sticklauf beendet sich selbst" "$rc" eq 21
    for f in ready msc bsize blocks hostok wrote reread afterread afteropen done; do
        a=$(wert "$S" "$f"); b=$(wert "$TMPD/stick1.txt" "$f")
        if [ -n "$a" ] && [ "$a" = "$b" ]; then ok "firnc1 misst dasselbe: $f = $a"
        else bad "firnc1: $f = ${b:-fehlt}, firnc0 sagte ${a:-fehlt}"; fi
    done
else
    bad "firnc1 hat keinen Kern gebaut -- elf Zusagen fallen aus"
fi

echo
echo "K17: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
