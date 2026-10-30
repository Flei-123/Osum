# tools/odbc -- odbc, the host client of the OrientOS debug bridge

Python 3, stdlib only (server, Windows laptop, anywhere). Protocol: `docs/ODB.md`. Agent: `odbd` (inside the OS, W-O1).

```
python3 tools/odbc/odbc.py --port <spec> [--token-file F] <command>
```
Port specs (`--port` or `$ODB_PORT`): `unix:/path/sock` (qemu chardev), `tcp:host:port`, `pipe:\\.\pipe\name` (VirtualBox uart2 server pipe),
`tty:/dev/pts/N`, `com:COM3`. Token: `--token`, `--token-file`, `$ODB_TOKEN`, `$ODB_TOKEN_FILE` (HMAC-SHA256 auth, the token is never sent).

| command | what |
|---|---|
| `devices` | probe `$ODB_PORT` list (`;`), /tmp/odb*.sock, /root/abbilder/*/odb.sock, Windows pipes `odb*`: online/offline + rtt |
| `info [--idle-ms N]` | os, uptime, cpus, mem, `idle_pct`, `idle_core`, screen |
| `exec [--argv] [--cwd d] [--stdin f\|-] cmd...` | stdout/stderr passthrough, exit code = remote exit |
| `shell [cmd...]` | interactive pty shell (Ctrl-] leaves); with args = exec |
| `push <local> <remote>` / `pull <remote> <local>` | go-back-N file transfer, sha256 + crc32 verified, prints KiB/s and rewinds |
| `shot [out.png] [--format png\|ppm\|raw]` | framebuffer screenshot |
| `input text\|key\|mouse\|scroll ...` | `input text hello`, `input key Enter --mods ctrl+shift`, `input mouse 100 200 --button left --action click` |
| `ps`, `kill <pid> [--sig]`, `logs [-n N] [-f] [--src kernel\|app\|all]` | |
| `crash [list\|get <id> [out]\|clear <id>]` | crash dumps |
| `reboot [--off] [--force]`, `ping -c N`, `wait [sec]` | `wait` = until the agent answers (boot done) |

Exit codes: remote exit status for exec; 4 agent error (ERR code on stderr); 5 transport/timeout; 3 integrity.

## Layout
`odb/frame.py` codec + resync decoder, `odb/proto.py` TLV/stream/ACK payloads, `odb/client.py` Session (hello+auth, RETRY, CANCEL,
go-back-N push/pull), `odb/transport.py` adapters (reader thread per transport; Windows pipes/COM are polled because a blocked
synchronous ReadFile would block writes), `odb/mock.py` Python mock agent (faults: noise, corrupt, drop, slow UART), `odb/cli.py`,
`bench.py` (latency/throughput numbers), `qemu.sh` (server runner), `run.sh` (gate: all unit tests).

## Tests
`bash tools/odbc/run.sh` (gate `odbc`, quick tier, host only, ~7 s): `python3 -I -m unittest discover -s tools/odbc -p 'test_*.py'`.

## Runners
- qemu (server): `tools/odbc/qemu.sh start <img> <dir>` -> `<dir>/odb.sock` (COM1 log in `<dir>/com1.log`), `odbc --port unix:<dir>/odb.sock ...`, `qemu.sh stop <dir>`.
- VirtualBox (laptop): `vbtest.ps1 mkvm` adds uart2 as a server pipe `\\.\pipe\odb-test` (disable: `VBL_ODB=0`). One-time:
  `bash tools/vbox/run.sh odbc-pack` + `odb-token`, paste the printed `odbinstall` / `odbtoken` lines on the laptop.
  Then `vbtest.ps1 odbwait 90` (marks the agent up; `shot` then uses odb, VBoxManage stays the fallback), `odb info`, `odb exec ...`,
  `odb push/pull`, `odbidle 3000` (guest idle_pct), `odbbench --mib 1`.

## Kernel ODB over LAN (no userland needed)

Boot word `kodb` (or `odb=1`) makes the kernel network task answer ODB on UDP port 6970 (`kodbport=N` changes it). One datagram = one frame. Only hosts in the same subnet are served; `nokodb` turns it off. The token is `/etc/odb.token` (without it only hello/ping work).

    odbc --net 192.168.1.50 --token-file token.txt ping
    odbc --net 192.168.1.50 --token-file token.txt info
    odbc --net 192.168.1.50 --token-file token.txt ps --full
    odbc --net 192.168.1.50 --token-file token.txt stacks [pid]
    odbc --net 192.168.1.50 --token-file token.txt logs -n 100 [-f]
    odbc --net 192.168.1.50 --token-file token.txt ls /var/log
    odbc --net 192.168.1.50 --token-file token.txt cat /var/log/<file>

`ls`/`cat` answer `EBUSY` while the filesystem lock is held. Gate: `tools/kodb/run.sh`.
