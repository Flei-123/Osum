#!/usr/bin/env bash
# tools/k16/fas-zaehlen.sh -- WIEVIELE PROGRAMME BINDET `fas`?
#
# RUNDE BAUFEHLER (14.09.2026). Die Zahl, an der A-015 haengt, in einem
# Aufruf und ohne den ganzen Abschnitt 21 zu fahren. Sie zaehlt genau,
# was `tools/k16/run.sh` zaehlt (jede Datei unter kernel/user/ mit
# `fn u_start`, ohne die acht Bibliotheksmodule), baut jedes Programm mit
# dem Profil AUS SEINER WURZELDATEI und haengt `--crt` nur an, wenn die
# .s kein eigenes `_start` mitbringt.
#
# Ausgabe:
#     PROGRAMME_GESAMT=135
#     PROFILE_APP=18
#     GEBUNDEN=135
#     NICHT:
#
# Gemessen am 13.09.2026 auf main (ae381a3): GEBUNDEN=117, und die
# achtzehn fehlenden waren genau die mit `profile app` -- alle an
# "diese Marke gibt es zwei '_F1.rt__ld8'". Ursache und Behebung stehen
# in vendor/firn/patches/0005-rt-rt-heisst-std-rt.patch und in
# docs/RUNDE-BAUFEHLER.md.
#
# Laeuft rund 20 Minuten (firnc1 uebersetzt 135 Programme einzeln).
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
FIRNC=vendor/firn/bin/firnc
FC1=vendor/firn/bin/firnc1
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
  case "$n" in appdir|flate|nidx|pw|tools|ulib|wlib|wlibc) continue;; esac
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
