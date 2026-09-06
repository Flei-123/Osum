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
