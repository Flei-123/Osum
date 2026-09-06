#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/hda/mkmedia.sh -- die Testdateien der Runde HDA, auf dem WIRT gebaut.
#
# NICHTS DAVON WIRD EINGECHECKT, und das ist eine Regel dieses Projekts
# und keine Bequemlichkeit: eine Tondatei im Repo ist ein Fremdinhalt,
# den niemand nachrechnen kann. Dieses Skript baut sie aus einer Formel,
# und jeder Lauf ergibt dieselben Oktette.
#
#   bash tools/hda/mkmedia.sh <verzeichnis>
#
# Erzeugt:
#   ton.wav   440 Hz, 48000 Hz, stereo, 16 Bit, eine Sekunde -- dieselbe
#             Festkommareihe, die der Kernel rechnet, damit /bin/play
#             gegen refsine.py geprueft werden kann
#   ton44.wav dasselbe mit 44100 Hz -- damit die Ratenaushandlung eine
#             Datei hat, die sie WIRKLICH braucht
#   mono.wav  ein Kanal, 48000 Hz -- der Weg Mono -> Stereo
#   ton.mp3   dieselbe Sekunde als MPEG-1 Layer III, 128 kbit/s
set -uo pipefail
AUS=${1:?Verzeichnis fehlt}
mkdir -p "$AUS"

python3 - "$AUS" <<'PY'
import math, struct, sys, wave, os
aus = sys.argv[1]

Q28 = 1 << 28
PI_HALF_Q28 = 421657428

def sine_q28(phase):
    q = (phase >> 30) & 3
    r = phase & 0x3FFFFFFF
    if q in (1, 3):
        r = (0x40000000 - r) & 0xFFFFFFFFFFFFFFFF
    x = (r * PI_HALF_Q28) >> 30
    x2 = (x * x) >> 28
    p3 = (x * x2) >> 28
    p5 = (p3 * x2) >> 28
    p7 = (p5 * x2) >> 28
    p9 = (p7 * x2) >> 28
    v = x + p5 // 120 + p9 // 362880
    sub = p3 // 6 + p7 // 5040
    if sub >= v:
        return 0
    v -= sub
    return Q28 if v > Q28 else v

def reihe(hz, rate, n, amp):
    step = (hz * 4294967296 + rate // 2) // rate
    ph = 0
    out = []
    for _ in range(n):
        m = (sine_q28(ph) * amp) >> 28
        v = m if ((ph >> 31) & 1) == 0 else (65536 - m) & 0xFFFF
        if v > 65535:
            v = 65535
        out.append(v - 65536 if v >= 32768 else v)
        ph = (ph + step) & 0xFFFFFFFF
    return out

def schreib(pfad, rate, kanaele, werte):
    w = wave.open(pfad, 'wb')
    w.setnchannels(kanaele); w.setsampwidth(2); w.setframerate(rate)
    w.writeframes(b''.join(struct.pack('<h', v) for v in werte))
    w.close()

# 48000 Hz stereo, eine Sekunde, 440 Hz, Pegel 24000
s = reihe(440, 48000, 48000, 24000)
schreib(os.path.join(aus, 'ton.wav'), 48000, 2, [v for x in s for v in (x, x)])
# 44100 Hz stereo -- fuer die Ratenaushandlung
s44 = reihe(440, 44100, 44100, 24000)
schreib(os.path.join(aus, 'ton44.wav'), 44100, 2, [v for x in s44 for v in (x, x)])
# ein Kanal
schreib(os.path.join(aus, 'mono.wav'), 48000, 1, s)

# ================================================== RUNDE TON-2
# ZWEI DATEIEN MIT VERSCHIEDENEN TONHOEHEN, damit sich ZWEI
# gleichzeitig laufende PROGRAMME in der Ausgabedatei EINZELN
# nachweisen lassen (Goertzel auf 440 und auf 660 Hz).
#
# DER PEGEL IST ABSICHTLICH 12000 UND NICHT 24000: zwei Stroeme zu je
# 12000 ergeben 24000 und bleiben damit unter der Vollaussteuerung.
# Damit ist "keine Uebersteuerung" eine Aussage ueber den MISCHER und
# nicht ueber die Quellen -- die Gegenprobe mit vollem Pegel steht
# daneben (a5.wav/b5.wav).
schreib(os.path.join(aus, 'a4.wav'), 48000, 2,
        [v for x in reihe(440, 48000, 48000 * 5, 12000) for v in (x, x)])
schreib(os.path.join(aus, 'b6.wav'), 48000, 2,
        [v for x in reihe(660, 48000, 48000 * 5, 12000) for v in (x, x)])
# DIE GEGENPROBE ZUR SAETTIGUNG: zweimal fast Vollaussteuerung. Die
# Summe MUSS begrenzt werden, der Zaehler MUSS ausschlagen, und in der
# Datei MUSS ein flacher Scheitel stehen statt eines Sprungs ans
# andere Ende.
schreib(os.path.join(aus, 'a5.wav'), 48000, 2,
        [v for x in reihe(440, 48000, 48000 * 2, 30000) for v in (x, x)])
schreib(os.path.join(aus, 'b5.wav'), 48000, 2,
        [v for x in reihe(660, 48000, 48000 * 2, 30000) for v in (x, x)])

# ================================================== RUNDE TON-2
# LANG44.WAV -- 60 Sekunden, 44100 Hz, stereo.
#
# WARUM ES DIESE DATEI BRAUCHT UND DIE EINE SEKUNDE NICHT REICHT: ein
# Aussetzer ist ein SELTENES Ereignis. Ueber eine Sekunde gemessen
# schwankte die Zahl in fuenf gleichen Laeufen zwischen eins und fuenf
# -- das ist Rauschen und keine Messung, und man kann daran keine
# Verbesserung ablesen. Ueber sechzig Sekunden ist derselbe Fehler
# sechzigmal so wahrscheinlich und die Zahl entsprechend stabiler.
#
# WARUM 44100 UND NICHT 48000: weil dann die Umrechnung der Rate im
# Mischer WIRKLICH laeuft (das Geraet faehrt 48000). Eine Abnahme, die
# nur die Rate misst, bei der nichts umgerechnet wird, prueft den
# leichten Fall.
#
# WARUM EIN GLEITENDER TON und nicht derselbe 440-Hz-Sinus: eine
# Nullstrecke in einem Dauerton faellt auf; in einem Ton, der die
# Tonhoehe wechselt, faellt zusaetzlich auf, WO sie liegt. Der Ton
# laeuft in zehn Stufen von 220 auf 880 Hz und wieder zurueck.
if os.environ.get('TON_LANG', '1') != '0':
    # ZEHN SEKUNDEN UND NICHT SECHZIG, und das ist eine Grenze des
    # Dateisystems und keine Bequemlichkeit: ein Inode fasst hier
    # 2134016 Oktette (kernel/fs.fi), also 12,1 s bei 44100 Hz
    # stereo. Die 60-s-Abnahme entsteht daraus mit `play -w 6` --
    # sechs Durchlaeufe an EINEM offenen Strom, und die fuenf Nahte
    # dazwischen sind zusaetzlich das, was eine einzelne lange Datei
    # gar nicht pruefen koennte.
    lang = []
    stufen = [220, 262, 330, 392, 440, 523, 660, 784, 880, 660]
    je = 44100 * 10 // len(stufen)
    for hz in stufen:
        lang.extend(reihe(hz, 44100, je, 24000))
    schreib(os.path.join(aus, 'lang44.wav'), 44100, 2,
            [v for x in lang for v in (x, x)])
PY

# Das MP3. ffmpeg auf dem WIRT, mit -flags +bitexact, damit zwei Laeufe
# dieselbe Datei ergeben. Der Dekodierer im System bekommt damit eine
# Datei, die er NICHT selbst erzeugt hat -- alles andere waere eine
# Pruefung gegen sich selbst.
if command -v ffmpeg >/dev/null 2>&1; then
    ffmpeg -hide_banner -loglevel error -y -flags +bitexact -fflags +bitexact \
        -i "$AUS/ton.wav" -codec:a libmp3lame -b:a 128k "$AUS/ton.mp3" \
        2>/dev/null || \
    ffmpeg -hide_banner -loglevel error -y -flags +bitexact -fflags +bitexact \
        -i "$AUS/ton.wav" -codec:a mp3 -b:a 128k "$AUS/ton.mp3" || true
fi
ls -l "$AUS"
