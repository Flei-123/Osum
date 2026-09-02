<!-- SPDX-License-Identifier: GPL-2.0-only -->
# `kernel/drivers/` — die Treiber

Alles, was hier liegt, **redet mit einem Gerät**: Register, Portadressen,
Ringe, Unterbrechungen. Alles andere gehört nach `kernel/`.

Die ausführliche Anleitung — *einen neuen Treiber hinzufügen, in
konkreten Schritten* — steht in **[`docs/TREIBER.md`](../../docs/TREIBER.md)**.
Diese Datei ist nur die Karte.

```
bus/    pci.fi acpi.fi          der Bus. Hier entsteht jede Treiberwahl.
net/    netdev.fi               SCHNITTSTELLE: PCI-Nummer -> Treiber
        virtio.fi e1000.fi      je Chip eine Datei
blk/    blk.fi                  SCHNITTSTELLE: Gerätenummer -> Treiber
        nvme.fi ahci.fi         je Chip eine Datei
usb/    usb.fi                  SCHNITTSTELLE: der Kern über dem Regler
        xhci.fi                 je Regler eine Datei
input/  kbd.fi ps2m.fi          Tastatur, Zeigegerät (noch ohne Naht)
gfx/    gfx.fi                  SCHNITTSTELLE (die Naht zur Grafik)
        gfx-aus.fi              ihre Leerfassung für `--gui off`
        fb.fi vmode.fi font.fi  Rahmenpuffer und Bildmodi
snd/    (leer)                  siehe docs/TREIBER.md, Abschnitt 6
```

## Die drei Regeln

1. **Der Kern nennt keinen Treiber beim Namen.** Er ruft `netdev.…`,
   `blk.…`, `gfx.…` — die Schnittstellendatei der Klasse. Welcher Chip
   dahinter steckt, entscheidet die Tabelle in dieser Datei, nicht der
   Aufrufer. (`gfx.fi` ist das sauberste Beispiel: sie hat eine
   vollständige Leerfassung, mit der Osum ohne eine Zeile Grafik baut.)

2. **Je Chip eine Datei, mit einheitlichen Namen.** Alle Netztreiber
   liefern `init_on`, `tx_frame_on`, `rx_take_on`, `link_up_on` …; alle
   Blocktreiber `read_block`, `write_block`, `blocks`, `present`. Wer
   einen Namen anders schreibt, zwingt die Schnittstelle zu einem
   Sonderfall — und Sonderfälle sind der Anfang von `if chip == …`.

3. **Rechne einen Unterbrechungsvektor nicht aus, vergib ihn.**
   `netdev.vec_of(c)` ist die einzige Stelle, die weiß, welche Karte auf
   welchem Vektor meldet. Warum das eine Regel ist und keine
   Geschmacksfrage, steht in `docs/TREIBER.md` — es hat eine Netzkarte
   und eine Maus auf denselben Vektor gelegt, und niemand hat es
   gemerkt.

## Was `import` angeht

Der Übersetzer sucht ein `import` **(1) neben der importierenden Datei,
(2) neben `kernel/kmain.fi`**. Deshalb:

* `import kstate` funktioniert aus jedem Treiber unverändert;
* Treiber derselben Klasse erreichen einander mit dem nackten Namen
  (`netdev.fi` schreibt `import virtio`);
* von außerhalb braucht es den Pfad: `import drivers.net.netdev` — und
  der Aufruf heißt danach trotzdem weiter `netdev.probe(state)`, weil
  ein Modul unter dem *letzten* Pfadteil angesprochen wird.

**Dateinamen müssen im ganzen Kernbaum eindeutig bleiben.** Der
Modulname ist der Dateiname; zwei Dateien `net.fi` in verschiedenen
Verzeichnissen ergäben doppelte Symbole.

## Nach jeder Änderung

```sh
./tools/struktur/run.sh                            # halten die drei Regeln noch? (~1 s ohne Gegenprobe)
./tools/build-kernel.sh /tmp/k.bin                 # baut es?
./tools/build-kernel.sh /tmp/k-off.bin --gui off   # auch ohne Grafik?
python3 tools/kernel/memmap.py                     # Speicher- und Vektorkollisionen
```

`tools/struktur/run.sh` ist die maschinelle Fassung dieser Seite: die
drei Regeln oben sind dort 20 geprüfte Zusagen, und sie läuft als
Abschnitt 34 in `./test.sh` mit. Sie meldet unter anderem, wenn eine
Datei wieder flach unter `kernel/` liegt, wenn ein Chiptreiber einen
Pflichtnamen anders schreibt, wenn jemand wieder einen Vektor *rechnet*
statt ihn von `netdev.vec_of` zu bekommen, und wenn `gfx-aus.fi` mit
`gfx.fi` nicht mehr Schritt hält.

Dass sie überhaupt rot werden **kann**, prüft `tools/struktur/gegenprobe.sh`:
es bricht jede Zusage genau einmal in einem Wegwerfbaum (`git worktree`
unter `/tmp`, der eigene Baum bleibt unberührt) und verlangt, dass
`run.sh` es meldet. Der Grund steht in dieser Runde: `memmap.py` prüfte
Vektorkollisionen seit Runde K10 — und übersah `VEC_MOUSE = 46` gegen
`VEC_NET + 1 = 46` trotzdem, weil die eine Seite eine *Rechnung* war.
Eine grüne Probe ist nur so viel wert wie ihr Nachweis, dass sie zubeißt.

Und `tools/struktur/pfade.sh` beantwortet die Frage, an der dieser Umzug
beinahe still gescheitert wäre: **zeigt ein Werkzeug auf eine Datei, die
es nicht mehr gibt?** `grep -aE '^const FOO' kernel/fb.fi` fällt nach
einem Umzug nicht aus — es findet einfach nichts, und der Vergleich
danach ist lautlos falsch.

Wer eine Datei zu `drivers/gfx/` (oder `drivers/input/ps2m.fi`)
hinzufügt, trägt sie in `GFX_DATEIEN` in `tools/build-kernel.sh` ein —
sonst zieht der Serverbau Grafik in ein Abbild, das keine haben soll.
