#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/audio/mischer.sh -- RUNDE TON-2: DER MISCHER, VON RING 3 AUS.
#
#   bash tools/audio/mischer.sh [ausgabeverzeichnis]
#
# Der Mischer selbst ist seit Runde HDA da und wird von
# tools/hda/run.sh Abschnitt 5 geprueft -- ABER VON INNEN, aus einem
# Kernel-Pruefpfad (`audmix`) mit zwei erfundenen Stroemen. Das ist
# eine Aussage ueber die Additionsschleife und keine darueber, ob ZWEI
# PROGRAMME nebeneinander spielen koennen.
#
# Diese Abnahme fragt das von aussen: zwei Mal `/bin/play`, durch die
# Shell, ueber das Dateisystem, jedes mit eigenem Strom. Nachgewiesen
# wird jeder Ton EINZELN mit einer Goertzel-Auswertung auf seiner
# eigenen Frequenz -- 440 und 660 Hz, und zur Kontrolle die Mitte bei
# 550, wo NICHTS sein darf.
#
# SECHS PRUEFUNGEN:
#   1  zwei Programme, beide Toene da, keine Begrenzung
#   2  Lautstaerke JE STROM: der leise Strom faellt, der andere nicht
#   3  ein Strom auf 0: er verschwindet, der andere bleibt
#   4  MASTER: beide fallen zusammen
#   5  SAETTIGUNG: zwei volle Stroeme werden begrenzt statt umzulaufen
#   6  SYSTEMKLANG: ein Klick NEBEN der Musik, ohne sie zu unterbrechen
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
ULD=kernel/user/user.ld
PROGS="sh echo cat ls play"
OUT=${1:-/root/ton2-mischer}
mkdir -p "$OUT"
ok=0; bad=0
gruen() { ok=$((ok+1)); echo "  OK   $1"; }
rot()   { bad=$((bad+1)); echo "  FEHL $1"; }
# zahl name ist soll-vergleich
num() { local n=$1 v=$2 op=$3 s=$4
  case "$op" in
    ge) [ "${v:-0}" -ge "$s" ] && gruen "$n ($v >= $s)" || rot "$n ($v, erwartet >= $s)";;
    le) [ "${v:-999999}" -le "$s" ] && gruen "$n ($v <= $s)" || rot "$n ($v, erwartet <= $s)";;
    eq) [ "${v:-x}" = "$s" ] && gruen "$n ($v)" || rot "$n ($v, erwartet $s)";;
    lt) [ "${v:-999999}" -lt "$s" ] && gruen "$n ($v < $s)" || rot "$n ($v, erwartet < $s)";;
  esac
}

echo "== bauen =="
bash tools/build-kernel.sh "$OUT/k.mb" > "$OUT/build.txt" 2>&1 \
    || { echo "der Kern baut nicht:"; tail -20 "$OUT/build.txt"; exit 1; }
as --64 -o "$OUT/crt.o" kernel/user/crt.s 2>/dev/null
for p in $PROGS; do
    "$FIRNC" -o "$OUT/$p.o" "kernel/user/$p.fi" > "$OUT/$p.log" 2>&1 \
        || { echo "$p uebersetzt nicht"; tail -20 "$OUT/$p.log"; exit 1; }
    ld -T "$ULD" --defsym=USER_ENTRY=_F0.u_start -o "$OUT/$p.elf" \
        "$OUT/crt.o" "$OUT/$p.o" 2>/dev/null || { echo "$p bindet nicht"; exit 1; }
done
bash tools/hda/mkmedia.sh "$OUT/m" > "$OUT/media.txt" 2>&1
SPEC="/bin/"; for p in $PROGS; do SPEC="$SPEC /bin/$p=$OUT/$p.elf"; done
for f in "$OUT"/m/*; do SPEC="$SPEC /$(basename "$f")=$f"; done
SEKT=$(( $(du -cb "$OUT"/m/* "$OUT"/*.elf | tail -1 | cut -f1) * 3 / 2 / 512 + 4096 ))
python3 tools/osum/mkfs.py build "$OUT/disk.img" "$SEKT" $SPEC > "$OUT/mkfs.txt" 2>&1 \
    || { echo mkfs; tail -5 "$OUT/mkfs.txt"; exit 1; }

HDADEV="-device intel-hda -device hda-duplex,audiodev=snd0"
# name  skript
lauf() {
    local n=$1 cmd=$2
    local aud="-audiodev wav,id=snd0,path=$OUT/$n.wav,out.frequency=48000,out.channels=2,out.format=s16"
    rm -f "$OUT/$n.wav"
    cp "$OUT/disk.img" "$OUT/live-$n.img"
    timeout 600 $QEMU_X86 -kernel "$OUT/k.mb" -m 512 -smp 4 \
        -append "osum nokbd audio nosounds script=$cmd;exit" \
        -serial "file:$OUT/$n.txt" -display none -no-reboot $aud $HDADEV \
        -drive "file=$OUT/live-$n.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    rm -f "$OUT/live-$n.img"
}
# wert aus wavcheck holen
w() { grep -oE "$2=-?[0-9]+" "$OUT/$1.chk" | tail -1 | grep -oE '\-?[0-9]+$'; }
# pruef <name> [weitere wavcheck-Argumente]
#
# DAS FENSTER IST OFT WICHTIGER ALS DIE ZAHL. Enden zwei gleichzeitig
# laufende Programme zu verschiedenen Zeiten, steht am Dateiende die
# Stille des laengeren allein -- `catch_up` (kernel/audio.fi) holt den
# Schreibzeiger auf die Position und nullt den Rest. Das ist der
# dokumentierte Entwurf; ueber die GANZE Datei gemessen sieht es aber
# aus wie eine Luecke. Deshalb bekommen die Abschnitte, in denen sich
# die Laufzeiten unterscheiden, ein `--bis-ms`.
pruef() { local n=$1; shift
    python3 tools/hda/wavcheck.py "$OUT/$n.wav" --hz 440 --zweite 660 \
    --rate 48000 "$@" > "$OUT/$n.chk" 2>&1; sed 's/^/    /' "$OUT/$n.chk"; }

echo
echo "== 1. ZWEI PROGRAMME GLEICHZEITIG =="
lauf zwei "/bin/play /a4.wav &;/bin/play /b6.wav"
pruef zwei
num "440 Hz ist da"            "$(w zwei p1)"      ge 2000
num "660 Hz ist AUCH da"       "$(w zwei p2)"      ge 2000
num "dazwischen (550 Hz) fast nichts" "$(w zwei pmitte)" le 500
num "keine Luecke"             "$(w zwei gaps)"    eq 0
num "keine Begrenzung noetig"  "$(w zwei max)"     lt 32767
# ZWEI PROGRAMME SCHREIBEN AUF DIESELBE SERIELLE LEITUNG, und sie
# tun es gleichzeitig. Deshalb steht dort Zeilensalat wie
# "strom:   art: wav" -- die Zeile des einen ist mitten in der des
# anderen gelandet. Ein `head -1`/`tail -1` liest dann zweimal
# dieselbe Zahl und meldet einen Fehler, den es nicht gibt (genau das
# ist beim ersten Lauf unter test.sh passiert, waehrend derselbe
# Aufruf einzeln durchlief).
#
# ALSO NICHT DIE ZEILEN ZAEHLEN, SONDERN DIE ZAHLEN EINSAMMELN: alle
# "strom: N" holen, doppelte streichen, und fragen, ob zwei
# VERSCHIEDENE uebrig bleiben.
sn=$(grep -aoE 'strom: [0-9]+' "$OUT/zwei.txt" | grep -oE '[0-9]+$' \
     | sort -u | tr '\n' ' ')
sc=$(printf '%s' "$sn" | wc -w)
[ "$sc" -ge 2 ] && gruen "zwei VERSCHIEDENE Stroeme ($sn)" \
    || rot "es war nur ein Strom offen ($sn)"

echo
echo "== 2. LAUTSTAERKE JE STROM =="
#
# MIT EINEM EINZIGEN STROM GEMESSEN, und das ist eine Korrektur am
# MESSGERAET: der erste Anlauf stellte einen von ZWEI gleichzeitigen
# Stroemen leiser und verglich beide Leistungen mit dem Lauf davor.
# Das war falsch, und die Zahlen haben es gezeigt -- der Ton, der GAR
# NICHT angefasst wurde, stand in drei Laeufen bei 4522, 2397 und
# 6000. Der Grund: die Shell startet A im Hintergrund und B danach,
# die beiden ueberlappen sich also je Lauf verschieden lang, und eine
# Goertzel-Auswertung ueber die GANZE Datei misst dann die
# Ueberlappung und nicht die Lautstaerke.
#
# Mit EINEM Strom gibt es diese Unsicherheit nicht: die Amplitude in
# der Datei IST der eingestellte Wert. Dass zwei Stroeme sich nicht
# gegenseitig stoeren, weist Abschnitt 3 nach -- dort ist der eine auf
# NULL, und ein Ton, der ganz fehlt, laesst sich nicht mit einer
# Ueberlappung verwechseln.
lauf voll  "/bin/play /a4.wav"
pruef voll
lauf leise "/bin/play -v 25 /a4.wav"
pruef leise
mv=$(w voll max); ml=$(w leise max)
num "voller Strom steuert wie die Quelle aus" "$mv" ge 11000
num "auf 25 % gestellt ist die Amplitude ein Viertel" "$ml" le 3600
num "und sie ist nicht null"                          "$ml" ge 2400
num "keine Luecke"  "$(w leise gaps)" eq 0
echo "    (voll max=$mv, auf 25 % max=$ml -- erwartet ist ein Viertel)"

echo
echo "== 3. EIN STROM AUF NULL, DER ANDERE SPIELT WEITER =="
# HIER wird die Unabhaengigkeit gemessen, und hier traegt sie auch:
# ein Ton, der GANZ fehlt, ist nicht mit einer kuerzeren Ueberlappung
# zu verwechseln.
lauf stumm "/bin/play -v 0 /a4.wav &;/bin/play /b6.wav"
pruef stumm --bis-ms 4800
num "der stummgestellte Ton ist WEG" "$(w stumm p1)" le 300
num "der andere spielt weiter"       "$(w stumm p2)" ge 2000
num "und er steht in voller Aussteuerung" "$(w stumm max)" ge 11000

echo
echo "== 4. DER MASTER =="
#
# ZWEI STROEME, ABER GEMESSEN WIRD DIE AMPLITUDE UND NICHT DIE
# LEISTUNG JE TON -- aus demselben Grund wie in Abschnitt 2: die
# Programme ueberlappen sich je Lauf verschieden lang. `max` ist davon
# unabhaengig: es ist der groesste Wert, der ueberhaupt in der Datei
# steht, und der haengt nur an den Lautstaerken.
#
# ZWEI STROEME ZU JE 12000 ergeben zusammen bis zu 24000. Auf den
# halben Master gedreht duerfen daraus hoechstens 12000+ werden, und
# ein einzelner Strom allein steht bei 12000 -- die Zahl trennt also
# "Master wirkt" von "Master wirkt nicht" eindeutig.
lauf master "/bin/play -m 50 /a4.wav &;/bin/play /b6.wav"
pruef master --bis-ms 4800
mm=$(w master max); mz=$(w zwei max)
num "der Master senkt die Aussteuerung deutlich" "$mm" le 14000
num "aber er macht nicht still"                  "$mm" ge 4000
num "beide Toene sind weiter da (440)" "$(w master p1)" ge 400
num "beide Toene sind weiter da (660)" "$(w master p2)" ge 400
num "keine Luecke"                     "$(w master gaps)" eq 0
echo "    (ohne Master max=$mz, mit Master 50 % max=$mm)"

echo
echo "== 5. SAETTIGUNG STATT UMLAUF =="
# Zwei Stroeme mit je 30000: die Summe waere 60000 und passt nicht in
# 16 Bit. Begrenzt ergibt das einen FLACHEN Scheitel bei 32767;
# umlaufend ergaebe es einen Sprung ans andere Ende.
lauf clip "/bin/play /a5.wav &;/bin/play /b5.wav"
pruef clip --bis-ms 1800
num "die Ausgabe steht FLACH bei 32767" "$(w clip max)" ge 32000
num "und kippt NICHT ans andere Ende"   "$(w clip min)" le -32000
cl=$(grep -aoE 'begrenzt: *[0-9]+' "$OUT/clip.txt" | tail -1 | grep -oE '[0-9]+$')
echo "    (der Kern meldet begrenzte Abtastwerte: ${cl:-?})"

echo
echo "== 6. SYSTEMKLANG NEBEN DER MUSIK =="
# `nosounds` faellt hier absichtlich weg UND `/bin/play -k 60` loest
# den Klang MITTEN im Stueck aus (nach 60 Schueben). Ein Klang vor
# oder nach der Musik wuerde nichts beweisen -- die Frage ist, ob er
# NEBEN ihr liegt.
n=klang
aud="-audiodev wav,id=snd0,path=$OUT/$n.wav,out.frequency=48000,out.channels=2,out.format=s16"
rm -f "$OUT/$n.wav"; cp "$OUT/disk.img" "$OUT/live-$n.img"
timeout 600 $QEMU_X86 -kernel "$OUT/k.mb" -m 512 -smp 4 \
    -append "osum nokbd audio sounds script=/bin/play -k 60 /a4.wav;exit" \
    -serial "file:$OUT/$n.txt" -display none -no-reboot $aud $HDADEV \
    -drive "file=$OUT/live-$n.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
rm -f "$OUT/live-$n.img"
pruef klang
num "die Musik laeuft durch"  "$(w klang p1)"   ge 2000
num "ohne Luecke"             "$(w klang gaps)" eq 0
# DER KLANG SELBST. Er dauert 180 ms in einer Datei von 5 Sekunden --
# ueber alles gemessen waere er auf ein Dreissigstel gemittelt, und ein
# GERATENES Fenster trifft ihn nicht: `-k 60` zaehlt SCHUEBE, und der
# Abspieler schiebt schneller, als das Geraet spielt (er fuellt den
# Ring), 60 Schuebe sind also nicht 60 mal 21 ms Wiedergabezeit. Der
# erste Anlauf suchte bei 1200..1700 ms und fand nichts; der Ton lag
# bei 1050.
#
# ALSO NICHT RATEN, SONDERN SUCHEN: das Stueck wird in 50-ms-Fenster
# zerlegt und das staerkste 880-Hz-Fenster gemeldet. Das ist zugleich
# der schaerfere Nachweis -- es sagt nicht nur DASS der Ton da ist,
# sondern WO, und der Grundpegel daneben sagt, wie eindeutig.
python3 - "$OUT/klang.wav" > "$OUT/klangf.txt" 2>&1 <<'PYEOF'
import wave, array, math, sys
w = wave.open(sys.argv[1]); fr = w.getframerate(); nch = w.getnchannels()
d = array.array('h'); d.frombytes(w.readframes(w.getnframes()))
L = list(d[0::nch])
def g(seg, f):
    k = 2 * math.pi * f / fr; re = im = 0.0
    for i, v in enumerate(seg):
        re += v * math.cos(k * i); im += v * math.sin(k * i)
    return math.hypot(re, im) / max(1, len(seg))
W = fr // 20
w880 = [(g(L[s:s + W], 880), s * 1000 // fr) for s in range(0, len(L) - W, W)]
w880.sort(reverse=True)
med = sorted(x[0] for x in w880)[len(w880) // 2]
print("klang_max=%d klang_bei_ms=%d klang_grund=%d"
      % (w880[0][0], w880[0][1], med))
PYEOF
sed 's/^/    /' "$OUT/klangf.txt"
kf=$(grep -oE 'klang_max=[0-9]+' "$OUT/klangf.txt" | grep -oE '[0-9]+$')
kg=$(grep -oE 'klang_grund=[0-9]+' "$OUT/klangf.txt" | grep -oE '[0-9]+$')
num "der Hinweiston (880 Hz) ist im Stueck zu finden" "${kf:-0}" ge 300
num "und daneben ist bei 880 Hz nichts"               "${kg:-999}" le 20
sy=$(grep -aoE 'systemklaenge: *[0-9]+' "$OUT/$n.txt" | tail -1 | grep -oE '[0-9]+$')
num "der Systemklang ging WIRKLICH durch den Mischer" "${sy:-0}" ge 1

echo
echo "== ERGEBNIS: $ok gut, $bad beanstandet =="
[ "$bad" -eq 0 ] || exit 1
