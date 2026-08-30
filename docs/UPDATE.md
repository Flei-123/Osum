# Runde UPDATE — der Weg, auf dem sich dieses System selbst erneuert

Zweig `update`, abgezweigt von `mergeline`, **nicht nach `main` gemerged**.
Ein Lauf, fünf Abschnitte: **49 Zusagen, 0 Fehler** (`bash tools/update/run.sh`),
dazu **4725 Prüfungen, 0 Fehler** in der Rechnung selbst
(`python3 tools/update/vectors.py`, 57 s).

Was diese Runde angreift, steht in `docs/ROADMAP-UPDATE.md`:

* **A3** — „Ed25519 ist in Firn NICHT umgesetzt. Ein Update-Weg, der die
  Signatur nicht prüfen kann, ist ein Update-Weg, der jedem gehört, der
  die Verbindung umleitet."
* **A5** — „ein Zähler, den der Lader hochzählt und ein erfolgreicher
  Start zurücksetzt […] Ohne ihn verwandelt ein misslungenes Update ein
  Gerät im Nebenzimmer in einen Ziegel."
* **6.2** — „der öffentliche Schlüssel entsteht bei jedem Bau neu."

Alle drei sind eingelöst. Was **nicht** eingelöst ist, steht am Ende, und
es ist der längste Abschnitt.

---

## Was gebaut wurde

| Datei | Zeilen | Was |
|---|---:|---|
| `lib/crypto/sha512.fi` | 281 | SHA-512 (FIPS 180-4), strömend, ohne Profilzeile, ohne Importe |
| `lib/crypto/ed25519.fi` | 809 | Ed25519 (RFC 8032): signieren, prüfen, Punktarithmetik, Skalare |
| `kernel/ab.fi` | 237 | der Erprobungszähler im Kern |
| `kernel/user/opk.fi` | 1628 (+172) | Signaturpflicht, `/system/ERPROBUNG`, `opk erprobung [ok]` |
| `kernel/user/hallo3.fi` | 18 | das Paket, das sich sauber installiert und **nicht startet** |
| `tools/update/oracle.fi` | 174 | das Messgerät auf dem Wirt |
| `tools/update/vectors.py` | 325 | die Vektoren |
| `tools/update/signpak.py` | 83 | Pakete signieren, mit Gegenprüfung durch libsodium |
| `tools/update/pakete.sh` | 99 | die kaputten Pakete und Quellen |
| `tools/update/run.sh` | 239 | der Läufer |

Der Zweig enthält außerdem `hwnet` (TLS 1.3, `/bin/fetch`, e1000), weil
der Update-Weg HTTPS braucht.

---

## 1. Ed25519 und SHA-512 — 4725 Prüfungen

`lib/crypto/ed25519.fi` rechnet auf der Montgomery-Arithmetik, die schon
X25519, P-256 und RSA benutzen (`lib/crypto/big.fi`), und fügt genau das
hinzu, was die Edwards-Form braucht. **Eine** Punktroutine: für a = −1
(ein Quadrat mod p) und d als Nichtquadrat ist das Additionsgesetz
**vollständig** — Verdoppeln ist `add(P,P)`, das neutrale Element ist kein
Sonderfall, und damit gibt es die ganze Klasse Fehler nicht, bei der eine
Kurvenimplementierung für einen unerwarteten Punkt den falschen Zweig
nimmt.

Die Skalarmultiplikation ist **konstant in der Zeit über dem Skalar**: pro
Bit laufen immer dieselben zwei Additionen, und welche überlebt,
entscheidet eine maskierte Auswahl ohne Sprung (`big.select_into`, dieselbe
Grundfunktion wie in der X25519-Leiter). Die Schleife läuft 256-mal,
gleich wie klein der Skalar ist.

| Gruppe | grün |
|---|---:|
| SHA-512 gegen FIPS 180-4 (Literale) | 3 |
| SHA-512 gegen `hashlib` (alle Längen 0–259, 1000, 4096, 65000) | 263 |
| Ed25519 gegen die 5 Vektoren im **Text** von RFC 8032 7.1 | 12 |
| Ed25519 gegen die **1024** Vektoren der offiziellen `sign.input` | 3072 |
| Ed25519 gegen **libsodium** (pynacl), 57 Längen, beide Richtungen | 175 |
| negativ: gekipptes Bit in Nachricht / R / S / öffentlichem Schlüssel | 800 |
| negativ: **S+L** statt S (Malleabilität, RFC 8032 8.4) | 200 |
| negativ: die Signatur einer anderen Nachricht | 200 |
| **Summe** | **4725** |

Drei unabhängige Autoritäten: die 1024 Vektoren stammen von den
Ed25519-Autoren, die fünf Literale sind aus dem RFC-Text abgetippt,
libsodium ist eine fremde Umsetzung. Und `signpak.py` prüft **jede**
erzeugte Signatur sofort mit libsodium nach — eine Signatur, die nur ihr
eigener Erzeuger anerkennt, sagt nichts.

Die Prüfgleichung ist die **kofaktorlose** ([S]B = R + [k]A), die RFC 8032
5.1.7 erlaubt und die strenger ist als die mit 8 multiplizierte. S ≥ L
wird abgelehnt.

## 2. Die Signaturpflicht auf dem Gerät

Bis zu dieser Runde rechnete `/bin/opk` eine **Prüfsumme**. Die fängt eine
kaputte Übertragung und sonst nichts: wer die Oktette ändern kann, ändert
die Prüfsumme mit — sie steht im selben Kopf.

Seit dieser Runde:

* `/system/schluessel.pub`, 32 rohe Oktette, ist der vertraute Schlüssel.
  **Fehlt er, wird nichts installiert.** Es gibt keinen Schalter dagegen —
  eine Ausnahme, die man im Notfall setzt, ist die Ausnahme, die ein
  Angreifer benutzt.
* Neben `x.opk` liegt `x.opk.sig`: Ed25519 über **alle** Oktette des
  Pakets, den Kopf eingeschlossen (nicht über die Prüfsumme — dann wären
  die Längenfelder ungedeckt).
* Bei `aktualisieren` wird zusätzlich `INDEX.sig` geprüft, **bevor** eine
  Zeile des INDEX geglaubt wird. Damit hängt die ganze Kette an einem
  Schlüssel: INDEX → Streuwert → Paketoktette.
* Die Prüfung steht **vor dem ersten Schreibzugriff**. Was durchfällt, hat
  das System nie berührt.

Gemessen in QEMU auf einer echten Platte, gestartet über die
EFI-Partition, jede Ablehnung mit der Gegenprobe „es wurde wirklich nichts
installiert":

| Fall | Antwort |
|---|---|
| richtig signiert | installiert, Streuwert = der des Wirts |
| ohne `.sig` | `opk: KEINE SIGNATUR -- abgelehnt` |
| ein gekipptes Oktett im Archiv | `opk: SIGNATUR FALSCH` — **vor** der Prüfsumme |
| veränderter INDEX, alte `INDEX.sig` | `opk: SIGNATUR DES INDEX FALSCH -- Quelle ABGELEHNT` |
| fremder öffentlicher Schlüssel | `opk: SIGNATUR FALSCH` |
| gar kein `/system/schluessel.pub` | `opk: kein vertrauter Schlüssel` |

## 3. Der Erprobungszähler (A/B-Boot)

`/system/ERPROBUNG`, **genau 36 Oktette** fester Breite:

    gen=00000001 vor=00000000 v=01 ok=0

Feste Breite aus demselben Grund wie bei `/system/AKTUELL`: eine Datei,
deren Länge sich nicht ändert, geht in **genau einen** Datenblock, und ein
Sektor erreicht die Platte ganz oder gar nicht. Ausgerechnet der Zähler,
der einen Stromausfall überleben soll, darf den Zwischenzustand nicht
haben.

`opk` schreibt den Eintrag beim Umschalten; `kernel/ab.fi` zählt bei jedem
Start hoch, **bevor der erste Prozess läuft**; beim dritten Versuch ohne
Erfolgsvermerk schreibt der Kern `/system/AKTUELL` auf `vor` zurück.
`opk erprobung ok` setzt den Vermerk — auf einem ausgelieferten System
gehört dieser Aufruf ans Ende des Startvorgangs.

Gemessen mit `kernel/user/hallo3.fi`: ein Update, das **sauber signiert**
ist, sich einwandfrei installiert und dessen Programm sich mit Code 1
beendet. Drei echte Neustarts in QEMU:

```
Start 1   ab: gen=1 versuch=1 von 3     paket-hallo fassung 3 SCHEITERT
Start 2   ab: gen=1 versuch=2 von 3     (kein Erfolgsvermerk)
Start 3   ab: ERPROBUNG gescheitert, zurueck auf 0
          paket-hallo fassung 1         ← die alte Fassung läuft wieder
Start 4   ab: gen=0 bestaetigt
```

**Gegenprobe** mit einem Update, das läuft: im selben Start bestätigt, und
auch nach vier weiteren Starts wird nie zurückgefallen. Ohne diese
Gegenprobe wäre „es fällt zurück" auch dann grün, wenn es *immer*
zurückfiele.

**Warum der Zähler nicht im Lader sitzt.** Der Lader ist Limine, fremder
Code aus `vendor/limine`, ohne Zustandsspeicher zwischen zwei Starts und
ohne Stelle, an der man einen ohne Patch hineinbekäme. Ein gepatchter
Fremdlader bräche bei jedem Limine-Update. Also sitzt der Zähler an der
frühesten Stelle, die dieses System **selbst** besitzt: im Kern,
unmittelbar nach dem Einhängen der Wurzel und vor dem ersten Prozess.

## 4. Der Ablauf am Stück

    opk liste
    opk aktualisieren <name> --quelle <verzeichnis>   # Signatur, Streuwert, Generation
    (Neustart)
    opk richten ; if /apps/<name>.osp/start ; then opk erprobung ok ; fi

`tools/update/update.sh` ist genau das, mit dem `fetch`-Aufruf für die
HTTPS-Seite als Kommentar darüber.

---

## WAS NOCH FEHLT — für ein echtes Update über das Internet

Ehrlich und vollständig, ohne Zeitplan.

1. **Die HTTPS-Strecke ist in dieser Runde nicht Ende-zu-Ende gelaufen.**
   `/bin/fetch` (Runde HWNET, in diesem Zweig enthalten) holt eine Datei
   über TLS 1.3 mit Kettenprüfung und ist dort gegen `openssl s_server`
   und gegen das echte Netz gemessen. Die Quelle in dieser Runde ist ein
   Verzeichnis auf der Platte. Es fehlt die Verdrahtung, nicht die
   Kryptographie: `fetch` ist ein `kernel/app/`-Programm und liegt in
   keinem der Abbilder, die `tools/install/build.sh` baut.
2. **Kein Resolver.** `fetch` nimmt eine IPv4-Adresse und den Namen für
   das Zertifikat getrennt entgegen. Für `https://pkg.example.org/…`
   braucht es DNS. `vendor/firn/lib/net/dns.fi` ist im festgenagelten
   Vorrat, `/etc/resolv.conf` schreibt niemand, `dhcp.fi` kennt den
   Nameserver schon. Etwa 50 Zeilen und eine Messung gegen `dig`.
3. **Der Kern ist nicht Teil des A/B-Wechsels.** Der Zähler fängt eine
   Generation, deren *Userland* nicht hochkommt. Ein Kern, der gar nicht
   bis zum Einhängen der Wurzel kommt, wird davon nicht gefangen. Dafür
   bräuchte es zwei Kernabbilder auf der EFI-Partition und einen Lader,
   der zwischen ihnen umschaltet — und der PLAN nennt seit Fassung 2
   einen Kernel-Streuwert, benutzt ihn aber nicht.
4. **Der Erfolgsvermerk wird von Hand gesetzt.** In dieser Runde tut es
   das Startskript des Testlaufs. Auf einem ausgelieferten System gehört
   `opk erprobung ok` in `/etc/inittab` bzw. an das Ende des
   Startvorgangs — und die Frage, **was** „erfolgreich gestartet"
   heißt (läuft das Paket? ist das Netz da? antwortet der Helfer?), ist
   eine Entscheidung und keine Runde.
5. **Nach einem Rückfall zeigt `/apps` noch auf die gescheiterte
   Generation.** Der Kern schreibt nur `/system/AKTUELL` um; `/apps` ist
   abgeleiteter Zustand und wird von `opk richten` neu gebaut. Im
   Testlauf steht `opk richten` deshalb als erste Zeile des Startskripts.
   Sauberer wäre, der Kern oder init täte es.
6. **Der geheime Schlüssel liegt unverschlüsselt auf der Baumaschine**
   (`$OUT/geheim.key`). Er wird seit dieser Runde nicht mehr bei jedem Bau
   neu gewürfelt (Roadmap 6.2), aber wo er auf Dauer liegen soll — Tresor,
   HSM, getrennte Signiermaschine —, ist eine Entscheidung, die noch
   niemand getroffen hat.
7. **Die Uhr.** Die Zertifikatsprüfung benutzt die CMOS-Uhr. Eine Maschine
   mit leerer Knopfzelle hält jedes gültige Zertifikat für ungültig und
   kann sich dann nicht mehr aktualisieren. SNTP ist ein UDP-Paket von 48
   Oktett.
8. **Der Wurzelzertifikatsspeicher altert.** `/etc/ssl/roots.pem` ist ins
   Abbild gebacken. Lösung: er wird ein Paket wie jedes andere — das setzt
   Punkt 1 voraus und ist danach Fleißarbeit.
9. **Ein Rückruf ist nicht vorgesehen.** Es gibt einen vertrauten
   Schlüssel und keinen Weg, eine Fassung nachträglich für ungültig zu
   erklären oder den Schlüssel zu wechseln. Ein zweiter Schlüssel im
   Abbild („Ersatz") und eine Sperrliste im signierten INDEX wären der
   übliche Weg.
10. **Diese Kryptographie ist nicht auditiert.** Sie ist gegen die Normen
    und gegen libsodium gemessen — viel mehr als nichts und viel weniger
    als eine Prüfung. Nicht jeder Pfad ist zeitkonstant; welche das sind
    und warum es dort nichts zu holen gibt, steht als Punkte E1–E5 im Kopf
    von `lib/crypto/ed25519.fi`.
