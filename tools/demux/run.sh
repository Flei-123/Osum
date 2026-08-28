#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/demux/run.sh -- DIE ABNAHME DER RUNDE DEMUX.
#
# Was hier gemessen wird, und woran:
#
#  1. DIE BEHAELTER. `demuxt` liest MP4, Matroska und MP3 und meldet je
#     Spur Art, Codec, Aufloesung, Abtastrate, Kanaele, Dauer, Oktette
#     und Beispielzahl. Jede dieser Zahlen wird gegen `ffprobe` auf dem
#     WIRT gehalten -- nicht gegen eine Erwartung, die jemand hier
#     hingeschrieben hat.
#  2. DER TONDEKODIERER. Dieselbe Datei wird von Osum dekodiert und von
#     ffmpeg dekodiert, und die Abtastwerte werden nebeneinandergelegt:
#     mittlerer und groesster Fehler je Abtastwert, Effektivfehler,
#     Stoerabstand und ein FFT-Vergleich (tools/demux/vergleich.py).
#     "Klingt richtig" kommt in dieser Datei nicht vor.
#  3. WAS KAPUTT IST, STUERZT NICHT AB. Abgeschnittene Dateien, gekippte
#     Oktette, eine geloegene Boxlaenge, eine leere Datei, ein Bild statt
#     eines Films: jeder Fall MUSS ohne Ausnahme und ohne
#     `osum_panic` durchlaufen.
#  4. DIE EHRLICHE MELDUNG. Eine H.264-Datei muss den Codec beim Namen
#     nennen, die Aufloesung, die Dauer und die Datenrate -- und den Ton
#     anbieten, wenn er spielbar ist.
#  5. DIE RECHENLAST, in Prozent EINES Kerns, aus der Zeit des Gastes
#     (100-Hz-Zaehler) gegen die Spieldauer des Stuecks.
#  6. DER GANZE WEG: /bin/play spielt eine MP3 ueber den AC97 aus Runde
#     MEDIA1, QEMU schreibt mit (`-audiodev wav`), und der Wirt prueft
#     das Ergebnis im Spektrum gegen das erzeugte Signal.
#
#   bash tools/demux/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh

export FIRNLIB="$(pwd)/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
ULD=kernel/user/user.ld
PROGS="sh demuxt play"

TMPD=${OSUM_WORK:-$(mktemp -d)}
mkdir -p "$TMPD"
[ -n "${KEEP_TMPD:-}" ] && echo "TMPD=$TMPD"

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() { # name wert op erwartet
    local name=$1 v=$2 op=$3 w=$4
    if [ -z "$v" ]; then bad "$name: keine Zahl gefunden (erwartet $op $w)"; return; fi
    if [ "$v" -"$op" "$w" ] 2>/dev/null; then ok "$name: $v"
    else bad "$name: $v, erwartet $op $w"; fi
}
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' steht da" || ok "$3"; }

command -v ffmpeg >/dev/null 2>&1 || { echo "DEMUX: uebersprungen, kein ffmpeg"; exit 0; }
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "DEMUX: uebersprungen, kein qemu"; exit 0; }

# ------------------------------------------------------- 1. der Bau

echo "== 1. bauen: der Kern, die Tafeln und drei Programme =="
bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "firnc fehlt"; exit 1; }

# Die Zahlentafeln des MP3-Dekodierers werden ERZEUGT. Steht die Quelle
# nicht da, wird die eingecheckte Fassung genommen -- aber dann sagt der
# Lauf es.
PD=${PDMP3:-/tmp/pdmp3.c}
if [ -f "$PD" ]; then
    python3 tools/demux/mktab.py "$PD" "$TMPD/mp3tab.fi" >"$TMPD/mktab.log" 2>&1 \
        && ok "mktab.py: $(sed -n '1p' "$TMPD/mktab.log")" \
        || bad "mktab.py fehlgeschlagen"
    if diff -q "$TMPD/mp3tab.fi" kernel/user/mp3tab.fi >/dev/null 2>&1; then
        ok "die eingecheckte Tafel ist genau das, was der Erzeuger liefert"
    else
        bad "kernel/user/mp3tab.fi weicht vom Erzeuger ab"
    fi
else
    echo "  --    mktab.py nicht nachgerechnet (keine Quelle unter $PD)"
fi

as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s"
bash tools/build-kernel.sh "$TMPD/k.mb" >"$TMPD/kbuild.log" 2>&1 \
    && ok "der Kern ist gebaut ($(stat -c%s "$TMPD/k.mb") Oktette)" \
    || { bad "der Kern baut nicht"; tail -5 "$TMPD/kbuild.log"; }
for p in $PROGS; do
    $FIRNC "kernel/user/$p.fi" -o "$TMPD/$p.o" >"$TMPD/e-$p" 2>&1 \
        || { bad "$p.fi uebersetzt nicht"; head -5 "$TMPD/e-$p"; }
    ld -T "$ULD" --defsym=USER_ENTRY="_F0.u_start" \
        -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>"$TMPD/ld-$p" \
        || bad "$p bindet nicht"
    strip --strip-all "$TMPD/$p.elf" 2>/dev/null
done
[ -f "$TMPD/play.elf" ] && ok "demuxt und play sind gebunden ($(stat -c%s "$TMPD/play.elf") Oktette)"

echo "  Zeilen: media.fi $(wc -l < kernel/user/media.fi), mp4.fi $(wc -l < kernel/user/mp4.fi), mkv.fi $(wc -l < kernel/user/mkv.fi), mp3.fi $(wc -l < kernel/user/mp3.fi), mp3tab.fi $(wc -l < kernel/user/mp3tab.fi) (erzeugt), srt.fi $(wc -l < kernel/user/srt.fi), demuxt.fi $(wc -l < kernel/user/demuxt.fi)"

# --------------------------------------------------- 2. die Testdateien

echo "== 2. die Testdateien, mit ffmpeg auf dem Wirt erzeugt =="
MED="$TMPD/media"
bash tools/demux/mkmedia.sh "$MED" >"$TMPD/mkmedia.log" 2>&1 \
    && ok "mkmedia.sh: $(ls "$MED" | wc -l) Dateien" \
    || { bad "mkmedia.sh fehlgeschlagen"; tail -5 "$TMPD/mkmedia.log"; }

# ---------------------------------------------------------- 3. das Abbild

SPEC="/bin/"
for p in $PROGS; do SPEC="$SPEC /bin/$p=$TMPD/$p.elf"; done
SPEC="$SPEC /w/ /m/"
for f in "$MED"/*; do
    case "$f" in *.raw) continue ;; esac
    SPEC="$SPEC /m/$(basename "$f")=$f"
done
python3 tools/osum/mkfs.py build "$TMPD/disk.img" 32768 $SPEC >"$TMPD/mkfs.log" 2>&1 \
    && ok "ein Abbild mit den Programmen und den Mediendateien" \
    || { bad "mkfs.py"; tail -3 "$TMPD/mkfs.log"; }

lauf() { # name kommandozeile [zusatzargumente fuer qemu]
    local name=$1 zeile=$2
    shift 2
    cp -f "$TMPD/disk.img" "$TMPD/live-$name.img"
    timeout 900 $QEMU_X86 -kernel "$TMPD/k.mb" -m 512 \
        -append "osum ${EXTRA:-} nokbd nosched noproc nofs noring3 script=$zeile;exit" \
        -serial "file:$TMPD/$name.txt" -display none -no-reboot \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 "$@" >/dev/null 2>&1
    local rc=$?
    cp -f "$TMPD/live-$name.img" "$TMPD/after-$name.img"
    return $rc
}

holen() { # abbild pfad ziel
    python3 tools/demux/holen.py "$1" "$2" "$3" >/dev/null 2>&1
}

# ------------------------------------------------- 4. was in den Dateien steht

echo "== 3. die Behaelter: jede Zahl gegen ffprobe =="
FILES="film.mp4 film.mkv ton1.mp3 ton2.mp3 ton3.mp3 ton1.m4a ton1.mka ton1mp3.mp4 vp9.webm stumm.mp4"
CMD=""
for f in $FILES; do CMD="$CMD demuxt /m/$f;"; done
lauf info "${CMD%;}"
RC=$?
num "QEMU-Beendigungscode des Auskunftslaufs" "$RC" eq 21
hasnot "$TMPD/info.txt" "*** EXCEPTION" "keine Ausnahme im Auskunftslauf"
hasnot "$TMPD/info.txt" "osum_panic" "kein osum_panic im Auskunftslauf"

python3 - "$TMPD/info.txt" "$MED" > "$TMPD/pruef.txt" 2>&1 <<'PY'
import json, subprocess, sys, re
log, med = sys.argv[1], sys.argv[2]
txt = open(log, errors="replace").read()
bloecke = {}
cur = None
for line in txt.split("\n"):
    if line.startswith("file "):
        cur = line[5:].strip().split("/")[-1]
        bloecke[cur] = []
    elif cur is not None:
        if line.startswith("done"):
            cur = None
        else:
            bloecke[cur].append(line)

KIND = {1: "video", 2: "audio", 3: "subtitle"}
CODEC = {1: "h264", 2: "hevc", 3: "av1", 4: "vp9", 5: "vp8",
         20: "aac", 21: "mp3", 26: "pcm", 40: "subrip"}

def probe(p):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_streams",
                          "-of", "json", p], capture_output=True, text=True)
    return json.loads(out.stdout)["streams"]

gut, schlecht = 0, 0
def sag(ok, text):
    global gut, schlecht
    if ok: gut += 1; print("  OK    " + text)
    else:  schlecht += 1; print("  FAIL  " + text)

for name, zeilen in bloecke.items():
    trks = []
    for z in zeilen:
        m = re.match(r"trk (\d+) kind=(\d+) codec=(\d+) w=(\d+) h=(\d+) "
                     r"rate=(\d+) ch=(\d+) dur=(\d+) bytes=(\d+) nsamp=(\d+)", z)
        if m:
            trks.append([int(x) for x in m.groups()])
    try:
        st = probe(med + "/" + name)
    except Exception as e:
        sag(False, "%s: ffprobe: %s" % (name, e)); continue
    st = [s for s in st if s.get("codec_type") in ("video", "audio", "subtitle")]
    sag(len(trks) == len(st), "%s: %d Spuren (ffprobe: %d)" % (name, len(trks), len(st)))
    for i, t in enumerate(trks):
        if i >= len(st): break
        s = st[i]
        sag(KIND.get(t[1]) == s["codec_type"],
            "%s trk%d: Art %s" % (name, i, KIND.get(t[1])))
        erw = CODEC.get(t[2], "?")
        sag(erw == s["codec_name"],
            "%s trk%d: Codec %s (ffprobe: %s)" % (name, i, erw, s["codec_name"]))
        if s["codec_type"] == "video":
            sag(t[3] == s["width"] and t[4] == s["height"],
                "%s trk%d: %dx%d" % (name, i, t[3], t[4]))
        if s["codec_type"] == "audio":
            sag(t[5] == int(s["sample_rate"]),
                "%s trk%d: %d Hz" % (name, i, t[5]))
            sag(t[6] == int(s["channels"]),
                "%s trk%d: %d Kanaele" % (name, i, t[6]))
            if "nb_frames" in s:
                nf = int(s["nb_frames"])
                sag(abs(t[9] - nf) <= 2,
                    "%s trk%d: %d Beispiele (ffprobe: %d)" % (name, i, t[9], nf))
        d = float(s.get("duration", 0)) * 1000
        if d > 0:
            sag(abs(t[7] - d) <= 120,
                "%s trk%d: Dauer %d ms (ffprobe: %d ms)" % (name, i, t[7], int(d)))
print("SUMME %d %d" % (gut, schlecht))
PY
sed -n '/^  \(OK\|FAIL\)/p' "$TMPD/pruef.txt"
G=$(grep -c '^  OK' "$TMPD/pruef.txt")
S=$(grep -c '^  FAIL' "$TMPD/pruef.txt")
pass=$((pass + G)); fail=$((fail + S))
[ "$S" -gt 0 ] && sed -n '/^  FAIL/p' "$TMPD/pruef.txt" | head -10

# Untertitel aus Matroska
has "$TMPD/info.txt" "text=Erster Untertitel" "Untertitel 1 aus Matroska"
has "$TMPD/info.txt" "text=Zweiter Untertitel, mit Komma" "Untertitel 2 aus Matroska"
has "$TMPD/info.txt" "text=Dritter" "Untertitel 3 aus Matroska"

# ------------------------------------------------ 5. kaputte Dateien

echo "== 4. was kaputt ist, stuerzt nicht ab =="
BROKEN="kurz.mp4 kurz.mkv kurz.mp3 luege.mp4 luege.mkv kaputt.mp3 muell.bin leer.mp4 unter.srt sig1.wav"
CMD=""
for f in $BROKEN; do CMD="$CMD demuxt /m/$f;"; done
lauf kaputt "${CMD%;}"
RC=$?
num "QEMU-Beendigungscode des Schadenslaufs" "$RC" eq 21
hasnot "$TMPD/kaputt.txt" "*** EXCEPTION" "keine Prozessorausnahme an kaputten Dateien"
hasnot "$TMPD/kaputt.txt" "osum_panic" "keine geprueft-ueberlaufende Rechnung an kaputten Dateien"
n=$(grep -ca '^done$' "$TMPD/kaputt.txt")
num "kaputte Dateien, die vollstaendig durchgelaufen sind" "$n" eq "$(echo $BROKEN | wc -w)"
# Auch der Abspieler selbst darf daran nicht sterben.
CMD=""
for f in $BROKEN; do CMD="$CMD play -i /m/$f;"; done
lauf kaputt2 "${CMD%;}"
RC=$?
num "QEMU-Beendigungscode von /bin/play an kaputten Dateien" "$RC" eq 21
hasnot "$TMPD/kaputt2.txt" "*** EXCEPTION" "play: keine Ausnahme an kaputten Dateien"
hasnot "$TMPD/kaputt2.txt" "osum_panic" "play: kein osum_panic an kaputten Dateien"
# Ein abgeschnittenes MP4 hat keinen moov: das MUSS gesagt werden.
has "$TMPD/kaputt.txt" "fmt none" "eine Datei ohne lesbaren Kopf heisst 'none' und nicht 'geht schon'"

# --------------------------------------- 6. die ehrliche Meldung

echo "== 5. die ehrliche Meldung =="
lauf ehrlich "play -i /m/film.mp4; play -i /m/film.mkv; play -i /m/vp9.webm; play -i /m/stumm.mp4; play -i /m/ton1.mp3"
num "QEMU-Beendigungscode des Meldungslaufs" "$?" eq 21
has "$TMPD/ehrlich.txt" "play: Bildspur nicht dekodierbar" "die Bildspur wird abgelehnt"
has "$TMPD/ehrlich.txt" "H.264 / AVC  320x240  3.0 s" "mit Codecname, Aufloesung und Dauer"
grep -qaE 'H\.264 / AVC  320x240  3\.0 s  [0-9]+ kbit/s' "$TMPD/ehrlich.txt" \
    && ok "und mit der gerechneten Datenrate" || bad "die Datenrate fehlt in der Meldung"
has "$TMPD/ehrlich.txt" "play: spiele nur den Ton dieser Datei" "der Ton wird angeboten, wenn er spielbar ist"
has "$TMPD/ehrlich.txt" "Tonspur nicht dekodierbar, Codec: AAC-LC" "AAC wird beim Namen genannt und abgelehnt"
has "$TMPD/ehrlich.txt" "VP9  160x120" "VP9 wird beim Namen genannt"
has "$TMPD/ehrlich.txt" "play: keine Tonspur darin" "eine stumme Datei sagt, dass sie stumm ist"
hasnot "$TMPD/ehrlich.txt" "*** EXCEPTION" "kein Absturz im Meldungslauf"

# ------------------------------------------- 7. der Tondekodierer

echo "== 6. der Tondekodierer gegen ffmpeg =="
lauf dekod "demuxt -d /w/a.pcm /m/ton1.mp3; demuxt -d /w/b.pcm /m/ton2.mp3; demuxt -d /w/c.pcm /m/ton3.mp3; demuxt -d /w/d.pcm /m/ton1.mka; demuxt -d /w/e.pcm /m/ton1mp3.mp4; demuxt -d /w/f.pcm /m/film.mkv"
RC=$?
num "QEMU-Beendigungscode des Dekodierlaufs" "$RC" eq 21
hasnot "$TMPD/dekod.txt" "osum_panic" "kein osum_panic beim Dekodieren"
hasnot "$TMPD/dekod.txt" "*** EXCEPTION" "keine Ausnahme beim Dekodieren"

pruefe() { # abbildname pfad referenz kanaele name grenze_mittel grenze_max
    local pcm=$1 ref=$2 ch=$3 name=$4 gm=$5 gx=$6
    holen "$TMPD/after-dekod.img" "$pcm" "$TMPD/$name.raw" \
        || { bad "$name: nichts aus dem Abbild geholt"; return; }
    python3 tools/demux/vergleich.py "$TMPD/$name.raw" "$ref" "$ch" \
        --name "$name" --json "$TMPD/$name.json" > "$TMPD/$name.cmp" 2>&1
    cat "$TMPD/$name.cmp"
    local m x
    m=$(python3 -c "import json;print('%.4f'%json.load(open('$TMPD/$name.json'))['mittel'])" 2>/dev/null)
    x=$(python3 -c "import json;print(json.load(open('$TMPD/$name.json'))['max'])" 2>/dev/null)
    local la lb vs nn
    la=$(python3 -c "import json;print(json.load(open('$TMPD/$name.json'))['laenge_osum'])" 2>/dev/null)
    lb=$(python3 -c "import json;print(json.load(open('$TMPD/$name.json'))['laenge_ffmpeg'])" 2>/dev/null)
    vs=$(python3 -c "import json;print(abs(json.load(open('$TMPD/$name.json'))['versatz']))" 2>/dev/null)
    nn=$(python3 -c "import json;print(json.load(open('$TMPD/$name.json'))['n'])" 2>/dev/null)
    if [ -z "$m" ]; then bad "$name: der Vergleich lief nicht"; return; fi
    awk -v m="$m" -v g="$gm" 'BEGIN{exit !(m<g)}' \
        && ok "$name: mittlerer Fehler $m unter $gm" \
        || bad "$name: mittlerer Fehler $m, Grenze $gm"
    num "$name: groesster Fehler" "$x" lt "$gx"
    # Der Versatz ist die Anlaufzeit, die ffmpeg abschneidet und wir
    # nicht -- er darf nicht groesser sein als ein Rahmen plus die 529
    # Abtastwerte der Filterbank.
    num "$name: Versatz gegen ffmpeg in Rahmen" "$vs" lt 1682
    num "$name: verglichene Abtastwerte" "$nn" gt 90000
}

pruefe /w/a.pcm "$MED/ton1.ref.raw"    2 ton1_mp3      1.0 12
pruefe /w/b.pcm "$MED/ton2.ref.raw"    1 ton2_mono48   1.0 12
pruefe /w/c.pcm "$MED/ton3.ref.raw"    2 ton3_stereo   1.0 12
pruefe /w/d.pcm "$MED/ton1mka.ref.raw" 2 mp3_in_mkv    1.0 12
pruefe /w/e.pcm "$MED/ton1.ref.raw"    2 mp3_in_mp4    1.0 12
pruefe /w/f.pcm "$MED/filmmkv.ref.raw" 2 mkv_mit_video 1.0 12

for f in a b c d e f; do :; done
grep -a '^pcm ' "$TMPD/dekod.txt" | sed 's/^/  /'
e=$(grep -a '^pcm ' "$TMPD/dekod.txt" | grep -oaE 'errs=[0-9]+' | cut -d= -f2 | awk '{s+=$1} END{printf "%d", s+0}')
n=$(grep -ca '^pcm ' "$TMPD/dekod.txt")
num "Dateien mit einer pcm-Zeile" "$n" eq 6
num "Dekodierfehler ueber alle sechs Dateien" "${e:-9}" eq 0
c=$(grep -a '^pcm ' "$TMPD/dekod.txt" | grep -oaE 'clamps=[0-9]+' | cut -d= -f2 | awk '{s+=$1} END{printf "%d", s+0}')
num "begrenzte Spektralwerte ueber alle sechs Dateien" "${c:-9}" eq 0

# ------------------------------------------------- 8. die Rechenlast

echo "== 7. die Rechenlast, in Prozent EINES Kerns =="
echo "  Wirtslast vor der Messung: $(uptime | sed 's/.*average: //')"
lauf last "demuxt -n 3 -d /w/z.pcm /m/ton1.mp3"
num "QEMU-Beendigungscode der Lastmessung" "$?" eq 21
LINE=$(grep -a '^pcm ' "$TMPD/last.txt" | tail -1)
echo "  $LINE"
TICKS=$(echo "$LINE" | grep -oaE 'ticks=[0-9]+' | cut -d= -f2)
MAL=$(echo "$LINE" | grep -oaE 'mal=[0-9]+' | cut -d= -f2)
DUR=$(echo "$LINE" | grep -oaE 'durms=[0-9]+' | cut -d= -f2)
if [ -n "$TICKS" ] && [ -n "$DUR" ] && [ "$DUR" -gt 0 ]; then
    PCT=$(( TICKS * 10 * 100 / (MAL * DUR) ))
    echo "  Rechenlast: $TICKS Zecken / $MAL Durchlaeufe = $((TICKS*10/MAL)) ms je $DUR ms Musik = $PCT % eines Kerns"
    echo "  (Wirtslast waehrend der Messung: $(uptime | sed 's/.*average: //'))"
    num "Rechenlast in Prozent eines Kerns" "$PCT" lt 100
else
    bad "die Lastmessung hat keine Zahlen geliefert"
fi

# ------------------------------------ 9. der ganze Weg: wirklich hoerbar

echo "== 8. der ganze Weg: MP3 -> Dekodierer -> AC97 -> Mitschnitt =="
# Der Kern schaltet die Tonschicht nur an, wenn das Wort `audio` auf der
# Befehlszeile steht (Runde MEDIA1, kmain.fi -- `noaudio` ist die
# Gegenprobe dazu). Alle Abschnitte davor liefen OHNE das Wort, und
# genau deshalb steht dort in jedem Protokoll "kein Tongeraet": das ist
# die Gegenprobe, dass /bin/play ohne Geraet trotzdem Auskunft gibt und
# nicht abstuerzt.
EXTRA=audio
WAVOUT="$TMPD/ac97.wav"
rm -f "$WAVOUT"
lauf spiel "play -q -K /m/ton1.mp3" \
    -audiodev "wav,id=snd0,path=$WAVOUT,out.frequency=48000,out.channels=2,out.format=s16" \
    -device AC97,audiodev=snd0
RC=$?
num "QEMU-Beendigungscode des Spiellaufs" "$RC" eq 21
hasnot "$TMPD/spiel.txt" "osum_panic" "kein osum_panic beim Spielen"
if [ -s "$WAVOUT" ]; then
    SZ=$(stat -c%s "$WAVOUT")
    num "Mitschnitt in Oktetten" "$SZ" gt 100000
    python3 - "$WAVOUT" "$MED/sig1.wav" > "$TMPD/spektrum.txt" 2>&1 <<'PYX'
import math, struct, sys, wave


def lade(p):
    w = wave.open(p, "rb")
    n, ch, sr = w.getnframes(), w.getnchannels(), w.getframerate()
    d = w.readframes(n)
    w.close()
    v = struct.unpack("<%dh" % (len(d) // 2), d)
    return list(v[0::ch]), sr


def einsatz(x, schwelle=2000):
    """Der erste Abtastwert ueber der Schwelle. Der Mitschnitt faengt mit
    Stille an, die Quelle nicht -- ohne diesen Abgleich vergleicht man
    Stille mit Musik."""
    for i, v in enumerate(x):
        if abs(v) > schwelle:
            return i
    return 0


def goertzel(x, f, sr):
    k = 2.0 * math.cos(2.0 * math.pi * f / sr)
    s1 = s2 = 0.0
    for v in x:
        s = v + k * s1 - s2
        s2, s1 = s1, s
    return math.sqrt(abs(s2 * s2 + s1 * s1 - k * s1 * s2)) / max(1, len(x))


a, sra = lade(sys.argv[1])
b, srb = lade(sys.argv[2])
ea = einsatz(a)
eb = einsatz(b)
fa = a[ea:ea + sra]
fb = b[eb:eb + srb]
print("einsatz mitschnitt=%d quelle=%d" % (ea, eb))
bezug = max(1e-9, goertzel(fa, 440.0, sra))
for f in (440.0, 1567.0, 3000.0):
    va = goertzel(fa, f, sra)
    vb = goertzel(fb, f, srb)
    # Bezug ist der 440-Hz-Pegel IM MITSCHNITT: bei einem Ton, den es in
    # der Quelle nicht gibt, waere ein Verhaeltnis zur Quelle eine
    # Division durch fast null und damit eine Zufallszahl.
    print("ton %d Hz: mitschnitt=%.2f quelle=%.2f verhaeltnis=%.3f anteil=%.5f"
          % (f, va, vb, va / vb if vb > 0 else 0, va / bezug))
rms = math.sqrt(sum(v * v for v in a) / max(1, len(a)))
print("rms mitschnitt=%.1f rahmen=%d rate=%d" % (rms, len(a), sra))
PYX
    cat "$TMPD/spektrum.txt" | sed 's/^/  /'
    R440=$(grep -a 'ton 440' "$TMPD/spektrum.txt" | grep -oaE 'verhaeltnis=[0-9.]+' | cut -d= -f2)
    R1567=$(grep -a 'ton 1567' "$TMPD/spektrum.txt" | grep -oaE 'verhaeltnis=[0-9.]+' | cut -d= -f2)
    R3000=$(grep -a 'ton 3000' "$TMPD/spektrum.txt" | grep -oaE 'anteil=[0-9.]+' | cut -d= -f2)
    awk -v r="$R440" 'BEGIN{exit !(r>0.5 && r<2.0)}' \
        && ok "440 Hz kommt im Mitschnitt an (Verhaeltnis $R440)" \
        || bad "440 Hz fehlt im Mitschnitt (Verhaeltnis $R440)"
    awk -v r="$R1567" 'BEGIN{exit !(r>0.3 && r<3.0)}' \
        && ok "1567 Hz kommt im Mitschnitt an (Verhaeltnis $R1567)" \
        || bad "1567 Hz fehlt im Mitschnitt (Verhaeltnis $R1567)"
    awk -v r="$R3000" 'BEGIN{exit !(r<0.02)}' \
        && ok "3000 Hz ist NICHT da -- die Gegenprobe (Anteil am 440-Hz-Pegel: $R3000)" \
        || bad "3000 Hz ist im Mitschnitt, obwohl es im linken Kanal nicht vorkommt (Anteil $R3000)"
else
    bad "QEMU hat keinen Ton mitgeschrieben"
fi

# ----------------------------------- 10. Bedienung: Liste, Lautstaerke, Spulen

echo "== 9. die Bedienung: Wiedergabeliste, Lautstaerke, Spulen, Spurwahl =="
lauf bedien "play -K -v 40 /m/ton1.mp3 /m/ton2.mp3; play -K -s 2 /m/ton1.mp3; play -K -t 1 -u /m/unter.srt /m/film.mkv" \
    -audiodev "wav,id=snd1,path=$TMPD/ac97b.wav,out.frequency=48000,out.channels=2,out.format=s16" \
    -device AC97,audiodev=snd1
RC=$?
num "QEMU-Beendigungscode des Bedienlaufs" "$RC" eq 21
hasnot "$TMPD/bedien.txt" "osum_panic" "kein osum_panic in der Bedienung"
n=$(grep -ca '^play: \[[12]/2\]' "$TMPD/bedien.txt")
num "Zeilen der Wiedergabeliste" "$n" eq 2
has "$TMPD/bedien.txt" "play: volume=40" "die Lautstaerke wird gesetzt"
F1=$(grep -a '^play: frames=' "$TMPD/bedien.txt" | sed -n '3p' | cut -d= -f2)
F0=$(grep -a '^play: frames=' "$TMPD/bedien.txt" | sed -n '1p' | cut -d= -f2)
if [ -n "$F1" ] && [ -n "$F0" ]; then
    num "nach -s 2 sind es weniger Rahmen als von vorn" "$F1" lt "$F0"
fi
has "$TMPD/bedien.txt" "play: [Erster Untertitel]" "der Untertitel aus der SRT-Datei erscheint zur richtigen Zeit"
has "$TMPD/bedien.txt" "play: [Dritter]" "und der dritte auch"

# --------------------------------------------------------------- Ende

echo
echo "DEMUX: $pass bestanden, $fail gescheitert"
[ "$fail" -eq 0 ] || exit 1
exit 0
