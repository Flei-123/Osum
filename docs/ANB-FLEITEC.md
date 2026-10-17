# Rücken `fleitec` — Anmelden mit Code (Device Flow)

Stand 17.10.2026. Dienst: `fleitec-id` (OIDC, RFC 8628). Kein Kennwort auf dem Gerät.

## Ablauf
- `konto anmelden --anbieter=fleitec --geraet` → Zustand `geraet`, Ausgabe `code`, `url`, `urlkomplett`, `zwischen` (Geräte-Code), `intervall`, `gueltig`. Rückgabecode 11.
- `... --geraet --zwischen=<code>` fragt EINMAL ab (pending → `geraet`, slow_down → `gebremst`, expired → `abgelaufen`, denied → `abgelehnt`, sonst Sitzung).
- `... --geraet --warten` fragt selbst ab (`intervall`, +5 s nach slow_down, bis `gueltig`).
- Scope: `openid profile offline_access fleitec.account`. Ohne `fleitec.account` trägt das Access-Token kein `uid` (nur `sub`) und die Brücke unten findet kein Konto.
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
- Die frühere LÜCKE (Broker-Token ist kein `fkt1.<konto>.<64 hex>`) ist durch die Brücke unten geschlossen; `socfleitec v1 login token <JWT>` lehnt ein JWT weiterhin ab (nur fkz1/fkm1/fkt1 sind Token).
- Start: `heavy bash tools/anbfleitec/interop.sh` (Env `FLEITEC_ID=<Ordner>`). Section 8 = Brücke (siehe unten).

## Brücke: Broker-Token gegen Buch-Token (fkt1) tauschen (r115b)
Trennung: `anb_fleitec`/`konto` = Anmeldung am Broker (Device-Flow, Scope `fleitec.account`). `socfleitec` = Zugang zum Adressbuch, inklusive Tausch.
- Ablauf: `konto anmelden --anbieter=fleitec --geraet --warten` → Access-Token (EdDSA-JWT, `aud` `orientos`, `uid`) → `socfleitec v1 login broker <JWT>` oder `socfleitec v1 login broker -f <Datei>` → `POST <url>/api/kontakte/zugang-broker` mit `Authorization: Bearer <JWT>` → Antwort `{"token":"fkt1.<uid>.<64 hex>"}` → das fkt1 steht danach als `token=` in `/etc/social/fleitec.conf` (wie bei `login token`). Ausgabe: `account <uid>` + `ok`.
- `-f <Datei>` liest das JWT aus einer Datei (Zeilenende am Schluss wird abgeschnitten). Nötig, weil die Shell des Geräts eine Zeile bei 255 Zeichen kappt und ein JWT länger ist; außerdem steht das Token so nicht in der Argumentliste. Die Datei danach selbst löschen.
- Das JWT wird nur als Bearer dieses einen Aufrufs gebraucht: nie ausgegeben, nie geloggt, nie in die Conf geschrieben (der Puffer wird nach dem Aufruf überschrieben). `url=` (IPv4) und `name=`/`roots=` müssen in der Conf stehen.
- Fehler: Buch lehnt ab (401/403) → `err denied`; nicht erreichbar → `err offline`; sonstiger Status → `err http <code>`; kein JWT-Format → `err bad`; Antwort ohne fkt1 → `err bad`. Ein abgelehnter Tausch lässt ein vorhandenes `token=` unberührt.
- Buch-Seite (FirnChat main b634eb8, `docs/LOGIN-OIDC.md`): prüft EdDSA/`kid`/`iss`/`aud`/`exp`/`nbf`/`sub`, `jti` Pflicht (ein id_token wird abgelehnt), Konto muss existieren. Ein neuer Tausch ersetzt nur den alten Broker-fkt1.
- Test: `interop.sh` Section 8. Mock-Buch `tools/anbfleitec/buch.py` hinter `proxy.py` (`--route /api/kontakte=…`) mit ECHTER Ed25519-Prüfung gegen das JWKS des echten Brokers und denselben Regeln wie FirnChat. Gemessen: Tausch klappt, fkt1 öffnet das Buch (`contacts`), JWT nirgends im Klartext (Ausgabe, Conf, Abbild); abgelehnt: fremde Signatur, id_token, falsches `aud`, abgelaufen (Uhr des Buchs vorgestellt), unbekanntes Konto, Müll; Kontrolle: dasselbe Token tauscht wieder, sobald das Buch zustimmt.
- Grenze des Tests: das Mock-Buch ist kein FirnChat. Die echte Gegenstelle prüft `tests/zugang-broker.mjs` im FirnChat-Repo (42, auch gegen den echten `fleitec-id`). Zusammen ergibt das noch keinen Lauf OrientOS-Gast gegen die echte `firnchat-web`-Binary.
- LIVE (nur mit Boss-Ja, Teil von L1–L7): im FirnChat-Dienst `broker-tausch = ja` und `broker-aud = orientos` setzen (dazu `--kontakte-port`/`--kontakte-key`, r106), Client `orientos-device` mit `aud` `orientos` und Scope `fleitec.account` im echten `fleitec-id` registrieren, auf dem Gerät `url=https://<IPv4>:<port>`, `name=`, `roots=` in `/etc/social/fleitec.conf`.

## Offen
- Client `orientos-device` mit `aud` `orientos` im echten Dienst registrieren (device_code-Grant) — vor Live, nur mit Boss-Ja.
- Live-Schaltung der Brücke (siehe oben, Boss-Ja).
- Optional später: ein Knopf „Konto anmelden“, der nach der Anmeldung den Tausch gleich selbst auslöst (heute zwei Schritte).
