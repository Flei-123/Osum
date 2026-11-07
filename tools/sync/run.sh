#!/usr/bin/env bash
#
# Verwendung:  bash tools/sync/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

FIRNC=${FIRNC:-vendor/firn/bin/firnc}
BLOCKS=6144
PROGS="sh ls cat echo mkdir rm cp sync vault backup key bsect sleep"

TMPD=$(mktemp -d)
SYNC_SHA0=$(sha256sum kernel/user/sync.fi | cut -d' ' -f1)
aufraeumen() {
    rm -rf "$TMPD"
}
trap aufraeumen EXIT INT TERM

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }
is()  { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', erwartet '$3'"; fi; }
hat() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
nicht() { grep -qaF "$2" "$1" && bad "$3 -- '$2' steht da und sollte nicht" || ok "$3"; }
feld() { tr -cd '\11\12\15\40-\176' < "$1" | grep -a "^$2: " | tail -1 | sed "s/^$2: //"; }
feld_n() { tr -cd '\11\12\15\40-\176' < "$1" | grep -a "^$2: " | sed -n "$3p" | sed "s/^$2: //"; }

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "fetch-firnc.sh fehlgeschlagen"; exit 1; }
[ -x "$FIRNC" ] || { echo "firnc0 fehlt: $FIRNC"; exit 1; }
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "SYNC: uebersprungen, qemu fehlt"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SYNC: uebersprungen, python3 fehlt"; exit 0; }

# =====================================================================
echo "== 1. bauen =="
# =====================================================================
mkdir -p .probe
if $FIRNC tools/sync/oracle.fi -o .probe/syncoracle 2>"$TMPD/e"; then
    ok "tools/sync/oracle.fi builds against lib/crypto/ and lib/sync/"
else
    bad "the oracle does not build"; head -12 "$TMPD/e" | sed 's/^/        /'
fi

bash tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/b0.txt" 2>&1 \
    && ok "firnc0 baut den Kern" \
    || { bad "firnc0 does not build the kernel"; sed 's/^/        /' "$TMPD/b0.txt" | head -12; }
[ -f "$TMPD/k0.img" ] || { echo "SYNC: $pass passed, $((fail+1)) failed"; exit 1; }

bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/bprog.txt" 2>&1 \
    && ok "firnc0 baut $(echo $PROGS | wc -w) Programme in Ring 3" \
    || { bad "firnc0 does not build all programs"
         sed 's/^/        /' "$TMPD/bprog.txt" | head -14; }
[ -f "$TMPD/bin/sync.elf" ] || { echo "SYNC: $pass passed, $((fail+1)) failed"; exit 1; }

undef=""
for p in sync vault; do
    u=$(nm -u "$TMPD/bin/$p.elf" 2>/dev/null | awk '{print $NF}' | sed '/^$/d')
    [ -n "$u" ] && undef="$undef $p:$u"
done
[ -z "$undef" ] && ok "neither /bin/sync nor /bin/vault has an undefined name" \
               || bad "undefinierte Namen:$undef"
note "/bin/sync: $(stat -c%s "$TMPD/bin/sync.elf") Oktette, /bin/vault: $(stat -c%s "$TMPD/bin/vault.elf") Oktette"

if bash tools/sync/build.sh "$TMPD/bin1" 1 sync vault > "$TMPD/b1.txt" 2>&1; then
    ok "firnc1 baut sync und vault ebenfalls"
else
    note "firnc1 hat nicht gebaut -- gemessen wird mit firnc0"
    sed 's/^/        /' "$TMPD/b1.txt" | head -6
fi

# =====================================================================
echo "== 2. the building blocks against their standards (on the host) =="
# =====================================================================
if python3 tools/sync/vectors.py > "$TMPD/vec.txt" 2>&1; then
    grep -E '^  ' "$TMPD/vec.txt" | sed 's/^/     /'
    ok "$(tail -1 "$TMPD/vec.txt")"
else
    bad "the test vectors failed"
    tail -25 "$TMPD/vec.txt" | sed 's/^/        /'
fi

spec_von() {
    local hd=$1 pre=$2
    [ -d "$hd" ] || return 0
    ( cd "$hd" && find . -type d | sed 's|^\./\{0,1\}||' | while read -r d; do
        [ -z "$d" ] && echo "$pre/" || echo "$pre/$d/"
      done
      find . -type f | sed 's|^\./||' | while read -r f; do
        echo "$pre/$f=$hd/$f"
      done )
}

# hol <abbild> <praefix> <zielverzeichnis>
hol() {
    local img=$1 pre=$2 ziel=$3
    rm -rf "$ziel"; mkdir -p "$ziel"
    bash tools/mkfsfi/mkfs.sh list "$img" 2>/dev/null | awk '{print $1}' \
    | grep "^$pre/" | while read -r p; do
        local rel=${p#"$pre/"}
        if [ "${p%/}" != "$p" ]; then
            mkdir -p "$ziel/${rel%/}"
        else
            mkdir -p "$ziel/$(dirname "$rel")"
            bash tools/mkfsfi/mkfs.sh cat "$img" "$p" > "$ziel/$rel" 2>/dev/null
        fi
    done
}

# geraet <abbild> <skriptdatei> <kontoverz|-> <storeverz|-> <datenverz|-> <tresorverz|->
geraet() {
    local img=$1 skript=$2 kd=$3 sd=$4 dd=$5 td=$6
    local spec=""
    [ "$kd" != "-" ] && spec="$spec $(spec_von "$kd" /konto)"
    [ "$sd" != "-" ] && spec="$spec $(spec_von "$sd" /store)"
    [ "$dd" != "-" ] && spec="$spec $(spec_von "$dd" /daten)"
    [ "$td" != "-" ] && spec="$spec $(spec_von "$td" /tresor)"
    bash tools/mkfsfi/mkfs.sh build "$img" $BLOCKS \
        /bin/ /t/ /proc/ /dev/ /konto/ /store/ /daten/ /tresor/ /system/ \
        $(for p in $PROGS; do echo "/bin/$p=$TMPD/bin/$p.elf"; done) \
        /t/s.sh="$skript" \
        $spec > "$TMPD/mkfs.txt" 2>&1
}

lauf() { # <abbild> <name>  -> Beendigungscode
    bash tools/sync/lauf.sh "$TMPD/k0.img" "$1" "$TMPD/$2.txt" /t/s.sh
}

klar() { tr -cd '\11\12\15\40-\176' < "$TMPD/$1.txt" | grep -v '^elf:'; }

# =====================================================================
echo "== 3. (a) two systems, one account =="
# =====================================================================
PASS=geheimeslosungswort
NP=256   # scrypt N fuer den Testlauf -- die Begruendung steht in kbund.fi B2
RP=8

mkdir -p "$TMPD/daten/unter"
printf 'die erste zeile\nGEHEIMNIS-4711 steht hier\n' > "$TMPD/daten/a.txt"
head -c 9000 /dev/urandom > "$TMPD/daten/unter/b.bin"
printf 'hallo\n' > "$TMPD/daten/klein.txt"
printf '100 farbe blau\n100 sprache de\n' > "$TMPD/daten/EINST"
head -c 200000 /dev/urandom > "$TMPD/daten/gross.bin"
mkdir -p "$TMPD/fremd"
printf 'diese datei hat er nicht\n' > "$TMPD/fremd/x.txt"

cat > "$TMPD/sA.sh" <<EOS
echo ==NEU==
sync new /konto $PASS own /store $NP $RP
echo ==AB==
sync merge /konto /daten $PASS
echo ==END==
EOS
geraet "$TMPD/A.img" "$TMPD/sA.sh" - - "$TMPD/daten" - \
    && ok "mkfs.py baut Geraet A" || bad "mkfs.py fehlgeschlagen"
rc=$(lauf "$TMPD/A.img" A)
is "Geraet A endet ordentlich" "$rc" "21"
klar A > "$TMPD/A.log"
hat "$TMPD/A.log" "recovery code: " "A zeigt den Wiederherstellungscode"
hat "$TMPD/A.log" "WARNING: without the passphrase AND without the recovery code" \
    "und die Warnung steht VOR dem Anlegen"
CODE=$(grep -a '^recovery code: ' "$TMPD/A.log" | tail -1 | sed 's/^recovery code: //')
note "Code: $CODE"
is "der Code hat 65 Zeichen" "${#CODE}" "65"
is "A meldet fertig" "$(klar A | grep -c '^done')" "1"
A_DAT=$(feld "$TMPD/A.txt" files)
A_BLK=$(feld "$TMPD/A.txt" blocks)
A_NEU=$(feld "$TMPD/A.txt" newblocks)
A_GEN=$(feld "$TMPD/A.txt" generation)
is "A sieht 5 Dateien" "$A_DAT" "5"
is "A legt alle Bloecke neu ab" "$A_NEU" "$A_BLK"
is "A schreibt Generation 1" "$A_GEN" "1"

hol "$TMPD/A.img" /store "$TMPD/store1"
hol "$TMPD/A.img" /konto "$TMPD/kontoA"
[ -f "$TMPD/store1/PACK" ] && ok "the store has PACK, INDEX and ROOT" \
                           || bad "the store is incomplete"
note "Speicher: PACK $(stat -c%s "$TMPD/store1/PACK" 2>/dev/null) Oktette, INDEX $(stat -c%s "$TMPD/store1/INDEX" 2>/dev/null), ROOT $(stat -c%s "$TMPD/store1/ROOT" 2>/dev/null)"

mkdir -p "$TMPD/kontoB"
cp "$TMPD/kontoA/KOPF" "$TMPD/kontoB/KOPF"
mkdir -p "$TMPD/leer"
cat > "$TMPD/sB.sh" <<EOS
echo ==AB==
sync merge /konto /daten $PASS
echo ==LS==
ls /daten
echo ==END==
EOS
geraet "$TMPD/B.img" "$TMPD/sB.sh" "$TMPD/kontoB" "$TMPD/store1" "$TMPD/leer" - \
    && ok "mkfs.py builds device B (only HEAD and store, no COUNTER)" \
    || bad "mkfs.py fehlgeschlagen"
rc=$(lauf "$TMPD/B.img" B)
is "Geraet B endet ordentlich" "$rc" "21"
klar B > "$TMPD/B.log"
B_RUNTER=$(feld "$TMPD/B.txt" downloaded)
B_EINST=$(feld "$TMPD/B.txt" settings)
is "B holt 4 Dokumente herunter" "$B_RUNTER" "4"
[ -n "$B_EINST" ] && [ "$B_EINST" -gt 0 ] \
    && ok "and SETTINGS arrive through the settings path: $B_EINST keys merged" \
    || bad "B merged no setting: '$B_EINST'"
is "B meldet fertig" "$(klar B | grep -c '^done')" "1"

hol "$TMPD/B.img" /daten "$TMPD/datenB"
gleich=0
ungleich=""
for f in a.txt klein.txt EINST unter/b.bin gross.bin; do
    if [ -f "$TMPD/datenB/$f" ] && cmp -s "$TMPD/daten/$f" "$TMPD/datenB/$f"; then
        gleich=$((gleich+1))
    else
        ungleich="$ungleich $f"
    fi
done
is "(a) alle fuenf Dateien sind auf B Oktett fuer Oktett dieselben" "$gleich" "5"
note "darunter gross.bin mit 200000 Oktetten -- 49 Bloecke, deren Namen als eigene Kette (K-Form) abgelegt sind"
[ -n "$ungleich" ] && note "ungleich:$ungleich"
note "verglichen wurde aus dem Plattenabbild, nicht aus der seriellen Leitung"

# =====================================================================
echo "== 4./5. (b) the server sees nothing, (c) the recognition attack =="
# =====================================================================
cp "$TMPD/kontoA/KOPF" "$TMPD/store1/KOPF"   # der Angreifer darf den Kopf haben
if python3 tools/sync/schnueffel.py "$TMPD/store1" "$TMPD/daten" "$PASS" \
    "$NP" "$RP" --habe "$TMPD/daten/a.txt" "$TMPD/daten/klein.txt" \
    "$TMPD/daten/unter/b.bin" "$TMPD/daten/gross.bin" \
    --habe-nicht "$TMPD/fremd/x.txt" \
    > "$TMPD/schn.txt" 2>&1; then
    sed 's/^/     /' "$TMPD/schn.txt"
    ok "$(tail -1 "$TMPD/schn.txt")"
else
    sed 's/^/     /' "$TMPD/schn.txt"
    bad "the snooper found something"
fi
rm -f "$TMPD/store1/KOPF"

# =====================================================================
echo "== 6. (d) wrong passphrase, and the way back =="
# =====================================================================
cat > "$TMPD/sD.sh" <<EOS
echo ==FALSCH==
sync merge /konto /daten diesistfalsch
echo ==FASTRICHTIG==
sync open /konto ${PASS}x
echo ==CODE==
sync code /konto $CODE
echo ==CODEFALSCH==
sync code /konto 00000-00000-00000-00000-00000-00000-00000-00000-00000-00000-00000
echo ==RICHTIG==
sync open /konto $PASS
echo ==END==
EOS
geraet "$TMPD/D.img" "$TMPD/sD.sh" "$TMPD/kontoB" "$TMPD/store1" "$TMPD/leer" -
rc=$(lauf "$TMPD/D.img" D)
is "der Passphrasenlauf endet ordentlich" "$rc" "21"
klar D > "$TMPD/D.log"
absch() { sed -n "/^==$1==/,/^==/p" "$TMPD/D.log"; }
absch FALSCH | grep -qa 'wrong passphrase' \
    && ok "(d) a wrong passphrase is rejected" \
    || bad "(d) a wrong passphrase is NOT rejected"
absch FALSCH | grep -qa 'done' \
    && bad "(d) der Abgleich lief trotzdem" \
    || ok "(d) and NOTHING is synchronised"
absch FASTRICHTIG | grep -qa 'wrong passphrase' \
    && ok "(d) a single wrong character is enough" \
    || bad "(d) an almost correct passphrase got through"
absch CODE | grep -qa 'account: open' \
    && ok "(d) the recovery code restores access" \
    || bad "(d) the recovery code has no effect"
absch CODEFALSCH | grep -qa 'not valid' \
    && ok "(d) an invented code is rejected" \
    || bad "(d) an invented code got through"
absch RICHTIG | grep -qa 'account: open' \
    && ok "(d) and the correct passphrase still works" \
    || bad "(d) the correct passphrase no longer works"
nicht "$TMPD/D.log" "GEHEIMNIS-4711" "(d) kein Teilklartext im ganzen Lauf"

# =====================================================================
echo "== 7. (e) ein boesartiger Server =="
# =====================================================================
cat > "$TMPD/sE.sh" <<EOS
echo ==AB==
sync merge /konto /daten $PASS
echo ==LS==
ls /daten
echo ==END==
EOS
boese_lauf() { # <was> <erwarteter text> <name> [extra]
    local was=$1 erw=$2 nm=$3 extra=${4:-}
    rm -rf "$TMPD/sb-$nm"; cp -r "$TMPD/store1" "$TMPD/sb-$nm"
    python3 tools/sync/boese.py "$was" "$TMPD/sb-$nm" $extra > "$TMPD/boese-$nm.txt" 2>&1
    note "$was: $(cat "$TMPD/boese-$nm.txt")"
    geraet "$TMPD/E-$nm.img" "$TMPD/sE.sh" "$TMPD/kontoB" "$TMPD/sb-$nm" "$TMPD/leer" -
    lauf "$TMPD/E-$nm.img" "E-$nm" > /dev/null
    klar "E-$nm" > "$TMPD/E-$nm.log"
    if grep -qa "$erw" "$TMPD/E-$nm.log"; then
        ok "(e) $was is detected and rejected"
    else
        bad "(e) $was is NOT detected"
        grep -a 'sync:\|error\|done' "$TMPD/E-$nm.log" | head -4 | sed 's/^/        /'
    fi
}
boese_lauf aendern      "sync: error" aendern
boese_lauf fremd        "sync: error" fremd
boese_lauf gross        "sync: error" gross
boese_lauf wurzelluege  "forged"  luege
boese_lauf halbe        "forged"  halbe

rm -rf "$TMPD/kontoR"; cp -r "$TMPD/kontoA" "$TMPD/kontoR"
printf '9\n' > "$TMPD/kontoR/COUNTER"
rm -rf "$TMPD/sb-rueck"; cp -r "$TMPD/store1" "$TMPD/sb-rueck"
geraet "$TMPD/E-rueck.img" "$TMPD/sE.sh" "$TMPD/kontoR" "$TMPD/sb-rueck" "$TMPD/leer" -
lauf "$TMPD/E-rueck.img" E-rueck > /dev/null
klar E-rueck > "$TMPD/E-rueck.log"
if grep -qa 'ROLLBACK' "$TMPD/E-rueck.log"; then
    ok "(e) THE ROLLBACK is detected (counter 9, store offers 1)"
else
    bad "(e) THE ROLLBACK is NOT detected -- a server can slip in old data"
    grep -a 'sync:\|error\|done\|generation' "$TMPD/E-rueck.log" | head -4 | sed 's/^/        /'
fi
rm -rf "$TMPD/kontoR2"; cp -r "$TMPD/kontoA" "$TMPD/kontoR2"
printf '1\n' > "$TMPD/kontoR2/ZAEHLER"
geraet "$TMPD/E-ok.img" "$TMPD/sE.sh" "$TMPD/kontoR2" "$TMPD/store1" "$TMPD/leer" -
lauf "$TMPD/E-ok.img" E-ok > /dev/null
klar E-ok > "$TMPD/E-ok.log"
grep -qa 'done' "$TMPD/E-ok.log" \
    && ok "(e) CONTROL: with a matching counter the same store passes" \
    || bad "(e) CONTROL: even the intact store is rejected"

# =====================================================================
echo "== 8. (f) Abbruch mitten im Abgleich, 30 mal =="
# =====================================================================
mkdir -p "$TMPD/gross"
i=0
while [ $i -lt 12 ]; do
    head -c 12000 /dev/urandom > "$TMPD/gross/d$i.bin"
    i=$((i+1))
done
#
cat > "$TMPD/sF.sh" <<EOS
sync new /konto $PASS own /store $NP $RP
sync merge /konto /daten $PASS
echo ==ERSTER-DURCH==
cp /daten/d0.bin /daten/n0.bin
cp /daten/d1.bin /daten/n1.bin
cp /daten/d2.bin /daten/n2.bin
cp /daten/d3.bin /daten/n3.bin
cp /daten/d4.bin /daten/n4.bin
cp /daten/d5.bin /daten/n5.bin
sync merge /konto /daten $PASS
echo ==END==
EOS
geraet "$TMPD/F0.img" "$TMPD/sF.sh" - - "$TMPD/gross" -

cp "$TMPD/F0.img" "$TMPD/Fv.img"
tv0=$(date +%s%N)
SYNC_TIMEOUT=900 lauf "$TMPD/Fv.img" Fv > /dev/null
tv1=$(date +%s%N)
F_VOLL=$(( (tv1 - tv0) / 1000000 ))
klar Fv > "$TMPD/Fv.log"
grep -qa '^==END==' "$TMPD/Fv.log" \
    && ok "(f) the undisturbed reference run passes: $F_VOLL ms" \
    || bad "(f) even the undisturbed run does not pass"
[ "$F_VOLL" -lt 1500 ] && F_VOLL=1500
rm -f "$TMPD/Fv.img"

root_whole() {
    [ -f "$1" ] && grep -qaE '^osumwurzel1 [0-9]+ [0-9a-f]{64} [0-9a-f]{64}$' "$1"
}

kills=0
gefunden=0
konten=0
halbe=0
letztes=""
n=0
while [ $n -lt 30 ]; do
    cp "$TMPD/F0.img" "$TMPD/F-$n.img"
    : > "$TMPD/F.txt"
    qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" \
        -kernel "$TMPD/k0.img" -m 512 \
        -append "osum vfs nokbd script=sh /t/s.sh;exit" \
        -serial "file:$TMPD/F.txt" -display none -no-reboot \
        -drive "file=$TMPD/F-$n.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    qp=$!
    ms=$(( (F_VOLL * 50 / 100) + (RANDOM % (F_VOLL * 49 / 100)) ))
    sleep "$(awk "BEGIN{print $ms/1000}")"
    if kill -0 "$qp" 2>/dev/null; then
        kill -9 "$qp" 2>/dev/null
        kills=$((kills+1))
    fi
    wait "$qp" 2>/dev/null
    hol "$TMPD/F-$n.img" /store "$TMPD/fs-$n" 2>/dev/null
    hol "$TMPD/F-$n.img" /konto "$TMPD/fk-$n" 2>/dev/null
    if [ -f "$TMPD/fk-$n/KOPF" ]; then
        konten=$((konten+1))
        letztes=$n
        rm -f "$TMPD/Flast.img"
        mv "$TMPD/F-$n.img" "$TMPD/Flast.img"
    fi
    rm -f "$TMPD/F-$n.img"
    rm -rf "$TMPD/fk-$n"
    if [ -f "$TMPD/fs-$n/ROOT" ]; then
        gefunden=$((gefunden+1))
        if ! root_whole "$TMPD/fs-$n/ROOT" && ! root_whole "$TMPD/fs-$n/ROOT.T"; then
            halbe=$((halbe+1))
            note "Lauf $n: ROOT is not whole and ROOT.T is no fallback: $(head -c 120 "$TMPD/fs-$n/ROOT" | tr -d '\n') | $(head -c 120 "$TMPD/fs-$n/ROOT.T" 2>/dev/null | tr -d '\n')"
        fi
    fi
    n=$((n+1))
done
note "$kills von 30 Laeufen wurden wirklich mit SIGKILL abgebrochen"
note "Abbruchfenster: 50-99 % von $F_VOLL ms"
is "(f) 30 Abbrueche gefahren" "$n" "30"
num_ge=$gefunden
note "$num_ge davon hatten schon eine Wurzel auf der Platte, $konten ein Konto"
[ "$num_ge" -ge 1 ] \
    && ok "(f) $num_ge aborts came AFTER writing the root" \
    || bad "(f) no single abort hit the root -- (f) measures the wrong spot"
is "(f) a ROOT that is not whole always has a whole ROOT.T next to it, in all 30 cases" "$halbe" "0"
[ "$kills" -ge 15 ] \
    && ok "(f) the aborts really hit the middle: $kills von 30" \
    || bad "(f) only $kills of 30 runs were still running at all -- the window does not fit"
[ "$konten" -ge 1 ] \
    && ok "(f) at least one aborted run already had an account: $konten" \
    || bad "(f) no single abort reached the account"
if [ -n "$letztes" ]; then
    cp "$TMPD/Flast.img" "$TMPD/F.img"
    note "weitergefahren wird Lauf $letztes"
fi

cat > "$TMPD/sF2.sh" <<EOS
echo ==AB==
sync merge /konto /daten $PASS
echo ==END==
EOS
hol "$TMPD/F.img" /konto "$TMPD/kontoF"
hol "$TMPD/F.img" /store "$TMPD/storeF"
if [ -f "$TMPD/kontoF/KOPF" ]; then
    geraet "$TMPD/F2.img" "$TMPD/sF2.sh" "$TMPD/kontoF" "$TMPD/storeF" "$TMPD/gross" -
    rc=$(lauf "$TMPD/F2.img" F2)
    klar F2 > "$TMPD/F2.log"
    grep -qa 'done' "$TMPD/F2.log" \
        && ok "(f) after the abort the sync resumes and finishes" \
        || bad "(f) after the abort the sync no longer completes"
    hol "$TMPD/F2.img" /store "$TMPD/storeF2"
    mkdir -p "$TMPD/kontoF2"; cp "$TMPD/kontoF/KOPF" "$TMPD/kontoF2/KOPF"
    geraet "$TMPD/F3.img" "$TMPD/sB.sh" "$TMPD/kontoF2" "$TMPD/storeF2" "$TMPD/leer" -
    lauf "$TMPD/F3.img" F3 > /dev/null
    hol "$TMPD/F3.img" /daten "$TMPD/datenF3"
    g=0
    i=0
    while [ $i -lt 12 ]; do
        cmp -s "$TMPD/gross/d$i.bin" "$TMPD/datenF3/d$i.bin" && g=$((g+1))
        i=$((i+1))
    done
    is "(f) und alle 12 Dateien kommen danach heil beim naechsten Geraet an" "$g" "12"
    if [ "$g" != 12 ]; then
        klar F3 | grep -a 'sync\|fehler\|done\|downloaded\|files\|^d[0-9]' \
            | head -12 | sed 's/^/        F3: /'
        note "F3 /daten: $(ls "$TMPD/datenF3" 2>/dev/null | tr '\n' ' ')"
        note "F2: $(klar F2 | grep -a 'files\|uploaded\|newblocks\|generation' | tr '\n' ' ')"
        note "storeF2: $(ls -l "$TMPD/storeF2" 2>/dev/null | tr '\n' ';')"
        note "storeF ROOT: $(head -c 140 "$TMPD/storeF/ROOT" 2>/dev/null | tr '\n' ' ') | ROOT.T: $(head -c 140 "$TMPD/storeF/ROOT.T" 2>/dev/null | tr '\n' ' ')"
        note "storeF2 ROOT: $(head -c 140 "$TMPD/storeF2/ROOT" 2>/dev/null | tr '\n' ' ') | ROOT.T: $(head -c 140 "$TMPD/storeF2/ROOT.T" 2>/dev/null | tr '\n' ' ')"
    fi
    hin=0; kaputt=0
    i=0
    while [ $i -lt 6 ]; do
        if [ -f "$TMPD/datenF3/n$i.bin" ]; then
            if cmp -s "$TMPD/gross/d$i.bin" "$TMPD/datenF3/n$i.bin"; then
                hin=$((hin+1))
            else
                kaputt=$((kaputt+1))
            fi
        fi
        i=$((i+1))
    done
    note "vom abgebrochenen zweiten Abgleich kamen $hin von 6 Kopien ganz an"
    is "(f) und KEINE davon kam halb an" "$kaputt" "0"
    mkdir -p "$TMPD/storeP"
    head -c $((4112 * 3)) "$TMPD/storeF2/PACK" > "$TMPD/storeP/PACK"
    geraet "$TMPD/P2.img" "$TMPD/sF2.sh" "$TMPD/kontoF" "$TMPD/storeP" "$TMPD/gross" -
    lauf "$TMPD/P2.img" P2 > /dev/null
    hol "$TMPD/P2.img" /store "$TMPD/storeP2"
    mkdir -p "$TMPD/kontoP2"; cp "$TMPD/kontoF/KOPF" "$TMPD/kontoP2/KOPF"
    geraet "$TMPD/P3.img" "$TMPD/sB.sh" "$TMPD/kontoP2" "$TMPD/storeP2" "$TMPD/leer" -
    lauf "$TMPD/P3.img" P3 > /dev/null
    hol "$TMPD/P3.img" /daten "$TMPD/datenP3"
    g=0
    i=0
    while [ $i -lt 12 ]; do
        cmp -s "$TMPD/gross/d$i.bin" "$TMPD/datenP3/d$i.bin" && g=$((g+1))
        i=$((i+1))
    done
    is "(f) a PACK without INDEX (abort before the first index write): all 12 files arrive intact" "$g" "12"
else
    bad "(f) after the aborts there is no account any more"
fi

# =====================================================================
echo "== 8b. der eigene Datentraeger laeuft voll =="
mkdir -p "$TMPD/vollmess"
i=0
while [ $i -lt 20 ]; do
    head -c 51200 /dev/urandom > "$TMPD/vollmess/v$i.bin"
    i=$((i+1))
done
cat > "$TMPD/sV.sh" <<EOS
echo ==AB==
sync new /konto $PASS own /store $NP $RP
sync merge /konto /daten $PASS
echo ==END==
EOS
BLOCKS_ALT=$BLOCKS
BLOCKS=4400   # 1 MiB Daten, aber nur rund 600 KiB frei
geraet "$TMPD/V.img" "$TMPD/sV.sh" - - "$TMPD/vollmess" -
BLOCKS=$BLOCKS_ALT
SYNC_TIMEOUT=900 lauf "$TMPD/V.img" V > /dev/null
klar V > "$TMPD/V.log"
grep -qa '^done' "$TMPD/V.log" \
    && bad "der volle Datentraeger meldet trotzdem fertig" \
    || ok "a full disk does NOT report done"
grep -qa '^sync: error' "$TMPD/V.log" \
    && ok "but an error: $(grep -a '^sync: error' "$TMPD/V.log" | tail -1)" \
    || bad "and it reports no error either -- the abort is silent"
grep -qa '^sync: at:' "$TMPD/V.log" \
    && ok "and it names the file where it broke: $(grep -a '^sync: at:' "$TMPD/V.log" | tail -1 | sed 's/^sync: at:  *//')" \
    || bad "but not WHERE it broke"
is "und er schreibt KEINE Wurzel (Generation bleibt 0)" \
   "$(feld "$TMPD/V.txt" generation)" "0"
hol "$TMPD/V.img" /store "$TMPD/storeV"
[ -f "$TMPD/storeV/ROOT" ] \
    && bad "there is still a root in the store" \
    || ok "there is no root in the store, only octets nobody points to"

# =====================================================================
echo "== 9. (g) the conflict =="
cat > "$TMPD/sG1.sh" <<EOS
echo ==AB1==
sync merge /konto /daten $PASS
echo ==AENDERN==
echo VON-B > /daten/a.txt
echo ==AB2==
sync merge /konto /daten $PASS
echo ==END==
EOS
geraet "$TMPD/G1.img" "$TMPD/sG1.sh" "$TMPD/kontoB" "$TMPD/store1" "$TMPD/leer" -
lauf "$TMPD/G1.img" G1 > /dev/null
klar G1 > "$TMPD/G1.log"
hol "$TMPD/G1.img" /store "$TMPD/store2"
grep -qa 'done' "$TMPD/G1.log" && ok "(g) B changes a.txt and uploads" \
                                 || bad "(g) B does not get through"

cat > "$TMPD/sG2.sh" <<EOS
echo ==AENDERN==
echo VON-A > /daten/a.txt
echo ==AB==
sync merge /konto /daten $PASS
echo ==LS==
ls /daten
echo ==KONF==
sync conflicts /konto
echo ==A==
cat /daten/a.txt
echo ==K==
cat /daten/a.txt.konflikt
echo ==END==
EOS
geraet "$TMPD/G2.img" "$TMPD/sG2.sh" "$TMPD/kontoA" "$TMPD/store2" "$TMPD/daten" -
lauf "$TMPD/G2.img" G2 > /dev/null
klar G2 > "$TMPD/G2.log"
G_KONF=$(feld "$TMPD/G2.txt" conflicts)
is "(g) A meldet genau einen Konflikt" "$G_KONF" "1"
hol "$TMPD/G2.img" /daten "$TMPD/datenG"
[ -f "$TMPD/datenG/a.txt.konflikt" ] \
    && ok "(g) the foreign version lies next to it as a.txt.konflikt" \
    || bad "(g) there is no second version -- something was silently lost"
if [ -f "$TMPD/datenG/a.txt" ] && [ -f "$TMPD/datenG/a.txt.konflikt" ]; then
    x=$(cat "$TMPD/datenG/a.txt"); y=$(cat "$TMPD/datenG/a.txt.konflikt")
    is "(g) die eigene Fassung ist geblieben" "$x" "VON-A"
    is "(g) und die fremde ist auch da" "$y" "VON-B"
fi
sed -n '/^==KONF==/,/^==A==/p' "$TMPD/G2.log" | grep -qa '/a.txt' \
    && ok "(g) sync konflikte names the path" \
    || bad "(g) sync konflikte names the path nicht"

# =====================================================================
echo "== 10. (h) the vault =="
# =====================================================================
cat > "$TMPD/sH.sh" <<EOS
echo ==OHNE==
vault get /tresor bank
echo ==AUF==
vault open /konto /tresor $PASS 300
echo ==LEGEN==
vault put /tresor bank GEHEIMNIS-4711
echo ==LISTE==
vault list /tresor
echo ==GIB==
vault get /tresor bank
echo ==ZU==
vault close /tresor
echo ==NACHZU==
vault get /tresor bank
echo ==FALSCHPASS==
vault open /konto /tresor falschespass 300
echo ==KURZ==
vault open /konto /tresor $PASS 1
echo ==WARTEN==
sleep 3
echo ==NACHFRIST==
vault get /tresor bank
echo ==END==
EOS
geraet "$TMPD/H.img" "$TMPD/sH.sh" "$TMPD/kontoA" "$TMPD/store1" "$TMPD/leer" -
rc=$(lauf "$TMPD/H.img" H)
klar H > "$TMPD/H.log"
habs() { sed -n "/^==$1==/,/^==/p" "$TMPD/H.log"; }
habs OHNE | grep -qa 'no open session' \
    && ok "(h) without a session there is no secret" \
    || bad "(h) without a session something came out"
habs AUF | grep -qa 'vault: open' && ok "(h) the vault opens with the passphrase" \
                                  || bad "(h) the vault does not open"
habs LEGEN | grep -qa 'vault: stored' && ok "(h) a secret can be stored" \
                               || bad "(h) das Ablegen scheitert"
habs GIB | grep -qa 'GEHEIMNIS-4711' \
    && ok "(h) and retrieved again with an open session" \
    || bad "(h) the secret does not come back"
habs NACHZU | grep -qa 'no open session' \
    && ok "(h) nach 'vault close' ist er zu" \
    || bad "(h) nach 'vault close' ist er NICHT zu"
habs FALSCHPASS | grep -qa 'wrong passphrase' \
    && ok "(h) a wrong passphrase does not open the vault" \
    || bad "(h) a wrong passphrase opened the vault"
habs NACHFRIST | grep -qa 'timeout has expired' \
    && ok "(h) after the timeout the vault closes by itself" \
    || bad "(h) the timeout has no effect"
hol "$TMPD/H.img" /tresor "$TMPD/tresorH"
found=0
for f in "$TMPD/tresorH"/*; do
    [ -f "$f" ] && grep -qaF "GEHEIMNIS-4711" "$f" && found=$((found+1))
done
is "(h) der Klartext steht in KEINER Datei des Tresors" "$found" "0"
[ -f "$TMPD/tresorH/G-bank" ] && ok "(h) the secret lies there as G-bank (sealed)" \
                             || bad "(h) G-bank fehlt"

hol "$TMPD/H.img" /tresor "$TMPD/tresorH2"
cat > "$TMPD/sH2.sh" <<'EOS'
echo ==OHNERECHT==
vault get /tresor bank
echo ==END==
EOS
geraet "$TMPD/H2.img" "$TMPD/sH2.sh" "$TMPD/kontoA" "$TMPD/store1" "$TMPD/leer" "$TMPD/tresorH2"
lauf "$TMPD/H2.img" H2 > /dev/null
klar H2 > "$TMPD/H2.log"
if grep -qa 'no right\|no open session\|timeout' "$TMPD/H2.log"; then
    ok "(h) without the session key in /system no secret comes out"
else
    bad "(h) without a session key a secret came out"
fi
nicht "$TMPD/H2.log" "GEHEIMNIS-4711" "(h) und der Klartext steht auch nicht im Protokoll"

# =====================================================================
echo "== 11. (i) without an account everything continues =="
# =====================================================================
cat > "$TMPD/sI.sh" <<'EOS'
echo ==KEINKONTO==
sync merge /konto /daten egal
echo ==ARBEIT==
echo hallo > /daten/neu.txt
cat /daten/neu.txt
echo ==BACKUP==
backup save /daten /store s1
echo ==RESTORE==
backup restore /store s1 /leer
echo ==END==
EOS
mkdir -p "$TMPD/leer2"
bash tools/mkfsfi/mkfs.sh build "$TMPD/I.img" $BLOCKS \
    /bin/ /t/ /proc/ /dev/ /daten/ /store/ /leer/ \
    $(for p in $PROGS; do echo "/bin/$p=$TMPD/bin/$p.elf"; done) \
    /daten/a.txt="$TMPD/daten/a.txt" /t/s.sh="$TMPD/sI.sh" >/dev/null 2>&1
rc=$(lauf "$TMPD/I.img" I)
klar I > "$TMPD/I.log"
is "(i) der Lauf ohne Konto endet ordentlich" "$rc" "21"
sed -n '/^==KEINKONTO==/,/^==ARBEIT==/p' "$TMPD/I.log" | grep -qa 'no such account' \
    && ok "(i) without an account sync says so clearly and does nothing else" \
    || bad "(i) without an account something unexpected happens"
sed -n '/^==ARBEIT==/,/^==BACKUP==/p' "$TMPD/I.log" | grep -qa 'hallo' \
    && ok "(i) and the system keeps working normally" \
    || bad "(i) the system does not keep working"
sed -n '/^==BACKUP==/,/^==END==/p' "$TMPD/I.log" | grep -qa 'restored files' \
    && ok "(i) the backup of round VAULT is still usable unchanged" \
    || bad "(i) the backup broke"

# =====================================================================
echo "== 12. (j) four deliberately broken versions =="
mkdir -p "$TMPD/kaputt"

cp lib/sync/chain.fi "$TMPD/kaputt/kette.fi.orig"
python3 - "$TMPD" <<'PY'
import sys, re
d = sys.argv[1]
s = open("lib/sync/chain.fi").read()
s = s.replace("""fn block_name(namekey: u64, p: u64, n: u64, out: u64) {
    sha256.hmac(namekey, KEYLEN as usize, p, n as usize, out)
}""", """fn block_name(namekey: u64, p: u64, n: u64, out: u64) {
    sha256.hash(p, n as usize, out)
}""")
open(d + "/kaputt/kette-naiv.fi", "w").write(s)
PY
cp -a lib "$TMPD/lib-naiv"
cp "$TMPD/kaputt/kette-naiv.fi" "$TMPD/lib-naiv/sync/chain.fi"   # vor Runde ENGLISCH: kette.fi
if FIRNLIB="$TMPD/lib-naiv" $FIRNC tools/sync/oracle.fi \
        -o "$TMPD/naivoracle" 2>/dev/null; then
    r=$(python3 - "$TMPD" <<'PY'
import binascii, hashlib, os, subprocess, sys
d = sys.argv[1]
blk = os.urandom(4096)
p = subprocess.run([d + "/naivoracle"],
                   input="name %s %s\n" % ("00" * 32,
                                           binascii.hexlify(blk).decode()),
                   capture_output=True, text=True)
print("JA" if p.stdout.strip() == hashlib.sha256(blk).hexdigest() else "NEIN")
PY
)
    is "(j1) GEGENPROBE: mit dem blanken SHA-256 geht der Angriff auf" "$r" "JA"
else
    bad "(j1) the broken version does not build -- the control measures nothing"
fi

python3 - "$TMPD" <<'PYX'
import sys
d = sys.argv[1]
s = open("lib/sync/chain.fi").read()
mit = """    chacha.xaead_seal((&kb[0]) as u64, (&nc[0]) as u64, name,
        NAMELEN as usize, p, n as usize, out)"""
ohne = """    chacha.xaead_seal((&kb[0]) as u64, (&nc[0]) as u64, name,
        0, p, n as usize, out)"""
assert s.count(mit) == 1
t = s.replace(mit, ohne)
auf_mit = """    let ok: bool = chacha.xaead_open((&kb[0]) as u64, (&nc[0]) as u64,
        name, NAMELEN as usize, ct, n as usize, out)"""
auf_ohne = """    let ok: bool = chacha.xaead_open((&kb[0]) as u64, (&nc[0]) as u64,
        name, 0, ct, n as usize, out)"""
assert t.count(auf_mit) == 1
t = t.replace(auf_mit, auf_ohne)
open(d + "/kaputt/kette-ohneaad.fi", "w").write(t)

alt_k = """    block_key(inhaltkey, name, (&kb[0]) as u64)
    block_nonce(inhaltkey, name, (&nc[0]) as u64)"""
neu_k = """    var fest: [u8; 33] = "osum-sync-block-ohne-namensbindg\\0"
    block_key(inhaltkey, (&fest[0]) as u64, (&kb[0]) as u64)
    block_nonce(inhaltkey, (&fest[0]) as u64, (&nc[0]) as u64)"""
assert t.count(alt_k) == 2, t.count(alt_k)
open(d + "/kaputt/kette-losgeloest.fi", "w").write(t.replace(alt_k, neu_k))
PYX
[ $? -eq 0 ] || bad "(j2) the patch script for the broken chain versions failed"
if cmp -s "$TMPD/kaputt/kette-ohneaad.fi" lib/sync/chain.fi; then
    bad "(j2) the broken version is identical to the original -- it measures nothing"
else
    cp -a lib "$TMPD/lib-ohneaad"
    cp "$TMPD/kaputt/kette-ohneaad.fi" "$TMPD/lib-ohneaad/sync/chain.fi"
    cp -a lib "$TMPD/lib-los"
    cp "$TMPD/kaputt/kette-losgeloest.fi" "$TMPD/lib-los/sync/chain.fi"
    b1=nein; b2=nein
    FIRNLIB="$TMPD/lib-ohneaad" $FIRNC tools/sync/oracle.fi \
        -o "$TMPD/aadoracle" 2>/dev/null && b1=ja
    FIRNLIB="$TMPD/lib-los" $FIRNC tools/sync/oracle.fi \
        -o "$TMPD/losoracle" 2>/dev/null && b2=ja
    if [ "$b1" = ja ] && [ "$b2" = ja ]; then
        r=$(python3 - "$TMPD" <<'PYX'
import binascii, os, subprocess, sys
d = sys.argv[1]
k = os.urandom(32)
na, nb = os.urandom(32), os.urandom(32)
blk = os.urandom(4096)
hx = lambda b: binascii.hexlify(b).decode()

def frage(prog, zeile):
    p = subprocess.run([prog], input=zeile + "\n",
                       capture_output=True, text=True)
    return p.stdout.strip()

aus = []
for nam, prog in (("ECHT", ".probe/syncoracle"),
                  ("OHNEAAD", d + "/aadoracle"),
                  ("LOS", d + "/losoracle")):
    ct = frage(prog, "seal %s %s %s" % (hx(k), hx(na), hx(blk)))
    auf = frage(prog, "open %s %s %s" % (hx(k), hx(nb), ct))
    aus.append("%s=%s" % (nam, "FAIL" if auf == "FAIL" else "OFFEN"))
print(" ".join(aus))
PYX
)
        is "(j2) GEGENPROBE: der Block haengt am Namen -- und woran genau" \
           "$r" "ECHT=FAIL OHNEAAD=FAIL LOS=OFFEN"
        note "das AAD allein traegt die Bindung NICHT: Schluessel und Nonce tun es."
        note "Erst wenn auch die weg sind (LOS), geht ein Block unter fremdem Namen auf."
    else
        bad "(j2) the broken versions do not build (ohneaad=$b1 losgeloest=$b2)"
    fi
fi

rm -rf "$TMPD/usrc-j3"; cp -a kernel/user "$TMPD/usrc-j3"
sed 's/^    if g < counter {$/    if false {/' kernel/user/sync.fi > "$TMPD/kaputt/sync-ohneschutz.fi"
if ! cmp -s "$TMPD/kaputt/sync-ohneschutz.fi" kernel/user/sync.fi; then
    cp "$TMPD/kaputt/sync-ohneschutz.fi" "$TMPD/usrc-j3/sync.fi"
    if USRC="$TMPD/usrc-j3" bash tools/sync/build.sh "$TMPD/binj" 0 sync >/dev/null 2>&1; then
        cp "$TMPD/bin/sync.elf" "$TMPD/bin/sync.elf.sicher"
        cp "$TMPD/binj/sync.elf" "$TMPD/bin/sync.elf"
        geraet "$TMPD/J3.img" "$TMPD/sE.sh" "$TMPD/kontoR" "$TMPD/sb-rueck" "$TMPD/leer" -
        lauf "$TMPD/J3.img" J3 > /dev/null
        klar J3 > "$TMPD/J3.log"
        if grep -qa 'ROLLBACK' "$TMPD/J3.log"; then
            bad "(j3) even without protection the rollback is reported -- the test does not measure it"
        else
            ok "(j3) CONTROL: without the counter comparison the rollback passes"
        fi
        cp "$TMPD/bin/sync.elf.sicher" "$TMPD/bin/sync.elf"
    else
        bad "(j3) the broken version does not build"
    fi
    rm -rf "$TMPD/usrc-j3"
else
    bad "(j3) the cut changed nothing -- the control measures nothing"
fi

rm -rf "$TMPD/usrc-j4"; cp -a kernel/user "$TMPD/usrc-j4"
python3 - kernel/user/sync.fi "$TMPD/kaputt/sync-still.fi" <<'PYS'
import sys
s = open(sys.argv[1], encoding='utf-8').read()
s = s.replace("if nat + NAMEHEX + 2 >= NAMBUF {", "if nat + NAMEHEX + 2 >= NAMINLINE {")
s = s.replace("""                    remember_path((&relp[0]) as u64)
                    io.close(dfd[depth as usize])
                    return false""",
              """                    relp[keep as usize] = 0 as u8
                    continue""")
open(sys.argv[2], 'w', encoding='utf-8').write(s)
PYS
if ! cmp -s "$TMPD/kaputt/sync-still.fi" kernel/user/sync.fi; then
    cp "$TMPD/kaputt/sync-still.fi" "$TMPD/usrc-j4/sync.fi"
    if USRC="$TMPD/usrc-j4" bash tools/sync/build.sh "$TMPD/binj4" 0 sync >/dev/null 2>&1; then
        cp "$TMPD/bin/sync.elf" "$TMPD/bin/sync.elf.sicher"
        cp "$TMPD/binj4/sync.elf" "$TMPD/bin/sync.elf"
        mkdir -p "$TMPD/j4store" "$TMPD/j4leer"
        cat > "$TMPD/sJ4.sh" <<EOS
sync new /konto $PASS own /store $NP $RP
sync merge /konto /daten $PASS
echo ==END==
EOS
        geraet "$TMPD/J4a.img" "$TMPD/sJ4.sh" - - "$TMPD/daten" -
        lauf "$TMPD/J4a.img" J4a > /dev/null
        klar J4a > "$TMPD/J4a.log"
        j4dat=$(feld "$TMPD/J4a.txt" files)
        if grep -qa '^done' "$TMPD/J4a.log" && [ "$j4dat" = "4" ]; then
            ok "(j4) CONTROL: with the old 700-octet field gross.bin silently drops out of the sync -- $j4dat instead of 5 files, and the run still reports done"
        else
            bad "(j4) the old version does not behave as expected: dateien=$j4dat, fertig=$(grep -ca '^done' "$TMPD/J4a.log")"
        fi
        cp "$TMPD/bin/sync.elf.sicher" "$TMPD/bin/sync.elf"
    else
        bad "(j4) the broken version does not build"
    fi
    rm -rf "$TMPD/usrc-j4"
else
    bad "(j4) the revert changed nothing -- the control measures nothing"
fi

# =====================================================================
echo "== 12b. the default cost of the key derivation =="
cat > "$TMPD/sP.sh" <<EOS
echo ==VOR==
date -u
sync new /konto $PASS own /store
date -u
vault new /konto /tresor $PASS
date -u
vault open /konto /tresor $PASS 60
date -u
echo ==ZUVIEL==
sync neu /konto2 $PASS eigen /store2 16384 8
echo ==END==
EOS
mkdir -p "$TMPD/leer2"
PROGS_ALT=$PROGS
if ! echo "$PROGS" | grep -qw date; then
    PROGS="$PROGS date"
    bash tools/sync/build.sh "$TMPD/bin" 0 date >/dev/null 2>&1
fi
geraet "$TMPD/P.img" "$TMPD/sP.sh" - - "$TMPD/leer2" -
PROGS=$PROGS_ALT
SYNC_TIMEOUT=900 lauf "$TMPD/P.img" P > /dev/null
klar P > "$TMPD/P.log"
grep -qa '^account: open' "$TMPD/P.log" \
    && ok "the DEFAULT cost (N=4096, r=8, 4 MiB) creates an account" \
    || bad "the default cost creates NO account -- the default is broken"
grep -qa '^vault: open' "$TMPD/P.log" \
    && ok "and the vault opens with it" \
    || bad "and the vault does NOT open with it"
sed -n '/^==ZUVIEL==/,$p' "$TMPD/P.log" | grep -qa 'error' \
    && ok "CONTROL: N=16384 (16 MiB) fails -- the arena has 6 MiB" \
    || bad "N=16384 got through -- then the limit in the header of kbund.fi is wrong"
python3 - "$TMPD/P.log" <<'PYT'
import re, sys
marke = None; letzte = None; namen = ["sync neu", "vault new", "vault open"]
i = 0
for z in open(sys.argv[1], encoding='utf-8', errors='replace').read().splitlines():
    z = z.strip()
    m = re.match(r'^up (\d+) ms$', z)
    if not m:
        continue
    t = int(m.group(1))
    if letzte is not None and i < len(namen):
        print("        %-12s %5d ms (N=4096, r=8, im System)" % (namen[i], t - letzte))
        i += 1
    letzte = t
PYT

# =====================================================================
echo "== 13. die Messungen =="
mkdir -p "$TMPD/mess"
i=0
while [ $i -lt 20 ]; do
    head -c 51200 /dev/urandom > "$TMPD/mess/m$i.bin"
    i=$((i+1))
done
cat > "$TMPD/sM.sh" <<EOS
sync new /konto $PASS own /store $NP $RP
echo ==VOLL==
sync merge /konto /daten $PASS
echo ==NOCHMAL==
sync merge /konto /daten $PASS
echo ==KLEIN==
echo eine-kleine-aenderung > /daten/m0.bin
sync merge /konto /daten $PASS
echo ==END==
EOS
BLOCKS_ALT=$BLOCKS
BLOCKS=16384
geraet "$TMPD/M.img" "$TMPD/sM.sh" - - "$TMPD/mess" -
BLOCKS=$BLOCKS_ALT
t0=$(date +%s%N)
SYNC_TIMEOUT=1800 lauf "$TMPD/M.img" M > /dev/null
t1=$(date +%s%N)
klar M > "$TMPD/M.log"
grep -qa '^==END==' "$TMPD/M.log" \
    && ok "the measurement run really reached the end" \
    || bad "the measurement run did not finish -- the numbers below are worthless"
M_GESAMT=$(( (t1 - t0) / 1000000 ))
M_BLK=$(feld_n "$TMPD/M.txt" blocks 1)
M_NEU1=$(feld_n "$TMPD/M.txt" newblocks 1)
M_NEU2=$(feld_n "$TMPD/M.txt" newblocks 2)
M_NEU3=$(feld_n "$TMPD/M.txt" newblocks 3)
M_GES1=$(feld_n "$TMPD/M.txt" sent 1)
M_GES3=$(feld_n "$TMPD/M.txt" sent 3)
M_LES1=$(feld_n "$TMPD/M.txt" read 1)
note "1 MiB in 20 Dateien: $M_BLK Bloecke, erster Lauf $M_NEU1 neu ($M_GES1 Oktette gesendet)"
note "zweiter Lauf: $M_NEU2 neue Bloecke; nach einer kleinen Aenderung: $M_NEU3"
note "alle drei Laeufe samt Anlegen des Kontos und Systemstart: $M_GESAMT ms (accel=$OSUM_QEMU_ACCEL)"
is "der Messlauf meldet dreimal fertig" "$(grep -ca '^done' "$TMPD/M.log")" "3"
is "der volle Abgleich sieht alle 20 Dateien" "$(feld_n "$TMPD/M.txt" files 1)" "20"
[ -n "$M_BLK" ] && [ "$M_BLK" -ge 300 ] \
    && ok "the full sync sees all blocks: $M_BLK (260 data + 40 name chains + directory)" \
    || bad "the full sync sees only $M_BLK blocks -- 302 expected"
is "und er legt jeden davon neu ab" "$M_NEU1" "$M_BLK"
is "der zweite Lauf schreibt NULL neue Bloecke" "$M_NEU2" "0"
[ -n "$M_NEU3" ] && [ "$M_NEU3" -le 3 ] \
    && ok "a small change costs $M_NEU3 new blocks, not $M_NEU1" \
    || bad "a small change costs $M_NEU3 blocks"

hol "$TMPD/M.img" /store "$TMPD/storeM"
M_KLAR=$(du -sb "$TMPD/mess" | cut -f1)
M_PACK=$(stat -c%s "$TMPD/storeM/PACK" 2>/dev/null || echo 0)
M_IDX=$(stat -c%s "$TMPD/storeM/INDEX" 2>/dev/null || echo 0)
if [ "$M_KLAR" -gt 0 ] && [ "$M_PACK" -gt 0 ]; then
    proz=$(awk "BEGIN{printf \"%.1f\", ($M_PACK+$M_IDX-$M_KLAR)*100.0/$M_KLAR}")
    sieg=$(awk "BEGIN{printf \"%.2f\", 16*100.0/4096}")
    note "Klartext $M_KLAR Oktette -> Speicher $M_PACK (PACK) + $M_IDX (INDEX) = Mehraufwand ${proz} %"
    note "davon Siegel ${sieg} % je Block; der Rest ist das Auffuellen auf 4096 und das Verzeichnis"
    awk "BEGIN{exit !($M_PACK+$M_IDX > $M_KLAR)}" \
        && ok "the store is larger than the plaintext, as it must be" \
        || bad "the store is SMALLER than the plaintext -- a number is wrong"
else
    bad "the overhead cannot be computed: plaintext $M_KLAR, PACK $M_PACK"
fi

M_S1=$(feld_n "$TMPD/M.txt" seconds 1)
M_S2=$(feld_n "$TMPD/M.txt" seconds 2)
M_S3=$(feld_n "$TMPD/M.txt" seconds 3)
note "Dauer der drei Abgleiche: $M_S1 s (voll), $M_S2 s (nichts neu), $M_S3 s (eine Aenderung)"
if [ -n "$M_S1" ] && [ "$M_S1" -gt 0 ]; then
    kbs=$(awk "BEGIN{printf \"%.1f\", $M_KLAR/1024.0/$M_S1}")
    kbs3=$(awk "BEGIN{printf \"%.1f\", $M_KLAR/1024.0/$M_S3}")
    note "erster voller Abgleich: ${kbs} KiB/s; nach einer kleinen Aenderung ${kbs3} KiB/s"
    note "(in QEMU auf einem Wirt unter Last -- das misst die Emulation mit, nicht nur das Verfahren)"
fi

python3 - "$TMPD" > "$TMPD/kdf.txt" <<'PY'
import binascii, os, subprocess, sys, time
d = sys.argv[1]
O = ".probe/syncoracle"
for (N, r) in [(256, 8), (1024, 8), (4096, 8), (16384, 8)]:
    t = time.time()
    subprocess.run([O], input="scrypt %s %s %d %d 1 32\n"
                   % (binascii.hexlify(b"passphrase").decode(),
                      binascii.hexlify(os.urandom(16)).decode(), N, r),
                   capture_output=True, text=True)
    el = (time.time() - t) * 1000
    print("  N=%-6d r=%d  Speicher %7d KiB  %7.1f ms"
          % (N, r, (N + 2) * 128 * r // 1024, el))
PY
sed 's/^/     /' "$TMPD/kdf.txt"
is "die Schluesselableitung: vier Stufen gemessen (auf dem Wirt, firnc0)" \
   "$(grep -c 'N=' "$TMPD/kdf.txt" 2>/dev/null || echo 0)" "4"

python3 - <<'PY'
n = 10000
zeile = 64 + 1 + 9 + 1 + 4 + 1     # name TAB offset TAB laenge NL
print("  Block index for 10 000 files (one block each): %d octets = %.1f KiB"
      % (n * zeile, n * zeile / 1024.0))
print("  in the store (32 octets name + 2 x 8 number per block): %d KiB"
      % (n * 48 // 1024))
PY
note "gerechnet aus dem Format, dessen Zeilen oben gemessen wurden"

is "kernel/user/sync.fi im Baum ist nach allen Gegenproben unangetastet" \
   "$(sha256sum kernel/user/sync.fi | cut -d' ' -f1)" "$SYNC_SHA0"

echo
echo "SYNC: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
