#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/demux/mkmedia.sh -- die Testdateien dieser Runde, auf dem WIRT gebaut.
#
# Nichts davon wird eingecheckt: ein MP4 mit H.264 ist ein Fremdcodec im
# Repo, und eine Datei, die man nicht nachbauen kann, ist als Beleg
# wertlos. Dieses Skript baut sie alle aus zwei erzeugten Signalen, und
# jeder Lauf bekommt dieselben Oktette (ffmpeg mit -flags +bitexact).
#
#   bash tools/demux/mkmedia.sh <ausgabeverzeichnis>
#
# Das Signal ist ABSICHTLICH gemischt: Dauerton, Gleitton, Stille und
# harte Knacke. Die Knacke sind der Punkt -- sie zwingen den MP3-Kodierer
# in die KURZEN Bloecke (block_type 2) und in den Mischblock, und ein
# Dekodierer, der nur lange Bloecke kann, faellt genau daran auf.
set -uo pipefail
AUS=${1:?Ausgabeverzeichnis fehlt}
mkdir -p "$AUS"
FF="ffmpeg -hide_banner -loglevel error -y -flags +bitexact -fflags +bitexact"

# ---------------------------------------------------------- die Signale
python3 - "$AUS" <<'PY'
import math, struct, sys, wave, os
aus = sys.argv[1]

def schreib(pfad, rate, kanaele, proben):
    w = wave.open(pfad, 'wb')
    w.setnchannels(kanaele); w.setsampwidth(2); w.setframerate(rate)
    w.writeframes(b''.join(struct.pack('<h', max(-32768, min(32767, int(v))))
                           for v in proben))
    w.close()

# Signal 1: 44100 Hz stereo, 4 s. Links Dauerton + Oberton, rechts
# Gleitton. Bei 1,5 s eine halbe Sekunde Stille, bei 2,0/2,5/3,0 s je
# ein Knack ueber einen einzigen Abtastwert.
r, n = 44100, 44100*4
p = []
for i in range(n):
    t = i / r
    if 1.5 <= t < 2.0:
        l = rr = 0.0
    else:
        l = 9000*math.sin(2*math.pi*440*t) + 3000*math.sin(2*math.pi*1567*t)
        f = 200 + 3000*(t/4.0)
        rr = 11000*math.sin(2*math.pi*f*t)
    for k in (2.0, 2.5, 3.0):
        if abs(t-k) < 1.0/r:
            l = 30000; rr = -30000
    p.append(l); p.append(rr)
schreib(os.path.join(aus, 'sig1.wav'), r, 2, p)

# Signal 2: 48000 Hz mono, 2 s -- die andere Abtastrate und der Monopfad.
r, n = 48000, 48000*2
p = []
for i in range(n):
    t = i / r
    v = 8000*math.sin(2*math.pi*997*t) + 4000*math.sin(2*math.pi*3001*t)
    if abs(t-1.0) < 1.0/r: v = 32000
    p.append(v)
schreib(os.path.join(aus, 'sig2.wav'), r, 1, p)
PY

# ------------------------------------------------------------ nur Audio
# CBR 128k, Joint Stereo -> der MS-Stereo-Pfad. Ohne Xing-Rahmen, damit
# beide Dekodierer denselben ersten Rahmen sehen.
$FF -i "$AUS/sig1.wav" -c:a libmp3lame -b:a 128k -joint_stereo 1 \
    -write_xing 0 -id3v2_version 0 "$AUS/ton1.mp3"
# Mono, 48 kHz, andere Datenrate.
$FF -i "$AUS/sig2.wav" -c:a libmp3lame -b:a 96k \
    -write_xing 0 -id3v2_version 0 "$AUS/ton2.mp3"
# Volle Stereotrennung (nicht joint) -- der zweite Stereopfad.
$FF -i "$AUS/sig1.wav" -c:a libmp3lame -b:a 192k -joint_stereo 0 \
    -write_xing 0 -id3v2_version 0 "$AUS/ton3.mp3"
# AAC-LC in MP4 (.m4a) -- der haeufigste Ton in MP4.
$FF -i "$AUS/sig1.wav" -c:a aac -b:a 128k "$AUS/ton1.m4a"
# MP3 in MP4 -- gibt es, und der Leser muss es unterscheiden.
$FF -i "$AUS/sig1.wav" -c:a libmp3lame -b:a 128k "$AUS/ton1mp3.mp4"
# MP3 in MKV, ohne Video -- der Musikspielerfall im anderen Behaelter.
$FF -i "$AUS/sig1.wav" -c:a libmp3lame -b:a 128k "$AUS/ton1.mka"

# ------------------------------------------------------ Bild UND Ton
# H.264, 320x240, 24 Bilder/s, 3 s -- die Videospur, die dieses System
# NICHT dekodieren kann und darum benennen muss.
$FF -f lavfi -i "testsrc2=size=320x240:rate=24:duration=3" \
    -i "$AUS/sig1.wav" -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
    -profile:v baseline -c:a aac -b:a 128k -shortest "$AUS/film.mp4"
# Dasselbe mit MP3-Ton in Matroska, plus eine Untertitelspur.
cat > "$AUS/unter.srt" <<'SRT'
1
00:00:00,200 --> 00:00:01,200
Erster Untertitel

2
00:00:01,500 --> 00:00:02,400
Zweiter Untertitel, mit Komma

3
00:00:02,600 --> 00:00:02,900
Dritter
SRT
$FF -f lavfi -i "testsrc2=size=320x240:rate=24:duration=3" \
    -i "$AUS/sig1.wav" -i "$AUS/unter.srt" \
    -c:v libx264 -preset ultrafast -pix_fmt yuv420p -profile:v baseline \
    -c:a libmp3lame -b:a 128k -c:s srt -shortest "$AUS/film.mkv"
# VP9 in WebM -- der zweite Codec, der ehrlich abgelehnt werden muss.
$FF -f lavfi -i "testsrc2=size=160x120:rate=10:duration=1" \
    -c:v libvpx-vp9 -b:v 100k -an "$AUS/vp9.webm"
# Nur Video, kein Ton -- dann gibt es auch nichts anzubieten.
$FF -f lavfi -i "testsrc2=size=160x120:rate=10:duration=1" \
    -c:v libx264 -preset ultrafast -pix_fmt yuv420p -an "$AUS/stumm.mp4"

# ------------------------------------------------------- kaputte Dateien
# 1. abgeschnitten mitten im moov
head -c 700 "$AUS/film.mp4" > "$AUS/kurz.mp4"
# 2. abgeschnitten mitten in einem Cluster
head -c 2000 "$AUS/film.mkv" > "$AUS/kurz.mkv"
# 3. abgeschnittenes MP3 -- letzter Rahmen unvollstaendig
head -c 5000 "$AUS/ton1.mp3" > "$AUS/kurz.mp3"
# 4. eine Boxlaenge, die ueber das Dateiende zeigt
python3 - "$AUS" <<'PY'
import os, sys, struct
aus = sys.argv[1]
d = bytearray(open(os.path.join(aus,'film.mp4'),'rb').read())
# die erste Box nach ftyp bekommt eine Laenge von 4 GB
off = struct.unpack('>I', d[0:4])[0]
d[off:off+4] = struct.pack('>I', 0xFFFFFF00)
open(os.path.join(aus,'luege.mp4'),'wb').write(bytes(d))
# ein MKV, dessen Segmentgroesse luegt
m = bytearray(open(os.path.join(aus,'film.mkv'),'rb').read())
i = m.find(b'\x18\x53\x80\x67')
if i >= 0:
    m[i+4:i+12] = b'\x01\xff\xff\xff\xff\xff\xff\xf0'
open(os.path.join(aus,'luege.mkv'),'wb').write(bytes(m))
# ein MP3, in dem jedes 37. Oktett gekippt ist
b = bytearray(open(os.path.join(aus,'ton1.mp3'),'rb').read())
for k in range(0, len(b), 37): b[k] ^= 0x5A
open(os.path.join(aus,'kaputt.mp3'),'wb').write(bytes(b))
# eine Datei, die gar nichts ist
open(os.path.join(aus,'muell.bin'),'wb').write(bytes(range(256))*8)
# eine leere Datei
open(os.path.join(aus,'leer.mp4'),'wb').write(b'')
PY

# -------------------------------------------------- die Referenzen (WAV)
# Was ffmpeg aus DENSELBEN Dateien macht. s16le, roh, ohne Kopf.
for f in ton1 ton2 ton3; do
    $FF -i "$AUS/$f.mp3" -f s16le -acodec pcm_s16le "$AUS/$f.ref.raw"
done
$FF -i "$AUS/ton1.m4a" -f s16le -acodec pcm_s16le "$AUS/ton1m4a.ref.raw"
$FF -i "$AUS/film.mkv" -map 0:a -f s16le -acodec pcm_s16le "$AUS/filmmkv.ref.raw"
$FF -i "$AUS/ton1.mka" -map 0:a -f s16le -acodec pcm_s16le "$AUS/ton1mka.ref.raw"

ls -l "$AUS" | sed 's/^/  /'
