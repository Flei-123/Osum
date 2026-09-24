<!-- SPDX-License-Identifier: GPL-2.0-only -->
# Runde ROADMAP-5 — A-032, A-033, K-002, K-008, K-009, K-011, K-012

Zweig `runde-roadmap-5`, von `main` 6190ba0d. Jeder Punkt ein eigener
Commit, jeder mit Messung und Gegenprobe.

| Punkt | vorher | nachher | Commit |
|---|---|---|---|
| A-033 Probedateien im Baum | `order.sh`/`themestore` legen `.fi` in `kernel/`, `lib/` | nichts mehr im Baum | `4f0cdd0b` |
| A-032 wmplug-Tabellenkopf | `spalten` 15/1 | **26/0** | `72fdf296` |
| K-009 Rückverfolgung | Stapelscan: 3 echte + 13 Altlast | Rahmenkette: genau 5, alle echt | `9cc9a770` |
| K-012 smp-Gegenprobe | 5/0/6/0 Doppelte über 4 Läufe | 8 Runden, 40/40 Läufe treffen | `b2763991` |
| K-011 Panikbericht | Versuch; mit Sperre verloren | im Speicher, beim Warmstart gerettet | `b9e407cb` |
| K-002 Speicherdruck/OOM | keine Reserve, keine Auswahl | Reserve, ehrliches `brk`, Auswahl per SIGKILL | `f8503afb`, `587033bb` |
| K-008 Drucker | kein Druckweg | `drucke`: IPP an Netzwerkdrucker, **61/0**; Auftrag 60 s → 15 s | (dieser Commit) |

## A-033 — keine Probe mehr im Quelltext

* `tools/arch/order.sh`: die Probe braucht eine Wurzel neben `kernel/`,
  damit `import arch.arch` so aufgelöst wird wie im Kern. Sie liegt jetzt
  in `$TMP/root/`, und `$TMP/root/arch` ist ein Verweis auf
  `kernel/arch` — gelesen wird derselbe Code, geschrieben nichts.
* `tools/themestore/run.sh`: beide Gegenproben (zweiter Eckenabtaster,
  untergeschobener Mischer) legen ihre Datei in `$TMPD` und reichen sie
  demselben `grep` als weitere Eingabe. Beim Mischer wird der Pfad
  vorangestellt, den die Datei im Baum hätte — die Zeile, die `comm`
  sieht, ist oktettgleich mit früher.

## A-032 — der Kopf war immer da

Der Tabellenkopf stand bildpunktgenau im Foto, 24 Punkte links und 40
höher, als der Läufer suchte. `/etc/wmregeln.conf` sagt
`titel=Terminal kacheln`, und seit plugregel beim Start läuft, liegt das
Terminal bei 0,0 statt 24,40. Der Läufer hatte den Rasterursprung fest
auf 26,62. Jetzt: Fensterlage aus `wm: win … t=[Terminal`, dazu
`BORDER0` und `TITLE_H0` aus `kernel/ui/wm.fi`. Gegenprobe: am alten
Ursprung steht der Kopf in keiner der 24 Zeilen. 15/1 → 26/0 — die zehn
Paarproben (Kopf und Wert auf derselben Endspalte) laufen erst jetzt,
vorher hingen sie am gefundenen Kopf.

## K-009 — die Rahmenkette statt des Stapelscans

firnc legt jeden Rahmen mit `push rbp; mov rbp, rsp` an (am erzeugten
Assembler beider Stufen nachgesehen), und `boot.s` löscht `rbp` vor
`kernel_main`. `trap.kspur_kette` geht die Kette ab; jeder Schritt muss
ausgerichtet sein, über `rsp` und im 256-KiB-Kernstapel liegen und
streng steigen. Bleibt die Kette leer, wird wie bisher gescannt, und die
Leitung sagt, welcher Weg es war (`kspur: rahmenkette` /
`kspur: stapelscan`).

An der erzwungenen Panik (`krach krachjetzt`):

    rahmenkette:  crash.knall_b, crash.knall_a, crash.knall, KERNEL_MAIN, long_mode
    stapelscan:   dieselben drei, dann arch.dev_out8, serial.port, serial.ready,
                  serial.out8, gfx.echo, serial.put, serial.nl, bootmod.recheck,
                  hv.on, serial.dec, serial.nl, guard.report_aps, arch.dev_out8

`tools/protocol/run.sh` verlangte bisher „mindestens fünf aufgelöste
Symbole" — die Zahl maß den Scan samt Altlast. Jetzt wird genau die
Aufrufkette verlangt, auf dem Schirm und auf der Leitung; Gegenprobe
`stapelscan` muss Einträge liefern, die keine Rufer sind (13).

Offen: Ring 3 (`trace_say`) scannt weiter.

## K-012 — die Gegenprobe war ein Würfel

Gemessen, bevor etwas geändert wurde: eine Runde des Rahmen-Rennens
(`nolock`, 4 Kerne × 16 Rahmen) trifft nur in rund zwei Dritteln der
Fälle — 235 von 320 Runden. Das ist die Reihe 5/0/6/0. Seit Runde MEM
sind 16 Rahmen ein paar hundert Takte Arbeit.

Nichts wird verbreitert oder verzögert; dasselbe echte Rennen läuft
acht Mal. Jede Runde braucht eine eigene Phasennummer (64..71): ein
gestarteter Kern sieht dieselbe Nummer kein zweites Mal — der erste
Versuch mit gleicher Nummer hing. Das `>=` des Zeichen-Rennens (7..31)
ist deshalb nach oben begrenzt. Mit Sperre muss die Summe über alle acht
Runden 0 sein.

    nolock, 40 Läufe:  40 mit Doppelten, Treffer je Lauf 1..8 von 8
    mit Sperre, 5:     dups=0 über alle 8 Runden
    tools/smp/run.sh:  4 × 60/0

## K-011 — der Bericht überlebt im Speicher

Der fertige Bericht geht zuerst nach 0x96000 (12 KiB, unter
`kernel_end`, vom Rahmenverwalter nie vergeben; Kopf: Magie
`OSPANIK1`, Länge, FNV-1a), erst danach wird die Platte versucht. Gelingt
die Platte, wird das Speicherstück sofort ungültig. Der nächste Start
legt einen gültigen Bericht vor `crash.init` nach /var/crash — mit
Marke, wie jeden anderen.

`krach kernfs` (art 2) ist die Panik MIT gehaltener Dateisystemsperre,
also genau der Fall, in dem die Platte nicht darf.

    kalt (neuer QEMU):       nichts gerettet, kein art-2-Bericht auf der Platte
    warm (system_reset):     "bericht aus dem speicher gerettet",
                             /var/crash/<zeit>.txt geschrieben,
                             /bin/absturz zeigt ABSTURZBERICHT (KERN) mit "art 2"

Grenze: ein Kaltstart löscht den Speicher, und eine UEFI-Firmware darf
den unteren Speicher beim Start benutzen — auf echtem Blech ungemessen.

## K-002 — Speicherdruck, neu gebaut

Der Zweig `speicherdruck` (vor O-STRUKTUR) auf den heutigen Baum
übertragen: Reserve nur für den Kern, ehrliches `brk`, Auswahl des
größten beendbaren Prozesses, geschützt ist, was der Schreibtisch
startet, vorher `sync`. Der Bericht des Zweigs liegt als
`docs/SPEICHERDRUCK.md` dabei.

Belegungen waren inzwischen vergeben und wurden neu gesetzt: kdata
1752..1784 (1704..1736 = ZIEH/BLUR), Modus 910..916 (983..989 belegt),
`T_UPAGES`/`T_OOMSAFE` 664/672 (hinter `T_CTR`), `P_HOG`/`P_HOGWRITE`
66/67 — 64/65 sind `P_SCHLAF`/`P_WACH`; der erste Lauf startete statt des
Fressers das Schlafprogramm.

Zwei Fehler des Zweigs, beide gemessen und behoben:

1. **Das Opfer rechnete weiter.** Der Zweig setzte es auf `S_ZOMBIE`,
   auch wenn es der Prozess war, der gerade im Aufruf steckt (der größte
   Verbraucher ist meist der, der fragt). Es druckte weiter und endete
   mit Code 0, während es schon abräumbar war. Jetzt `SIGKILL` über
   `signal.send_task` — derselbe Weg wie `kill -9`, Code 137.
2. **Ein Container an seiner eigenen Grenze wurde erschossen.**
   `container` 52/0 → 51/1. Die Auswahl handelt jetzt nur, wenn die
   Maschine an der Reserve steht.

`tools/oom/run.sh` 44/0: ohne Auswahl ehrliche Absage und jeder Rahmen
zurück; Reserve-Gegenprobe; mit Auswahl genau ein Kill, `sync` davor,
Code 137, kein Weiterrechnen; drei Fresser; 64 MiB; Schreibtisch —
getroffen nur die Fresser, Schreibtisch/Taskleiste/Starter leben.
Daneben `mem` 50/0, `kernel` 176/0, `posix` 150/0, `container` 52/0.

Offen: kein Auslagern, keine Warnschwelle, die Meldung steht nur auf der
Leitung, und `hogwrite` kommt nicht bis zum Schreiben.

## K-008 — Drucken über IPP

`kernel/app/drucke.fi`: druckt eine Textdatei oder ein PDF auf einen
Netzwerkdrucker über IPP (RFC 8010/8011), ohne Treiber — IPP Everywhere.
Text wird mit der Systemschrift (`/lib/mono.ttf`) als PWG-Raster
gerastert (8 Bit Grau, 300 dpi, Papiergröße aus `media-default`, 15 mm
Rand, Umbruch langer Zeilen, Seitenvorschub). Ein PDF geht Oktett für
Oktett hinaus. Ziel aus der Kommandozeile oder `/etc/drucker.conf`.
`drucke info` liest den Drucker. HTTP läuft über `knetz.send_raw` —
derselbe Klient wie für JSON, kein zweiter.

Gegenstelle ist nicht aus diesem Baum: CUPS' Referenzdrucker
`ippeveprinter` im Netz-Namensraum. Was dort ankommt, liest ein zweiter,
nach der Norm geschriebener PWG-Leser (`tools/print/pwgcheck.py`) und
dann `tesseract` (deutsch) — das Blatt muss sagen, was die Datei sagte.
`tools/print/run.sh` **61/0**.

Drei Befunde auf dem Weg:

1. **Jeder Auftrag dauerte 60 s.** Der Drucker meldete „fertig“ nach
   14 s, `drucke` sah es erst nach 60 s. Die Serienausgabe mit Zeitstempel
   je Abfrage zeigte: ab der 8. Verbindung scheitert `connect` sofort.
   Der TCP-Stack hat 8 Plätze (`MAXCONN`), und wer zuerst schließt,
   hält seinen Platz 60 s in TIME_WAIT. Behoben im Stack selbst,
   `vendor/firn/patches/0007-time-wait-slot-reuse.patch`: ist der Tisch
   voll, übernimmt eine neue Verbindung den TIME_WAIT-Platz, der am
   nächsten am Ablauf ist (Zähler `ST_TW_REUSE`). Danach 15 s für den
   ganzen Lauf (Start bis fertig), als Zusage im Läufer (≤ 40 s).
   Das betrifft jeden Klienten mit kurzen Verbindungen, nicht nur Drucken.
2. **`knetz` las bis zum Zeitlimit.** `ippeveprinter` hält die
   Verbindung trotz `Connection: close` offen; jede Antwort kostete die
   vollen 20 s. `knetz` erkennt das Ende jetzt nach RFC 9112 6.3
   (`Content-Length` oder letzter Chunk).
3. **Drei Testfehler, keine Druckfehler.** OCR liest in der Mono-Schrift
   0/O und 1/l vertauscht und verliert die Punkte eines einzelnen „Ü“
   (auf dem Seitenbild sichtbar vorhanden) — die Probetexte bestehen
   jetzt aus Wörtern ohne Ziffern, große Umlaute stehen in Wörtern.
   Und `ippeveprinter` schickt `document-format-supported` zweimal
   (`-a`-Datei plus eigene Liste); verglichen wird mit der ersten.

Nebenbei: der festgenagelte Firn-Stand `7b4c22b1` steht seit dem
Umschreiben vom 18.09. in keinem lebenden Firn-Repo mehr. Ein neuer
Flicken ändert die Marke, kein Geschwisterbaum hat sie, also konnte
nichts mehr gebaut werden. `fetch-firnc.sh` greift jetzt auf das
Bündel von vor dem Umschreiben zurück (`FIRN_BUNDLE` oder
`~/repo-backup/firn-vor-rewrite.bundle`). Dauerlösung: A-037/F-004.

Offen: kein Druckdialog in der Oberfläche, keine Druckersuche per
DNS-SD, keine Farbe, kein IPPS (TLS ist da, ungetestet gegen einen
Drucker), und auf echtem Drucker ungemessen.

## K-014 — ein Treiber lässt sich zurücknehmen

Justins Entscheidung (24.09.): Treiber sollen wie Apps nachinstallierbar
sein, nur signierte. Signiert und ladbar war schon da (Runde MODUL); was
fehlte, war der Rückweg: ein einmal signiertes Modul galt für immer.

Neu: `/lib/omod.sperre`, eine mit **demselben** Schlüssel signierte
Liste (`tools/module/mksperre.py`). Ein Eintrag ist die Ed25519-Signatur
der gesperrten `.omod` — Ed25519 ist deterministisch, eine Signatur
benennt genau eine Datei, und der Lader hat sie ohnehin in der Hand;
keine zweite Hashfunktion im Kern. `check_banlist` läuft **nach** der
Signaturprüfung des Moduls und **vor** dem ELF-Teil:

| Zustand der Liste | Ergebnis |
|---|---|
| keine Datei | nichts gesperrt |
| gültig, Modul nicht drauf | lädt (`sperre=N` in der Zahlenzeile) |
| gültig, Modul drauf | `laden=gesperrt`, `modul_init` läuft nicht |
| kaputt/falsch signiert/Länge passt nicht | `laden=sperrliste` — **nichts** lädt |

Kaputte Liste = alles zu, weil ein ignorierter Fehler hieße: ein
gekipptes Oktett entsperrt jeden Treiber darauf. Gemessen in
`tools/module/run.sh` Abschnitt 11 (vier Platten, gleiches Modul).

Ehrlich offen: **Löschen** der Liste entsperrt alles (wer `/lib`
schreiben kann, kann sie entfernen — braucht einen Mindeststand im Kern
oder im OTA-Abbild). Der Kern lädt Module weiterhin nur im Messpfad
(`modul`), nicht beim normalen Start aus `/apps/*.osp/lib/`; das ist
der nächste Schritt zu „wie Apps“. Dazu weiter: Verweiszähler beim
Entladen, zweiter Steckplatz, eigener Auslieferungsschlüssel.

## K-004 — echter Standby (S3)

Justins Entscheidung (24.09.): echtes S3, nicht nur Ruhezustand. Die
Vorrunde hatte es gelassen („Trampolin unter 1 MiB fehlt“, Angst vor
Firmware, die den Bereich anfasst). Erst gemessen, dann gebaut:

1. **Stummel-Experiment** (200 Zeilen, außerhalb des Kerns): FACS-Vektor
   auf 0x9000, SLP_TYP=1|SLP_EN nach PM1a_CNT. QEMU meldet
   `paused (suspended)`, `system_wakeup` → SeaBIOS springt 0900:0000,
   der Stummel druckt. Die Annahme hält.
2. **Erste Falle, im Experiment gefunden:** `ld -Ttext=0x100000` legt den
   ELF-Kopf als Segment bei 0xFF000 ab → der Lader überschreibt den
   BIOS-Schatten, der Aufwachweg der Firmware springt in Nullen, ohne
   eine Zeile Ausgabe. Der Kern (kernel.ld) hat kein Segment unter 1 MiB;
   `tools/s3/run.sh` prüft das.
3. **Zweite Falle, am Kern gefunden:** mit `-kernel` schreibt QEMU das
   ELF bei **jedem** Reset neu in den Speicher — und das Aufwachen aus S3
   ist ein Reset. Seitentabellen in `.bss` waren danach null, #PF bei
   0x8078 direkt nach CR0.PG. Echte Firmware tut das nicht. Der Läufer
   startet deshalb von einer 48-MiB-Platte mit Limine (BIOS).

Gebaut: der Aufwachcode am Ende von `arch/x86_64/smp.s` (0x8000, eigene
GDT, 16→32→64 Bit, danach GDT/IDT/CR4/XCR0/CR0/MSRs/TR, alle Register
wie vor dem Schlaf — zweite Rückkehr von `s3_save` mit 1), und
`pwr/s3.fi`: sichert und schreibt zurück, was S3 löscht und die Firmware
nicht wiederherstellt — PCI-Kopf (Befehlsregister zuletzt) und MSI,
lokaler APIC und die I/O-APIC-Tafel, 8259-Masken, SCI_EN.

    tools/s3/run.sh 28/0 (KVM):  suspended -> wach stufe=4, APIC 24 Leitungen 0 falsch,
                                 PCI 6 Geraete, 11 geloeschte Register, danach 0 falsch,
                                 Speichermuster gleich (0x5b237b456dd7f146), 2 Zyklen,
                                 Zeitgeber danach 20 Takte / 200 ms, Kern bis "kernel: done"
    Gegenprobe s3kaputt:         schlaeft genauso, Firmware weckt, Kern kommt NICHT zurueck
    TCG von Hand:                dasselbe

Offen: kein Knopf dafür (Syscall + Menüpunkt fehlen), Treiber mit
Zustand im Gerät (Netzkarte, xHCI, NVMe, HDA) haben keinen Aufwachpfad,
die anderen Prozessoren werden nach dem Aufwachen nicht neu gestartet,
unter OVMF/UEFI und auf echtem Blech ungemessen.

## Pflicht-Abnahmen auf dem Endstand

(siehe Tabelle unten, nach dem letzten Lauf eingetragen)
