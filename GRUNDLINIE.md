# GRUNDLINIE main (3389fbd) -- gemessen 28.08.2026, seriell, 3157 s
Ergebnis: 20 Abschnitte bestanden, 3 FEHLGESCHLAGEN, 2196 Zusagen (rc=1)

ROT: K13 (87 passed / 12 failed), K14 (144/8), K16 (58/6)

Zusagen je Laeufer:
BOOT 20 | CAPS 67 | CORE 46 | FREESTANDING 41 | GFX 76 | GUARD 55 | HV 114
K11 85 | K13 87 | K14 144 | K15 251 | K16 58 | K18 170 | KERNEL 176 | NET 75
OSUM 130 | PCI 98 | POSIX 134 | SMP 59 | UNIX 107 | USERLAND 91 | WM 103

Vorbestehende Fehlerursachen (Kurzfassung):
- K13: su/setuid-Kette (eigene Kennung nach su bleibt 0), noperm/nosuid-Gegenproben
- K14: Gegenprobe novfs meldet keine Zeilen; Wurzelplatte-Vergleich
- K16: fas kennt '_F1.u_start' nicht -> 70 statt 75 gebundene Programme,
  das auf Osum uebersetzte Programm laeuft nicht (LAUF=127 statt 42)
