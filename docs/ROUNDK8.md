# Round K8 — a network card, and the stack of round K3 on top of it

Round K2 taught the kernel to read its own machine over PCI and to let a
disk fetch its own commands out of memory. Round K3 wrote a TCP/IP stack
in Firn — Ethernet, ARP, IPv4, ICMP, UDP, TCP with all eleven states —
and measured it against the Linux kernel **without a driver under it at
all**: a program on the host held one end of a `veth` pair and called
`net_input`/`net_output` directly. That proved the protocol and nothing
about an operating system.

This round closes the gap. A virtio-net driver in Firn, the stack of
round K3 pulled in as a **dependency and not as a copy**, a seam between
the two, socket system calls with the numbers of Linux x86-64, and two
programs in `/bin` that use them.

| | |
|---|---|
| driver | `kernel/virtio.fi` — 925 lines |
| seam | `kernel/inet.fi` — 1,135 lines (memory, clock, lock, sockets, ICMP) |
| services to measure | `kernel/netsvc.fi` — 605 lines |
| system calls | `kernel/sys.fi`, the K8 section — 486 lines |
| userland | `lib/libc/net.fi` 265, `kernel/user/ping.fi` 210, `kernel/user/wget.fi` 299 |
| the wire | `tools/net/bruecke.c` 170, `tools/net/run.sh` 582 |
| stack | **not written here** — `vendor/firn/lib/net/`, 2,646 lines, pinned by `vendor/firn/COMMIT` |
| guard | `tools/net/run.sh`, **74 proofs**, section 12 of `test.sh` |

---

## 1. The stack is a dependency, not a copy

This is the first thing the round decided and the reason it is written
down first. `lib/net/` exists once, in Firn, at the commit
`c66c6bcd5f30d632d74e20facb6a5757c6043379` — and that commit is already
nailed down in this repository, because it is the same one the
**compiler** comes from.

`vendor/firn/hole-firnc.sh` unpacks that commit and copies the whole Firn
library to `vendor/firn/lib/`. Both compiler stages look for an `import`
last in `<directory of the compiler binary>/../lib`. So

```firn
import net.wire
import net.tcp
import net.stack
```

inside the kernel finds **exactly the state named in `vendor/firn/COMMIT`
and no other**. There is no second copy that could drift, `$FIRNLIB`
points at this repository's own `lib/` (the libc), and `lib/net/` here
does not exist on purpose.

Section 1 of `./test.sh` checks it, and not by looking: the three blob
hashes in `vendor/net/BLOBS` are the ones Firn has in the tree of that
commit, and `git hash-object` recomputes them against the files
`hole-firnc.sh` really unpacked. Pull `COMMIT` forward and let the stack
change with it, and the acceptance run says so before any measurement
does. `vendor/net/HERKUNFT.md` has the whole story.

Two diverging copies of the same code have been expensive three times in
this project already.

---

## 2. The driver

`virtio-net-pci`, in the **modern** shape of the virtio 1.0
specification: the four regions are read out of the device's own
capability list, the features are negotiated, the queues are described
with 64-bit addresses.

Why virtio and not e1000, in one sentence: e1000 is a data sheet —
EEPROM reads, a PHY, sixteen registers whose names only mean something
with the manual open — and every line of it would be about an Intel chip
from 2000. virtio is one ring structure that every virtio device shares
and a feature negotiation that is a protocol rather than a table of
quirks.

Why the modern path and not the legacy one, which is fewer lines: legacy
virtio is port I/O for every register (`in ax, dx` — exactly what round
K2 left behind), a queue address that is a 32-bit **page number**, and no
way to say which of several regions is which. The modern layout is read
out of the device, the same way the BARs were.

**What it does.** Find the card (vendor 0x1AF4, class 02:00); walk the
capability list for the five vendor capabilities and tell them apart by
`cfg_type`; reset the device and wait for the reset to be acknowledged;
ACKNOWLEDGE, DRIVER; negotiate; FEATURES_OK and **check that it stayed
set**; build two split virtqueues of 64 descriptors each with 2 KiB
buffers; arm MSI-X entry 0 or the interrupt pin; enable both queues;
DRIVER_OK; fill the receive ring and ring the doorbell.

**What was negotiated,** measured rather than claimed —
`features=0x100010020`:

| bit | name | why |
|---:|---|---|
| 5 | `VIRTIO_NET_F_MAC` | the device has an address and this driver refuses to invent one |
| 16 | `VIRTIO_NET_F_STATUS` | link up/down |
| 32 | `VIRTIO_F_VERSION_1` | without it none of the layout above holds, and `negotiate` refuses |

Everything else is **refused**: no merged receive buffers, no checksum or
segmentation offload, no control queue, one queue pair, no packed rings,
no indirect descriptors. Refusing is a decision the device is told about
rather than one the driver keeps to itself.

**What it does not do,** said plainly: it cannot receive a frame larger
than 2 KiB (every Ethernet frame is smaller), it has one queue pair so
it cannot spread receive work over the four cores of round K5, and it
computes every checksum in software because it refused to let the device
do it.

---

## 3. The seam: memory, clock, thread, lock

`stack.Stack` is **1,125,520 octets** and Firn has no global variables
(SPEC 14.1 item 5). So it lives in a run of frames the kernel allocates
once and hands over as a pointer — the same answer `kstate.fi` gave the
same question in round 59. Three more pages go with it: one for what
`net_output` writes a frame into, one bounce page for what a system call
copies out of ring 3, one for the two `sockaddr_in` of a call.

**The clock.** The stack asks for microseconds. The kernel's tick is a
hundredth of a second, which would quantise every round-trip estimate to
10,000 µs. So `now_us` reads the TSC and divides by the frequency round
K2 measured; without an APIC it falls back to the tick.

**The thread.** `net_input` and `net_output` are called from **exactly
one place**: a kernel task of its own, `K_NETD`, whose body is
`inet.netd_body`. It is a task and not a loop inside a system call
because a `ping` from the other side has to be answered while every
process in the system is waiting for something else. It spins with
`yield_now` while anything is moving and lies down with `sleep_ticks(1)`
when the wire has been quiet for 4,000 turns.

**The lock.** One struct, two writers: `net_input` out of the network
task and `net_send` out of a system call. `atomic.L_NET` is the seventh
lock of `atomic.fi` and it is held with interrupts off, the same
discipline round K5 gave the run queue, the frame allocator and the file
system. The interrupt handler does **not** take it — it acknowledges the
device, counts, and returns; a TCP state machine in interrupt context
would run on whichever kernel stack happened to be current, with
interrupts off, for as long as a retransmission takes.

### 3.1 The one thing the stack has no door for

`lib/net/stack.fi` answers an ICMP echo **request** — which is why a
`ping` from the host works with nothing added — but it cannot **send**
one, and its ARP cache is private (`arp_slot_mac` is not exported). A
`ping` on Osum needs both.

Changing the vendored library would be exactly the copy this round exists
to avoid. So the ICMP path is built in `inet.fi` on top of `net.wire` —
the same module the stack itself uses for every header — with a hardware
address cache of its own, eight entries, fed from the source address of
every frame that comes in. That is a duplication of forty octets of
state and it is written down here rather than hidden. The right fix is a
raw-datagram door in `lib/net/stack.fi`, and it belongs in Firn, not
here.

---

## 4. The sockets

`kernel/sys.fi`, in the same table as `read` and `write`, with Linux's
numbers — because stage 2 of this plan is to run a statically linked
Linux binary and every number picked differently is a translation table
somebody has to keep right.

| call | number | | call | number |
|---|---:|---|---|---:|
| `socket` | 41 | | `shutdown` | 48 |
| `connect` | 42 | | `bind` | 49 |
| `accept` | 43 | | `listen` | 50 |
| `sendto` | 44 | | `getsockname` | 51 |
| `recvfrom` | 45 | | `getpeername` | 52 |
| `setsockopt` | 54 | | `accept4` | 288 |

There is no `send` and no `recv` in the x86-64 table: glibc turns both
into `sendto`/`recvfrom` with a null address, and Osum copies that.
Errors are negative and come out of the one list in `kernel/errno.fi`,
which grew the socket block of `asm-generic/errno.h` this round —
`-EAFNOSUPPORT` 97, `-EADDRINUSE` 98, `-ECONNRESET` 104, `-ENOTCONN`
107, `-ETIMEDOUT` 110, `-ECONNREFUSED` 111 and nine more.

**A socket lives in two tables at once.** In the open file table of round
K4 it is kind `file.K_SOCK` with the socket number in `OF_INO` — which
is what makes `read`, `write`, `close`, `dup2` and `fork` work on it
without any of them learning what a socket is. In the socket table of
`inet.fi` it has a kind, a handle in the stack of round K3, and a bound
port. The reference count of the first decides when the second is torn
down: a forked child that closes its copy does not take the parent's
connection with it.

Three kinds:

* `AF_INET` + `SOCK_STREAM` → TCP,
* `AF_INET` + `SOCK_DGRAM` → UDP,
* `AF_INET` + `SOCK_DGRAM` + `IPPROTO_ICMP` → the **ping socket** Linux
  has had since 3.0. That is what `/bin/ping` uses, and it is why it
  needs no raw socket and no privilege.

**`close` on a TCP socket is an orderly close and not a teardown.** The
FIN travels and `tcp.fi` walks through LAST_ACK or TIME_WAIT on its own
and frees the slot when it is due. The first attempt at this round in
Firn (K3) is on record as having got exactly that wrong — "TIME_WAIT
holds the slot and then frees it" — and a `close` that tore the slot out
here would be the same bug one layer up.

---

## 5. Measured against the Linux kernel

`/dev/net/tun` does not exist in the container this repository is
measured in and cannot be created there. `AF_PACKET` needs no device
node, so the wire is:

```
Osum in QEMU <--virtio-net--> QEMU <--UDP on the loopback-->
tools/net/bruecke <--AF_PACKET--> veth v0 | v1 <--> Linux in the
network namespace k8net, 10.9.0.1/24
```

Osum is 10.9.0.2/24. Checksum offload is switched off on both veth ends:
over a `veth` the kernel hands out locally generated frames with
`CHECKSUM_PARTIAL` — a checksum field it has **not** filled in — and a
stack that checks the checksum rightly throws every one of them away.
That cost round K3 an afternoon and it is in the script rather than in
somebody's memory.

**Everything below is QEMU/TCG. There is no KVM in this container**
(`/dev/kvm` does not exist), so every instruction of Osum is emulated
and every number is a number about an emulator. The comparisons between
them are what mean something.

### 5.1 The numbers

| what | result |
|---|---|
| `ping -c 10` from the Linux kernel | **10 of 10 answered**, round trip 8.6 ms average |
| ARP | Linux asked, Osum answered, the entry went into Linux's neighbour table |
| MSI-X interrupts for those ten | 24 |
| `nc` pushes 1 MiB in | **1,048,576 octets**, 733 frames, 0 bad checksums, 0 retransmissions, 0 dropped by the driver, **5,765 KiB/s** (177,608 µs) |
| `nc` through the echo | **262,144 octets there and back, md5 identical**, 2,045 KiB/s |
| `curl http://10.9.0.2:8080/` | status line, headers and `Content-Length: 40` accepted by curl itself |
| Osum connects **actively** to a python server | 262,144 out, 262,144 back, **0 wrong octets**, ephemeral port, clean close |
| UDP, 5 datagrams of 1,400 octets | all five came back **reversed**, checksums intact |
| `tc netem loss 20 %` Linux → Osum | all 262,144 arrive **in order**, 75 segments reassembled out of order, 35 KiB/s against 5,765 on a clean wire |
| `tc netem loss 20 %` Osum → Linux | 65,536 out and back, **0 wrong**, **1 retransmission on the timer and 6 on three duplicate acknowledgements**, 198 KiB/s |
| `/bin/ping` in ring 3 | 3 of 3, 0 % loss |
| `/bin/wget` in ring 3 | status 200 from a real python HTTP server, 46 octets of body |

The echo is half the speed of the sink and that is not a mystery: every
octet is handled twice, and between the two halves stand a `recv` and a
`send` through the same single-threaded pump.

**The throughput is not a claim about how fast Firn is.** It is what
came out of an emulator without hardware virtualisation, with a
user-space bridge in the middle, a network task that runs at the mercy
of a 100 Hz scheduler, and a stack that computes every checksum itself
because it refused every offload. The number that means something is the
one next to it: with the driver switched off, the same kernel image
transfers nothing at all.

### 5.2 The counter-checks

A test that only asks whether the expected thing happened passes with an
implementation that always says yes. Every claim above has one that has
to collapse:

| switch | what has to happen | what happened |
|---|---|---|
| **no `nic`** | the same kernel image never touches the card | `ping` 100 % loss, `nc` cannot open the connection at all, `nic: skipped` in the log |
| **`nicnobm`** | no bus master bit: the device may answer registers but may not fetch a descriptor | `master=0`, ping 100 % loss |
| **`nicnoirq`** | the message vector is masked: the frames still arrive because the task polls the ring, and **not one interrupt** does | 262,144 octets arrived, `irqs=0` — both in the same run |
| **`nicintx`** | the same card over its interrupt PIN through the I/O APIC instead of MSI-X | 262,144 octets, `irqs=33` |
| **UDP reversed** | an echo that merely mirrored frames would pass; a reversal will not | 5 of 5 reversed |
| **`tc netem`** | one frame in five thrown away, and TCP still delivers every octet in order | it did, and the retransmission counters say what it cost |

The switch that turns the card on is the word **`nic`** and not `net`,
and that is not taste: the counter-check runs the same command line
without it, and every parameter of this round (`nip=`, `ngw=`, `nsvc=`)
carries the three letters `net` inside it. A switch that its own
arguments turn on again is no switch.

---

## 6. The two traps, and what they cost

**Checked arithmetic.** Since round 72 plain `+`, `-` and `*` are checked
and abort on overflow. TCP sequence numbers are *defined* to wrap, and so
are the 16-bit ring indices of a virtqueue. `lib/net/wire.fi` and
`tcp.fi` already had that right — round K3 paid for it. This round paid
for it once more in `virtio.fi`, where `avail.idx` and `used.idx` wrap at
2^16: every one of them is `+%`/`-%` and masked with `& 0xFFFF`. The
plain operator would have panicked the kernel after 65,536 frames, which
is a megaoctet and a half — that is, in a measurement rather than in a
test. Section 11 of the acceptance run checks that no `osum_panic` is in
the log.

**TIME_WAIT.** Section 4 above: `close` hands the connection to the state
machine and does not free the slot itself.

**And one this round found on its own.** The active test reported 77,880
wrong octets out of 262,144 on a connection that had carried every one of
them correctly. The bug was in the *test*: the pattern buffer is one page
long, the send read from `sent % 4096` for up to 4,096 octets, and the
last part of every send ran past the end of the pattern into the buffer
the answer was being read into. A measurement can be wrong in exactly the
way it is supposed to catch, and the only reason it was found is that the
same run also printed `sent` and `back` and both were right.

---

## 7. What is missing

* **No name resolution.** Osum has no resolver and no `/etc/hosts`; an
  address is four numbers. `/bin/wget` refuses a URL with a name in it
  rather than answering something wrong.
* **No raw datagram door in the stack.** See 3.1 — the ICMP path is
  beside `stack.fi` instead of in it.
* **One queue pair.** Round K5 has four cores; the network task uses one.
* **No offload of any kind**, by refusal, so every checksum costs the
  processor.
* **A `connect` and an `accept` give up after thirty seconds** with
  `-EAGAIN` rather than waiting for ever. Bounded on purpose: a
  measurement that ends in the time limit of the shell script measures
  nothing.
* **One bounce page for the whole system.** Two processes in `sendto` at
  the same instant would share it — the same shape `kstate.BLOCK_OFF`
  has had for every file operation since round 62, and no better for
  being older.
* **No IPv6, no fragment reassembly, no window scaling, no SACK.** Those
  are the stack's gaps and they are listed in `docs/OSUM-K3.md`.
* **The round trip is 8.6 ms** and about 10 of that is the network task
  waking up on the next tick when the wire has been quiet. A wake from
  the interrupt handler would take it down; it would also mean touching
  the run queue from interrupt context, and that is a change to
  `sched.fi` while another round is working in this repository.
