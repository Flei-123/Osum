#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
build_kernel() { # build_kernel <srcdir> <out.mb>
    ( cd "$1" && bash tools/build-kernel.sh "$2" --stufe 1 ) > "$2.log" 2>&1
}
build_image() { # build_image <srcdir> <outdir>   (user programs of the system + our tests)
    local S=$1 O=$2
    mkdir -p "$O/p"
    as --64 -o "$O/crt.o" "$S/kernel/user/crt.s" || return 1
    local progs="sh ls cat echo"
    for p in $progs; do
        "$FIRNC1" "$S/kernel/user/$p.fi" -o "$O/p/$p.o" > "$O/p/$p.log" 2>&1 || return 1
        ld -T "$S/kernel/user/user.ld" --defsym=USER_ENTRY="_F1.u_start" -o "$O/p/$p.elf" "$O/crt.o" "$O/p/$p.o" 2>>"$O/p/$p.log" || return 1
        strip --strip-all "$O/p/$p.elf" 2>/dev/null
    done
    local spec="/lib/ /bin/ /tmp/ /etc/ /var/ /var/tmp/ /dev/ /proc/ /sys/ /mnt/ /root/ /run/ /w/"
    for p in $progs; do spec="$spec /bin/$p=$O/p/$p.elf"; done
    spec="$spec /lib/ld-musl-x86_64.so.1=$LDREAL"
    # the proof stone busybox (dynamic, musl): as /bin/busybox (t_proc points /bin/sh at it for system() and popen())
    if [ -r "${BBDYN:-/nonexistent}" ]; then
        spec="$spec /bin/busybox=$BBDYN /etc/bb.sh=$D/bb.sh /etc/pruef.txt=$D/pruef.txt"
    fi
    for f in "$D"/bin/*; do spec="$spec /bin/$(basename $f)=$f"; done
    for f in "$D"/lib/*.so; do [ -e "$f" ] && spec="$spec /lib/$(basename $f)=$f"; done
    printf 'root:x:0:0:root:/root:/bin/sh\n' > "$D/passwd"; printf '127.0.0.1 localhost\n' > "$D/hosts"
    spec="$spec /etc/passwd=$D/passwd /etc/hosts=$D/hosts"
    # the files and directories a Linux package set puts under /etc and /usr/share (not kernel business; the real image
    # builder tools/usbimg/build.sh does not ship them yet -- roadmap): stat() by name is what the checks measure.
    printf 'nameserver 10.0.2.3\n' > "$D/resolv.conf"; printf '0123456789abcdef0123456789abcdef\n' > "$D/machine-id"
    printf '<?xml version="1.0"?>\n<fontconfig></fontconfig>\n' > "$D/fonts.conf"; printf 'UTC\n' > "$D/localtime"
    spec="$spec /etc/ssl/ /etc/ssl/certs/ /etc/fonts/ /usr/ /usr/lib/ /usr/share/ /usr/share/fonts/ /usr/share/zoneinfo/"
    spec="$spec /etc/resolv.conf=$D/resolv.conf /etc/machine-id=$D/machine-id /etc/fonts/fonts.conf=$D/fonts.conf /etc/localtime=$D/localtime"
    spec="$spec ${EXTRA_SPEC:-}"
    bash "$S/tools/mkfsfi/mkfs.sh" build "$O/disk.img" ${UB_BLOCKS:-98304} --v3 --inodes=1024 ${UB_MKFSX:-} $spec > "$O/mkfs.txt" 2>&1
}
boot() { # boot <kernel> <disk> <script> <serial-out>
    cp -f "$2" "$2.live"
    local drive=(-drive "file=$2.live,format=raw,if=ide,index=0${UB_DRIVEX:-}")
    [ "${UB_DRIVE:-ide}" = ahci ] && drive=(-device ahci,id=ahci -drive "file=$2.live,format=raw,if=none,id=d0${UB_DRIVEX:-}" -device ide-hd,drive=d0,bus=ahci.0)
    timeout "$TMO" $QEMU "${KVM[@]}" -smp "$SMP" -kernel "$1" -m 512 \
        -append "osum vfs nokbd nosched noproc nofs ${KARGS:-} script=$3;exit" -serial "file:$4" -display none -no-reboot \
        ${NETARGS:-} "${drive[@]}" -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    local rc=$?; rm -f "$2.live"; return $rc
}
stones_spec() { # stones_spec <stonesdir>
    local STONES=$1 so SX
    SX="/usr/bin/ /usr/lib/python3.12/ /usr/lib/python3.12/lib-dynload/ /w/"
    [ -r "$STONES/python3" ] && SX="$SX /usr/bin/python3=$STONES/python3 /usr/lib/python312.zip=$STONES/lib/python312.zip"
    [ -r "$STONES/lib/os.pyc" ] && SX="$SX /usr/lib/python3.12/os.pyc=$STONES/lib/os.pyc"
    for so in "$STONES"/lib/ext/*.so; do [ -e "$so" ] && SX="$SX /usr/lib/python3.12/lib-dynload/$(basename "$so")=$so"; done
    [ -r "$STONES/curl" ] && SX="$SX /bin/curl=$STONES/curl"
    [ -r "$STONES/git" ] && SX="$SX /bin/git=$STONES/git /share/ /share/git-core/ /share/git-core/templates/"
    echo "$SX"
}
