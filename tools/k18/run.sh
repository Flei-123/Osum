#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/k18/run.sh -- ENERGIE UND LEISTUNG, GEMESSEN.
#
# Bis zu dieser Runde konnte Osum ueber ACPI genau eine Sache: abschalten.
# Zwischen "laeuft" und "aus" gab es nichts -- keinen Takt, keinen
# Ruhezustand, kein Turbo, keine Temperatur, keinen Akku. Der Auftrag
# dieser Runde war nicht "schneller machen", sondern STEUERBAR machen:
# Energiesparen, Ausgeglichen, Hoechstleistung, so wie Windows und
# Zorin OS es zeigen.
#
# ==================================================================
# WAS DIESER WIRT HERGIBT UND WAS NICHT -- BITTE ZUERST LESEN
# ==================================================================
#
# Die Messmaschine ist QEMU 7.2 OHNE /dev/kvm, also TCG, auf einem AMD
# EPYC. `tools/k18/msrprobe.s` hat das VOR der ersten Zeile Kernelcode
# ausgemessen (eigene IDT, damit ein #GP eine Zahl wird und nicht das Ende
# des Laufs). Das Ergebnis bestimmt, was hier ueberhaupt gemessen werden
# KANN:
#
#   * KEIN Zugriff auf eines dieser Register loest eine Schutzverletzung
#     aus. QEMU nimmt alle an.
#   * ABER NUR IA32_MISC_ENABLE BEHAELT, was man hineinschreibt.
#     IA32_PERF_CTL, IA32_HWP_REQUEST und IA32_PM_ENABLE werden
#     geschluckt und lesen sich als Null zurueck.
#   * ALSO: dass der TAKT WIRKLICH FAELLT, ist hier NICHT messbar. TCG
#     uebersetzt Befehle, es taktet nichts. In diesem Laeufer steht
#     deshalb KEINE einzige Frequenzzusage. Wer eine sucht, sucht
#     vergeblich, und das ist Absicht.
#   * HWP ist auf diesem Wirt gar nicht ausfuehrbar: CPUID Blatt 6 meldet
#     in EAX Bit 7 eine Null bei JEDEM CPU-Modell, das QEMU 7.2 anbietet,
#     und eine Eigenschaft `hwp` kennt dieses QEMU nicht. Der Pfad ist
#     gebaut und wird nie betreten. Geprueft wird davon nur die
#     KODIERFUNKTION, und sie wird auch genau so benannt.
#
# WAS TROTZDEM WIRKLICH GEMESSEN WIRD:
#
#   1. DIE DREI PROFILE SCHREIBEN DREI VERSCHIEDENE WOERTER, und fuer
#      IA32_MISC_ENABLE werden sie WIRKLICH AUS DEM PROZESSOR
#      ZURUECKGELESEN. Dieselbe Stelle, dreimal gelesen, drei
#      verschiedene Werte -- und die Werte stehen im Handbuch. Nachgerechnet
#      wird nicht gegen eine Konstante in diesem Skript, sondern gegen
#      `tools/k18/expect.py`, eine zweite, unabhaengige Fassung derselben
#      Kodierung.
#   2. DER LEERLAUFPFAD BENUTZT WIRKLICH `mwait`. Zaehler vorher/nachher,
#      und zwei Gegenlaeufe, die einbrechen MUESSEN: `nocstates` (der
#      Kernel faellt auf `hlt` zurueck) und eine CPU ohne CPUID.01H:ECX
#      Bit 3 (die Maschine kann es nicht). Gleiche Zahl Durchlaeufe,
#      andere Aufteilung.
#   3. DER AKKU KOMMT AUS EINER ACPI-TABELLE, DIE DER TESTLAUF SCHREIBT.
#      QEMU 7.2 hat kein `-device battery` (das kam erst mit 8.2), aber
#      `-acpitable` nimmt eine fertige Tabelle. `tools/k18/ssdt.py` baut
#      sie, der Testlauf gibt die Werte vor, und `/bin/power` muss genau
#      diese zeigen. Andere Werte -> andere Ausgabe. Keine Tabelle ->
#      "kein Akku". Das ist der Unterschied zwischen einer Messung und
#      einer Zahl, die das Programm sich selbst gesetzt hat.
#   4. DIE DROSSELUNG WIRD VON DERSELBEN TABELLE AUSGELOEST. Neunzig Grad
#      in der Thermalzone, und das Profil bleibt auf Energiesparen --
#      auch wenn Ring 3 ausdruecklich Hoechstleistung verlangt.
#   5. DER BILDSCHIRM WIRD IM BILD GEMESSEN, AN EINER AUSGERECHNETEN
#      STELLE. Das ist die Lehre aus Runde K7B, und sie steht in der
#      Aufgabe dieser Runde noch einmal: dort schien Text zu 87 Prozent
#      zu stimmen, waehrend JEDER Buchstabe fehlte -- die 87 Prozent
#      waren schwarzer Hintergrund. Hier wird keine Flaeche gezaehlt und
#      kein Mittelwert gebildet: EIN Bildpunkt an EINER Stelle gegen EINEN
#      ausgerechneten Wert, und einer DANEBEN, der schwarz sein muss.
#   6. BEIDE WEGE MUESSEN DASSELBE SAGEN. Der Kernel meldet seine Zahlen
#      auf der seriellen Leitung, `/bin/power roh` holt dieselben Zahlen
#      ueber `syscall` aus Ring 3. Wo sie auseinandergehen, ist die
#      Schnittstelle kaputt.
#
# UND WAS AUSDRUECKLICH NICHT GEZAEHLT WIRD (die Lehre aus B3): eine
# Zusage, die nur besteht, weil beide Seiten leer sind, ist keine. Jeder
# Vergleich hier holt seinen Wert ueber `sagt`/`wert`, und ein FEHLENDER
# Wert laesst die Zusage FALLEN statt sie durchzuwinken.
#
# Aufruf:  bash tools/k18/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
FC1=${FIRNC1:-vendor/firn/bin/firnc1}
ULD=kernel/user/user.ld
BLOCKS=4096
PROGS="sh echo cat ls power"

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
    if [ "$2" = "$3" ]; then ok "$1 ($3)"
    else bad "$1 -- soll '$2', ist '$3'"; fi
}
hat() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hat_nicht() { grep -qaF "$2" "$1" && bad "$3 -- '$2' steht da und sollte nicht" || ok "$3"; }

# EIN WERT AUS DER MELDUNG DES KERNELS ("pwr: name=zahl", hex mit 0x).
kw() { # datei name
    grep -a -m1 "^pwr: $2=" "$1" 2>/dev/null | sed 's/^[^=]*=//' | tr -d '\r\000'
}
# EIN WERT AUS DEM PROGRAMM IN RING 3 ("k18: name = zahl").
uw() { # datei name
    grep -a -m1 "^k18: $2 = " "$1" 2>/dev/null | sed 's/.* = //' | tr -d '\r\000'
}
# EIN WERT AUS /bin/power roh ("power: name=zahl").
pw() { # datei name
    grep -a -m1 "^power: $2=" "$1" 2>/dev/null | sed 's/^[^=]*=//' | tr -d '\r\000'
}
# EINE ZUSAGE UEBER EINEN WERT AUS RING 3. Ein FEHLENDER Wert faellt
# durch -- das ist die Lehre aus B3 (zwei leere Seiten sind kein Test).
sagt() { # datei name soll beschreibung
    local got; got=$(uw "$1" "$2")
    if [ -z "$got" ]; then bad "$4 -- die Zeile 'k18: $2 =' fehlt ganz"; return; fi
    if [ "$got" = "$3" ]; then ok "$4 ($2 = $got)"
    else bad "$4 -- $2 = $got, erwartet $3"; fi
}
ksagt() { # datei name soll beschreibung
    local got; got=$(kw "$1" "$2")
    if [ -z "$got" ]; then bad "$4 -- die Zeile 'pwr: $2=' fehlt ganz"; return; fi
    if [ "$got" = "$3" ]; then ok "$4 ($2 = $got)"
    else bad "$4 -- $2 = $got, erwartet $3"; fi
}
hexdez() { python3 -c "import sys;print(int(sys.argv[1],0))" "$1" 2>/dev/null; }
soll() { python3 tools/k18/expect.py "$@" 2>/dev/null; }
number_in() { # datei name
    grep -aE "^const $2: u64 = [0-9]+" "$1" | head -1 \
        | sed -E 's/^const [A-Za-z0-9_]+: u64 = ([0-9]+).*/\1/'
}
punkt() { python3 tools/gfx/checkshot.py punkt "$@" 2>/dev/null; }

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "vendor/firn/fetch-firnc.sh fehlgeschlagen"; exit 1; }
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "K18: uebersprungen, qemu-system-x86_64 fehlt"
    exit 0
fi

# ============================================ 1. die Nummern und die Karte

echo "== 1. der Nummernvorrat, die Karte von kdata und die Register =="

check() { # name soll grund
    local got; got=$(number_in kernel/sys.fi "SYS_$1")
    if [ "$got" = "$2" ]; then ok "SYS_$1 = $2 ($3)"
    else bad "SYS_$1 = ${got:-fehlt}, erwartet $2"; fi
}
check OSUM_PWRGET 1750 "der Block dieser Runde"
check OSUM_PWRSET 1751 "der Block dieser Runde"
check OSUM_PWRSTR 1752 "der Block dieser Runde"

# JEDE eigene Aufrufnummer liegt im zugeteilten Bereich 1750..1799.
for n in PWRGET PWRSET PWRSTR; do
    v=$(number_in kernel/sys.fi "SYS_OSUM_$n")
    if [ "${v:-0}" -ge 1750 ] && [ "${v:-0}" -le 1799 ]; then
        ok "SYS_OSUM_$n liegt im Vorrat 1750..1799: $v"
    else
        bad "SYS_OSUM_$n = ${v:-fehlt} liegt AUSSERHALB von 1750..1799"
    fi
done

# Die Programmnummern in Ring 3: 45..47 und nichts anderes.
for n in P_PWR:45 P_PWRIDLE:46 P_PWRLOAD:47; do
    nm=${n%%:*}; soll_v=${n##*:}
    v=$(number_in kernel/uprog.fi "$nm")
    gleich "die Ring-3-Programmnummer $nm" "$soll_v" "${v:-fehlt}"
done

# DIE ZAHLEN DIESER RUNDE KOMMEN NIRGENDS SONST VOR. Genau die Lage, aus
# der die vier kdata-Kollisionen dieses Projekts entstanden sind: mehrere
# Runden arbeiten gleichzeitig am selben Baum.
# Gesucht sind AUFRUFNUMMERN, also `const SYS_...: u64 = 17xx`, und
# NICHT jede Zahl in dem Bereich. Die erste Fassung dieses Laeufers hat
# stumpf nach der Zahl gesucht und `kernel/tty.fi` angezeigt -- dort
# steht `const EDITBUF: u64 = 1792`, die GROESSE eines Puffers. Eine
# Zeilenlaenge kollidiert mit keiner Aufrufnummer; der Test hat einen
# Fehler gemeldet, wo keiner war, und das ist genauso schlecht wie einer,
# der keinen meldet, wo einer ist.
fremd=$(grep -ran --include='*.fi' --include='*.s' -E '^const SYS_[A-Za-z0-9_]+: u64 = 17(5[0-9]|[6-9][0-9])' kernel/ \
    | grep -v -e '^kernel/sys.fi' -e '^kernel/uprog.fi' -e '^kernel/user/power.fi' \
              -e '^kernel/user/powermon.fi' -e '^kernel/user/taskbar.fi' || true)
# `kernel/user/taskbar.fi` steht seit Runde MERGE aus demselben Grund in
# der Liste wie powermon.fi: die Taskleiste zeigt den Ladestand an und
# fragt ihn ueber GENAU DIESEN Aufruf. Ein dritter Leser derselben Zahl
# ist der Zweck einer Aufrufnummer.
#
# `kernel/user/powermon.fi` steht seit Runde POWERMON in dieser Liste, und
# das ist keine Aufweichung der Zusage. Die Frage, die diese Zeile stellt,
# ist "vergibt eine ANDERE Runde dieselbe Nummer noch einmal fuer etwas
# anderes" -- nicht "benutzt sonst niemand diese Runde". /bin/powermon
# liest den Akku ueber GENAU diesen Aufruf, so wie /bin/power daneben, und
# ein zweites Programm, das nach dem Ladestand fragt, ist der Zweck einer
# Aufrufnummer und nicht ihr Missbrauch. Kollidieren wuerde erst eine
# ZWEITE Vergabe, und die faende diese Suche weiterhin.
if [ -z "$fremd" ]; then
    ok "keine AUFRUFNUMMER aus 1750..1799 steht ausserhalb der Dateien dieser Runde"
else
    bad "Aufrufnummern aus 1750..1799 stehen auch in: $(echo $fremd | tr '\n' ' ')"
fi
# Und dieselbe Frage andersherum: in kernel/sys.fi sind es GENAU drei.
eigen=$(grep -ahE '^const SYS_[A-Za-z0-9_]+: u64 = 17(5[0-9]|[6-9][0-9])' kernel/sys.fi | wc -l | tr -d ' ')
gleich "in kernel/sys.fi stehen genau drei Nummern aus dem Vorrat" "3" "$eigen"

k18off=$(grep -aE '^const K18_OFF' kernel/kstate.fi | sed 's/.*= //')
batoff=$(grep -aE '^const BATT_OFF' kernel/kstate.fi | sed 's/.*= //')
gleich "die kdata-Seite dieser Runde" "0x58000" "$k18off"
gleich "die kdata-Seite des Akkus" "0x59000" "$batoff"

# kdata musste wachsen, weil der Vorrat dieser Runde hinter der alten
# Grenze liegt -- und die Zahl steht ZWEIMAL. Beide muessen gleich sein.
kd_fi=$(grep -aE '^const KDATA_SIZE' kernel/kstate.fi | sed 's/.*= //')
kd_s=$(grep -aE '\.set KDATA_SIZE' kernel/arch/x86_64/boot.s | sed -E 's/.*KDATA_SIZE, *([0-9a-fx]+).*/\1/')
gleich "KDATA_SIZE in kstate.fi und boot.s ist dieselbe Zahl" "$kd_fi" "$kd_s"
if [ "$(hexdez "${kd_fi:-0}")" -ge "$(hexdez 0x60000)" ]; then
    ok "kdata reicht ueber den Vorrat dieser Runde hinaus: $kd_fi"
else
    bad "kdata ist zu klein fuer 0x58000..0x60000: $kd_fi"
fi

if python3 tools/kernel/memmap.py kernel > "$TMPD/karte.txt" 2>&1; then
    ok "die Speicherkarte von kdata: $(tail -1 "$TMPD/karte.txt")"
else
    bad "tools/kernel/memmap.py meldet Kollisionen"
    sed 's/^/        /' "$TMPD/karte.txt" | head -8
fi
hat "$TMPD/karte.txt" "0 Kollisionen" "keine zwei Bereiche ueberschneiden sich"

# DIE REGISTERNUMMERN GEGEN DAS HANDBUCH. Ein Zahlendreher hier waere ein
# Schreibzugriff auf ein fremdes Register -- auf echter Hardware das
# Schlimmste, was diese Runde anrichten koennte.
for r in IA32_PERF_CTL:0x199 IA32_MISC_ENABLE:0x1A0 IA32_THERM_STATUS:0x19C \
         IA32_TEMPERATURE_TARGET:0x1A2 IA32_HWP_REQUEST:0x774 \
         IA32_PM_ENABLE:0x770 IA32_HWP_CAPABILITIES:0x771 \
         MSR_PLATFORM_INFO:0xCE IA32_ENERGY_PERF_BIAS:0x1B0; do
    nm=${r%%:*}; want=${r##*:}
    got=$(grep -aE "^const $nm: u64 = " kernel/pwr.fi | sed 's/.*= //')
    gleich "$nm" "$want" "${got:-fehlt}"
done
mb=$(grep -aE '^const MISC_NOTURBO' kernel/pwr.fi | sed 's/.*= //' | sed 's/ .*//')
gleich "IA32_MISC_ENABLE Bit 38 (Turbo Mode Disable)" "274877906944" "$mb"
me=$(grep -aE '^const MISC_EIST' kernel/pwr.fi | sed 's/.*= //' | sed 's/ .*//')
gleich "IA32_MISC_ENABLE Bit 16 (SpeedStep Enable)" "65536" "$me"

# ==================================================== 2. bauen

echo "== 2. der Kern und die Programme =="

as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || { echo "as scheitert"; exit 1; }
rc=0
bash tools/build-kernel.sh "$TMPD/k0.mb" > "$TMPD/k0.log" 2>&1 || {
    bad "der Kern laesst sich nicht bauen"; sed 's/^/        /' "$TMPD/k0.log" | tail -8; rc=1; }
for p in $PROGS; do
    "$FIRNC" "kernel/user/$p.fi" -o "$TMPD/$p.o" > "$TMPD/$p.err" 2>&1 || {
        bad "firnc uebersetzt $p.fi nicht"; head -6 "$TMPD/$p.err"; rc=1; continue; }
    ld -T "$ULD" --defsym=USER_ENTRY=_F0.u_start -o "$TMPD/$p.elf" \
        "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null || { bad "ld scheitert an $p"; rc=1; continue; }
    strip --strip-all "$TMPD/$p.elf"
done
[ "$rc" = 0 ] && ok "der Kern und $(echo $PROGS | wc -w) Programme sind gebaut"
[ -f "$TMPD/k0.mb" ] || { echo "K18: ohne Kern geht nichts weiter"; echo "K18: $pass passed, $((fail+1)) failed"; exit 1; }

# Der zweite Uebersetzer -- derselbe Baum, in Firn geschrieben.
if bash tools/build-kernel.sh "$TMPD/k1.mb" --stufe 1 > "$TMPD/k1.log" 2>&1; then
    ok "firnc1 baut diese Runde auch (der Uebersetzer in Firn)"
else
    bad "firnc1 baut diese Runde nicht"; tail -5 "$TMPD/k1.log" | sed 's/^/        /'
fi

MKARGS=""
for p in $PROGS; do MKARGS="$MKARGS /bin/$p=$TMPD/$p.elf"; done
python3 tools/osum/mkfs.py build "$TMPD/root.img" "$BLOCKS" /bin/ $MKARGS \
    > "$TMPD/mkfs.log" 2>&1 && ok "die Platte steht: $(tail -1 "$TMPD/mkfs.log")" \
    || bad "mkfs.py scheitert"

# ================================================== die Tabellen bauen

echo "== 3. die ACPI-Tabellen, die dieser Testlauf vorgibt =="

mk_ssdt() { # name [argumente...]
    local n=$1; shift
    python3 tools/k18/ssdt.py "$TMPD/$n.aml" "$@" > "$TMPD/$n.soll" 2>&1 \
        && ok "SSDT '$n' gebaut: $(cat "$TMPD/$n.soll")" \
        || { bad "ssdt.py scheitert bei '$n'"; cat "$TMPD/$n.soll"; }
}
mk_ssdt akku
mk_ssdt laden --zustand 2 --rest 2200 --rate 1100 --netz 1
mk_ssdt heiss --temp 3632
mk_ssdt methode --methode
mk_ssdt ohneakku --kein-akku
mk_ssdt anders --rest 1100 --voll 5500 --rate 275 --temp 3232

# ------------------------------------------------------------- die Laeufe

lauf() { # name kommandozeile [ssdt] [cpu] [zeitlimit]
    # ${4:-max} WAERE HIER EIN FEHLER, und er ist in der ersten Fassung
    # dieses Laeufers auch passiert: `:-` greift nicht nur bei einem
    # FEHLENDEN Argument, sondern auch bei einem LEEREN. Die Gegenprobe
    # "eine CPU ohne MONITOR" bekam damit heimlich `-cpu max`, meldete
    # brav MONITOR und fiel durch. Deshalb wird das Modell hier immer
    # ausgeschrieben.
    local name=$1 zeile=$2 ssdt=${3:-} cpu=${4-max} t=${5:-120}
    local aus="$TMPD/$name.txt"
    rm -f "$aus"
    cp -f "$TMPD/root.img" "$TMPD/live-$name.img"
    local -a args
    args=(-kernel "$TMPD/k0.mb" -m 256 -append "$zeile" -serial "file:$aus"
          -display none -no-reboot
          -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0"
          -device isa-debug-exit,iobase=0xf4,iosize=0x04)
    [ -n "$cpu" ] && args+=(-cpu "$cpu")
    [ -n "$ssdt" ] && args+=(-acpitable
        "sig=SSDT,rev=2,oem_id=OSUM,oem_table_id=K18,data=$TMPD/$ssdt.aml")
    timeout "$t" qemu-system-x86_64 "${args[@]}" > /dev/null 2>&1
    echo $?
}

# Ein Lauf MIT Bildschirmfoto. Die Marke ist `pwr: shot` -- der Kernel
# schaltet dafuer die Konsole stumm und haelt fuenf Sekunden still, damit
# nichts mehr auf dem Schirm rollt, waehrend das Bild entsteht.
lauf_bild() { # name kommandozeile
    local name=$1 zeile=$2
    local sock="$TMPD/mon-$name.sock" aus="$TMPD/$name.txt" ppm="$TMPD/$name.ppm"
    rm -f "$aus" "$ppm" "$sock"
    timeout 150 qemu-system-x86_64 -cpu max -kernel "$TMPD/k0.mb" -m 256 \
        -append "$zeile" -serial "file:$aus" -display none -no-reboot \
        -vga std -monitor "unix:$sock,server,nowait" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1 &
    local pid=$! i=0
    while [ $i -lt 1200 ]; do
        grep -qa '^pwr: shot$' "$aus" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1; i=$((i + 1))
    done
    sleep 0.4
    python3 tools/gfx/screenshot.py "$sock" "$ppm" 25 > "$TMPD/$name.shot" 2>&1
    wait "$pid"
    rm -f "$sock"
}

GRUND="nokbd noproc nofs"

echo "== 4. die drei Profile: drei Schreibvorgaenge, drei Register =="

RC=$(lauf profile "$GRUND pwr" akku)
num "der Lauf endet sauber (21 = der Kernel hat sich selbst beendet)" "$RC" eq 21
P="$TMPD/profile.txt"

# Die Erkundung hat stattgefunden und der Kernel sagt, was er gefunden hat.
caps=$(uw "$P" caps)
num "CPUID hat etwas gefunden (caps)" "${caps:-0}" gt 0
ratios=$(uw "$P" ratios)
num "die Taktstufen sind gesetzt" "${ratios:-0}" gt 0
orig=$(uw "$P" miscorig)
if [ -z "$orig" ]; then bad "miscorig fehlt -- ohne den Anfangswert ist keine Zusage moeglich"; fi

# --- DIE ZUSAGE DER RUNDE ---
# Dreimal dieselbe Stelle, dreimal ein anderer Wert, und die Werte sind
# die aus dem Handbuch -- nachgerechnet von `expect.py`, nicht von hier.
for i in 0 1 2; do
    sagt "$P" "setrc$i" "0" "das Profil $i liess sich setzen"
    sagt "$P" "prof$i" "$i" "der Kernel steht danach wirklich auf Profil $i"
    want=$(soll perfctl "${ratios:-0}" "$i")
    sagt "$P" "perfctl$i" "$want" "IA32_PERF_CTL fuer Profil $i (Handbuch: expect.py)"
    wantm=$(soll misc "${orig:-0}" "$i")
    sagt "$P" "misc$i" "$wantm" "IA32_MISC_ENABLE fuer Profil $i (Handbuch: expect.py)"
    # UND DAS IST DER EIGENTLICHE BEWEIS: derselbe Wert, aus dem
    # PROZESSOR ZURUECKGELESEN.
    sagt "$P" "miscback$i" "$wantm" "IA32_MISC_ENABLE Profil $i ZURUECKGELESEN"
done

# Drei verschiedene Werte -- nicht dreimal derselbe.
m0=$(uw "$P" miscback0); m1=$(uw "$P" miscback1); m2=$(uw "$P" miscback2)
if [ -n "$m0" ] && [ -n "$m1" ] && [ -n "$m2" ] \
   && [ "$m0" != "$m1" ] && [ "$m1" != "$m2" ] && [ "$m0" != "$m2" ]; then
    ok "dieselbe Stelle, dreimal gelesen, DREI VERSCHIEDENE Werte: $m0 / $m1 / $m2"
else
    bad "IA32_MISC_ENABLE liest sich nicht dreimal verschieden: '$m0' '$m1' '$m2'"
fi
p0=$(uw "$P" perfctl0); p1=$(uw "$P" perfctl1); p2=$(uw "$P" perfctl2)
if [ -n "$p0" ] && [ "$p0" != "$p1" ] && [ "$p1" != "$p2" ] && [ "$p0" != "$p2" ]; then
    ok "IA32_PERF_CTL bekommt drei verschiedene Woerter: $p0 / $p1 / $p2"
else
    bad "IA32_PERF_CTL bekommt nicht drei verschiedene Woerter: '$p0' '$p1' '$p2'"
fi

# Die Turbosperre ist GENAU im Sparprofil gesetzt und sonst nicht.
bit38=274877906944
for i in 0 1 2; do
    v=$(uw "$P" "miscback$i")
    an=$(python3 -c "print(1 if (int('${v:-0}') & $bit38) else 0)" 2>/dev/null)
    if [ "$i" = 0 ]; then
        gleich "Turbo ist bei Energiesparen GESPERRT (Bit 38)" "1" "$an"
    else
        gleich "Turbo ist bei Profil $i FREI (Bit 38 = 0)" "0" "$an"
    fi
done
# Und SpeedStep ist bei Hoechstleistung aus (der Takt bleibt oben).
b16=65536
for i in 0 1 2; do
    v=$(uw "$P" "miscback$i")
    an=$(python3 -c "print(1 if (int('${v:-0}') & $b16) else 0)" 2>/dev/null)
    if [ "$i" = 2 ]; then
        gleich "SpeedStep ist bei Hoechstleistung AUS" "0" "$an"
    else
        gleich "SpeedStep ist bei Profil $i AN" "1" "$an"
    fi
done

# DIE EHRLICHKEIT: was NICHT zurueckgelesen werden konnte, steht auch so
# da. Das ist eine Zusage ueber den WIRT, nicht ueber den Kernel -- und
# sie faellt auf, wenn ein neueres QEMU das Register doch behaelt.
pb=$(uw "$P" perfback0)
gleich "IA32_PERF_CTL liest sich auf diesem Wirt als 0 zurueck (QEMU schluckt es)" "0" "${pb:-fehlt}"

# HWP ist hier nicht ausfuehrbar -- der Kernel darf es dann auch nicht
# benutzen. C_HWP ist Bit 4 (16).
hwpan=$(python3 -c "print(1 if (int('${caps:-0}') & 16) else 0)" 2>/dev/null)
gleich "CPUID meldet KEIN HWP auf diesem Wirt (der Pfad bleibt unbetreten)" "0" "$hwpan"
sagt "$P" "hwpreq0" "0" "und folglich wird IA32_HWP_REQUEST nie beschrieben"

# Die HWP-KODIERUNG wird trotzdem geprueft -- als reine Funktion, gegen
# expect.py. Das prueft die Kodierung, NICHT die Wirkung, und wird auch
# genau so benannt.
for i in 0 1 2; do
    a=$(soll hwp "${ratios:-0}" "$i")
    if [ -n "$a" ] && [ "$a" -gt 0 ]; then
        ok "die HWP-Kodierung fuer Profil $i ist berechenbar: $a (NUR die Kodierung, nicht die Wirkung)"
    else
        bad "die HWP-Kodierung fuer Profil $i ergibt nichts"
    fi
done

echo "== 5. der Ruhezustand: benutzt der Leerlaufpfad wirklich mwait? =="

# Die Zaehler VORHER und NACHHER, um ein Programm herum, das SCHLAEFT --
# und um eines herum, das RECHNET. Der Unterschied kommt aus der
# Beschaeftigung der Maschine und nicht aus einem Schalter.
mi=$(uw "$P" mwaits_idle); hi=$(uw "$P" hlts_idle); ii=$(uw "$P" idleruns_idle)
ml=$(uw "$P" mwaits_load); il=$(uw "$P" idleruns_load)
num "waehrend ein Programm SCHLAEFT laeuft der Leerlaufpfad" "${ii:-0}" gt 20
num "und er geht dabei wirklich in mwait" "${mi:-0}" gt 20
gleich "kein einziger Rueckfall auf hlt, solange mwait geht" "0" "${hi:-fehlt}"
gleich "jeder Durchlauf ging in mwait" "${ii:-x}" "${mi:-y}"
num "waehrend ein Programm RECHNET laeuft er fast nie" "${il:-99}" lt 5
if [ -n "$ii" ] && [ -n "$il" ] && [ "$ii" -gt $((il + 20)) ]; then
    ok "schlafend $ii Durchlaeufe gegen rechnend $il -- der Unterschied kommt aus der Maschine"
else
    bad "kein Unterschied zwischen schlafend ($ii) und rechnend ($il)"
fi
sagt "$P" "mwaithint" "0" "der mwait-Hinweis ist C1 (CPUID Blatt 5 EDX = 0: nichts Tieferes angeboten)"
sagt "$P" "cstate" "1" "und der Kernel behauptet auch nichts Tieferes"

# --- GEGENPROBE A: derselbe Kernel, C-Zustaende im Kernel abgeschaltet.
RC=$(lauf nocst "$GRUND pwr nocstates" akku)
num "der Gegenlauf nocstates endet sauber" "$RC" eq 21
N="$TMPD/nocst.txt"
ncaps=$(uw "$N" caps)
gleich "die MASCHINE kann es immer noch (dieselben caps)" "${caps:-a}" "${ncaps:-b}"
gleich "aber es wird kein einziges mwait mehr ausgefuehrt" "0" "$(uw "$N" mwaits_idle)"
nh=$(uw "$N" hlts_idle); ni=$(uw "$N" idleruns_idle)
num "stattdessen faellt jeder Durchlauf auf hlt zurueck" "${nh:-0}" gt 20
gleich "und zwar JEDER" "${ni:-x}" "${nh:-y}"

# --- GEGENPROBE B: eine CPU, die MONITOR/MWAIT gar nicht hat.
RC=$(lauf nomon "$GRUND pwr" akku qemu64)
num "der Gegenlauf mit -cpu qemu64 endet sauber" "$RC" eq 21
M="$TMPD/nomon.txt"
mcaps=$(uw "$M" caps)
mon=$(python3 -c "print(1 if (int('${mcaps:-0}') & 2) else 0)" 2>/dev/null)
gleich "qemu64 meldet KEIN MONITOR (CPUID.01H:ECX Bit 3)" "0" "$mon"
gleich "und dann geht der Kernel auch nicht hinein" "0" "$(uw "$M" mwaits_idle)"
num "sondern faellt auf hlt zurueck" "$(uw "$M" hlts_idle)" gt 20

echo "== 6. der Akku: die Zahlen kommen aus der Tabelle, nicht aus dem Programm =="

# Die Sollwerte stehen in der Zeile, die ssdt.py beim BAUEN gedruckt hat
# -- also aus derselben Quelle wie die Tabelle und nicht aus diesem Skript.
soll_feld() { sed -E "s/.*$2=([0-9-]+).*/\1/" "$TMPD/$1.soll"; }

sagt "$P" "batpresent" "1" "der Akku aus der SSDT wird gefunden"
sagt "$P" "batwhy" "0" "und ohne Beanstandung gelesen"
sagt "$P" "percent"  "$(soll_feld akku prozent)" "der Ladestand ist der aus der Tabelle"
sagt "$P" "minutes"  "$(soll_feld akku minuten)" "die Restzeit ebenso"
sagt "$P" "batremain" "3300" "die Restkapazitaet ist die aus _BST"
sagt "$P" "batfull"   "4400" "die letzte volle Ladung ist die aus _BIF"
sagt "$P" "batrate"   "500"  "der Strom ist der aus _BST"
sagt "$P" "batstate"  "1"    "der Zustand ist der aus _BST (1 = entlaedt)"
sagt "$P" "acok" "1" "das Netzteilgeraet wird gefunden"
sagt "$P" "ac"   "0" "und es sagt: Akkubetrieb"
num "es wurden mehrere ACPI-Tabellen durchsucht" "$(uw "$P" tables)" ge 5

# --- ANDERE ZAHLEN IN DER TABELLE -> ANDERE AUSGABE. Das ist der
#     Unterschied zwischen einer Messung und einer Konstante.
RC=$(lauf laden "$GRUND pwr" laden)
L="$TMPD/laden.txt"
sagt "$L" "percent" "$(soll_feld laden prozent)" "geladener Akku: der Ladestand folgt der Tabelle"
sagt "$L" "minutes" "$(soll_feld laden minuten)" "und die Zeit BIS VOLL statt bis leer"
sagt "$L" "batstate" "2" "der Zustand sagt 'laedt'"
sagt "$L" "ac" "1" "und das Netzteil ist angesteckt"
pz1=$(uw "$P" percent); pz2=$(uw "$L" percent)
if [ -n "$pz1" ] && [ "$pz1" != "$pz2" ]; then
    ok "zwei Tabellen, zwei Ladestaende: $pz1% gegen $pz2%"
else
    bad "beide Tabellen ergeben denselben Ladestand ('$pz1'/'$pz2') -- dann misst das nichts"
fi

RC=$(lauf anders "$GRUND pwr" anders)
A="$TMPD/anders.txt"
sagt "$A" "percent" "$(soll_feld anders prozent)" "eine dritte Tabelle, ein dritter Ladestand"
sagt "$A" "minutes" "$(soll_feld anders minuten)" "und eine dritte Restzeit"

# --- GEGENPROBE C: gar keine Tabelle. Dann gibt es keinen Akku, und der
#     Kernel sagt das, statt eine Zahl zu raten.
RC=$(lauf keinetab "$GRUND pwr" "")
K="$TMPD/keinetab.txt"
sagt "$K" "batpresent" "0" "GEGENPROBE: ohne SSDT wird kein Akku gemeldet"
sagt "$K" "percent" "-19" "und der Ladestand ist -ENODEV, keine Null"
sagt "$K" "acok" "0" "auch kein Netzteilgeraet"

# --- GEGENPROBE D: `_BST` als METHODE statt als konstantes Paket. Das ist
#     die Form, die ein echter Laptop hat -- und die dieser Kernel
#     ausdruecklich NICHT lesen kann. Er MUSS das zugeben.
RC=$(lauf meth "$GRUND pwr" methode)
ME="$TMPD/meth.txt"
sagt "$ME" "batpresent" "0" "GEGENPROBE: _BST als Methode wird NICHT gelesen"
sagt "$ME" "percent" "-19" "und es wird auch keine Zahl geraten"
sagt "$ME" "acok" "1" "das konstante _PSR daneben wird weiterhin gefunden"

# --- GEGENPROBE E: eine Tabelle ohne Akku, aber mit Netzteil und Zone.
RC=$(lauf ohnebat "$GRUND pwr" ohneakku)
O="$TMPD/ohnebat.txt"
sagt "$O" "batpresent" "0" "GEGENPROBE: SSDT ohne Akku -> kein Akku"
sagt "$O" "acok" "1" "aber das Netzteil steht drin und wird gefunden"
sagt "$O" "tempok" "1" "und die Thermalzone auch"

echo "== 7. die Temperatur und die Drosselung =="

sagt "$P" "tempok" "1" "es gibt eine Temperatur"
sagt "$P" "tzraw" "3032" "und zwar die rohe Zahl aus _TMP (Zehntelkelvin)"
sagt "$P" "temp" "$(soll_feld akku grad)" "in Grad Celsius umgerechnet"
sagt "$P" "throttles" "0" "bei 30 Grad wird nicht gedrosselt"
sagt "$P" "throttled" "0" "und nichts ist gedeckelt"

# DIE DROSSELUNG, AUSGELOEST VON DER TABELLE. Neunzig Grad in _TMP.
RC=$(lauf heiss "$GRUND pwr" heiss)
H="$TMPD/heiss.txt"
sagt "$H" "temp" "$(soll_feld heiss grad)" "die heisse Tabelle wird gelesen"
num "und sie loest die Drosselung aus" "$(uw "$H" throttles)" ge 1
sagt "$H" "throttled" "1" "der Kernel steht danach auf gedrosselt"
hat "$H" "pwr: throttle at" "die Drosselung meldet sich mit der Temperatur"
# UND DAS IST DER PUNKT: Ring 3 verlangt Hoechstleistung und bekommt sie
# NICHT. Ein Deckel, der sich uebergehen laesst, ist keiner.
sagt "$H" "prof2" "0" "GEDROSSELT: 'Hoechstleistung' wird auf Energiesparen gedeckelt"
sagt "$H" "prof1" "0" "auch 'Ausgeglichen' kommt nicht durch"
sagt "$H" "setrc2" "0" "der Aufruf selbst schlaegt dabei NICHT fehl (er wird gedeckelt, nicht abgelehnt)"
# Gegenprobe: bei 30 Grad kommt Hoechstleistung sehr wohl durch.
sagt "$P" "prof2" "2" "GEGENPROBE kalt: dort geht Hoechstleistung durch"

# Auf diesem Wirt gibt es KEINE Anzeige im Prozessor selbst. Das wird
# festgehalten, nicht beschoenigt -- und es faellt auf, wenn ein neueres
# QEMU eine liefert.
ksagt "$P" "tjmax" "0" "IA32_TEMPERATURE_TARGET ist auf diesem Wirt 0 (keine Schwelle im Prozessor)"
dts=$(python3 -c "print(1 if (int('${caps:-0}') & 4) else 0)" 2>/dev/null)
gleich "und CPUID meldet auch keinen digitalen Temperatursensor" "0" "$dts"

echo "== 8. der Bildschirm, im BILD gemessen und an einer ausgerechneten Stelle =="

if ! command -v python3 >/dev/null 2>&1; then
    echo "  (uebersprungen, python3 fehlt)"
else
    lauf_bild hell   "$GRUND nosched gfx pwr noblank"
    lauf_bild dunkel "$GRUND nosched gfx pwr pwrdim noblank"
    lauf_bild aus    "$GRUND nosched gfx pwr pwrblank noblank"

    # Was der Kernel aus dem Rahmenpuffer ZURUECKGELESEN hat.
    ksagt "$TMPD/hell.txt" "px_a" "0xc86432" "der Kernel malt 200/100/50 und liest es zurueck"
    ksagt "$TMPD/dunkel.txt" "px_b" "0x643219" "bei 50 Prozent steht dort genau die Haelfte"
    ksagt "$TMPD/dunkel.txt" "px_c" "0xc86432" "und beim Zurueckregeln auf 100 wieder der alte Wert"
    ksagt "$TMPD/aus.txt" "px_d" "0x0" "abgeschaltet ist der Bildpunkt schwarz"
    ksagt "$TMPD/aus.txt" "px_e" "1" "und der Zaehler der Abschaltungen steht auf eins"

    # UND JETZT IM BILD. Nicht "es ist dunkler geworden" -- EIN Bildpunkt
    # an EINER Stelle gegen EINEN ausgerechneten Wert.
    rgb() { python3 -c "v=int('$1',0);print((v>>16)&255,(v>>8)&255,v&255)"; }
    gleich "im BILD bei (120,120): das Pruefbild steht da" \
        "$(rgb 0xc86432)" "$(punkt "$TMPD/hell.ppm" 120 120)"
    gleich "im BILD bei (120,120) mit pwrdim: genau die Haelfte" \
        "$(rgb "$(soll skala 13132850 100 50)")" "$(punkt "$TMPD/dunkel.ppm" 120 120)"
    gleich "im BILD bei (120,120) mit pwrblank: schwarz" \
        "0 0 0" "$(punkt "$TMPD/aus.ppm" 120 120)"
    # DIE KANTEN. Ohne die waere "da ist die Farbe" auch dann wahr, wenn
    # der ganze Schirm so aussaehe.
    gleich "die linke obere Ecke des Pruefbildes (100,100) traegt die Farbe" \
        "$(rgb 0xc86432)" "$(punkt "$TMPD/hell.ppm" 100 100)"
    gleich "die rechte untere (163,163) auch" \
        "$(rgb 0xc86432)" "$(punkt "$TMPD/hell.ppm" 163 163)"
    gleich "und einen Bildpunkt DANEBEN (164,164) ist nichts" \
        "0 0 0" "$(punkt "$TMPD/hell.ppm" 164 164)"
    gleich "und daneben (99,99) auch nicht" \
        "0 0 0" "$(punkt "$TMPD/hell.ppm" 99 99)"

    # Die beiden Bilder sind WIRKLICH verschieden -- sonst haette die
    # Helligkeit nichts getan.
    h=$(punkt "$TMPD/hell.ppm" 120 120); d=$(punkt "$TMPD/dunkel.ppm" 120 120)
    if [ -n "$h" ] && [ "$h" != "$d" ]; then
        ok "dasselbe Pruefbild, ein Wort Unterschied, zwei Farben: '$h' gegen '$d'"
    else
        bad "beide Bilder zeigen dasselbe ('$h'/'$d') -- dann regelt nichts"
    fi
fi

echo "== 9. /bin/power: dieselben Zahlen, aus Ring 3 ueber die Platte =="

RC=$(lauf shell "osum nokbd nosched noproc pwr script=power roh;power;power leistung;power" akku)
num "der Lauf mit /bin/power endet sauber" "$RC" eq 21
S="$TMPD/shell.txt"
hat "$S" "osum\$ power" "das Programm ist gestartet"

# DIE BEIDEN WEGE MUESSEN DASSELBE SAGEN. Links die Meldung des Kernels
# auf der seriellen Leitung, rechts das, was ein Programm in Ring 3 ueber
# `syscall` herausbekommt.
for f in percent minutes batremain batfull batrate temp tzraw caps ratios; do
    a=$(kw "$S" "$f"); b=$(pw "$S" "$f")
    # der Kernel meldet hex mit 0x, /bin/power dezimal -- also beide
    # ueber dieselbe Umrechnung schicken
    a=$(hexdez "${a:-0}"); b=$(hexdez "${b:-0}")
    if [ -z "$(kw "$S" "$f")" ] || [ -z "$(pw "$S" "$f")" ]; then
        bad "$f: einer der beiden Wege sagt gar nichts (Kernel '$(kw "$S" "$f")', Ring 3 '$(pw "$S" "$f")')"
    else
        gleich "$f: Kernelmeldung und /bin/power sagen dasselbe" "$a" "$b"
    fi
done

hat "$S" "Profil:" "die Uebersicht nennt das Profil"
hat "$S" "Ausgeglichen" "und zwar beim Namen"
hat "$S" "Akku:" "sie nennt den Akku"
hat "$S" "OSUM-BAT" "und den Modellnamen aus _BIF"
hat "$S" "Netz:" "sie nennt das Netzteil"
hat "$S" "Waerme:" "sie nennt die Temperatur"
hat "$S" "Ruhe:" "sie nennt den Ruhezustand"
hat "$S" "power: jetzt auf Hoechstleistung" "das Umschalten meldet sich"
hat "$S" "Profil:  Hoechstleistung" "und danach steht wirklich Hoechstleistung da"
# Der Ladestand steht als Zahl UND als Balken da.
if grep -qa '75%' "$S"; then ok "der Ladestand steht als Zahl da (75%)"
else bad "der Ladestand 75% steht nicht in der Uebersicht"; fi
if grep -qaE '\[#+\.*\]' "$S"; then ok "und als Balken"
else bad "der Balken fehlt"; fi

# GEGENPROBE F: dasselbe Programm ohne die Schicht.
RC=$(lauf shellaus "osum nokbd nosched noproc nopwr script=power" akku)
SA="$TMPD/shellaus.txt"
hat "$SA" "power: die Energieschicht laeuft nicht" "GEGENPROBE nopwr: /bin/power sagt es und rechnet nicht weiter"
hat_nicht "$SA" "Profil:" "und zeigt kein Profil"
hat_nicht "$SA" "Akku:" "und keinen Akku"
hat "$SA" "pwr: skipped" "der Kernel sagt es ebenfalls"

echo "== 10. die Schnittstelle weist ab, was sie abweisen muss =="

# Ein Profil, das es nicht gibt, und ein Feld, das es nicht gibt.
# (Das prueft das Programm in Ring 3 mit; hier wird die Meldung gelesen.)
sagt "$P" "applies" "$(uw "$P" applies)" "die Zahl der Anwendungen wird gefuehrt"
ap=$(uw "$P" applies); sw=$(uw "$P" switches)
num "es wurde mehr als einmal ein Profil angewandt" "${ap:-0}" ge 4
num "und mehr als einmal wirklich gewechselt" "${sw:-0}" ge 3

echo
echo "K18: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
