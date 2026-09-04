# Runde STARTKNOPF

Repo `/root/osum-blechhid`, Basis `6589cac`. Alles hier ist an Justins
Fotos vom echten Brett gemessen (Ryzen, RTX 3060, 3440x1440, UEFI) oder
im Prüfstand nachgestellt — und wo etwas **nicht** belegt ist, steht das
dabei.

---

## 1. Der Absturz — aufgelöst

Die Absturzanzeige aus der Runde BLECHFUENF hat zum ersten Mal Zahlen
geliefert:

    RIP 0x000000000010049C   CS 0x0008   ERR 0x0
    RSP 0x000000004007F000   CR2 0x000000004007EFF8

`objdump -d` auf genau das Abbild, das Justin gebootet hat:

    000000000010046d <enter_user_task>:
      10046d: mov  %rdi,%rcx
      100470: mov  $0x202,%r11
      100477: mov  %rsi,%rsp
      ...
      10049c: sysretq          <-- HIER

Das ist der Übergang nach Ring 3 (`kernel/arch/x86_64/switch.s`),
gerufen aus `proc.user_start`. `rcx` trägt dabei `T_ENTRY`, `rsp` den
`T_USTACK` — und 0x4007F000 ist genau `proc.ARGS_BASE`, der
Stapelzeiger **jedes Programms von der Platte**. Es wurde also gerade
ein Programm gestartet.

`sysretq` fasst keinen Speicher an; ein `#PF` ist an dieser Adresse
unmöglich. Mit Fehlercode 0 in Ring 0 bleibt genau eine Deutung:
**`#GP(0)`**, und den wirft dieser Befehl aus genau einem Grund — ein
**nicht kanonischer Rücksprungzeiger in `rcx`** (AMD APM Bd. 3, SYSRET:
„#GP(0) if the target RIP is non-canonical"; Intel SDM Bd. 2B
gleichlautend).

### Das `cr2` war ein Irrläufer

Ein `#GP` fasst `cr2` nicht an. Die Zahl 0x4007EFF8 stand noch von dem
Seitenfehler, mit dem der Stapel dieses Prozesses gewachsen war —
0x4007F000 minus 8 ist genau der erste `push` eines frisch gestarteten
Programms. Sie hat die Analyse in die falsche Richtung geschickt
(„fehlgeschlagener PUSH"), und deshalb steht `cr2` ab dieser Runde
**nur noch bei `#PF`** auf dem Schirm; bei allem anderen erscheint es
mit dem Vermerk „ALT, gilt nur bei PF".

### Warum es die Maschine mitnimmt und nicht nur das Programm

Das `sysretq` steht in **Ring 0**. `trap.user_fault` verlangt
`(cs & 3) == 3`; ein Fehler mit `cs=0x0008` fällt also an jeder
Signalbehandlung vorbei bis `trap.report`, und das hält an. **Ein**
Programm mit kaputtem Einsprung nimmt den ganzen Rechner mit.

### Behoben

* `proc.user_start` prüft Einsprung **und** Stapelzeiger vor dem
  `sysretq`. Was nicht in der unteren Hälfte des Adressraums liegt
  (also alles Nichtkanonische **und** jede Kernadresse), kommt gar
  nicht bis dorthin. Der Prozess stirbt mit Code 127, die Maschine
  läuft. Kosten: zwei Vergleiche, einmal je Programmstart.
* `elf.spawn` lehnt einen Einsprung außerhalb dieser Hälfte schon beim
  Laden ab (`R_ENTRY`) und sagt es (`elf: entry abgelehnt e=…`).

### Gegenprobe

`tools/einsprung/run.sh` mit dem neuen Kernwort `einsprung`: jedes
Programm von der Platte bekommt einen Einsprung von
`0xDEAD000000000000` — nicht kanonisch, also genau Justins Fall.
Zusage: der Start wird abgelehnt, **es gibt keine Ausnahme**, und der
Fensterserver läuft weiter bis `wm: hold`. Vor dieser Runde wäre der
Lauf mit genau dem Bild gestorben, das Justin fotografiert hat.

Der Läufer prüft außerdem am fertigen Abbild nach, dass
`enter_user_task` wirklich auf `sysretq` endet — bricht diese Zusage,
ist die Analyse oben neu zu machen.

---

## 2. „ANGEHALTEN" war gelogen

Justin hat den Absturz fotografiert, dann die Maus bewegt — und die
rote Anzeige war weg, alles wieder grün, die Zähler liefen weiter
(B31 → B2626 → B7085).

Der Grund steht in `power.halt_forever`: das ist `cli; hlt`, und das
hält **den Kern an, auf dem es läuft**, nicht die Maschine. Lief der
Fehler auf einem anderen Kern, steht der bis zum Ausschalten still und
der Rest merkt nichts. Der nächste Tafelanstrich vom lebenden Kern hat
die rote Anzeige dann überschrieben — und damit das wichtigste
Beweisstück des Abends.

**Ab hier gibt es eine Absturzklinke.** Nummer, Vektor, RIP, CS, ERR
und **der Kern** werden gemerkt, und solange sie steht, malt die Tafel
sie in **jedem** Anstrich in den Zeilen 22/23 wieder mit:

    22 KNALL N 1 VEK 13 #GP K 3 WEITER
    23 KRIP  0010049C  CS 0008 ERR 0000 RSP 4007F000

Die Vollbildanzeige sagt jetzt `KERN n HAELT AN` oder
`KERN n LAEUFT WEITER` statt pauschal „ANGEHALTEN", und nennt Aufgabe,
PID und **Programmnamen** — die Frage „welches Programm war das"
beantwortet damit ein Foto.

---

## 3. Die Tastatur

Justins Fotos: `18 TAST D 2 BER 14 ARM 15 CC 1` und
`11 USB … KBD 2 TAS 7`. **Sieben Tastendrücke sind angekommen.** Punkt
erledigt.

Vorsorglich gebaut, weil es die wahrscheinlichste Ursache für ein
Wiederauftreten ist: ein Unterbrechungsendpunkt, der einen Stall (6)
oder einen Übertragungsfehler (4) gemeldet hat, steht in xHCI im
Zustand `halted` und nimmt **keinen Block mehr an** (xHCI 1.2, 4.6.8).
In `usb.service` stand an dieser Stelle nur `arm` — also klingeln auf
einen Endpunkt, der nicht mehr zuhört: `ARM` läuft hoch, `BER` steht.
Genau dieses Zahlenbild. Die Maus läuft weiter, weil sie nie einen
Fehler hat; in QEMU kommt es nie vor, weil ein nachgebildetes Gerät
keine Übertragungsfehler erzeugt.

`unstall()` (Reset Endpoint + CLEAR_FEATURE(ENDPOINT_HALT) + Set TR
Dequeue) wird jetzt auch für Unterbrechungsendpunkte gerufen, nicht nur
vom Massenspeicher. Dazu eine Wiedereintrittssperre um `service` — die
Wiederbelebung wartet auf den Regler, und `service` kommt aus der
Unterbrechung **und** aus `poll`.

Messbar auf zwei neuen Zeilen:

    20 ENDP  KBD EP1 F0 H0 MAU EP1 F0 HEI 0 OP 0
    21 FUND  3:ADCB 5:ADCB 7:AD-- 9:A--- 11:----

`EP` ist der Endpunktzustand **aus dem Gerätezusammenhang** — das ist
die Sicht des Reglers, nicht unsere Buchführung: 1 läuft, 2 angehalten,
4 Fehler. Zeile 21 löst den Widerspruch „FUND 5 DEV 2 FAIL 0" auf:
`FAIL` zählt nur die Fehlschläge **vor** dem Geräteplatz; wer an
`Address Device`, am Deskriptor oder an der Konfiguration scheitert,
verschwand lautlos. Jetzt steht je Fund, wie weit er kam (A adressiert,
D beschrieben, C konfiguriert, B gebunden).

**Offen:** `ROH` steht auf Nullen, obwohl `TAS 7` zählt. Das heißt: der
Bericht wird verstanden (die Tasten kommen an), aber der Rohpuffer, aus
dem die Tafel liest, ist nicht der, in den geschrieben wird — der
generische Weg (`hidin.report`) benutzt einen eigenen. Kosmetik an der
Anzeige, kein Fehler an der Eingabe.

---

## 4. Der Klick im Starter

Kein Fehler an der Trefferfläche: eine Liste löste bis hierher **nur
beim Doppelklick** aus (`wlib.fi`, `s_lastclick`). Für einen
Dateimanager ist das richtig — dort wählt man oft und öffnet selten.
Für ein Startmenü ist es falsch: dort ist der einzige Zweck eines
Klicks, das Programm zu starten.

`wlib.list_einklick(i, true)` macht das zu einer Eigenschaft **dieser
Liste**; der Explorer behält seinen Doppelklick.

---

## 5. Die Taskleiste

Justins drei Befunde, drei unabhängige Ursachen.

**„St" und „Termina" abgeschnitten.** Kein Platzmangel bei 3440
Bildpunkten, sondern `TASK_MAX = 132` und ein Titel, der nicht
hineinpasst. Windows 11 löst das nicht mit mehr Platz, sondern mit
einem **Symbol** — ein Symbol wird nie abgeschnitten. Neuer Schlüssel
`labels=never|always|room`, Vorgabe `never`. Gemessen im Prüfstand:
`btn i=0 id=7 x=38 y=9 w=30 h=22 t=` — quadratisch, ohne Text.

**Der Startknopf trägt das Markenzeichen** statt des Wortes.
Gemessen: `taskbar: marke n=16 x=11 y=12 ink=236` — 236 gesetzte
Bildpunkte, also wirklich ein Bild und kein leeres Rechteck.

**„kein Akku" auf einem Tischrechner.** Ein Feld ohne passende Hardware
wird gar nicht mehr gezeichnet — kein Rechteck, kein Symbol, kein Satz.
Dasselbe für das Netz ohne Netzkarte. `hide_missing=0` stellt das alte
Verhalten her. Gemessen: im Prüfstandslauf kommt das Wort `battery` in
der ganzen seriellen Ausgabe **null**mal vor, und die Feldliste enthält
nur noch `net` und `clock`.

**Die Uhr stand.** Sie zeigte nur Stunde und Minute und wurde deshalb
höchstens **einmal je Minute** neu gemalt — eine Leiste, die 59
Sekunden dasselbe Bild zeigt, ist von einer eingefrorenen nicht zu
unterscheiden. Neu: `clock_seconds`, `clock_date`, `clock_weekday`,
`clock_lines` (2 = Uhrzeit über Datum). Die Feldbreite rechnet sich aus
dem Text, wächst also mit dem Format mit. Gemessen:
`text clock … t=18:28:06 04.09.26`, Feldbreite von 53 auf 148
gewachsen. Der Wochentag wird nach Sakamoto gerechnet, weil
`SYS_SYSINFO` keinen liefert.

### Was ich NICHT belegen konnte

Justins Verdacht, die Leiste werde nur einmal gezeichnet und nehme
keine Eingaben mehr an, habe ich **nicht sauber reproduziert**. Im
Prüfstand bei 3440x1440 malt sie weiter (Uhr 18:16 → 18:17, `paints=3`
→ `paints=4`); ein zweiter Lauf blieb bei einem einzigen Anstrich
stehen, aber dort lag die Tafel bei `HZ 6` und `LOOP 0` — die Maschine
war schlicht zu langsam, und das ist ein QEMU-Artefakt und nicht
Justins Fehler (sein Brett meldet `HZ 99`, `LOOP 810`).

Deshalb gibt es dafür jetzt **eine Zahl statt einer Vermutung**:
Tafelzeile 12 endet auf `TB <n>` — der Zustand der Aufgabe hinter der
Leiste (1 bereit, 2 läuft, 3 **schläft**, 4 wartet, 5 **Leiche**, 0
keine). Sie steht im **Zeitgeberpfad** und nicht in Zeile 7: Zeile 7
kommt aus der Schreibtischschleife, und wenn die hängt, fehlt genau die
Zeile, die man dann bräuchte.

---

## 6. Das Startmenü und die Super-Taste

`kbd.fi`: **Super allein** — gedrückt und losgelassen, ohne dass
dazwischen eine andere Taste kam — setzt jetzt ebenfalls einen
Hotkey-Puls, mit dem Code **0**. Kein Zeichen hat den Wert null, also
kann ihn keine Buchstabenkombination erzeugen. Die klassische Falle ist
berücksichtigt: Super gedrückt halten und dabei mit der Maus arbeiten
löst **nicht** aus.

`taskbar.fi` liest die Klinke nach demselben Zählerprotokoll wie
`qs.step` (Super+A) und schaltet das Startmenü um — mit `WA_TOGGLE`,
also demselben Weg, den ein Klick auf den Fensterknopf schon nimmt.
Der Startknopf ruft dieselbe Funktion; vorher startete er bei jedem
Druck einen **weiteren** Starter.

`launcher.fi`: kein Fensterrahmen und keine Titelleiste mehr
(`window_plain`, Ebene `L_TOP`), verankert an der echten Lage des
Startknopfes — die Ausrichtung kommt aus `/etc/taskbar.conf`
(`align=`), **derselben Datei**, die auch die Leiste liest. Escape
schließt.

Das ist **Stufe 1** des Auftrags. Symbolraster, „zuletzt benutzt" und
Benutzerzeile (Stufen 2–4) sind nicht gebaut.

---

## 7. Super+A — das Kontrollzentrum gibt es schon

`kernel/user/qs.fi` ist genau dieses Panel, seit der Runde NETVIEW: es
öffnet mit **Super+A** über der Ecke der Leiste, schließt mit Escape,
mit einem Klick daneben und mit einem zweiten Super+A.

Es hat **drei** Kacheln und nicht sechs, und der Kopf der Datei
begründet jede Auslassung einzeln — mit derselben Regel, die Justin für
den Infobereich aufgestellt hat: *eine Kachel für etwas, das dieses
System nicht hat, ist keine Platzhalterin, sondern eine Lüge mit
runden Ecken.* Kein Ton (`grep -ri audio kernel/*.fi` findet
`A_VOLUME` im FAT-Treiber und sonst nichts), keine Helligkeitsrampe
auf diesem Zweig, kein Schema-Verzeichnis, keine Benachrichtigungen.
WLAN und Bluetooth gibt es in diesem Kern nicht.

Damit ist Punkt 8 der Liste inhaltlich erfüllt; was fehlt, fehlt an
der **Hardware-Unterstützung** und nicht an dem Panel.

---

## 8. Kosmetik

| Punkt | Stand |
|---|---|
| zwei bunte Kästchen rechts | hängen seit BLECHFUENF an `pulsled` und sind in Eintrag 1 **aus** |
| `RND 2200221` bei `LOOP 440` | kein Fehler: `RND` sind die Runden der Schreibtischschleife, `LOOP` die Tafelanstriche daraus. Steht seit BLECHFUENF im Kopfkommentar |
| `HZ` in Zeile 8 und 10 | Zeile 10 heißt seit BLECHFUENF `SCHL` |
| LED-Herzschlag | seit BLECHFUENF an `pulsled`, in Eintrag 1 aus |
| Blit-Versatz bei 3440 | in Justins letzten drei Fotos **nicht mehr aufgetreten**. Nicht nachgestellt, nicht behoben — offen als Beobachtung |

Dazu ein Fund am Rand: die Bandgrenze in `fb.set_band` lag bei zwei
Fünfteln der Schirmhöhe. 24 Tafelzeilen sind auf 1440 Bildpunkten 583,
und 583·5 ≥ 1440·2 — Ergebnis `fb: band=0`, **kein Band**, und die
Messtafel wieder überschreibbar. Zum zweiten Mal in zwei Runden still
ausgefallen. Die Grenze ist jetzt die halbe Höhe.

---

## 9. Ziel 4: `jarvisd` und `ota` auf echtem Blech

### (a) Was fehlt, damit `jarvisd` auf Justins Brett läuft

Im Abbild ist alles: `/bin/jarvisd` (aus `APPS="fetch jarvisd"`),
`/bin/jsig`, `/bin/jarvisctl`, `/etc/jarvis/rechte.conf`,
`/etc/ssl/roots.pem`. Es fehlen **drei** Dinge, und keines davon ist
Programmcode:

1. **Ein Netz.** Die Schreibtisch-Einträge fahren mit
   `nic nip=169.254.10.1/16 nsvc=0 nwait=0` — eine feste
   Verbindungslos-Adresse, kein DHCP, kein DNS. Justins Tafel zeigt
   genau diese Adresse. Für `jarvisd` braucht es eine Route ins
   Internet: `dhcp` auf der Kommandozeile statt `nip=`, oder eine
   feste Adresse plus Vorgaberoute plus Nameserver.
   **Und der Treiber muss seinen Chip kennen.** `kernel/netdev.fi`
   führt e1000/e1000e/I219/I225/I226/I210 (Intel) und
   8139/8168/8169/8136/8125/8126/3000 (Realtek). Ein Ryzen-Brett hat
   meistens einen Realtek 8125 — der steht in der Tabelle, ist aber im
   Kopf von `r8169.fi` ausdrücklich als **nicht gemessen** vermerkt.
   Der erste Schritt ist also nicht Code, sondern eine Zahl:
   `netdev: tab <vid>:<did>` aus Justins Lauf.
2. **Die Rechteliste.** `/etc/jarvis/rechte.conf` liegt im Abbild, aber
   **ab Werk steht alles auf `nein`** (`befehle`, `bildschirmfoto`,
   `systeminfo`). Ohne Rechteliste startet der Dienst gar nicht; mit
   der ausgelieferten darf er nichts. Justin muss die drei Zeilen auf
   `ja` setzen und Serveradresse und Zertifikatsnamen eintragen.
3. **Die Kopplung.** `jarvisctl koppeln` erzeugt über `jsig` den
   Ed25519-Ausweis des Geräts; der öffentliche Teil muss auf der
   Serverseite eingetragen werden. Ohne das lehnt die Gegenstelle die
   Anmeldung ab.

Konkret für den nächsten Blechlauf: `dhcp` in die Kommandozeile,
booten, `netdev:`-Zeile fotografieren. Steht dort ein Chip aus der
Tabelle und danach eine Adresse aus dem Router, ist der Rest
Konfiguration.

### (b) `ota` von Ende zu Ende, und wie Pakete in den Feed kommen

`ota` **läuft** von Ende zu Ende — gemessen in `tools/ota/run.sh`
gegen `tools/ota/server.py` mit echtem TLS 1.3 (OpenSSL auf der
Gegenseite), echter Zertifikatskette gegen `/etc/ssl/roots.pem`,
echtem `Range`/`206`, echten Verbindungsabbrüchen und einer echten
Netzkarte. Was dort **nicht** echt ist: die Leitung ist kurz, es gibt
keinen Zwischenspeicher und keinen DNS.

Auf dem Blech fehlt genau dasselbe wie bei `jarvisd`: **eine
Netzverbindung mit DNS**. `/etc/ota.conf` trägt einen **Namen**
(`quelle=https://store.fleitec.com/osum/aktuell`), keine Adresse — das
Gerät löst ihn selbst auf. Mit `nip=` und `nsvc=0` gibt es keinen
Nameserver, also kann `ota suchen` nicht funktionieren. Zweitens muss
`/system/schluessel.pub` im Abbild liegen; ohne den vertrauten
Schlüssel nimmt `ota` kein Verzeichnis an. Der Abbildbau nimmt ihn aus
`/srv/store/osum/aktuell/schluessel.pub` — der ist da.

**Der Feed enthält nur `hallo-2.opk`**, ein Testpaket. Echte Programme
kommen so hinein:

    tools/ota/veroeffentlichen.py <auslieferung> --stand <verzeichnis> \
        --bund <bund.json> [--notiz <text>]

Das Werkzeug macht aus einem Stand eine Auslieferung: es baut die
Pakete, zählt die Fassungsnummer in `register.json` hoch (sie geht nie
zurück, auch nicht durch eine Rücknahme), legt `pakete/<sha256>.opk`
inhaltsadressiert ab, verknüpft sie hart nach `v/<n>/` und `aktuell/`
und signiert INDEX und VERZEICHNIS. Alte Fassungen weiter vorzuhalten
kostet damit nur Verzeichniseinträge.

Ein `.opk` je Programm baut `tools/ota/pakete.sh` (es setzt auf
`tools/install/pakete.sh` und `tools/update/pakete.sh` auf). Für die
`PROGS` des Schreibtischs — `desktop taskbar settings launcher
explorer netview edit …` — ist das ein Stand mit `/bin/<name>` und
einem Bündel unter `/apps/<name>.osp/`; genau die Form, die
`tools/k15/bundle.py` schon erzeugt.

**Ehrlich:** ich habe (b) in dieser Runde **nicht ausgeführt**. Der
Feed hat nach dieser Runde denselben Inhalt wie vorher. Was oben steht,
ist aus dem Quelltext der Werkzeuge gelesen, nicht gemessen — das
erste echte Selbst-Nachinstallieren ist eine eigene Runde und hängt an
Punkt (a), dem Netz.

---

## Neue Kommandozeilenwörter

| Wort | Wirkung |
|---|---|
| `einsprung` | jedes Programm von der Platte bekommt einen nicht kanonischen Einsprung. Gegenprobe zu Justins Absturz — die Maschine muss überleben |

## Neue Schlüssel in `/etc/taskbar.conf`

| Schlüssel | Werte | Vorgabe im Abbild |
|---|---|---|
| `labels` | `never`, `always`, `room` | `never` |
| `clock_seconds` | 0/1 | 1 |
| `clock_date` | 0/1 | 1 |
| `clock_weekday` | 0/1 | 0 |
| `clock_lines` | 1/2 | 1 |
| `hide_missing` | 0/1 | 1 |
