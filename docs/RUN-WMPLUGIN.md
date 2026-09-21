# RUN.md — wie man die Runde WMPLUGIN startet und nachfaehrt

Zweig `wmplugin` im Worktree `/root/os-wmplug`. Alle Befehle aus diesem
Ordner, alle Pfade relativ.

Was die Runde inhaltlich ist und was gemessen wurde, steht in
**`docs/RUNDE-WMPLUGIN.md`**. Dieses Blatt sagt nur, welchen Befehl man
tippt.

---

## 1. Der eine Befehl

```bash
bash tools/wmplug/run.sh
```

Das ist der Abnahmelauf. Er macht alles selbst:

1. baut den Kernel (`tools/build-kernel.sh`, ~30 s),
2. baut die elf Ring-3-Programme,
3. sieht in der **Symboltafel des Kerns** nach, dass kein Plugin darin
   steht,
4. baut das Plattenabbild (mit Schriften — ohne sie meldet der Kern
   "wm: kein Bildschirm"),
5. bootet **sechs** QEMU-Laeufe: Absturz, Frist, Rechte, Schnittstelle,
   Verwaltung und die der zwei Modullaeufer,
6. ruft `tools/wmplug/regel.sh` und `tools/wmplug/widget.sh` und
   rechnet deren Zahlen in seine Summe ein,
7. prueft `tools/check-ui.sh`,
8. legt die Bilder nach `docs/shots/wmplug/`,
9. druckt am Ende `WMPLUG: N bestanden, M gescheitert` und beendet sich
   mit 1, wenn M ungleich 0 ist.

Dauer: rund **20 Minuten** mit KVM.

### Schalter

| | |
|---|---|
| `WMPLUG_SCHNELL=1` | ohne die zwei Modullaeufer — nur die Kernseite, rund 8 Minuten |
| `WMPLUG_KEEP=1` | behaelt das Arbeitsverzeichnis `/tmp/wmplug-run-*` mit allen seriellen Mitschnitten (`*.clean`), Fotos und Abbildern |
| `OSUM_ACCEL=tcg` | ohne KVM rechnen (rund viermal langsamer) |

```bash
WMPLUG_SCHNELL=1 WMPLUG_KEEP=1 bash tools/wmplug/run.sh
```

### Die einzelnen Modullaeufer

Beide laufen auch allein und bauen sich ihren Kernel selbst:

```bash
bash tools/wmplug/regel.sh     # die Fensterregel-Engine
bash tools/wmplug/widget.sh    # das Leistenwidget, an und aus
```

---

## 2. Voraussetzungen

* `qemu-system-x86_64` — fehlt es, sagt der Laeufer das und beendet sich
  mit 0, statt rot zu werden.
* `/dev/kvm` les- und schreibbar (sonst faellt `tools/lib/qemu.sh`
  selbsttaetig auf TCG zurueck und schreibt das in die erste Zeile).
* `python3` mit **Pillow** — nur fuer das Umwandeln der Fotos nach PNG.
* `as`, `ld`, `nm`, `objcopy` (binutils).
* Der Firn-Uebersetzer wird bei Bedarf geholt:
  `bash vendor/firn/fetch-firnc.sh`.

**Andere QEMU laufen auf dieser Maschine parallel.** Der Laeufer legt
seine Sockets und Dateien deshalb in ein eigenes `mktemp`-Verzeichnis.
Wer von Hand bootet, soll das auch tun — sonst fahren sich zwei Laeufe
gegenseitig in die Sockets.

---

## 3. Von Hand starten (einzelner Lauf)

Wer nur einmal booten und zusehen will:

```bash
# 1. Kernel
bash tools/build-kernel.sh /tmp/mein.img

# 2. ein Programm (Beispiel: das Widget)
export FIRNLIB="$PWD/lib"
as --64 -o /tmp/crt.o kernel/user/crt.s
vendor/firn/bin/firnc -c kernel/user/pluguhr.fi -o /tmp/pluguhr.o
ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
   -o /tmp/pluguhr.elf /tmp/crt.o /tmp/pluguhr.o
```

Das Plattenabbild braucht die **Schriften**, sonst startet der
Fensterserver nicht:

```bash
python3 tools/k15/tree.py /tmp/baum
python3 tools/osum/mkfs.py build /tmp/disk.img 32768 \
    /lib/ /lib/mono.ttf=assets/osum-mono.ttf /lib/sans.ttf=assets/osum-sans.ttf \
    /bin/ /bin/pluguhr=/tmp/pluguhr.elf \
    /etc/ /etc/wmplug.conf=etc/wmplug.conf /etc/wmregeln.conf=etc/wmregeln.conf
```

Booten (eigene Socket-Namen benutzen!):

```bash
qemu-system-x86_64 -accel kvm -cpu host -kernel /tmp/mein.img -m 256 \
  -append "gfx wm wig desk wmhold wiglong nokbd nosched noproc nofs wmplug" \
  -serial file:/tmp/ser.txt -display none -no-reboot \
  -vga std -global VGA.edid=off -monitor unix:/tmp/mon.sock,server,nowait \
  -drive file=/tmp/disk.img,format=raw,if=ide,index=0 \
  -device isa-debug-exit,iobase=0xf4,iosize=0x04
```

**Exitcode 21 heisst sauber.** Auf `wm: hold` in `/tmp/ser.txt` warten,
dann fotografieren:

```bash
python3 tools/gfx/screenshot.py /tmp/mon.sock /tmp/bild.ppm 25
python3 tools/gfx/checkshot.py groesse /tmp/bild.ppm     # -> 800 600
```

### Die Modusworte dieser Runde

| Wort | was es tut |
|---|---|
| `wmplug` | die Plugintafel aufsetzen — **ohne dieses Wort nimmt der Kern keine Plugins an** |
| `plugaus` | die Tafel ausdruecklich zulassen (Gegenprobe) |
| `plugtest` | den Selbsttest von `kernel/wmplug.fi` beim Hochlauf fahren |
| `plugfrist` | die Frist auf wenige Ticks kuerzen, damit ein Haenger im Lauf auffliegt |

Ein zusaetzliches Programm startet der Schreibtisch mit
`wigapp=/bin/NAME,wort1,wort2` (bis zu vier durch Komma getrennte
Woerter). Beispiele:

```
wigapp=/bin/plugboese,boese,segv        # Absturz-Gegenprobe
wigapp=/bin/plugboese,boese,hang        # Haenger-Gegenprobe (mit plugfrist)
wigapp=/bin/plugboese,boese,greif       # Rechte-Gegenprobe
wigapp=/bin/uhrstart,uhrstart,verwaltung,runden=30
```

### Die serielle Leitung lesen

Der Kern schreibt Namen mit **fester Laenge** (`serial.text(name, 8)`),
mitten in den Zeilen stehen also Nulloktette. Vor dem Suchen putzen:

```bash
tr -d '\000' < /tmp/ser.txt > /tmp/ser.clean
grep -aE 'wmplug:|plugboese:|pluguhr:|plugregel:' /tmp/ser.clean
```

Und: Kernzeilen und Ring-3-Zeilen laufen **ineinander**. Auf der Leitung
steht wirklich `plugstart: wmplug: unreg uhr grund=4`. Wer mit `^`
ankert, sucht vergeblich.

---

## 4. Was gerade herauskommt

Letzter voller Lauf auf diesem Rechner (KVM), Exitcode 0:

```
WMPLUG: 139 bestanden, 0 gescheitert
```

Die zwei Modullaeufer, die darin mitlaufen:

```
REGEL:  38 bestanden, 0 gescheitert
WIDGET: 30 bestanden, 0 gescheitert
```

Dazu:

```bash
bash tools/check-ui.sh            # PASSED
python3 tools/kernel/memmap.py    # 111 Bereiche, 0 Kollisionen
```

---

## 5. Wenn etwas rot ist

| Meldung | woran es liegt |
|---|---|
| `wm: kein Bildschirm` | das Abbild hat keine Schriften — `/lib/mono.ttf` und `/lib/sans.ttf` fehlen in der `mkfs.py`-Zeile |
| Exitcode 124 | `timeout` hat zugeschlagen: der Lauf ist nicht bis `wm: hold` gekommen |
| Exitcode 137 | dieser QEMU wurde von aussen abgeraeumt (Speicherdruck, paralleler Lauf) — wiederholen |
| `firnc fehlt` | `bash vendor/firn/fetch-firnc.sh` |
| `the module 'std.rt' ... not available in profile 'kernel'` | das Programm traegt `profile app` — mit `tools/lib/userprog.sh` (`up_build`) bauen, nicht mit einem getippten `firnc`-Aufruf |
| Fotos fehlen | Pillow ist nicht da; die `.ppm` liegen trotzdem im `WMPLUG_KEEP`-Verzeichnis |

---

## 6. Die Dateien der Runde

| Datei | was |
|---|---|
| `kernel/wmplug.fi` | die Buchhaltung: acht Plaetze, Ereignisringe, Rechte, Frist, Kehrbesen |
| `kernel/sysgui.fi` | `plug_call` — die Aufrufe 2117..2126 und die Rechtepruefung |
| `kernel/sys.fi` | die Nummern, `WM_MAXNR` = 2126 |
| `kernel/wm.fi` | `notify` an den Stellen, an denen Ereignisse entstehen; Kehrbesen je Bild und je Tick |
| `kernel/kstate.fi` | `WMP_OFF`, die Modusworte |
| `kernel/user/plugregel.fi` | **Plugin 1** — Fensterregel-Engine |
| `kernel/user/pluguhr.fi` | **Plugin 2** — Leistenwidget (Uhr/CPU) |
| `kernel/user/plugboese.fi` | die Gegenprobe: `segv`, `hang`, `greif` |
| `kernel/user/plugprobe.fi` | der Prueflauf der Schnittstelle |
| `kernel/user/plugstart.fi` | Starthelfer (**Abkuerzung**, siehe Bericht) |
| `kernel/user/wmplug.fi` | `/bin/wmplug` — list/info/enable/disable |
| `etc/wmplug.conf` | wer was darf |
| `etc/wmregeln.conf` | die Fensterregeln |
| `pakete/wmplug-*/rezept` | die drei opk-Pakete |
| `tools/wmplug/run.sh` | der Abnahmelauf |
| `docs/RUNDE-WMPLUGIN.md` | der Bericht mit allen Messwerten |
