#!/usr/bin/env bash
cd "$1" || exit 1
export FIRNLIB="$PWD/lib"
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
list=$( (ls kernel/user/*.fi kernel/app/*.fi; echo kernel/kmain.fi; echo kernel/uprog.fi) )
one() { f=$1; o=$D/$(echo $f | tr / _).o; if vendor/firn/bin/firnc $f -o $o >$o.log 2>&1; then echo "$f ok"; else echo "$f fail $(wc -l < $o.log)"; fi; }
export -f one; export D
echo "$list" | xargs -P 6 -I{} bash -c 'one {}' | sort > "$2"
grep -c ' ok$' "$2"; grep -c ' fail' "$2"
