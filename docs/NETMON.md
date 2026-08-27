<!-- SPDX-License-Identifier: GPL-2.0-only -->
# Round NETMON — who used how much, and handing the connection on

Before this round Osum could send and receive (round K8), and since
round NETVIEW it could give a single process a network of its own. What
it could not do was answer the first question anybody asks about a
network: **which program is using it, and how much.** There was no
`netstat`, no `ss`, no connection list, and no counter that belonged to
anything smaller than the card.

This round is that counter, the list that goes with it, the history that
survives a reboot — and the second half of the job: **handing this
machine's connection on to another machine.**

Everything below is a number out of `tools/netmon/run.sh`. That run was
green at **70 of 70** when this file was written.

---

## Part 1 — the accounting

### 1.1 Two numbers per direction, and the difference is the point

Every accounting of "data used" that reports one number is hiding
something. This one reports two:

| | what it is |
|---|---|
| **payload** | the octets the PROGRAM handed to `send` or took out of `recv`. The number that matches the file it downloaded. |
| **wire** | the octets that really crossed the card: Ethernet header, IP header, TCP header, acknowledgements, retransmissions and all. The number a data plan is billed by. |

Measured, on a 65 536-octet file fetched by `/bin/wget` from a python
HTTP server on the other side of a veth pair:

```
the server sent                      65 536 octets of body
wget itself reported                 65 536
the kernel counted for wget, payload 65 691   (+155 = the HTTP header)
the kernel counted for wget, wire    68 247
the card itself counted, inbound     68 613
```

The wire is **4 % more than the payload** for one large download. That
is why "data used" never matches the size of the file, and it is the
smaller error of the two: for a program that sends forty octets every
second the two numbers differ by a factor of three, because every one of
those forty octets travels with fifty-four octets of header and is
answered by a bare acknowledgement of the same size. A monitor that
reported only the payload would tell that program's user it used
nothing.

### 1.2 Where each one is counted, and why there

The two places are not the same place, and the choice of each is the
substance of the round.

**Payload** is counted in `kernel/inet.fi`, in `sock_send`, `sock_recv`,
`sock_sendto` and `sock_recvfrom`. Those four functions are where every
octet of every process passes AND where the socket is known. That is the
seam where a connection is tied to a process.

* Not in `kernel/sys.fi`: that layer also carries the octets a **faked**
  socket of round NETVIEW swallowed, and those never touched a wire.
  Counting them would say a program used a network it was being kept
  away from.
* Not in `lib/net/stack.fi`: that is vendored library code and has never
  heard of a process.

**Wire** is counted in `inet.pump`, per frame, in both directions. The
pump is the only caller of `net_input`/`net_output`; a frame not seen
there did not happen. Each frame is classified by its **local port** —
source port outbound, destination port inbound — and that port is looked
up in a socket table that knows the owner.

Two paths do **not** go through the pump and are counted where they are:

* `inet.icmp_send` builds an echo request and hands it to the card
  itself, because the vendored stack cannot send one. The first measured
  run of this round showed `ping  192 <- 192 payload, wire 0 <- 294` —
  the outward half missing entirely. There is a `frame_seen` call there
  now, and the run checks it (`ping, WIRE out … 294`).
* `inet.arp_ask` likewise. ARP belongs to nobody and goes to the system
  bucket, which is what that bucket is for.

### 1.3 Whose socket it is

`inet.fi` keeps sixteen sockets and never knew who opened them: a socket
is an entry of the open file table, and that table is shared by `fork`
and `dup2`. So the owner is written down **once**, when the slot is
taken, in the one moment the asking task and the running task are the
same task. Everything afterwards — including a frame arriving while a
completely different process holds the processor — reads that record
instead of asking the scheduler, which would be wrong most of the time
and spectacularly wrong under load.

`inet.sock_new` records a provisional owner as well, because the
kernel's own network service (`netsvc.fi`) opens sockets by calling
`inet.fi` directly and never through a system call. Without that, the
throughput measurement showed `hit=0 miss=774`: every frame of a
megaoctet in the system bucket.

### 1.4 What it costs

**The stopwatch measurement is in the run and it is worthless here.**
Move a megaoctet with the counting on, move it again with `nonetmon`,
compare. Four alternating pairs during development, same image, same
wire:

```
with counting     2282  3179  3484  4005  KiB/s
without counting  2695  5831  4363  2642  KiB/s
```

The ranges overlap and one pair comes out the wrong way round. There is
no `/dev/kvm` on the machine this repository is measured on, so QEMU
emulates every instruction, and four other rounds of this repository
were building at the same time — load average twenty on twelve cores.
That is a measurement of the neighbours, not of the counter. It is
printed anyway, labelled as such.

**The measurement that means something** calls `netmon.frame_seen`
65 536 times on a frame the kernel builds, between two reads of the
cycle counter, three times (`netmonbench` on the command line):

```
counting switched off (the floor)          440 cycles per frame
cache hit  (every frame of a transfer)   5 292 cycles per frame
whole socket table walked                8 587 cycles per frame
```

so the counting **adds 4 852 cycles = 2 201 ns** to a frame at 2 204
MHz. These are cycles under QEMU's instruction emulator; the absolute
number is not a property of the code. What is a property of the code is
the share, computed from the same run:

```
1 048 576 octets moved in 439 ms, 776 frames classified
776 x 2201 ns = 1707 us of classifying in 439 ms
```

**0.3 % of the time the transfer took.** The run fails if it is above
5 %.

It is 0.3 % because of a **one-entry cache**. The first version walked
all sixteen socket records for every frame; during a transfer every
frame carries the same local port, so one remembered answer turns
sixteen records into one comparison. Measured over the same megaoctet:
**769 of 776 frames answered out of the cache, 1 needed the table
walked.** The cached slot is verified before it is used — a socket can
be closed and its slot handed to somebody else between two frames, and a
cache that trusted itself would put one program's octets on another.

### 1.5 The attribution, not the sum

A counter that gets the total right and the split wrong passes a test
that adds them up. So the run puts two programs on one wire in one boot,
one using a lot and one using a little:

```
ping   payload      192 out /    192 in     wire  294 out /  294 in
wget   payload       54 out / 65 691 in     wire  328 out / 68 247 in
ratio wget/ping                                              340 : 1
```

### 1.6 The connection list — `/bin/netstat`

The name and the shape are the ones every Unix has had for thirty years.
Measured, while a download was open:

```
Proto Local                Remote               State       Age  Program
tcp   10.9.0.2:61545       10.9.0.1:8000        ESTABLISHED    2 wget
```

* `netstat` — the live connections
* `netstat -a` — and the listening sockets
* `netstat -p` — per program: payload and wire, both directions, since boot
* `netstat -t` — per process instead of per program
* `netstat -s` — the machine, and the card's own numbers to hold it against
* `netstat -w` — fold the counters into the history file
* `netstat -H` — show the history

Every number comes out of one system call, `SYS_NETMON(kind, index,
field)`. There is no buffer and no pointer into the kernel anywhere in
that program — which is, as `ps` put it in round K6, why a `netstat`
that lies is a `netstat` the kernel lied to.

**One bug found by looking at that output** and worth recording: the
socket record was 64 octets while it had twelve fields of eight.
`sset(S_RXWIRE)` wrote 24 octets past the end of record *i*, into the
first three fields of record *i+1*, one of which is the flag that says
the record is in use. The symptom was a `netstat` listing a connection
nobody had opened, with no owner and no port, protocol read out of an
octet belonging to somebody else. There is a test for it now
(`rows for a socket that was never opened … 0`).

### 1.7 The history — `/var/net/usage`

A counter that starts at zero every boot cannot answer "how much has
this program used this month". So the running totals are folded into a
small text file, and the file is what survives:

```
# osum network usage -- period program sent recvd wire-out wire-in
2026-08-27 ping 128 128 196 196
2026-08 ping 128 128 196 196
2026-08-27 wget 54 16499 328 17313
2026-08 wget 54 16499 328 17313
```

Plain text, readable with `cat`, editable with `edit`. **No second copy
of this exists anywhere** — no index, no binary shadow, nothing that
could disagree with it.

**It bounds itself.** A day line is kept for 31 days, a month line for
12 months; older ones are simply not written back. With ten programs
that is at most 430 lines and about twenty kilooctets, which fits on the
two-megaoctet drive with room to spare. (That drive limit is real and
still there: the block bitmap is one block, so 4096 blocks of 512
octets. Round OFS3 is lifting it on its own branch.)

**Nothing is counted twice.** `SYS_NETMONROLL(program, field)` hands out
what has been used since the last roll and moves the kernel's watermark
in the same call, so a second `netstat -w` immediately after the first
writes nothing at all. Measured:

```
netstat: programs written 1
netstat: programs written 0
```

### 1.8 THE DATA PROTECTION RULE

**What is recorded is HOW MUCH per program. Never WHERE.**

There is no address, no host name and no port in `/var/net/usage`, and
there never will be. The run checks it — `addresses in the history file
(there must be NONE): 0`, `ports …: 0` — because a rule that is only
written down is a rule that erodes.

A file that remembered every address every program ever reached would be
a surveillance database on the user's own disk, kept by their own
operating system. It does not become acceptable by never leaving the
machine: a disk can be taken, imaged, subpoenaed or backed up, and the
person it belongs to did not ask for that record to exist.

The **live** connection list does show destinations, and that is not a
contradiction. It is read out of the kernel's live table at the moment
somebody asks, it disappears when the connection closes, and a person
asking *right now* what their machine is talking to has every right to
know. The difference between the two is the difference between looking
and recording.

The remote address of a connection lives exactly as long as the
connection: `inet.sock_free` clears the record.

---

## Part 2 — handing the connection on

### 2.1 WHY THERE IS NO WLAN HOTSPOT, said first

Windows has a feature called **Mobiler Hotspot**. It turns the machine's
**wifi adapter** into an access point: other devices see a network name,
join it with a password, and reach the internet through this machine.

That needs 802.11 — the whole of it, association, authentication, the
four-way handshake, WPA2 — **and** a wifi driver whose firmware can run
in access-point mode.

**Osum has not one line of 802.11.** No wifi driver, no wifi stack, no
802.11 frame format anywhere in this repository. The only network card
this kernel has ever spoken to is virtio-net over PCI. A WLAN hotspot is
therefore **not possible here**, and announcing one would be announcing
something that cannot work. It is not a matter of effort: it is a
device-driver problem for hardware this system does not support, plus a
protocol stack of roughly the size of the TCP/IP one.

### 2.2 What was built instead, and it serves the same purpose

As soon as there are two network interfaces, the useful half of the
feature is available: **take the connection on one and hand it on
through the other.** Windows calls that *Internet Connection Sharing*.
It is three things, and `kernel/share.fi` is those three things:

* **forwarding** — a frame arriving on the shared side that is not for
  this machine goes out of the uplink instead of being dropped;
* **NAT** — the addresses on the shared side are private and the world
  cannot route back to them, so every connection leaves wearing this
  machine's address and a port that belongs to it, and a table of 64
  records remembers whose port was whose;
* **a DHCP server** — a device just plugged in has no address. It asks,
  and something has to answer.

**The DHCP server is not the DHCP client.** `kernel/user/dhcp.fi` has
existed since round DESKTOP and it *asks* for an address, in ring 3.
This *answers*, in the kernel, because the frames it answers arrive on a
card no process can see. They share a packet format and nothing else —
no code, no state, not even a direction.

### 2.3 The DNS forwarder, honestly

Clients are handed the uplink's gateway as their name server (DHCP
option 6), and their queries to it are carried by the NAT like any other
datagram to port 53. That is **forwarding by routing and not a resolver
of our own** — this system has no resolver at all, as `/bin/wget` says
when it is given a name instead of an address. A client whose gateway
does not answer DNS gets no names. That is the honest half of the
feature; the other half is a round of its own.

### 2.4 The second card

`kernel/virtio.fi` was written for one card, with its scalars at fixed
offsets. It now takes a card number: `sc(c, off)` picks the block, card 0
stands exactly where it stood (octet for octet, which is why every
measurement of round K8 still reads the same numbers) and card 1's block
begins at `K2_SCALARS + 0x1400`. Each card gets its own ring memory, its
own MSI-X vector (45 and 46) and its own place in the PCI scan — `find`
returns the *c*-th virtio-net on the bus, not the first, because
otherwise the second driver takes the first card's registers away and
both break in a way that looks like a hardware fault.

The old names (`virtio.rx_take`, `virtio.tx_frame`, …) still exist and
mean card 0. Forty call sites in four files did not have to learn about
a second card.

### 2.5 Two machines, measured

The run builds this:

```
the namespace  10.9.0.1        (a python HTTP server -- "the internet")
      |  veth + AF_PACKET bridge + QEMU's UDP socket backend
MACHINE A  10.9.0.2 on card 0   192.168.42.1 on card 1   `share`
      |  QEMU's UDP socket backend, card 1 to card 0
MACHINE B  169.254.1.9/16 -- a placeholder it cannot route with
```

Machine B is a **second Osum**. Everything it ends up with, it got from
machine A. Measured:

```
dhcp: offer ip=192.168.42.100  maske=255.255.255.0  gateway=192.168.42.1  server=192.168.42.1
dhcp: ack ip=192.168.42.100  lease=3600
ping 192.168.42.1   2 transmitted, 2 received, 0% packet loss
ping 10.9.0.1       2 transmitted, 2 received, 0% packet loss     <- through the NAT
wget http://10.9.0.1:8000/x   65 536 octets, three times          <- through the NAT
```

and on the router:

```
share: clients=1 nat=4 made=4 evict=0 out=44 in=150
       offers=1 acks=1 arps=4 drops=0
```

**`drops=0` is the interesting zero.** Before the gateway's hardware
address was resolved up front, the first packet of the first client was
always dropped while the ARP question was out, and a `ping -c 3` lost
its first echo. `share.pump` now asks once per boot, ahead of any
client.

The router's own per-process accounting puts every forwarded frame in
the **system bucket**, and that is right: a frame belonging to another
machine belongs to no process on this one.

### 2.6 Two things that had to be built to make this work at all

**Proxy ARP on the shared side.** Osum's own DHCP client cannot send a
broadcast without first resolving a next hop — the vendored stack looks
one up even for 255.255.255.255, and round DESKTOP wrote that down as a
limit it could not fix, because the stack is pinned vendor code. It can
be fixed from the *other* side, and it is: the gateway answers ARP for
its own address, for 255.255.255.255, and for **any address outside the
shared subnet** — since everything off that subnet really does go
through this machine, answering with our own address is the truth. An
address *inside* the subnet that is not ours is not answered: that is
one client asking about another, they are on the same wire, and putting
ourselves in the middle would be a lie and a bottleneck.

**An address out of the pool, not the one the client already had.** The
first measured run offered the client 169.254.1.9 — the placeholder it
booted with — because the forwarder had learned that address from the
DISCOVER packet's source field. A client that has not asked yet is still
carrying whatever it was booted with, and it is one line to say so.

### 2.7 ICMP through a NAT

ICMP has no ports. The **identifier** of an echo does the same job and
is substituted like one — that is what every NAT does and it is why
`ping` through a router works at all. The identifier must **not** also
be stored as the remote port: on the way back it is the one *we* put in,
not the one the client chose, and the reverse lookup never matches. The
first measured run of part two showed exactly that: a `ping` that went
out and never came back.

---

## The interface

`/bin/netmon` is a window with three tabs:

* **Programs** — one row per program: rate now, used today, used this
  month, and which network of round NETVIEW it can see. Below it four
  buttons — `real`, `filtered`, `faked`, `none` — which set that view
  for **every living process of the selected program**. That is the join
  between the two rounds and the reason both exist: seeing who is
  talking, and switching it off in the same window.
* **Connections** — the live list, the same one `/bin/netstat` prints.
* **Sharing** — the shared side's address and pool, a button to switch
  it on and off, and one row per connected device with what each has
  used. Those numbers fall out of part one: the forwarder counts a
  client's octets in the same breath as it moves them.

The rate graph is **thirty-two samples of ramp characters in an ordinary
label**, and that is said out loud rather than dressed up. A pixel graph
needs a drawing surface `wlib` does not offer an application; inventing
one here would be a window-server round wearing a network round's name.
The measurement behind it is real either way — it is the resolution that
is coarse, not the number.

Colours come from the theme: everything drawn goes through `wlib`, which
asks `wlibc.theme()` for every colour by its role. Nothing is a constant
in this file.

---

## WHAT IS NOT DONE, AND WHY

**1. The window was not raised in a measured run.** `/bin/netmon`
compiles, links and its whole data path runs — but started from
`/bin/sh` it reports `netmon: no window server`, because
`wlibc.start()` cannot get its drawing surface on that path. This is
**not this round's fault and the counter-check proves it**: `/bin/wigdemo`,
the reference application of round K15 and the program the widget
library is measured against, was put on the same disk and started from
the same shell in the same boot, and said `wigdemo: keine Flaeche` —
the identical failure. Applications of that library are started by the
kernel's `wig` stage, not by a shell. Wiring `/bin/netmon` into a
desktop session is one commit and one measured run; it is not in this
one, and no screenshot of it exists.

**2. The symbol font of round ICONS, the colour roles of round THEME and
the language catalogue of round I18N are not used**, because those three
rounds are being built **at the same time as this one, on their own
branches**, and are not in this tree. There is nothing here to import
them from. The texts are English strings in `kernel/user/netmon.fi` and
the rows carry no symbols. Each is one commit once those branches land.

**3. The quick-settings tile for sharing was not built.** The taskbar
and its quick settings belong to round DESKTOP/NETVIEW; the switch
exists as a system call (`SHARE(SH_SET)`, root only) and as a button in
`/bin/netmon`, but there is no tile.

**4. The NAT table was not measured under load.** The run opens five
connections (two pings, three fetches) and confirms `made=4, evict=0` —
no record lost and none left behind. The table holds 64 and evicts the
oldest when it is full, counting each eviction. **Whether it behaves
under sixty-four simultaneous connections is untested**, because the
only second machine this repository has is another Osum with one shell,
and it cannot open sixty-four at once. That number is a claim until
something opens them.

**5. There is no lease timer.** A DHCP lease is handed out with a
duration of 3600 seconds and nothing expires it. A client record is
freed only when the table is full. On a machine handing addresses to
more than sixteen devices over its lifetime that is a leak, and it is
one that shows up as "no address left" rather than as a crash.

**6. No IPv6, no fragmentation, no MTU discovery** through the
forwarder. A fragmented IP packet is dropped and counted as a drop; the
stack sets Don't-Fragment on everything it sends itself.

**7. TCP connection tracking is by five-tuple and a timestamp, not by
state.** A NAT record is not removed when the connection closes; it ages
out by being the oldest when the table is full. A real implementation
watches for FIN and RST and frees the record then.

**8. `netstat -w` has to be called by something.** Nothing calls it on a
timer yet. The monitor calls it on a button, and a person can put it in
a script. Windows does this continuously; here the history is only as
current as the last roll.

**9. The outer port range (50000–59999) does not consult the local
socket table.** It is deliberately above everything the rest of the
kernel hands out (`inet.sock_sendto` takes 40000–44095, the TCP stack
picks below that), so a collision is unlikely — but "unlikely" is not
"checked", and a collision would show up as a client's answer arriving
on a port a local program is listening on.

---

## The numbers, in one place

| what | measured |
|---|---|
| payload counted for `wget` against a 65 536-octet file | 65 691 (+155 = HTTP header) |
| wire against payload, one large download | +4 % |
| classifier, counting off (the floor) | 440 cycles/frame |
| classifier, cache hit | 5 292 cycles/frame |
| classifier, whole table walked | 8 587 cycles/frame |
| what the counting adds per frame | 4 852 cycles = 2 201 ns |
| **share of the transfer the counting costs** | **0.3 %** |
| frames answered out of the one-entry cache | 769 of 776 |
| frames placed on a process, 64 KiB download | 54 of 61 (7 = ARP and late frames) |
| history: second roll immediately after the first | 0 programs written |
| addresses or ports in the history file | 0 |
| client's address from the DHCP server | 192.168.42.100 out of .100–.150 |
| ping through the NAT | 2 of 2 |
| files fetched through the NAT | 3 x 65 536 octets |
| NAT records made / evicted / frames dropped | 4 / 0 / 0 |
| frames forwarded out / in | 44 / 150 |
| `tools/netmon/run.sh` | **70 passed, 0 failed** |

## Where it lives

```
kernel/netmon.fi          the accounting: per task, per program, per socket
kernel/share.fi           forwarding, NAT, the DHCP server, proxy ARP
kernel/virtio.fi          one card became two
kernel/inet.fi            the four payload doors, the pump, ICMP and ARP
kernel/sys.fi             SYS_NETMON 1320, SYS_NETMONROLL 1321, SYS_SHARE 1322
kernel/user/netstat.fi    /bin/netstat, and the history file
kernel/user/netmon.fi     the window
tools/netmon/run.sh       every number in this file
```
