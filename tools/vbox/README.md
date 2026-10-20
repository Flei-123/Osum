# tools/vbox -- OrientOS dev loop on the laptop's VirtualBox

Loop: code -> merge -> build image on the SERVER (heavy) -> image to the laptop (HTTP) -> VirtualBox VM `OrientOS-Test`
boots it -> worker drives it (screenshots, keys, mouse, idle, serial) -> result + screenshots back -> fix -> next round.
Server qemu stays for long parallel series (see docs/DEV-LOOP-VBOX.md).

Two halves:
- `run.sh` (server, bash): lock, build, publish image over HTTP, publish helper script, pull screenshots.
- `vbtest.ps1` (laptop, PowerShell 5.1): fetch, VM create/start/stop, keys, mouse, shots, serial, idle, cleanup.

## Rules (hard)
- Device `HOLO-LAPTOP-3`, `shell: powershell`. NEVER the Dell.
- NEVER touch the boss VM `OrientOS` ({0ee259f6-4232-4c00-b855-ae407ee6bb2d}). `vbtest.ps1` only knows `OrientOS-Test` and refuses the boss UUID.
- ONE test VM at a time. Take the lock first: `bash tools/vbox/run.sh lock <your-name>` (exit 2 = someone else has it, wait). Release at the end.
- Clean up after every run: `vbtest.ps1 cleanup` (VM, disk, stage, serial, shots) + `run.sh unpublish <hex>` + `run.sh unlock`. Boss VM window may be open or closed, it does not matter.
- Laptop must be on, unlocked, online, helper running. If it goes offline mid-run: stop, report what is left (VM may still run -> `cleanup` next time).
- Use `remote_shell` with long sleeps carefully: one call should stay under ~60 s of waiting (the device times out otherwise). Split with `wait`.

## One-time install on the laptop (idempotent, also updates the script)
Server: `bash tools/vbox/run.sh script` prints the line. Run it on the laptop:
```
New-Item -ItemType Directory -Force C:\Users\justi\vbl | Out-Null; curl.exe -sS -f -o C:\Users\justi\vbl\vbtest.ps1 https://jarvis.fleitec.com/t-vbl/vbtest.ps1
```
(remote_write also works for this small file; never for the image.) Everything lives under `C:\Users\justi\vbl\` (stage\, shots\, serial.txt).

## The round
Server (use `(nohup setsid ... &)` + poll; the build takes ~11 min plus heavy queue time; `run_shell` aborts after ~60 s):
```
bash tools/vbox/run.sh lock w-xyz
bash tools/vbox/run.sh stamp round-start
bash tools/vbox/run.sh build z30 /path/to/worktree          # -> /root/abbilder/z30/orientos-usb.img (via heavy)
bash tools/vbox/run.sh publish z30                           # xz + public/t-<hex>/o.xz; prints the LAPTOP fetch line
```
Laptop (`$s` = `powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\justi\vbl\vbtest.ps1`; paste the fetch line from `publish`):
```
$s fetch <url> <sha-xz> <sha-raw>     # curl.exe + sha256 + python lzma -> stage\o.img   (~8 s for 23 MB)
$s mkvm                               # creates OrientOS-Test (replaces an old one), convertfromraw -> os.vdi  (~2 s)
$s start                              # GUI window (default); 'start headless' for no window
$s serial wait . 40                   # only if serial is on and the kernel writes COM1 (see Traps)
$s wait 25; $s shot boot; $s shotstat boot     # login screen visible and not black
$s login                              # types 'startkennwort' + Enter (German layout)
$s wait 12; $s shot desk; $s shotstat desk
$s hint 1920 1080; $s wait 8; $s shot r1920    # live resize; try 1280x720, 2400x1350
$s idle 30 3                          # host CPU of the VM process, 3 samples, target < 30 %
$s keys 'combo:ctrl+shift+t;sleep:1500;type:ls;key:enter;sleep:800;shot:tab'
$s mouse 'goto:960:1060,left,sleep:600,shot:menu'
$s cleanup keepshots                  # VM + disk + stage + serial gone, shots stay until delivered
```
Get screenshots back: `remote_deliver(device, paths:["C:\Users\justi\vbl\shots\desk.png", ...])`, then on the server
`bash tools/vbox/run.sh pull <reports/...-shots dir> desk.png ...` (delivered files land in /root/jarvis/downloads/<uid>/<id>/<name>), then `view_image` the file.
Finish: `$s cleanup`, `bash tools/vbox/run.sh unpublish <hex>`, `bash tools/vbox/run.sh unlock`, `bash tools/vbox/run.sh clean <id>` (image dir is rebuildable).

Swapping only the disk of an existing test VM: `$s fetch ...; $s swapdisk; $s start` (keeps VM settings, ~3 s faster than mkvm).

## vbtest.ps1 commands
`fetch <url> <sha-xz> [sha-raw]` | `mkvm` | `swapdisk` | `start [headless]` | `stop` | `cleanup [keepshots]` | `status`
`shot <name>` | `shotstat <name>` | `shotdiff <a> <b>` | `startgate` | `hint <w> <h>` | `wait <sec>` | `idle <sec> [samples]` | `login [pw]`
`keys "<tokens;>"`: `type:text` (letters, digits, space . , - / _ : ; = "), `key:enter|esc|tab|bs|space|up|down|left|right|del|home|end|f1..f12`,
`combo:ctrl+shift+t` (also `win+v`, `alt+tab`; modifiers ctrl shift alt win altgr), `k:1D 2A ..` (raw set-1 hex scancodes), `sleep:ms`, `shot:name`.
`mouse "<tokens,>"`: `goto:x:y` (absolute from top-left, PS/2 relative with reset), `rel:dx:dy`, `left`, `dbl`, `right`, `mid`, `ldown`/`lup` (drag), `wheel:n`, `sleep:ms`, `shot:name`.
`serial tail [n]` | `grep <re>` | `count <re>` | `wait <re> <timeout>` | `size`.
Env: `VBL_MEM` (MB, max 4096, default 3072), `VBL_CPUS` (3), `VBL_SERIAL=0` (no uart file), `VBL_LAYOUT=de|us` (guest layout for `type:`, default de: y/z swapped).
Output lines start with `OK:` / `FAIL:` / `INFO:`; exit code 1 on FAIL.

## Input gate
`$s startgate` (after `login` + ~18 s, fresh desktop, any size): Win key opens the start menu, a mouse click on the 'Editor' tile opens an app, typing reaches it. Prints `OK:`/`FAIL:` per check and `startgate 3/3` or `FAIL: ... of 3`, exit 1 on FAIL. Needs a LIVE guest: the known VBox hang (guest frozen, host core 99 %, see reports w-r7/w-r8) makes checks 2/3 FAIL -- check `idle` before judging.

## Automatic checks (grep the output)
- Login screen / desktop visible: `shotstat` prints `OK: ... not black` (non-black pixel share > 5 %).
- Taskbar right populated: `shotstat` line `taskbar_strip ... diff_right=NN %` (share of non-background pixels in the right third of the last 56 px; ~0 % = empty/stale bar, e.g. bar not following a resize).
- Idle: `idle` prints `OK: idle min .. % (target < 30)` or `FAIL`.
- Tabs / Win+V / glass / tray / battery: visual via screenshots (view_image).

## Traps
- PowerShell is case-insensitive: `$serial` and `$SERIAL` are the same variable (this bit the first version).
- PS 5.1 strips double quotes inside arguments of native commands (python -c ...): use single quotes inside.
- `remote_shell` waits at most about a minute per call; split long sleeps. The helper may drop (laptop sleep): check `list_devices` before blaming the OS.
- VirtualBoxVM.exe command lines are not readable for the helper; the VM pid comes from COM (`IMachine.SessionPID`), `idle` uses that. Several VirtualBoxVM.exe processes exist (boss VM, leftovers) -- do not measure by name.
- Serial: `uart1 -> file` only produces bytes if the kernel writes COM1 under VirtualBox; with the file uart attached the idle number may be a little higher. Use `VBL_SERIAL=0` for the idle number if in doubt.
- Password at the login screen: `startkennwort` (personal image, user `justi` shown as "justin"). The tray shows layout DEU/DE, so `type:` uses German scancodes (y and z swapped).
- Screen size: first boot is 1024x768; `hint` changes it. The taskbar follows after a few seconds (W-C3g); measure after `wait 8`.
- Test VM connects to the server as device "OrientOS-VM" (jarvisd in the image). Never use that device for commands.
- Boss VM scale factor is 1.75 (boss decision: set to 1, not done by us); the test VM gets ScaleFactor 1.

## r1268: guest "freezes", host 99-105 % CPU (analysis 19.10.2026, laptop = Surface Laptop 4, VBox 7.2.20)
- Host runs VirtualBox on Hyper-V (VBS on, `HM: VT-x is not available -> NEM`). All VMs use the WHv/NEM backend.
- Boss VM in burn state: ONE EMT thread (EMT-2) at 99.7 % host CPU, the other two vCPUs idle in `idt.halt`. `debugvm statistics`: `/TM/CPU/02/cNsOther` = 3203 s of 3477 s (neither executing nor halted), `/TM/VirtualSync/GivenUp` = 3196 s = the guest clock lagged by 53 min; the burn ended the moment VBox logged `TM: Giving up catch-up attempt at a 3 118 354 249 999 ns lag`. NEM exit counters are tiny (PortIo 30k, MemUnmapped 20k) -> not exit-bound, no guest spin (guest rips seen on the burning vCPU were syscall paths, registers moved).
- Test VMs: 3 vCPUs burned in the first minute (2 of 2, EMT-1/EMT-2 at ~90 %, TM counters of vCPU0 frozen); 1 vCPU VM did not (n=1, host ~25 % during boot). 2 vCPUs: see report.
- Workaround: `VBL_CPUS=1` (or `VBoxManage modifyvm <vm> --cpus 1`, VM powered off). Real fix candidates: native VT-x (Windows Hypervisor Platform off: `bcdedit /set hypervisorlaunchtype off` + disable Core Isolation, needs admin + reboot, Boss decision), newer VBox, or find what the guest does on APs that makes NEM spin.
- Tools: `VBL_VM=<name>` runs vbtest against an extra test VM (never the boss VM), `VBL_EXTRA='--hpet on ...'` extra `modifyvm` args at mkvm, `VBL_XDATA='key=val;key=val'` extradata, `diag/mx.ps1` repeated-boot runner (use host CPU per pid; the TM counters freeze in the burn state). Keep `VBL_MEM=1536` when running 3 VMs in parallel (16 GB laptop, VERR_NO_PAGE_MEMORY otherwise).
- Reading a burning VM: thread names via GetThreadDescription (EMT-n), `debugvm <vm> statistics --pattern '/TM/CPU/*|/TM/VirtualSync/*'`; `debugvm getregisters` may unstick it (do not use it when you want to keep the burn).

## Boss VM on 1 vCPU (r1268 workaround A, 20.10.2026)
`diag/bossvm.ps1 [-Cpus 1] [-Boots 4] [-Minutes 30] [-Sec 15] [-NoModify] [-Gui]` touches ONLY the boss VM `OrientOS` (the one deliberate exception to the rule above, boss decision):
config dump to `C:\Users\justi\vbl\bossvm-before-*.txt`, clean ACPI shutdown, `modifyvm --cpus 1`, N short boots + one long run (login by scancodes, ctrl+shift+t),
per sample host CPU of the VM process + per-vCPU Other share + TM lag. BURN = other>=50 % / lag>200 ms/s / host>90 %. Log `C:\Users\justi\vbl\bossvm.log`.
Start in the background: `Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine='powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\justi\vbl\bossvm.ps1'}`.
Fallback B (if 1 vCPU is not acceptable): switch the Windows Hyper-V feature off (hypervisorlaunchtype off) so VirtualBox uses VT-x directly.
