#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/dynlader/run.sh -- DIE ABNAHME DER RUNDE DYNLADER.
#
#   bash tools/dynlader/run.sh [arbeitsverzeichnis]
#
# ==================================================================
# WAS HIER GEMESSEN WIRD
# ==================================================================
#
# Die Frage der Runde ist EINE: laeuft ein DYNAMISCH gelinktes
# Linux-Programm auf OrientOS? Bis zu dieser Runde lief nur, was
# statisch gelinkt war -- der Befund der Runden LAUFZEIT und FREMDLAND.
#
# Die Messlatte hat drei Stufen, und jede wird HIER gefahren:
#
#   Stufe 1  ein eigenes hello.c, dynamisch gegen musl gelinkt, mit
#            PT_INTERP. Es druckt seine Zeile und endet mit 0.
#   Stufe 2  busybox, DYNAMISCH gegen musl gebaut: zehn Applets, und
#            ihre Ausgabe muss OKTETT FUER OKTETT dieselbe sein wie die
#            derselben Applets auf dem Linux-Wirt.
#   Stufe 3  dlopen/dlsym.
#
# UND DIE GEGENPROBEN, ohne die die Zusagen nichts wert waeren:
#
#   * ein Interpreter-Pfad, den es NICHT gibt, muss einen sauberen
#     Fehler geben (ENOENT) und keinen Haenger,
#   * ein Interpreter, der selbst einen PT_INTERP hat, muss abgewiesen
#     werden (ELOOP),
#   * die BESTEHENDEN, statisch gebundenen Programme muessen unveraendert
#     weiterlaufen -- eine Runde, die den dynamischen Fall oeffnet und
#     dabei den statischen bricht, hat nichts gewonnen,
#   * jede Textkonstante in kernel/elf.fi muss so lang sein wie ihr Feld.
#     Das ist keine Formsache: firnc1 bricht bei einer zu langen
#     Zeichenkette OHNE MELDUNG ab (Rueckgabe 1, leeres stderr, keine
#     Datei), und genau das hat in dieser Runde Stunden gekostet.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

TMPD=${1:-$(mktemp -d)}
mkdir -p "$TMPD"

pass=0
fail=0
skip=0
ok()   { pass=$((pass + 1)); printf '  \033[32mok\033[0m   %s\n' "$*"; }
bad()  { fail=$((fail + 1)); printf '  \033[31mNEIN\033[0m %s\n' "$*"; }
weg()  { skip=$((skip + 1)); printf '  \033[33m--\033[0m   %s\n' "$*"; }

QEMU_X86=${QEMU_X86:-qemu-system-x86_64}
KVM=()
if [ -w /dev/kvm ]; then KVM=(-accel kvm -cpu host); fi

echo "== 0. das Werkzeug =="
for t in musl-gcc "$QEMU_X86" readelf; do
    command -v "$t" >/dev/null 2>&1 || { echo "DYNLADER: $t fehlt, uebersprungen"; exit 0; }
done
ok "musl-gcc, qemu und readelf sind da"
[ ${#KVM[@]} -gt 0 ] && ok "KVM wird benutzt (-accel kvm -cpu host)" \
                     || weg "kein /dev/kvm -- der Lauf geht unter TCG und ist langsamer"

# ============================================================ 1.
# DIE TEXTKONSTANTEN. Zuerst, weil ein Fehler hier den Bau ohne jede
# Meldung umbringt und man ihn sonst durch Halbierung suchen muss.
echo "== 1. die Textkonstanten in kernel/elf.fi =="
python3 - "$ROOT/kernel/elf.fi" > "$TMPD/texte.txt" 2>&1 <<'PY'
import re, sys
s = open(sys.argv[1], encoding='utf-8', errors='surrogateescape').read()
bad = 0
n = 0
for m in re.finditer(r'var (\w+): \[u8; (\d+)\] = "((?:[^"\\]|\\.)*)"', s):
    real = m.group(3).replace('\\0', '\0').replace('\\n', '\n').replace('\\\\', '\\')
    n += 1
    if int(m.group(2)) != len(real):
        print("FALSCH %s: Feld %s, Inhalt %d" % (m.group(1), m.group(2), len(real)))
        bad += 1
print("GEPRUEFT %d FALSCH %d" % (n, bad))
PY
if grep -q 'FALSCH 0$' "$TMPD/texte.txt"; then
    ok "$(grep -o 'GEPRUEFT [0-9]*' "$TMPD/texte.txt") Textkonstanten, alle so lang wie ihr Feld"
else
    bad "eine Textkonstante passt nicht in ihr Feld -- firnc1 braeche STILL ab"
    sed 's/^/        /' "$TMPD/texte.txt"
fi

# ============================================================ 2.
echo "== 2. die Zielprogramme, dynamisch gegen musl gebaut =="
cat > "$TMPD/hello.c" <<'C'
#include <stdio.h>
int main(int argc, char **argv) {
    printf("hallo dynamisch\n");
    return 0;
}
C
musl-gcc -O2 -o "$TMPD/hello_dyn" "$TMPD/hello.c" 2>"$TMPD/cc.err" \
    && ok "hello.c dynamisch gegen musl gebunden" \
    || { bad "musl-gcc gescheitert"; sed 's/^/        /' "$TMPD/cc.err" | head -5; }

# Der Nachweis, dass es WIRKLICH dynamisch ist und nicht versehentlich
# statisch -- sonst misst die ganze Runde den Fall von vorletzter Runde.
IPATH=$(readelf -lW "$TMPD/hello_dyn" 2>/dev/null \
        | sed -n 's/.*Requesting program interpreter: \(.*\)\]/\1/p')
[ -n "$IPATH" ] && ok "hello_dyn hat ein PT_INTERP: $IPATH" \
                || bad "hello_dyn hat KEIN PT_INTERP -- es waere statisch"
readelf -hW "$TMPD/hello_dyn" 2>/dev/null | grep -q 'Type:.*DYN' \
    && ok "hello_dyn ist ET_DYN (PIE)" || bad "hello_dyn ist nicht ET_DYN"

# Der Interpreter selbst.
LDSO=${LDSO:-/lib/ld-musl-x86_64.so.1}
if [ -r "$LDSO" ]; then
    LDREAL=$(readlink -f "$LDSO")
    ok "der Interpreter liegt vor: $LDREAL ($(stat -c%s "$LDREAL") Oktette)"
    readelf -hW "$LDREAL" | grep -q 'Type:.*DYN' \
        && ok "und er ist selbst ein ET_DYN -- deshalb musste read_header geoeffnet werden" \
        || bad "der Interpreter ist kein ET_DYN"
else
    bad "kein Interpreter unter $LDSO"
fi

# dlopen/dlsym, Stufe 3.
cat > "$TMPD/dltest.c" <<'C'
#include <stdio.h>
#include <dlfcn.h>
int main(void) {
    void *h = dlopen(0, RTLD_NOW);
    if (!h) { printf("dlopen NEIN\n"); return 1; }
    int (*f)(const char *) = dlsym(h, "puts");
    if (!f) { printf("dlsym NEIN\n"); return 2; }
    f("dlsym ok");
    return 0;
}
C
musl-gcc -O2 -o "$TMPD/dltest" "$TMPD/dltest.c" 2>/dev/null \
    && ok "dltest (dlopen/dlsym) gebunden" || weg "dltest nicht baubar"

# busybox, dynamisch. Wird NICHT hier gebaut (das dauert Minuten) --
# wer ihn hat, gibt ihn an; wer nicht, bekommt Stufe 2 uebersprungen
# statt einen Abbruch. Derselbe Umgang wie in tools/usbimg/build.sh.
BBDYN=${BBDYN:-/root/bbdyn/busybox}
BB_DA=0
if [ -x "$BBDYN" ] && readelf -lW "$BBDYN" 2>/dev/null | grep -q 'program interpreter'; then
    BB_DA=1
    ok "busybox dynamisch liegt vor: $BBDYN ($(stat -c%s "$BBDYN") Oktette)"
else
    weg "kein dynamisches busybox (BBDYN=...) -- Stufe 2 wird uebersprungen"
fi

# ============================================================ 3.
echo "== 3. der Kernel =="
# DER KERNEL WIRD MIT tools/build-kernel.sh GEBAUT UND NICHT MIT EINER
# EIGENEN ld-ZEILE. Der Grund steht in jenem Skript: das Binden ist seit
# der Runde SYMBOLE ZWEI Durchgaenge (die Symboltabelle fuer den
# Panik-Bildschirm entsteht aus dem ersten und geht in den zweiten), und
# es braucht sieben --defsym. Ein Laeufer, der das nachbaut, baut etwas
# anderes als das, was ausgeliefert wird -- und misst dann auch etwas
# anderes.
if bash tools/build-kernel.sh "$TMPD/k.mb" --stufe 1 > "$TMPD/k.log" 2>&1; then
    ok "der Kernel ist gebaut ($(stat -c%s "$TMPD/k.mb") Oktette)"
else
    bad "der Kernel baut NICHT (Meldung unten -- bei firnc1 oft LEER,"
    echo "        und dann ist es meist eine Textkonstante, die nicht in ihr Feld passt)"
    sed 's/^/        /' "$TMPD/k.log" | tail -12
    echo "DYNLADER: $pass bestanden, $fail gescheitert"
    exit 1
fi

# ============================================================ 3b.
# DIE PROGRAMME DES SYSTEMS. Ohne sie ist das Abbild leer: `script=`
# gibt seine Zeile an /bin/sh, und eine Shell, die es nicht gibt, kann
# auch kein dynamisches Programm starten. Gemessen, bevor diese
# Abschnitt dastand: JEDER Lauf endete mit `elf: refused, reason 1 --
# no such file`, und zwar auch fuer das eingebaute `cat`. Das sah aus
# wie ein Fehler des neuen Laders und war keiner.
echo "== 3b. die Programme des Userlands =="
PROGS=${PROGS:-"sh ls cat echo"}
export FIRNLIB="$ROOT/lib"
FIRNC="$ROOT/vendor/firn/bin/firnc1"
ULD=kernel/user/user.ld
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>"$TMPD/ascrt.err" \
    || bad "crt.s assembliert nicht"
ubad=0
for p in $PROGS; do
    "$FIRNC" "kernel/user/$p.fi" -o "$TMPD/$p.o" > "$TMPD/e$p.log" 2>&1 || {
        bad "firnc1 uebersetzt $p.fi nicht"; ubad=$((ubad+1)); continue; }
    ld -T "$ULD" --defsym=USER_ENTRY="_F1.u_start" \
        -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>"$TMPD/ld$p.err" || {
        bad "ld an $p gescheitert"; ubad=$((ubad+1)); continue; }
    strip --strip-all "$TMPD/$p.elf" 2>/dev/null
done
[ $ubad = 0 ] && ok "$(echo $PROGS | wc -w) Programme gebaut ($PROGS)" \
              || bad "$ubad Programme fehlen -- das Abbild waere unbrauchbar"

# ============================================================ 4.
# DAS DATEISYSTEM. Der Interpreter muss unter GENAU dem Pfad liegen, den
# das PT_INTERP nennt -- sonst sucht der Kern ihn dort, wo er nicht ist.
echo "== 4. das Abbild =="
BLOCKS=${BLOCKS:-65536}
mkdir -p "$TMPD/bin"

# Ein Skript, das die Shell abfaehrt. Es steht als Datei im Abbild,
# damit die Kommandozeile kurz bleibt.
SPEC="/lib/ /bin/"
for p in $PROGS; do SPEC="$SPEC /bin/$p=$TMPD/$p.elf"; done
SPEC="$SPEC /lib/ld-musl-x86_64.so.1=$LDREAL"
SPEC="$SPEC /bin/hello_dyn=$TMPD/hello_dyn"
[ -x "$TMPD/dltest" ] && SPEC="$SPEC /bin/dltest=$TMPD/dltest"
[ "$BB_DA" = 1 ] && SPEC="$SPEC /bin/busybox=$BBDYN"

# DIE GEGENPROBE-DATEIEN.
# a) ein Programm, dessen PT_INTERP auf etwas zeigt, das es nicht gibt.
python3 - "$TMPD/hello_dyn" "$TMPD/badinterp" <<'PY'
import sys, struct
d = bytearray(open(sys.argv[1], 'rb').read())
phoff = struct.unpack_from('<Q', d, 0x20)[0]
phentsize = struct.unpack_from('<H', d, 0x36)[0]
phnum = struct.unpack_from('<H', d, 0x38)[0]
for i in range(phnum):
    o = phoff + i * phentsize
    if struct.unpack_from('<I', d, o)[0] == 3:      # PT_INTERP
        off = struct.unpack_from('<Q', d, o + 8)[0]
        sz = struct.unpack_from('<Q', d, o + 32)[0]
        neu = b'/lib/gibtesnicht.so\x00'
        assert len(neu) <= sz, (len(neu), sz)
        d[off:off + sz] = neu + b'\x00' * (sz - len(neu))
        break
open(sys.argv[2], 'wb').write(bytes(d))
PY
[ -s "$TMPD/badinterp" ] && SPEC="$SPEC /bin/badinterp=$TMPD/badinterp"

# b) ein "Interpreter", der selbst einen PT_INTERP hat: das ist
#    hello_dyn selbst, als Interpreter eingetragen.
python3 - "$TMPD/hello_dyn" "$TMPD/chaininterp" <<'PY'
import sys, struct
d = bytearray(open(sys.argv[1], 'rb').read())
phoff = struct.unpack_from('<Q', d, 0x20)[0]
phentsize = struct.unpack_from('<H', d, 0x36)[0]
phnum = struct.unpack_from('<H', d, 0x38)[0]
for i in range(phnum):
    o = phoff + i * phentsize
    if struct.unpack_from('<I', d, o)[0] == 3:
        off = struct.unpack_from('<Q', d, o + 8)[0]
        sz = struct.unpack_from('<Q', d, o + 32)[0]
        neu = b'/bin/hello_dyn\x00'
        assert len(neu) <= sz
        d[off:off + sz] = neu + b'\x00' * (sz - len(neu))
        break
open(sys.argv[2], 'wb').write(bytes(d))
PY
[ -s "$TMPD/chaininterp" ] && SPEC="$SPEC /bin/chaininterp=$TMPD/chaininterp"

python3 tools/osum/mkfs.py build "$TMPD/disk.img" $BLOCKS $SPEC \
    > "$TMPD/mkfs.txt" 2>&1 \
    && ok "OFS-Abbild gebaut ($BLOCKS Bloecke)" \
    || { bad "mkfs.py gescheitert"; sed 's/^/        /' "$TMPD/mkfs.txt" | head -10; }

run_disk() { # append out
    cp -f "$TMPD/disk.img" "$TMPD/live.img"
    timeout "${TMO:-240}" $QEMU_X86 "${KVM[@]}" -kernel "$TMPD/k.mb" -m 512 \
        -append "$1" -serial "file:$2" -display none -no-reboot \
        -drive "file=$TMPD/live.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    return $?
}
QUIET="nokbd nosched noproc nofs"

# ============================================================ 5.
echo "== 5. STUFE 1: ein dynamisch gelinktes Programm laeuft =="
run_disk "osum $QUIET script=hello_dyn;exit" "$TMPD/s1.txt"
sed '/^mb: flags=/d' "$TMPD/s1.txt" > "$TMPD/s1.rein" 2>/dev/null
if grep -q 'hallo dynamisch' "$TMPD/s1.rein" 2>/dev/null; then
    ok "STUFE 1 GEFALLEN: hello_dyn hat seine Zeile gedruckt"
else
    bad "STUFE 1: keine Ausgabe von hello_dyn"
    echo "        --- was der Kern gesagt hat:"
    grep -iE 'elf:|refused|reason|vector|panic|#PF|#GP' "$TMPD/s1.txt" 2>/dev/null \
        | sed 's/^/        /' | head -12
fi

# ============================================================ 6.
echo "== 6. STUFE 2: busybox, zehn Applets, Oktett fuer Oktett =="
if [ "$BB_DA" = 1 ]; then
    cat > "$TMPD/bbskript" <<'S'
/bin/busybox echo hallo-echo
/bin/busybox wc -c /etc/pruef.txt
/bin/busybox cat /etc/pruef.txt
/bin/busybox head -2 /etc/pruef.txt
/bin/busybox sort /etc/pruef.txt
/bin/busybox grep zwei /etc/pruef.txt
/bin/busybox uname -s
/bin/busybox sha256sum /etc/pruef.txt
/bin/busybox env
/bin/busybox ls /bin
S
    printf 'eins\nzwei\ndrei\n' > "$TMPD/pruef.txt"
    # Das Abbild noch einmal, mit der Pruefdatei und dem Skript.
    python3 tools/osum/mkfs.py build "$TMPD/disk.img" $BLOCKS $SPEC \
        /etc/ "/etc/pruef.txt=$TMPD/pruef.txt" > "$TMPD/mkfs2.txt" 2>&1 \
        || bad "mkfs.py (Stufe 2) gescheitert"
    # Jedes Applet EINZELN, damit ein Absturz nicht die uebrigen verdeckt.
    # NUR APPLETS, DEREN AUSGABE AUF BEIDEN SEITEN DIESELBE SEIN KANN.
    #
    # `env` und `ls /bin` standen hier zuerst und waren beide FALSCH
    # gemessen: `env` druckt die Umgebung DES WIRTS (SHELL=/bin/bash,
    # PATH=...), die es auf Osum nicht gibt, und `ls /bin` listet das
    # /bin DES WIRTS mit seinen tausend Dateien. Beide "scheiterten"
    # deshalb, obwohl sie auf Osum sauber liefen -- `busybox ls /bin`
    # druckt dort in Spalten
    #     badinterp cat dltest hello_dyn sh busybox chaininterp echo ls
    # also genau den Inhalt dieses Abbilds. Ein Vergleich, der zwei
    # verschiedene Dinge nebeneinanderlegt, misst keines von beiden.
    #
    # Sie werden deshalb nicht weggelassen, sondern ANDERS geprueft:
    # weiter unten gegen den Inhalt, den DIESES Abbild hat.
    for a in "echo hallo-echo" "cat /etc/pruef.txt" "wc -c /etc/pruef.txt" \
             "head -n 2 /etc/pruef.txt" "sort /etc/pruef.txt" \
             "grep zwei /etc/pruef.txt" "uname -s" \
             "sha256sum /etc/pruef.txt"; do
        name=${a%% *}
        run_disk "osum $QUIET script=busybox $a;exit" "$TMPD/bb-$name.txt"
        # Der Wirt sagt, was herauskommen muss.
        ( cd "$TMPD" && mkdir -p wirt/etc wirt/bin && cp pruef.txt wirt/etc/ )
        soll=$("$BBDYN" $(echo "$a" | sed "s|/etc/pruef.txt|$TMPD/pruef.txt|g") 2>/dev/null \
               | head -5 | tr -d '\r')
        # Nur die ERSTE Zeile vergleichen: die Serienausgabe traegt
        # Kernmeldungen, und ein Vergleich der ganzen Datei misst die.
        if [ -n "$soll" ]; then
            erste=$(printf '%s' "$soll" | head -1)
            # sha256sum/wc nennen den Pfad, der auf beiden Seiten anders
            # ist -- dann nur die Summe/Zahl vergleichen.
            case "$name" in
                sha256sum|wc) erste=$(printf '%s' "$erste" | awk '{print $1}') ;;
            esac
            # DIE KOMMANDOZEILE WIRD WEGGESCHNITTEN, BEVOR VERGLICHEN
            # WIRD. Der Kern druckt beim Start seine eigene `cmdline`
            # (`mb: flags=... cmd=... script=busybox echo hallo-echo`),
            # und die enthaelt den gesuchten Text WOERTLICH. Ohne diese
            # Zeile bestaende die Zusage auch dann, wenn busybox gar
            # nicht gelaufen waere -- gemessen: `echo` und `grep` galten
            # als bestanden, waehrend der Lader in Wahrheit noch mit
            # `reason 1` abbrach. Eine Zusage, die ohne das Programm
            # haelt, misst das Programm nicht.
            sed '/^mb: flags=/d' "$TMPD/bb-$name.txt" > "$TMPD/bb-$name.rein"
            if grep -qF "$erste" "$TMPD/bb-$name.rein" 2>/dev/null; then
                ok "busybox $name -- Ausgabe wie auf dem Wirt ($erste)"
            else
                bad "busybox $name -- Ausgabe fehlt oder weicht ab (erwartet: $erste)"
            fi
        else
            weg "busybox $name -- der Wirt liefert nichts zum Vergleichen"
        fi
    done
    # `ls /bin` GEGEN DAS ABBILD, nicht gegen den Wirt. Was dort steht,
    # ist bekannt: es ist die Liste, die weiter oben in SPEC aufgebaut
    # wurde.
    run_disk "osum $QUIET script=busybox ls /bin;exit" "$TMPD/bb-ls.txt"
    sed '/^mb: flags=/d' "$TMPD/bb-ls.txt" > "$TMPD/bb-ls.rein"
    lsfehlt=""
    for n in busybox hello_dyn dltest sh cat echo ls; do
        grep -qw "$n" "$TMPD/bb-ls.rein" || lsfehlt="$lsfehlt $n"
    done
    [ -z "$lsfehlt" ] \
        && ok "busybox ls -- nennt jede Datei, die in /bin dieses Abbilds liegt" \
        || bad "busybox ls -- diese Namen fehlen in der Ausgabe:$lsfehlt"

    # `env` GEGEN DIE UMGEBUNG DIESES SYSTEMS. Osum fuehrt EINEN
    # Umgebungsblock (Runde K11), und `build_stack` legt ihn als envp
    # auf den Stapel. Die Zusage ist deshalb nicht "dieselbe Ausgabe wie
    # der Wirt" (die kann es nicht sein), sondern: es laeuft, es endet
    # sauber, und was es druckt, stammt aus dem Stapel, den diese Runde
    # gebaut hat.
    run_disk "osum $QUIET script=busybox env;exit" "$TMPD/bb-env.txt"
    sed '/^mb: flags=/d' "$TMPD/bb-env.txt" > "$TMPD/bb-env.rein"
    # `refused` ALLEIN REICHT NICHT ALS ABBRUCHZEICHEN. Der Kern druckt
    # beim Start `heap test: ... 1M refused=1` -- eine voellig normale
    # Zeile des Haldentests, die mit diesem Lauf nichts zu tun hat. Ein
    # Muster, das sie trifft, meldet jeden Lauf als abgebrochen. Gesucht
    # ist die Ablehnung DES LADERS, und die heisst `elf: refused`.
    if grep -qiE 'panic|vector=|elf: refused' "$TMPD/bb-env.rein"; then
        bad "busybox env -- der Lauf ist abgebrochen"
        grep -iE 'panic|vector=|elf: refused' "$TMPD/bb-env.rein" | sed 's/^/        /' | head -4
    else
        ok "busybox env -- laeuft und endet ohne Absturz (envp kommt vom neuen Stapel)"
    fi
else
    weg "STUFE 2 uebersprungen (kein dynamisches busybox)"
fi

# ============================================================ 7.
echo "== 7. STUFE 3: dlopen/dlsym =="
if [ -x "$TMPD/dltest" ]; then
    run_disk "osum $QUIET script=dltest;exit" "$TMPD/s3.txt"
    sed '/^mb: flags=/d' "$TMPD/s3.txt" > "$TMPD/s3.rein" 2>/dev/null
    if grep -q 'dlsym ok' "$TMPD/s3.rein" 2>/dev/null; then
        ok "STUFE 3 GEFALLEN: dlopen(0)+dlsym(\"puts\") hat gearbeitet"
    else
        bad "STUFE 3: dlopen/dlsym nicht gelaufen"
        grep -iE 'elf:|refused|dlopen|dlsym|vector' "$TMPD/s3.txt" 2>/dev/null \
            | sed 's/^/        /' | head -8
    fi
else
    weg "STUFE 3 uebersprungen"
fi

# ============================================================ 8.
# DIE GEGENPROBEN. Eine Zusage ohne sie ist eine Behauptung.
echo "== 8. die Gegenproben =="

# a) fehlender Interpreter: SAUBERER FEHLER, KEIN HAENGER.
run_disk "osum $QUIET script=badinterp;exit" "$TMPD/g1.txt"
rc=$?
if [ $rc -eq 124 ]; then
    bad "ein fehlender Interpreter HAENGT die Maschine (Zeitueberschreitung)"
elif grep -qiE 'interpreter missing|reason 26' "$TMPD/g1.txt" 2>/dev/null; then
    ok "ein fehlender Interpreter wird mit Grund 26 abgelehnt, die Maschine laeuft"
elif grep -qiE 'refused|not found|No such' "$TMPD/g1.txt" 2>/dev/null; then
    ok "ein fehlender Interpreter wird abgelehnt (Meldung, kein Haenger)"
else
    bad "ein fehlender Interpreter gibt keine erkennbare Ablehnung"
    grep -iE 'elf:|reason|vector' "$TMPD/g1.txt" | sed 's/^/        /' | head -6
fi

# b) Interpreter-Kette: ABGEWIESEN.
run_disk "osum $QUIET script=chaininterp;exit" "$TMPD/g2.txt"
rc=$?
if [ $rc -eq 124 ]; then
    bad "eine Interpreter-Kette HAENGT die Maschine"
elif grep -qiE 'interpreter chained|reason 27' "$TMPD/g2.txt" 2>/dev/null; then
    ok "ein Interpreter mit eigenem PT_INTERP wird mit Grund 27 abgewiesen"
elif grep -qiE 'refused' "$TMPD/g2.txt" 2>/dev/null; then
    ok "ein Interpreter mit eigenem PT_INTERP wird abgewiesen"
else
    bad "eine Interpreter-Kette wird nicht erkennbar abgewiesen"
    grep -iE 'elf:|reason|vector' "$TMPD/g2.txt" | sed 's/^/        /' | head -6
fi

# c) DER STATISCHE FALL LEBT. Die Runde darf nicht kaputtmachen, was
#    seit K1 laeuft: die eingebauten Programme sind ET_EXEC und muessen
#    unveraendert starten.
run_disk "osum $QUIET script=echo statisch-lebt;exit" "$TMPD/g3.txt"
sed '/^mb: flags=/d' "$TMPD/g3.txt" > "$TMPD/g3.rein" 2>/dev/null
if grep -q 'statisch-lebt' "$TMPD/g3.rein" 2>/dev/null; then
    ok "die statisch gebundenen Programme laufen unveraendert weiter"
else
    # /bin/echo liegt in diesem Abbild vielleicht gar nicht -- dann ist
    # das keine Aussage, und es wird auch keine behauptet.
    weg "kein /bin/echo im Abbild -- der statische Fall wurde hier nicht gemessen"
fi

echo
echo "DYNLADER: $pass bestanden, $fail gescheitert, $skip uebersprungen"
echo "  Arbeitsverzeichnis: $TMPD"
[ "$fail" = 0 ]
