# WAS NOCH FEHLT -- für das Auto-Update und für den JARVIS-Helfer

Runde HWNET, 28.08.2026. Eine ehrliche Liste, kein Zeitplan.

Bei jedem Punkt steht: was es schon gibt, was fehlt, was es ungefähr
kostet, und ob es eine **eigene Runde** braucht oder **nebenbei** läuft.
Es steht KEIN Datum darin. Aufwand ist in „Zeilen und Messungen"
geschätzt, weil das die einzige Größe ist, die diese Runden bisher
verlässlich getroffen haben.

---

## 0. ZUERST: WO DIE RUNDE PLAN2 GELANDET IST

Justins Beobachtung war richtig: im Osum-Baum gibt es keine PLAN-Dateien
und keine `docs/UPDATE.md`. Der Grund ist, dass **die ganze Paket- und
Generationenmaschinerie nicht in Osum liegt, sondern in OrientOS**:

    /root/jarvis/projects/u_DiS4in7esMF1/orientos
      pkg/opk.py                          das Paketwerkzeug (Python, auf dem WIRT)
      docs/PLAN-FORMAT.md                 das Format, Fassung 2 (Runde PLAN2)
      docs/ROUND-PLAN2.md                 das Rundenprotokoll: 15 Schritte,
                                          234 Zusagen, davon 33 neu
      docs/BACKUP.md                      Sicherung, Quellen, Ed25519
      tests/step-90-plan.sh               die Abnahme dazu
      build/wurzel/system/generations/{0,1,2,3}/PLAN   vier echte Generationen

Osum ist der KERN, OrientOS ist das SYSTEM darum. Deshalb steht in Osums
Baum nichts davon -- und deshalb ist die Frage „was fehlt zum
Auto-Update" nur zur Hälfte eine Osum-Frage.

Was PLAN2 schon kann (aus dem Rundenprotokoll, gemessene Zahlen):
ein ganzer Rechnerzustand als **13 Zeilen und 745 Oktett** Text --
Anwendungen mit Streuwert, der Kernel mit Streuwert, Quellen mit
Ed25519-Schlüssel, Systemeinstellungen, Benutzerkonten, Vorlieben je
Benutzer; ein Baum, der daraus **oktettgleich** neu gebaut wird.

---

## TEIL A -- DER UPDATE-WEG

### A1. Ein Paketwerkzeug, das AUF DEM GERÄT läuft
**Da:** `pkg/opk.py` -- Speicher (store), Generationen, Ein- und
Ausspielen, `rebuild` aus einem PLAN, Waisenerkennung, Sicherung.
**Fehlt:** es ist **Python auf dem Wirt**. Auf dem Gerät läuft kein
Python. Heute wird ein OrientOS-Baum auf einem Entwicklungsrechner
gebaut und als Abbild geschrieben; das Gerät kann sich selbst nicht
aktualisieren.
**Was es braucht:** `/bin/opk` in Firn, gebaut als `kernel/app/`-Programm
(die Bauart, die diese Runde für `/bin/fetch` eingeführt hat: volle
Firn-Bibliothek, Halde, Ring 3). Es muss lesen können: PLAN (Text, TAB-getrennt,
sechs Zeilenarten), den Speicher (Verzeichnisse mit Streuwertnamen), die
Generationen. Und schreiben: eine neue Generation, den Zeiger darauf.
**Aufwand:** ~1200 Zeilen Firn plus Abnahme. Das Format ist fertig und
in `docs/PLAN-FORMAT.md` beschrieben; das ist der halbe Weg.
**Eigene Runde.** Die größte einzelne Position auf dieser Liste.

### A2. Die Quelle über HTTPS
**Da seit dieser Runde:** TLS 1.3 mit Kettenprüfung in Ring 3
(`kernel/app/fetch.fi`), gemessen gegen `openssl s_server` UND gegen das
echte Netz -- `https://example.com` mit demselben SHA-256 des Rumpfes,
den `curl` auf dem Wirt bekommt.
**Fehlt für den Paketbezug:** nichts Grundsätzliches mehr. `/bin/fetch`
kann eine Datei über HTTPS holen und mit `-o` wegschreiben. Was fehlt,
ist der Aufrufer (A1) und:
**Namensauflösung.** Osum hat keinen Resolver. Für eine Quelle wie
`https://pkg.orientos.dev/…` braucht es einen. **Das ist billig:**
`vendor/firn/lib/net/dns.fi` ist bereits im festgenagelten Vorrat
(`resolve_a`, `read_resolv_conf`) und benutzt UDP-Steckdosen, die Osum
hat. Es fehlt: `/etc/resolv.conf` (DHCP liefert den Nameserver schon,
`kernel/user/dhcp.fi` schreibt ihn nur nicht), und zwanzig Zeilen in
`fetch.fi`, die einen Namen statt einer Adresse annehmen.
**Aufwand:** ~50 Zeilen und eine Messung gegen `dig`. **Nebenbei.**

### A3. Signaturprüfung der Pakete -- **die größte Lücke, die niemand sieht**
**Da:** das PLAN-Format nennt zu jeder Quelle einen
**Ed25519**-Schlüssel (`source <url> <64 hex>`), und `docs/BACKUP.md`
baut darauf.
**Fehlt:** **Ed25519 ist in Firn NICHT umgesetzt.** Gemessen:
`vendor/firn/lib/std/crypto/` hat X25519 (Schlüsseltausch, keine
Signatur), ECDSA auf P-256/P-384 und RSA. In `x25519.fi` steht es
wörtlich: *„NO EDWARDS FORM, no signature. Ed25519 is a different
curve"*, und `x509.fi` gibt für Ed25519 `UNSUPPORTED` zurück.
Ein Update-Weg, der die Signatur nicht prüfen kann, ist ein Update-Weg,
der jedem gehört, der die Verbindung umleitet -- und TLS allein reicht
dafür ausdrücklich NICHT (der Server könnte übernommen sein, und die
Wurzelzertifikate im Abbild altern).
**Zwei Wege, und der zweite ist der bessere:**
1. Ed25519 in Firn bauen: Edwards-Kurve, Punktarithmetik, SHA-512
   (vorhanden), ~350 Zeilen, messbar gegen Pythons `cryptography` mit
   den RFC-8032-Testvektoren. Danach passt es zum Format, wie es steht.
2. Das Format auf ECDSA/P-256 umstellen: kostet nichts an Code (ist da),
   aber ändert eine Datei, die schon in vier Generationen steht.
**Empfehlung: Weg 1.** Ed25519 ist der Standard für Paketsignaturen, und
das Format ist schon so geschrieben.
**Eigene Runde**, aber eine kleine und sehr gut messbare.

### A4. Generationen und Zurückrollen -- auf dem Gerät
**Da:** Generationen als Verzeichnisse mit je einem PLAN
(`/system/generations/<n>/PLAN`), vier davon im Baubaum; der Speicher
hält einen Eintrag, solange ihn eine Generation nennt.
**Fehlt:** (a) das Umschalten auf dem Gerät (A1), (b) **der Kernel
selbst.** Der PLAN nennt zwar seit PLAN2 einen Kernel-Streuwert, aber
gestartet wird, was auf der EFI-Partition liegt. Ein Zurückrollen, das
den Kernel einschließt, muss diese Datei tauschen --
`kernel/user/install.fi` schreibt sie schon einmal (GPT,
EFI-Partition, `/EFI/BOOT/BOOTX64.EFI`, `limine.conf`, `osum.mb`), also
gibt es den Weg; er muss nur ein zweites Mal begehbar werden.
**Aufwand:** ~200 Zeilen im Installationsprogramm, plus eine
Ende-zu-Ende-Messung: installieren, aktualisieren, neu starten,
zurückrollen, neu starten, prüfen dass der alte Kernel läuft.
**Nebenbei zu A1**, aber die Messung ist eine eigene.

### A5. Was passiert, wenn die neue Generation NICHT bootet
**Da:** nichts.
**Fehlt:** ein Zähler, den der Lader hochzählt und ein erfolgreicher
Start zurücksetzt (das, was andere Systeme „A/B-Boot" nennen). Ohne ihn
verwandelt ein misslungenes Update ein Gerät im Nebenzimmer in einen
Ziegel, und genau das ist der Fall, für den Justin den Helfer will.
**Kostet:** eine Datei auf der EFI-Partition, drei Zeilen im
Limine-Eintrag, ~80 Zeilen im Kern (beim erfolgreichen Hochlauf
zurücksetzen).
**Eigene Runde** -- weil die Messung „ein absichtlich kaputter Kernel
und die Maschine kommt trotzdem hoch" der ganze Punkt ist.

### A6. Der Wurzelzertifikatsspeicher altert
**Da seit dieser Runde:** `/etc/ssl/roots.pem`, elf Wurzeln, Herkunft in
`tools/hwnet/mkroots.py` dokumentiert.
**Fehlt:** ein Weg, ihn zu erneuern. Er ist ins Abbild gebacken. Eine
zurückgezogene Wurzel bleibt drin; eine neue fehlt.
**Lösung:** er wird ein Paket wie jedes andere und steht damit im PLAN.
Das setzt A1 und A3 voraus, ist danach aber Fleißarbeit.
**Nebenbei**, nach A1/A3.

### A7. Die Uhr
**Da:** CMOS-Uhr beim Start (`kernel/time.fi`), und die Zertifikatsprüfung
benutzt sie (gemessen: abgelaufene Zertifikate werden korrekt abgelehnt).
**Fehlt:** NTP. Eine Maschine mit leerer Knopfzelle hält jedes gültige
Zertifikat für ungültig und kann sich dann nicht mehr aktualisieren --
ein Henne-Ei-Problem, das reale Systeme wirklich haben.
**Kostet:** SNTP ist ein UDP-Paket von 48 Oktett; ~120 Zeilen in einem
`kernel/app/`-Programm.
**Nebenbei.**

### A8. Der Rundruf nach außen (DHCP in einem fremden Netz)
**Gemessen in dieser Runde:** der festgenagelte Stapel
(`vendor/firn/lib/net/stack.fi`) sucht auch für 255.255.255.255 den
nächsten Sprung per ARP, statt `ff:ff:ff:ff:ff:ff` zu nehmen. In einem
Netz, in dem der DHCP-Server das Gateway ist (jeder Heimrouter), fällt
das nicht auf. In einem Netz, in dem er es nicht ist, geht **gar
nichts**: 0 UDP-Rahmen verlassen die Maschine (mitgeschnitten).
**Kostet:** drei Zeilen in `lib/net/stack.fi` -- aber die Datei gehört
**Firn**, nicht Osum, und ist über `vendor/firn/COMMIT` festgenagelt.
Also: eine kleine Firn-Runde, danach den Vorrat neu festnageln.
**Nebenbei in Firn, dann eine Neu-Festnagelung in Osum.**

---

## TEIL B -- DER JARVIS-HELFER

Der Helfer soll: eine dauerhafte, verschlüsselte Verbindung zu JARVIS
halten, Befehle entgegennehmen, Programme starten, deren Ausgabe
zurückschicken. Was davon steht schon?

### B1. Die Verbindung
**Da seit dieser Runde:** TLS 1.3, Kettenprüfung, gemessen gegen das
echte Netz. Eine `tls.Tls` liest und schreibt, solange die Steckdose
offen ist.
**Fehlt für „dauerhaft":**
* **Wiederverbinden mit Warteabstand.** Reines Programmwerk, ~60 Zeilen.
* **Am Leben halten.** Ein NAT unterwegs vergisst eine stille Verbindung
  nach 30 bis 300 Sekunden. Braucht entweder eine leere Nachricht alle
  60 Sekunden (billig, das richtige Mittel) oder TCP-Keepalive, das
  `setsockopt` bräuchte -- Osum nimmt `setsockopt` (54) an, aber
  SO_KEEPALIVE tut dort nichts.
* **Schlüsselerneuerung (KeyUpdate).** `tls.fi` kennt die Nachricht
  (`HS_KEY_UPDATE`), ob sie über Stunden trägt, ist NICHT gemessen. Eine
  Verbindung, die tagelang steht, überschreitet irgendwann die
  Datensatzgrenzen von AES-GCM.
**Aufwand:** ~150 Zeilen plus eine Messung, die eine Verbindung eine
Stunde hält und zählt. **Nebenbei**, außer der Schlüsselerneuerung --
die braucht eine eigene Messung.

### B2. Auf zwei Dingen gleichzeitig warten -- **die harte Lücke**
Ein Helfer wartet immer auf ZWEI Dinge: auf die Steckdose (kommt ein
Befehl?) und auf das Kindprozess-Rohr (kommt Ausgabe?).
**Fehlt in Osum:** `poll` (7), `select` (23), `epoll` -- **keiner dieser
Aufrufe existiert.** Gemessen: `grep -c 'SYS_POLL\|SYS_SELECT' kernel/sys.fi`
→ 0. Ebenso fehlt `fcntl` (72), also auch `F_SETFL` für O_NONBLOCK auf
einem Rohr.
**Was es gibt:** nicht blockierende STECKDOSEN
(`inet.sock_set_nonblock`, `SOCK_NONBLOCK` bei `accept4`). Für Rohre gibt
es das nicht.
**Zwei Wege:**
1. `SYS_POLL` (7) bauen: Deskriptorliste, Ereignismaske, Zeitlimit. Für
   Steckdosen ist die Bereitschaftsprüfung im Kern schon da
   (`inet.sock_readable`, `sock_writable`); für Rohre und Terminals
   müsste sie dazu. ~250 Zeilen in `kernel/sys.fi` plus `file.fi`, und
   die Gegenprobe ist leicht: ein Programm, das ohne `poll` in einer
   Schleife brennt, und eines mit, und die gemessene Prozessorlast.
2. Ohne `poll` leben: alles nicht blockierend abfragen und dazwischen
   schlafen. Läuft, kostet Latenz und Strom, und Rohre kann man so gar
   nicht abfragen.
**Empfehlung: `poll` bauen.** Es ist der eine fehlende Systemaufruf, den
JEDES Programm dieser Art braucht -- und er ist nicht „für den
Assistenten", was `ASSISTENT.md` in OrientOS ausdrücklich verlangt.
**Eigene Runde**, eine kleine.

### B3. Ein Programm starten und seine Ausgabe zurückgeben
**Da, und vollständig:** `fork` (57), `execve` (59), `pipe` (22), `dup2`
(33), `wait4` (61), `kill` (62), Prozessgruppen, Signale. Das ist genau
das, was eine Shell braucht, und Osum hat eine Shell, die es benutzt.
**Fehlt:** nichts Grundsätzliches. Mit B2 ist der Helfer schreibbar.
**Nebenbei.**

### B4. Beim Hochfahren starten und nach einem Absturz wieder
**Da, und fertig:** `kernel/user/init.fi` liest `/etc/inittab` mit den
Arten `once`, `respawn`, `ctrl`, `off` und startet abgestürzte Dienste
neu -- gedeckelt auf fünfmal je Sekunde. Ein Helfer ist eine Zeile:

    jarvis:respawn:/bin/jarvisd

**Fehlt:** nichts. **Nebenbei.**

### B5. Wo das Geheimnis liegt
**Da:** Runde TRESOR -- Geräteidentität, ein verschlüsselter Speicher,
PBKDF2, `crypto erase` (gemessen: 20 ms).
**Fehlt:** die Entscheidung, ob der Helfer sein Merkmal im Tresor hält
(dann braucht der Start ein Passwort -- schlecht für einen Rechner ohne
Menschen davor) oder in einer Datei, die nur `root` lesen darf (dann
liest sie jeder, der die Platte ausbaut). Ohne TPM gibt es hier keine
gute dritte Antwort.
**Braucht eine Entscheidung, keine Runde.**

### B6. Was der Helfer NICHT bekommen darf
Aus `ASSISTENT.md` in OrientOS, und es gilt hier genauso: kein
Kernelcode gehört ihm, kein Systemaufruf existiert nur seinetwegen, kein
Programm ruft ihn auf. `poll` (B2) besteht diesen Test -- eine Shell,
ein Terminalprogramm und jeder Server brauchen es auch.

---

## DIE KÜRZESTE STRECKE ZUM ZIEL

Wenn das Ziel ist „OrientOS läuft auf einem echten Brett bei Justin und
der Helfer redet mit JARVIS", dann in dieser Reihenfolge:

1. **Ein Brett aussuchen und die serielle Ausgabe ablesen.** Sagt der
   Kern `netdev: no driver for 0x10ec:0x8168`, ist der nächste Schritt
   ein Realtek-Treiber; sagt er `netdev: c0=e1000`, ist das Netz fertig.
   Findet er die Platte nicht, ist AHCI der nächste Schritt.
   **Kostet nichts außer dem Brett.**
2. **`poll`** (B2) -- die eine fehlende Kernfunktion.
3. **Der Helfer selbst** (B1+B3+B4), gegen einen JARVIS-Endpunkt im
   Heimnetz gemessen.
4. **Ed25519** (A3), weil ohne sie kein Update-Weg vertretbar ist.
5. **`/bin/opk`** (A1) und der Generationswechsel auf dem Gerät (A4).
6. **A/B-Boot** (A5) -- spätestens, bevor das erste Update aus der Ferne
   auf ein Gerät geht, das keiner anfassen kann.

Punkt 1 bis 3 machen das Gerät fernsteuerbar. Punkt 4 bis 6 machen es
fernwartbar. Das ist nicht dasselbe, und die Reihenfolge ist wichtig:
ein Gerät, das man erreichen kann, kann man auch von Hand reparieren.
