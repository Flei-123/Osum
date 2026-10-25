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

echo "== 6. pre-flight checks (dirty, journal, bad clusters, hibernation) =="
MUT="python3 -I tools/ntfsshrink/mut.py"
python3 -I - "$D/src" <<'PY'
import sys, os
d = sys.argv[1]
for name, sig, size in [('hibr_s', b'hibr', 600), ('HIBR_b', b'HIBR', 16384), ('wake_s', b'wake', 600), ('WAKE_b', b'WAKE', 16384), ('zero_b', b'\0\0\0\0', 16384), ('junk_b', b'ABCD', 16384), ('hibr_b', b'hibr', 16384), ('wake_b', b'wake', 16384)]:
    open(os.path.join(d, name + '.bin'), 'wb').write(sig + os.urandom(size - 4) if sig != b'\0\0\0\0' else b'\0' * size)
PY
chk() {
    local name=$1 img=$2 skip=$3 want=$4 got
    got=$( "$D/unit" "$img" c "$skip" 2>&1 | grep -a -m1 '^check=' )
    if [ "$got" = "check=$want" ]; then ok "$name -> check=$want"; else bad "$name: want check=$want got '$got'"; fi
}
fresh() { cp "$D/$1.img" "$D/w.img"; }
putfile() { ntfscp -f "$D/w.img" "$D/src/$1" "$2" >/dev/null 2>&1 || bad "ntfscp $2"; }

for n in a b c d; do chk "clean volume $n" "$D/$n.img" 0 0; done

for fl in 0x0001 0x0002 0x8000 0x0004; do
    fresh a; $MUT "$D/w.img" flags $fl
    chk "volume flags $fl" "$D/w.img" 0 6
done
fresh a; $MUT "$D/w.img" flags 0x0001
NI=$(ntfsinfo -m "$D/w.img" 2>&1)
if echo "$NI" | grep -q 'scheduled for check'; then ok "oracle: ntfs-3g also sees flag 0x0001 as dirty"; else bad "oracle dirty flag"; fi

fresh a; $MUT "$D/w.img" log 0 5 0 0
chk "journal: page 0 has a client in use, not clean" "$D/w.img" 0 8
fresh a; $MUT "$D/w.img" log 0 5 0 2
chk "journal: page 0 marked clean" "$D/w.img" 0 0
fresh a; $MUT "$D/w.img" log 0 5 0xFFFF 0
chk "journal: page 0 has no client in use" "$D/w.img" 0 0
fresh a; $MUT "$D/w.img" log 0 5 0 2; $MUT "$D/w.img" log 1 9 0 0
chk "journal: older page clean, newer page dirty" "$D/w.img" 0 8
fresh a; $MUT "$D/w.img" log 0 9 0 0; $MUT "$D/w.img" log 1 5 0 2
chk "journal: older page dirty, newer page clean" "$D/w.img" 0 8
fresh a; $MUT "$D/w.img" log 0 5 0 0; $MUT "$D/w.img" log 1 9 0 2
chk "journal: newest page is page 1 and clean" "$D/w.img" 0 0
fresh a; $MUT "$D/w.img" logjunk 0
chk "journal: unknown page magic" "$D/w.img" 0 8
fresh a; $MUT "$D/w.img" log 1 7 0 0
chk "journal: only page 1 valid and dirty" "$D/w.img" 0 8

for v in datarun short split long; do
    fresh a; $MUT "$D/w.img" bad $v
    chk "\$Bad variant $v" "$D/w.img" 0 13
done

hib() {
    local label=$1 base=$2 src=$3 dst=$4 want=$5
    fresh "$base"; putfile "$src" "$dst"
    chk "$label" "$D/w.img" 0 "$want"
}
hib "hiberfil.sys resident 'hibr'" a hibr_s.bin /hiberfil.sys 7
hib "hiberfil.sys nonresident 'HIBR'" a HIBR_b.bin /hiberfil.sys 7
hib "hiberfil.sys nonresident 'hibr'" a hibr_b.bin /hiberfil.sys 7
hib "hiberfil.sys unknown signature" a junk_b.bin /hiberfil.sys 7
hib "HiberFil.SYS (case) 'hibr'" a hibr_b.bin /HiberFil.SYS 7
hib "hiberfil.sys resident 'wake'" a wake_s.bin /hiberfil.sys 0
hib "hiberfil.sys nonresident 'WAKE'" a WAKE_b.bin /hiberfil.sys 0
hib "hiberfil.sys nonresident zero header" a zero_b.bin /hiberfil.sys 0
hib "hiberfil.sys.bak with 'hibr' is another file" a hibr_b.bin /hiberfil.sys.bak 0
hib "hiberfile.sys with 'hibr' is another file" a hibr_b.bin /hiberfile.sys 0
hib "120-file directory, hiberfil.sys 'hibr' in an index block" d hibr_b.bin /hiberfil.sys 7
hib "120-file directory, hiberfil.sys 'wake'" d wake_b.bin /hiberfil.sys 0
fresh a; putfile hibr_b.bin /hiberfil.sys
LS=$(ntfsls "$D/w.img" 2>/dev/null)
if echo "$LS" | grep -qx 'hiberfil.sys' && [ "$(ntfscat -f "$D/w.img" /hiberfil.sys 2>/dev/null | head -c4)" = "hibr" ]; then ok "oracle: ntfsls/ntfscat see hiberfil.sys starting with hibr"; else bad "oracle hiberfil.sys"; fi
fresh a; putfile hibr_b.bin /hiberfil.sys; $MUT "$D/w.img" seq /hiberfil.sys 77
chk "hiberfil.sys record with other sequence number is a stale entry" "$D/w.img" 0 0
fresh a; putfile hibr_b.bin /hiberfil.sys; $MUT "$D/w.img" free /hiberfil.sys
chk "hiberfil.sys record not in use is a stale entry" "$D/w.img" 0 0
fresh a; putfile hibr_b.bin /hibtarget.bin; $MUT "$D/w.img" rootentry /hibtarget.bin 0
chk "entry in INDEX_ROOT -> record with 'hibr'" "$D/w.img" 0 7
fresh a; putfile hibr_b.bin /hibtarget.bin; $MUT "$D/w.img" rootentry /hibtarget.bin 1
chk "entry in INDEX_ROOT with wrong sequence number" "$D/w.img" 0 0
fresh a; putfile wake_b.bin /hibtarget.bin; $MUT "$D/w.img" rootentry /hibtarget.bin 0
chk "entry in INDEX_ROOT -> record with 'wake'" "$D/w.img" 0 0
fresh a; putfile hibr_b.bin /hibtarget.bin; $MUT "$D/w.img" rootentry /hibtarget.bin 0; $MUT "$D/w.img" free /hibtarget.bin
chk "entry in INDEX_ROOT -> record not in use" "$D/w.img" 0 0

echo "== 7. counter-probes: a skipped check must make the gate red =="
fresh a; $MUT "$D/w.img" flags 0x0001; cp "$D/w.img" "$D/x_dirty.img"
fresh a; $MUT "$D/w.img" log 0 5 0 0; cp "$D/w.img" "$D/x_log.img"
fresh a; $MUT "$D/w.img" bad split; cp "$D/w.img" "$D/x_bad.img"
fresh a; putfile hibr_b.bin /hiberfil.sys; cp "$D/w.img" "$D/x_hib.img"
probe() {
    local name=$1 img=$2 skipbit=$3 want=$4 all=15 others got
    others=$((all - skipbit))
    got=$( "$D/unit" "$img" c "$skipbit" 2>&1 | grep -a -m1 '^check=' )
    if [ "$got" = "check=0" ]; then ok "skip $name -> defect passes (gate would turn red)"; else bad "skip $name did not hide the defect: '$got'"; fi
    got=$( "$D/unit" "$img" c "$others" 2>&1 | grep -a -m1 '^check=' )
    if [ "$got" = "check=$want" ]; then ok "only $name active -> check=$want"; else bad "only $name active: want check=$want got '$got'"; fi
}
probe "dirty check" "$D/x_dirty.img" 1 6
probe "journal check" "$D/x_log.img" 2 8
probe "bad-cluster check" "$D/x_bad.img" 4 13
probe "hibernation check" "$D/x_hib.img" 8 7

echo "== 8. source mutations: each broken check must be caught by section 6 images =="
mutcase() {
    local name=$1 expr=$2 img=$3 file=${4:-checks.fi}
    rm -rf "$D/mutlib"; cp -r lib "$D/mutlib"
    sed -i "$expr" "$D/mutlib/ntfsshrink/$file"
    if cmp -s lib/ntfsshrink/$file "$D/mutlib/ntfsshrink/$file"; then bad "mutation $name did not change the source"; return; fi
    if ! FIRNLIB="$D/mutlib" "$FIRNC" -o "$D/mutunit" tools/ntfsshrink/unit.fi > "$D/mut.log" 2>&1; then bad "mutation $name does not build"; return; fi
    local got
    got=$( "$D/mutunit" "$img" c 0 2>&1 | grep -a -m1 '^check=' )
    if [ "$got" = "check=0" ]; then ok "mutation $name: defective volume passes -> section 6 would be red"; else bad "mutation $name not detected: '$got'"; fi
}
mutcase "flags mask 0" 's/const FLAGS_MASK: u64 = 49207/const FLAGS_MASK: u64 = 0/' "$D/x_dirty.img"
mutcase "journal verdict inverted" 's/if clean == 0 {/if clean == 7 {/' "$D/x_log.img"
mutcase "bad-cluster length ignored" 's/ || it.len != (\*v).clusters//; s/if runs.next(&it) || it.bad != 0 {/if false {/' "$D/x_bad.img"
mutcase "hibernation verdict dropped" 's/    return codes.E_HIBERNATED/    return codes.E_OK/' "$D/x_hib.img" hiber.fi

. tools/ntfsshrink/shrink.sh

echo "NTFSSHRINK: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
