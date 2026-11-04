# Was im Firn-Repository entfernt werden muss

**Nichts davon ist ausgefuehrt.** Diese Datei ist die Anleitung fuer den
Schnitt, den Justin selbst macht, wenn die laufende Vollabnahme durch
ist. Bezugspunkt ist der Branch **`k6-merge`, Spitze `c66c6bcd`** — das
ist der Stand, aus dem dieses Repository herausgeloest wurde.

Zeilennummern beziehen sich auf `test.sh` in genau diesem Commit. Nach
einem Merge nach `main` verschieben sie sich; deshalb steht zu jedem
Abschnitt zusaetzlich das Suchmuster, das ihn eindeutig findet.

---

## 1. Pfade, die geloescht werden

Diese liegen jetzt vollstaendig im Osum-Repository, mit Historie:

| Pfad in `firn` | liegt jetzt in `osum` als |
|---|---|
| `demos/kernel/` (47 Dateien, inkl. `user/`) | `kernel/` |
| `lib/osum/` (7 Dateien) | `lib/libc/` |
| `tools/kernel/` | `tools/kernel/` |
| `tools/osum/` (`run.sh`, `mkfs.py`, `break.py`) | `tools/osum/` |
| `tools/posix/` | `tools/posix/` |
| `tools/smp/` | `tools/smp/` |
| `tools/pci/` | `tools/pci/` |
| `tools/userland/` | `tools/userland/` |

```sh
git rm -r demos/kernel lib/osum \
          tools/kernel tools/osum tools/posix tools/smp tools/pci tools/userland
```

`demos/` bleibt bestehen (`demos/` enthaelt weitere Beispiele) — nur
`demos/kernel/` faellt weg.

---

## 2. Zwei Faelle, die NICHT einfach geloescht werden duerfen

`tools/core/` und `tools/freestanding/` sind **Uebersetzertests**, keine
Kerneltests. Sie beweisen, dass `profile kernel` und `std.core`
funktionieren — Eigenschaften von Firn. Ihr Prueflingsobjekt liegt aber
in `demos/kernel/`:

* `tools/freestanding/run.sh` uebersetzt `demos/kernel/core.fi` (147
  Zeilen) und bindet gegen `demos/kernel/linker.ld` (31 Zeilen), mit
  `demos/kernel/start.s` (193 Zeilen).
* `tools/core/run.sh` uebersetzt `demos/kernel/kcore.fi` (360 Zeilen),
  ebenfalls mit `start.s` und `linker.ld`.

Es gibt zwei Moeglichkeiten, und ich habe **keine davon ausgefuehrt**:

**(a) empfohlen — die vier Dateien in Firn behalten, umgezogen.** Sie
gehoeren fachlich zum Uebersetzer:

```sh
mkdir -p demos/freestanding
git mv demos/kernel/core.fi   demos/freestanding/core.fi
git mv demos/kernel/kcore.fi  demos/freestanding/kcore.fi
git mv demos/kernel/start.s   demos/freestanding/start.s
git mv demos/kernel/linker.ld demos/freestanding/linker.ld
# danach in tools/core/run.sh und tools/freestanding/run.sh
# demos/kernel/ -> demos/freestanding/ ersetzen
```

Dann bleiben die Abschnitte 19 und 30 von `firn/test.sh` bestehen und
Punkt 3 unten entfaellt fuer diese beiden. Die vier Dateien liegen dann
in beiden Repositorien — das ist gewollt: in Osum sind sie Teil des
Kernels, in Firn sind sie der Prueftext des Uebersetzers.

**(b) alternativ — die Abschnitte 19 und 30 aus `firn/test.sh` und die
beiden Verzeichnisse `tools/core/`, `tools/freestanding/` entfernen.**
Dann verliert Firn 41 + 46 = 87 Zusagen und die einzige Messung, die
`profile kernel` gegen die Wirklichkeit haelt. Davon rate ich ab.

---

## 3. Abschnitte, die aus `firn/test.sh` verschwinden

Der Kopfkommentar von `test.sh` beschreibt jeden Abschnitt; die
Beschreibung muss mit dem Abschnitt weg.

### Kopfkommentar (Zeilen im Kopfblock)

| Zeilen | Inhalt | Suchmuster |
|---:|---|---|
| 87–90 | `19. Freestanding compilation` | `^#  19\. Freestanding` |
| 91–96 | `57. Four processors (tools/smp/run.sh, ROUND K5)` | `^#  57\. Four processors` |
| 97–105 | `22. The kernel (tools/kernel/run.sh, round 59)` | `^#  22\. The kernel` |
| 106–111 | `30. std.core in a kernel` | `^#  30\. std\.core` |
| 208–214 | `56. THE POSIX FLOOR (tools/posix/run.sh, ROUND K4)` | `^#  56\. THE POSIX FLOOR` |

Fuer die Abschnitte 49 (K1), 50 (K2) und 58 (K6) gibt es **keinen**
Eintrag im Kopfkommentar — dort ist nichts zu loeschen.

### Die Abschnitte selbst

| Zeilen | Abschnitt | Suchmuster (`echo "== …`) |
|---:|---|---|
| 628–640 | 19. freestanding | `tools/freestanding/run.sh` |
| 694–715 | 22. the kernel really runs | `tools/kernel/run.sh` |
| 818–841 | 30. std.core in a kernel | `tools/core/run.sh` |
| 1190–1198 | 49. a program off the disk (K1) | `tools/osum/run.sh` |
| 1200–1211 | 50. PCI, APIC, NVMe (K2) — inkl. der zwei Kommentarzeilen davor | `tools/pci/run.sh` |
| 1309–1323 | 56. POSIX + libc (K4) | `tools/posix/run.sh` |
| 1324–1340 | 57. vier Prozessoren (K5) | `tools/smp/run.sh` |
| 1351–1373 | 58. das Userland (K6) — inkl. der zwei Kommentarzeilen davor | `tools/userland/run.sh` |

Faellt Variante (a) oben, bleiben 628–640 und 818–841 **stehen** und nur
die Pfade darin aendern sich.

Ein Abschnitt reicht jeweils von seiner `echo "== …"`-Zeile (bzw. dem
Kommentarblock unmittelbar davor) bis zum abschliessenden `fi` vor der
naechsten `echo "== …"`-Zeile.

**Nach dem Schnitt nicht neu durchnummerieren.** Die Nummern in
`firn/test.sh` sind historisch vergeben (49 steht im Kopfkommentar fuer
„Phi nodes", im Rumpf fuer K1 — das ist bereits so). Luecken sind dort
normal und billiger als eine Umnummerierung, die jede Fehlermeldung in
den Rundenberichten falsch macht.

---

## 4. Was im Firn-Repository BLEIBT

* **`docs/`** — alle Rundenberichte, auch `OSUM-K1/K2/K3`, `ROUNDK4/K5/K6`,
  `ROUND52/59/62/73`. Sie sind das Logbuch des Firn-Projekts. Osum hat
  Kopien davon; das Original bleibt.
* **`lib/net/`** und **`tools/k3net/`** — der TCP/IP-Stack aus Runde K3.
  Er ist nie an den Kernel angeschlossen worden und haengt an nichts aus
  `demos/kernel/`.
* **`tools/strlib/src/std_core.fi`** — enthaelt in Zeile 25 nur einen
  Kommentar, der `demos/kernel/core.fi` erwaehnt. Kein Code haengt daran;
  den Kommentar bei Gelegenheit anpassen.
* **`lib/firnc1/codegen.fi`**, Zeile 1829 — dito, ein Kommentar, der
  `demos/kernel/start.s` nennt.

---

## 5. Textstellen, die danach nicht mehr stimmen

Kein Code, aber sie werden falsch. Vor dem Commit durchsehen:

* `README.md` — nennt den Kernel unter `demos/kernel`
* `RUN.md` — Anleitung, den Kernel zu starten
* `SPEC.md` — Beispiele mit `demos/kernel`
* `ACCEPTANCE.md`, `PLAN.md`, `ROADMAP.md` — pruefen, ob dort
  Kernel-Punkte als Firn-Zusagen gefuehrt werden; die gehoeren jetzt in
  die Abnahme von Osum.

Die Rundenberichte in `docs/` **nicht** anfassen: sie beschreiben, wie es
damals war, und das war so.

---

## 6. Reihenfolge

1. Vollabnahme auf `main` abwarten und gruen sehen.
2. `./test.sh` im Osum-Repository gruen sehen (es haengt an
   `vendor/firn/COMMIT` = `c66c6bcd…`, also am selben Stand).
3. Erst dann in Firn schneiden: Punkt 2 (Variante a), dann Punkt 1, dann
   Punkt 3, dann Punkt 5.
4. `firn/test.sh` einmal komplett laufen lassen. Es muss ohne die
   entfernten Abschnitte gruen bleiben; die Zahl der Abschnitte sinkt um
   sechs (bzw. acht bei Variante b).
5. Erst danach in Osum `vendor/firn/COMMIT` weiterziehen — nie vorher.
