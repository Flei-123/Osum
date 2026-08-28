#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/poll/run.sh -- RUNDE POLL: AUF ZWEI DINGE GLEICHZEITIG WARTEN.
#
# EHRLICHER AUSGANGSPUNKT, gemessen und nicht behauptet: vor dieser Runde
# fand `grep` im ganzen Baum kein `poll`, kein `select` und kein `epoll`.
# Es gab `fork`, `exec`, `pipe`, `dup2`, `wait4` und eine `/etc/inittab`
# mit `respawn` -- alles, was ein Unix braucht, ausser der einen Sache,
# ohne die ein Prozess nur auf GENAU EINE Quelle warten kann.
#
# WARUM DAS DER HARTE BLOCKER WAR. Die geplante Bruecke nach JARVIS
# (`jarvisd`) ist ein Helfer, der gleichzeitig auf einen NETZANSCHLUSS
# und auf das ROHR ZU EINEM KINDPROZESS warten muss. Ohne `poll` bleibt
# nur der Wechsel zwischen beiden in einer Warteschleife -- Rechenzeit,
# wenn nichts los ist, und Verzoegerung, wenn etwas los ist. Jede Shell
# braucht denselben Aufruf.
#
# WAS HIER GEMESSEN WIRD, und jeder Punkt hat eine GEGENPROBE, weil eine
# Eigenschaft ohne Gegenprobe eine Behauptung ist:
#
#   1. DIE NUMMER. `poll` ist 7 -- Linux' Nummer, denn Regel 1 der Karte
#      in `kernel/sys.fi` sagt: was Linux hat, hat Linux' Nummer. Geprueft
#      wird, dass KEINE Nummer in einer der beiden Tafeln (Kernel und
#      libc) zweimal vorkommt und dass beide Tafeln Zahl fuer Zahl
#      uebereinstimmen. Das ist die Lehre aus der Runde, in der zwei
#      Zweige beide die 1320 vergeben hatten: eine Nummer, die zwei Dinge
#      bedeutet, ist ein Programm, das nach `poll` fragt und `lstat`
#      bekommt. Geprueft wird die GANZE Tafel, nicht nur die neue Zeile.
#   2. ZWEI ROHRE, EINES BESCHRIEBEN -- `poll` meldet GENAU EINES. Ein
#      `poll`, das beide meldet, hat geraten.
#   3. DAS GESCHLOSSENE GEGENENDE ist POLLHUP, und mit Oktetten im Rohr
#      POLLHUP UND POLLIN. Die Schreibseite ohne Leser ist POLLERR. Beide
#      kommen, OHNE dass danach gefragt wurde (so verlangt es POSIX).
#   4. DER ZEITABLAUF MISST WIRKLICH DIE ZEIT, gemessen mit
#      CLOCK_MONOTONIC und nicht mit dem Tickzaehler, den `poll` selbst
#      benutzt -- sonst misst die Uhr sich selbst. Die Toleranz ist
#      begruendet: der Zeitgeber laeuft mit 100 Hz, `poll` rundet auf und
#      zaehlt die angebrochene Marke mit, also liegt die Frist zwischen
#      `timeout` und `timeout + 20 ms`. FRUEHER als verlangt darf sie nie
#      liegen.
#   5. WER WARTET, RECHNET NICHT. Das ist die Zusage, um die es geht.
#      Gemessen wird der Systemaufrufzaehler des ganzen Systems ueber
#      1,2 Sekunden Wartezeit -- einmal mit `poll` und einmal als
#      Warteschleife mit 10 ms Schlaf. Der Unterschied ist der Beweis.
#   6. DIE FEHLER: zu viele Deskriptoren (-EINVAL), ein Nullzeiger und
#      ein Zeiger in den Kern (-EFAULT), ein Deskriptor, der nicht offen
#      ist (POLLNVAL statt eines Fehlers des ganzen Aufrufs).
#   7. DIE BRUECKE SELBST, MIT DRAHT. `/bin/jarvisd` lauscht auf 9100,
#      haelt daneben das Rohr eines Kindes und steht in EINEM `poll`
#      ueber beide. Der Wirt verbindet sich durch QEMUs Weiterleitung und
#      schickt eine Zeile; das Kind redet unabhaengig davon. BEIDES muss
#      bedient werden, und die Antwort muss beim Wirt ankommen.
#
# Gemessen wie die Runden 59, 62 und K1 gemessen haben: QEMU je Fall, mit
# Zeitgrenze, serielle Ausgabe gegen Erwartungen, Beendigungscode aus
# `isa-debug-exit` (21 = der Kernel hat selbst Schluss gemacht, 63 = eine
# Ausnahme). MIT `-accel kvm`, wo vorhanden -- das ist seit Runde KVMFIX
# moeglich und rund viereinhalbmal schneller; ohne KVM faellt der Laeufer
# auf `-accel tcg` zurueck und sagt es.
#
# Aufruf:  bash tools/poll/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."

export FIRNLIB="$(pwd)/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
FC1=${FIRNC1:-vendor/firn/bin/firnc1}
LDSCRIPT=kernel/kernel.ld
ULD=kernel/user/user.ld
PROGS="sh ls cat echo hello pollt jarvisd"
BLOCKS=2048
OSUM_IP=10.0.2.15
OSUM_GW=10.0.2.2
FWPORT=${FWPORT:-45719}
QPID=""

TMPD=$(mktemp -d)
cleanup() {
    [ -n "$QPID" ] && kill "$QPID" 2>/dev/null
    rm -rf "$TMPD"
}
trap cleanup EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }

num() { # name wert op erwartet
    local name=$1 value=$2 op=$3 want=$4
    if [ -z "$value" ]; then bad "$name: keine Zahl gefunden (erwartet $op $want)"; return; fi
    if [ "$value" -"$op" "$want" ] 2>/dev/null; then ok "$name: $value"
    else bad "$name: $value, erwartet $op $want"; fi
}

between() { # name wert unten oben
    local name=$1 v=$2 lo=$3 hi=$4
    if [ -z "$v" ]; then bad "$name: keine Zahl gefunden"; return; fi
    if [ "$v" -ge "$lo" ] && [ "$v" -le "$hi" ]; then ok "$name: $v (erlaubt $lo..$hi)"
    else bad "$name: $v, erlaubt $lo..$hi"; fi
}

value_of()  { grep -a -m1 "^pollt: $2 = " "$1" 2>/dev/null | sed 's/.* = //'; }
jvalue_of() { grep -a -m1 "^jarvisd: $2 = " "$1" 2>/dev/null | sed 's/.* = //'; }

say() { # datei name erwartet beschreibung
    local got
    got=$(value_of "$1" "$2")
    if [ -z "$got" ]; then bad "$4 -- keine Zeile 'pollt: $2 ='"; return; fi
    if [ "$got" = "$3" ]; then ok "$4 ($2 = $got)"
    else bad "$4 -- $2 = $got, erwartet $3"; fi
}

number_in() { # datei name
    grep -aE "^const $2: u64 = [0-9]+" "$1" | head -1 \
        | sed -E 's/^const [A-Za-z0-9_]+: u64 = ([0-9]+).*/\1/'
}

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "vendor/firn/fetch-firnc.sh fehlgeschlagen"; exit 1; }
[ -x "$FIRNC" ] || { echo "firnc0 fehlt: $FIRNC"; exit 1; }
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "POLL: uebersprungen, qemu-system-x86_64 fehlt"
    exit 0
fi

# RUNDE KVMFIX hat den Kernel unter KVM zum Laufen gebracht (zwei echte
# Hardwarefehler, siehe KVMFIX-STATUS.md). Wo /dev/kvm da ist, wird es
# benutzt -- und wo nicht, sagt es der Laeufer, statt still langsamer zu
# messen.
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    ACCEL="-accel kvm"; ACCELNAME="kvm"
else
    ACCEL="-accel tcg"; ACCELNAME="tcg (kein /dev/kvm)"
fi

# =====================================================================
echo "== 1. die Nummer: 7, einmal, in beiden Tafeln =="
# =====================================================================
kn=$(number_in kernel/sys.fi SYS_POLL)
ln=$(number_in lib/libc/kcall.fi SYS_POLL)
[ "$kn" = 7 ] && ok "kernel/sys.fi: SYS_POLL = 7 (Linux' Nummer)" \
              || bad "kernel/sys.fi: SYS_POLL = ${kn:-fehlt}, Linux sagt 7"
[ "$ln" = 7 ] && ok "lib/libc/kcall.fi: SYS_POLL = 7" \
              || bad "lib/libc/kcall.fi: SYS_POLL = ${ln:-fehlt}"

# DIE PRUEFUNG, DIE ES OHNE DIE 1320 NICHT GAEBE: keine Nummer darf in
# einer der beiden Tafeln zweimal vergeben sein.
dup_in() { # datei
    grep -aoE "^const SYS_[A-Z0-9_]+: u64 = [0-9]+" "$1" \
        | sed -E 's/^const ([A-Z0-9_]+): u64 = ([0-9]+).*/\2 \1/' \
        | grep -vE '^(1|2) SYS_(MARK|LEAVE)$' \
        | sort -u \
        | awk '{c[$1]=c[$1]" "$2; n[$1]++} END {for (k in n) if (n[k]>1) print k":"c[k]}'
}
kdup=$(dup_in kernel/sys.fi)
[ -z "$kdup" ] && ok "kernel/sys.fi: keine Systemaufrufnummer ist zweimal vergeben" \
               || { bad "kernel/sys.fi: doppelt vergebene Nummern"; echo "$kdup" | sed 's/^/        /'; }
ldup=$(dup_in lib/libc/kcall.fi)
[ -z "$ldup" ] && ok "lib/libc/kcall.fi: keine Nummer ist zweimal vergeben" \
               || { bad "lib/libc/kcall.fi: doppelt vergebene Nummern"; echo "$ldup" | sed 's/^/        /'; }

# Und beide Tafeln sagen dasselbe -- Name fuer Name, wie Abschnitt 1 von
# tools/posix/run.sh es seit Runde K4 tut.
diffs=0
while read -r name value; do
    other=$(number_in lib/libc/kcall.fi "$name")
    [ -n "$other" ] || continue
    [ "$other" = "$value" ] || { diffs=$((diffs+1)); echo "        $name: kernel $value, libc $other"; }
done < <(grep -aoE "^const SYS_[A-Z0-9_]+: u64 = [0-9]+" kernel/sys.fi \
    | sed -E 's/^const ([A-Z0-9_]+): u64 = ([0-9]+).*/\1 \2/' \
    | grep -vE '^SYS_(MARK|LEAVE) ')
num "Nummern, bei denen Kernel und libc auseinanderlaufen" "$diffs" eq 0

# Die Bits von <poll.h> sind die von Linux, und in beiden Dateien gleich.
for pair in "POLLIN 1" "POLLPRI 2" "POLLOUT 4" "POLLERR 8" "POLLHUP 16" "POLLNVAL 32"; do
    set -- $pair
    k=$(number_in kernel/sys.fi "$1"); l=$(number_in lib/libc/io.fi "$1")
    if [ "$k" = "$2" ] && [ "$l" = "$2" ]; then ok "$1 = $2 in Kernel und libc"
    else bad "$1: kernel ${k:-fehlt}, libc ${l:-fehlt}, erwartet $2"; fi
done

# Die Gegenprobe zur Ausgangslage: es gibt weiterhin kein `select` und
# kein `epoll` -- diese Runde hat `poll` gebaut und nichts vorgetaeuscht.
if grep -aqE "^const SYS_(SELECT|EPOLL)" kernel/sys.fi; then
    bad "es steht ploetzlich select/epoll in der Tafel -- diese Runde hat das nicht gebaut"
else
    ok "kein select und kein epoll vorgetaeuscht (nur poll ist da)"
fi

# =====================================================================
echo "== 2. bauen: Kernel, libc, /bin/pollt und /bin/jarvisd =="
# =====================================================================
for f in boot isr switch smp hv; do
    as --64 -o "$TMPD/$f.o" "kernel/arch/x86_64/$f.s" 2>"$TMPD/as.err" \
        || bad "$f.s laesst sich nicht assemblieren"
done
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s"

build_stage() { # 0 = firnc0, 1 = firnc1
    local s=$1 cc p
    if [ "$s" = 0 ]; then cc="$FIRNC"; else cc="$FC1"; fi
    [ -x "$cc" ] || return 1
    "$cc" kernel/kmain.fi -o "$TMPD/k$s.o" >"$TMPD/e$s" 2>&1 \
        || { bad "firnc$s uebersetzt den Kernel nicht"; sed 's/^/        /' "$TMPD/e$s" | head -8; return 1; }
    "$cc" kernel/uprog.fi -o "$TMPD/u$s.o" >>"$TMPD/e$s" 2>&1 \
        || { bad "firnc$s uebersetzt uprog.fi nicht"; return 1; }
    ld -n -T "$LDSCRIPT" \
        --defsym=KERNEL_MAIN="_F$s.kernel_main" \
        --defsym=KERNEL_TRAP="_F$s.trap__entry" \
        --defsym=KERNEL_SYSCALL="_F$s.sys__entry" \
        --defsym=KERNEL_TASK_MAIN="_F$s.tasks__main" \
        --defsym=KERNEL_USER_START="_F$s.proc__user_start" \
        --defsym=KERNEL_AP_MAIN="_F$s.smp__ap_main" \
        --defsym=USER_MAIN="_F$s.u_enter" \
        -o "$TMPD/k$s.elf" "$TMPD/boot.o" "$TMPD/isr.o" "$TMPD/switch.o" \
        "$TMPD/smp.o" "$TMPD/hv.o" "$TMPD/k$s.o" "$TMPD/u$s.o" 2>"$TMPD/ld$s.err" \
        || { bad "firnc$s: ld ist am Kernel gescheitert"; return 1; }
    objcopy -O elf32-i386 "$TMPD/k$s.elf" "$TMPD/k$s.mb" 2>/dev/null
    for p in $PROGS; do
        "$cc" "kernel/user/$p.fi" -o "$TMPD/$p$s.o" >"$TMPD/e$p$s" 2>&1 \
            || { bad "firnc$s uebersetzt $p.fi nicht"; sed 's/^/        /' "$TMPD/e$p$s" | head -6; return 1; }
        ld -T "$ULD" --defsym=USER_ENTRY="_F$s.u_start" \
            -o "$TMPD/$p$s.elf" "$TMPD/crt.o" "$TMPD/$p$s.o" 2>/dev/null \
            || { bad "firnc$s: ld ist an $p gescheitert"; return 1; }
        strip --strip-all "$TMPD/$p$s.elf"
    done
    return 0
}
build_stage 0 || { echo "POLL: $pass bestanden, $fail durchgefallen"; exit 1; }
ok "firnc0: Kernel + $(echo $PROGS | wc -w) Programme"
if build_stage 1; then
    ok "firnc1: dasselbe, aus dem in Firn geschriebenen Uebersetzer"
else
    note "firnc1 hat nicht gebaut -- die Messungen unten laufen mit firnc0"
fi

undef=$(nm -u "$TMPD/pollt0.elf" 2>/dev/null | awk '{print $NF}' | sed '/^$/d')
[ -z "$undef" ] && ok "/bin/pollt hat keinen undefinierten Namen -- die libc ist vollstaendig" \
                || bad "undefinierte Namen in pollt: $undef"
undef=$(nm -u "$TMPD/jarvisd0.elf" 2>/dev/null | awk '{print $NF}' | sed '/^$/d')
[ -z "$undef" ] && ok "/bin/jarvisd ebenso" || bad "undefinierte Namen in jarvisd: $undef"

SPEC="/bin/"
for p in $PROGS; do SPEC="$SPEC /bin/$p=$TMPD/${p}0.elf"; done
python3 tools/osum/mkfs.py build "$TMPD/disk.img" $BLOCKS $SPEC > "$TMPD/mkfs.txt" 2>&1 \
    && ok "mkfs.py hat ein OFS-Abbild mit dem Userland dieser Runde gebaut" \
    || { bad "mkfs.py fehlgeschlagen"; sed 's/^/        /' "$TMPD/mkfs.txt"; }

run_disk() { # abbild anhang ausgabe
    local copy="$TMPD/live.img"
    cp "$TMPD/disk.img" "$copy"
    timeout 300 qemu-system-x86_64 $ACCEL -kernel "$1" -m 128 -append "$2" \
        -serial "file:$3" -display none -no-reboot \
        -drive "file=$copy,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    return $?
}

QUIET="nokbd nosched noproc nofs noring3"

# =====================================================================
echo "== 3. jede Zusage von poll, im laufenden Kernel ($ACCELNAME) =="
# =====================================================================
T0=$(date +%s%N)
run_disk "$TMPD/k0.mb" "osum $QUIET script=pollt;exit" "$TMPD/run0.txt"
rc=$?
T1=$(date +%s%N)
F="$TMPD/run0.txt"
[ "$rc" -eq 21 ] && ok "der Kernel hat selbst Schluss gemacht (Beendigungscode 21)" \
                 || { bad "QEMU-Beendigungscode $rc, erwartet 21"; tail -8 "$F" | tr -d '\000' | sed 's/^/        /'; }
note "Laufzeit dieses Abschnitts: $(( (T1-T0)/1000000 )) ms mit $ACCELNAME"

echo "   -- zwei Rohre, eines beschrieben"
say "$F" two_ret 1  "poll meldet GENAU EINEN bereiten Deskriptor"
say "$F" two_re0 1  "und zwar das beschriebene Rohr: POLLIN"
say "$F" two_re1 0  "das andere Rohr meldet nichts"
say "$F" two_fd0 3  "poll hat den Deskriptor im Eintrag nicht angefasst (nur revents)"

echo "   -- das geschlossene Gegenende"
say "$F" hup_ret 1       "ein Rohr ohne Schreiber ist ein Ereignis"
say "$F" hup_re 16       "und es ist POLLHUP -- ungefragt, angefordert war nur POLLIN"
say "$F" hup_data_re 17  "mit Oktetten im Rohr: POLLIN UND POLLHUP (17 = 1|16)"
say "$F" hup_read 3      "und diese Oktette lassen sich danach wirklich lesen"

echo "   -- die Schreibseite"
say "$F" out_re 4        "Platz im Rohr ist POLLOUT"
say "$F" out_gone_re 8   "kein Leser mehr ist POLLERR -- ungefragt"
say "$F" neg_fd_ret 0    "ein negativer Deskriptor wird uebergangen und zaehlt nicht"
say "$F" neg_fd_re 0     "und seine revents sind null"

echo "   -- was kein Rohr ist"
say "$F" nval_ret 1      "ein Deskriptor, der nicht offen ist, ist ein Ereignis"
say "$F" nval_re 32      "und es ist POLLNVAL -- kein Fehler des ganzen Aufrufs (POSIX)"
say "$F" file_re 5       "eine gewoehnliche Datei ist immer bereit (POLLIN|POLLOUT = 5)"

echo "   -- die Fehler"
say "$F" err_nfds -22    "mehr Deskriptoren als erlaubt: -EINVAL"
say "$F" err_null -14    "ein Nullzeiger mit nfds > 0: -EFAULT"
say "$F" err_kern -14    "ein Zeiger in den Kern: -EFAULT"

echo "   -- der Zeitablauf misst die Zeit"
say "$F" tmo_ret 0       "nichts wurde bereit: 0, kein Fehler"
# Die Toleranz, begruendet: der Zeitgeber laeuft mit 100 Hz. `poll`
# rundet auf die naechste Marke auf und zaehlt die ANGEBROCHENE Marke
# mit, weil `kstate.TICKS` beim Eintritt schon mitten in ihr steht --
# also 300..320 ms; die 340 oben lassen dem Umschalten der Aufgaben Luft.
# Unter 300 darf es NIE liegen: zu frueh zurueckzukommen ist das eine,
# was POSIX verbietet und was ein Programm nicht nachbessern kann.
between "poll(300 ms) hat wirklich mindestens 300 ms gewartet" "$(value_of "$F" tmo_ms)" 300 340
say "$F" tmo0_ret 0      "Zeitablauf 0: nachsehen und sofort zurueck"
between "und das kostet keine messbare Zeit" "$(value_of "$F" tmo0_ms)" 0 20
between "poll(0 Deskriptoren, 200 ms) ist ein sauberer Schlaf" "$(value_of "$F" tmo_nofd_ms)" 200 240

echo "   -- wer wartet, rechnet nicht (die Zusage dieser Runde)"
say "$F" blk_ret 1 "das Kind hat nach 1,2 s geschrieben, und poll ist aufgewacht"
say "$F" blk_got 5 "und die Oktette waren wirklich da"
between "poll(OHNE Frist) kam nach der Zeit des Kindes zurueck" "$(value_of "$F" blk_ms)" 1150 1400
bc=$(value_of "$F" blk_calls)
busy=$(value_of "$F" busy_calls)
num "Systemaufrufe im ganzen System waehrend der 1,2 s mit poll" "$bc" le 20
num "dieselben 1,2 s als Warteschleife mit 10 ms Schlaf" "$busy" ge 100
if [ -n "$bc" ] && [ -n "$busy" ] && [ "$bc" -gt 0 ]; then
    num "Verhaeltnis Warteschleife : poll" "$(( busy / bc ))" ge 5
    note "poll: $bc Aufrufe -- Warteschleife: $busy Aufrufe. Das ist der Unterschied,"
    note "um den es geht: EIN blockierender Aufruf statt hundertzwanzig Weckern."
fi
between "und die Warteschleife hat dieselbe Zeit gebraucht (sonst waere der Vergleich schief)" \
    "$(value_of "$F" busy_ms)" 1150 1400

echo "   -- die Bauform der Bruecke, ohne Draht"
# Ohne Karte gibt es keine Steckdose (-ENODEV, kernel/sys.fi). Das ist
# hier KEIN Fehler: der Lauf MIT Draht steht in Abschnitt 4. Was dieser
# Teil zeigt, ist, dass die Schleife mit einem Eintrag, den es nicht
# gibt, sauber weiterarbeitet und den Kindkanal trotzdem bedient.
say "$F" mix_ret 1    "poll ueber Netzseite und Kindkanal meldet den Kindkanal"
say "$F" mix_child 17 "der Kindkanal: POLLIN und POLLHUP (17)"
say "$F" mix_hup 16   "nach dem Ende des Kindes bleibt POLLHUP stehen"
n=$(value_of "$F" lines)
num "Messzeilen, die /bin/pollt gedruckt hat" "${n:-0}" ge 30

# Die Gegenprobe zum ganzen Abschnitt: der Kernel lebt danach noch.
grep -aq "kernel: done" "$F" && ok "der Kernel ist nach allen Faellen noch am Leben" \
                             || bad "'kernel: done' fehlt -- der Kernel hat den Lauf nicht ueberstanden"

# =====================================================================
echo "== 4. die Bruecke selbst: /bin/jarvisd am Draht =="
# =====================================================================
# Der Draht ist QEMUs Benutzernetz mit einer Weiterleitung. Das braucht
# keine Netzwerknamensraeume und keine Rechte -- anders als
# tools/net/run.sh, das den Stapel auf einem veth-Paar misst. Hier geht
# es nicht um den Stapel, sondern um EINE Frage: bedient ein Prozess in
# EINEM `poll` gleichzeitig eine Verbindung und ein Kind?
if ! command -v nc >/dev/null 2>&1; then
    note 'Abschnitt 4: uebersprungen, nc fehlt'
else
    cp "$TMPD/disk.img" "$TMPD/live2.img"
    JF="$TMPD/jarvisd.txt"
    rm -f "$JF" "$JF.rc"
    ( timeout 300 qemu-system-x86_64 $ACCEL -kernel "$TMPD/k0.mb" -m 256 \
        -append "osum $QUIET nic nip=$OSUM_IP/24 ngw=$OSUM_GW script=jarvisd;exit" \
        -serial "file:$JF" -display none -no-reboot \
        -drive "file=$TMPD/live2.img,format=raw,if=ide,index=0" \
        -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:$FWPORT-$OSUM_IP:9100" \
        -device "virtio-net-pci,netdev=n0,mac=52:54:00:aa:bb:cc" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
      echo $? > "$JF.rc" ) &
    QPID=$!

    # Warten, bis der Helfer WIRKLICH lauscht. Die Zeile steht nach
    # `listen` und nicht davor -- ein Test, der frueher verbindet, misst
    # das Zeitverhalten von QEMU und nicht das von `poll`.
    listening=0
    for i in $(seq 1 600); do
        [ -f "$JF" ] && grep -qa 'jarvisd: listening' "$JF" && { listening=1; break; }
        kill -0 "$QPID" 2>/dev/null || break
        sleep 0.2
    done
    if [ "$listening" = 1 ]; then
        ok "jarvisd lauscht auf $OSUM_IP:9100 (nach rund $(( i * 200 )) ms)"
        sleep 0.5
        printf 'hallo welt\n' | timeout 30 nc -q 3 -w 10 127.0.0.1 $FWPORT > "$TMPD/nc.out" 2>&1
        ncrc=$?
        wait "$QPID" 2>/dev/null; QPID=""
        jrc=$(cat "$JF.rc" 2>/dev/null)
        [ "$jrc" = 21 ] && ok "der Kernel hat auch diesen Lauf selbst beendet (21)" \
                        || bad "QEMU-Beendigungscode ${jrc:-keiner}, erwartet 21"
        num "nc kam durch (Beendigungscode)" "$ncrc" eq 0
        if grep -aq 'osum: hallo welt' "$TMPD/nc.out"; then
            ok "die Antwort des Helfers kam beim Wirt an: 'osum: hallo welt'"
        else
            bad "die Antwort kam nicht beim Wirt an"; sed 's/^/        /' "$TMPD/nc.out" | head -4
        fi
        v=$(jvalue_of "$JF" accepted);    num "angenommene Verbindungen"          "${v:-0}" eq 1
        v=$(jvalue_of "$JF" net_lines);   num "Zeilen aus dem Netz bedient"       "${v:-0}" ge 1
        v=$(jvalue_of "$JF" child_lines); num "Zeilen aus dem Kindrohr bedient"   "${v:-0}" ge 2
        v=$(jvalue_of "$JF" child_hup);   num "das Ende des Kindes kam als POLLHUP" "${v:-0}" eq 1
        v=$(jvalue_of "$JF" child_code);  num "und das Kind ist ordentlich gestorben" "${v:-0}" eq 5
        # DIE ZUSAGE: beides in EINER Schleife, und die Schleife ist nicht
        # heissgelaufen. Ein `poll`, das in Wahrheit eine Warteschleife
        # waere, haette in diesen Sekunden Hunderte von Durchlaeufen.
        v=$(jvalue_of "$JF" polls)
        num "Durchlaeufe der einen Schleife (eine Warteschleife haette Hunderte)" "${v:-999}" le 12
        v=$(jvalue_of "$JF" first)
        if [ "$v" = 1 ] || [ "$v" = 2 ]; then
            ok "beide Quellen wurden bedient, in der Reihenfolge, in der sie kamen (first=$v)"
        else
            bad "keine der beiden Quellen war zuerst da (first=${v:-fehlt})"
        fi
    else
        kill "$QPID" 2>/dev/null; QPID=""
        bad "jarvisd hat nicht angefangen zu lauschen"
        tail -6 "$JF" 2>/dev/null | tr -d '\000' | sed 's/^/        /'
    fi
fi

echo
echo "POLL: $pass bestanden, $fail durchgefallen"
[ "$fail" -eq 0 ] || exit 1
exit 0
