# STATUS FVVIEWER-PAKET (M4 preparation, 13.10.2026)

Goal: ship the OrientOS FreeViewer viewer (`fvviewer`, plan `docs/ORIENTOS-VIEWER.md` in the FreeViewer repo)
as a signed store package with auto-update. Measured against `origin/main` 04b7232f.

## 1. IST (what exists in origin/main)

| Part | Where | State |
|---|---|---|
| Package format `.opk` | `kernel/user/opk.fi` (on device: `/bin/opk`), host tool `pkg/opk.py` | exists. **`pkg/opk.py` is NOT in this repo**: it lives in the OrientOS repo (`projects/.../orientos`), found via `tools/lib/opkpfad.py` (git show + cache). |
| Recipe pattern | `pakete/<name>/rezept` + `pakete/bauen.sh` (wmplug-*, notes) | exists; `bauen.sh` had a stale default `OPK=/root/orientos-install/...` (folder removed) -> fixed here |
| Bundle packages (start + INFO + symbol) | `tools/loader/pakete.sh` + `apps.tab` (14 apps) | exists; this is the model for an app with window/icon |
| Manifest v2 / SDK | `tools/sdk/osdk.py`, `docs/SDK.md`, `tools/sdk/run.sh` | exists (host lint/build). Modules `ulib actwire rpc` from `kernel/user/`. |
| `rpc.fi` | `kernel/user/rpc.fi` (588 lines) | **exists. `lib/rpc.fi` does not** -- ACCEL.md D-01 meant the lib path, the KB meant kernel/user. Both statements are half true. |
| Permissions | `osdk.py perms` | only `net` is ENFORCED (netview, `net=` in INFO). `notify clipboard.* fs.home audio.play` and `min_os` are declared only (S-010). |
| Store UI | `kernel/user/store.fi` (window), `bstore.fi`, `stored.fi` (root daemon), `etc/store.conf`, `docs/STORE-OBERFLAECHE.md` | exists; lists the VERIFIED catalogue (`opk katalog`: INDEX + INDEX.sig), install/update/remove through the action bus. Default: only admin installs. Never run against the live store (docs says so). |
| OTA | `kernel/user/ota.fi`, `docs/OTA.md`, `docs/OTA-FEED.md`, `tools/ota/*` | exists: channels `kanal=stable|test` (not published live), `ota service` (auto), `ota boot` (confirm), rollback, A/B counter in kernel. |
| Signature | `lib/crypto/ed25519.fi`, `sha512.fi`; `opk.fi` section "DIE SIGNATUR"; `kernel/user/jsig.fi` | **every install is signed (Ed25519)**; trusted key = ONE file `/system/schluessel.pub`; VERZEICHNIS and INDEX signed, per-package `.opk.sig`, anti-rollback via `register.json`. (`lib/jsig.fi` does not exist; the file is `kernel/user/jsig.fi`.) |
| Live feed | `https://store.fleitec.com/osum/aktuell` (`/srv/store/osum`), publisher `tools/ota/veroeffentlichen.py`, bundle `/root/.secrets/osum-ota-bund.json` | exists; carries the 14 apps of `apps.tab`. Publishing needs the owner's yes (`docs/OTA-FEED.md`). |
| Viewer prerequisites | `lib/fv/{crypto,proto,session}.fi`, `lib/net/ws.fi`, DNS+TLS 1.3 from the VM to freeviewer.fleitec.com | W1-W3: crypto + ws done; `cryptoif.fi` mock until swapped. |
| `kernel/user/fvviewer.fi` | -- | **missing** (W3b is building it). |

## 2. DONE in this branch (`w4-fvpaket`)

* `pakete/fvviewer/{rezept,INFO,symbol.txt}`: bundle recipe `fvviewer` 1.0.0, title FreeViewer, INFO manifest v2
  (`id=com.fleitec.fvviewer`, `perm=net`, `net=real`, `osdk.py check --strict` = ok, 0 warnings), 16x16 monitor symbol (OSYM builds, 1036 octets).
* `pakete/bauen.sh`: new `app()` step (ELF + osdk lint + symbol), fvviewer in the package list, OPK default via `opkpfad.py`.
  Without `fvviewer.fi` the step says so and skips the package -- no placeholder ELF.
* `tools/ota/fvstand.sh <stand-dir>`: builds the package and drops `fvviewer-1.opk` into a stand dir for `veroeffentlichen.py`.
* Measured: recipe + dummy `start` file -> `opk.py bauen` OK, `zeigen` lists `INFO`, `start`, `symbol` (the three files `opk` turns into `/apps/fvviewer.osp`).
  `bash pakete/bauen.sh` still builds the 4 existing packages.

## 3. GAPS

1. `kernel/user/fvviewer.fi` missing -> no ELF, so no real `.opk` yet (not built end to end).
2. No device test: install via `opk installieren` / store window, app appears in launcher with icon, `net=real` lets it reach the relay -- not run.
3. Only ONE trusted key and one `quelle` in `/etc/ota.conf`: FreeViewer updates can only ride the main OS feed (see 4). Key rotation/revocation list: missing (OTA.md "Was noch fehlt" 4).
4. `fassung` is a plain counter: the feed `fassung` (whole OS stand) and the package `fassung` are different numbers; `ota` replaces by hash.
5. Live feed has no `stable/`/`test/`; publishing is a live change (needs Boss yes).
6. Declared-only permissions: if the viewer uses clipboard/audio they are not enforced.
7. `ota apply` slow in QEMU (r179); AVX-512 `#UD` problem on bare metal (OTA.md item 1) -- the update path is dead on such CPUs until fixed.
8. Static linking: viewer is a static ELF (libc updates = rebuild all).

## 4. Auto-update plan (proposal only, nothing live touched)

**Recommended: same signed feed, same key.** The viewer is one more package in the existing feed -- no new trust, no new code.

1. Build: `bash tools/loader/build.sh S && bash tools/loader/pakete.sh S && bash tools/ota/fvstand.sh S/stand`.
2. Publish: `veroeffentlichen.py /tmp/ota-feed/osum --stand S/stand --bund /root/.secrets/osum-ota-bund.json --notiz "fvviewer 1.x"` (register counts the feed `fassung` up; old versions stay in `v/<n>/`).
3. Accept: `bash tools/ota/feedtest.sh <image> /tmp/ota-feed` (install, apply, confirm, rollback) plus store window shows FreeViewer.
4. Go live only with the owner's yes: `rsync` to `/srv/store/osum/` => `https://store.fleitec.com/osum/aktuell/` (INDEX, VERZEICHNIS, `pakete/<sha256>.opk(.sig)`).
5. Devices: `ota service` (auto=ja) fetches, verifies INDEX/VERZEICHNIS/package signature, installs as a new generation, `ota boot` confirms, rollback on failure. A bad viewer build is withdrawn with `--zuruecknehmen <n>`.

Alternative (not recommended now): a separate FreeViewer feed on `freeviewer.fleitec.com/os/` with its own register -- needs a second trusted key + second `quelle` in `ota`, i.e. the key-management work of OTA.md item 4 first. Also keep the Windows auto-update signature (FreeViewer roadmap r2) on the SAME Ed25519 scheme but its own key, never the OS key.

Signing key: stays `/root/.secrets/osum-ota-bund.json` (encrypted, passphrase file 0600). Do not copy it into the FreeViewer repo.

## 5. Steps and effort (estimate, not measured)

| # | Step | Effort |
|---|---|---|
| 1 | W3b delivers `kernel/user/fvviewer.fi`; `bauen.sh` builds the real `.opk` | follows W3b; 0.5 h for the build wiring |
| 2 | Install in a VM (`opk installieren`, store window, launcher icon, netview `real`) + gate script | 0.5-1 day |
| 3 | `apps.tab`/loader integration (optional: ship in the image) | 0.5 day |
| 4 | Local feed test with `feedtest.sh` incl. update 1.0.0 -> 1.0.1 and rollback | 0.5 day (QEMU ~25 min/run) |
| 5 | Publish to live feed (Boss yes) + check on a real device (FLEI-ONE only with Boss ok) | 0.5 day |
| 6 | Optional: second key / separate channel (key management) | 2-4 days |

Total to a first installable, auto-updating FreeViewer package after W3b: roughly 2-3 days; key management comes on top.


## 6. STATE 13.10.2026 (W7: real package, install, update, negatives)

Built and measured (nothing live touched):

* `bash pakete/bauen.sh <out>` builds `fvviewer-1.0.0.opk` (544226 octets, ELF 542184, symbol 1036) next to the other packages;
  `osdk check --strict` = ok, 0 warnings. `bauen.sh` now builds sources with the app profile
  (`firnc --profile=app -c`, no crt, no `USER_ENTRY`), like `tools/loader/build.sh` and the fvviewer gate.
* `bash tools/ota/fvtest.sh [out]` (run via `/root/jarvis/bin/heavy`, ~3 min): local test key + CA + feed server on the host, live image
  (QEMU, RAM root): `opk install` of the package (signature checked), `/apps/fvviewer.osp/start` starts (headless usage line),
  `ota apply` 1.0.0 -> 1.0.1 over the signed local feed (generation 0 -> 1), three negatives: wrong package signature
  (`SIGNATURE WRONG`), tampered package (`HASH MISMATCH`), VERZEICHNIS signed with a foreign key
  (`SIGNATURE OF THE VERZEICHNIS WRONG`); in each case nothing is installed.

NOT done / known:

* Disk install path: `install /dev/hda` fails on current origin/main ("install: FEHLER bei copy", ESP copy, reproducible on 96 and 256 MiB,
  also with a plain image without fvviewer) -- NOT caused by the package; test therefore uses the live (iso) mode. Needs an installer fix
  before `ota confirm` / reboot / rollback on an installed disk can be tested for fvviewer.
* Window (fUi) comes from W6; the package only starts the headless mode until then. Not run on real hardware (FLEI-ONE needs the owner's ok).
* Declared-only permissions (clipboard etc.) unchanged, see section 3.

## 7. LIVE PUBLICATION (needs the owner's yes -- DO NOT run without it)

1. `git pull` osum main (tests green), `bash tools/loader/build.sh S && bash tools/loader/pakete.sh S` (heavy).
2. `bash tools/ota/fvstand.sh S/stand` -> `fvviewer-1.opk` in the stand.
3. Publish into a COPY of the feed first: `python3 tools/ota/veroeffentlichen.py /tmp/ota-feed/osum --stand S/stand --bund /root/.secrets/osum-ota-bund.json --notiz "fvviewer 1.0.0"` (passphrase file, 0600).
4. Accept locally: `bash tools/ota/feedtest.sh <image-dir> /tmp/ota-feed` and `bash tools/ota/fvtest.sh` green; store window lists FreeViewer.
5. After the owner's ok: `rsync` the new `v/<n>/`, `aktuell/`, `pakete/`, `register.json` to `/srv/store/osum/` (=> `https://store.fleitec.com/osum/aktuell/`).
6. Check on one device (QEMU first; FLEI-ONE only with the owner's ok): `ota search` shows fvviewer, `ota apply`, `ota boot`/confirm.
7. Bad build: `veroeffentlichen.py ... --zuruecknehmen <n>`. Never copy the signing key into the FreeViewer repo.
