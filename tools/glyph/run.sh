#!/usr/bin/env bash
#
#     panic: integer overflow in 'u64 * u64' at wlibc.fi:1128
#
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/firnenv.sh
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
TMPD=${GLYPHE_TMPD:-$(mktemp -d)}
[ -n "${GLYPHE_KEEP:-}" ] || trap 'rm -rf "$TMPD"' EXIT

LAEUFE=${OSUM_GLYPHE_LAEUFE:-20}
PAR=${OSUM_GLYPHE_PAR:-4}
SEK=${OSUM_GLYPHE_SEK:-200}

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
zahl() { # name wert op soll
    local name=$1 wert=$2 op=$3 soll=$4
    if [ -z "$wert" ]; then bad "$name: no number (wanted $op $want)"; return; fi
    if [ "$wert" -"$op" "$soll" ] 2>/dev/null; then ok "$name: $wert"
    else bad "$name: $val, wanted $op $want"; fi
}

echo "== 1. at the source: who fetches the stage, and from where =="
ROH=$(grep 'base(state) + STAGE_OFF' kernel/ui/wig.fi | grep -vc '^[[:space:]]*//')
zahl "Stellen im CODE, die die geteilte Buehne noch direkt nehmen" "$ROH" eq 1
grep -q 'fn stage_of' kernel/ui/wig.fi \
    && ok "wig.stage_of exists" || bad "wig.stage_of fehlt"
for f in blit glyph_into; do
    n=$(awk "/^fn $f\(/,/^}/" kernel/ui/wig.fi | grep -c 'stage_of(state)')
    if [ "$n" -ge 1 ]; then ok "wig.$f fetches the stage via stage_of"
    else bad "wig.$f does NOT fetch the stage via stage_of"; fi
done
grep -q 'kstate.WIGST_OFF + k \* STAGE_MAX' kernel/ui/wig.fi \
    && ok "stage_of computes with the core number (WIGST_OFF + k * STAGE_MAX)" \
    || bad "stage_of rechnet nicht je Kern"
if awk '/^fn glyph\(/,/^}/' kernel/gfx/ttf.fi | grep -q 'table_on('; then
    ok "ttf.glyph nimmt die Tafelsperre"
else bad "ttf.glyph does not take the table lock"; fi
if awk '/^fn glyph\(/,/^}/' kernel/gfx/ttf.fi \
   | grep -qE 'irq_(ack|aus)\(\)' \
   && awk '/^fn glyph\(/,/^}/' kernel/gfx/ttf.fi | grep -q 'irq_an('; then
    ok "and stops interrupts while doing so (the tag is a core number)"
else bad "ttf.glyph does not stop interrupts"; fi
if awk '/^fn gload\(/,/^}/' kernel/user/uikit/uiglyph.fi | grep -q 'gw > GMAX'; then
    ok "uiglyph.gload checks the header before it 'gw * gh' rechnet"
else bad "uiglyph.gload does not check the header"; fi

echo
echo "== 2. bauen: Kern, Programme, Platte =="
bash tools/build-kernel.sh "$TMPD/k.mb" > "$TMPD/k.log" 2>&1 \
    && ok "der Kern baut ($(stat -c%s "$TMPD/k.mb") Oktette)" \
    || { bad "the kernel does not build"; tail -12 "$TMPD/k.log" | sed 's/^/        /'
         echo "GLYPHE: $pass bestanden, $fail gescheitert"; exit 1; }

PROGS="desktop taskbar settings launcher dhcp explorer widgetdemo locate sh echo ls cat edit taskmgr"
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s faellt"
bauen_ok=1
for p in $PROGS; do
    UPROF=""; UCRT="$TMPD/crt.o"
    grep -qa '^profile app' "kernel/user/$p.fi" && { UPROF=--profile=app; UCRT=""; }
    "$FIRNC" $UPROF -c "kernel/user/$p.fi" -o "$TMPD/$p.o" > "$TMPD/e$p" 2>&1 \
        || { bauen_ok=0; break; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start \
        -o "$TMPD/$p.elf" $UCRT "$TMPD/$p.o" 2>/dev/null || { bauen_ok=0; break; }
    strip --strip-all "$TMPD/$p.elf"
done
[ "$bauen_ok" = 1 ] && ok "die $(echo $PROGS | wc -w) Programme bauen" \
    || { bad "the programs do not build"
         echo "GLYPHE: $pass bestanden, $fail gescheitert"; exit 1; }

python3 tools/k15/tree.py "$TMPD/baum" > "$TMPD/baum.log" 2>&1 || bad "tree.py faellt"
printf '# taskbar.conf\nedge=0\nheight=40\nwidth=0\nautohide=0\nontop=1\n' > "$TMPD/tb.conf"
ARGS=(build "$TMPD/disk.img" 65536 /lib/
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" /bin/)
for p in $PROGS; do ARGS+=("/bin/$p=$TMPD/$p.elf"); done
ARGS+=("/bin/files@/bin/explorer")
ARGS+=(/etc/ "/etc/theme=$TMPD/baum/theme" "/etc/taskbar.conf=$TMPD/tb.conf")
while read -r z; do ARGS+=("$z"); done < <(python3 tools/k15/bundle.py assets/apps "$TMPD/buendel" "nur=$PROGS")
while read -r z; do ARGS+=("$z"); done < "$TMPD/baum/liste"
bash tools/mkfsfi/mkfs.sh "${ARGS[@]}" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "the disk is ready ($(stat -c%s "$TMPD/disk.img") Oktette)" \
    || { bad "mkfs.py faellt"; tail -4 "$TMPD/mkfs.txt" | sed 's/^/        /'; }

rennen() { # name smp extra
    local name=$1 smp=$2 extra=$3
    cp -f "$TMPD/disk.img" "$TMPD/r-$name.img"
    timeout 240 $QEMU_X86 -kernel "$TMPD/k.mb" -m 512 -smp "$smp" \
        -append "nokbd nosched noproc nofs $extra" \
        -serial "file:$TMPD/r-$name.txt" -display none -no-reboot \
        -drive "file=$TMPD/r-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    rm -f "$TMPD/r-$name.img"
    return 0
}
r_fehl() { grep -a '^smp: glyphrace cores=' "$1" 2>/dev/null | tail -1 \
    | sed -n 's/.*errors=\([0-9]*\).*/\1/p'; }
r_zyk() { grep -a '^smp: glyphrace cores=' "$1" 2>/dev/null | tail -1 \
    | sed -n 's/.*cycles=\([0-9]*\).*/\1/p'; }
r_zeichen() { grep -a '^smp: glyphrace   c0' "$1" 2>/dev/null | tail -1 \
    | grep -oE 'glyphs=[0-9]+' | sed 's/.*=//' | sort -un | wc -l; }

echo
echo "== 3. the proof: all cores draw at the same instant =="
for n in 4 8; do
    rennen "n$n" "$n" "glyphrace"
    L="$TMPD/r-n$n.txt"
    grep -a '^smp: glyphrace' "$L" | sed 's/^/        /'
    zahl "Kerne mit je EIGENEM Zeichen (-smp $n)" "$(r_zeichen $L)" ge 2
    zahl "Abweichungen mit der Buehne je Kern (-smp $n)" "$(r_fehl $L)" eq 0
done

echo
echo "== 4. CONTROL 1: glyphblind -- ONE stage, as in MERGE-6 =="
for n in 4 8; do
    rennen "b$n" "$n" "glyphblind"
    L="$TMPD/r-b$n.txt"
    grep -a '^smp: glyphrace cores' "$L" | sed 's/^/        /'
    zahl "Abweichungen OHNE die Trennung (-smp $n)" "$(r_fehl $L)" ge 1
done

echo
echo "== 5. CONTROL 2: glyphtafelfrei -- the glyph store without lock =="
rennen tf 4 "glyphrace glyphtafelfrei"
TFF=$(r_fehl "$TMPD/r-tf.txt")
if grep -qa '^panic:' "$TMPD/r-tf.txt"; then
    ok "without the table lock the KERNEL dies: $(grep -a '^panic:' "$TMPD/r-tf.txt" | head -1 | cut -c1-72)"
elif grep -qaE 'kernel/gfx/ttf\.fi:[0-9]+:[0-9]+[[:space:]]*$' "$TMPD/r-tf.txt"; then
    # several cores panic at once and their letters interleave on the
    # serial line ("ppanaicni:c ..."), so '^panic:' is not found -- the
    # source position of the panic still stands on its own line
    ok "without the table lock the KERNEL dies (panic of several cores, interleaved): $(grep -aoE 'kernel/gfx/ttf\.fi:[0-9]+:[0-9]+[[:space:]]*$' "$TMPD/r-tf.txt" | head -1 | tr -d "\r")"
elif [ -n "$TFF" ] && [ "$TFF" -ge 1 ]; then
    ok "without the table lock: $TFF deviations"
elif grep -qa 'grace font=' "$TMPD/r-tf.txt" \
     && [ -z "$TFF" ] && ! grep -qa '^kernel: done' "$TMPD/r-tf.txt"; then
    # four cores panicking in the same instant interleave EVERY letter,
    # even the source position is shredded -- but the race started and the
    # kernel reached neither its result line nor 'kernel: done'
    ok "without the table lock the KERNEL dies in the middle of the race (no result, no 'kernel: done')"
else
    bad "without the table lock NOTHING happens -- then it measures nothing either (LAEUFE=$LAEUFE)"
fi

echo
echo "== 6. THE MEASUREMENT THAT DECIDED: per core against one lock =="
for n in 4 8; do
    rennen "s$n" "$n" "glyphrace glyphsperre"
    L="$TMPD/r-s$n.txt"
    zahl "Abweichungen mit EINER Sperre (-smp $n)" "$(r_fehl $L)" eq 0
    a=$(r_zyk "$TMPD/r-n$n.txt"); b=$(r_zyk "$L")
    if [ -n "$a" ] && [ -n "$b" ] && [ "$a" -gt 0 ]; then
        printf '  ZAHL  -smp %s: je Kern %s Zyklen, eine Sperre %s Zyklen (Faktor %s,%02d)\n' \
            "$n" "$a" "$b" "$((b / a))" "$(( (b * 100 / a) % 100 ))"
    fi
done

schreibtisch() { # name smp extra
    local name=$1 smp=$2 extra=$3
    cp -f "$TMPD/disk.img" "$TMPD/d-$name.img"
    local A="gfx wm wig desk wmhold wiglong wmdauer wigapp=/bin/taskmgr,report,takt,500 wighalt=60"
    A="$A r3alle nokbd nosched noproc nofs $extra"
    timeout "$SEK" $QEMU_X86 -kernel "$TMPD/k.mb" -m 512 -smp "$smp" \
        -append "$A" -serial "file:$TMPD/d-$name.txt" -display none \
        -no-reboot -vga std \
        -drive "file=$TMPD/d-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    rm -f "$TMPD/d-$name.img"
}
serie() { # praefix smp extra -> "panics laeufe zeilen starts"
    local pre=$1 smp=$2 extra=$3 i=1
    while [ $i -le "$LAEUFE" ]; do
        while [ "$(jobs -rp | wc -l)" -ge "$PAR" ]; do sleep 0.5; done
        schreibtisch "$pre$i" "$smp" "$extra" &
        i=$((i + 1))
    done
    wait
    local p=0 l=0 z=0 s=0
    for f in "$TMPD"/d-"$pre"[0-9]*.txt; do
        [ -e "$f" ] || continue
        l=$((l + 1))
        grep -qa '^panic:\|EXCEPTION' "$f" && p=$((p + 1))
        z=$((z + $(grep -ac 'taskmgr: row' "$f")))
        grep -qa '^desk: start /bin/taskmgr ' "$f" && s=$((s + 1))
    done
    echo "$p $l $z $s"
}

echo
echo "== 7. the case that triggered the round: $LAEUFE runs per core count =="
for n in 4 8; do
    read -r P L Z S <<<"$(serie "f$n" "$n" "")"
    printf '        -smp %s: %s Laeufe, %s mit Panic, %s Meldezeilen, %s mal gestartet\n' \
        "$n" "$L" "$P" "$Z" "$S"
    zahl "Laeufe mit -smp $n" "$L" ge "$LAEUFE"
    zahl "davon mit Panic oder Ausnahme (-smp $n)" "$P" eq 0
    zahl "der Aufgabenverwalter startete und meldete (-smp $n)" "$Z" ge 1
done

echo
echo "== 8. GEGENPROBE 3: dieselben Laeufe mit glyphblind =="
read -r P L Z S <<<"$(serie gb4 4 "glyphblind")"
printf '        -smp 4 glyphblind: %s Laeufe, %s mit Panic/Ausnahme, %s Meldezeilen\n' \
    "$L" "$P" "$Z"
if [ "$P" -ge 1 ]; then
    ok "with ONE stage it still breaks: $P of $L runs"
else
    printf '  ZAHL  mit EINER Buehne im Schreibtischlauf diesmal kein Bruch (0 von %s) -- Zufall, siehe Abschnitt 4/5\n' "$L"
fi

echo
echo "== 9. the single-core leftovers, counted at the source =="
EK_SOLL=${EK_SOLL:-67}
ekz=$(python3 tools/multicore/onecore.py)
echo "        $ekz"
ek=$(echo "$ekz" | sed -n 's/.*offen=\([0-9]*\).*/\1/p')
if [ -n "$ek" ] && [ "$ek" -le "$EK_SOLL" ] 2>/dev/null; then
    ok "functions with a data-side buffer without a lock word: $ek (contract: at most $EK_SOLL)"
else
    bad "single-core leftovers: $ek, contract is at most $EK_SOLL"
fi
if echo "$ekz" | grep -q 'wig.fi'; then
    bad "wig.fi is back in the open list"
else
    ok "wig.fi is NO longer in the open list"
fi

echo
echo "GLYPHE: $pass bestanden, $fail gescheitert"
[ "$fail" -eq 0 ]
