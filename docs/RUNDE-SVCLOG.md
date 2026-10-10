# Round SVCLOG: service output, autostart of `jarvisd`, Dell offline (10.10.2026)

## B. Service output in the terminal window

Dell photo: the terminal (`sh`) kept filling with `fetch: ...` lines.

Cause (read in the code):
- `kgui.desk_spawn_n` gives every desktop program fd 1/2 = a log terminal that only writes to the serial line (`protokoll_binden`).
- `file.inherit_std` (called by `elf.spawn`) swaps exactly that log terminal against the console entries for every child, so that a `sh` from the start menu writes into the terminal window (SINK_WINDOW).
- `ota` (service, started by the desktop) starts `/bin/fetch` with `elf.spawn` every 30 s while there is no network -> `fetch` is a child of a log-bound process -> it gets the console -> its error line lands in the terminal window.

Fix:
- Services (`dhcp`, `jarvisd`, `ota`, `sntp`) are started with `kgui.desk_spawn_svc`: they get a SECOND log terminal (same sink, serial line) that `inherit_std` does not swap. Children, grandchildren, fork and exec inherit it unchanged. `sh` from the start menu is unchanged.
- Boot word `svccon` = control sample (old behaviour).
- `jarvisd` itself keeps writing its protocol to `/var/log/jarvisd.log` (unchanged).
- Test: `tools/svclog/run.sh` (fix: `fetch:` on the serial line, 0 rows in the window cells; control `svccon`: rows in the window).

Not done: `ota`/`fetch` text is not written to a file yet (the serial line is not readable on the Dell). Tests read `ota:`/`dhcp:` from the serial line, so redirecting them to `/var/log` needs its own round (roadmap).

## C. Dell offline

Evidence (files in /srv/bruecke):
- `geraete/osum-a4206b26eb96/154531-170.txt` (read from the Dell, 08.10. 15:45 UTC) is the STICK menu: `default_entry: 1`, `timeout: 20`, entry 1 `/OrientOS` has `dhcp jarvis ... anmeldung absturzneustart`. So the default entry DOES start `jarvisd`.
- `154535-171.txt` (`ps`, 08.10. 15:45 UTC): `jarvisd` pid 27 with parent 1 (the autostart supervisor) and its worker pid 115 were running when the Boss started `jarvisd` by hand (pid 157 under `sh` pid 152, worker 158). The autostart was NOT missing.
- `status.json` events from 17:14 UTC on show the consequence: sessions of 29..30 s ending "without goodbye" (two helpers fighting for the same key), then `KLOPFT NUR AN` (greeting, never `ich`; the sign-in did not work on the device), 21+ times until 18:25 UTC.
- Between 07.10. 22:59 and 08.10. 15:45 UTC no file exists because files only appear when somebody sends a command; the bridge keeps only the last session (`status.json` ring of 80 events starting 08.10. 17:14), so the reason for the silence in that gap is NOT provable from the files. Not claimed.

Changes:
- The installer wrote an entry WITHOUT `absturzneustart` (`kernel/user/installer.fi`, `lim_text`, `lim_dual1`): after a kernel panic an installed disk would stay on the panic screen (`absturzhalt`) forever. Both now carry `absturzneustart` like the stick menu.
- `kgui.jarvis_watch`: the desktop loop watches the process the boot word `jarvis` started. Gone or zombie -> restart after 5 s, doubling up to 60 s; a run of >= 2 min resets the back-off. (`jarvisd` already restarts its worker with the same back-off; nothing watched the supervisor itself.)
- Test: `tools/svclog/respawn.sh`.

Wait times (from the code, not measured on the Dell): boot word order is `dhcp` first, then `jarvis` (so the name server is in `/etc/resolv.conf`); `jarvisd` retries a failed connection with back-off (250 ms .. 30 s); sign-in happens right after the TLS connection to `store.fleitec.com:443` (log line `session signed-in` in `/var/log/jarvisd.log`).
