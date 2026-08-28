#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/unix/run.sh -- WAS JEDES UNIX-PROGRAMM STILLSCHWEIGEND VORAUSSETZT.
#
# Runde K4 hat die POSIX-Schicht gelegt, K6 ein Userland darauf gebaut --
# und trotzdem konnte man in diesem System einen Prozess nicht ordentlich
# unterbrechen, es gab kein Terminal, keine Uhr und keinen Zufall. Ohne
# die vier bleibt jedes portierte Programm ein Krueppel: es kann nicht auf
# STRG-C hoeren, es kann seinen Bildschirm nicht ausmessen, es kann nicht
# sagen, wie spaet es ist, und es kann keine Folgenummer waehlen, die
# niemand erraet.
#
# WAS HIER GEMESSEN WIRD, und alles davon IM LAUFENDEN KERNEL. Ein
# Aufruf, der nicht abstuerzt, ist keine Zusage:
#
#   1. DIE NUMMERN sind Linux' Nummern, und die Karte in `kernel/sys.fi`
#      sagt, welchen Bereich diese Runde belegt -- drei Runden arbeiten
#      gleichzeitig an diesem Repo.
#   2. SIGNALE. Ein Programm faengt SIGUSR1 ab und ZAEHLT MIT. Ein
#      blockiertes Signal geht nicht verloren, es wartet und kommt beim
#      Freigeben. Ein ueberhoertes kommt nie. SIGKILL und SIGSTOP lassen
#      sich nicht abfangen. Ein Kind stirbt an SIGTERM mit 143, eines an
#      SIGKILL mit 137, und der Elternteil bekommt SIGCHLD.
#   3. AUSNAHMEN SIND SIGNALE. Ein Zugriff auf die Null wird zu SIGSEGV
#      und landet in einer Routine in Ring 3, die von dort einen
#      Systemaufruf macht (Beendigungscode 51 = 40 + 11). Ohne Routine
#      bleibt der Beendigungscode der von Runde 62: 128 + Vektor.
#   4. ANHALTEN UND FORTSETZEN. Ein Prozess wird angehalten, sein Zustand
#      ist S_STOP, SEINE RECHENZEIT STEHT STILL, und nach SIGCONT laeuft
#      sie weiter. Ein schlafender Prozess taete das nicht.
#   5. TERMINAL. Zeilendisziplin, Echo an und aus, roher Modus,
#      Fenstergroesse (mit SIGWINCH), und ein Pseudoterminalpaar in beide
#      Richtungen -- mit dem Echo, das ein Terminal macht.
#   6. STRG-C BEENDET WIRKLICH. Ein Vordergrundprozess in eigener
#      Prozessgruppe, ein Oktett 3 auf der Steuerseite, und der Prozess
#      ist tot mit 130 = 128 + SIGINT. Dazu STRG-Z (angehalten) und ein
#      Hintergrundleser (SIGTTIN, angehalten).
#   7. DIE MONOTONE UHR LAEUFT NIE RUECKWAERTS -- ueber zwanzigtausend
#      Messungen geprueft, nicht ueber zwei.
#   8. DER ZUFALL besteht die Verteilung ueber 256 Faecher (Chi-Quadrat)
#      und ist zwischen zwei Neustarts VERSCHIEDEN.
#
# UND DIE GEGENPROBEN, ohne die in diesem Projekt nichts zaehlt:
#
#   `nosig`      Es wird nichts zugestellt. `kill` sagt weiter 0, das Bit
#                wird gesetzt -- der Zaehler des Programms MUSS bei null
#                bleiben. Ein Test, der auch dann zaehlt, hat nie Signale
#                gemessen.
#   `fixedrand`  Der Generator gibt fuer immer dasselbe Oktett. Die
#                statistische Pruefung MUSS durchfallen. (Und dabei faellt
#                ein zweites auf: der Bit-Test allein faellt NICHT durch,
#                weil 0x5A vier von acht Bits gesetzt hat. Eine Pruefung
#                allein reicht nicht -- das Chi-Quadrat ist die, die es
#                merkt.)
#   drei Laeufe  Derselbe Kernel, dreimal gestartet, drei verschiedene
#                Zufallssaaten. Ein Generator, der bei jedem Start
#                dasselbe liefert, ist kein Generator.
#
# Gemessen wie in den Runden 59 bis K6: QEMU je Fall, mit Zeitlimit,
# serielle Ausgabe gegen Erwartungen, Beendigungscode aus `isa-debug-exit`
# (21 = der Kernel hat sich selbst beendet, 63 = eine Ausnahme).
#
# Aufruf:  bash tools/unix/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL

export FIRNLIB="$(pwd)/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
FC1=${FIRNC1:-vendor/firn/bin/firnc1}
ULD=kernel/user/user.ld
PROGS="sh ls cat echo unix"
BLOCKS=4096

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

value_of() { # file name
    grep -a -m1 "^unix: $2 = " "$1" | sed 's/.* = //'
}

say() { # file name expected description
    local got
    got=$(value_of "$1" "$2")
    if [ -z "$got" ]; then bad "$4 -- keine Zeile 'unix: $2 ='"; return; fi
    if [ "$got" = "$3" ]; then ok "$4 ($2 = $got)"
    else bad "$4 -- $2 = $got, erwartet $3"; fi
}

between() { # file name lo hi description
    local got
    got=$(value_of "$1" "$2")
    if [ -z "$got" ]; then bad "$5 -- keine Zeile 'unix: $2 ='"; return; fi
    if [ "$got" -ge "$3" ] && [ "$got" -le "$4" ]; then ok "$5 ($2 = $got)"
    else bad "$5 -- $2 = $got, erwartet $3..$4"; fi
}

number_in() { # file name
    grep -aE "^const $2: u64 = [0-9]+" "$1" | head -1 \
        | sed -E 's/^const [A-Za-z0-9_]+: u64 = ([0-9]+).*/\1/'
}

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "vendor/firn/fetch-firnc.sh failed"; exit 1; }
[ -x "$FIRNC" ] || { echo "firnc0 fehlt: $FIRNC"; exit 1; }
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "UNIX: skipped, qemu-system-x86_64 ist nicht da"
    exit 0
fi

# ------------------------------------------------------------- Abschnitt 1

echo "== 1. die Nummern, und die Karte, wer welchen Bereich hat =="
check() { # name expected
    local got
    got=$(number_in kernel/sys.fi "SYS_$1")
    if [ "$got" = "$2" ]; then ok "SYS_$1 = $2 (Linux' Nummer)"
    else bad "SYS_$1 = ${got:-fehlt}, Linux sagt $2"; fi
}
check RT_SIGACTION 13
check RT_SIGPROCMASK 14
check RT_SIGRETURN 15
check IOCTL 16
check PAUSE 34
check ALARM 37
check KILL 62
check GETTIMEOFDAY 96
check SETPGID 109
check GETPGRP 111
check SETSID 112
check GETPGID 121
check RT_SIGPENDING 127
check TIME 201
check CLOCK_GETTIME 228
check GETRANDOM 318
# Was Osum selbst erfunden hat, liegt im Hunderterblock DIESER Runde --
# 1000..1099 gehoert den Runden K1 und K6, 1200 aufwaerts den Runden K7
# und K8. Genau daran ist an diesem Repo schon dreimal ein Zusammenstoss
# entstanden.
own=$(grep -aoE "^const SYS_OSUM_(PTY|TTYINFO|SIGINFO): u64 = [0-9]+" kernel/sys.fi \
    | sed -E 's/.*= ([0-9]+).*/\1/' | sort -n)
lo=$(echo "$own" | head -1); hi=$(echo "$own" | tail -1)
num "die kleinste Nummer, die Runde K9 selbst erfunden hat" "${lo:-0}" ge 1100
num "und die groesste" "${hi:-0}" le 1199
grep -q '1100\.\.1199   RUNDE K9' kernel/sys.fi \
    && ok "die Bereichskarte steht oben in sys.fi" \
    || bad "die Bereichskarte fehlt in sys.fi"
# Keine Nummer von K9 liegt im Socket-Block, den Runde K8 braucht.
clash=0
for n in 13 14 15 16 34 37 56 62 96 109 111 112 121 127 201 202 228 229 230 234 318; do
    if [ "$n" -ge 41 ] && [ "$n" -le 55 ]; then clash=$((clash+1)); fi
done
num "Nummern von K9, die im Socket-Block 41..55 von K8 liegen" "$clash" eq 0

# ------------------------------------------------------------- Abschnitt 2

echo "== 2. bauen: der Kernel, das Userland und das messende Programm =="
for f in boot isr switch smp hv; do
    as --64 -o "$TMPD/$f.o" "kernel/arch/x86_64/$f.s" 2>"$TMPD/as.err" \
        || { bad "$f.s laesst sich nicht assemblieren"; sed 's/^/        /' "$TMPD/as.err" | head -5; }
done
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>"$TMPD/ascrt.err" \
    && ok "crt.s assembliert (mit den Behandlungsroutinen von Runde K9)" \
    || { bad "crt.s"; sed 's/^/        /' "$TMPD/ascrt.err" | head -5; }
# Die Routine MUSS in crt.s liegen: eine Behandlungsroutine ist eine
# ADRESSE, und Stufe 0 von Firn kann die Adresse einer eigenen Funktion
# nicht nennen. Ohne diese Zeilen koennte kein Programm `sigaction` auch
# nur aufrufen.
nm "$TMPD/crt.o" | grep -q 'T osum_sighandler' \
    && ok "crt.s stellt osum_sighandler bereit -- die Adresse, die Firn nicht nennen kann" \
    || bad "osum_sighandler fehlt in crt.o"

build_stage() { # 0 = firnc0, 1 = firnc1
    local s=$1 cc
    if [ "$s" = 0 ]; then cc="$FIRNC"; else cc="$FC1"; fi
    [ -x "$cc" ] || return 1
    "$cc" kernel/kmain.fi -o "$TMPD/k$s.o" >"$TMPD/e$s" 2>&1 \
        || { bad "firnc$s uebersetzt den Kernel nicht"; sed 's/^/        /' "$TMPD/e$s" | head -8; return 1; }
    "$cc" kernel/uprog.fi -o "$TMPD/u$s.o" >>"$TMPD/e$s" 2>&1 \
        || { bad "firnc$s uebersetzt uprog.fi nicht"; return 1; }
    ld -n -T kernel/kernel.ld \
        --defsym=KERNEL_MAIN="_F$s.kernel_main" \
        --defsym=KERNEL_TRAP="_F$s.trap__entry" \
        --defsym=KERNEL_SYSCALL="_F$s.sys__entry" \
        --defsym=KERNEL_TASK_MAIN="_F$s.tasks__main" \
        --defsym=KERNEL_USER_START="_F$s.proc__user_start" \
        --defsym=KERNEL_AP_MAIN="_F$s.smp__ap_main" \
        --defsym=USER_MAIN="_F$s.u_enter" \
        -o "$TMPD/k$s.elf" "$TMPD/boot.o" "$TMPD/isr.o" "$TMPD/switch.o" \
        "$TMPD/smp.o" "$TMPD/hv.o" "$TMPD/k$s.o" "$TMPD/u$s.o" 2>"$TMPD/ld$s.err" \
        || { bad "firnc$s: ld am Kernel gescheitert"; grep -v 'GNU-stack\|RWX\|deprecated' "$TMPD/ld$s.err" | sed 's/^/        /' | head -5; return 1; }
    objcopy -O elf32-i386 "$TMPD/k$s.elf" "$TMPD/k$s.mb" 2>/dev/null
    ok "firnc$s: der Kernel ist gebunden und ein Multiboot-Abbild"
    local p
    for p in $PROGS; do
        "$cc" "kernel/user/$p.fi" -o "$TMPD/$p$s.o" >"$TMPD/e$p$s" 2>&1 \
            || { bad "firnc$s uebersetzt $p.fi nicht"; sed 's/^/        /' "$TMPD/e$p$s" | head -6; return 1; }
        ld -T "$ULD" --defsym=USER_ENTRY="_F$s.u_start" \
            -o "$TMPD/$p$s.elf" "$TMPD/crt.o" "$TMPD/$p$s.o" 2>"$TMPD/ldu.err" \
            || { bad "firnc$s: ld an $p gescheitert"; grep -v 'GNU-stack\|RWX' "$TMPD/ldu.err" | sed 's/^/        /' | head -5; return 1; }
        strip --strip-all "$TMPD/$p$s.elf"
    done
    ok "firnc$s: $(echo $PROGS | wc -w) Programme als eigenstaendige ELF64-Dateien"
    return 0
}
build_stage 0 || { echo "UNIX: $pass passed, $fail failed"; exit 1; }

u=$(nm -u "$TMPD/unix0.elf" 2>/dev/null | awk '{print $NF}' | sed '/^$/d')
[ -z "$u" ] && ok "/bin/unix hat kein undefiniertes Symbol" \
            || bad "/bin/unix hat undefinierte Symbole: $u"

SPEC="/bin/"
for p in $PROGS; do SPEC="$SPEC /bin/$p=$TMPD/${p}0.elf"; done
python3 tools/osum/mkfs.py build "$TMPD/disk.img" $BLOCKS $SPEC > "$TMPD/mkfs.txt" 2>&1 \
    && ok "mkfs.py hat ein OFS-Abbild von $BLOCKS Bloecken gebaut" \
    || { bad "mkfs.py gescheitert"; sed 's/^/        /' "$TMPD/mkfs.txt"; }

run_disk() { # image append out
    cp "$TMPD/disk.img" "$TMPD/live.img"
    timeout 300 $QEMU_X86 -kernel "$1" -m 128 -append "$2" \
        -serial "file:$3" -display none -no-reboot \
        -drive "file=$TMPD/live.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    return $?
}

QUIET="nokbd nosched noproc nofs noring3"

# ------------------------------------------------------------- Abschnitt 3

echo "== 3. der Lauf: achtundfuenfzig Messungen aus Ring 3 =="
run_disk "$TMPD/k0.mb" "osum unix $QUIET script=unix;exit" "$TMPD/run.txt"
rc=$?
F="$TMPD/run.txt"
[ "$rc" -eq 21 ] && ok "der Kernel hat sich selbst beendet (exit 21)" \
                 || { bad "QEMU-Beendigungscode $rc, erwartet 21"; tail -8 "$F" | tr -d '\000' | sed 's/^/        /'; }

echo "   -- Signale: abfangen, blockieren, ueberhoeren"
say "$F" "sigact" 0 "sigaction nimmt eine Routine an"
say "$F" "caught" 1 "ein Signal an sich selbst landet in der Routine"
say "$F" "count" 6 "sechs Signale, sechsmal gezaehlt"
say "$F" "last" 10 "und die Routine bekam die richtige Nummer (SIGUSR1)"
say "$F" "blocked ok" 0 "sigprocmask nimmt eine Maske an"
say "$F" "pending" 1 "ein blockiertes Signal WARTET -- es geht nicht verloren"
say "$F" "after unblock" 1 "und kommt in dem Augenblick an, in dem es freigegeben wird"
say "$F" "ignore" 0 "ein ueberhoertes Signal kommt nie an"

echo "   -- und jede Art, falsch zu liegen"
say "$F" "act kill" -22 "SIGKILL laesst sich nicht abfangen: -EINVAL"
say "$F" "act zero" -22 "Signal 0 gibt es nicht: -EINVAL"
say "$F" "act big" -22 "Signal 64 gibt es nicht: -EINVAL"
say "$F" "kill srch" -3 "ein Prozess, den es nicht gibt: -ESRCH"
say "$F" "kill probe" 0 "kill(pid, 0) schickt nichts und sagt, dass es ihn gibt"

echo "   -- das Standardverhalten, und SIGCHLD"
say "$F" "term code" 143 "ein Kind stirbt an SIGTERM mit 128 + 15"
say "$F" "kill code" 137 "SIGKILL laesst sich auch mit Routine nicht abfangen: 128 + 9"
say "$F" "chld" 1 "der Elternteil bekommt SIGCHLD, wenn ein Kind endet"

echo "   -- anhalten und fortsetzen"
say "$F" "stop state" 7 "SIGSTOP macht S_STOP aus dem Prozess"
num "angehaltene Prozesse, die der Kern zaehlt" "$(value_of "$F" 'stopped seen')" ge 1
say "$F" "stop frozen" 1 "und SEINE RECHENZEIT STEHT STILL -- ein Schlaefer taete das nicht"
say "$F" "cont state" 1 "SIGCONT holt ihn zurueck"
say "$F" "cont moves" 1 "und die Rechenzeit laeuft weiter"

echo "   -- eine Ausnahme des Prozessors ist ein Signal"
say "$F" "segv caught" 51 "ein Zugriff auf die Null wird SIGSEGV und landet in Ring 3 (40 + 11)"
say "$F" "segv code" 142 "ohne Routine bleibt der Code von Runde 62: 128 + Vektor 14"
say "$F" "fpe caught" 48 "geteilt durch null wird SIGFPE (40 + 8)"

echo "   -- das Terminal"
say "$F" "tcgets" 0 "ioctl(TCGETS) beantwortet die Zeilendisziplin"
say "$F" "canon" 1 "die Konsole ist kanonisch und hoert auf Steuerzeichen"
say "$F" "echo off" 0 "ihr Echo ist aus (kbd.fi und die Shell schreiben schon selbst)"
say "$F" "echo on" 1 "und der Schalter dafuer wirkt"
say "$F" "rows" 24 "die Fenstergroesse hat Zeilen"
say "$F" "cols" 80 "und Spalten"
say "$F" "winch" 1 "wer sie aendert, schickt der Vordergrundgruppe SIGWINCH"
say "$F" "winsize" 1 "und die neue Groesse kommt zurueck"
say "$F" "notty" -25 "was kein Terminal ist, antwortet -ENOTTY"

echo "   -- das Pseudoterminal"
say "$F" "pty" 0 "ein Paar aus Steuer- und Nutzerseite"
say "$F" "pty to slave" 6 "was auf der Steuerseite hineingeht, kommt auf der Nutzerseite heraus"
say "$F" "pty echo" 7 "und das Terminal echot es zurueck (mit dem Wagenruecklauf von ONLCR)"
say "$F" "pty to master" 6 "und in der anderen Richtung ebenso"
say "$F" "pty raw" 1 "im rohen Modus kommt ein einzelnes Zeichen ohne Zeilenende durch"
say "$F" "pty ctlc" 1 "ein Oktett 3 auf der Steuerseite ist ein SIGINT, kein Zeichen"

echo "   -- STRG-C, STRG-Z und der Hintergrund: die Auftragssteuerung"
say "$F" "job grp" 0 "setpgid(0,0) macht aus dem Kind seine eigene Prozessgruppe"
say "$F" "job ctlc" 130 "STRG-C BEENDET DEN VORDERGRUNDPROZESS WIRKLICH: 128 + SIGINT"
say "$F" "job tstp" 7 "STRG-Z haelt ihn an statt ihn zu beenden"
say "$F" "job cont" 1 "und SIGCONT setzt ihn fort"
say "$F" "job ttin" 7 "wer aus dem Hintergrund lesen will, bekommt SIGTTIN und steht"

echo "   -- die Uhr"
say "$F" "mono runs" 1 "die monotone Uhr laeuft vorwaerts"
say "$F" "mono backward" 0 "UND SIE LAEUFT NIE RUECKWAERTS"
num "Messungen, ueber die das geprueft wurde" "$(value_of "$F" 'mono samples')" ge 20000
num "das Jahr, das die Echtzeituhr meldet" "$(value_of "$F" 'real year')" ge 2024
between "$F" "sleep 50ms" 40 500 "ein Schlaf von 50 ms dauert wirklich so lange (ms)"
say "$F" "clock 99" -22 "eine Uhr, die es nicht gibt: -EINVAL"
say "$F" "tod agree" 1 "gettimeofday und time sagen dasselbe"
say "$F" "res fine" 1 "die Koernung ist feiner als eine Zeitgebermarke (Zyklenzaehler statt Marken)"

echo "   -- der Zufall"
say "$F" "random got" 1024 "getrandom fuellt, worum es gebeten wird"
between "$F" "random chi" 100 500 "die Verteilung ueber 256 Faecher, Chi-Quadrat (255 +- 23 waere ideal)"
between "$F" "random bits" 450 550 "und die Verteilung der Bits in Zehntelprozent (500 = die Haelfte)"
num "verschiedene Oktette zwischen zwei Puffern von 1024" "$(value_of "$F" 'random diff')" ge 990
say "$F" "random zero" 0 "getrandom(0) ist 0 und kein Fehler"
say "$F" "random fault" -14 "ein Zeiger in den Kernel: -EFAULT"

lines=$(value_of "$F" lines)
seen=$(grep -ac '^unix: .* = ' "$F")
num "Messungen, die das Programm gezaehlt hat" "${lines:-0}" ge 55
if [ -n "$lines" ] && [ "$seen" = "$((lines + 1))" ]; then
    ok "jede gezaehlte Zeile ist wirklich ueber die serielle Leitung gekommen ($seen)"
else
    bad "das Programm zaehlte ${lines:-0} Zeilen, angekommen sind $seen"
fi
if grep -aq 'osum\$ unix' "$F" && grep -aq 'sh: bye' "$F"; then
    ok "die Shell hat das Programm von der Platte gestartet, auf es gewartet und danach selbst geendet"
else
    bad "die Shell hat das Programm nicht sauber gestartet oder nicht geendet"
fi
if grep -aq '\*\*\* EXCEPTION' "$F"; then
    bad "eine unbehandelte Ausnahme in einem Lauf, der drei davon absichtlich ausloest"
else
    ok "keine unbehandelte Ausnahme -- die drei provozierten wurden zu Signalen"
fi
grep -aq 'kernel: done' "$F" \
    && ok "der Kernel ist nach alldem bis zum Ende gekommen" \
    || bad "'kernel: done' fehlt"

# ------------------------------------------------------------- Abschnitt 4

echo "== 4. GEGENPROBE 'nosig': ohne Zustellung bleibt der Zaehler bei null =="
run_disk "$TMPD/k0.mb" "osum unix nosig $QUIET script=unix probe;exit" "$TMPD/nosig.txt"
rc=$?
N="$TMPD/nosig.txt"
[ "$rc" -eq 21 ] && ok "der Lauf ohne Zustellung endet von selbst (exit 21)" \
                 || bad "nosig: QEMU-Beendigungscode $rc"
say "$N" "caught" 0 "ohne Zustellung faengt niemand etwas ab"
say "$N" "count" 0 "und sechs abgeschickte Signale zaehlen null"
say "$N" "after unblock" 0 "auch die Freigabe holt nichts nach"
say "$N" "pending" 1 "ABER DAS BIT STEHT -- abgeschickt wurde sehr wohl etwas"
# Das ist der Kern der Gegenprobe: `kill` verhaelt sich gleich, nur
# ZUGESTELLT wird nichts. Waere `kill` selbst abgeschaltet, wuerde die
# Gegenprobe etwas anderes messen, als sie behauptet.
p_on=$(value_of "$TMPD/run.txt" "count"); p_off=$(value_of "$N" "count")
if [ "$p_on" = "6" ] && [ "$p_off" = "0" ]; then
    ok "derselbe Code, ein Wort auf der Kommandozeile: 6 gegen 0"
else
    bad "die Gegenprobe unterscheidet nicht: $p_on gegen $p_off"
fi

# ------------------------------------------------------------- Abschnitt 5

echo "== 5. GEGENPROBE 'fixedrand': die statistische Pruefung MUSS durchfallen =="
run_disk "$TMPD/k0.mb" "osum unix fixedrand $QUIET script=unix probe;exit" "$TMPD/fixed.txt"
rc=$?
X="$TMPD/fixed.txt"
[ "$rc" -eq 21 ] && ok "der Lauf mit festverdrahtetem Zufall endet von selbst (exit 21)" \
                 || bad "fixedrand: QEMU-Beendigungscode $rc"
chi=$(value_of "$X" "random chi")
num "Chi-Quadrat mit festverdrahtetem Oktett (die Pruefung muss durchfallen)" "${chi:-0}" ge 100000
say "$X" "random diff" 0 "und zwei Puffer hintereinander sind Oktett fuer Oktett gleich"
say "$X" "random got" 1024 "geliefert wird trotzdem, worum gebeten wurde -- nur eben Unsinn"
# UND DIE LEHRE DARAUS, die mit im Bericht steht: die Bitverteilung ALLEIN
# haette den festen Strom durchgewinkt, weil 0x5A vier von acht Bits
# gesetzt hat. Eine Pruefung reicht nicht.
bits=$(value_of "$X" "random bits")
if [ -n "$bits" ] && [ "$bits" -ge 450 ] && [ "$bits" -le 550 ]; then
    ok "und die Bitverteilung allein haette ihn durchgewinkt ($bits) -- deshalb gibt es zwei Pruefungen"
else
    bad "die Bitverteilung des festen Stroms: $bits"
fi

# ------------------------------------------------------------- Abschnitt 6

echo "== 6. drei Neustarts, drei verschiedene Saaten =="
seeds=""
for i in 1 2 3; do
    run_disk "$TMPD/k0.mb" "osum unix $QUIET script=exit" "$TMPD/seed$i.txt"
    s=$(grep -a -m1 '^rand: seed=' "$TMPD/seed$i.txt" | sed 's/.*seed=//' | awk '{print $1}')
    seeds="$seeds $s"
    sleep 1
done
distinct=$(echo $seeds | tr ' ' '\n' | sed '/^$/d' | sort -u | wc -l)
found=$(echo $seeds | wc -w)
num "Saaten, die drei Neustarts gemeldet haben" "$found" eq 3
num "davon verschieden" "$distinct" eq 3
hw=$(grep -a -m1 '^rand: seed=' "$TMPD/seed1.txt" | grep -oE 'hw=[0-9]+' | cut -d= -f2)
stirs=$(grep -a -m1 '^rand: seed=' "$TMPD/seed1.txt" | grep -oE 'stirs=[0-9]+' | cut -d= -f2)
num "Ereignisse, die bis zum Saeen in den Sammler gingen" "${stirs:-0}" ge 20
if [ "${hw:-0}" = "0" ]; then
    ok "ohne RDSEED/RDRAND auf dieser Maschine -- die Entropie kommt allein aus dem Flattern (hw=0)"
else
    ok "die Rauschquelle des Prozessors war da und ist mit eingegangen (hw=$hw)"
fi
tsc=$(grep -a -m1 '^time: tsc=' "$TMPD/seed1.txt" | grep -oE 'tsc=[0-9]+' | cut -d= -f2)
num "die gemessene Taktfrequenz des Zyklenzaehlers (kHz)" "${tsc:-0}" ge 100000
wall=$(grep -a -m1 '^time: tsc=' "$TMPD/seed1.txt" | grep -oE 'wall=[0-9]+' | cut -d= -f2)
num "die Wandzeit aus der CMOS-Uhr (Sekunden seit 1970)" "${wall:-0}" ge 1700000000

echo
echo "UNIX: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
