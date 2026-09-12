# Runde MERGE-5 — `avx` und `betrieb` nach `main`, und die zwei Dinge, die nur auf dem Blech zu prüfen sind

Arbeitsbaum `/root/osum-merge5`, Zweig `merge5`, abgezweigt von `main`
(`163984d`). Gemessen am 02.09.2026 auf dem üblichen Wirt (AMD EPYC
7571, Zen 1, 12 Kerne, 19 GiB, `/dev/kvm` vorhanden), QEMU 7.2.22.

**Zur Aussagekraft, und das gehört an den Anfang:** auf demselben Wirt
liefen während dieser Runde **zwei weitere vollständige Abnahmen**
fremder Runden (`/root/osum-blech` ab 09:30, `/root/osum-modul` ab
09:56) — Lastmittel zeitweise über 22, bis zu zwanzig QEMU-Prozesse, und
der Datenträger war um 12:20 für einige Minuten **voll** (405 MiB frei).
Deshalb wird hier jede rote Zusage **einzeln auf ruhigerem Wirt
nachgemessen**, genau nach dem Verfahren von MERGE-FINAL und MERGE-3.

---

## DIE RUNDE IN FÜNF ZEILEN

1. **`avx` ist drin** — konfliktfrei, und das war nachrechenbar, nicht
   gehofft.
2. **`betrieb` ist drin** — eine einzige gemeinsam berührte Datei, kein
   Konflikt.
3. **Drei Runden hatten ihre Zusagen in KEINER Abnahme.** AVX hatte gar
   keinen Läufer, OTA und BETRIEB waren nie in `test.sh` angemeldet. Der
   Läufer für AVX ist geschrieben (32 Zusagen), AVX und OTA sind
   angemeldet — und beim Anmelden fielen **zwei echte Fehler** heraus,
   die seit zwei Runden im Baum lagen, ohne dass etwas rot wurde.
4. **Das Update über einen NAMEN von einem ECHTEN Server läuft**:
   `https://store.fleitec.com/` — DHCP liefert den Nameserver, Osum löst
   den Namen selbst auf, prüft eine echte Let's-Encrypt-Kette (vier
   Zertifikate, Tiefe 3) und spielt ein signiertes Paket ein.
   **`tools/operation/store.sh`: 37 Zusagen, 0 rot** — mit der Gegenprobe,
   dass derselbe Lauf ohne die Runde AVX an einem `#UD` stirbt.
5. **AVX-512 ist auf diesem Wirt nicht messbar** und bleibt es. Dafür
   gibt es jetzt einen vierten Menüeintrag auf dem Stick und eine
   ausdruckbare Anleitung in `docs/AUFSETZEN.md`, Abschnitt 5.1.

---

## TEIL 1 — DIE ZWEI MERGES

### 1.1 `avx` → konfliktfrei, und zwar nachgerechnet

Der Bericht von MERGE-3 sagt voraus, dass `avx` sauber hineinpasst.
Diese Runde hat das **nicht geglaubt, sondern nachgesehen**, bevor sie
gemerged hat:

```
git merge-base main avx                    ->  94c12fd  (mergeline2, MERGE-2 18)
comm -12 <(git diff --name-only 94c12fd..main) \
         <(git diff --name-only 94c12fd..avx)   ->  LEER
```

`main` hat seit `mergeline2` **genau sieben Dateien** angefasst
(`docs/AUFSETZEN.md`, `docs/RUNDE-MERGE3.md`,
`docs/bilder/merge3-schreibtisch.png`, `tools/icons/run.sh`,
`tools/k15/run.sh`, `tools/vault/run.sh`, `tools/wm/run.sh`), `avx`
hat dreizehn — und **keine davon kommt in beiden Listen vor**. Der
Merge (`b109e20`) war deshalb kein Glück: er konnte gar nicht
kollidieren.

| | |
|---|---|
| Commits | 10 |
| Dateien | 13 (+2718 Zeilen, −8) |
| davon neu | `kernel/arch/x86_64/fpu.fi` (946), `tools/avx/cputab.sh` (144), `docs/RUNDE-AVX.md` (492) |

### 1.2 `betrieb` → eine gemeinsame Datei, kein Konflikt

```
git merge-base main betrieb                ->  b010f75  (MERGE-2 13)
comm -12 <(git diff --name-only b010f75..main) \
         <(git diff --name-only b010f75..betrieb)  ->  kernel/user/opk.fi
```

`main` hat seither 158 Dateien angefasst, `betrieb` 32, und die
Schnittmenge ist **eine einzige Datei**. Der Merge (`2f330d4`) lief
ohne Konflikt durch.

**Die im Auftrag vermuteten Berührungspunkte sind keine** — nachgesehen,
Datei für Datei:

| vermutet | Befund |
|---|---|
| `tools/ota/run.sh` | Gibt es auf `main` **gar nicht.** Die Runde OTA wurde nie nach `main` gemerged; MERGE-3 hat sie nur auf ihrem eigenen Zweig gesichert (`da48676`). `betrieb` bringt sie jetzt vollständig mit — `da48676` ist ein Vorfahr von `betrieb` |
| `kernel/netsvc.fi` | Auf beiden Seiten **Oktett für Oktett dieselbe Datei** (`git diff HEAD betrieb -- kernel/netsvc.fi` ist leer) |
| `kernel/user/dhcp.fi` | Nur `betrieb` hat sie angefasst (Option 6, `/etc/resolv.conf`) |
| `nprof.fi` | **Gibt es nicht** — weder auf `main` noch auf `betrieb`. `find . -name '*nprof*'` findet nichts |

Mit `betrieb` kommen also **zwei** Runden gleichzeitig herein: OTA
(4 Commits) und BETRIEB (17). Zusammen 32 Dateien, +9327 Zeilen.

---

## TEIL 1b — WAS DAS ANMELDEN DER LÄUFER ANS LICHT GEBRACHT HAT

Das ist das Ergebnis dieser Runde, das nicht im Auftrag stand.

### Der Befund: 116 Zusagen, die in keiner Abnahme standen

```
grep -rn vecproc tools/          ->  auf Zweig avx: NULL Treffer
grep -n 'ota/run.sh' test.sh     ->  auf Zweig betrieb: NULL Treffer
grep -n 'betrieb/run.sh' test.sh ->  auf Zweig betrieb: NULL Treffer
```

Die Runde AVX hat zehn Commits und einen Bericht von 492 Zeilen, in dem
jede Zahl gemessen ist — **und keinen Läufer.** Ihr eigentlicher
Nachweis („kein Prozess sieht je die Vektorregister eines anderen")
wurde von Hand gefahren und war ab dem nächsten Commit eine Behauptung.
`tools/ota/run.sh` gibt es, aber `test.sh` kannte ihn nicht. Es ist
derselbe Schaden, den MERGE-2 bei `usbimg`, `themestore` und `softui`
gefunden hat: **ein Läufer, der nicht angemeldet ist, misst nichts.**

### Was diese Runde daran gemacht hat

**`tools/avx/run.sh` (neu, 32 Zusagen, 50 s).** Er fährt die Messungen
aus `docs/RUNDE-AVX.md`, Abschnitt 3, nach — mit denselben Kernwörtern
und gegen dieselben Zeilen:

| Abschnitt | was gemessen wird | Ergebnis auf diesem Wirt |
|---|---|---|
| 1 | Vektoranweisungen im Kernabbild **außerhalb** der Probe | 0 (die 149 im Abbild liegen alle in `u_vec*`/`u_xmm*`/`u_ymm*`/`u_zmm*`/`fpu__vec_*`) |
| 2 | CR4 Bit 9/10/18, `mode`, `xcr0`, `size` gegen `need` | `cr4=0x340620`, `mode=3`, `xcr0=0x7`, `size=832 = need=832` |
| 3 | vier Prozesse, 64 Runden, zwei `sched_yield` je Runde | `vec: sum=0`, `clean=1`, viermal `bad=0`, `forkbad=0`, `saves=2935 restores=2934` |
| 4 | **Gegenprobe** `nofpuswitch` (freigeschaltet, nicht gesichert) | `vec: sum=1000`, `clean=0` — sie wird rot, also misst Abschnitt 3 etwas |
| 4 | **Gegenprobe** `nofpu` (der Stand vor der Runde) | `user fault: vector=6` (#UD) |
| 5 | CR4 ist pro Prozessor, `-smp 4` | `vecsmp: cores=4`, `clean=1` |
| 6 | **Gegenprobe** `noavx` | `xcr0=0x3`, `width=1`, trotzdem `clean=1` |
| 7 | XCR0 verlangt kein Bit, das `cpuid` nicht anbietet | `xcr0=0x7 ⊆ sup=0x7` |

**Und zwei echte Fehler, die erst dadurch sichtbar wurden:**

**(a) `tools/ota/run.sh` baute nicht mehr.**

```
  FAIL  fetch.fi baut nicht
error: cannot read 'kernel/app/libc/dns.fi': No such file or directory
   --> kernel/app/fetch.fi:88:1   |   import libc.dns
```

Die Runde BETRIEB hat `kernel/app/fetch.fi` den Auflöser aus
`lib/libc/dns.fi` importieren lassen und `tools/install/build.sh` dafür
auf `FIRNLIB="$ROOT/lib"` umgestellt (dort Zeile 101) — **die Probe in
`tools/ota/run.sh` (Zeile 158) wurde dabei übersehen** und stand weiter
auf `FIRNLIB="$ROOT/vendor/firn/lib"`. Der Fehler lag seit der Runde
BETRIEB im Baum, ohne dass irgendetwas rot geworden wäre, weil ihn
nichts fuhr. Behoben; die Bibliothek von Firn geht dabei nicht verloren
(der Übersetzer sucht immer auch in `<Übersetzer>/../lib`).

**(b) Drei rote Zusagen für eine Sache, die das Gerät richtig macht.**

```
  FAIL  opk prueft die Signatur ein ZWEITES Mal -- 'opk: Signatur geprueft' fehlt
  FAIL  und ist bestaetigt -- 'opk: erprobung bestaetigt' fehlt
  FAIL  und wird bestaetigt -- 'opk: erprobung bestaetigt' fehlt
```

`kernel/user/opk.fi` druckt seit Runde UMLAUT2 (Zeilen 157 und 164)
`opk: Signatur geprüft` und `opk: erprobung bestätigt` — **mit echten
Umlauten**. Der Läufer suchte weiter nach der ASCII-Umschrift. Das ist
keine entschärfte Zusage: gesucht wird dieselbe Meldung, nur so
geschrieben, wie sie wirklich auf der Leitung steht. Nachgemessen an
einem echten Lauf gegen `store.fleitec.com`:

```
opk: Signatur geprüft /tmp/ota/INDEX.sig
opk: Signatur geprüft /tmp/ota/hallo-2.opk
```

### Was NICHT angemeldet wurde, und warum

`tools/operation/run.sh` ist **nicht** in `test.sh` aufgenommen. Er setzt
`tools/operation/vorbereiten.sh` voraus (Pakete, Zertifikate,
Schlüsselbund, vier Auslieferungen, ein Abbild und eine **in QEMU
installierte Platte**, zusammen deutlich über zehn Minuten) und misst
gegen **echte Namen bei echten Nameservern**. Das gehört in eine
Abnahme, sobald der Läufer seine Vorbereitung selbst herstellt; solange
er sie nur behauptet, wäre der Abschnitt auf einem frischen Baum
zuverlässig rot. Er steht unter „was noch fehlt".

---

## TEIL 2 — DAS NEUE ABBILD

```
bash tools/usbimg/build.sh /tmp/usbimg5
```

Das Skript baut Übersetzer, Kern, Ring-3-Programme, Symbole und das
OFS-Dateisystem neu und prüft die Pflichtpfade selbst nach.

| | MERGE-3 | **MERGE-5** | Unterschied |
|---|---:|---:|---|
| Abbild | 123 731 968 Oktette (118 MiB) | **123 731 968 Oktette (118 MiB)** | **0** |
| SHA-256 | `1bf0609d12be8830f7ed59580f1a77a5e79ff83c1aaf117a6b914981b4df1031` | **`16a188f1266f937ecdbb9073e4cc3e0a4e518ba251ae0cbe5f5eab775b542719`** | anders |
| Kern | 3 313 608 Oktette | **3 363 920 Oktette** | **+50 312 (+1,52 %)** |
| Ring 3 | 43 Programme | **43 Programme** | 0 |
| Wurzel | 20 971 520 Oktette, OFS v3 | **20 971 520 Oktette, OFS v3** | 0 |
| Symbole | — | 11 Stück nach `/etc/netview/` | — |
| Pflichtpfade nachgezählt | 24 | **24** | 0 |
| Umlaute im Wurzelabbild | 126 UTF-8-Folgen | **129 UTF-8-Folgen** | **+3** |
| Aufteilung | GPT, EFI 96 MiB + Wurzel 21 MiB | **dieselbe** | 0 |
| Menüeinträge | 3 | **4** | **+1** (Vektoreinheit prüfen) |

**Warum die Größe gleich bleibt, obwohl der Kern wächst:** das Abbild
ist eine GPT-Platte mit fester Aufteilung (EFI 96 MiB, Wurzel 21 MiB);
der Kern liegt in der 96-MiB-EFI-Partition und hat dort reichlich Platz.
Erst wenn er die füllt, wächst die Datei.

**Woher die 50 312 Oktette kommen:** aus `kernel/arch/x86_64/fpu.fi`
(946 Zeilen neu), den Erweiterungen in `sched.fi`, `tasks.fi`,
`uprog.fi`, `kstate.fi` und `kmain.fi` der Runde AVX, plus
`hwdiag.park_if_asked` dieser Runde. Der Kern der **Runde BETRIEB**
steckt nicht darin — deren Programme (`ota`, `host`, `dnswt`) sind
Ring-3-Programme und stehen nicht in der Programmliste des Sticks
(siehe „was noch fehlt").

**Woher die drei Umlaute kommen:** aus `kernel/user/dhcp.fi`, das die
Runde BETRIEB um die Auswertung von DHCP-Option 6 und das Schreiben von
`/etc/resolv.conf` erweitert hat — mitsamt deutscher Meldungen.

### Beide Startwege, gemessen

`bash tools/usbimg/run.sh` → **`USBIMG: 46 bestanden, 0 gescheitert`**,
unter `-accel kvm -cpu host`, also auf der echten CPU.

| Weg | Beleg |
|---|---|
| **BIOS** | „der Kern startet unter BIOS von dem Abbild"; `hwdiag: firmware=BIOS`; der Diagnose-Eintrag hält an, und danach kommt kein `kernel: done` mehr |
| **UEFI** (OVMF) | „derselbe Kern startet unter UEFI"; **kein** „Cannot use text mode with UEFI"; `hwdiag: firmware=UEFI`; die Firmware setzt den Rahmenpuffer: `fb 1280x800` |
| Plattencontroller | mit `-device ahci` meldet die Diagnose **AHCI**, mit `-device ide-hd` **IDE** |
| Netzkarten | Intel → `e1000`, virtio → `virtio-net`, `rtl8139` → `no driver for 0x10ec:0x8139`, und der Kern läuft danach weiter |

### Die Diagnose, aus dem BIOS-Lauf DIESES Abbilds

Neu darin sind die letzten drei Zeilen vor `ANGEHALTEN` — vorher hielt
der Eintrag an, bevor sie gedruckt waren:

```
hwdiag: ==================== OSUM HARDWARE-DIAGNOSE ====================
hwdiag: firmware=BIOS  vgarom=0xc0000  smbios=0xf59f0  rsdp=0xf59d0
hwdiag: cpu vendor=AuthenticAMD  hersteller=AMD
hwdiag: cpu family=23  model=1  stepping=2  maxleaf=0xd
hwdiag: cpu brand=AMD EPYC 7571 32-Core Processor
hwdiag: mem usable=2096639 KiB  top=0x7ffe0000  frames=524256
hwdiag: fb 1280x800  bpp=32  pitch=5120  src=multiboot  phys=0xfd000000  cols/rows=160/50
hwdiag: pci devices=6
hwdiag: pci 00:01.1 8086:7010  class=01 sub=01 prog=80
hwdiag: pci 00:03.0 8086:100e  class=02 sub=00 prog=00
hwdiag: disk IDE    bdf=0x9 8086:7010
hwdiag: net -- was netdev daraus macht:
hwdiag: ==================== ENDE DER DIAGNOSE ========================
guard: cr4=0x340620  smep=1  smap=1  cpu=1/1
fpu: mode=3  cr4=0x340620  xcr0=0x7  size=832  lazy=0
fpu: f1c=0xfff83203  f1d=0x78bfbff  f7b=0x209c01ab  sup=0x7  need=832
vec: skipped
hwdiag: ANGEHALTEN. Der Bildschirm bleibt so stehen.
```

`vec: skipped` steht da, weil auf **diesem** Eintrag das Wort `vecproc`
fehlt — dafür ist Eintrag 4 da.

### Das Bild

`docs/bilder/merge5-schreibtisch.png` — der deutsche Schreibtisch aus
**diesem** Abbild, 800×600, aufgenommen von `tools/usbimg/run.sh`. Der
Läufer misst darin bildpunktgenau nach, dass die Beschriftungen echte
Umlaute tragen (u. a. `Ausführen`, und `kein Netz` in der Taskleiste bei
x=561, Grundlinie 591: 100 % der 63 Tintenpunkte und 100 % der 234
Gegenpunkte).

---

## TEIL 3 — DIE ZWEI DINGE, DIE NUR AUF DEM BLECH ZU PRÜFEN SIND

### 3.1 AVX-512 — die Anleitung, und der Weg, sie überhaupt ablesen zu können

`docs/RUNDE-AVX.md`, Abschnitt 8, Punkt 1: der Weg für AVX-512 ist
gebaut und durch `cpuid` verriegelt, aber **auf diesem Wirt nicht
auslösbar** — Zen 1 hat es nicht, QEMUs TCG kennt es nicht. Nachgemessen
in dieser Runde, damit es nicht bei der Behauptung bleibt:

```
fpu: mode=3  cr4=0x340620  xcr0=0x7  size=832  lazy=0
fpu: f1c=0xfff83203  f1d=0x78bfbff  f7b=0x209c01ab  sup=0x7  need=832
```

`sup=0x7` ist `cpuid` Blatt 0x0D, Unterblatt 0, EAX — **die Maschine
bietet AVX-512 nicht an**, und Osum nimmt genau das, was sie anbietet.
Auf einer Maschine mit AVX-512 stünde dort `sup=0xe7`, `xcr0=0xe7` und
`size` um 2700.

**Beim Schreiben der Anleitung ist ein Fehler aufgefallen, der sie
wertlos gemacht hätte.** Der Eintrag „Hardware-Diagnose (bleibt stehen)"
auf dem Stick hielt an, **bevor** die `fpu:`-Zeilen gedruckt waren:
`hwdiag.stage` steht in `kernel_main` bei Zeile 333, `fpu.apply` bei
351 und `fpu.report` bei 369. Auf einem Rechner **ohne serielles Kabel**
— und genau für den ist dieser Eintrag da — waren die zwei Zeilen also
nicht zu bekommen.

Behoben, und die Begründung steht im Quelltext: `hwdiag.stage` **druckt
nur noch**, das Anhalten macht `hwdiag.park_if_asked`, und das ruft
`kernel_main` hinter `fpu.report` **und hinter der Vektorprobe** auf.
Dazwischen liegt keine Gerätesuche (`netsvc.stage` bei 467, `hw.disk`
bei 494) — der Grund, aus dem der Bericht früh gedruckt wird, bleibt
also unangetastet.

Dazu ein **vierter Menüeintrag** in `tools/usbimg/build.sh`:

```
/Osum -- Vektoreinheit pruefen (bleibt stehen)
    cmdline: hwdiag hwdiagstop vecproc gfx nokbd nosched noproc nofs noring3
```

Gemessen an genau diesem Abbild (`-cpu host`, KVM, echte CPU), gekürzt:

```
hwdiag: cpu brand=AMD EPYC 7571 32-Core Processor
hwdiag: ==================== ENDE DER DIAGNOSE ========================
guard: cr4=0x340620  smep=1  smap=1  cpu=1/1
fpu: mode=3  cr4=0x340620  xcr0=0x7  size=832  lazy=0
vec: begin
vec: pid=3   vec: arg=1   vec: width=2
   ... (viermal)
vec: rounds=64   vec: bad=0     (viermal)
vec: forkpid=7   vec: forkbad=0
vec: exit=0 0 0 0
vec: sum=0
vec: clean=1
hwdiag: ANGEHALTEN. Der Bildschirm bleibt so stehen.
```

Die Anleitung selbst steht in **`docs/AUFSETZEN.md`, Abschnitt 5.1**
(neu, zum Ausdrucken): welche vier Zeilen abzulesen sind, eine Tabelle
„was gut ist", eine Tabelle „was jeder andere Befund bedeutet"
(`xcr0=0x7` → kein Fehler, die Maschine hat es nicht; `sup=0xe7` bei
`xcr0=0x7` → Fehler in `fpu.probe`, melden; `vec: bad≠0` → der
schwerste Befund, melden und die Maschine nicht benutzen;
`vector=6` → die Freischaltung hat nicht gegriffen) — und die
Gegenprobe, mit der der Eigner sich selbst überzeugen kann, dass die
Nullen etwas wert sind (`nofpuswitch` an die Kommandozeile hängen).

### 3.2 Die Update-Kette gegen einen ECHTEN Server

**`https://store.fleitec.com/`** — Let's-Encrypt-Zertifikat, ausgeliefert
vom systemd-Dienst `orientstore` aus `/srv/store`. Was daran anders ist
als am Prüfstand, und warum es die Mühe wert war:

| | Prüfstand (`tools/ota/server.py`) | store.fleitec.com |
|---|---|---|
| Zertifikat | selbst erzeugt, **eine Minute alt** | Let's Encrypt, gültig 01.09.–30.11.2026 |
| Kette | **1 Zertifikat**, Tiefe 1 | **4 Zertifikate**, Tiefe 3: `store.fleitec.com` ← `YE1` ← `Root YE` ← `ISRG Root X2` (← `ISRG Root X1`) |
| Schlüssel | RSA-2048 | **ECDSA P-256**, Signatur `ecdsa-with-SHA384` |
| Wurzelspeicher im Abbild | die selbstgemachte Wurzel | **11 Mozilla-Wurzeln** aus `tools/hwnet/mkroots.py` (15261 Oktett) |
| Adresse | `10.0.2.2` (fest) | ein **Name**, aufgelöst vom Gerät |
| Nameserver | von Hand in `/etc/resolv.conf` | **von DHCP** (Option 6) |
| Weg | localhost | echtes Internet, HTTP/2-fähiges openresty davor |

**Der Läufer: `tools/operation/store.sh` (neu). 37 Zusagen, 0 rot.**
Er ist **absichtlich nicht in `test.sh` angemeldet** — er schreibt auf
einen echten Server und braucht das offene Internet; eine Abnahme, die
ohne fremde Infrastruktur nicht grün werden kann, ist keine Abnahme.

Die Kette, Glied für Glied, aus dem Protokoll des Laufs:

```
dhcp: offer ip=10.0.2.15  maske=255.255.255.0  gateway=10.0.2.2
dhcp: /etc/resolv.conf geschrieben, dns 1
   -> nameserver 10.0.2.3                (Option 6, Runde BETRIEB)
osum$ host store.fleitec.com
109.69.172.199                            (dig auf dem Wirt: dasselbe)
osum$ ota einspielen
ota: quelle https://store.fleitec.com/osum/aktuell
fetch: aufgeloest 1833282759              ( = 109.69.172.199 )
fetch: roots 11
fetch: verify OK
fetch: suite 4865                         ( TLS_AES_256_GCM_SHA384 )
fetch: certs 4    fetch: depth 3
ota: fassung hier 0        ota: fassung dort 2
ota: platz 56902144        ota: noetig 102873
ota: streuwert stimmt hallo-2.opk
opk: Signatur geprüft /tmp/ota/INDEX.sig
opk: Signatur geprüft /tmp/ota/hallo-2.opk
opk: installiert hallo -> 0
ota: BEREIT ZUM NEUSTART -- es wird NICHT
osum$ ota zeigen
ota: fassung hier 2
```

**Und die Gegenprobe, die das Ganze erst zu einem Nachweis macht.**
Derselbe Lauf, dasselbe Abbild, derselbe Server, nur das Kernwort
`nofpu` daneben — also **genau der Zustand vor der Runde AVX**:

```
fpu: mode=0  cr4=0x300020  xcr0=0x0  size=0  lazy=0
fetch: aufgeloest 1833282759              (der Name wird noch aufgeloest -- das ist BETRIEB)
fetch: roots 11
user fault: pid=7  vector=6  err=0x0  rip=0x40141c06  -- process killed
ota: nicht zu holen: VERZEICHNIS
osum$ ota -> 1
```

Das ist Wort für Wort die Vorhersage aus `docs/OTA.md` („AVX-512 tötet
`/bin/fetch`"), zum ersten Mal **gegen einen echten Server im Internet**
gemessen — und daneben derselbe Lauf, der mit der Runde AVX durchgeht.
Die zwei hereingeholten Runden sind damit nicht nur beide drin, sondern
**in einer Messung voneinander abhängig**: ohne AVX kein Update, ohne
BETRIEB kein Name.

#### Was am Store abgelegt wurde — und was nicht

* `/srv/store/osum/` — die Auslieferung, genau so, wie
  `tools/ota/veroeffentlichen.py` sie schreibt: `aktuell/` (7 Dateien),
  `v/1/`, `v/2/`, `pakete/` (inhaltsadressiert), `register.json`,
  `journal.txt`, `gesperrt.txt`. Der Dienst liefert sie als gewöhnliche
  Dateien aus; `curl` holt `VERZEICHNIS` und `VERZEICHNIS.sig` mit
  HTTP 200, Oktett für Oktett dasselbe, was veröffentlicht wurde.
* **Ein Eintrag im Katalog**, über den vorgesehenen Weg:
  `python3 werkzeug/store --repo bau/repo add <datei>.opk` und
  `... publish /srv/store`. Der Katalog ging von **Revision 18 auf 19**
  (und mit dem zweiten Lauf des Läufers auf 20); `opk:hallo` hat jetzt
  zwei statt einer Fassung. **Entfernt wurde nichts**: die vier Pakete
  `com.fleitec.certus` (5 Fassungen), `com.fleitec.orientstore` (1),
  `com.fleitec.probe` (2) und `opk:hallo` stehen unverändert da, und
  `store verify` sagt danach „Signatur gültig (beide Umsetzungen einig),
  10 Dateien geprüft, Ergebnis in Ordnung".

#### Zwei Befunde, die dieser Server hergegeben hat und der Prüfstand nicht

1. **`Range` kann dieser Auslieferungsplatz nicht.** `python3 -m
   http.server` beantwortet `Range: bytes=100-199` mit **`200` und der
   ganzen Datei** statt mit `206`. Der Prüfstand (`tools/ota/server.py`)
   kann `206` ausdrücklich, weil die Runde OTA die Wiederaufnahme daran
   gemessen hat. `/bin/ota` fällt darauf nicht herein — genau dieser
   Fall steht im Kopf von `kernel/user/ota.fi` („ein Bruchstück, das
   länger ist als angekündigt, wird weggeworfen und neu geholt") —, aber
   **die Wiederaufnahme nach einem Abbruch kostet gegen diesen Server
   jedes Mal den ganzen Download.** Das ist eine Eigenschaft des
   Servers, keine des Geräts, und es gehört in `docs/OTA.md`.
2. **Ein halb überschriebener Auslieferungsplatz wird zu Recht
   abgelehnt** — und zwar hat das der erste automatische Lauf des
   Läufers selbst vorgeführt. Eine Musterliste im Kopierteil
   (`for f in hallo-*.opk ...`) wurde im **Arbeitsverzeichnis**
   aufgelöst statt im Auslieferungsverzeichnis und traf deshalb nichts;
   auf dem Server stand danach ein `VERZEICHNIS` aus dem neuen Lauf
   neben einer Paketsignatur aus dem alten, mit einem anderen
   Schlüssel. Das Gerät hat das gemerkt:

   ```
   opk: SIGNATUR FALSCH -- das Paket wird ABGELEHNT: /tmp/ota/hallo-2.opk
   ota: opk hat nicht installiert, Code 1
   ```

   Also genau das richtige Verhalten; der Fehler lag im Läufer. Er ist
   behoben (erst Nutzlast, dann `VERZEICHNIS`, **zuletzt** dessen
   Signatur), und der Läufer prüft seitdem selbst nach, dass jede Datei
   auf dem Server aus demselben Lauf stammt.

---

## DIE ABNAHME

Gefahren wurde **zweimal die volle Abnahme**, mit `OSUM_JOBS=4` und
`accel=auto` — dieselben Einstellungen wie bei der Grundlinie von
MERGE-3, damit die Zahlen vergleichbar sind:

| Lauf | Stand | Zeit | Protokoll |
|---|---|---|---|
| **A** | nach dem Merge von `avx` | 02.09. 08:23–10:34 (2 h 11 min) | `/root/m5logs/ABNAHME-A-avx.log` |
| **B** | nach dem Merge von `betrieb`, mit den drei neuen/berichtigten Läufern — **das ist der Stand von `main`** | 02.09. ab 11:25 | `/root/m5logs/ABNAHME-B-final.log` |

### Lauf A — `avx` allein

| | Abschnitte | grün | rot | Zusagen |
|---|---:|---:|---:|---:|
| Grundlinie MERGE-3 (`main` `163984d`) | 55 | 50 | 5 | 4309 |
| **nach `avx`** | **55** | **52** | **3** | **4327** |

Die Veränderungen gegenüber der Grundlinie, Abschnitt für Abschnitt —
und **alle bis auf eine sind Verbesserungen**:

| Abschnitt | MERGE-3 | Lauf A | Urteil |
|---|---|---|---|
| `GUARD` | 55 / 0 | **58 / 0** | +3 Zusagen: die Runde AVX hat die CR4-Prüfung auf **Bits** statt auf die ganze Zahl umgestellt (aus `0x300020` wurde `0x340620`) und dabei aus zwei Zusagen vier gemacht |
| `K15` | 249 / 3 | **252 / 0** | MERGE-3s Reparaturen halten |
| `TRESOR` | 212 / 7 | **220 / 0** | dito |
| `icons` | 15 / 12 | **25 / 0** | dito |
| `NETMON` | 75 / 1 | **76 / 0** | war in MERGE-3 als Lastphantom benannt — bestätigt |
| `NETVIEW` | 191 / 4 | **195 / 0** | **die offene Regression von MERGE-3 ist weg** — siehe unten |
| `MULTIUSER` | 91 / 0 | 90 / 1 | Lastphantom, in Lauf B wieder **91 / 0** |
| `tunnel`, `tunnelkosten` | grün | „rot" | **kein Fehler der Läufer** — beide melden intern `16 passed, 0 failed` bzw. `3 bestanden, 0 fehlgeschlagen`; der Harnisch hat ihr Ergebnis verloren (siehe „was noch fehlt", Punkt 5) |

### Lauf B — der Stand von `main`

Dieser Lauf lief unter der schwersten Fremdlast des Tages (Lastmittel
bis 44, bis zu vier fremde Abnahmen gleichzeitig, der Datenträger
zwischendurch voll). Er ist deshalb **roh** angegeben und daneben jede
rote Zusage einzeln nachgemessen.

### Jeder rote Abschnitt aus Lauf B, einzeln nachgemessen

| Abschnitt | Lauf B (unter Last) | einzeln, ruhiger Wirt | Urteil |
|---|---|---|---|
| `HANDLE` | 78 / 2 | **80 / 0** (zweimal) | **Last.** Die zwei roten sind Zyklenzähler (`lseek < 700`, `getpid < 450`). Gegenprobe: dieselbe Messung auf der **Grundlinie** `163984d` unter derselben Last gab **77 / 3** — also schlechter als dieser Zweig. Auf ruhigem Wirt gepaart gemessen: dieser Zweig `getpid 366 / lseek 527`, Grundlinie `355 / 512`, Leerschleife 9 gegen 8 |
| `K17` | 157 / 1 | **158 / 0** (zweimal) | **Last.** Die Grundlinie gab unter derselben Last ebenfalls 158 / 0 |
| `NET` | 74 / 1 | **75 / 0** | **Last.** Die eine rote ist ein Durchsatz durch 20 % Paketverlust (`237247`, erwartet `262144`) — einzeln grün, siehe unten |
| `NETVIEW` | 193 / 3 | — | **Last.** Der erste rote Haken ist `online: the kernel reported state: 2, expected eq 3` — die Maschine war gar nicht online, und die zwei anderen (`online: falsch 40 von 82`, `9c: … 599948 µs`) hängen daran. In Lauf A: 195 / 0 |
| `FSROBUST` | 27 / 4 | **30 / 0** | **Datenträger voll.** `FAIL corrupt.py` und `kaputte Abbilder gebaut: 11, erwartet ge 13` — der Läufer konnte seine Prüfabbilder nicht anlegen |
| `USBIMG` | 45 / 1 | **46 / 0** | **Last.** Zweimal rot mit **verschiedenen** Zusagen (einmal „der Diagnose-Eintrag hält nicht an", einmal „der Kern kommt nach der unbekannten Karte nicht mehr bis zum Ende") — beide Male ein abgeschnittener Lauf, kein Befund |
| `HWNETTLS` | 0 / 1 | **24 / 0** nach der Reparatur | **ECHT.** `fetch.fi does not compile` — derselbe `FIRNLIB`-Fehler wie in `tools/ota/run.sh`. Repariert, siehe Teil 1b |
| `OTA` | 104 grün / 5 rot | **107 grün / 0 rot** | **Datenträger voll.** Alle fünf roten liegen in Abschnitt (e); zwischen ihnen steht im Protokoll `No space left on device` — siehe unten |
| `UMLAUT2` | 45 / 3 | — | **ECHT, und nicht repariert.** Die eine offene Regression dieser Runde — siehe unten |

### Die eine offene Regression: `UMLAUT2` (45 / 3 statt 48 / 0)

Sie kommt **eindeutig** aus dem Merge von `betrieb`: in Lauf A (nur
`avx`) war der Abschnitt **48 / 0**, in Lauf B ist er 45 / 3, und
`tools/i18n/quellen.py` sagt genau, woran:

```
quellen: 58 Umschriften in kernel/**  --  SICHTBAR=24  MITSCHNITT=24  MARKE=10
  FAIL  SICHTBARE Umschrift in kernel/**: '24', erwartet '0'
  FAIL  marken rc: '1', erwartet '0'
```

**Alle 24 stehen in Dateien, die diese Zusammenführung neu hereingeholt
hat** (nachgezählt: 24 von 24) — `kernel/app/fetch.fi`,
`kernel/user/dnswt.fi` und vor allem `kernel/user/ota.fi`. Die Runden
OTA und BETRIEB sind von `mergeline2` abgezweigt, **bevor** UMLAUT2 dort
lag; ihre deutschen Sätze tragen deshalb noch die ASCII-Umschrift
(`laesst`, `Laenge`, `Schluessel`, `verfuegbar`).

Dazu ein zweiter, kleinerer Punkt: `kernel/user/ota.fi:134` erklärt den
Unterbefehl `C_ZUR = 'zurueck'`, und **nur** in dieser Schreibung — wer
`zurück` tippt, wird nicht verstanden. `kernel/user/opk.fi` macht es an
derselben Stelle richtig und nimmt beide.

**Warum diese Runde das NICHT repariert hat**, und das ist eine
Entscheidung und kein Vergessen: die 24 sind nicht alle gleich. Der
Prüfer kennt drei Klassen (SICHTBAR / MITSCHNITT / MARKE), und in der
Klasse SICHTBAR stehen hier **mindestens drei Zeichenketten, die
Umlaute NICHT bekommen dürfen**:

| Stelle | Inhalt | was es wirklich ist |
|---|---|---|
| `ota.fi:170` | `schluesselgen\t` | ein **Feldname im Dateiformat OTA2**. Mit Umlaut liest kein Gerät mehr ein VERZEICHNIS |
| `ota.fi:171` | `osum-schluessel\t` | dito, der Kettensatz des Schlüsselwechsels |
| `ota.fi:186` | `zurueck` | ein **Argument**, das an `/bin/opk` weitergereicht wird |

Ein Umbau, der die 21 echten Sätze auf Umlaute zieht, muss diese drei
gleichzeitig aus der Klasse SICHTBAR herausholen — sonst bleibt der
Abschnitt rot, nur mit kleinerer Zahl. Das ist eine eigene, kleine
Runde („UMLAUT3"): die 21 Sätze (byte-längenerhaltend, `ue`→`ü` sind in
UTF-8 wie `ue` zwei Oktette, die Puffer `[u8; N]` bleiben also gültig),
der Unterbefehl `zurück` neben `zurueck` in `ota.fi`, und für die drei
Formatwörter entweder ein eigener Klassenname im Prüfer oder eine
Trennung von Datei- und Bildschirmtext in `ota.fi`. **In dieser Runde
wäre das ein Eingriff in den Quelltext von zwei frisch gemergten
Runden, mitten in der Abnahme, an genau dem Programm, mit dem Teil 3.2
gemessen wird** — und dafür gibt es keine Not: die Meldungen sind
lesbar, nur nicht schön.

### `netview`: die offene Regression von MERGE-3 ist weg

MERGE-3 hat `netview` als einzige ungelöste Regression übergeben
(einzeln nachgemessen 192 / 3, verdächtigt wurde die Alpha-Mischung aus
Runde PAINT). In Lauf A dieser Runde steht:

```
NETVIEW: 195 passed, 0 failed
OK    online: the icon is on the screen at 561,578 -- ok 82 von 82 gleich
```

**82 von 82 statt 40 von 82 falsch.** Dazwischen liegt genau ein Merge:
`avx`. In Lauf B — unter schwerer Last — fiel dieselbe Zusage wieder,
und dort steht die Erklärung mit: `online: the kernel reported state:
2, expected eq 3`. Die Maschine war **nicht online**, also hat die
Leiste das richtige Zeichen für „keine Route" gezeichnet, und der
Prüfer hat es gegen die Maske für „online" gehalten — 40 von 82 passen
nicht. **Die zweite und die dritte rote Zusage sind Folgen der
ersten.**

Damit ist `netview` sehr wahrscheinlich nie ein Zeichenfehler gewesen,
sondern eine Zustandsfrage: die Maschine war zum Zeitpunkt der Aufnahme
nicht online. **Bewiesen ist das nicht.** Bewiesen ist: der Abschnitt
ist auf diesem Zweig auf ruhigem Wirt grün (195 / 0), und die 40 von 82
treten zusammen mit `state: 2` auf. Wer es zu Ende bringen will, prüft
in `tools/netview/run.sh`, ob die Zusage über das Zeichen erst nach
`state=3` genommen wird — dann kann sie nicht mehr aus dem falschen
Grund fallen.

### Die zwei Nachmessungen, die Lauf B noch schuldig war: `net` und `ota`

Beide Abschnitte standen in der Tafel oben mit einem Strich, weil sie zum
Zeitpunkt des ersten Berichtsentwurfs noch nicht einzeln gemessen waren.
Sie sind es jetzt, auf **ruhigem Wirt** (Lastmittel 2,7 statt über 20,
keine fremde Abnahme daneben, Datenträger nicht voll):

| Abschnitt | Lauf B (unter Last) | einzeln, ruhiger Wirt | Protokoll | Dauer |
|---|---|---|---|---|
| `NET` | 74 / 1 | **75 / 0** | `/root/m5logs/einzeln/net-m5.log` | 19:12–19:21 |
| `OTA` | 104 grün / 5 rot | **107 grün / 0 rot** | `/root/m5logs/einzeln/ota-m5-4.log` | 19:25–22:51 (3 h 26 min) |

**`net`.** Die eine rote Zusage in Lauf B war ein Durchsatz durch 20 %
künstlichen Paketverlust (`octets that arrived, all of them in order:
237247, expected eq 262144`) — eine Zeitzusage, und die einzige des
Abschnitts. Einzeln: `NET: 75 passed, 0 failed`, kein einziger roter
Haken, und das schließt die Zusagen des Auflösers aus der Runde BETRIEB
mit ein.

**`ota`.** Hier steht die Ursache **wörtlich im Protokoll von Lauf B**,
mitten zwischen den fünf roten Zusagen:

```
  FAIL  (e) Schuss 1 in Phase netz: die Maschine kommt NICHT mehr hoch (rc=)
  FAIL  Gegenstelle
cp: error copying '/tmp/ota-run/basis.img' to '/tmp/ota-run/ziel.img': No space left on device
```

Alle fünf roten Zusagen liegen in Abschnitt (e), dem Stromausfall mit 30
Schüssen, und alle fünf hängen an **diesem einen** fehlgeschlagenen
`cp`: ohne Zielabbild kommt Schuss 1 nicht mehr hoch, und daraus werden
`29, erwartet eq 30` (dreimal) und `kaputt=1`. Das ist kein Befund am
Zweig, sondern der volle Datenträger des Wirts um 12:20.

Einzeln, auf demselben Baum, ohne fremde Last:

```
  OK    (e) Schuesse, nach denen die Maschine ENTWEDER alt ODER neu ist: 30
  OK    (e) davon: nichts dazwischen und kein Ziegelstein: 0
  OK    (e) Schuesse, die ihre Phase wirklich getroffen haben: 30
        alt=20  neu=10  kaputt=0  Phase getroffen=30 verfehlt=0

  107 gruen, 0 rot
```

**30 von 30 Schüssen mitten ins Einspielen, und danach ist die Maschine
jedes Mal entweder ganz die alte oder ganz die neue** — kein
Ziegelstein, nichts dazwischen.

Dass der Unterschied wirklich der Wirt war und nicht der Baum, sagt
dieselbe Messung noch einmal in Millisekunden. Der Läufer misst den
Einspielvorgang **in der Maschine** mit, und dieselben vier Marken
brauchten unter Last durchweg länger:

| Marke | Lauf B (unter Last) | einzeln | Unterschied |
|---|---:|---:|---:|
| Firmware → Netz | 10 946 ms | **9958 ms** | −9,0 % |
| → Paket geprüft | 15 622 ms | **14 064 ms** | −10,0 % |
| → geschrieben | 28 542 ms | **19 378 ms** | **−32,1 %** |
| → bereit zum Neustart | 28 641 ms | **19 451 ms** | **−32,1 %** |
| Rückfallstart (der Start, in dem der Kern zurückschaltet) | 63 101 ms | **55 777 ms** | −11,6 % |

Der größte Sprung liegt genau dort, wo geschrieben wird — auf demselben
Datenträger, der um 12:20 voll war. **Die Zahlen des Geräts sind
unverändert:** `/bin/fetch` 717 256 Oktett, `/bin/ota` 146 248 Oktett,
ein VERZEICHNIS 132 Oktett, ein Paket 34 291 Oktett, auf der Leitung
38 838 Oktett, davon wirklich übertragen 34 710.

### Der Abschlusslauf in Zahlen

| | Abschnitte | grün | rot | Zusagen |
|---|---:|---:|---:|---:|
| Grundlinie MERGE-3 (`main` `163984d`) | 55 | 50 | 5 | 4309 |
| Lauf A (nach `avx`) | 55 | 52 | 3 | 4327 |
| **Lauf B (`main`, roh, unter Fremdlast)** | **57** | **48** | **9** | **4325** |
| **Lauf B nach den Nachmessungen und der einen Reparatur** | **57** | **56** | **1** | — |

Die zwei zusätzlichen Abschnitte sind die neu angemeldeten: `avx`
(15b, 32 Zusagen, 13 s) und `ota` (34, 13 841 s). Zur Zählweise, damit
zwei Zahlen im Bericht nicht widersprüchlich aussehen: `test.sh` meldet
im Kopf die Zahl der **angemeldeten Läufer** (54 → 56), die Schlussbilanz
zählt zusätzlich den Abschnitt 1 (den festgenagelten Übersetzer) mit und
kommt deshalb auf **55 → 57**. Beide Zahlen stehen so in den
Protokollen.

**Von den neun roten sind acht nachgewiesenermaßen keine Fehler dieses
Zweiges** — **sechs** einzeln auf ruhigem Wirt grün nachgemessen
(`handle` 80/0, `k17` 158/0, `fsrobust` 30/0, `usbimg` 46/0, `net` 75/0,
`ota` 107/0), **einer** repariert und grün nachgemessen (`hwnettls`
24/0), **einer** aus dem Zustand des Wirts erklärt (`netview`: die
Maschine war nicht online) —, und **einer ist echt und bleibt offen**
(`UMLAUT2`).

Die Laufzeiten des Abschlusslaufs sagen mehr über den Wirt als über den
Baum: `tunnelpakete` 16 463 s, `ota` 13 841 s, `tunnelkosten` 10 118 s
(davon **9623 s Warten auf die Netzsperre**), `netview` 7615 s, `netmon`
6988 s, `tunnel` 6770 s (davon 6498 s Warten). Fünf Abschnitte hängen an
der wirtweiten Sperre `/tmp/osum-netz.lock`, und die wurde an diesem Tag
von **bis zu vier vollständigen Abnahmen gleichzeitig** gehalten. Ein
Lauf, in dem vier von vier Arbeitsplätzen an derselben Sperre stehen,
misst die Sperre und nicht den Kern.

---

## WAS NOCH FEHLT — ehrlich benannt

### 1. AVX-512 ist weiterhin nicht gemessen, nur messbar gemacht

Das ist unverändert der erste offene Punkt aus `docs/RUNDE-AVX.md`,
Abschnitt 8. Diese Runde hat ihn **nicht erledigt** — sie hat nur den
Weg gebaut, auf dem der Eigner ihn in zwei Minuten erledigen kann
(Menüeintrag 4 auf dem Stick, `docs/AUFSETZEN.md` Abschnitt 5.1). Was
auf einer AVX-512-Maschine gemessen werden muss: `xcr0=0xe7`,
`size` um 2700, `vec: width=3`, viermal `vec: bad=0`, `vec: clean=1`.

### 2. Der Stick kann kein Update

`tools/usbimg/build.sh` baut **43 Ring-3-Programme**, und weder
`/bin/ota` noch `/bin/host` noch `/bin/fetch` sind darunter. `fetch` ist
außerdem ein `--profile=app`-Programm, und der Bauweg des Sticks kennt
für Apps keinen Zweig (`tools/install/build.sh` schon). Der Stick kann
also alles, was diese Runde für das Blech nachweist — **außer dem, was
Teil 3.2 gemessen hat**. Für die Update-Kette auf echtem Blech braucht
es entweder die Programme im Stick oder eine Installation auf Platte
(`install --ja`, `docs/AUFSETZEN.md` Abschnitt 6). Das gehört in eine
eigene, kleine Runde: PROGS erweitern, den App-Bauweg aus
`tools/install/build.sh` übernehmen, und die 43 werden 46.

### 3. `tools/operation/run.sh` ist nicht in der Abnahme

Der dritte nie angemeldete Läufer (95 Zusagen auf seinem Zweig). Er
setzt `tools/operation/vorbereiten.sh` voraus — Pakete, Zertifikate,
Schlüsselbund, vier Auslieferungen, ein Abbild und eine **in QEMU
installierte Platte** — und stellt sie nicht selbst her; und er misst
gegen zwanzig echte Namen bei echten Nameservern. Anzumelden ist er
erst, wenn (a) die Vorbereitung im Läufer selbst steht und (b)
entschieden ist, ob eine Abnahme das offene Internet voraussetzen darf.
Bis dahin ist er das, was AVX vor dieser Runde war, und das ist
ausdrücklich schlecht.

### 4. `Range` gegen den echten Auslieferungsplatz

`/srv/store` wird von `python3 -m http.server` ausgeliefert, und der
kennt `Range` nicht (`curl -r 100-199` bekommt `200` und die ganze
Datei). Die Wiederaufnahme eines abgebrochenen Downloads — von der
Runde OTA gegen ihren eigenen Prüfstand gemessen — kostet gegen diesen
Server jedes Mal den **vollständigen** erneuten Download. Das Gerät
verhält sich richtig (`kernel/user/ota.fi` wirft ein zu langes
Bruchstück weg), aber die Eigenschaft fehlt dem Server. Ein `nginx`
oder ein `http.server` mit Range-Unterstützung vor `/srv/store` würde
es lösen.

### 5. Der Harnisch von `test.sh` kann einen Abschnitt verlieren

Im Lauf nach dem `avx`-Merge standen `tunnel` und `tunnelkosten` als
**rot** in der Zusammenfassung, obwohl beide Läufer intern
durchgelaufen sind (`16 passed, 0 failed` und `3 bestanden, 0
fehlgeschlagen`). Der Grund ist im Arbeitsverzeichnis nachweisbar:
`.netto.34` und `.netto.35` wurden geschrieben (das ist die **innere**
Schale unter `flock`), `.rc.34`, `.ms.34` und `.done.34` **nicht** (das
ist die äußere). `abschnitt_ausgeben` liest ein fehlendes `.rc.$i` als
`1` und meldet „ist fehlgeschlagen" — es kann nicht zwischen „der
Läufer war rot" und „dieser Abschnitt hat gar kein Ergebnis abgelegt"
unterscheiden. Beide Abschnitte hängen an der wirtweiten Netzsperre
`/tmp/osum-netz.lock`, die an diesem Tag von **drei** vollständigen
Abnahmen gleichzeitig gehalten wurde; der Datenträger war zeitweise
voll. Die Ursache ist damit **nicht** bewiesen, nur eingegrenzt.
Was zu tun ist: `abschnitt_ausgeben` muss ein fehlendes Ergebnis als
**eigenen** Befund melden („kein Ergebnis abgelegt") statt als
Fehlschlag des Läufers, sonst wird eine Störung des Prüfstands der
gemessenen Sache angelastet. Das ist eine eigene kleine Runde am
Harnisch und wurde hier bewusst nicht mitgemacht: an einem Prüfstand zu
schrauben, während er die Abnahme dieser Runde fährt, wäre genau der
Fehler, den dieser Bericht bei anderen benennt.

### 6. Was diese Runde NICHT nachgemessen hat

* `tools/ofs4/run.sh` — unverändert nicht gefahren (über eine halbe
  Stunde), wie schon in MERGE-3 vermerkt.
* Die Zahlen der Runde AVX zu **Kosten** (Zyklen je Kontextwechsel,
  `docs/RUNDE-AVX.md` Abschnitt 4) sind nicht nachgefahren worden;
  `tools/avx/run.sh` misst Richtigkeit, nicht Preis.
* **Warum `netview` grün geworden ist**, ist nicht geklärt — siehe
  unten. Dass es grün ist, ist gemessen; das Warum ist es nicht.

---

## WAS DIESE RUNDE GEÄNDERT HAT — die vollständige Liste

| Datei | | Was |
|---|---:|---|
| `tools/avx/run.sh` | 320 (neu) | der Läufer der Runde AVX, den es nicht gab. 32 Zusagen, 50 s |
| `tools/operation/store.sh` | 400 (neu) | die Update-Kette gegen `store.fleitec.com`. 37 Zusagen. Nicht in `test.sh` |
| `test.sh` | +37 | Abschnitt 15b (`avx`) und Abschnitt 34 (`ota`) angemeldet — 54 Abschnitte werden 56 |
| `tools/ota/run.sh` | +19 / −1 | `FIRNLIB` auf die Bibliothek des Repos; drei Erwartungen auf echte Umlaute |
| `tools/hwnet/tls.sh` | +17 / −1 | derselbe `FIRNLIB`-Fehler |
| `kernel/hwdiag.fi` | +36 / −2 | `stage` druckt nur noch, `park_if_asked` hält an |
| `kernel/kmain.fi` | +7 | `hwdiag.park_if_asked` hinter `fpu.report` und der Vektorprobe |
| `tools/usbimg/build.sh` | +26 | der vierte Menüeintrag „Vektoreinheit prüfen" |
| `docs/AUFSETZEN.md` | +68 | Abschnitt 5.1, die ausdruckbare Prüfanleitung; der vierte Eintrag in der Menütabelle |
| `docs/bilder/merge5-schreibtisch.png` | neu | der Schreibtisch aus diesem Abbild |
| `docs/RUNDE-MERGE5.md` | neu | dieser Bericht |

**Kein Kernquelltext der zwei hereingeholten Runden wurde angefasst** —
die einzige Änderung am Kern ist die Trennung von Bericht und Anhalten
in `hwdiag`, und die ist in Teil 3.1 begründet.

---

## DIE DREI ZAHLEN

<!-- ZUSAMMENFASSUNG -->

1. **`avx` und `betrieb` sind auf `main`**, beide konfliktfrei, und die
   Konfliktfreiheit ist vor dem Merge ausgerechnet und nicht gehofft
   worden: Schnittmenge der berührten Dateien **leer** (avx) und
   **eine Datei** (betrieb).

2. **`tools/operation/store.sh`: 37 Zusagen, 0 rot** — ein Osum in QEMU
   holt sich über den **Namen** `store.fleitec.com` ein signiertes
   Update aus dem offenen Internet: DHCP-Option 6 → eigener Auflöser →
   Let's-Encrypt-Kette mit **4 Zertifikaten, Tiefe 3** → Fassung 0 wird
   Fassung 2. Und mit `nofpu` daneben, also ohne die Runde AVX, stirbt
   derselbe Lauf an `user fault: vector=6`.

3. **Das Abbild: 123 731 968 Oktette,
   SHA-256 `16a188f1266f937ecdbb9073e4cc3e0a4e518ba251ae0cbe5f5eab775b542719`**,
   Kern 3 363 920 Oktette (+50 312 gegen MERGE-3), 43 Ring-3-Programme,
   Wurzel 20 971 520 Oktette OFS v3, 24 Pflichtpfade, 129 Umlautfolgen —
   und `USBIMG: 46 bestanden, 0 gescheitert` über BIOS **und** UEFI.
