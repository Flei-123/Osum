# Bridge pairing by number (design)

Status: design only, nothing built yet. Date 25.10.2026.

## Goal

Pairing like the Windows helper, for an OrientOS device:

- The device shows a numeric code, big (jarvisctl status, tray, mini).
- The boss types the code into the JARVIS web UI (devices page) or tells it to the chat ("pair OrientOS code 123456").
- Done. No admin curl, no hex comparison, no `jarvisctl pair` on the device.
- The device then shows up in `list_devices` as type `OrientOS`, usable with remote_shell / remote_read / remote_write / remote_search / computer screenshot, bound to the boss' account.

## What exists today (findings)

### Windows helper (server.js)

- `POST /api/pair/new` (session): 8-char code in the in-memory map `pairCodes` (`code -> {uid, exp}`, 10 min, single use). The web page shows it.
- `POST /api/pair/redeem` (no session, rate limit `loginguard` per IP): the helper sends the code, gets `{server, token: user.deviceToken, username}`.
- The helper opens a WebSocket with `role=device` + token. The server knows the account from the token and calls `registerDevice(uid, name, bridge)`.
- Registry: `devices: Map<uid, Map<name, bridge>>`. Tools call only `connected()` and `request(type, payload, timeoutMs)` on the entry. `list_devices` reads `userDeviceInfo(uid)`.
- So the account binding of a Windows device is the token, the code only moves the token to the device.

### OrientOS today

- Device `jarvisd` talks the wire protocol (line + payload) tunnelled in HTTPS POSTs (`/bruecke/draht`, header `X-Draht`) through the store proxy to the Bruecke service (`/root/bruecke/bruecke_server.py`, 127.0.0.1:8090, state `/srv/bruecke`).
- Identity = Ed25519 key in `jsig`. Device id = `osum-` + first 12 hex of the public key. No account token on the device.
- Unknown device sends `ich <pub>`: bridge creates the entry, makes a 6-digit code (`g.code`, no expiry, one per device), answers `kopplung-noetig <hex of the digits>`.
- Device `jarvisd` writes the code to `/var/jarvis/pairing`, then waits for the human to run `jarvisctl pair <code>` on the device (writes `/var/jarvis/pairing-ok`). Without it: `kopplung-abgelehnt`, disconnect.
- The bridge only completes the pairing when the ADMIN calls `POST /bruecke/koppeln {geraet, code}` with the file key `/srv/bruecke/verwalter.key` (curl on the server). Also `was=vorab` (pre-paired key baked into an image: `HP_STICK=1` with `/root/abbilder/hp-device.key`).
- Jarvis side: `lib/osumBridgeDevices.js` (`BridgeWatcher`, `BridgeDevice`, device type `OrientOS`). It polls `GET /bruecke/geraete` every 10 s and shows ONLY devices pinned in `data/bruecke_devices.json` (`{id, name, uid?}`; without `uid` the device belongs to all admins). Jobs: `POST /bruecke/auftrag` + `GET /bruecke/holen`.
- Job kinds today (German on the wire): `befehl`, `lies`, `schreib`, `liste`, `foto`, `system`. The mapping to tools is in `BridgeDevice.fs()` and `BridgeDevice.computer()`.
- Second, unused path: `lib/osumbridge.js` (TLS listener 8443, own `Koppelbuch` data/osum_devices.json, `POST /api/osum/pair` reverse flow). It was never used, the home network cannot be reached from outside. Keep as is, do not extend. Remove after the new flow works.

### Why the HP is missing in list_devices

- `data/bruecke_devices.json` pins `osum-a4206b26eb96` (Dell), `osum-3807242d1d62` (VM), `osum-13c1e04076bf` ("HP-ORIENTOS", the key baked in the image).
- The real HP is `osum-07278ff1aafb` (paired by hand). It is paired in the bridge but pinned nowhere, so only `/srv/bruecke` knows it.

## Flow

```
device                      bridge (/bridge/*)               jarvis server                 boss
  | ich <pub>  ------------->  |                                |                          |
  |                            | new pending entry, code 6 digits, ttl 10 min              |
  | <---- pairing-needed <digits> (hex of the digits, as today) |                          |
  | shows code big (status/tray/mini), re-asks `ich` every 3 s  |                          |
  |                            |                                | <--- POST /api/bridge/pair {code}   (web or chat tool)
  |                            | <--- POST /bridge/pair {code} (admin key)                 |
  |                            | match, mark paired, return {id, info}                     |
  |                            | ---------------------------->  | bind id -> uid, name, save, attach, broadcastDevices
  | ich <pub>  ------------->  | paired: challenge                                         |
  | <---- challenge, signs, welcome                              |                          |
  |                            |  heartbeat -> online           | list_devices shows it     |
```

Steps in words:

1. Device shows the code. It keeps asking (`ich`) every 3 s while pending, so the screen switches to "Connected" within seconds after the boss typed the code. No local confirmation.
2. Boss types the code (devices page, or chat tool `pair_device`).
3. Jarvis shows what it found BEFORE binding when called with `confirm=false` (device name, IP, resolution, commit): "HP EliteBook at 192.168.x.x, pair?". The web UI uses the two-step; the chat tool does both steps in one call only when the user said "pair" with the code.
4. Jarvis calls the bridge, gets the device id, stores the binding for the logged-in account, attaches the device to the registry at once (no restart), pushes `broadcastDevices(uid)`.

## Endpoints

English names, aligned with the bridge rename (paths `/bridge/...`, see reports/20261025-W-bridge-english.md when merged; if the names there differ, take theirs and keep the semantics).

### Bridge service (admin key `X-Bridge-Admin`, formerly `X-Bruecke-Verwalter`; loopback only)

| Method + path | Body | Answer | Notes |
|---|---|---|---|
| `GET /bridge/pending` | - | `{pending:[{id, ip, info, age_s}]}` | NO codes in the answer. For the UI hint "1 device waits". |
| `POST /bridge/pair` | `{code}` | `{paired:true, id, info}` or 404 `no match` or 429 | Finds the pending device with that code (constant-time compare over all pending), marks paired, clears code. Replaces `POST /bruecke/koppeln` for the code case. `peek:true` returns `{id, info}` without pairing (step 3). |
| `POST /bridge/forget` | `{device}` | `{ok}` | Unpair (keeps the block flag logic of `sperren`), device must pair again. |
| `GET /bridge/devices` | - | as today (`kennung` becomes `id`) | Already used by the watcher. |
| jobs | - | as today | Job kinds renamed `command, read, write, list, photo, system` (English worker). |

Bridge rules for the code:

- 6 digits, from `secrets`, unique among pending entries.
- TTL 10 min; after expiry a new code is made on the next `ich` (today the code never expires).
- Pending cap: at most 20 unpaired entries; oldest pending is dropped first. Today every stranger can create entries.
- Wrong-code limiter inside the bridge: 5 wrong attempts per 10 min globally, then `POST /bridge/pair` answers 429 and all current pending codes are re-rolled. This is the real guard, the Jarvis-side limiter only adds to it.
- `was=vorab` stays (renamed `preset`), used by image builds, same admin key.

### Jarvis server (session cookie, admin accounts first)

Put in one new module `lib/bridgePairing.js`, server.js only mounts it.

| Method + path | Body | Answer |
|---|---|---|
| `POST /api/bridge/pair` | `{code, name?, confirm?}` | `confirm:false` -> `{found:true, id, info}`; `confirm:true` -> `{ok:true, name}` |
| `GET /api/bridge/devices` | - | `[{id, name, online, lastSeenAgo, pairedAt}]` for this account |
| `POST /api/bridge/forget` | `{id}` | `{ok}` (calls `/bridge/forget`, removes the binding) |
| `GET /api/bridge/pending` | - | `{count}` only, so the page can say "a device waits for a code" |

Chat: new tool `pair_device(code, name?)` in `lib/tools.js`, same function as the web route (`lib/bridgePairing.js: pairByCode(uid, code, name)`). Add one line to `systemPrompt.js` tool list. Rate limit with `loginguard` keys `bridgepair:<uid>` and `bridgepair:<ip>`.

## Data model

Bridge (`/srv/bruecke/koppelbuch.json`, existing, fields stay): `pubkey, paired, blocked, code, code_expires (new), info, mac`. The bridge knows NO account. That keeps it multi-tenant ready.

Jarvis `data/bridge_devices.json` (new, replaces `data/bruecke_devices.json`; the old file is read as fallback and migrated on first start):

```
{ "devices": [ { "id": "osum-07278ff1aafb", "name": "HP", "uid": "<account uid>", "pairedAt": 1790000000000 } ] }
```

- `uid` is mandatory for new entries. Entries without `uid` (legacy) keep meaning "all admins".
- Name is unique per account. `pair` without `name` uses `info.rechner` of the device, else `OrientOS-<last 4 of id>`.
- `BridgeWatcher` change: the device set becomes mutable. New methods `addDevice({id,name,uid})`, `removeDevice(id)`, `reload()`. `poll()` calls `reload()` when the file mtime changed, so editing the file also works without a restart.

## Attaching to the device manager

No change in tools. `BridgeDevice` already implements `connected()` and `request()`; `userDeviceInfo(uid)` already appends `bridgeWatch.describeFor(uid)`; `list_devices` shows `type: 'OrientOS'`.

Job kind mapping (tool -> bridge job -> device):

| Tool | `fs_request.op` / action | Bridge job | Device right (`permissions.conf`) |
|---|---|---|---|
| remote_shell | `run` | `command` | `commands` + `command_allowed` |
| remote_read | `read` | `read` | `read` |
| remote_write | `write` | `write` | `write` |
| remote_search | `search` | `list` | `list` |
| computer screenshot | `screenshot` | `photo` | `screenshot` + photo permit |
| (info) | - | `system` | `sysinfo` |

Not offered (clear error text already in `BridgeDevice.fs()`): mkdir, delete, deliver, powershell, UI automation. Possible later: `deliver` via bridge `dl`, `mkdir` via `command`.

## Security

- The code only chooses WHICH pending device. It carries no secret to the device. The device keeps its Ed25519 key; the account binding lives on the Jarvis side. A leaked code is worth nothing after pairing.
- The dangerous direction: someone else claims the boss' pending device. Guards: only logged-in accounts, 6 digits + 10 min TTL + global 5-wrong limiter + re-roll on limiter hit, pending cap. Expected guess chance per window below 5 / 10^6 per pending device.
- The wrong direction (an attacker's device appears in the boss' list) needs the boss to type a code he did not read from his own screen. The `confirm:false` step shows IP and machine name so he sees what he pairs.
- Device rights stay on the device: `/etc/jarvis/permissions.conf` (source `assets/jarvis/rechte.conf`) is read before every job, default is no. Pairing grants reachability, not rights.
- Local confirm on the device becomes a switch in `permissions.conf`: `pairing = web` (default: the code seen on the screen and typed in the web is the proof of presence) or `pairing = device` (old behaviour, `jarvisctl pair <code>` required, for unattended or shared machines). Do not drop the old mode.
- The admin key stays in a root-only file, never in a response, never logged. `GET /bridge/pending` never returns codes.
- Unpair: web button -> `/api/bridge/forget` -> bridge `forget` -> device must show a new code. Device shows "Not paired" within one poll.
- Do not use the image key (`hp-device.key`) in parallel in QEMU: same id as the real device (see KNOWLEDGE).
- Admin borrowing of other users' devices (`adminBorrows`) works on the registry key, so OrientOS devices bound to a uid are borrowable like Windows ones. Not part of this change.

## Device side

- `kernel/app/jarvisd.fi`: on `pairing-needed`: write `/var/jarvis/pairing` (digits), then if `pairing = web` do not wait for `/var/jarvis/pairing-ok`; sleep 3 s and send `ich` again until `challenge` or the 10 min TTL ends. `pairing = device` keeps today's wait.
- New file `/var/jarvis/state` (written by `jarvisd`, world readable, no secrets): lines `pairing: waiting <digits> <seconds left>` / `pairing: ok` / `pairing: none`. Nothing like it exists today: `/var/jarvis/pairing` holds only the digits, and neither the tray nor `jarvismini` knows anything about the helper.
- Display (all new readers of `/var/jarvis/state`, no new IPC): `jarvisctl status` prints the code in big block digits plus "Enter it at <host> > Devices" (host from `servername` in `/etc/jarvis/permissions.conf`); the tray gets a "Pairing" row with the digits while pending (`kernel/user/traypop.fi` and the tray model, `tools/tray`); `kernel/user/jarvismini.fi` shows the digits full screen when pairing is pending.
- Later: let the bridge answer `welcome` with the account name so the tray can say "Paired with <name>".
- `jarvisctl pair <code>` stays (mode `device`), accepts digits and hex.

## Migration of the HP

1. Now (no code): add `{"id":"osum-07278ff1aafb","name":"HP"}` to `data/bruecke_devices.json` and restart Jarvis once (not done in this task: no restart allowed). Remove or keep `osum-13c1e04076bf` (image key; keep only if the image key is used again).
2. After stage 1: edit `data/bridge_devices.json`, no restart (mtime reload).
3. After stage 3: the HP can be unpaired and paired again by code as the end-to-end test; the old entry is removed by `forget`.

## Staging plan

Each stage is mergeable alone and does not break the old flow.

### Stage 1: Jarvis device set (small, safe, no bridge change)

- `lib/osumBridgeDevices.js`: `addDevice/removeDevice/reload`, file `data/bridge_devices.json` with fallback to `data/bruecke_devices.json`, mtime check in `poll()`, uid required for new entries.
- `lib/bridgeDeviceStore.js` (new, small): load/save/migrate the JSON file, unique names per account.
- `test/osumBridgeDevices.test.mjs`: add tests for add/remove/reload/migration/uid scoping.
- `server.js`: use the new store path only (2 lines).
- Gate: `node --test test/osumBridgeDevices.test.mjs`.

### Stage 2: bridge service (after the English rename merged)

- `tools/bruecke-server/bruecke_server.py` (deployed copy `/root/bruecke/bruecke_server.py`): `/bridge/pending`, `/bridge/pair`, `/bridge/forget`, code TTL, pending cap, wrong-code limiter. Split into a new module `pairing.py` (code store, limiter) instead of growing the 1600-line file.
- `tools/bruecke-server/test_pairing.py` (new): pair ok, wrong code, expiry, cap, limiter lockout + re-roll, peek does not pair, no codes in `/pending`.
- Keep `POST /bruecke/koppeln` working for one release (old devices, image pre-pairing).
- Gate: `python3 tools/bruecke-server/test_pairing.py` and the existing `test_warum.py`.

### Stage 3: Jarvis API, chat tool, UI

- `lib/bridgePairing.js` (new): `pairByCode`, `forget`, `listFor`, limiter keys.
- `server.js`: mount `/api/bridge/*` (about 10 lines).
- `lib/tools.js` + `lib/systemPrompt.js`: tool `pair_device`.
- `public/index.html`, `public/app.js`, `public/i18n.js`: devices page block "Pair OrientOS device" (code input, found-device confirm, list with unpair).
- Tests: `test/bridgePairing.test.mjs` with a fake bridge HTTP server.

### Stage 4: device

- `kernel/app/jarvisd.fi` (pairing mode, 3 s re-ask, status lines), `kernel/user/jarvisctl.fi` (big digits), `kernel/user/traypop.fi` + tray model (Pairing row), `kernel/user/jarvismini.fi` (full screen code), `assets/jarvis/rechte.conf`, `rechte-justin.conf`, `rechte-hp.conf` (`pairing = web`).
- `tools/bridge/peer.py`, `tools/bridge/run.sh`: new section "pairing by web" with the Python peer playing the bridge: no local confirm needed, re-ask works, expiry works, `pairing = device` still demands the confirm (counter-test).
- Gates: `heavy bash tools/bridge/run.sh`, `tools/classes/run.sh`.

### Stage 5: cleanup

- Remove `lib/osumbridge.js` + the `/api/osum/*` routes + `data/osum-cert.pem` use once nobody needs the 8443 listener (needs a boss decision: it is the only direct TLS path).
- Update `docs/BRIDGE.md` and `docs/BRUECKE.md` (pairing chapters) to point here.

## Open questions

- Admin only, or every account? Today the pinned devices belong to admins; the code path is generic, the check is one line in `lib/bridgePairing.js`.
- Name of the public host shown on the device ("Enter it at ..."): take it from `servername` in `permissions.conf`.
