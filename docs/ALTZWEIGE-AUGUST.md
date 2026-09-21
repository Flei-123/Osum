# Die Altzweige vom August — gesichtet, entschieden, begründet

**Erhebung vom 21.09.2026.** Baum `/root/fb-osum`, `main` bei `0f7e047a`
("Merge branch 'runde-zieh'").

Sechs Zweige lagen seit Ende August ungemergt herum, und niemand wusste
mehr, was davon noch gilt. Dieses Blatt beantwortet für **jeden** dieser
Zweige die drei Fragen — was er wollte, ob es noch gilt, ob er noch
aufsetzt — **mit gemessenen Belegen**, damit die Frage nicht in vier
Wochen wieder auftaucht.

**Kein Zweig wird gelöscht.** Alle sechs bleiben im Baum stehen; wer
eine Zahl aus einer dieser Runden nachlesen will, findet sie dort. Was
sich ändert, ist nur: es ist jetzt aufgeschrieben, was mit ihnen ist.

---

## 0. Die kurze Antwort

| Zweig | Commits | was er wollte | gilt noch? | gemergt? |
|---|---:|---|---|---|
| `certus` | 12 | Certus-Browser auf Osum | **nein** — von `certus2` (05.09.) ersetzt | nein |
| `demux` | 11 | MP4/MKV/MP3 abspielen | **teilweise** — Ton+MP3 da, Behälter nicht | nein |
| `feedback` | 8 | Bildschirmfoto + Rückmeldung | **nein** — `/bin/snip` + 1841 sind da | nein |
| `a11y` | 5 | Barrierefreiheitsbaum (S-007) | **JA — als einziger** | nein, **Neubau nötig** |
| `inventory` | 3 | SPDX-Kopfzeilen, Lizenzsplit | **nein** — vollständig auf `main` | nein |
| `haertung` | 2 | W^X im Kern, Wachseiten, ASLR | **JA** | nein, **Portierung nötig** |

**Gemergt wurde am Ende: keiner.** Die Begründung dafür steht in
Abschnitt 1 und ist bei allen sechs dieselbe — sie ist der eigentliche
Befund dieser Sichtung.

---

## 1. Der gemeinsame Grund: der Baum ist unter den Zweigen weggelaufen

Alle sechs Zweige zweigten zwischen dem **27. und 30. August** ab.
Seither ist `main` weitergelaufen — und zwar nicht ein bisschen:

| Zweig | Abzweig | Datum | Commits auf `main` seither |
|---|---|---|---:|
| `inventory` | `afafc7f4` | 27.08. | **1308** |
| `feedback` | `c60c0307` | 28.08. | **1101** |
| `certus` | `5cb03208` | 28.08. | **1085** |
| `demux` | `5cb03208` | 28.08. | **1085** |
| `a11y` | `5cb03208` | 28.08. | **1085** |
| `haertung` | `326c0ece` | 30.08. | **907** |

Dazwischen liegt die Runde **O-STRUKTUR** (17.09., `docs/STRUKTUR.md`),
die den Kernbaum in Schichten geordnet hat: **120 Dateien sind
umgezogen**, alle als echte Umbenennung. Die Zweige vom August kennen
diese Ordnung nicht.

### Was das praktisch heisst

`kernel/sys.fi` → `kernel/sys/sys.fi` · `kernel/kstate.fi` →
`kernel/lib/kstate.fi` · `kernel/wm.fi` → `kernel/ui/wm.fi` ·
`kernel/kbd.fi` → `kernel/drv/hid/kbd.fi` · `kernel/ac97.fi`,
`kernel/audio.fi` → `kernel/drv/snd/`

Ein `git merge` eines Augustzweigs meldet diese Umzüge als
**`modify/delete`** — und legt die **alte** Datei am **alten** Pfad
wieder an. Gemessen:

```
a11y      13 Konflikte,  3 davon modify/delete
demux     10 Konflikte,  2 davon modify/delete
feedback  10 Konflikte,  3 davon modify/delete
certus    26 Konflikte,  1 davon modify/delete
inventory 47 Konflikte, 19 davon modify/delete
haertung   7 Konflikte,  0 davon modify/delete
```

Bei `a11y` hiesse das wörtlich: `kernel/wm.fi` (4083 Zeilen, Stand
August) käme **neben** `kernel/ui/wm.fi` (10279 Zeilen, Stand heute) zu
liegen. **Zwei Fensterserver in einem Baum.**

### Und die Dateien, die git *nicht* als Konflikt meldet

Das ist der gefährlichere Teil, und es ist genau der Unfall, vor dem
der Auftrag gewarnt hat:

| Datei | bei Abzweig | auf dem Zweig | auf `main` heute |
|---|---:|---:|---:|
| `kernel/user/wlib.fi` | 3215 | 3921 (`a11y`) | **10475** |
| `kernel/user/wlibc.fi` | 2943 | 3145 (`a11y`) | **6155** |
| `kernel/kmain.fi` | 5657 | 5971 (`a11y`) | **7801** |

In `wlib.fi` sitzen seit `986acdc2` die **Animationen** und seit
`0f7e047a` Justins **Zieh-Aufhebung**. Nachgezählt:

```
main  kernel/user/wlib.fi :  anim  20 Treffer,  zug_laeuft/zug_bilder  4 Treffer
a11y  kernel/user/wlib.fi :  anim   0 Treffer,  zug_laeuft/zug_bilder  0 Treffer
main  kernel/ui/wm.fi     :  anim  43 Treffer
a11y  kernel/wm.fi        :  anim   0 Treffer
```

Eine Zusammenführung, die an einer dieser Stellen die Augustfassung
gewinnen lässt, **löscht die Animationen und die Zieh-Aufhebung still
aus** — ohne einen einzigen Konflikt zu melden. Das ist derselbe
Vorgang, der auf `certus` schon einmal passiert ist (siehe dort,
Abschnitt 2).

**Deshalb wird keiner dieser Zweige gemergt.** Was von ihnen gilt
(`a11y`, `haertung`), wird **neu gegen den heutigen Baum gebaut** — mit
den Zweigen als Vorlage und mit ihren Messwerten als Sollwert.

---

## 2. `certus` — überholt, und der Unfall ist erklärt

**Was er wollte.** 12 Commits, 28.08., 134 Dateien: Justins Browser
Certus als gewöhnliches Ring-3-Programm auf Osum. Der Zweig hat dabei
drei echte Kernel-Lücken gefunden und geschlossen — `/proc/self` für
Firns Sammler, SSE (`CR0.EM`/`CR4.OSFXSR`), und `fxsave` beim
Umschalten.

**Gilt es noch? Nein.** Die Runde ist am **05.09.** als `certus2`
komplett neu gefahren worden, gegen `merge6` statt gegen den Augustbaum,
und **ist auf `main`**. Beleg: `STATUS-CERTUS.md` auf `main` trägt das
Datum 05.09. und beschreibt ausdrücklich die *zweite* Fassung:

> "Der erste Versuch (Runde CERTUS, 28.08.2026) sprach direkt mit dem
> Fensterserver und hatte als Bedienleiste eine Textzeile. Diese Runde
> benutzt die Widget-Bibliothek."

Auf `main` liegen `tools/certus/run.sh`, `assets/apps/certus.osp`,
`kernel/user/sysstub.s`, `kernel/user/certus/build.sh`. Die drei
Kernel-Funde sind ebenfalls da, nur woanders: SSE und `fxsave` stehen
in `kernel/arch/x86_64/fpu.fi` (`CR4_OSFXSR` Zeile 108, gesetzt in
Zeile 439).

**Der Unfall.** Commit `f687ab44` benennt ihn selbst: `ebccaa5a`
("MEDIA1 1/n", der AC97-Treiber) liegt auf `certus`, **weil zwei Runden
dasselbe Arbeitsverzeichnis benutzten und ein `git add -A` der anderen
Runde den ausgecheckten Zweig traf**. Der Inhalt liegt inhaltsgleich
auch auf `media1`. Die Historie wurde bewusst nicht umgeschrieben, weil
jede Zahl der Runde auf genau diesem Baum gemessen ist.

Nachgeprüft: `git branch --contains ebccaa5a` nennt nur `certus` und
`origin/certus` — der Fremdkörper ist also wirklich nur dort.

**Setzt er auf?** 26 Konflikte, darunter elf PNG-Dateien und
`kernel/user/play.fi` als `add/add` — letzteres ist der Fremdkörper,
der mit der heutigen HDA-Fassung kollidiert.

**Entscheidung: begraben.** Ersetzt durch `certus2`.

---

## 3. `demux` — der Ton ist da, die Behälter fehlen

**Was er wollte.** 11 Commits, 28.08.: MP4 und Matroska öffnen, auch
wenn H.264 nicht dekodierbar ist, und den Ton spielen, wenn MP3 oder AAC
darin steckt. Dazu ein vollständiger MP3-Dekodierer in Festkomma. Eigene
Abnahme `tools/demux/run.sh`: **141/0**.

**Gilt es noch? Teilweise — und das ist der einzige Zweig mit echtem
Restwert neben `a11y` und `haertung`.**

Was inzwischen **auf anderem Weg** gekommen ist:

* Der **Ton** kam über die Runden **MEDIA1 → HDA → TON-2**. Auf `main`
  liegen `kernel/drv/snd/ac97.fi`, `kernel/drv/snd/audio.fi`,
  `kernel/drv/snd/hda.fi` (2359 Zeilen, Intel HD-Audio) und
  `kernel/mix.fi`. Der Zweig-Kommentar "ein zweiter Tontreiber wäre ein
  zweiter Fehler" ist damit eingelöst — aber von der anderen Seite.
* **MP3** ist auf `main`: `kernel/user/mp3.fi` (45 566 Oktette) und
  `kernel/user/mp3tab.fi`, gekommen über die Runde HDA.
* `/bin/play` auf `main` (`kernel/user/play.fi`) spielt WAV und MP3,
  über Mischer **und** Einstromweg.

Was **fehlt**: die Behälter. Auf `main` gibt es **kein**
`kernel/user/mp4.fi`, **kein** `mkv.fi`, **kein** `omc.fi`, **kein**
`srt.fi`, **kein** `vol.fi`, **kein** `demuxt.fi`. `media.fi` nennt MP4
und Matroska nur in Kommentaren und kennt `C_MPEG4V` als *Name*, nicht
als Leser.

**Setzt er auf?** 10 Konflikte, 2 `modify/delete`, darunter
`kernel/user/play.fi` und `kernel/user/mp3.fi` — also genau die zwei
Dateien, die inzwischen aus einer **anderen** Runde stammen. Ein Merge
würde die HDA-Fassung von `play.fi` gegen die MEDIA1-Fassung tauschen
und damit den Mischerweg verlieren.

**Entscheidung: nicht mergen, Inhalt als Vorlage aufheben.** Die
Behälterleser (`mp4.fi` 786 Z., `mkv.fi` 979 Z., `srt.fi` 274 Z.) sind
**eigenständige neue Dateien ohne Kollision** — sie lassen sich in einer
eigenen Runde gegen das heutige `media.fi`/`play.fi` neu anschliessen.
Das ist echte Arbeit, keine Zusammenführung. Gehört als eigener Punkt in
die Offenliste (verwandt mit **P-009**, "kein Videodekodierer").

---

## 4. `feedback` — überholt

**Was er wollte.** 8 Commits, 29.08.: der Bildschirmfoto-Systemaufruf
(`kernel/shot.fi`, `SYS_OSUM_SHOT` mit Schein, Taskleisten-Recht und dem
Weg über Super+P), `/bin/shot` als PNG-Schreiber, `/bin/feedback` (935
Zeilen), dazu `tools/hwnet/` mit TLS gegen echte Hardware.

**Gilt es noch? Nein.**

* Der **Systemaufruf ist auf `main`** — und zwar unter der **richtigen**
  Nummer. `kernel/sys/sys.fi` Zeile 1576: `const SYS_OSUM_SHOT: u64 =
  1841`, mit `SH_INFO`, `SH_ARM`, `SH_GRAB`, `SH_KEY`, `SH_DROP` (Zeile
  143) und der Behandlung in Zeile 2868.
* **Der Zweig hat hier einen Fehler, der heute ein echter Schaden
  wäre.** `feedback` schreibt `SYS_OSUM_SHOT = 1840`. Die **1840 ist
  seit der Runde WERKZEUGE `SYS_OSUM_CPUSTAT`** — nachzulesen in
  `lib/libc/kcall.fi`, wo die Kollision ausführlich dokumentiert ist.
  Genau deshalb bekam der Aufruf später die **1841**. Ein Merge von
  `feedback` würde zwei Systemaufrufe auf dieselbe Nummer legen;
  `tools/posix/run.sh` Abschnitt 1 fiele darüber.
* Das **Bildschirmfoto als Programm** gibt es auf `main` als
  `/bin/snip` (`kernel/user/snip.fi`, Runde ALLTAG) — mit Fenster,
  Vollbild, Verzögerung, Fenstermodus, Malwerkzeugen und PNG.
* `tools/hwnet/` liegt vollständig auf `main`.

Was **nicht** auf `main` ist: `/bin/feedback` selbst, also das Programm,
das eine Rückmeldung an einen Server schickt — samt der PHP-Gegenstelle.
Das ist aber kein Betriebssystemteil, sondern ein Dienst, und
`STATUS-FEEDBACK.md` sagt selbst, dass serverseitig etwas fehlt.

**Setzt er auf?** 10 Konflikte, 3 `modify/delete`, darunter
`lib/libc/kcall.fi` — genau die Datei mit der Nummernkollision.

**Entscheidung: begraben.** Der Kern ist da, die Nummer des Zweigs ist
falsch.

---

## 5. `a11y` — der einzige, dessen Substanz noch fehlt

**Was er wollte.** 5 Commits, 28.08., Punkt **S-007** der Offenliste:
den Barrierefreiheitsbaum ins Fensterserver-Protokoll legen — `ax.fi`
im Kern (746 Zeilen, 256 Knoten zu 64 Oktetten), sechs Systemaufrufe,
der Baum entsteht von selbst in `wlib.ax_flush()`, dazu Bildschirmlupe,
hoher Kontrast und Einrastfunktion.

Die Begründung in `docs/A11Y.md` ist gut und gilt unverändert: *nach­
träglich muss jedes einzelne Programm noch einmal angefasst werden;
jetzt kostet es eine Stelle.* Der Auftrag nennt zu Recht den doppelten
Wert — ein solcher Baum ist auch die Grundlage für **automatisches
Messen der Oberfläche**. Die Offenliste sagt dasselbe noch einmal
unabhängig unter **R-010** (und nennt die EU-Barrierefreiheitsrichtlinie
seit 28.06.2025 als Marktzugangsvoraussetzung).

**Gilt es noch? JA — als einziger der sechs vollständig.** Gemessen auf
`main`:

```
grep ax_flush|ax_node|AX_ROLE|a11y  in wm.fi, wlib.fi, wlibc.fi  ->  0 Treffer
grep lupe|Lupe|hochkontrast         in kernel/ui/wm.fi           ->  0 Treffer
grep einrast|sticky                 in kernel/drv/hid/kbd.fi     ->  0 Treffer
git ls-files | grep -i 'a11y|/ax\.|axlesen'                      ->  leer
```

Es gibt auf `main` **keinen** Barrierefreiheitsbaum. S-007 ist offen,
und zwar zu Recht.

**Setzt er auf? Nein — und hier ist es am gefährlichsten.** 13
Konflikte, 3 `modify/delete` (`kernel/kstate.fi`, `kernel/wm.fi`,
`kernel/user/leiste.fi`). Dazu die stillen Kollisionen aus Abschnitt 1:
`wlib.fi` 3921 gegen 10475 Zeilen, ohne eine Spur der Animationen.

**Und zwei Kollisionen, die git überhaupt nicht als Konflikt sieht:**

| `a11y` belegt | auf `main` heute belegt durch |
|---|---|
| `AX_OFF = 0x7A000`, `AX_MAX = 0x6000` (also `0x7A000..0x80000`) | `NETDEV_OFF = 0x7A000` (e1000-Auswahl) und die Runde FSROBUST, die sich **dieselben** drei Seiten `0x7A000..0x80000` genommen hat |
| Systemaufrufe `1960..1965` | `SYS_OSUM_BUS = 1960` (Systembus, mit `BUS_REG`/`BUS_FIND`/`BUS_SEND`/…) |

**Dieser Befund ist nicht neu.** `BEFUND-ZIEH.md` (TEIL 2) hat `a11y`
schon einmal geprüft und aus demselben Grund liegen gelassen — "nicht
aus Zeitmangel", sondern weil "der Versuch kein Merge mehr, sondern eine
Neuschreibung" wäre. Dort steht auch die Nummernkollision 1960 bereits
wortgleich, samt der Beobachtung, dass **beide** Runden dieselbe Lücke
zwischen `SYS_OSUM_WGSET` (1951) und `CAP_BASE` (2000) mit derselben
Begründung belegt haben. Was diese Sichtung hinzufügt, ist die
**zweite** stille Kollision — der Speicherbereich `0x7A000` — und die
Feststellung, dass `wlib.fi` inzwischen auf 10475 Zeilen gewachsen ist.

Beides steht in Dateien, die ein Merge stellenweise sauber zusammen­
führen würde. Das Ergebnis wäre kein Konflikt, sondern ein Kern, der
den Barrierefreiheitsbaum über den Netzkartenzustand schreibt und
dessen Systemaufruf 1960 zwei Bedeutungen hat. Das findet kein Test
sofort, und es ist genau die Art Fehler, die dieses Projekt sonst
sauber vermeidet.

**Entscheidung: nicht mergen — neu bauen, Zweig als Vorlage.** Die
Substanz ist wertvoll und fehlt wirklich; der Code ist aber gegen einen
Baum geschrieben, den es nicht mehr gibt. Eine eigene Runde **A11Y-2**
sollte:

1. `ax.fi` nach `kernel/ui/ax.fi` legen (dorthin gehört es heute —
   `kernel/ui/` enthält `wm.fi`, `wig.fi`, `kgui.fi`, `shot.fi`,
   `tile.fi`, `wmplug.fi`).
2. Für `AX_OFF` einen **freien** Bereich aus `kernel/lib/kstate.fi`
   nehmen und ihn dort **vorher vergeben** — so, wie es die Seiten-Welle
   vom 18.09. (`8e772f44`, kdata auf 1408 KiB, zwölf Bereiche vorher
   vergeben) vormacht. Gegenprobe: `tools/kernel/memmap.py`.
3. Für die sechs Aufrufe **freie** Nummern nehmen (1960 und 1970 sind
   belegt, `SYS_OSUM_CODEC = 1970`) und sie **gleichzeitig** in
   `kernel/sys/sys.fi` **und** `lib/libc/kcall.fi` eintragen —
   `tools/posix/run.sh` Abschnitt 1 hält beide Tafeln nebeneinander,
   und genau diese Zeile ist in diesem Projekt schon **dreimal**
   vergessen worden (CPUSTAT, SHOT, KLOG).
4. `ax_flush()` gegen das **heutige** `wlib.fi` (10475 Zeilen) neu
   anschliessen, nicht gegen das von August.
5. Die drei Regressionen, die der Zweig damals selbst gefunden hat,
   als Tests übernehmen — besonders die zweite (hoher Kontrast gegen
   `/etc/theme`: `fg=0` auf `bg=0x1C2030` ergab **1,3:1**), weil sie
   sich mit dem heutigen Farbschema leicht wiederholt.
6. Falls eine neue Datei ausgeliefert wird (`/bin/axlesen`): Eintrag in
   `tools/usbimg/build.sh` **und** in die `PFLICHT`-Liste (Zeile 1051),
   mit der Gegenprobe — sonst wiederholt sich `nedit`/`bold.ttf`.

Sollwert der Runde, aus dem Zweig übernommen: `ax: selftest 9/9`,
Speicherkarte ohne Kollision, `k15` und `theme` grün.

---

## 6. `inventory` — vollständig erledigt

**Was er wollte.** 3 Commits, 27.08.: `THIRD_PARTY.md` (was in Osum
nicht selbst geschrieben ist), der Lizenzwechsel auf GPL-2.0-only für
Kern und Programme mit MIT für die Ring-3-Bibliotheken, und SPDX-Kopf­
zeilen — eine Zeile je Quelldatei, ausdrücklich als **separater** Commit
("SEPARATE COMMIT -- rebase this one on its own").

**Gilt es noch? Nein, restlos erledigt.** Auf `main` liegen:

* `THIRD_PARTY.md`, `LICENSE`, `LICENSE.MIT`, `LICENSING.md`,
  `LICENSE-UEBERSICHT.md`, `LICENSES/MIT.txt` **und** `.reuse/dep5`.
* **SPDX-Kopfzeilen in 1153 Dateien.** Von 1030 gezählten Quelldateien
  (`.fi`, `.py`, `.sh`, `.s`, `.c`) tragen **979** die Zeile in den
  ersten drei Zeilen.
* Die Zeile ist **byteweise dieselbe** wie auf dem Zweig — geprüft an
  `kernel/kmain.fi`: beide Seiten beginnen mit
  `// SPDX-License-Identifier: GPL-2.0-only`.

Die verbleibenden **51** Dateien ohne Kopfzeile (u. a.
`tools/check-ui.sh`, `tools/foreign/*.c`, `tools/english/*.py`,
`wasm-module/quelle/*.c`) hätte der Zweig **auch nicht** gelöst — für
alle vier Stichproben gilt: auf `inventory` steht dort ebenfalls keine
Zeile. Sie sind über `.reuse/dep5` per Pfad abgedeckt, was genau der
dort beschriebene Zweck der Datei ist.

**Setzt er auf?** Am schlechtesten von allen: **47 Konflikte, 19
`modify/delete`** — er fasst 221 Dateien an, und 19 davon sind
umgezogen. Der Rat des Auftrags, ihn zuletzt zu machen, war richtig; er
ist nur gegenstandslos geworden.

**Entscheidung: begraben.** Der Restposten sind die 51 Dateien, und der
ist mit `.reuse/dep5` beantwortet.

---

## 7. `haertung` — gilt noch, und ist der sauberste Kandidat

**Was er wollte.** 2 Commits, 30.08., nur 16 Dateien: W^X **für den
Kern selbst**, Wachseiten unter den Kernstapeln, Stapel-ASLR, IOMMU
gelesen. Dazu `tools/guard/run.sh` **55/0** und `tools/haertung/run.sh`
**37/0**.

Der zweite Commit ist bemerkenswert und spricht für die Runde: der
Läufer fand einen echten Rahmenverlust (129019 von 129020 Rahmen kamen
zurück), und behoben wurde die **Ursache**, nicht der Test —
`guard_under` löste eine 2-MiB-Kachel mitten im Lauf auf; jetzt
erledigt `presplit` das beim Start.

**Gilt es noch? JA.** Gemessen auf `main`:

```
grep guard_under|presplit   in kernel/ --include=*.fi   ->  0 Treffer
kernel/hard.fi                                          ->  nicht vorhanden
docs/HAERTUNG.md                                        ->  nicht vorhanden
```

Was **schon** da ist und von dieser Runde auch gar nicht beansprucht
wird: SMEP/SMAP stehen seit Runde K10 in
`kernel/arch/x86_64/guard.fi`, NX für Ring 3 seit K1, `proc.user_ok`
seit Runde 62. `docs/HAERTUNG.md` sagt das auf dem Zweig **selbst** und
korrigiert die Roadmap-Zeile A12 ausdrücklich — eine Runde, die zuerst
nachmisst, was schon da ist, bevor sie etwas behauptet.

Die eigentliche Lücke bleibt offen: die Identitätsabbildung des Kerns
wird aus 2-MiB-Kacheln mit den Bits `0x83` gebaut — *vorhanden |
schreibbar | grosse Seite*, **kein NX**. Jede Seite des Kerns ist damit
gleichzeitig schreibbar und ausführbar. SMEP hilft dagegen nicht, weil
keine dieser Seiten ein Benutzerbit hat. Das deckt sich mit den
Offenpunkten **R-024** und **R-025**.

**Setzt er auf?** **7 Konflikte, 0 `modify/delete`** — mit Abstand das
beste Ergebnis der sechs. Kein Umzug trifft ihn, weil er fast nur
`kernel/arch/x86_64/*` und die Ablaufsteuerung anfasst. Aber: die sieben
sind `smp.fi`, `trap.fi`, `kmain.fi`, `elf.fi`, `kstate.fi`, `proc.fi`,
`sched.fi` — also durchweg **Inhalts**konflikte im Kern, und `kmain.fi`
ist seit dem Abzweig von 5657 auf 7801 Zeilen gewachsen.

**Entscheidung: nicht blind mergen — portieren, Zweig als Vorlage.**
Er ist klein (16 Dateien, 2057 Zeilen), wertvoll und kollidiert an
keiner Namensgrenze. Eine eigene Runde **HAERTUNG-3** sollte
`kernel/hard.fi` nach `kernel/arch/x86_64/` oder `kernel/lib/` legen
(der Name `hard.fi` ist heute irreführend neben `guard.fi`), die sieben
Konfliktstellen einzeln von Hand nachziehen und die beiden Sollwerte
`tools/guard/run.sh` 55/0 und `tools/haertung/run.sh` 37/0 nachmessen.
`tools/haertung/run.sh` liegt bereits auf `main` (aus der späteren Runde
HAERTUNG-2, die etwas anderes misst — Vorsicht, gleicher Name).

---

## 8. Was aus dieser Sichtung folgt

**Für die Offenliste:**

* **S-007** (`a11y`): Beleg zeigte auf `/root/osum-a11y/STATUS-A11Y.md`
  — **dieses Verzeichnis gibt es nicht mehr**. Der Text liegt im Zweig
  selbst: `git show a11y:STATUS-A11Y.md` und `git show a11y:docs/A11Y.md`.
  Der Punkt bleibt offen und braucht eine Runde A11Y-2, keinen Merge.
* **A-012** ("Ungemergte Zweige"): sechs davon sind jetzt beantwortet —
  drei begraben (`certus`, `feedback`, `inventory`), drei als Vorlage
  aufgehoben (`a11y`, `haertung`, `demux`).
* Neu einzutragen wäre: die Behälterleser aus `demux` (MP4/MKV/SRT) als
  eigener Punkt neben **P-009**.

**Die Regel, die dieser Fall belegt.** Ein Zweig, der 900 Commits alt
ist, ist kein Zweig mehr, sondern eine Vorlage. Die Frage ist dann nicht
"lässt er sich mergen", sondern "gilt sein Inhalt noch, und was kostet
der Neubau". Bei vier von sechs war die Antwort: der Inhalt ist längst
auf anderem Weg gekommen. Das deckt sich mit der Erfahrung der letzten
Tage (P-001, P-002, P-005, S-002, `nedit`, `bold.ttf`, die deutsche
Oberfläche) — **bei diesem Projekt ist "ist längst erledigt" der
Normalfall, und danach zu prüfen ist billiger als zu mergen.**

---

## 9. Die Zweige bleiben stehen

Gelöscht wird keiner. Nachlesen:

```
git log --oneline main..<zweig>          die Commits der Runde
git show <zweig>:STATUS-<NAME>.md        der Zwischenstand mit den Zahlen
git show a11y:docs/A11Y.md               die Begründung des Baumes
git show haertung:docs/HAERTUNG.md       die Korrektur zu Roadmap A12
git diff --stat main...<zweig>           was er anfasst
```

---

## 10. Die Abnahmen an diesem Tag — gemessen, mit einer Warnung

`main` wurde **nicht verändert**: kein Merge, kein Commit am Quelltext.
Die Abnahmen liefen als Beleg, dass der Stand `0f7e047a` grün ist.

| Abnahme | Soll | gemessen | |
|---|---|---|---|
| `tools/check-ui.sh` | 196 Dateien, 0 Verstöße | **196 / 0, PASSED** | grün |
| `pruef/anim-ab.sh` | `anim=4` | **anim=4** (zweimal) | grün |
| `tools/clip2/run.sh` | 32/0 | **32 grün, 0 rot**, RC=0 | grün |
| `tools/hotplug/run.sh` | 45/0 | **45 passed, 0 failed**, RC=0 | grün |
| `tools/logind/run.sh` | 49/0 | **37/0** — siehe unten | Messfalle |
| `tools/install/abnahme.sh` | 35/0 | **34 grün, 1 rot** — siehe unten | Messfalle |

### Die Messfalle, und warum sie keine Regression ist

Auf dieser Maschine lief den ganzen Tag die Runde `glas` weiter
(`/tmp/osum-tsbuild-*`, QEMU im Dauerbetrieb). Die Lastmittel lagen
zwischen **6 und 10**. Beide roten Zeilen sind daran gebunden, und
beide sind **bekannte Punkte der Offenliste** — **A-008**
("Lastflakes verfälschen jeden Volllauf") und **A-010** ("nach vielen
Zyklen in EINER QEMU-Sitzung reagiert der Starter nicht mehr").

**`install` 34/1.** Die eine rote Zeile ist `[FEHL] kein Foto vom
Fenster` — ein Bildschirmfoto, nicht eine Zusage über das System. Alles
Inhaltliche daneben ist grün, bis hin zu *"das Fenster meldet 7
Bedienelemente"*, *"die Installation meldet sich fertig"*, *"der Kern
findet seine Wurzel auf der Platte"* und beiden Gegenproben.

**`logind` 37/0 statt 49/0.** Hier ist die Rechnung sauber aufgegangen:
Abschnitt 5 zählt die Zusagen von `pruef/abmelden.py` **einzeln** mit
(so steht es im Läufer, damit keine Sammelzeile entsteht). Dieses
Skript liefert 13 Zusagen; fällt es aus, fehlen zwölf:

```
37 − 1 (die verbliebene Sammelzeile) + 13 = 49
```

`UITRACE=1` war gesetzt und hat gewirkt — das Baulog sagt
`uitrace  AN`, und die Prüfung auf `/etc/uitrace` griff. Der Ausfall
stand in `.logind-mess/abmelden.log` und ist eine reine Tippflanke:

```
Versuch 3: nur 12 von 13 Tasten angekommen -- Feld leeren und neu
FAIL  die Anmeldung hat nicht geklappt
glogin: angemeldet als  w=justin16
```

`justin16` ist `justin` + `16`: zwei Tastendrücke sind unter Last
verschmolzen. Nachgefahren bei Lastmittel 5,2 meldete dasselbe Skript
dann **`OK angemeldet als justin, der Schreibtisch läuft unter
uid=1000`** und kam auf 10/3 — die Abmeldekette selbst ist intakt
(Sitzung beendet, 1 SIGKILL, Anmeldeschirm wieder aufgebaut, *"nach dem
Abmelden ist niemand angemeldet"*); die drei roten sind Zeit- und
Bildvergleiche.

**Eigener Fehler, benannt:** `install` und `clip2` habe ich zuerst
**gleichzeitig** gestartet. Beide bauen im **selben** Arbeitsbaum, und
`clip2` schaltet für seine Gegenprobe `wlib.drop_an(true)` auf `false`.
Der erste `clip2`-Lauf mass deshalb **22/10**. Allein nachgefahren:
**32/0**. Die Regel aus A-008 gilt also auch für *zwei* Läufer im
selben Baum — nicht nur für Last.

