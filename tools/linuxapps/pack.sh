#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
WD=${1:?workdir from prep-firefox.sh}
OUT=${2:-$(mktemp -d)}
mkdir -p "$OUT/pack"
python3 -I tools/linuxapps/hpspec.py "$WD/fxrun/spec.txt" "$OUT/hp.spec" "$PWD/tools/linuxapps/fxrun.sh" > "$OUT/hpspec.log" 2>&1 || { cat "$OUT/hpspec.log"; exit 1; }
mkdir -p "$OUT/km"
python3 tools/wayland/genkeys.py --keymaps "$OUT/km" > "$OUT/keys.log" 2>&1 || { tail -5 "$OUT/keys.log"; exit 1; }
python3 -I tools/linuxapps/hppack.py "$OUT/hp.spec" "$OUT/pack" --base-spec "$WD/fxrun/spec.txt" \
    --extra "/var/xfx/profile/user.js=$PWD/assets/xfx/user.js@644" \
    --extra "/usr/share/wayd/keymap-us.xkb=$OUT/km/keymap-us.xkb@644" --extra "/usr/share/wayd/keymap-de.xkb=$OUT/km/keymap-de.xkb@644" > "$OUT/pack.log" 2>&1 || { cat "$OUT/pack.log"; exit 1; }
cat "$OUT/pack.log"
export SPEC="$OUT/pack/base.spec" GUI=1 GUI_EXTRA=tar DRIVE=ahci
export EXTRA="/firefox.tar=$OUT/pack/firefox.tar@644 /etc/fx3.sh=$PWD/tools/linuxapps/guest-fx3-window.sh@755"
export KARGS="gfx disp wm wmdauer wmshell osum vfs bus fremdtrace script=sh /etc/fx.sh;exit"
export BLOCKS=${BLOCKS:-2400000} TMO=${TMO:-2400} INODES=${INODES:-8192}
bash tools/linuxapps/run.sh "$WD" tools/linuxapps/guest-fx5-pack.sh "$OUT/run" > "$OUT/run.log" 2>&1
verdict=$(python3 -I tools/linuxapps/f5check.py "$OUT/run/ser.clean" 2>&1)
grep -a "FXPACK" "$OUT/run/ser.clean" | head -5
echo "PACK-GATE: $verdict"
[ "${verdict%% *}" = green ]
