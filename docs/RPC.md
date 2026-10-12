# RPC on the bus -- request / reply (kernel/user/rpc.fi)

Status: **built and measured** (`bash tools/rpc/run.sh`, T01..T16 + stress).

## 1. What it is

A small library on top of the existing frame layer (`actwire.fi`, docs/ACTION-BUS.md 4):
no new syscall, no kernel change. It replaces the three hand-written
request/reply loops (act, orientbus, notes) for every new service:

| side | calls |
|------|-------|
| client | `client_open`, `call(svc, req, len, out, max, timeout_ms)` (sync), `call_async` -> id, `state_of(id)`, `take(id, out, max)`, `cancel(id)`, `pump(ms)`, `last_len`, `last_error` |
| server | `serve_open(name, access)`, `serve_next(ms)` -> slot, `req_buf/req_len/req_over/req_pid/req_uid/req_id`, `reply(slot, data, len)`, `fail(slot, code, data, len)` |
| both | `stat(i)` counters (calls, replies, timeouts, late, gone, served, sent, dead box, protocol) |

A process can be client and server at once: `pump` queues requests for `serve_next`
and routes replies to their pending calls.

## 2. Wire

Frames of actwire (`K_REQ`/`K_REP`, same 32-bit id). Request payload: opaque
(text by convention). Reply payload: **one status octet** + data.
Status 0 = ok, 1..99 server side (`E_BADREQ 1`, `E_NOMETHOD 2`, `E_BUSY 3`,
`E_DENIED 4`, `E_TOOBIG 5`, `E_FAILED 7` and up for the service's own errors),
100+ client side (`E_TIMEOUT 100`, `E_NOSVC 101`, `E_SEND 102`, `E_GONE 103`,
`E_NOSLOT 104`, `E_PROTO 105`, `E_PENDING 106`, `E_BADID 107`, `E_NOBOX 108`).

## 3. Rules

* Reply box `r.<pid>` is `A_SAMEUID`; a service of another user answers only as root.
* Server learns the caller from `req_pid/req_uid` -- stamped by the kernel, not by the text.
* Client accepts a reply only for a waiting id and only from the pid of the FIRST frame;
  a middle frame from another pid is dropped and counted (`stat 8`).
* Timeout 0 = 5 s. A late reply (after timeout/cancel) is dropped and counted (`stat 3`).
* While waiting, the client asks every <=100 ms whether the service still exists.

## 4. Limits (declared, tested)

request <= 2047 octets (else the server sees `req_over` -> `E_TOOBIG`);
reply <= 4094 octets of data (else `E_TOOBIG`); 8 calls in flight per process
(`E_NOSLOT`). Bigger data: bus segments (`bus.seg_*`), pass the segment id in the request.

## 5. Known limit: dead but unreaped servers

The kernel frees a task's bus names at **reap** (`proc.reap` -> `bus.forget_task`),
not at exit. A server that crashed and whose parent did not `wait` keeps its name:
the client then gets `E_TIMEOUT` at its deadline, not `E_GONE`. With a reaped server
`E_GONE` comes within one slice. Fix (separate kernel item): free the names at exit.

## 6. Tests

`tools/rpc/run.sh` (guest under QEMU, rpcd = test service, rpcc = battery):
T01 echo, T02 service error, T03 unknown verb, T04 no service, T05 timeout, T06 late reply dropped,
T07 async out of order, T08 kernel pid, T09 3000 B reply, T10 reply too big, T11 request too big,
T12 8 in flight + 9th refused, T13 cancel, T14 dying server, T15 afterwards, T16 1000 calls.
Section 3: 3 parallel clients x 300 calls on 4 cores, every answer exact. Section 4: counter-proof
without a bus (T01 must fail, no hang). Latency: LAT line (tick resolution 10 ms).
