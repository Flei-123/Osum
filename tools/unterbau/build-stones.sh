#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/unterbau/build-stones.sh -- build the proof stones (busybox full, python3, curl, git) with musl-gcc, dynamic.
#
#   /root/jarvis/bin/heavy bash tools/unterbau/build-stones.sh <outdir> [<workdir>]
#
# <outdir> afterwards holds what tools/unterbau/run.sh wants:
#   STONES=<outdir>  BBDYN=<outdir>/busybox   (python3, lib/python312.zip, lib/os.pyc, lib/ext/*.so, curl, git)
# Sources: busybox from /root/fremdquellen, the rest is downloaded (python.org, curl.se, kernel.org, github zlib).
# Needs: musl-gcc, make, xz, curl. Workdir is removed at the end unless KEEP_WORK=1.
set -euo pipefail
OUT=$(realpath -m "${1:?usage: build-stones.sh <outdir> [workdir]}")
W=${2:-$(mktemp -d)}
[ -n "${KEEP_WORK:-}" ] || trap 'rm -rf "$W"' EXIT
mkdir -p "$OUT/lib/ext" "$W"/{dl,x,prefix}
P=$W/prefix
PYV=3.12.7; CURLV=8.10.1; GITV=2.46.2; ZV=1.3.1
J=${JOBS:-6}
# STONES_ONLY="curl" builds just those stones (names: busybox zlib mbedtls curl git python3); curl needs zlib+mbedtls, empty = all
want() { [ -z "${STONES_ONLY:-}" ] || echo " $STONES_ONLY " | grep -q " $1 "; }
dl() { [ -s "$W/dl/$2" ] || curl -sfL --max-time 300 -o "$W/dl/$2" "$1"; }
if want python3; then dl https://www.python.org/ftp/python/$PYV/Python-$PYV.tar.xz py.tar.xz; else cp /root/fremdquellen/Python-$PYV.tar.xz "$W/dl/py.tar.xz"; fi
dl https://curl.se/download/curl-$CURLV.tar.xz curl.tar.xz
if want git; then dl https://www.kernel.org/pub/software/scm/git/git-$GITV.tar.xz git.tar.xz; else cp /root/fremdquellen/git-$GITV.tar.xz "$W/dl/git.tar.xz"; fi
dl https://github.com/madler/zlib/releases/download/v$ZV/zlib-$ZV.tar.gz zlib.tar.gz
# pinned sha256 of the downloads (also in /root/fremdquellen/SHA256SUMS.txt); a mismatch stops the build
( cd "$W/dl" && sha256sum -c - >/dev/null <<'SUMS'
24887b92e2afd4a2ac602419ad4b596372f67ac9b077190f459aba390faf5550  py.tar.xz
73a4b0e99596a09fa5924a4fb7e4b995a85fda0d18a2c02ab9cf134bebce04ee  curl.tar.xz
5ee8a1c68536094a4f7f9515edc154b12a275b8a57dda4c21ecfbf1afbae2ca3  git.tar.xz
9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23  zlib.tar.gz
SUMS
) || { echo "build-stones: sha256 mismatch in downloads"; exit 1; }
for n in py curl git zlib bb mbed ossl; do mkdir -p "$W/x/$n"; done
tar xJf "$W/dl/py.tar.xz" -C "$W/x/py" --strip-components=1
tar xJf "$W/dl/curl.tar.xz" -C "$W/x/curl" --strip-components=1
tar xJf "$W/dl/git.tar.xz" -C "$W/x/git" --strip-components=1
tar xzf "$W/dl/zlib.tar.gz" -C "$W/x/zlib" --strip-components=1
tar xjf /root/fremdquellen/busybox-1.36.1.tar.bz2 -C "$W/x/bb" --strip-components=1
# openssl 3.0.15 (only for python's _ssl/_hashlib; curl uses the smaller mbedtls)
( cd /root/fremdquellen && grep ' openssl-3.0.15.tar.gz$' SHA256SUMS.txt | sha256sum -c - >/dev/null ) || { echo "build-stones: sha256 mismatch for openssl"; exit 1; }
tar xzf /root/fremdquellen/openssl-3.0.15.tar.gz -C "$W/x/ossl" --strip-components=1
# mbedtls 3.6.2 (TLS stone): from /root/fremdquellen, sha256 pinned
( cd /root/fremdquellen && grep ' mbedtls-3.6.2.tar.bz2$' SHA256SUMS.txt | sha256sum -c - >/dev/null ) || { echo "build-stones: sha256 mismatch for mbedtls"; exit 1; }
tar xjf /root/fremdquellen/mbedtls-3.6.2.tar.bz2 -C "$W/x/mbed" --strip-components=1

want busybox && {
echo "== busybox (defconfig; no tc/hwclock/mtd/ubi: the musl headers lack linux/ and mtd/) =="
( cd "$W/x/bb" && make defconfig >/dev/null 2>&1
  sed -i 's/^CONFIG_TC=y/# CONFIG_TC is not set/;s/^CONFIG_FEATURE_TC_INGRESS=y/# CONFIG_FEATURE_TC_INGRESS is not set/;s/^CONFIG_HWCLOCK=y/# CONFIG_HWCLOCK is not set/;s/^CONFIG_SELINUX=y/# CONFIG_SELINUX is not set/' .config
  for k in NANDWRITE NANDDUMP FLASHCP FLASH_ERASEALL FLASH_LOCK FLASH_UNLOCK UBIATTACH UBIDETACH UBIMKVOL UBIRMVOL UBIRSVOL UBIUPDATEVOL UBIRENAME MTD_INFO; do sed -i "s/^CONFIG_$k=y/# CONFIG_$k is not set/" .config; done
  { yes "" | make oldconfig; } >/dev/null 2>&1 || true
  make -j"$J" CC=musl-gcc HOSTCC=gcc SKIP_STRIP=y >/dev/null 2>&1 && strip -o "$OUT/busybox" busybox )
}

echo "== zlib (static, PIC) =="
( cd "$W/x/zlib" && CC=musl-gcc CFLAGS="-O2 -fPIC" ./configure --prefix="$P" --static >/dev/null && make -j"$J" >/dev/null 2>&1 && make install >/dev/null 2>&1 )

echo "== mbedtls (static, PIC, default config; only the library -- 'make install' would build the programs) =="
( cd "$W/x/mbed" && make -j"$J" CC=musl-gcc CFLAGS="-O2 -fPIC" lib >/dev/null 2>&1 \
  && mkdir -p "$P/include" "$P/lib" && cp -r include/mbedtls include/psa "$P/include/" && cp library/*.a "$P/lib/" )

echo "== curl (static libcurl + mbedtls, https; CA bundle /etc/ssl/roots.pem) =="
( cd "$W/x/curl" && CC=musl-gcc CPPFLAGS="-I$P/include" LDFLAGS="-L$P/lib" ./configure --prefix="$P" --disable-shared --enable-static --with-mbedtls="$P" --with-ca-bundle=/etc/ssl/roots.pem --with-zlib="$P" \
    --disable-ldap --disable-ldaps --disable-rtsp --disable-docs --disable-manual --without-libpsl --without-brotli --without-zstd --without-nghttp2 --without-libidn2 \
    --disable-threaded-resolver --disable-ipv6 >/dev/null 2>&1 && make -j"$J" >/dev/null 2>&1 && strip -o "$OUT/curl" src/curl )

want git && {
echo "== git (no openssl/curl/expat/perl/python/gettext) =="
( cd "$W/x/git" && make -j"$J" CC=musl-gcc NO_OPENSSL=1 NO_CURL=1 NO_EXPAT=1 NO_TCLTCK=1 NO_GETTEXT=1 NO_PERL=1 NO_PYTHON=1 NO_ICONV=1 NO_REGEX=NeedsStartEnd \
    ZLIB_PATH="$P" CFLAGS="-O2 -I$P/include" LDFLAGS="-L$P/lib" prefix=/ git >/dev/null 2>&1 && strip -o "$OUT/git" git )
}

want python3 && {
echo "== openssl (static, PIC, no-asm; no-async/afalgeng: musl lacks ucontext and linux/if_alg.h) =="
( cd "$W/x/ossl" && ./Configure linux-x86_64 no-shared no-asm no-tests no-async no-afalgeng no-engine no-dso no-legacy \
    --prefix="$P" --libdir=lib --openssldir=/etc/ssl CC=musl-gcc CFLAGS="-O2 -fPIC" >/dev/null 2>&1 \
  && make -j"$J" build_libs >/dev/null 2>&1 && make install_dev >/dev/null 2>&1 )
echo "== python3 (musl-gcc wrapper: configure insists multiarch == platform triplet) =="
cat > "$W/mcc" <<'EOS'
#!/bin/sh
for a in "$@"; do [ "$a" = "--print-multiarch" ] && { echo x86_64-linux-musl; exit 0; }; done
exec musl-gcc "$@"
EOS
chmod +x "$W/mcc"
( cd "$W/x/py" && CC="$W/mcc" CFLAGS="-O2" CPPFLAGS="-I$P/include" LDFLAGS="-L$P/lib" ./configure --without-ensurepip --with-openssl="$P" --disable-test-modules --without-doc-strings --disable-ipv6 \
    py_cv_module__lzma=n/a py_cv_module__bz2=n/a py_cv_module__sqlite3=n/a py_cv_module__curses=n/a \
    py_cv_module__curses_panel=n/a py_cv_module_readline=n/a py_cv_module__uuid=n/a py_cv_module__dbm=n/a py_cv_module__gdbm=n/a py_cv_module__tkinter=n/a py_cv_module__ctypes=n/a \
    PKG_CONFIG_LIBDIR=/nonexistent ac_cv_file__dev_ptmx=no ac_cv_file__dev_ptc=no >/dev/null 2>&1 && make -j"$J" >/dev/null 2>&1 )
strip -o "$OUT/python3" "$W/x/py/python"
# stdlib as ONE stored zip of .pyc (the image builder takes files, not trees); os.pyc doubles as the prefix landmark
cp -r "$W/x/py/Lib" "$W/pylib"
( cd "$W/pylib" && rm -rf test idlelib tkinter turtledemo ensurepip lib2to3 pydoc_data site-packages \
  && find . -name __pycache__ -type d -prune -exec rm -rf {} + \
  && "$W/x/py/python" -I -m compileall -q -b . >/dev/null 2>&1; find . -name '*.py' -delete
  "$W/x/py/python" -I - "$OUT/lib/python312.zip" <<'PY'
import os, sys, zipfile
z = zipfile.ZipFile(sys.argv[1], 'w', zipfile.ZIP_STORED)
for r, d, f in os.walk('.'):
    for n in f:
        p = os.path.join(r, n); z.write(p, p[2:])
z.close()
PY
  cp os.pyc "$OUT/lib/os.pyc" )
cp "$W"/x/py/build/lib*/*.cpython-312-x86_64-linux-musl.so "$OUT/lib/ext/"
strip --strip-unneeded "$OUT"/lib/ext/*.so 2>/dev/null || true   # _ssl/_hashlib carry all of libcrypto: 9.5 MB unstripped
}
ls -la "$OUT" "$OUT/lib"
echo "BUILD-STONES DONE"
