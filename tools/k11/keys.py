#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/k11/keys.py -- TASTEN UEBER DEN QEMU-MONITOR.

Ein Editor, der nur "startet ohne Absturz" beweist, beweist nichts. Diese
Datei ist der Mensch vor der Tastatur: sie uebersetzt einen Text in die
`sendkey`-Befehle des QEMU-Monitors und schickt sie an den laufenden
Rechner. Was ankommt, sind echte Abtastcodes am Tor 0x60, echte
IRQ1-Unterbrechungen und der Weg durch `kernel/drv/hid/kbd.fi` und die
Zeilendisziplin -- kein eingeschleustes Oktett irgendwo weiter oben.

    keys.py <monitor-socket> <warte-auf-datei> <muster> <taste> ...

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


def keys_for(text):
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
            raise SystemExit("keys.py: fuer %r gibt es keine Taste" % c)
    return aus


def key_lines(pfad):
    """Wie viele `key: `-Zeilen der Kern schon gemeldet hat.

    RUNDE ROTABSCHNITTE. `kernel/drv/hid/kbd.fi` meldet GENAU EINE Zeile
    `key: ` je Taste, die ueber IRQ1 angekommen ist (die Zusage steht
    dort woertlich in Zeile 602). Das ist ein EREIGNIS -- und auf ein
    Ereignis laesst sich warten, statt auf die Uhr zu sehen.
    """
    try:
        with open(pfad, 'rb') as f:
            return f.read().count(b'key: ')
    except OSError:
        return 0


TIME_JE_KEY = 8.0


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    sock, wait, muster = sys.argv[1], sys.argv[2], sys.argv[3]
    seq = []
    for t in sys.argv[4:]:
        if t.startswith('text:'):
            seq += keys_for(t[5:])
        else:
            seq.append(t)

    bis = time.time() + 60
    ready = False
    while time.time() < bis:
        try:
            with open(wait, 'rb') as f:
                if muster.encode() in f.read():
                    ready = True
                    break
        except OSError:
            pass
        time.sleep(0.2)
    if not ready:
        print("keys.py: '%s' ist nie in %s aufgetaucht" % (muster, wait))
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
        print("keys.py: kein Monitor an %s" % sock)
        return 1
    time.sleep(0.3)
    try:
        s.recv(65536)
    except OSError:
        pass
    for k in seq:
        if k.startswith('foto:'):
            ziel = k[5:]
            if os.path.exists(ziel):
                os.unlink(ziel)
            time.sleep(1.2)
            try:
                with open(wait, 'rb') as f:
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
                    jetzt = os.path.getsize(wait)
                except OSError:
                    break
                if jetzt == letzte:
                    break
                letzte = jetzt
            continue
        if k.startswith('nowait:'):
            s.sendall(("sendkey %s\n" % k[7:]).encode())
            time.sleep(0.3)
            try:
                s.recv(65536)
            except OSError:
                pass
            continue
        vorher = key_lines(wait)
        s.sendall(("sendkey %s\n" % k).encode())
        bis3 = time.time() + TIME_JE_KEY
        while time.time() < bis3:
            if key_lines(wait) > vorher:
                break
            time.sleep(0.02)
        try:
            s.recv(65536)
        except OSError:
            pass
    time.sleep(0.5)
    s.close()
    print("%d Tasten geschickt" % len(seq))
    return 0


if __name__ == '__main__':
    sys.exit(main())
