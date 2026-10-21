#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/linuxapps/prep-firefox.sh <workdir> -- Alpine root + `apk add firefox` (chroot on the server), Linux strace reference (bwrap), mkroot spec.
# Needs net, bwrap, strace, /root/fremdquellen/alpine-minirootfs-3.24.2-x86_64.tar.gz. Result: <workdir>/fx-root, fxver.files, fxshot.files, fxrun/spec.txt
set -uo pipefail
WD=${1:?workdir}; HERE=$(cd "$(dirname "$0")" && pwd); mkdir -p "$WD/fx-root" "$WD/fxrun"; cd "$WD"
tar -xzf /root/fremdquellen/alpine-minirootfs-3.24.2-x86_64.tar.gz -C fx-root && cp /etc/resolv.conf fx-root/etc/resolv.conf
timeout 900 chroot fx-root /sbin/apk add --no-cache firefox font-dejavu > apk-fx.log 2>&1 || { tail -3 apk-fx.log; exit 1; }
if [ -z "${FX_KEEP_SCUDO:-}" ]; then
    # scudo's static arena spans 256 MiB; the 288 MiB mmap arena of Osum cannot hold it plus libxul, so the guest root gets an empty libscudo.so (musl malloc is used) until mmap is lazy and the window larger
    mkdir -p scudo-stub && echo 'int scudo_stub_marker = 1;' > scudo-stub/s.c
    cp fx-root/usr/lib/libscudo.so scudo-stub/libscudo.so.orig
    gcc -shared -nostdlib -fPIC -o fx-root/usr/lib/libscudo.so scudo-stub/s.c -Wl,-soname,libscudo.so || { echo "prep: stub build failed"; exit 1; }
fi
cat > bwfx.sh <<EOB
#!/bin/bash
exec bwrap --bind "$WD/fx-root" / --proc /proc --dev /dev --tmpfs /tmp --unshare-pid --unshare-net --die-with-parent --setenv HOME /root --setenv XDG_RUNTIME_DIR /tmp --setenv MOZ_DISABLE_CONTENT_SANDBOX 1 "\$@"
EOB
chmod +x bwfx.sh
timeout 50 strace -f -qq -o fxver.strace -s 80 ./bwfx.sh /usr/bin/firefox --version
timeout 100 strace -f -qq -o fxshot.strace -s 80 ./bwfx.sh /usr/bin/firefox --headless --screenshot /tmp/x.png --profile /tmp/p about:blank
for n in fxver fxshot; do python3 -I "$HERE/straceset.py" $n.strace --after /usr/bin/firefox --files $n.files --top 30 > $n.summary.txt; done
python3 -I "$HERE/mkroot.py" fx-root fxrun/spec.txt --base --files fxver.files --files fxshot.files --tree /usr/lib/firefox --tree /usr/share/fonts \
  --tree /usr/share/fontconfig --tree /usr/share/icu --tree /usr/share/X11/xkb --tree /usr/share/glib-2.0 --tree /var/cache/fontconfig \
  --skip /usr/lib/libLLVM.so.22.1 --skip /usr/lib/libgallium-26.1.6.so
