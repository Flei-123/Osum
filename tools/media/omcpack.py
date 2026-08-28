#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/media/omcpack.py -- eine beliebige Mediendatei in OMC umwandeln.

Das Format steht in docs/CONTAINER.md, der Leser in kernel/user/omc.fi.
Dieses Programm laeuft auf dem PC, nicht auf Osum -- und das ist der
ganze Trick des Formats: die Vielfalt der Welt (jeder Codec, jeder
Behaelter) wird hier von ffmpeg erledigt, und auf Osum kommt genau eine
Sache an, die Osum lesen kann.

    python3 tools/media/omcpack.py film.mp4 film.omc
    python3 tools/media/omcpack.py lied.flac lied.omc --nur-ton
    python3 tools/media/omcpack.py film.mp4 f.omc --breite 854 --fps 24
    python3 tools/media/omcpack.py --sinus 440 --dauer 2 pruefton.omc
    python3 tools/media/omcpack.py --wav ein.wav aus.omc

Voreinstellung ist das Ziel aus Block F der Roadmap: 854x480 bei 24
Bildern je Sekunde, Ton 48 kHz Stereo 16 Bit.

WAS ES NICHT TUT: es prueft nicht, ob Osum die Bildspur auch dekodieren
kann. Kann es in Runde MEDIA1 noch nicht -- /bin/play ueberspringt sie
und zaehlt sie. Der JPEG-Dekodierer ist Runde VIEWER.
"""
import argparse
import math
import os
import shutil
import struct
import subprocess
import sys
import tempfile

MAGIC = b"OMC1"
HDR = 32
TRK = 32
BLK = 16
K_AUDIO, K_VIDEO = 1, 2
C_PCM_S16LE, C_MJPEG, C_FLAC = 1, 2, 3

RATE = 48000
CHANS = 2
BITS = 16
AUDIO_BLOCK_MS = 20  # 20 ms je Tonblock -- Begruendung in docs/CONTAINER.md


def ffmpeg():
    p = shutil.which("ffmpeg")
    if not p:
        sys.exit("omcpack: ffmpeg fehlt (apt install ffmpeg)")
    return p


def ffprobe_dauer_us(pfad):
    p = shutil.which("ffprobe")
    if not p:
        return 0
    try:
        out = subprocess.run(
            [p, "-v", "error", "-show_entries", "format=duration",
             "-of", "default=nw=1:nk=1", pfad],
            capture_output=True, text=True, timeout=60).stdout.strip()
        return int(float(out) * 1_000_000)
    except Exception:
        return 0


def ton_lesen(pfad):
    """Die Tonspur als rohes PCM s16le, 48 kHz, Stereo."""
    r = subprocess.run(
        [ffmpeg(), "-v", "error", "-i", pfad, "-vn", "-map", "a:0",
         "-ac", str(CHANS), "-ar", str(RATE), "-f", "s16le", "-"],
        capture_output=True)
    if r.returncode != 0:
        return b""
    return r.stdout


def bild_lesen(pfad, breite, fps, guete, tmpd):
    """Die Bildspur als einzelne JPEG-Dateien.

    Ueber Dateien und nicht ueber eine Roehre: ein JPEG-Strom muesste
    hier nach den Markern SOI/EOI zerlegt werden, und das ist genau die
    Art Handarbeit, die man sich mit einem eigenen Format ersparen will.
    """
    muster = os.path.join(tmpd, "f%08d.jpg")
    vf = "fps=%s" % fps
    if breite:
        vf = "scale=%d:-2:flags=bicubic," % breite + vf
    r = subprocess.run(
        [ffmpeg(), "-v", "error", "-i", pfad, "-an", "-map", "v:0",
         "-vf", vf, "-q:v", str(guete), muster],
        capture_output=True)
    if r.returncode != 0:
        return []
    namen = sorted(n for n in os.listdir(tmpd) if n.endswith(".jpg"))
    return [os.path.join(tmpd, n) for n in namen]


def sinus_pcm(hz, sekunden, aussteuerung=24000):
    n = int(RATE * sekunden)
    aus = bytearray()
    for i in range(n):
        v = int(round(aussteuerung * math.sin(2 * math.pi * hz * i / RATE)))
        v = max(-32768, min(32767, v))
        aus += struct.pack("<hh", v, v)
    return bytes(aus)


def wav_pcm(pfad):
    """Eine WAV-Datei auf 48 kHz Stereo 16 Bit bringen."""
    r = subprocess.run(
        [ffmpeg(), "-v", "error", "-i", pfad, "-vn",
         "-ac", str(CHANS), "-ar", str(RATE), "-f", "s16le", "-"],
        capture_output=True)
    if r.returncode != 0:
        sys.exit("omcpack: ffmpeg kann %s nicht lesen" % pfad)
    return r.stdout


def schreiben(ziel, pcm, bilder, fps, breite, hoehe, dauer_us):
    spuren = []
    ton_block = RATE * AUDIO_BLOCK_MS // 1000          # Rahmen je Block
    ton_octets = ton_block * CHANS * BITS // 8
    n_ton = (len(pcm) + ton_octets - 1) // ton_octets if pcm else 0
    n_bild = len(bilder)

    nr = 0
    if pcm:
        spuren.append(struct.pack("<BBHIHHIQQ", nr, K_AUDIO, C_PCM_S16LE,
                                  RATE, CHANS, BITS, ton_octets, n_ton, 0))
        ton_nr = nr
        nr += 1
    else:
        ton_nr = -1
    if bilder:
        groesste = max(os.path.getsize(p) for p in bilder)
        spuren.append(struct.pack("<BBHIHHIQQ", nr, K_VIDEO, C_MJPEG,
                                  int(round(fps * 1000)), breite, hoehe,
                                  groesste, n_bild, 0))
        bild_nr = nr
        nr += 1
    else:
        bild_nr = -1

    if not spuren:
        sys.exit("omcpack: weder Ton noch Bild gefunden")

    # Bloecke bauen: (pts_us, spur, flags, nutzlast)
    bloecke = []
    for i in range(n_ton):
        teil = pcm[i * ton_octets:(i + 1) * ton_octets]
        pts = i * ton_block * 1_000_000 // RATE
        bloecke.append((pts, ton_nr, 0, teil))
    for i, p in enumerate(bilder):
        with open(p, "rb") as f:
            teil = f.read()
        pts = int(i * 1_000_000 / fps)
        bloecke.append((pts, bild_nr, 1, teil))
    # NACH ZEITSTEMPEL ORDNEN, und bei gleichem Zeitstempel der TON
    # zuerst. Das ist kein Schoenheitsfehler: der Abspieler fuellt den
    # Tonpuffer aus dem Strom, und ein Bild vor dem gleichzeitigen Ton
    # heisst, dass der Ton eine Bildlaenge spaeter kommt als noetig.
    bloecke.sort(key=lambda x: (x[0], 0 if x[1] == ton_nr else 1))

    erster = HDR + TRK * len(spuren)
    if dauer_us == 0 and bloecke:
        dauer_us = max(b[0] for b in bloecke)
    kopf = struct.pack("<4sHHQIIII", MAGIC, HDR, len(spuren), dauer_us,
                       erster, len(bloecke), 0, 0)
    assert len(kopf) == HDR, len(kopf)

    with open(ziel, "wb") as f:
        f.write(kopf)
        for s in spuren:
            assert len(s) == TRK, len(s)
            f.write(s)
        for pts, spur, flags, nutz in bloecke:
            f.write(struct.pack("<BBHIQ", spur, flags, 0, len(nutz), pts))
            f.write(nutz)
    return len(bloecke), n_ton, n_bild


def main():
    ap = argparse.ArgumentParser(add_help=True, description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("eingabe", nargs="?", help="Videodatei, Tondatei")
    ap.add_argument("ausgabe")
    ap.add_argument("--nur-ton", action="store_true")
    ap.add_argument("--breite", type=int, default=854)
    ap.add_argument("--fps", type=float, default=24.0)
    ap.add_argument("--guete", type=int, default=5, help="JPEG, 2 = gut, 31 = grob")
    ap.add_argument("--sinus", type=float, default=0.0, help="Pruefton in Hz")
    ap.add_argument("--dauer", type=float, default=1.0, help="Sekunden beim Pruefton")
    ap.add_argument("--pegel", type=int, default=24000)
    ap.add_argument("--wav", help="eine WAV-Datei einpacken")
    a = ap.parse_args()

    if a.sinus > 0:
        pcm = sinus_pcm(a.sinus, a.dauer, a.pegel)
        n, nt, nb = schreiben(a.ausgabe, pcm, [], a.fps, 0, 0,
                              int(a.dauer * 1_000_000))
        print("omcpack: %s -- %d Bloecke (%d Ton, %d Bild), Sinus %g Hz, %g s"
              % (a.ausgabe, n, nt, nb, a.sinus, a.dauer))
        return
    if a.wav:
        pcm = wav_pcm(a.wav)
        n, nt, nb = schreiben(a.ausgabe, pcm, [], a.fps, 0, 0, 0)
        print("omcpack: %s -- %d Bloecke (%d Ton, %d Bild) aus %s"
              % (a.ausgabe, n, nt, nb, a.wav))
        return
    if not a.eingabe:
        ap.error("ohne --sinus/--wav braucht es eine Eingabedatei")

    dauer = ffprobe_dauer_us(a.eingabe)
    pcm = ton_lesen(a.eingabe)
    bilder = []
    breite = hoehe = 0
    tmpd = None
    try:
        if not a.nur_ton:
            tmpd = tempfile.mkdtemp(prefix="omcpack-")
            bilder = bild_lesen(a.eingabe, a.breite, a.fps, a.guete, tmpd)
            if bilder:
                # Die wirkliche Groesse steht im ersten JPEG (SOF0).
                breite, hoehe = jpeg_groesse(bilder[0])
        n, nt, nb = schreiben(a.ausgabe, pcm, bilder, a.fps, breite, hoehe,
                              dauer)
    finally:
        if tmpd:
            shutil.rmtree(tmpd, ignore_errors=True)
    print("omcpack: %s -- %d Bloecke (%d Ton a %d ms, %d Bild %dx%d @ %g fps), "
          "%d Oktette" % (a.ausgabe, n, nt, AUDIO_BLOCK_MS, nb, breite, hoehe,
                          a.fps, os.path.getsize(a.ausgabe)))


def jpeg_groesse(pfad):
    """Breite und Hoehe aus dem SOF-Marker. 30 Zeilen statt einer
    Fremdbibliothek -- und dieselben 30 Zeilen wird der Dekodierer der
    Runde VIEWER als erstes brauchen."""
    with open(pfad, "rb") as f:
        d = f.read()
    i = 2
    while i + 9 < len(d):
        if d[i] != 0xFF:
            i += 1
            continue
        m = d[i + 1]
        if m in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
                 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
            h = (d[i + 5] << 8) | d[i + 6]
            w = (d[i + 7] << 8) | d[i + 8]
            return w, h
        if m in (0xD8, 0xD9) or 0xD0 <= m <= 0xD7:
            i += 2
            continue
        laenge = (d[i + 2] << 8) | d[i + 3]
        i += 2 + laenge
    return 0, 0


if __name__ == "__main__":
    main()
