#!/usr/bin/env bash
set -u

cd "$(dirname "$0")/../.." || exit 1
ROOT=$PWD
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  ok   $1"; }
bad() { fail=$((fail+1)); echo "  FEHL $1"; }

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

echo "== 1. the kernel and the memory map =="

if python3 tools/kernel/memmap.py kernel > "$TMPD/map.txt" 2>&1; then
    if grep -q "0 collisions" "$TMPD/map.txt"; then
        ok "Speicherkarte: $(tail -1 "$TMPD/map.txt")"
    else
        bad "Speicherkarte meldet Kollisionen"; sed 's/^/        /' "$TMPD/map.txt" | tail -5
    fi
else
    bad "memmap.py gescheitert"; sed 's/^/        /' "$TMPD/map.txt" | tail -5
fi

if bash tools/build-kernel.sh "$TMPD/k.elf" > "$TMPD/build.txt" 2>&1; then
    ok "der Kern baut ($(stat -c%s "$TMPD/k.elf") Oktette)"
    objcopy -O elf32-i386 "$TMPD/k.elf" "$TMPD/k.mb" 2>/dev/null
else
    bad "the kernel does NOT build"
    grep -viE 'warning|^\s+\||^\s+=|note:' "$TMPD/build.txt" | tail -10 | sed 's/^/        /'
    echo "== WAYLAND: $pass bestanden, $fail gescheitert =="
    exit 1
fi

echo
echo "== 2. the real client, static against musl =="

WLB=${WLBUILD:-/root/wl-build}
if [ -d "$WLB/musl-root/lib" ] && [ -f "$WLB/musl-root/lib/libwayland-client.a" ]; then
    ok "libwayland-client.a (musl, static) is present"
else
    bad "libwayland-client.a fehlt -- siehe docs/RUNDE-WAYLAND.md, Abschnitt Bauen"
fi
if [ -f "$WLB/out/simple-shm-memfd" ]; then
    ok "weston-simple-shm gebaut ($(stat -c%s "$WLB/out/simple-shm-memfd") Oktette)"
else
    bad "weston-simple-shm nicht gebaut"
fi

echo
echo "== 3. wltest im laufenden Kern: AF_UNIX, SCM_RIGHTS, MAP_SHARED =="

if musl-gcc -static -O2 -nostartfiles -T tools/foreign/osum.ld \
        -Wl,--build-id=none -o "$TMPD/wltest" \
        tools/foreign/start.s tools/foreign/osum_main.c \
        tools/wayland/wltest.c 2>"$TMPD/cc.txt"; then
    ok "wltest gebaut (musl, statisch, ab 0x40100000)"
else
    bad "wltest baut nicht"; grep -v 'GNU-stack\|deprecated' "$TMPD/cc.txt" | head -5 | sed 's/^/        /'
fi

. "$ROOT/tools/lib/firnenv.sh"
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>"$TMPD/as.txt" \
    && ok "crt.s assembliert" || { bad "crt.s"; sed 's/^/        /' "$TMPD/as.txt" | head -3; }
if "$FIRNC" kernel/user/sh.fi -o "$TMPD/sh.o" > "$TMPD/sh.txt" 2>&1 \
   && ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
        -o "$TMPD/sh.elf" "$TMPD/crt.o" "$TMPD/sh.o" 2>>"$TMPD/sh.txt"; then
    strip --strip-all "$TMPD/sh.elf"
    ok "/bin/sh gebaut"
else
    bad "/bin/sh baut nicht"; grep -v 'GNU-stack\|RWX' "$TMPD/sh.txt" | head -5 | sed 's/^/        /'
fi

if [ -f "$TMPD/wltest" ]; then
    bash tools/mkfsfi/mkfs.sh build "$TMPD/disk.img" 4096 --inodes=64 \
        /bin/ "/bin/sh=$TMPD/sh.elf" "/bin/wltest=$TMPD/wltest" \
        > "$TMPD/mkfs.txt" 2>&1 \
        && ok "Abbild gebaut" || { bad "mkfs gescheitert"; sed 's/^/        /' "$TMPD/mkfs.txt" | head -5; }

    QEMU="qemu-system-x86_64"
    ACCEL=""
    [ -w /dev/kvm ] && ACCEL="-accel kvm -cpu host"
    timeout 180 $QEMU -kernel "$TMPD/k.mb" -m 256 $ACCEL \
        -append "osum nokbd noring3 script=wltest;exit" \
        -serial "file:$TMPD/run.txt" -display none -no-reboot \
        -drive "file=$TMPD/disk.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    rc=$?
    F="$TMPD/run.txt"
    tr -d '\000' < "$F" > "$TMPD/clean.txt" 2>/dev/null
    if grep -q "wltest fertig" "$TMPD/clean.txt"; then
        ok "wltest ran in the kernel"
        sed -n '/== wltest/,/wltest fertig/p' "$TMPD/clean.txt" | sed 's/^/     /'
        n_ok=$(grep -c '^  ok   ' "$TMPD/clean.txt" 2>/dev/null | tr -dc '0-9')
        n_bad=$(grep -c '^  FEHL ' "$TMPD/clean.txt" 2>/dev/null | tr -dc '0-9')
        [ -n "$n_ok" ] || n_ok=0
        [ -n "$n_bad" ] || n_bad=0
        pass=$((pass + n_ok)); fail=$((fail + n_bad))
    else
        bad "wltest did not report (QEMU code $rc)"
        tail -20 "$TMPD/clean.txt" 2>/dev/null | sed 's/^/        /'
    fi
fi

echo
echo "== 4. der echte Client: libwayland-client, unveraendert =="

if python3 tools/wayland/gen.py > "$TMPD/wlproto.fi" 2>"$TMPD/gen.txt"; then
    if cmp -s "$TMPD/wlproto.fi" kernel/user/wlproto.fi; then
        ok "wlproto.fi ist ERZEUGT: $(tail -1 "$TMPD/gen.txt")"
    else
        bad "kernel/user/wlproto.fi deviates from what gen.py produces"
    fi
else
    bad "tools/wayland/gen.py scheitert"; sed 's/^/        /' "$TMPD/gen.txt" | head -3
fi

for x in /usr/share/wayland/wayland.xml \
         /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml; do
    [ -r "$x" ] && ok "Protokollquelle da: $x" \
                || bad "Protokollquelle fehlt: $x"
done

if [ -f "$WLB/out/simple-shm-memfd" ]; then
    m=$(md5sum "$WLB/weston-10.0.1/clients/simple-shm.c" 2>/dev/null | cut -c1-32)
    if [ "$m" = "09565c8cc58ea14f40e2a59182328e57" ]; then
        ok "weston-simple-shm.c ist UNVERAENDERT (md5 $m)"
    else
        bad "simple-shm.c hat md5 $m -- erwartet 09565c8c..."
    fi
fi

echo
echo "== 5. the images of the round =="
for b in docs/shots/wayland/stufe1-muster.png; do
    [ -s "$b" ] && ok "Bild da: $b ($(stat -c%s "$b") Oktett)" \
                || bad "Bild fehlt: $b"
done

echo
echo "== 6. Modularitaet: eigener Prozess, Dienst, Paket =="
grep -q 'wayd:grafik:off:/bin/wayd' etc/inittab.wayland 2>/dev/null \
    && ok "service line is in etc/inittab.wayland (on 'off')" \
    || bad "keine Dienstzeile"
[ -s pkg/rezepte/wayland.rezept ] \
    && ok "Paketrezept da: pkg/rezepte/wayland.rezept" \
    || bad "kein Paketrezept"
[ -s kernel/user/wayd.fi ] \
    && ok "the server is a ring-3 program (kernel/user/wayd.fi)" \
    || bad "wayd.fi missing"
n=$(grep -rl 'wayd\.' kernel/*.fi kernel/user/desktop.fi \
        kernel/user/taskbar.fi kernel/user/taskbar 2>/dev/null | wc -l)
[ "$n" -eq 0 ] \
    && ok "CONTROL RUN: no kernel part and no desktop part calls wayd" \
    || bad "$n file(s) call wayd -- it would not be switchable off"

echo
echo "== 7. keyboard, pointer, clipboard (round WAYLAND-INPUT; the acceptance on a screen is tools/wayland/input.sh) =="
for f in wl_msg wl_input wl_data wl_keytab; do
    [ -s "kernel/user/$f.fi" ] && ok "kernel/user/$f.fi is there" || bad "kernel/user/$f.fi is missing"
done
if python3 tools/wayland/genkeys.py 2>/dev/null | cmp -s - kernel/user/wl_keytab.fi; then
    ok "wl_keytab.fi is GENERATED (tools/wayland/genkeys.py, from the host's libxkbcommon)"
else
    bad "kernel/user/wl_keytab.fi differs from what genkeys.py generates"
fi
if python3 tools/wayland/genkeys.py --keymaps "$TMPD/km" 2>"$TMPD/km.txt"; then
    ok "the keymaps us and de compile with libxkbcommon and again from their own text ($(tr '\n' ' ' < "$TMPD/km.txt"))"
else
    bad "genkeys.py --keymaps fails"
fi
grep -q 'IF_WL_DATA_DEVICE_MANAGER' kernel/user/wlproto.fi \
    && ok "wlproto.fi knows wl_data_device_manager (the clipboard)" || bad "wlproto.fi has no wl_data_device_manager"

echo
echo "== WAYLAND: $pass bestanden, $fail gescheitert =="
[ "$fail" -eq 0 ]
