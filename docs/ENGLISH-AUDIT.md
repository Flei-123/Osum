# English audit of the OrientOS terminal (PARTIAL -- first pass, 04.10.2026)

Rule (Justin, 04.10.2026): commands, sub-commands, identifiers, console/log text,
comments and commit messages are English. End-user UI text on the desktop stays as is.
This first pass lists what was FOUND by reading the command tables. It is not complete;
nothing is renamed yet.

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
