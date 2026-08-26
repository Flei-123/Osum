#!/usr/bin/env python3
"""tools/k11/tasten.py -- TASTEN UEBER DEN QEMU-MONITOR.

Ein Editor, der nur "startet ohne Absturz" beweist, beweist nichts. Diese
Datei ist der Mensch vor der Tastatur: sie uebersetzt einen Text in die
`sendkey`-Befehle des QEMU-Monitors und schickt sie an den laufenden
Rechner. Was ankommt, sind echte Abtastcodes am Tor 0x60, echte
IRQ1-Unterbrechungen und der Weg durch `kernel/kbd.fi` und die
Zeilendisziplin -- kein eingeschleustes Oktett irgendwo weiter oben.

    tasten.py <monitor-socket> <warte-auf-datei> <muster> <taste> ...

Eine Taste ist entweder ein QEMU-Name (`ret`, `spc`, `ctrl-o`, `up`,
`shift-a`, `pgdn`, ...) oder `text:HALLO WELT`, das in einzelne Tasten
zerlegt wird -- samt Umschalttaste fuer Grossbuchstaben und Sonderzeichen.

`foto:/pfad.ppm` MITTEN in der Folge macht ein Bildschirmfoto -- der
einzige Weg, den Schirm zu sehen, WAEHREND das Programm noch laeuft und
nicht erst, wenn es sich schon verabschiedet hat.

`warte:0.8` haelt an dieser Stelle an; `ruhe` wartet, bis der Rechner
nichts mehr auf die Leitung schreibt.
"""
import os
import socket
import sys
import time

# Ein Zeichen -> eine QEMU-Taste. Was hier nicht steht, kann diese
# Tastatur nicht schicken, und dann sagt das Programm das, statt es
# stillschweigend wegzulassen.
EINFACH = {
    ' ': 'spc', '\n': 'ret', '\t': 'tab',
    '-': 'minus', '=': 'equal', '[': 'bracket_left', ']': 'bracket_right',
    ';': 'semicolon', "'": 'apostrophe', '`': 'grave_accent',
    '\\': 'backslash', ',': 'comma', '.': 'dot', '/': 'slash',
}
UMSCHALT = {
    '!': '1', '@': '2', '#': '3', '$': '4', '%': '5', '^': '6', '&': '7',
    '*': '8', '(': '9', ')': '0', '_': 'minus', '+': 'equal',
    '{': 'bracket_left', '}': 'bracket_right', ':': 'semicolon',
    '"': 'apostrophe', '~': 'grave_accent', '|': 'backslash',
    '<': 'comma', '>': 'dot', '?': 'slash',
}


def tasten_fuer(text):
    aus = []
    for c in text:
        if c.islower() or c.isdigit():
            aus.append(c)
        elif c.isupper():
            aus.append('shift-' + c.lower())
        elif c in EINFACH:
            aus.append(EINFACH[c])
        elif c in UMSCHALT:
            aus.append('shift-' + UMSCHALT[c])
        else:
            raise SystemExit("tasten.py: fuer %r gibt es keine Taste" % c)
    return aus


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    sock, warte, muster = sys.argv[1], sys.argv[2], sys.argv[3]
    folge = []
    for t in sys.argv[4:]:
        if t.startswith('text:'):
            folge += tasten_fuer(t[5:])
        else:
            folge.append(t)

    # Warten, bis der Rechner sagt, dass er bereit ist. Ohne das faellt die
    # erste Taste in die Shell und nicht in den Editor.
    bis = time.time() + 60
    bereit = False
    while time.time() < bis:
        try:
            with open(warte, 'rb') as f:
                if muster.encode() in f.read():
                    bereit = True
                    break
        except OSError:
            pass
        time.sleep(0.2)
    if not bereit:
        print("tasten.py: '%s' ist nie in %s aufgetaucht" % (muster, warte))
        return 1

    s = None
    bis = time.time() + 30
    while time.time() < bis:
        try:
            s = socket.socket(socket.AF_UNIX)
            s.settimeout(5.0)
            s.connect(sock)
            break
        except OSError:
            s = None
            time.sleep(0.2)
    if s is None:
        print("tasten.py: kein Monitor an %s" % sock)
        return 1
    time.sleep(0.3)
    try:
        s.recv(65536)
    except OSError:
        pass
    for k in folge:
        if k.startswith('foto:'):
            ziel = k[5:]
            if os.path.exists(ziel):
                os.unlink(ziel)
            # Erst zur Ruhe kommen lassen: ein Foto mitten im Neuzeichnen
            # zeigt einen halben Schirm, und der verliert jeden Vergleich.
            time.sleep(1.2)
            # DER MITSCHNITT WIRD IM SELBEN AUGENBLICK FESTGEHALTEN.
            # Ohne das misst man spaeter den Schirm, den der Editor beim
            # VERLASSEN hinterlassen hat, und nicht den, der auf dem Foto
            # steht -- und dann vergleicht man zwei verschiedene
            # Zeitpunkte miteinander.
            try:
                with open(warte, 'rb') as f:
                    open(ziel + '.ser', 'wb').write(f.read())
            except OSError:
                pass
            s.sendall(("screendump %s\n" % ziel).encode())
            letzte = -1
            ruhig = 0
            bis2 = time.time() + 20
            while time.time() < bis2:
                time.sleep(0.15)
                try:
                    jetzt = os.path.getsize(ziel)
                except OSError:
                    continue
                if jetzt == letzte and jetzt > 0:
                    ruhig += 1
                    if ruhig >= 3:
                        break
                else:
                    ruhig = 0
                    letzte = jetzt
            try:
                s.recv(65536)
            except OSError:
                pass
            continue
        if k.startswith('warte:'):
            time.sleep(float(k[6:]))
            continue
        if k == 'ruhe':
            letzte = -1
            while True:
                time.sleep(0.4)
                try:
                    jetzt = os.path.getsize(warte)
                except OSError:
                    break
                if jetzt == letzte:
                    break
                letzte = jetzt
            continue
        s.sendall(("sendkey %s\n" % k).encode())
        time.sleep(0.12)
        try:
            s.recv(65536)
        except OSError:
            pass
    time.sleep(0.5)
    s.close()
    print("%d Tasten geschickt" % len(folge))
    return 0


if __name__ == '__main__':
    sys.exit(main())
