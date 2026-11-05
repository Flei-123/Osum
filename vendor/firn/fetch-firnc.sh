#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
HERE=$(pwd)

COMMIT=$(cat COMMIT)
SHORT=${COMMIT:0:8}

PATCHSUM=$( { cat "$HERE"/patches/*.patch 2>/dev/null || true; } | sha256sum | cut -c1-16)
STAMP="$COMMIT $PATCHSUM"

exec 9>"$HERE/.holen.lock"
flock 9

link_aliases() {
    if [[ -f $HERE/lib/font/ttf.fi && ! -e $HERE/lib/font/fuittf.fi ]]; then
        ln -s ttf.fi "$HERE/lib/font/fuittf.fi"
    fi
}
FORCE=0
[[ ${1:-} == --force ]] && FORCE=1

if [[ $FORCE -eq 0 && -x $HERE/bin/firnc && -x $HERE/bin/firnc1 \
      && -f $HERE/.gebaut && $(cat "$HERE/.gebaut") == "$STAMP" ]]; then
    link_aliases
    echo "firnc is up to date ($SHORT, patches $PATCHSUM)"
    exit 0
fi

if [[ $FORCE -eq 0 ]]; then
    while read -r tree; do
        [[ -n $tree ]] || continue
        source="$tree/vendor/firn"
        [[ $(cd "$source" 2>/dev/null && pwd) == "$HERE" ]] && continue
        [[ -x $source/bin/firnc && -x $source/bin/firnc1 && -d $source/lib \
           && -f $source/.gebaut ]] || continue
        [[ $(cat "$source/.gebaut") == "$STAMP" ]] || continue
        echo ">> Firn $SHORT (patches $PATCHSUM) reused from worktree $tree"
        rm -rf "$HERE/bin" "$HERE/lib"
        cp -a "$source/bin" "$HERE/bin"
        cp -a "$source/lib" "$HERE/lib"
        printf '%s\n' "$STAMP" > "$HERE/.gebaut"
        link_aliases
        exit 0
    done < <(git -C "$HERE" worktree list --porcelain 2>/dev/null \
             | sed -n 's/^worktree //p')
fi

toolchain_version() {
    [[ ${OSUM_FIRN_TOOLCHAIN:-1} != 0 ]] || return 1
    compgen -G "$HERE/patches/*.patch" >/dev/null && return 1
    local v
    for v in "${FIRN_HOME:-$HOME/.firn}"/versions/*/; do
        v=${v%/}
        [[ -f $v/.ready && -x $v/bin/firnc && -d $v/lib && -f $v/src/firnc1.fi && -e $v/src/ast.fi ]] || continue
        [[ $(cat "$v/COMMIT" 2>/dev/null) == "$COMMIT" ]] || continue
        printf '%s\n' "$v"
        return 0
    done
    return 1
}

BUILD=${FIRN_BUILD_DIR:-${TMPDIR:-/tmp}}/firn-pin-$SHORT
rm -rf "$BUILD"
if TOOLCHAIN=$(toolchain_version); then
    echo ">> Firn $SHORT from installed toolchain $TOOLCHAIN"
    FIRNC0_BIN=$TOOLCHAIN/bin/firnc
    LIB_SRC=$TOOLCHAIN/lib
    FIRNC1_SRC=$TOOLCHAIN/src/firnc1.fi
else
    candidates=()
    [[ -n ${FIRN_REPO:-} ]] && candidates+=("$FIRN_REPO")
    candidates+=("$HERE/../../../firn" "$HERE/../../firn" "$HERE/../../../../firn" "$HOME/firn")
    FIRN=""
    for k in "${candidates[@]}"; do
        if [[ -d $k/.git ]] && git -C "$k" cat-file -e "$COMMIT^{commit}" 2>/dev/null; then
            FIRN=$(cd "$k" && pwd); break
        fi
    done
    if [[ -z $FIRN ]]; then
        echo "Firn repo with commit $SHORT not found and no installed toolchain has it." >&2
        echo "Searched in: ${candidates[*]} ${FIRN_HOME:-$HOME/.firn}/versions" >&2
        echo "Set the path via FIRN_REPO=/path/to/firn or run: firn install <version of $SHORT>." >&2
        exit 1
    fi
    echo ">> Firn $SHORT unpack from $FIRN"
    mkdir -p "$BUILD"
    git -C "$FIRN" archive "$COMMIT" | tar -x -C "$BUILD"
    HOST=$(rustc -vV | sed -n 's/^host: //p')
    echo ">> build firnc0 (target $HOST)"
    ( cd "$BUILD/compiler" && cargo build --release --target "$HOST" >/dev/null )
    FIRNC0_BIN=$BUILD/compiler/target/$HOST/release/firnc
    LIB_SRC=$BUILD/lib
    FIRNC1_SRC=$BUILD/bin/firnc1.fi
fi

mkdir -p "$HERE/bin"
rm -f "$HERE/bin/firnc" "$HERE/bin/firnc0" "$HERE/bin/firnc1" "$HERE/.gebaut"
cp -f "$FIRNC0_BIN" "$HERE/bin/firnc0"
cat > "$HERE/bin/firnc" <<'WRAP'
#!/bin/sh
export FIRN_USE_AS="${FIRN_USE_AS-1}"
exec "$(dirname "$0")/firnc0" "$@"
WRAP
chmod +x "$HERE/bin/firnc"
rm -rf "$HERE/lib"
cp -rL "$LIB_SRC" "$HERE/lib"

if [[ -d $HERE/patches ]]; then
    rm -rf "$HERE/lib/.roh"
    for f in "$HERE"/patches/*.patch; do
        [[ -e $f ]] || continue
        while read -r target; do
            [[ -n $target ]] || continue
            [[ -f $HERE/lib/$target ]] || continue
            mkdir -p "$HERE/lib/.roh/$(dirname "$target")"
            [[ -e $HERE/lib/.roh/$target ]] || cp -p "$HERE/lib/$target" "$HERE/lib/.roh/$target"
        done < <(sed -n 's|^+++ [ab]/||p' "$f" | sed 's/\t.*//')
        echo ">> patch: $(basename "$f")"
        patch -p1 -d "$HERE/lib" -i "$f" --silent \
            || { echo "patch $(basename "$f") does not apply to Firn $SHORT" >&2
                 exit 1; }
    done
fi

if [[ -d $LIB_SRC ]]; then
    ( cd "$LIB_SRC" && find . -type l -printf '%p\t%l\n' ) |
    while IFS=$'\t' read -r loc target; do
        [[ -e "$HERE/lib/$(dirname "$loc")/$target" ]] || continue
        if ! cmp -s "$HERE/lib/$loc" "$HERE/lib/$(dirname "$loc")/$target"; then
            echo "Symlink $loc would change content -- kept as copy" >&2
            continue
        fi
        rm -f "$HERE/lib/$loc"
        ln -s "$target" "$HERE/lib/$loc"
    done
fi

echo ">> build firnc1"
FIRNLIB="$HERE/lib" "$HERE/bin/firnc" "$FIRNC1_SRC" -o "$HERE/bin/firnc1"

link_aliases
echo "$STAMP" > "$HERE/.gebaut"
rm -rf "$BUILD"
echo ">> done: vendor/firn/bin/firnc + bin/firnc1 + lib ($SHORT, patches $PATCHSUM)"
