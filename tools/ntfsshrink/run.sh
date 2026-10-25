#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
FIRNC=vendor/firn/bin/firnc
for t in mkntfs ntfsinfo ntfscat ntfscp ntfsresize ntfsfix; do
    command -v "$t" >/dev/null 2>&1 || { echo "NTFSSHRINK: $t missing"; exit 1; }
done

mkimg() {
    python3 -I - "$1" "$2" <<'PY'
import sys
f = open(sys.argv[1], 'wb'); f.seek(int(sys.argv[2]) * 1048576 - 1); f.write(b'\0'); f.close()
PY
}

echo "== 1. lib/ntfsshrink on real mkntfs images =="
if "$FIRNC" -o "$D/unit" tools/ntfsshrink/unit.fi > "$D/cc.log" 2>&1; then
    ok "lib/ntfsshrink builds with tools/ntfsshrink/unit.fi"
else
    bad "unit.fi does not build"; head -20 "$D/cc.log" | sed 's/^/        /'
    echo "NTFSSHRINK: $pass passed, $fail failed"; exit 1
fi

mkdir -p "$D/src"
head -c 1500000 /dev/urandom > "$D/src/big.bin"
head -c 700 /dev/urandom > "$D/src/small.bin"
for i in $(seq 1 120); do head -c $((i * 37)) /dev/urandom > "$D/src/f$i.dat"; done

mkvariant() {
    local name=$1 mib=$2 cs=$3 ss=$4 files=$5
    mkimg "$D/$name.img" "$mib"
    mkntfs -F -q -s "$ss" -c "$cs" "$D/$name.img" >/dev/null 2>&1 || { bad "mkntfs $name"; return 1; }
    if [ "$files" = 1 ]; then
        ntfscp -f "$D/$name.img" "$D/src/big.bin" /big.bin >/dev/null 2>&1
        ntfscp -f "$D/$name.img" "$D/src/small.bin" /small.bin >/dev/null 2>&1
    fi
    if [ "$files" = 2 ]; then
        for i in $(seq 1 120); do ntfscp -f "$D/$name.img" "$D/src/f$i.dat" "/f$i.dat" >/dev/null 2>&1; done
    fi
}

verify() {
    local name=$1
    ( cd "$D" && "$D/unit" "$D/$name.img" info x > "$D/$name.out" 2>&1 )
    if res=$(python3 -I tools/ntfsshrink/check.py "$D/$name.img" "$D/$name.out" 2>&1); then
        ok "$name: geometry, records, mirror, bitmap end, \$Bad match ntfsinfo/ntfscat ($(grep -a '^used_end' "$D/$name.out"))"
    else
        bad "$name: $(echo "$res" | tr '\n' ';')"
    fi
}

mkvariant a 64 4096 512 0 && verify a
mkvariant b 48 512 512 1 && verify b
mkvariant c 96 65536 512 1 && verify c
mkvariant d 40 4096 512 2 && verify d
grep -aq 'used_end=' "$D/b.out" && ok "b: file data pushes the used end past the metadata ($(grep -a '^used_end' "$D/b.out"), a: $(grep -a '^used_end' "$D/a.out"))"

echo "== 2. runlist decoder =="
python3 -I tools/ntfsshrink/rltest.py "$D" "$FIRNC" > "$D/rl.out" 2>&1 && ok "$(tail -1 "$D/rl.out")" || { bad "runlist decoder"; tail -8 "$D/rl.out" | sed 's/^/        /'; }

echo "== 3. refused volumes =="
refuse() {
    local name=$1 want=$2 patch=$3
    cp "$D/a.img" "$D/n.img"
    python3 -I - "$D/n.img" "$patch" <<'PY'
import sys, struct
p, kind = sys.argv[1], sys.argv[2]
f = open(p, 'r+b')
rd = lambda o, n: (f.seek(o), f.read(n))[1]
wr = lambda o, b: (f.seek(o), f.write(b))
S = struct.unpack('<Q', rd(0x28, 8))[0]
if kind == 'fve': wr(3, b'-FVE-FS-')
elif kind == 'zero': wr(0, b'\0' * 512)
elif kind == 'sig': wr(510, b'\0\0')
elif kind == 'oem': wr(3, b'EXFAT   ')
elif kind == 'altserial': wr(S * 512 + 0x48, b'\1\2\3\4\5\6\7\x08')
elif kind == 'altgone': wr(S * 512, b'\0' * 512)
elif kind == 'spc3': wr(13, b'\3')
elif kind == 'spc200': wr(13, b'\xc8')
elif kind == 'bps1024': wr(11, struct.pack('<H', 1024))
elif kind == 'bigS': wr(0x28, struct.pack('<Q', S * 4))
elif kind == 'mft0': wr(0x30, struct.pack('<Q', 0))
elif kind == 'recsz': wr(0x40, b'\xfa')
elif kind == 'usn':
    mft = struct.unpack('<Q', rd(0x30, 8))[0] * 4096
    wr(mft + 510, b'\xff\xff')
f.close()
PY
    ( cd "$D" && "$D/unit" "$D/n.img" info x > "$D/n.out" 2>&1 )
    local got
    got=$(grep -a -m1 -E '^(open|mft_load)=[1-9]' "$D/n.out" | head -1)
    if [ "$got" = "$want" ]; then ok "$name -> $got"; else bad "$name: want $want got '$got'"; fi
}
refuse "BitLocker OEM" "open=3" fve
refuse "zeroed boot sector" "open=2" zero
refuse "no boot signature" "open=2" sig
refuse "other filesystem OEM" "open=2" oem
refuse "backup boot sector differs" "open=5" altserial
refuse "backup boot sector missing" "open=5" altgone
refuse "cluster factor 3" "open=4" spc3
refuse "cluster factor 2^56" "open=4" spc200
refuse "sector size 1024" "open=4" bps1024
refuse "volume larger than partition" "open=5" bigS
refuse "MFT at cluster 0" "open=5" mft0
refuse "record size 64 bytes" "open=4" recsz
refuse "broken update sequence of record 0" "mft_load=5" usn

echo "== 4. record write touches only the changed sectors =="
cp "$D/a.img" "$D/t.img"
( cd "$D" && "$D/unit" "$D/t.img" t "$D/t.out.img" > "$D/t.out" 2>&1 )
python3 -I - "$D/a.img" "$D/t.out.img" <<'PY' > "$D/t.cmp" 2>&1
import sys
a = open(sys.argv[1], 'rb').read(); b = open(sys.argv[2], 'rb').read()
assert len(a) == len(b)
diff = [i for i in range(0, len(a), 512) if a[i:i+512] != b[i:i+512]]
print(len(diff))
PY
if [ "$(cat "$D/t.cmp")" = 2 ] && grep -aq 't_write=0' "$D/t.out" && grep -aq 't_writem=0' "$D/t.out" && grep -aq 't_sectors_written=2' "$D/t.out"; then ok "dirty flag in record 3 + mirror changes exactly 2 sectors (2 sector writes, unchanged sectors skipped)"; else bad "sector diff: $(cat "$D/t.cmp") $(grep -a '^t_' "$D/t.out" | tr '\n' ' ')"; fi
NI=$(ntfsinfo -m "$D/t.out.img" 2>&1); NF=$(ntfsfix -n "$D/t.out.img" 2>&1)
if echo "$NI" | grep -q 'scheduled for check'; then ok "ntfs-3g refuses the volume as dirty (flag written by mft_write)"; else bad "ntfs-3g does not see the dirty flag"; fi
if echo "$NF" | grep -q 'Checking the alternate boot sector... OK'; then ok "ntfsfix -n: MFT, mirror and alternate boot sector still consistent"; else bad "ntfsfix -n on the rewritten image"; fi

echo "== 5. bitmap padding against ntfsresize =="
NEWC=11999
cp "$D/a.img" "$D/r.img"
if ntfsresize -f -s $(((NEWC + 1) * 4096)) "$D/r.img" > "$D/rs.log" 2>&1; then
    ( cd "$D" && "$D/unit" "$D/a.img" pad "$NEWC" "$D/p.img" > "$D/p.out" 2>&1 )
    python3 -I tools/ntfsshrink/padcmp.py "$D/p.img" "$D/r.img" "$D/a.img" "$NEWC" > "$D/pc.out" 2>&1 && ok "$(tail -1 "$D/pc.out")" || { bad "padding"; tail -5 "$D/pc.out" | sed 's/^/        /'; }
else
    bad "ntfsresize -s failed"; tail -3 "$D/rs.log" | sed 's/^/        /'
fi

echo "NTFSSHRINK: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
