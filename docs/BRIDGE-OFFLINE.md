# Why the Dell left the bridge (04./05.10.2026), and what was built

## 1. Verdict (measured, not guessed)

The Dell did **not** go quiet because it was switched off or lost the network. At 04.10.2026 16:00:22 UTC
its normal polling (one POST every ~2 s) stopped; from 16:00:55 UTC it sent **one POST every ~30 s**
and has done so without a gap until now (proxy log of the ingress, ~119 per hour, hour after hour).

* Proof it is the Dell: a packet capture on the forwarder showed `X-Draht: a4206b26eb96739dee636355`
  (= the first 24 hex digits of the Dell's public key, kennung `osum-a4206b26eb96`), body
  `osum-bruecke 1 0` (the greeting), answer length 0.
* Where it fails: the sign-in sends the greeting, then must ask `/bin/jsig` for the key
  (`jsig_rufen`: `fork` + `execve`). Nothing further reaches the server (no `ich`, no log line), and a
  failing round makes the client wait 30 s (`erg == 1` -> `warte = 30000`). That is exactly the cadence.
  `fork` fails when the task table is full: `MAX_TASKS = 32`, the system holds ~18, and corpses of programs
  nobody `wait`s for keep their slot (docs/DELL-FOUR-BUGS.md section 1: "26 live tasks, `fork failed` for
  every `befehl`"). The image on the Dell predates the corpse sweep (kgui.zombie_sweep) and the fork-free `ps`/`kill`/`reboot`, and its sign-in always needs two forks (jsig).
* What is NOT known: what ended the 13-minute session at 16:00:22 (a failed poll, a protocol error?).
  It had been re-signing in about every 10-50 minutes all day (9 sign-ins 12:28-15:47 UTC), each one
  spending two forks on `jsig`.
* The Dell is therefore very probably **still running**. It can only be fixed by a restart (power off/on):
  without a sign-in the bridge cannot give it any command, and Wake-on-LAN does nothing for a machine
  that is already on.

Things checked and ruled out: server restarts (bruecke had run since 11:36 UTC, the host 3.5 days; no
traceback in the journal), proxy/forwarder (answers 200 now, public `/bruecke/gesund` ok), DHCP lease
(the router's lease is 10 days; this client has no renewal at all, see 6), idle lock (idlelock only sets
the lock; there is no automatic standby: docs/STANDBY-MEHRKERN.md), certificate or clock (the TLS
handshake succeeds every 30 s).

Found on the way: the forwarder (`orientstore/werkzeug/diagnose_server.py`) did **not pass `X-Draht` on**.
The bridge service saw the id `unbekannt` for every device, so all devices shared one wire state.
Fixed 05.10.2026 (header added to the forwarded list); the bridge now logs a warning if the header is
missing. The real client address stays hidden (NAT on the host: the proxy sees 192.168.1.1).

## 2. What the server records now (`bruecke_server.py`)

* `GET /bruecke/warum[?geraet=<kennung>]` (admin key): per device `zustand`, a one-sentence `kurz`,
  last contact (UTC and Vienna), session length, polls, longest gap, running/last job, an event ring.
  States: `online`, `beschaeftigt` (a command runs, old clients do not poll meanwhile), `klopft`
  (greetings but never `ich`: alive, sign-in fails ON the device), `sauber_beendet` (`tschuess`),
  `stumm` (silent, no reason on the wire: off / crashed / sleeping / network gone, not distinguishable),
  `nie`.
* `/srv/bruecke/status.json` keeps this over restarts (last contact, events, MAC).
  A watcher thread writes `STUMM`, `BESCHAEFTIGT`, `KLOPFT NUR AN`, `WIEDER DA` events to the journal
  the moment the state changes. Server restarts are written as events too.
* Jobs older than 900 s are dropped (`ttl_s` per job, 0 = never): a machine coming back after hours
  must not run commands queued for an earlier moment. (4 such jobs were waiting for the Dell.)
* New wire words: `lebt` (keepalive, hands out nothing) and `info mac=..` (the device reports its MAC).
* Wake-on-LAN: `POST /bruecke/wol {"geraet"|"mac", "broadcast":[..], "speichern":true}` and
  `{"was":"mac"}` on `/bruecke/koppeln`. See 4.

## 3. What the client does now (`kernel/app/jarvisd.fi`)

* **Keepalive**: while a `befehl` runs, `lebt` goes out every 20 s from inside the wait loop (before,
  the helper was silent for up to `command_timeout`, 1200 s on the Dell, and showed as offline).
* **Address forgotten after a failed round**: the DNS is asked again (before, a changed answer was never
  noticed).
* **Supervisor + watchdog**: the kernel starts `jarvisd` once (`desk_start`), nothing restarted it.
  Now the service forks a worker and restarts it when it ends, or when it has had no good contact for
  `watchdog` seconds (`/etc/jarvis/permissions.conf`, default 600, 0 = off, minimum 20). The worker
  rewrites `/var/jarvis/alive` after every good exchange (at most every 30 s). Only over 443 and only
  when started without arguments.
* **`info mac=<hex>`** after every sign-in, so the server knows the MAC.

Cost: the supervisor is one more task (the table has 32 slots, ~18 used by the system): one program less can be open at the same time.

Limit: if `fork` itself is refused, the supervisor cannot start a new worker either; it retries every
10 s. The corpse sweep of the new kernel (docs/DELL-FOUR-BUGS.md) is what prevents that state.

## 4. Getting a machine back

| Situation | What works |
|---|---|
| Machine on but stuck (the Dell now) | power button 5 s, then on again (or a smart plug) |
| Machine off, BIOS WoL on, a device in ITS network | magic packet from there (`tools/wol/wol.py`, PowerShell line in its header) |
| Machine off, nothing in its network | smart plug + BIOS "AC Recovery = Power On" |

The JARVIS server is in another network than the Dell (server: Fritz!Box 192.168.178.x at the Mieming
house, Dell: Justin's own home), so a packet from the server cannot arrive. `POST /bruecke/wol` only
helps for devices in the server's own broadcast domain.

Dell OptiPlex 9020 BIOS: Power Management -> Wake on LAN = *LAN Only* (or *LAN with PXE Boot*),
Deep Sleep Control = disabled; for a plug: AC Recovery = *Power On*. **Not tested on the real Dell**;
whether OrientOS leaves the NIC armed at shutdown is unknown (the e1000e driver may reset the chip).
The MAC is only known after the first sign-in with a client that sends `info` (the server stores it).

## 5. Tests

* `tools/bruecke-server/test_warum.py`: 38 checks (states, events, restart survival, TTL, MAC, WoL packet
  bytes, knock detection).
* VM (image of branch `bridge-watch`, `watchdog = 30`, `command_timeout = 300`, vm-device key) against the live
  bridge: sign-in + `info` MAC (525400123456 = QEMU's e1000), supervisor on the serial line, job ok, a 130 s
  `/bin/sleep` with the server's 90 s silence limit stays `online` throughout (keepalive), `kill <worker>` ->
  new worker under the same supervisor signs in again, network cut for >30 s -> the supervisor kills the worker
  after 33 s ("worker silent too long"), network back -> signed in again. 12/12.
* Not exercised in a VM: DNS answer change (the reset of the cached address is a two-line change, compiled only).

## 6. Not done / open

* DHCP lease renewal (`dhcp.fi` asks once; the Fritz!Box lease is 10 days, other routers 1-24 h).
* Real client IP in the bridge log (needs the host's NAT to keep the source, or a header from outside).
* Taskbar sync/offline indicator for the bridge.
* Smart plug integration (needs a plug and a path into the Dell's network).
