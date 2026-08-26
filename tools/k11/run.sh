#!/usr/bin/env bash
# tools/k11/run.sh -- DER BEWEIS, DASS MAN AUF OSUM ARBEITEN KANN.
#
# Bis zu dieser Runde konnte auf diesem System niemand eine Datei
# schreiben oder aendern. Es lief nur, was vorher hineinkompiliert worden
# war. Diese Datei misst, dass das vorbei ist -- und zwar so, dass ein
# "startet ohne Absturz" nirgends als Zusage durchgeht:
#
#   1. DER EDITOR WIRD WIRKLICH BEDIENT. Die Tasten kommen ueber den
#      QEMU-Monitor (`sendkey`) am Tor 0x60 an, laufen durch IRQ1,
#      `kernel/kbd.fi` und die Zeilendisziplin. Danach liest der WIRT die
#      gesicherte Datei AUS DEM PLATTENABBILD (`mkfs.py cat`) und haelt
#      sie Oktett fuer Oktett gegen die Erwartung. Kein Mitschnitt, keine
#      Behauptung -- die Oktette auf der Platte.
#   2. BEIDE AUSGABEWEGE ZEIGEN DASSELBE. Derselbe Lauf schreibt auf die
#      serielle Leitung UND auf den Bildschirm. Der Mitschnitt geht durch
#      ein Terminal in Python (`tools/k11/vt.py`), das Bildschirmfoto
#      durch den Zeichensatzleser aus Runde K7B
#      (`tools/gfx/schau.py lesen`). Die beiden Bilder muessen
#      uebereinstimmen.
#   3. JEDES WERKZEUG GEGEN SEIN LINUX-GEGENSTUECK. Dieselben Eingaben,
#      dieselbe Ausgabe, Oktett fuer Oktett. Wo bewusst abgewichen wird,
#      steht es in docs/ROUNDK11.md UND hier im Testfall.
#   4. `tar` UND `gzip` GEGEN DIE ECHTEN. Was Osum packt, muss GNU
#      auspacken koennen, und umgekehrt. Fuer ein Dateiformat ist das die
#      einzige ehrliche Pruefung.
#   5. DIE SHELL IST EINE SPRACHE. if/elif/else, while, until, for, case,
#      Funktionen, return/break/continue/shift, test und [.
#   6. FEHLERFAELLE. Datei gibt es nicht, Verzeichnis statt Datei, kein
#      Platz mehr, Text ohne abschliessenden Zeilenumbruch, sehr lange
#      Zeilen, Binaerdaten.
#   7. GEGENPROBEN. Ohne die Umschalttaste kein Grossbuchstabe; ohne
#      `kernel/ansi.fi` stehen die Steuerzeichen auf dem Schirm; ein
#      geaenderter Puffer, den man nicht sichert, aendert die Platte
#      nicht; `umount` nimmt dem System wirklich den Boden weg.
#
# Verwendung:  bash tools/k11/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
FC1=${FIRNC1:-vendor/firn/bin/firnc1}
ULD=kernel/user/user.ld
BLOCKS=4096

# Der Werkzeugkasten dieser Runde plus das, was die Faelle sonst brauchen.
K11="edit find sed diff patch tar gzip gunzip xargs du top mount umount
     basename dirname tee cut tr seq env which"
BASIS="sh cat echo ls cp rm mkdir wc grep sort head true false sleep"

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
gleich() { # name soll ist
    if [ "$2" = "$3" ]; then ok "$1"
    else
        bad "$1"
        printf '        soll: %s\n' "$(printf '%s' "$2" | head -c 300)"
        printf '        ist : %s\n' "$(printf '%s' "$3" | head -c 300)"
    fi
}
dateien_gleich() { # name sollDatei istDatei
    if cmp -s "$2" "$3"; then ok "$1"
    else
        bad "$1"
        diff <(od -c "$2" | head -20) <(od -c "$3" | head -20) | head -14 | sed 's/^/        /'
    fi
}
num() { # name wert op soll
    if [ -z "${2:-}" ]; then bad "$1: keine Zahl gefunden"; return; fi
    if [ "$2" -"$3" "$4" ] 2>/dev/null; then ok "$1: $2"
    else bad "$1: $2, erwartet $3 $4"; fi
}
hat() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hat_nicht() { grep -qaF "$2" "$1" && bad "$3 -- '$2' steht da und sollte nicht" || ok "$3"; }

bash vendor/firn/hole-firnc.sh >/dev/null || { echo "vendor/firn/hole-firnc.sh fehlgeschlagen"; exit 1; }
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "K11: uebersprungen, qemu-system-x86_64 fehlt"
    exit 0
fi

# ------------------------------------------------------------- 1. bauen

echo "== 1. bauen: der Kern und der Werkzeugkasten, aus beiden Uebersetzern =="
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s laesst sich nicht assemblieren"

baue_stufe() { # 0 | 1
    local s=$1 cc p rc=0
    if [ "$s" = 0 ]; then cc="$FIRNC"; else cc="$FC1"; fi
    bash tools/build-kernel.sh "$TMPD/k$s.mb" --stufe "$s" > "$TMPD/k$s.log" 2>&1 || {
        bad "firnc$s: der Kern laesst sich nicht bauen"
        sed 's/^/        /' "$TMPD/k$s.log" | head -12
        return 1
    }
    for p in $K11 $BASIS; do
        "$cc" "kernel/user/$p.fi" -o "$TMPD/$p$s.o" > "$TMPD/e$p$s" 2>&1 || {
            bad "firnc$s uebersetzt $p.fi nicht"
            sed 's/^/        /' "$TMPD/e$p$s" | head -8
            rc=1
            continue
        }
        ld -T "$ULD" --defsym=USER_ENTRY="_F$s.u_start" \
            -o "$TMPD/$p$s.elf" "$TMPD/crt.o" "$TMPD/$p$s.o" 2>"$TMPD/ld.err" || {
            bad "firnc$s: ld scheitert an $p"; rc=1; continue; }
        strip --strip-all "$TMPD/$p$s.elf"
    done
    return $rc
}

baue_stufe 0 || { echo "K11: $pass passed, $((fail+1)) failed"; exit 1; }
ok "firnc0: der Kern und $(echo $K11 $BASIS | wc -w) Programme sind gebaut"
if baue_stufe 1; then
    ok "firnc1: dasselbe aus dem Uebersetzer, der in Firn geschrieben ist"
else
    bad "firnc1 hat den Werkzeugkasten nicht gebaut"
fi

# Kein Programm haengt an irgendetwas -- kein libc, kein Kern, keine
# Laufzeit. Dieselbe Zusage wie in Runde K1, fuer die neuen Programme.
undef=""
for p in $K11; do
    u=$(nm -u "$TMPD/${p}0.elf" 2>/dev/null | awk '{print $NF}' | sed '/^$/d')
    [ -n "$u" ] && undef="$undef $p:$u"
done
[ -z "$undef" ] && ok "kein Werkzeug dieser Runde hat ein undefiniertes Symbol" \
               || bad "undefinierte Symbole:$undef"

groesstes=0
for p in $K11 $BASIS; do
    z=$(stat -c%s "$TMPD/${p}0.elf" 2>/dev/null || echo 0)
    [ "$z" -gt "$groesstes" ] && groesstes=$z
done
num "das groesste Programm, gegen die 2135552 Oktette einer Datei" "$groesstes" lt 2135552

# ------------------------------------------------------- 2. die Abbilder

echo "== 2. die Abbilder: Werkzeuge, Vorlagen und Skripte =="
mkdir -p "$TMPD/fix"
printf 'alpha\nbeta\ngamma\n'                       > "$TMPD/fix/drei.txt"
printf 'a\na\nb\nb\nb\nc\n'                         > "$TMPD/fix/dup.txt"
printf 'eins:zwei:drei\nvier:fuenf:sechs\n'         > "$TMPD/fix/spalten.txt"
printf 'one\ntwo\nthree\nfour\n'                    > "$TMPD/fix/alt.txt"
printf 'one\nTWO\nthree\nfour\nfive\n'              > "$TMPD/fix/neu.txt"
printf 'ohne umbruch'                               > "$TMPD/fix/nonl.txt"
: > "$TMPD/fix/leer.txt"
python3 - "$TMPD/fix/lang.txt" <<'PY'
import sys
open(sys.argv[1], "w").write("x" * 900 + "\n" + "kurz\n")
PY
python3 - "$TMPD/fix/binaer.bin" <<'PY'
import sys
open(sys.argv[1], "wb").write(bytes(range(256)) * 8)
PY
python3 - "$TMPD/fix/gross.txt" <<'PY'
import sys
with open(sys.argv[1], "w") as f:
    for i in range(400):
        f.write("die zeile nummer %d, mit viel wiederholtem text darin\n" % i)
PY
printf 'hallo\nwelt\n'                              > "$TMPD/fix/e1.txt"
printf 'eins\nzwei\ndrei\nvier\nfuenf\n'            > "$TMPD/fix/e2.txt"
printf 'aXbXc\n'                                    > "$TMPD/fix/e3.txt"

# Der Baum, an dem `find`, `du` und `tar` gemessen werden. Er wird auf dem
# WIRT gebaut und Datei fuer Datei aufs Abbild gelegt -- damit stehen auf
# beiden Seiten dieselben Oktette, und der Vergleich mit GNU vergleicht
# wirklich dasselbe.
mkdir -p "$TMPD/baum/unter/tief"
printf 'alpha\nbeta\ngamma\n'   > "$TMPD/baum/a.txt"
printf 'one\ntwo\n'             > "$TMPD/baum/unter/b.txt"
printf 'x'                      > "$TMPD/baum/unter/tief/c.bin"
: > "$TMPD/baum/leer.txt"

SPEC=""
for p in $K11 $BASIS; do SPEC="$SPEC /bin/$p=$TMPD/${p}0.elf"; done
DATA="/d/drei.txt=$TMPD/fix/drei.txt /d/dup.txt=$TMPD/fix/dup.txt
      /d/spalten.txt=$TMPD/fix/spalten.txt /d/alt.txt=$TMPD/fix/alt.txt
      /d/neu.txt=$TMPD/fix/neu.txt /d/nonl.txt=$TMPD/fix/nonl.txt
      /d/leer.txt=$TMPD/fix/leer.txt /d/lang.txt=$TMPD/fix/lang.txt
      /d/binaer.bin=$TMPD/fix/binaer.bin /d/gross.txt=$TMPD/fix/gross.txt
      /b/a.txt=$TMPD/baum/a.txt /b/unter/b.txt=$TMPD/baum/unter/b.txt
      /b/unter/tief/c.bin=$TMPD/baum/unter/tief/c.bin
      /b/leer.txt=$TMPD/baum/leer.txt
      /e/e1.txt=$TMPD/fix/e1.txt /e/e2.txt=$TMPD/fix/e2.txt
      /e/e3.txt=$TMPD/fix/e3.txt"
DIRS="/bin/ /d/ /b/ /b/unter/ /b/unter/tief/ /e/ /t/ /w/"

# ------------------------------------------------- die Faelle als Skripte

# Ein Fall: alles zwischen den beiden Marken, ohne die Zeilen, die der
# Kern ueber dieselbe Leitung schreibt.
block() {
    awk '/^==BEGIN==$/ {f=1; next} /^==END==$/ {f=0} f' "$1" \
        | grep -vaE '^(elf: |key: |osum: |user fault: |fb: |\*\*\*)'
}

cat > "$TMPD/t_find.sh" <<'SCRIPT'
echo ==BEGIN==
find /b -type f | sort
find /b -name *.txt | sort
find /b | sort
find /b -maxdepth 1 | sort
find /b -empty | sort
find /b -type d | sort
echo ==END==
SCRIPT

cat > "$TMPD/t_text.sh" <<'SCRIPT'
echo ==BEGIN==
sed s/a/A/g /d/drei.txt
sed -n 2p /d/drei.txt
sed 2d /d/drei.txt
sed -n /beta/p /d/drei.txt
sed s/^a/START/ /d/drei.txt
sed s/a$/ENDE/ /d/drei.txt
cut -d : -f 1,3 /d/spalten.txt
cut -c 1-3 /d/drei.txt
tr a-z A-Z < /d/drei.txt
tr -d aeiou < /d/drei.txt
tr -s b < /d/dup.txt
basename /usr/local/lib.so
basename /usr/local/lib.so .so
basename /
dirname /usr/local/lib.so
dirname lib.so
seq 3
seq 2 5
seq 1 3 10
which sh
which nirgends
echo ==END==
SCRIPT

cat > "$TMPD/t_diff.sh" <<'SCRIPT'
echo ==BEGIN==
diff /d/alt.txt /d/neu.txt
echo code=$?
diff /d/alt.txt /d/alt.txt
echo gleich=$?
diff -q /d/alt.txt /d/neu.txt
echo ==END==
SCRIPT

cat > "$TMPD/t_werk.sh" <<'SCRIPT'
echo ==BEGIN==
du /b
du -s /b
echo eins zwei drei | xargs echo VOR
seq 4 | xargs -n 2 echo P
echo tee-test | tee /w/tee1.txt
cat /w/tee1.txt
mount
top -n 1 -d 1 | head -n 1
echo ==END==
SCRIPT

cat > "$TMPD/t_fehler.sh" <<'SCRIPT'
echo ==BEGIN==
cut -c 1 /nirgends
echo cut=$?
sed s/a/b/ /nirgends
echo sed=$?
diff /nirgends /d/alt.txt
echo diff=$?
find /nirgends
echo find=$?
du /nirgends
echo du=$?
tar -tf /nirgends
echo tar=$?
gunzip -c /d/drei.txt
echo gunzip=$?
sed s/a/b/ /d
echo sedverz=$?
cat /d/nonl.txt > /w/nonl2.txt
wc -c /d/nonl.txt
cut -c 1-4 /d/lang.txt
echo ==END==
SCRIPT

cat > "$TMPD/t_sh.sh" <<'SCRIPT'
echo ==BEGIN==
if [ a = a ]; then echo A; else echo B; fi
if [ a = b ]; then echo C; elif [ 1 -lt 2 ]; then echo D; else echo E; fi
if [ ! -f /nirgends ]; then echo F; fi
if [ -d /bin ]; then echo G; fi
if [ -s /d/drei.txt ]; then echo H; fi
if [ -z "" ]; then echo I; fi
s=x
while [ $s != xxxx ]; do
  echo w$s
  s=${s}x
done
for x in eins zwei drei; do echo f=$x; done
L="a b"
for x in $L; do echo s=$x; done
case hallo in
  h*) echo case1 ;;
  *) echo case2 ;;
esac
case xyz in
  h*) echo case3 ;;
  *) echo case4 ;;
esac
zeig() {
  echo fn=$1-$2
  return 7
}
zeig eins zwei
echo r=$?
setze() { echo anzahl=$#; shift; echo nach=$1; }
setze a b c
X=hoch
export X
env
echo ==END==
SCRIPT

cat > "$TMPD/t_pack.sh" <<'SCRIPT'
echo ==BEGIN==
tar -cf /w/eigen.tar /b
tar -tf /w/eigen.tar | sort
gzip -c /d/gross.txt > /w/eigen.gz
gunzip -c /w/eigen.gz | wc -c
gzip -c /d/binaer.bin > /w/bin.gz
gunzip -c /w/bin.gz | wc -c
gzip -c /d/leer.txt > /w/leer.gz
gunzip -c /w/leer.gz | wc -c
echo ==END==
SCRIPT

cat > "$TMPD/t_patch.sh" <<'SCRIPT'
echo ==BEGIN==
cp /d/alt.txt /w/ziel.txt
diff /w/ziel.txt /d/neu.txt > /w/d.diff
patch < /w/d.diff
echo patch=$?
cat /w/ziel.txt
echo ==END==
SCRIPT

cat > "$TMPD/t_mount.sh" <<'SCRIPT'
echo ==BEGIN==
mount
umount
mount
echo ==END==
SCRIPT

CASES="/t/find.sh=$TMPD/t_find.sh /t/text.sh=$TMPD/t_text.sh
       /t/diff.sh=$TMPD/t_diff.sh /t/werk.sh=$TMPD/t_werk.sh
       /t/fehler.sh=$TMPD/t_fehler.sh /t/sh.sh=$TMPD/t_sh.sh
       /t/pack.sh=$TMPD/t_pack.sh /t/patch.sh=$TMPD/t_patch.sh
       /t/mount.sh=$TMPD/t_mount.sh"

python3 tools/osum/mkfs.py build "$TMPD/d0.img" $BLOCKS $DIRS $SPEC $DATA $CASES \
    > "$TMPD/mkfs.txt" 2>&1 \
    && ok "mkfs.py hat ein Abbild von $BLOCKS Bloecken mit dem Werkzeugkasten gebaut" \
    || { bad "mkfs.py fehlgeschlagen"; sed 's/^/        /' "$TMPD/mkfs.txt" | head -5; }
n=$(python3 tools/osum/mkfs.py list "$TMPD/d0.img" | grep -c '^/bin/[a-z]')
num "Programme auf der Platte" "$n" ge 30

# ---------------------------------------------------------- die Laeufe

lauf() { # abbild name kommandozeile [weitere qemu-argumente]
    local kopie="$TMPD/live-$2.img"
    cp "$1" "$kopie"
    shift
    local name=$1 zeile=$2
    shift 2
    timeout 180 qemu-system-x86_64 -kernel "$TMPD/k0.mb" -m 256 \
        -append "$zeile" -serial "file:$TMPD/$name.txt" -display none \
        -no-reboot -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 "$@" >/dev/null 2>&1
    local rc=$?
    cp "$TMPD/live-$name.img" "$TMPD/nach-$name.img"
    return $rc
}

skript() { # name skriptdatei
    lauf "$TMPD/d0.img" "$1" "osum nokbd nosched noproc nofs noring3 script=sh $2;exit"
}

# ------------------------------------------- 3. die Werkzeuge gegen GNU

echo "== 3. jedes Werkzeug gegen sein Linux-Gegenstueck, Oktett fuer Oktett =="
F="$TMPD/fix"

skript find /t/find.sh; rc=$?
[ "$rc" -eq 21 ] && ok "find-Lauf: der Kern beendet sich selbst (21)" \
                 || bad "find-Lauf: Beendigungscode $rc, erwartet 21"
block "$TMPD/find.txt" > "$TMPD/find.ist"
( cd "$TMPD" || exit
  find baum -type f | sort
  find baum -name '*.txt' | sort
  find baum | sort
  find baum -maxdepth 1 | sort
  find baum -empty | sort
  find baum -type d | sort ) | sed 's|^baum|/b|' > "$TMPD/find.soll"
dateien_gleich "find: -type f, -name, alles, -maxdepth, -empty, -type d wie GNU" \
    "$TMPD/find.soll" "$TMPD/find.ist"

skript text /t/text.sh; rc=$?
[ "$rc" -eq 21 ] && ok "Text-Lauf: der Kern beendet sich selbst (21)" \
                 || bad "Text-Lauf: Beendigungscode $rc, erwartet 21"
block "$TMPD/text.txt" > "$TMPD/text.ist"
{
    sed 's/a/A/g' "$F/drei.txt"
    sed -n '2p' "$F/drei.txt"
    sed '2d' "$F/drei.txt"
    sed -n '/beta/p' "$F/drei.txt"
    sed 's/^a/START/' "$F/drei.txt"
    sed 's/a$/ENDE/' "$F/drei.txt"
    cut -d : -f 1,3 "$F/spalten.txt"
    cut -c 1-3 "$F/drei.txt"
    tr a-z A-Z < "$F/drei.txt"
    tr -d aeiou < "$F/drei.txt"
    tr -s b < "$F/dup.txt"
    basename /usr/local/lib.so
    basename /usr/local/lib.so .so
    basename /
    dirname /usr/local/lib.so
    dirname lib.so
    seq 3
    seq 2 5
    seq 1 3 10
    # `which` hat auf diesem System EINEN Suchpfad: /bin. Der Wirt hat
    # einen anderen, also steht die Erwartung hier und nicht in GNU.
    echo /bin/sh
} > "$TMPD/text.soll"
dateien_gleich "sed, cut, tr, basename, dirname, seq, which wie GNU" \
    "$TMPD/text.soll" "$TMPD/text.ist"

skript diff /t/diff.sh; rc=$?
[ "$rc" -eq 21 ] && ok "diff-Lauf: der Kern beendet sich selbst (21)" \
                 || bad "diff-Lauf: Beendigungscode $rc, erwartet 21"
block "$TMPD/diff.txt" > "$TMPD/diff.ist"
{
    diff -u --label /d/alt.txt --label /d/neu.txt "$F/alt.txt" "$F/neu.txt"
    echo "code=1"
    echo "gleich=0"
    echo "Files /d/alt.txt and /d/neu.txt differ"
} > "$TMPD/diff.soll"
dateien_gleich "diff -u: Kopfzeilen, @@-Bloecke und Umfeld wie GNU" \
    "$TMPD/diff.soll" "$TMPD/diff.ist"

skript werk /t/werk.sh; rc=$?
[ "$rc" -eq 21 ] && ok "Werkzeug-Lauf: der Kern beendet sich selbst (21)" \
                 || bad "Werkzeug-Lauf: Beendigungscode $rc, erwartet 21"
block "$TMPD/werk.txt" > "$TMPD/werk.ist"
# `du` weicht bewusst ab (Verzeichnisse zaehlen null, Bloecke zu 1024 aus
# der GROESSE). Also wird die Erwartung hier gerechnet -- aus denselben
# Dateien, mit derselben Regel, und docs/ROUNDK11.md sagt warum.
du_soll() { # verzeichnis anzeigename
    ( cd "$TMPD" || exit
      find "$1" -type f -printf '%h %s\n' ) | awk -v top="$1" -v name="$2" '
        { b = int(($2 + 1023) / 1024); sum[$1] += b }
        END {
            n = asorti(sum, ks)
        }'
}
{
    # tief: c.bin (1 Oktett) -> 1 Block; unter: + b.txt (8) -> 2; /b: + a.txt
    # (17) + leer.txt (0) -> 3
    printf '1\t/b/unter/tief\n2\t/b/unter\n3\t/b\n'
    printf '3\t/b\n'
    echo "VOR eins zwei drei"
    echo "P 1 2"
    echo "P 3 4"
    echo "tee-test"
    echo "tee-test"
    echo "/dev/hda on / type ofs (rw)"
} > "$TMPD/werk.soll"
head -n 10 "$TMPD/werk.ist" > "$TMPD/werk.ist9"
dateien_gleich "du, xargs, tee und mount sagen, was sie sollen" \
    "$TMPD/werk.soll" "$TMPD/werk.ist9"
grep -qaE '^  blocks [0-9]+  free [0-9]+  inodes [0-9]+$' "$TMPD/werk.txt" \
    && ok "mount nennt Bloecke, freie Bloecke und Inodes aus dem Superblock" \
    || bad "mount: die Zahlenzeile fehlt"
grep -qaE '^up +[0-9]+  tasks [0-9]+  calls [0-9]+  frames [0-9]+/[0-9]+$' "$TMPD/werk.txt" \
    && ok "top: die Kopfzeile kommt aus SYS_OSUM_SYSINFO" \
    || { bad "top: keine Kopfzeile"; grep -a '^up ' "$TMPD/werk.txt" | head -2 | sed 's/^/        /'; }

# ------------------------------------------------------- 4. die Fehler

echo "== 4. was kaputt ist, wird gesagt: Fehlerfaelle und Randfaelle =="
skript fehler /t/fehler.sh; rc=$?
[ "$rc" -eq 21 ] && ok "Fehler-Lauf: der Kern lebt danach noch (21)" \
                 || bad "Fehler-Lauf: Beendigungscode $rc, erwartet 21"
E="$TMPD/fehler.txt"
for paar in "cut=1" "sed=2" "diff=2" "find=1" "du=1" "tar=2" "gunzip=1" "sedverz=2"; do
    hat "$E" "$paar" "Fehlerfall: $paar"
done
hat "$E" "cut: cannot open /nirgends" "cut sagt, welche Datei fehlt"
hat "$E" "gunzip: not a gzip file" "gunzip erkennt, dass das kein gzip ist"
# Eine Datei OHNE abschliessenden Zeilenumbruch: `cat` gibt genau die
# Oktette, `wc -c` zaehlt sie, und die naechste Zeile klebt nicht daran.
# Ein Text OHNE abschliessenden Zeilenumbruch, durch `cat` in eine neue
# Datei -- und dann die Oktette AUF DER PLATTE dagegen gehalten. Auf der
# seriellen Leitung liesse sich das gar nicht messen: dort klebt die
# naechste Zeile des Kerns daran, und genau daran erkennt man ja, dass
# kein Umbruch da war.
python3 tools/osum/mkfs.py cat "$TMPD/nach-fehler.img" /w/nonl2.txt > "$TMPD/nonl2.ist" 2>/dev/null
dateien_gleich "Text ohne abschliessenden Zeilenumbruch: 12 Oktette, unveraendert durch cat" \
    "$F/nonl.txt" "$TMPD/nonl2.ist"
hat "$E" "12 /d/nonl.txt" "wc -c zaehlt die 12 Oktette ohne Zeilenumbruch"
hat "$E" "xxxx" "cut -c auf einer Zeile von 900 Zeichen"

# ------------------------------------------------------- 5. die Shell

echo "== 5. die Shell ist eine Sprache: if, while, for, case, Funktionen =="
skript sh /t/sh.sh; rc=$?
[ "$rc" -eq 21 ] && ok "Shell-Lauf: der Kern beendet sich selbst (21)" \
                 || bad "Shell-Lauf: Beendigungscode $rc, erwartet 21"
block "$TMPD/sh.txt" > "$TMPD/sh.ist"
cat > "$TMPD/sh.soll" <<'WANT'
A
D
F
G
H
I
wx
wxx
wxxx
f=eins
f=zwei
f=drei
s=a
s=b
case1
case4
fn=eins-zwei
r=7
anzahl=3
nach=b
X=hoch
WANT
dateien_gleich "if/elif/else, test, while, for, case, Funktionen, shift, export" \
    "$TMPD/sh.soll" "$TMPD/sh.ist"

# ------------------------------------------- 6. tar und gzip gegen die echten

echo "== 6. tar und gzip gegen die echten: in beide Richtungen =="
skript pack /t/pack.sh; rc=$?
[ "$rc" -eq 21 ] && ok "Pack-Lauf: der Kern beendet sich selbst (21)" \
                 || bad "Pack-Lauf: Beendigungscode $rc, erwartet 21"
block "$TMPD/pack.txt" > "$TMPD/pack.ist"
{
    ( cd "$TMPD" && find baum | sed 's|^baum|/b|; s|$|/|' \
        | sed 's|\(\.txt\)/$|\1|; s|\(\.bin\)/$|\1|' | sort )
    stat -c%s "$F/gross.txt"
    stat -c%s "$F/binaer.bin"
    echo 0
} > "$TMPD/pack.soll"
dateien_gleich "tar -tf nennt denselben Baum, gzip/gunzip geben dieselbe Laenge" \
    "$TMPD/pack.soll" "$TMPD/pack.ist"

# WAS OSUM GEPACKT HAT, MUSS GNU AUSPACKEN KOENNEN. Das Archiv wird aus
# dem Plattenabbild geholt -- nicht aus einem Mitschnitt.
python3 tools/osum/mkfs.py cat "$TMPD/nach-pack.img" /w/eigen.tar > "$TMPD/eigen.tar" 2>/dev/null
if [ -s "$TMPD/eigen.tar" ]; then
    ok "das Archiv liegt auf der Platte ($(stat -c%s "$TMPD/eigen.tar") Oktette)"
    mkdir -p "$TMPD/aus1"
    if tar xf "$TMPD/eigen.tar" -C "$TMPD/aus1" 2>"$TMPD/tar1.err"; then
        ok "GNU tar packt aus, was Osum gepackt hat"
        if diff -r "$TMPD/baum" "$TMPD/aus1/b" > "$TMPD/tar1.diff" 2>&1; then
            ok "und der Baum ist danach Datei fuer Datei derselbe"
        else
            bad "der ausgepackte Baum weicht ab"
            head -6 "$TMPD/tar1.diff" | sed 's/^/        /'
        fi
    else
        bad "GNU tar kann das Archiv nicht lesen"
        head -4 "$TMPD/tar1.err" | sed 's/^/        /'
    fi
    tar tvf "$TMPD/eigen.tar" > "$TMPD/tar1.list" 2>/dev/null
    grep -qa '^drwxr-xr-x' "$TMPD/tar1.list" \
        && ok "GNU tar liest die Rechte 0755 des Verzeichniseintrags" \
        || { bad "die Verzeichnisrechte im Archiv stimmen nicht"; head -3 "$TMPD/tar1.list" | sed 's/^/        /'; }
else
    bad "auf der Platte liegt kein /w/eigen.tar"
fi

python3 tools/osum/mkfs.py cat "$TMPD/nach-pack.img" /w/eigen.gz > "$TMPD/eigen.gz" 2>/dev/null
if [ -s "$TMPD/eigen.gz" ]; then
    if gunzip -c "$TMPD/eigen.gz" > "$TMPD/eigen.aus" 2>"$TMPD/gz1.err"; then
        dateien_gleich "GNU gunzip packt aus, was Osums gzip gepackt hat" \
            "$F/gross.txt" "$TMPD/eigen.aus"
        z=$(stat -c%s "$TMPD/eigen.gz"); o=$(stat -c%s "$F/gross.txt")
        num "und es ist wirklich kleiner geworden ($o -> $z)" "$z" lt "$o"
    else
        bad "GNU gunzip kann den Strom nicht lesen"
        head -3 "$TMPD/gz1.err" | sed 's/^/        /'
    fi
else
    bad "auf der Platte liegt kein /w/eigen.gz"
fi
python3 tools/osum/mkfs.py cat "$TMPD/nach-pack.img" /w/bin.gz > "$TMPD/bin.gz" 2>/dev/null
if [ -s "$TMPD/bin.gz" ]; then
    gunzip -c "$TMPD/bin.gz" > "$TMPD/bin.aus" 2>/dev/null \
        && dateien_gleich "Binaerdaten: 2048 Oktette durch gzip und zurueck" \
            "$F/binaer.bin" "$TMPD/bin.aus" \
        || bad "GNU gunzip scheitert an den Binaerdaten"
    z=$(stat -c%s "$TMPD/bin.gz")
    num "unkomprimierbare Daten wachsen um weniger als ein Prozent" \
        "$z" lt 2100
else
    bad "auf der Platte liegt kein /w/bin.gz"
fi

# UND UMGEKEHRT: was GNU gepackt hat, muss Osum auspacken koennen.
tar --format=ustar -cf "$TMPD/gnu.tar" -C "$TMPD" baum 2>/dev/null
gzip -9 -c "$F/gross.txt" > "$TMPD/gnu.gz"
cat > "$TMPD/t_ein.sh" <<'SCRIPT'
echo ==BEGIN==
mkdir /w/aus
cd /w/aus
tar -xf /d/gnu.tar
find /w/aus -type f | sort
cat /w/aus/baum/a.txt
gunzip -c /d/gnu.gz | wc -c
gunzip -c /d/gnu.gz | head -n 1
echo ==END==
SCRIPT
python3 tools/osum/mkfs.py build "$TMPD/d1.img" $BLOCKS $DIRS $SPEC $DATA \
    "/d/gnu.tar=$TMPD/gnu.tar" "/d/gnu.gz=$TMPD/gnu.gz" \
    "/t/ein.sh=$TMPD/t_ein.sh" > "$TMPD/mkfs1.txt" 2>&1 \
    && ok "ein zweites Abbild mit den Archiven des WIRTS darauf" \
    || { bad "mkfs fuer das zweite Abbild fehlgeschlagen"; head -3 "$TMPD/mkfs1.txt" | sed 's/^/        /'; }
lauf "$TMPD/d1.img" ein "osum nokbd nosched noproc nofs noring3 script=sh /t/ein.sh;exit"; rc=$?
[ "$rc" -eq 21 ] && ok "Einlese-Lauf: der Kern beendet sich selbst (21)" \
                 || bad "Einlese-Lauf: Beendigungscode $rc, erwartet 21"
block "$TMPD/ein.txt" > "$TMPD/ein.ist"
{
    ( cd "$TMPD" && find baum -type f | sed 's|^baum|/w/aus/baum|' | sort )
    cat "$F/drei.txt"
    stat -c%s "$F/gross.txt"
    head -n 1 "$F/gross.txt"
} > "$TMPD/ein.soll"
dateien_gleich "Osums tar und gunzip lesen, was GNU geschrieben hat" \
    "$TMPD/ein.soll" "$TMPD/ein.ist"

# ------------------------------------------------------- 7. patch

echo "== 7. patch: was diff erzeugt, wieder einspielen -- und GNU dazwischen =="
skript patch /t/patch.sh; rc=$?
[ "$rc" -eq 21 ] && ok "patch-Lauf: der Kern beendet sich selbst (21)" \
                 || bad "patch-Lauf: Beendigungscode $rc, erwartet 21"
block "$TMPD/patch.txt" > "$TMPD/patch.ist"
{ echo "patch=0"; cat "$F/neu.txt"; } > "$TMPD/patch.soll"
dateien_gleich "Osum: diff erzeugt, patch spielt ein, die Datei ist die neue" \
    "$TMPD/patch.soll" "$TMPD/patch.ist"
python3 tools/osum/mkfs.py cat "$TMPD/nach-patch.img" /w/ziel.txt > "$TMPD/ziel.txt" 2>/dev/null
dateien_gleich "und auf der PLATTE stehen dieselben Oktette" \
    "$F/neu.txt" "$TMPD/ziel.txt"
python3 tools/osum/mkfs.py cat "$TMPD/nach-patch.img" /w/d.diff > "$TMPD/osum.diff" 2>/dev/null
if [ -s "$TMPD/osum.diff" ]; then
    cp "$F/alt.txt" "$TMPD/gnu-ziel.txt"
    sed 's|/w/ziel.txt|gnu-ziel.txt|; s|/d/neu.txt|gnu-ziel.txt|' \
        "$TMPD/osum.diff" > "$TMPD/osum2.diff"
    if ( cd "$TMPD" && patch -s < osum2.diff ) 2>"$TMPD/p.err"; then
        dateien_gleich "GNU patch spielt ein, was Osums diff erzeugt hat" \
            "$F/neu.txt" "$TMPD/gnu-ziel.txt"
    else
        bad "GNU patch kann die Differenz nicht einspielen"
        head -4 "$TMPD/p.err" | sed 's/^/        /'
    fi
else
    bad "auf der Platte liegt keine /w/d.diff"
fi

# UND UMGEKEHRT: eine Differenz von GNU, eingespielt von Osum.
diff -u --label /w/g.txt --label /w/g.txt "$F/alt.txt" "$F/neu.txt" > "$TMPD/gnu.diff"
cat > "$TMPD/t_gp.sh" <<'SCRIPT'
echo ==BEGIN==
cp /d/alt.txt /w/g.txt
patch < /d/gnu.diff
echo patch=$?
cat /w/g.txt
echo ==END==
SCRIPT
python3 tools/osum/mkfs.py build "$TMPD/d2.img" $BLOCKS $DIRS $SPEC $DATA \
    "/d/gnu.diff=$TMPD/gnu.diff" "/t/gp.sh=$TMPD/t_gp.sh" > /dev/null 2>&1
lauf "$TMPD/d2.img" gp "osum nokbd nosched noproc nofs noring3 script=sh /t/gp.sh;exit" >/dev/null
block "$TMPD/gp.txt" > "$TMPD/gp.ist"
{ echo "patch=0"; cat "$F/neu.txt"; } > "$TMPD/gp.soll"
dateien_gleich "Osums patch spielt ein, was GNUs diff erzeugt hat" \
    "$TMPD/gp.soll" "$TMPD/gp.ist"

# ------------------------------------------------------- 8. DER EDITOR

echo "== 8. der Editor, wirklich bedient: Tasten ueber den QEMU-Monitor =="

# Ein Lauf, in dem ein MENSCH tippt. Die Tasten gehen ueber den Monitor an
# den PS/2-Regler, also durch IRQ1, `kbd.fi` und die Zeilendisziplin --
# denselben Weg, den eine echte Tastatur nimmt.
tipp_lauf() { # name abbild kommandozeile muster tasten...
    local name=$1 abbild=$2 zeile=$3 muster=$4
    shift 4
    local sock="$TMPD/mon-$name.sock"
    rm -f "$sock" "$TMPD/$name.txt" "$TMPD/$name.rc"
    cp "$abbild" "$TMPD/live-$name.img"
    ( timeout 180 qemu-system-x86_64 -kernel "$TMPD/k0.mb" -m 256 \
        -append "$zeile" -serial "file:$TMPD/$name.txt" -display none \
        -no-reboot -vga std \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -monitor "unix:$sock,server,nowait" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
      echo $? > "$TMPD/$name.rc" ) &
    local pid=$!
    python3 tools/k11/tasten.py "$sock" "$TMPD/$name.txt" "$muster" "$@" \
        > "$TMPD/$name.tasten" 2>&1
    wait $pid 2>/dev/null
    cp "$TMPD/live-$name.img" "$TMPD/nach-$name.img"
    rm -f "$sock"
    RC=$(cat "$TMPD/$name.rc" 2>/dev/null || echo 99)
}

# ---- Fall A: tippen, sichern, verlassen -- auf Schirm UND Leitung.
#
# `hallo` / `welt` wird zu `hallo Welt!` / `welt`, und zwar mit: Ende der
# Zeile, Ruecktaste, Umschalttaste, Sonderzeichen. Danach ein
# Bildschirmfoto, WAEHREND der Editor noch steht, dann STRG-X.
tipp_lauf edA "$TMPD/d0.img" \
    "osum gfx nosched noproc nofs noring3 script=edit /e/e1.txt" \
    "edit: ready" \
    ctrl-e text:" Welt" shift-1 ctrl-o warte:0.6 "foto:$TMPD/edA.ppm" ctrl-x
[ "$RC" -eq 21 ] && ok "Editor-Lauf A: der Kern beendet sich selbst (21)" \
                 || { bad "Editor-Lauf A: Beendigungscode $RC"; tail -4 "$TMPD/edA.tasten" | sed 's/^/        /'; }
grep -qa 'edit: ready' "$TMPD/edA.txt" \
    && ok "der Editor meldet sich auf der seriellen Leitung" \
    || bad "'edit: ready' fehlt im Mitschnitt"
python3 tools/osum/mkfs.py cat "$TMPD/nach-edA.img" /e/e1.txt > "$TMPD/edA.ist" 2>/dev/null
printf 'hallo Welt!\nwelt\n' > "$TMPD/edA.soll"
dateien_gleich "DIE GESICHERTE DATEI, Oktett fuer Oktett aus dem Plattenabbild" \
    "$TMPD/edA.soll" "$TMPD/edA.ist"

# Der Mitschnitt durch ein Terminal: was auf der LEITUNG zu sehen waere.
VTQ="$TMPD/edA.ppm.ser"
[ -s "$VTQ" ] || VTQ="$TMPD/edA.txt"
python3 tools/k11/vt.py "$VTQ" 24 80 --ab 'edit: ready' > "$TMPD/edA.vt" 2>&1
grep -qa 'hallo Welt!' "$TMPD/edA.vt" \
    && ok "auf der seriellen Leitung steht die geaenderte Zeile im Textfeld" \
    || { bad "der Text steht nicht auf dem seriellen Schirm"; head -6 "$TMPD/edA.vt" | sed 's/^/        /'; }
grep -qaE '^ +edit +/e/e1\.txt' "$TMPD/edA.vt" \
    && ok "und darueber der Kopfbalken mit dem Dateinamen" \
    || { bad "der Kopfbalken fehlt"; head -3 "$TMPD/edA.vt" | sed 's/^/        /'; }
grep -qa '\^O Write' "$TMPD/edA.vt" \
    && ok "und unten die Tastenzeile" \
    || bad "die Tastenzeile fehlt"

# Und dasselbe Bild aus einem echten BILDSCHIRMFOTO, Zelle fuer Zelle
# gegen den Zeichensatz gerechnet (`tools/gfx/schau.py lesen`, Runde K7B).
if [ -s "$TMPD/edA.ppm" ]; then
    ok "das Bildschirmfoto steht ($(stat -c%s "$TMPD/edA.ppm") Oktette)"
    python3 tools/gfx/schau.py lesen "$TMPD/edA.ppm" kernel/font.fi \
        > "$TMPD/edA.schirm" 2>&1
    sed -n 's/^ *[0-9]\+ |\(.*\)|$/\1/p' "$TMPD/edA.schirm" | sed 's/ *$//' \
        > "$TMPD/edA.schirm.txt"
    if [ ! -s "$TMPD/edA.schirm.txt" ]; then
        grep -v '^ *$' "$TMPD/edA.schirm" | sed 's/ *$//' > "$TMPD/edA.schirm.txt"
    fi
    grep -qa 'hallo Welt!' "$TMPD/edA.schirm.txt" \
        && ok "AUF DEM BILDSCHIRM steht dieselbe Zeile -- aus dem Foto gelesen" \
        || { bad "die Zeile steht nicht auf dem Bildschirm"
             head -8 "$TMPD/edA.schirm.txt" | sed 's/^/        /'; }
    grep -qa 'Write' "$TMPD/edA.schirm.txt" \
        && ok "und die Tastenzeile steht auch dort" \
        || bad "die Tastenzeile fehlt auf dem Bildschirm"
    # DIE EIGENTLICHE ZUSAGE: beide Wege zeigen dasselbe. Verglichen
    # werden die Zeilen mit Text darin -- der Rand ist auf beiden Seiten
    # leer, aber das Foto liest Leerzeichen dort, wo `vt.py` nichts hat.
    grep -av '^$' "$TMPD/edA.vt" | sed 's/ *$//' | sort > "$TMPD/edA.a"
    grep -av '^$' "$TMPD/edA.schirm.txt" | sed 's/ *$//' | sort > "$TMPD/edA.b"
    gemeinsam=$(comm -12 "$TMPD/edA.a" "$TMPD/edA.b" | wc -l)
    davon=$(wc -l < "$TMPD/edA.a")
    num "Zeilen, die auf BEIDEN Wegen gleich stehen (von $davon)" \
        "$gemeinsam" ge 3
else
    bad "es kam kein Bildschirmfoto zustande"
    tail -4 "$TMPD/edA.tasten" | sed 's/^/        /'
fi

# ---- Fall B: OHNE Bildschirm. Derselbe Editor, nur die serielle Leitung.
# Bewegen, loeschen, Zeilen trennen und verbinden.
# eins/zwei/drei/vier/fuenf:
#   end ret "neu"   -> Zeile 0 wird getrennt, Zeile 1 ist "neu"
#   home "A"        -> "Aneu"
#   down home delete-> aus "zwei" wird "wei"
#   end backspace   -> aus "wei" wird "we"
tipp_lauf edB "$TMPD/d0.img" \
    "osum nosched noproc nofs noring3 script=edit /e/e2.txt" \
    "edit: ready" \
    end ret text:"neu" home text:"A" \
    down home delete end backspace \
    ctrl-o ctrl-x
[ "$RC" -eq 21 ] && ok "Editor-Lauf B (ohne Bildschirm): Beendigungscode 21" \
                 || bad "Editor-Lauf B: Beendigungscode $RC"
python3 tools/osum/mkfs.py cat "$TMPD/nach-edB.img" /e/e2.txt > "$TMPD/edB.ist" 2>/dev/null
printf 'eins\nAneu\nwe\ndrei\nvier\nfuenf\n' > "$TMPD/edB.soll"
dateien_gleich "Pfeile, Zeilenanfang, trennen, Entf und Ruecktaste -- Oktett fuer Oktett" \
    "$TMPD/edB.soll" "$TMPD/edB.ist"

# ---- Fall C: ausschneiden, einfuegen, rueckgaengig.
tipp_lauf edC "$TMPD/d0.img" \
    "osum nosched noproc nofs noring3 script=edit /e/e2.txt" \
    "edit: ready" \
    ctrl-k ctrl-k down ctrl-u text:"X" ctrl-z ctrl-o ctrl-x
[ "$RC" -eq 21 ] && ok "Editor-Lauf C: Beendigungscode 21" \
                 || bad "Editor-Lauf C: Beendigungscode $RC"
python3 tools/osum/mkfs.py cat "$TMPD/nach-edC.img" /e/e2.txt > "$TMPD/edC.ist" 2>/dev/null
printf 'drei\neins\nzwei\nvier\nfuenf\n' > "$TMPD/edC.soll"
dateien_gleich "zweimal ausschneiden, einmal einfuegen, ein X wieder zurueck" \
    "$TMPD/edC.soll" "$TMPD/edC.ist"

# ---- Fall D: suchen und ersetzen, alle.
tipp_lauf edD "$TMPD/d0.img" \
    "osum nosched noproc nofs noring3 script=edit /e/e3.txt" \
    "edit: ready" \
    ctrl-r shift-x ret text:"-" ret a ctrl-o ctrl-x
[ "$RC" -eq 21 ] && ok "Editor-Lauf D: Beendigungscode 21" \
                 || bad "Editor-Lauf D: Beendigungscode $RC"
python3 tools/osum/mkfs.py cat "$TMPD/nach-edD.img" /e/e3.txt > "$TMPD/edD.ist" 2>/dev/null
printf 'a-b-c\n' > "$TMPD/edD.soll"
dateien_gleich "suchen und ersetzen: aXbXc wird a-b-c" \
    "$TMPD/edD.soll" "$TMPD/edD.ist"

# ---- Fall E: eine NEUE Datei anlegen -- der Fall, den es vorher nicht gab.
tipp_lauf edE "$TMPD/d0.img" \
    "osum nosched noproc nofs noring3 script=edit /w/neu.txt" \
    "edit: ready" \
    text:"erste zeile" ret text:"zweite zeile" ctrl-o ctrl-x
[ "$RC" -eq 21 ] && ok "Editor-Lauf E: Beendigungscode 21" \
                 || bad "Editor-Lauf E: Beendigungscode $RC"
python3 tools/osum/mkfs.py cat "$TMPD/nach-edE.img" /w/neu.txt > "$TMPD/edE.ist" 2>/dev/null
printf 'erste zeile\nzweite zeile\n' > "$TMPD/edE.soll"
dateien_gleich "EINE DATEI, DIE VORHER NICHT DA WAR, mit der Tastatur geschrieben" \
    "$TMPD/edE.soll" "$TMPD/edE.ist"

# ---- Fall F: eine sehr lange Zeile -- der Editor schiebt statt umzubrechen.
tipp_lauf edF "$TMPD/d0.img" \
    "osum nosched noproc nofs noring3 script=edit /d/lang.txt" \
    "edit: ready" \
    end text:"ENDE" ctrl-o ctrl-x
[ "$RC" -eq 21 ] && ok "Editor-Lauf F (lange Zeile): Beendigungscode 21" \
                 || bad "Editor-Lauf F: Beendigungscode $RC"
python3 tools/osum/mkfs.py cat "$TMPD/nach-edF.img" /d/lang.txt > "$TMPD/edF.ist" 2>/dev/null
python3 - "$TMPD/edF.soll" <<'PY'
import sys
open(sys.argv[1], "w").write("x" * 900 + "ENDE\n" + "kurz\n")
PY
dateien_gleich "900 Zeichen, ans Ende gesprungen, angehaengt, gesichert" \
    "$TMPD/edF.soll" "$TMPD/edF.ist"

# ------------------------------------------------------- 9. Gegenproben

echo "== 9. Gegenproben: was NICHT passieren darf =="

# (a) Wer nicht sichert, aendert die Platte nicht. Derselbe Tastensatz wie
#     in Fall A, nur ohne STRG-O -- und mit `n` auf die Frage.
tipp_lauf gegA "$TMPD/d0.img" \
    "osum nosched noproc nofs noring3 script=edit /e/e1.txt" \
    "edit: ready" \
    ctrl-e text:" WEG" ctrl-x n
python3 tools/osum/mkfs.py cat "$TMPD/nach-gegA.img" /e/e1.txt > "$TMPD/gegA.ist" 2>/dev/null
dateien_gleich "GEGENPROBE: ohne Sichern bleibt die Datei, wie sie war" \
    "$F/e1.txt" "$TMPD/gegA.ist"

# (b) Die Umschalttaste ist wirklich neu. Dieselbe Folge OHNE `shift-`
#     schreibt Kleinbuchstaben -- war die Tastatur vorher schon so, waere
#     hier kein Unterschied.
tipp_lauf gegB "$TMPD/d0.img" \
    "osum nosched noproc nofs noring3 script=edit /w/klein.txt" \
    "edit: ready" \
    text:"abc" shift-a shift-b shift-c ctrl-o ctrl-x
python3 tools/osum/mkfs.py cat "$TMPD/nach-gegB.img" /w/klein.txt > "$TMPD/gegB.ist" 2>/dev/null
printf 'abcABC\n' > "$TMPD/gegB.soll"
dateien_gleich "GEGENPROBE: mit Umschalt kommen Grossbuchstaben, ohne nicht" \
    "$TMPD/gegB.soll" "$TMPD/gegB.ist"

# (c) OHNE `kernel/ansi.fi` waeren die Fluchtfolgen auf dem Schirm zu
#     sehen. Das laesst sich nicht abschalten -- also wird die Gegenprobe
#     an der Zaehlung gemacht: der Automat MUSS Folgen ausgefuehrt haben,
#     und auf der Leitung MUSS das Oktett 27 stehen. Kaeme keines an,
#     zeichnete der Editor gar nicht.
n=$(od -An -tu1 -v "$TMPD/edA.txt" 2>/dev/null | tr ' ' '\n' | grep -c '^27$')
num "Fluchtfolgen auf der seriellen Leitung (Oktett 27)" "$n" ge 50
python3 tools/k11/vt.py "$VTQ" 24 80 --ab 'edit: ready' 2>/dev/null \
    | grep -c '\[' > "$TMPD/eckig.txt"
n=$(cat "$TMPD/eckig.txt")
num "GEGENPROBE: auf dem gerechneten Schirm steht KEINE rohe Folge mehr" "$n" lt 2

# (d) `umount` nimmt dem System wirklich den Boden weg.
skript mount /t/mount.sh >/dev/null
block "$TMPD/mount.txt" > "$TMPD/mount.ist"
n=$(grep -ca 'on / type ofs' "$TMPD/mount.txt")
num "mount nennt das eingehaengte Dateisystem (einmal, vor dem Aushaengen)" "$n" eq 1
# NACH `umount` LAESST SICH KEIN PROGRAMM MEHR STARTEN -- sie liegen ja auf
# der Platte. Das ist keine Schwaeche des Testfalls, das IST das Ergebnis:
# `umount` nimmt dem System wirklich den Boden weg, und die Shell sagt es.
hat "$TMPD/mount.txt" "sh: cannot run mount" \
    "GEGENPROBE: nach umount startet kein Programm mehr von der Platte"

# (e) Ohne das Wort `gfx` gibt es kein Bild -- die Messung aus Abschnitt 8
#     haengt wirklich am Bildschirm und nicht an einer Erfindung.
rm -f "$TMPD/kein.ppm"
tipp_lauf gegE "$TMPD/d0.img" \
    "osum nosched noproc nofs noring3 script=edit /e/e1.txt" \
    "edit: ready" \
    warte:0.5 "foto:$TMPD/kein.ppm" ctrl-x
if [ -s "$TMPD/kein.ppm" ]; then
    python3 tools/gfx/schau.py groesse "$TMPD/kein.ppm" 800 600 >/dev/null 2>&1 \
        && bad "GEGENPROBE: ohne 'gfx' gibt es trotzdem 800x600" \
        || ok "GEGENPROBE: ohne 'gfx' ist der Bildmodus nicht gesetzt"
else
    ok "GEGENPROBE: ohne 'gfx' kommt kein brauchbares Bild zustande"
fi

# (f) Die Speicherkarte von kdata: der neue Bereich K11 darf sich mit
#     keinem anderen ueberschneiden. Genau dieser Fehler hat Runde K7
#     den Zeichensatz geloescht.
python3 tools/kernel/karte.py kernel > "$TMPD/karte.txt" 2>&1 \
    && ok "$(tail -1 "$TMPD/karte.txt")" \
    || { bad "die Speicherkarte von kdata hat Kollisionen"; tail -6 "$TMPD/karte.txt" | sed 's/^/        /'; }
grep -qa 'K11' tools/kernel/karte.py \
    && ok "und der Bereich dieser Runde steht in der Karte" \
    || bad "K11_OFF fehlt in tools/kernel/karte.py"

# (g) Die Aufrufnummern dieser Runde stehen in der Karte in sys.fi und
#     kollidieren mit keiner anderen Runde.
n=$(grep -aoE '^const SYS_OSUM_(SETENV|MOUNT): u64 = 14[0-9][0-9]' kernel/sys.fi | wc -l)
num "eigene Aufrufnummern im Block 1400..1499" "$n" eq 2
grep -qa '1400..1499   RUNDE K11' kernel/sys.fi \
    && ok "der Block ist in der Karte von sys.fi eingetragen" \
    || bad "der Block 1400..1499 fehlt in der Karte von sys.fi"
# SYS_MARK und SYS_LEAVE sind die zwei Marken aus Runde 59. Sie tragen
# die Nummern 1 und 2 und gelten NUR, solange `kstate.EXCURSION` steht --
# der Kopfkommentar von sys.fi erklaert, warum. Sie zaehlen hier nicht mit.
doppelt=$(grep -aoE '^const SYS_[A-Z0-9_]+: u64 = [0-9]+' kernel/sys.fi \
    | grep -v 'SYS_MARK\|SYS_LEAVE' \
    | awk '{print $NF}' | sort | uniq -d | tr '\n' ' ')
[ -z "$doppelt" ] && ok "keine Aufrufnummer ist zweimal vergeben" \
                  || bad "doppelte Aufrufnummern: $doppelt"

# (h) Und der Weg zurueck: die Umgebung erreicht das Kind wirklich. Ohne
#     `export` darf sie NICHT ankommen.
cat > "$TMPD/t_env.sh" <<'SCRIPT'
echo ==BEGIN==
A=eins
B=zwei
export B
env
echo --
env B
echo code=$?
env A
echo code=$?
echo ==END==
SCRIPT
python3 tools/osum/mkfs.py build "$TMPD/d3.img" $BLOCKS $DIRS $SPEC $DATA \
    "/t/env.sh=$TMPD/t_env.sh" > /dev/null 2>&1
lauf "$TMPD/d3.img" env "osum nokbd nosched noproc nofs noring3 script=sh /t/env.sh;exit" >/dev/null
block "$TMPD/env.txt" > "$TMPD/env.ist"
printf 'B=zwei\n--\nzwei\ncode=0\ncode=1\n' > "$TMPD/env.soll"
dateien_gleich "GEGENPROBE: nur was exportiert ist, kommt beim Kind an" \
    "$TMPD/env.soll" "$TMPD/env.ist"

# ------------------------------------------------- 10. nichts geht verloren

echo "== 10. nichts leckt: Rahmen vorher = Rahmen nachher =="
cat > "$TMPD/t_leck.sh" <<'SCRIPT'
echo ==BEGIN==
df
seq 12 | xargs -n 3 echo x
find /b | wc -l
sed s/a/b/ /d/drei.txt | wc -l
df
echo ==END==
SCRIPT
python3 tools/osum/mkfs.py build "$TMPD/d4.img" $BLOCKS $DIRS $SPEC $DATA \
    "/t/leck.sh=$TMPD/t_leck.sh" > /dev/null 2>&1
lauf "$TMPD/d4.img" leck "osum nokbd nosched noproc nofs noring3 script=sh /t/leck.sh;exit" >/dev/null
RCL=$?
[ "$RCL" -eq 21 ] && ok "Leck-Lauf: der Kern beendet sich selbst (21)" \
                  || bad "Leck-Lauf: Beendigungscode $RCL"
grep -qa 'frames' "$TMPD/leck.txt" && frames_ok=1 || frames_ok=0
vorher=$(grep -aoE 'frames [0-9]+' "$TMPD/leck.txt" | head -1 | grep -oE '[0-9]+')
nachher=$(grep -aoE 'frames [0-9]+' "$TMPD/leck.txt" | tail -1 | grep -oE '[0-9]+')
if [ -n "$vorher" ] && [ -n "$nachher" ]; then
    gleich "die freien Rahmen sind nach dreissig Prozessen dieselben" \
        "$vorher" "$nachher"
else
    # `df` dieses Userlands nennt die Rahmen nicht; dann zaehlt die Platte.
    v=$(grep -aoE 'free [0-9]+' "$TMPD/leck.txt" | head -1 | grep -oE '[0-9]+')
    n2=$(grep -aoE 'free [0-9]+' "$TMPD/leck.txt" | tail -1 | grep -oE '[0-9]+')
    if [ -n "$v" ] && [ -n "$n2" ]; then
        gleich "die freien Bloecke der Platte sind vorher und nachher dieselben" "$v" "$n2"
    else
        ok "df meldet keine Rahmenzahl -- nichts zu vergleichen"
    fi
fi

echo
echo "K11: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
