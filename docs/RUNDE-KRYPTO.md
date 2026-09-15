# Runde KRYPTO (K-019) — Plattenverschlüsselung

Zweig `krypto`, Grundlage `main` = `fd33f0f`. Worktree `/root/osum-w-krypto`.

Ziel: blockweise Verschlüsselung eines Datenträgers, entsperrbar beim Start
mit einer Passphrase, nach dem LUKS2-Prinzip, aber mit eigenem Code.

**Abnahme: `bash tools/krypto/run.sh` → 61 bestanden, 0 gescheitert.**

---

## 1. Die Vorabmessung: was lag schon im Baum?

Die erste Frage des Auftrags war, was an Krypto schon da ist. Gemessen,
bevor eine Zeile geschrieben wurde:

| Was | Wo | Zustand | Verwendet? |
|---|---|---|---|
| AES-128/192/256, FIPS 197 | `lib/crypto/aes.fi` | gegen FIPS 197, RFC 4493, RFC 3394, OpenSSL gemessen | **ja**, unverändert als Chiffre unter XTS |
| SHA-256 + HMAC | `lib/crypto/sha256.fi` | gegen `hashlib`/`hmac` gemessen | **ja**, Kopfprüfsumme und Schlüsselplatz-MAC |
| PBKDF2-HMAC-SHA256 | `lib/crypto/scrypt.fi` | allgemeine Form, gemessen | vorgesehen als Rückfall, **nicht gebraucht** |
| scrypt, RFC 7914 | `lib/crypto/scrypt.fi` | gegen `hashlib.scrypt` gemessen | nein (siehe 2.) |
| ChaCha20-CSPRNG, RDSEED/RDRAND | `kernel/rand.fi` | mit `fixedrand`-Gegenprobe | **ja**, Hauptschlüssel und Salze |
| BLAKE2s | `lib/crypto/blake2s.fi` | aus Runde TUNNEL (WireGuard) | nein — Argon2 braucht BLAKE2**b** |
| ChaCha20, X25519, Ed25519, SHA-1/512, HKDF | `lib/crypto/` | — | nein |

**Nicht vorhanden und deshalb neu geschrieben** — jeweils mit Begründung:

* **BLAKE2b** (`lib/crypto/blake2b.fi`). Der Baum hatte nur BLAKE2s, und das
  ist nicht dieselbe Funktion mit anderer Ausgabelänge: 64-Bit-Worte statt 32,
  128er Block statt 64, 12 Runden statt 10, andere Rotationen, zwölf
  sigma-Zeilen statt zehn. Argon2 schreibt BLAKE2b vor.
* **Argon2id** (`lib/crypto/argon2.fi`). Siehe Abschnitt 2.
* **XTS** (`lib/crypto/xts.fi`). Im ganzen Baum kein `xts`, kein `essiv`, kein
  `gf_mul`. Die Suche nach `\bxts\b` traf nur `kernel/user/jpeg.fi`
  (unbeteiligt).

Die Naht für die Einbindung war ebenfalls schon da und musste nicht erfunden
werden: `kernel/blk.fi` hat mit `read`/`write` **eine** Stelle für die
Wurzelplatte, und `blk.use_at` (Runde INSTALL) kann der Wurzel einen Versatz
auf dem Gerät geben. Genau das braucht ein Kopfsatz.

---

## 2. Die Verfahrenswahl

### Datenverschlüsselung: XTS-AES-256

Eine Platte hat keinen Platz für einen Prüfwert je Sektor — 512 Oktette
Klartext müssen in 512 Oktetten Geheimtext liegen. Damit fällt jedes
authentifizierende Verfahren aus. Unter den verbleibenden ist XTS seit 2007 die
Norm für genau diesen Zweck (IEEE 1619, NIST SP 800-38E) und das, was LUKS2,
BitLocker und FileVault benutzen. CBC-ESSIV, die im Auftrag genannte
Rückfallebene, ist nachweislich schwächer: kontrolliertes Bitkippen im
Folgeblock und Anfälligkeit für Wasserzeichen-Angriffe.

Der Tweak kommt aus der Sektornummer, little endian (wie `dm-crypt plain64`).
Zwei Sektoren mit demselben Klartext haben damit verschiedenen Geheimtext.
Die beiden Schlüsselhälften werden auf Gleichheit geprüft und ein solcher
Schlüssel abgelehnt (FIPS 140-2 IG A.9).

### Schlüsselableitung: Argon2id — und warum die Runde SYNC anders entschied

`lib/crypto/scrypt.fi` begründet in seinem Kopf, warum dort **nicht** Argon2id
gewählt wurde. Drei Punkte; diese Runde hat sie nachgemessen:

1. *„Argon2 braucht BLAKE2b, das der Baum nicht hat."* — **Galt.** Erledigt:
   BLAKE2b ist gebaut und gegen `hashlib.blake2b` gemessen (71/71).
2. *„`argon2-cffi` ist auf diesem Wirt nicht vorhanden — eine selbstgebaute
   Kryptographie ohne fremde Gegenrechnung wäre die schlechteste aller
   Fassungen."* — **Galt für den Wirt von damals.** Gemessen am 14.09.2026:
   der `argon2`-Befehl (Referenzumsetzung der Norm) ist paketiert und
   installiert, `argon2-cffi` ist ladbar. Damit ist die Gegenrechnung da, und
   zwar gegen die Referenz selbst.
   *Nebenbefund:* libsodium/PyNaCl kann Argon2id auch, aber **nur mit p=1** —
   der RFC-9106-Vektor mit p=4 lässt sich damit nicht prüfen. Das ist der
   Grund, warum `argon2-cffi` und nicht PyNaCl die Gegenstelle ist.
3. *„Zwei neue Kryptobausteine in einer Runde, deren Aufgabe der Abgleich
   ist."* — **War richtig, gilt hier nicht:** in dieser Runde *ist* die
   Schlüsselableitung die Aufgabe.

Argon2id, weil seine erste Hälfte datenunabhängig läuft (Widerstand gegen
Seitenkanäle) und die zweite datenabhängig (Widerstand gegen
Zeit-Speicher-Handel). Es ist die Vorgabe von LUKS2 und die Empfehlung von
RFC 9106.

PBKDF2-SHA256 bleibt als Nummer im Kopfsatz vorgesehen (`KDF_PBKDF2 = 2`),
ist aber nicht gebaut — es wurde nicht gebraucht.

---

## 3. Der Aufbau

### Der Kopfsatz (eigener Entwurf, LUKS2-Prinzip)

Der tragende Gedanke von LUKS, und er ist der Grund für alles Weitere:

> **Der Hauptschlüssel wird nie aus der Passphrase abgeleitet.**

Er kommt einmal aus `rand.bytes` und bleibt für die Lebensdauer des Trägers
derselbe. Die Passphrase leitet nur einen *Einpackschlüssel* ab, und damit
liegt der Hauptschlüssel verschlüsselt in einem *Schlüsselplatz*. Daraus folgt
unmittelbar, was Abschnitt 7 der Abnahme misst: Passphrase wechseln, ohne einen
einzigen Sektor neu zu verschlüsseln.

Acht Sektoren zu 512 = 4096 Oktette:

```
0x000  Kennung "OSUMCRYPT" (9)
0x010  Fassung (4, le)      0x014  Chiffre (4)     0x018  KDF (4)
0x01C  Sektorgröße (4)      0x020  erster Datensektor (8)
0x028  Zahl der Datensektoren (8)
0x030  SHA-256 über den Kopf, dieses Feld als Nullen gerechnet (32)
0x100  Schlüsselplatz 0 … 0x800  Schlüsselplatz 7   (je 256 Oktette)
```

Ein Schlüsselplatz:

```
0x00 belegt (4)   0x04 t (4)   0x08 m in KiB (4)   0x0C p (4)
0x10 Salz (32, je Platz eigenes)
0x30 der eingepackte Hauptschlüssel (64, XTS mit Tweak 0)
0x70 HMAC-SHA256 darüber, mit den letzten 32 Oktetten der Ableitung
```

Die Ableitung liefert 96 Oktette: 64 zum Einpacken, 32 zum Prüfen. Der
Prüfwert geht über den **eingepackten** Schlüssel und nicht über den
Hauptschlüssel — sonst wäre er für jeden Platz derselbe und ein Orakel für
einen geratenen Hauptschlüssel.

### Die Einbindung

`kernel/blk.fi`, Funktionen `read`/`write`: sie fragen `krypto.active(state)`
und gehen sonst den alten Weg. Der bisherige Rumpf heißt jetzt
`read_raw`/`write_raw`, Zeile für Zeile unverändert.

**`kernel/fs.fi` hat keine geänderte Zeile** — und kann auch keine brauchen:
was es liest, ist entschlüsselt, bevor es ankommt. Dasselbe gilt für OFS' Journal,
FAT, ext4 und NTFS.

Der Tweak wird aus der Nummer gerechnet, die **oben** benutzt wird (der Block
des Dateisystems), nicht aus der absoluten auf dem Gerät. Damit ist er
unabhängig davon, wo der Datenbereich anfängt.

### Der Speicher

`CRYPT_OFF = 0x113000 … 0x118000`, fünf Seiten — **die zugeteilte Adresse**,
nicht eine gesuchte. `tools/kernel/memmap.py`: 123 Bereiche, 222 Modusnamen,
**0 Kollisionen**. Der Hauptschlüssel liegt in der zweiten Seite und nirgendwo
sonst; Ring 3 kommt dort nicht hin (SMEP/SMAP, Runde K10). Das ist der Grund,
warum die Entsperrung im Kern sitzt und nicht in einem Programm.

---

## 4. Die Messwerte

### Gegen die Normen und gegen fremde Umsetzungen

| Gruppe | Ergebnis | Gegenstelle |
|---|---|---|
| BLAKE2b | **71/71** | `hashlib.blake2b`, 11 Nachrichtenlängen × 5 Ausgabelängen, dazu 16 mit Schlüssel |
| Argon2id/i/d | **49/49** | `argon2-cffi` (Referenzumsetzung), t=1..3, m=8..256, p=1,2,4 |
| XTS-AES-256 | **42/42** | `cryptography`/OpenSSL, beide Richtungen, 16..4096 Oktette, CTS, Sektor-Tweak |
| Negative Hälfte | **6/6** | jede muss `FAIL` geben |
| **Summe** | **168/168** | |

Dazu der offizielle Argon2id-Vektor (t=3, m=32, p=4) gegen den
`argon2`-Befehl der Distribution — eine **dritte** Umsetzung neben unserer und
`argon2-cffi`: `f25048ec…e5ce`, Ziffer für Ziffer gleich.

Die negative Hälfte ist keine Zierde: gleiche XTS-Schlüsselhälften, zu kurzer
Block, zu kurzer Schlüssel, zu kleines Salz, m < 8·p, unbekanntes Wort. Ein
Orakel, das nie `FAIL` sagt, misst nichts.

### Die volle Kette, über einen echten Neustart

```
Lauf 1  krypto: neu=1  selbst=1  fsformat=1  kopfda=1  mount=1  baum=4
── Rechner neu gestartet ──
Lauf 2  krypto: auf=1 fehler=0 platz=0  mount=1
        sha 0 = 5a2cda2351d1cdd9dd7957e57c0b3c8522451f25b6494569b7e94388c46f0980
        sha 1 = 2f6a24a8fa6fc911e352959a821326e276ae9b5bcaada44d7daea8471f91917c
        sha 2 = 722a77af0e1dac276b056311f6da48e143a64318996fdc6a9ccd272285241166
        sha 3 = 4a5816411def80d35a632eb1d5dcc8eaf06c14cb4b53a086e561576c7d3a253c
```

Alle vier gegen `hashlib` auf dem Wirt: **4/4**. Die Längen sind 100, 700,
5000 und 40000 Oktette — ein Block, zwei Blöcke, über die direkten Zeiger
hinaus, tief in die zweifach indirekten.

### Die Gegenproben

| Fall | Antwort |
|---|---|
| falsche Passphrase | `auf=0 fehler=1` · `mount=0` |
| beschädigter Kopfsatz (16 Oktette im Platz gekippt) | `auf=0 fehler=1` · `mount=0` |
| gar nicht entsperrt (`kryptoroh`) | `roh=1` · `mount=0` |

Die ersten beiden Zeilen sind **Zeichen für Zeichen dieselbe**; der Läufer
vergleicht sie ausdrücklich. `unlock` rechnet **immer alle acht Plätze** durch,
auch wenn der erste passt — ein Abbruch beim ersten Treffer machte die Laufzeit
zum Orakel dafür, welcher Platz gepasst hat, ein Abbruch beim ersten
Fehlschlag verriete, wie viele belegt sind.

### Das Rohgerät

```
roh: sektoren=8184   leer=8017   beschrieben=167
roh: entropie_min=7.495  mittel=7.586  unter7=0
roh: sig OFS-Superblock=0  OFS-Kennung gedreht=0  NTFS=0  FAT=0
roh: textfolgen16=0
```

Die ersten 64 Oktette jeder der vier Dateien: im ganzen Rohbild nicht zu
finden. Die 8017 leeren Sektoren sind **nie beschrieben** worden und werden
bei der Entropie ausdrücklich nicht mitgezählt — eine unbenutzte Platte ist
kein Leck, aber sie würde den Mittelwert schönen.

### Schlüsselplatz-Wechsel

```
1) kryptoneu kryptopw=alt                          -> baum=4
2) kryptoauf kryptowechs kryptokill (alt -> neu)   -> wechsel=1 kill=1 plaetze=1
3) kryptoauf kryptopw=alt                          -> auf=0        (abgewiesen)
4) kryptoauf kryptopw=neu                          -> auf=1 platz=1 mount=1
                                                      sha 0..3 unverändert (4/4)
```

Der gelöschte Platz ist genullt und nicht nur als leer gemeldet — sonst stünde
der eingepackte Schlüssel weiter auf der Platte.

### Die Gegenprobe mit fremden Augen, beide Richtungen

**Richtung 1** — was OrientOS verschlüsselt hat, macht der Wirt auf:
Kopfprüfsumme richtig, Schlüsselplatz mit Argon2id+XTS ausgepackt, darunter
der OFS-Superblock (`SFO-MUSO`), und **alle vier Dateien 4/4** Oktett für
Oktett aus dem Geheimtext geholt — bis in die zweifach indirekten Zeiger.

**Richtung 2, die schärfere** — der Wirt legt einen Träger an, den OrientOS nie
gesehen hat (Hauptschlüssel aus `os.urandom`, fremdes Salz, fremde Ableitung).
OrientOS macht ihn auf (`auf=1`), legt sein Dateisystem darauf an
(`fsformat=1`) und schreibt den Baum (`baum=4`) — und der Wirt liest ihn
wieder: **4/4**.

Diese Richtung fällt aus, sobald OrientOS irgendwo etwas anderes rechnet als
die Norm, auch wenn es mit sich selbst einig bleibt.

### Geschwindigkeit

| Was | Vorher | Nachher | Faktor |
|---|---|---|---|
| Argon2id t=3, m=64 MiB, p=4 | 13,1 s | **2,7 s** | 4,9 |
| XTS, ein Sektor (512 Oktette) | 3,7 ms | **1,2 ms** | 3,1 |
| Durchsatz XTS | 0,13 MiB/s | **0,41 MiB/s** | |
| Entsperren mit den Vorgaben (8 Plätze, samt Hochlauf) | — | **5,2 s** | |

Zwei gemessene Engstellen, beide ohne Wertänderung (168/168 vorher wie
nachher):

1. `qget`/`qput` in Argon2 holten jedes 64-Bit-Wort aus acht Einzeloktetten —
   über 800 Millionen Einzelzugriffe bei t=3/m=64 MiB. x86-64 *ist* little
   endian; ein unausgerichtetes `u64` ist dort ein Befehl.
2. `mix_columns` in AES rief die allgemeine Körpermultiplikation (Schleife über
   acht Bits) für die Faktoren 2 und 3 auf. `gmul(x,2)` ist `xtime(x)`,
   `gmul(x,3)` ist `xtime(x) ^ x`.

`aes.fi` gehört nicht dieser Runde allein — WLAN und SSH binden dieselbe
Datei. Deshalb ist die Abnahme der Runde WLAN mitgelaufen: **171 Zusagen, 0
Fehler**, darunter der echte WPA2-Mitschnitt.

**Die Vorgaben der Ableitung** (t=2, m=32 MiB, p=4) sind aus der gemessenen
Geschwindigkeit gewählt, nicht abgeschrieben: 13,7 µs je KiB und Durchgang,
also 0,90 s je Platz und 7,2 s für acht. Mit den Werten aus RFC 9106
Abschnitt 4 (t=3, m=64 MiB) wären es 21,6 s gewesen.

---

## 5. Die roten Punkte

Einzeln benannt, nicht versteckt.

1. **XTS läuft mit 0,41 MiB/s.** Für eine Platte ist das zu wenig — ein
   Sektor kostet 1,2 ms, ein Megaoktett rund 2,5 s. Die Ursache ist bekannt
   und liegt nicht in dieser Runde: `lib/crypto/aes.fi` rechnet Oktett für
   Oktett über eine S-Box-Tabelle, weil es für WLAN geschrieben wurde, wo AES
   einmal je Rahmen läuft. Der Weg ist AES-NI (`AESENC`/`AESENCLAST`, auf jedem
   x86-64 seit 2010, Faktor ~1000). Das ist eine eigene Runde.
2. **Die Rechnung ist nicht konstantzeitig.** Die S-Box ist eine Tabelle, und
   `sbox[x]` mit geheimem x hat auf einem Rechner mit Zwischenspeicher eine
   Laufzeit, die vom Wert abhängt. `aes.fi` sagt das seit Runde WLAN selbst.
   Gegen einen Angreifer mit der gestohlenen Platte — der Fall, um den es bei
   Plattenverschlüsselung geht — ist das ohne Belang; gegen einen Angreifer auf
   *derselben* Maschine nicht. Die Vergleiche von Prüfwerten und Kennung in
   `krypto.fi` laufen dagegen über alle Oktette und brechen nicht früh ab.
3. **Argon2 rechnet p > 1 nicht wirklich parallel.** Die Norm erlaubt p Spuren
   nebeneinander; diese Umsetzung rechnet sie nacheinander in der
   vorgeschriebenen Reihenfolge. Das Ergebnis ist Oktett für Oktett dasselbe
   (der RFC-9106-Vektor mit p=4 stimmt), es fehlt nur der
   Geschwindigkeitsgewinn.
4. **Die Vorgaben sind eine Abwägung, keine Empfehlung der Norm.** t=2 und
   32 MiB liegen unter RFC 9106 Abschnitt 4. Dass das keine Sackgasse ist, ist
   der Grund für die Schlüsselplätze: die Zahlen stehen je Platz im Kopfsatz,
   und ein Träger bekommt später einen Platz mit mehr, ohne dass ein Sektor
   neu verschlüsselt wird.
5. **Keine Authentifizierung.** XTS erkennt keine Veränderung — das ist keine
   Nachlässigkeit, sondern folgt daraus, dass ein Sektor keinen Platz für ein
   Etikett hat. Wer Manipulation erkennen will, braucht eine Schicht wie
   `dm-integrity` daneben. LUKS2 hat dieselbe Eigenschaft.
6. **Die Passphrase kommt von der Kommandozeile, nicht von der Tastatur.**
   `kryptopw=…` ist eine Einschränkung des Messlaufs (ein Abnahmelauf in QEMU
   hat keinen Menschen, der tippt) — und im Betrieb **nichts wert**: sie steht
   im Startprotokoll und in `/proc`. Die Eingabe über den Sperrbildschirm ist
   die nächste Runde. Der Sperrbildschirm und die Benutzerverwaltung sind da;
   was fehlt, ist die Eingabe *vor* dem Einhängen der Wurzel.
7. **Kein Umwandeln im Betrieb.** Ein Träger wird verschlüsselt *angelegt*;
   bestehende Daten werden dabei überschrieben, nicht umgeschrieben. Was
   `cryptsetup reencrypt` kann, kann diese Runde nicht.
8. **Nur die Wurzelplatte.** Die Naht sitzt in `blk.read`/`blk.write`, also am
   Weg zur Wurzel. `read_on`/`write_on` (zweite Platte, USB, FAT-Partitionen)
   gehen daran vorbei und sind unverschlüsselt. Für einen verschlüsselten
   zweiten Datenträger bräuchte es eine Tafel „Gerät → Schlüssel" statt der
   einen Seite in `kstate`.
9. **Der Abnahmelauf rechnet mit kleinen Parametern** (t=1, m=64 KiB), damit er
   in Minuten läuft. Sie stehen im Kopfsatz, werden also beim Aufmachen
   genauso benutzt — ein Schalter, der im Messlauf etwas anderes rechnete als
   im Betrieb, wäre unehrlich. Die Vorgabe-Parameter sind in einem eigenen
   Lauf gemessen (5,2 s).

---

## 6. Was wo steht

| Datei | Was |
|---|---|
| `lib/crypto/blake2b.fi` | BLAKE2b, RFC 7693 |
| `lib/crypto/argon2.fi` | Argon2id/i/d, RFC 9106 |
| `lib/crypto/xts.fi` | XTS-AES-256, IEEE 1619 |
| `kernel/krypto.fi` | Kopfsatz, Schlüsselplätze, Entsperren, Sektorweg |
| `kernel/blk.fi` | die Naht (`read`/`write` → `read_raw`/`write_raw`) |
| `kernel/kstate.fi` | `CRYPT_OFF` und die Modusworte |
| `kernel/kmain.fi` | die Stufe beim Hochlauf, zwischen `use_ata` und `fs.mount` |
| `tools/krypto/orakel.fi` | dieselben `lib/crypto`-Dateien, auf dem Wirt |
| `tools/krypto/gegen.py` | die unabhängige Umsetzung |
| `tools/krypto/run.sh` | die Abnahme, 61 Punkte |

Modusworte: `kryptoneu`, `kryptoauf`, `kryptofs`, `kryptotest`, `kryptoroh`,
`kryptofalsch`, `kryptobaum`, `kryptopruef`, `kryptowechs`, `kryptokill`;
Werte `kryptopw=`, `kryptopw2=`, `kryptot=`, `kryptom=`, `kryptop=`.

---

## 7. Drei Fehler, die nur die Gegenprobe gefunden hat

Sie stehen hier, weil sie der eigentliche Beleg dafür sind, warum gegen eine
fremde Umsetzung gemessen wird und nicht gegen sich selbst.

1. **Der Adressblock von Argon2i/id wurde am Segmentanfang nie erzeugt.** Im
   ersten Segment fängt der Index bei 2 an, und die Bedingung
   `index % 128 == 0` trifft dann nie zu. **Mit seg_len < 4 fällt das nicht
   auf** — m=8 und m=16 waren grün, ab m=32 war jeder Argon2i- und
   Argon2id-Wert falsch, während argon2**d** weiter stimmte. Ein Selbsttest
   hätte das nie gefunden: die Werte waren stabil und in sich stimmig.
2. **`cur - 1` lief unter** bei lane 0, slice 0, index 0. Firn panickt bei
   Unterlauf, also fiel es auf — aber erst bei p > 1.
3. **`index_alpha` hatte tote Zweige** für die fremde Spur, in denen ich mich
   verrechnet hatte.

Dazu drei Fehler, die *wie* Fehler der Verschlüsselung aussahen und keine
waren: `root_from_part` stellte den Wurzelversatz zurück, worauf `fs.format`
den Kopfsatz überschrieb; `find` traf `kryptot` innerhalb von `kryptotest` und
nahm lautlos die Vorgabe; und OFS-Fassung 2 rechnet die Kartenblöcke nicht aus
der Plattengröße aus, worauf `mount` 8184 Blöcke richtigerweise ablehnte.
Gefunden wurde der letzte, indem der Superblock **mit Python entschlüsselt**
und Feld für Feld gelesen wurde.
