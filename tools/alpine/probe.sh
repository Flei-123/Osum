# tools/alpine/probe.sh -- runs INSIDE the guest as an ash script, with the Alpine minirootfs as its root
# (either the image root itself, or after `chroot /alpine`). Every line "AL <name> ok|FAIL [...]" is
# read back from the serial log by tools/alpine/run.sh and compared with tools/alpine/gaps.txt.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
chk() { # chk <name> <expected stdout> <command...>
    n=$1; want=$2; shift 2
    got=$(timeout 40 sh -c "$*" 2>&1)
    if [ "$got" = "$want" ]; then echo "AL $n ok"; else echo "AL $n FAIL [rc=$? got: $(echo "$got" | head -2 | tr '\n' '|' | cut -c1-90)]"; fi
}
ok() { # ok <name> <command...>: only the exit status counts
    n=$1; shift
    o=$(timeout 40 sh -c "$*" 2>&1); rc=$?
    if [ $rc -eq 0 ]; then echo "AL $n ok"; else echo "AL $n FAIL [rc=$rc $(echo "$o" | head -1 | cut -c1-90)]"; fi
}
echo "AL start ok"
# --- chroot (only when run.sh started this script with CHROOTED=1): the jail must really hold
if [ -n "${CHROOTED:-}" ]; then
    chk chroot-pwd "/" 'pwd'
    chk chroot-no-host "gone" '[ -e /alpine ] && echo visible || echo gone'
    chk chroot-dotdot "/bin/busybox" 'readlink /../../../bin/ls'
    chk chroot-abs-symlink "BusyBox v1.3" '/bin/ls --help 2>&1 | head -1 | cut -c1-12'
    chk chroot-etc "3.24.2" 'cat /etc/alpine-release'
fi
# --- the loader and the C library
chk ld-musl "musl libc (x86_64)" '/lib/ld-musl-x86_64.so.1 2>&1 | head -1'
chk libc-link "ld-musl-x86_64.so.1" 'readlink /lib/libc.musl-x86_64.so.1'
chk release-file "3.24.2" 'cat /etc/alpine-release'
chk os-release "Alpine Linux" 'sed -n "s/^NAME=\"\(.*\)\"/\1/p" /etc/os-release'
# --- busybox through absolute symlinks (the applet name is argv[0])
chk bb-link "/bin/busybox" 'readlink /bin/ls'
chk bb-banner "BusyBox v1.3" 'busybox 2>&1 | head -1 | cut -c1-12'
chk ls-applet "/bin/ls" 'ls /bin/ls'
chk cat-applet "ok" 'echo ok > /tmp/c1; cat /tmp/c1'
chk sed "aXc" 'echo abc | sed s/b/X/'
chk sed-inplace "XYZ" 'echo xyz > /tmp/s1; sed -i y/xyz/XYZ/ /tmp/s1; cat /tmp/s1'
chk awk "3" 'echo 1 2 | awk "{print \$1+\$2}"'
chk awk-fs "b" 'echo a:b:c | awk -F: "{print \$2}"'
chk grep "2" 'printf "a\nb\na\n" | grep -c a'
chk grep-E "1" 'echo ab12 | grep -Ec "[0-9]{2}"'
chk egrep-link "/bin/busybox" 'readlink /bin/egrep'
chk sort "c" 'printf "a\nc\nb\n" | sort -r | head -1'
chk uniq "2" 'printf "a\na\nb\n" | uniq | wc -l'
chk wc "3" 'printf "a b c\n" | wc -w'
chk cut "b" 'echo a:b | cut -d: -f2'
chk tr "ABC" 'echo abc | tr a-z A-Z'
chk head-tail "2" 'printf "1\n2\n3\n" | head -n 2 | tail -n 1'
chk find "1" 'mkdir -p /tmp/f1 && touch /tmp/f1/x && find /tmp/f1 -type f | wc -l'
chk xargs "3" 'echo 1 2 3 | xargs -n1 echo | wc -l'
chk cp-mv-rm "ok" 'echo d > /tmp/a; cp /tmp/a /tmp/b && mv /tmp/b /tmp/c && cmp /tmp/a /tmp/c && rm /tmp/c && echo ok'
chk ln-s "d" 'ln -sf /tmp/a /tmp/l1; cat /tmp/l1'
chk ln-hard "d" 'ln /tmp/a /tmp/h1; cat /tmp/h1'
chk stat-mode "600" 'chmod 600 /tmp/a; stat -c %a /tmp/a'
chk id "0" 'id -u'
chk uname "Linux" 'uname -s'
chk uname-m "x86_64" 'uname -m'
chk expr "42" 'expr 6 \* 7'
chk sha256 "5891b5b522d5" 'printf "hello\n" | sha256sum | cut -c1-12'
chk md5 "b1946ac92492" 'printf "hello\n" | md5sum | cut -c1-12'
chk diff "same" 'diff /tmp/a /tmp/a >/dev/null && echo same'
chk du "ok" 'du -s /bin >/dev/null && echo ok'
[ -z "${CHROOTED:-}" ] && chk df "ok" 'df / >/dev/null && echo ok'
chk mktemp "ok" 'mktemp /tmp/xXXXXXX >/dev/null && echo ok'
chk basename "z" 'basename /a/b/z'
chk dirname "/a/b" 'dirname /a/b/z'
chk seq "5" 'seq 1 5 | tail -n 1'
chk printf "007" 'printf %03d 7'
chk env "1" 'env FOO=1 sh -c "echo \$FOO"'
chk hexdump "6162" 'printf ab | hexdump -v -e "/1 \"%02x\""'
chk od "0000000 061 062 012" 'echo 12 | od -b | head -1'
chk date-year "2026" 'date +%Y'
chk sleep "ok" 'sleep 1 && echo ok'
chk test-bracket "y" '[ -x /bin/sh ] && [[ 1 = 1 ]] && echo y'
chk basename-ash "ok" 'f() { echo $(($1 * 2)); }; [ "$(f 21)" = 42 ] && echo ok'
chk heredoc "hd" 'cat <<EOT
hd
EOT'
chk subshell "3" '(exit 3); echo $?'
chk pipe-fail "1" 'false | true; echo 1'
# --- archives
chk gzip-roundtrip "3" 'printf "1\n2\n3\n" | gzip -c | gunzip | wc -l'
chk tar-roundtrip "x" 'mkdir -p /tmp/tt/d && echo x > /tmp/tt/d/f && ln -sf f /tmp/tt/d/l && tar cf /tmp/tt.tar -C /tmp/tt d && mkdir -p /tmp/tx && tar xf /tmp/tt.tar -C /tmp/tx && cat /tmp/tx/d/l'
chk tar-gz "d/f" 'tar czf /tmp/tt.tgz -C /tmp/tt d && tar tzf /tmp/tt.tgz | grep f$ | head -1'
chk bzip2 "ok" 'echo ok | bzip2 -c | bunzip2'
chk unzip-applet "/bin/busybox" 'readlink /usr/bin/unzip'
chk cpio "ok" 'echo f > /tmp/cpf; echo /tmp/cpf | cpio -o -H newc 2>/dev/null | cpio -t 2>/dev/null | head -1 | grep -q tmp/cpf && echo ok'
# --- /proc and /dev
[ -z "${CHROOTED:-}" ] && ok proc-self 'ls /proc/self >/dev/null'
[ -z "${CHROOTED:-}" ] && ok proc-loadavg 'cat /proc/loadavg'
[ -z "${CHROOTED:-}" ] && ok proc-meminfo 'cat /proc/meminfo'
[ -z "${CHROOTED:-}" ] && ok proc-mounts 'cat /proc/mounts'
[ -z "${CHROOTED:-}" ] && chk dev-null "0" 'echo x > /dev/null; echo 0'
[ -z "${CHROOTED:-}" ] && chk dev-zero "16" 'head -c 16 /dev/zero | wc -c'
[ -z "${CHROOTED:-}" ] && chk dev-urandom "16" 'head -c 16 /dev/urandom | wc -c'
[ -z "${CHROOTED:-}" ] && ok dev-tty-stat 'ls -l /dev/tty /dev/null'
[ -z "${CHROOTED:-}" ] && ok free 'free'
ok uptime 'uptime'
[ -z "${CHROOTED:-}" ] && ok mount-list 'mount'
ok hostname 'hostname'
# --- apk (apk-tools 3 from the minirootfs: libapk, libssl, libcrypto, libz)
chk apk-version "apk-tools 3" 'apk --version | cut -c1-11'
ok apk-info 'apk info'
ok apk-info-v 'apk info -v'
chk apk-info-musl "musl" 'apk info | grep -x musl'
ok apk-list-installed 'apk list -I'
ok apk-stats 'apk stats'
chk apk-who "/lib/ld-musl-x86_64.so.1" 'apk info -W /lib/ld-musl-x86_64.so.1 | tr -d "\n" | sed "s/.* owned by .*/\/lib\/ld-musl-x86_64.so.1/"'
ok apk-verify 'apk verify'
ok apk-policy 'apk policy busybox'
# --- apk add from a local mirror (only when run.sh packed one under /repo)
if [ -f /repo/APKINDEX.tar.gz ]; then
    chk apk-add-local "ok" 'apk add --no-network --allow-untrusted --repository /repo tree >/tmp/apk.out 2>&1 && echo ok || { tail -3 /tmp/apk.out | tr "\n" "|"; }'
    ok apk-add-run 'tree --version'
fi
# ps last: busybox ps segfaults (gaps.txt) and must not hide the probes behind it
ok ps 'ps'
echo "AL end ok"
