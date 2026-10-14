#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/unterbau/build-gtk-stones.sh -- build the GTK proof stones (r729): glib probe + GTK4 hello (Wayland backend), musl, dynamic.
#
#   /root/jarvis/bin/heavy bash tools/unterbau/build-gtk-stones.sh <outdir> [<workdir>]      (KEEP_WORK=1 keeps <workdir>, steps resume)
#
# <outdir>/gtk/ afterwards holds manifest.txt ("guestpath=hostfile"), glib-hello, gtk4-hello and the shared libraries they need.
# Chain: zlib pcre2 libffi expat pixman freetype wayland(+egl) wayland-protocols xkbcommon fontconfig fribidi glib harfbuzz cairo pango
#        libpng libjpeg-turbo libtiff gdk-pixbuf graphene libepoxy gtk4.  Sources: /root/fremdquellen (SHA256SUMS.txt is checked).
# Needs: musl-gcc, meson (or python3 venv + pip), ninja, cmake, nasm, bison, gperf, make, pkg-config.
set -euo pipefail
OUT=$(realpath -m "${1:?usage: build-gtk-stones.sh <outdir> [workdir]}")
W=${2:-$(mktemp -d)}
[ -n "${KEEP_WORK:-}" ] || trap 'rm -rf "$W"' EXIT
SRC=${FREMDQUELLEN:-/root/fremdquellen}
HERE=$(cd "$(dirname "$0")" && pwd)
J=${JOBS:-6}
mkdir -p "$OUT/gtk" "$W"/{x,log,prefix,kinc}
P=$W/prefix
mkdir -p "$P/lib/pkgconfig"

( cd "$SRC" && for f in zlib-1.3.1.tar.gz pcre2-10.44.tar.bz2 libffi-3.4.6.tar.gz expat-2.6.3.tar.xz pixman-0.43.4.tar.gz freetype-2.13.3.tar.xz wayland-1.23.1.tar.xz \
    wayland-protocols-1.38.tar.xz libxkbcommon-1.7.0.tar.xz fontconfig-2.15.0.tar.xz fribidi-1.0.16.tar.xz glib-2.82.2.tar.xz harfbuzz-10.0.1.tar.xz cairo-1.18.2.tar.xz \
    pango-1.54.0.tar.xz gdk-pixbuf-2.42.12.tar.xz graphene-1.10.8.tar.gz libepoxy-1.5.10.tar.gz gtk-4.16.3.tar.xz; do grep " $f\$" SHA256SUMS.txt; done | sha256sum -c - >/dev/null ) \
    || { echo "build-gtk-stones: sha256 mismatch or missing source in $SRC"; exit 1; }
( cd "$SRC" && grep ' gtk-subprojects/' SHA256SUMS.txt | sha256sum -c - >/dev/null ) || { echo "build-gtk-stones: sha256 mismatch in gtk-subprojects"; exit 1; }

if command -v meson >/dev/null && [ "$(meson --version | cut -d. -f1)" -ge 1 ]; then MESON=meson; else
    python3 -m venv "$W/venv" && "$W/venv/bin/pip" install -q meson && MESON=$W/venv/bin/meson
fi
ln -sfn /usr/include/linux "$W/kinc/linux"; ln -sfn /usr/include/asm-generic "$W/kinc/asm-generic"; ln -sfn /usr/include/x86_64-linux-gnu/asm "$W/kinc/asm"
export CC=musl-gcc CFLAGS="-O2 -fPIC -isystem $W/kinc" CPPFLAGS="-isystem $W/kinc"
export PKG_CONFIG_LIBDIR="$P/lib/pkgconfig:$P/share/pkgconfig" PKG_CONFIG_PATH=
export PATH="$P/bin:$PATH" LDFLAGS="-Wl,-rpath,$P/lib -L$P/lib"

unpack() { mkdir -p "$W/x/$1"; tar xf "$SRC/$2" -C "$W/x/$1" --strip-components=1; }
step() { local n=$1; shift; echo "== $n =="; [ -e "$W/log/$n.ok" ] && { echo "(done before)"; return 0; }; if ! ( "$@" ) >"$W/log/$n.log" 2>&1; then echo "FAILED: $n"; tail -n 40 "$W/log/$n.log"; exit 1; fi; touch "$W/log/$n.ok"; }
mesonb() { local n=$1; shift
    ( cd "$W/x/$n" && "$MESON" setup b --prefix="$P" --libdir=lib --buildtype=release -Ddefault_library=shared "$@" && ninja -C b -j"$J" && ninja -C b install ) }
cmakeb() { local n=$1; shift
    ( cd "$W/x/$n" && cmake -S . -B b -G Ninja -DCMAKE_INSTALL_PREFIX="$P" -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=musl-gcc \
        -DCMAKE_C_FLAGS="$CFLAGS" -DBUILD_SHARED_LIBS=ON -DCMAKE_INSTALL_RPATH="$P/lib" "$@" && ninja -C b -j"$J" && ninja -C b install ) }

unpack zlib zlib-1.3.1.tar.gz; unpack pcre2 pcre2-10.44.tar.bz2; unpack libffi libffi-3.4.6.tar.gz; unpack expat expat-2.6.3.tar.xz; unpack pixman pixman-0.43.4.tar.gz
unpack freetype freetype-2.13.3.tar.xz; unpack wayland wayland-1.23.1.tar.xz; unpack wlproto wayland-protocols-1.38.tar.xz; unpack xkbcommon libxkbcommon-1.7.0.tar.xz
unpack fontconfig fontconfig-2.15.0.tar.xz; unpack fribidi fribidi-1.0.16.tar.xz; unpack glib glib-2.82.2.tar.xz; unpack harfbuzz harfbuzz-10.0.1.tar.xz
unpack cairo cairo-1.18.2.tar.xz; unpack pango pango-1.54.0.tar.xz; unpack pixbuf gdk-pixbuf-2.42.12.tar.xz; unpack graphene graphene-1.10.8.tar.gz
unpack epoxy libepoxy-1.5.10.tar.gz; unpack gtk gtk-4.16.3.tar.xz
mkdir -p "$W/x/png" "$W/x/jpeg" "$W/x/tiff"
tar xf "$SRC/gtk-subprojects/libpng-1.6.37.tar.gz" -C "$W/x/png" --strip-components=1
tar xf "$SRC/gtk-subprojects/libjpeg-turbo-2.1.3.tar.gz" -C "$W/x/jpeg" --strip-components=1
tar xf "$SRC/gtk-subprojects/tiff-4.1.0.tar.gz" -C "$W/x/tiff" --strip-components=1

step zlib bash -c "cd '$W/x/zlib' && ./configure --prefix='$P' --libdir='$P/lib' && make -j$J && make install && rm -f '$P/lib/libz.a'"
step pcre2 bash -c "cd '$W/x/pcre2' && ./configure --prefix='$P' --libdir='$P/lib' --enable-shared --disable-static --enable-pcre2-16=no --enable-pcre2-32=no --disable-pcre2grep-libz --disable-pcre2grep-libbz2 && make -j$J && make install"
step libffi bash -c "cd '$W/x/libffi' && ./configure --prefix='$P' --libdir='$P/lib' --enable-shared --disable-static --disable-docs --disable-multi-os-directory && make -j$J && make install"
step expat bash -c "cd '$W/x/expat' && ./configure --prefix='$P' --libdir='$P/lib' --enable-shared --disable-static --without-docs --without-examples --without-tests --without-xmlwf && make -j$J && make install"
step pixman mesonb pixman -Dgtk=disabled -Dlibpng=disabled -Dtests=disabled -Ddemos=disabled -Dopenmp=disabled -Dtls=disabled
step freetype mesonb freetype -Dzlib=disabled -Dbzip2=disabled -Dpng=disabled -Dharfbuzz=disabled -Dbrotli=disabled -Dtests=disabled
step wayland mesonb wayland -Dlibraries=true -Dscanner=true -Dtests=false -Ddocumentation=false -Ddtd_validation=false
step wlproto mesonb wlproto -Dtests=false
step xkbcommon mesonb xkbcommon -Denable-x11=false -Denable-wayland=false -Denable-docs=false -Denable-tools=false -Denable-xkbregistry=false \
    -Denable-bash-completion=false -Dxkb-config-root=/usr/share/X11/xkb -Dx-locale-root=/usr/share/X11/locale
step fontconfig bash -c "cd '$W/x/fontconfig' && '$MESON' setup b --prefix='$P' --libdir=lib --sysconfdir=/etc --localstatedir=/var --buildtype=release -Ddefault_library=shared \
    -Dtests=disabled -Dtools=disabled -Ddoc=disabled -Dnls=disabled -Dcache-build=disabled -Ddefault-fonts-dirs=/usr/share/fonts \
    && ninja -C b -j$J && DESTDIR='$W/fcroot' ninja -C b install && cp -a '$W/fcroot$P/.' '$P/'"
step fribidi mesonb fribidi -Ddocs=false -Dtests=false -Dbin=false
step glib mesonb glib -Dtests=false -Dnls=disabled -Dlibmount=disabled -Dselinux=disabled -Dxattr=false -Dman-pages=disabled -Ddocumentation=false -Dintrospection=disabled \
    -Dlibelf=disabled -Dsysprof=disabled -Ddtrace=disabled -Dsystemtap=disabled -Dglib_debug=disabled -Dinstalled_tests=false
step harfbuzz mesonb harfbuzz -Dtests=disabled -Ddocs=disabled -Dbenchmark=disabled -Dglib=enabled -Dgobject=enabled -Dfreetype=enabled -Dcairo=disabled -Dicu=disabled -Dintrospection=disabled -Dutilities=disabled
step cairo mesonb cairo -Dtests=disabled -Dxlib=disabled -Dxcb=disabled -Dzlib=enabled -Dpng=disabled -Dfreetype=enabled -Dfontconfig=enabled -Dglib=enabled -Dspectre=disabled -Dsymbol-lookup=disabled -Dgtk2-utils=disabled
step pango mesonb pango -Dintrospection=disabled -Dgtk_doc=false -Dbuild-testsuite=false -Dbuild-examples=false -Dfontconfig=enabled -Dcairo=enabled -Dxft=disabled
step libpng cmakeb png -DPNG_STATIC=OFF -DPNG_TESTS=OFF -DPNG_EXECUTABLES=OFF -DPNG_ARM_NEON=off
step libjpeg cmakeb jpeg -DENABLE_STATIC=OFF -DWITH_TURBOJPEG=OFF -DWITH_JAVA=OFF -DENABLE_SHARED=ON -DCMAKE_ASM_NASM_COMPILER=nasm
step libtiff cmakeb tiff -Dcxx=OFF -Dlzma=OFF -Dzstd=OFF -Dwebp=OFF -Djbig=OFF -Dold-jpeg=OFF -Djpeg12=OFF -Dpixarlog=OFF -Dlerc=OFF -Dtiff-tools=OFF -Dtiff-tests=OFF -Dtiff-contrib=OFF -Dtiff-docs=OFF
step pixbuf mesonb pixbuf -Dpng=enabled -Djpeg=enabled -Dtiff=disabled -Dothers=disabled -Dbuiltin_loaders=all -Dgio_sniffing=false -Dintrospection=disabled -Dman=false -Dtests=false -Dinstalled_tests=false -Drelocatable=false
step graphene mesonb graphene -Dtests=false -Dgobject_types=true -Dintrospection=disabled -Dinstalled_tests=false -Darm_neon=false
step epoxy mesonb epoxy -Dtests=false -Degl=yes -Dglx=no -Dx11=false
step gtk mesonb gtk -Dx11-backend=false -Dwayland-backend=true -Dbroadway-backend=false -Dmedia-gstreamer=disabled -Dprint-cups=disabled -Dvulkan=disabled -Dcloudproviders=disabled \
    -Dsysprof=disabled -Dtracker=disabled -Dcolord=disabled -Dintrospection=disabled -Ddocumentation=false -Dman-pages=false -Dbuild-demos=false -Dbuild-testsuite=false \
    -Dbuild-examples=false -Dbuild-tests=false -Df16c=disabled -Dscreenshots=false

echo "== probes =="
for n in glib_hello gtk4_hello; do
    case $n in glib_hello) pk="glib-2.0 gio-2.0 gio-unix-2.0";; *) pk="gtk4";; esac
    # shellcheck disable=SC2046
    musl-gcc -O2 -o "$W/$n" "$HERE/gtk/$n.c" $(pkg-config --cflags $pk) $(pkg-config --libs $pk) -Wl,-rpath,/usr/lib
done

echo "== collect =="
G=$OUT/gtk; rm -rf "$G"; mkdir -p "$G/lib"
cp "$W/glib_hello" "$G/glib-hello"; cp "$W/gtk4_hello" "$G/gtk4-hello"
: > "$G/manifest.txt"
echo "/usr/bin/glib-hello=$G/glib-hello" >> "$G/manifest.txt"; echo "/usr/bin/gtk4-hello=$G/gtk4-hello" >> "$G/manifest.txt"
declare -A seen
collect() { # walk DT_NEEDED
    local f=$1 n r
    for n in $(readelf -d "$f" 2>/dev/null | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p'); do
        [ -z "${seen[$n]:-}" ] || continue
        case $n in libc.musl-x86_64.so.1|ld-musl-x86_64.so.1) continue;; esac
        r=$(readlink -f "$P/lib/$n" 2>/dev/null || true)
        [ -f "$r" ] || { echo "collect: $n not found in prefix (needed by $f)"; continue; }
        seen[$n]=1
        strip --strip-unneeded -o "$G/lib/$n" "$r" 2>/dev/null || cp "$r" "$G/lib/$n"
        echo "/usr/lib/$n=$G/lib/$n" >> "$G/manifest.txt"
        collect "$G/lib/$n"
    done
}
collect "$G/glib-hello"; collect "$G/gtk4-hello"
# runtime data: gsettings schemas, fontconfig config, a font, xkb data come from the foot stones / image builder
mkdir -p "$G/data"
glib-compile-schemas --targetdir="$G/data" "$P/share/glib-2.0/schemas" 2>/dev/null && echo "/usr/share/glib-2.0/schemas/gschemas.compiled=$G/data/gschemas.compiled" >> "$G/manifest.txt" || true
cp -a /root/stones/foot/etc "$G/" 2>/dev/null || true
echo "gtk stones: $(grep -c . "$G/manifest.txt") manifest lines, $(du -sh "$G" | cut -f1)"
echo "BUILD-GTK-STONES DONE"
