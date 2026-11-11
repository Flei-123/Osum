#!/usr/bin/env bash
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
. tools/lib/firnenv.sh
firnenv_need_firnc1
FC1=$FIRNC1
ULD=kernel/user/user.ld
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
as --64 -o "$TMPD/hostcrt.o" tools/k11/hostcrt.s 2>/dev/null || { echo "as hostcrt FAIL"; exit 1; }
"$FIRNC" -c -o "$TMPD/fas.o" kernel/user/fas.fi >"$TMPD/fas.err" 2>&1 \
 && ld -T "$ULD" --defsym=USER_ENTRY=_F0.u_start -o "$TMPD/fas" "$TMPD/hostcrt.o" "$TMPD/fas.o" 2>/dev/null \
 || { echo "fas baut nicht:"; head -5 "$TMPD/fas.err"; exit 1; }
FAS="$TMPD/fas"
mkdir -p "$TMPD/s"
PROGS=""
for f in kernel/user/*.fi; do
  n=$(basename "$f" .fi)
  case "$n" in appdir|flate|nidx|pw|tools|ulib) continue;; esac
  grep -q "fn u_start" "$f" || continue
  PROGS="$PROGS $n"
done
ANZ=$(echo $PROGS | wc -w)
gebaut=0; nichtgebaut=""; appzahl=0
for p in $PROGS; do
  PROF=""
  grep -qa '^profile app' "kernel/user/$p.fi" && { PROF="--profile=app"; appzahl=$((appzahl+1)); }
  if "$FC1" $PROF "kernel/user/$p.fi" > "$TMPD/s/$p.s" 2>"$TMPD/s/$p.err"; then
    FCRT=(--crt _F1.u_start)
    grep -qE '^[[:space:]]*(\.globl[[:space:]]+_start|_start:)' "$TMPD/s/$p.s" && FCRT=()
    if "$FAS" "$TMPD/s/$p.s" -o "$TMPD/s/$p.bin" "${FCRT[@]}" >"$TMPD/s/$p.fas" 2>&1; then
      gebaut=$((gebaut+1))
    else
      nichtgebaut="$nichtgebaut $p[fas:$(head -1 "$TMPD/s/$p.fas"|cut -c1-60)]"
    fi
  else
    nichtgebaut="$nichtgebaut $p[firnc:$(head -1 "$TMPD/s/$p.err"|cut -c1-60)]"
  fi
  rm -f "$TMPD/s/$p.s" "$TMPD/s/$p.bin"
done
echo "PROGRAMME_GESAMT=$ANZ"
echo "PROFILE_APP=$appzahl"
echo "GEBUNDEN=$gebaut"
echo "NICHT:$nichtgebaut"
