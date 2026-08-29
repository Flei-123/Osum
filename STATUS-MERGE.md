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
- [offen] paint
- [offen] KVM-Bootlauf, mergeline -> main, OrientOS vendor/osum/COMMIT

## Zahlen
| Stand | Abschnitte | rot | Zusagen |
|---|---|---|---|
| main (Grundlinie) | 23 | 3 (k13,k14,k16) | 2196 |
| mergeline + kvmfix + testfast (voll, accel=auto) | 37 | 11 | 3256 |
| dieselben einzeln, mit TCG-Ausnahmen | -- | 4 vorbestehend | -- |
