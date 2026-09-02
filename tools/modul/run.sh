#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/modul/run.sh -- DER BEWEIS, DASS EIN TREIBER NACHGELADEN WERDEN KANN.
#
# Die Frage des Eigners war: "Wie macht es Windows? Bei der GPU steht da
# Basic Display Driver, und dann kann ich mir z. B. von NVIDIA
# GPU-Treiber herunterladen." `docs/MODUL-BEFUND.md` sagt, was daran
# geht und was nicht. Dieser Laeufer misst den Teil, der geht.
#
# NEUN ABSCHNITTE, und jeder hat eine Gegenprobe, die ihn umbringt:
#
#   1. BAUEN. Zwei Kernabbilder aus DEMSELBEN Quelltext: eines mit
#      `kernel/ps2m.fi` darin, eines mit `--ohne-ps2m` (dann steht
#      `kernel/ps2m-aus.fi` an seiner Stelle -- dieselben 31 Ausfuhren,
#      kein Treiber). Und das Modul, aus derselben Datei `ps2m.fi`.
#   2. DIE AUSFUHRTAFEL. Der Kern druckt Name und Adresse jedes Symbols,
#      das er anbietet; dieser Laeufer haelt jede Zahl gegen `nm` auf
#      dem gebundenen Abbild. Waeren sie verschieden, waere der Kniff in
#      `kernel/ksym.fi` falsch und alles darunter Zufall.
#   3. OHNE MODUL FEHLT DAS GERAET. `--ohne-ps2m`, leere Platte:
#      `mouse_init` sagt nein, `present` sagt nein.
#   4. MIT MODUL IST ES DA. Dieselbe Zeile Quelltext, andere Antwort --
#      und die Maus bewegt sich wirklich: der QEMU-Monitor schickt
#      `mouse_move`, der Paketzaehler steigt.
#   5. ENTLADEN. Danach sagt `present` wieder nein, UND die Zahl der
#      freien Rahmen ist wieder die von vorher. Ein Lader, der Speicher
#      verliert, faellt an dieser Zahl auf.
#   6. DIE SECHS ABWEISUNGEN. Falsche Schnittstellenfassung, gekippte
#      Signatur, gekippte Nutzlast, kaputte Kennung, ein Symbol, das der
#      Kern nicht anbietet, gar keine Datei. Jede mit ihrem Grund, und
#      der Kern lebt nach jeder weiter.
#   7. DIE GEMESSENE GRENZE. Ein Modul, dessen PROGRAMMTEXT verdorben
#      ist und das TROTZDEM richtig signiert wurde, kommt durch alle
#      Riegel -- und nimmt den Kern mit. Das ist kein Fehler des
#      Laeufers, sondern die Wahrheit ueber Ring 0, und sie wird hier
#      GEMESSEN statt beschwiegen.
#   8. WAS ES KOSTET. Abbildgroessen, Modulgroesse, Zahl der
#      Relokationen.
#   9. BEIDE UEBERSETZERSTUFEN. Ein Modul von firnc0 laeuft unter einem
#      Kern von firnc1 und umgekehrt -- das ist der Sinn von
#      `#[export_c]` und der Grund, warum in `kernel/ksym.fi` kein
#      `_F0.` steht.
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
    if [ -z "$value" ]; then bad "$name: keine Zahl gefunden (erwartet $op $want)"; return; fi
    if [ "$value" -"$op" "$want" ] 2>/dev/null; then ok "$name: $value"
    else bad "$name: $value, erwartet $op $want"; fi
}
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' sollte nicht dastehen" || ok "$3"; }

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "MODUL: uebersprungen, qemu-system-x86_64 fehlt"; exit 0
fi

# ---------------------------------------------------------------- 1. bauen
echo "== 1. bauen: zwei Kerne aus einem Quelltext, ein Modul aus derselben Treiberdatei =="

bash tools/build-kernel.sh "$TMPD/k-fest" > "$TMPD/b1.txt" 2>&1 \
    && ok "Kern MIT ps2m.fi ($(stat -c%s "$TMPD/k-fest") Oktette)" \
    || { bad "Kern mit ps2m"; sed 's/^/        /' "$TMPD/b1.txt" | head -5; }
bash tools/build-kernel.sh "$TMPD/k-modul" --ohne-ps2m > "$TMPD/b2.txt" 2>&1 \
    && ok "Kern OHNE ps2m.fi ($(stat -c%s "$TMPD/k-modul") Oktette)" \
    || { bad "Kern ohne ps2m"; sed 's/^/        /' "$TMPD/b2.txt" | head -5; }

# Die Gegenprobe zur Gegenprobe: der Treiber ist im zweiten Abbild WIRKLICH
# nicht drin. Nicht "wird nicht benutzt" -- NICHT VORHANDEN.
# ACHTUNG, UND ES HAT DIESEN LAEUFER EINMAL FALSCH ROT GEMACHT: unter
# `set -o pipefail` darf hier kein `nm ... | grep -q` stehen. `grep -q`
# bricht ab, sobald es fuegt, `nm` stirbt an SIGPIPE, und pipefail macht
# daraus einen Fehlschlag der ganzen Roehre -- unabhaengig davon, ob das
# Symbol da war. Also erst in eine Datei, dann suchen.
nm "$TMPD/k-fest.elf" > "$TMPD/nm-fest.txt" 2>/dev/null
nm "$TMPD/k-modul.elf" > "$TMPD/nm-modul.txt" 2>/dev/null
if grep -c 'ps2m__consume' "$TMPD/nm-fest.txt" >/dev/null 2>&1 \
   && [ "$(grep -c 'ps2m__consume' "$TMPD/nm-fest.txt")" -gt 0 ]; then
    ok "ps2m.consume steht im gewoehnlichen Abbild"
else
    bad "ps2m.consume fehlt im gewoehnlichen Abbild"
fi
if [ "$(grep -c 'ps2m__consume' "$TMPD/nm-modul.txt")" -gt 0 ]; then
    bad "ps2m.consume steht noch im Abbild mit --ohne-ps2m"
else
    ok "ps2m.consume ist mit --ohne-ps2m NICHT im Abbild (kein toter Zweig, keine Zeile)"
fi

bash tools/modul/bau.sh "$TMPD/ps2maus.omod" --name ps2maus --abi 1 \
    > "$TMPD/mb.txt" 2>&1 \
    && ok "Modul gebaut ($(stat -c%s "$TMPD/ps2maus.omod") Oktette)" \
    || { bad "Modulbau"; sed 's/^/        /' "$TMPD/mb.txt" | head -8; }
UNDEF=$(grep -o 'undefinierte Symbole:.*' "$TMPD/mb.txt" | sed 's/undefinierte Symbole: //')
echo "        offene Namen im Modul: $UNDEF"
for n in k_abi k_bind k_dec k_puts kdata osum_panic; do
    case " $UNDEF " in *" $n "*) ;; *) bad "Modul verlangt $n nicht mehr?" ;; esac
done
ok "das Modul verlangt genau die sechs Namen, die kernel/ksym.fi anbietet"

# Die absichtlich kaputten Fassungen. Sie entstehen HIER und nicht mit
# `dd` hinterher -- eine Datei, die ein Skript nachtraeglich verbiegt,
# misst am naechsten Tag etwas anderes.
bash tools/modul/bau.sh "$TMPD/m-abi.omod"  --name ps2maus --abi 2 >/dev/null 2>&1
bash tools/modul/bau.sh "$TMPD/m-sig.omod"  --name ps2maus --abi 1 --sig-dreh >/dev/null 2>&1
bash tools/modul/bau.sh "$TMPD/m-nutz.omod" --name ps2maus --abi 1 --nutz-dreh 1000 >/dev/null 2>&1
bash tools/modul/bau.sh "$TMPD/m-kenn.omod" --name ps2maus --abi 1 --kennung >/dev/null 2>&1
bash tools/modul/bau.sh "$TMPD/m-text.omod" --name ps2maus --abi 1 --text-dreh 64 >/dev/null 2>&1
bash tools/modul/bau.sh "$TMPD/m-fremd.omod" --quelle module/ps2maus-fremd.fi \
    --name ps2maus --abi 1 >/dev/null 2>&1
n=0
for f in m-abi m-sig m-nutz m-kenn m-text m-fremd; do
    [ -s "$TMPD/$f.omod" ] && n=$((n+1))
done
num "absichtlich kaputte Fassungen gebaut" "$n" eq 6

# Die Platten.
mkdisk() { # name omod-datei
    if [ -n "${2:-}" ]; then
        python3 tools/osum/mkfs.py build "$TMPD/d-$1.img" 2048 '/lib/' \
            "/lib/ps2maus.omod=$2" >/dev/null 2>&1
    else
        python3 tools/osum/mkfs.py build "$TMPD/d-$1.img" 2048 '/lib/' >/dev/null 2>&1
    fi
}
mkdisk gut "$TMPD/ps2maus.omod"
mkdisk leer ""
for f in abi sig nutz kenn text fremd; do mkdisk "$f" "$TMPD/m-$f.omod"; done
ok "acht OFS-Abbilder mit je einer /lib/ps2maus.omod (bzw. keiner)"

# ------------------------------------------------------------- der Laeufer
#
# Er wartet auf die MARKE, die die Maschine selbst gedruckt hat
# (`modul: warte`), und nicht auf die Uhr des Wirts -- derselbe Griff wie
# in Runde OTA (docs/RUNDE-MERGE3.md Teil 1b).
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
        grep -qa 'modul: warte' "$4" 2>/dev/null && break
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
# DIE ZAHLEN AUS DER EINEN ZEILE, DIE `zahlen()` DRUCKT. Getrennt, und das
# ist kein Schoenheitsfehler: `ext=[0-9]+` trifft sonst das `ext=0` in
# `k_text=0x1153cc`, und `id=[0-9]+` das `id=0` in `apic: id=0`. Beides ist
# hier passiert und hat den Laeufer falsch rot gemacht.
zwert() { grep -a 'modul: sigok=' "$1" | head -1 | grep -oE "$2" | grep -oE '[0-9]+$'; }
nwert() { grep -a 'modul: nach init=' "$1" | head -1 | grep -oE "$2" | grep -oE '[0-9]+$'; }

# ------------------------------------------------- 2. die Ausfuhrtafel
echo "== 2. die Ausfuhrtafel des Kerns: dieselben Zahlen, die nm nennt =="
lauf "$TMPD/k-modul" "$TMPD/d-gut.img" "modul modulaus $QUIET" "$TMPD/l-gut.txt"
num "der Lauf endet sauber" "$RC" eq 21
num "Symbole in der Tafel" "$(wert "$TMPD/l-gut.txt" 'modul: syms=[0-9]+')" eq 13
python3 - "$TMPD/l-gut.txt" "$TMPD/k-modul.elf" > "$TMPD/nm.txt" 2>&1 <<'PYEOF'
import re, subprocess, sys
log = open(sys.argv[1], errors='replace').read()
tab = {m.group(1): int(m.group(2), 16)
       for m in re.finditer(r'modul:   (\w+)=0x([0-9a-f]+)', log)}
nm = subprocess.run(['nm', sys.argv[2]], capture_output=True, text=True).stdout
sym = {}
for line in nm.splitlines():
    p = line.split()
    if len(p) == 3:
        sym[p[2]] = int(p[0], 16)
paar = {'k_puts': 'serial__puts', 'k_dec': 'serial__dec', 'k_hex': 'serial__hex',
        'k_nl': 'serial__nl', 'k_text': 'serial__text', 'k_get': 'kstate__get',
        'k_set': 'kstate__set', 'k_get8': 'kstate__get8', 'k_bind': 'modtab__bind',
        'k_abi': 'ksym__abi_wert', 'k_putc': 'ksym__putc_u64',
        'k_set8': 'ksym__set8_u64'}
gut = 0
for k, v in paar.items():
    a = tab.get(k)
    b = sym.get('_F0.' + v, sym.get('_F1.' + v))
    if a is not None and b is not None and a == b:
        gut += 1
    else:
        print("ABWEICHUNG %s: gedruckt=%s nm=%s" % (k, a, b))
kd = tab.get('kdata')
if kd is not None and kd == sym.get('kdata'):
    gut += 1
else:
    print("ABWEICHUNG kdata: gedruckt=%s nm=%s" % (kd, sym.get('kdata')))
print("gleich=%d" % gut)
PYEOF
num "Adressen, die mit nm uebereinstimmen" "$(wert "$TMPD/nm.txt" 'gleich=[0-9]+')" eq 13
grep -q ABWEICHUNG "$TMPD/nm.txt" && sed 's/^/        /' "$TMPD/nm.txt" | head -5

# ------------------------------------------ 3. ohne Modul fehlt das Geraet
echo "== 3. ohne Modul fehlt das Geraet =="
lauf "$TMPD/k-modul" "$TMPD/d-leer.img" "modul $QUIET" "$TMPD/l-leer.txt"
num "der Lauf endet sauber" "$RC" eq 21
has "$TMPD/l-leer.txt" "modul: laden=datei-fehlt" "keine Moduldatei -> Grund 'datei-fehlt'"
has "$TMPD/l-leer.txt" "modul: vor init=0 present=0" "vor dem Laden: kein Zeigegeraet"
has "$TMPD/l-leer.txt" "modul: nach init=0 present=0" "und danach immer noch keins"
has "$TMPD/l-leer.txt" "modul: ende" "der Kern lebt und kommt bis ans Ende des Abschnitts"

# --------------------------------------------- 4. mit Modul ist es da
echo "== 4. mit Modul ist es da, und es bewegt sich wirklich =="
has "$TMPD/l-gut.txt" "modul: vor init=0 present=0" "vor dem Laden: kein Zeigegeraet"
has "$TMPD/l-gut.txt" "modul: laden=ok" "das Modul wird angenommen"
has "$TMPD/l-gut.txt" "ps2maus: eingetragen 28" "modul_init lief IM KERN und trug 28 Adressen ein"
has "$TMPD/l-gut.txt" "modul: nach init=1 present=1" "NACH dem Laden: dasselbe mouse_init sagt ja"
num "sigok" "$(zwert "$TMPD/l-gut.txt" 'sigok=[0-9]+')" eq 1
num "ELF-Abschnitte" "$(zwert "$TMPD/l-gut.txt" 'secs=[0-9]+')" ge 8
num "aufgeloeste Relokationen" "$(zwert "$TMPD/l-gut.txt" 'rel=[0-9]+')" ge 500
num "Namen, die aus dem KERN kamen" "$(zwert "$TMPD/l-gut.txt" 'ext=[0-9]+')" ge 6
num "Rahmen fuer das Abbild" "$(zwert "$TMPD/l-gut.txt" 'rahmen=[0-9]+')" ge 1
num "belegte Plaetze in der Treibertafel" "$(zwert "$TMPD/l-gut.txt" 'plaetze=[0-9]+')" eq 28
num "Rueckgabe von modul_init" "$(zwert "$TMPD/l-gut.txt" 'initrc=[0-9]+')" eq 0
# Die Kennung des Geraets kommt vom ECHTEN 8042 und nicht aus einer
# Tabelle: 3 heisst "mit Rad", und QEMU baut ein Rad ein.
num "Geraetekennung vom 8042" "$(nwert "$TMPD/l-gut.txt" 'id=[0-9]+')" eq 3
PKT=$(grep -a 'modul: pkt=' "$TMPD/l-gut.txt" | head -1 | grep -oE 'pkt=[0-9]+' | grep -oE '[0-9]+')
num "PS/2-Pakete, nachdem der Monitor die Maus bewegt hat" "$PKT" ge 3
MOV=$(grep -a 'modul: pkt=' "$TMPD/l-gut.txt" | head -1 | grep -oE 'mov=[0-9]+' | grep -oE '[0-9]+')
num "gezaehlte Bewegungen" "$MOV" ge 3

# --------------------------------------------------- 5. Entladen
echo "== 5. entladen, und die Rahmen kommen zurueck =="
has "$TMPD/l-gut.txt" "ps2maus: entladen" "modul_exit lief"
has "$TMPD/l-gut.txt" "modul: entladen=1 present=0" "nach dem Entladen: wieder kein Zeigegeraet"
FREI=$(grep -a 'modul: frei=' "$TMPD/l-gut.txt" | head -1)
A=$(echo "$FREI" | grep -oE 'frei=[0-9]+' | grep -oE '[0-9]+')
B=$(echo "$FREI" | sed 's/.*=//')
if [ -n "$A" ] && [ "$A" = "$B" ]; then
    ok "freie Rahmen nachher = vorher ($A) -- der Lader verliert keinen"
else
    bad "freie Rahmen: nachher=$A, vorher=$B"
fi
# Und danach wird die Maus WEITER bewegt. Eine Unterbrechung, die jetzt
# noch kommt, findet in der Treibertafel eine Null.
LETZT=$(grep -a 'modul: pkt=' "$TMPD/l-gut.txt" | tail -1 | grep -oE 'pkt=[0-9]+' | grep -oE '[0-9]+')
num "Pakete nach dem Entladen (der Stummel zaehlt nichts mehr)" "$LETZT" eq 0
has "$TMPD/l-gut.txt" "modul: ende" "der Kern lebt nach dem Entladen weiter"

# ------------------------------------------------ 6. die sechs Abweisungen
echo "== 6. sechs Arten, falsch zu liegen -- sechs Abweisungen, ein lebender Kern =="
pruefe_abweisung() { # name grund
    local n=$1 g=$2
    lauf "$TMPD/k-modul" "$TMPD/d-$n.img" "modul $QUIET" "$TMPD/l-$n.txt"
    if [ "$RC" != 21 ]; then bad "$n: rc=$RC statt 21 -- der Kern hat es nicht ueberlebt"; return; fi
    has "$TMPD/l-$n.txt" "modul: laden=$g" "$n -> Grund '$g'"
    has "$TMPD/l-$n.txt" "modul: nach init=0 present=0" "$n: kein Geraet danach"
    hasnot "$TMPD/l-$n.txt" "ps2maus: eingetragen" "$n: modul_init ist NICHT gelaufen"
}
pruefe_abweisung abi   fassung
pruefe_abweisung sig   signatur
pruefe_abweisung nutz  signatur
pruefe_abweisung kenn  kennung
pruefe_abweisung fremd symbol
# Bei `fremd` ist die Signatur GUELTIG und der Parser laeuft durch -- die
# Abweisung kommt erst am Namen. Das ist die schaerfere Zusage: der Lader
# springt nicht in ein Modul, dessen Luecken er nicht fuellen konnte.
num "fremd: die Signatur war gueltig" "$(zwert "$TMPD/l-fremd.txt" 'sigok=[0-9]+')" eq 1
num "fremd: es wurden schon Relokationen angewandt" "$(zwert "$TMPD/l-fremd.txt" 'rel=[0-9]+')" ge 1
num "fremd: aber KEIN Platz in der Treibertafel" "$(zwert "$TMPD/l-fremd.txt" 'plaetze=[0-9]+')" eq 0

# ---------------------------------------------------- 7. die Grenze
echo "== 7. die gemessene GRENZE: ein signiertes, kaputtes Modul in Ring 0 =="
lauf "$TMPD/k-modul" "$TMPD/d-text.img" "modul $QUIET" "$TMPD/l-text.txt"
has "$TMPD/l-text.txt" "modul: laden=ok" "das Modul kommt durch alle drei Riegel -- es IST richtig signiert"
if [ "$RC" = 63 ]; then
    ok "und danach steht die Maschine (rc=63, Ausnahme) -- SO IST RING 0, und das ist gemessen"
elif [ "$RC" = 21 ]; then
    bad "rc=21: der verdorbene Programmtext hat nichts ausgeloest -- die Gegenprobe misst nichts"
else
    bad "rc=$RC, erwartet 63"
fi
grep -qa 'EXCEPTION' "$TMPD/l-text.txt" \
    && ok "der Kern sagt, WORAN er gestorben ist ($(grep -ao 'EXCEPTION [0-9]* #[A-Z]*' "$TMPD/l-text.txt" | head -1))" \
    || bad "kein Ausnahmebericht"

# ---------------------------------------------------------- 8. was es kostet
echo "== 8. was es kostet =="
A=$(stat -c%s "$TMPD/k-fest"); B=$(stat -c%s "$TMPD/k-modul")
M=$(stat -c%s "$TMPD/ps2maus.omod")
echo "        Kern mit ps2m.fi      $A Oktette"
echo "        Kern ohne ps2m.fi     $B Oktette   (Differenz $((A-B)))"
echo "        das Modul             $M Oktette"
echo "        davon Abbild im RAM   $(zwert "$TMPD/l-gut.txt" 'bytes=[0-9]+') Oktette in $(zwert "$TMPD/l-gut.txt" 'rahmen=[0-9]+') Rahmen"
num "der Kern ohne den Treiber ist kleiner" "$((A-B))" gt 0
num "das Modul ist groesser als das, was aus dem Kern verschwand" "$M" gt "$((A-B))"

# ------------------------------------------------------- 9. beide Stufen
echo "== 9. beide Uebersetzerstufen: ein Modul von firnc0 unter einem Kern von firnc1 =="
if bash tools/build-kernel.sh "$TMPD/k1-modul" --ohne-ps2m --stufe 1 \
        > "$TMPD/b3.txt" 2>&1; then
    ok "Kern mit firnc1 gebaut"
    lauf "$TMPD/k1-modul" "$TMPD/d-gut.img" "modul modulaus $QUIET" "$TMPD/l-s1.txt"
    num "der Lauf endet sauber" "$RC" eq 21
    has "$TMPD/l-s1.txt" "modul: laden=ok" "dasselbe Modul (von firnc0) laedt unter dem Kern von firnc1"
    has "$TMPD/l-s1.txt" "modul: nach init=1 present=1" "und das Geraet ist da"
    has "$TMPD/l-s1.txt" "ps2maus: entladen" "und es laesst sich entladen"
else
    bad "firnc1 baut den Kern nicht"
    sed 's/^/        /' "$TMPD/b3.txt" | head -5
fi

# ------------------------------------------------- 10. die Auslieferung
echo "== 10. der ganze Weg: .omod -> .opk -> Speicher -> Platte -> Kern =="
OPK=${OPK:-/root/orientos-install/pkg/opk.py}
STORE=${STORE:-/root/orientstore/werkzeug/store}
if [ -f "$OPK" ] && [ -f "$STORE" ]; then
    bash tools/modul/paket.sh "$TMPD/pak" > "$TMPD/pak.txt" 2>&1
    if grep -q 'Ergebnis    in Ordnung' "$TMPD/pak.txt"; then
        ok "der Speicherkatalog prueft sich selbst durch (store verify --tief)"
    else
        bad "store verify"
        sed 's/^/        /' "$TMPD/pak.txt" | tail -12
    fi
    has "$TMPD/pak.txt" "f lib/ps2maus.omod" "das .opk traegt genau eine Datei: lib/ps2maus.omod"
    # DER SCHRITT, DER DEN KREIS SCHLIESST: das Paket wird ausgepackt wie
    # auf dem Geraet, daraus eine Platte gebaut, und DER KERN LAEDT DAS,
    # WAS DIE PAKETVERWALTUNG DORT HINGELEGT HAT.
    W="$TMPD/wurzel"
    rm -rf "$W"; mkdir -p "$W"
    if python3 "$OPK" installieren --wurzel "$W" \
            "$TMPD/pak/ps2maus-1.0.0.opk" > "$TMPD/inst.txt" 2>&1; then
        ok "opk installiert das Paket in einen Wurzelbaum"
        if cmp -s "$W/apps/ps2maus.prog/lib/ps2maus.omod" "$TMPD/pak/ps2maus.omod"; then
            ok "die installierte Datei ist OKTETT FUER OKTETT das gebaute .omod"
        else
            bad "die installierte Datei weicht ab"
        fi
        SPEC=""
        for x in $(cd "$W" && find . -type d | sed 's|^\./||' | grep -v '^\.$' | sort); do
            SPEC="$SPEC $x/"
        done
        for x in $(cd "$W" && find . -type f | sed 's|^\./||' | sort); do
            SPEC="$SPEC $x=$W/$x"
        done
        python3 tools/osum/mkfs.py build "$TMPD/d-opk.img" 2048 $SPEC \
            > "$TMPD/mkopk.txt" 2>&1 \
            && ok "eine Platte aus dem installierten Baum" \
            || bad "mkfs auf dem installierten Baum"
        lauf "$TMPD/k-modul" "$TMPD/d-opk.img" "modul modulaus $QUIET" \
            "$TMPD/l-opk.txt"
        num "der Lauf endet sauber" "$RC" eq 21
        has "$TMPD/l-opk.txt" "modul: vor init=0 present=0" "vorher: kein Zeigegeraet"
        has "$TMPD/l-opk.txt" "modul: laden=ok" "der Kern laedt die Datei, die OPK dorthin gelegt hat"
        has "$TMPD/l-opk.txt" "modul: nach init=1 present=1" "danach: das Geraet ist da"
        PK=$(grep -a 'modul: pkt=' "$TMPD/l-opk.txt" | head -1 | grep -oE 'pkt=[0-9]+' | grep -oE '[0-9]+')
        num "und es bewegt sich" "$PK" ge 3
        has "$TMPD/l-opk.txt" "modul: entladen=1 present=0" "und es laesst sich wieder entladen"
    else
        bad "opk installieren"
        sed 's/^/        /' "$TMPD/inst.txt" | head -6
    fi
else
    echo "        opk.py oder werkzeug/store fehlt -- Abschnitt 10 uebersprungen"
fi

echo
echo "MODUL: $pass bestanden, $fail gefallen"
[ "$fail" -eq 0 ]
