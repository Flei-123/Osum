# QA-DELL-DURCHKLICK -- every app, one photo per step, one protocol

Tool: `tools/qa/dell_walk.sh` (+ `tools/qa/dell_walk.py`). Two modes, one app table.

| mode | machine | how it clicks | evidence |
|---|---|---|---|
| `vm` | QEMU/KVM, stick machine (`tools/design/eh6.sh`), 3440x1440 | QEMU monitor through `tools/design/drive.py` (rectangles the programs report on the serial line) | serial log cut per step, screenshots compared pixel by pixel |
| `echt` | the real Dell (`osum-a4206b26eb96`) | bridge jobs `input` (scan codes, mouse) on the local bridge server | PNG photo job, `ps`, `log -l warn`, `/var/log/jarvisd.log` |

The VM run finds what is reproducible. The real run finds the rest. The protocol keeps the two apart:
scope `VM` = fix it in the repo and re-run in the VM; `DELL` = only seen on the machine; the section
"Only on the real Dell" lists what a VM can never say OK to (keyboard, I219 net, EDID, GPU, sound, USB, power).

## The app list

Derived from `assets/apps/*.osp` (what the start menu shows) plus the three taskbar fields.
`bash tools/qa/dell_walk.sh list` prints it.

Started: Settings, File Explorer, Terminal (twice), Editor (`edit`), Editor+ (`nedit`), Task Manager,
PDF-Betrachter, Programme (Store), Papierkorb, Widgets, Certus; taskbar: network field (control
centre), clock, notification bell. **Not started on purpose:** the installer (it partitions disks) and
the launcher (it is the menu itself).

Per app: photo before -> start menu open -> search text typed -> Return -> window open (photo) -> app
specific action (type, Ctrl+N dialog, Tab, wait 5-8 s) -> maximise (photo) -> restore -> drag the title
bar (photo) -> close button (photo). A step that changes nothing on the screen counts as not done.

## VM mode (what JARVIS runs on the server)

```
/root/jarvis/bin/heavy bash tools/qa/dell_walk.sh vm /tmp/dwalk        # all apps, ~25 min
/root/jarvis/bin/heavy bash tools/qa/dell_walk.sh vm /tmp/dwalk --apps settings,taskmgr
python3 tools/qa/dell_walk.py eval /tmp/dwalk --runner /tmp/dwalk/run  # judge a run again
```

Result: `/tmp/dwalk/protokoll.md|json`, `/tmp/dwalk/fotos/*.png`, the serial log in `/tmp/dwalk/run/serial.txt`.
Exit code 0 = every app OK. Remove the directory afterwards (`rm -rf /tmp/dwalk /tmp/dwalk-build`).

## Real Dell -- step by step (JARVIS / the control room)

1. **Is the device online?** `list_devices` (OrientOS device `osum-a4206b26eb96`), or
   `curl -H "X-Bruecke-Verwalter: $(cat /srv/bruecke/verwalter.key)" localhost:8090/bruecke/geraete`
   -> `"verbunden": true`. Offline: stop here. Do not queue jobs (they expire after 15 min and then run
   on a machine nobody watches).
2. **Permissions on the Dell** (`/etc/jarvis/permissions.conf`): `screenshot = yes`, `input = yes`
   (worker D1 sets it for Justin's Dell), `commands = yes` with `/bin/ps`, `/bin/log`, `/bin/kill` in the
   allow list. Without `input = yes` every job is refused with "`input = no`" -- then only photos work.
3. **Baseline photo + process list** (`photo`, `command /bin/ps`). Write down the pid list. The screen
   must show the desktop with the taskbar; if a lock screen or the login stands there, stop.
4. **Run:** `python3 tools/qa/dell_walk.py echt /tmp/dwalk-echt` (or `bash tools/qa/dell_walk.sh echt ...`).
   It re-checks step 1 itself and sends nothing when the device is offline. `--dry` prints the jobs only.
   Per app: photo -> click start (24, H-20) -> scan codes of the search word -> Return -> wait 10 s ->
   photo -> `ps` diff -> `log -l warn -n 40` -> kill the new process -> photo.
5. **Photo per step:** the PNGs land in `fotos/`. JARVIS looks at the `*-2-offen.png` of each failed app
   (`view_image`) before writing the verdict; the pixel diff only says "something changed".
6. **Protocol:** `protokoll.md` (OK/FEHLER per app, scope DELL). Copy findings into the roadmap; findings that
   reproduce with `vm --apps <id>` are fixed in the repo, the rest stay "only Dell".
7. **Manual extras the script cannot do** (ask Justin or do them with `computer`/photos): plug a USB stick,
   unplug the network cable and replug (I219 link), type with AltGr (`@`, `{`), play a sound, close the lid.

### Emergency stop (Not-Aus)

- Hard stop of the run: `Ctrl+C` on the script, or `kill` the python process; queued jobs expire after 120 s
  (`ttl_s`) on their own.
- On the Dell: set `input = no` in `/etc/jarvis/permissions.conf` or press the "Bridge off" switch in
  Settings -> Bridge tab (it writes `input = no` and `screenshot = no`; the helper re-reads the list before
  every job). Last resort: the power button / unplug the network.
- Block the device at the server: `POST /bruecke/koppeln` with the lock action (`dieses Geraet ist gesperrt`).

### Abort conditions (the script stops by itself)

- device offline, or the first photo job fails (no `screenshot`), or `input = no`;
- 4 apps in a row FEHLER (the machine is probably hung or a dialog blocks the screen);
- a photo shows the lock screen / login / a black screen (check by eye at the first failure);
- JARVIS aborts manually when `log -l warn` shows a panic line, when the Dell stops answering `ps` for two jobs,
  or when Justin asks.

## What the protocol cannot judge

"OK" means: the launcher started the bundle, the screen changed, no crash line, the window closed. It does
not mean the app is correct inside. Look at the photos of Settings, Explorer and Terminal by eye.

## Findings

See the section "Findings of the first VM run" below (filled in by the run of 10.10.2026).
