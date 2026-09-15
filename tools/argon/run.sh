#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/argon/run.sh -- DIE ABNAHME DER RUNDE ARGON (K-021).
#
# DIE FRAGE DIESER RUNDE: wird das AUFSPERREN schneller, ohne dass die
# Rechnung wackelt?
#
# Die zweite Haelfte ist die schwerere, und sie ist schaerfer als bei
# AES-NI. Ein Argon2, das anders rechnet als die Norm, macht jede
# bestehende verschluesselte Platte UNAUFSPERRBAR -- und zwar still: der
# abgeleitete Schluessel sieht genauso zufaellig aus wie der richtige,
# nur passt der Pruefwert nicht mehr. Deshalb misst dieser Laeufer die
# Richtigkeit zuerst und das Tempo zuletzt.
#
# WAS GEMESSEN WIRD, in dieser Reihenfolge:
#
#   1. Die Speicherkarte: 0 Kollisionen, und der Bereich dieser Runde
#      an der ZUGETEILTEN Adresse (0x126000) mit den zugeteilten
#      Modusindizes (1040..1049).
#   2. Der Bau: Kern und Orakel.
#   3. DIE RICHTIGKEIT VON ARGON2 gegen `argon2-cffi`, die
#      Referenzumsetzung von RFC 9106 -- und darin ausdruecklich der
#      Vektor t=3/m=32/p=4, denn genau der prueft, ob die Spuren
#      richtig zusammengesetzt werden.
#   4. EINE BESTEHENDE PLATTE. Mit dem ALTEN Code angelegt, mit dem
#      NEUEN aufgesperrt. Das ist die Zusage, die zaehlt.
#   5. DIE PARALLELITAET: laufen die Spuren wirklich auf mehreren
#      Kernen? Gemessen wird die Zahl der KERNE, auf denen die Spuren
#      gerechnet haben -- nicht die Zahl der angelegten Aufgaben.
#   6. SHA-NI: die Kreisprobe ueber viele Laengen, FIPS 180-4, und der
#      Rueckfallweg ECHT gefahren (`-cpu qemu64` hat kein SHA-NI).
#   7. DAS TEMPO, seriell gegen parallel, auf DERSELBEN Maschine.
#   8. Dass die Nachbarn heil sind: krypto 61/0 und aesni 31/0.
#
# Aufruf:  bash tools/argon/run.sh
#          OSUM_ARGON_SCHNELL=1   ohne die beiden Nachbar-Abnahmen
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
SCHNELL=${OSUM_ARGON_SCHNELL:-0}

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
info(){ printf '        %s\n' "$1"; }

# Das fremde Werkzeug. Ohne argon2-cffi gibt es keine Gegenrechnung.
PY=python3
for kandidat in "${OSUM_KRYPTO_PY:-}" /root/.krypto-venv/bin/python python3; do
    [ -n "$kandidat" ] || continue
    command -v "$kandidat" >/dev/null 2>&1 || [ -x "$kandidat" ] || continue
    if "$kandidat" -c 'import argon2.low_level' 2>/dev/null; then
        PY=$kandidat
        break
    fi
done

echo "== 1. die Speicherkarte und die zugeteilten Nummern =="

if python3 tools/kernel/memmap.py kernel >"$TMPD/map.txt" 2>&1; then
    ok "die kdata-Karte ist ueberschneidungsfrei (memmap.py)"
    info "$(tail -1 "$TMPD/map.txt")"
else
    bad "memmap.py meldet eine Kollision"
    tail -5 "$TMPD/map.txt"
fi

grep -q 'ARGON_OFF' tools/kernel/memmap.py \
    && ok "ARGON steht in tools/kernel/memmap.py" \
    || bad "ARGON fehlt in tools/kernel/memmap.py"

grep -q 'const ARGON_OFF: u64 = 0x126000' kernel/kstate.fi \
    && ok "der kdata-Bereich liegt auf 0x126000 wie zugeteilt" \
    || bad "ARGON_OFF steht nicht auf 0x126000"
grep -q 'const ARGON_MAX: u64 = 0x1000' kernel/kstate.fi \
    && ok "und ist EINE Seite gross wie zugeteilt" \
    || bad "ARGON_MAX ist nicht 0x1000"
grep -q 'const M_NOARGONPAR: u64 = 1040' kernel/kstate.fi \
    && ok "die Modusindizes fangen bei 1040 an wie zugeteilt" \
    || bad "M_NOARGONPAR steht nicht auf 1040"
hoch=$(grep -oE 'const M_[A-Z0-9]+: u64 = 104[0-9]' kernel/kstate.fi \
    | grep -oE '104[0-9]' | sort -n | tail -1)
[[ -n $hoch && $hoch -le 1049 ]] \
    && ok "kein Modusindex dieser Runde oberhalb von 1049 (hoechster: $hoch)" \
    || bad "ein Modusindex liegt ausserhalb von 1040..1049"
# Und der Vektor muss die Indizes TRAGEN -- die Lehre aus Welle 2.
mw=$(grep -oE 'const MODE_WORDS: u64 = [0-9]+' kernel/kstate.fi | grep -oE '[0-9]+$')
[[ -n $mw ]] && [[ $((mw * 64)) -gt 1049 ]] \
    && ok "der Modusvektor traegt Index 1049 (MODE_WORDS=$mw -> $((mw*64)) Bits)" \
    || bad "der Modusvektor ist zu kurz fuer 1049"

echo "== 2. der Bau =="

if $FIRNC tools/krypto/orakel.fi -o "$TMPD/orakel" 2>"$TMPD/o.err"; then
    ok "das Orakel uebersetzt (dieselben lib/crypto-Dateien wie der Kern)"
else
    bad "das Orakel uebersetzt nicht"
    tail -5 "$TMPD/o.err"
fi

if $FIRNC tools/argon/kreis.fi -o "$TMPD/kreis" 2>"$TMPD/k.err"; then
    ok "die SHA-Kreisprobe uebersetzt"
else
    bad "die SHA-Kreisprobe uebersetzt nicht"
    tail -5 "$TMPD/k.err"
fi

if timeout 900 bash tools/build-kernel.sh "$TMPD/k0.mb" >"$TMPD/b.log" 2>&1; then
    ok "der Kern baut"
else
    bad "der Kern baut nicht"
    tail -8 "$TMPD/b.log"
fi

echo "== 3. Argon2 gegen die Referenzumsetzung (RFC 9106) =="

if "$PY" -c 'import argon2.low_level' 2>/dev/null && [ -x "$TMPD/orakel" ]; then
    "$PY" - "$TMPD/orakel" >"$TMPD/arg.txt" 2>&1 <<'PYEOF'
import subprocess, sys, random
from argon2.low_level import hash_secret_raw, Type
ORA = sys.argv[1]
def ora(cmd):
    return subprocess.run([ORA], input=cmd + "\n", capture_output=True,
                          text=True).stdout.strip()
# DER WICHTIGSTE VEKTOR: RFC 9106 Abschnitt 5.3, p=4.
pw = bytes([1]) * 32
salt = bytes([2]) * 16
soll = hash_secret_raw(secret=pw, salt=salt, time_cost=3, memory_cost=32,
                       parallelism=4, hash_len=32, type=Type.ID,
                       version=19).hex()
ist = ora("argon2id %s %s 3 32 4 32" % (pw.hex(), salt.hex()))
print("RFC9106 %s" % ("ja" if soll == ist else "NEIN %s %s" % (soll, ist)))
# Und die Breite: alle drei Spielarten, t, m und p durchgefahren.
tt = {"ID": Type.ID, "I": Type.I, "D": Type.D}
wort = {"ID": "argon2id", "I": "argon2i", "D": "argon2d"}
random.seed(4711)
gut = 0
ges = 0
for ty in ("ID", "I", "D"):
    for t in (1, 2, 3):
        for m in (8, 16, 32, 64, 128, 256):
            for p in (1, 2, 4, 8):
                if m < 8 * p:
                    continue
                pwd = bytes(random.randrange(256)
                            for _ in range(random.choice([0, 8, 16])))
                sl = bytes(random.randrange(256) for _ in range(16))
                n = random.choice([16, 32, 64, 96])
                s = hash_secret_raw(secret=pwd, salt=sl, time_cost=t,
                                    memory_cost=m, parallelism=p,
                                    hash_len=n, type=tt[ty],
                                    version=19).hex()
                i = ora("%s %s %s %d %d %d %d"
                        % (wort[ty], pwd.hex() if pwd else "-", sl.hex(),
                           t, m, p, n))
                ges += 1
                if s == i:
                    gut += 1
print("breite %d/%d" % (gut, ges))
PYEOF
    grep -q '^RFC9106 ja' "$TMPD/arg.txt" \
        && ok "der RFC-9106-Vektor mit t=3/m=32/p=4 stimmt (die Spuren werden richtig zusammengesetzt)" \
        || bad "der RFC-9106-Vektor mit p=4 stimmt NICHT -- $(grep '^RFC9106' "$TMPD/arg.txt")"
    br=$(grep -oE '^breite [0-9]+/[0-9]+' "$TMPD/arg.txt" | cut -d' ' -f2)
    if [[ -n $br && ${br%/*} == ${br#*/} ]]; then
        ok "Argon2id/i/d gegen argon2-cffi: $br"
    else
        bad "Argon2 weicht ab: $br"
    fi
    # Und die ganze Kryptokette, mit SHA-NI scharf.
    if "$PY" tools/krypto/gegen.py vektoren "$TMPD/orakel" >"$TMPD/vek.txt" 2>&1; then
        ges=$(grep -oE 'gesamt [0-9]+/[0-9]+' "$TMPD/vek.txt" | cut -d' ' -f2)
        [[ -n $ges && ${ges%/*} == ${ges#*/} ]] \
            && ok "die ganze Kryptokette gegen hashlib/OpenSSL/argon2-cffi: $ges" \
            || bad "die Kryptokette weicht ab: $ges"
    else
        bad "gegen.py vektoren scheitert"
    fi
else
    info "argon2-cffi fehlt -- Abschnitt 3 uebersprungen"
    info "  python3 -m venv /root/.krypto-venv"
    info "  /root/.krypto-venv/bin/pip install argon2-cffi cryptography"
fi

echo "== 4. eine BESTEHENDE Platte: mit dem ALTEN Code angelegt, mit dem NEUEN auf =="

BLOCKS=8192
python3 tools/osum/mkfs.py build "$TMPD/root.img" "$BLOCKS" \
    /bin/ /proc/ /dev/ >"$TMPD/mkfs.log" 2>&1 \
    && ok "die Wurzelplatte steht" \
    || bad "mkfs.py scheitert"

# Der ALTE Kern: derselbe Baum, aber mit `noargonpar` -- das ist
# buchstabengetreu der Weg der Vorrunde (Spuren nacheinander).
lauf() { # name abbild kommandozeile [smp] [zeitlimit]
    local name=$1 img=$2 app=$3 smp=${4:-4} t=${5:-300}
    timeout "$t" $QEMU_X86 -kernel "$TMPD/k0.mb" -m 512 -smp "$smp" \
        -append "$app" -serial "file:$TMPD/$name.txt" -display none \
        -no-reboot -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        -drive "file=$img,format=raw,if=ide,index=0" >/dev/null 2>&1
    return 0
}

cp --sparse=always "$TMPD/root.img" "$TMPD/alt.img"
KP="kryptot=1 kryptom=64 kryptop=4"
lauf alt1 "$TMPD/alt.img" "osum nopwr kryptoneu noargonpar kryptopw=geheim $KP" 1
grep -q 'krypto: neu=1' "$TMPD/alt1.txt" \
    && ok "die Platte wird mit dem SERIELLEN Weg angelegt (noargonpar, ein Kern)" \
    || bad "das Anlegen mit dem seriellen Weg scheitert"

lauf alt2 "$TMPD/alt.img" "osum nopwr kryptoauf kryptopw=geheim" 4
grep -q 'auf=1' "$TMPD/alt2.txt" \
    && ok "und der PARALLELE Weg macht sie wieder auf -- die Zusage dieser Runde" \
    || bad "die bestehende Platte geht mit dem parallelen Weg NICHT auf"
grep -q 'osum: mount=1' "$TMPD/alt2.txt" \
    && ok "das Dateisystem darauf haengt ein" \
    || bad "mount scheitert"

# Und die Gegenrichtung: parallel angelegt, seriell aufgemacht.
cp --sparse=always "$TMPD/root.img" "$TMPD/par.img"
lauf par1 "$TMPD/par.img" "osum nopwr kryptoneu kryptopw=geheim $KP" 4
lauf par2 "$TMPD/par.img" "osum nopwr kryptoauf noargonpar kryptopw=geheim" 1
grep -q 'auf=1' "$TMPD/par2.txt" \
    && ok "und umgekehrt: parallel angelegt, seriell aufgemacht" \
    || bad "die Gegenrichtung scheitert"

# Eine falsche Passphrase muss weiter abgewiesen werden.
lauf fal "$TMPD/alt.img" "osum nopwr kryptoauf kryptofalsch kryptopw=geheim" 4
grep -q 'auf=0' "$TMPD/fal.txt" \
    && ok "die falsche Passphrase wird weiter abgewiesen (auf=0)" \
    || bad "eine falsche Passphrase kommt durch"

echo "== 5. laufen die Spuren wirklich auf mehreren Kernen? =="

kerne_von() { grep -oE 'argon: par=[0-9]+ +spur=[0-9]+ +kerne=[0-9]+' "$1" \
    | grep -oE 'kerne=[0-9]+' | cut -d= -f2 | tail -1; }
par_von() { grep -oE 'argon: par=[0-9]+' "$1" | cut -d= -f2 | tail -1; }

p4=$(par_von "$TMPD/alt2.txt")
[[ ${p4:-0} == 1 ]] \
    && ok "der parallele Weg wird wirklich gegangen (par=1)" \
    || bad "par=$p4 -- der parallele Weg greift nicht"

# WIE VIELE KERNE WIRKLICH GERECHNET HABEN -- und warum das NICHT an
# `alt2.txt` gemessen wird.
#
# `alt.img` traegt die kleinen Abnahmeparameter (t=1, m=64 KiB). Ein
# Segment ist dort VIER Bloecke gross, und die sind schneller gerechnet,
# als der Ablaufplaner eine Aufgabe auf einen anderen Kern legt: der
# Startkern hat alle vier Spuren fertig, bevor ein zweiter sie
# anfassen kann. GEMESSEN, vier Laeufe hintereinander, alle `kerne=1`
# bei `takte=5,8..6,0 Mio`.
#
# Das ist KEIN Fehler und wird hier deshalb auch nicht als einer
# gemeldet -- es ist die richtige Antwort auf eine Rechnung, die zu
# klein ist, um sie zu verteilen. Gemessen wird die Verteilung deshalb
# an den VORGABEparametern (t=2, m=32 MiB), und das ist genau der Lauf,
# den Abschnitt 7 ohnehin fuer das Tempo braucht.
info "an den kleinen Abnahmeparametern (t=1, m=64 KiB) ist kerne=$(kerne_von "$TMPD/alt2.txt") -- ein Segment ist dort 4 Bloecke gross"

# Die Gegenprobe: mit `noargonpar` MUSS par=0 herauskommen.
ps=$(par_von "$TMPD/par2.txt")
[[ ${ps:-9} == 0 ]] \
    && ok "GEGENPROBE: mit noargonpar ist par=0 (der Schalter wirkt wirklich)" \
    || bad "noargonpar schaltet nicht ab (par=$ps)"

echo "== 6. SHA-NI: Kreisprobe, FIPS 180-4, und der Rueckfall ECHT gefahren =="

if [[ -x "$TMPD/kreis" ]]; then
    kz=$("$TMPD/kreis" 2>&1 | head -1)
    kh=$("$TMPD/kreis" 2>&1 | tail -1)
    info "$kz"
    ungl=$(echo "$kz" | grep -oE 'ungleich=[0-9]+' | cut -d= -f2)
    fae=$(echo "$kz" | grep -oE 'faelle=[0-9]+' | cut -d= -f2)
    [[ ${ungl:-1} == 0 && ${fae:-0} -gt 1000 ]] \
        && ok "beide SHA-256-Wege liefern dasselbe ueber $fae Laengen (0 ungleich)" \
        || bad "die SHA-Wege weichen ab: $kz"
    [[ $kh == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" ]] \
        && ok "FIPS 180-4 'abc' ueber den schnellen Weg" \
        || bad "FIPS 180-4 stimmt nicht: $kh"
fi

# Im Kern, auf drei verschiedenen Maschinen.
shani_lauf() { # name cpu extra
    timeout 300 $QEMU_X86 -kernel "$TMPD/k0.mb" -m 512 -smp 4 -cpu "$2" \
        -append "osum nopwr shatest kryptoauf kryptopw=geheim $3" \
        -serial "file:$TMPD/$1.txt" -display none -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        -drive "file=$TMPD/alt.img,format=raw,if=ide,index=0" >/dev/null 2>&1
    return 0
}

shani_lauf sh_host host ""
shani_lauf sh_off host "noshani"
shani_lauf sh_q qemu64 ""

kreis_ok() { # datei
    local u
    u=$(grep -oE 'shani: kreis g=[0-9]+ +ungl=[0-9]+' "$1" \
        | grep -oE 'ungl=[0-9]+' | cut -d= -f2 | tail -1)
    [[ ${u:-1} == 0 ]]
}

grep -q 'shani: have=1  used=1' "$TMPD/sh_host.txt" \
    && ok "auf einer CPU MIT SHA-NI ist der schnelle Weg scharf (have=1 used=1)" \
    || bad "SHA-NI greift auf -cpu host nicht: $(grep -o 'shani: .*' "$TMPD/sh_host.txt" | head -1)"
kreis_ok "$TMPD/sh_host.txt" \
    && ok "und die Kreisprobe in Ring 0 ist sauber (ungl=0)" \
    || bad "die Kreisprobe in Ring 0 weicht ab"

grep -q 'shani: have=1  used=0' "$TMPD/sh_off.txt" \
    && ok "GEGENPROBE von Hand: noshani nimmt den schnellen Weg heraus (used=0)" \
    || bad "noshani wirkt nicht"
kreis_ok "$TMPD/sh_off.txt" \
    && ok "und auch dann rechnen beide Wege dasselbe" \
    || bad "ohne SHA-NI weicht die Kreisprobe ab"

grep -q 'shani: have=0  used=0' "$TMPD/sh_q.txt" \
    && ok "RUECKFALL ECHT GEFAHREN: -cpu qemu64 hat kein SHA-NI (have=0), kein #UD" \
    || bad "auf -cpu qemu64 stimmt der Befund nicht: $(grep -o 'shani: .*' "$TMPD/sh_q.txt" | head -1)"
grep -q 'kernel: done' "$TMPD/sh_q.txt" \
    && ok "und der Kern laeuft dort bis zum Ende durch" \
    || bad "der Kern stirbt auf einer CPU ohne SHA-NI"
grep -q 'auf=1' "$TMPD/sh_q.txt" \
    && ok "und macht die Platte auch dort auf" \
    || bad "ohne SHA-NI geht die Platte nicht auf"

echo "== 7. das Tempo, seriell gegen parallel, auf DERSELBEN Maschine =="

takte_von() { grep -oE 'takte=[0-9]+' "$1" | cut -d= -f2 | tail -1; }

cp --sparse=always "$TMPD/root.img" "$TMPD/t.img"
lauf tneu "$TMPD/t.img" "osum nopwr kryptoneu noargonpar kryptopw=geheim kryptot=2 kryptom=32768 kryptop=4" 1 600
lauf tser "$TMPD/t.img" "osum nopwr kryptoauf noargonpar kryptopw=geheim" 4 600
lauf tpar "$TMPD/t.img" "osum nopwr kryptoauf kryptopw=geheim" 4 600
ts=$(takte_von "$TMPD/tser.txt")
tp=$(takte_von "$TMPD/tpar.txt")
kp=$(kerne_von "$TMPD/tpar.txt")
if [[ -n $ts && -n $tp && $tp -gt 0 ]]; then
    fak=$(( ts * 100 / tp ))
    info "Argon2 (t=2, m=32 MiB, p=4): seriell $ts Takte, parallel $tp Takte auf $kp Kernen"
    info "Faktor $((fak / 100)),$(printf '%02d' $((fak % 100)))"
    [[ $fak -ge 150 ]] \
        && ok "der parallele Weg ist mindestens Faktor 1,5 schneller (gemessen: $((fak/100)),$(printf '%02d' $((fak%100))))" \
        || bad "der Gewinn ist zu klein: Faktor $((fak/100)),$(printf '%02d' $((fak%100)))"
    # DIE VERTEILUNG, an den Vorgabeparametern gemessen -- hier ist die
    # Rechnung gross genug, dass sich das Verteilen lohnt.
    [[ ${kp:-0} -ge 2 ]] \
        && ok "und die Spuren rechnen dabei wirklich auf mehreren Kernen (kerne=$kp)" \
        || bad "kerne=$kp -- bei den Vorgabeparametern laeuft alles auf einem Kern"
else
    bad "keine Taktzahlen gemessen (ts=$ts tp=$tp)"
fi

echo "== 8. die Nachbarn =="

if [[ $SCHNELL == 1 ]]; then
    info "OSUM_ARGON_SCHNELL=1 -- die Nachbar-Abnahmen uebersprungen"
else
    if bash tools/krypto/run.sh >"$TMPD/kr.txt" 2>&1; then
        z=$(grep -oE 'KRYPTO: [0-9]+ bestanden, [0-9]+ gescheitert' "$TMPD/kr.txt" | tail -1)
        info "$z"
        echo "$z" | grep -q ', 0 gescheitert' \
            && ok "die Abnahme der Runde KRYPTO ist weiter gruen ($z)" \
            || bad "KRYPTO ist rot: $z"
    else
        bad "tools/krypto/run.sh scheitert"
        tail -5 "$TMPD/kr.txt"
    fi
    if bash tools/aesni/run.sh >"$TMPD/ae.txt" 2>&1; then
        z=$(grep -oE 'AESNI: [0-9]+ bestanden, [0-9]+ gescheitert' "$TMPD/ae.txt" | tail -1)
        info "$z"
        echo "$z" | grep -q ', 0 gescheitert' \
            && ok "die Abnahme der Runde AESNI ist weiter gruen ($z)" \
            || bad "AESNI ist rot: $z"
    else
        bad "tools/aesni/run.sh scheitert"
        tail -5 "$TMPD/ae.txt"
    fi
fi

echo "== 9. die Oberflaeche =="
if bash tools/check-ui.sh >"$TMPD/ui.txt" 2>&1; then
    ok "check-ui.sh PASSED"
else
    bad "check-ui.sh scheitert"
    tail -5 "$TMPD/ui.txt"
fi

echo
echo "ARGON: $pass bestanden, $fail gescheitert"
[[ $fail == 0 ]]
