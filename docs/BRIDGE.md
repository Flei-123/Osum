# Runde BRIDGE — der JARVIS-Helfer in Osum

Zweig `bridge`, abgezweigt von `mergeline2`. Arbeitsbaum `/root/osum-bridge`.

`docs/REALHW.md` nennt das Ziel: OrientOS auf einem gewöhnlichen PC, und
darauf den JARVIS-Helfer. Auf Justins Windows-Rechnern gibt es dieses
Programm längst — der Server spricht es an, es führt Befehle aus, liest
und schreibt Dateien, macht Bildschirmfotos. Diese Runde baut das
Gegenstück für Osum.

## Was neu ist

| Datei | Profil | Zweck |
|---|---|---|
| `kernel/app/jarvisd.fi` | `--profile=app` | der Helfer: TLS 1.3 hinaus, Anmeldung, Aufträge, Rechteprüfung, Protokoll |
| `kernel/user/jsig.fi` | `profile kernel` | der Schlüsselhalter: Ed25519, hält den privaten Schlüssel |
| `kernel/user/jarvisctl.fi` | `profile kernel` | was der Mensch am Gerät sieht und entscheidet |
| `assets/jarvis/rechte.conf` | — | die mitgelieferte Rechteliste mit Begründungen |
| `tools/bridge/build.sh` | — | Kern + Userland + Helfer, zwei Profile in einem Abbild |
| `tools/bridge/peer.py` | — | die Gegenstelle für den Prüfstand (TLS 1.3, Python) |
| `tools/bridge/run.sh` | — | die Abnahme, dreizehn Abschnitte |

**Es gab schon eine Datei namens `kernel/user/jarvisd.fi`** — die Runde
POLL hat sie gebaut. Sie ist nicht der Helfer, sondern ihr Beweis in
Bauform: ein Programm, das gleichzeitig auf einen Netzanschluss und auf
das Rohr eines Kindprozesses wartet. Sie bleibt unangetastet; der Helfer
dieser Runde liegt unter `kernel/app/` und ist ein anderes Programm mit
einem anderen Profil. **Beim Zusammenführen muss einer von beiden
umbenannt werden**, denn beide wollen `/bin/jarvisd` heißen; die
Prüfstände bauen ihre Abbilder getrennt, im gemeinsamen Abbild geht das
nicht. Vorschlag: POLLs Programm wird `/bin/pollbr`.

## Warum drei Programme und nicht eines

**Der private Schlüssel gehört nicht in den Prozess am Netz.** `jarvisd`
spricht mit einem Rechner, den es nicht kontrolliert, und ist die größte
Angriffsfläche, die dieses System nach außen hat. Also liegt der
Ed25519-Samen bei `jsig`; `jarvisd` startet es, gibt ihm die
Zufallsforderung des Servers und bekommt die Unterschrift zurück. Ein
Fehler im TLS-Datensatzleser gibt dem Angreifer damit den Schlüssel
nicht.

**Und der Übersetzer erzwingt es ohnehin.** firnc führt Module unter
ihrem letzten Namen. `crypto.sha512` dieses Repos (Runde UPDATE, für
Ed25519) und `std.crypto.sha512` der Firn-Bibliothek (Runde B5, für TLS)
heißen beide `sha512` und haben verschiedene Schnittstellen. Ein
Programm, das beides einbindet, übersetzt nicht — gemessen, nicht
vermutet, und Abschnitt 1 der Abnahme prüft es jedes Mal nach:

```
error: module 'sha512' has no element 'sha384'
   --> vendor/firn/lib/std/crypto/rsa.fi:94:9
```

## Wie die Rechteprüfung wirklich funktioniert

`/etc/jarvis/rechte.conf` ist eine lesbare Textdatei, die dem Menschen
gehört. Sie enthält alles: die Adresse des Servers, den Namen, den sein
Zertifikat tragen muss, den Wurzelspeicher, und die Rechte.

**Die Voreinstellung ist nein.** Was nicht drinsteht, ist nicht erlaubt.
Eine leere Liste heißt „nichts", nicht „alles". Fehlt die Datei ganz,
startet der Dienst nicht.

**Sie wird vor jedem einzelnen Auftrag neu gelesen**, nicht beim
Verbinden. Wer ein Recht entzieht, hat es mit dem nächsten Auftrag
entzogen, ohne irgendetwas neu zu starten.

Die Prüfung je Auftragsart:

* `system` — braucht `systeminfo = ja`.
* `lies` — der Pfad muss *sauber* sein (absolut, kein `..`, kein `//`,
  keine Steuerzeichen) **und** unter `lesen` stehen. Ein Eintrag mit `/`
  am Ende ist ein Verzeichnisvorspann, alles andere muss wörtlich
  stimmen. `..` wird **abgelehnt und nicht aufgelöst** — eine Auflösung
  wäre eine zweite Fassung dessen, was der Kern tut, und die beiden
  liefen auseinander.
* `schreib` — dasselbe gegen `schreiben`, dazu `max_datei`.
* `liste` — dasselbe gegen `auflisten`.
* `befehl` — braucht `befehle = ja`, und das erste Wort muss **wörtlich**
  einem `befehl_erlaubt`-Eintrag gleichen. Keine Muster. **Keine Shell**:
  Osums `/bin/sh` kennt kein `-c`, und eine Zeichenkette durch eine Shell
  ist die klassische Stelle, an der aus einem erlaubten Befehl ein
  beliebiger wird.
* `foto` — braucht `bildschirmfoto = ja` **und** einen einmaligen,
  befristeten Schein (siehe unten).

Jede Ablehnung geht mit einem Grund im Klartext zurück **und** in
`/var/log/jarvisd.log`. Eine stille Ablehnung ist von einem Fehler nicht
zu unterscheiden.

### Das zweite Schloss: der Kern sagt nein, nicht das Programm

Runde HANDLE hat jedem Deskriptor ein Rechtebitfeld gegeben und mit
`HND_DUP` (2208) einen Weg, einen Deskriptor mit **weniger** Rechten
herzustellen — die Maske kann nur wegnehmen. Der Helfer benutzt das:

```
lies     open(...)  →  HND_DUP(fd, R_READ  | R_INSPECT | R_SEEK)  →  close(fd)
schreib  open(...)  →  HND_DUP(fd, R_WRITE | R_INSPECT | R_SEEK)  →  close(fd)
```

Ab da arbeitet er nur noch auf dem beschnittenen Deskriptor. Ein Fehler
im Pfadprüfer gibt damit trotzdem kein Schreibrecht: `write` prüft in
`kernel/sys.fi` (`file.fd_check(..., handle.R_WRITE)`) ein Bit, das
dieser Deskriptor nicht mehr hat.

`jarvisd -p` führt das vor und ist Abschnitt 11 der Abnahme: eine Datei
wird mit `O_RDWR` geöffnet, auf Leserechte beschnitten, dann wird
geschrieben. Gemessen: Rechte vorher **6187**, nachher **2081**
(`R_READ|R_INSPECT|R_SEEK`), Schreibversuch **abgewiesen**, Lesen geht
weiter.

## Die Anmeldung

```
Helfer → Server                Server → Helfer
osum-bruecke 1 0               frage <32 Oktette Zufall, hex> 0
ich <öffentlicher Schlüssel> 0 kopplung-noetig <code> 0
beweis <Ed25519-Signatur> 0    willkommen 0
kopplung <code> 0              weg <grund> 0
kopplung-abgelehnt 0           auftrag <id> <art> <a1hex> <a2hex> <länge>
fertig <id> <ok|nein> <länge>  tschuess 0
puls 0
```

Jede Nachricht ist **eine Zeile, deren letztes Feld die Länge der
Nutzlast ist**; danach kommen genau so viele Oktette. Felder trennt ein
Leerzeichen; alles, was Leerzeichen enthalten kann (Pfade, Befehle,
Gründe), steht als Hexfolge. Damit gibt es keine Zeile, die sich durch
ihren Inhalt zerlegen lässt. Jeder Auftrag trägt eine Kennung, jede
Antwort dieselbe.

**Die Erstanmeldung braucht einen Menschen.** Der Server schickt
`kopplung-noetig <code>`; der Helfer legt den Code nach
`/var/jarvis/kopplung` und schreibt ihn auf die Konsole. Erst wenn jemand
**an diesem Gerät** `jarvisctl koppeln <code>` mit demselben Code
eingegeben hat, geht es weiter. Der Code steht im Cockpit und auf dem
Bildschirm; wer beide sieht, ist der Mensch. Ohne Bestätigung sendet der
Helfer `kopplung-abgelehnt`, protokolliert und legt auf.

`jarvisctl koppeln` weigert sich seinerseits, einen Code zu bestätigen,
den niemand angefragt hat.

## Das Bildschirmfoto — und was hier fehlt

Runde FEEDBACK hat den richtigen Weg gebaut: `kernel/shot.fi`,
`SYS_OSUM_SHOT` (1840), mit Schein, Taskleisten-Recht und Super+P, im
**Kern**. **Dieser Zweig hat ihn nicht** — `feedback` ist in `mergeline2`
noch nicht gemergt (gemessen: `SYS_OSUM_SHOT` kommt in `kernel/sys.fi`
nicht vor).

Der Helfer ruft deshalb **zuerst** 1840. Sobald FEEDBACK hereinkommt,
läuft das Bildschirmfoto über den Kern-Schein und über nichts sonst;
**es wird hier kein zweiter Kernweg gebaut.** Solange 1840 fehlt, geht es
über `/dev/fb` (Runde K7) und nur mit zwei Schlössern in Ring 3:

1. `bildschirmfoto = ja` in der Rechteliste, und
2. ein **einmaliger, befristeter** Schein, den nur ein Mensch am Gerät
   ausstellt (`jarvisctl fotoschein [sek]`). Der Helfer verbraucht ihn.

**Ehrlich dazu:** Schloss 2 ist Ring 3. Ein Programm, das als Wurzel
läuft, kann `/dev/fb` selbst öffnen — `open_devfb` in `kernel/sys.fi`
prüft in diesem Zweig **keine** Kennung. Das ist die Lücke, die FEEDBACK
im Kern schließt und die diese Runde nicht schließen kann, ohne einen
zweiten Weg neben FEEDBACK zu bauen. Sie steht hier, statt versteckt zu
werden.

Das Bild kommt als PNG heraus (Farbart 2, 8 Bit je Anteil), gepackt mit
`std.deflate`.

**Und hier ist die zweite ehrliche Stelle: in diesem Zweig bekommt Ring 3
die Bildschirmmaße gar nicht.** Gemessen mit `jarvisd -s` auf einem Kern
mit `gfx` und `-vga std`, auf dem `fb: 800x600x32 pitch=3200` auf der
seriellen Leitung steht:

```
schirm: shot -38   w -19   h -19   pitch -19   bpp -19   devfb 3
```

`/dev/fb` lässt sich öffnen (Deskriptor 3), aber `WIG_SCREEN` (1805) und
`SYS_OSUM_DISPGET` (1810) antworten mit `-ENODEV`, weil beide hinter
`wm.ready`/`vmode.ready` liegen — ohne laufenden Fensterserver gibt es
keine Zahlen. `SYS_OSUM_SHOT` antwortet mit `-ENOSYS`, weil FEEDBACK
fehlt. Ein Bild aus Oktetten ohne Breite und Zeilenlänge ist keins.

Der Helfer sagt in dem Fall genau das, statt zu raten. **Es wurde in
dieser Runde also kein Bildschirmfoto vom echten Bildschirm gemessen.**

Der Kodierer selbst ist trotzdem gemessen und nicht nur übersetzt:
`jarvisd -b` rechnet ein 64×48-Muster aus, schickt es durch denselben
Weg (`png_bauen` → `zlib_compress` → IHDR/IDAT/IEND mit CRC) und gibt es
als Hexfolge aus. Der Prüfstand prüft die Signatur, jede Stück-CRC, den
IHDR-Kopf, entpackt mit Pythons `zlib` und rechnet **jeden einzelnen
Bildpunkt** gegen die Formel im Quelltext nach. Gemessen: 64×48,
**8236 Oktette**, 0 Abweichungen.

## Was der Mensch sieht

```
jarvisctl zustand              Rechteliste, Schlüssel und seine Rechte,
                               Protokollgröße, offener Fotoschein,
                               wartende Kopplung
jarvisctl rechte               die Rechteliste, wie sie dasteht
jarvisctl protokoll [n]        die letzten n Zeilen aus /var/log/jarvisd.log
jarvisctl koppeln <code>       die Erstanmeldung bestätigen
jarvisctl fotoschein [sek]     genau ein Bildschirmfoto freigeben
jarvisctl fotoschein weg       zurücknehmen
```

Eine Oberfläche gibt es nicht. Der Auftrag nennt sie als Zugabe; sie
fällt weg, weil der Helfer auch auf einem Bau ohne Bildschirm laufen muss
und das Werkzeug, das ihn sichtbar macht, dann mitkommen soll.

## Was für den echten JARVIS-Server noch fehlt

Gemessen wurde gegen `tools/bridge/peer.py`, einen TLS-1.3-Server
in Python, **nicht** gegen den echten JARVIS-Server. Alles Grüne ist eine
Aussage über Osums Seite und über das Protokoll dieser Runde. Offen:

1. **Protokollabgleich.** Der echte Helfer auf Windows spricht das
   Protokoll des JARVIS-Servers, nicht dieses. Entweder bekommt der
   Server einen Endpunkt für diese Zeilen, oder dieser Helfer lernt das
   vorhandene. Das ist eine Entscheidung auf der Serverseite und keine
   Arbeit in Osum.
2. **Kopplung im Cockpit.** Der Code muss dort erzeugt, angezeigt und
   gegen den öffentlichen Schlüssel des Geräts gebucht werden. In Osum
   ist die Geräteseite fertig.
3. **Namensauflösung.** Es gibt in diesem System keinen Resolver. Die
   Rechteliste trägt darum eine IPv4-Adresse und daneben den Namen, den
   das Zertifikat tragen muss. Für einen Server hinter einem Namen
   braucht es DNS oder einen festen Eintrag.
4. **Mehrere Aufträge gleichzeitig.** Der Helfer arbeitet einen Auftrag
   nach dem anderen ab. Runde POLL hat den Ereignisring, mit dem das
   nebenläufig ginge; diese Runde nutzt ihn nicht.
5. **Der Bildschirmfoto-Weg im Kern** (siehe oben), sobald `feedback`
   gemergt ist.
6. **Diese Kryptografie ist nicht geprüft worden.** Derselbe Satz wie in
   `docs/REALHW.md` gilt hier.

## Die Abnahme

`bash tools/bridge/run.sh` (auch Abschnitt 32 von `./test.sh`).
Überspringt sich laut, wenn QEMU, Netzräume oder
`python3-cryptography` fehlen.

**Gemessen: 112 Zusagen, 0 gefallen** (QEMU mit `-accel kvm`, e1000).

### Die Zahlen

| | |
|---|---|
| Quelltext dieser Runde | 3008 Zeilen in drei Dateien |
| `/bin/jarvisd` auf der Platte | 815 544 Oktette (TLS 1.3, X.509, RSA, ECDSA, DEFLATE, das Protokoll) |
| `/bin/jsig` | 111 064 Oktette (Ed25519, SHA-512, Montgomery-Arithmetik) |
| `/bin/jarvisctl` | rund 68 000 Oktette |
| eine Sitzung mit sieben Aufträgen, QEMU-Start bis Ende | 4860 ms |
| Wartelast ohne Gegenstelle | **14 Systemaufrufe in 31 750 ms** — 0 je Sekunde |
| Rechtebitfeld vor / nach `HND_DUP` | 6187 → 2081 |
| PNG (64×48, gerechnetes Muster) | 8236 Oktette, 0 Abweichungen |
| TLS-Verfahren | 4865 / 4867 (AES-128-GCM bzw. ChaCha20-Poly1305) |

Die drei falschen Zertifikate werden mit den richtigen Gründen abgelehnt:
`expired` → 2, `wrong` → 4 (falscher Name), `rogue` → 5 (unbekannter
Aussteller). Ein leerer Wurzelspeicher lehnt auch das gute ab.

### Regression

Es wurde **keine bestehende Datei geändert** — nur neue kamen dazu, plus
ein Abschnitt in `test.sh`. Nachgemessen auf diesem Zweig:

| Abschnitt | Ergebnis |
|---|---|
| `tools/core/run.sh` | 46 / 0 |
| `tools/caps/run.sh` | 67 / 0 |
| `tools/handle/run.sh` | 80 / 0 |
| `tools/posix/run.sh` | 134 / 0 |
| `tools/userland/run.sh` | 91 / 0 |
| `tools/freestanding/run.sh` | 41 / 0 |
| Bau Stufe 0 (GUI) | grün |
| Bau Stufe 0 `--gui off` | grün |
| Bau Stufe 1 (firnc1) | grün |

Ein erster Lauf meldete `core` 10/46 und `caps` 33/1. **Beides war kein
Fehler im Code, sondern eine volle Platte** (`No space left on device` in
`tools/core/run.sh` Zeile 152, `/` stand auf 99 %). Nach dem Aufräumen
sind beide grün. Es steht hier, damit es niemand ein zweites Mal sucht.

See `docs/BRIDGE-OFFLINE.md` for the 05.10.2026 round: why the Dell left the bridge, the why-offline record on the server, keepalive/supervisor/watchdog in the helper, Wake-on-LAN.

---

# Part II — Server link (formerly docs/BRUECKE.md)

## Names: current vs legacy

The server (`tools/bridge-server/bridge_server.py`, systemd unit `bruecke`, data in `/srv/bruecke`) speaks two dialects, chosen by the URL prefix. `/bridge/*` answers with the current English names, `/bruecke/*` answers with the old German names so images in the field keep working. Requests are accepted in both spellings on both prefixes. All aliases live in `tools/bridge-server/legacy.py`.

| Current | Legacy |
|---|---|
| `/bridge/login` `wait` `result` `devices` `job` `fetch` `pair` `wire` `why` `health` | `/bruecke/anmelden` `warten` `ergebnis` `geraete` `auftrag` `holen` `koppeln` `draht` `warum` `gesund` |
| `X-Bridge-Admin` `-Wire` `-Device` `-Token` `-Id` `-Status` `-Type` | `X-Bruecke-Verwalter` `X-Draht` `-Geraet` `-Marke` `-Id` `-Status` `-Typ` |
| wire: `osum-bridge` `hello` `challenge` `proof` `welcome` `pairing-needed` `pair` `pair-rejected` `drop` `poll` `alive` `job` `done` `bye` | `osum-bruecke` `ich` `frage` `beweis` `willkommen` `kopplung-noetig` `kopplung` `kopplung-abgelehnt` `weg` `puls` `lebt` `auftrag` `fertig` `tschuess` |
| job kinds `read` `write` `list` `run` `screenshot` `input` (`key` `mouse` `click` `scan`), result status `failed` | `lies` `schreib` `liste` `befehl` `foto` `eingabe` (`taste` `maus` `knopf` `scan`), `nein` |
| files `admin.key` `pairing_book.json` `devices/` | `verwalter.key` `koppelbuch.json` `geraete/` (kept as copies/symlink) |

Since 25.10.2026 `jarvisd` sends only the current names; a legacy `path = /bruecke/draht` in `permissions.conf` is rewritten to `/bridge/wire`. Tests: `python3 tools/bridge-server/test_why.py` (current) and `test_legacy.py` (old names), 39 checks each. Pairing by digit code: `docs/BRIDGE-PAIRING.md`.

The text below is the original German round report and still uses the legacy names.

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
| `kernel/tip.fi` | die eingespeiste Eingabe, Aufruf 1843 |
| `kernel/tip-off.fi` | dieselbe Schnittstelle, die „es gibt sie nicht" sagt |
| `kernel/user/settings.fi` | der elfte Reiter: Zustand sehen, Brücke abschalten |
| `tools/bridge2/echt.sh` | 18 Zusagen gegen store.fleitec.com |
| `tools/bridge2/kette.sh` | Osum in QEMU → Anschluss → Dienst → Bild |
| `tools/bridge2/abriss.sh` | Wiederverbindung, mit Zeitabständen |
| `tools/bridge2/reiter.sh` | der Reiter, fotografiert — **noch nicht fertig** |

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

### Der Weg von außen — `tools/bridge2/echt.sh`, 18/0

Gegen `https://store.fleitec.com`, durch das echte Zertifikat:
Verwalterschutz, Kopplungscode, falscher Code abgelehnt,
Zufallsforderung, falsche Unterschrift abgelehnt, richtige angenommen,
fremder Schlüssel abgelehnt, Auftrag → Bild → abgeholt (Oktett für
Oktett dasselbe), langes Polling 25 079 ms, Sperre wirkt.

### Die ganze Kette — `tools/bridge2/kette.sh`, 9/0

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

### Die Wiederverbindung — `tools/bridge2/abriss.sh`, 7/0

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

## Notes 04.10.2026 (Dell remote access)

* **Permission lists hold 64 entries** (`jarvisd`, was 32). The 33rd `command_allowed`
  line -- `/bin/act` -- had been dropped silently; a dropped entry is now logged
  (`jarvisd: permission list full -- an entry was DROPPED`).
* **Without fork** (task table full, `fork failed`): `/bin/ps`, `/bin/kill <pid>` (up to three
  pids) and `/bin/reboot` still work, handled inside `jarvisd` itself. Compiled, not triggered in
  a test (a full table cannot be produced through the bridge, `sh` waits for background jobs).
* **Screenshot and typing need no person at the device**: `jarvisctl screenshot` /
  `jarvisctl eingabe` are in `command_allowed`; run it, then the `foto` / `eingabe` job
  within 60 s. Measured in the VM: PNG came back.
* **a11y tree**: personal image only, `/etc/orientbus/policy` carries
  `allow jarvis a11y.* write`. Dry run first is still enforced (`act call a11y.tree --dry`, then
  `act call a11y.tree`). Measured in the VM: `decision=allow`, tree returned.
* **`/var/jarvis` takes about seven files** (the eighth `schreib` is refused without an error);
  `dell-update.py` therefore writes ONE script `u.sh` and removes older `*.sh`.
* **Result files**: the bridge server keeps 300 per device and prunes by NAME (`HHMMSS-id`), not
  by time -- fresh answers can be deleted at once (seen on the VM device). Open: r352.

---

## Fernsteuerung für Justins Dell (Runde D1, 10.10.2026)

**Befund (belegt).**
* `jarvisd` liest NUR die englischen Schlüssel (`commands`, `input`, `transport`, `path` …,
  `kernel/app/jarvisd.fi`, Umbenennung E-001, 02e3ffd1). `assets/jarvis/rechte-justin.conf` und
  `rechte.conf` trugen noch die deutschen (`befehle`, `eingabe`, `weg` …): ein damit gebautes Abbild
  hätte `transport = https` NICHT gelesen und der Dienst wäre mit „no `server =`“ beendet.
  Beide Dateien sind jetzt englisch (Werte `yes`/`no`).
* Welche Datei im Abbild liegt: `tools/usbimg/build.sh` kopiert `$JARVIS_CONF` nach
  `/etc/jarvis/permissions.conf`, sonst die eingebaute Vorgabe (alles `no`, jetzt auch `input = no`
  ausdrücklich). Justins Stick: `IMAGE_PROFILE=personal JARVIS_CONF=assets/jarvis/rechte-justin.conf`.
  `IMAGE_PROFILE=public` lehnt `JARVIS_CONF` ab und bricht zusätzlich ab, falls `input = yes` drinsteht.
* **Was das für den schon installierten Dell heißt.** Die Datei entsteht nur beim Abbild-Bau/Installieren.
  OTA (`/bin/ota`, Pakete) tauscht Programme und Kern, nicht `/etc/jarvis/permissions.conf` (OTA.md kennt
  nur `/etc/ota.conf` als Konfiguration, nichts schreibt die Rechteliste). Der Dell behält also seine
  alte Datei (englische oder deutsche Schlüssel — NICHT verifiziert, Dell offline). Wege für `input = yes`:
  (1) neues Abbild flashen; (2) am Gerät die Zeile `input = yes` in `/etc/jarvis/permissions.conf`
  eintragen (der Helfer liest sie vor jedem Auftrag neu, kein Neustart); (3) per Bridge-Auftrag `schreib`
  geht NICHT (`write` erlaubt nur `/var/jarvis/`, `/tmp/`, `/home/` — mit Absicht nicht `/etc`).
  Ein Fern-Update der Rechteliste per OTA gibt es bewusst nicht: wer sich selbst Rechte schenken kann, hat sie.

**Sichtbare Anzeige.** Der Kern merkt sich, wann zuletzt ein Tippschein ausgestellt oder eine Taste/der
Zeiger eingespeist wurde (`tip.recent`, 6 s, `TQ_RECENT`). Die Leiste (`kernel/user/taskbar.fi`, Feld
`F_REM`) zeigt dann ein ROTES Feld „JARVIS“ und postet einmal je Sitzung die Meldung „JARVIS steuert gerade
diesen Rechner“. Gefragt wird der Kern, nicht der Helfer.

**Not-Aus.** (a) `Win+Esc` — im Kern (`kbd.fi`), geht auch bei hängender Oberfläche; (b) `jarvisctl input
off`; beides setzt die Sperre (`TI_LOCK`): offener Schein wird entzogen, kein neuer ausgestellt, nichts
eingespeist — egal was `input =` sagt; `jarvisd` meldet dann „emergency stop engaged“. Aufheben: nur root,
`jarvisctl input on`. Die Sperre liegt im RAM (nach Neustart gilt wieder die Rechteliste); dauerhaft aus:
Einstellungen → Brücke → Aus (schreibt `input = no`). `jarvisctl input` zeigt Sperre und Anzeige.
Nebenbei behoben: `jarvisctl input revoke` hieß durch die Umbenennung „transport“.

**Abnahme.** `tools/bridge2/eingabe.sh` (Config-Schlüssel, Public-Wächter, Bau, Not-Aus in der VM mit
Gegenprobe). Die volle Kette Auftrag → Gerät → Ergebnis: `tools/bridge2/kette.sh`.
