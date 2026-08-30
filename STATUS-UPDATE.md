# RUNDE UPDATE — Zwischenstand

Zweig `update`, abgezweigt von `mergeline`. **Nicht nach `main` gemerged.**
Gemessen mit `bash tools/update/run.sh` (QEMU mit `-accel kvm` über
`tools/install/oneshot.sh`) und `python3 tools/update/vectors.py`.

**ENDSTAND: 49 Zusagen grün, 0 rot** (Volllauf) und **4725 Prüfungen grün,
0 rot** in der Rechnung. Die ausführliche Fassung mit der ehrlichen
Fehlliste steht in `docs/UPDATE.md`.

---

## Was gebaut wurde

| Datei | Zeilen | Was |
|---|---:|---|
| `lib/crypto/sha512.fi` | 281 | SHA-512 (FIPS 180-4), strömend, profilfrei |
| `lib/crypto/ed25519.fi` | 809 | Ed25519 (RFC 8032), signieren und prüfen |
| `kernel/ab.fi` | 237 | der Erprobungszähler (A/B-Boot) im Kern |
| `kernel/user/opk.fi` | +172 | Signaturpflicht, `/system/ERPROBUNG`, `opk erprobung` |
| `kernel/user/hallo3.fi` | 18 | das Paket, das sich sauber installiert und **nicht startet** |
| `tools/update/oracle.fi` | 174 | das Messgerät auf dem Wirt (dieselben `lib/crypto/`-Dateien wie der Kern) |
| `tools/update/vectors.py` | 325 | SHA-512 und Ed25519 gegen FIPS/RFC/`sign.input`/libsodium |
| `tools/update/signpak.py` | 83 | Pakete auf dem Wirt signieren, mit Gegenprüfung durch libsodium |
| `tools/update/pakete.sh` | 99 | die kaputten Pakete und Quellen der Gegenproben |
| `tools/update/run.sh` | 239 | der Läufer, fünf Abschnitte |
| `tools/update/sign.input.gz` | — | die 1024 offiziellen Ed25519-Vektoren, im Repo statt aus dem Netz |

---

## 1. Die Rechnung — grün

`tools/update/vectors.py`, **4725 Prüfungen, 0 Fehler** (Volllauf):

| Gruppe | grün |
|---|---:|
| SHA-512 gegen FIPS 180-4 (Literale) | 3 |
| SHA-512 gegen Pythons `hashlib` (Längen 0–259, 1000, 4096, 65000) | 263 |
| Ed25519 gegen die 5 Vektoren im Text von RFC 8032 7.1 (Schlüssel/Signatur/Prüfung) | 12 |
| Ed25519 gegen die **1024** Vektoren der offiziellen `sign.input` | 3072 |
| Ed25519 gegen libsodium (pynacl), 57 Längen, beide Richtungen | 175 |
| **negativ**: ein gekipptes Bit in Nachricht / R / S / öffentlichem Schlüssel | 800 |
| **negativ**: S+L statt S (Malleabilität, RFC 8032 8.4) | 200 |
| **negativ**: die Signatur einer anderen Nachricht | 200 |

Laufzeit des Volllaufs: **57 s** auf dem Wirt.

Die zweite Meinung ist wirklich eine zweite: `sign.input` stammt von den
Ed25519-Autoren, die fünf Literale sind aus dem RFC-Text abgetippt, und
libsodium ist eine fremde Umsetzung. Eine Signatur, die nur ihr eigener
Erzeuger anerkennt, sagt nichts — deshalb prüft `signpak.py` jede erzeugte
Signatur sofort mit libsodium nach.

## 2. Die Signaturpflicht auf dem Gerät — grün

`/bin/opk` prüft **vor jedem Schreibzugriff**:

* `/system/schluessel.pub` (32 rohe Oktette) ist der vertraute Schlüssel.
  Fehlt er, wird **nichts** installiert. Es gibt keinen Schalter dagegen.
* neben `x.opk` muss `x.opk.sig` liegen: Ed25519 über **alle** Oktette des
  Pakets, Kopf eingeschlossen.
* bei `aktualisieren` zusätzlich `INDEX.sig` über den INDEX, **bevor** eine
  Zeile daraus geglaubt wird.

Gemessen in QEMU, auf einer echten Platte, gestartet über die
EFI-Partition — und jede Ablehnung mit der Gegenprobe „es wurde wirklich
nichts installiert":

| Fall | Antwort |
|---|---|
| richtig signiert | installiert, Streuwert = der des Wirts |
| **ohne `.sig`** | `opk: KEINE SIGNATUR -- abgelehnt` |
| **ein gekipptes Oktett im Archiv** | `opk: SIGNATUR FALSCH` (und zwar **vor** der Prüfsumme) |
| **veränderter INDEX, alte `INDEX.sig`** | `opk: SIGNATUR DES INDEX FALSCH -- Quelle ABGELEHNT` |
| **fremder öffentlicher Schlüssel** | `opk: SIGNATUR FALSCH` |
| **gar kein `/system/schluessel.pub`** | `opk: kein vertrauter Schluessel` |

## 3. Der Erprobungszähler (A/B) — grün

`/system/ERPROBUNG`, genau 36 Oktette fester Breite:

    gen=00000001 vor=00000000 v=01 ok=0

`opk` schreibt den Eintrag beim Umschalten, `kernel/ab.fi` zählt bei jedem
Start hoch — **bevor der erste Prozess läuft** —, und beim dritten Versuch
ohne Erfolgsvermerk schreibt der Kern `/system/AKTUELL` auf die vorige
Generation zurück.

Gemessen mit einem Update, das **sauber signiert** ist und dessen Programm
sich mit Code 1 beendet (`kernel/user/hallo3.fi`):

```
Start 1   ab: gen=1 versuch=1 von 3        paket-hallo fassung 3 SCHEITERT
Start 2   ab: gen=1 versuch=2 von 3        (kein Erfolgsvermerk)
Start 3   ab: ERPROBUNG gescheitert, zurueck auf 0
          paket-hallo fassung 1            ← die alte Fassung läuft wieder
Start 4   ab: gen=0 bestaetigt
```

Gegenprobe mit einem Update, das läuft: im selben Start bestätigt, und
auch nach vier weiteren Starts wird **nie** zurückgefallen.

## 4. Was NICHT gemessen ist

Steht ausführlich in `docs/UPDATE.md`. Das Wichtigste:

* **Die HTTPS-Strecke ist in dieser Runde nicht Ende-zu-Ende gelaufen.**
  `/bin/fetch` (Runde HWNET) kann eine Datei über TLS 1.3 mit
  Kettenprüfung holen und ist dort gegen `openssl s_server` und gegen das
  echte Netz gemessen. Die Quelle in dieser Runde ist ein Verzeichnis auf
  der Platte. Was zwischen beidem fehlt, ist ein Resolver und die
  Verdrahtung — nicht die Kryptographie.
* **Der Kern selbst ist nicht Teil des A/B-Wechsels.** Der Zähler sitzt im
  Kern, nicht im Lader (Limine ist fremder Code ohne Zustandsspeicher).
  Ein Kern, der gar nicht bis zum Einhängen der Wurzel kommt, wird davon
  nicht gefangen; dafür bräuchte es zwei Kernabbilder auf der
  EFI-Partition. Das steht in `kernel/ab.fi` als Grenze im Kopf.
* **Die Kryptographie ist nicht auditiert.** Sie ist gegen die Normen und
  gegen libsodium gemessen, was viel mehr als nichts und viel weniger als
  eine Prüfung ist.
