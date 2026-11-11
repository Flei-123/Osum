#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
cd "$(dirname "$0")/../../.."
ROOT=$(pwd)

ZIEL=${1:-$ROOT/.certus-bau/certus.elf}
CERTUS_REPO=${CERTUS_REPO:-/root/certus-ui}
. tools/lib/firnenv.sh
FIRNC=${CERTUS_FIRNC:-/root/firnc-gc/compiler/target/release/firnc}
BAU=${CERTUS_BAU:-$ROOT/.certus-bau}

[ -d "$CERTUS_REPO/lib/browser" ] || {
    echo "no Certus tree in $CERTUS_REPO (set CERTUS_REPO)" >&2; exit 2; }
[ -x "$FIRNC" ] || {
    echo "no compiler: $FIRNC" >&2
    echo "  (cd $CERTUS_REPO/compiler && cargo build --release)" >&2; exit 2; }
if [ -f "$CERTUS_REPO/lib/osum/window/backend.fi" ]; then
    LAYOUT=new
elif [ -f "$CERTUS_REPO/lib/fenster/osum.fi" ]; then
    LAYOUT=old
else
    echo "$CERTUS_REPO has no Osum backend -- wrong branch/tree?" >&2; exit 2
fi

rm -rf "$BAU"
mkdir -p "$BAU"

for d in "$CERTUS_REPO"/lib/*; do
    ln -sfn "$d" "$BAU/$(basename "$d")"
done
for pair in fui:.fui-win rt:.rt-win std:.std-win; do
    if [ -d "$CERTUS_REPO/${pair#*:}" ]; then
        ln -sfn "$CERTUS_REPO/${pair#*:}" "$BAU/${pair%%:*}"
    fi
done
FIRN_SHARED=${FIRN_SHARED:-/root/firn}
if [ -d "$FIRN_SHARED/lib" ]; then
    for d in "$FIRN_SHARED"/lib/*; do
        [ -e "$BAU/$(basename "$d")" ] || ln -sfn "$d" "$BAU/$(basename "$d")"
    done
fi
for sub in $(ls "$CERTUS_REPO/lib"); do
    case "$sub" in fui|rt|std|libc|window|dlg|media|osum|windows) continue ;; esac
    if [ -d "$CERTUS_REPO/lib/$sub" ] && [ -d "$FIRN_SHARED/lib/$sub" ]; then
        rm -f "$BAU/$sub"; mkdir -p "$BAU/$sub"
        for f in "$CERTUS_REPO/lib/$sub"/* "$FIRN_SHARED/lib/$sub"/*; do
            [ -e "$BAU/$sub/$(basename "$f")" ] || ln -sfn "$f" "$BAU/$sub/$(basename "$f")"
        done
    fi
done
rm -f "$BAU/fenster" "$BAU/libc"
cp -r "$ROOT/lib/libc" "$BAU/libc"
cp "$ROOT/lib/icons.fi" "$ROOT/lib/utf8.fi" "$BAU/"
cp "$ROOT/kernel/user/ulib.fi" "$ROOT/kernel/user/wlib.fi" \
   "$ROOT/kernel/user/wlibc.fi" "$BAU/"
rm -rf "$BAU/wlib" "$BAU/wlibc"
cp -r "$ROOT/kernel/user/wlib" "$ROOT/kernel/user/wlibc" "$BAU/"
python3 - "$ROOT" "$BAU" <<'PYEOF'
import os, re, shutil, sys
root, bau = sys.argv[1], sys.argv[2]
todo = ['wlib', 'wlibc', 'ulib']
seen = set(todo)
def sources(name):
    paths = [os.path.join(bau, name + '.fi')]
    if name in ('wlib', 'wlibc'):
        d = os.path.join(bau, name)
        paths += [os.path.join(d, f) for f in sorted(os.listdir(d)) if f.endswith('.fi')]
    return paths
while todo:
    name = todo.pop()
    lines = [l for p in sources(name) for l in open(p, encoding='latin1')]
    for line in lines:
        m = re.match(r'import ([a-z0-9_]+)\s*$', line)
        if not m or m.group(1) in seen:
            continue
        mod = m.group(1)
        seen.add(mod)
        for d in ('kernel/user', 'lib'):
            src = os.path.join(root, d, mod + '.fi')
            if os.path.exists(src):
                if not os.path.exists(os.path.join(bau, mod + '.fi')):
                    shutil.copy(src, os.path.join(bau, mod + '.fi'))
                todo.append(mod)
                break
PYEOF
if [ -f "$BAU/msg.fi" ]; then
    mv "$BAU/msg.fi" "$BAU/osmsg.fi"
    for f in "$BAU"/*.fi "$BAU"/wlib/*.fi "$BAU"/wlibc/*.fi; do
        [ -f "$f" ] && [ ! -L "$f" ] && grep -q '^import msg[[:space:]]*$' "$f" || continue
        sed -i -e 's/^import msg[[:space:]]*$/import osmsg/' -e 's/\bmsg\./osmsg./g' "$f"
    done
fi
if [ -d "$CERTUS_REPO/.fui-win" ]; then
    rm -f "$BAU/fui"; mkdir -p "$BAU/fui"
    for f in "$CERTUS_REPO"/.fui-win/*; do ln -sfn "$f" "$BAU/fui/$(basename "$f")"; done
    for f in "$ROOT"/lib/fui/* "$FIRN_SHARED"/lib/fui/*; do
        [ -e "$BAU/fui/$(basename "$f")" ] || ln -sfn "$f" "$BAU/fui/$(basename "$f")"
    done
fi

if [ "$LAYOUT" = new ]; then
    for sub in window dlg media; do
        rm -f "$BAU/$sub"
        mkdir -p "$BAU/$sub"
        for f in "$CERTUS_REPO/lib/$sub"/*; do
            [ -e "$f" ] && ln -sfn "$f" "$BAU/$sub/$(basename "$f")"
        done
        if [ -d "$CERTUS_REPO/lib/osum/$sub" ]; then
            for f in "$CERTUS_REPO/lib/osum/$sub"/*; do
                ln -sfn "$(readlink -f "$f")" "$BAU/$sub/$(basename "$f")"
            done
        fi
    done
    if [ -d "$CERTUS_REPO/lib/osum/prof_os" ]; then
        rm -rf "$BAU/prof_os"
        ln -sfn "$CERTUS_REPO/lib/osum/prof_os" "$BAU/prof_os"
    fi
    rm -f "$BAU/window/osum.fi" "$BAU/window/backend.fi"
    sed 's/wlib\.canvas2(/wlib.canvas(/g' "$CERTUS_REPO/lib/window/osum.fi" > "$BAU/window/osum.fi"
    ln -sfn osum.fi "$BAU/window/backend.fi"
else
    mkdir -p "$BAU/fenster"
    for f in "$CERTUS_REPO"/lib/fenster/*.fi; do
        ln -sfn "$f" "$BAU/fenster/$(basename "$f")"
    done
    ln -sfn "$CERTUS_REPO/lib/fenster/osum.fi" "$BAU/fenster/rueck.fi"
fi

find "$BAU" -type l -name '*.fi' | while read -r link; do
    if grep -q 'as%' "$link" 2>/dev/null; then
        src=$(readlink -f "$link")
        rm -f "$link"
        sed 's/ as% / as /g' "$src" > "$link"
    fi
done
python3 "$ROOT/kernel/user/certus/entkern.py" "$BAU" > "$BAU/entkern.log"

cp "$CERTUS_REPO/lib/osum/certus_main.fi" "$BAU/certus_main.fi"
(cd "$BAU" && python3 "$ROOT/kernel/user/certus/inlineconsts.py" "$BAU" wlib.fi wlibc.fi wlib/*.fi wlibc/*.fi) | tee "$BAU/inlineconsts.log"
python3 "$ROOT/kernel/user/certus/splitstems.py" "$ROOT" "$BAU" "$FIRN_TOOLCHAIN" | tee "$BAU/splitstems.log"
(cd "$BAU" && python3 "$ROOT/kernel/user/certus/inlineconsts.py" "$BAU" osa/*.fi fui/*.fi) | tee -a "$BAU/inlineconsts.log"
(cd "$BAU" && grep -l '__bits(\|__include_str(' osa/*.fi fui/*.fi 2>/dev/null | xargs -r python3 "$ROOT/kernel/user/certus/lowerintrinsics.py" "$BAU") | tee "$BAU/lowerintrinsics.log"
if [ -f "$BAU/std/deflate.fi" ] && ! grep -q 'fn inflate_limited' "$BAU/std/deflate.fi"; then
    stddir=$(readlink -f "$BAU/std")
    rm "$BAU/std"
    mkdir "$BAU/std"
    for f in "$stddir"/*; do ln -sfn "$f" "$BAU/std/$(basename "$f")"; done
    src="$stddir/deflate.fi"
    rm "$BAU/std/deflate.fi"
    { sed '0,/^export {/s//export {\n    inflate_limited,/' "$src"; cat "$ROOT/kernel/user/certus/shims/deflate_limited.fi"; } > "$BAU/std/deflate.fi"
fi

cd "$BAU"
FIRNLIB="$BAU" "$FIRNC" -c -o "$BAU/certus.o" certus_main.fi
as --64 -o "$BAU/sysstub.o" "$ROOT/kernel/user/sysstub.s"
ld -T "$ROOT/kernel/user/user.ld" -o "$BAU/certus.dbg" \
    "$BAU/certus.o" "$BAU/sysstub.o"
mkdir -p "$(dirname "$ZIEL")"
cp "$BAU/certus.dbg" "$ZIEL"
strip --strip-all "$ZIEL"

echo "certus: $(stat -c%s "$ZIEL") Oktette -> $ZIEL"
