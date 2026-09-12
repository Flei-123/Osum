# Runde KONTO — Anmelden mit einem JARVIS-, Xoffi- oder eigenen Konto

Zweig `konto`, Arbeitsbaum `/root/osum-konto`, abgezweigt von
`mergeline2`. Diese Runde baut die **Identitätsschicht**: anmelden,
Token halten, Sitzung erneuern, abmelden — auf der Kommandozeile und in
den Systemeinstellungen. Sie baut **keinen** Datenabgleich; die
Übergabe an Runde SYNC ist eine Seite lang und steht in
[docs/KONTO-SYNC.md](KONTO-SYNC.md).

Über allem steht der Satz, der schon in der Roadmap unter 6.1e steht und
hier wörtlich weitergilt:

> **Ein Konto ist eine Bequemlichkeit, es ist nie eine Bedingung.**

Abschnitt 14 der Messung prüft genau das, und zwar nicht als Meinung:
ein Gerät wird eingerichtet und benutzt, ohne sich je anzumelden, und es
entsteht dabei keine einzige Kontodatei und kein Siegelschlüssel.

---

## 1. Die ehrliche Antwort zuerst

**Kann man sich jetzt mit einem Xoffi-Konto an OrientOS anmelden — ja
oder nein?**

**Technisch ja, nachgewiesen gegen einen Nachbau — gegen das echte
Xoffi noch nicht bewiesen.** Der Rücken spricht genau die vom Betreiber
beschriebene API (`/api/auth/login`, `/refresh`, `/logout`,
Bearer-Token, `mfa_required` + `temp_token`, Organisation im Körper),
und der ganze Weg ist gegen eine Attrappe gemessen, die diese Antworten
liefert: Anmeldung, zweiter Faktor, zwei Organisationen mit derselben
Adresse, Erneuerung, Ablehnung, Abmeldung. Gegen das Produktivsystem
liefen **nur harmlose `GET /api/health`-Abrufe**, wie abgesprochen —
keine Anmeldeversuche, keine Last, keine Registrierung.

Zwei Dinge fehlen für ein glattes „ja" gegen das echte System:

1. **Der zweite MFA-Schritt ist eine Annahme.** Die Beschreibung des
   Betreibers nennt den ersten Schritt (`{ mfa_required, temp_token }`,
   10 Minuten) und nennt den zweiten nicht. Der Rücken nimmt
   `POST /api/auth/mfa/verify` mit `{ temp_token, code }` an. Das steht
   an **einer** Stelle (`p_mfa` in `kernel/app/anb_xoffi.fi`); wer den
   echten Weg kennt, ändert eine Zeile.
2. **Ob der Server ein Feld `organisation` im Anmeldekörper liest,**
   weiß das Gerät nicht — bei Xoffi entscheidet die **Domäne**, und ein
   OrientOS-Gerät hat keine. Das Gerät kann nur prüfen, **was
   zurückkam**, und genau das tut es: kommt eine andere Organisation
   zurück als angefragt, wird die Anmeldung abgelehnt.

Mit einem **JARVIS-Konto** und mit einem **eigenen Server/Ordner**
funktioniert es vollständig; beim eigenen Ordner sogar ganz ohne Netz.

---

## 2. Was gebaut wurde

### Neu, `kernel/app/` (Programm `/bin/konto`, `--profile=app`)

| Datei | Zeilen | wofür |
|---|---:|---|
| `anbieter.fi` | 321 | die Anbieter-Schnittstelle: Ops-Tafel mit vier Funktionen, Kontobegriff, Kennung = SHA-256(Anbieter+Bereich+Subjekt) |
| `anb_jarvis.fi` | 296 | Rücken JARVIS |
| `anb_xoffi.fi` | 585 | Rücken Xoffi |
| `anb_eigen.fi` | 653 | Rücken „eigen": HTTPS **oder** ein Ordner ohne Netz |
| `knetz.fi` | 630 | HTTPS-Aufrufe über `std.net` + `tls.tls` (TLS 1.3), Fehlerarten getrennt |
| `kjson.fi` | 891 | JSON lesen und schreiben **ohne Fließkomma** (siehe 6) |
| `ksiegel.fi` | 261 | das Siegel über der Sitzungsdatei, Schlüssel unter `/device/kontoschluessel` |
| `kspeicher.fi` | 476 | `/etc/konten` (ohne Geheimnis) und `/state/session/konto/<kennung>` (gesiegelt) |
| `kmsg.fi` | 332 | Sprachkatalog zur Laufzeit, Benutzername |
| `kgegen.fi` | 85 | die absichtlich kaputten Fassungen für die Gegenproben |
| `konto.fi` | 1042 | die Befehle, `/etc/konten.conf`, Übergabe an SYNC |

Zusammen **5 572 Zeilen**; das gebundene Programm ist **779 712
Oktette** groß, gebaut mit `firnc --profile=app` und `kernel/user/user.ld`,
ohne `crt.s` und ohne libc.

### Geändert

* `kernel/user/settings.fi` — der **neunte Reiter „Konten"**: Anbieter
  wählen, Adresse, Anmeldename, Kennwort, Organisation, zweiter Faktor,
  Liste der angemeldeten Konten, Abmelden. Die Seite kennt **keinen**
  Anbieter und **kein** Token: sie ruft `/bin/konto` auf und liest
  dessen Zeilen. Das Kennwort geht durch ein **Rohr**, nie über `argv`
  (das stünde in jeder Prozessliste) und nie über eine Datei.
* `locale/de/messages`, `locale/en/messages` — **34 Schlüssel**, in
  beiden Dateien vollständig, deutsche Texte mit echten Umlauten.
* `kernel/user/settings.fi`, ein **Fehler dieser Runde, den ein fremder
  Läufer gefunden hat** — siehe Abschnitt 3b: die Elementtafel fasste
  128 Bedienelemente, mit der neunten Seite waren es mehr, und `merke`
  hat den Überlauf **still verschluckt**. Ein nicht gemerktes Element
  wird von `zeige_reiter` nie versteckt und steht damit auf **jeder**
  Seite. Jetzt: Tafel 192, und der Überlauf **sagt es**
  (`settings: elementtafel voll`) statt zu schweigen; dazu eine eigene
  Zeile `settings: elemente n=… max=…`, damit ein Läufer den Abstand
  zur Grenze messen kann, bevor sie erreicht ist.

### Werkzeuge

* `tools/konto/attrappe.py` (400 Zeilen) — der Testaufbau: die drei
  APIs als Nachbau über TLS 1.3, mit Protokoll **jeder** Kopfzeile.
* `tools/konto/trennung.py` (140) — die Trennungswache.
* `tools/konto/run.sh` (792) — die Messung, **107 Zusicherungen**.
* `tools/konto/dbg.sh` — die kurze Schleife zum Fehlersuchen.

---

## 3. Die Messung

```
bash tools/konto/run.sh
KONTO: 107 passed, 0 failed
```

Alles gegen einen **echten Testserver** (TLS 1.3, eigener Netzraum,
QEMU-Gast mit echter Netzkarte), nichts gegen eine Attrappe im Speicher.
Die wichtigsten Werte:

| Zusage | gemessen |
|---|---|
| drei Rücken angemeldet, alle drei anmeldbar | 4 Konten nach 4 Anmeldungen |
| zweiter Faktor vollständig | `zweitfaktor` → `temp_token` (16 Zeichen) → `ok`; dasselbe Zwischentoken erneut → `abgelaufen` |
| Sitzung überlebt Neustart | ja |
| Token im Abbild gesucht | **0 Treffer**; die Sitzungsdatei trägt das Siegel `OKS1`, 330 Oktette |
| Abmelden löscht wirklich | Datei weg **und** der Block überschrieben (0 Oktette ≠ 0, kein `OKS1` mehr) |
| keine ambienten Kekse | 3 Xoffi-Aufrufe, **0** mit Keks |
| falsches Kennwort | `falsch`, kein Konto, kein Token auf der Platte |
| 20 Fehlversuche | 76 s, 14× `falsch`, 6× `gebremst`, **20 von 20 beantwortet**, kein Absturz |
| Aufzählung verhindert | unbekannter Name und falsches Kennwort geben **dieselbe** Antwort |
| zwei Organisationen | wird **gefragt**; zwei Kennungen `da06d599…` / `f2ecf65b…`, zwei Subjekte, zwei Token |
| Erneuerung | fällig erkannt, durchgeführt, Ablauf 1788087109 → 1788087113 |
| Erneuerung abgelehnt | sauber abgemeldet, **Kontoeintrag bleibt**, Token weg |
| **kein Netz** | Sitzung bleibt, Liste steht, Übergabe liefert das Token, neue Anmeldung sagt klar `keinnetz`, System läuft weiter |
| faules Zertifikat | eigener Stand `tls`, **nicht** „kein Netz"; kein Konto entsteht |
| `master_session` | **abgelehnt**, kein Konto |
| `is_admin` / `nexus_core_access` | angenommen, aber **keine** lokale Berechtigung; `/etc/konten` trägt 7 Felder und keinen fremden Anspruch |
| ohne jedes Konto | schreiben, lesen, `konto status` = `ok`, **keine** Kontodatei, **kein** Siegelschlüssel |

### Die Gegenproben (sie fallen wirklich)

| `--kaputt …` | was sie kaputt macht | und der Test fällt |
|---|---|---|
| `klartext` | Token roh auf die Platte | Token im Abbild **gefunden** (1), kein `OKS1` |
| `keks` | schickt einen Keks mit | 1 Keks im Protokoll |
| `einemandant` | Mandant fällt aus der Kennung | Bereich leer, andere Kennung |
| `claimcheck` | prüft `master_session` nicht | Anmeldung geht durch |
| `rechte` | macht aus `is_admin` eine lokale Berechtigung | `/etc/konto.rechte` entsteht |
| (Trennung) | ein `if` mit Anbietername im allgemeinen Teil | `trennung.py` schlägt an |

Sechs Gegenproben, gefordert waren drei.

---

## 3a. Was die Nachbarläufe sagen (und was schon vorher rot war)

Die Auflage war: bestehende Tests, GUI-Bau und GUI-loser Serverbau
bleiben grün. Gemessen:

| Lauf | Ergebnis |
|---|---|
| `tools/konto/run.sh` | **107 erfüllt, 0 gescheitert** |
| `tools/look/run.sh` | **40 erfüllt, 0 gescheitert** |
| `tools/wm/run.sh` (aus zwei Suiten heraus) | **103 erfüllt, 0 gescheitert** |
| GUI-Bau `tools/hwnet/build.sh` (mit `/bin/settings`) | gebaut |
| GUI-loser Serverbau `tools/server/build.sh` | Kern 2 443 100 Oktette (gui=off), 59 Programme, 3 427 576 Oktette |
| Systemebene `orientos/test.sh` | **ALLE 19 SCHRITTE BESTANDEN, 355 Zusagen** — darin Schritt 19, der Umzug auf einem Stick **ohne Konto und ohne Netz** |

Zwei Läufe sind rot, und **beide waren es vorher schon**. Das ist nicht
behauptet, sondern gegengemessen — in einem eigenen Arbeitsbaum auf
`mergeline2` (`git worktree add --detach /root/konto-ref mergeline2`),
also ohne eine einzige Zeile dieser Runde:

* **`tools/i18n/run.sh`, Abschnitt 6** — 9 gefallene Zusagen, im
  Referenzbaum **dieselben neun, Zeile für Zeile** („der Knopf heißt auf
  Englisch: '', erwartet 'Apply'" usw.). Ursache: der Läufer sucht
  Zeilen der Form `settings: feld id=…`; `/bin/settings` schreibt dieses
  Format seit einer früheren Runde nicht mehr, sondern
  `settings: rect name=…`. Nachgesehen:
  `git show mergeline2:kernel/user/settings.fi | grep -c "feld id="` →
  **0**. Der Läufer misst ein Format, das es nicht mehr gibt.
* **`tools/desktop/run.sh`** — eine gefallene Zusage,
  „WM_MAXNR does not match the calls": der Läufer verlangt
  `const WM_MAXNR: u64 = 2115`, in `kernel/sys.fi` steht **2116** —
  in diesem Arbeitsbaum **und** im Referenzbaum identisch
  (`git diff mergeline2 -- kernel/sys.fi` ist leer).

Beides gehört den Runden, die diese Läufer betreuen, und nicht dieser.
Diese Runde macht es nicht schlimmer und repariert es nicht: fremde
Läufer im Vorbeigehen nachzuziehen, während parallel dreizehn Runden auf
denselben Dateien arbeiten, richtet mehr an, als es hilft. Gemeldet ist
es hier, damit niemand die neun für neu hält.

---

## 3b. Der zweite Durchgang: drei weitere Nachbarläufe, und was sie an
dieser Runde gefunden haben

Nach dem ersten Bericht sind `tools/desktop/run.sh`,
`tools/umlaut/run.sh` und `tools/themestore/run.sh` noch einmal
gelaufen — und zwar **zweimal**: einmal in diesem Arbeitsbaum und
einmal in einem Referenzbaum auf **derselben Basis** wie dieser Zweig
(`git worktree add --detach 7d487fb`, MERGE-2 17), damit „war schon
vorher rot" eine Messung ist und keine Behauptung.

| Lauf | dieser Zweig | Referenzbaum 7d487fb |
|---|---|---|
| `tools/konto/run.sh` | **107 / 0** | — (gibt es dort nicht) |
| `tools/look/run.sh` | **40 / 0** | — |
| `tools/themestore/run.sh` | **81 / 0** | 81 / 0 |
| `tools/umlaut/run.sh` | 45 grün / **2 rot** | 45 grün / **2 rot**, dieselben zwei |
| `tools/desktop/run.sh` | 95 / **3** | 94 / **4** |

**Zwei echte Fehler dieser Runde sind dabei herausgekommen. Beide sind
behoben, beide waren im Quelltext unsichtbar.**

1. **`themestore` war rot, und es lag an dieser Runde.**
   `shotcheck` misst Überlappungen im Bild und meldete auf der Seite
   *Vorlagen*: `OVER 'Vorschau -- aus den Mark' und 'Konten auf diesem
   Gerät'`. Der Satz „Konten auf diesem Gerät" gehört auf die
   Kontenseite und stand über der Vorschau einer **anderen** Seite.
   Ursache war nicht das Layout, sondern eine Grenze:
   `static mut ids: [u64; 128]`, und `merke()` legt bei vollem Feld
   **still nichts ab**. Was nicht in der Tafel steht, versteckt
   `zeige_reiter()` nicht — es steht auf allen neun Seiten. Behoben:
   Tafel auf 192, Überlauf meldet sich (`settings: elementtafel voll`),
   und `settings: elemente n=… max=…` sagt bei jedem Start, wie voll
   sie ist. Danach: **81 / 0**, und die Zusage „und sie zeigt zehn
   Kacheln" ist mit zurückgekommen.
   *Das ist genau der Fehler, den nur ein Läufer findet, der das BILD
   ansieht.*

2. **`umlaut` fand acht sichtbare Umschriften — alle aus dieser Runde.**
   `tools/i18n/quellen.py --alle` zählte `SICHTBAR=8`, davon sieben in
   `kernel/app/account.fi`, eine in `kernel/app/anb_eigen.fi`, dazu eine
   getippte Marke ohne Umlautform. Behoben, jede einzeln:
   * Protokoll- und Feldnamen umbenannt, statt Umlaute in ein
     maschinenlesbares Feld zu schreiben: `pruef` → `nachweis`
     (Nachweisdatei des Rückens `eigen`), `ruecken` →
     `anbieter_anzahl`, `ruecken_name` → `anbieter_name`,
     `lokal_geloescht` → `lokal_entfernt`. Der Läufer
     `tools/konto/run.sh` und die Einstellungsseite lesen die neuen
     Namen.
   * Zwei Meldungen umformuliert, weil sie den Umlaut gar nicht
     brauchten: „die Sitzung **ließ** sich nicht ablegen" → „konnte
     nicht abgelegt werden"; „**uebergabe** braucht --kennung" → „hier
     fehlt --kennung".
   * Der Unterbefehl `uebergabe` nimmt jetzt **beide** Schreibungen an
     (`uebergabe` und `übergabe`), und die Hilfe zeigt die mit Umlaut —
     dieselbe Regel wie `keys=` in den Bündeln.
   Danach: `SICHTBAR=0`, `quellen.py --marken` rc=0.

Was **danach noch rot ist, ist es im Referenzbaum genauso** — Zeile für
Zeile dieselben Zusagen:

* `umlaut`, Abschnitt 9 (2 rot): die beiden Kontrastzeilen der
  Einstellungen werden von `wlib.elide()` gekürzt gemalt
  („Akzentfarbe unverändert übernom…"), weil der Text breiter ist als
  die linke Spalte; `umlaut.py` sucht den ganzen Satz und findet ihn
  nicht. Gemessen im Referenzbaum ohne eine Zeile dieser Runde:
  **dieselben zwei**, `UMLAUT2: 45 Zusagen gruen, 2 rot`.
* `desktop` (95 grün / 3 rot): `WM_MAXNR does not match the calls`,
  `the settings did not report their geometry` und, aus Abschnitt 9,
  `tools/k15/run.sh: K15: 249 passed, 3 failed`. Im Referenzbaum sind
  **genau diese drei** ebenfalls rot — bis auf die Zahl hinter k15,
  die dort mit `249 passed, 3 failed` **Zeichen für Zeichen dieselbe**
  ist. Der Referenzbaum hatte zusätzlich `the bar never came back`
  (94 / 4), was hier grün war: eine Zeitmessung, die unter Last
  wackelt.

---

## 4. Die drei Rücken im Vergleich

| | `jarvis` | `xoffi` | `eigen` |
|---|---|---|---|
| Anmeldung | `POST /api/login` | `POST /api/auth/login` | `POST /konto/anmelden` **oder** ein Ordner |
| Token | ein JWT, 30 Tage | Access 7 Tage + Refresh 30 Tage | frei, vom eigenen Server; im Ordner eine Sitzungsdatei |
| Erneuern | **gibt es nicht** — meldet ehrlich „neu anmelden" | `POST /api/auth/refresh`, Vorlauf vor dem Ablauf | `POST /konto/erneuern` |
| Abmelden | `logout` löscht nur den Keks, das JWT bleibt bis `exp` gültig | `logout` + Sperrliste (Redis, **fail-open**) | eigener Server; im Ordner: Datei weg |
| Mandant | keiner | **Pflichtteil der Kennung** | optional |
| zweiter Faktor | nein | ja (`temp_token`) | ja, im Protokoll vorgesehen |
| Kopfzeile | liest **kein** `Bearer` (nur Keks oder `?token=`) | `Authorization: Bearer`, immer | `Bearer` |
| ohne Netz | nein | nein | **ja**, als Ordner |

Drei ehrliche Grenzen beim JARVIS-Rücken stehen im Kopf von
`anb_jarvis.fi`: kein `Bearer`, kein Erneuern, kein serverseitiges
Sperren. Der Rücken schickt deshalb die Kopfzeile **und** einen für
genau diesen Aufruf gebauten Keks — kein ambienter, es gibt kein
Keksglas in `knetz.fi`. `deviceToken` aus `/api/me` wird **nicht**
eingesammelt: das ist der Schlüssel zur Fernsteuerung eines Rechners,
und ein Anmeldevorgang, der ihn nebenbei mitnimmt, wäre eine
Rechteausweitung durch Bequemlichkeit.

---

## 5. Welche Daten wohin gehen

**Zu Xoffi geht** (nur beim Anmelden, Erneuern, Abmelden, Prüfen):
Anmeldename oder E-Mail, das Kennwort, der zweite Faktor, der Name der
Organisation, das Zugriffs-/Erneuerungstoken, und die Kopfzeile
`User-Agent: OrientOS-konto`. Dazu unvermeidlich die **IP-Adresse** und
der Zeitpunkt jedes Aufrufs.

**Zu Xoffi geht NICHT:** kein Dateiname, kein Dateiinhalt, keine
Gerätekennung (`machine-id`), kein Gerätename, keine
Hardwarebeschreibung, keine Liste der Programme, keine Telemetrie, keine
Absturzberichte. Diese Runde überträgt **keine Nutzdaten**, nur die
Anmeldung.

**Auf dem Gerät bleibt:** `/etc/konten` (Anbieter, Bereich, Subjekt,
Anzeigename, Datenort, lokaler Benutzer — **nie** ein Passwort),
`/etc/konten.conf` (nur Adressen), `/state/session/konto/<kennung>`
(**gesiegelt**), `/device/kontoschluessel` (der Siegelschlüssel).

**Datenort getrennt je Anbieter,** wie entschieden: Xoffi-Daten hinter
Xoffi, JARVIS-Daten hinter JARVIS, `eigen` beim Nutzer. Ein Format und
eine Verschlüsselung für alle drei — das baut SYNC. **Kein Anbieter hat
in dieser Runde ein zweites Format erzwungen**; es gibt nichts zu
melden.

---

## 6. Ein Fund, der nichts mit Konten zu tun hat: Ring 3 kann kein SSE

Der erste echte Lauf im Gast endete so:

```
user fault: pid=5 vector=6 err=0x0 rip=0x40148784 -- process killed
```

Vektor 6 ist „unbekannter Befehl", und der Befehl an der Stelle war
`cvtsi2sd` — SSE2, im Rumpf von `json__parse_number`. Firns
`std/json.fi` hält **jede** Zahl als `f64`; dieser Kern schaltet SSE
aber nirgends frei (weder `CR0.EM=0` noch `CR4.OSFXSR` in
`kernel/arch/x86_64/boot.s` oder `start.s`), und einen Platz für
`fxsave` beim Prozesswechsel gibt es auch nicht. **Bis heute hat kein
Programm in Ring 3 `std.json` benutzt** — deshalb ist es nie
aufgefallen.

SSE freizuschalten und den Fließkommazustand zu sichern ist eine
richtige, eigene Runde und gehört nicht in eine über Anmeldung; halb
erledigt (Bits gesetzt, Zustand nicht gesichert) wäre sie ein Fehler,
den erst der zweite Prozess sieht. Also steht in `kernel/app/kjson.fi`
jetzt ein eigener Leser: Objekte, Felder, Zeichenketten,
Wahrheitswerte, **ganze** Zahlen, entpackte Escapes samt `\uXXXX` und
Ersatzpaaren — ohne ein einziges `f64`. Was das kostet, steht dort
ebenfalls: eine echte Bruchzahl in einer Antwort würde abgeschnitten,
statt still falsch gerechnet zu werden.

**Für die Roadmap:** *Ring 3 kann keine Fließkommazahlen.* Das trifft
jedes künftige Programm, das eine fremde JSON-API liest.

### Und ein zweiter: acht Wörter

`proc.MAX_ARGS` ist **8** (`kernel/proc.fi`), und die Shell sagt bei
mehr `sh: too many arguments` — leise, der Befehl fällt weg.
`konto anmelden --anbieter x --ziel y --name z --kennung k --bereich b
--zwischen t --code c` sind vierzehn. `kernel/user/backup.fi` ist aus
demselben Grund bei `-pfoo` gelandet. Konsequenz hier, dreifach:

1. `/bin/konto` nimmt **beide** Schreibweisen, `--ziel <url>` und
   `--ziel=<url>`; die angehängte ist **ein** Wort.
2. Der Befehl ist das erste Wort, **das ein Befehl ist** — nicht das
   zweite Wort. Vorher endete `konto --kaputt=klartext anmelden` still
   in der Hilfe, und die Gegenprobe maß nichts.
3. Adressen gehören in `/etc/konten.conf`, eine Zeile je Anbieter. Die
   Einstellungsseite **merkt sich** dort, was der Nutzer einträgt, und
   ruft `/bin/konto` danach ohne `--ziel`/`--name` auf.

Abschnitt 11c misst das: `MAX_ARGS` = 8, beide Schreibweisen führen zur
gleichen Kennung, und die lange Form fällt nachweislich durch.

---

## 7. Datenschutz und Recht — die ehrliche Liste (keine Rechtsberatung)

Xoffi gehört einer anderen Firma. Solange **Justin selbst** sein eigenes
Konto benutzt, ist das seine Sache. Sobald **fremde Nutzer** OrientOS
mit einem Xoffi-Konto verwenden, steht das an:

1. **Rollen klären.** Wer ist Verantwortlicher für die Anmeldedaten —
   der Xoffi-Betreiber, das OrientOS-Projekt, oder beide gemeinsam? Bei
   einem Anmeldedienst ist der Betreiber in der Regel eigener
   Verantwortlicher; dann ist es **keine** Auftragsverarbeitung, sondern
   eine Übermittlung, und es braucht eine Rechtsgrundlage (Vertrag mit
   dem Nutzer reicht meist).
2. **Auftragsverarbeitungsvertrag (Art. 28 DSGVO)**, falls Xoffi im
   Auftrag des OrientOS-Projekts Daten verarbeitet — dann schriftlich,
   mit Zweck, Dauer, Unterauftragnehmern und Löschfristen.
3. **Verzeichnis der Verarbeitungstätigkeiten** (Art. 30) für die
   Anmeldung.
4. **Informationspflicht (Art. 13)** an der Stelle, an der der Nutzer
   den Anbieter wählt: wer bekommt was, wozu, wie lange. Die Liste aus
   Abschnitt 5 ist dafür der Rohtext.
5. **Speicherfristen** für die serverseitigen Zugriffsprotokolle
   (IP-Adresse!) benennen.
6. **Ort der Verarbeitung** — liegen Server oder Backups außerhalb der
   EU, braucht es die entsprechenden Garantien.
7. **Auskunft und Löschung**: Wie bekommt ein Nutzer sein Xoffi-Konto
   und die daran hängenden Daten gelöscht? Das Gerät kann nur seine
   lokale Sitzung löschen — das tut es —, das Konto selbst nicht.
8. **Minderjährige**, falls OrientOS in Schulen läuft: Einwilligung der
   Erziehungsberechtigten.

Fachlich, unabhängig vom Recht: Die Wahlfreiheit bleibt das beste
Argument. Wer kein Konto will, braucht keines; wer eines will, aber
keiner Firma trauen mag, nimmt `eigen`.

---

## 8. Hinweise an den Betreiber (sachlich, zum Weitergeben)

Alle Angaben aus **einzelnen, harmlosen Abrufen** am 30.08.2026, keine
Anmeldeversuche, keine Last.

1. **`environment: "development"` in Produktion.**
   `GET https://react.xoffi.com/api/health` antwortet mit
   `"frontend": { "environment": "development" }` und
   `"backend": { "framework": "FastAPI", "version": "2.0.0",
   "environment": { "node_env": "development" } }`.
2. **Die Anmeldeseite ist ein Entwicklungsbau.** `GET /login` (58 650
   Oktette HTML) lädt **30 JavaScript-Bündel mit zusammen 13 490 584
   Oktetten**. Darunter:
   * `node_modules_@remixicon_react_index_mjs_…` — **3 980 010** Oktette
     (die komplette Icon-Bibliothek, unaufgeteilt),
   * `next_dist_compiled_next-devtools_index_…` — **1 503 653** Oktette,
   * `[turbopack]_browser_dev_hmr-client_hmr-client_ts_…` — der
     **Hot-Module-Reload-Client**, der in einem Produktionsbau gar nicht
     vorkommt.
   Justins eigener Befund (20 Bündel, 9 849 387 Oktette) ist damit
   bestätigt und inzwischen eher noch größer.
   **Ein `next build` statt `next dev` würde beides beheben** und die
   Anmeldeseite vermutlich um eine Größenordnung verkleinern.
3. **Der zweite MFA-Schritt ist nicht dokumentiert.** Der erste liefert
   `{ mfa_required, temp_token }`; welcher Endpunkt den Code prüft,
   steht in der Beschreibung nicht. Bitte den echten Weg nennen.
4. **Liest `/api/auth/login` ein Feld `organisation` im Körper?** Für
   Geräte ohne Domäne ist das der einzige Weg, den Mandanten zu wählen.
   Falls nein: wie soll ein Client die Organisation angeben?
5. **Die Sperrliste fällt bei Redis-Ausfall offen** (fail-open). Das ist
   eine bewusste Entscheidung, aber sie heißt: ein Abmelden wirkt dann
   serverseitig nicht. Ein `iat`-Grenzwert je Nutzer in der Datenbank
   wäre eine Rückfallebene, die auch ohne Redis trägt.
6. **Access-Token 7 Tage.** Für Geräte ist das lang. Kürzer + Refresh
   wäre sicherer; dieses Gerät legt es nur gesiegelt ab und erneuert
   früh, aber ein gestohlenes Token bleibt sonst eine Woche gültig.
7. **`is_admin` und `nexus_core_access` stehen nur im Token, nicht im
   `user`-Objekt.** Für Clients ist das eine Stolperstelle: wer das
   `user`-Objekt für vollständig hält, übersieht Rechte. OrientOS
   ignoriert beide bewusst.
8. Positiv, der Vollständigkeit halber: HSTS, `X-Frame-Options`,
   `X-Content-Type-Options`, `Referrer-Policy` und `X-Robots-Tag` sind
   gesetzt, und `/` leitet auf `/signin` um.

**Kein Sicherheitsproblem ausgenutzt.** Es wurde nichts geraten, nichts
registriert, nichts gespeichert.

---

## 9. Was diese Runde ausdrücklich NICHT tut

* Kein Datenabgleich, keine Verschlüsselung von Nutzdaten (Runde SYNC).
* Keine Anmeldung während der Ersteinrichtung, kein Dialog, der ein
  Konto verlangt, keine Funktion hinter einer Anmeldung.
* Keine Übernahme fremder Rollen in lokale Rechte.
* Kein SSE im Kern (siehe 6) — das ist eine eigene Runde.

## 10. Offene Punkte

1. Der zweite MFA-Schritt bei Xoffi ist eine Annahme (eine Zeile).
2. Passkeys und OAuth (u. a. ID Austria) bietet Xoffi an; dieser Rücken
   kann sie nicht.
3. Der JARVIS-Server kann Token nicht erneuern und nicht sperren — das
   ist eine Grenze des Servers, keine des Rückens.
4. Ring 3 ohne Fließkomma (siehe 6).
5. Der Ordner-Rücken schützt nur mit PBKDF2 (8192 Runden, wie
   `kernel/user/pw.fi`): wer den Ordner hat, kann offline raten. Steht
   so im Kopf von `anb_eigen.fi`.
