# STANDBY (S3) MIT MEHREREN KERNEN — DD-12 / K-004c

Stand 03.10.2026, Zweig `dd12-standby`. Jede Aussage ist gekennzeichnet:
**[gemessen]** (hier ausgeführt, Zahl steht dabei), **[Quelle]** (aus dem Code gelesen),
**[unbekannt]** (niemand hat es am echten Gerät nachgesehen).

## 1. Das Problem

* **[Quelle]** Bis hierher schlief nur eine Maschine mit **einem** Prozessor: `s3.suspend` verweigerte mit
  `R_SMP`, sobald ein zweiter Kern lief — „sie sterben im S3 und werden nicht neu gestartet". Jedes echte
  Gerät hat mehrere Kerne, also ging Standby dort nie.
* **[Quelle]** Dazu verliert nach einem echten S3 jedes Gerät, was es **in sich** hält: Ringe, Warteschlangen,
  Slots, Streams. Der Kern stellte nur die Busseite wieder her (PCI-Kopf, BARs, MSI, APIC, 8259).

## 2. Was gebaut wurde

**Kerne parken** (`kernel/arch/x86_64/smp.fi`, `kernel/sched/sched.fi`, `kernel/arch/cpu.fi`):

1. `park_all` setzt je Zusatzkern `C_PARKREQ`. `sched.pick` gibt einem Kern mit Parkwunsch nichts Neues
   mehr (nur seine Leerlaufaufgabe); was er gerade lief, geht beim nächsten Wechsel zurück in die Warteschlange
   und wird von den anderen Kernen genommen.
2. Steht der Kern in seiner Leerlaufaufgabe, maskiert er seinen Zeitgeber/LAPIC (`apic.core_init`), setzt
   `C_PARKED` und wartet in `cli; hlt`. Der Startkern wartet höchstens 3 s darauf; schafft es einer nicht
   (eine an ihn gebundene Aufgabe, ein Kern, der nie im Scheduler stand), werden alle wieder gestartet und
   Standby wird **verweigert** (`R_PARK`, im Menü „2") — nie ein halber Schlaf.
3. Nach dem Aufwachen startet `unpark_all` jeden geparkten Kern **wie beim ersten Mal** (INIT + 2×STARTUP auf
   demselben Stapel, derselben GDT und derselben TSS-Seite; die Trampolin-Kopie wird neu in die niedrige Seite
   geschrieben, weil der S3-Aufwachblock dieselbe Seite benutzt hat). Der Kern kehrt in seine Scheduler-Schleife
   mit **derselben** Leerlaufaufgabe zurück — es wird nichts neu angelegt.

**Geräte nach S3** (`kernel/pwr/s3dev.fi`, je ein `resume`-Haken im Treiber): jeder Haken ist die eigene
Erststart-Folge des Treibers noch einmal (deren `init` setzt die Hardware ohnehin zuerst zurück):

| Gerät | Haken | Was dabei geprüft wird |
|---|---|---|
| NVMe | `nvme.resume` | Controller aus, Admin- + I/O-Warteschlange, Identify; danach lesen die ersten 8 Sektoren dieselbe Prüfsumme |
| AHCI | `ahci.resume` | HBA neu, Ports, Befehlslisten; dieselbe Prüfsumme |
| xHCI/USB | `usb.resume` (= `versuch`) | Regler neu, alles neu aufgezählt; die Tastatur ist wieder da **und ein Tastendruck nach dem Aufwachen kommt an** |
| e1000-Familie | `netdev.resume_cards` | Karte neu, Ring neu; ein ARP für das Gateway wird beantwortet |
| HD-Audio | `hda.resume` | Regler, Codec-Graph, Weg; Lautstärke bleibt (die „schon versuchten Buchsen" werden zurückgesetzt — `init` hatte sie nie gelöscht, ein zweiter Lauf fand deshalb keinen Weg) |

**Uhr** (`sched/time.fi`): vor dem Schlaf merkt sich der Kern RTC-Sekunden und monotone Uhr; danach zieht er die
Zählerbasis so, dass die monotone Uhr dort weiterläuft, wo sie stand (auch wenn die TSC bei null anfängt), und
rückt die Echtzeit um die **Differenz** der RTC vor — nicht um deren Absolutwert, damit eine per SNTP
gestellte Uhr richtig bleibt.

## 3. Wie es gemessen wird

QEMU schneidet beim Schlaf keinem Gerät den Strom ab. Eine Messung „Gerät geht nach dem Schlaf" wäre deshalb
leer. Das Kernwort **`s3loss`** ist die **Stromverlust-Simulation**: vor den Haken wird jedes Gerät so zurückgesetzt,
wie ein Stromausfall es hinterlässt (NVMe: `CC.EN=0`, AHCI: `GHC.HR`, xHCI: `HCRST`, e1000: `CTRL.RST`, HDA: `CRST=0`).
Die Gegenprobe **`s3nohooks`** setzt dasselbe zurück und führt die Haken **nicht** aus.

* **`tools/s3smp/run.sh`** [gemessen]: `-smp 2` und `-smp 4`, je drei Schlaf-Zyklen hintereinander (der Kern
  schläft aus `s3smp` heraus, nachdem die Zusatzkerne in ihrer Scheduler-Schleife stehen — der Zustand eines
  laufenden Schreibtischs). Je Zyklus: die VM schläft wirklich (QEMU-Monitor), `kerne geparkt online=1`, `kerne wieder
  online=N`, **jeder Kern** (nicht nur online) hat 300 ms danach ≥ 10 Zeitgebertakte mehr, die Leerlaufdrehungen der
  Zusatzkerne wachsen, die Echtzeit hat die Schlafzeit nachgeholt (3 Schlaf à ≥ 2 s: Summe ≥ 6 s), der Kern läuft
  bis zum Ende. Gegenprobe `s3nostart` (Kerne parken und **nicht** neu starten): der Takt-Test schlägt an
  (Kern 1: 41 → 42 Takte).
* **`tools/s3dev/run.sh`** [gemessen]: eine Maschine mit NVMe, USB-Tastatur an xHCI, e1000 hinter QEMUs
  Benutzernetz, HD-Audio, zwei Kernen; dazu eine mit AHCI. Je drei Zyklen mit `s3loss`: **24/0** — NVMe/AHCI
  Prüfsumme gleich, Tastatur da und Taste angekommen, Netz up und ARP-Antwort, Audio bereit. Gegenprobe
  `s3nohooks`: NVMe nicht zurück (`resume=0`), Taste kommt nicht an, nichts wird empfangen.
* **`tools/s3/run.sh`** [gemessen] Abschnitt 8: der Menüweg (`standby --wish` unter dem Fensterserver) schläft jetzt
  mit **2 und mit 4** Kernen und wacht auf (Antwort 1, alle Kerne wieder da); **55/0**.

## 4. Gefundene und behobene Fehler

* **HD-Audio:** `init` ist nicht wiederholbar — das Bitfeld „Buchse schon versucht" (`TRIED_OFF`) wird nie
  gelöscht, ein zweiter Lauf fand deshalb für **jede** Buchse „schon versucht" und meldete „kein Weg Wandler →
  Buchse". Der Haken löscht es vor dem Lauf. [gemessen: `hda: codec 0 p=1 w=1 c=0` vor, `dev hda resume=1` nach dem Fix]
* **Zeit nach S3:** ohne Nachziehen blieb die Echtzeit um die Schlafzeit zurück (QEMU: 1 s .. 21 s in den Läufen).
* Kein Fehler im Aufwachblock selbst; der Weg dahin (`s3.fi`) war bis auf die Kerne vollständig.

## 5. Was nur am echten Gerät geprüft werden kann (Prüfpunkte für den Boss)

Alles unten ist **[unbekannt]** — QEMU/SeaBIOS bildet es nicht nach:

1. **Mehrkern auf echter Hardware:** Standby → Taste: kommen alle Kerne zurück? (`dmesg`-Zeile `s3: kerne wieder online=N` auf der seriellen Leitung / im Foto).
2. **UEFI/OVMF:** auf dem Dell-Stick (nicht SeaBIOS) — andere FACS/Wake-Vektor-Wege (r145).
3. **Tastatur/Maus an einem echten xHCI** nach dem Aufwachen (QEMU-Regler behält seinen Zustand, die Simulation setzt ihn zurück — ein Intel/AMD-Regler kann anders aufwachen, z. B. mit gesetzten Ports/Legacy-Handover).
4. **Netzkarte I217/I219 (Dell)**: der e1000-Haken ist gegen die QEMU-e1000 gemessen; die PCH-Karte hat einen anderen Aufwachweg (PHY-Reset, Link-Wartezeit). **virtio-net und r8169 werden bewusst nicht angefasst** (nie gemessen).
5. **Platte am echten SATA/NVMe**: Prüfsumme der ersten Sektoren (der Haken liest sie; ein echter NVMe braucht evtl. die Wartezeit `CSTS.RDY`).
6. **Grafik:** es gibt keinen GPU-Treiber (r36); auf UEFI-Rechnern ohne GPU-Treiber bleibt das Bild oft schwarz — der Kern sagt nicht „Bild kommt" sondern restauriert nur den Bochs-/Framebuffer-Modus.
7. **Audio**: Codec nach echtem Stromverlust (QEMU-Codec behält seine Einstellungen; ein echter fängt bei null an — der Graph-Lauf ist derselbe wie beim Start).
8. **Dauer-Stresstest**: 20 Zyklen hintereinander mit laufendem Schreibtisch.

## 6. Grenzen (ehrlich)

* **Keine Auswahl nach Bedarf:** ein Gerät, dessen Haken fehlt (WLAN, Bluetooth, Kamera: es gibt keine Treiber; virtio-net/r8169;
  eine USB-Platte als Wurzel — der Stick kommt als **neues** Gerät, der Einhängepunkt folgt nicht), ist nach dem Aufwachen so, wie der Strom es hinterlassen hat.
* **Deckel → Standby** und **Auto-Standby nach Zeit** sind nicht gebaut (Akku/Deckel: K-003). Heute sperrt der Deckel nur.
* Der Parkweg braucht, dass die Zusatzkerne im Scheduler oder in `phases` stehen (jeder Boot, der `smp.stage` gefahren ist);
  sonst: Standby wird verweigert, nicht halb ausgeführt.
* Aus einem **Systemaufruf** heraus (`/bin/standby`) läuft die Folge mit gesperrten Unterbrechungen; die Treiberhaken
  gehen dann über ihre Abfragewege (NVMe/AHCI/xHCI bei Wartezeiten per Zyklenzähler). [gemessen: `tools/s3/run.sh` Abschnitt 7 + 8]
