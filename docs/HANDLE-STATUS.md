# Runde HANDLE — die Lebensdauer, bevor es Asynchronitaet gibt

Zweig `handle`, Arbeitsbaum `/root/osum-handle`, Abzweig von `mergeline` (2bdd362).
Gemessen am 29.08.2026 auf AMD EPYC 7571, 12 Kerne, QEMU mit `-accel kvm`,
TSC 2,2020 GHz.

## Warum diese Runde vor dem Ring kommt

Google hat 2023 berichtet, dass rund **60 % der eingereichten
Linux-Kernel-Exploits aus io_uring** stammten, und hat den Ring auf Android und
ChromeOS abgeschaltet. Die Ursache war nicht der geteilte Speicher und nicht die
Ringform — es war die **asynchrone Lebensdauer**: ein Auftrag lebt laenger als
der Aufruf, der ihn eingereicht hat; das Programm schliesst inzwischen sein
Handle, der Platz wird neu vergeben, und der alte Auftrag greift auf das neue
Objekt zu.

Das ist nachtraeglich nicht zu reparieren. Also wird es hier **vorher** gebaut
und **vorher** gemessen. Der Ring selbst (Runde RING) ist NICHT Teil dieser
Runde.

## Was gebaut wurde

| Datei | Zeilen | was |
|---|---:|---|
| `kernel/handle.fi` | 1110 | neu: Objekttafel mit Verweiszaehler, Handle-Plaetze je Prozess, Auftrags-/Abbruchtafel |
| `kernel/file.fi` | +230 | der Deskriptor ist ein Handle; `fd_check`, `fd_pass`, `open_settle` |
| `kernel/sys.fi` | +250 | Rechtepruefung im Lese-/Schreib-/Suchpfad, die elf Aufrufe ab 2200 |
| `kernel/uprog.fi` | +330 | `u_handle` (35 Zusagen aus Ring 3), `u_hbench` |
| `kernel/kmain.fi` | +290 | die Runde, die zwei kernelseitigen Messungen, der Mikrobenchmark |
| `kernel/kstate.fi` | +75 | fuenf Bereiche in `kdata`, sechs Modusbits, zehn Zaehler |
| `kernel/proc.fi` | +8 | leere Handle-Tafel vor den Deskriptoren |
| `tools/handle/run.sh` | 367 | neu: der Testlaeufer, 80 Zusagen |

Zusammen rund **2660 Zeilen**, davon 1110 neues Kernmodul.

### Drei Tafeln, drei Fragen

1. **Handle-Plaetze je Aufgabe** — „darf DIESER Prozess DIESES Objekt, und wie?"
   Platz + Generation + Wuerfelwert aus der pid, dazu ein Rechte-Bitfeld aus
   dreizehn Bits (die zehn von `cap.fi`/OrientOS plus `R_APPEND`, `R_SEEK`,
   `R_IOCTL`).
2. **Objekttafel** — „lebt das Ding noch?" Genau EIN Eintrag je Kernobjekt, mit
   Verweiszaehler, Zahl der Auftraege in Flug und eigener Generation.
3. **Auftragstafel** — „laeuft das noch, und meint es noch dasselbe?" Ein
   Auftrag merkt sich, mit WELCHEM Handle er eingereicht wurde. Das
   Abbruch-Token ist Platz + eigene Generation.

`kernel/cap.fi` (die native ABI aus OrientOS) bleibt unveraendert; ihre
Rechtebits bedeuten hier dasselbe wie dort.

## Die Zahlen

### Abnahme

| Abschnitt | vorher (mergeline) | nachher (handle) |
|---|---|---|
| `tools/kernel/run.sh` | 176 / 0 | 176 / 0 |
| `tools/osum/run.sh` | 130 / 0 | 130 / 0 |
| `tools/posix/run.sh` | 134 / 0 | 134 / 0 |
| `tools/unix/run.sh` | 107 / 0 | 107 / 0 |
| `tools/caps/run.sh` | 67 / 0 | 67 / 0 |
| `tools/k13/run.sh` (uid/gid) | — | 99 / 0 |
| `tools/k14/run.sh` (VFS) | 151 / 1 | 151 / 1 |
| `tools/userland/run.sh` | — | 91 / 0 |
| `tools/k16/run.sh` (Selbstbau) | 58 / 6 | 58 / 6 |
| `tools/handle/run.sh` | — | **80 / 0** (neu, beide Uebersetzer) |

Zusammen **1093 bestandene Zusagen**, davon 80 neue.

**Die sieben roten sind ALT und stehen genauso auf `mergeline`.** Das ist nicht
behauptet, sondern nachgemessen: `tools/k14/run.sh` und `tools/k16/run.sh` sind
auf dem Vorher-Stand gelaufen, und die Fehlerzeilen sind Zeile fuer Zeile
dieselben (`diff` ueber die `FAIL`-Zeilen: identisch). K14: „und die Wurzelplatte
danach, Oktett fuer Oktett". K16: `fas` findet `_F1.u_start` nicht, bindet 100
statt 107 Programme, und die vier Folgezusagen daran.

`tools/userland/run.sh` ist der Abschnitt, an dem diese Runde am ehesten haette
scheitern muessen: eine Shell, fuenfundzwanzig Werkzeuge, Roehren und Umlenkung,
alles ueber Deskriptoren, die seit dieser Runde Handles sind. 91 / 0.

### Kosten, gemessen

Median aus 33 Bloecken zu 512 (Ring 0) bzw. 256 (Ring 3) Aufrufen, davon
wiederum der Median aus neun Kernellaeufen. Beide Staende tragen denselben
Benchmark; der Vorher-Stand ist `mergeline` plus ausschliesslich den
Messfunktionen.

| Messung | vorher | nachher | Delta |
|---|---:|---:|---:|
| `file.fd_of` (Ring 0, die Funktion selbst) | 20 Zyklen | 135 Zyklen | +115 |
| `getpid` aus Ring 3 (kein Deskriptor — der Massstab) | 342 Zyklen | 342 Zyklen | ±0 |
| `lseek` aus Ring 3 (durch die ganze Schicht) | 388 Zyklen | 506 Zyklen | **+118 (+30,4 %)** |

+118 Zyklen sind bei 2,2020 GHz **+53,6 ns** je Systemaufruf, der einen
Deskriptor anfasst. Systemaufrufe ohne Deskriptor (`getpid`) sind unveraendert —
das ist die Gegenprobe, dass die Messung den richtigen Pfad trifft.

**Der Waechter der Messung.** `bench-fdok` steht mit in der Ausgabe: es ist der
Eintrag, den `fd_of` liefert, und es MUSS 1 sein. Der erste Anlauf dieser Messung
hat 19 gegen 21 Zyklen ergeben — und beide Male lief die Aufloesung gar nicht,
weil der Bootprozess keine Deskriptoren hat und `fd_of` sofort ausstieg.

### Was die 118 Zyklen wirklich sind

Fuenf Fassungen, jede gemessen:

| Fassung | `file.fd_of` |
|---|---:|
| ohne Handle-Schicht | 20 |
| 1. sauber aus Hilfsfunktionen zusammengesetzt, `kstate.add` (`lock xadd`) als Zaehler | 155 |
| 2. Hilfsaufrufe ausgeschrieben, Zaehler nur im Selbsttest, Moduswort einmal | 129 |
| 3. zusaetzlich ohne `kstate.get`, Adressen am Aufrufort gerechnet | **212** |
| 4. eine Aufloesung je Systemaufruf statt zwei, Moduswort nur im Nein-Pfad | 166 |
| 5. dieselbe Form, Lesungen wieder ueber `kstate.get` | **135** |

**Dass Fassung 3 langsamer war als Fassung 2, ist der eigentliche Befund dieser
Runde:** firnc0 macht keine Registerzuteilung. Jeder Zwischenwert wird auf den
Stapel geschrieben und wieder gelesen; jede Funktion oeffnet einen Rahmen von
128 Oktett, ob gebraucht oder nicht. Fassung 3 hatte 575 Maschinenbefehle fuer
fuenfzehn Zeilen Quelltext. Es gilt hier also nicht „weniger Aufrufe ist
schneller", sondern **weniger Ausdruecke ist schneller** — und `kstate.get(state,
off)` ist billiger als dieselbe Lesung an Ort und Stelle, weil nicht die Lesung
kostet, sondern die Adressrechnung davor.

Die Handle-Schicht liest im Erfolgsfall **acht** Worte (Deskriptorplatz,
Objektverweis, Objektart, Objektgeneration, Platzgeneration, Wuerfelwert, Rechte,
Objektnummer) und vergleicht ~zehnmal. Mit einem Uebersetzer mit
Registerzuteilung waeren das geschaetzt 25–40 Zyklen statt 135. **Der Aufschlag
ist ueberwiegend eine Eigenschaft von Firn Stufe 0, nicht des Entwurfs.** Das
gehoert in die Firn-Roadmap und nicht in die Kernel-Roadmap.

Zwei Dinge, die im Regelbetrieb ABSICHTLICH nicht mehr passieren:
* **Der Zaehler `H_CHECKS` laeuft im heissen Pfad nicht mit.** `kstate.add` ist
  ein `lock xadd`, und das war der teuerste Einzelposten (Fassung 1 → 2).
* **Das Moduswort wird im Erfolgsfall nicht gelesen.** Die Gegenproben koennen
  einen Zugriff nie zusaetzlich verbieten, also wird erst gefragt, wenn die
  strenge Pruefung schon Nein gesagt hat.

## Die Sicherheitszusagen und ihre Gegenproben

35 Zusagen meldet ein unprivilegiertes Programm aus Ring 3 (`uprog.u_handle`,
gearbeitet wird auf einer Roehre — die hat zwei Enden mit UNGLEICHEN Rechten und
einen echten Verweiszaehler). Jede wird im Laeufer einzeln nachgelesen.

| # | Szenario | Zusage | Gegenprobe |
|---|---|---|---|
| a | Rechte-Eskalation beim Weitergeben | `keine-eskalation`: ALLE Rechte verlangt, keines dazubekommen | `norights` → `kopie-darf-nicht` faellt |
| b | Use-after-close mit Generationszaehler | `veraltet` (-E_STALE) **und** `nicht-das-neue-ding` | `nogen` → beide fallen, der alte Auftrag trifft wirklich das neue Objekt |
| b | kein Free waehrend in Flug | `kein-free-in-flug`: Schliessen gibt nicht frei | `noflight` → faellt |
| c | doppeltes close | `close-zweimal` gibt -EBADF | — |
| d | fremdes Handle | kernelseitig: zwei Prozesse, derselbe Platz, `differ=1 cross=1` | — |
| e | Abbruch mitten im Auftrag | `abbruch-raeumt-nicht`, `ende-raeumt-noch-nicht`, `close-raeumt-ab` | — |

Dazu die **Leckzahlen**: nach dem Lauf ist `angelegt == abgeraeumt` und kein
Auftrag mehr in Flug. Und die kernelseitige Uebergabe:
`pass=1 shrink=1 notransfer=1 refs=2` — sie gelingt, sie SCHNEIDET die Rechte,
ohne `R_TRANSFER` geht sie nicht, und das Objekt haelt danach zwei Verweise.

Dass die Schicht im heissen Pfad ueberhaupt gefragt wird, beweisen die
Gegenproben staerker als ein Zaehler es koennte: wuerde sie nicht gefragt,
koennte das Umlegen von `nogen`/`norights` das Ergebnis nicht aendern.

## Zwei Fehler, die die Runde selbst gemacht hat

Beide stehen im Quelltext an ihrer Stelle, weil sie wiederkommen koennen:

1. **Handle-Werte sahen aus wie Fehlercodes.** In die Generation geht der
   Wuerfelwert der Tafel ein, und der ist ein Hashwert — bei etwa der Haelfte
   aller Prozesse haette er Bit 31 gesetzt. Handle und Fehler kommen durch
   DENSELBEN Kanal zurueck (`>= 0` Ergebnis, `< 0` Fehler). Gemessen:
   `hb=0x9ed0744400000001`, und jedes `is_err(hb)` sagte ja. Behoben: die
   Generation ist **31 Bit** breit (`GEN_MASK`). Kosten: 2^31 statt 2^32
   Wiederverwendungen je Platz. `kernel/cap.fi` hat dieselbe Eigenschaft noch;
   ihr Test toleriert sie, aber es ist eine offene Kante.
2. **`kstate.add` kann nicht dekrementieren.** Es rechnet
   `__atomic_add(...) + v`, und dieses `+` ist seit Runde 72 geprueft: mit
   `v = 0 -% 1` laeuft die Addition des alten Wertes ueber und der Kernel
   panickt — mitten im Ring-3-Test. `H_INFLIGHT` zaehlt deshalb die BEGONNENEN
   Auftraege und faellt nie; wie viele laufen, sagt `req_live` durch Nachsehen.

Und ein Fehler im Testlaeufer, der wie ein Kernelfehler aussah: `kernel.ld`
sammelt den Ring-3-Code mit dem Muster `*uprog*.o(.text .text.*)` in den einzigen
Abschnitt mit gesetztem User-Bit. Die Objektdatei hiess `u0.o` — also landete
`uprog.fi` im Kerneltext, der Kernel bootete sauber durch, meldete „exit 21", und
keine einzige Zusage kam. Der Laeufer prueft jetzt die Groesse von `.utext`.

## Was noch offen ist

* **Der strenge Modus ist ein Schalter (`hstrict`), keine Umstellung.** Er stellt
  die Vererbung von einem Prozess an sein Kind ab (`elf.spawn` →
  `file.inherit_std`); gemessen: mit dem Schalter schreibt `ls` kein Wort mehr,
  die Shell laeuft weiter. Er erwischt NICHT die erste Shell: die startet aus dem
  Bootprozess, der selbst keine Deskriptoren hat, also ruft `elf.spawn`
  `inherit_std` fuer sie gar nicht — ihre drei kommen aus `file.init_task` in
  `proc.create_bare`. Wer wirklich „nichts ausser explizit uebergeben" will, muss
  auch `init_task` leeren und dem Init-Prozess seine Deskriptoren ausdruecklich
  geben. Das ist eine eigene Runde.
* **Nicht jeder Systemaufruf prueft schon ein Recht.** `read`, `write` und
  `lseek` tun es (`R_READ`, `R_WRITE`, `R_SEEK`). `stat`, `ioctl`, `mmap` und die
  Socket-Aufrufe loesen ueber `fd_of` auf — also durch die Schicht, mit
  Generation und Existenzpruefung —, verlangen aber noch kein eigenes Bit.
  `R_APPEND` und `R_IOCTL` sind vergeben und noch nirgends verlangt.
* **`MAX_H` ist 16 je Prozess**, dieselbe Zahl wie `file.MAX_FD`. Fuer den Ring
  wird das zu klein; die Tafel liegt in den letzten freien fuenf Seiten von
  `kdata` (0x7B000–0x80000, davon 16,25 KiB belegt). Mehr braucht ein groesseres
  `KDATA_SIZE`.
* **Der Aufschlag von 118 Zyklen** ist ueberwiegend Uebersetzer und nicht
  Entwurf. Eine Registerzuteilung in firnc waere hier der groesste Hebel.
* **`cap.fi` und `handle.fi` sind zwei Handle-Tafeln nebeneinander.** Das ist
  bewusst so (zwei ABIs, zwei Listen), aber der Ring sollte auf `handle.fi`
  aufsetzen, und irgendwann sollte `cap.fi` darauf abgebildet werden.

## Kann Runde RING darauf aufsetzen?

**Ja.** Die drei Dinge, die der Ring braucht und die nachtraeglich nicht
einbaubar gewesen waeren, stehen und sind gemessen:

1. Ein Auftrag haelt sein Objekt fest (`OB_FLIGHT`), und ein `close` waehrend des
   Auftrags gibt nicht frei, sondern verschiebt die Freigabe auf `req_end` →
   `file.open_settle`. Gemessen: `deferred >= 1` im Selbstlauf, und die
   Gegenprobe `noflight` laesst den Test fallen.
2. Ein Auftrag, dessen Handle geschlossen und dessen Platz neu vergeben wurde,
   bekommt `-E_STALE` und **nicht** das neue Objekt. Genau die io_uring-Fehler-
   klasse, und sie ist als Testfall nachgestellt.
3. Ein Abbruch-Token existiert von Anfang an, es markiert nur, und abgeraeumt
   wird von dem, der zuletzt geht.

Was der Ring zusaetzlich braucht und was diese Runde NICHT liefert: die
Warteschlangen im geteilten Speicher, die Speicherbarrieren, den Rueckstau bei
Ueberlauf — und, wenn er viele Auftraege gleichzeitig tragen soll, eine groessere
Auftragstafel als die heutigen 64 Plaetze.
