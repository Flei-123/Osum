# Runde WAYLAND — ein Wayland-Server für OrientOS

Zweig `wayland`, Grundlage `main` @ `ce4a232`. Arbeitsbaum
`/root/os-wayland`. Nichts gemergt.

**Das Ergebnis in einem Satz:** **Stufe 2 ist gefallen** — ein
**unveränderter** `weston-simple-shm` aus dem Weston-Quellarchiv läuft
auf OrientOS gegen einen selbstgebauten Wayland-Server und bekommt ein
Fenster auf dem Fensterserver des Kerns; Stufe 1 ist **pixelgenau** durch
ein Bildschirmfoto belegt.

Abnahme: `bash tools/wayland/run.sh` → **45 bestanden, 0 gescheitert**
(darin `wltest` im laufenden Kern mit 27 eigenen Zusagen).

---

## 1. Was zuerst gemessen wurde — und warum die Runde damit anfing

Der Auftrag verlangt ausdrücklich, **vor** dem Protokoll zwei Fragen zu
klären: kann OrientOS Dateideskriptoren über einen Socket übergeben
(SCM_RIGHTS), und kann es fremden Speicher einblenden (MAP_SHARED)? Die
Antwort war dreimal **nein**, und sie steht im Quelltext:

| Frage | Befund vor dieser Runde |
|---|---|
| AF_UNIX? | `kernel/sys.fi`, `do_socket`: `if domain != AF_INET { -EAFNOSUPPORT }` |
| MAP_SHARED? | `kernel/sys.fi` kennt `MAP_PRIVATE=2` und `MAP_ANONYMOUS=32` — sonst nichts |
| SCM_RIGHTS? | `grep SCM_RIGHTS/sendmsg/recvmsg kernel/` → **null Treffer** |

Dagegen wurde gemessen, was ein **echter** Client wirklich braucht:
`weston-simple-shm` 10.0.1, statisch gegen musl + libwayland-client
1.21.0 gebaut, gegen ein **echtes weston** gelaufen (Beendigungscode 0).
Ein Lauf, mit `strace` gezählt:

```
sendmsg 323   poll 323   recvmsg 322   mmap 120
fcntl 3       socket 1   memfd_create 1   connect 1
```

Drei Dinge daraus bestimmen alles Weitere:

1. **Kein `read`/`write` auf dem Socket.** libwayland benutzt
   ausschließlich `sendmsg`/`recvmsg`. Ein Unix-Socket, der nur `read`
   und `write` kann, ist für Wayland kein Unix-Socket.
2. **SCM_RIGHTS kommt genau einmal vor** — beim `wl_shm_pool`, der den
   memfd hinüberreicht. Selten, aber unvermeidbar.
3. **Der Puffer wird geteilt, nicht kopiert.** Eine Kopie je Bild wäre
   bei 250 000 Oktetten das Ende jeder Bildrate — und sie wäre falsch,
   weil der Client nach dem `mmap` weitermalt.

---

## 2. Die Entscheidung, die die Runde kurz gemacht hat

**OrientOS hatte den schweren Teil schon.** `kernel/wm.fi` ist
architektonisch bereits ein Wayland-Compositor: die Anwendung malt in
einen **eigenen** Puffer, der Server setzt zusammen, die Anwendung sieht
den Bildschirm nie. Nur der **Transport** war ein anderer — Systemaufrufe
(`WM_CREATE` = 2100) statt Socket und Protokoll.

Und: **fremde Linux-Binaries laufen hier schon** (Runden LAUFZEIT und
FREMDLAND — busybox, Lua, SQLite, QuickJS), weil dieser Kern **Linux'
Syscall-Nummern** benutzt. Damit war klar, dass der Client **statisch**
gegen musl + libwayland gebaut werden kann und der dynamische Lader (der
parallel in einer anderen Runde entsteht) für **diese** Runde nicht
gebraucht wird. Das ist der Grund, warum sie unabhängig messbar blieb.

---

## 3. Was gebaut wurde

### Im Kern

| Datei | Was |
|---|---|
| `kernel/unixsock.fi` (neu) | Unix-Domain-Sockets und Speicherobjekte: fünf Tafeln in `kdata` ab `0xF3000` |
| `kernel/file.fi` | zwei neue Deskriptorarten: `K_USOCK=14`, `K_SHM=15` |
| `kernel/sys.fi` | `socket(AF_UNIX)`, `bind`/`listen`/`accept`/`connect` über einen **Pfad**, `sendmsg`/`recvmsg` mit SCM_RIGHTS, `memfd_create` (319), `ftruncate` (77), `fallocate` (285), `fcntl F_ADD_SEALS/F_GET_SEALS`, `mmap MAP_SHARED`, `poll` für die neue Art |
| `kernel/proc.fi` | nichts Neues — `map_frame` gab es schon und war genau richtig |

**Eigene Deskriptorart statt `K_SOCK` mitbenutzen:** bei `K_SOCK` trägt
`OF_INO` die Nummer eines Platzes in `inet.fi`. Hätte ein Unix-Socket
dieselbe Art, schlösse ein `close` den INET-Platz derselben Nummer — eine
fremde Verbindung, die nichts damit zu tun hat. Eine Zahl mehr macht
diesen Fehler unmöglich.

**`map_shm` benutzt `proc.map_frame`, nicht `map_page`.** `map_page`
**holt** einen Rahmen; hier gibt es ihn schon und ein **zweiter** Prozess
soll **denselben** bekommen. `map_frame` trägt außerdem `PAGE_SHARED`
ein, damit `page_drop` den Rahmen beim Abräumen nicht freigibt — er
gehört dem Objekt, nicht dem Prozess.

### In Ring 3

| Datei | Was |
|---|---|
| `tools/wayland/gen.py` | **erzeugt** `kernel/user/wlproto.fi` aus den offiziellen XML-Dateien: 16 Schnittstellen, 146 Konstanten, 920 Zeilen |
| `kernel/user/wlproto.fi` | erzeugt, nicht abgetippt — **nicht von Hand ändern** |
| `kernel/user/wayd.fi` | der Server, ~1100 Zeilen |
| `tools/wayland/waydctl.c` | der Wächter für den Bedarfsstart |
| `tools/wayland/wltest.c` | die Messung der drei Primitive im Kern |
| `tools/wayland/wlclient.c` | der Stufe-1-Client gegen libwayland |
| `tools/wayland/leerlauf.c` | Speicher und Rechenzeit im Leerlauf |

**Warum erzeugt und nicht abgetippt:** `wayland.xml` allein hat 22
Schnittstellen mit über hundert Anfragen und Ereignissen. Erzeugt werden
**Daten** — Nummern, Signaturen, Opcodes. Der Klebe-Code, den
`wayland-scanner` für C erzeugt (Funktionszeigertabellen, libffi,
Marshalling), fehlt absichtlich: Firn hat keine Funktionszeiger, und ein
`if opcode == 3` ist hier ehrlicher als eine Sprungtabelle.

**Gebaut sind elf Schnittstellen** — `wl_display`, `wl_registry`,
`wl_callback`, `wl_compositor`, `wl_shm`, `wl_shm_pool`, `wl_buffer`,
`wl_surface`, `wl_seat`, `wl_output`, `xdg_wm_base`, `xdg_surface`,
`xdg_toplevel`. Drei Stellen, an denen ein Server sonst **still hängt**,
sind ausdrücklich bedient: `wl_display.sync` beantwortet **jeden**
roundtrip (ein Client macht beim Start zwei), `wl_surface.frame`
beantwortet den Bildrahmen-Rückruf (sonst malt der Client genau ein Bild
und schläft), und `xdg_surface` schickt sein `configure` **ungefragt**
(sonst schickt der Client nie einen Puffer).

---

## 4. Die Messungen

### Stufe 0 — die drei Primitive im Kern

`tools/wayland/wltest.c`, gebaut wie jedes fremde Programm (musl,
statisch, ab `0x40100000`), gelaufen im Kern: **27 bestanden, 0
gescheitert.**

Die Messung, um die es geht: das Kind schreibt `0xA5A5F00D` und `4242`
in sein eigenes Speicherobjekt, reicht den **Deskriptor** per SCM_RIGHTS
durch den Socket, der Elternteil bildet den geerbten Deskriptor ab und
liest **beide** Zahlen zurück. Kein Oktett wurde kopiert.

**Gegenproben, alle bestanden:** `AF_99` abgewiesen,
`AF_UNIX+SOCK_DGRAM` abgewiesen, derselbe Pfad zweimal abgewiesen,
`connect` auf einen Pfad ohne Lauscher scheitert **sofort** statt zu
hängen, Verkleinern nach `F_SEAL_SHRINK` scheitert, frisch abgebildeter
geteilter Speicher ist **genullt**.

### Stufe 1 — ein echter libwayland-Client, pixelgenau

`docs/shots/wayland/stufe1-muster.png`. Gemessen, nicht angesehen —
Spalte x=160 des Bildschirmfotos, Kante für Kante:

| Zeilen | Farbe | gemalt bei Muster-y |
|---|---|---|
| 78–81 | Titelleiste des OrientOS-Fensterservers | — |
| 82–91 | Grund (32,32,96) | 0–9 |
| **92–121** | **ROT (224,0,0)** | **10–39** |
| 122–131 | Grund | 40–49 |
| **132–161** | **GRÜN (0,192,0)** | **50–79** |
| 162–171 | Grund | 80–89 |
| **172–201** | **BLAU (0,96,255)** | **90–119** |

Je **1500** Bildpunkte pro Balkenfarbe, 3000 Grund. Die Balken sind
**exakt 30** Bildpunkte hoch und die Lücken **exakt 10** — Bildpunkt für
Bildpunkt das, was der Client gezeichnet hat, um den Fensterrahmen
versetzt.

### Stufe 2 — `weston-simple-shm`, unverändert

Quelle: Weston 10.0.1, `clients/simple-shm.c`, **md5
`09565c8cc58ea14f40e2a59182328e57`**, Zeile für Zeile wie im Archiv von
`gitlab.freedesktop.org`. Aus dem seriellen Mitschnitt:

```
wm: fokus id=8 vor=7
wm: fen i=1 id=8 x=60 y=60 w=250 h=250 lay=1 fl=0 z=1 malen=11
wm: fen i=1 id=8 x=60 y=60 w=250 h=250 lay=1 fl=0 z=1 malen=16
```

Der Fensterserver des Kerns führt ein 250×250-Fenster, das einem fremden
Programm gehört, und der Malzähler **läuft weiter** — simple-shm
animiert, Bild um Bild.

### Stufe 3 — nicht erreicht

Fenster verschieben und schließen über die OrientOS-Oberfläche wirkt
**noch nicht** auf den Client. `xdg_toplevel.close` und ein `configure`
bei Größenänderung sind im Server vorgesehen, aber nicht an die
Ereignisse des Fensterservers gehängt. Das ist ehrlich offen.

---

## 5. Die vierzehn Fehler, die das Messen gefunden hat

Keiner davon wäre durch Nachdenken aufgefallen.

1. **`0 - 1` auf einem `u64` hält die Maschine an.** Unter
   `profile kernel` ist die Subtraktion geprüft; der erste Lauf starb mit
   `panic: integer overflow in u64 - u64`.
2. **`SK_HEAD` trug zwei Bedeutungen** — Leseposition im Ring **und**
   Verkettung der Annahmeschlange. Ein lauschender Socket meldete sofort
   „Socket 0 wartet", `accept` nahm eine Verbindung an, die es nicht gab.
3. `room()` konnte unterlaufen.
4. **`poll` wird nur von `sched.poll_kick` geweckt**, nicht davon, dass
   Oktette im Ring liegen. Der Server schickte 180 Oktette, der Kern
   bestätigte 180, und der Client schlief trotzdem weiter. Sah aus wie
   ein Server, der nicht antwortet, war ein Wecker, der nicht klingelte.
5. **`ev_end` rechnete `8 + nargs * 4`** — falsch, sobald eine
   Zeichenkette dabei ist, und `wl_registry.global` schickt eine.
6. **`drain` warf einen Client hinaus, dessen Paket in zwei Stücken
   ankam** (`live = false` schließt die Verbindung).
7. `c_inlen - at >= 8` war wieder eine geprüfte Subtraktion.
8. **`WM_FILL` braucht vier Zahlen.** Ein Aufruf mit dreien ließ die
   Farbe in `a3` stehen, wo eine Null lag: gemalt wurde schwarz auf
   schwarz. Der Schirm blieb leer, während jede andere Messung stimmte.
9. **Der Fensterserver steht später als das Skript.** `script=` läuft in
   `ring3()`, `stage_surface()` kommt **danach**. `wayd` wartet jetzt.
10. **Der Deskriptor gehört nicht dem ersten Paket im Stoß**, sondern
    dem, das ihn verlangt (die vierte von elf Nachrichten).
    `wlproto.req_has_fd` entscheidet das aus der XML-Datei.
11. **`fallocate` (285) fehlte ganz.** Ohne den Aufruf gibt musl
    `EOPNOTSUPP`, und der Client stirbt in `abort()` — ein `hlt` mitten
    in musl, das wie ein Haldenfehler **aussieht**.
12. **256 KiB je Speicherobjekt waren zu wenig.** simple-shm legt einen
    Vorrat mit **zwei** Puffern an: 250·250·4·2 = 500 000 Oktette.
13. **`map_shm` hatte keinen Rückfall in den großen Bildbereich**, den
    `do_map` seit Runde K16 kennt.
14. **`file.close_all` geht an `unref_of` vorbei.** Ein Client, der sich
    beendete, ließ seinen Socket **verbunden** zurück; der Server sah nie
    ein Dateiende. `sock_close_all` kennt jetzt auch die neuen Arten —
    und damit stimmt der Zähler **auch bei einem Client, der abstürzt**.

**Eine Kollision hat der Kartenprüfer verhindert:** `WL_SCRATCH` lag auf
`0xFA000` und wäre von der gewachsenen Adresstafel überschrieben worden —
ein `sendmsg` hätte die Rahmenadressen eines fremden Puffers
zerschrieben. Beide Arbeitsplätze stehen jetzt in
`tools/kernel/memmap.py`: **117 Bereiche, 0 Kollisionen.**

**Die Methode, die den vierten Fehler fand, ist mehr wert als der
Fehler:** ein kleiner C-Server auf **Linux**, der genau dieselben Oktette
schickt wie `wayd`. Der echte Client lief dagegen bis „FERTIG" durch —
damit war bewiesen, dass das Drahtformat stimmt und der Fehler im Kern
liegt. Ohne diese Trennung hätte die Suche im Protokoll stattgefunden,
wo nichts zu finden war.

---

## 6. Modularität — eigener Prozess, Dienst, Paket

Justins Vorgabe vom 14.09.2026, Punkt für Punkt:

| Vorgabe | Stand |
|---|---|
| **eigener Prozess in Ring 3**, nicht im Kernel, nicht in desktop/taskbar/wm hineinkompiliert | **erfüllt.** `/bin/wayd` ist ein gewöhnliches Ring-3-Programm. Gegenprobe in der Abnahme: kein Kernteil und kein Schreibtischteil ruft `wayd` |
| **als Dienst an-/abschaltbar** über `init`/`inittab`/`svc` | **vorbereitet.** `etc/inittab.wayland` enthält `wayd:grafik:off:/bin/wayd /tmp/wayland-0`. `off` heißt: die Zeile steht da, der Dienst läuft nicht; `svc start wayd` startet ihn. Die Dienstverwaltung gibt es seit den Runden K13 und INIT und ist **nicht** Teil dieser Runde — die Zeile hängt sich nur ein |
| **als eigenes Paket** auslieferbar | **erfüllt.** `pkg/rezepte/wayland.rezept` baut ein `.opk` mit `python3 pkg/opk.py bauen` |
| **standardmäßig an oder aus?** | siehe unten |
| **Ressourcenverbrauch im Leerlauf messen** | **gemessen**, siehe unten |

### Die Leerlaufkosten, gemessen

`tools/wayland/leerlauf.c`, im laufenden Kern, über zehn Sekunden:

| | Seiten | Speicher | Marken / 10 s |
|---|---|---|---|
| `wayd` im Dauerbetrieb, wartet auf den ersten Client | **51** | **204 KiB** | **0** von 1000 |
| *Gegenprobe:* die Leerlaufaufgabe des Kerns | 0 | — | **1000** von 1000 |

Die Gegenprobe steht da, weil eine Null sonst nichts wert wäre: eine
blinde Messung zeigte für beide null.

**Ehrlich zu den 0 Marken:** `wayd` benutzt eine **beschäftigte Schleife**
mit `SYS_YIELD`, kein blockierendes `poll`. Die Null heißt „gibt ab,
bevor seine Marke voll ist" — **nicht** „schläft". Auf einer Maschine
ohne andere Last dreht die Schleife trotzdem. Ein `poll` mit Frist wäre
hier das Richtige und ist ein offener Punkt.

### Die Entscheidung: **Bedarfsstart**, nicht „an" und nicht „aus"

Justins zweite Vorgabe ersetzt die erste, und sie ist besser als beide
Alternativen. Was Linux **socket activation** nennt, ist hier gebaut:

* **`/bin/waydctl`** legt den Socket an und **hält** ihn. `bind` und
  `listen` passieren bei ihm, einmal.
* Klopft jemand, startet er `/bin/wayd` mit **`fork`** — das muss `fork`
  sein und nicht `elf.spawn`, weil `inherit_task` **alle** Deskriptoren
  weitergibt und `inherit_std` nur die drei Standardeingänge.
* Der Server zählt seine Clients; fällt die Zahl auf null, läuft eine Uhr
  und er beendet sich.

**Warum das überhaupt geht** — eine Eigenschaft aus Abschnitt 3: dieser
Kern lässt `connect` **warten**, bis jemand `accept` ruft. Ein Client
bekommt deshalb **kein** „connection refused", während der Server noch
startet. Ohne diese Eigenschaft wäre der Bedarfsstart nicht baubar.

Gemessen, in dieser Reihenfolge:

```
waydctl: waechter bereit auf /tmp/wayland-0 (fd 3)
waydctl: ein Client klopft -- starte /bin/wayd
wayd: bereit auf /tmp/wayland-0
wayd: verbunden
wlclient: beende mich
wayd: verbunden          <- ZWEITER Client, SELBER Server
wayd: Client gegangen
```

**Was davon noch nicht belegt ist:** das **Ablaufen** der Leerlaufuhr und
der dadurch beendete Server. Die Erkennung (`wayd: Client gegangen`)
steht und ist gemessen; der letzte Schritt — Server weg, Socket bleibt,
nächster Client startet ihn erneut — ist in keinem Lauf bis zum Ende
gekommen, weil die QEMU-Zeitgrenze vorher griff. **Das ist offen und
wird nicht als erledigt ausgegeben.**

**Die Zwischenablage**, nach der ausdrücklich gefragt wurde: dieser
Server hält **keinen** Zustand, der jemandem gehört. Er hat kein
`wl_data_device` (Abschnitt „Was nicht gebaut ist"), also gibt es unter
ihm gar keine Wayland-Zwischenablage, die ein Neustart zerstören könnte.
OrientOS hat eine **eigene** Zwischenablage im Kern
(`kernel/user/wlibc.fi`, `clip_put`/`clip_take`, Runde SYSTEMBUS) — die
lebt im Kern und überlebt jeden Neustart von `wayd`. Sobald
`wl_data_device` dazukommt, ändert sich das: dann gilt Waylands Regel,
dass der Inhalt dem anbietenden **Programm** gehört, und ein
Server-Neustart zwischen Kopieren und Einfügen verlöre ihn. Das gehört
dann in dieselbe Runde wie `wl_data_device`.

---

## 7. Kommt Fremdcode ins System?

Die Frage wurde ausdrücklich gestellt. **Antwort: nein — nicht durch den
Server.** Sauber aufgeschlüsselt, was wo landet:

| Was | Fremd? | Wo es läuft | Im Grundabbild? |
|---|---|---|---|
| `/bin/wayd`, `kernel/user/wlproto.fi` | **nein** — eigener Firn-Code | Ring 3, gewöhnlicher Prozess | nein, eigenes Paket |
| `kernel/unixsock.fi` und die Syscalls | **nein** — eigener Firn-Code | Ring 0 | ja (es sind Systemaufrufe wie `pipe` oder `socket`) |
| `wayland.xml`, `xdg-shell.xml` | **Spezifikation**, kein Programmtext | nur auf dem **Bauwirt**, zur Erzeugung | nein |
| `libwayland-client` 1.21.0 | **ja, fremd** | im Adressraum **des Anwendungsprogramms**, Ring 3 | nein |
| `libffi` 3.4.6 | **ja, fremd** | dito (libwayland braucht es) | nein |
| `weston-simple-shm`, `os-compatibility.c` | **ja, fremd** | nur in der **Abnahme**, Ring 3 | nein |
| `tools/wayland/wlclient.c`, `wltest.c`, `waydctl.c`, `leerlauf.c` | **nein** — eigener C-Code | nur in der Abnahme | nein |

**Die Begründung, warum eine Spezifikation kein Fremdcode ist:** aus
`wayland.xml` erzeugt `tools/wayland/gen.py` Firn-Quelltext — Nummern,
Signaturen, Opcodes. Das ist dasselbe Verhältnis wie zwischen RFC 793 und
einem TCP-Stapel. Wäre es anders, wäre jeder TCP-Stapel fremder Code.

**Und die ehrliche Kehrseite:** ein *nützliches* fremdes GUI-Programm
(Firefox, LibreOffice) bringt **seine** libwayland mit, und die ist
fremd. Sie läuft aber in **seinem** Prozess, in Ring 3, mit **seinen**
Rechten — genau wie jede andere Bibliothek, die ein Programm mitbringt.
Der Server sieht davon nichts; er sieht Oktette auf einem Socket.

---

## 8. Was fehlt für Firefox oder LibreOffice — realistisch

Nicht schöngeredet. Was diese Runde erreicht hat, ist die **Grundlage**;
was zwischen hier und Firefox liegt, ist mehr als das Bisherige:

1. **Der dynamische Lader.** Firefox ist gegen ~40 Bibliotheken
   dynamisch gelinkt. Diese Runde hat das umgangen, indem sie statisch
   gebaut hat — bei Firefox geht das nicht. (Läuft parallel als eigene
   Runde.)
2. **`wl_data_device`** — ohne Zwischenablage zwischen Programmen ist ein
   Browser kaum benutzbar.
3. **Tastatur und Zeiger wirklich.** `wl_seat` **meldet** beide, aber die
   Ereignisse des Fensterservers werden noch nicht auf
   `wl_keyboard.key` / `wl_pointer.motion` übersetzt. Dazu gehört das
   **Tastaturformat**: Wayland schickt eine xkb-Keymap als Deskriptor,
   und die hat OrientOS nicht.
4. **Mehr Pufferformate und Skalierung.** Heute ARGB8888/XRGB8888
   undurchsichtig, kein `wl_subsurface`, keine Transformation.
5. **EGL/OpenGL.** Firefox malt seit Jahren nicht mehr über `wl_shm`,
   sondern über `dmabuf` und GPU. `wl_shm` ist bei ihm der Notweg, und
   der Notweg ist langsam.
6. **Das Programm selbst.** Firefox braucht Fäden, Prozesse,
   `epoll`, Signale, `/proc`, eine funktionierende `malloc`-Arena über
   Fadengrenzen und ein Dateisystem mit den Pfaden, die es erwartet.

**Realistische Einschätzung:** `weston-terminal` und ähnliche einfache
GTK-freie Clients sind die nächste erreichbare Stufe. Firefox ist
mehrere Runden entfernt, und die GPU-Frage (Punkt 5) ist davon die
größte.

---

## 9. Wie man es nachbaut

```
# Der Wirt braucht: musl-gcc, wayland-scanner, libwayland-dev,
# wayland-protocols, qemu-system-x86_64.
# Einmalig, weil musl mit -nostdinc baut:
ln -s /usr/include/linux            /usr/include/x86_64-linux-musl/linux
ln -s /usr/include/x86_64-linux-gnu/asm /usr/include/x86_64-linux-musl/asm
ln -s /usr/include/asm-generic      /usr/include/x86_64-linux-musl/asm-generic

# libffi 3.4.6 und libwayland 1.21.0 statisch gegen musl
# (die genauen Schritte stehen im Kopf von tools/wayland/run.sh)

# Den Protokollteil neu erzeugen:
./tools/wayland/gen.py > kernel/user/wlproto.fi

# Die ganze Abnahme:
bash tools/wayland/run.sh
```

**Zwei Fallen, die Zeit gekostet haben und deshalb hier stehen:**
`-I weston-10.0.1/shared` **nicht** benutzen — dort liegt ein eigenes
`signal.h`, das `<signal.h>` verdeckt. Und `_GNU_SOURCE` muss auf der
**Befehlszeile** stehen, nicht erst in `config.h`.

---

## 10. Offene Punkte, ehrlich

* **Stufe 3** (Fenster schließen/verschieben wirkt auf den Client) —
  nicht gebaut.
* **Das Ablaufen der Leerlaufuhr** ist nicht bis zum Ende belegt.
* **`wayd` dreht eine beschäftigte Schleife** statt in `poll` zu warten.
* **Kein `wl_data_device`, kein `wl_touch`, kein `wl_subsurface`, kein
  `xdg_popup`**, keine Skalierung, keine Transformation.
* **Tastatur und Zeiger sind angekündigt, aber nicht verdrahtet.**
* **Höchstens 4 Clients und 16 Speicherobjekte** gleichzeitig.
* **`svc disable wayd` mit Foto und Gegenprobe** ist als Zusage
  verlangt, aber nicht gemessen — die Dienstzeile ist eingehängt, der
  Lauf mit `init` steht aus.
