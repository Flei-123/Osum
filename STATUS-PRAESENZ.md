# STATUS — RUNDE PRÄSENZ

Zweig `praesenz`, abgezweigt von `merge7` (c176fd2). Die Zahlen auf einer
Seite. Was hier steht, ist gemessen; was nicht gemessen ist, steht unter
„offen".

---

## 1. Der Merge (Schritt 0)

`konto` und `sync` lagen **nicht** in `merge7`, sondern beide auf der
MERGE-2-Linie (`git merge-base merge7 konto` = `git merge-base merge7
sync` = `7d487fb`).

| | vor dem Merge | nach dem Merge |
|---|---|---|
| `tools/account/run.sh` | 107 passed, 0 failed (Zweig `konto`) | **107 passed, 0 failed** |
| `memmap.py` Kollisionen | 0 | **0** (104 Bereiche in 0x100000, 11 Vektoren, 173 Modusnamen) |
| Kernel Stufe 0 | baut | **baut**, 5 305 332 Oktette |

**Konflikte:** 20 Bilder (binär, die neueren genommen), beide
Sprachkataloge (Vereinigung, danach 279 Schlüssel je Datei, 0 Doppelte),
`settings.fi` mit vier Blöcken.

**Der echte Konflikt:** beide Runden hatten unabhängig `= 8` für ihren
Reiter genommen. Aufgelöst als `R_KONTO = 8`, `R_SYNC = 9`,
`R_ANZ = 10`, Elementtafel 192, Leistenbreite 760.
`tools/account/run.sh` zählt jetzt zehn Reiter statt neun.

---

## 2. Was gebaut wurde

| Datei | Zeilen | was |
|---|---:|---|
| `kernel/user/praesenz.fi` | 620 | der Präsenzdienst am Systembus (`/bin/praesenz`) |
| `kernel/user/freunde.fi` | 430 | die Freundesleiste und das Chatfenster (`/bin/freunde`) |
| `/root/jarvis/lib/praesenzd.js` | 480 | Freundschaftsgraph, Präsenz-Push, Chat-Weiterleitung, Postfach |
| `/root/jarvis/test/praesenzd.test.mjs` | 250 | der Prüfstand des Kontodienstes |
| `tools/presence/run.sh` | 300 | die Abnahme |
| `locale/{de,en}/messages` | +12 je | die Texte der Leiste |

Größen: `/bin/praesenz` **206 192** Oktette, `/bin/freunde` **394 888**
Oktette. Beide ohne undefinierte Namen.

An `lib/osumbridge.js` wurde **keine Zeile** geändert.

---

## 3. Die Messungen

### Der Kontodienst (`test/praesenzd.test.mjs`, echtes TLS 1.3)

```
PRAESENZD: 33 passed, 0 failed
```

Fünfmal hintereinander gefahren: **5 × 33/0**, keine Schwankung.

| Zusage | gemessen |
|---|---|
| Anmeldung mit echtem Ed25519-Beweis | zwei Geräte, beide angemeldet |
| **falsche** Unterschrift | abgelehnt (`nein`), Verbindung zu |
| Freundschaft steht auf beiden Seiten | ja, beide Richtungen geprüft |
| **Präsenz beim Freund** | **40–41 ms** (Abnahme: unter 2 000) |
| App und Statustext kommen an | `certus` / `liest xoffi.ai` |
| unsichtbar | Zustand 3, App-Länge 0, Text-Länge 0 |
| beide Geräte rechnen denselben Sitzungsschlüssel | ja (X25519 + HKDF) |
| **Klartext im gesamten Servermaterial** | **0 Treffer** |
| Gegenprobe: die Suche findet ihn, wenn er da ist | ja |
| Offline: niemand online → direkt zugestellt | 0 |
| die Nachricht liegt im Postfach | 1, danach abgeholt und lesbar |
| ein Fremder darf schreiben | **nein** |
| Entfernen wirkt auf beiden Seiten | ja |

### Der Dienst im Gast (QEMU)

| Zusage | gemessen |
|---|---|
| der Dienst meldet sich am Bus an | `praesenz: dienst nummer=0` |
| abgelehnte Rufe | 0 |
| Panik | 0 |
| **sichtbar** | `zustand=da app=certus text=GEHEIMTEXT4711` |
| **unsichtbar** | `zustand=unsichtbar app= text=` |
| ohne `/etc/praesenz.conf` setzt eine App einen Text | **nein** |
| eine App außerhalb der Liste | bekommt keinen Text |

### Justins Regel (`freunde.fi`, ohne Kommentarzeilen gezählt)

| Zusage | gemessen |
|---|---|
| direkte Zeichenaufrufe außerhalb `wlib` | **0** |
| direkte `mal_*`-Aufrufe | **0** |
| feste Farbwerte (`0xRRGGBB`) | **0** |
| Gegenprobe: der Wächter erkennt einen echten Verstoß | ja |
| Texte aus dem Sprachkatalog | 7 × `msg.get` |
| Sprachschlüssel, die in einem Katalog fehlen | **0** |
| deutsche Texte mit echten Umlauten | 2 |

### Der Speicher

```
104 Bereiche in 0x100000 Oktetten kdata, 11 Vektoren,
173 Modusnamen in 16 Woertern, 0 Kollisionen
```

Diese Runde nimmt sich **keinen** neuen `kdata`-Bereich: der Präsenzdienst
lebt in Ring 3 und benutzt den Bus, der seine acht Seiten seit Runde
SYSTEMBUS hat.

---

## 4. Die Fehler dieser Runde

Fünf im Programm, zwei im Prüfstand. Ausführlich in
[docs/PRAESENZ.md](docs/PRAESENZ.md) Abschnitt 4.

1. **0 ist eine gültige Dienstnummer.** `if z_dienst == 0` hielt den
   ersten Dienst im System für „nicht angemeldet" und veröffentlichte
   nie. Sentinel jetzt `0xFFFFFFFF` (`SVC_MAX` ist 64).
2. **`praesenz zeigen` druckte seine eigenen Nullen** statt den Dienst zu
   fragen. Jetzt: SUB, `P_FRAGE`, auf das `PUB` warten.
3. **Die Frist war in Ticks, gelesen als Millisekunden** (`TICK_HZ` =
   100). `dienst 8000` waren achtzig Sekunden.
4. **Der Wächter hielt seinen eigenen Kommentar für einen Verstoß.**
5. **Ein Fensterprogramm ohne Fensterserver** — und ohne
   `/lib/mono.ttf` + `/lib/sans.ttf` meldet der Kern „ttf: keine Schrift
   gefunden", der Fensterserver kommt nicht hoch, und **jedes**
   Fensterprogramm bleibt still.

Im Prüfstand: `bis('zugestellt')` fand eine Zeile aus einem früheren
Abschnitt wieder (ein Test, der eine alte Antwort für die neue hält), und
ein `setTimeout(300)` statt des echten `listening`-Ereignisses.

---

## 5. Offen

* **Der Netzteil im OS fehlt.** `/bin/praesenz` spricht mit dem Bus,
  `praesenzd.js` spricht TLS — die Verbindung dazwischen (ein
  `praesenzd`-Gegenstück in Firn, nach dem Muster von `jarvisd.fi`) ist
  **nicht gebaut**. Der Chat ist damit auf der Serverseite vollständig
  gemessen und auf der Gerätseite noch nicht angeschlossen. Das ist der
  nächste Schritt und die größte offene Position.
* **Kein Double-Ratchet.** Der Sitzungsschlüssel entsteht aus X25519
  zwischen zwei Geräten; Vorwärtsschutz gibt es nicht.
* **Keine Gruppen.** 1:1, wie beauftragt.
* **Verkehrsanalyse** bleibt möglich (wer mit wem, wann, wie oft, wie
  viel) — genannt statt verschwiegen.
* **Das Kontrollzentrum** hat den Schalter „unsichtbar" noch nicht; die
  Leiste hat ihn.
