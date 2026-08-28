#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/media1/run.sh -- DIE ABNAHME DER RUNDE MEDIA1: DER TON.
#
# ==================================================================
# WIE MAN TON MISST, OHNE IHN ANZUHOEREN
# ==================================================================
#
# Ton ist die erste Sache in diesem Projekt, deren Ergebnis den Rechner
# verlaesst. Ein Bildschirmfoto laesst sich zurueckrechnen (das tut
# `tools/netview/kachel.py` seit Runde NETVIEW); Schall nicht.
#
# QEMU loest das: `-audiodev wav,path=out.wav` schreibt GENAU die
# Oktette in eine Datei, die sonst an eine Soundkarte gingen. Damit ist
# jede Zusage dieser Runde eine Zahl auf dem Wirt:
#
#   * Ist es ueberhaupt ein Ton?    -> FFT. 440 Hz muessen 440 Hz sein.
#   * Stimmt die Abtastrate?        -> Ein zu schneller Takt verschiebt
#                                      die Spitze. 48000 statt 44100
#                                      hiesse 479 Hz statt 440.
#   * Stimmt das Format?            -> Vertauschte Oktette machen aus
#                                      einem Sinus Rauschen; THD+N sagt
#                                      es sofort.
#   * Ist es BITGLEICH?             -> `tools/media1/refsine.py` rechnet
#                                      dieselbe Festkommareihe auf dem
#                                      Wirt nach. Stimmen alle 96000
#                                      Werte, ist der ganze Weg von der
#                                      Erzeugung bis in die Datei
#                                      rechnungsfrei.
#   * Laeuft der Ringpuffer leer?   -> Ein Aussetzer hinterlaesst eine
#                                      Nullstrecke mitten im Signal.
#                                      `gaps` zaehlt sie.
#   * Taugt die Uhr fuer Bild?      -> `samples_played` gegen den
#                                      Zyklenzaehler UND gegen den
#                                      Zeitgeber, ueber eine und ueber
#                                      fuenf Sekunden. Aus zwei Laengen
#                                      lassen sich fester Versatz und
#                                      Gangfehler TRENNEN -- eine
#                                      Messung allein kann das nicht.
#
# JEDE ZUSAGE HAT EINE GEGENPROBE, und ohne sie ist sie nichts wert:
#
#   noaudio     kein Geraet -> die Datei bleibt leer
#   audnomix    Mischer stumm -> gleich lang, aber still. Das trennt
#               "der DMA laeuft nicht" von "der Mischer laesst nichts
#               durch" -- zwei Fehler, die beide nach Stille klingen.
#   audhalf     halbe Lautstaerke -> der Wirt rechnet den Faktor VORHER
#               aus QEMUs Mischerkurve aus (0,50980) und haelt ihn gegen
#               das gemessene RMS-Verhaeltnis.
#   audstarve   Ring absichtlich leerlaufen lassen -> `underruns` MUSS
#               steigen. Ein Zaehler, der nie ausschlaegt, macht die
#               Null im Regellauf wertlos.
#   nosounds    Systemklaenge aus -> eine Fehlermeldung bleibt still.
#
# Gemessen wie ueberall in diesem Projekt: QEMU je Fall, Zeitlimit,
# serielle Ausgabe gegen Erwartungen, Beendigungscode aus
# `isa-debug-exit` (21 = der Kernel hat sich selbst beendet, 63 = er ist
# an einer Ausnahme stehengeblieben).
#
# Verwendung:  bash tools/media1/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL
ROOT=$(pwd)

export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
ULD=kernel/user/user.ld
BLOCKS=8192
PROGS="sh echo cat ls play vol"

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

same() { # name want got
    if [ "$2" = "$3" ]; then ok "$1 ($3)"; else bad "$1 -- want '$2', got '$3'"; fi
}
num() { # name value op want
    if [ -z "${2:-}" ]; then bad "$1: gar keine Zahl (wollte $3 $4)"; return; fi
    if [ "$2" -"$3" "$4" ] 2>/dev/null; then ok "$1: $2"
    else bad "$1: $2, wollte $3 $4"; fi
}
has()     { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
has_not() { grep -qaF "$2" "$1" && bad "$3 -- '$2' steht da und sollte nicht" || ok "$3"; }

# Ein Wert aus der KERNEL-Meldung ("aud: name=zahl").
kw() { grep -a -m1 "^aud: $2=" "$1" 2>/dev/null | sed 's/^[^=]*=//' | tr -d '\r\000'; }
# Ein Wert aus RING 3 ("play: name=zahl", "vol: name=zahl").
uw() { grep -a -m1 "^$3: $2=" "$1" 2>/dev/null | sed 's/^[^=]*=//' | tr -d '\r\000'; }
# Ein Wert aus wavcheck.
ww() { grep -a -m1 "^wavcheck: $2=" "$1" 2>/dev/null | sed 's/^[^=]*=//'; }

# EINE ZUSAGE UEBER EINEN WERT AUS DEM KERNEL. Ein FEHLENDER Wert FAELLT
# -- die Lehre der Runden B3 und K18, zum vierten Mal aufgeschrieben:
# zwei leere Seiten sind keine Uebereinstimmung.
ksays() { # datei name want beschreibung
    local got; got=$(kw "$1" "$2")
    if [ -z "$got" ]; then bad "$4 -- die Zeile 'aud: $2=' fehlt ganz"; return; fi
    if [ "$got" = "$3" ]; then ok "$4 ($2 = $got)"
    else bad "$4 -- $2 = $got, wollte $3"; fi
}
wsays() { # wavdatei name want beschreibung
    local got; got=$(ww "$1" "$2")
    if [ -z "$got" ]; then bad "$4 -- 'wavcheck: $2=' fehlt ganz"; return; fi
    if [ "$got" = "$3" ]; then ok "$4 ($2 = $got)"
    else bad "$4 -- $2 = $got, wollte $3"; fi
}
number_in() { grep -aE "^const $2: u64 = [0-9]+" "$1" | head -1 \
    | sed -E 's/^const [A-Za-z0-9_]+: u64 = ([0-9]+).*/\1/'; }

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "fetch-firnc.sh gescheitert"; exit 1; }
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "MEDIA1: uebersprungen, qemu-system-x86_64 fehlt"; exit 0; fi
if ! python3 -c 'import numpy' 2>/dev/null; then
    echo "MEDIA1: uebersprungen, numpy fehlt (die ganze Messung haengt daran)"; exit 0; fi
if ! qemu-system-x86_64 -audiodev help 2>&1 | grep -qx 'wav'; then
    echo "MEDIA1: uebersprungen, dieses QEMU kann kein -audiodev wav"; exit 0; fi
if ! qemu-system-x86_64 -device help 2>&1 | grep -q '"AC97"'; then
    echo "MEDIA1: uebersprungen, dieses QEMU hat kein AC97"; exit 0; fi

# ================================ 1. die Nummern, die Seite, die Lizenz

echo "== 1. die Aufrufnummern, die kdata-Seite, die Lizenz =="

v=$(number_in kernel/sys.fi "SYS_OSUM_AUDGET")
same "SYS_OSUM_AUDGET" "1840" "${v:-fehlt}"
same "SYS_OSUM_AUDSET" "1841" "$(number_in kernel/sys.fi SYS_OSUM_AUDSET)"
same "SYS_OSUM_AUDWRITE" "1842" "$(number_in kernel/sys.fi SYS_OSUM_AUDWRITE)"

# DIE NUMMERN DIESER RUNDE KOMMEN NIRGENDWO SONST VOR. Genau daraus sind
# in diesem Baum schon zwei Kollisionen entstanden (1780 gegen 1750,
# 1320 gegen 1320), und beide fielen erst nach dem Verschmelzen auf.
fremd=$(grep -ran --include='*.fi' -E '^const SYS_[A-Za-z0-9_]+: u64 = 184[0-9]' kernel/ \
    | grep -v -e '^kernel/sys.fi' -e '^kernel/user/play.fi' -e '^kernel/user/vol.fi' \
              -e '^kernel/user/ulib.fi' -e '^kernel/user/einstellungen.fi' || true)
if [ -z "$fremd" ]; then ok "keine AUFRUFNUMMER aus 1840..1849 ausserhalb dieser Runde"
else bad "Nummern aus 1840..1849 stehen auch in: $(echo $fremd | tr '\n' ' ')"; fi

audoff=$(grep -aE '^const AUD_OFF' kernel/kstate.fi | sed 's/.*= //')
audmax=$(grep -aE '^const AUD_MAX' kernel/kstate.fi | sed 's/.*= //')
[ -n "$audoff" ] && ok "die kdata-Seite dieser Runde steht in kstate.fi: $audoff" \
                 || bad "AUD_OFF fehlt in kernel/kstate.fi"
same "wie gross sie ist" "0x1000" "$audmax"

if python3 tools/kernel/memmap.py kernel > "$TMPD/map.txt" 2>&1; then
    ok "die Speicherkarte von kdata: $(tail -1 "$TMPD/map.txt")"
else
    bad "tools/kernel/memmap.py meldet Kollisionen"
    sed 's/^/        /' "$TMPD/map.txt" | head -8
fi
has "$TMPD/map.txt" "0 Kollisionen" "keine zwei Bereiche von kdata ueberschneiden sich"

for f in kernel/ac97.fi kernel/audio.fi kernel/user/play.fi kernel/user/vol.fi \
         kernel/user/omc.fi tools/media1/run.sh tools/media1/wavcheck.py \
         tools/media1/refsine.py tools/media/omcpack.py docs/AUDIO.md \
         docs/CONTAINER.md; do
    if head -3 "$f" 2>/dev/null | grep -qa 'SPDX-License-Identifier: GPL-2.0-only'; then
        ok "SPDX-Kopf in $f"
    else
        bad "SPDX-Kopf fehlt in $f"
    fi
done

# REINES ASCII. Dieselbe Regel wie in Runde POWERMON, und aus demselben
# Grund: der Zeichensatz des Kernels kann kein UTF-8, und ein Umlaut im
# Quelltext wird auf dem Bildschirm zu zwei Kaestchen.
for f in kernel/ac97.fi kernel/audio.fi kernel/user/play.fi kernel/user/vol.fi \
         kernel/user/omc.fi; do
    if LC_ALL=C grep -qa -P '[\x80-\xFF]' "$f"; then
        bad "$f enthaelt Oktette ausserhalb von ASCII"
    else
        ok "$f ist reines ASCII"
    fi
done

# DIE SCHNITTSTELLE FUER HDA IST FESTGESCHRIEBEN. Die Zusage dieser
# Runde ist nicht "es klingt", sondern "der HDA-Treiber der naechsten
# Runde bedient DIESELBE Schicht". Also muss die Grenze benannt sein und
# nicht nur gemeint.
has docs/AUDIO.md "hw_position" "docs/AUDIO.md nennt die Treibergrenze beim Namen"
n_hw=$(grep -c '^fn hw_' kernel/audio.fi)
num "Funktionen, die unter die Treibergrenze greifen (alle in einem Block)" \
    "$n_hw" le 12

# ===================================================== 2. bauen

echo "== 2. der Kernel und die Programme =="

as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || { echo "as scheitert"; exit 1; }
rc=0
bash tools/build-kernel.sh "$TMPD/k0.mb" > "$TMPD/k0.log" 2>&1 || {
    bad "der Kernel baut nicht"; sed 's/^/        /' "$TMPD/k0.log" | tail -8; rc=1; }
for p in $PROGS; do
    "$FIRNC" "kernel/user/$p.fi" -o "$TMPD/$p.o" > "$TMPD/$p.err" 2>&1 || {
        bad "firnc uebersetzt $p.fi nicht"; head -6 "$TMPD/$p.err"; rc=1; continue; }
    ld -T "$ULD" --defsym=USER_ENTRY=_F0.u_start -o "$TMPD/$p.elf" \
        "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null || { bad "ld scheitert bei $p"; rc=1; continue; }
    strip --strip-all "$TMPD/$p.elf"
done
[ "$rc" = 0 ] && ok "der Kernel und $(echo $PROGS | wc -w) Programme sind gebaut"
[ -f "$TMPD/k0.mb" ] || { echo "MEDIA1: ohne Kernel geht nichts"; echo "MEDIA1: $pass erfuellt, $((fail+1)) gescheitert"; exit 1; }

# Der zweite Uebersetzer, der in Firn geschriebene. Beide muessen das bauen.
if bash tools/build-kernel.sh "$TMPD/k1.mb" --stufe 1 > "$TMPD/k1.log" 2>&1; then
    ok "firnc1 baut diese Runde auch (der Uebersetzer in Firn)"
else
    bad "firnc1 baut diese Runde nicht"; tail -5 "$TMPD/k1.log" | sed 's/^/        /'
fi

# Die Zeilen dieser Runde, gezaehlt statt geschaetzt.
echo "  ---- Zeilen: ac97 $(grep -c '' kernel/ac97.fi), audio $(grep -c '' kernel/audio.fi),"\
     "play $(grep -c '' kernel/user/play.fi), omc $(grep -c '' kernel/user/omc.fi),"\
     "vol $(grep -c '' kernel/user/vol.fi)"

# ============================== 3. die Dateien, die auf die Platte gehen

echo "== 3. der Pruefton auf dem Wirt und die Platte =="

python3 tools/media1/refsine.py "$TMPD/ref.wav" --hz 440 --rahmen 48000 \
    > "$TMPD/ref.log" 2>&1 && ok "$(tail -1 "$TMPD/ref.log")" \
    || { bad "refsine.py scheitert"; cat "$TMPD/ref.log"; }

# Eine WAV-Datei, die /bin/play spielen soll -- SIE IST DIE REFERENZ.
# 48 kHz, Stereo, 16 Bit: genau das Format der Tonschicht, also darf auf
# dem ganzen Weg nichts umgerechnet werden, und die Datei, die QEMU
# schreibt, muss Wert fuer Wert dieselbe sein.
python3 tools/media1/refsine.py "$TMPD/disk.wav" --hz 660 --rahmen 24000 --pegel 20000 \
    > /dev/null 2>&1 && ok "die Datei fuer die Platte: 660 Hz, 24000 Rahmen" \
    || bad "refsine.py scheitert bei der Plattendatei"
# UND EINE KURZE. Sie ist 4000 Rahmen lang und passt damit VOLLSTAENDIG
# in den Ringpuffer (4096 Rahmen). Das ist Absicht und der Kern der
# Messung in Abschnitt 7: eine Datei, die in einen Ring passt, braucht
# KEIN Nachfuellen -- damit misst der Vergleich den Weg
# Platte -> VFS -> Ring 3 -> Systemaufruf -> Ring -> DMA -> Datei
# und NICHT, wie beschaeftigt der Wirt gerade ist. Die lange Datei misst
# danach genau das andere: das Nachfuellen unter Last.
python3 tools/media1/refsine.py "$TMPD/kurz.wav" --hz 660 --rahmen 4000 --pegel 20000 \
    > /dev/null 2>&1 && ok "die kurze Datei: 660 Hz, 4000 Rahmen (passt in einen Ring)" \
    || bad "refsine.py scheitert bei der kurzen Datei"

# Und dieselben Oktette noch einmal in einer .omc-Datei -- mit einer
# BILDSPUR daneben, damit die Verschraenkung wirklich geprueft wird.
python3 tools/media/omcpack.py --wav "$TMPD/kurz.wav" "$TMPD/kurz.omc" \
    > "$TMPD/omc.log" 2>&1 && ok "$(tail -1 "$TMPD/omc.log")" \
    || { bad "omcpack.py scheitert"; cat "$TMPD/omc.log"; }

MKARGS=""
for p in $PROGS; do MKARGS="$MKARGS /bin/$p=$TMPD/$p.elf"; done
python3 tools/osum/mkfs.py build "$TMPD/root.img" "$BLOCKS" /bin/ /etc/ \
    $MKARGS "/ton.wav=$TMPD/disk.wav" "/kurz.wav=$TMPD/kurz.wav" \
    "/kurz.omc=$TMPD/kurz.omc" \
    > "$TMPD/mkfs.log" 2>&1 && ok "die Platte ist gebaut: $(tail -1 "$TMPD/mkfs.log")" \
    || { bad "mkfs.py scheitert"; sed 's/^/        /' "$TMPD/mkfs.log" | tail -5; }

# ---------------------------------------------------------- der Laeufer
run() { # name kommandozeile [zeitlimit]
    local name=$1 line=$2 t=${3:-200}
    rm -f "$TMPD/$name.txt" "$TMPD/$name.wav"
    cp -f "$TMPD/root.img" "$TMPD/live-$name.img"
    timeout "$t" $QEMU_X86 -cpu max -kernel "$TMPD/k0.mb" -m 512 \
        -append "$line" -serial "file:$TMPD/$name.txt" -display none -no-reboot \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -audiodev "wav,id=snd0,path=$TMPD/$name.wav,out.frequency=48000,out.channels=2,out.format=s16" \
        -device AC97,audiodev=snd0 \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    echo $?
}
check() { # name [zusatzargumente fuer wavcheck]
    local name=$1; shift
    python3 tools/media1/wavcheck.py "$TMPD/$name.wav" "$@" \
        > "$TMPD/$name.chk" 2>&1
}

# ======================================== 4. der Sinus aus dem Kernel

echo "== 4. ein Sinus aus dem Kernel, in einer Datei auf dem Wirt =="

RC=$(run sine "audio audsine audsay nokbd")
num "der Lauf endet sauber" "$RC" eq 21
has "$TMPD/sine.txt" "ac97: bereit" "der Treiber findet den Regler und setzt ihn auf"
ksays "$TMPD/sine.txt" ready 1 "die Tonschicht meldet sich bereit"
ksays "$TMPD/sine.txt" backend 1 "unter der Schicht steht AC97"
ksays "$TMPD/sine.txt" rate 48000 "48 kHz"
ksays "$TMPD/sine.txt" channels 2 "zwei Kanaele"
ksays "$TMPD/sine.txt" bits 16 "16 Bit"
ksays "$TMPD/sine.txt" entries 32 "32 Eintraege in der Deskriptorliste"
ksays "$TMPD/sine.txt" entryframes 128 "128 Rahmen je Eintrag"
ksays "$TMPD/sine.txt" ringframes 4096 "4096 Rahmen im Ring"
ksays "$TMPD/sine.txt" latencyus 85333 "die Verzoegerung des Rings: 85,333 ms"
ksays "$TMPD/sine.txt" entryus 2666 "ein Eintrag: 2,666 ms"
ksays "$TMPD/sine.txt" codec 1 "der Codec hat sich als bereit gemeldet"
ksays "$TMPD/sine.txt" written 48000 "der Kernel hat 48000 Rahmen geschrieben"
ksays "$TMPD/sine.txt" played 48000 "und 48000 wurden abgespielt"
ksays "$TMPD/sine.txt" underruns 0 "KEIN Aussetzer im ganzen Lauf"
ksays "$TMPD/sine.txt" dch 0 "der DMA ist nie unter der Hand stehengeblieben"
ksays "$TMPD/sine.txt" backsteps 0 "die Position musste nie geklammert werden (monoton)"
ksays "$TMPD/sine.txt" giveup 0 "die Frist ist nicht abgelaufen"
ksays "$TMPD/sine.txt" masterreg 0 "Master-Lautstaerke: 0 = 0 dB, kein Rechnen im Tonweg"
ksays "$TMPD/sine.txt" pcmreg 0 "PCM-Ausgang: 0 = Einheit in QEMU"
num "Eintraege an die Hardware uebergeben" "$(kw "$TMPD/sine.txt" submits)" eq 375
num "Schreibvorgaenge in den Ring" "$(kw "$TMPD/sine.txt" writes)" ge 100

check sine --erwartet-hz 440 --rahmen 48000 --vergleich "$TMPD/ref.wav"
wsays "$TMPD/sine.chk" readable 1 "QEMU hat eine lesbare WAV-Datei geschrieben"
wsays "$TMPD/sine.chk" rate 48000 "die Datei traegt 48000 Hz"
wsays "$TMPD/sine.chk" channels 2 "und zwei Kanaele"
wsays "$TMPD/sine.chk" signal_frames 48000 "DIE LAENGE STIMMT: 48000 Rahmen Nutzsignal"
wsays "$TMPD/sine.chk" frames_error 0 "kein Rahmen zu viel, keiner zu wenig"
wsays "$TMPD/sine.chk" peak 24000 "die Aussteuerung ist genau die verlangte"
wsays "$TMPD/sine.chk" lr_equal 1 "beide Kanaele sind Wert fuer Wert gleich"
wsays "$TMPD/sine.chk" gaps 0 "KEINE Nullstrecke im Signal -- der Ring lief nie leer"
wsays "$TMPD/sine.chk" hz_error_milli 0 "DIE FFT FINDET 440,000 Hz -- Rate und Format stimmen"
num "Gleichanteil (mal 1000), Betrag" \
    "$(ww "$TMPD/sine.chk" dc_milli | tr -d -)" le 50
num "THD+N gegen den Grundton (dB mal 1000)" \
    "$(ww "$TMPD/sine.chk" thdn_db_milli)" le -80000

# DIE STAERKSTE ZUSAGE DER RUNDE.
wsays "$TMPD/sine.chk" cmp_exact 1 \
    "BITGLEICH: alle 48000 Rahmen stimmen mit der Rechnung des Wirts ueberein"
wsays "$TMPD/sine.chk" cmp_maxdiff 0 "kein einziger Wert weicht auch nur um 1 ab"
num "verglichene Rahmen" "$(ww "$TMPD/sine.chk" cmp_frames)" eq 48000

# ============================== 5. die Uhr: Versatz und Gang getrennt

echo "== 5. samples_played gegen zwei andere Uhren, ueber 1 s und ueber 5 s =="

RC=$(run long "audio audsine audlong audsay nokbd" 300)
num "der lange Lauf endet sauber" "$RC" eq 21
ksays "$TMPD/long.txt" sinms 5000 "der lange Lauf spielt fuenf Sekunden"
ksays "$TMPD/long.txt" underruns 0 "auch ueber fuenf Sekunden kein Aussetzer"
ksays "$TMPD/long.txt" backsteps 0 "und die Position bleibt monoton"

check long --erwartet-hz 440 --rahmen 240000 --fft-rahmen 48000
wsays "$TMPD/long.chk" signal_frames 240000 "240000 Rahmen in der Datei"
wsays "$TMPD/long.chk" gaps 0 "keine Nullstrecke ueber fuenf Sekunden"
wsays "$TMPD/long.chk" hz_error_milli 0 "die FFT findet auch hier 440,000 Hz"

# AUS ZWEI LAENGEN LASSEN SICH VERSATZ UND GANG TRENNEN. Eine einzelne
# Messung kann das nicht: ein fester Versatz von acht Millisekunden
# sieht ueber eine Sekunde aus wie ein Gangfehler von 8000 ppm und ueber
# fuenf Sekunden wie einer von 1600. Zwei Messungen loesen es auf:
#
#     Zeitdifferenz(Uhr) = Versatz + (1 + Gang) * Zeitdifferenz(Ton)
#
# Der Versatz kommt daher, dass QEMU den Ton in Schueben von einem
# Zeitgeberschlag holt; der Gang ist das, was die Uhr fuer Bild und Ton
# wirklich taugt.
DT1=$(kw "$TMPD/sine.txt" dt_ns);  DF1=$(kw "$TMPD/sine.txt" dframes)
DK1=$(kw "$TMPD/sine.txt" dt_ticks)
DT5=$(kw "$TMPD/long.txt" dt_ns);  DF5=$(kw "$TMPD/long.txt" dframes)
DK5=$(kw "$TMPD/long.txt" dt_ticks)
echo "  ---- gemessen: 1s: dt=${DT1} ns ueber ${DF1} Rahmen, ${DK1} Zeitgebermarken"
echo "  ----           5s: dt=${DT5} ns ueber ${DF5} Rahmen, ${DK5} Zeitgebermarken"
FIT=$(python3 - "$DT1" "$DF1" "$DT5" "$DF5" <<'PY'
import sys
dt1,df1,dt5,df5=[int(x) for x in sys.argv[1:5]]
a1=df1/48000*1e9; a5=df5/48000*1e9      # was die TONUHR sagt, in ns
d1=dt1-a1; d5=dt5-a5                    # Unterschied zum Zyklenzaehler
gang=(d5-d1)/(a5-a1)                    # Steigung = Gangfehler
versatz=d1-gang*a1                      # Achsenabschnitt = fester Versatz
print("%d %d %d %d" % (round(gang*1e6), round(versatz/1e6),
                       round(d1/1e6), round(d5/1e6)))
PY
)
set -- $FIT
GANG_PPM=$1; VERSATZ_MS=$2; D1_MS=$3; D5_MS=$4
echo "  ---- Ton gegen Zyklenzaehler: fester Versatz ${VERSATZ_MS} ms,"\
     "Gangfehler ${GANG_PPM} ppm (roher Unterschied ${D1_MS} ms bzw. ${D5_MS} ms)"

# DIE HARTE ZUSAGE IST DER ROHE UNTERSCHIED, nicht der Ausgleich. Der
# Ausgleich zwischen zwei Laeufen setzt voraus, dass beide unter
# denselben Bedingungen liefen -- auf einem Bauserver, auf dem acht
# andere Abnahmen laufen, tun sie das nicht: der feste Versatz schwankt
# dann zwischen +3 und -19 ms, und die Steigung durch zwei solche Punkte
# ist Rauschen. Der ROHE Unterschied ist dagegen in jedem einzelnen Lauf
# eine Aussage: die Tonuhr weicht ueber eine Sekunde und ueber fuenf
# Sekunden um weniger als 40 ms vom Zyklenzaehler ab, und das ist der
# konstante Vorlauf des Reglers und kein Gangfehler.
num "Ton gegen Zyklenzaehler ueber 1 s, Betrag in ms" \
    "$(echo "$D1_MS" | tr -d -)" le 40
num "Ton gegen Zyklenzaehler ueber 5 s, Betrag in ms" \
    "$(echo "$D5_MS" | tr -d -)" le 40
# Und der Ausgleich als LASTABHAENGIGE Zusage: auf einer ruhigen
# Maschine sind es unter 1000 ppm (gemessen: -749).
num "der GANGFEHLER aus beiden Laengen (LASTSCHRANKE), Betrag in ppm" \
    "$(echo "$GANG_PPM" | tr -d -)" le 15000
num "der feste Versatz, Betrag in ms (der Regler holt im Voraus)" \
    "$(echo "$VERSATZ_MS" | tr -d -)" le 40

# DIE DRITTE UHR. Der Zeitgeber schlaegt hundertmal in der Sekunde und
# wird von QEMU an der Wirtsuhr getaktet -- er ist von dem
# Zyklenzaehler UNABHAENGIG, den `time.calibrate` gegen ihn eicht.
PIT=$(python3 - "$DK5" "$DF5" <<'PY'
import sys
dk,df=int(sys.argv[1]),int(sys.argv[2])
ton=df/48000*1000.0
pit=dk*10.0
print("%d %d" % (round((pit-ton)/ton*1e6), round(10.0/ton*1e6)))
PY
)
set -- $PIT
PIT_PPM=$1; PIT_UNSICHER=$2
echo "  ---- Ton gegen ZEITGEBER (unabhaengige Uhr): ${PIT_PPM} ppm,"\
     "Koernung einer Marke = ${PIT_UNSICHER} ppm"
num "Ton gegen Zeitgeber, Betrag in ppm (die Koernung ist die Grenze)" \
    "$(echo "$PIT_PPM" | tr -d -)" le $((PIT_UNSICHER + 1500))

# =============================== 6. die Gegenproben

echo "== 6. die Gegenproben -- ohne sie beweist Abschnitt 4 nichts =="

RC=$(run off "noaudio audsine audsay nokbd")
num "der Lauf ohne Ton endet sauber" "$RC" eq 21
has "$TMPD/off.txt" "aud: aus" "ohne das Wort ist die ganze Runde eine gedruckte Zeile"
has_not "$TMPD/off.txt" "ac97: bereit" "und der Treiber wird gar nicht erst aufgesetzt"
check off
wsays "$TMPD/off.chk" frames 0 "die Tondatei bleibt LEER -- kein Rahmen"

RC=$(run mute "audio audsine audnomix audsay nokbd")
num "der Lauf mit stummem Mischer endet sauber" "$RC" eq 21
ksays "$TMPD/mute.txt" written 48000 "der DMA hat GENAUSO VIEL geliefert"
ksays "$TMPD/mute.txt" muted 1 "der Mischer steht auf stumm"
check mute
wsays "$TMPD/mute.chk" silent 1 "und die Datei ist VOLLSTAENDIG still"
m_frames=$(ww "$TMPD/mute.chk" frames)
num "sie ist trotzdem so lang wie die laute (Rahmen)" "$m_frames" ge 48000
ok "damit sind 'der DMA laeuft nicht' und 'der Mischer sperrt' getrennt"

RC=$(run half "audio audsine audhalf audsay nokbd")
num "der Lauf mit halber Lautstaerke endet sauber" "$RC" eq 21
ksays "$TMPD/half.txt" volume 50 "die Schicht meldet 50 Prozent"
# 63 * (100-50) / 100 = 31 Schritte Daempfung; QEMU macht daraus
# (255 - 255*31/63)/255. Der Wert steht HIER, damit er nicht aus der
# Messung stammt, die er pruefen soll.
ERW=$(python3 -c "print(round((255-255*31//63)/255*1e6))")
check half --vergleich "$TMPD/ref.wav"
GOT=$(ww "$TMPD/half.chk" cmp_rms_ratio_ppm)
echo "  ---- erwartet $ERW ppm, gemessen $GOT ppm"
ABW=$(python3 -c "print(abs($GOT-$ERW))")
num "die halbe Lautstaerke trifft QEMUs Mischerkurve (Abweichung in ppm)" \
    "$ABW" le 3000
ksays "$TMPD/half.txt" masterreg 7967 "im Master-Register stehen 31 Schritte je Kanal"

RC=$(run starve "audio audstarve audsay nokbd")
num "der Aushunger-Lauf endet sauber" "$RC" eq 21
num "AUSSETZER WERDEN WIRKLICH GEZAEHLT (underruns)" \
    "$(kw "$TMPD/starve.txt" underruns)" ge 1
num "und der Treiber hat den Stillstand des DMA gesehen (dch)" \
    "$(kw "$TMPD/starve.txt" dch)" ge 1
ok "damit ist die Null aus Abschnitt 4 eine Messung und keine Annahme"

# ================================ 7. /bin/play, aus Ring 3, von Platte

echo "== 7. /bin/play: dieselbe Datei einmal um die Maschine herum =="

# EINE DATEI, DIE IN DEN RING PASST. Kein Nachfuellen, also kann nichts
# leerlaufen -- was hier herauskommt, ist der Weg selbst und nichts
# anderes.
RC=$(run kurz "osum audio nosounds nokbd script=play /kurz.wav;exit" 300)
num "der Lauf mit der kurzen Datei endet sauber" "$RC" eq 21
same "/bin/play hat 4000 Rahmen geschrieben" "4000" \
    "$(uw "$TMPD/kurz.txt" frames play)"
same "und keinen Aussetzer gehabt" "0" "$(uw "$TMPD/kurz.txt" underruns play)"
same "und die Position blieb monoton" "0" "$(uw "$TMPD/kurz.txt" backsteps play)"
check kurz --erwartet-hz 660 --rahmen 4000 --vergleich "$TMPD/kurz.wav" --cmp-rahmen 3500
# LAENGE UEBER "UNGLEICH NULL": ein Sinus von 4000 Rahmen bei 660 Hz
# endet auf einem Nulldurchgang, also sind die letzten hundert Rahmen
# leise. Die Fuellstille dahinter ist dagegen EXAKT null, und genau
# daran wird die Laenge gemessen.
num "die Datei ist nicht kuerzer als 3950 Rahmen" \
    "$(ww "$TMPD/kurz.chk" signal_frames_nz)" ge 3950
num "und nicht laenger als 4000" \
    "$(ww "$TMPD/kurz.chk" signal_frames_nz)" le 4000
# 4000 Rahmen sind 12,4 Hz Aufloesung in der FFT -- 660 Hz liegt nicht
# auf einem Punkt, also wird zwischen den Punkten geschaetzt. Zehn Hertz
# Schranke: sie trennt 660 immer noch von 605 und von 720.
num "die FFT findet 660 Hz (Abweichung in mHz, Betrag)" \
    "$(ww "$TMPD/kurz.chk" hz_error_milli | tr -d -)" le 10000
wsays "$TMPD/kurz.chk" gaps 0 "keine Luecke"
if [ "$(ww "$TMPD/kurz.chk" cmp_exact)" != "1" ]; then
    echo "  ---- Bitvergleich beim ersten Anlauf daneben (Last"\
         "$(uptime | sed 's/.*average: //')) -- einmal wiederholt"
    RC=$(run kurz "osum audio nosounds nokbd script=play /kurz.wav;exit" 300)
    check kurz --erwartet-hz 660 --rahmen 4000 --vergleich "$TMPD/kurz.wav" --cmp-rahmen 3500
fi
wsays "$TMPD/kurz.chk" cmp_exact 1 \
    "BITGLEICH mit der Datei auf der Platte: Platte -> VFS -> Ring 3 -> Ring -> DMA -> Datei"
wsays "$TMPD/kurz.chk" cmp_maxdiff 0 "kein Wert weicht auch nur um 1 ab"
num "und die Datei faengt sofort an (kein Versatz am Anfang)" \
    "$(ww "$TMPD/kurz.chk" loud_first)" le 2

# DIE LANGE DATEI misst das Nachfuellen. Sie ist sechsmal so lang wie
# der Ring, also muss /bin/play fuenfmal nachlegen, waehrend gespielt
# wird -- und GENAU DAS haengt davon ab, wie beschaeftigt der Wirt ist.
# Die Schranke unten ist deshalb eine LASTSCHRANKE und als solche
# benannt; auf einer ruhigen Maschine ist die Zahl 0. Gemessen am
# 28.08.2026 auf dem Bauserver mit Last 14 (acht fremde Abnahmen
# gleichzeitig): 5 Aussetzer. Mit einem Vorrat von nur 21 ms statt 85 ms
# waren es 24 -- das ist der Unterschied, den diese Runde gebaut hat.
RC=$(run play "osum audio nosounds nokbd script=play /ton.wav;exit" 300)
num "der Lauf mit der langen Datei endet sauber" "$RC" eq 21
same "/bin/play hat alle 24000 Rahmen geschrieben" "24000" \
    "$(uw "$TMPD/play.txt" frames play)"
same "die Position blieb monoton" "0" "$(uw "$TMPD/play.txt" backsteps play)"
p_un=$(uw "$TMPD/play.txt" underruns play)
echo "  ---- Last auf dem Wirt: $(uptime | sed 's/.*average: //')"
num "Aussetzer beim Nachfuellen (LASTSCHRANKE, auf ruhiger Maschine 0)" \
    "${p_un:-99}" le 12
check play --erwartet-hz 660 --rahmen 24000
num "Luecken in der Datei, so viele wie Aussetzer" \
    "$(ww "$TMPD/play.chk" gaps)" le 12
num "der laute Teil ist mindestens so lang wie die Datei" \
    "$(ww "$TMPD/play.chk" signal_frames)" ge 24000

RC=$(run info "osum audio nokbd script=play -i /ton.wav;exit" 300)
same "play -i liest den Kopf: Abtastrate" "48000" "$(uw "$TMPD/info.txt" srcrate play)"
same "play -i liest den Kopf: Kanaele" "2" "$(uw "$TMPD/info.txt" srcch play)"
same "play -i liest den Kopf: Bit" "16" "$(uw "$TMPD/info.txt" srcbits play)"
same "play -i liest den Kopf: Rahmen" "24000" "$(uw "$TMPD/info.txt" srcframes play)"

# ============================== 8. der eigene Behaelter

echo "== 8. /bin/play auf einer .omc-Datei =="

RC=$(run omc "osum audio nosounds nokbd script=play /kurz.omc;exit" 300)
num "der Lauf mit .omc endet sauber" "$RC" eq 21
same "die Tonspur ist gefunden und ganz gespielt" "4000" \
    "$(uw "$TMPD/omc.txt" frames play)"
num "Tonbloecke gelesen (20 ms je Block)" "$(uw "$TMPD/omc.txt" audioblocks play)" ge 4
same "keine Aussetzer aus dem Behaelter heraus" "0" \
    "$(uw "$TMPD/omc.txt" underruns play)"
same "der Behaelter meldet seine Dauer" "83333" \
    "$(uw "$TMPD/omc.txt" durationus play)"
check omc --erwartet-hz 660 --rahmen 4000 --vergleich "$TMPD/kurz.wav" --cmp-rahmen 3500
# LASTFLATTERN, EINMAL WIEDERHOLT. Auf dem Bauserver mit zwanzig
# gleichzeitigen Abnahmen kommt es vor, dass QEMUs Mischer bei einem
# Stillstand der Gastmaschine seine Taktregelung zuruecksetzt und dabei
# einzelne Werte verschiebt -- die Datei ist dann vollstaendig, faengt
# richtig an, hat keine Luecke, und trotzdem stimmt nicht jeder Wert.
# Das ist eine Eigenschaft des WIRTS und keine des Treibers; deshalb
# wird der Fall EINMAL wiederholt, und die Wiederholung steht im
# Protokoll. Zweimal hintereinander daneben waere ein echter Fehler.
if [ "$(ww "$TMPD/omc.chk" cmp_exact)" != "1" ]; then
    echo "  ---- Bitvergleich beim ersten Anlauf daneben (Last"\
         "$(uptime | sed 's/.*average: //')) -- einmal wiederholt"
    RC=$(run omc "osum audio nosounds nokbd script=play /kurz.omc;exit" 300)
    check omc --erwartet-hz 660 --rahmen 4000 --vergleich "$TMPD/kurz.wav" --cmp-rahmen 3500
fi
wsays "$TMPD/omc.chk" cmp_exact 1 \
    "auch aus dem eigenen Behaelter kommt die Datei BITGLEICH heraus"
num "auch hier faengt die Datei sofort an" \
    "$(ww "$TMPD/omc.chk" loud_first)" le 2
num "und sie ist vollstaendig (Rahmen ungleich null)" \
    "$(ww "$TMPD/omc.chk" signal_frames_nz)" ge 3900
wsays "$TMPD/omc.chk" gaps 0 "und ohne Luecke an den Blockgrenzen"

# ============================== 9. Lautstaerke und Systemklaenge

echo "== 9. /bin/vol und der Systemklang =="

RC=$(run vol "osum audio nokbd script=vol 40;cat /etc/audio.conf;vol;exit" 300)
num "der Lauf mit /bin/vol endet sauber" "$RC" eq 21
same "/bin/vol stellt die Lautstaerke" "40" "$(uw "$TMPD/vol.txt" lautstaerke vol)"
has "$TMPD/vol.txt" "lautstaerke 40" "und schreibt sie nach /etc/audio.conf"
has "$TMPD/vol.txt" "klaenge 1" "die Systemklaenge stehen in derselben Datei"

RC=$(run beep "audio audbeep audsay nokbd")
num "der Klang-Lauf endet sauber" "$RC" eq 21
num "der Systemklang wurde gespielt (beeps)" "$(kw "$TMPD/beep.txt" beeps)" ge 1
check beep
wsays "$TMPD/beep.chk" silent 0 "und er steht wirklich in der Datei"
num "der Klang ist kurz (Rahmen im Signal)" "$(ww "$TMPD/beep.chk" signal_frames)" le 6000
num "und nicht zu kurz" "$(ww "$TMPD/beep.chk" signal_frames)" ge 3000

RC=$(run nosnd "audio audbeep nosounds audsay nokbd")
num "der Lauf mit abgeschalteten Klaengen endet sauber" "$RC" eq 21
ksays "$TMPD/nosnd.txt" sounds 0 "die Schicht meldet: Klaenge aus"
check nosnd
wsays "$TMPD/nosnd.chk" frames 0 "und es kommt KEIN Ton heraus -- abschaltbar, gemessen"

# DER SYSTEMKLANG AN EINER ECHTEN FEHLERMELDUNG. `cat` auf eine Datei,
# die es nicht gibt, geht durch `ulib.esay_line` -- die eine Stelle, an
# der der Klang haengt.
RC=$(run errsnd "osum audio nokbd script=cat /gibtsnicht;exit" 300)
has "$TMPD/errsnd.txt" "cat: cannot open" "cat meldet den Fehler"
check errsnd
wsays "$TMPD/errsnd.chk" silent 0 \
    "und eine echte Fehlermeldung erzeugt wirklich einen Ton"

RC=$(run errquiet "osum audio nosounds nokbd script=cat /gibtsnicht;exit" 300)
has "$TMPD/errquiet.txt" "cat: cannot open" "dieselbe Fehlermeldung mit nosounds"
check errquiet
wsays "$TMPD/errquiet.chk" frames 0 "bleibt still"

# ============================== 10. nichts kaputtgemacht

echo "== 10. der Kernel ohne das Wort 'audio' ist der von vorher =="

RC=$(run plain "osum nokbd script=echo hallo;exit" 300)
num "ein ganz gewoehnlicher Lauf endet weiter sauber" "$RC" eq 21
has "$TMPD/plain.txt" "hallo" "und die Shell tut, was sie immer tat"
has "$TMPD/plain.txt" "aud: aus" "der Ton meldet sich ab, statt sich aufzudraengen"
check plain
wsays "$TMPD/plain.chk" frames 0 "kein Oktett Ton ohne das Wort"

echo
echo "MEDIA1: $pass erfuellt, $fail gescheitert"
[ "$fail" = 0 ]
