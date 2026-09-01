# Runde OTA — das Update, das sich das Gerät selbst über das Internet holt

Zweig `ota`, abgezweigt von `mergeline2`. **Nicht nach `main` gemerged.**
Gemessen mit `bash tools/ota/run.sh` (QEMU mit `-accel kvm`).

Was diese Runde angreift, steht in `docs/UPDATE.md` unter „WAS NOCH FEHLT"
als Punkt 1 und in `docs/ROADMAP-UPDATE.md` als TEIL A:

> „**Die HTTPS-Strecke ist in dieser Runde nicht Ende-zu-Ende gelaufen.**
> […] Die Quelle in dieser Runde ist ein Verzeichnis auf der Platte. Es
> fehlt die Verdrahtung, nicht die Kryptographie: `fetch` ist ein
> `kernel/app/`-Programm und liegt in keinem der Abbilder, die
> `tools/install/build.sh` baut."

Das ist eingelöst. Was **nicht** eingelöst ist, steht am Ende, und es ist
wieder der längste Abschnitt — mit einem Punkt darin, der ein Sperrpunkt
für echtes Blech ist und der vorher niemandem aufgefallen war.

---

## GEGEN WAS GEMESSEN WURDE — ausdrücklich

**Es gibt keinen echten Update-Server im Internet, gegen den diese Runde
messen könnte.** Gemessen wurde gegen `tools/ota/server.py`, eine
Gegenstelle auf demselben Wirt. Was daran echt ist:

* **echtes TLS 1.3**, ausgehandelt von Pythons `ssl` (OpenSSL) — also von
  einer Umsetzung, die dieses Repository nicht geschrieben hat;
* **ein echtes Zertifikat mit einer echten Kette**, gebaut mit Pythons
  `cryptography`, geprüft vom Gerät gegen `/etc/ssl/roots.pem`;
* **echtes HTTP**: `Content-Length`, `Range`/`206 Partial Content`, und
  echte Verbindungsabbrüche (`SO_LINGER` 0 → RST);
* **eine echte Netzkarte**: e1000 (Runde HWNET), über QEMUs Benutzernetz,
  in dem 10.0.2.2 der Wirt ist.

Was daran nicht echt ist: die Leitung ist kurz, es gibt keinen
Zwischenspeicher, keinen Lastverteiler, keine Mehrfachnamen und keinen
DNS. Siehe „Was für den Betrieb noch fehlt".

---

## Was gebaut wurde

| Datei | Zeilen | Was |
|---|---:|---|
| `kernel/user/ota.fi` | 1220 | `/bin/ota`: suchen, holen, prüfen, einspielen, Wachhund, Dienst, Einstellungen |
| `kernel/app/fetch.fi` | +90 | `Range`/Wiederaufnahme (`-b`), Anhängen (`-a`), und `-o` schreibt endlich den **Rumpf** statt der ganzen Antwort |
| `tools/install/build.sh` | +60 | `/bin/fetch` und `/bin/ota` liegen jetzt **im Abbild**, dazu `/etc/ssl/roots.pem` und `/etc/ota.conf` |
| `tools/install/oneshot.sh` | +35 | ein Netz für den Prüfstand (`OTA_NETZ`), und `-cpu` ist einstellbar |
| `tools/ota/server.py` | 300 | die Gegenstelle: HTTPS, Range, Abbruch auf Ansage |
| `tools/ota/verzeichnis.py` | 190 | das signierte VERZEICHNIS, mit Gegenprüfung durch libsodium |
| `tools/ota/mkcerts.py` | 130 | die Zertifikate, gemacht mit fremdem Werkzeug |
| `tools/ota/pakete.sh` | 120 | sechs Quellen fürs Netz, vier davon kaputt |
| `tools/ota/run.sh` | 560 | der Läufer, sechs Abschnitte |

---

## 1. Das VERZEICHNIS — und warum es neben dem INDEX steht

    OTA1
    fassung <TAB> <dezimal>
    paket <TAB> name <TAB> fassung <TAB> sha256 <TAB> oktette <TAB> datei

`VERZEICHNIS.sig` sind 64 rohe Oktette: die Ed25519-Signatur über **alle**
Oktette von `VERZEICHNIS`.

`INDEX`/`INDEX.sig` gibt es seit Runde UPDATE, und es bleibt. Der INDEX
nennt je Paket den **Store-Streuwert** — den über Metadaten und Daten
*innerhalb* des Pakets. Das ist das richtige Glied für „ist das
Ausgepackte das gemeinte", und `opk` rechnet es.

Es ist **nicht** das Glied für die Frage, die ein Update aus dem Netz
zuerst stellen muss: „sind die Oktette, die über die Leitung kamen,
vollständig und unverändert — **bevor** ich sie anfasse?" Dafür braucht es
den Streuwert über die **Datei** und ihre **Länge**. Beides steht im
VERZEICHNIS, beides ist von derselben Signatur gedeckt, und beides wird
geprüft, bevor `opk` überhaupt aufgerufen wird.

Damit gibt es **zwei unabhängige Prüfungen mit zwei verschiedenen
Programmen**: `ota` prüft die Datei gegen das VERZEICHNIS, `opk` prüft den
Paketinhalt gegen den INDEX und die Paketsignatur gegen denselben
Schlüssel. Der Läufer misst beide Linien einzeln (Fälle (g) und (a)).

## 2. Der Rückschrittsschutz

`/system/FASSUNG`, **genau neun Oktette**: acht Ziffern und ein
Zeilenende. Feste Breite aus demselben Grund wie bei `/system/AKTUELL`
(Runde INSTALL) und `/system/ERPROBUNG` (Runde UPDATE): eine Datei, deren
Länge sich nicht ändert, geht in **genau einen** Datenblock, und ein
Sektor erreicht die Platte ganz oder gar nicht.

Die Regel ist eine Zeile: **`fassung` im VERZEICHNIS muss größer sein als
`/system/FASSUNG`.** Gleich ist auch nicht neuer.

Das ist der Angriff, den man am leichtesten vergisst. Ohne diese Zahl ist
**jede alte, richtig signierte Antwort eine gültige Antwort**: wer sie
aufgehoben hat, setzt ein Gerät auf eine Fassung mit bekannter Lücke
zurück, und jede Signaturprüfung der Welt sagt dazu ja. Die Gegenprobe im
Läufer ist wichtiger als der Fall selbst: **dieselbe Quelle, dieselbe
Signatur, ein Gerät bei Fassung 0 — und sie geht durch.** Ein Schutz, der
immer zuschlägt, ist kein Schutz, sondern ein kaputter Update-Weg.

## 3. Die Reihenfolge, und sie ist der ganze Punkt

1. VERZEICHNIS holen (HTTPS, Kette geprüft).
2. **Ed25519-Signatur prüfen.** Fällt sie durch, ist danach keine Zeile
   daraus geglaubt worden — auch nicht die Fassungsnummer.
3. **Rückschrittsschutz.**
4. Jedes Paket **vollständig** holen, dann Länge und SHA-256 gegen das
   VERZEICHNIS halten. Erst wenn **alle** stimmen, geht es weiter.
5. **Platz prüfen** (`SYS_SYSINFO`, `I_BFREE` × `I_BSIZE`), mit Faktor
   drei: die Datei unter `/tmp/ota`, der ausgepackte Store-Eintrag, und
   Luft für Generation, Journal und Verzeichniseinträge.
6. `opk aktualisieren` — prüft INDEX.sig und die Paketsignatur ein
   **zweites** Mal mit eigenem Code, legt den Store-Eintrag an, schreibt
   die neue Generation, schaltet `/system/AKTUELL` um.
7. **Zuletzt** `/system/FASSUNG` hochsetzen.

**Warum Schritt 7 zuletzt kommt.** Zwischen 6 und 7 kann der Strom
ausfallen. Dann steht die neue Generation und `/system/FASSUNG` nennt noch
die alte Zahl — dasselbe Update wird noch einmal angeboten und noch einmal
eingespielt. Das ist Arbeit zweimal und sonst nichts. Andersherum stünde
eine Fassung eingetragen, die das Gerät nicht hat, und es lehnte genau das
Update ab, das es braucht. Von zwei Fehlern nimmt man den, der sich von
selbst repariert.

## 4. Die Wiederaufnahme

Reißt die Leitung, bleibt ein Bruchstück unter `/tmp/ota/`. Der nächste
Versuch sieht dessen Länge an und lässt `/bin/fetch -b <länge>` nur den
Rest holen (`Range: bytes=n-`, Antwort `206`). Geprüft wird danach der
Streuwert des **ganzen** Ergebnisses. Ein Bruchstück, das länger ist als
angekündigt, wird weggeworfen — das ist der Fall, in dem eine Gegenstelle
`Range` nicht kann und den ganzen Rumpf noch einmal schickt.

**`-o` schrieb bis zu dieser Runde die ganze Antwort**, Kopfzeilen
eingeschlossen. Für Runde HWNET fiel das nicht auf (dort wurde `-o` nicht
benutzt, gemessen wurde der Streuwert des Rumpfes auf der Ausgabe); für
ein Update ist es der Unterschied zwischen einem Paket und einer Datei,
die mit `HTTP/1.0 200 OK` anfängt.

**Acht Argumente, nicht mehr.** `kernel/proc.fi` gibt einem `exec` genau
`MAX_ARGS = 8` mit. `fetch -q -o <datei> -n <name> -b <von> <url>` sind
neun. Deshalb ist „still" in `fetch` seit dieser Runde die **Vorgabe** und
`-v` schaltet den Rumpf auf die Ausgabe; `-q` bleibt als Wort erhalten,
damit kein Aufrufer von vorher bricht.

## 5. Der automatische Rückfall — und wo seine Grenze liegt

`kernel/ab.fi` (Runde UPDATE) zählt bei jedem Start hoch und schaltet beim
dritten Versuch ohne Erfolgsvermerk von selbst auf die vorige Generation
zurück. Das fängt jede Generation, die **nicht hochkommt** — vorausgesetzt,
die Maschine startet überhaupt noch einmal.

Genau da war die Lücke, und `ota wachhund` ist sie: eine Generation, die
**hochkommt und dann hängt**, startet nie wieder von selbst. Niemand setzt
den Erfolgsvermerk, niemand zählt, das Gerät steht. Der Wachhund wartet die
eingestellte Frist ab, sieht in `/system/ERPROBUNG` nach, und wenn dort
noch `ok=0` steht, startet er die Maschine neu — dann zählt der Kern, und
nach drei solchen Runden ist die alte Generation wieder da.

**Er beißt nur, wenn etwas in Erprobung steht.** Auf einem System ohne
laufendes Update tut er nichts. Ein Wachhund, der auch dann beißt, wenn
nichts los ist, wird abgeschaltet — und dann ist er nicht da, wenn er
gebraucht wird. Der Läufer misst beide Hälften.

## 6. Die Bedienung

    ota suchen                    nachsehen (schreibt nichts am System)
    ota zeigen                    Fassung, Generation, Erprobung
    ota einspielen                holen, prüfen, einspielen -- OHNE Neustart
    ota bestaetigen               der Erfolgsvermerk nach einem guten Start
    ota zurueck                   von Hand auf die vorige Generation
    ota wachhund [sekunden]       die Frist abwarten, notfalls neu starten
    ota dienst                    automatische Suche im Zeitabstand
    ota einstellungen             die Einstellungsseite
    ota einstellen <schlüssel> <wert>

`/etc/ota.conf`:

    quelle=https://10.0.2.2:8443     woher (IPv4 -- es gibt keinen Resolver)
    name=ota.test                    der Name, den das Zertifikat tragen MUSS
    abstand=3600                     Sekunden zwischen zwei Suchen
    auto=ja                          automatisch suchen? ja/nein
    frist=120                        Sekunden für den Wachhund

**Es wird nie von selbst neu gestartet.** `einspielen` endet mit „BEREIT
ZUM NEUSTART" und tut nichts weiter. Der einzige Ort, der `reboot` ruft,
ist der Wachhund — und der läuft nur, wenn schon ein Update in Erprobung
steht und sich nicht meldet; dann ist ein Neustart nicht der Eingriff,
sondern die Rettung.

Der Dienst gehört in `/etc/inittab`:

    ota:respawn:/bin/ota dienst

**Die Einstellungsseite ist die des Kommandozeilenwerkzeugs und kein
Reiter in der grafischen Oberfläche**, und das ist eine Entscheidung mit
einem Grund, den man nachzählen kann: `kernel/user/settings.fi` legt seine
Bedienelemente mit `merke()` in ein Feld von **64** und ruft `merke()`
**86 Mal** auf (`grep -o 'merke(' kernel/user/settings.fi | wc -l` = 87,
davon eine die Definition; alle Aufrufe stehen zwischen Zeile 1521 und
1680 in derselben Funktion). Alles ab dem 65. Element steht in `ids`/`rtr`
nicht drin, also kann `zeige_reiter` es weder zeigen noch verstecken — es
steht auf **jedem** Reiter. Ein achter Reiter wäre ein Fehler auf einen
Fehler gesetzt. Das gehört repariert, in einer Runde, die diese Datei
aufräumt.

## 7. Der Test, der zuerst nichts gemessen hat

Fall (e) — dreißigmal der Stecker mitten im Einspielen — stand im ersten
vollen Lauf mit **30 von 30 grün** da: jede Maschine kam hoch, jede hatte
entweder die alte oder die neue Fassung, keine war ein Ziegelstein. Die
Zeile darunter war das Problem:

    alt=30  neu=0  kaputt=0  (Schuesse bei 1000..16000 ms)

**Kein einziger Schuss ist je hinter das Umschalten gekommen.** Die
Spanne 1–16 Sekunden war geschätzt („ein Einspielen dauert etwa zwanzig
Sekunden"), und die Schätzung war falsch. `tools/ota/zeitprobe.sh` fährt
denselben Vorgang einmal sauber durch und stempelt jede serielle Zeile
mit der Zeit seit dem Start von QEMU. Gemessen:

| Marke | ms |
|---|---:|
| `ota: quelle …` — das Netz steht | 9 799 |
| `ota: streuwert stimmt` — das Paket ist geladen und geprüft | 13 938 |
| `opk: installiert` — geschrieben | 22 731 |
| `ota: BEREIT ZUM NEUSTART` | 22 814 |

Die ersten zehn Sekunden gehören der Firmware und dem Hochfahren. Alle
dreißig Schüsse lagen also **vor der ersten Zeile, die `ota` überhaupt
schreibt** — dreißig grüne Haken dafür, dass eine Maschine, an der nichts
passiert, unverändert bleibt.

Seitdem wird das Fenster **gemessen statt gesetzt**: der Läufer fährt die
Zeitprobe, nimmt ihre Marken und verteilt die Schüsse in drei Dritteln —
über den ganzen Vorgang, dicht in die Schreibphase (Paket geprüft bis
`opk: installiert`) und hinter das Umschalten. Und er prüft sich selbst:
kommt **kein einziges „neu"** heraus, fällt der Abschnitt durch, weil ein
Fenster, das nur die Firmware trifft, nichts belegt. Genau diese Prüfung
war beim ersten Lauf mit dem neuen Code rot — sie tut also, wofür sie da
ist.

Zwei weitere Zahlen waren aus demselben Grund still falsch und sind
repariert: „davon wirklich übertragen" las Feld 5 statt 6 aus dem
Protokoll der Gegenstelle und zeigte immer 0, und „Blöcke frei" war leer,
weil `df` in keinem der Prüfläufe je aufgerufen wurde.

---

## WAS NOCH FEHLT — für den Betrieb gegen einen echten Server

1. **AVX-512 tötet `/bin/fetch`.** Gemessen mit demselben Abbild und
   demselben Kern, nur mit anderem `-cpu`:

   | `-cpu` | was dazukommt | Ergebnis |
   |---|---|---|
   | `qemu64` | SSE2 | läuft |
   | `Nehalem` | SSE4.2 | läuft |
   | `Westmere` | AES-NI | läuft |
   | `SandyBridge` | AVX | läuft |
   | `Haswell` | AVX2, BMI2 | läuft |
   | `max` | AVX-512, SHA-NI, … | **`user fault: vector=6` (#UD)** |

   Die Ursache liegt nicht in dieser Runde und nicht in `fetch`: **Osum
   schaltet für Ring 3 weder `CR4.OSXSAVE` noch `XCR0` frei, und der
   Kontextwechsel sichert keine Vektorregister.** Firns Bibliothek fragt
   `cpuid` und nimmt den breitesten Weg, den die Maschine anbietet.
   Solange das so ist, ist der Update-Weg auf jedem Rechner mit AVX-512
   tot — und das ist Blech auf dem Tisch, nicht QEMU. Es ist eine eigene
   Runde: `CR0.MP`/`EM`, `CR4.OSFXSR|OSXMMEXCPT|OSXSAVE`, `XCR0`, und
   `FXSAVE`/`XSAVE` im Kontextwechsel. Das Freischalten allein wäre
   **falsch**: dann benutzt Ring 3 Vektorregister, die kein Kontextwechsel
   sichert.

2. **Kein Resolver.** `quelle` trägt eine IPv4-Adresse und `name` den
   Namen fürs Zertifikat. Für `https://pkg.example.org/…` fehlt DNS.
   `vendor/firn/lib/net/dns.fi` ist im festgenagelten Vorrat,
   `/etc/resolv.conf` schreibt niemand, `dhcp.fi` kennt den Nameserver
   schon. ~50 Zeilen und eine Messung gegen `dig`
   (`docs/ROADMAP-UPDATE.md` A2).

3. **Die Server-Seite ist ein Prüfstand und kein Betrieb.**
   `tools/ota/server.py` liefert ein Verzeichnis aus. Für den Betrieb
   fehlt: ein Bau, der aus einem Stand Pakete, INDEX und VERZEICHNIS
   erzeugt und **automatisch** die Fassungsnummer hochzählt; ein Ort, an
   dem die Fassungsnummer geführt wird (sie darf nie zurückgehen, auch
   nicht durch ein zurückgenommenes Auslieferungspaket); und eine
   Auslieferung, die alte Fassungen weiter vorhält, damit ein Gerät, das
   drei Fassungen hinterherhinkt, nicht ins Leere greift.

4. **Schlüsselverwaltung.** Es gibt **einen** vertrauten Schlüssel
   (`/system/schluessel.pub`) und keinen Weg, ihn zu wechseln oder eine
   Fassung nachträglich für ungültig zu erklären. Der übliche Weg wären
   ein zweiter Schlüssel im Abbild („Ersatz") und eine Sperrliste im
   signierten VERZEICHNIS. Der geheime Schlüssel liegt unverschlüsselt auf
   der Baumaschine (`$OUT/geheim.key`); wo er auf Dauer liegen soll —
   Tresor, HSM, getrennte Signiermaschine —, hat noch niemand entschieden.

5. **Fassungsplan.** Die Zahl in `fassung` ist eine Zahl und kein Plan. Es
   fehlt die Festlegung, was sie zählt (jede Auslieferung? jede
   Sicherheitslücke?), und wie ein Gerät, das lange aus war, mehrere
   Sprünge nacheinander macht. Heute holt es die neueste und überspringt
   den Rest — das ist für Pakete richtig und für ein Format, das sich
   ändert, falsch.

6. **Der Kern ist nicht Teil des A/B-Wechsels.** Der Zähler sitzt im Kern
   (`kernel/ab.fi`), nicht im Lader. Ein Kern, der gar nicht bis zum
   Einhängen der Wurzel kommt, wird davon nicht gefangen; dafür bräuchte
   es zwei Kernabbilder auf der EFI-Partition. Steht seit Runde UPDATE so
   da und ist weiter offen.

7. **Statisch gelinkt heißt: alles neu.** Osum ist statisch gelinkt
   (Roadmap A9). Eine Lücke in der libc bedeutet, dass **jedes** Programm
   neu gebaut werden muss. **Kann die Paketmaschinerie das ausdrücken?
   Nein.** Das PLAN-Format (`docs/PLAN-FORMAT.md`, Fassung 2) nennt zu
   jeder Anwendung einen Streuwert und keine Abhängigkeiten; es gibt kein
   Feld, in dem stünde „dieses Paket enthält libc-Stand X". Was
   funktioniert: ein VERZEICHNIS, das **alle** betroffenen Pakete mit
   neuen Streuwerten nennt — dann wird alles geholt und alles ersetzt, und
   das Ergebnis ist richtig. Was fehlt: dass irgendjemand außer einem
   Menschen *weiß*, welche Pakete betroffen sind. Ohne ein Feld für
   „gebaut gegen libc-Stand X" ist das eine Buchführung auf der
   Baumaschine und keine Zusage des Formats.

8. **Die Uhr.** Die Zertifikatsprüfung benutzt die CMOS-Uhr. Eine Maschine
   mit leerer Knopfzelle hält jedes gültige Zertifikat für ungültig und
   kann sich dann nicht mehr aktualisieren. SNTP ist ein UDP-Paket von 48
   Oktett (`docs/ROADMAP-UPDATE.md` A7).

9. **Der Wurzelzertifikatsspeicher altert.** `/etc/ssl/roots.pem` liegt
   seit dieser Runde im Abbild — aber weiterhin **gebacken**. Er wird erst
   erneuerbar, wenn er ein Paket wie jedes andere ist.

10. **Diese Kryptographie ist nicht auditiert.** Sie ist gegen die Normen
    und gegen libsodium gemessen (Runde UPDATE, 4725 Prüfungen) — viel
    mehr als nichts und viel weniger als eine Prüfung.
