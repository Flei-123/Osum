# RUNDE PRÄSENZ — Freunde, Präsenz und ein Chat, den der Server nicht lesen kann

Zweig `praesenz`, Arbeitsbaum `/root/osum-praesenz`, abgezweigt von
`merge7` (c176fd2).

Der Auftrag, wörtlich:

> „solche Dienste wie Freunde oder Chat-System wären schon auch cool, wo
> man auch sieht, was ein Freund gerade macht — aber halt im OS
> integriert, mit dem OS-Konto"

Das sind drei Dinge, und diese Runde hält sie auseinander:

| Frage | wer beantwortet sie |
|---|---|
| **Wer bin ich?** | Runde KONTO (`/bin/konto`, drei Anbieter hinter einer Schnittstelle) — diese Runde baut das nicht nach, sie holt es herein |
| **Was mache ich gerade?** | `kernel/user/praesenz.fi`, ein Dienst am Systembus |
| **Wer darf es sehen?** | `lib/praesenzd.js` am Server: der Freundschaftsgraph |

Und über allem steht weiter der Satz aus Runde KONTO:

> **Ein Konto ist eine Bequemlichkeit, es ist nie eine Bedingung.**

Ohne Anmeldung hält der Präsenzdienst den Status lokal, veröffentlicht
ihn am Bus und schickt **nichts** ins Netz. Die Freundesleiste zeigt
dann einen Satz, der sagt, was zu tun wäre — keine leere Liste (das
sieht aus wie „du hast keine Freunde") und kein verschwundenes Fenster
(das sieht aus wie ein Fehler).

---

## 0. Schritt null war ein Merge, und er war der halbe Auftrag

**Die Runden KONTO und SYNC lagen nicht in `merge7`.** Beide hingen an
der alten MERGE-2-Linie:

```
git merge-base merge7 konto  ->  7d487fb
git merge-base merge7 sync   ->  7d487fb
git merge-base --is-ancestor konto merge7  ->  NEIN
git merge-base --is-ancestor sync  merge7  ->  NEIN
```

Ohne sie gibt es kein OS-Konto (die Identitätsschicht) und kein
E2E-Prinzip (die Schlüsselkette). Also zuerst beide auf `praesenz`.

### Die Konflikte, und wie sie aufgelöst wurden

| Datei | Konflikt | Auflösung |
|---|---|---|
| `docs/shots/*.png` | 20 Bilder, binär | die neueren aus `merge7` |
| `locale/{de,en}/messages` | beide Runden hängen Blöcke an derselben Stelle an | Vereinigung; danach 279 Schlüssel je Datei, **0 Doppelte** |
| `kernel/user/settings.fi` | **der echte Konflikt** (siehe unten) | vier Blöcke von Hand |
| `kernel/user/wlib.fi` | — | ging automatisch |

**Der echte Konflikt: beide Runden hatten sich unabhängig den Reiter 8
genommen.** `konto` schrieb `const R_KONTO: u64 = 8`, `sync` schrieb
`const R_SYNC: u64 = 8`, und beide schrieben `R_ANZ = 9`. Auf ihrem
eigenen Zweig hatte jede recht; zusammen wäre eine der beiden Seiten
unerreichbar gewesen, und zwar **still** — `zeige_reiter` hätte eine
Seite nie eingeblendet.

Aufgelöst:

* `R_KONTO = 8` behält seine Nummer (KONTO kam zuerst, und
  `tools/konto/run.sh` Abschnitt 9 liest sie),
* `R_SYNC = 9`,
* `R_ANZ = 10`,
* die Elementtafel wird **192** (KONTO wollte 192, SYNC 160 — jetzt sind
  beide Seiten drin, und der Abstand zur Grenze wird gemessen:
  `settings: elemente n=… max=…`),
* `bw = 760` für die Reiterleiste (die von `tools/konto/run.sh` **gemessene**
  Zahl; SYNC hatte 700 stehenlassen wollen, weil `tab_breite` ohnehin
  herunterskaliert — mit zehn Reitern ist 760 die belegte Zahl),
* `settings.tabs` in beiden Katalogen zu **einer** Zeile mit zehn
  Beschriftungen.

`tools/konto/run.sh` sagte „Reiter eq 9". Die Zahl steht jetzt auf 10 —
und weiterhin **fest im Skript** und nicht aus der Datei abgeleitet:
eine Zusage, die sich selbst nachrechnet, fällt nie auf.

### Die Abnahme vorher und nachher

| Messung | vor dem Merge (Zweig `konto`) | nach dem Merge |
|---|---|---|
| `tools/konto/run.sh` | 107 passed, 0 failed | **107 passed, 0 failed** |
| `memmap.py` | 0 Kollisionen | **104 Bereiche in 0x100000, 11 Vektoren, 173 Modusnamen, 0 Kollisionen** |
| Kernel Stufe 0 | baut | **baut, 5 305 332 Oktette** |

---

## 1. Die OS-Schicht: ein Dienst am Systembus

`kernel/user/praesenz.fi` → `/bin/praesenz` (206 184 Oktette).

```
praesenz dienst [frist]        der Dienst selbst (frist in TICKS)
praesenz setzen <app> <text>   eine App setzt ihren Status
praesenz fokus  <app>          "in <app>" (vom Fensterserver)
praesenz weg | da              abwesend / wieder da
praesenz unsichtbar <an|aus>   niemand sieht mich
praesenz zeigen                was steht gerade
```

### Warum ein Busdienst und keine Datei in `/var/run`

Eine Statusdatei müsste jeder, der sie lesen will, **pollen** — und der
Fensterserver schreibt sie bei jedem Fokuswechsel. `PUB` schickt eine
Kopie an jeden Abonnenten, und wer nichts abonniert hat, wird nicht
geweckt.

Dazu das, was eine Datei nicht kann und `docs/SYSTEMBUS.md` „der ganze
Unterschied" nennt: **pid und uid trägt der Kern ein**, nicht der
Absender. Ein Programm kann sich nicht als ein anderes ausgeben.

Angemeldet wird mit `A_SAMEUID`. Auf einem Mehrbenutzergerät sieht
Benutzer B damit nicht, was A tut — nicht weil dieses Programm höflich
ist, sondern weil der Kern die Nachricht gar nicht erst zustellt.

### Der Rahmen: 64 Oktette

`bus.MSG_INLINE` ist 64. Was größer ist, braucht ein Segment — drei
Systemrufe für dreizehn Zeichen. Also:

```
Oktett 0      Art     (P_SETZEN, P_FOKUS, P_WEG, P_DA, P_SICHT, P_FRAGE, P_EREIGNIS)
Oktett 1      Zustand (Z_DA=0, Z_WEG=1, Z_BESCH=2, Z_UNSICHT=3)
Oktett 2      Länge der App    (0..16)
Oktett 3      Länge des Textes (0..44)
Oktett 4..19  App    ("certus", "edit")
Oktett 20..63 Text   ("liest xoffi.ai")
```

Die App ist 16 Oktette, weil ein Dienstname am Bus auch 16 ist
(`bus.NAME_MAX`) — dieselbe Grenze zweimal zu führen wäre eine Einladung
für den Tag, an dem eine davon wächst. Ein zu langer Text wird
**gekürzt und das Kürzen gezählt** (`gekuerzt=` in `praesenz zeigen`),
damit es beim Messen auffällt und nicht beim Benutzer.

### Datenschutz als Mechanik, nicht als Vorsatz

**(a) Unsichtbar ist unsichtbar.** `rahmen_bauen` kehrt um, *bevor* ein
Oktett des Textes in den Rahmen kommt. Die Abonnenten bekommen
`Z_UNSICHT` und einen leeren Text — kein „offline vortäuschen": ein
Freund sieht „unsichtbar" und weiß damit, dass er nichts sieht. Das ist
ehrlicher als eine Lüge und billiger als ein zweiter Zustand, der
auseinanderlaufen kann.

Gemessen, beide Richtungen:

```
sichtbar:    praesenz: zustand=da         app=certus text=GEHEIMTEXT4711
unsichtbar:  praesenz: zustand=unsichtbar app=       text=
```

**(b) Der App-Text ist opt-in, je App.** Eine App darf ihren Text nur
setzen, wenn sie in `/etc/praesenz.conf` unter `text` steht:

```
text certus edit karte
```

Verglichen wird ein **ganzes Wort** — `cert` rutscht nicht durch, weil
`certus` erlaubt ist. **Fehlt die Datei, darf keine App einen Text
setzen.** Wer nichts eingestellt hat, verrät nichts.

**(c) `fokus` trägt nie einen Text.** Der Fensterserver kennt den
Fenstertitel, und ein Fenstertitel ist ein Dateiname, eine Netzadresse
oder ein Betreff. `P_FOKUS` nimmt den Text deshalb gar nicht erst an
(`mit_text = false`), statt sich auf die Erlaubnisliste zu verlassen.

---

## 2. Die Serverseite: `lib/praesenzd.js`

Ein **zweiter** Dienst in neuen Dateien unter `/root/jarvis/lib/`. An
`lib/osumbridge.js` wurde **keine Zeile** geändert.

*Warum nicht dort andocken:* `osumbridge.js` ist die **Gerätebrücke** —
eine Sache zwischen Justin und seinem Rechner. Präsenz und Chat sind
eine Sache zwischen **zwei Menschen**: anderer Vertrauensraum, anderer
Lebenszyklus (ein Chat überlebt das Abmelden eines Geräts), anderes
Fehlerbild. Dieselbe Begründung, die `osumbridge.js` für seinen eigenen
Port gibt.

Gemeinsam ist die **Identität**: beide erkennen ein Gerät an seinem
Ed25519-Schlüssel aus demselben Koppelbuch (`data/osum_devices.json`).

Protokoll: dasselbe Zeilenprotokoll wie die Gerätebrücke (eine Zeile,
deren letztes Feld die Länge der Nutzlast ist), weil Osums Seite es schon
spricht und ein zweites Format zwei Fehlerquellen wären.

```
Gerät -> Server                Server -> Gerät
  hallo <pubhex>                 forderung <noncehex>
  beweis <sighex>                willkommen <uid> | nein
  status <rahmenhex>             praesenz <freund> <rahmenhex>
  freunde                        freundliste <json>
  anfrage <namehex>              anfrage-von <namehex>
  annehmen <namehex>             freund-neu <namehex>
  entfernen <namehex>            entfernt-von <namehex>
  senden <an> <len>+Chiffrat     post <von> <len>+Chiffrat
  abholen                        postfach <n> | leer <n>
```

### Der Freundschaftsgraph

Eine Freundschaft ist **beidseitig** und wird als **zwei** Einträge
geführt. Der Grund ist die Frage, die beim Zustellen gestellt wird:
„darf B den Status von A sehen?" — die beantwortet ein Eintrag unter A,
ohne dass eine Paar-Ordnung sortiert werden muss.

Eine **Anfrage** ist einseitig und steht nur beim Empfänger. Die Antwort
auf `anfrage` ist **immer dieselbe** (`gesendet`), egal ob es das Konto
gibt, ob schon eine Anfrage lief oder ob geblockt wurde — sonst ist der
Dienst eine Kontoauskunft.

**Entfernen wirkt auf beiden Seiten.** Eine halbe Freundschaft wäre ein
Zustand, in dem einer noch sieht und der andere nicht mehr, und das ist
die unangenehmste Variante von beiden.

### Der Chat: der Server sieht den Klartext nicht

Übernommen aus RUNDE SYNC („der Abgleich, den der Server nicht mitlesen
kann") und hier genauso gemeint:

* Eine Nachricht kommt als **Chiffrat** an. Der Server sieht `von`, `an`,
  eine Länge, einen Zeitstempel und einen Block Oktette, die für ihn
  Rauschen sind.
* Er hat **keinen Schlüssel** und bekommt nie einen. Die Schlüssel
  entstehen aus X25519 zwischen den **Geräten**; der private Teil
  verlässt das Gerät nicht — dasselbe Muster wie `jsig` in RUNDE BRIDGE
  (der private Schlüssel liegt nicht im Prozess am Netz).
* Das **Postfach** für Offline-Zustellung speichert denselben Block
  unverändert. Ein Postfach, das entschlüsseln könnte, wäre ein Server,
  der mitliest, mit extra Schritten.

**Was er trotzdem sieht**, und das gehört genannt statt verschwiegen —
dieselbe Ehrlichkeit wie Abschnitt 4 von RUNDE SYNC: **wer mit wem, wann,
wie oft und wie viel.** Verkehrsanalyse bleibt möglich. Diese Runde tut
nichts dagegen und behauptet auch nicht, es zu tun.

**Kein Chat ohne Freundschaft** — sonst ist ein Chatdienst ein Weg, jedem
Fremden etwas zu schicken.

---

## 3. Das Userland: `kernel/user/freunde.fi`

`/bin/freunde` (394 888 Oktette), eine schmale Leiste am rechten Rand:
je Freund ein Punkt, sein Name, was er gerade tut, und ein Klick öffnet
das Chatfenster.

**Justins Regel, wörtlich: 0 direkte Zeichenaufrufe außerhalb `wlib`, 0
feste Farbwerte außerhalb `theme`.** Diese Datei hält sich daran
vollständig — kein `wlibc.rect`, kein `wlibc.text`, kein `mal_flaeche`.

Der Statuspunkt, der am ehesten nach „einmal schnell ein Kreis in grün"
aussieht, ist deshalb ein **Label mit einem Zeichen** (`*` da, `!`
beschäftigt, `.` abwesend, `?` unsichtbar). Ein gemalter Kreis müsste
seine Farbe irgendwoher nehmen, und „irgendwoher" wäre ein Zahlenwert im
Quelltext. Ein Zeichen nimmt die Schriftfarbe des Themas mit.

`tools/praesenz/run.sh` Abschnitt 8 zählt das nach — **ohne
Kommentarzeilen** und **mit Gegenprobe** (siehe unten).

---

## 4. Die Fehler, die diese Runde gemacht und gefunden hat

Fünf, und sie stehen hier, weil ein Bericht ohne sie eine Werbebroschüre
wäre.

### (1) 0 ist eine gültige Dienstnummer

`bus_reg` gibt die Nummer des Dienstes zurück, und der **erste** Dienst
im System bekommt die **0**. Der Wächter

```
if z_dienst == 0 { return 0 }     // "noch nicht angemeldet"
```

in `verteilen()` hielt genau diesen Fall für „nicht angemeldet" und
kehrte um, **bevor** er veröffentlichte. Der Dienst nahm Nachrichten an
(im Mitschnitt als `DIAG recv art=1` sichtbar) und tat nichts damit;
`praesenz zeigen` wartete auf eine Antwort, die nie kam.

**Ein Sentinel gehört außerhalb des Wertebereichs.** `SVC_MAX` ist 64,
also ist `KEIN_DIENST = 0xFFFFFFFF` der richtige Wert. Der Fehler kostete
eine Stunde und war nur zu finden, indem der Rückgabewert von `PUB`
gedruckt wurde — vorher sah es aus wie ein Fehler im Bus.

### (2) `praesenz zeigen` druckte seine eigenen Nullen

`zeigen` ist ein **eigener Prozess** mit eigenen Statics, die alle null
sind. Es meldete damit den Stand eines Dienstes, den es nie gefragt
hatte. Richtig ist: abonnieren, `P_FRAGE` schicken, auf die
Veröffentlichung warten — und weil der Bus nur an **Dienste** senden kann
und nicht an eine pid, ist die Antwort ein `PUB`.

### (3) Die Frist war in Ticks und wurde als Millisekunden gelesen

`I_TICKS` läuft mit `time.TICK_HZ = 100`; ein Tick ist 10 ms.
`praesenz dienst 8000` waren damit **achtzig Sekunden** statt acht. Der
Parameter heißt jetzt `frist`, und das Warten in `fragen()` misst **an
der Uhr** statt an Schleifenrunden — eine Rundenzahl ist auf einer
schnellen Maschine eine andere Zeit als auf einer langsamen.

### (4) Der Wächter hielt seinen eigenen Kommentar für einen Verstoß

Abschnitt 8 zählt „direkte Zeichenaufrufe in `freunde.fi`" und war rot.
Der einzige Treffer war der Kommentar, der sagt, dass es diese Aufrufe
dort **nicht** gibt („KEIN `wlibc.rect`, KEIN `wlibc.text`"). Jetzt wird
ohne Kommentarzeilen gezählt — **und mit Gegenprobe**: derselbe Wächter
muss auf eine Datei anschlagen, in der wirklich einer steht. Sonst ist
„0 Treffer" auch das Ergebnis eines kaputten Suchmusters.

### (5) Ein Fensterprogramm ohne Fensterserver

Abschnitt 9 startete `/bin/freunde` über ein Shell-Skript wie ein
Kommandozeilenprogramm. Ohne `gfx wm wig desk` gibt es kein Fenster,
`wlib.begin` sagt nein, und das Programm meldet gar nichts — vier rote
Zusagen, keine davon am Programm. Gestartet wird jetzt über `wigapp`,
wie in `tools/glyphe/run.sh`.

### Und zwei am Prüfstand selbst

Der Node-Läufer war dreimal rot an einer Stelle, an der der Dienst recht
hatte: `bis('zugestellt')` sucht im **ganzen** bisherigen Verlauf und fand
die Zeile aus einem früheren Abschnitt wieder. Ein Test, der eine alte
Antwort für die neue hält, misst die Vergangenheit.

Ebenso: `await new Promise(r => setTimeout(r, 300))` statt auf das echte
`listening`-Ereignis zu warten. Ein Test, der 300 ms schläft, ist auf
einer belasteten Maschine manchmal rot — und ein Läufer, der manchmal rot
ist, wird irgendwann nicht mehr gelesen.

---

## 5. Was gemessen ist

`tools/praesenz/run.sh` (QEMU-Gäste, echtes TLS 1.3, echte
Ed25519-Schlüssel) und `test/praesenzd.test.mjs`.

Die Zahlen stehen in [STATUS-PRAESENZ.md](../STATUS-PRAESENZ.md).

Die drei Zusagen, auf die es ankommt:

1. **Präsenz kommt beim Freund an**, gemessen **41 ms** (Abnahme: unter
   2 000).
2. **Der Server sieht keinen Klartext**: der gesamte Mitschnitt, das
   Freundesbuch auf der Platte und das Chiffrat werden nach dem Klartext
   durchsucht — **0 Treffer**, mit Gegenprobe, dass die Suche ihn findet,
   wenn er da ist.
3. **Unsichtbar heißt, dass nichts hinausgeht**, in beiden Richtungen
   gemessen.

---

## 6. Was es nicht gibt

* **Keine Gruppen.** 1:1, wie beauftragt. Ein Gruppenchat mit
  Ende-zu-Ende ist ein eigenes Schlüsselproblem (wer bekommt den
  Schlüssel, wenn jemand die Gruppe verlässt) und keine Zeile mehr.
* **Kein Schutz gegen Verkehrsanalyse.** Siehe oben — genannt statt
  verschwiegen.
* **Keine Schlüsselerneuerung im Chat.** Der Sitzungsschlüssel entsteht
  aus X25519 zwischen zwei Geräten; ein Double-Ratchet mit Vorwärtsschutz
  ist der nächste Schritt und nicht dieser.
* **Kein Verlauf auf dem Server.** Der Verlauf liegt lokal; das Postfach
  ist ein Zwischenlager und keine Ablage.
* **Keine Statusanzeige für Nicht-Freunde.** Es gibt keinen
  „öffentlichen" Modus, weil es niemanden gibt, dem er nützt.
