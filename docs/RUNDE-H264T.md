# RUNDE H264T (P-023) -- der Dekodierer wird schnell, ohne ein Bit zu verlieren

Zweig `h264t`, Basis `main` d5583ee.

Die Vorrunde (P-022, `docs/RUNDE-CODEC.md`) hat einen h.264-Dekodierer
gebaut, der **bitgenau** ist: 51 Bilder aus 10 Stroemen, 51 SHA-256
gegen ffmpeg, 51 Treffer. Er ist aber zu langsam fuer alles ueber CIF.
Diese Runde macht ihn schnell -- und die Bitgenauigkeit ist dabei keine
Nebenbedingung, sondern die Messlatte, an der jede Aenderung scheitert
oder nicht.

---

## 1. ZUERST MESSEN. UND DIE MESSUNG WIDERLEGT DEN AUFTRAG.

Der Auftrag nennt drei Ursachen **in dieser Reihenfolge**:

> 1. `tab_find` geht bitweise linear durch bis zu 68 Eintraege.
> 2. Die Bewegungskompensation rechnet je 4x4-Block einzeln.
> 3. Kein SIMD.

Er sagt aber auch dazu, dass das **Vermutungen aus dem Bericht sind und
nicht gemessen**, und verlangt die Profiltabelle, **bevor** etwas
geaendert wird. Das ist gut so, denn die Rangfolge stimmt nicht.

### 1.1 Wie gemessen wurde

Fuenf Zaehler in `kernel/user/h264.fi`, gefuellt mit `rdtsc`:

| Zaehler | was er umschliesst |
|---|---|
| `PF_CAVLC` | `residual_block` -- die Entropiedekodierung, und `tab_find` sitzt darin |
| `PF_MC` | `mc_mb` -- die Bewegungskompensation eines Makroblocks |
| `PF_RECON` | `recon_mb` -- Transformation, Skalierung, Intra-Vorhersage |
| `PF_DEBLOCK` | `deblock` -- der Entblockungsfilter, einmal je Bild |
| `PF_REST` | `slice_verarbeiten` -- **die Gesamtzeit**, gegen die die anderen vier geprueft werden |

**Warum Takte und nicht Nanosekunden:** ein Abschnitt liegt unter der
Aufloesung, die `clock_gettime` ueber einen Syscall hergibt, und der
Syscall kostet mehr als das, was er messen soll. `rdtsc` ist ein Befehl
ohne Ringwechsel. Dasselbe Argument steht in `kernel/kaesni.fi`.

**Was die Messung selbst kostet, nachgerechnet statt behauptet:** zwei
`rdtsc` je Abschnitt, bei CIF 16 764 Messpunkte auf 260 Mio. Takte --
**rund 0,5 %**. Bei 720p 0,45 %. Die Zahlen unten sind also nicht
wesentlich durch das Messen verzogen.

`PF_REST` ist absichtlich die **Gesamtzeit** und nicht "der Rest": so
muss die Summe der vier Abschnitte kleiner sein als sie, und die
Differenz ist das, was zwischen den Abschnitten liegt (Syntax,
Nachbarschaftsrechnerei, Slice-Kopf). Eine Tabelle, deren Teile sich
nicht zum Ganzen fuegen, waere kein Messgeraet.

### 1.2 DIE PROFILTABELLE VORHER

QEMU mit KVM, `-cpu host`, `-m 512`, AMD EPYC 7571. Stufe-0-Uebersetzer.

**CIF 352x288, 10 Bilder -- 214 ms, 46,72 Bilder/s**

| Abschnitt | Takte | Anteil | Aufrufe |
|---|---:|---:|---:|
| **Bewegungskompensation** | 118 071 580 | **45,4 %** | 3 303 |
| **Entblockung** | 64 280 546 | **24,7 %** | 10 |
| Transformation + Intra | 38 956 742 | 15,0 % | 1 579 |
| **Entropie (`tab_find`)** | 28 419 666 | **10,9 %** | 11 862 |
| Rest (Syntax, Nachbarn) | 10 626 440 | 4,1 % | |
| **gesamt** | 260 354 974 | 100 % | 10 |

**640x480, 6 Bilder -- 288 ms, 20,83 Bilder/s**

| Abschnitt | Takte | Anteil | Aufrufe |
|---|---:|---:|---:|
| **Bewegungskompensation** | 155 614 118 | **42,1 %** | 5 530 |
| **Entblockung** | 101 246 750 | **27,4 %** | 6 |
| Transformation + Intra | 65 058 928 | 17,6 % | 2 776 |
| **Entropie (`tab_find`)** | 33 970 574 | **9,2 %** | 15 431 |
| Rest | 14 001 636 | 3,8 % | |
| **gesamt** | 369 892 006 | 100 % | 6 |

**1280x720, 4 Bilder -- 586 ms, 6,82 Bilder/s**

| Abschnitt | Takte | Anteil | Aufrufe |
|---|---:|---:|---:|
| **Bewegungskompensation** | 316 380 724 | **39,1 %** | 10 329 |
| **Entblockung** | 231 695 420 | **28,7 %** | 4 |
| Transformation + Intra | 156 164 162 | 19,3 % | 5 639 |
| **Entropie (`tab_find`)** | 74 248 790 | **9,2 %** | 29 831 |
| Rest | 29 735 046 | 3,7 % | |
| **gesamt** | 808 224 142 | 100 % | 4 |

### 1.3 WAS DARAUS FOLGT, und es ist nicht das, was im Auftrag steht

> **`tab_find` ist NICHT die Hauptursache. Es ist der vierte Posten mit
> 9 bis 11 Prozent.**

Waere die Baumtafel **unendlich schnell** -- nicht schneller, sondern
kostenlos --, brächte sie bei 640x480 aus 20,83 Bilder/s ganze 22,9.
Die Messlatte sind 25. Der Auftrag haette mit seiner Reihenfolge in die
falsche Richtung gearbeitet, und zwar zuerst.

Die Zeit liegt bei **Bewegungskompensation (39-45 %)** und
**Entblockung (25-29 %)**. Zusammen sind das **zwei Drittel**.

Warum die Bewegungskompensation so teuer ist, sieht man an
`qpel_one`/`rpix`: **jeder einzelne Bildpunkt** geht durch `rpix`, und
`rpix` klemmt jedes Mal beide Koordinaten gegen den Bildrand (vier
Vergleiche), obwohl der weit ueberwiegende Teil aller Bloecke gar nicht
am Rand liegt. Bei `fx=2, fy=2` (dem teuersten Fall) ruft `jhalf` sechs
`hraw` auf, und jedes `hraw` ruft sechs `rpix` -- **36 geklemmte
Zugriffe fuer EINEN Bildpunkt**, und die Zwischenwerte werden fuer den
Nachbarpunkt vollstaendig neu gerechnet.

Die Vermutung des Auftrags ("rechnet je 4x4-Block einzeln") trifft
damit den richtigen Bereich, aber aus dem falschen Grund: teuer ist
nicht die Blockgroesse, teuer ist die **fehlende Zwischenspeicherung
der Filterwerte und die Klemmung je Bildpunkt**.

---

*(Die Abschnitte 2 ff. -- was gebaut wurde, die Profiltabelle nachher,
die Tempozahlen und die Belege der Bitgenauigkeit -- stehen weiter
unten und werden im Lauf der Runde gefuellt.)*
