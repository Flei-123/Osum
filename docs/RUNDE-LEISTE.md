# Runde LEISTE

Repo `/root/osum-blechhid`, Basis `0471a84`. Justin bootet erst wieder,
wenn es wirklich läuft — also steht in diesem Papier nur, was **gemessen**
ist, und wo etwas nicht gemessen ist, steht das dabei.

---

## Das Ergebnis in einem Satz

**Blocker 1 (die Taskleiste hört nach ~20 s auf zu malen) und Blocker 2
(der unsichtbare Speicherüberschreiber) waren derselbe Fehler, und es
gab ihn dreimal:** ein Stapel läuft unten heraus und schreibt in das,
was zufällig darunter liegt. Wer das Opfer ist, entscheidet die
Bindereihenfolge — deshalb sah es aus, als hätte ein `import` etwas
kaputt gemacht.

---

## 1. Wie der Fehler gefangen wurde

Die Absturzanzeige aus der Runde BLECHFUENF sagte, **wohin** gesprungen
wurde, und nichts darüber, **woher**. Also bekam `trap.report_user` drei
Zahlen mehr: den Stapelzeiger, die **physische** Adresse dahinter, den
Kernstapel des Prozesses — und die Wörter auf dem Benutzerstapel, die wie
Programmcode aussehen (die Kette der Rücksprungadressen).

Der erste Lauf damit:

    user fault: pid=4  vector=14  err=0x15  cr2=0xd70  rip=0xd70
      spur rsp=0x40079dd0  phys=0x3169dd0  kstack=0x2eca000
          0x573068 0x573068 0x505fd0 0x505fd0 0x527000 0x3169f00 0x3169e90

Drei Dinge stehen da, und jedes einzelne beweist den Fall:

* `phys=0x3169dd0` — der **Benutzerstapel** des Starters liegt physisch
  auf 0x3169dd0. Der Kernstapel der Aufgabe daneben fängt bei
  **0x316A000** an, also **0x230 Oktette darüber**.
* `0x527000` ist `kdata`. `0x573068` liegt in der **Modusseite**
  (`kdata + MODE_OFF`). Kein Programm in Ring 3 kann diese Zahlen kennen.
* `0x3169f00` und `0x3169e90` sind Zeiger **in dieselbe Seite** — das
  Selbstbild eines Stapels.

Ein Kernstapel war unten herausgelaufen und hatte in den Rahmen darunter
geschrieben. Dass `rip` bei jedem Lauf eine **andere** Zufallszahl war
(0xd70, 0x296c1a), passt genau dazu: es war nie ein bestimmter Fehler,
es war eine überschriebene Rücksprungadresse.

`rip=0x296c1a` löst sich auf zu `wm.mess_kol+0x79` — einer **Kernadresse**
auf dem Benutzerstapel. `err=0x15` (vorhanden, Ring 3, Befehlsholen)
sagt dasselbe: das Ziel war eine Seite, die Ring 3 nicht ausführen darf.

### Die Zahl, die es beweist

Tafelzeile 12 endet jetzt auf `KS <n>` — der höchste Kernstapelstand
aller Aufgaben, aus der Färbung zurückgelesen. Gemessen im
Schreibtischlauf:

    KS 39992

**39 992 Oktette.** Die alten acht Rahmen sind 32 768. Der Stapel war
also um **7 224 Oktette zu klein** — und was in diesen 7 224 Oktetten
landete, gehörte jemand anderem.

---

## 2. Drei Stapel, drei Reparaturen

### (a) Die Kernstapel der Aufgaben — `kernel/sched.fi`

* `KSTACK_FRAMES` **8 → 16** (32 → 64 KiB). Bei 32 Aufgaben 2 MiB.
* **Eine Wächterseite unter jedem Stapel.** `frame_run` holt
  `KSTACK_FRAMES + 1` Rahmen; der unterste gehört nicht zum Stapel, wird
  mit `0xC0DEFACEC0DEFACE` gefüllt und bei **jedem Zeitgeberschlag** für
  die laufende Aufgabe geprüft (zwei Lesezugriffe). Bricht sie, kommt
  eine Zeile mit Aufgabennummer, PID, Tiefe und Stapeladresse — und der
  Zähler steht auf der Tafel (`WA`).

Eine echte, im Seitenverzeichnis ungemappte Wache wäre schöner. Sie geht
nicht: der Kern bildet den unteren Speicher mit 2-MiB-Seiten ab, und eine
einzelne 4-KiB-Seite daraus zu entfernen hieße, die Kachel für **jeden**
Stapel in eine Seitentabelle aufzulösen. Ein geprüfter Wachwert findet
denselben Fehler.

### (b) Der Startstapel des Kerns — `kernel/arch/x86_64/boot.s`

Der zweite Fund, und der gefährlichere. Sobald die Messtafel auf 24
Zeilen ging:

    *** EXCEPTION 14 #PF  err=0xb  cr2=0xb2c140  rsp=0x5096c0
    *** EXCEPTION 14 #PF  err=0x2  cr2=0xa00000  rsp=0x503ea0

`err=0xb` hat das **RESERVED-Bit**: der Prozessor fand in einem
Seitentafeleintrag Bits, die dort nicht stehen dürfen. Und der zweite
`rsp` ist **0x503ea0** — das lag genau in `pml4` (0x503000).

Die alte Reihenfolge in `.bss` war

    pml4, pdpt, pd, tss, boot_stack(16K), kernel_stack(64K), ...

und ein Stapel wächst nach unten. `kernel_stack` — der Stapel, auf dem
`kmain` die ganze Kette der Startstufen fährt — lief unten heraus, durch
`boot_stack` und `tss` hindurch, und **fraß die Seitentafeln**. Danach ist
jede Adresse des Rechners eine Zufallszahl.

Drei Änderungen:

1. **Die Seitentafeln und das TSS stehen jetzt oben**, hinter allen
   Stapeln. Kein Stapel dieses Kerns erreicht sie noch.
2. **Ein Wachfeld von 128 KiB** unter dem untersten Stapel.
3. `kernel_stack` **64 → 256 KiB**. `.bss` kostet nichts im Abbild.

Neue Lage, aus `nm -n`:

    00503000 B stack_guard_lo      128 KiB Wachfeld
    00523000 b boot_stack_bottom
    00527000 b kernel_stack_bottom 256 KiB
    00567000 B kernel_stack_top
    00573000 b pml4                jetzt OBERHALB der Stapel
    00576000 B tss

### (c) Die Messtafel — `kernel/kgui.fi` und `kernel/wm.fi`

Der dritte Fund, und er ist **wörtlich** das, was die Runde STARTKNOPF
gesucht hat („irgendwo im Baum schreibt etwas über das Ende eines Feldes
hinaus; vorher traf das etwas Folgenloses, nach der Umordnung die
Modusseite"):

    static mut tafel_txt: [u8; 960]      // 20 * 48
    static mut tafel_len: [u64; 20]
    static mut tafel_fg:  [u64; 20]

Diese drei standen fest auf **20**, während die Zahl der Zeilen eine
**Konstante** eine Seite weiter oben ist. `tafel_len` und `tafel_fg`
fliegen bei 24 Zeilen mit `index out of bounds` auf (gemessen,
`kgui.fi:3170`). **`tafel_txt` nicht** — dort wird über
`kstate.set8(ziel + i, …)` geschrieben, also mit rohem Zeiger und ohne
Grenze. Vier Zeilen zu 48 Oktetten gingen **still** hinter das Feld, und
was dahinter liegt, entscheidet die Bindereihenfolge. Der `import cpu`
war der Würfel, nicht die Ursache.

Dazu, **zum vierten Mal**, dieselbe Zahl an zwei Stellen: `MESS_ZEILEN`
in `wm.fi` stand auf 20, `TAFEL_ZEILEN` in `kgui.fi` auf 24. Ergebnis
war diesmal kein schwarzes Drittel, sondern ein `#PF` im Kern
(`fb.fill_words`, der Löschbalken einer Zeile, die es nicht gibt).

Behoben: alle Größen hängen an derselben Zahl, `messzeile` nimmt keine
Zeilennummer mehr an, die es nicht gibt, und **`kgui` vergleicht die
beiden Zahlen beim Start** und meldet Ungleichheit auf die Leitung. Vier
Runden sind an dieser Verwechslung verlorengegangen; der Vergleich kostet
eine Zeile.

---

## 3. Die Messung stand auf dem falschen Fenster

`wm.top_layer_win` liefert das oberste Fenster der Ebene `L_TOP`. Der
Kommentar dort sagte „dorthin legt `taskbar.fi` sich, und sonst nichts" —
das stimmte, bis die Runde STARTKNOPF das **Startmenü** auf dieselbe
Ebene legte. Seitdem zeigte Tafelzeile 7 die Anstriche und den
Aufgabenzustand des **Starters** und meldete „die Leiste lebt", während
die Leiste stand.

Neu: `wm.panel_win` fragt nach dem, was eine Taskleiste wirklich ausmacht
und was ein Menü nie tut — sie reserviert eine **Kante des Schirms**
(`W_STRUT != 0`). Gemessen im Prüfstand:

    tafel: 7 LEISTE id9 y1400 MAL 27 fl2 ZU 1

`y1400` — das ist die Leiste am unteren Rand, nicht der Starter bei
y=110.

---

## 4. Was die Tafel jetzt zeigt

24 Zeilen, Band 582 von 1440. Neu oder geändert:

| Zeile | Inhalt |
|---|---|
| 12 | `… TB <zustand> WA <wächterbrüche> T <tiefe> KS <höchster Kernstapelstand>` |
| 20 | `ENDP` — eigener Platz statt 14 |
| 21 | `FUND` — eigener Platz statt 17 |
| 22 | `NETZ K<treiber> BDF <bus> L <verbindung> ABL <n>:<vid>:<did> IP <a.b.c.d>` |

`WA` **muss null bleiben.** Steht dort etwas anderes, hat ein Kernstapel
in fremden Speicher geschrieben, und jeder andere Messwert auf der Tafel
ist ab da eine Vermutung.

---

## 5. `jarvisd` — was gebaut ist und was fehlt

### (a) Die eine Angabe, die ich von Justin brauche

> **Boote Eintrag 1, warte bis der Schreibtisch steht, und fotografiere
> Tafelzeile 22 (`22 NETZ …`). Diese eine Zeile.**

Sie beantwortet alles auf einmal:

* `K 0` → **kein Treiber**. Dann steht dahinter `ABL n:vvvv:dddd` —
  Hersteller und Gerät des ersten abgelehnten Chips. Genau diese vier
  Hexziffernpaare fehlen mir; damit steht fest, ob sein Chip in
  `netdev.fi` fehlt oder ob der vorhandene Treiber ihn nicht hochbekommt.
* `K 3` → r8169 hat übernommen. `L 1` heißt Kabel steckt.
* `IP 169.254.x.x` → DHCP hat nichts gebracht; `IP <heimnetz>` → die
  Leitung ist fertig.

Ersatzweise vom Windows-Rechner: Geräte-Manager → Netzwerkadapter →
Eigenschaften → Details → **Hardware-IDs**, dort steht
`PCI\VEN_10EC&DEV_8125`. Das sind dieselben zwei Zahlen.

### (b) Was ohne diese Angabe gebaut wurde

* **`dhcp` steht im Haupteintrag** des Schreibtischs
  (`tools/usbimg/build.sh`). Die feste `nip=169.254.10.1/16` bleibt
  daneben stehen: kommt kein Angebot, ist der Rechner genauso bedienbar
  wie vorher, nur ohne Netz. Ein Schreibtisch, der auf DHCP **wartet**,
  wäre ein Rückschritt.
* **`jarvisd -d`** — die Startdiagnose. Geht die Kette der Reihe nach
  durch und schreibt je Glied ein Wort: Netzstapel, Adresse, Maske, Tor,
  Rechteliste (mit Server, Befehlen, Foto, Systeminfo), Geräteschlüssel,
  Wurzelzertifikate, Bildschirm. So gebaut, dass ein **Foto** davon
  reicht.
* **`jarvisd -f <datei>`** — das Bildschirmfoto als **PPM**, ohne Netz,
  ohne Server. Vorlage ist `r_ppm` aus `lib/fenster/win32.fi` des
  Certus-Zweigs. PPM und nicht PNG, weil es hier in eine **Datei** geht:
  kein zlib, kein Zwischenpuffer über dem ganzen Bild — Kopfzeile, dann
  Zeile für Zeile durch. Auf 3440×1440 sind das 14,9 MiB, die sofort auf
  die Platte gehen statt vorher in den Speicher.

### (c) Das Server-Ende — es gibt keines

Gemessen, nicht vermutet:

    grep -rl 'jarvisd\|kopplung-noetig\|fotoschein' /root/jarvis \
        --include=*.js --include=*.mjs --include=*.py
    -> nur Chatverläufe unter data/conv/, kein Code

Der Windows-Helfer (`/root/jarvis/client/helper.py`) spricht **WebSocket
gegen jarvis.fleitec.com** — ein völlig anderes Protokoll als `jarvisd`
(TLS 1.3, Ed25519-Ausweis, zeilenweise Aufträge). Es gibt auf dem
JARVIS-Server **keinen Endpunkt**, der `jarvisd` annehmen würde.

Die einzige funktionierende Gegenstelle ist
`tools/bridge/peer.py` im Osum-Zweig — ein Prüfstandsserver mit
eigenem Zertifikat, der die Aufträge aus einer Datei liest.

**Was gebaut werden müsste** (ich fasse den JARVIS-Server nicht ohne
Rückfrage an):

1. Ein TLS-Anschluss auf dem Server mit einem Zertifikat, dessen Name in
   `/etc/jarvis/rechte.conf` als `servername` steht.
2. Der Anmelde-Handschlag: Zufallsforderung hinaus, Ed25519-Unterschrift
   herein, Gerätekennung gegen eine Liste öffentlicher Schlüssel.
3. Die Erstkopplung: `kopplung-noetig <code>` hinaus, Code im Cockpit
   anzeigen, warten bis das Gerät `jarvisctl koppeln <code>` bestätigt hat.
4. Ein Auftragskanal für `befehl`, `lies`, `schreib`, `liste`, `foto`,
   `system` — und die Antwort auf `foto` als PNG in den Chat.

Das ist eine eigene Runde auf der Serverseite, und sie hängt vor allem an
Punkt (a): ohne Netz auf dem Blech nützt der beste Endpunkt nichts.

### (d) Schritt für Schritt für Justin

    # 1. Terminal auf dem Schreibtisch öffnen
    # 2. Sehen, ob überhaupt ein Netz da ist:
    jarvisd -d

    # 3. Wenn Punkt 2 der Diagnose eine 169.254er-Adresse zeigt:
    dhcp
    jarvisd -d          # noch einmal, jetzt sollte eine echte Adresse stehen

    # 4. Ein Bildschirmfoto, ganz ohne Server:
    jarvisd -f /var/jarvis/schirm.ppm

    # 5. Die Rechteliste (sie steht ab Werk auf "nein"):
    edit /etc/jarvis/rechte.conf

`/etc/jarvis/rechte.conf`, die drei Zeilen, die zählen:

    server         = <adresse des jarvis-servers>:8443
    servername     = <name im zertifikat>
    befehle        = ja
    bildschirmfoto = ja
    systeminfo     = ja

Woran er sieht, dass die Verbindung steht: `jarvisd -v` schreibt
`jarvisd: bereit` und danach je Auftrag eine Zeile; ohne Gegenstelle
bleibt es bei `bereit` und wachsender Wartezeit (250 ms, verdoppelnd bis
30 s) — **das ist kein Fehler, das ist der fehlende Endpunkt aus (c)**.

---

## 6. Die Abnahme

Am **fertigen Abbild**, über Limine, unter **UEFI**, 3440×1440,
xHCI-Tastatur + Tablett + Massenspeicher, e1000 mit DHCP —
Justins Aufbau, nicht der Prüfstands-Abkürzung.

| gemessen | Zahl |
|---|---|
| Anstriche der Leiste in 160 s | **164** |
| Uhr-Anstriche / davon **verschiedene** Zeiten | 164 / **163** |
| erste → letzte Uhr | `20:18:44 04.09.26` → `20:21:24` |
| Wächterbrüche (`WA`) | **0** |
| `user fault` | **0** |
| Kernausnahmen | **0** |
| höchster Kernstapelstand (`KS`) | 44 168 von 65 536 |
| Netz | `22 NETZ K2 BDF 0020 L 1 ABL 0 IP 10.0.2.15` |

**164 Anstriche in 160 Sekunden und 163 verschiedene Uhrzeiten** heißt:
die Leiste malt genau einmal je Sekunde, über die ganze Zeit, ohne eine
einzige Wiederholung. Genau das war der Punkt, an dem Justin bisher
umsonst gebrannt hat.

### Klicks

`taskbar: state … clicks=10` und `taskbar: click x=… y=… hits=…` — die
Kette Kern → Fensterserver → Leiste → Trefferprüfung läuft. Ein Klick
wurde auch **wirksam**: `taskbar: drag start` → `drag done edge=3`, die
Leiste ist an den rechten Rand gewandert und hat sich neu vermessen
(`size w=104 h=1440`, `strut edge=3`).

**Was ich NICHT belegen konnte:** ein Klick, der den 30 Bildpunkte
breiten Startknopf trifft. QEMUs `mouse_move` ist im Monitor **relativ**
und in Tablett-Einheiten (gemessen: elf Bewegungen um 40…400 ergaben
x=1759…3439, also die Summe); ich habe den Knopf nicht getroffen. Das
ist eine Eigenschaft meines Prüfaufbaus, nicht des Systems.

### Die Eingabe, ohne Maus

    tafel: 11 USB   DEV 3 FUND 3 HUB 0 KBD 2 TAS 0 -> TAS 7 FAIL 0
    tafel: 18 TAST  D 2 BER 4 ARM 5 CC 1  ->  BER 18 ARM 19 CC 1

Sieben Tastendrücke, achtzehn fertige Interrupt-IN-Transfers,
Fertigmeldungscode 1, null Fehler — am fertigen Abbild.

**Super+A geht:** `taskbar: klinke seq=1 war=0 taste=97`, und das
Kontrollzentrum geht auf (`qs: text … [Netz vortäuschen]`).

**Super ALLEIN geht nicht.** Der Kern erkennt es (`hk: super allein`,
zweimal), der Leser der Leiste sieht den Zähler aber nicht steigen —
`taskbar: klinke` bleibt aus, während dieselbe Zeile bei Super+A kommt.
Der Systemaufruf und der Leser sind also in Ordnung; nur dieser eine
Puls kommt nicht an. Eingekreist, nicht behoben.

### Regression

`tools/einsprung/run.sh`: **12 von 14**.

* `FAIL 'DEAD000000000000' fehlt` — der erwartete Text im Prüfskript,
  seit der Vorrunde. Kosmetik.
* `FAIL Regellauf: 'wm: hold' fehlt` — **neu**. In demselben Lauf startet
  der Schreibtisch nachweislich (`taskbar: state n=1 paints=13`, Uhr
  läuft), nur die Marke am Ende des Haltens kommt nicht mehr in 240 s.
  Die Messtafel malt seit dieser Runde 24 statt 20 Zeilen, also rund ein
  Fünftel mehr Band je Zeitgeberrunde. Das ist eine **Laufzeit**- und
  keine Funktionsregression — aber sie ist da, und sie steht hier.

---

## 7. Was NICHT erledigt ist

* **`ROH` bleibt auf Nullen trotz `TAS 7`** — nicht angefasst.
* **Blit-Versatz bei 3440** — nicht nachgestellt, nicht behoben.
* **Startmenü Stufe 2–4** (Symbolraster, zuletzt benutzt, Benutzerzeile)
  — nicht gebaut.
* **Super+A von drei auf mehr Kacheln** — geht nicht ohne Ton- und
  Helligkeitsunterstützung im Kern.
* **Der Feed** (`/srv/store/osum/aktuell/`) enthält weiter nur
  `hallo-2.opk`. `ota` läuft im Prüfstand von Ende zu Ende; auf dem Blech
  fehlt dasselbe wie bei `jarvisd`: **DNS**.
* **Die statischen Stapel haben kein Prüfwerk**, nur Abstand. Die
  Aufgaben-Kernstapel haben eines (`WA` auf der Tafel).
* **Super allein** öffnet das Startmenü nicht (siehe Abschnitt 6).
* **`wm: hold` in `tools/einsprung/run.sh`** braucht länger als 240 s.
