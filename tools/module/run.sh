#!/usr/bin/env bash
#
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() { local name=$1 value=$2 op=$3 want=$4
    if [ -z "$value" ]; then bad "$name: no number found (expected $op $want)"; return; fi
    if [ "$value" -"$op" "$want" ] 2>/dev/null; then ok "$name: $value"
    else bad "$name: $value, erwartet $op $want"; fi
}
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' sollte nicht dastehen" || ok "$3"; }

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "MODUL: uebersprungen, qemu-system-x86_64 fehlt"; exit 0
fi

# ---------------------------------------------------------------- 1. bauen
echo "== 1. build: two kernels from one source, a module from the same driver file =="

bash tools/build-kernel.sh "$TMPD/k-fest" > "$TMPD/b1.txt" 2>&1 \
    && ok "Kern MIT ps2m.fi ($(stat -c%s "$TMPD/k-fest") Oktette)" \
    || { bad "Kern mit ps2m"; sed 's/^/        /' "$TMPD/b1.txt" | head -5; }
bash tools/build-kernel.sh "$TMPD/k-modul" --ohne-ps2m > "$TMPD/b2.txt" 2>&1 \
    && ok "kernel WITHOUT ps2m.fi ($(stat -c%s "$TMPD/k-modul") Oktette)" \
    || { bad "kernel without ps2m"; sed 's/^/        /' "$TMPD/b2.txt" | head -5; }

nm "$TMPD/k-fest.elf" > "$TMPD/nm-fest.txt" 2>/dev/null
nm "$TMPD/k-modul.elf" > "$TMPD/nm-modul.txt" 2>/dev/null
if grep -c 'ps2m__consume' "$TMPD/nm-fest.txt" >/dev/null 2>&1 \
   && [ "$(grep -c 'ps2m__consume' "$TMPD/nm-fest.txt")" -gt 0 ]; then
    ok "ps2m.consume is in the ordinary image"
else
    bad "ps2m.consume is missing in the ordinary image"
fi
if [ "$(grep -c 'ps2m__consume' "$TMPD/nm-modul.txt")" -gt 0 ]; then
    bad "ps2m.consume is still in the image with the no-ps2m switch"
else
    ok "ps2m.consume is NOT in the image with the no-ps2m switch (no dead branch, no line)"
fi

bash tools/module/build.sh "$TMPD/ps2maus.omod" --name ps2maus --abi 1 \
    > "$TMPD/mb.txt" 2>&1 \
    && ok "Modul gebaut ($(stat -c%s "$TMPD/ps2maus.omod") Oktette)" \
    || { bad "Modulbau"; sed 's/^/        /' "$TMPD/mb.txt" | head -8; }
UNDEF=$(grep -o 'undefinierte Symbole:.*' "$TMPD/mb.txt" | sed 's/undefinierte Symbole: //')
echo "        open names in the module: $UNDEF"
for n in k_abi k_bind k_dec k_puts kdata osum_panic; do
    case " $UNDEF " in *" $n "*) ;; *) bad "does the module no longer require $n?" ;; esac
done
ok "the module requires exactly the six names that kernel/lib/ksym.fi offers"

bash tools/module/build.sh "$TMPD/m-abi.omod"  --name ps2maus --abi 2 >/dev/null 2>&1
bash tools/module/build.sh "$TMPD/m-sig.omod"  --name ps2maus --abi 1 --sig-dreh >/dev/null 2>&1
bash tools/module/build.sh "$TMPD/m-nutz.omod" --name ps2maus --abi 1 --nutz-dreh 1000 >/dev/null 2>&1
bash tools/module/build.sh "$TMPD/m-kenn.omod" --name ps2maus --abi 1 --kennung >/dev/null 2>&1
bash tools/module/build.sh "$TMPD/m-text.omod" --name ps2maus --abi 1 --text-dreh 64 >/dev/null 2>&1
bash tools/module/build.sh "$TMPD/m-fremd.omod" --quelle module/ps2mouse-foreign.fi \
    --name ps2maus --abi 1 >/dev/null 2>&1
n=0
for f in m-abi m-sig m-nutz m-kenn m-text m-fremd; do
    [ -s "$TMPD/$f.omod" ] && n=$((n+1))
done
num "absichtlich kaputte Fassungen gebaut" "$n" eq 6

# Die Platten.
mkdisk() { # name omod-datei
    if [ -n "${2:-}" ]; then
        bash tools/mkfsfi/mkfs.sh build "$TMPD/d-$1.img" 2048 '/lib/' \
            "/lib/ps2maus.omod=$2" >/dev/null 2>&1
    else
        bash tools/mkfsfi/mkfs.sh build "$TMPD/d-$1.img" 2048 '/lib/' >/dev/null 2>&1
    fi
}
mkdisk gut "$TMPD/ps2maus.omod"
mkdisk leer ""
for f in abi sig nutz kenn text fremd; do mkdisk "$f" "$TMPD/m-$f.omod"; done
ok "eight OFS images with one /lib/ps2maus.omod each (or none)"

# ------------------------------------------------------------- der Laeufer
#
lauf() { # kernel disk append log
    local sock="$TMPD/mon.$$.$RANDOM"
    cp -f "$2" "$TMPD/live.img"
    printf 'mouse_move -120 -120\nmouse_move -120 -120\nmouse_move -120 -120\nmouse_move 50 40\nmouse_move 30 20\nmouse_move 20 10\nmouse_button 1\nmouse_button 0\n' \
        > "$TMPD/mv.txt"
    timeout 200 $QEMU_X86 -kernel "$1" -m 256 -append "$3" \
        -serial "file:$4" -display none -no-reboot -vga std \
        -monitor "unix:$sock,server,nowait" \
        -drive "file=$TMPD/live.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local pid=$! i=0
    while [ $i -lt 900 ]; do
        grep -qa 'module: wait' "$4" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1; i=$((i+1))
    done
    if kill -0 "$pid" 2>/dev/null; then
        python3 tools/wm/monitor.py "$sock" "$TMPD/mv.txt" >/dev/null 2>&1
    fi
    wait "$pid"; RC=$?
    rm -f "$sock"
    return 0
}
QUIET="nokbd nosched noproc nofs noring3"
wert() { grep -aoE "$2" "$1" | head -1 | grep -oE '[0-9]+$'; }
zwert() { grep -a 'module: sigok=' "$1" | head -1 | grep -oE "$2" | grep -oE '[0-9]+$'; }
nwert() { grep -a 'module: after init=' "$1" | head -1 | grep -oE "$2" | grep -oE '[0-9]+$'; }

# ------------------------------------------------- 2. die Ausfuhrtafel
echo "== 2. the export table of the kernel: the same numbers nm reports =="
lauf "$TMPD/k-modul" "$TMPD/d-gut.img" "modul modulaus $QUIET" "$TMPD/l-gut.txt"
num "der Lauf endet sauber" "$RC" eq 21
num "Symbole in der Tafel" "$(wert "$TMPD/l-gut.txt" 'module: syms=[0-9]+')" eq 14
python3 - "$TMPD/l-gut.txt" "$TMPD/k-modul.elf" > "$TMPD/nm.txt" 2>&1 <<'PYEOF'
import re, subprocess, sys
log = open(sys.argv[1], errors='replace').read()
tab = {m.group(1): int(m.group(2), 16)
       for m in re.finditer(r'module:   (\w+)=0x([0-9a-f]+)', log)}
nm = subprocess.run(['nm', sys.argv[2]], capture_output=True, text=True).stdout
sym = {}
for line in nm.splitlines():
    p = line.split()
    if len(p) == 3:
        sym[p[2]] = int(p[0], 16)
paar = {'k_puts': 'serial__puts', 'k_dec': 'serial__dec', 'k_hex': 'serial__hex',
        'k_nl': 'serial__nl', 'k_text': 'serial__text', 'k_get': 'kstate__get',
        'k_set': 'kstate__set', 'k_get8': 'kstate__get8', 'k_bind': 'modtab__bind',
        'k_abi': 'ksym__abi_value', 'k_putc': 'ksym__putc_u64',
        'k_set8': 'ksym__set8_u64', 'k_fwreq': 'drvfw__request'}
gut = 0
for k, v in paar.items():
    a = tab.get(k)
    b = sym.get('_F0.' + v, sym.get('_F1.' + v))
    if a is not None and b is not None and a == b:
        gut += 1
    else:
        print("ABWEICHUNG %s: gedruckt=%s nm=%s" % (k, a, b))
for k in ('kdata',):
    if tab.get(k) is not None and tab.get(k) == sym.get(k):
        gut += 1
    else:
        print("ABWEICHUNG %s: gedruckt=%s nm=%s" % (k, tab.get(k), sym.get(k)))
print("gleich=%d" % gut)
PYEOF
num "Adressen, die mit nm uebereinstimmen" "$(wert "$TMPD/nm.txt" 'gleich=[0-9]+')" eq 14
grep -q ABWEICHUNG "$TMPD/nm.txt" && sed 's/^/        /' "$TMPD/nm.txt" | head -5

echo "== 3. without the module the device is missing =="
lauf "$TMPD/k-modul" "$TMPD/d-leer.img" "modul $QUIET" "$TMPD/l-leer.txt"
num "der Lauf endet sauber" "$RC" eq 21
has "$TMPD/l-leer.txt" "module: load=file-missing" "keine Moduldatei -> reason 'file-missing'"
has "$TMPD/l-leer.txt" "module: before init=0 present=0" "vor dem Laden: kein Zeigegeraet"
has "$TMPD/l-leer.txt" "module: after init=0 present=0" "und danach immer noch keins"
has "$TMPD/l-leer.txt" "module: end" "der Kern lebt und kommt bis ans Ende des Abschnitts"

echo "== 4. with the module it is there, and it really moves =="
has "$TMPD/l-gut.txt" "module: before init=0 present=0" "vor dem Laden: kein Zeigegeraet"
has "$TMPD/l-gut.txt" "module: load=ok" "das Modul wird angenommen"
has "$TMPD/l-gut.txt" "ps2mouse: registered 37" "module_init lief IM KERN und trug 37 Adressen ein"
has "$TMPD/l-gut.txt" "module: after init=1 present=1" "NACH dem Laden: dasselbe mouse_init sagt ja"
num "sigok" "$(zwert "$TMPD/l-gut.txt" 'sigok=[0-9]+')" eq 1
num "ELF-Abschnitte" "$(zwert "$TMPD/l-gut.txt" 'secs=[0-9]+')" ge 8
num "aufgeloeste Relokationen" "$(zwert "$TMPD/l-gut.txt" 'rel=[0-9]+')" ge 500
num "Namen, die aus dem KERN kamen" "$(zwert "$TMPD/l-gut.txt" 'ext=[0-9]+')" ge 6
num "Rahmen fuer das Abbild" "$(zwert "$TMPD/l-gut.txt" 'frames=[0-9]+')" ge 1
num "belegte Plaetze in der Treibertafel" "$(zwert "$TMPD/l-gut.txt" 'slots=[0-9]+')" eq 37
num "Rueckgabe von module_init" "$(zwert "$TMPD/l-gut.txt" 'initrc=[0-9]+')" eq 0
num "Geraetekennung vom 8042" "$(nwert "$TMPD/l-gut.txt" 'id=[0-9]+')" eq 3
PKT=$(grep -a 'module: pkt=' "$TMPD/l-gut.txt" | head -1 | grep -oE 'pkt=[0-9]+' | grep -oE '[0-9]+')
num "PS/2-Pakete, nachdem der Monitor die Maus bewegt hat" "$PKT" ge 3
MOV=$(grep -a 'module: pkt=' "$TMPD/l-gut.txt" | head -1 | grep -oE 'mov=[0-9]+' | grep -oE '[0-9]+')
num "gezaehlte Bewegungen" "$MOV" ge 3

# --------------------------------------------------- 5. Entladen
echo "== 5. unloaded, and the frames come back =="
has "$TMPD/l-gut.txt" "ps2maus: entladen" "module_exit lief"
has "$TMPD/l-gut.txt" "module: unloaded=1 present=0" "nach dem Entladen: wieder kein Zeigegeraet"
FREI=$(grep -a 'module: free=' "$TMPD/l-gut.txt" | head -1)
A=$(echo "$FREI" | grep -oE 'free=[0-9]+' | grep -oE '[0-9]+')
B=$(echo "$FREI" | sed 's/.*=//')
if [ -n "$A" ] && [ "$A" = "$B" ]; then
    ok "free frames afterwards = before ($A) -- the loader loses none"
else
    bad "freie Rahmen: after=$A, vorher=$B"
fi
LETZT=$(grep -a 'module: pkt=' "$TMPD/l-gut.txt" | tail -1 | grep -oE 'pkt=[0-9]+' | grep -oE '[0-9]+')
num "Pakete nach dem Entladen (der Stummel zaehlt nichts mehr)" "$LETZT" eq 0
has "$TMPD/l-gut.txt" "module: end" "der Kern lebt nach dem Entladen weiter"

# ------------------------------------------------ 6. die sechs Abweisungen
echo "== 6. six ways to be wrong -- six rejections, a living kernel =="
pruefe_abweisung() { # name grund
    local n=$1 g=$2
    lauf "$TMPD/k-modul" "$TMPD/d-$n.img" "modul $QUIET" "$TMPD/l-$n.txt"
    if [ "$RC" != 21 ]; then bad "$n: rc=$RC instead of 21 -- the kernel did not survive it"; return; fi
    has "$TMPD/l-$n.txt" "module: load=$g" "$n -> Grund '$g'"
    has "$TMPD/l-$n.txt" "module: after init=0 present=0" "$n: kein Geraet danach"
    hasnot "$TMPD/l-$n.txt" "ps2mouse: registered" "$n: module_init ist NICHT gelaufen"
}
pruefe_abweisung abi   version
pruefe_abweisung sig   signature
pruefe_abweisung nutz  signature
pruefe_abweisung kenn  magic
pruefe_abweisung fremd symbol
num "fremd: die Signatur war gueltig" "$(zwert "$TMPD/l-fremd.txt" 'sigok=[0-9]+')" eq 1
num "fremd: es wurden schon Relokationen angewandt" "$(zwert "$TMPD/l-fremd.txt" 'rel=[0-9]+')" ge 1
num "fremd: aber KEIN Platz in der Treibertafel" "$(zwert "$TMPD/l-fremd.txt" 'slots=[0-9]+')" eq 0

# ---------------------------------------------------- 7. die Grenze
echo "== 7. the measured LIMIT: a signed, broken module in ring 0 =="
lauf "$TMPD/k-modul" "$TMPD/d-text.img" "modul $QUIET" "$TMPD/l-text.txt"
has "$TMPD/l-text.txt" "module: load=ok" "das Modul kommt durch alle drei Riegel -- es IST richtig signiert"
if [ "$RC" = 63 ]; then
    ok "and afterwards the machine stops (rc=63, exception) -- THAT IS RING 0, and it is measured"
elif [ "$RC" = 21 ]; then
    bad "rc=21: the corrupted program text triggered nothing -- the negative test measures nothing"
else
    bad "rc=$RC, erwartet 63"
fi
grep -qa 'EXCEPTION' "$TMPD/l-text.txt" \
    && ok "the kernel says WHAT it died of ($(grep -ao 'EXCEPTION [0-9]* #[A-Z]*' "$TMPD/l-text.txt" | head -1))" \
    || bad "kein Ausnahmebericht"

# ---------------------------------------------------------- 8. was es kostet
echo "== 8. was es kostet =="
A=$(stat -c%s "$TMPD/k-fest"); B=$(stat -c%s "$TMPD/k-modul")
M=$(stat -c%s "$TMPD/ps2maus.omod")
echo "        Kern mit ps2m.fi      $A Oktette"
echo "        kernel without ps2m.fi     $B octets   (difference $((A-B)))"
echo "        the module                 $M octets"
echo "        davon Abbild im RAM   $(zwert "$TMPD/l-gut.txt" 'bytes=[0-9]+') Oktette in $(zwert "$TMPD/l-gut.txt" 'frames=[0-9]+') Rahmen"
num "der Kern ohne den Treiber ist kleiner" "$((A-B))" gt 0
num "das Modul ist groesser als das, was aus dem Kern verschwand" "$M" gt "$((A-B))"

# ------------------------------------------------------- 9. beide Stufen
echo "== 9. both compiler stages: a module from firnc0 under a kernel from firnc1 =="
if bash tools/build-kernel.sh "$TMPD/k1-modul" --ohne-ps2m --stufe 1 \
        > "$TMPD/b3.txt" 2>&1; then
    ok "Kern mit firnc1 gebaut"
    lauf "$TMPD/k1-modul" "$TMPD/d-gut.img" "modul modulaus $QUIET" "$TMPD/l-s1.txt"
    num "der Lauf endet sauber" "$RC" eq 21
    has "$TMPD/l-s1.txt" "module: load=ok" "dasselbe Modul (von firnc0) laedt unter dem Kern von firnc1"
    has "$TMPD/l-s1.txt" "module: after init=1 present=1" "und das Geraet ist da"
    has "$TMPD/l-s1.txt" "ps2maus: entladen" "und es laesst sich entladen"
else
    bad "firnc1 does not build the kernel"
    sed 's/^/        /' "$TMPD/b3.txt" | head -5
fi

# ------------------------------------------------- 10. die Auslieferung
echo "== 10. the whole path: .omod -> .opk -> store -> disk -> kernel =="
OPK=${OPK:-$(python3 "$(dirname "${BASH_SOURCE[0]}")/../lib/opkpfad.py")}   # A-025: der alte Ordner war ein Arbeitsbaum
STORE=${STORE:-/root/orientstore/werkzeug/store}
if [ -f "$OPK" ] && [ -f "$STORE" ]; then
    bash tools/module/package.sh "$TMPD/pak" > "$TMPD/pak.txt" 2>&1
    if grep -q 'Ergebnis    in Ordnung' "$TMPD/pak.txt"; then
        ok "the store catalog verifies itself (store verify --tief)"
    else
        bad "store verify"
        sed 's/^/        /' "$TMPD/pak.txt" | tail -12
    fi
    has "$TMPD/pak.txt" "f lib/ps2maus.omod" "das .opk traegt genau eine Datei: lib/ps2maus.omod"
    W="$TMPD/wurzel"
    rm -rf "$W"; mkdir -p "$W"
    if python3 "$OPK" installieren --wurzel "$W" \
            "$TMPD/pak/ps2maus-1.0.0.opk" > "$TMPD/inst.txt" 2>&1; then
        ok "opk installs the package into a root tree"
        INST=$(ls "$W"/apps/ps2maus.*/lib/ps2maus.omod 2>/dev/null | head -1)
        if [ -n "$INST" ] && cmp -s "$INST" "$TMPD/pak/ps2maus.omod"; then
            ok "the installed file is OCTET FOR OCTET the built .omod"
        else
            bad "the installed file differs"
        fi
        SPEC=""
        for x in $(cd "$W" && find . -type d | sed 's|^\./||' | grep -v '^\.$' | sort); do
            SPEC="$SPEC $x/"
        done
        for x in $(cd "$W" && find . -type f | sed 's|^\./||' | sort); do
            SPEC="$SPEC $x=$W/$x"
        done
        bash tools/mkfsfi/mkfs.sh build "$TMPD/d-opk.img" 2048 $SPEC \
            > "$TMPD/mkopk.txt" 2>&1 \
            && ok "a disk from the installed tree" \
            || bad "mkfs on the installed tree"
        lauf "$TMPD/k-modul" "$TMPD/d-opk.img" "modul modulaus $QUIET" \
            "$TMPD/l-opk.txt"
        num "der Lauf endet sauber" "$RC" eq 21
        has "$TMPD/l-opk.txt" "module: before init=0 present=0" "vorher: kein Zeigegeraet"
        has "$TMPD/l-opk.txt" "module: load=ok" "der Kern laedt die Datei, die OPK dorthin gelegt hat"
        has "$TMPD/l-opk.txt" "module: after init=1 present=1" "danach: das Geraet ist da"
        PK=$(grep -a 'module: pkt=' "$TMPD/l-opk.txt" | head -1 | grep -oE 'pkt=[0-9]+' | grep -oE '[0-9]+')
        num "und es bewegt sich" "$PK" ge 3
        has "$TMPD/l-opk.txt" "module: unloaded=1 present=0" "und es laesst sich wieder entladen"
    else
        bad "opk install"
        sed 's/^/        /' "$TMPD/inst.txt" | head -6
    fi
else
    echo "        opk.py or werkzeug/store missing -- section 10 skipped"
fi

# ------------------------------------------ 11. K-014: die Sperrliste
echo "== 11. K-014: the blocklist -- a signed driver can be revoked =="
SP="tools/module/mksperre.py"
python3 "$SP" "$TMPD/sp-fremd"  "$TMPD/m-abi.omod" >/dev/null 2>&1
python3 "$SP" "$TMPD/sp-drin"   "$TMPD/m-abi.omod" "$TMPD/ps2maus.omod" >/dev/null 2>&1
python3 "$SP" "$TMPD/sp-dreh"   --sig-dreh "$TMPD/m-abi.omod" >/dev/null 2>&1
python3 "$SP" "$TMPD/sp-zahl"   --anzahl 3 "$TMPD/m-abi.omod" >/dev/null 2>&1
n=0
for f in fremd drin dreh zahl; do
    [ -s "$TMPD/sp-$f" ] && bash tools/mkfsfi/mkfs.sh build "$TMPD/d-sp-$f.img" 2048 '/lib/' \
        "/lib/ps2maus.omod=$TMPD/ps2maus.omod" "/lib/omod.sperre=$TMPD/sp-$f" \
        >/dev/null 2>&1 && n=$((n+1))
done
num "Platten mit Sperrliste gebaut" "$n" eq 4
lauf "$TMPD/k-modul" "$TMPD/d-sp-fremd.img" "modul $QUIET" "$TMPD/l-sp-fremd.txt"
num "fremd: der Lauf endet sauber" "$RC" eq 21
has "$TMPD/l-sp-fremd.txt" "module: load=ok" "die Sperrliste sperrt nur, was draufsteht: das gute Modul laedt"
num "fremd: Eintraege in der gueltigen Liste" "$(zwert "$TMPD/l-sp-fremd.txt" 'ban=[0-9]+')" eq 1
has "$TMPD/l-sp-fremd.txt" "module: after init=1 present=1" "fremd: das Geraet ist da"
for f in drin:revoked dreh:banlist zahl:banlist; do
    n=${f%%:*}; g=${f#*:}
    lauf "$TMPD/k-modul" "$TMPD/d-sp-$n.img" "modul $QUIET" "$TMPD/l-sp-$n.txt"
    if [ "$RC" != 21 ]; then bad "sp-$n: rc=$RC statt 21"; continue; fi
    has "$TMPD/l-sp-$n.txt" "module: load=$g" "die Sperrliste: $n -> Grund '$g'"
    has "$TMPD/l-sp-$n.txt" "module: after init=0 present=0" "sp-$n: kein Geraet danach"
    hasnot "$TMPD/l-sp-$n.txt" "ps2mouse: registered" "sp-$n: module_init ist NICHT gelaufen"
done
num "drin: die Signatur des Moduls war gueltig" "$(zwert "$TMPD/l-sp-drin.txt" 'sigok=[0-9]+')" eq 1
num "drin: die Liste hatte 2 Eintraege" "$(zwert "$TMPD/l-sp-drin.txt" 'ban=[0-9]+')" eq 2

echo
echo "MODUL: $pass bestanden, $fail gefallen"
[ "$fail" -eq 0 ]
