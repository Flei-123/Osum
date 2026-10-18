# ODB — OrientOS Debug Bridge (wire protocol v1)

Like `adbd`, for OrientOS: an agent (`odbd`, runs inside the OS) and a host
client (`odbc`, `tools/odbc/`, Python) talk a fixed framed protocol over an
interchangeable byte-stream transport. No USB gadget. Spec status: **v1,
stable** — after the first push only ADDITIVE changes (new commands, new
TLV keys, new frame types, new flag bits). Receivers MUST ignore unknown TLV
keys and unknown flag bits; unknown frame types are answered with
`ERR code=EUNSUP`.

All integers are **little endian**. Strings are UTF-8, no terminator.

## 1. Transports

A transport is a reliable-enough, ordered byte stream with possible garbage
bytes (resync handles it). The agent has a tiny dispatch layer
(`lib/odb/transport.fi`: `open/read/write/close` per transport id) so more
can be added without touching framing.

| id | transport | status |
|---|---|---|
| `serial` | second UART COM2 (I/O 0x2F8, IRQ 3, kernel name `ttyS1`) | v1 |
| `tcp` | listen on 127.0.0.1 / VM-NAT only, never public | later |

COM1 (`0x3F8`) stays the kernel console/log and is never used by ODB.
Serial parameters: 115200 8N1, FIFO on (QEMU/VBox ignore the baud rate).

Host side wiring:

- QEMU: `-serial file:$D/com1.log -chardev socket,id=odb,path=$D/odb.sock,server=on,wait=off -serial chardev:odb`
  (first `-serial` = COM1, second = COM2). Alternative: `-serial pty` (read the pty path from QEMU's stdout).
- VirtualBox: `VBoxManage modifyvm <vm> --uart2 0x2F8 3 --uartmode2 server <pipe>`
  (Linux/macOS: unix socket path; Windows: `\\.\pipe\odb`) or `--uartmode2 tcpserver 5555`.
  Keep `--uart1` for the console log.

## 2. Frame

```
offset size field
0      4    magic   'O' 'D' 'B' '1'  (4F 44 42 31)
4      1    ver     protocol version, 1
5      1    type    see 2.1
6      2    flags   see 2.2
8      4    id      request id (chosen by the host, never 0 for REQ; 0 for unsolicited)
12     4    len     payload length, 0..65536
16     len  payload
16+len 4    crc32   CRC-32/IEEE (zlib.crc32) over bytes 0 .. 16+len-1
```

Header = 16 bytes, trailer = 4 bytes, max frame = 65556 bytes.
CRC-32: poly 0xEDB88320 reflected, init 0xFFFFFFFF, final xor 0xFFFFFFFF;
check value `crc32("123456789") = 0xCBF43926`.

Test vector (PING id 0, payload `hi`):
`4f444231 01 06 0000 00000000 02000000 6869 2d574d30`
Test vector (REQ id 1, `hello ver=1 client=odbc`, 46 bytes):
`4f4442310101000001000000 1a000000 0568656c6c6f0376657201003106636c69656e7404006f646263 aa891c76`

### 2.1 Frame types

| type | name | direction | meaning |
|---|---|---|---|
| 1 | REQ | host→agent | start a command; payload = command TLV (2.3) |
| 2 | RESP | agent→host | successful FINAL answer of request `id`; payload = TLV (no command name) |
| 3 | DATA | both | stream data for request `id`; payload = `stream u8` + bytes (2.4) |
| 4 | END | both | end of one stream; payload = `stream u8` [+ TLV] |
| 5 | ERR | agent→host | FINAL failure of request `id`; payload = TLV `code`,`msg` |
| 6 | PING | both | liveness/latency; payload echoed in PONG |
| 7 | PONG | both | reply to PING (same id, same payload) |
| 8 | CANCEL | host→agent | abort running request `id` (agent ends it with `ERR code=ECANCEL` or its normal RESP) |
| 9 | ACK | both | file stream flow control (2.5); payload = `stream u8`, `next u64` |

Every request `id` ends with exactly ONE of RESP or ERR from the agent.
PING/PONG/CANCEL/ACK/DATA/END do not end a request.

### 2.2 Flags

| bit | name | use |
|---|---|---|
| 0 | RETRY | host re-sent this REQ (no reply arrived). Agent answers idempotently from a cache of its last RESP/ERR; it never executes the same `id` twice |
| 1 | LAST | on DATA: last chunk (an END for the stream still follows) — optional hint |
| 2..15 | — | reserved, send 0, ignore on receive |

### 2.3 TLV and command payload

```
REQ payload  = cmdlen u8 | cmd ASCII | tlv*
RESP/ERR/END payload (after stream byte) = tlv*
tlv          = klen u8 | key ASCII | vlen u16 | value bytes
```

Values are ASCII text unless stated: integers in decimal, hashes lower-case
hex, booleans `0`/`1`, paths UTF-8. A repeated key means a list (order
kept), e.g. several `arg=` for argv. Max TLV block = payload size.

### 2.4 Streams

`DATA payload = stream u8 | bytes`. Stream ids:

| id | name | direction |
|---|---|---|
| 0 | stdin | host→agent |
| 1 | stdout | agent→host |
| 2 | stderr | agent→host |
| 3 | file | both (push: host→agent, pull/crashdump: agent→host); payload = `3 | offset u64 | bytes` |
| 4 | shot | agent→host (image bytes) |
| 5 | log | agent→host (text) |
| 6.. | reserved | |

Chunk size: ≤ 32768 bytes of data per DATA frame (agent advertises `maxchunk`
in `hello`). Streams of one request are independent; each ends with its own
END (`END payload = stream u8 [+ tlv e.g. size=,sha256=]`).

### 2.5 File flow control (stream 3)

Go-back-N, so a lost/corrupt frame never needs a resync of the whole job.
The receiver sends `ACK(stream=3, next=<first byte offset it has NOT yet
received in order>)` after every `window/2` bytes, after END, and at once on
a gap or CRC error. The sender may be at most `window` bytes ahead of the
last ACK (`window` advertised in `hello`, default 65536); on an ACK lower
than what it sent it rewinds and continues from `next`. If no ACK arrives
within 2 s, resend from the last ACK. Final integrity: `sha256` (and
`crc32` of whole file) in the RESP.

## 3. Resync (garbage tolerance)

Receiver state machine on any byte stream:

1. Scan for `4F 44 42 31`. Bytes before it are discarded.
2. Read the remaining 12 header bytes. If `ver != 1` or `len > 65536`
   → treat as false match: drop ONE byte after the start of the candidate
   magic (not the whole candidate) and rescan.
3. Read `len + 4` bytes, check CRC. On mismatch → same as 2 (drop one byte,
   rescan inside the already buffered bytes, so a real frame hidden inside
   a corrupt one is still found).
4. Frame ok → deliver; continue after the frame.

Frames never carry the magic in escaped form; a payload that happens to
contain `ODB1` is harmless because step 3 validates the CRC. A receiver
with no complete frame for 5 s while a request is open may send PING.
Lost REQ/RESP: host resends the REQ (same `id`, RETRY flag) after
`timeout` (default 2 s, up to 5 times).

## 4. Session: HELLO and authentication

Nothing is sent by the agent on connect (the UART may carry boot noise).

1. Host: `REQ hello  ver=1 client=<name> clientver=<n>`
2. Agent: `RESP ver=1 agent=odbd agentver=<n> os=OrientOS kernel=<build> features=<csv> maxchunk=32768 window=65536 maxpayload=65536 auth=token nonce=<32 hex = 16 random bytes>`
   (version mismatch: `ERR code=EVER`, field `supported=1`).
3. Host: `REQ auth  mac=<hex>`, where `mac = HMAC-SHA256(key = token bytes, msg = "ODB1-auth" || nonce_raw)`
   (nonce_raw = the 16 decoded bytes). The token itself is never sent.
4. Agent: `RESP ok=1` or `ERR code=EAUTH`. Each failed attempt delays the
   next reply by 1 s doubling to a 30 s cap; the nonce changes on every
   `hello`.

Before successful `auth` the agent answers only `hello`, `auth`, `ping`;
everything else → `ERR code=EAUTH msg=not authenticated`.
Per-frame MAC/encryption is NOT part of v1 (host-local transports only);
reserved via a future flag + `features=mac`.

Token: read by the agent from `/etc/odb.token` (raw text, trailing
whitespace stripped, ≥ 16 chars). No token file → agent refuses every
`auth` (there is no default password). The image build / VM start writes
the file (`tools/odb/`), the host client reads the same value from its
`--token-file`.

### 4.1 Enabling (debug builds only)

- The agent is shipped only in images built with `ODB=1`
  (`tools/usbimg/build.sh`); default releases do not contain `odbd`.
- Even then it starts only if `/etc/odb.conf` has `enable=1` (or the kernel
  command line has the word `odb=1`).
- `/etc/odb.conf` keys: `enable=0|1`, `transport=serial`, `port=ttyS1`,
  `token_file=/etc/odb.token`, `allow=exec,push,pull,shot,input,ps,kill,logs,crashdump,power`
  (comma list; omitted commands → `ERR code=EACCES`).
- Nothing listens on the network in v1.

## 5. Commands (v1)

`features` lists what the agent really implements, e.g.
`info,exec,shell,push,pull,shot,input,ps,kill,logs,crashdump,power`.
Unimplemented → `ERR code=EUNSUP`.

| cmd | request keys | stream(s) | RESP keys |
|---|---|---|---|
| `hello` | `ver`, `client` | – | see 4 |
| `auth` | `mac` | – | `ok=1` |
| `ping` | – | (use PING frame; `ping` REQ also allowed) | `ok=1` |
| `info` | `idle_ms` (optional sample window, default 0 = since boot/last info) | – | `os`, `kernel`, `uptime_ms`, `cpus`, `mem_total_kb`, `mem_free_kb`, `idle_pct` (all cores, 0..100), `idle_core=<n>:<pct>` (repeated, one per core), `procs`, `screen=<w>x<h>`, `time_unix` |
| `exec` | `cmd` (shell string, run by `/bin/sh -c`) OR `arg` (repeated argv, no shell), `cwd`, `env` (`K=V`, repeated), `timeout_ms`, `stdin=1` (expect stream 0) | out 1, err 2, in 0 | `exit` (int), `signal` (0 if none), `time_ms` |
| `shell` | `cols`, `rows`, `cmd` (default login shell), `cwd`, `env` | in 0, out 1 (stdout+stderr merged, pty) | `exit` — runs until the shell exits or CANCEL; resize: `REQ resize cols= rows=` with same session id in key `sid` |
| `push` | `path`, `size`, `mode` (octal, default 644), `sha256` (optional, verified at end), `overwrite=1` | file 3 host→agent, ACKs | `size`, `sha256`, `crc32` |
| `pull` | `path`, `offset` (resume, default 0) | file 3 agent→host, ACKs from host | `size`, `sha256`, `crc32`, `mtime` |
| `shot` | `display` (default 0), `format=png\|ppm\|raw` (default png; raw = BGRA 32 bit), `scale` (percent, default 100) | shot 4 | `w`, `h`, `format`, `bytes` |
| `input` | `kind=key`: `key` (name: `Enter`,`Esc`,`F5`,`a`,… ), `mods` (`ctrl+shift+alt+super`), `action=press\|down\|up` (default press); `kind=text`: `text` (UTF-8, typed char by char, `delay_ms`); `kind=mouse`: `x`,`y` (absolute px) or `dx`,`dy`, `button=left\|right\|middle`, `action=click\|dblclick\|down\|up\|move`; `kind=scroll`: `dy` | – | `ok=1` (`n` events injected) |
| `ps` | `full=1` (optional) | out 1: TSV text, header `pid\tppid\tuid\tstate\tcpu_pct\trss_kb\tname\tcmdline` | `count` |
| `kill` | `pid`, `sig` (number or name, default TERM) | – | `ok=1` |
| `logs` | `src=kernel\|app\|all` or `name=<app>`, `lines` (tail, default 200), `follow=1` (until CANCEL), `since_ms` | log 5 | `lines`, `bytes` |
| `crashdump` | `op=list\|get\|clear`, `id` | list: out 1 (text lines `id size time summary`); get: file 3 | `count` / `size`,`sha256` |
| `reboot` | `mode=normal\|force` | – | `ok=1` (sent BEFORE the action; connection then drops) |
| `shutdown` | `mode=normal\|force`, `poweroff=1` | – | `ok=1` (same) |

Notes:

- v1 agent runs one request at a time (plus PING, CANCEL, ACK, and DATA for
  the running request). A second REQ while busy → `ERR code=EBUSY`.
  `features=mux` (later) will lift this.
- `exec` with `stdin=1`: host sends stdin as DATA stream 0 and ends it with
  END stream 0; without `stdin=1` stdin is closed.
- Output ordering within one stream is preserved; between stdout and stderr
  it is not guaranteed.
- Path `/` separators; paths are used as given (agent runs with the rights
  of its configured user, default root in test images).

## 6. Errors

`ERR payload = tlv: code=<NAME> msg=<text> [errno=<n>]`. Codes:

`EPROTO` malformed REQ/TLV · `EVER` version · `EAUTH` not authenticated /
bad MAC · `EUNSUP` unknown command/feature · `EARG` missing/bad key ·
`EACCES` disabled by `allow=` or file permission · `ENOENT` · `EIO` ·
`EBUSY` · `ETIMEOUT` · `ECRC` (data integrity failed, e.g. final sha256
mismatch) · `ELIMIT` (size/length) · `ECANCEL` · `EINTERNAL`.

Frames that fail CRC are silently dropped (resync, section 3) — they never
produce an ERR, so a noisy line cannot trigger an ERR storm.

## 7. Latency / throughput targets (measured by `tools/odb/run.sh`)

PING round trip, `info`, `exec echo`, `push`/`pull` of 1 MiB, `shot`.
Numbers are recorded in `reports/20261018-W-O1.md` and the gate output.

## 8. Versioning

`ver` in the frame header = wire version (1). New features announce
themselves in `hello features=…`; clients test features, not versions.
Changes after the first push are listed in the section below.

### Change log

- 2026-10-18: v1 initial.

## 9. Host tools (odbc) — W-O2

The host client lives in `tools/odbc/` (see its README): `odbc.py` CLI, `odb/` package (frame codec with resync, TLV, session with
hello/auth, RETRY, CANCEL, go-back-N file transfer, transports unix/tcp/pipe/tty/com), `odb/mock.py` (Python mock agent that
implements this spec, with fault injection), `bench.py`, `qemu.sh`, unit tests (gate `odbc`).

Client behaviour worth knowing when writing the agent:

- Host ids start at 1 and wrap at 2^32-1; PING uses fresh non-zero ids (PONG must echo id + payload).
- REQ is re-sent with `RETRY` every 2 s (max 5x) until the first frame of that id arrives; after that only the inactivity timeout
  (`-t`, default 15 s) applies. Frames of other ids are ignored (kept in `Session.stray`).
- ACK rule used by the host sender/receiver: an ACK is a cumulative progress report. The sender rewinds only on a DUPLICATE ACK
  (`next <= last acked` while it has sent beyond) or after 2 s without ACK; an ACK with progress is never a rewind (otherwise every
  normal windowed ACK would resend data). The receiver ACKs every `window/2` bytes, after END, on a gap (offset > next) and after 2 s of silence.
- `push` sends `sha256` in the REQ and again in the END TLV (`size`, `sha256`); `pull` verifies `sha256`/`crc32`/`size` of the RESP.
- `exec` ends with RESP (`exit`, `signal`); the per-stream END frames precede it and are optional for the host.
- `ps` is read from stream 1, `logs` from stream 5, `shot` from stream 4, `crashdump list` from stream 1, `crashdump get` over stream 3.

## 12. Idle agent and wake preamble (additive, v1)

- After 3 s without a byte on the line (and an empty receive buffer) `odbd` polls the UART only every ~5 ms instead of
  spinning, so an idle agent costs next to no CPU. The 16-byte UART FIFO cannot hold the head of a frame while it sleeps.
- A host that was silent for more than 8 s (or has just connected) therefore sends a WAKE PREAMBLE before its first frame: 160 zero octets, then a
  pause of 50 ms. Zero octets are garbage to the frame resync (the magic is `ODB1`), the pause lets the agent wake and
  switch back to fast polling (it stays fast for 3 s after the last frame). `tools/odbc` does this in `Transport.write`
  (`ODB_WAKE=0` turns it off).
- Resync after a cut frame: the 250 ms silence is measured from the FIRST EMPTY POLL after the last byte, not from the
  last byte (the agent can be busy for longer than that in a disk write while the rest of a good frame is on its way).
- `exec` returns when the shell has exited and the pipes stayed quiet for 300 ms (a detached child that keeps the pipes
  open does not hold the answer back). `logs` honours `lines` (tail, default 200).
- The slow poll alone did not make the agent cheap: the kernel read of `/dev/odb0` (`kernel/drv/con/odbuart.fi`) spun
  40000 port reads on an empty FIFO per call (~100+ % of a vCPU in QEMU/KVM). The spin is now long (8000) only when the
  previous read returned octets ("hot") and 16 polls after an empty read ("cold"). Measured idle cost: 97 % -> 2 % of a
  host core (gate section 7b); `exec echo` round trip 1023 ms -> 159 ms.
