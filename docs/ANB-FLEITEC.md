# Rücken `fleitec` — Anmelden mit Code (Device Flow)

Stand 17.10.2026. Dienst: `fleitec-id` (OIDC, RFC 8628). Kein Kennwort auf dem Gerät.

## Ablauf
- `konto anmelden --anbieter=fleitec --geraet` → Zustand `geraet`, Ausgabe `code`, `url`, `urlkomplett`, `zwischen` (Geräte-Code), `intervall`, `gueltig`. Rückgabecode 11.
- `... --geraet --zwischen=<code>` fragt EINMAL ab (pending → `geraet`, slow_down → `gebremst`, expired → `abgelaufen`, denied → `abgelehnt`, sonst Sitzung).
- `... --geraet --warten` fragt selbst ab (`intervall`, +5 s nach slow_down, bis `gueltig`).
- Optionen `--client` (Standard `orientos-device`) und `--aud` (Standard `orientos`): Platzhalter, bis der Client im Dienst eingetragen ist.
- Einstellungen → Konten: Knopf „Mit Code anmelden" (erster Klick zeigt Code + Adresse, jeder weitere fragt einmal ab).

## Prüfung der Token (`kernel/app/kjwt.fi`)
- Regeln = `docs/fleitec-id/vectors_v2.json` (Gruppe `jwt_eddsa`, 34 Fälle): `alg` exakt `EdDSA`, `kid` Pflicht (JWKS-Suche), strikte base64url, `iss` oktettgenau, `aud`, `exp`, `nbf`, `sub`.
- Erwartetes `iss` = Ziel-URL des Geräts, nie ein Wert aus Token oder Discovery. Endpunkt-Pfade fest.
- id_token (falls da) muss auch stimmen und dieselbe `sub` nennen.

## Kopien der Krypto-Module
- Firn benennt ein Modul nach dem LETZTEN Importsegment. TLS (`std.crypto.big`, `std.crypto.sha512`) kollidiert mit `lib/crypto/big|sha512`.
- Deshalb `kernel/app/{kbig,ksha512,ked25519}.fi`, erzeugt von `tools/anbfleitec/mkcopies.sh` (`--check` im Test).

## Test
- `bash tools/anbfleitec/run.sh` (schwer: `heavy`). Mock-IdP `tools/anbfleitec/idp.py` über TLS 1.3.
- Gemessen: alle 34 Vektoren im Gast; approve, slow_down (+5 s), denied, expired; 9 kaputte Token; kein Token im Klartext im Abbild (Gegenprobe `--kaputt=klartext`); Rotation + Replay; Abmelden ruft `/oidc/revoke`; ohne Netz bleibt die Sitzung.

## Interop gegen den echten Broker (`tools/anbfleitec/interop.sh`)
- Der Gast spricht mit dem ECHTEN `fleitec-id` (node, `--fake`, Client `orientos-device`/aud `orientos` per `--device-client`), über einen TLS-1.3-Terminator (`proxy.py`; der Gast kann nur HTTPS). Der „Mensch am anderen Gerät“ ist `approve.py` (Login + CSRF + Bestätigen/Ablehnen wie ein Browser).
- Gemessen (68/0): Discovery + JWKS; Device-Flow in zwei Schritten und mit `--warten`; Subjekt/aud/iss/exp im Gast = Token des Brokers; abgelehnt, abgelaufen, slow_down (Host-Vorabfrage), falsches `--aud`, unbekannter Client, Device-Code zweimal; Refresh-Rotation, Replay tötet die Familie (am Broker geprüft); Abmelden → `POST /oidc/revoke`; kein Token im Klartext im Abbild; kein Cookie/Authorization vom Gast.
- Kein Fehler in `anb_fleitec` gefunden. Beobachtung: ein einzelnes `--zwischen`-Abfragen gibt bei `gebremst` kein neues `intervall` aus (das +5 steckt nur in der `--warten`-Schleife; der Einstellungsdialog fragt pro Klick, braucht es nicht).
- LÜCKE: ein Broker-Token (EdDSA-JWT) ist KEIN `fkt1.<konto>.<64 hex>`. `socfleitec v1 login token <JWT>` wird abgelehnt (gemessen). Die Brücke OIDC-Sitzung → fkt1 fehlt noch (fleikontakte kennt keine OIDC-Sitzung, r106).
- Start: `heavy bash tools/anbfleitec/interop.sh` (Env `FLEITEC_ID=<Ordner>`).

## Offen
- Client `orientos-device` mit `aud` `orientos` im echten Dienst registrieren (device_code-Grant) — vor Live, nur mit Boss-Ja.
- Brücke OIDC-Sitzung → fkt1 für `socfleitec` (r106).
