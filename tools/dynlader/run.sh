#!/usr/bin/env bash
#
#   bash tools/dynlader/run.sh [arbeitsverzeichnis]
#
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

TMPD=${1:-$(mktemp -d)}
. tools/lib/tmpdir.sh
osum_tmp_guard "${1:-}" "$TMPD"
mkdir -p "$TMPD"

pass=0
fail=0
skip=0
ok()   { pass=$((pass + 1)); printf '  \033[32mok\033[0m   %s\n' "$*"; }
bad()  { fail=$((fail + 1)); printf '  \033[31mNEIN\033[0m %s\n' "$*"; }
weg()  { skip=$((skip + 1)); printf '  \033[33m--\033[0m   %s\n' "$*"; }

QEMU_X86=${QEMU_X86:-qemu-system-x86_64}
KVM=()
if [ -w /dev/kvm ]; then KVM=(-accel kvm -cpu host); fi

echo "== 0. das Werkzeug =="
for t in musl-gcc "$QEMU_X86" readelf; do
    command -v "$t" >/dev/null 2>&1 || { echo "DYNLADER: $t fehlt, uebersprungen"; exit 0; }
done
ok "musl-gcc, qemu and readelf are there"
[ ${#KVM[@]} -gt 0 ] && ok "KVM wird benutzt (-accel kvm -cpu host)" \
                     || weg "kein /dev/kvm -- der Lauf geht unter TCG und ist langsamer"

echo "== 1. die Textkonstanten in kernel/ldr/elf.fi =="
python3 - "$ROOT/kernel/ldr/elf.fi" > "$TMPD/texte.txt" 2>&1 <<'PY'
import re, sys
s = open(sys.argv[1], encoding='utf-8', errors='surrogateescape').read()
bad = 0
n = 0
for m in re.finditer(r'var (\w+): \[u8; (\d+)\] = "((?:[^"\\]|\\.)*)"', s):
    real = m.group(3).replace('\\0', '\0').replace('\\n', '\n').replace('\\\\', '\\')
    n += 1
    if int(m.group(2)) != len(real):
        print("FALSCH %s: Feld %s, Inhalt %d" % (m.group(1), m.group(2), len(real)))
        bad += 1
print("GEPRUEFT %d FALSCH %d" % (n, bad))
PY
if grep -q 'FALSCH 0$' "$TMPD/texte.txt"; then
    ok "$(grep -o 'GEPRUEFT [0-9]*' "$TMPD/texte.txt") Textkonstanten, alle so lang wie ihr Feld"
else
    bad "a text constant does not fit its field -- firnc1 would abort SILENTLY"
    sed 's/^/        /' "$TMPD/texte.txt"
fi

# ============================================================ 2.
echo "== 2. the target programs, built dynamically against musl =="
cat > "$TMPD/hello.c" <<'C'
#include <stdio.h>
int main(int argc, char **argv) {
    printf("hallo dynamisch\n");
    return 0;
}
C
musl-gcc -O2 -o "$TMPD/hello_dyn" "$TMPD/hello.c" 2>"$TMPD/cc.err" \
    && ok "hello.c dynamisch gegen musl gebunden" \
    || { bad "musl-gcc gescheitert"; sed 's/^/        /' "$TMPD/cc.err" | head -5; }

IPATH=$(readelf -lW "$TMPD/hello_dyn" 2>/dev/null \
        | sed -n 's/.*Requesting program interpreter: \(.*\)\]/\1/p')
[ -n "$IPATH" ] && ok "hello_dyn has a PT_INTERP: $IPATH" \
                || bad "hello_dyn has NO PT_INTERP -- it would be static"
readelf -hW "$TMPD/hello_dyn" 2>/dev/null | grep -q 'Type:.*DYN' \
    && ok "hello_dyn ist ET_DYN (PIE)" || bad "hello_dyn is not ET_DYN"

LDSO=${LDSO:-/lib/ld-musl-x86_64.so.1}
if [ -r "$LDSO" ]; then
    LDREAL=$(readlink -f "$LDSO")
    ok "the interpreter is present: $LDREAL ($(stat -c%s "$LDREAL") Oktette)"
    readelf -hW "$LDREAL" | grep -q 'Type:.*DYN' \
        && ok "and it is itself an ET_DYN -- that is why read_header had to be opened up" \
        || bad "the interpreter is not an ET_DYN"
else
    bad "no interpreter at $LDSO"
fi

# dlopen/dlsym, Stufe 3.
cat > "$TMPD/dltest.c" <<'C'
#include <stdio.h>
#include <dlfcn.h>
int main(void) {
    void *h = dlopen(0, RTLD_NOW);
    if (!h) { printf("dlopen NEIN\n"); return 1; }
    int (*f)(const char *) = dlsym(h, "puts");
    if (!f) { printf("dlsym NEIN\n"); return 2; }
    f("dlsym ok");
    return 0;
}
C
musl-gcc -O2 -o "$TMPD/dltest" "$TMPD/dltest.c" 2>/dev/null \
    && ok "dltest (dlopen/dlsym) gebunden" || weg "dltest nicht baubar"

BBDYN=${BBDYN:-/root/bbdyn/busybox}
BB_DA=0
if [ -x "$BBDYN" ] && readelf -lW "$BBDYN" 2>/dev/null | grep -q 'program interpreter'; then
    BB_DA=1
    ok "dynamic busybox is present: $BBDYN ($(stat -c%s "$BBDYN") Oktette)"
else
    weg "kein dynamisches busybox (BBDYN=...) -- Stufe 2 wird uebersprungen"
fi

# ============================================================ 3.
echo "== 3. der Kernel =="
if bash tools/build-kernel.sh "$TMPD/k.mb" --stufe 1 > "$TMPD/k.log" 2>&1; then
    ok "the kernel is built ($(stat -c%s "$TMPD/k.mb") Oktette)"
else
    bad "the kernel does NOT build (message below -- with firnc1 often EMPTY,"
    echo "        and then it is usually a text constant that does not fit its field)"
    sed 's/^/        /' "$TMPD/k.log" | tail -12
    echo "DYNLADER: $pass bestanden, $fail gescheitert"
    exit 1
fi

echo "== 3b. the userland programs =="
PROGS=${PROGS:-"sh ls cat echo"}
export FIRNLIB="$ROOT/lib"
. "$ROOT/tools/lib/firnenv.sh"
firnenv_need_firnc1
FIRNC=$FIRNC1
ULD=kernel/user/user.ld
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>"$TMPD/ascrt.err" \
    || bad "crt.s assembliert nicht"
ubad=0
for p in $PROGS; do
    "$FIRNC" "kernel/user/$p.fi" -o "$TMPD/$p.o" > "$TMPD/e$p.log" 2>&1 || {
        bad "firnc1 uebersetzt $p.fi nicht"; ubad=$((ubad+1)); continue; }
    ld -T "$ULD" --defsym=USER_ENTRY="_F1.u_start" \
        -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>"$TMPD/ld$p.err" || {
        bad "ld an $p gescheitert"; ubad=$((ubad+1)); continue; }
    strip --strip-all "$TMPD/$p.elf" 2>/dev/null
done
[ $ubad = 0 ] && ok "$(echo $PROGS | wc -w) Programme gebaut ($PROGS)" \
              || bad "$ubad Programme fehlen -- das Abbild waere unbrauchbar"

echo "== 4. das Abbild =="
BLOCKS=${BLOCKS:-65536}
mkdir -p "$TMPD/bin"

SPEC="/lib/ /bin/"
for p in $PROGS; do SPEC="$SPEC /bin/$p=$TMPD/$p.elf"; done
SPEC="$SPEC /lib/ld-musl-x86_64.so.1=$LDREAL"
SPEC="$SPEC /bin/hello_dyn=$TMPD/hello_dyn"
[ -x "$TMPD/dltest" ] && SPEC="$SPEC /bin/dltest=$TMPD/dltest"
[ "$BB_DA" = 1 ] && SPEC="$SPEC /bin/busybox=$BBDYN"

python3 - "$TMPD/hello_dyn" "$TMPD/badinterp" <<'PY'
import sys, struct
d = bytearray(open(sys.argv[1], 'rb').read())
phoff = struct.unpack_from('<Q', d, 0x20)[0]
phentsize = struct.unpack_from('<H', d, 0x36)[0]
phnum = struct.unpack_from('<H', d, 0x38)[0]
for i in range(phnum):
    o = phoff + i * phentsize
    if struct.unpack_from('<I', d, o)[0] == 3:      # PT_INTERP
        off = struct.unpack_from('<Q', d, o + 8)[0]
        sz = struct.unpack_from('<Q', d, o + 32)[0]
        neu = b'/lib/gibtesnicht.so\x00'
        assert len(neu) <= sz, (len(neu), sz)
        d[off:off + sz] = neu + b'\x00' * (sz - len(neu))
        break
open(sys.argv[2], 'wb').write(bytes(d))
PY
[ -s "$TMPD/badinterp" ] && SPEC="$SPEC /bin/badinterp=$TMPD/badinterp"

python3 - "$TMPD/hello_dyn" "$TMPD/chaininterp" <<'PY'
import sys, struct
d = bytearray(open(sys.argv[1], 'rb').read())
phoff = struct.unpack_from('<Q', d, 0x20)[0]
phentsize = struct.unpack_from('<H', d, 0x36)[0]
phnum = struct.unpack_from('<H', d, 0x38)[0]
for i in range(phnum):
    o = phoff + i * phentsize
    if struct.unpack_from('<I', d, o)[0] == 3:
        off = struct.unpack_from('<Q', d, o + 8)[0]
        sz = struct.unpack_from('<Q', d, o + 32)[0]
        neu = b'/bin/hello_dyn\x00'
        assert len(neu) <= sz
        d[off:off + sz] = neu + b'\x00' * (sz - len(neu))
        break
open(sys.argv[2], 'wb').write(bytes(d))
PY
[ -s "$TMPD/chaininterp" ] && SPEC="$SPEC /bin/chaininterp=$TMPD/chaininterp"

bash tools/mkfsfi/mkfs.sh build "$TMPD/disk.img" $BLOCKS $SPEC \
    > "$TMPD/mkfs.txt" 2>&1 \
    && ok "OFS-Abbild gebaut ($BLOCKS Bloecke)" \
    || { bad "mkfs.py gescheitert"; sed 's/^/        /' "$TMPD/mkfs.txt" | head -10; }

run_disk() { # append out
    cp -f "$TMPD/disk.img" "$TMPD/live.img"
    timeout "${TMO:-240}" $QEMU_X86 "${KVM[@]}" -kernel "$TMPD/k.mb" -m 512 \
        -append "$1" -serial "file:$2" -display none -no-reboot \
        -drive "file=$TMPD/live.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    return $?
}
QUIET="nokbd nosched noproc nofs"

# ============================================================ 5.
echo "== 5. STAGE 1: a dynamically linked program runs =="
run_disk "osum $QUIET script=hello_dyn;exit" "$TMPD/s1.txt"
sed '/^mb: flags=/d' "$TMPD/s1.txt" > "$TMPD/s1.rein" 2>/dev/null
if grep -q 'hallo dynamisch' "$TMPD/s1.rein" 2>/dev/null; then
    ok "STAGE 1 PASSED: hello_dyn printed its line"
else
    bad "STAGE 1: no output from hello_dyn"
    echo "        --- what the kernel said:"
    grep -iE 'elf:|refused|reason|vector|panic|#PF|#GP' "$TMPD/s1.txt" 2>/dev/null \
        | sed 's/^/        /' | head -12
fi

# ============================================================ 6.
echo "== 6. STAGE 2: busybox, ten applets, octet for octet =="
if [ "$BB_DA" = 1 ]; then
    cat > "$TMPD/bbskript" <<'S'
/bin/busybox echo hallo-echo
/bin/busybox wc -c /etc/pruef.txt
/bin/busybox cat /etc/pruef.txt
/bin/busybox head -2 /etc/pruef.txt
/bin/busybox sort /etc/pruef.txt
/bin/busybox grep zwei /etc/pruef.txt
/bin/busybox uname -s
/bin/busybox sha256sum /etc/pruef.txt
/bin/busybox env
/bin/busybox ls /bin
S
    printf 'eins\nzwei\ndrei\n' > "$TMPD/pruef.txt"
    bash tools/mkfsfi/mkfs.sh build "$TMPD/disk.img" $BLOCKS $SPEC \
        /etc/ "/etc/pruef.txt=$TMPD/pruef.txt" > "$TMPD/mkfs2.txt" 2>&1 \
        || bad "mkfs.py (Stufe 2) gescheitert"
    #
    for a in "echo hallo-echo" "cat /etc/pruef.txt" "wc -c /etc/pruef.txt" \
             "head -n 2 /etc/pruef.txt" "sort /etc/pruef.txt" \
             "grep zwei /etc/pruef.txt" "uname -s" \
             "sha256sum /etc/pruef.txt"; do
        name=${a%% *}
        run_disk "osum $QUIET script=busybox $a;exit" "$TMPD/bb-$name.txt"
        ( cd "$TMPD" && mkdir -p wirt/etc wirt/bin && cp pruef.txt wirt/etc/ )
        soll=$("$BBDYN" $(echo "$a" | sed "s|/etc/pruef.txt|$TMPD/pruef.txt|g") 2>/dev/null \
               | head -5 | tr -d '\r')
        if [ -n "$soll" ]; then
            erste=$(printf '%s' "$soll" | head -1)
            case "$name" in
                sha256sum|wc) erste=$(printf '%s' "$erste" | awk '{print $1}') ;;
            esac
            sed '/^mb: flags=/d' "$TMPD/bb-$name.txt" > "$TMPD/bb-$name.rein"
            if grep -qF "$erste" "$TMPD/bb-$name.rein" 2>/dev/null; then
                ok "busybox $name -- output as on the host ($erste)"
            else
                bad "busybox $name -- output missing or differs (expected: $erste)"
            fi
        else
            weg "busybox $name -- der Wirt liefert nichts zum Vergleichen"
        fi
    done
    run_disk "osum $QUIET script=busybox ls /bin;exit" "$TMPD/bb-ls.txt"
    sed '/^mb: flags=/d' "$TMPD/bb-ls.txt" > "$TMPD/bb-ls.rein"
    lsfehlt=""
    for n in busybox hello_dyn dltest sh cat echo ls; do
        grep -qw "$n" "$TMPD/bb-ls.rein" || lsfehlt="$lsfehlt $n"
    done
    [ -z "$lsfehlt" ] \
        && ok "busybox ls -- names every file that is in /bin of this image" \
        || bad "busybox ls -- these names are missing from the output:$lsfehlt"

    run_disk "osum $QUIET script=busybox env;exit" "$TMPD/bb-env.txt"
    sed '/^mb: flags=/d' "$TMPD/bb-env.txt" > "$TMPD/bb-env.rein"
    if grep -qiE 'panic|vector=|elf: refused' "$TMPD/bb-env.rein"; then
        bad "busybox env -- the run aborted"
        grep -iE 'panic|vector=|elf: refused' "$TMPD/bb-env.rein" | sed 's/^/        /' | head -4
    else
        ok "busybox env -- runs and ends without crash (envp comes from the new stack)"
    fi
else
    weg "STUFE 2 uebersprungen (kein dynamisches busybox)"
fi

# ============================================================ 7.
echo "== 7. STUFE 3: dlopen/dlsym =="
if [ -x "$TMPD/dltest" ]; then
    run_disk "osum $QUIET script=dltest;exit" "$TMPD/s3.txt"
    sed '/^mb: flags=/d' "$TMPD/s3.txt" > "$TMPD/s3.rein" 2>/dev/null
    if grep -q 'dlsym ok' "$TMPD/s3.rein" 2>/dev/null; then
        ok "STUFE 3 GEFALLEN: dlopen(0)+dlsym(\"puts\") hat gearbeitet"
    else
        bad "STAGE 3: dlopen/dlsym did not run"
        grep -iE 'elf:|refused|dlopen|dlsym|vector' "$TMPD/s3.txt" 2>/dev/null \
            | sed 's/^/        /' | head -8
    fi
else
    weg "STUFE 3 uebersprungen"
fi

echo "== 8. die Gegenproben =="

run_disk "osum $QUIET script=badinterp;exit" "$TMPD/g1.txt"
rc=$?
if [ $rc -eq 124 ]; then
    bad "a missing interpreter HANGS the machine (timeout)"
elif grep -qiE 'interpreter missing|reason 26' "$TMPD/g1.txt" 2>/dev/null; then
    ok "a missing interpreter is rejected with reason 26, the machine runs"
elif grep -qiE 'refused|not found|No such' "$TMPD/g1.txt" 2>/dev/null; then
    ok "a missing interpreter is rejected (message, no hang)"
else
    bad "a missing interpreter gives no recognisable rejection"
    grep -iE 'elf:|reason|vector' "$TMPD/g1.txt" | sed 's/^/        /' | head -6
fi

# b) Interpreter-Kette: ABGEWIESEN.
run_disk "osum $QUIET script=chaininterp;exit" "$TMPD/g2.txt"
rc=$?
if [ $rc -eq 124 ]; then
    bad "an interpreter chain HANGS the machine"
elif grep -qiE 'interpreter chained|reason 27' "$TMPD/g2.txt" 2>/dev/null; then
    ok "an interpreter with its own PT_INTERP is rejected with reason 27"
elif grep -qiE 'refused' "$TMPD/g2.txt" 2>/dev/null; then
    ok "an interpreter with its own PT_INTERP is rejected"
else
    bad "an interpreter chain is not recognisably rejected"
    grep -iE 'elf:|reason|vector' "$TMPD/g2.txt" | sed 's/^/        /' | head -6
fi

run_disk "osum $QUIET script=echo statisch-lebt;exit" "$TMPD/g3.txt"
sed '/^mb: flags=/d' "$TMPD/g3.txt" > "$TMPD/g3.rein" 2>/dev/null
if grep -q 'statisch-lebt' "$TMPD/g3.rein" 2>/dev/null; then
    ok "the statically linked programs keep running unchanged"
else
    weg "kein /bin/echo im Abbild -- der statische Fall wurde hier nicht gemessen"
fi

echo "== 9. Modularitaet: abschaltbar und separat ausgeliefert =="

. "$(dirname "${BASH_SOURCE[0]}")/baseimage.sh"
if base_image_has_musl; then
    bad "tools/usbimg/build.sh puts ld-musl into the public image -- the interpreter would be in the base image"
else
    ok "ld-musl and busybox only enter the image behind BBSH=1 (personal profile opt-in), never in the public image"
fi
sed 's|^if \[ "\$BBSH" = 1 \]; then$|if true; then|' tools/usbimg/build.sh > "$TMPD/build-unguarded.sh"
if BUILD_SCRIPT="$TMPD/build-unguarded.sh" base_image_has_musl; then
    ok "counter-check: a build script that adds ld-musl unconditionally is flagged"
else
    bad "counter-check: an unguarded ld-musl line was not detected"
fi

OPKPY=${OPKPY:-$(python3 "$(dirname "${BASH_SOURCE[0]}")/../lib/opkpfad.py")}   # A-025: der alte Ordner war ein Arbeitsbaum
if [ -r "$OPKPY" ]; then
    mkdir -p "$TMPD/opk"
    LDR=$(readlink -f "$LDSO")
    sed "s|@LDSO@|$LDR|" tools/dynlader/paket/linux-abi.rezept \
        > "$TMPD/opk/linux-abi.rezept" 2>/dev/null \
        || cp tools/dynlader/paket/linux-abi.rezept "$TMPD/opk/linux-abi.rezept"
    if python3 "$OPKPY" bauen "$TMPD/opk/linux-abi.rezept" \
            -o "$TMPD/opk/linux-abi.opk" > "$TMPD/opk/bau1.txt" 2>&1; then
        ok "the package linux-abi builds ($(stat -c%s "$TMPD/opk/linux-abi.opk") Oktette)"
    else
        bad "the package linux-abi does not build"
        sed 's/^/        /' "$TMPD/opk/bau1.txt" | head -4
    fi
    rm -rf "$TMPD/wurzel"; mkdir -p "$TMPD/wurzel"
    if python3 "$OPKPY" installieren --wurzel "$TMPD/wurzel" \
            "$TMPD/opk/linux-abi.opk" > "$TMPD/opk/inst.txt" 2>&1; then
        ok "linux-abi laesst sich installieren (Generation, Store, Pruefsumme)"
        python3 "$OPKPY" pruefen --wurzel "$TMPD/wurzel" 2>&1 \
            | grep -q '0 kaputt' \
            && ok "und opk verify findet nichts Kaputtes" \
            || bad "opk verify complains about the tree"
    else
        bad "linux-abi cannot be installed"
        sed 's/^/        /' "$TMPD/opk/inst.txt" | head -4
    fi
else
    weg "kein opk.py ($OPKPY) -- der Paketbau wurde nicht gemessen"
fi

APPLIB="/apps/linux-abi.prog/lib/ld-musl-x86_64.so.1"
SPEC3="--v3 /lib/ /bin/ /etc/ /apps/ /apps/linux-abi.prog/ /apps/linux-abi.prog/lib/"
SPEC3="$SPEC3 $APPLIB=$LDREAL /lib/ld-musl-x86_64.so.1->$APPLIB"
for p in $PROGS; do SPEC3="$SPEC3 /bin/$p=$TMPD/$p.elf"; done
SPEC3="$SPEC3 /bin/hello_dyn=$TMPD/hello_dyn /etc/pruef.txt=$TMPD/pruef.txt"
[ "$BB_DA" = 1 ] && SPEC3="$SPEC3 /bin/busybox=$BBDYN"
if bash tools/mkfsfi/mkfs.sh build "$TMPD/paket.img" $BLOCKS $SPEC3 \
        > "$TMPD/mkfs3.txt" 2>&1; then
    ok "image in package form built (file under /apps, /lib/... as link)"
    cp -f "$TMPD/paket.img" "$TMPD/live.img"
    timeout "${TMO:-240}" $QEMU_X86 "${KVM[@]}" -kernel "$TMPD/k.mb" -m 512 \
        -append "osum $QUIET script=hello_dyn;exit" \
        -serial "file:$TMPD/p1.txt" -display none -no-reboot \
        -drive "file=$TMPD/live.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    sed '/^mb: flags=/d' "$TMPD/p1.txt" > "$TMPD/p1.rein"
    grep -q 'hallo dynamisch' "$TMPD/p1.rein" \
        && ok "a dynamic program runs when the loader comes FROM THE PACKAGE" \
        || bad "it does not run via the package link"
else
    bad "the image in package form cannot be built"
    sed 's/^/        /' "$TMPD/mkfs3.txt" | head -5
fi

SPEC4="/bin/ /etc/"
for p in $PROGS; do SPEC4="$SPEC4 /bin/$p=$TMPD/$p.elf"; done
SPEC4="$SPEC4 /bin/hello_dyn=$TMPD/hello_dyn /etc/pruef.txt=$TMPD/pruef.txt"
bash tools/mkfsfi/mkfs.sh build "$TMPD/ohne.img" $BLOCKS $SPEC4 \
    > "$TMPD/mkfs4.txt" 2>&1
cp -f "$TMPD/ohne.img" "$TMPD/live.img"
timeout "${TMO:-240}" $QEMU_X86 "${KVM[@]}" -kernel "$TMPD/k.mb" -m 512 \
    -append "osum $QUIET script=hello_dyn;exit" \
    -serial "file:$TMPD/p2.txt" -display none -no-reboot \
    -drive "file=$TMPD/live.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
prc=$?
sed '/^mb: flags=/d' "$TMPD/p2.txt" > "$TMPD/p2.rein"
if [ $prc -eq 124 ]; then
    bad "without the package the machine HANGS"
elif grep -qiE 'interpreter missing|reason 26' "$TMPD/p2.rein"; then
    ok "without the package: reason 26, cleanly rejected, the machine runs"
else
    bad "without the package there is no recognisable rejection"
fi

cp -f "$TMPD/ohne.img" "$TMPD/live.img"
timeout "${TMO:-240}" $QEMU_X86 "${KVM[@]}" -kernel "$TMPD/k.mb" -m 512 \
    -append "osum $QUIET script=echo ohne-paket-lebt;exit" \
    -serial "file:$TMPD/p3.txt" -display none -no-reboot \
    -drive "file=$TMPD/live.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
sed '/^mb: flags=/d' "$TMPD/p3.txt" > "$TMPD/p3.rein"
grep -q 'ohne-paket-lebt' "$TMPD/p3.rein" \
    && ok "a system WITHOUT the package is not broken -- Osum programs run" \
    || bad "without the package the own programs do not run either"

echo
echo "DYNLADER: $pass bestanden, $fail gescheitert, $skip uebersprungen"
echo "  Arbeitsverzeichnis: $TMPD"
[ "$fail" = 0 ]
