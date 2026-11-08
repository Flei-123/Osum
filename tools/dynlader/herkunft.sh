#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."

LDSO=${LDSO:-/lib/ld-musl-x86_64.so.1}
BBDYN=${BBDYN:-/root/bbdyn/busybox}
BBQUELLE=${BBQUELLE:-/root/fremdquellen/busybox-1.36.1.tar.bz2}

echo "=================================================================="
echo " FOREIGN CODE OF THE DYNLOADER ROUND -- origin, version, license"
echo "=================================================================="
echo
echo "1. THE INTERPRETER  (required -- without it no PT_INTERP image runs)"
echo "   Package:   linux-abi        Target on the system: /lib/ld-musl-x86_64.so.1"
echo "   Ring:      3                (like every program; NOT in the kernel)"
echo "   Herkunft:  musl libc, https://musl.libc.org/"
if command -v dpkg >/dev/null 2>&1 && dpkg -s musl >/dev/null 2>&1; then
    echo "   Fassung:   $(dpkg -s musl | sed -n 's/^Version: //p')  (Debian-Paket musl:amd64)"
fi
echo "   License:   MIT -- Copyright 2005-2020 Rich Felker and contributors"
echo "   Form:      FERTIGE BINAERDATEI, unveraendert uebernommen."
if [ -r "$LDSO" ]; then
    R=$(readlink -f "$LDSO")
    echo "   Datei:     $R"
    echo "   Groesse:   $(stat -c%s "$R") Oktette"
    echo "   SHA-256:   $(sha256sum "$R" | cut -d' ' -f1)"
    echo "   Note:      the same file IS libc.so -- so it brings"
    echo "              dlopen/dlsym along without anything being added."
else
    echo "   File:      NOT PRESENT ($LDSO)"
fi
echo
echo "2. THE TARGET SOFTWARE  (optional -- only needed to measure the round)"
echo "   Package:   busybox          Target on the system: /bin/busybox"
echo "   Ring:      3"
echo "   Herkunft:  BusyBox, https://busybox.net/"
echo "   Fassung:   1.36.1"
echo "   Lizenz:    GPL-2.0-only"
echo "   Form:      QUELLTEXT unveraendert, HIER gebaut (musl-gcc,"
echo "              CONFIG_STATIC off). The binary artifact is ours,"
echo "              the source is foreign."
if [ -r "$BBQUELLE" ]; then
    echo "   Quelle:    $BBQUELLE"
    echo "   SHA-256:   $(sha256sum "$BBQUELLE" | cut -d' ' -f1)"
    if [ -r /root/fremdquellen/SHA256SUMS.txt ]; then
        SOLL=$(grep 'busybox-1.36.1.tar.bz2' /root/fremdquellen/SHA256SUMS.txt | cut -d' ' -f1)
        IST=$(sha256sum "$BBQUELLE" | cut -d' ' -f1)
        [ "$SOLL" = "$IST" ] \
            && echo "   Abgleich:  stimmt mit /root/fremdquellen/SHA256SUMS.txt ueberein" \
            || echo "   Abgleich:  WEICHT AB von SHA256SUMS.txt -- nachsehen!"
    fi
fi
if [ -r "$BBDYN" ]; then
    echo "   Binaer:    $BBDYN ($(stat -c%s "$BBDYN") Oktette)"
    echo "   SHA-256:   $(sha256sum "$BBDYN" | cut -d' ' -f1)"
fi
echo
echo "3. WHAT IS OURS"
echo "   kernel/ldr/elf.fi -- the only kernel file this round touches."
BASE=$(git merge-base main dynlader 2>/dev/null || echo "")
if [ -n "$BASE" ]; then
    git diff --numstat "$BASE"..dynlader -- kernel/ 2>/dev/null \
        | awk '{printf "   %-22s +%s -%s Zeilen\n", $3, $1, $2}'
    ZU=$(git diff "$BASE"..dynlader -- kernel/ldr/elf.fi | grep '^+' | grep -v '^+++' | wc -l)
    COMMENT_N=$(git diff "$BASE"..dynlader -- kernel/ldr/elf.fi | grep '^+' | grep -v '^+++' \
          | sed 's/^+//' | grep -cE '^\s*//')
    EMPTY_N=$(git diff "$BASE"..dynlader -- kernel/ldr/elf.fi | grep '^+' | grep -v '^+++' \
          | sed 's/^+//' | grep -cE '^\s*$')
    echo "   of which comment: $COMMENT_N, empty: $EMPTY_N, real CODE: $((ZU - COMMENT_N - EMPTY_N))"
fi
echo "   Not one line of foreign code in the kernel. No adopted ld.so,"
echo "   no copied relocation code -- the foreign loader is"
echo "   BENUTZT, nicht nachgebaut."
echo
echo "4. WHAT IS IN THE BASE IMAGE"
. "$(dirname "${BASH_SOURCE[0]}")/baseimage.sh"
if base_image_has_musl; then
    echo "   WARNING: tools/usbimg/build.sh puts ld-musl into the public image."
    echo "   That contradicts rule 3."
else
    echo "   The public image carries none of it. tools/usbimg/build.sh names"
    echo "   ld-musl and a dynamic busybox only behind BBSH=1, which is on by"
    echo "   default for the personal profile only; both otherwise come as a"
    echo "   package (.opk)."
fi
echo
echo "=================================================================="
