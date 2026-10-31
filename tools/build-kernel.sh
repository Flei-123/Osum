#!/usr/bin/env bash
#
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)

AUS=${1:-}
if [[ -z $AUS ]]; then
    sed -n '2,20p' "$0"
    exit 1
fi
shift

STUFE=0
OHNE_PS2M=0
OHNE_BRUECKE=0
SYMBOLE=on

# --------------------------------------------------- die Baukonfiguration
#
GUI=on
TUNNEL=on
if [[ -f tools/config ]]; then
    while IFS='=' read -r k v; do
        k=${k%%#*}; k=${k// /}; v=${v%%#*}; v=${v// /}
        [[ -z $k ]] && continue
        case "$k" in
            gui) GUI=$v ;;
            tunnel) TUNNEL=$v ;;
        esac
    done < tools/config
fi
[[ -n ${OSUM_GUI:-} ]] && GUI=$OSUM_GUI
[[ -n ${OSUM_TUNNEL:-} ]] && TUNNEL=$OSUM_TUNNEL
MODULE_KEYS=${MODULE_KEYS:-}
BAN_FLOOR=${BAN_FLOOR:-}
OHNE_EXT4=${OHNE_EXT4:-0}
OHNE_NTFS=${OHNE_NTFS:-0}
[[ -n ${OSUM_EXT4:-} ]] && [[ $OSUM_EXT4 == off ]] && OHNE_EXT4=1
[[ -n ${OSUM_NTFS:-} ]] && [[ $OSUM_NTFS == off ]] && OHNE_NTFS=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ohne-tunnel) TUNNEL=off; shift ;;
        --ohne-ext4) OHNE_EXT4=1; shift ;;
        --ohne-ntfs) OHNE_NTFS=1; shift ;;
        --ohne-fremdfs) OHNE_EXT4=1; OHNE_NTFS=1; shift ;;
        --ohne-ps2m) OHNE_PS2M=1; shift ;;
        --module-keys) MODULE_KEYS=$2; shift 2 ;;
        --ban-floor) BAN_FLOOR=$2; shift 2 ;;
        --ohne-bruecke) OHNE_BRUECKE=1; shift ;;
        --ohne-symbole) SYMBOLE=off; shift ;;
        --gui) GUI=$2; shift 2 ;;
        --stufe) STUFE=$2; shift 2 ;;
        *) echo "unbekannte Option: $1" >&2; exit 1 ;;
    esac
done
case "$GUI" in on|off) ;; *) echo "--gui nimmt on oder off, nicht '$GUI'" >&2; exit 1 ;; esac
case "$TUNNEL" in on|off) ;; *) echo "tunnel nimmt on oder off, nicht '$TUNNEL'" >&2; exit 1 ;; esac
OHNE_TUNNEL=0
[[ $TUNNEL == off ]] && OHNE_TUNNEL=1

export FIRNLIB="$ROOT/lib"
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

for f in boot isr switch smp hv; do
    as --64 -o "$TMP/$f.o" "kernel/arch/x86_64/$f.s" || exit 1
done

cp -a kernel "$TMP/kernel" || exit 1

FASSUNG_HASH=$(git rev-parse --short=8 HEAD 2>/dev/null || echo "unbekant")
if git status --porcelain 2>/dev/null | grep -q .; then
    FASSUNG_HASH="${FASSUNG_HASH:0:7}+"
fi
#
python3 "$(dirname "$0")/marke-einsetzen.py" "$TMP" \
    "$(dirname "$0")/../marke.conf" "$FASSUNG_HASH" "${IMAGE_ID:-dev}" || {
    echo "die Marke wurde NICHT eingesetzt -- Bau abgebrochen" >&2
    exit 1; }
VERSIONDATEI=$(find "$TMP/kernel" -path "$TMP/kernel/user" -prune -o \
    -path "$TMP/kernel/app" -prune -o -name version.fi -type f -print | head -1)
[[ -n $VERSIONDATEI ]] || { echo "version.fi nicht gefunden" >&2; exit 1; }
grep -q " $FASSUNG_HASH" "$VERSIONDATEI" || {
    echo "die Fassungsnummer wurde NICHT eingesetzt -- Bau abgebrochen" >&2
    exit 1; }
BRANDDATEI=$(find "$TMP/kernel" -path "$TMP/kernel/user" -prune -o \
    -path "$TMP/kernel/app" -prune -o -name brand.fi -type f -print | head -1)
[[ -n $BRANDDATEI ]] || { echo "brand.fi nicht gefunden" >&2; exit 1; }
if grep -qE 'static mut s_[a-z]+: \[u8; [0-9]+\] = "[^"]*\?' \
        "$BRANDDATEI"; then
    echo "in brand.fi steht noch ein Platzhalter -- abgebrochen" >&2
    exit 1
fi
#
ersetze() { # $1 = Stummel ohne .fi, $2 = Ziel ohne .fi
    local stummel ziel
    stummel=$(find "$TMP/kernel" -name "$1.fi" -type f | head -1)
    ziel=$(find "$TMP/kernel" -name "$2.fi" -type f | head -1)
    [[ -n $stummel ]] || { echo "Bau: $1.fi nicht gefunden" >&2; return 1; }
    [[ -n $ziel    ]] || { echo "Bau: $2.fi nicht gefunden" >&2; return 1; }
    cp -f "$stummel" "$ziel" || return 1
}
weg() { # $1 = Name ohne .fi
    local p
    p=$(find "$TMP/kernel" -name "$1.fi" -type f)
    [[ -n $p ]] && rm -f $p
    return 0
}

if [[ $OHNE_BRUECKE == 1 ]]; then
    ersetze tip-off tip || exit 1
fi
weg tip-off

if [[ $OHNE_TUNNEL == 1 ]]; then
    ersetze wg-aus wg || exit 1
fi
weg wg-aus

if [[ $OHNE_EXT4 == 1 ]]; then
    ersetze ext4-aus ext4 || exit 1
fi
weg ext4-aus
if [[ $OHNE_NTFS == 1 ]]; then
    ersetze ntfs-aus ntfs || exit 1
fi
weg ntfs-aus

GFX_DATEIEN="fb wm wig font ttf tile wmplug vmode ansi ps2m kgui sysgui dispsave cursor vgpu beam vmsvga pixelguard shot"
if [[ $GUI == off ]]; then
    for f in $GFX_DATEIEN; do
        #
        TREFFER=$(find "$TMP/kernel" -name "$f.fi" -type f -not -path "*/user/*")
        if [[ -z $TREFFER ]]; then
            echo "SERVERBUILD-WARNUNG: '$f.fi' steht in GFX_DATEIEN," \
                 "liegt aber nicht im Kernbaum -- hier wird NICHTS" \
                 "geloescht. Entweder ist der Name veraltet, oder die" \
                 "Datei wurde verschoben." >&2
        fi
        rm -f $TREFFER
    done
    GFXZIEL=$(find "$TMP/kernel" -name "gfx.fi" -type f | head -1)
    [[ -n $GFXZIEL ]] || { echo "SERVERBUILD: gfx.fi nicht gefunden" >&2; exit 1; }
    ersetze gfx-aus gfx || exit 1
fi
weg gfx-aus

if [[ $OHNE_PS2M == 1 ]]; then
    if [[ $GUI == off ]]; then
        echo "--ohne-ps2m und --gui off zusammen ergeben nichts: ohne GUI ist ps2m.fi ohnehin nicht im Baum" >&2
        exit 1
    fi
    ersetze ps2m-aus ps2m || exit 1
fi
weg ps2m-aus
KDIR="$TMP/kernel"
if [[ -n $MODULE_KEYS || -n $BAN_FLOOR ]]; then
    cp -a lib "$TMP/lib" || exit 1
    export FIRNLIB="$TMP/lib"
    python3 tools/module/mkpolicy.py "$TMP/lib/modpolicy/policydata.fi" \
        ${MODULE_KEYS:+--keys "$MODULE_KEYS"} ${BAN_FLOOR:+--floor "$BAN_FLOOR"} \
        >/dev/null || { echo "mkpolicy failed" >&2; exit 1; }
fi

KMAIN=$(find "$KDIR" -name kmain.fi -type f | head -1)
UPROG=$(find "$KDIR" -name uprog.fi -type f | head -1)
[[ -n $KMAIN ]] || { echo "kmain.fi nicht gefunden" >&2; exit 1; }
[[ -n $UPROG ]] || { echo "uprog.fi nicht gefunden" >&2; exit 1; }
# ACCEL phase 1 (B-01/B-02): the two compiles go through a content-addressed cache and run in
# parallel (they are independent; before: 2 x serial).  Compile with cwd = the kernel copy and
# relative root paths, so the objects do not contain the random mktemp name (reproducible).
# Details, env switches (OSUM_BUILD_CACHE=off) and the proof: tools/kernel/buildcache.sh, docs/DEVLOOP.md.
. "$(dirname "$0")/kernel/buildcache.sh"
BC_KEY=$(bc_common_key "$FIRNC" "$TMP" "$STUFE")
bc_compile "$FIRNC" "$TMP" "$BC_KEY" "${KMAIN#$TMP/}" "$TMP/k.o" &
BC_P1=$!
bc_compile "$FIRNC" "$TMP" "$BC_KEY" "${UPROG#$TMP/}" "$TMP/uprog.o" &
BC_P2=$!
BC_RC=0
wait "$BC_P1" || BC_RC=1
wait "$BC_P2" || BC_RC=1
[[ $BC_RC == 0 ]] || { echo "Firn compile failed" >&2; exit 1; }

# firnc0 stellt jedem Symbol `_F0.` voran, firnc1 `_F1.`
# (docs/SELF_HOSTING.md im Firn-Repo).
P="_F${STUFE}."

# ==================================================== RUNDE PROTOKOLL
# ZWEIMAL BINDEN, UND DANACH NACHRECHNEN.
#
binde() { # $1 = osym-Objekt, $2 = Ausgabe
    ld -n -T kernel/kernel.ld \
        --defsym=KERNEL_MAIN="${P}kernel_main" \
        --defsym=KERNEL_TRAP="${P}trap__entry" \
        --defsym=KERNEL_SYSCALL="${P}sys__entry" \
        --defsym=KERNEL_TASK_MAIN="${P}tasks__main" \
        --defsym=KERNEL_USER_START="${P}proc__user_start" \
        --defsym=KERNEL_AP_MAIN="${P}smp__ap_main" \
        --defsym=USER_MAIN="${P}u_enter" \
        -o "$2" "$TMP/boot.o" "$TMP/isr.o" "$TMP/switch.o" \
        "$TMP/smp.o" "$TMP/hv.o" "$TMP/k.o" "$TMP/uprog.o" $1 \
        2> >(grep -vE 'GNU-stack|deprecated|LOAD segment with RWX' >&2)
}

binde "" "$TMP/osum.elf" || exit 1

if [[ $SYMBOLE == on ]]; then
    nm -n "$TMP/osum.elf" | awk '$2=="T"||$2=="t"' > "$TMP/sym1.txt"
    python3 "$(dirname "$0")/kernel/symtab.py" "$TMP/osum.elf" \
        "$TMP/osym2.s" || { echo "symtab.py fehlgeschlagen" >&2; exit 1; }
    as --64 -o "$TMP/osym2.o" "$TMP/osym2.s" || exit 1
    binde "$TMP/osym2.o" "$TMP/osum2.elf" || exit 1
    nm -n "$TMP/osum2.elf" | awk '$2=="T"||$2=="t"' > "$TMP/sym2.txt"
    if ! cmp -s "$TMP/sym1.txt" "$TMP/sym2.txt"; then
        echo "PROTOKOLL: der zweite Bindedurchgang hat Funktionsadressen" \
             "verschoben -- die Symboltabelle waere falsch. Bau abgebrochen." >&2
        diff "$TMP/sym1.txt" "$TMP/sym2.txt" | head -5 >&2
        exit 1
    fi
    mv -f "$TMP/osum2.elf" "$TMP/osum.elf"
fi

mkdir -p "$(dirname "$AUS")"
cp -f "$TMP/osum.elf" "$AUS.elf"
objcopy -O elf32-i386 "$TMP/osum.elf" "$AUS" || exit 1
echo "$AUS ($(stat -c%s "$AUS") Oktette, Stufe $STUFE, gui=$GUI, tunnel=$TUNNEL, ps2m=$([[ $OHNE_PS2M == 1 ]] && echo modul || echo fest), symbole=$SYMBOLE, ext4=$([[ $OHNE_EXT4 == 1 ]] && echo aus || echo an), ntfs=$([[ $OHNE_NTFS == 1 ]] && echo aus || echo an))"
