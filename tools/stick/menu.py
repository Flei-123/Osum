#!/usr/bin/env python3
"""menu.py <monitor-socket> <n> [wartezeit] [abstand]

Im Limine-Menue n mal nach unten und dann Eingabe.

WARUM SO LANGSAM: der erste Tastendruck haelt den Countdown an, und
Limine liest die Tastatur im Polling. Kommt eine Taste, bevor das Menue
steht, ist sie weg -- gemessen: sechs Tastendruecke nach vier Sekunden
kamen als zwei an.
"""
import socket
import sys
import time

pfad = sys.argv[1]
n = int(sys.argv[2])
warte = float(sys.argv[3]) if len(sys.argv) > 3 else 8.0
abstand = float(sys.argv[4]) if len(sys.argv) > 4 else 0.8

s = None
for _ in range(600):
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(pfad)
        break
    except OSError:
        s = None
        time.sleep(0.05)
if s is None:
    print("keine Monitor-Steckdose: %s" % pfad)
    raise SystemExit(1)
s.settimeout(0.3)

time.sleep(warte)
try:
    s.recv(65536)
except OSError:
    pass
for i in range(n):
    s.sendall(b"sendkey down\n")
    time.sleep(abstand)
time.sleep(0.6)
s.sendall(b"sendkey ret\n")
time.sleep(0.4)
s.close()
print("menu: %d x runter, dann Eingabe (nach %.1fs, Abstand %.1fs)"
      % (n, warte, abstand))
