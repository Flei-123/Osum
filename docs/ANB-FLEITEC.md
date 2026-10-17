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
- Grenze des schnellen Laufs: das Mock-Buch ist kein FirnChat. Den Lauf gegen die ECHTE `firnchat-web` gibt es als eigenes Skript, siehe unten.
- LIVE (nur mit Boss-Ja, Teil von L1–L7): im FirnChat-Dienst `broker-tausch = ja` und `broker-aud = orientos` setzen (dazu `--kontakte-port`/`--kontakte-key`, r106), Client `orientos-device` mit `aud` `orientos` und Scope `fleitec.account` im echten `fleitec-id` registrieren, auf dem Gerät `url=https://<IPv4>:<port>`, `name=`, `roots=` in `/etc/social/fleitec.conf`.

## Interop gegen die ECHTE FirnChat (`tools/anbfleitec/interop-real.sh`, r120)
Nichts ist gemockt: OrientOS-Gast (`konto`, `socfleitec`) → `proxy.py` (TLS 1.3, Pfad-Routing) → `/api/kontakte` an die echte `firnchat-web` (mit echtem `fleikontakte` dahinter), alles andere an den echten `fleitec-id --fake`. `firnchat-web` erreicht den Broker als OIDC-Issuer selbst über https (`https://10.9.0.1:8443`, `ca-datei` = Test-CA). Das schnelle Mock-Buch (`interop.sh` Section 8) bleibt daneben bestehen.
- Start: `heavy bash tools/anbfleitec/interop-real.sh` (~5 min, ~12 Gast-Starts). Env: `FLEITEC_ID`, `FIRNCHAT` (HEAD wird in den Temp-Ordner gebaut: `firnchat`, `firnchat-web`, `fleikontakte`), `FIRNCHAT_BIN` (fertige Binaries, kein Build), `FC_FIRNC`/`FC_FIRNLIB`. Es bleibt nichts im Repo zurück (alles `mktemp -d`, Netns/Veth/Prozesse werden beendet).
- Einrichtung wie in `LOGIN-OIDC.md`: `anbieter.conf` `typ = oidc`, Issuer des Brokers, `broker-tausch = ja`, `broker-aud = orientos`, `broker-sperrliste`, `broker-audit`; `--kontakte-port`/`--kontakte-key`; `fleikontakte --proxy-key`. Der Broker hat zwei Geräte-Clients: `orientos-device` (aud `orientos`) und `other-device` (aud `other-product`, für das echte „falsche Audience“), plus `--client-redirect` für den Web-Login.
- Konto: `zugang-broker` legt nie ein Konto an. Es entsteht durch den Web-Login der Person (`tools/anbfleitec/weblogin.py`, Browser-Ablauf gegen den echten Broker, `auto-konto = ja`) → `jarvis:u_FAKEjustin01`. Vorher (Section 2) wird ein gültiges Token abgelehnt (`[no account]`).
- Frische Tokens: `tools/anbfleitec/devtoken.py` holt per Device-Flow ohne Gast beliebig viele frische Access-Tokens (die echte FirnChat tauscht ein Token nur EINMAL, r121). Der Gast meldet sich zusätzlich selbst an (`konto anmelden … --warten`) und tauscht dessen Token.
- „Abgelaufen“ ist echt: `fleitec-id --fake --access-ttl 1` stellt ein 1-s-Token aus, das erst >70 s später benutzt wird (die Bibliothek lässt 60 s Toleranz). Dafür gibt es in `fleitec-id` die neuen Fake-Optionen `--access-ttl` und `--device-client ID:AUD,ID:AUD`.
- Gemessen: Device-Flow → `socfleitec v1 login broker -f` → echtes `fkt1.<uid>.<64 hex>` → `contacts` ok; das fkt1 öffnet das Buch auch auf dem Host (200) und darf das Profil nicht ändern (403); JWT nie in Ausgabe/Conf/Abbild/Server-Log/Audit. Abgelehnt von der ECHTEN Prüfung, jeweils mit dem Grund aus dem Server-Log: fremde Signatur `[sig]`, id_token `[aud]`, falsches Audience `[aud]`, abgelaufen `[expired]`, unbekanntes Konto `[no account]`; Müll und fehlende Datei kommen gar nicht erst vom Gerät. Ein abgelehntes Token lässt ein gespeichertes fkt1 stehen. Dasselbe Token zweimal → zweiter Tausch `err denied` (jti); frisches Token tauscht wieder.
- Schutz (r121) am gleichen Pfad: Sperrliste (`jti`, `konto`; wirkt ohne Neustart, ein Block verbraucht das Token nicht), Bremse (Garbage-Stoß → 401, ab dem Limit 429 mit `Retry-After`, auch für ein GÜLTIGES Token, das nach dem Fenster noch tauscht), Audit-Datei (`swap`/`deny replay`/`deny blocked`, kein Token darin).
- FUND (nicht behoben): der Zertifikatsprüfer von Firn (`lib/tls/x509.fi`) kennt nur `dNSName`-Einträge, keinen `iPAddress`. `firnchat-web` lehnt ein Zertifikat, das nur für die IP gilt, ab (`unreachable`); gemessen im ersten Lauf (mkcerts-Zertifikat mit IP-SAN). Der Test setzt deshalb im Zertifikat zusätzlich den TEXT `10.9.0.1` als `dNSName`. Der Gast kann umgekehrt nur IPv4-Ziele (`knetz.target_read`), also muss sein Issuer-Text die IP sein — beides zusammen heißt: ein echter Broker mit DNS-Namen als Issuer braucht Namensauflösung im Gast (r34), und ein IP-Issuer braucht IP-SAN-Unterstützung in Firn.

## Übergabe `konto` → `socfleitec`: Anmelden + Tausch in einem Schritt (`--tauschen`)
- `konto anmelden --anbieter=fleitec --geraet --warten --tauschen` (auch mit `--zwischen=<code> --tauschen`): nach erfolgreicher Anmeldung und gespeicherter Sitzung ruft `konto` den Hook `anbieter.tu_uebergeben` des Rückens; `anb_fleitec` startet `/bin/socfleitec v1 login broker -s` (fork + Röhre + execve). Der allgemeine Teil (`account.fi`) kennt weder `socfleitec` noch das Ziel (Trennungswache `tools/account/split.py`); Rücken ohne Übergabe (jarvis, xoffi, eigen) melden `fehler` und schreibt das Access-Token in dessen stdin. `socfleitec` tauscht es (siehe Brücke) und schreibt NUR das fkt1 in `/etc/social/fleitec.conf`.
- Das JWT steht nie in einer Datei, nie in argv (Prozessliste), nie in der Ausgabe oder im Log. Beide Seiten überschreiben ihren Puffer (konto: `s.zugriff` und Lesepuffer, socfleitec: Lesepuffer + Bearer-Kopie). `socfleitec v1 login broker -s` liest nur die erste Zeile von stdin (bis 4096 Zeichen).
- Reihenfolge: ERST Sitzung siegeln, DANN tauschen. Ein Fehlschlag beim Tausch macht die Anmeldung nicht rückgängig und lässt ein vorhandenes `token=` in der Conf unberührt.
- Ausgabe: `konto: tausch = ok|keinnetz|abgelehnt|fehler` (dazu die Zeilen `account <uid>` / `ok` bzw. `err ...` von `socfleitec`). Rückgabecode: ok 0, keinnetz 5 (`RC_KEINNETZ`), abgelehnt 6 (`RC_ABGELEHNT`), sonst 8. Fehlt dem Token die `uid` (Scope `fleitec.account` fehlt), meldet `anb_fleitec` `abgelehnt` mit `hinweis` (`konto.hint.noscope`) schon VOR dem Senden: es geht nichts ins Netz.
- `--tauschen` ohne `--geraet` wird abgelehnt (Rückgabe 2). `url=`/`name=`/`roots=` müssen in der Conf stehen (wie bei `login broker`).
- Ein Token wird genau EINMAL getauscht: der Tausch läuft einmal pro Anmeldung, es gibt keinen Wiederholversuch und kein Zwischenspeichern des Access-Tokens (wichtig für die jti-Sperre am FirnChat-Endpunkt).
- Test: `interop.sh` Section 8d (ein Schritt ohne Datei; abgelehnter Tausch auf demselben Abbild lässt Sitzung und altes fkt1 stehen; Buch offline; `--tauschen` ohne `--geraet`).
- Einstellungen → Konten: kein Knopf. Der Dialog reicht `--tauschen` nicht durch, weil er jeden Rückgabecode ≠ 0 als Fehlschlag der Anmeldung zeigt; das braucht eine eigene Meldung (siehe Offen).

## Offen
- Client `orientos-device` mit `aud` `orientos` im echten Dienst registrieren (device_code-Grant) — vor Live, nur mit Boss-Ja.
- Live-Schaltung der Brücke (siehe oben, Boss-Ja).
- Einstellungen → Konten: Knopf bzw. Haken „Adressbuch verbinden“ (`--tauschen`) mit eigener Meldung für `tausch = …`.
