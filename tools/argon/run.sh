#!/usr/bin/env bash
#
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

PY=python3
for kandidat in "${OSUM_KRYPTO_PY:-}" /root/.krypto-venv/bin/python python3; do
    [ -n "$kandidat" ] || continue
    command -v "$kandidat" >/dev/null 2>&1 || [ -x "$kandidat" ] || continue
    if "$kandidat" -c 'import argon2.low_level' 2>/dev/null; then
        PY=$kandidat
        break
    fi
done

echo "== 1. the memory map and the assigned numbers =="

if python3 tools/kernel/memmap.py kernel >"$TMPD/map.txt" 2>&1; then
    ok "the kdata map is overlap-free (memmap.py)"
    info "$(tail -1 "$TMPD/map.txt")"
else
    bad "memmap.py meldet eine Kollision"
    tail -5 "$TMPD/map.txt"
fi

grep -q 'ARGON_OFF' tools/kernel/memmap.py \
    && ok "ARGON steht in tools/kernel/memmap.py" \
    || bad "ARGON fehlt in tools/kernel/memmap.py"

grep -q 'const ARGON_OFF: u64 = 0x126000' kernel/lib/kstate.fi \
    && ok "the kdata range is at 0x126000 as assigned" \
    || bad "ARGON_OFF is not at 0x126000"
grep -q 'const ARGON_MAX: u64 = 0x1000' kernel/lib/kstate.fi \
    && ok "and is ONE page in size as assigned" \
    || bad "ARGON_MAX is not 0x1000"
grep -q 'const M_NOARGONPAR: u64 = 1040' kernel/lib/kstate.fi \
    && ok "the mode indices start at 1040 as assigned" \
    || bad "M_NOARGONPAR is not at 1040"
hoch=$(grep -oE 'const M_[A-Z0-9]+: u64 = 104[0-9]' kernel/lib/kstate.fi \
    | grep -oE '104[0-9]' | sort -n | tail -1)
[[ -n $hoch && $hoch -le 1049 ]] \
    && ok "no mode index of this round above 1049 (highest: $hoch)" \
    || bad "a mode index is outside 1040..1049"
mw=$(grep -oE 'const MODE_WORDS: u64 = [0-9]+' kernel/lib/kstate.fi | grep -oE '[0-9]+$')
[[ -n $mw ]] && [[ $((mw * 64)) -gt 1049 ]] \
    && ok "der Modusvektor traegt Index 1049 (MODE_WORDS=$mw -> $((mw*64)) Bits)" \
    || bad "the mode vector is too short for 1049"

echo "== 2. der Bau =="

if $FIRNC tools/krypto/orakel.fi -o "$TMPD/orakel" 2>"$TMPD/o.err"; then
    ok "the oracle compiles (the same lib/crypto files as the kernel)"
else
    bad "the oracle does not compile"
    tail -5 "$TMPD/o.err"
fi

if $FIRNC tools/argon/kreis.fi -o "$TMPD/kreis" 2>"$TMPD/k.err"; then
    ok "die SHA-Kreisprobe uebersetzt"
else
    bad "the SHA round-trip check does not compile"
    tail -5 "$TMPD/k.err"
fi

if timeout 900 bash tools/build-kernel.sh "$TMPD/k0.mb" >"$TMPD/b.log" 2>&1; then
    ok "der Kern baut"
else
    bad "the kernel does not build"
    tail -8 "$TMPD/b.log"
fi

echo "== 3. Argon2 against the reference implementation (RFC 9106) =="

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
        && ok "the RFC 9106 vector with t=3/m=32/p=4 matches (the lanes are assembled correctly)" \
        || bad "the RFC 9106 vector with p=4 does NOT match -- $(grep '^RFC9106' "$TMPD/arg.txt")"
    br=$(grep -oE '^breite [0-9]+/[0-9]+' "$TMPD/arg.txt" | cut -d' ' -f2)
    if [[ -n $br && ${br%/*} == ${br#*/} ]]; then
        ok "Argon2id/i/d gegen argon2-cffi: $br"
    else
        bad "Argon2 weicht ab: $br"
    fi
    if "$PY" tools/krypto/gegen.py vektoren "$TMPD/orakel" >"$TMPD/vek.txt" 2>&1; then
        ges=$(grep -oE 'gesamt [0-9]+/[0-9]+' "$TMPD/vek.txt" | cut -d' ' -f2)
        [[ -n $ges && ${ges%/*} == ${ges#*/} ]] \
            && ok "the whole crypto chain against hashlib/OpenSSL/argon2-cffi: $ges" \
            || bad "die Kryptokette weicht ab: $ges"
    else
        bad "gegen.py vektoren scheitert"
    fi
else
    bad "argon2-cffi missing or oracle not built: section 3 cannot run (no skip allowed)"
    info "  python3 -m venv /root/.krypto-venv"
    info "  /root/.krypto-venv/bin/pip install argon2-cffi cryptography"
fi

echo "== 3b. fixed known-answer vectors (FIPS-197, SP 800-38A, IEEE 1619, Argon2 reference) =="

if [ -x "$TMPD/orakel" ]; then
    python3 -I tools/krypto/kat.py "$TMPD/orakel" >"$TMPD/kat.txt" 2>&1
    katline=$(grep -oE 'kat total [0-9]+/[0-9]+' "$TMPD/kat.txt" | tail -1)
    kg=${katline#kat total }
    if [[ -n $kg && ${kg%/*} == ${kg#*/} && ${kg#*/} -ge 30 ]]; then
        ok "all fixed known-answer vectors match, table and AES-NI path ($kg)"
    else
        bad "known-answer vectors fail: ${katline:-no result}"
        grep 'kat: FAIL' "$TMPD/kat.txt" | head -5 | cut -c1-160
    fi
    tamper_build() { # name sed-or-python-expression-file
        local name=$1
        rm -rf "$TMPD/lib_$name"
        cp -r lib "$TMPD/lib_$name"
    }
    tamper_build sbox
    python3 -I - "$TMPD/lib_sbox/crypto/aes.fi" <<'PYEOF'
import sys
d = open(sys.argv[1]).read()
assert "0x63,0x7c" in d
open(sys.argv[1], "w").write(d.replace("0x63,0x7c", "0x62,0x7c", 1))
PYEOF
    tamper_build version
    python3 -I - "$TMPD/lib_version/crypto/argon2.fi" <<'PYEOF'
import sys
d = open(sys.argv[1]).read()
assert "const VERSION: u64 = 0x13" in d
open(sys.argv[1], "w").write(d.replace("const VERSION: u64 = 0x13", "const VERSION: u64 = 0x12", 1))
PYEOF
    tamper_build imc
    python3 -I - "$TMPD/lib_imc/crypto/aesni.fi" <<'PYEOF'
import sys
d = open(sys.argv[1]).read()
a = "aesimc xmm0,xmm0"
assert a in d
open(sys.argv[1], "w").write(d.replace(a, "movdqa xmm0,xmm0", 1))
PYEOF
    for t in sbox version imc; do
        if FIRNLIB="$TMPD/lib_$t" $FIRNC tools/krypto/orakel.fi -o "$TMPD/orakel_$t" 2>"$TMPD/ot_$t.err"; then
            if python3 -I tools/krypto/kat.py "$TMPD/orakel_$t" >"$TMPD/kat_$t.txt" 2>&1; then
                bad "CONTROL RUN: tampered $t is NOT detected by the known-answer vectors"
            else
                ok "CONTROL RUN: tampered $t is detected ($(grep -c 'kat: FAIL' "$TMPD/kat_$t.txt") vectors red)"
            fi
        else
            bad "CONTROL RUN: tampered $t oracle does not build"
            tail -3 "$TMPD/ot_$t.err"
        fi
    done
else
    bad "oracle not built: known-answer vectors cannot run (no skip allowed)"
fi

echo "== 4. an EXISTING disk: created with the OLD code, opened with the NEW =="

BLOCKS=8192
bash tools/mkfsfi/mkfs.sh build "$TMPD/root.img" "$BLOCKS" \
    /bin/ /proc/ /dev/ >"$TMPD/mkfs.log" 2>&1 \
    && ok "the root disk is there" \
    || bad "mkfs.py scheitert"

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
    && ok "the disk is created with the SERIAL path (noargonpar, one core)" \
    || bad "creating with the serial path fails"

lauf alt2 "$TMPD/alt.img" "osum nopwr kryptoauf kryptopw=geheim" 4
grep -q 'auf=1' "$TMPD/alt2.txt" \
    && ok "and the PARALLEL path opens it again -- the promise of this round" \
    || bad "the existing disk does NOT open with the parallel path"
grep -q 'osum: mount=1' "$TMPD/alt2.txt" \
    && ok "the file system on it mounts" \
    || bad "mount scheitert"

cp --sparse=always "$TMPD/root.img" "$TMPD/par.img"
lauf par1 "$TMPD/par.img" "osum nopwr kryptoneu kryptopw=geheim $KP" 4
lauf par2 "$TMPD/par.img" "osum nopwr kryptoauf noargonpar kryptopw=geheim" 1
grep -q 'auf=1' "$TMPD/par2.txt" \
    && ok "und umgekehrt: parallel angelegt, seriell aufgemacht" \
    || bad "die Gegenrichtung scheitert"

lauf fal "$TMPD/alt.img" "osum nopwr kryptoauf kryptofalsch kryptopw=geheim" 4
grep -q 'auf=0' "$TMPD/fal.txt" \
    && ok "the wrong passphrase is still rejected (open=0)" \
    || bad "a wrong passphrase gets through"

echo "== 5. do the lanes really run on several cores? =="

kerne_von() { grep -oE 'argon: par=[0-9]+ +spur=[0-9]+ +kerne=[0-9]+' "$1" \
    | grep -oE 'kerne=[0-9]+' | cut -d= -f2 | tail -1; }
par_von() { grep -oE 'argon: par=[0-9]+' "$1" | cut -d= -f2 | tail -1; }

p4=$(par_von "$TMPD/alt2.txt")
[[ ${p4:-0} == 1 ]] \
    && ok "the parallel path is really taken (par=1)" \
    || bad "par=$p4 -- the parallel path does not take effect"

info "with the small acceptance parameters (t=1, m=64 KiB) cores=$(kerne_von "$TMPD/alt2.txt") -- ein Segment ist dort 4 Bloecke gross"

ps=$(par_von "$TMPD/par2.txt")
[[ ${ps:-9} == 0 ]] \
    && ok "CONTROL: with noargonpar par=0 (the switch really works)" \
    || bad "noargonpar schaltet nicht ab (par=$ps)"

echo "== 6. SHA-NI: round-trip check, FIPS 180-4, and the fallback REALLY driven =="

if [[ -x "$TMPD/kreis" ]]; then
    kz=$("$TMPD/kreis" 2>&1 | head -1)
    kh=$("$TMPD/kreis" 2>&1 | tail -1)
    info "$kz"
    ungl=$(echo "$kz" | grep -oE 'ungleich=[0-9]+' | cut -d= -f2)
    fae=$(echo "$kz" | grep -oE 'faelle=[0-9]+' | cut -d= -f2)
    [[ ${ungl:-1} == 0 && ${fae:-0} -gt 1000 ]] \
        && ok "both SHA-256 paths yield the same over $fae lengths (0 unequal)" \
        || bad "die SHA-Wege weichen ab: $kz"
    [[ $kh == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" ]] \
        && ok "FIPS 180-4 'abc' ueber den schnellen Weg" \
        || bad "FIPS 180-4 stimmt nicht: $kh"
fi

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
    && ok "on a CPU WITH SHA-NI the fast path is armed (have=1 used=1)" \
    || bad "SHA-NI does not take effect on -cpu host: $(grep -o 'shani: .*' "$TMPD/sh_host.txt" | head -1)"
kreis_ok "$TMPD/sh_host.txt" \
    && ok "and the round-trip check in ring 0 is clean (unequal=0)" \
    || bad "die Kreisprobe in Ring 0 weicht ab"

grep -q 'shani: have=1  used=0' "$TMPD/sh_off.txt" \
    && ok "CONTROL by hand: noshani takes the fast path out (used=0)" \
    || bad "noshani wirkt nicht"
kreis_ok "$TMPD/sh_off.txt" \
    && ok "and even then both paths compute the same" \
    || bad "without SHA-NI the round-trip check deviates"

grep -q 'shani: have=0  used=0' "$TMPD/sh_q.txt" \
    && ok "FALLBACK REALLY DRIVEN: -cpu qemu64 has no SHA-NI (have=0), no #UD" \
    || bad "on -cpu qemu64 the finding does not match: $(grep -o 'shani: .*' "$TMPD/sh_q.txt" | head -1)"
grep -q 'kernel: done' "$TMPD/sh_q.txt" \
    && ok "and the kernel runs through to the end there" \
    || bad "the kernel dies on a CPU without SHA-NI"
grep -q 'auf=1' "$TMPD/sh_q.txt" \
    && ok "and opens the disk there too" \
    || bad "without SHA-NI the disk does not open"

echo "== 7. the speed, serial against parallel, on the SAME machine =="

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
        && ok "the parallel path is at least factor 1.5 faster (measured: $((fak/100)),$(printf '%02d' $((fak%100))))" \
        || bad "the gain is too small: factor $((fak/100)),$(printf '%02d' $((fak%100)))"
    [[ ${kp:-0} -ge 2 ]] \
        && ok "and the lanes really compute on several cores (cores=$kp)" \
        || bad "cores=$kp -- with the default parameters everything runs on one core"
else
    bad "keine Taktzahlen gemessen (ts=$ts tp=$tp)"
fi

echo "== 8. die Nachbarn =="

if [[ $SCHNELL == 1 ]]; then
    info "OSUM_ARGON_SCHNELL=1 -- the neighbour acceptances skipped"
else
    if bash tools/krypto/run.sh >"$TMPD/kr.txt" 2>&1; then
        z=$(grep -oE 'KRYPTO: [0-9]+ bestanden, [0-9]+ gescheitert' "$TMPD/kr.txt" | tail -1)
        info "$z"
        echo "$z" | grep -q ', 0 gescheitert' \
            && ok "the acceptance of round KRYPTO is still green ($z)" \
            || bad "KRYPTO ist rot: $z"
    else
        bad "tools/krypto/run.sh scheitert"
        tail -5 "$TMPD/kr.txt"
    fi
    if bash tools/aesni/run.sh >"$TMPD/ae.txt" 2>&1; then
        z=$(grep -oE 'AESNI: [0-9]+ bestanden, [0-9]+ gescheitert' "$TMPD/ae.txt" | tail -1)
        info "$z"
        echo "$z" | grep -q ', 0 gescheitert' \
            && ok "the acceptance of round AESNI is still green ($z)" \
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
