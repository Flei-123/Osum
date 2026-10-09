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
| `kernel/user/wayd.fi` | der Server, ~1100 Zeilen (seit Runde WAYLAND-INPUT: Tastatur/Zeiger/Zwischenablage in eigenen Dateien, siehe Kapitel 11) |
| `kernel/user/wl_msg.fi`, `wl_input.fi`, `wl_data.fi` | Runde WAYLAND-INPUT: Ereignisse schreiben; Tastatur und Zeiger; wl_data_device und die Brücke zur Zwischenablage |
| `kernel/user/wl_keytab.fi` | erzeugt durch `tools/wayland/genkeys.py` aus der libxkbcommon des Wirts — nicht von Hand |
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

**Stand Runde WAYLAND-INPUT (09.10.2026): überholt.** `wayd` wartet jetzt in
einem `poll` über den Lauschsocket und alle Clientsockets (Kapitel 11,
„Leerlauf“); die Aussage unten gilt für die frühere Fassung.

**Ehrlich zu den 0 Marken (frühere Fassung):** `wayd` benutzte eine **beschäftigte Schleife**
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
2. **`wl_data_device`** — **gebaut in Runde WAYLAND-INPUT** (Kapitel 11).
   Ohne Zwischenablage zwischen Programmen ist ein Browser kaum benutzbar.
3. **Tastatur und Zeiger wirklich** — **gebaut in Runde WAYLAND-INPUT**
   (Kapitel 11; offen bleiben Mausrad-Achsen, Touch und Zeigersperre).
   Der alte Stand war: `wl_seat` **meldet** beide, aber die
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
* ~~**`wayd` dreht eine beschäftigte Schleife**~~ — erledigt in Runde WAYLAND-INPUT (`poll`).
* **(`wl_data_device` ist seit Runde WAYLAND-INPUT da.) Kein `wl_touch`, kein `wl_subsurface`, kein
  `xdg_popup`**, keine Skalierung, keine Transformation.
* ~~**Tastatur und Zeiger sind angekündigt, aber nicht verdrahtet.**~~ — erledigt in Runde WAYLAND-INPUT (Kapitel 11).
* **Höchstens 4 Clients und 16 Speicherobjekte** gleichzeitig.
* **`svc disable wayd` mit Foto und Gegenprobe** ist als Zusage
  verlangt, aber nicht gemessen — die Dienstzeile ist eingehängt, der
  Lauf mit `init` steht aus.

---

## 11. Keyboard, pointer, clipboard (round WAYLAND-INPUT, 09.10.2026)

Until now `wayd` offered a seat and a window; a key or a click of the window server reached a Wayland program only as a raw evdev code and
nobody could copy and paste. Now a real libwayland client gets a keyboard with a **keymap**, **focus**, **serials** and **modifiers**, a
pointer with **enter / motion / button / frame / leave**, and a **clipboard** that works between Wayland clients and with the OrientOS system
clipboard in both directions. Acceptance: `bash tools/wayland/input.sh` (WL-INPUT, real input over the QEMU monitor, a real
libwayland-client program, keysyms checked by libxkbcommon on the host) and `bash tools/wayland/run.sh` (generators, keymaps).

### 11.1 Where the code is

| File | What |
|---|---|
| `kernel/user/wl_msg.fi` | writes one event into a client's output region (head, arguments, string, size) -- shared by the two modules below |
| `kernel/user/wl_input.fi` | window server events -> `wl_keyboard` / `wl_pointer` events; the keymap descriptor; serials; focus |
| `kernel/user/wl_data.fi` | `wl_data_device_manager`, `wl_data_device`, `wl_data_source`, `wl_data_offer`; the bridge to the system clipboard |
| `kernel/user/wl_keytab.fi` | **generated** by `tools/wayland/genkeys.py` from the host's libxkbcommon: character -> (evdev key, modifiers) for `us` and `de` |
| `kernel/user/wlproto.fi` | generated as before; `tools/wayland/gen.py` got four more interfaces (`LIMIT`) and `wl_data_device_manager` v3 |
| `kernel/user/wayd.fi` | thin: object table, sockets, the descriptor queue, one `poll` instead of a busy loop, hooks into the three modules |
| `tools/wayland/wlin.c`, `idle.c`, `keycheck.py`, `input.sh` | the test client (libwayland 1.21, xdg-shell, static musl), the system call counter, the host-side keysym check, the acceptance |

`wm.fi` and `wmd.fi` were **not touched**: wayd only uses what the window server already offers (`WM_EVENT`, `WM_INFO`).

### 11.2 The keyboard

The window server does not deliver key codes, but **characters**, and never a key release: `A` is one `E_KEY` with 65, Ctrl+C is 3, and
the special keys come the way a terminal sends them, one octet per event (`ESC [ A` = arrow up, `ESC [ 3 ~` = Delete, `ESC [ 20 ~` = F9,
`ESC [ 1 ; 2 D` = Shift+Left). `wl_input.fi` puts these together (a lone ESC is the Escape key after 50 ms), maps them to evdev codes with the
generated table, and makes the events a keyboard would: the modifier key presses, `wl_keyboard.modifiers`, the key press and release, the
modifiers released. UTF-8 octets of the German layout (`ö` = 0xC3 0xB6) are assembled.

* **The keymap** is a memfd with the xkb text compiled by libxkbcommon (`xkb_keymap_get_as_string`, 64 KB for `us`, 66 KB for `de`), sent
  with `SCM_RIGHTS` **out of** wayd (`send_fd_msg`). It lives in `/usr/share/wayd/keymap-<us|de>.xkb` next to wayd (the package/image
  provides it; `genkeys.py --keymaps <dir>` makes it). If the file is missing the client gets `no_keymap` and raw codes (the test
  `tools/actionbus/gui.sh` runs like this). The layout in force is the kernel's (`SYS_OSUM_KBD`); **Ctrl+Alt+L** makes wayd send every keyboard the new keymap.
* **The host check:** the key and modifier events a client logged are fed into libxkbcommon on the host (`tools/wayland/keycheck.py`),
  the way a client does it: `A 1 exclam Ctrl+c Return Left Up Delete` on `us`, `y odiaeresis exclam` for z, ; and Shift+1 on `de`.
* **Focus:** `E_FOCUS` of the window server -> `wl_keyboard.enter` / `leave` with serials and an empty key array; a window that is already
  focused when the client calls `get_keyboard` gets its `enter` at once. Only the focused client gets keys.
* **`repeat_info`** (25 / 400 ms, seat version 4 and up) and `wl_seat.name` (`seat0`).

### 11.3 The pointer

`E_MOVE`, `E_DOWN`, `E_UP` carry window-local coordinates; wayd sends `wl_pointer.enter` once, `motion`, `button` (BTN_LEFT / BTN_RIGHT,
evdev 272 / 273) and `frame`, coordinates as 24.8 fixed point. The window server reports motion only **inside** a window, so wayd polls
the pointer position (`WIG_SCREEN` mouse position against `WM_INFO` position, border and size of the window) and sends `leave` itself.
**Not built:** `axis` (the window server has no wheel events at all), `axis_source`, touch, `set_cursor` (accepted, no effect), pointer
constraints. A window hidden under another one still thinks it is hovered until the pointer leaves its rectangle.

### 11.4 The clipboard

One selection exists: **none**, **WL** (a Wayland client owns it) or **SYS** (the OrientOS clipboard of the bus changed, by someone
else). Every client with a data device **and keyboard focus** is told (`data_offer`, `offer` x n, `selection`), again each time it gets the focus,
**never while the screen is locked**.

* **client -> client:** `offer.receive(mime, fd)` -> wayd passes the descriptor on to the owner with `wl_data_source.send(mime, fd)`
  (`SCM_RIGHTS`, like `wl_shm` in the other direction). The text never sits in the server.
* **WL -> system:** at `set_selection` wayd asks the source to send its text into a pipe of its own, reads it **without blocking** (zero timeout
  `poll` per round, 3 s limit) and puts it into the OrientOS clipboard (bus op 10, type text). A native program can paste it.
  The system clipboard holds 192 octets inline; a longer text reaches other Wayland clients whole but is cut there.
* **system -> WL:** every round the newest clipboard item is read (bus op 11 with the meta block: pid, sequence); a new sequence from
  another pid is the selection now, a Wayland owner is told `cancelled`. `receive` on it writes the text into the client's pipe (polled, bounded).
* **Rules:** `set_selection` only with a serial this server gave **that client** after its latest keyboard enter, and only with focus
  (`wl_input.serial_ok`); anything else is ignored and the source gets `cancelled`. A source that is replaced gets `cancelled`. A client that
  **exits** empties the selection it owned. `start_drag` gets `cancelled` (no drag and drop). Text only, one data device per client.
* A descriptor a client sends **per request** is now taken from a **queue** (`fdq`): several `receive` calls in one burst each get theirs
  (before, `taken_fd` handed over only the first descriptor of a `recvmsg`).

### 11.5 Idle, and one thing that was a hang

* **`poll` instead of a busy loop.** One `poll` over the listening socket and all client sockets; with a window open (events must be
  fetched from the window server, which has no descriptor to wait on) the timeout is 10 ms (the kernel rounds up to 20), without a window
  200 ms -- a connecting or writing client wakes it at once. The idle clock of the on-demand start counts **ticks** now
  (the old unit, a round of about half a millisecond, is converted: `leer / 20` ticks).
* **`sendmsg` does not block any more** (`MSG_DONTWAIT`, partial writes keep the rest). Before, a client that did not read could stop the whole server in a
  blocking `sendmsg`; with transfers between clients that would have happened to the clipboard first. A client that does not read gets no
  more answers (`recv_into` waits) instead of overflowing its output region.

### 11.6 Measured (tools/wayland/input.sh, one boot, real input)

`bash tools/wayland/input.sh`: **66 passed, 0 failed** (QEMU, KVM, three `wlin` programs, host input over the monitor):

| What | Result |
|---|---|
| keymap | all three clients got `fmt=1 size=64434 crc=0x33fc972e` = the file the host compiled (65 KB, `us`); `repeat_info 25/400`; seat `seat0`, version 5, caps 3 |
| focus | B (newest window) got `enter` at once and the key `a` as evdev 30 press + release; A and C got **nothing**; a click on A: A `enter`, B `leave` |
| pointer | A: `enter`, `motion` (40,30) when (40,30) was clicked, `button` 272 pressed/released, `frame`; `leave` when the pointer left; B, over which the pointer only passed, got no button |
| keysyms (libxkbcommon on the host) | `A 1 exclam Ctrl+c Return Left Up Delete` on `us`; every event of these keys has its own serial; Ctrl is xkb mask 4 |
| German layout | after Ctrl+Alt+L every keyboard got the 66 KB `de` keymap (`crc=0xa5928665`); z -> `y`, ; -> `odiaeresis` (UTF-8 over two octets), Shift+1 -> `exclam` |
| clipboard client -> client | A `set_selection` (serial of a key press), B pasted `hello-from-A` **through A** (descriptor passed on, `source.send ... wrote=12`) |
| clipboard -> system | after that a native system call reads `hello-from-A` from the OrientOS clipboard |
| clipboard system -> client | a native program set `native-says-hi`; B was offered it and pasted it; A (the owner before) got `cancelled` |
| counter-proofs | no `set_selection` -> `selection=none`; a serial that was never given -> refused, `cancelled`, nothing offered; the owner exits -> `selection=none` for the next client, no hang |
| locked screen | `osum_sperre`: no key, no pointer event (not even `leave`) reached the window; after the unlock keys arrive again; `tools/lockseal/run.sh` 43/0 as before |
| idle | wayd alone: **122** system calls of the whole system in 5 s (24 per second); the busy loop of before: **451 010** in 5 s (90 202 per second), measured with the same program (`BASE_WAYD=<old elf> IDLE_ONLY=1 bash tools/wayland/input.sh`); three windows open and nobody touching: 4 684 in 5 s |

Other gates run with this change: `tools/wayland/run.sh` **52 passed, 0 failed** (was 45; the new ones: modules present, key table and keymaps generated and
compiled, `wl_data_device_manager` known), `tools/actionbus/gui.sh` **67 passed, 0 failed** (a real Wayland program on wayd steered by the
action bus -- the old keymap-less path, `no_keymap`, still works), `tools/lockseal/run.sh` **43/0**, `tools/a11y/run.sh` **58/0**.
Nothing outside Ring 3 (`wayd` and its test tools) was changed, so the other gates of the system (wm, k15, alltag, fourbugs, softui,
themestore, comp) cannot move and were not run for this change.

### 11.7 What the measurement found (and what was changed because of it)

1. **Arrow keys, Delete and F-keys arrive as escape sequences, one octet per event, and plain Up is the octet 14 (= Ctrl+N).** The first
   run delivered `ESC`, `[`, `2`, `0`, `~` as five keys. Now a small state machine decodes them (`csi_key`), Ctrl+N and Ctrl+H come as
   `ESC [ 31 ; 5 ~` / `ESC [ 30 ; 5 ~` from the kernel and stay Ctrl+N / Ctrl+H.
2. **The pointer enters where it first touches the window**, not where the click is: the test's relative mouse walks over other windows on
   its way. The check looks at the last motion before the button.
3. **A locked screen must also hide that the pointer left a window**: `leave` is not sent while locked.
4. **`osum_sperre`: op 1 locks, but only the registered locker can unlock** -- a test program has to call op 4 first.
5. **KERNEL, NOT FIXED: a client that dies by a fault keeps its socket until somebody `wait`s for it.** `exit` closes the descriptors
   (`sock_close_all`), a process killed by SIGSEGV becomes a zombie and its descriptors are closed only in `proc.reap` (`file.close_all`, which
   bypasses `unref_of`, so a `K_USOCK` is not even released there). wayd then never sees the end of the connection: the dead client's
   window and its selection stay. Measured (run of the 09.10.2026 with a client that wrote to address 0): the selection of the dead owner is still offered
   and a paste yields nothing; no `Client gegangen` line from wayd. The fix belongs to the kernel (close descriptors at death, not at reaping); roadmap item.

### 11.8 Open

* no `axis` events (no wheel in the window server), no touch, no `wl_subsurface`, no drag and drop;
* the clipboard is text only and 192 octets in the system clipboard; one data device per client;
* a fault-killed client (see 11.7, 5);
* the keymap files must be in the image (`/usr/share/wayd/`); the package recipe lists them;
* the key tables are `us` and `de` (the layouts of the kernel); characters outside them (`é` on `us`) are dropped;
* **Alt** works only as the xterm `ESC [ 27 ; 3 ~` form the kernel sends for Alt+Enter; Alt+letter does not exist in the window server.
