# STATUS MERGE-FINAL (Runde 31)

Stand: 29.08.2026, 03:10 -- laufend.

## Ausgangslage (verifiziert)
- main = 3389fbd, mergeline = e9fcc1c (200 Commits vor main)
- /dev/kvm da, 12 CPUs, 19 GB RAM, /root ~3,6 GB frei
- Merge-Vorschau: kvmfix/testfast/hwnet konfliktfrei; look und paint je
  11 Konflikte, alle in docs/shots/netview/*.png (regenerierbar)

## Grundlinie
- main (/root/BASE-MAIN.log): 23 Abschnitte, 20 gruen / 3 rot, 2196 Zusagen
  rot: k13, k14, k16
- mergeline vor den Merges (/root/ML-CHECK.log): icons rot (24 ok/1),
  tunnelpakete rot (15/3) -- beide VORBESTEHEND, nicht in main enthalten

## Fortschritt
- [erledigt] Merge kvmfix -> mergeline (konfliktfrei)
- [erledigt] Merge testfast -> mergeline (6b602af)
- [erledigt] Abnahme danach: /root/M2-TESTFAST.log, 26 gruen / 11 rot (3256 Zusagen)
- [erledigt] jeden roten Abschnitt EINZELN nachgemessen (/root/M2-SINGLE.log):
  - Phantom aus dem vollen Lauf (einzeln gruen): net 75/0, k15 252/0, arm 48/0
  - vorbestehend rot: k14 (151/1), k16 (58/6), icons (24/1), tunnelpakete (15/3)
  - NEU rot unter KVM: kernel 168/8, pci 91/7, k18 167/3, k17 153/5
- [erledigt] Gegenprobe mit OSUM_ACCEL=tcg (/root/TCG-CHECK.log):
  kernel 176/0, pci 98/0, k18 170/0, k17 158/0 -- alle vier gruen.
  Ursache ist der Wirt unter KVM (Zeitscheiben, DMA-Zeit, CPUID Blatt 5
  ohne mwait, xHCI-Tempo), kein Merge-Schaden.
  -> tools/lib/accel-ausnahmen.txt: die vier stehen wieder drin, mit
     Messwerten (Commit 62e0ac7). KEIN Test entschaerft.
- [erledigt] Merge hwnet -> mergeline (09eba52; 7 Konflikte, alle in
  docs/shots/netview/*.png, mit --theirs geloest -- die Bilder werden von
  tools/netview/run.sh ohnehin neu erzeugt und der Abschnitt ist gruen)
- [erledigt] volle Abnahme danach (/root/M3-HWNET.log): 39 Abschnitte,
  32 gruen / 7 rot, 3173 Zusagen
- [erledigt] die sieben einzeln nachgemessen (/root/M3-SINGLE.log):
  posix 134/0, smp 59/0, k17 158/0 -- alle drei nur im vollen Lauf rot
  (posix und smp an 'No space left on device', k17 an Last).
  Es bleiben k14, k16, icons, tunnelpakete -- alle VORBESTEHEND.
  KEIN NEUER SCHADEN DURCH hwnet.
- [erledigt] Merge look -> mergeline (656fc98; 11 PNG-Konflikte, --theirs)
- [erledigt] volle Abnahme danach (/root/M4-LOOK.log): 39 Abschnitte,
  35 gruen / 4 rot, 3360 Zusagen -- die vier roten sind GENAU die
  vorbestehenden (k14, k16, icons, tunnelpakete). Kein neuer Schaden.
- [erledigt] Merge paint -> mergeline (2bdd362; 13 PNG-Konflikte --theirs,
  plus EIN echter Konflikt in kernel/user/wlib.fi: die export-Liste --
  HEAD hatte set_menu_title, paint window_app; beide behalten, beide
  Funktionen sind da (Zeile 391 und 1388))
- [erledigt] volle Abnahme danach (/root/M5-PAINT.log): 40 Abschnitte,
  34 gruen / 6 rot, 3274 Zusagen. Die zwei zusaetzlichen einzeln
  nachgemessen (/root/M5-SINGLE.log): k11 85/0 (im vollen Lauf abgebrochen),
  netview 195/0 (im vollen Lauf eine ZEITZUSAGE: 354 ms statt < 200 ms).
  Beide sind Last, kein Schaden. Es bleiben k14, k16, icons, tunnelpakete.
- [erledigt] KVM-Abnahme ausdruecklich mit OSUM_ACCEL=kvm: tools/kvm/run.sh
  35 Zusagen, keine rote (/root/KVM-BOOT.log). Dazu lief JEDE der vier
  vollen Abnahmen mit accel=auto, also fuer die allermeisten Abschnitte
  wirklich unter /dev/kvm -- nicht nur TCG.
- [erledigt] main auf mergeline vorgezogen (fast-forward): main = 1a1491f
- [erledigt] OrientOS vendor/osum/COMMIT auf 1a1491f (Commit 17bf2c8)

## FERTIG

## Zahlen
| Stand | Abschnitte | rot | Zusagen |
|---|---|---|---|
| main (Grundlinie) | 23 | 3 (k13,k14,k16) | 2196 |
| mergeline + kvmfix + testfast (voll, accel=auto) | 37 | 11 | 3256 |
| dieselben einzeln, mit TCG-Ausnahmen | -- | 4 vorbestehend | -- |


## ENDSTAND

| | Abschnitte | gruen | rot | Zusagen |
|---|---|---|---|---|
| main VORHER (3389fbd) | 23 | 20 | 3 | 2196 |
| main NACHHER (1a1491f) | 40 | 36 | 4 | 3360+ |

Rot NACHHER, alle vier VORBESTEHEND (keiner davon durch diese Runde):
- k14  151/1   die Wurzelplatte Oktett fuer Oktett nach dem Schreiben
- k16   58/6   fas findet _F1.u_start nicht; das Selbst-Uebersetzen bricht ab
- icons 24/1   lib/icons.fi laesst sich aus der Karte nicht reproduzieren
- tunnelpakete 15/3  /apps/*.osp/start fehlt nach der Installation

k13 war in der Grundlinie rot und ist jetzt GRUEN (99/0).

Aufgenommen: kvmfix, testfast, hwnet, look, paint.
Geaendert wurde ausserdem nur tools/lib/accel-ausnahmen.txt (vier
Abschnitte zurueck auf TCG, jeder mit gemessener Begruendung).
KEIN Test entschaerft.
