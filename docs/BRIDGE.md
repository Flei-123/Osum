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
| `tools/bridge/gegenstelle.py` | — | die Gegenstelle für den Prüfstand (TLS 1.3, Python) |
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
`std.deflate`; `tools/bridge/run.sh` rechnet CRC und Bilddaten mit
Pythons `zlib` nach.

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

Gemessen wurde gegen `tools/bridge/gegenstelle.py`, einen TLS-1.3-Server
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

`bash tools/bridge/run.sh` (auch Abschnitt 30 von `./test.sh`).
Überspringt sich laut, wenn QEMU, Netzräume oder
`python3-cryptography` fehlen.
