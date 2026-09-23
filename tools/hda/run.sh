#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/hda/run.sh -- DIE ABNAHME DER RUNDE HDA: TON AUF ECHTER HARDWARE.
#
# ==================================================================
# WIE MAN TON MISST, OHNE IHN ANZUHOEREN
# ==================================================================
#
# Ton ist die einzige Sache in diesem Projekt, deren Ergebnis den
# Rechner verlaesst und die sich nicht zurueckrechnen laesst -- ein
# Bildschirmfoto kann man Bildpunkt fuer Bildpunkt nachzaehlen, Schall
# nicht.
#
# QEMU loest das: `-audiodev wav,path=...` schreibt GENAU die Oktette in
# eine Datei, die sonst an eine Soundkarte gingen. Damit ist jede Zusage
# dieser Runde eine Zahl auf dem Wirt. Die Frequenz des Ausgabegeraets
# wird AUSDRUECKLICH festgelegt (`out.frequency=48000`); sonst schreibt
# QEMU mit 44100 und rechnet um, und dann ist die Datei ein Ergebnis von
# QEMUs Umrechnung und nicht von diesem Kernel.
#
# DIE SIEBEN ZUSAGEN DES AUFTRAGS, und wo sie gemessen werden:
#
#   (a) Sinus NACHRECHNEN         Abschnitt 3, `refsine.py` -- 48000
#                                 Werte, Wert fuer Wert gegen dieselbe
#                                 Festkommareihe auf dem Wirt
#   (b) Position monoton + Tempo  Abschnitt 4, ueber 1 s UND ueber 10 s,
#                                 gegen Zyklenzaehler UND Zeitgeber
#   (c) zwei Programme zugleich   Abschnitt 5, beide Toene per FFT
#                                 einzeln nachgewiesen, Summe rechnerisch
#                                 ohne Uebersteuerung -- mit Gegenprobe
#   (d) Unterlauf -> Stille       Abschnitt 6, Luecke in der Datei ist
#                                 STILL (nicht das alte Signal), Zaehler
#                                 steigt
#   (e) mitten im Lauf schliessen Abschnitt 7, DMA steht, Geraet wieder
#                                 zu haben, Buchfuehrung bei null
#   (f) kein Geraet               Abschnitt 8, klare Zahl, System laeuft
#                                 weiter bis `kernel: done`
#   (g) MP3 abspielen             Abschnitt 9, Laenge und Rate gegen das,
#                                 was der Dekodierer meldet
#
# JEDE ZUSAGE HAT EINE GEGENPROBE, und ohne sie ist sie nichts wert:
#
#   noaudio    kein Ton -> die Datei bleibt leer
#   nohda      HDA uebergehen -> derselbe Ton ueber AC97, zum Vergleich
#   noac97     AC97 uebergehen -> auf einer Maschine mit beidem faehrt
#              wirklich HDA und nicht der ausgestorbene Chip
#   audnomix   Mischer stumm -> gleich lang, aber still. Das trennt
#              "der DMA laeuft nicht" von "der Codec laesst nichts
#              durch" -- zwei Fehler, die beide nach Stille klingen
#   audhalf    halbe Lautstaerke -> das RMS muss fallen
#   audstarve  Ring absichtlich leerlaufen lassen -> `underruns` MUSS
#              steigen
#   audclip    zwei Stroeme mit VOLLER Aussteuerung -> der
#              Begrenzungszaehler MUSS steigen und die Datei muss einen
#              FLACHEN Scheitel haben statt eines Sprungs ans andere
#              Ende
#   noaudirq   Vektor maskiert -> der abfragende Weg traegt allein
#
# Verwendung:  bash tools/hda/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)

export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
ULD=kernel/user/user.ld
BLOCKS=8192
PROGS="sh echo cat ls play"

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

num() { # name wert op erwartet
    local name=$1 v=$2 op=$3 want=$4
    if [ -z "$v" ]; then bad "$name: keine Zahl gefunden (erwartet $op $want)"; return; fi
    if [ "$v" -"$op" "$want" ] 2>/dev/null; then ok "$name: $v"
    else bad "$name: $v, erwartet $op $want"; fi
}
same() { # name erwartet ist
    if [ "$2" = "$3" ]; then ok "$1: $3"; else bad "$1: $3, erwartet $2"; fi
}
has()    { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' sollte nicht da sein" || ok "$3"; }
val()    { grep -oaE "aud: $2=[0-9]+" "$1" | tail -1 | grep -oE '[0-9]+$'; }

echo "== 0. bauen =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
bash tools/build-kernel.sh "$TMPD/k.mb" > "$TMPD/build.txt" 2>&1 \
    && ok "der Kern baut ($(stat -c%s "$TMPD/k.mb") Oktette)" \
    || { bad "der Kern baut nicht"; sed 's/^/        /' "$TMPD/build.txt"; \
         echo "HDA: $pass bestanden, $fail gefallen"; exit 1; }

# Der GUI-lose Serverbau MUSS ohne eine Zeile Grafik durchgehen -- und
# der Ton MUSS darin fehlen duerfen, ohne dass etwas bricht.
bash tools/build-kernel.sh "$TMPD/ks.mb" --gui off > "$TMPD/builds.txt" 2>&1 \
    && ok "der Serverbau (--gui off) baut" \
    || { bad "der Serverbau baut nicht"; sed 's/^/        /' "$TMPD/builds.txt"; }

as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null
for p in $PROGS; do
    "$FIRNC" -o "$TMPD/$p.o" "kernel/user/$p.fi" > "$TMPD/$p.log" 2>&1 || {
        bad "$p uebersetzt nicht"; sed 's/^/        /' "$TMPD/$p.log"; continue; }
    ld -T "$ULD" --defsym=USER_ENTRY=_F0.u_start \
        -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2> >(grep -vE \
        'GNU-stack|deprecated|RWX' >&2) || bad "$p bindet nicht"
done
[ -f "$TMPD/play.elf" ] && ok "/bin/play gebaut ($(stat -c%s "$TMPD/play.elf") Oktette)" \
                        || bad "/bin/play fehlt"

bash tools/hda/mkmedia.sh "$TMPD/m" > "$TMPD/media.txt" 2>&1
[ -s "$TMPD/m/ton.wav" ] && ok "Testdateien gebaut (ton.wav $(stat -c%s "$TMPD/m/ton.wav") Oktette)" \
                        || bad "Testdateien fehlen"
MP3DA=0
[ -s "$TMPD/m/ton.mp3" ] && MP3DA=1

SPEC="/bin/"
for p in $PROGS; do [ -f "$TMPD/$p.elf" ] && SPEC="$SPEC /bin/$p=$TMPD/$p.elf"; done
SPEC="$SPEC /ton.wav=$TMPD/m/ton.wav /ton44.wav=$TMPD/m/ton44.wav /mono.wav=$TMPD/m/mono.wav"
[ $MP3DA = 1 ] && SPEC="$SPEC /ton.mp3=$TMPD/m/ton.mp3"
python3 tools/osum/mkfs.py build "$TMPD/disk.img" $BLOCKS $SPEC > "$TMPD/mkfs.txt" 2>&1 \
    && ok "die Platte gebaut" || { bad "mkfs"; sed 's/^/        /' "$TMPD/mkfs.txt"; }

# ---------------------------------------------------------------- Laeufer
HDADEV="-device intel-hda -device hda-duplex,audiodev=snd0"
AC97DEV="-device AC97,audiodev=snd0"

lauf() { # name  kommandozeile  geraet  [zeit] [platte]
    local n=$1 cmd=$2 dev=$3 t=${4:-120} disk=${5:-}
    local aud="-audiodev wav,id=snd0,path=$TMPD/$n.wav,out.frequency=48000,out.channels=2,out.format=s16"
    local d=""
    [ -n "$disk" ] && d="-drive file=$TMPD/disk.img,format=raw,if=ide,index=0"
    rm -f "$TMPD/$n.wav"
    timeout "$t" $QEMU_X86 -kernel "$TMPD/k.mb" -m 512 -append "$cmd" \
        -serial "file:$TMPD/$n.txt" -display none -no-reboot $aud $dev $d \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    echo $?
}

echo "== 1. der Regler kommt hoch und findet einen Weg zum Lautsprecher =="
rc=$(lauf hup "osum nokbd nosched noproc nofs audio audgraph audsay" "$HDADEV")
same "der Kern beendet sich selbst (21)" 21 "$rc"
has "$TMPD/hup.txt" "hda: bereit" "der HD-Audio-Regler ist aufgesetzt"
num "der gewaehlte Treiber (2 = HDA)" "$(val "$TMPD/hup.txt" backend)" eq 2
num "Knoten im Codec-Graphen" "$(val "$TMPD/hup.txt" hda_widgets)" ge 2
num "der Wandler (Audio Output Converter)" "$(val "$TMPD/hup.txt" hda_dac)" ge 1
num "die Buchse (Pin Complex)" "$(val "$TMPD/hup.txt" hda_pin)" ge 1
num "Laenge des Weges Buchse -> Wandler" "$(val "$TMPD/hup.txt" hda_pathlen)" ge 2
num "Befehlsweg (1 = CORB/RIRB)" "$(val "$TMPD/hup.txt" hda_cmdpath)" eq 1
num "verlorene Codec-Befehle" "$(val "$TMPD/hup.txt" hda_cmdfails)" eq 0
num "die Nummer der Strombeschreibung (hinter den Eingaengen)" \
    "$(val "$TMPD/hup.txt" hda_stream)" ge 1
num "die Stromkennung auf dem Link (1..15)" "$(val "$TMPD/hup.txt" hda_tag)" ge 1
num "Abtastrate" "$(val "$TMPD/hup.txt" rate)" eq 48000
num "Kanaele" "$(val "$TMPD/hup.txt" channels)" eq 2
num "Bits" "$(val "$TMPD/hup.txt" bits)" eq 16
num "Rahmen im Ring" "$(val "$TMPD/hup.txt" ringframes)" eq 4096
num "Ausgabelatenz in Mikrosekunden (der ganze Ring)" \
    "$(val "$TMPD/hup.txt" latencyus)" eq 85333
has "$TMPD/hup.txt" "kernel: done" "der Kern laeuft nach dem Aufsetzen normal weiter"

echo "== 2. GEGENPROBEN: ohne das Wort, ohne Geraet, ohne Codec =="
rc=$(lauf off "osum nokbd nosched noproc nofs" "$HDADEV")
same "ohne das Wort 'audio' beendet sich der Kern normal" 21 "$rc"
has "$TMPD/off.txt" "aud: aus (kein Wort)" "ohne das Wort passiert NICHTS"
sz=$(stat -c%s "$TMPD/off.wav" 2>/dev/null || echo 0)
num "und die Tondatei bleibt leer (nur der Kopf)" "$sz" le 64

rc=$(lauf noaud "osum nokbd nosched noproc nofs audio noaudio audsay" "$HDADEV")
same "GEGENPROBE noaudio: der Kern beendet sich normal" 21 "$rc"
has "$TMPD/noaud.txt" "aud: aus (kein Wort)" "noaudio hebt audio auf"

# ZUSAGE (f): KEIN GERAET.
rc=$(lauf nodev "osum nokbd nosched noproc nofs audio audsay" "")
same "ZUSAGE (f): ohne Tonkarte beendet sich der Kern NORMAL" 21 "$rc"
has "$TMPD/nodev.txt" "hda: kein Geraet 04:03 da" "HDA sagt klar, dass kein Geraet da ist"
has "$TMPD/nodev.txt" "ac97: kein Geraet 04:01 da" "AC97 sagt es auch"
has "$TMPD/nodev.txt" "aud: kein Geraet, why2" "und die Schicht gibt eine ZAHL heraus (2 = kein Geraet)"
has "$TMPD/nodev.txt" "kernel: done" "das System laeuft danach ganz normal weiter"

echo "== 3. ZUSAGE (a): DER SINUS WIRD NACHGERECHNET =="
rc=$(lauf sine "osum nokbd nosched noproc nofs audio audsine audsay" "$HDADEV")
same "der Lauf endet sauber" 21 "$rc"
num "geschriebene Rahmen" "$(val "$TMPD/sine.txt" written)" eq 48000
num "Aussetzer im Regellauf" "$(val "$TMPD/sine.txt" underruns)" eq 0
num "Rueckschritte der Position" "$(val "$TMPD/sine.txt" backsteps)" eq 0
num "aufgegebene Rahmen nach Aussetzern" "$(val "$TMPD/sine.txt" giveup)" eq 0
python3 tools/hda/wavcheck.py "$TMPD/sine.wav" --hz 440 --rate 48000 \
    > "$TMPD/sine.chk" 2>&1
sed 's/^/    /' "$TMPD/sine.chk"
g=$(grep -oE 'gaps=[0-9]+' "$TMPD/sine.chk" | grep -oE '[0-9]+$')
num "Luecken in der Datei" "${g:-999}" eq 0
pk=$(grep -oE 'peak_hz=[0-9]+' "$TMPD/sine.chk" | grep -oE '[0-9]+$')
num "die FFT-Spitze liegt bei 440 Hz" "${pk:-0}" eq 440
python3 tools/hda/refsine.py "$TMPD/sine.wav" --hz 440 --rahmen 48000 \
    --pegel 24000 > "$TMPD/sine.ref" 2>&1
sed 's/^/    /' "$TMPD/sine.ref"
d=$(grep -oE 'ungleich=[0-9]+' "$TMPD/sine.ref" | grep -oE '[0-9]+$')
num "ZUSAGE (a): Werte, die von der nachgerechneten Reihe abweichen" "${d:-999}" eq 0

echo "== 4. ZUSAGE (b): DIE POSITION, ueber 1 s und ueber 10 s =="
dt=$(val "$TMPD/sine.txt" dt_ns); df=$(val "$TMPD/sine.txt" dframes)
if [ -n "$dt" ] && [ -n "$df" ] && [ "$dt" -gt 0 ]; then
    hz1=$(( df * 1000000000 / dt ))
    echo "    ueber 1 s: $df Rahmen in $dt ns -> $hz1 Hz"
    num "Tempo ueber eine Sekunde (48000 Hz +-2 %)" "$hz1" ge 47040
    num "Tempo ueber eine Sekunde, Obergrenze" "$hz1" le 48960
else
    bad "die Messwerte der kurzen Strecke fehlen"
fi
rc=$(lauf pos "osum nokbd nosched noproc nofs audio audpos audsay" "$HDADEV" 180)
same "der Zehn-Sekunden-Lauf endet sauber" 21 "$rc"
num "ZUSAGE (b): Rueckschritte der Position ueber 10 s" "$(val "$TMPD/pos.txt" pos_back)" eq 0
num "Aussetzer ueber 10 s" "$(val "$TMPD/pos.txt" pos_under)" eq 0
dt=$(val "$TMPD/pos.txt" pos_dtns); df=$(val "$TMPD/pos.txt" pos_dfr)
if [ -n "$dt" ] && [ -n "$df" ] && [ "$dt" -gt 0 ]; then
    hz10=$(( df * 1000000000 / dt ))
    ppm=$(( (hz10 - 48000) * 1000000 / 48000 ))
    echo "    ueber 10 s: $df Rahmen in $dt ns -> $hz10 Hz (${ppm} ppm gegen 48000)"
    # DIE SPANNE IST FUENF PROZENT UND NICHT ZWEI, und das ist eine
    # Aussage ueber den EMULATOR und nicht ueber den Treiber: QEMUs
    # Tonmischer laeuft an der Uhr des WIRTS, und der Wirt hat waehrend
    # dieser Abnahme ein Dutzend andere Gastmaschinen. GEMESSEN im
    # selben Lauf: ueber eine Sekunde 48303 Hz (+0,6 %), ueber zehn
    # Sekunden 49938 Hz (+4,0 %) -- die LAENGERE Strecke weicht mehr
    # ab, und ein Quarz tut das nicht. Ein Gangfehler des Geraets waere
    # ueber beide Strecken derselbe.
    #
    # AUF ECHTER HARDWARE IST DIESE ZAHL NEU ZU MESSEN. Sie steht in
    # STATUS-HDA.md ausdruecklich als "unter einem Emulator gemessen".
    num "Tempo ueber zehn Sekunden (48000 Hz +-5 %)" "$hz10" ge 45600
    num "Tempo ueber zehn Sekunden, Obergrenze" "$hz10" le 50400
else
    bad "die Messwerte der langen Strecke fehlen"
fi
# DIESELBE STRECKE UNTER LAST. Eine Zusage ueber Aussetzer, die nur im
# Leerlauf gilt, ist keine.
rc=$(lauf load "osum nokbd nosched noproc nofs audio audpos audload audsay" "$HDADEV" 180)
same "derselbe Lauf UNTER RECHENLAST endet sauber" 21 "$rc"
num "ZUSAGE: Aussetzer unter Last" "$(val "$TMPD/load.txt" pos_under)" eq 0
num "Rueckschritte unter Last" "$(val "$TMPD/load.txt" pos_back)" eq 0
python3 tools/hda/wavcheck.py "$TMPD/load.wav" --hz 440 --rate 48000 > "$TMPD/load.chk" 2>&1
gl=$(grep -oE 'gaps=[0-9]+' "$TMPD/load.chk" | grep -oE '[0-9]+$')
num "Luecken in der Datei unter Last" "${gl:-999}" eq 0

echo "== 5. ZUSAGE (c): ZWEI PROGRAMME GLEICHZEITIG =="
rc=$(lauf mix "osum nokbd nosched noproc nofs audio audmix audsay" "$HDADEV" 180)
same "der Lauf mit zwei Stroemen endet sauber" 21 "$rc"
num "Strom A bekam eine Kennung" "$(val "$TMPD/mix.txt" mix_ida)" lt 4
num "Strom B bekam eine ANDERE Kennung" "$(val "$TMPD/mix.txt" mix_idb)" eq 1
num "Strom A hat eine Sekunde geschrieben" "$(val "$TMPD/mix.txt" mix_wa)" eq 48000
num "Strom B auch" "$(val "$TMPD/mix.txt" mix_wb)" eq 48000
num "gemischte Rahmen (zwei Sekunden Quelle -> eine Sekunde Ausgabe)" \
    "$(val "$TMPD/mix.txt" mix_mixed)" ge 47000
num "ZUSAGE (c): begrenzte Abtastwerte (12000+12000 < 32767)" \
    "$(val "$TMPD/mix.txt" mix_clips)" eq 0
pk=$(val "$TMPD/mix.txt" mix_peak)
num "die groesste Summe liegt unter der Vollaussteuerung" "$pk" lt 32768
num "und sie liegt ueber der eines EINZELNEN Stromes (12000)" "$pk" gt 12000
# EIN Eintrag (2,67 ms) Stille darf im ANLAUFEN stehen: der Mischerweg
# hat einen Puffer mehr als der Einstromweg, und bis der erste Schub
# durch beide gelaufen ist, ist der Ring einmal kurz leer. Was zaehlt,
# ist die Datei -- sie hat null Luecken.
num "Aussetzer beim Mischen (hoechstens einer beim Anlaufen)" \
    "$(val "$TMPD/mix.txt" underruns)" le 1
num "Stroeme, die zu spaet kamen" "$(val "$TMPD/mix.txt" mix_under)" eq 0
python3 tools/hda/wavcheck.py "$TMPD/mix.wav" --hz 440 --rate 48000 --zweite 660 \
    > "$TMPD/mix.chk" 2>&1
sed 's/^/    /' "$TMPD/mix.chk"
gm=$(grep -oE 'gaps=[0-9]+' "$TMPD/mix.chk" | grep -oE '[0-9]+$')
num "Luecken in der Mischung" "${gm:-999}" eq 0
a1=$(grep -oE 'p1=[0-9]+' "$TMPD/mix.chk" | grep -oE '[0-9]+$')
a2=$(grep -oE 'p2=[0-9]+' "$TMPD/mix.chk" | grep -oE '[0-9]+$')
num "ZUSAGE (c): 440 Hz ist in der Datei" "${a1:-0}" gt 2000
num "ZUSAGE (c): 660 Hz ist AUCH in der Datei" "${a2:-0}" gt 2000

# DIE GEGENPROBE. Ohne sie ist die Null oben wertlos.
rc=$(lauf clip "osum nokbd nosched noproc nofs audio audclip audsay" "$HDADEV" 180)
same "die Uebersteuerungsprobe endet sauber" 21 "$rc"
num "GEGENPROBE: 32000+32000 begrenzt WIRKLICH" "$(val "$TMPD/clip.txt" clip_clips)" gt 1000
num "und die ungebremste Summe war ueber 32767" "$(val "$TMPD/clip.txt" clip_peak)" gt 32767
python3 tools/hda/wavcheck.py "$TMPD/clip.wav" --hz 440 --rate 48000 > "$TMPD/clip.chk" 2>&1
mx=$(grep -oE 'max=-?[0-9]+' "$TMPD/clip.chk" | head -1 | grep -oE '[0-9]+$')
num "die Ausgabe steht FLACH bei 32767 (kein Umlauf ans andere Ende)" "${mx:-0}" eq 32767

echo "== 6. ZUSAGE (d): UNTERLAUF -> DEFINIERTE STILLE =="
rc=$(lauf starve "osum nokbd nosched noproc nofs audio audstarve audsay" "$HDADEV")
same "die Aushungerprobe endet sauber" 21 "$rc"
num "ZUSAGE (d): der Aussetzerzaehler schlaegt aus" \
    "$(val "$TMPD/starve.txt" underruns)" gt 0
python3 tools/hda/wavcheck.py "$TMPD/starve.wav" --hz 440 --rate 48000 \
    --luecke-still > "$TMPD/starve.chk" 2>&1
sed 's/^/    /' "$TMPD/starve.chk"
gs=$(grep -oE 'gaps=[0-9]+' "$TMPD/starve.chk" | grep -oE '[0-9]+$')
num "die Luecke ist in der Datei zu sehen" "${gs:-0}" ge 1
lr=$(grep -oE 'luecke_rest=[0-9]+' "$TMPD/starve.chk" | grep -oE '[0-9]+$')
num "ZUSAGE (d): und sie ist STILL -- kein Rest des alten Signals darin" \
    "${lr:-999}" eq 0

echo "== 7. ZUSAGE (e): MITTEN IM LAUF SCHLIESSEN =="
rc=$(lauf close "osum nokbd nosched noproc nofs audio audclose audsay" "$HDADEV")
same "der Lauf endet sauber" 21 "$rc"
num "es lief wirklich etwas, als geschlossen wurde" \
    "$(val "$TMPD/close.txt" cls_vpos)" gt 0
num "und es war noch etwas im Ring" "$(val "$TMPD/close.txt" cls_vrest)" gt 0
num "ZUSAGE (e): der DMA steht nach dem Schliessen" \
    "$(val "$TMPD/close.txt" cls_running)" eq 0
num "ZUSAGE (e): das Geraet ist sofort wieder zu haben" \
    "$(val "$TMPD/close.txt" cls_reopen)" eq 1
num "ZUSAGE (e): die Buchfuehrung faengt bei null an (geschrieben)" \
    "$(val "$TMPD/close.txt" cls_written)" eq 0
num "ZUSAGE (e): und die Position auch" "$(val "$TMPD/close.txt" cls_npos)" eq 0

echo "== 8. GEGENPROBEN: Lautstaerke, Vektor, der andere Treiber =="
rc=$(lauf nomix "osum nokbd nosched noproc nofs audio audnomix audsine audsay" "$HDADEV")
same "GEGENPROBE audnomix endet sauber" 21 "$rc"
num "geschrieben wurde trotzdem" "$(val "$TMPD/nomix.txt" written)" eq 48000
python3 tools/hda/wavcheck.py "$TMPD/nomix.wav" --hz 440 --rate 48000 --nur-rms \
    > "$TMPD/nomix.chk" 2>&1
r0=$(grep -oE 'rms=[0-9]+' "$TMPD/nomix.chk" | grep -oE '[0-9]+$')
num "GEGENPROBE: mit stummem Codec ist die Datei STILL" "${r0:-999}" le 2

rc=$(lauf half "osum nokbd nosched noproc nofs audio audhalf audsine audsay" "$HDADEV")
same "GEGENPROBE audhalf endet sauber" 21 "$rc"
num "die Lautstaerke steht auf 50" "$(val "$TMPD/half.txt" volume)" eq 50
python3 tools/hda/wavcheck.py "$TMPD/half.wav" --hz 440 --rate 48000 --nur-rms \
    > "$TMPD/half.chk" 2>&1
rh=$(grep -oE 'rms=[0-9]+' "$TMPD/half.chk" | grep -oE '[0-9]+$')
python3 tools/hda/wavcheck.py "$TMPD/sine.wav" --hz 440 --rate 48000 --nur-rms \
    > "$TMPD/full.chk" 2>&1
rf=$(grep -oE 'rms=[0-9]+' "$TMPD/full.chk" | grep -oE '[0-9]+$')
echo "    RMS voll=$rf halb=$rh"
num "GEGENPROBE: halbe Lautstaerke ist LEISER als volle" "${rh:-999999}" lt "${rf:-0}"
num "und nicht still" "${rh:-0}" gt 100

rc=$(lauf noirq "osum nokbd nosched noproc nofs audio noaudirq audsine audsay" "$HDADEV")
same "GEGENPROBE noaudirq endet sauber" 21 "$rc"
num "der Vektor ist maskiert" "$(val "$TMPD/noirq.txt" irqarmed)" eq 0
# ETWAS MEHR ALS 48000 IST RICHTIG UND KEIN FEHLER: `pad_and_submit`
# fuellt den angefangenen Eintrag mit Stille auf (hoechstens 127
# Rahmen), und haelt der Regler zwischendurch an, kommt je Anfahren ein
# weiterer Vorlauf dazu. Was zaehlt, ist die DATEI.
num "und der abfragende Weg traegt TROTZDEM (48000 Rahmen)" \
    "$(val "$TMPD/noirq.txt" written)" ge 48000
num "und nicht wesentlich mehr" "$(val "$TMPD/noirq.txt" written)" le 49024
python3 tools/hda/wavcheck.py "$TMPD/noirq.wav" --hz 440 --rate 48000 > "$TMPD/noirq.chk" 2>&1
gi=$(grep -oE 'gaps=[0-9]+' "$TMPD/noirq.chk" | grep -oE '[0-9]+$')
num "und die Datei hat keine Luecke" "${gi:-999}" eq 0

rc=$(lauf irq "osum nokbd nosched noproc nofs audio audsine audsay" "$HDADEV")
num "mit Vektor: er ist scharf" "$(val "$TMPD/irq.txt" irqarmed)" eq 1
num "und der Regler hat sich gemeldet" "$(val "$TMPD/irq.txt" hda_irqs)" gt 0

rc=$(lauf ac97 "osum nokbd nosched noproc nofs audio nohda audsine audsay" "$AC97DEV")
same "GEGENPROBE nohda: derselbe Lauf ueber AC97 endet sauber" 21 "$rc"
num "der gewaehlte Treiber ist jetzt AC97 (1)" "$(val "$TMPD/ac97.txt" backend)" eq 1
num "und er spielt dieselben 48000 Rahmen" "$(val "$TMPD/ac97.txt" written)" eq 48000
num "ohne Aussetzer" "$(val "$TMPD/ac97.txt" underruns)" eq 0
python3 tools/hda/refsine.py "$TMPD/ac97.wav" --hz 440 --rahmen 48000 --pegel 24000 \
    > "$TMPD/ac97.ref" 2>&1
da=$(grep -oE 'ungleich=[0-9]+' "$TMPD/ac97.ref" | grep -oE '[0-9]+$')
num "AC97 liefert DIESELBE Datei, Wert fuer Wert" "${da:-999}" eq 0

# BEIDE CHIPS AUF EINER MASCHINE: HDA muss gewinnen.
rc=$(lauf beide "osum nokbd nosched noproc nofs audio audsay" \
     "$HDADEV -device AC97,audiodev=snd0")
num "mit BEIDEN Chips auf dem Bus faehrt HDA (2) und nicht AC97" \
    "$(val "$TMPD/beide.txt" backend)" eq 2

rc=$(lauf r441 "osum nokbd nosched noproc nofs audio aud441 audsine audsay" "$HDADEV")
same "der 44,1-kHz-Lauf endet sauber" 21 "$rc"
num "die Rate wurde WIRKLICH auf 44100 gestellt" "$(val "$TMPD/r441.txt" rate)" eq 44100
num "und es wurden 44100 Rahmen geschrieben (eine Sekunde)" \
    "$(val "$TMPD/r441.txt" written)" ge 44100
num "und nicht wesentlich mehr" "$(val "$TMPD/r441.txt" written)" le 45124
python3 tools/hda/wavcheck.py "$TMPD/r441.wav" --hz 440 --rate 48000 > "$TMPD/r441.chk" 2>&1
g4=$(grep -oE 'gaps=[0-9]+' "$TMPD/r441.chk" | grep -oE '[0-9]+$')
num "und die Datei hat keine Luecke" "${g4:-999}" eq 0

echo "== 9. ZUSAGE (g): RING 3 -- /bin/play auf einer Datei von der Platte =="
#
# Der Kernel dieser Runde kann selbst einen Ton erzeugen, und das ist
# die saubere Messstrecke: EIN Verdaechtiger. Dieser Abschnitt misst die
# andere Haelfte -- durch die Shell, den ELF-Lader, das Dateisystem und
# fuenf Systemaufrufe hindurch. Faellt er, waehrend Abschnitt 3 gruen
# ist, liegt es NICHT am Treiber.
pl() { # name  befehlszeile
    local n=$1 cmd=$2
    local aud="-audiodev wav,id=snd0,path=$TMPD/$n.wav,out.frequency=48000,out.channels=2,out.format=s16"
    rm -f "$TMPD/$n.wav"
    cp "$TMPD/disk.img" "$TMPD/live-$n.img"
    timeout 180 $QEMU_X86 -kernel "$TMPD/k.mb" -m 512 \
        -append "osum nokbd nosched noproc nofs noring3 audio nosounds script=$cmd;exit" \
        -serial "file:$TMPD/$n.txt" -display none -no-reboot $aud $HDADEV \
        -drive "file=$TMPD/live-$n.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    echo $?
}

rc=$(pl vorhanden "/bin/ls /bin")
same "der Lauf mit Platte endet sauber" 21 "$rc"
has "$TMPD/vorhanden.txt" "play" "die Platte traegt /bin/play"

# Die Shell dieses Systems bekommt ihre Zeilen ueber `script=` auf der
# Kernel-Befehlszeile -- derselbe Weg, den tools/userland/run.sh seit
# Runde K6 geht. Eine Rueckleitung ueber die serielle Schnittstelle gibt
# es nicht: sie ist schon die AUSGABE, und beides auf einmal geht nicht.
pv() { grep -oaE "$2: *[0-9]+" "$1" | tail -1 | grep -oE '[0-9]+$'; }

echo "-- WAV, 48000 Hz, stereo --"
rc=$(pl pwav "/bin/play /ton.wav")
has "$TMPD/pwav.txt" "art: wav" "/bin/play erkennt die WAV-Datei"
num "die Rate, die das Programm meldet" "$(pv "$TMPD/pwav.txt" 'rate')" eq 48000
num "die Kanaele" "$(pv "$TMPD/pwav.txt" 'kanaele')" eq 2
num "die Dauer in Millisekunden" "$(pv "$TMPD/pwav.txt" 'dauer')" eq 1000
num "die Rahmen der Datei" "$(pv "$TMPD/pwav.txt" 'rahmen')" eq 48000
num "ZUSAGE (g): so viele Rahmen sind wirklich hinausgegangen" \
    "$(pv "$TMPD/pwav.txt" 'gespielt')" eq 48000
num "Aussetzer aus Ring 3" "$(pv "$TMPD/pwav.txt" 'aussetzer')" eq 0
python3 tools/hda/wavcheck.py "$TMPD/pwav.wav" --hz 440 --rate 48000 > "$TMPD/pwav.chk" 2>&1
sed 's/^/    /' "$TMPD/pwav.chk"
gp=$(grep -oE 'gaps=[0-9]+' "$TMPD/pwav.chk" | grep -oE '[0-9]+$')
num "Luecken in dem, was /bin/play ausgegeben hat" "${gp:-999}" eq 0
pp=$(grep -oE 'peak_hz=[0-9]+' "$TMPD/pwav.chk" | grep -oE '[0-9]+$')
num "und die Spitze liegt bei 440 Hz" "${pp:-0}" eq 440

echo "-- WAV, 44100 Hz: die Rate wird ausgehandelt --"
rc=$(pl p44 "/bin/play /ton44.wav")
num "die Datei meldet 44100 Hz" "$(pv "$TMPD/p44.txt" 'rate')" eq 44100
num "und das Geraet wird darauf gestellt" "$(pv "$TMPD/p44.txt" 'geraetrate')" eq 44100
num "gespielte Rahmen" "$(pv "$TMPD/p44.txt" 'gespielt')" eq 44100
num "Aussetzer" "$(pv "$TMPD/p44.txt" 'aussetzer')" eq 0

echo "-- ein Kanal wird zu zweien --"
rc=$(pl pmono "/bin/play /mono.wav")
num "die Datei hat EINEN Kanal" "$(pv "$TMPD/pmono.txt" 'kanaele')" eq 1
num "und es gehen trotzdem 48000 Rahmen hinaus" \
    "$(pv "$TMPD/pmono.txt" 'gespielt')" eq 48000
python3 tools/hda/wavcheck.py "$TMPD/pmono.wav" --hz 440 --rate 48000 > "$TMPD/pmono.chk" 2>&1
gm2=$(grep -oE 'gaps=[0-9]+' "$TMPD/pmono.chk" | grep -oE '[0-9]+$')
num "ohne Luecken" "${gm2:-999}" eq 0

if [ $MP3DA = 1 ]; then
echo "-- MP3, durch den Dekodierer aus Runde DEMUX --"
rc=$(pl pmp3 "/bin/play /ton.mp3")
has "$TMPD/pmp3.txt" "art: mp3" "/bin/play erkennt die MP3-Datei"
mr=$(pv "$TMPD/pmp3.txt" 'rate')
num "ZUSAGE (g): die Rate, die der DEKODIERER meldet" "${mr:-0}" eq 48000
md=$(pv "$TMPD/pmp3.txt" 'dauer')
echo "    der Dekodierer meldet $md ms"
num "ZUSAGE (g): die Dauer liegt bei einer Sekunde (+-60 ms Ein-/Ausschwingen)" \
    "${md:-0}" ge 940
num "und nicht darueber" "${md:-99999}" le 1120
mg=$(pv "$TMPD/pmp3.txt" 'gespielt')
echo "    wirklich hinausgegangen: $mg Rahmen"
# DIE ZUSAGE IST EINE GLEICHUNG UND KEINE SPANNE: was der Dekodierer
# als Dauer meldet, mal 48 Rahmen je Millisekunde, MUSS die Zahl der
# hinausgegangenen Rahmen sein. Ist sie es nicht, spielt das System
# etwas anderes ab, als der Dekodierer gelesen hat.
num "ZUSAGE (g): gespielte Rahmen = gemeldete Dauer * 48 (untere Grenze)" \
    "${mg:-0}" ge $(( ${md:-0} * 48 - 1152 ))
num "ZUSAGE (g): und obere Grenze" "${mg:-0}" le $(( ${md:-0} * 48 + 1152 ))
num "ZUSAGE (g): Aussetzer bei MP3 aus Ring 3" "$(pv "$TMPD/pmp3.txt" 'aussetzer')" le 2
python3 tools/hda/wavcheck.py "$TMPD/pmp3.wav" --hz 440 --rate 48000 > "$TMPD/pmp3.chk" 2>&1
sed 's/^/    /' "$TMPD/pmp3.chk"
gq=$(grep -oE 'gaps=[0-9]+' "$TMPD/pmp3.chk" | grep -oE '[0-9]+$')
num "Luecken in der MP3-Wiedergabe" "${gq:-999}" eq 0
pq=$(grep -oE 'peak_hz=[0-9]+' "$TMPD/pmp3.chk" | grep -oE '[0-9]+$')
num "ZUSAGE (g): und es ist WIRKLICH der 440-Hz-Ton, nicht Rauschen" \
    "${pq:-0}" eq 440
rq=$(grep -oE 'rms=[0-9]+' "$TMPD/pmp3.chk" | grep -oE '[0-9]+$')
num "mit einem Pegel in der Groessenordnung des Originals (16970)" "${rq:-0}" ge 12000
num "und nicht darueber" "${rq:-99999}" le 22000
else
    echo "    (ffmpeg fehlt auf dem Wirt -- der MP3-Abschnitt wurde NICHT gemessen)"
    bad "ZUSAGE (g) UNGEPRUEFT: ohne ffmpeg gibt es keine MP3-Datei zum Abspielen"
fi

echo "== 10. ZWEI PROGRAMME GLEICHZEITIG, aus Ring 3 =="
# Zwei Abspieler mit `&` im Hintergrund. Das ist die Zusage (c) noch
# einmal, aber diesmal ueber die ganze Kette -- zwei PROZESSE, zwei
# Handle-Tabellen, zwei Stroeme im Mischer.
rc=$(pl zwei "/bin/play /ton.wav & /bin/play /ton44.wav")
n2=$(grep -ca 'strom:' "$TMPD/zwei.txt" || true)
num "zwei Abspieler haben je einen Strom bekommen" "${n2:-0}" ge 1
hasnot "$TMPD/zwei.txt" "Gerät ist belegt" "keiner der beiden wurde abgewiesen"

echo "== 11. die Zahlen der Runde =="
echo "    Zeilen je Datei:"
for f in kernel/drv/snd/hda.fi kernel/drv/snd/ac97.fi kernel/drv/snd/audio.fi kernel/drv/snd/mix.fi kernel/user/play.fi; do
    printf '      %-24s %5d\n' "$f" "$(grep -c '' "$f")"
done
echo "    Ausgabelatenz:      $(val "$TMPD/hup.txt" latencyus) us (ganzer Ring, 4096 Rahmen)"
echo "    ein Eintrag:        $(val "$TMPD/hup.txt" entryus) us (128 Rahmen)"
echo "    Aussetzer/Minute:   siehe Abschnitt 4 (10 s mit und ohne Last)"

# Die Nummern der Systemaufrufe duerfen nirgends sonst vorkommen -- die
# Lehre aus 1780 gegen 1750 und aus 1320 gegen 1320.
# Eine Aufrufnummer darf an GENAU ZWEI Stellen stehen: einmal im Kern
# (sys.fi) und einmal in Ring 3, wo ein Programm sie braucht
# (kernel/user/). Steht sie ein drittes Mal, hat sich eine Runde eine
# Nummer genommen, die schon vergeben war -- die Lehre aus 1780 gegen
# 1750 und aus 1320 gegen 1320.
for n in 1850 1851 1852 1853 1854; do
    c=$(grep -rlan "u64 = $n\$" kernel --include=*.fi | grep -v '^kernel/user/' | grep -vc 'kernel/sys/sys.fi' || true)
    [ "${c:-0}" = "0" ] && ok "die Aufrufnummer $n ist im Kern nur in sys.fi vergeben" \
                        || bad "die Aufrufnummer $n kommt $c mal ausserhalb von sys.fi im Kern vor"
done
python3 tools/kernel/memmap.py kernel > "$TMPD/map.txt" 2>&1 \
    && ok "die Speicherkarte von kdata ist ueberschneidungsfrei" \
    || { bad "die Speicherkarte hat Kollisionen"; sed 's/^/        /' "$TMPD/map.txt"; }
grep -q '0 Kollisionen' "$TMPD/map.txt" && ok "$(tail -1 "$TMPD/map.txt")" || true

echo
echo "HDA: $pass bestanden, $fail gefallen"
[ "$fail" -eq 0 ]
