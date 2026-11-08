#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
chk() { if [ "$1" = 1 ]; then ok "$2"; else bad "$2"; fi; }

TOOLS=${XR_TOOLS:-/root/jarvis/data/orientos-xremote}
HOSTBIN=${XR_HOST:-$TOOLS/v2/freeviewer-host}
LIBS=${XR_LIBS_DIR:-/root/fxhp/fx-root}
OPK=${OPK:-$(python3 tools/lib/opkpfad.py)}
for f in "$HOSTBIN" "$LIBS/lib/ld-musl-x86_64.so.1" "$LIBS/usr/lib/libgcc_s.so.1" "$OPK"; do
    [ -e "$f" ] || { echo "XRPACKAGE: skipped, $f missing"; exit 0; }
done

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

stage() {
    local dir=$1
    mkdir -p "$dir/bau"
    cp pakete/xremote/INFO pakete/xremote/rezept "$dir/"
    cp "$HOSTBIN" "$dir/bau/freeviewer-host"
    cp "$LIBS/lib/ld-musl-x86_64.so.1" "$dir/bau/ld-musl-x86_64.so.1"
    cp "$LIBS/usr/lib/libgcc_s.so.1" "$dir/bau/libgcc_s.so.1"
    python3 tools/k15/icon.py pakete/xremote/symbol.txt "$dir/bau/symbol" > /dev/null
}

echo "== 1. metadata =="
python3 tools/sdk/osdk.py check pakete/xremote/INFO --strict > "$T/osdk.txt" 2>&1
chk $([ $? = 0 ] && echo 1 || echo 0) "INFO passes osdk --strict"
net_declared() { grep -qx 'perm=net' "$1" && grep -qx 'net=real' "$1"; }
net_declared pakete/xremote/INFO && ok "INFO declares perm=net and net=real" || bad "INFO misses the net declaration"
grep -qx 'id=com.fleitec.xremote' pakete/xremote/INFO && ok "INFO id is com.fleitec.xremote" || bad "INFO id differs"
[ -s pakete/xremote/symbol.txt ] && ok "the Store icon source exists" || bad "no symbol.txt"

echo "== 2. package build and install layout =="
stage "$T/pkg"
OUTD="$T/out"; mkdir -p "$OUTD"
(cd "$T/pkg" && python3 "$OPK" bauen rezept -o "$OUTD/xremote.opk") > "$T/build.txt" 2>&1
[ -s "$OUTD/xremote.opk" ] && ok "opk builds from the recipe" || { bad "opk build failed"; head -5 "$T/build.txt"; }
python3 "$OPK" zeigen "$OUTD/xremote.opk" > "$T/show.txt" 2>&1
for f in INFO bin/freeviewer-host lib/ld-musl-x86_64.so.1 lib/libgcc_s.so.1 symbol; do
    grep -qE "^  f $f " "$T/show.txt" && ok "package holds $f" || bad "package misses $f"
done
mkdir -p "$T/root"
python3 "$OPK" installieren --wurzel "$T/root" "$OUTD/xremote.opk" > "$T/inst.txt" 2>&1
APPDIR=$T/root/apps/xremote.osp
[ -f "$APPDIR/bin/freeviewer-host" ] && ok "install puts the host at /apps/xremote.osp/bin" || bad "host not at /apps/xremote.osp/bin"
[ -f "$APPDIR/lib/ld-musl-x86_64.so.1" ] && ok "install puts the loader at /apps/xremote.osp/lib" || bad "loader not at /apps/xremote.osp/lib"
HOSTPATH=$(sed -n 's/^static mut P_HOST: .*= "\(.*\)\\0"$/\1/p' kernel/user/xrpath.fi)
[ "$HOSTPATH" = "/apps/xremote.osp/bin/freeviewer-host" ] && ok "xremoted looks where the installer puts the host" || bad "xremoted host path is $HOSTPATH"
LDPATH=$(sed -n 's/^static mut P_LD: .*= "\(.*\)\\0"$/\1/p' kernel/user/xrpath.fi)
[ "$LDPATH" = "/apps/xremote.osp/lib/ld-musl-x86_64.so.1" ] && ok "xremoted looks where the installer puts the loader" || bad "xremoted loader path is $LDPATH"
grep -q 'chmod' kernel/user/xrhost.fi && ok "xremoted makes the package files executable (the installer writes 0644)" || bad "xremoted never chmods the host"

echo "== 3. counter-probes =="
stage "$T/mut1"
sed -i 's/^info=.*/info=Let another device see and control this computer through the FreeViewer relay with a one-time password/' "$T/mut1/INFO"
python3 tools/sdk/osdk.py check "$T/mut1/INFO" --strict > /dev/null 2>&1 && bad "a 100-character info passes the lint" || ok "a too long info is refused by the lint"
stage "$T/mut2"
sed -i '/^perm=net$/d' "$T/mut2/INFO"
net_declared "$T/mut2/INFO" && bad "a manifest without perm=net passes the net check" || ok "a manifest without perm=net fails the net check"
grep -E '^  f bin/freeviewer-host +644 ' "$T/show.txt" > /dev/null && ok "the installer writes the host as 0644 (so xremoted must chmod)" || bad "host mode in the package changed"

echo "XRPACKAGE: $pass passed, $fail failed"
[ "$fail" = 0 ]
