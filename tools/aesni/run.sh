#!/usr/bin/env bash
#
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
SCHNELL=${OSUM_AESNI_SCHNELL:-0}

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
info(){ printf '        %s\n' "$1"; }

gleich() { # name ist soll
    if [[ "$2" == "$3" ]]; then ok "$1: $2"; else bad "$1: $2 -- erwartet $3"; fi
}

echo "== 1. the memory map and the assigned numbers =="

if python3 tools/kernel/memmap.py kernel >"$TMPD/map.txt" 2>&1; then
    ok "the kdata map is overlap-free (memmap.py)"
    info "$(tail -1 "$TMPD/map.txt")"
else
    bad "memmap.py meldet eine Kollision"
    tail -5 "$TMPD/map.txt"
fi

grep -q 'AESNI_OFF' tools/kernel/memmap.py \
    && ok "AESNI steht in tools/kernel/memmap.py" \
    || bad "AESNI fehlt in tools/kernel/memmap.py"

grep -q 'const AESNI_OFF: u64 = 0x120000' kernel/lib/kstate.fi \
    && ok "the kdata range is at 0x120000 as assigned" \
    || bad "AESNI_OFF is not at 0x120000"
grep -q 'const AESNI_MAX: u64 = 0x1000' kernel/lib/kstate.fi \
    && ok "and is ONE page in size as assigned" \
    || bad "AESNI_MAX is not 0x1000"
grep -q 'const M_NOAESNI: u64 = 1010' kernel/lib/kstate.fi \
    && ok "the mode indices start at 1010 as assigned" \
    || bad "M_NOAESNI is not at 1010"
hoch=$(grep -oE 'const M_[A-Z]+: u64 = 101[0-9]' kernel/lib/kstate.fi \
    | grep -oE '101[0-9]' | sort -n | tail -1)
[[ -n $hoch && $hoch -le 1019 ]] \
    && ok "no mode index of this round above 1019 (highest: $hoch)" \
    || bad "a mode index is outside 1010..1019"

echo "== 2. der Bau =="

if $FIRNC tools/krypto/orakel.fi -o "$TMPD/orakel" 2>"$TMPD/o.err"; then
    ok "the oracle compiles (the same lib/crypto files as the kernel)"
else
    bad "the oracle does not compile"
    tail -5 "$TMPD/o.err"
fi

if $FIRNC tools/aesni/kreis.fi -o "$TMPD/kreis" 2>"$TMPD/k.err"; then
    ok "die Kreisprobe uebersetzt"
else
    bad "the round-trip check does not compile"
    tail -5 "$TMPD/k.err"
fi

if timeout 900 bash tools/build-kernel.sh "$TMPD/k0.mb" >"$TMPD/b.log" 2>&1; then
    ok "der Kern baut"
else
    bad "the kernel does not build"
    tail -8 "$TMPD/b.log"
fi

echo "== 3. the round-trip check: table against instructions, octet for octet =="

if [[ -x "$TMPD/kreis" ]]; then
    kr=$("$TMPD/kreis" 2>&1 | tail -1)
    info "$kr"
    if [[ $kr == *"aesni=0"* ]]; then
        bad "this machine has no AES-NI: the round-trip check cannot run (no skip allowed)"
    else
        ungl=$(echo "$kr" | grep -oE 'ungleich=[0-9]+' | cut -d= -f2)
        glei=$(echo "$kr" | grep -oE 'gleich=[0-9]+' | head -1 | cut -d= -f2)
        gleich "ungleiche Bloecke ueber 128/192/256" "$ungl" "0"
        [[ ${glei:-0} -ge 6000 ]] \
            && ok "verglichene Bloecke: $glei (>= 6000)" \
            || bad "zu wenige verglichene Bloecke: $glei"
    fi
fi

echo "== 4. against foreign eyes: OpenSSL and FIPS 197 =="

python3 - "$TMPD" <<'PY' >"$TMPD/vek.txt" 2>&1
import os, random, subprocess, sys
tmp = sys.argv[1]
try:
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
except ImportError:
    print("SKIP cryptography fehlt"); raise SystemExit

random.seed(20260915)
n = 60 if os.environ.get("OSUM_AESNI_SCHNELL") == "1" else 300
faelle = []
for i in range(n):
    key = os.urandom(32) + os.urandom(32)
    if key[:32] == key[32:]:
        continue
    ln = random.choice([16, 32, 512, 4096])
    pt = os.urandom(ln)
    sek = random.randrange(0, 2**40)
    faelle.append((key, sek, pt))

def lauf(vorspann):
    ein = []
    if vorspann:
        ein.append(vorspann)
    for key, sek, pt in faelle:
        ein.append("xtssec %s %d %s" % (key.hex(), sek, pt.hex()))
    p = subprocess.run([tmp + "/orakel"], input="\n".join(ein) + "\n",
                       capture_output=True, text=True)
    zeilen = [z for z in p.stdout.strip().split("\n") if z and z != "ok"]
    return zeilen

schnell = lauf(None)
tabelle = lauf("noaesni")

bad_ossl = 0
for (key, sek, pt), got in zip(faelle, schnell):
    c = Cipher(algorithms.AES(key), modes.XTS(sek.to_bytes(16, "little"))).encryptor()
    if (c.update(pt) + c.finalize()).hex() != got:
        bad_ossl += 1
bad_weg = sum(1 for a, b in zip(schnell, tabelle) if a != b)

print("faelle=%d openssl_abweichungen=%d wegunterschiede=%d"
      % (len(faelle), bad_ossl, bad_weg))

ein = []
erw = []
for key, sek, pt in faelle[:40]:
    c = Cipher(algorithms.AES(key), modes.XTS(sek.to_bytes(16, "little"))).encryptor()
    ct = c.update(pt) + c.finalize()
    ein.append("xtssecd %s %d %s" % (key.hex(), sek, ct.hex()))
    erw.append(pt.hex())
p = subprocess.run([tmp + "/orakel"], input="\n".join(ein) + "\n",
                   capture_output=True, text=True)
got = [z for z in p.stdout.strip().split("\n") if z]
zurueck = sum(1 for a, b in zip(erw, got) if a != b)
print("rueckrichtung_abweichungen=%d von=%d" % (zurueck, len(erw)))
PY

vz=$(cat "$TMPD/vek.txt")
info "$vz"
if [[ $vz == *"SKIP"* ]]; then
    bad "python3-cryptography is missing: the control against OpenSSL cannot run (no skip allowed)"
else
    ossl=$(echo "$vz" | grep -oE 'openssl_abweichungen=[0-9]+' | cut -d= -f2)
    wegd=$(echo "$vz" | grep -oE 'wegunterschiede=[0-9]+' | cut -d= -f2)
    rueck=$(echo "$vz" | grep -oE 'rueckrichtung_abweichungen=[0-9]+' | cut -d= -f2)
    gleich "Abweichungen gegen OpenSSL" "$ossl" "0"
    gleich "Unterschiede zwischen Tabellenweg und AES-NI-Weg" "$wegd" "0"
    gleich "Abweichungen beim Entschluesseln fremden Geheimtextes" "$rueck" "0"
fi

echo "== 5. the fallback, on a CPU WITHOUT AES-NI =="

if command -v qemu-x86_64 >/dev/null 2>&1; then
    KEY=$(python3 -c "print('00'*32+'11'*32)")
    PL=$(python3 -c "print('ab'*256)")
    printf 'xtssec %s 7 %s\n' "$KEY" "$PL" > "$TMPD/f.in"
    "$TMPD/orakel" < "$TMPD/f.in" > "$TMPD/f.host" 2>/dev/null
    if timeout 120 qemu-x86_64 -cpu qemu64 "$TMPD/orakel" \
            < "$TMPD/f.in" > "$TMPD/f.noaes" 2>"$TMPD/f.err"; then
        ok "the same binary runs on a CPU without AES-NI (no #UD)"
    else
        bad "the binary dies on a CPU without AES-NI"
        tail -3 "$TMPD/f.err"
    fi
    if diff -q "$TMPD/f.host" "$TMPD/f.noaes" >/dev/null 2>&1; then
        ok "and yields the same octet for octet -- both ways read the same disk"
    else
        bad "der Rueckfallweg liefert etwas anderes"
    fi
    if timeout 60 qemu-x86_64 -cpu Westmere "$TMPD/orakel" \
            < "$TMPD/f.in" >/dev/null 2>&1; then
        ok "on -cpu Westmere (the first with AES-NI, 2010) it runs as well"
    else
        bad "on -cpu Westmere it does not run"
    fi
else
    info "qemu-x86_64 is missing -- the fallback is only measured in the kernel"
fi

echo "== 6. in the kernel: the round-trip check in ring 0 =="

kern_lauf() { # name cpu append zeitlimit
    local name=$1 cpu=$2 app=$3 t=${4:-200}
    timeout "$t" $QEMU_X86 -kernel "$TMPD/k0.mb" -m 512 -cpu "$cpu" \
        -append "$app" -serial "file:$TMPD/$name.txt" -display none \
        -no-reboot -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        >/dev/null 2>&1
    return 0
}

if [[ -f "$TMPD/k0.mb" ]]; then
    kern_lauf mit max "osum nopwr aestest aesbench" 200
    zeile=$(grep -E '^aesni: have=' "$TMPD/mit.txt" 2>/dev/null | head -1)
    info "${zeile:-no aesni line}"
    if [[ $zeile == *"have=1"* ]]; then
        [[ $zeile == *"used=1"* ]] \
            && ok "on -cpu max the fast path is armed (used=1)" \
            || bad "AES-NI is there but not used: $zeile"
        kz=$(grep -E '^aesni: gleich=' "$TMPD/mit.txt" | head -1)
        info "${kz:-no round-trip line}"
        ung=$(echo "$kz" | grep -oE 'ungleich=[0-9]+' | cut -d= -f2)
        gleich "die Kreisprobe im Kern, ungleiche Bloecke" "${ung:-keine}" "0"
    else
        bad "-cpu max reports no AES-NI: the in-kernel round-trip cannot run (no skip allowed)"
    fi
    grep -q '^kernel: done' "$TMPD/mit.txt" 2>/dev/null \
        && ok "the kernel runs through to the end with AES-NI" \
        || bad "the kernel does not reach the end with AES-NI: 'kernel: done'"

    kern_lauf ohne max "osum nopwr aestest aesbench noaesni" 380
    zo=$(grep -E '^aesni: have=' "$TMPD/ohne.txt" 2>/dev/null | head -1)
    info "${zo:-no aesni line}"
    [[ $zo == *"used=0"* ]] \
        && ok "CONTROL: noaesni really takes the fast path out" \
        || bad "noaesni wirkt nicht: $zo"
    grep -q '^kernel: done' "$TMPD/ohne.txt" 2>/dev/null \
        && ok "and the kernel runs through on the table likewise" \
        || bad "the kernel dies on the table path"

    kern_lauf keine "qemu64,-aes" "osum nopwr aestest aesbench" 380
    zk=$(grep -E '^aesni: have=' "$TMPD/keine.txt" 2>/dev/null | head -1)
    info "${zk:-no aesni line}"
    if [[ $zk == *"have=0"* ]]; then
        ok "on -cpu qemu64,-aes the kernel detects that AES-NI is missing"
        [[ $zk == *"used=0"* ]] \
            && ok "and falls back to the table instead of dying with #UD" \
            || bad "AES-NI is missing but is used -- that is a #UD"
    else
        bad "on -cpu qemu64,-aes the kernel reports AES-NI anyway: $zk"
    fi
    grep -q '^kernel: done' "$TMPD/keine.txt" 2>/dev/null \
        && ok "the kernel runs through to the end on a CPU without AES-NI" \
        || bad "the kernel dies on a CPU without AES-NI"
fi

echo "== 7. the speed, on the same machine =="

if [[ -x "$TMPD/orakel" ]]; then
    KEY=$(python3 -c "print('00'*32+'11'*32)")
    {
        echo "xtsbench $KEY 512 2000"
        echo "xtsbench $KEY 4096 300"
        echo "noaesni"
        echo "xtsbench $KEY 512 150"
        echo "xtsbench $KEY 4096 30"
    } > "$TMPD/t.in"
    "$TMPD/orakel" < "$TMPD/t.in" > "$TMPD/t.out" 2>/dev/null
    python3 - "$TMPD/t.out" <<'PY' > "$TMPD/t.txt"
import sys
v = [int(x) for x in open(sys.argv[1]).read().split() if x != "ok"]
if len(v) < 4:
    print("too few measurements"); raise SystemExit
def mibs(ns, n): return n / (ns / 1e9) / 1048576
print("512 B : AES-NI %8.2f us (%7.2f MiB/s)  Tabelle %9.2f us (%5.2f MiB/s)  Faktor %.0f"
      % (v[0]/1000, mibs(v[0], 512), v[2]/1000, mibs(v[2], 512), v[2]/v[0]))
print("4096 B: AES-NI %8.2f us (%7.2f MiB/s)  Tabelle %9.2f us (%5.2f MiB/s)  Faktor %.0f"
      % (v[1]/1000, mibs(v[1], 4096), v[3]/1000, mibs(v[3], 4096), v[3]/v[1]))
print("FAKTOR512 %.0f" % (v[2]/v[0]))
print("MIBS512 %.2f" % mibs(v[0], 512))
PY
    while IFS= read -r z; do
        [[ $z == FAKTOR512* || $z == MIBS512* ]] && continue
        info "$z"
    done < "$TMPD/t.txt"
    fak=$(grep -oE '^FAKTOR512 [0-9]+' "$TMPD/t.txt" | awk '{print $2}')
    mib=$(grep -oE '^MIBS512 [0-9.]+' "$TMPD/t.txt" | awk '{print $2}')
    if [[ -n ${fak:-} ]] && [[ $fak -ge 20 ]]; then
        ok "the fast path is at least 20 times as fast (factor $fak)"
    else
        bad "the gain is too small: factor ${fak:-?}"
    fi
    if [[ -n ${mib:-} ]] && python3 -c "import sys; sys.exit(0 if float('$mib') >= 20 else 1)"; then
        ok "XTS schafft mindestens 20 MiB/s je Sektor ($mib MiB/s)"
    else
        bad "XTS stays below 20 MiB/s: ${mib:-?}"
    fi

    tm=$(grep -oE 'takt512=[0-9]+' "$TMPD/mit.txt" 2>/dev/null | head -1 | cut -d= -f2)
    to=$(grep -oE 'takt512=[0-9]+' "$TMPD/ohne.txt" 2>/dev/null | head -1 | cut -d= -f2)
    if [[ -n ${tm:-} && -n ${to:-} && ${tm:-0} -gt 0 ]]; then
        info "in the kernel: $tm cycles per sector with AES-NI, $to without -- factor $((to / tm))"
        [[ $((to / tm)) -ge 20 ]] \
            && ok "in the kernel also at least factor 20 (measured: $((to / tm)))" \
            || bad "in the kernel only factor $((to / tm))"
    fi
fi

echo "== 8. die Nachbarn an derselben lib/crypto/aes.fi =="

if [[ $SCHNELL == 1 ]]; then
    info "OSUM_AESNI_SCHNELL=1 -- crypto and wlan are not run along"
else
    if timeout 2400 bash tools/krypto/run.sh >"$TMPD/kr.log" 2>&1; then
        kl=$(grep -E '^KRYPTO: ' "$TMPD/kr.log" | tail -1)
        info "$kl"
        [[ $kl == *" 0 gescheitert"* ]] \
            && ok "the disk encryption acceptance stays green" \
            || bad "the crypto acceptance is red: $kl"
    else
        bad "tools/krypto/run.sh does not run through"
        tail -5 "$TMPD/kr.log"
    fi
    if timeout 2400 bash tools/wlan/run.sh >"$TMPD/wl.log" 2>&1; then
        wl=$(grep -E '^WLAN: ' "$TMPD/wl.log" | tail -1)
        info "$wl"
        [[ $wl == *" 0 Fehler"* ]] \
            && ok "the WLAN acceptance stays green (the same aes.fi)" \
            || bad "the WLAN acceptance is red: $wl"
    else
        bad "tools/wlan/run.sh does not run through"
        tail -5 "$TMPD/wl.log"
    fi
fi

echo "== 9. die Oberflaeche =="
if timeout 300 bash tools/check-ui.sh >"$TMPD/ui.log" 2>&1; then
    ok "check-ui.sh PASSED"
else
    bad "check-ui.sh faellt"
    tail -5 "$TMPD/ui.log"
fi

echo
echo "AESNI: $pass bestanden, $fail gescheitert"
[[ $fail -eq 0 ]]
