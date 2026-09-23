# Runde ROADMAP-2 (23.09.2026)

Auftrag: die Roadmap weiter abarbeiten, Schwerpunkt `K-` und `A-`.
`O-004` war gesperrt und ist unberuehrt geblieben.

**62 -> 60 Arbeitspunkte.** Vier abgegangen, zwei neue echte Punkte
gefunden, bei zwei weiteren die Zahl richtiggestellt.

## Was gemessen wurde, und was dabei herauskam

| Punkt | Ausgang | Beleg |
|---|---|---|
| `A-005` | erledigt | `tools/ahci/run.sh` **58/4 -> 62/0** |
| `K-003` | war schon fertig | AML-Interpreter 4215 Z., aus `kmain.fi` gerufen |
| `K-005` | war schon fertig | `tools/k18/run.sh` **170/0** |
| `A-022` | erledigt (neu gefunden) | `tools/multicore/run.sh` **30/10 -> 37/3** |
| `A-006` | Befund korrigiert | `glyphe` **26/3 -> 28/1**, `vielkern` 30/10 -> 37/3 |
| `A-003` | gilt weiter, groesser | `tools/k15/run.sh` **214/38**, nicht "20 Fehler" |
| `A-023` | neu, offen | ein frischer Arbeitsbaum kann gar nicht bauen |
| `A-024` | neu, offen | zwei Runden teilen sich `/tmp/abnahme` |

## Der rote Faden: vier von fuenf roten Laeufern hatten denselben Grund

Nicht der Code war kaputt, sondern die MESSUNG -- und zwar dreimal aus
derselben Wurzel wie `F-003`: **ein Laeufer sucht einen Namen, den eine
fruehere Runde umbenannt hat.**

1. `A-022`: `grep '^tafel: 23 SICHER'`, aber der Kern schreibt seit
   Runde ENGLISCH `23 SAFETY` (`kernel/ui/kgui.fi:6792`). Sieben
   Zusagen meldeten "keine Zahl gefunden".
2. `A-006`: `grep 'irq_aus()'`, aber die Funktion heisst seit
   `d3b925ba` `irq_ack`. Die Zusage war inhaltlich IMMER erfuellt.
3. `A-005`: keine Umbenennung, aber dieselbe Sorte Fehler eine Ebene
   tiefer -- eine Zeitschranke, die in RUNDEN zaehlt und gegen die
   Kosten eines VM-Austritts unter KVM geeicht ist, misst unter TCG
   etwas ganz anderes.
4. `A-024`: zwei Runden schrieben gleichzeitig nach `/tmp/abnahme`.

**Die Gegenmassnahme ist jedes Mal dieselbe:** nicht den Namen
nachziehen, sondern auf etwas messen, das sich nicht aendert -- die
ZEILENNUMMER statt des uebersetzbaren Wortes, das PAAR aus Abschalten
und Wiederherstellen statt eines Funktionsnamens, eine UHR statt einer
Rundenzahl. Genau die Bauart von `A-004`/`A-021`.

## Zwei Fallen fuer die naechste Runde

### A-023: ein frischer Arbeitsbaum baut nicht

`vendor/firn/{bin,lib}` ist nicht eingecheckt und liegt je Arbeitsbaum
einzeln. In einem neuen `git worktree` fehlt es; `fetch-firnc.sh` will
dann den Pin `7b4c22b1` bauen, und **dieser Commit existiert in
`/root/firn` nicht mehr** (dort `f61c2904`; die alte Historie liegt
laut `vendor/firn/HERKUNFT.md` nur noch im privaten Archiv `FirnOld`).

Jeder Laeufer meldet dann "der Kern baut nicht" -- was nach einem
kaputten Baum aussieht und keiner ist. Das hat diese Runde drei
falsch-rote Laeufe gekostet.

    cp -a /root/fb-osum/vendor/firn/{bin,lib,.gebaut} <baum>/vendor/firn/

13,5 MB, danach sagt `fetch-firnc.sh` "firnc ist aktuell".

### A-024: `/tmp/abnahme` gehoert allen

`tools/install/abnahme.sh` legt seine Zielplatte unter
`OUT=${1:-/tmp/abnahme}` ab -- ohne Argument also immer am selben Ort.
Liefen zwei Runden gleichzeitig, misst die zweite Truemmer: **16/17
statt 35/0**, mit Folgefehlern bis in `O-009` hinein, und KEINER davon
echt. Mit eigenem Ziel gemessen: **35/0**.

    bash tools/install/abnahme.sh /tmp/<eigener-pfad>

## Abnahmen nach der Kernaenderung

Alle Pflichtwerte gehalten:

    tools/install/abnahme.sh   35/0
    tools/hotplug/run.sh       45/0
    tools/clip2/run.sh         32/0
    tools/check-ui.sh          PASSED
    pruef/anim-ab.sh           anim=4
