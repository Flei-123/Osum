#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/vielkern/run.sh -- RING 3 AUF ALLEN KERNEN, UND DER RIEGEL DAVOR.
#
#   bash tools/vielkern/run.sh
#
# ======================================================================
# WARUM ES DIESEN LAEUFER GIBT
# ======================================================================
#
# Runde BLECHKERN (a53cb1d) hat einen Satz in einen Kommentar geschrieben
# und nicht in den Code: "Ring 3 bleibt auf dem Startkern". Die Zeile
# darunter stand auf `ANY_CPU`. Ein Anwendungskern durfte damit einen
# Ring-3-Prozess nehmen, dessen `syscall` den Kernstapel aus EINEM Wort
# fuer die ganze Maschine holte -- zwei Kerne auf einem Stapel.
#
# GEMERKT HAT ES NIEMAND. Kein Laeufer hat je gefragt, auf welchem Kern
# ein Ring-3-Prozess wirklich lief; die Abnahme war gruen. Aufgefallen
# ist es auf ECHTER HARDWARE, auf Justins Brett, als Foto:
#
#     VEK 6 #UD RIP 0x80   KERN 2   ART 1
#
# 0x80 ist keine Adresse, sondern der Rest einer ueberschriebenen
# Ruecksprungkette.
#
# Ein Riegel, dessen Bruch niemand herbeifuehren kann, ist nicht
# geprueft, sondern geglaubt. Dieser Laeufer kann ihn brechen.
#
# ======================================================================
# WAS GEMESSEN WIRD
# ======================================================================
#
# A. STATISCH, an den Quellen -- die Klasse Fehler, die still bleibt:
#    1. Die Feldabstaende in isr.s (`CPU_SYSRSP`, `CPU_KSTACK`,
#       `CPU_SYSCALLS`) stimmen Zahl fuer Zahl mit cpu.fi ueberein.
#       Laufen sie auseinander, holt der Einsprung seinen Kernstapel aus
#       einem falschen Feld -- und zwar leise.
#    2. `sched.darf_ring3` gibt es, und die Auswahl im Ablaufplaner ruft
#       sie wirklich. Das ist die Zeile, die in BLECHKERN gefehlt hat.
#    3. Kein Weg in fs.fi fasst einen geteilten Blockpuffer an, ohne
#       durch `enter` (also `atomic.L_FS`) zu gehen. Das war die zweite
#       Ursache dieser Runde und wird deshalb an der QUELLE nachgezaehlt
#       und nicht nur am Verhalten.
#
# B. AM LAUFENDEN KERN, voller Schreibtisch, vier Ring-3-Programme:
#    4. `-smp 4 r3alle`  -- R3W 0, R3K >= 2, keine Ausnahme, alle vier
#       Programme bekommen eine pid, die Systemaufrufe verteilen sich
#       auf mehr als einen Kern, `abw` 0.
#    5. `-smp 8 r3alle`  -- dasselbe mit acht.
#    6. GEGENPROBE ZUR MESSUNG: `-smp 4` OHNE `r3alle` -- R3K MUSS 1
#       sein und alle Systemaufrufe auf c0. Eine Messung, die auch ohne
#       die Eigenschaft dasselbe sagt, misst nichts.
#    7. GEGENPROBE ZUM RIEGEL, HAELFTE 1: `gsluege` gibt jedem
#       Anwendungskern eine FALSCHE GS-Basis -- der Zustand vom 05.09.
#       Der Riegel MUSS greifen: R3W > 0, R3K 1, KEINE Ausnahme, die
#       Maschine lebt.
#    8. GEGENPROBE ZUM RIEGEL, HAELFTE 2: `gsluege r3blind` schaltet den
#       Riegel zusaetzlich ab. Jetzt MUSS die Maschine brechen -- und
#       zwar in einem Ring-3-Programm. Faellt diese Zusage, dann rettet
#       nicht der Riegel die Maschine, sondern der Zufall, und Zusage 7
#       ist wertlos.
#
#    9. RUNDE MERGE-6, DER INODEPUFFER AUF BESTELLUNG. Bis hierher war
#       der Fund von VIELKERN 3 (`fs.inode_get` liest in EINEN Puffer
#       der ganzen Maschine) nur STATISCH gesichert -- Abschnitt 3
#       zaehlt an der Quelle nach, dass kein Weg ohne `enter`
#       auskommt. Eine Zusage ueber Text faellt, wenn jemand die
#       Sperre entfernt, und sie faellt NICHT, wenn die Sperre dasteht
#       und nicht wirkt.
#       `fsrace` erzwingt den Fall: die Sperre `smp.run_phase` startet
#       ALLE Kerne im selben Augenblick, jeder liest zwanzigtausend Mal
#       die Art SEINES Inodes -- aus einem EIGENEN Inodeblock, denn der
#       geteilte Puffer fasst einen BLOCK und nicht einen Inode.
#       GEGENPROBE `fsblind`: dieselbe Schleife durch den Rumpf, den
#       `inode_get` VOR VIELKERN 3 hatte. Sie MUSS fallen.
#
#   10. RUNDE MERGE-6, DIE UEBRIGEN EIN-KERN-RESTE. Ein Puffer in der
#       Datenseite gehoert der ganzen Maschine. `tools/vielkern/onecore.py`
#       zaehlt an der Quelle, wie viele Funktionen einen benutzen, ohne
#       dass ein Sperrwort in ihrem Rumpf steht. Die Zahl ist KEINE
#       Fehlerliste -- sie ist ein Vertrag: sie darf nicht wachsen,
#       ohne dass jemand es aufschreibt.
#
# Zusage 8 ist der eigentliche Punkt: sie ist die einzige, die BEWEIST,
# dass Zusage 7 etwas misst.
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
zahl() { # name wert op soll
    local name=$1 wert=$2 op=$3 soll=$4
    if [ -z "$wert" ]; then bad "$name: keine Zahl gefunden (wollte $op $soll)"; return; fi
    if [ "$wert" -"$op" "$soll" ] 2>/dev/null; then ok "$name: $wert"
    else bad "$name: $wert, wollte $op $soll"; fi
}

echo "== 1. die Zahlen, die auf beiden Seiten gleich sein muessen =="
for paar in "CPU_SYSRSP:C_SYSRSP" "CPU_KSTACK:C_KSTACK" "CPU_SYSCALLS:C_SYSCALLS"; do
    a=${paar%%:*}; b=${paar##*:}
    va=$(grep -aoE "\.set $a, *[0-9]+" kernel/arch/x86_64/isr.s | grep -oE '[0-9]+' | head -1)
    vb=$(grep -aoE "const $b: u64 = [0-9]+" kernel/cpu.fi | grep -oE '[0-9]+$' | head -1)
    if [ -n "$va" ] && [ "$va" = "$vb" ]; then ok "isr.s $a = cpu.fi $b = $va"
    else bad "isr.s $a='$va' gegen cpu.fi $b='$vb'"; fi
done
grep -qa 'incq %gs:CPU_SYSCALLS' kernel/arch/x86_64/isr.s \
    && ok "syscall_entry zaehlt ueber die GS-Basis mit (der Beweis je Kern)" \
    || bad "in syscall_entry fehlt 'incq %gs:CPU_SYSCALLS'"

echo
echo "== 2. der Riegel steht im CODE und nicht im Kommentar =="
grep -qa '^fn darf_ring3' kernel/sched.fi \
    && ok "sched.darf_ring3 gibt es" || bad "sched.darf_ring3 fehlt"
grep -qa 'darf_ring3(state, i, me)' kernel/sched.fi \
    && ok "die Auswahl des Ablaufplaners ruft ihn wirklich" \
    || bad "darf_ring3 wird in der Auswahl NICHT gerufen -- genau der Fehler von BLECHKERN"
grep -qa 'gs_bereit(state, me)' kernel/sched.fi \
    && ok "und er fragt die GEPRUEFTE GS-Basis ab" \
    || bad "darf_ring3 fragt die GS-Basis nicht ab"
# `gs_gut` ist ein festes Feld von acht. Waechst MAX_CPUS, ohne dass es
# mitwaechst, meldet `gs_bereit` fuer jeden Kern ab dem neunten "nein" --
# Ring 3 liefe dort nie, und niemand saehe warum.
mc=$(grep -aoE 'const MAX_CPUS: u64 = [0-9]+' kernel/kstate.fi | grep -oE '[0-9]+$')
gg=$(grep -aoE 'static mut gs_gut: \[u64; [0-9]+\]' kernel/sched.fi | sed -n 's/.*; \([0-9]*\)\]/\1/p')
if [ -n "$mc" ] && [ "$mc" = "$gg" ]; then ok "kstate.MAX_CPUS = sched.gs_gut = $mc"
else bad "MAX_CPUS=$mc, aber gs_gut fasst $gg -- Kerne darueber bekaemen nie Ring 3"; fi

echo
echo "== 3. kein geteilter Blockpuffer ohne die Sperre L_FS =="
py=$(python3 - <<'PYEOF'
import re
s=open("kernel/fs.fi","rb").read().decode("utf-8","surrogateescape")
funcs={}; cur=None; body=[]
for l in s.split("\n"):
    m=re.match(r"^fn (\w+)\(", l)
    if m:
        if cur: funcs[cur]=body
        cur=m.group(1); body=[]
    elif cur is not None:
        if l=="}": funcs[cur]=body; cur=None; body=[]
        else: body.append(l)
if cur: funcs[cur]=body
m=re.search(r"^export \{(.*?)^\}", s, re.S|re.M)
exp=set(t.strip() for t in re.split(r"[,\s]+", m.group(1)) if re.match(r"^[a-zA-Z_]\w*$", t.strip()))
def enter(f): return "enter(state)" in "\n".join(funcs.get(f,[]))
def roh(f):
    return bool(re.search(r"buf_(in|dt|bm|sb|ib|i2)\(|ofsj\.(read|write)\(|blk\.(read|write)\(",
                          "\n".join(funcs.get(f,[]))))
def callers(f):
    return [n for n,b in funcs.items() if n!=f and re.search(r"(?<![\w.])"+f+r"\(", "\n".join(b))]
# RUNDE MERGE-6: DIE GEGENPROBE IST KEIN FEHLER.
# `inode_get_blind` ist WOERTLICH der Rumpf, den `inode_get` vor
# VIELKERN 3 hatte, und `race_core` ruft ihn -- absichtlich und nur,
# wenn `fsblind` auf der Befehlszeile steht. Ein Pruefer, der seine
# eigene Gegenprobe anzeigt, zwingt den naechsten dazu, die Gegenprobe
# zu loeschen statt sie zu behalten. Beide stehen deshalb HIER mit
# Namen, und wer einen dritten Namen dazutut, muss ihn hier eintragen
# und begruenden.
mitwissen={"inode_get_blind","race_core"}
offen=[f for f in funcs if roh(f) and not enter(f) and f not in mitwissen]
leck=[]; gesehen=set(); todo=list(offen)
while todo:
    f=todo.pop()
    if f in gesehen: continue
    gesehen.add(f)
    if enter(f): continue
    if f in mitwissen: continue
    if f in exp: leck.append(f); continue
    cs=callers(f)
    if not cs: leck.append(f+"(ohne-Aufrufer)")
    todo.extend(cs)
print(len(funcs), len(offen), ",".join(sorted(set(leck))) or "-")
PYEOF
)
nfun=$(echo "$py" | awk '{print $1}')
nroh=$(echo "$py" | awk '{print $2}')
leck=$(echo "$py" | awk '{print $3}')
if [ "$leck" = "-" ]; then
    ok "$nfun Funktionen in fs.fi, $nroh fassen Bloecke an -- jeder Weg nach draussen geht durch enter()"
else
    bad "diese Wege erreichen einen geteilten Puffer OHNE L_FS: $leck"
fi

echo
echo "== 4. der Kern und die Schreibtischplatte =="
bash tools/build-kernel.sh "$TMPD/k.mb" > "$TMPD/k.log" 2>&1 \
    && ok "der Kern baut ($(stat -c%s "$TMPD/k.mb") Oktette)" \
    || { bad "der Kern baut nicht"; tail -12 "$TMPD/k.log" | sed 's/^/        /'; \
         echo "VIELKERN: $pass bestanden, $fail gescheitert"; exit 1; }

PROGS="desktop taskbar settings launcher dhcp explorer widgetdemo locate sh echo ls cat edit"
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s laesst sich nicht assemblieren"
bauen_ok=1
for p in $PROGS; do
    vendor/firn/bin/firnc "kernel/user/$p.fi" -o "$TMPD/$p.o" > "$TMPD/e$p" 2>&1 || { bauen_ok=0; break; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start \
        -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null || { bauen_ok=0; break; }
    strip --strip-all "$TMPD/$p.elf"
done
if [ "$bauen_ok" = 1 ]; then
    ok "die $(echo $PROGS | wc -w) Programme des Schreibtischs bauen"
else
    bad "die Programme bauen nicht"
    echo "VIELKERN: $pass bestanden, $fail gescheitert"; exit 1
fi

python3 tools/k15/tree.py "$TMPD/baum" > "$TMPD/baum.log" 2>&1 || bad "tools/k15/tree.py faellt"
printf '# taskbar.conf\nedge=0\nheight=40\nwidth=0\nautohide=0\nontop=1\n' > "$TMPD/tb.conf"
ARGS=(build "$TMPD/disk.img" 16384 /lib/
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" /bin/)
for p in $PROGS; do ARGS+=("/bin/$p=$TMPD/$p.elf"); done
ARGS+=("/bin/files@/bin/explorer")
ARGS+=(/etc/ "/etc/theme=$TMPD/baum/theme" "/etc/taskbar.conf=$TMPD/tb.conf")
# RUNDE MERGE-6: `nur=` -- SONST IST DIESER LAEUFER TOT.
# Die Runde WERKZEUGE hat assets/apps/taskmgr.osp dazugelegt. Ein
# Buendel ist ein VERWEIS auf eine Datei unter /bin; steht sie nicht in
# $PROGS, bricht mkfs.py mit "gibt es nicht" ab -- und dann faellt
# ALLES ab Abschnitt 5, weil es keine Platte gibt. Gemessen am
# zusammengefuehrten Stand VOR dieser Zeile: 22 rote Zusagen, davon 21
# allein an der fehlenden Platte.
while read -r z; do ARGS+=("$z"); done < <(python3 tools/k15/bundle.py assets/apps "$TMPD/buendel" "nur=$PROGS")
while read -r z; do ARGS+=("$z"); done < "$TMPD/baum/liste"
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "die Platte steht ($(stat -c%s "$TMPD/disk.img") Oktette)" \
    || { bad "mkfs.py faellt"; tail -4 "$TMPD/mkfs.txt" | sed 's/^/        /'; }

BASE="gfx wm wig desk wmhold wiglong nokbd nosched noproc nofs tafel einst"
lauf() { # name smp extra [limit]
    local name=$1 smp=$2 extra=$3 limit=${4:-200}
    local out="$TMPD/$name.txt"
    rm -f "$out"; : > "$out"
    cp -f "$TMPD/disk.img" "$TMPD/live-$name.img"
    timeout "$limit" $QEMU_X86 -kernel "$TMPD/k.mb" -m 512 -smp "$smp" \
        -append "$BASE $extra" -serial "file:$out" -display none -no-reboot \
        -vga std -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/$name.qemu" 2>&1 &
    local pid=$! i=0
    # GEWARTET WIRD AUF FUENF MESSTAFELN, NICHT AUF EINE.
    #
    # Die Tafel geht alle fuenf Sekunden auf die Leitung. Die erste
    # steht, BEVOR die Programme wirklich gelaufen sind -- `R3K` ist
    # dann 1, weil noch nichts gewandert ist, und die Zahl der
    # Systemaufrufe einstellig. Gemessen an einem zu frueh
    # abgebrochenen Lauf: `summe=8`. Fuenf Tafeln sind rund zwanzig
    # Sekunden Schreibtischbetrieb, und das ist die Zeit, in der der
    # Fehler der Runde BLECHKERN (Abschnitt 9) auch wirklich zuschlaegt.
    # `wm: hold` taugt als Marke NICHT: unter `gsluege` laeuft alles auf
    # Kern 0 und die Zeile kommt in der Zeit gar nicht.
    while [ $i -lt 800 ]; do
        [ "$(grep -ac '^tafel: 23 SICHER' "$out" 2>/dev/null)" -ge 5 ] && break
        grep -qa '^absturz:  0\|^\*\*\* EXCEPTION' "$out" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.2; i=$((i + 1))
    done
    sleep 2
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    return 0
}
# ACHTUNG BEIM AUSLESEN: in "R3K" steckt eine 3. `grep -oE '[0-9]+'`
# liefert darauf ZWEI Zahlen ("3" und den Wert), und die Zusage misst
# dann die 3 aus dem Namen. Deshalb ueberall das zweite Feld.
w_r3k()  { grep -a '^tafel: 23 SICHER' "$1" | tail -1 | grep -oE 'R3K [0-9]+' | awk '{print $2}'; }
w_r3w()  { grep -a '^tafel: 23 SICHER' "$1" | tail -1 | grep -oE 'R3W [0-9]+' | awk '{print $2}'; }
w_abw()  { grep -a '^r3: syscalls' "$1" | tail -1 | sed -n 's/.*abw=\([0-9]*\).*/\1/p'; }
w_kerne(){ grep -a '^r3: prozesse' "$1" | tail -1 | sed -n 's/.* n=\([0-9]*\).*/\1/p'; }
w_scpu() { grep -a '^r3: syscalls' "$1" | tail -1 \
    | grep -oE 'c[0-9]+=[0-9]+' | grep -vE '=0$' | wc -l; }
w_exc()  { grep -ac '^\*\*\* EXCEPTION\|^absturz:  0' "$1"; }
w_pid0() { grep -ac '^desk: start .* pid=0' "$1"; }

echo
echo "== 5. vier Kerne, Ring 3 auf allen (r3alle) =="
lauf a4 4 r3alle
L=$TMPD/a4.txt
zahl "R3W (Kerne ohne eigene GS-Basis)" "$(w_r3w $L)" eq 0
zahl "R3K (Kerne, auf denen Ring 3 lief)" "$(w_r3k $L)" ge 2
zahl "Kerne in der Maske der Prozesse" "$(w_kerne $L)" ge 2
zahl "Kerne, auf denen Systemaufrufe ankamen" "$(w_scpu $L)" ge 2
zahl "abw (Summe der Kernzaehler gegen kstate.SYSCALLS)" "$(w_abw $L)" eq 0
zahl "Programmstarts mit pid=0" "$(w_pid0 $L)" eq 0
zahl "Ausnahmen" "$(w_exc $L)" eq 0
grep -qa '^desk: start /bin/settings  pid=[1-9]' $L \
    && ok "auch das vierte Programm (/bin/settings) kommt hoch" \
    || bad "/bin/settings kommt nicht hoch -- genau der Fehler der Vorrunde"
grep -a '^r3: prozesse' $L | tail -1 | sed 's/^/        /'
grep -a '^r3: syscalls' $L | tail -1 | sed 's/^/        /'

echo
echo "== 6. acht Kerne =="
lauf a8 8 r3alle
L=$TMPD/a8.txt
zahl "R3W" "$(w_r3w $L)" eq 0
zahl "R3K" "$(w_r3k $L)" ge 2
zahl "Kerne mit Systemaufrufen" "$(w_scpu $L)" ge 2
zahl "abw" "$(w_abw $L)" eq 0
zahl "Programmstarts mit pid=0" "$(w_pid0 $L)" eq 0
zahl "Ausnahmen" "$(w_exc $L)" eq 0
grep -a '^r3: syscalls' $L | tail -1 | sed 's/^/        /'

echo
echo "== 7. GEGENPROBE zur Messung: dieselbe Platte mit r3eins (Ring 3 nur auf Kern 0) =="
lauf n4 4 "r3eins"
L=$TMPD/n4.txt
zahl "R3K muss 1 sein" "$(w_r3k $L)" eq 1
zahl "nur EIN Kern bekommt Systemaufrufe" "$(w_scpu $L)" eq 1
zahl "abw" "$(w_abw $L)" eq 0
zahl "Ausnahmen" "$(w_exc $L)" eq 0
grep -a '^r3: syscalls' $L | tail -1 | sed 's/^/        /'

echo
echo "== 8. GEGENPROBE zum Riegel, Haelfte 1: gsluege -- er MUSS halten =="
# Jeder Anwendungskern bekommt die GS-Basis von Kern 0. Das ist der
# Zustand, an dem Justins Brett am 05.09. gestorben ist -- nur dass ihn
# `sched.darf_ring3` jetzt sieht.
lauf g4 4 "r3alle gsluege"
L=$TMPD/g4.txt
zahl "R3W muss GROESSER null werden (die Luege wird gesehen)" "$(w_r3w $L)" ge 1
zahl "R3K faellt auf 1 zurueck (Ring 3 bleibt auf Kern 0)" "$(w_r3k $L)" eq 1
zahl "Ausnahmen -- die Maschine lebt" "$(w_exc $L)" eq 0
zahl "nur Kern 0 bekommt Systemaufrufe" "$(w_scpu $L)" eq 1
grep -a '^tafel: 23 SICHER' $L | tail -1 | sed 's/^/        /'

echo
echo "== 9. GEGENPROBE zum Riegel, Haelfte 2: gsluege r3blind -- er MUSS brechen =="
# Ohne diese Zusage misst Abschnitt 8 nichts: dass die Maschine dort
# lebt, koennte auch Zufall sein. Hier wird der Riegel abgeschaltet, und
# derselbe Fehler MUSS wiederkommen.
lauf b4 4 "r3alle gsluege r3blind" 200
L=$TMPD/b4.txt
if [ "$(w_exc $L)" -ge 1 ]; then
    ok "ohne den Riegel bricht die Maschine wieder -- er ist es, der sie haelt"
    grep -a '^absturz:  [0-6] ' $L | head -7 | sed 's/^/        /'
else
    bad "ohne den Riegel passiert NICHTS -- dann misst Abschnitt 8 nicht den Riegel"
fi
grep -qa 'ART 3' $L && ok "und zwar in einer Aufgabe der Gattung 3 (K_USER, also Ring 3)" \
    || bad "der Bruch trifft keine Ring-3-Aufgabe -- dann ist es ein anderer Fehler"

echo
echo "== 10. RUNDE MERGE-6: der Inodepuffer, auf mehreren Kernen ERZWUNGEN =="
# Der Lauf braucht kein Ring 3 und keinen Schreibtisch: er laeuft in
# `smp.stage`, also im Hochlauf, und ist nach einer Sekunde fertig.
# `nosched noproc` haelt alles andere still -- was hier misst, ist der
# Puffer und nichts sonst.
fsrace() { # name  smp  extra
    local name=$1 smp=$2 extra=$3
    cp -f "$TMPD/disk.img" "$TMPD/fsr-$name.img"
    timeout 240 $QEMU_X86 -kernel "$TMPD/k.mb" -m 512 -smp "$smp" \
        -append "nokbd nosched noproc $extra" \
        -serial "file:$TMPD/fsr-$name.txt" -display none -no-reboot \
        -drive "file=$TMPD/fsr-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    return 0
}
w_fehl() { grep -a '^smp: fsrace kerne=' "$1" | tail -1 \
    | sed -n 's/.*fehler=\([0-9]*\).*/\1/p'; }
w_inos() { grep -a '^smp: fsrace   c0' "$1" | tail -1 \
    | grep -oE 'inode=[0-9]+' | sed 's/.*=//' | sort -un | wc -l; }

fsrace mit 4 "fsrace"
L=$TMPD/fsr-mit.txt
if [ -s "$L" ]; then
    grep -a '^smp: fsrace' $L | sed 's/^/        /'
    zahl "Kerne mit je EIGENEM Inodeblock" "$(w_inos $L)" ge 2
    zahl "Abweichungen MIT der Sperre" "$(w_fehl $L)" eq 0
else
    bad "kein Mitschnitt des fsrace-Laufs"
fi

echo
echo "== 11. GEGENPROBE dazu: fsblind -- ohne die Sperre MUSS es brechen =="
# Ohne diesen Abschnitt misst Abschnitt 10 nichts: null Abweichungen
# koennten auch heissen, dass die Schleife gar nicht gelaufen ist.
fsrace ohne 4 "fsblind"
L=$TMPD/fsr-ohne.txt
if [ -s "$L" ]; then
    grep -a '^smp: fsrace' $L | sed 's/^/        /'
    zahl "Abweichungen OHNE die Sperre" "$(w_fehl $L)" ge 1
else
    bad "kein Mitschnitt des fsblind-Laufs"
fi

echo
echo "== 12. RUNDE MERGE-6: die uebrigen Ein-Kern-Reste, an der Quelle gezaehlt =="
# KEINE FEHLERLISTE, SONDERN EIN VERTRAG. Die Zahl darf nicht wachsen,
# ohne dass jemand sie hier hochsetzt und in docs/RUNDE-MERGE6.md
# aufschreibt, warum.
# RUNDE GLYPHE: 60 -> 66. Nicht, weil sechs Stellen dazugekommen
# waeren -- `onecore.py` SIEHT seit dieser Runde eine zweite Bauform
# desselben Fehlers: eine Seite, die eine Datei ueber einen EIGENEN
# Zugriff holt (`base(state) + KONST` statt `state + kstate.X_OFF`).
# Genau in dieser Form stand der Fehler, an dem MERGE-6 gescheitert
# ist. Die sechs neuen sind hwid.fi (2), ofsj.fi (2) und rand.fi (2);
# `wig.fi` war die siebte und ist repariert. Begruendung ausfuehrlich
# in docs/RUNDE-GLYPHE.md.
# RUNDE MERGE-7: 66 -> 67. Die drei neuen Stellen sind ALLE in
# `kernel/klog.fi` (Runde PROTOKOLL, in merge6 gibt es die Datei nicht):
# `base()`, `emit()` und `set_filter()` fassen `kstate.LOG_OFF` an, ohne
# dass `onecore.py` ein Sperrwort SIEHT. Sie sind trotzdem gesperrt --
# klog nimmt eine EIGENE Sperre mit `atomic.cas` auf `H_LK`
# (kernel/klog.fi:300..311), weil alle acht Plaetze in `kstate.LOCK_COUNT`
# vergeben sind und `atomic.lock_take` deshalb ausschied. `onecore.py`
# kennt nur die Namen aus SPERRE und sieht diese Bauform nicht.
#
# BELEGT, nicht behauptet: tools/protokoll/run.sh laesst vier Kerne
# gleichzeitig in den Ring schreiben (PH_LOG) und misst 40000 Zeilen
# geschrieben, 40000 gezaehlt, **0 verschraenkte Eintraege**. Eine
# ungesperrte Datenseite haette dort Kopf und Text verschiedener Kerne
# gemischt.
EK_SOLL=${EK_SOLL:-67}
ek=$(python3 tools/vielkern/onecore.py | sed -n 's/.*offen=\([0-9]*\).*/\1/p')
if [ -n "$ek" ] && [ "$ek" -le "$EK_SOLL" ] 2>/dev/null; then
    ok "Funktionen mit einem Puffer der Datenseite ohne Sperrwort: $ek (Vertrag: hoechstens $EK_SOLL)"
else
    bad "Ein-Kern-Reste: $ek, Vertrag ist hoechstens $EK_SOLL -- neue Stelle? Dann in docs/RUNDE-MERGE6.md eintragen"
fi
python3 tools/vielkern/onecore.py | sed 's/^/        /'

echo
echo "VIELKERN: $pass bestanden, $fail gescheitert"
[ "$fail" -eq 0 ] || exit 1
