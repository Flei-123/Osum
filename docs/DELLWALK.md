# DELLWALK — testing on the REAL Dell (smoke + walk), VM only as a pre-check

Stand 11.10.2026. Everything here is what exists in `tools/qa/dell_walk.{sh,py}` — measured values are marked.
Not measured = "not measured".

## 1. How the server talks to the Dell (read from the code, not guessed)

`tools/qa/dell_walk.py` class `Bruecke` calls the local bridge server (`bruecke_server.py`, `127.0.0.1:8090`):

| Call | Meaning |
|---|---|
| `GET /bruecke/geraete` | is the device registered and `verbunden` (header `X-Bruecke-Verwalter: <key>`, key = `/srv/bruecke/verwalter.key`, root only) |
| `POST /bruecke/auftrag` `{geraet, art, ziel, wert}` | queue a job: `art` = `command` / `photo` / `input` / `read` / `write` / `list` |
| `GET /bruecke/holen?geraet=&id=` | answer (404 = not yet) |

So the script needs NO MCP tools. It only runs on the JARVIS server (key file). The device never talks to the script,
it polls the bridge itself (`jarvisd`). Permission list on the Dell: `/etc/jarvis/permissions.conf` (commands, screenshot, input).

## 2. Two modes (plus the VM mode)

    bash tools/qa/dell_walk.sh smoke [outdir] [--device ID]   # READ-ONLY, ~1 min, safe at any time
    bash tools/qa/dell_walk.sh echt  [outdir] [--apps a,b]    # sends INPUT (clicks/keys): only at the desktop
    /root/jarvis/bin/heavy bash tools/qa/dell_walk.sh vm ...  # QEMU pre-check (old behaviour)

Default outdir for `smoke`/`echt`: `/root/dellwalk-logs/<YYYYMMDD-HHMMSS>/` with `protokoll.md` (+ `.json` for `echt`) and
`fotos/*.png`. Exit code 0 = everything OK, 1 = at least one FAIL, 3 = aborted (device offline, screen locked, no photo).

### smoke — read-only (no input, no write, no reboot)

One line per check, `OK|FAIL <name>: <why>`:

| Check | Command on the Dell | OK when |
|---|---|---|
| uname | `/bin/uname -a` | answer `ende 0` |
| /system/FASSUNG | `/bin/cat /system/FASSUNG` | answer `ende 0` (the value is printed; compare with the feed by hand) |
| df | `/bin/df` | free space of the root ≥ 20 MiB (FAIL = still the 50 MiB stick RAM image: OTA has no room) |
| session | `/bin/ps` | info only: `lock`/`login`/`glogin` in the list = locked |
| daemons | `/bin/ps` | `jarvisd taskbar starter desktop` all present |
| klog panic / fault / refused / failed | `/bin/grep <word> /proc/klog` | no line left after `crash_lines` (the same ignore list as the VM walk) |
| photo | `/bin/jarvisctl screenshot` then job `photo` | PNG with > 50 distinct colours |

Measured 11.10.2026 on the Dell (stick system, lock screen): **9 OK / 1 FAIL in 66 s**, the FAIL was `df`
(root 50 MiB, free 5.4 MiB) — correct, that is the OTA blocker (r542). The first bridge job of a run took up to ~39 s.

### echt — walk through the apps (sends input)

Per app: photo before → start menu (click bottom left) → type the name + Return → photo → `ps` diff (an app is a NEW PID,
its name is `-`) → `/bin/log -l warn` → maximise / restore / drag / close with the buttons found IN THE PHOTO →
kill leftovers → photo. Result `OK` / `FEHLER` per app and per window step (see `docs/QA-DELL-DURCHKLICK.md`).
Guards: aborts at once if the Dell is offline, if the screen is LOCKED (`lock`/`login` in `ps`, new 11.10.), if no photo
is possible, or after 4 failed apps in a row. **Not-Aus: Win+Esc** on the Dell, or `jarvisctl input off`.
Status: the `echt` loop has never run through on the Dell (r526/r547); `--dry` is tested, `smoke` is tested on the Dell.

## 3. Manual protocol for an agent with the MCP tools (when the script is not wanted)

Same checks, by hand. Always full paths, no pipes, no `sleep` over ~55 s in the shell tool.

1. `remote_shell(Dell, "/bin/uname -a")`, `"/bin/cat /system/FASSUNG"`, `"/bin/df"`, `"/bin/ps"`.
2. `remote_shell(Dell, "/bin/grep panic /proc/klog")` and the same for `fault`, `refused`, `failed` (`/bin/grep` takes the
   pattern as 1st argument, no options). Expected: no output (or only lines already explained in the roadmap).
3. Photo: `remote_shell(Dell, "/bin/jarvisctl screenshot")` BEFORE EVERY photo (the permit lasts one photo / 60 s), then
   `computer(action: screenshot, device: Dell)`.
4. Judge: lock screen in `ps` → no input. Desktop → one app: start via start menu, photo, `ps` (new PID), `/bin/log -l warn -n 40`.
5. Pass criteria: no new klog line with the 4 words, the new PID exists, the screen changed, the window can be closed.

## 4. Not covered (honest)

- Pixel correctness of rounded corners, shadows, text: the walk only says "the screen changed / the window box moved".
  The gate tools (`tools/aacorner`, `tools/drag`, `tools/midline`) have never run against the Dell.
- Keyboard layout / AltGr, sound, standby: manual (`docs/QA-DELL-DURCHKLICK.md`).
- Whole `echt` run: no measured duration yet (VM: ~3 min per app, real "4 apps in 40 min" under load, r535).
