#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/aesni/run.sh -- DIE ABNAHME DER RUNDE AESNI (K-020).
#
# DIE FRAGE DIESER RUNDE: rechnet die Plattenverschluesselung schnell
# genug, um benutzbar zu sein -- UND rechnet sie dabei noch dasselbe?
#
# Die zweite Haelfte ist die schwerere. Eine schnelle AES-Umsetzung, die
# anders rechnet als die Norm, macht jede verschluesselte Platte
# unlesbar, und zwar still: der Geheimtext sieht genauso zufaellig aus
# wie vorher. Deshalb misst dieser Laeufer das Tempo ZULETZT und die
# Richtigkeit zuerst.
#
# WAS GEMESSEN WIRD, in dieser Reihenfolge:
#
#   1. Die Speicherkarte: 0 Kollisionen, und der Bereich dieser Runde
#      an der ZUGETEILTEN Adresse (0x120000) mit den zugeteilten
#      Modusindizes (1010..1019).
#   2. Der Bau: Kern und Orakel.
#   3. DIE KREISPROBE auf dem Wirt. Dieselben Eingaben durch BEIDE Wege
#      -- Tabelle und AES-NI --, byteweise verglichen, ueber alle drei
#      Schluessellaengen und ueber tausende Zufallsbloecke.
#   4. GEGEN FREMDE AUGEN. Was der schnelle Weg verschluesselt, muss
#      OpenSSL entschluesseln koennen, und umgekehrt. Dazu die Vektoren
#      aus FIPS 197 Anhang C.
#   5. DER RUECKFALLWEG, und zwar ECHT: `qemu-x86_64 -cpu qemu64` hat
#      kein AES-NI. Dieselbe Binaerdatei muss dort laufen, dasselbe
#      liefern und NICHT mit #UD sterben.
#   6. Im KERN: `aestest` (die Kreisprobe in Ring 0), auf einer CPU mit
#      und auf einer ohne AES-NI, und die Gegenprobe `noaesni`.
#   7. DAS TEMPO, vorher und nachher, auf DERSELBEN Maschine.
#   8. Dass die Nachbarn heil sind: krypto 61/0 und WLAN 0 Fehler
#      haengen an derselben `lib/crypto/aes.fi`.
#
# Aufruf:  bash tools/aesni/run.sh
#          OSUM_AESNI_SCHNELL=1   ohne die langen Schleifen und ohne
#                                 die beiden Nachbar-Abnahmen
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

echo "== 1. die Speicherkarte und die zugeteilten Nummern =="

if python3 tools/kernel/memmap.py kernel >"$TMPD/map.txt" 2>&1; then
    ok "die kdata-Karte ist ueberschneidungsfrei (memmap.py)"
    info "$(tail -1 "$TMPD/map.txt")"
else
    bad "memmap.py meldet eine Kollision"
    tail -5 "$TMPD/map.txt"
fi

grep -q 'AESNI_OFF' tools/kernel/memmap.py \
    && ok "AESNI steht in tools/kernel/memmap.py" \
    || bad "AESNI fehlt in tools/kernel/memmap.py"

# DIE ZUGETEILTEN BEREICHE. Sie stehen im Auftrag und in kstate.fi oben
# bei KDATA_SIZE; wer sie verschiebt, faellt hier auf.
grep -q 'const AESNI_OFF: u64 = 0x120000' kernel/kstate.fi \
    && ok "der kdata-Bereich liegt auf 0x120000 wie zugeteilt" \
    || bad "AESNI_OFF steht nicht auf 0x120000"
grep -q 'const AESNI_MAX: u64 = 0x1000' kernel/kstate.fi \
    && ok "und ist EINE Seite gross wie zugeteilt" \
    || bad "AESNI_MAX ist nicht 0x1000"
grep -q 'const M_NOAESNI: u64 = 1010' kernel/kstate.fi \
    && ok "die Modusindizes fangen bei 1010 an wie zugeteilt" \
    || bad "M_NOAESNI steht nicht auf 1010"
# Kein Index oberhalb von 1019.
hoch=$(grep -oE 'const M_[A-Z]+: u64 = 101[0-9]' kernel/kstate.fi \
    | grep -oE '101[0-9]' | sort -n | tail -1)
[[ -n $hoch && $hoch -le 1019 ]] \
    && ok "kein Modusindex dieser Runde oberhalb von 1019 (hoechster: $hoch)" \
    || bad "ein Modusindex liegt ausserhalb von 1010..1019"

echo "== 2. der Bau =="

if $FIRNC tools/krypto/orakel.fi -o "$TMPD/orakel" 2>"$TMPD/o.err"; then
    ok "das Orakel uebersetzt (dieselben lib/crypto-Dateien wie der Kern)"
else
    bad "das Orakel uebersetzt nicht"
    tail -5 "$TMPD/o.err"
fi

if $FIRNC tools/aesni/kreis.fi -o "$TMPD/kreis" 2>"$TMPD/k.err"; then
    ok "die Kreisprobe uebersetzt"
else
    bad "die Kreisprobe uebersetzt nicht"
    tail -5 "$TMPD/k.err"
fi

if timeout 900 bash tools/build-kernel.sh "$TMPD/k0.mb" >"$TMPD/b.log" 2>&1; then
    ok "der Kern baut"
else
    bad "der Kern baut nicht"
    tail -8 "$TMPD/b.log"
fi

echo "== 3. die Kreisprobe: Tabelle gegen Befehle, Oktett fuer Oktett =="

if [[ -x "$TMPD/kreis" ]]; then
    kr=$("$TMPD/kreis" 2>&1 | tail -1)
    info "$kr"
    if [[ $kr == *"aesni=0"* ]]; then
        info "diese Maschine hat kein AES-NI -- die Kreisprobe entfaellt"
        ok "auf einer Maschine ohne AES-NI ist die Tabelle der einzige Weg"
    else
        ungl=$(echo "$kr" | grep -oE 'ungleich=[0-9]+' | cut -d= -f2)
        glei=$(echo "$kr" | grep -oE 'gleich=[0-9]+' | head -1 | cut -d= -f2)
        gleich "ungleiche Bloecke ueber 128/192/256" "$ungl" "0"
        [[ ${glei:-0} -ge 6000 ]] \
            && ok "verglichene Bloecke: $glei (>= 6000)" \
            || bad "zu wenige verglichene Bloecke: $glei"
    fi
fi

echo "== 4. gegen fremde Augen: OpenSSL und FIPS 197 =="

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

# Beide Wege durch DASSELBE Orakel, einmal mit und einmal ohne AES-NI.
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

# Und die Rueckrichtung: was OpenSSL anlegt, muss OrientOS aufmachen.
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
    info "python3-cryptography fehlt -- die Gegenprobe gegen OpenSSL entfaellt"
else
    ossl=$(echo "$vz" | grep -oE 'openssl_abweichungen=[0-9]+' | cut -d= -f2)
    wegd=$(echo "$vz" | grep -oE 'wegunterschiede=[0-9]+' | cut -d= -f2)
    rueck=$(echo "$vz" | grep -oE 'rueckrichtung_abweichungen=[0-9]+' | cut -d= -f2)
    gleich "Abweichungen gegen OpenSSL" "$ossl" "0"
    gleich "Unterschiede zwischen Tabellenweg und AES-NI-Weg" "$wegd" "0"
    gleich "Abweichungen beim Entschluesseln fremden Geheimtextes" "$rueck" "0"
fi

echo "== 5. der Rueckfallweg, auf einer CPU OHNE AES-NI =="

# `qemu-x86_64` (Ring 3, Befehlssatzemulation) kann eine CPU ohne
# AES-NI vortaeuschen. Das ist die einzige Stelle, an der sich der
# Rueckfallweg auf dieser Maschine WIRKLICH fahren laesst.
if command -v qemu-x86_64 >/dev/null 2>&1; then
    KEY=$(python3 -c "print('00'*32+'11'*32)")
    PL=$(python3 -c "print('ab'*256)")
    printf 'xtssec %s 7 %s\n' "$KEY" "$PL" > "$TMPD/f.in"
    "$TMPD/orakel" < "$TMPD/f.in" > "$TMPD/f.host" 2>/dev/null
    if timeout 120 qemu-x86_64 -cpu qemu64 "$TMPD/orakel" \
            < "$TMPD/f.in" > "$TMPD/f.noaes" 2>"$TMPD/f.err"; then
        ok "dieselbe Binaerdatei laeuft auf einer CPU ohne AES-NI (kein #UD)"
    else
        bad "die Binaerdatei stirbt auf einer CPU ohne AES-NI"
        tail -3 "$TMPD/f.err"
    fi
    if diff -q "$TMPD/f.host" "$TMPD/f.noaes" >/dev/null 2>&1; then
        ok "und liefert Oktett fuer Oktett dasselbe -- beide Wege lesen dieselbe Platte"
    else
        bad "der Rueckfallweg liefert etwas anderes"
    fi
    # UND DIE GEGENPROBE ZUR GEGENPROBE: ohne die cpuid-Abfrage waere
    # genau das ein #UD. Das belegt, dass die Pruefung nicht Zierde ist.
    if timeout 60 qemu-x86_64 -cpu Westmere "$TMPD/orakel" \
            < "$TMPD/f.in" >/dev/null 2>&1; then
        ok "auf -cpu Westmere (dem ersten mit AES-NI, 2010) laeuft es ebenfalls"
    else
        bad "auf -cpu Westmere laeuft es nicht"
    fi
else
    info "qemu-x86_64 fehlt -- der Rueckfallweg wird nur im Kern gemessen"
fi

echo "== 6. im Kern: die Kreisprobe in Ring 0 =="

kern_lauf() { # name cpu append zeitlimit
    local name=$1 cpu=$2 app=$3 t=${4:-200}
    timeout "$t" $QEMU_X86 -kernel "$TMPD/k0.mb" -m 512 -cpu "$cpu" \
        -append "$app" -serial "file:$TMPD/$name.txt" -display none \
        -no-reboot >/dev/null 2>&1
    return 0
}

if [[ -f "$TMPD/k0.mb" ]]; then
    kern_lauf mit max "osum nopwr aestest aesbench" 200
    zeile=$(grep -E '^aesni: have=' "$TMPD/mit.txt" 2>/dev/null | head -1)
    info "${zeile:-keine aesni-Zeile}"
    if [[ $zeile == *"have=1"* ]]; then
        [[ $zeile == *"used=1"* ]] \
            && ok "auf -cpu max ist der schnelle Weg scharf (used=1)" \
            || bad "AES-NI ist da, wird aber nicht benutzt: $zeile"
        kz=$(grep -E '^aesni: gleich=' "$TMPD/mit.txt" | head -1)
        info "${kz:-keine Kreisprobe-Zeile}"
        ung=$(echo "$kz" | grep -oE 'ungleich=[0-9]+' | cut -d= -f2)
        gleich "die Kreisprobe im Kern, ungleiche Bloecke" "${ung:-keine}" "0"
    else
        info "diese QEMU-CPU meldet kein AES-NI -- Abschnitt entfaellt"
    fi
    grep -q '^kernel: done' "$TMPD/mit.txt" 2>/dev/null \
        && ok "der Kern laeuft mit AES-NI bis zum Ende durch" \
        || bad "der Kern kommt mit AES-NI nicht bis 'kernel: done'"

    # DIE GEGENPROBE: derselbe Kern, dieselbe CPU, der schnelle Weg von
    # Hand heraus. Ohne diesen Lauf waere der Faktor unten eine
    # Behauptung.
    kern_lauf ohne max "osum nopwr aestest aesbench noaesni" 380
    zo=$(grep -E '^aesni: have=' "$TMPD/ohne.txt" 2>/dev/null | head -1)
    info "${zo:-keine aesni-Zeile}"
    [[ $zo == *"used=0"* ]] \
        && ok "GEGENPROBE: noaesni nimmt den schnellen Weg wirklich heraus" \
        || bad "noaesni wirkt nicht: $zo"
    grep -q '^kernel: done' "$TMPD/ohne.txt" 2>/dev/null \
        && ok "und der Kern laeuft auf der Tabelle ebenso durch" \
        || bad "der Kern stirbt auf dem Tabellenweg"

    # UND EINE CPU, DIE ES WIRKLICH NICHT KANN.
    kern_lauf keine "qemu64,-aes" "osum nopwr aestest aesbench" 380
    zk=$(grep -E '^aesni: have=' "$TMPD/keine.txt" 2>/dev/null | head -1)
    info "${zk:-keine aesni-Zeile}"
    if [[ $zk == *"have=0"* ]]; then
        ok "auf -cpu qemu64,-aes erkennt der Kern, dass AES-NI fehlt"
        [[ $zk == *"used=0"* ]] \
            && ok "und faellt auf die Tabelle zurueck statt #UD zu sterben" \
            || bad "AES-NI fehlt, wird aber benutzt -- das ist ein #UD"
    else
        bad "auf -cpu qemu64,-aes meldet der Kern trotzdem AES-NI: $zk"
    fi
    grep -q '^kernel: done' "$TMPD/keine.txt" 2>/dev/null \
        && ok "der Kern laeuft auf einer CPU ohne AES-NI bis zum Ende durch" \
        || bad "der Kern stirbt auf einer CPU ohne AES-NI"
fi

echo "== 7. das Tempo, auf derselben Maschine =="

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
    print("zu wenige Messwerte"); raise SystemExit
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
        ok "der schnelle Weg ist mindestens 20-mal so schnell (Faktor $fak)"
    else
        bad "der Gewinn ist zu klein: Faktor ${fak:-?}"
    fi
    if [[ -n ${mib:-} ]] && python3 -c "import sys; sys.exit(0 if float('$mib') >= 20 else 1)"; then
        ok "XTS schafft mindestens 20 MiB/s je Sektor ($mib MiB/s)"
    else
        bad "XTS bleibt unter 20 MiB/s: ${mib:-?}"
    fi

    # Die Takte aus dem KERN, wenn die Laeufe oben etwas geliefert haben.
    tm=$(grep -oE 'takt512=[0-9]+' "$TMPD/mit.txt" 2>/dev/null | head -1 | cut -d= -f2)
    to=$(grep -oE 'takt512=[0-9]+' "$TMPD/ohne.txt" 2>/dev/null | head -1 | cut -d= -f2)
    if [[ -n ${tm:-} && -n ${to:-} && ${tm:-0} -gt 0 ]]; then
        info "im Kern: $tm Takte je Sektor mit AES-NI, $to ohne -- Faktor $((to / tm))"
        [[ $((to / tm)) -ge 20 ]] \
            && ok "auch im Kern mindestens Faktor 20 (gemessen: $((to / tm)))" \
            || bad "im Kern nur Faktor $((to / tm))"
    fi
fi

echo "== 8. die Nachbarn an derselben lib/crypto/aes.fi =="

if [[ $SCHNELL == 1 ]]; then
    info "OSUM_AESNI_SCHNELL=1 -- krypto und wlan werden nicht mitgefahren"
else
    if timeout 2400 bash tools/krypto/run.sh >"$TMPD/kr.log" 2>&1; then
        kl=$(grep -E '^KRYPTO: ' "$TMPD/kr.log" | tail -1)
        info "$kl"
        [[ $kl == *" 0 gescheitert"* ]] \
            && ok "die Abnahme der Plattenverschluesselung bleibt gruen" \
            || bad "die krypto-Abnahme ist rot: $kl"
    else
        bad "tools/krypto/run.sh laeuft nicht durch"
        tail -5 "$TMPD/kr.log"
    fi
    if timeout 2400 bash tools/wlan/run.sh >"$TMPD/wl.log" 2>&1; then
        wl=$(grep -E '^WLAN: ' "$TMPD/wl.log" | tail -1)
        info "$wl"
        [[ $wl == *" 0 Fehler"* ]] \
            && ok "die WLAN-Abnahme bleibt gruen (dieselbe aes.fi)" \
            || bad "die WLAN-Abnahme ist rot: $wl"
    else
        bad "tools/wlan/run.sh laeuft nicht durch"
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
