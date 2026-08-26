#!/usr/bin/env bash
# tools/k16/run.sh -- RUNDE K16: DER UEBERSETZER LAEUFT AUF DEM SYSTEM
# SELBST, UND EINE DATEI WEISS, WOMIT MAN SIE OEFFNET.
#
# Fuenf Teile, und der vierte ist der, um den es geht:
#
#   1. WAS EIN ASSEMBLER LEISTEN MUSS (auf dem Wirt, ohne QEMU).
#      `kernel/user/fas.fi` liest den Assemblertext, den `firnc`
#      ausgibt, und macht daraus UNMITTELBAR eine ausfuehrbare Datei --
#      ohne `as`, ohne `ld`, ohne Objektformat. Gemessen wird nicht
#      "es laeuft durch", sondern: dasselbe Programm, einmal von
#      `as`+`ld` gebaut und einmal von `fas`, sagt bei denselben
#      Eingaben Oktett fuer Oktett dasselbe und geht mit demselben Code.
#      Und: ALLE Programme dieses Userlands gehen durch.
#      Gegenproben: ein Befehl, den `fas` nicht kennt, eine Quelle ohne
#      `_start` und ein Sprung ins Nichts -- alle drei muessen mit
#      Zeilennummer abbrechen.
#
#   2. DIE ZAHLEN, AUS DENEN DIE KERNAENDERUNGEN FOLGEN. Wie viel
#      Adressraum und wie viel Stapel `firnc1` wirklich braucht,
#      gemessen mit `setrlimit` auf dem Wirt. Ohne diese zwei Zahlen
#      waeren "3 MiB Abbildfenster", "6 MiB Arena" und "504 KiB Stapel"
#      geraten. Gegenprobe: mit weniger geht es nachweislich nicht.
#
#   3. DIE SPEICHERKARTE. `tools/kernel/karte.py` rechnet nach, dass
#      sich der Bereich dieser Runde (0x49000..0x4C000) mit keinem
#      anderen ueberschneidet. Gegenprobe: mit der Adresse von Runde K15
#      MUSS der Pruefer anschlagen.
#
#   4. DER UEBERSETZER AUF OSUM -- DER BEWEIS DIESER RUNDE.
#      `/bin/firnc` liest eine `.fi` von der Platte, uebersetzt sie und
#      schreibt eine `.s` auf die Platte. `/bin/fas` macht daraus ein
#      Programm auf der Platte. Das Programm LAEUFT. Und dann die
#      Steigerung: der WIRT liest beides aus dem Plattenabbild zurueck
#      und haelt es gegen das, was DERSELBE Uebersetzer auf Linux aus
#      DERSELBEN Quelle macht -- Oktett fuer Oktett.
#      Gegenproben: `nostackgrow` (der Stapel waechst nicht -- der
#      Uebersetzer MUSS an einem Seitenfehler sterben), `nobigmem` (die
#      grosse Arena ist aus -- er MUSS an Speichermangel sterben) und
#      eine ANDERE Quelle, die NICHT zeichengleich herauskommen darf.
#
#   5. WOMIT MAN EINE DATEI OEFFNET. Die Tabelle im Kern
#      (`kernel/ftype.fi`) und der Ausleger (`#!`) in `execve`, gemessen
#      aus Ring 3 durch `kernel/user/k16.fi`. Der Fall, der die Regel
#      ueberhaupt zu einer Regel macht: `/tarn.fi` heisst wie
#      Firn-Quelltext und IST ein Programm -- der Inhalt geht vor.
#
# Verwendung:  bash tools/k16/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

FIRNC=${FIRNC:-vendor/firn/bin/firnc}
FC1=${FIRNC1:-vendor/firn/bin/firnc1}
ULD=kernel/user/user.ld

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() { # name value op expected
    local name=$1 value=$2 op=$3 want=$4
    if [ -z "$value" ]; then bad "$name: keine Zahl gefunden (erwartet $op $want)"; return; fi
    if [ "$value" -"$op" "$want" ] 2>/dev/null; then ok "$name: $value"
    else bad "$name: $value, erwartet $op $want"; fi
}
gleich() { # name ist soll
    if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', erwartet '$3'"; fi
}
hat() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hatnicht() { grep -qaF "$2" "$1" && bad "$3 -- '$2' sollte nicht dastehen" || ok "$3"; }
wert() { grep -a -m1 -oE "$2" "$1" 2>/dev/null | head -1; }

bash vendor/firn/hole-firnc.sh >/dev/null || { echo "hole-firnc.sh fehlgeschlagen"; exit 1; }
[ -x "$FIRNC" ] || { echo "firnc0 fehlt"; exit 1; }
[ -x "$FC1" ]   || { echo "firnc1 fehlt"; exit 1; }

# ===================================================================
echo "== 1. der Assembler: aus dem .s von firnc unmittelbar ein Programm =="

as --64 -o "$TMPD/hostcrt.o" tools/k11/hostcrt.s 2>/dev/null \
    || { echo "as auf hostcrt.s fehlgeschlagen"; exit 1; }
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null \
    || { echo "as auf crt.s fehlgeschlagen"; exit 1; }

if "$FIRNC" -c -o "$TMPD/fas.o" kernel/user/fas.fi > "$TMPD/fas.err" 2>&1 \
   && ld -T "$ULD" --defsym=USER_ENTRY=_F0.u_start -o "$TMPD/fas" \
        "$TMPD/hostcrt.o" "$TMPD/fas.o" 2>/dev/null; then
    ok "fas ist gebaut ($(stat -c%s "$TMPD/fas") Oktette)"
else
    bad "fas laesst sich nicht bauen"; sed 's/^/        /' "$TMPD/fas.err" | head -8
fi
FAS="$TMPD/fas"

# ---- 1a. ALLE Programme dieses Userlands gehen durch den Assembler.
#
# `flate`, `tools` und `ulib` sind KEINE Programme dieser Platte: die
# ersten beiden sind Bibliotheksmodule ohne `u_start`, `ulib` hat ein
# `fn main` und damit ein eigenes `_start`. Sie stehen hier als
# Ausnahme, damit die Zahl darunter eine Zahl ueber PROGRAMME ist.
#
# NACHTRAG ZUM MERGE VON K15: dieselbe Ausnahme fuer die fuenf Module,
# die diese Runde mitgebracht hat -- `wlib`/`wlibc` (die Widget-
# Bibliothek), `appdir` (das Anwendungsverzeichnis), `nidx` (der
# Namensindex) und `pw` (die Passwortdatei von K13). Auch sie haben kein
# `u_start`; sie werden EINGEBUNDEN. Wer sie mitzaehlt, misst nicht den
# Assembler, sondern seine eigene Liste.
mkdir -p "$TMPD/s"
PROGS=""
for f in kernel/user/*.fi; do
    n=$(basename "$f" .fi)
    case "$n" in flate|tools|ulib) continue;; esac
    grep -q "fn u_start" "$f" || continue
    PROGS="$PROGS $n"
done
gebaut=0; nichtgebaut=""
for p in $PROGS; do
    if "$FC1" "kernel/user/$p.fi" > "$TMPD/s/$p.s" 2>"$TMPD/s/$p.err"; then
        if "$FAS" "$TMPD/s/$p.s" -o "$TMPD/s/$p.bin" --crt _F1.u_start \
                > "$TMPD/s/$p.fas" 2>&1; then
            gebaut=$((gebaut+1))
        else
            nichtgebaut="$nichtgebaut $p[$(head -1 "$TMPD/s/$p.fas")]"
        fi
    else
        nichtgebaut="$nichtgebaut $p[firnc]"
    fi
done
ANZ=$(echo $PROGS | wc -w)
if [ -z "$nichtgebaut" ]; then
    ok "fas uebersetzt und bindet alle $gebaut Programme dieses Userlands"
else
    bad "fas scheitert an:$nichtgebaut"
fi
num "Programme, die fas gebunden hat" "$gebaut" eq "$ANZ"

# ---- 1b. DIE EIGENTLICHE MESSUNG: gleiches Verhalten wie as+ld.
printf 'b\na\nb\nc\na\n' > "$TMPD/in.txt"
VERGLEICH="echo wc sort head tail uniq grep cat seq tr cut basename dirname which true false"
same=0; diffs=""
for p in $VERGLEICH; do
    as --64 -o "$TMPD/s/$p.o" "$TMPD/s/$p.s" 2>/dev/null || { diffs="$diffs $p(as)"; continue; }
    ld -T "$ULD" --defsym=USER_ENTRY=_F1.u_start -o "$TMPD/s/$p.ld" \
        "$TMPD/hostcrt.o" "$TMPD/s/$p.o" 2>/dev/null || { diffs="$diffs $p(ld)"; continue; }
    "$FAS" "$TMPD/s/$p.s" -o "$TMPD/s/$p.fas" --wirt --crt _F1.u_start 2>/dev/null
    chmod +x "$TMPD/s/$p.fas" "$TMPD/s/$p.ld"
    case $p in
      echo) A="hallo welt 42";; wc|sort|uniq|cat) A="$TMPD/in.txt";;
      head|tail) A="-n 2 $TMPD/in.txt";; grep) A="a $TMPD/in.txt";;
      seq) A="1 7";; tr) A="a X";; cut) A="-c 1 $TMPD/in.txt";;
      basename|dirname) A="/x/y/z.txt";; which) A="ls";; *) A="";;
    esac
    o1=$("$TMPD/s/$p.ld" $A < "$TMPD/in.txt" 2>&1; echo "rc=$?")
    o2=$("$TMPD/s/$p.fas" $A < "$TMPD/in.txt" 2>&1; echo "rc=$?")
    if [ "$o1" = "$o2" ]; then same=$((same+1)); else diffs="$diffs $p"; fi
done
ANZV=$(echo $VERGLEICH | wc -w)
if [ -z "$diffs" ]; then
    ok "$same von $ANZV Programmen: fas und as+ld sagen dasselbe und gehen mit demselben Code"
else
    bad "fas und as+ld unterscheiden sich bei:$diffs"
fi

# ---- 1c. GEGENPROBEN. Ein Assembler, der nie nein sagt, misst nichts.
printf '.intel_syntax noprefix\n.text\n.globl _start\n_start:\n    mov rax, rbx\n    quatschbefehl rax, rbx\n    ret\n' > "$TMPD/kaputt.s"
if "$FAS" "$TMPD/kaputt.s" -o "$TMPD/kaputt.bin" --wirt > "$TMPD/kaputt.err" 2>&1; then
    bad "GEGENPROBE: fas hat einen unbekannten Befehl durchgelassen"
else
    if grep -q "Zeile 6" "$TMPD/kaputt.err" && grep -q "quatschbefehl" "$TMPD/kaputt.err"; then
        ok "GEGENPROBE: ein unbekannter Befehl bricht ab -- mit Zeilennummer und Wort"
    else
        bad "GEGENPROBE: der Abbruch nennt nicht Zeile 6 und das Wort: $(head -1 "$TMPD/kaputt.err")"
    fi
fi
printf '.intel_syntax noprefix\n.text\nfoo:\n    ret\n' > "$TMPD/ohne.s"
if "$FAS" "$TMPD/ohne.s" -o "$TMPD/ohne.bin" --wirt > "$TMPD/ohne.err" 2>&1; then
    bad "GEGENPROBE: fas hat eine Quelle ohne _start gebunden"
else
    hat "$TMPD/ohne.err" "_start" "GEGENPROBE: ohne die Marke _start bricht fas ab"
fi
printf '.intel_syntax noprefix\n.text\n.globl _start\n_start:\n    jmp nirgendwo\n' > "$TMPD/weg.s"
if "$FAS" "$TMPD/weg.s" -o "$TMPD/weg.bin" --wirt > "$TMPD/weg.err" 2>&1; then
    bad "GEGENPROBE: fas hat einen Sprung ins Nichts gebunden"
else
    hat "$TMPD/weg.err" "nirgendwo" "GEGENPROBE: ein Sprung auf einen unbekannten Namen bricht ab"
fi
printf '.intel_syntax noprefix\n.text\n.globl _start\n_start:\n    mov edi, 5\n    mov eax, 60\n    syscall\n' > "$TMPD/gut.s"
if "$FAS" "$TMPD/gut.s" -o "$TMPD/gut.bin" --wirt >/dev/null 2>&1; then
    chmod +x "$TMPD/gut.bin"; "$TMPD/gut.bin"; rc=$?
    num "und dieselbe Quelle ohne den Fehler laeuft und gibt 5 zurueck" "$rc" eq 5
else
    bad "die fehlerfreie Gegenprobe liess sich nicht bauen"
fi

# ===================================================================
echo "== 2. die Zahlen, aus denen die Kernaenderungen folgen =="
mkdir -p "$TMPD/mess"
printf 'fn main(start: u64) -> i32 {\n    return 0\n}\n' > "$TMPD/mess/klein.fi"
python3 - "$ROOT/$FC1" "$TMPD/mess/klein.fi" > "$TMPD/mess.txt" 2>&1 <<'PY'
import resource, subprocess, sys
fc1, quelle = sys.argv[1], sys.argv[2]
def geht(art, wert):
    def pre():
        resource.setrlimit(art, (wert, wert))
    try:
        return subprocess.run([fc1, quelle], stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL,
                              preexec_fn=pre).returncode == 0
    except Exception:
        return False
def kleinste(art, lo, hi, einheit):
    while lo < hi:
        m = (lo + hi) // 2
        if geht(art, m * einheit): hi = m
        else: lo = m + 1
    return lo
ar = kleinste(resource.RLIMIT_AS, 1, 512, 1024 * 1024)
st = kleinste(resource.RLIMIT_STACK, 8, 2048, 1024)
print("adressraum_mib", ar)
print("stapel_kib", st)
print("weniger_adressraum", 1 if geht(resource.RLIMIT_AS, (ar - 1) * 1024 * 1024) else 0)
print("weniger_stapel", 1 if geht(resource.RLIMIT_STACK, (st - 8) * 1024) else 0)
PY
AR=$(wert "$TMPD/mess.txt" 'adressraum_mib [0-9]+' | grep -oE '[0-9]+')
ST=$(wert "$TMPD/mess.txt" 'stapel_kib [0-9]+' | grep -oE '[0-9]+')
num "firnc1 braucht so viel Adressraum (MiB) -- Osum gibt 3 MiB Abbild und 6 MiB Arena" "${AR:-}" le 9
num "firnc1 braucht so viel Stapel (KiB) -- Osum gibt jetzt 504" "${ST:-}" le 504
gleich "GEGENPROBE: mit einem MiB weniger Adressraum geht es nicht" \
    "$(wert "$TMPD/mess.txt" 'weniger_adressraum [0-9]+' | grep -oE '[0-9]+$')" "0"
gleich "GEGENPROBE: mit acht KiB weniger Stapel geht es nicht" \
    "$(wert "$TMPD/mess.txt" 'weniger_stapel [0-9]+' | grep -oE '[0-9]+$')" "0"

# ===================================================================
echo "== 3. die Speicherkarte: der Bereich dieser Runde ueberschneidet keinen =="
if python3 tools/kernel/karte.py kernel > "$TMPD/karte.txt" 2>&1; then
    ok "$(tail -1 "$TMPD/karte.txt")"
else
    bad "die Speicherkarte hat Kollisionen"; sed 's/^/        /' "$TMPD/karte.txt" | head -5
fi
grep -q 'K16_OFF' tools/kernel/karte.py \
    && ok "der Bereich K16 steht in tools/kernel/karte.py und wird mitgerechnet" \
    || bad "K16 fehlt in tools/kernel/karte.py"
mkdir -p "$TMPD/kern"
cp kernel/*.fi "$TMPD/kern/"
# Die Gegenprobe legt K16 auf die Seite des Schriftlesers aus Runde K10
# (TTF_OFF = 0x3F000). Sie ist BELEGT, also MUSS der Pruefer anschlagen
# -- ein Pruefer, der nie anschlaegt, rechnet nichts nach. (Nicht auf
# 0x46000: der Bereich von Runde K15 steht noch in ihrem eigenen Zweig
# und waere hier eine leere Seite.)
sed -i 's/^const K16_OFF: u64 = 0x49000$/const K16_OFF: u64 = 0x3F000/' "$TMPD/kern/kstate.fi"
if python3 tools/kernel/karte.py "$TMPD/kern" > "$TMPD/karte2.txt" 2>&1; then
    bad "GEGENPROBE: auf 0x3F000 (Runde K10, der Schriftleser) haette der Pruefer anschlagen muessen"
else
    ok "GEGENPROBE: auf einer schon belegten Seite schlaegt der Kartenpruefer an ($(grep -c KOLLISION "$TMPD/karte2.txt") Kollisionen)"
fi

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo
    echo "K16: $pass passed, $fail failed  (ohne QEMU -- Teil 4 und 5 uebersprungen)"
    [ "$fail" -eq 0 ] && exit 0 || exit 1
fi

# ===================================================================
echo "== 4. der Uebersetzer auf Osum =="

bash tools/build-kernel.sh "$TMPD/k.mb" >/dev/null 2>&1 \
    || { bad "der Kernel laesst sich nicht bauen"; echo "K16: $pass passed, $fail failed"; exit 1; }

# DIE PROGRAMME FUER OSUM LIEGEN IN EINEM EIGENEN VERZEICHNIS, und das ist
# kein Ordnungssinn: `$FAS` ist der Assembler FUER DEN WIRT, gebunden mit
# tools/k11/hostcrt.s. Ein `fas` fuer Osum an derselben Stelle waere ein
# Programm, das auf 0x40100000 liegt und seine Argumente aus rdi liest --
# auf dem Wirt gestartet gaebe es die Gebrauchsanweisung aus, und der
# Vergleich weiter unten haette nichts zu vergleichen. Genau so ist es
# beim Bau dieser Runde passiert.
mkdir -p "$TMPD/o"
bau_osum() { # name
    "$FIRNC" -c -o "$TMPD/o/$1.o" "kernel/user/$1.fi" > "$TMPD/o/$1.err" 2>&1 || return 1
    ld -T "$ULD" --defsym=USER_ENTRY=_F0.u_start -o "$TMPD/o/$1" \
        "$TMPD/crt.o" "$TMPD/o/$1.o" 2>/dev/null || return 1
    strip --strip-all "$TMPD/o/$1"
}
for p in sh cat echo hello fas firun k16; do
    bau_osum "$p" || { bad "$p laesst sich nicht fuer Osum bauen"; sed 's/^/        /' "$TMPD/o/$p.err" | head -5; }
done

# `firnc` FUER OSUM: dasselbe `bin/firnc1.fi` wie auf dem Wirt, nur gegen
# `kernel/user/user.ld` gebunden -- Abbild ab 0x40100000 statt 0x400000.
# Kein crt.s: `firnc1.fi` hat ein `fn main`, und dafuer erzeugt firnc
# sein `_start` selbst (genau deshalb musste der Kern den Argumentblock
# auf den Stapelzeiger legen, siehe kernel/elf.fi).
FIRNQ=""
for k in "${FIRN_REPO:-}" "$ROOT/../firn" "$ROOT/../../firn" "$ROOT/../../../firn"; do
    [ -n "$k" ] && [ -f "$k/bin/firnc1.fi" ] && FIRNQ=$(cd "$k" && pwd) && break
done
if [ -z "$FIRNQ" ]; then
    bad "die Quelle des Uebersetzers (bin/firnc1.fi) wurde nicht gefunden"
else
    if ( cd "$FIRNQ" && FIRNLIB="$FIRNQ/lib" "$ROOT/$FIRNC" -c -o "$TMPD/o/firnc.o" bin/firnc1.fi ) > "$TMPD/firnc.err" 2>&1 \
       && ld -T "$ULD" -o "$TMPD/o/firnc" "$TMPD/o/firnc.o" 2>/dev/null; then
        strip --strip-all "$TMPD/o/firnc"
        ok "firnc ist fuer Osum gebunden ($(stat -c%s "$TMPD/o/firnc") Oktette, Abbild ab 0x40100000)"
    else
        bad "firnc laesst sich nicht fuer Osum binden"; sed 's/^/        /' "$TMPD/firnc.err" | head -5
    fi
fi

# DIE QUELLE, DIE OSUM UEBERSETZEN SOLL. Sie steht hier im Skript und
# nicht in einer Datei des Repos, damit ihr Inhalt UND IHR NAME auf
# beiden Seiten dieselben sind -- der Pfad steht in den Panikmeldungen,
# die firnc nach `.rodata` legt, und ein anderer Pfad ist ein anderes
# Programm. Genau daran ist der erste Vergleich dieser Runde gescheitert
# (docs/ROUNDK16.md).
mkdir -p "$TMPD/q"
cat > "$TMPD/q/probe.fi" <<'FI'
fn schreib(fd: u64, p: u64, n: u64) -> u64 {
    return asm("syscall", out("rax"), in("rax") 1, in("rdi") fd,
        in("rsi") p, in("rdx") n, clobber("rcx"), clobber("r11"),
        clobber("memory"))
}

fn main(start: u64) -> i32 {
    var s: [u8; 30] = "osum hat mich uebersetzt\n\0\0\0\0\0"
    schreib(1, (&s[0]) as u64, 25)
    return 42
}
FI
cat > "$TMPD/q/kaputt.fi" <<'FI'
fn main(start: u64) -> i32 {
    return diesenamengibtesnicht
}
FI
printf 'fn main(start: u64) -> i32 {\n    return 1\n}\n' > "$TMPD/q/andere.fi"

lauf() { # abbild anhang ausgabe [zeitlimit]
    local img=$1 anh=$2 out=$3 tl=${4:-900}
    cp "$img" "$TMPD/live.img"
    timeout "$tl" qemu-system-x86_64 -kernel "$TMPD/k.mb" -m 512 \
        -append "$anh" -serial "file:$out" -display none -no-reboot \
        -drive "file=$TMPD/live.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    return $?
}

if [ -x "$TMPD/o/firnc" ]; then
python3 tools/osum/mkfs.py build "$TMPD/d.img" 4096 /bin/ \
    /bin/sh="$TMPD/o/sh" /bin/echo="$TMPD/o/echo" /bin/fas="$TMPD/o/fas" \
    /bin/firun="$TMPD/o/firun" /bin/k16="$TMPD/o/k16" \
    /bin/firnc="$TMPD/o/firnc" \
    /probe.fi="$TMPD/q/probe.fi" /kaputt.fi="$TMPD/q/kaputt.fi" \
    > "$TMPD/mkfs.txt" 2>&1 \
    && ok "ein Plattenabbild mit dem Uebersetzer darauf ($(grep -o 'free=[0-9]*' "$TMPD/mkfs.txt") Bloecke)" \
    || { bad "mkfs fuer das Uebersetzerabbild fehlgeschlagen"; head -3 "$TMPD/mkfs.txt"; }
fi

if [ -f "$TMPD/d.img" ]; then
S='cd /;firnc probe.fi > /probe.s;echo UEB=$?;fas /probe.s -o /probe;echo BIN=$?;/probe;echo LAUF=$?;exit'
lauf "$TMPD/d.img" "osum nokbd nosched noproc nofs noring3 script=$S" "$TMPD/ueb.txt"
rc=$?
num "QEMU-Beendigungscode des Uebersetzerlaufs" "$rc" eq 21
cp "$TMPD/live.img" "$TMPD/nach-ueb.img"
gleich "der Uebersetzer auf Osum ist zufrieden zurueckgekommen" \
    "$(wert "$TMPD/ueb.txt" 'UEB=[0-9]+')" "UEB=0"
gleich "der Assembler auf Osum ist zufrieden zurueckgekommen" \
    "$(wert "$TMPD/ueb.txt" 'BIN=[0-9]+')" "BIN=0"
hat "$TMPD/ueb.txt" "osum hat mich uebersetzt" \
    "DAS AUF OSUM UEBERSETZTE PROGRAMM LAEUFT AUF OSUM UND SAGT SEINEN SATZ"
gleich "und es geht mit genau dem Code, den seine Quelle nennt" \
    "$(wert "$TMPD/ueb.txt" 'LAUF=[0-9]+')" "LAUF=42"

python3 tools/osum/mkfs.py cat "$TMPD/nach-ueb.img" /probe.s > "$TMPD/osum.s" 2>/dev/null
python3 tools/osum/mkfs.py cat "$TMPD/nach-ueb.img" /probe > "$TMPD/osum.bin" 2>/dev/null
( cd "$TMPD/q" && "$ROOT/$FC1" probe.fi > "$TMPD/wirt.s" 2>/dev/null )
"$FAS" "$TMPD/wirt.s" -o "$TMPD/wirt.bin" > "$TMPD/wirt.fas" 2>&1 \
    || { bad "fas kam auf dem Wirt nicht durch: $(head -1 "$TMPD/wirt.fas")"; }
num "die .s von Osum ist nicht leer (Oktette)" "$(stat -c%s "$TMPD/osum.s" 2>/dev/null || echo 0)" gt 1000
if cmp -s "$TMPD/osum.s" "$TMPD/wirt.s"; then
    ok "ZEICHENGLEICH: der Assemblertext von Osum ist Oktett fuer Oktett der vom Wirt ($(stat -c%s "$TMPD/osum.s") Oktette)"
else
    bad "der Assemblertext unterscheidet sich: $(cmp "$TMPD/osum.s" "$TMPD/wirt.s" 2>&1 | head -1)"
    diff "$TMPD/osum.s" "$TMPD/wirt.s" 2>/dev/null | head -6 | sed 's/^/        /'
fi
if cmp -s "$TMPD/osum.bin" "$TMPD/wirt.bin"; then
    ok "ZEICHENGLEICH: die ausfuehrbare Datei von Osum ist Oktett fuer Oktett die vom Wirt ($(stat -c%s "$TMPD/osum.bin") Oktette)"
else
    bad "die ausfuehrbare Datei unterscheidet sich: Osum $(stat -c%s "$TMPD/osum.bin" 2>/dev/null || echo -) Oktette, Wirt $(stat -c%s "$TMPD/wirt.bin" 2>/dev/null || echo -) Oktette, $(cmp -l "$TMPD/osum.bin" "$TMPD/wirt.bin" 2>/dev/null | wc -l) verschieden"
    head -c 120 "$TMPD/osum.bin" | od -An -tx1 | head -2 | sed 's/^/        osum /'
    head -c 120 "$TMPD/wirt.bin" | od -An -tx1 | head -2 | sed 's/^/        wirt /'
    head -2 "$TMPD/wirt.fas" | sed 's/^/        /' 
fi
( cd "$TMPD/q" && "$ROOT/$FC1" andere.fi > "$TMPD/andere.s" 2>/dev/null )
if cmp -s "$TMPD/osum.s" "$TMPD/andere.s"; then
    bad "GEGENPROBE: eine andere Quelle kam zeichengleich heraus -- der Vergleich misst nichts"
else
    ok "GEGENPROBE: eine ANDERE Quelle kommt NICHT zeichengleich heraus"
fi

GROW=$(wert "$TMPD/ueb.txt" 'stackgrow=[0-9]+' | grep -oE '[0-9]+')
num "Stapelseiten, die waehrend des Laufs bei Bedarf entstanden sind" "${GROW:-0}" gt 10

lauf "$TMPD/d.img" "osum nokbd nosched noproc nofs noring3 nostackgrow script=$S" \
     "$TMPD/nostack.txt"
if [ "$(wert "$TMPD/nostack.txt" 'UEB=[0-9]+')" = "UEB=0" ]; then
    bad "GEGENPROBE nostackgrow: der Uebersetzer lief trotzdem durch -- das Wachsen beweist nichts"
else
    ok "GEGENPROBE nostackgrow: der Uebersetzer kommt NICHT durch ($(wert "$TMPD/nostack.txt" 'UEB=[0-9]+'))"
fi
hat "$TMPD/nostack.txt" "user fault:" \
    "GEGENPROBE nostackgrow: er stirbt an einem Seitenfehler"
hatnicht "$TMPD/nostack.txt" "osum hat mich uebersetzt" \
    "GEGENPROBE nostackgrow: und nichts wird uebersetzt"
gleich "GEGENPROBE nostackgrow: kein einziges Stapelfach ist entstanden" \
    "$(wert "$TMPD/nostack.txt" 'stackgrow=[0-9]+')" "stackgrow=0"

lauf "$TMPD/d.img" "osum nokbd nosched noproc nofs noring3 nobigmem script=$S" \
     "$TMPD/nobig.txt"
if [ "$(wert "$TMPD/nobig.txt" 'UEB=[0-9]+')" = "UEB=0" ]; then
    bad "GEGENPROBE nobigmem: der Uebersetzer lief trotzdem durch -- die Arena beweist nichts"
else
    ok "GEGENPROBE nobigmem: ohne die grosse Arena kommt der Uebersetzer nicht durch ($(wert "$TMPD/nobig.txt" 'UEB=[0-9]+'))"
fi
hatnicht "$TMPD/nobig.txt" "osum hat mich uebersetzt" \
    "GEGENPROBE nobigmem: und nichts wird uebersetzt"

S2='cd /;k16 open /probe.fi;k16 open /kaputt.fi;exit'
lauf "$TMPD/d.img" "osum nokbd nosched noproc nofs noring3 script=$S2" "$TMPD/open.txt"
hat "$TMPD/open.txt" "osum hat mich uebersetzt" \
    "DER DOPPELKLICK: fopen auf eine .fi uebersetzt sie und startet sie"
G=$(grep -a -c 'k16: fopen_c = 42' "$TMPD/open.txt" 2>/dev/null || true)
num "und der Beendigungscode des uebersetzten Programms kommt durch (42)" "${G:-0}" ge 1
K=$(grep -a -c 'k16: fopen_c = 70' "$TMPD/open.txt" 2>/dev/null || true)
num "GEGENPROBE: eine .fi, die NICHT uebersetzt, endet mit 70 statt mit 0" "${K:-0}" ge 1
# WAS DER NUTZER WIRKLICH LIEST -- und was er NICHT liest.
# `firnc1` schreibt bei einem Fehler keine Zeile: nicht auf Deskriptor 1,
# nicht auf Deskriptor 2, gemessen am 26.08.2026. Es gibt einen Code
# zurueck und sonst nichts. `firun` uebersetzt diesen Code in einen Satz,
# und DAS ist es, was ein Mensch nach einem Doppelklick zu sehen bekommt.
# Die Grenze steht so in docs/ROUNDK16.md: WELCHER ART der Fehler ist,
# steht da -- WO er steht, nicht.
hat "$TMPD/open.txt" "firun: der Uebersetzer lehnt ab, Code 1" \
    "GEGENPROBE: und der Nutzer LIEST, warum -- der Grund steht auf dem Schirm"
hat "$TMPD/open.txt" "im Quelltext steht ein Fehler" \
    "GEGENPROBE: und zwar als Satz und nicht als nackte Zahl"
fi

# ===================================================================
echo "== 5. womit man eine Datei oeffnet: die Tabelle und der Ausleger =="

mkdir -p "$TMPD/d"
printf 'fn main(start: u64) -> i32 {\n    return 0\n}\n' > "$TMPD/d/p.fi"
printf 'ein text\n' > "$TMPD/d/q.txt"
cp "$TMPD/o/hello" "$TMPD/d/tarn.fi"          # heisst .fi, IST ein ELF
printf 'weder magisch noch bekannt\n' > "$TMPD/d/fremd.zzz"
printf '#!/bin/echo ausleger\nrest egal\n' > "$TMPD/d/s1.sh"
printf '#!/r2.sh\n' > "$TMPD/d/r1.sh"
printf '#!/r1.sh\n' > "$TMPD/d/r2.sh"

python3 tools/osum/mkfs.py build "$TMPD/t.img" 4096 /bin/ \
    /bin/sh="$TMPD/o/sh" /bin/cat="$TMPD/o/cat" /bin/echo="$TMPD/o/echo" \
    /bin/hello="$TMPD/o/hello" /bin/k16="$TMPD/o/k16" \
    /p.fi="$TMPD/d/p.fi" /q.txt="$TMPD/d/q.txt" /tarn.fi="$TMPD/d/tarn.fi" \
    /fremd.zzz="$TMPD/d/fremd.zzz" /s1.sh="$TMPD/d/s1.sh" \
    /r1.sh="$TMPD/d/r1.sh" /r2.sh="$TMPD/d/r2.sh" \
    > "$TMPD/mkfs2.txt" 2>&1 \
    && ok "ein Plattenabbild mit den sieben Faellen darauf" \
    || { bad "mkfs fuer den Tabellenlauf fehlgeschlagen"; head -3 "$TMPD/mkfs2.txt"; }

lauf "$TMPD/t.img" "osum nokbd nosched noproc nofs noring3 script=k16;exit" \
     "$TMPD/tab.txt" 300
rc=$?
num "QEMU-Beendigungscode des Tabellenlaufs" "$rc" eq 21
hat "$TMPD/tab.txt" "k16: fertig" "das Programm in Ring 3 ist durchgelaufen"

k16w() { grep -a -m1 -oE "k16: $1 = .*" "$TMPD/tab.txt" 2>/dev/null | sed "s/k16: $1 = //"; }
K() { gleich "$3" "$(k16w "$1")" "$2"; }

K art_elf_l   "elf"  "eine ELF-Datei wird an ihrer magischen Zahl erkannt"
K art_elf_a   "1"    "und ihre Wirkung ist: sie SELBST starten (A_EXEC)"
K art_elf_m   "4"    "die magische Zahl ist vier Oktette lang"
K art_fi_l    "firn" "eine .fi wird an ihrer Endung erkannt"
K art_fi_p    "/bin/firun" "und geoeffnet wird sie mit /bin/firun"
K art_fi_e    ".fi"  "die Endung im Satz ist .fi"
K art_txt_p   "/bin/edit" "eine .txt wird mit dem Editor geoeffnet"
K art_tarn_l  "elf"  "DER INHALT GEHT VOR: /tarn.fi heisst .fi und IST ein Programm"
K art_fremd   "-8"   "GEGENPROBE: weder magische Zahl noch bekannte Endung: -ENOEXEC"
K art_weg     "-2"   "GEGENPROBE: eine Datei, die es nicht gibt: -ENOENT"
num "Eintraege in der Tabelle" "$(k16w tab_anz)" ge 8
K tab_end     "-2"   "GEGENPROBE: hinter dem letzten Eintrag: -ENOENT"
num "freg hat einen Platz vergeben" "$(k16w reg_nr)" ge 0
if [ "$(k16w reg_danach)" = "-8" ]; then
    bad "nach freg wird /fremd.zzz immer noch nicht eingeordnet -- die Tabelle wirkt nicht"
else
    ok "nach freg wird /fremd.zzz eingeordnet (Platz $(k16w reg_danach)) -- die Tabelle wirkt wirklich"
fi
K reg_prog    "/bin/cat" "und zwar mit dem Programm, das Ring 3 eingetragen hat"
K reg_kurz    "-22"  "GEGENPROBE: ein Satz der falschen Laenge wird abgelehnt (-EINVAL)"
num "fopen auf ein Programm gibt eine Prozessnummer" "$(k16w open_elf)" gt 0
K open_fremd  "-2"   "GEGENPROBE: fopen auf einen Pfad, den es nicht gibt, startet NICHTS"
num "ein Skript mit #! startet ueber seinen Ausleger" "$(k16w shebang)" gt 0
hat "$TMPD/tab.txt" "ausleger /s1.sh" \
    "DER AUSLEGER BEKOMMT SEIN ARGUMENT UND DEN PFAD: 'ausleger /s1.sh'"
K shebang_ring "-40" "GEGENPROBE: ein #! im Kreis endet mit -ELOOP und startet nichts"
K kein_programm "-8" "GEGENPROBE: eine Datei ohne #! und ohne ELF-Kopf bleibt kein Programm"
SB=$(wert "$TMPD/tab.txt" 'shebangs=[0-9]+' | grep -oE '[0-9]+')
num "wie oft execve einen Ausleger gefunden hat" "${SB:-0}" ge 1

echo
echo "K16: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && exit 0 || exit 1
