#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/unterbau/build-foot-stones.sh -- build the foot proof stones (r701): expat libffi pixman freetype wayland
# fontconfig xkbcommon tllist fcft foot, musl, dynamic, meson.
#
#   /root/jarvis/bin/heavy bash tools/unterbau/build-foot-stones.sh <outdir> [<workdir>]
#
# <outdir> afterwards holds:  foot/manifest.txt  (lines "guestpath=hostfile", fed to the image builder)  and the files themselves.
# Sources: /root/fremdquellen (SHA256SUMS.txt checked). Needs: musl-gcc, meson (or python3 -m venv + pip), ninja, bison, gperf, make.
# Layout in the guest: /usr/bin/foot, /usr/lib/lib*.so*, /etc/fonts/fonts.conf, /usr/share/fonts/*.ttf
set -euo pipefail
OUT=$(realpath -m "${1:?usage: build-foot-stones.sh <outdir> [workdir]}")
W=${2:-$(mktemp -d)}
[ -n "${KEEP_WORK:-}" ] || trap 'rm -rf "$W"' EXIT
SRC=${FREMDQUELLEN:-/root/fremdquellen}
J=${JOBS:-6}
mkdir -p "$OUT/foot" "$W"/{x,log,prefix,kinc}
P=$W/prefix
mkdir -p "$P/lib/pkgconfig"

# --- source checks
( cd "$SRC" && for f in expat-2.6.3.tar.xz libffi-3.4.6.tar.gz pixman-0.43.4.tar.gz freetype-2.13.3.tar.xz wayland-1.23.1.tar.xz wayland-protocols-1.38.tar.xz \
    fontconfig-2.15.0.tar.xz libxkbcommon-1.7.0.tar.xz tllist-1.1.0.tar.gz fcft-3.1.1.tar.gz foot-1.19.0.tar.gz; do grep " $f\$" SHA256SUMS.txt; done | sha256sum -c - >/dev/null ) \
    || { echo "build-foot-stones: sha256 mismatch or missing source in $SRC"; exit 1; }

# --- meson
if command -v meson >/dev/null; then MESON=meson; else
    python3 -m venv "$W/venv" && "$W/venv/bin/pip" install -q meson && MESON=$W/venv/bin/meson
fi

# --- compiler environment: musl-gcc + Linux uapi headers (musl-gcc has none: linux/input-event-codes.h etc.)
ln -s /usr/include/linux "$W/kinc/linux"; ln -s /usr/include/asm-generic "$W/kinc/asm-generic"; ln -s /usr/include/x86_64-linux-gnu/asm "$W/kinc/asm"
export CC=musl-gcc CFLAGS="-O2 -fPIC -isystem $W/kinc" CPPFLAGS="-isystem $W/kinc"
export PKG_CONFIG_LIBDIR="$P/lib/pkgconfig:$P/share/pkgconfig" PKG_CONFIG_PATH=
export PATH="$P/bin:$PATH" LDFLAGS="-Wl,-rpath,$P/lib -L$P/lib"

unpack() { mkdir -p "$W/x/$1"; tar xf "$SRC/$2" -C "$W/x/$1" --strip-components=1; }
step() { local n=$1; shift; echo "== $n =="; [ -e "$W/log/$n.ok" ] && { echo "(done before)"; return 0; }; if ! ( "$@" ) >"$W/log/$n.log" 2>&1; then echo "FAILED: $n"; tail -n 40 "$W/log/$n.log"; exit 1; fi; touch "$W/log/$n.ok"; }
mesonb() { # <name> <extra meson args...>  (source dir $W/x/<name>)
    local n=$1; shift
    ( cd "$W/x/$n" && "$MESON" setup b --prefix="$P" --libdir=lib --buildtype=release -Ddefault_library=shared "$@" && ninja -C b -j"$J" && ninja -C b install )
}

unpack expat expat-2.6.3.tar.xz; unpack libffi libffi-3.4.6.tar.gz; unpack pixman pixman-0.43.4.tar.gz; unpack freetype freetype-2.13.3.tar.xz
unpack wayland wayland-1.23.1.tar.xz; unpack wlproto wayland-protocols-1.38.tar.xz; unpack fontconfig fontconfig-2.15.0.tar.xz
unpack xkbcommon libxkbcommon-1.7.0.tar.xz; unpack tllist tllist-1.1.0.tar.gz; unpack fcft fcft-3.1.1.tar.gz; unpack foot foot-1.19.0.tar.gz

step expat bash -c "cd '$W/x/expat' && ./configure --prefix='$P' --libdir='$P/lib' --enable-shared --disable-static --without-docs --without-examples --without-tests --without-xmlwf && make -j$J && make install"
step libffi bash -c "cd '$W/x/libffi' && ./configure --prefix='$P' --libdir='$P/lib' --enable-shared --disable-static --disable-docs --disable-multi-os-directory && make -j$J && make install"
step pixman mesonb pixman -Dgtk=disabled -Dlibpng=disabled -Dtests=disabled -Ddemos=disabled -Dopenmp=disabled -Dtls=disabled
step freetype mesonb freetype -Dzlib=disabled -Dbzip2=disabled -Dpng=disabled -Dharfbuzz=disabled -Dbrotli=disabled -Dtests=disabled
step wayland mesonb wayland -Dlibraries=true -Dscanner=true -Dtests=false -Ddocumentation=false -Ddtd_validation=false
step wlproto mesonb wlproto -Dtests=false
step xkbcommon mesonb xkbcommon -Denable-x11=false -Denable-wayland=false -Denable-docs=false -Denable-tools=false -Denable-xkbregistry=false \
    -Denable-bash-completion=false -Dxkb-config-root=/usr/share/X11/xkb -Dx-locale-root=/usr/share/X11/locale
step tllist mesonb tllist
# fontconfig: config paths are compiled in (/etc/fonts, /var/cache), so install into a DESTDIR and merge by hand
step fontconfig bash -c "cd '$W/x/fontconfig' && '$MESON' setup b --prefix='$P' --libdir=lib --sysconfdir=/etc --localstatedir=/var --buildtype=release -Ddefault_library=shared \
    -Dtests=disabled -Dtools=disabled -Ddoc=disabled -Dnls=disabled -Dcache-build=disabled -Ddefault-fonts-dirs=/usr/share/fonts \
    && ninja -C b -j$J && DESTDIR='$W/fcroot' ninja -C b install && cp -a '$W/fcroot$P/.' '$P/'"
step fcft mesonb fcft -Dgrapheme-shaping=disabled -Drun-shaping=disabled -Dsvg-backend=none -Dtest-text-shaping=false -Dexamples=false -Ddocs=disabled
step foot mesonb foot -Ddocs=disabled -Dgrapheme-clustering=disabled -Dime=false -Dterminfo=disabled -Dthemes=false -Dutmp-backend=none -Dtests=false

# --- collect: foot + every shared library it needs (transitively), as manifest guestpath=hostfile
echo "== collect =="
F=$OUT/foot; rm -rf "$F"; mkdir -p "$F/lib" "$F/etc/fonts" "$F/fonts"
cp "$P/bin/foot" "$F/foot"; strip "$F/foot" || true
echo "/usr/bin/foot=$F/foot" > "$F/manifest.txt"
need=$(readelf -d "$F/foot" | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p')
seen=" "
while [ -n "$need" ]; do
    nx=""
    for so in $need; do
        case "$seen" in *" $so "*) continue ;; esac
        seen="$seen$so "
        case "$so" in libc.so|libc.musl-x86_64.so.1) continue ;; esac
        h=$(find -L "$P/lib" -maxdepth 1 -name "$so" | head -n 1)
        [ -n "$h" ] || { echo "collect: $so not found in $P/lib"; exit 1; }
        cp -L "$h" "$F/lib/$so"; strip --strip-unneeded "$F/lib/$so" || true
        echo "/usr/lib/$so=$F/lib/$so" >> "$F/manifest.txt"
        nx="$nx $(readelf -d "$F/lib/$so" | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p')"
    done
    need=$nx
done
# minimal fontconfig setup + one monospace font
cat > "$F/etc/fonts/fonts.conf" <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <dir>/usr/share/fonts</dir>
  <cachedir>/tmp/fontconfig</cachedir>
  <alias><family>monospace</family><prefer><family>DejaVu Sans Mono</family></prefer></alias>
</fontconfig>
EOF
echo "/etc/fonts/fonts.conf=$F/etc/fonts/fonts.conf" >> "$F/manifest.txt"
FONT=$(fc-list 2>/dev/null | grep -i 'DejaVuSansMono.ttf' | head -n 1 | cut -d: -f1)
[ -n "$FONT" ] || FONT=$(find /usr/share/fonts -name DejaVuSansMono.ttf | head -n 1)
[ -n "$FONT" ] && { cp "$FONT" "$F/fonts/DejaVuSansMono.ttf"; echo "/usr/share/fonts/DejaVuSansMono.ttf=$F/fonts/DejaVuSansMono.ttf" >> "$F/manifest.txt"; }
echo "stone libs: $(grep -c '/usr/lib/' "$F/manifest.txt")"; cat "$F/manifest.txt"
echo "BUILD-FOOT-STONES DONE"
