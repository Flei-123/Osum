# RUNDE OTA — Zwischenstand

Zweig `ota`, abgezweigt von `mergeline2` (b010f75). **Nicht nach `main`
gemerged.** Gemessen mit `bash tools/ota/run.sh` (QEMU mit `-accel kvm`).

Die ausführliche Fassung mit der ehrlichen Fehlliste steht in
`docs/OTA.md`. Hier stehen nur die Zahlen und der Stand.

---

## Was diese Runde einlöst

`docs/UPDATE.md` schloss mit einer Fehlliste, deren erster Punkt lautete:

> „Die HTTPS-Strecke ist in dieser Runde nicht Ende-zu-Ende gelaufen. […]
> Es fehlt die Verdrahtung, nicht die Kryptographie: `fetch` ist ein
> `kernel/app/`-Programm und liegt in keinem der Abbilder."

Seit dieser Runde liegt es in jedem Abbild, und ein Gerät holt sich sein
Update selbst über HTTPS, prüft es und spielt es ein.

## Was gebaut wurde

| Datei | Zeilen | Was |
|---|---:|---|
| `kernel/user/ota.fi` | (siehe Läufer) | `/bin/ota` |
| `kernel/app/fetch.fi` | +90 | `Range`/Wiederaufnahme, `-o` schreibt den Rumpf |
| `tools/install/build.sh` | +60 | `fetch`, `ota`, `roots.pem`, `ota.conf` ins Abbild |
| `tools/install/oneshot.sh` | +35 | Netz für den Prüfstand, `-cpu` einstellbar |
| `tools/ota/server.py` | ~300 | die Gegenstelle |
| `tools/ota/listing.py` | ~190 | das signierte VERZEICHNIS |
| `tools/ota/mkcerts.py` | ~130 | die Zertifikate |
| `tools/ota/pakete.sh` | ~120 | sechs Quellen, vier davon kaputt |
| `tools/ota/run.sh` | ~560 | der Läufer |

## Wogegen gemessen wurde

**Es gibt keinen echten Update-Server im Internet.** Gemessen wurde gegen
`tools/ota/server.py` auf demselben Wirt: echtes TLS 1.3 aus Pythons
`ssl` (OpenSSL), ein echtes Zertifikat mit echter Kette aus Pythons
`cryptography`, echtes `Content-Length`, echtes `Range`/`206`, echte
Verbindungsabbrüche (RST). Das Gerät spricht darüber eine e1000 und
QEMUs Benutzernetz an, in dem 10.0.2.2 der Wirt ist.

## Der Befund, mit dem niemand gerechnet hat

`/bin/fetch` stirbt unter `-cpu max` mit `user fault: vector=6` (#UD).
Gemessen, gleiches Abbild, gleicher Kern, nur anderes `-cpu`:

| `-cpu` | dazu | Ergebnis |
|---|---|---|
| `qemu64` | SSE2 | läuft |
| `Nehalem` | SSE4.2 | läuft |
| `Westmere` | AES-NI | läuft |
| `SandyBridge` | AVX | läuft |
| `Haswell` | AVX2, BMI2 | läuft |
| `max` | AVX-512, SHA-NI | **#UD** |

Osum schaltet für Ring 3 weder `CR4.OSXSAVE` noch `XCR0` frei, und der
Kontextwechsel sichert keine Vektorregister; Firns Bibliothek fragt
`cpuid` und nimmt den breitesten Weg, den die Maschine anbietet. **Auf
einem Rechner mit AVX-512 ist der Update-Weg damit tot** — und das ist
Blech auf dem Tisch und nicht QEMU. Eine eigene Runde. Steht in
`docs/OTA.md` als Punkt 1 der Fehlliste.

Gemessen wird deshalb mit `-cpu Haswell`: ein echtes Prozessormodell,
kein Notbehelf, und alles, was dieser Kern kann, ist darin an.
