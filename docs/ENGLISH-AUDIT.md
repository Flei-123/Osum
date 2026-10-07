# English audit of the OrientOS terminal (PARTIAL -- first pass, 04.10.2026)

Rule (Justin, 04.10.2026): commands, sub-commands, identifiers, console/log text,
comments and commit messages are English. End-user UI text on the desktop stays as is.
This pass lists what was FOUND by reading the command tables. It is not complete.

## Status (04.10.2026)

DONE (E-001 step 1): `ota`, `opk`, `stored` (arguments it passes), `settingsd` (arguments it
passes to ota): sub-commands and console messages are English; tests, living docs and
`tools/` follow. Bridge job kinds: the device (`jarvisd`) accepts BOTH spellings
(read/write/list/command/photo/input and lies/schreib/liste/befehl/foto/eingabe); the server
(`lib/osumbridge.js`, `/root/bruecke/bruecke_server.py`) sends German by default and English
with `OSUM_JOB_KINDS=en` / `BRUECKE_JOB_KINDS=en`; `dell-update.py` uses `DELL_KINDS=en`.
Flip the defaults once the Dell runs an image with E-001, then delete the German words.

DONE (E-001 step 2, 04.10.2026): program names and their sub-commands / console lines:

| German program | English | sub-commands |
|---|---|---|
| tresor | vault | neu/auf/zu/legen/gib/liste -> new/open/close/put/get/list |
| auswerfen | eject | (no sub-commands; texts English; `explorer: eject` marker) |
| praesenz | presence | dienst/setzen/fokus/weg/da/unsichtbar an/zeigen -> service/set/focus/away/back/invisible on/show |
| sperrwache | idlelock | -- |
| netzmess | netmeter | -- (`netmeter: done`) |
| kontocli | accountcli | -- (`accountcli: ERROR`) |

Kept German on purpose: bus service name `praesenz`, `/etc/praesenz.conf`, `/etc/sperre.conf` and
its keys, the state words `da abwesend beschaeftigt unsichtbar` (wire protocol with the friends
server), the mount point `/tresor`, `/system/tresor.sit`.

DONE (E-001 step 3, 07.10.2026): program `papierkorb` -> `trashbin` (sub-commands list/put/restore/remove/empty; the old
German words are still understood; data stays: `<root>/.papierkorb`, `/etc/papierkorb.conf`), `drucke` -> `ipprint`
(output keys and states English: `state=nonet|rejected|...`; `/etc/printer.conf` with `target=` first, the old
`/etc/drucker.conf` with `ziel=` as a fall-back), module `dateiop` -> `fileop`. The guard `tools/english/run.sh`
(test.sh section 58) keeps the counts from growing; `count.py --diff <base>` checks new lines.

STILL GERMAN (next steps): `papierkorb`, `dispctl` console lines, `drucke`, `hurt` (an English word -- stays),
`instkonto` (module), the kernel log (`/bin/log`: "Karte gefunden", ...), comments and identifiers
inside the sources (see tools/english for the identifier renamer).

KEPT GERMAN ON PURPOSE (data formats, not commands -- renaming breaks signed or persisted data):
* feed/wire: `VERZEICHNIS`, `INDEX`, field names `paket`, `fassung`, `gesperrt`, `schluesselgen`,
  `kette`, the signed text `osum-schluessel`, package members `PAKET/SYSTEM/PLAN/GRUND`
* files: `/system/FASSUNG`, `AKTUELL`, `ERPROBUNG`, `GESPERRT`, `ota.stand`, `schluessel.pub`
* config keys of `/etc/ota.conf` (`quelle abstand frist kanal gesund`), `/etc/store.conf`,
  `/etc/ntp.conf` values -- needs a config migration
* state words shared with the settings/store windows (`ruhe verfuegbar bereit fehler laedt fertig`)
* the other bridge wire words (`hallo gruss beweis puls fertig tschuess weg auftrag`)
* identifiers and comments inside the sources (no user-visible effect)

## Sub-commands found (German -> proposed English)

| Program | German today | English |
|---|---|---|
| ota | suchen, zeigen, holen, einspielen, bestaetigen, zurueck, wachhund, dienst, einstellungen, einstellen, aktualisieren, richten, erprobung | search, show, fetch, apply, confirm, rollback, watchdog, service, settings, set, update, settle, trial |
| opk | liste, katalog, installieren, entfernen, aktualisieren, generationen, zurueck/zurück, richten, pruefen/prüfen, erprobung | list, catalog, install, remove, update, generations, rollback, settle, verify, trial |
| stored | katalog, holen, aktualisieren, entfernen | catalog, fetch, update, remove |
| installer (window args) | zeig, sofort, zweite, daneben | show, now, second, beside |
| jarvis bridge job kinds (`art`) | schreib, befehl, ... | write, command, ... (list the rest from the bridge server) |

Console/log lines are German too (`ota: fassung hier`, `alles aktuell`, `nicht zu holen`,
`fetch: aufgeloest`, `sntp:` is already English). Kernel log (`/bin/log`) is German
("Karte gefunden", "eingehängt").

## Where the old names are used (must change together)

* ~46 files outside the kernel sources: docs/ (15), tools/ota (7), tools/operation (3),
  tools/loader (2), tools/usbimg, tools/stick, tools/avx; tests grep the German output
  text (`fassung hier`, `NEUE FASSUNG`, `RUECKSCHRITT ABGELEHNT`, `alles aktuell` ...).
* `/root/abbilder/dell-update.py` and the bridge server send `befehl` / `schreib` jobs.

## Risks to decide before the rename

1. **Bridge protocol.** The Dell runs a6dd7fad with German job kinds. If the server
   switches to English kinds first, the running Dell cannot be reached any more.
   Needs a compat window (server accepts both) or an update of the Dell first.
2. **Rollback / old feed.** `ota` on already-installed devices is German; scripts that
   drive old devices (dell-update.py, feedtest.sh against old images) need the old names.
3. **No alias** was requested, so old tests must be converted in the same commit.

## Proposed order

1. Complete this list for every program in `kernel/user/*.fi` (225 files) and `/bin`.
2. Rename in one branch per program family (ota/opk/stored, installer, bridge), tests
   converted with it; run ota, loader, operation, installer, k15 suites via heavy.
3. Bridge: server accepts both kinds, then device, then drop the German kinds.
