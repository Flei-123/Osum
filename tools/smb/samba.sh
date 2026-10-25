#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
SMB_PREFIX=${SMB_PREFIX:-}
SMB_BIND=${SMB_BIND:-127.0.0.1}
SMB_MIN=${SMB_MIN:-SMB2_02}
SMB_MAX=${SMB_MAX:-SMB3_11}
SMB_USER=${SMB_USER:-gateuser}
SMB_PASS=${SMB_PASS:-gatepass}
SMB_EXTRA=${SMB_EXTRA:-}
SMB_SHARES=${SMB_SHARES:-}
SMBPID=""

samba_setup() {
    SMB_D=$1
    SMB_PORT=${2:-$(( 20000 + RANDOM % 20000 ))}
    SHARE="$SMB_D/share"
    SMB_NCAL=$(mktemp -d /tmp/sn.XXXXXX)
    mkdir -p "$SHARE/sub" "$SMB_D/priv" "$SMB_D/lock" "$SMB_D/state" "$SMB_D/cache"
    chmod 755 "$SMB_D"; chmod 777 "$SHARE" "$SHARE/sub"
    echo "hello world" > "$SHARE/hello.txt"
    head -c 300000 /dev/urandom > "$SHARE/big.bin"
    echo "nobody = $SMB_USER" > "$SMB_D/usermap"
}

samba_conf() {
cat > "$SMB_D/smb.conf" <<CONF
[global]
workgroup = TESTGRP
interfaces = $SMB_BIND
bind interfaces only = yes
smb ports = $SMB_PORT
disable netbios = yes
load printers = no
printing = bsd
printcap name = /dev/null
disable spoolss = yes
log file = $SMB_D/log.%m
private dir = $SMB_D/priv
lock directory = $SMB_D/lock
state directory = $SMB_D/state
cache directory = $SMB_D/cache
ncalrpc dir = $SMB_NCAL
pid directory = $SMB_D/lock
passdb backend = tdbsam:$SMB_D/priv/passdb.tdb
username map = $SMB_D/usermap
server min protocol = $SMB_MIN
server max protocol = $SMB_MAX
map to guest = never
server signing = $1
$SMB_EXTRA
[data]
path = $SHARE
read only = no
force user = root
$SMB_SHARES
CONF
}

samba_user() {
    printf '%s\n%s\n' "$SMB_PASS" "$SMB_PASS" | smbpasswd -c "$SMB_D/smb.conf" -a -s nobody >/dev/null 2>&1
}

samba_stop() {
    [ -n "$SMBPID" ] && kill "$SMBPID" 2>/dev/null && wait "$SMBPID" 2>/dev/null
    SMBPID=""
    [ -n "${SMB_D:-}" ] && for helper in $(pgrep -f "configfile=$SMB_D/smb.conf" 2>/dev/null); do kill "$helper" 2>/dev/null; done
    [ -n "${SMB_NCAL:-}" ] && rm -rf "$SMB_NCAL"
}

samba_start() {
    samba_stop
    mkdir -p "$SMB_NCAL"
    samba_conf "$1"
    TMPDIR=/tmp setsid $SMB_PREFIX smbd -s "$SMB_D/smb.conf" -F --no-process-group > "$SMB_D/smbd.out" 2>&1 < /dev/null &
    SMBPID=$!
    for _ in $(seq 1 50); do
        $SMB_PREFIX ss -ltn 2>/dev/null | grep -q ":$SMB_PORT " && return 0
        sleep 0.2
    done
    return 1
}
