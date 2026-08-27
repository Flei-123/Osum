# Round TUNNEL — a VPN for OrientOS, and an honest account of it

This round gives Osum a WireGuard implementation, the AmneziaWG
obfuscation as an option on top of it, a SOCKS5 and HTTP-proxy client,
and a recommendation about Tor that is a recommendation *not* to build
something.

Everything below that is a number came out of a run. Everything that did
not work is named, with the reason.

---

## 1. Why WireGuard, and not OpenVPN or IPsec

The decision was not made on features. It was made on **how much code has
to be right**, because every line of a VPN is a line an attacker gets to
attack, and this project has one round to write it.

| | WireGuard | OpenVPN | IPsec (strongSwan/Linux) |
|---|---|---|---|
| Reference implementation | a few thousand lines | tens of thousands | hundreds of thousands across kernel and daemon |
| Algorithm negotiation | **none** | cipher/digest/TLS suite negotiation | IKEv2 proposals, transforms, DH groups |
| Message types | 4 | many, over a TLS control channel | IKE_SA_INIT, IKE_AUTH, CREATE_CHILD_SA, INFORMATIONAL, plus ESP |
| Parser | fixed-size fields | TLS + its own framing | ASN.1-ish payload chains |
| Configuration surface | 8 keys | hundreds of options | policy database + SPD + SAD |

The property that matters most is the second row. **WireGuard has no
algorithm negotiation at all.** There is one hash (BLAKE2s), one AEAD
(ChaCha20-Poly1305), one curve (Curve25519), one key derivation (HKDF).
There is no cipher list to downgrade, no version byte to lie about, no
"NULL cipher" to negotiate. A very large share of the attacks on TLS over
twenty years — FREAK, Logjam, the downgrade half of POODLE — were attacks
on negotiation, and WireGuard simply does not contain the machinery.

The second property: **the messages are fixed size.** 148, 92, 64, and
32+n octets. There is no length-prefixed nesting, no ASN.1, no
variable-length option chain. The parser is a handful of offsets. Most
memory-safety bugs in VPN software live in parsers; there is barely a
parser here.

The third: **it is silent.** Every handshake message carries `mac1`, a
keyed BLAKE2s over the message keyed with a hash of the *receiver's*
public key. A scanner that does not already know the public key cannot
produce a correct `mac1`, and a message with a wrong one is dropped
before a single asymmetric operation. From the outside the UDP port looks
closed.

This is the only VPN protocol that a project this size can attempt
responsibly. That is the argument, and it is also the limit of the
argument — see section 8.

---

## 2. What was built

| Where | What | Lines |
|---|---|---|
| `lib/crypto/blake2s.fi` | BLAKE2s, keyed BLAKE2s, HMAC-BLAKE2s (RFC 7693, RFC 2104) | 396 |
| `lib/crypto/chacha.fi` | ChaCha20, Poly1305, the AEAD (RFC 8439) + XChaCha20-Poly1305 | 548 |
| `lib/crypto/x25519.fi` | X25519 (RFC 7748) | 302 |
| `lib/crypto/big.fi` | the Montgomery arithmetic under it | 662 |
| `lib/wg/proto.fi` | the WireGuard protocol: Noise IK, rekeying, cookie reply, replay window, cryptokey routing, AmneziaWG | 1742 |
| `lib/socks/socks5.fi` | SOCKS5 (RFC 1928, RFC 1929) and HTTP CONNECT | 393 |
| `kernel/wg.fi` | the tunnel as an interface: the packet path, the kill switch, address translation | 1024 |
| `tools/tunnel/` | the five measuring instruments | 2800 |

### Where the code lives, and why

**The primitives are in this repository and not in Firn's `lib/std/crypto/`,
which is where they belong.** Three of the four already exist there —
ChaCha20, Poly1305 and X25519 were written in Firn's round B5 for a TLS
1.3 client. Osum cannot reach them: `vendor/firn/COMMIT` pins Firn at
`c66c6bcd5`, a commit from before round B5, and that pin is what makes a
kernel bug distinguishable from a compiler bug while Firn moves
(`vendor/firn/fetch-firnc.sh` states the reasoning). Moving the pin would
swap the compiler out from under the fourteen rounds working in this
repository at the same time, in order to import three files.

So ChaCha20-Poly1305 and X25519 were **ported** from Firn round B5 —
`import std.rt` removed, `BIG_MAX` cut from 136 limbs to 12 — and BLAKE2s
and XChaCha20-Poly1305 were **written**, because Firn has neither. Every
ported file says so in its header and names the original. When the pin
next moves, these four files should be deleted in favour of Firn's, and
`tools/tunnel/vectors.py` is what will say whether that is safe.

This is not a new pattern in Osum: `kernel/rand.fi` already carries its
own ChaCha20 and `kernel/user/pw.fi` its own SHA-256, HMAC and PBKDF2,
for exactly the same reason.

**The protocol is split in two.** `lib/wg/proto.fi` is the protocol and
nothing else: no socket, no scheduler, no allocator, no system call, no
profile line. It is compiled into the kernel *and* into a hosted Linux
program (`tools/tunnel/peer.fi`) that speaks it to a real `wg`. That
split is the reason section 4 is possible at all.

**The kernel half is in ring 0** for three reasons: the private key must
be somewhere ring 3 cannot read (SMEP/SMAP from round K10 already keep it
out), the kill switch is only real at the bottom of the stack, and a
tunnel is worth having precisely because programs do not have to know
about it.

---

## 3. The primitives: 1522 test vectors

Cryptography without passed test vectors is decoration. `tools/tunnel/vectors.py`
drives `lib/crypto/*.fi` — the same files the kernel links — against the
literal vectors printed in the RFCs *and* against a second, independent
implementation over generated inputs.

```
  AEAD refusals               9 vectors  all passed
  AEAD vs OpenSSL           172 vectors  all passed
  BLAKE2s KAT (keyed)       256 vectors  all passed
  BLAKE2s digest lengths     64 vectors  all passed
  BLAKE2s key lengths        33 vectors  all passed
  BLAKE2s length sweep      207 vectors  all passed
  BLAKE2s refusals            4 vectors  all passed
  ChaCha20 vs OpenSSL       136 vectors  all passed
  HMAC-BLAKE2s              100 vectors  all passed
  RFC 7693 App. B             1 vectors  all passed
  RFC 7748 5.2                2 vectors  all passed
  RFC 7748 5.2 iterated       2 vectors  all passed
  RFC 7748 6.1                4 vectors  all passed
  RFC 8439 2.3.2 block        1 vectors  all passed
  RFC 8439 2.4.2              1 vectors  all passed
  RFC 8439 2.5.2              1 vectors  all passed
  RFC 8439 2.8.2 seal         1 vectors  all passed
  RFC 8439 A.1 blocks         5 vectors  all passed
  RFC 8439 A.2 encrypt        2 vectors  all passed
  RFC 8439 A.3 Poly1305      11 vectors  all passed
  RFC 8439 A.5 open           1 vectors  all passed
  X25519 top bit ignored     20 vectors  all passed
  X25519 vs libsodium       400 vectors  all passed
  XChaCha20 vs libsodium     88 vectors  all passed
  draft-xchacha A.3.1         1 vectors  all passed

1522 vectors, all passed
```

Per algorithm: **BLAKE2s 565**, **ChaCha20 145**, **Poly1305 12**,
**ChaCha20-Poly1305 AEAD 182**, **XChaCha20-Poly1305 89**, **X25519 428**,
**HMAC-BLAKE2s 100**.

Two things about how this was done:

* **The literal RFC vectors are the authority.** A cross-check against a
  second implementation only proves two implementations agree, which is
  exactly what happens when both are wrong the same way. The RFC vectors
  are typed in from the document. Two of them were typed in *wrong* while
  this round was being built — RFC 8439 A.2 vector 1 with counter 1
  instead of 0, and A.3 vectors 10 and 11 with a malformed key literal —
  and both were caught because the implementation disagreed with them.
  The guard that had silently skipped the malformed literals was changed
  to abort instead: a test that quietly counts nothing is worse than no
  test.
* **The refusals are counted as vectors.** 9 AEAD refusals (a flipped
  octet in the body, in the tag, in the AAD, in the key, in the nonce, a
  truncated packet) and 4 BLAKE2s refusals (a digest longer than 32, a
  key longer than 32, a zero-length digest). An AEAD that returns
  plaintext for a broken tag is not an AEAD, and that property has no
  positive test vector.

The million-round iterated X25519 of RFC 7748 5.2 is behind `--slow` and
was not completed in this round; the 1-round and 1000-round checkpoints
both pass.

---

## 4. The protocol against the Linux kernel — 29 checks

This is the measurement the round stands on. `lib/wg/proto.fi` — the
identical file the kernel compiles — was driven against the WireGuard
implementation **in the Linux kernel**, over a veth pair into a network
namespace.

```
== against the Linux kernel's WireGuard ==
  handshake initiation is 148 octets             ok   148
  Linux answered with a 92 octet response        ok   92 octets, type 2
  the response verified and keys are up          ok   resp 0
  `wg show` reports a handshake                  ok   1787821145
  `wg show` counts octets received from us       ok   180 92
  Linux's ping goes through our tunnel           ok   3 of 3 replies,
                          rtt min/avg/max/mdev = 0.850/0.897/0.957/0.044 ms
  Linux accepted every packet we encrypted       ok   1896000 octets on the wire
  we decrypted every packet Linux sent us        ok   410 of 400 packets
  20000 AEAD opens all verified                  ok   20000
  a replayed transport packet is refused         ok   data then none
  one flipped octet is refused                   ok   none
  a truncated packet is refused                  ok   none
  Linux ignores an initiation with a wrong mac1  ok   silent

== the same again with a preshared key ==
  ... all 13 again, all ok
```

**`ping` inside the namespace prints a round-trip time.** The Linux kernel
encrypts an ICMP echo request with the keys it negotiated with us; this
code decrypts it, builds the echo reply, encrypts it, and sends it back;
Linux decrypts that and `ping` reports 0.9 ms. Nothing about that works
if a single field, a single hash input or a single key-derivation step is
wrong.

The run is done twice, with and without a **preshared key**, because
`psk2` changes the chaining-key derivation and an implementation can pass
without one and fail with one.

### Throughput

Two numbers, and the difference between them matters.

* **Through the test harness: about 0.4 MB/s.** This is the rate of the
  *harness*, not of the code: every packet crosses a pipe to a subprocess
  and a Python loop. It is reported here only so nobody quotes it as a
  throughput figure.
* **The inner loop, measured inside the program with no I/O:
  ChaCha20-Poly1305 over 1200-octet payloads, 20 000 times.**

  | | seal | open |
  |---|---|---|
  | quiet machine, best of run | **15.2 MB/s** | **14.7 MB/s** |
  | machine at load average 16 | 9.9–12.9 MB/s | 9.0–11.7 MB/s |

  All 20 000 opens verified their tags. For scale, OpenSSL's
  ChaCha20-Poly1305 on the same machine is in the gigabytes per second:
  it has hand-written AVX2 and processes four or eight ChaCha blocks at a
  time. This implementation is a straightforward scalar loop in Firn with
  every 32-bit word carried in a `u64` and masked, because Firn traps on
  overflow. **A factor of roughly a hundred is the honest cost of writing
  it in a young language with no SIMD and no assembly.** It is fast
  enough for a 100 Mbit link and it is not fast enough for a gigabit one.

The measurement was taken while thirteen other rounds were building on
the same machine, which is why the range is wide and why both numbers are
given.

---

## 5. AmneziaWG — 18 checks, and one thing that could not be measured

AmneziaWG is a WireGuard derivative that adds obfuscation against deep
packet inspection. **It is implemented here as an option on WireGuard, not
as a second protocol** — the same `lib/wg/proto.fi`, with three switches.

The specification was researched from the upstream sources
(`amnezia-vpn/amneziawg-go`, `amnezia-vpn/amneziawg-linux-kernel-module`,
`docs.amnezia.org`) rather than assumed. What was implemented is
**AmneziaWG 1.0 and nothing above it**:

| Parameter | What it does | Status |
|---|---|---|
| `H1`–`H4` | replace the `uint32` message type at the front of the four message kinds. WireGuard's 1/2/3/4 is a four-octet constant at a fixed offset — the cheapest signature a DPI box can match. | **implemented** |
| `S1`, `S2` | prepend random octets to the initiation and the response, so they stop being exactly 148 and 92 octets | **implemented** |
| `Jc`, `Jmin`, `Jmax` | send `Jc` datagrams of random length between `Jmin` and `Jmax` *before every handshake* | **implemented** |
| `S3`, `S4` | padding for the cookie reply and for transport packets (AWG 2.0) | **not implemented** |
| `I1`–`I5` | custom signature packets built from a small tag language `<b 0x..>`, `<r n>`, `<rd n>`, `<rc n>`, `<t>` (AWG 1.5+) | **not implemented** |
| `J1`–`J3`, `Itime` | existed in AWG 1.5, removed again in 2.0 | **not implemented, and should not be** |
| `HeaderProtectionKey`, `ContentPaddingAddition`, timing ranges | AWG 3+ | **not implemented** |

The constraints the upstream README states are **enforced, not trusted**:
`H1`–`H4` must be pairwise distinct, and `S1 + 148 != S2 + 92` (upstream
writes it as `S1 + 56 != S2`) so that the two padded handshake messages do
not come out the same size — padding that made them equal would replace
one signature with another.

### What could not be established

Three things are **not stated anywhere this round could verify**, and
guessing them would produce something that looks like AmneziaWG and does
not interoperate:

1. **The exact byte position of the S paddings.** `docs.amnezia.org`
   describes them as "prefixes"; the `amneziawg-go` README calls them
   "padding" without saying prepend or append. The length arithmetic
   (`148 + S1`) fits a prefix, and a prefix is what is implemented — but
   it was not verified against upstream source.
2. **The distribution of the junk lengths** — uniform? inclusive bounds?
   Not documented.
3. **The permitted range of `S1`/`S2`.** The kernel-module README says
   `S1 <= 1132`; `docs.amnezia.org` says `0–64`. These contradict. The
   implementation takes the wider bound and the test uses values inside
   the intersection (15–150 recommended, 39 and 121 used).

### What could not be measured at all

**There is no interoperability test against real AmneziaWG.** The kernel
module is not packaged for this machine, and `amneziawg-go` needs
`/dev/net/tun`, which cannot be created in the container this repository
is measured in (`mknod: Operation not permitted` — the same finding round
K8 wrote down). **Nothing in this round proves that Osum's AmneziaWG
would complete a handshake with Amnezia's own client.** That claim is not
made anywhere.

What *was* measured (`tools/tunnel/amnezia.py`, 18 checks):

```
  a valid parameter set is accepted                    ok
  two equal headers are refused                        ok
  S1 + 56 == S2 is refused (equal padded sizes)        ok
  Jc above 128 is refused                              ok
  Jmin above Jmax is refused                           ok
  the initiation is 148 + S1 octets                    ok   187
  the initiation's type word is H1                     ok   1020325451
  octet 0 is NOT the WireGuard type 1                  ok   0xbfe9c0d6
  the response is 92 + S2 octets                       ok   213
  the response's type word is H2                       ok   1457133905
  the obfuscated handshake completed                   ok
  a transport packet's type word is H4                 ok   1904583849
  the payload came through the obfuscated tunnel       ok
  a 200 octet payload is padded to 208 with zeroes     ok
  a plain WireGuard end cannot parse it                ok
  control: plain WireGuard, Linux answers              ok
  a stock Linux WireGuard ignores the obfuscated handshake  ok   silent
```

The last two are the pair that matters: the **same code and the same
keys** get an answer from Linux with the parameters off, and get silence
with them on. That proves the obfuscation is a real change to the wire
and not decoration.

---

## 6. Proxies, and the Tor recommendation

### SOCKS5 and HTTP CONNECT — 19 checks

`lib/socks/socks5.fi` implements RFC 1928, the username/password
sub-negotiation of RFC 1929, and HTTP `CONNECT`. It was measured against
a real SOCKS5 server, a real HTTP proxy, and **the real Tor daemon**:

```
  a plain CONNECT reaches the target                 ok
  the host name went over UNRESOLVED (ATYP 3)        ok   ('osum.example', 80, 3)
  a credential is offered and accepted               ok
  the proxy saw the credential we sent               ok   ('ident-a', 'secret')
  no credential against a proxy that demands one is refused  ok
  reply 1..7 and Tor's 240, 246 are each refused     ok   (8 checks)
  a proxy that is not there is refused               ok
  CONNECT reaches the target                         ok
  the request line is well formed                    ok   CONNECT osum.example:443 HTTP/1.1
  a page fetched through the real Tor network        ok   ok 0 200 HTTP/1.1 200 OK
  Tor refuses a malformed .onion address             ok   fail reply 1
  two isolated streams both work                     ok
```

**A page really was fetched over the Tor network** from this code.

The single most important line in that list is the second one. **The host
name goes over the wire unresolved, as `ATYP = 0x03`.** If a program
resolves the name locally first, the DNS query leaves the machine in the
clear, from the real address, past the proxy — and the resolver, the ISP
and everyone on the path learn who is about to visit what. The connection
that follows is then perfectly encrypted and perfectly pointless. curl
calls the difference `socks5h://` versus `socks5://`; Firefox calls it
`network.proxy.socks_remote_dns`. It is the most common way a proxy setup
leaks, and Osum has one accidental advantage here: it has no resolver at
all, so there is no local lookup that *could* leak.

The username/password exchange is implemented for **Tor's stream
isolation**, not for security: Tor treats any distinct credential pair as
a request for a separate circuit, which is the supported way to keep two
identities off the same exit node. Both isolated streams were measured
working.

### Tor: the recommendation is not to build it

**Do not implement Tor. Speak SOCKS5 to a Tor that other people wrote and
other people audit.** This round adopts that position, and the reasoning
below is what was checked rather than assumed.

**Tor is not a protocol; it is six subsystems.** A client must implement
the directory protocol and the consensus, the directory authorities'
certificates and signature threshold, circuit construction (`CREATE2`/
`EXTEND2` with ntor), relay cells and stream management, and — the part
that is pure policy and pure danger — path selection: entry guards, the
/16 rule, family declarations, bandwidth weighting.

**A bug does not crash; it deanonymises, silently.** This is the whole
argument and it is worth spelling out:

* **Entry guards.** The guard specification states the arithmetic
  directly: without guards, an adversary holding a fraction *k/N* of the
  network deanonymises *F = (k/N)²* of circuits, and after *C* circuits
  has seen a given user with probability *1−(1−F)^C*. That converges to
  1. An implementation that picks a fresh entry node per circuit — or
  that fails to persist its guard state across restarts and quietly falls
  back to picking a fresh one — is not slightly weaker. It makes
  deanonymisation a question of time rather than of probability.
  Øverlier and Syverson demonstrated the practical version of this in
  2006, locating hidden services with a single hostile node in minutes.
* **The /16 and family rules.** The path specification requires that no
  two relays in a path come from the same /16, the same family, or be the
  same relay. Tor's security rests on entry and exit being controlled by
  different parties; whoever sees both can correlate. An operator with a
  /16 — cheap for a hoster or a state — can put 200 relays in it, and an
  implementation without the rule will happily pick guard and exit from
  the same one. **The circuit works perfectly. There is no error, no log
  line, no crash.**
* **The consensus signature.** The consensus defines which relays exist
  at all. If the signatures are not checked, or the >50% threshold is not
  enforced, a man in the middle hands the client a consensus containing
  only his own relays. All three hops belong to the attacker and the
  client shows "connected".
* **Fingerprinting.** Tor's anonymity is anonymity *in a set*. A client
  whose TLS fingerprint, circuit-build timing, padding behaviour or
  directory-fetch pattern differs from the standard one is no longer "a
  Tor user" but "the user of that implementation". The anonymity set can
  collapse to one.
* **There is a documented case of exactly this class of bug.** The 2014
  relay-early traffic-confirmation attack deanonymised hidden-service
  users from February to July 2014 using ~115 relays, about 6.4% of guard
  capacity. The vulnerability was that Tor limited *outbound* relay-early
  cells but not *inbound* ones — a single missing validation rule in one
  direction, which became a covert channel that encoded hidden-service
  names into the protocol headers. That is precisely the kind of rule a
  reimplementation leaves out, because it looks functionally unnecessary.

**The most telling evidence is what the Tor Project itself does.** It is
rewriting Tor in Rust as *Arti*, with full-time cryptographers and
protocol authors, and that effort has been running for years. Two honest
caveats about this paragraph: the specific line count of Arti could not
be verified in this round (the research attempt to pin it down failed and
is not being invented here), and **the Tor Project publishes no explicit
warning against third-party implementations** — the specifications
formally invite compatible implementations. But the path specification —
the anonymity-critical one — carries the notice **"THIS SPEC ISN'T DONE
YET."** That is the strongest argument available: *the document one would
need in order to reimplement Tor safely does not exist in finished form.*
Whoever implements from the spec alone implements the interoperability
and not the security, because part of the security lives only in the C
code.

**Therefore:** the switch in the settings is labelled for what it is. It
routes traffic through a SOCKS5 proxy that is expected to be a Tor
client. It does not say "anonymous". Osum's contribution is the SOCKS5
client — measured, above, against real Tor — and the anonymity remains
with the people who can audit it.

**What Osum does not have, and it matters:** Osum cannot *run* a Tor
daemon. Tor is a large C program with an event loop, OpenSSL and a
filesystem full of state, and Osum has no port of it. So the switch is
useful when there is a Tor on the network — a router, another machine,
`tor` on a phone — and is useless otherwise. That is written into the
settings page rather than hidden.

---

## 7. The kernel: what works and what does not

`kernel/wg.fi` puts the tunnel between `stack.net_output` and the card.
Two calls were added to `inet.pump`, one on each side, and they are the
only changes to the packet path.

### What was measured

* **The kernel builds with the tunnel in it** and `wg:` comes up at boot.
* **X25519 inside the Osum kernel agrees with libsodium exactly.** The
  kernel derives its public key from the configured private key and
  prints it; the test compares it octet for octet with what libsodium
  computes on the host from the same private key. Two independent runs,
  two different random keys, both matched.
* **The Osum kernel completed a real WireGuard handshake with the Linux
  kernel.** `wg show` in the namespace reports a latest handshake and
  180 octets received — which is 148 for the initiation plus 32 for a
  transport keepalive that Linux authenticated and counted. Linux would
  not count either unless both decrypted and verified.

### Data through the tunnel, in the kernel

```
-- 5b. the handshake, kernel to kernel --
  OK    the Linux kernel completed a handshake with Osum
  OK    Linux received 180 octets from the Osum tunnel
  OK    Linux pinged Osum THROUGH the tunnel: 4 of 4,
        rtt min/avg/max/mdev = 3.744/5.590/7.347/1.333 ms
```

`ping 10.91.0.1` inside the namespace goes to the Linux `wg0`, is
encrypted by the Linux kernel, arrives at Osum's virtio card as a UDP
datagram, is decrypted by `kernel/wg.fi`, has its inner destination
rewritten, is handed to `inet.fi` as an ordinary frame, is answered by
Osum's own ICMP, is encrypted again on the way out and is decrypted by
Linux. **Four of four, at 5.6 ms.** On the wire it is visible as the
pairs it should be:

```
IP 10.9.0.1.51820 > 10.9.0.2.51820: UDP, length 128
IP 10.9.0.2.51820 > 10.9.0.1.51820: UDP, length 128
```

128 octets is exactly an encrypted 84-octet ICMP echo plus WireGuard's
16-octet header and 16-octet tag, twice. The kernel's own counters agree:
`encap=3 decap=4 rx_good=4 rx_bad=0 icmp=3`.

### The kill switch: 0 octets

The count does not come from the kernel — a kill switch that reports its
own success is a claim, not a measurement. `tcpdump` runs inside the
namespace on the far end of the veth and records everything that arrives;
a script counts the octets of IPv4 packets whose source is Osum. Nothing
in the kernel can influence that number.

The same kernel image is run twice with the same service (`nsvc=4`, which
makes Osum open a TCP connection outwards by itself), the same
unreachable tunnel endpoint, and the only difference is the word
`wgkill`:

```
  counter-check: WITHOUT wgkill the same kernel put 44 IP octets on the wire   OK
  KILL SWITCH: 0 IP octets on the wire, counted by tcpdump outside the kernel  OK
  --  ARP frames, allowed on purpose: 5 without, 2 with the switch
  --  the kernel says it refused 290 octets
```

**Zero.** The kernel's own counter agrees that it refused 290 octets, and
the independent count on the wire is 0.

Two honest qualifications:

* **ARP is exempt on purpose and is counted separately** — 2 frames got
  out with the switch armed. `kernel/wg.fi` lets ARP through because
  without it the endpoint cannot be resolved and the tunnel could never
  come back up. An ARP frame carries a MAC and an IP the local segment
  already knows and it does not leave the segment. That is a decision,
  not an oversight, and it is why the count is of *IPv4* octets.
* **The counter-check is thin.** 44 octets is one packet, not a stream.
  The contrast 44 → 0 is real and the direction is right, but a
  counter-check that leaked kilobytes would be a stronger statement and
  this one does not make it.

The mechanism is one branch in `tx_hook`, sitting below the only call to
`virtio.tx_frame` there is in the system — which is why nothing in the
system can route around it.

### The fault this round spent an afternoon on, and what it really was

For most of the round stage 5b failed with `0 of 4 replies`, and the
capture showed Linux sending the encrypted pings while Osum's counters
said `rx_f=6, decap=0`. The obvious reading was that the tunnel was
dropping them. It was not. **`nwait` is counted in TICKS, not seconds**
(`kernel/netsvc.fi`, `idle_service`); the runner passed `nwait=55`, and at
100 Hz that is 0.55 seconds. The kernel finished its service, printed its
counters and stopped — one second into a run whose handshake happens in
that first second. Everything after it, in both directions, was being
measured after the machine had already reported.

It is written down because the wrong diagnosis was written down first, in
this file, and because the shape of the mistake is general: a counter that
stops growing looks exactly like a component that is dropping packets.

### The regression

Round K8's own network acceptance — the section this round changed —
is **75 passed, 0 failed** with `kernel/wg.fi` compiled in and hooked
into `inet.pump` on both sides, at 5382 KiB/s on a clean wire. Both
compiler stages build the kernel with the tunnel in it.


### The one-address problem

Osum's stack is `vendor/firn/lib/net/stack.fi`, pinned. `net_init` takes
**one** address and `net_input` discards every IP packet not addressed to
it. There is no second address, no interface list and no routing table,
and this round may not change that file.

So the tunnel address is **mapped one-to-one onto the stack's address** at
the two points where a packet crosses the tunnel's edge: inbound, the
inner destination is rewritten from the tunnel address to the stack's;
outbound, the source is rewritten back. The IP header checksum is
recomputed and the TCP/UDP checksums are adjusted incrementally by RFC
1624's method. This is address translation and it has the limits of
address translation: exactly one address is mapped, and nothing carrying
an address inside its payload survives it.

### Other limits of the kernel half

* **One interface.** Several profiles, one up at a time.
* **Four peers.** `PEER_MAX` is 4; a client profile has one.
* **IPv4 only.** The stack has no IPv6, so a v6 tunnel would have nothing
  to carry. A v6 line in a configuration file is refused with a message,
  not silently dropped.
* **No fragmentation and no ICMP "fragmentation needed".** A packet too
  large after encapsulation is dropped and counted.
* **Handshakes run on the network task.** A Curve25519 operation takes
  long enough to be visible and this kernel has nowhere else to put it.

---

## 8. The warning that matters most

**None of this cryptography has been audited.**

`lib/crypto/` and `lib/wg/proto.fi` are a from-scratch implementation of
a security protocol, written in one round, by one project. What has been
established is:

* it computes the right functions — 1522 published test vectors;
* it computes them in the right order — it completes handshakes and
  carries authenticated traffic with the WireGuard implementation in the
  Linux kernel, with and without a preshared key;
* it refuses what it should refuse — replays, flipped octets, truncated
  packets, wrong MACs, wrong timestamps.

What has **not** been established, and cannot be by testing:

* that it is free of timing side channels. The X25519 ladder is written
  with a masked conditional swap and no scalar-dependent branch, and the
  tag comparisons accumulate differences instead of returning early —
  both deliberately — but nobody has *measured* the timing.
* that it has no memory-safety fault reachable from a hostile packet.
  Firn traps on integer overflow and bounds-checks its arrays, which
  removes a large class, but there has been no fuzzing campaign.
* that the state machine has no reachable bad state under adversarial
  ordering, duplication and delay.
* that the AmneziaWG obfuscation actually defeats any real censor's DPI.
  It changes the wire; whether that is *enough* is an empirical question
  about a specific adversary, and no such measurement was made.

**Concretely: do not put anything behind this that you would mind
losing.** Use it to learn how WireGuard works, to move traffic between
machines you own, and to have a VPN that is yours end to end. Do not use
it where the consequence of a break is serious — where a real WireGuard
implementation exists, use it. The same warning is in the header of
`lib/wg/proto.fi` and belongs on the settings page, because a warning
that appears only in a source file is a warning nobody reads.

---

## 9. What is not built

Named plainly, because a round that lists only what it finished is a
sales document:

* **The graphical half.** The settings page with the profile list, the
  taskbar indicator, the quick-settings tile and the `.conf` import from
  the file explorer were designed against the neighbouring rounds
  (NETVIEW's quick-settings panel, ICONS' glyph names) but **were not
  built**. The protocol and kernel work took the round.
* **The profile store.** `/etc/wg/*.conf` parsing in the standard
  WireGuard format, several named profiles, one marked default, switching
  between them and the milliseconds that takes — designed, not built.
  `kernel/wg.fi` takes its configuration from the kernel command line,
  which is enough for a test runner and not enough for a user.
* **The system-wide proxy setting.** `lib/socks/socks5.fi` is a library
  with no `/etc/proxy.conf` behind it and no per-program override yet.
* **AmneziaWG 1.5 and above** — see section 5.
* **The million-round X25519 checkpoint** of RFC 7748 5.2.

---

## 10. How to run it

```sh
./tools/tunnel/run.sh          # all five stages
ONLY=5 ./tools/tunnel/run.sh   # just the kernel stage
./tools/tunnel/vectors.py      # just the test vectors
./tools/tunnel/vectors.py --slow   # and the 1 000 000 round X25519
```

Stages 2, 3 and 5 need root (network namespaces), `wireguard-tools`,
`qemu-system-x86_64` and `gcc`, and say so and skip when they are
missing. Stage 4 finds `tor` if it is installed and reports SKIPPED
rather than passing if it cannot reach the network.
