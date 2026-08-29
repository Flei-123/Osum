# RUNDE FEEDBACK — Zwischenstand

Zweig `feedback`, abgezweigt von `mergeline`. **Nicht nach `main` gemergt.**
Arbeitsbaum `/root/fb-osum`.

---

## 1. Was jetzt geht

Ein Mensch, der in Osum sitzt, kann eine Fehlermeldung oder einen Wunsch
absetzen — mit einem Bildschirmfoto — und Justin sieht sie im selben
Dashboard, in dem FleiLauncher und FreeViewer landen.

```
/bin/feedback -f 'Text'      eine Fehlermeldung
/bin/feedback -w 'Text'      ein Wunsch
              -b             ein Bildschirmfoto anhaengen
              -k kontakt     freiwillig
              -ja            senden (OHNE das geht nichts hinaus)
              -warten        nur die Warteschlange abarbeiten
/bin/feedback                ohne Argumente: das Fenster
```

Der Weg einer Meldung, von unten nach oben:

| Schicht | Datei | was sie tut |
|---|---|---|
| Kern | `kernel/shot.fi` | `SYS_OSUM_SHOT` (1840): der Rahmenpuffer, bandweise, **nur mit Schein** |
| Kern | `kernel/sse.fi` | CR4.OSFXSR — ohne das stirbt TLS (siehe 3.) |
| Ring 3 | `kernel/app/png.fi` | PNG-Schreiber ueber `std.deflate` (kein eigener Packer) |
| Ring 3 | `kernel/app/shot.fi` | `/bin/shot`: Rahmenpuffer → PNG + Vorschaubild |
| Ring 3 | `kernel/user/feedback.fi` | das Programm, JSON, base64, Warteschlange, Fenster |
| Ring 3 | `kernel/app/fetch.fi` | `-p <datei>` / `-c <typ>`: HTTPS **POST** ueber TLS 1.3 |
| Server | `tools/feedback/php/feedback.php` | `image` als base64, 4-MiB-Grenze, Magic Bytes, Ratenbremse |
| Server | `tools/feedback/php/feedback-dash.php` | Vorschaubild in der Meldung, Bild nur mit Token |

## 2. Die Sicherheitsfrage, ausdruecklich beantwortet

> Darf ein beliebiges Programm den Bildschirm mitlesen?

**Nein.** `SYS_OSUM_SHOT` gibt nur Bildpunkte heraus, wenn ein **Schein**
auf die eigene Prozessnummer ausgestellt ist. Den Schein gibt es auf
genau zwei Wegen:

* `SH_ARM` — nur die **Taskleiste** oder die **Wurzel** duerfen ihn
  ausstellen (`shot_may_arm`), und die Taskleiste stellt ihn aus,
  **nachdem** sie den Menschen gefragt hat;
* `SH_KEY` — der Mensch hat **Super+P** gedrueckt. Die Zaehlernummer des
  Tastendrucks wird dabei **verbraucht**: ein zweiter Aufruf zu
  demselben Druck bekommt nichts.

Jeder abgelehnte Versuch wird gezaehlt (`SI_DENIED`) und ist aus Ring 3
frei abfragbar — was gezaehlt wird, kann nicht heimlich sein. In dieser
Runde kam ein Loch im **Protokoll** dazu: ein zurueckgewiesenes
`SH_DROP` wurde als einziges der drei nicht gezaehlt, der Zaehler stand
nach drei Versuchen auf zwei. Behoben.

Und oben herum: **ohne `-ja` bzw. ohne den Knopf im Bestaetigungsfenster
geht nichts hinaus.** Das Fenster zeigt vorher, was gesendet wird —
Projekt, Art, Text, Kontakt und das Bild, so wie es hinausgeht.

## 3. Der Fehler, an dem die Runde wirklich hing

`/bin/fetch` starb reproduzierbar:

```
user fault: pid=5  vector=6  err=0x0  cr2=0x4006ce48  rip=0x4013905f
40139059:  mov  -0x680(%rbp),%rax
4013905f:  movdqu (%rax),%xmm4        <-- #UD
```

`_F0.accel__sha256_ni_blocks`. Nicht der Uebersetzer, nicht die
Bibliothek: **dieser Kern hat SSE nie erlaubt.** Nach dem Ruecksetzen ist
`CR4.OSFXSR` null, und ohne dieses Bit ist jeder SSE-Befehl ein
ungueltiger Befehl.

Warum das nie auffiel: unter **TCG** meldet QEMUs Ersatzprozessor kein
SHA-NI, also nimmt `std/crypto/sha256.fi` den skalaren Weg. Mit
`-accel kvm -cpu host` auf einem Zen meldet CPUID SHA-NI, `accel.fi`
rechnet in `xmm0..xmm5` — und das erste Wort in ein 128-Bit-Register
bringt den Prozess um. **Dieselbe Sorte wie Runde KVMFIX: der Fehler
steht erst da, wenn die echte CPU darunter liegt.**

Behoben in vier Dateien, und die Pflicht ist mitbehoben:

* `kernel/sse.fi` — `CR0.MP=1`, `CR0.EM=0`, `CR4.OSFXSR`,
  `CR4.OSXMMEXCPT`; **nur** wenn CPUID FXSR und SSE meldet (sonst waere
  das `mov cr4` ein #GP im Kern), und danach **zurueckgelesen**.
* `arch/x86_64/switch.s` — wer xmm erlaubt, muss xmm aufheben:
  `fxsave`/`fxrstor` in 512 Oktetten auf dem Kernstapel der Aufgabe, die
  weggelegt wird. Die 16er-Ausrichtung wird **erzwungen** und nicht aus
  der Aufrufregel gefolgert.
* `sched.fi` — `frame_build` legt fuer eine Aufgabe, die noch nie lief,
  eine **gueltige** Anfangsablage an (FCW `0x037F`, MXCSR `0x1F80`); ein
  `fxrstor` auf Muell waere ein #GP.
* `arch/x86_64/smp.fi` — jeder weitere Prozessor bekommt die Bits auch,
  CR4 ist pro Kern.

Zwei weitere Fehler, beide mit einer Zahl belegt statt mit einer
Vermutung:

* **`exec` gab 127.** `proc.MAX_ARGS` ist **acht**, `senden()` uebergab
  **neun** — `elf.write_args` weist alles darueber wortlos ab. Weg
  damit: `-r /etc/ssl/roots.pem` **ist** der Vorgabewert von `/bin/fetch`,
  und `application/json` ist dort die Vorgabe fuer einen POST.
* **Die Warteschlange ging verloren.** `SYS_RENAME` antwortet in dieser
  Zusammenstellung mit **-38 (ENOSYS)**: `sys.do_rename` prueft
  `vfs.ready`. Die Meldung blieb als `melden.json` liegen, der naechste
  Start suchte `warten.json` und fand nichts. Jetzt gibt es nur **eine**
  Datei — gebaut wird gleich unter dem endgueltigen Namen, geloescht
  wird erst, wenn der Server geantwortet hat.

## 4. Die Zahlen

`tools/feedback/run.sh`, QEMU mit `-accel kvm -cpu host`:

```
FEEDBACK: 71 gruen, 0 rot, 0 uebersprungen
```

Das Wichtigste daraus, gemessen und nicht behauptet:

| | |
|---|---|
| PNG von innen, 800x600 | **18 820 Oktette** |
| roh (`(800*3+1)*600`) | 1 440 600 Oktette → **76:1**, also wirklich DEFLATE und kein `stored` |
| Bildpunkte gegen QEMUs eigenen `screendump` | 480 000 verglichen, **0 Unterschiede** |
| Vorschaubild | 200 x 150, 0 abweichende Stichproben |
| Meldung ohne Bild | 180 Oktette, `POST /feedback.php`, `Content-Type: application/json` |
| Meldung mit Bild | 27 451 Oktette; beim Server ein gueltiges PNG, 800x600, 20 454 Oktette |
| ohne Netz | liegt als `/var/feedback/warten.json` (180 Oktette), Text unveraendert |
| naechster Lauf mit Netz | **dieselbe** Meldung geht nach |
| alter Vertrag | alle sieben Felder in jeder Meldung, `type` immer eines der drei Woerter |
| Schloss | `SH_GRAB`/`SH_KEY`/`SH_DROP` ohne Schein: **alle drei** -EPERM, alle drei gezaehlt |

Das PNG wird auf dem **Wirt** mit Pillow geoeffnet, nicht mit diesem
Repo; der HTTPS-Empfaenger im Testlauf ist pythons `http.server` mit
`ssl` — beides Code, den dieses Projekt nicht geschrieben hat.

Bilder: `docs/shots/feedback/` (von innen, screendump des Wirtes, und
das, was beim Server ankam).

## 5. Serverseite — Stand

Der Endpunkt **lebt und kann Bilder**, gemessen von hier aus gegen
`https://fleilauncher.fleitec.com/feedback.php` (109.69.172.199):

| Probe | Antwort |
|---|---|
| GET | `405 POST only` |
| alter Vertrag, ohne Bild | `{"ok":true,"id":"..."}` — **unveraendert** |
| gueltiges PNG | `{"ok":true,"id":"...","image":true}` |
| PHP-Code als „Bild" | `image_error: not a PNG or JPEG` (Magic Bytes, nicht die Endung) |
| 5 MiB | `image_error: image too large` |
| kein base64 | `image_error: image is not base64` |
| 9. Meldung in 10 Minuten | **HTTP 429** `too many reports, try later` |
| Dashboard ohne Token | **403** |
| Bild ohne Token | **403** |
| Bild mit Token | `200 image/png`, Pillow oeffnet es |

Der Dateiname kommt **nie** aus der Anfrage: er ist die zufaellige
Satz-Kennung, die Endung kommt aus den magischen Oktetten, das
Verzeichnis liegt ausserhalb des Web-Roots.

### Was serverseitig noch fehlt / offen ist

* **Ich habe keine Konsole auf dem Zielrechner.** `fleilauncher.fleitec.com`
  laeuft hinter dem openresty-Ingress auf CT103 (192.168.1.53); SSH
  dorthin wird abgelehnt (`Permission denied (publickey,password)`), und
  weder `/var/www/fleilauncher` noch `/var/lib/fleifeedback` liegen auf
  dem JARVIS-Server. Die Kopien in `tools/feedback/php/` sind der
  **Bezug**; dass die dort ausgelieferte Fassung sich **genauso
  verhaelt**, ist oben gemessen — dass sie Oktett fuer Oktett dieselbe
  ist, kann ich von hier aus nicht nachweisen.
* Ein **Aufraeumen alter Bilder** gibt es nicht. `/var/lib/fleifeedback/bilder`
  waechst, bis jemand loescht; ein `find -mtime +N -delete` im cron fehlt.
* Der Ratenzaehler liegt als Datei je Adress-Streuwert unter
  `/var/lib/fleifeedback/rate`. Auch das waechst.

## 6. Bekannte Grenzen im Betriebssystem

* Die Warteschlange hat **einen Platz**. Liegt eine Meldung, fuer die es
  kein Netz gab, und der Mensch schreibt eine neue, bevor sie hinausging,
  ueberschreibt die neue die alte. Fuer mehr braucht es durchnummerierte
  Dateien im Verzeichnis — das ist eine eigene Runde wert und wird hier
  nicht behauptet.
* `/bin/feedback` sendet ueber `/bin/fetch`, also einen zweiten Prozess.
  Die Grenze von **acht** Argumenten (`proc.MAX_ARGS`) ist damit hart:
  ein weiteres Wahlwort passt nicht mehr hinein, ohne dass diese Zahl
  steigt.
* Das Fenster (`feedback` ohne Argumente) haengt am Fensterserver; die
  Abnahme oben misst den **Weg ohne Fenster**. Der Fensterweg ist
  gebaut, aber nicht mit Bildpunkten belegt.

## 7. Commits dieser Runde

```
FEEDBACK 1/n  der Bildschirmfoto-Aufruf (kernel/shot.fi, SYS_OSUM_SHOT 1840)
FEEDBACK 2/n  /bin/shot -- der Rahmenpuffer wird ein PNG
FEEDBACK 3/n  SSE einschalten -- der Fehler, der nur unter KVM da ist
FEEDBACK 4/n  ein abgelehnter SH_DROP wird gezaehlt wie die anderen zwei
FEEDBACK 5/n  /bin/feedback -- die Meldung geht wirklich hinaus
```
