#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/ota/run.sh -- RUNDE OTA: EIN UPDATE, DAS DAS GERAET SICH SELBST
# UEBER DAS NETZ HOLT -- UND DIE SECHS ARTEN, AUF DIE ES SCHIEFGEHEN
# DARF, OHNE DASS ETWAS KAPUTTGEHT.
#
# GEGEN WAS GEMESSEN WIRD, und das steht hier und nicht im Kleingedruckten:
# ES GIBT KEINEN ECHTEN UPDATE-SERVER IM INTERNET. Gemessen wird gegen
# `tools/ota/server.py` -- einen HTTPS-Dienst auf DEMSELBEN WIRT, mit
# echtem TLS 1.3 aus Pythons `ssl` (also OpenSSL, nicht dieses
# Repository), einem echten Zertifikat mit echter Kette, echtem
# `Content-Length`, echtem `Range`/`206` und echten Verbindungsabbruechen.
# Das Geraet spricht darueber eine echte e1000 und QEMUs Benutzernetz an,
# in dem 10.0.2.2 der Wirt ist. Was daran fehlt, um "im Internet" zu
# heissen, steht am Ende von `docs/OTA.md`.
#
# DIE ABSCHNITTE:
#
#   1. DER BAU. `/bin/ota` (profile kernel) und `/bin/fetch`
#      (--profile=app, die volle Firn-Bibliothek mit TLS 1.3) -- und ein
#      Abbild, in dem BEIDE liegen. Bis zu dieser Runde lag `fetch` in
#      keinem Abbild; `docs/UPDATE.md` nannte das als ersten Punkt seiner
#      Fehlliste.
#
#   2. DER GUTE WEG, ENDE ZU ENDE. Ein Geraet mit Fassung 1 sucht,
#      findet Fassung 2, holt sie, prueft sie, spielt sie ein, startet
#      neu, laeuft und bestaetigt. MIT MESSUNGEN: Oktette, Dauer,
#      Platzbedarf.
#
#   3. DIE ABLEHNUNGEN. Sechs Faelle, und nach jedem wird nachgesehen,
#      dass WIRKLICH NICHTS geschrieben wurde:
#        (a) falsch signiertes Paket
#        (a2) falsch signiertes VERZEICHNIS
#        (g) richtig signiertes VERZEICHNIS mit veraendertem Streuwert
#        (b) eine AELTERE Fassung -- der Rueckschrittsschutz
#        (c) mitten im Laden abgebrochen, danach wiederaufgenommen
#        (f) die Platte ist voll
#
#   4. (d) DAS UPDATE, DAS NICHT HOCHKOMMT. Zehn volle Durchlaeufe:
#      einspielen, neu starten, es kommt nicht hoch, der Kern faellt von
#      selbst zurueck, die Maschine laeuft wieder. Zehnmal, weil einmal
#      ein Zufall ist.
#
#   5. (e) DER STROMAUSFALL. Dreissigmal QEMU mit SIGKILL abgeschossen,
#      an dreissig verschiedenen Stellen des Einspielens. Danach muss die
#      Maschine JEDESMAL hochkommen und ENTWEDER die alte ODER die neue
#      Fassung haben -- nie etwas dazwischen.
#
# Verwendung:  bash tools/ota/run.sh [--kurz]
#   --kurz  drei statt zehn Rueckfaelle und zehn statt dreissig Schuesse.
#           Zum Iterieren waehrend der Arbeit; die Zahlen im Bericht
#           kommen aus dem VOLLEN Lauf.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
. tools/lib/qemu.sh

# WELCHER PROZESSOR -- UND WARUM NICHT `max`.
#
# GEMESSEN IN DIESER RUNDE, mit demselben `/bin/fetch` und demselben
# Kern, nur mit anderem `-cpu`:
#
#     qemu64        laeuft      SSE2
#     Nehalem       laeuft      SSE4.2
#     Westmere      laeuft      + AES-NI
#     SandyBridge   laeuft      + AVX
#     Haswell       laeuft      + AVX2, BMI2
#     max           #UD         + AVX-512, SHA-NI und alles Weitere
#
# Unter `-cpu max` stirbt `/bin/fetch` mit
# `user fault: vector=6 (#UD)` mitten im TLS-Aufbau. Die Ursache liegt
# NICHT in dieser Runde und nicht in `fetch`: Osum schaltet fuer Ring 3
# weder `CR4.OSXSAVE` noch `XCR0` frei, und der Kontextwechsel sichert
# keine Vektorregister. Firns Bibliothek fragt `cpuid` und nimmt den
# breitesten Weg, den die Maschine anbietet -- und der ist dann einer,
# den dieser Kern nicht tragen kann.
#
# Gemessen wird deshalb mit `Haswell`: ein echtes Prozessormodell, kein
# Notbehelf, und alles, was dieser Kern kann, ist darin an. DASS ES EINE
# GRENZE GIBT, WIRD NICHT VERSCHWIEGEN -- sie steht in `docs/OTA.md` in
# der Fehlliste, weil ein Rechner mit AVX-512 auf dem Tisch steht und
# nicht in QEMU.
export OSUM_CPU=${OSUM_CPU:-Haswell}
OUT=${OUT:-/tmp/ota-run}
mkdir -p "$OUT" .probe
export OUT
PORT=${OTA_PORT:-$(( 18000 + ($$ % 900) ))}
NETZ="nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0"
KURZ=${1:-}
RUNDEN=10
SCHUESSE=6
if [ "$KURZ" = "--kurz" ]; then RUNDEN=3; SCHUESSE=10; fi
if [ "$KURZ" = "--probe" ]; then RUNDEN=1; SCHUESSE=2; fi

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
gleich() { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', erwartet '$3'"; fi; }
hat() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hatnicht() { grep -qaF "$2" "$1" && bad "$3 -- '$2' steht da und sollte nicht" || ok "$3"; }
zahl() { local n=$1 v=$2 o=$3 w=$4
    if [ -z "${v:-}" ]; then bad "$n: keine Zahl (erwartet $o $w)"; return; fi
    if [ "$v" -"$o" "$w" ] 2>/dev/null; then ok "$n: $v"; else bad "$n: $v, erwartet $o $w"; fi
}

SRVPID=""
dienst_aus() {
    if [ -n "$SRVPID" ]; then kill "$SRVPID" 2>/dev/null; wait "$SRVPID" 2>/dev/null; fi
    SRVPID=""
}
dienst() { # <wurzel> [weitere Schalter...]
    dienst_aus
    local w=$1; shift
    python3 tools/ota/server.py --wurzel "$w" --port "$PORT" \
        --cert "$OUT/certs/srv.pem" --key "$OUT/certs/srv.key" \
        --log "$OUT/srv.log" "$@" > "$OUT/srv.out" 2>&1 &
    SRVPID=$!
    local i
    for i in $(seq 1 40); do
        grep -qa "^START" "$OUT/srv.log" 2>/dev/null && return 0
        sleep 0.2
    done
    return 1
}
aufraeumen() { dienst_aus; }
trap aufraeumen EXIT

# Ein Lauf von der PLATTE, ueber OVMF, mit Netz. Gibt den
# Beendigungscode zurueck.
lauf() { # name skript [limit]
    : > "$OUT/srv.log"
    OTA_NETZ="$NETZ" OUT="$OUT" bash tools/install/oneshot.sh \
        "$1" platte "$2" "${3:-600}" > /dev/null 2>&1
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' "$OUT/$1.txt" 2>/dev/null
    cat "$OUT/$1.rc" 2>/dev/null
}

for t in qemu-system-x86_64 python3 curl mcopy; do
    command -v "$t" >/dev/null 2>&1 || { echo "OTA: uebersprungen, $t fehlt"; exit 0; }
done
python3 -c 'import cryptography' 2>/dev/null || {
    echo "OTA: uebersprungen, python3-cryptography fehlt"; exit 0; }

# =====================================================================
echo
echo "== 5. (e) der Stromausfall: $SCHUESSE Schuesse mitten ins Einspielen =="
# =====================================================================
#
# QEMU wird mit SIGKILL abgeschossen -- nicht `-no-reboot`, nicht ein
# Ausgang, sondern der Stecker.
#
# WO DIE SCHUESSE LIEGEN, UND WARUM DAS NICHT GERATEN WIRD: im ersten
# vollen Lauf standen sie fest zwischen 1 und 16 Sekunden, weil "so etwa
# zwanzig Sekunden" geschaetzt war. Gemessen (tools/ota/zeitprobe.sh,
# jede serielle Zeile gestempelt) faengt das Netz aber erst nach rund
# zehn Sekunden an und geschrieben wird erst kurz vor der
# sechsundzwanzigsten. Ergebnis: alle dreissig Schuesse trafen die
# Firmware, dreissig von dreissig endeten auf "alt", KEIN EINZIGER auf
# "neu" -- dreissig gruene Haken, die nichts belegten.
#
# Deshalb wird das Fenster JETZT GEMESSEN und nicht gesetzt: die Probe
# laeuft einmal sauber durch und liefert T_NETZ, T_LADEN, T_SCHREIB und
# T_FERTIG. Die eine Haelfte der Schuesse verteilt sich gleichmaessig
# ueber den ganzen Vorgang, die andere DICHT ueber die Schreibphase
# (vom gepruefsten Paket bis kurz hinter "bereit zum Neustart") -- genau
# dort, wo ein Stromausfall wehtun kann.
#
# DIE ZUSAGE: die Maschine kommt danach hoch, und sie hat ENTWEDER die
# alte ODER die neue Fassung. Nie etwas dazwischen, nie eine Generation
# ohne Store-Eintrag, nie ein halbes AKTUELL. UND: das Fenster muss
# BEIDE Seiten treffen -- kommt kein einziges "neu" heraus, ist der Test
# wertlos und faellt durch.
dienst "$OUT/netz2" || bad "Gegenstelle"
OUT="$OUT" bash tools/ota/zeitprobe.sh "$OUT/zeitmarken" > "$OUT/zeitprobe.log" 2>&1
dienst_aus
T_NETZ=0; T_LADEN=0; T_SCHREIB=0; T_FERTIG=0; T_ENDE=0
. "$OUT/zeitmarken" 2>/dev/null || true
zahl "(e) die Zeitprobe hat den ganzen Einspielvorgang gesehen" "$T_FERTIG" gt 0
echo "        gemessen: netz $T_NETZ ms, paket geprueft $T_LADEN ms, geschrieben $T_SCHREIB ms, bereit $T_FERTIG ms"
E_MAX=$(( T_ENDE + 1000 ))
[ "$E_MAX" -gt 2000 ] || E_MAX=27000
E_S0=$T_LADEN
[ "$E_S0" -gt 0 ] || E_S0=14000
E_S1=$T_SCHREIB
[ "$E_S1" -gt "$E_S0" ] || E_S1=$(( E_S0 + 9000 ))
# Das dritte Fenster liegt HINTER dem Umschalten. Es reicht bewusst ueber
# das Ende des gemessenen Laufs hinaus: der naechste Lauf ist nie exakt
# gleich schnell (gemessen 22,8 s und 25,8 s auf demselben Wirt), und ein
# Schuss, der zu frueh kommt, faellt einfach in die Schreibphase zurueck.
E_S2=$(( T_ENDE + 3000 ))
[ "$E_S2" -gt "$E_S1" ] || E_S2=$(( E_S1 + 4000 ))
alt_n=0
neu_n=0
tot_n=0
i=0
while [ "$i" -lt "$SCHUESSE" ]; do
    i=$((i+1))
    dienst "$OUT/netz2" || bad "Gegenstelle"
    cp -f "$OUT/basis.img" "$OUT/ziel.img"
    # Der Zeitpunkt kommt aus den GEMESSENEN Marken (siehe oben):
    # ungerade Schuesse gleichmaessig ueber den ganzen Vorgang, gerade
    # Schuesse dicht in die Schreibphase.
    if [ $(( i % 3 )) = 1 ]; then
        # ueber den GANZEN Vorgang -- auch die Firmware und das Netz
        MS=$(( 500 + (i * (E_MAX - 500)) / SCHUESSE ))
    elif [ $(( i % 3 )) = 2 ]; then
        # dicht in die SCHREIBPHASE: vom gepruefften Paket bis zu dem
        # Augenblick, in dem `opk` fertig geschrieben hat
        MS=$(( E_S0 + (i * (E_S1 - E_S0)) / SCHUESSE ))
    else
        # UND HINTER DAS UMSCHALTEN. Ohne diesen Drittel trifft kein
        # einziger Schuss den Zustand "neu", und der ganze Abschnitt
        # belegt nur, dass eine Maschine ohne Update unveraendert bleibt.
        MS=$(( E_S1 + (i * (E_S2 - E_S1)) / SCHUESSE ))
    fi
    OVMF=$(ls /usr/share/OVMF/OVMF_CODE.fd /usr/share/ovmf/OVMF.fd 2>/dev/null | head -1)
    cp -f /usr/share/OVMF/OVMF_VARS.fd "$OUT/e.vars.fd" 2>/dev/null || true
    {
        echo "timeout: 0"; echo "verbose: yes"; echo
        echo "/OrientOS"; echo "    protocol: multiboot1"
        echo "    path: boot():/osum.mb"
        echo "    cmdline: osum vfs nokbd nosched noproc nofs noring3 $NETZ script=ota einspielen;exit"
    } > "$OUT/e.conf"
    mcopy -o -i "$OUT/ziel.img@@1048576" "$OUT/e.conf" ::/limine.conf 2>/dev/null
    : > "$OUT/e$i.txt"
    $QEMU_X86 -machine pc -cpu "$OSUM_CPU" -m 512 -display none -no-reboot \
        -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF" \
        -drive "if=pflash,format=raw,unit=1,file=$OUT/e.vars.fd" \
        -serial "file:$OUT/e$i.txt" \
        -drive "file=$OUT/ziel.img,format=raw,if=ide,index=0" \
        -netdev user,id=otan0 -device e1000,netdev=otan0,mac=52:54:00:0a:0b:0c \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1 &
    QP=$!
    # Millisekunden warten, dann DEN STECKER ZIEHEN.
    python3 -c "import time;time.sleep($MS/1000.0)"
    kill -9 "$QP" 2>/dev/null
    wait "$QP" 2>/dev/null
    dienst_aus
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' "$OUT/e$i.txt" 2>/dev/null
    # ---- und jetzt: kommt sie hoch, und was hat sie?
    rc=$(lauf "en$i" "opk richten;/apps/hallo.osp/start;opk liste;exit" 400)
    if [ "$rc" != 21 ]; then
        tot_n=$((tot_n+1))
        bad "(e) Schuss $i bei ${MS} ms: die Maschine kommt NICHT mehr hoch (rc=$rc)"
    elif grep -qa "paket-hallo fassung 2" "$OUT/en$i.txt"; then
        neu_n=$((neu_n+1))
    elif grep -qa "paket-hallo fassung 1" "$OUT/en$i.txt"; then
        alt_n=$((alt_n+1))
    else
        tot_n=$((tot_n+1))
        bad "(e) Schuss $i bei ${MS} ms: WEDER die alte NOCH die neue Fassung laeuft"
    fi
done
zahl "(e) Schuesse, nach denen die Maschine ENTWEDER alt ODER neu ist" \
     "$((alt_n + neu_n))" eq "$SCHUESSE"
zahl "(e) davon: nichts dazwischen und kein Ziegelstein" "$tot_n" eq 0
# Der Test, der den Test prueft: ein Fenster, das nur die Firmware
# trifft, wuerde dreissig makellose "alt" liefern und nichts belegen.
zahl "(e) Schuesse, die WIRKLICH nach dem Umschalten lagen (sonst misst das nichts)" \
     "$neu_n" gt 0
zahl "(e) und Schuesse, die davor lagen" "$alt_n" gt 0
echo "        alt=$alt_n  neu=$neu_n  kaputt=$tot_n  (Schuesse zwischen 500 und $E_MAX ms, verdichtet auf $E_S0..$E_S1 ms und $E_S1..$E_S2 ms)"


echo "  $pass gruen, $fail rot"
[ "$fail" = 0 ] || exit 1
exit 0
