<!-- SPDX-License-Identifier: GPL-2.0-only -->
# Runde STICK — die zwei Dinge, die noch zwischen Justin und dem USB-Anschluss standen

Arbeitsbäume `/root/osum-stick` (Zweig `stick`, von `main` `e59c3b2`) und
`/root/osum-schirm` (Zweig `schirm`). Gemessen am 03.09.2026 auf dem
üblichen Wirt (AMD EPYC 7571, 12 Kerne, 19 GiB, `/dev/kvm`, QEMU 7.2.22).

`docs/BLECH-BEREIT.md` hat den Auftrag selbst geschrieben: zwei Punkte,
beide klein, beide standen dem Satz „steck den Stick rein" im Weg.

1. **Auf dem Stick fehlten sieben Programme** (Abschnitt 7 der Tafel).
2. **Die Oberfläche füllte den Schirm nicht** (Abschnitt 4, `49 % × 50 %`
   bei 1280x800), und deshalb war der Zweig `schirm` nicht in `main`.

Beides ist erledigt. Dabei sind **fünf** Fehler gefunden worden, von denen
im Auftrag nur einer stand.

---

## DIE RUNDE IN SECHS ZEILEN

1. **Der halbe Schreibtisch war eine Wand bei 1024 Bildpunkten.**
   `wig.blit` — der einzige Weg, auf dem ein Programm aus Ring 3
   Bildpunkte in sein Fenster bekommt — hat jede Zeile **abgelehnt**, die
   breiter war als der Umschlagpuffer (`w > MAX_ROW`, MAX_ROW = 1024).
   Schreibtisch und Taskleiste sind so breit wie der Schirm.
2. **Behoben durch Zerlegen statt Ablehnen**: 100 % × 100 % auf
   800x600, 1280x800, 1920x1080 und 2048x1152, Taskleiste sichtbar.
3. **`schirm` hätte zwei weitere Abnahmen rot gemacht** — GFX 76/0 →
   62/14, TILING 68/0 → 51/17 —, und das hatte niemand gemessen. Ursache:
   sieben Läufer prüfen die eingebaute Vorgabe 800x600 und bekommen seit
   SCHIRM QEMUs EDID von 1280x800. Behoben in der Messung, nicht im Kern.
4. **Die sieben Programme sind auf dem Stick** — und mit ihnen `dhcp`
   und `reboot`, ohne die die anderen nichts können. 43 → **52**.
5. **DHCP ging vom Stick aus gar nicht.** Ein DISCOVER an
   255.255.255.255 lief durch `next_hop` und ARP; ohne eingetragenes
   Gateway blieb es liegen. Drei Zeilen im Stapel, und `kernel/user/dhcp.fi`
   hatte genau diese drei Zeilen vorhergesagt.
6. **Gemessen im laufenden System, vom Abbild**, unter BIOS und UEFI:
   `dhcp`, `host store.fleitec.com`, `fetch` gegen den echten Server mit
   echter Let's-Encrypt-Kette, `ota suchen` über den **Namen**, und
   `jarvisd`, das einen Auftrag über die Brücke beantwortet.
   **`STICK: 42 bestanden, 0 gescheitert`.**

---

## TEIL 1 — DER HALBE SCHREIBTISCH: DIE URSACHE, MIT ZAHLEN

### 1.1 Was die vorige Runde gemessen hatte

`docs/RUNDE-BLECH-ECHT.md`, Teil 3, und `docs/SCHIRM.md`, Abschnitt 7,
sagten dasselbe aus zwei Richtungen:

| Start | Rahmenpuffer | gezeichneter Inhalt | Taskleiste |
|---|---|---|---|
| nativ | 1280x800 | `24..650 × 40..443` — **49 % × 50 %** | **nicht sichtbar** |
| `fbres=800x600` | 800x600 | `0..798 × 0..599` — 100 % | sichtbar |

und dazu der Befund, der sich als richtig herausgestellt hat: *„Es fehlt
nicht die Auflösung, sondern das, was das Bild zusammensetzt."*

### 1.2 Die erste Messung dieser Runde: welche Farbe fehlt

Das Bild von damals (`docs/shots/schirm-vor-1280x800.png`) enthält
1 024 000 Bildpunkte, davon **781 118 in genau einer Farbe (16,20,26) —
76,3 %**. Zwei weitere Farben kommen in beiden Bildern **gleich oft** vor:

| Farbe | 1280x800 | 800x600 |
|---|---:|---:|
| (18,24,32) | 127 309 | 127 216 |
| (28,36,48) | **48 330** | **48 330** |

Zwei Fenster werden also **identisch** gemalt, und der Verlauf des
Schreibtischs fehlt **ganz**. Der Fensterauszug des Servers sagt, welche:

```
wm: win nr=0 z=1 layer=1 deco=1 x=24  y=40  w=560  h=380  ow=564 oh=404  [Terminal -- sh]
wm: win nr=1 z=0 layer=0 deco=0 x=0   y=0   w=1280 h=800                 [desktop.title]
wm: win nr=2 z=4 layer=2 deco=0 x=0   y=768 w=1280 h=32   strut=32       [Taskbar]
wm: win nr=4 z=3 layer=1 deco=1 x=190 y=110 w=440  h=300  ow=444 oh=324  [Suchen]
```

Terminal (564 breit) und Starter (444 breit) sind da. Schreibtisch (1280)
und Taskleiste (1280) fehlen. **Das umschließende Rechteck der beiden
sichtbaren Fenster ist genau `24..650 × 40..443`.**

### 1.3 Die Spur, die es entschieden hat

Eine Zeile in `wm.paint_win` (danach zurückgenommen), die für jedes
Fenster ohne Schmuck ab 1000 Bildpunkten Breite meldet, was sie kopiert
— und **welche Farbe im Fensterpuffer steht**:

```
WDBG i=1 w=1280 h=800 buf=0x14b0000 c=0,0-1280,800 b=0,0-1280,800 n=1280 px=0x10141a
```

* Das Zusammensetzen **arbeitet**: der schmutzige Bereich ist das ganze
  Bild, das Rechteck stimmt, 1280 Bildpunkte je Zeile.
* Im Puffer steht **`0x10141a` = (16,20,26)** — die Farbe, mit der
  `wm.create` ein neues Fenster füllt. Der Verlauf des Schreibtischs ist
  **nie angekommen**.
* Für die Taskleiste kam die Zeile **überhaupt nicht**: ohne Blit läuft
  auch kein `wm.damage`, und was nie schmutzig wird, wird nie gemalt.

### 1.4 Die Ursache, wörtlich

`kernel/wig.fi`:

```
const STAGE_MAX: u64 = 4096
// Die breiteste Bildpunktzeile, die durch den Umschlagpuffer passt.
// 4096 / 4 = 1024, und der Bildschirm dieser Runde ist 800 breit.
const MAX_ROW: u64 = 1024 // STAGE_MAX / 4

fn blit(...) {
    if w == 0 || h == 0 || w > MAX_ROW { return 0 }
```

Der Kommentar nennt den Grund selbst. `wig.blit` ist der **einzige** Weg,
auf dem ein Ring-3-Programm Bildpunkte in sein Fenster bekommt
(`wlibc.push` → `WIG_BLIT`). Eine Zeile breiter als 1024 → `return 0`, und
zwar stillschweigend. Auf 800x600 und 1024x768 fiel das nie auf; ab 1280
sind Schreibtisch und Leiste betroffen und sonst nichts.

Die Zusage des Selbsttests, die das grün abgesegnet hat, stand auf dem
Kopf: *„Ein Blit, das breiter ist als der Umschlagpuffer, wird abgelehnt
— und nicht halb ausgeführt."*

### 1.5 Die Behebung

**Nicht der Puffer wurde größer** — das wäre eine Änderung an der
Speicherkarte gewesen, und genau daran hat sich Runde BLECH-ECHT zweimal
die Finger verbrannt (`docs/RUNDE-BLECH-ECHT.md`, 2.2 und 2.3). Statt
dessen zerlegt `blit` eine zu breite Zeile in `stuecke(w)` Umschläge von
je MAX_ROW. Bis 1024 ist das **genau ein Umschlag und damit derselbe Weg
wie vorher**; darüber sind es mehrere. `stuecke` steht als eigene
Funktion da, weil die neue Zusage 2 sie an beiden Kanten nachrechnet.

### 1.6 Nachher, gemessen

`bash tools/screen/build.sh` + ein Start je Auflösung, Bildschirmfoto aus
dem QEMU-Monitor, umschließendes Rechteck der Bildpunkte, die nicht die
häufigste Farbe sind:

| Tafel | Rahmenpuffer | gezeichneter Inhalt | Farben in den untersten 40 Zeilen | Bild |
|---|---|---|---:|---|
| 800x600 | 800x600 | `0..799 × 0..599` — **100 % × 100 %** | 60 | `docs/shots/schirm-nach-800x600.png` |
| 1280x800 | 1280x800 | `0..1279 × 0..799` — **100 % × 100 %** | 59 | `docs/shots/schirm-nach-1280x800.png` |
| 1920x1080 | 1920x1080 | `0..1919 × 0..1079` — **100 % × 100 %** | 59 | `docs/shots/schirm-nach-1920x1080.png` |
| 3840x2160 | 2048x1152 ¹ | `0..2047 × 0..1151` — **100 % × 100 %** | 59 | `docs/shots/schirm-nach-4k-2048x1152.png` |

¹ QEMU meldet für einen 4K-Schirm keine Zeitlage; der Kern nimmt den
größten Kurzsatz. Das ist der bekannte Punkt 4 aus `docs/SCHIRM.md`.

Eine Farbe in den untersten 40 Zeilen hieße „da ist nur Hintergrund" —
das war der Zustand vorher (**1**). Und die Leiste steht auch als Form
im Bild: Start-Knopf und Fensterknöpfe links (x 16..336), Netz, Akku und
Uhr rechts (x 1024..1280).

Selbsttests auf allen vier: `fb 13/13`, `wm 30/30`, `wig 7/7`.

### 1.7 Und die dritte vergessene 2048

`wm.place_win` (Kacheln) hatte denselben Deckel noch stehen, den
`resize_win` in Runde SCHIRM verloren hat. Auf einem 2560er Schirm blieb
ein gekacheltes Fenster kleiner als sein Platz. Jetzt
`MAX_W_HARD`/`MAX_H_HARD`; die echte Grenze prüft `reframe` zwei Zeilen
tiefer ohnehin.

---

## TEIL 2 — WAS `schirm` SONST NOCH KAPUTT GEMACHT HÄTTE

Der Zweig ist in BLECH-ECHT an **einer** roten Zusage gescheitert
(`usbimg`). Diese Runde hat die Abnahme breiter gefahren, und da standen
zwei weitere Abschnitte rot:

| Abschnitt | auf `main` | mit `schirm` | danach |
|---|---:|---:|---:|
| `GFX` | 76 / 0 | **62 / 14** | **76 / 0** |
| `TILING` | 68 / 0 | **51 / 17** | **68 / 0** |
| `WM` | 103 / 0 | 103 / 0 | 103 / 0 |
| `PAINT` | 36 / 0 | 36 / 0 | 36 / 0 |

Die vierzehn und die siebzehn sagen alle dasselbe:

```
FAIL  800x600 bei 32 Bit je Bildpunkt -- 'fb: 800x600x32' fehlt
FAIL  Zeilenlaenge 3200 = Breite mal vier -- 'pitch=3200' fehlt
FAIL  das Foto ist 800x600 -- der Bildmodus wurde wirklich gesetzt -- 1280 800
FAIL  der ganze Schirm sind: 1024000, erwartet eq 480000
```

**Das ist kein Fehler des Kerns.** Er tut seit SCHIRM das Richtige: er
fragt die Tafel. QEMUs `-vga std` trägt ab Werk einen EDID-Block mit
1280x800. Falsch ist die MESSUNG: sie stellt eine Maschine mit Tafel hin
und verlangt die Zahl einer Maschine ohne. Also bekommen genau diese
Läufe eine Maschine ohne Tafel — `-global VGA.edid=off`, ein Wort je
Aufrufstelle in sieben Läufern. Der EDID-Weg behält seine eigenen
Messungen: `tools/display/run.sh` Abschnitt 4 (dieser eine Lauf bekommt
seine Tafel ausdrücklich zurück), `tools/customres/run.sh`, und
`docs/messungen/schirm/`.

---

## TEIL 3 — DIE SIEBEN PROGRAMME

### 3.1 Was fehlte und warum

`docs/BLECH-BEREIT.md` Abschnitt 7: der Stick trug **43** Ring-3-Programme,
und `ota`, `fetch`, `host`, `jarvisd`, `jsig`, `jarvisctl`, `pollbr`
waren nicht darunter. Es fehlte eine Zeile Bauliste und der App-Bauweg.

`tools/usbimg/build.sh` hat jetzt beides — den App-Weg **wörtlich** aus
`tools/install/build.sh`, damit es eine Bauart gibt und nicht zwei:

| | vorher | nachher |
|---|---:|---:|
| `PROGS` (profile kernel) | 43 | **50** (+ `dhcp host ota jsig jarvisctl pollbr reboot`) |
| `APPS` (`--profile=app`, TLS 1.3) | — | **2** (`fetch`, `jarvisd`, 1 532 800 Oktette) |
| Programme im Abbild | 43 | **52** |
| Pflichtpfade | 24 | **36** |

`dhcp` und `reboot` stehen nicht im Auftrag und gehören trotzdem dazu:
ohne `dhcp` gibt es kein `/etc/resolv.conf`, und ohne das ist
`store.fleitec.com` eine Zeichenkette und keine Adresse.

**Eine Stolperstelle beim App-Bauweg**, weil sie beim nächsten Mal wieder
kommt: `FIRNLIB` bleibt auf `lib/` und zeigt **nicht** auf
`vendor/firn/lib`. `fetch` braucht beide Hälften — `std.io`, `std.net`,
`tls.tls` von Firn und `libc.dns` aus diesem Repo. Der Übersetzer sucht
erst in `$FIRNLIB` und danach in `<Verzeichnis des Übersetzers>/../lib`,
und das ist `vendor/firn/lib`. Mit `FIRNLIB=vendor/firn/lib` fällt
`libc.dns` heraus:
`error: cannot read 'kernel/app/libc/dns.fi' --> fetch.fi:88`.

### 3.2 Und was die Programme brauchen, um etwas zu KÖNNEN

Ein `/bin/ota` ohne Vertrauensanker ist ein Programm, das nichts annimmt.
Neu im Abbild:

| Pfad | was | woher |
|---|---|---|
| `/etc/ssl/roots.pem` | 15 261 Oktette, **11 Mozilla-Wurzeln** | `tools/hwnet/mkroots.py` (`$OTA_ROOTS` überschreibt) |
| `/etc/ota.conf` | `quelle=https://store.fleitec.com/osum/aktuell`, **`auto=nein`** | Vorgabe, `$OTA_CONF` überschreibt |
| `/system/schluessel.pub` | 32 Oktette, der Schlüssel der Auslieferung | `/srv/store/osum/aktuell/schluessel.pub`, `$OTA_KEY` überschreibt |
| `/system/FASSUNG`, `/system/SCHLUESSELGEN` | je neun Oktette fester Breite | `$OTA_FASSUNG`, `$OTA_KGEN` |
| `/etc/jarvis/rechte.conf` | die Rechteliste — **ab Werk alles aus** | Vorgabe, `$JARVIS_CONF` überschreibt |
| `/etc/jarvis/`, `/var/`, `/var/log/`, `/var/jarvis/`, `/etc/ssl/` | die Verzeichnisse | — |

Zwei Entscheidungen stehen ausdrücklich so da und nicht anders:

* **`auto=nein`.** Ein Stick, der ab Werk von selbst irgendwo nachfragt,
  wäre eine Entscheidung, die niemand getroffen hat. Der Mensch tippt
  `ota suchen`.
* **Die Rechteliste ist leer.** Kein Server, keine Befehle, kein
  Bildschirmfoto, keine Pfade. `jarvisd` startet damit und meldet sich
  nirgends an. Wer ihn benutzt, trägt ein, was er darf — oder gibt eine
  eigene Datei mit `jarvisd -c`.

Fehlt der Schlüssel beim Bauen, wird er **nicht erfunden**: dann steht er
nicht im Abbild, das Bauskript sagt es (`schluessel  KEINER — ota nimmt
kein Verzeichnis an`), und `ota` sagt es beim ersten Versuch.

### 3.3 Zwei neue Menüeinträge und einer, der eine Netzkarte bekommen hat

Bis hierher konnte man auf dem Stick nur **zusehen**: Diagnose oder
Schreibtisch. Es gab keinen Eintrag, in dem ein Mensch etwas tippen kann
— und das waren genau die Programme, die auch nicht drauf waren.

```
/Osum -- Kommandozeile mit Netz (dhcp, host, fetch, ota, jarvisd)
    cmdline: modfs osum vfs nic nip=169.254.10.1/16 nsvc=0 nwait=0 console=ttyS0 nosched noproc nofs
```

* `console=ttyS0` macht COM1 zu einem richtigen Terminal (Runde
  SERVERBUILD): auf einem Rechner ohne Tastatur der einzige Weg herein,
  und das Warten auf eine Zeile wird unbegrenzt statt vier Sekunden.
* `vfs` gibt die Einhängetafel — und hängt nebenbei eine FAT-Partition
  auf der zweiten Platte beim Start unter `/mnt` ein.
* **Warum da trotzdem eine Adresse steht, obwohl `dhcp` sie holen soll:**
  `netsvc` startet den Stapel nur, wenn `nip=` etwas nennt; ohne sagt der
  Kern `kein Netz im Kernel` und `/bin/dhcp` hat keinen Socket. Gemessen.
  `169.254.10.1/16` ist verbindungslokal (RFC 3927) und kollidiert per
  Definition mit keinem Heim- oder Firmennetz; der erste `dhcp` ersetzt sie.

Der Eintrag *„nur der Schreibtisch (deutsch)"* hat dieselbe Karte
bekommen — ohne sie blieb er für immer bei „kein Netz", und das Terminal
darin konnte `dhcp` nicht fahren.

Damit hat `limine.conf` **sieben** Einträge (vier aus USBIMG/MERGE-5,
zwei aus SCHIRM, einer aus dieser Runde).

---

## TEIL 4 — DER FEHLER, DEN NIEMAND BESTELLT HAT: DHCP GING NICHT

Der erste Lauf vom fertigen Abbild:

```
osum$ dhcp
dhcp: discover xid=2380164160  mac=82840185286
   (nichts mehr, 90 Sekunden lang)
```

`kernel/user/dhcp.fi` hat den Grund selbst aufgeschrieben, lange vor
dieser Runde:

> HINAUS: dort fehlt der Sonderfall. `net_output` sucht auch für
> 255.255.255.255 den nächsten Sprung und fragt per ARP nach dessen
> Hardwareadresse — statt ff:ff:ff:ff:ff:ff zu nehmen. Antwortet
> niemand, bleibt das Paket liegen. […] Dafür bräuchte der Stapel drei
> Zeilen mehr, und der Stapel ist festgenagelter Vorrat (vendor/firn) —
> er gehört dieser Runde nicht.

**Er gehört dieser Runde.** Ein Startstick, dessen DHCP nur dann geht,
wenn schon ein Gateway eingetragen ist, ist kein Startstick — beim ersten
Start in einem fremden Netz ist genau das nicht der Fall.

`vendor/firn/lib/net/stack.fi`, `net_output`, vor `next_hop`:

```
if (*s).out_dst[e] == 0xFFFFFFFF {
    var bc: [u8; 6] = [0 as u8; 6]
    wire.mac_broadcast(&bc[0])
    wire.eth_build(slot, &bc[0], &(*s).mac[0], wire.ETYPE_IP4)
    wire.copy(buf, slot, len)
    (*s).out_head = out_next(e)
    bump(s, NS_TX)
    return len
}
```

Nach dem Rundruf fragt man nicht: die Hardwareadresse ist
ff:ff:ff:ff:ff:ff, und zwar immer. Danach, derselbe Stick, derselbe
Befehl:

```
osum$ dhcp
dhcp: discover xid=4168622220  mac=82840185286
dhcp: offer ip=10.0.2.15  maske=255.255.255.0  gateway=10.0.2.2  server=10.0.2.2
dhcp: request ip=10.0.2.15
dhcp: ack ip=10.0.2.15  lease=86400  weg=0
dhcp: gesetzt ip=10.0.2.15
dhcp: /etc/network.conf geschrieben, Oktette 103
dhcp: /etc/resolv.conf geschrieben, dns 1
osum$ dhcp -> 0
```

Der Zweig greift **nur** für Ziel 255.255.255.255 — Pakete, die bis
hierher stillschweigend liegengeblieben sind. Alles andere geht
unverändert über `next_hop`.

**Und er überlebt den nächsten Bau.** `vendor/firn/lib/` ist nicht
eingecheckt (`.gitignore`), und `fetch-firnc.sh` räumt es mit `rm -rf`
weg und legt es aus dem festgenagelten Firn-Commit neu an. Eine Änderung,
die nur dort liegt, wäre beim nächsten `--force` still verschwunden — und
der DHCP-Klient hätte wieder geschwiegen, ohne dass jemand etwas geändert
hat. Deshalb liegt sie als **eingecheckter Flicken** unter
`vendor/firn/patches/0001-rundruf-ohne-arp.patch`, mit der Begründung im
Kopf, und `fetch-firnc.sh` legt sie nach dem Auspacken auf. Ein Flicken,
der nicht passt, bricht den Bau ab — eine halb geflickte Bibliothek wäre
schlimmer als eine ungeflickte, weil der Fehler dann anderswo auftaucht.
Wohin die drei Zeilen wirklich gehören, steht in `REMOVE-FROM-FIRN.md`:
nach Firn.

---

## TEIL 5 — DIE ABNAHME: `tools/stick/run.sh`

Der Unterschied zu `tools/usbimg/run.sh` in einem Satz: **dort** wird
gemessen, dass das Abbild STARTET, **hier**, dass man damit etwas TUN
kann. Deshalb kein `qemu -kernel`: der Kern kommt vom Abbild über Limine,
der Menüeintrag wird über den QEMU-Monitor gewählt (vier Mal nach unten,
dann Eingabe — wie ein Mensch am Bildschirm), und danach wird auf der
seriellen Leitung **getippt** (`tools/server/console.py`).

**`STICK: 42 bestanden, 0 gescheitert`** — angemeldet in `test.sh` als
Abschnitt 39.

### 5.1 BIOS, vom Stick

```
osum$ dhcp                      -> 0   ip=10.0.2.15, dns 1
osum$ cat /etc/resolv.conf      -> 0   nameserver 10.0.2.3
osum$ host store.fleitec.com    -> 0   109.69.172.199
osum$ fetch https://store.fleitec.com/index.json
      fetch: aufgeloest 1833282759
      fetch: roots 11
      fetch: verify OK
      fetch: certs 4
      fetch: suite 4865           (TLS_AES_256_GCM_SHA384)
      fetch -> 0
osum$ ota suchen
      ota: fassung dort 2
      ota: NEUE FASSUNG verfuegbar
```

Und die Gegenprobe, die aus einer Beobachtung eine Messung macht:
`dig +short store.fleitec.com` auf dem Wirt sagt **dieselbe** Adresse.
Zwei Auflöser, eine Antwort.

Die Kette ist **echt**: vier Zertifikate, Let's Encrypt, geprüft gegen
die elf Mozilla-Wurzeln **im Abbild** — nicht gegen eine Wurzel, die
derselbe Lauf zwei Minuten vorher selbst erzeugt hat.

### 5.2 UEFI, dieselbe Datei

Derselbe Menüeintrag über OVMF und `/EFI/BOOT/BOOTX64.EFI`: dieselbe
Shell, dasselbe DHCP, dieselbe geprüfte Kette, dasselbe VERZEICHNIS.
(OVMF braucht länger, bis Limine malt — der Läufer wartet dort 15
Sekunden statt 9, sonst läuft die Menüwahl in den Vorgabeeintrag.)

### 5.3 Die Brücke

Gemessen gegen `tools/bridge/peer.py`, einen TLS-1.3-Server in
Python — **nicht** gegen den echten JARVIS-Server; der läuft anderswo.

**Das Abbild wird dafür nicht angefasst.** Die Rechteliste des
Prüfstands und seine Wurzel kommen auf einer **zweiten Platte** herein
(FAT32 auf einer MBR-Partition), und `jarvisd -c /mnt/rechte.conf` nimmt
sie. Das Abbild, das ausgeliefert wird, ist Oktett für Oktett das hier
gemessene.

```
osum$ mount
      … /mnt type vfat …
osum$ cat /mnt/rechte.conf      -> 0
osum$ dhcp                      -> 0
osum$ jarvisd -c /mnt/rechte.conf -1 -t 90000
      jarvisd: rechte lesen 1 schreiben 1 auflisten 1 befehle 1 foto nein system ja
      jarvisd: bereit
      jarvisd: verbunden, Verfahren 4867, Zertifikate 1
      jarvisd: angemeldet
      jarvisd: verbindungen 1  auftraege 2  abgelehnt 0
```

und auf der anderen Seite, in Python geschrieben und von Python geprüft:

```
TLSv1.3
BEWEIS gut                      (Ed25519, nachgerechnet von python-cryptography)
ANGEMELDET
ANTWORT 1 system  ok 178 c0a9b9fb…
ANTWORT 2 befehl  ok …          Nutzlast: "hallo-vom-stick"
```

**Zwei Aufträge hinein, zwei Antworten heraus, und die Ausgabe des
Befehls ist auf dem Stick entstanden.**

### 5.4 Was die Abnahme unterwegs mitgemessen hat

* **OFS lässt sich nicht zweimal einhängen.** `mount /dev/hdb /mnt ofs`
  gibt 0 und hängt den Stick noch einmal an sich selbst
  (`vfs.mount_at` endet für FS_OFS in `ofs.node_root`, egal welches
  Gerät genannt wurde). `tools/e2e/run.sh` hat das schon aufgeschrieben;
  diese Runde ist erst hineingelaufen und dann darauf gestoßen. Deshalb
  ist die zweite Platte FAT32.
* **`mount /dev/hdb1 /mnt vfat` von Hand sagt „cannot mount" und gibt 1
  — zu Recht.** Der Kern hängt mit `vfs` die FAT-Partition der zweiten
  ATA-Platte beim Start schon selbst unter `/mnt` ein
  (`kernel/kmain.fi`), und ein zweiter Eintrag auf demselben Ort wird
  abgewiesen. Für Justin heißt das: **eine FAT-Platte oder ein zweiter
  Stick ist beim Start einfach da.**

---

## TEIL 6 — DAS ABBILD

`bash tools/usbimg/build.sh`

| | BLECH-ECHT | **STICK** | Unterschied |
|---|---:|---:|---|
| Abbild | 123 731 968 | **123 731 968 Oktette (118 MiB)** | 0 |
| SHA-256 | `39a2952c…` | **`5a520aaf7835d643030d2e7e0583a2fe1f000709141b70e1649aa456a6746b57`** | anders |
| Kern | 3 789 672 | **3 844 792 Oktette** | +55 120 |
| Ring-3-Programme | 43 | **52** | **+9** |
| davon Apps mit TLS 1.3 | 0 | **2** (1 532 800 Oktette) | +2 |
| Wurzel | 20 971 520, OFS v3 | **dieselbe** | 0 |
| Pflichtpfade | 24 | **36** | **+12** |
| Umlautfolgen | 133 | 136 | +3 |
| Menüeinträge | 4 | **7** | +3 |

Der SHA-256 ist mit `sha256sum` auf dem fertigen Abbild gemessen und
nicht abgeschrieben. Er gehört zu **dieser Datei** (gebaut aus `main`
`102873b`), und ein zweiter Baulauf aus demselben Baum gibt eine andere
Prüfsumme — auch das ist gemessen und nicht vermutet: zwei `mkfs.vfat`
auf identische Eingaben unterscheiden sich in **sechs** Oktetten, bei
0x44..0x46 und 0xC44..0xC46. Das ist die Datenträgernummer der
EFI-Partition, die `mkfs.vfat` aus der Uhr nimmt, im Startsatz und in
seiner Sicherung. Das Abbild ist also **nicht** oktettgleich
reproduzierbar; wer eine bestimmte Datei meint, meint ihren SHA.

Gemessen mit genau diesem Abbild: **`STICK: 42 bestanden, 0 gescheitert`**
und **`USBIMG: 48 bestanden, 0 gescheitert`**.

---

## WAS NOCH FEHLT — ehrlich benannt

1. **Kein Rechner.** Es gibt weiterhin **keine einzige Messung auf
   echtem Blech**. Alles oben ist QEMU. Das ist unverändert der größte
   offene Punkt dieses Projekts.
2. **`jarvisd` ist gegen einen Prüfstand gemessen, nicht gegen den
   echten JARVIS-Server.** Was dafür fehlt, steht in `docs/BRIDGE.md`.
3. **`ota einspielen` vom Stick ist NICHT gemessen** — nur `ota suchen`.
   Ein Einspielen schreibt in die Wurzel, und die Wurzel des Sticks ist
   ein Boot-Modul im Arbeitsspeicher: es überlebt den Neustart nicht.
   Für ein Update, das bleibt, muss Osum erst installiert sein
   (`/bin/install`). Das ist keine Vermutung über `ota`, sondern eine
   Aussage über den Stick.
4. **WLAN** gibt es weiterhin nicht, in keiner Zeile.
5. **`struktur`** ist unverändert nicht gemerged (siehe
   `docs/RUNDE-BLECH-ECHT.md`); er ändert kein Verhalten.
6. **`UMLAUT2`** bleibt offen (24 ASCII-Umschriften), unverändert seit
   MERGE-5.
7. **Die vier Zeitzusagen** (`net`, `powermon`, `init`, `multiuser`)
   sind auch in dieser Runde nicht einzeln auf ruhigem Wirt nachgemessen
   worden.
8. **Der Rundruf-Zweig im Stapel ist gegen QEMUs Benutzernetz gemessen**,
   in dem der DHCP-Server zugleich das Gateway ist. Dass er auch in einem
   Netz greift, in dem das nicht so ist, folgt aus dem Quelltext — eine
   Messung dafür gibt es hier nicht.
