#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/glyphe/run.sh -- RUNDE GLYPHE: DER ZEICHENWEG AUF MEHREREN KERNEN.
#
# WORUM ES GEHT. `wig.glyph_into` hat die Antwort auf einen `WIG_GLYPH`
# in EINEM Puffer der Datenseite zusammengebaut (`base(state) +
# STAGE_OFF`): sechs Kopfworte, dann die Bildpunkte, dann alles am
# Stueck nach Ring 3. Und `wig.blit` -- der Weg, durch den JEDE
# Fensterzeile geht -- benutzte DENSELBEN Puffer, ohne jede Sperre.
# Zeichnen zwei Kerne gleichzeitig, steht im Kopf die Breite des einen
# Zeichens und dahinter die Bildpunkte des anderen, und der Klient
# rechnet `gw * gh` auf Zahlen, die nicht zusammengehoeren:
#
#     panic: integer overflow in 'u64 * u64' at wlibc.fi:1128
#
# GEMESSEN in Runde MERGE-6, gleicher Kern, gleiche Platte:
# `-smp 1` 0 Panics bei 212 Meldezeilen, `-smp 4` ein Panic in fuenf
# Laeufen. Die Buehnensperre jener Runde senkte die Rate und schloss
# die Luecke NICHT -- sie lag nur um `glyph_into`, nicht um `blit`.
#
# WAS DIESE RUNDE GEBAUT HAT:
#   * JE KERN EINE BUEHNE (`kstate.WIGST_OFF`, MAX_CPUS Seiten,
#     angesprochen ueber `cpu.here` wie `C_KSTACK` ueber die GS-Basis).
#     Sicher, weil `MSR_SFMASK` IF fuer den ganzen Systemaufruf unten
#     haelt: darin wird nicht verdraengt und nicht der Kern gewechselt.
#   * DEN GLYPHENSPEICHER UNTER EINE SPERRE (`ttf.tafel_an`): der
#     Schluessel wurde vor den Daten veroeffentlicht, der Stossallokator
#     und die Kantenliste gehoerten allen.
#   * DIE ZWISCHENABLAGE unter dieselbe Sperre -- derselbe Fehler, vom
#     erweiterten `tools/vielkern/einkern.py` gefunden.
#   * EINEN ZWEITEN RIEGEL IN RING 3 (`wlibc.gload`): ein Kopf, der
#     nicht zur gemeldeten Laenge passt, wird verworfen statt
#     multipliziert.
#
# WIE ES NACHGEWIESEN WIRD. Wie `fsrace` in MERGE-6: nicht durch
# Zusehen, sondern erzwungen. `glyphrace` laesst ueber `smp.run_phase`
# ALLE Kerne im selben Augenblick durch `wig.glyph_build` zeichnen --
# den Rumpf des Systemaufrufs, keine Nachbildung -- und in derselben
# Runde eine Bildpunktzeile auf die Buehne legen, so wie `blit` es tut.
# Dazu DREI Gegenproben, denn eine Zusage ohne Gegenprobe ist eine
# Behauptung:
#
#   `glyphblind`      eine Buehne fuer alle, Sperre nur um die Glyphe
#                     -- WOERTLICH der Stand von MERGE-6.
#   `glyphsperre`     eine Buehne, aber `blit` UND `glyph_into` unter
#                     derselben Sperre -- die zweite Bauform, gegen die
#                     gemessen wurde.
#   `glyphtafelfrei`  der Glyphenspeicher ohne seine Sperre.
#
# Und zuletzt der Fall, der die Runde ausgeloest hat: der volle
# Schreibtisch mit dem Aufgabenverwalter, $LAEUFE mal mit vier und
# $LAEUFE mal mit acht Kernen. Eine gruene Runde reicht nicht -- der
# Fehler kam in einem von fuenf Laeufen.
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

LAEUFE=${OSUM_GLYPHE_LAEUFE:-20}
PAR=${OSUM_GLYPHE_PAR:-4}
SEK=${OSUM_GLYPHE_SEK:-200}

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
zahl() { # name wert op soll
    local name=$1 wert=$2 op=$3 soll=$4
    if [ -z "$wert" ]; then bad "$name: keine Zahl (wollte $op $soll)"; return; fi
    if [ "$wert" -"$op" "$soll" ] 2>/dev/null; then ok "$name: $wert"
    else bad "$name: $wert, wollte $op $soll"; fi
}

echo "== 1. an der Quelle: wer holt die Buehne, und woher =="
# Der Fehler war nicht, dass eine Sperre fehlte -- er war, dass ZWEI
# Wege denselben Puffer nahmen und nur einer davon gesichert war. Also
# wird hier gezaehlt, wer den Puffer ueberhaupt anfasst.
ROH=$(grep -c 'base(state) + STAGE_OFF' kernel/wig.fi)
zahl "Stellen, die die geteilte Buehne noch direkt nehmen" "$ROH" eq 1
grep -q 'fn stage_of' kernel/wig.fi \
    && ok "wig.stage_of gibt es" || bad "wig.stage_of fehlt"
for f in blit glyph_into; do
    n=$(awk "/^fn $f\(/,/^}/" kernel/wig.fi | grep -c 'stage_of(state)')
    if [ "$n" -ge 1 ]; then ok "wig.$f holt die Buehne ueber stage_of"
    else bad "wig.$f holt die Buehne NICHT ueber stage_of"; fi
done
grep -q 'kstate.WIGST_OFF + k \* STAGE_MAX' kernel/wig.fi \
    && ok "stage_of rechnet mit der Kernnummer (WIGST_OFF + k * STAGE_MAX)" \
    || bad "stage_of rechnet nicht je Kern"
if awk '/^fn glyph\(/,/^}/' kernel/ttf.fi | grep -q 'tafel_an('; then
    ok "ttf.glyph nimmt die Tafelsperre"
else bad "ttf.glyph nimmt die Tafelsperre nicht"; fi
if awk '/^fn glyph\(/,/^}/' kernel/ttf.fi | grep -q 'irq_aus()'; then
    ok "und haelt dabei die Unterbrechungen an (die Kennung ist eine Kernnummer)"
else bad "ttf.glyph haelt die Unterbrechungen nicht an"; fi
if awk '/^fn gload\(/,/^}/' kernel/user/wlibc.fi | grep -q 'gw > GMAX'; then
    ok "wlibc.gload prueft den Kopf, bevor es 'gw * gh' rechnet"
else bad "wlibc.gload prueft den Kopf nicht"; fi

echo
echo "== 2. bauen: Kern, Programme, Platte =="
bash tools/build-kernel.sh "$TMPD/k.mb" > "$TMPD/k.log" 2>&1 \
    && ok "der Kern baut ($(stat -c%s "$TMPD/k.mb") Oktette)" \
    || { bad "der Kern baut nicht"; tail -12 "$TMPD/k.log" | sed 's/^/        /'
         echo "GLYPHE: $pass bestanden, $fail gescheitert"; exit 1; }

PROGS="desktop taskbar settings launcher dhcp explorer widgetdemo locate sh echo ls cat edit taskmgr"
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s faellt"
bauen_ok=1
for p in $PROGS; do
    vendor/firn/bin/firnc "kernel/user/$p.fi" -o "$TMPD/$p.o" > "$TMPD/e$p" 2>&1 \
        || { bauen_ok=0; break; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start \
        -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null || { bauen_ok=0; break; }
    strip --strip-all "$TMPD/$p.elf"
done
[ "$bauen_ok" = 1 ] && ok "die $(echo $PROGS | wc -w) Programme bauen" \
    || { bad "die Programme bauen nicht"
         echo "GLYPHE: $pass bestanden, $fail gescheitert"; exit 1; }

python3 tools/k15/tree.py "$TMPD/baum" > "$TMPD/baum.log" 2>&1 || bad "tree.py faellt"
printf '# taskbar.conf\nedge=0\nheight=40\nwidth=0\nautohide=0\nontop=1\n' > "$TMPD/tb.conf"
ARGS=(build "$TMPD/disk.img" 16384 /lib/
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" /bin/)
for p in $PROGS; do ARGS+=("/bin/$p=$TMPD/$p.elf"); done
ARGS+=("/bin/files@/bin/explorer")
ARGS+=(/etc/ "/etc/theme=$TMPD/baum/theme" "/etc/taskbar.conf=$TMPD/tb.conf")
while read -r z; do ARGS+=("$z"); done < <(python3 tools/k15/bundle.py assets/apps "$TMPD/buendel" "nur=$PROGS")
while read -r z; do ARGS+=("$z"); done < "$TMPD/baum/liste"
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "die Platte steht ($(stat -c%s "$TMPD/disk.img") Oktette)" \
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
r_fehl() { grep -a '^smp: glyphrace kerne=' "$1" 2>/dev/null | tail -1 \
    | sed -n 's/.*fehler=\([0-9]*\).*/\1/p'; }
r_zyk() { grep -a '^smp: glyphrace kerne=' "$1" 2>/dev/null | tail -1 \
    | sed -n 's/.*zyklen=\([0-9]*\).*/\1/p'; }
r_zeichen() { grep -a '^smp: glyphrace   c0' "$1" 2>/dev/null | tail -1 \
    | grep -oE 'zeichen=[0-9]+' | sed 's/.*=//' | sort -un | wc -l; }

echo
echo "== 3. der Nachweis: alle Kerne zeichnen im selben Augenblick =="
for n in 4 8; do
    rennen "n$n" "$n" "glyphrace"
    L="$TMPD/r-n$n.txt"
    grep -a '^smp: glyphrace' "$L" | sed 's/^/        /'
    zahl "Kerne mit je EIGENEM Zeichen (-smp $n)" "$(r_zeichen $L)" ge 2
    zahl "Abweichungen mit der Buehne je Kern (-smp $n)" "$(r_fehl $L)" eq 0
done

echo
echo "== 4. GEGENPROBE 1: glyphblind -- EINE Buehne, wie in MERGE-6 =="
# Ohne diesen Abschnitt misst Abschnitt 3 nichts: null Abweichungen
# koennten auch heissen, dass gar nicht gezeichnet wurde.
for n in 4 8; do
    rennen "b$n" "$n" "glyphblind"
    L="$TMPD/r-b$n.txt"
    grep -a '^smp: glyphrace kerne' "$L" | sed 's/^/        /'
    zahl "Abweichungen OHNE die Trennung (-smp $n)" "$(r_fehl $L)" ge 1
done

echo
echo "== 5. GEGENPROBE 2: glyphtafelfrei -- der Glyphenspeicher ohne Sperre =="
rennen tf 4 "glyphrace glyphtafelfrei"
TFF=$(r_fehl "$TMPD/r-tf.txt")
if grep -qa '^panic:' "$TMPD/r-tf.txt"; then
    ok "ohne die Tafelsperre stirbt der KERN: $(grep -a '^panic:' "$TMPD/r-tf.txt" | head -1 | cut -c1-72)"
elif [ -n "$TFF" ] && [ "$TFF" -ge 1 ]; then
    ok "ohne die Tafelsperre: $TFF Abweichungen"
else
    bad "ohne die Tafelsperre passiert NICHTS -- dann misst sie auch nichts"
fi

echo
echo "== 6. DIE MESSUNG, DIE ENTSCHIEDEN HAT: je Kern gegen eine Sperre =="
# Bauform A (`glyphsperre`) ist RICHTIG -- und teuer: sie stellt das
# Zeichnen aller Kerne wieder in eine Reihe. Beide Zahlen stehen hier,
# damit die Wahl nachrechenbar ist und nicht behauptet.
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
    # `wighalt=60` -- DREIMAL SO LANG WIE DIE VORGABE. Der Fehler kam
    # in einem von fuenf Laeufen; ein Lauf, der nach zwanzig Sekunden
    # aufhoert, gibt ihm ein Drittel der Gelegenheiten.
    local A="gfx wm wig desk wmhold wiglong wmdauer wigapp=/bin/taskmgr,melde,takt,500 wighalt=60"
    A="$A nokbd nosched noproc nofs $extra"
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
        z=$((z + $(grep -ac 'taskmgr: zeile' "$f")))
        grep -qa '^desk: start /bin/taskmgr ' "$f" && s=$((s + 1))
    done
    echo "$p $l $z $s"
}

echo
echo "== 7. der Fall, der die Runde ausgeloest hat: $LAEUFE Laeufe je Kernzahl =="
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
# Ohne sie sagt Abschnitt 7 nur, dass an DIESEM Tag nichts passiert ist.
read -r P L Z S <<<"$(serie gb4 4 "glyphblind")"
printf '        -smp 4 glyphblind: %s Laeufe, %s mit Panic/Ausnahme, %s Meldezeilen\n' \
    "$L" "$P" "$Z"
if [ "$P" -ge 1 ]; then
    ok "mit EINER Buehne bricht es weiterhin: $P von $L Laeufen"
else
    bad "mit EINER Buehne passiert nichts -- dann misst Abschnitt 7 nichts (Rate war 1 von 5)"
fi

echo
echo "== 9. die Ein-Kern-Reste, an der Quelle gezaehlt =="
EK_SOLL=${EK_SOLL:-66}
ekz=$(python3 tools/vielkern/einkern.py)
echo "        $ekz"
ek=$(echo "$ekz" | sed -n 's/.*offen=\([0-9]*\).*/\1/p')
if [ -n "$ek" ] && [ "$ek" -le "$EK_SOLL" ] 2>/dev/null; then
    ok "Funktionen mit einem Puffer der Datenseite ohne Sperrwort: $ek (Vertrag: hoechstens $EK_SOLL)"
else
    bad "Ein-Kern-Reste: $ek, Vertrag ist hoechstens $EK_SOLL"
fi
if echo "$ekz" | grep -q 'wig.fi'; then
    bad "wig.fi steht wieder in der offenen Liste"
else
    ok "wig.fi steht NICHT mehr in der offenen Liste"
fi

echo
echo "GLYPHE: $pass bestanden, $fail gescheitert"
[ "$fail" -eq 0 ]
