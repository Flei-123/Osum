# NETVIEW -- one network per process

Round NETVIEW, branch `netview`. This document is the design; the
numbers are in [Measurements](#measurements) and every one of them comes
out of `tools/netview/run.sh`.

## 1. The problem, stated exactly

A great many programs refuse to work without a network although they
would work perfectly well without one. A game that runs entirely on the
device shows "no connection" and stops. A note-taking program will not
open a local file until it has reached its server. What these programs
want the network for is almost never what the person in front of the
screen asked for: it is an advertisement to fetch, a start to report, a
licence to check.

There are two obvious answers and both are bad.

**Let it through.** Then the person pays for the traffic, waits for it,
and is counted by it.

**Block it.** Then the program sees `ECONNREFUSED` or, worse, waits for
its own timeout, and shows the error box. Blocking a program that
insists on a network does not give you the program without a network. It
gives you no program.

The third answer is the one built here: **give the program a network
that looks normal and leads nowhere.** The connection succeeds. The
reachability check succeeds. The download is empty.

## 2. Why this is cheap in Osum and expensive elsewhere

Osum carries its own TCP/IP stack in the kernel -- `kernel/inet.fi`
(1182 lines) over the stack of round K3, `kernel/virtio.fi` (925 lines)
under it, and the socket calls in `kernel/sys.fi`. Every octet a process
wants to put on a wire passes through code this repository wrote.

That is why a per-process network here is **a field in the task record
and a question asked at one door**. `sched.T_NETV`, one word, and
`netview.decide` in `kernel/netview.fi`. There is no virtual device, no
second protocol stack, no packet filter and no namespace.

Compare:

**Android** has no per-application network view in the kernel it can
reach, so the applications that do this (the ad blockers, the "no
internet for this app" tools) register themselves as a **VPN**. The
system routes the device's traffic into a fake VPN, the tool reassembles
the IP packets in Java, decides per application, and either forwards or
drops. The costs are visible: only ONE VPN may be active at a time, so
the tool and an actual VPN are mutually exclusive; there is a permanent
key icon in the status bar; and every packet is copied into user space
and back. Android does have `INTERNET` as a permission, but it is
all-or-nothing and it is decided at install time, not by the person
later.

**Linux** can do it properly and it takes three mechanisms.
`unshare -n` gives the process a **network namespace**, which is a
second, empty network stack; then a `veth` pair, an address, a route and
usually a NAT rule are needed to give it anything at all; then
`nftables` or `iptables` per namespace to decide where it may go.
Alternatively `cgroup/skb` eBPF programs, or per-socket marks with
`SO_MARK` plus policy routing. All of them work. None of them is one
field, all of them need root to set up, and none of them ANSWERS the
program -- they drop, reject or reroute. Making the connection succeed
and return `204 No Content` means running a small HTTP server inside the
namespace and pointing DNS at it.

**Windows** effectively cannot. The Windows Filtering Platform filters
per application, but it filters -- permit or block. There is no
supported way to make one application see a different, working, fake
network while another sees the real one; what exists in practice are
kernel-mode filter drivers from third parties, and a kernel-mode driver
is a much larger thing to trust than a field.

So: the reason this round is 700 lines of kernel and not a subsystem is
that the kernel already owns the stack. That is the argument for writing
your own, and it is worth stating plainly because it is rarely this
concrete.

## 3. The four views

The numbers are ordered **by how much they allow**, and one rule rests
on that order (§6).

| n | name | what the program sees |
|---|------|----------------------|
| 0 | `real` | the wire. What every process got before this round, and the default. |
| 1 | `filtered` | a list of up to six destinations is reachable for real; everything else is answered as in `faked`. |
| 2 | `faked` | an address, a gateway, a name server and connections that succeed -- and nothing behind any of them. |
| 3 | `none` | no network. Every attempt fails at once with `-ENETUNREACH`, as a machine with the cable pulled fails. |

### 3.1 How a faked connection ends -- the decision of the round

Three answers were possible. Two of them are wrong, and it is worth
writing down why, because the wrong ones are what a firewall does.

**Refuse (RST at once).** Honest, fast, useless. The program sees
`ECONNREFUSED`, concludes it is offline, and shows the error box this
round exists to avoid.

**Swallow (accept the SYN, never answer).** The worst of the three, and
exactly what a naive "drop the packets" rule produces. The program hangs
in `connect` until its own timeout expires -- thirty seconds, sixty,
sometimes forever. **Offline would have been better.** A view whose
purpose is to keep a program working may not make it hang.

**Accept and end it (what is built).** The connection succeeds
IMMEDIATELY, inside the same system call, with no wire and no waiting.
What the program writes is taken and dropped. What it reads is a
defined, short answer and then an ordinary end of stream. The program's
own "the server said nothing useful" path runs -- which is a path it has
been tested on -- and it runs in microseconds.

Measured: a faked `connect` took **435 us** and the whole
socket-connect-send-read-close exchange **3 840 us**. The real one over
the veth in the same boot took **11 233 us** for the connect alone.

### 3.2 And one answer is not empty

Very many programs decide whether they are online by fetching one URL
and looking at the status. Android asks a server for a **204**, Windows
for a short text file, GNOME for a fixed body. So if what the program
wrote looks like an HTTP request -- `GET `, `POST`, `HEAD`, `PUT ` --
what it reads back is:

```
HTTP/1.1 204 No Content
Server: osum-netview
Content-Length: 0
Connection: close

```

87 octets of header, **zero octets of body**. The reachability check
SUCCEEDS and the download stays EMPTY. That is the entire point of the
round in one exchange.

204 and not 200: a `200 OK` with an empty body is a page that failed to
load, and a client will retry it. `204 No Content` MEANS "there is
nothing here, and that is the answer".

### 3.3 Names resolve

A program that fails at `getaddrinfo` never reaches the interesting
code. So a datagram to port 53 is answered, built out of the question
that was asked: same identifier, same question section, `QR=1`, `RA=1`,
`RCODE=0`, and one A record with a TTL of 60 seconds. A question that is
not an A record is answered `NOERROR` with no records, so the resolver
stops instead of retrying.

Every address invented in this round comes out of **TEST-NET-2,
198.51.100.0/24 (RFC 5737)**, which the registry reserves for
documentation and guarantees is never routed:

| | |
|---|---|
| address of the machine | 198.51.100.2 |
| netmask | 255.255.255.0 |
| gateway | 198.51.100.1 |
| name server | 198.51.100.53 |
| what every name resolves to | 198.51.100.80 |
| hardware address | 02:00:56:45:00:02 (locally administered) |

An address this kernel makes up therefore cannot collide with a machine
that exists. The hardware address is invented as well and on purpose:
the real one identifies the machine, and this round is about not leaking
such numbers.

### 3.4 What `faked` does with the rest of the socket interface

* `bind` and `listen` succeed and touch the stack not at all. The port
  exists only in the program's imagination.
* `accept` returns `-EAGAIN` **at once**, not after thirty seconds of
  sleeping. Nobody will ever connect, because there is no wire.
* `getsockname` reports 198.51.100.2, `getpeername` the address the
  program connected to.
* `shutdown` returns 0. `-ENOTCONN` would be the one place an otherwise
  clean run suddenly reported that something was wrong.
* A UDP `recvfrom` with nothing queued returns `-EAGAIN` immediately.
* An ICMP echo request turns into an echo reply, so `ping` in a faked
  process answers itself.
* Reading the network configuration (`SYS_OSUM_NETGET`) returns the
  invented numbers. Otherwise the program could find out through that
  call that it was being deceived, and the deception would be
  transparent at its own information desk.

## 4. Not one octet leaves

A faked socket never calls a function of `inet.fi` or of the vendored
stack, and those two are the only things in this kernel that can hand a
frame to `virtio.tx_frame`. The claim is not this sentence. The kernel
prints its own driver's octet counter at the end of every run as
`nv: wire_o=`, and `tools/netview/run.sh` boots the same image twice
with no wire attached at all, differing in one word on one command line:

```
faked   nv: dropped=116   nv: opened=2   nv: wire_o=0
real    nv: dropped=0     nv: opened=0   nv: wire_o=546
```

116 octets were offered by the program and thrown away; 0 octets left
the machine. The control run, same image, same absent wire, put 546 on
the card.

## 5. Where the state lives

**In the task record and nowhere else.** `sched.T_NETV` at offset 448
holds the view; `sched.T_NETOK`, six words at 456..503, holds the allow
list of the `filtered` view. The record has been 512 octets since round
K4 and was filled to `T_UMASK` (440); 504 is still empty.

There is no second table. `netview.view_of(state, task)` reads that word
on every call and never copies it. A view changed while a program is
running is therefore in force for the next call, not "the next time it
starts".

One thing does live beside it, and it is a different thing: per SOCKET,
`kernel/netview.fi` keeps whether THIS connection was faked, what it was
aimed at, and how far the canned answer has been handed out (16 records
of 64 octets in `pci.K2_SCALARS`, plus 256 octets of answer each). A
process can hold four sockets and they need four read positions; that
cannot live in the process. It is not a copy of the view.

### 5.1 Inheritance

| | |
|---|---|
| `fork` | the child gets the view and the allow list (`sys.do_fork`). |
| `execve` | nothing to do -- the same task record survives, so the view does. This is what makes `netview faked <program>` work. |
| `exec`, `spawn`, `fopen` (Osum's own three, which build a NEW task) | the view is copied from the caller. Without those three lines, `exec` would be the way out of every view. |
| a fresh task | `sched.create` zeroes the record, and 0 is `real`. Everything that existed before this round goes on seeing exactly what it saw. |

### 5.2 Where it is set FROM

Two places, in this order, and the order is written once, in
`appdir.view_for`:

1. **The person.** `/users/<name>/config/netview`, one line per bundle:

   ```
   # what which program may see
   explorer faked
   browser  filtered
   ```

   This wins. A system that lets a package overrule its user is a system
   that works for the package.
2. **The package.** `net=real|filtered|faked|none` in
   `/apps/<name>.prog/INFO`. The author of the program saying what it
   needs: a reasonable default and never more.
3. Neither, and it is `real`.

Neither file is a second copy of the running state. What is read there
is handed to `/bin/netview`, which tightens ITSELF and then starts the
program -- so there is exactly one mechanism for putting a view on a
program, and the launcher, the file manager and the shell all use it.

## 6. Who may change what

`netview.may_set` carries the whole rule and it is sixteen lines:

* **Tightening your own view is always allowed** and needs no privilege.
  This is the one that matters: it is how `/bin/netview` works for an
  ordinary user, and how a launcher drops its own network between `fork`
  and `execve`.
* **Everything else needs euid 0** -- loosening your own view, and
  touching another process at all, in either direction.

The second half is the guarantee, not caution. If a process could loosen
its own view, the faked program would set itself back to `real` in one
call. If it could touch a process with the same user, it would set a
SIBLING to `real` and have the sibling fetch. Both are escapes and one
line closes both.

**Reading is allowed for anybody about anybody.** That is a decision
(§7), and it is why `ps` and the taskbar, which do not run as root, can
tell the truth.

## 7. The principle: the PROGRAM is deceived, never the person

A system that lies to its own user is exactly as bad as one that spies
on him. What this round builds is a deception, and a deception that the
person cannot see through is a deception aimed at the person.

So:

* `ps` has a **NET** column with the view of every process.
* The **taskbar** puts a mark in front of the window title: `~` for
  `faked`, `+` for `filtered`, `x` for `none`. One character and a
  space, because a taskbar button is narrow and a word is the first
  thing the shortening throws away -- which would mean the mark
  disappears exactly when there are many windows.
* The **settings** application has a page "Netzzugriff" listing every
  running process with its view, changeable there.
* The **file manager** has a context menu entry "Netzzugriff" with the
  four views, which starts the selected program under the chosen one.
* `SYS_OSUM_NETVGET` is readable by anybody, about anybody, without
  privilege.
* `/bin/netview` with no arguments prints the whole table.

None of that is decoration. A faked network with no visible mark would
be a rootkit with good intentions.

## 8. Using it

```
netview                                     every process and its view
netview show [pid]                          one of them
netview stats                               the kernel's four counters
netview set <pid> <view>                    change a running process
netview [-a <target>]... <view> <cmd> ...   run a command with a view
```

`<view>` is `real`, `filtered`, `faked` or `none`; `<target>` is
`a.b.c.d[/prefix][:port]`.

```
netview faked /bin/wget http://10.9.0.1:8000/x
netview -a 10.9.0.1:8000 filtered /bin/nvcheck x 10.9.0.1 8000
```

The system calls are 1310 (`NETVGET`), 1311 (`NETVSET`) and 1312
(`NETVALLOW`), in the block round K8 reserved for the network. They are
in `kernel/sys.fi`, `lib/libc/kcall.fi` and `kernel/user/ulib.fi`, and
`tools/posix/run.sh` compares all three tables name by name.

## 9. Measurements

`bash tools/netview/run.sh` -- **53 passed, 0 failed**. The wire is the
one round K8 built: QEMU's virtio-net over a UDP socket to
`tools/net/bruecke.c`, from there over `AF_PACKET` onto a `veth` pair
into a network namespace with the Linux kernel and a python HTTP server
on the other end. Nothing talks to itself.

### 9.1 The four views, in ONE boot, against that server

| | `real` | `none` | `faked` | `filtered` (on list) | `filtered` (not on list) |
|---|---|---|---|---|---|
| view reported | 0 | 3 | 2 | 1 | 1 |
| network reports itself up | 1 | 0 | 1 | 1 | 1 |
| address the process believes | 10.9.0.2 | -- | 198.51.100.2 | 10.9.0.2 | 10.9.0.2 |
| `connect` | 0 | `-ENETUNREACH` | 0 | 0 | 0 |
| HTTP status | 200 | -- | **204** | 200 | **204** |
| octets of body | 46 | 0 | **0** | 46 | **0** |
| octets in total | 184 | 0 | 87 | 184 | 87 |
| a name resolved to | -- | -- | 198.51.100.80 | -- | -- |

### 9.2 The times, in microseconds, same boot

| | us |
|---|---|
| `real` connect over the veth | 11 233 |
| `none` connect (the failure) | 322 |
| `faked` connect | 435 |
| `faked` reading the answer | 925 |
| `faked` whole exchange | 3 840 |

`faked` is **26 times faster than the real connect** and never
approaches a timeout. That is the number the design in §3.1 was chosen
for.

### 9.3 Octets on the wire

| run | dropped | opened | **wire_o** |
|---|---|---|---|
| `faked`, no wire attached | 116 | 2 | **0** |
| `real`, no wire attached | 0 | 0 | **546** |

Same image, same absent wire, one word different on the command line.

### 9.4 Two processes, two views, at the same time

The actual claim of the round. One faked and one real program, started
in the same shell against the same server:

| | faked | real |
|---|---|---|
| view | 2 | 0 |
| HTTP status | 204 (from the kernel) | 200 (from python) |
| octets of body | 0 | 46 |

and the python server, **which counts its requests, saw exactly one of
the two**.

### 9.5 Nothing else moved

`real` is the default and every existing suite runs against the changed
kernel:

| suite | before | after |
|---|---|---|
| `tools/net/run.sh` | 75 passed, 0 failed | 75 passed, 0 failed |
| `tools/posix/run.sh` | 133 passed, 1 failed | 133 passed, 1 failed |
| `tools/unix/run.sh` | 107 passed, 0 failed | 107 passed, 0 failed |
| `tools/userland/run.sh` | 91 passed, 0 failed | 91 passed, 0 failed |

The one failure in `tools/posix/run.sh` is **older than this round**: two
system call numbers on which `kernel/sys.fi` and `lib/libc/kcall.fi`
disagree. It was there before the branch and is not touched by it. The
three numbers this round adds were entered in all three tables, which is
why the count is 2 and not 5.

`tools/userland/run.sh` measures the size of the userland against the
2 097 152 octets of the drive, and that measurement caught a real
mistake in this round: the four ring-3 helper functions first stood in
`kernel/user/ulib.fi`, which all twenty-eight programs link, and the
userland grew from 1 991 728 to 2 097 416 octets -- **over the drive**.
They are in `kernel/user/nv.fi` now, and the only program of those
twenty-eight that this round touches is `ps`.

That is not free either, and the number is worth writing down because it
is uncomfortable: the NET column costs `ps` **4 296 octets** in firnc1
(63 888 -> 68 184) for about ten lines of source. The userland now
totals **1 996 080** octets against a limit of 1 997 152 -- **1 072
octets of room left**. Anything the next round adds to a program on that
drive will hit the limit before it hits anything else, and the honest
reading is that the drive wants to grow, not that this round should have
left the column out.

Two runs of `tools/net/run.sh` on this branch failed one assertion each
in section 9 (`tc netem`, 20 % loss inbound and 10 % outbound), and they
failed DIFFERENT assertions. The measuring machine was carrying a load
average of 13 with a dozen other suites of this repository running at the
same time, and the runner's own comment warns that this case walks into
the thirty-second stall guard of `netsvc.connect_service` when it is
starved. A third run under the same load passed all 75. Neither of those
two cases goes through `kernel/sys.fi` at all -- `nsvc=1` and `nsvc=4`
are kernel-side services and never touch a socket call -- so this round
cannot be what moved them. It is written down rather than left out.

## 10. What does not work, plainly

* **TLS.** A faked answer on port 443 is impossible. The client would
  have to verify a certificate for a name, and forging one means being a
  certificate authority it trusts. A faked TLS connection therefore gets
  an immediate, clean end of stream and the program sees "the server
  hung up" -- which is still better than a hang, and still not a real
  answer. Any program that only speaks HTTPS gets nothing useful out of
  `faked` beyond not hanging.
* **The canned answer is 256 octets per socket.** Enough for a 204 and
  for a DNS answer; not a place to put a fake page.
* **`faked` looks at the first 256 octets of what a program sends.**
  The rest is counted and dropped without being examined. A program that
  puts its HTTP request line 300 octets in gets an empty stream rather
  than a 204.
* **One view per process, not per socket.** A program that wants the
  real network for one connection and a faked one for another is asking
  for a policy engine. This is a field.
* **Six entries in the allow list.** It is meant for "the one service
  this program really needs". A list long enough to be a firewall rule
  set would be a firewall, in a task record.
* **`filtered` filters DESTINATIONS, not content.** An allowed
  destination is the real network, with everything that means.
* **The allow list holds addresses, not names.** Osum has no resolver,
  so there is nothing to resolve a name in a rule with. A rule for a
  service behind a rotating set of addresses cannot be written.
* **`bind`/`listen` in `faked` and `none` accept and then never
  deliver.** A program that waits for an incoming connection waits for
  ever. It does not hang in a system call -- `accept` returns `-EAGAIN`
  at once -- but its own loop will not end. Nothing was found that does
  this in practice, and it is named here rather than hidden.
* **Changing the view of a running process needs root.** The settings
  page therefore reports `-EPERM` as a sentence when an ordinary user
  tries it. Writing the CONFIGURATION, which takes effect at the next
  start, needs no privilege.
* **A second `netview` inside a faked process cannot loosen it**, which
  is correct, but it also means a wrapper cannot hand a helper program
  the real network. That is the price of the rule in §6 and it is the
  right price.

## 11. The two displays (addendum)

Windows puts one icon in the corner: a globe with no connection, a
monitor with a cable for LAN, bars for wifi. That icon describes **the
machine**. Here the network is a property of a **process**, and one icon
cannot say that: this machine can be genuinely online while three
programs see a faked network, one sees none and two see the real one. A
single symbol would have to be wrong about five of them.

So there are **two** displays and they answer two different questions.

### 11.1 The corner: what the machine really has

Four states, worked out in the kernel (`sys.NG_STATE`) so that the
taskbar does not ask three questions and draw its own conclusion:

| n | state | when | icon |
|---|-------|------|------|
| 0 | no carrier | no card, or the link bit is down | the screen, with a slash right across the whole icon |
| 1 | no address | link up, no IP yet (DHCP still running) | an empty screen with three dots on it |
| 2 | no route | IP set, the gateway never answered ARP | a warning triangle in the corner, bang cut out |
| 3 | online | IP set and the gateway answered | the screen, filled |

`no route` is Windows' "connected, no internet", one hop earlier: this
kernel cannot know whether the far side of the world answers, but it
knows whether the **first hop** ever did. That is `inet.gw_known`, it
costs no probing traffic of its own, and the limit is written down
rather than dressed up.

**Wired only, and no wifi icon.** There is not one line of 802.11 in
this tree. An icon for a carrier that does not exist would be, in a
round about not lying to the user, the worst possible shortcut. When
wifi arrives, a number is added here.

While the pointer rests on the corner, the sentence and the three
numbers appear in the free space of the bar: *"Verbunden ueber Kabel
10.9.0.2 Maske 255.255.255.0 gw 10.9.0.1"*.

### 11.2 The button and the title bar: what THIS program sees

A mark, on the taskbar button **and** in the window's own title bar --
the second one because a window is visible when the bar is covered,
moved or hidden.

| view | mark | why that shape |
|------|------|----------------|
| `real` | **none** | the normal case gets no sign. A mark on every window is a screen full of marks that say nothing, and the one that means something drowns in it. |
| `filtered` | a ring with a **funnel** | it lets some through and holds the rest |
| `faked` | a ring with a **wave** | the shape of a signal that is drawn and not received |
| `none` | a ring with a **slash** | what a crossed-out thing has looked like for a century |

All three are a ring, so that somebody who has seen one knows the next
one is about the same thing. Hovering gives the sentence: *"Netzzugriff:
vorgetaeuscht -- dieses Programm erreicht nichts von draussen"*.

### 11.3 The rules the drawings are held to, and the numbers

**Drawn at the size they are shown at.** 16x16 for the corner, 12x12 for
the mark on a 22-pixel button. An icon designed at 24 and squeezed to 16
loses exactly the pixel it was recognisable by, so nothing here was
designed larger.

**Colours are roles, not values.** OSYM stores four octets per pixel and
the fourth is coverage; 0 has always meant transparent and 255 "these
three octets are the colour". This round uses **1 to 5** to mean *ask
the scheme*: ink, dim, accent, warn, panel
(`tools/k15/symbol.py`, `wlibc.icon_draw`). One file is therefore right
in a light scheme and in a dark one, and every symbol that existed
before this addendum carries 0 and 255 and does not change by one octet.

**Contrast**, computed out of the two scheme files that the measured
runs actually boot with, against the panel the icon lies on:

| role | dark | light |
|------|------|-------|
| ink | 10.85:1 | 14.14:1 |
| dim | 4.53:1 | 4.97:1 |
| accent | 6.33:1 | 5.59:1 |
| warn | 7.74:1 | 4.90:1 |

All eight over the 4.5:1 WCAG asks for small elements. `dim` in the dark
scheme is the tightest at 4.53:1, and it is only ever used for a whole
badge or a slash -- never for a one-pixel line.

**Form carries the difference, not colour.** Somebody who cannot tell
the accent from the warning colour still has to tell the icons apart, so
every drawing is flattened to a silhouette -- every colour to one -- and
the silhouettes are compared. Of every pixel either shape inks, this
many are inked by only one of them:

| | vs | | |
|---|---|---|---|
| nocarrier | noip | 32 of 73 | **43 %** |
| nocarrier | noroute | 50 of 90 | 55 % |
| nocarrier | online | 52 of 98 | 53 % |
| noip | noroute | 36 of 78 | 46 % |
| noip | online | 30 of 82 | **36 %** |
| noroute | online | 66 of 108 | 61 % |
| filtered | faked | 25 of 64 | **39 %** |
| filtered | none | 26 of 66 | 39 % |
| faked | none | 27 of 64 | 42 % |

The threshold is a third, and it caught two real mistakes. The first
pair of state icons differed **0 pixels** in silhouette -- both were a
filled round badge and only the colour inside differed, which is exactly
the mistake this section tells other people not to make. The second
attempt cut the sign out of the badge as a hole and got to 19 %, still
two corner badges of the same size. Only the third -- a warning triangle
against three dots inside the screen -- passed.

### 11.4 One drawing, two renderers

The same mark is drawn in two places that have nothing to do with each
other: the taskbar (ring 3, reads an OSYM file off the disk) and the
window server (the kernel, in the middle of painting a window, with no
file system). Writing the twelve rows twice is how two signs for one
thing appear a month later, so the **drawing is the source**:

```
assets/netview/mark-*.txt
      |
      +-- tools/netview/icons.py bauen  -> /etc/netview/mark-*   (OSYM)
      +-- tools/netview/icons.py kern   -> kernel/netmark.fi     (bit rows)
```

and `tools/netview/run.sh` regenerates `kernel/netmark.fi` on every run
and fails if it differs from the file in the tree by one octet.

**The title-bar mark is one colour.** The window server on this branch
has no colour roles -- round THEME is giving it some (`WM_DECO`) -- so
the mark is drawn in the colour the title text already has. That costs
nothing, because the three shapes are distinguishable by form alone and
the number above proves it. When THEME lands, one expression changes.

### 11.5 What was measured, on a real screen

`bash tools/netview/run.sh`, sections 5 and 6. Every coordinate is read
out of what the taskbar **reported** on the serial line and then checked
in the **picture** at that coordinate, pixel by pixel, with the role
colours resolved against the scheme the run booted with
(`tools/netview/schau.py`). A bar that reported one thing and drew
another fails here.

| | |
|---|---|
| four boots, four states of the machine | every icon pixel-perfect at the reported place: 62, 52, 68 and 82 opaque pixels, none wrong |
| one boot, FOUR programs in FOUR views | `filtered` 54 of 54, `faked` 49 of 49, `none` 52 of 52 -- and the `real` button checked for **absence**: 49 of 49 pixels differ from a mark |
| the same again in the light scheme | identical, out of the same seven files |
| the bar found its pictures | `taskbar: icons=4 marks=3` |
| the whole run | **86 passed, 0 failed** |
| round DESKTOP's own run against the changed taskbar | 0 failed (the one flake it does have is older than this branch) |

The screenshots are in `docs/shots/netview/`: `state-*.png` (the four
corner states), `four-views-dark.png` and `four-views-light.png` (four
programs, four marks, one bar), and `icons-sheet.png` (all seven signs
1:1 and magnified, in both schemes).

**Three faults this measurement found, and they are the reason it
exists.**

1. *The offset.* The bar reports coordinates inside its own window and
   the picture is the whole screen. The first run measured the icon
   against the wrong 62 pixels. Worse, the second version read the
   offset out of a serial line that a **second program had written into
   the middle of**, got nothing, quietly used zero, and reported `falsch
   54 von 54` about an icon that was perfect. The runner now matches
   that line end to end and says so when there is none, instead of
   assuming a zero.
2. *The icon had no room.* It was drawn in front of the address and the
   status field kept the width it had, so the address ran out of its own
   rectangle into the battery beside it. `tools/desktop/run.sh` -- round
   DESKTOP's own acceptance run, not this one -- said the rectangles
   were wrong after a restart, and it was right. The icon takes its room
   off the text's share now.
3. *The extra reporting was noise.* Three ring 3 programs share one
   serial line. Printing `netv=0` for every window of every repaint made
   two of them write into each other's words often enough to break a
   claim in another suite. The bar reports the netview fields only when
   there is something to report, and the machine state only when it
   changes.

One failure in `tools/desktop/run.sh` is **not** this round's:
`settings: rect name=edge is missing` is the same serial splicing, and
it was reproduced on the unchanged `taskbar-edge` commit this branch
starts from -- one failure there, the same one. It is written down here
rather than left for somebody else to find.

### 11.6 What the addendum does not do

* **No wifi icon**, see above.
* **`no route` is one hop, not the internet.** A gateway that answers
  ARP and drops everything after it reads as `online` here. Probing
  further would mean sending traffic nobody asked for, which is the
  opposite of what this round is about.
* **The hover sentence is drawn in the bar, not in a window of its own.**
  There is no tooltip layer in this system and a bar 28 pixels high
  cannot open one. On a **vertical** bar there is no free space for it at
  all, and there it is left out rather than crammed in.
* **The title-bar mark is one colour** until round THEME lands.
* **The corner icon has no click.** Windows opens a network panel from
  it; there is nothing here to open yet.

## 13. The systemwide fallback (second addendum)

Setting every program by hand is work, and the moment it is needed is
the moment there is least patience for it: the machine has no network,
and half a dozen programs are refusing to start over it. So there is
**one systemwide preference**, and it decides what a program gets **when
nothing else was said about it**.

| value | what it does |
|---|---|
| `off` | Nothing is faked. What this system did before this addendum, and the default. |
| `when-offline` | While there is no way out, a program nobody configured starts in `faked`. The moment there is a way out again, the next program to start gets `real`. |
| `always` | Everything faked, network or not -- for shutting the machine up on purpose. |

`off` answers **`real`** and not `none`, and that is a decision rather
than an oversight. A machine with no network already fails every
connection; answering `none` on top of that would be a second way of
being offline, with its own error number, handed to programs that never
asked for one. The default of a system has to be the behaviour that
system had.

### 13.1 Precedence -- the table

Three places can say what network a program sees. They are ordered, the
order lives in one function (`appdir.view_for`), and the rule in one
line is: **an explicit setting on a program always beats the
preference.**

| `/users/<name>/config/netview` | `net=` in the bundle's `INFO` | preference | the program gets |
|---|---|---|---|
| `faked` | anything | anything | **faked** |
| `real` | anything | `always` | **real** |
| `none` | anything | `always` | **none** |
| -- | `filtered` | anything | **filtered** |
| -- | `real` | `always` | **real** |
| -- | -- | `off` | **real** |
| -- | -- | `when-offline`, no way out | **faked** |
| -- | -- | `when-offline`, online | **real** |
| -- | -- | `always` | **faked** |

Read the two rows that matter: a program the person put on `real` is not
quietly forced into `faked`, and a program put on `none` stays without a
network even while the preference is inventing one for everybody else.
**The preference fills a blank; it does not overrule an answer.** A
default that can overrule is not a default, it is a policy engine, and
this system already has a place for saying "this program, this network"
-- twice.

### 13.2 A running program is never switched

When the real network comes back, what happens to the program that is
running in `faked`?

**Nothing.** It keeps the view it started with. The alternative was
considered and rejected: a view that changes under a program's feet
changes it *in the middle of a connection*. A socket that was faked a
moment ago and is real now has a read position into a canned answer that
no longer exists, and the program on the other end of that gets a
failure that depends on when the gateway happened to answer an ARP. That
is the kind of fault that is rare, unreproducible and takes a week to
find, and it would be bought for a convenience nobody asked for.

So: **new programs get the new view, running ones keep theirs, and the
mark on the window says which is which.** That last clause is what makes
the rule liveable rather than confusing -- the person can see, per
window, that this one is still faked and that one is not.

This falls out of where the preference is applied rather than being
enforced somewhere: it is read once, when a program is started, and
written into the task record. There is no code that could change a
running process's view, so there is no code that has to be trusted not
to.

### 13.3 Where it is applied, and the price of that

Not in the kernel at `exec`. That was the first design and it collapses
on the launcher, which is worth writing down because it looks like the
obvious answer.

The launcher is the thing that puts an explicit view on a program, and
it does it by **tightening itself and then starting the program**
(section 6). If the kernel had already forced the launcher into `faked`,
the launcher could never start anything as `real` again -- because
`netview.may_set` refuses every loosening, on purpose, and loosening it
for this one case would re-open exactly the escape section 6 closed: a
faked program handing itself the wire back in one call.

So the preference is resolved where the other two sources already are:
at the door a program is started through, in `appdir.view_for`. That
covers everything started from the desktop -- the launcher, the file
manager, the desktop icons.

**The price, stated plainly:** a program started from a **shell** keeps
`real`. A shell is somebody saying exactly what to run, and
`netview default <cmd>` is that same sentence spelled out; it asks the
kernel the identical question and applies the identical answer. It is a
real limit, not a hidden one, and it is where the acceptance measures
the preference from.

### 13.4 `when-offline` is pessimistic on a silent machine

`when-offline` asks whether there is a **way out**, and that is measured
as "has the first hop ever answered" (`netview.link_state`, `NS_NOROUTE`
against `NS_ONLINE`). A machine that has just booted with a static
address and has not spoken to anybody yet honestly does not know, so it
answers "no way out" and fakes.

On a normal machine this never shows: the DHCP client has already
exchanged packets with the gateway before the first program starts, and
the address cache is filled. On a static-address machine with no traffic
it does show, and the alternative would be for the system to send probe
traffic of its own the way Windows' connectivity check does -- traffic
nobody asked for, from a round about not sending traffic nobody asked
for. So it is a limit, and it is written here instead of behind a probe.

### 13.5 The corner sign

Windows' corner icon describes the **machine**. Here the preference is a
statement about the machine too -- but a different one from the four
states, and the two can disagree in the direction that matters most:

> the machine is genuinely **online**, and every new program is
> nevertheless getting a **faked** network.

One icon cannot say both, so there are two signs beside each other, and
the faking sign comes **first**. What is read first is what is read at
all, and "this system is telling programs a story" is the more important
of the two sentences -- especially in exactly that case, where the state
icon on its own would be true and misleading at the same time.

The sign appears **only while the system is actually faking**
(`netview.faking`): `off` shows nothing, and `when-offline` on a machine
that is online shows nothing either. The normal case gets no sign, the
same rule the window marks follow, and for the same reason.

**The grammar of the round, and it is carried by the frame and not by
the colour:**

| shape | scope |
|---|---|
| a **ring** | one program (`mark-filtered`, `mark-faked`, `mark-none`) |
| a **screen** | the whole machine (the four state icons, and `sys-faking`) |

`sys-faking` is a screen containing the **same wave** that is inside
`mark-faked` -- it is the same lie, told at a different scope. Somebody
who cannot tell one colour from another still sees a ring in one place
and a box in the other; measured, the two silhouettes differ in 79% of
the pixels either of them colours.

Resting the pointer on the corner adds the sentence:

> `Das System taeuscht neuen Programmen ein Netz vor (Voreinstellung: immer)`

A sign nobody can look up is not honesty, it is decoration.

### 13.6 Where the preference lives

| | |
|---|---|
| running value | `netview.fallback`, one word in `pci.K2_SCALARS`. One place. |
| at boot | `nvfall=0\|1\|2` on the kernel command line (`hw.net_fallback`), applied by `kmain` in one line. |
| at run time | `SYS_OSUM_NETVFB` (1313), **euid 0 only** -- it is the one setting of this round that touches every process. |
| readable by | `NETVGET` with `NV_FALLBACK` / `NV_FBVIEW` / `NV_LINK` -- anybody, about the machine. |
| across reboots | `/etc/netview.conf`, one line `fallback=<word>`. Written by `netview fallback <word>` and by the settings page; read back by `netview boot`, which belongs in `/etc/inittab` as a `once` line. |

The kernel does not read files while it boots and this addendum is not
the round to teach it to, so persistence is a program that runs early
rather than a line in `kmain`. The **seam** that costs something: the
shape of that one line is written out in two places, `kernel/user/netview.fi`
and `kernel/user/einstellungen.fi`, because the settings application does
not fetch a second program to save a setting. It is named here rather
than hidden.

Does `NV_FALLBACK` leak the deception to a faked program? It tells it
that the system is faking -- but `netview show` has told any process its
own view since the main round (section 7), on purpose, because a view
the person cannot read is the lie this system will not tell. The
deception lives at the **socket**, not at the information desk.

### 13.7 Using it

```
netview fallback                     what it is, and what that amounts to now
netview fallback when-offline        set it, and write /etc/netview.conf
netview boot                         apply /etc/netview.conf   (for /etc/inittab)
netview default /bin/wget http://... start a program the way the launcher would
```

`default` is **not a fifth view**. It is the question the launcher asks
for every program nobody configured, asked out loud, and it is resolved
once before the command starts -- resolving it later would mean a
program whose view depends on when it got round to opening a socket.

In the settings application it is on the **same page** as the list of
programs, **below** the list: it is the weakest of the three sources,
and the page reads in the order the system decides.

### 13.8 Measured

Same image, same script, same wire -- **one word different on the kernel
command line**. If a program fails in one run and works in the other,
that difference has exactly one cause.

| | |
|---|---|
| 8a: no card at all, `nvfall=0` | link 0, preference 0, view `real`, **connect fails**, body 0 |
| 8b: the same, `nvfall=1` | link 0, preference 1, view `faked`, **connect succeeds**, 204, body 0 |
| 8b: octets on the wire | **0** |
| 8c: `always` + real wire, no setting | `faked`, 204 |
| 8c: `always` + **explicit `real`** | `real`, **200**, 46 octets of real page |
| 8c: `always` + **explicit `none`** | `none`, `-ENETUNREACH`, not a faked 204 |
| 8d: `when-offline` + online | view `real`, 200, the real page |
| 8e: preference changed mid-boot | every running process keeps its view; the next program to start is `faked` |
| 8f: reboot | second boot told nothing, comes up `always` out of `/etc/netview.conf` |

### 13.9 What this addendum does not do

* **It does not catch a program started from a shell.** Section 13.3.
* **It does not switch a running program.** Section 13.2 -- deliberate.
* **`when-offline` cannot tell "no route" from "has not asked yet".**
  Section 13.4.
* **There is no per-user preference.** It is one number for the machine.
  A second one per user would need the resolution to know which user is
  starting the program before the program starts, and
  `/users/<name>/config/netview` already answers that question one row
  higher in the table.
* **The corner sign still has no click.** Neither does the state icon
  beside it.

## 14. The switch and the quick settings (third addendum)

### 14.1 The correction, first

Justin's ruling, and it takes precedence over everything in section 13:

> `when-offline` shall **not** be the default and shall **not** engage by
> itself. The switch is a plain on/off for "fake a network", at system
> level, and a person flips it on purpose.

Two things follow, and one of them is a change of substance while the
other is only a change of shape.

**The default did not move, and that is measured rather than promised.**
`off` was already the default and still is. Section 9e of the acceptance
boots a machine that was told nothing anywhere -- no `nvfall=` on the
kernel command line, no `/etc/netview.conf` in the image -- and reads
`nv: fallb=0`, `nv: fbview=0`, and a program that came up `real`. A
default that is only asserted in a comment is not a default; this one
comes off a boot.

**The control became binary, and that is the substance.** The second
addendum offered three values as though they were equal, and they are
not:

| | |
|---|---|
| **the switch** | two positions, `off` and `always`. This is what the tile toggles, what `netview fallback on\|off` sets, and what a person means by "fake a network". One question, one answer. |
| **`when-offline`** | a third value that has to be picked out of a list on purpose: `netview fallback when-offline`, or the drop-down on the settings page. Nothing reaches it without somebody typing or choosing the word. |

`on` is a fourth *spelling*, not a fourth value: it is accepted on the
way in and `always` is what gets written to `/etc/netview.conf`, so the
file keeps one spelling per value. Section 9f measures both halves --
`fallback=always` in the file, and the word `when-offline` appearing
nowhere in a run that only ever flipped the switch.

**Why `when-offline` was not deleted.** It is built, it is measured, and
there is a real case for it -- a laptop that is offline for an hour.
What was wrong was never the value. What was wrong was handing somebody
a *switch* whose meaning depends on what the cable is doing this second.
Naming a thing explicitly is a different act from flipping a switch, and
that difference is the whole of the correction.

**The precedence table of 13.1 is unchanged.** A setting on a program
still beats the system level, in both directions.

### 14.2 The quick settings

A small panel over the corner of the taskbar, the way `Win+A` opens one
on Windows. It exists because of one switch; the rule that got it built
is worth more than the panel:

> **Only what really exists and what is really switched often goes in
> here.** Four honest tiles beat twelve of which half do nothing. A tile
> for something this system does not have is not a placeholder. It is a
> lie with rounded corners.

So the interesting part of this section is the list of what is **not**
in it, and every line of it was checked against this tree rather than
assumed:

| left out | why |
|---|---|
| **Volume** | There is no sound. `grep -ri audio kernel/*.fi` finds `A_VOLUME` in the FAT driver and nothing else. A slider would move a number that reaches no speaker. |
| **Brightness** | Round DISPLAY has not delivered a gamma ramp on this branch. What does exist is `pwr.rescale`, which multiplies every pixel in the framebuffer **in place** and says so in its own comment. That is fine for `power hell 40` typed once; a slider is dragged across fifty values and every one of them throws away low bits the next one cannot get back. A slider over a lossy operation is worse than no slider. |
| **Light / dark** | The interface is not there. `/etc/theme` exists and is one file of colour *values*; the settings read a list of named schemes out of `/etc/schemas`, and **nothing in this tree creates that directory** -- no image builder writes it, so on a running machine it is empty. There is no mark anywhere saying which scheme is the light one. Round THEME is building exactly that, and a tile here would have had to invent their interface and then disagree with it. |
| **Do not disturb** | There are no notifications. Nothing to silence. |

What is left is three, and all three are switches a person really flips:

| tile | what it does |
|---|---|
| **Netz vortaeuschen** | the reason the panel was asked for. `off` ↔ `always`. |
| **Netz** | the machine's address, away and back. **This is not the same switch**: a faked program keeps believing in its invented network after the address is gone, and a real one genuinely loses everything. They sit next to each other because they are two different things, not two words for one. |
| **Leiste verbergen** | `/etc/taskbar.conf`, `autohide`. It belongs to the taskbar, and so does this panel. |

and a row that opens `/bin/einstellungen`, where the things that are
*not* flipped often live.

### 14.3 Where it appears

At the edge the bar is on, in the corner the icon group is in -- and the
rectangle it lays itself out in is the **work area** (`wlibc.work_*`,
the interface addendum TASKBAR built), never the screen. A panel that
assumed the screen would sit under the bar on three edges out of four.
The acceptance opens it on all four and checks that the reported
rectangle lies inside the reported work area, on all four.

It is the taskbar's own second window, created at start and kept hidden;
opening it is `WS_HIDDEN 0`, a move and a paint, not a program start.
That is not a detail -- it is why the thing can be timed in
microseconds at all.

It closes three ways, and all three are measured: **Escape** (it takes
the focus when it opens, so the key arrives), the **hotkey again**, and
a **press anywhere outside it**, which has to be polled from the pointer
because a press outside a window raises no event belonging to that
window.

### 14.4 The Super key did not arrive, and now it does

Asked, and answered honestly before anything was written: **no.** The
key comes in as `0xE0 0x5B` (left) or `0xE0 0x5C` (right). The prefix
set `KB_EXT`, the code after it fell through to `arrow()`, which has no
entry for `0x5B` and returns 0 -- so the key was dropped without a
trace. There was not one line in this tree that mentioned `0x5B`.

It is now a **modifier**, handled exactly like Shift and Control in the
same function: it produces no character, so it produces no `key: ` line,
and round K11's promise of exactly one such line per key holds
unchanged.

`Super` + a letter is **latched, not delivered**, and the "not
delivered" is the important half: a `Super+A` that also typed an `a`
into whatever window had the focus would leave a stray letter in the
person's document every single time they opened this panel. Section 9a
measures exactly that -- one `key: a` from a plain `a`, one
`hk: super+a` from the combination, and *still* only one `key: a`.

**Why a latch and not an event.** A hotkey has no window; that is what
makes it global. The window server hands a key to the window with the
focus (`wm.on_key`), and the taskbar is deliberately never that window.
So the press is written down in the keyboard interrupt -- a counter, the
character, and the monotone clock -- and whoever cares reads it
(`SYS_OSUM_HOTKEY`). **The counter is the protocol**: a reader keeps the
number it saw last and acts when it changes. Nothing is acknowledged, so
nothing can forget to acknowledge, and two readers cannot take a press
away from each other.

There is **one** hotkey and it is spelled out in the source rather than
configured. A key map is a round of its own, and half of one here would
be exactly the kind of half-thing this round keeps refusing.

**And the Escape key had never arrived either.** Scan code 1, and
position 1 of the table in `translate` is a NUL -- so pressing Escape
in this system produced nothing at all, and had produced nothing since
round 59. It was found the same way round K15 found the tab key: by
needing it and measuring that nothing happened. It is now a 27.

What that changes for everyone else, written down rather than left to be
discovered: a program that reads keys now sees a 27 where it saw
nothing. `/bin/edit` reads arrow keys as `ESC [ x` and will take a lone
Escape for the start of one, swallowing the next character -- which is
what a real terminal does with a lone Escape too, and is why terminals
have had a timeout for it since the seventies. This round does not build
that timeout. `tools/unix/run.sh` (107) and `tools/kernel/run.sh` (176)
were re-run against the change and neither moved.

### 14.5 The tiles, and why there are three drawings and not six

The obvious build is two drawings per tile, one for on and one for off,
so that somebody who cannot tell the colours apart still sees which way
the switch stands. It was drawn that way first and then **measured**,
and it failed its own test: a sixteen-by-sixteen glyph is mostly
outline, so "the same shape with the middle changed" comes out at about
a quarter of its pixels different -- under the third that
`tools/netview/icons.py` demands of any two signs that mean different
things. The tool was right. A quarter is not a difference anybody sees
at a glance.

So the switch position is carried where a toggle actually carries it,
and **only one of the three is colour**:

1. **the word** under the tile -- `an` or `aus`. Not a hue, a word.
2. **the relief** of the frame -- raised when off, sunken when on
   (`wlibc.frame3`, the same relief every button in this system has had
   since K15).
3. the fill, which is colour, and which is therefore the one of the
   three nobody has to be able to see.

The three glyphs themselves are OSYM with colour **roles**, like every
other sign of this round, so one file is right in a light scheme and in
a dark one. `tile-fake` is `sys-faking` enlarged, on purpose: this tile
turns on exactly the thing that corner sign announces, and two drawings
for one switch and its consequence would be two things to learn instead
of one. `tile-hide` is deliberately *not* a screen, because `tile-fake`
is one and they sit side by side.

Measured, silhouette against silhouette, threshold 33 %:

| | |
|---|---|
| fake vs net | **85 %** |
| fake vs hide | **77 %** |
| net vs hide | **92 %** |
| tile-fake vs state-online | **75 %** |
| tile-fake vs state-nocarrier | **76 %** |
| tile-hide vs state-online | **76 %** |
| tile-net vs state-online | **66 %** |

The last four are there because the panel opens directly above the
corner: those signs are on the screen at the same time and are the same
size.

### 14.6 Two defects the screenshots found

The panel was built, it compiled, it opened, and it was wrong twice --
in ways that are invisible in a source file and obvious in a picture.
`tools/netview/kachel.py` reads the panel back out of the screenshot and
found both:

1. **The label ran off its own tile.** "Netz vortaeuschen" reached four
   pixels past the right edge at `TW = 120`. In the source it says
   `text_at(tx + 10, ...)`, which is correct.
2. **Two text rows touched.** On the third tile, the label and the word
   under it shared a row of pixels. Also not visible in any source: it
   is the sum of the tile height, the ascent of the font and two
   baselines, and nobody adds those up right in their head.

The widest label turned out to be between 141 and 160 pixels, found by
**bisection against the running system** rather than by reading the
font: at `TW = 140` the panel's own `fit` cut it to "Netz vortaeusc", at
160 to "Netz vortaeusche", at 180 it stands whole. The checker now runs
on all four edges, so neither defect can come back quietly.

`fit` stays as a safety net, and it reports the **shortened** label, not
the long one -- a tile that reported the long label and painted a
clipped one would pass a checker that compares the two, which is the
trap round DESKTOP wrote down for the status fields.

Two more, from the same habit of driving the thing instead of reading
it, and **neither was what it looked like**:

3. **The panel was on `L_TOP` and could not be typed at.** The window
   server gives the keyboard only to a window on the normal layer:
   `wm.set_layer` takes the focus away from anything that leaves it, and
   `wm.on_mouse` calls `set_focus` only for `L_NORMAL`. That is round
   DESKTOP's rule and a good one -- a taskbar that swallowed the
   keyboard would make every key after a click on it useless. But this
   panel is not a taskbar. It lives on the normal layer now and is
   raised when it opens. The price is one line in `leiste.list_read`: a
   normal-layer window gets a button in the bar, and a panel that
   belongs to the bar must not stand beside the programs.
4. **The key is at bits 32..47 of the event word, not at 0.**
   `wm.ev_push` packs three numbers as `(a << 32) | (b << 16) | c`, and
   for a key the character is the first of them. Read as the whole word
   it is `27 << 32`, which is never 27 -- so every Escape was silently
   ignored, and the symptom was indistinguishable from the focus problem
   above. It cost two runs to stop believing the first explanation after
   it had been fixed.

### 14.7 A seam closed rather than widened

Section 13.6 admitted a seam: the shape of the line `fallback=<word>`
stood in `netview.fi` **and** in `einstellungen.fi`. The quick settings
would have made that three. So the reader and the writer moved into
`nv.fi`, where `fb_name` and `fb_word` already live and where all three
callers already come. There is one shape of that line now.

The cost is honest and was measured rather than guessed: `nv.fi` now
pulls `libc.io` into the two programs that imported it without one
(`ps` and `nvcheck`), and `tools/userland/run.sh` measures the whole
userland against the 2 MiB of the drive. The number is in the round's
report.

### 14.8 What this addendum does not do

* **No key map.** One hotkey, `Super+A`, in the source. `Super` with any
  other letter is latched and ignored -- which means it is also swallowed,
  and that is a deliberate trade: swallowing it costs nothing today and
  leaving it through would put stray letters in documents the day
  somebody adds a second hotkey.
* **No light/dark tile, no brightness, no volume, no do-not-disturb.**
  See 14.2. Three of the four are waiting on other rounds; the fourth
  has nothing behind it at all.
* **The panel does not remember an address across a reboot.** "Network
  off" keeps the address it took away in memory, so "network on" gives
  the same one back; after a restart that memory is gone and DHCP is the
  thing that answers, which is right. A remembered address in a file
  would be a second, stale answer to a question something else already
  answers at every start.
* **No animation, no drop shadow.** The panel appears and disappears.
* **The corner sign still has no click of its own** -- the icon *group*
  opens the panel, which is one target for three icons.

## 12. Files

| file | what |
|---|---|
| `kernel/netview.fi` | the views, the decision, the faked endpoint, the counters |
| `kernel/sched.fi` | `T_NETV`, `T_NETOK`, `NETOK_MAX` in the task record |
| `kernel/sys.fi` | the door: `socket`, `bind`, `listen`, `accept`, `connect`, `sendto`, `recvfrom`, `shutdown`, the names, `NETGET`, inheritance, and the three new calls |
| `kernel/kmain.fi` | one line: the report at the end of a run |
| `kernel/user/nv.fi` | the four calls for ring 3 |
| `kernel/user/netview.fi` | `/bin/netview` |
| `kernel/user/nvcheck.fi` | `/bin/nvcheck`, the program that is measured |
| `kernel/user/ps.fi` | the NET column |
| `kernel/user/leiste.fi` | the mark in the taskbar |
| `kernel/user/einstellungen.fi` | the page "Netzzugriff" |
| `kernel/user/explorer.fi` | the context menu entry |
| `kernel/user/starter.fi` | starting a bundle with its view |
| `kernel/user/appdir.fi` | `net=` in INFO, `/users/<name>/config/netview`, and the order between them |
| `lib/libc/kcall.fi`, `kernel/user/ulib.fi` | the three call numbers |
| `kernel/netmark.fi` | GENERATED from the drawings: the three marks as bit rows, for the window server |
| `kernel/wm.fi` | the only change this round makes there: the mark in the title bar |
| `kernel/kmain.fi` | `netvdemo`, a measurement word that starts three programs under three views |
| `assets/netview/*.txt` | the eight drawings -- the single source of every sign |
| `assets/netview/sys-faking.txt` | second addendum: the sign for "the machine is faking" |
| `kernel/hw.fi` | second addendum: `nvfall=` on the kernel command line |
| `/etc/netview.conf` | second addendum: `fallback=<word>`, written by `netview fallback`, read by `netview boot` |
| `assets/netview/theme-dark`, `theme-light` | the two schemes the measured runs boot with, and the numbers the contrast is computed from |
| `tools/netview/icons.py` | builds the OSYM files and `netmark.fi`, and checks contrast and silhouettes |
| `tools/netview/schau.py` | reads a sign back out of a screenshot with the roles resolved |
| `tools/netview/blatt.py` | the sheet of all eight signs |
| `tools/netview/run.sh` | the acceptance run |
| `kernel/user/qs.fi` | third addendum: the quick settings panel -- layout, tiles, drawing, the hotkey |
| `kernel/kbd.fi` | third addendum: the Super key as a modifier, the hotkey latch, and the Escape key that had never arrived |
| `kernel/kstate.fi` | third addendum: `KB_SUPER`, `HK_SEQ`, `HK_KEY`, `HK_NS` in the K11 block |
| `assets/netview/tile-fake.txt`, `tile-net.txt`, `tile-hide.txt` | third addendum: the three tile drawings |
| `tools/netview/kachel.py` | third addendum: reads the panel back out of a screenshot -- overflowing labels and touching rows |
| `tools/netview/smoke.sh` | third addendum: one boot, one Super+A, one picture -- the fast loop while the panel was being built |
