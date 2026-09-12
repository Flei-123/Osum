#!/usr/bin/env bash
# herkunft.sh -- der Nachweis "fremd und unveraendert".
# Entpackt JEDES Archiv ein zweites Mal an einen frischen Ort und
# vergleicht es mit dem Baum, aus dem wirklich gebaut wurde.
set -u
Q=/root/fremdquellen
W=/root/fremdland-tmp
V=$W/verify
rm -rf "$V"; mkdir -p "$V"
echo "=== SHA-256 der Archive (wie heruntergeladen) ==="
cd "$Q" && sha256sum *.tar.gz *.tar.bz2 *.tar.xz *.zip 2>/dev/null
echo
echo "=== diff -r Original gegen Baubaum ==="
cd "$V"
tar xzf "$Q/lua-5.4.7.tar.gz"
tar xJf "$Q/quickjs-2024-01-13.tar.xz"
unzip -q "$Q/sqlite-amalgamation-3460000.zip"
tar xjf "$Q/busybox-1.36.1.tar.bz2"
for pair in \
  "lua-5.4.7:$W/src/lua-5.4.7" \
  "quickjs-2024-01-13:$W/src/quickjs-2024-01-13" \
  "sqlite-amalgamation-3460000:$W/src/sqlite-amalgamation-3460000" \
  "busybox-1.36.1:$W/busybox"
do
  o="${pair%%:*}"; b="${pair##*:}"
  if [ ! -d "$b" ]; then echo "$o: BAUBAUM FEHLT ($b)"; continue; fi
  # Bauartefakte zaehlen nicht als Aenderung am QUELLTEXT.
  d=$(diff -r -x '*.o' -x '*.a' -x '.config*' -x 'busybox' -x 'busybox_unstripped*' \
        -x 'include' -x 'applets' -x '.kernelrelease' -x 'Makefile.flags' \
        -x '*.d' -x '.*.cmd' -x 'scripts' -x 'docs' -x '_*' \
        "$V/$o" "$b" 2>&1 | grep -v '^Only in .*: \.gitignore$')
  n=$(printf '%s' "$d" | grep -c . )
  if [ "$n" = 0 ]; then
    echo "$o: diff LEER -- unveraendert"
  else
    echo "$o: $n Zeilen Unterschied:"
    printf '%s\n' "$d" | head -8
  fi
done
echo
echo "=== Zeilenzahlen (wc -l, nur .c/.h des Originals) ==="
for o in lua-5.4.7 quickjs-2024-01-13 sqlite-amalgamation-3460000 busybox-1.36.1; do
  c=$(find "$V/$o" -name '*.c' | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')
  a=$(find "$V/$o" \( -name '*.c' -o -name '*.h' \) | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')
  echo "$o: .c=$c  .c+.h=$a"
done
