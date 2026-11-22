#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=${1:?directory with wordcraft/ gridcraft/ deckcraft/ launcher/ release trees}
OUT=${2:-$(mktemp -d)}
WD=${AC_WD:-/root/fxhp}
. tools/lib/tmpdir.sh
osum_tmp_guard "${2:-}" "$OUT"
mkdir -p "$OUT"
KERNEL_ENV=()
[ -n "${KERNEL:-}" ] && KERNEL_ENV=(env "KERNEL=$KERNEL")
pass=0
fail=0
report() {
    if [ "$2" = ok ]; then pass=$((pass + 1)); printf '  OK    %s\n' "$1"; else fail=$((fail + 1)); printf '  FAIL  %s%s\n' "$1" "${3:+ ($3)}"; fi
}
bin_of() { echo "$ROOT/$1"/*/bin/"$2"; }
if [[ " ${STAGES:-cli gui} " == *" cli "* ]]; then
    ENTRIES=$(python3 -I tools/linuxapps/glibcspec.py "bin:$(bin_of gridcraft gridcraft-cli)" "bin:$(bin_of wordcraft wordcraft-cli)" "bin:$(bin_of deckcraft deckcraft-cli)")
    EXTRA="$ENTRIES /opt/ac/ /opt/ac/gridcraft-cli=$(bin_of gridcraft gridcraft-cli)@755 /opt/ac/wordcraft-cli=$(bin_of wordcraft wordcraft-cli)@755 /opt/ac/deckcraft-cli=$(bin_of deckcraft deckcraft-cli)@755"
    BLOCKS=${BLOCKS:-1200000} TMO=${TMO:-900} EXTRA="$EXTRA" "${KERNEL_ENV[@]}" bash tools/linuxapps/run.sh "$WD" tools/linuxapps/guest-artcraft-cli.sh "$OUT/cli" > "$OUT/cli.log" 2>&1
    log=$OUT/cli/ser.clean
    for step in grid-version grid-eval grid-run grid-cat word-version word-convert word-text word-pdf deck-version deck-run; do
        grep -qaF "AC $step rc=0" "$log" && report "cli $step" ok || report "cli $step" no "no 'rc=0' line"
    done
    grep -qaxF "12" "$log" && report "cli grid-eval prints 12" ok || report "cli grid-eval prints 12" no
    grep -qa "Hello ArtCraft" "$log" && report "cli word-text round trip" ok || report "cli word-text round trip" no
    grep -qa "AC pdf size: -.* [1-9][0-9]* .*out.pdf" "$log" && report "cli pdf written" ok || report "cli pdf written" no
fi
if [[ " ${STAGES:-cli gui} " == *" gui "* ]]; then
    for entry in ${GUI_APPS:-gridcraft:gridcraft wordcraft:wordcraft deckcraft:deckcraft}; do
        dir=${entry%%:*}
        app=${entry##*:}
        AC_BINDIR=$(echo "$ROOT/$dir"/*/bin) BLOCKS=${GUI_BLOCKS:-2400000} TMO=${GUI_TMO:-1200} "${KERNEL_ENV[@]}" \
            bash tools/linuxapps/artcraft-gui.sh "$WD" "$app" "$OUT/gui-$dir" > "$OUT/gui-$dir.log" 2>&1
        ser=$OUT/gui-$dir/ser.clean
        grep -qaF "wayd: window c=" "$ser" && report "gui $dir window" ok || report "gui $dir window" no "no wayd window"
        TYPED=()
        [ "$dir" = gridcraft ] && TYPED=("$OUT/gui-$dir/typed.ppm")
        DARK=()
        [ "$dir" = launcher ] && DARK=(--dark)
        verdict=$(python3 -I tools/linuxapps/artcraftcheck.py "${DARK[@]}" "$OUT/gui-$dir/window.ppm" "${TYPED[@]}" 2>&1 | tail -1)
        [ "$verdict" = "ARTCRAFT-CHECK green" ] && report "gui $dir pixels${TYPED:+ + typing}" ok || report "gui $dir pixels${TYPED:+ + typing}" no "$verdict"
    done
fi
echo "ARTCRAFT-GATE: $pass ok, $fail failed"
[ "$fail" -eq 0 ]
