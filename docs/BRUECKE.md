# Runde BRUECKE — der Rechner meldet sich von selbst

Zweig `bruecke`, abgezweigt von `merge9` @ 6659add. Arbeitsbaum
`/root/osum-bruecke`.

Ziel: JARVIS kann mit Justins echtem OrientOS-Rechner arbeiten, ohne
dass er den Bildschirm abfotografieren muss.

---

## Die Randbedingung, aus der alles folgt

Justins Rechner steht **nicht** im Netz des JARVIS-Servers. Beide haben
zufällig 192.168.1.x, aber das sind zwei getrennte Heimnetze hinter
NAT. Der Server kann das Gerät **nie** anrufen.

Also ruft das Gerät den Server — auf dem Weg, der aus jedem fremden Netz
hinausgeht: **HTTPS auf Port 443 zu store.fleitec.com**. Derselbe Weg,
auf dem Certus seine Absturzberichte schickt; der ist gemessen und
funktioniert.

## Wo der Vorbau sitzt, und warum das nicht zu raten war

`openresty` läuft **nicht** auf dem JARVIS-Server, sondern auf
192.168.1.51 — und dorthin gibt es keinen SSH-Zugang. Gemessen wurde
dann, dass er *jeden* Pfad an den Speicherdienst weiterreicht:
`/bruecke/gesund` kam als **404 dieses Dienstes** zurück, nicht als 404
des Vorbaus, und eine frisch angelegte Datei unter `/srv/store` war
sofort öffentlich abrufbar.

Deshalb hängt die Weiterreichung in
`orientstore/werkzeug/diagnose_server.py` — an der Stelle, die
store.fleitec.com ohnehin ausliefert, und nicht in einer Konfiguration
auf einem Rechner, den dieser Baum nicht erreicht.

```
Gerät → https://store.fleitec.com/bruecke/… → openresty (.51)
      → diagnose_server.py :8088 → bruecke_server.py :8090 (nur 127.0.0.1)
```

Der Brückendienst horcht **ausschließlich** auf der Rückschleife. Von
außen kommt man nur durch die Weiterreichung — ein zweiter offener Port
wäre eine zweite Tür, die niemand bewacht.

## Langes Polling und nicht Websocket

Die Entscheidung gilt dem Prozess **am Netz**. Langes Polling braucht
dort nur, was schon da ist: eine HTTPS-Anfrage stellen, eine Antwort
lesen. Kein HTTP-Upgrade, keine RFC-6455-Rahmen, keine Maskierung, kein
zweiter Zustandsautomat in dem Programm, dessen Angriffsfläche klein
bleiben soll.

Gemessen: liegt ein Auftrag an, kommt er nach **78 ms**; liegt keiner
an, hält der Server die Anfrage **25 079 ms** offen und antwortet dann
`{"auftrag": null}`. Bei anliegender Arbeit ist die Verzögerung damit
dieselbe wie bei einem offenen Kanal.

---

## Was neu ist

| Datei | Zweck |
|---|---|
| `/root/bruecke/bruecke_server.py` | der Dienst: Anmeldung, Schlange, Ablage, Kopplung, Sperre |
| `/root/bruecke/anschluss.py` | spricht Osums Zeilenprotokoll und reicht an den Dienst weiter |
| `/etc/systemd/system/bruecke.service` | Dienst, `enabled`, nur 127.0.0.1 |
| `kernel/tipp.fi` | die eingespeiste Eingabe, Aufruf 1843 |
| `kernel/tipp-aus.fi` | dieselbe Schnittstelle, die „es gibt sie nicht" sagt |
| `kernel/user/settings.fi` | der elfte Reiter: Zustand sehen, Brücke abschalten |
| `tools/bruecke/echt.sh` | 18 Zusagen gegen store.fleitec.com |
| `tools/bruecke/kette.sh` | Osum in QEMU → Anschluss → Dienst → Bild |
| `tools/bruecke/abriss.sh` | Wiederverbindung, mit Zeitabständen |
| `tools/bruecke/reiter.sh` | der Reiter, fotografiert — **noch nicht fertig** |

Der größte Teil der Brücke stand schon: `kernel/app/jarvisd.fi` (TLS
1.3 hinaus, Ed25519, Rechteliste), `kernel/shot.fi` (Bildschirmfoto),
`kernel/user/jsig.fi`, `kernel/user/jarvisctl.fi` — aus den Runden
BRIDGE und BRIDGE-2, mit 113 gemessenen Zusagen. Diese Runde hat den
**Weg von außen** gebaut und die **fehlende Hälfte** ergänzt.

---

## Die Sicherheit

**Beidseitig ausgewiesen.** Der Server durch das echte Zertifikat von
store.fleitec.com (das Gerät prüft es, bevor es irgendetwas sendet), das
Gerät durch ein Ed25519-Schlüsselpaar, das beim ersten Start **auf dem
Gerät** entsteht. Der private Teil liegt in `/etc/jarvis/geraet.key` mit
0600 und wird von `jsig` gehalten — nicht vom Prozess am Netz.

**Kopplung.** Ein unbekanntes Gerät bekommt einen sechsstelligen Code
und sonst nichts. Der Code steht auf dem **Bildschirm des Geräts**;
freigegeben wird er über einen zweiten Weg. Beides muss ein Mensch
gesehen haben.

**Drei Ablehnungen, gemessen:**

| Fall | Antwort |
|---|---|
| falsche Unterschrift | `Unterschrift falsch` |
| fremder Schlüssel auf denselben Namen | `Schluessel passt nicht zur Kopplung` |
| gesperrtes Gerät | `dieses Geraet ist gesperrt` |

**Sichtbar am Gerät.** `jarvisctl eingabe` und der Reiter in den
Einstellungen fragen den **Kern** (`TI_INFO`), nicht den Helfer. Ein
Fernzugriff, der sich selbst bescheinigt, dass er nichts tut,
bescheinigt gar nichts.

**Abschaltbar.** In den Einstellungen, Reiter „Brücke". Der Knopf
schreibt `eingabe = nein` und `bildschirmfoto = nein` in die
Rechteliste — die der Helfer **vor jedem Auftrag** neu liest — und nimmt
einen offenen Tippschein weg.

**`--ohne-bruecke`** lässt sie ganz weg. Gemessen 4 444 Oktette kleiner,
und derselbe Befehl sagt dann „diesen Aufruf gibt es nicht" (`-ENOSYS`)
statt „du darfst nicht" (`-EPERM`). Ein Schloss kann falsch zugehen,
eine Abwesenheit nicht.

---

## Die eingespeiste Eingabe (Aufruf 1843)

Das Bildschirmfoto ohne Eingabe ist ein Fenster ohne Klinke. `tipp.fi`
speist Tasten und Mausereignisse dort ein, wo der Treiber sie ablegt:
`kbd.push_hot` und `ps2m.set_pos`/`usb_packet`. Eine eingespeiste Taste
nimmt damit denselben Weg wie eine echte — sonst prüft der Durchklick
den falschen Weg.

Dieselben drei Schlösser wie beim Foto, absichtlich dieselben: Schein,
nur Leiste oder Wurzel darf ihn ausstellen, sichtbarer Zustand. Der
Schein gilt **zwei Minuten** und höchstens **200 Anschläge** — ein
Ablauf ist eine Folge von Anschlägen, ein Schein je Anschlag wäre in der
Praxis ein Schein für alles.

### Zwei Zahlen waren falsch gegriffen

* **`TIPP_OFF`**: erst 0x8A000, weil hinter `SHOT_OFF` Luft zu sein
  schien. Dort liegt die **Aufgabentafel** (`TASK_OFF` 0x88000, 32×1024
  = bis 0x90000). `memmap.py` hat es gefangen, bevor es die
  Prozesstabelle zerschrieb. Jetzt 0x9F000, von der Karte als frei
  ausgewiesen.
* **Der Aufruf**: erst 1842 (1840 ist CPUSTAT, 1841 SHOT).
  `syscalls.py --zweige` meldete 1842 als in einem **anderen Zweig**
  vergeben. Jetzt 1843.

### Und eine Prüfung war zu streng

`tipp_call` verlangte `wm.ready`. Der Tastaturring liegt aber in
`kbd.fi` (`K11_OFF`), der Zeiger in `ps2m.fi` (`MOUSE_OFF`) — beide sind
da, sobald der Kern läuft, und das Bildschirmfoto braucht `wm` auch
nicht. Mit der Prüfung antwortete jede Einspeisung `-ENODEV`.

---

## Die Belege

### Der Weg von außen — `tools/bruecke/echt.sh`, 18/0

Gegen `https://store.fleitec.com`, durch das echte Zertifikat:
Verwalterschutz, Kopplungscode, falscher Code abgelehnt,
Zufallsforderung, falsche Unterschrift abgelehnt, richtige angenommen,
fremder Schlüssel abgelehnt, Auftrag → Bild → abgeholt (Oktett für
Oktett dasselbe), langes Polling 25 079 ms, Sperre wirkt.

### Die ganze Kette — `tools/bruecke/kette.sh`, 9/0

```
Osum (QEMU) --TLS 1.3--> anschluss.py --HTTP--> bruecke_server.py
```

```
  OK    Osum verbindet sich und zeigt den KOPPLUNGSCODE auf dem Schirm
  OK    der Dienst fuehrt das Geraet als osum-23fb577adebe
  OK    JARVIS gibt die Kopplung frei
  OK    DAS BILD IST DA -- 1280x800, 31630 Oktette
```

Serverzeilen:

```
[anschluss] ANGEMELDET als osum-23fb577adebe
[anschluss] -> auftrag 1 foto 0 0 0
[anschluss] <- fertig ok (31636 Oktett)
[bruecke]   ERGEBNIS <- osum-…: id=1 status=ok 31641 Oktett -> /srv/bruecke/geraete/…/131909-1.png
```

Das Bild liegt unter `/srv/store/belege/bruecke/osum-schuss-1280x800.png`.

### Die Wiederverbindung — `tools/bruecke/abriss.sh`, 7/0

**9 Versuche in 70 Sekunden** — bei festen 250 ms wären es rund 280.
Das ist der Beweis für den wachsenden Abstand (250, 500, 1000, …,
gedeckelt bei 30 s). **18 Systemaufrufe in 91 750 ms** Wartezeit: es
wird geschlafen, nicht gedreht.

Nach `kill -9` auf die Gegenstelle (kein FIN, kein RST — härter als ein
Router-Neustart):

```
jarvisd: verbunden … / angemeldet / warten
jarvisd: keine Verbindung      <- die Gegenstelle ist tot
jarvisd: keine Verbindung
jarvisd: keine Verbindung
jarvisd: verbunden … / angemeldet
```

### Eingabe einspeisen

Derselbe Befehl, zwei Kerne:

| Kern | Antwort |
|---|---|
| mit Brücke | `eingespeist`, Anschläge gesamt: 2 |
| `--ohne-bruecke` | `Dieser Kern hat die Bruecke NICHT` |

### Befehl und Dateien — `tools/bridge/run.sh`, 113/0 (keine Regression)

`schreib` → `lies` → *Oktett für Oktett dasselbe*; `/bin/echo` lief,
Ausgabe und Beendigungscode kamen zurück. Acht Ablehnungen mit Grund,
alle im Protokoll.

---

## Was **nicht** geklappt hat

**1. Osum spricht nicht selbst HTTPS mit store.fleitec.com.** Es
spricht TLS mit `anschluss.py`, und *der* spricht HTTP mit dem Dienst.
Für Justins Rechner heißt das: der Anschluss muss von seinem Netz aus
erreichbar sein. Das ist die eine Stelle, an der diese Runde das Ziel
nicht ganz erreicht.

*Warum so:* `jarvisd` müsste sonst zusätzlich zu TLS 1.3 einen
HTTP-Client, JSON in beide Richtungen und base64 bekommen — alles im
Prozess am Netz. Das Zeilenprotokoll dagegen ist mit 113 Zusagen
gemessen. Der nächste Schritt ist, `fetch.fi`s HTTPS-Weg in `jarvisd`
zu heben; dann fällt `anschluss.py` weg.

**2. Der Reiter ist nicht fotografiert.** Er übersetzt, steht in beiden
Sprachdateien, und die Elementtafel reicht (163 von 192 belegt, das
Muster von Runde LOOK ist geprüft). Aber der Läufer schafft es nicht,
`settings` aufzumachen: der Klick in die Starterliste trifft Terminal
statt Settings (die Liste ist anders sortiert als die
`launcher: treffer`-Zeilen), `script=settings` gibt „keine Fläche", und
`sendkey` in die `wmshell` kommt nicht an. **Dass der Reiter wirklich
gezeichnet wird, ist damit nicht belegt** — und genau diese Sorte Fehler
hat Runde LOOK einen Tag gekostet.

**3. Nicht auf echter Hardware gemessen.** Alles hier ist QEMU. Der
Sinn der Runde ist ja gerade, das zu beenden — der erste echte Lauf ist
der auf Justins Rechner.

**4. Sechs Fehler im Prüfstand**, die alle wie Fehler der Brücke
aussahen: `grep -q` in einer Pipeline mit `pipefail` (dreimal, gibt 141
statt 0), `nft add` statt `insert` (Regel hinter dem `drop`), zwei Ports
aus derselben Zahl, die Kennung aus Fließtext gefischt, jeder Start ein
frisches Abbild (also jedes Mal ein neuer Geräteschlüssel — die
Ablehnung war völlig richtig), und `--max-time 3` gegen einen Endpunkt,
der 25 Sekunden wartet.

---

## Was Justin tun muss

**Booten.** Sonst nichts.

1. `orientos-usb-20260910-bee3999.img` auf einen Stick:
   `sudo dd if=… of=/dev/sdX bs=4M conv=fsync status=progress`
2. Davon starten.
3. Den **sechsstelligen Code** vorlesen, der auf dem Bildschirm steht.
4. Ich gebe ihn frei. Ab da meldet sich der Rechner bei jedem Start von
   selbst.

Solange Punkt 1 der Einschränkungen offen ist, muss in
`/etc/jarvis/rechte.conf` die Zeile `server = <adresse>:<port>` auf den
Anschluss zeigen. Sobald `jarvisd` selbst HTTPS spricht, steht dort
store.fleitec.com und es ist wirklich nur noch booten.
