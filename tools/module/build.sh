#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

AUS=${1:-}
if [[ -z $AUS ]]; then
    sed -n '2,12p' "$0"
    exit 1
fi
shift

STUFE=0
QUELLE=module/ps2mouse.fi
MKARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --stufe) STUFE=$2; shift 2 ;;
        --source|--quelle) QUELLE=$2; shift 2 ;;
        *) MKARGS+=("$1"); shift ;;
    esac
done

bash vendor/firn/fetch-firnc.sh >/dev/null || {
    echo "vendor/firn/fetch-firnc.sh fehlgeschlagen" >&2; exit 1; }
if [[ $STUFE == 0 ]]; then
    FIRNC="$ROOT/vendor/firn/bin/firnc"
else
    FIRNC="$ROOT/vendor/firn/bin/firnc1"
fi
[[ -x $FIRNC ]] || { echo "Uebersetzer fehlt: $FIRNC" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/k/arch"

cp -f "$QUELLE" "$TMP/k/" || exit 1

such() {
    local t; t=$(find kernel -name "$1" -type f -not -path '*/user/*' | head -1)
    [[ -n $t ]] || { echo "module/build.sh: $1 not in the kernel" >&2; return 1; }
    echo "$t"
}
mkdir -p "$TMP/k/lib" "$TMP/k/gfx" "$TMP/k/arch"
for f in ps2m.fi serial.fi modidx.fi; do
    cp -f "$(such $f)" "$TMP/k/$f" || exit 1
done
for f in kstate.fi errno.fi; do
    cp -f "$(such $f)" "$TMP/k/lib/$f" || exit 1
done
cp -f "$(such arch.fi)" "$(such machine.fi)" "$(such cpu.fi)" "$TMP/k/arch/" || exit 1
cp -f "$(such gfx-aus.fi)" "$TMP/k/gfx/gfx.fi" || exit 1
mkdir -p "$TMP/k/drv/hid" "$TMP/k/fs"
for f in ptrcfg.fi tpcfg.fi inputclass.fi; do
    cp -f "$(such $f)" "$TMP/k/drv/hid/$f" || exit 1
done
cp -f "$(such fs-off.fi)" "$TMP/k/fs/fs.fi" || exit 1
mkdir -p "$TMP/k/bus"
cp -f "$(such drvnull.fi)" "$TMP/k/bus/drvnull.fi" || exit 1

export FIRNLIB="$ROOT/lib"
BASENAME=$(basename "$QUELLE")
"$FIRNC" -o "$TMP/m.o" "$TMP/k/$BASENAME" || exit 1

UNDEF=$(readelf -sW "$TMP/m.o" | awk '$7=="UND" && $8!="" {print $8}' | sort -u)
echo "undefinierte Symbole: $(echo $UNDEF | tr '\n' ' ')"

python3 tools/module/mkomod.py bauen "$TMP/m.o" "$AUS" "${MKARGS[@]}" || exit 1
