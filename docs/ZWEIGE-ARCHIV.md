# Zweige-Archiv — was abgeschrieben ist, und warum

**Stand 22.09.2026.** Baum `/root/fb-osum`, `main` bei der
Sammelrunde MODULE + DREI.

Dieses Blatt ist die **eine Stelle**, an der steht, welche Zweige
erledigt sind. Es fasst die beiden früheren Sichtungen zusammen und
schreibt sie fort:

* `docs/ALTZWEIGE-AUGUST.md` (Commit `fe475d47`) — die sechs
  Augustzweige, einzeln begründet.
* `docs/GROSSZWEIGE-SEPTEMBER.md` (Commit `c9d9e534`) — die neun
  großen Septemberzweige.

**Kein Zweig wird gelöscht.** Wer eine Zahl aus einer dieser Runden
nachlesen will, findet sie weiter im Baum. Was sich ändert: jeder
abgeschriebene Zweig trägt jetzt ein **leeres Merkzeichen**
`archiv/<name>`, und `git branch --list 'archiv/*'` zeigt auf einen
Blick, was Karteileiche ist.

---

## 0. Die kurze Antwort

| Zweig | Commits | Konflikte gegen `main` (22.09.) | Urteil |
|---|---:|---:|---|
| `certus` | 12 | **26** (1 modify/delete) | abgeschrieben — von `certus2` ersetzt |
| `demux` | 11 | **10** (2 modify/delete) | abgeschrieben — Ton+MP3 sind auf `main` |
| `feedback` | 8 | **10** (3 modify/delete) | abgeschrieben — `/bin/snip` ist auf `main` |
| `a11y` | 5 | **13** (3 modify/delete) | **gilt fachlich, aber NEUBAU** — siehe 2. |
| `inventory` | 3 | **47** (19 modify/delete) | abgeschrieben — vollständig auf `main` |
| `haertung` | 2 | **7** (0 modify/delete) | gilt fachlich, **Portierung nötig** |
| `blur-gemergt-c0cda62c` | 4 | — | **Name ist falsch**, siehe 3. |
| `blur-und-logind-und-d016` | 4 | — | **gemergt am 22.09.**, siehe 3. |

Die Konfliktzahlen sind an diesem Tag **neu gemessen**, nicht aus den
alten Blättern übernommen: für jeden Zweig ein echter
`git merge --no-commit --no-ff` gegen `fc3fb8cc` in einem
Wegwerf-Arbeitsbaum, gezählt mit
`git diff --name-only --diff-filter=U`.

---

## 1. Der gemeinsame Grund, zum dritten Mal derselbe

Alle sechs Altzweige zweigten zwischen **27. und 30. August** ab.
Dazwischen liegt die Runde **O-STRUKTUR** (17.09., `docs/STRUKTUR.md`):
**120 Kerndateien sind umgezogen**, alle als echte Umbenennung.

    kernel/wm.fi      → kernel/ui/wm.fi
    kernel/kstate.fi  → kernel/lib/kstate.fi
    kernel/sys.fi     → kernel/sys/sys.fi
    kernel/kbd.fi     → kernel/drv/hid/kbd.fi

Die Zweige vom August kennen diese Ordnung nicht. Deshalb steht in der
Tabelle oben neben der Konfliktzahl die Zahl der
**modify/delete**-Konflikte: das sind die Fälle, in denen der Zweig
eine Datei ändert, die auf `main` **gar nicht mehr existiert**. Ein
unachtsamer Merge legt dann `kernel/wm.fi` **neben**
`kernel/ui/wm.fi` — zwei Fensterserver im selben Baum, von denen der
gebaute der falsche ist.

### Die Gefahr, die `git` NICHT meldet

Bei `certus` sind so schon einmal fast fünf Errungenschaften
verschwunden. Der Grund ist, dass ein Merge auch **ohne** Konflikt
Zeilen löschen kann, wenn eine Seite eine Datei in einem Zustand
trägt, der älter ist als die Arbeit auf `main`.

Deshalb wird bei jedem Merge in diesem Repo **vorher gezählt**:

| Zähler | `main` | wofür er steht |
|---|---:|---|
| `grep -c anim kernel/ui/wm.fi` | **43** | die Fensteranimationen |
| `grep -c zug_ kernel/user/wlib.fi` | **13** | Justins Zieh-Aufhebung |
| `grep -c blur kernel/ui/wm.fi` | **65** | der Weichzeichner |

Für `a11y` sieht das so aus — und das ist der Grund, warum er trotz
gültiger Sache nicht gemergt wird:

    a11y  kernel/wm.fi         anim = 0     (main: 43)
    a11y  kernel/user/wlib.fi  zug_ = 0     (main: 13)

Ein Merge dieses Zweigs würde die Animationen **und** die
Zieh-Aufhebung stillschweigend mitnehmen.

---

## 2. `a11y` — der einzige, der noch etwas bringt

Der Auftrag verlangte, ihn vor dem Begraben nochmal anzusehen, weil
sein Commit-Text behauptet, `k15` und `theme` seien grün gewesen
(`70350eec`, 28.08.: „0 von 964 Kantenpunkten falsch", `tests/theme`
0 Fehler). Das stimmt — **für den Baum von damals**.

**Was er bringt, und was `main` davon nicht hat:**

| | `main` | `a11y` |
|---|---:|---:|
| `tools/a11y/run.sh` | fehlt | 566 Zeilen |
| `tools/a11y/felder.py`, `lupe.py`, `kontrast.py`, `schnitt.py`, `spur.py`, `ppm.py` | fehlen | da |
| `a11y`/`axnode` in `wlib.fi` | **0** | **25** |

Das ist ein **Barrierefreiheitsbaum**, und er wäre nicht nur für S-007
wertvoll, sondern auch **fürs automatische Messen der Oberfläche**:
ein Läufer, der Bedienelemente benennen kann, muss sie nicht mehr aus
Bildpunkten raten.

**Warum trotzdem kein Merge:** 13 Konfliktdateien, darunter
`kernel/wm.fi` als modify/delete, und die Nullzähler oben. Die Sache
gilt, der Baum darunter nicht mehr.

**Wie ein Neubau aussähe** (damit niemand bei null anfängt): die sechs
Skripte unter `tools/a11y/` sind **eigenständig** und hängen nicht an
der Kernstruktur — die lassen sich einzeln herübernehmen. Der Teil in
`wlib.fi`/`wlibc.fi` muss gegen den heutigen Stand neu geschrieben
werden; der Zweig zeigt, **welche** Stellen anzufassen sind, nicht
mehr wie.

---

## 3. Die zwei Blur-Zweige — ein Commit, zwei Namen

`blur-gemergt-c0cda62c` und `blur-und-logind-und-d016` zeigen **beide
auf denselben Commit** `47c590ac`.

* `c0cda62c` **ist** auf `main` (der Merge der Runde BLUR).
* Die **vier Commits darüber** waren es am 21.09. nicht — der Name
  `blur-gemergt-…` war also irreführend: gemergt war der Sockel, nicht
  der Nachlauf.
* Am **22.09.** ist dieser Nachlauf gemergt worden (logind-Läufer,
  Papierkorb-Befund, Blur-Nachmessung).

Beide Namen sind damit erledigt und bekommen ihr Merkzeichen. Wer so
etwas wieder anlegt: **einen Zweig nicht nach seinem vermuteten
Zustand benennen.** Der Name veraltet, der Commit nicht.

---

## 4. Die vier klar überholten

* **`certus` (12)** — Certus-Browser auf Osum. Von `certus2` (05.09.)
  ersetzt. Sein eigener letzter Commit protokolliert einen Unfall: ein
  `git add -A` einer *anderen* Runde hat in den ausgecheckten Zweig
  hineingeschrieben, weil zwei Runden dasselbe Arbeitsverzeichnis
  benutzten. 26 Konfliktdateien.

* **`demux` (11)** — MP4/MKV/MP3. Ton und MP3 sind auf `main`
  (`audio.fi` 2075 Zeilen gegen 789, dazu `hda.fi` und `mix.fi`);
  `docs/AUDIO.md` sagt selbst, es löse MEDIA1 ab. Die **Behälter**
  (Demultiplexer) fehlen weiter — das ist der Rest, der gälte, und er
  ist als Neubau kleiner als der Merge.

* **`feedback` (8)** — Bildschirmfoto + Rückmeldung. `/bin/snip` aus
  der Runde ALLTAG und `ui/shot.fi` sind auf `main`.

* **`inventory` (3)** — SPDX-Kopfzeilen und Lizenzsplit. Vollständig
  auf `main`. Mit **47** Konfliktdateien (19 davon modify/delete) der
  roteste der Sechs, weil er jede Quelldatei in der Kopfzeile anfasst
  und 120 davon inzwischen woanders liegen.

## 5. Der eine, der gilt und portiert werden muss

* **`haertung` (2)** — W^X im Kern, Wachseiten, ASLR. Fachlich
  unverändert gültig und der **sauberste** der Sechs: 7 Konfliktdateien,
  **kein** modify/delete. Trotzdem kein Merge — der Zweig setzt auf
  Seitentabellen auf, die seit O-STRUKTUR woanders stehen. Er ist der
  beste Kandidat für eine eigene kurze Runde.

---

## 6. Die Regel, damit dieses Blatt nicht ein viertes Mal nötig wird

1. Ein Zweig, der **abgeschrieben** ist, bekommt sofort das Merkzeichen
   `archiv/<name>` und eine Zeile in diesem Blatt.
2. Ein Zweig, der **älter als vier Wochen** ist und mehr als fünf
   Konfliktdateien gegen `main` hat, ist **kein Merge-Kandidat mehr**,
   sondern eine Vorlage für einen Neubau. Das ist keine Meinung: es ist
   dreimal gemessen worden (August, September, jetzt).
3. Vor jedem Merge in `wm.fi`, `wlib.fi`, `desktop.fi`, `taskbar.fi`
   die drei Zähler aus Abschnitt 1 **beidseitig** vergleichen. Git
   meldet dort gern 0 Konflikte und löscht trotzdem etwas aus.
4. Einen Zweig **nicht nach seinem Zustand benennen** (siehe 3.).
